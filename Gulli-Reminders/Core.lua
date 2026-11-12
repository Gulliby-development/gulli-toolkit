-- Small icons on screen for what is missing before a fight: the class's own long buffs, a
-- weapon poison or imbue, arrows and bullets, soul shards. Checked out of combat only.

local ADDON, ns = ...
local L = ns.L

-- Long self buffs per class: any of the spells counts (ranks share a name). Rank 1 ids.
ns.BUFFS = {
    MAGE = { { "INTELLECT", { 1459, 23028 } }, { "ARMOR", { 168, 7302, 6117 } } },
    PRIEST = { { "FORTITUDE", { 1243, 21562 } }, { "INNER_FIRE", { 588 } } },
    DRUID = { { "WILD", { 1126, 21849 } } },
    WARLOCK = { { "DEMON_ARMOR", { 687, 706 } } },
    PALADIN = { { "BLESSING", { 19740, 19742, 20217, 1038, 19977, 20911, 25782, 25894, 25898, 25890, 25899, 25895 } },
                { "AURA", { 465, 7294, 19746, 19876, 19888, 19891, 20218 } } },
    HUNTER = { { "ASPECT", { 13165, 13163, 5118, 13159, 20043 } } },
    SHAMAN = { { "SHIELD", { 324 } } },
}
ns.IMBUES = { SHAMAN = { 8017, 8024, 8033, 8232 } } -- a shaman who knows one should use one
local POISON_LEVEL = 20
local SOUL_SHARD = 6265
local AMMO_SLOT, OFF_HAND = 0, 17
local SOON = 60 * 1000 -- a weapon buff with less than a minute left counts as missing
local ITEM_WEAPON = 2

-- Game API wrappers.
local function knows(id) return IsPlayerSpell and IsPlayerSpell(id) or false end
local function spellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return (GetSpellInfo(id))
end
local function spellIcon(id)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
    return select(3, GetSpellInfo(id))
end
local function buffNames()
    local names = {}
    for i = 1, 40 do
        local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not a then break end
        if a.name and not (issecretvalue and issecretvalue(a.name)) then names[a.name] = true end
    end
    return names
end
local function itemCount(id) return ((C_Item and C_Item.GetItemCount) or GetItemCount)(id) or 0 end
local function offHandWeapon()
    local id = GetInventoryItemID("player", OFF_HAND)
    if not id then return false end
    local classID = select(12, ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(id))
    return classID == ITEM_WEAPON
end

-- What is missing now: { { key, text, icon } }.
function ns.Missing()
    local out = {}
    local db = ns.db
    if InCombatLockdown() then return out end
    if db.notResting and IsResting() then return out end
    local _, class = UnitClass("player")
    local level = UnitLevel("player")
    if db.buffs then
        local have = buffNames()
        for _, b in ipairs(ns.BUFFS[class] or {}) do
            local known, found
            for _, id in ipairs(b[2]) do
                if knows(id) then known = known or id end
                local name = spellName(id)
                if name and have[name] then found = true end
            end
            if known and not found then
                out[#out + 1] = { key = b[1], text = L["BUFF_" .. b[1]], icon = spellIcon(known) }
            end
        end
    end
    if db.weapon then
        local hasMain, mainLeft, _, _, hasOff, offLeft = GetWeaponEnchantInfo()
        local function weak(has, left) return not has or (left or 0) < SOON end
        local need
        if class == "ROGUE" and level >= POISON_LEVEL then
            need = weak(hasMain, mainLeft) or (offHandWeapon() and weak(hasOff, offLeft))
        elseif ns.IMBUES[class] then
            for _, id in ipairs(ns.IMBUES[class]) do
                if knows(id) then need = weak(hasMain, mainLeft); break end
            end
        end
        if need then
            out[#out + 1] = { key = "WEAPON", text = L.WEAPON, icon = "Interface\\Icons\\Trade_BrewPoison" }
        end
    end
    if db.ammo and class == "HUNTER" then
        local n = GetInventoryItemCount("player", AMMO_SLOT) or 0
        if n < db.ammoMin then
            out[#out + 1] = { key = "AMMO", text = L.AMMO:format(n), icon = "Interface\\Icons\\INV_Ammo_Arrow_02" }
        end
    end
    if db.shards and class == "WARLOCK" then
        local n = itemCount(SOUL_SHARD)
        if n < db.shardsMin then
            out[#out + 1] = { key = "SHARDS", text = L.SHARDS:format(n), icon = "Interface\\Icons\\INV_Misc_Gem_Amethyst_02" }
        end
    end
    return out
end

local pending = false
local function soon()
    if pending then return end
    pending = true
    C_Timer.After(0.5, function()
        pending = false
        if ns.Refresh then ns.Refresh() end
    end)
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliRemindersDB = GulliRemindersDB or {}
        ns.db = GulliRemindersDB
        local defaults = { buffs = true, weapon = true, ammo = true, shards = true, notResting = true,
                           ammoMin = 200, shardsMin = 3 }
        for k, v in pairs(defaults) do if ns.db[k] == nil then ns.db[k] = v end end
        for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "UNIT_AURA", "UNIT_INVENTORY_CHANGED", "BAG_UPDATE_DELAYED",
                             "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_UPDATE_RESTING" }) do
            self:RegisterEvent(e)
        end
        -- Weapon buffs run out without an event.
        C_Timer.NewTicker(15, soon)
        return
    end
    if (event == "UNIT_AURA" or event == "UNIT_INVENTORY_CHANGED") and a1 ~= "player" then return end
    if event == "PLAYER_REGEN_DISABLED" then
        if ns.Refresh then ns.Refresh() end -- hide at once when a fight starts
        return
    end
    soon()
end)

SLASH_GULLIREMINDERS1 = "/grm"
SLASH_GULLIREMINDERS2 = "/gullireminders"
SlashCmdList.GULLIREMINDERS = function() ns.Toggle() end

function GulliReminders_Toggle() ns.Toggle() end

-- The same switches as in the window, so the Gulli Toolkit hub can show them.
-- The game icon of each switch, in the window and in the hub.
ns.OPT_ICON = {
    buffs = "Interface\\Icons\\Spell_Holy_WordFortitude",
    weapon = "Interface\\Icons\\INV_Stone_02",
    ammo = "Interface\\Icons\\INV_Ammo_Arrow_02",
    shards = "Interface\\Icons\\INV_Misc_Gem_Amethyst_02",
    notResting = "Interface\\Icons\\Spell_Nature_Sleep",
}

local function option(key, label)
    return { label = label, icon = ns.OPT_ICON[key], get = function() return ns.db ~= nil and ns.db[key] == true end,
             set = function(on) if ns.db then ns.db[key] = on and true or false end; if ns.Refresh then ns.Refresh() end end }
end

if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({
        key = "Reminders",
        icon = "Interface\\AddOns\\Gulli-Reminders\\icon",
        slash = "/grm",
        open = function() ns.Toggle() end,
        window = function() return ns.Window and ns.Window() end,
        options = {
            option("buffs", ns.L.OPT_BUFFS),
            option("weapon", ns.L.OPT_WEAPON),
            option("ammo", ns.L.OPT_AMMO),
            option("shards", ns.L.OPT_SHARDS),
            option("notResting", ns.L.OPT_RESTING),
        },
    })
end
