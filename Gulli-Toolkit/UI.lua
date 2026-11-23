-- The hub window. On the left a narrow list of the modules (their state in the colour of the name),
-- grouped by category, with the search on top. In the centre always one page: the module the
-- player clicked (its own window, docked; a narrow one keeps a card about the module beside
-- it), the home page (a dashboard: the Ready card, the session, the modules' news as number
-- tiles, the Recent feed and the Modules card) or the Setup page. Unlock frames is a link in
-- the header. It only shows what Core.lua gives (ns.List, ns.Filter, ns.Groups, ns.Tiles,
-- ns.SessionCard, ns.Readiness, ns.FeedRows, ns.Overview) and calls ns.Switch, ns.SetLoaded,
-- ns.ApplyPreset, ns.SetMoving and the module's own window.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local SIDE, CARD, GAP = 210, 280, S.GAP
local MID = S.NARROW_W
local HOST_W = MID + GAP + CARD
local HOST_H = S.DOCK_H
local W = 2 * S.PAD + SIDE + GAP + HOST_W
-- The hub's header is taller than a module window's, with less room above and below the
-- centre, so the window stays 1086 by 700.
local HUB_HEAD, VPAD = 56, 10
local H = HUB_HEAD + 2 * VPAD + HOST_H
-- The side column runs from the window's edge to a hairline, SIDE_IN pixels of room inside.
local SIDE_IN = 10
local LIST_W = SIDE + S.PAD - 1 - 2 * SIDE_IN - 10
local ROW_H, HEAD_H = 30, 26
local LABEL_H = 20
local LINE_H = 24
-- The Setup page's buttons that are not presets (a preset names its own icon in ns.PRESETS),
-- its own row in the list, and the Unlock link in the header.
local QUICK_ICON = {
    page = "Interface\\Icons\\INV_Misc_Gear_01",
    move = "Interface\\Icons\\Ability_Hunter_Pathfinding",
    transfer = "Interface\\Icons\\INV_Misc_Note_01",
    protect = "Interface\\Icons\\Spell_Holy_SealOfProtection",
    setup = "Interface\\Icons\\INV_Misc_Gear_02",
}

local GOOD, WAIT, BAD = S.GOOD, S.WARN, S.BAD
local LINE, HOVER = S.LINE, S.HOVER
local TOOLKIT_ICON = "Interface\\AddOns\\Gulli-Toolkit\\icon"
local MARK = "Interface\\AddOns\\Gulli-Toolkit\\Art\\Mark"
-- The emblem's size behind the centre, and how much of it runs off the window's corner.
local MARK_SIZE, MARK_CUT_X, MARK_CUT_Y = 430, 34, 46

-- page: "home", "module", "setup", "protect", "transfer", "ready" or "errors"; inside: the key of
-- the docked module; from: the page a centre page was opened from ("setup"), where its close
-- button goes back to.
local view = { page = "home", query = "" }
local frame, side, search, placeholder, scroll, list, empty
local scaleText, protectBtn, protectFrame, transfer, errorsFrame, readyFrame
local host, hubSwitch, pinBox, offWin, insideWin, card, home, homeRow, tweaksRow, setupRow, setupFrame, unlockLink
local rows, heads = {}, {}
local fillSetup

local function catName(key)
    if key == "All" then return L.ALL_MODULES end
    return L["CAT_" .. key]
end

local function line(parent, color)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetTexture("Interface\\Buttons\\WHITE8X8")
    local c = color or LINE
    t:SetVertexColor(c[1], c[2], c[3], c[4])
    return t
end

local function stateText(row)
    if row.paused then return L.STATE_PAUSED, S.MUTED end
    if row.state == "ready" then return L.STATE_ON, GOOD end
    if row.state == "reload" then return L.STATE_RELOAD, WAIT end
    if row.state == "blocked" then return L.STATE_BLOCKED:format(ns.ReasonText(row.reason)), BAD end
    return L.OFF, S.MUTED
end

local function moduleName(key)
    for _, r in ipairs(ns.List()) do if r.key == key then return r.title, r end end
    return key
end

local function findRow(key)
    if not key then return nil end
    for _, r in ipairs(ns.List()) do if r.key == key then return r end end
end

-- A tooltip: a white title and grey lines that wrap.
local function tip(owner, title, lines, anchor)
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    GameTooltip:SetText(title or "", 1, 1, 1, 1, true)
    for _, l in ipairs(lines or {}) do
        if l and l ~= "" then GameTooltip:AddLine(l, 0.6, 0.61, 0.66, true) end
    end
    GameTooltip:Show()
end

local function hideTip() GameTooltip:Hide() end

-- The minimap button's tooltip: each action named in the game's yellow, the
-- command in green, what it does in white, so it reads on any background.
function ns.MinimapTip()
    local key, cmd = "|cffffd100", "|cff4cff4c"
    return {
        { title = L.TITLE },
        { text = key .. L.MM_CLICK_KEY .. "|r " .. L.MM_CLICK },
        { text = key .. L.MM_RIGHT_KEY .. "|r " .. L.MM_RIGHT },
        { text = key .. L.MM_DRAG_KEY .. "|r " .. L.MM_DRAG },
        { text = cmd .. "/gulli minimap|r " .. L.MM_HIDE },
    }
end

-- A see-through tooltip skin lets the minimap buttons behind show through, so
-- ours gets a dense centre while it shows and gives the old one back after.
local tipCenter
local function denseTip(on)
    local nine = rawget(GameTooltip, "NineSlice")
    local c = nine and rawget(nine, "Center")
    if not (c and c.GetVertexColor and c.SetVertexColor) then return end
    if on and not tipCenter then
        tipCenter = { c:GetVertexColor() }
        c:SetVertexColor(S.SOLID[1], S.SOLID[2], S.SOLID[3], 0.97)
        if not rawget(GameTooltip, "gulliDense") and GameTooltip.HookScript then
            rawset(GameTooltip, "gulliDense", true)
            GameTooltip:HookScript("OnHide", function() denseTip(false) end)
        end
    elseif not on and tipCenter then
        c:SetVertexColor(tipCenter[1], tipCenter[2], tipCenter[3], tipCenter[4])
        tipCenter = nil
    end
end

local function place(f, y)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", 0, -y)
    f:SetPoint("TOPRIGHT", 0, -y)
end

-- A module that has no window for the hub opens alone and the hub steps aside.
local function open(row)
    if row and ns.OpenModule(row.key) then frame:Hide() end
end

-- The centre ------------------------------------------------------------------------------------

-- The window a module gives the hub, when it can sit inside it.
local function moduleWindow(row)
    local fn = row.info and row.info.window
    if type(fn) ~= "function" then return nil end
    local ok, win = pcall(fn)
    if not ok or type(win) ~= "table" or type(win.Dock) ~= "function" then return nil end
    local size = win.size or {}
    if (size[1] or 0) > HOST_W or (size[2] or 0) > HOST_H then return nil end
    return win
end

-- The page for a module that is not loaded (off, waiting for a reload, refused).
local function offWindow(row)
    if not offWin then
        offWin = S.Window(nil, "", MID, HOST_H)
        offWin.empty = S.Empty(offWin.body)
        offWin.reload = S.Primary(S.FitButton(offWin.body, L.RELOAD, 32, 140))
        offWin.reload:SetPoint("TOP", offWin.body, "CENTER", 0, -60)
        offWin.reload:SetScript("OnClick", function() ReloadUI() end)
    end
    offWin.icon:SetTexture(row.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    offWin.icon:SetDesaturated(true)
    offWin.title:SetText(row.title)
    offWin.sub:SetText(row.slash or "")
    if row.state == "blocked" then
        offWin.empty:Set(row.reason == "INTERFACE_VERSION" and L.INSIDE_OUTDATED
            or L.INSIDE_BLOCKED:format(ns.ReasonText(row.reason)))
    else
        offWin.empty:Set(row.state == "reload" and L.INSIDE_RELOAD or L.INSIDE_OFF)
    end
    offWin.reload:SetShown(row.state == "reload")
    return offWin
end

local function hidePanels()
    if protectFrame then protectFrame:Hide() end
    if transfer then transfer:Hide() end
    if errorsFrame then errorsFrame:Hide() end
    if readyFrame then readyFrame:Hide() end
    if setupFrame then setupFrame:Hide() end
    if ns.TweaksPage and ns.TweaksPage() then ns.TweaksPage():Hide() end
end

-- Takes the docked module out, without choosing another page.
local function leave()
    local win = insideWin
    insideWin, view.inside = nil, nil
    if card then card:Hide() end
    if win then win:Undock() end
end

local function showHome()
    leave()
    hidePanels()
    local was = home:IsShown()
    view.page = "home"
    home:Show()
    if not was then S.MotionIn(home, 6, S.BASE) end
    ns.Refresh()
end

-- The back button and the Home row: the hub opens on the home page next time.
local function goHome()
    ns.SetLast(nil)
    showHome()
end

-- Takes the module out of the hub into its own window.
local function popOut()
    local win = insideWin
    if not win or win == offWin then return end
    showHome()
    win:Show()
end

-- The module closed its own window: back to the home page while the hub stays open.
local function windowHidden()
    if frame:IsShown() then showHome() else leave() end
end

local function enter(row)
    if not row then return end
    local win
    if row.state == "ready" then
        win = moduleWindow(row)
        if not win then return open(row) end
    else
        win = offWindow(row)
    end
    if insideWin and insideWin ~= win then leave() end
    hidePanels()
    home:Hide()
    local narrow = (win.size and win.size[1] or MID) <= MID
    insideWin, view.inside, view.narrow, view.page = win, row.key, narrow, "module"
    if row.state == "ready" then ns.SetLast(row.key) end
    ns.MarkSeen(row)
    card:SetShown(narrow)
    hubSwitch:SetChecked(row.on)
    pinBox.switch:SetChecked(ns.Pinned(row.key))
    win:Dock(host, {
        width = narrow and MID or HOST_W, height = HOST_H, right = { hubSwitch, pinBox },
        back = goHome, popOut = popOut, onHide = windowHidden,
    })
    S.MotionIn(win, 6, S.BASE)
    ns.Refresh()
end

local function showPanel(name, from)
    leave()
    hidePanels()
    home:Hide()
    view.page, view.from = name, from
    if name == "protect" then protectFrame:Show()
    elseif name == "setup" then setupFrame:Show()
    elseif name == "tweaks" then ns.TweaksPage():Show()
    elseif name == "errors" then errorsFrame:Show()
    elseif name == "ready" then readyFrame:Show()
    else transfer:Show() end
    ns.Refresh()
end

-- Left column ----------------------------------------------------------------------------------

local function rowTip(self)
    local row = self.row
    if not row then return end
    local st, c = stateText(row)
    local lines = { row.desc, S.Hex(c) .. st .. "|r" }
    if row.slash then lines[#lines + 1] = L.COMMAND:format(row.slash) end
    if row.new then lines[#lines + 1] = S.Hex(S.Accent()) .. L.NEW_TIP .. "|r" end
    tip(self, row.title, lines)
end

-- A row of the side list. The selection is one plate (selPlate) that slides to the chosen row;
-- the row itself only lights up under the cursor.
local selPlate

local function selectable(r)
    S.Box(r, S.CLEAR, S.CLEAR, S.R_MD)
    function r:SetSelected(on)
        self.selected = on
        S.Fill(self, S.CLEAR)
    end
    r:SetScript("OnLeave", function(self)
        S.Fill(self, S.CLEAR)
        hideTip()
    end)
end

local function makeSelPlate()
    local p = CreateFrame("Frame", nil, list)
    p:SetHeight(ROW_H)
    local a = S.Accent()
    S.Box(p, { S.FILL[1], S.FILL[2], S.FILL[3], 0.34 }, S.CLEAR, S.R_MD)
    p.bar = S.Tex(p, "ARTWORK", 2, a)
    p.bar:SetWidth(2)
    p.bar:SetPoint("TOPLEFT", 0, -5)
    p.bar:SetPoint("BOTTOMLEFT", 0, 5)
    selPlate = p
    return p
end

-- Puts the plate on the row at y; it slides there from where it was.
local function moveSel(y)
    local p = selPlate or makeSelPlate()
    if not y then p:Hide(); rawset(p, "y", nil) return end
    local from = rawget(p, "y")
    rawset(p, "y", y)
    p:Show()
    S.Tween(p, "y", from, y, S.BASE, function(v) place(p, math.floor(v + 0.5)) end)
end

local function makeRow(i)
    local r = CreateFrame("Button", nil, list)
    r:SetHeight(ROW_H)
    selectable(r)
    r.box = S.IconBox(r, 20)
    r.box:SetPoint("LEFT", 8, 0)
    r.icon = r.box.tex
    -- A mark at the end of the row, so a state never shows by colour alone: an empty ring when
    -- the module is off or paused, an orange dot while it waits for a reload, a red one when
    -- the game refuses it, a gold one when it was updated since the player last opened it.
    r.ring = S.Circle(r, 8, S.FAINT, "ARTWORK")
    r.ring:SetPoint("RIGHT", -10, 0)
    r.hole = S.Circle(r, 6, S.SIDE, "OVERLAY")
    r.hole:SetPoint("CENTER", r.ring, "CENTER")
    r.dot = S.Circle(r, 8, S.GOLD, "OVERLAY", 1)
    r.dot:SetPoint("RIGHT", -10, 0)
    r.title = S.Text(r, 13)
    r.title:SetPoint("LEFT", r.box, "RIGHT", 9, 0)
    r.title:SetPoint("RIGHT", -22, 0)
    r.title:SetWordWrap(false)
    r:SetScript("OnClick", function(self) enter(self.row) end)
    r:SetScript("OnEnter", function(self)
        if not self.selected then S.Fill(self, HOVER) end
        rowTip(self)
    end)
    rows[i] = r
    return r
end

local function fillRow(r, row)
    r.row = row
    r.icon:SetTexture(row.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    local live = row.state == "ready" and not row.paused
    r.icon:SetDesaturated(not live)
    r.box:SetAlpha(live and 1 or 0.6)
    r.title:SetText(row.title)
    -- The state shows in the name's colour and the mark at the end; the tooltip and the page
    -- say why. The switch itself is in the header of the module's page.
    local tc, dot = S.TEXT, nil
    if row.state == "reload" then tc, dot = WAIT, WAIT
    elseif row.state == "blocked" then tc, dot = BAD, BAD
    elseif not live then tc = S.FAINT
    elseif row.new then dot = S.GOLD end
    r.title:SetTextColor(tc[1], tc[2], tc[3], 1)
    if dot then r.dot:SetVertexColor(dot[1], dot[2], dot[3], 1) end
    r.dot:SetShown(dot ~= nil)
    local ring = not live and dot == nil
    r.ring:SetShown(ring)
    r.hole:SetShown(ring)
    r:SetSelected(view.page == "module" and view.inside == row.key)
    r:Show()
end

local function makeHead(i)
    local h = CreateFrame("Frame", nil, list)
    h:SetHeight(HEAD_H)
    -- A section label in bold dim gold capitals with the count at the right, like the cards'.
    h.count = S.Text(h, 12, S.FAINT)
    h.count:SetPoint("BOTTOMRIGHT", -8, 5)
    h.count:SetJustifyH("RIGHT")
    h.text = S.Text(h, 12, S.GOLD_DIM, nil, "bold")
    h.text:SetPoint("BOTTOMLEFT", 8, 5)
    h.text:SetPoint("RIGHT", h.count, "LEFT", -6, 0)
    h.text:SetWordWrap(false)
    heads[i] = h
    return h
end

local function fillSide(data)
    local searching = view.query ~= ""
    local shown = ns.Filter(data, "All", "all", view.query)
    local counts = ns.Counts(data)
    local y, ri, hi = 0, 0, 0
    local selY
    homeRow:SetShown(not searching)
    setupRow:SetShown(not searching)
    -- While searching, a row says how many tweaks the words find; a click shows them.
    local found = searching and #ns.TweakFilter(ns.TweakRows(data), "all", view.query) or 0
    tweaksRow:SetShown(not searching or found > 0)
    tweaksRow.text:SetText(searching and (L.TW_PAGE .. "  " .. S.Emph(tostring(found))) or L.TW_PAGE)
    if searching and found > 0 then
        place(tweaksRow, y)
        tweaksRow:SetSelected(false)
        y = y + ROW_H
    end
    if not searching then
        place(homeRow, y)
        homeRow:SetSelected(view.page == "home")
        if view.page == "home" then selY = y end
        y = y + ROW_H
        place(tweaksRow, y)
        tweaksRow:SetSelected(view.page == "tweaks")
        if view.page == "tweaks" then selY = y end
        y = y + ROW_H
        place(setupRow, y)
        setupRow:SetSelected(view.page == "setup")
        if view.page == "setup" then selY = y end
        y = y + ROW_H
    end
    for _, g in ipairs(ns.Groups(shown)) do
        hi = hi + 1
        local h = heads[hi] or makeHead(hi)
        local c = counts[g.key] or { on = 0, total = 0 }
        h.cat = g.key
        h.text:SetText(S.Upper(catName(g.key)))
        h.count:SetText(c.on .. "/" .. c.total)
        place(h, y)
        h:Show()
        y = y + HEAD_H
        for _, row in ipairs(g.rows) do
            ri = ri + 1
            local r = rows[ri] or makeRow(ri)
            fillRow(r, row)
            place(r, y)
            if r.selected then selY = y end
            y = y + ROW_H
        end
    end
    for i = ri + 1, #rows do rows[i]:Hide() end
    for i = hi + 1, #heads do heads[i]:Hide() end
    moveSel(selY)
    empty:SetShown(#shown == 0 and found == 0)
    list:SetHeight(math.max(1, y))
    scroll:Update(y)
    return shown
end

-- The card beside a narrow module window --------------------------------------------------------

local function fillCard(row)
    local d = card
    d.row = row
    d.icon:SetTexture(row.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    d.icon:SetDesaturated(row.state ~= "ready")
    d.title:SetText(row.title)
    d.cat:Set(catName(row.category))
    local st, color = stateText(row)
    d.state:Set(st, color)
    d.desc:SetText(row.desc)
    d.slash:SetText(row.slash and L.COMMAND:format(row.slash) or "")
    local facts = {}
    if row.version then facts[#facts + 1] = L.VERSION:format(row.version) end
    local mem = row.state == "ready" and ns.Memory(row)
    if mem then facts[#facts + 1] = L.MEMORY:format(mem) end
    d.facts:SetText(table.concat(facts, "   "))
    local canReset = row.state == "ready" and row.info and type(row.info.reset) == "function"
    d.reset:SetShown(canReset)
    -- Bottom up: open alone, load in the game, reload when waiting, reset.
    local canLoad = row.canPause or (row.running and not row.loadOn)
    d.load:SetShown(canLoad == true)
    d.load:SetText(row.loadOn and L.UNLOAD or L.LOAD)
    d.reload:ClearAllPoints()
    local below = canLoad and d.load or d.pop
    d.reload:SetPoint("BOTTOMLEFT", below, "TOPLEFT", 0, 8)
    d.reload:SetPoint("BOTTOMRIGHT", below, "TOPRIGHT", 0, 8)
    d.reload:SetShown(row.state == "reload")
    below = row.state == "reload" and d.reload or below
    d.reset:ClearAllPoints()
    d.reset:SetPoint("BOTTOMLEFT", below, "TOPLEFT", 0, 8)
    d.reset:SetPoint("BOTTOMRIGHT", below, "TOPRIGHT", 0, 8)
    if d.resetFor ~= row.key then
        d.resetFor, d.armed = row.key, false
        d.reset:SetText(L.RESET)
    end
    d.pop:SetEnabled(insideWin ~= offWin)
end

-- The home page ---------------------------------------------------------------------------------
-- A dashboard: the Ready card (a ring and a bar per check) and the session card (a graph) on
-- top, the modules' news as number tiles under them, then the Recent feed and the Modules card.

local tiles, feedLines, ovLines = {}, {}, {}
local TOP_H, SIDE_W = 196, 320
local RING, TICKS = 128, 72
local ARC = "Interface\\AddOns\\Gulli-Toolkit\\Art\\Arc"
local TRACK = { 0, 0, 0, 0.45 }
local TONE = { bad = S.BAD, warn = S.WARN, good = S.GOOD }
local WHITE = { 1, 1, 1, 1 }

local function paint(t, c, a)
    t:SetVertexColor(c[1], c[2], c[3], a or c[4] or 1)
end

-- A thin bar: a dark track, a fill and, when the value has a limit, a mark where it sits.
local function makeBar(parent, h)
    local b = CreateFrame("Frame", nil, parent)
    b:SetHeight(h)
    local track = S.Tex(b, "BACKGROUND", 0, TRACK)
    track:SetAllPoints()
    b.fill = S.Tex(b, "ARTWORK", 0, S.GOOD)
    b.fill:SetPoint("TOPLEFT")
    b.fill:SetPoint("BOTTOMLEFT")
    b.extra = S.Tex(b, "ARTWORK", 0, S.GOOD)
    b.extra:SetPoint("TOPLEFT", b.fill, "TOPRIGHT")
    b.extra:SetPoint("BOTTOMLEFT", b.fill, "BOTTOMRIGHT")
    b.extra:Hide()
    b.mark = S.Tex(b, "OVERLAY", 0, S.MUTED)
    b.mark:SetSize(2, h + 6)
    b.mark:Hide()
    -- width: the bar's own, as its frame may not be laid out yet.
    function b:Set(width, frac, color, mark, extra, extraColor)
        self:SetWidth(width)
        frac = math.max(0, math.min(1, frac or 0))
        self.fill:SetWidth(math.max(1, math.floor(width * frac + 0.5)))
        self.fill:SetShown(frac > 0)
        paint(self.fill, color)
        self.mark:SetShown(mark ~= nil)
        if mark then
            self.mark:ClearAllPoints()
            self.mark:SetPoint("CENTER", self, "LEFT", math.floor(width * mark + 0.5), 0)
        end
        local ew = math.floor(width * math.max(0, math.min(1 - frac, extra or 0)) + 0.5)
        self.extra:SetShown(ew > 0 and frac > 0)
        if ew > 0 then
            self.extra:SetWidth(ew)
            paint(self.extra, extraColor or color)
        end
    end
    return b
end

-- The Ready card: a ring with a run of marks per check and the count in its middle, and a
-- bar per check beside it, the ones not met first. Returns false when it is switched off.
local meters, ringTicks = {}, {}

local function makeMeter(i)
    local m = CreateFrame("Frame", nil, home.ready.body)
    m:SetHeight(32)
    m.icon = S.IconBox(m, 22)
    m.icon:SetPoint("TOPLEFT")
    m.value = S.Text(m, 13, S.TEXT, nil, "bold")
    m.value:SetPoint("RIGHT", m, "TOPRIGHT", 0, -11)
    m.value:SetJustifyH("RIGHT")
    m.value:SetWordWrap(false)
    m.label = S.Text(m, 13, S.MUTED)
    m.label:SetPoint("LEFT", m.icon, "RIGHT", 8, 0)
    m.label:SetPoint("RIGHT", m.value, "LEFT", -6, 0)
    m.label:SetWordWrap(false)
    m.bar = makeBar(m, 5)
    m.bar:SetPoint("BOTTOMLEFT")
    m:EnableMouse(true)
    m:SetScript("OnEnter", function(self) if self.text then tip(self, self.text, {}) end end)
    m:SetScript("OnLeave", hideTip)
    meters[i] = m
    return m
end

local function fillRing(list)
    local marks = ns.RingTicks(list, TICKS)
    for k = 1, TICKS do
        local t = ringTicks[k]
        if not t then
            t = home.ring:CreateTexture(nil, "ARTWORK")
            t:SetTexture(ARC)
            t:SetAllPoints(home.ring)
            -- clockwise from the top; a positive rotation turns the other way
            t:SetRotation(-math.rad((k - 0.5) * 360 / TICKS))
            ringTicks[k] = t
        end
        local on = marks[k]
        if on == nil then paint(t, TRACK) else paint(t, on and S.GOOD or S.BAD, 1) end
    end
end

local function fillReady(width)
    local card = home.ready
    if not ns.ReadyGet("show") then card:Hide() return false end
    card:Show()
    card:SetWidth(width)
    local list = {}
    for _, r in ipairs(ns.Readiness()) do if not r.ok then list[#list + 1] = r end end
    for _, r in ipairs(ns.Readiness()) do if r.ok then list[#list + 1] = r end end
    local ok, n = ns.ReadyCount(list)
    fillRing(list)
    home.ringCount:SetText(ok)
    home.ringOf:SetText("/" .. n)
    home.ringNote:SetText(ok == n and L.RD_ALL or L.RD_FIX:format(n - ok))
    local nc = ok == n and S.GOOD or S.WARN
    home.ringNote:SetTextColor(nc[1], nc[2], nc[3], 1)
    -- The meters: two columns beside the ring, more when the card has the whole width.
    local left = RING + 22
    local room = width - 2 * S.INSET - left
    local cols = math.max(2, math.floor((room + 18) / 172))
    local w = math.floor((room - (cols - 1) * 18) / cols)
    local rows = math.max(1, math.ceil(#list / cols))
    local bodyH = TOP_H - 36 - S.INSET
    local pitch = math.min(42, math.floor((bodyH + 6) / rows))
    for i, r in ipairs(list) do
        local m = meters[i] or makeMeter(i)
        m.icon:SetIcon(r.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        m.label:SetText(r.label)
        m.value:SetText(r.value)
        local lc, vc = r.ok and S.MUTED or WHITE, r.ok and S.TEXT or S.BAD
        m.label:SetTextColor(lc[1], lc[2], lc[3], 1)
        m.value:SetTextColor(vc[1], vc[2], vc[3], 1)
        m.bar:Set(w, r.frac, r.ok and S.GOOD or S.BAD, r.mark)
        m.text = r.text
        m:SetWidth(w)
        m:ClearAllPoints()
        m:SetPoint("TOPLEFT", left + ((i - 1) % cols) * (w + 18), -math.floor((i - 1) / cols) * pitch)
        m:Show()
    end
    for i = #list + 1, #meters do meters[i]:Hide() end
    return true
end

-- The session card (ns.SessionCard): the leading number big with its columns beside it, a line
-- under it, up to ns.SES_STATS small tiles, a quiet line of facts and the bar of the level. A
-- session with nothing in it yet says what will come. Returns the card's data.
local columns, sesStats = {}, {}
local COL_H, COL_W, COL_GAP = 30, 5, 3
local STAT_ICON, STAT_PAD, STAT_GAP = 20, 6, 10

local function makeStat(i)
    local t = CreateFrame("Frame", nil, home.sesStats)
    t:SetHeight(30)
    t.icon = S.IconBox(t, STAT_ICON)
    t.icon:SetPoint("LEFT", 0, 0)
    t.value = S.Text(t, 13, WHITE, nil, "bold")
    t.value:SetPoint("TOPLEFT", STAT_ICON + STAT_PAD, 0)
    t.value:SetWordWrap(false)
    t.label = S.Text(t, 12, S.FAINT)
    t.label:SetPoint("BOTTOMLEFT", STAT_ICON + STAT_PAD, 0)
    t.label:SetWordWrap(false)
    sesStats[i] = t
    return t
end

local function textWidth(fs) return math.ceil(tonumber(fs:GetStringWidth()) or 0) end

local function sessionTip(owner)
    local d = home.session.data
    if not d or d.empty then return end
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:SetText(L.SESSION, S.GOLD[1], S.GOLD[2], S.GOLD[3])
    GameTooltip:AddLine(d.span, S.FAINT[1], S.FAINT[2], S.FAINT[3])
    for _, g in ipairs(d.tip or {}) do
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine((g.icon and (S.TipIcon(g.icon) .. " ") or "") .. g.head, g.value, 1, 1, 1, 1, 1, 1)
        for _, r in ipairs(g.rows or {}) do
            local c = r[3] and S.BAD or S.TEXT
            GameTooltip:AddDoubleLine("    " .. r[1], r[2], S.MUTED[1], S.MUTED[2], S.MUTED[3], c[1], c[2], c[3])
        end
    end
    GameTooltip:Show()
end

local function fillSession(data, width)
    local card = home.session
    local d = ns.SessionCard(data)
    card.data = d
    card:Show()
    card:SetWidth(width)
    card:SetTitle(L.SESSION, d.span)
    local h = d.hero
    home.sesEmpty:SetShown(d.empty == true)
    home.sesFull:SetShown(not d.empty)
    if d.empty then return d end
    local inner = width - 2 * S.INSET
    home.sesValue:SetText(h.value)
    home.sesUnit:SetText(h.unit)
    home.sesLine:SetText(S.Emph(h.line, WHITE))

    -- The columns, at the right of the number; a young session grows from the left.
    local n = #h.bars
    local max = 0
    for _, v in ipairs(h.bars) do max = math.max(max, v) end
    local graph = n > 0 and max > 0
    home.sesGraph:SetShown(graph)
    if graph then
        local fill, last = S.FILL, S.Accent()
        for i = 1, n do
            local c = columns[i]
            if not c then
                c = S.Tex(home.sesGraph, "ARTWORK", 0, fill)
                columns[i] = c
            end
            c:ClearAllPoints()
            c:SetSize(COL_W, math.max(2, math.floor(COL_H * h.bars[i] / max + 0.5)))
            c:SetPoint("BOTTOMLEFT", (i - 1) * (COL_W + COL_GAP), 1)
            if i == n then paint(c, last, 1) else paint(c, fill, 0.8) end
            c:Show()
        end
    end
    for i = (graph and n or 0) + 1, #columns do columns[i]:Hide() end

    -- The small tiles side by side; labels give way when the row is too long.
    local ns_ = #d.stats
    home.sesStats:SetShown(ns_ > 0)
    local total = 0
    for i = 1, ns_ do
        local st = d.stats[i]
        local t = sesStats[i] or makeStat(i)
        t.icon:SetIcon(st.icon)
        t.value:SetWidth(0)
        t.label:SetWidth(0)
        t.value:SetText(st.value)
        t.label:SetText(st.label)
        t.textW, t.cut = math.max(textWidth(t.value), textWidth(t.label), 20) + 2, false
        total = total + STAT_ICON + STAT_PAD + t.textW
        t:Show()
    end
    total = total + math.max(0, ns_ - 1) * STAT_GAP
    -- Too long for the card: the widest text gives way, the others keep theirs.
    local over = total - inner
    while over > 0 do
        local widest
        for i = 1, ns_ do
            if not widest or sesStats[i].textW > widest.textW then widest = sesStats[i] end
        end
        if not widest or widest.textW <= 30 then break end
        local cut = math.min(over, widest.textW - 30)
        widest.textW, widest.cut, over = widest.textW - cut, true, over - cut
    end
    local x = 0
    for i = 1, ns_ do
        local t = sesStats[i]
        if t.cut then
            t.value:SetWidth(t.textW)
            t.label:SetWidth(t.textW)
        end
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", x, 0)
        t:SetWidth(STAT_ICON + STAT_PAD + t.textW)
        x = x + STAT_ICON + STAT_PAD + t.textW + STAT_GAP
    end
    for i = ns_ + 1, #sesStats do sesStats[i]:Hide() end

    -- The quiet line: as many facts as fit.
    local low, shown = home.sesLow, ""
    low:SetWidth(inner)
    for i, f in ipairs(d.facts) do
        local try = (i > 1 and (shown .. S.DOT) or "") .. f
        low:SetText(try)
        if i > 1 and textWidth(low) > inner then break end
        shown = try
    end
    low:SetText(shown)
    low:SetShown(shown ~= "")

    local p = h.progress
    home.sesBar:SetShown(p ~= nil)
    home.sesLeft:SetShown(p ~= nil)
    home.sesRight:SetShown(p ~= nil)
    low:ClearAllPoints()
    low:SetPoint("BOTTOMLEFT", 0, p and 20 or 2)
    if p then
        home.sesLeft:SetText(p.left)
        home.sesRight:SetText(p.right)
        local lw, rw = textWidth(home.sesLeft), textWidth(home.sesRight)
        local bw = inner - (lw > 0 and lw + 8 or 0) - (rw > 0 and rw + 8 or 0)
        home.sesBar:ClearAllPoints()
        home.sesBar:SetPoint("BOTTOMLEFT", lw > 0 and lw + 8 or 0, 4)
        home.sesBar:Set(bw, p.value, S.XP, nil, p.extra, { 0.35, 0.59, 1, 0.55 })
    end
    return d
end

-- A tile: the key number big in the colour of its tone, the module's name, one short line
-- (or a row of pips), and the module's icon at the right.
local TILE_COLS, TILE_H, TILE_GAP = 3, 62, 8

local function makeTile(i)
    local t = CreateFrame("Button", nil, home.summary)
    t:SetSize(10, TILE_H)
    -- No edge: a tile stands out from the window by its shade only.
    S.Box(t, S.SURFACE, S.CLEAR, S.R_LG)
    S.Depth(t, S.R_LG)
    t.value = S.Text(t, 28, WHITE, nil, "title")
    t.value:SetPoint("LEFT", 14, 0)
    t.value:SetWordWrap(false)
    t.icon = S.IconBox(t, 26)
    t.icon:SetPoint("RIGHT", -12, 0)
    t.name = S.Text(t, 12, S.GOLD, nil, "bold")
    t.name:SetWordWrap(false)
    t.text = S.Text(t, 13, S.MUTED)
    t.text:SetPoint("TOPLEFT", t.name, "BOTTOMLEFT", 0, -2)
    t.text:SetPoint("RIGHT", t.icon, "LEFT", -8, 0)
    t.text:SetJustifyV("TOP")
    t.pips = {}
    t:SetScript("OnClick", function(self) enter(self.row) end)
    -- The module's whole line in a tooltip, as the tile keeps it short.
    t:SetScript("OnEnter", function(self)
        S.Fill(self, S.RAISED)
        if self.row then tip(self, self.row.title, { self.full }, "ANCHOR_TOP") end
    end)
    t:SetScript("OnLeave", function(self) S.Fill(self, S.SURFACE); hideTip() end)
    tiles[i] = t
    return t
end

local function fillTile(t, e)
    t.row, t.full = e.row, e.text
    t.icon:SetIcon(e.icon or e.row.icon)
    t.name:SetText(S.Upper(e.row.title))
    t.value:SetShown(e.value ~= nil)
    t.name:ClearAllPoints()
    local x = 14
    if e.value then
        t.value:SetText(e.value)
        local c = TONE[e.tone or ""] or WHITE
        t.value:SetTextColor(c[1], c[2], c[3], 1)
        x = x + math.max(34, math.ceil(tonumber(t.value:GetStringWidth()) or 0)) + 11
    end
    local have, of = 0, 0
    if e.pips then have, of = e.pips[1], e.pips[2] end
    t.text:SetShown(of == 0)
    -- A line too long for the tile takes two lines (never cut mid-word), the name moves up.
    t.text:SetWordWrap(false)
    t.text:SetText(S.Emph(e.label, S.TEXT))
    local room = t.width - x - 12 - 26 - 8
    local two = of == 0 and (tonumber(t.text:GetStringWidth()) or 0) > room
    t.text:SetWordWrap(two)
    t.text:SetMaxLines(two and 2 or 1)
    t.name:SetPoint("TOPLEFT", x, two and -7 or -14)
    t.name:SetPoint("RIGHT", t.icon, "LEFT", -8, 0)
    for k = 1, of do
        local p = t.pips[k]
        if not p then
            p = S.Tex(t, "ARTWORK", 0, S.GOOD)
            p:SetSize(14, 5)
            t.pips[k] = p
        end
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", t.name, "BOTTOMLEFT", (k - 1) * 17, -7)
        paint(p, k <= have and (TONE[e.tone or ""] or S.GOOD) or S.OFF, 1)
        p:Show()
    end
    for k = of + 1, #t.pips do t.pips[k]:Hide() end
end

-- A line of the Recent feed: the module's icon, its name and the newest text, how many lines
-- it stands for, and how long ago at the right.
local FEED_H = 32
local function makeFeedLine(i)
    local b = CreateFrame("Button", nil, home.recent.body)
    b:SetHeight(FEED_H)
    S.Box(b, S.CLEAR, S.CLEAR, S.R_MD)
    b.icon = S.IconBox(b, 22)
    b.icon:SetPoint("LEFT", 2, 0)
    b.ago = S.Text(b, 12, S.FAINT)
    b.ago:SetPoint("RIGHT", -4, 0)
    b.ago:SetJustifyH("RIGHT")
    b.ago:SetWordWrap(false)
    b.text = S.Text(b, 13, S.MUTED)
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 10, 0)
    b.text:SetPoint("RIGHT", b.ago, "LEFT", -8, 0)
    b.text:SetWordWrap(false)
    b.rule = S.Tex(b, "ARTWORK", 0, LINE)
    b.rule:SetHeight(1)
    b.rule:SetPoint("BOTTOMLEFT")
    b.rule:SetPoint("BOTTOMRIGHT")
    b:SetScript("OnClick", function(self) enter(findRow(self.key)) end)
    b:SetScript("OnEnter", function(self)
        S.Fill(self, HOVER)
        tip(self, self.who, { self.full }, "ANCHOR_TOP")
    end)
    b:SetScript("OnLeave", function(self) S.Fill(self, S.CLEAR); hideTip() end)
    feedLines[i] = b
    return b
end

local function fillFeed(height)
    local feed = ns.FeedRows()
    local room = math.max(1, math.floor((height - 36 - S.INSET) / FEED_H))
    local now = time()
    local shown = math.min(#feed, room)
    for i = 1, shown do
        local b = feedLines[i] or makeFeedLine(i)
        local e = feed[i]
        local who = tostring(e.key or "")
        if ns.T.en["M_" .. who] then who = L["M_" .. who] end
        local row = findRow(e.key)
        b.key, b.who, b.full = e.key, who, e.text
        b.icon:SetIcon((row and row.icon) or TOOLKIT_ICON)
        b.ago:SetText(ns.Ago(e.t, now))
        b.text:SetText(S.Hex(S.TEXT) .. who .. "|r  " .. e.text ..
            (e.n > 1 and ("  " .. S.Hex(S.FAINT) .. "x" .. e.n .. "|r") or ""))
        b.rule:SetShown(i < shown)
        place(b, (i - 1) * FEED_H)
        b:Show()
    end
    for i = shown + 1, #feedLines do feedLines[i]:Hide() end
    home.noRecent:SetShown(#feed == 0)
    home.clear:SetShown(#feed > 0)
end

-- A line of the Modules card: text, a tooltip with the whole text, and a click that opens the
-- module it names.
local function makeLine(parent, list, i, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(LINE_H)
    S.Box(b, S.CLEAR, S.CLEAR, S.R_MD)
    b.text = S.Text(b, size or 13, S.MUTED)
    b.text:SetPoint("LEFT", 4, 0)
    b.text:SetPoint("RIGHT", -4, 0)
    b.text:SetWordWrap(false)
    b:SetScript("OnClick", function(self)
        if self.open then self.open() elseif self.row then enter(self.row) end
    end)
    b:SetScript("OnEnter", function(self)
        if self.row or self.open then S.Fill(self, HOVER) end
        if self.full then tip(self, self.head, { self.full }, "ANCHOR_TOP") end
    end)
    b:SetScript("OnLeave", function(self) S.Fill(self, S.CLEAR); hideTip() end)
    list[i] = b
    return b
end

-- The lines of the Modules card from ns.Overview, only what the player should know: errors,
-- what waits for a reload, what the game refuses, what is paused and what was updated.
-- { { head, color, names, row, open } }
local function overviewLines(o)
    local out = {}
    if (o.errors or 0) > 0 then
        local seen, t = {}, {}
        for _, e in ipairs(ns.Errors()) do
            local name = ns.ShortName and ns.ShortName(e.addon) or e.addon
            if not seen[name] then seen[name] = true; t[#t + 1] = name end
        end
        out[#out + 1] = { L.OV_ERRORS .. " " .. o.errors, S.BAD, table.concat(t, ", "), nil,
                          function() ns.OpenErrors() end }
    end
    local function names(rows, extra)
        local t = {}
        for _, r in ipairs(rows) do t[#t + 1] = r.title .. (extra and extra(r) or "") end
        return table.concat(t, ", ")
    end
    if #o.reload > 0 then out[#out + 1] = { L.OV_RELOAD, S.WARN, names(o.reload), o.reload[1] } end
    if #o.blocked > 0 then
        out[#out + 1] = { L.OV_BLOCKED, S.BAD,
            names(o.blocked, function(r) return " (" .. ns.ReasonText(r.reason) .. ")" end), o.blocked[1] }
    end
    if #o.paused > 0 then out[#out + 1] = { L.OV_PAUSED, S.MUTED, names(o.paused), o.paused[1] } end
    if #o.new > 0 then
        out[#out + 1] = { L.OV_NEW, S.GOOD, names(o.new, function(r) return " " .. r.version end), o.new[1] }
    end
    return out
end

-- One pip per module across the card: green runs, dark is off or paused, orange waits for a
-- reload, red is refused by the game.
local pips = {}
local PIP_GAP = 2
local function fillPips(data, width)
    local n = #data
    local w = math.max(2, math.floor((width - (n - 1) * PIP_GAP) / math.max(1, n)))
    for i, r in ipairs(data) do
        local p = pips[i]
        if not p then
            p = S.Tex(home.ovPips, "ARTWORK", 0, S.GOOD)
            pips[i] = p
        end
        local c = S.OFF
        if r.state == "blocked" then c = S.BAD
        elseif r.state == "reload" then c = S.WARN
        elseif r.state == "ready" and not r.paused then c = S.GOOD end
        paint(p, c, 1)
        p:SetSize(w, 8)
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", (i - 1) * (w + PIP_GAP), 0)
        p:Show()
    end
    for i = n + 1, #pips do pips[i]:Hide() end
end

-- The heaviest modules as bars, the first one full: name at the left, memory at the right.
local heavyBars = {}
local HEAVY_H, HEAVY_MAX = 24, 3
local function makeHeavy(i)
    local b = CreateFrame("Button", nil, home.overview.body)
    b:SetHeight(HEAVY_H)
    local track = S.Tex(b, "BACKGROUND", 0, TRACK)
    track:SetAllPoints()
    b.fill = S.Tex(b, "ARTWORK", 0, S.FILL)
    b.fill:SetPoint("TOPLEFT")
    b.fill:SetPoint("BOTTOMLEFT")
    b.size = S.Text(b, 13, S.MUTED)
    b.size:SetPoint("RIGHT", -8, 0)
    b.size:SetJustifyH("RIGHT")
    b.name = S.Text(b, 13)
    b.name:SetPoint("LEFT", 8, 0)
    b.name:SetPoint("RIGHT", b.size, "LEFT", -8, 0)
    b.name:SetWordWrap(false)
    b:SetScript("OnClick", function(self) enter(self.row) end)
    b:SetScript("OnEnter", function(self) tip(self, L.OV_HEAVY, { self.row and self.row.title }, "ANCHOR_TOP") end)
    b:SetScript("OnLeave", hideTip)
    heavyBars[i] = b
    return b
end

local function fillOverview(data, height)
    local o = ns.Overview(data)
    local width = SIDE_W - 2 * S.INSET
    home.ovCount:SetText(o.on)
    home.ovTotal:SetText("/ " .. o.total)
    home.ovMemory:SetText(o.kb > 0 and S.Emph(ns.Size(o.kb), WHITE) or "")
    fillPips(data, width)
    home.ovReload:SetShown(#o.reload > 0)
    local room = height - 36 - S.INSET - 64
    -- What needs the player comes first; the memory bars take the room that is left.
    local lines = overviewLines(o)
    local nl = math.min(#lines, math.max(0, math.floor(room / 22)))
    local nb = math.min(#o.heavy, HEAVY_MAX, math.max(0, math.floor((room - nl * 22 + 5) / (HEAVY_H + 5))))
    local y = 64
    local top = (o.heavy[1] and o.heavy[1].kb) or 1
    for i = 1, nb do
        local b = heavyBars[i] or makeHeavy(i)
        local h = o.heavy[i]
        b.row = h.row
        b.name:SetText(h.row.title)
        b.size:SetText(ns.Size(h.kb))
        b.fill:SetWidth(math.max(2, math.floor(width * h.kb / math.max(1, top) + 0.5)))
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 0, -y)
        b:SetPoint("TOPRIGHT", 0, -y)
        b:Show()
        y = y + HEAVY_H + 5
    end
    for i = nb + 1, #heavyBars do heavyBars[i]:Hide() end
    if nb > 0 then y = y + 3 end
    for i = 1, nl do
        local e = lines[i]
        local b = ovLines[i] or makeLine(home.overview.body, ovLines, i)
        b.head, b.full, b.row, b.open = e[1], e[3] ~= "" and e[3] or nil, e[4], e[5]
        b.text:SetText(S.Hex(e[2]) .. e[1] .. "|r" .. (e[3] ~= "" and ("  " .. e[3]) or ""))
        b:SetHeight(22)
        place(b, y)
        b:Show()
        y = y + 22
    end
    for i = nl + 1, #ovLines do ovLines[i]:Hide() end
end

local function fillHome(data)
    -- The top row: Ready and the session side by side, or the one that shows across the width.
    local ses = fillSession(data, SIDE_W)
    local ready = fillReady(HOST_W - SIDE_W - GAP)
    if not ready then
        home.session:SetWidth(HOST_W)
        fillSession(data, HOST_W)
    end
    local top = TOP_H + GAP

    local shown = {}
    if ready then for _, r in ipairs(ns.Readiness()) do shown[r.key] = true end end
    local list2 = ns.Tiles(data, shown, ses.hero and ses.hero.row and ses.hero.row.key or nil)
    local n = #list2
    local w = math.floor((HOST_W - (TILE_COLS - 1) * TILE_GAP) / TILE_COLS)
    for i = 1, n do
        local t = tiles[i] or makeTile(i)
        t.width = w
        fillTile(t, list2[i])
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", ((i - 1) % TILE_COLS) * (w + TILE_GAP),
            -math.floor((i - 1) / TILE_COLS) * (TILE_H + TILE_GAP))
        t:SetSize(w, TILE_H)
        t:Show()
    end
    for i = n + 1, #tiles do tiles[i]:Hide() end
    home.noSummary:SetShown(n == 0)
    local lines = math.max(1, math.ceil(n / TILE_COLS))
    local inner = n == 0 and 36 or (lines * (TILE_H + TILE_GAP) - TILE_GAP)
    local sh = LABEL_H + inner
    home.summaryCard:ClearAllPoints()
    home.summaryCard:SetPoint("TOPLEFT", 0, -top)
    home.summaryCard:SetPoint("TOPRIGHT", 0, -top)
    home.summaryCard:SetHeight(sh)

    local rest = HOST_H - top - sh - GAP
    home.recent:SetHeight(rest)
    home.overview:SetHeight(rest)
    fillOverview(data, rest)
    fillFeed(rest)
end

-- The whole window -----------------------------------------------------------------------------

local function applyScale()
    local sw = tonumber(UIParent:GetWidth()) or W
    local sh = tonumber(UIParent:GetHeight()) or H
    local user = (GulliToolkitDB and GulliToolkitDB.scale) or 1
    S.ApplyScale(frame, ns.HubScale(user, sw, sh, W, H))
    if scaleText then scaleText:SetText(math.floor(user * 100 + 0.5) .. "%") end
end

local function nudgeScale(step)
    GulliToolkitDB = GulliToolkitDB or {}
    local v = (GulliToolkitDB.scale or 1) + step
    GulliToolkitDB.scale = math.max(0.7, math.min(1.3, math.floor(v * 10 + 0.5) / 10))
    applyScale()
end

function ns.Refresh()
    if not frame or not frame:IsShown() then return end
    local data = ns.List()
    fillSide(data)
    if view.inside then
        local row
        for _, r in ipairs(data) do if r.key == view.inside then row = r end end
        if row then
            hubSwitch:SetChecked(row.on)
            pinBox.switch:SetChecked(ns.Pinned(row.key))
            if insideWin == offWin then offWindow(row) end
            if card:IsShown() then fillCard(row) end
        end
    end
    if view.page == "home" then fillHome(data) end

    if view.page == "setup" and setupFrame then fillSetup(data) end
    if view.page == "tweaks" then ns.FillTweaks(data) end
    -- How many frames show on the screen, beside the link that places them.
    local fon, ftotal = ns.FrameCount()
    unlockLink:Set(ns.moving and L.MOVE_DONE or L.UNLOCK, ftotal > 0 and (fon .. "/" .. ftotal) or "")
    if protectFrame and protectFrame:IsShown() then ns.RefreshProtected() end
end

-- Protected items: a page in the centre, with a drop zone for items from the bags.
local protRows = {}
local function itemInfo(id)
    local _, _, _, _, _, _, _, _, _, icon = (C_Item and C_Item.GetItemInfo or GetItemInfo)(id)
    if not icon and C_Item and C_Item.GetItemIconByID then icon = C_Item.GetItemIconByID(id) end
    return ns.ItemName(id), icon
end

function ns.RefreshProtected()
    local ids = ns.Protected()
    table.sort(ids, function(a, b)
        local na, nb = itemInfo(a) or "", itemInfo(b) or ""
        if na ~= nb then return na < nb end
        return a < b
    end)
    for i, id in ipairs(ids) do
        local r = protRows[i]
        if not r then
            r = CreateFrame("Frame", nil, protectFrame.list)
            r:SetHeight(30)
            r:SetPoint("TOPLEFT", 0, -(i - 1) * 32)
            r:SetPoint("TOPRIGHT", 0, -(i - 1) * 32)
            S.Box(r, S.ROW, { 0, 0, 0, 0 }, S.R_MD)
            r.iconBox = S.IconBox(r, 22)
            r.iconBox:SetPoint("LEFT", 6, 0)
            r.icon = r.iconBox.tex
            r.remove = S.Button(r, 76, 28)
            r.remove:SetPoint("RIGHT", -1, 0)
            r.remove:SetText(L.REMOVE)
            r.remove:SetScript("OnClick", function(self) GulliToolkit.Protect(self:GetParent().id, false) end)
            r.name = S.Text(r, 12)
            r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
            r.name:SetPoint("RIGHT", r.remove, "LEFT", -6, 0)
            r.name:SetWordWrap(false)
            protRows[i] = r
        end
        r.id = id
        local name, icon = itemInfo(id)
        r.name:SetText(name or "...")
        r.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        r:Show()
    end
    for i = #ids + 1, #protRows do protRows[i]:Hide() end
    protectFrame.list:SetHeight(math.max(1, #ids * 32))
    protectFrame.scroll:Update(#ids * 32)
end

local function dropItem()
    local kind, id = GetCursorInfo()
    if kind == "item" and id then
        GulliToolkit.Protect(id, true)
        ClearCursor()
    end
end

-- A page in the centre with a title and a close button that goes home.
local function centrePage(name, title)
    local p = CreateFrame("Frame", name, host)
    p:SetAllPoints(host)
    p:EnableMouse(true)
    S.Box(p, S.SURFACE, S.EDGE, S.R_LG)
    p.title = S.Text(p, 14)
    p.title:SetPoint("TOPLEFT", S.INSET, -14)
    p.title:SetText(title)
    -- A page opened from the Setup page goes back there.
    local close = S.Close(p, function()
        if view.from == "setup" and view.page ~= "setup" and setupFrame then showPanel("setup") else showHome() end
    end)
    close:SetPoint("TOPRIGHT", -6, -6)
    p.hint = S.Note(p, 12)
    p.hint:SetPoint("TOPLEFT", p.title, "BOTTOMLEFT", 0, -8)
    p.hint:SetPoint("RIGHT", -S.INSET - 30, 0)
    p.hint:SetMaxLines(3)
    p:Hide()
    return p
end

local function buildProtected()
    protectFrame = centrePage("GulliToolkitProtected", L.PROTECTED)
    protectFrame.hint:SetText(L.PROTECT_HINT)
    local drop = S.DropZone(protectFrame, L.DROP, dropItem, 44)
    drop:SetPoint("TOPLEFT", S.INSET, -84)
    drop:SetPoint("TOPRIGHT", -S.INSET, -84)
    protectFrame.scroll = S.Scroll(protectFrame)
    protectFrame.scroll:SetPoint("TOPLEFT", drop, "BOTTOMLEFT", 0, -S.GAP)
    protectFrame.scroll:SetPoint("BOTTOMRIGHT", -22, S.INSET)
    protectFrame.list = protectFrame.scroll.child
    protectFrame.list:SetWidth(HOST_W - 2 * S.INSET - 10)
    protectFrame:SetScript("OnShow", ns.RefreshProtected)
end

-- The Ready page: the thresholds of the checks and the switches.
function ns.BuildReady()
    readyFrame = centrePage("GulliToolkitReady", L.READY)
    readyFrame.hint:SetText(L.READY_HINT)
    local function stepper(key, step, min, max, fmt)
        return S.Stepper(readyFrame, function() return ns.ReadyGet(key) end,
            function(v) ns.ReadySet(key, v) end, step, min, max, fmt)
    end
    local pct = function(v) return v .. "%" end
    local I = "Interface\\Icons\\"
    local rows = {}
    for _, x in ipairs({ { "durMin", L.RD_SET_DUR, 10, 10, 100, pct, ns.READY_ICON.REPAIR },
                         { "bagsMin", L.RD_SET_BAGS, 1, 0, 30, nil, ns.READY_ICON.BAGS },
                         { "foodMin", L.RD_SET_FOOD, 5, 0, 100, nil, ns.READY_ICON.FOOD },
                         { "drinkMin", L.RD_SET_DRINK, 5, 0, 100, nil, ns.READY_ICON.DRINK },
                         { "ammoMin", L.RD_SET_AMMO, 100, 0, 3000, nil, ns.READY_ICON.AMMO },
                         { "shardsMin", L.RD_SET_SHARDS, 1, 0, 30, nil, ns.READY_ICON.SHARDS },
                         { "reagentMin", L.RD_SET_REAGENT, 1, 0, 40, nil, ns.READY_ICON.REAGENT } }) do
        rows[#rows + 1] = { x[2], nil, control = stepper(x[1], x[3], x[4], x[5], x[6]), icon = x[7] }
    end
    local w = math.floor((HOST_W - 2 * S.INSET - GAP) / 2)
    local left, lh = S.SettingsCard(readyFrame, L.RD_THRESHOLDS, rows)
    left:SetPoint("TOPLEFT", S.INSET, -84)
    left:SetWidth(w)
    left:SetHeight(lh)
    local sw = {
        { L.RD_SHOW, L.RD_SHOW_D, function() return ns.ReadyGet("show") end, function(v) ns.ReadySet("show", v) end,
          icon = I .. "INV_Misc_Note_01" },
        { L.RD_CLASS, L.RD_CLASS_D, function() return ns.ReadyGet("classCheck") end,
          function(v) ns.ReadySet("classCheck", v) end, icon = I .. "INV_Misc_Bag_10" },
    }
    local right, rh = S.SettingsCard(readyFrame, L.RD_SWITCHES, sw)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", GAP, 0)
    right:SetWidth(w)
    right:SetHeight(rh)
    readyFrame.steppers = rows
    readyFrame:SetScript("OnShow", function()
        for _, r in ipairs(rows) do if r.control.Refresh then r.control:Refresh() end end
    end)
    local reset = S.Ghost(S.FitButton(readyFrame, L.RD_RESET, 28, 120))
    reset:SetPoint("BOTTOMRIGHT", -S.INSET, S.INSET)
    reset:SetScript("OnClick", function()
        ns.ReadyReset()
        for _, r in ipairs(rows) do if r.control.Refresh then r.control:Refresh() end end
    end)
end

-- Export / import: one line of text with every Gulli setting.
local function buildTransfer()
    transfer = centrePage("GulliToolkitTransfer", L.TRANSFER)
    transfer.hint:SetText(L.TRANSFER_HINT)
    local memo = S.Memo(transfer, HOST_W - 2 * S.INSET, HOST_H - 84 - 64)
    memo:SetPoint("TOPLEFT", S.INSET, -84)
    transfer.memo = memo
    local import = S.FitButton(transfer, L.IMPORT, 32, 120)
    import:SetPoint("BOTTOMRIGHT", -S.INSET, S.INSET)
    local export = S.Primary(S.FitButton(transfer, L.EXPORT, 32, 120))
    export:SetPoint("RIGHT", import, "LEFT", -8, 0)
    local reload = S.Primary(S.FitButton(transfer, L.RELOAD, 32, 120))
    reload:SetPoint("RIGHT", export, "LEFT", -8, 0)
    reload:SetScript("OnClick", function() ReloadUI() end)
    reload:Hide()
    transfer.status = S.Note(transfer, 12)
    transfer.status:SetPoint("BOTTOMLEFT", S.INSET, S.INSET + 8)
    transfer.status:SetPoint("RIGHT", reload, "LEFT", -12, 0)
    transfer.status:SetMaxLines(2)
    local function status(text, c)
        c = c or S.MUTED
        transfer.status:SetText(text)
        transfer.status:SetTextColor(c[1], c[2], c[3], 1)
    end
    export:SetScript("OnClick", function()
        memo.edit:SetText(ns.Export())
        memo.edit:SetFocus()
        memo.edit:HighlightText()
        reload:Hide()
        status(L.COPY_HINT)
    end)
    import:SetScript("OnClick", function()
        local n = ns.Import(memo.edit:GetText())
        if n then
            status(L.IMPORT_OK:format(n), GOOD)
            reload:Show()
        else
            status(L.IMPORT_BAD, BAD)
            reload:Hide()
        end
    end)
    transfer:SetScript("OnShow", function()
        memo.edit:SetText("")
        reload:Hide()
        status("")
    end)
    transfer.export, transfer.import, transfer.reload = export, import, reload
end

-- The errors of the Gulli addons, as text to copy into a bug report.
local function buildErrors()
    errorsFrame = centrePage("GulliToolkitErrors", L.ERRORS)
    errorsFrame.hint:SetText(L.ERRORS_HINT)
    local memo = S.Memo(errorsFrame, HOST_W - 2 * S.INSET, HOST_H - 84 - 64)
    memo:SetPoint("TOPLEFT", S.INSET, -84)
    errorsFrame.memo = memo
    local copy = S.Primary(S.FitButton(errorsFrame, L.COPY, 32, 120))
    copy:SetPoint("BOTTOMRIGHT", -S.INSET, S.INSET)
    local clear = S.FitButton(errorsFrame, L.CLEAR, 32, 120)
    clear:SetPoint("RIGHT", copy, "LEFT", -8, 0)
    errorsFrame.status = S.Note(errorsFrame, 12)
    errorsFrame.status:SetPoint("BOTTOMLEFT", S.INSET, S.INSET + 8)
    errorsFrame.status:SetPoint("RIGHT", clear, "LEFT", -12, 0)
    errorsFrame.status:SetMaxLines(2)
    local function fill()
        local n = #ns.Errors()
        memo.edit:SetText(n > 0 and ns.ErrorsText() or L.NO_ERRORS)
        copy:SetEnabled(n > 0)
        clear:SetEnabled(n > 0)
        errorsFrame.status:SetText(L.ERRORS_COUNT:format(n))
    end
    copy:SetScript("OnClick", function()
        memo.edit:SetText(ns.ErrorsText())
        memo.edit:SetFocus()
        memo.edit:HighlightText()
        errorsFrame.status:SetText(L.COPY_HINT)
    end)
    clear:SetScript("OnClick", function()
        ns.ClearErrors()
        fill()
        ns.Refresh()
    end)
    errorsFrame:SetScript("OnShow", fill)
    errorsFrame.copy, errorsFrame.clear = copy, clear
end

function ns.OpenErrors()
    if not (frame and frame:IsShown()) then ns.Toggle() end
    if not errorsFrame then buildErrors() end
    showPanel("errors")
end

-- The header: the window's own (icon, title, version), plus the Unlock link at the right, where
-- players look for it: accent text over a thin line, the frames that show counted beside it.
local function buildHeader()
    local b = CreateFrame("Button", nil, frame.bar)
    b:SetHeight(28)
    b.icon = S.IconBox(b, 18, QUICK_ICON.move)
    b.icon:SetPoint("LEFT", 2, 0)
    local a = S.Accent()
    b.text = S.Text(b, 13, a)
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 7, 0)
    b.text:SetWordWrap(false)
    b.count = S.Text(b, 12, S.FAINT)
    b.count:SetPoint("LEFT", b.text, "RIGHT", 6, 0)
    b.rule = S.Tex(b, "ARTWORK", 0, { a[1], a[2], a[3], 0.35 })
    b.rule:SetHeight(1)
    b.rule:SetPoint("BOTTOMLEFT", b.text, "BOTTOMLEFT", 0, -4)
    b.rule:SetPoint("BOTTOMRIGHT", b.text, "BOTTOMRIGHT", 0, -4)
    function b:Set(text, count)
        self.text:SetText(text)
        self.count:SetText(count)
        local w = (tonumber(self.text:GetStringWidth()) or 0) + (tonumber(self.count:GetStringWidth()) or 0)
        self:SetWidth(math.ceil(w) + 2 + 18 + 7 + (count ~= "" and 6 or 0) + 4)
    end
    b:SetScript("OnClick", function()
        if ns.SetMoving(not ns.moving) then ns.Print(ns.moving and L.MOVE_ON or L.MOVE_OFF) end
    end)
    b:SetScript("OnEnter", function(self)
        self.rule:SetVertexColor(a[1], a[2], a[3], 1)
        tip(self, L.MOVE, { L.UNLOCK_TIP }, "ANCHOR_BOTTOM")
    end)
    b:SetScript("OnLeave", function(self)
        self.rule:SetVertexColor(a[1], a[2], a[3], 0.35)
        hideTip()
    end)
    b:Set(L.UNLOCK, "")
    unlockLink = frame:AddHeaderButton(b)
    unlockLink:ClearAllPoints()
    unlockLink:SetPoint("RIGHT", frame.close, "LEFT", -14, 0)
end

-- A switch row for the minimap button: on the home page and on the Options page.
local mapSwitches = {}
-- A label with a switch at the right, as the Quick setup card and the Options page show it.
local function switchRow(parent, label, get, set, tipText, all)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(30)
    local sw = S.Switch(row)
    sw:SetPoint("RIGHT", 0, 0)
    sw:SetChecked(get())
    sw:SetScript("OnClick", function() set(not get()) end)
    local text = S.Text(row, 12)
    text:SetPoint("LEFT", 0, 0)
    text:SetPoint("RIGHT", sw, "LEFT", -6, 0)
    text:SetWordWrap(false)
    text:SetText(label)
    if tipText then
        sw:HookScript("OnEnter", function(self) tip(self, label, { tipText }) end)
        sw:HookScript("OnLeave", hideTip)
    end
    row.switch = sw
    all[#all + 1] = sw
    return row
end

local function minimapRow(parent)
    return switchRow(parent, L.MINIMAP, ns.MinimapShown,
        function(on) ns.SetMinimap("hide", (not on) or nil) end, nil, mapSwitches)
end

local calmSwitches = {}

local function calmRow(parent)
    return switchRow(parent, L.CALM, ns.Calm, ns.SetCalm, L.CALM_TIP, calmSwitches)
end

function ns.SyncCalm()
    for _, sw in ipairs(calmSwitches) do sw:SetChecked(ns.Calm()) end
end

local function buildSide()
    -- No card: a darker strip from the header to the window's bottom edge, a hairline at its right.
    side = CreateFrame("Frame", nil, frame.body)
    side:SetWidth(SIDE + S.PAD - 1)
    side:SetPoint("TOPLEFT", -(S.PAD - 1), VPAD)
    side:SetPoint("BOTTOMLEFT", -(S.PAD - 1), -(VPAD - 1))
    S.Box(side, S.SIDE, S.CLEAR, S.R_XL - 1, "bottomleft")
    S.Glass(side, S.R_XL)
    local edge = line(side, LINE)
    edge:SetWidth(1)
    edge:SetPoint("TOPRIGHT")
    edge:SetPoint("BOTTOMRIGHT")
    local body = CreateFrame("Frame", nil, side)
    body:SetPoint("TOPLEFT", SIDE_IN, -10)
    body:SetPoint("BOTTOMRIGHT", -SIDE_IN, SIDE_IN)
    side.body = body

    search = S.Edit(body, SIDE + S.PAD - 1 - 2 * SIDE_IN, 30)
    search:SetPoint("TOPLEFT")
    search:SetPoint("TOPRIGHT")
    search:SetJustifyH("LEFT")
    search:SetTextInsets(28, 8, 0, 0)
    local glass = search:CreateTexture(nil, "OVERLAY")
    glass:SetSize(14, 14)
    glass:SetPoint("LEFT", 8, 0)
    glass:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    glass:SetVertexColor(S.FAINT[1], S.FAINT[2], S.FAINT[3], 1)
    placeholder = S.Text(search, 13, S.FAINT)
    placeholder:SetPoint("LEFT", 28, 0)
    placeholder:SetPoint("RIGHT", -8, 0)
    placeholder:SetWordWrap(false)
    placeholder:SetText(L.SEARCH)
    local function hint(self)
        placeholder:SetShown((self:GetText() or "") == "" and not self:HasFocus())
    end
    search:HookScript("OnEditFocusGained", hint)
    search:HookScript("OnEditFocusLost", hint)
    search:SetScript("OnTextChanged", function(self)
        view.query = self:GetText() or ""
        hint(self)
        scroll:Top()
        ns.Refresh()
    end)
    search:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    -- Enter opens the first module found.
    search:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        local first = ns.Filter(ns.List(), "All", "all", view.query)[1]
        if view.query ~= "" and first then enter(first) end
    end)

    scroll = S.Scroll(body)
    scroll:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -8)
    scroll:SetPoint("BOTTOMRIGHT", -10, 0)
    list = scroll.child
    list:SetWidth(LIST_W)

    homeRow = CreateFrame("Button", nil, list)
    homeRow:SetHeight(ROW_H)
    selectable(homeRow)
    local hi = S.IconBox(homeRow, 20, TOOLKIT_ICON)
    hi:SetPoint("LEFT", 8, 0)
    local ht = S.Text(homeRow, 13)
    ht:SetPoint("LEFT", hi, "RIGHT", 9, 0)
    ht:SetText(L.HOME)
    homeRow:SetScript("OnClick", goHome)
    homeRow:SetScript("OnEnter", function(self) if not self.selected then S.Fill(self, HOVER) end end)

    -- Tweaks, right under Home: the small switches of the toolkit and the ones modules lend.
    tweaksRow = CreateFrame("Button", nil, list)
    tweaksRow:SetHeight(ROW_H)
    selectable(tweaksRow)
    local twi = S.IconBox(tweaksRow, 20, ns.TWEAKS_ICON)
    twi:SetPoint("LEFT", 8, 0)
    tweaksRow.text = S.Text(tweaksRow, 13)
    tweaksRow.text:SetPoint("LEFT", twi, "RIGHT", 9, 0)
    tweaksRow.text:SetPoint("RIGHT", -8, 0)
    tweaksRow.text:SetWordWrap(false)
    tweaksRow.text:SetText(L.TW_PAGE)
    tweaksRow:SetScript("OnClick", function()
        local q = view.query
        if q:match("%S") then
            search:SetText("")
            search:ClearFocus()
        else
            q = nil
        end
        ns.OpenTweaks(q)
    end)
    tweaksRow:SetScript("OnEnter", function(self) if not self.selected then S.Fill(self, HOVER) end end)

    -- Setup, under Tweaks: the presets, the tools and the hub's own switches.
    setupRow = CreateFrame("Button", nil, list)
    setupRow:SetHeight(ROW_H)
    selectable(setupRow)
    local si = S.IconBox(setupRow, 20, QUICK_ICON.page)
    si:SetPoint("LEFT", 8, 0)
    local st = S.Text(setupRow, 13)
    st:SetPoint("LEFT", si, "RIGHT", 9, 0)
    st:SetText(L.SETUP_PAGE)
    setupRow:SetScript("OnClick", function() ns.OpenSetupPage() end)
    setupRow:SetScript("OnEnter", function(self) if not self.selected then S.Fill(self, HOVER) end end)

    empty = S.Empty(scroll)
    empty:Set(L.NO_MATCH)
end

-- A small rounded label (the module's group, its state).
local function pill(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetHeight(20)
    S.Box(p, S.RAISED, S.CLEAR, S.R_MD)
    p.text = S.Text(p, 12, S.MUTED)
    p.text:SetPoint("CENTER")
    function p:Set(text, c)
        self.text:SetText(text or "")
        c = c or S.MUTED
        self.text:SetTextColor(c[1], c[2], c[3], 1)
        S.Fill(self, c == S.MUTED and S.RAISED or { c[1] * 0.3, c[2] * 0.3, c[3] * 0.3, 1 })
        self:SetWidth(math.floor((tonumber((self.text:GetStringWidth())) or 0) + 18))
    end
    return p
end

local function buildCard()
    -- No box: a column beside the module with a hairline at its left, like the side list.
    card = CreateFrame("Frame", nil, host)
    card:SetWidth(CARD)
    card:SetPoint("TOPRIGHT")
    card:SetPoint("BOTTOMRIGHT")
    local edge = line(card, LINE)
    edge:SetWidth(1)
    edge:SetPoint("TOPLEFT", 0, VPAD)
    edge:SetPoint("BOTTOMLEFT", 0, -(VPAD - 1))
    local d = card
    d.body = CreateFrame("Frame", nil, card)
    d.body:SetPoint("TOPLEFT", S.INSET, 0)
    d.body:SetPoint("BOTTOMRIGHT", 0, 0)

    local banner = CreateFrame("Frame", nil, d.body)
    banner:SetHeight(110)
    banner:SetPoint("TOPLEFT")
    banner:SetPoint("TOPRIGHT")
    local ring = CreateFrame("Frame", nil, banner)
    ring:SetSize(70, 70)
    ring:SetPoint("CENTER", 0, -4)
    S.Circle(ring, 70, S.RING, "BACKGROUND", -7):SetPoint("CENTER")
    S.Circle(ring, 68, S.INPUT, "BACKGROUND", -6):SetPoint("CENTER")
    d.icon = ring:CreateTexture(nil, "ARTWORK")
    d.icon:SetSize(66, 66)
    d.icon:SetPoint("CENTER")
    d.icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    S.RoundMask(ring, d.icon)

    d.title = S.Text(d.body, 16, S.GOLD, nil, "title")
    d.title:SetPoint("TOPLEFT", banner, "BOTTOMLEFT", 4, -6)
    d.title:SetPoint("RIGHT", -S.INSET, 0)
    d.title:SetWordWrap(false)
    d.cat = pill(d.body)
    d.cat:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -8)
    d.state = pill(d.body)
    d.state:SetPoint("LEFT", d.cat, "RIGHT", 6, 0)
    d.desc = S.Text(d.body, 13, S.MUTED)
    d.desc:SetPoint("TOPLEFT", d.cat, "BOTTOMLEFT", 0, -12)
    d.desc:SetPoint("RIGHT", -S.INSET, 0)
    d.desc:SetJustifyV("TOP")
    d.desc:SetHeight(74)
    d.desc:SetMaxLines(5)
    d.slash = S.Text(d.body, 12, S.FAINT)
    d.slash:SetPoint("TOPLEFT", d.desc, "BOTTOMLEFT", 0, -6)
    d.slash:SetPoint("RIGHT", -S.INSET, 0)
    d.facts = S.Text(d.body, 12, S.FAINT)
    d.facts:SetPoint("TOPLEFT", d.slash, "BOTTOMLEFT", 0, -6)
    d.facts:SetPoint("RIGHT", -S.INSET, 0)
    d.facts:SetWordWrap(false)

    d.pop = S.Button(d.body, CARD - 2 * S.INSET, 34)
    d.pop:SetPoint("BOTTOMLEFT", 0, 0)
    d.pop:SetPoint("BOTTOMRIGHT", 0, 0)
    d.pop:SetText(L.POP_OUT)
    d.pop:SetScript("OnClick", function() popOut() end)
    -- Load or not load the module at all: the switch only pauses it.
    d.load = S.Ghost(S.Button(d.body, CARD - 2 * S.INSET, 30))
    d.load:SetPoint("BOTTOMLEFT", d.pop, "TOPLEFT", 0, 8)
    d.load:SetPoint("BOTTOMRIGHT", d.pop, "TOPRIGHT", 0, 8)
    d.load:SetScript("OnClick", function()
        local r = d.row
        if r then ns.SetLoaded(r, not r.loadOn) end
    end)
    d.load:HookScript("OnEnter", function(self) tip(self, self:GetText(), { L.UNLOAD_TIP }) end)
    d.load:HookScript("OnLeave", hideTip)
    d.reload = S.Primary(S.Button(d.body, CARD - 2 * S.INSET, 30))
    d.reload:SetPoint("BOTTOMLEFT", d.load, "TOPLEFT", 0, 8)
    d.reload:SetPoint("BOTTOMRIGHT", d.load, "TOPRIGHT", 0, 8)
    d.reload:SetText(L.RELOAD)
    d.reload:SetScript("OnClick", function() ReloadUI() end)
    -- Reset asks twice: the first press only arms it.
    d.reset = S.Ghost(S.Button(d.body, CARD - 2 * S.INSET, 30))
    d.reset:SetScript("OnClick", function(self)
        if not d.armed then
            d.armed = true
            self:SetText(L.RESET_SURE)
            return
        end
        d.armed = false
        self:SetText(L.RESET)
        if ns.Reset(d.row) then ns.Print(L.RESET_DONE:format(d.row.title)) end
    end)
    card:Hide()
end

-- A section label in bold dim gold capitals, as on the cards.
local function label(parent, text)
    local t = S.Text(parent, 12, S.GOLD_DIM, nil, "bold")
    t:SetText(S.Upper(text))
    t:SetWordWrap(false)
    return t
end

-- A link-like action in a card's title line: accent text, no box.
local function link(parent, text)
    local b = S.Ghost(S.FitButton(parent, text, 22, 40))
    b.text:SetTextColor(S.Accent()[1], S.Accent()[2], S.Accent()[3], 1)
    b:SetWidth(math.floor((tonumber((b.text:GetStringWidth())) or 0) * 1.1 + 24))
    return b
end

-- The Setup page ------------------------------------------------------------------------------
-- What the player sets once, on the window's own background: the presets as cards that show
-- their modules, the board of every module, the hub's own switches, the commands and the tools.
local buildSetupPage
do
local PRESET_GAP, PRESET_H = 8, 122
local PRESET_W = math.floor((HOST_W - 3 * PRESET_GAP) / 4)
local SETUP_TOP, BOARD_TOP = 66, 220
local TOOL_GAP, TOOL_H, FOOT_H = 10, 108, 26
local TOOL_W = math.floor((HOST_W - 2 * TOOL_GAP) / 3)
local TOOLS_TOP = HOST_H - FOOT_H - TOOL_H - 6
local BOARD_W = MID - 16
local BOARD_H = TOOLS_TOP - S.GAP - BOARD_TOP
local BOARD_LABEL, BOARD_COUNT, BOARD_ICON = 168, 34, 30
local MINI, MINI_MAX = 18, 9

local function width(t)
    return math.floor((tonumber((t:GetStringWidth())) or 0) + 0.5)
end

-- A small pill at the right of the page's title: a number with its words.
local function setupChip(parent, button)
    local c = CreateFrame(button and "Button" or "Frame", nil, parent)
    c:SetHeight(26)
    S.Box(c, S.SURFACE, S.CARD_EDGE, 11)
    c.text = S.Text(c, 12, S.MUTED)
    c.text:SetPoint("RIGHT", -11, 0)
    c.text:SetWordWrap(false)
    function c:Set(text, lead)
        self.text:SetText(text)
        self:SetWidth(width(self.text) + 22 + (lead or 0))
    end
    return c
end

-- A module on the board or on a preset card: its round icon, and on the board the dot of its state.
local function modIcon(parent, size, dot)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.icon = S.IconBox(b, size)
    b.icon:SetPoint("CENTER")
    if dot then
        b.dotBack = S.Circle(b, 11, S.SOLID, "OVERLAY", 1)
        b.dotBack:SetPoint("CENTER", b, "BOTTOMRIGHT", -3, 3)
        b.dot = S.Circle(b, 7, S.GOOD, "OVERLAY", 2)
        b.dot:SetPoint("CENTER", b.dotBack, "CENTER")
        b.dotIn = S.Circle(b, 3, S.SOLID, "OVERLAY", 3)
        b.dotIn:SetPoint("CENTER", b.dotBack, "CENTER")
    end
    b:SetScript("OnLeave", hideTip)
    return b
end

-- The state of a module as the board shows it: the dot's colour, a hollow dot and a grey icon
-- for one that is off, so no state shows by colour alone.
local function paintMod(b, row)
    b.row = row
    b.icon:SetIcon(row.icon)
    local off = not row.on
    if b.icon.tex.SetDesaturated then b.icon.tex:SetDesaturated(off) end
    b.icon.tex:SetAlpha(off and 0.55 or 1)
    b.icon:SetGlow(off and S.EDGE or nil)
    if b.dot then
        local c = (row.state == "blocked" and BAD) or (row.state == "reload" and WAIT) or (off and S.FAINT) or GOOD
        b.dot:SetVertexColor(c[1], c[2], c[3], 1)
        b.dotIn:SetShown(off and row.state ~= "reload")
    end
end

local function boardTip(self)
    local row = self.row
    if not row then return end
    local text, color = stateText(row)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(row.title, S.GOLD[1], S.GOLD[2], S.GOLD[3], 1, true)
    GameTooltip:AddLine(catName(row.category) .. S.DOT .. text, color[1], color[2], color[3], true)
    if self.can then
        local a = S.Accent()
        GameTooltip:AddLine(row.on and L.BOARD_OFF or L.BOARD_ON, a[1], a[2], a[3], true)
    end
    GameTooltip:Show()
end

-- A switch from the board: the same switch as the one in a module's header.
local function boardClick(self)
    local row = self.row and findRow(self.row.key)
    if not row or not self.can then return end
    ns.Switch(row, not row.on)
    ns.Refresh()
    if GameTooltip:IsOwned(self) then boardTip(self) end
end

local presetCards, boardRows, boardIcons = {}, {}, {}

local function makePreset(parent, i, p)
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(PRESET_W, PRESET_H)
    c:SetPoint("TOPLEFT", (i - 1) * (PRESET_W + PRESET_GAP), -(SETUP_TOP + 20))
    S.Box(c, S.SURFACE, S.CARD_EDGE, S.R_LG)
    S.Depth(c, S.R_LG)
    c.key = p.key
    c.icon = S.IconBox(c, 36, p.icon)
    c.icon:SetPoint("TOPLEFT", 12, -12)
    c.name = S.Text(c, 16, S.GOLD, nil, "title")
    c.name:SetPoint("TOPLEFT", 58, -11)
    c.name:SetPoint("RIGHT", -8, 0)
    c.name:SetWordWrap(false)
    c.name:SetText(L["PRESET_" .. p.key])
    c.count = S.Text(c, 12, S.MUTED)
    c.count:SetPoint("TOPLEFT", 58, -32)
    c.count:SetPoint("RIGHT", -8, 0)
    c.count:SetWordWrap(false)
    c.minis = {}
    c.apply = S.Button(c, PRESET_W - 24, 26)
    c.apply:SetPoint("BOTTOM", 0, 10)
    c.apply:SetText(L.SETUP_APPLY)
    local a = S.Accent()
    c.apply.text:SetTextColor(a[1], a[2], a[3], 1)
    c.apply:SetScript("OnClick", function()
        local n = ns.ApplyPreset(p.key)
        ns.Print(n > 0 and L.PRESET_DONE:format(n) or L.PRESET_SAME)
        ns.Refresh()
    end)
    return c
end

local function miniTip(self)
    if self.row then tip(self, self.row.title, { catName(self.row.category) }) end
end

-- The preset's modules that are installed, as small icons in the preset's own order.
local function fillPreset(c, p, byKey)
    local n = 0
    for _, k in ipairs(p.modules) do
        local row = byKey[k]
        if row and n < MINI_MAX then
            n = n + 1
            local m = c.minis[n]
            if not m then
                m = modIcon(c, MINI)
                m:SetScript("OnEnter", miniTip)
                c.minis[n] = m
            end
            m.row = row
            m.icon:SetIcon(row.icon)
            m:Show()
        end
    end
    local step = math.min(MINI + 2, math.floor((PRESET_W - 24) / math.max(1, n)))
    for i, m in ipairs(c.minis) do
        m:SetShown(i <= n)
        m:ClearAllPoints()
        m:SetPoint("TOPLEFT", 12 + (i - 1) * step, -58)
    end
    c.shown = n
    c.count:SetText(L.MODULES_N:format(n))
end

-- The board: a line per group, its modules as icons. The lines share the card's height, and a
-- group with many modules moves its icons closer, so every installed module has a place.
local function fillBoard(board, data)
    local groups = ns.Groups(data)
    local rowH = math.min(40, math.floor((BOARD_H - 36 - S.INSET) / math.max(1, #groups)))
    local size = math.min(BOARD_ICON, rowH - 8)
    local room = BOARD_W - 2 * S.INSET - BOARD_LABEL - BOARD_COUNT
    local used = 0
    for gi, g in ipairs(groups) do
        local line = boardRows[gi]
        if not line then
            line = CreateFrame("Frame", nil, board.body)
            line.label = S.Text(line, 13)
            line.label:SetPoint("LEFT")
            line.label:SetWidth(BOARD_LABEL - 6)
            line.label:SetWordWrap(false)
            line.count = S.Text(line, 12, S.FAINT)
            line.count:SetPoint("LEFT", BOARD_LABEL, 0)
            line.count:SetWidth(BOARD_COUNT)
            boardRows[gi] = line
        end
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", 0, -(gi - 1) * rowH)
        line:SetPoint("TOPRIGHT", 0, -(gi - 1) * rowH)
        line:SetHeight(rowH)
        line.key = g.key
        line.label:SetText(catName(g.key))
        local on = 0
        local step = math.min(size + 9, math.floor(room / #g.rows))
        local sz = math.max(18, math.min(size, step - 4))
        for ri, row in ipairs(g.rows) do
            if row.on then on = on + 1 end
            used = used + 1
            local b = boardIcons[used]
            if not b or b.size ~= sz then
                if b then b:Hide() end
                b = modIcon(board.body, sz, true)
                b.size = sz
                b:SetScript("OnEnter", boardTip)
                b:SetScript("OnClick", boardClick)
                boardIcons[used] = b
            end
            b:ClearAllPoints()
            b:SetPoint("LEFT", line, "LEFT", BOARD_LABEL + BOARD_COUNT + (ri - 1) * step, 0)
            -- A module the hub cannot switch (no addon of its own to switch and no pause) only shows.
            b.can = row.addon ~= nil or row.canPause == true
            paintMod(b, row)
            b:Show()
        end
        line.count:SetText(on .. "/" .. #g.rows)
        line:Show()
    end
    for i = #groups + 1, #boardRows do boardRows[i]:Hide() end
    for i = used + 1, #boardIcons do boardIcons[i]:Hide() end
    board.groups, board.shown, board.icons = #groups, used, boardIcons
end

-- A tool of the Setup page as a tile: icon, name, what it is for, and where it leads.
local function toolTile(parent, i, text, desc, icon, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(TOOL_W, TOOL_H)
    b:SetPoint("TOPLEFT", (i - 1) * (TOOL_W + TOOL_GAP), -TOOLS_TOP)
    S.Box(b, S.SURFACE, S.CARD_EDGE, S.R_LG)
    S.Depth(b, S.R_LG)
    b.icon = S.IconBox(b, 36, icon)
    b.icon:SetPoint("TOPLEFT", 12, -14)
    b.value = S.Text(b, 28, WHITE, nil, "title")
    b.value:SetPoint("BOTTOMRIGHT", -14, 6)
    b.value:SetJustifyH("RIGHT")
    b.title = S.Text(b, 15, S.GOLD, nil, "title")
    b.title:SetPoint("TOPLEFT", 58, -13)
    b.title:SetPoint("RIGHT", -10, 0)
    b.title:SetWordWrap(false)
    b.title:SetText(text)
    b.desc = S.Note(b, 12)
    b.desc:SetPoint("TOPLEFT", 58, -36)
    b.desc:SetPoint("RIGHT", -14, 0)
    b.desc:SetMaxLines(3)
    b.desc:SetText(desc)
    b.go = S.Text(b, 12, S.Accent())
    b.go:SetPoint("BOTTOMLEFT", 58, 9)
    b.go:SetPoint("RIGHT", b.value, "LEFT", -6, 0)
    b.go:SetWordWrap(false)
    b.go:SetText(L.OPEN .. " »")
    b:SetScript("OnEnter", function(self) S.Fill(self, S.RAISED) end)
    b:SetScript("OnLeave", function(self) S.Fill(self, S.SURFACE) end)
    b:SetScript("OnClick", onClick)
    return b
end

-- The hub's own row among the minimap buttons.
local HUB_PIN = { key = false, title = L.TITLE, icon = "Interface\\AddOns\\Gulli-Toolkit\\icon" }

local function pinShown(row)
    if row == HUB_PIN then return ns.MinimapShown() end
    return ns.Pinned(row.key)
end

local function pinTip(self)
    local row = self.row
    if not row then return end
    local a = S.Accent()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(row.title, S.GOLD[1], S.GOLD[2], S.GOLD[3], 1, true)
    GameTooltip:AddLine(pinShown(row) and L.PIN_ON or L.PIN_OFF, a[1], a[2], a[3], true)
    GameTooltip:Show()
end

local function pinClick(self)
    local row = self.row
    if not row then return end
    if row == HUB_PIN then
        ns.SetMinimap("hide", ns.MinimapShown() or nil)
        ns.Refresh()
    else
        ns.SetPinned(row.key, not ns.Pinned(row.key))
    end
end

-- Every button the minimap can have, as icons: bright with a gold dot is there, grey is not.
-- The icons take the biggest size at which all of them fit the card.
local PIN_GAP = 2

local function fillPins(card, data)
    local rows = { HUB_PIN }
    for _, r in ipairs(data) do rows[#rows + 1] = r end
    local size, cols = 22, 1
    for _, s in ipairs({ 30, 28, 26, 24, 22 }) do
        size, cols = s, math.max(1, math.floor((card.w + PIN_GAP) / (s + PIN_GAP)))
        if math.ceil(#rows / cols) * (s + PIN_GAP) - PIN_GAP <= card.h then break end
    end
    local shown = 0
    for i, row in ipairs(rows) do
        local b = card.icons[i]
        if not b or b.size ~= size then
            if b then b:Hide() end
            b = modIcon(card.body, size, true)
            b.size = size
            b:SetScript("OnEnter", pinTip)
            b:SetScript("OnClick", pinClick)
            card.icons[i] = b
        end
        b.row = row
        b.icon:SetIcon(row.icon)
        local on = pinShown(row)
        if on then shown = shown + 1 end
        if b.icon.tex.SetDesaturated then b.icon.tex:SetDesaturated(not on) end
        b.icon.tex:SetAlpha(on and 1 or 0.5)
        b.icon:SetGlow(not on and S.EDGE or nil)
        b.dot:SetVertexColor(S.GOLD[1], S.GOLD[2], S.GOLD[3], 1)
        b.dot:SetShown(on); b.dotBack:SetShown(on); b.dotIn:Hide()
        b.on = on
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", ((i - 1) % cols) * (size + PIN_GAP), -math.floor((i - 1) / cols) * (size + PIN_GAP))
        b:Show()
    end
    for i = #rows + 1, #card.icons do card.icons[i]:Hide() end
    card.shown, card.size, card.count = #rows, size, shown
    card.hint:SetText(L.PIN_N:format(shown, #rows))
end

function fillSetup(data)
    local p = setupFrame
    local byKey, on, waits = {}, 0, 0
    for _, r in ipairs(data) do
        byKey[r.key] = r
        if r.on then on = on + 1 end
        if r.state == "reload" then waits = waits + 1 end
    end
    p.onChip:Set(S.Emph(L.OV_ON:format(on, #data)))
    p.waitChip:SetShown(waits > 0)
    if waits > 0 then
        p.waitChip:Set(S.Emph(L.SETUP_WAIT:format(waits)) .. S.DOT .. S.Hex(S.Accent()) .. L.RELOAD .. "|r", 14)
    end
    p.onChip:ClearAllPoints()
    if waits > 0 then p.onChip:SetPoint("RIGHT", p.waitChip, "LEFT", -8, 0) else p.onChip:SetPoint("TOPRIGHT", 0, -2) end
    p.waits = waits
    for i, pr in ipairs(ns.PRESETS) do fillPreset(presetCards[i], pr, byKey) end
    fillBoard(p.board, data)
    fillPins(p.pins, data)
    protectBtn.value:SetText(#ns.Protected())
    local o = ns.Overview(data)
    local foot = L.TITLE .. " " .. ns.Version() .. S.DOT .. L.MODULES_N:format(#data)
    if o.kb > 0 then foot = foot .. S.DOT .. ns.Size(o.kb) end
    p.foot:SetText(foot)
end

function buildSetupPage()
    local p = CreateFrame("Frame", "GulliToolkitSetupPage", host)
    p:SetAllPoints(host)
    p:EnableMouse(true)
    p:Hide()
    setupFrame = p
    p.title = S.Text(p, 20, S.GOLD, nil, "title")
    p.title:SetPoint("TOPLEFT", 2, 0)
    p.title:SetText(L.SETUP_PAGE)
    p.hint = S.Note(p, 12)
    p.hint:SetPoint("TOPLEFT", 2, -28)
    p.hint:SetWidth(HOST_W - 400)
    p.hint:SetMaxLines(2)
    p.hint:SetText(L.SETUP_PAGE_HINT)

    -- At the right of the title: how many modules are on, and the reload that waits, if any.
    p.waitChip = setupChip(p, true)
    p.waitChip:SetPoint("TOPRIGHT", 0, -2)
    p.waitChip.text:SetTextColor(WAIT[1], WAIT[2], WAIT[3], 1)
    local dot = S.Circle(p.waitChip, 7, WAIT, "ARTWORK")
    dot:SetPoint("LEFT", 10, 0)
    p.waitChip:SetScript("OnClick", function() ReloadUI() end)
    p.waitChip:SetScript("OnEnter", function(self) S.Fill(self, S.RAISED) end)
    p.waitChip:SetScript("OnLeave", function(self) S.Fill(self, S.SURFACE) end)
    p.onChip = setupChip(p)

    local pl = label(p, L.PRESETS)
    pl:SetPoint("TOPLEFT", 2, -SETUP_TOP)
    local ph = S.Text(p, 12, S.FAINT)
    ph:SetPoint("TOPRIGHT", 0, -SETUP_TOP)
    ph:SetPoint("LEFT", pl, "RIGHT", 12, 0)
    ph:SetJustifyH("RIGHT")
    ph:SetWordWrap(false)
    ph:SetText(L.PRESET_HINT)
    for i, pr in ipairs(ns.PRESETS) do presetCards[i] = makePreset(p, i, pr) end
    p.presets = presetCards

    local board = S.Card(p, L.OV_TITLE, L.BOARD_HINT)
    board:SetPoint("TOPLEFT", 0, -BOARD_TOP)
    board:SetSize(BOARD_W, BOARD_H)
    p.board = board

    local win = S.Card(p, L.SETUP_WINDOW)
    win:SetPoint("TOPLEFT", board, "TOPRIGHT", S.GAP, 0)
    win:SetPoint("RIGHT")
    local w = win.body
    local calm = calmRow(w)
    calm:SetPoint("TOPLEFT")
    calm:SetPoint("TOPRIGHT")
    p.calm = calm
    -- The size of the hub window: the player's own factor on top of the fit to the screen.
    local size = CreateFrame("Frame", nil, w)
    size:SetHeight(30)
    size:SetPoint("TOPLEFT", 0, -34)
    size:SetPoint("TOPRIGHT", 0, -34)
    local plus = S.Button(size, 28, 28)
    plus:SetPoint("RIGHT")
    plus:SetText("+")
    plus:SetScript("OnClick", function() nudgeScale(0.1) end)
    scaleText = S.Text(size, 13, WHITE, nil, "bold")
    scaleText:SetWidth(48)
    scaleText:SetJustifyH("CENTER")
    scaleText:SetPoint("RIGHT", plus, "LEFT", 0, 0)
    local minus = S.Button(size, 28, 28)
    minus:SetPoint("RIGHT", scaleText, "LEFT", 0, 0)
    minus:SetText("-")
    minus:SetScript("OnClick", function() nudgeScale(-0.1) end)
    local st = S.Text(size, 12)
    st:SetPoint("LEFT")
    st:SetPoint("RIGHT", minus, "LEFT", -6, 0)
    st:SetWordWrap(false)
    st:SetText(L.SETUP_SCALE)
    p.scale = { minus = minus, plus = plus }
    local winH = win:Fit(64)

    -- The buttons at the minimap: the hub's own first, then every module. A click puts a
    -- button there or takes it away.
    local pins = S.Card(p, L.PIN_TITLE)
    pins:SetPoint("TOPLEFT", win, "BOTTOMLEFT", 0, -TOOL_GAP)
    pins:SetPoint("RIGHT")
    pins:SetHeight(BOARD_H - winH - TOOL_GAP)
    pins.w = HOST_W - BOARD_W - S.GAP - 2 * S.INSET
    pins.h = BOARD_H - winH - TOOL_GAP - 36 - S.INSET
    pins.icons = {}
    p.pins = pins

    local tr = toolTile(p, 1, L.TRANSFER, L.TOOL_TRANSFER, QUICK_ICON.transfer, function()
        if not transfer then buildTransfer() end
        showPanel("transfer", "setup")
    end)
    protectBtn = toolTile(p, 2, L.PROTECTED, L.TOOL_PROTECT, QUICK_ICON.protect, function()
        if not protectFrame then buildProtected() end
        showPanel("protect", "setup")
    end)
    local first = toolTile(p, 3, L.SETUP, L.TOOL_SETUP, QUICK_ICON.setup, function() ns.OpenSetup() end)
    p.transfer, p.protect, p.first = tr, protectBtn, first

    p.foot = S.Text(p, 12, S.FAINT)
    p.foot:SetPoint("BOTTOMLEFT", 2, 4)
    p.foot:SetWordWrap(false)
    local lang = S.Text(p, 12, S.FAINT)
    lang:SetPoint("BOTTOMRIGHT", 0, 4)
    lang:SetPoint("LEFT", p.foot, "RIGHT", 12, 0)
    lang:SetJustifyH("RIGHT")
    lang:SetWordWrap(false)
    lang:SetText(L.FOOT_LANG)

    p:SetScript("OnShow", applyScale)
end
end

-- The Tweaks page; query (optional) is put into its search.
function ns.OpenTweaks(query)
    if not frame or not frame:IsShown() then ns.Toggle() end
    if not ns.TweaksPage() then
        ns.BuildTweaksPage(host, HOST_W, HOST_H, { tip = tip, hideTip = hideTip, enter = enter })
    end
    if query then ns.TweaksSearch(query) end
    showPanel("tweaks")
end

function ns.OpenSetupPage()
    if not setupFrame then buildSetupPage() end
    showPanel("setup")
end
function ns.PinBox() return pinBox end

function ns.SetupPage()
    if not setupFrame then buildSetupPage() end
    return setupFrame
end

local function buildHome()
    home = CreateFrame("Frame", nil, host)
    home:SetAllPoints(host)
    home:Show()

    -- Ready: the ring at the left of the card's body, the meters beside it.
    local ready = S.Card(home, L.READY, "")
    ready:SetPoint("TOPLEFT")
    ready:SetSize(HOST_W - SIDE_W - GAP, TOP_H)
    home.ready = ready
    ready.title:SetPoint("RIGHT", ready, "RIGHT", -100, 0)
    local rs = link(ready, L.READY_SET)
    rs:SetPoint("TOPRIGHT", -6, -7)
    rs:SetScript("OnClick", function()
        if not readyFrame then ns.BuildReady() end
        if readyFrame:IsShown() then showHome() else showPanel("ready") end
    end)
    home.ring = CreateFrame("Frame", nil, ready.body)
    home.ring:SetSize(RING, RING)
    home.ring:SetPoint("LEFT", 4, 0)
    home.ringCount = S.Text(home.ring, 32, WHITE, nil, "title")
    home.ringCount:SetPoint("BOTTOMRIGHT", home.ring, "CENTER", 4, -6)
    home.ringCount:SetJustifyH("RIGHT")
    home.ringOf = S.Text(home.ring, 16, S.MUTED, nil, "title")
    home.ringOf:SetPoint("BOTTOMLEFT", home.ringCount, "BOTTOMRIGHT", 1, 3)
    home.ringNote = S.Text(home.ring, 12, S.WARN)
    home.ringNote:SetPoint("TOP", home.ring, "CENTER", 0, -10)
    home.ringNote:SetWidth(RING - 36)
    home.ringNote:SetJustifyH("CENTER")
    home.ringNote:SetMaxLines(2)

    -- The session: the number with its columns, a line, the small tiles, the facts, the level's bar.
    local ses = S.Card(home, L.SESSION, "")
    ses:SetPoint("TOPRIGHT")
    ses:SetSize(SIDE_W, TOP_H)
    home.session = ses
    local sb = CreateFrame("Frame", nil, ses.body)
    sb:SetAllPoints(ses.body)
    home.sesFull = sb
    home.sesValue = S.Text(sb, 28, WHITE, nil, "title")
    home.sesValue:SetPoint("TOPLEFT", 0, 2)
    home.sesUnit = S.Text(sb, 13, S.MUTED)
    home.sesUnit:SetPoint("BOTTOMLEFT", home.sesValue, "BOTTOMRIGHT", 6, 4)
    home.sesLine = S.Text(sb, 13, S.MUTED)
    home.sesLine:SetPoint("TOPLEFT", 0, -34)
    home.sesLine:SetPoint("RIGHT")
    home.sesLine:SetWordWrap(false)
    home.sesGraph = CreateFrame("Frame", nil, sb)
    home.sesGraph:SetPoint("TOPRIGHT", 0, 0)
    home.sesGraph:SetSize(ns.SESSION_BARS * (COL_W + COL_GAP) - COL_GAP, COL_H + 1)
    local base = S.Tex(home.sesGraph, "BACKGROUND", 0, LINE)
    base:SetHeight(1)
    base:SetPoint("BOTTOMLEFT")
    base:SetPoint("BOTTOMRIGHT")
    home.sesStats = CreateFrame("Frame", nil, sb)
    home.sesStats:SetPoint("TOPLEFT", 0, -66)
    home.sesStats:SetPoint("TOPRIGHT", 0, -66)
    home.sesStats:SetHeight(30)
    local rule = S.Tex(home.sesStats, "BACKGROUND", 0, LINE)
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT", home.sesStats, "TOPLEFT", 0, 7)
    rule:SetPoint("BOTTOMRIGHT", home.sesStats, "TOPRIGHT", 0, 7)
    home.sesLow = S.Text(sb, 12, S.MUTED)
    home.sesLow:SetWordWrap(false)
    home.sesLow:SetJustifyH("LEFT")
    home.sesLeft = S.Text(sb, 12, S.MUTED)
    home.sesLeft:SetPoint("BOTTOMLEFT")
    home.sesRight = S.Text(sb, 12, S.MUTED)
    home.sesRight:SetPoint("BOTTOMRIGHT")
    home.sesBar = makeBar(sb, 7)
    -- Nothing yet: what the card will show.
    local se = CreateFrame("Frame", nil, ses.body)
    se:SetAllPoints(ses.body)
    home.sesEmpty = se
    local seIcon = S.IconBox(se, 30, ns.SES_ICON.empty)
    seIcon:SetPoint("TOP", 0, -22)
    local seTitle = S.Text(se, 13, S.TEXT, nil, "bold")
    seTitle:SetPoint("TOP", seIcon, "BOTTOM", 0, -8)
    seTitle:SetText(L.SES_EMPTY)
    local seText = S.Text(se, 13, S.MUTED)
    seText:SetPoint("TOP", seTitle, "BOTTOM", 0, -4)
    seText:SetWidth(SIDE_W - 2 * S.INSET - 24)
    seText:SetJustifyH("CENTER")
    seText:SetText(L.SES_EMPTY_D)
    -- The whole card opens the module that leads it and tells the rest in its tooltip.
    local open = CreateFrame("Button", nil, ses)
    open:SetAllPoints(ses)
    open:SetScript("OnClick", function()
        local d = ses.data
        local row = d and d.hero and d.hero.row
        if row then enter(row) end
    end)
    open:SetScript("OnEnter", function(self) S.Fill(ses, S.RAISED); sessionTip(self) end)
    open:SetScript("OnLeave", function() S.Fill(ses, S.SURFACE); GameTooltip:Hide() end)
    home.sessionOpen = open

    -- At a glance: a label and the tiles, no card around them.
    local sc = CreateFrame("Frame", nil, home)
    sc:SetPoint("TOPLEFT")
    sc:SetPoint("TOPRIGHT")
    sc:SetHeight(120)
    local sl = label(sc, L.SUMMARY)
    sl:SetPoint("TOPLEFT", 0, 0)
    local body = CreateFrame("Frame", nil, sc)
    body:SetPoint("TOPLEFT", 0, -LABEL_H)
    body:SetPoint("BOTTOMRIGHT")
    home.summaryCard, home.summary = sc, body
    home.noSummary = S.Note(body, 13)
    home.noSummary:SetPoint("TOPLEFT")
    home.noSummary:SetPoint("RIGHT")
    home.noSummary:SetMaxLines(2)
    home.noSummary:SetText(L.NO_SUMMARY)

    local ov = S.Card(home, L.OV_TITLE)
    ov:SetWidth(SIDE_W)
    ov:SetPoint("TOPRIGHT", sc, "BOTTOMRIGHT", 0, -GAP)
    home.overview = ov
    home.ovReload = S.Primary(S.FitButton(ov, L.RELOAD, 26, 90))
    home.ovReload:SetPoint("TOPRIGHT", -8, -6)
    home.ovReload:SetScript("OnClick", function() ReloadUI() end)
    -- The number of modules that are on, big, the memory at the right, a pip per module under.
    home.ovCount = S.Text(ov.body, 28, WHITE, nil, "title")
    home.ovCount:SetPoint("TOPLEFT", 0, 2)
    home.ovTotal = S.Text(ov.body, 13, S.MUTED)
    home.ovTotal:SetPoint("BOTTOMLEFT", home.ovCount, "BOTTOMRIGHT", 6, 4)
    home.ovMemory = S.Text(ov.body, 13, S.MUTED)
    home.ovMemory:SetPoint("BOTTOMRIGHT", ov.body, "TOPRIGHT", 0, -28)
    home.ovMemory:SetJustifyH("RIGHT")
    home.ovPips = CreateFrame("Frame", nil, ov.body)
    home.ovPips:SetPoint("TOPLEFT", 0, -42)
    home.ovPips:SetPoint("TOPRIGHT", 0, -42)
    home.ovPips:SetHeight(8)

    local recent = S.Card(home, L.RECENT)
    recent:SetPoint("TOPLEFT", sc, "BOTTOMLEFT", 0, -GAP)
    recent:SetPoint("TOPRIGHT", ov, "TOPLEFT", -GAP, 0)
    home.recent = recent
    home.clear = link(recent, L.CLEAR)
    home.clear:SetPoint("TOPRIGHT", -6, -7)
    home.clear:SetScript("OnClick", function() GulliToolkit.ClearFeed() end)
    home.noRecent = S.Note(recent.body, 13)
    home.noRecent:SetPoint("TOPLEFT")
    home.noRecent:SetText(L.NO_RECENT)
end

local function onOpen()
    applyScale()
    -- The hub opens where the player left it: the last module, or the home page.
    if not view.inside and view.page == "home" then
        local row = findRow(ns.Last())
        if row and row.state == "ready" and moduleWindow(row) then return enter(row) end
    end
    ns.Refresh()
end

local function build()
    frame = S.Window("GulliToolkitFrame", L.TITLE, W, H, { sub = ns.Version(), fullTitle = true })
    -- The hub's own header: taller, a bigger icon and title, the version in grey beside it.
    frame.bar:SetHeight(HUB_HEAD)
    frame.iconBox:Hide()
    local big = S.IconBox(frame.bar, 34, TOOLKIT_ICON)
    big:SetPoint("LEFT", 16, 0)
    frame.iconBox, frame.icon = big, big.tex
    S.SetFont(frame.title, 20, nil, "title")
    frame.title:ClearAllPoints()
    frame.title:SetPoint("LEFT", big, "RIGHT", 10, 0)
    frame.sub:ClearAllPoints()
    frame.sub:SetPoint("LEFT", frame.title, "RIGHT", 8, -2)
    frame.body:ClearAllPoints()
    frame.body:SetPoint("TOPLEFT", S.PAD, -(HUB_HEAD + VPAD))
    frame.body:SetPoint("BOTTOMRIGHT", -S.PAD, VPAD)
    -- The hub sizes itself by ns.HubScale, also when the screen or the UI scale changes.
    S.TrackScale(frame, applyScale)

    buildHeader()
    buildSide()
    host = CreateFrame("Frame", nil, frame.body)
    host:SetPoint("TOPLEFT", frame.body, "TOPLEFT", SIDE + GAP, 0)
    host:SetPoint("BOTTOMRIGHT")
    -- Behind the centre: a warm light from its top left, and low on the right the toolkit's
    -- satchel as a pale emblem in a second light, so the see-through cards and tiles have
    -- something to show. The emblem runs off the window's corner: the texture is cut there.
    local light = frame:CreateTexture(nil, "BACKGROUND", nil, -5)
    light:SetTexture(S.RADIAL)
    light:SetPoint("TOPLEFT", host, "TOPLEFT", -GAP, 0)
    light:SetPoint("BOTTOMRIGHT", host, "CENTER", 0, -40)
    light:SetVertexColor(0.85, 0.62, 0.32, 0.07)
    local glow = frame:CreateTexture(nil, "BACKGROUND", nil, -5)
    glow:SetTexture(S.RADIAL)
    glow:SetTexCoord(1, 0, 1, 0)
    glow:SetSize(620, 460)
    glow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    glow:SetVertexColor(0.85, 0.62, 0.32, 0.10)
    local mark = frame:CreateTexture(nil, "BACKGROUND", nil, -4)
    mark:SetTexture(MARK)
    mark:SetTexCoord(0, (MARK_SIZE - MARK_CUT_X) / MARK_SIZE, 0, (MARK_SIZE - MARK_CUT_Y) / MARK_SIZE)
    mark:SetSize(MARK_SIZE - MARK_CUT_X, MARK_SIZE - MARK_CUT_Y)
    mark:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    mark:SetVertexColor(1, 0.86, 0.66, 0.12)
    frame.light, frame.glow, frame.mark = light, glow, mark
    buildHome()
    buildCard()

    hubSwitch = S.Switch(frame)
    hubSwitch:Hide()
    hubSwitch:SetScript("OnClick", function()
        local r = findRow(view.inside)
        if r then ns.Switch(r, not r.on) end
    end)
    hubSwitch:HookScript("OnEnter", function(self) tip(self, L.ON_TIP, nil, "ANCHOR_BOTTOM") end)
    hubSwitch:HookScript("OnLeave", hideTip)

    -- Beside it: the module's own button at the minimap.
    pinBox = CreateFrame("Frame", nil, frame)
    pinBox:SetHeight(28)
    pinBox:Hide()
    pinBox.switch = S.Switch(pinBox)
    pinBox.switch:SetPoint("RIGHT")
    pinBox.label = S.Text(pinBox, 12, S.MUTED)
    pinBox.label:SetPoint("RIGHT", pinBox.switch, "LEFT", -6, 0)
    pinBox.label:SetWordWrap(false)
    pinBox.label:SetText(L.PIN)
    pinBox:SetWidth(math.ceil(tonumber(pinBox.label:GetStringWidth()) or 60) + 6 + (tonumber(pinBox.switch:GetWidth()) or 44))
    pinBox.switch:SetScript("OnClick", function()
        if view.inside then ns.SetPinned(view.inside, not ns.Pinned(view.inside)) end
    end)
    pinBox.switch:HookScript("OnEnter", function(self) tip(self, L.PIN_TITLE, { L.PIN_TIP }, "ANCHOR_BOTTOM") end)
    pinBox.switch:HookScript("OnLeave", hideTip)

    frame:SetScript("OnShow", onOpen)
    -- Closing the hub leaves the module; it opens again from ns.Last().
    frame:SetScript("OnHide", function()
        leave()
        hidePanels()
        view.page = "home"
        home:Show()
    end)
end

function ns.Toggle()
    if not frame then build() end
    frame:SetShown(not frame:IsShown())
    if frame:IsShown() then onOpen() end
end

-- The view the hub shows now, for the tests.
function ns.View()
    return view, frame
end

-- Opens a module inside the hub (row key), or the home page (nil). For the tests.
function ns.Enter(key)
    if not key then return goHome() end
    return enter(findRow(key))
end
-- Types into the hub's search, for the tests and previews.
function ns.HubSearch(text) search:SetText(text or "") end
function ns.Inside() return insideWin end
function ns.Home() return home end
function ns.UnlockLink() return unlockLink end
function ns.Card() return card end
function ns.ShowPanel(name)
    if name == "protect" and not protectFrame then buildProtected() end
    if name == "transfer" and not transfer then buildTransfer() end
    showPanel(name)
    return name == "protect" and protectFrame or transfer
end

-- The first-run window ---------------------------------------------------------------------------

-- Which modules to use: a switch per installed module, grouped like the hub, with a grey line
-- that says why a module starts off or on (ns.SetupPlan). Nothing changes before Apply.
local setupWin, setupPlan
local SETUP_H, SETUP_ROW = 600, 48

local function setupItems()
    -- The modules with a reason come first, so the player sees at once what was picked and why.
    local by, items, found = {}, {}, {}
    for _, p in ipairs(setupPlan) do
        if p.why then
            found[#found + 1] = p
        else
            by[p.row.category] = by[p.row.category] or {}
            table.insert(by[p.row.category], p)
        end
    end
    if #found > 0 then
        items[#items + 1] = { head = L.SETUP_FOUND }
        -- The ones that start off first, then the ones that stay on.
        for _, p in ipairs(found) do if not p.on then items[#items + 1] = p end end
        for _, p in ipairs(found) do if p.on then items[#items + 1] = p end end
    end
    local cats = {}
    for _, c in ipairs(ns.CATEGORIES) do cats[#cats + 1] = c end
    cats[#cats + 1] = "Other"
    for _, c in ipairs(cats) do
        if by[c] then
            items[#items + 1] = { head = catName(c) or c }
            for _, p in ipairs(by[c]) do items[#items + 1] = p end
        end
    end
    return items
end

local function setupStatus()
    local on = 0
    for _, p in ipairs(setupPlan) do if p.on then on = on + 1 end end
    setupWin.footer:SetStatus(L.SETUP_COUNT:format(on, #setupPlan))
    setupWin.apply:SetText(ns.SetupNeedsReload(setupPlan) and L.SETUP_APPLY_RELOAD or L.SETUP_APPLY)
    setupWin.apply:SetWidth(math.max(120, math.floor((tonumber(setupWin.apply.text:GetStringWidth()) or 100) + 28)))
end

local function makeSetupRow(r)
    r.head = S.Text(r, 12, S.FAINT)
    r.head:SetPoint("BOTTOMLEFT", 4, 8)
    r.head:SetPoint("RIGHT", -4, 0)
    r.head:SetWordWrap(false)
    r.icon = S.IconBox(r, 28)
    r.icon:SetPoint("LEFT", 4, 0)
    r.switch = S.Switch(r)
    r.switch:SetPoint("RIGHT", -4, 0)
    r.name = S.Text(r, 12)
    r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 12, 2)
    r.name:SetPoint("RIGHT", r.switch, "LEFT", -12, 0)
    r.name:SetWordWrap(false)
    r.why = S.Text(r, 12, S.FAINT)
    r.why:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -4)
    r.why:SetPoint("RIGHT", r.switch, "LEFT", -12, 0)
    r.why:SetWordWrap(false)
    r.switch:SetScript("OnClick", function(self)
        if not r.item then return end
        r.item.on = not r.item.on
        self:SetChecked(r.item.on)
        rawset(setupWin, "reloadNext", nil)
        setupStatus()
    end)
end

local function fillSetupRow(r, item)
    r.item = not item.head and item or nil
    r.head:SetShown(item.head ~= nil)
    r.icon:SetShown(item.head == nil)
    r.switch:SetShown(item.head == nil)
    r.name:SetShown(item.head == nil)
    r.why:SetShown(item.head == nil)
    r.line:SetShown(item.head == nil)
    if item.head then
        r.head:SetText(S.Upper(item.head))
        return
    end
    r.icon:SetIcon(item.row.icon or TOOLKIT_ICON)
    r.name:SetText(item.row.title)
    r.why:SetText(item.why or item.row.desc or "")
    local c = item.why and S.MUTED or S.FAINT
    r.why:SetTextColor(c[1], c[2], c[3], 1)
    r.switch:SetChecked(item.on)
end

local function buildSetup()
    setupWin = S.Window("GulliToolkitSetup", L.SETUP_TITLE, S.NARROW_W, SETUP_H,
        { sub = "/gulli setup", icon = TOOLKIT_ICON, fullTitle = true })
    local ft = S.Footer(setupWin)
    setupWin.apply = ft:Add(S.Primary(S.FitButton(setupWin, L.SETUP_APPLY, 32, 120)))
    setupWin.later = ft:Add(S.Ghost(S.FitButton(setupWin, L.SETUP_LATER, 32, 90)))
    local body = setupWin.body
    local st = S.Stack(body)
    local intro = S.Card(body)
    local w = S.NARROW_W - 2 * S.PAD - 2 * S.INSET
    local text, th = S.Paragraph(intro.body, L.SETUP_HINT, w, 12)
    text:SetPoint("TOPLEFT")
    st:Add(intro, intro:Fit(th + 4))
    local listCard = S.Card(body, L.SETUP_MODULES)
    st:Add(listCard, setupWin.inner[2] - st.y)
    setupWin.list = S.List(listCard.body, SETUP_ROW, makeSetupRow, fillSetupRow)
    setupWin.list:SetPoint("TOPLEFT")
    setupWin.list:SetPoint("BOTTOMRIGHT")
    -- The reload gets a click of its own: in the same click as the switches the game may refuse
    -- it ("Interface action failed because of an AddOn"), and then nothing seemed to happen.
    setupWin.apply:SetScript("OnClick", function()
        if rawget(setupWin, "reloadNext") then ReloadUI(); return end
        local reload = ns.SetupNeedsReload(setupPlan)
        local n = ns.ApplySetup(setupPlan)
        if not reload then
            setupWin:Hide()
            if n > 0 then ns.Print(L.SETUP_DONE:format(n)) end
            return
        end
        rawset(setupWin, "reloadNext", true)
        ns.SetupRows(setupPlan)
        setupWin.footer:SetStatus(L.SETUP_SAVED)
        setupWin.apply:SetText(L.SETUP_RELOAD)
        setupWin.apply:SetWidth(math.max(120, math.floor((tonumber(setupWin.apply.text:GetStringWidth()) or 100) + 28)))
        ns.Print(L.SETUP_SAVED)
    end)
    setupWin.later:SetScript("OnClick", function() setupWin:Hide() end)
    -- Closing it any way counts: it does not open by itself again.
    setupWin:HookScript("OnHide", function() ns.SetupDone() end)
end

-- Opens the setup window. auto: opened by the first run, so only when there is a module to pick.
function ns.OpenSetup(auto)
    setupPlan = ns.SetupPlan()
    if auto and #setupPlan == 0 then ns.SetupDone(); return nil end
    if not setupWin then buildSetup() end
    rawset(setupWin, "reloadNext", nil)
    if frame and frame:IsShown() then frame:Hide() end
    setupWin:Show()
    setupWin.list:SetData(setupItems())
    setupStatus()
    return setupWin, setupPlan
end

-- A page under Options > AddOns with a button that opens the hub.
function ns.RegisterSettings()
    local panel = CreateFrame("Frame")
    panel.name = L.TITLE
    local title = S.Text(panel, 16, S.Accent())
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(L.TITLE)
    local sub = S.Text(panel, 12, S.MUTED)
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetText(L.SUBTITLE .. " " .. L.HELP)
    local btn = S.Button(panel, 200, 30)
    btn:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -12)
    btn:SetText(L.OPEN_HUB)
    btn:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel.Close then SettingsPanel:Close(true) end
        if not frame or not frame:IsShown() then ns.Toggle() end
    end)
    local map = minimapRow(panel)
    map:SetWidth(240)
    map:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -12)
    local calm = calmRow(panel)
    calm:SetWidth(240)
    calm:SetPoint("TOPLEFT", map, "BOTTOMLEFT", 0, -4)
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, L.TITLE)
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

-- The minimap button: our icon on the minimap's edge. A click opens the hub, a drag moves it
-- around the minimap, and the switch in the hub or under Options hides it.
local mapButton

local function minimapRadius(ring) return S.MapRadius(ring) end

local function squareMinimap() return S.MapSquare() end

function ns.PlaceMinimap()
    for _, sw in ipairs(mapSwitches) do sw:SetChecked(ns.MinimapShown()) end
    if not mapButton then return end
    local x, y = ns.MinimapOffset(ns.MinimapAngle(), minimapRadius(), squareMinimap())
    mapButton:ClearAllPoints()
    mapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
    mapButton:SetShown(ns.MinimapShown())
end

local function mapRound(o)
    o.dense = denseTip
    return S.MapButton(o)
end

-- A right-click on the hub's button starts the Unlock mode at once (and saves it again).
function ns.MinimapClick(_, mouse)
    if mouse == "RightButton" then
        ns.SetMoving(not ns.moving)
    else
        ns.Toggle()
    end
end

-- The tooltip of a module's own button: its name, its line of the home page, what a click does.
function ns.PinTip(row)
    local key = "|cffffd100"
    local lines = { { title = row.title } }
    local sum = ns.SummaryOf(row)
    if sum then lines[#lines + 1] = { text = sum } end
    lines[#lines + 1] = { text = key .. L.MM_CLICK_KEY .. "|r " .. L.MM_OPEN }
    lines[#lines + 1] = { text = key .. L.MM_DRAG_KEY .. "|r " .. L.MM_DRAG }
    return lines
end

-- The modules' own buttons: one per pinned module that runs, built when first needed.
local pinButtons = {}

local function pinButton(key)
    local b = pinButtons[key]
    if b then return b end
    b = mapRound({
        name = "GulliToolkitMinimap" .. key,
        click = function(self) if self.row and self.row.info then self.row.info.open() end end,
        drag = function(a)
            ns.SetPinAngle(key, a)
            ns.PlacePins(true)
        end,
        tip = function() return ns.PinTip(pinButtons[key].row) end,
    })
    pinButtons[key] = b
    return b
end

-- Shows the buttons of ns.Pins and hides the others. moved: only the places changed (a drag).
function ns.PlacePins(moved)
    if not mapButton then return end
    local square = squareMinimap()
    -- Two buttons side by side on this minimap are this many degrees apart.
    ns.pinStep = S.MapStep(1)
    ns.pinStep2 = S.MapStep(2)
    local want = {}
    for _, row in ipairs(moved and {} or ns.Pins()) do want[row.key] = row end
    if moved then for key, b in pairs(pinButtons) do if b:IsShown() then want[key] = b.row end end end
    for key, row in pairs(want) do
        local b = pinButton(key)
        b.row = row
        b.icon:SetTexture(row.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        -- A module shown by default gets its place the first time it is drawn.
        if not ns.PinAngle(key) and not moved then
            local a, ring = ns.FreeAngle(ns.pinStep, ns.pinStep2)
            ns.SetPinAngle(key, a, ring)
        end
        local x, y = ns.MinimapOffset(ns.PinAngle(key) or ns.MinimapAngle(), minimapRadius(ns.PinRing(key)), square)
        b:ClearAllPoints()
        b:SetPoint("CENTER", Minimap, "CENTER", x, y)
        b:Show()
    end
    for key, b in pairs(pinButtons) do if not want[key] then b:Hide() end end
end

function ns.PinButton(key) return pinButtons[key] end

function ns.BuildMinimap()
    if mapButton or not Minimap then return mapButton end
    mapButton = mapRound({
        name = "GulliToolkitMinimapButton", icon = "Interface\\AddOns\\Gulli-Toolkit\\icon",
        click = ns.MinimapClick,
        drag = function(a)
            GulliToolkitDB.minimap = GulliToolkitDB.minimap or {}
            GulliToolkitDB.minimap.angle = a
            ns.PlaceMinimap()
        end,
        tip = ns.MinimapTip,
    })
    ns.PlaceMinimap()
    ns.PlacePins()
    return mapButton
end

function ns.MinimapButton() return mapButton end

-- The Unlock mode (/gulli unlock): a grid over the screen, a bar at the top that says what to
-- do, and a panel on the left with every frame of the running modules: a switch to show it, a
-- button that puts it back, Cancel and Save & lock. A click on a row or a frame selects it, and
-- the arrow keys move it by one (Shift: ten). Esc or the cross cancels.
local overlay, panel, sample
local gridLines = {}
local PANEL_W, PANEL_H = 420, 600
local STEPS = { 16, 32, 64 }

local function unlockDB()
    GulliToolkitDB = GulliToolkitDB or {}
    GulliToolkitDB.unlock = GulliToolkitDB.unlock or {}
    local u = GulliToolkitDB.unlock
    if u.snap == nil then u.snap = true end
    if not u.step then u.step = 32 end
    return u
end

local function applySnap()
    local u = unlockDB()
    GulliHUD = GulliHUD or {}
    GulliHUD.snap, GulliHUD.step = u.snap, u.step
end

-- Lines every step units out from the middle of the screen; the middle lines in the accent.
local function drawGrid()
    local step = unlockDB().step
    for _, t in ipairs(gridLines) do t:Hide() end
    local w = tonumber((UIParent:GetWidth())) or 1366
    local h = tonumber((UIParent:GetHeight())) or 768
    local n = 0
    local function line()
        n = n + 1
        local t = gridLines[n]
        if not t then
            t = S.Tex(overlay, "ARTWORK", 0, { 1, 1, 1, 0.06 })
            gridLines[n] = t
        end
        t:ClearAllPoints()
        t:Show()
        return t
    end
    for i = -math.ceil(w / 2 / step), math.ceil(w / 2 / step) do
        if i ~= 0 then
            local t = line()
            t:SetPoint("TOP", overlay, "TOP", i * step, 0)
            t:SetPoint("BOTTOM", overlay, "BOTTOM", i * step, 0)
            t:SetWidth(1)
        end
    end
    for i = -math.ceil(h / 2 / step), math.ceil(h / 2 / step) do
        if i ~= 0 then
            local t = line()
            t:SetPoint("LEFT", overlay, "LEFT", 0, i * step)
            t:SetPoint("RIGHT", overlay, "RIGHT", 0, i * step)
            t:SetHeight(1)
        end
    end
end

-- The frame a row stands for, and its mover (built when the module shows it for the mode).
local function moverOf(fr)
    if fr.module == "Toolkit" then return sample and sample.mover end
    local info = GulliToolkit.modules[fr.module]
    local list = info and info.frames
    for _, d in ipairs(type(list) == "table" and list or {}) do
        if (d.key or fr.module) == fr.key and type(d.frame) == "function" then
            local ok, f = pcall(d.frame)
            return ok and type(f) == "table" and rawget(f, "mover") or nil
        end
    end
end

local function placeSample()
    local at = GulliToolkitDB and GulliToolkitDB.toastAt
    local k = tonumber((sample:GetScale())) or 1
    if k <= 0 then k = 1 end
    sample:ClearAllPoints()
    sample:SetPoint("TOP", UIParent, "TOP", (tonumber(at and at[1]) or 0) / k, (tonumber(at and at[2]) or -150) / k)
end

-- A notice that stands where the stack starts, to place it.
local function buildSample()
    sample = S.ToastFrame("GulliToolkitToastSample", UIParent)
    S.ApplyScale(sample, S.BaseScale())
    sample:Set({ icon = "Interface\\Icons\\INV_Letter_15", title = L.FR_TOASTS, text = L.UNLOCK_TOAST })
    sample.close:Hide()
    sample:Hide()
    S.Mover(sample, { label = L.FR_TOASTS,
        save = function()
            GulliToolkitDB = GulliToolkitDB or {}
            GulliToolkitDB.toastAt = S.ToastPlace(sample)
            ns.ApplyToastPlace()
        end,
        reset = function()
            GulliToolkitDB = GulliToolkitDB or {}
            GulliToolkitDB.toastAt = nil
            placeSample()
            ns.ApplyToastPlace()
        end })
end

local function buildPanel()
    panel = S.Window("GulliToolkitUnlock", L.UNLOCK_TITLE, PANEL_W, PANEL_H,
        { sub = "/gulli unlock", icon = "Interface\\AddOns\\Gulli-Toolkit\\icon", strata = "FULLSCREEN_DIALOG", fullTitle = true })
    panel:ClearAllPoints()
    panel:SetPoint("LEFT", UIParent, "LEFT", 24, 0)
    -- The cross and Esc cancel.
    panel:HookScript("OnHide", function()
        if ns.moving then
            ns.SetMoving(false, true)
            ns.Print(L.UNLOCK_CANCELLED)
        end
    end)
    local body = panel.body
    local inner = PANEL_W - 2 * S.PAD
    local st = S.Stack(body)

    local u = unlockDB()
    local steps = {}
    for i, n in ipairs(STEPS) do steps[i] = tostring(n) end
    local tabs = S.Tabs(body, steps, 48, function(i)
        unlockDB().step = STEPS[i]
        applySnap()
        drawGrid()
    end, 30)
    for i, n in ipairs(STEPS) do if n == u.step then tabs:Select(i) end end
    tabs.frame:SetSize(3 * 48 + 4, 30)
    local card, ch = S.SettingsCard(body, nil, {
        { L.UNLOCK_SNAP, nil, function() return unlockDB().snap end,
          function(v) unlockDB().snap = v; applySnap() end, icon = "Interface\\Icons\\INV_Misc_Spyglass_03" },
        { L.UNLOCK_STEP, nil, control = tabs.frame, icon = "Interface\\Icons\\Ability_Hunter_Pathfinding" },
    })
    st:Add(card, ch)

    local head = CreateFrame("Frame", nil, body)
    head.label = S.Text(head, 12, S.GOLD_DIM, nil, "bold")
    head.label:SetPoint("LEFT", 2, 0)
    head.hideAll = S.Ghost(S.FitButton(head, L.UNLOCK_HIDE_ALL, 28, 90))
    head.hideAll:SetPoint("RIGHT")
    head.label:SetPoint("RIGHT", head.hideAll, "LEFT", -8, 0)
    head.label:SetWordWrap(false)
    head.hideAll:SetScript("OnClick", function()
        for _, fr in ipairs(ns.Frames()) do
            if fr.get and ns.FrameShown(fr) then ns.SetFrameShown(fr, false) end
        end
        ns.RefreshUnlock()
    end)
    st:Add(head, 30)
    panel.head = head

    local list = S.List(body, 48, function(r)
        r.icon = S.IconBox(r, 26)
        r.icon:SetPoint("LEFT", 4, 0)
        -- Reset at the right edge, then the switch (or "by itself") left of it, so both line up.
        r.reset = S.Button(r, 28, 28)
        S.SetButtonIcon(r.reset, "Interface\\Buttons\\UI-RefreshButton", 16)
        r.reset.btnIcon:ClearAllPoints()
        r.reset.btnIcon:SetPoint("CENTER")
        r.reset:SetPoint("RIGHT", -2, 0)
        r.reset:SetScript("OnEnter", function(self) tip(self, L.UNLOCK_RESET, {}) end)
        r.reset:SetScript("OnLeave", hideTip)
        r.sw = S.Switch(r)
        r.sw:SetPoint("RIGHT", r.reset, "LEFT", -10, 0)
        r.auto = S.Note(r, 12)
        r.auto:SetPoint("RIGHT", r.reset, "LEFT", -10, 0)
        r.auto:SetText(L.UNLOCK_AUTO)
        r.name = S.Text(r, 13)
        r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 10, 1)
        r.name:SetWordWrap(false)
        r.sub = S.Note(r, 12)
        r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -2)
        r.sub:SetWordWrap(false)
        r.hit = CreateFrame("Button", nil, r)
        r.hit:SetPoint("TOPLEFT")
        r.hit:SetPoint("BOTTOM")
    end, function(r, fr)
        r.icon:SetIcon(fr.icon)
        r.name:SetText(fr.label or "")
        r.sub:SetText(fr.title or "")
        local m = moverOf(fr)
        local sel = m ~= nil and GulliHUD ~= nil and GulliHUD.selected == m
        S.Fill(r, sel and { S.FILL[1], S.FILL[2], S.FILL[3], 0.34 } or S.CLEAR)
        r.sw:SetShown(fr.get ~= nil)
        r.auto:SetShown(fr.get == nil)
        local edge = fr.get and r.sw or r.auto
        for _, t in ipairs({ r.name, r.sub }) do
            t:SetPoint("RIGHT", edge, "LEFT", -8, 0)
        end
        r.hit:SetPoint("RIGHT", edge, "LEFT", -4, 0)
        if fr.get then
            r.sw:SetChecked(ns.FrameShown(fr))
            r.sw:SetScript("OnClick", function() ns.SetFrameShown(fr, not ns.FrameShown(fr)) end)
        end
        r.reset:SetEnabled(m ~= nil)
        r.reset:SetScript("OnClick", function() S.ResetMover(moverOf(fr)); ns.RefreshUnlock() end)
        r.hit:SetScript("OnClick", function() S.SelectMover(moverOf(fr)) end)
    end)
    list:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -st.y)
    list:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
    panel.list = list

    local ft = S.Footer(panel)
    panel.save = ft:Add(S.Primary(S.FitButton(ft, L.UNLOCK_SAVE, 32, 120)))
    panel.save:SetScript("OnClick", function()
        ns.SetMoving(false)
        ns.Print(L.MOVE_OFF)
    end)
    panel.cancel = ft:Add(S.FitButton(ft, L.UNLOCK_CANCEL, 32, 90))
    panel.cancel:SetScript("OnClick", function()
        ns.SetMoving(false, true)
        ns.Print(L.UNLOCK_CANCELLED)
    end)
    panel.footer = ft

    -- The arrow keys move the selected frame; every other key goes on to the game.
    panel:EnableKeyboard(true)
    panel:SetScript("OnKeyDown", function(self, key)
        local H = GulliHUD
        local d = ({ UP = { 0, 1 }, DOWN = { 0, -1 }, LEFT = { -1, 0 }, RIGHT = { 1, 0 } })[key]
        local free = not (InCombatLockdown and InCombatLockdown())
        if d and H and H.selected and free then
            local n = (IsShiftKeyDown and IsShiftKeyDown()) and 10 or 1
            S.NudgeMover(H.selected, d[1] * n, d[2] * n)
            if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
            return
        end
        if free and self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
    end)
end

-- The panel's list and counts again (a switch changed, a frame was selected).
function ns.RefreshUnlock()
    if not (panel and panel:IsShown()) then return end
    local frames = ns.Frames()
    local on, total = ns.FrameCount(frames)
    panel.head.label:SetText(S.Upper(L.UNLOCK_LIST:format(on, total)))
    panel.head.hideAll:SetEnabled(on > 0)
    -- A frame switched off stays placeable, darkened and marked on the screen.
    for _, fr in ipairs(frames) do
        local m = moverOf(fr)
        if m and m.SetOff then m:SetOff(fr.get ~= nil and not ns.FrameShown(fr), L.UNLOCK_OFF) end
    end
    panel.list:SetData(frames)
    local sel = GulliHUD and GulliHUD.selected
    local name = sel and sel.opts and sel.opts.label
    panel.footer:SetStatus(name and L.UNLOCK_SELECTED:format(name) or L.UNLOCK_HINT)
end

function ns.MoveOverlay(on)
    if not overlay then
        if not on then return end
        overlay = CreateFrame("Frame", "GulliToolkitMoveGrid", UIParent)
        overlay:SetAllPoints()
        overlay:SetFrameStrata("BACKGROUND")
        overlay:EnableMouse(false)
        local a = S.Accent()
        local cx = S.Tex(overlay, "ARTWORK", 1, { a[1], a[2], a[3], 0.35 })
        cx:SetPoint("TOP")
        cx:SetPoint("BOTTOM")
        cx:SetWidth(1)
        local cy = S.Tex(overlay, "ARTWORK", 1, { a[1], a[2], a[3], 0.35 })
        cy:SetPoint("LEFT")
        cy:SetPoint("RIGHT")
        cy:SetHeight(1)

        local bar = CreateFrame("Frame", "GulliToolkitMoveBar", UIParent)
        bar:SetFrameStrata("FULLSCREEN_DIALOG")
        bar:SetPoint("TOP", 0, -24)
        bar:SetHeight(40)
        S.HudPanel(bar)
        bar.text = S.Text(bar, 13)
        bar.text:SetPoint("CENTER")
        bar.text:SetText(L.MOVE_BAR)
        bar:SetWidth(math.floor((tonumber((bar.text:GetStringWidth())) or 400) + 32))
        overlay.bar = bar
        GulliHUD = GulliHUD or {}
        GulliHUD.onSelect = function() ns.RefreshUnlock() end
    end
    if on then
        applySnap()
        drawGrid()
        if not panel then buildPanel() end
        if not sample then buildSample() end
        placeSample()
        sample:Show()
        sample:SetMoving(true)
    elseif sample then
        sample:SetMoving(false)
        sample:Hide()
    end
    overlay:SetShown(on and true or false)
    overlay.bar:SetShown(on and true or false)
    -- The hub steps aside while frames are placed (it would cover them) and comes back after.
    if on then
        if frame and frame:IsShown() then
            ns.hubAside = true
            frame:Hide()
        end
    elseif ns.hubAside then
        ns.hubAside = nil
        if frame and not frame:IsShown() then frame:Show() end
    end
    if on then
        panel:Show()
        ns.RefreshUnlock()
    elseif panel and panel:IsShown() then
        panel:Hide()
    end
end
function ns.MoveGrid() return overlay end
function ns.UnlockPanel() return panel end
