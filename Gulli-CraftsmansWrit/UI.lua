-- The window, narrow, with five tabs. Today: the camp's standing, what is ready to hand in and
-- what still lacks its item. Plan: a goal and a number of days, and the cheapest writs that reach
-- it, day by day, with every Coin Pouch taken off in plain sight (purchases - pouches = total).
-- Writs: every writ of the character's side. History: the writs handed in. Settings: the
-- switches and what the pouches paid. At the auction house it opens beside the auction window;
-- while it leads, a small tracker on the screen lists the customers to go to.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, tabs, pages = nil, nil, {}
local calcBtn, buyBtn, skipBtn, leadBtn
local repCard, repBar, repText, repSub, todayStats, todayCard, todayList, todayEmpty
local goalTabs, planCard, planStats, planList, planEmpty
local writTabs, sortTabs, writCard, writList, writFind, writEmpty
local stepStrip
local SORT_W = 170
local periodTabs, histStats, histList, histEmpty
local setCard, pouchStats, pouchNote, histCard
local tab, period, rankFilter = 1, "all", nil
local ROW, HEAD, HIST_ROW = 38, 26, 38

ns.ICON = "Interface\\AddOns\\Gulli-CraftsmansWrit\\icon"
local WRIT_ICON = "Interface\\Icons\\INV_Scroll_03"
local POUCH_ICON = "Interface\\Icons\\INV_Misc_Coin_02"
local REP_ICON = "Interface\\Icons\\INV_Misc_Ribbon_01"
local TIME_ICON = "Interface\\Icons\\INV_Misc_PocketWatch_01"
local AH_ICON = "Interface\\Minimap\\Tracking\\Auctioneer"
local MAP_ICON = "Interface\\Icons\\INV_Misc_Map_02"

-- What a row of the Today list says about its writ: a word and its colour.
local STATUS = {
    ready = { "ST_READY", "GOOD" },
    item = { "ST_ITEM", "WARN" },
    bank = { "ST_BANK", "WARN" },
    done = { "ST_DONE", "FAINT" },
}
local STATUS_ORDER = { ready = 1, item = 2, bank = 3, done = 4 }

local fmtDate = date or (os and os.date)

local function timeText(sec)
    if not sec then return "" end
    sec = math.max(0, math.floor(sec))
    local h, m = math.floor(sec / 3600), math.floor(sec / 60) % 60
    if h > 0 then return L.TIME_HM:format(h, m) end
    return L.TIME_M:format(m)
end
ns.TimeText = timeText

local function itemTip(owner, id)
    if not (GameTooltip and id) then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then GameTooltip:SetItemByID(id) else GameTooltip:AddLine(ns.DisplayName(id)) end
    GameTooltip:Show()
end
local function hideTip() if GameTooltip then GameTooltip:Hide() end end

local function profName(code) return L["PROF_" .. (code or "")] or code or "" end

-- A row of an item list: an icon, a name, a note under it, a value at the right and a word
-- under that. Reused by every list of the window.
local function makeRow(r)
    r:EnableMouse(true)
    r.icon = S.ItemIcon(r, 26)
    r.icon:SetPoint("LEFT", 2, 0)
    r.value = S.Text(r, 12)
    r.value:SetPoint("TOPRIGHT", -4, -4)
    r.value:SetJustifyH("RIGHT")
    r.value:SetWordWrap(false)
    r.sub = S.Text(r, 12, S.FAINT)
    r.sub:SetPoint("BOTTOMRIGHT", -4, 4)
    r.sub:SetJustifyH("RIGHT")
    r.name = S.Text(r, 12)
    r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, 2)
    r.name:SetPoint("RIGHT", r.value, "LEFT", -8, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.note = S.Text(r, 12, S.MUTED)
    r.note:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 8, -2)
    r.note:SetPoint("RIGHT", r.sub, "LEFT", -8, 0)
    r.note:SetJustifyH("LEFT")
    r.note:SetWordWrap(false)
    -- a header row of a list (a day of the plan, a group of Today)
    r.head = S.Text(r, 12, S.GOLD_DIM, nil, "bold")
    r.head:SetPoint("LEFT", 4, 0)
    r.head:SetPoint("RIGHT", -4, 0)
    r.head:SetJustifyH("LEFT")
    r.head:SetWordWrap(false)
    r:SetScript("OnEnter", function(self) if self.tip then itemTip(self, self.tip) end end)
    r:SetScript("OnLeave", hideTip)
end

local function asHead(r, text)
    r.tip = nil
    r.head:SetText(S.Upper(text))
    r.head:Show()
    for _, k in ipairs({ "icon", "value", "sub", "name", "note" }) do r[k]:Hide() end
end
local function asItem(r)
    r.head:Hide()
    for _, k in ipairs({ "icon", "value", "sub", "name", "note" }) do r[k]:Show() end
end

-- ---------- Today ----------

function ns.TodayRows(states)
    local list = {}
    for _, s in ipairs(states or ns.States()) do if s.status ~= "none" then list[#list + 1] = s end end
    table.sort(list, function(a, b)
        if a.status ~= b.status then return STATUS_ORDER[a.status] < STATUS_ORDER[b.status] end
        return a.w.id < b.w.id
    end)
    -- Each held writ carries what handing it in costs (the item less its pouch); a group's head
    -- adds them up while every one of them has a price.
    local rows, last, head = {}, nil, nil
    for _, s in ipairs(list) do
        if s.status ~= last then
            head = { head = L["GROUP_" .. s.status], cost = s.status ~= "done" and 0 or nil }
            rows[#rows + 1] = head
            last = s.status
        end
        local c = ns.CloseCost(s)
        if head.cost then
            if c and c.total then head.cost = head.cost + c.total; head.estimate = head.estimate or c.estimate
            else head.cost = nil end
        end
        rows[#rows + 1] = { s = s, close = c }
    end
    local sealed = ns.SealedHeld(ns.db and ns.db.bank)
    local any
    for _, r in ipairs(ns.RANKS) do
        if (sealed[r] or 0) > 0 then
            if not any then rows[#rows + 1] = { head = L.GROUP_sealed }; any = true end
            rows[#rows + 1] = { sealed = r, n = sealed[r] }
        end
    end
    return rows
end

local function fillToday(r, row)
    if row.head then
        asHead(r, row.head)
        if row.cost then r.head:SetText(S.Upper(row.head) .. S.DOT .. ns.CostText(row.cost, row.estimate)) end
        return
    end
    asItem(r)
    if row.sealed then
        local id = ns.SealedOf(row.sealed)
        r.tip = id
        r.icon:Set(ns.ItemIcon(id), row.n, 2)
        r.name:SetText(ns.DisplayName(id))
        r.note:SetText(L.SEALED_NOTE)
        r.value:SetText(L.TIP_REP:format(ns.REP[row.sealed]))
        r.sub:SetText(L["RANK_" .. row.sealed])
        return
    end
    local s, w = row.s, row.s.w
    r.tip = w.id
    r.icon:Set(ns.ItemIcon(w.id), s.bags > 1 and s.bags or nil, 1)
    local st = STATUS[s.status]
    r.name:SetText((s.status == "done" and S.Hex(S.FAINT) or "") .. ns.WritName(w) .. (s.status == "done" and "|r" or ""))
    local have = s.have + (ns.db.bank and s.haveBank or 0)
    local need = L.NEEDS:format(math.min(have, w.count), w.count, ns.ShortName(ns.DisplayName(w.item)))
    local who = ns.Customer(w)
    local spot = ns.Spot(w)
    local zone = spot and ns.ZoneName(spot.map)
    local note = s.status == "done" and profName(w.prof) or need
    if s.status ~= "done" and who then note = note .. S.DOT .. (zone and L.WHO_WHERE:format(who, zone) or who) end
    if s.status == "item" and s.haveBank > 0 and have >= w.count then note = need .. S.DOT .. S.Hex(S.WARN) .. L.FROM_BANK .. "|r" end
    r.note:SetText(note)
    local rep = L.TIP_REP:format(math.floor(w.rep * ns.Mult() + 0.5))
    if s.status == "done" then
        r.value:SetText(S.Hex(S.FAINT) .. rep .. "|r")
        r.sub:SetText(S.Hex(S.BAD) .. ns.DoneText() .. "|r")
        return
    end
    -- What handing it in costs from here (the group's head names the state); the tooltip splits it.
    local c = row.close
    r.value:SetText(c and c.total and ns.CostText(c.total, c.estimate) or (S.Hex(S.FAINT) .. L.NO_PRICE .. "|r"))
    r.sub:SetText(S.Hex(S[st[2]]) .. rep .. "|r")
end

-- ---------- Plan ----------

function ns.PlanRows(plan)
    local rows = {}
    if not plan then return rows end
    local ways = ns.Ways(plan)
    if #ways > 1 then rows[#rows + 1] = { ways = ways } end
    local day
    for _, l in ipairs(plan.lines) do
        if l.day ~= day then
            day = l.day
            local d = plan.byDay[day]
            rows[#rows + 1] = { head = L.DAY_HEAD:format(day, d.n, d.rep), cost = d.cost }
        end
        rows[#rows + 1] = { line = l }
    end
    if plan.short > 0 then rows[#rows + 1] = { short = plan.short } end
    return rows
end

-- "Writ 2g · Item 1g 20s · - Pouch 35s": every part of a line's cost, the pouch always shown.
function ns.LineParts(l)
    local parts = {}
    if l.writFrom == "own" then parts[#parts + 1] = L.PART_WRIT_OWN
    else parts[#parts + 1] = L.PART_WRIT:format(S.MoneyText(l.writ, true)) end
    if l.kind == "sealed" then parts[#parts + 1] = L.PART_ITEM_EST:format(S.MoneyText(l.item, true))
    elseif l.item == 0 then parts[#parts + 1] = L.PART_ITEM_OWN
    else parts[#parts + 1] = L.PART_ITEM:format(S.MoneyText(l.item, true)) end
    if l.pouch > 0 then parts[#parts + 1] = S.Hex(S.GOOD) .. L.PART_POUCH:format(S.MoneyText(l.pouch, true)) .. "|r" end
    return table.concat(parts, S.DOT)
end

-- A line's cost at the right: what it costs, or what it pays when the pouch is worth more.
function ns.CostText(cost, estimate, short)
    if cost < 0 then return S.Hex(S.GOOD) .. "+|r" .. S.MoneyText(-cost, short) end
    if cost > 0 then return S.Hex(S.BAD) .. "-|r" .. S.MoneyText(cost, short) end
    return S.MoneyText(0, short)
end

local function planHeight(row)
    if row.head then return HEAD end
    return ROW
end

local function fillPlan(r, row)
    if row.head then
        asHead(r, row.head)
        r.head:SetText(S.Upper(row.head) .. S.DOT .. ns.CostText(row.cost))
        return
    end
    asItem(r)
    r.tip = nil
    if row.ways then
        r.icon:Set(REP_ICON, nil, 1)
        r.name:SetText(L.WAYS)
        local parts = {}
        for i, w in ipairs(row.ways) do
            if i > 3 then break end
            parts[#parts + 1] = L[w.key] .. " " .. ns.CostText(w.cost, w.estimate, true)
        end
        r.note:SetText(table.concat(parts, S.DOT))
        r.value:SetText("")
        r.sub:SetText("")
        return
    end
    if row.short then
        r.icon:Set("Interface\\Icons\\INV_Misc_QuestionMark", nil, 1)
        r.name:SetText(S.Hex(S.WARN) .. L.SHORT:format(row.short) .. "|r")
        r.note:SetText(L.SHORT_SUB)
        r.value:SetText("")
        r.sub:SetText("")
        return
    end
    local l = row.line
    local cur = ns.Current()
    local buying = cur and (cur.id == l.id or (l.w and cur.id == l.w.item))
    if l.kind == "sealed" then
        r.tip = l.id
        r.icon:Set(ns.ItemIcon(l.id), nil, 2)
        r.name:SetText(ns.DisplayName(l.id))
    else
        r.tip = l.id
        r.icon:Set(ns.ItemIcon(l.id), l.k > 1 and l.k or nil, 1)
        local c = buying and S.Accent() or S.TEXT
        r.name:SetText(S.Hex(c) .. ns.WritName(l.w) .. "|r")
    end
    r.note:SetText(ns.LineParts(l))
    r.value:SetText(ns.CostText(l.cost, l.estimate))
    r.sub:SetText(l.cost < 0 and (S.Hex(S.GOOD) .. L.PROFIT .. "|r") or (S.Hex(S.BAD) .. L.LOSS .. "|r"))
end

-- ---------- Writs ----------

-- sort "gain" (the default): the best gain first, the dearest last, writs without a price at
-- the end; "prof": the data's order, by profession.
-- Lower case, Cyrillic too, so a search finds "Хинтерланд" by "хинтерланд".
function ns.Fold(text)
    local s = tostring(text or ""):lower()
    s = s:gsub("\208([\144-\159])", function(c) return "\208" .. string.char(c:byte() + 32) end)
    s = s:gsub("\208([\160-\175])", function(c) return "\209" .. string.char(c:byte() - 32) end)
    s = s:gsub("\208\129", "\209\145")
    return s
end

-- Does a writ match the search? Every word of it must be in the writ's name, the item it asks
-- for, its trade, its rank, the customer or the zone the customer stands in.
function ns.WritMatches(w, text)
    local words = {}
    for word in ns.Fold(text):gmatch("%S+") do words[#words + 1] = word end
    if #words == 0 then return true end
    local spot = ns.Spot(w)
    local hay = ns.Fold(table.concat({ ns.WritName(w), ns.DisplayName(w.item), profName(w.prof),
        L["RANK_" .. w.rank] or "", ns.Customer(w) or "", spot and ns.ZoneName(spot.map) or "" }, "\n"))
    for _, word in ipairs(words) do
        if not hay:find(word, 1, true) then return false end
    end
    return true
end

function ns.WritRows(rank, sort, text)
    local rows = {}
    for _, w in ipairs(ns.Writs()) do
        if (not rank or w.rank == rank) and ns.WritMatches(w, text) then rows[#rows + 1] = w end
    end
    if (sort or (ns.db and ns.db.writSort) or "gain") == "gain" then
        local cost, at = {}, {}
        for i, w in ipairs(rows) do cost[w] = ns.CostOf(w, ns.db and ns.db.bank).total; at[w] = i end
        table.sort(rows, function(a, b)
            local x, y = cost[a], cost[b]
            if x and y and x ~= y then return x < y end
            if (x == nil) ~= (y == nil) then return x ~= nil end
            return at[a] < at[b]
        end)
    end
    return rows
end

local function fillWrit(r, w)
    asItem(r)
    r.tip = w.id
    local s = ns.StateOf(w)
    r.icon:Set(ns.ItemIcon(w.id), s.bags + s.bank > 0 and (s.bags + s.bank) or nil, 1)
    r.name:SetText(ns.WritName(w))
    local who = ns.Customer(w)
    local spot = ns.Spot(w)
    local zone = spot and ns.ZoneName(spot.map)
    local note = profName(w.prof)
    if who then note = note .. S.DOT .. (zone and L.WHO_WHERE:format(who, zone) or who)
    else note = note .. S.DOT .. S.Hex(S.FAINT) .. L.NO_SPOT .. "|r" end
    r.note:SetText(note)
    local c = ns.CostOf(w, ns.db.bank)
    r.value:SetText(c.total and ns.CostText(c.total, true) or (S.Hex(S.FAINT) .. L.NO_PRICE .. "|r"))
    r.sub:SetText(s.done and (S.Hex(S.BAD) .. ns.DoneText() .. "|r") or L.TIP_REP:format(math.floor(w.rep * ns.Mult() + 0.5)))
end

-- ---------- History ----------

local function fillHist(r, e)
    asItem(r)
    local w = ns.Writ(e.writ)
    r.tip = e.writ
    r.icon:Set(ns.ItemIcon(e.writ), nil, 1)
    r.name:SetText(w and ns.WritName(w) or ns.DisplayName(e.writ))
    r.note:SetText((fmtDate and fmtDate(L.DATE, e.at) or "") .. (e.who and (S.DOT .. e.who) or ""))
    local net = (e.paid or 0) - (e.pouch or 0)
    r.value:SetText(ns.CostText(net))
    r.sub:SetText(L.TIP_REP:format(e.rep or 0))
end

-- ---------- footer ----------

local function label(b, text, min)
    b:SetText(text)
    b:SetWidth(math.max(min, math.floor((b.text:GetStringWidth() or 0) + 28)))
end

local function lineText(line)
    if not line then return "" end
    return ns.Left(line) .. " x " .. ns.ShortName(ns.DisplayName(line.id))
end

local function buyText()
    local b, line = ns.buy, ns.Current()
    if b.phase == "done" or not line then return L.BUY_DONE end
    if b.phase == "quote" then return L.BUY_WAIT end
    if b.phase == "buying" then return L.BUY_BUYING end
    if b.phase == "ready" then return L.BUY_CONFIRM:format(S.MoneyIcons(b.quote.total, true)) end
    return L.BUY_ASK
end

local function buyStatus(plan)
    local b, queue = ns.buy, ns.buy.queue
    if ns.Scanning() then return L.SCANNING:format(math.min(ns.scan.done + 1, ns.scan.n), ns.scan.n), S.Accent() end
    if not ns.HasPrices() then return L.NO_PRICES, S.WARN end
    if not plan then return L.HOW end
    if ns.stale then return L.STALE, S.WARN end
    if plan.need == 0 then return L.AT_GOAL, S.GOOD end
    if #queue == 0 then return L.NOTHING_TO_BUY, S.GOOD end
    if b.phase == "done" then return L.BUY_DONE .. ": " .. S.MoneyText(b.spent), S.GOOD end
    if not ns.atAH then return plan.estimate and L.ESTIMATE or L.NOT_AT_AH, S.WARN end
    if b.err then return lineText(ns.Current()) .. ": " .. L[b.err], S.BAD end
    if b.phase == "ready" and ns.Dear() then return lineText(ns.Current()) .. ": " .. L.DEAR, S.WARN end
    return lineText(ns.Current())
end

-- ---------- the buying steps ----------
-- Over the status line: the step the Buy button is at (one writ type: its writs, then its item)
-- and a node per copy, one a day: filled green when the bags hold it or it was bought here, the
-- next one to buy ringed in the accent, the rest hollow.

local DOT_MAX, DOT_MIN = 10, 4

local function makeDots(parent)
    local g = CreateFrame("Frame", nil, parent)
    g:SetHeight(18)
    g.icon = S.IconBox(g, 18)
    g.icon:SetPoint("LEFT")
    g.dots = {}
    function g:Set(icon, done, of, current, width)
        self.icon:SetIcon(icon)
        local room = width - 26
        local size = math.max(DOT_MIN, math.min(DOT_MAX, math.floor(room / math.max(1, of)) - 3))
        local gap = size >= 8 and 4 or 2
        for i = 1, math.max(of, #self.dots) do
            local d = self.dots[i]
            if i <= of and not d then
                d = { ring = S.Circle(self, size, S.FAINT, "ARTWORK", 1), fill = S.Circle(self, size - 2, S.BG, "ARTWORK", 2) }
                self.dots[i] = d
            end
            if d then
                local show = i <= of
                d.ring:SetShown(show)
                d.fill:SetShown(show)
                if show then
                    d.ring:SetSize(size, size)
                    d.fill:SetSize(size - 2, size - 2)
                    d.ring:ClearAllPoints()
                    d.ring:SetPoint("LEFT", 26 + (i - 1) * (size + gap), 0)
                    d.fill:ClearAllPoints()
                    d.fill:SetPoint("CENTER", d.ring)
                    local ring, fill = S.FAINT, S.BG
                    if i <= done then ring, fill = S.GOOD, S.GOOD
                    elseif current and i == done + 1 then ring = S.Accent() end
                    d.ring:SetVertexColor(ring[1], ring[2], ring[3], ring[4] or 1)
                    d.fill:SetVertexColor(fill[1], fill[2], fill[3], fill[4] or 1)
                    d.done = i <= done
                end
            end
        end
        self:SetWidth(26 + of * (size + gap))
    end
    return g
end

local function buildSteps(ft)
    local f = CreateFrame("Frame", nil, ft)
    f:SetHeight(18)
    f:SetPoint("TOPLEFT", S.PAD, -8)
    f:SetPoint("TOPRIGHT", -S.PAD, -8)
    f:EnableMouse(true)
    f.label = S.Text(f, 12, S.GOLD_DIM, nil, "bold")
    f.label:SetPoint("LEFT")
    f.label:SetWordWrap(false)
    f.writ = makeDots(f)
    f.item = makeDots(f)
    f:SetScript("OnEnter", function(self)
        if not (GameTooltip and self.lines) then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        for i, l in ipairs(self.lines) do
            if i == 1 then GameTooltip:AddLine(l, 1, 0.82, 0) else GameTooltip:AddLine(l, 1, 1, 1) end
        end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", hideTip)
    return f
end

-- What the strip shows now: the current line's step, or the last one when all is bought.
function ns.StepView()
    local b = ns.buy
    if not ns.plan or ns.stale or not b.steps or #b.steps == 0 or #b.queue == 0 then return nil end
    local line = ns.Current() or b.queue[#b.queue]
    local i, of = ns.StepOf(line)
    if not i then return nil end
    local s = b.steps[i]
    local nodes = ns.StepNodes(s)
    return { i = i, of = of, step = s, nodes = nodes, part = b.phase ~= "done" and line.part or nil }
end

local function refreshSteps()
    local v = tab == 2 and ns.StepView()
    stepStrip:SetShown(v and true or false)
    if not v then return end
    local f = stepStrip
    f.label:SetText(S.Upper(L.STEP:format(v.i, v.of)))
    local width = (f:GetWidth() or 480)
    if width < 100 then width = 480 end
    local room = width - (f.label:GetStringWidth() or 80) - 16
    local s, n = v.step, v.nodes
    local itemName = s.item and ns.ShortName(ns.DisplayName(s.item.id))
    f.writ:ClearAllPoints()
    f.writ:SetPoint("LEFT", f.label, "RIGHT", 12, 0)
    f.writ:Set(ns.ItemIcon(s.id), n.writ.done, n.writ.of, v.part == "writ", n.item and math.floor(room / 2) - 8 or room)
    f.item:SetShown(n.item ~= nil)
    if n.item then
        f.item:ClearAllPoints()
        f.item:SetPoint("LEFT", f.writ, "RIGHT", 16, 0)
        f.item:Set(ns.ItemIcon(s.item.id), n.item.done, n.item.of, v.part == "item", math.floor(room / 2) - 8)
    end
    f.lines = { s.kind == "sealed" and ns.DisplayName(s.id) or ns.WritName(s.w),
                L.NODE_WRITS:format(n.writ.done, n.writ.of) }
    if n.item then f.lines[3] = L.NODE_ITEM:format(itemName, n.item.done, n.item.of) end
end

local function refreshFooter()
    -- only Today and Plan have actions: the other tabs give the footer's place to their lists
    frame.footer:SetShown(tab <= 2)
    if ns.FitFooter then ns.FitFooter() end
    refreshSteps()
    local onPlan = tab == 2
    local plan = ns.plan
    local b = ns.buy
    calcBtn:SetShown(onPlan)
    buyBtn:SetShown(onPlan)
    leadBtn:SetShown(tab == 1)
    skipBtn:SetShown(onPlan and plan ~= nil and ns.Current() ~= nil and b.phase ~= "done" and ns.atAH)
    if tab == 1 then
        local n = #ns.Stops()
        label(leadBtn, ns.Guiding() and L.STOP_LEAD or L.LEAD:format(n), 140)
        leadBtn:SetEnabled(ns.Guiding() or n > 0)
        local t = ns.Today()
        frame.footer:SetStatus(t.ready > 0 and L.READY_LINE:format(t.ready, t.readyRep) or L.TODAY_HOW,
            t.ready > 0 and S.GOOD or nil)
        return
    end
    if not onPlan then frame.footer:SetStatus(""); return end
    local calculating, share = ns.Calculating()
    local busy = b.phase == "quote" or b.phase == "buying" or ns.Scanning() or calculating
    label(calcBtn, calculating and L.CALC_BUSY:format(math.floor(share * 100)) or (plan and L.RECALC or L.CALCULATE), 110)
    calcBtn:SetEnabled(not ns.Scanning() and not ns.Busy() and not calculating)
    label(buyBtn, buyText(), 160)
    buyBtn:SetEnabled(plan ~= nil and not ns.stale and #b.queue > 0 and b.phase ~= "done" and not busy
        and ns.atAH and ns.CanBuy())
    if calculating then frame.footer:SetStatus(L.CALC_LINE:format(math.floor(share * 100)), S.Accent())
    else frame.footer:SetStatus(buyStatus(plan)) end
end

-- ---------- refresh ----------

local function refreshToday()
    local rep = ns.Rep()
    local need, goal = ns.Need(rep, 0)
    if rep then
        local from = ns.REACTION_AT[goal - 1] or 0
        local to = ns.REACTION_AT[goal] or from
        local frac = to > from and (rep.value - from) / (to - from) or 1
        repCard:SetTitle(rep.name or L.CAMP, L["STAND_" .. (rep.reaction or 4)] or "")
        repBar:Set(math.max(0, math.min(1, frac)))
        repText:SetText(rep.reaction >= 8 and L.EXALTED_DONE
            or L.REP_TO:format(S.Emph(tostring(need)), L["STAND_" .. goal] or ""))
    else
        repCard:SetTitle(L.CAMP, "")
        repBar:Set(0)
        repText:SetText(L.NO_REP)
    end
    repSub:SetText(L.RESET_IN:format(timeText(ns.ResetIn())))
    local states = ns.States()
    local t = ns.Today(states)
    todayStats.tiles[1]:Set(tostring(t.ready), t.ready > 0 and S.GOOD or nil)
    todayStats.tiles[2]:Set(tostring(t.item), t.item > 0 and S.WARN or nil)
    todayStats.tiles[3]:Set(S.MoneyText(t.pouchGold, true))
    local rows = ns.TodayRows(states)
    todayList:SetData(rows)
    todayEmpty:SetShown(#rows == 0)
end

local function refreshPlan()
    goalTabs.sync()
    planCard.days:Refresh()
    local plan = ns.plan
    -- as money flows: what the purchases take (red), what the pouches give back (green), the sum
    planStats.tiles[1]:Set(plan and ns.CostText(plan.buy, nil, true) or "-")
    planStats.tiles[2]:Set(plan and ns.CostText(-plan.pouch, nil, true) or "-")
    planStats.tiles[3]:Set(plan and ns.CostText(plan.total, plan.estimate) or "-")
    planList:SetData(ns.PlanRows(plan))
    planEmpty:SetShown(not plan or #plan.lines == 0)
    if plan and plan.need == 0 then planEmpty:Set(L.AT_GOAL, L.AT_GOAL_SUB)
    elseif plan then planEmpty:Set(L.PLAN_NONE, L.PLAN_NONE_SUB)
    else planEmpty:Set(L.PLAN_EMPTY, L.PLAN_EMPTY_SUB) end
    planCard:SetTitle(L.PLAN, plan and #plan.lines > 0 and L.PLAN_HINT:format(plan.rep, plan.days) or "")
    local calculating, share = ns.Calculating()
    planCard.calcBar:SetShown(calculating)
    if calculating then
        planCard.calcBar:Set(share)
        planCard.calcWatch:Show()
    end
end

local function refreshWrits()
    local text = writFind and writFind:GetText() or ""
    local rows = ns.WritRows(rankFilter, ns.db.writSort, text)
    writList:SetData(rows)
    writEmpty:SetShown(#rows == 0)
    writCard:SetTitle(L.WRITS, tostring(#rows))
end

local function refreshHistory()
    local list, sum = ns.History(period)
    histList:SetData(list)
    histEmpty:SetShown(#list == 0)
    histStats.tiles[1]:Set(tostring(sum.count))
    histStats.tiles[2]:Set(S.Hex(S.GOOD) .. "-" .. "|r" .. S.MoneyText(sum.pouch, true))
    histStats.tiles[3]:Set(ns.CostText(sum.per100, false, true))
    histCard:SetTitle(L.HISTORY, sum.rep > 0 and L.TIP_REP:format(sum.rep) or "")
end

local function refreshSettings()
    for _, row in ipairs(setCard.rows or {}) do if row.control and row.control.Refresh then row.control:Refresh() end end
    local seen = 0
    for i, r in ipairs(ns.RANKS) do
        local avg, n = ns.PouchAvg(r)
        seen = seen + n
        pouchStats.tiles[i]:Set(S.MoneyText(avg, true))
    end
    pouchNote:SetText(L.POUCHES_SUB .. " " .. L.TIP_POUCH_SEEN:format(seen))
end

local function refreshTab()
    if tab == 1 then refreshToday()
    elseif tab == 2 then refreshPlan()
    elseif tab == 3 then refreshWrits()
    elseif tab == 4 then refreshHistory()
    else refreshSettings() end
    refreshFooter()
end

function ns.Refresh()
    S.SideRefresh()
    if ns.RefreshTracker and ns.guide then ns.RefreshTracker() end
    if not frame or not frame:IsShown() then return end
    -- how long it took, for /gcw perf
    ns.perf.redraw, ns.perf.tab = S.Timed(refreshTab), tab
end

-- ---------- build ----------

local function listCard(parent, title, icon, make, fill, heightOf)
    local card = S.Card(parent, title, "", icon)
    local list = S.List(card.body, ROW, make, fill)
    list:SetPoint("TOPLEFT")
    list:SetPoint("BOTTOMRIGHT", -10, 0)
    if heightOf then list.heightOf = heightOf end
    return card, list
end

local function goalLabels()
    local out = { L.GOAL_NEXT }
    for _, g in ipairs(ns.GOALS) do out[#out + 1] = L["STAND_" .. g] end
    return out
end

local function build()
    frame = S.Window("GulliCraftsmansWritFrame", L.TITLE, S.NARROW_W, S.DOCK_H)
    local ft = S.Footer(frame)
    buyBtn = S.Primary(S.Button(ft, 200, 32))
    ft:Add(buyBtn)
    buyBtn:SetScript("OnClick", function() ns.BuyClick() end)
    calcBtn = S.Button(ft, 120, 32)
    ft:Add(calcBtn)
    label(calcBtn, L.CALCULATE, 110)
    calcBtn:SetScript("OnClick", function() ns.Calculate() end)
    skipBtn = S.Ghost(S.Button(ft, 80, 32))
    ft:Add(skipBtn)
    label(skipBtn, L.SKIP, 72)
    skipBtn:SetScript("OnClick", function() ns.Skip() end)
    leadBtn = S.Primary(S.Button(ft, 160, 32))
    leadBtn:SetPoint("BOTTOMRIGHT", -S.PAD, 12)
    leadBtn:SetScript("OnClick", function()
        if ns.Guiding() then ns.StopGuide() elseif not ns.StartGuide() then ns.Say(L.GUIDE_NONE) end
        ns.Refresh()
    end)
    -- the status line takes the whole width above the buttons, so its long texts are never cut
    local extra = 56
    ft:SetHeight(S.FOOTER_H + extra)
    stepStrip = buildSteps(ft)
    ft.status:ClearAllPoints()
    ft.status:SetPoint("TOPLEFT", S.PAD, -30)
    ft.status:SetPoint("TOPRIGHT", -S.PAD, -30)
    ft.status:SetHeight(extra - 22)
    ft.status:SetJustifyV("TOP")
    buyBtn:ClearAllPoints()
    buyBtn:SetPoint("BOTTOMRIGHT", -S.PAD, 12)
    -- the step strip shows only on the Plan tab: elsewhere the status line moves up and the
    -- footer is lower, so the lists keep that room
    local function fit(self)
        local steps = tab == 2
        ft:SetHeight(S.FOOTER_H + (steps and extra or 38))
        ft.status:SetPoint("TOPLEFT", S.PAD, steps and -30 or -8)
        ft.status:SetPoint("TOPRIGHT", -S.PAD, steps and -30 or -8)
        frame.body:SetPoint("BOTTOMRIGHT", -S.PAD, (self:IsShown() and ft:GetHeight() or 0) + S.PAD)
    end
    ns.FitFooter = function() fit(ft) end
    ft:HookScript("OnShow", fit)
    ft:HookScript("OnHide", fit)
    fit(ft)
    frame.inner[2] = frame.inner[2] - extra
    local W = frame.inner[1]

    tabs = S.PageTabs(frame.body, { L.TAB_TODAY, L.TAB_PLAN, L.TAB_WRITS, L.TAB_HISTORY, L.TAB_SETTINGS }, nil, function(i)
        tab = i
        for j, p in ipairs(pages) do p:SetShown(j == i) end
        ns.Refresh()
    end, nil, { TIME_ICON, AH_ICON, WRIT_ICON, S.TAB.recent, S.TAB.settings })
    for i = 1, 5 do
        local p = CreateFrame("Frame", nil, frame.body)
        p:SetPoint("TOPLEFT", 0, -30 - S.GAP)
        p:SetPoint("BOTTOMRIGHT")
        p:SetShown(i == 1)
        pages[i] = p
    end

    -- Today
    local tp = pages[1]
    local st = S.Stack(tp)
    repCard = S.Card(tp, L.CAMP, "", REP_ICON)
    repBar = S.Progress(repCard.body, 8)
    repBar:SetPoint("TOPLEFT", 0, -2)
    repBar:SetPoint("TOPRIGHT", 0, -2)
    repText = S.Text(repCard.body, 12)
    repText:SetPoint("TOPLEFT", 0, -16)
    repText:SetPoint("RIGHT", -150, 0)
    repText:SetJustifyH("LEFT")
    repText:SetWordWrap(false)
    repSub = S.Text(repCard.body, 12, S.MUTED)
    repSub:SetPoint("TOPRIGHT", 0, -16)
    repSub:SetJustifyH("RIGHT")
    st:Add(repCard, repCard:Fit(34))
    todayStats = S.StatRow(tp, { L.ST_READY, L.ST_ITEM, L.ST_POUCH_TODAY }, 62,
        { WRIT_ICON, "Interface\\Icons\\Trade_BlackSmithing", POUCH_ICON })
    st:Add(todayStats, 62)
    todayStats:Layout(W)
    todayCard, todayList = listCard(tp, L.TODAY, WRIT_ICON, makeRow, fillToday,
        function(row) return row.head and HEAD or ROW end)
    todayCard:SetPoint("TOPLEFT", 0, -st.y)
    todayCard:SetPoint("BOTTOMRIGHT")
    todayEmpty = S.Empty(todayList)
    todayEmpty:Set(L.TODAY_EMPTY, L.TODAY_EMPTY_SUB)

    -- Plan
    local pp = pages[2]
    local ps = S.Stack(pp)
    goalTabs = S.Tabs(pp, goalLabels(), nil, function(i) ns.SetPref("goal", i == 1 and 0 or ns.GOALS[i - 1]) end, 28)
    goalTabs.frame:ClearAllPoints()
    goalTabs.frame:SetPoint("TOPLEFT")
    goalTabs.frame:SetPoint("TOPRIGHT")
    function goalTabs.sync()
        local want = 1
        for i, g in ipairs(ns.GOALS) do if g == ns.db.goal then want = i + 1 end end
        if goalTabs.selected ~= want then goalTabs:Select(want, true) end
    end
    ps:Space(28 + S.GAP)
    local days = S.Stepper(pp, function() return ns.db.days end, function(v) ns.SetPref("days", v) end,
        1, 1, ns.DAYS_MAX, nil, 130)
    local dayCard, h = S.SettingsCard(pp, nil, { { L.OPT_days, nil, control = days, icon = TIME_ICON } })
    ps:Add(dayCard, h)
    planStats = S.StatRow(pp, { L.ST_BUY, L.ST_POUCHES, L.ST_TOTAL }, 62, { AH_ICON, POUCH_ICON, REP_ICON })
    ps:Add(planStats, 62)
    planStats:Layout(W)
    planCard, planList = listCard(pp, L.PLAN, AH_ICON, makeRow, fillPlan, planHeight)
    planCard.days = days
    planCard:SetPoint("TOPLEFT", 0, -ps.y)
    planCard:SetPoint("BOTTOMRIGHT")
    planEmpty = S.Empty(planList)
    planEmpty:Set(L.PLAN_EMPTY, L.PLAN_EMPTY_SUB)
    -- while a plan is calculated: a moving bar over the list, the share on the button and the
    -- status line, drawn each frame; the list keeps the last plan meanwhile
    planCard.calcBar = S.Progress(planCard, 6)
    planCard.calcBar:SetPoint("TOPLEFT", planCard, "TOPLEFT", S.INSET, -34)
    planCard.calcBar:SetPoint("TOPRIGHT", planCard, "TOPRIGHT", -S.INSET, -34)
    planCard.calcBar:SetFrameLevel((tonumber(planCard:GetFrameLevel()) or 1) + 20)
    planCard.calcBar:Hide()
    planCard.calcWatch = CreateFrame("Frame", nil, frame)
    planCard.calcWatch:Hide()
    planCard.calcWatch:SetScript("OnUpdate", function(self)
        local calculating, share = ns.Calculating()
        if not calculating then self:Hide(); return end
        if tab ~= 2 or not frame:IsShown() then return end
        planCard.calcBar:Set(share)
        label(calcBtn, L.CALC_BUSY:format(math.floor(share * 100)), 110)
        frame.footer:SetStatus(L.CALC_LINE:format(math.floor(share * 100)), S.Accent())
    end)

    -- Writs
    local wp = pages[3]
    writTabs = S.Tabs(wp, { L.ALL, L.RANK_J, L.RANK_E, L.RANK_A }, nil, function(i)
        rankFilter = i > 1 and ns.RANKS[i - 1] or nil
        ns.Refresh()
    end, 28)
    writTabs.frame:ClearAllPoints()
    writTabs.frame:SetPoint("TOPLEFT")
    writTabs.frame:SetPoint("TOPRIGHT", -(SORT_W + S.GAP), 0)
    local sorts = { "gain", "prof" }
    sortTabs = S.Tabs(wp, { L.SORT_GAIN, L.SORT_PROF }, nil, function(i)
        ns.db.writSort = sorts[i]
        ns.Refresh()
    end, 28)
    sortTabs.frame:ClearAllPoints()
    sortTabs.frame:SetPoint("TOPRIGHT")
    sortTabs.frame:SetWidth(SORT_W)
    sortTabs:Select(ns.db.writSort == "prof" and 2 or 1, true)
    writFind = S.Edit(wp, 100, 28)
    writFind:SetPoint("TOPLEFT", 0, -(28 + S.GAP))
    writFind:SetPoint("TOPRIGHT", 0, -(28 + S.GAP))
    writFind:SetJustifyH("LEFT")
    S.Placeholder(writFind, L.WRIT_FIND)
    writFind:SetScript("OnTextChanged", function() ns.Refresh() end)
    writFind:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    writCard, writList = listCard(wp, L.WRITS, WRIT_ICON, makeRow, fillWrit)
    writCard:SetPoint("TOPLEFT", 0, -2 * (28 + S.GAP))
    writCard:SetPoint("BOTTOMRIGHT")
    writEmpty = S.Empty(writList)
    writEmpty:Set(L.FIND_NONE, "")

    -- History
    local hp = pages[4]
    local hs = S.Stack(hp)
    periodTabs = S.Tabs(hp, { L.PERIOD_day, L.PERIOD_week, L.PERIOD_all }, nil, function(i)
        period = ns.PERIODS[i]
        ns.Refresh()
    end, 28)
    periodTabs:Select(3, true)
    periodTabs.frame:ClearAllPoints()
    periodTabs.frame:SetPoint("TOPLEFT")
    hs:Space(28 + S.GAP)
    histStats = S.StatRow(hp, { L.ST_COUNT, L.ST_POUCHES, L.ST_PER100 }, 62,
        { WRIT_ICON, POUCH_ICON, AH_ICON })
    hs:Add(histStats, 62)
    histStats:Layout(W)
    histCard, histList = listCard(hp, L.HISTORY, S.TAB.recent, makeRow, fillHist)
    histList.step = HIST_ROW
    histCard:SetPoint("TOPLEFT", 0, -hs.y)
    histCard:SetPoint("BOTTOMRIGHT")
    histEmpty = S.Empty(histList)
    histEmpty:Set(L.HIST_EMPTY, L.HIST_EMPTY_SUB)

    -- Settings
    local sp = S.ScrollPage(pages[5], W)
    sp:SetAllPoints()
    local ss = S.Stack(sp.inner)
    local rows = {}
    for _, key in ipairs({ "auto", "bank", "sealed", "pouch", "live", "tooltip" }) do
        rows[#rows + 1] = { L["OPT_" .. key], L["TIP_" .. key], function() return ns.db[key] end,
                            function(v) ns.SetPref(key, v) end, icon = ns.OPT_ICON[key] }
    end
    setCard, h = S.SettingsCard(sp.inner, nil, rows)
    ss:Add(setCard, h)
    local pouchCard = S.Card(sp.inner, L.POUCHES, "", POUCH_ICON)
    pouchStats = S.StatRow(pouchCard.body, { L.RANK_J, L.RANK_E, L.RANK_A }, 62, { POUCH_ICON, POUCH_ICON, POUCH_ICON })
    pouchStats:SetPoint("TOPLEFT")
    pouchStats:SetPoint("TOPRIGHT")
    pouchStats:Layout(W - 2 * S.INSET - 10)
    pouchNote = S.Text(pouchCard.body, 12, S.MUTED)
    pouchNote:SetPoint("TOPLEFT", 0, -62 - S.GAP)
    pouchNote:SetPoint("RIGHT")
    pouchNote:SetJustifyH("LEFT")
    pouchNote:SetText(L.POUCHES_SUB)
    ss:Add(pouchCard, pouchCard:Fit(62 + S.GAP + 52))
    sp:SetContent(ss.y)

    frame:SetScript("OnShow", function() if ns.Prefetch then ns.Prefetch() end; ns.Refresh(); ns.TickClock() end)
end

function ns.Toggle()
    local open, shown = S.SideIs("CraftsmansWrit")
    if open and not shown then S.SideOpen("CraftsmansWrit", true); ns.Refresh(); return end
    S.ToggleWindow(ns.Window())
end

-- Opens a tab: 1 Today, 2 Plan, 3 Writs, 4 History, 5 Settings.
function ns.ShowTab(i)
    local w = ns.Window()
    if not w:IsShown() and not w.docked then S.ToggleWindow(w) end
    tabs:Select(i)
end
function ns.Tab() return tab end

-- Once a minute while the window shows, so "Again in 4 h 33 min" and the reset line count down.
function ns.TickClock()
    if ns.clock or not (C_Timer and C_Timer.After) then return end
    ns.clock = true
    C_Timer.After(60, function()
        ns.clock = nil
        if frame and frame:IsShown() then ns.Refresh(); ns.TickClock() end
    end)
end

function ns.Window()
    if not frame then build() end
    return frame
end

function ns.ShowAtAH()
    local w = ns.Window()
    if w.docked then if w:IsShown() then ns.Refresh() end return end
    ns.byAH = true
    S.SideOpen("CraftsmansWrit")
    tabs:Select(2)
    ns.Refresh()
end

function ns.HideAtAH()
    ns.byAH = false
    S.SideClose("CraftsmansWrit")
    ns.Refresh()
end

-- The lines the Buy button still has to buy: the number on the tab.
function ns.LinesLeft()
    local b = ns.buy
    if not ns.plan or not b or not b.queue or b.phase == "done" then return 0 end
    return math.max(0, #b.queue - (b.i or 1) + 1)
end

S.SideAdd({ key = "CraftsmansWrit", order = 15, title = function() return L.TITLE end, icon = ns.ICON,
            window = function() return ns.Window() end, badge = function() return ns.LinesLeft() end,
            closed = function() ns.byAH = false end })

-- ---------- the tracker on the screen ----------

local TW, T_HEAD, T_ROW = 290, 28, 44
local tracker

function ns.PlaceTracker()
    if not tracker then return end
    tracker:ClearAllPoints()
    local p = ns.db and ns.db.trackerPoint
    if p then tracker:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
    else tracker:SetPoint("RIGHT", UIParent, "RIGHT", -260, -120) end
end

-- The tracker's rows: one per customer, nearest first; the one the pin is on is first.
function ns.TrackerItems()
    local out = {}
    for i, st in ipairs(ns.stops or {}) do
        if i > ns.TRACK_MAX then break end
        local names = {}
        for _, w in ipairs(st.writs) do names[#names + 1] = ns.WritName(w) end
        out[#out + 1] = { first = st == ns.stop, who = st.who or L.UNKNOWN_SPOT, zone = st.zone,
                          what = table.concat(names, ", "), rep = st.rep, stop = st, icon = st.writs[1].id }
    end
    return out
end

local function trackerRow(parent)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(T_ROW)
    r.icon = S.IconBox(r, 24)
    r.icon:SetPoint("TOPLEFT", 8, -8)
    r.pin = CreateFrame("Button", nil, r)
    r.pin:SetSize(22, 22)
    r.pin:SetPoint("TOPRIGHT", -6, -6)
    r.pin.icon = S.IconBox(r.pin, 22, MAP_ICON)
    r.pin.icon:SetAllPoints()
    r.pin:SetScript("OnClick", function(self)
        local it = self:GetParent().item
        if it and it.stop then ns.SetPin(it.stop, true) end
    end)
    local function text(y, c)
        local t = S.Text(r, 12, c)
        t:SetPoint("TOPLEFT", 40, y)
        t:SetPoint("RIGHT", -32, 0)
        t:SetJustifyH("LEFT")
        t:SetWordWrap(false)
        return t
    end
    r.name = text(-6)
    r.what = text(-22, S.MUTED)
    return r
end

local function buildTracker()
    tracker = CreateFrame("Frame", "GulliCraftsmansWritTracker", UIParent)
    tracker:SetSize(TW, T_HEAD + 40)
    tracker:SetFrameStrata("MEDIUM")
    tracker:SetClampedToScreen(true)
    tracker:EnableMouse(true)
    S.HudPanel(tracker)
    tracker.icon = S.IconBox(tracker, 18, ns.ICON)
    tracker.icon:SetPoint("TOPLEFT", 8, -5)
    tracker.close = S.Close(tracker, function() ns.StopGuide() end)
    tracker.close:SetSize(24, 24)
    tracker.close:SetPoint("TOPRIGHT", -2, -2)
    tracker.title = S.Text(tracker, 12)
    tracker.title:SetPoint("LEFT", tracker.icon, "RIGHT", 8, 0)
    tracker.title:SetPoint("RIGHT", tracker.close, "LEFT", -6, 0)
    tracker.title:SetJustifyH("LEFT")
    tracker.title:SetWordWrap(false)
    tracker.title:SetText(L.TR_TITLE)
    local line = S.Divider(tracker)
    line:SetPoint("TOPLEFT", 1, -T_HEAD)
    line:SetPoint("TOPRIGHT", -1, -T_HEAD)
    line:SetHeight(1)
    tracker.empty = S.Text(tracker, 12, S.FAINT)
    tracker.empty:SetPoint("TOPLEFT", 10, -T_HEAD - 10)
    tracker.empty:SetPoint("RIGHT", -10, 0)
    tracker.empty:SetJustifyH("LEFT")
    tracker.empty:SetText(L.TR_EMPTY)
    tracker.rows = {}
    for i = 1, ns.TRACK_MAX do tracker.rows[i] = trackerRow(tracker) end
    S.Mover(tracker, { label = L.TR_TITLE,
        save = function(p, rp, x, y) if ns.db then ns.db.trackerPoint = { p, rp, x, y } end end,
        reset = function() if ns.db then ns.db.trackerPoint = nil end; ns.PlaceTracker() end })
    tracker:Hide()
end

function ns.MoveTracker(on)
    ns.movingTracker = on and true or nil
    ns.RefreshTracker()
end

function ns.RefreshTracker()
    if not ns.db then return end
    local moving = ns.movingTracker
    if not ((ns.Guiding() and not ns.paused) or moving) then
        if tracker then tracker:SetMoving(false); tracker:Hide() end
        return
    end
    if not tracker then buildTracker() end
    ns.PlaceTracker()
    local items = ns.Guiding() and ns.TrackerItems() or {}
    local y = T_HEAD + 2
    for i, r in ipairs(tracker.rows) do
        local it = items[i]
        r.item = it
        r:SetShown(it ~= nil)
        if it then
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 1, -y)
            r:SetPoint("TOPRIGHT", -1, -y)
            y = y + T_ROW
            r.icon:SetIcon(ns.ItemIcon(it.icon))
            local where = it.zone and L.WHO_WHERE:format(it.who, it.zone) or it.who
            r.name:SetText(where)
            r.name:SetTextColor(unpack(it.first and S.Accent() or S.GOLD))
            r.what:SetText(L.TIP_REP:format(it.rep) .. S.DOT .. it.what)
            r.pin:SetShown(it.stop.spot ~= nil)
        end
    end
    tracker.empty:SetShown(#items == 0)
    tracker:SetHeight(#items > 0 and (y + 4) or (T_HEAD + 40))
    tracker:SetMoving(moving and not (InCombatLockdown and InCombatLockdown()))
    tracker:Show()
end

function ns.TrackerFrame()
    if not tracker and ns.db then buildTracker() end
    return tracker
end

-- The search of the Writs tab (for the previews and the tests).
function ns.SetWritFind(text)
    ns.Window()
    writFind:SetText(text or "")
    ns.Refresh()
end
