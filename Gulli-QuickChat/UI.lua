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
    local w = math.floor((width - (COLS - 1) * 6) / COLS)
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
        b:SetPoint("TOPLEFT", ((i - 1) % COLS) * (w + 6), -math.floor((i - 1) / COLS) * (BTN_H + 6))
        b.index, b.phrase = i, text
        b:SetText(editing and ("|cffff6060X|r  " .. text) or text)
        b:Show()
    end
    for i = #list + 1, #phraseButtons do phraseButtons[i]:Hide() end
    page.grid:SetHeight(math.ceil(#list / COLS) * (BTN_H + 6))
    page.add:SetShown(editing)
    page.addBtn:SetShown(editing)
    page.reset:SetShown(editing)
    page.edit:SetText(editing and L.DONE or L.EDIT)
    for i, b in ipairs(channelButtons) do
        S.SetBorder(b, ns.CHANNELS[i] == ns.db.channel and S.Accent() or S.BORDER)
    end
end

local function buildPhrases(page)
    local x = 0
    for i, ch in ipairs(ns.CHANNELS) do
        local b = S.Button(page, 96, 28)
        b:SetPoint("TOPLEFT", x, 0)
        b:SetText(L["CH_" .. ch])
        b:SetScript("OnClick", function() ns.db.channel = ch; layoutPhrases() end)
        b:SetScript("OnLeave", function(self) S.SetBorder(self, ns.db.channel == ch and S.Accent() or S.BORDER) end)
        channelButtons[i] = b
        x = x + 100
    end
    page.edit = S.Button(page, 90, 28)
    page.edit:SetPoint("TOPRIGHT", 0, 0)
    page.edit:SetScript("OnClick", function() editing = not editing; layoutPhrases() end)

    local scroll = S.Scroll(page)
    scroll:SetPoint("TOPLEFT", 0, -36)
    scroll:SetPoint("BOTTOMRIGHT", -12, 40)
    page.grid = scroll.child
    page.grid:SetWidth(640)

    page.add = S.Edit(page, 400)
    page.add:SetPoint("BOTTOMLEFT", 0, 4)
    page.add:SetJustifyH("LEFT")
    page.add:SetMaxLetters(200)
    page.addBtn = S.Button(page, 90, 30)
    page.addBtn:SetPoint("LEFT", page.add, "RIGHT", 6, 0)
    page.addBtn:SetText(L.ADD)
    local function add()
        if ns.AddPhrase(page.add:GetText()) then page.add:SetText("") end
        page.add:ClearFocus()
        layoutPhrases()
    end
    page.addBtn:SetScript("OnClick", add)
    page.add:SetScript("OnEnterPressed", add)
    page.reset = S.Button(page, 120, 30)
    page.reset:SetPoint("BOTTOMRIGHT", 0, 4)
    page.reset:SetText(L.RESET)
    page.reset:SetScript("OnClick", function() ns.ResetPhrases(); layoutPhrases() end)
    local hint = S.Note(page, 11)
    hint:SetPoint("BOTTOMLEFT", 0, 10)
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
    local qLabel = S.Text(page, 12, S.MUTED)
    qLabel:SetPoint("TOPLEFT", 0, 0)
    qLabel:SetText(L.QUEST)
    local prev = S.Button(page, 40, 30)
    prev:SetPoint("TOPLEFT", 0, -18)
    prev:SetText("<")
    local nextB = S.Button(page, 40, 30)
    nextB:SetPoint("TOPRIGHT", 0, -18)
    nextB:SetText(">")
    local title = S.Text(page, 13)
    title:SetPoint("LEFT", prev, "RIGHT", 8, 0)
    title:SetPoint("RIGHT", nextB, "LEFT", -8, 0)
    title:SetJustifyH("CENTER")
    title:SetWordWrap(false)

    local cLabel = S.Text(page, 12, S.MUTED)
    cLabel:SetPoint("TOPLEFT", 0, -60)
    cLabel:SetText(L.HOW_MANY)
    local counts = {}
    for n = 1, 4 do
        local b = S.Button(page, 50, 30)
        b:SetPoint("TOPLEFT", (n - 1) * 56, -78)
        b:SetText(tostring(n))
        b:SetScript("OnClick", function() lfm.count = n; page.Update() end)
        counts[n] = b
    end
    local roles = {}
    for i, r in ipairs(ns.ROLES) do
        local c = S.Check(page, 28)
        c:SetPoint("TOPLEFT", 250 + (i - 1) * 120, -78)
        c:SetScript("OnClick", function() lfm.roles[r] = not lfm.roles[r]; page.Update() end)
        local t = S.Text(page, 12)
        t:SetPoint("LEFT", c, "RIGHT", 4, 0)
        t:SetText(L["ROLE_" .. r])
        roles[r] = c
    end

    local preview = CreateFrame("Frame", nil, page)
    preview:SetPoint("TOPLEFT", 0, -124)
    preview:SetPoint("TOPRIGHT", 0, -124)
    preview:SetHeight(60)
    S.Box(preview, S.PANEL)
    local text = S.Text(preview, 13)
    text:SetPoint("TOPLEFT", 10, -10)
    text:SetPoint("BOTTOMRIGHT", -10, 10)
    text:SetJustifyV("TOP")

    local post = S.Button(page, 200, 34)
    post:SetPoint("TOPLEFT", 0, -196)
    post:SetText(L.POST_LFG)
    post:SetScript("OnClick", function() ns.PostLFM((lfmText())) end)
    local say = S.Button(page, 200, 34)
    say:SetPoint("LEFT", post, "RIGHT", 8, 0)
    say:SetText(L.POST_HERE)
    say:SetScript("OnClick", function() ns.Say((lfmText())) end)
    local note = S.Note(page, 11)
    note:SetPoint("TOPLEFT", 0, -240)
    note:SetPoint("RIGHT", 0, 0)
    note:SetText(L.LFM_NOTE)

    page.Update = function()
        local msg, quests = lfmText()
        local q = quests[lfm.index]
        title:SetText(q and ("[" .. q.level .. "] " .. q.title) or L.NO_QUEST)
        text:SetText(msg)
        for n, b in ipairs(counts) do S.SetBorder(b, n == lfm.count and S.Accent() or S.BORDER) end
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
    r.busy:SetPoint("RIGHT", -4, 0)
    r.busy:SetText(L.BUSY)
    r.busy:SetScript("OnClick", function(self) ns.Busy(self:GetParent().entry) end)
    r.reply = S.Button(r, 80, 28)
    r.reply:SetPoint("RIGHT", r.busy, "LEFT", -4, 0)
    r.reply:SetText(L.REPLY)
    r.reply:SetScript("OnClick", function(self) ns.Reply(self:GetParent().entry) end)
    r.who = S.Text(r, 12, S.Accent())
    r.who:SetPoint("TOPLEFT", 8, -5)
    r.who:SetPoint("RIGHT", r.reply, "LEFT", -6, 0)
    r.text = S.Text(r, 12)
    r.text:SetPoint("TOPLEFT", r.who, "BOTTOMLEFT", 0, -2)
    r.text:SetPoint("RIGHT", r.reply, "LEFT", -6, 0)
    r.text:SetWordWrap(false)
end

local function fillMissed(r, e)
    r.entry = e
    local m = math.floor((time() - e.t) / 60)
    r.who:SetText(e.short .. "  " .. S.Hex(S.MUTED) .. L.AGO_M:format(m) .. "|r")
    r.text:SetText(e.text)
end

local function buildMissed(page)
    page.list = S.List(page, 44, makeMissed, fillMissed)
    page.list:SetPoint("TOPLEFT", 0, 0)
    page.list:SetPoint("BOTTOMRIGHT", -12, 40)
    page.empty = S.Note(page, 12)
    page.empty:SetPoint("TOPLEFT", 4, -6)
    page.empty:SetPoint("RIGHT", -16, 0)
    page.empty:SetText(L.NO_MISSED)
    page.always = S.Check(page, 26)
    page.always:SetPoint("BOTTOMLEFT", 0, 4)
    page.always:SetScript("OnClick", function(self)
        ns.db.always = not ns.db.always
        self:SetChecked(ns.db.always)
    end)
    local t = S.Text(page, 12)
    t:SetPoint("LEFT", page.always, "RIGHT", 4, 0)
    t:SetText(L.ALWAYS)
    local clear = S.Button(page, 100, 30)
    clear:SetPoint("BOTTOMRIGHT", 0, 2)
    clear:SetText(L.CLEAR)
    clear:SetScript("OnClick", function() wipe(ns.missed); ns.Refresh() end)
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
    frame = S.Window("GulliQuickChatFrame", L.TITLE, 680, 440)
    local body = frame.body
    tabs = S.Tabs(body, { L.TAB_PHRASES, L.TAB_GROUP, L.TAB_MISSED }, 150, function(i) current = i; ns.Refresh() end)
    for i, b in ipairs({ buildPhrases, buildGroup, buildMissed }) do
        local page = CreateFrame("Frame", nil, body)
        page:SetPoint("TOPLEFT", 0, -40)
        page:SetPoint("BOTTOMRIGHT", 0, 0)
        b(page)
        pages[i] = page
    end
    frame:SetScript("OnShow", function() tabs:Select(current) end)
end

function ns.Toggle()
    if not frame then build() end
    frame:SetShown(not frame:IsShown())
    ns.Refresh()
end
