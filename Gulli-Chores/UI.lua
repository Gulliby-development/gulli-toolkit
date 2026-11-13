-- Three tabs. Characters: the list on the left, the chosen one's card and what waits for it.
-- Overview: every character in one table, sorted by a click on a column head, with the money
-- per realm. Settings: which tasks to show, their limits and the reminders.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, tabs, filterTabs, pages = nil, nil, nil, {}
local chars, list, forget, hide, head, empty, note
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

-- The facts of the character card: four tiles, the professions and the lines that only some
-- characters have. Each tile is { value, color, sub, frac }.
local HEARTH_ID = 6948
local function itemIcon(id)
    local get = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
    return get and get(id)
end
local TILE_ICON = {
    rested = "Interface\\Icons\\Spell_Nature_Sleep",
    money = "Interface\\Icons\\INV_Misc_Coin_01",
    played = "Interface\\Icons\\INV_Misc_PocketWatch_01",
}

local function realmMoney(c)
    for _, g in ipairs(ns.RealmGold()) do
        if g.realm == c.realm then return g.money end
    end
end

function ns.CardInfo(c, key, now)
    now = now or time()
    local info = { extra = {}, profs = {} }
    if c.maxLevel then
        info.rested = { L.MAX_LEVEL, S.MUTED, "" }
    else
        local r = ns.RestedNow(c, now)
        local full = ns.RestedFullIn(c, now)
        local sub = (full and full > 0) and L.FULL_IN:format(ns.Span(full)) or L.RESTED_FULL
        local tone = ns.Tone("rested", r)
        info.rested = { math.floor(r * 100) .. "%", tone and S[tone] or S.TEXT, sub, r / ns.RESTED_MAX }
    end
    local total = realmMoney(c)
    info.money = { S.MoneyText(c.money), S.TEXT,
                   -- The realm's total in whole gold, so it fits under the tile's value.
                   (total and total ~= (c.money or 0)) and L.REALM_MONEY:format(S.MoneyText(total >= 10000 and total - total % 10000 or total))
                   or (c.realm or "") }
    if c.hearth or c.bind then
        local ready = not c.hearth or c.hearth <= now
        info.hearth = { ready and L.READY_UP or ns.Span(c.hearth - now), ready and S.GOOD or S.TEXT, c.bind or "?" }
    else
        info.hearth = { "-", S.MUTED, "" }
    end
    local seen = key == ns.CharKey() and L.SEEN_NOW or L.SEEN_AGO:format(ns.Span(now - (c.t or now)))
    info.played = { c.played and ns.Span(c.played) or "-", c.played and S.TEXT or S.MUTED, seen }
    local nextCd = ns.NextReady(c, now)
    if nextCd then info.extra[#info.extra + 1] = L.NEXT_CD:format(ns.Span(nextCd - now)) end
    if c.mailUntil and c.mailUntil > now then
        info.extra[#info.extra + 1] = L.MAIL_LINE:format(c.mailItems or 0, ns.Span(c.mailUntil - now))
    end
    if (c.cod or 0) > 0 then info.extra[#info.extra + 1] = L.COD_LINE:format(c.cod) end
    local locks = {}
    for _, l in ipairs(c.lockouts or {}) do
        if l.til > now then locks[#locks + 1] = l.name .. " " .. ns.Span(l.til - now) end
    end
    if #locks > 0 then info.extra[#info.extra + 1] = L.LOCKS:format(table.concat(locks, ", ")) end
    for _, p in ipairs(c.profs or {}) do
        local cap = p.cap or 0
        -- A rank that is full waits for the trainer: yellow, like the task.
        local full = cap > 0 and cap < 300 and (p.skill or 0) >= cap
        info.profs[#info.profs + 1] = { name = p.name, icon = p.icon, skill = p.skill or 0, cap = cap,
            frac = cap > 0 and (p.skill or 0) / cap or 0, color = full and S.WARN or S.Accent(), full = full }
    end
    return info
end

local tiles, extra, top, profCard, profRows, taskCard
-- The task list takes what is left under the professions, or under the card without them.
local function placeTasks(withProfs)
    taskCard:ClearAllPoints()
    taskCard:SetPoint("TOPLEFT", withProfs and profCard or top, "BOTTOMLEFT", 0, -S.GAP)
    taskCard:SetPoint("BOTTOMRIGHT")
end
local PROF_MAX, PROF_H = 6, 26
local TILE_H, HEAD_H = 74, 28

local function fillCard(c)
    local info = ns.CardInfo(c, selected)
    tiles.rested:Set(info.rested[1], info.rested[2], info.rested[3], info.rested[4], { 0.36, 0.55, 0.88, 1 })
    tiles.money:Set(info.money[1], nil, info.money[3])
    tiles.hearth.icon:SetIcon(itemIcon(HEARTH_ID))
    tiles.hearth:Set(info.hearth[1], info.hearth[2], info.hearth[3])
    tiles.played:Set(info.played[1], info.played[2], info.played[3])
    extra:SetText(table.concat(info.extra, "\n"))
    local lines = #info.extra
    top:Fit(HEAD_H + 10 + TILE_H + (lines > 0 and (8 + lines * 16) or 0))
    local n = math.min(#info.profs, PROF_MAX)
    for i = 1, PROF_MAX do
        local r, p = profRows[i], info.profs[i]
        r:SetShown(i <= n)
        if p and i <= n then
            r.icon:SetIcon(p.icon)
            r.name:SetText(p.name)
            r.bar:Set(p.frac, p.color)
            r.value:SetText(p.full and (S.Hex(S.WARN) .. p.skill .. "/" .. p.cap .. "|r")
                or (p.skill .. S.Hex(S.MUTED) .. "/" .. p.cap .. "|r"))
        end
    end
    profCard:SetShown(n > 0)
    if n > 0 then profCard:Fit(n * PROF_H) end
    placeTasks(n > 0)
end

local function refreshChars()
    local all = ns.Chars(true)
    if not selected or not ns.db.chars[selected] then selected = all[1] and all[1].key end
    chars:SetData(all)
    local c = selected and ns.db.chars[selected]
    local tasks = c and ns.Tasks(c) or {}
    list:SetData(tasks)
    if c then
        local lc = S.LevelColor(c.level, UnitLevel and UnitLevel("player"))
        local fac = c.faction == "Horde" and "|cffe0503c" or c.faction == "Alliance" and "|cff4a8ef0" or nil
        head:SetText(classColor(c.class) .. c.name .. "|r  " .. S.Hex(lc) .. (c.level or "") .. "|r" ..
            (c.realm and ("   " .. S.Hex(S.MUTED) .. c.realm .. "|r") or "") ..
            (fac and c.faction and ("   " .. fac .. (L["FACTION_" .. c.faction] or c.faction) .. "|r") or ""))
        if not note:HasFocus() then note:SetText(c.note or "") end
        fillCard(c)
    else
        head:SetText("")
        note:SetText("")
        extra:SetText("")
        profCard:Hide()
        placeTasks(false)
    end
    for _, t in pairs(tiles) do t:SetShown(c ~= nil) end
    note:SetShown(c ~= nil)
    empty:SetShown(c ~= nil and #tasks == 0)
    empty:Set(L.NOTHING)
    local other = selected ~= nil and selected ~= ns.CharKey()
    forget:SetEnabled(other)
    hide:SetEnabled(other)
    hide:SetText(ns.db.hidden[selected or ""] and L.SHOW_CHAR or L.HIDE_CHAR)
end

local function makeProf(parent, i)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(PROF_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * PROF_H)
    r:SetPoint("RIGHT")
    r.icon = S.IconBox(r, 22)
    r.icon:SetPoint("LEFT")
    r.name = S.Text(r, 12)
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 10, 0)
    r.name:SetWidth(110)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.value = S.Text(r, 12)
    r.value:SetPoint("RIGHT")
    r.value:SetWidth(70)
    r.value:SetJustifyH("RIGHT")
    r.bar = S.Progress(r, 6)
    r.bar:SetPoint("LEFT", r.name, "RIGHT", 8, 0)
    r.bar:SetPoint("RIGHT", r.value, "LEFT", -10, 0)
    return r
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

    top = S.Card(page)
    top:SetPoint("TOPLEFT", left, "TOPRIGHT", S.GAP, 0)
    top:SetPoint("TOPRIGHT")
    top:Fit(HEAD_H + 10 + TILE_H)
    head = S.Text(top.body, 16)
    head:SetPoint("TOPLEFT", 0, -4)
    head:SetPoint("TOPRIGHT", -230, -4)
    head:SetWordWrap(false)
    note = S.Edit(top.body, 220, 28)
    note:SetPoint("TOPRIGHT", 0, 0)
    note:SetJustifyH("LEFT")
    S.Placeholder(note, L.NOTE_HINT)
    local function save(self) if selected then ns.SetNote(selected, self:GetText()) end; self:ClearFocus() end
    note:SetScript("OnEnterPressed", save)
    note:SetScript("OnEditFocusLost", function(self) S.SetBorder(self, S.EDGE); if selected then ns.SetNote(selected, self:GetText()) end end)
    local row = CreateFrame("Frame", nil, top.body)
    row:SetPoint("TOPLEFT", 0, -(HEAD_H + 10))
    row:SetPoint("TOPRIGHT", 0, -(HEAD_H + 10))
    row:SetHeight(TILE_H)
    tiles = {
        rested = S.InfoTile(row, L.TILE_RESTED, TILE_ICON.rested),
        money = S.InfoTile(row, L.TILE_MONEY, TILE_ICON.money),
        hearth = S.InfoTile(row, L.TILE_HEARTH, itemIcon(HEARTH_ID)),
        played = S.InfoTile(row, L.TILE_PLAYED, TILE_ICON.played),
    }
    local order = { tiles.rested, tiles.money, tiles.hearth, tiles.played }
    local function layout()
        local w = tonumber(row:GetWidth()) or 0
        if w <= 0 then return end
        local tw = math.floor((w - 3 * 8) / 4)
        for i, t in ipairs(order) do
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", (i - 1) * (tw + 8), 0)
            t:SetSize(tw, TILE_H)
        end
    end
    row:SetScript("OnSizeChanged", layout)
    for i, t in ipairs(order) do t:SetPoint("TOPLEFT", (i - 1) * 145, 0); t:SetSize(137, TILE_H) end
    layout()
    extra = S.Text(top.body, 12, S.MUTED)
    extra:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 0, -8)
    extra:SetPoint("RIGHT")
    extra:SetJustifyH("LEFT")
    extra:SetJustifyV("TOP")
    extra:SetSpacing(3)

    profCard = S.Card(page, L.SEC_PROFS)
    profCard:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -S.GAP)
    profCard:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT", 0, -S.GAP)
    profRows = {}
    for i = 1, PROF_MAX do profRows[i] = makeProf(profCard.body, i) end
    profCard:Fit(PROF_H)

    taskCard = S.Card(page)
    placeTasks(true)
    local right = taskCard
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

local function tint(fs, tone)
    local c = tone and S[tone] or S.TEXT
    fs:SetTextColor(c[1], c[2], c[3], 1)
end

local function fillOver(r, e)
    r.entry = e
    local c, cell = e.char, r.cells
    local now = time()
    cell[1]:SetText(classColor(c.class) .. e.name .. "|r" .. (c.note and (" " .. S.Hex(S.MUTED) .. c.note .. "|r") or ""))
    cell[2]:SetText(tostring(e.level))
    local lc = S.LevelColor(e.level, UnitLevel and UnitLevel("player"))
    cell[2]:SetTextColor(lc[1], lc[2], lc[3], 1)
    cell[3]:SetText(e.rested < 0 and "-" or (math.floor(e.rested * 100) .. "%"))
    tint(cell[3], e.rested < 0 and "MUTED" or ns.Tone("rested", e.rested))
    cell[4]:SetText(S.MoneyText(e.money))
    cell[5]:SetText(e.durability .. "%")
    tint(cell[5], ns.Tone("durability", e.durability))
    cell[6]:SetText(tostring(e.free))
    tint(cell[6], ns.Tone("free", e.free))
    cell[7]:SetText(e.cd == 0 and L.READY_UP or e.cd == math.huge and "-" or ns.Span(e.cd - now))
    tint(cell[7], e.cd == math.huge and "MUTED" or ns.Tone("cd", e.cd))
    cell[8]:SetText(tostring(e.tasks))
    tint(cell[8], e.tasks == 0 and "MUTED" or ns.Tone("tasks", e.tasks))
end

local function refreshOver()
    for k, h in ipairs(overHeads) do
        local mark = COLS[k][1] == sortCol and (sortDesc and " v" or " ^") or ""
        h.text:SetText(L[COLS[k][2]] .. mark)
    end
    over:SetData(ns.Overview(sortCol, sortDesc))
    local parts = {}
    for _, g in ipairs(ns.RealmGold()) do parts[#parts + 1] = g.realm .. ": " .. S.MoneyText(g.money) end
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
    tabs = S.Tabs(body, { L.TAB_CHARS, L.TAB_OVERVIEW, L.TAB_SETTINGS }, nil, function() ns.Refresh() end, nil, { S.TAB.char, S.TAB.overview, S.TAB.settings })
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
