local _, ns = ...
local L = ns.L
local S = ns.Skin

-- The window has three pages: Mobs (the search switch and the list, one row per mob, and the
-- zone's rares), Found (the last finds, with a map pin) and Settings. A find shows a
-- card with the mob's model and a secure Target button, also on a key. Every change is saved
-- at once; the search itself lives in Core.lua.
local W = S.NARROW_W
local BUTTON = "GulliMobFinderTarget"

local frame, pageTabs, pages, status
local mobList, mobEmpty, histList, histEmpty, addEdit, keyButton
local card, flash
local pendingMacro, repeater

local function ago(t)
    local d = (time and time() or 0) - (t or 0)
    if d < 3600 then return L.AGO_MIN:format(math.max(1, math.floor(d / 60))) end
    if d < 86400 then return L.AGO_HOUR:format(math.floor(d / 3600)) end
    return L.AGO_DAY:format(math.floor(d / 86400))
end

---- The find card --------------------------------------------------------------

local function stopRepeat()
    if repeater then repeater:Cancel(); repeater = nil end
end

-- The Target button lives on UIParent, not on the card: the game blocks showing a frame with a
-- secure child in combat, and a find often comes in combat. It shows and hides only out of combat.
local targetPending

-- The card is wider than a notice and keeps its buttons on a row of their own under the name,
-- so a long name and its line never share the width with Tell, Pin and Target.
local CARD_W, CARD_H, CARD_PAD = 420, 100, 12
local cardMeta, cardWaiting

local function layoutCard()
    if not card or not rawget(card, "target") then return end
    card:SetSize(CARD_W, CARD_H)
    card.ico:ClearAllPoints()
    card.ico:SetPoint("TOPLEFT", 13, -12)
    card.title:ClearAllPoints()
    -- Without a grey line the name sits in the middle of the icon.
    local t = card.text:GetText()
    if t and t ~= "" and t ~= " " then
        card.title:SetPoint("TOPLEFT", card.ico, "TOPRIGHT", 10, -2)
    else
        card.title:SetPoint("LEFT", card.ico, "RIGHT", 10, 0)
    end
    card.title:SetPoint("RIGHT", card.close, "LEFT", -4, 0)
    card.text:ClearAllPoints()
    card.text:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -4)
    card.text:SetPoint("RIGHT", card.close, "LEFT", -4, 0)
    -- Target sits at the right end of the row while it shows; in a fight it waits, and the other
    -- buttons take its place instead of leaving a gap.
    local on = card.target:IsShown() and (tonumber((card.target:GetAlpha())) or 1) > 0
    card.target:ClearAllPoints()
    card.target:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -CARD_PAD, CARD_PAD)
    local last = on and card.target or nil
    for _, b in ipairs(card.buttons) do
        if b:IsShown() then
            b:ClearAllPoints()
            if last then b:SetPoint("RIGHT", last, "LEFT", -6, 0)
            else b:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -CARD_PAD, CARD_PAD) end
            last = b
        end
    end
    if card.timer:IsShown() then card.timer:SetWidth(CARD_W - 2 * S.R_LG) end
end
ns.LayoutCard = layoutCard

-- The grey line under the name: what the card knows, and the wait for Target in a fight.
local function cardLine()
    local parts = {}
    for _, p in ipairs(cardMeta or {}) do parts[#parts + 1] = p end
    if cardWaiting then parts[#parts + 1] = L.AFTER_COMBAT end
    card.text:SetText(table.concat(parts, S.DOT))
end

local function showTarget(on)
    if not card then return end
    if InCombatLockdown() then
        targetPending = on
        if not on then pcall(card.target.SetAlpha, card.target, 0) end
        return
    end
    targetPending = nil
    card.target:SetAlpha(1)
    card.target:SetShown(on and true or false)
    layoutCard()
end

local function hideCard()
    stopRepeat()
    if card then card:Hide() end
end
ns.HideCard = hideCard

-- The Target button runs /targetexact; its macro may change only out of combat.
local function aimTarget(name)
    local macro = name and ns.TargetMacro(name) or nil
    if InCombatLockdown() then pendingMacro = macro or false; return false end
    pendingMacro = nil
    card.target:SetAttribute("type", "macro")
    card.target:SetAttribute("macrotext", macro)
    return true
end

-- Below the top of the screen, where the XP bar, guide arrows and the notice stack sit.
local CARD_POINT = { "TOP", 0, -200 }

local function placeCard()
    local p = ns.db.cardPoint or CARD_POINT
    card:ClearAllPoints()
    card:SetPoint(p[1], UIParent, p[4] or p[1], p[2], p[3])
end

local function buildCard()
    -- The Gulli HUD notice card, at its own place (it is movable) so it stays above the others.
    card = S.ToastFrame("GulliMobFinderCard")
    card:SetFrameStrata("HIGH")
    card:SetSize(CARD_W, CARD_H)
    -- The mob's name is the card's title: a name, so gold.
    S.SetFont(card.title, 15, nil, "bold")
    card.title:SetTextColor(S.GOLD[1], S.GOLD[2], S.GOLD[3], 1)
    placeCard()
    S.Mover(card, { label = L.TITLE, save = function(p, rp, x, y) ns.db.cardPoint = { p, x, y, rp } end,
        reset = function() ns.db.cardPoint = nil; placeCard() end })
    card:HookScript("OnHide", function() stopRepeat(); showTarget(false) end)

    -- The secure Target button, drawn like S.Primary, with the key on it.
    local t = CreateFrame("Button", BUTTON, UIParent, "SecureActionButtonTemplate")
    t:SetSize(96, 28)
    t:SetFrameStrata("HIGH")
    t:SetFrameLevel((tonumber((card:GetFrameLevel())) or 0) + 10)
    t:SetPoint("RIGHT", card, "RIGHT", -32, 0)
    S.Box(t, S.Accent(), S.EDGE, S.R_MD)
    t.text = S.Text(t, 12, S.BG)
    t.text:SetShadowColor(0, 0, 0, 0)
    t.text:SetPoint("CENTER")
    t:RegisterForClicks("AnyUp", "AnyDown")
    t:SetAttribute("type", "macro")
    t:HookScript("OnClick", function() stopRepeat() end)
    t:Hide()
    card.target = t
end

-- The card while the hub's Unlock mode places it: a sample find with its mover.
function ns.MoveCard(on)
    if not ns.db then return end
    ns.movingCard = on and true or nil
    -- The card holds the secure Target button: the game refuses to show or hide it in a fight.
    if InCombatLockdown and InCombatLockdown() then return end
    if not card then buildCard() end
    card:SetMoving(on)
    if on then
        cardMeta, cardWaiting = { L.CARD_D }, nil
        card:Set({ icon = "Interface\\Icons\\Ability_Hunter_SniperShot", title = L.TITLE, text = L.CARD_D,
                   kind = "bad" })
        layoutCard()
    else
        card:Hide()
    end
end

function ns.CardFrame()
    if not card and ns.db then buildCard() end
    return card
end

-- The edges of the screen flash red for a moment.
local function doFlash()
    if not flash then
        flash = CreateFrame("Frame", nil, UIParent)
        flash:SetAllPoints()
        flash:SetFrameStrata("FULLSCREEN_DIALOG")
        flash:EnableMouse(false)
        for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 40 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 40 },
                             { "TOPLEFT", "BOTTOMLEFT", 40 }, { "TOPRIGHT", "BOTTOMRIGHT", 40 } }) do
            local t = flash:CreateTexture(nil, "OVERLAY")
            t:SetColorTexture(S.BAD[1], S.BAD[2], S.BAD[3], 0.45)
            t:SetPoint(e[1])
            t:SetPoint(e[2])
            if e[3] then t:SetWidth(e[3]) else t:SetHeight(e[4]) end
        end
        flash:SetScript("OnUpdate", function(self, elapsed)
            self.left = (self.left or 0) - elapsed
            self:SetAlpha(math.max(0, self.left / 1.5))
            if self.left <= 0 then self:Hide() end
        end)
    end
    flash.left = 1.5
    flash:SetAlpha(1)
    flash:Show()
end

local function classification(unit)
    local c = UnitClassification and UnitClassification(unit)
    if c == "rareelite" then return L.RARE_ELITE end
    if c == "rare" then return L.RARE end
    if c == "elite" or c == "worldboss" then return L.ELITE end
    return nil
end

-- A find: the card (model, name, level, kind) with Target on the key, the flash, the repeat.
function ns.ShowFind(hits)
    local h = hits and hits[1]
    if not h or not ns.db then return end
    if ns.db.flash then doFlash() end
    if not card then buildCard() end
    card.hit = h
    local parts = {}
    local portrait
    if h.unit and UnitExists(h.unit) then
        local lvl = UnitLevel and UnitLevel(h.unit)
        if issecretvalue and issecretvalue(lvl) then lvl = nil end
        if lvl then parts[#parts + 1] = L.LEVEL:format(lvl > 0 and tostring(lvl) or "??") end
        parts[#parts + 1] = classification(h.unit)
        portrait = h.unit
    end
    if h.vignette then parts[#parts + 1] = L.ON_MAP end
    if #hits > 1 then parts[#parts + 1] = L.MORE:format(#hits - 1) end
    cardMeta = parts
    cardWaiting = not aimTarget(h.name) or nil
    local key = ns.db.key and S.ShortKey(ns.db.key)
    card.target.text:SetText(L.TARGET .. (key and key ~= "" and ("  " .. S.Hex(S.HEAD) .. key .. "|r") or ""))
    card.target:SetWidth(math.max(80, math.floor((tonumber((card.target.text:GetStringWidth())) or 60) + 24)))
    local buttons = {}
    if IsInGroup and IsInGroup() then
        buttons[#buttons + 1] = { text = L.TELL_BTN, keep = true,
            onClick = function() if card.hit then ns.TellGroup(card.hit.name) end end }
    end
    buttons[#buttons + 1] = { text = L.PIN, keep = true, onClick = function()
        local last = ns.db.history[1]
        if last then ns.Pin(last) end
    end }
    card:Set({ icon = "Interface\\Icons\\Ability_Hunter_SniperShot", portrait = portrait, title = h.name,
               text = " ", kind = "bad", buttons = buttons, seconds = ns.CARD_SECONDS })
    cardLine()
    showTarget(true)
    layoutCard()
    stopRepeat()
    if ns.db.repeatSound and C_Timer and C_Timer.NewTicker then
        repeater = C_Timer.NewTicker(3, function() ns.PlayAlert() end, 10)
    end
end

---- Key ----------------------------------------------------------------------------

local keyOwner

function ns.ApplyKey()
    if InCombatLockdown() then return end
    if not card then buildCard() end
    keyOwner = keyOwner or CreateFrame("Frame")
    ClearOverrideBindings(keyOwner)
    if ns.db.key then S.BindKey(keyOwner, true, ns.db.key, BUTTON, "LeftButton") end
end

local MODIFIER = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true }

local function keyText()
    local key = ns.db.key
    return key and (GetBindingText and GetBindingText(key) or key) or L.KEY_NONE
end

local function capture(b, on)
    b.capturing = on
    b:EnableKeyboard(on)
    if b.SetPropagateKeyboardInput and not InCombatLockdown() then b:SetPropagateKeyboardInput(not on) end
    b:SetText(on and L.KEY_PRESS or keyText())
end

local function makeKeyButton(parent)
    local b = S.Button(parent, 150, 28)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, mouse)
        if mouse == "RightButton" then
            ns.db.key = nil
            capture(self, false)
            ns.ApplyKey()
        else
            capture(self, not self.capturing)
        end
    end)
    b:SetScript("OnKeyDown", function(self, key)
        if not self.capturing or MODIFIER[key] then return end
        if key ~= "ESCAPE" then
            local mods = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
                .. (IsShiftKeyDown() and "SHIFT-" or "")
            ns.db.key = S.KeyBase(mods .. key)
            ns.ApplyKey()
        end
        capture(self, false)
    end)
    b:SetScript("OnShow", function(self) capture(self, false) end)
    return b
end

---- Refresh ------------------------------------------------------------------------

local function mobItems()
    local items = {}
    for i, n in ipairs(ns.db.names) do items[#items + 1] = { name = n, i = i } end
    local ids = {}
    for id, name in pairs(ns.db.ids) do ids[#ids + 1] = { name = name, id = id } end
    table.sort(ids, function(a, b) return a.name < b.name end)
    for _, e in ipairs(ids) do items[#items + 1] = e end
    return items
end

-- Shows the saved settings and the search state.
function ns.Refresh()
    if not frame then return end
    local d = ns.db
    for _, r in ipairs(frame.switches) do if r.Refresh then r:Refresh() end end
    local n = #d.names
    for _ in pairs(d.ids) do n = n + 1 end
    local on = d.enabled and not ns.paused
    local text = on and L.SUMMARY:format(n) or L.STATUS_OFF
    if ns.lastFound then
        text = text .. "\n" .. L.STATUS_LAST:format(table.concat(ns.lastFound.names, ", "))
    end
    status:SetText(text)
    local c = on and S.GOOD or S.MUTED
    status:SetTextColor(c[1], c[2], c[3], 1)
    local items = mobItems()
    mobList:SetData(items)
    mobEmpty:SetShown(#items == 0)
    histList:SetData(d.history)
    histEmpty:SetShown(#d.history == 0)
end

ns.OnState = ns.Refresh
ns.OnFound = function(hits)
    ns.ShowFind(hits)
    ns.Refresh()
end

---- Adding from the game world ------------------------------------------------------

local ADD_ICON = "Interface\\Icons\\Ability_Hunter_SniperShot"

-- A mob added with Alt+click or from the unit menu: a notice with Undo.
function ns.OnQuick(name, new)
    local buttons
    if new then
        buttons = { { text = L.UNDO, onClick = function()
            ns.RemoveName(name)
            ns.Refresh()
        end } }
    end
    S.Toast({ key = "add", icon = ADD_ICON, title = name, text = new and L.QUICK_ADDED or L.QUICK_HAVE,
              kind = new and "good" or nil, buttons = buttons, seconds = 6 })
    ns.Refresh()
end

-- "Look for this mob" in the menu of the target and focus frames.
function ns.UnitMenu(_, root, context)
    if ns.paused or not ns.db then return end
    local unit = context and context.unit
    if not unit then return end
    local name, guid = ns.Addable(unit)
    if not name then return end
    root:CreateDivider()
    if ns.OnList(name) then
        root:CreateButton(L.MENU_REMOVE, function()
            ns.RemoveName(name)
            ns.Refresh()
        end)
    else
        root:CreateButton(L.MENU_ADD, function() ns.OnQuick(name, ns.AddName(name, guid)) end)
    end
end

if Menu and Menu.ModifyMenu then
    for _, tag in ipairs({ "MENU_UNIT_TARGET", "MENU_UNIT_FOCUS" }) do
        pcall(Menu.ModifyMenu, tag, function(...) return ns.UnitMenu(...) end)
    end
end

---- Building -----------------------------------------------------------------------

-- A button that steps through values (right click: back).
local function cycle(parent, get, set, values, text, width)
    local b = S.Button(parent, width or 120, 28)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    function b:Refresh() self:SetText(text(get())) end
    b:SetScript("OnClick", function(self, mouse)
        local at = 1
        for i, v in ipairs(values) do if v == get() then at = i end end
        at = (at - 1 + (mouse == "RightButton" and -1 or 1)) % #values + 1
        set(values[at])
        self:Refresh()
    end)
    b:Refresh()
    return b
end

local function switch(key, label, desc, icon, onSet)
    return { label, desc, function() return ns.db[key] end, function(on)
        ns.db[key] = on
        if onSet then onSet(on) end
    end, icon = icon }
end

-- The settings: the sound, the Target key and the two ways an alert can be louder.
local function buildSettings(page, width)
    local st = S.Stack(page)
    local keys = {}
    for i, snd in ipairs(ns.SOUNDS) do keys[i] = snd.key end
    local sound = cycle(page, function() return ns.db.sound end, function(v) ns.db.sound = v; ns.PlayAlert() end,
        keys, function(v) return L["SND_" .. v] end, 170)
    keyButton = makeKeyButton(page)
    local opts, oh = S.SettingsCard(page, nil, {
        { L.SOUND, nil, control = sound, icon = "Interface\\Icons\\INV_Misc_Horn_01" },
        { L.KEY, L.KEY_D, control = keyButton, icon = "Interface\\Icons\\INV_Gizmo_01" },
        switch("repeatSound", L.REPEAT, L.REPEAT_D, ns.OPT_ICON.repeatSound),
        switch("flash", L.FLASH, nil, ns.OPT_ICON.flash),
    })
    for i = 3, 4 do
        local row = opts.rows[i]
        frame.switches[#frame.switches + 1] = row
    end
    st:Add(opts, oh)
    local note, nh = S.Paragraph(page, L.NOTE, width)
    st:Add(note, nh)
    return st:Height()
end

local function makeMobRow(r)
    r.toggle = S.Switch(r)
    r.toggle:SetPoint("LEFT", 0, 0)
    r.remove = S.Close(r, function(self)
        local e = self:GetParent().entry
        if e.id then ns.db.ids[e.id] = nil
        else
            table.remove(ns.db.names, e.i)
            ns.db.mobs[ns.Lower(e.name)] = nil
        end
        ns.Refresh()
    end)
    r.remove:SetPoint("RIGHT", 0, 0)
    r.toggle:SetScript("OnClick", function(self)
        local e = self:GetParent().entry
        local info = ns.Info(e.name)
        info.off = not info.off or nil
        self:SetChecked(not info.off)
    end)
    r.text = S.Text(r, 12)
    r.text:SetPoint("TOPLEFT", r.toggle, "TOPRIGHT", 10, 0)
    r.text:SetPoint("RIGHT", r.remove, "LEFT", -8, 0)
    r.text:SetWordWrap(false)
    r.sub = S.Note(r, 12)
    r.sub:SetPoint("TOPLEFT", r.text, "BOTTOMLEFT", 0, -2)
    r.sub:SetPoint("RIGHT", r.remove, "LEFT", -8, 0)
    r.sub:SetWordWrap(false)
end

local function fillMobRow(r, e)
    r.entry = e
    r.text:SetText(e.name)
    if e.id then
        r.toggle:Hide()
        r.sub:SetText(L.RARE_ROW)
    else
        local info = ns.Info(e.name)
        r.toggle:Show()
        r.toggle:SetChecked(not info.off)
        r.sub:SetText(info.count and L.FOUND_N:format(info.count, info.zone or "?") or L.NOT_FOUND)
    end
end

local function addNames(text)
    local list = ns.db.names
    for _, n in ipairs(ns.ParseNames(text)) do list[#list + 1] = n end
    ns.SetNames(ns.ParseNames(table.concat(list, "\n")))
    ns.Refresh()
end

local function buildMobs(page, width)
    local main, mh = S.SettingsCard(page, nil, {
        { L.ENABLE, nil, function() return ns.db.enabled end, function(on) ns.SetEnabled(on) end,
          icon = "Interface\\Icons\\Ability_Hunter_SniperShot" } })
    main:SetPoint("TOPLEFT")
    main:SetPoint("TOPRIGHT")
    main:SetHeight(mh)
    frame.enable = main.rows[1]
    S.SetFont(frame.enable.label, 14)
    frame.switches[#frame.switches + 1] = { Refresh = function() frame.enable:SetChecked(ns.db.enabled) end }
    local top = mh + S.GAP
    addEdit = S.Edit(page, width - 98, 30)
    addEdit:SetPoint("TOPLEFT", 0, -top)
    S.Placeholder(addEdit, L.ADD_HINT)
    addEdit:SetScript("OnEnterPressed", function(self)
        addNames(self:GetText())
        self:SetText("")
        self:ClearFocus()
    end)
    local add = S.Button(page, 90, 30)
    add:SetText(L.ADD)
    add:SetPoint("TOPRIGHT", 0, -top)
    add:SetScript("OnClick", function()
        addNames(addEdit:GetText())
        addEdit:SetText("")
    end)
    local target = S.FitButton(page, L.ADD_TARGET, 30, 120)
    target:SetPoint("TOPLEFT", 0, -(top + 38))
    target:SetScript("OnClick", function()
        local name = ns.AddTarget()
        ns.Refresh()
        if not name then status:SetText(L.NO_TARGET) end
    end)
    local rares = S.FitButton(page, L.ADD_RARES, 30, 120)
    rares:SetPoint("LEFT", target, "RIGHT", 8, 0)
    rares:SetScript("OnClick", function()
        local n = ns.AddZoneRares()
        ns.Refresh()
        status:SetText(L.RARES_ADDED:format(n))
    end)
    local hint = S.Note(page, 12)
    hint:SetPoint("TOPLEFT", 0, -(top + 76))
    hint:SetPoint("RIGHT")
    hint:SetWordWrap(false)
    hint:SetText(L.QUICK_HINT)
    mobList = S.List(page, 40, makeMobRow, fillMobRow)
    mobList:SetPoint("TOPLEFT", 0, -(top + 98))
    mobList:SetPoint("BOTTOMRIGHT", -10, 0)
    mobEmpty = S.Empty(mobList)
    mobEmpty:Set(L.LIST_EMPTY, L.LIST_EMPTY_D)
end

local function makeHistRow(r)
    r.pin = S.Button(r, 70, 28)
    r.pin:SetText(L.PIN)
    r.pin:SetPoint("RIGHT", 0, 0)
    r.pin:SetScript("OnClick", function(self) ns.Pin(self:GetParent().entry) end)
    r.text = S.Text(r, 12)
    r.text:SetPoint("TOPLEFT", 2, -4)
    r.text:SetPoint("RIGHT", r.pin, "LEFT", -8, 0)
    r.text:SetWordWrap(false)
    r.sub = S.Note(r, 12)
    r.sub:SetPoint("TOPLEFT", r.text, "BOTTOMLEFT", 0, -2)
    r.sub:SetPoint("RIGHT", r.pin, "LEFT", -8, 0)
    r.sub:SetWordWrap(false)
end

local function fillHistRow(r, e)
    r.entry = e
    r.text:SetText(e.name)
    local where = e.zone or ""
    if e.x and e.y then where = where .. (" %.0f, %.0f"):format(e.x * 100, e.y * 100) end
    local line = where .. S.DOT .. ago(e.t)
    if e.who then line = line .. S.DOT .. L.FROM:format(e.who) end
    r.sub:SetText(line)
    r.pin:SetEnabled(e.map ~= nil and e.x ~= nil)
end

local function buildHistory(page)
    histList = S.List(page, 40, makeHistRow, fillHistRow)
    histList:SetPoint("TOPLEFT")
    histList:SetPoint("BOTTOMRIGHT", -10, 0)
    histEmpty = S.Empty(histList)
    histEmpty:Set(L.NO_HISTORY)
end

local function build()
    frame = S.Window("GulliMobFinderFrame", L.TITLE, W, S.DOCK_H, { sub = "/gmf" })
    frame.switches = {}
    status = S.Footer(frame).status
    local body, width = frame.body, frame.inner[1]
    local holder = CreateFrame("Frame", nil, body)
    holder:SetPoint("TOPLEFT")
    holder:SetSize(width, 30)
    pages = {}
    pageTabs = S.PageTabs(holder, { L.PAGE_MOBS, L.PAGE_HISTORY, L.PAGE_SETTINGS }, nil, function(i)
        for j, p in ipairs(pages) do p:SetShown(j == i) end
        ns.Refresh()
    end, nil, { "Interface\\Icons\\Ability_Hunter_SniperShot", S.TAB.recent, S.TAB.settings })
    for i = 1, 3 do
        local p = i == 3 and S.ScrollPage(body, width) or CreateFrame("Frame", nil, body)
        p:SetPoint("TOPLEFT", 0, -38)
        p:SetPoint("BOTTOMRIGHT")
        pages[i] = p
    end
    buildMobs(pages[1], width)
    buildHistory(pages[2])
    pages[3]:SetContent(buildSettings(pages[3].inner, width - 10))
    pages[2]:Hide()
    pages[3]:Hide()
    frame:HookScript("OnShow", ns.Refresh)
end

-- Opens one page of the window: 1 Mobs, 2 Found, 3 Settings.
function ns.ShowPage(i)
    ns.Window()
    pageTabs:Select(i)
    for j, p in ipairs(pages) do p:SetShown(j == i) end
    ns.Refresh()
end

-- Applies a Target macro and the key that waited for the end of a fight.
local regen = CreateFrame("Frame")
regen:RegisterEvent("PLAYER_REGEN_ENABLED")
regen:RegisterEvent("PLAYER_LOGIN")
regen:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if ns.db and ns.db.key then ns.ApplyKey() end
        return
    end
    if pendingMacro ~= nil and card then
        aimTarget(pendingMacro ~= false and card.hit and card.hit.name or nil)
        if cardWaiting then cardWaiting = nil; cardLine() end
    end
    if targetPending ~= nil then showTarget(targetPending and card:IsShown()) end
    if ns.db and ns.db.key then ns.ApplyKey() end
end)

function ns.Toggle()
    S.ToggleWindow(ns.Window())
end

-- The window, for the hub (/gulli) to show inside it.
function ns.Window()
    if not frame then build() end
    return frame
end

-- The addon compartment (the minimap addon menu) opens the window too.
function GulliMobFinder_Toggle() ns.Toggle() end

-- A module of Gulli Toolkit: the hub lists it when the core is loaded.
-- With the hub: its row and button there; alone: its own minimap button (Skin.lua).
do
    local register = GulliToolkit and GulliToolkit.Register or function(info) ns.alone = info end
    register({
        key = "MobFinder",
        title = L.TITLE,
        desc = L.DESC,
        icon = "Interface\\AddOns\\Gulli-MobFinder\\icon",
        open = ns.Toggle,
        window = function() return ns.Window and ns.Window() end,
        slash = "/gmf",
        pause = function(on) if ns.Pause then ns.Pause(on) end end,
        move = function(on) if ns.MoveCard then ns.MoveCard(on) end end,
        -- The card shows by itself on a find; the Unlock mode only places it.
        frames = { { key = "card", label = L.TITLE, icon = "Interface\\Icons\\Ability_Hunter_SniperShot",
                     frame = function() return ns.CardFrame and ns.CardFrame() end } },
        options = {
            { label = L.ENABLE, tip = L.DESC, icon = "Interface\\Icons\\Ability_Hunter_SniperShot",
              get = function() return ns.db ~= nil and ns.db.enabled end,
              set = function(on) if ns.db then ns.SetEnabled(on) end end },
            { label = L.REPEAT, tip = L.REPEAT_D, icon = ns.OPT_ICON.repeatSound,
              get = function() return ns.db ~= nil and ns.db.repeatSound end,
              set = function(on) if ns.db then ns.db.repeatSound = on; ns.Refresh() end end },
            { label = L.FLASH, icon = ns.OPT_ICON.flash,
              get = function() return ns.db ~= nil and ns.db.flash end,
              set = function(on) if ns.db then ns.db.flash = on; ns.Refresh() end end },
        },
        -- A row on the hub's Tweaks page.
        tweaks = {
            { key = "rares", group = "combat", label = L.TWK_RARES, desc = L.TWK_RARES_D, tip = L.DESC,
              icon = "Interface\\Icons\\Ability_EyeOfTheOwl",
              get = function() return ns.db ~= nil and ns.db.enabled == true end,
              set = function(on) if ns.db then ns.SetEnabled(on) end end },
        },
        summary = function()
            if not ns.db or not ns.db.enabled or ns.paused then return nil end
            if ns.lastFound then return L.STATUS_LAST:format(table.concat(ns.lastFound.names, ", ")) end
            return L.SUMMARY:format(#ns.db.names)
        end,
    })
end
