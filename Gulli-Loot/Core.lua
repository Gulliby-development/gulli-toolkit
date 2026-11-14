-- Group loot rolls by the player's rules: one rule per item, one per item type, one per quality
-- (gray, white, green). Bind-on-pickup items and items without a rule stay with the player, and
-- so do protected items (Gulli Toolkit) unless their own rule says otherwise. Every decision goes
-- into a short log with its reason and, later, who won.

local ADDON, ns = ...
local L = ns.L

ns.ROLL = { pass = 0, need = 1, greed = 2 }
ns.ROLL_NAME = { [0] = "pass", [1] = "need", [2] = "greed" }
-- For a quality or a type. "safe" is Need when the item fits you (you can need it and, for
-- gear, it beats what you wear), else Greed.
ns.RULES = { "ask", "need", "safe", "greed", "pass" }
ns.ITEM_RULES = { "ask", "need", "greed", "pass" }
ns.QUALITIES = { 0, 1, 2 }
-- Item types with a rule of their own, by the game's item class id.
ns.TYPES = { { key = "RECIPE", class = 9 }, { key = "TRADE", class = 7 }, { key = "CONSUMABLE", class = 0 },
             { key = "QUEST", class = 12 } }
-- Where the quality and type rules apply: everywhere, in a party (not a raid), in a raid.
ns.WHERE = { "always", "party", "raid" }
ns.LOG_MAX = 30
ns.DEFAULTS = {
    on = true, report = true, where = "always", greedUnusable = false, needUpgrade = false,
    fastLoot = false, soloConfirm = false,
}

-- Equip slots by the item's equip location, for the upgrade check.
local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 },
    INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
    INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 },
    INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 },
}

local function protected(id)
    return GulliToolkit and GulliToolkit.IsProtected and GulliToolkit.IsProtected(id) or false
end
local function say(msg) print("|cff9ad0ffGulli Loot|r: " .. msg) end

local function itemInfo(item)
    local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not f then return nil end
    return f(item)
end
-- The item class id (9 recipe, 7 trade goods...) and the equip location.
local function itemClass(id)
    if C_Item and C_Item.GetItemInfoInstant then
        local _, _, _, equip, _, class = C_Item.GetItemInfoInstant(id)
        return class, equip
    end
    local r = { itemInfo(id) }
    return r[12], r[9]
end
local function itemLevel(item)
    if C_Item and C_Item.GetDetailedItemLevelInfo then
        local lvl = C_Item.GetDetailedItemLevelInfo(item)
        if lvl then return lvl end
    end
    local _, _, _, lvl = itemInfo(item)
    return lvl
end

-- True when the item would be better than what is worn in its slot (by item level).
function ns.Upgrade(item, id)
    local _, equip = itemClass(id)
    local slots = equip and SLOTS[equip]
    local lvl = itemLevel(item)
    if not slots or not lvl then return false end
    for _, slot in ipairs(slots) do
        local worn = GetInventoryItemLink and GetInventoryItemLink("player", slot)
        if not worn then return true end
        local w = itemLevel(worn)
        if w and lvl > w then return true end
    end
    return false
end

local function whereOK()
    local w = ns.db.where
    if w == "always" then return true end
    local raid = IsInRaid and IsInRaid() or false
    if w == "raid" then return raid end
    return not raid
end

-- The rule for a roll and its reason. rule: "need", "greed", "pass", or nil to leave it to the
-- player. reason: "item", "type", "quality", "unusable", "upgrade", "fits", "nofit", "bop",
-- "protected", "where", "ask", "off". extra: { upgrade = item link to compare } (optional).
function ns.Decide(id, quality, bop, canNeed, canGreed, link)
    local db = ns.db
    if not db.on then return nil, "off" end
    local rule, reason = id and db.items[id], "item"
    if rule == "ask" then return nil, "ask" end
    if not rule then
        if bop then return nil, "bop" end
        if id and protected(id) then return nil, "protected" end
        if not whereOK() then return nil, "where" end
        local class = id and itemClass(id)
        rule, reason = class and db.types[class], "type"
        if not rule then
            rule, reason = db.quality[quality], "quality"
            if quality == 2 and db.needUpgrade and canNeed and link and ns.Upgrade(link, id) then
                rule, reason = "need", "upgrade"
            elseif quality == 2 and db.greedUnusable and not canNeed and canGreed then
                rule, reason = "greed", "unusable"
            end
        end
        if not rule or rule == "ask" then return nil, "ask" end
        if rule == "safe" then
            local _, equip = itemClass(id)
            local gear = equip and SLOTS[equip]
            if canNeed and (not gear or (link and ns.Upgrade(link, id))) then rule, reason = "need", "fits"
            else rule, reason = "greed", "nofit" end
        end
    end
    if rule == "need" and not canNeed then rule = "greed" end
    if rule == "greed" and not canGreed then return nil, reason end
    return rule, reason
end

---- The log of rolls ---------------------------------------------------------------

-- Adds a roll to the log (newest first, at most LOG_MAX), saved between sessions.
local function log(e)
    table.insert(ns.db.log, 1, e)
    for i = #ns.db.log, ns.LOG_MAX + 1, -1 do ns.db.log[i] = nil end
    if ns.Refresh then ns.Refresh() end
end

-- Chat lines for rolls are gathered for a moment and printed as one line per rule.
local batch
local function report(rule, link)
    if not ns.db.report then return end
    if not (C_Timer and C_Timer.After) then
        say(L.ROLLED:format(L["RULE_" .. rule:upper()], link))
        return
    end
    if not batch then
        batch = {}
        C_Timer.After(1, function()
            local parts = {}
            for _, r in ipairs(ns.ITEM_RULES) do
                if batch[r] then parts[#parts + 1] = L.ROLLED:format(L["RULE_" .. r:upper()], table.concat(batch[r], ", ")) end
            end
            batch = nil
            if #parts > 0 then say(table.concat(parts, "; ")) end
        end)
    end
    batch[rule] = batch[rule] or {}
    table.insert(batch[rule], link)
end

local pending = {}

function ns.OnRoll(rollID)
    local _, name, _, quality, bop, canNeed, canGreed = GetLootRollItemInfo(rollID)
    local link = GetLootRollItemLink(rollID)
    local id = link and tonumber(link:match("item:(%d+)"))
    local rule, reason
    if IsShiftKeyDown and IsShiftKeyDown() then
        reason = "shift"
    else
        rule, reason = ns.Decide(id, quality, bop, canNeed, canGreed, link)
    end
    log({ id = id, link = link or name, quality = quality, rule = rule, reason = reason, t = time and time() or 0 })
    if not rule then return nil end
    pending[rollID] = ns.ROLL[rule]
    RollOnLoot(rollID, ns.ROLL[rule])
    report(rule, link or name or "?")
    return rule
end

-- The game asks to confirm a roll on a bind-on-pickup item; only rolls we made are confirmed.
function ns.OnConfirm(rollID, rollType)
    if pending[rollID] ~= nil and pending[rollID] == rollType then
        pending[rollID] = nil
        ConfirmLootRoll(rollID, rollType)
        if StaticPopup_Hide then StaticPopup_Hide("CONFIRM_LOOT_ROLL") end
        return true
    end
    return false
end

-- A Lua pattern from a game format string such as "%s won: %s".
local function pattern(fmt)
    if not fmt then return nil end
    local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
    return "^" .. p .. "$"
end

-- "Name won: [Item]" in the loot chat: who won the newest logged roll of that item.
function ns.OnLootMessage(msg)
    if type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then return end
    local who, link
    local you = pattern(LOOT_ROLL_YOU_WON)
    local won = pattern(LOOT_ROLL_WON)
    if you then link = msg:match(you); if link then who = UnitName("player") end end
    if not link and won then who, link = msg:match(won) end
    local id = link and tonumber(link:match("item:(%d+)"))
    if not id then return end
    for _, e in ipairs(ns.db.log) do
        if e.id == id and not e.winner then
            e.winner = who
            if who == UnitName("player") and GulliToolkit and GulliToolkit.Notify then
                GulliToolkit.Notify("Loot", L.WON:format(link))
            end
            if ns.Refresh then ns.Refresh() end
            return e
        end
    end
end

---- Rules ---------------------------------------------------------------------------

function ns.SetItem(id, rule)
    ns.db.items[id] = rule
    if ns.Refresh then ns.Refresh() end
end

function ns.SetType(class, rule)
    ns.db.types[class] = rule ~= "ask" and rule or nil
    if ns.Refresh then ns.Refresh() end
end

function ns.SetPref(key, value)
    ns.db[key] = value
    if ns.Refresh then ns.Refresh() end
end

-- The item name for sorting and the list, or "#id" until the game knows it.
function ns.ItemName(id)
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    if not name then name = itemInfo(id) end
    return name or ("#" .. id)
end

-- The item rules as a list sorted by name: { { id, rule } }; filter: part of the name.
function ns.Items(filter)
    local out = {}
    filter = filter and filter ~= "" and filter:lower() or nil
    for id, rule in pairs(ns.db.items) do
        local name = ns.ItemName(id)
        if not filter or name:lower():find(filter, 1, true) then
            out[#out + 1] = { id = id, rule = rule, name = name }
        end
    end
    table.sort(out, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    return out
end

-- What the addon would do with this item now, as one line (for /glt test).
function ns.Test(link)
    local id = link and tonumber(link:match("item:(%d+)") or link:match("^(%d+)$"))
    if not id then return L.TEST_BAD end
    local _, l, quality, _, _, _, _, _, _, _, _, _, _, bind = itemInfo(id)
    local rule, reason = ns.Decide(id, quality or 1, bind == 1, true, true, l or link)
    return L.TEST:format(l or link, rule and L["RULE_" .. rule:upper()] or L.RULE_ASK, L["WHY_" .. reason:upper()])
end

---- Looting on your own ---------------------------------------------------------------

-- Fast loot: takes every slot at once when the game would loot automatically anyway.
function ns.FastLoot()
    if not ns.db.fastLoot or not GetNumLootItems then return 0 end
    local auto = GetCVarBool and GetCVarBool("autoLootDefault")
    if IsModifiedClick and IsModifiedClick("AUTOLOOTTOGGLE") then auto = not auto end
    if not auto then return 0 end
    local n = GetNumLootItems()
    for i = n, 1, -1 do LootSlot(i) end
    return n
end

-- Alone, the bind-on-pickup question when you loot is answered for you.
function ns.OnBindConfirm(slot)
    if not ns.db.soloConfirm or (IsInGroup and IsInGroup()) then return false end
    ConfirmLootSlot(slot)
    if StaticPopup_Hide then StaticPopup_Hide("LOOT_BIND") end
    return true
end

---- Slash commands and events ---------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1, a2)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliLootDB = GulliLootDB or {}
        ns.db = GulliLootDB
        ns.db.quality = ns.db.quality or { [0] = "pass", [1] = "ask", [2] = "ask" }
        ns.db.items = ns.db.items or {}
        ns.db.types = ns.db.types or {}
        ns.db.log = ns.db.log or {}
        for k, v in pairs(ns.DEFAULTS) do
            if ns.db[k] == nil then ns.db[k] = v end
        end
        for _, e in ipairs({ "START_LOOT_ROLL", "CONFIRM_LOOT_ROLL", "CHAT_MSG_LOOT", "LOOT_READY", "LOOT_BIND_CONFIRM" }) do
            self:RegisterEvent(e)
        end
        if hooksecurefunc and HandleModifiedItemClick then
            -- Alt-click on an item anywhere (bags, a roll frame, a chat link) gives it a rule.
            hooksecurefunc("HandleModifiedItemClick", function(link)
                if not ns.paused and IsAltKeyDown and IsAltKeyDown() and ns.OnAltClick then ns.OnAltClick(link) end
            end)
        end
        return
    end
    -- Paused from the hub: only the closing events still run, so nothing stays open.
    if ns.paused and not event:find("_CLOSED$") then return end
    if event == "START_LOOT_ROLL" then ns.OnRoll(a1)
    elseif event == "CONFIRM_LOOT_ROLL" then ns.OnConfirm(a1, a2)
    elseif event == "CHAT_MSG_LOOT" then ns.OnLootMessage(a1)
    elseif event == "LOOT_READY" then ns.FastLoot()
    elseif event == "LOOT_BIND_CONFIRM" then ns.OnBindConfirm(a1) end
end)

-- Alt-click: a new item gets "Greed", one with a rule goes to the next rule; the line says which.
function ns.OnAltClick(link)
    local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
    if not id then return end
    local cur = ns.db.items[id]
    local rule = "greed"
    if cur then
        for i, r in ipairs(ns.ITEM_RULES) do
            if r == cur then rule = ns.ITEM_RULES[i % #ns.ITEM_RULES + 1] end
        end
    end
    ns.SetItem(id, rule)
    say(L.SET:format(link, L["RULE_" .. rule:upper()]))
end

SLASH_GULLILOOT1 = "/glt"
SLASH_GULLILOOT2 = "/gulliloot"
SlashCmdList.GULLILOOT = function(msg)
    msg = msg or ""
    local cmd, rest = msg:match("^%s*(%a+)%s*(.-)%s*$")
    cmd = cmd and cmd:lower()
    local id = rest and tonumber(rest:match("item:(%d+)") or rest:match("^(%d+)$"))
    if cmd == "test" then
        say(ns.Test(rest))
    elseif cmd and ns.ROLL[cmd] or cmd == "ask" then
        if not id then say(L.TEST_BAD); return end
        ns.SetItem(id, cmd)
        say(L.SET:format(rest, L["RULE_" .. cmd:upper()]))
    elseif cmd == "remove" and id then
        ns.SetItem(id, nil)
    elseif cmd == "on" or cmd == "off" then
        ns.SetPref("on", cmd == "on")
        say(cmd == "on" and L.NOW_ON or L.NOW_OFF)
    else
        ns.Toggle()
    end
end

function GulliLoot_Toggle() ns.Toggle() end

ns.OPT_ICON = {
    on = "Interface\\Icons\\INV_Misc_Bag_10",
    report = "Interface\\Icons\\INV_Letter_01",
    greedUnusable = "Interface\\Icons\\INV_Misc_Coin_02",
    needUpgrade = "Interface\\Icons\\INV_Chest_Plate06",
    fastLoot = "Interface\\Icons\\Ability_Rogue_Sprint",
    soloConfirm = "Interface\\Icons\\INV_Misc_Key_03",
    where = "Interface\\Icons\\INV_Misc_Map_01",
}

local function option(key, label, tip)
    return { label = label, tip = tip, icon = ns.OPT_ICON[key],
             get = function() return ns.db ~= nil and ns.db[key] == true end,
             set = function(on) if ns.db then ns.SetPref(key, on and true or false) end end }
end

if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({
        pause = function(on) ns.paused = on end,
        key = "Loot",
        icon = "Interface\\AddOns\\Gulli-Loot\\icon",
        slash = "/glt",
        open = function() ns.Toggle() end,
        window = function() return ns.Window and ns.Window() end,
        options = {
            option("on", L.OPT_ON, L.OPT_ON_D),
            option("report", L.OPT_REPORT),
            option("fastLoot", L.OPT_FAST, L.OPT_FAST_D),
        },
        summary = function()
            if not ns.db then return nil end
            if not ns.db.on then return L.NOW_OFF end
            local n = 0
            for _ in pairs(ns.db.items) do n = n + 1 end
            return L.SUMMARY:format(n)
        end,
        reset = function()
            if not ns.db then return end
            for k in pairs(ns.db) do ns.db[k] = nil end
            ns.db.quality = { [0] = "pass", [1] = "ask", [2] = "ask" }
            ns.db.items, ns.db.types, ns.db.log = {}, {}, {}
            for k, v in pairs(ns.DEFAULTS) do ns.db[k] = v end
            if ns.Refresh then ns.Refresh() end
        end,
    })
end
