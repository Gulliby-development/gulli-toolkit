-- A flat look in the spirit of ElvUI: dark panels, 1 pixel borders, the class colour as
-- the accent. Built from plain textures, so it needs no template and no library.

local _, ns = ...

local S = {}
ns.Skin = S

local WHITE = "Interface\\Buttons\\WHITE8X8"
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

S.BG = { 0.06, 0.06, 0.07, 0.94 }
S.PANEL = { 0.10, 0.10, 0.11, 1 }
S.ROW = { 1, 1, 1, 0.03 }
S.BORDER = { 0, 0, 0, 1 }
S.MUTED = { 0.55, 0.55, 0.58, 1 }
S.TEXT = { 0.92, 0.92, 0.92, 1 }

-- The player's class colour, like ElvUI's default accent.
function S.Accent()
    local _, class = UnitClass and UnitClass("player")
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return { c.r, c.g, c.b, 1 } end
    return { 0.60, 0.82, 1, 1 }
end

function S.Hex(c)
    return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255)
end

local function tex(f, layer, sub, color)
    local t = f:CreateTexture(nil, layer, nil, sub)
    t:SetTexture(WHITE)
    t:SetVertexColor(color[1], color[2], color[3], color[4])
    return t
end

-- A filled rectangle with a 1 pixel border around it.
function S.Box(f, bg, border)
    f.bg = tex(f, "BACKGROUND", -8, bg or S.BG)
    f.bg:SetAllPoints()
    local b = border or S.BORDER
    f.edges = {}
    for i, p in ipairs({ { "TOPLEFT", "TOPRIGHT", 0, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 0, 1 },
                         { "TOPLEFT", "BOTTOMLEFT", 1, 0 }, { "TOPRIGHT", "BOTTOMRIGHT", 1, 0 } }) do
        local e = tex(f, "BORDER", 7, b)
        e:SetPoint(p[1])
        e:SetPoint(p[2])
        if p[3] == 1 then e:SetWidth(1) else e:SetHeight(1) end
        f.edges[i] = e
    end
    return f
end

function S.SetBorder(f, c)
    for _, e in ipairs(f.edges) do e:SetVertexColor(c[1], c[2], c[3], c[4]) end
end

function S.Fill(f, c)
    f.bg:SetVertexColor(c[1], c[2], c[3], c[4])
end

function S.Text(parent, size, color, flags)
    local t = parent:CreateFontString(nil, "OVERLAY")
    t:SetFont(FONT, size or 12, flags or "")
    t:SetShadowOffset(1, -1)
    t:SetShadowColor(0, 0, 0, 0.8)
    local c = color or S.TEXT
    t:SetTextColor(c[1], c[2], c[3], c[4])
    t:SetJustifyH("LEFT")
    return t
end

-- A flat button: the border lights up in the accent colour under the cursor.
function S.Button(parent, width, height)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 110, height or 30)
    S.Box(b, S.PANEL)
    b.text = S.Text(b, 13)
    b.text:SetPoint("CENTER")
    b.text:SetJustifyH("CENTER")
    b.SetText = function(self, s) self.text:SetText(s) end
    b.GetText = function(self) return self.text:GetText() end
    b:SetScript("OnEnter", function(self) S.SetBorder(self, S.Accent()) end)
    b:SetScript("OnLeave", function(self) S.SetBorder(self, S.BORDER) end)
    b:SetScript("OnDisable", function(self) self.text:SetAlpha(0.4) end)
    b:SetScript("OnEnable", function(self) self.text:SetAlpha(1) end)
    return b
end

-- A flat check box: a dark square that fills with the accent colour when ticked.
-- state: true, false or "some" (part of a group is ticked).
function S.Check(parent, size)
    local c = CreateFrame("Button", nil, parent)
    size = size or 26
    c:SetSize(size, size)
    local box = CreateFrame("Frame", nil, c)
    box:SetSize(16, 16)
    box:SetPoint("CENTER")
    S.Box(box, { 0.02, 0.02, 0.02, 1 }, { 0.25, 0.25, 0.27, 1 })
    c.box = box
    c.mark = tex(box, "ARTWORK", 0, S.Accent())
    c.mark:SetPoint("TOPLEFT", 3, -3)
    c.mark:SetPoint("BOTTOMRIGHT", -3, 3)
    c.state = false
    function c:SetChecked(state)
        self.state = state
        self.mark:SetShown(state and true or false)
        self.mark:SetAlpha(state == "some" and 0.45 or 1)
    end
    function c:GetChecked() return self.state == true end
    c:SetScript("OnEnter", function(self) S.SetBorder(self.box, S.Accent()) end)
    c:SetScript("OnLeave", function(self) S.SetBorder(self.box, { 0.25, 0.25, 0.27, 1 }) end)
    c:SetChecked(false)
    return c
end

function S.Edit(parent, width)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(width or 44, 26)
    S.Box(e, { 0.02, 0.02, 0.02, 1 })
    e:SetFont(FONT, 14, "")
    e:SetTextInsets(4, 4, 0, 0)
    e:SetJustifyH("CENTER")
    e:SetAutoFocus(false)
    e:SetScript("OnEditFocusGained", function(self) S.SetBorder(self, S.Accent()) end)
    e:SetScript("OnEditFocusLost", function(self) S.SetBorder(self, S.BORDER) end)
    return e
end

-- A scroll area with a thin scroll bar that can be dragged by mouse or touch.
function S.Scroll(parent)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(1, 1)
    sf:SetScrollChild(child)
    local bar = CreateFrame("Slider", nil, parent)
    bar:SetWidth(8)
    bar:SetPoint("TOPLEFT", sf, "TOPRIGHT", 4, 0)
    bar:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 4, 0)
    bar:SetOrientation("VERTICAL")
    S.Box(bar, { 0.02, 0.02, 0.02, 0.8 }, { 0, 0, 0, 0 })
    local thumb = bar:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(WHITE)
    thumb:SetVertexColor(0.35, 0.35, 0.38, 1)
    thumb:SetSize(8, 40)
    bar:SetThumbTexture(thumb)
    bar:SetMinMaxValues(0, 0)
    bar:SetValueStep(1)
    bar:SetScript("OnValueChanged", function(_, v) sf:SetVerticalScroll(v) end)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(_, delta)
        bar:SetValue(bar:GetValue() - delta * 40)
    end)
    function sf:Update(contentHeight)
        local range = math.max(0, contentHeight - self:GetHeight())
        bar:SetMinMaxValues(0, range)
        bar:SetShown(range > 0)
        if bar:GetValue() > range then bar:SetValue(range) end
    end
    function sf:Top() bar:SetValue(0); self:SetVerticalScroll(0) end
    sf.child, sf.bar = child, bar
    return sf
end

-- A multi-line text box that scrolls, for lists typed one entry per line.
function S.Memo(parent, width, height)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(width, height)
    S.Box(box, { 0.02, 0.02, 0.02, 1 })
    local sf = S.Scroll(box)
    sf:SetPoint("TOPLEFT", 6, -6)
    sf:SetPoint("BOTTOMRIGHT", -16, 6)
    local e = CreateFrame("EditBox", nil, sf)
    e:SetMultiLine(true)
    e:SetAutoFocus(false)
    e:SetFont(FONT, 13, "")
    e:SetWidth(width - 24)
    e:SetHeight(height - 12)
    sf:SetScrollChild(e)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEditFocusGained", function() S.SetBorder(box, S.Accent()) end)
    e:SetScript("OnEditFocusLost", function() S.SetBorder(box, S.BORDER) end)
    -- Keep the line with the cursor in view.
    e:SetScript("OnCursorChanged", function(self, _, y, _, h)
        sf:Update(self:GetHeight())
        local top, view = sf:GetVerticalScroll(), sf:GetHeight()
        y = -y
        if y < top then sf.bar:SetValue(y)
        elseif y + h > top + view then sf.bar:SetValue(y + h - view) end
    end)
    -- A click anywhere in the box starts typing, also below the last line.
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() e:SetFocus() end)
    box.edit, box.scroll = e, sf
    return box
end
