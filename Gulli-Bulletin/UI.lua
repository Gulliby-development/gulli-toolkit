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
end

local function build()
    frame = S.Window("GulliBulletinFrame", L.TITLE, S.WIDE_W, 500)
    local body, width = frame.body, frame.inner[1]
    local labels = {}
    for i, k in ipairs(TAB_KEYS) do labels[i] = L[k] end
    tabs = S.Tabs(body, labels, math.floor((width - 4) / #labels), function(i) current = i; ns.Refresh() end)

    local card = S.Card(body)
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
    S.ToggleWindow(ns.Window())
end

-- The window, for the hub (/gulli) to show inside it.
function ns.Window()
    if not frame then build() end
    return frame
end
