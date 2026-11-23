-- The Tweaks page of the hub: a title with the search and two buttons, a filter track (All, On
-- and the groups), and under it the rows of ns.TweakRows in group cards. A row is an icon, a
-- name, one line, and at the right its switch (and a gear when it has settings, which open
-- under the row). A row a module lends carries the module's tag; when the module is off or
-- paused the row is dim and leads to the module instead of a switch. It only shows what
-- Tweaks.lua holds and calls ns.SetTweak, ns.SetTweakOpt, the module's own set and
-- ns.TweaksRecommended / ns.TweaksAllOff.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local ROW_H, HEAD_H, CARD_GAP = 44, 34, 10
local ICON = 30
local TEXT_X = 12 + ICON + 12
-- The font has no star glyph: the star is our own texture, tinted gold.
local STAR = "Interface\\AddOns\\Gulli-Toolkit\\Art\\Star"
local GEAR = "Interface\\Icons\\INV_Misc_Gear_01"
ns.TWEAKS_ICON = "Interface\\Icons\\INV_Misc_Wrench_01"

local page, api
local view = { filter = "all", query = "", open = {} }
local cards, rowPool, panels = {}, {}, {}
local FILTERS = { "all", "on" }
for _, g in ipairs(ns.TWEAK_GROUPS) do FILTERS[#FILTERS + 1] = g end

local function filterName(f)
    if f == "all" then return L.TW_ALL elseif f == "on" then return L.TW_ON end
    return L["TWG_" .. f:upper()]
end

local function width(fs) return math.ceil(tonumber(fs:GetStringWidth()) or 0) end

local function setStar(t)
    t:SetTexture(STAR)
    t:SetVertexColor(S.GOLD[1], S.GOLD[2], S.GOLD[3], 1)
end

-- Rows --------------------------------------------------------------------------------------------

local function rowTip(self)
    local r = self.data
    if not r then return end
    local lines = { r.tip or r.desc }
    if r.kind == "module" then lines[#lines + 1] = S.Hex(S.FAINT) .. L.TW_SETOF:format(r.module.title) .. "|r" end
    if r.shift then lines[#lines + 1] = S.Hex(S.FAINT) .. L.TW_SHIFT .. "|r" end
    if r.star then lines[#lines + 1] = S.Hex(S.GOLD) .. L.TW_REC_TIP .. "|r" end
    api.tip(self, r.label, lines)
end

local function openModule(r)
    if r and r.module then api.enter(r.module) end
end

local function makeRow(i)
    local f = CreateFrame("Button", nil, page.inner)
    f:SetHeight(ROW_H)
    S.Box(f, S.CLEAR, S.CLEAR)
    f.line = f:CreateTexture(nil, "BORDER")
    f.line:SetColorTexture(S.LINE[1], S.LINE[2], S.LINE[3], S.LINE[4] or 1)
    f.line:SetHeight(1)
    f.line:SetPoint("TOPLEFT", 0, 0)
    f.line:SetPoint("TOPRIGHT", 0, 0)
    f.icon = S.IconBox(f, ICON)
    f.icon:SetPoint("LEFT", 12, 0)
    f.name = S.Text(f, 13, S.TEXT, nil, "bold")
    f.name:SetPoint("TOPLEFT", TEXT_X, -6)
    f.name:SetWordWrap(false)
    f.star = f:CreateTexture(nil, "ARTWORK")
    f.star:SetSize(14, 14)
    setStar(f.star)
    -- The module's tag after the name: its icon and its name, a click opens it.
    f.tag = CreateFrame("Button", nil, f)
    f.tag:SetHeight(20)
    S.Box(f.tag, S.RAISED, S.CLEAR, 10)
    f.tag.icon = S.IconBox(f.tag, 14)
    f.tag.icon:SetPoint("LEFT", 4, 0)
    f.tag.text = S.Text(f.tag, 12, S.MUTED)
    f.tag.text:SetPoint("LEFT", f.tag.icon, "RIGHT", 4, 0)
    f.tag.text:SetWordWrap(false)
    -- The module is off: a hollow dot after the word, so the state never shows by colour alone.
    f.tag.ring = S.Circle(f.tag, 8, S.FAINT, "ARTWORK")
    f.tag.hole = S.Circle(f.tag, 6, S.RAISED, "OVERLAY")
    f.tag.hole:SetPoint("CENTER", f.tag.ring, "CENTER")
    f.tag:SetScript("OnClick", function(self) openModule(self:GetParent().data) end)
    f.tag:SetScript("OnEnter", function(self)
        local r = self:GetParent().data
        if r and r.module then api.tip(self, r.module.title, { L.TW_SETOF:format(r.module.title) }) end
    end)
    f.tag:SetScript("OnLeave", function() api.hideTip() end)
    f.desc = S.Text(f, 12, S.MUTED)
    f.desc:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -3)
    f.desc:SetWordWrap(false)
    f.switch = S.Switch(f)
    f.switch:SetPoint("RIGHT", -12, 0)
    f.switch:SetScript("OnClick", function(self)
        local r = self:GetParent().data
        if not r then return end
        if r.kind == "own" then ns.SetTweak(r.key, not r.on)
        else pcall(r.set, not r.on); ns.Refresh() end
    end)
    f.switch:HookScript("OnEnter", function(self) rowTip(self:GetParent()) end)
    f.switch:HookScript("OnLeave", function() api.hideTip() end)
    f.gear = S.Button(f, 28, 28)
    f.gear:SetPoint("RIGHT", f.switch, "LEFT", -10, 0)
    S.SetButtonIcon(f.gear, GEAR, 18)
    f.gear.btnIcon:ClearAllPoints()
    f.gear.btnIcon:SetPoint("CENTER")
    f.gear:SetScript("OnClick", function(self)
        local r = self:GetParent().data
        if r then view.open[r.key] = not view.open[r.key] or nil; ns.Refresh() end
    end)
    f.gear:HookScript("OnEnter", function(self)
        api.tip(self, L.TW_SETTINGS, { self:GetParent().data and self:GetParent().data.label or nil })
    end)
    f.gear:HookScript("OnLeave", function() api.hideTip() end)
    f.link = CreateFrame("Button", nil, f)
    f.link:SetHeight(28)
    f.link:SetPoint("RIGHT", -12, 0)
    f.link.text = S.Text(f.link, 12, S.Accent())
    f.link.text:SetPoint("RIGHT")
    f.link.text:SetWordWrap(false)
    f.link:SetScript("OnClick", function(self) openModule(self:GetParent().data) end)
    f:SetScript("OnClick", function(self)
        local r = self.data
        if not r then return end
        if not r.live then openModule(r)
        elseif r.panel then view.open[r.key] = not view.open[r.key] or nil; ns.Refresh() end
    end)
    f:SetScript("OnEnter", function(self) S.Fill(self, S.HOVER); rowTip(self) end)
    f:SetScript("OnLeave", function(self) S.Fill(self, S.CLEAR); api.hideTip() end)
    rowPool[i] = f
    return f
end

local function fillRow(f, r, w, first)
    f.data = r
    f:SetWidth(w)
    f.line:SetShown(not first)
    f.icon:SetIcon(r.icon)
    local live = r.live
    f.icon.tex:SetDesaturated(not live)
    f.icon:SetAlpha(live and 1 or 0.6)
    local c = live and S.TEXT or S.FAINT
    f.name:SetTextColor(c[1], c[2], c[3], 1)
    f.desc:SetTextColor(live and S.MUTED[1] or S.FAINT[1], live and S.MUTED[2] or S.FAINT[2],
        live and S.MUTED[3] or S.FAINT[3], live and 1 or 0.8)
    f.name:SetText(r.label)
    f.desc:SetText(r.desc or "")
    -- What stands at the right: the switch (and the gear), or the way to a module that is off.
    local right
    f.switch:SetShown(live)
    f.link:SetShown(not live)
    f.gear:SetShown(live and r.panel ~= nil)
    if live then
        f.switch:SetChecked(r.on)
        right = 12 + 44 + (r.panel and (10 + 28) or 0)
    else
        f.link.text:SetText(L.TW_OPEN:format(r.module.title))
        f.link:SetWidth(width(f.link.text) + 2)
        right = 12 + width(f.link.text) + 2
    end
    local room = w - TEXT_X - right - 12
    f.desc:SetWidth(math.max(40, room))
    -- The name as wide as it is, the star or the tag right after it.
    local extra = 0
    f.star:SetShown(r.star)
    f.tag:SetShown(r.kind == "module")
    if r.kind == "module" then
        local label = r.module.title
        if not live then label = label .. S.DOT .. L.TW_OFF end
        f.tag.text:SetText(label)
        f.tag.icon:SetIcon(r.module.icon)
        f.tag.ring:ClearAllPoints()
        f.tag.ring:SetPoint("LEFT", f.tag.text, "RIGHT", 5, 0)
        f.tag.ring:SetShown(not live)
        f.tag.hole:SetShown(not live)
        local tw = 4 + 14 + 4 + width(f.tag.text) + (live and 8 or (5 + 8 + 8))
        f.tag:SetWidth(tw)
        extra = 8 + tw
    elseif r.star then
        extra = 6 + 14
    end
    local nameW = math.min(width(f.name) + 4, math.max(40, room - extra))
    f.name:SetWidth(nameW)
    f.star:ClearAllPoints()
    f.star:SetPoint("LEFT", f.name, "LEFT", nameW + 6, 0)
    f.tag:ClearAllPoints()
    f.tag:SetPoint("LEFT", f.name, "LEFT", nameW + 8, 0)
    f:Show()
end

-- The settings under a row ----------------------------------------------------------------------

local PANEL_PAD, PART_H, COL_GAP = 12, 32, 24

local function partLabel(parent, text, color)
    local t = S.Text(parent, 12, color or S.TEXT)
    t:SetWordWrap(false)
    t:SetText(text or "")
    return t
end

-- Builds the controls of a tweak's settings once; layout() places the ones `when` lets show.
local function buildPanel(r)
    local t = r.tweak
    local key = t.key
    local p = CreateFrame("Frame", nil, page.inner)
    S.Box(p, S.INPUT, S.LINE, S.R_MD)
    p.parts = {}
    local get = ns.TweakGetter(key)
    for _, part in ipairs(t.panel or {}) do
        local e = { part = part }
        if part.kind == "head" then
            e.text = partLabel(p, part.label, S.FAINT)
        elseif part.kind == "switch" then
            e.text = partLabel(p, part.label)
            e.control = S.Switch(p)
            e.control:SetScript("OnClick", function()
                ns.SetTweakOpt(key, part.key, not get(part.key))
                ns.Refresh()
            end)
        elseif part.kind == "check" then
            e.control = S.Check(p, 26)
            e.text = partLabel(p, part.label)
            e.control:SetScript("OnClick", function()
                ns.SetTweakOpt(key, part.key, not get(part.key))
                ns.Refresh()
            end)
        elseif part.kind == "choice" then
            e.text = partLabel(p, part.label, S.FAINT)
            local labels = {}
            for i, v in ipairs(part.values or {}) do labels[i] = v[2] end
            e.tabs = S.Tabs(p, labels, nil, function(i)
                ns.SetTweakOpt(key, part.key, part.values[i][1])
                ns.Refresh()
            end, 30)
            e.control = e.tabs.frame
        elseif part.kind == "step" then
            e.text = partLabel(p, part.label)
            e.control = S.Stepper(p, function() return get(part.key) or part.min or 0 end,
                function(v) ns.SetTweakOpt(key, part.key, v) end,
                part.step or 1, part.min or 0, part.max or 100, part.fmt, part.width or 110)
        end
        if part.tip and e.control then
            e.control:HookScript("OnEnter", function(self) api.tip(self, part.label, { part.tip }) end)
            e.control:HookScript("OnLeave", function() api.hideTip() end)
        end
        p.parts[#p.parts + 1] = e
    end

    -- Lays the parts out for a panel w wide and returns its height.
    function p:Layout(w)
        local inner = w - 2 * PANEL_PAD
        local colW = math.floor((inner - COL_GAP) / 2)
        local y, col, lineX = PANEL_PAD, 0, nil
        local function newLine()
            if col == 1 then y = y + PART_H; col = 0 end
            if lineX then y = y + PART_H; lineX = nil end
        end
        for _, e in ipairs(self.parts) do
            local part = e.part
            local shown = not part.when or part.when(get) == true
            if e.text then e.text:SetShown(shown) end
            if e.control then e.control:SetShown(shown) end
            if shown then
                if part.kind == "switch" then
                    if lineX then y = y + PART_H; lineX = nil end
                    local x = PANEL_PAD + col * (colW + COL_GAP)
                    e.control:SetChecked(get(part.key) == true)
                    e.control:ClearAllPoints()
                    e.control:SetPoint("TOPLEFT", x + colW - 44, -(y + 2))
                    e.text:ClearAllPoints()
                    e.text:SetPoint("LEFT", e.control, "LEFT", -(colW - 44), 0)
                    e.text:SetWidth(colW - 44 - 8)
                    if col == 0 then col = 1 else col = 0; y = y + PART_H end
                elseif part.kind == "check" then
                    if col == 1 then y = y + PART_H; col = 0 end
                    e.control:SetChecked(get(part.key) == true)
                    e.text:SetWidth(0)
                    local need = 26 + 4 + width(e.text) + 22
                    if lineX and lineX + need > PANEL_PAD + inner then y = y + PART_H; lineX = nil end
                    local x = lineX or PANEL_PAD
                    e.control:ClearAllPoints()
                    e.control:SetPoint("TOPLEFT", x - 5, -(y + 2))
                    e.text:ClearAllPoints()
                    e.text:SetPoint("LEFT", e.control, "RIGHT", 2, 0)
                    e.text:SetWidth(math.min(width(e.text) + 6, PANEL_PAD + inner - x - 26))
                    lineX = x + need
                else
                    newLine()
                    if part.kind == "head" then
                        e.text:ClearAllPoints()
                        e.text:SetPoint("TOPLEFT", PANEL_PAD, -y)
                        e.text:SetWidth(inner)
                        y = y + 22
                    elseif part.kind == "choice" then
                        e.text:ClearAllPoints()
                        e.text:SetPoint("TOPLEFT", PANEL_PAD, -(y + 8))
                        local lw = width(e.text) + 6
                        e.text:SetWidth(lw)
                        e.control:ClearAllPoints()
                        e.control:SetPoint("TOPLEFT", PANEL_PAD + lw + 12, -y)
                        local value = get(part.key)
                        for i, v in ipairs(part.values or {}) do
                            if v[1] == value then e.tabs:Select(i, true) end
                        end
                        y = y + 38
                    elseif part.kind == "step" then
                        e.control:Refresh()
                        e.control:ClearAllPoints()
                        e.control:SetPoint("TOPRIGHT", -PANEL_PAD, -(y + 2))
                        e.text:ClearAllPoints()
                        e.text:SetPoint("LEFT", PANEL_PAD, 0)
                        e.text:SetPoint("TOP", e.control, "TOP", 0, -7)
                        e.text:SetWidth(inner - (part.width or 110) - 12)
                        y = y + PART_H + 2
                    end
                end
            end
        end
        newLine()
        return y + PANEL_PAD - 6
    end
    panels[key] = p
    return p
end

-- Cards -----------------------------------------------------------------------------------------

local function makeCard(i)
    local c = CreateFrame("Frame", nil, page.inner)
    S.Box(c, S.SURFACE, S.CARD_EDGE, S.R_LG)
    S.Depth(c, S.R_LG)
    c.title = S.Text(c, 12, S.GOLD_DIM, nil, "bold")
    c.title:SetPoint("TOPLEFT", S.INSET + 2, -12)
    c.title:SetWordWrap(false)
    c.count = S.Text(c, 12, S.FAINT)
    c.count:SetPoint("TOPRIGHT", -S.INSET - 2, -12)
    c.count:SetJustifyH("RIGHT")
    cards[i] = c
    return c
end

-- The page ----------------------------------------------------------------------------------------

local function toast(textKey, n, was)
    S.Toast({ key = "tweaks", icon = ns.TWEAKS_ICON, title = L.TW_PAGE, text = L[textKey]:format(n),
        seconds = 10, buttons = { { text = L.TW_UNDO, onClick = function() ns.TweaksRestore(was) end } } })
end

-- The filter track. mode 1: icon and name on every part; 2: the groups by name only; 3: the
-- groups by icon only (a tooltip names them). The parts are packed closer than S.Tabs does, so
-- the full track fits the centre in most languages.
local function buildTrack(mode)
    local old = rawget(page, "track")
    if old then old.frame:Hide() end
    local labels, icons = {}, {}
    for i, f in ipairs(FILTERS) do
        local fixed = f == "all" or f == "on"
        -- Room for a two-digit count after All and On.
        labels[i] = (fixed or mode ~= 3) and (filterName(f) .. (fixed and " 88" or "")) or ""
        icons[i] = (fixed or mode ~= 2) and ns.TWEAK_GROUP_ICON[f] or false
    end
    local t = S.Tabs(page, labels, nil, function(i)
        view.filter = FILTERS[i]
        page.scroll:Top()
        ns.Refresh()
    end, 30, icons)
    local x = 2
    for i, f in ipairs(FILTERS) do
        local b = t.buttons[i]
        if labels[i] == "" then b.tip = filterName(f) end
        local bw = labels[i] == "" and 34 or (width(b.text) + 22 + (icons[i] and 18 or 0))
        b:SetWidth(bw)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", x, -2)
        b.x = x
        x = x + bw
    end
    t.frame:SetWidth(x + 2)
    t:Select(1, true)
    t.frame:ClearAllPoints()
    t.frame:SetPoint("TOPLEFT", 0, -66)
    page.track = t
    return t
end

function ns.BuildTweaksPage(host, w, h, hub)
    api = hub
    page = CreateFrame("Frame", "GulliToolkitTweaksPage", host)
    page:SetAllPoints(host)
    page:EnableMouse(true)
    page:Hide()
    page.w, page.h = w, h
    page.title = S.Text(page, 20, S.GOLD, nil, "title")
    page.title:SetPoint("TOPLEFT", 2, 0)
    page.title:SetText(L.TW_PAGE)
    page.hint = S.Text(page, 12, S.MUTED)
    page.hint:SetPoint("TOPLEFT", 2, -30)
    page.hint:SetWidth(w - 4)
    page.hint:SetWordWrap(false)

    -- At the right of the title: Turn all off, Recommended, and the search.
    local off = S.Button(page, 100, 30)
    off:SetText(L.TW_ALL_OFF)
    off:SetWidth(width(off.text) + 32)
    off:SetPoint("TOPRIGHT", 0, 0)
    off:SetScript("OnClick", function()
        local was, n = ns.TweaksAllOff()
        if n > 0 then toast("TW_TOAST_OFF", n, was) end
        ns.Refresh()
    end)
    off:HookScript("OnEnter", function(self) api.tip(self, L.TW_ALL_OFF, { L.TW_ONLY }) end)
    off:HookScript("OnLeave", function() api.hideTip() end)
    local rec = S.Button(page, 100, 30)
    rec:SetText(L.TW_RECOMMENDED)
    rec.star = rec:CreateTexture(nil, "ARTWORK")
    rec.star:SetSize(14, 14)
    setStar(rec.star)
    rec.star:SetPoint("LEFT", 10, 0)
    rec.text:ClearAllPoints()
    rec.text:SetPoint("LEFT", 28, 0)
    rec.text:SetPoint("RIGHT", -10, 0)
    rec:SetWidth(width(rec.text) + 54)
    rec:SetPoint("RIGHT", off, "LEFT", -8, 0)
    rec:SetScript("OnClick", function()
        local was, n = ns.TweaksRecommended()
        if n > 0 then toast("TW_TOAST_REC", n, was) end
        ns.Refresh()
    end)
    rec:HookScript("OnEnter", function(self)
        api.tip(self, L.TW_RECOMMENDED, { L.TW_REC_HINT:format(ns.RecommendedCount()), L.TW_ONLY })
    end)
    rec:HookScript("OnLeave", function() api.hideTip() end)
    page.off, page.rec = off, rec

    local search = S.Edit(page, 200, 30)
    search:SetPoint("RIGHT", rec, "LEFT", -10, 0)
    search:SetJustifyH("LEFT")
    search:SetTextInsets(28, 8, 0, 0)
    local glass = search:CreateTexture(nil, "OVERLAY")
    glass:SetSize(14, 14)
    glass:SetPoint("LEFT", 8, 0)
    glass:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    glass:SetVertexColor(S.FAINT[1], S.FAINT[2], S.FAINT[3], 1)
    local ph = S.Text(search, 13, S.FAINT)
    ph:SetPoint("LEFT", 28, 0)
    ph:SetPoint("RIGHT", -8, 0)
    ph:SetWordWrap(false)
    ph:SetText(L.TW_SEARCH)
    local function hint(self) ph:SetShown((self:GetText() or "") == "" and not self:HasFocus()) end
    search:HookScript("OnEditFocusGained", hint)
    search:HookScript("OnEditFocusLost", hint)
    search:SetScript("OnTextChanged", function(self)
        view.query = self:GetText() or ""
        hint(self)
        page.scroll:Top()
        ns.Refresh()
    end)
    search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    page.search, page.placeholder = search, ph
    -- The title and the controls share the first line: the search gives way in a long language.
    local spare = w - (width(page.title) + 16) - rec:GetWidth() - off:GetWidth() - 18
    search:SetWidth(math.max(140, math.min(220, spare)))

    -- The filter track: the fullest one that fits.
    for mode = 1, 3 do
        local t = buildTrack(mode)
        if (tonumber(t.frame:GetWidth()) or 0) <= w or mode == 3 then break end
    end

    local body = S.ScrollPage(page, w)
    body:SetPoint("TOPLEFT", 0, -106)
    body:SetPoint("BOTTOMRIGHT", 0, 0)
    page.body, page.inner, page.scroll = body, body.inner, body.scroll
    page.empty = S.Empty(body)
    return page
end

function ns.TweaksPage() return page end
function ns.TweaksView() return view end

-- Puts a search on the page, as the hub's search does when it finds tweaks.
function ns.TweaksSearch(query)
    if not page then return end
    page.search:SetText(query or "")
    view.query = query or ""
    view.filter = "all"
    page.track:Select(1, true)
end

function ns.FillTweaks(list)
    if not page or not page:IsShown() then return end
    local all = ns.TweakRows(list)
    local matched = ns.TweakFilter(all, "all", view.query)
    local counts = ns.TweakCounts(matched)
    local searching = view.query:match("%S") ~= nil
    -- The track: All and On count what the search finds.
    for i, f in ipairs(FILTERS) do
        local b = page.track.buttons[i]
        if f == "all" then b:SetText(filterName(f) .. " " .. S.Emph(tostring(counts.all.total)))
        elseif f == "on" then b:SetText(filterName(f) .. " " .. S.Emph(tostring(counts.all.on)))
        end
        b:SetAlpha((f == "all" or f == "on" or (counts[f] and counts[f].total > 0)) and 1 or 0.45)
    end
    if searching then page.hint:SetText(L.TW_FOUND:format(#matched))
    else page.hint:SetText(L.TW_HINT) end

    local shown = ns.TweakFilter(matched, view.filter, "")
    local w = page.inner:GetWidth()
    if not w or w < 100 then w = page.w - 10 end
    local y, ci, ri = 0, 0, 0
    for _, p in pairs(panels) do p:Hide() end
    for _, g in ipairs(ns.TweakGroups(shown)) do
        ci = ci + 1
        local c = cards[ci] or makeCard(ci)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", 0, -y)
        c:SetWidth(w)
        c.title:SetText(S.Upper(L["TWG_" .. g.key:upper()]))
        local gc = counts[g.key]
        c.count:SetText(gc.on .. "/" .. gc.total)
        local cy = HEAD_H
        for i, r in ipairs(g.rows) do
            ri = ri + 1
            local f = rowPool[ri] or makeRow(ri)
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", 0, -(y + cy))
            fillRow(f, r, w, i == 1)
            f:SetFrameLevel((tonumber(c:GetFrameLevel()) or 0) + 2)
            cy = cy + ROW_H
            if r.kind == "own" and r.panel and view.open[r.key] then
                local p = panels[r.key] or buildPanel(r)
                local ph = p:Layout(w - TEXT_X - 12)
                p:ClearAllPoints()
                p:SetPoint("TOPLEFT", TEXT_X, -(y + cy))
                p:SetSize(w - TEXT_X - 12, ph)
                p:SetFrameLevel((tonumber(c:GetFrameLevel()) or 0) + 2)
                p:Show()
                cy = cy + ph + 10
            end
        end
        c:SetHeight(cy + 2)
        c:Show()
        y = y + cy + 2 + CARD_GAP
    end
    for i = ci + 1, #cards do cards[i]:Hide() end
    for i = ri + 1, #rowPool do rowPool[i]:Hide() end
    page.empty:SetShown(#shown == 0)
    if #shown == 0 then
        if searching then page.empty:Set(L.TW_NONE:format(view.query), L.TW_NONE2)
        elseif view.filter == "on" then page.empty:Set(L.TW_NONE_ON, L.TW_NONE_ON2)
        else page.empty:Set(L.TW_NONE_GROUP, "") end
    end
    page.body:SetContent(math.max(1, y - CARD_GAP))
end
