-- Three pages: Phrases (big buttons and where they go), Group (an LFM message from a quest)
-- and Missed (whispers from fights and AFK, with Reply and Busy).

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, tabs, pages = nil, nil, {}
local current = 1
local phraseButtons, channelButtons = {}, {}
local editing = false
local lfm = { index = 1, count = 1, roles = {} }

---- Phrases --------------------------------------------------------------------

local COLS, BTN_H = 3, 44

local function layoutPhrases()
    local page = pages[1]
    local list = ns.Phrases()
    local width = (page:GetWidth() > 1 and page:GetWidth() or 640)
    local w = math.floor((width - (COLS - 1) * 8) / COLS)
    for i, text in ipairs(list) do
        local b = phraseButtons[i]
        if not b then
            b = S.Button(page.grid, w, BTN_H)
            b.text:SetWordWrap(true)
            b.text:SetPoint("LEFT", 6, 0)
            b.text:SetPoint("RIGHT", -6, 0)
            b:SetScript("OnClick", function(self)
                if editing then
                    ns.RemovePhrase(self.index)
                    layoutPhrases()
                else
                    ns.Say(self.phrase)
                end
            end)
            phraseButtons[i] = b
        end
        b:SetSize(w, BTN_H)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", ((i - 1) % COLS) * (w + 8), -math.floor((i - 1) / COLS) * (BTN_H + 8))
        b.index, b.phrase = i, text
        b:SetText(editing and (S.Hex(S.BAD) .. "x|r  " .. text) or text)
        b:Show()
    end
    for i = #list + 1, #phraseButtons do phraseButtons[i]:Hide() end
    page.grid:SetHeight(math.ceil(#list / COLS) * (BTN_H + 8))
    page.scroll:Update(math.ceil(#list / COLS) * (BTN_H + 8))
    page.add:SetShown(editing)
    page.addBtn:SetShown(editing)
    page.reset:SetShown(editing)
    page.edit:SetText(editing and L.DONE or L.EDIT)
    for i, ch in ipairs(ns.CHANNELS) do
        if ch == ns.db.channel and page.channels.selected ~= i then page.channels:Select(i, true) end
    end
end

local function buildPhrases(page)
    local labels = {}
    for i, ch in ipairs(ns.CHANNELS) do labels[i] = L["CH_" .. ch] end
    page.channels = S.Tabs(page, labels, 96, function(i) ns.db.channel = ns.CHANNELS[i]; layoutPhrases() end)
    channelButtons = page.channels.buttons
    page.edit = S.Ghost(S.Button(page, 90, 30))
    page.edit:SetPoint("TOPRIGHT", 0, 0)
    page.edit:SetScript("OnClick", function() editing = not editing; layoutPhrases() end)

    local scroll = S.Scroll(page)
    scroll:SetPoint("TOPLEFT", 0, -30 - S.GAP)
    scroll:SetPoint("BOTTOMRIGHT", -12, 44)
    page.scroll = scroll
    page.grid = scroll.child
    page.grid:SetWidth(640)

    page.add = S.Edit(page, 400, 30)
    page.add:SetPoint("BOTTOMLEFT", 0, 0)
    page.add:SetJustifyH("LEFT")
    page.add:SetMaxLetters(200)
    page.addBtn = S.Primary(S.Button(page, 90, 30))
    page.addBtn:SetPoint("LEFT", page.add, "RIGHT", 8, 0)
    page.addBtn:SetText(L.ADD)
    local function add()
        if ns.AddPhrase(page.add:GetText()) then page.add:SetText("") end
        page.add:ClearFocus()
        layoutPhrases()
    end
    page.addBtn:SetScript("OnClick", add)
    page.add:SetScript("OnEnterPressed", add)
    page.reset = S.Ghost(S.Button(page, 120, 30))
    page.reset:SetPoint("BOTTOMRIGHT", 0, 0)
    page.reset:SetText(L.RESET)
    page.reset:SetScript("OnClick", function() ns.ResetPhrases(); layoutPhrases() end)
    local hint = S.Note(page, 11)
    hint:SetPoint("BOTTOMLEFT", 0, 8)
    hint:SetPoint("RIGHT", 0, 0)
    hint:SetText(L.TOKENS)
    page.hint = hint
    page.Update = function()
        hint:SetShown(not editing)
        layoutPhrases()
    end
end

---- Group (LFM) ----------------------------------------------------------------

local function lfmText()
    local quests = ns.Quests()
    if lfm.index > #quests then lfm.index = 1 end
    return ns.LFM(quests[lfm.index], lfm.count, lfm.roles), quests
end

local function buildGroup(page)
    local card = S.Card(page, L.QUEST)
    card:SetPoint("TOPLEFT")
    card:SetPoint("TOPRIGHT")
    card:SetHeight(36 + 30 + 12 + 42 + 12)
    local cb = card.body
    local prev = S.Button(cb, 36, 30)
    prev:SetPoint("TOPLEFT")
    prev:SetText("<")
    local nextB = S.Button(cb, 36, 30)
    nextB:SetPoint("TOPRIGHT")
    nextB:SetText(">")
    local title = S.Text(cb, 13)
    title:SetPoint("LEFT", prev, "RIGHT", 10, 0)
    title:SetPoint("RIGHT", nextB, "LEFT", -10, 0)
    title:SetJustifyH("CENTER")
    title:SetWordWrap(false)

    local cLabel = S.Text(cb, 12, S.MUTED)
    cLabel:SetPoint("TOPLEFT", 0, -50)
    cLabel:SetText(L.HOW_MANY)
    local countTabs = S.Tabs(cb, { "1", "2", "3", "4" }, 40, function(n) lfm.count = n; page.Update() end)
    countTabs.frame:ClearAllPoints()
    countTabs.frame:SetPoint("LEFT", cLabel, "RIGHT", 10, 0)
    local roles, prevRole = {}, nil
    for i = #ns.ROLES, 1, -1 do
        local r = ns.ROLES[i]
        local t = S.Text(cb, 12)
        t:SetText(L["ROLE_" .. r])
        if prevRole then t:SetPoint("RIGHT", prevRole, "LEFT", -14, 0) else t:SetPoint("RIGHT", cb, "TOPRIGHT", 0, -65) end
        local c = S.Check(cb, 26)
        c:SetPoint("RIGHT", t, "LEFT", -2, 0)
        c:SetScript("OnClick", function() lfm.roles[r] = not lfm.roles[r]; page.Update() end)
        roles[r] = c
        prevRole = c
    end

    local preview = CreateFrame("Frame", nil, page)
    preview:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, -S.GAP)
    preview:SetPoint("TOPRIGHT", card, "BOTTOMRIGHT", 0, -S.GAP)
    preview:SetHeight(64)
    S.Box(preview, S.INPUT, S.EDGE)
    local text = S.Text(preview, 13)
    text:SetPoint("TOPLEFT", 12, -12)
    text:SetPoint("BOTTOMRIGHT", -12, 12)
    text:SetJustifyV("TOP")

    local post = S.Primary(S.Button(page, 200, 34))
    post:SetPoint("TOPRIGHT", preview, "BOTTOMRIGHT", 0, -S.GAP)
    post:SetText(L.POST_LFG)
    post:SetScript("OnClick", function() ns.PostLFM((lfmText())) end)
    local say = S.Button(page, 160, 34)
    say:SetPoint("RIGHT", post, "LEFT", -8, 0)
    say:SetText(L.POST_HERE)
    say:SetScript("OnClick", function() ns.Say((lfmText())) end)
    local note = S.Note(page, 11)
    note:SetPoint("TOPLEFT", preview, "BOTTOMLEFT", 0, -S.GAP - 2)
    note:SetPoint("RIGHT", say, "LEFT", -12, 0)
    note:SetMaxLines(3)
    note:SetText(L.LFM_NOTE)
    local counts = countTabs

    page.Update = function()
        local msg, quests = lfmText()
        local q = quests[lfm.index]
        title:SetText(q and ("[" .. q.level .. "] " .. q.title) or L.NO_QUEST)
        text:SetText(msg)
        if counts.selected ~= lfm.count then counts:Select(lfm.count, true) end
        for r, c in pairs(roles) do c:SetChecked(lfm.roles[r] and true or false) end
    end
    prev:SetScript("OnClick", function()
        local _, quests = lfmText()
        lfm.index = lfm.index > 1 and lfm.index - 1 or math.max(#quests, 1)
        page.Update()
    end)
    nextB:SetScript("OnClick", function()
        local _, quests = lfmText()
        lfm.index = lfm.index < #quests and lfm.index + 1 or 1
        page.Update()
    end)
end

---- Missed whispers --------------------------------------------------------------

local function makeMissed(r)
    r.busy = S.Button(r, 80, 28)
    r.busy:SetPoint("RIGHT", 0, 0)
    r.busy:SetText(L.BUSY)
    r.busy:SetScript("OnClick", function(self) ns.Busy(self:GetParent().entry) end)
    r.reply = S.Button(r, 80, 28)
    r.reply:SetPoint("RIGHT", r.busy, "LEFT", -6, 0)
    r.reply:SetText(L.REPLY)
    r.reply:SetScript("OnClick", function(self) ns.Reply(self:GetParent().entry) end)
    r.who = S.Text(r, 12, S.Accent())
    r.who:SetPoint("TOPLEFT", 10, -7)
    r.who:SetPoint("RIGHT", r.reply, "LEFT", -6, 0)
    r.text = S.Text(r, 12)
    r.text:SetPoint("TOPLEFT", r.who, "BOTTOMLEFT", 0, -4)
    r.text:SetPoint("RIGHT", r.reply, "LEFT", -6, 0)
    r.text:SetWordWrap(false)
end

local function fillMissed(r, e)
    r.entry = e
    local m = math.floor((time() - e.t) / 60)
    r.who:SetText(e.short .. "  " .. S.Hex(S.FAINT) .. L.AGO_M:format(m) .. "|r")
    r.text:SetText(e.text)
end

local function buildMissed(page)
    local always, ah = S.SettingsCard(page, nil, {
        { L.ALWAYS, nil, function() return ns.db.always end, function(v) ns.db.always = v end,
          icon = "Interface\\Icons\\INV_Letter_02" } })
    always:SetPoint("BOTTOMLEFT")
    always:SetPoint("BOTTOMRIGHT")
    always:SetHeight(ah)
    page.always = always.rows[1]
    local card = S.Card(page, L.TAB_MISSED)
    card:SetPoint("TOPLEFT")
    card:SetPoint("BOTTOMRIGHT", always, "TOPRIGHT", 0, S.GAP)
    local clear = S.Ghost(S.Button(card, 90, 26))
    clear:SetPoint("TOPRIGHT", -6, -6)
    clear:SetText(L.CLEAR)
    clear:SetScript("OnClick", function() wipe(ns.missed); ns.Refresh() end)
    page.list = S.List(card.body, 48, makeMissed, fillMissed)
    page.list:SetPoint("TOPLEFT")
    page.list:SetPoint("BOTTOMRIGHT", -10, 0)
    page.empty = S.Empty(card.body)
    page.empty:Set(L.NO_MISSED)
    page.Update = function()
        page.list:SetData(ns.missed)
        page.empty:SetShown(#ns.missed == 0)
        page.always:SetChecked(ns.db.always and true or false)
    end
end

---- Window ------------------------------------------------------------------------

function ns.Refresh()
    if not frame or not frame:IsShown() then return end
    tabs.buttons[3]:SetText(L.TAB_MISSED .. (#ns.missed > 0 and (" " .. #ns.missed) or ""))
    for i, p in ipairs(pages) do p:SetShown(i == current) end
    pages[current].Update()
end

local function build()
    frame = S.Window("GulliQuickChatFrame", L.TITLE, S.WIDE_W, 480)
    local body = frame.body
    tabs = S.Tabs(body, { L.TAB_PHRASES, L.TAB_GROUP, L.TAB_MISSED }, 150, function(i) current = i; ns.Refresh() end)
    for i, b in ipairs({ buildPhrases, buildGroup, buildMissed }) do
        local page = CreateFrame("Frame", nil, body)
        page:SetPoint("TOPLEFT", 0, -30 - S.GAP)
        page:SetPoint("BOTTOMRIGHT", 0, 0)
        b(page)
        pages[i] = page
    end
    frame:SetScript("OnShow", function() tabs:Select(current) end)
end

function ns.Toggle()
    if S.ToggleWindow(ns.Window()) then
        ns.Refresh()
    end
end

-- The window, for the hub (/gulli) to show inside it.
function ns.Window()
    if not frame then
        build()
        -- In the hub the window is shown by the hub, not by ns.Toggle.
        frame:HookScript("OnShow", function(self)
            if not self.docked then return end
            ns.Refresh()
        end)
    end
    return frame
end
