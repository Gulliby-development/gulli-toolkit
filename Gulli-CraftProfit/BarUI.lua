-- The craft bar on the screen (the "board"): the item, a big count, the time left, a thick bar
-- for the whole batch cut into crafts, a thin one for the craft that runs, and a line under
-- them. Bar.lua says what it shows (ns.BarState, ns.BarView); this file only draws it.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local BAR_W, BAR_H = 560, 132
local PAD, ICON = 16, 56
local TRACK_H, THIN_H = 20, 6
local TEXT_EVERY = 0.2 -- seconds between two repaints of the texts
local DONE = { 0.435, 0.337, 0.196, 1 }
local CUR = { 0.851, 0.690, 0.424, 1 }
local GOOD_FILL = { 0.31, 0.56, 0.36, 1 }
local STOP_FILL = { 0.36, 0.30, 0.22, 1 }
local TICK = { 0.055, 0.043, 0.031, 0.9 }
local CLOCK = "Interface\\Icons\\INV_Misc_PocketWatch_01"

local bar

local function now() return GetTime and GetTime() or time() end

local function gameBar()
    return PlayerCastingBarFrame or CastingBarFrame
end

-- The game's own cast bar comes back (the switch went off, the batch ended).
function ns.ShowGameBar()
    local g = gameBar()
    if g and ns.hidGame then
        ns.hidGame = nil
        if g.SetAlpha then g:SetAlpha(1) end
    end
end

local function hideGameBar()
    local g = gameBar()
    if not (g and g.SetAlpha and g.GetAlpha) then return end
    ns.hidGame = true
    if (tonumber(g:GetAlpha()) or 0) > 0 then g:SetAlpha(0) end
end

function ns.PlaceBar()
    if not bar then return end
    bar:ClearAllPoints()
    local p = ns.db and ns.db.barPoint
    if p then bar:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 190) end
end

local function color(region, c) region:SetTextColor(c[1], c[2], c[3], 1) end

local function piece(track, c)
    local t = track:CreateTexture(nil, "ARTWORK")
    t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    return t
end

local function build()
    bar = CreateFrame("Frame", "GulliCraftProfitBar", UIParent)
    bar:SetSize(BAR_W, BAR_H)
    bar:SetFrameStrata("MEDIUM")
    S.HudPanel(bar)

    bar.icon = S.IconBox(bar, ICON, ns.OPT_ICON.bar)
    bar.icon:SetPoint("TOPLEFT", PAD, -12)

    -- the count, right to left: "12 of 40"
    bar.of = S.Text(bar, 28, S.TEXT, nil, "title")
    bar.of:SetPoint("TOPRIGHT", -PAD, -12)
    bar.word = S.Text(bar, 14, S.MUTED)
    bar.word:SetPoint("BOTTOMRIGHT", bar.of, "BOTTOMLEFT", -5, 4)
    bar.made = S.Text(bar, 28, S.TEXT, nil, "title")
    bar.made:SetPoint("BOTTOMRIGHT", bar.word, "BOTTOMLEFT", -5, -4)

    bar.name = S.Text(bar, 16, S.GOLD, nil, "bold")
    bar.name:SetPoint("TOPLEFT", bar.icon, "TOPRIGHT", 14, -4)
    bar.name:SetPoint("RIGHT", bar.made, "LEFT", -12, 0)
    bar.name:SetJustifyH("LEFT")
    bar.name:SetWordWrap(false)

    bar.left = S.Text(bar, 16, S.TIME, nil, "bold")
    bar.left:SetPoint("TOPRIGHT", -PAD, -48)
    bar.left:SetJustifyH("RIGHT")
    bar.sub = S.Text(bar, 13, S.MUTED)
    bar.sub:SetPoint("TOPLEFT", bar.icon, "TOPRIGHT", 14, -32)
    bar.sub:SetPoint("RIGHT", bar.left, "LEFT", -12, 0)
    bar.sub:SetJustifyH("LEFT")
    bar.sub:SetWordWrap(false)

    -- the whole batch: the crafts made, the one that runs in a lighter tone, a cut per craft
    bar.track = CreateFrame("Frame", nil, bar)
    bar.track:SetPoint("TOPLEFT", PAD, -76)
    bar.track:SetPoint("TOPRIGHT", -PAD, -76)
    bar.track:SetHeight(TRACK_H)
    S.Box(bar.track, S.INPUT, S.EDGE)
    bar.done = piece(bar.track, DONE)
    bar.done:SetPoint("TOPLEFT", 1, -1)
    bar.done:SetPoint("BOTTOMLEFT", 1, 1)
    bar.cur = piece(bar.track, CUR)
    bar.cur:SetPoint("TOPLEFT", bar.done, "TOPRIGHT")
    bar.cur:SetPoint("BOTTOMLEFT", bar.done, "BOTTOMRIGHT")
    bar.ticks = {}

    -- the craft that runs
    bar.thin = CreateFrame("Frame", nil, bar)
    bar.thin:SetPoint("TOPLEFT", bar.track, "BOTTOMLEFT", 0, -4)
    bar.thin:SetPoint("TOPRIGHT", bar.track, "BOTTOMRIGHT", 0, -4)
    bar.thin:SetHeight(THIN_H)
    S.Box(bar.thin, S.INPUT, S.EDGE)
    bar.thinFill = piece(bar.thin, CUR)
    bar.thinFill:SetPoint("TOPLEFT", 1, -1)
    bar.thinFill:SetPoint("BOTTOMLEFT", 1, 1)

    -- the line under them: a clock (or the state's dot) with its word, and the end on the right
    bar.clock = S.IconBox(bar, 14, CLOCK)
    bar.clock:SetPoint("BOTTOMLEFT", PAD, 9)
    bar.dot = S.Circle(bar, 8, S.GOOD, "OVERLAY", 1)
    bar.dot:SetPoint("CENTER", bar.clock, "CENTER")
    bar.right = S.Text(bar, 13, S.MUTED)
    bar.right:SetPoint("BOTTOMRIGHT", -PAD, 9)
    bar.right:SetJustifyH("RIGHT")
    bar.foot = S.Text(bar, 13, S.MUTED)
    bar.foot:SetPoint("LEFT", bar.clock, "RIGHT", 6, 0)
    bar.foot:SetPoint("RIGHT", bar.right, "LEFT", -12, 0)
    bar.foot:SetJustifyH("LEFT")
    bar.foot:SetWordWrap(false)

    S.Mover(bar, { label = L.P_bar,
        save = function(p, rp, x, y) ns.db.barPoint = { p, rp, x, y } end,
        reset = function() ns.db.barPoint = nil; ns.PlaceBar() end })
    bar:SetScript("OnUpdate", function() ns.TickBar() end)
    bar:Hide()
    ns.PlaceBar()
end

local function inner()
    return math.max(2, (tonumber(bar.track:GetWidth()) or (BAR_W - 2 * PAD)) - 2)
end

-- The cuts between the crafts; none for a long batch, which is one smooth bar.
local function setTicks(n)
    if rawget(bar, "tickCount") == (n or 0) then return end
    bar.tickCount = n or 0
    local w = inner()
    for i = 1, math.max(#bar.ticks, n and n - 1 or 0) do
        local t = bar.ticks[i]
        if n and i < n then
            if not t then
                t = bar.track:CreateTexture(nil, "OVERLAY")
                t:SetColorTexture(TICK[1], TICK[2], TICK[3], TICK[4])
                t:SetWidth(1)
                bar.ticks[i] = t
            end
            t:ClearAllPoints()
            local x = 1 + math.floor(w * i / n + 0.5)
            t:SetPoint("TOPLEFT", bar.track, "TOPLEFT", x, -1)
            t:SetPoint("BOTTOMLEFT", bar.track, "BOTTOMLEFT", x, 1)
            t:Show()
        elseif t then
            t:Hide()
        end
    end
end

local function setBars(v)
    local w = inner()
    local done = v.doneFrac or v.frac or 0
    local dw = w * done
    local cw = w * math.max(0, (v.frac or 0) - done)
    bar.done:SetShown(dw >= 1)
    bar.done:SetWidth(math.max(1, dw))
    -- a hidden piece still anchors the next one: the craft that runs starts where the made end
    bar.cur:ClearAllPoints()
    bar.cur:SetPoint("TOPLEFT", bar.track, "TOPLEFT", 1 + dw, -1)
    bar.cur:SetPoint("BOTTOMLEFT", bar.track, "BOTTOMLEFT", 1 + dw, 1)
    bar.cur:SetShown(cw >= 1)
    bar.cur:SetWidth(math.max(1, cw))
    local c = (v.tone == "good" and GOOD_FILL) or (v.tone == "warn" and STOP_FILL) or DONE
    bar.done:SetColorTexture(c[1], c[2], c[3], 1)
    local tw = w * (v.cast or 0)
    bar.thinFill:SetShown(tw >= 1)
    bar.thinFill:SetWidth(math.max(1, tw))
end

local function setTexts(v)
    bar.icon:SetIcon(v.icon or ns.OPT_ICON.bar)
    bar.name:SetText(v.name or "")
    bar.made:SetText(tostring(v.made or 0))
    bar.word:SetText(v.of and L.BAR_OF or "")
    bar.of:SetText(v.of and tostring(v.of) or "")
    bar.left:SetText(v.left or "")
    bar.sub:SetText(v.sub or "")
    local tone = (v.tone == "good" and S.GOOD) or (v.tone == "warn" and S.WARN) or nil
    bar.clock:SetShown(tone == nil)
    bar.dot:SetShown(tone ~= nil)
    if tone then bar.dot:SetVertexColor(tone[1], tone[2], tone[3], 1) end
    bar.foot:SetText(v.foot or "")
    color(bar.foot, tone or S.MUTED)
    bar.right:SetText(v.right or "")
    setTicks(v.ticks)
end

local function paint(state, texts)
    local v = ns.BarView(state)
    if texts then
        setTexts(v)
        bar.textAt = now()
    end
    setBars(v)
end

-- Every frame while the bar shows: the bars move, the texts follow a few times a second, and
-- the state changes when time alone ends it.
function ns.TickBar()
    if not bar then return end
    local state = ns.BarState()
    if state ~= rawget(bar, "state") then return ns.RefreshBar() end
    if state == "run" and ns.BarPref("barHide") then hideGameBar() end
    paint(state, now() - (rawget(bar, "textAt") or 0) >= TEXT_EVERY)
end

-- Shows, hides and repaints the bar; called on every cast and setting.
function ns.RefreshBar()
    if not ns.db then return end
    local state = ns.BarState()
    local show = state ~= nil or ns.moving
    if show and not bar then build() end
    if not bar then return end
    if state == "run" and ns.BarPref("barHide") then
        hideGameBar()
    elseif ns.hidGame then
        -- the game fades its own bar out first; then it is whole again for the next spell
        if state ~= "run" and C_Timer then
            C_Timer.After(1, function() if ns.BarState() ~= "run" then ns.ShowGameBar() end end)
        else
            ns.ShowGameBar()
        end
    end
    local was = bar:IsShown()
    bar.state = state
    if show then
        paint(state, true)
        if not was then
            bar:Show()
            if S.MotionIn then S.MotionIn(bar, 6) end
        end
    elseif was then
        bar:Hide()
    end
    if bar.SetMoving then bar:SetMoving(ns.moving) end
end

-- The bar for the hub's Unlock mode, built hidden when it is asked for.
function ns.BarFrame()
    if not bar and ns.db then build() end
    return bar
end
