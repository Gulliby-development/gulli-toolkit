-- Four pages: Rolls (what to roll for each quality and item type, the roll window), Pickup
-- (looting and the loot feed with an example of it), Items (the item rules, rule by rule: drop
-- an item, Alt-click one, or /glt need <link>) and History (the last rolls with what was rolled,
-- why and who won; a row makes a rule in one tap).

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, pages, pageTabs
local qtabs, ttabs = {}, {}
local itemList, itemEmpty, search, logList, logEmpty
local QUALITY_COLOR = { [0] = "|cff9d9d9d", [1] = "|cffffffff", [2] = "|cff1eff00" }
local ITEMS_TOP = 66 -- the drop zone and its hint over the item list
local SEG_W = 40
local COL_W = 64 -- a roll column on the Rolls page, wide enough for the word over it
-- The game's own roll pictures, so a rule reads like the roll window.
local ROLL_ICON = {
    ask = "Interface\\Icons\\INV_Misc_QuestionMark",
    need = "Interface\\Buttons\\UI-GroupLoot-Dice-Up",
    safe = "Interface\\Icons\\Ability_Defend",
    greed = "Interface\\Buttons\\UI-GroupLoot-Coin-Up",
    pass = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
}

-- A segmented choice of rolls drawn as the game's roll icons; the cursor names each one.
local function rollTabs(holder, values, onSelect, height, width)
    local labels, icons = {}, {}
    for i, v in ipairs(values) do labels[i] = ""; icons[i] = ROLL_ICON[v] end
    local t = S.Tabs(holder, labels, width or SEG_W, onSelect, height, icons)
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
    r.holder = holder
    r.seg = rollTabs(holder, ns.ITEM_RULES, function(i)
        if r.entry and r.entry.rule ~= ns.ITEM_RULES[i] then ns.SetItem(r.entry.id, ns.ITEM_RULES[i]) end
    end, 28)
    r.text = S.Text(r, 12)
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
    r.text:SetPoint("RIGHT", holder, "LEFT", -8, 0)
    r.text:SetWordWrap(false)
    -- a group's head: the rule's roll icon, its name and how many items it has
    r.head = S.Text(r, 12, S.GOLD_DIM, nil, "bold")
    r.head:SetPoint("BOTTOMLEFT", 4, 6)
    r.head:SetWordWrap(false)
    r.count = S.Text(r, 12, S.FAINT)
    r.count:SetPoint("BOTTOMRIGHT", -6, 6)
end

local function fillItemRow(r, e)
    local head = e.head ~= nil
    r.entry = not head and e or nil
    r.iconBox:SetShown(not head); r.remove:SetShown(not head); r.holder:SetShown(not head); r.text:SetShown(not head)
    r.head:SetShown(head); r.count:SetShown(head)
    if head then
        r.head:SetText(S.IconTag(ROLL_ICON[e.head], 14) .. " " .. S.Upper(L["RULE_" .. e.head:upper()]))
        r.count:SetText(tostring(e.count))
        return
    end
    r.icon:SetTexture(itemIcon(e.id))
    r.text:SetText(ns.ItemLabel(e))
    r.seg:Select(indexOf(ns.ITEM_RULES, e.rule), true)
end

---- History page -------------------------------------------------------------------

local PILL_W = 112

-- What a History row says under the item: why it was rolled so and, on a line of its own once
-- the roll is over, who won.
function ns.LogSub(e)
    local won
    if e.winner then
        local me = UnitName and UnitName("player")
        won = (me and e.winner == me) and (S.Hex(S.GOOD) .. L.LOG_YOU .. "|r") or L.WINNER:format(e.winner)
    end
    return L["WHY_" .. (e.reason or "ask"):upper()], won
end

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
            pageTabs:Select(3)
        end
    end)
    -- what was rolled, as the game's roll picture and its word
    r.pill = CreateFrame("Frame", nil, r)
    r.pill:SetSize(PILL_W, 24)
    r.pill:SetPoint("RIGHT", -96, 0)
    S.Box(r.pill, S.INPUT, S.EDGE, S.R_MD)
    r.what = S.Text(r.pill, 12)
    r.what:SetPoint("LEFT", 6, 0)
    r.what:SetPoint("RIGHT", -6, 0)
    r.what:SetJustifyH("CENTER")
    r.what:SetWordWrap(false)
    r.text = S.Text(r, 12)
    r.text:SetPoint("TOPLEFT", 34, -5)
    r.text:SetPoint("RIGHT", r.pill, "LEFT", -8, 0)
    r.text:SetWordWrap(false)
    r.sub = S.Note(r, 12)
    r.sub:SetPoint("TOPLEFT", r.text, "BOTTOMLEFT", 0, -2)
    r.sub:SetPoint("RIGHT", r.pill, "LEFT", -8, 0)
    r.sub:SetWordWrap(false)
    r.won = S.Note(r, 12)
    r.won:SetPoint("TOPLEFT", r.sub, "BOTTOMLEFT", 0, -2)
    r.won:SetPoint("RIGHT", r.pill, "LEFT", -8, 0)
    r.won:SetWordWrap(false)
end

local function fillLogRow(r, e)
    r.entry = e
    r.icon:SetTexture(e.id and itemIcon(e.id) or "Interface\\Icons\\INV_Misc_QuestionMark")
    r.text:SetText(e.link or "?")
    local rule = e.rule or "ask"
    r.what:SetText(S.IconTag(ROLL_ICON[rule], 14) .. " " .. L[rule == "ask" and "COL_ASK" or ("RULE_" .. rule:upper())])
    local why, won = ns.LogSub(e)
    r.sub:SetText(why)
    r.won:SetShown(won ~= nil)
    r.won:SetText(won or "")
    r.make:SetShown(e.id ~= nil and ns.db.items[e.id] == nil)
end

---- The loot feed's example --------------------------------------------------------

-- A still copy of the feed with sample loot, drawn from the same lines (ns.FeedLine), so the
-- feed's settings show what they change. It never takes part in the real feed.
local SAMPLE_H, S_ROW, S_ROW2, S_FOOT, S_PAD = 152, 26, 40, 24, 6
local sampleBox

local function buildSample(parent)
    local box = CreateFrame("Frame", nil, parent)
    box:SetHeight(SAMPLE_H)
    S.Box(box, S.SIDE, S.LINE, S.R_MD)
    local panel = CreateFrame("Frame", nil, box)
    panel:SetPoint("CENTER")
    panel.back = CreateFrame("Frame", nil, panel)
    panel.back:SetAllPoints()
    S.HudPanel(panel.back)
    panel.rows = {}
    for i = 1, 3 do
        local r = CreateFrame("Frame", nil, panel)
        r.icon = S.IconBox(r, 20)
        r.icon:SetPoint("LEFT", 2, 0)
        r.price = S.Text(r, 12); r.price:SetJustifyH("RIGHT")
        r.text = S.Text(r, 12); r.text:SetWordWrap(false)
        r.src = S.Text(r, 12, S.FAINT); r.src:SetJustifyH("RIGHT")
        r.note = S.Text(r, 12, S.MUTED); r.note:SetWordWrap(false)
        panel.rows[i] = r
    end
    panel.foot = CreateFrame("Frame", nil, panel)
    panel.foot:SetHeight(S_FOOT)
    panel.foot:SetPoint("BOTTOMLEFT", S_PAD, S_PAD - 2)
    panel.foot:SetPoint("BOTTOMRIGHT", -S_PAD, S_PAD - 2)
    panel.foot.label = S.Text(panel.foot, 12, S.GOLD_DIM, nil, "bold")
    panel.foot.label:SetPoint("LEFT", 4, -1)
    panel.foot.label:SetText(S.Upper(L.FEED_TOTAL))
    panel.foot.value = S.Text(panel.foot, 12)
    panel.foot.value:SetPoint("RIGHT", -4, -1)
    box.panel = panel
    function box:Refresh()
        if not ns.FeedSample then return end
        local list, shown = ns.FeedSample(), {}
        local y = S_PAD
        for i, r in ipairs(panel.rows) do
            local e = i <= ns.FeedRows() and list[i] or nil
            r:SetShown(e ~= nil)
            if e then
                shown[#shown + 1] = e
                local ln = ns.FeedLine(e)
                local two = ln.note ~= nil
                local h = two and S_ROW2 or S_ROW
                r:SetHeight(h)
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", S_PAD, -y)
                r:SetPoint("RIGHT", -S_PAD, 0)
                y = y + h
                r.icon:SetIcon(e.icon)
                r.price:ClearAllPoints(); r.text:ClearAllPoints(); r.note:ClearAllPoints(); r.src:ClearAllPoints()
                r.price:SetPoint("RIGHT", -4, two and 8 or 0)
                r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, two and 8 or 0)
                r.text:SetPoint("RIGHT", r.price, "LEFT", -6, 0)
                r.src:SetPoint("RIGHT", -4, -8)
                r.note:SetPoint("LEFT", r.icon, "RIGHT", 6, -8)
                r.note:SetPoint("RIGHT", r.src, "LEFT", -6, 0)
                r.text:SetText(ln.left)
                r.price:SetText(ln.right or "")
                r.note:SetShown(two); r.src:SetShown(two)
                r.note:SetText(ln.note or "")
                r.src:SetText(ln.src or "")
            end
        end
        local total, parts = ns.FeedTotal(shown)
        panel.foot:SetShown(parts >= 2)
        if parts >= 2 then
            panel.foot.value:SetText(S.MoneyText(total))
            y = y + S_FOOT
        end
        panel.back:SetShown(ns.db.feedBare ~= true)
        panel:SetSize(ns.FeedWidth(), y + S_PAD)
    end
    return box
end

---- Refresh ------------------------------------------------------------------------

function ns.Refresh()
    if not frame or not frame:IsShown() then return end
    for q, t in pairs(qtabs) do t:Select(indexOf(ns.RULES, ns.db.quality[q] or "ask"), true) end
    for class, t in pairs(ttabs) do t:Select(indexOf(ns.RULES, ns.db.types[class] or "ask"), true) end
    local filter = search and search:GetText()
    local items = ns.ItemGroups(filter)
    local many = #ns.Items() > 10 or (filter or "") ~= ""
    search:SetShown(many)
    itemList:ClearAllPoints()
    itemList:SetPoint("TOPLEFT", 0, many and -ITEMS_TOP - 36 or -ITEMS_TOP)
    itemList:SetPoint("BOTTOMRIGHT", -10, 0)
    itemList:SetData(items)
    itemEmpty:SetShown(#items == 0)
    logList:SetData(ns.db.log)
    logEmpty:SetShown(#ns.db.log == 0)
    if sampleBox then sampleBox:Refresh() end
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

local function segRow(get, set)
    local holder = CreateFrame("Frame", nil, frame.body)
    holder:SetSize(#ns.RULES * COL_W + 4, 30)
    local t = rollTabs(holder, ns.RULES, function(sel) set(ns.RULES[sel]) end, nil, COL_W)
    t:Select(indexOf(ns.RULES, get()), true)
    return holder, t
end

-- The words over the roll columns, so nobody has to guess what a roll picture means.
local function colHead()
    local holder = CreateFrame("Frame", nil, frame.body)
    holder:SetSize(#ns.RULES * COL_W + 4, 30)
    for i, v in ipairs(ns.RULES) do
        local t = S.Text(holder, 12, S.MUTED)
        t:SetPoint("LEFT", 2 + (i - 1) * COL_W, 0)
        t:SetWidth(COL_W)
        t:SetJustifyH("CENTER")
        t:SetText(L["COL_" .. v:upper()])
    end
    return holder
end

local function blank()
    local f = CreateFrame("Frame", nil, frame.body)
    f:SetSize(1, 30)
    return f
end

local function switch(key, label, desc)
    return { label, desc, function() return ns.db[key] end, function(v) ns.SetPref(key, v) end, icon = ns.OPT_ICON[key] }
end

local function stepper(page, key, label, desc, get, step, min, max, fmt)
    return { label, desc, icon = ns.OPT_ICON[key],
             control = S.Stepper(page, get, function(v) ns.SetPref(key, v) end, step, min, max, fmt, 110) }
end

local function buildRolls(page, width)
    local st = S.Stack(page)
    local main, mh = S.SettingsCard(page, nil, { switch("on", L.OPT_ON, L.OPT_ON_D) })
    st:Add(main, mh)

    local rows = { { "", nil, control = colHead() } }
    for _, q in ipairs(ns.QUALITIES) do
        local holder, t = segRow(function() return ns.db.quality[q] or "ask" end, function(v) ns.db.quality[q] = v end)
        qtabs[q] = t
        rows[#rows + 1] = { QUALITY_COLOR[q] .. L["Q" .. q] .. "|r", nil, control = holder }
    end
    rows[#rows + 1] = { S.Hex(S.GOLD_DIM) .. S.Upper(L.SEC_TYPES) .. "|r", nil, control = blank() }
    for _, t in ipairs(ns.TYPES) do
        local holder, tabs = segRow(function() return ns.db.types[t.class] or "ask" end, function(v) ns.SetType(t.class, v) end)
        ttabs[t.class] = tabs
        rows[#rows + 1] = { L["TYPE_" .. t.key], nil, control = holder }
    end
    local rc, rh = S.SettingsCard(page, L.SEC_ROLLS, rows)
    st:Add(rc, rh)
    local note, nh = S.Paragraph(page, L.NOTE_ROLLS, width)
    st:Add(note, nh)

    local wc, wh = S.SettingsCard(page, L.SEC_ROLLWIN, {
        switch("rollers", L.OPT_ROLLERS, L.OPT_ROLLERS_D),
        stepper(page, "rollScale", L.OPT_ROLL_SCALE, L.OPT_ROLL_SCALE_D, function() return ns.db.rollScale or 100 end,
            10, 70, 150, function(v) return L.PCT:format(v) end),
    })
    st:Add(wc, wh)
    return st:Height()
end

local function buildPickup(page, width)
    local st = S.Stack(page)
    local pc, ph = S.SettingsCard(page, L.SEC_PICKUP, {
        switch("fastLoot", L.OPT_FAST, L.OPT_FAST_D),
        switch("window", L.OPT_WINDOW, L.OPT_WINDOW_D),
        switch("soloConfirm", L.OPT_SOLO, L.OPT_SOLO_D),
    })
    st:Add(pc, ph)

    -- the feed's card: its example on top, then the settings that change it
    local fc = S.Card(page, L.SEC_FEED)
    local fs = S.Stack(fc.body, 0)
    sampleBox = buildSample(fc.body)
    fs:Add(sampleBox, SAMPLE_H, 6)
    local rows = {
        switch("feedCompact", L.OPT_FEED_COMPACT, L.OPT_FEED_COMPACT_D),
        switch("feedBare", L.OPT_FEED_BARE, L.OPT_FEED_BARE_D),
        stepper(page, "feedRows", L.OPT_FEED_ROWS, L.OPT_FEED_ROWS_D, function() return ns.FeedRows() end,
            1, 1, ns.FEED_ROWS_MAX),
        stepper(page, "feedWidth", L.OPT_FEED_WIDTH, L.OPT_FEED_WIDTH_D, function() return ns.FeedWidth() end,
            ns.FEED_WIDTH_STEP, ns.FEED_WIDTH_MIN, ns.FEED_WIDTH_MAX),
    }
    S.rowWidth = S.GuessWidth(page) - 2 * S.INSET
    for n, r in ipairs(rows) do
        local row = r.control and S.SettingRow(fc.body, r[1], r[2], r.control, nil, r.icon)
            or S.SwitchRow(fc.body, r[1], r[2], r[3], r[4], nil, r.icon)
        fs:Add(row, row.height)
        row.line:SetShown(n < #rows)
    end
    S.rowWidth = nil
    st:Add(fc, fc:Fit(fs:Height() - 6))
    local note, nh = S.Paragraph(page, L.NOTE_FEED, width)
    st:Add(note, nh)
    return st:Height()
end

local function buildItems(page)
    local drop = S.DropZone(page, L.DROP, dropItem, 36)
    drop:SetPoint("TOPLEFT")
    drop:SetPoint("TOPRIGHT")
    local hint = S.Note(page, 12)
    hint:SetPoint("TOPLEFT", drop, "BOTTOMLEFT", 0, -6)
    hint:SetPoint("TOPRIGHT", drop, "BOTTOMRIGHT", 0, -6)
    hint:SetJustifyH("CENTER")
    hint:SetWordWrap(false)
    hint:SetText(L.ITEMS_HINT)
    search = S.Edit(page, 200, 28)
    search:SetPoint("TOPLEFT", 0, -ITEMS_TOP)
    search:SetPoint("TOPRIGHT", 0, -ITEMS_TOP)
    S.Placeholder(search, L.SEARCH)
    search:SetScript("OnTextChanged", function() ns.Refresh() end)
    itemList = S.List(page, 34, makeItemRow, fillItemRow)
    itemList:SetPoint("TOPLEFT", 0, -ITEMS_TOP)
    itemList:SetPoint("BOTTOMRIGHT", -10, 0)
    itemEmpty = S.Empty(itemList)
    itemEmpty:Set(L.NO_ITEMS)
end

local function buildRecent(page)
    logList = S.List(page, 40, makeLogRow, fillLogRow)
    logList.heightOf = function(e) return e.winner and 56 or 40 end
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
    pageTabs = S.PageTabs(holder, { L.PAGE_ROLLS, L.PAGE_PICKUP, L.PAGE_ITEMS, L.PAGE_RECENT }, nil, function(i)
        for j, p in ipairs(pages) do p:SetShown(j == i) end
        ns.Refresh()
    end, nil, { "Interface\\Icons\\INV_Misc_Dice_01", S.TAB.items, S.TAB.list, S.TAB.recent })
    local builders = { buildRolls, buildPickup }
    for i = 1, 4 do
        local p = builders[i] and S.Scroll(body) or CreateFrame("Frame", nil, body)
        p:SetPoint("TOPLEFT", 0, -38)
        p:SetPoint("BOTTOMRIGHT", builders[i] and -12 or 0, 0)
        pages[i] = p
        if builders[i] then
            p.child:SetWidth(width - 12)
            local h = builders[i](p.child, width - 12)
            p.child:SetHeight(h)
            p:Update(h)
        end
        if i > 1 then p:Hide() end
    end
    buildItems(pages[3])
    buildRecent(pages[4])
    frame:HookScript("OnShow", function() ns.Refresh() end)
end

-- Opens a page by its number (1 Rolls, 2 Pickup, 3 Items, 4 History).
function ns.ShowPage(i)
    ns.Window()
    pageTabs:Select(i)
end

function ns.Toggle()
    S.ToggleWindow(ns.Window())
end

-- The window, for the hub (/gulli) to show inside it.
function ns.Window()
    if not frame then build() end
    return frame
end
