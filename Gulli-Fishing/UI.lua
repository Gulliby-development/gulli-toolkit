-- The secure cast buttons (the double-click's and the cast key's), the lure notice and the
-- window: a strip that says what to do now, three tiles (catches, the lure, the skill), the
-- "How to fish" steps, what was caught this session, and the settings.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, tiles, tabs, caughtList, castBtn, keyBtn, footer
local status, howto, howRow, listCard, layoutTop
local pages = {}
local TONE = { good = "GOOD", warn = "WARN", muted = "MUTED" }
local MOUSE_ART = "Interface\\AddOns\\Gulli-Fishing\\Art\\Mouse"

-- The button a double right-click clicks: Fishing, or the lure onto the pole (attributes set by
-- ns.Arm, out of combat only).
function ns.CastButton()
    if castBtn then return castBtn end
    castBtn = CreateFrame("Button", "GulliFishingCast", UIParent, "SecureActionButtonTemplate")
    castBtn:SetSize(1, 1)
    castBtn:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 10, -10)
    castBtn:RegisterForClicks("AnyUp", "AnyDown")
    castBtn:SetScript("PostClick", function() ns.Disarm() end)
    castBtn:Show()
    return castBtn
end

-- A lure is missing: a Gulli HUD notice with the lure's own icon.
function ns.OnLureMissing(id, text)
    if S.Toast then
        S.Toast({ key = "Fishing:lure", icon = ns.ItemIcon(id), title = L.LURE_TITLE, text = text, kind = "warn", seconds = 8 })
    else
        print(L.TITLE .. ": " .. text)
    end
end

-- The button the cast key clicks. Its action is set again before each press out of a fight, so
-- a pole that lost its lure gets one first.
function ns.KeyCastButton()
    if keyBtn then return keyBtn end
    keyBtn = CreateFrame("Button", "GulliFishingKey", UIParent, "SecureActionButtonTemplate")
    keyBtn:SetSize(1, 1)
    keyBtn:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 20, -10)
    keyBtn:RegisterForClicks("AnyUp", "AnyDown")
    keyBtn:SetScript("PreClick", function(self) ns.SetAction(self) end)
    keyBtn:Show()
    return keyBtn
end

-- "12 min" left on the pole, or a dash.
function ns.LureText()
    local left = ns.LureLeft()
    if left > 0 then return ns.Span(left), S.GOOD end
    if ns.HasPole() then return L.NO_LURE, S.WARN end
    return "-", S.MUTED
end

-- The skill tile: "187/225".
function ns.SkillText()
    local rank, cap = ns.Skill()
    if not rank then return "-", S.MUTED end
    return (cap and cap > 0) and (rank .. "/" .. cap) or tostring(rank), S.TEXT
end

-- The cast key button: a click waits for a key or a mouse button, a right-click clears it.
local MODIFIER = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true }
local MOUSE = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }

local function mods()
    return (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "") .. (IsShiftKeyDown() and "SHIFT-" or "")
end

local function capture(b, on)
    b.capturing = on
    b:EnableKeyboard(on)
    if b.SetPropagateKeyboardInput and not InCombatLockdown() then b:SetPropagateKeyboardInput(not on) end
    b:SetText(on and L.KEY_PRESS or ns.CastKeyText() or L.KEY_NONE)
end

function ns.KeyButton(parent)
    local b = S.Button(parent, 150, 28)
    b:RegisterForClicks("AnyUp")
    b:SetScript("OnClick", function(self, mouse)
        if self.capturing and MOUSE[mouse] then
            ns.SetCastKey(mods() .. MOUSE[mouse])
            capture(self, false)
        elseif mouse == "RightButton" then
            ns.SetCastKey(nil)
            capture(self, false)
        elseif mouse == "LeftButton" then
            capture(self, not self.capturing)
        end
    end)
    b:SetScript("OnKeyDown", function(self, key)
        if not self.capturing or MODIFIER[key] then return end
        if key ~= "ESCAPE" then ns.SetCastKey(mods() .. key) end
        capture(self, false)
    end)
    b:SetScript("OnShow", function(self) capture(self, false) end)
    capture(b, false)
    return b
end

-- The strip on top: a dot, what to do now and a line under it.
local function statusStrip(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(48)
    S.Box(f, S.SURFACE, S.CARD_EDGE, S.R_LG)
    S.Depth(f, S.R_LG)
    f.dot = S.Circle(f, 10, S.GOOD, "ARTWORK")
    f.dot:SetPoint("LEFT", S.INSET, 0)
    f.title = S.Text(f, 13, S.GOOD, nil, "bold")
    f.title:SetPoint("TOPLEFT", S.INSET + 20, -8)
    f.title:SetPoint("RIGHT", -S.INSET, 0)
    f.title:SetJustifyH("LEFT")
    f.title:SetWordWrap(false)
    f.sub = S.Text(f, 12, S.MUTED)
    f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
    f.sub:SetPoint("RIGHT", -S.INSET, 0)
    f.sub:SetJustifyH("LEFT")
    f.sub:SetWordWrap(false)
    function f:Set(title, sub, tone)
        local c = S[TONE[tone] or "MUTED"]
        self.title:SetText(title)
        self.title:SetTextColor(c[1], c[2], c[3], 1)
        self.dot:SetVertexColor(c[1], c[2], c[3], 1)
        self.sub:SetText(sub or "")
    end
    return f
end

-- One step of the "How to fish" card: its number in a ring, a title, what to do, and a line
-- with its state now. `side` (a button, a picture) sits at its right.
local STEP_H = { 70, 96, 84 }
local function stepRow(parent, i, sideWidth)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(STEP_H[i])
    r.ring = S.Circle(r, 24, S.GOLD_DIM, "BACKGROUND", 1)
    r.ring:SetPoint("TOPLEFT", 0, -4)
    r.num = S.Text(r, 13, { 0.10, 0.08, 0.05, 1 }, nil, "bold")
    r.num:SetShadowColor(0, 0, 0, 0)
    r.num:SetPoint("CENTER", r.ring, "CENTER")
    r.num:SetText(tostring(i))
    r.title = S.Text(r, 14, S.TEXT, nil, "bold")
    r.title:SetPoint("TOPLEFT", 34, -4)
    r.title:SetPoint("RIGHT", -(sideWidth + 8), 0)
    r.title:SetJustifyH("LEFT")
    r.title:SetWordWrap(false)
    r.desc = S.Text(r, 12, S.MUTED)
    r.desc:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -3)
    r.desc:SetPoint("RIGHT", -(sideWidth + 8), 0)
    r.desc:SetJustifyH("LEFT")
    r.desc:SetJustifyV("TOP")
    r.desc:SetWordWrap(true)
    r.state = S.Text(r, 12, S.MUTED)
    r.state:SetPoint("TOPLEFT", r.desc, "BOTTOMLEFT", 0, -3)
    r.state:SetPoint("RIGHT", -(sideWidth + 8), 0)
    r.state:SetJustifyH("LEFT")
    r.state:SetWordWrap(false)
    if i > 1 then
        r.line = S.Divider(r, S.LINE)
        r.line:SetPoint("TOPLEFT", 0, 6)
        r.line:SetPoint("TOPRIGHT", 0, 6)
        r.line:SetHeight(1)
    end
    function r:Set(step)
        local c = step.done and S.GOOD or S.GOLD_DIM
        self.ring:SetVertexColor(c[1], c[2], c[3], 1)
        self.title:SetText(L["STEP_" .. step.key])
        local desc = L[step.desc or ("STEP_" .. step.key .. "_D")]
        if step.desc and step.arg and desc:find("%%s") then desc = desc:format(step.arg) end
        self.desc:SetText(desc)
        local st = step.state and L[step.state] or ""
        if step.state and step.arg and st:find("%%s") then st = st:format(step.arg) end
        local tc = S[TONE[step.tone] or "MUTED"]
        self.state:SetText(st)
        self.state:SetTextColor(tc[1], tc[2], tc[3], 1)
    end
    return r
end

local HOW_H = 36 + STEP_H[1] + STEP_H[2] + STEP_H[3] + 12 + S.INSET

local function howCard(parent)
    local card = S.Card(parent, L.SEC_HOW)
    card:SetHeight(HOW_H)
    card.steps = {}
    local y = 0
    for i = 1, 3 do
        local r = stepRow(card.body, i, i == 1 and 110 or i == 2 and 64 or 0)
        r:SetPoint("TOPLEFT", 0, -y)
        r:SetPoint("TOPRIGHT", 0, -y)
        y = y + STEP_H[i] + 6
        card.steps[i] = r
    end
    -- step 1: the pole from the bags into the hand
    card.equip = S.Primary(S.FitButton(card.steps[1], L.EQUIP, 28, 90))
    card.equip:SetPoint("TOPRIGHT", 0, -8)
    card.equip:SetScript("OnClick", function()
        if ns.EquipPole() and C_Timer then C_Timer.After(0.5, function() ns.Refresh() end) end
        ns.Refresh()
    end)
    -- step 2: the right mouse button, twice
    card.mouse = card.steps[2]:CreateTexture(nil, "ARTWORK")
    card.mouse:SetTexture(MOUSE_ART)
    card.mouse:SetSize(48, 48)
    card.mouse:SetPoint("TOPRIGHT", 0, -6)
    card.twice = S.Text(card.steps[2], 13, S.GOLD, nil, "bold")
    card.twice:SetPoint("TOP", card.mouse, "BOTTOM", 0, -2)
    card.twice:SetText("x2")
    -- folds away once the player knows
    card.hide = S.FitButton(card, L.HOW_HIDE, 24, 60)
    card.hide:SetPoint("TOPRIGHT", -S.INSET, -6)
    card.hide:SetScript("OnClick", function() ns.howto = false; ns.Refresh() end)
    return card
end

-- The folded card: one row at the bottom of the catch page.
local function howFolded(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(44)
    S.Box(f, S.SURFACE, S.CARD_EDGE, S.R_LG)
    S.Depth(f, S.R_LG)
    f.icon = S.IconBox(f, 26, ns.OPT_ICON.cast)
    f.icon:SetPoint("LEFT", S.INSET, 0)
    f.show = S.FitButton(f, L.HOW_SHOW, 28, 80)
    f.show:SetPoint("RIGHT", -S.INSET, 0)
    f.show:SetScript("OnClick", function() ns.howto = true; ns.Refresh() end)
    f.title = S.Text(f, 13)
    f.title:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 10, 1)
    f.title:SetPoint("RIGHT", f.show, "LEFT", -8, 0)
    f.title:SetJustifyH("LEFT")
    f.title:SetWordWrap(false)
    f.title:SetText(L.SEC_HOW)
    f.sub = S.Text(f, 12, S.MUTED)
    f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -2)
    f.sub:SetPoint("RIGHT", f.show, "LEFT", -8, 0)
    f.sub:SetJustifyH("LEFT")
    f.sub:SetWordWrap(false)
    f.sub:SetText(L.HOW_SUB)
    return f
end

local function catchPage(body)
    local p = CreateFrame("Frame", nil, body)
    howto = howCard(p)
    howRow = howFolded(p)
    howRow:SetPoint("BOTTOMLEFT")
    howRow:SetPoint("BOTTOMRIGHT")
    listCard = S.Card(p, L.SEC_CAUGHT)
    caughtList = S.List(listCard.body, 34, function(r)
        r.icon = S.IconBox(r, 24)
        r.icon:SetPoint("LEFT", 2, 0)
        r.count = S.Text(r, 13)
        r.count:SetPoint("RIGHT", -4, 0)
        r.count:SetJustifyH("RIGHT")
        r.name = S.Text(r, 12)
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 10, 0)
        r.name:SetPoint("RIGHT", r.count, "LEFT", -8, 0)
        r.name:SetWordWrap(false)
    end, function(r, it)
        r.icon:SetIcon(ns.ItemIcon(it.id))
        r.name:SetText(ns.ItemName(it.id))
        r.count:SetText("+" .. it.n)
    end)
    caughtList:SetAllPoints()
    return p
end

local function settingsPage(body, width)
    local page = S.ScrollPage(body, width)
    local p = page.inner
    local st = S.Stack(p)
    local function row(key)
        if key == "castKey" then
            return { L.OPT_KEY, L.OPT_KEY_TIP, control = ns.KeyButton(p), icon = ns.OPT_ICON.castKey }
        end
        local up = key:upper()
        local tip = L["OPT_" .. up .. "_TIP"]
        if key == "interact" then
            local k = ns.InteractKey()
            tip = tip .. " " .. (k and L.INTERACT_IS:format(k) or L.INTERACT_UNSET)
        end
        return { L["OPT_" .. up], tip, function() return ns.db[key] end,
                 function(v) ns.SetPref(key, v) end, icon = ns.OPT_ICON[key] }
    end
    for _, sec in ipairs({ { L.SEC_CAST, { "cast", "castKey", "lure" } }, { L.SEC_CATCH, { "interact", "loot" } },
                           { L.SEC_SOUND, { "loud", "mute", "remind" } }, { L.SEC_SCREEN, { "hideCast" } } }) do
        local rows = {}
        for _, k in ipairs(sec[2]) do rows[#rows + 1] = row(k) end
        local card, h = S.SettingsCard(p, sec[1], rows)
        st:Add(card, h)
    end
    page:SetContent(st:Height())
    return page
end

-- Whether the steps show whole: before the first catch, or when the player asked for them.
function ns.HowtoOpen()
    if ns.howto ~= nil then return ns.howto end
    return ns.s.catches == 0
end

-- The tiles show once there is a catch; the steps fold to a row then.
local function layout()
    local caught = ns.s.catches > 0
    local open = ns.HowtoOpen()
    local y = 48 + S.GAP
    tiles:SetShown(caught)
    if caught then
        tiles:ClearAllPoints()
        tiles:SetPoint("TOPLEFT", 0, -y)
        y = y + 62 + S.GAP
    end
    if layoutTop ~= y then
        layoutTop = y
        tabs.frame:ClearAllPoints()
        tabs.frame:SetPoint("TOPLEFT", 0, -y)
        for _, p in ipairs(pages) do
            p:ClearAllPoints()
            p:SetPoint("TOPLEFT", 0, -(y + 30 + S.GAP))
            p:SetPoint("BOTTOMRIGHT")
        end
    end
    howto:SetShown(open)
    howRow:SetShown(not open)
    howto.hide:SetShown(caught)
    -- the open steps take the page; the catch comes back when they fold
    listCard:SetShown(caught and not open)
    howto:ClearAllPoints()
    howto:SetPoint("TOPLEFT")
    howto:SetPoint("TOPRIGHT")
    listCard:ClearAllPoints()
    listCard:SetPoint("TOPLEFT")
    listCard:SetPoint("BOTTOMRIGHT", 0, 44 + S.GAP)
end

local function paintWindow()
    layout()
    status:Set(ns.Status())
    local t = tiles.tiles
    local rate = ns.PerHour()
    t[1]:Set(tostring(ns.s.catches), ns.s.catches > 0 and S.TEXT or S.MUTED, rate and L.ST_RATE:format(rate) or L.ST_CATCHES)
    t[2]:Set(ns.LureText())
    t[3]:Set(ns.SkillText())
    local steps = ns.Steps()
    for i, r in ipairs(howto.steps) do r:Set(steps[i]) end
    howto.equip:SetShown(steps[1].equip ~= nil)
    howto.mouse:SetAlpha(ns.db.cast and 1 or 0.35)
    howto.twice:SetAlpha(ns.db.cast and 1 or 0.35)
    caughtList:SetData(ns.Caught())
    if not ns.footNote then footer:SetStatus(ns.SessionLine()) end
end

function ns.Refresh()
    if not ns.s or not ns.db then return end
    if ns.RefreshBar then ns.RefreshBar() end
    if frame and frame:IsShown() then paintWindow() end
end

local function build()
    frame = S.Window("GulliFishingFrame", L.TITLE, S.NARROW_W, S.DOCK_H)
    local body, width = frame.body, frame.inner[1]
    footer = S.Footer(frame)
    local new = S.Primary(S.FitButton(frame, L.NEW_SESSION, 30, 120))
    new:SetScript("OnClick", function()
        ns.Start()
        ns.footNote = true
        footer:SetStatus(L.NEW_SESSION_DONE)
        ns.Refresh()
        ns.footNote = nil
    end)
    footer:Add(new)
    status = statusStrip(body)
    status:SetPoint("TOPLEFT")
    status:SetPoint("TOPRIGHT")
    tiles = S.StatRow(body, { L.ST_CATCHES, L.ST_LURE, L.ST_SKILL }, 62,
        { ns.OPT_ICON.catches, ns.OPT_ICON.lure, ns.OPT_ICON.skill })
    tiles:Layout(width)
    tabs = S.PageTabs(body, { L.TAB_CATCH, L.TAB_SETTINGS }, nil, function(i)
        for j, p in ipairs(pages) do p:SetShown(j == i) end
        ns.Refresh()
    end, nil, { S.TAB.list, S.TAB.settings })
    pages[1] = catchPage(body)
    pages[2] = settingsPage(body, width)
    for i, p in ipairs(pages) do p:SetShown(i == 1) end
    frame:HookScript("OnShow", function() ns.howto = nil; ns.Refresh() end)
end

function ns.Toggle()
    if S.ToggleWindow(ns.Window()) then ns.Refresh() end
end

-- The window, for the hub (/gulli) to show inside it.
function ns.Window()
    if not frame then build() end
    return frame
end

-- For the tests and the previews.
function ns.Parts() return frame, tiles, pages, tabs, status, howto end
