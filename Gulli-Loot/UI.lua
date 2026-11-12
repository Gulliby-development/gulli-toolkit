-- The rules: one row per quality with Ask / Greed / Pass, then the item rules (drop an item
-- to add one; tap its rule to change it, x to remove it).

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, list, empty, itemsCard
local tabs = {}
local QUALITY_COLOR = { [0] = "|cff9d9d9d", [1] = "|cffffffff", [2] = "|cff1eff00" }

local function indexOf(t, v) for i, x in ipairs(t) do if x == v then return i end end return 1 end

local function makeRow(r)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(22, 22)
    r.icon:SetPoint("LEFT", 2, 0)
    r.remove = S.Close(r, function(self) ns.SetItem(self:GetParent().entry.id, nil) end)
    r.remove:SetPoint("RIGHT", 0, 0)
    r.rule = S.Button(r, 96, 28)
    r.rule:SetPoint("RIGHT", r.remove, "LEFT", -6, 0)
    r.rule:SetScript("OnClick", function(self)
        local e = self:GetParent().entry
        local i = indexOf(ns.ITEM_RULES, e.rule) % #ns.ITEM_RULES + 1
        ns.SetItem(e.id, ns.ITEM_RULES[i])
    end)
    r.text = S.Text(r, 12)
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
    r.text:SetPoint("RIGHT", r.rule, "LEFT", -8, 0)
    r.text:SetWordWrap(false)
end

local function itemName(id)
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    if not name and GetItemInfo then name = GetItemInfo(id) end
    return name or ("#" .. id)
end

local function fillRow(r, e)
    r.entry = e
    r.icon:SetTexture((C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(e.id)) or
        "Interface\\Icons\\INV_Misc_QuestionMark")
    r.text:SetText(itemName(e.id))
    r.rule:SetText(L["RULE_" .. e.rule:upper()])
end

function ns.Refresh()
    if not frame or not frame:IsShown() then return end
    for q, t in pairs(tabs) do
        t:Select(indexOf(ns.RULES, ns.db.quality[q] or "ask"))
    end
    local items = ns.Items()
    list:SetData(items)
    empty:SetShown(#items == 0)
    itemsCard:SetTitle(L.SEC_ITEMS, #items > 0 and tostring(#items) or "")
end

local function dropItem()
    local kind, id = GetCursorInfo()
    if kind == "item" and id then
        ClearCursor()
        if not ns.db.items[id] then ns.SetItem(id, "greed") end
    end
end

local function build()
    frame = S.Window("GulliLootFrame", L.TITLE, 500, 600)
    local body, width = frame.body, frame.inner[1]
    local st = S.Stack(body)

    local labels = { L.RULE_ASK, L.RULE_GREED, L.RULE_PASS }
    local qrows = {}
    for i, q in ipairs(ns.QUALITIES) do
        local holder = CreateFrame("Frame", nil, body)
        holder:SetSize(3 * 86 + 4, 30)
        tabs[q] = S.Tabs(holder, labels, 86, function(sel) ns.db.quality[q] = ns.RULES[sel] end)
        qrows[i] = { QUALITY_COLOR[q] .. L["Q" .. q] .. "|r", nil, control = holder }
    end
    local quality, qh = S.SettingsCard(body, L.SEC_QUALITY, qrows)
    st:Add(quality, qh, 8)
    local note, nh = S.Paragraph(body, L.NOTE, width)
    st:Add(note, nh)

    itemsCard = S.Card(body, L.SEC_ITEMS)
    st:Add(itemsCard, 230)
    local drop = S.DropZone(itemsCard.body, L.DROP, dropItem, 36)
    drop:SetPoint("BOTTOMLEFT")
    drop:SetPoint("BOTTOMRIGHT")
    list = S.List(itemsCard.body, 34, makeRow, fillRow)
    list:SetPoint("TOPLEFT")
    list:SetPoint("BOTTOMRIGHT", drop, "TOPRIGHT", -10, 8)
    empty = S.Empty(list)
    empty:Set(L.NO_ITEMS)

    local report, rh = S.SettingsCard(body, nil, {
        { L.OPT_REPORT, nil, function() return ns.db.report end, function(v) ns.db.report = v end,
          icon = "Interface\\Icons\\INV_Letter_01" } })
    st:Add(report, rh)
    S.FitWindow(frame, st:Height())
    frame:SetScript("OnShow", function() ns.Refresh() end)
end

function ns.Toggle()
    if not frame then build() end
    frame:SetShown(not frame:IsShown())
end
