-- Three tabs. Characters: the list on the left, the chosen one's card and what waits for it.
-- Overview: every character in one table, sorted by a click on a column head, with the money
-- per realm. Settings: which tasks to show, their limits and the reminders.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, tabs, filterTabs, pages = nil, nil, nil, {}
local chars, list, info, forget, hide, head, empty, note
local over, overHeads, gold
local selected
local sortCol, sortDesc = "name", false

local ICON = {
    CD = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    TRAINER = "Interface\\Icons\\INV_Misc_Book_09",
    PROF = "Interface\\Icons\\Trade_Tailoring",
    MAIL = "Interface\\Icons\\INV_Letter_15",
    EXPIRE = "Interface\\Icons\\INV_Letter_15",
    RESTED = "Interface\\Icons\\Spell_Nature_Sleep",
    REPAIR = "Interface\\Icons\\Trade_BlackSmithing",
    BAGS = "Interface\\Icons\\INV_Misc_Bag_08",
}
-- Each cooldown shows the icon of what it makes; a new cooldown text key gets one here.
local CD_ICON = {
    CD_TRANSMUTE = "Interface\\Icons\\Trade_Alchemy",
    CD_MOONCLOTH = "Interface\\Icons\\INV_Fabric_Moonrag_01",
}
local function cdIcon(key)
    if key == "CD_SALT" then
        local get = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
        return get and get(15846) -- Salt Shaker
    end
    return CD_ICON[key]
end

local function classColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return c and string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) or ""
end

local function money(copper)
    if GetCoinTextureString then return GetCoinTextureString(copper or 0) end
    local g = math.floor((copper or 0) / 10000)
    local s = math.floor((copper or 0) / 100) % 100
    return g > 0 and (g .. "g " .. s .. "s") or (s .. "s")
end

-- How urgent a task is: what hurts when it waits red, what is ready to use green.
local TONE = { REPAIR = "BAD", BAGS = "BAD", EXPIRE = "BAD", CD = "GOOD", RESTED = "GOOD" }
function ns.TaskColor(key)
    local t = TONE[key]
    return t and S[t] or S.TEXT
end

-- ---------- Characters ----------

local function makeChar(r)
    S.NavRow(r)
    r.line:Hide()
    r.text = S.Text(r, 12)
    r.text:SetPoint("LEFT", 12, 0)
    r.text:SetPoint("RIGHT", -30, 0)
    r.text:SetWordWrap(false)
    r.count = S.Badge(r)
    r.count:SetPoint("RIGHT", -8, 0)
    r.click = CreateFrame("Button", nil, r)
    r.click:SetAllPoints()
    r.click:SetScript("OnClick", function(self) selected = self:GetParent().entry.key; ns.Refresh() end)
end

local function fillChar(r, e)
    r.entry = e
    local name = e.hidden and (S.Hex(S.FAINT) .. e.char.name .. "|r") or (classColor(e.char.class) .. e.char.name .. "|r")
    r.text:SetText(name .. " " .. S.Hex(S.MUTED) .. (e.char.level or "") .. "|r")
    local n = #ns.Tasks(e.char)
    r.count:Set(n > 0 and tostring(n) or nil, S.Accent())
    r:SetSelected(e.key == selected)
end

local function makeRow(r)
    r.icon = S.IconBox(r, 26)
    r.icon:SetPoint("LEFT", 2, 0)
    r.text = S.Text(r, 12)
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 10, 0)
    r.text:SetPoint("RIGHT", -8, 0)
    r.text:SetWordWrap(false)
end

local function fillRow(r, task)
    r.icon:SetIcon(task.cd and cdIcon(task.cd) or ICON[task.key])
    r.text:SetText(task.text)
    r.text:SetTextColor(unpack(ns.TaskColor(task.key)))
end

-- The lines of the character card.
function ns.InfoLines(c, key, now)
    now = now or time()
    local lines = {}
    if not c.maxLevel then
        local full = ns.RestedFullIn(c, now)
        local line = L.RESTED:format(math.floor(ns.RestedNow(c, now) * 100))
        if full and full > 0 then line = line .. ", " .. L.FULL_IN:format(ns.Span(full)) end
        lines[#lines + 1] = line
    end
    lines[#lines + 1] = L.MONEY:format(money(c.money))
    if key ~= ns.CharKey() then lines[#lines + 1] = L.SEEN:format(ns.Span(now - c.t)) end
    local nextCd = ns.NextReady(c, now)
    if nextCd then lines[#lines + 1] = L.NEXT_CD:format(ns.Span(nextCd - now)) end
    if c.hearth or c.bind then
        local h = (not c.hearth or c.hearth <= now) and L.READY or ns.Span(c.hearth - now)
        lines[#lines + 1] = L.HEARTH:format(h, c.bind or "?")
    end
    if c.mailUntil and c.mailUntil > now then
        lines[#lines + 1] = L.MAIL_LINE:format(c.mailItems or 0, ns.Span(c.mailUntil - now))
    end
    if (c.cod or 0) > 0 then lines[#lines + 1] = L.COD_LINE:format(c.cod) end
    local profs = {}
    for _, p in ipairs(c.profs or {}) do profs[#profs + 1] = p.name .. " " .. p.skill .. "/" .. p.cap end
    if #profs > 0 then lines[#lines + 1] = L.PROFS:format(table.concat(profs, ", ")) end
    local locks = {}
    for _, l in ipairs(c.lockouts or {}) do
        if l.til > now then locks[#locks + 1] = l.name .. " " .. ns.Span(l.til - now) end
    end
    if #locks > 0 then lines[#lines + 1] = L.LOCKS:format(table.concat(locks, ", ")) end
    if c.played then lines[#lines + 1] = L.PLAYED:format(ns.Span(c.played)) end
    return lines
end

local function refreshChars()
    local all = ns.Chars(true)
    if not selected or not ns.db.chars[selected] then selected = all[1] and all[1].key end
    chars:SetData(all)
    local c = selected and ns.db.chars[selected]
    local tasks = c and ns.Tasks(c) or {}
    list:SetData(tasks)
    if c then
        info:SetText(table.concat(ns.InfoLines(c, selected), "\n"))
        head:SetText(classColor(c.class) .. c.name .. "|r  " .. S.Hex(S.MUTED) .. (c.level or "") ..
            (c.realm and ("  " .. c.realm) or "") .. "|r")
        if not note:HasFocus() then note:SetText(c.note or "") end
    else
        info:SetText("")
        head:SetText("")
        note:SetText("")
    end
    note:SetShown(c ~= nil)
    empty:SetShown(c ~= nil and #tasks == 0)
    empty:Set(L.NOTHING)
    local other = selected ~= nil and selected ~= ns.CharKey()
    forget:SetEnabled(other)
    hide:SetEnabled(other)
    hide:SetText(ns.db.hidden[selected or ""] and L.SHOW_CHAR or L.HIDE_CHAR)
end

local function buildChars(page)
    local left = S.Card(page)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(200)
    forget = S.Ghost(S.Button(left.body, 1, 30))
    forget:SetPoint("BOTTOMLEFT")
    forget:SetPoint("BOTTOMRIGHT")
    forget:SetText(L.FORGET)
    forget:SetScript("OnClick", function() if selected then ns.Forget(selected); selected = nil end end)
    hide = S.Ghost(S.Button(left.body, 1, 30))
    hide:SetPoint("BOTTOMLEFT", forget, "TOPLEFT", 0, 6)
    hide:SetPoint("BOTTOMRIGHT", forget, "TOPRIGHT", 0, 6)
    hide:SetScript("OnClick", function()
        if selected then ns.SetHidden(selected, not ns.db.hidden[selected]) end
    end)
    chars = S.List(left.body, 32, makeChar, fillChar)
    chars:SetPoint("TOPLEFT")
    chars:SetPoint("BOTTOMRIGHT", -10, 76)

    local top = S.Card(page)
    top:SetPoint("TOPLEFT", left, "TOPRIGHT", S.GAP, 0)
    top:SetPoint("TOPRIGHT")
    top:SetHeight(214)
    head = S.Text(top.body, 15)
    head:SetPoint("TOPLEFT")
    head:SetPoint("TOPRIGHT", -230, 0)
    head:SetWordWrap(false)
    note = S.Edit(top.body, 220, 28)
    note:SetPoint("TOPRIGHT", 0, 4)
    note:SetJustifyH("LEFT")
    S.Placeholder(note, L.NOTE_HINT)
    local function save(self) if selected then ns.SetNote(selected, self:GetText()) end; self:ClearFocus() end
    note:SetScript("OnEnterPressed", save)
    note:SetScript("OnEditFocusLost", function(self) S.SetBorder(self, S.EDGE); if selected then ns.SetNote(selected, self:GetText()) end end)
    info = S.Text(top.body, 12, S.MUTED)
    info:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -12)
    info:SetPoint("RIGHT")
    info:SetJustifyV("TOP")
    info:SetSpacing(4)

    local right = S.Card(page)
    right:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -S.GAP)
    right:SetPoint("BOTTOMRIGHT")
    list = S.List(right.body, 34, makeRow, fillRow)
    list:SetPoint("TOPLEFT")
    list:SetPoint("BOTTOMRIGHT", -10, 0)
    empty = S.Empty(right.body)
end

-- ---------- Overview ----------

-- Columns: key in ns.COLUMNS, header text key, width (the name takes the room left).
local COLS = {
    { "name", "COL_NAME" }, { "level", "COL_LEVEL", 44 }, { "rested", "COL_RESTED", 64 },
    { "money", "COL_MONEY", 130 }, { "durability", "COL_DURABILITY", 64 }, { "free", "COL_FREE", 54 },
    { "cd", "COL_CD", 80 }, { "tasks", "COL_TASKS", 54 },
}
local COL_GAP = 8
local function colRight(k)
    local x = 6
    for j = #COLS, k + 1, -1 do x = x + COLS[j][3] + COL_GAP end
    return x
end
local function place(fs, parent, k)
    fs:ClearAllPoints()
    if k == 1 then
        fs:SetPoint("LEFT", parent, "LEFT", 6, 0)
        fs:SetPoint("RIGHT", parent, "RIGHT", -(colRight(1) + COL_GAP), 0)
        fs:SetJustifyH("LEFT")
    else
        fs:SetPoint("RIGHT", parent, "RIGHT", -colRight(k), 0)
        fs:SetWidth(COLS[k][3])
        fs:SetJustifyH("RIGHT")
    end
end

local function makeOver(r)
    r.cells = {}
    for k = 1, #COLS do
        local fs = S.Text(r, 12)
        fs:SetWordWrap(false)
        place(fs, r, k)
        r.cells[k] = fs
    end
    r.click = CreateFrame("Button", nil, r)
    r.click:SetAllPoints()
    r.click:SetScript("OnClick", function(self)
        selected = self:GetParent().entry.key
        tabs:Select(1)
    end)
end

local function fillOver(r, e)
    r.entry = e
    local c, cell = e.char, r.cells
    local now = time()
    cell[1]:SetText(classColor(c.class) .. e.name .. "|r" .. (c.note and (" " .. S.Hex(S.MUTED) .. c.note .. "|r") or ""))
    cell[2]:SetText(tostring(e.level))
    cell[3]:SetText(e.rested < 0 and "-" or (math.floor(e.rested * 100) .. "%"))
    local rc = e.rested >= ns.RESTED_MAX and S.GOOD or S.TEXT
    cell[3]:SetTextColor(rc[1], rc[2], rc[3], 1)
    cell[4]:SetText(money(e.money))
    cell[5]:SetText(e.durability .. "%")
    local dc = e.durability < ns.Pref("repairAt") and S.BAD or S.TEXT
    cell[5]:SetTextColor(dc[1], dc[2], dc[3], 1)
    cell[6]:SetText(tostring(e.free))
    local fc = e.free <= ns.Pref("bagsAt") and S.BAD or S.TEXT
    cell[6]:SetTextColor(fc[1], fc[2], fc[3], 1)
    cell[7]:SetText(e.cd == 0 and L.READY or e.cd == math.huge and "-" or ns.Span(e.cd - now))
    local cc = e.cd == 0 and S.GOOD or S.TEXT
    cell[7]:SetTextColor(cc[1], cc[2], cc[3], 1)
    cell[8]:SetText(tostring(e.tasks))
    local tc = e.tasks > 0 and S.Accent() or S.MUTED
    cell[8]:SetTextColor(tc[1], tc[2], tc[3], 1)
end

local function refreshOver()
    for k, h in ipairs(overHeads) do
        local mark = COLS[k][1] == sortCol and (sortDesc and " v" or " ^") or ""
        h.text:SetText(L[COLS[k][2]] .. mark)
    end
    over:SetData(ns.Overview(sortCol, sortDesc))
    local parts = {}
    for _, g in ipairs(ns.RealmGold()) do parts[#parts + 1] = g.realm .. ": " .. money(g.money) end
    gold:SetText(L.GOLD:format(table.concat(parts, "   ")))
end

local function buildOver(page)
    local card = S.Card(page)
    card:SetPoint("TOPLEFT")
    card:SetPoint("BOTTOMRIGHT")
    overHeads = {}
    for k, col in ipairs(COLS) do
        local h = CreateFrame("Button", nil, card.body)
        h:SetHeight(18)
        h.text = S.Text(h, 10, S.MUTED)
        h.text:SetWordWrap(false)
        if k == 1 then
            h:SetPoint("TOPLEFT", 6, 0)
            h:SetPoint("TOPRIGHT", -(colRight(1) + COL_GAP + 10), 0)
            h.text:SetPoint("LEFT"); h.text:SetPoint("RIGHT"); h.text:SetJustifyH("LEFT")
        else
            h:SetPoint("TOPRIGHT", -(colRight(k) + 10), 0)
            h:SetWidth(col[3])
            h.text:SetPoint("LEFT"); h.text:SetPoint("RIGHT"); h.text:SetJustifyH("RIGHT")
        end
        h:SetScript("OnClick", function()
            -- A second click on the same column turns the order.
            if sortCol == col[1] then sortDesc = not sortDesc
            else sortCol, sortDesc = col[1], col[1] ~= "name" end
            ns.Refresh()
        end)
        overHeads[k] = h
    end
    gold = S.Text(card.body, 12, S.MUTED)
    gold:SetPoint("BOTTOMLEFT")
    gold:SetPoint("BOTTOMRIGHT")
    gold:SetJustifyH("LEFT")
    gold:SetWordWrap(false)
    over = S.List(card.body, 32, makeOver, fillOver)
    over:SetPoint("TOPLEFT", 0, -22)
    over:SetPoint("BOTTOMRIGHT", -10, 26)
end

-- ---------- Settings ----------

local function buildSettings(page)
    local taskRows = {}
    for _, k in ipairs(ns.TASKS) do
        local o = ns.Option(k, true)
        taskRows[#taskRows + 1] = { o.label, nil, o.get, o.set, icon = o.icon }
    end
    local left, h1 = S.SettingsCard(page, L.SEC_TASKS, taskRows)
    left:SetPoint("TOPLEFT")
    left:SetPoint("RIGHT", page, "CENTER", -S.GAP / 2, 0)
    left:SetHeight(h1)

    local function stepper(key, step, min, max, fmt)
        return S.Stepper(page, function() return ns.Pref(key) end, function(v) ns.SetPref(key, v) end,
                         step, min, max, fmt, 120)
    end
    local login, alerts = ns.Option("login"), ns.Option("alerts")
    local rows = {
        { login.label, L.TIP_LOGIN, login.get, login.set, icon = login.icon },
        { alerts.label, L.TIP_ALERTS, alerts.get, alerts.set, icon = alerts.icon },
        { L.OPT_REPAIR_AT, nil, control = stepper("repairAt", 10, 10, 90, function(v) return v .. "%" end),
          icon = ICON.REPAIR },
        { L.OPT_BAGS_AT, nil, control = stepper("bagsAt", 1, 0, 10), icon = ICON.BAGS },
        { L.OPT_MAIL_DAYS, nil, control = stepper("mailDays", 1, 1, 30, function(v) return L.DAYS:format(v) end),
          icon = ICON.EXPIRE },
    }
    local right, h2 = S.SettingsCard(page, L.SEC_REMIND, rows)
    right:SetPoint("TOPLEFT", page, "TOP", S.GAP / 2, 0)
    right:SetPoint("RIGHT")
    right:SetHeight(h2)
    pages.settingsCards = { left, right }
end

local function refreshSettings()
    for _, card in ipairs(pages.settingsCards) do
        for _, r in ipairs(card.rows) do
            if r.switch and r:GetScript("OnShow") then r:GetScript("OnShow")(r) end
            if r.control and r.control.Refresh then r.control:Refresh() end
        end
    end
end

-- ---------- Window ----------

function ns.Refresh()
    if not frame or not frame:IsShown() then return end
    local t = tabs.selected
    for i, p in ipairs(pages) do p:SetShown(i == t) end
    filterTabs.frame:SetShown(t ~= 3)
    if t == 1 then refreshChars() elseif t == 2 then refreshOver() else refreshSettings() end
end

local function build()
    frame = S.Window("GulliChoresFrame", L.TITLE, S.WIDE_W, S.DOCK_H)
    local body = frame.body
    tabs = S.Tabs(body, { L.TAB_CHARS, L.TAB_OVERVIEW, L.TAB_SETTINGS }, nil, function() ns.Refresh() end)
    local labels = {}
    for i, k in ipairs(ns.FILTERS) do labels[i] = L["FILTER_" .. k:upper()] end
    filterTabs = S.Tabs(body, labels, nil, function(i) ns.SetPref("filter", ns.FILTERS[i]) end)
    filterTabs.frame:ClearAllPoints()
    filterTabs.frame:SetPoint("TOPRIGHT")
    for i = 1, 3 do
        local p = CreateFrame("Frame", nil, body)
        p:SetPoint("TOPLEFT", 0, -(30 + S.GAP))
        p:SetPoint("BOTTOMRIGHT")
        pages[i] = p
    end
    buildChars(pages[1])
    buildOver(pages[2])
    buildSettings(pages[3])
    frame:SetScript("OnShow", function()
        for i, k in ipairs(ns.FILTERS) do if k == ns.Pref("filter") then filterTabs:Select(i, true) end end
        ns.Snapshot(); ns.Refresh()
    end)
end

-- For the tests and the preview.
function ns.Tabs() return tabs end
function ns.Select(key) selected = key; ns.Refresh() end
function ns.SortBy(col) overHeads[(function() for k, c in ipairs(COLS) do if c[1] == col then return k end end end)()]:GetScript("OnClick")() end

function ns.Toggle()
    S.ToggleWindow(ns.Window())
end

-- The window, for the hub (/gulli) to show inside it.
function ns.Window()
    if not frame then build() end
    return frame
end
