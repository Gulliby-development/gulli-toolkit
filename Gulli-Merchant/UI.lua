-- The window, wide: on the left what the visits earned and the switches in two groups (selling,
-- repair); on the right one list at a time, picked by its tab: what the next sale sells (untick
-- to keep an item this session), the "always sell" list with a place to drop an item, and the
-- suggestions. Sell now in the footer. A Sell junk button also sits on the vendor's own window.

local _, ns = ...
local L = ns.L
local S = ns.Skin
local J = ns.J

local frame, sellBtn, stats, list, empty, listCard, vendorBtn, tabs, headLine, headSum, drop
local subRows = {}

-- The tabs of the list: in the bags, always sell, suggested.
ns.TABS = { "bags", "always", "suggest" }
ns.tab = 1

local function showTip(r)
    local e = r.entry
    if not (e and GameTooltip and GameTooltip.SetOwner) then return end
    GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
    if e.item and e.item.bag and GameTooltip.SetBagItem then GameTooltip:SetBagItem(e.item.bag, e.item.slot)
    elseif GameTooltip.SetItemByID then GameTooltip:SetItemByID(e.id)
    else return end
    GameTooltip:Show()
end
local function hideTip() if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end end

local function makeRow(r)
    r.check = S.Check(r, 26)
    r.check:SetPoint("LEFT", -4, 0)
    r.check:SetScript("OnClick", function(self)
        local e = self:GetParent().entry
        if e.kind ~= "sell" then return end
        ns.skip[e.item.id] = e.item.checked and true or nil
        ns.Refresh()
    end)
    r.icon = S.ItemIcon(r, 24)
    -- "x": off the "always sell" list, or a suggestion not wanted.
    r.no = S.Button(r, 28, 26)
    r.no:SetPoint("RIGHT", -2, 0)
    r.no:SetText("x")
    r.no:SetScript("OnClick", function(self)
        local e = self:GetParent().entry
        if e.kind == "suggest" then ns.Dismiss(e.id) else J.SetAlways(e.id, false) end
        ns.Refresh()
    end)
    r.no:HookScript("OnEnter", function(self)
        if not (GameTooltip and GameTooltip.SetOwner) then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(self:GetParent().entry.kind == "suggest" and L.NO_SUGGEST or L.REMOVE)
        GameTooltip:Show()
    end)
    r.no:HookScript("OnLeave", hideTip)
    r.btn = S.FitButton(r, L.ADD, 26, 70)
    r.btn:SetPoint("RIGHT", r.no, "LEFT", -4, 0)
    r.btn:SetScript("OnClick", function(self) J.SetAlways(self:GetParent().entry.id, true); ns.Refresh() end)
    r.value = S.Text(r, 12, S.MUTED)
    r.value:SetJustifyH("RIGHT")
    r.name = S.Text(r, 12)
    r.name:SetWordWrap(false)
    if r.EnableMouse then r:EnableMouse(true) end
    r:SetScript("OnEnter", showTip)
    r:SetScript("OnLeave", hideTip)
end

local TAG = { always = "TAG_ALWAYS", unusable = "TAG_UNUSABLE" }

-- An item of the "always sell" list may not be loaded yet: ask for it and redraw when it comes.
local waiting = {}
local function itemName(id)
    local name, _, quality, _, _, _, _, _, _, icon = ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(id)
    if not name then
        waiting[id] = true
        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    end
    return name or "...", quality or 1, icon
end
local loader = CreateFrame("Frame")
loader:RegisterEvent("GET_ITEM_INFO_RECEIVED")
-- A list of items the client has not loaded answers in a burst: one redraw for all of it.
local redrawQueued
loader:SetScript("OnEvent", function(_, _, id)
    if not (id and waiting[id]) then return end
    waiting[id] = nil
    if not (C_Timer and C_Timer.After) then if ns.Refresh then ns.Refresh() end return end
    if redrawQueued then return end
    redrawQueued = true
    C_Timer.After(0.2, function()
        redrawQueued = nil
        if ns.Refresh then ns.Refresh() end
    end)
end)

local function fillRow(r, e)
    r.entry = e
    local it = e.item
    local name, quality, icon, count, tag
    if it then
        name, quality, icon, count, tag = it.name, it.quality, it.icon, it.count, TAG[it.why]
    else
        name, quality, icon = itemName(e.id)
    end
    if e.kind == "always" then tag, count = e.inBags and "TAG_INBAGS" or nil, nil end
    local sell = e.kind == "sell"
    r.check:SetShown(sell)
    if sell then r.check:SetChecked(it.checked) end
    r.icon:ClearAllPoints()
    if sell then r.icon:SetPoint("LEFT", r.check, "RIGHT", 4, 0) else r.icon:SetPoint("LEFT", 2, 0) end
    r.icon:Set(icon, count, quality)
    r.name:SetText(S.QualityHex(quality) .. name .. "|r" .. (tag and ("  " .. S.Hex(S.FAINT) .. L[tag] .. "|r") or ""))
    r.value:SetText(sell and S.MoneyText(it.value) or "")
    r.no:SetShown(not sell)
    r.btn:SetShown(e.kind == "suggest")
    r.value:ClearAllPoints()
    r.value:SetPoint("RIGHT", -4, 0)
    r.name:ClearAllPoints()
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
    if sell then r.name:SetPoint("RIGHT", r.value, "LEFT", -6, 0)
    else r.name:SetPoint("RIGHT", e.kind == "suggest" and r.btn or r.no, "LEFT", -8, 0) end
end

-- The rows of one tab (the shown one when none is given): what a sale sells, ticked or not; the
-- "always sell" list, each marked when it is in the bags; or the suggestions. Also the junk and
-- its ticked value.
function ns.Rows(tab)
    tab = ns.TABS[tab or ns.tab] or "bags"
    local junk, total = ns.Junk()
    local rows = {}
    if tab == "bags" then
        for _, it in ipairs(junk) do rows[#rows + 1] = { kind = "sell", item = it, id = it.id } end
    elseif tab == "always" then
        local inBags = {}
        for _, it in ipairs(junk) do inBags[it.id] = true end
        for _, id in ipairs(J.AlwaysIDs()) do rows[#rows + 1] = { kind = "always", id = id, inBags = inBags[id] } end
    else
        for _, id in ipairs(ns.Suggestions()) do rows[#rows + 1] = { kind = "suggest", id = id } end
    end
    return rows, junk, total
end

-- The footer line and its colour: what a sale would sell now, and what the player has to do.
function ns.StatusLine()
    local selling, sellValue = ns.ToSell()
    local ticked = 0
    for _, it in ipairs(ns.Junk()) do if it.checked then ticked = ticked + 1 end end
    if ticked == 0 then return L.NO_JUNK, S.MUTED, 0 end
    local text, color = L.JUNK:format(#selling, S.MoneyText(sellValue)), S.TEXT
    if ticked > #selling then text = L.JUNK_PART:format(#selling, ticked, S.MoneyText(sellValue))
    elseif #selling > J.BATCH then text, color = text .. " " .. L.BUYBACK, S.WARN end
    if not ns.atVendor then text = text .. " " .. L.OPEN_VENDOR end
    return text, color, #selling
end

local function tabLabel(i, n) return L["TAB_" .. ns.TABS[i]:upper()] .. (n > 0 and ("  " .. n) or "") end

function ns.Refresh()
    if vendorBtn then
        local n = #(ns.ToSell())
        vendorBtn:SetShown(ns.atVendor and n > 0)
        vendorBtn:SetText(L.SELL_JUNK:format(n))
    end
    if not frame or not frame:IsShown() then return end
    local rows, junk, total = ns.Rows()
    local kind = ns.TABS[ns.tab]
    if tabs.selected ~= ns.tab then tabs:Select(ns.tab, true) end
    tabs.buttons[1]:SetText(tabLabel(1, #junk))
    tabs.buttons[2]:SetText(tabLabel(2, #J.AlwaysIDs()))
    tabs.buttons[3]:SetText(tabLabel(3, #ns.Suggestions()))
    drop:SetShown(kind == "always")
    headLine:SetShown(kind ~= "always" and #rows > 0)
    headSum:SetShown(kind == "bags" and #rows > 0)
    headLine:SetText(kind == "bags" and L.KEEP_HINT or L.SUGGEST_HEAD)
    headSum:SetText(S.MoneyText(total))
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", 0, kind == "always" and -82 or -64)
    list:SetPoint("BOTTOMRIGHT", -10, 0)
    list:SetData(rows)
    empty:SetShown(#rows == 0)
    if kind == "bags" then empty:Set(L.NO_JUNK, L.EMPTY_SUB)
    elseif kind == "always" then empty:Set(L.EMPTY_ALWAYS, "")
    else empty:Set(L.EMPTY_SUGGEST, L.EMPTY_SUGGEST_SUB) end
    stats.tiles[1]:Set(S.MoneyText(ns.session.value, true), nil, L.STAT_SOLD:format(ns.session.sold))
    stats.tiles[2]:Set(S.MoneyText(ns.session.repair, true))
    -- A setting under a switch that is off does nothing: dim it.
    for _, sub in ipairs(subRows) do sub.row:SetAlpha(ns.db[sub.under] and 1 or 0.45) end
    local status, color, n = ns.StatusLine()
    frame.footer:SetStatus(status, color)
    sellBtn:SetEnabled(ns.atVendor and n > 0)
end

local function dropItem()
    local kind, id = GetCursorInfo()
    if kind ~= "item" or not id then return end
    ClearCursor()
    if J.Protected(id) then print("|cff9ad0ffGulli Merchant|r: " .. L.IS_PROTECTED) return end
    J.SetAlways(id, true)
    ns.Refresh()
end

local INDENT = 38 -- a setting under another one starts where that one's text starts

-- A card of switches: the first is the group's own, the others stand under it, indented.
-- defs: { key, label, desc, under = the key it depends on }.
local function group(parent, title, defs, width)
    local card = S.Card(parent, title)
    local st = S.Stack(card.body, 0)
    for i, d in ipairs(defs) do
        local key = d[1]
        S.rowWidth = width - 2 * S.INSET - (d.under and INDENT or 0)
        local row = S.SwitchRow(card.body, d[2], d[3], function() return ns.db[key] end,
            function(v) ns.db[key] = v; ns.Refresh() end, nil, not d.under and ns.OPT_ICON[key] or nil)
        if d.under then
            row.label:ClearAllPoints()
            if row.desc then
                row.label:SetPoint("TOPLEFT", INDENT, -9)
                row.label:SetPoint("TOPRIGHT", -56, -9)
            else
                row.label:SetPoint("LEFT", INDENT, 0)
                row.label:SetPoint("RIGHT", -56, 0)
            end
            subRows[#subRows + 1] = { row = row, under = d.under }
        end
        st:Add(row, row.height)
        row.line:SetShown(i < #defs)
    end
    S.rowWidth = nil
    return card, card:Fit(st:Height() - 6)
end

local function build()
    frame = S.Window("GulliMerchantFrame", L.TITLE, S.WIDE_W, S.DOCK_H)
    local ft = S.Footer(frame)
    sellBtn = S.Primary(S.FitButton(ft, L.SELL_NOW, 32, 110))
    ft:Add(sellBtn)
    sellBtn:SetScript("OnClick", function() ns.SellJunk() end)

    local body, width = frame.body, frame.inner[1]
    local leftW = 320
    local left = CreateFrame("Frame", nil, body)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(leftW)
    local st = S.Stack(left)
    stats = S.StatRow(left, { L.STAT_SOLD:format(0), L.STAT_REPAIR }, 62)
    st:Add(stats, 62)
    stats:Layout(leftW)
    local card, h = group(left, L.GROUP_SELL, {
        { "sell", L.OPT_SELL },
        { "unusable", L.ROW_UNUSABLE, L.DESC_UNUSABLE, under = "sell" },
        { "safe", L.OPT_SAFE, L.BUYBACK, under = "sell" } }, leftW)
    st:Add(card, h)
    card, h = group(left, L.GROUP_REPAIR, {
        { "repair", L.OPT_REPAIR },
        { "guild", L.ROW_GUILD, nil, under = "repair" } }, leftW)
    st:Add(card, h)
    local hint = S.Text(left, 12, S.FAINT)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.SHIFT)
    st:Add(hint, 30)

    listCard = S.Card(body)
    listCard:SetPoint("TOPLEFT", left, "TOPRIGHT", S.GAP, 0)
    listCard:SetPoint("BOTTOMRIGHT")
    local listW = (tonumber(width) or (S.WIDE_W - 2 * S.PAD)) - leftW - S.GAP - 2 * S.INSET
    tabs = S.Tabs(listCard.body, { tabLabel(1, 0), tabLabel(2, 0), tabLabel(3, 0) },
        math.floor((listW - 4) / 3), function(i) ns.tab = i; ns.Refresh() end, 30)
    -- One line over the list: what a tick does, or what the suggestions are; the value at its end.
    headSum = S.Text(listCard.body, 12, S.MUTED)
    headSum:SetPoint("TOPRIGHT", -10, -40)
    headSum:SetJustifyH("RIGHT")
    headLine = S.Text(listCard.body, 12, S.FAINT)
    headLine:SetPoint("TOPLEFT", 2, -40)
    headLine:SetPoint("RIGHT", headSum, "LEFT", -8, 0)
    headLine:SetJustifyH("LEFT")
    headLine:SetWordWrap(false)
    drop = S.DropZone(listCard.body, L.DROP, dropItem, 36)
    drop:SetPoint("TOPLEFT", 0, -38)
    drop:SetPoint("TOPRIGHT", 0, -38)
    list = S.List(listCard.body, 34, makeRow, fillRow)
    list:SetPoint("TOPLEFT", 0, -64)
    list:SetPoint("BOTTOMRIGHT", -10, 0)
    empty = S.Empty(list)
    empty:Set(L.NO_JUNK, L.EMPTY_SUB)
    frame:SetScript("OnShow", function() ns.Refresh() end)
end

-- The Sell junk button on the vendor's window, for a visit skipped with Shift or with
-- selling switched off.
function ns.ShowVendorButton()
    if vendorBtn or not MerchantFrame then if vendorBtn then vendorBtn:Show(); ns.Refresh() end return end
    vendorBtn = S.Primary(S.FitButton(MerchantFrame, L.SELL_JUNK:format(0), 26, 100))
    vendorBtn:SetPoint("TOPRIGHT", MerchantFrame, "TOPRIGHT", -40, -30)
    vendorBtn:SetFrameLevel((MerchantFrame:GetFrameLevel() or 1) + 10)
    vendorBtn:SetScript("OnClick", function() ns.SellJunk() end)
    ns.Refresh()
end

function ns.HideVendorButton() if vendorBtn then vendorBtn:Hide() end end

function ns.Toggle()
    S.ToggleWindow(ns.Window())
end

-- The window, for the hub (/gulli) to show inside it.
function ns.Window()
    if not frame then build() end
    return frame
end
