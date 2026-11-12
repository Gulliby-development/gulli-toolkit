-- The Gulli look, shared by every Gulli addon: dark layered panels, 1 pixel edges, the class
-- colour as the accent, and a fixed spacing scale. Built from plain textures, so it needs no
-- template and no library. This file is the same in every addon folder: edit
-- Gulli-Toolkit/Skin.lua and run tools/skin/sync.sh (CI checks that the copies match).

local addon, ns = ...

local S = {}
ns.Skin = S

local WHITE = "Interface\\Buttons\\WHITE8X8"
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

-- Colours. A window is the darkest layer, a card sits on it, a button sits on a card.
S.BG = { 0.067, 0.071, 0.082, 0.97 }
S.HEAD = { 0.090, 0.094, 0.108, 1 }
S.SURFACE = { 0.106, 0.110, 0.126, 1 }
S.RAISED = { 0.150, 0.155, 0.176, 1 }
S.INPUT = { 0.035, 0.037, 0.045, 1 }
S.EDGE = { 0.205, 0.212, 0.240, 1 }
S.LINE = { 1, 1, 1, 0.07 }
S.HOVER = { 1, 1, 1, 0.05 }
S.BORDER = { 0, 0, 0, 1 }
S.TEXT = { 0.93, 0.93, 0.94, 1 }
S.MUTED = { 0.60, 0.61, 0.66, 1 }
S.FAINT = { 0.42, 0.43, 0.48, 1 }
S.GOOD = { 0.42, 0.84, 0.50, 1 }
S.WARN = { 1.00, 0.72, 0.30, 1 }
S.BAD = { 0.93, 0.42, 0.40, 1 }
S.CLEAR = { 0, 0, 0, 0 }
-- Older names, still used by some windows.
S.PANEL = S.RAISED
S.ROW = { 1, 1, 1, 0.025 }

-- Spacing: 4, 8, 12, 16, 24. Window padding, gap between cards, padding inside a card.
S.PAD, S.GAP, S.INSET = 16, 12, 12
S.HEADER_H, S.FOOTER_H, S.ROW_H, S.ROW_DESC_H = 44, 56, 40, 56

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

-- The width of a text, or 0 where the game cannot tell yet.
local function strw(fs) return tonumber(fs:GetStringWidth()) or 0 end

local function tex(f, layer, sub, color)
    local t = f:CreateTexture(nil, layer, nil, sub)
    t:SetTexture(WHITE)
    t:SetVertexColor(color[1], color[2], color[3], color[4])
    return t
end
S.Tex = tex

-- A filled rectangle with a 1 pixel border around it.
function S.Box(f, bg, border)
    f.bg = tex(f, "BACKGROUND", -7, bg or S.BG)
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

-- A muted line of text; anchor it on both sides and it wraps.
function S.Note(parent, size)
    local t = S.Text(parent, size or 11, S.MUTED)
    t:SetJustifyV("TOP")
    return t
end

-- A grey paragraph of a known width; returns it and its height, for S.Stack.
function S.Paragraph(parent, text, width, size)
    local t = S.Note(parent, size or 11)
    t:SetWidth(width)
    t:SetText(text or "")
    return t, math.ceil(tonumber(t:GetStringHeight()) or 14)
end

-- A thin line across its parent, for separating rows.
function S.Divider(parent, color)
    return tex(parent, "BORDER", 0, color or S.LINE)
end

-- A short "Gulli Merchant" becomes "Merchant": the icon already says it is ours.
local function shortTitle(title)
    title = tostring(title or "")
    return (title:gsub("^Gulli[%s%-]+", ""))
end

-- Buttons ------------------------------------------------------------------------------------

local function paint(b)
    local hover = b.hover and b:IsEnabled()
    if b.kind == "primary" or b.kind == "danger" then
        local c = b.kind == "danger" and S.BAD or S.Accent()
        local k = hover and 1 or 0.86
        S.Fill(b, { c[1] * k, c[2] * k, c[3] * k, 1 })
        S.SetBorder(b, hover and S.TEXT or { c[1] * 0.6, c[2] * 0.6, c[3] * 0.6, 1 })
        b.text:SetTextColor(0.05, 0.05, 0.06, 1)
        b.text:SetShadowColor(0, 0, 0, 0)
    elseif b.kind == "ghost" then
        S.Fill(b, hover and S.HOVER or S.CLEAR)
        S.SetBorder(b, S.CLEAR)
    else
        S.Fill(b, hover and { 0.19, 0.195, 0.22, 1 } or S.RAISED)
        S.SetBorder(b, hover and S.Accent() or S.EDGE)
    end
end

-- A flat button: the edge lights up in the accent colour under the cursor.
function S.Button(parent, width, height)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 110, height or 30)
    S.Box(b, S.RAISED, S.EDGE)
    b.text = S.Text(b, 12)
    b.text:SetPoint("LEFT", 6, 0)
    b.text:SetPoint("RIGHT", -6, 0)
    b.text:SetJustifyH("CENTER")
    b.text:SetWordWrap(false)
    b.kind = "normal"
    b.SetText = function(self, s) self.text:SetText(s) end
    b.GetText = function(self) return self.text:GetText() end
    b:SetScript("OnEnter", function(self) self.hover = true; paint(self) end)
    b:SetScript("OnLeave", function(self) self.hover = false; paint(self) end)
    b:SetScript("OnDisable", function(self) self.text:SetAlpha(0.4); paint(self) end)
    b:SetScript("OnEnable", function(self) self.text:SetAlpha(1); paint(self) end)
    return b
end

-- The one main action of a view: filled with the accent colour.
function S.Primary(b)
    b.kind = "primary"
    paint(b)
    return b
end

-- An action that removes something for good: filled red.
function S.Danger(b)
    b.kind = "danger"
    paint(b)
    return b
end

-- A button without a box, for small actions inside a row.
function S.Ghost(b)
    b.kind = "ghost"
    b.text:SetTextColor(S.MUTED[1], S.MUTED[2], S.MUTED[3], 1)
    paint(b)
    return b
end

-- A button that fits its text: S.Button with the width of the label plus padding.
function S.FitButton(parent, text, height, minWidth)
    local b = S.Button(parent, 10, height or 30)
    b:SetText(text)
    b:SetWidth(math.max(minWidth or 72, math.floor(strw(b.text) + 28)))
    return b
end

-- A square close button with an X drawn from two lines.
local function closeButton(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(28, 28)
    S.Box(b, S.CLEAR, S.CLEAR)
    local lines = {}
    for i, d in ipairs({ { "TOPLEFT", 9, -9, "BOTTOMRIGHT", -9, 9 }, { "BOTTOMLEFT", 9, 9, "TOPRIGHT", -9, -9 } }) do
        local l = b:CreateLine(nil, "ARTWORK")
        l:SetThickness(1.5)
        l:SetColorTexture(S.MUTED[1], S.MUTED[2], S.MUTED[3], 1)
        l:SetStartPoint(d[1], b, d[2], d[3])
        l:SetEndPoint(d[4], b, d[5], d[6])
        lines[i] = l
    end
    local function color(c) for _, l in ipairs(lines) do l:SetColorTexture(c[1], c[2], c[3], 1) end end
    b:SetScript("OnEnter", function(self) S.Fill(self, { S.BAD[1], S.BAD[2], S.BAD[3], 0.25 }); color(S.TEXT) end)
    b:SetScript("OnLeave", function(self) S.Fill(self, S.CLEAR); color(S.MUTED) end)
    b:SetScript("OnClick", onClick)
    return b
end
S.Close = closeButton

-- Inputs -------------------------------------------------------------------------------------

-- A flat check box: a dark square that fills with the accent colour when ticked. It is 26
-- pixels so it is easy to hit by touch. state: true, false or "some" (part of a group).
function S.Check(parent, size)
    local c = CreateFrame("Button", nil, parent)
    size = size or 26
    c:SetSize(size, size)
    local box = CreateFrame("Frame", nil, c)
    box:SetSize(16, 16)
    box:SetPoint("CENTER")
    S.Box(box, S.INPUT, S.EDGE)
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
    c:SetScript("OnLeave", function(self) S.SetBorder(self.box, S.EDGE) end)
    c:SetChecked(false)
    return c
end

-- An on/off switch: a track that fills with the accent colour and a knob that slides over.
-- The button is 44 by 28 so it is easy to hit by touch.
function S.Switch(parent)
    local s = CreateFrame("Button", nil, parent)
    s:SetSize(44, 28)
    local track = CreateFrame("Frame", nil, s)
    track:SetSize(36, 18)
    track:SetPoint("CENTER")
    S.Box(track, S.INPUT, S.EDGE)
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
            S.Fill(self.track, S.INPUT)
        end
    end
    function s:GetChecked() return self.on end
    s:SetScript("OnEnter", function(self) S.SetBorder(self.track, S.Accent()) end)
    s:SetScript("OnLeave", function(self) S.SetBorder(self.track, S.EDGE) end)
    s:SetScript("OnDisable", function(self) self:SetAlpha(0.4) end)
    s:SetScript("OnEnable", function(self) self:SetAlpha(1) end)
    s:SetChecked(false)
    return s
end

function S.Edit(parent, width, height)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(width or 44, height or 28)
    S.Box(e, S.INPUT, S.EDGE)
    e:SetFont(FONT, 13, "")
    e:SetTextInsets(8, 8, 0, 0)
    e:SetJustifyH("CENTER")
    e:SetAutoFocus(false)
    e:SetScript("OnEditFocusGained", function(self) S.SetBorder(self, S.Accent()) end)
    e:SetScript("OnEditFocusLost", function(self) S.SetBorder(self, S.EDGE) end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return e
end

-- A grey hint inside an empty edit box, like "Search".
function S.Placeholder(edit, text)
    local p = S.Text(edit, 12, S.FAINT)
    p:SetPoint("LEFT", 8, 0)
    p:SetPoint("RIGHT", -8, 0)
    p:SetWordWrap(false)
    p:SetText(text)
    edit:HookScript("OnTextChanged", function(self) p:SetShown((self:GetText() or "") == "") end)
    edit.placeholder = p
    return p
end

-- A scroll area with a thin scroll bar that can be dragged by mouse or touch.
function S.Scroll(parent)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(1, 1)
    sf:SetScrollChild(child)
    local bar = CreateFrame("Slider", nil, parent)
    bar:SetWidth(6)
    bar:SetPoint("TOPLEFT", sf, "TOPRIGHT", 4, 0)
    bar:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 4, 0)
    bar:SetOrientation("VERTICAL")
    S.Box(bar, { 1, 1, 1, 0.03 }, S.CLEAR)
    local thumb = bar:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(WHITE)
    thumb:SetVertexColor(1, 1, 1, 0.22)
    thumb:SetSize(6, 40)
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
    S.Box(box, S.INPUT, S.EDGE)
    local sf = S.Scroll(box)
    sf:SetPoint("TOPLEFT", 8, -8)
    sf:SetPoint("BOTTOMRIGHT", -16, 8)
    local e = CreateFrame("EditBox", nil, sf)
    e:SetMultiLine(true)
    e:SetAutoFocus(false)
    e:SetFont(FONT, 13, "")
    e:SetWidth(width - 28)
    e:SetHeight(height - 16)
    sf:SetScrollChild(e)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEditFocusGained", function() S.SetBorder(box, S.Accent()) end)
    e:SetScript("OnEditFocusLost", function() S.SetBorder(box, S.EDGE) end)
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

-- Choosers -----------------------------------------------------------------------------------

-- A flat pill that can be selected, for filters such as All / On / Off.
function S.Pill(parent, width, height)
    local b = S.Button(parent, width, height or 28)
    function b:SetSelected(on)
        self.selected = on
        local a = S.Accent()
        if on then
            S.Fill(self, { a[1], a[2], a[3], 0.20 })
            S.SetBorder(self, a)
            self.text:SetTextColor(a[1], a[2], a[3], 1)
        else
            S.Fill(self, S.RAISED)
            S.SetBorder(self, S.EDGE)
            self.text:SetTextColor(S.TEXT[1], S.TEXT[2], S.TEXT[3], 1)
        end
    end
    b:SetScript("OnEnter", function(self) if not self.selected then S.SetBorder(self, S.Accent()) end end)
    b:SetScript("OnLeave", function(self) self:SetSelected(self.selected) end)
    return b
end

-- A segmented control: one track with a part per label, the chosen one filled. width is the
-- width of each part (nil fits each label). onSelect(i) runs on a click and on Select(i).
-- t.frame is the track (anchored to the top left of parent; move it freely), t.buttons the parts.
function S.Tabs(parent, labels, width, onSelect, height)
    height = height or 30
    local t = { buttons = {}, selected = 1 }
    local track = CreateFrame("Frame", nil, parent)
    track:SetPoint("TOPLEFT")
    S.Box(track, S.INPUT, S.EDGE)
    t.frame = track
    local x = 2
    for i, label in ipairs(labels) do
        local b = CreateFrame("Button", nil, track)
        S.Box(b, S.CLEAR, S.CLEAR)
        b.text = S.Text(b, 12, S.MUTED)
        b.text:SetPoint("LEFT", 6, 0)
        b.text:SetPoint("RIGHT", -6, 0)
        b.text:SetJustifyH("CENTER")
        b.text:SetWordWrap(false)
        b.text:SetText(label)
        b.SetText = function(self, s) self.text:SetText(s) end
        b.GetText = function(self) return self.text:GetText() end
        local w = width or math.floor(strw(b.text) + 28)
        b:SetSize(w, height - 4)
        b:SetPoint("TOPLEFT", x, -2)
        x = x + w
        b.bar = tex(b, "ARTWORK", 0, S.Accent())
        b.bar:SetPoint("BOTTOMLEFT", 6, 0)
        b.bar:SetPoint("BOTTOMRIGHT", -6, 0)
        b.bar:SetHeight(2)
        b:SetScript("OnClick", function() t:Select(i) end)
        b:SetScript("OnEnter", function(self) if t.selected ~= i then S.Fill(self, S.HOVER) end end)
        b:SetScript("OnLeave", function(self) if t.selected ~= i then S.Fill(self, S.CLEAR) end end)
        t.buttons[i] = b
    end
    track:SetSize(x + 2, height)
    function t:Select(i, quiet)
        self.selected = i
        for j, b in ipairs(self.buttons) do
            local on = j == i
            S.Fill(b, on and S.RAISED or S.CLEAR)
            b.bar:SetShown(on)
            local c = on and S.TEXT or S.MUTED
            b.text:SetTextColor(c[1], c[2], c[3], 1)
        end
        if onSelect and not quiet then onSelect(i) end
    end
    t:Select(1, true)
    return t
end

-- Layout -------------------------------------------------------------------------------------

-- Places frames under each other with a fixed gap, so no window counts pixels by hand.
-- st:Add(frame, height[, gap]) puts frame across the parent; st.y is the height used so far.
function S.Stack(parent, gap, startY)
    local st = { y = startY or 0, gap = gap or S.GAP, items = {} }
    function st:Add(frame, height, gapAfter)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -self.y)
        frame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -self.y)
        if height then frame:SetHeight(height) end
        self.items[#self.items + 1] = frame
        self.y = self.y + (height or frame:GetHeight()) + (gapAfter or self.gap)
        return frame
    end
    function st:Space(n) self.y = self.y + n end
    function st:Height() return math.max(0, self.y - self.gap) end
    return st
end

-- A card: a lighter panel with an optional title (a game icon before it, a grey hint on the
-- right) for one group of things. card.body is the area inside the padding, under the title.
function S.Card(parent, title, hint, icon)
    local c = CreateFrame("Frame", nil, parent)
    S.Box(c, S.SURFACE, S.EDGE)
    c.body = CreateFrame("Frame", nil, c)
    c.body:SetPoint("BOTTOMRIGHT", -S.INSET, S.INSET)
    if title then
        c.title = S.Text(c, 13)
        if icon then
            c.icon = S.IconBox(c, 18, icon)
            c.icon:SetPoint("TOPLEFT", S.INSET, -10)
            c.title:SetPoint("TOPLEFT", S.INSET + 26, -12)
        else
            c.title:SetPoint("TOPLEFT", S.INSET, -12)
        end
        c.title:SetWordWrap(false)
        c.title:SetText(title)
        c.hint = S.Text(c, 11, S.MUTED)
        c.hint:SetPoint("TOPRIGHT", -S.INSET, -13)
        c.hint:SetJustifyH("RIGHT")
        c.hint:SetWordWrap(false)
        c.hint:SetText(hint or "")
        c.title:SetPoint("RIGHT", c.hint, "LEFT", -8, 0)
        c.body:SetPoint("TOPLEFT", S.INSET, -36)
    else
        c.body:SetPoint("TOPLEFT", S.INSET, -S.INSET)
    end
    function c:SetTitle(t, h)
        if self.title then self.title:SetText(t) end
        if h and self.hint then self.hint:SetText(h) end
    end
    -- The card height that fits a body of h pixels.
    function c:Fit(h)
        local total = h + (title and 36 or S.INSET) + S.INSET
        self:SetHeight(total)
        return total
    end
    return c
end

-- A settings row: the label and an optional grey line under it on the left, a control on the
-- right (a switch, an edit box, a button...). row.control is that control.
function S.SettingRow(parent, label, desc, control, controlWidth, icon)
    local row = CreateFrame("Frame", nil, parent)
    local left = 0
    if icon then
        row.icon = S.IconBox(row, 26, icon)
        row.icon:SetPoint("LEFT", 0, 0)
        left = 26 + 12
    end
    row.label = S.Text(row, 12)
    row.label:SetWordWrap(false)
    row.label:SetText(label)
    local right = -((controlWidth or (control and control:GetWidth()) or 0) + 12)
    if desc and desc ~= "" then
        row.label:SetPoint("TOPLEFT", left, -10)
        row.label:SetPoint("TOPRIGHT", right, -10)
        row.desc = S.Note(row, 11)
        row.desc:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -4)
        row.desc:SetPoint("TOPRIGHT", row.label, "BOTTOMRIGHT", 0, -4)
        row.desc:SetMaxLines(2)
        row.desc:SetText(desc)
        row.height = S.ROW_DESC_H
    else
        row.label:SetPoint("LEFT", left, 0)
        row.label:SetPoint("RIGHT", right, 0)
        row.height = S.ROW_H
    end
    if control then
        control:SetParent(row)
        control:ClearAllPoints()
        control:SetPoint("RIGHT", 0, 0)
        row.control = control
    end
    row.line = S.Divider(row)
    row.line:SetPoint("BOTTOMLEFT")
    row.line:SetPoint("BOTTOMRIGHT")
    row.line:SetHeight(1)
    return row
end

-- A settings row with an on/off switch. get() and set(value) read and write the setting.
-- extra (an edit box for a number...) sits left of the switch.
function S.SwitchRow(parent, label, desc, get, set, extra, icon)
    local sw = S.Switch(parent)
    local row = S.SettingRow(parent, label, desc, sw, 44 + (extra and (extra:GetWidth() + 8) or 0), icon)
    row.switch = sw
    if extra then
        extra:SetParent(row)
        extra:ClearAllPoints()
        extra:SetPoint("RIGHT", sw, "LEFT", -8, 0)
        row.extra = extra
    end
    sw:SetScript("OnClick", function(self)
        set(not get())
        self:SetChecked(get())
    end)
    row:SetScript("OnShow", function() sw:SetChecked(get()) end)
    sw:SetChecked(get())
    function row:SetChecked(v) sw:SetChecked(v) end
    function row:GetChecked() return sw:GetChecked() end
    return row
end

-- A card full of settings rows, stacked with their dividers. rows: { label, desc, get, set }
-- for a switch, or { label, desc, control = frame } for any other control; icon = a game icon
-- path shows it at the start of the row. Returns the card
-- and its height; card.rows has the rows in order.
function S.SettingsCard(parent, title, rows, hint, icon)
    local card = S.Card(parent, title, hint, icon)
    card.rows = {}
    local st = S.Stack(card.body, 0)
    for i, r in ipairs(rows) do
        local row = r.control and S.SettingRow(card.body, r[1], r[2], r.control, nil, r.icon)
            or S.SwitchRow(card.body, r[1], r[2], r[3], r[4], r.extra, r.icon)
        st:Add(row, row.height)
        row.line:SetShown(i < #rows)
        card.rows[i] = row
    end
    return card, card:Fit(st:Height() - (title and 6 or 0))
end

-- A check box with its label to the right; get() and set(value) read and write the setting.
-- The label is anchored to the box, so put the box where the row goes.
function S.CheckRow(parent, label, get, set, width)
    local c = S.Check(parent, 26)
    c.label = S.Text(c, 12)
    c.label:SetPoint("LEFT", c, "RIGHT", 6, 0)
    c.label:SetWidth(width or 300)
    c.label:SetWordWrap(false)
    c.label:SetText(label)
    c:SetScript("OnClick", function(self)
        set(not get())
        self:SetChecked(get())
    end)
    c:SetScript("OnShow", function(self) self:SetChecked(get()) end)
    c:SetChecked(get())
    return c
end

-- Showing state ------------------------------------------------------------------------------

-- A message in the middle of an empty area: a title and a grey line under it.
function S.Empty(parent)
    local e = CreateFrame("Frame", nil, parent)
    e:SetAllPoints()
    e.title = S.Text(e, 13, S.MUTED)
    e.title:SetPoint("BOTTOMLEFT", e, "LEFT", 24, 4)
    e.title:SetPoint("BOTTOMRIGHT", e, "RIGHT", -24, 4)
    e.title:SetJustifyH("CENTER")
    e.sub = S.Note(e, 11)
    e.sub:SetTextColor(S.FAINT[1], S.FAINT[2], S.FAINT[3], 1)
    e.sub:SetPoint("TOPLEFT", e, "LEFT", 24, -4)
    e.sub:SetPoint("TOPRIGHT", e, "RIGHT", -24, -4)
    e.sub:SetJustifyH("CENTER")
    function e:Set(title, sub)
        self.title:SetText(title or "")
        self.sub:SetText(sub or "")
    end
    return e
end

-- A tile with one big number and its name under it, for counters.
function S.Stat(parent, label, icon)
    local t = CreateFrame("Frame", nil, parent)
    S.Box(t, S.SURFACE, S.EDGE)
    local right = -S.INSET
    if icon then
        t.icon = S.IconBox(t, 30, icon)
        t.icon:SetPoint("RIGHT", -S.INSET, 0)
        right = -S.INSET - 38
    end
    t.value = S.Text(t, 20)
    t.value:SetPoint("TOPLEFT", S.INSET, -12)
    t.value:SetPoint("TOPRIGHT", right, -12)
    t.value:SetWordWrap(false)
    t.label = S.Text(t, 11, S.MUTED)
    t.label:SetPoint("TOPLEFT", t.value, "BOTTOMLEFT", 0, -6)
    t.label:SetPoint("TOPRIGHT", t.value, "BOTTOMRIGHT", 0, -6)
    t.label:SetWordWrap(false)
    t.label:SetText(label or "")
    function t:Set(value, color, label2)
        self.value:SetText(value)
        local c = color or S.TEXT
        self.value:SetTextColor(c[1], c[2], c[3], 1)
        if label2 then self.label:SetText(label2) end
    end
    return t
end

-- Tiles side by side, all the same width: holder:Layout(width) places them. holder.tiles.
-- icons (optional) gives each tile a game icon.
function S.StatRow(parent, labels, height, icons)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(height or 62)
    holder.tiles = {}
    for i, label in ipairs(labels) do holder.tiles[i] = S.Stat(holder, label, icons and icons[i]) end
    function holder:Layout(width)
        local n = #self.tiles
        local w = math.floor((width - (n - 1) * 8) / n)
        for i, t in ipairs(self.tiles) do
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", (i - 1) * (w + 8), 0)
            t:SetSize(w, self:GetHeight())
        end
    end
    return holder
end

-- A place to drop an item from the bags (or click with one on the cursor). onDrop() reads the
-- cursor itself.
function S.DropZone(parent, text, onDrop, height)
    local d = CreateFrame("Button", nil, parent)
    d:SetHeight(height or 40)
    S.Box(d, S.INPUT, S.EDGE)
    d.text = S.Text(d, 12, S.MUTED)
    d.text:SetPoint("LEFT", 10, 0)
    d.text:SetPoint("RIGHT", -10, 0)
    d.text:SetJustifyH("CENTER")
    d.text:SetText("+  " .. (text or ""))
    d:SetScript("OnReceiveDrag", onDrop)
    d:SetScript("OnClick", onDrop)
    d:SetScript("OnEnter", function(self)
        S.SetBorder(self, S.Accent())
        self.text:SetTextColor(S.TEXT[1], S.TEXT[2], S.TEXT[3], 1)
    end)
    d:SetScript("OnLeave", function(self)
        S.SetBorder(self, S.EDGE)
        self.text:SetTextColor(S.MUTED[1], S.MUTED[2], S.MUTED[3], 1)
    end)
    return d
end

-- A thin bar that fills from the left: bar:Set(fraction[, color]).
function S.Progress(parent, height)
    local p = CreateFrame("Frame", nil, parent)
    p:SetHeight(height or 6)
    S.Box(p, S.INPUT, S.EDGE)
    p.fill = tex(p, "ARTWORK", 0, S.Accent())
    p.fill:SetPoint("TOPLEFT", 1, -1)
    p.fill:SetPoint("BOTTOMLEFT", 1, 1)
    function p:Set(f, c)
        f = math.max(0, math.min(1, f or 0))
        local w = (tonumber(self:GetWidth()) or 0) - 2
        self.fill:SetWidth(math.max(0.01, w * f))
        self.fill:SetShown(f > 0)
        if c then self.fill:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end
    end
    return p
end

-- A small coloured label, like "On" or "3 new".
function S.Badge(parent, text, color)
    local b = CreateFrame("Frame", nil, parent)
    S.Box(b, S.CLEAR, S.CLEAR)
    b.text = S.Text(b, 10)
    b.text:SetPoint("CENTER")
    function b:Set(s, c)
        c = c or S.MUTED
        self.text:SetText(s or "")
        self.text:SetTextColor(c[1], c[2], c[3], 1)
        S.Fill(self, { c[1], c[2], c[3], 0.14 })
        S.SetBorder(self, { c[1], c[2], c[3], 0.35 })
        self:SetSize(math.floor(strw(self.text) + 12), 18)
        self:SetShown(s ~= nil and s ~= "")
    end
    b:Set(text, color)
    return b
end

-- A game icon (an item or a spell, "Interface\\Icons\\...") in a thin dark frame, cropped
-- like the action bars do. box.tex is the texture.
function S.IconBox(parent, size, path)
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(size or 26, size or 26)
    S.Box(b, S.INPUT, S.BORDER)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetPoint("TOPLEFT", 1, -1)
    b.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    function b:SetIcon(p) self.tex:SetTexture(p or "Interface\\Icons\\INV_Misc_QuestionMark") end
    b:SetIcon(path)
    return b
end

-- An item in a game icon frame, with a stack count in the corner and the border in the
-- item's quality colour: icon:Set(texture, count, quality).
S.QUALITY = { [2] = { 0.12, 1, 0, 1 }, [3] = { 0, 0.44, 0.87, 1 }, [4] = { 0.64, 0.21, 0.93, 1 } }
function S.ItemIcon(parent, size)
    local b = S.IconBox(parent, size)
    b.count = S.Text(b, math.max(8, math.floor((size or 26) * 0.45)), S.TEXT, "OUTLINE")
    b.count:SetPoint("BOTTOMRIGHT", 0, 1)
    function b:Set(texture, n, quality)
        self:SetIcon(texture)
        self.count:SetText((n and n > 1) and (n > 999 and (math.floor(n / 100) / 10 .. "k") or tostring(n)) or "")
        S.SetBorder(self, S.QUALITY[quality or 1] or S.BORDER)
        self:Show()
    end
    return b
end

-- A number with - and + buttons: get() reads it, set(value) writes it; fmt(value) shows it.
-- stepper.minus, stepper.plus and stepper.value; stepper:Refresh() redraws the number.
function S.Stepper(parent, get, set, step, min, max, fmt, width)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width or 110, 28)
    f.minus = S.Button(f, 28, 28)
    f.minus:SetPoint("LEFT")
    f.minus:SetText("-")
    f.plus = S.Button(f, 28, 28)
    f.plus:SetPoint("RIGHT")
    f.plus:SetText("+")
    f.value = S.Text(f, 12)
    f.value:SetPoint("LEFT", f.minus, "RIGHT", 2, 0)
    f.value:SetPoint("RIGHT", f.plus, "LEFT", -2, 0)
    f.value:SetJustifyH("CENTER")
    f.value:SetWordWrap(false)
    function f:Refresh() self.value:SetText((fmt or tostring)(get())) end
    f.minus:SetScript("OnClick", function() set(math.max(min, get() - step)); f:Refresh() end)
    f.plus:SetScript("OnClick", function() set(math.min(max, get() + step)); f:Refresh() end)
    f:Refresh()
    return f
end

-- The module icon, from the addon folder.
function S.Icon(parent, size)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetSize(size or 20, size or 20)
    t:SetTexture("Interface\\AddOns\\" .. tostring(addon) .. "\\icon")
    t:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    return t
end

-- Windows ------------------------------------------------------------------------------------

-- A movable window: a header with the addon icon, the title, a grey subtitle (the slash
-- command) and a close button. frame.body is the padded area under the header; S.Footer adds
-- a bar for the buttons at the bottom. opts: { sub = "/gmc", icon = path, strata, fullTitle }.
function S.Window(name, title, width, height, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(width, height)
    f:SetPoint("CENTER")
    f:SetFrameStrata(opts.strata or "DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    -- A soft shadow: a few dark rings outside the edge.
    for i = 1, 4 do
        local sh = tex(f, "BACKGROUND", -8, { 0, 0, 0, 0.16 - i * 0.03 })
        sh:SetPoint("TOPLEFT", -i, i)
        sh:SetPoint("BOTTOMRIGHT", i, -i - 1)
    end
    S.Box(f, S.BG, S.BORDER)
    if name then tinsert(UISpecialFrames, name) end

    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    bar:SetHeight(S.HEADER_H)
    S.Box(bar, S.HEAD, S.CLEAR)
    local line = S.Divider(bar, S.EDGE)
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(1)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() f:StartMoving() end)
    bar:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    f.bar = bar

    f.icon = S.Icon(bar, 22)
    if opts.icon then f.icon:SetTexture(opts.icon) end
    f.icon:SetPoint("LEFT", 14, 0)
    f.title = S.Text(bar, 14)
    f.title:SetPoint("LEFT", f.icon, "RIGHT", 10, 0)
    f.title:SetWordWrap(false)
    f.title:SetText(opts.fullTitle and title or shortTitle(title))
    f.sub = S.Text(bar, 11, S.FAINT)
    f.sub:SetPoint("LEFT", f.title, "RIGHT", 8, -1)
    f.sub:SetWordWrap(false)
    local slash = _G["SLASH_" .. tostring(addon):gsub("%-", ""):upper() .. "1"]
    f.sub:SetText(opts.sub or slash or "")

    f.close = closeButton(bar, function() f:Hide() end)
    f.close:SetPoint("RIGHT", -8, 0)
    -- Small header buttons (help, scale...) go left of the close button: f:AddHeaderButton(b).
    f.headerRight = f.close
    function f:AddHeaderButton(b)
        b:SetParent(bar)
        b:ClearAllPoints()
        b:SetPoint("RIGHT", self.headerRight, "LEFT", -6, 0)
        self.headerRight = b
        return b
    end

    f.body = CreateFrame("Frame", nil, f)
    f.body:SetPoint("TOPLEFT", S.PAD, -(S.HEADER_H + S.PAD))
    f.body:SetPoint("BOTTOMRIGHT", -S.PAD, S.PAD)
    f.inner = { width - 2 * S.PAD, height - S.HEADER_H - 2 * S.PAD }
    f:Hide()
    return f
end

-- Sets the window height so the body is exactly h pixels high.
function S.FitWindow(f, h)
    f:SetHeight(S.HEADER_H + 2 * S.PAD + h + (f.footer and S.FOOTER_H or 0))
end

-- A bar at the bottom of a window for its buttons: the main one on the right, a grey status
-- line on the left. footer:Add(button) puts buttons from the right to the left.
function S.Footer(f)
    local ft = CreateFrame("Frame", nil, f)
    ft:SetPoint("BOTTOMLEFT", 1, 1)
    ft:SetPoint("BOTTOMRIGHT", -1, 1)
    ft:SetHeight(S.FOOTER_H)
    S.Box(ft, S.HEAD, S.CLEAR)
    local line = S.Divider(ft, S.EDGE)
    line:SetPoint("TOPLEFT")
    line:SetPoint("TOPRIGHT")
    line:SetHeight(1)
    ft.status = S.Note(ft, 11)
    ft.status:SetJustifyV("MIDDLE")
    ft.status:SetPoint("TOPLEFT", S.PAD, -8)
    ft.status:SetPoint("BOTTOMLEFT", S.PAD, 8)
    ft.status:SetMaxLines(2)
    ft.last = nil
    function ft:Add(b)
        b:SetParent(self)
        b:ClearAllPoints()
        if self.last then b:SetPoint("RIGHT", self.last, "LEFT", -8, 0)
        else b:SetPoint("RIGHT", -S.PAD, 0) end
        self.last = b
        self.status:SetPoint("RIGHT", b, "LEFT", -12, 0)
        return b
    end
    function ft:SetStatus(s, c)
        c = c or S.MUTED
        self.status:SetText(s or "")
        self.status:SetTextColor(c[1], c[2], c[3], 1)
    end
    f.body:SetPoint("BOTTOMRIGHT", -S.PAD, S.FOOTER_H + S.PAD)
    f.inner[2] = f.inner[2] - S.FOOTER_H
    f.footer = ft
    return ft
end

-- A column of choices on the left of a window (characters, dungeons...). Like S.List, with
-- the chosen row marked by the accent bar.
function S.NavRow(r)
    S.Fill(r, S.CLEAR)
    r.mark = tex(r, "ARTWORK", 0, S.Accent())
    r.mark:SetPoint("TOPLEFT")
    r.mark:SetPoint("BOTTOMLEFT")
    r.mark:SetWidth(2)
    r.mark:Hide()
    function r:SetSelected(on)
        self.selected = on
        S.Fill(self, on and S.RAISED or S.CLEAR)
        self.mark:SetShown(on)
    end
    return r
end

-- A scrolling list of rows that are made once and reused. make(row) builds a row frame,
-- fill(row, item, i) shows one item in it. list:SetData(items) redraws. Rows are separated by
-- a hairline and light up under the cursor when they are buttons.
function S.List(parent, rowHeight, make, fill, gap)
    gap = gap or 0
    local sf = S.Scroll(parent)
    local rows = {}
    function sf:SetData(items)
        local width = self:GetWidth()
        self.child:SetWidth(width > 1 and width or 400)
        for i, item in ipairs(items) do
            local r = rows[i]
            if not r then
                r = CreateFrame("Frame", nil, self.child)
                r:SetHeight(rowHeight)
                r:SetPoint("TOPLEFT", 0, -(i - 1) * (rowHeight + gap))
                r:SetPoint("TOPRIGHT", 0, -(i - 1) * (rowHeight + gap))
                S.Box(r, S.CLEAR, S.CLEAR)
                r.line = S.Divider(r)
                r.line:SetPoint("BOTTOMLEFT")
                r.line:SetPoint("BOTTOMRIGHT")
                r.line:SetHeight(1)
                make(r)
                rows[i] = r
            end
            fill(r, item, i)
            r:Show()
        end
        for i = #items + 1, #rows do rows[i]:Hide() end
        local h = #items * (rowHeight + gap)
        self.child:SetHeight(math.max(h, 1))
        self:Update(h)
    end
    sf.rows = rows
    return sf
end
