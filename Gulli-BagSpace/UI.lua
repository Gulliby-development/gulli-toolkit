-- The window: how many slots to free, the plan with a tick per item, and OK.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, space, want, list, empty, summary, ok, note
local plan

local QUALITY = { [0] = "|cff9d9d9d", [1] = "|cffffffff" }

local function makeRow(r)
    r.check = S.Check(r, 26)
    r.check:SetPoint("LEFT", 2, 0)
    r.check:SetScript("OnClick", function(self)
        local it = self:GetParent().item
        it.checked = not it.checked
        self:SetChecked(it.checked)
        ns.Refresh(false)
    end)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(22, 22)
    r.icon:SetPoint("LEFT", r.check, "RIGHT", 4, 0)
    r.value = S.Text(r, 11, S.MUTED)
    r.value:SetPoint("RIGHT", -8, 0)
    r.value:SetJustifyH("RIGHT")
    r.name = S.Text(r, 12)
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.name:SetPoint("RIGHT", r.value, "LEFT", -6, 0)
    r.name:SetWordWrap(false)
end

local function fillRow(r, it)
    r.item = it
    r.check:SetChecked(it.checked)
    r.icon:SetTexture(it.icon)
    r.name:SetText((QUALITY[it.quality] or "") .. it.name .. "|r" .. (it.count > 1 and (" x" .. it.count) or "") ..
        (it.tier == 3 and ("  " .. S.Hex(S.MUTED) .. L.MAYBE .. "|r") or ""))
    r.value:SetText(it.value > 0 and ns.Money(it.value) or "")
end

-- rebuild: true makes a new plan from the bags, false keeps the ticks.
function ns.Refresh(rebuild)
    if not frame or not frame:IsShown() then return end
    if rebuild ~= false or not plan then plan = ns.Plan(ns.db.want) end
    space:SetText(L.SPACE:format(plan.free, plan.total))
    list:SetData(plan.items)
    local slots, value = ns.Summary(plan)
    empty:SetShown(#plan.items == 0)
    empty:SetText(plan.merged > 0 and L.ONLY_MERGE:format(plan.merged) or L.NOTHING)
    summary:SetText(L.SUMMARY:format(slots, plan.merged) .. (value > 0 and ("  " .. ns.Money(value)) or ""))
    ok:SetText(ns.atMerchant and L.SELL or L.DELETE)
    ok:SetEnabled(slots > 0)
    note:SetText(ns.atMerchant and L.NOTE_SELL or L.NOTE_DELETE)
end

local function build()
    frame = S.Window("GulliBagSpaceFrame", L.TITLE, 520, 480)
    local body = frame.body
    space = S.Text(body, 14, S.Accent())
    space:SetPoint("TOPLEFT", 0, -4)

    local label = S.Text(body, 12)
    label:SetPoint("TOPLEFT", 0, -32)
    label:SetText(L.WANT)
    want = S.Edit(body, 48)
    want:SetPoint("LEFT", label, "RIGHT", 8, 0)
    want:SetNumeric(true)
    want:SetMaxLetters(3)
    local planBtn = S.Button(body, 110, 30)
    planBtn:SetPoint("LEFT", want, "RIGHT", 8, 0)
    planBtn:SetText(L.PLAN)
    local function apply()
        local n = tonumber(want:GetText())
        if n and n > 0 then ns.db.want = n end
        want:SetText(tostring(ns.db.want))
        want:ClearFocus()
        ns.Refresh(true)
    end
    want:SetScript("OnEnterPressed", apply)
    planBtn:SetScript("OnClick", apply)

    list = S.List(body, 30, makeRow, fillRow)
    list:SetPoint("TOPLEFT", 0, -70)
    list:SetPoint("BOTTOMRIGHT", -12, 80)
    empty = S.Note(body, 12)
    empty:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -6)
    empty:SetPoint("RIGHT", list, "RIGHT", -4, 0)

    summary = S.Text(body, 13)
    summary:SetPoint("BOTTOMLEFT", 0, 46)
    summary:SetPoint("RIGHT", 0, 0)
    ok = S.Button(body, 140, 32)
    ok:SetPoint("BOTTOMRIGHT", 0, 0)
    ok:SetScript("OnClick", function()
        ns.Run(plan)
        C_Timer.After(1, function() ns.Refresh(true) end)
    end)
    note = S.Note(body, 11)
    note:SetPoint("BOTTOMLEFT", 0, 4)
    note:SetPoint("RIGHT", ok, "LEFT", -8, 0)
    note:SetMaxLines(2)

    frame:SetScript("OnShow", function()
        want:SetText(tostring(ns.db.want))
        ns.Refresh(true)
    end)
end

function ns.Toggle()
    if not frame then build() end
    frame:SetShown(not frame:IsShown())
    if frame:IsShown() then ns.Refresh(true) end
end
