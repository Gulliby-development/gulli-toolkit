-- The window: professions and tabs on top, the settings column on the right, and on the left
-- the levelling route as a graph of stops (or the crafts, items and recipes lists). It only
-- shows what Core.lua planned; every setting goes through ns.SetPref, which rebuilds the plan.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local W, H = S.WIDE_W, S.DOCK_H
local SIDE = 300
local NODE_W, NODE_H, COL_W, ROW_H = 130, 74, 140, 84
local MAIN = W - 2 * S.PAD - SIDE - S.GAP
local GRAPH_W = MAIN - 2 * S.INSET - 10
-- As many stops in a row as the graph is wide.
local PER_ROW = math.max(2, math.floor((GRAPH_W - 8 + COL_W - NODE_W) / COL_W))

-- Icons from the game for the stops; a craft stop shows the profession's own icon.
ns.STOP_ICONS = {
    bank = "Interface\\Icons\\INV_Box_02", ah = "Interface\\Icons\\INV_Misc_Bag_10",
    vendor = "Interface\\Icons\\INV_Misc_Bag_11", trainer = "Interface\\Icons\\INV_Misc_Book_11",
    craft = "Interface\\Icons\\Trade_Tailoring", sell = "Interface\\Icons\\INV_Misc_Coin_02",
}
local PATTERN_ICON = "Interface\\Icons\\INV_Scroll_03"
local RANK_ICON = "Interface\\Icons\\INV_Misc_Book_09"
local GOLD = { 1, 0.82, 0.25, 1 }
local GOOD, BAD = S.GOOD, S.BAD
local NODE_EDGE = S.EDGE

local frame
local ui = { checks = {}, modes = {}, nodes = {}, lines = {}, profs = {}, steppers = {} }
ns.ui = ui
local tab = 1
local selected = 1

-- ---------- money ----------

local function coins(c)
    if GetCoinTextureString then return GetCoinTextureString(c) end
    local g, s, k = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    local out = {}
    if g > 0 then out[#out + 1] = g .. "g" end
    if s > 0 or (g > 0 and k > 0) then out[#out + 1] = s .. "s" end
    if k > 0 or #out == 0 then out[#out + 1] = k .. "c" end
    return table.concat(out, " ")
end
-- A signed amount; `plus` adds "+" to a gain.
function ns.Money(c, plus)
    if c ~= c or c == math.huge or c == -math.huge then return "?" end
    c = math.floor((c or 0) + 0.5)
    local sign = c < 0 and "-" or (plus and c > 0 and "+" or "")
    return sign .. coins(math.abs(c))
end
-- The biggest coin only, for the tight space on a stop.
function ns.Short(c)
    if c ~= c or c == math.huge or c == -math.huge then return "?" end
    c = math.floor(math.abs(c or 0) + 0.5)
    if c >= 10000 then return coins(math.floor(c / 10000 + 0.5) * 10000) end
    if c >= 100 then return coins(math.floor(c / 100 + 0.5) * 100) end
    return coins(c)
end

local function color(c) return S.Hex(c) end
local function segColor(key) return ns.COLORS[key or "gy"] or ns.COLORS.gy end

-- ---------- the settings column ----------

-- The loss budgets the stepper offers, in copper; 0 is no limit.
local BUDGETS = { 0, 10000, 20000, 50000, 100000, 200000, 500000, 1000000, 2000000, 5000000, 10000000 }

local function pref(key)
    if key == "target" and ns.view.state then return ns.Target(ns.view.state, ns.view.prefs) end
    local P = ns.view.prefs or ns.Prefs(ns.db and ns.db.prefs)
    return P[key]
end

-- A switch row; ui.checks[key] is its switch.
local function switchRow(key)
    return { L["P_" .. key], nil, function() return pref(key) and true or false end,
             function(on) ns.SetPref(key, on and true or false) end, icon = ns.OPT_ICON[key] }
end

-- A row with the label over a - value + stepper, so long labels keep the full width.
local function stepRow(parent, key, step, min, max, fmt)
    local row = CreateFrame("Frame", nil, parent)
    row.height, row.isRow = 70, true
    row.icon = S.IconBox(row, 26, ns.OPT_ICON[key])
    row.icon:SetPoint("TOPLEFT", 0, -8)
    row.label = S.Text(row, 12)
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 12, 0)
    row.label:SetPoint("RIGHT", 0, 0)
    row.label:SetWordWrap(false)
    row.label:SetText(key == "target" and L.SIDE_TARGET or L["P_" .. key])
    local get = function() return pref(key) or ns.DEFAULTS[key] end
    local set = function(v) ns.SetPref(key, v) end
    if key == "budget" then
        -- the stepper walks the BUDGETS list, the setting keeps copper
        get = function()
            local b, at = pref("budget") or 0, 1
            for i, x in ipairs(BUDGETS) do if x <= b then at = i end end
            return at
        end
        set = function(i) ns.SetPref("budget", BUDGETS[i]) end
    end
    local st = S.Stepper(row, get, set, step, min, max, fmt)
    st:SetPoint("BOTTOMLEFT", 38, 8)
    st:SetPoint("BOTTOMRIGHT", 0, 8)
    row.line = S.Divider(row)
    row.line:SetPoint("BOTTOMLEFT")
    row.line:SetPoint("BOTTOMRIGHT")
    row.line:SetHeight(1)
    ui[key] = st
    ui.steppers[key] = st
    return row
end

-- A card of rows: switch rows (tables) and ready frames (stepRow), stacked.
local function rowsCard(parent, title, rows)
    local card = S.Card(parent, title)
    local st = S.Stack(card.body, 0)
    for i, r in ipairs(rows) do
        local row = r
        if r.isRow then r:SetParent(card.body) end
        if not r.isRow then
            row = S.SwitchRow(card.body, r[1], r[2], r[3], r[4], nil, r.icon)
            ui.checks[r.key] = row.switch
        end
        st:Add(row, row.height)
        row.line:SetShown(i < #rows)
    end
    return card, card:Fit(st:Height() - 6)
end

local function sw(key) local r = switchRow(key); r.key = key; return r end

local function buildSide(scroll)
    local inner = SIDE - 10
    local col = scroll.child
    col:SetWidth(inner)
    local st = S.Stack(col)

    -- the professions this character has seen
    local prof = S.Card(col, L.SIDE_PROF)
    ui.profCard = prof
    st:Add(prof, prof:Fit(4 * 34 - 6))

    local lv = sw("level")
    local target = stepRow(col, "target", 5, 1, 300)
    local budget = stepRow(col, "budget", 1, 1, #BUDGETS, function(i) return BUDGETS[i] == 0 and L.NO_LIMIT or ns.Money(BUDGETS[i]) end)
    local c0, h0 = rowsCard(col, L.SIDE_TARGET, { lv, target, budget })
    st:Add(c0, h0)

    local c1, h1 = rowsCard(col, L.SIDE_FROM, { sw("useBags"), sw("useBank"), sw("buyAH"),
        stepRow(col, "maxBuy", 10, 10, 200, function(v) return L.UNITS:format(v) end), sw("buyVendor") })
    st:Add(c1, h1)
    local c2, h2 = rowsCard(col, L.SIDE_LEARN, { sw("buyRecipes"), sw("trainer") })
    st:Add(c2, h2)
    local c3, h3 = rowsCard(col, L.SIDE_SELL, { sw("sellAH"), sw("neutral"), sw("freshOnly"),
        stepRow(col, "chance", 5, 30, 100, function(v) return v .. "%" end),
        stepRow(col, "maxSell", 1, 1, 40, function(v) return L.UNITS:format(v) end) })
    st:Add(c3, h3)
    ui.sideCards = st.items
    col:SetHeight(st:Height())
    scroll:Update(st:Height())
end

local function refreshSide()
    local P = ns.view.prefs or ns.Prefs(ns.db and ns.db.prefs)
    for k, c in pairs(ui.checks) do c:SetChecked(P[k] and true or false) end
    for _, key in ipairs({ "target", "budget" }) do
        ui[key].minus:SetEnabled(P.level and true or false)
        ui[key].plus:SetEnabled(P.level and true or false)
    end
    for _, s in pairs(ui.steppers) do s:Refresh() end
    local d = ns.view.delta
    if d then
        local up = d.net >= 0
        local text = L.DELTA:format(ns.Money(d.fromNet), ns.Money(ns.view.plan.net)) .. " "
            .. color(up and GOOD or BAD) .. "(" .. ns.Money(d.net, true) .. ")|r\n"
            .. L.DELTA_CRAFTS:format(d.fromCrafts, d.fromCrafts + d.crafts)
        if d.crafts ~= 0 then
            text = text .. " " .. color(d.crafts <= 0 and GOOD or BAD) .. "(" .. (d.crafts > 0 and "+" or "") .. d.crafts .. ")|r"
        end
        ui.toast:SetText(text)
    else
        ui.toast:SetText(L.TOAST_HINT)
    end
end

-- ---------- the route graph ----------

local function stopIcon(n)
    if n.kind == "craft" and n.prep and n.lines[1] then
        local r = ns.view.state.recipes[n.lines[1].recipe]
        if r and r.out then return ns.ItemIcon(r.out) end
    end
    if n.kind == "craft" and ns.view.state.icon then return ns.view.state.icon end
    return ns.STOP_ICONS[n.kind]
end

local function stopTitle(n)
    if n.title == "STOP_CRAFT" then return L.STOP_CRAFT:format(n.from, n.to) end
    if n.title == "STOP_EARN" then return L.STOP_EARN end
    if n.title == "STOP_RANK" then return L.STOP_RANK:format(n.rank.cap) end
    return L[n.title]
end

local function lineIcon(l)
    if l.rank then return RANK_ICON, 1 end
    if l.id then return ns.ItemIcon(l.id), (ns.view.state.items[l.id] or {}).quality end
    local r = l.recipe and ns.view.state.recipes[l.recipe]
    if l.src == "prep" and r and r.out then return ns.ItemIcon(r.out), 1 end
    return PATTERN_ICON, 1
end

local function makeNode(parent, i)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(NODE_W, NODE_H)
    S.Box(b, S.RAISED, NODE_EDGE)
    b.stripe = S.Tex(b, "ARTWORK", 0, { 1, 1, 1, 1 })
    b.stripe:SetPoint("TOPLEFT", 1, -1)
    b.stripe:SetPoint("BOTTOMLEFT", 1, 1)
    b.stripe:SetWidth(3)
    b.icon = S.ItemIcon(b, 28)
    b.icon:SetPoint("TOPLEFT", 10, -7)
    b.kind = S.Text(b, 9, S.MUTED, "")
    b.kind:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 6, 0)
    b.kind:SetPoint("RIGHT", -4, 0)
    b.kind:SetWordWrap(false)
    b.title = S.Text(b, 11)
    b.title:SetPoint("TOPLEFT", b.kind, "BOTTOMLEFT", 0, -3)
    b.title:SetPoint("RIGHT", -4, 0)
    b.title:SetWordWrap(false)
    b.strip = {}
    for k = 1, 4 do
        local ic = S.ItemIcon(b, 16)
        ic:SetPoint("BOTTOMLEFT", 10 + (k - 1) * 18, 8)
        b.strip[k] = ic
    end
    b.more = S.Text(b, 9, S.MUTED)
    b.more:SetPoint("BOTTOMLEFT", 10 + 4 * 18, 11)
    b.money = S.Text(b, 10, S.MUTED)
    b.money:SetPoint("BOTTOMRIGHT", -6, 10)
    b.bar = {}
    b:SetScript("OnClick", function() selected = i; ns.Refresh() end)
    return b
end

local function nodePos(i)
    local row = math.floor((i - 1) / PER_ROW)
    local c = (i - 1) % PER_ROW
    local col = (row % 2 == 1) and (PER_ROW - 1 - c) or c
    return 4 + col * COL_W, -(4 + row * ROW_H)
end

local function fillNode(b, n)
    local kc = (n.kind == "craft" and n.segs) and segColor(n.segs[1].color) or ns.STOPS[n.kind]
    b.stripe:SetVertexColor(kc[1], kc[2], kc[3], 1)
    b.icon:Set(stopIcon(n))
    b.kind:SetText(color(kc) .. n.index .. ". " .. (L["KIND_" .. n.kind] or n.kind) .. "|r")
    b.title:SetText(stopTitle(n))
    local icons = {}
    if n.segs then
        local seen = {}
        for _, sg in ipairs(n.segs) do
            local r = ns.view.state.recipes[sg.rid]
            if r.out and not seen[r.out] then seen[r.out] = true; icons[#icons + 1] = { ns.ItemIcon(r.out), nil, (ns.view.state.items[r.out] or {}).quality } end
        end
    else
        for _, l in ipairs(n.lines or {}) do
            local t, q = lineIcon(l)
            icons[#icons + 1] = { t, l.n, q }
        end
    end
    for k = 1, 4 do
        local ic = icons[k]
        if ic then b.strip[k]:Set(ic[1], ic[2], ic[3]) else b.strip[k]:Hide() end
    end
    b.more:SetText(#icons > 4 and ("+" .. (#icons - 4)) or "")
    if n.segs then b.money:SetText("x" .. n.crafts)
    elseif n.cost and n.cost > 0 then b.money:SetText(ns.Short(n.cost))
    else b.money:SetText("") end
    -- the recipe colours along the bottom of a craft stop
    for _, t in ipairs(b.bar) do t:Hide() end
    if n.segs then
        local span = n.to - n.from
        local x = 4
        for k, sg in ipairs(n.segs) do
            local t = b.bar[k] or S.Tex(b, "OVERLAY", 0, S.TEXT)
            b.bar[k] = t
            local w = math.max(1, (NODE_W - 5) * (sg.to - sg.from) / span)
            local c = segColor(sg.color)
            t:SetVertexColor(c[1], c[2], c[3], 1)
            t:ClearAllPoints()
            t:SetPoint("BOTTOMLEFT", x, 1)
            t:SetSize(w, 3)
            t:Show()
            x = x + w
        end
    end
    n.shownSelected = (n.index == selected)
    S.SetBorder(b, n.shownSelected and S.Accent() or NODE_EDGE)
end

local function drawGraph()
    local route = ns.view.route or {}
    local child = ui.graph.child
    for i, n in ipairs(route) do
        local b = ui.nodes[i] or makeNode(child, i)
        ui.nodes[i] = b
        local x, y = nodePos(i)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", x, y)
        fillNode(b, n)
        b:Show()
        if ns.view.changed and ns.view.changed[i] then
            S.SetBorder(b, GOLD)
            b.lit = true
            C_Timer.After(1.4, function()
                b.lit = nil
                S.SetBorder(b, (selected == i) and S.Accent() or NODE_EDGE)
            end)
        end
    end
    for i = #route + 1, #ui.nodes do ui.nodes[i]:Hide() end
    -- arrows between stops: across a row, then down at its end
    for i = 2, #route do
        local l = ui.lines[i]
        if not l then
            l = child:CreateLine(nil, "BACKGROUND")
            l:SetColorTexture(0.35, 0.35, 0.38, 1)
            l:SetThickness(2)
            ui.lines[i] = l
        end
        local a, b = ui.nodes[i - 1], ui.nodes[i]
        local ax = select(1, nodePos(i - 1))
        local bx = select(1, nodePos(i))
        if ax == bx then
            l:SetStartPoint("BOTTOM", a, 0, 0); l:SetEndPoint("TOP", b, 0, 0)
        elseif ax < bx then
            l:SetStartPoint("RIGHT", a, 0, 0); l:SetEndPoint("LEFT", b, 0, 0)
        else
            l:SetStartPoint("LEFT", a, 0, 0); l:SetEndPoint("RIGHT", b, 0, 0)
        end
        l:Show()
    end
    for i = #route + 1, #ui.lines do if ui.lines[i] then ui.lines[i]:Hide() end end
    local rows = math.ceil(#route / PER_ROW)
    local h = 8 + rows * ROW_H
    child:SetSize(GRAPH_W, h)
    ui.graph:Update(h)
end

local SRC = { bank = "SRC_bank", ah = "SRC_ah", vendor = "SRC_vendor", trainer = "SRC_trainer", prep = "SRC_prep",
              sellah = "SRC_sellah", sellv = "SRC_sellv" }

-- The rows under the graph for the chosen stop.
local function detailRows(n)
    local rows = {}
    if not n then return rows end
    local st = ns.view.state
    for _, sg in ipairs(n.segs or {}) do
        local r = st.recipes[sg.rid]
        local reagents = {}
        for id, k in pairs(r.r) do reagents[#reagents + 1] = (st.items[id] or {}).name .. " x" .. ns.Ceil(k * sg.n) end
        table.sort(reagents)
        rows[#rows + 1] = { icon = r.out and ns.ItemIcon(r.out), q = r.out and (st.items[r.out] or {}).quality,
                            text = color(segColor(sg.color)) .. r.name .. "|r x" .. ns.Ceil(sg.n),
                            mid = sg.from .. " - " .. sg.to, right = table.concat(reagents, ", ") }
    end
    for _, l in ipairs(n.lines or {}) do
        local icon, q = lineIcon(l)
        local name = l.rank and L.STOP_RANK:format(l.rank) or l.name
        rows[#rows + 1] = { icon = icon, n = l.n, q = q, text = name .. " x" .. l.n, mid = L[SRC[l.src] or ""] or "",
                            right = l.price and ns.Money(l.price * l.n) or "" }
    end
    return rows
end

local function makeLine(r)
    r.icon = S.ItemIcon(r, 20)
    r.icon:SetPoint("LEFT", 4, 0)
    r.right = S.Text(r, 11)
    r.right:SetPoint("RIGHT", -6, 0)
    r.right:SetJustifyH("RIGHT")
    r.mid = S.Text(r, 11, S.MUTED)
    r.mid:SetPoint("RIGHT", -170, 0)
    r.text = S.Text(r, 12)
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.text:SetPoint("RIGHT", r.mid, "LEFT", -8, 0)
    r.text:SetWordWrap(false)
end
local function fillLine(r, e)
    if e.icon then r.icon:Set(e.icon, e.n, e.q) else r.icon:Hide() end
    r.text:SetText(e.text)
    r.mid:SetText(e.mid or "")
    r.right:SetText(e.right or "")
end

-- ---------- the list tabs ----------

-- Columns: { header key, x from the right edge (nil: the name column), width }.
local LISTS = {
    { { "C_RECIPE" }, { "C_COST", 330 }, { "C_VALUE", 250 }, { "C_WHERE", 170 }, { "C_PROFIT", 90 }, { "C_CAN", 6 } },
    { { "I_ITEM" }, { "I_BAGS", 400 }, { "I_BANK", 350 }, { "I_BEST", 200 }, { "I_EACH", 100 }, { "I_TOTAL", 6 } },
    { { "C_RECIPE" }, { "R_WHERE", 330 }, { "R_PRICE", 250 }, { "R_SKILL", 200 }, { "C_PROFIT", 100 }, { "R_PAY", 6 } },
}

local function listRows(which)
    local st, P = ns.view.state, ns.view.prefs
    local rows = {}
    if not st then return rows end
    if which == 2 then
        for _, x in ipairs(ns.Crafts(st, P)) do
            local r = st.recipes[x.recipe]
            local c = x.color and segColor(x.color) or S.MUTED
            rows[#rows + 1] = { icon = r.out and ns.ItemIcon(r.out), q = r.out and (st.items[r.out] or {}).quality,
                text = color(c) .. "■|r " .. x.name .. (x.stale and (" " .. color(GOLD) .. L.STALE .. "|r") or ""),
                cols = { ns.Money(x.cost), ns.Money(x.value), L["HOW_" .. x.how],
                         color(x.profit >= 0 and GOOD or BAD) .. ns.Money(x.profit, true) .. "|r",
                         x.can > 0 and L.TIMES:format(x.can) or "-" } }
        end
    elseif which == 3 then
        for _, x in ipairs(ns.Items(st, P)) do
            rows[#rows + 1] = { icon = ns.ItemIcon(x.id), n = x.bags + x.bank, q = (st.items[x.id] or {}).quality, text = x.name,
                cols = { tostring(x.bags), tostring(x.bank),
                         L["HOW_" .. x.how] .. (x.recipeName and (": " .. x.recipeName) or ""),
                         ns.Money(x.each), ns.Money(x.total) } }
        end
    else
        for _, x in ipairs(ns.Recipes(st, P)) do
            local r = st.recipes[x.recipe]
            rows[#rows + 1] = { icon = r.out and ns.ItemIcon(r.out) or PATTERN_ICON, text = x.name,
                cols = { L["WHERE_" .. x.src] or "", x.cost and ns.Money(x.cost) or "-", x.skill and tostring(x.skill) or "-",
                         x.profit and (color(x.profit >= 0 and GOOD or BAD) .. ns.Money(x.profit, true) .. "|r") or L.NO_PRICE,
                         x.pay and L.PAY_AT:format(x.pay) or (x.src == "text" and L.WHERE_text or (x.profit and L.PAY_NEVER or "-")) } }
        end
    end
    return rows
end

local function makeListRow(r)
    r.icon = S.ItemIcon(r, 22)
    r.icon:SetPoint("LEFT", 4, 0)
    r.cols = {}
    for k = 2, 6 do
        local t = S.Text(r, 11)
        t:SetJustifyH("RIGHT")
        r.cols[k - 1] = t
    end
    r.text = S.Text(r, 12)
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.text:SetWordWrap(false)
end

local function fillListRow(r, e)
    local spec = LISTS[tab - 1]
    if e.icon then r.icon:Set(e.icon, e.n, e.q) else r.icon:Hide() end
    r.text:SetText(e.text)
    r.text:SetPoint("RIGHT", r, "RIGHT", -(spec[2][2] + 80), 0)
    for k = 1, 5 do
        local t = r.cols[k]
        t:ClearAllPoints()
        t:SetPoint("RIGHT", r, "RIGHT", -spec[k + 1][2], 0)
        t:SetWidth(spec[k + 1][2] == 6 and 80 or 74)
        t:SetText(e.cols[k] or "")
    end
end

-- ---------- building and refreshing ----------


local function build()
    frame = S.Window("GulliCraftProfitFrame", L.TITLE, W, H)
    ui.frame = frame
    ui.age = frame.sub
    local footer = S.Footer(frame)
    ui.toast = footer.status
    ui.reset = footer:Add(S.FitButton(footer, L.RESET, 32, 96))
    ui.reset:SetScript("OnClick", function() ns.ResetPrefs() end)
    local body = frame.body
    local bodyH = frame.inner[2]

    -- the settings column on the right
    local sideBox = CreateFrame("Frame", nil, body)
    sideBox:SetPoint("TOPRIGHT", 0, 0)
    sideBox:SetPoint("BOTTOMRIGHT", 0, 0)
    sideBox:SetWidth(SIDE)
    local side = S.Scroll(sideBox)
    side:SetPoint("TOPLEFT", 0, 0)
    side:SetPoint("BOTTOMRIGHT", -10, 0)
    ui.side = side
    buildSide(side)

    local main = CreateFrame("Frame", nil, body)
    main:SetPoint("TOPLEFT", 0, 0)
    main:SetPoint("BOTTOMLEFT", 0, 0)
    main:SetWidth(MAIN)
    ui.main = main
    local labels = { L.TAB_ROUTE, L.TAB_CRAFTS, L.TAB_ITEMS, L.TAB_RECIPES }
    ui.tabs = S.Tabs(main, labels, nil, function(i) tab = i; if ns.Refresh then ns.Refresh() end end)
    local top = 30 + S.GAP

    -- route tab: numbers, the graph with the skill bar, the chosen stop
    local route = CreateFrame("Frame", nil, main)
    route:SetPoint("TOPLEFT", 0, -top)
    route:SetPoint("BOTTOMRIGHT", 0, 0)
    ui.route = route
    local st = S.Stack(route)
    -- the routes side by side: pick one, compare the result and the crafts
    local vars = CreateFrame("Frame", nil, route)
    st:Add(vars, 62)
    local nv = #ns.MODES
    local vw = math.floor((MAIN - (nv - 1) * 8) / nv)
    ui.varTiles = {}
    for i, m in ipairs(ns.MODES) do
        local b = CreateFrame("Button", nil, vars)
        b:SetSize(vw, 62)
        b:SetPoint("TOPLEFT", (i - 1) * (vw + 8), 0)
        S.Box(b, S.SURFACE, S.EDGE)
        b.mark = S.Tex(b, "ARTWORK", 0, S.Accent())
        b.mark:SetPoint("TOPLEFT", 1, -1)
        b.mark:SetPoint("TOPRIGHT", -1, -1)
        b.mark:SetHeight(2)
        b.icon = S.IconBox(b, 18, ns.EARN[m] and "Interface\\Icons\\INV_Misc_Coin_02" or ns.OPT_ICON.level)
        b.icon:SetPoint("TOPRIGHT", -6, -6)
        b.label = S.Text(b, 10, S.MUTED)
        b.label:SetPoint("TOPLEFT", 8, -8)
        b.label:SetPoint("RIGHT", b.icon, "LEFT", -4, 0)
        b.label:SetWordWrap(false)
        b.value = S.Text(b, 15)
        b.value:SetPoint("TOPLEFT", b.label, "BOTTOMLEFT", 0, -5)
        b.value:SetPoint("RIGHT", -6, 0)
        b.value:SetWordWrap(false)
        b.sub = S.Text(b, 10, S.MUTED)
        b.sub:SetPoint("BOTTOMLEFT", 8, 7)
        b.sub:SetPoint("RIGHT", -6, 0)
        b.sub:SetWordWrap(false)
        b:SetScript("OnClick", function(self)
            if ns.EARN[m] then ns.SetPref("mode", m); return end
            -- the best route within the budget stays automatic; a levelling tile turns levelling on
            ns.SetPrefs({ mode = (self.best and (ns.view.prefs.budget or 0) > 0) and "auto" or m, level = true })
        end)
        b:SetScript("OnEnter", function(self) if ns.view.mode ~= m then S.SetBorder(self, S.Accent()) end end)
        b:SetScript("OnLeave", function(self) if ns.view.mode ~= m then S.SetBorder(self, S.EDGE) end end)
        ui.varTiles[i] = b
        ui.modes[m] = b
    end
    local detailH = 36 + 3 * 28 + S.INSET
    local graphH = bodyH - top - st.y - S.GAP - detailH
    local gcard = S.Card(route, L.TAB_ROUTE)
    st:Add(gcard, graphH)
    ui.graphCard = gcard
    ui.money = gcard.hint
    local graphBox = CreateFrame("Frame", nil, gcard.body)
    graphBox:SetPoint("TOPLEFT", 0, 0)
    graphBox:SetPoint("BOTTOMRIGHT", 0, 30)
    ui.graph = S.Scroll(graphBox)
    ui.graph:SetPoint("TOPLEFT", 0, 0)
    ui.graph:SetPoint("BOTTOMRIGHT", -10, 0)
    local bar = CreateFrame("Frame", nil, gcard.body)
    bar:SetPoint("BOTTOMLEFT", 0, 16)
    bar:SetPoint("BOTTOMRIGHT", 0, 16)
    bar:SetHeight(8)
    S.Box(bar, S.INPUT, S.EDGE)
    ui.bar, ui.barParts = bar, {}
    ui.skillFrom = S.Text(gcard.body, 10, S.MUTED)
    ui.skillFrom:SetPoint("BOTTOMLEFT", 0, 0)
    ui.skillTo = S.Text(gcard.body, 10, S.MUTED)
    ui.skillTo:SetPoint("BOTTOMRIGHT", 0, 0)
    ui.skillTo:SetPoint("LEFT", ui.skillFrom, "RIGHT", 12, 0)
    ui.skillTo:SetWordWrap(false)
    ui.skillTo:SetJustifyH("RIGHT")
    local dcard = S.Card(route, " ")
    st:Add(dcard, detailH)
    ui.detailCard = dcard
    ui.detailTitle = dcard.title
    ui.detail = S.List(dcard.body, 28, makeLine, fillLine)
    ui.detail:SetPoint("TOPLEFT", 0, 0)
    ui.detail:SetPoint("BOTTOMRIGHT", -10, 0)

    -- list tabs: one card with column heads and rows
    local list = S.Card(main)
    list:SetPoint("TOPLEFT", 0, -top)
    list:SetPoint("BOTTOMRIGHT", 0, 0)
    ui.listFrame = list
    ui.listHead = {}
    for k = 1, 6 do ui.listHead[k] = S.Text(list.body, 10, S.MUTED) end
    ui.list = S.List(list.body, 32, makeListRow, fillListRow)
    ui.list:SetPoint("TOPLEFT", 0, -20)
    ui.list:SetPoint("BOTTOMRIGHT", -10, 0)

    local emptyBox = CreateFrame("Frame", nil, main)
    emptyBox:SetPoint("TOPLEFT", 0, -top)
    emptyBox:SetPoint("BOTTOMRIGHT", 0, 0)
    ui.empty = S.Empty(emptyBox)

    frame:SetScript("OnShow", function() ns.Recalc(false); ns.Refresh() end)
    ui.tabs:Select(1, true)
end

local function refreshProfessions()
    local profs = ns.Professions()
    local body = ui.profCard.body
    for i, p in ipairs(profs) do
        local b = ui.profs[i]
        if not b then
            b = S.Pill(body, 10, 28)
            b:SetPoint("TOPLEFT", 0, -(i - 1) * 34)
            b:SetPoint("TOPRIGHT", 0, -(i - 1) * 34)
            b.icon = S.IconBox(b, 20)
            b.icon:SetPoint("LEFT", 4, 0)
            b.text:ClearAllPoints()
            b.text:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
            b.text:SetPoint("RIGHT", -8, 0)
            b.text:SetJustifyH("LEFT")
            ui.profs[i] = b
        end
        b.icon:SetIcon(p.icon)
        b:SetText(p.name .. "  " .. color(S.MUTED) .. p.skill .. "/" .. p.cap .. "|r")
        b:SetScript("OnClick", function() ns.SetProfession(p.name) end)
        b:SetSelected(ns.char.current == p.name)
        b:Show()
    end
    for i = #profs + 1, #ui.profs do ui.profs[i]:Hide() end
    local n = math.max(1, #profs)
    local h = ui.profCard:Fit(n * 34 - 6)
    if h ~= ui.profH then
        -- the cards under it move with the card's height
        ui.profH = h
        local y = 0
        for _, c in ipairs(ui.sideCards) do
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", 0, -y)
            c:SetPoint("TOPRIGHT", 0, -y)
            y = y + c:GetHeight() + S.GAP
        end
        ui.side.child:SetHeight(y - S.GAP)
        ui.side:Update(y - S.GAP)
    end
end

-- A levelling route's name by its place among n: the cheapest, the fastest, or an option between.
local function routeName(mode, n, long)
    if ns.EARN[mode] then return L[(long and "VAR_" or "TILE_") .. mode] end
    local i = tonumber(mode:sub(2)) or 1
    local key = (i == 1) and "cheap" or (i == n and "fast" or "mid")
    return L[(long and "VAR_" or "TILE_") .. key]:format(i)
end

local function refreshRoute()
    local v = ns.view
    local plan = v.plan
    local levels, anyLevel = 0, false
    for _, x in ipairs(v.variants or {}) do if not ns.EARN[x.mode] and x.plan then levels = levels + 1; anyLevel = true end end
    -- the tiles shown: the levelling routes there are (or one that says why there are none), the profit ones
    local shown = {}
    for i, x in ipairs(v.variants or {}) do
        local b = ui.varTiles[i]
        local visible = x.plan ~= nil or (i == 1 and not anyLevel)
        b:SetShown(visible)
        if visible then shown[#shown + 1] = { b = b, x = x } end
    end
    local k = #shown
    local vw = math.floor((MAIN - (k - 1) * 8) / k)
    for j, e in ipairs(shown) do
        local b, x = e.b, e.x
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", (j - 1) * (vw + 8), 0)
        b:SetSize(vw, 62)
        local on = x.mode == v.mode
        local p = x.plan
        b.best = x.best
        S.Fill(b, on and S.RAISED or S.SURFACE)
        S.SetBorder(b, on and S.Accent() or S.EDGE)
        b.mark:SetShown(on)
        b.label:SetText(j .. ". " .. routeName(x.mode, levels))
        if p then
            -- the money of the whole way, so the tiles compare routes; the crafts of the next run
            local full = p.full or p
            b.value:SetText(color(full.net >= 0 and GOOD or BAD) .. (full.net < 0 and "-" or "+") .. ns.Short(full.net) .. "|r")
            local sub = (full.reached < full.target) and L.VAR_STOP:format(full.reached)
                or (p.earn and L.VAR_GOLD:format(ns.Ceil(p.crafts)) or L.VAR_RUN:format(p.reached, ns.Ceil(p.crafts)))
            if x.over then sub = color(BAD) .. L.VAR_OVER .. "|r"
            elseif x.best and v.prefs.budget > 0 then sub = color(GOOD) .. L.VAR_BEST .. "|r" end
            b.sub:SetText(sub)
            b:SetAlpha(x.over and 0.55 or 1)
        else
            b.label:SetText(j .. ". " .. L.TILE_cheap)
            b.value:SetText(color(S.FAINT) .. "-|r")
            b.sub:SetText(v.prefs.level and L.VAR_MAXED or L.VAR_OFF)
            b:SetAlpha(0.6)
        end
    end
    ui.money:SetText(L.HINT_MONEY:format(ns.Short(plan.spend), ns.Short(plan.own), ns.Short(plan.income)))
    ui.graphCard:SetTitle(routeName(v.mode, levels, true))
    local w = plan.warn or (plan.full and plan.full.warn)
    local warn = w and (color(GOLD) .. L[w[1]]:format(w[2], w[3]) .. "|r") or nil
    if selected > #v.route then selected = 1 end
    drawGraph()
    -- the skill bar: one colour per recipe stretch, a mark at each rank cap
    local span = math.max(1, plan.target - v.state.skill)
    local width = math.max(1, ui.bar:GetWidth() - 2)
    for _, t in ipairs(ui.barParts) do t:Hide() end
    local x, k = 1, 0
    for _, sg in ipairs(plan.segs) do
        k = k + 1
        local t = ui.barParts[k] or S.Tex(ui.bar, "ARTWORK", 0, S.TEXT)
        ui.barParts[k] = t
        local c = segColor(sg.color)
        local wd = math.max(1, width * (sg.to - sg.from) / span)
        t:SetVertexColor(c[1], c[2], c[3], 1)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", x, -1)
        t:SetSize(wd, 6)
        t:Show()
        x = x + wd
    end
    ui.bar:SetShown(not plan.earn)
    ui.skillFrom:SetText(L.SKILL_FROM:format(v.state.skill))
    local guess = false
    for _, r in pairs(v.state.recipes) do if r.guess and r.learned then guess = true end end
    if plan.earn then
        ui.skillTo:SetText(warn or "")
    else
        local full = plan.full or plan
        local where
        if full.reached < full.target then where = L.SKILL_SHORT:format(full.reached, full.target)
        elseif full ~= plan then where = L.SKILL_ALL:format(full.target, ns.Ceil(full.crafts))
        else where = L.SKILL_TARGET:format(plan.target) end
        if full ~= plan then where = L.SKILL_RUN:format(plan.reached) .. "  ·  " .. where end
        ui.skillTo:SetText((warn and (warn .. "  ·  ") or "") .. (guess and (L.GUESS .. "  ·  ") or "") .. where)
    end
    local n = v.route[selected]
    ui.detailCard:SetTitle(n and (n.index .. ". " .. (L["KIND_" .. n.kind] or "") .. ": " .. stopTitle(n)) or "")
    ui.detail:SetData(detailRows(n))
end

local function refreshList()
    local spec = LISTS[tab - 1]
    for k = 1, 6 do
        local t = ui.listHead[k]
        t:ClearAllPoints()
        if k == 1 then t:SetPoint("TOPLEFT", 34, 0) else t:SetPoint("TOPRIGHT", -(spec[k][2] + 10), 0) end
        t:SetText(L[spec[k][1]])
    end
    ui.list:SetData(listRows(tab))
end

function ns.Visible() return frame ~= nil and frame:IsShown() end

function ns.Refresh()
    if not ns.Visible() then return end
    refreshProfessions()
    refreshSide()
    local v = ns.view
    local age = ns.PriceAge(v.state)
    local slash = "/gcp  ·  "
    if not ns.HasAuctionator() then ui.age:SetText(slash .. color(GOLD) .. L.NO_AUCTIONATOR .. "|r")
    elseif age then ui.age:SetText(slash .. L.PRICES_AGE:format(age < 1 and L.AGE_TODAY or L.AGE_DAYS:format(math.floor(age))))
    else ui.age:SetText("/gcp") end
    local has = v.state ~= nil and v.plan ~= nil
    ui.empty:Set(has and "" or L.NO_PROF)
    ui.empty:SetShown(not has)
    ui.route:SetShown(has and tab == 1)
    ui.listFrame:SetShown(has and tab > 1)
    if not has then return end
    if tab == 1 then refreshRoute() else refreshList() end
end

-- The chosen stop and tab, for the tests.
function ns.Select(i) selected = i; ns.Refresh() end
function ns.Tab(i) if ui.tabs then ui.tabs:Select(i) end end
function ns.Selected() return selected, tab end

function ns.Toggle()
    if S.ToggleWindow(ns.Window()) then
        ns.Recalc(false); ns.Refresh()
    end
end

-- The window, for the hub (/gulli) to show inside it.
function ns.Window()
    if not frame then
        build()
        -- In the hub the window is shown by the hub, not by ns.Toggle.
        frame:HookScript("OnShow", function(self)
            if not self.docked then return end
            ns.Recalc(false); ns.Refresh()
        end)
    end
    return frame
end
