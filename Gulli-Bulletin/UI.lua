-- The board window: a tab per kind, groups split by dungeon (a header click folds one), a
-- search box, and Hide, Whisper, Ask or Invite on each row. The Setup tab picks the dungeons
-- to show and to alert on, the role for Ask, the blocked and watched words and the small feed.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, tabs, card, list, empty, myLevel, search, setup, dlist, blockedRow, channelHint
local feed
local current = 1
local query = ""
local I = "Interface\\Icons\\"
-- The board tabs, one per kind, then the setup page.
local TAB_KEYS = { "TAB_GROUPS", "TAB_WTS", "TAB_WTB", "TAB_CRAFT", "TAB_GUILD", "TAB_OTHER", "TAB_SETUP" }
local SETUP = #TAB_KEYS

local function ago(t)
    local m = math.floor((time() - t) / 60)
    return m < 1 and L.NOW or L.AGO_M:format(m)
end

local function classHex(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if not c then return nil end
    return string.format("|cff%02x%02x%02x", math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255))
end

local function itemIcon(id)
    if not id then return nil end
    local get = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
    return get and get(id) or nil
end

---- Board rows ------------------------------------------------------------------

local function makeRow(r)
    r.fold = CreateFrame("Button", nil, r)
    r.fold:SetAllPoints()
    r.fold:SetScript("OnClick", function(self)
        local key = self:GetParent().key
        if not key then return end
        ns.collapsed[key] = not ns.collapsed[key] or nil
        ns.Refresh()
    end)
    r.head = S.Text(r, 12)
    r.head:SetPoint("LEFT", 10, 0)
    r.head:SetPoint("RIGHT", -110, 0)
    r.head:SetWordWrap(false)
    r.lfm = S.Ghost(S.Button(r, 96, 28))
    r.lfm:SetPoint("RIGHT", 0, 0)
    r.lfm:SetText(L.POST_LFM)
    r.lfm:SetScript("OnClick", function(self) ns.PostLFM(self:GetParent().key) end)

    r.who = S.Text(r, 12)
    r.who:SetPoint("TOPLEFT", 10, -7)
    r.who:SetWidth(130)
    r.who:SetWordWrap(false)
    r.age = S.Text(r, 11, S.FAINT)
    r.age:SetPoint("TOPLEFT", r.who, "BOTTOMLEFT", 0, -4)
    r.age:SetWidth(130)
    r.age:SetWordWrap(false)
    r.act = S.Button(r, 86, 28)
    r.act:SetPoint("RIGHT", 0, 0)
    r.act:SetScript("OnClick", function(self)
        local p = self:GetParent().post
        if p.role == "LFG" then ns.Invite(p.author) else ns.Ask(p) end
    end)
    r.whisper = S.Button(r, 86, 28)
    r.whisper:SetText(L.WHISPER)
    r.whisper:SetScript("OnClick", function(self) ns.Whisper(self:GetParent().post.author) end)
    r.hide = S.Ghost(S.Button(r, 28, 28))
    r.hide:SetText("x")
    r.hide:SetScript("OnClick", function(self) ns.BlockPlayer(self:GetParent().post.short) end)
    r.icon = S.IconBox(r, 28)
    r.icon:SetPoint("TOPLEFT", 150, -8)
    r.text = S.Text(r, 12)
    r.text:SetJustifyV("TOP")
    r.text:SetMaxLines(3)
end

local function fillRow(r, item)
    local header = item.header
    r.fold:SetShown(header)
    r.head:SetShown(header)
    r.lfm:SetShown(header and item.dungeon ~= nil and ns.CanPostLFM())
    for _, w in ipairs({ r.who, r.age, r.text, r.whisper, r.act, r.hide }) do w:SetShown(not header) end
    r.icon:SetShown(not header and item.item ~= nil)
    if header then
        r.key = item.key
        -- The dungeon in the quest log colour of its level for you, with its level range.
        local d = item.dungeon and ns.Dungeon(item.dungeon)
        local name = ns.DungeonName(item.dungeon)
        local range = ""
        if d then
            name = S.Hex(S.LevelColor(math.floor((d.min + d.max) / 2))) .. name .. "|r"
            range = "  " .. S.Hex(S.MUTED) .. (d.min == d.max and tostring(d.min) or (d.min .. "-" .. d.max)) .. "|r"
        end
        local arrow = S.Hex(S.FAINT) .. (item.closed and "+  " or "-  ") .. "|r"
        r.head:SetText(arrow .. name .. range .. "   " .. S.Hex(S.FAINT) .. "(" .. item.count .. ")|r")
        S.Fill(r, S.RAISED)
        return
    end
    S.Fill(r, S.CLEAR)
    r.post = item
    local role = item.role and (S.Hex(S.Accent()) .. L[item.role] .. "|r ") or ""
    local hex = classHex(item.class)
    r.who:SetText(role .. (hex and (hex .. item.short .. "|r") or item.short))
    -- The roles an LFM asks for go under the name, next to the age.
    local needs = {}
    for _, n in ipairs(item.needs or {}) do needs[#needs + 1] = L["ROLE_" .. n] end
    r.age:SetText(ago(item.t) .. (#needs > 0 and ("  " .. S.Hex(S.WARN) .. table.concat(needs, " ") .. "|r") or ""))
    r.text:SetText(item.text)
    local act = item.kind == "GROUP"
    r.act:SetShown(act)
    r.act:SetText(item.role == "LFG" and L.INVITE or L.ASK_BTN)
    r.whisper:ClearAllPoints()
    if act then r.whisper:SetPoint("RIGHT", r.act, "LEFT", -6, 0) else r.whisper:SetPoint("RIGHT", 0, 0) end
    r.hide:ClearAllPoints()
    r.hide:SetPoint("RIGHT", r.whisper, "LEFT", -4, 0)
    r.text:ClearAllPoints()
    if item.item then
        r.icon:SetIcon(itemIcon(item.item))
        r.text:SetPoint("TOPLEFT", 186, -7)
    else
        r.text:SetPoint("TOPLEFT", 150, -7)
    end
    r.text:SetPoint("BOTTOMRIGHT", r.hide, "BOTTOMLEFT", -8, -11)
end

---- Setup rows ------------------------------------------------------------------

-- A row of the setup list: the dungeon, its level range, and the Show and Alert boxes.
local function makeDungeonRow(r)
    r.name = S.Text(r, 12)
    r.name:SetPoint("LEFT", 4, 0)
    r.name:SetPoint("RIGHT", -150, 0)
    r.name:SetWordWrap(false)
    r.alert = S.Check(r, 26)
    r.alert:SetPoint("RIGHT", -24, 0)
    r.show = S.Check(r, 26)
    r.show:SetPoint("RIGHT", -96, 0)
    r.show:SetScript("OnClick", function(self)
        local key = self:GetParent().key
        ns.db.only[key] = (not ns.db.only[key]) or nil
        ns.Refresh()
    end)
    r.alert:SetScript("OnClick", function(self)
        local key = self:GetParent().key
        ns.db.alert[key] = (not ns.db.alert[key]) or nil
        ns.Refresh()
        if ns.Feed then ns.Feed() end
    end)
end

local function fillDungeonRow(r, d)
    r.key = d.key
    local range = d.min == d.max and tostring(d.min) or (d.min .. "-" .. d.max)
    r.name:SetText(S.Hex(S.LevelColor(math.floor((d.min + d.max) / 2))) .. ns.DungeonName(d.key) .. "|r  " ..
        S.Hex(S.MUTED) .. range .. "|r")
    r.show:SetChecked(ns.db.only[d.key] == true)
    r.alert:SetChecked(ns.db.alert[d.key] == true)
end

local function channelText()
    local missing = ns.MissingChannels()
    if #missing == 0 then return "" end
    local names = {}
    for _, k in ipairs(missing) do names[#names + 1] = L["CH_" .. k] end
    return L.NOT_IN:format(table.concat(names, ", "))
end

function ns.Refresh()
    if not frame or not frame:IsShown() then return end
    for i, key in ipairs(TAB_KEYS) do
        local n = i < SETUP and ns.Count(ns.KINDS[i]) or 0
        tabs.buttons[i]:SetText(L[key] .. (n > 0 and (" " .. n) or ""))
    end
    card:SetShown(current ~= SETUP)
    setup:SetShown(current == SETUP)
    if current == SETUP then
        local rows = {}
        for _, d in ipairs(ns.DUNGEONS) do rows[#rows + 1] = ns.Dungeon(d[1]) end
        dlist:SetData(rows)
        blockedRow.label:SetText(L.BLOCKED_N:format(ns.BlockedCount()))
        blockedRow.control:SetEnabled(ns.BlockedCount() > 0)
        channelHint:SetText(channelText())
        return
    end
    local items = ns.View(ns.KINDS[current], ns.db.myLevel, UnitLevel("player") or 60, query)
    list:SetData(items)
    empty:SetShown(#items == 0)
    if query ~= "" then
        empty:Set(L.EMPTY_SEARCH)
    elseif current == 1 and next(ns.db.only) then
        empty:Set(L.EMPTY_PICKED, channelText())
    else
        empty:Set(L.EMPTY, channelText())
    end
    myLevel:SetShown(current == 1)
end

local function textEdit(width, get, set)
    local e = S.Edit(frame.body, width, 28)
    e:SetJustifyH("LEFT")
    e:SetMaxLetters(200)
    e:SetScript("OnShow", function(self) self:SetText(get() or "") end)
    local function apply(self) set(self:GetText() or ""); self:ClearFocus() end
    e:SetScript("OnEnterPressed", apply)
    e:SetScript("OnEditFocusLost", function(self) S.SetBorder(self, S.EDGE); apply(self) end)
    e:SetText(get() or "")
    return e
end

local function buildSetup(body, width)
    setup = CreateFrame("Frame", nil, body)
    setup:SetPoint("TOPLEFT", 0, -30 - S.GAP)
    setup:SetPoint("BOTTOMRIGHT")
    local leftW = math.floor((width - S.GAP) * 0.48)
    local rightW = width - leftW - S.GAP
    local dcard = S.Card(setup, L.SEC_DUNGEONS)
    dcard:SetPoint("TOPLEFT")
    dcard:SetPoint("BOTTOMLEFT")
    dcard:SetWidth(leftW)
    dlist = S.List(dcard.body, 32, makeDungeonRow, fillDungeonRow)
    dlist:SetPoint("TOPLEFT")
    dlist:SetPoint("BOTTOMRIGHT", -10, 0)
    -- Column names over the middle of the Show and Alert boxes.
    for _, c in ipairs({ { L.COL_SHOW, -109 }, { L.COL_ALERT, -37 } }) do
        local t = S.Text(dcard, 11, S.MUTED)
        t:SetPoint("BOTTOM", dlist, "TOPRIGHT", c[2], 10)
        t:SetText(c[1])
    end

    local right = CreateFrame("Frame", nil, setup)
    right:SetPoint("TOPLEFT", leftW + S.GAP, 0)
    right:SetPoint("BOTTOMRIGHT")
    local st = S.Stack(right)
    local alpha = S.Stepper(body, function() return ns.db.feed.alpha end,
        function(v) ns.db.feed.alpha = v; if ns.Feed then ns.Feed() end end, 10, 30, 100,
        function(v) return v .. "%" end, 110)
    local alerts, h1 = S.SettingsCard(right, L.SEC_ALERTS, {
        { L.OPT_SOUND, nil, function() return ns.db.sound end, function(v) ns.db.sound = v end,
          icon = I .. "INV_Misc_Bell_01" },
        { L.OPT_CHAT, nil, function() return ns.db.chat end, function(v) ns.db.chat = v end,
          icon = I .. "INV_Letter_15" },
        { L.WATCH, nil, control = textEdit(170, function() return ns.db.watch end,
            function(v) ns.db.watch = v end), icon = I .. "INV_Misc_Spyglass_02" },
        { L.OPT_FEED, nil, function() return ns.db.feed.show end,
          function(v) ns.db.feed.show = v; if ns.Feed then ns.Feed() end end, icon = I .. "INV_Scroll_03" },
        { L.OPT_THROUGH, nil, function() return ns.db.feed.through end,
          function(v) ns.db.feed.through = v; if ns.Feed then ns.Feed() end end, icon = I .. "Spell_Nature_Invisibilty" },
        { L.FEED_ALPHA, nil, control = alpha, icon = I .. "Spell_Shadow_Twilight" },
    })
    st:Add(alerts, h1)

    local roleLabels = {}
    for i, r in ipairs(ns.ROLES) do roleLabels[i] = L["ROLE_" .. r] end
    local roleHolder = CreateFrame("Frame", nil, body)
    roleHolder:SetSize(3 * 64 + 4, 30)
    local roles = S.Tabs(roleHolder, roleLabels, 64, function(i) ns.db.role = ns.ROLES[i] end)
    roleHolder:SetScript("OnShow", function()
        for i, r in ipairs(ns.ROLES) do if r == ns.db.role then roles:Select(i, true) end end
    end)
    local clear = S.Button(body, 90, 28)
    clear:SetText(L.UNBLOCK)
    clear:SetScript("OnClick", function() wipe(ns.db.blockNames); ns.Refresh() end)
    local me, h2 = S.SettingsCard(right, L.SEC_ME, {
        { L.MY_ROLE, nil, control = roleHolder, icon = I .. "Ability_Warrior_DefensiveStance" },
        { L.BLOCK_WORDS, nil, control = textEdit(170, function() return ns.db.blockWords end,
            function(v) ns.db.blockWords = v; ns.Refresh() end), icon = I .. "Ability_Warrior_ShieldWall" },
        { L.BLOCKED_N:format(0), nil, control = clear, icon = I .. "Spell_Holy_Silence" },
    })
    blockedRow = me.rows[3]
    st:Add(me, h2)
    channelHint = S.Note(right, 11)
    channelHint:SetTextColor(S.WARN[1], S.WARN[2], S.WARN[3], 1)
    st:Add(channelHint, 30)
    channelHint:SetWidth(rightW)
end

local function build()
    frame = S.Window("GulliBulletinFrame", L.TITLE, S.WIDE_W, S.DOCK_H)
    local body, width = frame.body, frame.inner[1]
    local labels = {}
    for i, k in ipairs(TAB_KEYS) do labels[i] = L[k] end
    tabs = S.Tabs(body, labels, math.floor((width - 4) / #labels), function(i) current = i; ns.Refresh() end)

    card = S.Card(body)
    card:SetPoint("TOPLEFT", 0, -30 - S.GAP)
    card:SetPoint("BOTTOMRIGHT")
    myLevel = S.CheckRow(card.body, L.MY_LEVEL, function() return ns.db.myLevel end,
        function(v) ns.db.myLevel = v; ns.Refresh() end, 300)
    myLevel:SetPoint("TOPLEFT", -6, 2)
    search = S.Edit(card.body, 220, 28)
    search:SetPoint("TOPRIGHT", -10, 1)
    search:SetJustifyH("LEFT")
    S.Placeholder(search, L.SEARCH)
    search:HookScript("OnTextChanged", function(self)
        query = self:GetText() or ""
        ns.Refresh()
    end)

    list = S.List(card.body, 50, makeRow, fillRow)
    list:SetPoint("TOPLEFT", 0, -36)
    list:SetPoint("BOTTOMRIGHT", -10, 0)
    empty = S.Empty(list)
    empty:Set(L.EMPTY)
    buildSetup(body, width)

    frame:SetScript("OnShow", function()
        myLevel:SetChecked(ns.db.myLevel)
        tabs:Select(current)
    end)
    -- Ages and expiry move on while the window is open.
    local elapsed = 0
    frame:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + (dt or 0)
        if elapsed > 20 then elapsed = 0; ns.Refresh() end
    end)
end

-- Picks a tab (1 Groups ... 7 Setup), for the previews and the tests.
function ns.ShowTab(i)
    ns.Window():Show()
    tabs:Select(i)
end

-- Types into the search box, for the previews and the tests.
function ns.Search(text)
    ns.Window()
    search:SetText(text)
    query = text
    ns.Refresh()
end

function ns.Toggle()
    S.ToggleWindow(ns.Window())
end

-- The window, for the hub (/gulli) to show inside it.
function ns.Window()
    if not frame then build() end
    return frame
end

---- The small feed ------------------------------------------------------------

-- The newest groups for the alerted dungeons (all groups while none is alerted), on a small
-- movable panel. Its opacity is a setting; click-through lets clicks reach the game below.
ns.FEED_ROWS = 5

function ns.FeedItems()
    local out = {}
    local any = next(ns.db.alert) ~= nil
    for _, p in ipairs(ns.posts) do
        if p.kind == "GROUP" and (not any or (p.dungeon and ns.db.alert[p.dungeon])) then
            out[#out + 1] = p
            if #out >= ns.FEED_ROWS then break end
        end
    end
    return out
end

local function buildFeed()
    feed = CreateFrame("Button", "GulliBulletinFeed", UIParent)
    feed:SetSize(320, 26 + ns.FEED_ROWS * 18)
    feed:SetFrameStrata("MEDIUM")
    feed:SetClampedToScreen(true)
    feed:SetMovable(true)
    feed:RegisterForDrag("LeftButton")
    feed:SetScript("OnDragStart", feed.StartMoving)
    feed:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint()
        ns.db.feed.point = { point, rel, x, y }
    end)
    feed:SetScript("OnClick", function() ns.Toggle() end)
    S.Box(feed)
    feed.title = S.Text(feed, 11, S.MUTED)
    feed.title:SetPoint("TOPLEFT", 8, -6)
    feed.title:SetText(L.TITLE)
    feed.lines = {}
    for i = 1, ns.FEED_ROWS do
        local t = S.Text(feed, 11)
        t:SetPoint("TOPLEFT", 8, -6 - i * 18)
        t:SetPoint("RIGHT", -8, 0)
        t:SetWordWrap(false)
        feed.lines[i] = t
    end
end

function ns.Feed()
    local o = ns.db and ns.db.feed
    if not o then return end
    if not o.show then
        if feed then feed:Hide() end
        return
    end
    if not feed then buildFeed() end
    feed:ClearAllPoints()
    local p = o.point
    if p then feed:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0) else feed:SetPoint("TOPRIGHT", -40, -220) end
    feed:SetAlpha((o.alpha or 80) / 100)
    feed:EnableMouse(not o.through)
    local items = ns.FeedItems()
    for i, line in ipairs(feed.lines) do
        local item = items[i]
        if item then
            local where = item.dungeon and ns.DungeonName(item.dungeon) or L.OTHER_GROUPS
            line:SetText(S.Hex(S.Accent()) .. where .. "|r  " .. item.short .. "  " .. S.Hex(S.MUTED) .. item.text .. "|r")
        else
            line:SetText(i == 1 and (S.Hex(S.FAINT) .. L.FEED_EMPTY .. "|r") or "")
        end
    end
    feed:Show()
end

function ns.SetupFeed() ns.Feed() end
