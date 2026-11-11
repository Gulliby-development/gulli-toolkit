-- The window (entries left, when the next is free, the list, the limits, Reset) and a small
-- counter on screen that opens it.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, big, next, list, empty, limitEdit, dayEdit, badgeCheck, resetBtn, badge

local function ago(t)
    return L.AGO:format(ns.Clock(time() - t))
end

local function makeRow(r)
    r.name = S.Text(r, 12)
    r.name:SetPoint("LEFT", 8, 0)
    r.name:SetPoint("RIGHT", -150, 0)
    r.name:SetWordWrap(false)
    r.when = S.Text(r, 11, S.MUTED)
    r.when:SetPoint("RIGHT", -8, 0)
    r.when:SetJustifyH("RIGHT")
end

local function fillRow(r, e)
    r.name:SetText((e.name or "?") .. "  " .. S.Hex(S.MUTED) .. (e.char or "") .. "|r")
    r.when:SetText(ago(e.t))
end

local function updateBadge(s)
    if not badge then return end
    badge:SetShown(ns.db.badge and true or false)
    local color = s.left == 0 and "|cffff5050" or (s.left == 1 and "|cffffc000" or S.Hex(S.Accent()))
    badge.text:SetText(color .. s.leftHour .. "/" .. ns.db.limit .. "|r" ..
        (s.wait > 0 and ("  " .. ns.Clock(s.wait)) or ""))
end

function ns.Refresh()
    local s = ns.Status()
    updateBadge(s)
    if not frame or not frame:IsShown() then return end
    big:SetText(L.LEFT_HOUR:format(s.leftHour, ns.db.limit))
    next:SetText((s.wait > 0 and L.NEXT_FREE:format(ns.Clock(s.wait)) or L.ALL_FREE) .. "   " ..
        S.Hex(S.MUTED) .. L.LEFT_DAY:format(s.leftDay, ns.db.dayLimit) .. "|r")
    local recent = {}
    for _, e in ipairs(ns.db.entries) do
        if time() - e.t < ns.HOUR then recent[#recent + 1] = e end
    end
    table.sort(recent, function(a, b) return a.t > b.t end)
    list:SetData(recent)
    empty:SetShown(#recent == 0)
    resetBtn:SetEnabled(ns.CanReset())
end

local function numberEdit(parent, get, set)
    local e = S.Edit(parent, 48)
    e:SetNumeric(true)
    e:SetMaxLetters(3)
    e:SetScript("OnShow", function(self) self:SetText(tostring(get())) end)
    local function apply(self)
        local n = tonumber(self:GetText())
        if n and n > 0 then set(n) end
        self:SetText(tostring(get()))
        self:ClearFocus()
        ns.Refresh()
    end
    e:SetScript("OnEnterPressed", apply)
    e:SetScript("OnEditFocusLost", function(self) S.SetBorder(self, S.BORDER); apply(self) end)
    return e
end

local function build()
    frame = S.Window("GulliInstanceLimitFrame", L.TITLE, 440, 420)
    local body = frame.body
    big = S.Text(body, 20, S.Accent())
    big:SetPoint("TOPLEFT", 0, -2)
    next = S.Text(body, 12)
    next:SetPoint("TOPLEFT", big, "BOTTOMLEFT", 0, -6)
    next:SetPoint("RIGHT", 0, 0)

    local head = S.Text(body, 11, S.MUTED)
    head:SetPoint("TOPLEFT", 0, -60)
    head:SetText(L.ENTRIES)
    list = S.List(body, 26, makeRow, fillRow)
    list:SetPoint("TOPLEFT", 0, -78)
    list:SetPoint("BOTTOMRIGHT", -12, 110)
    empty = S.Note(body, 12)
    empty:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -6)
    empty:SetText(L.NONE)

    limitEdit = numberEdit(body, function() return ns.db.limit end, function(n) ns.db.limit = n end)
    limitEdit:SetPoint("BOTTOMLEFT", 0, 74)
    local lt = S.Text(body, 12)
    lt:SetPoint("LEFT", limitEdit, "RIGHT", 8, 0)
    lt:SetText(L.LIMIT)
    dayEdit = numberEdit(body, function() return ns.db.dayLimit end, function(n) ns.db.dayLimit = n end)
    dayEdit:SetPoint("BOTTOMLEFT", 210, 74)
    local dt = S.Text(body, 12)
    dt:SetPoint("LEFT", dayEdit, "RIGHT", 8, 0)
    dt:SetText(L.DAY_LIMIT)

    badgeCheck = S.Check(body, 26)
    badgeCheck:SetPoint("BOTTOMLEFT", 0, 40)
    badgeCheck:SetScript("OnClick", function(self)
        ns.db.badge = not ns.db.badge
        self:SetChecked(ns.db.badge)
        ns.Refresh()
    end)
    local bt = S.Text(body, 12)
    bt:SetPoint("LEFT", badgeCheck, "RIGHT", 4, 0)
    bt:SetText(L.BADGE)

    resetBtn = S.Button(body, 170, 30)
    resetBtn:SetPoint("BOTTOMLEFT", 0, 0)
    resetBtn:SetText(L.RESET)
    resetBtn:SetScript("OnClick", function() ns.Reset() end)
    local tip = S.Note(body, 11)
    tip:SetPoint("LEFT", resetBtn, "RIGHT", 8, 0)
    tip:SetPoint("RIGHT", 0, 0)
    tip:SetText(L.RESET_TIP)

    frame:SetScript("OnShow", function()
        badgeCheck:SetChecked(ns.db.badge)
        ns.Refresh()
    end)
end

-- The counter: "3/5" with the wait time while no entry is free. Drag to move, click to open.
local function buildBadge()
    badge = CreateFrame("Button", "GulliInstanceLimitBadge", UIParent)
    badge:SetSize(96, 26)
    badge:SetPoint("TOP", 0, -120)
    badge:SetMovable(true)
    badge:SetClampedToScreen(true)
    badge:RegisterForDrag("LeftButton")
    badge:SetScript("OnDragStart", badge.StartMoving)
    badge:SetScript("OnDragStop", badge.StopMovingOrSizing)
    S.Box(badge)
    badge.text = S.Text(badge, 13)
    badge.text:SetPoint("CENTER")
    badge.text:SetJustifyH("CENTER")
    badge:SetScript("OnClick", function() ns.Toggle() end)
    local elapsed = 0
    badge:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + (dt or 0)
        if elapsed >= 1 then elapsed = 0; ns.Refresh() end
    end)
end

function ns.Toggle()
    if not frame then build() end
    frame:SetShown(not frame:IsShown())
end

function ns.SetupBadge()
    if not badge then buildBadge() end
    ns.Refresh()
end
