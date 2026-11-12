-- Adds lines to item and NPC tooltips: the vendor price of a full stack, the quests in the
-- log that still need the item (with the count), and the item or NPC id.

local ADDON, ns = ...
local L = ns.L

local MUTED, QUEST = { 0.6, 0.6, 0.62 }, { 1, 0.82, 0 }
local WHITE, DONE = { 1, 1, 1 }, { 0.42, 0.84, 0.50 }

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

function ns.Money(copper)
    copper = math.floor(copper or 0)
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
    return table.concat(parts, " ")
end

-- Quests in the log whose item objectives name the item: { { title, have, need } }.
-- Rebuilt when the log changes, so a tooltip only reads a table.
local needs
function ns.QuestNeeds(name)
    if not name then return {} end
    if not needs then
        needs = {}
        for _, q in ipairs(questEntries()) do
            for _, o in ipairs(C_QuestLog.GetQuestObjectives(q.id) or {}) do
                if o.type == "item" and o.text and not o.finished then
                    needs[#needs + 1] = { title = q.title, text = o.text, have = o.numFulfilled or 0,
                                          need = o.numRequired or 0 }
                end
            end
        end
    end
    local out = {}
    for _, n in ipairs(needs) do
        if n.text:find(name, 1, true) then out[#out + 1] = n end
    end
    return out
end

function ns.Forget() needs = nil end

-- The lines for an item: { { left, right, color } }.
function ns.ItemLines(id)
    local out = {}
    if not id or secret(id) then return out end
    local name, maxStack, price = itemInfo(id)
    if ns.db.price and price > 0 and maxStack > 1 then
        out[#out + 1] = { L.STACK:format(maxStack), ns.Money(price * maxStack), MUTED }
    end
    if ns.db.quest then
        for _, n in ipairs(ns.QuestNeeds(name)) do
            -- The count turns green once the bags hold enough.
            out[#out + 1] = { L.QUEST:format(n.title), n.have .. "/" .. n.need, QUEST,
                              n.need > 0 and n.have >= n.need and DONE or WHITE }
        end
    end
    if ns.db.id then out[#out + 1] = { L.ITEM_ID, tostring(id), MUTED } end
    return out
end

-- The NPC id from a unit GUID ("Creature-0-1-2-3-<npcID>-<spawn>").
function ns.NpcID(guid)
    if not guid or secret(guid) then return nil end
    local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

function ns.UnitLines(guid)
    local id = ns.db.id and ns.NpcID(guid)
    return id and { { L.NPC_ID, tostring(id), MUTED } } or {}
end

local function add(tt, lines)
    for _, l in ipairs(lines) do
        local c, r = l[3], l[4] or WHITE
        tt:AddDoubleLine(l[1], l[2], c[1], c[2], c[3], r[1], r[2], r[3])
    end
    if #lines > 0 then tt:Show() end
end

local function hook()
    if TooltipDataProcessor and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
            if data then add(tt, ns.ItemLines(data.id)) end
        end)
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt, data)
            if data then add(tt, ns.UnitLines(data.guid)) end
        end)
    elseif GameTooltip then
        GameTooltip:HookScript("OnTooltipSetItem", function(tt)
            local _, link = tt:GetItem()
            local id = link and tonumber(link:match("item:(%d+)"))
            add(tt, ns.ItemLines(id))
        end)
        GameTooltip:HookScript("OnTooltipSetUnit", function(tt)
            local _, unit = tt:GetUnit()
            add(tt, ns.UnitLines(unit and UnitGUID(unit)))
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
        for k, v in pairs({ price = true, quest = true, id = false }) do
            if ns.db[k] == nil then ns.db[k] = v end
        end
        self:RegisterEvent("QUEST_LOG_UPDATE")
        hook()
        return
    end
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
    quest = "Interface\\Icons\\INV_Misc_Note_01",
    id = "Interface\\Icons\\INV_Misc_Gear_01",
}

local function option(key, label)
    return { label = label, icon = ns.OPT_ICON[key], get = function() return ns.db ~= nil and ns.db[key] == true end,
             set = function(on) if ns.db then ns.db[key] = on and true or false end end }
end

if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({
        key = "Tooltip",
        icon = "Interface\\AddOns\\Gulli-Tooltip\\icon",
        slash = "/gtt",
        open = function() ns.Toggle() end,
        window = function() return ns.Window and ns.Window() end,
        options = {
            option("price", ns.L.OPT_PRICE),
            option("quest", ns.L.OPT_QUEST),
            option("id", ns.L.OPT_ID),
        },
    })
end
