-- Consumable macros: per-character macros that always use the best food, drink, bandage and
-- potion in the bags. They change after the bags change, only out of combat (the game refuses
-- macro changes in a fight). The player drags them onto a bar from the macro window; unticking
-- one deletes it, switching the tweak off leaves them as they are.

local _, ns = ...
local L = ns.L

local KEY = "macros"
local QUESTION = 134400 -- INV_Misc_QuestionMark; #showtooltip shows the item instead
local WAIT = 0.5

-- Items best first within a level: { item id, level it needs }. The highest level the character
-- may use wins; at the same level, the earlier entry (conjured before bought).
local FOOD = {
    { 19301, 51 }, { 13724, 45 }, { 8076, 45 }, { 8950, 45 }, { 8952, 45 }, { 8932, 45 }, { 8953, 45 },
    { 8948, 45 }, { 8957, 45 }, { 21552, 45 },
    { 8075, 35 }, { 4601, 35 }, { 4599, 35 }, { 3927, 35 }, { 4602, 35 }, { 4608, 35 }, { 4594, 35 },
    { 1487, 25 }, { 4544, 25 }, { 3771, 25 }, { 1707, 25 }, { 4539, 25 }, { 4607, 25 }, { 4593, 25 },
    { 1114, 15 }, { 4542, 15 }, { 3770, 15 }, { 422, 15 }, { 4538, 15 }, { 4606, 15 }, { 4592, 15 },
    { 1113, 5 }, { 4541, 5 }, { 2287, 5 }, { 414, 5 }, { 4537, 5 }, { 4605, 5 },
    { 5349, 1 }, { 4540, 1 }, { 117, 1 }, { 2070, 1 }, { 4536, 1 }, { 4604, 1 }, { 787, 1 },
}
local DRINK = {
    { 19301, 51 }, { 8079, 55 }, { 13724, 45 }, { 8078, 45 }, { 8766, 45 },
    { 8077, 35 }, { 1645, 35 }, { 3772, 25 }, { 1708, 25 }, { 2136, 15 }, { 1205, 15 },
    { 2288, 5 }, { 1179, 5 }, { 5350, 1 }, { 159, 1 },
}
local BANDAGE = {
    { 14530, 0 }, { 14529, 0 }, { 8545, 0 }, { 8544, 0 }, { 6451, 0 }, { 6450, 0 }, { 3531, 0 },
    { 3530, 0 }, { 2581, 0 }, { 1251, 0 },
}
local HEALTH = {
    { 19013, 48 }, { 19012, 48 }, { 9421, 48 }, { 13446, 45 }, { 19011, 36 }, { 19010, 36 }, { 5510, 36 },
    { 3928, 35 }, { 19009, 24 }, { 19008, 24 }, { 5509, 24 }, { 1710, 21 }, { 19007, 12 }, { 19006, 12 },
    { 5511, 12 }, { 929, 12 }, { 19005, 1 }, { 19004, 1 }, { 5512, 1 }, { 858, 3 }, { 118, 1 },
}
local MANA = {
    { 13444, 49 }, { 13443, 41 }, { 6149, 31 }, { 3827, 22 }, { 3385, 14 }, { 2455, 5 },
}

-- The macros in panel order: key (also the switch), its list(s), the body for the picked items.
ns.MACROS = {
    { key = "food", lists = { FOOD } },
    { key = "drink", lists = { DRINK } },
    { key = "rest", lists = { FOOD, DRINK } },
    { key = "bandage", lists = { BANDAGE }, use = "/use [@mouseover,help,nodead][help,nodead][@player] item:%d" },
    { key = "health", lists = { HEALTH } },
    { key = "mana", lists = { MANA } },
}
ns.MACRO_LISTS = { FOOD = FOOD, DRINK = DRINK, BANDAGE = BANDAGE, HEALTH = HEALTH, MANA = MANA }

local function count(id)
    if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id) or 0 end
    if GetItemCount then return GetItemCount(id) or 0 end
    return 0
end

-- The best item of a list the bags hold for a character of this level, else nil.
function ns.BestConsumable(list, level, have)
    have = have or count
    local best, bestLevel
    for _, e in ipairs(list) do
        if e[2] <= level and have(e[1]) > 0 and (not bestLevel or e[2] > bestLevel) then
            best, bestLevel = e[1], e[2]
        end
    end
    return best
end

local function db()
    GulliToolkitDB = GulliToolkitDB or {}
    GulliToolkitDB.tweakMacros = GulliToolkitDB.tweakMacros or {}
    return GulliToolkitDB.tweakMacros
end

-- The macro text for a macro: its picks now, else the item it used last (the button then shows
-- that item greyed out), else the first of its list.
function ns.MacroBody(m, level, have)
    local last = db()[m.key] or {}
    local ids = {}
    for i, list in ipairs(m.lists) do
        local id = ns.BestConsumable(list, level, have)
        ids[i] = id or (last.ids and last.ids[i]) or list[1][1]
    end
    local use = m.use or "/use item:%d"
    local lines = { "#showtooltip item:" .. ids[1] }
    for i, id in ipairs(ids) do
        if i == 1 or id ~= ids[1] then lines[#lines + 1] = use:format(id) end
    end
    return table.concat(lines, "\n"), ids
end

local function nameOf(m) return L["TWM_" .. m.key:upper()] end

local function findMacro(name)
    if not GetMacroIndexByName or not name then return 0 end
    return GetMacroIndexByName(name) or 0
end

local get, frame, pending, waiting

-- Makes, changes or deletes the macros to match the ticks; out of combat only.
function ns.UpdateMacros()
    waiting = false
    if not get then return end
    if InCombatLockdown and InCombatLockdown() then pending = true; return end
    pending = false
    if not (CreateMacro and EditMacro and GetMacroIndexByName) then return end
    local level = UnitLevel and UnitLevel("player") or 60
    for _, m in ipairs(ns.MACROS) do
        local saved = db()[m.key]
        local name = nameOf(m)
        local index = findMacro(saved and saved.name or name)
        if get(m.key) then
            local body, ids = ns.MacroBody(m, level)
            if index > 0 then
                local oldName, _, oldBody = GetMacroInfo(index)
                if oldBody ~= body or oldName ~= name then pcall(EditMacro, index, name, QUESTION, body) end
            else
                local _, perChar = GetNumMacros()
                local max = MAX_CHARACTER_MACROS or 18
                if perChar < max then
                    pcall(CreateMacro, name, QUESTION, body, true)
                elseif not ns.macrosFull then
                    ns.macrosFull = true
                    ns.Print(L.TWP_MAC_FULL)
                end
            end
            db()[m.key] = { name = name, ids = ids }
        elseif saved then
            if index > 0 and DeleteMacro then pcall(DeleteMacro, index) end
            db()[m.key] = nil
        end
    end
end

local function soon()
    if waiting then return end
    waiting = true
    if C_Timer and C_Timer.After then C_Timer.After(WAIT, ns.UpdateMacros) else ns.UpdateMacros() end
end

local function onEvent(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if pending then ns.UpdateMacros() end
    else
        soon()
    end
end
ns.MacrosEvent = onEvent

local panel = { { kind = "head", label = L.TWP_MAC_HEAD } }
for _, m in ipairs(ns.MACROS) do
    panel[#panel + 1] = { kind = "check", key = m.key, label = L["TWP_MAC_" .. m.key:upper()] }
end

ns.AddTweak({
    key = KEY, group = "combat", icon = "Interface\\Icons\\INV_Potion_54", star = true,
    defaults = { food = true, drink = true, rest = false, bandage = false, health = true, mana = false },
    panel = panel,
    enable = function(g)
        get = g
        frame = frame or CreateFrame("Frame")
        frame:SetScript("OnEvent", onEvent)
        frame:RegisterEvent("BAG_UPDATE_DELAYED")
        frame:RegisterEvent("PLAYER_LEVEL_UP")
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        ns.UpdateMacros()
    end,
    disable = function()
        if frame then frame:UnregisterAllEvents() end
        get, pending = nil, false
    end,
    changed = function(_, _, g) get = g; ns.UpdateMacros() end,
})
