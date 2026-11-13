local _, ns = ...
local L = ns.L
local S = ns.Skin

-- The window has three pages: Search (the switch and how to alert), Mobs (the list, one row
-- per mob, and the zone's rares) and History (the last finds, with a map pin). A find shows a
-- card with the mob's model and a secure Target button, also on a key. Every change is saved
-- at once; the search itself lives in Core.lua.
local W = S.NARROW_W
local BUTTON = "GulliMobFinderTarget"

local frame, pageTabs, pages, status
local mobList, mobEmpty, histList, histEmpty, addEdit, keyButton
local card, flash
local pendingMacro, repeater

local function soundIndex()
    for i, s in ipairs(ns.SOUNDS) do
        if s.key == ns.db.sound then return i end
    end
    return 1
end

local function intervalText(v)
    return (v == math.floor(v)) and tostring(math.floor(v)) or tostring(v)
end

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

local CARD_POINT = { "TOP", 0, -76 }

local function placeCard()
    local p = ns.db.cardPoint or CARD_POINT
    card:ClearAllPoints()
    card:SetPoint(p[1], UIParent, p[1], p[2], p[3])
end

local function buildCard()
    -- The Gulli HUD notice card, at its own place (it is movable) so it stays above the others.
    card = S.ToastFrame("GulliMobFinderCard")
    card:SetFrameStrata("HIGH")
    placeCard()
    S.Mover(card, { label = L.TITLE, save = function(p, _, x, y) ns.db.cardPoint = { p, x, y } end,
        reset = function() ns.db.cardPoint = nil; placeCard() end })
    card:HookScript("OnHide", function() stopRepeat(); showTarget(false) end)

    -- The secure Target button, drawn like S.Primary, with the key on it.
    local t = CreateFrame("Button", BUTTON, UIParent, "SecureActionButtonTemplate")
    t:SetSize(96, 28)
    t:SetFrameStrata("HIGH")
    t:SetFrameLevel((tonumber((card:GetFrameLevel())) or 0) + 10)
    t:SetPoint("RIGHT", card, "RIGHT", -32, 0)
    S.Box(t, S.Accent(), S.EDGE)
    t.text = S.Text(t, 12, S.BG)
    t.text:SetShadowColor(0, 0, 0, 0)
    t.text:SetPoint("CENTER")
    t:RegisterForClicks("AnyUp", "AnyDown")
    t:SetAttribute("type", "macro")
    t:HookScript("OnClick", function() stopRepeat() end)
    t:Hide()
    card.target = t
end

-- The card while /gulli move places it.
function ns.MoveCard(on)
    if not ns.db then return end
    if not card then buildCard() end
    card:SetMoving(on)
    if on then
        card:Set({ icon = "Interface\\Icons\\Ability_Hunter_SniperShot", title = L.TITLE, text = L.CARD_D,
                   kind = "bad" })
    else
        card:Hide()
    end
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
    if not ns.db.card then return end
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
    if not aimTarget(h.name) then parts[#parts + 1] = L.AFTER_COMBAT end
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
               text = table.concat(parts, " · "), kind = "bad", buttons = buttons,
               reserve = (card.target:GetWidth() or 96) + 6,
               seconds = (ns.db.cardSeconds or 0) > 0 and ns.db.cardSeconds or nil })
    showTarget(true)
    stopRepeat()
    if ns.db.repeatSound and C_Timer and C_Timer.NewTicker then
        repeater = C_Timer.NewTicker(3, function() if not ns.Quiet() then ns.PlayAlert() end end, 10)
    end
end

---- Key ----------------------------------------------------------------------------

local keyOwner

function ns.ApplyKey()
    if InCombatLockdown() then return end
    if not card then buildCard() end
    keyOwner = keyOwner or CreateFrame("Frame")
    ClearOverrideBindings(keyOwner)
    if ns.db.key then SetOverrideBindingClick(keyOwner, true, ns.db.key, BUTTON, "LeftButton") end
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
            ns.db.key = mods .. key
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
    local text = d.enabled and L.STATUS_ON:format(#d.names + (function()
        local n = 0
        for _ in pairs(d.ids) do n = n + 1 end
        return n
    end)(), intervalText(d.interval)) or L.STATUS_OFF
    if ns.lastFound then
        text = text .. "\n" .. L.STATUS_LAST:format(table.concat(ns.lastFound.names, ", "))
    end
    status:SetText(text)
    local c = d.enabled and S.GOOD or S.MUTED
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

local function buildSearch(page, width)
    local st = S.Stack(page)
    local main, mh = S.SettingsCard(page, nil, {
        { L.ENABLE, nil, function() return ns.db.enabled end, function(on) ns.SetEnabled(on) end,
          icon = "Interface\\Icons\\Ability_Hunter_SniperShot" } })
    frame.enable = main.rows[1]
    S.SetFont(frame.enable.label, 14)
    frame.switches[#frame.switches + 1] = { Refresh = function() frame.enable:SetChecked(ns.db.enabled) end }
    st:Add(main, mh)

    -- How often to look: [n] sec.
    local every = CreateFrame("Frame", nil, page)
    every:SetSize(96, 28)
    local interval = S.Edit(every, 52, 28)
    interval:SetPoint("LEFT")
    interval:SetMaxLetters(4)
    interval:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    interval:SetScript("OnEditFocusLost", function(self)
        S.SetBorder(self, S.EDGE)
        if not ns.SetInterval(self:GetText()) then
            status:SetText(L.BAD_INTERVAL)
            status:SetTextColor(S.BAD[1], S.BAD[2], S.BAD[3], 1)
        end
        self:SetText(intervalText(ns.db.interval))
    end)
    frame.switches[#frame.switches + 1] = { Refresh = function()
        if not interval:HasFocus() then interval:SetText(intervalText(ns.db.interval)) end
    end }
    local sec = S.Text(every, 12, S.MUTED)
    sec:SetPoint("LEFT", interval, "RIGHT", 8, 0)
    sec:SetText(L.SECONDS)

    local keys = {}
    for i, snd in ipairs(ns.SOUNDS) do keys[i] = snd.key end
    local sound = cycle(page, function() return ns.db.sound end, function(v) ns.db.sound = v; ns.PlayAlert() end,
        keys, function(v) return L["SND_" .. v] end, 170)
    local cooldown = cycle(page, function() return ns.db.cooldown end, function(v) ns.db.cooldown = v end,
        ns.COOLDOWNS, function(v) return v == 0 and L.NONE or L.SEC_N:format(v) end)
    local cardFor = cycle(page, function() return ns.db.cardSeconds end, function(v) ns.db.cardSeconds = v end,
        ns.CARD_SECONDS, function(v) return v == 0 and L.STAYS or L.SEC_N:format(v) end)
    keyButton = makeKeyButton(page)

    local opts, oh = S.SettingsCard(page, L.SEC_ALERT, {
        { L.EVERY, nil, control = every, icon = "Interface\\Icons\\INV_Misc_PocketWatch_01" },
        { L.SOUND, nil, control = sound, icon = "Interface\\Icons\\INV_Misc_Horn_01" },
        { L.COOLDOWN, nil, control = cooldown, icon = "Interface\\Icons\\Spell_Nature_TimeStop" },
        switch("again", L.AGAIN, nil, "Interface\\Icons\\Spell_Nature_TimeStop"),
        switch("repeatSound", L.REPEAT, nil, "Interface\\Icons\\INV_Misc_Bell_01"),
        switch("banner", L.BANNER, nil, "Interface\\Icons\\Ability_Warrior_BattleShout"),
        switch("flash", L.FLASH, nil, "Interface\\Icons\\Spell_Fire_Flare"),
        switch("quietRest", L.QUIET_REST, nil, "Interface\\Icons\\Spell_Nature_Sleep"),
        switch("quietCombat", L.QUIET_COMBAT, nil, "Interface\\Icons\\Ability_Warrior_OffensiveStance"),
    })
    st:Add(opts, oh)

    local found, fh = S.SettingsCard(page, L.SEC_FIND, {
        switch("card", L.CARD, L.CARD_D, "Interface\\Icons\\INV_Misc_Note_01"),
        { L.CARD_FOR, nil, control = cardFor, icon = "Interface\\Icons\\INV_Misc_PocketWatch_01" },
        { L.KEY, L.KEY_D, control = keyButton, icon = "Interface\\Icons\\INV_Gizmo_01" },
        switch("mark", L.MARK, nil, "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"),
        switch("share", L.SHARE, L.SHARE_D, "Interface\\Icons\\INV_Letter_01"),
    })
    st:Add(found, fh)

    local where, wh = S.SettingsCard(page, L.SEC_WHERE, {
        switch("sources", L.SOURCES, L.SOURCES_D, "Interface\\Icons\\INV_Misc_Spyglass_02"),
        switch("vignettes", L.VIGNETTES, nil, "Interface\\Icons\\INV_Misc_Map_01"),
        switch("skipTapped", L.TAPPED, nil, "Interface\\Icons\\Ability_Rogue_Disguise"),
    })
    st:Add(where, wh)
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
    r.exact = S.Button(r, 76, 28)
    r.exact:SetPoint("RIGHT", r.remove, "LEFT", -6, 0)
    r.exact:SetScript("OnClick", function(self)
        local info = ns.Info(self:GetParent().entry.name)
        info.exact = not info.exact or nil
        ns.Refresh()
    end)
    r.toggle:SetScript("OnClick", function(self)
        local e = self:GetParent().entry
        local info = ns.Info(e.name)
        info.off = not info.off or nil
        self:SetChecked(not info.off)
    end)
    r.text = S.Text(r, 12)
    r.text:SetPoint("TOPLEFT", r.toggle, "TOPRIGHT", 10, 0)
    r.text:SetPoint("RIGHT", r.exact, "LEFT", -8, 0)
    r.text:SetWordWrap(false)
    r.sub = S.Note(r, 11)
    r.sub:SetPoint("TOPLEFT", r.text, "BOTTOMLEFT", 0, -2)
    r.sub:SetPoint("RIGHT", r.exact, "LEFT", -8, 0)
    r.sub:SetWordWrap(false)
end

local function fillMobRow(r, e)
    r.entry = e
    r.text:SetText(e.name)
    if e.id then
        r.toggle:Hide()
        r.exact:Hide()
        r.sub:SetText(L.RARE_ROW)
    else
        local info = ns.Info(e.name)
        r.toggle:Show()
        r.toggle:SetChecked(not info.off)
        r.exact:Show()
        r.exact:SetText(info.exact and L.EXACT or L.PART)
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
    addEdit = S.Edit(page, width - 98, 30)
    addEdit:SetPoint("TOPLEFT")
    S.Placeholder(addEdit, L.ADD_HINT)
    addEdit:SetScript("OnEnterPressed", function(self)
        addNames(self:GetText())
        self:SetText("")
        self:ClearFocus()
    end)
    local add = S.Button(page, 90, 30)
    add:SetText(L.ADD)
    add:SetPoint("TOPRIGHT")
    add:SetScript("OnClick", function()
        addNames(addEdit:GetText())
        addEdit:SetText("")
    end)
    local target = S.FitButton(page, L.ADD_TARGET, 30, 120)
    target:SetPoint("TOPLEFT", 0, -38)
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
    mobList = S.List(page, 40, makeMobRow, fillMobRow)
    mobList:SetPoint("TOPLEFT", 0, -76)
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
    r.sub = S.Note(r, 11)
    r.sub:SetPoint("TOPLEFT", r.text, "BOTTOMLEFT", 0, -2)
    r.sub:SetPoint("RIGHT", r.pin, "LEFT", -8, 0)
    r.sub:SetWordWrap(false)
end

local function fillHistRow(r, e)
    r.entry = e
    r.text:SetText(e.name)
    local where = e.zone or ""
    if e.x and e.y then where = where .. (" %.0f, %.0f"):format(e.x * 100, e.y * 100) end
    local line = where .. " · " .. ago(e.t)
    if e.who then line = line .. " · " .. L.FROM:format(e.who) end
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
    local ft = S.Footer(frame)
    local play = ft:Add(S.FitButton(ft, L.PLAY, 30, 80))
    play:SetScript("OnClick", function() ns.PlayAlert() end)
    status = ft.status
    local body, width = frame.body, frame.inner[1]
    local holder = CreateFrame("Frame", nil, body)
    holder:SetPoint("TOPLEFT")
    holder:SetSize(width, 30)
    pages = {}
    pageTabs = S.Tabs(holder, { L.PAGE_SEARCH, L.PAGE_MOBS, L.PAGE_HISTORY }, nil, function(i)
        for j, p in ipairs(pages) do p:SetShown(j == i) end
        ns.Refresh()
    end, nil, { S.TAB.search, "Interface\\Icons\\Ability_Hunter_SniperShot", S.TAB.recent })
    for i = 1, 3 do
        local p = i == 1 and S.Scroll(body) or CreateFrame("Frame", nil, body)
        p:SetPoint("TOPLEFT", 0, -38)
        p:SetPoint("BOTTOMRIGHT", i == 1 and -12 or 0, 0)
        pages[i] = p
    end
    pages[1].child:SetWidth(width - 12)
    local h = buildSearch(pages[1].child, width - 12)
    pages[1].child:SetHeight(h)
    pages[1]:Update(h)
    buildMobs(pages[2], width)
    buildHistory(pages[3])
    pages[2]:Hide()
    pages[3]:Hide()
    frame:HookScript("OnShow", ns.Refresh)
end

-- Opens one page of the window: 1 Search, 2 Mobs, 3 Found.
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
if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({
        key = "MobFinder",
        title = L.TITLE,
        desc = L.DESC,
        icon = "Interface\\AddOns\\Gulli-MobFinder\\icon",
        open = ns.Toggle,
        window = function() return ns.Window and ns.Window() end,
        slash = "/gmf",
        move = function(on) if ns.MoveCard then ns.MoveCard(on) end end,
        options = {
            { label = L.ENABLE, tip = L.DESC, icon = "Interface\\Icons\\Ability_Hunter_SniperShot",
              get = function() return ns.db ~= nil and ns.db.enabled end,
              set = function(on) if ns.db then ns.SetEnabled(on) end end },
            { label = L.CARD, tip = L.CARD_D, icon = "Interface\\Icons\\INV_Misc_Note_01",
              get = function() return ns.db ~= nil and ns.db.card end,
              set = function(on) if ns.db then ns.db.card = on end end },
        },
        summary = function()
            if not ns.db or not ns.db.enabled then return nil end
            if ns.lastFound then return L.STATUS_LAST:format(table.concat(ns.lastFound.names, ", ")) end
            return L.SUMMARY:format(#ns.db.names)
        end,
    })
end
