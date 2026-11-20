-- The window: the session counters, the pause, the main switches; the rules; the ignore list.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, tabs, pages, stats, pauseRow, keyTabs, ignoreList, ignoreEmpty, footer, undo, ignoreNpc, ignoreQuest
local current = 1
local H = S.DOCK_H

local function row(key, label, desc)
    return { label, desc, function() return ns.db[key] end, function(v) ns.db[key] = v; ns.Refresh() end,
             icon = ns.OPT_ICON[key] }
end

local function pausedText()
    local why = ns.Paused()
    if why == "timer" then
        return L.PAUSED_FOR:format(math.max(1, math.ceil((ns.db.pauseUntil - time()) / 60))), S.WARN
    elseif why then
        return L.PAUSED, S.WARN
    end
    return L.RUNNING, S.GOOD
end

function ns.Refresh()
    if not frame or not frame:IsShown() then return end
    local s = ns.db.session
    stats.tiles[1]:Set(tostring(s.taken or 0))
    stats.tiles[2]:Set(tostring(s.done or 0))
    stats.tiles[3]:Set(tostring(s.clicks or 0))
    pauseRow:SetChecked(ns.db.paused)
    for i, k in ipairs(ns.KEYS) do if k == ns.db.pauseKey then keyTabs:Select(i, true) end end
    for i, p in ipairs(pages) do p:SetShown(i == current) end
    local text, color = pausedText()
    footer:SetStatus(text, color)
    undo:SetShown(current == 1)
    undo:SetEnabled(ns.last.accepted ~= nil)
    if current == 3 then
        local items = ns.Ignored()
        ignoreList:SetData(items)
        ignoreEmpty:SetShown(#items == 0)
        ignoreNpc:SetEnabled(ns.last.npc ~= nil and not ns.db.ignoreNpc[ns.last.npc])
        ignoreQuest:SetEnabled(ns.last.quest ~= nil and not ns.db.ignoreQuest[ns.last.quest])
        ignoreNpc:SetText(ns.last.npcName and L.IGNORE_NPC_N:format(ns.last.npcName) or L.IGNORE_NPC)
    end
end

local function mainPage(body)
    local p = CreateFrame("Frame", nil, body)
    local st = S.Stack(p)
    stats = S.StatRow(p, { L.ST_TAKEN, L.ST_DONE, L.ST_CLICKS }, 62,
        { "Interface\\Icons\\INV_Scroll_03", "Interface\\Icons\\INV_Misc_Bag_10", "Interface\\Icons\\INV_Misc_PocketWatch_01" })
    st:Add(stats, 62)
    stats:Layout(frame.inner[1])

    local five = S.FitButton(p, L.PAUSE_5, 28, 70)
    five:SetScript("OnClick", function() ns.PauseFor(ns.PAUSE_MINUTES) end)
    keyTabs = S.Tabs(p, { L.KEY_SHIFT, L.KEY_CTRL, L.KEY_ALT, L.KEY_NONE }, 60, function(i)
        ns.db.pauseKey = ns.KEYS[i]; ns.Refresh()
    end, 28)
    local card, h = S.SettingsCard(p, nil, {
        { L.OPT_PAUSED, L.OPT_PAUSED_D, function() return ns.db.paused end, function(v) ns.SetPaused(v) end,
          icon = ns.OPT_ICON.paused, extra = five },
        { L.PAUSE_KEY, nil, control = keyTabs.frame, icon = "Interface\\Icons\\INV_Misc_Key_04" },
    })
    pauseRow = card.rows[1]
    st:Add(card, h)
    local main, mh = S.SettingsCard(p, nil, {
        row("accept", L.OPT_ACCEPT), row("turnIn", L.OPT_TURNIN), row("skipTrivial", L.OPT_TRIVIAL),
        row("shared", L.OPT_SHARED, L.OPT_SHARED_D),
    })
    st:Add(main, mh)
    return p
end

local function rulesPage(body)
    local page = S.ScrollPage(body, frame.inner[1])
    local p = page.inner
    local st = S.Stack(p)
    local mobs, mh = S.SettingsCard(p, nil, {
        { L.TARGET_KEY, L.TARGET_KEY_D, control = ns.KeyButton(p), icon = ns.OPT_ICON.targetKey },
    })
    st:Add(mobs, mh)
    local free = S.Stepper(p, function() return ns.db.minFree end, function(v) ns.db.minFree = v end, 1, 0, 10,
        function(v) return v == 0 and L.OFF or tostring(v) end)
    local card, h = S.SettingsCard(p, nil, {
        row("itemQuests", L.OPT_ITEMS, L.OPT_ITEMS_D),
        row("skipElite", L.OPT_ELITE), row("skipDungeon", L.OPT_DUNGEON), row("skipGroup", L.OPT_GROUP),
        { L.OPT_FREE, L.OPT_FREE_D, control = free, icon = ns.OPT_ICON.minFree },
        row("pickBest", L.OPT_BEST, L.OPT_BEST_D),
        row("gossip", L.OPT_GOSSIP, L.OPT_GOSSIP_D),
        row("chat", L.OPT_CHAT),
    })
    st:Add(card, h)
    local tip, th = S.Paragraph(p, L.NOTE, frame.inner[1] - 10)
    st:Add(tip, th)
    page:SetContent(st:Height())
    return page
end

local function makeIgnored(r)
    r.icon = S.IconBox(r, 26)
    r.icon:SetPoint("LEFT", 6, 0)
    r.remove = S.FitButton(r, L.REMOVE, 28, 80)
    r.remove:SetPoint("RIGHT")
    r.remove:SetScript("OnClick", function(self) local it = self:GetParent().item; ns.Unignore(it.kind, it.id) end)
    r.name = S.Text(r, 12)
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 10, 0)
    r.name:SetPoint("RIGHT", r.remove, "LEFT", -8, 0)
    r.name:SetWordWrap(false)
end

local function fillIgnored(r, item)
    r.item = item
    r.icon:SetIcon(item.kind == "npc" and "Interface\\Icons\\INV_Misc_Head_Human_01" or "Interface\\Icons\\INV_Scroll_03")
    r.name:SetText(tostring(item.name) .. "  " .. S.Hex(S.FAINT) .. (item.kind == "npc" and L.NPC or L.QUEST) .. "|r")
end

local function ignoredPage(body)
    local p = CreateFrame("Frame", nil, body)
    ignoreNpc = S.Button(p, (frame.inner[1] - S.GAP) / 2, 30)
    ignoreNpc:SetPoint("TOPLEFT")
    ignoreNpc:SetScript("OnClick", function() ns.IgnoreNpc(ns.last.npc, ns.last.npcName) end)
    ignoreQuest = S.Button(p, (frame.inner[1] - S.GAP) / 2, 30)
    ignoreQuest:SetPoint("TOPRIGHT")
    ignoreQuest:SetText(L.IGNORE_QUEST)
    ignoreQuest:SetScript("OnClick", function() ns.IgnoreQuest(ns.last.quest, ns.last.questTitle) end)
    local card = S.Card(p)
    card:SetPoint("TOPLEFT", 0, -30 - S.GAP)
    card:SetPoint("BOTTOMRIGHT")
    ignoreList = S.List(card.body, 40, makeIgnored, fillIgnored)
    ignoreList:SetAllPoints()
    ignoreEmpty = S.Empty(card.body)
    ignoreEmpty:Set(L.NONE_IGNORED, L.NONE_IGNORED_D)
    return p
end

local function build()
    frame = S.Window("GulliAutoQuestFrame", L.TITLE, S.NARROW_W, H)
    local body = frame.body
    footer = S.Footer(frame)
    undo = S.FitButton(frame, L.UNDO, 32, 120)
    S.Danger(undo)
    footer:Add(undo)
    undo:SetScript("OnClick", function() ns.Undo() end)
    tabs = S.PageTabs(body, { L.TAB_MAIN, L.TAB_RULES, L.TAB_IGNORED }, nil, function(i) current = i; ns.Refresh() end, nil, { S.TAB.quests, S.TAB.rules, "Interface\\Icons\\Spell_ChargeNegative" })
    pages = { mainPage(body), rulesPage(body), ignoredPage(body) }
    for _, p in ipairs(pages) do
        p:SetPoint("TOPLEFT", 0, -30 - S.GAP)
        p:SetPoint("BOTTOMRIGHT")
    end
    frame:SetScript("OnShow", function() tabs:Select(current) end)
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(30, function() ns.Refresh() end) end
end

-- Opens one tab (1 main, 2 rules, 3 ignored).
function ns.ShowTab(i)
    local f = ns.Window()
    if not f:IsShown() then ns.Toggle() end
    tabs:Select(i)
end

function ns.Toggle()
    S.ToggleWindow(ns.Window())
end

-- The window, for the hub (/gulli) to show inside it.
function ns.Window()
    if not frame then build() end
    return frame
end

-- Quest mob key ------------------------------------------------------------------------------

local BUTTON = "GulliAutoQuestTarget"
local SIZE = 44
local target, holder, keyOwner, waiting, moving

-- The key and the screen button work while either is set.
local function active()
    return ns.db and (ns.db.targetKey or ns.db.targetButton) and not ns.paused
end

local function savePoint()
    local p, _, rel, x, y = holder:GetPoint()
    ns.db.buttonPoint = { p, x, y, rel }
end

local function tip(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(L.TARGET_BTN)
    local names = ns.QuestMobs()
    for i = #names, math.max(1, #names - 9), -1 do GameTooltip:AddLine(names[i], 1, 1, 1) end
    if #names == 0 then GameTooltip:AddLine(L.TARGET_NONE, 0.6, 0.6, 0.6) end
    GameTooltip:AddLine(L.TARGET_TIP, 0.55, 0.55, 0.58, true)
    GameTooltip:Show()
end

-- One secure button: the key clicks it, and on the screen it is the quest mob button.
local function targetButton()
    if target then return target end
    holder = CreateFrame("Frame", BUTTON .. "Frame", UIParent)
    holder:SetSize(SIZE, SIZE)
    local p = ns.db and ns.db.buttonPoint or { "CENTER", 0, -120 }
    holder:SetPoint(p[1], UIParent, p[4] or p[1], p[2], p[3])
    holder:Hide()
    S.Mover(holder, { label = L.TARGET_BTN,
        save = function() savePoint() end,
        reset = function()
            if InCombatLockdown() then return end
            ns.db.buttonPoint = nil
            holder:ClearAllPoints()
            holder:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
        end })
    target = CreateFrame("Button", BUTTON, holder, "SecureActionButtonTemplate")
    S.HudIcon(target, SIZE)
    target:SetPoint("CENTER")
    target:SetIcon(ns.OPT_ICON.targetKey)
    target:RegisterForClicks("AnyUp", "AnyDown")
    target:SetAttribute("type", "macro")
    target:SetScript("OnEnter", tip)
    target:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return target
end

local function set(b, k, v)
    if b:GetAttribute(k) ~= v then b:SetAttribute(k, v) end
end

-- Aims the button; secure attributes change only out of combat. Out of a fight it targets the
-- next living quest mob on the nameplates, of every kind the log asks for, so each press cycles
-- and a corpse is never taken. In a fight (and without nameplates) the names macro stands,
-- which drops a dead target.
function ns.UpdateTargetMacro(fight)
    if not ns.db or not (ns.db.targetKey or ns.db.targetButton) then return end
    if InCombatLockdown() then waiting = true; return end
    waiting = nil
    local b = targetButton()
    local names = ns.QuestMobs()
    local cur = UnitGUID("target")
    if not cur or (issecretvalue and issecretvalue(cur)) then cur = nil end
    local live = fight and {} or ns.LiveQuestMobs(names)
    local mob = ns.PickNext(live, cur)
    if mob then
        set(b, "type", "target")
        set(b, "unit", mob.unit)
    else
        set(b, "type", "macro")
        set(b, "macrotext", ns.TargetMacro(names))
    end
    -- The screen button: shown while it is on and a quest needs a mob, or in the Unlock mode.
    b:SetCount(#live > 0 and tostring(#live) or "")
    b:SetKey(ns.db.targetKey)
    b:SetDone(#names == 0)
    local show = moving or (ns.db.targetButton and not ns.paused and #names > 0)
    if holder:IsShown() ~= (show and true or false) then holder:SetShown(show and true or false) end
    holder:SetMoving(moving and true or false)
end

-- The hub's Unlock mode; the button is secure, so nothing changes in a fight.
function ns.MoveTarget(on)
    moving = on and true or false
    if InCombatLockdown() or not ns.db then return end
    targetButton()
    if ns.db.targetKey or ns.db.targetButton then ns.UpdateTargetMacro()
    else holder:SetShown(moving); holder:SetMoving(moving) end
end

-- The frame for the hub's Unlock panel.
function ns.TargetFrame()
    if not target and InCombatLockdown() then return nil end
    targetButton()
    return holder
end

-- The show switch of the screen button (the hub's Unlock panel).
function ns.SetTargetButton(on)
    ns.db.targetButton = on and true or nil
    if InCombatLockdown() then waiting = true; return end
    targetButton()
    if on then ns.UpdateTargetMacro() elseif not moving then holder:Hide() end
end

-- Binds the key to the button, or frees it (no key, or paused from the hub).
function ns.ApplyTargetKey()
    if InCombatLockdown() then waiting = true; return end
    keyOwner = keyOwner or CreateFrame("Frame")
    ClearOverrideBindings(keyOwner)
    local key = ns.db and ns.db.targetKey
    if active() or moving then
        targetButton()
        ns.UpdateTargetMacro()
    elseif holder and not moving then
        holder:Hide()
    end
    if key and not ns.paused then S.BindKey(keyOwner, true, key, BUTTON, "LeftButton") end
end

local MODIFIER = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true }
local MOUSE = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }

local function mods()
    return (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "") .. (IsShiftKeyDown() and "SHIFT-" or "")
end

local function keyText()
    local key = ns.db and ns.db.targetKey
    return key and (GetBindingText and GetBindingText(key) or key) or L.KEY_NONE
end

local function capture(b, on)
    b.capturing = on
    b:EnableKeyboard(on)
    if b.SetPropagateKeyboardInput and not InCombatLockdown() then b:SetPropagateKeyboardInput(not on) end
    b:SetText(on and L.KEY_PRESS or keyText())
end

function ns.SetTargetKey(key)
    ns.db.targetKey = S.KeyBase(key)
    ns.ApplyTargetKey()
end

-- The key button of the window: a click waits for a key or a mouse button, a right-click clears it.
function ns.KeyButton(parent)
    local b = S.Button(parent, 150, 28)
    b:RegisterForClicks("AnyUp")
    b:SetScript("OnClick", function(self, mouse)
        if self.capturing and MOUSE[mouse] then
            ns.SetTargetKey(mods() .. MOUSE[mouse])
            capture(self, false)
        elseif mouse == "RightButton" then
            ns.SetTargetKey(nil)
            capture(self, false)
        elseif mouse == "LeftButton" then
            capture(self, not self.capturing)
        end
    end)
    b:SetScript("OnKeyDown", function(self, key)
        if not self.capturing or MODIFIER[key] then return end
        if key ~= "ESCAPE" then ns.SetTargetKey(mods() .. key) end
        capture(self, false)
    end)
    b:SetScript("OnShow", function(self) capture(self, false) end)
    capture(b, false)
    return b
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "QUEST_LOG_UPDATE",
                     "ZONE_CHANGED_NEW_AREA", "PLAYER_TARGET_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }) do
    ev:RegisterEvent(e)
end
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" and waiting and ns.db then return ns.ApplyTargetKey() end
    if not ns.db or not (ns.db.targetKey or ns.db.targetButton) then return end
    if event == "PLAYER_LOGIN" then
        ns.ApplyTargetKey()
    elseif not ns.paused then
        -- PLAYER_REGEN_DISABLED comes just before the lockdown: the last chance to set the macro.
        ns.UpdateTargetMacro(event == "PLAYER_REGEN_DISABLED")
    end
end)

-- A mob that another player tags or that dies off a nameplate event: look again each second.
C_Timer.NewTicker(1, function()
    if active() and not InCombatLockdown() then ns.UpdateTargetMacro() end
end)
