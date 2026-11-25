-- The Real reminder (switch `real`): at level 60, a boss of a dungeon that drops Tarnished
-- Undermine Real leaves a Real to loot. After such a boss dies an icon shows until a Real comes
-- in, so it never stays on the corpse. A boss that gave this character a Real today is skipped,
-- and nothing shows at the cap. It only reads the game: kills from ENCOUNTER_END, the Real from
-- the currency it is.

local _, ns = ...
local L = ns.L
local S = ns.Skin

ns.REAL_CURRENCY = 3469
ns.REAL_CAP = 250          -- the cap players report, when the game gives none
ns.REAL_LEVEL = 60         -- the character's level the Real drops at
ns.REAL_BOSS_MIN = 55      -- a boss below this level never drops one
ns.REAL_WAIT = 300         -- the icon goes after this long when no Real came
ns.REAL_ICON = "Interface\\Icons\\INV_Misc_Coin_19"
-- Dungeons that drop it, by the instance id of GetInstanceInfo (Lower and Upper Blackrock
-- Spire share 229). Another dungeon joins `db.realLearned` once a Real came in there.
ns.REAL_DUNGEONS = { [230] = true, [229] = true, [429] = true, [289] = true, [329] = true }
-- WoW Forever's own dungeons by their English name, until a Real there gives their id.
ns.REAL_NAMES = { ["Blackmaw Hold"] = true, ["Shaper's Terrace"] = true }

local frame, icon, caption
local fight            -- { id, level } of the encounter that runs
local pending = {}     -- kills waiting for their Real, oldest first: { id, at, instance }
local lastQty

local function now() return time and time() or 0 end
local function secret(v) return issecretvalue and issecretvalue(v) end

function ns.RealOn() return ns.db ~= nil and ns.db.real == true and not ns.paused end

-- What this character holds and the cap, or nil when the game does not tell.
function ns.RealCount()
    local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(ns.REAL_CURRENCY)
    if not info or secret(info.quantity) then return nil end
    local cap = info.maxQuantity
    if secret(cap) or not cap or cap <= 0 then cap = ns.REAL_CAP end
    return info.quantity or 0, cap, info
end

function ns.RealAtCap()
    local n, cap = ns.RealCount()
    return n ~= nil and n >= cap
end

-- The dungeon we are in drops Reals.
function ns.RealDungeon()
    if not GetInstanceInfo then return false end
    local name, kind, _, _, _, _, _, id = GetInstanceInfo()
    if kind ~= "party" then return false end
    if id and (ns.REAL_DUNGEONS[id] or (ns.db.realLearned or {})[id]) then return true end
    return name ~= nil and not secret(name) and ns.REAL_NAMES[name] == true
end

-- The highest level of the bosses in sight; -1 (a skull) counts as high enough.
function ns.RealBossLevel()
    local best
    for _, u in ipairs({ "boss1", "boss2", "boss3", "boss4", "boss5", "target" }) do
        if UnitExists and UnitExists(u) and (not UnitCanAttack or UnitCanAttack("player", u)) then
            local lv = UnitLevel(u)
            if lv ~= nil and not secret(lv) then
                if lv < 0 then return -1 end
                if not best or lv > best then best = lv end
            end
        end
    end
    return best
end

function ns.RealBossCounts(level)
    return level == nil or level < 0 or level >= ns.REAL_BOSS_MIN
end

-- The end of today for the "looted today" marks: the game's daily reset.
local function resetAt()
    local left = C_DateAndTime and C_DateAndTime.GetSecondsUntilDailyReset and C_DateAndTime.GetSecondsUntilDailyReset()
    if type(left) ~= "number" or secret(left) or left <= 0 then left = 86400 end
    return now() + left
end

function ns.RealLootedToday(id)
    local got = ns.cdb and ns.cdb.realGot
    return got ~= nil and (got[id] or 0) > now()
end

-- Marks that ran out go at login.
function ns.RealPrune()
    local got = ns.cdb and ns.cdb.realGot
    if not got then return end
    for id, t in pairs(got) do if t <= now() then got[id] = nil end end
end

-- Whether a boss just killed should get the reminder.
function ns.RealWanted(id, level)
    if not ns.RealOn() or id == nil then return false end
    if (UnitLevel("player") or 0) < ns.REAL_LEVEL then return false end
    if not ns.RealDungeon() then return false end
    if not ns.RealBossCounts(level) then return false end
    if ns.RealLootedToday(id) then return false end
    for _, p in ipairs(pending) do if p.id == id then return false end end
    return not ns.RealAtCap()
end

local function dropOld()
    local cut = now() - ns.REAL_WAIT
    for i = #pending, 1, -1 do
        if pending[i].at <= cut then table.remove(pending, i) end
    end
end

function ns.RealPending() dropOld(); return pending end

function ns.OnRealEvent(event, a1, _, a3, _, a5)
    if event == "ENCOUNTER_START" then
        fight = { id = a1, level = ns.RealBossLevel() }
        -- the boss frames come a moment after the pull
        if C_Timer and C_Timer.After then
            C_Timer.After(1, function()
                if fight and fight.id == a1 then
                    local lv = ns.RealBossLevel()
                    if lv and (lv < 0 or not fight.level or lv > fight.level) then fight.level = lv end
                end
            end)
        end
    elseif event == "ENCOUNTER_END" then
        local level = fight and fight.id == a1 and fight.level or nil
        fight = nil
        if a5 ~= 1 or not ns.RealWanted(a1, level) then return end
        local _, _, _, _, _, _, _, inst = GetInstanceInfo()
        pending[#pending + 1] = { id = a1, at = now(), instance = inst }
        lastQty = ns.RealCount()
        ns.RealPaint()
    elseif event == "CURRENCY_DISPLAY_UPDATE" then
        if a1 ~= nil and a1 ~= ns.REAL_CURRENCY then return end
        local n = ns.RealCount()
        local gained = (n and lastQty and n > lastQty)
            or (a1 == ns.REAL_CURRENCY and type(a3) == "number" and not secret(a3) and a3 > 0)
        if n then lastQty = n end
        if not gained then
            if #pending > 0 and ns.RealAtCap() then wipe(pending); ns.RealPaint() end
            return
        end
        dropOld()
        local p = table.remove(pending, 1)
        if p then
            ns.cdb.realGot = ns.cdb.realGot or {}
            ns.cdb.realGot[p.id] = resetAt()
            if p.instance and not ns.REAL_DUNGEONS[p.instance] then
                ns.db.realLearned = ns.db.realLearned or {}
                ns.db.realLearned[p.instance] = true
            end
        end
        if ns.RealAtCap() then wipe(pending) end
        ns.RealPaint()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- out of the dungeon, nothing is left to loot
        if not ns.RealDungeon() then wipe(pending) end
        lastQty = ns.RealCount()
        ns.RealPaint()
    end
end

---- The icon ------------------------------------------------------------------------------

local function place()
    if not frame then return end
    frame:ClearAllPoints()
    local p = ns.db and ns.db.realPoint
    if p then frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else frame:SetPoint("TOP", UIParent, "TOP", 0, -180) end
end

local function build()
    frame = CreateFrame("Frame", "GulliLootReal", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetSize(48, 48)
    icon = S.HudIcon(CreateFrame("Frame", nil, frame), 48)
    icon:SetPoint("LEFT")
    caption = S.HudCaption(frame, 48)
    caption:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    S.Mover(frame, { label = L.FR_REAL, hint = L.TIP_MOVE,
        save = function(p, rp, x, y) ns.db.realPoint = { p, rp, x, y } end,
        reset = function() ns.db.realPoint = nil; place() end })
    local acc = 0
    frame:SetScript("OnUpdate", function(_, dt)
        acc = acc + (dt or 0)
        if acc < 1 then return end
        acc = 0
        if #pending > 0 then dropOld(); if #pending == 0 then ns.RealPaint() end end
    end)
    place()
    frame:Hide()
end

function ns.RealFrame()
    if not frame then build() end
    return frame
end

local moving
function ns.RealPaint()
    if not frame then build() end
    dropOld()
    local show = moving or (ns.RealOn() and #pending > 0)
    if not show then frame:Hide() return end
    local _, _, info = ns.RealCount()
    icon:SetIcon(info and info.iconFileID or ns.REAL_ICON)
    icon:SetState("need")
    icon:SetCount(#pending > 1 and tostring(#pending) or "")
    caption:Set(info and info.name or L.REAL_NAME, L.REAL_LOOT)
    if not frame:IsShown() then
        frame:Show()
        if S.MotionIn then S.MotionIn(frame, 6) end
    end
end

-- Unlock mode: the icon shows so the player can place it.
function ns.MoveReal(on)
    local f = ns.RealFrame()
    moving = on and true or nil
    ns.RealPaint()
    if f.SetMoving then f:SetMoving(on) end
end

function ns.SetReal(on)
    if not ns.db then return end
    ns.db.real = on and true or false
    if not on then wipe(pending) end
    if frame then ns.RealPaint() end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "ENCOUNTER_START", "ENCOUNTER_END", "CURRENCY_DISPLAY_UPDATE", "PLAYER_ENTERING_WORLD",
                     "PLAYER_LOGIN" }) do
    ev:RegisterEvent(e)
end
ev:SetScript("OnEvent", function(_, event, ...)
    if not ns.db then return end
    if event == "PLAYER_LOGIN" then ns.RealPrune() return end
    if ns.paused or ns.db.real ~= true then return end
    ns.OnRealEvent(event, ...)
end)

function ns.RealClear() wipe(pending); if frame then ns.RealPaint() end end
