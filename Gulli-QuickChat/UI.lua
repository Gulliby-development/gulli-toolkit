-- Five pages: Phrases (big buttons by category, where they go, favourites), Find group (an LFM
-- from a quest or an LFM/LFG for a Forever dungeon), Whispers (missed ones with Reply, Busy and a
-- ready answer; the history by player), More (emotes, raid marks, what was sent) and Setup.
-- Outside the window: the wheel of favourites on a key, and a small panel of favourites.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, tabs, pages = nil, nil, {}
local current = 1
local phraseButtons = {}
local editing = false
local catFilter = "ALL"
local lfm = { mode = 1, index = 1, dungeon = 1, count = 1, roles = {}, role = "DPS" }
local whisperView, whoFilter = 1, nil
local wheel, wheelButton, panel, picker
local I = "Interface\\Icons\\"
local CAT_TABS = { "ALL", "GROUP", "TRADE", "SOCIAL", "OWN" }

local function chanLabel(ch) return ch and L["CH_" .. ch] or L.CH_DEFAULT end

---- Phrases --------------------------------------------------------------------

local COLS, BTN_H = 3, 44

local function layoutPhrases()
    local page = pages[1]
    local list = ns.PhrasesIn(catFilter)
    local all = ns.Phrases()
    local width = (page:GetWidth() > 1 and page:GetWidth() or 800) - 12
    local w = math.floor((width - (COLS - 1) * 8) / COLS)
    for i, text in ipairs(list) do
        local b = phraseButtons[i]
        if not b then
            b = S.Button(page.grid, w, BTN_H)
            b.text:SetWordWrap(true)
            b.text:SetPoint("LEFT", 6, 0)
            b:SetScript("OnClick", function(self)
                if editing then
                    for j, p in ipairs(ns.Phrases()) do
                        if p == self.phrase then ns.RemovePhrase(j); break end
                    end
                    layoutPhrases()
                else
                    ns.Say(self.phrase)
                end
            end)
            b.chan = S.Ghost(S.Button(b, 74, 28))
            b.chan:SetPoint("RIGHT", -4, 0)
            b.chan:SetScript("OnClick", function(self) ns.CycleChannel(self:GetParent().phrase); layoutPhrases() end)
            b.fav = S.Ghost(S.Button(b, 44, 28))
            b.fav:SetPoint("RIGHT", b.chan, "LEFT", -2, 0)
            b.fav:SetText(L.FAV)
            b.fav:SetScript("OnClick", function(self)
                ns.ToggleFav(self:GetParent().phrase); layoutPhrases()
                if ns.Panel then ns.Panel() end
            end)
            phraseButtons[i] = b
        end
        b:SetSize(w, BTN_H)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", ((i - 1) % COLS) * (w + 8), -math.floor((i - 1) / COLS) * (BTN_H + 8))
        b.phrase = text
        local own = ns.db.chan[text]
        local fav = ns.db.fav[text] and (S.Hex(S.Accent()) .. "• |r") or ""
        local tag = own and (S.Hex(S.MUTED) .. "[" .. chanLabel(own) .. "] |r") or ""
        b.chan:SetShown(editing)
        b.fav:SetShown(editing)
        b.text:ClearAllPoints()
        b.text:SetPoint("LEFT", 6, 0)
        if editing then
            b.text:SetPoint("RIGHT", b.fav, "LEFT", -4, 0)
            b.text:SetText(S.Hex(S.BAD) .. "x|r  " .. text)
            b.chan:SetText(chanLabel(own))
            b.fav.text:SetTextColor(unpack(ns.db.fav[text] and S.Accent() or S.MUTED))
        else
            b.text:SetPoint("RIGHT", -6, 0)
            b.text:SetText(fav .. tag .. text)
        end
        b:Show()
    end
    for i = #list + 1, #phraseButtons do phraseButtons[i]:Hide() end
    local h = math.ceil(#list / COLS) * (BTN_H + 8)
    page.grid:SetHeight(math.max(h, 1))
    page.scroll:Update(h)
    page.add:SetShown(editing)
    page.addBtn:SetShown(editing)
    page.reset:SetShown(editing)
    page.hint:SetShown(not editing)
    page.type:SetShown(not editing)
    page.edit:SetText(editing and L.DONE or L.EDIT)
    page.empty:SetShown(#list == 0)
    for i, ch in ipairs(ns.CHANNELS) do
        if ch == ns.db.channel and page.channels.selected ~= i then page.channels:Select(i, true) end
    end
    page.count:SetText(#all > 0 and "" or "")
end

local function buildPhrases(page)
    local catLabels = {}
    for i, c in ipairs(CAT_TABS) do catLabels[i] = L["CAT_" .. c] end
    page.cats = S.Tabs(page, catLabels, 96, function(i) catFilter = CAT_TABS[i]; layoutPhrases() end)
    page.edit = S.Ghost(S.Button(page, 90, 30))
    page.edit:SetPoint("TOPRIGHT", 0, 0)
    page.edit:SetScript("OnClick", function() editing = not editing; layoutPhrases() end)
    local labels = {}
    for i, ch in ipairs(ns.CHANNELS) do labels[i] = L["CH_" .. ch] end
    page.channels = S.Tabs(page, labels, 96, function(i) ns.db.channel = ns.CHANNELS[i]; layoutPhrases() end)
    page.channels.frame:ClearAllPoints()
    page.channels.frame:SetPoint("TOPLEFT", 0, -30 - 8)
    page.count = S.Text(page, 11, S.FAINT)
    page.count:SetPoint("TOPRIGHT", 0, -46)

    local scroll = S.Scroll(page)
    scroll:SetPoint("TOPLEFT", 0, -68 - S.GAP)
    scroll:SetPoint("BOTTOMRIGHT", -12, 44)
    page.scroll = scroll
    page.grid = scroll.child
    page.grid:SetWidth(780)
    page.empty = S.Empty(scroll)
    page.empty:Set(L.NO_PHRASES)

    page.add = S.Edit(page, 400, 30)
    page.add:SetPoint("BOTTOMLEFT", 0, 0)
    page.add:SetJustifyH("LEFT")
    page.add:SetMaxLetters(200)
    page.addBtn = S.Primary(S.Button(page, 90, 30))
    page.addBtn:SetPoint("LEFT", page.add, "RIGHT", 8, 0)
    page.addBtn:SetText(L.ADD)
    local function add()
        if ns.AddPhrase(page.add:GetText(), catFilter) then page.add:SetText("") end
        page.add:ClearFocus()
        layoutPhrases()
    end
    page.addBtn:SetScript("OnClick", add)
    page.add:SetScript("OnEnterPressed", add)
    page.reset = S.Ghost(S.Button(page, 120, 30))
    page.reset:SetPoint("BOTTOMRIGHT", 0, 0)
    page.reset:SetText(L.RESET)
    page.reset:SetScript("OnClick", function() ns.ResetPhrases(); layoutPhrases() end)
    page.type = S.Button(page, 120, 30)
    page.type:SetPoint("BOTTOMRIGHT", 0, 0)
    page.type:SetText(L.TYPE)
    page.type:SetScript("OnClick", function() ns.Type() end)
    local hint = S.Note(page, 11)
    hint:SetPoint("BOTTOMLEFT", 0, 0)
    hint:SetPoint("RIGHT", page.type, "LEFT", -12, 0)
    hint:SetHeight(36)
    hint:SetMaxLines(3)
    hint:SetText(L.TOKENS)
    page.hint = hint
    page.Update = layoutPhrases
end

---- Find group -----------------------------------------------------------------

local MODES = { "QUEST", "LFM", "LFG" }

local function dungeonList() return ns.DungeonsFor(UnitLevel("player") or 1) end

local function groupText()
    local mode = MODES[lfm.mode]
    if mode == "QUEST" then
        local quests = ns.Quests()
        if lfm.index > #quests then lfm.index = 1 end
        local q = quests[lfm.index]
        ns.pickedQuest = q and q.title or nil
        return ns.LFM(q, lfm.count, lfm.roles), q and ("[" .. q.level .. "] " .. q.title) or L.NO_QUEST
    end
    local keys = dungeonList()
    if lfm.dungeon > #keys then lfm.dungeon = 1 end
    local key = keys[lfm.dungeon]
    local title
    for _, d in ipairs(ns.DUNGEONS) do
        if d[1] == key then title = ns.DungeonName(key) .. "  " .. S.Hex(S.MUTED) .. d[4] .. "-" .. d[5] .. "|r" end
    end
    if mode == "LFG" then return ns.LFG(key, lfm.role), title end
    return ns.LFM(key, lfm.count, lfm.roles), title
end

local function buildGroup(page)
    local modeLabels = { L.MODE_QUEST, L.MODE_LFM, L.MODE_LFG }
    local modes = S.Tabs(page, modeLabels, 160, function(i) lfm.mode = i; page.Update() end)
    page.modes = modes
    local card = S.Card(page, L.QUEST)
    card:SetPoint("TOPLEFT", 0, -30 - S.GAP)
    card:SetPoint("TOPRIGHT", 0, -30 - S.GAP)
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
        c:SetScript("OnClick", function()
            if MODES[lfm.mode] == "LFG" then lfm.role = r else lfm.roles[r] = not lfm.roles[r] end
            page.Update()
        end)
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
    post:SetScript("OnClick", function() ns.PostLFM((groupText())); page.Update() end)
    local say = S.Button(page, 160, 34)
    say:SetPoint("RIGHT", post, "LEFT", -8, 0)
    say:SetText(L.POST_HERE)
    say:SetScript("OnClick", function() ns.Say((groupText())) end)
    local note = S.Note(page, 11)
    note:SetPoint("TOPLEFT", preview, "BOTTOMLEFT", 0, -S.GAP - 2)
    note:SetPoint("RIGHT", say, "LEFT", -12, 0)
    note:SetMaxLines(3)
    note:SetText(L.LFM_NOTE)
    local posted = S.Text(page, 12, S.MUTED)
    posted:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -S.GAP)
    posted:SetPoint("RIGHT", 0, 0)
    posted:SetWordWrap(false)

    page.Update = function()
        local msg, label = groupText()
        local mode = MODES[lfm.mode]
        if modes.selected ~= lfm.mode then modes:Select(lfm.mode, true) end
        card:SetTitle(mode == "QUEST" and L.QUEST or L.DUNGEON)
        title:SetText(label or "")
        text:SetText(msg)
        cLabel:SetText(mode == "LFG" and L.MY_ROLE or L.HOW_MANY)
        countTabs.frame:SetShown(mode ~= "LFG")
        if countTabs.selected ~= lfm.count then countTabs:Select(lfm.count, true) end
        for r, c in pairs(roles) do
            if mode == "LFG" then c:SetChecked(lfm.role == r) else c:SetChecked(lfm.roles[r] and true or false) end
        end
        if ns.lastLFM then
            local m = math.floor((time() - ns.lastLFM.t) / 60)
            posted:SetText(time() - ns.lastLFM.t >= ns.REMIND_AFTER and (S.Hex(S.GOOD) .. L.REPOST .. "|r")
                or L.POSTED_AGO:format(m))
        else
            posted:SetText("")
        end
    end
    local function step(d)
        if MODES[lfm.mode] == "QUEST" then
            local n = math.max(#ns.Quests(), 1)
            lfm.index = (lfm.index - 1 + d) % n + 1
        else
            local n = #dungeonList()
            lfm.dungeon = (lfm.dungeon - 1 + d) % n + 1
        end
        page.Update()
    end
    prev:SetScript("OnClick", function() step(-1) end)
    nextB:SetScript("OnClick", function() step(1) end)
end

-- Bulletin's "My LFM": the Find group page on that dungeon.
function ns.OpenLFM(key)
    local f = ns.Window()
    if not f:IsShown() then S.ToggleWindow(f) end
    lfm.mode = 2
    for i, k in ipairs(dungeonList()) do if k == key then lfm.dungeon = i end end
    tabs:Select(2)
end

---- Whispers -------------------------------------------------------------------

local function showPicker(anchor, entry)
    if not picker then
        picker = CreateFrame("Frame", "GulliQuickChatPicker", UIParent)
        picker:SetFrameStrata("TOOLTIP")
        picker:SetClampedToScreen(true)
        S.Box(picker, S.SURFACE, S.EDGE)
        picker.buttons = {}
        picker:EnableMouse(true)
        tinsert(UISpecialFrames, "GulliQuickChatPicker")
    end
    local list = ns.Phrases()
    local n = math.min(#list, 10) + 1
    picker:SetSize(260, n * 32 + 8)
    for i = 1, n do
        local b = picker.buttons[i]
        if not b then
            b = S.Button(picker, 248, 28)
            b:SetPoint("TOPLEFT", 6, -4 - (i - 1) * 32)
            picker.buttons[i] = b
        end
        local text = list[i]
        if i == n then
            b:SetText(S.Hex(S.MUTED) .. L.TYPE .. "|r")
            b:SetScript("OnClick", function() picker:Hide(); ns.Reply(entry) end)
        else
            b:SetText(text)
            b:SetScript("OnClick", function() picker:Hide(); ns.ReplyWith(entry, text) end)
        end
        b:Show()
    end
    for i = n + 1, #picker.buttons do picker.buttons[i]:Hide() end
    picker:ClearAllPoints()
    picker:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
    picker:Show()
end
ns.ShowPicker = showPicker

local function makeMissed(r)
    r.busy = S.Button(r, 80, 28)
    r.busy:SetPoint("RIGHT", 0, 0)
    r.busy:SetText(L.BUSY)
    r.busy:SetScript("OnClick", function(self) ns.Busy(self:GetParent().entry) end)
    r.reply = S.Button(r, 80, 28)
    r.reply:SetPoint("RIGHT", r.busy, "LEFT", -6, 0)
    r.reply:SetText(L.REPLY)
    r.reply:SetScript("OnClick", function(self) showPicker(self, self:GetParent().entry) end)
    r.whoBtn = CreateFrame("Button", nil, r)
    r.whoBtn:SetPoint("TOPLEFT", 10, -4)
    r.whoBtn:SetSize(220, 18)
    r.whoBtn:SetScript("OnClick", function(self)
        local e = self:GetParent().entry
        whoFilter = (whoFilter ~= e.from) and e.from or nil
        ns.Refresh()
    end)
    r.who = S.Text(r, 12, S.Accent())
    r.who:SetPoint("TOPLEFT", 10, -7)
    r.who:SetPoint("RIGHT", r.reply, "LEFT", -6, 0)
    r.text = S.Text(r, 12)
    r.text:SetPoint("TOPLEFT", r.who, "BOTTOMLEFT", 0, -4)
    r.text:SetPoint("RIGHT", r.reply, "LEFT", -6, 0)
    r.text:SetWordWrap(false)
end

local function fillMissed(r, e)
    -- History rows are { who, out }; missed rows are { from }.
    if e.who then e.from = e.who end
    r.entry = e
    local m = math.floor((time() - e.t) / 60)
    local arrow = e.out == true and (S.Hex(S.FAINT) .. L.TO .. " |r") or (e.out == false and (S.Hex(S.FAINT) .. L.FROM .. " |r") or "")
    r.who:SetText(arrow .. e.short .. "  " .. S.Hex(S.FAINT) .. L.AGO_M:format(m) .. "|r")
    r.text:SetText(e.text)
    r.busy:SetShown(e.out == nil)
end

local function buildWhispers(page)
    page.view = S.Tabs(page, { L.VIEW_MISSED, L.VIEW_HISTORY }, 140, function(i)
        whisperView = i; whoFilter = nil; ns.Refresh()
    end)
    local card = S.Card(page, L.TAB_MISSED)
    card:SetPoint("TOPLEFT", 0, -30 - S.GAP)
    card:SetPoint("BOTTOMRIGHT")
    local clear = S.Ghost(S.Button(card, 90, 26))
    clear:SetPoint("TOPRIGHT", -6, -6)
    clear:SetText(L.CLEAR)
    clear:SetScript("OnClick", function()
        if whisperView == 1 then wipe(ns.missed) else wipe(ns.db.log) end
        ns.Refresh()
    end)
    page.list = S.List(card.body, 48, makeMissed, fillMissed)
    page.list:SetPoint("TOPLEFT")
    page.list:SetPoint("BOTTOMRIGHT", -10, 0)
    page.empty = S.Empty(card.body)
    page.Update = function()
        local items
        if whisperView == 1 then
            items = ns.missed
            card:SetTitle(L.TAB_MISSED)
            page.empty:Set(L.NO_MISSED)
        else
            items = ns.Log(whoFilter)
            card:SetTitle(whoFilter and L.HISTORY_OF:format(whoFilter:match("^[^-]+") or whoFilter) or L.VIEW_HISTORY)
            page.empty:Set(ns.db.keepLog and L.NO_HISTORY or L.HISTORY_OFF)
        end
        page.list:SetData(items)
        page.empty:SetShown(#items == 0)
    end
end

---- More: emotes, marks, what was sent -------------------------------------------

local MARK_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"

local function makeSent(r)
    r.again = S.Button(r, 90, 28)
    r.again:SetPoint("RIGHT", 0, 0)
    r.again:SetText(L.AGAIN)
    r.again:SetScript("OnClick", function(self) ns.Repeat(self:GetParent().entry) end)
    r.text = S.Text(r, 12)
    r.text:SetPoint("LEFT", 6, 0)
    r.text:SetPoint("RIGHT", r.again, "LEFT", -8, 0)
    r.text:SetWordWrap(false)
end

local function fillSent(r, e)
    r.entry = e
    local where = e.kind == "WHISPER" and (L.TO .. " " .. (e.to or "?")) or (e.kind == "CHANNEL" and L.CH_LFG or L["CH_" .. e.kind] or e.kind)
    r.text:SetText(S.Hex(S.MUTED) .. "[" .. where .. "]|r " .. e.text)
end

local function buildMore(page, width)
    local emotes = S.Card(page, L.SEC_EMOTES)
    emotes:SetPoint("TOPLEFT")
    emotes:SetPoint("TOPRIGHT")
    emotes:Fit(30 + 8 + 30)
    local w = math.floor((width - 2 * S.INSET - 3 * 8) / 4)
    for i, token in ipairs(ns.EMOTES) do
        local b = S.Button(emotes.body, w, 30)
        b:SetPoint("TOPLEFT", ((i - 1) % 4) * (w + 8), -math.floor((i - 1) / 4) * 38)
        b:SetText(L["EMOTE_" .. token])
        b:SetScript("OnClick", function() ns.Emote(token) end)
    end

    local marks = S.Card(page, L.SEC_MARKS)
    marks:SetPoint("TOPLEFT", emotes, "BOTTOMLEFT", 0, -S.GAP)
    marks:SetPoint("TOPRIGHT", emotes, "BOTTOMRIGHT", 0, -S.GAP)
    marks:Fit(36)
    for i = 1, 8 do
        local b = S.Button(marks.body, 40, 36)
        b:SetPoint("TOPLEFT", (i - 1) * 46, 0)
        local t = b:CreateTexture(nil, "ARTWORK")
        t:SetSize(24, 24)
        t:SetPoint("CENTER")
        t:SetTexture(MARK_ICON .. i)
        b:SetScript("OnClick", function() ns.Mark(i) end)
    end
    local none = S.Ghost(S.Button(marks.body, 90, 36))
    none:SetPoint("TOPLEFT", 8 * 46 + 4, 0)
    none:SetText(L.MARK_CLEAR)
    none:SetScript("OnClick", function() ns.Mark(0) end)

    local sent = S.Card(page, L.SEC_SENT)
    sent:SetPoint("TOPLEFT", marks, "BOTTOMLEFT", 0, -S.GAP)
    sent:SetPoint("BOTTOMRIGHT")
    page.list = S.List(sent.body, 36, makeSent, fillSent)
    page.list:SetPoint("TOPLEFT")
    page.list:SetPoint("BOTTOMRIGHT", -10, 0)
    page.empty = S.Empty(sent.body)
    page.empty:Set(L.NO_SENT)
    page.Update = function()
        page.list:SetData(ns.db.history)
        page.empty:SetShown(#ns.db.history == 0)
    end
end

---- Setup ----------------------------------------------------------------------

local capture

local function keyText()
    return ns.db.wheelKey and (S.Hex(S.Accent()) .. ns.db.wheelKey .. "|r") or L.NO_KEY
end

local MODIFIERS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true }

-- The key (or gamepad button) that opens the wheel, with Shift, Ctrl or Alt.
function ns.SetKey(key)
    if key == "ESCAPE" then key = nil end
    if key and not key:find("^PAD") then
        if IsAltKeyDown and IsAltKeyDown() then key = "ALT-" .. key end
        if IsControlKeyDown and IsControlKeyDown() then key = "CTRL-" .. key end
        if IsShiftKeyDown and IsShiftKeyDown() then key = "SHIFT-" .. key end
    end
    ns.db.wheelKey = key
    ns.ApplyKey()
end

local function buildSetup(page, width)
    local scroll = S.Scroll(page)
    scroll:SetPoint("TOPLEFT")
    scroll:SetPoint("BOTTOMRIGHT", -12, 0)
    local c = scroll.child
    c:SetWidth(width - 12)
    local st = S.Stack(c)

    local keyBtn = S.Button(c, 150, 28)
    keyBtn:SetScript("OnShow", function(self) self:SetText(keyText()) end)
    keyBtn:SetText(keyText())
    keyBtn:SetScript("OnClick", function(self)
        if InCombatLockdown and InCombatLockdown() then return end
        capture = self
        self:SetText(L.PRESS_KEY)
        self:EnableKeyboard(true)
        if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
        if self.EnableGamePadButton then self:EnableGamePadButton(true) end
    end)
    local function done(self, key)
        if capture ~= self or MODIFIERS[key] then return end
        capture = nil
        self:EnableKeyboard(false)
        if self.EnableGamePadButton then self:EnableGamePadButton(false) end
        ns.SetKey(key)
        self:SetText(keyText())
    end
    keyBtn:SetScript("OnKeyDown", done)
    keyBtn:SetScript("OnGamePadButtonDown", done)
    local open = S.Button(c, 110, 28)
    open:SetText(L.OPEN_WHEEL)
    open:SetScript("OnClick", function() ns.ToggleWheel() end)
    local wheelCard, h1 = S.SettingsCard(c, L.SEC_WHEEL, {
        { L.WHEEL_KEY, L.WHEEL_KEY_D, control = keyBtn, icon = I .. "INV_Misc_Key_03" },
        { L.WHEEL_TRY, nil, control = open, icon = I .. "INV_Misc_EngGizmos_20" },
        { L.OPT_PANEL, L.TIP_PANEL, function() return ns.db.panelShow end,
          function(v) ns.db.panelShow = v; ns.Panel() end, icon = ns.OPT_ICON.panelShow },
        { L.PANEL_LOCK, nil, function() return ns.db.panelLocked end,
          function(v) ns.db.panelLocked = v; ns.Panel() end, icon = I .. "INV_Misc_Key_14" },
    })
    st:Add(wheelCard, h1)

    local minutes = S.Stepper(c, function() return ns.db.busyMinutes end, function(v) ns.db.busyMinutes = v end,
        1, 1, 30, function(v) return L.MIN_N:format(v) end, 110)
    local whispers, h2 = S.SettingsCard(c, L.SEC_WHISPERS, {
        { L.ALWAYS, nil, function() return ns.db.always end, function(v) ns.db.always = v end,
          icon = I .. "INV_Letter_02" },
        { L.OPT_AUTOBUSY, L.TIP_AUTOBUSY, function() return ns.db.autoBusy end, function(v) ns.db.autoBusy = v end,
          icon = ns.OPT_ICON.autoBusy },
        { L.BUSY_EVERY, nil, control = minutes, icon = I .. "INV_Misc_PocketWatch_01" },
        { L.OPT_SOUND, nil, function() return ns.db.sound end, function(v) ns.db.sound = v end, icon = ns.OPT_ICON.sound },
        { L.KEEP_LOG, nil, function() return ns.db.keepLog end, function(v) ns.db.keepLog = v end,
          icon = I .. "INV_Misc_Book_09" },
    })
    st:Add(whispers, h2)

    local group, h3 = S.SettingsCard(c, L.SEC_GROUP, {
        { L.OPT_REMIND, nil, function() return ns.db.remind end, function(v) ns.db.remind = v end,
          icon = I .. "Spell_Nature_TimeStop" },
    })
    st:Add(group, h3)
    c:SetHeight(st:Height())
    page.Update = function() scroll:Update(st:Height()) end
end

---- Window ------------------------------------------------------------------------

function ns.Refresh()
    if not frame or not frame:IsShown() then return end
    tabs.buttons[3]:SetText(L.TAB_MISSED .. (#ns.missed > 0 and (" " .. #ns.missed) or ""))
    for i, p in ipairs(pages) do p:SetShown(i == current) end
    pages[current].Update()
end

local function build()
    frame = S.Window("GulliQuickChatFrame", L.TITLE, S.WIDE_W, S.DOCK_H)
    local body, width = frame.body, frame.inner[1]
    tabs = S.Tabs(body, { L.TAB_PHRASES, L.TAB_GROUP, L.TAB_MISSED, L.TAB_MORE, L.TAB_SETUP }, 150,
        function(i) current = i; ns.Refresh() end)
    for i, b in ipairs({ buildPhrases, buildGroup, buildWhispers, buildMore, buildSetup }) do
        local page = CreateFrame("Frame", nil, body)
        page:SetPoint("TOPLEFT", 0, -30 - S.GAP)
        page:SetPoint("BOTTOMRIGHT", 0, 0)
        b(page, width)
        pages[i] = page
    end
    frame:SetScript("OnShow", function() tabs:Select(current) end)
end

-- Picks a page (1 Phrases ... 5 Setup), for the previews and the tests.
function ns.ShowPage(i, opts)
    ns.Window():Show()
    if opts and opts.editing ~= nil then editing = opts.editing end
    if opts and opts.mode then lfm.mode = opts.mode end
    if opts and opts.view then whisperView = opts.view end
    tabs:Select(i)
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

---- The wheel --------------------------------------------------------------------

-- A ring of up to eight favourites around the cursor, in the spirit of radial menus: round
-- icons on a soft disc, the one in the pointed direction lit, its text in the middle. Point and
-- click (or press the wheel key again, or 1-8) to send; a click in the middle or Escape closes it.
ns.WHEEL_R = 150
local SLOT = 58
local CAT_ICONS = { GROUP = I .. "Spell_Holy_PrayerOfFortitude", TRADE = I .. "INV_Misc_Coin_02",
                    SOCIAL = I .. "Spell_Holy_Heal", OWN = I .. "INV_Misc_Note_05" }
-- Each default phrase has its own picture; the player's own phrases show their category's.
local PHRASE_ICONS = { "INV_Letter_02", "Ability_Warrior_BattleShout", "INV_Misc_PocketWatch_01", "Ability_Rogue_Sprint",
                       "INV_Misc_Gift_01", "Ability_Mount_RidingHorse", "Spell_Holy_FlashHeal", "INV_Drink_18",
                       "INV_Misc_Coin_02", "INV_Misc_Coin_01" }

local function phraseIcon(text)
    for i, name in ipairs(PHRASE_ICONS) do
        if L["P" .. i] == text then return I .. name end
    end
    return CAT_ICONS[ns.Category(text)] or CAT_ICONS.OWN
end

local hovered -- the lit slot (kept outside the frame)

local function wheelSelect(i)
    if hovered == i then return end
    hovered = i
    local a = S.Accent()
    for j, slot in ipairs(wheel.slots) do
        local on = j == i
        slot.icon:SetRing(on and a or S.EDGE)
        slot.icon.fill:SetVertexColor(unpack(on and S.RAISED or S.SURFACE))
        slot.icon:SetScale(on and 1.12 or 1)
        local c = on and S.TEXT or S.MUTED
        slot.label:SetTextColor(c[1], c[2], c[3], 1)
    end
    local slot = i and wheel.slots[i]
    wheel.dot:SetShown(slot ~= nil)
    if slot then
        wheel.dot:ClearAllPoints()
        wheel.dot:SetPoint("CENTER", math.floor(math.cos(slot.angle) * 104), math.floor(math.sin(slot.angle) * 104))
        wheel.say:SetText(ns.Fill(slot.phrase))
        wheel.where:SetText(chanLabel(ns.Target(ns.db.chan[slot.phrase])))
    else
        wheel.say:SetText(L.WHEEL_PICK)
        wheel.where:SetText("")
    end
end

-- The slot the cursor points at: by direction once it is out of the middle.
local function pointedSlot()
    local n = wheel.count or 0
    if n == 0 or not GetCursorPosition then return nil end
    local x, y = GetCursorPosition()
    local scale = wheel:GetEffectiveScale()
    local cx, cy = wheel:GetCenter()
    if not cx then return nil end
    local dx, dy = x / scale - cx, y / scale - cy
    if dx * dx + dy * dy < 48 * 48 then return nil end
    local deg = math.deg(math.atan2(dy, dx))
    return math.floor(((90 - deg) % 360) / (360 / n) + 0.5) % n + 1
end

-- Lights a slot, for the previews and the tests.
function ns.WheelHover(i) wheelSelect(i) end

function ns.WheelSend(i)
    local slot = wheel and wheel.slots[i]
    if not slot or not slot:IsShown() then return false end
    wheel:Hide()
    return ns.Say(slot.phrase)
end

local function buildWheel()
    local size = 2 * (ns.WHEEL_R + 80)
    wheel = CreateFrame("Frame", "GulliQuickChatWheel", UIParent)
    wheel:SetSize(size, size)
    wheel:SetPoint("CENTER")
    wheel:SetFrameStrata("DIALOG")
    wheel:SetClampedToScreen(true)
    wheel:EnableMouse(true)
    tinsert(UISpecialFrames, "GulliQuickChatWheel")
    wheel.disc = S.Circle(wheel, size - 20, { 0, 0, 0, 0.55 }, "BACKGROUND", 0)
    wheel.disc:SetPoint("CENTER")
    wheel.track = S.Circle(wheel, 2 * ns.WHEEL_R + 4, { 1, 1, 1, 0.06 }, "BACKGROUND", 1)
    wheel.track:SetPoint("CENTER")
    wheel.hole = S.Circle(wheel, 2 * ns.WHEEL_R - 4, { 0, 0, 0, 0.35 }, "BACKGROUND", 2)
    wheel.hole:SetPoint("CENTER")
    -- The middle: what the lit slot says and where it goes.
    wheel.mid = S.Circle(wheel, 196, S.EDGE, "BORDER", 0)
    wheel.mid:SetPoint("CENTER")
    wheel.midFill = S.Circle(wheel, 192, S.BG, "BORDER", 1)
    wheel.midFill:SetPoint("CENTER")
    wheel.say = S.Text(wheel, 14)
    wheel.say:SetWidth(150)
    wheel.say:SetPoint("CENTER", 0, 8)
    wheel.say:SetJustifyH("CENTER")
    wheel.say:SetMaxLines(3)
    wheel.where = S.Text(wheel, 11, S.FAINT)
    wheel.where:SetPoint("TOP", wheel.say, "BOTTOM", 0, -6)
    wheel.dot = S.Circle(wheel, 10, S.Accent(), "ARTWORK", 0)
    wheel.slots = {}
    for i = 1, 8 do
        local slot = CreateFrame("Frame", nil, wheel)
        slot:SetSize(SLOT, SLOT)
        slot.icon = S.RoundIcon(slot, SLOT)
        slot.icon:SetPoint("CENTER")
        slot.num = S.Text(slot.icon, 10, S.FAINT)
        slot.num:SetPoint("TOPRIGHT", slot.icon, "TOPRIGHT", 2, 2)
        slot.num:SetText(tostring(i))
        slot.label = S.Text(slot, 11, S.MUTED)
        slot.label:SetWidth(124)
        slot.label:SetJustifyH("CENTER")
        slot.label:SetMaxLines(2)
        slot.label:SetPoint("TOP", slot, "BOTTOM", 0, -4)
        wheel.slots[i] = slot
    end
    wheel:SetScript("OnUpdate", function()
        local i = pointedSlot()
        if i then wheelSelect(i) end
    end)
    wheel:SetScript("OnMouseUp", function()
        local i = pointedSlot()
        if i then ns.WheelSend(i) else wheel:Hide() end
    end)
    -- Keys 1-8 send while the wheel is open; every other key goes on to the game.
    wheel:SetScript("OnKeyDown", function(self, key)
        local n = tonumber(key)
        local ok = n and self.slots[n] and self.slots[n]:IsShown()
        if self.SetPropagateKeyboardInput and not (InCombatLockdown and InCombatLockdown()) then
            self:SetPropagateKeyboardInput(not ok)
        end
        if ok then ns.WheelSend(n) end
    end)
    wheel:Hide() -- a new frame starts shown
end

-- Opens the ring at the cursor; on an open ring the wheel key sends the lit phrase, or closes it.
function ns.ToggleWheel()
    if not wheel then buildWheel() end
    if wheel:IsShown() then
        if hovered then ns.WheelSend(hovered) else wheel:Hide() end
        return false
    end
    local list = ns.Favorites(8)
    wheel.count = #list
    for i, slot in ipairs(wheel.slots) do
        slot.phrase = list[i]
        slot:SetShown(list[i] ~= nil)
        if list[i] then
            slot.angle = math.rad(90 - (i - 1) * 360 / #list)
            slot:ClearAllPoints()
            slot:SetPoint("CENTER", wheel, "CENTER", math.floor(math.cos(slot.angle) * ns.WHEEL_R),
                math.floor(math.sin(slot.angle) * ns.WHEEL_R))
            slot.icon:SetIcon(phraseIcon(list[i]))
            slot.label:SetText(list[i])
        end
    end
    hovered = -1
    wheelSelect(nil)
    wheel:ClearAllPoints()
    local x, y = GetCursorPosition and GetCursorPosition()
    if x and y and x > 0 then
        local scale = UIParent:GetEffectiveScale()
        wheel:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    else
        wheel:SetPoint("CENTER")
    end
    wheel:EnableKeyboard(not (InCombatLockdown and InCombatLockdown()))
    wheel:Show()
    return true
end

-- The key: a hidden button the binding clicks. Bindings change only out of combat.
function ns.ApplyKey()
    if not wheelButton then
        wheelButton = CreateFrame("Button", "GulliQuickChatWheelButton", UIParent)
        wheelButton:SetScript("OnClick", function() ns.ToggleWheel() end)
    end
    if InCombatLockdown and InCombatLockdown() then return false end
    if ClearOverrideBindings then ClearOverrideBindings(wheelButton) end
    if ns.db.wheelKey and SetOverrideBindingClick then
        SetOverrideBindingClick(wheelButton, true, ns.db.wheelKey, "GulliQuickChatWheelButton")
    end
    return true
end

---- The panel of favourites -------------------------------------------------------

ns.PANEL_MAX = 6

local function buildPanel()
    panel = CreateFrame("Frame", "GulliQuickChatPanel", UIParent)
    panel:SetFrameStrata("MEDIUM")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self) if not ns.db.panelLocked or ns.movingPanel then self:StartMoving() end end)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint()
        ns.db.panelPoint = { point, rel, x, y }
    end)
    S.Box(panel, S.BG, S.EDGE)
    panel.buttons = {}
    for i = 1, ns.PANEL_MAX do
        local b = S.Button(panel, 150, 30)
        b:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 34)
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnDragStart", function() panel:GetScript("OnDragStart")(panel) end)
        b:SetScript("OnDragStop", function() panel:GetScript("OnDragStop")(panel) end)
        b:SetScript("OnClick", function(self) ns.Say(self.phrase) end)
        panel.buttons[i] = b
    end
end

function ns.Panel()
    if not ns.db then return end
    if not ns.db.panelShow and not ns.movingPanel then
        if panel then panel:Hide() end
        return
    end
    if not panel then buildPanel() end
    local list = ns.Favorites(ns.PANEL_MAX)
    for i, b in ipairs(panel.buttons) do
        b.phrase = list[i]
        b:SetShown(list[i] ~= nil)
        if list[i] then b:SetText(list[i]) end
    end
    panel:SetSize(162, math.max(#list, 1) * 34 + 8)
    panel:EnableMouse(not ns.db.panelLocked or ns.movingPanel)
    panel:ClearAllPoints()
    local p = ns.db.panelPoint
    if p then panel:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0) else panel:SetPoint("LEFT", 40, 0) end
    panel:Show()
end

-- /gulli move: the panel shows and can be dragged even when it is locked or off.
function ns.MovePanel(on)
    ns.movingPanel = on and true or nil
    ns.Panel()
end

function ns.Setup()
    ns.ApplyKey()
    ns.Panel()
end
