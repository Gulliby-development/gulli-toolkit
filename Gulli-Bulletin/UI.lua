-- The board window: a tab per kind, groups split by dungeon, Whisper and Invite on each row.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, tabs, list, empty, myLevel
local current = 1
local TAB_KEYS = { "TAB_GROUPS", "TAB_WTS", "TAB_WTB", "TAB_CRAFT", "TAB_GUILD", "TAB_OTHER" }

local function ago(t)
    local m = math.floor((time() - t) / 60)
    return m < 1 and L.NOW or L.AGO_M:format(m)
end

local function makeRow(r)
    r.head = S.Text(r, 13, S.Accent())
    r.head:SetPoint("LEFT", 8, 0)
    r.head:SetPoint("RIGHT", -8, 0)
    r.head:SetWordWrap(false)
    r.who = S.Text(r, 12)
    r.who:SetPoint("TOPLEFT", 8, -5)
    r.who:SetWidth(130)
    r.who:SetWordWrap(false)
    r.age = S.Text(r, 10, S.MUTED)
    r.age:SetPoint("TOPLEFT", r.who, "BOTTOMLEFT", 0, -3)
    r.invite = S.Button(r, 76, 28)
    r.invite:SetPoint("RIGHT", -4, 0)
    r.invite:SetText(L.INVITE)
    r.invite:SetScript("OnClick", function(self) ns.Invite(self:GetParent().post.author) end)
    r.whisper = S.Button(r, 76, 28)
    r.whisper:SetPoint("RIGHT", r.invite, "LEFT", -4, 0)
    r.whisper:SetText(L.WHISPER)
    r.whisper:SetScript("OnClick", function(self) ns.Whisper(self:GetParent().post.author) end)
    r.text = S.Text(r, 12)
    r.text:SetPoint("TOPLEFT", 144, -5)
    r.text:SetPoint("BOTTOMRIGHT", r.whisper, "BOTTOMLEFT", -6, -9)
    r.text:SetJustifyV("TOP")
    r.text:SetMaxLines(3)
end

local function fillRow(r, item)
    local header = item.header
    r.head:SetShown(header)
    for _, w in ipairs({ r.who, r.age, r.text, r.whisper, r.invite }) do w:SetShown(not header) end
    if header then
        r.head:SetText(ns.DungeonName(item.dungeon) .. "  " .. S.Hex(S.MUTED) .. item.count .. "|r")
        S.Fill(r, S.PANEL)
        return
    end
    S.Fill(r, S.ROW)
    r.post = item
    local role = item.role and (S.Hex(S.Accent()) .. L[item.role] .. "|r ") or ""
    r.who:SetText(role .. item.short)
    r.age:SetText(ago(item.t))
    r.text:SetText(item.text)
    r.invite:SetShown(item.kind == "GROUP" and item.role == "LFG")
end

function ns.Refresh()
    if not frame or not frame:IsShown() then return end
    for i, key in ipairs(TAB_KEYS) do
        local n = ns.Count(ns.KINDS[i])
        tabs.buttons[i]:SetText(L[key] .. (n > 0 and (" " .. n) or ""))
    end
    local items = ns.View(ns.KINDS[current], ns.db.myLevel, UnitLevel("player") or 60)
    list:SetData(items)
    empty:SetShown(#items == 0)
    myLevel:SetShown(current == 1)
    myLevel.label:SetShown(current == 1)
end

local function build()
    frame = S.Window("GulliBulletinFrame", L.TITLE, 680, 460)
    local body = frame.body
    local labels = {}
    for i, k in ipairs(TAB_KEYS) do labels[i] = L[k] end
    tabs = S.Tabs(body, labels, 104, function(i) current = i; ns.Refresh() end)

    myLevel = S.Check(body, 26)
    myLevel:SetPoint("TOPLEFT", 0, -36)
    myLevel:SetScript("OnClick", function(self)
        ns.db.myLevel = not ns.db.myLevel
        self:SetChecked(ns.db.myLevel)
        ns.Refresh()
    end)
    myLevel.label = S.Text(body, 12)
    myLevel.label:SetPoint("LEFT", myLevel, "RIGHT", 4, 0)
    myLevel.label:SetText(L.MY_LEVEL)

    list = S.List(body, 46, makeRow, fillRow)
    list:SetPoint("TOPLEFT", 0, -68)
    list:SetPoint("BOTTOMRIGHT", -12, 0)
    empty = S.Note(body, 12)
    empty:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -8)
    empty:SetPoint("RIGHT", list, "RIGHT", -4, 0)
    empty:SetText(L.EMPTY)

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

function ns.Toggle()
    if not frame then build() end
    frame:SetShown(not frame:IsShown())
end
