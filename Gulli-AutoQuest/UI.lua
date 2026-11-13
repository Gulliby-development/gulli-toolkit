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
    local p = CreateFrame("Frame", nil, body)
    local st = S.Stack(p)
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
    local tip, th = S.Paragraph(p, L.NOTE, frame.inner[1])
    st:Add(tip, th)
    return p
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
    tabs = S.Tabs(body, { L.TAB_MAIN, L.TAB_RULES, L.TAB_IGNORED }, nil, function(i) current = i; ns.Refresh() end, nil, { S.TAB.quests, S.TAB.rules, "Interface\\Icons\\Spell_ChargeNegative" })
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
