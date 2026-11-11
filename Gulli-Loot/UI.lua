-- The rules: one row per quality with Ask / Greed / Pass, then the item rules (drop an item
-- to add one; tap its rule to change it, x to remove it).

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, list, empty
local tabs = {}
local QUALITY_COLOR = { [0] = "|cff9d9d9d", [1] = "|cffffffff", [2] = "|cff1eff00" }

local function indexOf(t, v) for i, x in ipairs(t) do if x == v then return i end end return 1 end

local function makeRow(r)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(22, 22)
    r.icon:SetPoint("LEFT", 6, 0)
    r.remove = S.Button(r, 28, 28)
    r.remove:SetPoint("RIGHT", -2, 0)
    r.remove:SetText("x")
    r.remove:SetScript("OnClick", function(self) ns.SetItem(self:GetParent().entry.id, nil) end)
    r.rule = S.Button(r, 90, 28)
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
    S.Fill(r, S.ROW)
end

function ns.Refresh()
    if not frame or not frame:IsShown() then return end
    for q, t in pairs(tabs) do
        t:Select(indexOf(ns.RULES, ns.db.quality[q] or "ask"))
    end
    local items = ns.Items()
    list:SetData(items)
    empty:SetShown(#items == 0)
end

local function dropItem()
    local kind, id = GetCursorInfo()
    if kind == "item" and id then
        ClearCursor()
        if not ns.db.items[id] then ns.SetItem(id, "greed") end
    end
end

local function build()
    frame = S.Window("GulliLootFrame", L.TITLE, 480, 470)
    local body = frame.body
    local labels = { L.RULE_ASK, L.RULE_GREED, L.RULE_PASS }
    for i, q in ipairs(ns.QUALITIES) do
        local row = CreateFrame("Frame", nil, body)
        row:SetSize(330, 30)
        row:SetPoint("TOPRIGHT", 0, -(i - 1) * 36)
        local name = S.Text(body, 12)
        name:SetPoint("RIGHT", row, "LEFT", -8, 0)
        name:SetPoint("LEFT", body, "LEFT", 0, 0)
        name:SetText(QUALITY_COLOR[q] .. L["Q" .. q] .. "|r")
        tabs[q] = S.Tabs(row, labels, 106, function(sel) ns.db.quality[q] = ns.RULES[sel] end)
    end
    local note = S.Note(body, 11)
    note:SetPoint("TOPLEFT", 0, -112)
    note:SetPoint("RIGHT", 0, 0)
    note:SetText(L.NOTE)
    list = S.List(body, 32, makeRow, fillRow)
    list:SetPoint("TOPLEFT", 0, -160)
    list:SetPoint("BOTTOMRIGHT", -12, 80)
    empty = S.Note(body, 12)
    empty:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -6)
    empty:SetPoint("RIGHT", -16, 0)
    empty:SetText(L.NO_ITEMS)
    local drop = S.Button(body, 1, 34)
    drop:SetPoint("BOTTOMLEFT", 0, 38)
    drop:SetPoint("BOTTOMRIGHT", 0, 38)
    drop:SetText(L.DROP)
    drop:SetScript("OnClick", dropItem)
    drop:SetScript("OnReceiveDrag", dropItem)
    local c = S.CheckRow(body, L.OPT_REPORT, function() return ns.db.report end, function(v) ns.db.report = v end)
    c:SetPoint("BOTTOMLEFT", 0, 0)
    frame:SetScript("OnShow", function() ns.Refresh() end)
end

function ns.Toggle()
    if not frame then build() end
    frame:SetShown(not frame:IsShown())
end
