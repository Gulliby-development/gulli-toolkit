local _, ns = ...
local L = ns.L
local S = ns.Skin

-- Two views in one window. Setup: the level and what to clean. Preview: zones
-- and their quests on the left, items on the right, a line from each quest to the items
-- it needs. Items no quest needs hang off a "No quest" label at the end.
local W, PREVIEW_H = S.WIDE_W, 600
local I = "Interface\\Icons\\"
local ROW_H, ZONE_H = 32, 28
local LEFT_W, GAP = 262, 52
local DIM = { 0.55, 0.55, 0.58, 0.35 }

local frame, footer, setup, preview, summary, frees, setupH
local edit, levelRow, clearButton, locksRow
local scroll, content, okButton, backButton, questHead, itemHead
local plan = { quests = {}, items = {}, future = {} }
local totals = { quests = 0, items = 0 }
local pools = { zone = {}, quest = {}, item = {}, label = {}, line = {}, band = {} }
local used = {}
local focusList, focus = {}, 0 -- rows a gamepad can step through, and the one it is on

-- The footer line: a message, else the hint of the preview.
local function setStatus(text)
    if (not text or text == "") and preview and preview:IsShown() then
        footer:SetStatus(L.HINT)
    else
        footer:SetStatus(text or "", S.TEXT)
    end
end

-- Fixed labels by key, set once the window is built.
local labels = {}
local function say(obj, key)
    labels[#labels + 1] = { obj, key }
    obj:SetText(L[key])
end

---- Pools ---------------------------------------------------------------------

local function take(kind, make)
    used[kind] = (used[kind] or 0) + 1
    local p = pools[kind]
    local o = p[used[kind]]
    if not o then
        o = make()
        p[used[kind]] = o
    end
    o:Show()
    return o
end

local function releaseAll()
    for kind, p in pairs(pools) do
        for i = 1, #p do p[i]:Hide() end
        used[kind] = 0
    end
    focusList = {}
end

local refresh

local function hover(r)
    local h = r:CreateTexture(nil, "HIGHLIGHT")
    h:SetAllPoints()
    h:SetColorTexture(1, 1, 1, 0.05)
end

-- A clickable row with a check box on the left; a click anywhere on it toggles.
local function checkRow(width, height, onToggle)
    local r = CreateFrame("Button", nil, content)
    r:SetSize(width, height)
    hover(r)
    r.check = S.Check(r, 26)
    r.check:SetPoint("LEFT", 2, 0)
    local function toggle()
        if r.locked == true then return end
        onToggle(r)
        refresh()
    end
    r:SetScript("OnClick", toggle)
    r.check:SetScript("OnClick", toggle)
    r.focus = r:CreateTexture(nil, "BACKGROUND")
    r.focus:SetAllPoints()
    r.focus:SetColorTexture(1, 1, 1, 0.10)
    r.focus:Hide()
    r.toggle = toggle
    return r
end

local function makeZoneRow()
    local r = checkRow(LEFT_W, ZONE_H, function(self)
        local all = true
        for _, q in ipairs(self.data.quests) do all = all and q.checked end
        for _, q in ipairs(self.data.quests) do q.checked = not all end
    end)
    r.text = S.Text(r, 13)
    r.text:SetPoint("LEFT", r.check, "RIGHT", 2, 0)
    r.text:SetPoint("RIGHT", -40, 0)
    r.text:SetWordWrap(false)
    r.count = S.Text(r, 11, S.MUTED)
    r.count:SetPoint("RIGHT", -6, 0)
    r.count:SetJustifyH("RIGHT")
    return r
end

local function makeQuestRow()
    local r = checkRow(LEFT_W - 14, ROW_H, function(self) self.data.checked = not self.data.checked end)
    r.text = S.Text(r, 12)
    r.text:SetPoint("LEFT", r.check, "RIGHT", 2, 0)
    r.text:SetPoint("RIGHT", -4, 0)
    r.text:SetWordWrap(false)
    r:SetScript("OnEnter", function(self)
        local q = self.data
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(q.title, 1, 1, 1)
        local where = ns.WhereToTake(q.questID)
        if where then GameTooltip:AddLine(L.TAKE_AGAIN:format(where), 0.6, 0.6, 0.6, true) end
        GameTooltip:AddLine(L.LOCK_HINT, 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return r
end

local function makeItemRow()
    local r = checkRow(200, ROW_H, function(self) self.data.checked = not self.data.checked end)
    local frameIcon = CreateFrame("Frame", nil, r)
    frameIcon:SetSize(24, 24)
    frameIcon:SetPoint("LEFT", r.check, "RIGHT", 2, 0)
    S.Box(frameIcon, { 0, 0, 0, 1 })
    r.icon = frameIcon:CreateTexture(nil, "ARTWORK")
    r.icon:SetPoint("TOPLEFT", 1, -1)
    r.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.text = S.Text(r, 12)
    r.text:SetPoint("TOPLEFT", frameIcon, "TOPRIGHT", 6, 1)
    r.text:SetPoint("RIGHT", -4, 0)
    r.text:SetWordWrap(false)
    r.sub = S.Text(r, 10, S.MUTED)
    r.sub:SetPoint("TOPLEFT", r.text, "BOTTOMLEFT", 0, -3)
    r.sub:SetPoint("RIGHT", -4, 0)
    r.sub:SetWordWrap(false)
    r:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetBagItem(self.data.bag, self.data.slot)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return r
end

local function makeLabel()
    local r = CreateFrame("Frame", nil, content)
    r:SetSize(LEFT_W, ROW_H)
    r.text = S.Text(r, 13, S.MUTED)
    r.text:SetPoint("LEFT", 30, 0)
    return r
end

local function makeLine()
    local l = content:CreateLine(nil, "BACKGROUND")
    l:SetThickness(2)
    return l
end

local function makeBand()
    local t = content:CreateTexture(nil, "BACKGROUND", nil, -1)
    t:SetTexture("Interface\\Buttons\\WHITE8X8")
    return t
end

---- Drawing -------------------------------------------------------------------

local function levelText(level)
    local c = GetQuestDifficultyColor and GetQuestDifficultyColor(level)
    local hex = c and S.Hex({ c.r, c.g, c.b }) or S.Hex(S.MUTED)
    return hex .. level .. "|r  "
end

local function connect(from, to, on)
    local l = take("line", makeLine)
    l:SetStartPoint("RIGHT", from, 0, 0)
    l:SetEndPoint("LEFT", to, 0, 0)
    local c = on and S.Accent() or DIM
    l:SetColorTexture(c[1], c[2], c[3], on and 0.9 or c[4])
end

local function band(y, h, color)
    local b = take("band", makeBand)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", 0, -y)
    b:SetSize(content:GetWidth(), h)
    b:SetVertexColor(color[1], color[2], color[3], color[4])
end

local function placeItem(it, y, x, width)
    local r = take("item", makeItemRow)
    r.data = it
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", x, -y)
    r:SetWidth(width)
    local blocked = false
    for _, q in ipairs(it.links) do
        if not q.checked then blocked = true end
    end
    r.locked = blocked
    r.check:SetChecked(it.checked and not blocked)
    r.check:SetEnabled(not blocked)
    r.icon:SetTexture(it.icon)
    r.text:SetText((it.link or it.name) .. (it.count > 1 and (S.Hex(S.MUTED) .. "  x" .. it.count .. "|r") or ""))
    r.sub:SetText(L[blocked and "WHY_QUEST_STAYS" or it.why] .. (it.bank and ("  ·  " .. L.IN_BANK) or ""))
    focusList[#focusList + 1] = r
    r:SetAlpha(ns.ItemGoes(it) and 1 or 0.45)
    return r
end

refresh = function()
    releaseAll()
    local width = content:GetWidth()
    local rightX = LEFT_W + GAP
    local rightW = width - rightX

    -- Each item is listed under the first planned quest that needs it.
    local byQuest, orphans = {}, {}
    for _, q in ipairs(plan.quests) do byQuest[q] = {} end
    for _, it in ipairs(plan.items) do
        local home
        for _, q in ipairs(it.links) do
            if byQuest[q] then home = q break end
        end
        if home then table.insert(byQuest[home], it) else orphans[#orphans + 1] = it end
    end

    local y = 0
    local questRow, itemRow = {}, {}
    local accent = S.Accent()
    for _, zone in ipairs(ns.Zones(plan.quests)) do
        band(y, ZONE_H, { 1, 1, 1, 0.06 })
        local z = take("zone", makeZoneRow)
        z.data = zone
        z:ClearAllPoints()
        z:SetPoint("TOPLEFT", 0, -y)
        local on = 0
        for _, q in ipairs(zone.quests) do if q.checked then on = on + 1 end end
        z.check:SetChecked(on == #zone.quests or (on > 0 and "some"))
        z.text:SetText(S.Hex(accent) .. (zone.name ~= "" and zone.name or "?") .. "|r")
        z.count:SetText(on .. "/" .. #zone.quests)
        focusList[#focusList + 1] = z
        y = y + ZONE_H + 2

        for _, q in ipairs(zone.quests) do
            local items = byQuest[q]
            local h = math.max(1, #items) * ROW_H
            local r = take("quest", makeQuestRow)
            r.data = q
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 14, -y)
            r.check:SetChecked(q.checked)
            local tag = q.warn and ("  " .. S.Hex({ 1, 0.6, 0.2 }) .. L[q.warn] .. "|r") or ""
            r.text:SetText(levelText(q.level) .. q.title .. tag)
            r:SetAlpha(q.checked and 1 or 0.45)
            focusList[#focusList + 1] = r
            questRow[q] = r
            for i, it in ipairs(items) do
                itemRow[it] = placeItem(it, y + (i - 1) * ROW_H, rightX, rightW)
            end
            y = y + h + 2
        end
        y = y + 6
    end
    if #orphans > 0 then
        band(y, ZONE_H, { 1, 1, 1, 0.06 })
        local label = take("label", makeLabel)
        label:ClearAllPoints()
        label:SetPoint("TOPLEFT", 0, -y)
        label:SetHeight(ZONE_H)
        label.text:SetText(L.NO_QUEST)
        y = y + ZONE_H + 2
        for i, it in ipairs(orphans) do
            itemRow[it] = placeItem(it, y + (i - 1) * ROW_H, rightX, rightW)
            connect(label, itemRow[it], ns.ItemGoes(it))
        end
        y = y + #orphans * ROW_H
    end
    for _, it in ipairs(plan.items) do
        for _, q in ipairs(it.links) do
            if questRow[q] and itemRow[it] then connect(questRow[q], itemRow[it], ns.ItemGoes(it)) end
        end
    end
    content:SetHeight(math.max(y, 1))
    scroll:Update(y)
    if focus > #focusList then focus = #focusList end
    for i, r in ipairs(focusList) do r.focus:SetShown(i == focus) end

    local nq, ni = 0, 0
    for _, q in ipairs(plan.quests) do if q.checked then nq = nq + 1 end end
    for _, it in ipairs(plan.items) do if ns.ItemGoes(it) then ni = ni + 1 end end
    questHead:SetText(L.QUESTS_N:format(nq, #plan.quests))
    itemHead:SetText(L.ITEMS_N:format(ni, #plan.items))
    summary:SetText(L.SUMMARY:format(nq, ni))
    local inLog, freeNow = #ns.Quests(), ns.FreeSlots()
    frees:SetText(L.FREES:format(inLog, inLog - nq, ns.MaxQuests(), freeNow, freeNow + ni))
    okButton:SetEnabled(nq + ni > 0)
end

---- Views ---------------------------------------------------------------------

local function showView(isPreview)
    setup:SetShown(not isPreview)
    preview:SetShown(isPreview)
    clearButton:SetShown(not isPreview)
    okButton:SetShown(isPreview)
    backButton:SetShown(isPreview)
end

function ns.ShowLocks()
    if not locksRow then return end
    local q, i = 0, 0
    for _ in pairs(ns.db().keepQuests) do q = q + 1 end
    for _ in pairs(ns.db().keep) do i = i + 1 end
    locksRow.desc:SetText(L.LOCKED_N:format(q, i))
end

local function showSetup()
    showView(false)
    ns.ShowLocks()
    S.FitWindow(frame, setupH)
    edit:SetText(tostring(ns.charDB().level or math.max(1, UnitLevel("player") - 10)))
    levelRow.desc:SetText(L.YOUR_LEVEL:format(UnitLevel("player")))
end

local function showPreview()
    showView(true)
    S.SetWindowHeight(frame, PREVIEW_H)
    local width = scroll:GetWidth()
    content:SetWidth(width > 0 and width or W - 80)
    scroll:Top()
    refresh()
end

local function onClear()
    local level = tonumber(edit:GetText())
    if not level or level < 1 or level > 99 then
        setStatus(L.BAD_LEVEL)
        return
    end
    local d = ns.db()
    ns.charDB().level = level
    d.quests, d.items = d.quests ~= false, d.items ~= false
    local zone = ns.oneZone or (d.zoneOnly and GetRealZoneText and GetRealZoneText()) or nil
    ns.oneZone = nil
    plan.quests = d.quests and ns.PlanQuests(level, { zone = zone }) or {}
    plan.items, plan.future = {}, {}
    if d.items then plan.items, plan.future = ns.PlanItems(plan.quests, level) end
    totals.quests, totals.items = 0, 0
    local kept = #plan.future > 0 and L.FUTURE:format(#plan.future) or ""
    if #plan.quests + #plan.items == 0 then
        setStatus(L.NOTHING .. (kept ~= "" and ("  " .. kept) or ""))
        return
    end
    showPreview()
    setStatus(kept)
end

local function onOK()
    local keep, keepQuests = ns.db().keep, ns.db().keepQuests
    for _, it in ipairs(plan.items) do
        if not it.checked then keep[it.itemID] = true end
    end
    -- A quest the player unticked stays locked until /gqc reset, like an item.
    for _, q in ipairs(plan.quests) do
        if not q.checked then keepQuests[q.questID] = q.title end
    end
    local beforeQ, beforeI = ns.Leftover(plan.quests, plan.items)
    ns.Run(plan.quests, plan.items)
    okButton:Disable()
    backButton:Disable()
    -- Abandons and deletes land a moment later; then count what really went and show
    -- what the game refused.
    C_Timer.After(1, function()
        backButton:Enable()
        local q, i = ns.Leftover(plan.quests, plan.items)
        totals.quests = totals.quests + #beforeQ - #q
        totals.items = totals.items + #beforeI - #i
        if #q + #i == 0 then
            local done = L.DONE:format(totals.quests, totals.items)
            ns.Print(done)
            if GulliToolkit and GulliToolkit.Notify then GulliToolkit.Notify("QuestCleaner", done) end
            plan.quests, plan.items = {}, {}
            showSetup()
            setStatus(done)
        else
            plan.quests, plan.items = q, i
            showPreview()
            setStatus(L.LEFT:format(#q + #i))
            if GulliToolkit and GulliToolkit.Notify then GulliToolkit.Notify("QuestCleaner", L.LEFT:format(#q + #i)) end
        end
    end)
end

---- Build ---------------------------------------------------------------------

local function button(parent, key, width)
    local b = S.Button(parent, width, 32)
    say(b, key)
    return b
end

-- A switch row for an account-wide setting that is on unless it was turned off.
local function setting(key, label, icon)
    return { L[label], nil, function() return ns.db()[key] ~= false end,
             function(v) ns.db()[key] = v and true or false end, icon = I .. icon }
end

local function build()
    frame = S.Window("GulliQuestCleanerFrame", "Quest Cleaner", W, PREVIEW_H)
    footer = S.Footer(frame)
    okButton = S.Danger(button(footer, "OK", 150))
    footer:Add(okButton)
    okButton:SetScript("OnClick", onOK)
    backButton = S.Ghost(button(footer, "BACK", 110))
    footer:Add(backButton)
    backButton:SetScript("OnClick", function()
        showSetup()
        setStatus("")
    end)
    clearButton = S.Primary(button(footer, "CLEAR", 150))
    clearButton:SetParent(footer)
    clearButton:SetPoint("RIGHT", -S.PAD, 0)
    clearButton:SetScript("OnClick", onClear)

    local body, width = frame.body, frame.inner[1]

    -- Setup view: the level, what to clean, what always stays.
    setup = CreateFrame("Frame", nil, body)
    setup:SetAllPoints()
    local st = S.Stack(setup)

    local level = CreateFrame("Frame", nil, setup)
    level:SetSize(44 + 8 + 90, 32)
    edit = S.Edit(level, 40, 32)
    edit:SetPoint("LEFT")
    edit:SetNumeric(true)
    edit:SetMaxLetters(2)
    edit:SetScript("OnEnterPressed", function(self) self:ClearFocus(); onClear() end)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local gray = button(level, "GRAY", 64)
    gray:SetPoint("LEFT", edit, "RIGHT", 6, 0)
    gray:SetScript("OnClick", function() edit:SetText(tostring(math.max(1, ns.GrayLevel()))) end)
    local green = button(level, "GREEN", 64)
    green:SetPoint("LEFT", gray, "RIGHT", 6, 0)
    green:SetScript("OnClick", function() edit:SetText(tostring(ns.GreenLevel())) end)
    level:SetWidth(40 + 6 + 64 + 6 + 64)
    local levelCard, h = S.SettingsCard(setup, nil, {
        { L.LEVEL .. " " .. L.OR_LOWER, L.YOUR_LEVEL:format(UnitLevel("player")), control = level } })
    levelRow = levelCard.rows[1]
    st:Add(levelCard, h)

    local what, wh = S.SettingsCard(setup, L.SEC_WHAT, {
        setting("quests", "DO_QUESTS", "INV_Scroll_03"),
        setting("items", "DO_ITEMS", "INV_Misc_Bag_10"),
        setting("offerFailed", "DO_FAILED", "Spell_ChargeNegative"),
        { L.ZONE_ONLY, nil, function() return ns.db().zoneOnly == true end,
          function(v) ns.db().zoneOnly = v and true or false end, icon = I .. "INV_Misc_Map_01" },
    })
    st:Add(what, wh)

    -- The right column: what always stays, and the rest.
    local right = CreateFrame("Frame", nil, setup)
    local half = math.floor((width - S.GAP) / 2)
    right:SetPoint("TOPLEFT", half + S.GAP, 0)
    right:SetPoint("BOTTOMRIGHT")
    local rt = S.Stack(right)
    local keep, kh = S.SettingsCard(right, L.SEC_KEEP, {
        setting("keepComplete", "KEEP_COMPLETE", "INV_Misc_Book_09"),
        setting("keepClass", "KEEP_CLASS", "INV_Misc_Book_11"),
        setting("keepDungeon", "KEEP_DUNGEON", "INV_Misc_Key_14"),
        setting("keepElite", "KEEP_ELITE", "INV_Misc_Head_Dragon_01"),
        { L.KEEP_GROUP, nil, function()
            local d = ns.db()
            if d.keepGroup == nil then return d.keepElite ~= false end
            return d.keepGroup
        end, function(v) ns.db().keepGroup = v and true or false end, icon = I .. "Spell_Holy_PrayerOfHealing" },
    })
    rt:Add(keep, kh)
    local keyButton = S.Button(right, 110, 28)
    keyButton:EnableKeyboard(false)
    local function showKey() keyButton:SetText(ns.db().key or L.KEY_NONE) end
    keyButton:SetScript("OnClick", function(self)
        self:SetText(L.KEY_PRESS)
        self:EnableKeyboard(true)
    end)
    keyButton:SetScript("OnKeyDown", function(self, key)
        if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL" or key == "LALT" or key == "RALT" then return end
        self:EnableKeyboard(false)
        if key == "ESCAPE" then ns.db().key = nil
        else
            local mod = (IsShiftKeyDown and IsShiftKeyDown() and "SHIFT-" or "") ..
                        (IsControlKeyDown and IsControlKeyDown() and "CTRL-" or "") ..
                        (IsAltKeyDown and IsAltKeyDown() and "ALT-" or "")
            ns.db().key = mod .. key
        end
        ns.ApplyKey()
        showKey()
    end)
    showKey()
    local locks = S.Button(right, 110, 28)
    say(locks, "RESET")
    locks:SetScript("OnClick", function()
        SlashCmdList.GULLIQUESTCLEANER("reset")
        ns.ShowLocks()
    end)
    local more, mh = S.SettingsCard(right, nil, {
        setting("tooltip", "OPT_TOOLTIP", "INV_Misc_Note_01"),
        { L.KEY, L.KEY_D, control = keyButton, icon = I .. "INV_Misc_Key_04" },
        { L.LOCKED, L.LOCKED_N:format(0, 0), control = locks, icon = I .. "INV_Box_01" },
    })
    locksRow = more.rows[3]
    rt:Add(more, mh)
    what:SetPoint("TOPRIGHT", setup, "TOPLEFT", half, -(st.y - wh - st.gap))
    levelCard:SetPoint("TOPRIGHT", setup, "TOPLEFT", half, 0)
    setupH = math.max(st:Height(), rt:Height())

    -- Preview view: quests on the left, items on the right, the totals under them.
    preview = CreateFrame("Frame", nil, body)
    preview:SetAllPoints()
    preview:Hide()

    frees = S.Text(preview, 11, S.MUTED)
    frees:SetPoint("BOTTOMLEFT", 0, 0)
    frees:SetPoint("RIGHT", 0, 0)
    frees:SetWordWrap(false)
    summary = S.Text(preview, 13)
    summary:SetPoint("BOTTOMLEFT", frees, "TOPLEFT", 0, 6)
    summary:SetPoint("RIGHT", 0, 0)
    summary:SetWordWrap(false)

    local card = S.Card(preview)
    card:SetPoint("TOPLEFT")
    card:SetPoint("TOPRIGHT")
    card:SetPoint("BOTTOM", summary, "TOP", 0, S.GAP)
    local cb = card.body
    local accent = S.Accent()
    questHead = S.Text(cb, 13, accent)
    questHead:SetPoint("TOPLEFT", 4, 0)
    itemHead = S.Text(cb, 13, accent)
    itemHead:SetPoint("TOPLEFT", 4 + LEFT_W + GAP, 0)
    local rule = S.Divider(cb, S.EDGE)
    rule:SetPoint("TOPLEFT", 0, -24)
    rule:SetPoint("TOPRIGHT", 0, -24)
    rule:SetHeight(1)

    scroll = S.Scroll(cb)
    scroll:SetPoint("TOPLEFT", 0, -34)
    scroll:SetPoint("BOTTOMRIGHT", -12, 0)
    content = scroll.child
    content:SetWidth(width - 2 * S.INSET - 12)

    frame:SetScript("OnShow", function()
        showSetup(); setStatus("")
        if frame.EnableGamePadButton then frame:EnableGamePadButton(true) end
    end)
    -- A gamepad steps through the preview rows: up and down move, A ticks, X runs the main
    -- button (Clear, then OK), B goes back.
    frame:SetScript("OnGamePadButtonDown", function(_, b) ns.Pad(b) end)
    ns.frameBuilt = true
    ns.ApplyTexts()
end

function ns.Pad(b)
    local inPreview = preview:IsShown()
    if b == "PADDDOWN" and inPreview then
        focus = math.min(#focusList, focus + 1); refresh()
    elseif b == "PADDUP" and inPreview then
        focus = math.max(1, focus - 1); refresh()
    elseif b == "PAD1" and inPreview and focusList[focus] then
        focusList[focus].toggle()
    elseif b == "PAD3" then
        if inPreview then if okButton:IsEnabled() then onOK() end else onClear() end
    elseif b == "PAD2" then
        if inPreview then showSetup(); setStatus("") else frame:Hide() end
    else
        return false
    end
    return true
end

function ns.Clear() onClear() end

function ns.ApplyTexts()
    for _, e in ipairs(labels) do e[1]:SetText(L[e[2]]) end
    if levelRow then levelRow.desc:SetText(L.YOUR_LEVEL:format(UnitLevel("player"))) end
    if preview:IsShown() then refresh() end
end

function ns.Toggle()
    S.ToggleWindow(ns.Window())
end

-- The window, for the hub (/gulli) to show inside it.
function ns.Window()
    if not frame then build() end
    return frame
end
