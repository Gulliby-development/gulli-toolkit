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
local ROW_W, ROW_H = 190, 28
ns.LIST_MAX = 5 -- rows of the mob list under the button
local target, holder, keyOwner, waiting, moving
local rows = {}
ns.cycle = 1 -- the name the button's next press tries first

-- The key and the screen button work while either is set.
local function active()
    return ns.db and (ns.db.targetKey or ns.db.targetButton) and not ns.paused
end

local function savePoint()
    local p, _, rel, x, y = holder:GetPoint()
    ns.db.buttonPoint = { p, x, y, rel }
end

ns.TIP_MOBS = 3

local function tip(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(L.TARGET_BTN)
    local names = ns.QuestMobs()
    for i = 1, math.min(#names, ns.TIP_MOBS) do GameTooltip:AddLine(names[i], 1, 1, 1) end
    if #names > ns.TIP_MOBS then GameTooltip:AddLine(L.TARGET_MORE:format(#names - ns.TIP_MOBS), 0.6, 0.6, 0.6) end
    if #names == 0 then GameTooltip:AddLine(L.TARGET_NONE, 0.6, 0.6, 0.6) end
    GameTooltip:AddLine(L.TARGET_TIP, 0.55, 0.55, 0.58, true)
    GameTooltip:Show()
end

local function set(b, k, v)
    if b:GetAttribute(k) ~= v then b:SetAttribute(k, v) end
end

-- A press on a living mob of one of the button's names goes on to the next mob of that name: the
-- macro loses its clear for that one press (ns.TargetMacro's keep), and PostClick puts it back.
-- The action runs on the release (useOnKeyDown false), so the press half does nothing here.
-- A press of the big button that found no living target first moves the next name to the front.
local function wire(b, main)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("useOnKeyDown", false)
    b:SetAttribute("type", "macro")
    b:HookScript("PreClick", function(self, _, down)
        if down or InCombatLockdown() or not self.names then return end
        local i = ns.CycleIndex(self.names)
        self.kept = i ~= nil
        if i then set(self, "macrotext", ns.TargetMacro(self.names, i, true)) end
    end)
    b:HookScript("PostClick", function(self, _, down)
        if down then return end
        if self.flash then
            self.flash:Show()
            C_Timer.After(0.15, function() self.flash:Hide() end)
        end
        if InCombatLockdown() or not self.names then return end
        if main and not self.kept and #self.names > 1 then ns.cycle = ns.cycle % #self.names + 1 end
        self.kept = nil
        set(self, "macrotext", ns.TargetMacro(self.names, main and ns.cycle or 1))
    end)
end

-- A light on each use (the key's too), and the icon darkens while the mouse holds it.
local function flash(b, icon)
    b.flash = b:CreateTexture(nil, "OVERLAY")
    b.flash:SetAllPoints(icon or b)
    b.flash:SetColorTexture(1, 0.9, 0.6, 0.35)
    S.RoundMask(b, b.flash, S.ROUND_SQ)
    b.flash:Hide()
end

local function rowTip(self)
    if not GameTooltip or not self.mob then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.mob)
    GameTooltip:AddLine(L.TARGET_ROW, 0.55, 0.55, 0.58, true)
    GameTooltip:Show()
end

-- One row of the list: the mob's face once it was seen (else the button's icon), its name and
-- how many of it the quest has; a click targets that one, the next click the next of it.
local function row(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Button", BUTTON .. "Row" .. i, holder, "SecureActionButtonTemplate")
    r:SetSize(ROW_W, ROW_H)
    r:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", 0, -4 - (i - 1) * (ROW_H + 2))
    S.Box(r, S.HUD_GLASS, S.GLASS_EDGE, S.R_MD)
    r.face = S.IconBox(r, ROW_H - 6)
    r.face:SetPoint("LEFT", 3, 0)
    r.count = S.Text(r, 12, S.MUTED)
    r.count:SetPoint("RIGHT", -8, 0)
    r.label = S.Text(r, 12, S.TEXT)
    r.label:SetPoint("LEFT", r.face, "RIGHT", 6, 0)
    r.label:SetPoint("RIGHT", r.count, "LEFT", -6, 0)
    r.label:SetJustifyH("LEFT")
    r.label:SetWordWrap(false)
    flash(r)
    wire(r, false)
    r:HookScript("OnMouseDown", function(self) self.face.tex:SetVertexColor(0.6, 0.6, 0.6, 1) end)
    r:HookScript("OnMouseUp", function(self) self.face.tex:SetVertexColor(1, 1, 1, 1) end)
    r:SetScript("OnEnter", rowTip)
    r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    rows[i] = r
    return r
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
    flash(target)
    wire(target, true)
    target:HookScript("OnMouseDown", function(self) self.icon:SetVertexColor(0.6, 0.6, 0.6, 1) end)
    target:HookScript("OnMouseUp", function(self) self:SetDone(rawget(self, "doneNow")) end)
    target:SetScript("OnEnter", tip)
    target:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return target
end

-- The texts of the rows; in a fight too, since they are only texts. A mob done in a fight keeps
-- its row (the rows are secure) and dims.
local function paintRows(list)
    local by = {}
    for _, m in ipairs(list) do by[m.name] = m end
    for _, r in ipairs(rows) do
        local m = r.mob and by[r.mob]
        r.label:SetText(r.mob or "")
        if m then
            r.count:SetText(m.need > 0 and (S.Emph(tostring(m.have)) .. "/" .. m.need) or "")
            r:SetAlpha(1)
        else
            r.count:SetText("")
            r:SetAlpha(0.45)
        end
    end
end

-- The mob's face on its row, once the game shows that mob (target, mouseover, a nameplate).
function ns.SeeMob(unit)
    if not unit or not SetPortraitTexture then return end
    local ok, name = pcall(UnitName, unit)
    if not ok or name == nil or (issecretvalue and issecretvalue(name)) then return end
    for _, r in ipairs(rows) do
        if r.mob == name and r.faceOf ~= name then
            SetPortraitTexture(r.face.tex, unit)
            r.faceOf = name
        end
    end
end

-- Aims the buttons; secure attributes change only out of combat (the macros of a fight are the
-- ones set just before it). The big button tries every name from ns.cycle on, a row its own.
function ns.UpdateTargetMacro()
    if not ns.db or not (ns.db.targetKey or ns.db.targetButton) then return end
    local list = ns.QuestMobList()
    if InCombatLockdown() then
        waiting = true
        paintRows(list)
        return
    end
    waiting = nil
    local b = targetButton()
    local names = {}
    for i, m in ipairs(list) do names[i] = m.name end
    if ns.cycle > #names then ns.cycle = 1 end
    b.names = names
    set(b, "macrotext", ns.TargetMacro(names, ns.cycle))
    b:SetCount(#names > 1 and tostring(#names) or "")
    b:SetKey(ns.db.targetKey)
    rawset(b, "doneNow", #names == 0)
    b:SetDone(#names == 0)
    -- The list: one row per name while the button shows.
    for i = 1, math.max(#rows, math.min(#names, ns.LIST_MAX)) do
        local name = i <= ns.LIST_MAX and names[i] or nil
        local r = (name or rows[i]) and row(i)
        if r then
            if r.mob ~= name then
                r.faceOf = nil
                r.face:SetIcon(ns.OPT_ICON.targetKey)
            end
            r.mob = name
            r.names = name and { name } or nil
            set(r, "macrotext", name and ns.TargetMacro(r.names) or nil)
            r:SetShown(name ~= nil)
        end
    end
    paintRows(list)
    -- The screen button: shown while it is on and a quest needs a mob, or in the Unlock mode.
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
                     "ZONE_CHANGED_NEW_AREA", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED" }) do
    ev:RegisterEvent(e)
end
local SEE = { PLAYER_TARGET_CHANGED = "target", UPDATE_MOUSEOVER_UNIT = "mouseover" }
ev:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_REGEN_ENABLED" and waiting and ns.db then return ns.ApplyTargetKey() end
    if not ns.db or not (ns.db.targetKey or ns.db.targetButton) then return end
    if event == "PLAYER_LOGIN" then
        ns.ApplyTargetKey()
    elseif SEE[event] or event == "NAME_PLATE_UNIT_ADDED" then
        if not ns.paused then ns.SeeMob(SEE[event] or unit) end
    elseif not ns.paused then
        -- PLAYER_REGEN_DISABLED comes just before the lockdown: the last chance to set the macros.
        ns.UpdateTargetMacro()
    end
end)
