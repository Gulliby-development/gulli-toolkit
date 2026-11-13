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
        { key = "TOUCH", ids = { 2652 }, race = "Scourge" },      -- Touch of Weakness (Undead)
        { key = "SHADOWGUARD", ids = { 18137 }, race = "Troll" },
        { key = "FEAR_WARD", ids = { 6346 }, race = "Dwarf", on = false },
        { key = "SHADOWFORM", ids = { 15473 }, on = false },
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
        { key = "FURY", ids = { 25780 }, on = false, tank = true }, -- on by default for a tank
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
-- The pets a warlock can pick to be summoned by a click: Imp, Voidwalker, Succubus, Felhunter.
ns.WARLOCK_PETS = { 688, 697, 712, 691 }
local REVIVE_PET = 982
local WELL_FED = 19705 -- any Well Fed buff has this name
-- Buff foods, best first; the food the player set comes before them.
ns.FOOD = { 21023, 20452, 13928, 13931, 18254, 12218, 18045, 12216, 21217, 13929, 21072 }
-- Rogue poisons, best first (Instant, Deadly, Wound, Crippling, Mind-numbing).
ns.POISONS = { 8928, 8927, 8926, 6950, 6949, 6947, 20844, 8985, 8984, 2893, 2892,
               10922, 10921, 10920, 10918, 3776, 3775, 9186, 6951, 5237 }
-- Oils, sharpening stones and weightstones for any class, best first.
ns.WEAPON_ITEMS = { 18262, 20749, 20748, 20750, 20747, 20746, 20745, 20744,
                    12404, 7964, 2871, 2863, 2862, 12643, 7965, 3241, 3240, 3239 }
-- Group buffs other classes give: when one of them is in the group and you lack it, it is shown
-- with their name (the "others" switch). mana: only worth asking for with a mana bar.
ns.OTHERS = {
    { key = "FORTITUDE", class = "PRIEST", ids = { 1243, 21562 } },
    { key = "WILD", class = "DRUID", ids = { 1126, 21849 } },
    { key = "INTELLECT", class = "MAGE", ids = { 1459, 23028 }, mana = true },
    { key = "SPIRIT", class = "PRIEST", ids = { 14752, 27681 }, mana = true },
    { key = "BLESSING", class = "PALADIN", ids = { 19740, 19742, 20217, 20911, 25782, 25894, 25898, 25899 } },
}
ns.PLACES = { "always", "group", "instance" }
ns.ALERTS = { "off", "always", "instance" }
local MAIN_HAND = 16
local POISON_LEVEL = 20
local SOUL_SHARD = 6265
local AMMO_SLOT, OFF_HAND = 0, 17
local ITEM_WEAPON = 2

ns.DEFAULTS = {
    show = true, inRest = true, track = {}, weapon = true, ammo = true, shards = true, pet = true,
    ammoMin = 200, shardsMin = 3, soonMin = 3,
    locked = true, size = 40, alpha = 100, labels = true, vertical = false,
    anyWeapon = false, food = true, where = "always", whereItems = "instance", alert = "instance",
    durability = true, durMin = 20, bags = true, bagsMin = 2, others = false, custom = {},
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
ns.SpellNameOf, ns.SpellIconOf = spellName, spellIcon
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
local function secret(v) return issecretvalue and issecretvalue(v) or false end
local function now() return GetTime and GetTime() or 0 end

---- Camp Benefits and other auras that block a weaker buff ------------------------

-- Forever's camp gives stats in one aura (spell CAMP_SPELL, lines such as "First Aid Kit:
-- Stamina increased by 34."). The game refuses a weaker buff of the same stat ("A more
-- powerful spell is already active"), so such a buff is not missing.
ns.CAMP_SPELL = 1229741
-- Rank 1 id -> the stat it raises (1 Strength .. 5 Spirit) and { spell id, amount, level } per rank.
ns.STAT_BUFFS = {
    [1243] = { stat = 3, ranks = { { 1243, 3, 1 }, { 1244, 8, 12 }, { 1245, 20, 24 }, { 2791, 32, 36 },
                                   { 10937, 43, 48 }, { 10938, 54, 60 } } },       -- Fortitude
    [21562] = { stat = 3, ranks = { { 21562, 43, 48 }, { 21564, 54, 60 } } },   -- Prayer of Fortitude
    [14752] = { stat = 5, ranks = { { 14752, 17, 30 }, { 14818, 23, 40 }, { 14819, 33, 50 },
                                    { 27841, 40, 60 } } },                        -- Divine Spirit
    [27681] = { stat = 5, ranks = { { 27681, 40, 60 } } },                      -- Prayer of Spirit
    [1459] = { stat = 4, ranks = { { 1459, 2, 1 }, { 1460, 7, 14 }, { 1461, 15, 28 }, { 10156, 22, 42 },
                                   { 10157, 31, 56 } } },                         -- Arcane Intellect
    [23028] = { stat = 4, ranks = { { 23028, 31, 56 } } },                      -- Arcane Brilliance
}
local STAT_EN = { "Strength", "Agility", "Stamina", "Intellect", "Spirit" }
local BLOCK_SECONDS = 600

local function statOf(text)
    local low = text:lower()
    for i = 1, 5 do
        for _, n in ipairs({ _G["SPELL_STAT" .. i .. "_NAME"], STAT_EN[i] }) do
            if type(n) == "string" and n ~= "" and (text:find(n, 1, true) or low:find(n:lower(), 1, true)) then
                return i
            end
        end
    end
end

-- The unit's camp aura: stat -> amount, and the seconds it has left; nil without one.
function ns.CampStats(unit)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
    for i = 1, 40 do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
        if not ok or not a then return nil end
        if not secret(a.spellId) and a.spellId == ns.CAMP_SPELL then
            local e = a.expirationTime
            local left = (e and not secret(e) and e > 0) and (e - now()) or math.huge
            local stats = {}
            local tip = C_TooltipInfo and C_TooltipInfo.GetUnitBuffByAuraInstanceID and a.auraInstanceID
                and C_TooltipInfo.GetUnitBuffByAuraInstanceID(unit, a.auraInstanceID)
            for _, line in ipairs(tip and tip.lines or {}) do
                local t = line.leftText
                if type(t) == "string" and not secret(t) then
                    local s, n = statOf(t), nil
                    for d in t:gmatch("%d+") do n = tonumber(d) end
                    if s and n then stats[s] = math.max(stats[s] or 0, n) end
                end
            end
            return stats, left
        end
    end
end

-- What the buff of this rank 1 id gives: the best rank the player knows, else (asking
-- someone else) the best rank for the player's level.
function ns.BuffAmount(id)
    local e = ns.STAT_BUFFS[id]
    if not e then return nil end
    local best
    for _, r in ipairs(e.ranks) do
        if IsPlayerSpell and IsPlayerSpell(r[1]) then best = r[2] end
    end
    if not best then
        local level = UnitLevel and UnitLevel("player") or 60
        for _, r in ipairs(e.ranks) do
            if r[3] <= level then best = r[2] end
        end
    end
    return best, e.stat
end

-- True when the unit already has an equal or stronger effect of this buff's stat.
function ns.Covered(unit, id, low)
    local amount, stat = ns.BuffAmount(id)
    if not amount then return false end
    local stats, left = ns.CampStats(unit)
    return stats ~= nil and (stats[stat] or 0) >= amount and left > (low or 0)
end

-- A buff the game refused after a click ("A more powerful spell is already active") is left
-- alone while the camp aura lasts, or BLOCK_SECONDS when it is something else.
local bounced, lastClick = {}, {}

function ns.NoteClick(key)
    lastClick.key, lastClick.t = key, now()
end

function ns.Bounced(key)
    if not key then return end
    local _, left = ns.CampStats("player")
    bounced[key] = now() + ((left and left < math.huge) and left or BLOCK_SECONDS)
end

function ns.IsBounced(key)
    local t = bounced[key]
    if t and t > now() then return true end
    bounced[key] = nil
    return false
end

-- Called with each UI error; a refused cast right after a click blocks that reminder.
function ns.OnError(msg)
    if msg and msg == _G.SPELL_FAILED_AURA_BOUNCED and lastClick.key and now() - (lastClick.t or 0) < 1.5 then
        ns.Bounced(lastClick.key)
        lastClick.key = nil
        return true
    end
    return false
end

local function itemCount(id) return ((C_Item and C_Item.GetItemCount) or GetItemCount)(id) or 0 end
local function offHandWeapon()
    local id = GetInventoryItemID("player", OFF_HAND)
    if not id then return false end
    local classID = select(12, ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(id))
    return classID == ITEM_WEAPON
end
local function playerClass() return select(2, UnitClass("player")) end
local function itemName(id)
    local n = ((C_Item and C_Item.GetItemNameByID) or GetItemInfo or function() end)(id)
    return n
end
local function itemIcon(id)
    return ((C_Item and C_Item.GetItemIconByID) or GetItemIcon or function() end)(id)
end
ns.ItemName, ns.ItemIcon = itemName, itemIcon
-- The name of the buff an item gives (its use spell), or nil.
local function itemSpell(id)
    local f = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    return f and (f(id)) or nil
end
ns.ItemSpell = itemSpell
-- The first item of the list that is in the bags.
local function firstInBags(list, preferred)
    if preferred and itemCount(preferred) > 0 then return preferred end
    for _, id in ipairs(list) do
        if itemCount(id) > 0 then return id end
    end
end

local function role()
    return UnitGroupRolesAssigned and UnitGroupRolesAssigned("player") or "NONE"
end

function ns.Tracked(b)
    local v = ns.db and ns.db.track[b.key]
    if v == nil then
        if b.tank and role() == "TANK" then return true end
        return b.on ~= false
    end
    return v
end

-- Does a reminder for this place setting show here? always | group | instance.
function ns.PlaceOK(w)
    if w == "group" then return (IsInGroup and IsInGroup()) and true or false end
    if w == "instance" then
        if not IsInInstance then return false end
        local inside, kind = IsInInstance()
        return inside and (kind == "party" or kind == "raid") or false
    end
    return true
end

-- The weakest equipped item, in percent of its durability; nil when nothing can break.
function ns.Durability()
    if not GetInventoryItemDurability then return nil end
    local low
    for slot = 1, 18 do
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max and max > 0 then
            local pct = cur / max * 100
            if not low or pct < low then low = pct end
        end
    end
    return low
end

-- Free slots in the general bags (not in a quiver, a soul bag or a herb bag).
function ns.FreeSlots()
    local get = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
    if not get then return nil end
    local free = 0
    for bag = 0, 4 do
        local n, kind = get(bag)
        if n and (kind == nil or kind == 0) then free = free + n end
    end
    return free
end

-- The spell a click on the pet icon casts: revive a dead hunter pet, else the pet the player picked.
local function petAction(class)
    if class == "HUNTER" and UnitExists("pet") and UnitIsDead("pet") and knows(REVIVE_PET) then
        return REVIVE_PET
    end
    if class == "WARLOCK" then
        local want = ns.db and ns.db.lockPet
        if want and knows(want) then return want end
    end
    return ns.PET_SPELL[class]
end

-- Applies a weapon item to the main hand.
local function weaponMacro(id)
    return { type = "macro", macrotext = "/use item:" .. id .. "\n/use " .. MAIN_HAND }
end

-- The class's buffs for the settings: { key, ids, on, known (a spell id or nil), name, icon }.
-- A racial buff (race = the second value of UnitRace) is listed only for that race or when known.
function ns.ClassBuffs(class)
    local out = {}
    local race = UnitRace and select(2, UnitRace("player"))
    for _, b in ipairs(ns.BUFFS[class or playerClass()] or {}) do
        local known
        for _, id in ipairs(b.ids) do
            if knows(id) then known = id; break end
        end
        if not b.race or known or b.race == race then out[#out + 1] = { key = b.key, ids = b.ids, on = b.on, tank = b.tank, known = known, name = L["BUFF_" .. b.key],
                          icon = spellIcon(known or b.ids[1]) } end
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
    local here, items = ns.PlaceOK(db.where), ns.PlaceOK(db.whereItems)
    local function cast(id) return { type = "spell", spell = spellName(id) } end
    for _, b in ipairs(here and ns.ClassBuffs(class) or {}) do
        if b.known and ns.Tracked(b) then
            local best
            for _, id in ipairs(b.ids) do
                local left = have[spellName(id) or ""]
                if left == false then best = false; break end
                if left and (not best or left > best) then best = left end
            end
            local id1 = b.ids[1]
            if best ~= false and (ns.IsBounced(b.key) or ns.Covered("player", id1, soon)) then
                best = false -- a stronger effect is on: nothing to cast
            end
            if best == nil then
                out[#out + 1] = { key = b.key, text = b.name, icon = spellIcon(b.known), act = cast(b.known) }
            elseif best and best < soon then
                out[#out + 1] = { key = b.key, text = b.name, icon = spellIcon(b.known), left = best, act = cast(b.known) }
            end
        end
    end
    local hasMain, mainLeft, _, _, hasOff, offLeft = GetWeaponEnchantInfo()
    local limit = math.max(60, soon) * 1000
    local function weak(has, left) return not has or (left or 0) < limit end
    if db.weapon and here then
        local need, act
        if class == "ROGUE" and level >= POISON_LEVEL then
            need = weak(hasMain, mainLeft) or (offHandWeapon() and weak(hasOff, offLeft))
            local id = firstInBags(ns.POISONS)
            if id then
                -- The main hand first; when it is fine, the off hand.
                act = weak(hasMain, mainLeft) and weaponMacro(id)
                    or { type = "macro", macrotext = "/use item:" .. id .. "\n/use " .. OFF_HAND }
            end
        elseif ns.IMBUES[class] then
            local best
            for _, id in ipairs(ns.IMBUES[class]) do
                if knows(id) then best = db.imbue and knows(db.imbue) and db.imbue or id end
            end
            if best then need = weak(hasMain, mainLeft); act = cast(best) end
        end
        if need then
            local left = hasMain and mainLeft and mainLeft > 0 and mainLeft / 1000 or nil
            out[#out + 1] = { key = "WEAPON", text = L.WEAPON, icon = "Interface\\Icons\\Trade_BrewPoison", left = left, act = act }
        end
    end
    -- Oils and stones for any class, with the consumables.
    if db.anyWeapon and items and not (db.weapon and (class == "ROGUE" or ns.IMBUES[class]))
        and GetInventoryItemID("player", MAIN_HAND) and weak(hasMain, mainLeft) then
        local id = firstInBags(ns.WEAPON_ITEMS)
        local left = hasMain and mainLeft and mainLeft > 0 and mainLeft / 1000 or nil
        out[#out + 1] = { key = "WEAPON_ITEM", text = L.WEAPON_ITEM, icon = id and itemIcon(id) or "Interface\\Icons\\INV_Stone_02",
                          left = left, act = id and weaponMacro(id) or nil, none = not id }
    end
    local pet = ns.PET_SPELL[class]
    if db.pet and here and pet and knows(pet) and not (IsMounted and IsMounted())
        and (not UnitExists("pet") or UnitIsDead("pet")) then
        local id = petAction(class)
        out[#out + 1] = { key = "PET", text = L.PET, icon = spellIcon(id), act = cast(id) }
    end
    if db.ammo and here and class == "HUNTER" then
        local n = GetInventoryItemCount("player", AMMO_SLOT) or 0
        if n < db.ammoMin then
            out[#out + 1] = { key = "AMMO", text = L.AMMO:format(n), icon = "Interface\\Icons\\INV_Ammo_Arrow_02",
                              buy = GetInventoryItemID("player", AMMO_SLOT), want = db.ammoMin - n }
        end
    end
    if db.shards and here and class == "WARLOCK" then
        local n = itemCount(SOUL_SHARD)
        if n < db.shardsMin then
            out[#out + 1] = { key = "SHARDS", text = L.SHARDS:format(n), icon = "Interface\\Icons\\INV_Misc_Gem_Amethyst_02" }
        end
    end
    if db.food and items then
        local left = have[spellName(WELL_FED) or ""]
        if left == nil or (left and left < soon) then
            local id = firstInBags(ns.FOOD, db.foodItem)
            out[#out + 1] = { key = "FOOD", text = L.FOOD, icon = id and itemIcon(id) or "Interface\\Icons\\INV_Misc_Food_14",
                              left = left or nil, act = id and { type = "item", item = "item:" .. id } or nil, none = not id }
        end
    end
    for i, c in ipairs(items and db.custom or {}) do
        local key = "CUSTOM" .. i
        if c.spell then
            local name = spellName(c.spell)
            local left = name and have[name]
            if name and knows(c.spell) and (left == nil or (left and left < soon)) then
                out[#out + 1] = { key = key, text = name, icon = spellIcon(c.spell), left = left or nil, act = cast(c.spell) }
            end
        elseif c.kind == "count" then
            local n = itemCount(c.id)
            if n < (c.min or 1) then
                out[#out + 1] = { key = key, text = L.COUNT:format(itemName(c.id) or ("#" .. c.id), n, c.min or 1),
                                  icon = itemIcon(c.id), buy = c.id, want = (c.min or 1) - n }
            end
        else
            local buff = itemSpell(c.id)
            local left = buff and have[buff]
            if left == nil or (left and left < soon) then
                local n = itemCount(c.id)
                out[#out + 1] = { key = key, text = itemName(c.id) or ("#" .. c.id), icon = itemIcon(c.id), left = left or nil,
                                  act = n > 0 and { type = "item", item = "item:" .. c.id } or nil, none = n == 0 }
            end
        end
    end
    if here and db.durability then
        local pct = ns.Durability()
        if pct and pct < db.durMin then
            out[#out + 1] = { key = "DURABILITY", text = L.DURABILITY:format(math.floor(pct)),
                              icon = "Interface\\Icons\\Trade_BlackSmithing" }
        end
    end
    if here and db.bags then
        local free = ns.FreeSlots()
        if free and free < db.bagsMin then
            out[#out + 1] = { key = "BAGS", text = L.BAGS:format(free), icon = "Interface\\Icons\\INV_Misc_Bag_08" }
        end
    end
    if db.others and here and IsInGroup and IsInGroup() then
        for _, o in ipairs(ns.OTHERS) do
            local mine = class == o.class
            local manaOK = not o.mana or not UnitPowerType or UnitPowerType("player") == 0
            if not mine and manaOK then
                local got
                for _, id in ipairs(o.ids) do
                    if have[spellName(id) or ""] ~= nil then got = true; break end
                end
                if not got and (ns.IsBounced("ASK_" .. o.key) or ns.Covered("player", o.ids[1], soon)) then got = true end
                local who = not got and ns.GroupMember(o.class)
                if who then
                    out[#out + 1] = { key = "ASK_" .. o.key, text = L.ASK:format(L["BUFF_" .. o.key], who),
                                      icon = spellIcon(o.ids[1]) }
                end
            end
        end
    end
    return out
end

-- The name of a living, online group member of this class, or nil.
function ns.GroupMember(class)
    local raid = IsInRaid and IsInRaid()
    local n = raid and GetNumGroupMembers() or (GetNumSubgroupMembers and GetNumSubgroupMembers() or 0)
    for i = 1, n do
        local unit = (raid and "raid" or "party") .. i
        local _, c = UnitClass(unit)
        if c == class and not UnitIsUnit(unit, "player") and UnitIsConnected(unit)
            and not UnitIsDeadOrGhost(unit) then
            return UnitName(unit)
        end
    end
end

-- The reminders that were not there at the last call, for the sound and the line on screen.
local seen = {}
function ns.NewOnes(list)
    local now, out = {}, {}
    for _, m in ipairs(list) do
        now[m.key] = true
        if not seen[m.key] and not m.sample then out[#out + 1] = m end
    end
    seen = now
    return out
end

-- Custom reminders: an item (its buff, or a count to keep in the bags) or a spell, by id.
function ns.AddItem(id)
    id = tonumber(id)
    if not id then return false end
    for _, c in ipairs(ns.db.custom) do if c.id == id then return false end end
    local kind = itemSpell(id) and "buff" or "count"
    table.insert(ns.db.custom, { id = id, kind = kind, min = kind == "count" and 5 or nil })
    if ns.Refresh then ns.Refresh() end
    return true
end

function ns.AddSpell(id)
    id = tonumber(id)
    if not id or not spellName(id) then return false end
    for _, c in ipairs(ns.db.custom) do if c.spell == id then return false end end
    table.insert(ns.db.custom, { spell = id })
    if ns.Refresh then ns.Refresh() end
    return true
end

function ns.RemoveCustom(i)
    table.remove(ns.db.custom, i)
    if ns.Refresh then ns.Refresh() end
end

function ns.SetCustom(i, field, value)
    local c = ns.db.custom[i]
    if not c then return end
    c[field] = value
    if field == "kind" and value == "count" and not c.min then c.min = 5 end
    if ns.Refresh then ns.Refresh() end
end

-- At an open vendor, buys what a count reminder lacks (whole stacks, never more than the money).
-- Returns how many it bought.
function ns.Buy(m)
    if not (m and m.buy and m.want and m.want > 0) then return 0 end
    if not (MerchantFrame and MerchantFrame:IsShown()) or not GetMerchantNumItems then return 0 end
    for i = 1, GetMerchantNumItems() do
        if GetMerchantItemID(i) == m.buy then
            local price, per
            if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
                local t = C_MerchantFrame.GetItemInfo(i)
                price, per = t and t.price, t and t.stackCount
            elseif GetMerchantItemInfo then
                local _
                _, _, price, per = GetMerchantItemInfo(i)
            end
            per = per or 1
            local each = (price or 0) / per
            local want = m.want
            if each > 0 then want = math.min(want, math.floor(GetMoney() / each)) end
            local stack = GetMerchantItemMaxStack and GetMerchantItemMaxStack(i) or want
            local bought = 0
            while want > 0 do
                local n = math.min(want, math.max(1, stack))
                BuyMerchantItem(i, n)
                bought, want = bought + n, want - n
            end
            return bought
        end
    end
    return 0
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
    if ns.db.food then out[#out + 1] = { key = "FOOD", text = L.FOOD, icon = "Interface\\Icons\\INV_Misc_Food_14", sample = true } end
    for i, c in ipairs(ns.db.custom) do
        out[#out + 1] = { key = "CUSTOM" .. i, text = c.spell and spellName(c.spell) or itemName(c.id) or "?",
                          icon = c.spell and spellIcon(c.spell) or itemIcon(c.id), sample = true }
    end
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
f:SetScript("OnEvent", function(self, event, a1, a2)
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
                             "PLAYER_DEAD", "PLAYER_UNGHOST", "PLAYER_ALIVE", "SPELLS_CHANGED",
                             "GROUP_ROSTER_UPDATE", "ZONE_CHANGED_NEW_AREA", "UPDATE_INVENTORY_DURABILITY",
                             "MERCHANT_SHOW", "MERCHANT_CLOSED", "PLAYER_ROLES_ASSIGNED", "UI_ERROR_MESSAGE" }) do
            self:RegisterEvent(e)
        end
        -- Buffs and weapon buffs run out without an event.
        C_Timer.NewTicker(10, soon)
        return
    end
    if (event == "UNIT_AURA" or event == "UNIT_INVENTORY_CHANGED") and a1 ~= "player" then return end
    if event == "UI_ERROR_MESSAGE" then
        if not ns.OnError(a2) then return end
    end
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
    elseif msg:match("^item%s") or msg:match("^spell%s") then
        -- /grm item <id or link>, /grm spell <id>
        local kind, rest = msg:match("^(%a+)%s+(.+)$")
        local id = tonumber(rest:match("item:(%d+)") or rest:match("spell:(%d+)") or rest:match("(%d+)"))
        local ok = id and (kind == "item" and ns.AddItem(id) or kind == "spell" and ns.AddSpell(id))
        print("|cff9ad0ffGulli-Reminders|r: " .. (ok and L.ADDED or L.NOT_ADDED))
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
    anyWeapon = "Interface\\Icons\\INV_Potion_100",
    food = "Interface\\Icons\\INV_Misc_Food_14",
    durability = "Interface\\Icons\\Trade_BlackSmithing",
    bags = "Interface\\Icons\\INV_Misc_Bag_08",
    others = "Interface\\Icons\\Spell_Holy_PrayerOfHealing02",
    where = "Interface\\Icons\\INV_Misc_Map_01",
    whereItems = "Interface\\Icons\\INV_Drink_05",
    alert = "Interface\\Icons\\INV_Misc_Bell_01",
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
            option("food", ns.L.OPT_FOOD),
        },
        move = function(on) if ns.db then ns.SetPref("locked", not on) end end,
        reset = function()
            if not ns.db then return end
            for k in pairs(ns.db) do ns.db[k] = nil end
            for k, v in pairs(ns.DEFAULTS) do ns.db[k] = type(v) == "table" and {} or v end
            if ns.Refresh then ns.Refresh() end
            if ns.RebuildWindow then ns.RebuildWindow() end
        end,
        summary = function()
            if not ns.db then return nil end
            local list, why = ns.Missing()
            if why then return nil end
            if #list == 0 then return ns.L.STATUS_NONE end
            return ns.L.SUMMARY:format(#list)
        end,
    })
end
