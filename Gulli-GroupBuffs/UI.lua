local _, ns = ...
local L = ns.L
local S = ns.Skin
local B = ns.Buffs

-- The Quick Buff bar: one big secure button (also on the key) that casts the next
-- missing buff, and small secure buttons for the ones after it. Out of combat every
-- change in the group re-aims them. In combat the game forbids that, so the big button
-- walks through the list made just before the fight, in restricted code (COMBAT_SNIPPET),
-- and the small buttons keep the target they had.

local MAIN, MINI, GAP = 52, 28, 4
local MINIS = 10
local BUTTON = "GulliGroupBuffsButton"

local bar, main, label, header
local moving = false
local minis = {}
local plan, far, list, byUnit = {}, {}, {}, {}
local built, dirty, pendingKey = false, true, false
local layout
local lastCast = {}       -- the unit the last press aimed at, and when
local readyUntil = 0      -- a ready check shows the bar until then

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
    S.HudIcon(b, size)
    local h = b:CreateTexture(nil, "HIGHLIGHT")
    h:SetAllPoints()
    h:SetColorTexture(1, 1, 1, 0.15)
end

local function tooltip(b, text)
    if not GameTooltip or not text then return end
    GameTooltip:SetOwner(b, "ANCHOR_TOP")
    GameTooltip:SetText(text)
    GameTooltip:Show()
end

local function now() return GetTime and GetTime() or 0 end

-- Remembers where a press went, so a failed cast can skip that unit for a while.
local function noteCast(self)
    lastCast.unit, lastCast.t = self:GetAttribute("unit"), now()
    lastCast.spell = self:GetAttribute("spell")
end

local function savePoint()
    if not bar then return end
    local p, _, _, x, y = bar:GetPoint()
    ns.DB().point = { p, x, y }
end

local function build()
    local d = ns.DB()
    bar = CreateFrame("Frame", "GulliGroupBuffsBar", UIParent)
    bar:SetSize(MAIN + 160, MAIN)
    local p = d.point or { "CENTER", 0, -180 }
    bar:SetPoint(p[1], UIParent, p[1], p[2], p[3])
    S.Mover(bar, { label = L.TITLE, hint = L.DRAG,
        save = function() savePoint() end,
        reset = function()
            if InCombatLockdown() then return end
            ns.DB().point = nil
            bar:ClearAllPoints()
            bar:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
        end })

    header = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
    main = CreateFrame("Button", BUTTON, bar, "SecureActionButtonTemplate")
    iconOn(main, MAIN)
    main:SetPoint("TOPLEFT")
    main:RegisterForClicks("AnyUp", "AnyDown")
    main:SetAttribute("type", "spell")
    header:WrapScript(main, "OnClick", ns.COMBAT_SNIPPET)
    main:HookScript("OnClick", function(self) dirty = true; noteCast(self) end)
    main:SetScript("OnEnter", function(self)
        local e = self.entry
        tooltip(self, (e and who(e) or L.ALL_DONE) .. "\n|cff8c8c94" .. L.TIP_MAIN .. "|r")
    end)
    main:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    -- What the big button casts and on whom, in a panel beside it.
    label = S.HudCaption(bar, MAIN)
    label:SetPoint("TOPLEFT", main, "TOPRIGHT", -1, 0)

    for i = 1, MINIS do
        local m = CreateFrame("Button", BUTTON .. "Mini" .. i, bar, "SecureActionButtonTemplate")
        iconOn(m, MINI)
        m:SetPoint("TOPLEFT", main, "BOTTOMLEFT", (i - 1) * (MINI + GAP), -GAP - 1)
        m:RegisterForClicks("AnyUp", "AnyDown")
        m:SetAttribute("type", "spell")
        m:HookScript("OnClick", function(self) dirty = true; noteCast(self) end)
        m:SetScript("OnEnter", function(self) tooltip(self, self.entry and who(self.entry)) end)
        m:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        m:Hide()
        minis[i] = m
    end
    built = true
end

-- /gulli move: the mover over the bar, and the bar shows so it can be placed.
function ns.Move(on)
    moving = on and true or false
    if built then layout() end
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
    b:SetIcon(e and e.icon or fallback)
    b:SetDone(done(e))
end

-- The marks on the game's party and raid frames: the icon of the first buff a unit misses.
-- Only textures of our own on top of those frames; nothing of theirs changes.
local marks = setmetatable({}, { __mode = "k" })

local function eachGroupFrame(fn)
    for i = 1, 5 do local f = _G["CompactPartyFrameMember" .. i]; if f then fn(f) end end
    for i = 1, 40 do local f = _G["CompactRaidFrame" .. i]; if f then fn(f) end end
    for g = 1, 8 do
        for m = 1, 5 do local f = _G["CompactRaidGroup" .. g .. "Member" .. m]; if f then fn(f) end end
    end
end

local function paintMarks()
    local on = ns.DB().marks
    eachGroupFrame(function(f)
        local unit = f.displayedUnit or f.unit
        local icon
        if on and type(unit) == "string" and UnitExists(unit) then
            for u, ic in pairs(byUnit) do
                if UnitIsUnit(u, unit) then icon = ic; break end
            end
        end
        local t = marks[f]
        if icon and not t then
            t = f:CreateTexture(nil, "OVERLAY", nil, 7)
            t:SetSize(14, 14)
            t:SetPoint("TOPRIGHT", -2, -2)
            t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            marks[f] = t
        end
        if t then
            t:SetTexture(icon)
            t:SetShown(icon ~= nil)
        end
    end)
end
ns.PaintMarks = paintMarks

-- Red: something to cast now; yellow: only out of reach or skipped; green: all done.
local function state()
    local n = #plan + #far
    main:SetCount(n > 1 and ("+" .. (n - 1)) or "")
    local st = "ok"
    if #plan > 0 then st = "need" elseif n > 0 or ((ns.info or {}).skipped or 0) > 0 then st = "soon" end
    main:SetState(st)
    main:SetKey(ns.DB().key)
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
    label:SetShown(d.labels ~= false)
    local cap = label:IsShown() and (label:GetWidth() or 120) - 1 or 0
    bar:SetWidth(math.max(MAIN + cap, shown * (MINI + GAP)))
    bar:SetHeight(MAIN + (shown > 0 and (GAP + 1 + MINI) or 0))
    local move = moving or not d.locked
    bar:SetMoving(move and not InCombatLockdown())
    local show = move
    if not show and d.who ~= "off" and d.show ~= "never" then
        if readyUntil > now() and #plan + #far > 0 then show = true
        elseif ns.PlaceOK() then show = d.show == "always" or #plan > 0 end
    end
    bar:SetShown(show)
end

-- The first reason why there is nothing to cast, as a line.
local function reason()
    local st = ns.Status(plan, far)[1]
    if not st then return nil end
    return st[2] and L[st[1]]:format(st[2]) or L[st[1]]
end

-- The caption beside the big button: the spell, then on whom (in the class colour) and the
-- extra line (out of range, the combat list).
local function caption(e, extra)
    local sub
    if e then
        local name = UnitName(e.unit) or e.unit
        local _, class = UnitClass(e.unit)
        local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if c then name = S.Hex({ c.r, c.g, c.b }) .. name .. "|r" end
        if e.group and e.covers and e.covers > 1 then name = name .. " +" .. (e.covers - 1) end
        sub = name
    end
    if extra then sub = sub and (sub .. "  " .. S.Hex(S.FAINT) .. extra .. "|r") or extra end
    label:Set(e and e.spell or reason() or L.ALL_DONE, sub)
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
        paintMarks()
        return
    end
    plan, far, byUnit = ns.Plan()
    byUnit = byUnit or {}
    local e = plan[1]
    aim(main, e)
    main:SetAttribute("gb-down", keyDown())
    main:SetAttribute("gb-count", 0)
    paint(main, e, "Interface\\RaidFrame\\ReadyCheck-Ready")
    caption(e, #far > 0 and L.FAR:format(#far) or nil)
    state()
    layout()
    paintMarks()
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
    "UNIT_FLAGS", "UNIT_CONNECTION", "UNIT_INVENTORY_CHANGED", "CVAR_UPDATE", "PLAYER_ROLES_ASSIGNED",
    "UI_ERROR_MESSAGE", "READY_CHECK", "UPDATE_MOUSEOVER_UNIT", "PLAYER_UPDATE_RESTING",
    "ZONE_CHANGED_NEW_AREA", "UNIT_PET", "UNIT_POWER_UPDATE" }

-- Errors after a press that mean "not this unit for now". Out of range is not here:
-- the range check already handles it.
local function failMessages()
    local set = {}
    for _, k in ipairs({ "SPELL_FAILED_LINE_OF_SIGHT", "SPELL_FAILED_AURA_BOUNCED", "SPELL_FAILED_BAD_TARGETS",
        "SPELL_FAILED_TARGET_AURASTATE", "SPELL_FAILED_BAD_IMPLICIT_TARGETS", "ERR_INVALID_ATTACK_TARGET" }) do
        if _G[k] then set[_G[k]] = true end
    end
    return set
end
for _, ev in ipairs(events) do driver:RegisterEvent(ev) end

driver:SetScript("OnEvent", function(_, event, unit, ...)
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
    elseif event == "UI_ERROR_MESSAGE" then
        local msg = ...
        -- A stronger buff is already on (Camp Benefits and the like): not that buff there for now.
        if lastCast.unit and lastCast.spell and now() - (lastCast.t or 0) < 1.5
            and msg == _G.SPELL_FAILED_AURA_BOUNCED then
            ns.Bounced(lastCast.unit, lastCast.spell)
            dirty = true
        end
        if lastCast.unit and lastCast.unit ~= "player" and now() - (lastCast.t or 0) < 1.5
            and type(msg) == "string" and failMessages()[msg] then
            ns.Skip(lastCast.unit)
            lastCast.unit = nil
            dirty = true
        end
    elseif event == "READY_CHECK" then
        if ns.DB().readyCheck and not InCombatLockdown() then
            ns.Refresh()
            if #plan + #far > 0 then
                readyUntil = now() + 40
                if PlaySound then PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master") end
                layout()
            end
        end
    elseif event == "UNIT_POWER_UPDATE" then
        if unit == "player" and (ns.DB().mana or 0) > 0 then dirty = true end
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

local W, H = S.NARROW_W, 580
local I = "Interface\\Icons\\"
local win, scroll, keyButton
local rows = {}

-- icon: a game icon path, or a function of the current value that gives one (or nil).
-- refill: the other rows show something else after a change of this one.
local function option(label, get, values, text, icon, refill)
    return { kind = "cycle", label = label, get = get, values = values, text = text, icon = icon, refill = refill }
end

local function spellIcon(id) return id and ns.SpellIcon(id) end

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

local CHOICE_LABEL = { shield = "SHIELD", weapon = "WEAPON", magearmor = "ARMOR", lockarmor = "ARMOR",
    aura = "AURA", aspect = "ASPECT" }

local function famLabel(f)
    if f.who == "blessing" then return L.BLESSINGS end
    if f.choice then return L[CHOICE_LABEL[f.choice]] end
    return ns.SpellName(f.id) or f.key
end

-- The group size whose settings the window edits (perSize on); the current one at first.
local editSize

local function sizeValue(key)
    return function(v)
        local d = ns.DB()
        if not d.perSize then
            if v ~= nil then d[key] = v end
            return d[key]
        end
        local t = d.size[editSize or ns.Size()]
        if v ~= nil then t[key] = v end
        local cur = t[key]
        if cur == nil then cur = d[key] end
        return cur
    end
end

local function onOff(v) return v and L.YES or L.NO end

local function rowList()
    local list = {
        { kind = "header", label = L.QUICK },
        option(L.WHO, dbValue("who"), ns.WHO, function(v) return L["WHO_" .. v] end,
            I .. "Spell_Holy_PrayerOfHealing02"),
        option(L.SHOW, dbValue("show"), ns.SHOW, function(v) return L["SHOW_" .. v] end,
            I .. "INV_Misc_Spyglass_02"),
        option(L.COMBAT, dbValue("combat"), { true, false },
            function(v) return v and L.COMBAT_ON or L.COMBAT_OFF end, I .. "Ability_Warrior_OffensiveStance"),
        { kind = "key", label = L.KEY, icon = I .. "INV_Gizmo_01" },
        option(L.LOCK, dbValue("locked"), { false, true }, function(v) return v and L.YES or L.NO end,
            I .. "INV_Misc_Key_04"),
        option(L.WHERE, dbValue("where"), ns.WHERE, function(v) return L["WHERE_" .. v] end,
            I .. "INV_Misc_Map_01"),
        option(L.READY, dbValue("readyCheck"), { true, false }, onOff, I .. "INV_Misc_Bell_01"),
        option(L.MARKS, dbValue("marks"), { true, false }, onOff, I .. "Ability_Hunter_MarkedForDeath"),
        option(L.LABELS, dbValue("labels"), { true, false }, onOff, I .. "INV_Misc_Note_01"),
        { kind = "header", label = L.TARGETS },
        option(L.PETS, dbValue("pets"), { true, false }, onOff, I .. "Ability_Hunter_BeastCall"),
        option(L.FOCUS, dbValue("focus"), { true, false }, onOff, I .. "Ability_Hunter_SniperShot"),
        option(L.RAID_GROUPS, dbValue("raidGroups"), ns.RAID_GROUPS,
            function(v) return v == "all" and L.RAID_ALL or L.RAID_N:format(v) end, I .. "INV_Banner_02"),
        option(L.MANA, dbValue("mana"), ns.MANA,
            function(v) return v == 0 and L.MANA_OFF or L.MANA_N:format(v) end, I .. "INV_Potion_76"),
        { kind = "header", label = L.TIMING },
        option(L.PER_SIZE, dbValue("perSize"), { false, true }, onOff, I .. "Spell_Nature_TimeStop", true),
        option(L.SIZE_EDIT, function(v)
            if v ~= nil then editSize = v end
            return editSize or ns.Size()
        end, ns.SIZES, function(v) return L["SIZE_" .. v] end, I .. "Achievement_GuildPerk_EverybodysFriend", true),
        option(L.LOW, sizeValue("low"), ns.LOW,
            function(v) return v == 0 and L.LOW_GONE or L.LOW_MIN:format(v / 60) end,
            I .. "INV_Misc_PocketWatch_01"),
        option(L.GROUP, sizeValue("groupMin"), ns.GROUP_MIN,
            function(v) return v == 0 and L.GROUP_NEVER or L.GROUP_N:format(v) end,
            I .. "Spell_Holy_PrayerOfFortitude"),
    }
    local _, class = UnitClass("player")
    local fams = B.CLASS[class]
    list[#list + 1] = { kind = "header", label = L.WATCH }
    if not fams then
        list[#list + 1] = { kind = "note", label = L.NO_BUFFS }
        return list
    end
    for _, f in ipairs(fams) do
        local id = f.id
        if f.who == "blessing" then id = B.BLESSINGS[1].id
        elseif f.choice then id = B.CHOICES[f.choice][1].id end
        list[#list + 1] = { kind = "check", label = famLabel(f), icon = spellIcon(id), get = function(v)
            local d = ns.DB()
            if v ~= nil then d.watch[f.key] = v end
            local on = d.watch[f.key]
            if on == nil then on = not f.off end
            return on
        end }
    end
    local opts = false
    local function classHeader()
        if not opts then list[#list + 1] = { kind = "header", label = L.CLASS_OPTS } end
        opts = true
    end
    -- One row per pick-one family: "auto" (where it is the default), each spell, none.
    for _, f in ipairs(fams) do
        if f.choice then
            classHeader()
            local keys, byKey = {}, {}
            if B.CHOICE_DEFAULT[f.choice] == "auto" then keys[1] = "auto" end
            for _, c in ipairs(B.CHOICES[f.choice]) do keys[#keys + 1] = c.key; byKey[c.key] = c end
            keys[#keys + 1] = "off"
            list[#list + 1] = option(famLabel(f), dbValue(f.choice), keys,
                function(v)
                    if v == "auto" then return L.AUTO end
                    if v == "off" then return L.NONE end
                    return byKey[v] and ns.SpellName(byKey[v].id) or v
                end,
                function(v) return byKey[v] and spellIcon(byKey[v].id) end)
        end
    end
    if class == "DRUID" then
        classHeader()
        list[#list + 1] = option(L.THORNS, dbValue("thorns"), ns.THORNS,
            function(v) return L["THORNS_" .. v] end, spellIcon(467))
    elseif class == "PALADIN" then
        classHeader()
        local plain = { "off" }
        for _, b in ipairs(B.BLESSINGS) do plain[#plain + 1] = b.key end
        local roleValues = { "class" }
        for _, k in ipairs(plain) do roleValues[#roleValues + 1] = k end
        local function blessIcon(v)
            for _, b in ipairs(B.BLESSINGS) do if b.key == v then return spellIcon(b.id) end end
        end
        list[#list + 1] = option(L.TANKS, blessValue("TANK"), roleValues, blessingName, blessIcon)
        list[#list + 1] = option(L.HEALERS, blessValue("HEALER"), roleValues, blessingName, blessIcon)
        for _, c in ipairs(B.CLASSES) do
            list[#list + 1] = option(className(c), blessValue(c), plain, blessingName, blessIcon)
        end
    end
    return list
end

local fillRows

local function cycle(r, step)
    local cur = r.data.get()
    local values = r.data.values
    local at = 1
    for i, v in ipairs(values) do if v == cur then at = i end end
    at = (at - 1 + step) % #values + 1
    r.data.get(values[at])
    r.button:SetText(r.data.text(values[at]))
    r:ShowIcon()
    if r.data.refill then r.fill() end
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

-- A row's icon: fixed, or picked by the current value (hidden when there is none).
local function rowIcon(data)
    if type(data.icon) == "function" then return data.icon(data.get()) end
    return data.icon
end

local function makeRow(parent, data)
    local control
    if data.kind == "cycle" then
        control = S.Button(parent, 190, 28)
        control:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    elseif data.kind == "check" then
        control = S.Switch(parent)
    elseif data.kind == "key" then
        control = makeKeyButton(parent)
        keyButton = control
    end
    local r = S.SettingRow(parent, data.label, nil, control, control and control:GetWidth(),
        data.icon and (I .. "INV_Misc_QuestionMark"))
    r.data = data
    r.fill = function() fillRows() end
    function r:ShowIcon()
        if not self.icon then return end
        local path = rowIcon(self.data)
        self.icon:SetShown(path ~= nil)
        if path then self.icon:SetIcon(path) end
    end
    if data.kind == "cycle" then
        r.button = control
        control:SetScript("OnClick", function(_, mouse) cycle(r, mouse == "RightButton" and -1 or 1) end)
    elseif data.kind == "check" then
        r.check = control
        control:SetScript("OnClick", function(self)
            self:SetChecked(r.data.get(not r.data.get()))
            dirty = true
        end)
    end
    return r
end

-- Shows each row's current value.
function fillRows()
    for _, r in ipairs(rows) do
        local data = r.data
        if data.kind == "cycle" then r.button:SetText(data.text(data.get()))
        elseif data.kind == "check" then r.check:SetChecked(data.get())
        elseif data.kind == "key" then capture(r.control, false) end
        r:ShowIcon()
    end
end

-- One card per header of rowList(); the class does not change, so this runs once.
local function buildRows()
    local child = scroll.child
    local width = child:GetWidth()
    local st = S.Stack(child)
    local card, cst, n
    local function close()
        if not card then return end
        if n > 0 then rows[#rows].line:Hide() end
        st:Add(card, card:Fit(cst:Height()))
    end
    for _, data in ipairs(rowList()) do
        if data.kind == "header" then
            close()
            card = S.Card(child, data.label)
            card:SetWidth(width)
            cst, n = S.Stack(card.body, 0), 0
        elseif data.kind == "note" then
            local t = S.Note(card.body, 12)
            t:SetText(data.label)
            cst:Add(t, S.ROW_H)
        else
            local r = makeRow(card.body, data)
            cst:Add(r, r.height)
            rows[#rows + 1] = r
            n = n + 1
        end
    end
    close()
    child:SetHeight(st:Height())
    scroll:Update(st:Height())
end

local function buildWindow()
    win = S.Window("GulliGroupBuffsSettings", L.TITLE, W, H)
    local ft = S.Footer(win)
    ft:SetStatus(L.MACRO)
    scroll = S.Scroll(win.body)
    scroll:SetPoint("TOPLEFT")
    scroll:SetPoint("BOTTOMRIGHT", -12, 0)
    scroll.child:SetWidth(win.inner[1] - 12)
    buildRows()
end

function ns.Toggle()
    if S.ToggleWindow(ns.Window()) then
        fillRows()
        scroll:Top()
    end
end

-- The settings window, for the hub (/gulli) to show inside it.
function ns.Window()
    if not win then
        buildWindow()
        -- In the hub the window is shown by the hub, not by ns.Toggle.
        win:HookScript("OnShow", function(self)
            if not self.docked then return end
            fillRows()
            scroll:Top()
        end)
    end
    return win
end
