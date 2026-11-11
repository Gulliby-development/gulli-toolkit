-- A thin bar on screen ("1.2k XP/h · 45 min · 12 kills") that opens the window: the numbers of
-- this session, a switch for the bar and Start again.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, info, bar

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
    local lines = {
        L.RATE:format(ns.Short(st.rate)),
        L.LEFT:format(ns.Short(st.left), st.percent),
        st.toLevel and L.TO_LEVEL:format(ns.Span(st.toLevel)) or L.NO_RATE,
        L.FROM_KILLS:format(st.kills, ns.Short(st.killXP)) ..
            (st.killsToLevel and ("  " .. L.KILLS:format(st.killsToLevel)) or ""),
        L.FROM_QUESTS:format(st.quests, ns.Short(st.questXP)),
        L.RESTED:format(ns.Short(st.rested)),
        L.SESSION:format(ns.Span(st.session), ns.Short(st.gained)),
    }
    info:SetText(table.concat(lines, "\n"))
end

local function build()
    frame = S.Window("GulliXPFrame", L.TITLE, 380, 300)
    local body = frame.body
    info = S.Text(body, 13)
    info:SetPoint("TOPLEFT", 0, 0)
    info:SetPoint("RIGHT", 0, 0)
    info:SetJustifyH("LEFT")
    info:SetSpacing(4)
    local c = S.CheckRow(body, L.OPT_BAR, function() return ns.db.bar end, function(v) ns.db.bar = v; ns.Refresh() end)
    c:SetPoint("BOTTOMLEFT", 0, 40)
    local reset = S.Button(body, 160, 30)
    reset:SetPoint("BOTTOMLEFT", 0, 0)
    reset:SetText(L.RESET)
    reset:SetScript("OnClick", function() ns.Start(); ns.Refresh() end)
    frame:SetScript("OnShow", function() ns.Refresh() end)
end

function ns.Toggle()
    if not frame then build() end
    frame:SetShown(not frame:IsShown())
end
