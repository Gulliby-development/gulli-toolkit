-- My BiS List: the best gear for each class, spec and level from the lists of wowtbc.gg, against
-- what the character wears and carries. It only reads the game; it never equips or buys anything.

local ADDON, ns = ...
local L = ns.L
local D = ns.Data

ns.DEFAULTS = { tooltip = true, notify = true, real = false, drop = true }
ns.ICON = "Interface\\AddOns\\Gulli-MyBisList\\icon"
ns.OPT_ICON = {
    tooltip = "Interface\\Icons\\INV_Misc_Note_01", notify = "Interface\\Icons\\INV_Misc_Bell_01",
    real = "Interface\\Icons\\INV_Misc_Coin_02", drop = "Interface\\Icons\\INV_Box_02",
}
ns.TOP = 3              -- a bag item this high on the list is worth a notice
-- The game's inventory slot of each list slot.
ns.INV = { head = 1, neck = 2, shoulder = 3, back = 15, chest = 5, wrist = 9, hands = 10, waist = 6, legs = 7,
           feet = 8, finger1 = 11, finger2 = 12, trinket1 = 13, trinket2 = 14, main = 16, off = 17, ranged = 18 }
-- Two slots that take the same items: what is worn goes where it ranks best.
ns.PAIR = { finger1 = "finger2", trinket1 = "trinket2" }
-- The talent tabs of each class, in the game's order, as our spec keys.
ns.TABS = {
    WARRIOR = { "WARRIOR_ARMS", "WARRIOR_FURY", "WARRIOR_PROTECTION" },
    PALADIN = { "PALADIN_HOLY", "PALADIN_PROTECTION", "PALADIN_RETRIBUTION" },
    HUNTER = { "HUNTER_BEASTMASTERY", "HUNTER_MARKSMANSHIP", "HUNTER_SURVIVAL" },
    ROGUE = { "ROGUE_ASSASSINATION", "ROGUE_COMBAT", "ROGUE_SUBTLETY" },
    PRIEST = { "PRIEST_DISCIPLINE", "PRIEST_HOLY", "PRIEST_SHADOW" },
    SHAMAN = { "SHAMAN_ELEMENTAL", "SHAMAN_ENHANCEMENT", "SHAMAN_RESTORATION" },
    MAGE = { "MAGE_ARCANE", "MAGE_FIRE", "MAGE_FROST" },
    WARLOCK = { "WARLOCK_AFFLICTION", "WARLOCK_DEMONOLOGY", "WARLOCK_DESTRUCTION" },
    DRUID = { "DRUID_BALANCE", "DRUID_FERALDPS", "DRUID_RESTORATION" },
}
-- The retail specialization ids, when the client has them.
ns.SPEC_ID = {
    [71] = "WARRIOR_ARMS", [72] = "WARRIOR_FURY", [73] = "WARRIOR_PROTECTION", [65] = "PALADIN_HOLY",
    [66] = "PALADIN_PROTECTION", [70] = "PALADIN_RETRIBUTION", [253] = "HUNTER_BEASTMASTERY",
    [254] = "HUNTER_MARKSMANSHIP", [255] = "HUNTER_SURVIVAL", [259] = "ROGUE_ASSASSINATION",
    [260] = "ROGUE_COMBAT", [261] = "ROGUE_SUBTLETY", [256] = "PRIEST_DISCIPLINE", [257] = "PRIEST_HOLY",
    [258] = "PRIEST_SHADOW", [262] = "SHAMAN_ELEMENTAL", [263] = "SHAMAN_ENHANCEMENT",
    [264] = "SHAMAN_RESTORATION", [62] = "MAGE_ARCANE", [63] = "MAGE_FIRE", [64] = "MAGE_FROST",
    [265] = "WARLOCK_AFFLICTION", [266] = "WARLOCK_DEMONOLOGY", [267] = "WARLOCK_DESTRUCTION",
    [102] = "DRUID_BALANCE", [103] = "DRUID_FERALDPS", [104] = "DRUID_FERALTANK", [105] = "DRUID_RESTORATION",
}
-- Each spec's own icon (the game's talent tree icons), on the spec button and in its picker.
ns.SPEC_ICON = {
    WARRIOR_ARMS = "Ability_Warrior_SavageBlow", WARRIOR_FURY = "Ability_Warrior_InnerRage",
    WARRIOR_PROTECTION = "Ability_Warrior_DefensiveStance", PALADIN_HOLY = "Spell_Holy_HolyBolt",
    PALADIN_PROTECTION = "Spell_Holy_DevotionAura", PALADIN_RETRIBUTION = "Spell_Holy_AuraOfLight",
    HUNTER_BEASTMASTERY = "Ability_Hunter_BeastTaming", HUNTER_MARKSMANSHIP = "Ability_Marksmanship",
    HUNTER_SURVIVAL = "Ability_Hunter_SwiftStrike", ROGUE_ASSASSINATION = "Ability_Rogue_Eviscerate",
    ROGUE_COMBAT = "Ability_BackStab", ROGUE_SUBTLETY = "Ability_Stealth",
    PRIEST_DISCIPLINE = "Spell_Holy_PowerWordShield", PRIEST_HOLY = "Spell_Holy_GuardianSpirit",
    PRIEST_SHADOW = "Spell_Shadow_ShadowWordPain", SHAMAN_ELEMENTAL = "Spell_Nature_Lightning",
    SHAMAN_ENHANCEMENT = "Spell_Nature_LightningShield", SHAMAN_RESTORATION = "Spell_Nature_MagicImmunity",
    MAGE_ARCANE = "Spell_Holy_MagicalSentry", MAGE_FIRE = "Spell_Fire_FireBolt02", MAGE_FROST = "Spell_Frost_FrostBolt02",
    WARLOCK_AFFLICTION = "Spell_Shadow_DeathCoil", WARLOCK_DEMONOLOGY = "Spell_Shadow_Metamorphosis",
    WARLOCK_DESTRUCTION = "Spell_Shadow_RainOfFire", DRUID_BALANCE = "Spell_Nature_StarFall",
    DRUID_FERALDPS = "Ability_Druid_CatForm", DRUID_FERALTANK = "Ability_Racial_BearForm",
    DRUID_RESTORATION = "Spell_Nature_HealingTouch",
}
function ns.SpecIcon(key)
    return "Interface\\Icons\\" .. (ns.SPEC_ICON[key] or "INV_Misc_QuestionMark")
end
ns.ROLE_ICON = { tank = "Interface\\Icons\\Ability_Warrior_DefensiveStance",
                 heal = "Interface\\Icons\\Spell_Holy_FlashHeal", dps = "Interface\\Icons\\Ability_DualWield" }
ns.SRC_ICON = {
    boss = "Interface\\Icons\\INV_Misc_Head_Dragon_01", quest = "Interface\\GossipFrame\\AvailableQuestIcon",
    rep = "Interface\\Icons\\INV_Misc_Note_02", craft = "Interface\\Icons\\Trade_BlackSmithing",
    pvp = "Interface\\Icons\\Ability_DualWield", vendor = "Interface\\Icons\\INV_Misc_Coin_02",
    fish = "Interface\\Icons\\Trade_Fishing", rare = "Interface\\Icons\\Ability_Hunter_SniperShot",
    zone = "Interface\\Icons\\INV_Misc_Map_01", world = "Interface\\Icons\\INV_Misc_Bag_10",
    other = "Interface\\Icons\\INV_Misc_Book_09", unknown = "Interface\\Icons\\INV_Misc_QuestionMark",
}

-- Game API wrappers -----------------------------------------------------------------------------

local CI = C_Item or {}

local function wornItem(slot)
    return GetInventoryItemID and GetInventoryItemID("player", ns.INV[slot]) or nil
end
local function itemCount(id)
    if CI.GetItemCount then return CI.GetItemCount(id, true) or 0 end
    return GetItemCount and GetItemCount(id, true) or 0
end
local function playerClass() local _, c = UnitClass("player"); return c end
local function playerLevel() return UnitLevel("player") or 1 end
local function playerSide()
    local f = UnitFactionGroup and UnitFactionGroup("player")
    return f == "Horde" and "H" or (f == "Alliance" and "A" or nil)
end

function ns.ItemName(id)
    local name = CI.GetItemNameByID and CI.GetItemNameByID(id)
    if name then return name end
    if CI.RequestLoadItemDataByID then CI.RequestLoadItemDataByID(id) end
    local it = D.item[id]
    return it and it[7] or (D.names and D.names[id]) or "..."
end
function ns.ItemIcon(id)
    return (CI.GetItemIconByID and CI.GetItemIconByID(id)) or "Interface\\Icons\\INV_Misc_QuestionMark"
end
function ns.ItemQuality(id)
    local it = D.item[id]
    return it and it[2] or (CI.GetItemQualityByID and CI.GetItemQualityByID(id)) or 1
end
ns.WornItem = wornItem

-- Enchants ----------------------------------------------------------------------------------------

-- Who makes an enchant (the data's kind): the icon of that trade, also the enchant's own icon
-- until the game gives one.
ns.ENCH_ICON = {
    ench = "Interface\\Icons\\Trade_Engraving", kit = "Interface\\Icons\\Trade_LeatherWorking",
    scope = "Interface\\Icons\\Trade_Engineering", arcanum = "Interface\\Icons\\INV_Misc_Book_11",
    other = "Interface\\Icons\\INV_Misc_Note_01",
}
local CS = C_Spell or {}
local function spellName(id)
    if CS.GetSpellName then return CS.GetSpellName(id) end
    if GetSpellInfo then return (GetSpellInfo(id)) end
end
local function spellIcon(id)
    if CS.GetSpellTexture then return (CS.GetSpellTexture(id)) end
    if GetSpellTexture then return (GetSpellTexture(id)) end
end
local function wornLink(slot)
    return GetInventoryItemLink and GetInventoryItemLink("player", ns.INV[slot]) or nil
end

-- Whether what is worn in a slot has an enchant: "on", "none", or nil with nothing worn. The item
-- link tells only that there is one, not which.
function ns.EnchantState(slot)
    local link = wornLink(slot)
    if type(link) ~= "string" then return nil end
    local e = link:match("item:%-?%d+:(%d*)")
    if not e then return nil end
    return (e ~= "" and e ~= "0") and "on" or "none"
end

-- The list's enchant of a slot: { id, name (the client's, else English), icon, kind, state }, or nil.
function ns.Enchant(list, slot)
    local e = list and list.ench and list.ench[slot]
    if not e then return nil end
    local kind = ns.ENCH_ICON[e[3]] and e[3] or "other"
    return { id = e[1], name = spellName(e[1]) or e[2], icon = spellIcon(e[1]) or ns.ENCH_ICON[kind],
             kind = kind, state = ns.EnchantState(slot) }
end

-- The slots of a list that take an enchant and how many of them have one on the worn item.
function ns.EnchantProgress(list)
    local have, of = 0, 0
    for _, slot in ipairs(D.slots) do
        if list.ench[slot] then
            of = of + 1
            if ns.EnchantState(slot) == "on" then have = have + 1 end
        end
    end
    return have, of
end

-- Specs and stages ----------------------------------------------------------------------------------

local SPEC = {}
for _, s in ipairs(D.specs) do SPEC[s[1]] = s end
function ns.SpecInfo(key) return SPEC[key] end

-- The specs of a class in the data's order.
function ns.Specs(class)
    local out = {}
    for _, s in ipairs(D.specs) do if s[2] == class then out[#out + 1] = s end end
    return out
end

function ns.SpecName(key)
    local s = SPEC[key]
    if not s then return key end
    return L["SPEC_" .. key:sub(#s[2] + 2)]
end
function ns.ClassName(class)
    local t = LOCALIZED_CLASS_NAMES_MALE
    return t and t[class] or (class:sub(1, 1) .. class:sub(2):lower())
end

-- The spec the character plays: the retail specialization, else the talent tab with the most
-- points, else the class's first. A feral druid is a cat until the player picks the bear.
function ns.DetectSpec()
    local class = playerClass()
    if GetSpecialization and GetSpecializationInfo then
        local i = GetSpecialization()
        local id = i and GetSpecializationInfo(i)
        if id and ns.SPEC_ID[id] then return ns.SPEC_ID[id] end
    end
    local tabs = ns.TABS[class]
    if tabs and GetTalentTabInfo then
        local best, most = nil, 0
        for i = 1, #tabs do
            local r = { pcall(GetTalentTabInfo, i) }
            if r[1] then
                local points = type(r[6]) == "number" and r[6] or (type(r[4]) == "number" and r[4]) or 0
                if points > most then best, most = tabs[i], points end
            end
        end
        if best then return best end
    end
    local first = ns.Specs(class)[1]
    return first and first[1] or D.specs[1][1]
end

function ns.MySpec()
    local key = ns.cdb and ns.cdb.spec
    if key and SPEC[key] and SPEC[key][2] == playerClass() then return key end
    return ns.DetectSpec()
end

function ns.SetMySpec(key)
    if not ns.cdb or not SPEC[key] then return end
    ns.cdb.spec = key
    if ns.Refresh then ns.Refresh() end
end

-- The list stage for a level: the level lists up to 50, then the pre-raid one.
function ns.AutoStage(level)
    level = level or playerLevel()
    if level <= 20 then return "L20" end
    if level <= 30 then return "L30" end
    if level <= 40 then return "L40" end
    if level <= 50 then return "L50" end
    return "PRE"
end

-- Lists ------------------------------------------------------------------------------------------------

-- A list is named by a ref: "auto" (the spec played, at the level's stage) or "site:SPEC:STAGE".
function ns.Ref(spec, stage) return "site:" .. spec .. ":" .. stage end
function ns.ParseRef(ref)
    if ref == "auto" or not ref then
        local stage = ns.AutoStage()
        if stage == "PRE" and ns.db and ns.db.real then stage = "REAL" end
        return ns.MySpec(), stage, true
    end
    local n = tonumber(ref:match("^own:(%d+)$"))
    if n then
        local own = ns.db and ns.db.own[n]
        if own and SPEC[own.spec] then return own.spec, own.stage, false, own, n end
        return nil
    end
    local spec, stage = ref:match("^site:([%u_]+):(%u[%u%d]*)$")
    if spec and SPEC[spec] and D.lists[spec] and D.lists[spec][stage] then return spec, stage, false end
    return nil
end

-- What the character can take: the items of the other faction leave the list and the rest move up.
function ns.Filter(ids, side)
    side = side or playerSide()
    local out = {}
    for _, id in ipairs(ids or {}) do
        local it = D.item[id]
        if it and not (side and it[6] and it[6] ~= side) then out[#out + 1] = id end
    end
    return out
end

-- The list behind a ref: { ref, spec, stage, auto, own, slots = { slot -> ids }, ench }. An own
-- list keeps what the player chose, other faction or not.
function ns.Resolve(ref)
    local spec, stage, auto, own, n = ns.ParseRef(ref)
    if not spec then return nil end
    local src = own and own.slots or (D.lists[spec] or {})[stage] or {}
    local list = { ref = ref or "auto", spec = spec, stage = stage, auto = auto, own = n, name = own and own.name,
                   slots = {}, ench = (D.ench[spec] or {})[stage] or {}, simmed = SPEC[spec][5] }
    for _, slot in ipairs(D.slots) do
        if src[slot] then
            if own then
                local copy = {}
                for i, id in ipairs(src[slot]) do copy[i] = id end
                list.slots[slot] = copy
            else
                list.slots[slot] = ns.Filter(src[slot])
            end
        end
    end
    return list
end

-- The site ref of a list, or its own ref.
function ns.RefOf(list)
    if not list then return nil end
    if list.own then return "own:" .. list.own end
    return ns.Ref(list.spec, list.stage)
end

function ns.StageName(stage) return L["STAGE_" .. stage] end
function ns.ListName(list)
    if list.own then return list.name or L.OWN_NAME:format(ns.SpecName(list.spec)) end
    return ns.SpecName(list.spec) .. " · " .. ns.StageName(list.stage)
end

function ns.MainRef() return ns.cdb and ns.cdb.main or "auto" end
function ns.SetMain(ref)
    if not ns.cdb then return end
    ns.cdb.main = ref or "auto"
    ns.told = nil
    if ns.Refresh then ns.Refresh() end
end
function ns.Main() return ns.Resolve(ns.MainRef()) or ns.Resolve("auto") end

-- The star: favourite lists, for the whole account.
function ns.IsFav(ref) return ns.db ~= nil and ns.db.fav[ref] == true end
function ns.SetFav(ref, on)
    if not ns.db or not ref or ref == "auto" then return end
    ns.db.fav[ref] = on and true or nil
    if ns.Refresh then ns.Refresh() end
end
function ns.Favs()
    local out = {}
    for ref in pairs(ns.db and ns.db.fav or {}) do
        local spec, stage, _, own = ns.ParseRef(ref)
        if spec and not own then out[#out + 1] = { ref = ref, spec = spec, stage = stage } end
    end
    table.sort(out, function(a, b) return a.ref < b.ref end)
    return out
end

-- Own lists -------------------------------------------------------------------------------------------
-- A copy of a site list the player edits, for the whole account: db.own[n] = { name, spec, stage,
-- slots = { slot -> ids }, from = the site ref, snap = { slot -> the site's first item then } }.

ns.OWN_MAX = 8          -- items a slot of an own list holds
ns.COPY_MAX = 5         -- items a copy takes from the site, like the site's own lists

-- Own lists in the order they were made: { ref, n, name, spec, stage }.
function ns.OwnLists()
    local out = {}
    for n, o in pairs(ns.db and ns.db.own or {}) do
        if SPEC[o.spec] then out[#out + 1] = { ref = "own:" .. n, n = n, name = o.name, spec = o.spec, stage = o.stage } end
    end
    table.sort(out, function(a, b) return a.n < b.n end)
    return out
end

local function firsts(list)
    local snap = {}
    for slot, ids in pairs(list.slots) do snap[slot] = ids[1] end
    return snap
end

-- Copies a list (a site list or an own one) into a new own list and returns its ref.
function ns.CopyList(ref)
    local list = ns.Resolve(ref)
    if not (list and ns.db) then return nil end
    local n = ns.db.ownNext or 1
    ns.db.ownNext = n + 1
    local from = list.own and ns.db.own[list.own].from or ns.Ref(list.spec, list.stage)
    local site = ns.Resolve(from)
    local slots = {}
    for slot, ids in pairs(list.slots) do
        local copy = {}
        for i, id in ipairs(ids) do if i <= ns.COPY_MAX then copy[#copy + 1] = id end end
        slots[slot] = copy
    end
    local base = list.own and list.name or ns.ListName(list)
    ns.db.own[n] = { name = L.OWN_NAME:format(base), spec = list.spec, stage = list.stage, slots = slots,
                     from = from, snap = site and firsts(site) or {} }
    if ns.Refresh then ns.Refresh() end
    return "own:" .. n
end

local function ownOf(ref)
    local n = tonumber(type(ref) == "string" and ref:match("^own:(%d+)$"))
    return n and ns.db and ns.db.own[n], n
end

function ns.RenameOwn(ref, name)
    local o = ownOf(ref)
    name = name and strtrim(name) or ""
    if not o or name == "" then return false end
    o.name = name:sub(1, 48)
    if ns.Refresh then ns.Refresh() end
    return true
end

-- Deletes an own list; returns what Undo needs. The star and the main list let go of it.
function ns.DeleteOwn(ref)
    local o, n = ownOf(ref)
    if not o then return nil end
    ns.db.own[n] = nil
    local fav = ns.db.fav[ref]
    ns.db.fav[ref] = nil
    local wasMain = ns.cdb and ns.cdb.main == ref
    if wasMain then ns.cdb.main = "auto" end
    if ns.view == ref then ns.view = nil end
    if ns.Refresh then ns.Refresh() end
    return { n = n, own = o, fav = fav, main = wasMain }
end

function ns.RestoreOwn(undo)
    if not (undo and ns.db) or ns.db.own[undo.n] then return end
    ns.db.own[undo.n] = undo.own
    local ref = "own:" .. undo.n
    ns.db.fav[ref] = undo.fav
    if undo.main and ns.cdb then ns.cdb.main = ref end
    if ns.Refresh then ns.Refresh() end
end

-- Adds an item to a slot (at the end, or at pos). False when the slot is full or has it already.
function ns.OwnAdd(ref, slot, id, pos)
    local o = ownOf(ref)
    if not (o and ns.INV[slot] and id) then return false end
    o.slots[slot] = o.slots[slot] or {}
    local ids = o.slots[slot]
    for _, x in ipairs(ids) do if x == id then return false end end
    if #ids >= ns.OWN_MAX then return false end
    table.insert(ids, math.min(pos or #ids + 1, #ids + 1), id)
    if ns.Refresh then ns.Refresh() end
    return true
end

function ns.OwnRemove(ref, slot, id)
    local o = ownOf(ref)
    local ids = o and o.slots[slot]
    if not ids then return false end
    for i, x in ipairs(ids) do
        if x == id then
            table.remove(ids, i)
            if ns.Refresh then ns.Refresh() end
            return true
        end
    end
    return false
end

-- Moves an item one place up (dir -1) or down (dir 1).
function ns.OwnMove(ref, slot, id, dir)
    local o = ownOf(ref)
    local ids = o and o.slots[slot]
    if not ids then return false end
    for i, x in ipairs(ids) do
        local j = i + dir
        if x == id and ids[j] then
            ids[i], ids[j] = ids[j], ids[i]
            if ns.Refresh then ns.Refresh() end
            return true
        end
    end
    return false
end

-- The own list to change instead of a site list: the one copied from it, made the first time.
-- It becomes the main list and the one shown.
function ns.OwnFor(ref)
    local list = ns.Resolve(ref)
    if not (list and ns.db) then return nil end
    if list.own then return ref end
    local site = ns.Ref(list.spec, list.stage)
    local mine
    for _, o in ipairs(ns.OwnLists()) do
        if ns.db.own[o.n].from == site then mine = o.ref; break end
    end
    mine = mine or ns.CopyList(site)
    if not mine then return nil end
    ns.SetMain(mine)
    if ns.ViewRefSet then ns.ViewRefSet(mine) end
    return mine
end

-- Adds an item at the end of a slot; a site list adds it to its own copy.
function ns.AddTo(ref, slot, id)
    local mine = ns.OwnFor(ref)
    return mine ~= nil and ns.OwnAdd(mine, slot, id), mine
end

-- An item id from what the player typed: a number or an item link.
function ns.ParseId(text)
    text = text or ""
    local id = tonumber(text:match("item:(%d+)") or text:match("^%s*(%d+)%s*$"))
    if id and id > 0 then return id end
end

-- Makes an item the first of a slot ("My target"). On an own list it moves or comes to the top
-- (the last one leaves when the slot is full). On a site list the item goes into the own list
-- copied from it, made the first time; that list becomes the main one and the one shown.
function ns.SetTarget(ref, slot, id)
    local list = ns.Resolve(ref)
    if not (list and id and ns.INV[slot] and ns.db) then return nil end
    if not list.own then
        local mine = ns.OwnFor(ref)
        return mine and ns.SetTarget(mine, slot, id)
    end
    local o = ownOf(ref)
    o.slots[slot] = o.slots[slot] or {}
    local ids = o.slots[slot]
    for i = #ids, 1, -1 do if ids[i] == id then table.remove(ids, i) end end
    table.insert(ids, 1, id)
    while #ids > ns.OWN_MAX do table.remove(ids) end
    if ns.Refresh then ns.Refresh() end
    return ref
end

-- The slots whose first site item changed since the own list was copied or last looked at.
function ns.SiteNews(ref)
    local o = ownOf(ref)
    local site = o and ns.Resolve(o.from)
    if not site then return {} end
    local out = {}
    for _, slot in ipairs(D.slots) do
        local now = (site.slots[slot] or {})[1]
        if now and now ~= o.snap[slot] then out[#out + 1] = slot end
    end
    return out
end

function ns.AckNews(ref)
    local o = ownOf(ref)
    local site = o and ns.Resolve(o.from)
    if site then o.snap = firsts(site) end
    if ns.Refresh then ns.Refresh() end
end

-- What a class can wear and wield (Vanilla rules; the shield and off-hand weapons by class).
ns.ARMOR = {
    WARRIOR = { plate = 1, mail = 2, leather = 3, cloth = 4 }, PALADIN = { plate = 1, mail = 2, leather = 3, cloth = 4 },
    HUNTER = { mail = 1, leather = 2, cloth = 3 }, SHAMAN = { mail = 1, leather = 2, cloth = 3 },
    ROGUE = { leather = 1, cloth = 2 }, DRUID = { leather = 1, cloth = 2 },
    PRIEST = { cloth = 1 }, MAGE = { cloth = 1 }, WARLOCK = { cloth = 1 },
}
local function set(list) local t = {} for w in list:gmatch("[^,]+") do t[w] = true end return t end
ns.WEAPON = {
    WARRIOR = set("axe,dagger,fist weapon,mace,sword,polearm,staff,shield,bow,crossbow,gun,thrown"),
    PALADIN = set("axe,mace,sword,polearm,shield,libram,held"),
    HUNTER = set("axe,dagger,fist weapon,sword,polearm,staff,bow,crossbow,gun,thrown"),
    ROGUE = set("dagger,fist weapon,mace,sword,bow,crossbow,gun,thrown"),
    PRIEST = set("dagger,mace,staff,wand,held"),
    SHAMAN = set("axe,dagger,fist weapon,mace,staff,shield,totem,held"),
    MAGE = set("dagger,sword,staff,wand,held"),
    WARLOCK = set("dagger,sword,staff,wand,held"),
    DRUID = set("dagger,fist weapon,mace,staff,polearm,idol,held"),
}
ns.DUAL = { WARRIOR = true, ROGUE = true, HUNTER = true }

-- Whether an item can go into a slot of a class's list.
function ns.Fits(class, slot, id)
    local it = D.item[id]
    if not it then return false end
    local code, kind = it[1], it[8] or ""
    local base = slot:gsub("%d$", "")
    if base == "main" then
        if not (code == "2h" or code == "mh" or code == "1h") then return false end
    elseif base == "off" then
        if code == "held" then return ns.WEAPON[class].held == true end
        if code == "oh" and kind == "shield" then return ns.WEAPON[class].shield == true end
        if not (code == "oh" or code == "1h") or not ns.DUAL[class] then return false end
    elseif base == "ranged" then
        if code ~= "ranged" and code ~= "relic" then return false end
    else
        if code ~= base then return false end
        if ns.ARMOR[class][kind] then return true end
        return kind == "" or (base == "back" and kind == "cloth")
    end
    return ns.WEAPON[class][kind] == true
end

local function fold(t) return (t or ""):lower() end

-- The items that fit a slot of an own list and are not in it, for its search: the items of the
-- spec's own site lists first, then of the class's other specs, then the rest; the best item level
-- first. Matches the client's name and the English one.
function ns.Candidates(ref, slot, query)
    local list = ns.Resolve(ref)
    if not list then return {} end
    local class = SPEC[list.spec][2]
    local have, weight = {}, {}
    for _, id in ipairs(list.slots[slot] or {}) do have[id] = true end
    for _, s in ipairs(D.specs) do
        if s[2] == class then
            for _, l in pairs(D.lists[s[1]] or {}) do
                for _, ids in pairs(l) do
                    for _, id in ipairs(ids) do
                        local w = s[1] == list.spec and 2 or 1
                        if (weight[id] or 0) < w then weight[id] = w end
                    end
                end
            end
        end
    end
    local side = playerSide()
    local out = {}
    -- an id or a link: that item first, whatever list or slot it comes from (the player knows it)
    local typed = ns.ParseId(query)
    if typed and not have[typed] then out[1] = typed end
    if (query or ""):find("|H") then return out end
    query = fold(query)
    for id, it in pairs(D.item) do
        if not have[id] and id ~= typed and not (side and it[6] and it[6] ~= side) and ns.Fits(class, slot, id) then
            local ok = query == "" or fold(it[7]):find(query, 1, true) or fold(ns.ItemName(id)):find(query, 1, true)
                or tostring(id) == query
            if ok then out[#out + 1] = id end
        end
    end
    table.sort(out, function(a, b)
        local wa, wb = weight[a] or 0, weight[b] or 0
        if wa ~= wb then return wa > wb end
        local ia, ib = D.item[a][3] or 0, D.item[b][3] or 0
        if ia ~= ib then return ia > ib end
        return a < b
    end)
    return out
end

-- Slots against what is worn and carried ---------------------------------------------------------

local function rankOf(ids, id)
    if not id then return nil end
    for i, x in ipairs(ids) do if x == id then return i end end
end

-- The best item of a list the character has in the bags or the bank and does not wear.
local function owned(ids, wornIds)
    for i, id in ipairs(ids) do
        local n = itemCount(id) - (wornIds[id] or 0)
        if n > 0 then return id, i end
    end
end

-- Whether an item is carried (bags or bank) besides what is worn.
function ns.Carried(id)
    local n = itemCount(id)
    for _, slot in ipairs(D.slots) do if wornItem(slot) == id then n = n - 1 end end
    return n > 0
end

local function isTwoHand(id) local it = id and D.item[id]; return it ~= nil and it[1] == "2h" end

-- One row per slot: { slot, ids, worn, rank, have, haveRank, counted, state }.
-- state: "bis" the first is worn, "bag" a better one is carried, "rank" worn but not the first,
-- "miss" what is worn is not on the list, "none" the list has no such slot, "covered" the
-- weapon is a two-hander.
function ns.SlotRows(list)
    local worn, wornIds = {}, {}
    for _, slot in ipairs(D.slots) do
        local id = wornItem(slot)
        worn[slot] = id
        if id then wornIds[id] = (wornIds[id] or 0) + 1 end
    end
    -- rings and trinkets: what is worn goes to the slot where it ranks best
    for a, b in pairs(ns.PAIR) do
        local la, lb = list.slots[a] or {}, list.slots[b] or {}
        local wa, wb = worn[a], worn[b]
        local function cost(x, y) return (rankOf(la, x) or 99) + (rankOf(lb, y) or 99) end
        if cost(wb, wa) < cost(wa, wb) then worn[a], worn[b] = wb, wa end
    end
    local rows = {}
    local mainTop = (list.slots.main or {})[1]
    for _, slot in ipairs(D.slots) do
        local ids = list.slots[slot] or {}
        local r = { slot = slot, ids = ids, worn = worn[slot], counted = #ids > 0 }
        r.rank = rankOf(ids, r.worn)
        r.have, r.haveRank = owned(ids, wornIds)
        -- where the list's first item is: worn, in the bags or the bank, or not found
        r.top = ids[1]
        if r.top then
            r.topAt = (r.rank == 1 and "worn") or (itemCount(r.top) - (wornIds[r.top] or 0) > 0 and "bag") or "miss"
        end
        if slot == "off" and isTwoHand(mainTop) then
            r.state, r.counted = "covered", false
        elseif #ids == 0 then
            r.state = "none"
        elseif r.rank == 1 then
            r.state = "bis"
        elseif r.haveRank and (not r.rank or r.haveRank < r.rank) then
            r.state = "bag"
        elseif r.rank then
            r.state = "rank"
        else
            r.state = "miss"
        end
        rows[#rows + 1] = r
    end
    return rows
end

function ns.Progress(list)
    local have, of = 0, 0
    for _, r in ipairs(ns.SlotRows(list)) do
        if r.counted then
            of = of + 1
            if r.state == "bis" then have = have + 1 end
        end
    end
    return have, of
end

-- Where an item comes from, as one short line and the kind of source.
function ns.SourceText(id)
    local it = D.item[id]
    local s = it and D.src[it[5]]
    if not s then return "", "unknown" end
    local kind, what, where = s[1], s[2], s[3]
    if kind == "boss" then
        local dg = where ~= "" and (GulliDungeonJournal and GulliDungeonJournal.Name and GulliDungeonJournal.Name(where)
            or D.dungeons[where]) or L.SRC_DUNGEONS
        return what ~= "" and (what .. " · " .. dg) or dg, kind
    elseif kind == "quest" then
        return L.SRC_QUEST:format(what), kind
    elseif kind == "rep" then
        return where ~= "" and (what .. " · " .. where) or what, kind
    elseif kind == "craft" then
        return L.SRC_CRAFT:format(what), kind
    elseif kind == "pvp" then
        return L.SRC_PVP, kind
    elseif kind == "vendor" then
        if what == "" then return L.SRC_VENDORS, kind end
        return where ~= "" and (what .. " · " .. where) or what, kind
    elseif kind == "fish" then
        return L.SRC_FISH, kind
    elseif kind == "rare" then
        return where ~= "" and L.SRC_RARE:format(what, where) or what, kind
    elseif kind == "zone" then
        return what ~= "" and (what .. " · " .. where) or where, kind
    elseif kind == "world" then
        return L.SRC_WORLD, kind
    elseif kind == "other" then
        return what, kind
    end
    return "", "unknown"
end

-- The short form of a source, for a narrow row: the dungeon, the faction or the trade alone.
function ns.SourcePlace(id)
    local it = D.item[id]
    local s = it and D.src[it[5]]
    if not s then return "" end
    if s[1] == "boss" and s[3] ~= "" then
        return GulliDungeonJournal and GulliDungeonJournal.Name and GulliDungeonJournal.Name(s[3]) or D.dungeons[s[3]] or ""
    elseif s[1] == "rep" or s[1] == "craft" then
        return s[2]
    elseif s[1] == "zone" then
        return s[3]
    end
    return (ns.SourceText(id))
end

-- The dungeon an item drops in (a Dungeon Journal key), when it does.
function ns.DungeonOf(id)
    local it = D.item[id]
    local s = it and D.src[it[5]]
    if s and s[1] == "boss" and s[3] ~= "" then return s[3] end
end

-- The level the game asks for, when the character has not reached it.
function ns.NeedsLevel(id)
    local it = D.item[id]
    if it and it[4] and it[4] > playerLevel() then return it[4] end
end

-- Item sets ------------------------------------------------------------------------------------------

-- The groups of the Sets tab, in the window's order, and the kinds of the data in each.
ns.SET_GROUPS = { { "DUNGEON", { t0 = true, t05 = true } }, { "PVP", { pvp = true } },
                  { "CLASS", { class = true } }, { "ANY", { any = true } } }
ns.SET_ICON = "Interface\\Icons\\INV_Helmet_08"
ns.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
-- The game's equip location -> the data's slot code.
local EQUIP = {
    INVTYPE_HEAD = "head", INVTYPE_NECK = "neck", INVTYPE_SHOULDER = "shoulder", INVTYPE_CLOAK = "back",
    INVTYPE_CHEST = "chest", INVTYPE_ROBE = "chest", INVTYPE_WRIST = "wrist", INVTYPE_HAND = "hands",
    INVTYPE_WAIST = "waist", INVTYPE_LEGS = "legs", INVTYPE_FEET = "feet", INVTYPE_FINGER = "finger",
    INVTYPE_TRINKET = "trinket", INVTYPE_2HWEAPON = "2h", INVTYPE_WEAPON = "1h", INVTYPE_WEAPONMAINHAND = "mh",
    INVTYPE_WEAPONOFFHAND = "oh", INVTYPE_SHIELD = "oh", INVTYPE_HOLDABLE = "held", INVTYPE_RANGED = "ranged",
    INVTYPE_RANGEDRIGHT = "ranged", INVTYPE_THROWN = "ranged", INVTYPE_RELIC = "relic",
}
-- The order of the slot codes on a set's page, how many pieces of one code a character wears at
-- once, and the list slots a code goes into.
local CODE_ORDER = { "head", "neck", "shoulder", "back", "chest", "wrist", "hands", "waist", "legs", "feet",
                     "finger", "trinket", "2h", "mh", "1h", "oh", "held", "ranged", "relic" }
local CODE_CAP = { finger = 2, trinket = 2, ["1h"] = 2 }
local CODE_SLOTS = { finger = { "finger1", "finger2" }, trinket = { "trinket1", "trinket2" }, ["2h"] = { "main" },
                     mh = { "main" }, ["1h"] = { "main", "off" }, oh = { "off" }, held = { "off" },
                     ranged = { "ranged" }, relic = { "ranged" } }
ns.CODE_SLOT = { finger = "finger1", trinket = "trinket1", ["2h"] = "main", mh = "main", ["1h"] = "main", oh = "off",
                 held = "off", relic = "ranged" }

local function itemInstant(id)
    if CI.GetItemInfoInstant then return CI.GetItemInfoInstant(id) end
    if GetItemInfoInstant then return GetItemInfoInstant(id) end
end
local function itemSetId(id)
    if CI.GetItemInfo then return (select(16, CI.GetItemInfo(id))) end
    if GetItemInfo then return (select(16, GetItemInfo(id))) end
end
local function setName(id)
    if CI.GetItemSetInfo then return CI.GetItemSetInfo(id) end
    if GetItemSetInfo then return (GetItemSetInfo(id)) end
end
local function tipLines(id)
    local data = C_TooltipInfo and C_TooltipInfo.GetItemByID and C_TooltipInfo.GetItemByID(id)
    return data and data.lines or nil
end
local function wornAll()
    local t = {}
    if GetInventoryItemID then
        for i = 1, 19 do
            local id = GetInventoryItemID("player", i)
            if id then t[id] = true end
        end
    end
    return t
end

-- The slot code of a set piece: the data's, else the game's.
function ns.PieceCode(id)
    local it = D.item[id]
    if it then return it[1] end
    local _, _, _, loc = itemInstant(id)
    return loc and EQUIP[loc] or nil
end

local SETS
local function setRow(id)
    if not SETS then
        SETS = {}
        for _, r in ipairs(D.sets or {}) do SETS[r[1]] = r end
    end
    return SETS[id]
end

-- The game's name of a set (asked through one of its pieces, so a wrong id never names another
-- set), else the English one.
function ns.SetName(id)
    local r = setRow(id)
    if not r then return "" end
    for _, piece in ipairs(r[8]) do
        local sid = itemSetId(piece)
        if sid and sid > 0 then
            local name = setName(sid)
            if name and name ~= "" then return name end
            break
        end
    end
    return r[2]
end

-- Whether a class sees a set: its own class sets, and the sets for anyone of its best armour
-- (or of no armour: rings, weapons), of the player's faction.
function ns.SetFits(r, class)
    local side = playerSide()
    if r[6] and side and r[6] ~= side then return false end
    if r[4] then return r[4] == class end
    return r[5] == "" or (ns.ARMOR[class] or {})[r[5]] == 1
end

-- The sets of a class for the list: { head = group key } and { set = id }, group by group.
function ns.SetList(class)
    local out = {}
    for _, g in ipairs(ns.SET_GROUPS) do
        local first = true
        for _, r in ipairs(D.sets or {}) do
            if g[2][r[3]] and ns.SetFits(r, class) then
                if first then out[#out + 1] = { head = g[1] }; first = false end
                out[#out + 1] = { set = r[1] }
            end
        end
    end
    return out
end

ns.setPick = {}         -- set id .. code -> the variant of a slot the player turned to

-- A set against what is worn and carried: { id, name, kind, class, from, groups, worn, of }.
-- A group is one place of the set: { code, ids (its variants), id (the one shown), at, worn, have,
-- step, from, fromHave }. A set with more pieces of a slot than a character wears has variants
-- (the tier 0.5 sets: one per role); the one shown is the worn one, the carried one, the one the
-- player turned to, the one on the list `on`, else the first.
function ns.SetInfo(id, on)
    local r = setRow(id)
    if not r then return nil end
    local worn = wornAll()
    local by, codes = {}, {}
    for _, piece in ipairs(r[8]) do
        local code = ns.PieceCode(piece) or "?"
        if not by[code] then by[code] = {}; codes[#codes + 1] = code end
        by[code][#by[code] + 1] = piece
    end
    local rank = {}
    for i, c in ipairs(CODE_ORDER) do rank[c] = i end
    table.sort(codes, function(a, b) return (rank[a] or 99) < (rank[b] or 99) end)
    local listed = {}
    if on then
        for _, ids in pairs(on.slots or {}) do
            for _, x in ipairs(ids) do listed[x] = true end
        end
    end
    local from = r[7] and setRow(r[7]) or nil
    local fromBy = {}
    if from then
        for _, piece in ipairs(from[8]) do fromBy[ns.PieceCode(piece) or "?"] = piece end
    end
    local groups = {}
    local function group(code, ids)
        local g = { code = code, ids = ids, at = 1 }
        local pick = ns.setPick[id .. code]
        for i, x in ipairs(ids) do
            if worn[x] then g.at, g.worn = i, true; break end
        end
        if not g.worn then
            for i, x in ipairs(ids) do
                if itemCount(x) > 0 then g.at, g.have = i, true; break end
            end
        end
        if not (g.worn or g.have) then
            if pick and ids[pick] then
                g.at = pick
            else
                for i, x in ipairs(ids) do
                    if listed[x] then g.at = i; break end
                end
            end
        end
        g.id = ids[g.at]
        g.step = D.setStep and D.setStep[g.id] or nil
        g.from = fromBy[code]
        g.fromHave = g.from ~= nil and (worn[g.from] or itemCount(g.from) > 0) or false
        groups[#groups + 1] = g
    end
    for _, code in ipairs(codes) do
        local ids = by[code]
        if #ids <= (CODE_CAP[code] or 1) then
            for _, x in ipairs(ids) do group(code, { x }) end
        else
            group(code, ids)
        end
    end
    local n = 0
    for _, g in ipairs(groups) do if g.worn then n = n + 1 end end
    return { id = id, name = ns.SetName(id), kind = r[3], class = r[4] or nil, armor = r[5], from = r[7] or nil,
             groups = groups, worn = n, of = #groups, counts = r[9] }
end

-- Turns a place of a set to its next variant.
function ns.SetTurn(id, code, n)
    local key = id .. code
    ns.setPick[key] = ((ns.setPick[key] or 1) % n) + 1
    if ns.Refresh then ns.Refresh() end
end

-- "(%d) Set: %s" -> a pattern.
local function linePattern(fmt)
    local p = fmt:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
    p = p:gsub("%%d", "(%%d+)"):gsub("%%s", "(.+)")
    return "^" .. p .. "$"
end

-- The bonuses of a set: { count, text, on }. The texts are the game's (read from a piece's
-- tooltip); until the game gives them, only the piece counts of the data, without a text.
function ns.SetBonuses(info)
    local out = {}
    local grey = linePattern(ITEM_SET_BONUS_GRAY or "(%d) Set: %s")
    local lit = linePattern(ITEM_SET_BONUS or "Set: %s")
    -- any piece tells them: the first one whose tooltip the client has
    for _, g in ipairs(info.groups) do
        for _, line in ipairs(tipLines(g.id) or {}) do
            local text = line.leftText
            if type(text) == "string" and not (issecretvalue and issecretvalue(text)) then
                text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                local n, what = text:match(grey)
                if not n then what = text:match(lit) end
                if what then out[#out + 1] = { count = tonumber(n), text = what } end
            end
        end
        if #out > 0 then break end
    end
    if #out == 0 then
        for _, n in ipairs(info.counts or {}) do out[#out + 1] = { count = n } end
    end
    for i, b in ipairs(out) do
        b.count = b.count or (info.counts or {})[i]
        b.on = b.count ~= nil and info.worn >= b.count
    end
    return out
end

-- The step of the tier 0.5 chain a set is at: the first quest whose pieces the character lacks,
-- { step, of, quest, codes }. Nil for another set, or when every piece is there.
function ns.SetChain(info)
    if info.kind ~= "t05" or not D.setSteps then return nil end
    for step, quest in ipairs(D.setSteps) do
        local codes = {}
        for _, g in ipairs(info.groups) do
            if g.step == step and not (g.worn or g.have) then codes[#codes + 1] = g.code end
        end
        if #codes > 0 then return { step = step, of = #D.setSteps, quest = quest, codes = codes } end
    end
end

-- Whether the character's class can wear a set (so its pieces can go on a list).
function ns.SetMine(info)
    local r = setRow(info.id)
    return r ~= nil and ns.SetFits(r, playerClass())
end

-- Puts the shown piece of every place of a set on a list (a site list: its own copy). Returns
-- how many were added.
function ns.SetAdd(info, ref)
    local n, used = 0, {}
    for _, g in ipairs(info.groups) do
        if not g.worn then
            for _, slot in ipairs(CODE_SLOTS[g.code] or { g.code }) do
                if ns.INV[slot] and not used[slot] then
                    used[slot] = true
                    local ok, mine = ns.AddTo(ref, slot, g.id)
                    ref = mine or ref
                    if ok then n = n + 1 end
                    break
                end
            end
        end
    end
    return n
end

-- Tooltip, notices, the hub ---------------------------------------------------------------------------

local function S_cap(t) return ns.Skin and ns.Skin.Cap and ns.Skin.Cap(t) or t end

-- Lines for an item's tooltip: its place on the main list and the place of what is worn there,
-- and the list's enchant of its slot (also for what is worn there and not on the list).
function ns.TipLines(id)
    if not ns.db or not ns.db.tooltip or ns.paused or not id then return nil end
    if not D.item[id] then
        local worn = false
        for slot in pairs(ns.INV) do if wornItem(slot) == id then worn = true; break end end
        if not worn then return nil end
    end
    local list = ns.Main()
    if not list then return nil end
    local S = ns.Skin
    local out = {}
    for _, r in ipairs(ns.SlotRows(list)) do
        local rank = rankOf(r.ids, id)
        local shown = false
        if rank and r.counted then
            local right
            if r.worn == id then right = L.TIP_WORN
            elseif r.rank then right = L.TIP_YOURS:format(r.rank)
            else right = L.TIP_YOURS_OFF end
            out[#out + 1] = { group = "note", icon = ns.ICON, left = S_cap(L.TIP_RANK:format(L["SLOT_" .. r.slot], rank, #r.ids)),
                              right = right, color = rank == 1 and S.GOLD or S.TEXT,
                              rcolor = r.worn == id and S.GOOD or S.MUTED, sub = #out > 0 }
            shown = true
        end
        local e = (shown or r.worn == id) and r.counted and ns.Enchant(list, r.slot) or nil
        if e then
            out[#out + 1] = { group = "note", icon = e.icon, left = S_cap(L.TIP_ENCH), right = e.name,
                              color = S.MUTED, rcolor = S.TEXT, sub = #out > 0 }
            if r.worn == id and e.state then
                local on = e.state == "on"
                out[#out + 1] = { group = "note", left = on and L.ENCH_ON or L.ENCH_NONE,
                                  color = on and S.GOOD or S.WARN, sub = true }
            end
        end
    end
    return #out > 0 and out or nil
end

local function toast(o)
    local S = ns.Skin
    if S and S.Toast then S.Toast(o) end
end

-- A list item that came into the bags and beats what is worn, told once per item.
function ns.CheckBags(first)
    if not ns.cdb or ns.paused then return 0 end
    local list = ns.Main()
    if not list then return 0 end
    local fresh = {}
    for _, r in ipairs(ns.SlotRows(list)) do
        if r.counted and r.state == "bag" and r.haveRank <= ns.TOP and not ns.cdb.told[r.have] then
            ns.cdb.told[r.have] = true
            fresh[#fresh + 1] = r
        end
    end
    if first or #fresh == 0 then return 0 end
    local r = fresh[1]
    local text = L.NEW_BAG:format(ns.ItemName(r.have), r.haveRank, L["SLOT_" .. r.slot])
    if GulliToolkit and GulliToolkit.Notify then GulliToolkit.Notify("MyBisList", text) end
    if ns.db.notify then
        toast({ key = "bag", icon = ns.ItemIcon(r.have), title = L.TITLE, text = text, seconds = 10,
                buttons = { { text = L.OPEN, onClick = function() ns.Show(r.slot) end } } })
    end
    return #fresh
end

-- A wanted item: on the main list, better than what is worn there and not carried yet.
-- Returns the slot and its place.
function ns.Wanted(id)
    if not id then return nil end
    local list = ns.Main()
    if not list or ns.Carried(id) then return nil end
    for _, r in ipairs(ns.SlotRows(list)) do
        local rank = rankOf(r.ids, id)
        if rank and r.state ~= "covered" and (not r.rank or rank < r.rank) then return r.slot, rank end
    end
end

local function linkId(link)
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

-- A wanted item in the loot window (also master loot) or in a roll: a sound and a notice, once a
-- minute per item.
function ns.CheckDrop(links)
    if not ns.db or not ns.db.drop or ns.paused then return 0 end
    ns.dropAt = ns.dropAt or {}
    local now, n = GetTime and GetTime() or 0, 0
    for _, link in ipairs(links) do
        local id = linkId(link)
        local slot, rank = ns.Wanted(id)
        if slot and not (ns.dropAt[id] and now - ns.dropAt[id] < 60) then
            ns.dropAt[id] = now
            n = n + 1
            if n == 1 then
                if PlaySound then PlaySound((SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, "Master") end
                local text = L.DROP:format(ns.ItemName(id), rank, L["SLOT_" .. slot])
                if GulliToolkit and GulliToolkit.Notify then GulliToolkit.Notify("MyBisList", text) end
                toast({ key = "drop", icon = ns.ItemIcon(id), title = L.TITLE, text = text, seconds = 12 })
            end
        end
    end
    return n
end

local function lootLinks()
    local out = {}
    local count = GetNumLootItems and GetNumLootItems() or 0
    for i = 1, count do
        local link = GetLootSlotLink and GetLootSlotLink(i)
        if link then out[#out + 1] = link end
    end
    return out
end

-- The hub's home line: "BiS 6/17 · Protection", with the number for its tile.
function ns.Summary()
    if not ns.db or ns.paused then return nil end
    local list = ns.Main()
    if not list then return nil end
    local have, of = ns.Progress(list)
    if of == 0 then return nil end
    return L.SUM:format(have, of, ns.SpecName(list.spec)), ns.ICON,
        { value = have .. "/" .. of, label = ns.SpecName(list.spec), pips = { have, of }, quiet = have == of }
end

-- Settings ----------------------------------------------------------------------------------------

function ns.SetPref(key, value)
    if not ns.db then return end
    ns.db[key] = value
    if ns.Refresh then ns.Refresh() end
end

function ns.Reset()
    for k, v in pairs(ns.DEFAULTS) do ns.db[k] = v end
    if ns.Refresh then ns.Refresh() end
end

-- The hub's switch: a paused module adds no tooltip line and tells nothing.
function ns.Pause(on)
    ns.paused = on and true or false
    if ns.Refresh then ns.Refresh() end
end

-- Slash command -------------------------------------------------------------------------------------

function ns.Slash(msg)
    local cmd = strtrim(msg or ""):lower()
    if cmd == "reset" then
        ns.Reset()
        print(L.TITLE .. ": " .. L.RESET_DONE)
    elseif cmd == "help" then
        print(L.TITLE .. ": " .. L.HELP)
    else
        ns.Toggle()
    end
end

-- Events ----------------------------------------------------------------------------------------------

-- Bag, gear and item news come in bursts: one refresh a moment later.
local function later()
    if ns.pending then return end
    ns.pending = true
    C_Timer.After(0.5, function()
        ns.pending = nil
        if ns.paused then return end
        if ns.Refresh then ns.Refresh() end
        ns.CheckBags(not ns.looked)
        ns.looked = true
    end)
end
ns.Later = later

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliMyBisListDB = GulliMyBisListDB or {}
        GulliMyBisListCharDB = GulliMyBisListCharDB or {}
        ns.db, ns.cdb = GulliMyBisListDB, GulliMyBisListCharDB
        for k, v in pairs(ns.DEFAULTS) do
            if ns.db[k] == nil then ns.db[k] = v end
        end
        ns.db.fav = ns.db.fav or {}
        ns.db.own = ns.db.own or {}
        ns.cdb.told = ns.cdb.told or {}
        ns.cdb.main = ns.cdb.main or "auto"
        for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED",
                             "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "GET_ITEM_INFO_RECEIVED", "LOOT_READY",
                             "START_LOOT_ROLL" }) do
            self:RegisterEvent(e)
        end
        return
    end
    if event == "PLAYER_LOGIN" then
        local S = ns.Skin
        if S and S.TipProvider then S.TipProvider("item", "MyBisList", function(id) return ns.TipLines(id) end) end
        return
    end
    if ns.paused then return end
    if event == "LOOT_READY" then ns.CheckDrop(lootLinks()); return end
    if event == "START_LOOT_ROLL" then
        ns.CheckDrop({ GetLootRollItemLink and GetLootRollItemLink(a1) or nil })
        return
    end
    later()
end)

SLASH_GULLIMYBISLIST1 = "/gbis"
SLASH_GULLIMYBISLIST2 = "/mybislist"
SlashCmdList.GULLIMYBISLIST = function(msg) ns.Slash(msg) end

function GulliMyBisList_Toggle() ns.Toggle() end

-- With the hub: its row and button there; alone: its own minimap button (Skin.lua).
do
    local register = GulliToolkit and GulliToolkit.Register or function(info) ns.alone = info end
    local function opt(key)
        local up = key:upper()
        return { label = L["OPT_" .. up], tip = L["OPT_" .. up .. "_TIP"], icon = ns.OPT_ICON[key],
                 get = function() return ns.db ~= nil and ns.db[key] == true end,
                 set = function(v) ns.SetPref(key, v) end }
    end
    register({
        key = "MyBisList",
        icon = ns.ICON,
        slash = "/gbis",
        open = function() ns.Toggle() end,
        window = function() return ns.Window and ns.Window() end,
        summary = function() return ns.Summary() end,
        pause = function(on) ns.Pause(on) end,
        reset = function() ns.Reset() end,
        options = { opt("tooltip"), opt("notify"), opt("drop"), opt("real") },
    })
end
