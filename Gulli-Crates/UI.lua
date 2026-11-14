-- The window, narrow: the crates in the bags to tick, the cheapest way to fill each one (bags,
-- bank, what to buy), and the two switches. Calculate and Buy are in the footer. At the auction
-- house it opens beside the auction window.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, crateCard, crateList, crateEmpty, planCard, planList, planEmpty, setCard
local calcBtn, buyBtn, skipBtn
local CRATE_ROW, PLAN_ROW, CRATE_ROWS_MAX = 32, 30, 4

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
        ns.picked[c.id] = (ns.picked[c.id] == false) and nil or false
        ns.Refresh()
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
function ns.PlanRows(plan)
    local rows, lines = {}, {}
    for _, line in ipairs(ns.buy.queue) do lines[line.id] = line end
    for _, e in ipairs(plan and plan.crates or {}) do
        rows[#rows + 1] = { kind = "crate", e = e }
        if e.none then
            for _, o in ipairs(e.others) do rows[#rows + 1] = { kind = "other", o = o, none = true } end
        else
            for _, x in ipairs(e.rows) do rows[#rows + 1] = { kind = "item", r = x, line = x.buy > 0 and lines[x.id] or nil } end
            if e.others[1] then rows[#rows + 1] = { kind = "other", o = e.others[1] } end
        end
    end
    return rows
end

-- ---------- refresh ----------

local function buyText()
    local b, line = ns.buy, ns.Current()
    if not ns.CanBuy() then return L.LIST end
    if b.phase == "done" or not line then return L.BUY_DONE end
    if b.phase == "quote" then return L.BUY_WAIT end
    if b.phase == "buying" then return L.BUY_BUYING end
    if b.phase == "ready" then return L.BUY_CONFIRM:format(S.MoneyText(b.quote.total, true)) end
    return L.BUY_ASK
end

function ns.Refresh()
    if not frame or not frame:IsShown() then return end
    local crates = ns.Crates()
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
    elseif b.phase == "done" then status, color = L.BUY_DONE .. ": " .. L.ALL_BOUGHT:format(b.bought, S.MoneyText(b.spent)), S.GOOD
    elseif not ns.atAH and ns.CanBuy() then status, color = L.NOT_AT_AH, S.WARN
    elseif b.err then status, color = itemLine(ns.Current().id, ns.Current().n) .. ": " .. L[b.err], S.BAD
    elseif b.phase == "ready" and ns.Dear() then status, color = itemLine(ns.Current().id, ns.Current().n) .. ": " .. L.DEAR, S.WARN
    elseif b.phase ~= "idle" or b.i > 1 then
        status = itemLine(ns.Current().id, ns.Current().n) .. S.DOT .. b.i .. "/" .. #queue
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

    local body = frame.body
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
