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
local H = S.HEADER_H + 2 * S.PAD + HOST_H
local LIST_W = SIDE - 2 * S.INSET - 10
local ROW_H, HEAD_H = 30, 30
local TILE_COLS, TILE_MAX, TILE_H = 3, 12, 58
local QUICK_W, LINE_H = 320, 24
-- The Quick setup buttons that are not presets (a preset names its own icon in ns.PRESETS).
local QUICK_ICON = {
    move = "Interface\\Icons\\Ability_Hunter_Pathfinding",
    transfer = "Interface\\Icons\\INV_Misc_Note_01",
    protect = "Interface\\Icons\\Spell_Holy_SealOfProtection",
}

local GOOD, WAIT, BAD = S.GOOD, S.WARN, S.BAD
local LINE, HOVER = S.LINE, S.HOVER
local TOOLKIT_ICON = "Interface\\AddOns\\Gulli-Toolkit\\icon"

-- page: "home", "module", "protect" or "transfer"; inside: the key of the docked module.
local view = { page = "home", query = "" }
local frame, side, search, placeholder, scroll, list, empty
local scaleText, protectBtn, protectFrame, transfer
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
    if row.state == "off" then return L.OFF, S.MUTED end
    if row.state == "reload" then return L.STATE_RELOAD, WAIT end
    if row.state == "blocked" then return L.STATE_BLOCKED:format(ns.ReasonText(row.reason)), BAD end
    return L.NOT_INSTALLED, BAD
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

-- The page for a module that is not loaded (off, waiting for a reload, refused, not installed).
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
    elseif row.state == "missing" then
        offWin.empty:Set(L.MISSING_HINT)
    else
        offWin.empty:Set(row.state == "reload" and L.INSIDE_RELOAD or L.INSIDE_OFF)
    end
    offWin.reload:SetShown(row.state == "reload")
    return offWin
end

local function hidePanels()
    if protectFrame then protectFrame:Hide() end
    if transfer then transfer:Hide() end
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
    view.page = "home"
    home:Show()
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
    local switchable = row.state ~= "missing"
    hubSwitch:SetChecked(row.on)
    win:Dock(host, {
        width = narrow and MID or HOST_W, height = HOST_H, right = switchable and { hubSwitch } or {},
        back = goHome, popOut = popOut, onHide = windowHidden,
    })
    if not switchable then hubSwitch:Hide() end
    ns.Refresh()
end

local function showPanel(name)
    leave()
    hidePanels()
    home:Hide()
    view.page = name
    if name == "protect" then protectFrame:Show() else transfer:Show() end
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

local function selectable(r)
    S.Box(r, S.CLEAR, S.CLEAR, S.R_MD)
    r.bar = line(r, S.Accent())
    r.bar:SetPoint("TOPLEFT", 1, -8)
    r.bar:SetPoint("BOTTOMLEFT", 1, 8)
    r.bar:SetWidth(3)
    function r:SetSelected(on)
        self.selected = on
        S.Fill(self, on and S.RAISED or S.CLEAR)
        self.bar:SetShown(on)
    end
    r:SetScript("OnLeave", function(self)
        if not self.selected then S.Fill(self, S.CLEAR) end
        hideTip()
    end)
end

local function makeRow(i)
    local r = CreateFrame("Button", nil, list)
    r:SetHeight(ROW_H)
    selectable(r)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(18, 18)
    r.icon:SetPoint("LEFT", 8, 0)
    r.icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    S.RoundMask(r, r.icon)
    -- A dot on the icon: updated since the player last opened it.
    r.dot = S.Circle(r, 7, S.Accent(), "OVERLAY")
    r.dot:SetPoint("CENTER", r.icon, "TOPRIGHT", 0, 0)
    r.title = S.Text(r, 12)
    r.title:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
    r.title:SetPoint("RIGHT", -4, 0)
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
    r.icon:SetAlpha(live and 1 or 0.55)
    r.title:SetText(row.title)
    -- The state shows in the colour of the name; the tooltip and the page say why. The switch
    -- itself is in the header of the module's page.
    local tc = S.TEXT
    if row.state == "reload" then tc = WAIT
    elseif row.state == "blocked" then tc = BAD
    elseif not live then tc = S.FAINT end
    r.title:SetTextColor(tc[1], tc[2], tc[3], 1)
    r.dot:SetShown(row.new == true)
    r:SetSelected(view.page == "module" and view.inside == row.key)
    r:Show()
end

local function makeHead(i)
    local h = CreateFrame("Frame", nil, list)
    h:SetHeight(HEAD_H)
    h.text = S.Text(h, 11, S.FAINT)
    h.text:SetPoint("BOTTOMLEFT", 2, 8)
    h.text:SetPoint("RIGHT", -4, 0)
    h.text:SetWordWrap(false)
    h.rule = line(h, S.EDGE)
    h.rule:SetHeight(1)
    h.rule:SetPoint("BOTTOMLEFT", 0, 0)
    h.rule:SetPoint("BOTTOMRIGHT", 0, 0)
    heads[i] = h
    return h
end

local function fillSide(data)
    local searching = view.query ~= ""
    local shown = ns.Filter(data, "All", "all", view.query)
    local counts = ns.Counts(data)
    local y, ri, hi = 0, 0, 0
    homeRow:SetShown(not searching)
    if not searching then
        place(homeRow, y)
        homeRow:SetSelected(view.page == "home")
        y = y + ROW_H
    end
    for _, g in ipairs(ns.Groups(shown)) do
        hi = hi + 1
        local h = heads[hi] or makeHead(hi)
        local c = counts[g.key] or { on = 0, total = 0 }
        h.cat = g.key
        h.text:SetText(catName(g.key) .. "  " .. c.on .. "/" .. c.total)
        place(h, y)
        h:Show()
        y = y + HEAD_H
        for _, row in ipairs(g.rows) do
            ri = ri + 1
            local r = rows[ri] or makeRow(ri)
            fillRow(r, row)
            place(r, y)
            y = y + ROW_H
        end
    end
    for i = ri + 1, #rows do rows[i]:Hide() end
    for i = hi + 1, #heads do heads[i]:Hide() end
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
    d.cat:SetText(catName(row.category))
    local st, color = stateText(row)
    d.state:SetText(st)
    d.state:SetTextColor(color[1], color[2], color[3], 1)
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

local function makeTile(i)
    local t = CreateFrame("Button", nil, home.summary)
    t:SetSize(10, TILE_H)
    S.Box(t, S.SURFACE, S.EDGE, S.R_LG)
    t.icon = S.IconBox(t, 28)
    t.icon:SetPoint("LEFT", 10, 0)
    t.name = S.Text(t, 11, S.MUTED)
    t.name:SetPoint("TOPLEFT", t.icon, "TOPRIGHT", 10, 2)
    t.name:SetPoint("RIGHT", -10, 0)
    t.name:SetWordWrap(false)
    t.text = S.Text(t, 12)
    t.text:SetPoint("TOPLEFT", t.name, "BOTTOMLEFT", 0, -4)
    t.text:SetPoint("RIGHT", -10, 0)
    t.text:SetJustifyV("TOP")
    t.text:SetMaxLines(2)
    t:SetScript("OnClick", function(self) enter(self.row) end)
    t:SetScript("OnEnter", function(self) S.SetBorder(self, S.Accent()) end)
    t:SetScript("OnLeave", function(self) S.SetBorder(self, S.EDGE) end)
    tiles[i] = t
    return t
end

local function makeFeedLine(i)
    local b = CreateFrame("Button", nil, home.recent.body)
    b:SetHeight(LINE_H)
    S.Box(b, S.CLEAR, S.CLEAR, S.R_MD)
    b.ago = S.Text(b, 11, S.FAINT)
    b.ago:SetPoint("LEFT", 4, 0)
    b.ago:SetWidth(52)
    b.ago:SetWordWrap(false)
    b.text = S.Text(b, 12, S.MUTED)
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
    b.text = S.Text(b, size or 12, S.MUTED)
    b.text:SetPoint("LEFT", 4, 0)
    b.text:SetPoint("RIGHT", -4, 0)
    b.text:SetWordWrap(false)
    b:SetScript("OnClick", function(self) if self.row then enter(self.row) end end)
    b:SetScript("OnEnter", function(self)
        if self.row then S.Fill(self, HOVER) end
        if self.full then tip(self, self.head, { self.full }, "ANCHOR_TOP") end
    end)
    b:SetScript("OnLeave", function(self) S.Fill(self, S.CLEAR); hideTip() end)
    list[i] = b
    return b
end

-- The lines of the Modules card from ns.Overview: what waits, what the game refuses, what was
-- updated and what uses the most memory. { { head, color, names, row } }
local function overviewLines(o)
    local out = {}
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
    if #out == 0 or (#out == 1 and #o.paused > 0) then table.insert(out, 1, { L.OV_FINE, S.GOOD, "" }) end
    if #o.heavy > 0 then
        local t = {}
        for i = 1, math.min(3, #o.heavy) do t[i] = o.heavy[i].row.title .. " " .. ns.Size(o.heavy[i].kb) end
        out[#out + 1] = { L.OV_HEAVY, S.FAINT, table.concat(t, ", "), o.heavy[1].row }
    end
    return out
end

local function fillOverview(data)
    local o = ns.Overview(data)
    local hex = S.Hex(S.TEXT)
    local parts = { hex .. L.OV_ON:format(o.on, o.total) .. "|r", L.OV_RUNNING:format(o.running) }
    if o.kb > 0 then parts[#parts + 1] = L.OV_MEMORY:format(ns.Size(o.kb)) end
    home.ovHead:SetText(table.concat(parts, S.Hex(S.FAINT) .. "   ·   |r"))
    home.ovReload:SetShown(#o.reload > 0)
    local lines = overviewLines(o)
    for i, e in ipairs(lines) do
        local b = ovLines[i] or makeLine(home.overview.body, ovLines, i)
        b.head, b.full, b.row = e[1], e[3] ~= "" and e[3] or nil, e[4]
        b.text:SetText(S.Hex(e[2]) .. e[1] .. "|r" .. (e[3] ~= "" and ("  " .. e[3]) or ""))
        place(b, 24 + (i - 1) * LINE_H)
        b:Show()
    end
    for i = #lines + 1, #ovLines do ovLines[i]:Hide() end
    return home.overview:Fit(24 + #lines * LINE_H)
end

-- The slash commands of the modules that run, as many as the Quick setup card has room for.
local function fillCommands(data)
    local room = math.floor((home.quick:GetHeight() - home.cmdTop - 36 - S.INSET) / LINE_H)
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

local function fillHome(data)
    local list2 = ns.Summaries(data)
    local n = math.min(#list2, TILE_MAX)
    local w = math.floor((HOST_W - 2 * S.INSET - (TILE_COLS - 1) * 8) / TILE_COLS)
    for i = 1, n do
        local t = tiles[i] or makeTile(i)
        local s = list2[i]
        t.row = s.row
        t.icon:SetIcon(s.icon or s.row.icon)
        t.name:SetText(s.row.title)
        t.text:SetText(s.text)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", ((i - 1) % TILE_COLS) * (w + 8), -math.floor((i - 1) / TILE_COLS) * (TILE_H + 8))
        t:SetSize(w, TILE_H)
        t:Show()
    end
    for i = n + 1, #tiles do tiles[i]:Hide() end
    home.noSummary:SetShown(n == 0)
    local lines = math.max(1, math.ceil(n / TILE_COLS))
    local inner = n == 0 and 36 or (lines * (TILE_H + 8) - 8)
    local sh = 36 + inner + S.INSET
    home.summaryCard:SetHeight(sh)
    local lower = HOST_H - sh - GAP
    home.quick:SetHeight(lower)
    local oh = fillOverview(data)
    local rh = lower - oh - GAP
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
        b.text:SetText(S.Hex(S.Accent()) .. who .. "|r  " .. e.text)
        place(b, (i - 1) * LINE_H)
        b:Show()
    end
    for i = shown + 1, #feedLines do feedLines[i]:Hide() end
    home.noRecent:SetShown(#feed == 0)
    home.clear:SetShown(#feed > 0)
    home.move:SetText(ns.moving and L.MOVE_DONE or L.MOVE)
end

-- The whole window -----------------------------------------------------------------------------

local function applyScale()
    local sw = tonumber(UIParent:GetWidth()) or W
    local sh = tonumber(UIParent:GetHeight()) or H
    local user = (GulliToolkitDB and GulliToolkitDB.scale) or 1
    frame:SetScale(ns.HubScale(user, sw, sh, W, H))
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

    protectBtn:SetText(L.PROTECTED_N:format(#ns.Protected()))
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
    p.hint = S.Note(p, 11)
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
    transfer.status = S.Note(transfer, 11)
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

-- The header: the window's own (icon, title, version), plus the size buttons.
local function buildHeader()
    local plus = frame:AddHeaderButton(S.Ghost(S.Button(frame, 28, 28)))
    plus:SetText("+")
    plus:SetScript("OnClick", function() nudgeScale(0.1) end)
    scaleText = S.Text(frame.bar, 11, S.FAINT)
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
local function minimapRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(30)
    local sw = S.Switch(row)
    sw:SetPoint("RIGHT", 0, 0)
    sw:SetChecked(ns.MinimapShown())
    sw:SetScript("OnClick", function()
        ns.SetMinimap("hide", ns.MinimapShown() or nil)
    end)
    local label = S.Text(row, 12)
    label:SetPoint("LEFT", 0, 0)
    label:SetPoint("RIGHT", sw, "LEFT", -6, 0)
    label:SetWordWrap(false)
    label:SetText(L.MINIMAP)
    row.switch = sw
    mapSwitches[#mapSwitches + 1] = sw
    return row
end

local function buildSide()
    side = S.Card(frame.body)
    side:SetWidth(SIDE)
    side:SetPoint("TOPLEFT")
    side:SetPoint("BOTTOMLEFT")
    local body = side.body

    search = S.Edit(body, SIDE - 2 * S.INSET, 30)
    search:SetPoint("TOPLEFT")
    search:SetPoint("TOPRIGHT")
    search:SetJustifyH("LEFT")
    search:SetTextInsets(28, 8, 0, 0)
    local glass = search:CreateTexture(nil, "OVERLAY")
    glass:SetSize(14, 14)
    glass:SetPoint("LEFT", 8, 0)
    glass:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    glass:SetVertexColor(0.6, 0.6, 0.64, 1)
    placeholder = S.Text(search, 12, S.FAINT)
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
    local hi = homeRow:CreateTexture(nil, "ARTWORK")
    hi:SetSize(18, 18)
    hi:SetPoint("LEFT", 8, 0)
    hi:SetTexture(TOOLKIT_ICON)
    hi:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    S.RoundMask(homeRow, hi)
    local ht = S.Text(homeRow, 12)
    ht:SetPoint("LEFT", hi, "RIGHT", 8, 0)
    ht:SetText(L.HOME)
    homeRow:SetScript("OnClick", goHome)
    homeRow:SetScript("OnEnter", function(self) if not self.selected then S.Fill(self, HOVER) end end)

    empty = S.Empty(scroll)
    empty:Set(L.NO_MATCH)
end

local function buildCard()
    card = S.Card(host)
    card:SetWidth(CARD)
    card:SetPoint("TOPRIGHT")
    card:SetPoint("BOTTOMRIGHT")
    local d = card
    d.body:ClearAllPoints()
    d.body:SetAllPoints()

    local banner = CreateFrame("Frame", nil, d.body)
    banner:SetHeight(92)
    banner:SetPoint("TOPLEFT", 1, -1)
    banner:SetPoint("TOPRIGHT", -1, -1)
    S.Box(banner, S.HEAD, S.CLEAR, S.R_LG - 1, "top")
    local a = S.Accent()
    local glow = line(banner, { a[1], a[2], a[3], 0.08 })
    glow:SetDrawLayer("BACKGROUND", 1)
    glow:SetPoint("TOPLEFT")
    glow:SetPoint("BOTTOMRIGHT", banner, "RIGHT", 0, 0)
    local rule = line(banner, S.EDGE)
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    local ring = CreateFrame("Frame", nil, banner)
    ring:SetSize(62, 62)
    ring:SetPoint("CENTER")
    local halo = ring:CreateTexture(nil, "BACKGROUND", nil, -8)
    halo:SetTexture(S.GLOW_TEX)
    halo:SetSize(84, 84)
    halo:SetPoint("CENTER")
    halo:SetVertexColor(S.GLOW[1], S.GLOW[2], S.GLOW[3], 0.4)
    S.Circle(ring, 62, { S.GLOW[1], S.GLOW[2], S.GLOW[3], 0.9 }, "BACKGROUND", -7):SetPoint("CENTER")
    S.Circle(ring, 60, S.INPUT, "BACKGROUND", -6):SetPoint("CENTER")
    d.icon = ring:CreateTexture(nil, "ARTWORK")
    d.icon:SetSize(58, 58)
    d.icon:SetPoint("CENTER")
    d.icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    S.RoundMask(ring, d.icon)

    d.title = S.Text(d.body, 16)
    d.title:SetPoint("TOPLEFT", banner, "BOTTOMLEFT", S.INSET - 1, -14)
    d.title:SetPoint("RIGHT", -S.INSET, 0)
    d.title:SetWordWrap(false)
    d.cat = S.Text(d.body, 11, S.MUTED)
    d.cat:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -6)
    d.state = S.Text(d.body, 11)
    d.state:SetPoint("LEFT", d.cat, "RIGHT", 10, 0)
    d.desc = S.Text(d.body, 12)
    d.desc:SetPoint("TOPLEFT", d.cat, "BOTTOMLEFT", 0, -12)
    d.desc:SetPoint("RIGHT", -S.INSET, 0)
    d.desc:SetJustifyV("TOP")
    d.desc:SetHeight(74)
    d.desc:SetMaxLines(5)
    d.slash = S.Text(d.body, 11, S.FAINT)
    d.slash:SetPoint("TOPLEFT", d.desc, "BOTTOMLEFT", 0, -6)
    d.slash:SetPoint("RIGHT", -S.INSET, 0)
    d.facts = S.Text(d.body, 11, S.FAINT)
    d.facts:SetPoint("TOPLEFT", d.slash, "BOTTOMLEFT", 0, -6)
    d.facts:SetPoint("RIGHT", -S.INSET, 0)
    d.facts:SetWordWrap(false)

    d.pop = S.Button(d.body, CARD - 2 * S.INSET, 34)
    d.pop:SetPoint("BOTTOMLEFT", S.INSET, S.INSET)
    d.pop:SetPoint("BOTTOMRIGHT", -S.INSET, S.INSET)
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

local function buildHome()
    home = CreateFrame("Frame", nil, host)
    home:SetAllPoints(host)
    home:Show()

    local sc = S.Card(home, L.SUMMARY)
    sc:SetPoint("TOPLEFT")
    sc:SetPoint("TOPRIGHT")
    sc:SetHeight(120)
    home.summaryCard, home.summary = sc, sc.body
    home.noSummary = S.Note(sc.body, 12)
    home.noSummary:SetPoint("TOPLEFT")
    home.noSummary:SetPoint("RIGHT")
    home.noSummary:SetMaxLines(2)
    home.noSummary:SetText(L.NO_SUMMARY)

    local quick = S.Card(home, L.QUICK)
    quick:SetWidth(QUICK_W)
    quick:SetPoint("TOPRIGHT", sc, "BOTTOMRIGHT", 0, -GAP)
    home.quick = quick
    local q = quick.body
    local bw = math.floor((QUICK_W - 2 * S.INSET - 8) / 2)
    for i, p in ipairs(ns.PRESETS) do
        local b = S.Button(q, bw, 30)
        b:SetPoint("TOPLEFT", ((i - 1) % 2) * (bw + 8), -math.floor((i - 1) / 2) * 38)
        b:SetText(L["PRESET_" .. p.key])
        S.SetButtonIcon(b, p.icon)
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
    local y = math.ceil(#ns.PRESETS / 2) * 38 + 8
    home.move = S.Button(q, bw, 30)
    home.move:SetPoint("TOPLEFT", 0, -y)
    S.SetButtonIcon(home.move, QUICK_ICON.move)
    home.move:SetScript("OnClick", function()
        local n = ns.SetMoving(not ns.moving)
        ns.Print(n == 0 and L.MOVE_NONE or (ns.moving and L.MOVE_ON or L.MOVE_OFF))
    end)
    local tr = S.Button(q, bw, 30)
    tr:SetPoint("TOPLEFT", bw + 8, -y)
    tr:SetText(L.TRANSFER)
    S.SetButtonIcon(tr, QUICK_ICON.transfer)
    tr:SetScript("OnClick", function()
        if not transfer then buildTransfer() end
        showPanel("transfer")
    end)
    protectBtn = S.Button(q, QUICK_W - 2 * S.INSET, 30)
    protectBtn:SetPoint("TOPLEFT", 0, -(y + 38))
    S.SetButtonIcon(protectBtn, QUICK_ICON.protect)
    protectBtn:SetScript("OnClick", function()
        if not protectFrame then buildProtected() end
        if protectFrame:IsShown() then showHome() else showPanel("protect") end
    end)
    local map = minimapRow(q)
    map:SetPoint("TOPLEFT", 0, -(y + 84))
    map:SetPoint("TOPRIGHT", 0, -(y + 84))
    home.cmdTop = y + 84 + 40
    home.cmdTitle = S.Text(q, 13)
    home.cmdTitle:SetPoint("TOPLEFT", 0, -home.cmdTop)
    home.cmdTitle:SetText(L.COMMANDS)
    local line = S.Tex(q, "ARTWORK", 0, LINE)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 0, -(home.cmdTop - 10))
    line:SetPoint("TOPRIGHT", 0, -(home.cmdTop - 10))

    local ov = S.Card(home, L.OV_TITLE)
    ov:SetPoint("TOPLEFT", sc, "BOTTOMLEFT", 0, -GAP)
    ov:SetPoint("TOPRIGHT", quick, "TOPLEFT", -GAP, 0)
    home.overview = ov
    home.ovReload = S.Primary(S.FitButton(ov, L.RELOAD, 24, 90))
    home.ovReload:SetPoint("TOPRIGHT", -8, -6)
    home.ovReload:SetScript("OnClick", function() ReloadUI() end)
    home.ovHead = S.Text(ov.body, 13, S.MUTED)
    home.ovHead:SetPoint("TOPLEFT", 4, 0)
    home.ovHead:SetPoint("TOPRIGHT", -4, 0)
    home.ovHead:SetWordWrap(false)

    local recent = S.Card(home, L.RECENT)
    recent:SetPoint("TOPLEFT", ov, "BOTTOMLEFT", 0, -GAP)
    recent:SetPoint("TOPRIGHT", ov, "BOTTOMRIGHT", 0, -GAP)
    home.recent = recent
    home.clear = S.Ghost(S.FitButton(recent, L.CLEAR, 24, 70))
    home.clear:SetPoint("TOPRIGHT", -8, -6)
    home.clear:SetScript("OnClick", function() GulliToolkit.ClearFeed() end)
    home.noRecent = S.Note(recent.body, 12)
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

    buildHeader()
    buildSide()
    host = CreateFrame("Frame", nil, frame.body)
    host:SetPoint("TOPLEFT", side, "TOPRIGHT", GAP, 0)
    host:SetPoint("BOTTOMRIGHT")
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
        GameTooltip:SetText(L.TITLE, 1, 1, 1)
        GameTooltip:AddLine(L.MINIMAP_TIP, 0.6, 0.61, 0.66, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    mapButton = b
    ns.PlaceMinimap()
    return b
end

function ns.MinimapButton() return mapButton end

-- /gulli move: a grid over the screen and a bar at the top with Lock frames, so it is clear
-- that the frames can be dragged and how to end it.
local overlay
function ns.MoveOverlay(on)
    if not overlay then
        if not on then return end
        overlay = CreateFrame("Frame", "GulliToolkitMoveGrid", UIParent)
        overlay:SetAllPoints()
        overlay:SetFrameStrata("BACKGROUND")
        overlay:EnableMouse(false)
        local w = tonumber((UIParent:GetWidth())) or 1366
        local h = tonumber((UIParent:GetHeight())) or 768
        -- Lines every 64 pixels out from the middle, so the middle lines (accent) sit on the grid.
        local step = 64
        for i = -math.ceil(w / 2 / step), math.ceil(w / 2 / step) do
            local t = S.Tex(overlay, "ARTWORK", 0, { 1, 1, 1, 0.05 })
            t:SetPoint("TOP", overlay, "TOP", i * step, 0)
            t:SetPoint("BOTTOM", overlay, "BOTTOM", i * step, 0)
            t:SetWidth(1)
        end
        for i = -math.ceil(h / 2 / step), math.ceil(h / 2 / step) do
            local t = S.Tex(overlay, "ARTWORK", 0, { 1, 1, 1, 0.05 })
            t:SetPoint("LEFT", overlay, "LEFT", 0, i * step)
            t:SetPoint("RIGHT", overlay, "RIGHT", 0, i * step)
            t:SetHeight(1)
        end
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
        bar:SetHeight(44)
        S.HudPanel(bar)
        bar.text = S.Text(bar, 12)
        bar.text:SetPoint("LEFT", 14, 0)
        bar.text:SetText(L.MOVE_BAR)
        bar.done = S.Primary(S.FitButton(bar, L.MOVE_DONE, 30, 110))
        bar.done:SetPoint("RIGHT", -7, 0)
        bar.done:SetScript("OnClick", function()
            ns.SetMoving(false)
            ns.Print(L.MOVE_OFF)
        end)
        bar:SetWidth(math.floor((tonumber((bar.text:GetStringWidth())) or 300) + 14 + 16 + bar.done:GetWidth() + 7))
        overlay.bar = bar
    end
    overlay:SetShown(on and true or false)
    overlay.bar:SetShown(on and true or false)
end
function ns.MoveGrid() return overlay end
