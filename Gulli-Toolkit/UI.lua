-- The hub window, in three columns: a search and the categories with their counts on the left,
-- the modules of the chosen category with an on/off switch in the middle, the chosen module with
-- its switches and Open on the right. It only shows what Core.lua gives (ns.List, ns.Filter,
-- ns.Groups, ns.Counts) and calls ns.OpenModule, ns.SetEnabled and the module's own options.
-- A module that gives its window (Register's window) opens inside the hub: a narrow window
-- takes the place of the list and keeps the module card beside it, a wide one takes both.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local SIDE, DETAIL, GAP = 210, 280, S.GAP
local MID = S.NARROW_W
local W = 2 * S.PAD + SIDE + GAP + MID + GAP + DETAIL
local HOST_W = W - 2 * S.PAD - SIDE - GAP
local HOST_H = S.DOCK_H
local H = S.HEADER_H + 2 * S.PAD + HOST_H
local LIST_W = MID - 12
local ROW_H, GROUP_H, CAT_H = 52, 34, 32
local FEED_LINES, MAX_OPTIONS = 3, 6

local GOOD, WAIT, BAD = S.GOOD, S.WARN, S.BAD
local LINE, HOVER = S.LINE, S.HOVER

local view = { cat = "All", state = "all", query = "" }
local frame, side, mid, detail, search, placeholder, midTitle, scroll, list, empty
local scaleText, reloadBtn, reloadHint, protectBtn, protectFrame, recent, mapRow
local host, hubSwitch, offWin, insideWin
local cats, pills, rows, heads, recentLines, optRows = {}, {}, {}, {}, {}, {}

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
    if row.state == "ready" then return L.STATE_ON, GOOD end
    if row.state == "off" then return L.OFF, S.MUTED end
    if row.state == "reload" then return L.STATE_RELOAD, WAIT end
    if row.state == "blocked" then return L.STATE_BLOCKED:format(ns.ReasonText(row.reason)), BAD end
    return L.NOT_INSTALLED, BAD
end

local function canOpen(row)
    return row.state == "ready" and row.info and type(row.info.open) == "function"
end

local function open(row)
    if row and ns.OpenModule(row.key) then frame:Hide() end
end

-- Inside a module ------------------------------------------------------------------------------

local function canEnter(row)
    return row ~= nil and row.state ~= "missing"
end

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

-- The page for a module that is off or waits for a reload: it is not loaded, so it has no window.
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

local function leave()
    local win = insideWin
    if not win then return end
    insideWin, view.inside, view.insideCat = nil, nil, nil
    win:Undock()
    mid:Show()
    detail:Show()
    ns.Refresh()
end

-- Takes the module out of the hub into its own window.
local function popOut()
    local win = insideWin
    if not win or win == offWin then return end
    leave()
    win:Show()
end

local function enter(row)
    if not canEnter(row) then return end
    local win
    if row.state == "ready" then
        win = moduleWindow(row)
        if not win then return open(row) end
    else
        win = offWindow(row)
    end
    if insideWin and insideWin ~= win then leave() end
    if protectFrame then protectFrame:Hide() end
    local narrow = (win.size and win.size[1] or MID) <= MID
    insideWin, view.inside, view.narrow, view.selected = win, row.key, narrow, row.key
    view.insideCat = row.category
    mid:Hide()
    detail:SetShown(narrow)
    hubSwitch:SetChecked(row.on)
    win:Dock(host, {
        width = narrow and MID or HOST_W, height = HOST_H, right = { hubSwitch },
        back = leave, popOut = popOut, onHide = leave,
    })
    ns.Refresh()
end

local function select(row)
    view.selected = row and row.key
    ns.Refresh()
end

-- Left column ----------------------------------------------------------------------------------

local function makeCat(i)
    local b = CreateFrame("Button", nil, side)
    b:SetHeight(CAT_H)
    b:SetPoint("TOPLEFT", side.body, "TOPLEFT", 0, -(42 + (i - 1) * (CAT_H + 2)))
    b:SetPoint("TOPRIGHT", side.body, "TOPRIGHT", 0, -(42 + (i - 1) * (CAT_H + 2)))
    S.Box(b, { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
    b.bar = line(b, S.Accent())
    b.bar:SetPoint("TOPLEFT")
    b.bar:SetPoint("BOTTOMLEFT")
    b.bar:SetWidth(2)
    b.countBox = CreateFrame("Frame", nil, b)
    b.countBox:SetSize(40, 20)
    b.countBox:SetPoint("RIGHT", -6, 0)
    b.count = S.Text(b.countBox, 11, S.FAINT)
    b.count:SetPoint("RIGHT")
    b.count:SetJustifyH("RIGHT")
    b.text = S.Text(b, 12)
    b.text:SetPoint("LEFT", 12, 0)
    b.text:SetPoint("RIGHT", b.countBox, "LEFT", -4, 0)
    b.text:SetWordWrap(false)
    b:SetScript("OnClick", function(self)
        leave()
        view.cat = self.key
        view.selected = nil
        search:SetText("")
        search:ClearFocus()
        scroll:Top()
        ns.Refresh()
    end)
    b:SetScript("OnEnter", function(self) if view.cat ~= self.key then S.Fill(self, HOVER) end end)
    b:SetScript("OnLeave", function(self) if view.cat ~= self.key then S.Fill(self, { 0, 0, 0, 0 }) end end)
    cats[i] = b
    return b
end

local function fillCats(counts)
    local keys = { "All" }
    for _, k in ipairs(ns.CATEGORIES) do keys[#keys + 1] = k end
    if counts.Other then keys[#keys + 1] = "Other" end
    local a = S.Accent()
    local searching = view.query ~= ""
    for i, key in ipairs(keys) do
        local b = cats[i] or makeCat(i)
        b.key = key
        local c = counts[key] or { on = 0, total = 0 }
        b.text:SetText(catName(key))
        b.count:SetText(c.on .. "/" .. c.total)
        -- Inside a module its group is marked.
        local sel
        if view.inside then sel = key == view.insideCat else sel = view.cat == key and not searching end
        b.bar:SetShown(sel)
        S.Fill(b, sel and S.RAISED or S.CLEAR)
        local tc = sel and S.TEXT or ((c.total > 0) and S.MUTED or S.FAINT)
        b.text:SetTextColor(tc[1], tc[2], tc[3], 1)
        b:Show()
    end
    for i = #keys + 1, #cats do cats[i]:Hide() end
end

-- Middle column --------------------------------------------------------------------------------

local function makeRow(i)
    local r = CreateFrame("Button", nil, list)
    r:SetHeight(ROW_H)
    S.Box(r, S.CLEAR, S.CLEAR)
    r.bar = line(r, S.Accent())
    r.bar:SetPoint("TOPLEFT")
    r.bar:SetPoint("BOTTOMLEFT")
    r.bar:SetWidth(2)
    r.rule = line(r)
    r.rule:SetHeight(1)
    r.rule:SetPoint("BOTTOMLEFT")
    r.rule:SetPoint("BOTTOMRIGHT")

    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(30, 30)
    r.icon:SetPoint("LEFT", 12, 0)

    r.go = CreateFrame("Button", nil, r)
    r.go:SetSize(28, ROW_H)
    r.go:SetPoint("RIGHT", 0, 0)
    r.go.text = S.Text(r.go, 18, S.MUTED)
    r.go.text:SetPoint("CENTER")
    r.go.text:SetText(">")
    r.go:SetScript("OnClick", function(self) enter(self:GetParent().row) end)
    r.go:SetScript("OnEnter", function(self)
        local a = S.Accent()
        self.text:SetTextColor(a[1], a[2], a[3], 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L.OPEN, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    r.go:SetScript("OnLeave", function(self)
        self.text:SetTextColor(S.MUTED[1], S.MUTED[2], S.MUTED[3], 1)
        GameTooltip:Hide()
    end)

    r.switch = S.Switch(r)
    r.switch:SetPoint("RIGHT", r.go, "LEFT", -2, 0)
    r.switch:SetScript("OnClick", function(self)
        local row = self:GetParent().row
        if row then
            view.selected = row.key
            ns.SetEnabled(row, not row.on)
        end
    end)
    r.switch:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L.ON_TIP, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    r.switch:HookScript("OnLeave", function() GameTooltip:Hide() end)

    r.status = S.Text(r, 11, S.FAINT)
    r.status:SetPoint("RIGHT", -12, 0)
    r.status:SetJustifyH("RIGHT")

    r.title = S.Text(r, 13)
    r.title:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 10, 1)
    r.title:SetWordWrap(false)
    r.desc = S.Text(r, 11, S.MUTED)
    r.desc:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -5)
    r.desc:SetWordWrap(false)

    r:SetScript("OnClick", function(self) select(self.row) end)
    r:SetScript("OnDoubleClick", function(self) enter(self.row) end)
    r:SetScript("OnEnter", function(self) if not self.selected then S.Fill(self, HOVER) end end)
    r:SetScript("OnLeave", function(self) if not self.selected then S.Fill(self, S.CLEAR) end end)
    rows[i] = r
    return r
end

local function fillRow(r, row)
    r.row = row
    r.icon:SetTexture(row.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    r.icon:SetDesaturated(row.state ~= "ready")
    local slash = row.slash and ("  " .. S.Hex(S.MUTED) .. row.slash .. "|r") or ""
    r.title:SetText(row.title .. slash)
    local tc = row.state == "ready" and S.TEXT or S.MUTED
    r.title:SetTextColor(tc[1], tc[2], tc[3], 1)
    -- A module that is on but not loaded says why in its row, so a grey row with its switch on
    -- is not a riddle.
    if row.state == "reload" or row.state == "blocked" then
        local st, c = stateText(row)
        r.desc:SetText(S.Hex(c) .. st .. "|r")
    else
        r.desc:SetText(row.desc)
    end
    local missing = row.state == "missing"
    r.switch:SetShown(not missing)
    r.go:SetShown(not missing)
    r.go:SetEnabled(canEnter(row))
    r.go:SetAlpha(canOpen(row) and 1 or 0.5)
    r.status:SetShown(missing)
    r.status:SetText(missing and L.NOT_INSTALLED or "")
    local right = missing and r.status or r.switch
    r.title:SetPoint("RIGHT", right, "LEFT", -8, 0)
    r.desc:SetPoint("RIGHT", right, "LEFT", -8, 0)
    r.switch:SetChecked(row.on)
    r.selected = view.selected == row.key
    S.Fill(r, r.selected and S.RAISED or S.CLEAR)
    r.bar:SetShown(r.selected)
    r:Show()
end

local function makeHead(i)
    local h = CreateFrame("Frame", nil, list)
    h:SetHeight(GROUP_H)
    h.text = S.Text(h, 11, S.FAINT)
    h.text:SetPoint("BOTTOMLEFT", 2, 8)
    h.rule = line(h, S.EDGE)
    h.rule:SetHeight(1)
    h.rule:SetPoint("BOTTOMLEFT", 0, 0)
    h.rule:SetPoint("BOTTOMRIGHT", 0, 0)
    heads[i] = h
    return h
end

local function place(f, y)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", 0, -y)
    f:SetPoint("TOPRIGHT", 0, -y)
end

local function fillRecent()
    local feed = ns.Feed()
    local n = math.min(#feed, FEED_LINES)
    for i = 1, FEED_LINES do
        local e = feed[i]
        local who = e and tostring(e.key or "")
        if who and ns.T.en["M_" .. who] then who = L["M_" .. who] end
        recentLines[i]:SetText(e and (S.Hex(S.Accent()) .. who .. "|r  " .. e.text) or "")
    end
    return n
end

local function fillList(data)
    local shown = ns.Filter(data, view.cat, view.state, view.query)
    local searching = view.query ~= ""
    local y, ri, hi = 0, 0, 0

    local n = (view.cat == "All" and not searching and view.state == "all") and fillRecent() or 0
    recent:SetShown(n > 0)
    if n > 0 then
        local h = 34 + n * 18
        recent:SetHeight(h)
        place(recent, y)
        y = y + h + 4
    end

    local found
    for _, g in ipairs(ns.Groups(shown)) do
        if view.cat == "All" or searching then
            hi = hi + 1
            local h = heads[hi] or makeHead(hi)
            h.text:SetText(catName(g.key))
            place(h, y)
            h:Show()
            y = y + GROUP_H
        end
        for _, row in ipairs(g.rows) do
            ri = ri + 1
            local r = rows[ri] or makeRow(ri)
            fillRow(r, row)
            place(r, y)
            y = y + ROW_H
            if row.key == view.selected then found = row end
        end
    end
    for i = ri + 1, #rows do rows[i]:Hide() end
    for i = hi + 1, #heads do heads[i]:Hide() end
    empty:SetShown(ri == 0)
    list:SetHeight(math.max(1, y))
    scroll:Update(y)
    return found or shown[1]
end

-- Right column ---------------------------------------------------------------------------------

local function makeOption(i)
    local o = CreateFrame("Frame", nil, detail)
    o:SetHeight(36)
    o:SetPoint("TOPLEFT", detail.setHead, "BOTTOMLEFT", 0, -6 - (i - 1) * 36)
    o:SetPoint("RIGHT", detail, "RIGHT", -S.INSET, 0)
    o.rule = line(o)
    o.rule:SetHeight(1)
    o.rule:SetPoint("BOTTOMLEFT")
    o.rule:SetPoint("BOTTOMRIGHT")
    o.switch = S.Switch(o)
    o.switch:SetPoint("RIGHT")
    o.switch:SetScript("OnClick", function(self)
        local opt = self:GetParent().opt
        if opt then
            local ok, cur = pcall(opt.get)
            pcall(opt.set, not (ok and cur))
            ns.Refresh()
        end
    end)
    o.icon = S.IconBox(o, 24)
    o.icon:SetPoint("LEFT")
    o.label = S.Text(o, 12)
    o.label:SetPoint("LEFT", 34, 0)
    o.label:SetPoint("RIGHT", o.switch, "LEFT", -6, 0)
    o.label:SetMaxLines(2)
    optRows[i] = o
    return o
end

local function fillDetail(row)
    detail.body:SetShown(row ~= nil)
    if not row then return end
    detail.row = row
    detail.icon:SetTexture(row.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    detail.icon:SetDesaturated(row.state ~= "ready")
    detail.title:SetText(row.title)
    detail.cat:SetText(catName(row.category))
    local st, color = stateText(row)
    detail.state:SetText(st)
    detail.state:SetTextColor(color[1], color[2], color[3], 1)
    detail.desc:SetText(row.desc)
    detail.slash:SetText(row.slash and L.COMMAND:format(row.slash) or "")

    -- Inside a module its own window shows the settings; the card only describes it.
    local inside = view.inside == row.key
    detail.setHead:SetShown(not inside)
    detail.srule:SetShown(not inside)
    local opts = (row.state == "ready" and not inside) and row.options or {}
    local count = math.min(#opts, MAX_OPTIONS)
    for i = 1, count do
        local o = optRows[i] or makeOption(i)
        o.opt = opts[i]
        o.label:SetText(opts[i].label)
        local icon = type(opts[i].icon) == "string" and opts[i].icon or nil
        o.icon:SetShown(icon ~= nil)
        if icon then o.icon:SetIcon(icon) end
        o.label:SetPoint("LEFT", icon and 34 or 0, 0)
        local ok, on = pcall(opts[i].get)
        o.switch:SetChecked(ok and on)
        o:Show()
    end
    for i = count + 1, #optRows do optRows[i]:Hide() end
    if row.state == "missing" then
        detail.none:SetText(L.MISSING_HINT)
    elseif row.state == "off" then
        detail.none:SetText(L.OFF_HINT)
    elseif row.state == "blocked" then
        detail.none:SetText(row.reason == "INTERFACE_VERSION" and L.INSIDE_OUTDATED
            or L.INSIDE_BLOCKED:format(ns.ReasonText(row.reason)))
    elseif row.state ~= "ready" then
        detail.none:SetText(L.RELOAD_HINT)
    else
        detail.none:SetText(L.NO_SETTINGS)
    end
    detail.none:SetShown(count == 0 and not inside)

    -- Inside, the module's own main button stays the only filled one.
    detail.open:SetShown(not inside)
    detail.pop:SetShown(inside)
    detail.pop:SetEnabled(insideWin ~= offWin)
    detail.open:SetText(row.state == "missing" and L.NOT_INSTALLED or L.OPEN_MODULE:format(row.title))
    detail.open:SetEnabled(canEnter(row))
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
    fillCats(ns.Counts(data))
    midTitle:SetText(view.query ~= "" and L.RESULTS or catName(view.cat))
    for key, p in pairs(pills) do p:SetSelected(view.state == key) end
    local row = fillList(data)
    if view.inside then
        for _, r in ipairs(data) do if r.key == view.inside then row = r end end
        hubSwitch:SetChecked(row and row.on)
        if row and insideWin == offWin then offWindow(row) end
    end
    view.selected = row and row.key
    -- fillList drew the rows before the selection was known when it fell back to the first one.
    for _, r in ipairs(rows) do
        if r:IsShown() and r.row then fillRow(r, r.row) end
    end
    fillDetail(row)

    local reload = ns.NeedsReload()
    reloadBtn:SetShown(reload)
    reloadHint:SetShown(reload)
    protectBtn:SetText(L.PROTECTED_N:format(#ns.Protected()))
    if protectFrame and protectFrame:IsShown() then ns.RefreshProtected() end
end

-- Protected items: shown over the right column, with a drop zone for items from the bags.
local protRows = {}
function ns.RefreshProtected()
    local ids = ns.Protected()
    for i, id in ipairs(ids) do
        local r = protRows[i]
        if not r then
            r = CreateFrame("Frame", nil, protectFrame.list)
            r:SetHeight(30)
            r:SetPoint("TOPLEFT", 0, -(i - 1) * 32)
            r:SetPoint("TOPRIGHT", 0, -(i - 1) * 32)
            S.Box(r, S.ROW, { 0, 0, 0, 0 })
            r.icon = r:CreateTexture(nil, "ARTWORK")
            r.icon:SetSize(22, 22)
            r.icon:SetPoint("LEFT", 4, 0)
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
        local name, _, _, _, _, _, _, _, _, icon = (C_Item and C_Item.GetItemInfo or GetItemInfo)(id)
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

local function buildProtected()
    protectFrame = CreateFrame("Frame", "GulliToolkitProtected", detail)
    protectFrame:SetAllPoints(detail)
    protectFrame:EnableMouse(true)
    S.Box(protectFrame, S.SURFACE, S.EDGE)
    local title = S.Text(protectFrame, 14)
    title:SetPoint("TOPLEFT", S.INSET, -14)
    title:SetText(L.PROTECTED)
    local close = S.Close(protectFrame, function() protectFrame:Hide() end)
    close:SetPoint("TOPRIGHT", -6, -6)
    local hint = S.Note(protectFrame, 11)
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    hint:SetPoint("RIGHT", -S.INSET, 0)
    hint:SetMaxLines(5)
    hint:SetText(L.PROTECT_HINT)
    local drop = CreateFrame("Button", nil, protectFrame)
    drop:SetHeight(44)
    drop:SetPoint("TOPLEFT", S.INSET, -122)
    drop:SetPoint("TOPRIGHT", -S.INSET, -122)
    S.Box(drop, S.INPUT, S.EDGE)
    local dropText = S.Text(drop, 12, S.MUTED)
    dropText:SetPoint("CENTER")
    dropText:SetText(L.DROP)
    drop:SetScript("OnReceiveDrag", dropItem)
    drop:SetScript("OnClick", dropItem)
    drop:SetScript("OnEnter", function(self) S.SetBorder(self, S.Accent()) end)
    drop:SetScript("OnLeave", function(self) S.SetBorder(self, S.EDGE) end)
    protectFrame.scroll = S.Scroll(protectFrame)
    protectFrame.scroll:SetPoint("TOPLEFT", drop, "BOTTOMLEFT", 0, -S.GAP)
    protectFrame.scroll:SetPoint("BOTTOMRIGHT", -22, S.INSET)
    protectFrame.list = protectFrame.scroll.child
    protectFrame.list:SetWidth(DETAIL - 2 * S.INSET - 10)
    protectFrame:SetScript("OnShow", ns.RefreshProtected)
    protectFrame:Hide()
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

-- A switch row for the minimap button: in the hub's side card and on the Options page.
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
        if view.query ~= "" then leave() end
        hint(self)
        scroll:Top()
        ns.Refresh()
    end)
    search:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    protectBtn = S.Button(body, SIDE - 2 * S.INSET, 30)
    protectBtn:SetPoint("BOTTOMLEFT")
    protectBtn:SetPoint("BOTTOMRIGHT")
    protectBtn:SetScript("OnClick", function()
        leave()
        if not protectFrame then buildProtected() end
        protectFrame:SetShown(not protectFrame:IsShown())
    end)
    mapRow = minimapRow(body)
    mapRow:SetPoint("BOTTOMLEFT", protectBtn, "TOPLEFT", 0, 8)
    mapRow:SetPoint("BOTTOMRIGHT", protectBtn, "TOPRIGHT", 0, 8)
    reloadBtn = S.Primary(S.Button(body, SIDE - 2 * S.INSET, 30))
    reloadBtn:SetPoint("BOTTOMLEFT", mapRow, "TOPLEFT", 0, 8)
    reloadBtn:SetPoint("BOTTOMRIGHT", mapRow, "TOPRIGHT", 0, 8)
    reloadBtn:SetText(L.RELOAD)
    reloadBtn:SetScript("OnClick", function() ReloadUI() end)
    reloadHint = S.Note(body, 11)
    reloadHint:SetTextColor(WAIT[1], WAIT[2], WAIT[3], 1)
    reloadHint:SetPoint("BOTTOMLEFT", reloadBtn, "TOPLEFT", 0, 8)
    reloadHint:SetPoint("BOTTOMRIGHT", reloadBtn, "TOPRIGHT", 0, 8)
    reloadHint:SetMaxLines(3)
    reloadHint:SetText(L.RELOAD_HINT)
end

local function buildMiddle()
    mid = CreateFrame("Frame", nil, frame.body)
    mid:SetWidth(MID)
    mid:SetPoint("TOPLEFT", side, "TOPRIGHT", GAP, 0)
    mid:SetPoint("BOTTOMLEFT", side, "BOTTOMRIGHT", GAP, 0)

    local order = { { "all", L.ALL }, { "on", L.STATE_ON }, { "off", L.OFF } }
    local labels = {}
    for i, o in ipairs(order) do labels[i] = o[2] end
    local seg = S.Tabs(mid, labels, nil, function(i)
        view.state = order[i][1]
        scroll:Top()
        ns.Refresh()
    end, 28)
    seg.frame:ClearAllPoints()
    seg.frame:SetPoint("TOPRIGHT", 0, 0)
    for i, o in ipairs(order) do
        local b = seg.buttons[i]
        b.SetSelected = function(_, on) if on and seg.selected ~= i then seg:Select(i, true) end end
        pills[o[1]] = b
    end
    midTitle = S.Text(mid, 16)
    midTitle:SetPoint("LEFT", mid, "TOPLEFT", 2, -14)
    midTitle:SetPoint("RIGHT", seg.frame, "LEFT", -8, 0)
    midTitle:SetWordWrap(false)

    scroll = S.Scroll(mid)
    scroll:SetPoint("TOPLEFT", 0, -40)
    scroll:SetPoint("BOTTOMRIGHT", -12, 0)
    list = scroll.child
    list:SetWidth(LIST_W)

    recent = CreateFrame("Frame", nil, list)
    S.Box(recent, S.SURFACE, S.EDGE)
    local accentBar = line(recent, S.Accent())
    accentBar:SetPoint("TOPLEFT")
    accentBar:SetPoint("BOTTOMLEFT")
    accentBar:SetWidth(2)
    local rt = S.Text(recent, 12)
    rt:SetPoint("TOPLEFT", S.INSET, -10)
    rt:SetText(L.RECENT)
    for i = 1, FEED_LINES do
        local t = S.Text(recent, 11, S.MUTED)
        t:SetPoint("TOPLEFT", S.INSET, -12 - i * 18)
        t:SetPoint("RIGHT", -S.INSET, 0)
        t:SetWordWrap(false)
        recentLines[i] = t
    end

    empty = S.Empty(scroll)
    empty:Set(L.NO_MATCH)
end

local function buildDetail()
    detail = S.Card(frame.body)
    detail:SetWidth(DETAIL)
    detail:SetPoint("TOPRIGHT")
    detail:SetPoint("BOTTOMRIGHT")
    local d = detail
    d.body:ClearAllPoints()
    d.body:SetAllPoints()

    local banner = CreateFrame("Frame", nil, d.body)
    banner:SetHeight(92)
    banner:SetPoint("TOPLEFT", 1, -1)
    banner:SetPoint("TOPRIGHT", -1, -1)
    S.Box(banner, S.HEAD, S.CLEAR)
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
    S.Box(ring, S.INPUT, a)
    d.icon = ring:CreateTexture(nil, "ARTWORK")
    d.icon:SetSize(52, 52)
    d.icon:SetPoint("CENTER")

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
    d.desc:SetHeight(58)
    d.desc:SetMaxLines(4)
    d.slash = S.Text(d.body, 11, S.FAINT)
    d.slash:SetPoint("TOPLEFT", d.desc, "BOTTOMLEFT", 0, -6)

    d.setHead = S.Text(d.body, 11, S.FAINT)
    d.setHead:SetPoint("TOPLEFT", d.slash, "BOTTOMLEFT", 0, -16)
    d.setHead:SetText(L.SETTINGS)
    local srule = line(d.body, S.EDGE)
    srule:SetHeight(1)
    srule:SetPoint("LEFT", d.setHead, "RIGHT", 8, 0)
    srule:SetPoint("RIGHT", -S.INSET, 0)
    d.srule = srule
    d.none = S.Note(d.body, 11)
    d.none:SetPoint("TOPLEFT", d.setHead, "BOTTOMLEFT", 0, -10)
    d.none:SetPoint("RIGHT", -S.INSET, 0)
    d.none:SetMaxLines(3)

    d.open = S.Primary(S.Button(d.body, DETAIL - 2 * S.INSET, 34))
    d.open:SetPoint("BOTTOMLEFT", S.INSET, S.INSET)
    d.open:SetPoint("BOTTOMRIGHT", -S.INSET, S.INSET)
    d.open:SetScript("OnClick", function() enter(detail.row) end)
    d.pop = S.Button(d.body, DETAIL - 2 * S.INSET, 34)
    d.pop:SetPoint("BOTTOMLEFT", S.INSET, S.INSET)
    d.pop:SetPoint("BOTTOMRIGHT", -S.INSET, S.INSET)
    d.pop:SetText(L.POP_OUT)
    d.pop:SetScript("OnClick", function() popOut() end)
    d.pop:Hide()
end

local function build()
    frame = S.Window("GulliToolkitFrame", L.TITLE, W, H, { sub = ns.Version(), fullTitle = true })

    buildHeader()
    buildSide()
    buildMiddle()
    buildDetail()

    host = CreateFrame("Frame", nil, frame.body)
    host:SetPoint("TOPLEFT", side, "TOPRIGHT", GAP, 0)
    host:SetPoint("BOTTOMRIGHT")
    hubSwitch = S.Switch(frame)
    hubSwitch:Hide()
    hubSwitch:SetScript("OnClick", function()
        for _, r in ipairs(ns.List()) do
            if r.key == view.inside then ns.SetEnabled(r, not r.on) end
        end
    end)
    hubSwitch:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L.ON_TIP, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    hubSwitch:HookScript("OnLeave", function() GameTooltip:Hide() end)

    frame:SetScript("OnShow", function()
        applyScale()
        ns.Refresh()
    end)
    frame:SetScript("OnHide", function() leave() end)
end

function ns.Toggle()
    if not frame then build() end
    frame:SetShown(not frame:IsShown())
    if frame:IsShown() then
        applyScale()
        ns.Refresh()
    end
end

-- The view the hub shows now, for the tests.
function ns.View()
    return view, frame
end

-- Opens a module inside the hub (row key), or goes back to the list (nil). For the tests.
function ns.Enter(key)
    if not key then return leave() end
    for _, r in ipairs(ns.List()) do
        if r.key == key then return enter(r) end
    end
end
function ns.Inside() return insideWin end

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
    if icon.SetMask then icon:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask") end
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
