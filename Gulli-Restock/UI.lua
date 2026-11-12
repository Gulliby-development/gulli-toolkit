-- The keep list (icon, name, have / keep, an edit box for the amount, a remove button), and
-- the small window at a vendor with what would be bought, the cost and OK.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, list, empty, card, autoRow
local planFrame, planList, planTotal, planOk
local currentPlan

local function money(copper)
    if GetCoinTextureString then return GetCoinTextureString(copper or 0) end
    return tostring(copper or 0)
end

local function makeRow(r)
    r.icon = S.IconBox(r, 26)
    r.icon:SetPoint("LEFT", 2, 0)
    r.remove = S.Close(r, function(self) ns.Set(self:GetParent().entry.id, 0) end)
    r.remove:SetPoint("RIGHT", 0, 0)
    r.edit = S.Edit(r, 52, 28)
    r.edit:SetPoint("RIGHT", r.remove, "LEFT", -8, 0)
    r.edit:SetNumeric(true)
    r.edit:SetMaxLetters(4)
    local function apply(self)
        local e = self:GetParent().entry
        local n = tonumber(self:GetText())
        if e and n then ns.Set(e.id, n) end
        self:ClearFocus()
    end
    r.edit:SetScript("OnEnterPressed", apply)
    r.edit:SetScript("OnEditFocusLost", function(self) S.SetBorder(self, S.EDGE); apply(self) end)
    r.have = S.Text(r, 12, S.MUTED)
    r.have:SetPoint("RIGHT", r.edit, "LEFT", -8, 0)
    r.text = S.Text(r, 12)
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 10, 0)
    r.text:SetPoint("RIGHT", r.have, "LEFT", -8, 0)
    r.text:SetWordWrap(false)
end

local function fillRow(r, e)
    r.entry = e
    r.icon:SetIcon(ns.ItemIcon(e.id))
    r.text:SetText(ns.ItemName(e.id))
    local low = e.have < e.want
    r.have:SetText((low and S.Hex(S.WARN) or "") .. L.HAVE:format(e.have) .. (low and "|r" or ""))
    r.edit:SetText(tostring(e.want))
end

function ns.Refresh()
    if not frame or not frame:IsShown() then return end
    local items = ns.List()
    list:SetData(items)
    empty:SetShown(#items == 0)
    card:SetTitle(L.SEC_KEEP, #items > 0 and tostring(#items) or "")
    autoRow:SetChecked(ns.db.auto)
end

local function dropItem()
    local kind, id = GetCursorInfo()
    if kind == "item" and id then
        ClearCursor()
        if not ns.char.list[id] then ns.Set(id, 20) end
    end
end

local function build()
    frame = S.Window("GulliRestockFrame", L.TITLE, 540, 520)
    local ft = S.Footer(frame)
    local preset = ft:Add(S.FitButton(ft, L.PRESET, 32, 120))
    preset:SetScript("OnClick", function()
        if ns.AddPreset() == 0 then print("|cff9ad0ffGulli Restock|r: " .. L.PRESET_NONE) end
    end)

    local body = frame.body
    local auto, ah = S.SettingsCard(body, nil, {
        { L.AUTO, nil, function() return ns.db.auto end, function(v) ns.db.auto = v end,
          icon = "Interface\\Icons\\INV_Misc_Bag_08" } })
    auto:SetPoint("BOTTOMLEFT")
    auto:SetPoint("BOTTOMRIGHT")
    auto:SetHeight(ah)
    autoRow = auto.rows[1]

    card = S.Card(body, L.SEC_KEEP)
    card:SetPoint("TOPLEFT")
    card:SetPoint("BOTTOMRIGHT", auto, "TOPRIGHT", 0, S.GAP)
    local drop = S.DropZone(card.body, L.DROP, dropItem, 36)
    drop:SetPoint("BOTTOMLEFT")
    drop:SetPoint("BOTTOMRIGHT")
    list = S.List(card.body, 36, makeRow, fillRow)
    list:SetPoint("TOPLEFT")
    list:SetPoint("BOTTOMRIGHT", drop, "TOPRIGHT", -10, 8)
    empty = S.Empty(list)
    empty:Set(L.EMPTY)

    frame:SetScript("OnShow", function() ns.Refresh() end)
end

function ns.Toggle()
    if not frame then build() end
    frame:SetShown(not frame:IsShown())
end

local function makePlanRow(r)
    r.icon = S.IconBox(r, 22)
    r.icon:SetPoint("LEFT", 2, 0)
    r.cost = S.Text(r, 12)
    r.cost:SetPoint("RIGHT", -2, 0)
    r.text = S.Text(r, 12)
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.text:SetPoint("RIGHT", r.cost, "LEFT", -6, 0)
    r.text:SetWordWrap(false)
end

local function fillPlanRow(r, e)
    r.icon:SetIcon(ns.ItemIcon(e.id))
    r.text:SetText(e.buy .. " x " .. ns.ItemName(e.id))
    r.cost:SetText(money(e.cost))
end

local function buildPlan()
    planFrame = S.Window("GulliRestockPlan", L.PLAN_TITLE, 360, 340)
    local ft = S.Footer(planFrame)
    planOk = ft:Add(S.Primary(S.FitButton(ft, L.BUY, 32, 90)))
    planOk:SetScript("OnClick", function()
        if currentPlan then ns.Buy(currentPlan) end
        currentPlan = nil
        planFrame:Hide()
    end)
    local cancel = ft:Add(S.FitButton(ft, L.CANCEL, 32, 80))
    cancel:SetScript("OnClick", function() currentPlan = nil; planFrame:Hide() end)
    planTotal = ft.status
    planList = S.List(planFrame.body, 30, makePlanRow, fillPlanRow)
    planList:SetPoint("TOPLEFT", 0, 0)
    planList:SetPoint("BOTTOMRIGHT", -10, 0)
end

function ns.ShowPlan(plan, total)
    if not planFrame then buildPlan() end
    currentPlan = plan
    planFrame:ClearAllPoints()
    if MerchantFrame then
        planFrame:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", 8, 0)
    else
        planFrame:SetPoint("CENTER")
    end
    planList:SetData(plan)
    local enough = total <= (GetMoney and GetMoney() or 0)
    planTotal:SetText(L.TOTAL:format(money(total)) .. (enough and "" or ("  " .. S.Hex(S.BAD) .. L.SHORT .. "|r")))
    planTotal:SetTextColor(S.TEXT[1], S.TEXT[2], S.TEXT[3], 1)
    planFrame:Show()
end

function ns.HidePlan()
    currentPlan = nil
    if planFrame then planFrame:Hide() end
end

function ns.PlanShown() return planFrame ~= nil and planFrame:IsShown() and currentPlan ~= nil end
