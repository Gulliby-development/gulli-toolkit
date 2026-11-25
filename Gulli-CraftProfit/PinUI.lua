-- The pinned route in the window: the pin button beside Recalculate, the strip under the header,
-- the three tiles in place of the route tiles, the comparison with a new calculation, the list
-- of routes behind the header chip, and the simulation's Save button. It only shows what
-- Pin.lua holds; UI.lua calls in here (ns.PinBuild, ns.PinPage, ns.PinChrome, ns.PinRoute).

local _, ns = ...
local L = ns.L
local S = ns.Skin

local STRIP_H = 34
local OFF = STRIP_H - S.PAD + S.GAP
local MAIN = S.WIDE_W - 2 * S.PAD
local TILE_H = 58
local HEAD_H = 34
local LOCK = "Interface\\Buttons\\LockButton-Locked-Up"
local ROW_H, GROUP_H = 54, 28

local ui, frame
local w = {}
ns.pinUI = w
local page -- nil, "compare" or "list"

local function hex(c) return S.Hex(c) end
local function strw(t) return tonumber((t:GetStringWidth())) or 0 end
local function money(c) return S.MoneyText(math.floor(math.abs(c or 0) + 0.5)) end
local function accentFill(a) return { S.FILL[1], S.FILL[2], S.FILL[3], a } end
local function tip(owner, title, text)
    if not (GameTooltip and GameTooltip.SetOwner) then return end
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
    GameTooltip:SetText(title, 1, 1, 1)
    if text then GameTooltip:AddLine(text, 0.8, 0.8, 0.8, true) end
    GameTooltip:Show()
end
local function untip() if GameTooltip then GameTooltip:Hide() end end
local function fit(b, min) b:SetWidth(math.max(min or 72, math.floor(strw(b.text) + 28))) end

local function stamp(at)
    local fmt = date or (os and os.date)
    if not fmt or not at or at <= 0 then return "" end
    return fmt("%d.%m, %H:%M", at)
end

function ns.PinPageShown() return page end
function ns.PinShowPage(p)
    page = p
    if ns.Refresh then ns.Refresh() end
end

-- ---------- pinning from the window ----------

-- The notice when a route pinned itself, with the way back.
function ns.PinToast(pin)
    if not S.Toast then return end
    S.Toast({ key = "pin", icon = ns.PIN_ICON, title = L.PIN_TOAST, text = L.PIN_TOAST_TEXT, seconds = 12,
              buttons = { { text = L.PIN_UNDO, onClick = function() ns.PinUndo(pin) end } } })
end

-- The pin button: pins the route shown, or takes the pin away.
function ns.PinClick()
    local v = ns.view
    -- in the simulation the same button saves the route, or takes the saved one away
    if ns.sim then
        if ns.sim.pin and not ns.sim.pin.gone then ns.Unpin(ns.sim.pin); ns.Refresh() else ns.PinSaveSim() end
        return
    end
    local pin = ns.PinHere()
    if pin then
        ns.Unpin(pin)
        ns.Toast(L.PIN_GONE)
        return
    end
    local made, why = ns.PinNow(false)
    if made then ns.Toast(L.PIN_TOAST .. ". " .. L.PIN_TOAST_TEXT)
    elseif why == "full" then ns.Toast(hex(S.WARN) .. L.PIN_FULL:format(ns.PIN_MAX) .. "|r")
    else ns.Toast(L.PIN_NONE) end
    if v.pin and ns.Refresh then ns.Refresh() end
end

-- The pin button in the simulation: the route stays in the list after the simulation.
function ns.PinSaveSim()
    if not ns.sim or ns.sim.pin then return end
    local made, why = ns.PinNow(false)
    if not made then ns.Toast(why == "full" and (hex(S.WARN) .. L.PIN_FULL:format(ns.PIN_MAX) .. "|r") or L.PIN_NONE) return end
    ns.Toast(L.SIM_SAVED_NOTE)
end

-- ---------- header chip, pin button, strip ----------

local function buildChrome()
    -- the header chip: how many routes are kept, and the way to their list
    local chip = S.Pill(frame.bar, 90, 26)
    chip.icon = S.IconBox(chip, 18, ns.PIN_ICON)
    chip.icon:SetPoint("LEFT", 4, 0)
    chip.text:ClearAllPoints()
    chip.text:SetPoint("LEFT", chip.icon, "RIGHT", 6, 0)
    chip:SetScript("OnClick", function() ns.PinShowPage(page ~= "list" and "list" or nil) end)
    chip:HookScript("OnEnter", function(self) tip(self, L.PINS_TITLE, L.PINS_TIP) end)
    chip:HookScript("OnLeave", untip)
    frame:AddHeaderButton(chip)
    ui.age:SetPoint("RIGHT", chip, "LEFT", -8, 0)
    w.chip = chip

    local b = ns.RoundButton(ui.main, LOCK)
    b.pic:SetSize(20, 20)
    b:SetPoint("RIGHT", ui.calc, "LEFT", -6, 0)
    b:SetScript("OnClick", ns.PinClick)
    w.button = b
    ui.pinBtn = b

    local s = CreateFrame("Frame", nil, frame.body)
    s:SetPoint("TOPLEFT", -S.PAD + 1, S.PAD - 1)
    s:SetPoint("TOPRIGHT", S.PAD - 1, S.PAD - 1)
    s:SetHeight(STRIP_H)
    S.Box(s, accentFill(0.2), S.CLEAR)
    s.line = S.Tex(s, "ARTWORK", 0, accentFill(0.8))
    s.line:SetPoint("BOTTOMLEFT")
    s.line:SetPoint("BOTTOMRIGHT")
    s.line:SetHeight(1)
    s.icon = S.IconBox(s, 22, ns.PIN_ICON)
    s.icon:SetPoint("LEFT", S.PAD - 1, 0)
    s.head = S.Text(s, 12, nil, nil, "bold")
    s.head:SetPoint("LEFT", s.icon, "RIGHT", 8, 0)
    s.head:SetWordWrap(false)
    s.head:SetText(S.Upper(L.PIN_STRIP))
    s.off = S.FitButton(s, L.PIN_UNPIN, 26, 80)
    s.off:SetPoint("RIGHT", -(S.PAD - 1), 0)
    s.off:SetScript("OnClick", ns.PinClick)
    s.better = S.FitButton(s, L.PIN_BETTER, 26, 80)
    s.better:SetPoint("RIGHT", s.off, "LEFT", -8, 0)
    s.better:SetScript("OnClick", function() ns.CompareStart() end)
    s.text = S.Text(s, 12, S.Accent())
    s.text:SetPoint("LEFT", s.head, "RIGHT", 14, 0)
    s.text:SetPoint("RIGHT", s.better, "LEFT", -10, 0)
    s.text:SetJustifyH("LEFT")
    s.text:SetWordWrap(false)
    s:Hide()
    w.strip = s
end

-- After the simulation's own refresh: the chip, the button, the strip.
function ns.PinChrome()
    if not w.chip then return end
    local v = ns.view
    local n = #ns.Pins()
    -- inside the hub the header is narrower: the number alone, the name in the tooltip
    w.chip:SetText(frame.docked and tostring(n) or L.PINS_CHIP:format(n))
    w.chip:SetWidth(math.floor(strw(w.chip.text)) + 4 + 18 + 6 + 12)
    S.SetBorder(w.chip, page == "list" and S.Accent() or S.EDGE)
    local sim = ns.sim
    local pin = not sim and ns.PinHere() or nil
    -- the same button in the simulation: it saves the route calculated there
    local saved = sim and sim.pin and not sim.pin.gone
    w.button:SetShown(not sim or (sim.prof ~= nil and v.plan ~= nil and v.legs ~= nil))
    if sim then
        w.button:SetText(saved and L.SIM_SAVED or L.SIM_SAVE)
        w.button.tip = L.SIM_SAVE_TIP
    else
        w.button:SetText(pin and L.PIN_OFF or L.PIN)
        w.button.tip = pin and L.PIN_OFF_TIP or L.PIN_TIP
    end
    local on = pin ~= nil or saved
    w.button.edge = on and S.Accent() or nil
    S.SetBorder(w.button, on and S.Accent() or S.EDGE)
    S.Fill(w.button, on and accentFill(0.34) or S.RAISED)
    w.strip:SetShown(pin ~= nil)
    if pin then
        ui.main:SetPoint("TOPLEFT", 0, -OFF)
        local at = stamp(pin.at)
        w.strip.text:SetText(at ~= "" and L.PIN_STRIP_TEXT:format(at) or L.PIN_TOAST_TEXT)
        w.strip.better:SetEnabled(v.pin == pin and v.plan ~= nil)
    end
end

-- ---------- the tiles of a pinned route ----------

local function tile(parent, label, icon)
    local t = CreateFrame("Frame", nil, parent)
    S.Box(t, S.SURFACE, S.CARD_EDGE, S.R_LG)
    t.icon = S.IconBox(t, 16, icon)
    t.icon:SetPoint("TOPLEFT", 10, -6)
    t.label = S.Text(t, 12, S.GOLD_DIM, nil, "bold")
    t.label:SetPoint("LEFT", t.icon, "RIGHT", 6, 0)
    t.label:SetPoint("RIGHT", -10, 0)
    t.label:SetWordWrap(false)
    t.label:SetText(S.Upper(label))
    t.value = S.Text(t, 14, nil, nil, "bold")
    t.value:SetPoint("TOPLEFT", 10, -23)
    t.value:SetPoint("RIGHT", -10, 0)
    t.value:SetWordWrap(false)
    t.sub = S.Text(t, 12, S.MUTED)
    t.sub:SetPoint("BOTTOMLEFT", 10, 5)
    t.sub:SetPoint("RIGHT", -10, 0)
    t.sub:SetWordWrap(false)
    return t
end

local function buildTiles()
    local box = CreateFrame("Frame", nil, ui.route)
    box:SetPoint("TOPLEFT", 0, 0)
    box:SetPoint("TOPRIGHT", 0, 0)
    box:SetHeight(TILE_H)
    local tw = math.floor((MAIN - 16) / 3)
    box.route = tile(box, L.PIN_T_ROUTE, ns.PIN_ICON)
    box.spent = tile(box, L.PIN_T_SPENT, "Interface\\Icons\\INV_Misc_Bag_08")
    box.left = tile(box, L.PIN_T_LEFT, "Interface\\Minimap\\Tracking\\Auctioneer")
    for i, t in ipairs({ box.route, box.spent, box.left }) do
        t:SetSize(tw, TILE_H)
        t:SetPoint("TOPLEFT", (i - 1) * (tw + 8), 0)
    end
    box:Hide()
    w.tiles = box
end

-- The Route tab of a pinned route: its three tiles stand where the routes to choose from were.
function ns.PinRoute(v)
    if not w.tiles then return end
    local pin = not v.state.sim and v.pin or nil
    w.tiles:SetShown(pin ~= nil)
    ui.target:SetAlpha(pin and 0.4 or 1)
    if not pin then return end
    for _, b in ipairs(ui.varTiles) do b:Hide() end
    ui.varPrev:Hide(); ui.varNext:Hide()
    local st = ns.PinStatus(v)
    local t = w.tiles
    t.route.value:SetText(hex(S.GOLD) .. ns.RouteName(pin.mode or "l1", 4) .. "|r")
    t.route.sub:SetText(S.Emph(L.PIN_T_RANGE:format(st.from, st.to, st.skill)))
    t.spent.value:SetText(money(st.spent))
    t.spent.sub:SetText(S.Emph(L.PIN_T_LINES:format(st.haveN, st.ofN)))
    if st.left <= 0 then
        t.left.value:SetText(hex(S.GOOD) .. L.PIN_T_ALL .. "|r")
        t.left.sub:SetText("")
    else
        t.left.value:SetText(money(st.left))
        local moved = math.abs(st.left - st.planLeft) > math.max(100, 0.01 * st.planLeft)
        t.left.sub:SetText(moved and L.PIN_T_PLAN:format(money(st.planLeft)) or L.PIN_T_SAME)
    end
end

-- ---------- is there a better route ----------

local function topRow(parent, title, back)
    local head = CreateFrame("Frame", nil, parent)
    head:SetPoint("TOPLEFT", 0, 0)
    head:SetPoint("TOPRIGHT", 0, 0)
    head:SetHeight(HEAD_H)
    head.back = S.Return(S.FitButton(head, back, 28, 96))
    head.back:SetPoint("LEFT", 0, 0)
    head.back:SetScript("OnClick", function() ns.PinShowPage(nil) end)
    head.title = S.Text(head, 16, S.GOLD, nil, "title")
    head.title:SetPoint("LEFT", head.back, "RIGHT", 14, 0)
    head.title:SetWordWrap(false)
    head.title:SetText(title)
    head.right = S.Text(head, 12, S.MUTED)
    head.right:SetPoint("RIGHT", 0, 0)
    head.right:SetJustifyH("RIGHT")
    head.title:SetPoint("RIGHT", head.right, "LEFT", -10, 0)
    return head
end

local CMP_ROWS = { "CMP_SPEND", "CMP_INCOME", "CMP_COST", "CMP_CRAFTS", "CMP_REACH" }
local CARD_H = 36 + #CMP_ROWS * 24 + S.INSET

local function sideCard(parent, title, icon)
    local c = S.Card(parent, title, nil, icon)
    c.rows = {}
    for i, key in ipairs(CMP_ROWS) do
        local r = {}
        r.label = S.Text(c.body, 12, S.MUTED)
        r.label:SetPoint("TOPLEFT", 0, -(i - 1) * 24 - 4)
        r.label:SetText(L[key])
        r.value = S.Text(c.body, key == "CMP_COST" and 14 or 13, nil, nil, key == "CMP_COST" and "bold" or nil)
        r.value:SetPoint("TOPRIGHT", 0, -(i - 1) * 24 - 4)
        r.value:SetJustifyH("RIGHT")
        r.label:SetPoint("RIGHT", r.value, "LEFT", -8, 0)
        r.label:SetWordWrap(false)
        c.rows[i] = r
    end
    function c:Set(x)
        local cost = x.cost
        local vals = { money(x.spend), money(x.income),
                       hex(cost > 0 and S.BAD or S.GOOD) .. (cost > 0 and "-" or "+") .. "|r" .. money(cost),
                       tostring(x.crafts), tostring(x.reached or "?") }
        for i, r in ipairs(self.rows) do r.value:SetText(vals[i]) end
    end
    return c
end

local CHANGE_ICON = {
    recipe = "Interface\\Icons\\INV_Scroll_03", drop = "Interface\\Icons\\INV_Misc_Coin_02",
    add = "Interface\\Minimap\\Tracking\\Auctioneer", unused = "Interface\\Icons\\INV_Misc_Bag_08",
    crafts = "Interface\\Icons\\Trade_BlackSmithing",
}

-- One line of "What changes", in words.
function ns.PinChangeText(r)
    if r.kind == "recipe" then
        if r.nameA and r.nameB then return L.CMP_ROW_RECIPE:format(r.from, r.to, r.nameB, r.nameA) end
        return L.CMP_ROW_STRETCH:format(r.from, r.to, r.nameB or r.nameA or "?")
    elseif r.kind == "drop" then return L.CMP_ROW_DROP:format(r.name, r.n)
    elseif r.kind == "add" then return L.CMP_ROW_ADD:format(r.name, r.n)
    elseif r.kind == "unused" then return L.CMP_ROW_UNUSED:format(r.name, r.n)
    elseif r.kind == "crafts" then return L.CMP_ROW_CRAFTS:format(r.b, r.a) end
    return ""
end

-- The verdict in words: { text, color, canSwitch }.
function ns.PinVerdict(c)
    if c.verdict == "better" then return L.CMP_BETTER:format(money(c.diff)), S.GOOD, true end
    if c.verdict == "worse" then return L.CMP_WORSE:format(money(-c.diff)), S.WARN, true end
    return L.CMP_SAME, S.TEXT, #c.rows > 0
end

local function buildCompare()
    local p = CreateFrame("Frame", nil, frame.body)
    p:SetAllPoints()
    p.head = topRow(p, L.PIN_BETTER, L.CMP_BACK)
    p.note = S.Text(p, 12, S.MUTED)
    p.note:SetPoint("TOPLEFT", 0, -(HEAD_H + 4))
    p.note:SetPoint("TOPRIGHT", 0, -(HEAD_H + 4))
    p.note:SetJustifyH("LEFT")
    p.note:SetHeight(30)
    p.note:SetJustifyV("TOP")
    p.note:SetText(L.CMP_NOTE)
    local top = HEAD_H + 4 + 30 + S.GAP
    local cw = math.floor((MAIN - S.GAP) / 2)
    p.mine = sideCard(p, L.CMP_MINE, ns.PIN_ICON)
    p.mine:SetPoint("TOPLEFT", 0, -top)
    p.mine:SetSize(cw, CARD_H)
    p.fresh = sideCard(p, L.CMP_NEW, "Interface\\Buttons\\UI-RefreshButton")
    p.fresh:SetPoint("TOPRIGHT", 0, -top)
    p.fresh:SetSize(cw, CARD_H)
    -- the footer: the verdict in words, the two ways on
    local foot = CreateFrame("Frame", nil, p)
    foot:SetPoint("BOTTOMLEFT", 0, 0)
    foot:SetPoint("BOTTOMRIGHT", 0, 0)
    foot:SetHeight(36)
    p.go = S.Primary(S.FitButton(foot, L.CMP_SWITCH, 32, 120))
    p.go:SetPoint("RIGHT", 0, 0)
    p.go:SetScript("OnClick", function()
        if ns.PinSwitch() then page = nil; ns.Toast(L.CMP_SWITCHED) end
        ns.Refresh()
    end)
    p.keep = S.FitButton(foot, L.CMP_KEEP, 32, 120)
    p.keep:SetPoint("RIGHT", p.go, "LEFT", -8, 0)
    p.keep:SetScript("OnClick", function() ns.PinShowPage(nil) end)
    p.dot = S.Tex(foot, "ARTWORK", 0, S.GOOD)
    p.dot:SetSize(8, 8)
    p.dot:SetPoint("LEFT", 2, 0)
    p.verdict = S.Text(foot, 13, nil, nil, "bold")
    p.verdict:SetPoint("LEFT", p.dot, "RIGHT", 8, 0)
    p.verdict:SetPoint("RIGHT", p.keep, "LEFT", -10, 0)
    p.verdict:SetJustifyH("LEFT")
    p.verdict:SetMaxLines(2)
    p.foot = foot
    -- what changes, between the cards and the footer
    p.changes = S.Card(p, L.CMP_CHANGES)
    p.changes:SetPoint("TOPLEFT", 0, -(top + CARD_H + S.GAP))
    p.changes:SetPoint("BOTTOMRIGHT", foot, "TOPRIGHT", 0, S.GAP)
    p.list = S.List(p.changes.body, 28, function(r)
        r.icon = S.IconBox(r, 20)
        r.icon:SetPoint("LEFT", 2, 0)
        r.text = S.Text(r, 12)
        r.text:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
        r.text:SetPoint("RIGHT", -6, 0)
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(false)
    end, function(r, e)
        r.icon:SetIcon(CHANGE_ICON[e.kind] or ns.PIN_ICON)
        r.text:SetText(S.Emph(ns.PinChangeText(e)))
    end)
    p.list:SetPoint("TOPLEFT", 0, 0)
    p.list:SetPoint("BOTTOMRIGHT", -10, 0)
    p.none = S.Text(p.changes.body, 12, S.MUTED)
    p.none:SetPoint("TOPLEFT", 0, -4)
    p.none:SetPoint("RIGHT", 0, 0)
    p.none:SetJustifyH("LEFT")
    p.none:SetText(L.CMP_NONE)
    -- while the new calculation runs
    p.busy = S.Text(p, 13, S.MUTED)
    p.busy:SetPoint("TOP", 0, -(top + 60))
    p.bar = S.Progress(p, 8)
    p.bar:SetPoint("TOPLEFT", 80, -(top + 90))
    p.bar:SetPoint("TOPRIGHT", -80, -(top + 90))
    p:Hide()
    w.cmp = p
end

local function refreshCompare()
    local p, v = w.cmp, ns.view
    local c = v.compare
    local busy = ns.BusyKind() == "fresh"
    local has = c ~= nil and not busy
    p.mine:SetShown(has); p.fresh:SetShown(has); p.changes:SetShown(has); p.foot:SetShown(has)
    p.busy:SetShown(not has); p.bar:SetShown(busy)
    if busy then
        p.busy:SetText(L.CMP_BUSY:format(math.floor((ns.progress.done or 0) * 100)))
        p.bar:Set(ns.progress.done or 0)
    elseif not c then
        p.busy:SetText(L.CMP_FAILED)
    end
    if not has then return end
    p.mine:Set(c.mine); p.fresh:Set(c.fresh)
    p.list:SetData(c.rows)
    p.none:SetShown(#c.rows == 0)
    local text, col, can = ns.PinVerdict(c)
    p.verdict:SetText(hex(col) .. text .. "|r")
    p.dot:SetVertexColor(col[1], col[2], col[3], 1)
    p.go:SetEnabled(can)
end

-- ---------- the list of routes ----------

local function classColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return { c.r, c.g, c.b, 1 } end
    return S.TEXT
end

-- A row of the list in words: { title, sub, tag }.
function ns.PinRowText(e)
    local p = e.pin
    local title = L.PINS_ROW:format(p.prof or "?", p.from or 0, p.to or 0)
    local who = p.sim and (hex(ns.SIM_COLOR) .. L.SIM .. "|r") or (hex(classColor(p.class)) .. (p.who or "?") .. "|r")
    local sub
    if p.done then sub = who
    elseif (p.left or 0) > 0 then sub = who .. S.DOT .. L.PINS_LEFT:format(money(p.left))
    elseif (p.ofN or 0) > 0 then sub = who .. S.DOT .. L.PIN_T_ALL
    else sub = who end
    return title, sub, e.opens == "here" and L.PINS_OPEN_TAG or nil
end

function ns.PinRowOpen(e)
    local p = e.pin
    if e.opens == "here" then
        page = nil
        ns.Refresh()
    elseif e.opens == "sim" then
        page = nil
        if ns.PinOpenSim(p) then ns.Calculate() else ns.Refresh() end
    elseif e.opens == "prof" then
        page = nil
        if ns.sim then ns.SimStop() end
        ns.SetProfession(p.prof)
        ns.Refresh()
    end
end

function ns.PinRowAdopt(e)
    local mine, why = ns.PinAdopt(e.pin)
    if not mine then
        if why == "full" then ns.Toast(hex(S.WARN) .. L.PIN_FULL:format(ns.PIN_MAX) .. "|r") end
        return
    end
    page = nil
    if ns.sim then ns.SimStop() end
    ns.SetProfession(mine.prof)
    ns.Calculate()
end

local function buildList()
    local p = CreateFrame("Frame", nil, frame.body)
    p:SetAllPoints()
    p.head = topRow(p, L.PINS_TITLE, L.PINS_BACK)
    local foot = CreateFrame("Frame", nil, p)
    foot:SetPoint("BOTTOMLEFT", 0, 0)
    foot:SetPoint("BOTTOMRIGHT", 0, 0)
    foot:SetHeight(36)
    p.newSim = S.FitButton(foot, L.PINS_NEW_SIM, 32, 120)
    S.SetButtonIcon(p.newSim, ns.SIM_ICON, 16)
    p.newSim:SetWidth(p.newSim:GetWidth() + 22)
    p.newSim:SetPoint("RIGHT", 0, 0)
    p.newSim:SetScript("OnClick", function()
        page = nil
        if ns.sim then ns.SimSetup() else ns.SimOpen() end
        ns.Refresh()
    end)
    p.hint = S.Text(foot, 12, S.MUTED)
    p.hint:SetPoint("LEFT", 0, 0)
    p.hint:SetPoint("RIGHT", p.newSim, "LEFT", -10, 0)
    p.hint:SetJustifyH("LEFT")
    p.hint:SetMaxLines(2)
    p.hint:SetText(L.PINS_HINT)
    p.card = S.Card(p)
    p.card:SetPoint("TOPLEFT", 0, -(HEAD_H + S.GAP))
    p.card:SetPoint("BOTTOMRIGHT", foot, "TOPRIGHT", 0, S.GAP)
    p.list = S.List(p.card.body, ROW_H, function(r)
        r.group = S.Text(r, 12, S.GOLD_DIM, nil, "bold")
        r.group:SetPoint("LEFT", 2, -2)
        r.group:SetPoint("RIGHT", -2, -2)
        r.group:SetJustifyH("LEFT")
        r.group:SetWordWrap(false)
        r.icon = S.IconBox(r, 34)
        r.icon:SetPoint("LEFT", 2, 0)
        r.del = S.FitButton(r, "x", 28, 28)
        r.del:SetWidth(28)
        r.del:SetPoint("RIGHT", -4, 0)
        r.del:HookScript("OnEnter", function(self) tip(self, L.PINS_DELETE) end)
        r.del:HookScript("OnLeave", untip)
        r.del:SetScript("OnClick", function()
            if r.entry then ns.Unpin(r.entry.pin); ns.Refresh() end
        end)
        r.open = S.FitButton(r, L.PINS_OPEN, 28, 72)
        r.open:SetPoint("RIGHT", r.del, "LEFT", -6, 0)
        r.open:SetScript("OnClick", function() if r.entry then ns.PinRowOpen(r.entry) end end)
        r.adopt = S.FitButton(r, L.PINS_ADOPT, 28, 72)
        r.adopt:SetPoint("RIGHT", r.open, "LEFT", -6, 0)
        r.adopt:SetScript("OnClick", function() if r.entry then ns.PinRowAdopt(r.entry) end end)
        r.adopt:HookScript("OnEnter", function(self) tip(self, L.PINS_ADOPT, L.PINS_ADOPT_TIP) end)
        r.adopt:HookScript("OnLeave", untip)
        r.tag = S.Badge(r)
        r.title = S.Text(r, 14, S.GOLD, nil, "bold")
        r.title:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 10, 3)
        r.title:SetWordWrap(false)
        r.sub = S.Text(r, 12, S.MUTED)
        r.sub:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 10, 8)
        r.sub:SetWordWrap(false)
        r.bar = S.Progress(r, 3)
        r.bar:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 10, -5)
        r.bar:SetWidth(220)
        r.pct = S.Text(r, 12, S.MUTED)
        r.pct:SetPoint("LEFT", r.bar, "RIGHT", 8, 1)
        r.pct:SetWidth(200)
        r.pct:SetJustifyH("LEFT")
        r.pct:SetWordWrap(false)
    end, function(r, e)
        r.entry = e.pin and e or nil
        local row = e.pin ~= nil
        r.group:SetShown(not row)
        for _, x in ipairs({ r.icon, r.del, r.open, r.adopt, r.title, r.sub, r.bar, r.pct, r.tag }) do x:SetShown(row) end
        if not row then
            r.group:SetText(S.Upper(e.head == "done" and L.PINS_DONE or L.PINS_ACTIVE))
            return
        end
        local p0 = e.pin
        local title, sub, tag = ns.PinRowText(e)
        r.icon:SetIcon(p0.icon or ns.PIN_ICON)
        r.title:SetText(title)
        r.sub:SetText(sub)
        r.tag:Set(tag, S.Accent())
        r.tag:ClearAllPoints()
        r.tag:SetPoint("LEFT", r.title, "RIGHT", 8, 0)
        r.bar:Set(e.progress or 0, p0.done and S.GOOD or nil)
        r.pct:SetText(p0.done and (hex(S.GOOD) .. L.PINS_DONE_TAG .. "|r") or L.PINS_SKILL:format(e.skill or p0.from or 0))
        local opens = e.opens ~= nil and e.opens ~= "here"
        r.open:SetShown(opens)
        r.adopt:SetShown(e.adopt and true or false)
        r.adopt:ClearAllPoints()
        r.adopt:SetPoint("RIGHT", opens and r.open or r.del, "LEFT", -6, 0)
        local last = (e.adopt and r.adopt) or (opens and r.open) or r.del
        r.title:SetPoint("RIGHT", last, "LEFT", tag and -(r.tag:GetWidth() + 18) or -10, 0)
        r.sub:SetPoint("RIGHT", last, "LEFT", -10, 0)
        r:SetAlpha(p0.done and 0.75 or 1)
    end, 2)
    rawset(p.list, "heightOf", function(e) return e.pin and ROW_H or GROUP_H end)
    p.list:SetPoint("TOPLEFT", 0, 0)
    p.list:SetPoint("BOTTOMRIGHT", -10, 0)
    p.empty = S.Empty(p.card.body)
    p:Hide()
    w.list = p
end

local function refreshList()
    local p = w.list
    local rows = ns.PinRows()
    p.head.right:SetText(S.Emph(L.PINS_COUNT:format(ns.PinCount(), ns.PIN_MAX)))
    p.list:SetData(rows)
    p.list:SetShown(#rows > 0)
    if #rows == 0 then p.empty:Set(L.PINS_EMPTY, L.PINS_EMPTY_SUB) else p.empty:Set("") end
    p.rows = rows
end

-- ---------- UI.lua calls ----------

function ns.PinBuild(u, f)
    ui, frame = u, f
    buildChrome()
    buildTiles()
    buildCompare()
    buildList()
end

-- First in a refresh: a page of its own (the comparison, the list) takes the whole body.
function ns.PinPage()
    if not w.cmp then return false end
    if page == "compare" and (ns.sim or not ns.view.pin) then page = nil end
    ns.PinChrome()
    w.cmp:SetShown(page == "compare")
    w.list:SetShown(page == "list")
    if not page then return false end
    ui.main:Hide()
    w.strip:Hide()
    if ns.simUI then
        if ns.simUI.strip then ns.simUI.strip:Hide() end
        if ns.simUI.setup then ns.simUI.setup:Hide() end
    end
    if page == "compare" then refreshCompare() else refreshList() end
    return true
end
