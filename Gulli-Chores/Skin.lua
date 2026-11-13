-- The Gulli look, shared by every Gulli addon: dark layered panels, 1 pixel edges, the class
-- colour as the accent, and a fixed spacing scale. Built from plain textures, so it needs no
-- template and no library. This file is the same in every addon folder: edit
-- Gulli-Toolkit/Skin.lua and run tools/skin/sync.sh (CI checks that the copies match).

local addon, ns = ...

local S = {}
ns.Skin = S

local WHITE = "Interface\\Buttons\\WHITE8X8"
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

-- The English game font has no Cyrillic or CJK glyphs, so Russian names and chat came out
-- blank. Text goes through a font family with the game's font for each alphabet.
local ALPHABETS = {
    { "roman", FONT }, { "russian", "Fonts\\FRIZQT___CYR.TTF" }, { "korean", "Fonts\\2002.TTF" },
    { "simplifiedchinese", "Fonts\\ARKai_T.ttf" }, { "traditionalchinese", "Fonts\\blei00d.TTF" },
}
local families = {}
local function family(size, flags)
    if not CreateFontFamily then return nil end
    flags = flags or ""
    local key = "GulliFont" .. size .. flags:gsub("%W", "")
    if families[key] == nil then
        local f = _G[key]
        if not f then
            local members = {}
            for _, a in ipairs(ALPHABETS) do
                members[#members + 1] = { alphabet = a[1], file = a[2], height = size, flags = flags }
            end
            local ok, made = pcall(CreateFontFamily, key, members)
            f = ok and made or false
        end
        families[key] = f
    end
    return families[key] or nil
end
function S.SetFont(region, size, flags)
    size = math.floor(size or 12)
    local f = family(size, flags)
    if f then region:SetFontObject(f) else region:SetFont(FONT, size, flags or "") end
end

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
-- Coin colours: money as coloured text, "28g 42s 5c", empty parts left out.
S.GOLD = { 1, 0.82, 0, 1 }
S.SILVER = { 0.78, 0.78, 0.81, 1 }
S.COPPER = { 0.93, 0.65, 0.37, 1 }
-- Older names, still used by some windows.
S.PANEL = S.RAISED
S.ROW = { 1, 1, 1, 0.025 }

-- Spacing: 4, 8, 12, 16, 24. Window padding, gap between cards, padding inside a card.
S.PAD, S.GAP, S.INSET = 16, 12, 12
S.HEADER_H, S.FOOTER_H, S.ROW_H, S.ROW_DESC_H = 44, 56, 40, 56
-- Window sizes that fit the hub (/gulli): a narrow window takes the place of the module list and
-- leaves the module card beside it, a wide one takes both. No window is taller than DOCK_H.
S.NARROW_W, S.WIDE_W, S.DOCK_H = 540, 832, 624

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
local function strw(fs) return tonumber((fs:GetStringWidth())) or 0 end

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
    S.SetFont(t, size or 12, flags)
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

-- Tab icons with one meaning in every module (pass them as the icons of S.Tabs).
local TI = "Interface\\Icons\\"
S.TAB = {
    settings = TI .. "Trade_Engineering", rules = TI .. "INV_Scroll_05", recent = TI .. "INV_Misc_PocketWatch_01",
    list = TI .. "INV_Scroll_02", group = TI .. "INV_Misc_GroupNeedMore", char = TI .. "INV_Misc_Head_Human_01",
    overview = TI .. "INV_Misc_Spyglass_02", quests = TI .. "INV_Scroll_03", items = TI .. "INV_Misc_Bag_10",
    search = TI .. "INV_Misc_Spyglass_03", mail = TI .. "INV_Letter_15", write = TI .. "INV_Letter_01",
    vendor = TI .. "INV_Misc_Coin_01", chat = TI .. "INV_Letter_02", more = TI .. "INV_Misc_Note_05",
}

-- Group roles, in every module that names one.
S.ROLE_ICON = { TANK = TI .. "Ability_Warrior_DefensiveStance", HEALER = TI .. "Spell_Holy_FlashHeal",
                DPS = TI .. "INV_Sword_04" }

-- A game icon inside a line of text (|T...|t), cropped like the icon boxes.
function S.IconTag(path, size)
    size = size or 14
    return "|T" .. path .. ":" .. size .. ":" .. size .. ":0:0:64:64:5:59:5:59|t"
end

-- A small game icon on the left of a button or tab, before its text (nil removes it). Only for
-- tabs, filters and pick-one choices (a kind, a role, a roll); main actions stay text.
function S.SetButtonIcon(b, path, size)
    size = size or 16
    if not rawget(b, "btnIcon") then
        b.btnIcon = b:CreateTexture(nil, "ARTWORK")
        b.btnIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    b.btnIcon:SetSize(size, size)
    b.btnIcon:ClearAllPoints()
    b.btnIcon:SetPoint("LEFT", 7, 0)
    b.btnIcon:SetTexture(path)
    b.btnIcon:SetShown(path ~= nil)
    b.text:ClearAllPoints()
    b.text:SetPoint("LEFT", path and size + 11 or 6, 0)
    b.text:SetPoint("RIGHT", -6, 0)
    return b
end

-- A choice with a game icon: the icon (with a count in its corner) on the left, a title and a
-- muted line under it; `vertical` puts the icon on top and the title under it (no line).
-- tile:Set{ icon, title, sub, count, quality }; SetEnabled greys it out.
function S.IconTile(parent, width, height, vertical)
    height = height or (vertical and 54 or 36)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 110, height)
    S.Box(b, S.RAISED, S.EDGE)
    b.kind = "normal"
    b.title = S.Text(b, vertical and 10 or 11)
    b.title:SetWordWrap(false)
    b.sub = S.Text(b, 9, S.MUTED)
    b.sub:SetWordWrap(false)
    if vertical then
        b.item = S.ItemIcon(b, height - 24)
        b.item:SetPoint("TOP", 0, -4)
        b.title:SetPoint("BOTTOMLEFT", 3, 4)
        b.title:SetPoint("BOTTOMRIGHT", -3, 4)
        b.title:SetJustifyH("CENTER")
        b.sub:Hide()
    else
        b.item = S.ItemIcon(b, height - 8)
        b.item:SetPoint("LEFT", 4, 0)
        b.title:SetPoint("TOPLEFT", b.item, "TOPRIGHT", 5, -1)
        b.title:SetPoint("RIGHT", -4, 0)
        b.title:SetJustifyH("LEFT")
        b.sub:SetPoint("BOTTOMLEFT", b.item, "BOTTOMRIGHT", 5, 1)
        b.sub:SetPoint("RIGHT", -4, 0)
        b.sub:SetJustifyH("LEFT")
    end
    b.text = b.title
    function b:Set(o)
        self.item:Set(o.icon, o.count, o.quality)
        self.item.count:SetText(o.count and o.count > 0 and tostring(o.count) or "")
        self.title:SetText(o.title or "")
        self.sub:SetText(o.sub or "")
    end
    b.SetText = function(self, s) self.title:SetText(s) end
    b.GetText = function(self) return self.title:GetText() end
    local function dim(self, a) self.item:SetAlpha(a); self.title:SetAlpha(a); self.sub:SetAlpha(a) end
    b:SetScript("OnEnter", function(self) self.hover = true; paint(self) end)
    b:SetScript("OnLeave", function(self) self.hover = false; paint(self) end)
    b:SetScript("OnDisable", function(self) dim(self, 0.4); paint(self) end)
    b:SetScript("OnEnable", function(self) dim(self, 1); paint(self) end)
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
    S.SetFont(e, 13)
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
    local function update(self) p:SetShown((self:GetText() or "") == "") end
    edit:HookScript("OnTextChanged", update)
    -- A later SetScript("OnTextChanged") would drop the hook and leave the hint over the text.
    local set = edit.SetScript
    edit.SetScript = function(self, name, fn, ...)
        if name == "OnTextChanged" then
            return set(self, name, function(e, ...) update(e); if fn then return fn(e, ...) end end)
        end
        return set(self, name, fn, ...)
    end
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
    sf:SetScript("OnMouseWheel", function(self, delta)
        bar:SetValue(bar:GetValue() - delta * (self.step or 40))
    end)
    -- The bar shows only when the content is taller than the view; the thumb is as long as the
    -- share in view. The view's own size can change later (docked in the hub), so it counts again.
    function sf:Update(contentHeight)
        self.content = contentHeight or self.content or 0
        local view = self:GetHeight()
        local range = self.content - view
        if range < 2 then range = 0 end
        bar:SetMinMaxValues(0, range)
        bar:SetShown(range > 0)
        if range > 0 and view > 0 then
            thumb:SetHeight(math.max(24, math.floor(view * view / self.content)))
        end
        if bar:GetValue() > range then bar:SetValue(range) end
        if range == 0 then self:SetVerticalScroll(0) end
    end
    sf:SetScript("OnSizeChanged", function(self, w)
        if self.onResize then self.onResize(self, w) end
        if self.content then self:Update() end
    end)
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
    S.SetFont(e, 13)
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
-- icons (optional) is a list of game icon paths, one per label, shown left of the text; with
-- an empty label the icon alone fills the part (set button.tip so the cursor names it).
function S.Tabs(parent, labels, width, onSelect, height, icons)
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
        if icons and icons[i] and label == "" then
            S.SetButtonIcon(b, icons[i], 18)
            b.btnIcon:ClearAllPoints()
            b.btnIcon:SetPoint("CENTER")
        elseif icons and icons[i] then
            S.SetButtonIcon(b, icons[i], 14)
        end
        local w = width or math.floor(strw(b.text) + 28 + (icons and icons[i] and 18 or 0))
        b:SetSize(w, height - 4)
        b:SetPoint("TOPLEFT", x, -2)
        x = x + w
        b.bar = tex(b, "ARTWORK", 0, S.Accent())
        b.bar:SetPoint("BOTTOMLEFT", 6, 0)
        b.bar:SetPoint("BOTTOMRIGHT", -6, 0)
        b.bar:SetHeight(2)
        b:SetScript("OnClick", function() t:Select(i) end)
        b:SetScript("OnEnter", function(self)
            if t.selected ~= i then S.Fill(self, S.HOVER) end
            if self.tip and GameTooltip and GameTooltip.SetOwner then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(self.tip)
                GameTooltip:Show()
            end
        end)
        b:SetScript("OnLeave", function(self)
            if t.selected ~= i then S.Fill(self, S.CLEAR) end
            if self.tip and GameTooltip then GameTooltip:Hide() end
        end)
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
            if rawget(b, "btnIcon") then b.btnIcon:SetAlpha(on and 1 or 0.55) end
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

-- An on/off switch with its label to the right, for a setting outside a settings card (a list
-- filter). get() and set(value) read and write the setting. The label is anchored to the switch,
-- so put the switch where the row goes. Check boxes are for picking entries of a list, never for
-- a setting.
function S.SwitchLabel(parent, label, get, set, width)
    local s = S.Switch(parent)
    s.label = S.Text(s, 12)
    s.label:SetPoint("LEFT", s, "RIGHT", 4, 0)
    s.label:SetWidth(width or 300)
    s.label:SetWordWrap(false)
    s.label:SetText(label)
    s:SetScript("OnClick", function(self)
        set(not get())
        self:SetChecked(get())
    end)
    s:SetScript("OnShow", function(self) self:SetChecked(get()) end)
    s:SetChecked(get())
    return s
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

-- Money in the coin colours, so gold, silver and copper read at a glance. `short` drops the
-- copper from 1 gold up (for tiles). A negative amount starts with a minus.
function S.MoneyText(copper, short)
    copper = tonumber(copper) or 0
    if copper ~= copper or copper == math.huge or copper == -math.huge then return "?" end
    copper = math.floor(copper + 0.5)
    local sign = copper < 0 and "-" or ""
    copper = math.abs(copper)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = S.Hex(S.GOLD) .. g .. "g|r" end
    if s > 0 then parts[#parts + 1] = S.Hex(S.SILVER) .. s .. "s|r" end
    if (c > 0 and not (short and g > 0)) or #parts == 0 then parts[#parts + 1] = S.Hex(S.COPPER) .. c .. "c|r" end
    return sign .. table.concat(parts, " ")
end

-- A tile with a game icon, a small label, one value and a line under it, and an optional bar:
-- tile:Set(value, color, sub[, fraction, barColor]). For a card's key facts side by side.
function S.InfoTile(parent, label, icon)
    local t = CreateFrame("Frame", nil, parent)
    S.Box(t, S.RAISED, S.EDGE)
    t.icon = S.IconBox(t, 30, icon)
    t.icon:SetPoint("TOPLEFT", 8, -8)
    t.label = S.Text(t, 10, S.MUTED)
    t.label:SetPoint("TOPLEFT", t.icon, "TOPRIGHT", 8, 1)
    t.label:SetPoint("RIGHT", -8, 0)
    t.label:SetWordWrap(false)
    t.label:SetText(label and label:upper() or "")
    t.value = S.Text(t, 15)
    t.value:SetPoint("TOPLEFT", t.label, "BOTTOMLEFT", 0, -3)
    t.value:SetPoint("RIGHT", -8, 0)
    t.value:SetWordWrap(false)
    t.bar = S.Progress(t, 5)
    t.bar:SetPoint("TOPLEFT", t.value, "BOTTOMLEFT", 0, -4)
    t.bar:SetPoint("RIGHT", -8, 0)
    t.sub = S.Text(t, 11, S.MUTED)
    t.sub:SetPoint("TOPLEFT", t.value, "BOTTOMLEFT", 0, -4)
    t.sub:SetPoint("RIGHT", -8, 0)
    t.sub:SetWordWrap(false)
    function t:Set(value, color, sub, fraction, barColor)
        self.value:SetText(value or "")
        local c = color or S.TEXT
        self.value:SetTextColor(c[1], c[2], c[3], 1)
        self.sub:SetText(sub or "")
        self.sub:ClearAllPoints()
        if fraction then
            self.bar:Show()
            self.bar:Set(fraction, barColor)
            self.sub:SetPoint("TOPLEFT", self.bar, "BOTTOMLEFT", 0, -3)
        else
            self.bar:Hide()
            self.sub:SetPoint("TOPLEFT", self.value, "BOTTOMLEFT", 0, -4)
        end
        self.sub:SetPoint("RIGHT", -8, 0)
    end
    return t
end

-- A tile with one big number and its name under it, for counters.
S.STAT_SIZE, S.STAT_MIN = 20, 11
function S.Stat(parent, label, icon)
    local t = CreateFrame("Frame", nil, parent)
    S.Box(t, S.SURFACE, S.EDGE)
    local right = -S.INSET
    if icon then
        t.icon = S.IconBox(t, 30, icon)
        t.icon:SetPoint("RIGHT", -S.INSET, 0)
        right = -S.INSET - 38
    end
    t.value = S.Text(t, S.STAT_SIZE)
    t.value:SetPoint("TOPLEFT", S.INSET, -12)
    t.value:SetPoint("TOPRIGHT", right, -12)
    t.value:SetWordWrap(false)
    t.label = S.Text(t, 11, S.MUTED)
    t.label:SetPoint("TOPLEFT", t.value, "BOTTOMLEFT", 0, -6)
    t.label:SetPoint("TOPRIGHT", t.value, "BOTTOMRIGHT", 0, -6)
    t.label:SetWordWrap(false)
    t.label:SetText(label or "")
    -- A long value (money such as "2g 56s 76c") shrinks to fit the tile instead of ending in "...".
    function t:Fit()
        local v = self.value
        S.SetFont(v, S.STAT_SIZE)
        local avail = (tonumber(self:GetWidth()) or 0) - S.INSET + right
        if avail <= 0 then return end
        local w = tonumber((v.GetUnboundedStringWidth and v:GetUnboundedStringWidth()) or v:GetStringWidth()) or 0
        if w > avail then S.SetFont(v, math.max(S.STAT_MIN, math.floor(S.STAT_SIZE * avail / w))) end
    end
    function t:Set(value, color, label2)
        self.value:SetText(value)
        self:Fit()
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
            t:Fit()
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
-- Round shapes for rings and radial menus: the game's round portrait mask on a flat texture.
local ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- A disc of one colour; size is the diameter.
function S.Circle(parent, size, color, layer, sub)
    local t = tex(parent, layer or "BACKGROUND", sub or 0, color)
    t:SetSize(size, size)
    if t.SetMask then t:SetMask(ROUND) end
    return t
end

-- A round game icon with a ring around it (r.ring, r.fill, r.tex); r:SetIcon(path).
function S.RoundIcon(parent, size, path)
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(size, size)
    b.ring = S.Circle(b, size, S.EDGE, "BACKGROUND", 1)
    b.ring:SetPoint("CENTER")
    b.fill = S.Circle(b, size - 4, S.SURFACE, "BACKGROUND", 2)
    b.fill:SetPoint("CENTER")
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetSize(size - 12, size - 12)
    b.tex:SetPoint("CENTER")
    if b.tex.SetMask then b.tex:SetMask(ROUND) end
    function b:SetIcon(p) self.tex:SetTexture(p or "Interface\\Icons\\INV_Misc_QuestionMark") end
    function b:SetRing(c) self.ring:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end
    b:SetIcon(path)
    return b
end

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
-- The game's item quality colour (0 grey .. 5 orange) as a "|cff..." prefix.
local QUALITY_HEX = { [0] = "|cff9d9d9d", [1] = "|cffffffff", [2] = "|cff1eff00", [3] = "|cff0070dd",
                      [4] = "|cffa335ee", [5] = "|cffff8000" }
function S.QualityHex(q)
    local c = ITEM_QUALITY_COLORS and q and ITEM_QUALITY_COLORS[q]
    if c and c.hex then return c.hex end
    return QUALITY_HEX[q or 1] or QUALITY_HEX[1]
end

-- The quest log colour of a level against the player's: grey, green, yellow, orange, red.
-- The game's own rule when it has it, else the same steps by hand.
function S.LevelColor(level, mine)
    if not level then return S.MUTED end
    if GetQuestDifficultyColor and not mine then
        local c = GetQuestDifficultyColor(level)
        if c and c.r then return { c.r, c.g, c.b, 1 } end
    end
    mine = mine or (UnitLevel and UnitLevel("player")) or 60
    local d = level - mine
    if d >= 5 then return { 1, 0.1, 0.1, 1 } end
    if d >= 3 then return { 1, 0.5, 0.25, 1 } end
    if d >= -2 then return { 1, 1, 0, 1 } end
    local gray = mine <= 5 and 0 or (mine <= 39 and mine - math.floor(mine / 10) - 5 or mine - math.floor(mine / 5) - 1)
    if level > gray then return { 0.25, 0.75, 0.25, 1 } end
    return { 0.5, 0.5, 0.5, 1 }
end

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

-- A square back button with a < drawn from two lines.
local function backButton(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(28, 28)
    S.Box(b, S.CLEAR, S.EDGE)
    local lines = {}
    for i, d in ipairs({ { "LEFT", 10, 0, "TOPRIGHT", -11, -8 }, { "LEFT", 10, 0, "BOTTOMRIGHT", -11, 8 } }) do
        local l = b:CreateLine(nil, "ARTWORK")
        l:SetThickness(1.5)
        l:SetColorTexture(S.MUTED[1], S.MUTED[2], S.MUTED[3], 1)
        l:SetStartPoint(d[1], b, d[2], d[3])
        l:SetEndPoint(d[4], b, d[5], d[6])
        lines[i] = l
    end
    local function color(c) for _, l in ipairs(lines) do l:SetColorTexture(c[1], c[2], c[3], 1) end end
    b:SetScript("OnEnter", function(self) S.SetBorder(self, S.Accent()); color(S.TEXT) end)
    b:SetScript("OnLeave", function(self) S.SetBorder(self, S.EDGE); color(S.MUTED) end)
    b:SetScript("OnClick", onClick)
    return b
end
S.Back = backButton

-- Puts a window inside another frame (the hub): no shadow, no dragging, a back button instead
-- of the close button, and opts.right (the hub's own controls) on the right of the header.
-- opts: { back = fn, popOut = fn, onHide = fn, onResize = fn, right = { frames }, width, height }
local function dock(f, host, opts)
    opts = opts or {}
    f.size = f.size or { f:GetWidth(), f:GetHeight() }
    f.dockOpts = opts
    f.docked = true
    f:StopMovingOrSizing()
    f:SetParent(host)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    f:SetWidth(opts.width or f.size[1])
    f:SetHeight(opts.height or f.size[2])
    f:SetFrameStrata(host:GetFrameStrata())
    f:SetFrameLevel((tonumber(host:GetFrameLevel()) or 0) + 5)
    for _, sh in ipairs(f.shadow or {}) do sh:Hide() end
    f.close:Hide()
    if not f.back then
        f.back = backButton(f.bar, function() if f.dockOpts and f.dockOpts.back then f.dockOpts.back(f) end end)
        f.back:SetPoint("LEFT", 10, 0)
    end
    f.back:Show()
    f.icon:ClearAllPoints()
    f.icon:SetPoint("LEFT", f.back, "RIGHT", 10, 0)
    local last
    for _, b in ipairs(opts.right or {}) do
        b:SetParent(f.bar)
        b:ClearAllPoints()
        if last then b:SetPoint("RIGHT", last, "LEFT", -8, 0) else b:SetPoint("RIGHT", -12, 0) end
        b:Show()
        last = b
    end
    -- Header buttons of the window (help, size...) move left of the hub's controls.
    local first = rawget(f.close, "dockNext")
    if first and last then
        first:ClearAllPoints()
        first:SetPoint("RIGHT", last, "LEFT", -8, 0)
    end
    if not f.dockHooked then
        f.dockHooked = true
        f:HookScript("OnHide", function(self)
            if self.docked and self.dockOpts and self.dockOpts.onHide then self.dockOpts.onHide(self) end
        end)
    end
    f:Show()
end

-- Takes a window out of the hub again: back to its own size in the middle of the screen. It
-- stays hidden; the caller shows it when it should stand alone.
local function undock(f)
    if not f.docked then return end
    local opts = f.dockOpts or {}
    f.docked = false
    f.dockOpts = false
    f:Hide()
    for _, b in ipairs(opts.right or {}) do b:Hide() end
    f:SetParent(UIParent)
    f:ClearAllPoints()
    f:SetPoint("CENTER")
    f:SetWidth(f.size[1])
    f:SetHeight(f.size[2])
    f:SetFrameStrata(f.strata or "DIALOG")
    for _, sh in ipairs(f.shadow or {}) do sh:Show() end
    if f.back then f.back:Hide() end
    f.close:Show()
    f.icon:ClearAllPoints()
    f.icon:SetPoint("LEFT", 14, 0)
    local first = rawget(f.close, "dockNext")
    if first then
        first:ClearAllPoints()
        first:SetPoint("RIGHT", f.close, "LEFT", -6, 0)
    end
end

-- A movable window: a header with the addon icon, the title, a grey subtitle (the slash
-- command) and a close button. frame.body is the padded area under the header; S.Footer adds
-- a bar for the buttons at the bottom. opts: { sub = "/gmc", icon = path, strata, fullTitle }.
function S.Window(name, title, width, height, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(width, height)
    f:SetPoint("CENTER")
    f.strata = opts.strata or "DIALOG"
    f:SetFrameStrata(f.strata)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    -- A soft shadow: a few dark rings outside the edge.
    f.shadow = {}
    for i = 1, 4 do
        local sh = tex(f, "BACKGROUND", -8, { 0, 0, 0, 0.16 - i * 0.03 })
        sh:SetPoint("TOPLEFT", -i, i)
        sh:SetPoint("BOTTOMRIGHT", i, -i - 1)
        f.shadow[i] = sh
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
    bar:SetScript("OnDragStart", function() if not f.docked then f:StartMoving() end end)
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
        if self.headerRight == self.close then self.close.dockNext = b end
        self.headerRight = b
        return b
    end

    f.body = CreateFrame("Frame", nil, f)
    f.body:SetPoint("TOPLEFT", S.PAD, -(S.HEADER_H + S.PAD))
    f.body:SetPoint("BOTTOMRIGHT", -S.PAD, S.PAD)
    f.inner = { width - 2 * S.PAD, height - S.HEADER_H - 2 * S.PAD }
    f.size = { width, height }
    f.docked, f.dockOpts, f.dockHooked, f.back, f.footer = false, false, false, false, false
    f.Dock, f.Undock = dock, undock
    f:Hide()
    return f
end

-- Sets the height of a window. A window that sits in the hub keeps the hub's height and only
-- remembers its own for when it stands alone again.
function S.SetWindowHeight(f, h)
    f.size = f.size or { f:GetWidth(), h }
    f.size[2] = h
    if f.docked then
        if f.dockOpts and f.dockOpts.onResize then f.dockOpts.onResize(f) end
        return
    end
    f:SetHeight(h)
end

-- Sets the window height so the body is exactly h pixels high.
function S.FitWindow(f, h)
    S.SetWindowHeight(f, S.HEADER_H + 2 * S.PAD + h + (f.footer and S.FOOTER_H or 0))
end

-- A slash command opens the window alone. When the window sits in the hub, the command takes
-- it out of the hub instead of closing it.
function S.ToggleWindow(f)
    if f.docked and f.dockOpts and f.dockOpts.popOut then
        f.dockOpts.popOut(f)
    else
        f:SetShown(not f:IsShown())
    end
    return f:IsShown()
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
    -- A page that hides the footer gets its height back (IsShown, not visibility: the window may be hidden).
    local function fit(self)
        f.body:SetPoint("BOTTOMRIGHT", -S.PAD, (self:IsShown() and S.FOOTER_H or 0) + S.PAD)
    end
    ft:HookScript("OnShow", fit)
    ft:HookScript("OnHide", fit)
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
    sf.step = rowHeight + gap
    sf.onResize = function(self, w) if w and w > 1 then self.child:SetWidth(w) end end
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

-- HUD: what sits on the game screen outside a window ----------------------------------------
-- One look for every popup and overlay (Gulli HUD): game icons framed like the action bars,
-- a coloured ring for their state, translucent panels, one card for notices (S.Toast) and one
-- way to move things (S.Mover, shown by /gulli move).

S.HUD_BG = { 0.055, 0.059, 0.071, 0.88 }
S.TOAST_W, S.TOAST_H = 360, 64

-- Edges of one width and colour around f, inside (inset >= 0) or outside (inset < 0) it.
local function frameLines(f, layer, sub, color, width, inset)
    local t = {}
    local o = inset or 0
    for i, p in ipairs({ { "TOPLEFT", "TOPRIGHT", o, -o, -o, -o, "h" }, { "BOTTOMLEFT", "BOTTOMRIGHT", o, o, -o, o, "h" },
                         { "TOPLEFT", "BOTTOMLEFT", o, -o, o, o, "v" }, { "TOPRIGHT", "BOTTOMRIGHT", -o, -o, -o, o, "v" } }) do
        local e = tex(f, layer, sub, color)
        e:SetPoint(p[1], p[3], p[4])
        e:SetPoint(p[2], p[5], p[6])
        if p[7] == "h" then e:SetHeight(width) else e:SetWidth(width) end
        t[i] = e
    end
    return t
end

local function colorLines(lines, c, a)
    for _, e in ipairs(lines) do e:SetVertexColor(c[1], c[2], c[3], a or c[4] or 1) end
end

local function showLines(lines, on)
    for _, e in ipairs(lines) do e:SetShown(on and true or false) end
end

-- A translucent HUD panel: black edge, a faint inner line and a soft shadow.
function S.HudPanel(f)
    S.Box(f, S.HUD_BG, S.BORDER)
    f.inner = frameLines(f, "BORDER", 6, { 1, 1, 1, 0.06 }, 1, 1)
    f.shadow = {}
    for i = 1, 3 do
        local sh = tex(f, "BACKGROUND", -8, { 0, 0, 0, 0.22 - i * 0.06 })
        sh:SetPoint("TOPLEFT", -i, i)
        sh:SetPoint("BOTTOMRIGHT", i, -i - 1)
        f.shadow[i] = sh
    end
    return f
end

-- "SHIFT-F" -> "sF", "BUTTON4" -> "M4": the short key text in the corner of an icon.
function S.ShortKey(key)
    if not key or key == "" then return "" end
    key = tostring(key):upper()
    key = key:gsub("SHIFT%-", "s"):gsub("CTRL%-", "c"):gsub("ALT%-", "a"):gsub("META%-", "m")
    key = key:gsub("MOUSEWHEELUP", "WU"):gsub("MOUSEWHEELDOWN", "WD"):gsub("BUTTON", "M")
    key = key:gsub("NUMPAD", "N"):gsub("SPACE", "Sp")
    return key
end

local STATE = { need = "BAD", soon = "WARN", ok = "GOOD" }

-- A game icon on the screen: cropped like the action bars, a black 1 pixel frame, a coloured
-- ring for its state (need = red and pulsing, soon = yellow, ok = green), the key in the top
-- left corner, a count in the bottom right and a big text in the middle (time left).
-- b is any frame, secure buttons too; the look is only textures and texts on it.
-- b:SetIcon(path), b:SetState(state), b:SetDone(on), b:SetKey(key), b:SetCount(s), b:SetMid(s, color).
function S.HudIcon(b, size)
    size = size or 40
    b:SetSize(size, size)
    S.Box(b, { 0, 0, 0, 1 }, S.BORDER)
    b.outline = frameLines(b, "BACKGROUND", -6, { 1, 1, 1, 0.10 }, 1, -1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.ring = frameLines(b, "OVERLAY", 6, S.BAD, size >= 32 and 2 or 1, 1)
    showLines(b.ring, false)
    b.glow = frameLines(b, "BACKGROUND", -7, S.BAD, 4, -2)
    showLines(b.glow, false)
    b.key = S.Text(b, math.max(9, math.floor(size * 0.22)), S.TEXT, "OUTLINE")
    b.key:SetPoint("TOPLEFT", 3, -3)
    b.count = S.Text(b, math.max(10, math.floor(size * 0.27)), S.TEXT, "OUTLINE")
    b.count:SetPoint("BOTTOMRIGHT", -2, 3)
    b.mid = S.Text(b, math.max(11, math.floor(size * 0.32)), S.WARN, "OUTLINE")
    b.mid:SetPoint("CENTER", 0, 0)
    b.mid:SetJustifyH("CENTER")
    -- The pulse runs on a child frame, so a secure button keeps its own scripts.
    local pulser = CreateFrame("Frame", nil, b)
    pulser:Hide()
    local t = 0
    pulser:SetScript("OnUpdate", function(_, dt)
        t = t + (dt or 0)
        local a = 0.25 + 0.35 * (0.5 + 0.5 * math.sin(t * 5))
        for _, e in ipairs(b.glow) do e:SetAlpha(a) end
    end)
    b.pulser = pulser
    function b:SetIcon(p) self.icon:SetTexture(p or "Interface\\Icons\\INV_Misc_QuestionMark") end
    function b:SetState(st)
        self.state = st
        local c = st and S[STATE[st] or ""]
        showLines(self.ring, c ~= nil)
        if c then colorLines(self.ring, c) end
        local pulse = st == "need"
        showLines(self.glow, pulse)
        if pulse then colorLines(self.glow, S.BAD, 0.5) end
        self.pulser:SetShown(pulse)
    end
    function b:SetDone(on)
        self.icon:SetDesaturated(on and true or false)
        self.icon:SetVertexColor(on and 0.6 or 1, on and 0.6 or 1, on and 0.6 or 1, 1)
    end
    function b:SetKey(k) self.key:SetText(S.ShortKey(k)) end
    function b:SetCount(s) self.count:SetText(s or "") end
    function b:SetMid(s, c)
        c = c or S.WARN
        self.mid:SetText(s or "")
        self.mid:SetTextColor(c[1], c[2], c[3], 1)
    end
    return b
end

-- What an icon is about, in a panel next to it: a white line and a grey one.
-- cap:Set(title, sub) sizes it to the longer line.
function S.HudCaption(parent, height)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(150, height or 40)
    S.HudPanel(f)
    f.title = S.Text(f, 13)
    f.title:SetPoint("TOPLEFT", 10, -((height or 40) / 2 - 13))
    f.title:SetWordWrap(false)
    f.sub = S.Text(f, 11, S.MUTED)
    f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
    f.sub:SetWordWrap(false)
    function f:Set(title, sub)
        self.title:SetText(title or "")
        self.sub:SetText(sub or "")
        self.sub:SetShown(sub ~= nil and sub ~= "")
        if sub == nil or sub == "" then
            self.title:SetPoint("TOPLEFT", 10, -((self:GetHeight() or 40) / 2 - 7))
        else
            self.title:SetPoint("TOPLEFT", 10, -((self:GetHeight() or 40) / 2 - 13))
        end
        self:SetWidth(math.max(120, math.floor(math.max(strw(self.title), strw(self.sub)) + 22)))
    end
    return f
end

-- A small counter on the screen: an icon, a value, up to 10 marks and a grey note, such as
-- "3/5 [marks] 18 m". chip:Set(icon, value, color, filled, total, note).
function S.Chip(parent, name)
    local f = CreateFrame("Button", name, parent or UIParent)
    f:SetSize(120, 30)
    S.HudPanel(f)
    f.ico = S.IconBox(f, 24)
    f.ico:SetPoint("LEFT", 3, 0)
    f.value = S.Text(f, 14, S.TEXT, "OUTLINE")
    f.value:SetPoint("LEFT", f.ico, "RIGHT", 8, 0)
    f.marks = {}
    f.note = S.Text(f, 12, S.MUTED)
    f.note:SetWordWrap(false)
    function f:Set(icon, value, color, filled, total, note)
        self.ico:SetIcon(icon)
        local c = color or S.TEXT
        self.value:SetText(value or "")
        self.value:SetTextColor(c[1], c[2], c[3], 1)
        total = math.min(total or 0, 10)
        local x = 3 + 24 + 8 + strw(self.value) + 8
        for i = 1, math.max(total, #self.marks) do
            local m = self.marks[i]
            if not m and i <= total then
                m = tex(self, "ARTWORK", 0, S.LINE)
                m:SetSize(8, 10)
                self.marks[i] = m
            end
            if m then
                m:SetShown(i <= total)
                m:ClearAllPoints()
                m:SetPoint("LEFT", x + (i - 1) * 10, 0)
                local on = i <= (filled or 0)
                local mc = on and (color or S.Accent()) or { 1, 1, 1, 0.12 }
                m:SetVertexColor(mc[1], mc[2], mc[3], mc[4] or 1)
            end
        end
        if total > 0 then x = x + total * 10 + 6 end
        self.note:ClearAllPoints()
        self.note:SetPoint("LEFT", x, 0)
        self.note:SetText(note or "")
        self:SetWidth(math.floor(x + ((note and note ~= "") and (strw(self.note) + 10) or 4)))
    end
    return f
end

-- A small list on the screen: a header (icon, title, a grey note on the right) and rows of a
-- coloured tag, a text and a grey note. list:SetRows({ { tag, tagColor, text, right } }, empty).
function S.HudList(name, width, rows, parent)
    local f = CreateFrame("Button", name, parent or UIParent)
    f:SetSize(width or 330, 26 + (rows or 3) * 22)
    S.HudPanel(f)
    f.ico = f:CreateTexture(nil, "ARTWORK")
    f.ico:SetSize(16, 16)
    f.ico:SetPoint("TOPLEFT", 8, -5)
    f.ico:SetTexture("Interface\\AddOns\\" .. tostring(addon) .. "\\icon")
    f.title = S.Text(f, 12)
    f.title:SetPoint("LEFT", f.ico, "RIGHT", 6, 0)
    f.right = S.Text(f, 11, S.FAINT)
    f.right:SetPoint("TOPRIGHT", -8, -7)
    f.right:SetJustifyH("RIGHT")
    local line = S.Divider(f)
    line:SetPoint("TOPLEFT", 1, -26)
    line:SetPoint("TOPRIGHT", -1, -26)
    line:SetHeight(1)
    f.rows = {}
    for i = 1, rows or 3 do
        local r = CreateFrame("Frame", nil, f)
        r:SetHeight(22)
        r:SetPoint("TOPLEFT", 1, -26 - (i - 1) * 22)
        r:SetPoint("TOPRIGHT", -1, -26 - (i - 1) * 22)
        r.tag = S.Badge(r)
        r.tag:SetPoint("LEFT", 7, 0)
        r.text = S.Text(r, 11)
        r.text:SetWordWrap(false)
        r.right = S.Text(r, 10, S.FAINT)
        r.right:SetPoint("RIGHT", -7, 0)
        r.right:SetJustifyH("RIGHT")
        f.rows[i] = r
    end
    function f:SetRows(list, empty)
        for i, r in ipairs(self.rows) do
            local it = list[i]
            r.text:ClearAllPoints()
            if it then
                r.tag:Set(it.tag, it.tagColor)
                r.right:SetText(it.right or "")
                if it.tag and it.tag ~= "" then r.text:SetPoint("LEFT", r.tag, "RIGHT", 6, 0)
                else r.text:SetPoint("LEFT", 8, 0) end
                r.text:SetPoint("RIGHT", r.right, "LEFT", -6, 0)
                r.text:SetText(it.text or "")
                r.text:SetTextColor(S.TEXT[1], S.TEXT[2], S.TEXT[3], 1)
                r:Show()
            elseif i == 1 and empty then
                r.tag:Set(nil)
                r.right:SetText("")
                r.text:SetPoint("LEFT", 8, 0)
                r.text:SetPoint("RIGHT", -8, 0)
                r.text:SetText(empty)
                r.text:SetTextColor(S.FAINT[1], S.FAINT[2], S.FAINT[3], 1)
                r:Show()
            else
                r:Hide()
            end
        end
    end
    return f
end

-- Notices -----------------------------------------------------------------------------------

local KIND = { bad = "BAD", warn = "WARN", good = "GOOD" }

-- A notice card: a coloured stripe on the left (o.kind: bad, warn, good, or the accent), an
-- icon, a title, a grey line, buttons on the right, a close button, and a thin line at the
-- bottom that runs out when the card hides by itself.
-- card:Set{ icon, portrait (a unit), title, text, kind, buttons = { { text, onClick, primary } },
--          seconds, reserve (pixels kept free on the right for a frame of the caller's own) }
function S.ToastFrame(name, parent)
    local t = CreateFrame("Frame", name, parent or UIParent)
    t:SetSize(S.TOAST_W, S.TOAST_H)
    t:SetFrameStrata("DIALOG")
    t:SetClampedToScreen(true)
    t:EnableMouse(true)
    S.HudPanel(t)
    t.stripe = tex(t, "ARTWORK", 1, S.Accent())
    t.stripe:SetPoint("TOPLEFT", 1, -1)
    t.stripe:SetPoint("BOTTOMLEFT", 1, 1)
    t.stripe:SetWidth(3)
    t.ico = S.IconBox(t, 40)
    t.ico:SetPoint("LEFT", 13, 0)
    t.title = S.Text(t, 13)
    t.title:SetWordWrap(false)
    t.text = S.Note(t, 11)
    t.text:SetMaxLines(2)
    t.close = closeButton(t, function() t:Dismiss() end)
    t.close:SetPoint("TOPRIGHT", 0, 0)
    t.track = tex(t, "ARTWORK", 0, { 1, 1, 1, 0.06 })
    t.track:SetPoint("BOTTOMLEFT", 4, 1)
    t.track:SetPoint("BOTTOMRIGHT", -1, 1)
    t.track:SetHeight(2)
    t.timer = tex(t, "ARTWORK", 1, S.Accent())
    t.timer:SetPoint("BOTTOMLEFT", 4, 1)
    t.timer:SetHeight(2)
    t.buttons = {}
    t:SetScript("OnUpdate", function(self, dt)
        if not self.left then return end
        self.left = self.left - (dt or 0)
        local w = (self:GetWidth() or S.TOAST_W) - 5
        self.timer:SetWidth(math.max(1, w * math.max(0, self.left) / self.seconds))
        if self.left <= 0 then self:Dismiss() end
    end)
    function t:Dismiss()
        self.left = nil
        self:Hide()
        if self.restack then self.restack() end
        if self.onClose then self.onClose(self) end
    end
    function t:Set(o)
        local c = o.kind and S[KIND[o.kind] or ""] or S.Accent()
        self.stripe:SetVertexColor(c[1], c[2], c[3], 1)
        self.timer:SetVertexColor(c[1], c[2], c[3], 0.8)
        if o.portrait and SetPortraitTexture and UnitExists and UnitExists(o.portrait) then
            SetPortraitTexture(self.ico.tex, o.portrait)
            self.ico.tex:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        else
            self.ico.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            self.ico:SetIcon(o.icon)
        end
        self.title:SetText(o.title or "")
        self.text:SetText(o.text or "")
        self.onClose = o.onClose
        local right = -32 - (o.reserve or 0)
        local last
        for i = 1, math.max(#(o.buttons or {}), #self.buttons) do
            local spec = (o.buttons or {})[i]
            local b = self.buttons[i]
            if spec then
                if not b then
                    b = S.Button(self, 60, 28)
                    self.buttons[i] = b
                end
                b.kind = spec.primary and "primary" or "normal"
                paint(b)
                if not spec.primary then b.text:SetTextColor(S.TEXT[1], S.TEXT[2], S.TEXT[3], 1) end
                b:SetText(spec.text)
                b:SetWidth(math.max(56, math.floor(strw(b.text) + 22)))
                b:ClearAllPoints()
                if last then b:SetPoint("RIGHT", last, "LEFT", -5, 0) else b:SetPoint("RIGHT", right, 0) end
                b:SetScript("OnClick", function()
                    if spec.onClick then spec.onClick(self) end
                    if not spec.keep then self:Dismiss() end
                end)
                b:Show()
                last = b
            elseif b then
                b:Hide()
            end
        end
        self.title:ClearAllPoints()
        -- Without a second line the title sits in the middle of the icon.
        self.title:SetPoint("TOPLEFT", self.ico, "TOPRIGHT", 10, (o.text and o.text ~= "") and -3 or -13)
        self.title:SetPoint("RIGHT", last or self.close, "LEFT", last and -8 or (-4 - (o.reserve or 0)), 0)
        self.text:ClearAllPoints()
        self.text:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -3)
        self.text:SetPoint("RIGHT", self.title, "RIGHT", 0, 0)
        self.seconds = o.seconds
        self.left = (o.seconds or 0) > 0 and o.seconds or nil
        self.track:SetShown(self.left ~= nil)
        self.timer:SetShown(self.left ~= nil)
        if self.left then self.timer:SetWidth((self:GetWidth() or S.TOAST_W) - 5) end
        self:Show()
    end
    t:Hide()
    return t
end

-- Notices of every Gulli addon share one stack at the top of the screen, so they never cover
-- each other. Each copy of this file uses the same global list.
local function stack()
    GulliHUD = GulliHUD or {}
    GulliHUD.toasts = GulliHUD.toasts or {}
    return GulliHUD
end

local function restack()
    local H = stack()
    local y = -150
    local keep = {}
    for _, t in ipairs(H.toasts) do
        if t:IsShown() then
            keep[#keep + 1] = t
            t:ClearAllPoints()
            t:SetPoint("TOP", UIParent, "TOP", 0, y)
            y = y - (t:GetHeight() or S.TOAST_H) - 8
        end
    end
    H.toasts = keep
end

-- Shows a notice in the shared stack; the same key replaces its card. Returns the card.
-- o as in ToastFrame:Set, plus key.
function S.Toast(o)
    local H = stack()
    H.byKey = H.byKey or {}
    local key = tostring(addon) .. ":" .. tostring(o.key or "")
    local t = H.byKey[key]
    if not t then
        t = S.ToastFrame(nil, UIParent)
        H.byKey[key] = t
        t.restack = restack
        t:HookScript("OnHide", function() restack() end)
    end
    local onClose = o.onClose
    t:Set(o)
    t.onClose = onClose
    local found = false
    for _, x in ipairs(H.toasts) do if x == t then found = true end end
    if not found then table.insert(H.toasts, 1, t) end
    restack()
    return t
end

-- Moving ------------------------------------------------------------------------------------

-- Makes a frame placeable for /gulli move: f:SetMoving(true) puts an accent frame with the
-- name over it, and dragging it moves f; a right click puts it back (opts.reset).
-- opts: { label, save = function(point, relPoint, x, y), reset = function() }.
-- Nothing moves in combat.
function S.Mover(f, opts)
    opts = opts or {}
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    local m = CreateFrame("Button", nil, f)
    m:SetPoint("TOPLEFT", -4, 4)
    m:SetPoint("BOTTOMRIGHT", 4, -4)
    m:SetFrameLevel((tonumber((f:GetFrameLevel())) or 0) + 20)
    local a = S.Accent()
    S.Box(m, { a[1], a[2], a[3], 0.12 }, a)
    m.name = CreateFrame("Frame", nil, m)
    m.name:SetPoint("BOTTOMLEFT", m, "TOPLEFT", 0, 2)
    m.name:SetHeight(18)
    S.Box(m.name, a, a)
    m.name.text = S.Text(m.name, 10, { 0.05, 0.05, 0.06, 1 })
    m.name.text:SetShadowColor(0, 0, 0, 0)
    m.name.text:SetPoint("LEFT", 5, 0)
    m.name.text:SetText(shortTitle(opts.label))
    m.name:SetWidth(math.floor(strw(m.name.text) + 10))
    m:RegisterForDrag("LeftButton")
    m:RegisterForClicks("RightButtonUp")
    m:SetScript("OnDragStart", function()
        if not (InCombatLockdown and InCombatLockdown()) then f:StartMoving() end
    end)
    m:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local p, _, rp, x, y = f:GetPoint()
        if opts.save then opts.save(p, rp, x, y) end
    end)
    m:SetScript("OnClick", function() if opts.reset then opts.reset() end end)
    m:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(opts.label or "")
        if opts.hint then GameTooltip:AddLine(opts.hint, S.MUTED[1], S.MUTED[2], S.MUTED[3], true) end
        GameTooltip:Show()
    end)
    m:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    m:Hide()
    f.mover = m
    function f:SetMoving(on)
        self.mover:SetShown(on and true or false)
    end
    return m
end
