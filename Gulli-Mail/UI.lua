-- The panel next to the mailbox, in two tabs: Letters (Take all, the summary, each letter
-- with Take and Return, ticks for Take selected) and Write (names to tap with a search,
-- quick attach by kind, all gold, and a Send button with a line that says what the letter
-- holds). /gml away from a mailbox opens the settings window: the panel's switch and the log.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local panel, tabs, pages = nil, nil, {}
local summary, stats, takeBtn, takeRow, letters, noLetters, takeSel
local names, noNames, search, attachRow, goldBtn, sendBtn, sendLine
local settings, logList, logEmpty
local selected = {}

local PANEL_W, PANEL_H = 380, 728
local TILE_H = 52
local GOLD_ICON = "Interface\\Icons\\INV_Misc_Coin_01"
local SEND_W, SEND_H = 116, 36

-- The tooltip of a quick-attach tile: what goes, most first, and how many fit.
local function kindTip(self)
    if not (GameTooltip and GameTooltip.SetOwner) then return end
    local info = self.info or ns.KindInfo(self.kind)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["KIND_" .. self.kind:upper()])
    if self.kind == "auction" then
        GameTooltip:AddLine(S.HasPrices() and L.TILE_AUCTION or L.TILE_NO_PRICES, 0.8, 0.8, 0.8, true)
    end
    if info.stacks == 0 then
        GameTooltip:AddLine(L.TILE_NONE, 0.6, 0.6, 0.6)
    else
        for i, it in ipairs(info.items) do
            if i > 10 then break end
            GameTooltip:AddDoubleLine(it.name, "x" .. it.count, 1, 1, 1, 1, 1, 1)
        end
        if info.going < info.stacks then
            GameTooltip:AddLine(L.TILE_FIT:format(info.going, info.stacks), 1, 0.82, 0)
        end
    end
    GameTooltip:Show()
end

-- The tooltip of a take-by-kind tile: what the letters hold of that kind, most first.
local function takeTip(self)
    if not (GameTooltip and GameTooltip.SetOwner) then return end
    local info = self.info or ns.InboxKindInfo(self.kind)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["KIND_" .. self.kind:upper()])
    if info.stacks == 0 then
        GameTooltip:AddLine(L.TILE_MAIL_NONE, 0.6, 0.6, 0.6)
    else
        for i, it in ipairs(info.items) do
            if i > 10 then break end
            GameTooltip:AddDoubleLine(it.name, "x" .. it.count, 1, 1, 1, 1, 1, 1)
        end
        GameTooltip:AddLine(L.TILE_MAIL_TAKE, 1, 0.82, 0)
    end
    GameTooltip:Show()
end

-- Four tiles a row, one per quick-attach kind; a `send` kind only on the send side.
local function kindTiles(parent, onClick, tip, sending)
    local row = CreateFrame("Frame", nil, parent)
    row.buttons = {}
    local bw = math.floor((PANEL_W - 2 * S.PAD - 3 * 6) / 4)
    local kinds = {}
    for _, kind in ipairs(ns.ATTACH_KINDS) do
        if sending or not kind.send then kinds[#kinds + 1] = kind end
    end
    local rows = math.ceil(#kinds / 4)
    row:SetHeight(TILE_H * rows + 6 * (rows - 1))
    for k, kind in ipairs(kinds) do
        local b = S.IconTile(row, bw, TILE_H, true)
        local r, col = math.floor((k - 1) / 4), (k - 1) % 4
        b:SetPoint("TOPLEFT", col * (bw + 6), -r * (TILE_H + 6))
        b.kind = kind.key
        b:SetScript("OnClick", function() onClick(kind.key); ns.Refresh() end)
        b:HookScript("OnEnter", tip)
        b:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        row.buttons[#row.buttons + 1] = b
    end
    return row
end

-- Letters tab ---------------------------------------------------------------------------------

local KIND_ICON = {
    sold = "Interface\\Minimap\\Tracking\\Auctioneer",
    bought = "Interface\\Icons\\INV_Misc_Bag_10",
    expired = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    player = "Interface\\Icons\\INV_Letter_15",
    system = "Interface\\Icons\\INV_Letter_15",
}

local function makeLetter(r)
    r.check = S.Check(r, 26)
    r.check:SetPoint("LEFT", -4, 0)
    r.check:SetScript("OnClick", function(self)
        local h = self:GetParent().letter
        selected[h.i] = not selected[h.i] or nil
        ns.Refresh()
    end)
    r.icon = S.IconBox(r, 22)
    r.icon:SetPoint("LEFT", r.check, "RIGHT", 2, 0)
    r.back = S.FitButton(r, L.RETURN_SHORT, 26, 40)
    r.back:SetPoint("RIGHT", -2, 0)
    r.back:SetScript("OnClick", function(self) ns.Return(self:GetParent().letter.i) end)
    r.back:SetScript("OnEnter", function(self)
        if GameTooltip and GameTooltip.SetOwner then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L.RETURN)
            GameTooltip:Show()
        end
    end)
    r.back:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    r.take = S.FitButton(r, L.TAKE, 26, 40)
    r.take:SetPoint("RIGHT", r.back, "LEFT", -4, 0)
    r.take:SetScript("OnClick", function(self) ns.TakeAll({ self:GetParent().letter.i }) end)
    r.from = S.Text(r, 12)
    r.from:SetPoint("BOTTOMLEFT", r.icon, "RIGHT", 8, 1)
    r.from:SetPoint("RIGHT", r.take, "LEFT", -6, 0)
    r.from:SetWordWrap(false)
    r.what = S.Text(r, 12, S.MUTED)
    r.what:SetPoint("TOPLEFT", r.icon, "RIGHT", 8, -1)
    r.what:SetPoint("RIGHT", r.take, "LEFT", -6, 0)
    r.what:SetWordWrap(false)
end

local function fillLetter(r, h)
    r.letter = h
    r.check:SetChecked(selected[h.i] and true or false)
    r.icon:SetIcon(KIND_ICON[h.kind])
    r.from:SetText((h.sender or "?") .. (h.subject and h.subject ~= "" and ("  " .. S.Hex(S.FAINT) .. h.subject .. "|r") or ""))
    local parts = {}
    if h.money > 0 then parts[#parts + 1] = S.MoneyText(h.money) end
    if h.items > 0 then parts[#parts + 1] = L.N_ITEMS:format(h.items) end
    if h.cod > 0 then parts[#parts + 1] = L.COD_SHORT:format(S.MoneyText(h.cod)) end
    local days = h.days < 1 and L.HOURS:format(math.max(0, math.floor(h.days * 24))) or L.DAYS:format(math.floor(h.days))
    local dc = h.days < 3 and S.Hex(S.BAD) or S.Hex(S.FAINT)
    r.what:SetText(dc .. days .. "|r  " .. table.concat(parts, ", "))
    r.take:SetEnabled(not ns.taking and h.cod == 0 and not h.gm and (h.money > 0 or h.items > 0))
    r.back:SetShown(h.canReturn and true or false)
    r.take:ClearAllPoints()
    if h.canReturn then r.take:SetPoint("RIGHT", r.back, "LEFT", -4, 0) else r.take:SetPoint("RIGHT", -2, 0) end
end

-- Write tab -----------------------------------------------------------------------------------

local SELECTED = { S.FILL[1], S.FILL[2], S.FILL[3], 0.34 }
local GROUP = { alt = "ALT", friend = "FRIEND", guild = "GUILD" }

local function makeName(r)
    r.dot = S.Circle(r, 8, S.FILL)
    r.dot:SetPoint("LEFT", 8, 0)
    r.text = S.Text(r, 12)
    r.text:SetPoint("LEFT", 24, 0)
    r.text:SetPoint("RIGHT", -8, 0)
    r.text:SetWordWrap(false)
    r.click = CreateFrame("Button", nil, r)
    r.click:SetAllPoints()
    r.click:SetScript("OnClick", function(self) ns.Pick(self:GetParent().entry.name); ns.Refresh() end)
    r.click:SetScript("OnEnter", function(self) S.Fill(self:GetParent(), S.HOVER) end)
    r.click:SetScript("OnLeave", function(self)
        local row = self:GetParent()
        S.Fill(row, row.picked and SELECTED or S.CLEAR)
    end)
end

local picked = ""
local function fillName(r, e)
    r.entry = e
    local g = GROUP[e.group]
    -- the picked name: a dot and the chosen fill, never colour alone
    r.picked = e.name:lower() == picked
    r.dot:SetShown(r.picked)
    S.Fill(r, r.picked and SELECTED or S.CLEAR)
    r.text:SetText((r.picked and S.Hex(S.Accent()) .. e.name .. "|r" or e.name)
        .. (g and ("  " .. S.Hex(S.FAINT) .. L[g] .. "|r") or ""))
end

-- The line beside Send: who gets the letter and what is in it. The second value says whether
-- Send works now.
function ns.SendLine()
    local st = ns.SendState()
    if st.to == "" then return L.ST_PICK, false, st end
    local parts = {}
    if st.items > 0 then parts[#parts + 1] = L.N_ITEMS:format(st.items) end
    if st.money > 0 then parts[#parts + 1] = S.MoneyText(st.money) end
    if #parts == 0 then return L.ST_TO:format(st.to) .. "\n" .. S.Hex(S.FAINT) .. L.ST_EMPTY .. "|r", st.can, st end
    return L.ST_TO:format(st.to) .. "\n" .. S.Emph(table.concat(parts, ", ")), st.can, st
end

-- Only the send footer and the picked name: runs on every change of the letter.
function ns.RefreshSend()
    if not panel or not panel:IsShown() or not sendLine then return end
    local text, can, st = ns.SendLine()
    sendLine:SetText(text)
    sendBtn:SetEnabled(can and not ns.paused)
    local now = st.to:lower()
    if now ~= picked then
        picked = now
        names:SetData(ns.Names(search and search:GetText()))
    end
end

-- Refresh -------------------------------------------------------------------------------------

function ns.Refresh()
    if settings and settings:IsShown() and ns.RefreshSettings then ns.RefreshSettings() end
    if not panel or not panel:IsShown() then return end
    local s = ns.Summary()
    stats.tiles[1]:Set(S.MoneyText(s.money), nil, L.ST_BOX:format(s.items))
    stats.tiles[2]:Set(S.MoneyText(ns.visit.money), nil, L.ST_VISIT:format(ns.visit.items))
    local lines = {}
    if s.cod > 0 then lines[#lines + 1] = L.COD:format(s.cod) end
    if s.more > 0 then lines[#lines + 1] = L.MORE:format(s.more) end
    if ns.taking and ns.taking.waiting then lines[#lines + 1] = L.WAITING end
    if ns.visit.money > 0 or ns.visit.items > 0 then
        if ns.visit.sold > 0 then lines[#lines + 1] = L.VISIT_SOLD:format(S.MoneyText(ns.visit.sold)) end
    end
    summary:SetText(table.concat(lines, "\n"))
    summary:SetShown(#lines > 0)
    takeBtn:SetEnabled(not ns.taking and (s.items > 0 or s.money > 0 or s.more > 0))
    takeBtn:SetText(ns.taking and L.TAKING or L.TAKE_ALL)
    for _, b in ipairs(takeRow.buttons) do
        local info = ns.InboxKindInfo(b.kind)
        b.info = info
        b:Set({ icon = info.icon, title = L["KIND_" .. b.kind:upper()], count = info.total })
        b:SetEnabled(not ns.taking and info.stacks > 0)
    end

    local list = ns.Letters()
    local n, keep = 0, {}
    for _, h in ipairs(list) do if selected[h.i] then n = n + 1; keep[h.i] = true end end
    for i in pairs(selected) do if not keep[i] then selected[i] = nil end end
    letters:SetData(list)
    noLetters:SetShown(#list == 0)
    takeSel:SetText(L.TAKE_SELECTED:format(n))
    takeSel:SetEnabled(n > 0 and not ns.taking)

    picked = ns.SendState().to:lower()
    local nm = ns.Names(search and search:GetText())
    names:SetData(nm)
    noNames:SetShown(#nm == 0)
    -- the tiles and the gold work from any tab: a click opens the send tab itself
    for _, b in ipairs(attachRow.buttons) do
        local info = ns.KindInfo(b.kind)
        b.info = info
        b:Set({ icon = info.icon, title = L["KIND_" .. b.kind:upper()], count = info.going })
        b:SetEnabled(info.stacks > 0 and info.going > 0)
    end
    local gold = ns.GoldToSend()
    goldBtn:SetEnabled(gold > 0)
    goldBtn:SetText(L.ALL_GOLD:format(S.MoneyText(gold)))
    ns.RefreshSend()
end

local function showPage(i)
    for j, p in ipairs(pages) do p:SetShown(i == j) end
    if i == 2 and MailFrameTab2 and MailFrameTab2.Click then MailFrameTab2:Click() end
    ns.Refresh()
end

local function buildPanel()
    panel = S.Window("GulliMailPanel", L.TITLE, PANEL_W, PANEL_H)
    local body = panel.body
    tabs = S.PageTabs(body, { L.TAB_LETTERS, L.TAB_WRITE }, math.floor((PANEL_W - 2 * S.PAD - 4) / 2), showPage, nil,
        { S.TAB.mail, S.TAB.write })
    for i = 1, 2 do
        local p = CreateFrame("Frame", nil, body)
        p:SetPoint("TOPLEFT", 0, -30 - S.GAP)
        p:SetPoint("BOTTOMRIGHT")
        pages[i] = p
    end

    -- Letters
    local p = pages[1]
    takeBtn = S.Primary(S.Button(p, 1, 34))
    takeBtn:SetPoint("TOPLEFT")
    takeBtn:SetPoint("TOPRIGHT")
    takeBtn:SetScript("OnClick", function() ns.TakeAll(); ns.Refresh() end)
    takeRow = kindTiles(p, function(key) ns.TakeAll(nil, key) end, takeTip)
    takeRow:SetPoint("TOPLEFT", takeBtn, "BOTTOMLEFT", 0, -6)
    takeRow:SetPoint("TOPRIGHT", takeBtn, "BOTTOMRIGHT", 0, -6)
    stats = S.StatRow(p, { "", "" }, 56, { "Interface\\Icons\\INV_Letter_15", "Interface\\Icons\\INV_Misc_Coin_01" })
    stats:SetPoint("TOPLEFT", takeRow, "BOTTOMLEFT", 0, -8)
    stats:SetPoint("TOPRIGHT", takeRow, "BOTTOMRIGHT", 0, -8)
    stats:Layout(PANEL_W - 2 * S.PAD)
    summary = S.Note(p, 12)
    summary:SetPoint("TOPLEFT", stats, "BOTTOMLEFT", 0, -6)
    summary:SetPoint("RIGHT")
    summary:SetMaxLines(6)
    takeSel = S.Button(p, 1, 30)
    takeSel:SetPoint("BOTTOMLEFT")
    takeSel:SetPoint("BOTTOMRIGHT")
    takeSel:SetScript("OnClick", function()
        local list = {}
        for i in pairs(selected) do list[#list + 1] = i end
        wipe(selected)
        ns.TakeAll(list)
        ns.Refresh()
    end)
    local card = S.Card(p, nil)
    card:SetPoint("TOPLEFT", stats, "BOTTOMLEFT", 0, -(8 + 16 * 2))
    card:SetPoint("BOTTOMRIGHT", takeSel, "TOPRIGHT", 0, 8)
    letters = S.List(card.body, 40, makeLetter, fillLetter)
    letters:SetPoint("TOPLEFT")
    letters:SetPoint("BOTTOMRIGHT", -10, 0)
    noLetters = S.Empty(card.body)
    noLetters:Set(L.NO_LETTERS, "")

    -- Write
    p = pages[2]
    search = S.Edit(p, 1, 28)
    search:SetPoint("TOPLEFT")
    search:SetPoint("TOPRIGHT")
    search:SetJustifyH("LEFT")
    S.Placeholder(search, L.SEARCH)
    search:SetScript("OnTextChanged", function() ns.Refresh() end)
    local tools = CreateFrame("Frame", nil, p)
    tools:SetPoint("BOTTOMLEFT")
    tools:SetPoint("BOTTOMRIGHT")
    attachRow = kindTiles(tools, ns.AttachKind, kindTip, true)
    tools:SetHeight(attachRow:GetHeight() + (30 + 6) + (SEND_H + 8))
    attachRow:SetPoint("TOPLEFT")
    attachRow:SetPoint("TOPRIGHT")
    goldBtn = S.Button(tools, 1, 30)
    S.SetButtonIcon(goldBtn, GOLD_ICON)
    goldBtn:SetPoint("TOPLEFT", attachRow, "BOTTOMLEFT", 0, -6)
    goldBtn:SetPoint("TOPRIGHT", attachRow, "BOTTOMRIGHT", 0, -6)
    goldBtn:SetScript("OnClick", function() ns.FillGold(); ns.Refresh() end)
    -- our own Send: a click on the game's button, with what the letter holds beside it
    sendBtn = S.Primary(S.Button(tools, SEND_W, SEND_H))
    sendBtn:SetPoint("BOTTOMRIGHT")
    sendBtn:SetText(L.SEND)
    sendBtn:SetScript("OnClick", function() ns.Send() end)
    sendLine = S.Text(tools, 12, S.MUTED)
    sendLine:SetPoint("LEFT", tools, "BOTTOMLEFT", 2, SEND_H / 2)
    sendLine:SetPoint("RIGHT", sendBtn, "LEFT", -8, 0)
    sendLine:SetJustifyH("LEFT")
    sendLine:SetWordWrap(true)
    sendLine:SetMaxLines(2)
    local nameCard = S.Card(p, L.SEND_TO)
    nameCard:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -8)
    nameCard:SetPoint("BOTTOMRIGHT", tools, "TOPRIGHT", 0, 8)
    names = S.List(nameCard.body, 30, makeName, fillName)
    names:SetPoint("TOPLEFT")
    names:SetPoint("BOTTOMRIGHT", -10, 0)
    -- Before any alt or letter is known the list is empty; say how it fills.
    noNames = S.Empty(nameCard.body)
    noNames:Set(L.NO_NAMES, L.NO_NAMES_SUB)

    showPage(1)
    panel:SetScript("OnShow", function() ns.Refresh() end)
end

-- The panel sits right of the open letter when there is one, else right of the mailbox, so it
-- never covers the letter the player is reading.
function ns.PanelAnchor()
    if OpenMailFrame and OpenMailFrame:IsShown() then return OpenMailFrame end
    return MailFrame
end

local function place()
    if not panel then return end
    local to = ns.PanelAnchor()
    panel:ClearAllPoints()
    if to then panel:SetPoint("TOPLEFT", to, "TOPRIGHT", 8, 0) else panel:SetPoint("CENTER") end
end

local hooked
function ns.ShowPanel()
    if not panel then buildPanel() end
    if not hooked and OpenMailFrame and OpenMailFrame.HookScript then
        hooked = true
        OpenMailFrame:HookScript("OnShow", place)
        OpenMailFrame:HookScript("OnHide", place)
    end
    if not ns.sendHooked and SendMailFrame and SendMailFrame.HookScript then
        ns.sendHooked = true
        SendMailFrame:HookScript("OnShow", function() ns.Refresh() end)
        SendMailFrame:HookScript("OnHide", function() ns.Refresh() end)
    end
    place()
    panel:Show()
end

function ns.HidePanel() if panel then panel:Hide() end end
function ns.ShowTab(i) if tabs then tabs:Select(i) end end

-- Settings window -----------------------------------------------------------------------------

local function makeLog(r)
    r.text = S.Text(r, 12)
    r.text:SetPoint("LEFT", 4, 0)
    r.text:SetPoint("RIGHT", -4, 0)
    r.text:SetWordWrap(false)
end

local function fillLog(r, e)
    local when = date and date("%d.%m %H:%M", e.t) or tostring(e.t)
    local what = {}
    if e.money > 0 then what[#what + 1] = S.MoneyText(e.money) end
    if e.items > 0 then what[#what + 1] = L.N_ITEMS:format(e.items) end
    r.text:SetText(S.Hex(S.FAINT) .. when .. "|r  " .. e.sender .. "  " .. table.concat(what, ", "))
end

function ns.RefreshSettings()
    if not settings then return end
    logList:SetData(ns.db.log)
    logEmpty:SetShown(#ns.db.log == 0)
end

-- One switch, the log, and one line about Take all: there is nothing else to set.
local function buildSettings()
    settings = S.Window("GulliMailFrame", L.TITLE, S.NARROW_W, S.DOCK_H)
    local body, width = settings.body, settings.inner[1]
    local card, h = S.SettingsCard(body, nil, {
        { L.OPT_PANEL, nil, function() return ns.db.panel end, function(v) ns.db.panel = v; ns.Refresh() end,
          icon = ns.OPT_ICON.panel },
    })
    card:SetPoint("TOPLEFT")
    card:SetPoint("TOPRIGHT")
    card:SetHeight(h)
    local hint = S.Note(body, 12)
    hint:SetPoint("BOTTOMLEFT", 2, 0)
    hint:SetPoint("BOTTOMRIGHT", -2, 0)
    hint:SetWidth(width - 4)
    hint:SetText(L.TAKE_HINT)
    local lcard = S.Card(body, L.LOG_TITLE, nil, "Interface\\Icons\\INV_Misc_PocketWatch_01")
    lcard:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, -S.GAP)
    lcard:SetPoint("BOTTOMRIGHT", 0, 40)
    logList = S.List(lcard.body, 26, makeLog, fillLog)
    logList:SetPoint("TOPLEFT")
    logList:SetPoint("BOTTOMRIGHT", -10, 0)
    logEmpty = S.Empty(lcard.body)
    logEmpty:Set(L.LOG_EMPTY, "")
    settings:SetScript("OnShow", function() ns.RefreshSettings() end)
end

function ns.Toggle()
    if ns.open then
        if panel and panel:IsShown() then panel:Hide() else ns.ShowPanel() end
        return
    end
    S.ToggleWindow(ns.Window())
end

-- The settings window, for the hub (/gulli) to show inside it. The mailbox panel stays at the
-- mailbox.
function ns.Window()
    if not settings then buildSettings() end
    return settings
end
