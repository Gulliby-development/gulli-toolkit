-- The simulation in the window: the switch in the header, the strip under it, the conditions
-- page, the whole way with its result, and the marks on the Settings tab. It only shows what
-- Sim.lua holds; UI.lua calls in here (ns.SimBuild, ns.SimRefresh, ns.SimWay, ns.SimSettings).

local _, ns = ...
local L = ns.L
local S = ns.Skin

local SIM = ns.SIM_COLOR
local SIM_FILL = { SIM[1], SIM[2], SIM[3], 0.16 }
local SIM_EDGE = { SIM[1], SIM[2], SIM[3], 0.7 }
local STRIP_H = 34
-- the strip lies in the padding under the header and takes this much of the body
local OFF = STRIP_H - S.PAD + S.GAP
local MAIN = S.WIDE_W - 2 * S.PAD
local RUN_H, RUNS_W = 40, 372
local STARTS, ENDS = { 1, 75, 150, 225 }, { 150, 225, 300 }
local FIND_ROWS = 5

local ui, frame
local w = {} -- the simulation's own widgets
ns.simUI = w

local function hex(c) return S.Hex(c) end
local function strw(t) return tonumber((t:GetStringWidth())) or 0 end
local function money(c) return S.MoneyText(math.floor(math.abs(c) + 0.5)) end
local function signed(c)
    return hex(c >= 0 and S.GOOD or S.BAD) .. (c < 0 and "-" or "+") .. "|r" .. money(c)
end

-- ---------- the header switch and the strip ----------

local function toggle()
    if ns.sim then ns.SimStop() else ns.SimOpen() end
end

local function buildSwitch()
    local b = CreateFrame("Button", nil, frame.bar)
    S.Box(b, SIM_FILL, SIM_EDGE, 14)
    b.icon = S.IconBox(b, 20, ns.SIM_ICON)
    b.icon:SetPoint("LEFT", 4, 0)
    b.text = S.Text(b, 12)
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
    b.text:SetWordWrap(false)
    b.text:SetText(L.SIM)
    b.switch = S.Switch(b)
    b.switch:SetPoint("RIGHT", -1, 0)
    b:SetSize(math.floor(strw(b.text)) + 4 + 20 + 6 + 6 + 44 + 1, 28)
    b:SetScript("OnClick", toggle)
    b.switch:SetScript("OnClick", toggle)
    b:SetScript("OnEnter", function(self)
        if not (GameTooltip and GameTooltip.SetOwner) then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L.SIM, 1, 1, 1)
        GameTooltip:AddLine(L.SIM_TIP, 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    function b:GetText() return self.text:GetText() end
    frame:AddHeaderButton(b)
    -- the line of the prices ends before the switch
    ui.age:SetPoint("RIGHT", b, "LEFT", -8, 0)
    w.toggle = b
end

local function buildStrip()
    local s = CreateFrame("Frame", nil, frame.body)
    s:SetPoint("TOPLEFT", -S.PAD + 1, S.PAD - 1)
    s:SetPoint("TOPRIGHT", S.PAD - 1, S.PAD - 1)
    s:SetHeight(STRIP_H)
    S.Box(s, SIM_FILL, S.CLEAR)
    s.line = S.Tex(s, "ARTWORK", 0, SIM_EDGE)
    s.line:SetPoint("BOTTOMLEFT")
    s.line:SetPoint("BOTTOMRIGHT")
    s.line:SetHeight(1)
    s.icon = S.IconBox(s, 22, ns.SIM_ICON)
    s.icon:SetPoint("LEFT", S.PAD - 1, 0)
    s.head = S.Text(s, 12, nil, nil, "bold")
    s.head:SetPoint("LEFT", s.icon, "RIGHT", 8, 0)
    s.head:SetText(S.Upper(L.SIM))
    s.exit = S.FitButton(s, L.SIM_EXIT, 26, 80)
    s.exit:SetPoint("RIGHT", -(S.PAD - 1), 0)
    S.SetBorder(s.exit, SIM_EDGE)
    s.exit:SetScript("OnClick", function() ns.SimStop() end)
    s.text = S.Text(s, 12, SIM)
    s.text:SetPoint("LEFT", s.head, "RIGHT", 14, 0)
    s.text:SetPoint("RIGHT", s.exit, "LEFT", -10, 0)
    s.text:SetJustifyH("LEFT")
    s.text:SetWordWrap(false)
    s:Hide()
    w.strip = s
end

-- ---------- the conditions page ----------

local function own(line)
    local p = ns.SimOwn(line)
    if p then return L.SIM_OWN:format(p.skill or 0) end
    return line == 186 and L.SIM_SMELTING or nil
end

local function chip(parent, value, pick)
    local b = S.Pill(parent, 42, 26)
    b:SetText(tostring(value))
    b.value = value
    b:SetScript("OnClick", function() pick(value) end)
    return b
end

-- A skill row: its chips and a stepper, right to left from the row's edge.
local function skillRow(parent, label, icon, values, get, set)
    local st = S.Stepper(parent, get, set, 5, 1, ns.SIM_MAX, nil, 104)
    local row = S.SettingRow(parent, label, nil, st, 104 + #values * 46, icon)
    row.stepper, row.chips = st, {}
    -- steps of five land on round numbers (1, 5, 10 ...)
    st.minus:SetScript("OnClick", function() local v = get(); set(v <= 5 and 1 or (math.ceil(v / 5) - 1) * 5); ns.Refresh() end)
    st.plus:SetScript("OnClick", function() set(math.min(ns.SIM_MAX, (math.floor(get() / 5) + 1) * 5)); ns.Refresh() end)
    local last = st
    for k = #values, 1, -1 do
        local c = chip(row, values[k], function(v) set(v); ns.Refresh() end)
        c:SetPoint("RIGHT", last, "LEFT", last == st and -8 or -4, 0)
        row.chips[k] = c
        last = c
    end
    function row:Refresh()
        self.stepper:Refresh()
        for _, c in ipairs(self.chips) do c:SetSelected(c.value == get()) end
    end
    return row
end

local function buildSetup()
    local page = CreateFrame("Frame", nil, frame.body)
    page:SetPoint("TOPLEFT", 0, -OFF)
    page:SetPoint("BOTTOMRIGHT", 0, 0)
    page:Hide()
    w.setup = page

    -- the profession: one tile each
    local pc = S.Card(page, L.SIM_PROF)
    local tw = math.floor((MAIN - 2 * S.INSET - 2 * 8) / 3)
    w.tiles = {}
    for i, line in ipairs(ns.SIM_LINES) do
        local b = CreateFrame("Button", nil, pc.body)
        b:SetSize(tw, 44)
        b:SetPoint("TOPLEFT", ((i - 1) % 3) * (tw + 8), -math.floor((i - 1) / 3) * 50)
        S.Box(b, S.SURFACE, S.CARD_EDGE, S.R_MD)
        b.icon = S.IconBox(b, 30, ns.SIM_PROF_ICON[line])
        b.icon:SetPoint("LEFT", 8, 0)
        b.name = S.Text(b, 13, nil, nil, "bold")
        b.name:SetWordWrap(false)
        b.sub = S.Text(b, 12, S.MUTED)
        b.sub:SetPoint("BOTTOMLEFT", b.icon, "BOTTOMRIGHT", 10, 0)
        b.sub:SetPoint("RIGHT", -8, 0)
        b.sub:SetJustifyH("LEFT")
        b.sub:SetWordWrap(false)
        b.line = line
        b:SetScript("OnClick", function(self) ns.SimSet({ line = self.line }) end)
        b:SetScript("OnEnter", function(self) if not self.on then S.SetBorder(self, S.Accent()) end end)
        b:SetScript("OnLeave", function(self) if not self.on then S.SetBorder(self, S.CARD_EDGE) end end)
        function b:GetText() return self.name:GetText() end
        w.tiles[i] = b
    end
    pc:SetPoint("TOPLEFT", 0, 0)
    pc:SetPoint("TOPRIGHT", 0, 0)
    local ph = pc:Fit(3 * 50 - 6)
    pc:SetHeight(ph)

    -- the skill: where it starts, where it goes, and the recipe it is all for
    local leftW = math.floor((MAIN - S.GAP) * 0.6)
    local sc = S.Card(page, L.SIM_SKILL)
    sc:SetPoint("TOPLEFT", 0, -(ph + S.GAP))
    sc:SetWidth(leftW)
    S.rowWidth = leftW - 2 * S.INSET
    local st = S.Stack(sc.body, 0)
    w.from = skillRow(sc.body, L.SIM_FROM, "Interface\\Icons\\INV_Misc_Note_01", STARTS,
        function() return ns.sim and ns.sim.from or 1 end, function(v) ns.SimSet({ from = v }) end)
    st:Add(w.from, w.from.height)
    w.to = skillRow(sc.body, L.SIM_TO, "Interface\\Icons\\INV_Misc_Book_09", ENDS,
        function() return ns.sim and ns.sim.to or ns.SIM_MAX end, function(v) ns.SimSet({ to = v }) end)
    st:Add(w.to, w.to.height)
    local goalW = leftW - 2 * S.INSET - 38 - 130
    local box = CreateFrame("Frame", nil, sc.body)
    box:SetSize(goalW, 28)
    w.goalRow = S.SettingRow(sc.body, L.SIM_GOAL, nil, box, goalW, "Interface\\Icons\\INV_Scroll_03")
    st:Add(w.goalRow, w.goalRow.height)
    w.goalRow.line:Hide()
    w.find = S.Edit(box, goalW, 28)
    w.find:SetPoint("LEFT")
    w.find:SetJustifyH("LEFT")
    S.Placeholder(w.find, L.SIM_GOAL_FIND)
    w.find:SetScript("OnTextChanged", function() ns.SimFindRefresh() end)
    -- the chosen recipe stands in the box's place, with a cross that takes it away
    local chosen = CreateFrame("Button", nil, box)
    chosen:SetAllPoints()
    S.Box(chosen, S.INPUT, S.EDGE, S.R_MD)
    chosen.icon = S.IconBox(chosen, 20)
    chosen.icon:SetPoint("LEFT", 4, 0)
    chosen.x = S.Text(chosen, 13, S.MUTED)
    chosen.x:SetPoint("RIGHT", -8, 0)
    chosen.x:SetText("x")
    chosen.at = S.Text(chosen, 12, S.MUTED)
    chosen.at:SetPoint("RIGHT", chosen.x, "LEFT", -8, 0)
    chosen.name = S.Text(chosen, 13)
    chosen.name:SetPoint("LEFT", chosen.icon, "RIGHT", 8, 0)
    chosen.name:SetPoint("RIGHT", chosen.at, "LEFT", -6, 0)
    chosen.name:SetJustifyH("LEFT")
    chosen.name:SetWordWrap(false)
    chosen:SetScript("OnClick", function() ns.SimSet({ goal = false }) end)
    chosen:SetScript("OnEnter", function(self)
        S.SetBorder(self, S.Accent())
        if GameTooltip and GameTooltip.SetOwner then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(L.SIM_GOAL_CLEAR, 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    chosen:SetScript("OnLeave", function(self) S.SetBorder(self, S.EDGE); if GameTooltip then GameTooltip:Hide() end end)
    function chosen:GetText() return self.name:GetText() end
    w.chosen = chosen
    local sh = sc:Fit(st:Height())
    sc:SetHeight(sh)

    -- the character the simulation assumes
    local cc = S.Card(page, L.SIM_CHAR)
    cc:SetPoint("TOPLEFT", leftW + S.GAP, -(ph + S.GAP))
    cc:SetPoint("TOPRIGHT", 0, -(ph + S.GAP))
    S.rowWidth = MAIN - leftW - S.GAP - 2 * S.INSET
    local ct = S.Stack(cc.body, 0)
    w.empty = S.SwitchRow(cc.body, L.SIM_EMPTY, nil, function() return ns.sim ~= nil and ns.sim.empty end,
        function(on) ns.SimSet({ empty = on }) end, nil, "Interface\\Icons\\INV_Misc_Bag_08")
    w.empty.label:SetWordWrap(true)
    w.empty.label:SetMaxLines(2)
    ct:Add(w.empty, w.empty.height)
    for _, r in ipairs({ { L.SIM_RECIPES, L.SIM_RECIPES_D, "Interface\\Icons\\INV_Scroll_03" },
                         { L.SIM_SETTINGS, L.SIM_SETTINGS_D, "Interface\\Icons\\Trade_Engineering" } }) do
        local row = S.SettingRow(cc.body, r[1], r[2], nil, 0, r[3])
        ct:Add(row, row.height)
        row.line:Hide()
    end
    S.rowWidth = nil
    local ch = math.max(sh, cc:Fit(ct:Height()))
    sc:SetHeight(ch); cc:SetHeight(ch)

    -- what the name finds: a list over the page, under the box
    local res = CreateFrame("Frame", nil, page)
    res:SetFrameLevel((tonumber(page:GetFrameLevel()) or 0) + 20)
    res:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -4)
    res:SetWidth(goalW)
    S.Box(res, S.SOLID, S.EDGE, S.R_MD)
    res.rows = {}
    for k = 1, FIND_ROWS do
        local b = CreateFrame("Button", nil, res)
        b:SetPoint("TOPLEFT", 4, -4 - (k - 1) * 30)
        b:SetPoint("TOPRIGHT", -4, -4 - (k - 1) * 30)
        b:SetHeight(28)
        S.Box(b, S.CLEAR, S.CLEAR, S.R_MD)
        b.icon = S.IconBox(b, 20)
        b.icon:SetPoint("LEFT", 4, 0)
        b.at = S.Text(b, 12, S.MUTED)
        b.at:SetPoint("RIGHT", -8, 0)
        b.name = S.Text(b, 13)
        b.name:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
        b.name:SetPoint("RIGHT", b.at, "LEFT", -6, 0)
        b.name:SetJustifyH("LEFT")
        b.name:SetWordWrap(false)
        b:SetScript("OnEnter", function(self) S.Fill(self, S.HOVER) end)
        b:SetScript("OnLeave", function(self) S.Fill(self, S.CLEAR) end)
        b:SetScript("OnClick", function(self)
            local rid = self.recipe
            w.find:SetText("")
            w.find:ClearFocus()
            ns.SimSet({ goal = rid })
        end)
        function b:GetText() return self.name:GetText() end
        res.rows[k] = b
    end
    res.more = S.Text(res, 12, S.MUTED)
    res.more:SetPoint("BOTTOMLEFT", 12, 8)
    res:Hide()
    w.results = res

    -- the footer: what it counts with, and Calculate
    w.go = S.Primary(S.FitButton(page, L.CALC, 36, 140))
    w.go:SetPoint("BOTTOMRIGHT", 0, 0)
    w.go:SetScript("OnClick", function() ns.SimCalculate() end)
    local icon = S.IconBox(page, 22, ns.SIM_ICON)
    icon:SetPoint("BOTTOMLEFT", 0, 7)
    w.note = S.Text(page, 12, S.MUTED)
    w.note:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    w.note:SetPoint("RIGHT", w.go, "LEFT", -S.GAP, 0)
    w.note:SetJustifyH("LEFT")
    w.note:SetWordWrap(true)
    w.note:SetMaxLines(2)
    w.note:SetText(L.SIM_NOTE)
end

-- The recipes the name in the goal box finds.
function ns.SimFindRefresh()
    local res, sim = w.results, ns.sim
    if not res then return end
    local text = w.find:GetText() or ""
    local list, all = {}, 0
    if sim and not sim.goal and text ~= "" then list, all = ns.SimFind(sim.line, text, FIND_ROWS) end
    for k, b in ipairs(res.rows) do
        local e = list[k]
        b:SetShown(e ~= nil)
        if e then
            b.recipe = e.recipe
            b.icon:SetIcon(e.out and ns.ItemIcon(e.out) or nil)
            b.name:SetText(e.name)
            b.at:SetText(L.SIM_AT:format(e.learn))
        end
    end
    local more = all - #list
    res.more:SetText(more > 0 and L.SIM_MORE:format(more) or (#list == 0 and L.SIM_NONE or ""))
    res:SetHeight(8 + math.max(1, #list) * 30 + (more > 0 and 22 or 0))
    res:SetShown(text ~= "" and sim ~= nil and not sim.goal)
end

local function refreshSetup()
    local sim = ns.sim
    for _, b in ipairs(w.tiles) do
        local sub = own(b.line)
        b.on = b.line == sim.line
        b.name:SetText(ns.SimProfName(b.line))
        b.name:ClearAllPoints()
        if sub then b.name:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 10, 1)
        else b.name:SetPoint("LEFT", b.icon, "RIGHT", 10, 0) end
        b.name:SetPoint("RIGHT", -8, 0)
        b.name:SetJustifyH("LEFT")
        b.sub:SetText(sub or "")
        S.Fill(b, b.on and { S.FILL[1], S.FILL[2], S.FILL[3], 0.34 } or S.SURFACE)
        S.SetBorder(b, b.on and S.Accent() or S.CARD_EDGE)
    end
    w.from:Refresh(); w.to:Refresh()
    w.empty.switch:SetChecked(sim.empty)
    local g = sim.goal and ns.SimRecipe(sim.line, sim.goal)
    w.chosen:SetShown(g ~= nil)
    w.find:SetShown(g == nil)
    if g then
        w.chosen.icon:SetIcon(g.out and ns.ItemIcon(g.out) or nil)
        w.chosen.name:SetText(g.name)
        w.chosen.at:SetText(L.SIM_AT:format(g.learn))
    end
    ns.SimFindRefresh()
end

-- Calculate on the conditions page: the simulated profession is built, then planned in steps.
function ns.SimCalculate()
    if not ns.sim then return end
    if ns.SimStart() then ns.Calculate() end
end

-- ---------- the whole way ----------

local function makeRun(r)
    r.icon = S.IconBox(r, 26)
    r.icon:SetPoint("LEFT", 2, 0)
    r.range = S.Text(r, 13, nil, nil, "bold")
    r.range:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
    r.range:SetWidth(70)
    r.range:SetJustifyH("LEFT")
    r.range:SetWordWrap(false)
    r.cost = S.Text(r, 13)
    r.cost:SetPoint("RIGHT", -6, 0)
    r.cost:SetJustifyH("RIGHT")
    r.name = S.Text(r, 13)
    r.name:SetPoint("LEFT", r.range, "RIGHT", 6, 0)
    r.name:SetPoint("RIGHT", r.cost, "LEFT", -8, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.line = S.Divider(r)
    r.line:SetPoint("BOTTOMLEFT")
    r.line:SetPoint("BOTTOMRIGHT")
    r.line:SetHeight(1)
    r:EnableMouse(true)
    r:SetScript("OnMouseUp", function(self) if self.leg then ns.SelectLeg(self.leg) end end)
    r:SetScript("OnEnter", function(self)
        if GameTooltip and GameTooltip.SetOwner and self.full then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.full, 1, 1, 1)
            GameTooltip:AddLine(L.SIM_RUNS_HINT, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end
local function fillRun(r, e)
    r.leg, r.full = e.leg, e.full
    r.icon:SetIcon(e.icon)
    r.range:SetText(e.range)
    r.name:SetText(e.name)
    r.cost:SetText(e.cost)
end

-- The runs of the way as rows: { leg, range, name, cost, icon, full }.
function ns.SimRuns()
    local v, rows = ns.view, {}
    for i, leg in ipairs(v.legs or {}) do
        local e = { leg = i, range = leg.from .. "-" .. leg.to }
        if leg.unknown or not leg.plan then
            e.name = hex(S.BAD) .. L.SIM_UNKNOWN .. "|r"
            e.cost, e.icon = "", "Interface\\Icons\\INV_Misc_QuestionMark"
        else
            local st = leg.state or v.state
            local sg = leg.plan.segs and leg.plan.segs[1]
            local r = sg and st.recipes[sg.rid]
            e.icon = r and r.out and ns.ItemIcon(r.out) or (r and r.icon) or nil
            e.full = r and r.name or nil
            e.name = r and (r.name .. hex(S.MUTED) .. " x" .. ns.Ceil(ns.LevelCrafts(leg.plan)) .. "|r") or ""
            e.cost = hex(leg.plan.net >= 0 and S.GOOD or S.BAD) .. (leg.plan.net < 0 and "-" or "+") .. ns.Short(leg.plan.net) .. "|r"
        end
        rows[#rows + 1] = e
    end
    return rows
end

local function tile(parent, label)
    local t = CreateFrame("Frame", nil, parent)
    S.Box(t, S.INPUT, S.CARD_EDGE, S.R_MD)
    t.label = S.Text(t, 12, S.MUTED)
    t.label:SetPoint("TOPLEFT", 10, -7)
    t.label:SetPoint("RIGHT", -6, 0)
    t.label:SetJustifyH("LEFT")
    t.label:SetWordWrap(false)
    t.label:SetText(label)
    t.value = S.Text(t, 14, nil, nil, "bold")
    t.value:SetPoint("BOTTOMLEFT", 10, 7)
    t.value:SetPoint("RIGHT", -6, 0)
    t.value:SetJustifyH("LEFT")
    t.value:SetWordWrap(false)
    return t
end

-- A line of a card: a text on the left, a number on the right.
local function pair(parent, size, face)
    local p = CreateFrame("Frame", nil, parent)
    p:SetHeight(22)
    p.right = S.Text(p, size or 12, nil, nil, face)
    p.right:SetPoint("RIGHT")
    p.right:SetJustifyH("RIGHT")
    p.left = S.Text(p, size or 12, face and S.TEXT or S.MUTED, nil, face)
    p.left:SetPoint("LEFT")
    p.left:SetPoint("RIGHT", p.right, "LEFT", -8, 0)
    p.left:SetJustifyH("LEFT")
    p.left:SetWordWrap(false)
    function p:Set(left, right)
        self:SetShown(left ~= nil)
        self.left:SetText(left or "")
        self.right:SetText(right or "")
    end
    return p
end

local PAY_LINES = 2
local function buildWay()
    local way = CreateFrame("Frame", nil, ui.route)
    way:SetPoint("TOPLEFT", ui.stopsBox, "TOPLEFT", 0, 0)
    way:SetPoint("BOTTOMRIGHT", ui.route, "BOTTOMRIGHT", 0, 0)
    way:Hide()
    w.way = way

    local runs = S.Card(way, L.SIM_RUNS, L.SIM_RUNS_HINT)
    runs:SetPoint("TOPLEFT", 0, 0)
    runs:SetPoint("BOTTOMLEFT", 0, 0)
    runs:SetWidth(RUNS_W)
    w.runs = S.List(runs.body, RUN_H, makeRun, fillRun)
    w.runs:SetPoint("TOPLEFT", 0, 0)
    w.runs:SetPoint("BOTTOMRIGHT", -10, 0)

    local x = RUNS_W + S.GAP
    local cw = MAIN - x - 2 * S.INSET
    local total = S.Card(way, " ")
    total:SetPoint("TOPLEFT", x, 0)
    total:SetPoint("TOPRIGHT", 0, 0)
    w.total = total
    local pill = CreateFrame("Frame", nil, total)
    S.Box(pill, SIM_FILL, SIM_EDGE, 11)
    pill.icon = S.IconBox(pill, 16, ns.SIM_ICON)
    pill.icon:SetPoint("LEFT", 3, 0)
    pill.text = S.Text(pill, 12)
    pill.text:SetPoint("LEFT", pill.icon, "RIGHT", 5, 0)
    pill.text:SetText(L.SIM_PILL)
    pill:SetSize(math.floor(strw(pill.text)) + 34, 22)
    pill:SetPoint("TOPRIGHT", -S.INSET, -7)
    total.title:SetPoint("RIGHT", pill, "LEFT", -8, 0)
    local tw3 = math.floor((cw - 2 * 8) / 3)
    w.tile = {}
    for k, key in ipairs({ "SIM_MATERIALS", "SIM_LEARN", "SIM_SALES" }) do
        local t = tile(total.body, L[key])
        t:SetSize(tw3, 46)
        t:SetPoint("TOPLEFT", (k - 1) * (tw3 + 8), 0)
        w.tile[k] = t
    end
    w.net = pair(total.body, 14, "bold")
    w.net:SetPoint("TOPLEFT", 0, -52)
    w.net:SetPoint("TOPRIGHT", 0, -52)
    w.level = pair(total.body)
    w.level:SetPoint("TOPLEFT", 0, -76)
    w.level:SetPoint("TOPRIGHT", 0, -76)
    -- a way that stops short says so in the place of the level
    w.warn = S.Text(total.body, 12, S.WARN)
    w.warn:SetPoint("TOPLEFT", 0, -78)
    w.warn:SetPoint("TOPRIGHT", 0, -78)
    w.warn:SetJustifyH("LEFT")
    w.warn:SetWordWrap(true)
    w.warn:SetMaxLines(2)
    local th = total:Fit(78 + 30)
    total:SetHeight(th)

    -- after the target: what one craft of the goal recipe gains, and when the way is paid back
    local after = S.Card(way, " ", " ")
    after:SetPoint("TOPLEFT", x, -(th + S.GAP))
    after:SetPoint("BOTTOMRIGHT", 0, 0)
    w.after = after
    local b = after.body
    w.payIcon = S.IconBox(b, 36)
    w.payIcon:SetPoint("TOPLEFT", 0, 0)
    w.gain = S.Text(b, 16, nil, nil, "bold")
    w.gain:SetPoint("TOPRIGHT", 0, -1)
    w.gain:SetJustifyH("RIGHT")
    w.gainSub = S.Text(b, 12, S.MUTED)
    w.gainSub:SetPoint("TOPRIGHT", 0, -22)
    w.gainSub:SetJustifyH("RIGHT")
    w.gainSub:SetText(L.SIM_PER_CRAFT)
    w.payName = S.Text(b, 16, S.GOLD, nil, "bold")
    w.payName:SetPoint("TOPLEFT", w.payIcon, "TOPRIGHT", 10, -1)
    w.payName:SetPoint("RIGHT", w.gain, "LEFT", -8, 0)
    w.payName:SetJustifyH("LEFT")
    w.payName:SetWordWrap(false)
    w.paySub = S.Text(b, 12, S.MUTED)
    w.paySub:SetPoint("TOPLEFT", w.payIcon, "TOPRIGHT", 10, -22)
    w.paySub:SetPoint("RIGHT", w.gainSub, "LEFT", -8, 0)
    w.paySub:SetJustifyH("LEFT")
    w.paySub:SetWordWrap(false)
    w.paySub.tipCut = true
    w.payLines = {}
    for k = 1, PAY_LINES + 1 do
        local p = pair(b)
        p:SetHeight(20)
        p:SetPoint("TOPLEFT", 0, -(42 + (k - 1) * 20))
        p:SetPoint("TOPRIGHT", 0, -(42 + (k - 1) * 20))
        w.payLines[k] = p
    end
    w.payBack = pair(b, 13, "bold")
    w.payBack:SetPoint("BOTTOMLEFT", 0, 0)
    w.payBack:SetPoint("BOTTOMRIGHT", 0, 0)
    w.payNone = S.Text(b, 12, S.MUTED)
    w.payNone:SetPoint("TOPLEFT", 0, 0)
    w.payNone:SetPoint("RIGHT", 0, 0)
    w.payNone:SetJustifyH("LEFT")
    w.payNone:SetWordWrap(true)
    w.payParts = { w.payIcon, w.gain, w.gainSub, w.payName, w.paySub, w.payBack }
end

-- The result of the simulation, counted once per plan.
local cache = {}
function ns.SimCached()
    local v = ns.view
    if not ns.sim or not v.plan then return nil end
    if cache.plan ~= v.plan or cache.legs ~= v.legs or cache.n ~= #(v.legs or {}) then
        cache = { plan = v.plan, legs = v.legs, n = #(v.legs or {}), result = ns.SimResult() }
    end
    return cache.result
end

-- When the way is paid back, as a text: { left, right } for the card's last line.
function ns.SimPayText(res)
    local p, t = res.pay, res.totals
    if not p or not p.gain then return L.SIM_PAY, hex(S.MUTED) .. L.SIM_PAY_NOPRICE .. "|r" end
    if p.gain <= 0 then return L.SIM_PAY, hex(S.BAD) .. L.SIM_PAY_NEVER .. "|r" end
    if (p.crafts or 0) <= 0 then return L.SIM_PAY, hex(S.GOOD) .. L.SIM_PAY_NONE .. "|r" end
    local right = L.SIM_PAY_N:format(p.crafts)
    if p.days then right = right .. S.DOT .. L.SIM_PAY_D:format(p.days) end
    return L.SIM_PAY, right, t
end

local function fillWay()
    local res = ns.SimCached()
    if not res then return end
    local t = res.totals
    w.runs:SetData(ns.SimRuns())
    w.total.title:SetText(S.Upper(L.SIM_WAY:format(res.from, t.reached)))
    w.tile[1].value:SetText(money(t.materials))
    w.tile[2].value:SetText(money(t.learn))
    w.tile[3].value:SetText(hex(S.GOOD) .. "+|r" .. money(t.sales))
    w.net:Set(t.net < 0 and L.SIM_COST or L.SIM_EARNS, signed(t.net))
    w.level:Set(L.SIM_LEVEL:format(t.reached), S.Emph(tostring(t.level)))
    local warn = ""
    if t.reached < t.target then warn = L.SIM_SHORT:format(t.reached)
    elseif res.warn then warn = L[res.warn[1]]:format(res.warn[2], res.warn[3]) end
    w.warn:SetText(warn)
    if warn ~= "" then w.level:Set(nil) end

    local p = res.pay
    local r = p and res.after.recipes[p.recipe]
    w.after.title:SetText(S.Upper(res.goal and L.SIM_AFTER or L.SIM_AFTER_BEST:format(t.reached)))
    w.after.hint:SetText(r and r.cd and L.CD_EVERY:format(ns.CdText(r.cd)) or "")
    for _, x in ipairs(w.payParts) do x:SetShown(r ~= nil) end
    w.payNone:SetShown(r == nil)
    for _, x in ipairs(w.payLines) do x:Set(nil) end
    if not r then
        w.payNone:SetText(L.SIM_NO_CRAFT)
        return
    end
    local items = res.after.items
    w.payIcon:SetIcon(r.out and ns.ItemIcon(r.out) or r.icon)
    w.payName:SetText(r.name)
    w.gain:SetText(p.gain and signed(p.gain) or hex(S.MUTED) .. "-|r")
    local parts = {}
    for _, l in ipairs(p.lines) do parts[#parts + 1] = l.n .. " " .. ((items[l.id] or {}).name or "?") end
    w.paySub:SetText(table.concat(parts, ", "))
    local k = 0
    for i, l in ipairs(p.lines) do
        if i <= PAY_LINES - 1 or #p.lines <= PAY_LINES then
            k = k + 1
            local how = L["SRC_" .. tostring(l.how)]
            w.payLines[k]:Set(((items[l.id] or {}).name or "?") .. " x" .. l.n .. (how and (S.DOT .. how) or ""),
                l.cost < math.huge and money(l.cost) or "-")
        end
    end
    if #p.lines > PAY_LINES then
        local rest = 0
        for i = PAY_LINES, #p.lines do rest = rest + (p.lines[i].cost < math.huge and p.lines[i].cost or 0) end
        k = k + 1
        w.payLines[k]:Set(L.SIM_MORE:format(#p.lines - PAY_LINES + 1), money(rest))
    end
    k = k + 1
    w.payLines[k]:Set(r.name .. S.DOT .. (L["HOW_" .. tostring(p.how)] or ""), hex(S.GOOD) .. "+|r" .. money(p.value))
    local left, right = ns.SimPayText(res)
    w.payBack:Set(left, right)
    -- why the goal is not simply there at the end of the way
    local note = ""
    if p.src == "rep" then note = L.SIM_GOAL_REP
    elseif p.src == "spec" then note = L.SIM_GOAL_SPEC
    elseif p.need and not p.reach then note = L.SIM_GOAL_FAR:format(p.need)
    elseif (p.extra or 0) > 0 then note = L.SIM_GOAL_EXTRA:format(ns.Money(p.extra)) end
    if note ~= "" then w.paySub:SetText(hex(S.WARN) .. note .. "|r") end
end

-- Shows (or hides) the whole way in the place of the stops.
function ns.SimWay(show)
    if not w.way then return end
    w.way:SetShown(show and true or false)
    if show then fillWay() end
end

-- ---------- the Settings tab ----------

-- The settings changed inside the simulation carry a mark; the footer counts them and gives
-- the player's own back.
function ns.SimSettings()
    if not w.back then return end
    local changed = ns.sim and ns.SimChanged() or {}
    local set = {}
    for _, k in ipairs(changed) do set[k] = true end
    for _, list in ipairs({ ui.checks, ui.steppers }) do
        for k, c in pairs(list) do
            local dot = rawget(c, "simDot")
            if set[k] and not dot then
                dot = S.Circle(c, 8, SIM, "OVERLAY")
                dot:SetPoint("RIGHT", c, "LEFT", -6, 0)
                rawset(c, "simDot", dot)
            end
            if dot then dot:SetShown(set[k] == true) end
        end
    end
    w.back:SetShown(#changed > 0)
    ui.toast:SetPoint("RIGHT", #changed > 0 and w.back or ui.reset, "LEFT", -S.GAP, 0)
    if #changed > 0 and not ns.view.delta then ui.toast:SetText(hex(SIM) .. L.SIM_CHANGED:format(#changed) .. "|r") end
end

-- ---------- everything together ----------

-- Sets a page tab's text and moves the tabs after it.
local function retab(i, text)
    local b = ui.tabs.buttons[i]
    if b:GetText() == text then return end
    b:SetText(text)
    local x = 0
    for _, t in ipairs(ui.tabs.buttons) do
        local tw = math.floor(strw(t.text) + 28)
        t:SetWidth(tw)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", x, 0)
        t.x = x
        x = x + tw + 2
    end
    ui.tabs.frame:SetWidth(x)
    ui.tabs:Select(ui.tabs.selected, true)
end

function ns.SimBuild(u, f)
    ui, frame = u, f
    buildSwitch()
    buildStrip()
    buildSetup()
    buildWay()
    -- no profession yet: the simulation is the way in
    ui.simTry = S.FitButton(ui.emptyBox, L.SIM_TRY, 36, 140)
    ui.simTry:SetPoint("TOP", ui.emptyBox, "CENTER", 0, -72)
    ui.simTry:SetScript("OnClick", function() ns.SimOpen() end)
    S.SetButtonIcon(ui.simTry, ns.SIM_ICON, 16)
    ui.simTry:SetWidth(ui.simTry:GetWidth() + 22)
    w.back = S.FitButton(ui.reset:GetParent(), L.SIM_RETURN, 32, 96)
    w.back:SetPoint("RIGHT", ui.reset, "LEFT", -8, 0)
    w.back:SetScript("OnClick", function() ns.SimRevert() end)
    w.back:Hide()
end

-- Called first by ns.Refresh. True when the conditions page shows and nothing else is drawn.
function ns.SimRefresh()
    if not w.strip then return false end
    local sim = ns.sim
    local on = sim ~= nil
    w.toggle.switch:SetChecked(on)
    if on then S.Fill(w.toggle.switch.track, SIM) end
    w.strip:SetShown(on)
    ui.main:SetPoint("TOPLEFT", 0, -(on and OFF or 0))
    if not frame.docked then S.SetBorder(frame, on and SIM_EDGE or S.GLASS_EDGE) end
    local goal = on and sim.to or nil
    retab(2, on and sim.prof and L.SIM_TAB_CRAFTS:format(goal) or L.TAB_CRAFTS)
    local items = ui.tabs.buttons[3]
    items:SetEnabled(not on)
    items:SetAlpha(on and 0.4 or 1)
    local setup = on and not sim.prof
    w.setup:SetShown(setup)
    ui.main:SetShown(not setup)
    if not on then return false end
    if setup then
        w.strip.text:SetText(L.SIM_STRIP_SETUP)
        refreshSetup()
        return true
    end
    -- the shopping list buys for real: the strip says for whom
    w.strip.text:SetText((ns.SimShopOn() and L.SIM_STRIP_SHOP or L.SIM_STRIP):format(sim.name, sim.from, sim.to))
    local _, tab = ns.Selected()
    if tab == 3 then ui.tabs:Select(1); return true end
    return false
end

-- The simulation ended: one notice, and nothing of it is left.
function ns.SimEnded()
    cache = {}
    if w.find then w.find:SetText("") end
    if S.Toast then
        S.Toast({ key = "sim", icon = ns.SIM_ICON, title = L.SIM, text = L.SIM_ENDED, seconds = 6 })
    end
end
