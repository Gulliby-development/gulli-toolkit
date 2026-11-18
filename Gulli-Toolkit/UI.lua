-- The hub window. On the left a narrow list of the modules (their state in the colour of the name),
-- grouped by category, with the search on top. In the centre always one page: the module the
-- player clicked (its own window, docked; a narrow one keeps a card about the module beside
-- it), or the home page with the modules' summaries, the Recent feed and quick setup.
-- It only shows what Core.lua gives (ns.List, ns.Filter, ns.Groups, ns.Summaries, ns.Feed)
-- and calls ns.Switch, ns.SetLoaded, ns.ApplyPreset and the module's own window.

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
local TILE_COLS, TILE_MAX, TILE_H = 3, 9, 58
local LABEL_H = 20
local QUICK_W, LINE_H = 320, 24
-- The Quick setup buttons that are not presets (a preset names its own icon in ns.PRESETS).
local QUICK_ICON = {
    move = "Interface\\Icons\\Ability_Hunter_Pathfinding",
    transfer = "Interface\\Icons\\INV_Misc_Note_01",
    protect = "Interface\\Icons\\Spell_Holy_SealOfProtection",
    setup = "Interface\\Icons\\INV_Misc_Gear_02",
}

local GOOD, WAIT, BAD = S.GOOD, S.WARN, S.BAD
local LINE, HOVER = S.LINE, S.HOVER
local TOOLKIT_ICON = "Interface\\AddOns\\Gulli-Toolkit\\icon"
local MARK = "Interface\\AddOns\\Gulli-Toolkit\\Art\\Mark"

-- page: "home", "module", "protect", "transfer" or "errors"; inside: the key of the docked module.
local view = { page = "home", query = "" }
local frame, side, search, placeholder, scroll, list, empty
local scaleText, protectBtn, protectFrame, transfer, errorsFrame, readyFrame
local host, hubSwitch, offWin, insideWin, card, home, homeRow
local rows, heads = {}, {}

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
    win:Dock(host, {
        width = narrow and MID or HOST_W, height = HOST_H, right = { hubSwitch },
        back = goHome, popOut = popOut, onHide = windowHidden,
    })
    S.MotionIn(win, 6, S.BASE)
    ns.Refresh()
end

local function showPanel(name)
    leave()
    hidePanels()
    home:Hide()
    view.page = name
    if name == "protect" then protectFrame:Show()
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
    if not searching then
        place(homeRow, y)
        homeRow:SetSelected(view.page == "home")
        if view.page == "home" then selY = y end
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
    empty:SetShown(#shown == 0)
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

local tiles, feedLines, ovLines, cmdLines = {}, {}, {}, {}
local fillReady

local function makeTile(i)
    local t = CreateFrame("Button", nil, home.summary)
    t:SetSize(10, TILE_H)
    -- No edge: a tile stands out from the window by its shade only.
    S.Box(t, S.SURFACE, S.CLEAR, S.R_LG)
    S.Depth(t, S.R_LG)
    t.icon = S.IconBox(t, 32)
    t.icon:SetPoint("LEFT", 12, 0)
    t.name = S.Text(t, 12, S.GOLD, nil, "bold")
    t.name:SetPoint("TOPLEFT", t.icon, "TOPRIGHT", 10, 3)
    t.name:SetPoint("RIGHT", -10, 0)
    t.name:SetWordWrap(false)
    t.text = S.Text(t, 13, S.MUTED)
    t.text:SetPoint("TOPLEFT", t.name, "BOTTOMLEFT", 0, -2)
    t.text:SetPoint("RIGHT", -10, 0)
    t.text:SetJustifyV("TOP")
    t.text:SetMaxLines(2)
    t:SetScript("OnClick", function(self) enter(self.row) end)
    -- The whole line in a tooltip, in case two lines do not hold it.
    t:SetScript("OnEnter", function(self)
        S.Fill(self, S.RAISED)
        if self.row then tip(self, self.row.title, { self.full }, "ANCHOR_TOP") end
    end)
    t:SetScript("OnLeave", function(self) S.Fill(self, S.SURFACE); hideTip() end)
    tiles[i] = t
    return t
end

local function makeFeedLine(i)
    local b = CreateFrame("Button", nil, home.recent.body)
    b:SetHeight(LINE_H)
    S.Box(b, S.CLEAR, S.CLEAR, S.R_MD)
    b.ago = S.Text(b, 12, S.FAINT)
    b.ago:SetPoint("LEFT", 4, 0)
    b.ago:SetWidth(48)
    b.ago:SetWordWrap(false)
    b.text = S.Text(b, 13, S.MUTED)
    b.text:SetPoint("LEFT", b.ago, "RIGHT", 6, 0)
    b.text:SetPoint("RIGHT", -4, 0)
    b.text:SetWordWrap(false)
    b:SetScript("OnClick", function(self) enter(findRow(self.key)) end)
    b:SetScript("OnEnter", function(self)
        S.Fill(self, HOVER)
        tip(self, self.who, { self.full }, "ANCHOR_TOP")
    end)
    b:SetScript("OnLeave", function(self) S.Fill(self, S.CLEAR); hideTip() end)
    feedLines[i] = b
    return b
end

-- A line of the Modules card or the commands list: text, a tooltip with the whole text, and a
-- click that opens the module it names.
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

-- The lines of the Modules card from ns.Overview: what waits, what the game refuses, what was
-- updated and what uses the most memory. { { head, color, names, row, open } }
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
    if #o.paused > 0 then out[#out + 1] = { L.OV_PAUSED, S.MUTED, names(o.paused), o.paused[1] } end
    if #o.blocked > 0 then
        out[#out + 1] = { L.OV_BLOCKED, S.BAD,
            names(o.blocked, function(r) return " (" .. ns.ReasonText(r.reason) .. ")" end), o.blocked[1] }
    end
    if #o.new > 0 then
        out[#out + 1] = { L.OV_NEW, S.GOOD, names(o.new, function(r) return " " .. r.version end), o.new[1] }
    end
    local quiet = #out - ((o.errors or 0) > 0 and 1 or 0) - (#o.paused > 0 and 1 or 0)
    if quiet == 0 and (o.errors or 0) == 0 then table.insert(out, 1, { L.OV_FINE, S.GOOD, "" }) end
    if #o.heavy > 0 then
        local t = {}
        for i = 1, math.min(3, #o.heavy) do t[i] = o.heavy[i].row.title .. " " .. ns.Size(o.heavy[i].kb) end
        out[#out + 1] = { L.OV_HEAVY, S.FAINT, table.concat(t, ", "), o.heavy[1].row }
    end
    return out
end

-- One pip per module: green runs, dark is off or paused, orange waits for a reload, red is
-- refused by the game. The number of modules that are on stands above them.
local pips = {}
local PIP_W, PIP_GAP = 6, 2
local function fillPips(data)
    local n = 0
    for _, r in ipairs(data) do
        n = n + 1
        local p = pips[n]
        if not p then
            p = S.Tex(home.ovPips, "ARTWORK", 0, S.GOOD)
            p:SetSize(PIP_W, 10)
            pips[n] = p
        end
        local c = S.OFF
        if r.state == "blocked" then c = S.BAD
        elseif r.state == "reload" then c = S.WARN
        elseif r.state == "ready" and not r.paused then c = S.GOOD end
        p:SetVertexColor(c[1], c[2], c[3], 1)
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", ((n - 1) % 24) * (PIP_W + PIP_GAP), -math.floor((n - 1) / 24) * 14)
        p:Show()
    end
    for i = n + 1, #pips do pips[i]:Hide() end
end

local function fillOverview(data, height)
    local o = ns.Overview(data)
    home.ovCount:SetText(o.on)
    home.ovTotal:SetText("/ " .. o.total)
    home.ovTotal:ClearAllPoints()
    home.ovTotal:SetPoint("BOTTOMLEFT", home.ovCount, "BOTTOMRIGHT", 6, 3)
    local parts = { L.OV_RUNNING:format(o.running) }
    if o.kb > 0 then parts[#parts + 1] = L.OV_MEMORY:format(ns.Size(o.kb)) end
    home.ovHead:SetText(S.Emph(table.concat(parts, S.DOT), S.TEXT))
    fillPips(data)
    home.ovReload:SetShown(#o.reload > 0)
    -- The lines wrap (never cut); as many as the card holds, each with its whole text in the
    -- tooltip and a click that opens the module it names.
    local lines = overviewLines(o)
    local width = math.max(1, (tonumber(home.ovBox:GetWidth()) or 0) - 8)
    local y, room = 0, (height or 999) - 36 - S.INSET
    local shown = 0
    for i, e in ipairs(lines) do
        local b = ovLines[i] or makeLine(home.ovBox, ovLines, i)
        b.text:SetWordWrap(true)
        b.text:SetMaxLines(2)
        b.text:SetJustifyV("TOP")
        b.head, b.full, b.row, b.open = e[1], e[3] ~= "" and e[3] or nil, e[4], e[5]
        b.text:SetText(S.Hex(e[2]) .. e[1] .. "|r" .. (e[3] ~= "" and ("  " .. e[3]) or ""))
        b.text:SetWidth(width)
        local h = math.min(2, math.max(1, math.ceil((tonumber(b.text:GetStringWidth()) or 0) / width))) * 16 + 4
        if 20 + y + h > room then b:Hide() else
            b:SetHeight(h)
            b.text:ClearAllPoints()
            b.text:SetPoint("TOPLEFT", 4, -2)
            b.text:SetPoint("BOTTOMRIGHT", -4, 2)
            place(b, 20 + y)
            b:Show()
            shown = i
            y = y + h
        end
    end
    for i = math.max(shown, #lines) + 1, #ovLines do ovLines[i]:Hide() end
end

-- The height the command lines may fill in a Quick setup card of height h whose commands title
-- sits cmdTop into the body: the body is the card less its 36 title and its inset.
function ns.CommandsRoom(h, cmdTop)
    return math.max(0, h - 36 - S.INSET - cmdTop - 24)
end

-- The slash commands of the modules that run, as many as the Quick setup card has room for.
local function fillCommands(data)
    -- The lines start 24 below the title, inside the body (the card less its title and inset).
    local room = math.floor((ns.CommandsRoom(home.quick:GetHeight(), home.cmdTop)) / LINE_H)
    local list = {}
    for _, r in ipairs(data) do if r.running and r.slash then list[#list + 1] = r end end
    home.cmdTitle:SetShown(room > 0 and #list > 0)
    local shown = math.max(0, math.min(#list, room))
    if shown < #list and shown > 0 then shown = shown - 1 end
    for i = 1, shown do
        local b = cmdLines[i] or makeLine(home.quick.body, cmdLines, i)
        local r = list[i]
        b.row, b.head, b.full = r, nil, nil
        b.text:SetText(S.Hex(S.Accent()) .. r.slash .. "|r  " .. r.title)
        place(b, home.cmdTop + 24 + (i - 1) * LINE_H)
        b:Show()
    end
    local n = shown
    if shown < #list and room > 0 then
        n = n + 1
        local b = cmdLines[n] or makeLine(home.quick.body, cmdLines, n)
        b.row, b.head, b.full = nil, nil, nil
        b.text:SetText(S.Hex(S.FAINT) .. L.COMMANDS_MORE:format(#list - shown) .. "|r")
        place(b, home.cmdTop + 24 + (n - 1) * LINE_H)
        b:Show()
    end
    for i = n + 1, #cmdLines do cmdLines[i]:Hide() end
end

-- The Ready card: one chip per check of ns.Readiness, two per row, the ones not met first:
-- a red edge and dot while a check is not met, a green dot when it is. Returns its height, 0
-- when it is switched off.
local readyChips = {}
local CHIP_H = 28
local function makeChip(i)
    local c = CreateFrame("Frame", nil, home.ready.body)
    c:SetHeight(CHIP_H)
    S.Box(c, S.RAISED, S.CLEAR, S.R_MD)
    S.Depth(c, S.R_MD)
    c.icon = S.IconBox(c, 18)
    c.icon:SetPoint("LEFT", 6, 0)
    c.dot = S.Circle(c, 8, S.GOOD, "OVERLAY")
    c.dot:SetPoint("RIGHT", -8, 0)
    c.value = S.Text(c, 13)
    c.value:SetPoint("LEFT", c.icon, "RIGHT", 7, 0)
    c.value:SetPoint("RIGHT", c.dot, "LEFT", -6, 0)
    c.value:SetWordWrap(false)
    c:EnableMouse(true)
    c:SetScript("OnEnter", function(self) if self.text then tip(self, self.text, {}) end end)
    c:SetScript("OnLeave", hideTip)
    readyChips[i] = c
    return c
end

function fillReady()
    local card = home.ready
    if not ns.ReadyGet("show") then
        card:Hide()
        home.overview:SetPoint("TOPLEFT", home.summaryCard, "BOTTOMLEFT", 0, -GAP)
        return 0
    end
    card:Show()
    home.overview:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, -GAP)
    local list = {}
    for _, r in ipairs(ns.Readiness()) do if not r.ok then list[#list + 1] = r end end
    for _, r in ipairs(ns.Readiness()) do if r.ok then list[#list + 1] = r end end
    local ok, n = ns.ReadyCount(list)
    card:SetTitle(L.READY .. "  " .. S.Hex(ok == n and S.GOOD or S.WARN) .. ok .. "/" .. n .. "|r", "")
    local width = HOST_W - QUICK_W - GAP - 2 * S.INSET
    local cols = 2
    local w = math.floor((width - (cols - 1) * 6) / cols)
    for i, r in ipairs(list) do
        local c = readyChips[i] or makeChip(i)
        c.icon:SetIcon(r.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        c.value:SetText(r.text)
        local tc = r.ok and S.TEXT or { 1, 1, 1, 1 }
        c.value:SetTextColor(tc[1], tc[2], tc[3], 1)
        local dc = r.ok and S.GOOD or S.BAD
        c.dot:SetVertexColor(dc[1], dc[2], dc[3], 1)
        S.SetBorder(c, r.ok and S.CLEAR or { S.BAD[1], S.BAD[2], S.BAD[3], 0.55 })
        c.text = r.text
        c:SetWidth(w)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", ((i - 1) % cols) * (w + 6), -math.floor((i - 1) / cols) * (CHIP_H + 6))
        c:Show()
    end
    for i = #list + 1, #readyChips do readyChips[i]:Hide() end
    local rows = math.max(1, math.ceil(#list / cols))
    return card:Fit(rows * (CHIP_H + 6) - 6)
end

local OV_H = 112

local function fillHome(data)
    local list2 = ns.Summaries(data)
    local n = math.min(#list2, TILE_MAX)
    local w = math.floor((HOST_W - (TILE_COLS - 1) * 8) / TILE_COLS)
    for i = 1, n do
        local t = tiles[i] or makeTile(i)
        local s = list2[i]
        t.row = s.row
        t.icon:SetIcon(s.icon or s.row.icon)
        t.name:SetText(S.Upper(s.row.title))
        t.full = s.text
        t.text:SetText(S.Emph(s.text, S.TEXT))
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", ((i - 1) % TILE_COLS) * (w + 8), -math.floor((i - 1) / TILE_COLS) * (TILE_H + 8))
        t:SetSize(w, TILE_H)
        t:Show()
    end
    for i = n + 1, #tiles do tiles[i]:Hide() end
    home.noSummary:SetShown(n == 0)
    local lines = math.max(1, math.ceil(n / TILE_COLS))
    local inner = n == 0 and 36 or (lines * (TILE_H + 8) - 8)
    local sh = LABEL_H + inner
    home.summaryCard:SetHeight(sh)
    local lower = HOST_H - sh - GAP
    home.quick:SetHeight(lower)
    local rdh = fillReady()
    local rest = lower - (rdh > 0 and (rdh + GAP) or 0)
    -- The Modules card keeps its height; the Recent feed takes what is left (at least 3 lines).
    local oh = math.max(OV_H, rest - GAP - (36 + S.INSET + 3 * LINE_H))
    oh = math.min(oh, OV_H + 40)
    home.overview:SetHeight(oh)
    fillOverview(data, oh)
    local rh = rest - oh - GAP
    home.recent:SetHeight(rh)
    fillCommands(data)

    local feed = ns.Feed()
    local room = math.max(1, math.floor((rh - 36 - S.INSET) / LINE_H))
    local now = time()
    local shown = math.min(#feed, room)
    for i = 1, shown do
        local b = feedLines[i] or makeFeedLine(i)
        local e = feed[i]
        local who = tostring(e.key or "")
        if ns.T.en["M_" .. who] then who = L["M_" .. who] end
        b.key, b.who, b.full = e.key, who, e.text
        b.ago:SetText(ns.Ago(e.t, now))
        b.text:SetText(S.Hex(S.TEXT) .. who .. "|r  " .. e.text)
        place(b, (i - 1) * LINE_H)
        b:Show()
    end
    for i = shown + 1, #feedLines do feedLines[i]:Hide() end
    home.noRecent:SetShown(#feed == 0)
    home.clear:SetShown(#feed > 0)
    home.move:SetText(ns.moving and L.MOVE_DONE or L.MOVE)
    -- How many frames show on the screen, so the Unlock mode is easy to find.
    local fon, ftotal = ns.FrameCount()
    home.move.value:SetText(ftotal > 0 and (fon .. "/" .. ftotal) or "")
end

-- The whole window -----------------------------------------------------------------------------

local function applyScale()
    local sw = tonumber(UIParent:GetWidth()) or W
    local sh = tonumber(UIParent:GetHeight()) or H
    local user = (GulliToolkitDB and GulliToolkitDB.scale) or 1
    S.ApplyScale(frame, ns.HubScale(user, sw, sh, W, H))
    scaleText:SetText(math.floor(user * 100 + 0.5) .. "%")
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
            if insideWin == offWin then offWindow(row) end
            if card:IsShown() then fillCard(row) end
        end
    end
    if view.page == "home" then fillHome(data) end

    protectBtn:SetText(L.PROTECTED)
    protectBtn.value:SetText(#ns.Protected())
    if protectFrame and protectFrame:IsShown() then ns.RefreshProtected() end
end

-- Protected items: a page in the centre, with a drop zone for items from the bags.
local protRows = {}
local function itemInfo(id)
    local name, _, _, _, _, _, _, _, _, icon = (C_Item and C_Item.GetItemInfo or GetItemInfo)(id)
    return name, icon
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
        r.name:SetText(name or ("item:" .. id))
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
    local close = S.Close(p, function() showHome() end)
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

-- The header: the window's own (icon, title, version), plus the size buttons.
local function buildHeader()
    local plus = frame:AddHeaderButton(S.Ghost(S.Button(frame, 28, 28)))
    plus:SetText("+")
    plus:SetScript("OnClick", function() nudgeScale(0.1) end)
    scaleText = S.Text(frame.bar, 12, S.FAINT)
    scaleText:SetWidth(40)
    scaleText:SetJustifyH("CENTER")
    scaleText:SetPoint("RIGHT", plus, "LEFT", 0, 0)
    local minus = S.Ghost(S.Button(frame.bar, 28, 28))
    minus:SetPoint("RIGHT", scaleText, "LEFT", 0, 0)
    minus:SetText("-")
    minus:SetScript("OnClick", function() nudgeScale(-0.1) end)
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
    -- The dim emblem of the toolkit behind the lower end of the module list.
    local mark = side:CreateTexture(nil, "BACKGROUND", nil, -5)
    mark:SetTexture(MARK)
    mark:SetSize(SIDE - 20, SIDE - 20)
    mark:SetPoint("BOTTOM", 0, 18)
    mark:SetVertexColor(1, 0.86, 0.66, 0.06)
    side.mark = mark
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

-- A full-width tool row of Quick setup: icon, label, an optional value on the right.
local function toolRow(parent, text, icon, onClick)
    local b = S.Button(parent, QUICK_W - 2 * S.INSET, 28)
    S.SetButtonIcon(b, icon, 18)
    b.text:ClearAllPoints()
    b.text:SetPoint("LEFT", b.btnIcon, "RIGHT", 8, 0)
    b.text:SetPoint("RIGHT", -40, 0)
    b.text:SetJustifyH("LEFT")
    b:SetText(text)
    b.value = S.Text(b, 13, S.MUTED)
    b.value:SetPoint("RIGHT", -10, 0)
    b.value:SetJustifyH("RIGHT")
    b:SetScript("OnClick", onClick)
    return b
end

local function buildHome()
    home = CreateFrame("Frame", nil, host)
    home:SetAllPoints(host)
    home:Show()

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

    local quick = S.Card(home, L.QUICK)
    quick:SetWidth(QUICK_W)
    quick:SetPoint("TOPRIGHT", sc, "BOTTOMRIGHT", 0, -GAP)
    home.quick = quick
    local q = quick.body
    local bw = math.floor((QUICK_W - 2 * S.INSET - 6) / 2)
    for i, p in ipairs(ns.PRESETS) do
        local b = S.Button(q, bw, 30)
        b:SetPoint("TOPLEFT", ((i - 1) % 2) * (bw + 6), -math.floor((i - 1) / 2) * 36)
        b:SetText(L["PRESET_" .. p.key])
        S.SetButtonIcon(b, p.icon, 18)
        b:SetScript("OnClick", function()
            local n = ns.ApplyPreset(p.key)
            ns.Print(n > 0 and L.PRESET_DONE:format(n) or L.PRESET_SAME)
        end)
        b:HookScript("OnEnter", function(self)
            local names = {}
            for _, k in ipairs(p.modules) do names[#names + 1] = (moduleName(k)) end
            tip(self, L["PRESET_" .. p.key], { L.PRESET_TIP, table.concat(names, ", ") })
        end)
        b:HookScript("OnLeave", hideTip)
    end
    local y = math.ceil(#ns.PRESETS / 2) * 36 + 4
    home.move = toolRow(q, L.MOVE, QUICK_ICON.move, function()
        if ns.SetMoving(not ns.moving) then ns.Print(ns.moving and L.MOVE_ON or L.MOVE_OFF) end
    end)
    home.move:SetPoint("TOPLEFT", 0, -y)
    local tr = toolRow(q, L.TRANSFER, QUICK_ICON.transfer, function()
        if not transfer then buildTransfer() end
        showPanel("transfer")
    end)
    tr:SetPoint("TOPLEFT", 0, -(y + 32))
    protectBtn = toolRow(q, L.PROTECTED, QUICK_ICON.protect, function()
        if not protectFrame then buildProtected() end
        if protectFrame:IsShown() then showHome() else showPanel("protect") end
    end)
    protectBtn:SetPoint("TOPLEFT", 0, -(y + 64))
    local setup = toolRow(q, L.SETUP, QUICK_ICON.setup, function() ns.OpenSetup() end)
    setup:SetPoint("TOPLEFT", 0, -(y + 96))
    home.setup = setup
    y = y + 128
    local l1 = S.Tex(q, "ARTWORK", 0, LINE)
    l1:SetHeight(1)
    l1:SetPoint("TOPLEFT", 0, -(y + 2))
    l1:SetPoint("TOPRIGHT", 0, -(y + 2))
    local map = minimapRow(q)
    map:SetPoint("TOPLEFT", 0, -(y + 8))
    map:SetPoint("TOPRIGHT", 0, -(y + 8))
    local calm = calmRow(q)
    calm:SetPoint("TOPLEFT", 0, -(y + 38))
    calm:SetPoint("TOPRIGHT", 0, -(y + 38))
    home.calm = calm
    -- Under a hairline, the slash commands (accent: they can be clicked); no label, as the
    -- accent already says what they are. The lines start 24 under cmdTop.
    local line2 = S.Tex(q, "ARTWORK", 0, LINE)
    line2:SetHeight(1)
    line2:SetPoint("TOPLEFT", 0, -(y + 74))
    line2:SetPoint("TOPRIGHT", 0, -(y + 74))
    home.cmdTop = y + 78 - 24
    home.cmdTitle = { SetShown = function() end }

    local ready = S.Card(home, L.READY, "")
    ready:SetPoint("TOPLEFT", sc, "BOTTOMLEFT", 0, -GAP)
    ready:SetPoint("TOPRIGHT", quick, "TOPLEFT", -GAP, 0)
    ready:SetHeight(80)
    home.ready = ready
    ready.title:SetPoint("RIGHT", ready, "RIGHT", -100, 0)
    local rs = link(ready, L.READY_SET)
    rs:SetPoint("TOPRIGHT", -6, -7)
    rs:SetScript("OnClick", function()
        if not readyFrame then ns.BuildReady() end
        if readyFrame:IsShown() then showHome() else showPanel("ready") end
    end)

    local ov = S.Card(home, L.OV_TITLE)
    ov:SetPoint("TOPLEFT", ready, "BOTTOMLEFT", 0, -GAP)
    ov:SetPoint("TOPRIGHT", quick, "TOPLEFT", -GAP, 0)
    home.overview = ov
    home.ovReload = S.Primary(S.FitButton(ov, L.RELOAD, 26, 90))
    home.ovReload:SetPoint("TOPRIGHT", -8, -6)
    home.ovReload:SetScript("OnClick", function() ReloadUI() end)
    -- The number of modules that are on, big, and a pip per module under it; the lines beside.
    home.ovCount = S.Text(ov.body, 28, { 1, 1, 1, 1 }, nil, "title")
    home.ovCount:SetPoint("TOPLEFT", 0, 2)
    home.ovTotal = S.Text(ov.body, 13, S.MUTED)
    home.ovPips = CreateFrame("Frame", nil, ov.body)
    home.ovPips:SetPoint("TOPLEFT", 0, -38)
    home.ovPips:SetSize(24 * (PIP_W + PIP_GAP), 24)
    local box = CreateFrame("Frame", nil, ov.body)
    box:SetPoint("TOPLEFT", 24 * (PIP_W + PIP_GAP) + 12, 0)
    box:SetPoint("BOTTOMRIGHT")
    box:SetWidth(HOST_W - QUICK_W - GAP - 2 * S.INSET - (24 * (PIP_W + PIP_GAP) + 12))
    home.ovBox = box
    home.ovHead = S.Text(box, 13, S.MUTED)
    home.ovHead:SetPoint("TOPLEFT", 4, 0)
    home.ovHead:SetPoint("TOPRIGHT", -4, 0)
    home.ovHead:SetWordWrap(false)

    local recent = S.Card(home, L.RECENT)
    recent:SetPoint("TOPLEFT", ov, "BOTTOMLEFT", 0, -GAP)
    recent:SetPoint("TOPRIGHT", ov, "BOTTOMRIGHT", 0, -GAP)
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
    -- Behind the centre: a warm light from its top left and the emblem, very dim, low on the
    -- right, so the see-through cards and tiles have something to show.
    local light = frame:CreateTexture(nil, "BACKGROUND", nil, -5)
    light:SetTexture(S.RADIAL)
    light:SetPoint("TOPLEFT", host, "TOPLEFT", -GAP, 0)
    light:SetPoint("BOTTOMRIGHT", host, "CENTER", 0, -40)
    light:SetVertexColor(0.85, 0.62, 0.32, 0.07)
    local mark = frame:CreateTexture(nil, "BACKGROUND", nil, -5)
    mark:SetTexture(MARK)
    mark:SetSize(360, 360)
    mark:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 20, -20)
    mark:SetVertexColor(1, 0.86, 0.66, 0.035)
    frame.light, frame.mark = light, mark
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
function ns.Inside() return insideWin end
function ns.Home() return home end
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

local function minimapRadius()
    return (Minimap:GetWidth() or 140) / 2 + 6
end

local function squareMinimap()
    return GetMinimapShape ~= nil and GetMinimapShape() == "SQUARE"
end

function ns.PlaceMinimap()
    for _, sw in ipairs(mapSwitches) do sw:SetChecked(ns.MinimapShown()) end
    if not mapButton then return end
    local x, y = ns.MinimapOffset(ns.MinimapAngle(), minimapRadius(), squareMinimap())
    mapButton:ClearAllPoints()
    mapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
    mapButton:SetShown(ns.MinimapShown())
end

local function followCursor(self)
    local cx, cy = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    if not cx or not px then return end
    GulliToolkitDB.minimap = GulliToolkitDB.minimap or {}
    GulliToolkitDB.minimap.angle = math.floor(ns.AngleTo(cx, cy, px / scale, py / scale) + 0.5)
    ns.PlaceMinimap()
end

function ns.BuildMinimap()
    if mapButton or not Minimap then return mapButton end
    local b = CreateFrame("Button", "GulliToolkitMinimapButton", Minimap)
    b:SetSize(32, 32)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 8)
    b:RegisterForClicks("LeftButtonUp")
    b:RegisterForDrag("LeftButton")
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture("Interface\\AddOns\\Gulli-Toolkit\\icon")
    -- The icon is square with dark corners: a round mask fits it to the minimap.
    if not S.RoundMask(b, icon) and icon.SetMask then icon:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask") end
    b.icon = icon
    local glow = b:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAllPoints()
    glow:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    glow:SetBlendMode("ADD")
    b:SetScript("OnMouseDown", function() icon:SetPoint("TOPLEFT", 1, -1); icon:SetPoint("BOTTOMRIGHT", -1, 1) end)
    b:SetScript("OnMouseUp", function() icon:SetAllPoints() end)
    b:SetScript("OnClick", function() ns.Toggle() end)
    b:SetScript("OnDragStart", function(self)
        self.dragging = true
        self:SetScript("OnUpdate", followCursor)
        GameTooltip:Hide()
    end)
    b:SetScript("OnDragStop", function(self)
        self.dragging = nil
        self:SetScript("OnUpdate", nil)
        icon:SetAllPoints()
    end)
    b:SetScript("OnEnter", function(self)
        if self.dragging then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        for _, l in ipairs(ns.MinimapTip()) do
            if l.title then GameTooltip:SetText(l.title, S.GOLD[1], S.GOLD[2], S.GOLD[3])
            else GameTooltip:AddLine(l.text, 1, 1, 1) end
        end
        GameTooltip:Show()
        denseTip(true)
    end)
    b:SetScript("OnLeave", function() denseTip(false); GameTooltip:Hide() end)
    mapButton = b
    ns.PlaceMinimap()
    return b
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
