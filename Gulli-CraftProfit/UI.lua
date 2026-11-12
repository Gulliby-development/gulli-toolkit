-- The window: professions and tabs on top, the settings column on the right, and on the left
-- the levelling route as a graph of stops (or the crafts, items and recipes lists). It only
-- shows what Core.lua planned; every setting goes through ns.SetPref, which rebuilds the plan.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local W, H = S.WIDE_W, S.DOCK_H
local SIDE = 264
local NODE_W, NODE_H, COL_W, ROW_H = 112, 66, 120, 74
-- Rows of stops the graph shows before **All stops** opens the rest.
local SHOWN_ROWS = 2
local STRIP = 3 -- item icons along the bottom of a stop
local MAIN = W - 2 * S.PAD - SIDE - S.GAP
local GRAPH_W = MAIN - 2 * S.INSET - 10
-- As many stops in a row as the graph is wide.
local PER_ROW = math.max(2, math.floor((GRAPH_W - 8 + COL_W - NODE_W) / COL_W))

-- Icons from the game for the stops; a craft stop shows the profession's own icon.
ns.STOP_ICONS = {
    bank = "Interface\\Minimap\\Tracking\\Banker", ah = "Interface\\Minimap\\Tracking\\Auctioneer",
    vendor = "Interface\\Icons\\INV_Misc_Bag_11", trainer = "Interface\\Icons\\INV_Misc_Book_11",
    craft = "Interface\\Icons\\Trade_Tailoring", sell = "Interface\\Icons\\INV_Misc_Coin_02",
    mail = "Interface\\Icons\\INV_Letter_15", gather = "Interface\\Icons\\Trade_Herbalism",
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
-- count settings whose stepper ends in "no limit"
local UNLIMITED = { maxSell = true, maxBuy = true }
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
    elseif UNLIMITED[key] then
        -- one step past the top is "no limit", saved as 0
        local top, show = max, fmt
        get = function() local v = pref(key) or ns.DEFAULTS[key]; return v == 0 and top + step or v end
        set = function(v) ns.SetPref(key, v > top and 0 or v) end
        fmt = function(v) return v > top and L.NO_LIMIT or show(v) end
        max = top + step
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

    local c1, h1 = rowsCard(col, L.SIDE_FROM, { sw("useBags"), sw("useBank"), sw("useMail"), sw("useAlts"), sw("buyAH"),
        stepRow(col, "maxBuy", 10, 10, 200, function(v) return L.UNITS:format(v) end), sw("buyVendor") })
    st:Add(c1, h1)
    local c2, h2 = rowsCard(col, L.SIDE_LEARN, { sw("buyRecipes"), sw("trainer") })
    st:Add(c2, h2)
    local c3, h3 = rowsCard(col, L.SIDE_SELL, { sw("sellAH"), sw("neutral"), sw("freshOnly"),
        stepRow(col, "chance", 5, 30, 100, function(v) return v .. "%" end),
        stepRow(col, "maxSell", 1, 1, 40, function(v) return L.UNITS:format(v) end) })
    st:Add(c3, h3)

    -- the run log: what the plan promised against what the run really did
    local log = S.Card(col, L.SIDE_LOG)
    ui.logBtn = S.Button(log.body, inner - 2 * S.INSET, 30)
    ui.logBtn:SetPoint("TOPLEFT")
    ui.logBtn:SetScript("OnClick", function()
        if ns.char.run then
            local e = ns.FinishRun()
            if e then ns.Print(ns.LogLine(e)) end
        else
            ns.StartRun()
        end
        ns.Refresh()
    end)
    ui.logText = S.Text(log.body, 11, S.MUTED)
    ui.logText:SetPoint("TOPLEFT", 0, -38)
    ui.logText:SetPoint("RIGHT", 0, 0)
    ui.logText:SetJustifyH("LEFT")
    ui.logText:SetWordWrap(true)
    st:Add(log, log:Fit(38 + 4 * 30))
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
    if ui.logBtn and ns.char then
        local run = ns.char.run
        ui.logBtn:SetText(run and L.LOG_FINISH or L.LOG_START)
        local lines = {}
        if run then lines[#lines + 1] = L.LOG_RUNNING:format(run.from, run.to, ns.Money(run.net, true)) end
        for i = 1, math.min(3, #ns.char.log) do lines[#lines + 1] = ns.LogLine(ns.char.log[i]) end
        ui.logText:SetText(#lines > 0 and table.concat(lines, "\n") or L.LOG_EMPTY)
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
    -- a run crafts one recipe: its item says more than the profession's icon
    if n.segs then
        local r = ns.view.state.recipes[n.segs[1].rid]
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

-- The recipe of a craft stop (one run is one recipe), with "+n" when it holds more.
local function runName(n)
    local ids, seen = {}, {}
    for _, sg in ipairs(n.segs) do if not seen[sg.rid] then seen[sg.rid] = true; ids[#ids + 1] = sg.rid end end
    local name = ns.view.state.recipes[ids[1]].name
    return #ids > 1 and (name .. " +" .. (#ids - 1)) or name
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
    b.title:SetJustifyV("TOP")
    b.title:SetWordWrap(false)
    b.strip = {}
    for k = 1, STRIP do
        local ic = S.ItemIcon(b, 16)
        ic:SetPoint("BOTTOMLEFT", 10 + (k - 1) * 18, 8)
        b.strip[k] = ic
    end
    b.more = S.Text(b, 9, S.MUTED)
    b.more:SetPoint("BOTTOMLEFT", 10 + STRIP * 18, 11)
    b.money = S.Text(b, 10, S.MUTED)
    b.money:SetPoint("BOTTOMRIGHT", -6, 7)
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
    -- a craft stop: the skill it covers on top, the recipe below on up to two lines, the crafts
    -- at the bottom; the item's icon is the stop's, so it needs no icons along the bottom
    local kind = n.index .. ". " .. (n.segs and (n.from .. "-" .. n.to) or (L["KIND_" .. n.kind] or n.kind))
    b.kind:SetText(color(kc) .. kind .. "|r")
    b.title:SetWordWrap(n.segs and true or false)
    b.title:SetMaxLines(n.segs and 2 or 1)
    b.title:SetHeight(n.segs and 26 or 13)
    b.title:SetText(n.segs and runName(n) or stopTitle(n))
    local icons = {}
    if not n.segs then
        for _, l in ipairs(n.lines or {}) do
            local t, q = lineIcon(l)
            -- no counts on the small icons: they do not fit; the list under the graph has them
            icons[#icons + 1] = { t, nil, q }
        end
    end
    for k = 1, STRIP do
        local ic = icons[k]
        if ic then b.strip[k]:Set(ic[1], ic[2], ic[3]) else b.strip[k]:Hide() end
    end
    b.more:SetText(#icons > STRIP and ("+" .. (#icons - STRIP)) or "")
    if n.segs then b.money:SetText(color(S.TEXT) .. L.CRAFTS_N:format(n.crafts) .. "|r")
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
    local rows = math.ceil(#route / PER_ROW)
    local open = ui.expanded or rows <= SHOWN_ROWS
    local shown = open and #route or SHOWN_ROWS * PER_ROW
    for i, n in ipairs(route) do
        local b = ui.nodes[i] or makeNode(child, i)
        ui.nodes[i] = b
        local x, y = nodePos(i)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", x, y)
        fillNode(b, n)
        b:SetShown(i <= shown)
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
        l:SetShown(i <= shown)
    end
    for i = #route + 1, #ui.lines do if ui.lines[i] then ui.lines[i]:Hide() end end
    -- the button shows how many stops wait below; open, it closes the list of the stop again
    ui.expand:SetShown(rows > SHOWN_ROWS)
    ui.money:ClearAllPoints()
    if rows > SHOWN_ROWS then ui.money:SetPoint("RIGHT", ui.expand, "LEFT", -8, 0)
    else ui.money:SetPoint("TOPRIGHT", ui.graphCard, "TOPRIGHT", -S.INSET, -13) end
    ui.expand:SetText(ui.expanded and L.GRAPH_LESS or L.GRAPH_ALL:format(#route))
    local h = 8 + (open and rows or SHOWN_ROWS) * ROW_H
    child:SetSize(GRAPH_W, h)
    ui.graph:Update(h)
end

local SRC = { bank = "SRC_bank", ah = "SRC_ah", vendor = "SRC_vendor", trainer = "SRC_trainer", prep = "SRC_prep",
              sellah = "SRC_sellah", sellv = "SRC_sellv", mail = "SRC_mail", alts = "SRC_alts", gather = "SRC_gather" }

-- The rows under the graph for the chosen stop.
local function detailRows(n)
    local rows = {}
    if not n then return rows end
    local st = ns.view.state
    -- a craft: the recipe with its skill stretch, then each reagent on its own row
    for _, sg in ipairs(n.segs or {}) do
        local r = st.recipes[sg.rid]
        rows[#rows + 1] = { rid = sg.rid, icon = r.out and ns.ItemIcon(r.out), q = r.out and (st.items[r.out] or {}).quality,
                            text = color(segColor(sg.color)) .. r.name .. "|r x" .. ns.Ceil(sg.n),
                            mid = sg.from .. " - " .. sg.to, right = L.CRAFTS_N:format(ns.Ceil(sg.n)) }
        local ids = {}
        for id in pairs(r.r) do ids[#ids + 1] = id end
        table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
        for _, id in ipairs(ids) do
            local it = st.items[id] or {}
            local k = ns.Ceil(r.r[id] * sg.n)
            rows[#rows + 1] = { id = id, icon = ns.ItemIcon(id), q = it.quality, text = "   " .. (it.name or tostring(id)) .. " x" .. k,
                                mid = it.gather and L.SRC_gather or L.REAGENT, right = "" }
        end
    end
    for _, l in ipairs(n.lines or {}) do
        local icon, q = lineIcon(l)
        local name = l.rank and L.STOP_RANK:format(l.rank) or l.name
        local mid = l.over and L.SRC_OVER:format(ns.view.prefs.maxSell) or L[SRC[l.src] or ""] or ""
        if l.src == "alts" then mid = L.SRC_alts:format(l.who or "?") end
        if l.id and (st.items[l.id] or {}).ladder and l.src == "ah" then mid = L.SRC_LADDER end
        rows[#rows + 1] = { id = l.id, rid = l.src == "prep" and l.recipe or nil, icon = icon, n = l.n, q = q,
                            text = name .. " x" .. l.n, mid = mid,
                            right = l.price and ns.Money(l.price * l.n) or "" }
    end
    return rows
end

local function makeLine(r)
    -- a click on a recipe opens it in the profession window; a right-click on a reagent marks it
    -- as gathered (the plan stops buying it)
    r.click = CreateFrame("Button", nil, r)
    r.click:SetAllPoints()
    r.click:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.click:SetScript("OnClick", function(_, button)
        local e = r.entry
        if not e then return end
        if button == "RightButton" and e.id then
            ns.SetGather(e.id, not ns.db.gather[e.id])
        elseif e.rid then
            if not ns.OpenRecipe(e.rid) then ns.Print(L.OPEN_PROF) end
        end
    end)
    r.click:SetScript("OnEnter", function(self)
        local e = r.entry
        if not e or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if e.id then
            GameTooltip:SetItemByID(e.id)
            GameTooltip:AddLine(ns.db.gather[e.id] and L.GATHER_TIP_OFF or L.GATHER_TIP, 0.6, 0.6, 0.6, true)
        elseif e.rid then
            GameTooltip:SetText(L.RECIPE_TIP, 1, 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    r.click:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    r.entry = false
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
    r.entry = e
    if e.icon then r.icon:Set(e.icon, e.n, e.q) else r.icon:Hide() end
    r.text:SetText(e.text)
    r.mid:SetText(e.mid or "")
    r.right:SetText(e.right or "")
end

-- ---------- the list tabs ----------

-- Columns: { header key, width }, the name column first (it takes the room left), the others
-- from the right edge. `sort`: the column a tab sorts by at first, highest first.
local LISTS = {
    { cols = { { "C_RECIPE" }, { "C_COST", 62 }, { "C_VALUE", 62 }, { "C_WHERE", 54 }, { "C_PROFIT", 66 }, { "C_CAN", 30 } }, sort = 5 },
    { cols = { { "I_ITEM" }, { "I_BAGS", 34 }, { "I_BANK", 34 }, { "I_BEST", 110 }, { "I_EACH", 62 }, { "I_TOTAL", 66 } }, sort = 6 },
    { cols = { { "C_RECIPE" }, { "R_WHERE", 84 }, { "R_PRICE", 60 }, { "R_SKILL", 34 }, { "C_PROFIT", 66 }, { "R_PAY", 64 } }, sort = 5 },
}
local COL_GAP = 6
-- x of each column's right edge, from the row's right edge
local function colRight(spec, k)
    local x = 6
    for j = #spec.cols, k + 1, -1 do x = x + spec.cols[j][2] + COL_GAP end
    return x
end
ns.LISTS = LISTS

-- Where a recipe comes from, in the game's own words: the label before the first colon of the
-- source text ("Vendor", "Drop", ...), without its colour codes.
function ns.SourceLabel(text)
    if not text or text == "" then return nil end
    local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|n", "\n")
    local label = plain:match("^%s*([^:\n]+):") or plain:match("^%s*([^\n]+)")
    return label and label:match("^%s*(.-)%s*$")
end

-- The tooltip of a list row: the reagents with their cost, then where the recipe comes from.
local function recipeTip(r)
    local st, P = ns.view.state, ns.view.prefs
    local tip = { { r.name, 1, 1, 1 } }
    local known = {}
    for rid, x in pairs(st.recipes) do if x.learned then known[rid] = true end end
    local stock = ns.Stock(st, P)
    local ids = {}
    for id in pairs(r.r) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
    for _, id in ipairs(ids) do
        local it = st.items[id] or {}
        local each = ns.UnitCost(st, P, stock, known, id)
        tip[#tip + 1] = { (it.name or tostring(id)) .. " x" .. r.r[id], each < math.huge and ns.Money(each * r.r[id]) or L.NO_PRICE }
    end
    if r.src and r.src.text then tip[#tip + 1] = { (r.src.text:gsub("|n", "\n")), nil, nil, nil, true } end
    return tip
end

local function listRows(which)
    local st, P = ns.view.state, ns.view.prefs
    local rows = {}
    if not st then return rows end
    if which == 2 then
        for _, x in ipairs(ns.Crafts(st, P)) do
            local r = st.recipes[x.recipe]
            -- the name in the recipe's colour, as in the game's profession window
            local c = x.color and segColor(x.color) or S.TEXT
            rows[#rows + 1] = { icon = r.out and ns.ItemIcon(r.out), q = r.out and (st.items[r.out] or {}).quality,
                text = color(c) .. x.name .. "|r" .. (x.stale and (" " .. color(GOLD) .. L.STALE .. "|r") or ""),
                cols = { ns.Money(x.cost), ns.Money(x.value), L["HOW_" .. x.how],
                         color(x.profit >= 0 and GOOD or BAD) .. ns.Money(x.profit, true) .. "|r",
                         x.can > 0 and ("x" .. x.can) or "-" },
                keys = { x.name, x.cost, x.value, x.how, x.profit, x.can }, tip = recipeTip(r) }
        end
    elseif which == 3 then
        for _, x in ipairs(ns.Items(st, P)) do
            rows[#rows + 1] = { icon = ns.ItemIcon(x.id), n = x.bags + x.bank, q = (st.items[x.id] or {}).quality, text = x.name,
                cols = { tostring(x.bags), tostring(x.bank),
                         L["HOW_" .. x.how] .. (x.recipeName and (": " .. x.recipeName) or ""),
                         ns.Money(x.each), ns.Money(x.total) },
                keys = { x.name, x.bags, x.bank, x.how, x.each, x.total } }
        end
    else
        for _, x in ipairs(ns.Recipes(st, P)) do
            local r = st.recipes[x.recipe]
            local where = (x.src == "text" and (ns.SourceLabel(x.text) or "-")) or L["WHERE_" .. x.src] or "-"
            -- an estimated vendor price gets "~"; the trainer's price is known after one visit
            local price = x.cost and ((x.est and "~" or "") .. ns.Money(x.cost)) or (x.src == "trainer" and "?" or "-")
            local tip = recipeTip(r)
            if x.who then tip[#tip + 1] = { L.TIP_VENDOR:format(table.concat(x.who, ", ")), nil, nil, nil, true } end
            if x.est then tip[#tip + 1] = { L.TIP_EST, nil, nil, nil, true } end
            if x.src == "trainer" and not x.cost then tip[#tip + 1] = { L.TIP_TRAINER, nil, nil, nil, true } end
            if x.pay then tip[#tip + 1] = { L.TIP_PAY:format(x.pay), nil, nil, nil, true } end
            rows[#rows + 1] = { icon = r.out and ns.ItemIcon(r.out) or PATTERN_ICON, text = x.name,
                cols = { where, price, x.skill and tostring(x.skill) or "-",
                         x.profit and (color(x.profit >= 0 and GOOD or BAD) .. ns.Money(x.profit, true) .. "|r") or L.NO_PRICE,
                         x.pay and L.PAY_AT:format(x.pay) or ((x.profit and x.cost) and L.PAY_NEVER or "-") },
                keys = { x.name, where, x.cost, x.skill, x.profit, x.pay }, tip = tip }
        end
    end
    -- the chosen column, highest first (names A to Z); rows without a value go last
    local sort = ui.sort and ui.sort[which] or { col = LISTS[which - 1].sort, desc = true }
    local k = sort.col
    table.sort(rows, function(a, b)
        local x, y = a.keys[k], b.keys[k]
        if x == y then return tostring(a.keys[1]) < tostring(b.keys[1]) end
        if x == nil then return false end
        if y == nil then return true end
        if type(x) ~= type(y) then x, y = tostring(x), tostring(y) end
        if type(x) == "string" then
            if sort.desc then return x < y end
            return x > y
        end
        if sort.desc then return x > y end
        return x < y
    end)
    return rows
end

local function showTip(r)
    if not GameTooltip or not r.tip then return end
    GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
    for i, l in ipairs(r.tip) do
        if i == 1 then GameTooltip:SetText(l[1], l[2], l[3], l[4])
        elseif l[5] then GameTooltip:AddLine(l[1], 0.8, 0.8, 0.8, true)
        else GameTooltip:AddDoubleLine(l[1], l[2], 0.8, 0.8, 0.8, 1, 1, 1) end
    end
    GameTooltip:Show()
end

local function makeListRow(r)
    r.icon = S.ItemIcon(r, 22)
    r.icon:SetPoint("LEFT", 4, 0)
    r.cols = {}
    for k = 2, 6 do
        local t = S.Text(r, 11)
        t:SetJustifyH("RIGHT")
        t:SetWordWrap(false)
        r.cols[k - 1] = t
    end
    r.text = S.Text(r, 12)
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.text:SetWordWrap(false)
    r:EnableMouse(true)
    r:SetScript("OnEnter", function(self) showTip(self) end)
    r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

local function fillListRow(r, e)
    local spec = LISTS[tab - 1]
    if e.icon then r.icon:Set(e.icon, e.n, e.q) else r.icon:Hide() end
    r.text:SetText(e.text)
    r.text:SetPoint("RIGHT", r, "RIGHT", -(colRight(spec, 2) + spec.cols[2][2] + COL_GAP), 0)
    for k = 1, 5 do
        local t = r.cols[k]
        t:ClearAllPoints()
        t:SetPoint("RIGHT", r, "RIGHT", -colRight(spec, k + 1), 0)
        t:SetWidth(spec.cols[k + 1][2])
        t:SetText(e.cols[k] or "")
    end
    r.tip = e.tip
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
    -- the whole way to the target as runs: one chip per run, the chosen one shown below
    local chips = CreateFrame("Frame", nil, route)
    st:Add(chips, 28, 8)
    ui.chipBox, ui.chips = chips, {}
    ui.chipNote = S.Text(chips, 11, S.MUTED)
    ui.chipNote:SetPoint("LEFT", 2, 0)
    ui.chipNote:SetPoint("RIGHT", 0, 0)
    ui.chipNote:SetWordWrap(false)
    local graphH = 36 + 8 + SHOWN_ROWS * ROW_H + 30 + S.INSET
    local gcard = S.Card(route, L.TAB_ROUTE)
    st:Add(gcard, graphH)
    local detailH = bodyH - top - st.y
    ui.graphCard, ui.graphH, ui.graphOpenH = gcard, graphH, graphH + S.GAP + detailH
    ui.money = gcard.hint
    ui.expand = S.FitButton(gcard, L.GRAPH_ALL:format(99), 28, 60)
    ui.expand:SetPoint("TOPRIGHT", -S.INSET, -4)
    ui.expand:SetScript("OnClick", function()
        ui.expanded = not ui.expanded
        gcard:SetHeight(ui.expanded and ui.graphOpenH or ui.graphH)
        ui.detailCard:SetShown(not ui.expanded)
        ns.Refresh()
    end)

    local graphBox = CreateFrame("Frame", nil, gcard.body)
    graphBox:SetPoint("TOPLEFT", 0, 0)
    graphBox:SetPoint("BOTTOMRIGHT", 0, 30)
    ui.unknown = S.Text(graphBox, 12, S.MUTED)
    ui.unknown:SetPoint("TOPLEFT", 8, -16)
    ui.unknown:SetPoint("RIGHT", -8, 0)
    ui.unknown:SetJustifyH("LEFT")
    ui.unknown:Hide()
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
    dcard:SetShown(not ui.expanded)
    ui.detailCard = dcard
    ui.detailTitle = dcard.title
    -- the stop's action: an Auctionator list and the lots at the auction, Make at a craft stop
    ui.act2 = S.FitButton(dcard, L.LOTS_UPDATE, 26, 60)
    ui.act2:SetPoint("TOPRIGHT", -S.INSET, -5)
    ui.act1 = S.FitButton(dcard, L.MAKE_N:format(999), 26, 60)
    ui.act1:SetPoint("RIGHT", ui.act2, "LEFT", -6, 0)
    dcard.title:SetPoint("RIGHT", ui.act1, "LEFT", -8, 0)
    ui.act1:SetScript("OnClick", function(self) if self.run then self.run() end end)
    ui.act2:SetScript("OnClick", function(self) if self.run then self.run() end end)
    ui.detail = S.List(dcard.body, 28, makeLine, fillLine)
    ui.detail:SetPoint("TOPLEFT", 0, 0)
    ui.detail:SetPoint("BOTTOMRIGHT", -10, 0)

    -- list tabs: one card with column heads and rows
    local list = S.Card(main)
    list:SetPoint("TOPLEFT", 0, -top)
    list:SetPoint("BOTTOMRIGHT", 0, 0)
    ui.listFrame = list
    -- the column heads sort the list: a click picks the column, a second click turns the order
    ui.listHead, ui.sort = {}, {}
    for k = 1, 6 do
        local h = CreateFrame("Button", nil, list.body)
        h:SetHeight(18)
        h.text = S.Text(h, 10, S.MUTED)
        h.text:SetPoint("LEFT")
        h.text:SetPoint("RIGHT")
        h.text:SetWordWrap(false)
        h:SetScript("OnClick", function()
            local cur = ui.sort[tab] or { col = LISTS[tab - 1].sort, desc = true }
            ui.sort[tab] = { col = k, desc = not (cur.col == k and cur.desc) }
            ns.Refresh()
        end)
        ui.listHead[k] = h
    end
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

-- The chips over the graph: each run of the whole way to the target, an unknown stretch in red.
-- When they do not all fit, the row shows the ones around the chosen run.
local CHIP_MIN = 92
local function refreshChips(v)
    local legs = v.legs or {}
    local n = #legs
    local fit = math.min(n, math.floor((MAIN + 4) / (CHIP_MIN + 4)))
    local cw = fit > 0 and math.floor((MAIN - (fit - 1) * 4) / fit) or 0
    local sel = v.leg or 1
    local first = math.max(1, math.min(sel - math.floor(fit / 2), n - fit + 1))
    for k = 1, math.max(#ui.chips, fit) do
        local i = first + k - 1
        local leg = k <= fit and legs[i]
        local b = ui.chips[k]
        if leg then
            if not b then
                b = S.Pill(ui.chipBox, cw, 28)
                b:SetScript("OnClick", function(self) ns.SelectLeg(self.leg) end)
                ui.chips[k] = b
            end
            b.leg = i
            b:SetSize(cw, 28)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", (k - 1) * (cw + 4), 0)
            -- each run with what it gains or loses, so the whole way reads at a glance
            local text = leg.from .. "-" .. leg.to
            if leg.unknown then text = color(BAD) .. text .. " ?|r"
            elseif leg.plan then
                local net = leg.plan.net
                text = text .. "  " .. color(net >= 0 and GOOD or BAD) .. (net < 0 and "-" or "+") .. ns.Short(net) .. "|r"
            end
            b:SetText(text)
            b:SetSelected(i == sel)
            b:Show()
        elseif b then
            b:Hide()
        end
    end
    ui.chipNote:SetText(n == 0 and (v.plan and v.plan.earn and L.LEGS_EARN or "") or "")
end

local function refreshRoute()
    local v = ns.view
    local leg = v.legs and v.legs[v.leg or 1]
    -- a later run shows its own plan; an unknown stretch has none and keeps the current one's numbers
    local plan = (leg and leg.plan and (v.leg or 1) > 1) and leg.plan or v.plan
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
    -- what is paid, what own stock is worth, what the sales bring, and the result with its sign
    ui.money:SetText(L.HINT_MONEY:format(ns.Short(plan.spend), ns.Short(plan.own), ns.Short(plan.income),
        color(plan.net >= 0 and GOOD or BAD) .. (plan.net < 0 and "-" or "+") .. ns.Short(plan.net) .. "|r"))
    refreshChips(v)
    local title = routeName(v.mode, levels, true)
    if leg and (v.leg or 1) > 1 then title = title .. "  ·  " .. leg.from .. "-" .. leg.to end
    ui.graphCard:SetTitle(title)
    ui.unknown:SetShown(leg and leg.unknown or false)
    if leg and leg.unknown then ui.unknown:SetText(L.LEG_UNKNOWN:format(leg.from, leg.to)) end
    local w = plan.warn or (plan.full and plan.full.warn)
    local warn = w and (color(GOLD) .. L[w[1]]:format(w[2], w[3]) .. "|r") or nil
    if selected > #v.route then selected = 1 end
    drawGraph()
    -- the skill bar: one colour per recipe stretch, a mark at each rank cap
    local start = (leg and (v.leg or 1) > 1) and leg.from or v.state.skill
    local span = math.max(1, plan.target - start)
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
    local unknown = leg and leg.unknown
    ui.bar:SetShown(not plan.earn and not unknown)
    ui.skillFrom:SetText(L.SKILL_FROM:format(start))
    local guess = false
    for _, r in pairs(v.state.recipes) do if r.guess and r.learned then guess = true end end
    if unknown then
        ui.skillFrom:SetText(L.SKILL_FROM:format(leg.from))
        ui.skillTo:SetText(L.SKILL_TARGET:format(leg.to))
        ui.money:SetText("")
    elseif plan.earn then
        ui.skillTo:SetText(warn or "")
    else
        local full = plan.full or plan
        local where
        if full.reached < full.target then where = L.SKILL_SHORT:format(full.reached, full.target)
        elseif full ~= plan then where = L.SKILL_ALL:format(full.target, ns.Ceil(full.crafts))
        else where = L.SKILL_TARGET:format(plan.target) end
        ui.skillTo:SetText((warn and (warn .. "  ·  ") or "") .. (guess and (L.GUESS .. "  ·  ") or "") .. where)
    end
    local n = v.route[selected]
    ui.detailCard:SetTitle(n and (n.index .. ". " .. (L["KIND_" .. n.kind] or "") .. ": " .. stopTitle(n)) or "")
    ui.detail:SetData(detailRows(n))
    ns.SetActions(n)
end

-- The buttons over the chosen stop's rows.
local function setAct(b, text, run)
    b:SetShown(text ~= nil)
    if not text then b.run = nil; return end
    b:SetText(text)
    b:SetWidth(math.max(60, math.floor((b.text:GetStringWidth() or 0) + 28)))
    b.run = run
end
function ns.SetActions(n)
    local a1, a2
    if n and n.kind == "ah" and n.title == "STOP_AH_BUY" then
        if ns.HasAuctionator() then
            a1 = { L.TO_AUCTIONATOR, function()
                local k = ns.ExportShopping(ns.view.route, L.LIST_NAME:format(ns.view.state.name or ""))
                ns.Print(k and L.LIST_DONE:format(k, L.LIST_NAME:format(ns.view.state.name or "")) or L.LIST_FAIL)
            end }
        end
        if ns.atAH then
            a2 = { L.LOTS_UPDATE, function()
                local k = ns.ScanLots(ns.view.route)
                ui.toast:SetText(L.LOTS_BUSY:format(k))
            end }
        end
    elseif n and n.kind == "craft" and n.segs then
        local rid, k = ns.NextCraft(n)
        if rid then
            a1 = { L.MAKE_N:format(k), function()
                if not ns.Craft(rid, k) then ns.Print(L.OPEN_PROF) end
            end }
            a2 = { L.OPEN_RECIPE, function() if not ns.OpenRecipe(rid) then ns.Print(L.OPEN_PROF) end end }
        end
    end
    setAct(ui.act1, a1 and a1[1], a1 and a1[2])
    setAct(ui.act2, a2 and a2[1], a2 and a2[2])
    if not a2 and a1 then
        ui.act1:ClearAllPoints()
        ui.act1:SetPoint("TOPRIGHT", -S.INSET, -5)
    else
        ui.act1:ClearAllPoints()
        ui.act1:SetPoint("RIGHT", ui.act2, "LEFT", -6, 0)
    end
end
function ns.Toast(text) if ui.toast then ui.toast:SetText(text) end end

local function refreshList()
    local spec = LISTS[tab - 1]
    local sort = ui.sort[tab] or { col = spec.sort, desc = true }
    for k = 1, 6 do
        local h = ui.listHead[k]
        h:ClearAllPoints()
        if k == 1 then
            h:SetPoint("TOPLEFT", 34, 0)
            h:SetWidth(120)
            h.text:SetJustifyH("LEFT")
        else
            -- the scroll bar takes 10 at the right of the rows
            h:SetPoint("TOPRIGHT", -(colRight(spec, k) + 10), 0)
            h:SetWidth(spec.cols[k][2])
            h.text:SetJustifyH("RIGHT")
        end
        -- the sorted column in the accent colour
        local on = sort.col == k
        h.text:SetText((on and color(S.Accent()) or "") .. L[spec.cols[k][1]] .. (on and "|r" or ""))
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

-- One line of the run log: the skill reached and the money, planned against real.
function ns.LogLine(e)
    local real = e.real or 0
    return L.LOG_LINE:format(e.prof or "", e.from or 0, e.skill or e.to or 0, ns.Money(e.net or 0, true),
        color(real >= (e.net or 0) - 100 and GOOD or BAD) .. ns.Money(real, true) .. "|r")
end

-- The item tooltip: how many of it the chosen run needs.
local function tooltipLine(tip, id)
    local v = ns.view
    if not id or not v or not v.route or not v.state or #v.route == 0 then return end
    local n = ns.RunNeeds(v.state, v.route)[id]
    if n and n > 0 then tip:AddLine(L.TOOLTIP_NEED:format(n), 0.6, 0.82, 1) end
end
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tip, data)
        if tip == GameTooltip or tip == ItemRefTooltip then tooltipLine(tip, data and data.id) end
    end)
elseif GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipSetItem", function(tip)
        local _, link = tip:GetItem()
        tooltipLine(tip, link and tonumber(link:match("item:(%d+)")))
    end)
end
