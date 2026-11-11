-- Takes and hands in quests without the extra taps. It never picks a reward when there is a
-- choice, never pays gold to finish a quest, and stops while Shift is held.

local ADDON, ns = ...
local L = ns.L

local function paused() return IsShiftKeyDown and IsShiftKeyDown() end
local function say(msg) print("|cff9ad0ffGulli AutoQuest|r: " .. msg) end
local function sellPrice(link)
    if not link then return 0 end
    return select(11, ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(link)) or 0
end

-- Quests at an NPC, the retail way (C_GossipInfo) with the old greeting as fallback:
-- { { kind = "active"|"available", ref, complete, trivial } }.
function ns.Offered(event)
    local out = {}
    if event == "GOSSIP_SHOW" and C_GossipInfo then
        for _, q in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
            out[#out + 1] = { kind = "active", ref = q.questID, complete = q.isComplete }
        end
        for _, q in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
            out[#out + 1] = { kind = "available", ref = q.questID, trivial = q.isTrivial }
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

-- What to open at an NPC: a finished quest first, then a new one. nil leaves the NPC alone.
function ns.Choose(offered)
    if ns.db.turnIn then
        for _, q in ipairs(offered) do
            if q.kind == "active" and q.complete then return q end
        end
    end
    if ns.db.accept then
        for _, q in ipairs(offered) do
            if q.kind == "available" and not (ns.db.skipTrivial and q.trivial) then return q end
        end
    end
end

local function open(event, q)
    local G = event == "GOSSIP_SHOW" and C_GossipInfo
    if q.kind == "active" then
        if G then G.SelectActiveQuest(q.ref) else SelectActiveQuest(q.ref) end
    else
        if G then G.SelectAvailableQuest(q.ref) else SelectAvailableQuest(q.ref) end
    end
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

function ns.OnEvent(event, ...)
    if paused() then return end
    local db = ns.db
    if event == "GOSSIP_SHOW" or event == "QUEST_GREETING" then
        local q = ns.Choose(ns.Offered(event))
        if q then open(event, q) end
    elseif event == "QUEST_DETAIL" then
        if db.accept then
            if QuestGetAutoAccept and QuestGetAutoAccept() then
                if AcknowledgeAutoAcceptQuest then AcknowledgeAutoAcceptQuest() end
            else
                AcceptQuest()
            end
        end
    elseif event == "QUEST_ACCEPT_CONFIRM" then
        if db.accept and ConfirmAcceptQuest then ConfirmAcceptQuest() end
    elseif event == "QUEST_PROGRESS" then
        if db.turnIn and IsQuestCompletable() and (GetQuestMoneyToGet and GetQuestMoneyToGet() or 0) == 0 then
            CompleteQuest()
        end
    elseif event == "QUEST_COMPLETE" then
        if not db.turnIn then return end
        local n = GetNumQuestChoices() or 0
        if n <= 1 then
            GetQuestReward(n)
        else
            local _, price, link = ns.BestChoice(n)
            if link and price > 0 then say(L.CHOOSE:format(link)) else say(L.CHOOSE_ANY) end
        end
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1, ...)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliAutoQuestDB = GulliAutoQuestDB or {}
        ns.db = GulliAutoQuestDB
        for k, v in pairs({ accept = true, turnIn = true, skipTrivial = true }) do
            if ns.db[k] == nil then ns.db[k] = v end
        end
        for _, e in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_ACCEPT_CONFIRM",
                             "QUEST_PROGRESS", "QUEST_COMPLETE" }) do
            self:RegisterEvent(e)
        end
        return
    end
    ns.OnEvent(event, a1, ...)
end)

SLASH_GULLIAUTOQUEST1 = "/gaq"
SLASH_GULLIAUTOQUEST2 = "/gulliautoquest"
SlashCmdList.GULLIAUTOQUEST = function() ns.Toggle() end

function GulliAutoQuest_Toggle() ns.Toggle() end

-- The same switches as in the window, so the Gulli Toolkit hub can show them.
local function option(key, label)
    return { label = label, get = function() return ns.db ~= nil and ns.db[key] == true end,
             set = function(on) if ns.db then ns.db[key] = on and true or false end end }
end

if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({
        key = "AutoQuest",
        icon = "Interface\\AddOns\\Gulli-AutoQuest\\icon",
        slash = "/gaq",
        open = function() ns.Toggle() end,
        options = {
            option("accept", ns.L.OPT_ACCEPT),
            option("turnIn", ns.L.OPT_TURNIN),
            option("skipTrivial", ns.L.OPT_TRIVIAL),
        },
    })
end
