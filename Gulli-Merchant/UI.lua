-- The window, wide: on the left what the visits earned and the switches; on the right the
-- preview of what a sale sells (untick to keep an item this session), the "always sell" list
-- and the suggestions, with a place to drop an item. Sell now in the footer. A Sell junk button
-- also sits on the vendor's own window.

local _, ns = ...
local L = ns.L
local S = ns.Skin
local J = ns.J

local frame, sellBtn, stats, list, empty, listCard, vendorBtn

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
    r.icon:SetPoint("LEFT", r.check, "RIGHT", 4, 0)
    r.btn = S.Button(r, 70, 26)
    r.btn:SetPoint("RIGHT", -2, 0)
    r.btn:SetScript("OnClick", function(self)
        local e = self:GetParent().entry
        if e.kind == "suggest" then J.SetAlways(e.id, true)
        else J.SetAlways(e.id, false) end
        ns.Refresh()
    end)
    r.no = S.Button(r, 28, 26)
    r.no:SetPoint("RIGHT", r.btn, "LEFT", -4, 0)
    r.no:SetText("x")
    r.no:SetScript("OnClick", function(self) ns.Dismiss(self:GetParent().entry.id); ns.Refresh() end)
    r.value = S.Text(r, 11, S.MUTED)
    r.value:SetJustifyH("RIGHT")
    r.name = S.Text(r, 12)
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
    r.name:SetWordWrap(false)
end

local TAG = { always = "TAG_ALWAYS", unusable = "TAG_UNUSABLE" }

local function itemName(id)
    local name, _, quality, _, _, _, _, _, _, icon = ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(id)
    return name or ("item:" .. id), quality or 1, icon
end

local function fillRow(r, e)
    r.entry = e
    local it = e.item
    local name, quality, icon, count, tag
    if it then
        name, quality, icon, count, tag = it.name, it.quality, it.icon, it.count, TAG[it.why]
    else
        name, quality, icon = itemName(e.id)
    end
    if e.kind == "suggest" then tag = "TAG_SUGGEST" end
    r.check:SetShown(e.kind == "sell")
    if it then r.check:SetChecked(it.checked) end
    r.icon:Set(icon, count, quality)
    r.name:SetText(S.QualityHex(quality) .. name .. "|r" .. (tag and ("  " .. S.Hex(S.FAINT) .. L[tag] .. "|r") or ""))
    r.value:SetText(it and ns.Money(it.value) or "")
    -- The row's button: remove from the "always" list, or add a suggestion to it.
    local showBtn = e.kind == "suggest" or e.kind == "always" or (it and it.why == "always")
    r.btn:SetShown(showBtn)
    r.btn:SetText(e.kind == "suggest" and L.ADD or L.REMOVE)
    r.no:SetShown(e.kind == "suggest")
    r.value:ClearAllPoints()
    r.value:SetPoint("RIGHT", showBtn and (e.kind == "suggest" and r.no or r.btn) or r, showBtn and "LEFT" or "RIGHT",
        showBtn and -8 or -4, 0)
    r.name:SetPoint("RIGHT", r.value, "LEFT", -6, 0)
end

-- The rows: what a sale sells (ticked or not), then "always sell" items not in the bags,
-- then the suggestions.
function ns.Rows()
    local junk, total = ns.Junk()
    local rows, inBags = {}, {}
    for _, it in ipairs(junk) do
        rows[#rows + 1] = { kind = "sell", item = it, id = it.id }
        inBags[it.id] = true
    end
    for _, id in ipairs(J.AlwaysIDs()) do
        if not inBags[id] then rows[#rows + 1] = { kind = "always", id = id } end
    end
    for _, id in ipairs(ns.Suggestions()) do rows[#rows + 1] = { kind = "suggest", id = id } end
    return rows, junk, total
end

function ns.Refresh()
    if vendorBtn then
        local n = #(ns.ToSell())
        vendorBtn:SetShown(ns.atVendor and n > 0)
        vendorBtn:SetText(L.SELL_JUNK:format(n))
    end
    if not frame or not frame:IsShown() then return end
    local rows, junk, total = ns.Rows()
    local selling, sellValue = ns.ToSell()
    list:SetData(rows)
    empty:SetShown(#rows == 0)
    listCard:SetTitle(L.WILL_SELL, #junk > 0 and ns.Money(total) or "")
    stats.tiles[1]:Set(ns.ShortMoney(total))
    stats.tiles[2]:Set(ns.ShortMoney(ns.session.value), nil, L.STAT_SOLD:format(ns.session.sold))
    stats.tiles[3]:Set(ns.ShortMoney(ns.session.repair))
    local status, color
    if #selling == 0 then status, color = L.NO_JUNK, S.MUTED
    elseif #selling > 12 then status, color = L.JUNK:format(#selling, ns.Money(sellValue)) .. " " .. L.BUYBACK, S.WARN
    else status, color = L.JUNK:format(#selling, ns.Money(sellValue)), S.TEXT end
    frame.footer:SetStatus(status, color)
    sellBtn:SetEnabled(ns.atVendor and #selling > 0)
end

local function dropItem()
    local kind, id = GetCursorInfo()
    if kind ~= "item" or not id then return end
    ClearCursor()
    if J.Protected(id) then print("|cff9ad0ffGulli Merchant|r: " .. L.IS_PROTECTED) return end
    J.SetAlways(id, true)
    ns.Refresh()
end

local function build()
    frame = S.Window("GulliMerchantFrame", L.TITLE, S.WIDE_W, S.DOCK_H)
    local ft = S.Footer(frame)
    sellBtn = S.Primary(S.FitButton(ft, L.SELL_NOW, 32, 110))
    ft:Add(sellBtn)
    sellBtn:SetScript("OnClick", function() ns.SellJunk() end)

    local body, width = frame.body, frame.inner[1]
    local leftW = 340
    local left = CreateFrame("Frame", nil, body)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(leftW)
    local st = S.Stack(left)
    stats = S.StatRow(left, { L.STAT_JUNK, L.STAT_SOLD:format(0), L.STAT_REPAIR }, 62,
        { "Interface\\Icons\\INV_Misc_Bag_08", ns.OPT_ICON.sell, ns.OPT_ICON.repair })
    st:Add(stats, 62)
    stats:Layout(leftW)
    for _, t in ipairs(stats.tiles) do t.icon:Hide(); t.value:SetPoint("TOPRIGHT", -S.INSET, -12) end
    local rows = {}
    for _, o in ipairs({ { "sell", L.OPT_SELL }, { "repair", L.OPT_REPAIR }, { "guild", L.OPT_GUILD },
                         { "safe", L.OPT_SAFE }, { "unusable", L.OPT_UNUSABLE } }) do
        local key = o[1]
        rows[#rows + 1] = { o[2], nil, function() return ns.db[key] end,
                            function(v) ns.db[key] = v; ns.Refresh() end, icon = ns.OPT_ICON[key] }
    end
    local card, h = S.SettingsCard(left, nil, rows)
    st:Add(card, h)
    local tip, th = S.Paragraph(left, L.SHIFT .. "\n\n" .. L.ALT_HELP, leftW)
    st:Add(tip, th)

    listCard = S.Card(body, L.WILL_SELL, "", "Interface\\Icons\\INV_Misc_Coin_02")
    listCard:SetPoint("TOPLEFT", left, "TOPRIGHT", S.GAP, 0)
    listCard:SetPoint("BOTTOMRIGHT")
    local drop = S.DropZone(listCard.body, L.DROP, dropItem, 36)
    drop:SetPoint("TOPLEFT")
    drop:SetPoint("TOPRIGHT")
    list = S.List(listCard.body, 34, makeRow, fillRow)
    list:SetPoint("TOPLEFT", 0, -36 - 8)
    list:SetPoint("BOTTOMRIGHT", -10, 0)
    empty = S.Empty(list)
    empty:Set(L.NO_JUNK, L.EMPTY_SUB)
    frame:SetScript("OnShow", function() ns.Refresh() end)
    if width then left:SetWidth(leftW) end
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
