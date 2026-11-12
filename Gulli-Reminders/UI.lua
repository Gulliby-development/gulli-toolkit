-- The panel of icons on screen (unlock it to drag it; it then shows every icon it can show) and the
-- settings window: the class buffs to watch, the other checks, when to show the panel and its look.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local panel, frame
local icons = {}
local GAP = 4

-- Panel --------------------------------------------------------------------------------------

local function savePoint()
    local p, _, _, x, y = panel:GetPoint()
    ns.db.point = { p, x, y }
end

local function tip(owner, m)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
    GameTooltip:SetText(m.text or L.TITLE)
    if m.sample then
        GameTooltip:AddLine(L.TIP_SAMPLE, 0.6, 0.61, 0.66, true)
    elseif m.left then
        GameTooltip:AddLine(L.TIP_ENDS:format(ns.Short(m.left)), 1, 0.72, 0.3)
    else
        GameTooltip:AddLine(L.TIP_MISSING, 0.93, 0.42, 0.40)
    end
    if m.none then GameTooltip:AddLine(L.TIP_NONE, 0.93, 0.42, 0.40, true) end
    local hint = L.TIP_MOVE
    if ns.db.locked then
        hint = m.act and L.TIP_ACT or (m.buy and L.TIP_BUY) or L.TIP_LOCKED
    end
    GameTooltip:AddLine(hint, 0.6, 0.61, 0.66, true)
    GameTooltip:Show()
end

local function startDrag() if not ns.db.locked then panel:StartMoving() end end
local function stopDrag() panel:StopMovingOrSizing(); savePoint() end

local function buildPanel()
    panel = CreateFrame("Frame", "GulliRemindersPanel", UIParent)
    panel:SetSize(40, 40)
    panel:SetFrameStrata("MEDIUM")
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    -- The frame around the icons while the panel is unlocked.
    panel.edge = CreateFrame("Frame", nil, panel)
    panel.edge:SetPoint("TOPLEFT", -6, 6)
    panel.edge:SetPoint("BOTTOMRIGHT", 6, -6)
    S.Box(panel.edge, { S.BG[1], S.BG[2], S.BG[3], 0.6 }, S.Accent())
    panel.edge:EnableMouse(true)
    panel.edge:RegisterForDrag("LeftButton")
    panel.edge:SetScript("OnDragStart", startDrag)
    panel.edge:SetScript("OnDragStop", stopDrag)
    panel.hint = S.Text(panel.edge, 11, S.TEXT, "OUTLINE")
    panel.hint:SetPoint("BOTTOMLEFT", panel.edge, "TOPLEFT", 0, 4)
    panel.hint:SetWordWrap(false)
    panel.hint:SetText(L.DRAG)
    panel.line = S.Text(panel, 12, S.TEXT, "OUTLINE")
    panel.line:SetJustifyH("CENTER")
    panel.line:SetWordWrap(false)
end

local function keyDown()
    return GetCVarBool and GetCVarBool("ActionButtonUseKeyDown") and true or false
end

-- A left click does what the icon asks (cast, use, apply to the weapon); the button is secure,
-- so its attributes change only out of combat, and the panel is hidden in combat anyway.
-- A right click, or a left click on an icon without an action, opens the settings; at an open
-- vendor a count icon buys what is missing.
local function postClick(self, button, down)
    if down ~= keyDown() then return end
    local m = self.m
    if button == "RightButton" then ns.Toggle(); return end
    if not ns.db.locked then return end
    if m and m.act and ns.NoteClick then ns.NoteClick(m.key) end
    if m and m.buy and ns.Buy(m) > 0 then return end
    if not (m and m.act) then ns.Toggle() end
end

local function aim(b, m)
    local act = ns.db.locked and m and not m.sample and m.act or nil
    b:SetAttribute("type1", act and act.type or nil)
    b:SetAttribute("spell1", act and act.spell or nil)
    b:SetAttribute("item1", act and act.item or nil)
    b:SetAttribute("macrotext1", act and act.macrotext or nil)
    b:SetAttribute("unit1", act and act.type == "spell" and "player" or nil)
end

local function icon(i)
    if icons[i] then return icons[i] end
    local b = CreateFrame("Button", "GulliRemindersIcon" .. i, panel, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetFrameLevel(panel:GetFrameLevel() + 5) -- above the drag frame, so each icon has its tooltip
    b.box = S.IconBox(b, 40)
    b.box:SetAllPoints()
    b.time = S.Text(b, 12, S.WARN, "OUTLINE")
    b.time:SetPoint("BOTTOM", 0, 2)
    b.time:SetJustifyH("CENTER")
    b.label = S.Text(b, 12, S.TEXT, "OUTLINE")
    b.label:SetPoint("LEFT", b, "RIGHT", 8, 0)
    b.label:SetWordWrap(false)
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", startDrag)
    b:SetScript("OnDragStop", stopDrag)
    b:SetScript("PostClick", postClick)
    b:SetScript("OnEnter", function(self) tip(self, self.m) end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    icons[i] = b
    return b
end

-- Places the icons in a row or a column with the size, opacity and place from the settings.
local function layout(list, missingKeys)
    local d = ns.db
    local size = d.size
    local n = #list
    local labels = {}
    for i, m in ipairs(list) do
        local b = icon(i)
        b.m = m
        b:SetSize(size, size)
        b:ClearAllPoints()
        if d.vertical then b:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -(i - 1) * (size + GAP))
        else b:SetPoint("TOPLEFT", panel, "TOPLEFT", (i - 1) * (size + GAP), 0) end
        b.box:SetIcon(m.icon)
        aim(b, m)
        local dim = m.sample and missingKeys and not missingKeys[m.key]
        b.box.tex:SetDesaturated(dim and true or false)
        b.box:SetAlpha(dim and 0.45 or 1)
        b.time:SetText(m.left and ns.Short(m.left) or "")
        b.label:SetText(m.text or "")
        b.label:SetShown(d.labels and d.vertical)
        b:Show()
        labels[#labels + 1] = m.text
    end
    for i = n + 1, #icons do icons[i]:Hide() end
    local long = n * size + math.max(0, n - 1) * GAP
    if d.vertical then panel:SetSize(size, long) else panel:SetSize(long, size) end
    panel.line:ClearAllPoints()
    panel.line:SetPoint("TOP", panel, "BOTTOM", 0, -6)
    panel.line:SetText(table.concat(labels, "  ·  "))
    panel.line:SetShown(d.labels and not d.vertical)
    panel.edge:SetShown(not d.locked)
    panel:SetAlpha(math.max(0.2, d.alpha / 100))
    panel:ClearAllPoints()
    local p = d.point or ns.PANEL_POINT
    panel:SetPoint(p[1], UIParent, p[1], p[2], p[3])
end

local refreshWindow

local function alert(missing)
    local d = ns.db
    local new = ns.NewOnes(missing)
    if #new == 0 or d.alert == "off" or not d.locked then return end
    if d.alert == "instance" and not ns.PlaceOK("instance") then return end
    if PlaySound then PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master") end
    if UIErrorsFrame then UIErrorsFrame:AddMessage(new[1].text, 1, 0.72, 0.3) end
end

function ns.Refresh()
    local missing, why = ns.Missing()
    local d = ns.db
    -- The icons are secure buttons: in combat nothing on the panel may change (it was hidden
    -- when the fight started).
    if InCombatLockdown() then
        if refreshWindow then refreshWindow(missing, why) end
        return missing
    end
    alert(missing)
    local list, keys
    if not d.locked and d.show and why ~= "combat" then
        keys = {}
        for _, m in ipairs(missing) do keys[m.key] = m end
        list = ns.Sample()
        for i, m in ipairs(list) do
            if keys[m.key] then list[i] = keys[m.key]; list[i].sample = nil end
        end
    elseif #missing > 0 then
        list = missing
    end
    if list then
        if not panel then buildPanel() end
        layout(list, keys)
        panel:Show()
    elseif panel then
        panel:Hide()
    end
    if refreshWindow then refreshWindow(missing, why) end
    return missing
end

-- Window --------------------------------------------------------------------------------------

local function numberEdit(parent, key)
    local e = S.Edit(parent, 52, 28)
    e:SetNumeric(true)
    e:SetMaxLetters(4)
    e:SetText(tostring(ns.db[key]))
    e:SetScript("OnShow", function(self) self:SetText(tostring(ns.db[key])) end)
    local function apply(self)
        local n = tonumber(self:GetText())
        if n then ns.db[key] = n end
        self:SetText(tostring(ns.db[key]))
        self:ClearFocus()
        ns.Refresh()
    end
    e:SetScript("OnEnterPressed", apply)
    e:SetScript("OnEditFocusLost", function(self) S.SetBorder(self, S.EDGE); apply(self) end)
    return e
end

local function switch(key, label, desc, extra)
    return { label, desc, function() return ns.db[key] end, function(v) ns.SetPref(key, v) end,
             extra = extra, icon = ns.OPT_ICON[key] }
end

-- A button that steps through values on a click (right click: back).
local function cycleButton(parent, get, set, values, text, width)
    local b = S.Button(parent, width or 170, 28)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local function show() b:SetText(text(get())) end
    b:SetScript("OnClick", function(_, mouse)
        local at = 1
        for i, v in ipairs(values) do if v == get() then at = i end end
        at = (at - 1 + (mouse == "RightButton" and -1 or 1)) % #values + 1
        set(values[at])
        show()
    end)
    b:SetScript("OnShow", show)
    show()
    return b
end

-- The item on the cursor, or nil.
local function cursorItem()
    if not GetCursorInfo then return nil end
    local kind, id = GetCursorInfo()
    if kind == "item" and id then
        if ClearCursor then ClearCursor() end
        return id
    end
end

-- A scrolling column; returns the column frame and its stack.
local function column(body, width, anchor)
    local sf = S.Scroll(body)
    sf:SetPoint("TOP" .. anchor, anchor == "LEFT" and 0 or -10, 0)
    sf:SetPoint("BOTTOM" .. anchor, anchor == "LEFT" and 0 or -10, 0)
    sf:SetWidth(width - 10)
    sf.child:SetWidth(width - 10)
    return sf, S.Stack(sf.child)
end

local CUSTOM_ROWS = 5

local function build()
    frame = S.Window("GulliRemindersFrame", L.TITLE, S.WIDE_W, S.DOCK_H)
    local ft = S.Footer(frame)
    frame.move = ft:Add(S.Primary(S.FitButton(ft, L.MOVE, 32, 150)))
    frame.move:SetScript("OnClick", function() ns.SetPref("locked", not ns.db.locked) end)
    local body, width = frame.body, frame.inner[1]
    local colW = math.floor((width - S.GAP) / 2)
    local leftScroll, left = column(body, colW, "LEFT")
    local rightScroll, right = column(body, colW, "RIGHT")
    local leftCol, rightCol = leftScroll.child, rightScroll.child
    local cw = colW - 10
    frame.steppers = {}
    local function stepper(key, step, min, max, fmt)
        local st = S.Stepper(body, function() return ns.db[key] end, function(v) ns.SetPref(key, v) end,
            step, min, max, fmt)
        frame.steppers[#frame.steppers + 1] = st
        return st
    end
    local function place(key)
        return cycleButton(body, function() return ns.db[key] end, function(v) ns.SetPref(key, v) end,
            ns.PLACES, function(v) return L["PLACE_" .. v] end)
    end

    -- Left: what to check.
    local className = UnitClass("player")
    local rows = {}
    for _, b in ipairs(ns.ClassBuffs()) do
        local key = b.key
        rows[#rows + 1] = { b.name, not b.known and L.NOT_KNOWN or nil,
            function() return ns.Tracked({ key = key, on = b.on, tank = b.tank }) end,
            function(v) ns.SetTracked(key, v) end, icon = b.icon }
    end
    if #rows > 0 then
        local card, h = S.SettingsCard(leftCol, L.SEC_BUFFS, rows, className)
        left:Add(card, h)
    else
        local card = S.Card(leftCol, L.SEC_BUFFS, className)
        local p, ph = S.Paragraph(card.body, L.NO_BUFFS, cw - 2 * S.INSET)
        p:SetPoint("TOPLEFT")
        left:Add(card, card:Fit(ph))
    end
    local e = ns.Extras()
    local other = {}
    if e.weapon then other[#other + 1] = switch("weapon", L.OPT_WEAPON) end
    if e.pet then
        local r = switch("pet", L.OPT_PET)
        r.icon = ns.PetIcon()
        other[#other + 1] = r
        local _, class = UnitClass("player")
        if class == "WARLOCK" then
            local names = {}
            for _, id in ipairs(ns.WARLOCK_PETS) do names[id] = ns.SpellNameOf(id) end
            other[#other + 1] = { L.OPT_LOCK_PET, nil, icon = ns.PetIcon(),
                control = cycleButton(body, function() return ns.db.lockPet or ns.WARLOCK_PETS[1] end,
                    function(v) ns.SetPref("lockPet", v) end, ns.WARLOCK_PETS,
                    function(v) return names[v] or "?" end) }
        end
    end
    if e.ammo then other[#other + 1] = switch("ammo", L.OPT_AMMO, nil, numberEdit(body, "ammoMin")) end
    if e.shards then other[#other + 1] = switch("shards", L.OPT_SHARDS, nil, numberEdit(body, "shardsMin")) end
    other[#other + 1] = switch("durability", L.OPT_DURABILITY, nil, numberEdit(body, "durMin"))
    other[#other + 1] = switch("bags", L.OPT_BAGS, nil, numberEdit(body, "bagsMin"))
    other[#other + 1] = switch("others", L.OPT_OTHERS, L.OPT_OTHERS_D)
    other[#other + 1] = { L.OPT_SOON, nil, icon = ns.OPT_ICON.soonMin,
        control = stepper("soonMin", 1, 0, 15, function(v) return v == 0 and L.OFF or L.MIN:format(v) end) }
    other[#other + 1] = { L.OPT_WHERE, nil, icon = ns.OPT_ICON.where, control = place("where") }
    local oc, oh = S.SettingsCard(leftCol, L.SEC_OTHER, other)
    left:Add(oc, oh)

    -- Consumables: food, oils and stones, and the items and spells the player adds.
    local setFood = S.Button(body, 90, 28)
    setFood:SetText(L.SET_FOOD)
    setFood:SetScript("OnClick", function()
        local id = cursorItem()
        ns.SetPref("foodItem", id)
    end)
    setFood:SetScript("OnReceiveDrag", function() ns.SetPref("foodItem", cursorItem()) end)
    setFood:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L.SET_FOOD_TIP)
        local id = ns.db.foodItem
        if id then GameTooltip:AddLine(ns.ItemName(id) or ("#" .. id), 1, 1, 1) end
        GameTooltip:Show()
    end)
    setFood:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    local cc, ch = S.SettingsCard(leftCol, L.SEC_ITEMS, {
        switch("food", L.OPT_FOOD, nil, setFood),
        switch("anyWeapon", L.OPT_ANY_WEAPON, L.OPT_ANY_WEAPON_D),
        { L.OPT_WHERE_ITEMS, nil, icon = ns.OPT_ICON.whereItems, control = place("whereItems") },
    })
    left:Add(cc, ch)

    -- Right: when and how the panel shows, then the player's own reminders.
    local wc, wh = S.SettingsCard(rightCol, L.SEC_WHEN, {
        switch("show", L.OPT_SHOW),
        switch("inRest", L.OPT_REST, L.OPT_REST_D),
        { L.OPT_ALERT, nil, icon = ns.OPT_ICON.alert,
          control = cycleButton(body, function() return ns.db.alert end, function(v) ns.SetPref("alert", v) end,
              ns.ALERTS, function(v) return L["ALERT_" .. v] end) },
    })
    right:Add(wc, wh)
    local reset = S.FitButton(body, L.PLACE_RESET, 28, 110)
    reset:SetScript("OnClick", function() ns.SetPref("point", nil) end)
    local pc, ph = S.SettingsCard(rightCol, L.SEC_PANEL, {
        switch("locked", L.OPT_LOCK, L.OPT_LOCK_D),
        { L.OPT_SIZE, nil, icon = ns.OPT_ICON.size, control = stepper("size", 4, 24, 64) },
        { L.OPT_ALPHA, nil, icon = ns.OPT_ICON.alpha,
          control = stepper("alpha", 10, 20, 100, function(v) return v .. "%" end) },
        switch("labels", L.OPT_LABELS),
        switch("vertical", L.OPT_VERTICAL),
        { L.OPT_PLACE, nil, icon = ns.OPT_ICON.point, control = reset },
    })
    right:Add(pc, ph)

    local own = S.Card(rightCol, L.SEC_CUSTOM, nil, "Interface\\Icons\\INV_Misc_Note_02")
    local drop = S.DropZone(own.body, L.DROP, function()
        local id = cursorItem()
        if id then ns.AddItem(id) end
    end, 40)
    drop:SetPoint("TOPLEFT")
    drop:SetPoint("TOPRIGHT")
    local hint = S.Note(own.body, 11)
    hint:SetPoint("TOPLEFT", drop, "BOTTOMLEFT", 0, -6)
    hint:SetPoint("TOPRIGHT", drop, "BOTTOMRIGHT", 0, -6)
    hint:SetText(L.CUSTOM_HINT)
    local listH = CUSTOM_ROWS * 36
    local list = S.List(own.body, 36, function(r)
        r.icon = S.IconBox(r, 26)
        r.icon:SetPoint("LEFT", 0, 0)
        r.del = S.Button(r, 28, 28)
        r.del:SetText("x")
        r.del:SetPoint("RIGHT", 0, 0)
        r.min = S.Stepper(r, function() return r.c and r.c.min or 1 end,
            function(v) ns.SetCustom(r.i, "min", v) end, 1, 1, 200, nil, 90)
        r.min:SetPoint("RIGHT", r.del, "LEFT", -6, 0)
        r.kind = S.Button(r, 70, 28)
        r.kind:SetPoint("RIGHT", r.min, "LEFT", -6, 0)
        r.name = S.Text(r, 12)
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
        r.name:SetPoint("RIGHT", r.kind, "LEFT", -8, 0)
        r.name:SetWordWrap(false)
        r.del:SetScript("OnClick", function() ns.RemoveCustom(r.i) end)
        r.kind:SetScript("OnClick", function()
            if r.c and r.c.id then ns.SetCustom(r.i, "kind", r.c.kind == "count" and "buff" or "count") end
        end)
    end, function(r, c, i)
        r.c, r.i = c, i
        if c.spell then
            r.icon:SetIcon(ns.SpellIconOf(c.spell))
            r.name:SetText(ns.SpellNameOf(c.spell) or ("#" .. c.spell))
            r.kind:SetText(L.KIND_SPELL)
            r.kind:SetEnabled(false)
            r.min:Hide()
        else
            r.icon:SetIcon(ns.ItemIcon(c.id))
            r.name:SetText(ns.ItemName(c.id) or ("#" .. c.id))
            r.kind:SetText(c.kind == "count" and L.KIND_COUNT or L.KIND_BUFF)
            r.kind:SetEnabled(true)
            r.min:SetShown(c.kind == "count")
            r.min:Refresh()
        end
    end)
    list:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8)
    list:SetPoint("RIGHT", own.body, "RIGHT", -10, 0)
    list:SetHeight(listH)
    frame.custom = list
    right:Add(own, own:Fit(40 + 6 + 30 + 8 + listH))

    leftCol:SetHeight(left:Height())
    leftScroll:Update(left:Height())
    rightCol:SetHeight(right:Height())
    rightScroll:Update(right:Height())

    refreshWindow = function(missing, why)
        if not frame:IsShown() then return end
        frame.move:SetText(ns.db.locked and L.MOVE or L.DONE)
        for _, st in ipairs(frame.steppers) do st:Refresh() end
        frame.custom:SetData(ns.db.custom)
        local reason = why and L["STATUS_" .. why:upper()]
        if reason then ft:SetStatus(reason, S.MUTED)
        elseif #missing == 0 then ft:SetStatus(L.STATUS_NONE, S.GOOD)
        else
            local names = {}
            for _, m in ipairs(missing) do names[#names + 1] = m.text end
            ft:SetStatus(L.STATUS_SOME:format(table.concat(names, ", ")), S.WARN)
        end
    end
    frame:HookScript("OnShow", function() ns.Refresh() end)
    frame.cards = { oc, cc, wc, pc, left.items[1] }
end

-- After a reset: every switch and button shows the saved value again.
function ns.RebuildWindow()
    if not frame then return end
    for _, card in ipairs(frame.cards) do
        for _, row in ipairs(card.rows or {}) do
            local on = row.GetScript and row:GetScript("OnShow")
            if on then on(row) end
            local c = row.control
            local cs = c and c.GetScript and c:GetScript("OnShow")
            if cs then cs(c) end
        end
    end
    if frame:IsShown() then ns.Refresh() end
end

function ns.Toggle()
    S.ToggleWindow(ns.Window())
end

-- The window, for the hub (/gulli) to show inside it.
function ns.Window()
    if not frame then build() end
    return frame
end
