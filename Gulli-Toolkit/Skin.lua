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

-- A button filled with the accent colour, for the one main action of a view.
function S.Primary(b)
    local a = S.Accent()
    S.Fill(b, { a[1], a[2], a[3], 0.9 })
    b.text:SetTextColor(0.05, 0.05, 0.06, 1)
    return b
end

-- A flat pill that can be selected, for filters such as All / On / Off.
function S.Pill(parent, width, height)
    local b = S.Button(parent, width, height or 28)
    b.text:SetFont(FONT, 12, "")
    function b:SetSelected(on)
        self.selected = on
        local a = S.Accent()
        if on then
            S.Fill(self, { a[1], a[2], a[3], 0.22 })
            S.SetBorder(self, a)
            self.text:SetTextColor(a[1], a[2], a[3], 1)
        else
            S.Fill(self, S.PANEL)
            S.SetBorder(self, S.BORDER)
            self.text:SetTextColor(S.TEXT[1], S.TEXT[2], S.TEXT[3], 1)
        end
    end
    b:SetScript("OnLeave", function(self) self:SetSelected(self.selected) end)
    return b
end

-- An on/off switch: a track that fills with the accent colour and a knob that slides over.
-- The button is 44 by 28 so it is easy to hit by touch.
function S.Switch(parent)
    local s = CreateFrame("Button", nil, parent)
    s:SetSize(44, 28)
    local track = CreateFrame("Frame", nil, s)
    track:SetSize(36, 18)
    track:SetPoint("CENTER")
    S.Box(track, { 0.02, 0.02, 0.02, 1 }, { 0.25, 0.25, 0.27, 1 })
    s.track = track
    s.knob = tex(track, "ARTWORK", 0, S.TEXT)
    s.knob:SetSize(14, 14)
    function s:SetChecked(on)
        self.on = on and true or false
        local a = S.Accent()
        self.knob:ClearAllPoints()
        if self.on then
            self.knob:SetPoint("RIGHT", -2, 0)
            self.knob:SetVertexColor(1, 1, 1, 1)
            S.Fill(self.track, { a[1], a[2], a[3], 0.85 })
        else
            self.knob:SetPoint("LEFT", 2, 0)
            self.knob:SetVertexColor(0.45, 0.45, 0.48, 1)
            S.Fill(self.track, { 0.02, 0.02, 0.02, 1 })
        end
    end
    function s:GetChecked() return self.on end
    s:SetScript("OnEnter", function(self) S.SetBorder(self.track, S.Accent()) end)
    s:SetScript("OnLeave", function(self) S.SetBorder(self.track, { 0.25, 0.25, 0.27, 1 }) end)
    s:SetScript("OnDisable", function(self) self:SetAlpha(0.4) end)
    s:SetScript("OnEnable", function(self) self:SetAlpha(1) end)
    s:SetChecked(false)
    return s
end
