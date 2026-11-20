-- Adds lines to item, NPC and spell tooltips: "protected" from the Gulli Toolkit, the quests in
-- the log that still need the item, how many you and your other characters hold (from Gulli
-- Chores), the vendor and auction price of a full stack (Auctionator), which of your professions
-- use it (from Gulli Craft Profit), where it drops (from the Dungeon Journal), and ids. Prices
-- and ids can wait for Shift. The lines go into the Gulli block that every module shares.

local ADDON, ns = ...
local L = ns.L

-- Game API wrappers.
local function itemInfo(id)
    local name, _, _, _, _, _, _, maxStack, _, _, price = ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(id)
    return name, maxStack or 1, price or 0
end
local function secret(v) return issecretvalue and issecretvalue(v) end
-- How many this character has: in the bags, in the bank.
local function ownCount(id)
    local count = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not count then return 0, 0 end
    local bags = tonumber((count(id))) or 0
    local all = tonumber((count(id, true))) or bags
    return bags, math.max(0, all - bags)
end
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

-- Quests in the log whose objectives name the item: { { title, name, have, need } }.
-- Rebuilt when the log changes, so a tooltip only reads a table.
local needs
local function allNeeds()
    if not needs then
        needs = {}
        for _, q in ipairs(questEntries()) do
            for _, o in ipairs(C_QuestLog.GetQuestObjectives(q.id) or {}) do
                if o.type == "item" and o.text and not o.finished then
                    needs[#needs + 1] = { title = q.title, name = ns.ObjectiveName(o.text),
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
        if n.name == name then out[#out + 1] = n end
    end
    return out
end

function ns.Forget() needs = nil end

local function shiftDown() return IsShiftKeyDown ~= nil and IsShiftKeyDown() == true end

-- Prices and ids wait for Shift when the player wants a short tooltip.
local function extra(key)
    return ns.db[key] and (not ns.db.shift or shiftDown())
end

-- From any price addon (Auctionator, auxForever, Naowh Forever, ...), through the shared reader.
local function auctionPrice(id)
    return ns.Skin and ns.Skin.AuctionPrice and (ns.Skin.AuctionPrice(id)) or nil
end

-- How many the other characters hold, from Gulli Chores' snapshots (read only):
-- { { name, class, bags, bank } }, the most first. This character is counted by the game.
function ns.AltCounts(id)
    local out = {}
    local db = GulliChoresDB
    if type(db) ~= "table" or type(db.chars) ~= "table" then return out end
    -- this character: an empty realm name from the game means the realm Chores saved last
    local name = UnitName("player") or ""
    local realm = GetRealmName and GetRealmName() or ""
    if realm == "" then realm = type(db.realm) == "string" and db.realm or "" end
    local me, bare = name .. "-" .. realm, name .. "-"
    for key, c in pairs(db.chars) do
        local bags = c.items and c.items[id] or 0
        local bank = c.bank and c.bank[id] or 0
        if key ~= me and key ~= bare and bags + bank > 0 then
            out[#out + 1] = { name = c.name or key, class = c.class, bags = bags, bank = bank }
        end
    end
    table.sort(out, function(a, b)
        local x, y = a.bags + a.bank, b.bags + b.bank
        if x ~= y then return x > y end
        return a.name < b.name
    end)
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
                        reagentOf[rid][prof] = p.icon or true
                    end
                end
            end
        end
    end
    local out = {}
    for prof in pairs(reagentOf[id] or {}) do out[#out + 1] = prof end
    table.sort(out)
    -- The second value: the first profession's own icon, when Craft Profit saved it.
    local icon = out[1] and reagentOf[id][out[1]]
    return out, icon ~= true and icon or nil
end

local function classHex(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return c and string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) or "|cffffffff"
end

-- The colours come from the skin, which loads after this file: read at call time.
local function C(key) return ns.Skin[key] end
local function hex(key, text) return ns.Skin.Hex(ns.Skin[key]) .. text .. "|r" end

-- The picture of each group's first line; the switches in the window show the same ones.
local ICON = {
    quest = "Interface\\GossipFrame\\AvailableQuestIcon",
    done = "Interface\\RaidFrame\\ReadyCheck-Ready",
}
local STOCK_ROWS = 4

-- The lines of who holds the item: the total, then this character and the others in their
-- class colours, "bags · bank". A lone count in the bags needs no rows under it.
function ns.StockLines(id, maxStack)
    local bags, bank = ownCount(id)
    local alts = ns.AltCounts(id)
    local total = bags + bank
    for _, a in ipairs(alts) do total = total + a.bags + a.bank end
    if total == 0 or (#alts == 0 and bank == 0 and (maxStack or 1) <= 1) then return {} end
    local out = { { group = "stock", icon = ns.OPT_ICON.alts, left = L.YOU_HAVE, right = tostring(total),
                    color = C("MUTED") } }
    if #alts == 0 and bank == 0 then return out end
    local rows = {}
    if bags + bank > 0 then
        local _, class = UnitClass("player")
        rows[1] = { name = UnitName("player"), class = class, bags = bags, bank = bank }
    end
    for _, a in ipairs(alts) do rows[#rows + 1] = a end
    for i, a in ipairs(rows) do
        if i > STOCK_ROWS then
            out[#out + 1] = { group = "stock", sub = true, left = L.MORE:format(#rows - STOCK_ROWS), color = C("FAINT") }
            break
        end
        local right = a.bank > 0 and hex("FAINT", L.BANK_N:format(a.bank)) or ""
        if a.bags > 0 then right = a.bags .. (right ~= "" and hex("FAINT", " · ") or "") .. right end
        out[#out + 1] = { group = "stock", sub = true, left = classHex(a.class) .. a.name .. "|r", right = right }
    end
    return out
end

-- Where the item drops, from the Dungeon Journal (read only): the boss with the best chance,
-- then its dungeon and whether the item is on the wish list.
function ns.DropLines(id)
    local J = GulliDungeonJournal
    if type(J) ~= "table" or not J.DropsOf then return {} end
    local ok, drops = pcall(J.DropsOf, id)
    local d = ok and type(drops) == "table" and drops[1]
    local wished = J.Wished and J.Wished(id) == true
    local out = {}
    if d then
        local pct = tonumber(d.pct) or 0
        out[1] = { group = "source", icon = ns.OPT_ICON.drops, left = tostring(d.boss), color = C("GOLD"),
                   right = pct > 0 and (pct .. hex("FAINT", "%")) or nil }
        local where = J.Name and J.Name(d.key)
        if where or wished then
            local text = where or ""
            if wished then text = text .. (where and hex("FAINT", " · ") or "") .. hex("GOOD", where and L.WISHED or ns.Skin.Cap(L.WISHED)) end
            out[2] = { group = "source", sub = true, left = text, color = C("MUTED") }
        end
    elseif wished then
        out[1] = { group = "source", icon = ns.OPT_ICON.drops, left = ns.Skin.Cap(L.WISHED), color = C("GOOD") }
    end
    return out
end

-- The lines for an item, for the Gulli block (see S.TipCollect in the skin): protected, quests,
-- who holds it, prices, professions, where it drops, the id.
function ns.ItemLines(id)
    local out = {}
    if not id or secret(id) then return out end
    local name, maxStack, price = itemInfo(id)
    local function add(l) out[#out + 1] = l end
    if ns.db.protect and GulliToolkit and GulliToolkit.IsProtected and GulliToolkit.IsProtected(id) then
        add({ group = "state", icon = ns.OPT_ICON.protect, left = L.PROTECTED, color = C("GOOD") })
    end
    if ns.db.quest then
        for i, n in ipairs(ns.QuestNeeds(name)) do
            -- Enough in the bags: a green count with a check mark, so it is not colour alone.
            local done = n.need > 0 and n.have >= n.need
            add({ group = "quest", tag = "quest", icon = i == 1 and ICON.quest or nil, sub = i > 1,
                  left = n.title, color = C("GOLD"),
                  right = done and (ns.Skin.TipIcon(ICON.done) .. n.have .. "/" .. n.need)
                      or (n.have .. hex("FAINT", "/" .. n.need)),
                  rcolor = done and C("GOOD") or C("TEXT") })
        end
    end
    if ns.db.alts then
        for _, l in ipairs(ns.StockLines(id, maxStack)) do add(l) end
    end
    local times = maxStack > 1 and hex("FAINT", " ×" .. maxStack) or ""
    local vendor = price * maxStack
    if extra("price") and price > 0 and maxStack > 1 then
        add({ group = "price", icon = ns.OPT_ICON.price, left = L.VENDOR .. times, right = ns.Money(vendor),
              color = C("MUTED") })
    end
    if extra("auction") then
        -- Auctionator shows the price of one; for a stack item this line gives the full stack.
        local ah = auctionPrice(id)
        if ah and ah > 0 then
            add({ group = "price", icon = ns.OPT_ICON.auction, left = L.AUCTION .. times,
                  right = ns.Money(ah * maxStack), color = C("MUTED") })
            -- After the auction house's cut a vendor would pay more.
            if price > 0 and ah * (1 - ns.AH_CUT) < price then
                add({ group = "price", sub = true, left = L.VENDOR_BETTER, color = C("GOOD") })
            end
        end
    end
    if ns.db.reagent then
        local profs, icon = ns.ReagentFor(id)
        if #profs > 0 then
            add({ group = "craft", icon = icon or ns.OPT_ICON.reagent, left = table.concat(profs, ", "),
                  color = C("MUTED") })
        end
    end
    if ns.db.drops then
        for _, l in ipairs(ns.DropLines(id)) do add(l) end
    end
    if extra("id") then add({ group = "id", left = L.ID:format(id), color = C("FAINT") }) end
    return out
end
ns.AH_CUT = 0.05

-- The NPC id from a unit GUID ("Creature-0-1-2-3-<npcID>-<spawn>").
function ns.NpcID(guid)
    if not guid or secret(guid) then return nil end
    local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

-- An NPC gets only its id: the game itself lists the kill objectives on it.
function ns.UnitLines(guid)
    local id = extra("id") and ns.NpcID(guid)
    if id then return { { group = "id", left = L.ID:format(id), color = C("FAINT") } } end
    return {}
end

-- Spell and aura ids, under the same switch.
function ns.SpellLines(id)
    if not extra("id") or not id or secret(id) then return {} end
    return { { group = "id", left = L.ID:format(id), color = C("FAINT") } }
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

-- Our lines go into the shared Gulli block of the skin, with every other module's.
local function hook()
    local S = ns.Skin
    S.TipProvider("item", "Tooltip", function(id, tt)
        if tt then paintBorder(tt, id) end
        return ns.ItemLines(id)
    end)
    S.TipProvider("unit", "Tooltip", function(guid) return ns.UnitLines(guid) end)
    S.TipProvider("spell", "Tooltip", function(id) return ns.SpellLines(id) end)
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
    price = "Interface\\Icons\\INV_Misc_Coin_02",
    auction = "Interface\\Minimap\\Tracking\\Auctioneer",
    quest = "Interface\\Icons\\INV_Misc_Note_01",
    protect = "Interface\\Icons\\INV_Misc_Key_03",
    alts = "Interface\\Icons\\INV_Misc_Bag_08",
    drops = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
    reagent = "Interface\\Icons\\Trade_Tailoring",
    id = "Interface\\Icons\\INV_Misc_Gear_01",
    shift = "Interface\\Icons\\INV_Misc_Key_14",
    quality = "Interface\\Icons\\INV_Misc_Gem_Pearl_04",
    cursor = "Interface\\Icons\\Ability_Hunter_MarkedForDeath",
}

-- The switches in window order; a new line gets its key here, a default, a text and a test.
ns.LINES = { "protect", "quest", "alts", "price", "auction", "reagent", "drops", "id" }
ns.LOOK = { "shift", "quality", "cursor" }
-- Auctionator shows its own auction line and the game says "Crafting Reagent", so those lines
-- start off.
ns.DEFAULTS = { price = true, auction = false, quest = true, protect = true, alts = true, drops = true,
                reagent = false, id = false, shift = false, quality = false, cursor = false }
-- Raise when a default changes for players who already have saved settings; ns.Migrate turns
-- the changed lines to their new default once.
ns.DEFAULTS_V = 2
function ns.Migrate(db)
    if (db.defaultsV or 1) < 2 then db.auction, db.reagent = false, false end
    db.mobs = nil -- the kill line on NPCs is gone: the game shows it
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

-- With the hub: its row and button there; alone: its own minimap button (Skin.lua).
do
    local register = GulliToolkit and GulliToolkit.Register or function(info) ns.alone = info end
    register({
        key = "Tooltip",
        icon = "Interface\\AddOns\\Gulli-Tooltip\\icon",
        slash = "/gtt",
        open = function() ns.Toggle() end,
        window = function() return ns.Window and ns.Window() end,
        summary = function() return ns.Summary() end,
        reset = function() ns.Reset() end,
        options = { option("protect"), option("quest"), option("alts"), option("price"), option("drops"), option("shift") },
    })
end
