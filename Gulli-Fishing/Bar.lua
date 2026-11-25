-- The fishing bar on the screen, in place of the game's cast bar while fishing: water that
-- drains while the bobber is out with a bobber on its edge, the catch for a moment, a quiet
-- "cast again" between casts, and the lure, the catches and the skill under it. Core.lua says
-- what it shows (ns.BarState); this file only draws it.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local BAR_W, BAR_H = 300, 86
local WATER = { 0.24, 0.58, 0.67, 1 }
local FLOAT_RED, FLOAT_WHITE = { 0.86, 0.30, 0.22, 1 }, { 0.95, 0.90, 0.80, 1 }
local SAMPLE = { left = 12, frac = 0.58 }

local bar

local function now() return GetTime and GetTime() or time() end

local function gameBar()
    return PlayerCastingBarFrame or CastingBarFrame
end

-- The game's own cast bar comes back (the switch went off, the cast ended).
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
    if InCombatLockdown and InCombatLockdown() then return end
    bar:ClearAllPoints()
    local p = ns.db and ns.db.barPoint
    if p then bar:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 190) end
end

local function chip(parent, icon)
    local c = CreateFrame("Frame", nil, parent)
    c:SetHeight(18)
    c.icon = S.IconBox(c, 16, icon)
    c.icon:SetPoint("LEFT")
    c.text = S.Text(c, 12, S.MUTED)
    c.text:SetPoint("LEFT", c.icon, "RIGHT", 5, 0)
    c.text:SetPoint("RIGHT")
    c.text:SetJustifyH("LEFT")
    c.text:SetWordWrap(false)
    return c
end

local function build()
    bar = CreateFrame("Frame", "GulliFishingBar", UIParent)
    bar:SetSize(BAR_W, BAR_H)
    bar:SetFrameStrata("MEDIUM")
    S.HudPanel(bar)
    bar.icon = S.IconBox(bar, 24, ns.OPT_ICON.cast)
    bar.icon:SetPoint("TOPLEFT", 9, -8)
    bar.right = S.Text(bar, 13, S.TEXT, "OUTLINE", "bold")
    bar.right:SetPoint("TOPRIGHT", -10, -13)
    bar.right:SetJustifyH("RIGHT")
    bar.name = S.Text(bar, 13, S.GOLD, nil, "bold")
    bar.name:SetPoint("LEFT", bar.icon, "RIGHT", 8, 0)
    bar.name:SetPoint("RIGHT", bar.right, "LEFT", -8, 0)
    bar.name:SetJustifyH("LEFT")
    bar.name:SetWordWrap(false)
    -- the water
    bar.track = CreateFrame("Frame", nil, bar)
    bar.track:SetPoint("TOPLEFT", 10, -40)
    bar.track:SetPoint("TOPRIGHT", -10, -40)
    bar.track:SetHeight(12)
    S.Box(bar.track, S.INPUT, S.EDGE, 6)
    bar.fill = CreateFrame("Frame", nil, bar.track)
    bar.fill:SetPoint("TOPLEFT", 1, -1)
    bar.fill:SetPoint("BOTTOMLEFT", 1, 1)
    S.Box(bar.fill, WATER, WATER, 5)
    bar.float = S.Circle(bar.track, 14, FLOAT_RED, "OVERLAY", 1)
    bar.floatTop = S.Circle(bar.track, 6, FLOAT_WHITE, "OVERLAY", 2)
    bar.floatTop:SetPoint("CENTER", bar.float, "CENTER")
    -- the lure, the catches, the skill
    local w = math.floor((BAR_W - 20) / 3)
    bar.chips = {}
    for i, icon in ipairs({ ns.OPT_ICON.lure, ns.OPT_ICON.catches, ns.OPT_ICON.skill }) do
        local c = chip(bar, icon)
        c:SetPoint("BOTTOMLEFT", 10 + (i - 1) * w, 8)
        c:SetWidth(w - 4)
        bar.chips[i] = c
    end
    S.Mover(bar, { label = L.TITLE,
        save = function(p, rp, x, y) ns.db.barPoint = { p, rp, x, y } end,
        reset = function() ns.db.barPoint = nil; ns.PlaceBar() end })
    bar:SetScript("OnUpdate", function(_, dt) ns.TickBar(dt) end)
    bar:Hide()
    ns.PlaceBar()
end

local function setFill(frac, color)
    local w = (tonumber(bar.track:GetWidth()) or (BAR_W - 20)) - 2
    frac = math.max(0, math.min(1, frac))
    local px = math.max(10, w * frac)
    bar.fill:SetShown(frac > 0)
    bar.fill:SetWidth(px)
    S.Fill(bar.fill, color)
    S.SetBorder(bar.fill, color)
    bar.float:SetShown(frac > 0)
    bar.floatTop:SetShown(frac > 0)
    -- the bobber rides the edge of the water, and bobs a little unless motion is reduced
    local bob = (S.Calm and S.Calm()) and 0 or math.sin(now() * 4) * 1.5
    bar.float:ClearAllPoints()
    bar.float:SetPoint("CENTER", bar.track, "LEFT", 1 + px, bob)
end

-- What the bar says in a state: { icon, name, right, frac, color, low }. For the tests too.
function ns.BarView(state, t)
    t = t or now()
    if state == "got" then
        local g = ns.got
        return { icon = ns.ItemIcon(g.id), name = ns.ItemName(g.id), right = "+" .. g.n, rcolor = S.GOOD,
                 frac = 1, color = S.GOLD_DIM }
    elseif state == "cast" then
        local c = ns.cast
        local left = math.max(0, c.finish - t)
        local low = left <= ns.BAR_LOW
        return { icon = ns.OPT_ICON.cast, name = L.TITLE, right = L.SEC:format(math.ceil(left)),
                 rcolor = low and S.WARN or S.TEXT, low = low,
                 frac = left / math.max(1, c.finish - c.start), color = low and S.WARN or WATER }
    elseif state == "idle" then
        return { icon = ns.OPT_ICON.cast, name = L.BAR_AGAIN, right = ns.CastKeyText() or "", rcolor = S.MUTED,
                 frac = 0, color = WATER }
    end
    return { icon = ns.OPT_ICON.cast, name = L.TITLE, right = L.SEC:format(SAMPLE.left), rcolor = S.TEXT,
             frac = SAMPLE.frac, color = WATER }
end

local function paint(state)
    local v = ns.BarView(state)
    bar.icon:SetIcon(v.icon)
    bar.name:SetText(v.name)
    bar.right:SetText(v.right)
    bar.right:SetTextColor(v.rcolor[1], v.rcolor[2], v.rcolor[3], 1)
    setFill(v.frac, v.color)
    local lure, lc = ns.LureText()
    bar.chips[1].text:SetText(lure)
    bar.chips[1].text:SetTextColor(lc[1], lc[2], lc[3], 1)
    bar.chips[2].text:SetText(tostring(ns.s.catches))
    bar.chips[3].text:SetText((ns.SkillText()))
end

-- Every frame while the bar shows: the water, and the state when it changes by time alone.
function ns.TickBar()
    if not bar then return end
    local state = ns.BarState()
    if state ~= bar.state and not ns.moving then return ns.RefreshBar() end
    if state == "cast" and ns.db.hideCast then hideGameBar() end
    paint(state)
end

-- Shows, hides and repaints the bar; called on every cast, catch and setting.
function ns.RefreshBar()
    if not ns.db or not ns.s then return end
    local state = ns.BarState()
    local show = state ~= nil or ns.moving
    if show and not bar then build() end
    if not bar then return end
    if state ~= "cast" and ns.hidGame then
        -- the game fades its own bar out first; then it is whole again for the next spell
        if C_Timer then C_Timer.After(1, function() if ns.BarState() ~= "cast" then ns.ShowGameBar() end end)
        else ns.ShowGameBar() end
    end
    local was = bar:IsShown()
    bar.state = state
    if show then
        paint(state)
        if not was then
            bar:Show()
            if S.MotionIn then S.MotionIn(bar, 6) end
        end
    elseif was then
        bar:Hide()
    end
    if bar.SetMoving then bar:SetMoving(ns.moving and not (InCombatLockdown and InCombatLockdown())) end
end

-- The bar for the hub's Unlock mode, built hidden when it is asked for.
function ns.BarFrame()
    if not bar and ns.db then build() end
    return bar
end
