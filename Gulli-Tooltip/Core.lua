-- Adds lines to item, NPC and spell tooltips: the vendor price of a full stack, the auction
-- price (Auctionator), the quests in the log that still need the item or the NPC, "protected"
-- from the Gulli Toolkit, how many your other characters hold (from Gulli Chores), which of
-- your professions use it (from Gulli Craft Profit), and ids. Prices and ids can wait for Shift.

local ADDON, ns = ...
local L = ns.L

local MUTED, QUEST = { 0.6, 0.6, 0.62 }, { 1, 0.82, 0 }
local WHITE, DONE = { 1, 1, 1 }, { 0.42, 0.84, 0.50 }
local FAINT, PROF = { 0.45, 0.46, 0.5 }, { 0.56, 0.77, 0.91 }
ns.COLORS = { MUTED = MUTED, QUEST = QUEST, WHITE = WHITE, DONE = DONE, FAINT = FAINT, PROF = PROF }

-- Game API wrappers.
local function itemInfo(id)
    local name, _, _, _, _, _, _, maxStack, _, _, price = ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(id)
    return name, maxStack or 1, price or 0
end
local function secret(v) return issecretvalue and issecretvalue(v) end
local function questEntries()
    local out = {}
    local Q = C_QuestLog
    local n = Q and Q.GetNumQuestLogEntries and Q.GetNumQuestLogEntries() or 0
    for i = 1, n do
        local info = Q.GetInfo(i)
        if info and not info.isHeader and not info.isHidden and info.questID then
            out[#out + 1] = { id = info.questID, title = info.title }
        end
    end
    return out
end

-- Money as text in coin colours (the skin loads after this file, so it is read at call time).
function ns.Money(copper)
    copper = math.floor(copper or 0)
    if ns.Skin and ns.Skin.MoneyText then return ns.Skin.MoneyText(copper) end
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
    return table.concat(parts, " ")
end

-- The name in an objective, without its count: "Wolf Pelt: 3/10" and "3/10 Wolf Pelt" are
-- both "Wolf Pelt".
function ns.ObjectiveName(text)
    if type(text) ~= "string" then return nil end
    local name = text:gsub("^%s*%d+%s*/%s*%d+%s+", ""):gsub("%s*:?%s*%d+%s*/%s*%d+%s*$", "")
    return (name:match("^%s*(.-)%s*$"))
end

-- Quests in the log whose objectives name the item or the NPC: { { title, have, need, kind } }.
-- Rebuilt when the log changes, so a tooltip only reads a table.
local needs
local function allNeeds()
    if not needs then
        needs = {}
        for _, q in ipairs(questEntries()) do
            for _, o in ipairs(C_QuestLog.GetQuestObjectives(q.id) or {}) do
                if (o.type == "item" or o.type == "monster") and o.text and not o.finished then
                    needs[#needs + 1] = { title = q.title, name = ns.ObjectiveName(o.text), kind = o.type,
                                          have = o.numFulfilled or 0, need = o.numRequired or 0 }
                end
            end
        end
    end
    return needs
end

-- The whole name must match: "Wolf Pelt" is not "Large Wolf Pelt".
function ns.QuestNeeds(name)
    local out = {}
    if not name then return out end
    for _, n in ipairs(allNeeds()) do
        if n.kind == "item" and n.name == name then out[#out + 1] = n end
    end
    return out
end

-- Kill objectives for an NPC: "Boar slain" names the Boar ("Boar" alone, or followed by a word).
function ns.MobNeeds(name)
    local out = {}
    if not name or secret(name) then return out end
    for _, n in ipairs(allNeeds()) do
        if n.kind == "monster" and n.name and n.name:sub(1, #name) == name then
            local rest = n.name:sub(#name + 1, #name + 1)
            if rest == "" or rest:match("[%s%p]") then out[#out + 1] = n end
        end
    end
    return out
end

function ns.Forget() needs = nil end

local function shiftDown() return IsShiftKeyDown ~= nil and IsShiftKeyDown() == true end

-- Prices and ids wait for Shift when the player wants a short tooltip.
local function extra(key)
    return ns.db[key] and (not ns.db.shift or shiftDown())
end

local function auctionPrice(id)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not (api and api.GetAuctionPriceByItemID) then return nil end
    local ok, price = pcall(api.GetAuctionPriceByItemID, "Gulli-Tooltip", id)
    return ok and tonumber(price) or nil
end

-- How many the other characters hold, from Gulli Chores' snapshots (read only):
-- { { name, bags, bank } }, the player's own bank as "me".
function ns.AltCounts(id)
    local out = {}
    local db = GulliChoresDB
    if type(db) ~= "table" or type(db.chars) ~= "table" then return out end
    local me = UnitName("player") .. "-" .. (GetRealmName and GetRealmName() or "")
    for key, c in pairs(db.chars) do
        local bags = c.items and c.items[id] or 0
        local bank = c.bank and c.bank[id] or 0
        if key == me then bags = 0 end
        if bags + bank > 0 then
            out[#out + 1] = { name = c.name or key, class = c.class, bags = bags, bank = bank, me = key == me }
        end
    end
    table.sort(out, function(a, b) if a.me ~= b.me then return a.me end return a.name < b.name end)
    return out
end

-- Which professions of this character use the item, from Gulli Craft Profit's recipes (read only).
local reagentOf
function ns.ReagentFor(id)
    if not reagentOf then
        reagentOf = {}
        local db = GulliCraftProfitCharDB
        for prof, p in pairs(type(db) == "table" and type(db.profs) == "table" and db.profs or {}) do
            -- A recipe keeps its reagents as r = { [itemID] = count }; only learned ones count.
            for _, r in pairs(type(p) == "table" and type(p.recipes) == "table" and p.recipes or {}) do
                if type(r) == "table" and r.learned and type(r.r) == "table" then
                    for rid in pairs(r.r) do
                        reagentOf[rid] = reagentOf[rid] or {}
                        reagentOf[rid][prof] = true
                    end
                end
            end
        end
    end
    local out = {}
    for prof in pairs(reagentOf[id] or {}) do out[#out + 1] = prof end
    table.sort(out)
    return out
end

local function classHex(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return c and string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) or "|cffffffff"
end
local function mutedHex(t) return string.format("|cff%02x%02x%02x", MUTED[1] * 255, MUTED[2] * 255, MUTED[3] * 255) .. t .. "|r" end

-- The lines of the other characters: a total, then each one in its class colour.
function ns.AltLines(id)
    local alts = ns.AltCounts(id)
    if #alts == 0 then return {} end
    local total = 0
    for _, a in ipairs(alts) do total = total + a.bags + a.bank end
    local out = { { L.YOUR_CHARS, tostring(total), MUTED, WHITE } }
    for _, a in ipairs(alts) do
        if a.me then
            out[#out + 1] = { "  " .. L.YOUR_BANK, tostring(a.bank), MUTED, WHITE }
        else
            out[#out + 1] = { "  " .. classHex(a.class) .. a.name .. "|r",
                              a.bags .. (a.bank > 0 and mutedHex(L.PLUS_BANK:format(a.bank)) or ""), WHITE, WHITE }
        end
    end
    return out
end

-- The lines for an item: { { left, right, color, rightColor } }, in groups: protected, quests,
-- prices, characters, professions, ids.
function ns.ItemLines(id)
    local out = {}
    if not id or secret(id) then return out end
    local name, maxStack, price = itemInfo(id)
    if ns.db.protect and GulliToolkit and GulliToolkit.IsProtected and GulliToolkit.IsProtected(id) then
        out[#out + 1] = { L.PROTECTED, "", DONE }
    end
    if ns.db.quest then
        for _, n in ipairs(ns.QuestNeeds(name)) do
            -- The count turns green once the bags hold enough.
            out[#out + 1] = { L.QUEST:format(n.title), n.have .. "/" .. n.need, QUEST,
                              n.need > 0 and n.have >= n.need and DONE or WHITE }
        end
    end
    if extra("price") and price > 0 and maxStack > 1 then
        out[#out + 1] = { L.STACK:format(maxStack), ns.Money(price * maxStack), MUTED, WHITE }
    end
    if extra("auction") then
        -- Auctionator shows the price of one; for a stack item this line gives the full stack.
        local ah = auctionPrice(id)
        if ah and ah > 0 then
            if maxStack > 1 then out[#out + 1] = { L.AUCTION_STACK, ns.Money(ah * maxStack), MUTED, WHITE }
            else out[#out + 1] = { L.AUCTION, ns.Money(ah), MUTED, WHITE } end
        end
    end
    if ns.db.alts then
        for _, l in ipairs(ns.AltLines(id)) do out[#out + 1] = l end
    end
    if ns.db.reagent then
        local profs = ns.ReagentFor(id)
        if #profs > 0 then out[#out + 1] = { L.REAGENT_FOR, table.concat(profs, ", "), MUTED, PROF } end
    end
    if extra("id") then out[#out + 1] = { L.ITEM_ID, tostring(id), FAINT, FAINT } end
    return out
end

-- The NPC id from a unit GUID ("Creature-0-1-2-3-<npcID>-<spawn>").
function ns.NpcID(guid)
    if not guid or secret(guid) then return nil end
    local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

function ns.UnitLines(guid, name)
    local out = {}
    if ns.db.mobs and ns.NpcID(guid) then
        for _, n in ipairs(ns.MobNeeds(name)) do
            out[#out + 1] = { L.QUEST:format(n.title), n.have .. "/" .. n.need, QUEST, WHITE }
        end
    end
    local id = extra("id") and ns.NpcID(guid)
    if id then out[#out + 1] = { L.NPC_ID, tostring(id), FAINT, FAINT } end
    return out
end

-- Spell and aura ids, under the same switch.
function ns.SpellLines(id)
    if not extra("id") or not id or secret(id) then return {} end
    return { { L.SPELL_ID, tostring(id), FAINT, FAINT } }
end

-- The tooltip's border in the item's quality colour.
local function paintBorder(tt, id)
    if not ns.db.quality or not id then return end
    local _, _, q = ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(id)
    local c = q and q >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if not c then return end
    if tt.NineSlice and tt.NineSlice.SetBorderColor then tt.NineSlice:SetBorderColor(c.r, c.g, c.b)
    elseif tt.SetBackdropBorderColor then tt:SetBackdropBorderColor(c.r, c.g, c.b) end
end

-- A thin line above our lines sets them apart from the game's and other addons' lines. The
-- line lives in our own weak table, never as a field on the game's tooltip.
local rules = setmetatable({}, { __mode = "k" })
local function rule(tt, first)
    local name = tt.GetName and tt:GetName()
    local fs = name and _G[name .. "TextLeft" .. first]
    if not fs or first < 2 or not tt.CreateTexture then return end
    local t = rules[tt]
    if not t then
        t = tt:CreateTexture(nil, "ARTWORK")
        t:SetColorTexture(1, 1, 1, 0.16)
        t:SetHeight(1)
        rules[tt] = t
        if tt.HookScript then tt:HookScript("OnTooltipCleared", function(self) rules[self]:Hide() end) end
    end
    t:ClearAllPoints()
    t:SetPoint("BOTTOMLEFT", fs, "TOPLEFT", 0, 3)
    t:SetPoint("RIGHT", tt, "RIGHT", -10, 0)
    t:Show()
end

local function add(tt, lines)
    if #lines == 0 then return end
    local first = (tt.NumLines and tt:NumLines() or 0) + 1
    for _, l in ipairs(lines) do
        local c, r = l[3], l[4] or WHITE
        tt:AddDoubleLine(l[1], l[2], c[1], c[2], c[3], r[1], r[2], r[3])
    end
    rule(tt, first)
    tt:Show()
end

local function unitName(data)
    local lines = data and data.lines
    local first = lines and lines[1]
    return first and first.leftText
end

local function hook()
    if TooltipDataProcessor and Enum and Enum.TooltipDataType then
        local T = Enum.TooltipDataType
        TooltipDataProcessor.AddTooltipPostCall(T.Item, function(tt, data)
            if data then add(tt, ns.ItemLines(data.id)); paintBorder(tt, data.id) end
        end)
        TooltipDataProcessor.AddTooltipPostCall(T.Unit, function(tt, data)
            if data then
                local name = unitName(data)
                if not name and tt.GetUnit then name = tt:GetUnit() end
                add(tt, ns.UnitLines(data.guid, name))
            end
        end)
        for _, kind in ipairs({ "Spell", "UnitAura" }) do
            if T[kind] then
                TooltipDataProcessor.AddTooltipPostCall(T[kind], function(tt, data)
                    if data then add(tt, ns.SpellLines(data.id)) end
                end)
            end
        end
    elseif GameTooltip then
        GameTooltip:HookScript("OnTooltipSetItem", function(tt)
            local _, link = tt:GetItem()
            local id = link and tonumber(link:match("item:(%d+)"))
            add(tt, ns.ItemLines(id))
            paintBorder(tt, id)
        end)
        GameTooltip:HookScript("OnTooltipSetUnit", function(tt)
            local name, unit = tt:GetUnit()
            add(tt, ns.UnitLines(unit and UnitGUID(unit), name))
        end)
        GameTooltip:HookScript("OnTooltipSetSpell", function(tt)
            local _, id = tt:GetSpell()
            add(tt, ns.SpellLines(id))
        end)
    end
    -- At the cursor instead of the corner of the screen, when the player wants it.
    if hooksecurefunc and GameTooltip_SetDefaultAnchor then
        hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tt, parent)
            if ns.db.cursor and tt and tt.SetOwner then tt:SetOwner(parent, "ANCHOR_CURSOR") end
        end)
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliTooltipDB = GulliTooltipDB or {}
        ns.db = GulliTooltipDB
        local fresh = next(ns.db) == nil
        for k, v in pairs(ns.DEFAULTS) do
            if ns.db[k] == nil then ns.db[k] = v end
        end
        if fresh then ns.db.defaultsV = ns.DEFAULTS_V else ns.Migrate(ns.db) end
        self:RegisterEvent("QUEST_LOG_UPDATE")
        self:RegisterEvent("MODIFIER_STATE_CHANGED")
        self:RegisterEvent("TRADE_SKILL_CLOSE")
        hook()
        return
    end
    if event == "MODIFIER_STATE_CHANGED" then
        -- Shift shows the waiting lines on the tooltip that is open.
        if ns.db.shift and (a1 == "LSHIFT" or a1 == "RSHIFT") and GameTooltip and GameTooltip.RefreshData
            and GameTooltip:IsShown() then
            GameTooltip:RefreshData()
        end
        return
    end
    if event == "TRADE_SKILL_CLOSE" then reagentOf = nil; return end
    ns.Forget()
end)

SLASH_GULLITOOLTIP1 = "/gtt"
SLASH_GULLITOOLTIP2 = "/gullitooltip"
SlashCmdList.GULLITOOLTIP = function() ns.Toggle() end

function GulliTooltip_Toggle() ns.Toggle() end

-- The same switches as in the window, so the Gulli Toolkit hub can show them.
-- The game icon of each switch, in the window and in the hub.
ns.OPT_ICON = {
    price = "Interface\\Icons\\INV_Misc_Coin_01",
    auction = "Interface\\Minimap\\Tracking\\Auctioneer",
    quest = "Interface\\Icons\\INV_Misc_Note_01",
    mobs = "Interface\\Icons\\Ability_Hunter_SniperShot",
    protect = "Interface\\Icons\\INV_Misc_Key_03",
    alts = "Interface\\Minimap\\Tracking\\Banker",
    reagent = "Interface\\Icons\\Trade_Tailoring",
    id = "Interface\\Icons\\INV_Misc_Gear_01",
    shift = "Interface\\Icons\\INV_Misc_Key_14",
    quality = "Interface\\Icons\\INV_Misc_Gem_Pearl_04",
    cursor = "Interface\\Icons\\Ability_Hunter_MarkedForDeath",
}

-- The switches in window order; a new line gets its key here, a default, a text and a test.
ns.LINES = { "price", "auction", "quest", "mobs", "protect", "alts", "reagent", "id" }
ns.LOOK = { "shift", "quality", "cursor" }
-- The engine may already show kill objectives on NPCs, and Auctionator its own auction line,
-- and the game says "Crafting Reagent", so those lines start off.
ns.DEFAULTS = { price = true, auction = false, quest = true, mobs = false, protect = true, alts = true,
                reagent = false, id = false, shift = false, quality = false, cursor = false }
-- Raise when a default changes for players who already have saved settings; ns.Migrate turns
-- the changed lines to their new default once.
ns.DEFAULTS_V = 2
function ns.Migrate(db)
    if (db.defaultsV or 1) < 2 then db.auction, db.reagent = false, false end
    db.defaultsV = ns.DEFAULTS_V
end

function ns.Set(key, on)
    ns.db[key] = on and true or false
    if ns.Refresh then ns.Refresh() end
end

function ns.Reset()
    for k, v in pairs(ns.DEFAULTS) do ns.db[k] = v end
    if ns.Refresh then ns.Refresh() end
end

-- One line for the hub's home page: how many lines are on.
function ns.Summary()
    if not ns.db then return nil end
    local n = 0
    for _, k in ipairs(ns.LINES) do if ns.db[k] then n = n + 1 end end
    return L.SUMMARY:format(n, #ns.LINES)
end

local function option(key)
    local K = key:upper()
    return { label = L["OPT_" .. K], tip = L["TIP_" .. K], icon = ns.OPT_ICON[key],
             get = function() return ns.db ~= nil and ns.db[key] == true end,
             set = function(on) if ns.db then ns.Set(key, on) end end }
end

if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({
        key = "Tooltip",
        icon = "Interface\\AddOns\\Gulli-Tooltip\\icon",
        slash = "/gtt",
        open = function() ns.Toggle() end,
        window = function() return ns.Window and ns.Window() end,
        summary = function() return ns.Summary() end,
        reset = function() ns.Reset() end,
        options = { option("price"), option("quest"), option("protect"), option("alts"), option("id"), option("shift") },
    })
end
