-- My BiS List: the best gear for each class, spec and level from the lists of wowtbc.gg, against
-- what the character wears and carries. It only reads the game; it never equips or buys anything.

local ADDON, ns = ...
local L = ns.L
local D = ns.Data

ns.DEFAULTS = { tooltip = true, notify = true, real = false }
ns.ICON = "Interface\\AddOns\\Gulli-MyBisList\\icon"
ns.OPT_ICON = {
    tooltip = "Interface\\Icons\\INV_Misc_Note_01", notify = "Interface\\Icons\\INV_Misc_Bell_01",
    real = "Interface\\Icons\\INV_Misc_Coin_02",
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
    return it and it[7] or "..."
end
function ns.ItemIcon(id)
    return (CI.GetItemIconByID and CI.GetItemIconByID(id)) or "Interface\\Icons\\INV_Misc_QuestionMark"
end
function ns.ItemQuality(id)
    local it = D.item[id]
    return it and it[2] or (CI.GetItemQualityByID and CI.GetItemQualityByID(id)) or 1
end
ns.WornItem = wornItem

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

-- The list behind a ref: { ref, spec, stage, auto, slots = { slot -> ids }, ench }.
function ns.Resolve(ref)
    local spec, stage, auto = ns.ParseRef(ref)
    if not spec then return nil end
    local src = D.lists[spec][stage] or {}
    local list = { ref = ref or "auto", spec = spec, stage = stage, auto = auto, slots = {},
                   ench = (D.ench[spec] or {})[stage] or {}, simmed = SPEC[spec][5] }
    for _, slot in ipairs(D.slots) do
        if src[slot] then list.slots[slot] = ns.Filter(src[slot]) end
    end
    return list
end

function ns.StageName(stage) return L["STAGE_" .. stage] end
function ns.ListName(list)
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
        local spec, stage = ns.ParseRef(ref)
        if spec then out[#out + 1] = { ref = ref, spec = spec, stage = stage } end
    end
    table.sort(out, function(a, b) return a.ref < b.ref end)
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

-- Tooltip, notices, the hub ---------------------------------------------------------------------------

local function S_cap(t) return ns.Skin and ns.Skin.Cap and ns.Skin.Cap(t) or t end

-- Lines for an item's tooltip: its place on the main list and the place of what is worn there.
function ns.TipLines(id)
    if not ns.db or not ns.db.tooltip or ns.paused or not id or not D.item[id] then return nil end
    local list = ns.Main()
    if not list then return nil end
    local out = {}
    for _, r in ipairs(ns.SlotRows(list)) do
        local rank = rankOf(r.ids, id)
        if rank and r.counted then
            local right
            if r.worn == id then right = L.TIP_WORN
            elseif r.rank then right = L.TIP_YOURS:format(r.rank)
            else right = L.TIP_YOURS_OFF end
            out[#out + 1] = { group = "note", icon = ns.ICON, left = S_cap(L.TIP_RANK:format(L["SLOT_" .. r.slot], rank, #r.ids)),
                              right = right, color = rank == 1 and ns.Skin.GOLD or ns.Skin.TEXT,
                              rcolor = r.worn == id and ns.Skin.GOOD or ns.Skin.MUTED, sub = #out > 0 }
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
        ns.cdb.told = ns.cdb.told or {}
        ns.cdb.main = ns.cdb.main or "auto"
        for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED",
                             "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "GET_ITEM_INFO_RECEIVED" }) do
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
        options = { opt("tooltip"), opt("notify"), opt("real") },
    })
end
