-- The board window: a tab per kind, groups split by dungeon, Whisper and Invite on each row.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, tabs, card, list, empty, myLevel, setup, dlist
local current = 1
-- The board tabs, one per kind, then the setup page (dungeons to show and to alert on).
local TAB_KEYS = { "TAB_GROUPS", "TAB_WTS", "TAB_WTB", "TAB_CRAFT", "TAB_GUILD", "TAB_OTHER", "TAB_SETUP" }
local SETUP = #TAB_KEYS

local function ago(t)
    local m = math.floor((time() - t) / 60)
    return m < 1 and L.NOW or L.AGO_M:format(m)
end

local function makeRow(r)
    r.head = S.Text(r, 12)
    r.head:SetPoint("LEFT", 10, 0)
    r.head:SetPoint("RIGHT", -8, 0)
    r.head:SetWordWrap(false)
    r.who = S.Text(r, 12)
    r.who:SetPoint("TOPLEFT", 10, -7)
    r.who:SetWidth(130)
    r.who:SetWordWrap(false)
    r.age = S.Text(r, 11, S.FAINT)
    r.age:SetPoint("TOPLEFT", r.who, "BOTTOMLEFT", 0, -4)
    r.invite = S.Button(r, 96, 28)
    r.invite:SetPoint("RIGHT", 0, 0)
    r.invite:SetText(L.INVITE)
    r.invite:SetScript("OnClick", function(self) ns.Invite(self:GetParent().post.author) end)
    r.whisper = S.Button(r, 86, 28)
    r.whisper:SetPoint("RIGHT", r.invite, "LEFT", -6, 0)
    r.whisper:SetText(L.WHISPER)
    r.whisper:SetScript("OnClick", function(self) ns.Whisper(self:GetParent().post.author) end)
    r.text = S.Text(r, 12)
    r.text:SetPoint("TOPLEFT", 150, -7)
    r.text:SetPoint("BOTTOMRIGHT", r.whisper, "BOTTOMLEFT", -10, -11)
    r.text:SetJustifyV("TOP")
    r.text:SetMaxLines(3)
end

local function fillRow(r, item)
    local header = item.header
    r.head:SetShown(header)
    for _, w in ipairs({ r.who, r.age, r.text, r.whisper, r.invite }) do w:SetShown(not header) end
    if header then
        -- The dungeon in the quest log colour of its level for you, with its level range.
        local d = item.dungeon and ns.Dungeon(item.dungeon)
        local name = ns.DungeonName(item.dungeon)
        local range = ""
        if d then
            name = S.Hex(S.LevelColor(math.floor((d.min + d.max) / 2))) .. name .. "|r"
            range = "  " .. S.Hex(S.MUTED) .. (d.min == d.max and tostring(d.min) or (d.min .. "-" .. d.max)) .. "|r"
        end
        r.head:SetText(name .. range .. "   " .. S.Hex(S.FAINT) .. "(" .. item.count .. ")|r")
        S.Fill(r, S.RAISED)
        return
    end
    S.Fill(r, S.CLEAR)
    r.post = item
    local role = item.role and (S.Hex(S.Accent()) .. L[item.role] .. "|r ") or ""
    r.who:SetText(role .. item.short)
    r.age:SetText(ago(item.t))
    r.text:SetText(item.text)
    local inv = item.kind == "GROUP" and item.role == "LFG"
    r.invite:SetShown(inv)
    r.whisper:ClearAllPoints()
    if inv then r.whisper:SetPoint("RIGHT", r.invite, "LEFT", -6, 0) else r.whisper:SetPoint("RIGHT", 0, 0) end
end

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
        return
    end
    local items = ns.View(ns.KINDS[current], ns.db.myLevel, UnitLevel("player") or 60)
    list:SetData(items)
    empty:SetShown(#items == 0)
    if current == 1 and next(ns.db.only) and #items == 0 then empty:Set(L.EMPTY_PICKED) else empty:Set(L.EMPTY) end
    myLevel:SetShown(current == 1)
end

local function buildSetup(body, width)
    setup = CreateFrame("Frame", nil, body)
    setup:SetPoint("TOPLEFT", 0, -30 - S.GAP)
    setup:SetPoint("BOTTOMRIGHT")
    local leftW = math.floor((width - S.GAP) * 0.58)
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
    local alerts, h = S.SettingsCard(right, L.SEC_ALERTS, {
        { L.OPT_SOUND, nil, function() return ns.db.sound end, function(v) ns.db.sound = v end,
          icon = "Interface\\Icons\\INV_Misc_Bell_01" },
        { L.OPT_CHAT, nil, function() return ns.db.chat end, function(v) ns.db.chat = v end,
          icon = "Interface\\Icons\\INV_Letter_15" },
    })
    st:Add(alerts, h)
    local hint = S.Paragraph(right, L.SETUP_HINT, width - leftW - S.GAP, 11)
    st:Add(hint, 60)
end

local function build()
    frame = S.Window("GulliBulletinFrame", L.TITLE, S.WIDE_W, 500)
    local body, width = frame.body, frame.inner[1]
    local labels = {}
    for i, k in ipairs(TAB_KEYS) do labels[i] = L[k] end
    tabs = S.Tabs(body, labels, math.floor((width - 4) / #labels), function(i) current = i; ns.Refresh() end)

    card = S.Card(body)
    card:SetPoint("TOPLEFT", 0, -30 - S.GAP)
    card:SetPoint("BOTTOMRIGHT")
    myLevel = S.CheckRow(card.body, L.MY_LEVEL, function() return ns.db.myLevel end,
        function(v) ns.db.myLevel = v; ns.Refresh() end, width - 60)
    myLevel:SetPoint("TOPLEFT", -6, 2)

    list = S.List(card.body, 50, makeRow, fillRow)
    list:SetPoint("TOPLEFT", 0, -34)
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

function ns.Toggle()
    S.ToggleWindow(ns.Window())
end

-- The window, for the hub (/gulli) to show inside it.
function ns.Window()
    if not frame then build() end
    return frame
end
