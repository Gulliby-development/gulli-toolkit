-- The keep list (icon, name, have / keep, an edit box for the amount, a remove button), and
-- the small window at a vendor with what would be bought, the cost and OK.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, list, empty, autoCheck
local planFrame, planList, planTotal, planOk
local currentPlan

local function money(copper)
    if GetCoinTextureString then return GetCoinTextureString(copper or 0) end
    return tostring(copper or 0)
end

local function makeRow(r)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(24, 24)
    r.icon:SetPoint("LEFT", 6, 0)
    r.remove = S.Button(r, 28, 28)
    r.remove:SetPoint("RIGHT", -2, 0)
    r.remove:SetText("x")
    r.remove:SetScript("OnClick", function(self) ns.Set(self:GetParent().entry.id, 0) end)
    r.edit = S.Edit(r, 52)
    r.edit:SetPoint("RIGHT", r.remove, "LEFT", -6, 0)
    r.edit:SetNumeric(true)
    r.edit:SetMaxLetters(4)
    local function apply(self)
        local e = self:GetParent().entry
        local n = tonumber(self:GetText())
        if e and n then ns.Set(e.id, n) end
        self:ClearFocus()
    end
    r.edit:SetScript("OnEnterPressed", apply)
    r.edit:SetScript("OnEditFocusLost", function(self) S.SetBorder(self, S.BORDER); apply(self) end)
    r.have = S.Text(r, 12, S.MUTED)
    r.have:SetPoint("RIGHT", r.edit, "LEFT", -8, 0)
    r.text = S.Text(r, 13)
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
    r.text:SetPoint("RIGHT", r.have, "LEFT", -8, 0)
    r.text:SetWordWrap(false)
end

local function fillRow(r, e)
    r.entry = e
    r.icon:SetTexture(ns.ItemIcon(e.id))
    r.text:SetText(ns.ItemName(e.id))
    local low = e.have < e.want
    r.have:SetText((low and S.Hex(S.Accent()) or "") .. L.HAVE:format(e.have) .. (low and "|r" or ""))
    r.edit:SetText(tostring(e.want))
    S.Fill(r, S.ROW)
end

function ns.Refresh()
    if not frame or not frame:IsShown() then return end
    local items = ns.List()
    list:SetData(items)
    empty:SetShown(#items == 0)
    autoCheck:SetChecked(ns.db.auto)
end

local function dropItem()
    local kind, id = GetCursorInfo()
    if kind == "item" and id then
        ClearCursor()
        if not ns.char.list[id] then ns.Set(id, 20) end
    end
end

local function build()
    frame = S.Window("GulliRestockFrame", L.TITLE, 520, 440)
    local body = frame.body
    list = S.List(body, 34, makeRow, fillRow)
    list:SetPoint("TOPLEFT", 0, 0)
    list:SetPoint("BOTTOMRIGHT", -12, 112)
    empty = S.Note(body, 12)
    empty:SetPoint("TOPLEFT", 4, -6)
    empty:SetPoint("RIGHT", -16, 0)
    empty:SetText(L.EMPTY)

    local drop = S.Button(body, 1, 36)
    drop:SetPoint("BOTTOMLEFT", 0, 70)
    drop:SetPoint("BOTTOMRIGHT", 0, 70)
    drop:SetText(L.DROP)
    drop:SetScript("OnClick", dropItem)
    drop:SetScript("OnReceiveDrag", dropItem)

    local preset = S.Button(body, 200, 30)
    preset:SetPoint("BOTTOMLEFT", 0, 32)
    preset:SetText(L.PRESET)
    preset:SetScript("OnClick", function()
        if ns.AddPreset() == 0 then print("|cff9ad0ffGulli Restock|r: " .. L.PRESET_NONE) end
    end)

    autoCheck = S.Check(body, 26)
    autoCheck:SetPoint("BOTTOMLEFT", 0, 0)
    autoCheck:SetScript("OnClick", function(self)
        ns.db.auto = not ns.db.auto
        self:SetChecked(ns.db.auto)
    end)
    local at = S.Text(body, 12)
    at:SetPoint("LEFT", autoCheck, "RIGHT", 6, 0)
    at:SetPoint("RIGHT", 0, 0)
    at:SetText(L.AUTO)

    frame:SetScript("OnShow", function() ns.Refresh() end)
end

function ns.Toggle()
    if not frame then build() end
    frame:SetShown(not frame:IsShown())
end

local function makePlanRow(r)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(20, 20)
    r.icon:SetPoint("LEFT", 6, 0)
    r.cost = S.Text(r, 12)
    r.cost:SetPoint("RIGHT", -6, 0)
    r.text = S.Text(r, 12)
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.text:SetPoint("RIGHT", r.cost, "LEFT", -6, 0)
    r.text:SetWordWrap(false)
end

local function fillPlanRow(r, e)
    r.icon:SetTexture(ns.ItemIcon(e.id))
    r.text:SetText(e.buy .. " x " .. ns.ItemName(e.id))
    r.cost:SetText(money(e.cost))
    S.Fill(r, S.ROW)
end

local function buildPlan()
    planFrame = S.Window("GulliRestockPlan", L.PLAN_TITLE, 340, 300)
    local body = planFrame.body
    planList = S.List(body, 28, makePlanRow, fillPlanRow)
    planList:SetPoint("TOPLEFT", 0, 0)
    planList:SetPoint("BOTTOMRIGHT", -12, 70)
    planTotal = S.Text(body, 13)
    planTotal:SetPoint("BOTTOMLEFT", 0, 44)
    planTotal:SetPoint("RIGHT", 0, 0)
    planOk = S.Button(body, 150, 32)
    planOk:SetPoint("BOTTOMLEFT", 0, 0)
    planOk:SetText(L.BUY)
    planOk:SetScript("OnClick", function()
        if currentPlan then ns.Buy(currentPlan) end
        currentPlan = nil
        planFrame:Hide()
    end)
    local cancel = S.Button(body, 150, 32)
    cancel:SetPoint("BOTTOMRIGHT", 0, 0)
    cancel:SetText(L.CANCEL)
    cancel:SetScript("OnClick", function() currentPlan = nil; planFrame:Hide() end)
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
    planTotal:SetText(L.TOTAL:format(money(total)) .. (enough and "" or ("  " .. S.Hex(S.Accent()) .. L.SHORT .. "|r")))
    planFrame:Show()
end

function ns.HidePlan()
    currentPlan = nil
    if planFrame then planFrame:Hide() end
end

function ns.PlanShown() return planFrame ~= nil and planFrame:IsShown() and currentPlan ~= nil end
