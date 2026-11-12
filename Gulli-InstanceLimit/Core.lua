-- Counts dungeon entries per hour and per day for the whole account, like the game does,
-- and says when the next entry is free. Entering the same dungeon again does not count
-- until it was reset or the group changed. Group members with the addon share resets and
-- what they have left over addon messages (prefix GulliIL).

local ADDON, ns = ...
local L = ns.L

ns.HOUR, ns.DAY = 3600, 86400
ns.DEFAULT_LIMIT, ns.DEFAULT_DAY = 5, 30
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

-- The time an entry counts from: the entry, or with "count from the exit" the exit (an entry
-- the player is still inside counts as now).
function ns.When(e, now)
    if ns.db.fromExit then return e.out or now or time() end
    return e.t
end

-- Drops entries older than a day; returns entries in the last hour and day.
function ns.Counts(now)
    now = now or time()
    local db = ns.db
    for i = #db.entries, 1, -1 do
        if now - ns.When(db.entries[i], now) >= ns.DAY then table.remove(db.entries, i) end
    end
    local hour, day = 0, #db.entries
    local oldestHour, oldestDay
    for _, e in ipairs(db.entries) do
        local t = ns.When(e, now)
        if now - t < ns.HOUR then
            hour = hour + 1
            if not oldestHour or t < oldestHour then oldestHour = t end
        end
        if not oldestDay or t < oldestDay then oldestDay = t end
    end
    return hour, day, oldestHour, oldestDay
end

-- How many entries are left, and in how many seconds the next one is free (0 = now).
-- by: "HOUR" or "DAY", the limit that blocks now (the one that frees last).
function ns.Status(now)
    now = now or time()
    local hour, day, oldestHour, oldestDay = ns.Counts(now)
    local db = ns.db
    local leftHour = math.max(0, db.limit - hour)
    local leftDay = math.max(0, db.dayLimit - day)
    local waitHour, waitDay = 0, 0
    if leftHour == 0 and oldestHour then
        -- The slot of the oldest entries frees one by one; the one that brings us under the limit.
        local times = {}
        for _, e in ipairs(db.entries) do
            local t = ns.When(e, now)
            if now - t < ns.HOUR then times[#times + 1] = t end
        end
        table.sort(times)
        waitHour = times[hour - db.limit + 1] + ns.HOUR - now
    end
    if leftDay == 0 and oldestDay then waitDay = oldestDay + ns.DAY - now end
    local by
    if leftHour == 0 or leftDay == 0 then by = waitDay > waitHour and "DAY" or "HOUR" end
    return { hour = hour, day = day, leftHour = leftHour, leftDay = leftDay, wait = math.max(waitHour, waitDay),
             waitHour = waitHour, waitDay = waitDay, left = math.min(leftHour, leftDay), by = by }
end

-- Warnings after an entry: at the limit, and at the chosen number of entries left.
local function warn(s)
    if s.left == 0 then
        local msg = L.WARN_NONE:format(ns.Clock(math.max(s.wait, 0)))
        say(msg); notify(msg); ring()
    elseif s.leftHour <= ns.db.warnAt then
        local msg = L.WARN_LEFT:format(s.leftHour)
        say(msg); notify(msg)
    elseif s.leftDay <= ns.db.warnDayAt then
        local msg = L.WARN_DAY:format(s.leftDay)
        say(msg); notify(msg)
    end
end

-- Run stats: what the player got inside, kept on the entry.
local function startRun(e)
    local cur, max = xp()
    e.money0, e.xp0, e.xpMax0, e.kills = money(), cur, max, 0
end

local function endRun(e, now)
    if e.out then return end
    e.out = now
    e.secs = now - e.t
    e.money = money() - (e.money0 or money())
    local cur = xp()
    local gained = cur - (e.xp0 or cur)
    if gained < 0 then gained = gained + (e.xpMax0 or 0) end -- a level up inside
    e.xp = gained
    e.money0, e.xp0, e.xpMax0 = nil, nil, nil
    if ns.db.summary then say(L.SUMMARY:format(e.name or "?", ns.RunText(e))) end
end

-- "12:30, 3400 XP, 1g 20s, 25 kills" for a finished run.
function ns.RunText(e)
    local parts = { ns.Clock(e.secs or 0) }
    if (e.xp or 0) > 0 then parts[#parts + 1] = L.RUN_XP:format(e.xp) end
    local m = e.money or 0
    if m ~= 0 then
        parts[#parts + 1] = (GetCoinTextureString and GetCoinTextureString(math.abs(m)) or (math.floor(m / 100) / 100 .. "g"))
    end
    if (e.kills or 0) > 0 then parts[#parts + 1] = L.RUN_KILLS:format(e.kills) end
    return table.concat(parts, ", ")
end

local function current()
    if not ns.inside then return nil end
    for i = #ns.db.entries, 1, -1 do
        local e = ns.db.entries[i]
        if e.map == ns.inside then return e end
    end
end

function ns.Killed()
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
        local e = current()
        if e then e.out = nil; startRun(e) end
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
    ns.db.confirmed = true
    if s.hour > 0 and s.hour < ns.db.limit then
        ns.db.limit = s.hour
        say(L.LEARNED:format(s.hour))
    end
end

-- Every setting back to its default; the counted entries stay.
function ns.ResetSettings()
    for _, k in ipairs({ "badgeMode", "badgeScale", "badgeAlpha", "badgePoint", "warnAt", "warnDayAt", "freeAlert",
                         "sound", "summary", "tellGroup", "sync", "fromExit" }) do ns.db[k] = nil end
    ns.Defaults()
    ns.DefaultLimits()
end

function ns.DefaultLimits()
    ns.db.limit, ns.db.dayLimit, ns.db.confirmed = ns.DEFAULT_LIMIT, ns.DEFAULT_DAY, false
    if ns.Refresh then ns.Refresh() end
end

-- "5" when the game confirmed the limit, "≈5" while it is our guess.
function ns.LimitText(n)
    return (ns.db.confirmed and "" or "≈") .. n
end

-- Watches the counter: when no entry was free and one frees, says so once.
function ns.Tick(now)
    local s = ns.Status(now)
    if ns.lastLeft == 0 and s.left > 0 and ns.db.freeAlert then
        say(L.FREE); notify(L.FREE); ring()
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
            if UnitPosition(unit) == nil then out[#out + 1] = UnitName(unit) end
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
-- "HELLO" (asks the others for their STATE). New types may come; old ones never change.
function ns.Share()
    if not ns.db or not ns.db.sync or not inGroup() then return end
    local s = ns.Status()
    sendAddon(string.format("STATE\t%d\t%d\t%d", s.leftHour, s.leftDay, math.floor(s.wait)), groupChannel())
end

ns.group = {}
function ns.Receive(prefix, text, sender, now)
    if prefix ~= ns.PREFIX or not ns.db.sync or secret(text) or secret(sender) or type(text) ~= "string" then return end
    now = now or time()
    local who = (sender or ""):match("^[^-]+") or sender
    if who == UnitName("player") then return end
    local kind, a, b, c = strsplit("\t", text)
    if kind == "RESET" and a then
        ns.Reopen(a)
        say(L.GROUP_RESET:format(who, a))
    elseif kind == "STATE" then
        ns.group[who] = { leftHour = tonumber(a) or 0, leftDay = tonumber(b) or 0, wait = tonumber(c) or 0, t = now }
    elseif kind == "HELLO" then
        ns.Share()
    end
    if ns.Refresh then ns.Refresh() end
end

-- The member with the fewest entries left, for "Group: Bob, 1 left".
function ns.GroupLow(now)
    now = now or time()
    local best, name
    for who, g in pairs(ns.group) do
        local left = math.min(g.leftHour, g.leftDay)
        local wait = math.max(0, g.wait - (now - g.t))
        if left == 0 and wait == 0 then left = 1 end
        if not best or left < best.left then best, name = { left = left, wait = wait }, who end
    end
    if best then best.name = name end
    return best
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

ns.DEFAULTS = { badgeMode = "ALWAYS", badgeScale = 100, badgeAlpha = 100, warnAt = 1, warnDayAt = 3,
                freeAlert = true, sound = true, summary = true, tellGroup = true, sync = true, fromExit = false,
                confirmed = false }
function ns.Defaults()
    for k, v in pairs(ns.DEFAULTS) do if ns.db[k] == nil then ns.db[k] = v end end
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
        db.dayLimit = db.dayLimit or ns.DEFAULT_DAY
        -- The old on/off counter switch becomes a mode.
        if db.badgeMode == nil then db.badgeMode = (db.badge == false) and "HIDDEN" or "ALWAYS" end
        db.badge = nil
        ns.Defaults()
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(ns.PREFIX) end
        if ns.SetupBadge then ns.SetupBadge() end
        for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "CHAT_MSG_SYSTEM",
                             "UI_ERROR_MESSAGE", "GROUP_LEFT", "GROUP_JOINED", "CHAT_MSG_ADDON",
                             "CHAT_MSG_COMBAT_XP_GAIN", "GROUP_ROSTER_UPDATE" }) do
            self:RegisterEvent(e)
        end
        ns.lastLeft = ns.Status().left
        if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(5, function() ns.Tick() end) end
        return
    end
    if event == "CHAT_MSG_SYSTEM" then
        ns.System(a1)
    elseif event == "UI_ERROR_MESSAGE" then
        ns.System(a2)
    elseif event == "CHAT_MSG_ADDON" then
        ns.Receive(a1, a2, a4)
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        ns.Killed()
    elseif event == "GROUP_ROSTER_UPDATE" then
        if not inGroup() then wipe(ns.group) end
    elseif event == "GROUP_LEFT" or event == "GROUP_JOINED" then
        ns.Reopen()
        wipe(ns.group)
        if event == "GROUP_JOINED" and ns.db.sync then sendAddon("HELLO", groupChannel()); ns.Share() end
    else
        local name, kind, mapID = instanceInfo()
        ns.Entered(name, kind, mapID)
    end
    if ns.Refresh then ns.Refresh() end
end)

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

if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({
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
            if s.left == 0 then return L.SUM_WAIT:format(ns.Clock(s.wait)), "Interface\\Icons\\Spell_Nature_TimeStop" end
            return L.SUM_LEFT:format(s.leftHour, ns.db.limit), "Interface\\Icons\\INV_Misc_PocketWatch_01"
        end,
        move = function(on) if ns.MoveBadge then ns.MoveBadge(on) end end,
        reset = function() ns.ResetSettings() end,
    })
end
