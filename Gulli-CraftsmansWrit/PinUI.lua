-- What a pinned plan shows on the Plan tab (Pin.lua holds the rules): a strip that says it is
-- pinned, a notice of what was missed with Do not catch up, two views (By days: a ribbon of the
-- plan's days and the selected day's writs; Purchases: what is left to buy, today or the whole
-- plan, against the plan's prices), the comparison with a new calculation and the list of every
-- plan. Today's card on the Today tab comes from here too.

local _, ns = ...
local L = ns.L
local S = ns.Skin

ns.PIN_ICON = "Interface\\Icons\\INV_Misc_Map_01"
local LOCK = "Interface\\Buttons\\LockButton-Locked-Up"
local TIME_ICON = "Interface\\Icons\\INV_Misc_PocketWatch_01"
local AH_ICON = "Interface\\Minimap\\Tracking\\Auctioneer"
local REP_ICON = "Interface\\Icons\\INV_Misc_Ribbon_01"
local POUCH_ICON = "Interface\\Icons\\INV_Misc_Coin_02"
local TICK = "Interface\\RaidFrame\\ReadyCheck-Ready"
local WRIT_ICON = "Interface\\Icons\\INV_Scroll_03"
local CHIP_W, CHIP_H, STRIP_H = 50, 40, 28

local ui, P = nil, {}
ns.pinMode = "days" -- "days" or "buys"
ns.pinPage = nil -- "list" while the list of plans shows

local function hex(c) return S.Hex(c) end
local fmtDate = date or (os and os.date)
local function fmtDay(t)
    local d = fmtDate and fmtDate("*t", math.floor(t + 60))
    return type(d) == "table" and tostring(d.day) or ""
end
local function accentFill(a) local f = S.FILL; return { f[1], f[2], f[3], a } end

local function classHex(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c and c.r then return string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) end
    return hex(S.GOLD)
end
ns.ClassHex = classHex

local function goalName(pin) return L["STAND_" .. (pin.goal or 5)] or "" end
local function rep(n) return L.TIP_REP:format(n or 0) end

local function tip(owner, head, text)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:SetText(head or "", 1, 1, 1)
    if text then GameTooltip:AddLine(text, 0.8, 0.8, 0.8, true) end
    GameTooltip:Show()
end
local function untip() if GameTooltip then GameTooltip:Hide() end end

-- A round button with a game picture (the pin of the footer).
local function roundButton(parent, picture)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(32, 32)
    S.Box(b, S.RAISED, S.EDGE, 16)
    b.pic = b:CreateTexture(nil, "ARTWORK")
    b.pic:SetSize(20, 20)
    b.pic:SetPoint("CENTER")
    b.pic:SetTexture(picture)
    local a = S.Accent()
    b.pic:SetVertexColor(a[1], a[2], a[3], 1)
    b.label = ""
    function b:SetText(s) self.label = s end
    function b:GetText() return self.label end
    b:SetScript("OnEnter", function(self) S.SetBorder(self, S.Accent()); tip(self, self.label, self.tip) end)
    b:SetScript("OnLeave", function(self) S.SetBorder(self, S.EDGE); untip() end)
    S.FollowEnabled(b, function(self, on) self.pic:SetAlpha(on and 1 or 0.4) end)
    return b
end

-- ---------- the pin button, the header chip ----------

-- The footer's pin: pins the plan shown, or takes the pinned one away with Undo.
function ns.PinClick(which)
    local pin = which or ns.PinShown()
    if pin then
        local undo = ns.Unpin(pin)
        if undo and S.Toast then
            S.Toast({ key = "CraftsmansWritPin", icon = ns.PIN_ICON, title = L.UNPINNED, text = L.UNPINNED_SUB,
                      seconds = 10, buttons = { { text = L.UNDO, onClick = function() ns.PinRestore(undo) end } } })
        end
        return
    end
    ns.PinNow()
end

function ns.PinShowList(on)
    ns.pinPage = on and "list" or nil
    if on and ns.ShowTab and ns.Tab and ns.Tab() ~= 2 then ns.ShowTab(2) end
    if ns.Refresh then ns.Refresh() end
end

-- ---------- rows ----------

-- What a copy of the plan says on its day: the word under its value and its colour.
function ns.CopyState(c, v)
    if c.dropped then return L.PS_DROPPED, S.FAINT end
    if c.done then return L.PS_DONE, S.GOOD end
    if v and v.extra[c] then return L.PS_EXTRA, S.FAINT end
    if v and c.day > v.today then return L.PS_LATER, S.MUTED end
    if c.kind == "writ" and v and v.mine then
        local w = ns.Writ(c.id)
        local s = w and ns.StateOf(w)
        if s then
            if s.status == "ready" then return L.ST_READY, S.GOOD end
            if s.status == "item" or s.status == "bank" then return L["ST_" .. s.status:upper()], S.WARN end
        end
    end
    return L.PS_BUY, S.MUTED
end

-- The rows of a day of the plan: its copies; a past day also the ones it missed.
function ns.PinDayRows(pin, d, v)
    v = v or ns.PinView(pin)
    local rows = {}
    for i, c in ipairs(pin.copies) do
        local day = c.done and c.done.day or c.day
        if not c.dropped and day == d then rows[#rows + 1] = { c = c }
        elseif d < v.today and pin.days and pin.days[d] then
            for _, m in ipairs(pin.days[d].miss) do
                if m == i then rows[#rows + 1] = { c = c, missed = true } end
            end
        end
    end
    table.sort(rows, function(a, b)
        if (a.c.done ~= nil) ~= (b.c.done ~= nil) then return b.c.done ~= nil end
        if a.missed ~= b.missed then return b.missed end
        return a.c.id < b.c.id
    end)
    return rows
end

local function fillDay(r, row)
    ui.asItem(r)
    local c = row.c
    local v = P.v
    r.tip = c.id
    if c.kind == "sealed" then
        r.icon:Set(ns.ItemIcon(c.id), nil, 2)
        r.name:SetText(ns.DisplayName(c.id))
        r.note:SetText(L.SEALED_NOTE)
    else
        local w = ns.Writ(c.id)
        r.icon:Set(ns.ItemIcon(c.id), nil, 1)
        r.name:SetText(w and ns.WritName(w) or ns.DisplayName(c.id))
        local who = w and ns.Customer(w)
        local spot = w and ns.Spot(w)
        local zone = spot and ns.ZoneName(spot.map)
        -- the row's name is the item already: the line says how many and who takes it
        local note = (w and w.count > 1) and (w.count .. " x") or ""
        if who then
            note = note .. (note ~= "" and S.DOT or "") .. (zone and L.WHO_WHERE:format(who, zone) or who)
        end
        r.note:SetText(note)
    end
    if row.missed then
        r.value:SetText(hex(S.WARN) .. rep(c.rep) .. "|r")
        r.sub:SetText(hex(S.WARN) .. (c.done and L.PS_LATE:format(c.done.day) or L.PS_MOVED:format(c.day)) .. "|r")
        return
    end
    if c.done then
        r.value:SetText(hex(S.GOOD) .. "+" .. rep(c.rep) .. "|r")
    else
        r.value:SetText(ns.CostText(c.cost or 0, c.estimate))
    end
    local word, color = ns.CopyState(c, v)
    r.sub:SetText(hex(color) .. word .. "|r")
end

local function fillBuy(r, l)
    ui.asItem(r)
    r.tip = l.id
    r.icon:Set(ns.ItemIcon(l.id), l.need > 1 and l.need or nil, 1)
    local name = ns.ShortName(ns.DisplayName(l.id))
    r.name:SetText(l.part == "writ" and ns.Writ(l.id) and ns.WritName(ns.Writ(l.id)) or name)
    local note = L.HAVE_OF:format(l.have, l.need)
    if l.left > 0 and l.dear then note = note .. S.DOT .. hex(S.WARN) .. L.DEARER:format(l.dear) .. "|r" end
    r.note:SetText(note)
    if l.left == 0 then
        r.value:SetText(hex(S.GOOD) .. L.ALL_THERE .. "|r")
        r.sub:SetText("")
    elseif not l.unit then
        r.value:SetText(hex(S.BAD) .. L.NO_SALE .. "|r")
        r.sub:SetText(L.LEFT_N:format(l.left))
    else
        r.value:SetText(S.MoneyText(l.cost))
        local each = L.EACH:format(S.MoneyText(math.floor(l.unit + 0.5), true))
        if l.plan then each = each .. S.DOT .. L.PLAN_WAS:format(S.MoneyText(math.floor(l.plan + 0.5), true)) end
        r.sub:SetText(l.dear and (hex(S.WARN) .. each .. "|r") or each)
    end
end

local function fillPlanRow(r, row)
    if row.head then ui.asHead(r, row.head); r.del:Hide(); return end
    ui.asItem(r)
    local pin = row.pin
    r.tip = nil
    r.icon:Set(ns.PIN_ICON, nil, 1)
    r.name:SetText(classHex(pin.class) .. (pin.who or "?") .. "|r" .. S.DOT .. goalName(pin))
    if pin.finished then
        local res = pin.result or {}
        r.note:SetText(L.LIST_DONE:format(ns.PinDateText(pin, 1), res.days or 0, res.n or 0))
        r.value:SetText(ns.CostText((res.spent or 0) - (res.pouch or 0)))
        r.sub:SetText(hex(S.GOOD) .. "+" .. rep(res.rep) .. "|r")
    else
        local v = ns.PinView(pin)
        r.note:SetText(L.LIST_RUN:format(ns.PinDateText(pin, 1), v.today, v.endDay, ns.PinDateText(pin, v.endDay)))
        r.value:SetText(rep(v.gained) .. " / " .. rep(v.need))
        r.sub:SetText(v.behindN > 0 and (hex(S.WARN) .. L.BEHIND_SHORT .. "|r") or (hex(S.GOOD) .. L.ON_PLAN .. "|r"))
    end
    r.del:Show()
    r.del.pin = pin
end

local function makePlanRow(r)
    ui.makeRow(r)
    r.del = S.Close(r, function(self)
        local pin = self.pin
        if not pin then return end
        if pin.finished then
            for i, p in ipairs(ns.Plans()) do if p == pin then table.remove(ns.Plans(), i) break end end
            if ns.Refresh then ns.Refresh() end
        else ns.PinClick(pin) end
    end)
    r.del:SetPoint("RIGHT", -2, 0)
    r.value:SetPoint("TOPRIGHT", -34, -4)
    r.sub:SetPoint("BOTTOMRIGHT", -34, 4)
    r:SetScript("OnMouseUp", function(self)
        local pin = self.del.pin
        if not pin or pin.finished then return end
        ns.viewPin = pin.key ~= ns.CharKey() and pin or nil
        ns.pinPage = nil
        ns.ResetBuy()
        if ns.Refresh then ns.Refresh() end
    end)
end

-- The rows of the list of plans: running ones, then finished ones.
function ns.PinListRows()
    local run, done = ns.PinRows()
    local rows = {}
    rows[#rows + 1] = { head = L.LIST_RUNNING:format(#run, ns.PIN_MAX) }
    for _, p in ipairs(run) do rows[#rows + 1] = { pin = p } end
    if #done > 0 then
        rows[#rows + 1] = { head = L.LIST_FINISHED }
        for _, p in ipairs(done) do rows[#rows + 1] = { pin = p } end
    end
    return rows
end

-- ---------- build ----------

local function chip(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(CHIP_W, CHIP_H)
    S.Box(b, S.RAISED, S.EDGE, S.R_MD)
    b.top = S.Text(b, 12, S.MUTED)
    b.top:SetPoint("TOP", 0, -4)
    b.top:SetWordWrap(false)
    b.mark = S.Text(b, 12)
    b.mark:SetPoint("BOTTOM", 0, 5)
    b.mark:SetWordWrap(false)
    b.tick = b:CreateTexture(nil, "OVERLAY")
    b.tick:SetSize(16, 16)
    b.tick:SetPoint("BOTTOM", 0, 3)
    b.tick:SetTexture(TICK)
    b:SetScript("OnClick", function(self)
        P.sel = self.d
        if ns.Refresh then ns.Refresh() end
    end)
    b:SetScript("OnEnter", function(self)
        if self.tipHead then tip(self, self.tipHead, self.tipText) end
    end)
    b:SetScript("OnLeave", untip)
    return b
end

function ns.BuildPin(arg)
    ui = arg
    local page, W = ui.page, ui.W
    local v = CreateFrame("Frame", nil, page)
    v:SetAllPoints()
    v:Hide()
    P.view = v

    -- the strip: pinned since, to which standing, and the way out
    local s = CreateFrame("Frame", nil, v)
    s:SetHeight(STRIP_H)
    s:SetPoint("TOPLEFT")
    s:SetPoint("TOPRIGHT")
    S.Box(s, accentFill(0.2), accentFill(0.5), S.R_LG)
    s.icon = S.IconBox(s, 20, ns.PIN_ICON)
    s.icon:SetPoint("LEFT", 6, 0)
    s.off = S.Ghost(S.FitButton(s, L.UNPIN, 24, 70))
    s.off:SetPoint("RIGHT", -4, 0)
    s.off:SetScript("OnClick", function() ns.PinClick() end)
    s.mine = S.Ghost(S.FitButton(s, L.BACK_MINE, 24, 70))
    s.mine:SetPoint("RIGHT", -4, 0)
    s.mine:SetScript("OnClick", function() ns.viewPin = nil; ns.ResetBuy(); ns.Refresh() end)
    s.text = S.Text(s, 12, nil, nil, "bold")
    s.text:SetPoint("LEFT", s.icon, "RIGHT", 8, 0)
    s.text:SetPoint("RIGHT", s.off, "LEFT", -8, 0)
    s.text:SetJustifyH("LEFT")
    s.text:SetWordWrap(false)
    P.strip = s

    -- what was missed, with Do not catch up
    local b = S.Banner(v, TIME_ICON, S.WARN)
    b.catch = S.FitButton(b, L.NO_CATCH_UP, 24, 80)
    b.catch:SetPoint("RIGHT", b.close, "LEFT", -6, 0)
    b.catch:SetScript("OnClick", function() ns.PinNoCatchUp() end)
    b.catch:SetScript("OnEnter", function(self) tip(self, L.NO_CATCH_UP, L.NO_CATCH_UP_TIP) end)
    b.catch:SetScript("OnLeave", untip)
    b.text:SetPoint("RIGHT", b.catch, "LEFT", -6, 0)
    b.text:SetMaxLines(2)
    b.onClose = function() ns.PinDismissMiss() end
    P.banner = b

    -- the two views and the comparison
    P.modes = S.Tabs(v, { L.VIEW_DAYS, L.VIEW_BUYS }, nil, function(i)
        ns.pinMode = i == 1 and "days" or "buys"
        if ns.Refresh then ns.Refresh() end
    end, 28, { TIME_ICON, AH_ICON })
    P.cheaper = S.FitButton(v, L.CHEAPER, 28, 90)
    P.cheaper:SetScript("OnClick", function() ns.PinCompareStart() end)
    P.cheaper:SetScript("OnEnter", function(self) tip(self, L.CHEAPER, L.CHEAPER_TIP) end)
    P.cheaper:SetScript("OnLeave", untip)

    P.tiles = S.StatRow(v, { "", "", "" }, 58, { REP_ICON, TIME_ICON, AH_ICON })

    -- By days
    local dv = CreateFrame("Frame", nil, v)
    P.daysView = dv
    P.ribbon = CreateFrame("Frame", nil, dv)
    P.ribbon:SetHeight(CHIP_H)
    P.ribbon:SetPoint("TOPLEFT")
    P.ribbon:SetPoint("TOPRIGHT")
    P.chips = {}
    P.perRow = math.max(3, math.floor((W + 6) / (CHIP_W + 6)))
    for i = 1, P.perRow do
        local c = chip(P.ribbon)
        c:SetPoint("LEFT", (i - 1) * (CHIP_W + 6), 0)
        P.chips[i] = c
    end
    P.dayCard, P.dayList = ui.listCard(dv, "", TIME_ICON, ui.makeRow, fillDay)
    P.dayCard:SetPoint("TOPLEFT", 0, -(CHIP_H + S.GAP))
    P.dayCard:SetPoint("BOTTOMRIGHT")
    P.dayEmpty = S.Empty(P.dayList)

    -- Purchases
    local bv = CreateFrame("Frame", nil, v)
    P.buysView = bv
    P.buyCard, P.buyList = ui.listCard(bv, L.BUYS_TITLE, AH_ICON, ui.makeRow, fillBuy)
    P.buyCard:SetAllPoints()
    P.buyCard.hint:Hide()
    P.scope = S.Tabs(P.buyCard, { L.SCOPE_TODAY, L.SCOPE_ALL }, nil, function(i)
        ns.db.pinScope = i == 1 and "today" or "all"
        ns.ResetBuy()
        if ns.Refresh then ns.Refresh() end
    end, 24)
    P.scope.frame:ClearAllPoints()
    P.scope.frame:SetPoint("TOPRIGHT", -S.INSET, -6)
    P.buyCard.title:SetPoint("RIGHT", P.scope.frame, "LEFT", -8, 0)
    P.buyEmpty = S.Empty(P.buyList)

    -- the comparison
    local cv = CreateFrame("Frame", nil, v)
    P.cmp = cv
    local half = math.floor((W - S.GAP) / 2)
    local function side(title, icon)
        local c = S.Card(cv, title, "", icon)
        c:SetSize(half, 36 + 5 * 20 + S.INSET)
        c.rows = {}
        for i = 1, 5 do
            local l = S.Text(c.body, 12, S.MUTED)
            l:SetPoint("TOPLEFT", 0, -(i - 1) * 20)
            l:SetWordWrap(false)
            local r = S.Text(c.body, 12)
            r:SetPoint("TOPRIGHT", 0, -(i - 1) * 20)
            r:SetJustifyH("RIGHT")
            r:SetWordWrap(false)
            l:SetPoint("RIGHT", r, "LEFT", -6, 0)
            c.rows[i] = { l, r }
        end
        return c
    end
    P.cmpMine = side(L.CMP_MINE, ns.PIN_ICON)
    P.cmpMine:SetPoint("TOPLEFT")
    P.cmpNew = side(L.CMP_NEW, REP_ICON)
    P.cmpNew:SetPoint("TOPRIGHT")
    P.verdict = S.Text(cv, 13, nil, nil, "bold")
    P.verdict:SetPoint("TOPLEFT", P.cmpMine, "BOTTOMLEFT", 0, -S.GAP)
    P.verdict:SetPoint("RIGHT")
    P.verdict:SetJustifyH("LEFT")
    P.verdict:SetWordWrap(true)
    P.verdict:SetMaxLines(2)
    P.chgCard, P.chgList = ui.listCard(cv, L.CMP_CHANGES, WRIT_ICON, ui.makeRow, function(r, e)
        ui.asItem(r)
        r.tip = e.id
        r.icon:Set(ns.ItemIcon(e.id), nil, 1)
        local w = e.kind == "writ" and ns.Writ(e.id)
        r.name:SetText(w and ns.WritName(w) or ns.ShortName(ns.DisplayName(e.id)))
        if e.held then
            r.note:SetText(L.CMP_HELD)
            r.value:SetText(hex(S.WARN) .. "x" .. e.held .. "|r")
            r.sub:SetText("")
        else
            r.note:SetText(e.to > e.from and L.CMP_ADD or L.CMP_REMOVE)
            r.value:SetText(e.from .. " - " .. e.to)
            r.sub:SetText(hex(e.to > e.from and S.GOOD or S.WARN) .. (e.to > e.from and "+" or "") .. (e.to - e.from) .. "|r")
        end
    end)
    P.chgCard:SetPoint("TOPLEFT", P.cmpMine, "BOTTOMLEFT", 0, -(S.GAP + 34))
    P.chgCard:SetPoint("BOTTOMRIGHT")
    P.chgEmpty = S.Empty(P.chgList)

    -- the list of plans
    local lv = CreateFrame("Frame", nil, page)
    lv:SetAllPoints()
    lv:Hide()
    P.listView = lv
    P.listCard, P.list = ui.listCard(lv, L.LIST_TITLE, ns.PIN_ICON, makePlanRow, fillPlanRow,
        function(row) return row.head and ui.HEAD or ui.ROW end)
    P.listCard:SetPoint("TOPLEFT", 0, -(28 + S.GAP))
    P.listCard:SetPoint("BOTTOMRIGHT")
    P.listBack = S.Return(S.FitButton(lv, L.LIST_BACK, 28, 90))
    P.listBack:SetPoint("TOPLEFT")
    P.listBack:SetScript("OnClick", function() ns.PinShowList(false) end)

    -- the header chip: how many plans, and the way to their list
    local hc = S.Pill(ui.frame.bar, 96, 26)
    hc.icon = S.IconBox(hc, 18, ns.PIN_ICON)
    hc.icon:SetPoint("LEFT", 4, 0)
    hc.text:ClearAllPoints()
    hc.text:SetPoint("LEFT", hc.icon, "RIGHT", 6, 0)
    hc.text:SetPoint("RIGHT", -8, 0)
    hc:SetScript("OnClick", function() ns.PinShowList(ns.pinPage ~= "list") end)
    hc:HookScript("OnEnter", function(self) tip(self, L.LIST_TITLE, L.LIST_TIP) end)
    hc:HookScript("OnLeave", untip)
    ui.frame:AddHeaderButton(hc)
    P.chip = hc

    -- the footer's pin button
    local pb = roundButton(ui.footer, LOCK)
    pb:SetPoint("BOTTOMLEFT", S.PAD, 12)
    pb:SetScript("OnClick", function() ns.PinClick() end)
    P.pinBtn = pb
end

-- ---------- refresh ----------

local function place(pin, v)
    local y = STRIP_H + S.GAP
    P.banner:ClearAllPoints()
    P.banner:SetPoint("TOPLEFT", 0, -y)
    P.banner:SetPoint("TOPRIGHT", 0, -y)
    if P.banner:IsShown() then y = y + S.BANNER_H + S.GAP end
    local comparing = ns.compare ~= nil
    P.modes.frame:SetShown(not comparing)
    P.cheaper:SetShown(not comparing and v.mine)
    P.tiles:SetShown(not comparing)
    P.cmp:SetShown(comparing)
    P.daysView:SetShown(not comparing and ns.pinMode == "days")
    P.buysView:SetShown(not comparing and ns.pinMode == "buys")
    if comparing then
        P.cmp:ClearAllPoints()
        P.cmp:SetPoint("TOPLEFT", 0, -y)
        P.cmp:SetPoint("BOTTOMRIGHT")
        return
    end
    P.modes.frame:ClearAllPoints()
    P.modes.frame:SetPoint("TOPLEFT", 0, -y)
    P.cheaper:ClearAllPoints()
    P.cheaper:SetPoint("TOPRIGHT", 0, -y)
    y = y + 28 + S.GAP
    P.tiles:ClearAllPoints()
    P.tiles:SetPoint("TOPLEFT", 0, -y)
    P.tiles:SetPoint("TOPRIGHT", 0, -y)
    P.tiles:Layout(ui.W)
    y = y + 58 + S.GAP
    for _, f in ipairs({ P.daysView, P.buysView }) do
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", 0, -y)
        f:SetPoint("BOTTOMRIGHT")
    end
end

local function refreshStrip(pin, v)
    local s = P.strip
    local since = ns.PinDateText(pin, 1)
    if v.mine then s.text:SetText(S.Upper(L.PIN_STRIP:format(since, goalName(pin))))
    else s.text:SetText(S.Upper(L.PIN_STRIP_OF:format(pin.who or "?", since, goalName(pin)))) end
    s.off:SetShown(v.mine)
    s.mine:SetShown(not v.mine)
    s.text:SetPoint("RIGHT", v.mine and s.off or s.mine, "LEFT", -8, 0)
end

local function refreshBanner(pin, v)
    local b = P.banner
    if #v.miss == 0 or ns.compare then b:Hide(); return end
    -- names only while they fit the banner's two lines; the day's list names them all
    local names = {}
    if #v.miss <= 2 then
        for _, c in ipairs(v.miss) do
            local w = c.kind == "writ" and ns.Writ(c.id)
            names[#names + 1] = w and ns.WritName(w) or ns.ShortName(ns.DisplayName(c.id))
        end
    end
    local head
    if v.missYesterday then
        head = L.MISS_YESTERDAY:format(ns.PinDateText(pin, v.today - 1), v.missYesterday.n, v.missYesterday.of)
    else
        head = L.MISS_SINCE:format(#v.miss, ns.PinDateText(pin, v.missDay or 1))
    end
    local endText = ns.PinDateText(pin, v.endDay)
    local tail = v.endDay > v.planEnd and L.MISS_SHIFT:format(endText) or L.MISS_SHIFT_SAME
    if #names > 0 then head = head .. ": " .. table.concat(names, ", ") end
    -- a date that ends in a dot (German "6. Jan.") ends the sentence too
    b:Set((head .. ". " .. tail):gsub("%.%.", "."))
    b.catch:SetShown(v.mine)
    b.text:SetPoint("RIGHT", v.mine and b.catch or b.close, "LEFT", -6, 0)
    b:Show()
end

local function refreshTiles(pin, v, buys)
    local t = P.tiles.tiles
    if ns.pinMode == "buys" then
        t[1].icon:SetIcon(AH_ICON)
        t[1]:Set(buys.missing > 0 and (hex(S.BAD) .. L.NO_SALE .. "|r") or ns.CostText(buys.left, nil, true),
            nil, L.T_LEFT_WAS:format(S.MoneyText(buys.planLeft, true)))
        t[2].icon:SetIcon(POUCH_ICON)
        t[2]:Set(ns.CostText(-buys.pouch, nil, true), nil, L.ST_POUCHES)
        t[3].icon:SetIcon(REP_ICON)
        t[3]:Set(ns.CostText(buys.total, nil, true), nil, L.T_REST)
        return
    end
    t[1].icon:SetIcon(REP_ICON)
    t[1]:Set(S.Emph(tostring(math.max(0, v.gained))) .. " / " .. v.need, v.behindN > 0 and S.WARN or nil,
        v.behindN > 0 and L.T_BEHIND:format(v.behind) or L.T_BY_TONIGHT:format(v.expected - (pin.repStart or 0)))
    t[2].icon:SetIcon(TIME_ICON)
    local endText = ns.PinDateText(pin, v.endDay)
    t[2]:Set(L.T_DAY:format(v.today, v.endDay), v.endDay > v.planEnd and S.WARN or nil,
        L.T_END:format(endText))
    t[3].icon:SetIcon(AH_ICON)
    local all = P.allBuys or buys
    t[3]:Set(all.missing > 0 and (hex(S.BAD) .. L.NO_SALE .. "|r") or ns.CostText(all.left, nil, true), nil, L.T_LEFT)
end

local function refreshDays(pin, v)
    local days = ns.PinDays(pin, v)
    if not P.sel or P.sel > #days or P.selPin ~= pin or P.selToday ~= v.today then
        P.sel, P.selPin, P.selToday = v.today, pin, v.today
    end
    local n = P.perRow
    local first = math.max(1, math.min(v.today - 2, #days - n + 1))
    local a = S.Accent()
    for i, c in ipairs(P.chips) do
        local d = days[first + i - 1]
        c.d = d and d.d
        c:SetShown(d ~= nil)
        if d then
            local wd = ns.WeekdayText(d.t)
            local dt = fmtDay(d.t)
            c.top:SetText(wd ~= "" and (wd .. " " .. dt) or dt)
            local full = d.n > 0 and d.done >= d.n
            c.tick:SetShown(full and (d.past or d.today))
            c.mark:SetShown(not c.tick:IsShown())
            local mark, color
            if d.past then
                mark = d.n > 0 and (d.done .. "/" .. d.n) or "-"
                color = (d.miss or 0) > 0 and S.WARN or S.MUTED
            elseif d.today then mark, color = d.done .. "/" .. d.n, a
            else mark, color = tostring(d.n), d.extra and S.WARN or S.TEXT end
            c.mark:SetText(hex(color) .. mark .. "|r")
            local edge = S.EDGE
            if d.d == P.sel then edge = a elseif d.extra then edge = S.WARN end
            S.Fill(c, d.today and accentFill(0.25) or S.RAISED)
            S.SetBorder(c, edge)
            c.tipHead = L.DAY_N:format(d.d) .. S.DOT .. ns.DateText(d.t)
            c.tipText = d.n > 0 and L.DAY_TIP:format(d.done, d.n) or nil
            if d.extra then c.tipText = (c.tipText and (c.tipText .. "\n") or "") .. L.DAY_EXTRA end
        end
    end
    local rows = ns.PinDayRows(pin, P.sel, v)
    P.dayList:SetData(rows)
    local d = days[P.sel]
    local title = P.sel == v.today and L.DAY_TODAY:format(ns.PinDateText(pin, P.sel))
        or L.DAY_OTHER:format(P.sel, ns.PinDateText(pin, P.sel))
    P.dayCard:SetTitle(title, d and d.n > 0 and L.DAY_HINT:format(d.done, d.n) or "")
    P.dayEmpty:SetShown(#rows == 0)
    P.dayEmpty:Set(L.DAY_EMPTY, "")
end

local function refreshBuys(pin, buys)
    P.scope:Select(ns.db.pinScope == "all" and 2 or 1, true)
    P.buyList:SetData(buys.lines)
    P.buyEmpty:SetShown(#buys.lines == 0)
    P.buyEmpty:Set(L.BUYS_EMPTY, "")
end

local function cmpRows(card, x, endText)
    local rows = {
        { L.CMP_WRITS, tostring(x.n) },
        { L.ST_BUY, ns.CostText(x.buy, nil, true) },
        { L.ST_POUCHES, ns.CostText(-x.pouch, nil, true) },
        { L.ST_TOTAL, ns.CostText(x.total, nil, true) },
        { L.CMP_END, endText },
    }
    for i, r in ipairs(rows) do
        card.rows[i][1]:SetText(r[1])
        card.rows[i][2]:SetText(r[2])
    end
end

local function refreshCompare(pin)
    local fresh = ns.fresh
    local calculating = ns.Calculating()
    if not fresh or calculating then
        P.verdict:SetText(hex(S.MUTED) .. L.CMP_WAIT .. "|r")
        P.cmpMine:Hide(); P.cmpNew:Hide()
        P.chgList:SetData({})
        P.chgEmpty:SetShown(false)
        return
    end
    P.cmpMine:Show(); P.cmpNew:Show()
    local c = ns.PinCompare(pin, fresh)
    P.cmpResult = c
    cmpRows(P.cmpMine, c.mine, ns.PinDateText(pin, c.mine.endDay))
    cmpRows(P.cmpNew, c.fresh, ns.PinDateText(pin, c.fresh.endDay))
    local text
    if c.verdict == "same" then text = hex(S.MUTED) .. L.CMP_SAME .. "|r"
    elseif c.verdict == "better" then text = hex(S.GOOD) .. L.CMP_BETTER:format(S.MoneyText(c.diff, true)) .. "|r"
    else text = hex(S.WARN) .. L.CMP_WORSE .. "|r" end
    P.verdict:SetText(text)
    P.chgList:SetData(c.changes)
    P.chgEmpty:SetShown(#c.changes == 0)
    P.chgEmpty:Set(L.CMP_NO_CHANGE, "")
end

-- Draws the Plan tab's pin parts; returns true when a pinned plan (or the list) took the page.
function ns.RefreshPin()
    if not P.view then return false end
    local n = #ns.Plans()
    P.chip:SetShown(n > 0)
    if n > 0 then P.chip:SetText(L.LIST_CHIP:format(n)) end
    if ns.pinPage == "list" then
        P.view:Hide()
        P.listView:Show()
        P.list:SetData(ns.PinListRows())
        return true
    end
    P.listView:Hide()
    local pin = ns.PinShown()
    if not pin then P.view:Hide(); return false end
    local v = ns.PinView(pin)
    P.v = v
    P.view:Show()
    refreshStrip(pin, v)
    refreshBanner(pin, v)
    local buys = ns.PinBuys(pin, ns.pinMode == "buys" and (ns.db.pinScope or "today") or "all")
    P.allBuys = ns.pinMode == "buys" and nil or buys
    P.buys = buys
    place(pin, v)
    P.modes:Select(ns.pinMode == "buys" and 2 or 1, true)
    if ns.compare then refreshCompare(pin) return true end
    refreshTiles(pin, v, buys)
    if ns.pinMode == "buys" then refreshBuys(pin, buys) else refreshDays(pin, v) end
    return true
end

-- The pin button of the footer (Plan tab only).
function ns.RefreshPinButton(onPlan)
    local b = P.pinBtn
    if not b then return end
    local pin = ns.PinShown()
    local show = onPlan and ns.pinPage ~= "list" and not ns.compare
        and ((pin and pin.key == ns.CharKey()) or (not pin and ns.plan ~= nil and #ns.plan.lines > 0))
    b:SetShown(show and true or false)
    if not show then return end
    b:SetText(pin and L.UNPIN or L.PIN)
    b.tip = pin and L.UNPIN_TIP or L.PIN_TIP
    b:SetEnabled(pin ~= nil or (not ns.stale and ns.plan.need > 0))
    local a = pin and S.Accent() or S.MUTED
    b.pic:SetVertexColor(a[1], a[2], a[3], 1)
    S.Fill(b, pin and accentFill(0.25) or S.RAISED)
end

-- The footer's status while a pinned plan shows: how it goes, or the prices of the purchases.
function ns.PinStatus()
    local pin = ns.PinShown()
    if not pin then return nil end
    local v = P.v or ns.PinView(pin)
    if ns.compare then
        local c = P.cmpResult
        if not ns.fresh or ns.Calculating() then return L.CMP_WAIT, S.Accent() end
        if c and c.verdict == "same" then return L.CMP_SAME_LINE, S.MUTED end
        return L.CMP_LINE, nil
    end
    if ns.pinMode == "buys" and P.buys then
        local b = P.buys
        local line = pin.priced and L.PRICED_AT:format(ns.DateText(pin.priced), fmtDate and fmtDate("%H:%M", pin.priced) or "")
            or L.PRICED_NEVER
        if b.left > b.planLeft + 100 then line = line .. " " .. L.DEARER_BY:format(S.MoneyText(b.left - b.planLeft, true))
        elseif b.left < b.planLeft - 100 then line = line .. " " .. L.CHEAPER_BY:format(S.MoneyText(b.planLeft - b.left, true)) end
        return line, b.left > b.planLeft + 100 and S.WARN or nil
    end
    local reset = ns.TimeText and ns.TimeText(ns.ResetIn()) or ""
    if v.behindN > 0 then return L.STATUS_BEHIND:format(v.behindN, reset), S.WARN end
    if v.ofToday > 0 and v.doneToday >= v.ofToday then return L.STATUS_DONE_TODAY:format(reset), S.GOOD end
    return L.STATUS_ON_PLAN:format(reset), nil
end

-- The Today tab's plan card: { title, hint, line, done, of, missN } or nil.
function ns.PinCardInfo()
    local pin = ns.PinFor()
    if not pin then return nil end
    local v = ns.PinView(pin)
    return { title = L.CARD_TITLE:format(v.today, v.endDay), hint = L.CARD_HINT:format(v.doneToday, v.ofToday),
             line = v.ofToday > v.doneToday and L.CARD_LEFT:format(v.ofToday - v.doneToday, v.repToday) or L.CARD_ALL_DONE,
             done = v.doneToday, of = v.ofToday, missN = v.missYesterday and v.missYesterday.n or 0 }
end


-- The Today tab's card of the pinned plan, in place of the tiles; a click opens the plan.
function ns.BuildPinCard(parent)
    local c = CreateFrame("Button", nil, parent)
    S.Box(c, S.SURFACE, S.CARD_EDGE, S.R_LG)
    S.Depth(c, S.R_LG)
    c.icon = S.IconBox(c, 30, ns.PIN_ICON)
    c.icon:SetPoint("LEFT", S.INSET, 0)
    c.hint = S.Text(c, 12, S.MUTED)
    c.hint:SetPoint("TOPRIGHT", -S.INSET, -10)
    c.hint:SetJustifyH("RIGHT")
    c.hint:SetWordWrap(false)
    c.title = S.Text(c, 12, S.GOLD_DIM, nil, "bold")
    c.title:SetPoint("TOPLEFT", c.icon, "TOPRIGHT", 10, 0)
    c.title:SetPoint("RIGHT", c.hint, "LEFT", -8, 0)
    c.title:SetJustifyH("LEFT")
    c.title:SetWordWrap(false)
    c.badge = S.Badge(c, "", S.WARN)
    c.badge:SetPoint("BOTTOMRIGHT", -S.INSET, 10)
    c.dots = {}
    c.line = S.Text(c, 12)
    c.line:SetJustifyH("LEFT")
    c.line:SetWordWrap(false)
    c:SetScript("OnClick", function() if ns.ShowTab then ns.ShowTab(2) end end)
    c:SetScript("OnEnter", function(self) S.SetBorder(self, S.Accent()) end)
    c:SetScript("OnLeave", function(self) S.SetBorder(self, S.CARD_EDGE) end)
    function c:SetInfo(info)
        self:SetShown(info ~= nil)
        if not info then return end
        self.title:SetText(S.Upper(info.title))
        self.hint:SetText(info.hint)
        local x = 0
        for i = 1, math.max(info.of, #self.dots) do
            local d = self.dots[i]
            if i <= info.of and not d then
                d = S.Circle(self, 10, S.FAINT, "ARTWORK", 1)
                self.dots[i] = d
            end
            if d then
                d:SetShown(i <= info.of and i <= 12)
                if i <= info.of and i <= 12 then
                    d:ClearAllPoints()
                    d:SetPoint("BOTTOMLEFT", self.icon, "BOTTOMRIGHT", 10 + x, 2)
                    local col = i <= info.done and S.GOOD or S.FAINT
                    d:SetVertexColor(col[1], col[2], col[3], 1)
                    x = x + 14
                end
            end
        end
        self.line:ClearAllPoints()
        self.line:SetPoint("BOTTOMLEFT", self.icon, "BOTTOMRIGHT", 10 + x + (x > 0 and 4 or 0), 0)
        self.line:SetText(info.line)
        self.badge:Set(info.missN > 0 and L.CARD_MISSED:format(info.missN) or nil, S.WARN)
        self.line:SetPoint("RIGHT", info.missN > 0 and self.badge or self, info.missN > 0 and "LEFT" or "RIGHT",
            info.missN > 0 and -8 or -S.INSET, 0)
    end
    c:Hide()
    return c
end
