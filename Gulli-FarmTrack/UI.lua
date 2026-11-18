-- The panel on the screen (a Gulli HUD panel with a row per target: icon, name, how much this
-- session, the goal bar, the rate and the time to the goal) and the window: three tiles, the
-- targets with their goals, what was looted this session, and the settings.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local panel, frame, tabs, tiles, targetCard, lootList, lootEmpty, targetEmpty
local pages, targetRows, steppers = {}, {}, {}
local PANEL_W, HEAD_H, ROW_H = 230, 26, 46
ns.PANEL_POINT = { "RIGHT", "RIGHT", -40, 120 }

local function amount(kind, n, colored)
    if kind == "gold" then return colored and S.MoneyText(n, true) or ns.Money(n) end
    return ns.Short(n)
end

-- "37 / 100" or "+37".
function ns.ValueText(i, colored)
    if i.goal then return amount(i.kind, i.gained, colored) .. S.Hex(S.FAINT) .. " / " .. amount(i.kind, i.goal) .. "|r" end
    return "+" .. amount(i.kind, i.gained, colored)
end

-- "52/h · goal in 1 h 10 min".
function ns.PaceText(i)
    local parts = { L.PER_HOUR:format(amount(i.kind, i.rate)) }
    if i.done then parts[#parts + 1] = S.Hex(S.GOOD) .. L.DONE .. "|r"
    elseif i.eta then parts[#parts + 1] = L.ETA:format(ns.Span(i.eta)) end
    return table.concat(parts, S.DOT)
end

-- The panel ---------------------------------------------------------------------------------------

function ns.Place()
    if not panel then return end
    local p = ns.db.point or ns.PANEL_POINT
    panel:ClearAllPoints()
    panel:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
end

local function panelRow(i)
    local r = CreateFrame("Frame", nil, panel)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", 6, -HEAD_H - (i - 1) * ROW_H)
    r:SetPoint("TOPRIGHT", -8, -HEAD_H - (i - 1) * ROW_H)
    r.icon = S.IconBox(r, 24)
    r.icon:SetPoint("LEFT", 2, 2)
    r.value = S.Text(r, 12, S.TEXT, "OUTLINE")
    r.value:SetPoint("TOPRIGHT", 0, -3)
    r.value:SetJustifyH("RIGHT")
    r.name = S.Text(r, 12)
    r.name:SetPoint("TOPLEFT", 34, -3)
    r.name:SetPoint("RIGHT", r.value, "LEFT", -6, 0)
    r.name:SetWordWrap(false)
    r.pace = S.Text(r, 12, S.MUTED)
    r.pace:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -2)
    r.pace:SetPoint("RIGHT", 0, 0)
    r.pace:SetWordWrap(false)
    r.bar = S.Progress(r, 3)
    r.bar:SetPoint("BOTTOMLEFT", 34, 2)
    r.bar:SetPoint("BOTTOMRIGHT", 0, 2)
    r.bar:SetWidth(PANEL_W - 54)
    return r
end

local function buildPanel()
    panel = CreateFrame("Button", "GulliFarmTrackPanel", UIParent)
    panel:SetSize(PANEL_W, HEAD_H + ROW_H)
    panel:SetFrameStrata("MEDIUM")
    S.HudPanel(panel)
    panel.ico = panel:CreateTexture(nil, "ARTWORK")
    panel.ico:SetSize(16, 16)
    panel.ico:SetPoint("TOPLEFT", 8, -5)
    panel.ico:SetTexture("Interface\\AddOns\\Gulli-FarmTrack\\icon")
    panel.title = S.Text(panel, 12)
    panel.title:SetPoint("LEFT", panel.ico, "RIGHT", 6, 0)
    panel.title:SetText(L.PANEL_TITLE)
    panel.time = S.Text(panel, 12, S.TIME)
    panel.time:SetPoint("TOPRIGHT", -8, -7)
    panel.time:SetJustifyH("RIGHT")
    local line = S.Divider(panel)
    line:SetPoint("TOPLEFT", 1, -HEAD_H + 2)
    line:SetPoint("TOPRIGHT", -1, -HEAD_H + 2)
    line:SetHeight(1)
    panel.rows = {}
    for i = 1, ns.MAX_TARGETS do panel.rows[i] = panelRow(i) end
    panel.empty = S.Text(panel, 12, S.FAINT)
    panel.empty:SetPoint("TOPLEFT", 10, -HEAD_H - 12)
    panel.empty:SetPoint("RIGHT", -10, 0)
    panel.empty:SetText(L.PANEL_EMPTY)
    S.Mover(panel, { label = L.TITLE, hint = L.TIP_MOVE,
        save = function(p, rp, x, y) ns.db.point = { p, rp, x, y } end,
        reset = function() ns.db.point = nil; ns.Place() end })
    panel:SetScript("OnClick", function() ns.Toggle() end)
    panel:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L.TITLE, 1, 1, 1)
        local m = S.MUTED
        for _, t in ipairs(ns.Targets()) do
            local i = ns.Info(t)
            GameTooltip:AddDoubleLine(i.name, ns.ValueText(i, true), S.TEXT[1], S.TEXT[2], S.TEXT[3], 1, 1, 1)
            GameTooltip:AddLine(ns.PaceText(i), m[1], m[2], m[3])
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L.TIP_CLICK, S.FAINT[1], S.FAINT[2], S.FAINT[3], true)
        GameTooltip:Show()
    end)
    panel:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    local elapsed = 0
    panel:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + (dt or 0)
        if elapsed >= 5 then elapsed = 0; ns.Refresh() end
    end)
    ns.Place()
end

-- The panel shows while there is something to farm, or in the Unlock mode so it can be placed.
function ns.PanelShown()
    if ns.Unlocked() then return true end
    return ns.db.panel and #ns.Targets() > 0
end

local function paintPanel()
    local list = ns.Targets()
    panel.time:SetText(ns.Span(ns.Active()))
    for k, r in ipairs(panel.rows) do
        local t = list[k]
        if t then
            local i = ns.Info(t)
            r.icon:SetIcon(i.icon)
            r.name:SetText(i.name)
            r.value:SetText(ns.ValueText(i, true))
            r.pace:SetText(ns.PaceText(i))
            r.bar:SetShown(i.goal ~= nil)
            if i.goal then r.bar:Set(i.pct, i.done and S.GOOD or nil) end
        end
        r:SetShown(t ~= nil)
    end
    panel.empty:SetShown(#list == 0)
    panel:SetHeight(HEAD_H + math.max(1, #list) * ROW_H + 4)
    panel:SetScale((ns.db.scale or 100) / 100)
    panel:SetAlpha((ns.db.alpha or 100) / 100)
end

-- A goal reached: a Gulli HUD notice.
function ns.OnGoal(i, text)
    if S.Toast then
        S.Toast({ key = "FarmTrack:" .. i.key, icon = i.icon, title = L.DONE, text = text, kind = "good", seconds = 8 })
    end
end

-- The window ------------------------------------------------------------------------------------

local function goalOf(t, edit)
    local n = tonumber(edit:GetText())
    if n and t.kind == "gold" then n = n * 10000 end
    return n
end

local function targetRow(parent, k)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(36)
    r:SetPoint("TOPLEFT", 0, -(k - 1) * 38)
    r:SetPoint("TOPRIGHT", 0, -(k - 1) * 38)
    r.icon = S.IconBox(r, 26)
    r.icon:SetPoint("LEFT", 2, 0)
    r.remove = S.Close(r, function() ns.RemoveTarget(k) end)
    r.remove:SetPoint("RIGHT")
    r.goal = S.Edit(r, 70, 28)
    r.goal:SetPoint("RIGHT", r.remove, "LEFT", -6, 0)
    r.goal:SetNumeric(true)
    r.goal.hint = S.Placeholder(r.goal, L.GOAL)
    local function save(self)
        local t = ns.Targets()[k]
        if t then ns.SetGoal(k, goalOf(t, self)) end
    end
    r.goal:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    r.goal:HookScript("OnEditFocusLost", save)
    r.value = S.Text(r, 13)
    r.value:SetPoint("RIGHT", r.goal, "LEFT", -10, 0)
    r.value:SetJustifyH("RIGHT")
    r.name = S.Text(r, 13)
    r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 10, 0)
    r.name:SetPoint("RIGHT", r.value, "LEFT", -8, 0)
    r.name:SetWordWrap(false)
    r.pace = S.Text(r, 12, S.MUTED)
    r.pace:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
    r.pace:SetPoint("RIGHT", r.value, "LEFT", -8, 0)
    r.pace:SetWordWrap(false)
    return r
end

-- Picks up the item on the cursor as a target.
local function dropItem()
    if not GetCursorInfo then return end
    local kind, id = GetCursorInfo()
    if kind ~= "item" or not id then return end
    if ClearCursor then ClearCursor() end
    if not ns.AddTarget("item", id) then print(L.FULL:format(ns.MAX_TARGETS)) end
end

-- Adds the item typed into the box (an id, a link or a name).
function ns.AddTyped(box)
    local id = ns.ParseItem(box:GetText())
    if not id then print(L.UNKNOWN_ITEM) return false end
    if not ns.AddTarget("item", id) then print(L.FULL:format(ns.MAX_TARGETS)) return false end
    box:SetText("")
    box:ClearFocus()
    return true
end

local function farmPage(body, width)
    local p = CreateFrame("Frame", nil, body)
    local st = S.Stack(p)
    targetCard = S.Card(p, L.SEC_TARGETS)
    for k = 1, ns.MAX_TARGETS do targetRows[k] = targetRow(targetCard.body, k) end
    targetEmpty = S.Note(targetCard.body, 12)
    targetEmpty:SetPoint("TOPLEFT", 0, -4)
    targetEmpty:SetPoint("RIGHT")
    targetEmpty:SetText(L.NO_TARGETS_SUB)
    local add = CreateFrame("Frame", nil, targetCard.body)
    add:SetHeight(36)
    add:SetPoint("BOTTOMLEFT")
    add:SetPoint("BOTTOMRIGHT")
    targetCard.gold = S.FitButton(add, L.ADD_GOLD, 36, 90)
    targetCard.gold:SetPoint("RIGHT")
    S.SetButtonIcon(targetCard.gold, ns.GOLD_ICON)
    targetCard.gold:SetScript("OnClick", function()
        if not ns.AddTarget("gold") then print(L.FULL:format(ns.MAX_TARGETS)) end
    end)
    local drop = S.DropZone(add, L.DROP, dropItem, 36)
    drop:SetPoint("LEFT")
    drop:SetPoint("RIGHT", targetCard.gold, "LEFT", -8, 0)
    local typed = CreateFrame("Frame", nil, targetCard.body)
    typed:SetHeight(32)
    typed:SetPoint("BOTTOMLEFT", add, "TOPLEFT", 0, 8)
    typed:SetPoint("BOTTOMRIGHT", add, "TOPRIGHT", 0, 8)
    local addBtn = S.FitButton(typed, L.ADD, 32, 90)
    addBtn:SetPoint("RIGHT")
    local box = S.Edit(typed, 100, 32)
    box:SetJustifyH("LEFT")
    box:SetPoint("LEFT")
    box:SetPoint("RIGHT", addBtn, "LEFT", -8, 0)
    box.hint = S.Text(box, 12, S.FAINT)
    box.hint:SetPoint("LEFT", 8, 0)
    box.hint:SetPoint("RIGHT", -8, 0)
    box.hint:SetWordWrap(false)
    box.hint:SetText(L.ID_HINT)
    local function hint() box.hint:SetShown(box:GetText() == "" and not box:HasFocus()) end
    box:SetScript("OnTextChanged", hint)
    box:HookScript("OnEditFocusGained", hint)
    box:HookScript("OnEditFocusLost", hint)
    box:SetScript("OnEnterPressed", function(self) ns.AddTyped(self) end)
    addBtn:SetScript("OnClick", function() ns.AddTyped(box) end)
    targetCard.box, targetCard.addBtn = box, addBtn
    -- Shift+click on an item puts its link into the box while it has the focus.
    if hooksecurefunc and ChatEdit_InsertLink then
        hooksecurefunc("ChatEdit_InsertLink", function(link)
            if box:HasFocus() and type(link) == "string" and link:find("item:") then box:SetText(link) end
        end)
    end
    st:Add(targetCard, targetCard:Fit(ns.MAX_TARGETS * 38 + 84))

    local loot = S.Card(p, L.SEC_LOOT)
    loot:SetPoint("TOPLEFT", 0, -st.y)
    loot:SetPoint("BOTTOMRIGHT")
    lootList = S.List(loot.body, 34, function(r)
        r.icon = S.IconBox(r, 24)
        r.icon:SetPoint("LEFT", 2, 0)
        r.track = S.Ghost(S.FitButton(r, L.TRACK, 28, 70))
        r.track:SetPoint("RIGHT", -4, 0)
        r.count = S.Text(r, 13)
        r.count:SetPoint("RIGHT", r.track, "LEFT", -10, 0)
        r.count:SetJustifyH("RIGHT")
        r.name = S.Text(r, 12)
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 10, 0)
        r.name:SetPoint("RIGHT", r.count, "LEFT", -8, 0)
        r.name:SetWordWrap(false)
    end, function(r, it)
        r.icon:SetIcon(it.icon)
        r.name:SetText(it.name)
        r.count:SetText(it.text)
        local on = ns.Tracked(it.kind, it.id)
        r.track:SetEnabled(not on)
        r.track:SetScript("OnClick", function()
            if not ns.AddTarget(it.kind, it.id) then print(L.FULL:format(ns.MAX_TARGETS)) end
        end)
    end)
    lootList:SetAllPoints()
    lootEmpty = S.Empty(loot.body)
    lootEmpty:Set(L.NO_LOOT, L.NO_LOOT_SUB)
    return p
end

local function settingsPage(body, width)
    local page = S.ScrollPage(body, width)
    local p = page.inner
    local st = S.Stack(p)
    local function pct(v) return v .. "%" end
    local alpha = S.Stepper(p, function() return ns.db.alpha end, function(v) ns.SetPref("alpha", v) end, 10, 30, 100, pct)
    local scale = S.Stepper(p, function() return ns.db.scale end, function(v) ns.SetPref("scale", v) end, 10, 60, 200, pct)
    steppers = { alpha, scale }
    local place = S.FitButton(p, L.PLACE_RESET, 28, 100)
    place:SetScript("OnClick", function() ns.db.point = nil; ns.Place() end)
    local card, h = S.SettingsCard(p, L.SEC_PANEL, {
        { L.OPT_ALPHA, nil, control = alpha, icon = "Interface\\Icons\\Spell_Magic_LesserInvisibilty" },
        { L.OPT_SCALE, nil, control = scale, icon = "Interface\\Icons\\INV_Misc_Spyglass_03" },
        { L.OPT_PLACE, nil, control = place, icon = "Interface\\Icons\\INV_Misc_Map_01" },
    })
    st:Add(card, h)
    local count, ch = S.SettingsCard(p, L.SEC_COUNT, {
        { L.OPT_SALES, L.OPT_SALES_TIP, function() return ns.db.sales end, function(v) ns.SetPref("sales", v) end,
          icon = ns.OPT_ICON.sales },
        { L.OPT_ALERT, L.OPT_ALERT_TIP, function() return ns.db.alert end, function(v) ns.SetPref("alert", v) end,
          icon = ns.OPT_ICON.alert },
    })
    st:Add(count, ch)
    page:SetContent(st:Height())
    return page
end

-- The rows of the loot list: gold first, then the items, the most first.
function ns.LootRows()
    local out = {}
    if ns.s.money > 0 then
        out[1] = { kind = "gold", name = L.GOLD, icon = ns.GOLD_ICON, text = "+" .. S.MoneyText(ns.s.money, true) }
    end
    for _, it in ipairs(ns.Looted()) do
        out[#out + 1] = { kind = "item", id = it.id, name = ns.ItemName(it.id), icon = ns.ItemIcon(it.id),
                          text = "+" .. ns.Short(it.n) }
    end
    return out
end

local function paintWindow()
    local items = 0
    for _, n in pairs(ns.s.items) do items = items + n end
    local t = tiles.tiles
    t[1]:Set(ns.Span(ns.Active()), S.TIME)
    t[2]:Set(S.MoneyText(ns.s.money, true), ns.s.money > 0 and S.TEXT or S.MUTED)
    t[3]:Set(ns.Short(items), items > 0 and S.TEXT or S.MUTED)
    local list = ns.Targets()
    for k, r in ipairs(targetRows) do
        local tg = list[k]
        if tg then
            local i = ns.Info(tg)
            r.icon:SetIcon(i.icon)
            r.name:SetText(i.name)
            r.value:SetText(ns.ValueText(i, true))
            r.pace:SetText(ns.PaceText(i))
            if not r.goal:HasFocus() then
                local g = tg.goal and (tg.kind == "gold" and math.floor(tg.goal / 10000) or tg.goal)
                r.goal:SetText(g and g > 0 and tostring(g) or "")
            end
        end
        r:SetShown(tg ~= nil)
    end
    targetEmpty:SetShown(#list == 0)
    targetCard.gold:SetEnabled(not ns.Tracked("gold") and #list < ns.MAX_TARGETS)
    local rows = ns.LootRows()
    lootList:SetData(rows)
    lootEmpty:SetShown(#rows == 0)
end

function ns.Refresh()
    if not ns.s or not ns.db then return end
    local show = ns.PanelShown()
    if show and not panel then buildPanel() end
    if panel then
        panel:SetShown(show)
        if show then paintPanel() end
        panel:SetMoving(ns.Unlocked() and not (InCombatLockdown and InCombatLockdown()))
    end
    if frame and frame:IsShown() then paintWindow() end
end

local function build()
    frame = S.Window("GulliFarmTrackFrame", L.TITLE, S.NARROW_W, S.DOCK_H)
    local body, width = frame.body, frame.inner[1]
    local ft = S.Footer(frame)
    local new = S.Primary(S.FitButton(frame, L.NEW_SESSION, 30, 120))
    new:SetScript("OnClick", function() ns.Start(); ns.Refresh(); ft:SetStatus(L.NEW_SESSION_DONE) end)
    ft:Add(new)
    ft:SetStatus(L.STATUS)
    local st = S.Stack(body)
    tiles = S.StatRow(body, { L.ST_TIME, L.ST_GOLD, L.ST_ITEMS }, 62,
        { "Interface\\Icons\\INV_Misc_PocketWatch_01", ns.GOLD_ICON, "Interface\\Icons\\INV_Misc_Bag_10" })
    st:Add(tiles, 62)
    tiles:Layout(width)
    tabs = S.PageTabs(body, { L.TAB_FARM, L.TAB_SETTINGS }, nil, function(i)
        for j, p in ipairs(pages) do p:SetShown(j == i) end
        for _, x in ipairs(steppers) do x:Refresh() end
        ns.Refresh()
    end, nil, { S.TAB.list, S.TAB.settings })
    tabs.frame:ClearAllPoints()
    tabs.frame:SetPoint("TOPLEFT", 0, -st.y)
    st:Space(30 + S.GAP)
    pages[1] = farmPage(body, width)
    pages[2] = settingsPage(body, width)
    for i, p in ipairs(pages) do
        p:SetPoint("TOPLEFT", 0, -st.y)
        p:SetPoint("BOTTOMRIGHT")
        p:SetShown(i == 1)
    end
    frame:HookScript("OnShow", function() ns.Refresh() end)
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
function ns.Parts() return panel, frame, tabs, pages end

-- The panel for the hub's Unlock mode, built hidden when it is asked for.
function ns.PanelFrame()
    if not panel and ns.db then buildPanel(); panel:SetShown(ns.PanelShown()) end
    return panel
end
