-- A fake WoW frame system that keeps anchors, sizes, textures and texts, resolves the layout
-- like the game does, and writes it out as HTML. It lets us look at a window without the game.
-- It knows only what our addons call; an unknown method does nothing.

local R = {}

local UI_W, UI_H = 1366, 768
local gen = 0 -- bumped on every change that can move something, so cached rects are dropped

local Region = {}
local regionMeta = {
    __index = function(t, k)
        local m = Region[k]
        if m then return m end
        if type(k) == "string" and k:match("^%u") then return function() end end
        return nil
    end,
}

local all = {}
local named = {}

local function new(kind, parent, name)
    local r = setmetatable({}, regionMeta)
    r.__kind, r.__parent, r.__name = kind, parent, name
    r.__points, r.__shown, r.__alpha = {}, true, 1
    r.__regions, r.__children = {}, {}
    r._events = {}
    if parent then
        if kind == "Texture" or kind == "FontString" or kind == "Line" then
            parent.__regions[#parent.__regions + 1] = r
        else
            parent.__children[#parent.__children + 1] = r
        end
    end
    if name then named[name] = r; _G[name] = r end
    all[#all + 1] = r
    gen = gen + 1
    return r
end

local function changed() gen = gen + 1 end

-- Points ---------------------------------------------------------------------------------------

function Region:SetPoint(point, a, b, c, d)
    local rel, relPoint, x, y = self.__parent, point, 0, 0
    if type(a) == "number" then x, y = a, b or 0
    elseif a ~= nil then
        rel = type(a) == "string" and named[a] or a
        if type(b) == "string" then relPoint, x, y = b, c or 0, d or 0
        elseif type(b) == "number" then x, y = b, c or 0 end
    end
    for i, p in ipairs(self.__points) do
        if p[1] == point then table.remove(self.__points, i) break end
    end
    self.__points[#self.__points + 1] = { point, rel or self.__parent, relPoint, x or 0, y or 0 }
    changed()
end

function Region:SetAllPoints(rel)
    self.__points = {}
    self:SetPoint("TOPLEFT", rel or self.__parent, "TOPLEFT", 0, 0)
    self:SetPoint("BOTTOMRIGHT", rel or self.__parent, "BOTTOMRIGHT", 0, 0)
end

function Region:ClearAllPoints() self.__points = {}; changed() end
function Region:GetNumPoints() return #self.__points end
function Region:GetPoint(i)
    local p = self.__points[i or 1]
    if p then return p[1], p[2], p[3], p[4], p[5] end
end

function Region:SetSize(w, h) self.__w, self.__h = w, h; changed() end
function Region:SetWidth(w) self.__w = w; changed() end
function Region:SetHeight(h) self.__h = h; changed() end
function Region:SetScale(s) self.__scale = s; changed() end
function Region:GetScale() return self.__scale or 1 end
function Region:GetEffectiveScale() return self.__scale or 1 end

-- Text width in the game's font, close enough for layout: Friz Quadrata is about half an em.
local function plain(s)
    s = tostring(s or "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "WW"):gsub("|n", "\n")
        :gsub("|H.-|h", ""):gsub("|h", "")
    return s
end
local function ulen(s) local _, n = s:gsub("[^\128-\191]", ""); return n end
local function textWidth(s, size)
    local w = 0
    for line in (plain(s) .. "\n"):gmatch("(.-)\n") do
        w = math.max(w, ulen(line) * size * 0.55)
    end
    return math.floor(w + 0.5)
end
R.textWidth = textWidth

local function anchorXY(rect, point)
    local x, y
    if point:find("LEFT") then x = rect.l elseif point:find("RIGHT") then x = rect.r else x = (rect.l + rect.r) / 2 end
    if point:find("TOP") then y = rect.t elseif point:find("BOTTOM") then y = rect.b else y = (rect.t + rect.b) / 2 end
    return x, y
end

local function natural(r)
    if r.__kind == "FontString" and r.__text and r.__text ~= "" then
        local size = r.__fontSize or 12
        local lines = 1
        for _ in plain(r.__text):gmatch("\n") do lines = lines + 1 end
        return textWidth(r.__text, size), lines * (size + 2)
    end
    return 0, 0
end

local resolving = {}

-- Returns { l, r, t, b } in UIParent coordinates (y grows upward).
function R.Rect(r)
    if r == R.UIParent then return { l = 0, r = UI_W, t = UI_H, b = 0 } end
    if r.__rect and r.__gen == gen then return r.__rect end
    if resolving[r] then return { l = 0, r = 0, t = 0, b = 0 } end
    resolving[r] = true
    local L, Rr, CX, T, B, CY
    if r.__scrollParent and #r.__points == 0 then
        local p = R.Rect(r.__scrollParent)
        L, T = p.l, p.t + (r.__scrollParent.__vscroll or 0)
    end
    for _, p in ipairs(r.__points) do
        local rel = p[2] or R.UIParent
        local x, y = anchorXY(R.Rect(rel), p[3])
        x, y = x + p[4], y + p[5]
        local pt = p[1]
        if pt:find("LEFT") then L = x elseif pt:find("RIGHT") then Rr = x elseif CX == nil then CX = x end
        if pt:find("TOP") then T = y elseif pt:find("BOTTOM") then B = y elseif CY == nil then CY = y end
    end
    local nw, nh = natural(r)
    local w, h = r.__w or nw, r.__h or nh
    if r.__kind == "FontString" and r.__w == nil and L and Rr then w = Rr - L end
    if r.__kind == "FontString" and r.__wrap ~= false and r.__h == nil and r.__text and not (T and B) then
        local size, lines = r.__fontSize or 12, 0
        for line in (plain(r.__text) .. "\n"):gmatch("(.-)\n") do
            lines = lines + math.max(1, math.ceil(textWidth(line, size) / math.max(w, 1)))
        end
        if r.__maxLines and r.__maxLines > 0 then lines = math.min(lines, r.__maxLines) end
        h = lines * (size + 2)
    end
    local l, rr
    if L and Rr then l, rr = L, Rr
    elseif L then l, rr = L, L + w
    elseif Rr then l, rr = Rr - w, Rr
    elseif CX then l, rr = CX - w / 2, CX + w / 2
    else l, rr = 0, w end
    local t, b
    if T and B then t, b = T, B
    elseif T then t, b = T, T - h
    elseif B then t, b = B + h, B
    elseif CY then t, b = CY + h / 2, CY - h / 2
    else t, b = h, 0 end
    resolving[r] = nil
    r.__bound = (L ~= nil and Rr ~= nil) or r.__w ~= nil
    r.__rect, r.__gen = { l = l, r = rr, t = t, b = b }, gen
    return r.__rect
end

function Region:GetWidth() local c = R.Rect(self); return c.r - c.l end
function Region:GetHeight() local c = R.Rect(self); return c.t - c.b end
function Region:GetSize() return self:GetWidth(), self:GetHeight() end
function Region:GetLeft() return R.Rect(self).l end
function Region:GetRight() return R.Rect(self).r end
function Region:GetTop() return R.Rect(self).t end
function Region:GetBottom() return R.Rect(self).b end
function Region:GetCenter() local c = R.Rect(self); return (c.l + c.r) / 2, (c.t + c.b) / 2 end

-- Visibility -----------------------------------------------------------------------------------

function Region:Hide()
    local was = self.__shown
    self.__shown = false
    if was and self._OnHide then self._OnHide(self) end
end
function Region:Show()
    local was = self.__shown
    self.__shown = true
    if not was and self._OnShow and self:IsVisible() then self._OnShow(self) end
end
function Region:SetShown(v) if v then self:Show() else self:Hide() end end
function Region:IsShown() return self.__shown end
function Region:IsVisible()
    local r = self
    while r do
        if not r.__shown then return false end
        r = r.__parent
    end
    return true
end
function Region:SetAlpha(a) self.__alpha = a end
function Region:GetAlpha() return self.__alpha end
function Region:GetParent() return self.__parent end
function Region:SetParent(p)
    local old = self.__parent
    if old then
        local list = (self.__kind == "Texture" or self.__kind == "FontString") and old.__regions or old.__children
        for i, x in ipairs(list) do if x == self then table.remove(list, i) break end end
    end
    self.__parent = p
    if p then p.__children[#p.__children + 1] = self end
    changed()
end
function Region:GetName() return self.__name end
function Region:GetObjectType() return self.__kind end
function Region:SetFrameStrata(s) self.__strata = s end
function Region:SetFrameLevel(l) self.__level = l end
function Region:GetFrameLevel() return self.__level or 1 end

-- Scripts and events ---------------------------------------------------------------------------

function Region:SetScript(name, fn) rawset(self, "_" .. name, fn) end
function Region:GetScript(name) return rawget(self, "_" .. name) end
function Region:HookScript(name, fn)
    local old = rawget(self, "_" .. name)
    rawset(self, "_" .. name, old and function(...) old(...); fn(...) end or fn)
end
function Region:RegisterEvent(e) self._events[e] = true end
function Region:UnregisterEvent(e) self._events[e] = nil end
function Region:RegisterUnitEvent(e) self._events[e] = true end
function Region:Click(button)
    if self.__enabled == false then return end
    if self._PreClick then self._PreClick(self, button or "LeftButton") end
    if self._OnClick then self._OnClick(self, button or "LeftButton", false) end
end
function Region:SetEnabled(v)
    v = v and true or false
    if self.__enabled ~= v then
        self.__enabled = v
        local s = rawget(self, v and "_OnEnable" or "_OnDisable")
        if s then s(self) end
    end
end
function Region:Enable() self:SetEnabled(true) end
function Region:Disable() self:SetEnabled(false) end
function Region:IsEnabled() return self.__enabled ~= false end
function Region:SetAttribute(k, v) self.__attr = self.__attr or {}; self.__attr[k] = v end
function Region:GetAttribute(k) return self.__attr and self.__attr[k] end

-- Frames ---------------------------------------------------------------------------------------

function Region:CreateTexture(name, layer, _, sub)
    local t = new("Texture", self, name)
    t.__layer, t.__sub = layer or "ARTWORK", sub or 0
    return t
end
function Region:CreateLine(name, layer)
    local t = new("Line", self, name)
    t.__layer, t.__sub = layer or "ARTWORK", 0
    return t
end
function Region:CreateFontString(name, layer)
    local t = new("FontString", self, name)
    t.__layer, t.__sub = layer or "ARTWORK", 0
    return t
end
function Region:SetDrawLayer(layer, sub) self.__layer, self.__sub = layer, sub or 0 end

function Region:SetScrollChild(c)
    self.__scrollChild = c
    c.__scrollParent = self
    changed()
end
function Region:GetScrollChild() return self.__scrollChild end
function Region:SetVerticalScroll(v) self.__vscroll = v; changed() end
function Region:GetVerticalScroll() return self.__vscroll or 0 end

function Region:SetMinMaxValues(a, b) self.__min, self.__max = a, b end
function Region:GetMinMaxValues() return self.__min or 0, self.__max or 0 end
function Region:SetValue(v)
    v = math.max(self.__min or 0, math.min(self.__max or v, v))
    self.__value = v
    if self._OnValueChanged then self._OnValueChanged(self, v) end
end
function Region:GetValue() return self.__value or 0 end
function Region:SetThumbTexture(t) self.__thumb = t end
function Region:SetChecked(v) self.__checked = v end
function Region:GetChecked() return self.__checked end

-- Textures -------------------------------------------------------------------------------------

function Region:SetTexture(path)
    self.__tex = path
    if type(path) == "number" then self.__tex = "file" .. path end
end
function Region:SetAtlas(a) self.__tex = "atlas:" .. tostring(a) end
function Region:GetTexture() return self.__tex end
function Region:SetColorTexture(r, g, b, a)
    self.__tex = "Interface\\Buttons\\WHITE8X8"
    self.__color = { r, g, b, a or 1 }
end
function Region:SetVertexColor(r, g, b, a) self.__color = { r, g, b, a or 1 } end
function Region:GetVertexColor() local c = self.__color or { 1, 1, 1, 1 }; return c[1], c[2], c[3], c[4] end
function Region:SetDesaturated(v) self.__desat = v end
function Region:SetTexCoord(a) self.__crop = a and a > 0 end
function Region:SetGradient() end
function Region:SetStartPoint(point, rel, x, y) self.__start = { point, rel or self.__parent, x or 0, y or 0 } end
function Region:SetEndPoint(point, rel, x, y) self.__end = { point, rel or self.__parent, x or 0, y or 0 } end
function Region:SetThickness(t) self.__thick = t end

-- Text -----------------------------------------------------------------------------------------

function Region:SetFont(_, size, flags) self.__fontSize, self.__flags = size, flags; changed(); return true end
function Region:GetFont() return "font", self.__fontSize or 12, self.__flags end
function Region:SetFontObject(o)
    if type(o) == "table" and o.__fontSize then self.__fontSize = o.__fontSize end
    self.__fontSize = self.__fontSize or 12
end
function Region:SetText(s)
    self.__text = s ~= nil and tostring(s) or nil
    changed()
    if self.__kind == "EditBox" and self._OnTextChanged then self._OnTextChanged(self, false) end
end
function Region:SetFormattedText(f, ...) self:SetText(string.format(f, ...)) end
function Region:GetText() return self.__text end
function Region:GetNumber() return tonumber(self.__text) or 0 end
function Region:SetShadowColor(_, _, _, a) self.__shadow = (a or 1) > 0 end
function Region:SetTextColor(r, g, b, a) self.__tcolor = { r, g, b, a or 1 } end
function Region:GetTextColor() local c = self.__tcolor or { 1, 0.82, 0, 1 }; return c[1], c[2], c[3], c[4] end
function Region:SetJustifyH(j) self.__jh = j end
function Region:SetJustifyV(j) self.__jv = j end
function Region:SetWordWrap(v) self.__wrap = v; changed() end
function Region:SetNonSpaceWrap() end
function Region:SetMaxLines(n) self.__maxLines = n end
function Region:SetSpacing() end
function Region:GetStringWidth() return textWidth(self.__text or "", self.__fontSize or 12) end
function Region:GetStringHeight()
    if self.__w and self.__wrap ~= false and self.__text then
        local size, lines = self.__fontSize or 12, 0
        for line in (plain(self.__text) .. "\n"):gmatch("(.-)\n") do
            lines = lines + math.max(1, math.ceil(textWidth(line, size) / math.max(self.__w, 1)))
        end
        if self.__maxLines and self.__maxLines > 0 then lines = math.min(lines, self.__maxLines) end
        return lines * (size + 2)
    end
    return select(2, natural(self))
end
function Region:GetUnboundedStringWidth() return self:GetStringWidth() end
function Region:SetTextInsets(l, r) self.__insets = { l or 0, r or 0 } end
function Region:HasFocus() return self.__focus == true end
function Region:SetFocus() self.__focus = true; if self._OnEditFocusGained then self._OnEditFocusGained(self) end end
function Region:ClearFocus() self.__focus = false; if self._OnEditFocusLost then self._OnEditFocusLost(self) end end

-- Creating frames ------------------------------------------------------------------------------

function R.CreateFrame(kind, name, parent)
    local f = new(kind or "Frame", parent or R.UIParent, name)
    if kind == "EditBox" then f.__fontSize = 12 end
    return f
end

function R.Reset(w, h)
    UI_W, UI_H = w or 1366, h or 768
    all, named = {}, {}
    R.UIParent = setmetatable({ __kind = "Frame", __points = {}, __shown = true, __alpha = 1,
                                __regions = {}, __children = {}, _events = {} }, regionMeta)
    R.UIParent.__parent = nil
    gen = gen + 1
end

-- Installs the fake frames over a test client (tests/<name>/wow.lua): its W.frames get every
-- frame, so W.Fire reaches them.
function R.Install(W)
    R.Reset()
    CreateFrame = function(kind, name, parent, template)
        local f = R.CreateFrame(kind, name, parent, template)
        if W and W.frames then W.frames[#W.frames + 1] = f end
        return f
    end
    UIParent = R.UIParent
    GameTooltip = R.CreateFrame("GameTooltip", "GameTooltip")
    GameTooltip:Hide()
    STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    UISpecialFrames = UISpecialFrames or {}
    RAID_CLASS_COLORS = {
        MAGE = { r = 0.25, g = 0.78, b = 0.92 }, PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
        PRIEST = { r = 1, g = 1, b = 1 }, DRUID = { r = 1, g = 0.49, b = 0.04 },
        HUNTER = { r = 0.67, g = 0.83, b = 0.45 }, ROGUE = { r = 1, g = 0.96, b = 0.41 },
        WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, WARLOCK = { r = 0.53, g = 0.53, b = 0.93 },
        SHAMAN = { r = 0, g = 0.44, b = 0.87 },
    }
end

-- HTML -----------------------------------------------------------------------------------------

local LAYERS = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }

local function css(c, alpha)
    c = c or { 1, 1, 1, 1 }
    return string.format("rgba(%d,%d,%d,%.3f)", (c[1] or 1) * 255, (c[2] or 1) * 255, (c[3] or 1) * 255,
        (c[4] or 1) * (alpha or 1))
end

local function esc(s) return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")) end

-- WoW text escapes to HTML: |cAARRGGBB..|r colours, |n new lines, |T..|t icons.
local function richText(s)
    s = tostring(s or ""):gsub("|H.-|h", ""):gsub("|h", "")
    local out, open = {}, 0
    local i = 1
    while i <= #s do
        local c = s:sub(i, i)
        if c == "|" then
            local n = s:sub(i + 1, i + 1)
            if n == "c" and s:sub(i + 2, i + 9):match("^%x+$") and #s:sub(i + 2, i + 9) == 8 then
                local hex = s:sub(i + 4, i + 9)
                out[#out + 1] = '<span style="color:#' .. hex .. '">'
                open = open + 1
                i = i + 10
            elseif n == "r" then
                if open > 0 then out[#out + 1] = "</span>"; open = open - 1 end
                i = i + 2
            elseif n == "n" then
                out[#out + 1] = "<br>"
                i = i + 2
            elseif n == "T" then
                local e = s:find("|t", i, true) or #s
                out[#out + 1] = '<span class="ti"></span>'
                i = e + 2
            elseif n == "|" then
                out[#out + 1] = "|"
                i = i + 2
            else
                out[#out + 1] = "|"
                i = i + 1
            end
        elseif c == "\n" then
            out[#out + 1] = "<br>"
            i = i + 1
        else
            local j = s:find("[|\n]", i) or (#s + 1)
            out[#out + 1] = esc(s:sub(i, j - 1))
            i = j
        end
    end
    for _ = 1, open do out[#out + 1] = "</span>" end
    return table.concat(out)
end

local function box(rect, parentRect)
    return string.format("left:%.1fpx;top:%.1fpx;width:%.1fpx;height:%.1fpx;",
        rect.l - parentRect.l, parentRect.t - rect.t, math.max(0, rect.r - rect.l), math.max(0, rect.t - rect.b))
end

local function iconName(path)
    path = tostring(path or "")
    local n = path:match("([^\\/]+)$") or path
    return n
end

local function textHtml(r, rect, prect)
    if not r.__text or r.__text == "" then return "" end
    local size = r.__fontSize or 12
    local jh = (r.__jh or "CENTER"):lower()
    local jv = r.__jv or "MIDDLE"
    local align = jv == "TOP" and "flex-start" or (jv == "BOTTOM" and "flex-end" or "center")
    local wrap = r.__wrap == false and (r.__bound == false and "white-space:nowrap;" or
        "white-space:nowrap;overflow:hidden;text-overflow:ellipsis;") or ""
    local outline = (r.__flags or ""):find("OUTLINE") and "text-shadow:0 0 1px #000,0 0 1px #000,0 0 1px #000;" or ""
    local c = r.__tcolor or { 1, 0.82, 0, 1 }
    local w = rect.r - rect.l
    return string.format(
        '<div class="fs" style="%sfont-size:%dpx;line-height:%dpx;color:%s;align-items:%s;%s">' ..
        '<div style="width:%s;text-align:%s;%s%s">%s</div></div>',
        box(rect, prect), size, size + 2, css(c), align, outline,
        w > 0 and "100%" or "auto", jh == "center" and "center" or (jh == "right" and "right" or "left"), wrap,
        (r.__shadow == false) and "text-shadow:none;" or "",
        richText(r.__text))
end

-- A real picture for a texture path, when tools/preview/icons.sh has fetched it.
local CACHE = (os.getenv("PWD") or ".") .. "/tools/preview/.cache/"
local function exists(f) local h = io.open(f, "rb"); if h then h:close() return true end end
local function picture(path)
    path = tostring(path or ""):lower():gsub("/", "\\")
    local icon = path:match("interface\\icons\\([%w_]+)")
    if icon and exists(CACHE .. "icons/" .. icon .. ".png") then return CACHE .. "icons/" .. icon .. ".png" end
    local track = path:match("interface\\minimap\\tracking\\([%w_]+)")
    if track and exists(CACHE .. "tracking/" .. track .. ".png") then return CACHE .. "tracking/" .. track .. ".png" end
    local addon = path:match("interface\\addons\\([%w%-]+)\\icon")
    if addon and exists(CACHE .. "addons/" .. addon .. ".png") then return CACHE .. "addons/" .. addon .. ".png" end
end

local function texHtml(t, rect, prect)
    local tex = t.__tex
    if not tex then return "" end
    local c = t.__color or { 1, 1, 1, 1 }
    if tostring(tex):find("WHITE8X8") or tostring(tex):find("WHITE8x8") then
        return string.format('<div class="tx" style="%sbackground:%s"></div>', box(rect, prect), css(c))
    end
    local pic = picture(tex)
    if pic then
        local crop = t.__crop and "background-size:118%;background-position:center;" or "background-size:100% 100%;"
        return string.format('<div class="tx" style="%sbackground-image:url(\'file://%s\');%s%s"></div>',
            box(rect, prect), pic, crop, t.__desat and "filter:grayscale(1);opacity:.6;" or "")
    end
    local name = iconName(tex)
    local cls = "ic"
    local low = name:lower()
    if low:find("readycheck%-ready") then cls = "ic ok"
    elseif low:find("readycheck%-notready") then cls = "ic no"
    elseif low:find("readycheck%-waiting") then cls = "ic wait" end
    return string.format('<div class="%s" title="%s" style="%s%s"></div>', cls, esc(name), box(rect, prect),
        t.__desat and "filter:grayscale(1);opacity:.6;" or "")
end

local function lineHtml(t, prect)
    if not t.__start or not t.__end then return "" end
    local sx, sy = anchorXY(R.Rect(t.__start[2]), t.__start[1])
    local ex, ey = anchorXY(R.Rect(t.__end[2]), t.__end[1])
    sx, sy, ex, ey = sx + t.__start[3], sy + t.__start[4], ex + t.__end[3], ey + t.__end[4]
    local dx, dy = ex - sx, ey - sy
    local len = math.sqrt(dx * dx + dy * dy)
    local ang = math.deg(math.atan2(-dy, dx))
    return string.format(
        '<div class="tx" style="left:%.1fpx;top:%.1fpx;width:%.1fpx;height:%.1fpx;background:%s;' ..
        'transform-origin:0 50%%;transform:rotate(%.2fdeg)"></div>',
        sx - prect.l, prect.t - sy, len, t.__thick or 1, css(t.__color), ang)
end

local function frameHtml(f, prect, out)
    if not f.__shown then return end
    local rect = R.Rect(f)
    local clip = f.__kind == "ScrollFrame" and "overflow:hidden;" or ""
    out[#out + 1] = string.format('<div class="fr" data-k="%s" style="%s%sopacity:%.2f">', f.__kind,
        box(rect, prect), clip, f.__alpha or 1)
    local regs = {}
    for i, r in ipairs(f.__regions) do regs[#regs + 1] = { r, i } end
    table.sort(regs, function(a, b)
        local la, lb = LAYERS[a[1].__layer] or 3, LAYERS[b[1].__layer] or 3
        if la ~= lb then return la < lb end
        if (a[1].__sub or 0) ~= (b[1].__sub or 0) then return (a[1].__sub or 0) < (b[1].__sub or 0) end
        return a[2] < b[2]
    end)
    for _, x in ipairs(regs) do
        local r = x[1]
        if r.__shown and r.__layer ~= "HIGHLIGHT" then
            local alpha = r.__alpha or 1
            local html
            if r.__kind == "Line" then html = lineHtml(r, rect)
            else
                local rr = R.Rect(r)
                html = r.__kind == "FontString" and textHtml(r, rr, rect) or texHtml(r, rr, rect)
            end
            if alpha < 1 and html ~= "" then
                html = html:gsub('style="', 'style="opacity:' .. alpha .. ';', 1)
            end
            out[#out + 1] = html
        end
    end
    if f.__kind == "EditBox" and f.__text and f.__text ~= "" then
        local ins = f.__insets or { 0, 0 }
        local tr = { l = rect.l + ins[1], r = rect.r - ins[2], t = rect.t, b = rect.b }
        out[#out + 1] = textHtml({ __text = f.__text, __fontSize = f.__fontSize, __jh = f.__jh or "LEFT",
            __tcolor = f.__tcolor or { 1, 1, 1, 1 }, __wrap = false }, tr, rect)
    end
    if f.__kind == "Slider" and f.__thumb and f.__thumb.__shown ~= false then
        local th = f.__thumb
        local h = th.__h or 20
        local min, max = f.__min or 0, f.__max or 0
        local frac = max > min and ((f.__value or 0) - min) / (max - min) or 0
        local top = rect.t - frac * ((rect.t - rect.b) - h)
        out[#out + 1] = texHtml(th, { l = rect.l, r = rect.r, t = top, b = top - h }, rect)
    end
    local kids = {}
    for i, c in ipairs(f.__children) do kids[#kids + 1] = { c, i } end
    table.sort(kids, function(a, b)
        local la, lb = a[1].__level or 0, b[1].__level or 0
        if la ~= lb then return la < lb end
        return a[2] < b[2]
    end)
    for _, k in ipairs(kids) do frameHtml(k[1], rect, out) end
    out[#out + 1] = "</div>"
end

local STYLE = [[
body{margin:0;background:#1d2229;background-image:radial-gradient(circle at 30%% 20%%,#3a4a3c 0,#1b2027 60%%);
  font-family:"Friz Quadrata","Liberation Sans","DejaVu Sans",sans-serif;}
.ui{position:relative;width:%dpx;height:%dpx;overflow:hidden}
.fr,.tx,.ic,.fs{position:absolute;box-sizing:border-box}
.fs{display:flex;text-shadow:1px -1px 0 rgba(0,0,0,.8);font-stretch:semi-condensed}
.ic{background:linear-gradient(135deg,#6b5a3a,#2b2418);border:1px solid #000;border-radius:2px}
.ic.ok{background:radial-gradient(#4ccf5a 55%%,transparent 60%%);border:0}
.ic.no{background:radial-gradient(#d9483f 55%%,transparent 60%%);border:0}
.ic.wait{background:radial-gradient(#e6b43c 55%%,transparent 60%%);border:0}
.ti{display:inline-block;width:1em;height:1em;vertical-align:-2px;background:#6b5a3a;border:1px solid #000}
]]

-- Writes every shown top-level frame of UIParent into one page. crop = a frame to frame the
-- picture around (its rect plus a margin) or nil for the whole screen.
function R.Html(crop, margin)
    local out = {}
    local root = { l = 0, r = UI_W, t = UI_H, b = 0 }
    for _, f in ipairs(R.UIParent.__children) do
        if f ~= GameTooltip then frameHtml(f, root, out) end
    end
    local body = table.concat(out, "\n")
    local w, h, ox, oy = UI_W, UI_H, 0, 0
    if crop then
        local c = R.Rect(crop)
        margin = margin or 16
        ox, oy = c.l - margin, UI_H - c.t - margin
        w, h = (c.r - c.l) + 2 * margin, (c.t - c.b) + 2 * margin
    end
    return string.format('<!doctype html><html><head><meta charset="utf-8"><style>%s</style></head><body>' ..
        '<div class="ui" style="width:%dpx;height:%dpx"><div style="position:absolute;left:%dpx;top:%dpx;' ..
        'width:%dpx;height:%dpx">%s</div></div></body></html>',
        STYLE:format(w, h), w, h, -ox, -oy, UI_W, UI_H, body)
end

-- Every pair of shown, non-empty texts that overlap inside one window: the "glued" look.
function R.Overlaps(root)
    local texts = {}
    local function walk(f)
        if not f.__shown then return end
        for _, r in ipairs(f.__regions) do
            if r.__kind == "FontString" and r.__shown and r.__text and r.__text ~= "" then
                texts[#texts + 1] = r
            end
        end
        for _, c in ipairs(f.__children) do walk(c) end
    end
    walk(root)
    local found = {}
    for i = 1, #texts do
        for j = i + 1, #texts do
            local a, b = R.Rect(texts[i]), R.Rect(texts[j])
            local ax = math.min(a.r, a.l + textWidth(texts[i].__text, texts[i].__fontSize or 12))
            local bx = math.min(b.r, b.l + textWidth(texts[j].__text, texts[j].__fontSize or 12))
            if a.l < bx - 1 and b.l < ax - 1 and a.b < b.t - 1 and b.b < a.t - 1 then
                found[#found + 1] = { texts[i].__text, texts[j].__text }
            end
        end
    end
    return found
end

return R
