-- A thin bar on screen ("1.2k XP/h · 45 min · 12 kills") that opens the window. Its line shows
-- the level done, the XP of finished quests (gold) and the rested part. At the top level it
-- shows the watched reputation instead. The window: three tiles, the level with the quests to
-- hand in, and three tabs: this session (with a graph), the last levels and the bar's settings.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, bar, tiles, left, ready, progress, tabs
local pages, info, graph, levelLines = {}, {}, {}, {}
local GRAPH_BARS = 18

local XP_COLOR, RESTED_COLOR = { 0.58, 0.36, 0.90, 1 }, { 0.25, 0.55, 1.00, 0.55 }
local READY_COLOR, REP_COLOR = { 1.00, 0.78, 0.25, 0.95 }, { 0.30, 0.75, 0.45, 1 }

-- What the bar says, by the chosen text (ns.TEXTS).
function ns.BarText(st)
    st = st or ns.Stats()
    local mode = ns.db.text or "all"
    local eta = st.toLevel and ns.Span(st.toLevel) or "-"
    if mode == "rate" then return L.RATE:format(ns.Short(st.rate)) end
    if mode == "eta" then return st.toLevel and L.TO_LEVEL:format(eta) or L.NO_RATE_SHORT end
    if mode == "left" then return L.LEFT_SHORT:format(ns.Short(st.left), st.percent) end
    if mode == "pct" then return L.LEVEL_PCT:format(st.level, st.percent) end
    local parts = { L.RATE:format(ns.Short(st.rate)) }
    if st.toLevel then parts[#parts + 1] = eta end
    if st.killsToLevel then parts[#parts + 1] = L.KILLS:format(st.killsToLevel) end
    return table.concat(parts, "  ·  ")
end

-- The numbers behind the bar, for its tooltip.
function ns.TipLines(st)
    st = st or ns.Stats()
    local lines = {
        L.RATE:format(ns.Short(st.rate)),
        st.toLevel and L.TO_LEVEL:format(ns.Span(st.toLevel)) or L.NO_RATE,
        L.LEFT:format(ns.Short(st.left), st.percent),
        L.RESTED:format(ns.Short(st.rested)),
    }
    if st.readyN > 0 then lines[#lines + 1] = L.READY:format(ns.Short(st.ready), st.readyN, st.readyPercent) end
    if st.killsToLevel then lines[#lines + 1] = L.KILLS_TO:format(st.killsToLevel) end
    if st.questsToLevel then lines[#lines + 1] = L.QUESTS_TO:format(st.questsToLevel) end
    lines[#lines + 1] = L.SESSION:format(ns.Span(st.session), ns.Short(st.gained))
    return lines
end

local function textLabel(mode) return L["TEXT_" .. mode:upper()] end

local function savePoint()
    local p, _, _, x, y = bar:GetPoint()
    ns.db.point = { p, x, y }
end

-- Opacity, scale, width, lock and place from the settings; the text keeps full opacity.
function ns.StyleBar()
    if not bar then return end
    local d = ns.db
    local a = d.alpha / 100
    S.Fill(bar, { S.BG[1], S.BG[2], S.BG[3], S.BG[4] * a })
    S.SetBorder(bar, { 0, 0, 0, a })
    bar.track:SetAlpha(math.max(0.35, a))
    bar:SetScale(d.scale / 100)
    local p = d.point or ns.BAR_POINT
    bar:ClearAllPoints()
    if d.wide then
        -- Across the whole screen, at the height the player chose.
        local w = (tonumber(UIParent:GetWidth()) or 1024) / (d.scale / 100)
        bar:SetWidth(w)
        bar:SetPoint(p[1], UIParent, p[1], 0, p[3])
    else
        bar:SetWidth(260)
        bar:SetPoint(p[1], UIParent, p[1], p[2], p[3])
    end
end

local function buildBar()
    bar = CreateFrame("Button", "GulliXPBar", UIParent)
    bar:SetSize(260, 24)
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function(self) if not ns.Locked() then self:StartMoving() end end)
    bar:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePoint() end)
    S.Box(bar)
    -- A thin line along the bottom: the level so far, finished quests, then the rested part.
    bar.track = CreateFrame("Frame", nil, bar)
    bar.track:SetPoint("BOTTOMLEFT", 1, 1)
    bar.track:SetPoint("BOTTOMRIGHT", -1, 1)
    bar.track:SetHeight(2)
    bar.xp = S.Tex(bar.track, "ARTWORK", 0, XP_COLOR)
    bar.xp:SetPoint("TOPLEFT")
    bar.xp:SetPoint("BOTTOMLEFT")
    bar.ready = S.Tex(bar.track, "ARTWORK", 0, READY_COLOR)
    bar.ready:SetPoint("TOPLEFT", bar.xp, "TOPRIGHT")
    bar.ready:SetPoint("BOTTOMLEFT", bar.xp, "BOTTOMRIGHT")
    bar.rested = S.Tex(bar.track, "ARTWORK", 0, RESTED_COLOR)
    bar.rested:SetPoint("TOPLEFT", bar.ready, "TOPRIGHT")
    bar.rested:SetPoint("BOTTOMLEFT", bar.ready, "BOTTOMRIGHT")
    bar.text = S.Text(bar, 12)
    bar.text:SetPoint("CENTER", 0, 1)
    bar.text:SetJustifyH("CENTER")
    bar:SetScript("OnClick", function()
        if IsShiftKeyDown and IsShiftKeyDown() then ns.Share() else ns.Toggle() end
    end)
    bar:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L.TITLE, 1, 1, 1)
        if not bar.atCap then
            for _, l in ipairs(ns.TipLines()) do GameTooltip:AddLine(l, 0.93, 0.93, 0.94) end
        end
        GameTooltip:AddLine(ns.Locked() and L.TIP_LOCKED or L.TIP_MOVE, 0.6, 0.61, 0.66, true)
        GameTooltip:Show()
    end)
    bar:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    local elapsed = 0
    bar:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + (dt or 0)
        if elapsed >= 5 then elapsed = 0; ns.Refresh() end
    end)
    ns.StyleBar()
end

local function setLine(done, readyPart, rested)
    local w = (tonumber(bar:GetWidth()) or 260) - 2
    bar.xp:SetWidth(math.max(0.01, w * done))
    bar.ready:SetWidth(math.max(0.01, w * readyPart))
    bar.ready:SetShown(readyPart > 0)
    bar.rested:SetWidth(math.max(0.01, w * rested))
    bar.rested:SetShown(rested > 0)
end

local function paintBar()
    if bar.atCap then
        local name, standing, v, size = ns.WatchedFaction()
        bar.text:SetText(name and L.REP_BAR:format(name, standing, ns.Short(v), ns.Short(size)) or L.MOVE_ME)
        bar.xp:SetVertexColor(REP_COLOR[1], REP_COLOR[2], REP_COLOR[3], 1)
        setLine(name and math.min(1, v / size) or 0, 0, 0)
        return
    end
    bar.xp:SetVertexColor(XP_COLOR[1], XP_COLOR[2], XP_COLOR[3], 1)
    local st = ns.Stats()
    bar.text:SetText(ns.BarText(st))
    local xp, rested, readyPart = ns.BarParts(st)
    setLine(xp, readyPart, rested)
end

-- At the top level the bar shows the watched reputation, when the player wants it.
local function barState()
    local atCap = ns.MaxLevel()
    local show = ns.db.bar
    if atCap then show = show and ns.db.rep and ns.WatchedFaction() ~= nil end
    return show or ns.moving, atCap
end

local function fillGraph()
    local s = ns.s
    local now = time()
    local last = math.floor((now - s.t) / ns.BUCKET) + 1
    local first = math.max(1, last - GRAPH_BARS + 1)
    local top = 1
    for i = first, last do top = math.max(top, s.buckets[i] or 0) end
    local h = graph.height
    for j = 1, GRAPH_BARS do
        local v = s.buckets[first + j - 1] or 0
        local b = graph.bars[j]
        b:SetHeight(math.max(1, h * v / top))
        b:SetShown(first + j - 1 <= last)
        b:SetAlpha(v > 0 and 1 or 0.25)
    end
    graph.top:SetText(L.GRAPH_TOP:format(ns.Short(top)))
end

local function fillLevels()
    local list = ns.Levels()
    for i, l in ipairs(levelLines) do
        local e = list[i]
        if e then
            local t = ns.Span(e.time) .. (e.partial and "+" or "")
            l.level:SetText(L.LEVEL_N:format(e.level))
            l.time:SetText(t)
            l.from:SetText(L.LEVEL_FROM:format(e.kills or 0, ns.Short(e.killXP or 0), ns.Short(e.questXP or 0)))
        end
        l:SetShown(e ~= nil)
    end
    pages[2].empty:SetShown(#list == 0)
end

function ns.Refresh()
    local show, atCap = barState()
    if show and not bar then buildBar() end
    if bar then
        bar.atCap = atCap
        bar:SetShown(show)
        if show then paintBar() end
    end
    if not frame or not frame:IsShown() then return end
    local st = ns.Stats()
    local t = tiles.tiles
    t[1]:Set(ns.Short(st.rate), st.rate > 0 and S.Accent() or S.MUTED)
    t[2]:Set(st.toLevel and ns.Span(st.toLevel) or "-", st.toLevel and S.TEXT or S.MUTED)
    t[3]:Set(st.killsToLevel and tostring(st.killsToLevel) or "-", st.killsToLevel and S.TEXT or S.MUTED)
    left:SetText(L.LEFT:format(ns.Short(st.left), st.percent) .. (st.toLevel and "" or ("   " .. S.Hex(S.FAINT) .. L.NO_RATE .. "|r")))
    ready:SetText(st.readyN > 0 and (S.Hex(READY_COLOR) .. L.READY:format(ns.Short(st.ready), st.readyN, st.readyPercent) .. "|r") or "")
    progress:Set(st.percent / 100)
    ns.FillInfo(st)
    fillGraph()
    fillLevels()
    if frame.textBtn then frame.textBtn:SetText(textLabel(ns.db.text or "all")) end
end

-- One line of a session card: a game icon, a grey label on the left, the value on the right.
local ROW_H = 24

local function infoRow(parent, i, label, icon)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(ROW_H - 4)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
    local ic = S.IconBox(r, 18, icon)
    ic:SetPoint("LEFT")
    r.value = S.Text(r, 13)
    r.value:SetPoint("RIGHT")
    r.value:SetJustifyH("RIGHT")
    r.value:SetWordWrap(false)
    r.label = S.Text(r, 12, S.MUTED)
    r.label:SetPoint("LEFT", ic, "RIGHT", 8, 0)
    r.label:SetPoint("RIGHT", r.value, "LEFT", -8, 0)
    r.label:SetWordWrap(false)
    r.label:SetText(label)
    function r:Set(text, color) self.value:SetText(text); self.value:SetTextColor(unpack(color or S.TEXT)) end
    return r
end

-- The session in two cards: where the XP came from, and the pace to the next level.
local SOURCES = {
    { "ROW_KILLS", "Interface\\Icons\\INV_Sword_04" },
    { "ROW_QUESTS", "Interface\\Icons\\INV_Misc_Note_01" },
    { "ROW_OTHER", "Interface\\Icons\\INV_Misc_Map_01" },
    { "ROW_RESTED", "Interface\\Icons\\Spell_Nature_Sleep" },
    { "ROW_TOTAL", "Interface\\Icons\\INV_Misc_Book_11" },
}
local PACE = {
    { "ROW_PLAYED", "Interface\\Icons\\INV_Misc_PocketWatch_01" },
    { "ROW_PER_KILL", "Interface\\Icons\\Ability_DualWield" },
    { "ROW_KILLS_TO", "Interface\\Icons\\INV_Sword_04" },
    { "ROW_QUESTS_TO", "Interface\\Icons\\INV_Misc_Note_01" },
}

local function fillInfo(st)
    local function xp(n, color) return ns.Short(n) .. " XP", color end
    local function count(n, what)
        return S.Hex(S.FAINT) .. L.TIMES:format(n) .. "|r  " .. what
    end
    info[1]:Set(count(st.kills, ns.Short(st.killXP) .. " XP"), st.killXP > 0 and XP_COLOR or S.MUTED)
    info[2]:Set(count(st.quests, ns.Short(st.questXP) .. " XP"), st.questXP > 0 and READY_COLOR or S.MUTED)
    info[3]:Set(xp(st.otherXP, st.otherXP > 0 and S.TEXT or S.MUTED))
    info[4]:Set(xp(st.rested, st.rested > 0 and { 0.45, 0.70, 1.00, 1 } or S.MUTED))
    info[5]:Set(xp(st.gained, st.gained > 0 and S.Accent() or S.MUTED))
    info[6]:Set(ns.Span(st.session))
    info[7]:Set(st.avgKill > 0 and (ns.Short(st.avgKill) .. " XP") or "-", st.avgKill > 0 and S.TEXT or S.MUTED)
    info[8]:Set(st.killsToLevel and tostring(st.killsToLevel) or "-", st.killsToLevel and S.TEXT or S.MUTED)
    info[9]:Set(st.questsToLevel and tostring(st.questsToLevel) or "-", st.questsToLevel and S.TEXT or S.MUTED)
end
ns.FillInfo = fillInfo

local function sessionPage(body, width)
    local p = CreateFrame("Frame", nil, body)
    local st = S.Stack(p)
    local half = math.floor((width - S.GAP) / 2)
    local pair = CreateFrame("Frame", nil, p)
    local src = S.Card(pair, L.SEC_SOURCES)
    local pace = S.Card(pair, L.SEC_PACE)
    local h = src:Fit(#SOURCES * ROW_H - 4)
    pace:SetHeight(h)
    src:SetPoint("TOPLEFT")
    src:SetWidth(half)
    pace:SetPoint("TOPRIGHT")
    pace:SetWidth(half)
    for i, d in ipairs(SOURCES) do info[i] = infoRow(src.body, i, L[d[1]], d[2]) end
    for i, d in ipairs(PACE) do info[#SOURCES + i] = infoRow(pace.body, i, L[d[1]], d[2]) end
    st:Add(pair, h)

    local gc = S.Card(p, L.SEC_GRAPH)
    graph.top = S.Text(gc, 11, S.FAINT)
    graph.top:SetPoint("TOPRIGHT", -S.INSET, -13)
    graph.height = 62
    graph.bars = {}
    local bw = math.floor((width - 2 * S.INSET - (GRAPH_BARS - 1) * 3) / GRAPH_BARS)
    for j = 1, GRAPH_BARS do
        local b = S.Tex(gc.body, "ARTWORK", 0, XP_COLOR)
        b:SetWidth(bw)
        b:SetPoint("BOTTOMLEFT", (j - 1) * (bw + 3), 0)
        graph.bars[j] = b
    end
    st:Add(gc, gc:Fit(graph.height))

    local row = CreateFrame("Frame", nil, p)
    local restart = S.Ghost(S.FitButton(row, L.RESET, 30, 120))
    restart:SetScript("OnClick", function() ns.Start(); ns.Refresh() end)
    restart:SetPoint("RIGHT")
    local note = S.Note(row, 11)
    note:SetPoint("LEFT")
    note:SetPoint("RIGHT", restart, "LEFT", -8, 0)
    note:SetMaxLines(2)
    note:SetText(L.SESSION_NOTE)
    st:Add(row, 30)
    return p
end

local function levelsPage(body)
    local p = CreateFrame("Frame", nil, body)
    local card = S.Card(p, L.SEC_LEVELS)
    card:SetPoint("TOPLEFT")
    card:SetPoint("TOPRIGHT")
    for i = 1, 10 do
        local l = CreateFrame("Frame", nil, card.body)
        l:SetHeight(24)
        l:SetPoint("TOPLEFT", 0, -(i - 1) * 26)
        l:SetPoint("TOPRIGHT", 0, -(i - 1) * 26)
        l.level = S.Text(l, 12)
        l.level:SetPoint("LEFT")
        l.level:SetWidth(80)
        l.time = S.Text(l, 12, S.Accent())
        l.time:SetPoint("LEFT", 84, 0)
        l.time:SetWidth(100)
        l.from = S.Text(l, 11, S.MUTED)
        l.from:SetPoint("LEFT", 190, 0)
        l.from:SetPoint("RIGHT")
        l.from:SetWordWrap(false)
        levelLines[i] = l
    end
    card:Fit(10 * 26 - 2)
    p.empty = S.Note(card.body, 12)
    p.empty:SetPoint("TOPLEFT")
    p.empty:SetPoint("RIGHT")
    p.empty:SetText(L.NO_LEVELS)
    return p
end

local function barPage(body)
    local p = CreateFrame("Frame", nil, body)
    local function pct(v) return v .. "%" end
    local alpha = S.Stepper(p, function() return ns.db.alpha end,
        function(v) ns.SetPref("alpha", v) end, 10, 0, 100, pct)
    local scale = S.Stepper(p, function() return ns.db.scale end,
        function(v) ns.SetPref("scale", v) end, 10, 60, 200, pct)
    local place = S.FitButton(p, L.PLACE_RESET, 28, 110)
    place:SetScript("OnClick", function() ns.SetPref("point", nil) end)
    -- The text cycles through the choices on each press.
    local text = S.Button(p, 130, 28)
    text:SetScript("OnClick", function()
        local cur = ns.db.text or "all"
        local nxt = ns.TEXTS[1]
        for i, m in ipairs(ns.TEXTS) do if m == cur then nxt = ns.TEXTS[i % #ns.TEXTS + 1] end end
        ns.SetPref("text", nxt)
    end)
    frame.textBtn = text
    local sw = S.SettingsCard(p, L.SEC_BAR, {
        { L.OPT_BAR, nil, function() return ns.db.bar end, function(v) ns.SetPref("bar", v) end,
          icon = ns.OPT_ICON.bar },
        { L.OPT_LOCK, nil, function() return ns.db.locked end, function(v) ns.SetPref("locked", v) end,
          icon = ns.OPT_ICON.locked },
        { L.OPT_TEXT, nil, control = text, icon = "Interface\\Icons\\INV_Misc_Note_01" },
        { L.OPT_ALPHA, nil, control = alpha, icon = "Interface\\Icons\\Spell_Magic_LesserInvisibilty" },
        { L.OPT_SCALE, nil, control = scale, icon = "Interface\\Icons\\INV_Misc_Spyglass_03" },
        { L.OPT_WIDE, nil, function() return ns.db.wide end, function(v) ns.SetPref("wide", v) end,
          icon = "Interface\\Icons\\INV_Misc_Map_02" },
        { L.OPT_PLACE, nil, control = place, icon = "Interface\\Icons\\INV_Misc_Map_01" },
        { L.OPT_REP, nil, function() return ns.db.rep end, function(v) ns.SetPref("rep", v) end,
          icon = ns.OPT_ICON.rep },
    })
    sw:SetPoint("TOPLEFT")
    sw:SetPoint("TOPRIGHT")
    frame.steppers = { alpha, scale }
    return p
end

local function build()
    frame = S.Window("GulliXPFrame", L.TITLE, S.NARROW_W, S.DOCK_H)
    local body, width = frame.body, frame.inner[1]
    local st = S.Stack(body)

    tiles = S.StatRow(body, { L.STAT_RATE, L.STAT_TIME, L.STAT_KILLS }, 62,
        { "Interface\\Icons\\INV_Misc_Book_11", "Interface\\Icons\\INV_Misc_PocketWatch_01",
          "Interface\\Icons\\INV_Sword_04" })
    st:Add(tiles, 62)
    tiles:Layout(width)

    local lv = CreateFrame("Frame", nil, body)
    left = S.Text(lv, 12, S.MUTED)
    left:SetPoint("TOPLEFT")
    left:SetPoint("TOPRIGHT")
    left:SetWordWrap(false)
    progress = S.Progress(lv, 6)
    progress:SetPoint("TOPLEFT", 0, -22)
    progress:SetPoint("TOPRIGHT", 0, -22)
    progress:SetWidth(width)
    ready = S.Text(lv, 12)
    ready:SetPoint("TOPLEFT", 0, -36)
    ready:SetPoint("TOPRIGHT", 0, -36)
    ready:SetWordWrap(false)
    st:Add(lv, 50)

    tabs = S.Tabs(body, { L.TAB_SESSION, L.TAB_LEVELS, L.TAB_BAR }, nil, function(i)
        for j, p in ipairs(pages) do p:SetShown(j == i) end
        if i == 3 then for _, x in ipairs(frame.steppers) do x:Refresh() end end
        ns.Refresh()
    end, nil, { S.TAB.recent, "Interface\\Icons\\Spell_ChargePositive", S.TAB.overview })
    tabs.frame:ClearAllPoints()
    tabs.frame:SetPoint("TOPLEFT", 0, -st.y)
    st:Space(30 + S.GAP)

    pages[1] = sessionPage(body, width)
    pages[2] = levelsPage(body)
    pages[3] = barPage(body)
    for i, p in ipairs(pages) do
        p:SetPoint("TOPLEFT", 0, -st.y)
        p:SetPoint("BOTTOMRIGHT")
        p:SetShown(i == 1)
    end
    frame:SetScript("OnShow", function()
        for _, x in ipairs(frame.steppers) do x:Refresh() end
        ns.Refresh()
    end)
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

-- The tabs, for the tests.
function ns.Tabs() return tabs, pages end
