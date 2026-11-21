-- Experience per hour over the last hour of play, the time, kills and quests to the next level,
-- how the XP came in (kills, quests, the rest), the XP of finished quests in the log, and how
-- long each level took. The session lives in GulliXPCharDB, so a /reload keeps it; a new login
-- starts a new one.

local ADDON, ns = ...
local L = ns.L

local WINDOW = 3600 -- the rate looks at the last hour
local MIN_SPAN = 60 -- and at least a minute, so the first kill does not show a huge rate
-- A gap without XP longer than this is a break (AFK, a talk, a meal): only this much of it
-- counts as play, so a break does not lower the rate or stretch the session.
ns.IDLE = 600
ns.BUCKET = 600 -- the session graph: XP per 10 minutes
ns.LEVELS_KEPT = 60

local function secret(v) return issecretvalue and issecretvalue(v) end

-- Game API wrappers -----------------------------------------------------------------------------

local Q = C_QuestLog or {}

-- The finished quests in the log: { { id, xp } }.
local function finishedQuests()
    local out = {}
    if Q.GetNumQuestLogEntries and Q.GetInfo then
        for i = 1, Q.GetNumQuestLogEntries() or 0 do
            local info = Q.GetInfo(i)
            local id = info and not info.isHeader and info.questID
            if id and Q.IsComplete and Q.IsComplete(id) then
                out[#out + 1] = { id = id, xp = tonumber(GetQuestLogRewardXP and GetQuestLogRewardXP(id)) or 0 }
            end
        end
    elseif GetNumQuestLogEntries and GetQuestLogTitle then
        -- The old log: the reward XP is read for the selected entry.
        local selected = GetQuestLogSelection and GetQuestLogSelection()
        for i = 1, GetNumQuestLogEntries() or 0 do
            local _, _, _, header, _, complete, _, id = GetQuestLogTitle(i)
            if not header and (complete == 1 or complete == true) then
                if SelectQuestLogEntry then SelectQuestLogEntry(i) end
                out[#out + 1] = { id = id or i, xp = tonumber(GetQuestLogRewardXP and GetQuestLogRewardXP()) or 0 }
            end
        end
        if selected and SelectQuestLogEntry then SelectQuestLogEntry(selected) end
    end
    return out
end

-- The watched reputation: name, standing text, value in the standing, its size.
local function watchedFaction()
    local R = C_Reputation
    if R and R.GetWatchedFactionData then
        local d = R.GetWatchedFactionData()
        if d and d.name and d.name ~= "" then
            local lo, hi = d.currentReactionThreshold or 0, d.nextReactionThreshold or 0
            return d.name, _G["FACTION_STANDING_LABEL" .. tostring(d.reaction)] or "",
                (d.currentStanding or 0) - lo, math.max(1, hi - lo)
        end
    end
    if GetWatchedFactionInfo then
        local name, standing, lo, hi, value = GetWatchedFactionInfo()
        if name and name ~= "" then
            return name, _G["FACTION_STANDING_LABEL" .. tostring(standing)] or "",
                (value or 0) - (lo or 0), math.max(1, (hi or 0) - (lo or 0))
        end
    end
end
ns.WatchedFaction = watchedFaction

-- The session -----------------------------------------------------------------------------------

-- Each part of `gained` belongs to one source: killXP + questXP + otherXP == gained (v = 2).
local function newSession(now)
    return { t = now, gained = 0, kills = 0, killXP = 0, quests = 0, questXP = 0, otherXP = 0, v = 2,
             events = {}, active = 0, lastActive = now, buckets = {} }
end

-- A session saved before the sources were measured: the counts of the messages could add up to
-- more than the bar gained, so they are cut to it once.
local function measured(s)
    if s.v == 2 then return end
    s.killXP = math.min(s.killXP or 0, s.gained or 0)
    s.questXP = math.min(s.questXP or 0, (s.gained or 0) - s.killXP)
    s.otherXP = (s.gained or 0) - s.killXP - s.questXP
    s.v = 2
end

-- The level the character is on now: its play time and XP sources, for the level history.
local function newLevel(now)
    local cur = UnitXP("player")
    return { level = UnitLevel("player"), active = 0, kills = 0, killXP = 0, questXP = 0, t = now,
             partial = not secret(cur) and (cur or 0) > 0 }
end

function ns.Start(now)
    now = now or time()
    ns.s = newSession(now)
    ns.pend, ns.loose = {}, nil
    if ns.cdb then ns.cdb.s = ns.s end
    ns.lastXP, ns.lastMax = UnitXP("player"), UnitXPMax("player")
end

-- After a /reload the saved session goes on; after a long break or a new login it starts again.
function ns.Resume(now)
    now = now or time()
    local s = ns.cdb and ns.cdb.s
    if type(s) == "table" and s.t and (now - (s.lastActive or s.t)) <= 2 * ns.IDLE then
        ns.s = s
        s.events, s.buckets = s.events or {}, s.buckets or {}
        s.active, s.lastActive = s.active or 0, s.lastActive or s.t
        measured(s)
        ns.lastXP, ns.lastMax = UnitXP("player"), UnitXPMax("player")
    else
        ns.Start(now)
    end
end

-- Play time since the last gain, capped at a break.
local function step(now, last)
    return math.min(math.max(0, now - (last or now)), ns.IDLE)
end

-- Seconds played in this session, without breaks.
function ns.Active(now)
    now = now or time()
    return ns.s.active + step(now, ns.s.lastActive)
end

-- Where the XP comes from. A kill message and a quest hand-in tell how much they bring, but the
-- game may report more than reaches the bar, and the message may come before or after the bar
-- moves. So a source only takes XP the bar really gained: a message waits in ns.pend until a gain
-- pays it (at most ns.PEND seconds), and a gain no message claimed waits in ns.loose for a
-- message that comes a moment later (ns.LATE). What no message claims is exploring and other XP.
ns.PEND = 60
ns.LATE = 3
ns.pend, ns.loose = {}, nil

local FIELD = { kill = "killXP", quest = "questXP" }

local function credit(kind, xp)
    local s, cur = ns.s, ns.cdb and ns.cdb.cur
    s[FIELD[kind]] = s[FIELD[kind]] + xp
    if cur then cur[FIELD[kind]] = (cur[FIELD[kind]] or 0) + xp end
end

-- A message that brought xp of this kind (kill or quest).
function ns.Claim(kind, xp, now)
    now = now or time()
    local l = ns.loose
    if l and now - l.at <= ns.LATE and l.xp > 0 then
        local take = math.min(xp, l.xp)
        l.xp = l.xp - take
        ns.s.otherXP = ns.s.otherXP - take
        credit(kind, take)
        xp = xp - take
    end
    if xp > 0 then ns.pend[#ns.pend + 1] = { kind = kind, xp = xp, at = now } end
end

-- A gain of the bar: the waiting messages take their share, the rest is other XP.
local function share(delta, now)
    local i = 1
    while ns.pend[i] do
        local p = ns.pend[i]
        if now - p.at > ns.PEND then
            table.remove(ns.pend, i)
        else
            local take = math.min(p.xp, delta)
            if take > 0 then credit(p.kind, take) end
            delta = delta - take
            -- one message is one gain: what the bar did not pay was never XP
            table.remove(ns.pend, i)
            if delta <= 0 then break end
        end
    end
    if delta > 0 then
        ns.s.otherXP = ns.s.otherXP + delta
        if ns.loose and now - ns.loose.at <= ns.LATE then
            ns.loose.xp, ns.loose.at = ns.loose.xp + delta, now
        else
            ns.loose = { xp = delta, at = now }
        end
    end
end

-- Counts what changed since the last update; a level up adds the rest of the old level.
function ns.Update(now)
    now = now or time()
    local cur, max = UnitXP("player"), UnitXPMax("player")
    if secret(cur) or secret(max) then return end
    local delta = cur - ns.lastXP
    if delta < 0 then delta = (ns.lastMax - ns.lastXP) + cur end
    ns.lastXP, ns.lastMax = cur, max
    if delta > 0 then
        local s = ns.s
        local played = step(now, s.lastActive)
        s.active = s.active + played
        s.lastActive = now
        s.gained = s.gained + delta
        table.insert(s.events, { now, delta })
        local b = math.floor((now - s.t) / ns.BUCKET)
        s.buckets[b + 1] = (s.buckets[b + 1] or 0) + delta
        if ns.cdb and ns.cdb.cur then ns.cdb.cur.active = ns.cdb.cur.active + played end
        share(delta, now)
    end
end

-- XP per hour over the last hour of play (or the session, when it is shorter); breaks longer
-- than ns.IDLE count only as ns.IDLE.
function ns.Rate(now)
    now = now or time()
    local events = ns.s.events
    while events[1] and events[1][1] < now - WINDOW do table.remove(events, 1) end
    local from = math.max(now - WINDOW, ns.s.t)
    local sum, span, prev = 0, 0, from
    for _, e in ipairs(events) do
        sum = sum + e[2]
        span = span + step(e[1], prev)
        prev = e[1]
    end
    span = span + step(now, prev)
    return sum * 3600 / math.max(MIN_SPAN, span)
end

-- XP per hour over the whole session: what it gained over the time played, without breaks.
function ns.SessionRate(now)
    return ns.s.gained * 3600 / math.max(MIN_SPAN, ns.Active(now))
end

-- The XP of the finished quests in the log, and how many there are. Cached until the log changes.
function ns.ReadyXP()
    if not ns.ready then
        local sum, n = 0, 0
        for _, q in ipairs(finishedQuests()) do
            sum, n = sum + q.xp, n + 1
        end
        ns.ready = { xp = sum, n = n }
    end
    return ns.ready.xp, ns.ready.n
end

-- Everything the bar and the window show.
function ns.Stats(now)
    now = now or time()
    local cur, max = UnitXP("player"), UnitXPMax("player")
    local left = math.max(0, max - cur)
    local rate = ns.Rate(now)
    local s = ns.s
    local avgKill = s.kills > 0 and s.killXP / s.kills or 0
    local avgQuest = s.quests > 0 and s.questXP / s.quests or 0
    local ready, readyN = ns.ReadyXP()
    return {
        -- avg: the whole session, the big number; rate: the last hour, which the times go by
        avg = ns.SessionRate(now),
        rate = rate,
        left = left,
        toLevel = rate > 0 and math.floor(left / rate * 3600) or nil,
        killsToLevel = avgKill > 0 and math.ceil(left / avgKill) or nil,
        questsToLevel = avgQuest > 0 and math.ceil(left / avgQuest) or nil,
        avgKill = avgKill,
        kills = s.kills, quests = s.quests, killXP = s.killXP, questXP = s.questXP,
        otherXP = s.otherXP or math.max(0, s.gained - s.killXP - s.questXP),
        gained = s.gained, session = ns.Active(now),
        rested = GetXPExhaustion and GetXPExhaustion() or 0,
        percent = max > 0 and math.floor(cur * 100 / max) or 0,
        ready = ready, readyN = readyN,
        -- the session as it stands once the finished quests are handed in
        withReady = s.gained + ready,
        -- Where the level stands after handing in every finished quest.
        readyPercent = max > 0 and math.min(100, math.floor((cur + ready) * 100 / max)) or 0,
        level = UnitLevel("player"), cur = cur, max = max,
    }
end

-- The level history ------------------------------------------------------------------------------

-- A level up: the old level goes into the history with its play time. Returns the entry.
function ns.LevelUp(newLevel_, now)
    now = now or time()
    local cdb = ns.cdb
    if not cdb then return end
    local cur = cdb.cur or newLevel(now)
    local entry = { level = (tonumber(newLevel_) or UnitLevel("player")) - 1, time = cur.active,
                    kills = cur.kills, killXP = cur.killXP, questXP = cur.questXP, at = now,
                    partial = cur.partial or nil }
    cdb.levels = cdb.levels or {}
    table.insert(cdb.levels, 1, entry)
    while #cdb.levels > ns.LEVELS_KEPT do table.remove(cdb.levels) end
    cdb.cur = { level = entry.level + 1, active = 0, kills = 0, killXP = 0, questXP = 0, t = now }
    if not entry.partial and GulliToolkit and GulliToolkit.Notify then
        GulliToolkit.Notify("XP", L.NOTE_LEVEL:format(entry.level + 1, ns.Span(entry.time)))
    end
    return entry
end

-- The last levels, newest first.
function ns.Levels()
    return (ns.cdb and ns.cdb.levels) or {}
end

-- Settings -------------------------------------------------------------------------------------

-- The bar's settings; a new one gets its default here. text: what the bar says (ns.TEXTS).
ns.DEFAULTS = { bar = false, alpha = 100, scale = 100, text = "all", wide = false, rep = true,
                style = "fill" }
ns.TEXTS = { "all", "rate", "eta", "left", "pct" }
-- How the bar looks: filled from end to end, or the old thin line under the text. A new look
-- gets a key here and a STYLE_<KEY> text in every language.
ns.STYLES = { "fill", "line" }
ns.BAR_POINT = { "TOP", 0, -150 }
ns.OPT_ICON = {
    bar = "Interface\\Icons\\INV_Misc_Spyglass_02",
    rep = "Interface\\Icons\\INV_Misc_Note_02",
}

-- Changes one setting and redraws the bar. key "point" with nil puts the bar back in its place.
function ns.SetPref(key, value)
    ns.db[key] = value
    if ns.StyleBar then ns.StyleBar() end
    if ns.Refresh then ns.Refresh() end
end

function ns.Reset()
    for k in pairs(ns.db) do ns.db[k] = nil end
    for k, v in pairs(ns.DEFAULTS) do ns.db[k] = v end
    ns.db.hudHidden = true
    if ns.StyleBar then ns.StyleBar() end
    if ns.Refresh then ns.Refresh() end
end

-- The hub's Unlock mode: the bar shows, even when it is off, and can be dragged.
ns.moving = false
function ns.Move(on)
    ns.moving = on and true or false
    if ns.Refresh then ns.Refresh() end
end

-- The bottom line of the bar: the share of the level done, the XP of finished quests after it
-- and the rested part after that (never past the end of the level).
function ns.BarParts(st)
    local cur, max = UnitXP("player"), UnitXPMax("player")
    if secret(cur) or secret(max) or not max or max <= 0 then return 0, 0, 0 end
    local done = math.min(1, cur / max)
    local ready = math.min(1 - done, (st.ready or 0) / max)
    local rested = math.min(1 - done - ready, (st.rested or 0) / max)
    return done, math.max(0, rested), math.max(0, ready)
end

function ns.MaxLevel()
    return UnitLevel("player") >= (GetMaxPlayerLevel and GetMaxPlayerLevel() or 60)
end

-- "1.2k" for 1234.
function ns.Short(n)
    n = math.floor(n + 0.5)
    if n >= 10000 then return string.format("%dk", math.floor(n / 1000)) end
    if n >= 1000 then return string.format("%.1fk", n / 1000) end
    return tostring(n)
end

function ns.Span(sec)
    sec = math.max(0, math.floor(sec))
    if sec >= 3600 then return L.HM:format(math.floor(sec / 3600), math.floor(sec % 3600 / 60)) end
    return L.M:format(math.max(1, math.floor(sec / 60)))
end

-- The pattern of the client's kill message ("%s dies, you gain %d experience."), with the mob name
-- and the XP as captures. The same event also brings quest and other XP ("You gain 5000
-- experience."), which must never count as a kill.
local killPattern
local function makeKillPattern()
    local fmt = COMBATLOG_XPGAIN_FIRSTPERSON
    if type(fmt) ~= "string" or fmt == "" then fmt = "%s dies, you gain %d experience." end
    local parts, i = {}, 1
    while i <= #fmt do
        local spec, nextI = fmt:match("^(%%%d?%$?[sd])()", i)
        if spec then
            parts[#parts + 1] = spec:sub(-1) == "d" and "(%d+)" or ".+"
            i = nextI
        else
            local c = fmt:sub(i, i)
            if c == "%" and fmt:sub(i + 1, i + 1) == "%" then i = i + 1 end
            parts[#parts + 1] = c:match("%w") and c or ("%" .. c)
            i = i + 1
        end
    end
    -- The bonus variants (rested, group, raid) add to the end, so only the start must match.
    return "^" .. table.concat(parts):gsub("%%%.$", "")
end

-- The XP of a kill message, or nil when the message is not a kill (a quest, exploring, ...).
function ns.KillXP(msg)
    if not msg or secret(msg) then return nil end
    killPattern = killPattern or makeKillPattern()
    return tonumber(msg:match(killPattern))
end

-- One line for the hub's home page.
function ns.Summary()
    if not ns.s then return nil end
    if ns.MaxLevel() then
        local name, standing, v, size = watchedFaction()
        if name then return L.SUM_REP:format(name, standing, math.floor(v * 100 / size)) end
        return nil
    end
    local st = ns.Stats()
    local line
    if st.toLevel then
        line = L.SUM_ETA:format(st.level + 1, ns.Span(st.toLevel), ns.Short(st.rate))
    else
        line = L.SUM_LEFT:format(ns.Short(st.left), st.level + 1)
    end
    if st.readyN > 0 then line = line .. "\n" .. L.SUM_READY:format(ns.Short(st.ready), st.readyN) end
    return line
end

-- Where the session's XP came from, for the hub's tooltip: { { "Kills", "61%" }, ... }.
function ns.SourceRows(st)
    local rows = {}
    if st.gained <= 0 then return rows end
    for _, e in ipairs({ { L.ROW_KILLS, st.killXP }, { L.ROW_QUESTS, st.questXP }, { L.ROW_OTHER, st.otherXP } }) do
        local pct = math.floor(e[2] * 100 / st.gained + 0.5)
        if pct > 0 then rows[#rows + 1] = { e[1], pct .. "%" } end
    end
    return rows
end

-- The session card of the hub's home page: the pace big, when the level comes, a column per
-- ns.BUCKET of the session (the newest ns.SESSION_COLUMNS) and the bar of the level with the
-- rested part. Nothing at the top level.
ns.SESSION_COLUMNS = 12
function ns.Session(now)
    if not ns.s or ns.MaxLevel() then return nil end
    now = now or time()
    local st = ns.Stats(now)
    local last = math.floor(math.max(0, now - ns.s.t) / ns.BUCKET) + 1
    local bars = {}
    for b = math.max(1, last - ns.SESSION_COLUMNS + 1), last do bars[#bars + 1] = ns.s.buckets[b] or 0 end
    local done, rested = ns.BarParts(st)
    return {
        value = ns.Short(st.avg), unit = L.TEXT_RATE,
        line = st.toLevel and L.TO_LEVEL:format(ns.Span(st.toLevel)) or L.SUM_LEFT:format(ns.Short(st.left), st.level + 1),
        span = ns.Span(st.session), bars = bars,
        progress = { value = done, extra = rested, left = st.level, right = st.percent .. "%" },
        -- when XP last came in, so another source leads the card after a while without any
        at = ns.s.gained > 0 and ns.s.lastActive or ns.s.t,
        tile = st.gained > 0 and { value = "+" .. ns.Short(st.gained), label = L.TITLE } or nil,
        facts = st.readyN > 0 and { L.SUM_READY:format(ns.Short(st.ready), st.readyN) } or nil,
        tip = { head = L.TITLE, value = ns.Short(st.gained), rows = ns.SourceRows(st) },
    }
end

-- One line to share in chat (shift-click on the bar).
function ns.ShareText()
    local st = ns.Stats()
    local parts = { L.RATE:format(ns.Short(st.avg)) }
    if st.toLevel then parts[#parts + 1] = L.TO_LEVEL:format(ns.Span(st.toLevel)) end
    parts[#parts + 1] = L.LEFT_SHORT:format(ns.Short(st.left), st.percent)
    return "Gulli XP: " .. L.LEVEL_N:format(st.level) .. ", " .. table.concat(parts, ", ")
end

function ns.Share()
    local text = ns.ShareText()
    if IsInGroup and IsInGroup() and SendChatMessage then
        SendChatMessage(text, (IsInRaid and IsInRaid()) and "RAID" or "PARTY")
    else
        print(text)
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1, a2)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliXPDB = GulliXPDB or {}
        GulliXPCharDB = GulliXPCharDB or {}
        ns.db, ns.cdb = GulliXPDB, GulliXPCharDB
        for k, v in pairs(ns.DEFAULTS) do
            if ns.db[k] == nil then ns.db[k] = v end
        end
        -- Frames on the screen start hidden: older saves hide the bar once.
        if not ns.db.hudHidden then ns.db.bar, ns.db.hudHidden = false, true end
        ns.db.locked = nil
        for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_XP_UPDATE", "CHAT_MSG_COMBAT_XP_GAIN",
                             "QUEST_TURNED_IN", "PLAYER_LEVEL_UP", "QUEST_LOG_UPDATE", "UPDATE_FACTION" }) do
            self:RegisterEvent(e)
        end
        ns.Resume()
        if not ns.cdb.cur or ns.cdb.cur.level ~= UnitLevel("player") then ns.cdb.cur = newLevel(time()) end
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        -- a1: a real login; a2: a /reload, which keeps the session.
        if a1 and not a2 then ns.Start() else ns.lastXP, ns.lastMax = UnitXP("player"), UnitXPMax("player") end
        ns.ready = nil
    elseif event == "PLAYER_XP_UPDATE" then
        ns.Update()
    elseif event == "PLAYER_LEVEL_UP" then
        ns.Update()
        ns.LevelUp(a1)
        if ns.FlashBar then ns.FlashBar() end
    elseif event == "QUEST_LOG_UPDATE" then
        ns.ready = nil
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        local xp = ns.KillXP(a1)
        if xp then
            ns.s.kills = ns.s.kills + 1
            local cur = ns.cdb.cur
            if cur then cur.kills = cur.kills + 1 end
            ns.Claim("kill", xp)
        end
    elseif event == "QUEST_TURNED_IN" then
        local xp = tonumber(a2) or 0
        ns.ready = nil
        if xp > 0 then
            ns.s.quests = ns.s.quests + 1
            ns.Claim("quest", xp)
        end
    end
    if ns.Refresh then ns.Refresh() end
end)

SLASH_GULLIXP1 = "/gxp"
SLASH_GULLIXP2 = "/gullixp"
SlashCmdList.GULLIXP = function(msg)
    if strtrim(msg or ""):lower() == "reset" then ns.Start(); if ns.Refresh then ns.Refresh() end return end
    ns.Toggle()
end

function GulliXP_Toggle() ns.Toggle() end

-- With the hub: its row and button there; alone: its own minimap button (Skin.lua).
do
    local register = GulliToolkit and GulliToolkit.Register or function(info) ns.alone = info end
    register({
        key = "XP",
        icon = "Interface\\AddOns\\Gulli-XP\\icon",
        slash = "/gxp",
        open = function() ns.Toggle() end,
        window = function() return ns.Window and ns.Window() end,
        summary = function() return ns.Summary() end,
        session = function() return ns.Session() end,
        move = function(on) ns.Move(on) end,
        reset = function() ns.Reset() end,
        frames = { { key = "bar", icon = ns.OPT_ICON.bar,
                     get = function() return ns.db ~= nil and ns.db.bar == true end,
                     set = function(v) ns.SetPref("bar", v) end,
                     frame = function() return ns.BarFrame and ns.BarFrame() end } },
        options = {
            { label = ns.L.OPT_REP, icon = ns.OPT_ICON.rep, tip = ns.L.OPT_REP_TIP,
              get = function() return ns.db ~= nil and ns.db.rep == true end, set = function(v) ns.SetPref("rep", v) end },
        },
    })
end
