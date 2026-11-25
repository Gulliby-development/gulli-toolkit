-- The Real reminder (switch `real`): at level 60, a boss of a dungeon that drops Tarnished
-- Undermine Real leaves a Real to loot. After such a boss dies an icon shows until a Real comes
-- in, so it never stays on the corpse. A boss that gave this character a Real today is skipped,
-- and nothing shows at the cap. It only reads the game: kills from ENCOUNTER_END, the Real from
-- the currency it is. The currency's count is set against the count before the pull every
-- second (its event alone missed the loot), the loot chat names it, a loot window that held it
-- counts once it closes, a click hides it, and it never outlives REAL_WAIT.

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
local moving
local fight            -- { id, level } of the encounter that runs
local pending = {}     -- kills waiting for their Real, oldest first: { id, at, instance }
local baseQty          -- the Real count before the first pending kill's pull
local hidden = {}      -- encounter ids already reminded on this visit

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

-- n Reals came in: the oldest kills got theirs.
local function got(n)
    for _ = 1, math.max(1, n or 1) do
        local p = table.remove(pending, 1)
        if not p then break end
        ns.cdb.realGot = ns.cdb.realGot or {}
        ns.cdb.realGot[p.id] = resetAt()
        if p.instance and not ns.REAL_DUNGEONS[p.instance] then
            ns.db.realLearned = ns.db.realLearned or {}
            ns.db.realLearned[p.instance] = true
        end
    end
    if #pending == 0 then baseQty = nil end
end

-- The count against the one before the pull: true when it went up.
function ns.RealCheck()
    if #pending == 0 then return false end
    local n = ns.RealCount()
    if not n then return false end
    if not baseQty then baseQty = n return false end
    if n <= baseQty then
        if n < baseQty then baseQty = n end
        if ns.RealAtCap() then wipe(pending); baseQty = nil; ns.RealPaint() end
        return false
    end
    got(n - baseQty)
    baseQty = #pending > 0 and n or nil
    if ns.RealAtCap() then wipe(pending); baseQty = nil end
    ns.RealPaint()
    return true
end

-- A loot line or a loot slot that is the Real: its currency link, or its name.
function ns.IsRealText(text)
    if type(text) ~= "string" or secret(text) then return false end
    if text:find("currency:" .. ns.REAL_CURRENCY .. "[:|]") then return true end
    local _, _, info = ns.RealCount()
    local name = info and info.name
    if type(name) == "string" and not secret(name) and name ~= "" and text:find(name, 1, true) then return true end
    return text:find(L.REAL_NAME, 1, true) ~= nil
end

local function selfLoot(text, guid)
    if guid ~= nil and not secret(guid) and UnitGUID then return guid == UnitGUID("player") end
    local head = type(LOOT_ITEM_SELF) == "string" and LOOT_ITEM_SELF:match("^(.-)%%s") or nil
    return head ~= nil and head ~= "" and text:sub(1, #head) == head
end

-- Take the oldest kill as looted, when the count did not tell already.
local function takeOne()
    if ns.RealCheck() or #pending == 0 then return end
    got(1)
    ns.RealPaint()
end

local lootHadReal

function ns.OnRealEvent(event, a1, _, _, _, a5, ...)
    if event == "ENCOUNTER_START" then
        fight = { id = a1, level = ns.RealBossLevel(), qty = ns.RealCount() }
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
        local before = fight and fight.id == a1 and fight.qty or nil
        fight = nil
        if a5 ~= 1 or hidden[a1] or not ns.RealWanted(a1, level) then return end
        hidden[a1] = true
        local _, _, _, _, _, _, _, inst = GetInstanceInfo()
        if #pending == 0 then baseQty = before or ns.RealCount() end
        pending[#pending + 1] = { id = a1, at = now(), instance = inst }
        -- the Real may have come in before the boss's end
        if not ns.RealCheck() then ns.RealPaint() end
        if C_Timer and C_Timer.After then C_Timer.After(ns.REAL_WAIT + 1, function() ns.RealPaint() end) end
    elseif event == "CURRENCY_DISPLAY_UPDATE" or event == "BAG_UPDATE_DELAYED" then
        ns.RealCheck()
    elseif event == "CHAT_MSG_CURRENCY" then
        if #pending > 0 and ns.IsRealText(a1) then takeOne() end
    elseif event == "CHAT_MSG_LOOT" then
        local guid = select(7, ...) -- the 12th argument
        if #pending > 0 and ns.IsRealText(a1) and selfLoot(a1, guid) then takeOne() end
    elseif event == "LOOT_OPENED" or event == "LOOT_READY" then
        if #pending == 0 or not GetNumLootItems then return end
        for i = 1, GetNumLootItems() or 0 do
            local link = GetLootSlotLink and GetLootSlotLink(i)
            local name = GetLootSlotInfo and select(2, GetLootSlotInfo(i))
            if ns.IsRealText(link) or ns.IsRealText(name) then lootHadReal = true end
        end
    elseif event == "LOOT_CLOSED" then
        -- the window showed the Real: it is taken, or the player chose to leave it
        if lootHadReal then lootHadReal = nil; takeOne() else ns.RealCheck() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- out of the dungeon, nothing is left to loot
        if not ns.RealDungeon() then wipe(pending); wipe(hidden); baseQty = nil end
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
        if #pending > 0 then
            dropOld()
            if #pending == 0 then ns.RealPaint() else ns.RealCheck() end
        end
    end)
    -- a click hides it: the player knows best whether the Real was looted
    frame:EnableMouse(true)
    frame:SetScript("OnMouseUp", function()
        if moving then return end
        if GameTooltip then GameTooltip:Hide() end
        ns.RealClear()
    end)
    frame:SetScript("OnEnter", function(self)
        if moving or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L.REAL_NAME)
        GameTooltip:AddLine(L.REAL_HIDE, 1, 1, 1)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    place()
    frame:Hide()
end

function ns.RealFrame()
    if not frame then build() end
    return frame
end

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
    if not on then wipe(pending); baseQty = nil end
    if frame then ns.RealPaint() end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "ENCOUNTER_START", "ENCOUNTER_END", "CURRENCY_DISPLAY_UPDATE", "PLAYER_ENTERING_WORLD",
                     "PLAYER_LOGIN", "BAG_UPDATE_DELAYED", "CHAT_MSG_CURRENCY", "CHAT_MSG_LOOT", "LOOT_READY", "LOOT_OPENED",
                     "LOOT_CLOSED" }) do
    ev:RegisterEvent(e)
end
ev:SetScript("OnEvent", function(_, event, ...)
    if not ns.db then return end
    if event == "PLAYER_LOGIN" then ns.RealPrune() return end
    if ns.paused or ns.db.real ~= true then return end
    ns.OnRealEvent(event, ...)
end)

function ns.RealClear() wipe(pending); baseQty = nil; lootHadReal = nil; if frame then ns.RealPaint() end end
