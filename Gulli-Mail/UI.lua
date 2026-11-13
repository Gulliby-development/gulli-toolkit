-- The panel next to the mailbox, in two tabs: Letters (Take all, the summary, each letter
-- with Take and Return, ticks for Take selected) and Write (names to tap with a search,
-- quick attach by kind, gold to another character, mailing rules). /gml away from a mailbox
-- opens the settings window: what Take all takes, the free slots to keep, the rules and
-- the log.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local panel, tabs, pages = nil, nil, {}
local summary, stats, takeBtn, letters, noLetters, takeSel
local names, noNames, search, attachRow, goldBtn, ruleBtn
local settings, rulesList, logList
local selected = {}

local PANEL_W, PANEL_H = 380, 560
local TILE_H = 52
local GOLD_ICON = "Interface\\Icons\\INV_Misc_Coin_01"

-- The tooltip of a quick-attach tile: what goes, most first, and how many fit.
local function kindTip(self)
    if not (GameTooltip and GameTooltip.SetOwner) then return end
    local info = self.info or ns.KindInfo(self.kind)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["KIND_" .. self.kind:upper()])
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
    r.from:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, 1)
    r.from:SetPoint("RIGHT", r.take, "LEFT", -6, 0)
    r.from:SetWordWrap(false)
    r.what = S.Text(r, 10, S.MUTED)
    r.what:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 8, -2)
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

local GROUP = { alt = "ALT", friend = "FRIEND", guild = "GUILD" }

local function makeName(r)
    r.text = S.Text(r, 12)
    r.text:SetPoint("LEFT", 10, 0)
    r.text:SetPoint("RIGHT", -8, 0)
    r.text:SetWordWrap(false)
    r.click = CreateFrame("Button", nil, r)
    r.click:SetAllPoints()
    r.click:SetScript("OnClick", function(self) ns.Pick(self:GetParent().entry.name) end)
    r.click:SetScript("OnEnter", function(self) S.Fill(self:GetParent(), S.HOVER) end)
    r.click:SetScript("OnLeave", function(self) S.Fill(self:GetParent(), S.CLEAR) end)
end

local function fillName(r, e)
    r.entry = e
    local g = GROUP[e.group]
    r.text:SetText(e.name .. (g and ("  " .. S.Hex(S.FAINT) .. L[g] .. "|r") or ""))
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
    if s.off > 0 then lines[#lines + 1] = L.OFF:format(s.off) end
    if s.more > 0 then lines[#lines + 1] = L.MORE:format(s.more) end
    if ns.taking and ns.taking.waiting then lines[#lines + 1] = L.WAITING end
    if ns.visit.money > 0 or ns.visit.items > 0 then
        if ns.visit.sold > 0 then lines[#lines + 1] = L.VISIT_SOLD:format(S.MoneyText(ns.visit.sold)) end
    end
    summary:SetText(table.concat(lines, "\n"))
    summary:SetShown(#lines > 0)
    takeBtn:SetEnabled(not ns.taking and (s.items > 0 or s.money > 0 or s.more > 0))
    takeBtn:SetText(ns.taking and L.TAKING or L.TAKE_ALL)

    local list = ns.Letters()
    local n, keep = 0, {}
    for _, h in ipairs(list) do if selected[h.i] then n = n + 1; keep[h.i] = true end end
    for i in pairs(selected) do if not keep[i] then selected[i] = nil end end
    letters:SetData(list)
    noLetters:SetShown(#list == 0)
    takeSel:SetText(L.TAKE_SELECTED:format(n))
    takeSel:SetEnabled(n > 0 and not ns.taking)

    local nm = ns.Names(search and search:GetText())
    names:SetData(nm)
    noNames:SetShown(#nm == 0)
    local sending = SendMailFrame and SendMailFrame.IsShown and SendMailFrame:IsShown()
    for _, b in ipairs(attachRow.buttons) do
        local info = ns.KindInfo(b.kind)
        b.info = info
        b:Set({ icon = info.icon, title = L["KIND_" .. b.kind:upper()], count = info.going })
        b:SetEnabled(sending and info.stacks > 0)
    end
    goldBtn:SetEnabled(sending)
    goldBtn:SetText(L.FILL_GOLD:format(ns.db.keepGold))
    local rule = ns.NextRule()
    ruleBtn:SetEnabled(sending and rule ~= nil)
    ruleBtn:SetText(rule and L.APPLY_RULE:format(L["KIND_" .. rule.kind:upper()], rule.to) or L.NO_RULE)
end

local function showPage(i)
    for j, p in ipairs(pages) do p:SetShown(i == j) end
    if i == 2 and MailFrameTab2 and MailFrameTab2.Click then MailFrameTab2:Click() end
    ns.Refresh()
end

local function buildPanel()
    panel = S.Window("GulliMailPanel", L.TITLE, PANEL_W, PANEL_H)
    local body = panel.body
    tabs = S.Tabs(body, { L.TAB_LETTERS, L.TAB_WRITE }, math.floor((PANEL_W - 2 * S.PAD - 4) / 2), showPage, nil,
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
    stats = S.StatRow(p, { "", "" }, 56, { "Interface\\Icons\\INV_Letter_15", "Interface\\Icons\\INV_Misc_Coin_01" })
    stats:SetPoint("TOPLEFT", takeBtn, "BOTTOMLEFT", 0, -8)
    stats:SetPoint("TOPRIGHT", takeBtn, "BOTTOMRIGHT", 0, -8)
    stats:Layout(PANEL_W - 2 * S.PAD)
    summary = S.Note(p, 11)
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
    tools:SetHeight(TILE_H * 2 + 6 + 2 * (30 + 6) + 18)
    attachRow = CreateFrame("Frame", nil, tools)
    attachRow:SetPoint("TOPLEFT")
    attachRow:SetPoint("TOPRIGHT")
    attachRow:SetHeight(TILE_H * 2 + 6)
    attachRow.buttons = {}
    local bw = math.floor((PANEL_W - 2 * S.PAD - 3 * 6) / 4)
    for k, kind in ipairs(ns.ATTACH_KINDS) do
        local b = S.IconTile(attachRow, bw, TILE_H, true)
        local row, col = math.floor((k - 1) / 4), (k - 1) % 4
        b:SetPoint("TOPLEFT", col * (bw + 6), -row * (TILE_H + 6))
        b.kind = kind.key
        b:SetScript("OnClick", function() ns.AttachKind(kind.key); ns.Refresh() end)
        b:HookScript("OnEnter", kindTip)
        b:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        attachRow.buttons[#attachRow.buttons + 1] = b
    end
    goldBtn = S.Button(tools, 1, 30)
    S.SetButtonIcon(goldBtn, GOLD_ICON)
    goldBtn:SetPoint("TOPLEFT", attachRow, "BOTTOMLEFT", 0, -6)
    goldBtn:SetPoint("TOPRIGHT", attachRow, "BOTTOMRIGHT", 0, -6)
    goldBtn:SetScript("OnClick", function() ns.FillGold() end)
    ruleBtn = S.Button(tools, 1, 30)
    ruleBtn:SetPoint("TOPLEFT", goldBtn, "BOTTOMLEFT", 0, -6)
    ruleBtn:SetPoint("TOPRIGHT", goldBtn, "BOTTOMRIGHT", 0, -6)
    ruleBtn:SetScript("OnClick", function() ns.ApplyRule(); ns.Refresh() end)
    S.SetButtonIcon(ruleBtn, S.TAB.rules)
    local hint = S.Note(tools, 10)
    hint:SetPoint("TOPLEFT", ruleBtn, "BOTTOMLEFT", 0, -4)
    hint:SetPoint("RIGHT")
    hint:SetText(L.SEND_HINT)
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

local function makeRule(r)
    r.kind = S.Button(r, 120, 28)
    r.kind:SetPoint("LEFT", 0, 0)
    r.kind:SetScript("OnClick", function(self)
        local rule = self:GetParent().rule
        local idx = 1
        for k, kind in ipairs(ns.ATTACH_KINDS) do if kind.key == rule.kind then idx = k end end
        rule.kind = ns.ATTACH_KINDS[idx % #ns.ATTACH_KINDS + 1].key
        ns.Refresh()
    end)
    r.arrow = S.Text(r, 12, S.MUTED)
    r.arrow:SetPoint("LEFT", r.kind, "RIGHT", 8, 0)
    r.arrow:SetText(">")
    r.del = S.Button(r, 28, 28)
    r.del:SetPoint("RIGHT", -2, 0)
    r.del:SetText("x")
    r.del:SetScript("OnClick", function(self) ns.RemoveRule(self:GetParent().index); ns.Refresh() end)
    r.to = S.Edit(r, 1, 28)
    r.to:SetPoint("LEFT", r.arrow, "RIGHT", 8, 0)
    r.to:SetPoint("RIGHT", r.del, "LEFT", -6, 0)
    r.to:SetJustifyH("LEFT")
    r.to:SetScript("OnTextChanged", function(self) local rr = self:GetParent().rule if rr then rr.to = strtrim(self:GetText() or "") end end)
end

local function fillRule(r, rule, i)
    r.rule, r.index = rule, i
    r.kind:SetText(L["KIND_" .. rule.kind:upper()])
    S.SetButtonIcon(r.kind, ns.KindIcon(rule.kind))
    if r.to:GetText() ~= rule.to then r.to:SetText(rule.to or "") end
end

local function makeLog(r)
    r.text = S.Text(r, 11)
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
    rulesList:SetData(ns.db.rules)
    logList:SetData(ns.db.log)
end

local function buildSettings()
    settings = S.Window("GulliMailFrame", L.TITLE, S.NARROW_W, S.DOCK_H)
    local body, width = settings.body, settings.inner[1]
    local spages = {}
    local stabs = S.Tabs(body, { L.TAB_SETTINGS, L.TAB_RULES, L.TAB_LOG }, math.floor((width - 4) / 3), function(i)
        for j, sp in ipairs(spages) do sp:SetShown(i == j) end
        ns.RefreshSettings()
    end, nil, { S.TAB.settings, S.TAB.rules, S.TAB.recent })
    for i = 1, 3 do
        local sp = CreateFrame("Frame", nil, body)
        sp:SetPoint("TOPLEFT", 0, -30 - S.GAP)
        sp:SetPoint("BOTTOMRIGHT")
        spages[i] = sp
    end

    local st = S.Stack(spages[1])
    local rows = {}
    for _, k in ipairs({ "panel", "money", "sold", "bought", "expired", "player" }) do
        rows[#rows + 1] = { L["OPT_" .. k:upper()], nil, function() return ns.db[k] end,
                            function(v) ns.db[k] = v; ns.Refresh() end, icon = ns.OPT_ICON[k] }
    end
    local free = S.Stepper(spages[1], function() return ns.db.keepFree end, function(v) ns.db.keepFree = v end, 1, 0, 20)
    rows[#rows + 1] = { L.OPT_KEEPFREE, nil, control = free, icon = ns.OPT_ICON.keepFree }
    local gold = S.Stepper(spages[1], function() return ns.db.keepGold end, function(v) ns.db.keepGold = v; ns.Refresh() end,
        10, 0, 100000, function(v) return v .. "g" end)
    rows[#rows + 1] = { L.OPT_KEEPGOLD, nil, control = gold, icon = ns.OPT_ICON.keepGold }
    local card, h = S.SettingsCard(spages[1], nil, rows)
    st:Add(card, h)
    local tip, th = S.Paragraph(spages[1], L.HELP, width)
    st:Add(tip, th)

    local add = S.Button(spages[2], 1, 30)
    add:SetPoint("BOTTOMLEFT")
    add:SetPoint("BOTTOMRIGHT")
    add:SetText(L.ADD_RULE)
    add:SetScript("OnClick", function() ns.AddRule(); ns.Refresh() end)
    local rcard = S.Card(spages[2], L.TAB_RULES, nil, "Interface\\Icons\\INV_Letter_15")
    rcard:SetPoint("TOPLEFT")
    rcard:SetPoint("BOTTOMRIGHT", add, "TOPRIGHT", 0, 8)
    local rhelp = S.Note(rcard.body, 11)
    rhelp:SetPoint("TOPLEFT")
    rhelp:SetPoint("TOPRIGHT")
    rhelp:SetText(L.RULES_HELP)
    rulesList = S.List(rcard.body, 36, makeRule, fillRule)
    rulesList:SetPoint("TOPLEFT", 0, -36)
    rulesList:SetPoint("BOTTOMRIGHT", -10, 0)

    local lcard = S.Card(spages[3], L.TAB_LOG, nil, "Interface\\Icons\\INV_Misc_PocketWatch_01")
    lcard:SetAllPoints()
    logList = S.List(lcard.body, 26, makeLog, fillLog)
    logList:SetPoint("TOPLEFT")
    logList:SetPoint("BOTTOMRIGHT", -10, 0)

    stabs:Select(1)
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
