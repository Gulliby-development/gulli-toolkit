-- The window, narrow, with three tabs. Deals: the scan line (when the next scan runs, how many
-- lots it saw, what the list is worth) over a dense list (12 pt, 24 px rows) of the lines that
-- sell to a vendor for more than they cost, each with its own small button, and the big button
-- in the footer that works on the top line, with few words: what a list or a button does is in
-- its tooltip. History: what was bought to sell. Settings: the switches and limits, and in the
-- footer the button that reads the whole market. A page with nothing for the footer hides it,
-- so its list reaches the bottom of the window. At the auction house it opens beside the auction window, in the shared
-- side tabs.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, tabs, pages = nil, nil, {}
local scanIcon, scanText, sumText, bar, dealCard, dealList, dealEmpty, heads
local histStats, histList, histEmpty, cards, buyBtn, scanBtn, wholeBtn, viewTabs, worthHead
local tab, period = 1, "all"
local ROW, HIST_ROW = 24, 24
-- column widths from the right: button, gain, vendor, auction, quantity
local W_BTN, W_GAIN, W_VEND, W_AH, W_N, COL_GAP = 72, 58, 74, 66, 34, 6
ns.ROW_H = ROW

local function money(c) return S.MoneyText(c, c >= 10000) end

local function clock(sec)
    sec = math.max(0, math.floor(sec or 0))
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

-- ---------- deal rows ----------

local function col(r, width, right)
    local t = S.Text(r, 12)
    t:SetJustifyH("RIGHT")
    t:SetWordWrap(false)
    t:SetWidth(width)
    t:SetPoint("RIGHT", r, "RIGHT", right, 0)
    return t
end

local function makeDealRow(r)
    r.icon = S.ItemIcon(r, 18)
    r.icon:SetPoint("LEFT", 4, 0)
    local x = -2
    r.btn = S.Button(r, W_BTN, 20)
    S.SetFont(r.btn.text, 12)
    r.btn:SetPoint("RIGHT", x, 0)
    r.btn:SetScript("OnClick", function(self) ns.Click(self:GetParent().line) end)
    r.state = S.Text(r, 12)
    r.state:SetJustifyH("CENTER")
    r.state:SetWordWrap(false)
    r.state:SetWidth(W_BTN)
    r.state:SetPoint("RIGHT", x, 0)
    x = x - W_BTN - COL_GAP
    r.gain = col(r, W_GAIN, x)
    x = x - W_GAIN - COL_GAP
    r.vendor = col(r, W_VEND, x)
    x = x - W_VEND - COL_GAP
    r.ah = col(r, W_AH, x)
    x = x - W_AH - COL_GAP
    r.n = col(r, W_N, x)
    r.n:SetTextColor(S.MUTED[1], S.MUTED[2], S.MUTED[3], 1)
    x = x - W_N - COL_GAP
    r.name = S.Text(r, 12)
    r.name:SetWordWrap(false)
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.name:SetPoint("RIGHT", r, "RIGHT", x, 0)
    -- the full name and the lot in the game's tooltip
    r:EnableMouse(true)
    r:SetScript("OnEnter", function(self)
        local line = self.line
        if not line or not GameTooltip or not GameTooltip.SetOwner then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetItemByID then GameTooltip:SetItemByID(line.id) else GameTooltip:SetText(self.full or "") end
        -- what the columns mean for this line: prices of one, and what a click buys
        if GameTooltip.AddLine then
            for _, text in ipairs(ns.LineTip(line)) do GameTooltip:AddLine(text, 1, 1, 1, true) end
        end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

-- The tooltip lines of a deal: how many at what price of one, and what one click buys.
function ns.LineTip(line)
    local each = line.each or line.cost / math.max(1, line.n)
    local sellEach = line.sellEach or line.value / math.max(1, line.n)
    local lot = line.mode == "d" and L.TIP_LOT_DE or L.TIP_LOT
    local out = { lot:format(line.left or line.n, S.MoneyText(math.floor(each + 0.5)), S.MoneyText(sellEach)) }
    if line.left then out[2] = L.TIP_ONE:format(S.MoneyText(line.gain))
    else out[2] = L.TIP_ALL:format(line.n, S.MoneyText(line.gain)) end
    return out
end

-- What a line's button says and does: text, primary, enabled; or the state word in its place.
function ns.RowButton(line)
    local b = ns.buy
    if line.state == "bought" then return nil, L.BOUGHT, S.GOOD end
    if line.state == "gone" then return nil, L.GONE, S.FAINT end
    if line.state == "lose" then return nil, L.LOSE, S.BAD end
    -- one of the lot was just bought: the rest waits for its new auction id
    if line.stale then return { text = L.PRICE_WAIT, on = false } end
    if b.line == line then
        if b.phase == "quote" then return { text = L.PRICE_WAIT, on = false } end
        if b.phase == "buying" then return { text = L.BUYING, on = false } end
        if b.phase == "ready" then return { text = S.MoneyIcons(b.quote.total, b.quote.total >= 10000), primary = true, on = true } end
    end
    -- while another purchase runs a click queues the line; a queued line shows its place
    local pos = ns.QueuePos(line)
    if pos then return { text = L.QUEUED:format(pos), primary = line == ns.Top(), on = ns.atAH == true } end
    return { text = line.kind == "c" and L.PRICE or L.BUY, primary = line == ns.Top(), on = ns.atAH == true }
end

local function fillDealRow(r, line)
    r.line = line
    local name, q, icon = ns.ItemInfo(line.id)
    r.full = name or ""
    r.icon:Set(icon or "Interface\\Icons\\INV_Misc_QuestionMark", nil, q or 1)
    local faint = line.state == "gone" or line.state == "bought"
    r.name:SetText((faint and S.Hex(S.FAINT) or S.QualityHex(q or 1)) .. (name or "...") .. "|r")
    r.n:SetText(tostring(line.n))
    -- both prices are for one, so they compare at a glance; the gain is for the whole line
    r.ah:SetText(money(math.floor((line.each or line.cost / math.max(1, line.n)) + 0.5)))
    r.vendor:SetText(money(line.sellEach or line.value / math.max(1, line.n)))
    r.gain:SetText(S.Hex(faint and S.FAINT or S.GOOD) .. "+" .. "|r" .. money(line.gain))
    r:SetAlpha(line.state == "bought" and 0.55 or 1)
    local spec, word, color = ns.RowButton(line)
    r.btn:SetShown(spec ~= nil)
    r.state:SetShown(spec == nil)
    if spec then
        r.btn:SetText(spec.text)
        r.btn:SetEnabled(spec.on)
        if spec.primary then S.Primary(r.btn)
        else
            -- back to a plain button: the skin paints by kind on the next hover
            r.btn.kind = "normal"
            S.Fill(r.btn, S.RAISED)
            S.SetBorder(r.btn, S.LINE)
            local a = S.Accent()
            r.btn.text:SetTextColor(a[1], a[2], a[3], 1)
        end
    else
        r.state:SetText(S.Hex(color) .. word .. "|r")
    end
    -- the line the big button buys is lit
    local cur = line == ns.Top() and not line.state
    S.Fill(r, cur and { S.FILL[1], S.FILL[2], S.FILL[3], 0.34 } or S.CLEAR)
end

-- ---------- history rows ----------

local fmtDate = date or (os and os.date)

local function makeHistRow(r)
    r.when = S.Text(r, 12, S.FAINT)
    r.when:SetPoint("LEFT", 4, 0)
    r.when:SetWidth(84)
    r.when:SetWordWrap(false)
    r.icon = S.ItemIcon(r, 18)
    r.icon:SetPoint("LEFT", r.when, "RIGHT", 4, 0)
    r.got = col(r, 70, -2)
    r.paid = col(r, 70, -2 - 70 - COL_GAP)
    r.n = col(r, W_N, -2 - 140 - 2 * COL_GAP)
    r.n:SetTextColor(S.MUTED[1], S.MUTED[2], S.MUTED[3], 1)
    r.name = S.Text(r, 12)
    r.name:SetWordWrap(false)
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.name:SetPoint("RIGHT", r, "RIGHT", -2 - 140 - W_N - 3 * COL_GAP, 0)
    r:EnableMouse(true)
    r:SetScript("OnMouseUp", function(self, button) if button == "RightButton" then ns.Keep(self.e) end end)
    r:SetScript("OnEnter", function(self)
        if not GameTooltip or not GameTooltip.SetOwner or not self.e then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.full or "", 1, 1, 1)
        if not self.e.keep and self.e.sold < self.e.n then GameTooltip:AddLine(L.KEEP_TIP, 0.8, 0.8, 0.8, true) end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

local function fillHistRow(r, e)
    r.e = e
    local name, q, icon = ns.ItemInfo(e.id)
    r.full = name or ""
    r.when:SetText(fmtDate and fmtDate(L.DATE, e.at) or "")
    r.icon:Set(icon or "Interface\\Icons\\INV_Misc_QuestionMark", nil, q or 1)
    r.name:SetText(S.QualityHex(q or 1) .. (name or "...") .. "|r")
    r.n:SetText(tostring(e.n))
    r.paid:SetText(money(e.paid))
    if e.keep then r.got:SetText(S.Hex(S.FAINT) .. L.KEPT .. "|r")
    elseif e.sold >= e.n then r.got:SetText(S.Hex(S.GOOD) .. "+|r" .. money(e.value))
    else r.got:SetText(S.Hex(S.FAINT) .. money(e.value) .. "|r") end
end

-- ---------- refresh ----------

local function label(b, text, min, max)
    b:SetText(text)
    local w = math.max(min, math.floor((b.text:GetStringWidth() or 0) + 28))
    b:SetWidth(max and math.min(w, max) or w)
    return w
end

-- The scan line: what runs now, or when the next scan comes, and the list's worth.
function ns.ScanLine()
    local s = ns.scan
    if not ns.CanScan() then return L.NO_API, 0 end
    if s.held and s.phase ~= "idle" then return L.SCAN_HELD, 0 end
    local browse = s.full and L.SCAN_FULL or L.SCAN_BROWSE
    -- nobody knows how many pages the whole market has: its bar fills with the lots looked at
    if s.phase == "browse" then return browse:format(#s.results), s.full and 0 or math.min(1, s.pages / s.maxPages) end
    if s.phase == "sift" then return browse:format(#s.results), #s.results > 0 and s.sifted / #s.results or 1 end
    if s.phase == "detail" then return L.SCAN_DETAIL:format(math.min(s.done + 1, s.n), s.n), s.n > 0 and s.done / s.n or 0 end
    if time() < s.quietUntil then return L.SCAN_QUIET, 0 end
    local left = ns.NextIn()
    if not left then return L.SCAN_OFF, 0 end
    return L.NEXT_SCAN:format(clock(left)), 1 - left / ns.Interval()
end

local function bigButton()
    local line = ns.Top()
    if not line then label(buyBtn, L.BUY_NONE, 140); buyBtn:SetEnabled(false); return end
    local b = ns.buy
    local text
    if b.line == line and b.phase == "ready" then text = L.BUY_FOR:format(S.MoneyIcons(b.quote.total, b.quote.total >= 10000))
    elseif b.line == line and b.phase == "quote" then text = L.PRICE_WAIT
    elseif b.line == line and b.phase == "buying" then text = L.BUYING
    else
        local name = ns.ItemInfo(line.id) or "..."
        text = L.BUY_TOP:format(name)
        -- a long name gives way to the plain verb, never cut
        buyBtn:SetText(text)
        if (buyBtn.text:GetStringWidth() or 0) + 28 > 300 then text = L.BUY_TOP_PLAIN end
    end
    label(buyBtn, text, 140, 300)
    buyBtn:SetEnabled(ns.atAH == true and b.phase ~= "quote" and b.phase ~= "buying")
end

local function refreshDeals()
    local text, frac = ns.ScanLine()
    scanText:SetText(text)
    bar:Set(frac)
    local shown = ns.Shown()
    local open, worth = 0, 0
    for _, line in ipairs(shown) do if not line.state then open, worth = open + 1, worth + line.gain end end
    -- while a scan runs its line needs the room
    sumText:SetText((open > 0 and not ns.Scanning()) and L.SUM:format(open, money(worth)) or "")
    dealList:SetData(shown)
    dealEmpty:SetShown(#shown == 0)
    local de = ns.view == "d"
    -- each list says how many deals it holds, and under the tabs what its gain comes from
    for i, v in ipairs(ns.VIEWS) do
        local n = ns.Open(v)
        viewTabs.buttons[i].text:SetText(L["VIEW_" .. v:upper()] .. (n > 0 and (" (" .. n .. ")") or ""))
    end
    worthHead:SetText(S.Upper(de and L.COL_DE or L.COL_VENDOR))
    -- one short line; the why is in the tooltips and on the Settings tab
    if de and not ns.Enchanter() then dealEmpty:Set(L.DE_NEED)
    elseif de and ns.db.de == false then dealEmpty:Set(L.DE_OFF)
    elseif not ns.atAH then dealEmpty:Set(L.NOT_AT_AH)
    elseif ns.Scanning() or not ns.scan.at then dealEmpty:Set(text)
    elseif de then dealEmpty:Set(L.EMPTY_DE)
    else dealEmpty:Set(L.EMPTY) end
    heads:SetShown(#shown > 0)
    scanBtn:SetEnabled(ns.atAH == true and ns.CanScan() and not ns.Scanning())
    bigButton()
    buyBtn:Show()
    local b = ns.buy
    if b.err then
        frame.footer:SetStatus(L[b.err], S.BAD)
    elseif #ns.queue > 0 then
        frame.footer:SetStatus(L.QUEUE_LINE:format(#ns.queue))
    else
        frame.footer:SetStatus("")
    end
end

local function refreshHistory()
    local list, sum = ns.History(period)
    histList:SetData(list)
    histEmpty:SetShown(#list == 0)
    histStats.tiles[1]:Set(S.MoneyText(sum.profit, true))
    histStats.tiles[2]:Set(tostring(sum.count))
    histStats.tiles[3]:Set("+" .. sum.pct .. "%")
end

function ns.Refresh()
    if S.SideRefresh then S.SideRefresh() end -- the number on its tab beside the auction house
    if not frame or not frame:IsShown() then return end
    if tab == 1 then return refreshDeals() end
    if tab == 2 then return refreshHistory() end
    for _, card in ipairs(cards) do
        for _, row in ipairs(card.rows) do if row.control and row.control.Refresh then row.control:Refresh() end end
    end
    wholeBtn:SetEnabled(ns.atAH == true and ns.CanScan() and not ns.Scanning())
    frame.footer:SetStatus(ns.PricesLine())
end

-- The footer of the Settings tab: how many prices the module holds and how old the last look at
-- the whole market is.
function ns.PricesLine()
    local m = ns.Market()
    if not m or (m.n or 0) == 0 then return L.PRICES_NONE end
    if not m.at then return L.PRICES_PART:format(m.n) end
    local mins = math.max(0, math.floor((time() - m.at) / 60))
    local span = mins < 60 and L.MINS:format(mins) or L.HOURS:format(math.floor(mins / 60))
    return L.PRICES_LINE:format(m.n, span)
end

-- ---------- build ----------

local function head(parent, text, width, right)
    local t = S.Text(parent, 12, S.GOLD_DIM, nil, "bold")
    t:SetText(S.Upper(text))
    t:SetWordWrap(false)
    if width then
        t:SetWidth(width)
        t:SetJustifyH("RIGHT")
        t:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", right, 2)
    end
    return t
end

-- A tooltip of a title and a line, on a frame that keeps its own scripts.
local function tip(f, title, text)
    f:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(type(title) == "function" and title() or title, 1, 1, 1)
        local t = type(text) == "function" and text() or text
        if t and t ~= "" then GameTooltip:AddLine(t, nil, nil, nil, true) end
        GameTooltip:Show()
    end)
    f:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

-- The footer of each page: Deals the buy button, Settings the button that reads the whole
-- market; History has none, so the footer hides and its list takes the room.
local function showFooter(i)
    buyBtn:SetShown(i == 1)
    wholeBtn:SetShown(i == 3)
    frame.footer:SetShown(i ~= 2)
    frame.footer.status:SetPoint("RIGHT", i == 3 and wholeBtn or buyBtn, "LEFT", -12, 0)
    -- set here too: the footer's own hooks do not run while the window is hidden
    frame.body:SetPoint("BOTTOMRIGHT", -S.PAD, (i ~= 2 and S.FOOTER_H or 0) + S.PAD)
end

local function build()
    frame = S.Window("GulliVendorFlipFrame", L.TITLE, S.NARROW_W, S.DOCK_H, { sub = "/gvf" })
    local ft = S.Footer(frame)
    buyBtn = S.Primary(S.Button(ft, 200, 32))
    ft:Add(buyBtn)
    buyBtn:SetScript("OnClick", function() ns.Click(ns.Top()) end)
    tip(buyBtn, function() return buyBtn.text and buyBtn.text:GetText() or "" end, L.HOW)
    wholeBtn = S.Primary(S.Button(ft, 200, 32))
    wholeBtn:SetPoint("RIGHT", -S.PAD, 0)
    label(wholeBtn, L.SCAN_ALL, 140, 240)
    wholeBtn:SetScript("OnClick", function() ns.Scan(true, true); ns.Refresh() end)
    tip(wholeBtn, L.SCAN_ALL, function() return L.SCAN_ALL_TIP .. "\n\n" .. L.PRICES_TIP end)
    wholeBtn:Hide()
    tabs = S.PageTabs(frame.body, { L.TAB_DEALS, L.TAB_HISTORY, L.TAB_SETTINGS }, nil, function(i)
        tab = i
        for j, p in ipairs(pages) do p:SetShown(j == i) end
        showFooter(i)
        ns.Refresh()
    end, nil, { "Interface\\Icons\\INV_Misc_Coin_02", S.TAB.recent, S.TAB.settings })
    for i = 1, 3 do
        local p = CreateFrame("Frame", nil, frame.body)
        p:SetPoint("TOPLEFT", 0, -30 - S.GAP)
        p:SetPoint("BOTTOMRIGHT")
        p:SetShown(i == 1)
        pages[i] = p
    end

    -- Deals
    local dp = pages[1]
    scanIcon = S.IconBox(dp, 20, "Interface\\Icons\\INV_Misc_PocketWatch_01")
    scanIcon:SetPoint("TOPLEFT", 0, -4)
    scanBtn = S.Button(dp, 120, 28)
    scanBtn:SetPoint("TOPRIGHT", 0, 0)
    label(scanBtn, L.REFRESH, 96)
    scanBtn:SetScript("OnClick", function() ns.Scan(true) end)
    scanBtn:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText(L.REFRESH, 1, 1, 1)
        GameTooltip:AddLine(L.REFRESH_TIP, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    scanBtn:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    sumText = S.Text(dp, 12, S.MUTED)
    sumText:SetPoint("RIGHT", scanBtn, "LEFT", -10, 0)
    sumText:SetJustifyH("RIGHT")
    sumText:SetWordWrap(false)
    scanText = S.Text(dp, 12, S.MUTED)
    scanText:SetPoint("LEFT", scanIcon, "RIGHT", 8, 0)
    scanText:SetPoint("RIGHT", sumText, "LEFT", -10, 0)
    scanText:SetWordWrap(false)
    scanText:SetJustifyH("LEFT")
    bar = S.Progress(dp, 4)
    bar:SetPoint("TOPLEFT", 0, -34)
    bar:SetPoint("TOPRIGHT", 0, -34)

    -- which list: what sells to a vendor for more, or what disenchants for more
    -- the two lists, named by what the player does with a purchase; each half of the page wide,
    -- so a count fits beside the name
    viewTabs = S.Tabs(dp, { L.VIEW_V, L.VIEW_D }, math.floor(frame.inner[1] / 2) - 2,
                      function(i) ns.SetView(ns.VIEWS[i]) end, 28,
                      { "Interface\\Icons\\INV_Misc_Coin_02", ns.OPT_ICON.de })
    viewTabs.frame:ClearAllPoints()
    viewTabs.frame:SetPoint("TOPLEFT", 0, -34 - 4 - S.GAP)
    -- what each list holds is its tooltip, not a paragraph over the list
    tip(viewTabs.buttons[1], L.VIEW_V, L.VIEW_V_HINT)
    tip(viewTabs.buttons[2], L.VIEW_D, L.VIEW_D_HINT)

    dealCard = S.Card(dp)
    dealCard:SetPoint("TOPLEFT", 0, -34 - 4 - S.GAP - 28 - S.GAP)
    dealCard:SetPoint("BOTTOMRIGHT")
    heads = CreateFrame("Frame", nil, dealCard.body)
    heads:SetPoint("TOPLEFT")
    heads:SetPoint("TOPRIGHT", -10, 0)
    heads:SetHeight(18)
    local x = -2 - W_BTN - COL_GAP
    head(heads, L.COL_GAIN, W_GAIN, x); x = x - W_GAIN - COL_GAP
    worthHead = head(heads, L.COL_VENDOR, W_VEND, x); x = x - W_VEND - COL_GAP
    head(heads, L.COL_AH, W_AH, x); x = x - W_AH - COL_GAP
    head(heads, L.COL_N, W_N, x); x = x - W_N - COL_GAP
    local item = head(heads, L.COL_ITEM)
    item:SetPoint("BOTTOMLEFT", 28, 2)
    item:SetPoint("RIGHT", heads, "RIGHT", x, 0)
    dealList = S.List(dealCard.body, ROW, makeDealRow, fillDealRow)
    dealList:SetPoint("TOPLEFT", 0, -22)
    dealList:SetPoint("BOTTOMRIGHT")
    dealEmpty = S.Empty(dealCard.body)
    dealEmpty:Set(L.NOT_AT_AH, L.NOT_AT_AH_SUB)

    -- History
    local hp = pages[2]
    local st = S.Stack(hp)
    local periodTabs = S.Tabs(hp, { L.PERIOD_day, L.PERIOD_week, L.PERIOD_all }, nil, function(i)
        period = ns.PERIODS[i]
        ns.Refresh()
    end, 28)
    periodTabs:Select(3, true)
    periodTabs.frame:ClearAllPoints()
    periodTabs.frame:SetPoint("TOPLEFT")
    st:Space(28 + S.GAP)
    histStats = S.StatRow(hp, { L.ST_PROFIT, L.ST_COUNT, L.ST_PCT }, 62,
        { "Interface\\Icons\\INV_Misc_Coin_02", "Interface\\Minimap\\Tracking\\Auctioneer", "Interface\\Icons\\INV_Misc_Coin_01" })
    st:Add(histStats, 62)
    histStats:Layout(frame.inner[1])
    local histCard = S.Card(hp, L.HISTORY, "", S.TAB.recent)
    histCard:SetPoint("TOPLEFT", 0, -st.y)
    histCard:SetPoint("BOTTOMRIGHT")
    local hh = CreateFrame("Frame", nil, histCard.body)
    hh:SetPoint("TOPLEFT")
    hh:SetPoint("TOPRIGHT", -10, 0)
    hh:SetHeight(18)
    local when = head(hh, L.COL_WHEN)
    when:SetPoint("BOTTOMLEFT", 4, 2)
    when:SetWidth(84)
    head(hh, L.COL_GOT, 70, -2)
    head(hh, L.COL_PAID, 70, -2 - 70 - COL_GAP)
    head(hh, L.COL_N, W_N, -2 - 140 - 2 * COL_GAP)
    histList = S.List(histCard.body, HIST_ROW, makeHistRow, fillHistRow)
    histList:SetPoint("TOPLEFT", 0, -22)
    histList:SetPoint("BOTTOMRIGHT")
    histEmpty = S.Empty(histCard.body)
    histEmpty:Set(L.HIST_EMPTY, L.HIST_EMPTY_SUB)

    -- Settings: a card per question. Scan, what the vendor list buys (each kind with its own
    -- qualities), the disenchant list, the limits, sound and selling, the prices kept.
    local sp = pages[3]
    local page = S.ScrollPage(sp, frame.inner[1])
    page:SetAllPoints()
    local inner = page.inner
    cards = {}
    local stack = S.Stack(inner)
    local function switch(key)
        return { L["OPT_" .. key], L["TIP_" .. key], function() return ns.db[key] ~= false and ns.db[key] ~= nil end,
                 function(v) ns.SetPref(key, v and true or false) end, icon = ns.OPT_ICON[key] }
    end
    local function moneyRow(key, min)
        return { L["OPT_" .. key], L["TIP_" .. key], icon = ns.OPT_ICON[key],
                 control = S.MoneyStepper(inner, function() return ns.db[key] end, function(v) ns.SetPref(key, v) end,
                                          min, ns.MAX_MONEY) }
    end
    -- A row of ticks, one per quality, for the kind above it (prefix gq: gear, oq: the rest).
    local function qualities(prefix)
        local row = CreateFrame("Frame", nil, inner)
        row.height = 36
        local boxes, x = {}, 38
        for _, q in ipairs(ns.QUALITIES) do
            local key = prefix .. q
            local cell = CreateFrame("Button", nil, row)
            local c = S.Check(cell, 26)
            c:SetPoint("LEFT")
            local t = S.Text(cell, 12)
            t:SetPoint("LEFT", c, "RIGHT", 2, 0)
            t:SetWordWrap(false)
            t:SetText(S.QualityHex(q) .. L["Q" .. q] .. "|r")
            local w = 26 + 2 + math.ceil(t:GetStringWidth() or 40)
            cell:SetSize(w, 30)
            cell:SetPoint("LEFT", x, 0)
            x = x + w + 10
            local function toggle() ns.SetPref(key, ns.db[key] == false) end
            cell:SetScript("OnClick", toggle)
            c:SetScript("OnClick", toggle)
            boxes[#boxes + 1] = { c, key }
        end
        row.control = { Refresh = function() for _, b in ipairs(boxes) do b[1]:SetChecked(ns.db[b[2]] ~= false) end end }
        row.control.Refresh()
        row:SetScript("OnShow", row.control.Refresh)
        row.line = S.Divider(row)
        row.line:SetPoint("BOTTOMLEFT")
        row.line:SetPoint("BOTTOMRIGHT")
        row.line:SetHeight(1)
        return row
    end
    local function card(title, rows, icon)
        local c = S.Card(inner, title, nil, icon)
        c.rows = {}
        local st = S.Stack(c.body, 0)
        S.rowWidth = S.GuessWidth(inner) - 2 * S.INSET
        for i, r in ipairs(rows) do
            local row = r.row or (r.control and S.SettingRow(c.body, r[1], r[2], r.control, nil, r.icon))
                or S.SwitchRow(c.body, r[1], r[2], r[3], r[4], nil, r.icon)
            if r.row then row:SetParent(c.body) end
            st:Add(row, row.height)
            row.line:SetShown(i < #rows)
            c.rows[i] = row
        end
        S.rowWidth = nil
        stack:Add(c, c:Fit(st:Height() - 6))
        cards[#cards + 1] = c
        return c
    end
    -- the interval steps through ns.INTERVALS
    local function slot()
        for i, v in ipairs(ns.INTERVALS) do if v == ns.Interval() then return i end end
        return 1
    end
    card(L.CARD_SCAN, {
        switch("scan"),
        { L.OPT_interval, L.TIP_interval, icon = ns.OPT_ICON.interval,
          control = S.Stepper(inner, slot, function(i) ns.SetPref("interval", ns.INTERVALS[i]) end, 1, 1, #ns.INTERVALS,
                              function(i)
                                  local v = ns.INTERVALS[i]
                                  return v < 60 and L.SECS:format(v) or L.MINS:format(v / 60)
                              end, 130) },
        switch("auto"),
    })
    card(L.FILTERS, { switch("gear"), { row = qualities("gq") }, switch("goods"), { row = qualities("oq") } })
    card(L.CARD_DE, { switch("de") })
    card(L.CARD_LIMITS, {
        moneyRow("minGain", ns.MIN_GAIN), moneyRow("reserve", 0),
        { L.OPT_keepFree, L.TIP_keepFree, icon = ns.OPT_ICON.keepFree,
          control = S.Stepper(inner, function() return ns.db.keepFree end, function(v) ns.SetPref("keepFree", v) end,
                              1, 0, 30, nil, 130) },
    })
    card(L.CARD_NOTIFY, { switch("sound"), moneyRow("soundAt", 1), switch("sell") })
    -- the prices kept and the button that reads every lot are in the footer, always at hand
    page:SetContent(stack:Height())
    frame.settingsPage = page

    frame:SetScript("OnShow", function() ns.Refresh() end)
end

function ns.Toggle()
    -- at the auction house its tab may be behind another module's: the command brings it up
    local open, shown = S.SideIs("VendorFlip")
    if open and not shown then S.SideOpen("VendorFlip", true); ns.Refresh(); return end
    S.ToggleWindow(ns.Window())
end

-- Opens a tab: 1 deals, 2 history, 3 settings.
function ns.ShowTab(i)
    ns.Window()
    tabs:Select(i)
end

-- Shows one list of the Deals page: "v" vendor, "d" disenchant.
function ns.ShowView(view)
    ns.ShowTab(1)
    for i, v in ipairs(ns.VIEWS) do if v == view then viewTabs:Select(i) end end
end

-- The window, for the hub (/gulli) to show inside it.
function ns.Window()
    if not frame then build() end
    return frame
end

-- At the auction house: beside its window, unless the window sits in the hub. The place is
-- shared with the other modules that have work there (the skin's side tabs).
function ns.ShowAtAH()
    local w = ns.Window()
    if w.docked then if w:IsShown() then ns.Refresh() end return end
    S.SideOpen("VendorFlip")
    ns.Refresh()
end

function ns.HideAtAH()
    S.SideClose("VendorFlip")
    ns.Refresh()
end

S.SideAdd({ key = "VendorFlip", order = 30, title = function() return L.TITLE end,
            icon = "Interface\\AddOns\\Gulli-VendorFlip\\icon",
            window = function() return ns.Window() end, badge = function() return ns.atAH and ns.Open() or 0 end })
