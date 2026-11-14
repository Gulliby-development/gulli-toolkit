-- The window, narrow, with two tabs. Fill: the crates in the bags to tick, the cheapest way to
-- fill each one (bags, bank, what to buy), and the two switches; Calculate and Buy are in the
-- footer. History: the crates filled, with what the auction house got for them. A round button
-- in the header looks at the bags again. At the auction house it opens beside the auction window.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, crateCard, crateList, crateEmpty, planCard, planList, planEmpty, setCard
local calcBtn, buyBtn, skipBtn, refreshBtn
local tabs, pages, histStats, histList, histEmpty, periodTabs = nil, {}, nil, nil, nil, nil
local CRATE_ROW, PLAN_ROW, HIST_ROW, CRATE_ROWS_MAX = 32, 30, 38, 4
local tab, period = 1, "all"
local stale

-- "Waylaid Crate: Flowering Expert Herbs" -> "Flowering Expert Herbs"
function ns.ShortName(name)
    name = name or ""
    return name:match("^[^:：]+[:：]%s*(.+)$") or name
end

local function itemLine(id, n)
    return n .. " × " .. (ns.ItemName(id) or ("item:" .. id))
end

-- ---------- crate rows ----------

local function makeCrateRow(r)
    r.check = S.Check(r, 26)
    r.check:SetPoint("LEFT", -4, 0)
    r.check:SetScript("OnClick", function(self)
        local c = self:GetParent().crate
        ns.TogglePick(c.id)
    end)
    r.icon = S.ItemIcon(r, 24)
    r.icon:SetPoint("LEFT", r.check, "RIGHT", 4, 0)
    r.value = S.Text(r, 11, S.MUTED)
    r.value:SetPoint("RIGHT", -4, 0)
    r.value:SetJustifyH("RIGHT")
    r.name = S.Text(r, 12)
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
    r.name:SetPoint("RIGHT", r.value, "LEFT", -8, 0)
    r.name:SetWordWrap(false)
end

local function fillCrateRow(r, c)
    r.crate = c
    r.check:SetChecked(ns.picked[c.id] ~= false)
    r.icon:Set(c.icon, c.count, 1)
    r.name:SetText(ns.ShortName(c.name))
    local level = ns.CRATES[c.id] and ns.CRATES[c.id][1]
    r.value:SetText(level and (S.Hex(S.LevelColor(level)) .. level .. "|r") or "")
end

-- ---------- plan rows ----------

local function makePlanRow(r)
    r.icon = S.ItemIcon(r, 22)
    r.value = S.Text(r, 11)
    r.value:SetPoint("RIGHT", -4, 0)
    r.value:SetJustifyH("RIGHT")
    r.name = S.Text(r, 12)
    r.name:SetWordWrap(false)
    r.note = S.Text(r, 11, S.FAINT)
    r.note:SetWordWrap(false)
end

local function fillPlanRow(r, row)
    r.icon:ClearAllPoints()
    r.name:ClearAllPoints()
    r.note:ClearAllPoints()
    r.note:SetText("")
    if row.kind == "crate" then
        r.icon:SetPoint("LEFT", 0, 0)
        r.icon:Set(ns.ItemIcon(row.e.crate), nil, 1)
        r.icon:Show()
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
        r.name:SetText(ns.ShortName(ns.ItemName(row.e.crate) or "") .. (row.e.k > 1 and ("  #" .. row.e.k) or ""))
        if row.e.none then r.value:SetText(S.Hex(S.BAD) .. L.NO_PRICE .. "|r")
        elseif row.e.cost == 0 then r.value:SetText(S.Hex(S.GOOD) .. L.FILLED .. "|r")
        else r.value:SetText(S.MoneyText(row.e.cost)) end
    elseif row.kind == "item" then
        local x = row.r
        r.icon:SetPoint("LEFT", 30, 0)
        r.icon:Set(ns.ItemIcon(x.id), nil, 1)
        r.icon:Show()
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
        local done = row.line and row.line.done
        local current = row.line and row.line == ns.Current() and ns.buy.phase ~= "done"
        local c = done and S.GOOD or (current and S.Accent() or S.TEXT)
        r.name:SetText(S.Hex(c) .. itemLine(x.id, x.n) .. "|r")
        local parts = {}
        if x.bags > 0 then parts[#parts + 1] = L.FROM_BAGS:format(x.bags) end
        if x.bank > 0 then parts[#parts + 1] = S.Hex(S.WARN) .. L.FROM_BANK:format(x.bank) .. "|r" end
        if x.buy > 0 then parts[#parts + 1] = L.TO_BUY:format(x.buy) end
        r.note:SetPoint("LEFT", r.name, "RIGHT", 8, 0)
        r.note:SetPoint("RIGHT", r.value, "LEFT", -8, 0)
        r.note:SetText(table.concat(parts, S.DOT))
        r.value:SetText(x.buy > 0 and S.MoneyText(x.cost) or "")
    elseif row.kind == "ready" then
        r.icon:Hide()
        r.name:SetPoint("LEFT", 0, 0)
        r.name:SetText(S.Hex(S.GOOD) .. L.READY_N:format(row.n) .. "|r")
        r.value:SetText("")
    else -- the next best bundle, or a crate no bundle can fill
        r.icon:Hide()
        r.name:SetPoint("LEFT", 30, 0)
        local o = row.o
        local text = itemLine(o.bundle[1], o.bundle[2])
        r.name:SetText(S.Hex(S.FAINT) .. (row.none and text or L.OTHER:format(text)) .. "|r")
        r.value:SetText(o.cost and (S.Hex(S.FAINT) .. S.MoneyText(o.cost) .. "|r") or (S.Hex(S.FAINT) .. L.NO_PRICE .. "|r"))
    end
    if row.kind ~= "item" then r.name:SetPoint("RIGHT", r.value, "LEFT", -8, 0) end
end

-- The plan as list rows: each crate, its bundle's item, then the next best bundle.
-- A crate the bags already fill is left out: it waits in the History until it is used.
function ns.PlanRows(plan)
    local rows, lines, ready = {}, {}, 0
    for _, line in ipairs(ns.buy.queue) do lines[line.id] = line end
    for _, e in ipairs(plan and plan.crates or {}) do
        local owned = not e.none and e.cost == 0
        if owned then ready = ready + 1 else rows[#rows + 1] = { kind = "crate", e = e } end
        if owned then -- nothing to show
        elseif
 e.none then
            for _, o in ipairs(e.others) do rows[#rows + 1] = { kind = "other", o = o, none = true } end
        else
            for _, x in ipairs(e.rows) do rows[#rows + 1] = { kind = "item", r = x, line = x.buy > 0 and lines[x.id] or nil } end
            if e.others[1] then rows[#rows + 1] = { kind = "other", o = e.others[1] } end
        end
    end
    if ready > 0 then rows[#rows + 1] = { kind = "ready", n = ready } end
    return rows
end

-- ---------- history rows ----------

local function makeHistRow(r)
    r.icon = S.ItemIcon(r, 26)
    r.icon:SetPoint("LEFT", 0, 0)
    r.value = S.Text(r, 12)
    r.value:SetPoint("TOPRIGHT", -4, -4)
    r.value:SetJustifyH("RIGHT")
    r.sub = S.Text(r, 10, S.FAINT)
    r.sub:SetPoint("BOTTOMRIGHT", -4, 4)
    r.sub:SetJustifyH("RIGHT")
    r.name = S.Text(r, 12)
    r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, 2)
    r.name:SetPoint("RIGHT", r.value, "LEFT", -8, 0)
    r.name:SetWordWrap(false)
    r.note = S.Text(r, 11, S.MUTED)
    r.note:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 8, -2)
    r.note:SetPoint("RIGHT", r.sub, "LEFT", -8, 0)
    r.note:SetWordWrap(false)
end

local fmtDate = date or (os and os.date)
local function fillHistRow(r, e)
    r.icon:Set(ns.ItemIcon(e.crate), nil, 1)
    r.name:SetText(ns.ShortName(ns.ItemName(e.crate) or ("item:" .. e.crate)))
    local note = itemLine(e.item, e.n)
    if e.bought and e.bought > 0 and e.bought < e.n then note = note .. S.DOT .. L.HIST_BOUGHT:format(e.bought) end
    if e.ready and e.bank > 0 then note = note .. S.DOT .. S.Hex(S.WARN) .. L.FROM_BANK:format(e.bank) .. "|r" end
    r.note:SetText(note)
    local paid = (e.paid or 0) > 0 and S.MoneyText(e.paid) or (S.Hex(S.GOOD) .. L.FROM_STOCK .. "|r")
    if e.ready then
        r.value:SetText(S.Hex(S.GOOD) .. L.FILLED .. "|r")
        r.sub:SetText(paid)
    else
        r.value:SetText(paid)
        r.sub:SetText((fmtDate and fmtDate(L.DATE, e.at) or "") .. (e.who and (S.DOT .. e.who) or ""))
    end
end

-- ---------- refresh ----------

local function buyText()
    local b, line = ns.buy, ns.Current()
    if not ns.CanBuy() then return L.LIST end
    if b.phase == "done" or not line then return L.BUY_DONE end
    if b.phase == "quote" then return L.BUY_WAIT end
    if b.phase == "buying" then return L.BUY_BUYING end
    if b.phase == "ready" then return L.BUY_CONFIRM:format(S.MoneyIcons(b.quote.total, true)) end
    return L.BUY_ASK
end

local function refreshHistory()
    local done, sum = ns.History(period)
    local list = ns.Ready()
    for _, e in ipairs(done) do list[#list + 1] = e end
    histList:SetData(list)
    histEmpty:SetShown(#list == 0)
    histStats.tiles[1]:Set(tostring(sum.count))
    histStats.tiles[2]:Set(S.MoneyText(sum.spent, true))
    histStats.tiles[3]:Set(S.MoneyText(sum.avg, true))
    frame.footer:SetStatus("")
end

function ns.Refresh()
    if not frame or not frame:IsShown() then return end
    local onFill = tab == 1
    buyBtn:SetShown(onFill)
    calcBtn:SetShown(onFill)
    if not onFill then skipBtn:Hide(); refreshHistory(); return end
    local crates = ns.Crates()
    local hours = not ns.staleClosed and ns.HasAuctionator() and #crates > 0 and ns.StaleHours()
    stale:SetShown(hours and true or false)
    if hours then stale:Set(L.STALE:format(hours)) end
    crateCard:SetPoint("TOPLEFT", 0, hours and -(S.BANNER_H + S.GAP) or 0)
    crateCard:SetPoint("TOPRIGHT", 0, hours and -(S.BANNER_H + S.GAP) or 0)
    crateList:SetData(crates)
    crateEmpty:SetShown(#crates == 0)
    local n = math.max(1, math.min(CRATE_ROWS_MAX, #crates))
    crateCard:SetHeight(crateCard:Fit(n * CRATE_ROW))

    local plan = ns.plan
    planList:SetData(ns.PlanRows(plan))
    planEmpty:SetShown(not plan or #plan.crates == 0)
    local queue = ns.buy.queue
    planCard:SetTitle(L.PLAN, plan and #plan.crates > 0 and S.MoneyText(plan.total) or "")

    calcBtn:SetText(plan and L.RECALC or L.CALCULATE)
    calcBtn:SetEnabled(#ns.Picks(crates) > 0)
    buyBtn:SetText(buyText())
    local b = ns.buy
    local busy = b.phase == "quote" or b.phase == "buying"
    buyBtn:SetEnabled(plan ~= nil and #queue > 0 and b.phase ~= "done" and not busy
        and (not ns.CanBuy() and ns.HasAuctionator() or ns.atAH))
    skipBtn:SetShown(plan ~= nil and ns.CanBuy() and ns.Current() ~= nil and b.phase ~= "done")

    local status, color
    if not ns.HasAuctionator() then status, color = L.NO_AUCTIONATOR, S.WARN
    elseif not plan then status = L.HOW
    elseif #queue == 0 then status, color = L.NOTHING_TO_BUY, S.GOOD
    elseif b.phase == "done" then status, color = L.BUY_DONE .. ": " .. S.MoneyText(b.spent), S.GOOD
    elseif not ns.atAH and ns.CanBuy() then status, color = L.NOT_AT_AH, S.WARN
    elseif b.err then status, color = itemLine(ns.Current().id, ns.Current().n) .. ": " .. L[b.err], S.BAD
    elseif b.phase == "ready" and ns.Dear() then status, color = itemLine(ns.Current().id, ns.Current().n) .. ": " .. L.DEAR, S.WARN
    elseif b.phase ~= "idle" or b.i > 1 then
        status = b.i .. " / " .. #queue -- the line being bought is lit in the list
    else
        local total = 0
        for _, line in ipairs(queue) do total = total + line.cost end
        status = L.TOTAL:format(#queue, S.MoneyText(total)) .. S.DOT .. itemLine(ns.Current().id, ns.Current().n)
    end
    frame.footer:SetStatus(status, color)
end

-- ---------- build ----------

local function build()
    frame = S.Window("GulliCratesFrame", L.TITLE, S.NARROW_W, S.DOCK_H)
    local ft = S.Footer(frame)
    buyBtn = S.Primary(S.Button(ft, 200, 32))
    ft:Add(buyBtn)
    buyBtn:SetScript("OnClick", function()
        if ns.CanBuy() then ns.BuyClick()
        else
            local n = ns.ExportList()
            if n then ns.Say(L.LIST_DONE:format(n)) end
        end
    end)
    calcBtn = S.Button(ft, 120, 32)
    ft:Add(calcBtn)
    calcBtn:SetText(L.CALCULATE)
    calcBtn:SetScript("OnClick", function() ns.Calculate() end)
    skipBtn = S.Ghost(S.Button(ft, 80, 32))
    ft:Add(skipBtn)
    skipBtn:SetText(L.SKIP)
    skipBtn:SetScript("OnClick", function() ns.Skip() end)

    refreshBtn = frame:AddHeaderButton(S.Ghost(S.Button(frame, 28, 28)))
    S.SetButtonIcon(refreshBtn, "Interface\\Buttons\\UI-RefreshButton", 16)
    refreshBtn.btnIcon:ClearAllPoints()
    refreshBtn.btnIcon:SetPoint("CENTER")
    refreshBtn:SetScript("OnClick", function() ns.Recheck() end)
    refreshBtn:HookScript("OnEnter", function(self)
        if GameTooltip and GameTooltip.SetOwner then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(L.REFRESH)
            GameTooltip:AddLine(L.REFRESH_TIP, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    refreshBtn:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    tabs = S.Tabs(frame.body, { L.TAB_FILL, L.TAB_HISTORY }, nil, function(i)
        tab = i
        for j, p in ipairs(pages) do p:SetShown(j == i) end
        ns.Refresh()
    end, nil, { "Interface\\Icons\\INV_Crate_01", S.TAB.recent })
    for i = 1, 2 do
        local p = CreateFrame("Frame", nil, frame.body)
        p:SetPoint("TOPLEFT", 0, -30 - S.GAP)
        p:SetPoint("BOTTOMRIGHT")
        p:SetShown(i == 1)
        pages[i] = p
    end

    -- History
    local hp = pages[2]
    local st = S.Stack(hp)
    periodTabs = S.Tabs(hp, { L.PERIOD_day, L.PERIOD_week, L.PERIOD_all }, nil, function(i)
        period = ns.PERIODS[i]
        ns.Refresh()
    end, 28)
    periodTabs:Select(3, true)
    periodTabs.frame:ClearAllPoints()
    periodTabs.frame:SetPoint("TOPLEFT")
    st:Space(28 + S.GAP)
    histStats = S.StatRow(hp, { L.ST_COUNT, L.ST_SPENT, L.ST_AVG }, 62,
        { "Interface\\Icons\\INV_Crate_01", "Interface\\Minimap\\Tracking\\Auctioneer", "Interface\\Icons\\INV_Misc_Coin_01" })
    st:Add(histStats, 62)
    histStats:Layout(frame.inner[1])
    local histCard = S.Card(hp, L.HISTORY, "", S.TAB.recent)
    histCard:SetPoint("TOPLEFT", 0, -st.y)
    histCard:SetPoint("BOTTOMRIGHT")
    histList = S.List(histCard.body, HIST_ROW, makeHistRow, fillHistRow)
    histList:SetPoint("TOPLEFT")
    histList:SetPoint("BOTTOMRIGHT", -10, 0)
    histEmpty = S.Empty(histList)
    histEmpty:Set(L.HIST_EMPTY, L.HIST_EMPTY_SUB)

    local body = pages[1]
    stale = S.Banner(body, "Interface\\Icons\\INV_Misc_PocketWatch_01")
    stale:SetPoint("TOPLEFT")
    stale:SetPoint("TOPRIGHT")
    stale.onClose = function() ns.staleClosed = true; ns.Refresh() end
    crateCard = S.Card(body, L.CRATES, "", "Interface\\Icons\\INV_Crate_01")
    crateCard:SetPoint("TOPLEFT")
    crateCard:SetPoint("TOPRIGHT")
    crateCard:Fit(CRATE_ROW)
    crateList = S.List(crateCard.body, CRATE_ROW, makeCrateRow, fillCrateRow)
    crateList:SetAllPoints()
    crateEmpty = S.Empty(crateList)
    crateEmpty:Set(L.NO_CRATES, "")

    local rows = {}
    for _, key in ipairs({ "auto", "bank" }) do
        rows[#rows + 1] = { L["OPT_" .. key], nil, function() return ns.db[key] end,
                            function(v) ns.db[key] = v; if key == "bank" and ns.plan then ns.Calculate() end end,
                            icon = ns.OPT_ICON[key] }
    end
    local h
    setCard, h = S.SettingsCard(body, nil, rows)
    setCard:SetPoint("BOTTOMLEFT")
    setCard:SetPoint("BOTTOMRIGHT")
    setCard:SetHeight(h)

    planCard = S.Card(body, L.PLAN, "", "Interface\\Minimap\\Tracking\\Auctioneer")
    planCard:SetPoint("TOPLEFT", crateCard, "BOTTOMLEFT", 0, -S.GAP)
    planCard:SetPoint("TOPRIGHT", crateCard, "BOTTOMRIGHT", 0, -S.GAP)
    planCard:SetPoint("BOTTOM", setCard, "TOP", 0, S.GAP)
    planList = S.List(planCard.body, PLAN_ROW, makePlanRow, fillPlanRow)
    planList:SetPoint("TOPLEFT")
    planList:SetPoint("BOTTOMRIGHT", -10, 0)
    planEmpty = S.Empty(planList)
    planEmpty:Set(L.PLAN_EMPTY, L.PLAN_EMPTY_SUB)

    frame:SetScript("OnShow", function() ns.Refresh() end)
end

function ns.Toggle()
    S.ToggleWindow(ns.Window())
end

-- Opens a tab: 1 fill, 2 history.
function ns.ShowTab(i)
    ns.Window()
    tabs:Select(i)
end

-- The window, for the hub (/gulli) to show inside it.
function ns.Window()
    if not frame then build() end
    return frame
end

-- At the auction house: beside its window, unless the window sits in the hub.
function ns.ShowAtAH()
    local w = ns.Window()
    if w.docked then if w:IsShown() then ns.Refresh() end return end
    local ah = AuctionHouseFrame or AuctionFrame
    if ah then
        w:ClearAllPoints()
        w:SetPoint("TOPLEFT", ah, "TOPRIGHT", 8, 0)
    end
    ns.byAH = true
    w:Show()
    ns.Refresh()
end

function ns.HideAtAH()
    if frame and ns.byAH and not frame.docked then frame:Hide() end
    ns.byAH = false
    ns.Refresh()
end
