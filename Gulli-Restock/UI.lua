-- The window in three tabs: the keep list of the chosen set (icon, name, in bags / in the
-- bank / how long it lasts, - and + for the amount), what the open vendor offers to add, and
-- the settings. Beside the vendor: the preview of what would be bought (untick or change a
-- line), beside the bank: what would move. Alt+click on a vendor item opens a quick buy.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, tabs, pages = nil, nil, {}
local list, empty, card, setBtn, delBtn, addEdit
local offers, noOffers
local planFrame, planList, planOk
local bankFrame, bankList, bankMoves
local quick
local currentPlan

local function money(copper)
    if GetCoinTextureString then return GetCoinTextureString(copper or 0) end
    return tostring(copper or 0)
end

-- The keep list ------------------------------------------------------------------------------

local function makeRow(r)
    r.entry = false
    r.icon = S.IconBox(r, 26)
    r.icon:SetPoint("LEFT", 2, 0)
    r.remove = S.Close(r, function(self) ns.Set(self:GetParent().entry.id, 0) end)
    r.remove:SetPoint("RIGHT", 0, 0)
    r.step = S.Stepper(r, function() return r.entry and r.entry.want or 0 end, function(v)
        if r.entry then ns.Set(r.entry.id, v) end
    end, 1, 0, 9999, nil, 110)
    r.step:SetPoint("RIGHT", r.remove, "LEFT", -8, 0)
    r.text = S.Text(r, 12)
    r.text:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 10, 1)
    r.text:SetPoint("RIGHT", r.step, "LEFT", -8, 0)
    r.text:SetWordWrap(false)
    r.have = S.Text(r, 10, S.MUTED)
    r.have:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 10, -2)
    r.have:SetPoint("RIGHT", r.step, "LEFT", -8, 0)
    r.have:SetWordWrap(false)
end

local function fillRow(r, e)
    r.entry = e
    r.icon:SetIcon(ns.EntryIcon(e.id))
    r.text:SetText(ns.EntryName(e.id) .. (e.best and ("  " .. S.Hex(S.FAINT) .. L.BEST_TAG .. "|r") or ""))
    -- None left red, too few orange, enough green.
    local c = e.have == 0 and S.BAD or (e.have < e.want and S.WARN or S.GOOD)
    local parts = { S.Hex(c) .. L.HAVE:format(e.have) .. "|r" }
    if e.bank > 0 then parts[#parts + 1] = L.IN_BANK:format(e.bank) end
    if e.hours then
        local h = e.hours
        parts[#parts + 1] = (h < 2 and S.Hex(S.WARN) or "") .. L.LASTS:format(math.max(1, math.floor(h + 0.5))) .. "|r"
    end
    r.have:SetText(table.concat(parts, "  "))
    r.step.step = ns.StepOf(e.id)
    -- The stepper moves by the item's stack.
    local stepSize = r.step.step
    r.step.minus:SetScript("OnClick", function() ns.Set(e.id, math.max(0, e.want - stepSize)) end)
    r.step.plus:SetScript("OnClick", function() ns.Set(e.id, e.want + stepSize) end)
    r.step:Refresh()
end

-- What this vendor offers --------------------------------------------------------------------

local function makeOffer(r)
    r.icon = S.IconBox(r, 24)
    r.icon:SetPoint("LEFT", 2, 0)
    r.add = S.FitButton(r, L.ADD, 26, 60)
    r.add:SetPoint("RIGHT", -2, 0)
    r.add:SetScript("OnClick", function(self)
        local v = self:GetParent().offer
        ns.Set(v.id, math.max(v.stack, ns.StepOf(v.id)))
    end)
    r.price = S.Text(r, 11, S.MUTED)
    r.price:SetPoint("RIGHT", r.add, "LEFT", -8, 0)
    r.text = S.Text(r, 12)
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
    r.text:SetPoint("RIGHT", r.price, "LEFT", -6, 0)
    r.text:SetWordWrap(false)
end

local function fillOffer(r, v)
    r.offer = v
    r.icon:SetIcon(ns.ItemIcon(v.id))
    r.text:SetText(ns.ItemName(v.id) .. (v.stack > 1 and (" x" .. v.stack) or ""))
    r.price:SetText(money(v.price))
end

function ns.Refresh()
    if not frame or not frame:IsShown() then return end
    local items = ns.List()
    list:SetData(items)
    empty:SetShown(#items == 0)
    card:SetTitle(L.SEC_KEEP, #items > 0 and tostring(#items) or "")
    setBtn:SetText(L.SET_LABEL:format(ns.char.set))
    delBtn:SetEnabled(#ns.SetNames() > 1)
    local o = ns.atVendor and ns.VendorOffers() or {}
    offers:SetData(o)
    noOffers:SetShown(#o == 0)
    noOffers:Set(ns.atVendor and L.NO_OFFERS or L.OPEN_VENDOR, "")
end

local function dropItem()
    local kind, id = GetCursorInfo()
    if kind == "item" and id then
        ClearCursor()
        if not ns.char.list[id] then ns.Set(id, ns.StepOf(id)) end
    end
end

local function showTab(i)
    for j, p in ipairs(pages) do p:SetShown(i == j) end
    ns.Refresh()
end

local function build()
    frame = S.Window("GulliRestockFrame", L.TITLE, S.NARROW_W, S.DOCK_H)
    local ft = S.Footer(frame)
    local preset = ft:Add(S.FitButton(ft, L.PRESET, 32, 120))
    preset:SetScript("OnClick", function()
        if ns.AddPreset() == 0 then print("|cff9ad0ffGulli Restock|r: " .. L.PRESET_NONE) end
    end)
    ft:SetStatus(L.FOOT_HINT)

    local body, width = frame.body, frame.inner[1]
    tabs = S.Tabs(body, { L.TAB_LIST, L.TAB_VENDOR, L.TAB_SETTINGS }, math.floor((width - 4) / 3), showTab, nil, { S.TAB.list, S.TAB.vendor, S.TAB.settings })
    for i = 1, 3 do
        local p = CreateFrame("Frame", nil, body)
        p:SetPoint("TOPLEFT", 0, -30 - S.GAP)
        p:SetPoint("BOTTOMRIGHT")
        pages[i] = p
    end

    -- The list: the set row on top, the add row and the kinds at the bottom.
    local p = pages[1]
    setBtn = S.Button(p, 1, 30)
    setBtn:SetPoint("TOPLEFT")
    setBtn:SetScript("OnClick", function() ns.NextSet() end)
    delBtn = S.FitButton(p, L.SET_DELETE, 30, 70)
    delBtn:SetPoint("TOPRIGHT")
    delBtn:SetScript("OnClick", function() ns.DeleteSet() end)
    local newBtn = S.FitButton(p, L.SET_NEW, 30, 70)
    newBtn:SetPoint("RIGHT", delBtn, "LEFT", -6, 0)
    newBtn:SetScript("OnClick", function() ns.NewSet() end)
    setBtn:SetPoint("RIGHT", newBtn, "LEFT", -6, 0)

    local bottom = CreateFrame("Frame", nil, p)
    bottom:SetPoint("BOTTOMLEFT")
    bottom:SetPoint("BOTTOMRIGHT")
    bottom:SetHeight(30 + 6 + 30)
    local bw = math.floor((width - 3 * 6) / 4)
    for k, kind in ipairs(ns.BEST_ORDER) do
        local b = S.Button(bottom, bw, 30)
        b:SetPoint("BOTTOMLEFT", (k - 1) * (bw + 6), 0)
        b:SetText("+ " .. L["KIND_" .. kind:upper()])
        b:SetScript("OnClick", function() ns.AddFromText(kind) end)
        b.kindKey = "best:" .. kind
        S.SetButtonIcon(b, ns.EntryIcon(b.kindKey))
        bottom[k] = b
    end
    -- The icon is the best item of the kind for the level now.
    bottom:SetScript("OnShow", function(self)
        for k in ipairs(ns.BEST_ORDER) do S.SetButtonIcon(self[k], ns.EntryIcon(self[k].kindKey)) end
    end)
    local addBtn = S.FitButton(bottom, L.ADD, 30, 70)
    addBtn:SetPoint("TOPRIGHT")
    addEdit = S.Edit(bottom, 1, 30)
    addEdit:SetPoint("TOPLEFT")
    addEdit:SetPoint("RIGHT", addBtn, "LEFT", -6, 0)
    addEdit:SetJustifyH("LEFT")
    S.Placeholder(addEdit, L.ADD_PLACEHOLDER)
    local function add()
        if ns.AddFromText(addEdit:GetText()) then addEdit:SetText("") end
        addEdit:ClearFocus()
    end
    addEdit:SetScript("OnEnterPressed", add)
    addBtn:SetScript("OnClick", add)
    -- Shift+click on an item while the box has the focus puts its link in.
    if ChatEdit_InsertLink then
        hooksecurefunc("ChatEdit_InsertLink", function(link)
            if addEdit:HasFocus() and link then addEdit:SetText(link) end
        end)
    end

    card = S.Card(p, L.SEC_KEEP)
    card:SetPoint("TOPLEFT", setBtn, "BOTTOMLEFT", 0, -8)
    card:SetPoint("RIGHT")
    card:SetPoint("BOTTOM", bottom, "TOP", 0, 8)
    local drop = S.DropZone(card.body, L.DROP, dropItem, 32)
    drop:SetPoint("BOTTOMLEFT")
    drop:SetPoint("BOTTOMRIGHT")
    list = S.List(card.body, 40, makeRow, fillRow)
    list:SetPoint("TOPLEFT")
    list:SetPoint("BOTTOMRIGHT", drop, "TOPRIGHT", -10, 8)
    empty = S.Empty(list)
    empty:Set(L.EMPTY)

    -- This vendor
    local vcard = S.Card(pages[2], L.TAB_VENDOR, nil, "Interface\\Icons\\INV_Misc_Bag_08")
    vcard:SetAllPoints()
    offers = S.List(vcard.body, 34, makeOffer, fillOffer)
    offers:SetPoint("TOPLEFT")
    offers:SetPoint("BOTTOMRIGHT", -10, 0)
    noOffers = S.Empty(vcard.body)

    -- Settings
    local st = S.Stack(pages[3])
    local reserve = S.Stepper(pages[3], function() return ns.db.reserve end, function(v) ns.db.reserve = v end,
        5, 0, 100000, function(v) return v .. "g" end)
    local scard, h = S.SettingsCard(pages[3], nil, {
        { L.AUTO, nil, function() return ns.db.auto end, function(v) ns.db.auto = v end, icon = ns.OPT_ICON.auto },
        { L.OPT_DEPOSIT, nil, function() return ns.db.deposit end, function(v) ns.db.deposit = v end,
          icon = ns.OPT_ICON.deposit },
        { L.OPT_FORECAST, nil, function() return ns.db.forecast end, function(v) ns.db.forecast = v; ns.Refresh() end,
          icon = ns.OPT_ICON.forecast },
        { L.OPT_RESERVE, nil, control = reserve, icon = ns.OPT_ICON.reserve },
    })
    st:Add(scard, h)
    local tip, th = S.Paragraph(pages[3], L.HELP, width)
    st:Add(tip, th)

    tabs:Select(1)
    frame:SetScript("OnShow", function() ns.Refresh() end)
end

function ns.Toggle()
    S.ToggleWindow(ns.Window())
end

function ns.ShowTab(i)
    ns.Window()
    tabs:Select(i)
end

-- The window, for the hub (/gulli) to show inside it.
function ns.Window()
    if not frame then build() end
    return frame
end

-- The preview at a vendor ---------------------------------------------------------------------

local CUT = { bags = "CUT_BAGS", money = "CUT_MONEY" }

local function refreshPlan()
    if not currentPlan then return end
    planList:SetData(currentPlan)
    local total = ns.PlanTotal(currentPlan)
    local enough = total <= (GetMoney and GetMoney() or 0)
    planFrame.footer:SetStatus(L.TOTAL:format(money(total)) .. (enough and "" or ("  " .. S.Hex(S.BAD) .. L.SHORT .. "|r")),
        S.TEXT)
    local any = false
    for _, e in ipairs(currentPlan) do if e.on and e.purchases > 0 then any = true end end
    planOk:SetEnabled(any)
end

local function makePlanRow(r)
    r.entry = false
    r.check = S.Check(r, 26)
    r.check:SetPoint("LEFT", -4, 0)
    r.check:SetScript("OnClick", function(self)
        local e = self:GetParent().entry
        e.on = not e.on
        refreshPlan()
    end)
    r.icon = S.IconBox(r, 22)
    r.icon:SetPoint("LEFT", r.check, "RIGHT", 2, 0)
    r.step = S.Stepper(r, function() return r.entry and r.entry.buy or 0 end, function() end, 1, 0, 9999, nil, 96)
    r.step:SetPoint("RIGHT", -2, 0)
    r.step.minus:SetScript("OnClick", function() ns.SetPurchases(r.entry, r.entry.purchases - 1); refreshPlan() end)
    r.step.plus:SetScript("OnClick", function() ns.SetPurchases(r.entry, r.entry.purchases + 1); refreshPlan() end)
    r.text = S.Text(r, 12)
    r.text:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 6, 1)
    r.text:SetPoint("RIGHT", r.step, "LEFT", -6, 0)
    r.text:SetWordWrap(false)
    r.cost = S.Text(r, 10, S.MUTED)
    r.cost:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 6, -2)
    r.cost:SetPoint("RIGHT", r.step, "LEFT", -6, 0)
    r.cost:SetWordWrap(false)
end

local function fillPlanRow(r, e)
    r.entry = e
    r.check:SetChecked(e.on)
    r.icon:SetIcon(ns.ItemIcon(e.id))
    r.text:SetText(ns.ItemName(e.id))
    r.cost:SetText(money(e.cost) .. (CUT[e.cut] and ("  " .. S.Hex(S.WARN) .. L[CUT[e.cut]] .. "|r") or ""))
    r.step:Refresh()
end

local function buildPlan()
    planFrame = S.Window("GulliRestockPlan", L.PLAN_TITLE, 380, 360)
    local ft = S.Footer(planFrame)
    planOk = ft:Add(S.Primary(S.FitButton(ft, L.BUY, 32, 90)))
    planOk:SetScript("OnClick", function()
        if currentPlan then ns.Buy(currentPlan) end
        currentPlan = nil
        planFrame:Hide()
    end)
    local cancel = ft:Add(S.FitButton(ft, L.CANCEL, 32, 80))
    cancel:SetScript("OnClick", function() currentPlan = nil; planFrame:Hide() end)
    planList = S.List(planFrame.body, 40, makePlanRow, fillPlanRow)
    planList:SetPoint("TOPLEFT", 0, 0)
    planList:SetPoint("BOTTOMRIGHT", -10, 0)
end

function ns.ShowPlan(plan)
    if not planFrame then buildPlan() end
    currentPlan = plan
    planFrame:ClearAllPoints()
    if MerchantFrame then
        planFrame:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", 8, 0)
    else
        planFrame:SetPoint("CENTER")
    end
    planFrame:Show()
    refreshPlan()
end

function ns.HidePlan()
    currentPlan = nil
    if planFrame then planFrame:Hide() end
end

function ns.PlanShown() return planFrame ~= nil and planFrame:IsShown() and currentPlan ~= nil end
function ns.CurrentPlan() return currentPlan end

-- The bank -----------------------------------------------------------------------------------

local function makeBankRow(r)
    r.icon = S.IconBox(r, 22)
    r.icon:SetPoint("LEFT", 2, 0)
    r.what = S.Text(r, 12, S.MUTED)
    r.what:SetPoint("RIGHT", -2, 0)
    r.text = S.Text(r, 12)
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.text:SetPoint("RIGHT", r.what, "LEFT", -6, 0)
    r.text:SetWordWrap(false)
end

local function fillBankRow(r, s)
    r.icon:SetIcon(ns.EntryIcon(s.key))
    r.text:SetText(ns.EntryName(s.key))
    local parts = {}
    if s.take > 0 then parts[#parts + 1] = S.Hex(S.GOOD) .. L.TAKE_N:format(s.take) .. "|r" end
    if s.put > 0 then parts[#parts + 1] = L.PUT_N:format(s.put) end
    r.what:SetText(table.concat(parts, "  "))
end

function ns.ShowBank(moves, sum)
    if not bankFrame then
        bankFrame = S.Window("GulliRestockBank", L.BANK_TITLE, 360, 320)
        local ft = S.Footer(bankFrame)
        local ok = ft:Add(S.Primary(S.FitButton(ft, L.MOVE, 32, 90)))
        ok:SetScript("OnClick", function()
            if bankMoves then ns.RunBank(bankMoves) end
            bankMoves = nil
            bankFrame:Hide()
        end)
        local cancel = ft:Add(S.FitButton(ft, L.CANCEL, 32, 80))
        cancel:SetScript("OnClick", function() bankMoves = nil; bankFrame:Hide() end)
        bankList = S.List(bankFrame.body, 30, makeBankRow, fillBankRow)
        bankList:SetPoint("TOPLEFT")
        bankList:SetPoint("BOTTOMRIGHT", -10, 0)
    end
    bankMoves = moves
    bankFrame:ClearAllPoints()
    if BankFrame then bankFrame:SetPoint("TOPLEFT", BankFrame, "TOPRIGHT", 8, 0) else bankFrame:SetPoint("CENTER") end
    bankList:SetData(sum)
    bankFrame.footer:SetStatus(L.BANK_HINT)
    bankFrame:Show()
end

function ns.HideBank()
    bankMoves = nil
    if bankFrame then bankFrame:Hide() end
end

function ns.BankShown() return bankFrame ~= nil and bankFrame:IsShown() and bankMoves ~= nil end
function ns.BankMoves() return bankMoves end

-- Quick buy ----------------------------------------------------------------------------------

function ns.ShowQuick(i)
    if not i then return end
    local id = GetMerchantItemID and GetMerchantItemID(i)
    if not id then return end
    if not quick then
        quick = S.Window("GulliRestockQuick", L.QUICK_TITLE, 300, 180)
        quick.stack = S.Button(quick.body, 1, 32)
        quick.stack:SetPoint("TOPLEFT", 0, -30)
        quick.stack:SetPoint("TOPRIGHT", 0, -30)
        quick.max = S.Primary(S.Button(quick.body, 1, 32))
        quick.max:SetPoint("TOPLEFT", quick.stack, "BOTTOMLEFT", 0, -8)
        quick.max:SetPoint("TOPRIGHT", quick.stack, "BOTTOMRIGHT", 0, -8)
        quick.name = S.Text(quick.body, 13)
        quick.name:SetPoint("TOPLEFT")
        quick.name:SetPoint("TOPRIGHT")
        quick.name:SetWordWrap(false)
    end
    local max, unit, step = ns.QuickMax(i)
    -- One "stack": a vendor stack for items sold in stacks, else the vendor's buy size.
    local one = (step or 1) > 1 and step or math.min(GetMerchantItemMaxStack and GetMerchantItemMaxStack(i) or 20, max)
    one = math.max(1, one)
    quick.name:SetText(ns.ItemName(id))
    quick.stack:SetText(L.QUICK_STACK:format(one, money(math.ceil(one / (step or 1)) * (unit or 0))))
    quick.stack:SetEnabled(max > 0)
    quick.stack:SetScript("OnClick", function() ns.QuickBuy(i, one); quick:Hide() end)
    quick.max:SetText(L.QUICK_MAX:format(max, money(math.ceil(max / (step or 1)) * (unit or 0))))
    quick.max:SetEnabled(max > 0)
    quick.max:SetScript("OnClick", function() ns.QuickBuy(i, max); quick:Hide() end)
    quick:ClearAllPoints()
    if MerchantFrame then quick:SetPoint("BOTTOMLEFT", MerchantFrame, "BOTTOMRIGHT", 8, 0) else quick:SetPoint("CENTER") end
    quick:Show()
end

function ns.HideQuick() if quick then quick:Hide() end end
