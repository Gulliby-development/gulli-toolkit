-- Experience per hour over the last hour of play, the time and kills to the next level, and
-- how the XP came in (kills or quests). Counted per session; a new login starts again.

local ADDON, ns = ...
local L = ns.L

local WINDOW = 3600 -- the rate looks at the last hour
local MIN_SPAN = 60 -- and at least a minute, so the first kill does not show a huge rate

local function secret(v) return issecretvalue and issecretvalue(v) end

function ns.Start()
    ns.s = { t = time(), gained = 0, kills = 0, killXP = 0, quests = 0, questXP = 0, events = {} }
    ns.lastXP, ns.lastMax = UnitXP("player"), UnitXPMax("player")
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
        ns.s.gained = ns.s.gained + delta
        table.insert(ns.s.events, { now, delta })
    end
end

-- XP per hour over the last hour (or the session, when it is shorter).
function ns.Rate(now)
    now = now or time()
    local sum = 0
    local events = ns.s.events
    while events[1] and events[1][1] < now - WINDOW do table.remove(events, 1) end
    for _, e in ipairs(events) do sum = sum + e[2] end
    local span = math.max(MIN_SPAN, math.min(WINDOW, now - ns.s.t))
    return sum * 3600 / span
end

-- Everything the bar and the window show.
function ns.Stats(now)
    now = now or time()
    local cur, max = UnitXP("player"), UnitXPMax("player")
    local left = math.max(0, max - cur)
    local rate = ns.Rate(now)
    local s = ns.s
    local avgKill = s.kills > 0 and s.killXP / s.kills or 0
    return {
        rate = rate,
        left = left,
        toLevel = rate > 0 and math.floor(left / rate * 3600) or nil,
        killsToLevel = avgKill > 0 and math.ceil(left / avgKill) or nil,
        avgKill = avgKill,
        kills = s.kills, quests = s.quests, killXP = s.killXP, questXP = s.questXP,
        gained = s.gained, session = now - s.t,
        rested = GetXPExhaustion and GetXPExhaustion() or 0,
        percent = max > 0 and math.floor(cur * 100 / max) or 0,
    }
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

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1, a2)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliXPDB = GulliXPDB or {}
        ns.db = GulliXPDB
        if ns.db.bar == nil then ns.db.bar = true end
        for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_XP_UPDATE", "CHAT_MSG_COMBAT_XP_GAIN", "QUEST_TURNED_IN",
                             "PLAYER_LEVEL_UP" }) do
            self:RegisterEvent(e)
        end
        ns.Start()
        return
    end
    if event == "PLAYER_LOGIN" then
        ns.Start()
    elseif event == "PLAYER_XP_UPDATE" then
        ns.Update()
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        local xp = ns.KillXP(a1)
        if xp then
            ns.s.kills = ns.s.kills + 1
            ns.s.killXP = ns.s.killXP + xp
        end
    elseif event == "QUEST_TURNED_IN" then
        local xp = tonumber(a2) or 0
        if xp > 0 then
            ns.s.quests = ns.s.quests + 1
            ns.s.questXP = ns.s.questXP + xp
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
    })
end
