-- The window: the tabs on top (Route, the three lists, Settings). The Route tab shows the
-- routes as tiles, the whole way as one bar of runs, the stops of the run under each other on
-- the left and the chosen stop large on the right, with its items and one main button. It only
-- shows what Core.lua planned; every setting goes through ns.SetPref, which rebuilds the plan.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local W, H = S.WIDE_W, S.DOCK_H
local MAIN = W - 2 * S.PAD
local TOP = 30 + S.GAP
local REP_ICON = "Interface\\Icons\\Achievement_Reputation_01"
-- a route tile below this width cuts its name and numbers; past it the row pages with arrows
local TILE_MIN, ARROW_W = 150, 24
local TILE_H, WAY_H, ROW_GAP = 58, 44, 8
-- the stops on the left, under them the money of the run
local STOPS_W, STOP_H, STOP_GAP, LEDGER_H = 264, 56, 6, 90
-- a row of the chosen stop, and the column at its right end for "Bought" or "Next"
local LINE_H, MARK_W = 48, 76
local STEP_W = 150

-- Icons from the game for the stops; a craft stop shows the profession's own icon.
ns.STOP_ICONS = {
    bank = "Interface\\Minimap\\Tracking\\Banker", ah = "Interface\\Minimap\\Tracking\\Auctioneer",
    vendor = "Interface\\Icons\\INV_Misc_Bag_11", trainer = "Interface\\Icons\\INV_Misc_Book_11",
    craft = "Interface\\Icons\\Trade_Tailoring", sell = "Interface\\Icons\\INV_Misc_Coin_02",
    mail = "Interface\\Icons\\INV_Letter_15", gather = "Interface\\Icons\\Trade_Herbalism",
}
local PATTERN_ICON = "Interface\\Icons\\INV_Scroll_03"
local RANK_ICON = "Interface\\Icons\\INV_Misc_Book_09"
local REFRESH_ICON = "Interface\\Buttons\\UI-RefreshButton"
local GOLD = S.WARN -- warnings (stale prices, no Auctionator); gold is for names only
local GOOD, BAD = S.GOOD, S.BAD
local CHOSEN = { S.FILL[1], S.FILL[2], S.FILL[3], 0.34 }
local NEXT_ROW = { S.FILL[1], S.FILL[2], S.FILL[3], 0.22 }

local frame, side
local ui = { checks = {}, modes = {}, nodes = {}, chips = {}, steppers = {} }
local sui = {} -- the window beside the auction house
ns.ui, ns.sui = ui, sui
local tab = 1
local selected = 1
local flash -- one line for the chosen stop that an action left (lots read, a list sent)

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
-- A signed amount for a list column: copper drops once there is gold, silver too from 100 gold,
-- so the column never cuts the amount with "...". The exact amount stays in the sort key.
function ns.Brief(c, plus)
    if c ~= c or c == math.huge or c == -math.huge then return "?" end
    c = math.floor((c or 0) + 0.5)
    local a = math.abs(c)
    if a >= 1000000 then a = math.floor(a / 10000 + 0.5) * 10000
    elseif a >= 10000 then a = math.floor(a / 100 + 0.5) * 100 end
    local sign = c < 0 and "-" or (plus and c > 0 and "+" or "")
    return sign .. coins(a)
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

-- ---------- the Settings tab ----------

-- The loss budgets the stepper offers, in copper; 0 is no limit.
-- count settings whose stepper ends in "no limit"
local UNLIMITED = { maxSell = true, maxBuy = true }
local BUDGETS = { 0, 10000, 20000, 50000, 100000, 200000, 500000, 1000000, 2000000, 5000000, 10000000 }

-- The saved settings, not the ones of the last result: a calculation may still be running.
local function pref(key)
    local P = ns.Prefs(ns.db and ns.db.prefs)
    if key == "target" then
        local st = ns.view.state or (ns.Skill and ns.Skill())
        if st then return ns.Target(st, P) end
    end
    return P[key]
end

-- A switch row; ui.checks[key] is its switch.
local function sw(key)
    return { L["P_" .. key], nil, function() return pref(key) and true or false end,
             function(on) ns.SetPref(key, on and true or false) end, icon = ns.OPT_ICON[key], key = key }
end

-- What a stepper reads, writes and shows for a setting.
local function stepper(parent, key, step, min, max, fmt, width)
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
    elseif key == "maxCrafts" then
        -- auto (0) shows and steps from the limit it stands for; stepping back onto that value
        -- binds it to the target again; one step past the top is "no limit" (-1)
        local top = max
        local function auto()
            local st = ns.view.state or (ns.Skill and ns.Skill())
            local P = ns.Prefs(ns.db and ns.db.prefs)
            P.maxCrafts = 0
            return st and ns.CraftCap(st, P) or ns.CRAFTS_SPARE
        end
        get = function()
            local v = pref(key) or 0
            if v < 0 then return top + step end
            return v == 0 and auto() or v
        end
        set = function(v) ns.SetPref(key, (v > top and -1) or (v == auto() and 0) or v) end
        fmt = function(v)
            if v > top then return L.NO_LIMIT end
            return (pref(key) or 0) == 0 and L.CRAFTS_AUTO:format(v) or tostring(v)
        end
        max = top + step
    elseif UNLIMITED[key] then
        -- one step past the top is "no limit", saved as 0
        local top, show = max, fmt
        get = function() local v = pref(key) or ns.DEFAULTS[key]; return v == 0 and top + step or v end
        set = function(v) ns.SetPref(key, v > top and 0 or v) end
        fmt = function(v) return v > top and L.NO_LIMIT or show(v) end
        max = top + step
    end
    return S.Stepper(parent, get, set, step, min, max, fmt, width)
end

-- A row with the label on the left (two lines when it is long) and a - value + stepper.
local function stepRow(parent, key, step, min, max, fmt)
    local st = stepper(parent, key, step, min, max, fmt, STEP_W)
    local row = S.SettingRow(parent, key == "target" and L.SIDE_TARGET or L["P_" .. key], nil, st, STEP_W, ns.OPT_ICON[key])
    row.label:SetWordWrap(true)
    row.label:SetMaxLines(2)
    row.isRow = true
    ui.steppers[key] = st
    if key ~= "target" then ui[key] = st end
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
            row.label:SetWordWrap(true)
            row.label:SetMaxLines(2)
            ui.checks[r.key] = row.switch
        end
        st:Add(row, row.height)
        row.line:SetShown(i < #rows)
    end
    return card, card:Fit(st:Height() - 6)
end

-- The crafts the player keeps out of the routes: a name box to find a recipe, then the avoided
-- ones (or what the name finds), each with a button that takes it out or puts it back.
local SKIP_ROWS, SKIP_ROW_H = 4, 32
local refreshSkip
local function toggleSkip(rid)
    local st = ns.view.state
    local r = st and st.recipes[rid]
    if not r then return end
    local on = not r.skip
    local text = (on and L.SKIP_ON or L.SKIP_OFF):format(r.name)
    ns.SetSkip(rid, on)
    ns.Toast(text)
end
local function skipCard(parent)
    local card = S.Card(parent, L.SIDE_SKIP)
    local body = card.body
    local edit = S.Edit(body, 100, 28)
    edit:SetPoint("TOPLEFT", 0, 0)
    edit:SetPoint("TOPRIGHT", 0, 0)
    edit:SetJustifyH("LEFT")
    S.Placeholder(edit, L.SKIP_FIND)
    edit:SetScript("OnTextChanged", function() if refreshSkip then refreshSkip() end end)
    ui.skipEdit, ui.skipRows = edit, {}
    for k = 1, SKIP_ROWS do
        local r = CreateFrame("Frame", nil, body)
        r:SetHeight(SKIP_ROW_H)
        r:SetPoint("TOPLEFT", 0, -(28 + 6 + (k - 1) * SKIP_ROW_H))
        r:SetPoint("RIGHT", 0, 0)
        r.icon = S.ItemIcon(r, 22)
        r.icon:SetPoint("LEFT", 0, 0)
        r.btn = S.Button(r, 84, 28)
        r.btn:SetPoint("RIGHT", 0, 0)
        r.btn:SetScript("OnClick", function() if r.rid then toggleSkip(r.rid) end end)
        r.text = S.Text(r, 12)
        r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
        r.text:SetPoint("RIGHT", r.btn, "LEFT", -8, 0)
        r.text:SetWordWrap(false)
        r:EnableMouse(true)
        r:SetScript("OnEnter", function(self)
            if not self.full or not GameTooltip or not GameTooltip.SetOwner then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.full, 1, 1, 1)
            if type(self.rid) == "number" then GameTooltip:AddLine("ID " .. self.rid, 0.6, 0.6, 0.6) end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        ui.skipRows[k] = r
    end
    ui.skipNote = S.Text(body, 12, S.MUTED)
    ui.skipNote:SetJustifyH("LEFT")
    ui.skipNote:SetJustifyV("TOP")
    ui.skipNote:SetWordWrap(true)
    return card, card:Fit(28 + 6 + SKIP_ROWS * SKIP_ROW_H)
end

function ns.SkipRows()
    local st = ns.view.state
    local text = ui.skipEdit and ui.skipEdit:GetText() or ""
    if type(text) ~= "string" then text = "" end
    text = text:match("^%s*(.-)%s*$")
    local rows, all
    if text ~= "" then rows, all = ns.FindRecipes(st, text, SKIP_ROWS)
    else rows = ns.Skipped(st); all = #rows end
    local note
    if all == 0 then note = text ~= "" and L.SKIP_NONE or L.SKIP_EMPTY
    elseif all > SKIP_ROWS then
        -- the last place says how many more there are
        for i = #rows, SKIP_ROWS, -1 do rows[i] = nil end
        note = L.SKIP_MORE:format(all - #rows)
    end
    return rows, note
end

refreshSkip = function()
    if not ui.skipRows then return end
    local rows, note = ns.SkipRows()
    for k, r in ipairs(ui.skipRows) do
        local e = rows[k]
        r:SetShown(e ~= nil)
        if e then
            r.rid, r.full = e.recipe, e.name
            r.icon:Set(e.out and ns.ItemIcon(e.out) or PATTERN_ICON)
            r.text:SetText(color(e.skip and S.MUTED or S.TEXT) .. e.name .. "|r")
            r.btn:SetText(e.skip and L.SKIP_BACK or L.SKIP_ADD)
            r.btn:SetWidth(math.max(84, math.floor((tonumber((r.btn.text:GetStringWidth())) or 0) + 24)))
        end
    end
    ui.skipNote:SetText(note or "")
    ui.skipNote:ClearAllPoints()
    ui.skipNote:SetPoint("TOPLEFT", 0, -(28 + 6 + #rows * SKIP_ROW_H + 8))
    ui.skipNote:SetPoint("RIGHT", 0, 0)
end

local function buildSettings(box)
    -- under the page: what the last change did to the plan, and the reset
    ui.reset = S.FitButton(box, L.RESET, 32, 96)
    ui.reset:SetPoint("BOTTOMRIGHT", 0, 0)
    ui.reset:SetScript("OnClick", function() ns.ResetPrefs() end)
    ui.toast = S.Text(box, 12, S.MUTED)
    ui.toast:SetPoint("BOTTOMLEFT", 0, 0)
    ui.toast:SetPoint("RIGHT", ui.reset, "LEFT", -S.GAP, 0)
    ui.toast:SetHeight(32)
    ui.toast:SetJustifyH("LEFT")
    ui.toast:SetJustifyV("MIDDLE")
    ui.toast:SetWordWrap(true)
    ui.toast:SetMaxLines(2)

    local page = S.ScrollPage(box, MAIN)
    page:SetPoint("TOPLEFT", 0, 0)
    page:SetPoint("BOTTOMRIGHT", 0, 32 + S.GAP)
    ui.page = page
    local colW = math.floor((MAIN - 10 - S.GAP) / 2)
    local cols, stacks = {}, {}
    for k = 1, 2 do
        local c = CreateFrame("Frame", nil, page.inner)
        c:SetPoint("TOPLEFT", (k - 1) * (colW + S.GAP), 0)
        c:SetSize(colW, 10)
        cols[k], stacks[k] = c, S.Stack(c)
    end
    local function add(k, card, h) stacks[k]:Add(card, h) end

    add(1, rowsCard(cols[1], L.SIDE_TARGET, { sw("level"), stepRow(cols[1], "target", 5, 1, 300),
        stepRow(cols[1], "maxCrafts", 5, 5, 500),
        stepRow(cols[1], "budget", 1, 1, #BUDGETS, function(i) return BUDGETS[i] == 0 and L.NO_LIMIT or ns.Money(BUDGETS[i]) end) }))
    add(1, skipCard(cols[1]))
    add(1, rowsCard(cols[1], L.SIDE_BUYING, { stepRow(cols[1], "guard", 5, 0, 100, function(v) return v .. "%" end), sw("side") }))
    add(1, rowsCard(cols[1], L.SIDE_LEARN, { sw("buyRecipes"), sw("trainer") }))

    add(2, rowsCard(cols[2], L.SIDE_FROM, { sw("useBags"), sw("useBank"), sw("useMail"), sw("useAlts"), sw("buyAH"),
        stepRow(cols[2], "maxBuy", 10, 10, 200, function(v) return L.UNITS:format(v) end), sw("buyVendor") }))
    add(2, rowsCard(cols[2], L.SIDE_SELL, { sw("sellAH"), sw("neutral"), sw("freshOnly"),
        stepRow(cols[2], "chance", 5, 30, 100, function(v) return v .. "%" end),
        stepRow(cols[2], "maxSell", 1, 1, 40, function(v) return L.UNITS:format(v) end) }))

    -- the run log: what the plan promised against what the run really did
    local log = S.Card(cols[1], L.SIDE_LOG)
    ui.logBtn = S.Button(log.body, 180, 30)
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
    ui.logText = S.Text(log.body, 12, S.MUTED)
    ui.logText:SetPoint("TOPLEFT", 0, -38)
    ui.logText:SetPoint("RIGHT", 0, 0)
    ui.logText:SetJustifyH("LEFT")
    ui.logText:SetWordWrap(true)
    add(1, log, log:Fit(38 + 4 * 30))

    local h = math.max(stacks[1]:Height(), stacks[2]:Height())
    cols[1]:SetHeight(h); cols[2]:SetHeight(h)
    page:SetContent(h)
end

-- The settings that need auction prices.
local AH_SWITCH = { buyAH = true, sellAH = true, neutral = true, freshOnly = true }
local AH_STEP = { maxBuy = true, chance = true, maxSell = true }

local function refreshSettings()
    local P = ns.Prefs(ns.db and ns.db.prefs)
    local priced = ns.HasPrices()
    for k, c in pairs(ui.checks) do
        -- without a price addon the auction switches can do nothing: off and grey
        local ah = AH_SWITCH[k] and not priced
        c:SetChecked(not ah and P[k] and true or false)
        c:SetEnabled(not ah)
    end
    for _, st in ipairs({ ui.target, ui.steppers.target, ui.steppers.maxCrafts, ui.steppers.budget }) do
        st.minus:SetEnabled(P.level and true or false)
        st.plus:SetEnabled(P.level and true or false)
    end
    for _, s in pairs(ui.steppers) do s:Refresh() end
    for k in pairs(AH_STEP) do
        local st = ui.steppers[k]
        if st then st.minus:SetEnabled(priced); st.plus:SetEnabled(priced); st:SetAlpha(priced and 1 or 0.4) end
    end
    ui.target:Refresh()
    refreshSkip()
    if ns.char then
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
        ui.toast:SetText(ns.view.plan and L.TOAST_HINT or "")
    end
end

-- ---------- the stops of the run ----------

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

-- What a stop is for, as "label: number", so no language needs plural forms.
local SUB = { STOP_BANK = "SUB_TAKE", STOP_MAIL = "SUB_TAKE", STOP_AH_BUY = "SUB_BUY", STOP_VENDOR_BUY = "SUB_BUY",
              STOP_PREP = "SUB_MAKE", STOP_TRAINER = "SUB_LEARN", STOP_RANK = "SUB_LEARN", STOP_AH_SELL = "SUB_LIST",
              STOP_VENDOR_SELL = "SUB_SELL", STOP_GATHER = "SUB_GATHER" }
local function stopSub(n)
    if n.segs then return runName(n) .. " x" .. n.crafts end
    return L[SUB[n.title] or "SUB_BUY"]:format(#(n.lines or {}))
end
-- The number at the right end of a waiting stop: the skill a craft covers, else its money.
local function stopSide(n)
    if n.segs then return n.to > n.from and (n.from .. "-" .. n.to) or "" end
    if not n.cost or n.cost <= 0 then return "" end
    if n.kind == "sell" or n.title == "STOP_VENDOR_SELL" then return color(GOOD) .. "+" .. ns.Short(n.cost) .. "|r" end
    return ns.Short(n.cost)
end

local function lineIcon(l)
    if l.rank then return RANK_ICON, 1 end
    if l.id then return ns.ItemIcon(l.id), (ns.view.state.items[l.id] or {}).quality end
    local r = l.recipe and ns.view.state.recipes[l.recipe]
    if l.src == "prep" and r and r.out then return ns.ItemIcon(r.out), 1 end
    return PATTERN_ICON, 1
end

-- A small tick drawn from two lines (the game font has no check mark).
local function tick(parent, c)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(12, 12)
    for _, d in ipairs({ { 1.5, -6.5, 4.5, -9.5 }, { 4.5, -9.5, 10.5, -3 } }) do
        local l = f:CreateLine(nil, "OVERLAY")
        l:SetThickness(2)
        l:SetColorTexture(c[1], c[2], c[3], 1)
        l:SetStartPoint("TOPLEFT", f, d[1], d[2])
        l:SetEndPoint("TOPLEFT", f, d[3], d[4])
    end
    return f
end

-- A small pill with a dot and a word: the state of a stop.
local function statePill(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetHeight(22)
    S.Box(p, S.CLEAR, S.EDGE, 11)
    p.dot = S.Circle(p, 8, S.FAINT, "ARTWORK")
    p.dot:SetPoint("LEFT", 9, 0)
    p.text = S.Text(p, 12)
    p.text:SetPoint("LEFT", 23, 0)
    p.text:SetWordWrap(false)
    function p:Set(text, c)
        self:SetShown(text ~= nil)
        if not text then return end
        c = c or S.FAINT
        self.text:SetText(text)
        self.dot:SetVertexColor(c[1], c[2], c[3], 1)
        self:SetWidth(math.floor((tonumber((self.text:GetStringWidth())) or 0) + 34))
    end
    return p
end

local function makeNode(parent, i)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(STOP_H)
    S.Box(b, S.SURFACE, S.CARD_EDGE, S.R_LG)
    b.icon = S.IconBox(b, 36)
    b.icon:SetPoint("LEFT", 10, 0)
    -- at the right end: Done with a tick, "You are here", or what the stop costs
    b.side = S.Text(b, 13)
    b.side:SetPoint("RIGHT", -10, 0)
    b.side:SetJustifyH("RIGHT")
    b.tick = tick(b, GOOD)
    b.tick:SetPoint("RIGHT", b.side, "LEFT", -4, 0)
    b.here = CreateFrame("Frame", nil, b)
    b.here:SetHeight(20)
    b.here:SetPoint("RIGHT", -8, 0)
    S.Box(b.here, S.FILL, S.FILL_EDGE, 10)
    b.here.text = S.Text(b.here, 12, nil, nil, "bold")
    b.here.text:SetPoint("CENTER")
    b.here.text:SetText(L.STOP_HERE)
    b.here:SetWidth(math.floor((tonumber((b.here.text:GetStringWidth())) or 0) + 18))
    b.right = CreateFrame("Frame", nil, b) -- where the two lines of text end
    b.right:SetSize(1, 1)
    b.head = S.Text(b, 13, nil, nil, "bold")
    b.head:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 10, -2)
    b.head:SetPoint("RIGHT", b.right, "LEFT", -6, 0)
    b.head:SetWordWrap(false)
    b.sub = S.Text(b, 12, S.MUTED)
    b.sub:SetPoint("BOTTOMLEFT", b.icon, "BOTTOMRIGHT", 10, 2)
    b.sub:SetPoint("RIGHT", b.right, "LEFT", -6, 0)
    b.sub:SetWordWrap(false)
    b:SetScript("OnClick", function() ns.Select(i) end)
    b:SetScript("OnEnter", function(self)
        if selected ~= i and not rawget(self, "lit") then S.SetBorder(self, S.Accent()) end
        if GameTooltip and GameTooltip.SetOwner then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.head:GetText() or "", 1, 1, 1)
            GameTooltip:AddLine(self.sub:GetText() or "", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        if selected ~= i and not rawget(self, "lit") then S.SetBorder(self, S.CARD_EDGE) end
        if GameTooltip then GameTooltip:Hide() end
    end)
    return b
end

local function fillNode(b, n, p, here)
    local kc = (n.kind == "craft" and n.segs) and (ns.COLORS[n.segs[1].color or "gy"] or ns.COLORS.gy) or ns.STOPS[n.kind]
    b.icon:SetIcon(stopIcon(n))
    S.SetBorder(b.icon, kc)
    b.icon:SetGlow(kc)
    local done = p and p.done or false
    b.icon:SetAlpha(done and 0.6 or 1)
    b.head:SetText(n.index .. " · " .. (L["KIND_" .. n.kind] or n.kind))
    b.sub:SetText(stopSub(n))
    b.tick:SetShown(done)
    b.here:SetShown(here and not done)
    if done then b.side:SetText(color(GOOD) .. L.STOP_DONE .. "|r")
    elseif here then b.side:SetText("")
    else b.side:SetText(stopSide(n)) end
    -- the text ends where the right part starts
    b.right:ClearAllPoints()
    b.here:ClearAllPoints()
    b.sub:SetShown(true)
    if here and not done then
        -- "You are here" stands at the right; where the stop's texts need that room (a long
        -- language), it takes the second line instead, and the chosen stop's card says the rest
        local room = STOPS_W - 10 - 36 - 10 - 6 - (tonumber((b.here:GetWidth())) or 0) - 8
        local need = math.max(tonumber((b.head:GetStringWidth())) or 0, tonumber((b.sub:GetStringWidth())) or 0)
        if need > room then
            b.here:SetPoint("BOTTOMLEFT", b.icon, "BOTTOMRIGHT", 10, 0)
            b.sub:SetShown(false)
            b.right:SetPoint("RIGHT", b, "RIGHT", -4, 0)
        else
            b.here:SetPoint("RIGHT", -8, 0)
            b.right:SetPoint("RIGHT", b.here, "LEFT", 0, 0)
        end
    elseif done then b.right:SetPoint("RIGHT", b.tick, "LEFT", 0, 0)
    else b.right:SetPoint("RIGHT", b.side, "LEFT", 0, 0) end
    local on = n.index == selected
    S.Fill(b, on and CHOSEN or S.SURFACE)
    if not rawget(b, "lit") then S.SetBorder(b, on and S.Accent() or S.CARD_EDGE) end
end

local function drawStops(prog, here)
    local route = ns.view.route or {}
    local child = ui.stops.child
    child:SetWidth(STOPS_W)
    for i, n in ipairs(route) do
        local b = ui.nodes[i] or makeNode(child, i)
        ui.nodes[i] = b
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 0, -(i - 1) * (STOP_H + STOP_GAP))
        b:SetPoint("TOPRIGHT", 0, -(i - 1) * (STOP_H + STOP_GAP))
        fillNode(b, n, prog[i], here == i)
        b:Show()
        if ns.view.changed and ns.view.changed[i] and not rawget(b, "lit") then
            S.SetBorder(b, GOLD)
            b.lit = true
            C_Timer.After(1.4, function()
                b.lit = nil
                S.SetBorder(b, (selected == i) and S.Accent() or S.CARD_EDGE)
            end)
        end
    end
    for i = #route + 1, #ui.nodes do ui.nodes[i]:Hide() end
    local h = math.max(1, #route * (STOP_H + STOP_GAP) - STOP_GAP)
    child:SetHeight(h)
    ui.stops:Update(h)
end

-- ---------- the chosen stop ----------

local SRC = { bank = "SRC_bank", ah = "SRC_ah", vendor = "SRC_vendor", trainer = "SRC_trainer", prep = "SRC_prep",
              sellah = "SRC_sellah", sellv = "SRC_sellv", mail = "SRC_mail", alts = "SRC_alts", gather = "SRC_gather" }

-- The pin of a stop: who sells or teaches the first line that is still open, when the data
-- knows where that is.
local function stopPin(n, p)
    for k, l in ipairs(n.lines or {}) do
        if l.npc and not (p and p.lines and p.lines[k] and p.lines[k].done) then
            local spot = ns.PickNpc(l.npc)
            if spot and spot.zone then return spot end
        end
    end
end

-- Pins the map on a spot and opens it there; says so, or that this map is not known.
function ns.ShowOnMap(spot)
    local text = (ns.SetPin(spot, true) and L.PIN_SET or L.PIN_FAIL):format(spot.label)
    ns.Print(text); ns.Toast(text)
end

-- What the stop's buttons do now. Returns { primary = { text, run, warn = true }, second =
-- { text, run }, tools = { { text, run } } (one with `pin` shows that spot on the map), counter = { text, at, of, right }, hint, bad (the
-- hint is a warning), pill = { text, colour }, vendor = the vendor's plan }. A button without
-- `run` is shown switched off: it says what the stop waits for. `aside`: the window beside the
-- auction house, which has no other stop to go to.
function ns.StopAction(i, aside)
    local v = ns.view
    local n = v.route and v.route[i]
    if not n then return nil end
    local prog = ns.RunProgress()
    local p = prog[i]
    local now = (v.leg or 1) == 1 -- a later run of the way is only a plan
    local done = p and p.done or false
    local a = { tools = {} }
    local onward = (not aside and v.route[i + 1]) and { L.NEXT_STOP, function() ns.Select(i + 1) end } or nil
    local name = v.state.name or ""
    if n.kind == "ah" and n.title == "STOP_AH_BUY" then
        if ns.HasAuctionator() then
            a.tools[#a.tools + 1] = { L.TO_AUCTIONATOR, function()
                local k = ns.ExportShopping(v.route, L.LIST_NAME:format(name))
                local text = k and L.LIST_DONE:format(k, L.LIST_NAME:format(name)) or L.LIST_FAIL
                ns.Print(text); ns.Toast(text)
            end }
        end
        if ns.atAH then
            a.tools[#a.tools + 1] = { L.LOTS_UPDATE, function() ns.Toast(L.LOTS_BUSY:format(ns.ScanLots(v.route))) end }
        end
        a.pill = done and { L.STOP_DONE, GOOD } or (ns.atAH and { L.OPEN_ah, GOOD } or { L.AWAY_ah })
        if done then
            a.primary, a.second, a.hint = { L.BUY_DONE }, onward, L.HINT_BOUGHT
        elseif not now then
            a.primary, a.hint = { L.BUY_AH }, L.HINT_LATER
        elseif not ns.atAH then
            a.primary, a.hint = { L.BUY_AH }, L.HINT_AH_AWAY
        elseif not ns.CanBuy() then
            a.primary, a.hint = { L.BUY_AH }, L.HINT_AH_NOAPI
        else
            local b = ns.BuyFor(n, p)
            local line, all = ns.BuyLine(), #b.queue
            if b.phase == "done" or not line then
                a.primary, a.second = { L.BUY_DONE }, onward
                a.hint = b.byHand > 0 and L.HINT_HAND:format(b.byHand) or L.HINT_BOUGHT
                a.bad = b.byHand > 0
                if b.bought > 0 then a.counter = { text = L.BOUGHT_OF:format(b.bought, all), at = 2 * all + 1, of = 2 * all,
                                                   right = L.PAID:format(S.MoneyText(b.spent)) } end
            else
                local at, of = ns.BuyClicks(all, b.i, b.phase == "ready" or b.phase == "buying")
                a.counter = { text = L.CLICK_OF:format(at, of), at = at, of = of, right = L.ITEM_OF:format(b.i, all) }
                a.second = { L.BUY_SKIP, ns.BuySkip }
                if b.phase == "quote" then
                    a.primary, a.hint = { L.BUY_WAIT }, L.HINT_AH_TWO
                elseif b.phase == "buying" then
                    a.primary, a.hint = { L.BUY_BUSY }, L.HINT_AH_TWO
                elseif b.phase == "ready" then
                    local dear = ns.BuyDear()
                    a.primary = { (dear and L.BUY_ANYWAY or L.BUY_NOW):format(line.n, line.name, S.MoneyIcons(b.quote.total)),
                                  ns.BuyClick, warn = dear,
                                  short = (dear and L.BUY_ANYWAY_SHORT or L.BUY_NOW_SHORT):format(S.MoneyIcons(b.quote.total)) }
                    if dear then
                        local over = math.floor((b.quote.unit / line.unit - 1) * 100 + 0.5)
                        a.hint, a.bad = L.HINT_DEAR:format(over, S.MoneyText(line.unit), S.MoneyText(b.quote.unit)), true
                    else
                        a.hint = L.HINT_PLANNED
                    end
                else
                    a.primary, a.hint = { L.BUY_CHECK:format(line.n, line.name), ns.BuyClick, short = L.BUY_CHECK_SHORT }, L.HINT_AH_TWO
                end
                if b.err then a.hint, a.bad = L[b.err], true end
            end
        end
    elseif n.kind == "vendor" and n.title == "STOP_VENDOR_BUY" then
        local spot = not done and stopPin(n, p)
        if spot then a.tools[#a.tools + 1] = { L.SHOW_ON_MAP, function() ns.ShowOnMap(spot) end, pin = spot } end
        a.pill = done and { L.STOP_DONE, GOOD } or (ns.atVendor and { L.OPEN_vendor, GOOD } or { L.AWAY_vendor })
        if done then
            a.primary, a.second, a.hint = { L.BUY_DONE }, onward, L.HINT_BOUGHT
        elseif not now then
            a.primary, a.hint = { L.BUY_VENDOR }, L.HINT_LATER
        elseif not ns.atVendor then
            a.primary, a.hint = { L.BUY_VENDOR }, L.HINT_V_AWAY
        else
            local plan = ns.VendorNow(n, p)
            a.vendor = plan
            if #plan.buys == 0 then
                a.primary, a.hint, a.bad = { L.BUY_VENDOR }, plan.short and L.HINT_V_MONEY or L.HINT_V_NONE, true
            else
                a.primary = { L.BUY_ALL:format(#plan.buys, S.MoneyIcons(plan.cost)), function()
                    ns.BuyVendor(n, ns.RunProgress()[i])
                    ns.Refresh()
                end }
                a.hint = L.HINT_V_ONE
                for _, e in ipairs(plan.buys) do
                    if e.extra > 0 then a.hint = L.HINT_V_STACK:format(e.name, e.stack, e.need, e.units); break end
                end
                if plan.short then a.hint, a.bad = L.HINT_V_MONEY, true
                elseif plan.missing > 0 then a.hint = a.hint .. " " .. L.HINT_V_MISSING:format(plan.missing) end
            end
        end
    elseif n.kind == "bank" or n.kind == "mail" then
        local open = (n.kind == "bank" and ns.atBank) or (n.kind == "mail" and ns.atMail)
        a.pill = done and { L.STOP_DONE, GOOD } or (open and { L["OPEN_" .. n.kind], GOOD } or { L["AWAY_" .. n.kind] })
        a.second = done and onward or nil
        a.hint = done and L.HINT_TAKEN or L.HINT_TAKE
    elseif n.kind == "craft" then
        -- a craft waits for the stops before it that bring its items
        local waits = 0
        for k = 1, i - 1 do if ns.Gets(v.route[k]) and not (prog[k] and prog[k].done) then waits = waits + 1 end end
        a.pill = (not now or waits == 0) and { L.CRAFT_READY, GOOD } or { L.CRAFT_WAITS:format(waits) }
        local rid, k
        if n.segs then rid, k = ns.NextCraft(n)
        elseif n.lines and n.lines[1] then rid, k = n.lines[1].recipe, n.lines[1].n end
        -- a reagent made in another profession (bars by Smelting) is crafted in that one's window
        local prof = rid and ns.ProfOf(rid) or ns.char.current or ""
        local closed = rid and not ns.ProfessionShown(prof) and ns.CanOpenProfession(prof)
        if closed then
            -- the game crafts only with the profession window open: the first click opens it
            a.primary = { L.OPEN_PROF_BTN:format(prof), function()
                if not ns.OpenProfession(rid) then ns.Print(L.OPEN_PROF); ns.Toast(L.OPEN_PROF) end
            end, short = L.OPEN_PROF_SHORT }
        elseif rid then
            a.primary = { L.MAKE_N:format(k), function() if not ns.Craft(rid, k) then ns.Print(L.OPEN_PROF); ns.Toast(L.OPEN_PROF) end end }
            a.second = { L.OPEN_RECIPE, function() if not ns.OpenRecipe(rid) then ns.Print(L.OPEN_PROF); ns.Toast(L.OPEN_PROF) end end }
        end
        if rid then
            -- the player does not want this craft: every route is planned again without it
            local r = v.state.recipes[rid]
            if r then
                a.tools[#a.tools + 1] = { L.SKIP_CRAFT, function()
                    local text = L.SKIP_ON:format(r.name)
                    ns.SetSkip(rid, true)
                    ns.Print(text); ns.Toast(text)
                end, skip = rid }
            end
        end
        a.hint = closed and L.HINT_CRAFT_OPEN or L.HINT_CRAFT
    elseif n.kind == "trainer" then
        local spot = stopPin(n, p)
        if spot then a.tools[#a.tools + 1] = { L.SHOW_ON_MAP, function() ns.ShowOnMap(spot) end, pin = spot } end
        a.hint = L.HINT_TRAINER
    elseif n.kind == "gather" then
        a.hint = L.HINT_GATHER
    else
        a.hint = L.HINT_SELL
    end
    return a
end

-- The rows of the chosen stop: its items, each with where it stands.
local function detailRows(n, i, a)
    local rows = {}
    if not n then return rows end
    local st = ns.view.state
    local p = ns.RunProgress()[i]
    -- a craft: the recipe with its skill stretch, then each reagent on its own row
    for _, sg in ipairs(n.segs or {}) do
        local r = st.recipes[sg.rid]
        local c = ns.COLORS[sg.color or "gy"] or ns.COLORS.gy
        rows[#rows + 1] = { rid = sg.rid, icon = r.out and ns.ItemIcon(r.out), q = r.out and (st.items[r.out] or {}).quality,
                            text = color(c) .. r.name .. "|r" .. color(S.MUTED) .. " x" .. ns.Ceil(sg.n) .. "|r",
                            note = sg.from .. " - " .. sg.to, right = L.CRAFTS_N:format(ns.Ceil(sg.n)) }
        local ids = {}
        for id in pairs(r.r) do ids[#ids + 1] = id end
        table.sort(ids, function(x, y) return tostring(x) < tostring(y) end)
        for _, id in ipairs(ids) do
            local it = st.items[id] or {}
            local k = ns.Ceil(r.r[id] * sg.n)
            rows[#rows + 1] = { id = id, icon = ns.ItemIcon(id), q = it.quality,
                                text = (it.name or tostring(id)) .. color(S.MUTED) .. " x" .. k .. "|r",
                                note = it.gather and L.SRC_gather or L.REAGENT, right = "" }
        end
    end
    local buying = n.kind == "ah" and n.title == "STOP_AH_BUY" and ns.atAH and ns.buy.sig == n.sig and ns.buy
    local cur = buying and ns.BuyLine()
    local byLine = {}
    for _, e in ipairs(buying and buying.queue or {}) do byLine[e.line] = e end
    local vend = {}
    for _, e in ipairs(a and a.vendor and a.vendor.buys or {}) do vend[e.line] = e end
    local taken = n.kind == "bank" or n.kind == "mail"
    for k, l in ipairs(n.lines or {}) do
        local icon, q = lineIcon(l)
        local name = l.rank and L.STOP_RANK:format(l.rank) or l.name
        local note = l.over and L.SRC_OVER:format(ns.view.prefs.maxSell) or L[SRC[l.src] or ""] or ""
        if l.src == "alts" then note = L.SRC_alts:format(l.who or "?") end
        if l.src == "trainer" and l.who then note = l.who end -- only this trainer teaches it
        -- who sells or teaches it, and where: a click on the line pins the map there
        local spot = l.npc and ns.PickNpc(l.npc)
        if spot then note = spot.label end
        if l.id and (st.items[l.id] or {}).ladder and l.src == "ah" then note = L.SRC_LADDER end
        if l.guess then note = L.SRC_GUESS end
        -- made in another profession of the character (bars by Smelting): name it
        local made = l.src == "prep" and l.recipe and st.recipes[l.recipe]
        if made and made.other then note = made.other end
        local right = l.price and ((l.guess and "~" or "") .. S.MoneyText(l.price * l.n)) or ""
        if l.price and (l.src == "ah" or l.src == "vendor") and l.n > 1 and not spot and not l.guess then note = L.EACH:format(S.MoneyText(l.price)) end
        local e = { id = l.id, rid = l.src == "prep" and l.recipe or nil, icon = icon, q = q,
                    pin = spot and spot.zone and spot or nil, noteShort = spot and spot.who or nil,
                    text = name .. color(S.MUTED) .. " x" .. l.n .. "|r" }
        local q1 = byLine[k]
        e.done = (p and p.lines[k] and p.lines[k].done) or (q1 and q1.done) or false
        if e.done then
            e.mark, e.markColor = taken and L.MARK_TAKEN or L.MARK_BOUGHT, GOOD
        elseif q1 and q1.hand then
            e.mark, e.markColor = L.MARK_HAND, GOLD
        elseif q1 and q1.skipped then
            e.mark, e.markColor = L.MARK_SKIPPED, S.MUTED
        elseif cur and cur == q1 then
            e.now, e.mark, e.markColor = true, L.MARK_NEXT, S.Accent()
            -- the price the auction just answered, for this many
            if buying.phase == "ready" and buying.quote then
                local dear = ns.BuyDear()
                note = L.EACH:format(S.MoneyText(buying.quote.unit)) .. "  ·  "
                    .. color(dear and GOLD or GOOD) .. (dear and L.NOTE_DEAR or L.NOTE_PLANNED) .. "|r"
                right = S.MoneyText(buying.quote.total)
            end
        end
        local vb = vend[k]
        if vb and vb.extra > 0 then note = L.NOTE_STACK:format(vb.need, vb.stack, vb.units) end
        if vb then right = S.MoneyText(vb.cost) end -- what the click pays, whole stacks
        if a and a.vendor and not vb and not e.done and not spot then note = L.NOTE_NOT_HERE end -- else: who has it
        e.note, e.right = note, right
        rows[#rows + 1] = e
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
        elseif e.pin then
            ns.ShowOnMap(e.pin)
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
        elseif e.pin then
            GameTooltip:SetText(e.pin.label, 1, 1, 1, 1, true)
            GameTooltip:AddLine(L.PIN_TIP, 0.6, 0.6, 0.6, true)
        else
            return
        end
        GameTooltip:Show()
    end)
    r.click:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    r.entry = false
    r.icon = S.ItemIcon(r, 30)
    r.icon:SetPoint("LEFT", 8, 0)
    r.mark = S.Text(r, 12, nil, nil, "bold")
    r.mark:SetPoint("RIGHT", -8, 0)
    r.mark:SetJustifyH("RIGHT")
    r.tick = tick(r, GOOD)
    r.tick:SetPoint("RIGHT", r.mark, "LEFT", -4, 0)
    r.right = S.Text(r, 13)
    r.right:SetPoint("RIGHT", -(MARK_W + 16), 0)
    r.right:SetJustifyH("RIGHT")
    r.text = S.Text(r, 13, nil, nil, "bold")
    r.text:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 10, 0)
    r.text:SetPoint("RIGHT", r.right, "LEFT", -8, 0)
    r.text:SetWordWrap(false)
    r.note = S.Text(r, 12, S.MUTED)
    r.note:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 10, 0)
    r.note:SetPoint("RIGHT", r.right, "LEFT", -8, 0)
    r.note:SetWordWrap(false)
end
local function fillLine(r, e)
    r.entry = e
    if e.icon then r.icon:Set(e.icon, nil, e.q) else r.icon:Hide() end
    r.text:SetText(e.text)
    r.note:SetText(e.note or "")
    r.right:SetText(e.right or "")
    -- a long name with its zone gives way to the name alone (the tooltip has both)
    if e.noteShort then
        local room, w = tonumber((r.note:GetWidth())) or 0, tonumber((r.note:GetStringWidth())) or 0
        if room > 0 and w > room then r.note:SetText(e.noteShort) end
    end
    r.mark:SetText(e.mark and (color(e.markColor or S.TEXT) .. e.mark .. "|r") or "")
    r.tick:SetShown(e.done and true or false)
    S.Fill(r, e.now and NEXT_ROW or S.CLEAR)
end

-- The chosen stop, large: its head with the state, its items, the counter of clicks, the main
-- button with a second one beside it, and one line of what the button does. Built into `card`
-- (a frame with a box), for the Route tab and for the window beside the auction house.
-- `width`: how wide the card is, so its texts can be fitted before the game lays it out.
local function makePanel(card, width)
    local p = { pips = {}, tools = {}, width = width }
    local pad = S.INSET
    p.icon = S.IconBox(card, 40)
    p.icon:SetPoint("TOPLEFT", pad, -pad)
    p.pill = statePill(card)
    p.pill:SetPoint("TOPRIGHT", -pad, -pad - 9)
    p.title = S.Text(card, 20, S.GOLD, nil, "title")
    p.title:SetPoint("TOPLEFT", p.icon, "TOPRIGHT", 10, 0)
    p.title:SetPoint("RIGHT", p.pill, "LEFT", -8, 0)
    p.title:SetWordWrap(false)
    p.sub = S.Text(card, 12, S.MUTED)
    p.sub:SetPoint("BOTTOMLEFT", p.icon, "BOTTOMRIGHT", 10, 0)
    p.sub:SetPoint("RIGHT", p.pill, "LEFT", -8, 0)
    p.sub:SetWordWrap(false)

    -- from the bottom up: the hint, the buttons, the counter with its small buttons
    p.hint = S.Text(card, 12, S.MUTED)
    p.hint:SetPoint("BOTTOMLEFT", pad, pad)
    p.hint:SetPoint("BOTTOMRIGHT", -pad, pad)
    p.hint:SetHeight(30)
    p.hint:SetJustifyH("LEFT")
    p.hint:SetJustifyV("TOP")
    p.hint:SetWordWrap(true)
    p.hint:SetMaxLines(2)
    p.act2 = S.Button(card, 100, 40)
    p.act2:SetPoint("BOTTOMRIGHT", -pad, pad + 30 + 8)
    p.act1 = S.Primary(S.Button(card, 100, 40))
    p.act1:SetPoint("BOTTOMLEFT", pad, pad + 30 + 8)
    S.SetFont(p.act1.text, 14, nil, "bold")
    for _, b in ipairs({ p.act1, p.act2 }) do
        b:SetScript("OnClick", function(self) flash = nil; if self.run then self.run() end end)
    end
    local rowY = pad + 30 + 8 + 40 + 8
    p.counter = S.Text(card, 13, nil, nil, "bold")
    p.counter:SetPoint("BOTTOMLEFT", pad, rowY + 6)
    p.count2 = S.Text(card, 12, S.MUTED)
    p.pipBox = CreateFrame("Frame", nil, card)
    p.pipBox:SetSize(10, 6)
    p.pipBox:SetPoint("LEFT", p.counter, "RIGHT", 10, 0)
    p.count2:SetPoint("LEFT", p.pipBox, "RIGHT", 10, 0)
    for k = 1, 2 do
        local b = S.Ghost(S.FitButton(card, " ", 28, 60))
        b:SetScript("OnClick", function(self) flash = nil; if self.run then self.run() end end)
        p.tools[k] = b
    end
    p.tools[1]:SetPoint("BOTTOMRIGHT", -pad, rowY)
    p.tools[2]:SetPoint("RIGHT", p.tools[1], "LEFT", -6, 0)

    p.list = S.List(card, LINE_H, makeLine, fillLine)
    p.list:SetPoint("TOPLEFT", pad, -(pad + 40 + 10))
    p.list:SetPoint("BOTTOMRIGHT", -pad - 10, rowY + 28 + 8)
    -- an unknown stretch of the way has no stops: the card says why
    p.none = S.Text(card, 12, S.MUTED)
    p.none:SetPoint("TOPLEFT", pad, -pad)
    p.none:SetPoint("RIGHT", -pad, 0)
    p.none:SetJustifyH("LEFT")
    p.none:SetWordWrap(true)
    p.none:Hide()
    p.parts = { p.icon, p.pill, p.title, p.sub, p.hint, p.act1, p.act2, p.counter, p.count2, p.pipBox, p.list,
                p.tools[1], p.tools[2] }

    local function setButton(b, spec)
        b:SetShown(spec ~= nil)
        b.run = spec and spec[2] or nil
        if not spec then return end
        b:SetText(spec[1])
        b:SetEnabled(spec[2] ~= nil)
    end

    -- Shows stop i of the route; `aside` for the window beside the auction house.
    function p:Set(i, aside)
        local n = ns.view.route and ns.view.route[i]
        self.none:SetShown(not n)
        for _, x in ipairs(self.parts) do x:SetShown(n ~= nil) end
        if not n then return end
        local a = ns.StopAction(i, aside)
        self.action = a
        self.icon:SetIcon(stopIcon(n))
        self.title:SetText(L["KIND_" .. n.kind] or n.kind)
        self.sub:SetText(n.segs and (stopTitle(n) .. "  ·  " .. L.CRAFTS_N:format(n.crafts)) or stopTitle(n))
        self.pill:Set(a.pill and a.pill[1], a.pill and a.pill[2])
        self.list:SetData(detailRows(n, i, a))
        -- the counter: "Click 3 of 4" with a pip per click
        local c = a.counter
        self.counter:SetText(c and c.text or "")
        self.count2:SetText(c and c.right or "")
        local of = c and c.of or 0
        local pw = of > 0 and math.max(4, math.min(22, math.floor((150 - (of - 1) * 4) / of))) or 0
        if of > 24 then of = 0 end
        for k = 1, math.max(of, #self.pips) do
            local pip = self.pips[k]
            if k <= of and not pip then
                pip = CreateFrame("Frame", nil, self.pipBox)
                S.Box(pip, S.OFF, S.OFF, 3)
                self.pips[k] = pip
            end
            if pip then
                pip:SetShown(k <= of)
                if k <= of then
                    pip:SetSize(pw, 6)
                    pip:ClearAllPoints()
                    pip:SetPoint("LEFT", (k - 1) * (pw + 4), 0)
                    local col = (k < c.at and GOOD) or (k == c.at and S.Accent()) or S.OFF
                    S.Fill(pip, col); S.SetBorder(pip, col)
                end
            end
        end
        self.pipBox:SetWidth(math.max(1, of * (pw + 4) - 4))
        -- the buttons: the main one takes the width the second leaves
        setButton(self.act1, a.primary)
        setButton(self.act2, a.second)
        if a.second then
            self.act2:SetWidth(math.max(96, math.floor((tonumber((self.act2.text:GetStringWidth())) or 0) + 32)))
        end
        self.act1:ClearAllPoints()
        self.act1:SetPoint("BOTTOMLEFT", pad, pad + 30 + 8)
        if a.second then self.act1:SetPoint("RIGHT", self.act2, "LEFT", -8, 0)
        else self.act1:SetPoint("RIGHT", card, "RIGHT", -pad, 0) end
        -- a price above the plan: the button asks first, with a warning edge and a word
        if a.primary and a.primary.warn then S.SetBorder(self.act1, GOLD) end
        for k = 1, 2 do
            local t = a.tools[k]
            setButton(self.tools[k], t)
            if t then self.tools[k]:SetWidth(math.floor((tonumber((self.tools[k].text:GetStringWidth())) or 0) + 24)) end
        end
        -- the counter's second text gives way when the row is full
        local function sw(t) return tonumber((t:GetStringWidth())) or 0 end
        local used = sw(self.counter) + 10 + self.pipBox:GetWidth() + 10 + sw(self.count2) + 12
        for k = 1, 2 do if a.tools[k] then used = used + self.tools[k]:GetWidth() + 6 end end
        if used > self.width - 2 * pad then self.count2:SetText("") end
        -- the main button names the item while that fits; a long name leaves it to the row marked above
        if a.primary and a.primary.short then
            local room = self.width - 2 * pad - (a.second and (self.act2:GetWidth() + 8) or 0) - 24
            if sw(self.act1.text) > room then self.act1:SetText(a.primary.short) end
        end
        local hint = flash or a.hint or ""
        self.hint:SetText((a.bad and not flash) and (color(GOLD) .. hint .. "|r") or hint)
    end
    return p
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
-- A column is at least as wide as its head in this language, so no head is cut.
local measured
local function fitColumns(probe)
    if measured then return end
    measured = true
    for _, spec in ipairs(LISTS) do
        for k = 2, #spec.cols do
            probe:SetText(L[spec.cols[k][1]])
            local w = math.ceil(tonumber((probe:GetStringWidth())) or 0) + 4
            if w > spec.cols[k][2] then spec.cols[k][2] = w end
        end
    end
    probe:SetText("")
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
                cols = { ns.Brief(x.cost), ns.Brief(x.value), L["HOW_" .. x.how],
                         color(x.profit >= 0 and GOOD or BAD) .. ns.Brief(x.profit, true) .. "|r",
                         x.can > 0 and ("x" .. x.can) or "-" },
                keys = { x.name, x.cost, x.value, x.how, x.profit, x.can }, tip = recipeTip(r) }
        end
    elseif which == 3 then
        for _, x in ipairs(ns.Items(st, P)) do
            rows[#rows + 1] = { icon = ns.ItemIcon(x.id), n = x.bags + x.bank, q = (st.items[x.id] or {}).quality, text = x.name,
                cols = { tostring(x.bags), tostring(x.bank),
                         L["HOW_" .. x.how] .. (x.recipeName and (": " .. x.recipeName) or ""),
                         ns.Brief(x.each), ns.Brief(x.total) },
                keys = { x.name, x.bags, x.bank, x.how, x.each, x.total } }
        end
    else
        for _, x in ipairs(ns.Recipes(st, P)) do
            local r = st.recipes[x.recipe]
            local where = (x.src == "text" and (ns.SourceLabel(x.text) or "-")) or L["WHERE_" .. x.src] or "-"
            -- an estimated vendor price gets "~"; the trainer's price is known after one visit
            local price = x.cost and ((x.est and "~" or "") .. ns.Brief(x.cost)) or (x.src == "trainer" and "?" or "-")
            local tip = recipeTip(r)
            if x.who then
                tip[#tip + 1] = { (x.src == "trainer" and L.TIP_TAUGHT or L.TIP_VENDOR):format(table.concat(x.who, ", ")), nil, nil, nil, true }
            end
            if x.src == "spec" then tip[#tip + 1] = { L.TIP_SPEC:format(x.text or L.WHERE_spec), nil, nil, nil, true } end
            if x.est then tip[#tip + 1] = { L.TIP_EST, nil, nil, nil, true } end
            if x.src == "trainer" and not x.cost then tip[#tip + 1] = { L.TIP_TRAINER, nil, nil, nil, true } end
            if x.pay then tip[#tip + 1] = { L.TIP_PAY:format(x.pay), nil, nil, nil, true } end
            rows[#rows + 1] = { icon = r.out and ns.ItemIcon(r.out) or PATTERN_ICON, text = x.name,
                cols = { where, price, x.skill and tostring(x.skill) or "-",
                         x.profit and (color(x.profit >= 0 and GOOD or BAD) .. ns.Brief(x.profit, true) .. "|r") or L.NO_PRICE,
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
        local t = S.Text(r, 12)
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

-- ---------- building ----------

-- A levelling route's name by its place among n: the cheapest, the fastest, or an option between.
local function routeName(mode, n, long)
    if ns.EARN[mode] then return L[(long and "VAR_" or "TILE_") .. mode] end
    local i = tonumber(mode:sub(2)) or 1
    local key = (i == 1) and "cheap" or (i == n and "fast" or "mid")
    return L[(long and "VAR_" or "TILE_") .. key]:format(i)
end

-- A round button with a game picture, for the row of the tabs.
local function roundButton(parent, picture)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(28, 28)
    S.Box(b, S.RAISED, S.EDGE, 14)
    b.pic = b:CreateTexture(nil, "ARTWORK")
    b.pic:SetSize(16, 16)
    b.pic:SetPoint("CENTER")
    b.pic:SetTexture(picture)
    local a = S.Accent()
    b.pic:SetVertexColor(a[1], a[2], a[3], 1)
    b.label = ""
    function b:SetText(s) self.label = s end
    function b:GetText() return self.label end
    b:SetScript("OnEnter", function(self)
        S.SetBorder(self, S.Accent())
        if GameTooltip and GameTooltip.SetOwner then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.label or "", 1, 1, 1)
            if self.tip then GameTooltip:AddLine(self.tip, 0.8, 0.8, 0.8, true) end
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        S.SetBorder(self, self.edge or S.EDGE)
        if GameTooltip then GameTooltip:Hide() end
    end)
    b:SetScript("OnDisable", function(self) self.pic:SetAlpha(0.4) end)
    b:SetScript("OnEnable", function(self) self.pic:SetAlpha(1) end)
    return b
end

local function buildRoute(route, height)
    -- the routes side by side: pick one, compare the result and the crafts
    local vars = CreateFrame("Frame", nil, route)
    vars:SetPoint("TOPLEFT", 0, 0)
    vars:SetPoint("TOPRIGHT", 0, 0)
    vars:SetHeight(TILE_H)
    ui.varTiles = {}
    ui.varPrev = S.FitButton(vars, "<", TILE_H, ARROW_W)
    ui.varPrev:SetWidth(ARROW_W)
    ui.varPrev:SetPoint("TOPLEFT", 0, 0)
    ui.varPrev:SetScript("OnClick", function() ui.varFirst = (ui.varFirst or 1) - 1; ns.Refresh() end)
    ui.varNext = S.FitButton(vars, ">", TILE_H, ARROW_W)
    ui.varNext:SetWidth(ARROW_W)
    ui.varNext:SetPoint("TOPRIGHT", 0, 0)
    ui.varNext:SetScript("OnClick", function() ui.varFirst = (ui.varFirst or 1) + 1; ns.Refresh() end)
    vars:EnableMouseWheel(true)
    vars:SetScript("OnMouseWheel", function(_, d)
        if not ui.varPrev:IsShown() then return end
        ui.varFirst = (ui.varFirst or 1) - d
        ns.Refresh()
    end)
    for i, m in ipairs(ns.MODES) do
        local b = CreateFrame("Button", nil, vars)
        b:SetSize(TILE_MIN, TILE_H)
        b:SetPoint("TOPLEFT", (i - 1) * (TILE_MIN + 8), 0)
        S.Box(b, S.SURFACE, S.CARD_EDGE, S.R_LG)
        -- the result with its sign, top right; the kind of route left of it
        b.value = S.Text(b, 16, nil, nil, "bold")
        b.value:SetPoint("TOPRIGHT", -10, -4)
        b.value:SetJustifyH("RIGHT")
        b.kind = S.Text(b, 12, S.GOLD_DIM, nil, "bold")
        b.kind:SetPoint("TOPLEFT", 10, -6)
        b.kind:SetPoint("RIGHT", b.value, "LEFT", -6, 0)
        b.kind:SetWordWrap(false)
        b.kind:SetText(S.Upper(ns.EARN[m] and L.KIND_PROFIT or L.KIND_LEVEL))
        b.label = S.Text(b, 14, S.GOLD, nil, "bold")
        b.label:SetPoint("TOPLEFT", 10, -22)
        b.label:SetPoint("RIGHT", -10, 0)
        b.label:SetWordWrap(false)
        b.sub = S.Text(b, 12, S.MUTED)
        b.sub:SetPoint("BOTTOMLEFT", 10, 5)
        b.sub:SetPoint("RIGHT", -10, 0)
        b.sub:SetWordWrap(false)
        b:SetScript("OnClick", function(self)
            if ns.EARN[m] then ns.ChooseMode(m); return end
            -- the best route within the budget stays automatic; a levelling tile turns levelling on
            ns.ChooseMode((self.best and (ns.Prefs(ns.db.prefs).budget or 0) > 0) and "auto" or m)
        end)
        b:SetScript("OnEnter", function(self) if ns.view.mode ~= m then S.SetBorder(self, S.Accent()) end end)
        b:SetScript("OnLeave", function(self) if ns.view.mode ~= m then S.SetBorder(self, S.CARD_EDGE) end end)
        ui.varTiles[i] = b
        ui.modes[m] = b
    end

    -- the whole way to the target as one bar: the skill now, a part per run, the target at its end
    local way = CreateFrame("Frame", nil, route)
    way:SetPoint("TOPLEFT", 0, -(TILE_H + ROW_GAP))
    way:SetPoint("TOPRIGHT", 0, -(TILE_H + ROW_GAP))
    way:SetHeight(WAY_H)
    ui.way = way
    local skillLabel = S.Text(way, 12, S.MUTED)
    skillLabel:SetPoint("TOPLEFT", 0, -5)
    skillLabel:SetText(L.R_SKILL)
    ui.skillNow = S.Text(way, 16, nil, nil, "bold")
    ui.skillNow:SetPoint("BOTTOMLEFT", 0, 5)
    ui.target = stepper(way, "target", 5, 1, 300, nil, 110)
    ui.target:SetPoint("RIGHT", 0, 0)
    local targetLabel = S.Text(way, 12, S.MUTED)
    targetLabel:SetPoint("RIGHT", ui.target, "LEFT", -8, 0)
    targetLabel:SetText(L.WAY_TARGET)
    local left = math.max(54, math.floor((tonumber((skillLabel:GetStringWidth())) or 0) + 12))
    local right = 110 + 8 + math.floor((tonumber((targetLabel:GetStringWidth())) or 0)) + 10
    ui.chipW = MAIN - left - right
    local chips = CreateFrame("Frame", nil, way)
    chips:SetPoint("TOPLEFT", left, 0)
    chips:SetPoint("BOTTOMRIGHT", -right, 0)
    ui.chipBox = chips
    ui.chipNote = S.Text(chips, 12, S.MUTED)
    ui.chipNote:SetPoint("LEFT", 2, 0)
    ui.chipNote:SetPoint("RIGHT", 0, 0)
    ui.chipNote:SetWordWrap(false)

    -- under them: the stops on the left with the money of the run, the chosen stop on the right
    local top = TILE_H + ROW_GAP + WAY_H + ROW_GAP
    ui.detailH = height - top
    local stopsBox = CreateFrame("Frame", nil, route)
    stopsBox:SetPoint("TOPLEFT", 0, -top)
    stopsBox:SetPoint("BOTTOMLEFT", 0, LEDGER_H + STOP_GAP)
    stopsBox:SetWidth(STOPS_W)
    ui.stops = S.Scroll(stopsBox)
    ui.stops:SetAllPoints()
    ui.stops.step = STOP_H + STOP_GAP
    local ledger = CreateFrame("Frame", nil, route)
    ledger:SetPoint("BOTTOMLEFT", 0, 0)
    ledger:SetSize(STOPS_W, LEDGER_H)
    S.Box(ledger, S.SURFACE, S.CARD_EDGE, S.R_LG)
    S.Depth(ledger, S.R_LG)
    ui.ledger = ledger
    ui.net = S.Text(ledger, 16, nil, nil, "bold")
    ui.net:SetPoint("TOPRIGHT", -S.INSET, -9)
    ui.net:SetJustifyH("RIGHT")
    local head = S.Text(ledger, 12, S.GOLD_DIM, nil, "bold")
    head:SetPoint("TOPLEFT", S.INSET, -12)
    head:SetPoint("RIGHT", ui.net, "LEFT", -8, 0)
    head:SetWordWrap(false)
    head:SetText(S.Upper(L.LEDGER))
    ui.money = S.Text(ledger, 12, S.MUTED)
    ui.money:SetPoint("TOPLEFT", S.INSET, -32)
    ui.money:SetPoint("RIGHT", -S.INSET, 0)
    ui.money:SetJustifyH("LEFT")
    ui.money:SetWordWrap(true)
    ui.money:SetMaxLines(2)
    -- how many crafts the chosen run takes, bottom left
    ui.crafts = S.Text(ledger, 12, S.MUTED)
    ui.crafts:SetPoint("BOTTOMLEFT", S.INSET, 9)
    ui.crafts:SetPoint("RIGHT", -S.INSET, 0)
    ui.crafts:SetJustifyH("LEFT")
    ui.crafts:SetWordWrap(false)

    local dcard = CreateFrame("Frame", nil, route)
    dcard:SetPoint("TOPLEFT", STOPS_W + S.GAP, -top)
    dcard:SetPoint("BOTTOMRIGHT", 0, 0)
    S.Box(dcard, S.SURFACE, S.CARD_EDGE, S.R_LG)
    S.Depth(dcard, S.R_LG)
    ui.detailCard = dcard
    ui.panel = makePanel(dcard, MAIN - STOPS_W - S.GAP)
    ui.detail, ui.act1, ui.act2, ui.tool1, ui.tool2 = ui.panel.list, ui.panel.act1, ui.panel.act2, ui.panel.tools[1], ui.panel.tools[2]
    ui.unknown = ui.panel.none
end

-- The world map opened from a stop must not hide behind the window: while that map shows, the
-- window (and the hub around it) lies under the map, and comes back up when the map or the
-- window closes. Only our own frames change strata, never the game's map.
local lowered
function ns.MapClosed()
    if not lowered then return end
    for _, e in ipairs(lowered) do e[1]:SetFrameStrata(e[2]) end
    lowered = nil
end

function ns.BehindMap()
    local map = _G.WorldMapFrame
    if lowered or not frame or not frame:IsShown() or not map then return end
    lowered = {}
    local f = frame
    while f and f ~= UIParent and #lowered < 6 do
        local strata = f:GetFrameStrata()
        lowered[#lowered + 1] = { f, type(strata) == "string" and strata or "DIALOG" }
        f:SetFrameStrata("LOW")
        f = f:GetParent()
    end
    if not rawget(ns, "mapHooked") and map.HookScript then
        ns.mapHooked = true
        map:HookScript("OnHide", ns.MapClosed)
        frame:HookScript("OnHide", ns.MapClosed)
    end
end

-- The factions the banner names: two, then how many more.
local function repNames(list)
    local out = table.concat(list, ", ", 1, math.min(2, #list))
    if #list > 2 then out = out .. " +" .. (#list - 2) end
    return out
end

local function build()
    frame = S.Window("GulliCraftProfitFrame", L.TITLE, W, H)
    ui.frame = frame
    ui.age = frame.sub
    local main = frame.body
    local bodyH = frame.inner[2]
    ui.main = main
    local labels = { L.TAB_ROUTE, L.TAB_CRAFTS, L.TAB_ITEMS, L.TAB_RECIPES, L.TAB_SETTINGS }
    ui.tabs = S.PageTabs(main, labels, nil, function(i) tab = i; if ns.Refresh then ns.Refresh() end end)

    -- on the row of the tabs: the profession (a click takes the next one) and Recalculate
    ui.calc = roundButton(main, REFRESH_ICON)
    ui.calc:SetPoint("TOPRIGHT", 0, 3)
    ui.calc:SetScript("OnClick", function() if ns.Busy() then ns.StopCalc() else ns.Calculate() end end)
    ui.stale = S.Badge(main)
    ui.stale:SetPoint("RIGHT", ui.calc, "LEFT", -8, 0)
    ui.prof = S.Pill(main, 120, 28)
    ui.prof:SetPoint("RIGHT", ui.calc, "LEFT", -8, 0)
    ui.prof.icon = S.IconBox(ui.prof, 20)
    ui.prof.icon:SetPoint("LEFT", 4, 0)
    ui.prof.text:ClearAllPoints()
    ui.prof.text:SetPoint("LEFT", ui.prof.icon, "RIGHT", 8, 0)
    ui.prof.text:SetJustifyH("LEFT")
    ui.prof:SetScript("OnClick", function()
        local profs = ns.Professions()
        if #profs < 2 then return end
        local at = 1
        for i, p in ipairs(profs) do if p.name == ns.char.current then at = i end end
        ns.SetProfession(profs[at % #profs + 1].name)
    end)
    ui.prof:HookScript("OnEnter", function(self)
        if not (GameTooltip and GameTooltip.SetOwner) then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L.SIDE_PROF, 1, 1, 1)
        for _, p in ipairs(ns.Professions()) do
            GameTooltip:AddDoubleLine(p.name, p.skill .. "/" .. p.cap, 0.8, 0.8, 0.8, 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    ui.prof:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    local route = CreateFrame("Frame", nil, main)
    route:SetPoint("TOPLEFT", 0, -TOP)
    route:SetPoint("BOTTOMRIGHT", 0, 0)
    ui.route = route
    buildRoute(route, bodyH - TOP)

    -- list tabs: one card with column heads and rows
    local list = S.Card(main)
    list:SetPoint("TOPLEFT", 0, -TOP)
    list:SetPoint("BOTTOMRIGHT", 0, 0)
    ui.listFrame = list
    -- the column heads sort the list: a click picks the column, a second click turns the order
    ui.listHead, ui.sort = {}, {}
    for k = 1, 6 do
        local h = CreateFrame("Button", nil, list.body)
        h:SetHeight(18)
        h.text = S.Text(h, 12, S.MUTED)
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
    ui.probe = S.Text(list.body, 12, S.MUTED)
    ui.probe:Hide()
    ui.list = S.List(list.body, 32, makeListRow, fillListRow)
    ui.list:SetPoint("TOPLEFT", 0, -20)
    ui.list:SetPoint("BOTTOMRIGHT", -10, 0)

    -- over the route and the lists: the reputation the plan could not read (like Crates' old prices)
    ui.repBanner = S.Banner(main, REP_ICON)
    ui.repBanner:SetPoint("TOPLEFT", 0, -TOP)
    ui.repBanner:SetPoint("TOPRIGHT", 0, -TOP)
    ui.repBanner.onClose = function() ns.repClosed = true; ns.Refresh() end
    -- no auction price addon: the prices are guesses and only levelling routes show
    ui.priceBanner = S.Banner(main, "Interface\\Minimap\\Tracking\\Auctioneer")
    ui.priceBanner.onClose = function() ns.priceClosed = true; ns.Refresh() end

    local settings = CreateFrame("Frame", nil, main)
    settings:SetPoint("TOPLEFT", 0, -TOP)
    settings:SetPoint("BOTTOMRIGHT", 0, 0)
    ui.settings = settings
    buildSettings(settings)

    local emptyBox = CreateFrame("Frame", nil, main)
    emptyBox:SetPoint("TOPLEFT", 0, -TOP)
    emptyBox:SetPoint("BOTTOMRIGHT", 0, 0)
    ui.emptyBox = emptyBox
    ui.empty = S.Empty(emptyBox)
    -- the calculation in steps: how far it is
    ui.progress = S.Progress(emptyBox, 8)
    ui.progress:SetPoint("TOPLEFT", emptyBox, "LEFT", 80, -48)
    ui.progress:SetPoint("TOPRIGHT", emptyBox, "RIGHT", -80, -48)
    ui.calcBig = S.Primary(S.FitButton(emptyBox, L.CALC, 36, 140))
    ui.calcBig:SetPoint("TOP", emptyBox, "CENTER", 0, -72)
    ui.calcBig:SetScript("OnClick", function() if ns.Busy() then ns.StopCalc() else ns.Calculate() end end)

    frame:SetScript("OnShow", function() ns.Rebuild(false, "open") end)
    ui.tabs:Select(1, true)
end

-- ---------- refreshing ----------

local function refreshProfession()
    local profs = ns.Professions()
    local cur
    for _, p in ipairs(profs) do if ns.char and p.name == ns.char.current then cur = p end end
    cur = cur or profs[1]
    ui.prof:SetShown(cur ~= nil)
    if not cur then return end
    ui.prof.icon:SetIcon(cur.icon)
    ui.prof:SetText(cur.name)
    ui.prof:SetWidth(math.max(72, math.floor((tonumber((ui.prof.text:GetStringWidth())) or 0) + 46)))
end

-- The runs of the whole way as parts of one bar; an unknown stretch in red. When they do not
-- all fit, the bar shows the ones around the chosen run.
local CHIP_MIN = 96
local function makeChip(parent)
    local b = CreateFrame("Button", nil, parent)
    S.Box(b, S.SURFACE, S.CARD_EDGE, S.R_MD)
    b.bar = S.Tex(b, "ARTWORK", 0, S.TEXT)
    b.bar:SetPoint("TOPLEFT", 10, -9)
    b.bar:SetPoint("TOPRIGHT", -10, -9)
    b.bar:SetHeight(4)
    b.net = S.Text(b, 12, nil, nil, "bold")
    b.net:SetPoint("BOTTOMRIGHT", -10, 8)
    b.net:SetJustifyH("RIGHT")
    b.text = S.Text(b, 12)
    b.text:SetPoint("BOTTOMLEFT", 10, 8)
    b.text:SetPoint("RIGHT", b.net, "LEFT", -6, 0)
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    function b:GetText() return (self.text:GetText() or "") .. "  " .. (self.net:GetText() or "") end
    b:SetScript("OnClick", function(self) ns.SelectLeg(self.leg) end)
    b:SetScript("OnEnter", function(self) if not self.on then S.SetBorder(self, S.Accent()) end end)
    b:SetScript("OnLeave", function(self) if not self.on then S.SetBorder(self, S.CARD_EDGE) end end)
    return b
end
local function refreshChips(v)
    local legs = v.legs or {}
    local n = #legs
    local room = ui.chipW
    local fit = math.min(n, math.floor((room + 6) / (CHIP_MIN + 6)))
    local cw = fit > 0 and math.floor((room - (fit - 1) * 6) / fit) or 0
    local sel = v.leg or 1
    local first = math.max(1, math.min(sel - math.floor(fit / 2), n - fit + 1))
    for k = 1, math.max(#ui.chips, fit) do
        local i = first + k - 1
        local leg = k <= fit and legs[i]
        local b = ui.chips[k]
        if leg then
            if not b then b = makeChip(ui.chipBox); ui.chips[k] = b end
            b.leg, b.on = i, i == sel
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", (k - 1) * (cw + 6), 0)
            b:SetSize(cw, WAY_H)
            -- each run named by the skill it ends at (the bar starts at the skill now), with what
            -- it gains or loses, so the whole way reads at a glance
            local range = tostring(leg.to)
            local c = BAD
            if leg.unknown then
                b.text:SetText(color(BAD) .. range .. " ?|r")
                b.net:SetText("")
            else
                local plan, st = leg.plan, leg.state or v.state
                local sg = plan and plan.segs and plan.segs[1]
                c = sg and (ns.COLORS[sg.color or "gy"] or ns.COLORS.gy) or S.FAINT
                local net = plan and plan.net or 0
                b.net:SetText(plan and (color(net >= 0 and GOOD or BAD) .. (net < 0 and "-" or "+") .. ns.Short(net) .. "|r") or "")
                -- the recipe of the run beside its skill, when the part is wide enough for it
                local r = sg and st and st.recipes[sg.rid]
                local long = r and (range .. "  " .. color(S.MUTED) .. r.name .. " x" .. ns.Ceil(plan.crafts or sg.n) .. "|r")
                b.text:SetText(long or range)
                if long then
                    local need = (tonumber((b.text:GetStringWidth())) or 0) + (tonumber((b.net:GetStringWidth())) or 0) + 28
                    if need > cw then b.text:SetText(range) end
                end
            end
            b.bar:SetVertexColor(c[1], c[2], c[3], b.on and 1 or 0.35)
            S.Fill(b, b.on and CHOSEN or S.SURFACE)
            S.SetBorder(b, b.on and S.Accent() or S.CARD_EDGE)
            b:Show()
        elseif b then
            b:Hide()
        end
    end
    if ns.BusyKind() == "legs" and n == 0 then
        ui.chipNote:SetText(L.LEGS_BUSY:format(math.floor(ns.progress.done * 100)))
    else
        ui.chipNote:SetText(n == 0 and (v.plan and v.plan.earn and L.LEGS_EARN or "") or "")
    end
    ui.legsBusy = ns.BusyKind() == "legs"
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
    -- fewer routes than tiles (no profit routes without prices): the rest hide
    for i = #(v.variants or {}) + 1, #ui.varTiles do ui.varTiles[i]:Hide() end
    -- as many tiles as fit at a readable width; arrows page through the rest, and the chosen
    -- route stays in view when it changes
    local k = #shown
    local fit, x0, avail = k, 0, MAIN
    if k > math.floor((MAIN + 8) / (TILE_MIN + 8)) then
        x0, avail = ARROW_W + 6, MAIN - 2 * (ARROW_W + 6)
        fit = math.max(1, math.floor((avail + 8) / (TILE_MIN + 8)))
        local sel
        for j, e in ipairs(shown) do if e.x.mode == v.mode then sel = j end end
        if sel and ui.varFollow ~= v.mode then
            ui.varFollow = v.mode
            if sel < (ui.varFirst or 1) then ui.varFirst = sel
            elseif sel >= (ui.varFirst or 1) + fit then ui.varFirst = sel - fit + 1 end
        end
        ui.varFirst = math.max(1, math.min(ui.varFirst or 1, k - fit + 1))
    else
        ui.varFirst = 1
    end
    local paged = fit < k
    ui.varPrev:SetShown(paged); ui.varNext:SetShown(paged)
    ui.varPrev:SetEnabled(ui.varFirst > 1)
    ui.varNext:SetEnabled(ui.varFirst + fit - 1 < k)
    local vw = math.floor((avail - (fit - 1) * 8) / math.max(1, fit))
    for j, e in ipairs(shown) do
        local b, x = e.b, e.x
        local slot = j - ui.varFirst
        b:SetShown(slot >= 0 and slot < fit)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", x0 + slot * (vw + 8), 0)
        b:SetSize(vw, TILE_H)
        local on = x.mode == v.mode
        local p = x.plan
        b.best, b.on = x.best, on
        S.Fill(b, on and CHOSEN or S.SURFACE)
        S.SetBorder(b, on and S.Accent() or S.CARD_EDGE)
        b.label:SetText(routeName(x.mode, levels))
        if p then
            -- the whole way, so the tiles compare routes: its money, its target and all its crafts
            local full = p.full or p
            b.value:SetText(color(full.net >= 0 and GOOD or BAD) .. (full.net < 0 and "-" or "+") .. ns.Short(full.net) .. "|r")
            local sub = (full.reached < full.target) and L.VAR_STOP:format(full.reached)
                or (p.earn and L.VAR_GOLD:format(ns.Ceil(p.crafts)) or L.VAR_RUN:format(full.target, ns.Ceil(full.crafts)))
            if x.many then sub = color(BAD) .. L.VAR_MANY .. "|r"
            elseif x.over then sub = color(BAD) .. L.VAR_OVER .. "|r"
            elseif x.best and v.prefs.budget > 0 then sub = color(GOOD) .. L.VAR_BEST .. "|r" end
            b.sub:SetText(sub)
            b:SetAlpha((x.over or x.many) and 0.55 or 1)
        else
            b.label:SetText(L.TILE_cheap)
            b.value:SetText(color(S.FAINT) .. "-|r")
            b.sub:SetText(v.prefs.level and L.VAR_MAXED or L.VAR_OFF)
            b:SetAlpha(0.6)
        end
    end
    refreshChips(v)
    local unknown = leg and leg.unknown
    local start = (leg and (v.leg or 1) > 1) and leg.from or v.state.skill
    ui.skillNow:SetText(tostring(start))
    -- what is paid, what own stock is worth, what the sales bring, and the result with its sign
    local w = plan.warn or (plan.full and plan.full.warn)
    local guess = false
    for _, r in pairs(v.state.recipes) do if r.guess and r.learned then guess = true end end
    ui.crafts:SetText((not unknown and (plan.crafts or 0) > 0)
        and L.LEDGER_CRAFTS:format(S.Emph(tostring(ns.Ceil(plan.crafts)))) or "")
    if unknown then
        ui.money:SetText("")
        ui.net:SetText("")
    else
        local text = L.LEDGER_MONEY:format(ns.Short(plan.spend), ns.Short(plan.own), ns.Short(plan.income))
        if w then text = color(GOLD) .. L[w[1]]:format(w[2], w[3]) .. "|r"
        elseif guess and not plan.earn then text = text .. "\n" .. L.GUESS end
        ui.money:SetText(text)
        ui.net:SetText(color(plan.net >= 0 and GOOD or BAD) .. (plan.net < 0 and "-" or "+") .. ns.Short(plan.net) .. "|r")
    end
    if selected > #v.route then selected = 1 end
    local prog = ns.RunProgress()
    drawStops(prog, (v.leg or 1) == 1 and ns.Here(v.route, prog, ns.Place()) or nil)
    if unknown then ui.unknown:SetText(L.LEG_UNKNOWN:format(leg.from, leg.to)) end
    ui.panel:Set(selected)
    if not v.route[selected] and not unknown then ui.unknown:SetText(plan.earn and L.WARN_EARN or "") end
end

function ns.Toast(text)
    flash = text
    if ns.Refresh then ns.Refresh() end
end

local function refreshList()
    fitColumns(ui.probe)
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
    if ns.SideRefresh then ns.SideRefresh() end
    if not ns.Visible() then return end
    refreshProfession()
    refreshSettings()
    local v = ns.view
    local age = ns.PriceAge(v.state)
    local slash = "/gcp  ·  "
    if not ns.HasPrices() then ui.age:SetText(slash .. color(GOLD) .. L.NO_AUCTIONATOR .. "|r")
    elseif age then ui.age:SetText(slash .. L.PRICES_AGE:format(age < 1 and L.AGE_TODAY or L.AGE_DAYS:format(math.floor(age))))
    else ui.age:SetText("/gcp") end
    local busy = ns.BusyKind() == "all"
    local has = v.state ~= nil and v.plan ~= nil and not busy
    local known = ns.char and ns.char.current and ns.char.profs and ns.char.profs[ns.char.current]
    local label = (ns.Busy() and busy) and L.CALC_STOP or (v.plan and L.RECALC or L.CALC)
    ui.calc:SetText(label)
    ui.calc:SetEnabled(known and true or false)
    ui.calcBig:SetText(label)
    ui.calcBig:SetShown(known and true or false)
    ui.progress:SetShown(busy)
    if busy then
        local f = ns.progress.done
        ui.empty:Set(L.CALC_BUSY:format(math.floor(f * 100)), L.CALC_SUB)
        ui.progress:Set(f)
    elseif not known then ui.empty:Set(L.NO_PROF)
    elseif not v.plan then ui.empty:Set(L.CALC_TITLE, L.CALC_SUB)
    else ui.empty:Set("") end
    -- bags or prices changed since the plan: the button says so, in a word and on its edge
    local stale = v.stale and not busy and v.plan ~= nil
    ui.stale:Set(stale and L.STALE_TAG or nil, GOLD)
    ui.calc.edge = stale and GOLD or nil
    local staleText = (v.stale == "target" or v.stale == "pick") and L.CALC_STALE_SET or L.CALC_STALE
    ui.calc.tip = stale and staleText or nil
    S.SetBorder(ui.calc, stale and GOLD or S.EDGE)
    ui.prof:ClearAllPoints()
    ui.prof:SetPoint("RIGHT", stale and ui.stale or ui.calc, "LEFT", -8, 0)
    if stale then ui.toast:SetText(color(GOLD) .. staleText .. "|r") end
    ui.settings:SetShown(tab == 5)
    -- patterns left out because the reputation was not read yet: ask for the reputation window
    local unknown = ns.RepUnknown()
    local rep = has and tab < 5 and #unknown > 0 and not ns.repClosed
    ui.repBanner:SetShown(rep and true or false)
    if rep then ui.repBanner:Set(L.REP_BANNER:format(repNames(unknown))) end
    local noPrices = has and tab < 5 and v.state.noPrices and not ns.priceClosed
    ui.priceBanner:SetShown(noPrices and true or false)
    local top = TOP + (rep and S.BANNER_H + S.GAP or 0)
    if noPrices then
        ui.priceBanner:Set(L.NO_PRICES_BANNER:format(ns.AH_GUESS))
        ui.priceBanner:ClearAllPoints()
        ui.priceBanner:SetPoint("TOPLEFT", 0, -top)
        ui.priceBanner:SetPoint("TOPRIGHT", 0, -top)
        top = top + S.BANNER_H + S.GAP
    end
    ui.route:SetPoint("TOPLEFT", 0, -top)
    ui.listFrame:SetPoint("TOPLEFT", 0, -top)
    ui.emptyBox:SetShown(not has and tab ~= 5)
    ui.route:SetShown(has and tab == 1)
    ui.listFrame:SetShown(has and tab > 1 and tab < 5)
    if not has or tab == 5 then return end
    if tab == 1 then refreshRoute() else refreshList() end
end

-- The chosen stop and tab, for the tests.
function ns.Select(i) selected = i; flash = nil; ns.Refresh() end
function ns.Tab(i) if ui.tabs then ui.tabs:Select(i) end end
function ns.Selected() return selected, tab end

function ns.Toggle()
    if S.ToggleWindow(ns.Window()) then ns.Rebuild(false, "open") end
end

-- ---------- beside the auction house ----------

-- The stop the small window shows: the first buy of the current run that is not done, at the
-- place that is open (the auction house, or a vendor that sells something of that stop).
local SIDE_STOPS = { ah = "STOP_AH_BUY", vendor = "STOP_VENDOR_BUY" }
local function sideStop()
    local v = ns.view
    if not v.route or not v.plan or (v.leg or 1) > 1 then return nil end
    local place = ns.sidePlace or "ah"
    local prog = ns.RunProgress()
    for i, n in ipairs(v.route) do
        if n.kind == place and n.title == SIDE_STOPS[place] and not (prog[i] and prog[i].done) then
            if place ~= "vendor" or #ns.VendorNow(n, prog[i]).buys > 0 then return i, prog[i] end
        end
    end
    return nil
end
-- Lines of the run still to buy at the auction: the number on the window's tab.
function ns.SideLeft()
    local _, p = sideStop()
    return p and p.left or 0
end

local STRIP_H = 36
local function buildSide()
    side = S.Window("GulliCraftProfitSide", L.TITLE, S.NARROW_W, S.DOCK_H)
    sui.frame = side
    local body = side.body
    sui.run = S.Text(body, 12, S.GOLD_DIM, nil, "bold")
    sui.run:SetPoint("TOPLEFT", 0, -3)
    sui.net = S.Text(body, 13, nil, nil, "bold")
    sui.net:SetPoint("TOPRIGHT", 0, -2)
    sui.net:SetJustifyH("RIGHT")
    sui.run:SetPoint("RIGHT", sui.net, "LEFT", -8, 0)
    sui.run:SetWordWrap(false)
    -- the stops of the run as a line of icons: done, here, to come
    local strip = CreateFrame("Frame", nil, body)
    strip:SetPoint("TOPLEFT", 0, -(18 + 8))
    strip:SetPoint("TOPRIGHT", 0, -(18 + 8))
    strip:SetHeight(STRIP_H)
    sui.strip, sui.icons, sui.links = strip, {}, {}
    local card = CreateFrame("Frame", nil, body)
    card:SetPoint("TOPLEFT", 0, -(18 + 8 + STRIP_H + 8))
    card:SetPoint("BOTTOMRIGHT", 0, 0)
    S.Box(card, S.SURFACE, S.CARD_EDGE, S.R_LG)
    S.Depth(card, S.R_LG)
    sui.panel = makePanel(card, S.NARROW_W - 2 * S.PAD)
end

function ns.SideWindow()
    if not side then buildSide() end
    return side
end

local STRIP_MAX = 9
local function refreshSideWindow()
    local v = ns.view
    local i = sideStop() or sui.stop
    local n = i and v.route and v.route[i]
    if not n then return end
    sui.stop = i
    local plan, st = v.plan, v.state
    local from, to = st.skill, plan.target or st.skill
    for _, x in ipairs(v.route) do if x.segs then from, to = x.from, x.to end end
    sui.run:SetText(S.Upper((to > from and L.SIDE_RUN:format(from, to) or L.SIDE_RUN_EARN) .. "  ·  " .. L.SIDE_STOP:format(i, #v.route)))
    sui.net:SetText(L.SIDE_RESULT:format(color(plan.net >= 0 and GOOD or BAD) .. (plan.net < 0 and "-" or "+") .. ns.Short(plan.net) .. "|r"))
    -- the icons around the stop shown, when the run has more than fit
    local prog = ns.RunProgress()
    local count = math.min(#v.route, STRIP_MAX)
    local first = math.max(1, math.min(i - math.floor(count / 2), #v.route - count + 1))
    local width = S.NARROW_W - 2 * S.PAD
    local gap = count > 1 and (width - 34) / (count - 1) or 0
    for k = 1, math.max(count, #sui.icons) do
        local ic = sui.icons[k]
        if k <= count and not ic then
            ic = S.IconBox(sui.strip, 26)
            sui.icons[k] = ic
            local l = S.Tex(sui.strip, "BACKGROUND", 0, S.LINE)
            l:SetHeight(2)
            sui.links[k] = l
        end
        if ic then
            local x = v.route[first + k - 1]
            ic:SetShown(k <= count)
            sui.links[k]:SetShown(k <= count and k > 1)
            if k <= count then
                local here = first + k - 1 == i
                local done = prog[first + k - 1] and prog[first + k - 1].done
                local size = here and 34 or 26
                ic:SetSize(size, size)
                ic.ring:SetSize(size, size); ic.bg:SetSize(size - 2, size - 2); ic.tex:SetSize(size - 2, size - 2)
                ic:ClearAllPoints()
                ic:SetPoint("CENTER", sui.strip, "LEFT", 17 + (k - 1) * gap, 0)
                ic:SetIcon(stopIcon(x))
                local c = done and GOOD or (here and S.Accent() or S.RING)
                S.SetBorder(ic, c); ic:SetGlow(c)
                ic:SetAlpha(done and 0.6 or 1)
                if k > 1 then
                    local l = sui.links[k]
                    local lc = (prog[first + k - 2] and prog[first + k - 2].done) and GOOD or S.EDGE
                    l:SetVertexColor(lc[1], lc[2], lc[3], lc[4] or 1)
                    l:ClearAllPoints()
                    l:SetPoint("LEFT", sui.strip, "LEFT", 17 + (k - 2) * gap + 20, 0)
                    l:SetWidth(math.max(1, gap - 40))
                end
            end
        end
    end
    sui.panel:Set(i, true)
end

function ns.SideRefresh()
    if S.SideRefresh then S.SideRefresh() end
    if side and side:IsShown() then refreshSideWindow() end
end

-- At the auction house or a vendor: the buy stop of the run opens beside its window (a tab
-- there when another Gulli window stands in the same place), unless the big window is on the
-- screen. A vendor gets it only when it sells something the stop still needs.
function ns.SideShow(place)
    local P = ns.Prefs(ns.db and ns.db.prefs)
    local big = frame and frame:IsShown() and not frame.docked
    ns.sidePlace = place or "ah"
    if not P.side or big or not S.SideOpen or not sideStop() then return false end
    sui.stop = nil
    ns.SideWindow()
    S.SideOpen("CraftProfit")
    refreshSideWindow()
    return true
end
function ns.SideHide()
    if S.SideClose then S.SideClose("CraftProfit") end
end
if S.SideAdd then
    S.SideAdd({ key = "CraftProfit", order = 20, title = L.TITLE, icon = "Interface\\AddOns\\Gulli-CraftProfit\\icon",
                window = function() return ns.SideWindow() end, badge = function() return ns.SideLeft() end })
end

-- The player opened or left a place: the route goes to the stop for it, and the auction house
-- or the vendor gets the small window beside it.
function ns.Arrive(place)
    local v = ns.view
    if place and v.route and (v.leg or 1) == 1 then
        local here = ns.Here(v.route, ns.RunProgress(), place)
        if here then selected, flash = here, nil end
    end
    local shown
    if place == "ah" or place == "vendor" then shown = ns.SideShow(place)
    elseif ns.atAH then shown = ns.SideShow("ah") end
    if not shown then ns.SideHide() end
    ns.Refresh()
end

-- ---------- calculating without freezing the game ----------

-- Milliseconds of each frame the calculation may take.
local SLICE = 12
local runner
local driver = CreateFrame("Frame")
ns.calcDriver = driver
driver:Hide()
local function finish(err)
    runner = nil
    driver:Hide()
    if err and err ~= "cancelled" then
        ns.Print(L.CALC_FAIL)
        if geterrorhandler then geterrorhandler()(err) end
    end
    ns.Refresh()
end
driver:SetScript("OnUpdate", function()
    if not runner then driver:Hide(); return end
    local done, err = runner:Step(SLICE)
    if done then finish(err) else ns.Refresh() end
end)

-- Starts a calculation in steps; the window shows how far it is and the game keeps running.
local function start(r)
    if runner then runner:Cancel() end
    runner = r
    local done, err = runner:Step(SLICE)
    if done then finish(err) else driver:Show(); ns.Refresh() end
end
function ns.Calculate(flash)
    if runner then runner:Cancel() end
    start(ns.RecalcJob(flash and ns.view.plan ~= nil))
end

-- A route tile: the routes are all in the result already, so the switch is instant; only the
-- runs of a route not shown before are built, in steps, while its graph is already there.
function ns.ChooseMode(want)
    local P = ns.Prefs(ns.db.prefs)
    local level = true
    if ns.EARN[want] then level = P.level end
    if ns.BusyKind() ~= "all" and level == P.level then
        local ok, needLegs = ns.PickMode(want)
        if ok then
            ns.db.prefs.mode = want
            if needLegs then start(ns.LegsJob(ns.view.mode)) else
                if runner then runner:Cancel(); runner = nil; driver:Hide() end
                ns.Refresh()
            end
            return
        end
    end
    ns.SetPrefs({ mode = want, level = level })
end
function ns.StopCalc()
    if runner then runner:Cancel() end
    finish("cancelled")
end

-- Nothing is calculated before the first Calculate: the window opens at once. After that the
-- player's own changes recalculate in steps, and bags or prices only mark the result outdated.
function ns.Rebuild(flash, why)
    local v = ns.view
    if why == "open" then
        -- nothing new: the last result stays
    elseif why == "event" then
        if v.plan then v.stale = v.stale or true end
    elseif why == "pick" or why == "target" then
        -- another profession or target: nothing is calculated until the player asks
        if runner then runner:Cancel(); runner = nil; driver:Hide() end
        if why == "target" and v.plan then v.stale = "target" end
    elseif v.plan or runner then
        ns.Calculate(flash)
        return
    end
    ns.Refresh()
end

-- The window, for the hub (/gulli) to show inside it.
function ns.Window()
    if not frame then
        build()
        -- In the hub the window is shown by the hub, not by ns.Toggle.
        frame:HookScript("OnShow", function(self)
            if not self.docked then return end
            ns.Rebuild(false, "open")
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

-- The item tooltip: how many of it the chosen run needs, in the Gulli block (see S.TipCollect).
function ns.TipLines(id)
    local v = ns.view
    if not id or not v or not v.route or not v.state or #v.route == 0 then return {} end
    local n = ns.RunNeeds(v.state, v.route)[id]
    if not (n and n > 0) then return {} end
    return { { group = "craft", sub = true, icon = "Interface\\AddOns\\Gulli-CraftProfit\\icon",
               left = S.Emph(L.TOOLTIP_NEED:format(n)), color = S.MUTED } }
end
S.TipProvider("item", "CraftProfit", function(id, tip)
    if tip == GameTooltip or tip == ItemRefTooltip then return ns.TipLines(id) end
end)
