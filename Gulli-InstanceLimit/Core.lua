-- Counts dungeon entries per hour for the whole account, like the game does, and says when
-- the next entry is free. The limit is not a setting: it is 5 until the game shows another. Entering the same dungeon again does not count
-- until it was reset or the group changed. Group members with the addon share resets and
-- what they have left over addon messages (prefix GulliIL).

local ADDON, ns = ...
local L = ns.L

ns.HOUR, ns.DAY = 3600, 86400
ns.DEFAULT_LIMIT = 5
ns.PREFIX = "GulliIL"
-- The counter on screen: always, only in a group or a dungeon (or when an entry is short), or never.
ns.BADGE_MODES = { "ALWAYS", "GROUP", "HIDDEN" }

-- Game API wrappers.
local function inInstance() return IsInInstance() end
local function instanceInfo()
    local name, kind, _, _, _, _, _, mapID = GetInstanceInfo()
    return name, kind, mapID
end
local function inGroup() return IsInGroup and IsInGroup() or false end
local function money() return GetMoney and GetMoney() or 0 end
local function xp() return UnitXP and UnitXP("player") or 0, UnitXPMax and UnitXPMax("player") or 0 end
local function secret(v) return issecretvalue and issecretvalue(v) end
local function sendAddon(text, channel, target)
    local send = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
    if send then send(ns.PREFIX, text, channel, target) end
end
local function groupChannel() return (IsInRaid and IsInRaid()) and "RAID" or "PARTY" end

local function say(msg) print("|cff9ad0ffGulli Instance Limit|r: " .. msg) end
local function notify(msg)
    if GulliToolkit and GulliToolkit.Notify then GulliToolkit.Notify("InstanceLimit", msg) end
end
local function ring()
    if ns.db.sound and PlaySound then PlaySound((SOUNDKIT and SOUNDKIT.READY_CHECK) or 8960) end
end

function ns.Clock(sec)
    sec = math.max(0, math.floor(sec))
    local f = math.floor
    if sec >= 3600 then return string.format("%d:%02d:%02d", f(sec / 3600), f((sec % 3600) / 60), sec % 60) end
    return string.format("%d:%02d", f(sec / 60), sec % 60)
end

-- Drops entries older than a day (the list shows a day); returns the entries of the last
-- hour, oldest first: each holds a slot of the hour until an hour after it.
function ns.Counts(now)
    now = now or time()
    local db = ns.db
    for i = #db.entries, 1, -1 do
        if now - db.entries[i].t >= ns.DAY then table.remove(db.entries, i) end
    end
    local used = {}
    for _, e in ipairs(db.entries) do
        if now - e.t < ns.HOUR then used[#used + 1] = e end
    end
    table.sort(used, function(a, b) return a.t < b.t end)
    return used
end

-- How many entries are left, and in how many seconds the next one is free (0 = now).
-- nextFree: when the oldest entry of the hour stops counting (0 = none counts).
function ns.Status(now)
    now = now or time()
    local used = ns.Counts(now)
    local limit = ns.db.limit
    local hour = #used
    local left = math.max(0, limit - hour)
    local wait = 0
    -- The slots free one by one; the one that brings us under the limit.
    if left == 0 and hour > 0 then wait = used[hour - limit + 1].t + ns.HOUR - now end
    return { hour = hour, leftHour = left, left = left, wait = wait, limit = limit,
             nextFree = hour > 0 and (used[1].t + ns.HOUR - now) or 0 }
end

-- The slots of the hour for the window: the used ones first, the one that frees first on top
-- ({ name, free = seconds until it frees, frac = the share of its hour left }), then the free ones.
function ns.Slots(now)
    now = now or time()
    local used = ns.Counts(now)
    local out = {}
    for i, e in ipairs(used) do
        local free = e.t + ns.HOUR - now
        out[i] = { name = e.name, free = free, frac = free / ns.HOUR, first = i == 1 }
    end
    for i = #used + 1, ns.db.limit do out[i] = { isFree = true } end
    return out
end

-- Warnings after an entry: at the limit, and at the chosen number of entries left.
local function warn(s)
    if s.left == 0 then
        local msg = L.WARN_NONE:format(ns.Clock(math.max(s.wait, 0)))
        say(msg); notify(msg); ring()
    elseif s.leftHour <= ns.db.warnAt then
        local msg = L.WARN_LEFT:format(s.leftHour)
        say(msg); notify(msg)
    end
end

-- Run stats: what the player got inside, kept on the entry. A run that goes on (back in
-- after leaving) keeps its kills and adds to the XP and money it had.
local function startRun(e, goesOn)
    local cur, max = xp()
    e.money0, e.xp0, e.xpMax0 = money(), cur, max
    if goesOn then
        e.xpBase, e.moneyBase = e.xp or 0, e.money or 0
        e.kills = e.kills or 0
    else
        e.kills = 0
    end
end

local function endRun(e, now)
    if e.out then return end
    e.out = now
    e.secs = now - e.t
    e.money = money() - (e.money0 or money())
    local cur = xp()
    local gained = cur - (e.xp0 or cur)
    if gained < 0 then gained = gained + (e.xpMax0 or 0) end -- a level up inside
    e.xp = gained + (e.xpBase or 0)
    e.money = e.money + (e.moneyBase or 0)
    e.money0, e.xp0, e.xpMax0, e.xpBase, e.moneyBase = nil, nil, nil, nil, nil
    if ns.db.summary then say(L.SUMMARY:format(e.name or "?", ns.RunText(e))) end
end

-- "12:30 · 3400 XP · 1g 20s · 25 kills" for a finished run, each part in its own colour.
function ns.RunText(e)
    local S = ns.Skin
    local function paint(color, text) return (S and S.Hex and color) and (S.Hex(color) .. text .. "|r") or text end
    local parts = { paint(S and S.TIME, ns.Clock(e.secs or 0)) }
    if (e.xp or 0) > 0 then parts[#parts + 1] = paint(S and S.XP, L.RUN_XP:format(e.xp)) end
    local m = e.money or 0
    if m ~= 0 then
        parts[#parts + 1] = (S and S.MoneyText) and S.MoneyText(m) or (math.floor(m / 100) / 100 .. "g")
    end
    if (e.kills or 0) > 0 then parts[#parts + 1] = paint(S and S.KILLS, L.RUN_KILLS:format(e.kills)) end
    return table.concat(parts, (S and S.DOT) or ", ")
end

local function current()
    if not ns.inside then return nil end
    for i = #ns.db.entries, 1, -1 do
        local e = ns.db.entries[i]
        if e.map == ns.inside then return e end
    end
end

-- The client's kill message ("%s dies, you gain %d experience.") as a pattern. The same event
-- also brings quest XP ("You gain 4200 experience."), which is no kill.
local killPattern
local function makeKillPattern()
    local fmt = COMBATLOG_XPGAIN_FIRSTPERSON
    if type(fmt) ~= "string" or fmt == "" then fmt = "%s dies, you gain %d experience." end
    local parts, i = {}, 1
    while i <= #fmt do
        local spec, nextI = fmt:match("^(%%%d?%$?[sd])()", i)
        if spec then
            parts[#parts + 1] = spec:sub(-1) == "d" and "%d+" or ".+"
            i = nextI
        else
            local c = fmt:sub(i, i)
            if c == "%" and fmt:sub(i + 1, i + 1) == "%" then i = i + 1 end
            parts[#parts + 1] = c:match("%w") and c or ("%" .. c)
            i = i + 1
        end
    end
    return "^" .. table.concat(parts):gsub("%%%.$", "")
end

function ns.IsKill(msg)
    if type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then return false end
    killPattern = killPattern or makeKillPattern()
    return msg:match(killPattern) ~= nil
end

function ns.Killed(msg)
    if msg ~= nil and not ns.IsKill(msg) then return end
    local e = current()
    if e and not e.out then e.kills = (e.kills or 0) + 1 end
end

-- Called when the player is in a new place. Returns true when an entry was counted.
function ns.Entered(name, kind, mapID, now)
    now = now or time()
    if kind ~= "party" and kind ~= "raid" then
        local e = current()
        if e then endRun(e, now) end
        ns.inside = nil
        ns.Share()
        return false
    end
    local db = ns.db
    if ns.inside == mapID then return false end
    ns.inside = mapID
    -- An unused copy of a dungeon goes away after a while; after an hour we count it again.
    local opened = db.open[mapID]
    if opened and (opened == true or now - opened < ns.HOUR) then
        -- Back in the same copy: the run goes on. After a /reload inside it never stopped,
        -- so its kills and the start values stay as they are.
        local e = current()
        if e and e.out then
            e.out = nil
            startRun(e, true)
        elseif e and not e.xp0 then
            startRun(e, true)
        end
        return false
    end
    db.open[mapID] = now
    local _, class = UnitClass("player")
    local e = { t = now, name = name, map = mapID, char = UnitName("player"), class = class }
    startRun(e)
    table.insert(db.entries, e)
    local s = ns.Status(now)
    -- We got in more often than the limit says: the real limit is higher.
    if s.hour > db.limit then
        db.limit = s.hour
        say(L.LEARNED_UP:format(s.hour))
        s = ns.Status(now)
    end
    warn(s)
    ns.Share()
    if ns.Refresh then ns.Refresh() end
    return true
end

-- A reset or a new group gives a new copy of the dungeon: entering it counts again.
function ns.Reopen(name)
    if not name then wipe(ns.db.open); return end
    for _, e in ipairs(ns.db.entries) do
        if e.name == name then ns.db.open[e.map] = nil end
    end
end

-- The game says it refused a dungeon: the real limit is what we counted this hour.
function ns.Refused(now)
    local s = ns.Status(now)
    if s.hour > 0 and s.hour < ns.db.limit then
        ns.db.limit = s.hour
        say(L.LEARNED:format(s.hour))
    end
end

-- Every setting back to its default; the counted entries stay.
function ns.ResetSettings()
    for _, k in ipairs({ "badgeMode", "badgeWas", "badgeScale", "badgeAlpha", "badgePoint", "warnAt", "freeAlert",
                         "sound", "summary", "tellGroup", "sync" }) do ns.db[k] = nil end
    ns.db.limit = ns.DEFAULT_LIMIT
    ns.Defaults()
    if ns.Refresh then ns.Refresh() end
end

-- Watches the counter: when no entry was free and one frees, says so once.
function ns.Tick(now)
    local s = ns.Status(now)
    if ns.lastLeft == 0 and s.left > 0 and ns.db.freeAlert then
        say(L.FREE); notify(L.FREE); ring()
        if ns.ShowFree then ns.ShowFree(s) end
    end
    if ns.lastLeft ~= s.left then
        ns.lastLeft = s.left
        ns.Share()
    end
    return s
end

---- The group ---------------------------------------------------------------------------------

-- Members still inside a dungeon: the game gives no position for a unit in another instance.
function ns.StillInside()
    local out = {}
    if not inGroup() or not UnitPosition then return out end
    local raid = IsInRaid and IsInRaid()
    local n = (GetNumGroupMembers and GetNumGroupMembers() or 0)
    for i = 1, raid and n or n - 1 do
        local unit = (raid and "raid" or "party") .. i
        if UnitExists(unit) and not UnitIsUnit(unit, "player") and UnitIsConnected(unit) then
            local name = UnitName(unit)
            if UnitPosition(unit) == nil and not (issecretvalue and issecretvalue(name)) then out[#out + 1] = name end
        end
    end
    return out
end

function ns.CanReset()
    if inInstance() then return false end
    if inGroup() then return UnitIsGroupLeader and UnitIsGroupLeader("player") or false end
    return true
end

-- Reset: when members may still be inside, the first press only asks to press again.
function ns.Reset(now)
    now = now or time()
    if not ns.CanReset() or not ResetInstances then return false end
    local inside = ns.StillInside()
    if #inside > 0 and not (ns.confirmAt and now - ns.confirmAt < 10) then
        ns.confirmAt = now
        ns.insideNames = inside
        if ns.Refresh then ns.Refresh() end
        return "ask"
    end
    ns.confirmAt, ns.insideNames = nil, nil
    ns.resetting = now
    ResetInstances()
    return true
end

-- Messages: "RESET\t<dungeon>" from the leader, "STATE\t<hour left>\t<day left>\t<wait>" and
-- "HELLO" (asks the others for their STATE). New types may come; old ones never change: the
-- day field stays in STATE, sent as NO_DAY (no day limit) and not read.
function ns.Share()
    if not ns.db or not ns.db.sync or not inGroup() then return end
    local s = ns.Status()
    sendAddon(string.format("STATE\t%d\t%d\t%d", s.leftHour, ns.NO_DAY, math.floor(s.wait)), groupChannel())
end

ns.NO_DAY = 99
ns.group = {}
function ns.Receive(prefix, text, sender, now)
    if prefix ~= ns.PREFIX or not ns.db.sync or secret(text) or secret(sender) or type(text) ~= "string" then return end
    now = now or time()
    local who = (sender or ""):match("^[^-]+") or sender
    if who == UnitName("player") then return end
    local kind, a, _, c = strsplit("\t", text)
    if kind == "RESET" and a then
        ns.Reopen(a)
        say(L.GROUP_RESET:format(who, a))
    elseif kind == "STATE" then
        ns.group[who] = { leftHour = tonumber(a) or 0, wait = tonumber(c) or 0, t = now }
    elseif kind == "HELLO" then
        ns.Share()
    end
    if ns.Refresh then ns.Refresh() end
end

-- The group for the window: the members who share their counter, the fewest left first
-- ({ name, class, left, wait }), then the ones without the addon ({ name, class, none = true }).
function ns.GroupList(now)
    now = now or time()
    local out, seen = {}, {}
    local function add(name, class)
        local g = ns.group[name]
        seen[name] = true
        if not g then out[#out + 1] = { name = name, class = class, none = true }; return end
        local wait = math.max(0, g.wait - (now - g.t))
        local left = g.leftHour
        if left == 0 and wait == 0 then left = 1 end
        out[#out + 1] = { name = name, class = class, left = left, wait = wait }
    end
    if inGroup() then
        local raid = IsInRaid and IsInRaid()
        local n = GetNumGroupMembers and GetNumGroupMembers() or 0
        for i = 1, raid and n or n - 1 do
            local unit = (raid and "raid" or "party") .. i
            if UnitExists(unit) and not UnitIsUnit(unit, "player") then
                local name = UnitName(unit)
                if name and not secret(name) then
                    local _, class = UnitClass(unit)
                    add(name, not secret(class) and class or nil)
                end
            end
        end
    end
    -- A sender the roster did not name (a hidden name) still counts.
    for who in pairs(ns.group) do if not seen[who] then add(who) end end
    table.sort(out, function(x, y)
        if (x.none or false) ~= (y.none or false) then return y.none or false end
        if not x.none and x.left ~= y.left then return x.left < y.left end
        return x.name < y.name
    end)
    return out
end

---- Events --------------------------------------------------------------------------------------

local resetPattern, refusedText
local function patterns()
    if resetPattern then return end
    local s = INSTANCE_RESET_SUCCESS or "%s has been reset."
    resetPattern = "^" .. s:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%s", "(.+)") .. "$"
    refusedText = TRANSFER_ABORT_TOO_MANY_INSTANCES or "You have entered too many instances recently."
end

function ns.System(msg)
    if type(msg) ~= "string" then return end
    patterns()
    local name = msg:match(resetPattern)
    if name then
        ns.Reopen(name)
        -- Our own reset: tell the group, in chat and to their addons.
        if ns.resetting and time() - ns.resetting < 10 and inGroup() then
            if ns.db.tellGroup and SendChatMessage then SendChatMessage(L.RESET_SAY:format(name), groupChannel()) end
            if ns.db.sync then sendAddon("RESET\t" .. name, groupChannel()) end
        end
    end
    if msg == refusedText then ns.Refused() end
end

ns.DEFAULTS = { badgeMode = "HIDDEN", badgeScale = 100, badgeAlpha = 100, warnAt = 1,
                freeAlert = true, sound = true, summary = true, tellGroup = true, sync = true }
-- Settings of older versions that are gone: the limits are not the player's to set, there is no
-- day limit in WoW Forever that anyone confirmed, and an entry counts from the entry.
local GONE = { "dayLimit", "warnDayAt", "fromExit", "confirmed" }
function ns.Defaults()
    for k, v in pairs(ns.DEFAULTS) do if ns.db[k] == nil then ns.db[k] = v end end
    -- Frames on the screen start hidden (owner's decision): a counter shown before is hidden
    -- once; the hub's Unlock mode or the Show choice brings it back. The per-frame lock is gone.
    if not ns.db.hudHidden then
        if ns.db.badgeMode ~= "HIDDEN" then ns.db.badgeWas, ns.db.badgeMode = ns.db.badgeMode, "HIDDEN" end
        ns.db.hudHidden = true
    end
    ns.db.badgeLocked = nil
    -- A limit typed in by hand goes back to 5 once; one the game showed stays.
    if not ns.db.limitFixed then
        if not ns.db.confirmed then ns.db.limit = ns.DEFAULT_LIMIT end
        ns.db.limitFixed = true
    end
    for _, k in ipairs(GONE) do ns.db[k] = nil end
end

-- The counter on or off for the hub's Unlock mode; on brings back the last Show choice.
function ns.BadgeOn() return ns.db ~= nil and ns.db.badgeMode ~= "HIDDEN" end
function ns.SetBadgeOn(on)
    if not ns.db or on == ns.BadgeOn() then return end
    if on then
        ns.db.badgeMode, ns.db.badgeWas = ns.db.badgeWas or "ALWAYS", nil
    else
        ns.db.badgeWas, ns.db.badgeMode = ns.db.badgeMode, "HIDDEN"
    end
    if ns.Refresh then ns.Refresh() end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1, a2, a3, a4)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliInstanceLimitDB = GulliInstanceLimitDB or {}
        ns.db = GulliInstanceLimitDB
        local db = ns.db
        db.entries = db.entries or {}
        db.open = db.open or {}
        db.limit = db.limit or ns.DEFAULT_LIMIT
        -- The old on/off counter switch becomes a mode.
        if db.badgeMode == nil then db.badgeMode = (db.badge == false) and "HIDDEN" or "ALWAYS" end
        db.badge = nil
        ns.Defaults()
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(ns.PREFIX) end
        if ns.SetupBadge then ns.SetupBadge() end
        for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "CHAT_MSG_SYSTEM",
                             "UI_ERROR_MESSAGE", "GROUP_LEFT", "GROUP_JOINED", "CHAT_MSG_ADDON",
                             "CHAT_MSG_COMBAT_XP_GAIN", "GROUP_ROSTER_UPDATE", "PLAYER_LOGOUT" }) do
            self:RegisterEvent(e)
        end
        ns.lastLeft = ns.Status().left
        if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(5, function() ns.Tick() end) end
        return
    end
    if event == "PLAYER_LOGOUT" then
        ns.db.seenAt = time()
        return
    end
    if event == "CHAT_MSG_SYSTEM" then
        ns.System(a1)
    elseif event == "UI_ERROR_MESSAGE" then
        ns.System(a2)
    elseif event == "CHAT_MSG_ADDON" then
        ns.Receive(a1, a2, a4)
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        ns.Killed(a1)
    elseif event == "GROUP_ROSTER_UPDATE" then
        if not inGroup() then wipe(ns.group) end
    elseif event == "GROUP_LEFT" or event == "GROUP_JOINED" then
        ns.Reopen()
        wipe(ns.group)
        if event == "GROUP_JOINED" and ns.db.sync then sendAddon("HELLO", groupChannel()); ns.Share() end
    else
        -- a1: a real login, a2: a /reload. Only leaving the game starts a new session for the
        -- hub's card.
        if event == "PLAYER_ENTERING_WORLD"
            and (ns.Skin.NewSession(a1, a2, ns.db.seenAt) or not ns.db.sessionAt) then
            ns.db.sessionAt = time()
        end
        local name, kind, mapID = instanceInfo()
        ns.Entered(name, kind, mapID)
    end
    if ns.Refresh then ns.Refresh() end
end)

-- The hub's session card: the runs of this character since the login. The number of runs with
-- their mean length, a column per run, and the run that still goes on.
ns.SESSION_ICON = "Interface\\Icons\\INV_Misc_Key_03"
function ns.Session(now)
    local db = ns.db
    if not db or not db.sessionAt then return nil end
    now = now or time()
    local me = UnitName("player")
    local runs, bars, rows, sum, done, last, open = 0, {}, {}, 0, 0, nil, nil
    for _, e in ipairs(db.entries) do
        if e.t >= db.sessionAt and e.char == me then
            runs = runs + 1
            local secs = e.out and (e.secs or 0) or math.max(0, now - e.t)
            bars[#bars + 1] = secs
            rows[#rows + 1] = { e.name or "?", ns.Clock(secs) }
            if e.out then sum, done = sum + secs, done + 1 else open = e end
            last = math.max(last or 0, e.out or now)
        end
    end
    if runs == 0 then return nil end
    local parts = {}
    if done > 0 then parts[#parts + 1] = L.SES_AVG:format(ns.Clock(sum / done)) end
    if open then parts[#parts + 1] = L.SES_NOW:format(open.name or "?", ns.Clock(now - open.t)) end
    return { value = runs, unit = L.SES_DUNGEONS, line = table.concat(parts, ", "), bars = bars, at = last,
             tile = { icon = ns.SESSION_ICON, value = runs, label = L.SES_DUNGEONS },
             tip = { icon = ns.SESSION_ICON, head = L.SES_DUNGEONS, value = runs, rows = rows } }
end

SLASH_GULLIINSTANCELIMIT1 = "/gil"
SLASH_GULLIINSTANCELIMIT2 = "/gulliinstancelimit"
SlashCmdList.GULLIINSTANCELIMIT = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "status" then
        local s = ns.Status()
        say(L.LEFT_HOUR:format(s.leftHour, ns.db.limit) .. ". " ..
            (s.wait > 0 and L.NEXT_FREE:format(ns.Clock(s.wait)) or L.ALL_FREE))
    else
        ns.Toggle()
    end
end

function GulliInstanceLimit_Toggle() ns.Toggle() end

-- The game icon of each switch the hub shows.
ns.OPT_ICON = {
    freeAlert = "Interface\\Icons\\INV_Misc_Bell_01",
    sync = "Interface\\Icons\\Spell_Holy_PrayerOfSpirit",
}

local function option(key, label)
    return { label = label, icon = ns.OPT_ICON[key], get = function() return ns.db ~= nil and ns.db[key] == true end,
             set = function(on) if ns.db then ns.db[key] = on and true or false end end }
end

-- With the hub: its row and button there; alone: its own minimap button (Skin.lua).
do
    local register = GulliToolkit and GulliToolkit.Register or function(info) ns.alone = info end
    register({
        key = "InstanceLimit",
        icon = "Interface\\AddOns\\Gulli-InstanceLimit\\icon",
        slash = "/gil",
        open = function() ns.Toggle() end,
        window = function() return ns.Window and ns.Window() end,
        options = { option("freeAlert", ns.L.OPT_FREE), option("sync", ns.L.OPT_SYNC) },
        -- The hub's home page: entries left, or when the next one frees.
        summary = function()
            if not ns.db then return nil end
            local s = ns.Status()
            -- the third value is for the hub's tile: a pip per entry of the hour, red when none is left
            if s.left == 0 then
                return L.SUM_WAIT:format(ns.Clock(s.wait)), "Interface\\Icons\\Spell_Nature_TimeStop", { tone = "bad" }
            end
            return L.SUM_LEFT:format(s.leftHour, ns.db.limit), "Interface\\Icons\\INV_Misc_PocketWatch_01",
                { pips = { s.leftHour, ns.db.limit }, tone = s.leftHour <= 1 and "warn" or "good" }
        end,
        session = function() return ns.Session() end,
        move = function(on) if ns.MoveBadge then ns.MoveBadge(on) end end,
        frames = { { key = "badge", label = ns.L.TITLE, icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
                     get = function() return ns.BadgeOn() end, set = function(v) ns.SetBadgeOn(v) end,
                     frame = function() return ns.BadgeFrame and ns.BadgeFrame() end } },
        reset = function() ns.ResetSettings() end,
    })
end
