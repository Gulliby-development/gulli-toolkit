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

local function newSession(now)
    return { t = now, gained = 0, kills = 0, killXP = 0, quests = 0, questXP = 0, events = {},
             active = 0, lastActive = now, buckets = {} }
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
        rate = rate,
        left = left,
        toLevel = rate > 0 and math.floor(left / rate * 3600) or nil,
        killsToLevel = avgKill > 0 and math.ceil(left / avgKill) or nil,
        questsToLevel = avgQuest > 0 and math.ceil(left / avgQuest) or nil,
        avgKill = avgKill,
        kills = s.kills, quests = s.quests, killXP = s.killXP, questXP = s.questXP,
        otherXP = math.max(0, s.gained - s.killXP - s.questXP),
        gained = s.gained, session = ns.Active(now),
        rested = GetXPExhaustion and GetXPExhaustion() or 0,
        percent = max > 0 and math.floor(cur * 100 / max) or 0,
        ready = ready, readyN = readyN,
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
ns.DEFAULTS = { bar = true, locked = false, alpha = 100, scale = 100, text = "all", wide = false, rep = true,
                style = "fill" }
ns.TEXTS = { "all", "rate", "eta", "left", "pct" }
-- How the bar looks: filled from end to end, or the old thin line under the text. A new look
-- gets a key here and a STYLE_<KEY> text in every language.
ns.STYLES = { "fill", "line" }
ns.BAR_POINT = { "TOP", 0, -150 }
ns.OPT_ICON = {
    bar = "Interface\\Icons\\INV_Misc_Spyglass_02",
    locked = "Interface\\Icons\\INV_Misc_Key_04",
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
    if ns.StyleBar then ns.StyleBar() end
    if ns.Refresh then ns.Refresh() end
end

-- /gulli move: the bar shows and follows the mouse until it is locked again.
ns.moving = false
function ns.Move(on)
    ns.moving = on and true or false
    if ns.Refresh then ns.Refresh() end
end

function ns.Locked()
    return ns.db.locked and not ns.moving
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

-- The XP number of a kill message: the first number in it ("Boar dies, you gain 45 experience").
function ns.KillXP(msg)
    if not msg or secret(msg) then return nil end
    return tonumber(msg:match("(%d+)"))
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

-- One line to share in chat (shift-click on the bar).
function ns.ShareText()
    local st = ns.Stats()
    local parts = { L.RATE:format(ns.Short(st.rate)) }
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
    elseif event == "QUEST_LOG_UPDATE" then
        ns.ready = nil
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        local xp = ns.KillXP(a1)
        if xp then
            ns.s.kills = ns.s.kills + 1
            ns.s.killXP = ns.s.killXP + xp
            local cur = ns.cdb.cur
            if cur then cur.kills, cur.killXP = cur.kills + 1, cur.killXP + xp end
        end
    elseif event == "QUEST_TURNED_IN" then
        local xp = tonumber(a2) or 0
        ns.ready = nil
        if xp > 0 then
            ns.s.quests = ns.s.quests + 1
            ns.s.questXP = ns.s.questXP + xp
            local cur = ns.cdb.cur
            if cur then cur.questXP = cur.questXP + xp end
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

if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({
        key = "XP",
        icon = "Interface\\AddOns\\Gulli-XP\\icon",
        slash = "/gxp",
        open = function() ns.Toggle() end,
        window = function() return ns.Window and ns.Window() end,
        summary = function() return ns.Summary() end,
        move = function(on) ns.Move(on) end,
        reset = function() ns.Reset() end,
        options = {
            { label = ns.L.OPT_BAR, icon = ns.OPT_ICON.bar, tip = ns.L.OPT_BAR_TIP,
              get = function() return ns.db ~= nil and ns.db.bar == true end, set = function(v) ns.SetPref("bar", v) end },
            { label = ns.L.OPT_LOCK, icon = ns.OPT_ICON.locked, tip = ns.L.OPT_LOCK_D,
              get = function() return ns.db ~= nil and ns.db.locked == true end, set = function(v) ns.SetPref("locked", v) end },
            { label = ns.L.OPT_REP, icon = ns.OPT_ICON.rep, tip = ns.L.OPT_REP_TIP,
              get = function() return ns.db ~= nil and ns.db.rep == true end, set = function(v) ns.SetPref("rep", v) end },
        },
    })
end
