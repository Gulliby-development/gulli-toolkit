-- A thin bar on screen ("1.2k XP/h · 45 min · 12 kills") that opens the window: the numbers of
-- this session, the bar's settings (shown, locked, opacity, scale, place) and Start again.

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

local XP_COLOR, RESTED_COLOR = { 0.58, 0.36, 0.90, 1 }, { 0.25, 0.55, 1.00, 0.55 }

local function savePoint()
    local p, _, _, x, y = bar:GetPoint()
    ns.db.point = { p, x, y }
end

-- Opacity, scale, lock and place from the settings; the text keeps full opacity.
function ns.StyleBar()
    if not bar then return end
    local d = ns.db
    local a = d.alpha / 100
    S.Fill(bar, { S.BG[1], S.BG[2], S.BG[3], S.BG[4] * a })
    S.SetBorder(bar, { 0, 0, 0, a })
    bar.track:SetAlpha(math.max(0.35, a))
    bar:SetScale(d.scale / 100)
    bar:ClearAllPoints()
    local p = d.point or ns.BAR_POINT
    bar:SetPoint(p[1], UIParent, p[1], p[2], p[3])
end

local function buildBar()
    bar = CreateFrame("Button", "GulliXPBar", UIParent)
    bar:SetSize(260, 24)
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function(self) if not ns.db.locked then self:StartMoving() end end)
    bar:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePoint() end)
    S.Box(bar)
    -- A thin line along the bottom: the level so far, then the rested part after it.
    bar.track = CreateFrame("Frame", nil, bar)
    bar.track:SetPoint("BOTTOMLEFT", 1, 1)
    bar.track:SetPoint("BOTTOMRIGHT", -1, 1)
    bar.track:SetHeight(2)
    bar.xp = S.Tex(bar.track, "ARTWORK", 0, XP_COLOR)
    bar.xp:SetPoint("TOPLEFT")
    bar.xp:SetPoint("BOTTOMLEFT")
    bar.rested = S.Tex(bar.track, "ARTWORK", 0, RESTED_COLOR)
    bar.rested:SetPoint("TOPLEFT", bar.xp, "TOPRIGHT")
    bar.rested:SetPoint("BOTTOMLEFT", bar.xp, "BOTTOMRIGHT")
    bar.text = S.Text(bar, 12)
    bar.text:SetPoint("CENTER", 0, 1)
    bar.text:SetJustifyH("CENTER")
    bar:SetScript("OnClick", function() ns.Toggle() end)
    bar:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(ns.db.locked and L.TIP_LOCKED or L.TIP_MOVE)
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

local function paintBar()
    local st = ns.Stats()
    bar.text:SetText(ns.BarText())
    local w = (tonumber(bar:GetWidth()) or 260) - 2
    local xp, rested = ns.BarParts(st)
    bar.xp:SetWidth(math.max(0.01, w * xp))
    bar.rested:SetWidth(math.max(0.01, w * rested))
    bar.rested:SetShown(rested > 0)
end

function ns.Refresh()
    local showBar = ns.db.bar and not ns.MaxLevel()
    if showBar and not bar then buildBar() end
    if bar then
        bar:SetShown(showBar)
        if showBar then paintBar() end
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
    frame = S.Window("GulliXPFrame", L.TITLE, S.NARROW_W, 420)
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

    local function pct(v) return v .. "%" end
    local alpha = S.Stepper(body, function() return ns.db.alpha end,
        function(v) ns.SetPref("alpha", v) end, 10, 0, 100, pct)
    local scale = S.Stepper(body, function() return ns.db.scale end,
        function(v) ns.SetPref("scale", v) end, 10, 60, 200, pct)
    local place = S.FitButton(body, L.PLACE_RESET, 28, 110)
    place:SetScript("OnClick", function() ns.SetPref("point", nil) end)
    local sw, h = S.SettingsCard(body, L.SEC_BAR, {
        { L.OPT_BAR, nil, function() return ns.db.bar end, function(v) ns.SetPref("bar", v) end,
          icon = ns.OPT_ICON.bar },
        { L.OPT_LOCK, L.OPT_LOCK_D, function() return ns.db.locked end, function(v) ns.SetPref("locked", v) end,
          icon = ns.OPT_ICON.locked },
        { L.OPT_ALPHA, nil, control = alpha, icon = "Interface\\Icons\\Spell_Magic_LesserInvisibilty" },
        { L.OPT_SCALE, nil, control = scale, icon = "Interface\\Icons\\INV_Misc_Spyglass_03" },
        { L.OPT_PLACE, nil, control = place, icon = "Interface\\Icons\\INV_Misc_Map_01" },
    })
    frame.steppers = { alpha, scale }
    st:Add(sw, h)
    S.FitWindow(frame, st:Height())
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
