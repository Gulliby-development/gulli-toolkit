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
    GameTooltip:AddLine(ns.db.locked and L.TIP_LOCKED or L.TIP_MOVE, 0.6, 0.61, 0.66, true)
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

local function icon(i)
    if icons[i] then return icons[i] end
    local b = CreateFrame("Button", nil, panel)
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
    b:SetScript("OnClick", function() if ns.db.locked then ns.Toggle() end end)
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

function ns.Refresh()
    local missing, why = ns.Missing()
    local d = ns.db
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

local function build()
    frame = S.Window("GulliRemindersFrame", L.TITLE, S.WIDE_W, 560)
    local ft = S.Footer(frame)
    frame.move = ft:Add(S.Primary(S.FitButton(ft, L.MOVE, 32, 150)))
    frame.move:SetScript("OnClick", function() ns.SetPref("locked", not ns.db.locked) end)
    local body, width = frame.body, frame.inner[1]
    local colW = math.floor((width - S.GAP) / 2)
    local leftCol = CreateFrame("Frame", nil, body)
    leftCol:SetPoint("TOPLEFT")
    leftCol:SetPoint("BOTTOMLEFT")
    leftCol:SetWidth(colW)
    local rightCol = CreateFrame("Frame", nil, body)
    rightCol:SetPoint("TOPRIGHT")
    rightCol:SetPoint("BOTTOMRIGHT")
    rightCol:SetWidth(colW)
    frame.steppers = {}
    local function stepper(key, step, min, max, fmt)
        local s = S.Stepper(body, function() return ns.db[key] end, function(v) ns.SetPref(key, v) end,
            step, min, max, fmt)
        frame.steppers[#frame.steppers + 1] = s
        return s
    end

    -- Left: what to check.
    local left = S.Stack(leftCol)
    local className = UnitClass("player")
    local rows = {}
    for _, b in ipairs(ns.ClassBuffs()) do
        local key = b.key
        rows[#rows + 1] = { b.name, not b.known and L.NOT_KNOWN or nil,
            function() return ns.Tracked({ key = key, on = b.on }) end,
            function(v) ns.SetTracked(key, v) end, icon = b.icon }
    end
    if #rows > 0 then
        local card, h = S.SettingsCard(leftCol, L.SEC_BUFFS, rows, className)
        left:Add(card, h)
    else
        local card = S.Card(leftCol, L.SEC_BUFFS, className)
        local p, ph = S.Paragraph(card.body, L.NO_BUFFS, colW - 2 * S.INSET)
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
    end
    if e.ammo then other[#other + 1] = switch("ammo", L.OPT_AMMO, nil, numberEdit(body, "ammoMin")) end
    if e.shards then other[#other + 1] = switch("shards", L.OPT_SHARDS, nil, numberEdit(body, "shardsMin")) end
    other[#other + 1] = { L.OPT_SOON, nil, icon = ns.OPT_ICON.soonMin,
        control = stepper("soonMin", 1, 0, 15, function(v) return v == 0 and L.OFF or L.MIN:format(v) end) }
    local oc, oh = S.SettingsCard(leftCol, L.SEC_OTHER, other)
    left:Add(oc, oh)

    -- Right: when and how the panel shows.
    local right = S.Stack(rightCol)
    local wc, wh = S.SettingsCard(rightCol, L.SEC_WHEN, {
        switch("show", L.OPT_SHOW),
        switch("inRest", L.OPT_REST, L.OPT_REST_D),
    })
    right:Add(wc, wh)
    local place = S.FitButton(body, L.PLACE_RESET, 28, 110)
    place:SetScript("OnClick", function() ns.SetPref("point", nil) end)
    local pc, ph = S.SettingsCard(rightCol, L.SEC_PANEL, {
        switch("locked", L.OPT_LOCK, L.OPT_LOCK_D),
        { L.OPT_SIZE, nil, icon = ns.OPT_ICON.size, control = stepper("size", 4, 24, 64) },
        { L.OPT_ALPHA, nil, icon = ns.OPT_ICON.alpha,
          control = stepper("alpha", 10, 20, 100, function(v) return v .. "%" end) },
        switch("labels", L.OPT_LABELS),
        switch("vertical", L.OPT_VERTICAL),
        { L.OPT_PLACE, nil, icon = ns.OPT_ICON.point, control = place },
    })
    right:Add(pc, ph)
    S.FitWindow(frame, math.max(left:Height(), right:Height()))

    refreshWindow = function(missing, why)
        if not frame:IsShown() then return end
        frame.move:SetText(ns.db.locked and L.MOVE or L.DONE)
        for _, s in ipairs(frame.steppers) do s:Refresh() end
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
end

function ns.Toggle()
    S.ToggleWindow(ns.Window())
end

-- The window, for the hub (/gulli) to show inside it.
function ns.Window()
    if not frame then build() end
    return frame
end
