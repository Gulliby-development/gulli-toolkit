-- The icons on screen (drag the strip to move it, tap it for the settings), and the settings.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local strip, frame
local icons = {}
local SIZE = 40

local function buildStrip()
    strip = CreateFrame("Button", "GulliRemindersStrip", UIParent)
    strip:SetSize(SIZE, SIZE)
    strip:SetPoint("TOP", 0, -190)
    strip:SetMovable(true)
    strip:SetClampedToScreen(true)
    strip:RegisterForDrag("LeftButton")
    strip:SetScript("OnDragStart", strip.StartMoving)
    strip:SetScript("OnDragStop", strip.StopMovingOrSizing)
    strip:SetScript("OnClick", function() ns.Toggle() end)
    strip.text = S.Text(strip, 12)
    strip.text:SetPoint("TOP", strip, "BOTTOM", 0, -4)
    strip.text:SetJustifyH("CENTER")
end

local function icon(i)
    if icons[i] then return icons[i] end
    local b = CreateFrame("Frame", nil, strip)
    b:SetSize(SIZE, SIZE)
    S.Box(b)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetPoint("TOPLEFT", 1, -1)
    b.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icons[i] = b
    return b
end

function ns.Refresh()
    local missing = ns.Missing()
    if #missing == 0 then
        if strip then strip:Hide() end
        return missing
    end
    if not strip then buildStrip() end
    local width = #missing * (SIZE + 4) - 4
    strip:SetWidth(width)
    local texts = {}
    for i, m in ipairs(missing) do
        local b = icon(i)
        b:ClearAllPoints()
        b:SetPoint("LEFT", strip, "LEFT", (i - 1) * (SIZE + 4), 0)
        b.tex:SetTexture(m.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        b:Show()
        texts[#texts + 1] = m.text
    end
    for i = #missing + 1, #icons do icons[i]:Hide() end
    strip.text:SetText(table.concat(texts, "\n"))
    strip:Show()
    return missing
end

local function numberEdit(parent, key)
    local e = S.Edit(parent, 52, 28)
    e:SetNumeric(true)
    e:SetMaxLetters(4)
    e:SetText(tostring(ns.db[key]))
    e:SetScript("OnShow", function(self) self:SetText(tostring(ns.db[key])) end)
    local function apply(self)
        local n = tonumber(self:GetText())
        if n then ns.db[key] = n end
        self:SetText(tostring(ns.db[key]))
        self:ClearFocus()
        ns.Refresh()
    end
    e:SetScript("OnEnterPressed", apply)
    e:SetScript("OnEditFocusLost", function(self) S.SetBorder(self, S.EDGE); apply(self) end)
    return e
end

local function build()
    frame = S.Window("GulliRemindersFrame", L.TITLE, S.NARROW_W, 360)
    local body = frame.body
    local function switch(key, label, extra)
        return { label, nil, function() return ns.db[key] end, function(v) ns.db[key] = v; ns.Refresh() end,
                 extra = extra, icon = ns.OPT_ICON[key] }
    end
    local st = S.Stack(body)
    local card, h = S.SettingsCard(body, nil, {
        switch("buffs", L.OPT_BUFFS),
        switch("weapon", L.OPT_WEAPON),
        switch("ammo", L.OPT_AMMO, numberEdit(body, "ammoMin")),
        switch("shards", L.OPT_SHARDS, numberEdit(body, "shardsMin")),
        switch("notResting", L.OPT_RESTING),
    })
    st:Add(card, h)
    local note, nh = S.Paragraph(body, L.NOTE, frame.inner[1])
    st:Add(note, nh)
    S.FitWindow(frame, st:Height())
end

function ns.Toggle()
    S.ToggleWindow(ns.Window())
end

-- The window, for the hub (/gulli) to show inside it.
function ns.Window()
    if not frame then build() end
    return frame
end
