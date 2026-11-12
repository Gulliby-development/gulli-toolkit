-- Four tabs. Character: characters on the left; on the right each raid or key with a progress
-- bar and its steps, the open ones marked Next with what they need and a map button. All
-- characters: one row per character, one column per raid. Group: what the group and the guild
-- told, with Ask guild and a line to the group about who has no access. Settings: the
-- switches and the export text.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, tabs, chars, list, forget, grid, gridHead, groupList, groupHead, raidPills, tellBtn, askBtn
local pages, exportBox, switchRows = {}, nil, {}
local selected, groupRaid = nil, "ONY"
local ICON = {
    done = "Interface\\RaidFrame\\ReadyCheck-Ready",
    active = "Interface\\RaidFrame\\ReadyCheck-Waiting",
    todo = "Interface\\RaidFrame\\ReadyCheck-NotReady",
}
-- The raid keys as columns, in the order of ns.RAIDS.
local KEYS = {}
do
    local seen = {}
    for _, r in ipairs(ns.RAIDS) do
        if not seen[r.key] then seen[r.key] = true; KEYS[#KEYS + 1] = r.key end
    end
end
local COL_W = 86

local function classColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return c and string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) or ""
end

-- How many chains of a character are ready, of those that apply to it.
local function readyCount(char)
    local n, all = 0, 0
    for _, r in ipairs(ns.RaidsFor(char)) do
        all = all + 1
        if ns.Progress(char, r).ready then n = n + 1 end
    end
    return n, all
end

local function makeChar(r)
    S.NavRow(r)
    r.line:Hide()
    r.text = S.Text(r, 12)
    r.text:SetPoint("LEFT", 12, 0)
    r.text:SetPoint("RIGHT", -44, 0)
    r.text:SetWordWrap(false)
    r.count = S.Text(r, 11, S.FAINT)
    r.count:SetPoint("RIGHT", -8, 0)
    r.click = CreateFrame("Button", nil, r)
    r.click:SetAllPoints()
    r.click:SetScript("OnClick", function(self) selected = self:GetParent().entry.key; ns.Refresh() end)
end

local function fillChar(r, e)
    r.entry = e
    r.text:SetText(classColor(e.char.class) .. e.char.name .. "|r " .. S.Hex(S.MUTED) .. (e.char.level or "") .. "|r")
    local n, all = readyCount(e.char)
    r.count:SetText(n .. "/" .. all)
    r.count:SetTextColor(unpack(n == all and S.GOOD or S.FAINT))
    r:SetSelected(e.key == selected)
end

-- A raid header shows the item the attunement gives, from the game.
local function raidIcon(raid)
    local get = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
    return raid.item and get and get(raid.item) or "Interface\\Icons\\INV_Misc_Key_14"
end

local function makeRow(r)
    r.raid = S.IconBox(r, 26)
    r.raid:SetPoint("LEFT", 6, 0)
    r.bar = S.Progress(r, 6)
    r.bar:SetPoint("BOTTOMLEFT", r.raid, "BOTTOMRIGHT", 10, 1)
    r.bar:SetWidth(160)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(16, 16)
    r.text = S.Text(r, 12)
    r.text:SetWordWrap(false)
    r.sub = S.Text(r, 10, S.MUTED)
    r.sub:SetWordWrap(false)
    r.pin = S.FitButton(r, L.MAP, 26, 56)
    r.pin:SetPoint("RIGHT", -8, 0)
    r.pin:SetScript("OnClick", function(self) ns.SetPin(self:GetParent().item.step) end)
end

local TAGS = { elite = "TAG_ELITE", dungeon = "TAG_DUNGEON", raid = "TAG_RAID" }

-- The line under an open step: where it starts, the level it needs, its kind, the items.
local function needLine(step, char, mine)
    local n = ns.Needs(step)
    local parts = { ns.Where(step) }
    if n.level > (char.level or 0) then
        parts[#parts + 1] = S.Hex(S.LevelColor(n.level, char.level)) .. L.FROM_LEVEL:format(n.level) .. "|r"
    end
    if n.tag then parts[#parts + 1] = S.Hex(S.WARN) .. L[TAGS[n.tag]] .. "|r" end
    if mine then
        for _, it in ipairs(n.items) do
            local have = ns.Have(it.id)
            local name = ((C_Item and C_Item.GetItemNameByID) or function() end)(it.id) or ("#" .. it.id)
            parts[#parts + 1] = S.Hex(have >= it.count and S.GOOD or S.MUTED) .. L.HAVE:format(name, have) .. "|r"
        end
    end
    return table.concat(parts, "  ·  ")
end

local function fillRow(r, item)
    r.icon:ClearAllPoints()
    r.text:ClearAllPoints()
    r.sub:ClearAllPoints()
    r.raid:SetShown(item.header == true)
    r.bar:SetShown(item.header == true)
    r.pin:Hide()
    r.item = item
    if item.header then
        local p = item.progress
        r.raid:SetIcon(raidIcon(p.raid))
        r.icon:SetPoint("RIGHT", -10, 0)
        r.icon:SetTexture(ICON[p.ready and "done" or (p.done > 0 and "active" or "todo")])
        r.text:SetPoint("TOPLEFT", r.raid, "TOPRIGHT", 10, 0)
        r.text:SetPoint("RIGHT", r.icon, "LEFT", -8, 0)
        local state = p.ready and (S.Hex(S.GOOD) .. L.READY .. "|r") or
            (S.Hex(p.done > 0 and S.Accent() or S.MUTED) .. L.STEPS:format(p.done, p.total) .. "  " .. p.pct .. "%|r")
        r.text:SetText(ns.RaidName(p.raid) .. "   " .. state)
        r.text:SetTextColor(unpack(S.TEXT))
        r.bar:Set(p.pct / 100, p.ready and S.GOOD or S.Accent())
        r.sub:SetText("")
        S.Fill(r, S.RAISED)
        return
    end
    S.Fill(r, S.CLEAR)
    if item.doneLine then
        r.icon:SetTexture(ICON.done)
        r.icon:SetPoint("LEFT", 40, 0)
        r.text:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
        r.text:SetPoint("RIGHT", -8, 0)
        r.text:SetText(L.DONE_STEPS:format(item.n))
        r.text:SetTextColor(unpack(S.MUTED))
        r.sub:SetText("")
        return
    end
    local name = ns.QuestName(item.step)
    r.text:SetText(item.isNext and (S.Hex(S.Accent()) .. L.NEXT .. "|r " .. name) or name)
    r.text:SetTextColor(unpack(item.state == "done" and S.MUTED or S.TEXT))
    r.icon:SetTexture(ICON[item.state])
    r.icon:SetPoint("TOPLEFT", item.isNext and 40 or 40, item.isNext and -5 or -11)
    r.text:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, 1)
    if item.isNext then
        r.pin:SetShown(ns.Needs(item.step).x > 0)
        r.text:SetPoint("RIGHT", r.pin, "LEFT", -8, 0)
        r.sub:SetPoint("TOPLEFT", r.text, "BOTTOMLEFT", 0, -3)
        r.sub:SetPoint("RIGHT", r.pin, "LEFT", -8, 0)
        r.sub:SetText(needLine(item.step, item.char, item.mine))
    else
        r.text:SetPoint("RIGHT", -8, 0)
        r.sub:SetText("")
    end
end

-- A row of raid columns: a name on the left, one cell per raid key.
local function makeGridRow(r)
    r.name = S.Text(r, 12)
    r.name:SetPoint("LEFT", 10, 0)
    r.name:SetPoint("RIGHT", -(#KEYS * COL_W) - 8, 0)
    r.name:SetWordWrap(false)
    r.cells = {}
    for i = 1, #KEYS do
        local c = S.Text(r, 12)
        c:SetWidth(COL_W - 6)
        c:SetJustifyH("CENTER")
        c:SetWordWrap(false)
        c:SetPoint("RIGHT", -((#KEYS - i) * COL_W) - 8, 0)
        r.cells[i] = c
    end
    r.click = CreateFrame("Button", nil, r)
    r.click:SetAllPoints()
    r.click:SetScript("OnClick", function(self)
        local e = self:GetParent().entry
        if e and e.key then selected = e.key; tabs:Select(1) end
    end)
end

-- A cell: ready, x/y, or a dash when the raid is not for this character or not known.
local function cellText(x)
    if not x then return S.Hex(S.FAINT) .. "-|r" end
    if x.ready then return S.Hex(S.GOOD) .. L.READY .. "|r" end
    return S.Hex((x.done or 0) > 0 and S.Accent() or S.MUTED) .. (x.done or 0) .. "/" .. (x.total or 0) .. "|r"
end

local function fillGridRow(r, e)
    r.entry = e
    r.name:SetText(e.label)
    for i, key in ipairs(KEYS) do r.cells[i]:SetText(e.section and "" or cellText(e.raids and e.raids[key])) end
    S.Fill(r, e.key == selected and S.RAISED or S.CLEAR)
end

local function charRaids(char)
    local out = {}
    for _, r in ipairs(ns.RaidsFor(char)) do
        local p = ns.Progress(char, r)
        out[r.key] = { done = p.done, total = p.total, ready = p.ready }
    end
    return out
end

local function gridHeader(parent)
    local h = CreateFrame("Frame", nil, parent)
    h:SetHeight(22)
    for i, key in ipairs(KEYS) do
        local t = S.Text(h, 11, S.FAINT)
        t:SetWidth(COL_W - 6)
        t:SetJustifyH("CENTER")
        t:SetWordWrap(false)
        t:SetPoint("RIGHT", -((#KEYS - i) * COL_W) - 18, 0)
        t:SetText(L["SHORT_" .. key])
    end
    local rule = S.Divider(h, S.EDGE)
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetHeight(1)
    return h
end

local function visibleChars()
    local all, out = ns.Chars(), {}
    for _, e in ipairs(all) do
        local started = e.me
        if not started then
            for _, r in ipairs(ns.RaidsFor(e.char)) do
                local p = ns.Progress(e.char, r)
                if p.done > 0 or p.ready then started = true break end
            end
        end
        if started or not ns.Get("hideEmpty") then out[#out + 1] = e end
    end
    return out
end

function ns.Refresh()
    if not frame or not frame:IsShown() then return end
    local all = visibleChars()
    if not selected or not ns.db.chars[selected] then selected = all[1] and all[1].key end
    local page = tabs.selected
    if page == 1 then
        chars:SetData(all)
        local items = {}
        local c = selected and ns.db.chars[selected]
        if c then
            local mine = selected == ns.CharKey()
            for _, raid in ipairs(ns.RaidsFor(c)) do
                if not ns.Get("onlyAvail") or ns.Available(c, raid) then
                    local p = ns.Progress(c, raid)
                    items[#items + 1] = { header = true, progress = p }
                    if not p.ready then
                        local open = {}
                        for _, s in ipairs(p.nexts) do open[s] = true end
                        -- Done steps fold into one line; the rest keep their order.
                        if p.done > 0 then items[#items + 1] = { doneLine = true, n = p.done } end
                        for _, s in ipairs(p.steps) do
                            if s.state ~= "done" then
                                items[#items + 1] = { step = s.step, state = s.state, isNext = open[s.step] == true,
                                                      char = c, mine = mine }
                            end
                        end
                    end
                end
            end
        end
        list:SetData(items)
        forget:SetEnabled(selected ~= nil and selected ~= ns.CharKey())
    elseif page == 2 then
        local rows = {}
        for _, e in ipairs(all) do
            rows[#rows + 1] = { key = e.key, raids = charRaids(e.char),
                                label = classColor(e.char.class) .. e.char.name .. "|r " .. S.Hex(S.MUTED) .. (e.char.level or "") .. "|r" }
        end
        grid:SetData(rows)
    elseif page == 3 then
        local rows, seen = {}, {}
        local me = ns.db.chars[ns.CharKey()]
        if me then
            rows[#rows + 1] = { label = UnitName("player"), raids = charRaids(me) }
            seen[UnitName("player")] = true
        end
        for _, m in ipairs(ns.Group()) do
            seen[m.name] = true
            rows[#rows + 1] = { label = m.name .. (m.raids and "" or (" " .. S.Hex(S.FAINT) .. L.NO_MODULE .. "|r")), raids = m.raids }
        end
        local guild = {}
        for _, m in ipairs(ns.Heard()) do
            if not seen[m.name] then guild[#guild + 1] = { label = m.name, raids = m.raids } end
        end
        if #guild > 0 then
            rows[#rows + 1] = { label = S.Hex(S.FAINT) .. L.HEARD .. "|r", section = true }
            for _, g in ipairs(guild) do rows[#rows + 1] = g end
        end
        groupList:SetData(rows)
        for i, key in ipairs(KEYS) do raidPills[i]:SetSelected(key == groupRaid) end
        tellBtn:SetEnabled(IsInGroup ~= nil and IsInGroup() == true)
        askBtn:SetEnabled(IsInGuild ~= nil and IsInGuild() == true and ns.Get("groupMsg"))
    else
        for _, x in ipairs(switchRows) do x.row:SetChecked(x.get()) end
        exportBox.edit:SetText(ns.Export())
    end
end

local function page(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetPoint("TOPLEFT", 0, -30 - S.GAP)
    p:SetPoint("BOTTOMRIGHT")
    p:Hide()
    pages[#pages + 1] = p
    return p
end

local function showTab(i)
    for j, p in ipairs(pages) do p:SetShown(j == i) end
    ns.Refresh()
end

-- Opens a tab: 1 character, 2 all characters, 3 group, 4 settings.
function ns.ShowTab(i)
    ns.Window()
    tabs:Select(i)
end

local function build()
    frame = S.Window("GulliAttuneFrame", L.TITLE, S.WIDE_W, S.DOCK_H)
    local body = frame.body
    tabs = S.Tabs(body, { L.TAB_CHAR, L.TAB_ALL, L.TAB_GROUP, L.TAB_SETTINGS }, nil, showTab)

    -- Character
    local p1 = page(body)
    local left = S.Card(p1)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(200)
    forget = S.Ghost(S.Button(left.body, 176, 30))
    forget:SetPoint("BOTTOMLEFT", 0, 0)
    forget:SetPoint("BOTTOMRIGHT", 0, 0)
    forget:SetText(L.FORGET)
    forget:SetScript("OnClick", function() if selected then ns.Forget(selected); selected = nil end end)
    chars = S.List(left.body, 32, makeChar, fillChar)
    chars:SetPoint("TOPLEFT", 0, 0)
    chars:SetPoint("BOTTOMRIGHT", -10, 40)
    local right = S.Card(p1)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", S.GAP, 0)
    right:SetPoint("BOTTOMRIGHT")
    list = S.List(right.body, 40, makeRow, fillRow)
    list:SetPoint("TOPLEFT", 0, 0)
    list:SetPoint("BOTTOMRIGHT", -10, 0)

    -- All characters
    local p2 = page(body)
    local card2 = S.Card(p2)
    card2:SetPoint("TOPLEFT")
    card2:SetPoint("BOTTOMRIGHT")
    gridHead = gridHeader(card2.body)
    gridHead:SetPoint("TOPLEFT")
    gridHead:SetPoint("TOPRIGHT")
    grid = S.List(card2.body, 34, makeGridRow, fillGridRow)
    grid:SetPoint("TOPLEFT", 0, -28)
    grid:SetPoint("BOTTOMRIGHT", -10, 0)

    -- Group
    local p3 = page(body)
    local bar = CreateFrame("Frame", nil, p3)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("TOPRIGHT")
    bar:SetHeight(30)
    raidPills = {}
    local x = 0
    for i, key in ipairs(KEYS) do
        local pill = S.Pill(bar, 70, 30)
        pill:SetText(L["SHORT_" .. key])
        pill:SetPoint("LEFT", x, 0)
        pill:SetScript("OnClick", function() groupRaid = key; ns.Refresh() end)
        raidPills[i] = pill
        x = x + 70 + 6
    end
    tellBtn = S.FitButton(bar, L.TELL_GROUP, 30, 90)
    tellBtn:SetPoint("RIGHT")
    tellBtn:SetScript("OnClick", function() ns.TellGroup(groupRaid) end)
    askBtn = S.FitButton(bar, L.ASK_GUILD, 30, 90)
    askBtn:SetPoint("RIGHT", tellBtn, "LEFT", -8, 0)
    askBtn:SetScript("OnClick", function() ns.AskGuild() end)
    local card3 = S.Card(p3)
    card3:SetPoint("TOPLEFT", 0, -30 - S.GAP)
    card3:SetPoint("BOTTOMRIGHT")
    groupHead = gridHeader(card3.body)
    groupHead:SetPoint("TOPLEFT")
    groupHead:SetPoint("TOPRIGHT")
    groupList = S.List(card3.body, 34, makeGridRow, fillGridRow)
    groupList:SetPoint("TOPLEFT", 0, -28)
    groupList:SetPoint("BOTTOMRIGHT", -10, 0)

    -- Settings
    local p4 = page(body)
    local rows = {}
    for _, o in ipairs({ { "groupMsg", L.OPT_GROUP, L.OPT_GROUP_D }, { "tooltip", L.OPT_TOOLTIP, L.OPT_TOOLTIP_D },
                         { "announce", L.OPT_ANNOUNCE, L.OPT_ANNOUNCE_D }, { "onlyAvail", L.OPT_AVAIL, L.OPT_AVAIL_D },
                         { "hideEmpty", L.OPT_EMPTY, L.OPT_EMPTY_D } }) do
        local key = o[1]
        rows[#rows + 1] = { o[2], o[3], function() return ns.Get(key) end, function(v) ns.Set(key, v) end,
                            icon = ns.OPT_ICON[key] }
    end
    local st = S.Stack(p4)
    local sc, sh = S.SettingsCard(p4, nil, rows)
    for i, row in ipairs(sc.rows) do switchRows[i] = { row = row, get = rows[i][3] } end
    st:Add(sc, sh)
    local ex = S.Card(p4, L.EXPORT, L.EXPORT_HINT)
    st:Add(ex, 130)
    exportBox = S.Memo(ex.body, 760, 70)
    exportBox:SetPoint("TOPLEFT")
    exportBox:SetPoint("TOPRIGHT")

    tabs.frame:SetPoint("TOPLEFT")
    pages[1]:Show()
    frame:SetScript("OnShow", function() ns.Scan() end)
end

function ns.Toggle()
    S.ToggleWindow(ns.Window())
end

-- The window, for the hub (/gulli) to show inside it.
function ns.Window()
    if not frame then build() end
    return frame
end
