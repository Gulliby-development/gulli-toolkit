-- Takes and hands in quests without the extra taps. It never picks a reward when there is a
-- choice (unless the player asks for the best vendor price), never pays gold to finish a
-- quest, and pauses with a key, a switch or for five minutes.

local ADDON, ns = ...
local L = ns.L

ns.DEFAULTS = {
    accept = true, turnIn = true, skipTrivial = true,
    shared = false,       -- accept quests a group member shares
    itemQuests = false,   -- hand in quests that take items other than quest items
    skipElite = false, skipDungeon = false, skipGroup = false,
    minFree = 0,          -- keep this many quest log places free (0: off)
    pickBest = false,     -- take the reward with the best vendor price
    gossip = false,       -- pick the only gossip line of an NPC
    chat = false,         -- a chat line for each quest taken or handed in
    paused = false, pauseUntil = 0, pauseKey = "SHIFT",
}
ns.KEYS = { "SHIFT", "CTRL", "ALT", "NONE" }
ns.PAUSE_MINUTES = 5
local TAG_GROUP, TAG_RAID, TAG_DUNGEON, TAG_RAID10, TAG_RAID25 = 1, 62, 81, 88, 89
local QUEST_CLASS = 12

local function say(msg) print("|cff9ad0ffGulli AutoQuest|r: " .. msg) end
local function sellPrice(link)
    if not link then return 0 end
    return select(11, ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(link)) or 0
end
local function itemClass(link)
    local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not f or not link then return nil end
    return select(6, f(link))
end
local function npcID()
    local guid = UnitGUID and UnitGUID("npc")
    return guid and tonumber(guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
end
local function questTag(id)
    if id and C_QuestLog and C_QuestLog.GetQuestTagInfo then
        local info = C_QuestLog.GetQuestTagInfo(id)
        if info then return info.tagID, info.isElite end
    end
end
local function logFree()
    local Q = C_QuestLog or {}
    local _, n = (Q.GetNumQuestLogEntries or GetNumQuestLogEntries)()
    local max = (Q.GetMaxNumQuestsCanAccept and Q.GetMaxNumQuestsCanAccept()) or MAX_QUESTS or 20
    return max - (n or 0)
end
local function keyDown(key)
    if key == "SHIFT" then return IsShiftKeyDown and IsShiftKeyDown() end
    if key == "CTRL" then return IsControlKeyDown and IsControlKeyDown() end
    if key == "ALT" then return IsAltKeyDown and IsAltKeyDown() end
    return false
end

-- Why it waits now: "key", "switch", "timer" or nil.
function ns.Paused()
    local db = ns.db
    if keyDown(db.pauseKey) then return "key" end
    if db.paused then return "switch" end
    if (db.pauseUntil or 0) > time() then return "timer" end
end

function ns.SetPaused(on)
    ns.db.paused = on and true or false
    if not on then ns.db.pauseUntil = 0 end
    if ns.Refresh then ns.Refresh() end
end

function ns.PauseFor(minutes)
    ns.db.pauseUntil = time() + minutes * 60
    if ns.Refresh then ns.Refresh() end
end

-- Counters of this session, kept in the saved variables so a /reload does not lose them.
local function count(key, n)
    local s = ns.db.session
    s[key] = (s[key] or 0) + (n or 1)
    if ns.Refresh then ns.Refresh() end
end

-- One feed line after a quiet moment: "Taken 3, handed in 2".
local batch = { taken = 0, done = 0, waiting = false }
local function feed(kind, title)
    batch[kind] = batch[kind] + 1
    if ns.db.chat and title then say((kind == "taken" and L.TOOK or L.HANDED):format(title)) end
    if batch.waiting then return end
    batch.waiting = true
    C_Timer.After(10, function()
        batch.waiting = false
        if batch.taken + batch.done == 0 then return end
        local text = L.FEED:format(batch.taken, batch.done)
        batch.taken, batch.done = 0, 0
        if GulliToolkit and GulliToolkit.Notify then GulliToolkit.Notify("AutoQuest", text) end
    end)
end

-- Ignore list -------------------------------------------------------------------------------

ns.last = {} -- { npc = id, npcName, quest = id, questTitle, accepted = id, acceptedTitle }

function ns.IgnoreNpc(id, name)
    if not id then return false end
    ns.db.ignoreNpc[id] = name or tostring(id)
    if ns.Refresh then ns.Refresh() end
    return true
end
function ns.IgnoreQuest(id, title)
    if not id then return false end
    ns.db.ignoreQuest[id] = title or tostring(id)
    if ns.Refresh then ns.Refresh() end
    return true
end
function ns.Unignore(kind, id)
    ns.db[kind == "npc" and "ignoreNpc" or "ignoreQuest"][id] = nil
    if ns.Refresh then ns.Refresh() end
end

-- The ignore list for the window: { kind, id, name }, NPCs first.
function ns.Ignored()
    local out = {}
    for id, name in pairs(ns.db.ignoreNpc) do out[#out + 1] = { kind = "npc", id = id, name = name } end
    for id, name in pairs(ns.db.ignoreQuest) do out[#out + 1] = { kind = "quest", id = id, name = name } end
    table.sort(out, function(a, b)
        if a.kind ~= b.kind then return a.kind == "npc" end
        return tostring(a.name) < tostring(b.name)
    end)
    return out
end

-- Rules -------------------------------------------------------------------------------------

-- Quests at an NPC, the retail way (C_GossipInfo) with the old greeting as fallback:
-- { { kind = "active"|"available", ref, id, complete, trivial } }.
function ns.Offered(event)
    local out = {}
    if event == "GOSSIP_SHOW" and C_GossipInfo then
        for _, q in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
            out[#out + 1] = { kind = "active", ref = q.questID, id = q.questID, complete = q.isComplete }
        end
        for _, q in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
            out[#out + 1] = { kind = "available", ref = q.questID, id = q.questID, trivial = q.isTrivial }
        end
    elseif event == "QUEST_GREETING" then
        for i = 1, (GetNumActiveQuests and GetNumActiveQuests() or 0) do
            local _, complete = GetActiveTitle(i)
            out[#out + 1] = { kind = "active", ref = i, complete = complete }
        end
        for i = 1, (GetNumAvailableQuests and GetNumAvailableQuests() or 0) do
            local trivial = GetAvailableQuestInfo and GetAvailableQuestInfo(i)
            out[#out + 1] = { kind = "available", ref = i, trivial = trivial }
        end
    end
    return out
end

-- Why a new quest is not taken: a text key, or nil to take it. id may be nil (old greeting).
function ns.SkipNew(id, trivial, group)
    local db = ns.db
    if not db.accept then return "OFF" end
    if id and db.ignoreQuest[id] then return "WHY_IGNORED" end
    if db.skipTrivial and trivial then return "WHY_TRIVIAL" end
    if db.minFree > 0 and logFree() <= db.minFree then return "WHY_FULL" end
    local tag, elite = questTag(id)
    if db.skipDungeon and (tag == TAG_DUNGEON or tag == TAG_RAID or tag == TAG_RAID10 or tag == TAG_RAID25) then
        return "WHY_DUNGEON"
    end
    if db.skipElite and elite then return "WHY_ELITE" end
    if db.skipGroup and (tag == TAG_GROUP or (group or 0) > 1) then return "WHY_GROUP" end
end

-- What to open at an NPC: a finished quest first, then a new one. nil leaves the NPC alone.
function ns.Choose(offered)
    if ns.db.turnIn then
        for _, q in ipairs(offered) do
            if q.kind == "active" and q.complete and not (q.id and ns.db.ignoreQuest[q.id]) then return q end
        end
    end
    for _, q in ipairs(offered) do
        if q.kind == "available" and not ns.SkipNew(q.id, q.trivial) then return q end
    end
end

local function open(event, q)
    local G = event == "GOSSIP_SHOW" and C_GossipInfo
    if q.kind == "active" then
        if G then G.SelectActiveQuest(q.ref) else SelectActiveQuest(q.ref) end
    else
        if G then G.SelectAvailableQuest(q.ref) else SelectAvailableQuest(q.ref) end
    end
    count("clicks")
end

-- The reward with the best vendor price, to point at it when the player must choose.
function ns.BestChoice(n)
    local best, bestPrice, bestLink = nil, -1, nil
    for i = 1, n do
        local link = GetQuestItemLink("choice", i)
        local price = sellPrice(link)
        if price > bestPrice then best, bestPrice, bestLink = i, price, link end
    end
    return best, bestPrice, bestLink
end

-- The required items that are not quest items (cloth, ore...), as links.
function ns.TakesItems()
    local out = {}
    for i = 1, (GetNumQuestItems and GetNumQuestItems() or 0) do
        local link = GetQuestItemLink("required", i)
        local class = itemClass(link)
        if link and class and class ~= QUEST_CLASS then out[#out + 1] = link end
    end
    return out
end

-- A glow around the reward button with the best vendor price.
local glow
local function rewardButton(i)
    local f = QuestInfoRewardsFrame
    return (f and f.RewardButtons and f.RewardButtons[i]) or _G["QuestInfoRewardsFrameQuestInfoItem" .. i]
        or _G["QuestInfoItem" .. i]
end
function ns.MarkBest(i)
    local b = rewardButton(i)
    if not b then return end
    if not glow then
        glow = CreateFrame("Frame", nil, UIParent)
        glow.tex = glow:CreateTexture(nil, "OVERLAY")
        glow.tex:SetAllPoints()
        glow.tex:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        glow.tex:SetBlendMode("ADD")
        glow.tex:SetVertexColor(1, 0.82, 0.2, 1)
    end
    glow:SetParent(b)
    glow:ClearAllPoints()
    glow:SetPoint("TOPLEFT", b, "TOPLEFT", -14, 14)
    glow:SetPoint("BOTTOMRIGHT", b, "BOTTOMLEFT", 54, -14)
    glow:Show()
    return glow
end

local function detailID() return GetQuestID and GetQuestID() or nil end
local function detailTitle() return GetTitleText and GetTitleText() or nil end

local function gossipOnly()
    if not ns.db.gossip or not C_GossipInfo or not C_GossipInfo.GetOptions then return end
    local opts = C_GossipInfo.GetOptions() or {}
    if #opts ~= 1 then return end
    local o = opts[1]
    if C_GossipInfo.SelectOption then C_GossipInfo.SelectOption(o.gossipOptionID or o.optionID or 1) end
    count("clicks")
    return true
end

function ns.OnEvent(event, ...)
    local db = ns.db
    if event == "GOSSIP_SHOW" or event == "QUEST_GREETING" then
        ns.last.npc, ns.last.npcName = npcID(), UnitName and UnitName("npc")
        if ns.Refresh then ns.Refresh() end
    elseif event == "QUEST_DETAIL" or event == "QUEST_PROGRESS" or event == "QUEST_COMPLETE" then
        ns.last.quest, ns.last.questTitle = detailID(), detailTitle()
        if ns.Refresh then ns.Refresh() end
    end
    if event == "QUEST_ACCEPTED" then
        local a, b = ...
        local id = b or a -- classic sends (index, questID), retail (questID)
        if ns.pendingAccept and (id == ns.pendingAccept.id or not ns.pendingAccept.id) then
            ns.last.accepted, ns.last.acceptedTitle = id, ns.pendingAccept.title
            ns.pendingAccept = nil
            if ns.Refresh then ns.Refresh() end
        end
        return
    end
    if ns.Paused() then return end
    if ns.last.npc and db.ignoreNpc[ns.last.npc] and event ~= "QUEST_ACCEPT_CONFIRM" then return end
    if event == "GOSSIP_SHOW" or event == "QUEST_GREETING" then
        local offered = ns.Offered(event)
        local q = ns.Choose(offered)
        if q then open(event, q)
        elseif event == "GOSSIP_SHOW" and #offered == 0 then gossipOnly() end
    elseif event == "QUEST_DETAIL" then
        local id = detailID()
        local why = ns.SkipNew(id, nil, GetSuggestedGroupNum and GetSuggestedGroupNum())
        if why then
            if why ~= "OFF" then say(L.SKIPPED:format(detailTitle() or "?", L[why])) end
            return
        end
        ns.pendingAccept = { id = id, title = detailTitle() }
        if QuestGetAutoAccept and QuestGetAutoAccept() then
            if AcknowledgeAutoAcceptQuest then AcknowledgeAutoAcceptQuest() end
        else
            AcceptQuest()
        end
        count("taken"); count("clicks")
        feed("taken", detailTitle())
    elseif event == "QUEST_ACCEPT_CONFIRM" then
        if db.accept and db.shared and ConfirmAcceptQuest then ConfirmAcceptQuest(); count("clicks") end
    elseif event == "QUEST_PROGRESS" then
        local id = detailID()
        if not db.turnIn or (id and db.ignoreQuest[id]) then return end
        if not IsQuestCompletable() or (GetQuestMoneyToGet and GetQuestMoneyToGet() or 0) > 0 then return end
        if not db.itemQuests then
            local items = ns.TakesItems()
            if #items > 0 then say(L.TAKES_ITEMS:format(items[1])); return end
        end
        CompleteQuest()
        count("clicks")
    elseif event == "QUEST_COMPLETE" then
        local id = detailID()
        if not db.turnIn or (id and db.ignoreQuest[id]) then return end
        local n = GetNumQuestChoices() or 0
        if n <= 1 then
            GetQuestReward(n)
        else
            local best, price, link = ns.BestChoice(n)
            if db.pickBest and best and price > 0 then
                GetQuestReward(best)
                say(L.PICKED:format(link))
            else
                if best and price > 0 then ns.MarkBest(best) end
                if link and price > 0 then say(L.CHOOSE:format(link)) else say(L.CHOOSE_ANY) end
                return
            end
        end
        count("done"); count("clicks")
        feed("done", detailTitle())
    end
end

-- One line for the hub's home page, or nil.
function ns.Summary()
    if not ns.db then return nil end
    if ns.Paused() then return L.PAUSED, ns.OPT_ICON.paused end
    local s = ns.db.session
    if (s.taken or 0) + (s.done or 0) == 0 then return nil end
    return L.FEED:format(s.taken or 0, s.done or 0)
end

-- Every setting back to its default; the ignore lists and the counters stay.
function ns.Reset()
    for k, v in pairs(ns.DEFAULTS) do ns.db[k] = v end
    if ns.Refresh then ns.Refresh() end
end

-- Abandons the last quest this module took (undo), from a click.
function ns.Undo()
    local id = ns.last.accepted
    if not id or not C_QuestLog then return false end
    if C_QuestLog.SetSelectedQuest then C_QuestLog.SetSelectedQuest(id) end
    if C_QuestLog.SetAbandonQuest then C_QuestLog.SetAbandonQuest() end
    if C_QuestLog.AbandonQuest then C_QuestLog.AbandonQuest() end
    say(L.UNDONE:format(ns.last.acceptedTitle or tostring(id)))
    ns.last.accepted, ns.last.acceptedTitle = nil, nil
    if ns.Refresh then ns.Refresh() end
    return true
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1, ...)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliAutoQuestDB = GulliAutoQuestDB or {}
        ns.db = GulliAutoQuestDB
        for k, v in pairs(ns.DEFAULTS) do
            if ns.db[k] == nil then ns.db[k] = v end
        end
        ns.db.ignoreNpc = ns.db.ignoreNpc or {}
        ns.db.ignoreQuest = ns.db.ignoreQuest or {}
        ns.db.session = ns.db.session or {}
        for _, e in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_ACCEPT_CONFIRM",
                             "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_ACCEPTED", "PLAYER_ENTERING_WORLD" }) do
            self:RegisterEvent(e)
        end
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        -- A new login starts a new session; a /reload keeps it.
        if a1 then ns.db.session = {} end
        return
    end
    if ns.paused then return end
    ns.OnEvent(event, a1, ...)
end)

SLASH_GULLIAUTOQUEST1 = "/gaq"
SLASH_GULLIAUTOQUEST2 = "/gulliautoquest"
SlashCmdList.GULLIAUTOQUEST = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "ignore" then
        if ns.IgnoreNpc(ns.last.npc, ns.last.npcName) then say(L.IGNORED:format(ns.last.npcName or "?"))
        else say(L.NO_NPC) end
    elseif msg == "pause" then
        ns.SetPaused(not ns.db.paused)
        say(ns.db.paused and L.PAUSED or L.RUNNING)
    else
        ns.Toggle()
    end
end

function GulliAutoQuest_Toggle() ns.Toggle() end

-- The same switches as in the window, so the Gulli Toolkit hub can show them.
-- The game icon of each switch, in the window and in the hub.
ns.OPT_ICON = {
    accept = "Interface\\Icons\\INV_Scroll_03",
    turnIn = "Interface\\Icons\\INV_Misc_Bag_10",
    skipTrivial = "Interface\\Icons\\Spell_ChargeNegative",
    paused = "Interface\\Icons\\Spell_Nature_TimeStop",
    shared = "Interface\\Icons\\INV_Letter_15",
    itemQuests = "Interface\\Icons\\INV_Fabric_Wool_01",
    skipElite = "Interface\\Icons\\Ability_Warrior_BattleShout",
    skipDungeon = "Interface\\Icons\\INV_Misc_Key_03",
    skipGroup = "Interface\\Icons\\Spell_Holy_PrayerOfHealing",
    minFree = "Interface\\Icons\\INV_Misc_Book_09",
    pickBest = "Interface\\Icons\\INV_Misc_Coin_02",
    gossip = "Interface\\Icons\\INV_Misc_Note_01",
    chat = "Interface\\Icons\\INV_Letter_02",
}

local function option(key, label, tip)
    return { label = label, tip = tip, icon = ns.OPT_ICON[key], get = function() return ns.db ~= nil and ns.db[key] == true end,
             set = function(on)
                 if not ns.db then return end
                 if key == "paused" then ns.SetPaused(on) else ns.db[key] = on and true or false end
             end }
end

if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({
        pause = function(on) ns.paused = on end,
        key = "AutoQuest",
        icon = "Interface\\AddOns\\Gulli-AutoQuest\\icon",
        slash = "/gaq",
        open = function() ns.Toggle() end,
        window = function() return ns.Window and ns.Window() end,
        options = {
            option("paused", ns.L.OPT_PAUSED, ns.L.OPT_PAUSED_D),
            option("accept", ns.L.OPT_ACCEPT, ns.L.NOTE),
            option("turnIn", ns.L.OPT_TURNIN, ns.L.NOTE),
            option("skipTrivial", ns.L.OPT_TRIVIAL),
        },
        summary = function() return ns.Summary() end,
        reset = function() ns.Reset() end,
    })
end
