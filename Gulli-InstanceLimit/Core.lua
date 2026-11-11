-- Counts dungeon entries per hour and per day for the whole account, like the game does,
-- and says when the next entry is free. Entering the same dungeon again does not count
-- until it was reset or the group changed.

local ADDON, ns = ...
local L = ns.L

ns.HOUR, ns.DAY = 3600, 86400

-- Game API wrappers.
local function inInstance() return IsInInstance() end
local function instanceInfo()
    local name, kind, _, _, _, _, _, mapID = GetInstanceInfo()
    return name, kind, mapID
end

local function say(msg) print("|cff9ad0ffGulli Instance Limit|r: " .. msg) end
local function notify(msg)
    if GulliToolkit and GulliToolkit.Notify then GulliToolkit.Notify("InstanceLimit", msg) end
end

function ns.Clock(sec)
    sec = math.max(0, math.floor(sec))
    local f = math.floor
    if sec >= 3600 then return string.format("%d:%02d:%02d", f(sec / 3600), f((sec % 3600) / 60), sec % 60) end
    return string.format("%d:%02d", f(sec / 60), sec % 60)
end

-- Drops entries older than a day; returns entries in the last hour and day.
function ns.Counts(now)
    now = now or time()
    local db = ns.db
    for i = #db.entries, 1, -1 do
        if now - db.entries[i].t >= ns.DAY then table.remove(db.entries, i) end
    end
    local hour, day = 0, #db.entries
    local oldestHour, oldestDay
    for _, e in ipairs(db.entries) do
        if now - e.t < ns.HOUR then
            hour = hour + 1
            if not oldestHour or e.t < oldestHour then oldestHour = e.t end
        end
        if not oldestDay or e.t < oldestDay then oldestDay = e.t end
    end
    return hour, day, oldestHour, oldestDay
end

-- How many entries are left, and in how many seconds the next one is free (0 = now).
function ns.Status(now)
    now = now or time()
    local hour, day, oldestHour, oldestDay = ns.Counts(now)
    local db = ns.db
    local leftHour = math.max(0, db.limit - hour)
    local leftDay = math.max(0, db.dayLimit - day)
    local wait = 0
    if leftHour == 0 and oldestHour then
        -- The slot of the oldest entries frees one by one; the one that brings us under the limit.
        local times = {}
        for _, e in ipairs(db.entries) do if now - e.t < ns.HOUR then times[#times + 1] = e.t end end
        table.sort(times)
        wait = times[hour - db.limit + 1] + ns.HOUR - now
    end
    if leftDay == 0 and oldestDay then wait = math.max(wait, oldestDay + ns.DAY - now) end
    return { hour = hour, day = day, leftHour = leftHour, leftDay = leftDay, wait = wait,
             left = math.min(leftHour, leftDay) }
end

-- Called when the player is in a new place. Returns true when an entry was counted.
function ns.Entered(name, kind, mapID, now)
    if kind ~= "party" and kind ~= "raid" then
        ns.inside = nil
        return false
    end
    now = now or time()
    local db = ns.db
    if ns.inside == mapID then return false end
    ns.inside = mapID
    -- An unused copy of a dungeon goes away after a while; after an hour we count it again.
    local opened = db.open[mapID]
    if opened and (opened == true or now - opened < ns.HOUR) then return false end
    db.open[mapID] = now
    table.insert(db.entries, { t = now, name = name, map = mapID, char = UnitName("player") })
    local s = ns.Status(now)
    if s.left == 1 then
        say(L.WARN_LAST); notify(L.WARN_LAST)
    elseif s.left == 0 then
        local msg = L.WARN_NONE:format(ns.Clock(math.max(s.wait, 0)))
        say(msg); notify(msg)
    end
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

function ns.CanReset()
    if inInstance() then return false end
    if IsInGroup and IsInGroup() then return UnitIsGroupLeader and UnitIsGroupLeader("player") or false end
    return true
end

function ns.Reset()
    if ns.CanReset() and ResetInstances then ResetInstances() end
end

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
    if name then ns.Reopen(name) end
    if msg == refusedText then ns.Refused() end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1, a2)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliInstanceLimitDB = GulliInstanceLimitDB or {}
        ns.db = GulliInstanceLimitDB
        ns.db.entries = ns.db.entries or {}
        ns.db.open = ns.db.open or {}
        ns.db.limit = ns.db.limit or 5
        ns.db.dayLimit = ns.db.dayLimit or 30
        if ns.db.badge == nil then ns.db.badge = true end
        if ns.SetupBadge then ns.SetupBadge() end
        for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "CHAT_MSG_SYSTEM",
                             "UI_ERROR_MESSAGE", "GROUP_LEFT", "GROUP_JOINED" }) do
            self:RegisterEvent(e)
        end
        return
    end
    if event == "CHAT_MSG_SYSTEM" then
        ns.System(a1)
    elseif event == "UI_ERROR_MESSAGE" then
        ns.System(a2)
    elseif event == "GROUP_LEFT" or event == "GROUP_JOINED" then
        ns.Reopen()
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

if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({
        key = "InstanceLimit",
        icon = "Interface\\AddOns\\Gulli-InstanceLimit\\icon",
        slash = "/gil",
        open = function() ns.Toggle() end,
    })
end
