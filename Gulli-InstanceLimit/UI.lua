-- The window (entries left, when the next is free, the list, the limits, Reset) and a small
-- counter on screen that opens it.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, big, next, list, empty, entries, resetBtn, badge

local function ago(t)
    return L.AGO:format(ns.Clock(time() - t))
end

local function makeRow(r)
    r.name = S.Text(r, 12)
    r.name:SetPoint("LEFT", 2, 0)
    r.name:SetPoint("RIGHT", -150, 0)
    r.name:SetWordWrap(false)
    r.when = S.Text(r, 11, S.MUTED)
    r.when:SetPoint("RIGHT", -2, 0)
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
    local function tone(left) return left == 0 and S.BAD or (left == 1 and S.WARN or S.GOOD) end
    big.tiles[1]:Set(s.leftHour .. " / " .. ns.db.limit, tone(s.leftHour))
    big.tiles[2]:Set(s.leftDay .. " / " .. ns.db.dayLimit, tone(s.leftDay))
    next:SetText(s.wait > 0 and L.NEXT_FREE:format(ns.Clock(s.wait)) or L.ALL_FREE)
    local recent = {}
    for _, e in ipairs(ns.db.entries) do
        if time() - e.t < ns.HOUR then recent[#recent + 1] = e end
    end
    table.sort(recent, function(a, b) return a.t > b.t end)
    list:SetData(recent)
    empty:SetShown(#recent == 0)
    entries:SetTitle(L.ENTRIES, #recent > 0 and tostring(#recent) or "")
    resetBtn:SetEnabled(ns.CanReset())
end

local function numberEdit(parent, get, set)
    local e = S.Edit(parent, 52, 28)
    e:SetNumeric(true)
    e:SetMaxLetters(3)
    e:SetText(tostring(get()))
    e:SetScript("OnShow", function(self) self:SetText(tostring(get())) end)
    local function apply(self)
        local n = tonumber(self:GetText())
        if n and n > 0 then set(n) end
        self:SetText(tostring(get()))
        self:ClearFocus()
        ns.Refresh()
    end
    e:SetScript("OnEnterPressed", apply)
    e:SetScript("OnEditFocusLost", function(self) S.SetBorder(self, S.EDGE); apply(self) end)
    return e
end

local function build()
    frame = S.Window("GulliInstanceLimitFrame", L.TITLE, S.NARROW_W, 600)
    local ft = S.Footer(frame)
    resetBtn = ft:Add(S.FitButton(ft, L.RESET, 32, 110))
    resetBtn:SetScript("OnClick", function() ns.Reset() end)
    ft:SetStatus(L.RESET_TIP)

    local body, width = frame.body, frame.inner[1]
    local st = S.Stack(body)
    big = S.StatRow(body, { L.STAT_HOUR, L.STAT_DAY }, 62,
        { "Interface\\Icons\\INV_Misc_PocketWatch_01", "Interface\\Icons\\Spell_Nature_TimeStop" })
    st:Add(big, 62, 8)
    big:Layout(width)
    next = S.Text(body, 12, S.MUTED)
    st:Add(next, 16)

    entries = S.Card(body, L.ENTRIES)
    st:Add(entries, 170)
    list = S.List(entries.body, 28, makeRow, fillRow)
    list:SetPoint("TOPLEFT")
    list:SetPoint("BOTTOMRIGHT", -10, 0)
    empty = S.Empty(entries.body)
    empty:Set(L.NONE)

    local limits, h = S.SettingsCard(body, L.SEC_LIMITS, {
        { L.ROW_LIMIT, nil, control = numberEdit(body, function() return ns.db.limit end, function(n) ns.db.limit = n end),
          icon = "Interface\\Icons\\INV_Misc_PocketWatch_02" },
        { L.ROW_DAY, nil, control = numberEdit(body, function() return ns.db.dayLimit end, function(n) ns.db.dayLimit = n end),
          icon = "Interface\\Icons\\Spell_Arcane_PortalIronForge" },
        { L.BADGE, nil, function() return ns.db.badge end, function(v) ns.db.badge = v; ns.Refresh() end,
          icon = "Interface\\Icons\\INV_Misc_Spyglass_03" },
    })
    st:Add(limits, h)
    S.FitWindow(frame, st:Height())
    frame:SetScript("OnShow", function() ns.Refresh() end)
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
    S.ToggleWindow(ns.Window())
end

-- The window, for the hub (/gulli) to show inside it.
function ns.Window()
    if not frame then build() end
    return frame
end

function ns.SetupBadge()
    if not badge then buildBadge() end
    ns.Refresh()
end
