local _, ns = ...
local L = ns.L
local S = ns.Skin
local B = ns.Buffs

-- The Quick Buff bar: one big secure button (also on the key) that casts the next
-- missing buff, and small secure buttons for the ones after it. Out of combat every
-- change in the group re-aims them. In combat the game forbids that, so the big button
-- walks through the list made just before the fight, in restricted code (COMBAT_SNIPPET),
-- and the small buttons keep the target they had.

local MAIN, MINI, GAP, GRIP = 44, 28, 4, 12
local MINIS = 10
local BUTTON = "GulliGroupBuffsButton"

local bar, grip, main, label, header
local minis = {}
local plan, far, list = {}, {}, {}
local built, dirty, pendingKey = false, true, false
local layout

-- Runs in the game's restricted environment on every click of the big button, before
-- the cast. Outside combat it does nothing (the button is already aimed). In combat it
-- aims the button at the next living unit of the list and moves on, wrapping at the end.
ns.COMBAT_SNIPPET = [[
    if not PlayerInCombat() then return end
    if down ~= self:GetAttribute("gb-down") then return end
    local n = self:GetAttribute("gb-count") or 0
    local i = self:GetAttribute("gb-index") or 1
    for _ = 1, n do
        if i > n then i = 1 end
        local unit = self:GetAttribute("gb-unit" .. i)
        if unit and SecureCmdOptionParse("[@" .. unit .. ",exists,nodead] ok") == "ok" then
            self:SetAttribute("spell", self:GetAttribute("gb-spell" .. i))
            self:SetAttribute("unit", unit)
            self:SetAttribute("gb-index", i + 1)
            return
        end
        i = i + 1
    end
    return false
]]

local function keyDown()
    return GetCVarBool and GetCVarBool("ActionButtonUseKeyDown") and true or false
end

local function who(e)
    local name = UnitName(e.unit) or e.unit
    if e.group and e.covers and e.covers > 1 then
        return L.NEXT_GROUP:format(e.spell, name, e.covers - 1)
    end
    return L.NEXT:format(e.spell, name)
end

local function done(e)
    if not e or not e.names then return false end
    local auras = ns.Auras(e.unit)
    return auras and ns.Present(e.names, auras, 0) or false
end

---- Building --------------------------------------------------------------------

local function iconOn(b, size)
    S.Box(b, { 0, 0, 0, 1 })
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local h = b:CreateTexture(nil, "HIGHLIGHT")
    h:SetAllPoints()
    h:SetColorTexture(1, 1, 1, 0.15)
    b:SetSize(size, size)
end

local function tooltip(b, text)
    if not GameTooltip or not text then return end
    GameTooltip:SetOwner(b, "ANCHOR_TOP")
    GameTooltip:SetText(text)
    GameTooltip:Show()
end

local function savePoint()
    local p, _, _, x, y = bar:GetPoint()
    ns.DB().point = { p, x, y }
end

local function build()
    local d = ns.DB()
    bar = CreateFrame("Frame", "GulliGroupBuffsBar", UIParent)
    bar:SetSize(GRIP + MAIN, MAIN)
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    local p = d.point or { "CENTER", 0, -180 }
    bar:SetPoint(p[1], UIParent, p[1], p[2], p[3])

    grip = CreateFrame("Frame", nil, bar)
    grip:SetSize(GRIP - 2, MAIN)
    grip:SetPoint("LEFT")
    S.Box(grip, S.PANEL)
    grip:EnableMouse(true)
    grip:RegisterForDrag("LeftButton")
    grip:SetScript("OnDragStart", function()
        if not InCombatLockdown() and not ns.DB().locked then bar:StartMoving() end
    end)
    grip:SetScript("OnDragStop", function()
        bar:StopMovingOrSizing()
        savePoint()
    end)
    grip:SetScript("OnEnter", function(self) tooltip(self, L.DRAG) end)
    grip:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    header = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
    main = CreateFrame("Button", BUTTON, bar, "SecureActionButtonTemplate")
    iconOn(main, MAIN)
    main:SetPoint("LEFT", GRIP, 0)
    main:RegisterForClicks("AnyUp", "AnyDown")
    main:SetAttribute("type", "spell")
    header:WrapScript(main, "OnClick", ns.COMBAT_SNIPPET)
    main:HookScript("OnClick", function() dirty = true end)
    main:SetScript("OnEnter", function(self)
        local e = self.entry
        tooltip(self, (e and who(e) or L.ALL_DONE) .. "\n|cff8c8c94" .. L.TIP_MAIN .. "|r")
    end)
    main:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    label = S.Text(bar, 12)
    label:SetPoint("BOTTOMLEFT", main, "TOPLEFT", 0, 4)
    label:SetWordWrap(false)

    for i = 1, MINIS do
        local m = CreateFrame("Button", BUTTON .. "Mini" .. i, bar, "SecureActionButtonTemplate")
        iconOn(m, MINI)
        m:SetPoint("LEFT", main, "RIGHT", GAP + (i - 1) * (MINI + GAP), 0)
        m:RegisterForClicks("AnyUp", "AnyDown")
        m:SetAttribute("type", "spell")
        m:SetScript("OnEnter", function(self) tooltip(self, self.entry and who(self.entry)) end)
        m:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        m:Hide()
        minis[i] = m
    end
    built = true
end

---- Keybind ---------------------------------------------------------------------

function ns.ApplyKey()
    if not built then return end
    if InCombatLockdown() then pendingKey = true; return end
    pendingKey = false
    ClearOverrideBindings(bar)
    local key = ns.DB().key
    if key then SetOverrideBindingClick(bar, true, key, BUTTON, "LeftButton") end
end

---- Showing the plan ------------------------------------------------------------

local function aim(b, e)
    b.entry = e
    b:SetAttribute("spell", e and e.spell or nil)
    b:SetAttribute("unit", e and e.unit or nil)
end

local function paint(b, e, fallback)
    b.icon:SetTexture(e and e.icon or fallback)
    b.icon:SetDesaturated(done(e))
end

function layout()
    local d = ns.DB()
    local shown = 0
    for i = 1, MINIS do
        local e = d.show ~= "never" and plan[i + 1] or nil
        aim(minis[i], e)
        if e then
            shown = i
            paint(minis[i], e)
            minis[i]:Show()
        else
            minis[i]:Hide()
        end
    end
    bar:SetWidth(GRIP + MAIN + shown * (MINI + GAP))
    grip:SetShown(not d.locked)
    local show = d.who ~= "off" and (d.show == "always" or (d.show == "missing" and #plan > 0))
    bar:SetShown(show and true or false)
end

-- Text over the bar: who is next, and how many are out of reach.
local function caption(e, extra)
    local text = e and who(e) or L.ALL_DONE
    if extra then text = text .. "  |cff8c8c94" .. extra .. "|r" end
    label:SetText(text)
end

function ns.Refresh()
    if not built then return end
    dirty = false
    if InCombatLockdown() then
        -- Only the look may change now: dim what got buffed, show where the key is.
        local n = main:GetAttribute("gb-count") or 0
        local i = main:GetAttribute("gb-index") or 1
        if i > n then i = 1 end
        local e = list[i]
        paint(main, e, "Interface\\Icons\\INV_Misc_QuestionMark")
        for _, m in ipairs(minis) do
            if m.entry then paint(m, m.entry) end
        end
        caption(e, n > 0 and L.COMBAT_N:format(i, n) or L.COMBAT_OFF)
        return
    end
    plan, far = ns.Plan()
    local e = plan[1]
    aim(main, e)
    main:SetAttribute("gb-down", keyDown())
    main:SetAttribute("gb-count", 0)
    paint(main, e, "Interface\\RaidFrame\\ReadyCheck-Ready")
    caption(e, #far > 0 and L.FAR:format(#far) or nil)
    layout()
end

-- The last moment before the lockdown: hand the list to the big button.
local function enterCombat()
    if not built then return end
    ns.Refresh()
    local d = ns.DB()
    list = d.combat and ns.CombatList(plan, far) or {}
    for i, e in ipairs(list) do
        main:SetAttribute("gb-spell" .. i, e.spell)
        main:SetAttribute("gb-unit" .. i, e.unit)
    end
    main:SetAttribute("gb-count", #list)
    main:SetAttribute("gb-index", 1)
end
ns.EnterCombat = enterCombat

---- Events ----------------------------------------------------------------------

local GROUP_UNIT = { player = true, target = true }

local driver = CreateFrame("Frame")
local events = { "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "UNIT_AURA",
    "PLAYER_TARGET_CHANGED", "SPELLS_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "UNIT_FLAGS", "UNIT_CONNECTION", "UNIT_INVENTORY_CHANGED", "CVAR_UPDATE", "PLAYER_ROLES_ASSIGNED" }
for _, ev in ipairs(events) do driver:RegisterEvent(ev) end

driver:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGIN" then
        if InCombatLockdown() then return end
        build()
        ns.ApplyKey()
        ns.Refresh()
    elseif event == "PLAYER_REGEN_DISABLED" then
        enterCombat()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if not built then build(); pendingKey = true end
        if pendingKey then ns.ApplyKey() end
        ns.Refresh()
    elseif event == "UNIT_AURA" then
        if unit and (GROUP_UNIT[unit] or unit:find("^party%d") or unit:find("^raid%d")) then dirty = true end
    else
        dirty = true
    end
end)

-- Events mark the plan dirty; it is rebuilt at most five times a second. Once a second
-- it is rebuilt anyway, for range and for buffs that run low without an event.
local since, tick = 0, 0
driver:SetScript("OnUpdate", function(_, elapsed)
    since, tick = since + elapsed, tick + elapsed
    if since < 0.2 then return end
    since = 0
    if tick >= 1 then
        tick = 0
        if not InCombatLockdown() then dirty = true end
    end
    if dirty then ns.Refresh() end
end)

---- Settings window -------------------------------------------------------------

local W, ROW = 460, 32
local win, scroll, keyButton
local rows = {}

local function option(label, get, values, text)
    return { kind = "cycle", label = label, get = get, values = values, text = text }
end

local function dbValue(key)
    return function(v)
        local d = ns.DB()
        if v ~= nil then d[key] = v end
        return d[key]
    end
end

local function blessValue(key)
    return function(v)
        local d = ns.DB()
        if v ~= nil then d.bless[key] = v end
        local cur = d.bless[key]
        if cur == nil then cur = B.BLESS_DEFAULT[key] end
        return cur
    end
end

local function blessingName(key)
    if key == "off" then return L.NONE end
    if key == "class" then return L.BY_CLASS end
    for _, b in ipairs(B.BLESSINGS) do
        if b.key == key then return ns.SpellName(b.id) or key end
    end
    return key
end

local function className(class)
    local names = LOCALIZED_CLASS_NAMES_MALE
    return names and names[class] or class
end

local function famLabel(f)
    if f.who == "blessing" then return L.BLESSINGS end
    if f.choice == "shield" then return L.SHIELD end
    if f.choice == "weapon" then return L.WEAPON end
    return ns.SpellName(f.id) or f.key
end

local function rowList()
    local list = {
        { kind = "header", label = L.QUICK },
        option(L.WHO, dbValue("who"), ns.WHO, function(v) return L["WHO_" .. v] end),
        option(L.SHOW, dbValue("show"), ns.SHOW, function(v) return L["SHOW_" .. v] end),
        option(L.COMBAT, dbValue("combat"), { true, false },
            function(v) return v and L.COMBAT_ON or L.COMBAT_OFF end),
        { kind = "key", label = L.KEY },
        option(L.LOCK, dbValue("locked"), { false, true }, function(v) return v and L.YES or L.NO end),
        option(L.LOW, dbValue("low"), ns.LOW,
            function(v) return v == 0 and L.LOW_GONE or L.LOW_MIN:format(v / 60) end),
        option(L.GROUP, dbValue("groupMin"), ns.GROUP_MIN,
            function(v) return v == 0 and L.GROUP_NEVER or L.GROUP_N:format(v) end),
    }
    local _, class = UnitClass("player")
    local fams = B.CLASS[class]
    list[#list + 1] = { kind = "header", label = L.WATCH }
    if not fams then
        list[#list + 1] = { kind = "note", label = L.NO_BUFFS }
        return list
    end
    for _, f in ipairs(fams) do
        list[#list + 1] = { kind = "check", label = famLabel(f), get = function(v)
            local d = ns.DB()
            if v ~= nil then d.watch[f.key] = v end
            local on = d.watch[f.key]
            if on == nil then on = not f.off end
            return on
        end }
    end
    if class == "DRUID" then
        list[#list + 1] = { kind = "header", label = L.CLASS_OPTS }
        list[#list + 1] = option(L.THORNS, dbValue("thorns"), ns.THORNS,
            function(v) return L["THORNS_" .. v] end)
    elseif class == "SHAMAN" then
        list[#list + 1] = { kind = "header", label = L.CLASS_OPTS }
        for _, choice in ipairs({ "shield", "weapon" }) do
            local keys, byKey = {}, {}
            for _, c in ipairs(B.CHOICES[choice]) do keys[#keys + 1] = c.key; byKey[c.key] = c end
            list[#list + 1] = option(choice == "shield" and L.SHIELD or L.WEAPON, dbValue(choice), keys,
                function(v) return byKey[v] and ns.SpellName(byKey[v].id) or v end)
        end
    elseif class == "PALADIN" then
        list[#list + 1] = { kind = "header", label = L.CLASS_OPTS }
        local plain = { "off" }
        for _, b in ipairs(B.BLESSINGS) do plain[#plain + 1] = b.key end
        local roleValues = { "class" }
        for _, k in ipairs(plain) do roleValues[#roleValues + 1] = k end
        list[#list + 1] = option(L.TANKS, blessValue("TANK"), roleValues, blessingName)
        list[#list + 1] = option(L.HEALERS, blessValue("HEALER"), roleValues, blessingName)
        for _, c in ipairs(B.CLASSES) do
            list[#list + 1] = option(className(c), blessValue(c), plain, blessingName)
        end
    end
    return list
end

local function cycle(r, step)
    local cur = r.data.get()
    local values = r.data.values
    local at = 1
    for i, v in ipairs(values) do if v == cur then at = i end end
    at = (at - 1 + step) % #values + 1
    r.data.get(values[at])
    r.button:SetText(r.data.text(values[at]))
    dirty = true
end

local function keyText()
    local key = ns.DB().key
    return key and (GetBindingText and GetBindingText(key) or key) or L.KEY_NONE
end

local MODIFIER = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true }

local function capture(b, on)
    b.capturing = on
    b:EnableKeyboard(on)
    if b.SetPropagateKeyboardInput and not InCombatLockdown() then b:SetPropagateKeyboardInput(not on) end
    b:SetText(on and L.KEY_PRESS or keyText())
end

local function makeKeyButton(parent)
    local b = S.Button(parent, 190, 28)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, mouse)
        if mouse == "RightButton" then
            ns.DB().key = nil
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
            ns.DB().key = mods .. key
            ns.ApplyKey()
            if InCombatLockdown() then print("|cff9ad0ffGulli-GroupBuffs|r: " .. L.AFTER_COMBAT) end
        end
        capture(self, false)
    end)
    return b
end

local function buildRows()
    for _, r in ipairs(rows) do r:Hide() end
    local y = 0
    local child = scroll.child
    for i, data in ipairs(rowList()) do
        local r = rows[i]
        if not r then
            r = CreateFrame("Frame", nil, child)
            r.text = S.Text(r, 12)
            r.text:SetPoint("LEFT", 8, 0)
            r.text:SetPoint("RIGHT", r, "RIGHT", -204, 0)
            r.text:SetWordWrap(false)
            rows[i] = r
        end
        r.data = data
        r:SetSize(W - 40, data.kind == "header" and 28 or ROW)
        r:SetPoint("TOPLEFT", 0, -y)
        r:Show()
        y = y + r:GetHeight()
        r.text:SetText(data.label)
        local c = data.kind == "header" and S.Accent() or (data.kind == "note" and S.MUTED or S.TEXT)
        r.text:SetTextColor(c[1], c[2], c[3], c[4])
        r.text:SetPoint("RIGHT", r, "RIGHT", (data.kind == "header" or data.kind == "note") and -8 or -204, 0)
        if r.button then r.button:Hide() end
        if r.check then r.check:Hide() end
        if r.key then r.key:Hide() end
        if data.kind == "cycle" then
            if not r.button then
                r.button = S.Button(r, 190, 28)
                r.button:SetPoint("RIGHT", -6, 0)
                r.button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                r.button:SetScript("OnClick", function(_, mouse) cycle(r, mouse == "RightButton" and -1 or 1) end)
            end
            r.button:SetText(data.text(data.get()))
            r.button:Show()
        elseif data.kind == "check" then
            if not r.check then
                r.check = S.Check(r, 28)
                r.check:SetPoint("RIGHT", -6, 0)
                r.check:SetScript("OnClick", function(self)
                    self:SetChecked(r.data.get(not r.data.get()))
                    dirty = true
                end)
            end
            r.check:SetChecked(data.get())
            r.check:Show()
        elseif data.kind == "key" then
            if not r.key then
                r.key = makeKeyButton(r)
                r.key:SetPoint("RIGHT", -6, 0)
            end
            capture(r.key, false)
            r.key:Show()
            keyButton = r.key
        end
    end
    child:SetSize(W - 40, y)
    scroll:Update(y)
end

local function buildWindow()
    win = CreateFrame("Frame", "GulliGroupBuffsSettings", UIParent)
    win:SetSize(W, 470)
    win:SetPoint("CENTER")
    win:SetFrameStrata("DIALOG")
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    S.Box(win)
    tinsert(UISpecialFrames, "GulliGroupBuffsSettings")

    local title = S.Text(win, 14)
    title:SetPoint("TOPLEFT", 12, -9)
    title:SetText(L.TITLE)
    local close = S.Button(win, 28, 28)
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetText("×")
    close:SetScript("OnClick", function() win:Hide() end)

    scroll = S.Scroll(win)
    scroll:SetPoint("TOPLEFT", 10, -40)
    scroll:SetPoint("BOTTOMRIGHT", -24, 36)

    local hint = S.Text(win, 11, S.MUTED)
    hint:SetPoint("BOTTOMLEFT", 12, 12)
    hint:SetPoint("RIGHT", -12, 0)
    hint:SetWordWrap(false)
    hint:SetText(L.MACRO)
    win:Hide()
end

function ns.Toggle()
    if not win then buildWindow() end
    if win:IsShown() then win:Hide(); return end
    buildRows()
    scroll:Top()
    win:Show()
end
