-- The window: professions and tabs on top, the settings column on the right, and on the left
-- the levelling route as a graph of stops (or the crafts, items and recipes lists). It only
-- shows what Core.lua planned; every setting goes through ns.SetPref, which rebuilds the plan.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local W, H = 940, 640
local SIDE = 250
local NODE_W, NODE_H, COL_W, ROW_H, PER_ROW = 150, 80, 168, 92, 4

-- Icons from the game for the stops; a craft stop shows the profession's own icon.
ns.STOP_ICONS = {
    bank = "Interface\\Icons\\INV_Box_02", ah = "Interface\\Icons\\INV_Misc_Coin_02",
    vendor = "Interface\\Icons\\INV_Misc_Bag_10", trainer = "Interface\\Icons\\INV_Misc_Book_11",
    craft = "Interface\\Icons\\Trade_Tailoring", sell = "Interface\\Icons\\INV_Misc_Coin_17",
}
local PATTERN_ICON = "Interface\\Icons\\INV_Scroll_03"
local RANK_ICON = "Interface\\Icons\\INV_Misc_Book_09"
local GOLD = { 1, 0.82, 0.25, 1 }
local GOOD, BAD = { 0.36, 0.82, 0.48, 1 }, { 1, 0.42, 0.42, 1 }

local frame
local ui = { checks = {}, modes = {}, nodes = {}, lines = {}, profs = {} }
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
    c = math.floor((c or 0) + 0.5)
    local sign = c < 0 and "-" or (plus and c > 0 and "+" or "")
    return sign .. coins(math.abs(c))
end
-- The biggest coin only, for the tight space on a stop.
function ns.Short(c)
    c = math.floor(math.abs(c or 0) + 0.5)
    if c >= 10000 then return coins(math.floor(c / 10000 + 0.5) * 10000) end
    if c >= 100 then return coins(math.floor(c / 100 + 0.5) * 100) end
    return coins(c)
end

local function color(c) return S.Hex(c) end
local function segColor(key) return ns.COLORS[key or "gy"] or ns.COLORS.gy end

-- ---------- the settings column ----------

local function header(parent, text, y)
    local t = S.Text(parent, 10, S.MUTED)
    t:SetPoint("TOPLEFT", 0, y)
    t:SetText(text:upper())
    return t
end

local PREF_ICONS = {
    useBags = "Interface\\Icons\\INV_Misc_Bag_08", useBank = "Interface\\Icons\\INV_Box_02",
    buyAH = "Interface\\Icons\\INV_Misc_Coin_02", buyVendor = "Interface\\Icons\\INV_Misc_Bag_10",
    buyRecipes = PATTERN_ICON, trainer = "Interface\\Icons\\INV_Misc_Book_11",
    sellAH = "Interface\\Icons\\INV_Misc_Coin_17", neutral = "Interface\\Icons\\INV_Misc_Coin_04",
    freshOnly = "Interface\\Icons\\INV_Misc_PocketWatch_01",
}

local function check(parent, key, y)
    local c = S.Check(parent, 26)
    c:SetPoint("TOPLEFT", 0, y)
    local icon = S.Icon(parent, 18)
    icon:SetPoint("LEFT", c, "RIGHT", 2, 0)
    icon:Set(PREF_ICONS[key])
    local t = S.Text(parent, 12)
    t:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    t:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    t:SetText(L["P_" .. key])
    c:SetScript("OnClick", function() ns.SetPref(key, not ns.view.prefs[key]) end)
    ui.checks[key] = c
    return c
end

-- A row: label, then - value +. `step`, `min`, `max`; `fmt` shows the value.
local function stepper(parent, key, y, step, min, max, fmt)
    local minus = S.Button(parent, 28, 28)
    minus:SetPoint("TOPLEFT", 0, y)
    minus:SetText("-")
    local plus = S.Button(parent, 28, 28)
    plus:SetPoint("TOPRIGHT", 0, y)
    plus:SetText("+")
    local value = S.Text(parent, 13)
    value:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    value:SetPoint("RIGHT", plus, "LEFT", -4, 0)
    value:SetJustifyH("CENTER")
    local function get()
        if key == "target" and ns.view.state then return ns.Target(ns.view.state, ns.view.prefs) end
        return ns.view.prefs and ns.view.prefs[key] or ns.DEFAULTS[key]
    end
    minus:SetScript("OnClick", function() ns.SetPref(key, math.max(min, get() - step)) end)
    plus:SetScript("OnClick", function() ns.SetPref(key, math.min(max, get() + step)) end)
    ui[key] = { minus = minus, plus = plus, value = value, fmt = fmt, get = get }
end

local function buildSide(side)
    local y = 0
    header(side, L.SIDE_MODE, y); y = y - 16
    for i, m in ipairs({ "money", "balance", "speed" }) do
        local b = S.Button(side, (SIDE - 8) / 3, 30)
        b:SetPoint("TOPLEFT", (i - 1) * ((SIDE - 8) / 3 + 4), y)
        b:SetText(L["MODE_" .. m])
        b:SetScript("OnClick", function() ns.SetPref("mode", m) end)
        b:SetScript("OnLeave", function(self) S.SetBorder(self, ns.view.prefs.mode == m and S.Accent() or S.BORDER) end)
        ui.modes[m] = b
    end
    y = y - 38
    header(side, L.SIDE_TARGET, y); y = y - 16
    stepper(side, "target", y, 5, 1, 300, function(v) return tostring(v) end); y = y - 36
    header(side, L.SIDE_FROM, y); y = y - 14
    for _, k in ipairs({ "useBags", "useBank", "buyAH", "buyVendor" }) do check(side, k, y); y = y - 26 end
    y = y - 4
    header(side, L.SIDE_LEARN, y); y = y - 14
    for _, k in ipairs({ "buyRecipes", "trainer" }) do check(side, k, y); y = y - 26 end
    y = y - 4
    header(side, L.SIDE_SELL, y); y = y - 14
    for _, k in ipairs({ "sellAH", "neutral" }) do check(side, k, y); y = y - 26 end
    local cl = S.Text(side, 11, S.MUTED); cl:SetPoint("TOPLEFT", 0, y - 2); cl:SetText(L.P_chance); y = y - 16
    stepper(side, "chance", y, 5, 30, 100, function(v) return v .. "%" end); y = y - 32
    local ml = S.Text(side, 11, S.MUTED); ml:SetPoint("TOPLEFT", 0, y - 2); ml:SetText(L.P_maxSell); y = y - 16
    stepper(side, "maxSell", y, 1, 1, 40, function(v) return L.UNITS:format(v) end); y = y - 32
    check(side, "freshOnly", y); y = y - 32

    local reset = S.Button(side, SIDE, 28)
    reset:SetPoint("BOTTOMLEFT", 0, 0)
    reset:SetText(L.RESET)
    reset:SetScript("OnClick", function() ns.ResetPrefs() end)
    ui.reset = reset
    local toast = CreateFrame("Frame", nil, side)
    toast:SetPoint("TOPLEFT", 0, y)
    toast:SetPoint("BOTTOMRIGHT", reset, "TOPRIGHT", 0, 6)
    S.Box(toast, { 0.05, 0.05, 0.06, 1 }, { 0.17, 0.17, 0.19, 1 })
    ui.toast = S.Text(toast, 11, S.MUTED)
    ui.toast:SetPoint("TOPLEFT", 6, -6)
    ui.toast:SetPoint("BOTTOMRIGHT", -6, 6)
    ui.toast:SetJustifyV("TOP")
end

local function refreshSide()
    local P = ns.view.prefs or ns.Prefs()
    for k, c in pairs(ui.checks) do c:SetChecked(P[k] and true or false) end
    for m, b in pairs(ui.modes) do
        S.SetBorder(b, P.mode == m and S.Accent() or S.BORDER)
        b.text:SetTextColor(unpack(P.mode == m and S.Accent() or S.TEXT))
    end
    for _, k in ipairs({ "target", "chance", "maxSell" }) do
        local s = ui[k]
        s.value:SetText(s.fmt(s.get()))
    end
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
    S.Box(b, S.PANEL, { 0.17, 0.17, 0.19, 1 })
    b.stripe = S.Tex(b, "ARTWORK", { 1, 1, 1, 1 })
    b.stripe:SetPoint("TOPLEFT", 1, -1)
    b.stripe:SetPoint("BOTTOMLEFT", 1, 1)
    b.stripe:SetWidth(3)
    b.icon = S.Icon(b, 28)
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
        local ic = S.Icon(b, 16)
        ic:SetPoint("BOTTOMLEFT", 10 + (k - 1) * 19, 8)
        b.strip[k] = ic
    end
    b.more = S.Text(b, 9, S.MUTED)
    b.more:SetPoint("BOTTOMLEFT", 10 + 4 * 19, 11)
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
    return 8 + col * COL_W, -(8 + row * ROW_H)
end

local function fillNode(b, n)
    local kc = (n.kind == "craft" and n.segs) and segColor(n.segs[1].color) or ns.STOPS[n.kind]
    b.stripe:SetVertexColor(kc[1], kc[2], kc[3], 1)
    b.icon:Set(stopIcon(n))
    b.kind:SetText(color(kc) .. n.index .. ". " .. (L["KIND_" .. n.kind] or n.kind):upper() .. "|r")
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
            local t = b.bar[k] or S.Tex(b, "OVERLAY")
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
    S.SetBorder(b, n.shownSelected and S.Accent() or { 0.17, 0.17, 0.19, 1 })
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
                S.SetBorder(b, (selected == i) and S.Accent() or { 0.17, 0.17, 0.19, 1 })
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
    local h = 16 + rows * ROW_H
    child:SetSize(W - SIDE - 40, h)
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
    r.icon = S.Icon(r, 20)
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
                         color(x.profit >= 0 and GOOD or BAD) .. ns.Money(x.profit, true) .. "|r",
                         x.pay and L.PAY_AT:format(x.pay) or (x.src == "text" and L.WHERE_text or L.PAY_NEVER) } }
        end
    end
    return rows
end

local function makeListRow(r)
    r.icon = S.Icon(r, 22)
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
    r.text:SetPoint("RIGHT", r, "RIGHT", -(spec[2][2] + 66), 0)
    for k = 1, 5 do
        local t = r.cols[k]
        t:ClearAllPoints()
        t:SetPoint("RIGHT", r, "RIGHT", -spec[k + 1][2], 0)
        t:SetWidth(spec[k + 1][2] == 6 and 80 or 74)
        t:SetText(e.cols[k] or "")
    end
end

-- ---------- building and refreshing ----------

local function kpi(parent, i, key, icon)
    local w = (W - SIDE - 40 - 4 * 6) / 5
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w, 40)
    f:SetPoint("TOPLEFT", (i - 1) * (w + 6), 0)
    S.Box(f, S.PANEL)
    local ic = S.Icon(f, 12)
    ic:SetPoint("TOPLEFT", 6, -5)
    ic:Set(icon)
    local t = S.Text(f, 9, S.MUTED)
    t:SetPoint("LEFT", ic, "RIGHT", 4, 0)
    t:SetText(L[key]:upper())
    f.value = S.Text(f, 13)
    f.value:SetPoint("BOTTOMLEFT", 6, 5)
    f.value:SetPoint("RIGHT", -4, 0)
    f.value:SetWordWrap(false)
    return f
end

local function build()
    frame = S.Window("GulliCraftProfitFrame", L.TITLE, W, H)
    local body = frame.body
    ui.frame = frame

    -- professions on top, prices on the right
    ui.profBar = CreateFrame("Frame", nil, body)
    ui.profBar:SetPoint("TOPLEFT", 0, 0)
    ui.profBar:SetSize(W - SIDE - 40, 28)
    ui.age = S.Text(body, 11, S.MUTED)
    ui.age:SetPoint("TOPRIGHT", 0, -8)
    ui.age:SetJustifyH("RIGHT")

    local tabsHolder = CreateFrame("Frame", nil, body)
    tabsHolder:SetPoint("TOPLEFT", 0, -34)
    tabsHolder:SetSize(W - SIDE - 30, 30)
    local labels = { L.TAB_ROUTE, L.TAB_CRAFTS, L.TAB_ITEMS, L.TAB_RECIPES }
    ui.tabs = S.Tabs(tabsHolder, labels, 158, function(i) tab = i; if ns.Refresh then ns.Refresh() end end)

    local main = CreateFrame("Frame", nil, body)
    main:SetPoint("TOPLEFT", 0, -70)
    main:SetPoint("BOTTOMRIGHT", -(SIDE + 14), 0)
    ui.main = main
    local side = CreateFrame("Frame", nil, body)
    side:SetPoint("TOPRIGHT", 0, -34)
    side:SetPoint("BOTTOMRIGHT", 0, 0)
    side:SetWidth(SIDE)
    buildSide(side)

    -- route tab
    local route = CreateFrame("Frame", nil, main)
    route:SetAllPoints()
    ui.route = route
    ui.kpis = {
        kpi(route, 1, "K_BUY", "Interface\\Icons\\INV_Misc_Coin_02"),
        kpi(route, 2, "K_OWN", "Interface\\Icons\\INV_Misc_Bag_08"),
        kpi(route, 3, "K_INCOME", "Interface\\Icons\\INV_Misc_Coin_17"),
        kpi(route, 4, "K_NET", "Interface\\Icons\\INV_Misc_Coin_01"),
        kpi(route, 5, "K_CRAFTS", "Interface\\Icons\\Trade_BlackSmithing"),
    }
    ui.warn = S.Text(route, 11, GOLD)
    ui.warn:SetPoint("TOPLEFT", 0, -46)
    ui.warn:SetPoint("RIGHT", 0, 0)
    local gbox = CreateFrame("Frame", nil, route)
    gbox:SetPoint("TOPLEFT", 0, -62)
    gbox:SetPoint("RIGHT", -12, 0)
    gbox:SetHeight(290)
    S.Box(gbox, { 0.04, 0.04, 0.05, 1 })
    ui.graph = S.Scroll(gbox)
    ui.graph:SetAllPoints()
    ui.skillFrom = S.Text(route, 10, S.MUTED)
    ui.skillFrom:SetPoint("TOPLEFT", gbox, "BOTTOMLEFT", 0, -6)
    ui.skillTo = S.Text(route, 10, S.MUTED)
    ui.skillTo:SetPoint("TOPRIGHT", gbox, "BOTTOMRIGHT", 0, -6)
    ui.skillTo:SetJustifyH("RIGHT")
    local bar = CreateFrame("Frame", nil, route)
    bar:SetPoint("TOPLEFT", gbox, "BOTTOMLEFT", 0, -20)
    bar:SetPoint("TOPRIGHT", gbox, "BOTTOMRIGHT", 0, -20)
    bar:SetHeight(14)
    S.Box(bar, { 0.04, 0.04, 0.05, 1 })
    ui.bar, ui.barParts = bar, {}
    ui.detailTitle = S.Text(route, 12)
    ui.detailTitle:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -8)
    ui.detailTitle:SetPoint("RIGHT", -12, 0)
    ui.detail = S.List(route, 24, makeLine, fillLine)
    ui.detail:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -26)
    ui.detail:SetPoint("BOTTOMRIGHT", -12, 0)

    -- list tabs
    local list = CreateFrame("Frame", nil, main)
    list:SetAllPoints()
    ui.listFrame = list
    ui.listHead = {}
    for k = 1, 6 do
        local t = S.Text(list, 10, S.MUTED)
        ui.listHead[k] = t
    end
    ui.list = S.List(list, 30, makeListRow, fillListRow)
    ui.list:SetPoint("TOPLEFT", 0, -20)
    ui.list:SetPoint("BOTTOMRIGHT", -12, 0)

    ui.empty = S.Note(main, 13)
    ui.empty:SetPoint("TOPLEFT", 4, -8)
    ui.empty:SetPoint("RIGHT", -16, 0)

    frame:SetScript("OnShow", function() ns.Recalc(false); ns.Refresh() end)
    ui.tabs:Select(1)
end

local function refreshProfessions()
    local profs = ns.Professions()
    local x = 0
    for i, p in ipairs(profs) do
        local b = ui.profs[i]
        if not b then
            b = S.Button(ui.profBar, 150, 26)
            b.text:ClearAllPoints()
            b.text:SetPoint("LEFT", 6, 0)
            b.text:SetPoint("RIGHT", -6, 0)
            b.text:SetWordWrap(false)
            ui.profs[i] = b
        end
        b:ClearAllPoints()
        b:SetPoint("LEFT", x, 0)
        b:SetText(p.name .. " " .. color(S.MUTED) .. p.skill .. "/" .. p.cap .. "|r")
        b:SetScript("OnClick", function() ns.SetProfession(p.name) end)
        S.SetBorder(b, ns.char.current == p.name and S.Accent() or S.BORDER)
        b:Show()
        x = x + 154
    end
    for i = #profs + 1, #ui.profs do ui.profs[i]:Hide() end
end

local function refreshRoute()
    local v = ns.view
    local plan = v.plan
    ui.kpis[1].value:SetText(ns.Money(plan.spend))
    ui.kpis[2].value:SetText(ns.Money(plan.own))
    ui.kpis[3].value:SetText(ns.Money(plan.income))
    ui.kpis[4].value:SetText(color(plan.net >= 0 and GOOD or BAD) .. ns.Money(plan.net, true) .. "|r")
    ui.kpis[5].value:SetText(tostring(ns.Ceil(plan.crafts)))
    local w = plan.warn
    ui.warn:SetText(w and L[w[1]]:format(w[2], w[3]) or "")
    if selected > #v.route then selected = 1 end
    drawGraph()
    -- the skill bar: one colour per recipe stretch, a mark at each rank cap
    local span = math.max(1, plan.target - v.state.skill)
    local width = math.max(1, ui.bar:GetWidth() - 2)
    for _, t in ipairs(ui.barParts) do t:Hide() end
    local x, k = 1, 0
    for _, sg in ipairs(plan.segs) do
        k = k + 1
        local t = ui.barParts[k] or S.Tex(ui.bar, "ARTWORK")
        ui.barParts[k] = t
        local c = segColor(sg.color)
        local wd = math.max(1, width * (sg.to - sg.from) / span)
        t:SetVertexColor(c[1], c[2], c[3], 1)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", x, -1)
        t:SetSize(wd, 12)
        t:Show()
        x = x + wd
    end
    ui.skillFrom:SetText(L.SKILL_FROM:format(v.state.skill))
    local guess = false
    for _, r in pairs(v.state.recipes) do if r.guess and r.learned then guess = true end end
    ui.skillTo:SetText((guess and (L.GUESS .. "  ") or "") .. (plan.reached < plan.target
        and L.SKILL_SHORT:format(plan.reached, plan.target) or L.SKILL_TARGET:format(plan.target)))
    local n = v.route[selected]
    ui.detailTitle:SetText(n and (n.index .. ". " .. (L["KIND_" .. n.kind] or "") .. ": " .. stopTitle(n)) or "")
    ui.detail:SetData(detailRows(n))
end

local function refreshList()
    local spec = LISTS[tab - 1]
    for k = 1, 6 do
        local t = ui.listHead[k]
        t:ClearAllPoints()
        if k == 1 then t:SetPoint("TOPLEFT", 32, -4) else t:SetPoint("TOPRIGHT", -(spec[k][2] + 12), -4) end
        t:SetText(L[spec[k][1]]:upper())
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
    if not ns.HasAuctionator() then ui.age:SetText(color(GOLD) .. L.NO_AUCTIONATOR .. "|r")
    elseif age then ui.age:SetText(L.PRICES_AGE:format(age < 1 and L.AGE_TODAY or L.AGE_DAYS:format(math.floor(age))))
    else ui.age:SetText("") end
    local has = v.state ~= nil and v.plan ~= nil
    ui.empty:SetText(has and "" or L.NO_PROF)
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
    if not frame then build() end
    frame:SetShown(not frame:IsShown())
    if frame:IsShown() then ns.Recalc(false); ns.Refresh() end
end
