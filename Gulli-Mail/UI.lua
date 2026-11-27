-- The panel next to the mailbox, in two tabs: Letters (Take all, the summary, each letter
-- with Take and Return, ticks for Take selected) and Write (names to tap with a search,
-- quick attach by kind, all gold, and a Send button with a line that says what the letter
-- holds, and the letters the mailing rules would send). /gml away from a mailbox opens the
-- settings window: the panel's switch, the mailing rules and the log.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local panel, tabs, pages = nil, nil, {}
local summary, stats, takeBtn, takeRow, letters, noLetters, takeSel
local names, noNames, search, attachRow, goldBtn, sendBtn, sendLine
local tools, rulesBox, ruleRows, rulesMore = nil, nil, {}, nil
local settings, logList, logEmpty, setTabs, setPages, rulesList, rulesEmpty, addBtn
local selected = {}

local PANEL_W, PANEL_H = 380, 728
local TILE_H = 52
local GOLD_ICON = "Interface\\Icons\\INV_Misc_Coin_01"
local SEND_W, SEND_H = 116, 36
local RULE_H, RULES_MAX, RULES_HEAD = 38, 3, 22

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

-- The letters of the mailing rules: a row each (the kind, how many, who gets them), Fill puts
-- one letter together. Shown only while a rule has something to send.
local function makeRuleRow(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(RULE_H)
    S.Box(r, S.SURFACE, S.CARD_EDGE, S.R_MD)
    r.icon = S.IconBox(r, 26)
    r.icon:SetPoint("LEFT", 6, 0)
    r.fill = S.FitButton(r, L.FILL, 28, 64)
    r.fill:SetPoint("RIGHT", -5, 0)
    r.fill:SetScript("OnClick", function(self) ns.FillRule(self:GetParent().index); ns.Refresh() end)
    r.what = S.Text(r, 12)
    r.what:SetPoint("BOTTOMLEFT", r.icon, "RIGHT", 8, 1)
    r.what:SetPoint("RIGHT", r.fill, "LEFT", -6, 0)
    r.what:SetWordWrap(false)
    r.to = S.Text(r, 12, S.MUTED)
    r.to:SetPoint("TOPLEFT", r.icon, "RIGHT", 8, -1)
    r.to:SetPoint("RIGHT", r.fill, "LEFT", -6, 0)
    r.to:SetWordWrap(false)
    r:EnableMouse(true)
    r:SetScript("OnEnter", function(self)
        if not (GameTooltip and GameTooltip.SetOwner and self.entry) then return end
        local e = self.entry
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["KIND_" .. e.kind:upper()] .. " » " .. e.to)
        if e.rule.auto then GameTooltip:AddLine(ns.RuleWhy(e.rule), 0.8, 0.8, 0.8, true) end
        GameTooltip:AddLine(L.RULE_LETTERS:format(e.letters), 1, 0.82, 0)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return r
end

-- Why a profession rule sends there: "By profession: Alchemy 250".
function ns.RuleWhy(rule)
    if not rule.auto then return nil end
    local prof = L["PROF_" .. tostring(rule.line)] or ""
    return L.RULE_AUTO:format(prof .. (rule.rank and rule.rank > 0 and (" " .. rule.rank) or ""))
end

local function layoutTools(n)
    local shown = math.min(n, RULES_MAX)
    local h = shown > 0 and (RULES_HEAD + shown * (RULE_H + 4) + 4) or 0
    rulesBox:SetHeight(math.max(1, h))
    rulesBox:SetShown(shown > 0)
    attachRow:ClearAllPoints()
    attachRow:SetPoint("TOPLEFT", 0, -h)
    attachRow:SetPoint("TOPRIGHT", 0, -h)
    tools:SetHeight(h + attachRow:GetHeight() + (30 + 6) + (SEND_H + 8))
end

local function refreshRules()
    local list = ns.RuleLetters()
    for i, r in ipairs(ruleRows) do
        local e = list[i]
        r:SetShown(e ~= nil)
        if e then
            r.entry, r.index = e, i
            r.icon:SetIcon(ns.KindInfo(e.kind).icon or ns.KindIcon(e.kind))
            r.what:SetText(L["KIND_" .. e.kind:upper()] .. "  " .. S.Emph("x" .. e.total))
            local why = e.rule.auto and (S.Hex(S.FAINT) .. "  " .. L.RULE_AUTO_SHORT .. "|r") or ""
            r.to:SetText("» " .. S.Hex(S.Accent()) .. e.to .. "|r" .. why)
            r.fill:SetEnabled(not ns.paused)
        end
    end
    rulesMore:SetText(#list > RULES_MAX and L.RULES_MORE:format(#list - RULES_MAX) or "")
    layoutTools(#list)
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
    refreshRules()
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
    tools = CreateFrame("Frame", nil, p)
    tools:SetPoint("BOTTOMLEFT")
    tools:SetPoint("BOTTOMRIGHT")
    rulesBox = CreateFrame("Frame", nil, tools)
    rulesBox:SetPoint("TOPLEFT")
    rulesBox:SetPoint("TOPRIGHT")
    local head = S.Text(rulesBox, 12, S.GOLD_DIM, nil, "bold")
    head:SetPoint("TOPLEFT", 2, -3)
    head:SetText(S.Upper(L.RULES_TITLE))
    local edit = S.Ghost(S.FitButton(rulesBox, L.RULES_EDIT, 20, 40))
    edit:SetPoint("TOPRIGHT", 0, 0)
    edit:SetScript("OnClick", function() ns.ShowRules() end)
    rulesMore = S.Text(rulesBox, 12, S.FAINT)
    rulesMore:SetPoint("RIGHT", edit, "LEFT", -6, 0)
    head:SetPoint("RIGHT", rulesMore, "LEFT", -6, 0)
    head:SetWordWrap(false)
    head:SetJustifyH("LEFT")
    for i = 1, RULES_MAX do
        local r = makeRuleRow(rulesBox)
        r:SetPoint("TOPLEFT", 0, -(RULES_HEAD + (i - 1) * (RULE_H + 4)))
        r:SetPoint("TOPRIGHT", 0, -(RULES_HEAD + (i - 1) * (RULE_H + 4)))
        ruleRows[i] = r
    end
    attachRow = kindTiles(tools, ns.AttachKind, kindTip, true)
    layoutTools(0)
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

-- A mailing rule: the kind (a click turns to the next, a right-click back), the recipient
-- (typed, or the next own character from the button beside it), an on/off switch, and Remove
-- for the player's own rules. The line under it says where a rule comes from.
local function makeRule(r)
    r.kind = S.Button(r, 150, 30)
    r.kind:SetPoint("TOPLEFT", 4, -6)
    r.kind:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.kind:SetScript("OnClick", function(self, button)
        local rule = self:GetParent().rule
        if rule and not rule.auto then ns.CycleRuleKind(rule.index, button == "RightButton"); ns.Refresh() end
    end)
    r.arrow = S.Text(r, 14, S.FAINT)
    r.arrow:SetPoint("LEFT", r.kind, "RIGHT", 6, 0)
    r.arrow:SetText("»")
    r.on = S.Switch(r)
    r.on:SetPoint("RIGHT", -4, 0)
    r.on:SetScript("OnClick", function(self)
        local rule = self:GetParent().rule
        ns.SetRuleOn(rule, rule.off and true or false)
        ns.Refresh()
    end)
    r.pick = S.Button(r, 30, 30)
    r.pick:SetPoint("RIGHT", r.on, "LEFT", -10, 0)
    r.pick:SetPoint("TOP", r.kind, "TOP")
    S.SetButtonIcon(r.pick, S.TAB.char)
    r.pick.btnIcon:ClearAllPoints()
    r.pick.btnIcon:SetPoint("CENTER")
    r.pick:SetScript("OnClick", function(self) ns.CycleRuleTo(self:GetParent().rule); ns.Refresh() end)
    r.pick:SetScript("OnEnter", function(self)
        if GameTooltip and GameTooltip.SetOwner then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L.PICK_OWN)
            GameTooltip:Show()
        end
    end)
    r.pick:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    r.to = S.Edit(r, 120, 30)
    r.to:SetPoint("LEFT", r.arrow, "RIGHT", 6, 0)
    r.to:SetPoint("RIGHT", r.pick, "LEFT", -6, 0)
    r.to:SetJustifyH("LEFT")
    S.Placeholder(r.to, L.RULE_NAME)
    local function save(self)
        local rule = self:GetParent().rule
        if rule and strtrim(self:GetText() or "") ~= (rule.to or "") then ns.SetRuleTo(rule, self:GetText()); ns.Refresh() end
    end
    r.to:SetScript("OnEnterPressed", function(self) save(self); self:ClearFocus() end)
    r.to:SetScript("OnEditFocusLost", save)
    r.to:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    r.why = S.Text(r, 12, S.FAINT)
    r.why:SetPoint("TOPLEFT", r.kind, "BOTTOMLEFT", 4, -4)
    r.why:SetWordWrap(false)
    r.del = S.Ghost(S.FitButton(r, L.REMOVE, 20, 40))
    r.del:SetPoint("TOPRIGHT", r.pick, "BOTTOMRIGHT", 0, -2)
    r.del:SetScript("OnClick", function(self) ns.RemoveRule(self:GetParent().rule.index); ns.Refresh() end)
    r.why:SetPoint("RIGHT", r.del, "LEFT", -6, 0)
end

local function fillRule(r, rule)
    r.rule = rule
    r.kind:SetText(L["KIND_" .. rule.kind:upper()])
    S.SetButtonIcon(r.kind, ns.KindIcon(rule.kind))
    if not (r.to.HasFocus and r.to:HasFocus()) and r.to:GetText() ~= rule.to then r.to:SetText(rule.to or "") end
    r.on:SetChecked(not rule.off)
    r.del:SetShown(not rule.auto)
    local why
    if rule.off then why = L.RULE_OFF
    elseif rule.auto then why = ns.RuleWhy(rule)
    elseif (rule.to or "") == "" then why = L.RULE_NO_NAME
    else why = L.RULE_OWN end
    r.why:SetText(why)
    r:SetAlpha(rule.off and 0.6 or 1)
end

function ns.RefreshSettings()
    if not settings then return end
    local rules = ns.Rules()
    rulesList:SetData(rules)
    rulesEmpty:SetShown(#rules == 0)
    logList:SetData(ns.db.log)
    logEmpty:SetShown(#ns.db.log == 0)
end

-- The panel's switch on top, then two pages: the mailing rules (Add a rule in the footer) and
-- the log with one line about Take all.
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
    local footer = S.Footer(settings)
    addBtn = footer:Add(S.Primary(S.FitButton(footer, L.ADD_RULE, 32, 140)))
    addBtn:SetScript("OnClick", function() ns.AddRule(); ns.Refresh() end)
    setPages = {}
    setTabs = S.PageTabs(body, { L.TAB_RULES, L.TAB_LOG }, math.floor((width - 4) / 2), function(i)
        for j, pg in ipairs(setPages) do pg:SetShown(i == j) end
        footer:SetShown(i == 1)
        ns.RefreshSettings()
    end, nil, { S.TAB.rules, S.TAB.recent })
    setTabs.frame:ClearAllPoints()
    setTabs.frame:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, -S.GAP)
    for i = 1, 2 do
        local pg = CreateFrame("Frame", nil, body)
        pg:SetPoint("TOPLEFT", setTabs.frame, "BOTTOMLEFT", 0, -S.GAP)
        pg:SetPoint("BOTTOMRIGHT")
        setPages[i] = pg
    end

    local rcard = S.Card(setPages[1], nil)
    rcard:SetAllPoints()
    local help = S.Note(rcard.body, 12)
    help:SetPoint("TOPLEFT", 2, 0)
    help:SetPoint("TOPRIGHT", -2, 0)
    help:SetText(L.RULES_HELP)
    help:SetMaxLines(3)
    rulesList = S.List(rcard.body, 62, makeRule, fillRule)
    rulesList:SetPoint("TOPLEFT", 0, -52)
    rulesList:SetPoint("BOTTOMRIGHT", -10, 0)
    rulesEmpty = S.Empty(rcard.body)
    rulesEmpty:Set(L.RULES_EMPTY, L.RULES_EMPTY_SUB)

    local hint = S.Note(setPages[2], 12)
    hint:SetPoint("BOTTOMLEFT", 2, 0)
    hint:SetPoint("BOTTOMRIGHT", -2, 0)
    hint:SetWidth(width - 4)
    hint:SetText(L.TAKE_HINT)
    local lcard = S.Card(setPages[2], L.LOG_TITLE, nil, "Interface\\Icons\\INV_Misc_PocketWatch_01")
    lcard:SetPoint("TOPLEFT")
    lcard:SetPoint("BOTTOMRIGHT", 0, 40)
    logList = S.List(lcard.body, 26, makeLog, fillLog)
    logList:SetPoint("TOPLEFT")
    logList:SetPoint("BOTTOMRIGHT", -10, 0)
    logEmpty = S.Empty(lcard.body)
    logEmpty:Set(L.LOG_EMPTY, "")
    setTabs:Select(1)
    settings:SetScript("OnShow", function() ns.RefreshSettings() end)
end

function ns.ShowLogTab() if setTabs then setTabs:Select(2) end end

-- The settings window on its Rules page (the link on the Write tab).
function ns.ShowRules()
    local w = ns.Window()
    if not w:IsShown() then S.ToggleWindow(w) end
    if setTabs then setTabs:Select(1) end
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
