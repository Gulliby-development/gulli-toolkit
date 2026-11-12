-- A panel of icons on screen for what is missing before a fight: the class's own long buffs (each
-- one switched on or off), a weapon poison or imbue, the pet, arrows and bullets, soul shards.
-- Checked out of combat only. UI.lua draws the panel and the settings.

local ADDON, ns = ...
local L = ns.L

-- Long buffs per class: any of the spells counts (ranks share a name; a group spell counts
-- for the single one). Rank 1 ids. on = false: off until the player switches it on.
ns.BUFFS = {
    MAGE = {
        { key = "INTELLECT", ids = { 1459, 23028 } },
        { key = "ARMOR", ids = { 168, 7302, 6117 } },
        { key = "MAGIC", ids = { 1008, 604 }, on = false },
    },
    PRIEST = {
        { key = "FORTITUDE", ids = { 1243, 21562 } },
        { key = "INNER_FIRE", ids = { 588 } },
        { key = "SPIRIT", ids = { 14752, 27681 } },
        { key = "SHADOW_PROT", ids = { 976, 27683 }, on = false },
    },
    DRUID = {
        { key = "WILD", ids = { 1126, 21849 } },
        { key = "OMEN", ids = { 16864 } },
        { key = "THORNS", ids = { 467 }, on = false },
    },
    WARLOCK = {
        { key = "DEMON_ARMOR", ids = { 687, 706 } },
    },
    PALADIN = {
        { key = "BLESSING", ids = { 19740, 19742, 20217, 1038, 19977, 20911, 25782, 25894, 25898, 25890, 25899, 25895 } },
        { key = "AURA", ids = { 465, 7294, 19746, 19876, 19888, 19891, 20218 } },
        { key = "FURY", ids = { 25780 }, on = false },
    },
    HUNTER = {
        { key = "ASPECT", ids = { 13165, 13163, 5118, 13159, 13161, 20043 } },
        { key = "TRUESHOT", ids = { 19506 } },
    },
    SHAMAN = {
        { key = "SHIELD", ids = { 324 } },
    },
    WARRIOR = {
        { key = "SHOUT", ids = { 6673 }, on = false }, -- two minutes: off unless asked
    },
}
ns.IMBUES = { SHAMAN = { 8017, 8024, 8033, 8232 } } -- a shaman who knows one should use one
ns.PET_SPELL = { HUNTER = 883, WARLOCK = 688 } -- Call Pet, Summon Imp
local POISON_LEVEL = 20
local SOUL_SHARD = 6265
local AMMO_SLOT, OFF_HAND = 0, 17
local ITEM_WEAPON = 2

ns.DEFAULTS = {
    show = true, inRest = true, track = {}, weapon = true, ammo = true, shards = true, pet = true,
    ammoMin = 200, shardsMin = 3, soonMin = 3,
    locked = true, size = 40, alpha = 100, labels = true, vertical = false,
}
ns.PANEL_POINT = { "TOP", 0, -190 }

-- Game API wrappers.
local function spellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return GetSpellInfo and (GetSpellInfo(id)) or nil
end
local function spellIcon(id)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
    return GetSpellInfo and select(3, GetSpellInfo(id)) or nil
end
-- Known by id, or by name in the spellbook (a client may know a higher rank only).
local function knows(id)
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    if IsSpellKnown and IsSpellKnown(id) then return true end
    if C_SpellBook and C_SpellBook.FindSpellBookSlotForSpell then
        return C_SpellBook.FindSpellBookSlotForSpell(id) ~= nil
    end
    return false
end
ns.Knows = knows
-- The player's buffs: name -> seconds left (false for a buff that does not run out).
local function buffs()
    local have = {}
    local now = GetTime()
    for i = 1, 40 do
        local a = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not a then break end
        local n = a.name
        if n and not (issecretvalue and issecretvalue(n)) then
            local left = false
            local e = a.expirationTime
            if e and not (issecretvalue and issecretvalue(e)) and e > 0 then left = e - now end
            local old = have[n]
            if old == nil or (old ~= false and (left == false or left > old)) then have[n] = left end
        end
    end
    return have
end
local function itemCount(id) return ((C_Item and C_Item.GetItemCount) or GetItemCount)(id) or 0 end
local function offHandWeapon()
    local id = GetInventoryItemID("player", OFF_HAND)
    if not id then return false end
    local classID = select(12, ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(id))
    return classID == ITEM_WEAPON
end
local function playerClass() return select(2, UnitClass("player")) end

function ns.Tracked(b)
    local v = ns.db and ns.db.track[b.key]
    if v == nil then return b.on ~= false end
    return v
end

-- The class's buffs for the settings: { key, ids, on, known (a spell id or nil), name, icon }.
function ns.ClassBuffs(class)
    local out = {}
    for _, b in ipairs(ns.BUFFS[class or playerClass()] or {}) do
        local known
        for _, id in ipairs(b.ids) do
            if knows(id) then known = id; break end
        end
        out[#out + 1] = { key = b.key, ids = b.ids, on = b.on, known = known, name = L["BUFF_" .. b.key],
                          icon = spellIcon(known or b.ids[1]) }
    end
    return out
end

-- The class checks besides buffs that this character can use.
function ns.Extras(class)
    class = class or playerClass()
    local e = {}
    if class == "ROGUE" or ns.IMBUES[class] then e.weapon = true end
    if class == "HUNTER" then e.ammo = true end
    if class == "WARLOCK" then e.shards = true end
    if ns.PET_SPELL[class] then e.pet = true end
    return e
end

-- What is missing now: { { key, text, icon, left } }, and as the second value why nothing is
-- checked ("off", "combat", "dead", "rest") when that is so.
function ns.Missing()
    local out = {}
    local db = ns.db
    if not db.show then return out, "off" end
    if InCombatLockdown() then return out, "combat" end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return out, "dead" end
    if UnitOnTaxi and UnitOnTaxi("player") then return out, "taxi" end
    if not db.inRest and IsResting() then return out, "rest" end
    local class = playerClass()
    local level = UnitLevel("player")
    local soon = (db.soonMin or 0) * 60
    local have = buffs()
    for _, b in ipairs(ns.ClassBuffs(class)) do
        if b.known and ns.Tracked(b) then
            local best
            for _, id in ipairs(b.ids) do
                local left = have[spellName(id) or ""]
                if left == false then best = false; break end
                if left and (not best or left > best) then best = left end
            end
            if best == nil then
                out[#out + 1] = { key = b.key, text = b.name, icon = spellIcon(b.known) }
            elseif best and best < soon then
                out[#out + 1] = { key = b.key, text = b.name, icon = spellIcon(b.known), left = best }
            end
        end
    end
    if db.weapon then
        local hasMain, mainLeft, _, _, hasOff, offLeft = GetWeaponEnchantInfo()
        local limit = math.max(60, soon) * 1000
        local function weak(has, left) return not has or (left or 0) < limit end
        local need
        if class == "ROGUE" and level >= POISON_LEVEL then
            need = weak(hasMain, mainLeft) or (offHandWeapon() and weak(hasOff, offLeft))
        elseif ns.IMBUES[class] then
            for _, id in ipairs(ns.IMBUES[class]) do
                if knows(id) then need = weak(hasMain, mainLeft); break end
            end
        end
        if need then
            local left = hasMain and mainLeft and mainLeft > 0 and mainLeft / 1000 or nil
            out[#out + 1] = { key = "WEAPON", text = L.WEAPON, icon = "Interface\\Icons\\Trade_BrewPoison", left = left }
        end
    end
    local pet = ns.PET_SPELL[class]
    if db.pet and pet and knows(pet) and not (IsMounted and IsMounted())
        and (not UnitExists("pet") or UnitIsDead("pet")) then
        out[#out + 1] = { key = "PET", text = L.PET, icon = spellIcon(pet) }
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

-- The icon of the class's pet summon, from the game.
function ns.PetIcon()
    local id = ns.PET_SPELL[playerClass()]
    return id and spellIcon(id) or nil
end

-- Every icon the panel can show for this character, for the unlocked panel to place it.
function ns.Sample()
    local out = {}
    local class = playerClass()
    for _, b in ipairs(ns.ClassBuffs(class)) do
        if b.known and ns.Tracked(b) then out[#out + 1] = { key = b.key, text = b.name, icon = b.icon, sample = true } end
    end
    local e = ns.Extras(class)
    if e.weapon and ns.db.weapon then out[#out + 1] = { key = "WEAPON", text = L.WEAPON, icon = "Interface\\Icons\\Trade_BrewPoison", sample = true } end
    if e.pet and ns.db.pet then out[#out + 1] = { key = "PET", text = L.PET, icon = spellIcon(ns.PET_SPELL[class]), sample = true } end
    if e.ammo and ns.db.ammo then out[#out + 1] = { key = "AMMO", text = L.OPT_AMMO, icon = "Interface\\Icons\\INV_Ammo_Arrow_02", sample = true } end
    if e.shards and ns.db.shards then out[#out + 1] = { key = "SHARDS", text = L.OPT_SHARDS, icon = "Interface\\Icons\\INV_Misc_Gem_Amethyst_02", sample = true } end
    if #out == 0 then out[1] = { key = "SAMPLE", text = L.TITLE, icon = "Interface\\AddOns\\Gulli-Reminders\\icon", sample = true } end
    return out
end

-- "12m", "45s": time left on an icon.
function ns.Short(sec)
    if not sec then return "" end
    if sec >= 60 then return math.floor(sec / 60 + 0.5) .. "m" end
    return math.max(0, math.floor(sec)) .. "s"
end

-- Every setting changes here, so the panel and the window follow at once.
function ns.SetPref(key, value)
    ns.db[key] = value
    if ns.Refresh then ns.Refresh() end
end

function ns.SetTracked(key, on)
    ns.db.track[key] = on and true or false
    if ns.Refresh then ns.Refresh() end
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

local function migrate(db)
    if db.buffs == false and next(db.track) == nil then
        for _, list in pairs(ns.BUFFS) do
            for _, b in ipairs(list) do db.track[b.key] = false end
        end
    end
    -- The old "not in towns" switch hid every icon in a capital; the new default shows them.
    db.buffs, db.notResting = nil, nil
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliRemindersDB = GulliRemindersDB or {}
        ns.db = GulliRemindersDB
        for k, v in pairs(ns.DEFAULTS) do
            if ns.db[k] == nil then ns.db[k] = type(v) == "table" and {} or v end
        end
        migrate(ns.db)
        for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "UNIT_AURA", "UNIT_INVENTORY_CHANGED", "BAG_UPDATE_DELAYED",
                             "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_UPDATE_RESTING", "UNIT_PET",
                             "PLAYER_DEAD", "PLAYER_UNGHOST", "PLAYER_ALIVE", "SPELLS_CHANGED" }) do
            self:RegisterEvent(e)
        end
        -- Buffs and weapon buffs run out without an event.
        C_Timer.NewTicker(10, soon)
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
SlashCmdList.GULLIREMINDERS = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "unlock" or msg == "lock" then
        ns.SetPref("locked", msg == "lock")
    elseif msg == "reset" then
        ns.SetPref("point", nil)
    else
        ns.Toggle()
    end
end

function GulliReminders_Toggle() ns.Toggle() end

-- The game icon of each switch, in the window and in the hub.
ns.OPT_ICON = {
    show = "Interface\\Icons\\Spell_Holy_MindVision",
    inRest = "Interface\\Icons\\Spell_Nature_Sleep",
    locked = "Interface\\Icons\\INV_Misc_Key_03",
    weapon = "Interface\\Icons\\INV_Stone_02",
    ammo = "Interface\\Icons\\INV_Ammo_Arrow_02",
    shards = "Interface\\Icons\\INV_Misc_Gem_Amethyst_02",
    soonMin = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    size = "Interface\\Icons\\INV_Misc_Spyglass_03",
    alpha = "Interface\\Icons\\Spell_Magic_LesserInvisibilty",
    labels = "Interface\\Icons\\INV_Misc_Note_01",
    vertical = "Interface\\Icons\\Ability_Rogue_Sprint",
    point = "Interface\\Icons\\INV_Misc_Map_01",
}

-- The same switches as in the window, so the Gulli Toolkit hub can show them.
local function option(key, label)
    return { label = label, icon = ns.OPT_ICON[key], get = function() return ns.db ~= nil and ns.db[key] == true end,
             set = function(on) if ns.db then ns.SetPref(key, on and true or false) end end }
end

if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({
        key = "Reminders",
        icon = "Interface\\AddOns\\Gulli-Reminders\\icon",
        slash = "/grm",
        open = function() ns.Toggle() end,
        window = function() return ns.Window and ns.Window() end,
        options = {
            option("show", ns.L.OPT_SHOW),
            option("locked", ns.L.OPT_LOCK),
            option("inRest", ns.L.OPT_REST),
        },
    })
end
