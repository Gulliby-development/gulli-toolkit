-- Two pages. Rules: cards of switches (invites, who counts as a friend, what to turn away,
-- help from others). Recent: whether you can invite now, what was turned away today, and the
-- last things the addon did, with Allow and Block for each player.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, tabs, rules, recent, stateLine, todayLine, list, empty, wordsHint
local page = 1
local I = "Interface\\Icons\\"

local function switch(key, label, desc)
    return { label, desc, function() return ns.db[key] end, function(v) ns.db[key] = v; ns.Refresh() end,
             icon = ns.OPT_ICON[key] }
end

local function textEdit(parent, width, key, onSet)
    local e = S.Edit(parent, width, 28)
    e:SetJustifyH("LEFT")
    e:SetMaxLetters(300)
    e:SetScript("OnShow", function(self) self:SetText(ns.db[key] or "") end)
    local function apply(self) ns.db[key] = self:GetText() or ""; self:ClearFocus(); if onSet then onSet() end end
    e:SetScript("OnEnterPressed", apply)
    e:SetScript("OnEditFocusLost", function(self) S.SetBorder(self, S.EDGE); apply(self) end)
    e:SetText(ns.db[key] or "")
    return e
end

---- Recent ------------------------------------------------------------------------------------

local function makeRow(r)
    r.what = S.Text(r, 12)
    r.what:SetPoint("TOPLEFT", 2, -6)
    r.what:SetPoint("RIGHT", -150, 0)
    r.what:SetWordWrap(false)
    r.when = S.Text(r, 11, S.FAINT)
    r.when:SetPoint("BOTTOMLEFT", 2, 6)
    r.block = S.Ghost(S.Button(r, 70, 28))
    r.block:SetPoint("RIGHT", 0, 0)
    r.block:SetText(L.BLOCK)
    r.block:SetScript("OnClick", function(self) ns.AddTo("deny", self:GetParent().entry.who) end)
    r.allow = S.Ghost(S.Button(r, 70, 28))
    r.allow:SetPoint("RIGHT", r.block, "LEFT", -4, 0)
    r.allow:SetText(L.ALLOW)
    r.allow:SetScript("OnClick", function(self) ns.AddTo("allow", self:GetParent().entry.who) end)
end

local function fillRow(r, e)
    r.entry = e
    local who = e.who or "?"
    local color = (e.what == "invited" or e.what == "joined" or e.what == "summon" or e.what == "res") and S.GOOD or S.WARN
    r.what:SetText(S.Hex(color) .. L["LOG_" .. e.what:upper()] .. "|r  " .. who)
    local m = math.floor((time() - e.t) / 60)
    r.when:SetText(m < 1 and L.NOW or L.AGO_M:format(m))
    local named = e.who ~= nil
    r.allow:SetShown(named and not ns.Listed("allow", e.who))
    r.block:SetShown(named and not ns.Listed("deny", e.who))
end

local STATE_TEXT = { ok = "STATE_OK", full = "STATE_FULL", lead = "STATE_LEAD", raid = "STATE_RAID" }

function ns.Refresh()
    if not frame or not frame:IsShown() then return end
    rules:SetShown(page == 1)
    recent:SetShown(page == 2)
    wordsHint:SetText(ns.db.match == "START" and L.HINT_START or L.HINT_WHOLE)
    local state = ns.InviteState()
    stateLine:SetText((state == "ok" and S.Hex(S.GOOD) or (state == "raid" and S.Hex(S.WARN) or S.Hex(S.BAD))) ..
        L[STATE_TEXT[state]] .. "|r")
    local n, s = ns.Today()
    if n == 0 then
        todayLine:SetText(L.TODAY_NONE)
    else
        local parts = {}
        for _, k in ipairs({ "invite", "duel", "guild", "trade", "petition", "spam" }) do
            if (s[k] or 0) > 0 then parts[#parts + 1] = L["N_" .. k:upper()]:format(s[k]) end
        end
        todayLine:SetText(L.TODAY:format(table.concat(parts, ", ")))
    end
    list:SetData(ns.db.log)
    empty:SetShown(#ns.db.log == 0)
end

---- Rules ---------------------------------------------------------------------------------------

local function buildRules(body, width)
    rules = CreateFrame("Frame", nil, body)
    rules:SetPoint("TOPLEFT", 0, -30 - S.GAP)
    rules:SetPoint("BOTTOMRIGHT")
    local scroll = S.Scroll(rules)
    scroll:SetPoint("TOPLEFT")
    scroll:SetPoint("BOTTOMRIGHT", -12, 0)
    local c = scroll.child
    c:SetWidth(width - 12)
    local st = S.Stack(c)

    local matchHolder = CreateFrame("Frame", nil, c)
    matchHolder:SetSize(2 * 110 + 4, 30)
    local match = S.Tabs(matchHolder, { L.MATCH_WHOLE, L.MATCH_START }, 110, function(i)
        ns.db.match = i == 2 and "START" or "WHOLE"; ns.Refresh()
    end)
    matchHolder:SetScript("OnShow", function() match:Select(ns.db.match == "START" and 2 or 1, true) end)
    local invites, h1 = S.SettingsCard(c, L.SEC_INVITE, {
        switch("invite", L.OPT_INVITE),
        { L.WORDS, nil, control = textEdit(c, 170, "words"), icon = I .. "INV_Misc_Note_05" },
        { L.MATCH, nil, control = matchHolder, icon = I .. "INV_Misc_Spyglass_03" },
        switch("inviteKnown", L.OPT_INVITE_KNOWN),
        switch("reply", L.OPT_REPLY, L.OPT_REPLY_D),
        switch("toRaid", L.OPT_RAID),
    })
    st:Add(invites, h1, 4)
    wordsHint = S.Note(c, 11)
    st:Add(wordsHint, 16)

    local friends, h2 = S.SettingsCard(c, L.SEC_FRIENDS, {
        switch("acceptKnown", L.OPT_ACCEPT_KNOWN),
        switch("bnet", L.OPT_BNET),
        { L.ALLOW_LIST, L.ALLOW_D, control = textEdit(c, 170, "allow", function() ns.Refresh() end),
          icon = I .. "Spell_Holy_SealOfSalvation" },
        { L.DENY_LIST, L.DENY_D, control = textEdit(c, 170, "deny", function() ns.Refresh() end),
          icon = I .. "Ability_Warrior_ShieldWall" },
    })
    st:Add(friends, h2)

    local away, h3 = S.SettingsCard(c, L.SEC_AWAY, {
        switch("blockStrangers", L.OPT_BLOCK),
        switch("noDuels", L.OPT_DUELS),
        switch("duelKnown", L.OPT_DUEL_KNOWN),
        switch("noGuildInvites", L.OPT_GUILD),
        switch("noTrade", L.OPT_TRADE),
        switch("noPetition", L.OPT_PETITION),
        switch("spam", L.OPT_SPAM, L.TIP_SPAM),
    })
    st:Add(away, h3)

    local help, h4 = S.SettingsCard(c, L.SEC_HELP, {
        switch("summon", L.OPT_SUMMON),
        switch("res", L.OPT_RES),
    }, L.HELP_HINT)
    st:Add(help, h4)
    c:SetHeight(st:Height())
    rules:SetScript("OnShow", function() scroll:Update(st:Height()) end)
end

local function buildRecent(body)
    recent = CreateFrame("Frame", nil, body)
    recent:SetPoint("TOPLEFT", 0, -30 - S.GAP)
    recent:SetPoint("BOTTOMRIGHT")
    local st = S.Stack(recent)
    stateLine = S.Text(recent, 12)
    stateLine:SetWordWrap(false)
    st:Add(stateLine, 16, 6)
    todayLine = S.Text(recent, 12, S.MUTED)
    todayLine:SetWordWrap(false)
    st:Add(todayLine, 16)
    local card = S.Card(recent, L.SEC_RECENT)
    card:SetPoint("TOPLEFT", 0, -st.y)
    card:SetPoint("BOTTOMRIGHT")
    list = S.List(card.body, 44, makeRow, fillRow)
    list:SetPoint("TOPLEFT")
    list:SetPoint("BOTTOMRIGHT", -10, 0)
    empty = S.Empty(card.body)
    empty:Set(L.LOG_EMPTY)
end

local function build()
    frame = S.Window("GulliSocialFrame", L.TITLE, S.NARROW_W, S.DOCK_H)
    local body, width = frame.body, frame.inner[1]
    tabs = S.Tabs(body, { L.TAB_RULES, L.TAB_RECENT }, 120, function(i) page = i; ns.Refresh() end, nil, { S.TAB.rules, S.TAB.recent })
    buildRules(body, width)
    buildRecent(body)
    frame:SetScript("OnShow", function() tabs:Select(page) end)
end

-- Picks a page (1 Rules, 2 Recent), for the previews and the tests.
function ns.ShowPage(i)
    ns.Window():Show()
    tabs:Select(i)
end

function ns.Toggle()
    S.ToggleWindow(ns.Window())
end

-- The window, for the hub (/gulli) to show inside it.
function ns.Window()
    if not frame then build() end
    return frame
end
