-- A thin bar on screen ("1.2k XP/h · 45 min · 12 kills") that opens the window: the numbers of
-- this session, a switch for the bar and Start again.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, bar, tiles, left, progress
local info = {}

function ns.BarText()
    local st = ns.Stats()
    local parts = { L.RATE:format(ns.Short(st.rate)) }
    if st.toLevel then parts[#parts + 1] = ns.Span(st.toLevel) end
    if st.killsToLevel then parts[#parts + 1] = L.KILLS:format(st.killsToLevel) end
    return table.concat(parts, "  ·  ")
end

local function buildBar()
    bar = CreateFrame("Button", "GulliXPBar", UIParent)
    bar:SetSize(260, 24)
    bar:SetPoint("TOP", 0, -150)
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", bar.StartMoving)
    bar:SetScript("OnDragStop", bar.StopMovingOrSizing)
    S.Box(bar)
    bar.text = S.Text(bar, 12)
    bar.text:SetPoint("CENTER")
    bar.text:SetJustifyH("CENTER")
    bar:SetScript("OnClick", function() ns.Toggle() end)
    local elapsed = 0
    bar:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + (dt or 0)
        if elapsed >= 5 then elapsed = 0; ns.Refresh() end
    end)
end

function ns.Refresh()
    local showBar = ns.db.bar and not ns.MaxLevel()
    if showBar and not bar then buildBar() end
    if bar then
        bar:SetShown(showBar)
        if showBar then bar.text:SetText(ns.BarText()) end
    end
    if not frame or not frame:IsShown() then return end
    local st = ns.Stats()
    local t = tiles.tiles
    t[1]:Set(ns.Short(st.rate), st.rate > 0 and S.Accent() or S.MUTED)
    t[2]:Set(st.toLevel and ns.Span(st.toLevel) or "-", st.toLevel and S.TEXT or S.MUTED)
    t[3]:Set(st.killsToLevel and tostring(st.killsToLevel) or "-", st.killsToLevel and S.TEXT or S.MUTED)
    left:SetText(L.LEFT:format(ns.Short(st.left), st.percent) .. (st.toLevel and "" or ("   " .. S.Hex(S.FAINT) .. L.NO_RATE .. "|r")))
    progress:Set(st.percent / 100)
    local lines = {
        L.FROM_KILLS:format(st.kills, ns.Short(st.killXP)),
        L.FROM_QUESTS:format(st.quests, ns.Short(st.questXP)),
        L.RESTED:format(ns.Short(st.rested)),
        L.SESSION:format(ns.Span(st.session), ns.Short(st.gained)),
    }
    for i, l in ipairs(lines) do info[i]:SetText(l) end
end

local function build()
    frame = S.Window("GulliXPFrame", L.TITLE, 460, 420)
    local ft = S.Footer(frame)
    local reset = ft:Add(S.FitButton(ft, L.RESET, 32, 110))
    reset:SetScript("OnClick", function() ns.Start(); ns.Refresh() end)
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
    st:Add(lv, 28)

    local card = S.Card(body, L.SEC_SESSION)
    for i = 1, 4 do
        local t = S.Text(card.body, 12)
        t:SetPoint("TOPLEFT", 0, -(i - 1) * 22)
        t:SetPoint("TOPRIGHT", 0, -(i - 1) * 22)
        t:SetWordWrap(false)
        info[i] = t
    end
    st:Add(card, card:Fit(4 * 22 - 8))

    local sw, h = S.SettingsCard(body, nil, {
        { L.OPT_BAR, nil, function() return ns.db.bar end, function(v) ns.db.bar = v; ns.Refresh() end,
          icon = "Interface\\Icons\\INV_Misc_Spyglass_02" } })
    st:Add(sw, h)
    S.FitWindow(frame, st:Height())
    frame:SetScript("OnShow", function() ns.Refresh() end)
end

function ns.Toggle()
    if not frame then build() end
    frame:SetShown(not frame:IsShown())
    if frame:IsShown() then ns.Refresh() end
end
