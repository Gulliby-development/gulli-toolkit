-- Three pages: Rules (the switches, one row per quality and per item type), Items (the item
-- rules: drop an item, Alt-click one, or /glt need <link>; search; a rule per row in segments)
-- and Recent (the last rolls with their reason and who won; a row makes a rule in one tap).

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, pages, pageTabs
local qtabs, ttabs = {}, {}
local itemList, itemEmpty, search, logList, logEmpty
local QUALITY_COLOR = { [0] = "|cff9d9d9d", [1] = "|cffffffff", [2] = "|cff1eff00" }
local SEG_W = 40
-- The game's own roll pictures, so a rule reads like the roll window.
local ROLL_ICON = {
    ask = "Interface\\Icons\\INV_Misc_QuestionMark",
    need = "Interface\\Buttons\\UI-GroupLoot-Dice-Up",
    safe = "Interface\\Icons\\Ability_Defend",
    greed = "Interface\\Buttons\\UI-GroupLoot-Coin-Up",
    pass = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
}

-- A segmented choice of rolls drawn as the game's roll icons; the cursor names each one.
local function rollTabs(holder, values, onSelect, height)
    local labels, icons = {}, {}
    for i, v in ipairs(values) do labels[i] = ""; icons[i] = ROLL_ICON[v] end
    local t = S.Tabs(holder, labels, SEG_W, onSelect, height, icons)
    for i, v in ipairs(values) do t.buttons[i].tip = L["SEG_" .. v:upper()] end
    return t
end

local function indexOf(t, v) for i, x in ipairs(t) do if x == v then return i end end return 1 end

local function itemIcon(id)
    return (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function quality(id)
    local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local q = f and select(3, f(id))
    return q
end

-- The rule's item name in its quality colour (S.QualityHex already starts with |cff).
function ns.ItemLabel(e)
    local q = quality(e.id)
    return q and (S.QualityHex(q) .. e.name .. "|r") or e.name
end

---- Items page ---------------------------------------------------------------------

local function makeItemRow(r)
    r.iconBox = S.IconBox(r, 22)
    r.iconBox:SetPoint("LEFT", 4, 0)
    r.icon = r.iconBox.tex
    r.remove = S.Close(r, function(self) ns.SetItem(self:GetParent().entry.id, nil) end)
    r.remove:SetPoint("RIGHT", 0, 0)
    local holder = CreateFrame("Frame", nil, r)
    holder:SetSize(#ns.ITEM_RULES * SEG_W + 4, 28)
    holder:SetPoint("RIGHT", r.remove, "LEFT", -6, 0)
    r.seg = rollTabs(holder, ns.ITEM_RULES, function(i)
        if r.entry and r.entry.rule ~= ns.ITEM_RULES[i] then ns.SetItem(r.entry.id, ns.ITEM_RULES[i]) end
    end, 28)
    r.text = S.Text(r, 12)
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
    r.text:SetPoint("RIGHT", holder, "LEFT", -8, 0)
    r.text:SetWordWrap(false)
end

local function fillItemRow(r, e)
    r.entry = e
    r.icon:SetTexture(itemIcon(e.id))
    r.text:SetText(ns.ItemLabel(e))
    r.seg:Select(indexOf(ns.ITEM_RULES, e.rule), true)
end

---- Recent page --------------------------------------------------------------------

local function makeLogRow(r)
    r.iconBox = S.IconBox(r, 22)
    r.iconBox:SetPoint("LEFT", 4, 0)
    r.icon = r.iconBox.tex
    r.make = S.Button(r, 90, 28)
    r.make:SetPoint("RIGHT", 0, 0)
    r.make:SetText(L.MAKE_RULE)
    r.make:SetScript("OnClick", function(self)
        local e = self:GetParent().entry
        if e and e.id then
            ns.SetItem(e.id, e.rule or "greed")
            pageTabs:Select(2)
        end
    end)
    r.text = S.Text(r, 12)
    r.text:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, 2)
    r.text:SetPoint("RIGHT", r.make, "LEFT", -8, 0)
    r.text:SetWordWrap(false)
    r.sub = S.Note(r, 11)
    r.sub:SetPoint("TOPLEFT", r.text, "BOTTOMLEFT", 0, -2)
    r.sub:SetPoint("RIGHT", r.make, "LEFT", -8, 0)
    r.sub:SetWordWrap(false)
end

local function fillLogRow(r, e)
    r.entry = e
    r.icon:SetTexture(e.id and itemIcon(e.id) or "Interface\\Icons\\INV_Misc_QuestionMark")
    r.text:SetText(e.link or "?")
    local what = e.rule and L["RULE_" .. e.rule:upper()] or L.RULE_ASK
    local line = what .. " · " .. L["WHY_" .. (e.reason or "ask"):upper()]
    if e.winner then line = line .. " · " .. L.WINNER:format(e.winner) end
    r.sub:SetText(line)
    r.make:SetShown(e.id ~= nil and ns.db.items[e.id] == nil)
end

---- Refresh ------------------------------------------------------------------------

function ns.Refresh()
    if not frame or not frame:IsShown() then return end
    for q, t in pairs(qtabs) do t:Select(indexOf(ns.RULES, ns.db.quality[q] or "ask"), true) end
    for class, t in pairs(ttabs) do t:Select(indexOf(ns.RULES, ns.db.types[class] or "ask"), true) end
    local items = ns.Items(search and search:GetText())
    itemList:SetData(items)
    itemEmpty:SetShown(#items == 0)
    search:SetShown(#ns.Items() > 10 or (search:GetText() or "") ~= "")
    logList:SetData(ns.db.log)
    logEmpty:SetShown(#ns.db.log == 0)
    for _, f in ipairs(frame.switches) do if f.Refresh then f:Refresh() end end
end

local function dropItem()
    local kind, id = GetCursorInfo()
    if kind == "item" and id then
        ClearCursor()
        if not ns.db.items[id] then ns.SetItem(id, "greed") end
    end
end

---- Building -----------------------------------------------------------------------

local function segRow(values, get, set)
    local holder = CreateFrame("Frame", nil, frame.body)
    local t
    if ROLL_ICON[values[1]] then
        holder:SetSize(#values * SEG_W + 4, 30)
        t = rollTabs(holder, values, function(sel) set(values[sel]) end)
    else
        local labels = {}
        for i, v in ipairs(values) do labels[i] = L["SEG_" .. v:upper()] end
        holder:SetSize(#labels * 78 + 4, 30)
        t = S.Tabs(holder, labels, 78, function(sel) set(values[sel]) end)
    end
    t:Select(indexOf(values, get()), true)
    return holder, t
end

local function switch(key, label, desc)
    return { label, desc, function() return ns.db[key] end, function(v) ns.SetPref(key, v) end, icon = ns.OPT_ICON[key] }
end

local function buildRules(page, width)
    local st = S.Stack(page)
    local main, mh = S.SettingsCard(page, nil, {
        switch("on", L.OPT_ON, L.OPT_ON_D),
        switch("report", L.OPT_REPORT),
    })
    st:Add(main, mh)

    local qrows = {}
    for i, q in ipairs(ns.QUALITIES) do
        local holder, t = segRow(ns.RULES, function() return ns.db.quality[q] or "ask" end,
            function(v) ns.db.quality[q] = v end)
        qtabs[q] = t
        qrows[i] = { QUALITY_COLOR[q] .. L["Q" .. q] .. "|r", nil, control = holder }
    end
    local wholder, wt = segRow(ns.WHERE, function() return ns.db.where end, function(v) ns.SetPref("where", v) end)
    frame.switches[#frame.switches + 1] = { Refresh = function() wt:Select(indexOf(ns.WHERE, ns.db.where), true) end }
    qrows[#qrows + 1] = { L.OPT_WHERE, nil, control = wholder, icon = ns.OPT_ICON.where }
    local qc, qh = S.SettingsCard(page, L.SEC_QUALITY, qrows)
    st:Add(qc, qh)

    local trows = {}
    for i, t in ipairs(ns.TYPES) do
        local holder, tabs = segRow(ns.RULES, function() return ns.db.types[t.class] or "ask" end,
            function(v) ns.SetType(t.class, v) end)
        ttabs[t.class] = tabs
        trows[i] = { L["TYPE_" .. t.key], nil, control = holder }
    end
    local tc, th = S.SettingsCard(page, L.SEC_TYPES, trows)
    st:Add(tc, th)

    local oc, oh = S.SettingsCard(page, L.SEC_MORE, {
        switch("greedUnusable", L.OPT_UNUSABLE, L.OPT_UNUSABLE_D),
        switch("needUpgrade", L.OPT_UPGRADE, L.OPT_UPGRADE_D),
        switch("fastLoot", L.OPT_FAST, L.OPT_FAST_D),
        switch("soloConfirm", L.OPT_SOLO, L.OPT_SOLO_D),
    })
    st:Add(oc, oh)
    local note, nh = S.Paragraph(page, L.NOTE, width)
    st:Add(note, nh)
    return st:Height()
end

local function buildItems(page, height)
    local drop = S.DropZone(page, L.DROP, dropItem, 36)
    drop:SetPoint("BOTTOMLEFT")
    drop:SetPoint("BOTTOMRIGHT")
    local hint = S.Note(page, 11)
    hint:SetPoint("BOTTOMLEFT", drop, "TOPLEFT", 0, 6)
    hint:SetPoint("BOTTOMRIGHT", drop, "TOPRIGHT", 0, 6)
    hint:SetText(L.ITEMS_HINT)
    search = S.Edit(page, 200, 28)
    search:SetPoint("TOPLEFT")
    search:SetPoint("TOPRIGHT")
    S.Placeholder(search, L.SEARCH)
    search:SetScript("OnTextChanged", function() ns.Refresh() end)
    itemList = S.List(page, 34, makeItemRow, fillItemRow)
    itemList:SetPoint("TOPLEFT", 0, -36)
    itemList:SetPoint("BOTTOMRIGHT", hint, "TOPRIGHT", -10, 8)
    itemEmpty = S.Empty(itemList)
    itemEmpty:Set(L.NO_ITEMS)
end

local function buildRecent(page)
    logList = S.List(page, 40, makeLogRow, fillLogRow)
    logList:SetPoint("TOPLEFT")
    logList:SetPoint("BOTTOMRIGHT", -10, 0)
    logEmpty = S.Empty(logList)
    logEmpty:Set(L.NO_LOG, L.NO_LOG_D)
end

local function build()
    frame = S.Window("GulliLootFrame", L.TITLE, S.NARROW_W, S.DOCK_H)
    frame.switches = {}
    local ft = S.Footer(frame)
    ft:SetStatus(L.FOOTER)
    local body, width = frame.body, frame.inner[1]
    local holder = CreateFrame("Frame", nil, body)
    holder:SetPoint("TOPLEFT")
    holder:SetSize(width, 30)
    pages = {}
    pageTabs = S.Tabs(holder, { L.PAGE_RULES, L.PAGE_ITEMS, L.PAGE_RECENT }, nil, function(i)
        for j, p in ipairs(pages) do p:SetShown(j == i) end
        ns.Refresh()
    end, nil, { S.TAB.rules, S.TAB.items, S.TAB.recent })
    for i = 1, 3 do
        local p = i == 1 and S.Scroll(body) or CreateFrame("Frame", nil, body)
        p:SetPoint("TOPLEFT", 0, -38)
        p:SetPoint("BOTTOMRIGHT", i == 1 and -12 or 0, 0)
        pages[i] = p
    end
    local rules = pages[1]
    rules.child:SetWidth(width - 12)
    local h = buildRules(rules.child, width - 12)
    rules.child:SetHeight(h)
    rules:Update(h)
    buildItems(pages[2])
    buildRecent(pages[3])
    pages[2]:Hide()
    pages[3]:Hide()
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
