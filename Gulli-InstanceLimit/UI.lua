-- The window has two pages. Status: the entries left this hour as one big number, a slot per
-- entry of the hour with the dungeon that holds it and when it frees, the group, and the runs
-- of the last day by character, with Reset in the footer. Settings: alerts, the group and the
-- counter. The counter is a small badge on screen that opens the window.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, tabs, statusPage, settingsPage, hero, groupRow, list, empty, entries
local resetBtn, footer, badge
local TIME_ICON = "Interface\\Icons\\Spell_Nature_TimeStop"
local page = 1
local SLOT_GAP, SLOTS_MAX, CHIPS_MAX = 6, 10, 6
local I = "Interface\\Icons\\"

local function ago(t)
    return L.AGO:format(ns.Clock(time() - t))
end

---- The entry list -------------------------------------------------------------

local function makeRow(r)
    -- a dot marks a run that still holds a slot of the hour
    r.dot = S.Circle(r, 8, S.WARN, "ARTWORK")
    r.dot:SetPoint("TOPLEFT", 2, -9)
    r.name = S.Text(r, 12)
    r.name:SetPoint("TOPLEFT", 16, -5)
    r.name:SetPoint("RIGHT", -110, 0)
    r.name:SetWordWrap(false)
    r.run = S.Text(r, 12, S.MUTED)
    r.run:SetPoint("BOTTOMLEFT", 16, 5)
    r.run:SetPoint("RIGHT", -110, 0)
    r.run:SetWordWrap(false)
    r.when = S.Text(r, 12, S.MUTED)
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
    r.dot:SetShown(not header and time() - e.t < ns.HOUR)
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

-- The runs of the last day, grouped by character (the player's first), the newest first.
function ns.ListItems(now)
    now = now or time()
    local byChar, chars = {}, {}
    for _, e in ipairs(ns.db.entries) do
        if now - e.t < ns.DAY then
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
        local runs = byChar[c]
        table.sort(runs, function(a, b) return a.t > b.t end)
        if #chars > 1 then out[#out + 1] = { header = true, char = c, class = runs[1].class, count = #runs } end
        for _, e in ipairs(runs) do out[#out + 1] = e end
    end
    return out
end

-- "Runs: 4 · 46:20 on average" over the runs of the list; the mean only of finished runs.
function ns.RunsHint(items)
    local n, sum, done = 0, 0, 0
    for _, e in ipairs(items) do
        if not e.header then
            n = n + 1
            if e.out then sum, done = sum + (e.secs or 0), done + 1 end
        end
    end
    if n == 0 then return "" end
    local text = L.RUNS_N:format(n)
    if done > 0 then text = text .. S.DOT .. L.SES_AVG:format(ns.Clock(sum / done)) end
    return text
end

---- The hero card: the number, the state and the slots of the hour ---------------

local function buildHero(parent, width)
    local c = S.Card(parent)
    c.big = S.Text(c, 28, S.GOOD, nil, "title")
    c.big:SetPoint("TOPLEFT", S.INSET + 2, -S.INSET - 4)
    c.dot = S.Circle(c, 8, S.GOOD, "ARTWORK")
    c.dot:SetPoint("TOPLEFT", S.INSET + 96, -S.INSET - 9)
    c.state = S.Text(c, 14)
    c.state:SetPoint("TOPLEFT", S.INSET + 112, -S.INSET - 4)
    c.state:SetPoint("RIGHT", -S.INSET, 0)
    c.state:SetWordWrap(false)
    c.sub = S.Text(c, 12, S.MUTED)
    c.sub:SetPoint("TOPLEFT", S.INSET + 112, -S.INSET - 26)
    c.sub:SetPoint("RIGHT", -S.INSET, 0)
    c.sub:SetWordWrap(false)
    c.slots = {}
    local function slot(i)
        local f = c.slots[i]
        if f then return f end
        f = CreateFrame("Frame", nil, c)
        S.Box(f, S.INPUT, S.LINE, S.R_MD)
        f:SetHeight(50)
        f.name = S.Text(f, 12)
        f.name:SetPoint("TOPLEFT", 7, -6)
        f.name:SetPoint("RIGHT", -5, 0)
        f.name:SetWordWrap(false)
        f.time = S.Text(f, 12, S.MUTED)
        f.time:SetPoint("TOPLEFT", 7, -22)
        f.track = f:CreateTexture(nil, "ARTWORK")
        f.track:SetColorTexture(1, 1, 1, 0.07)
        f.track:SetHeight(3)
        f.track:SetPoint("BOTTOMLEFT", 7, 7)
        f.track:SetPoint("BOTTOMRIGHT", -7, 7)
        f.fill = f:CreateTexture(nil, "OVERLAY")
        f.fill:SetHeight(3)
        f.fill:SetPoint("BOTTOMLEFT", 7, 7)
        -- A long dungeon name is cut in its slot: the tooltip has all of it.
        f:SetScript("OnEnter", function(self)
            if not self.full or not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.full)
            GameTooltip:Show()
        end)
        f:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        c.slots[i] = f
        return f
    end
    function c:Set(s, slots)
        local tone = s.left == 0 and S.BAD or (s.left == 1 and S.WARN or S.GOOD)
        self.big:SetText(S.Hex(tone) .. s.leftHour .. "|r" .. S.Hex(S.FAINT) .. " / " .. s.limit .. "|r")
        self.dot:SetVertexColor(tone[1], tone[2], tone[3], 1)
        if s.left == 0 then
            self.state:SetText(L.NO_LEFT)
            self.sub:SetText(S.Emph(L.NEXT_IN:format(ns.Clock(s.wait))))
        else
            self.state:SetText(L.ALL_FREE)
            self.sub:SetText(s.nextFree > 0 and S.Emph(L.SLOT_NEXT:format(ns.Clock(s.nextFree))) or "")
        end
        S.SetBorder(self, s.left == 0 and S.BAD or S.CARD_EDGE)
        local n = math.min(#slots, SLOTS_MAX)
        local w = math.floor((width - 2 * S.INSET - (n - 1) * SLOT_GAP) / n)
        for i = 1, math.max(n, #self.slots) do
            local f = slot(i)
            local d = slots[i]
            f:SetShown(i <= n)
            if i <= n then
                f:ClearAllPoints()
                f:SetPoint("BOTTOMLEFT", S.INSET + (i - 1) * (w + SLOT_GAP), S.INSET)
                f:SetWidth(w)
                local a = S.Accent()
                if d.isFree then
                    f.full = nil
                    f.name:SetText(S.Hex(S.GOOD) .. L.SLOT_FREE .. "|r")
                    f.time:SetText("")
                    f.fill:Hide()
                    S.SetBorder(f, S.LINE)
                else
                    f.full = d.name
                    f.name:SetText(d.name or "?")
                    f.time:SetText(ns.Clock(d.free))
                    local c2 = d.first and S.WARN or S.MUTED
                    f.time:SetTextColor(c2[1], c2[2], c2[3], 1)
                    f.fill:SetColorTexture(a[1], a[2], a[3], 1)
                    f.fill:SetWidth(math.max(1, (w - 14) * math.max(0, math.min(1, d.frac))))
                    f.fill:Show()
                    S.SetBorder(f, d.first and S.WARN or S.LINE)
                end
            end
        end
    end
    return c
end

---- The group: a chip per member ------------------------------------------------

local function buildGroup(parent, width)
    local g = CreateFrame("Frame", nil, parent)
    g.label = S.Text(g, 12, S.GOLD_DIM, nil, "bold")
    g.label:SetPoint("LEFT", 2, 0)
    g.label:SetText(S.Upper(L.GROUP))
    g.none = S.Text(g, 12, S.FAINT)
    g.none:SetPoint("LEFT", g.label, "RIGHT", 10, 0)
    g.none:SetPoint("RIGHT")
    g.none:SetWordWrap(false)
    g.more = S.Text(g, 12, S.FAINT)
    g.chips = {}
    local function chip(i)
        local f = g.chips[i]
        if f then return f end
        f = CreateFrame("Frame", nil, g)
        S.Box(f, S.INPUT, S.LINE, 11)
        f:SetHeight(22)
        f.text = S.Text(f, 12, S.MUTED)
        f.text:SetPoint("CENTER")
        g.chips[i] = f
        return f
    end
    function g:Set(members)
        self.none:SetShown(#members == 0)
        self.none:SetText(L.GROUP_NONE)
        local x = (tonumber(self.label:GetStringWidth()) or 0) + 12
        local shown = 0
        for i = 1, math.max(#members, #self.chips) do
            local m = members[i]
            local f = (m or self.chips[i]) and chip(i)
            if f then
                local fits = false
                if m and i <= CHIPS_MAX and shown == i - 1 then
                    local tail = m.none and L.NO_ADDON or
                        (S.Hex(m.left == 0 and S.BAD or (m.left == 1 and S.WARN or S.TEXT)) .. L.CHIP_LEFT:format(m.left) .. "|r")
                    f.text:SetText(classHex(m.class) .. m.name .. "|r " .. tail)
                    local w = math.floor((tonumber(f.text:GetStringWidth()) or 0) + 20)
                    if x + w <= width - 34 then
                        f:SetWidth(w)
                        f:ClearAllPoints()
                        f:SetPoint("LEFT", x, 0)
                        x = x + w + 6
                        shown = i
                        fits = true
                    end
                end
                f:SetShown(fits)
            end
        end
        self.more:SetShown(shown < #members)
        self.more:ClearAllPoints()
        self.more:SetPoint("LEFT", x, 0)
        self.more:SetText("+" .. (#members - shown))
    end
    return g
end

---- The badge -------------------------------------------------------------------

-- Whether the counter shows: always, never, or in a group, in a dungeon or when entries are short.
local function unlocked() return ns.moving end

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
    badge:Set(TIME_ICON, s.leftHour .. "/" .. ns.db.limit, color, s.leftHour, ns.db.limit,
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
    hero:Set(s, ns.Slots())
    groupRow:Set(ns.GroupList())
    local items = ns.ListItems()
    list:SetData(items)
    entries:SetTitle(L.RUNS, ns.RunsHint(items))
    empty:SetShown(#items == 0)
    resetBtn:SetEnabled(ns.CanReset())
    if ns.insideNames then
        footer:SetStatus(L.STILL_INSIDE:format(table.concat(ns.insideNames, ", ")), S.WARN)
    else
        footer:SetStatus(L.RESET_TIP)
    end
end

---- Settings --------------------------------------------------------------------

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

    local warnAt = S.Stepper(c, function() return ns.db.warnAt end, function(v) ns.db.warnAt = v end, 1, 0, 4, nil, 100)
    local alerts, h2 = S.SettingsCard(c, L.SEC_ALERTS, {
        { L.WARN_AT, nil, control = warnAt, icon = I .. "Spell_Nature_TimeStop" },
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

    -- When the counter shows; hiding it is the hub's switch (Frames on screen), and while it is
    -- hidden the choice is kept for when it comes back.
    local SHOWN = { "ALWAYS", "GROUP" }
    local modeLabels = {}
    for i, m in ipairs(SHOWN) do modeLabels[i] = L["MODE_" .. m] end
    local modeHolder = CreateFrame("Frame", nil, c)
    modeHolder:SetSize(#SHOWN * 136 + 4, 30)
    local modes = S.Tabs(modeHolder, modeLabels, 136, function(i)
        if ns.db.badgeMode == "HIDDEN" then ns.db.badgeWas = SHOWN[i] else ns.db.badgeMode = SHOWN[i] end
        ns.Refresh()
    end)
    modeHolder:SetScript("OnShow", function()
        local cur = ns.db.badgeMode == "HIDDEN" and (ns.db.badgeWas or "ALWAYS") or ns.db.badgeMode
        for i, m in ipairs(SHOWN) do if m == cur then modes:Select(i, true) end end
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
    tabs = S.PageTabs(body, { L.TAB_STATUS, L.TAB_SETTINGS }, 120, function(i) page = i; ns.Refresh() end, nil, { S.TAB.overview, S.TAB.settings })

    statusPage = CreateFrame("Frame", nil, body)
    statusPage:SetPoint("TOPLEFT", 0, -30 - S.GAP)
    statusPage:SetPoint("BOTTOMRIGHT")
    local st = S.Stack(statusPage)
    hero = buildHero(statusPage, width)
    st:Add(hero, 2 * S.INSET + 50 + 12 + 46)
    groupRow = buildGroup(statusPage, width)
    st:Add(groupRow, 22)

    entries = S.Card(statusPage, L.RUNS, " ")
    entries:SetPoint("TOPLEFT", 0, -st.y)
    entries:SetPoint("BOTTOMRIGHT")
    list = S.List(entries.body, 40, makeRow, fillRow)
    list:SetPoint("TOPLEFT")
    list:SetPoint("BOTTOMRIGHT", -10, 0)
    empty = S.Empty(entries.body)
    empty:Set(L.NONE_DAY)

    buildSettings(body, width)
    frame:SetScript("OnShow", function() tabs:Select(page) end)
end

-- Picks a page (1 Status, 2 Settings), for the previews and the tests.
function ns.ShowPage(i)
    ns.Window():Show()
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
        reset = function() ns.db.badgePoint = nil; badgePlace() end })
    badge:SetScript("OnClick", function() ns.Toggle() end)
    local elapsed = 0
    badge:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + (dt or 0)
        if elapsed >= 1 then elapsed = 0; ns.Refresh() end
    end)
end

-- The hub's Unlock mode: the counter shows even when its mode hides it, so it can be placed.
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

function ns.BadgeFrame()
    if not badge and ns.db then buildBadge() end
    return badge
end

function ns.SetupBadge()
    if not badge then buildBadge() end
    ns.Refresh()
end
