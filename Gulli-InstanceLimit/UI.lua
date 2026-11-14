-- The window has two pages. Status: entries left this hour and today (~ while the limit is
-- our guess), which limit blocks, the group, and the entries of the last hour or day by
-- character, with Reset in the footer. Settings: limits, alerts, the group and the counter.
-- The counter is a small badge on screen that opens the window.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, tabs, statusPage, settingsPage, big, nextLine, groupLine, list, empty, entries, span
local resetBtn, footer, badge
local TIME_ICON = "Interface\\Icons\\Spell_Nature_TimeStop"
local page, range = 1, "HOUR"
local I = "Interface\\Icons\\"

local function ago(t)
    return L.AGO:format(ns.Clock(time() - t))
end

---- The entry list -------------------------------------------------------------

local function makeRow(r)
    r.name = S.Text(r, 12)
    r.name:SetPoint("TOPLEFT", 2, -5)
    r.name:SetPoint("RIGHT", -110, 0)
    r.name:SetWordWrap(false)
    r.run = S.Text(r, 11, S.MUTED)
    r.run:SetPoint("BOTTOMLEFT", 2, 5)
    r.run:SetPoint("RIGHT", -110, 0)
    r.run:SetWordWrap(false)
    r.when = S.Text(r, 11, S.MUTED)
    r.when:SetPoint("RIGHT", -2, 0)
    r.when:SetJustifyH("RIGHT")
    r.head = S.Text(r, 12)
    r.head:SetPoint("LEFT", 6, 0)
end

local function classHex(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if not c then return S.Hex(S.TEXT) end
    return string.format("|cff%02x%02x%02x", math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255))
end

local function fillRow(r, e)
    local header = e.header
    r.head:SetShown(header)
    r.name:SetShown(not header); r.run:SetShown(not header); r.when:SetShown(not header)
    if header then
        S.Fill(r, S.RAISED)
        r.head:SetText(classHex(e.class) .. (e.char or "?") .. "|r  " .. S.Hex(S.FAINT) .. "(" .. e.count .. ")|r")
        return
    end
    S.Fill(r, S.CLEAR)
    r.name:SetText(e.name or "?")
    r.run:SetText(e.out and ns.RunText(e) or (S.Hex(S.GOOD) .. L.INSIDE .. "|r"))
    r.when:SetText(ago(e.t))
end

-- The entries of the last hour or day, grouped by character (the player's first).
function ns.ListItems(which, now)
    now = now or time()
    local span = which == "DAY" and ns.DAY or ns.HOUR
    local byChar, chars = {}, {}
    for _, e in ipairs(ns.db.entries) do
        if now - ns.When(e, now) < span then
            local c = e.char or "?"
            if not byChar[c] then byChar[c] = {}; chars[#chars + 1] = c end
            table.insert(byChar[c], e)
        end
    end
    local me = UnitName("player")
    table.sort(chars, function(a, b)
        if a == me then return b ~= me end
        if b == me then return false end
        return a < b
    end)
    local out = {}
    for _, c in ipairs(chars) do
        local list = byChar[c]
        table.sort(list, function(a, b) return a.t > b.t end)
        if #chars > 1 then out[#out + 1] = { header = true, char = c, class = list[1].class, count = #list } end
        for _, e in ipairs(list) do out[#out + 1] = e end
    end
    return out
end

---- The badge -------------------------------------------------------------------

-- Whether the counter shows: always, never, or in a group, in a dungeon or when entries are short.
local function unlocked() return ns.moving or ns.db.badgeLocked == false end

function ns.BadgeShown(s)
    if unlocked() then return true end
    local mode = ns.db.badgeMode
    if mode == "HIDDEN" then return false end
    if mode == "GROUP" then
        return (IsInGroup and IsInGroup()) or ns.inside ~= nil or s.left <= 1
    end
    return true
end

local function updateBadge(s)
    if not badge then return end
    badge:SetShown(ns.BadgeShown(s))
    badge:SetScale((ns.db.badgeScale or 100) / 100)
    badge:SetAlpha((ns.db.badgeAlpha or 100) / 100)
    local color = s.left == 0 and S.BAD or (s.left == 1 and S.WARN or nil)
    badge:Set(TIME_ICON, s.leftHour .. "/" .. ns.LimitText(ns.db.limit), color, s.leftHour, ns.db.limit,
        s.wait > 0 and ns.Clock(s.wait) or nil)
    badge:SetMoving(unlocked() and not InCombatLockdown())
end

-- "A dungeon entry is free again" as a Gulli HUD notice.
function ns.ShowFree(s)
    s = s or ns.Status()
    return S.Toast({ key = "free", icon = TIME_ICON, kind = "good", title = L.FREE,
        text = L.LEFT_HOUR:format(s.leftHour, ns.db.limit), seconds = 12 })
end

function ns.Refresh()
    local s = ns.Status()
    updateBadge(s)
    if not frame or not frame:IsShown() then return end
    statusPage:SetShown(page == 1)
    settingsPage:SetShown(page == 2)
    footer:SetShown(page == 1)
    local function tone(left) return left == 0 and S.BAD or (left == 1 and S.WARN or S.GOOD) end
    big.tiles[1]:Set(s.leftHour .. " / " .. ns.LimitText(ns.db.limit), tone(s.leftHour))
    big.tiles[2]:Set(s.leftDay .. " / " .. ns.LimitText(ns.db.dayLimit), tone(s.leftDay))
    if s.by then
        nextLine:SetText(S.Hex(S.BAD) .. (s.by == "DAY" and L.BLOCK_DAY or L.BLOCK_HOUR):format(ns.Clock(s.wait)) .. "|r")
    else
        nextLine:SetText(ns.db.confirmed and L.ALL_FREE or (L.ALL_FREE .. " " .. S.Hex(S.FAINT) .. L.ESTIMATE .. "|r"))
    end
    local low = ns.GroupLow()
    if low then
        groupLine:SetText(L.GROUP_LOW:format(low.name, low.left) ..
            (low.wait > 0 and (" " .. L.NEXT_FREE:format(ns.Clock(low.wait))) or ""))
    else
        groupLine:SetText(S.Hex(S.FAINT) .. L.GROUP_NONE .. "|r")
    end
    local items = ns.ListItems(range)
    list:SetData(items)
    empty:SetShown(#items == 0)
    empty:Set(range == "DAY" and L.NONE_DAY or L.NONE)
    resetBtn:SetEnabled(ns.CanReset())
    if ns.insideNames then
        footer:SetStatus(L.STILL_INSIDE:format(table.concat(ns.insideNames, ", ")), S.WARN)
    else
        footer:SetStatus(L.RESET_TIP)
    end
end

---- Settings --------------------------------------------------------------------

local function numberEdit(parent, get, set)
    local e = S.Edit(parent, 52, 28)
    e:SetNumeric(true)
    e:SetMaxLetters(3)
    e:SetText(tostring(get()))
    e:SetScript("OnShow", function(self) self:SetText(tostring(get())) end)
    local function apply(self)
        local n = tonumber(self:GetText())
        if n and n > 0 then set(n) end
        self:SetText(tostring(get()))
        self:ClearFocus()
        ns.Refresh()
    end
    e:SetScript("OnEnterPressed", apply)
    e:SetScript("OnEditFocusLost", function(self) S.SetBorder(self, S.EDGE); apply(self) end)
    return e
end

local function switch(key, label, desc, icon)
    return { label, desc, function() return ns.db[key] end, function(v) ns.db[key] = v; ns.Refresh() end, icon = icon }
end

local function buildSettings(body, width)
    -- A holder, so hiding the page also hides the scroll bar (it hangs off the scroll's parent).
    settingsPage = CreateFrame("Frame", nil, body)
    settingsPage:SetPoint("TOPLEFT", 0, -30 - S.GAP)
    settingsPage:SetPoint("BOTTOMRIGHT")
    local scroll = S.Scroll(settingsPage)
    scroll:SetPoint("TOPLEFT")
    scroll:SetPoint("BOTTOMRIGHT", -12, 0)
    local c = scroll.child
    c:SetWidth(width - 12)
    local st = S.Stack(c)

    local defaults = S.Button(c, 90, 28)
    defaults:SetText(L.DEFAULTS)
    defaults:SetScript("OnClick", function() ns.DefaultLimits() end)
    local limits, h1 = S.SettingsCard(c, L.SEC_LIMITS, {
        { L.ROW_LIMIT, nil, control = numberEdit(c, function() return ns.db.limit end,
            function(n) ns.db.limit = n; ns.db.confirmed = false end), icon = I .. "INV_Misc_PocketWatch_02" },
        { L.ROW_DAY, nil, control = numberEdit(c, function() return ns.db.dayLimit end,
            function(n) ns.db.dayLimit = n end), icon = I .. "Spell_Arcane_PortalIronForge" },
        switch("fromExit", L.FROM_EXIT, L.FROM_EXIT_D, I .. "INV_Misc_PocketWatch_01"),
        { L.ROW_DEFAULTS, L.ESTIMATE_D, control = defaults, icon = I .. "Spell_Nature_TimeStop" },
    })
    st:Add(limits, h1)

    local warnAt = S.Stepper(c, function() return ns.db.warnAt end, function(v) ns.db.warnAt = v end, 1, 0, 4, nil, 100)
    local warnDay = S.Stepper(c, function() return ns.db.warnDayAt end, function(v) ns.db.warnDayAt = v end, 1, 0, 10, nil, 100)
    local alerts, h2 = S.SettingsCard(c, L.SEC_ALERTS, {
        { L.WARN_AT, nil, control = warnAt, icon = I .. "Spell_Nature_TimeStop" },
        { L.WARN_DAY_AT, nil, control = warnDay, icon = I .. "Spell_Holy_BorrowedTime" },
        switch("freeAlert", L.OPT_FREE, nil, ns.OPT_ICON.freeAlert),
        switch("sound", L.OPT_SOUND, nil, I .. "INV_Misc_Drum_01"),
        switch("summary", L.OPT_SUMMARY, nil, I .. "INV_Misc_Note_01"),
    })
    st:Add(alerts, h2)

    local group, h3 = S.SettingsCard(c, L.SEC_GROUP, {
        switch("tellGroup", L.OPT_TELL, nil, I .. "INV_Letter_15"),
        switch("sync", L.OPT_SYNC, L.OPT_SYNC_D, ns.OPT_ICON.sync),
    })
    st:Add(group, h3)

    local modeLabels = {}
    for i, m in ipairs(ns.BADGE_MODES) do modeLabels[i] = L["MODE_" .. m] end
    local modeHolder = CreateFrame("Frame", nil, c)
    modeHolder:SetSize(3 * 86 + 4, 30)
    local modes = S.Tabs(modeHolder, modeLabels, 86, function(i) ns.db.badgeMode = ns.BADGE_MODES[i]; ns.Refresh() end)
    modeHolder:SetScript("OnShow", function()
        for i, m in ipairs(ns.BADGE_MODES) do if m == ns.db.badgeMode then modes:Select(i, true) end end
    end)
    local pct = function(v) return v .. "%" end
    local scale = S.Stepper(c, function() return ns.db.badgeScale end, function(v) ns.db.badgeScale = v; ns.Refresh() end,
        10, 60, 200, pct, 110)
    local alpha = S.Stepper(c, function() return ns.db.badgeAlpha end, function(v) ns.db.badgeAlpha = v; ns.Refresh() end,
        10, 20, 100, pct, 110)
    local counter, h4 = S.SettingsCard(c, L.SEC_COUNTER, {
        { L.BADGE_MODE, nil, control = modeHolder, icon = I .. "INV_Misc_Spyglass_03" },
        { L.BADGE_SIZE, nil, control = scale, icon = I .. "INV_Misc_Spyglass_02" },
        { L.BADGE_ALPHA, nil, control = alpha, icon = I .. "Spell_Shadow_Twilight" },
        switch("badgeLocked", L.OPT_LOCK, L.OPT_LOCK_D, I .. "INV_Misc_Key_04"),
    })
    st:Add(counter, h4)
    c:SetHeight(st:Height())
    settingsPage:SetScript("OnShow", function() scroll:Update(st:Height()) end)
end

---- The window ------------------------------------------------------------------

local function build()
    frame = S.Window("GulliInstanceLimitFrame", L.TITLE, S.NARROW_W, S.DOCK_H)
    footer = S.Footer(frame)
    resetBtn = footer:Add(S.FitButton(footer, L.RESET, 32, 110))
    resetBtn:SetScript("OnClick", function() ns.Reset() end)

    local body, width = frame.body, frame.inner[1]
    tabs = S.Tabs(body, { L.TAB_STATUS, L.TAB_SETTINGS }, 120, function(i) page = i; ns.Refresh() end, nil, { S.TAB.overview, S.TAB.settings })

    statusPage = CreateFrame("Frame", nil, body)
    statusPage:SetPoint("TOPLEFT", 0, -30 - S.GAP)
    statusPage:SetPoint("BOTTOMRIGHT")
    local st = S.Stack(statusPage)
    big = S.StatRow(statusPage, { L.STAT_HOUR, L.STAT_DAY }, 62,
        { "Interface\\Icons\\INV_Misc_PocketWatch_01", "Interface\\Icons\\Spell_Nature_TimeStop" })
    st:Add(big, 62, 8)
    big:Layout(width)
    nextLine = S.Text(statusPage, 12, S.MUTED)
    nextLine:SetWordWrap(false)
    st:Add(nextLine, 16, 4)
    groupLine = S.Text(statusPage, 12, S.MUTED)
    groupLine:SetWordWrap(false)
    st:Add(groupLine, 16)

    entries = S.Card(statusPage, L.ENTRIES)
    entries:SetPoint("TOPLEFT", 0, -st.y)
    entries:SetPoint("BOTTOMRIGHT")
    span = S.Tabs(entries, { L.SPAN_HOUR, L.SPAN_DAY }, 90, function(i)
        range = i == 2 and "DAY" or "HOUR"; ns.Refresh()
    end, 26)
    span.frame:ClearAllPoints()
    span.frame:SetPoint("TOPRIGHT", -S.INSET, -6)
    list = S.List(entries.body, 40, makeRow, fillRow)
    list:SetPoint("TOPLEFT")
    list:SetPoint("BOTTOMRIGHT", -10, 0)
    empty = S.Empty(entries.body)
    empty:Set(L.NONE)

    buildSettings(body, width)
    frame:SetScript("OnShow", function() tabs:Select(page) end)
end

-- Picks a page (1 Status, 2 Settings) and the list span, for the previews and the tests.
function ns.ShowPage(i, which)
    ns.Window():Show()
    if which then range = which; span:Select(which == "DAY" and 2 or 1, true) end
    tabs:Select(i)
end

-- The counter: a Gulli HUD chip "3/5" with a mark per entry and the wait time. Click opens the
-- window; /gulli move places it.
local function badgePlace()
    badge:ClearAllPoints()
    local p = ns.db.badgePoint
    if p then badge:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0) else badge:SetPoint("TOP", 0, -120) end
end

local function buildBadge()
    badge = S.Chip(UIParent, "GulliInstanceLimitBadge")
    badgePlace()
    S.Mover(badge, { label = L.TITLE, save = function(point, rel, x, y) ns.db.badgePoint = { point, rel, x, y } end,
        reset = function() ns.db.badgePoint = nil; badgePlace() end,
        lock = function() ns.db.badgeLocked = true; ns.Refresh() end, lockTip = L.OPT_LOCK })
    badge:SetScript("OnClick", function() ns.Toggle() end)
    local elapsed = 0
    badge:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + (dt or 0)
        if elapsed >= 1 then elapsed = 0; ns.Refresh() end
    end)
end

-- /gulli move: the counter shows even when its mode hides it, so it can be placed.
function ns.MoveBadge(on)
    ns.moving = on and true or nil
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

function ns.SetupBadge()
    if not badge then buildBadge() end
    ns.Refresh()
end
