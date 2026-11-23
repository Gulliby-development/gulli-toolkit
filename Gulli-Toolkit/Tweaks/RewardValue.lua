-- Reward value: when a quest offers several rewards to choose from, the one a vendor pays the
-- most for gets a coin in its corner. It only marks; the player still picks.

local _, ns = ...

local frame
local marks = {}
local COIN = "Interface\\Icons\\INV_Misc_Coin_02"

local function sellPrice(link)
    if not link then return nil end
    local info = C_Item and C_Item.GetItemInfo
    local f = info or GetItemInfo
    if not f then return nil end
    local price = select(11, f(link))
    return tonumber(price)
end

-- The index of the dearest reward, or nil when there is no choice, a price is not known yet or
-- every reward sells for nothing.
function ns.BestReward(prices, n)
    if (n or 0) < 2 then return nil end
    local best, at = 0, nil
    for i = 1, n do
        local p = prices[i]
        if p == nil then return nil, true end
        if p > best then best, at = p, i end
    end
    return at
end

local function button(i)
    local f = rawget(_G, "QuestInfoRewardsFrame")
    local list = f and rawget(f, "RewardButtons")
    return (list and list[i]) or rawget(_G, "QuestInfoRewardsFrameQuestInfoItem" .. i)
end

local function clear()
    for _, t in pairs(marks) do t:Hide() end
end

local function mark()
    clear()
    local n = GetNumQuestChoices and GetNumQuestChoices() or 0
    local prices = {}
    for i = 1, n do prices[i] = sellPrice(GetQuestItemLink and GetQuestItemLink("choice", i)) end
    local at, waiting = ns.BestReward(prices, n)
    if not at then return nil, waiting end
    local b = button(at)
    if not b then return at end
    local t = marks[b]
    if not t then
        t = b:CreateTexture(nil, "OVERLAY")
        t:SetSize(18, 18)
        t:SetPoint("TOPLEFT", b, "TOPLEFT", -4, 4)
        t:SetTexture(COIN)
        marks[b] = t
    end
    t:Show()
    return at
end
ns.MarkReward = mark

local waiting
local function run()
    local _, w = mark()
    waiting = w
end

local function onEvent(_, event)
    if event == "QUEST_COMPLETE" then
        -- The game lays out its reward buttons on the same event: mark after it.
        if C_Timer and C_Timer.After then C_Timer.After(0.05, run) else run() end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if waiting then
            local _, w = mark()
            waiting = w
        end
    else
        waiting = nil
        clear()
    end
end
ns.RewardValueEvent = onEvent

ns.AddTweak({
    key = "rewardValue", group = "quests", icon = "Interface\\Icons\\INV_Jewelry_Talisman_07", star = true,
    enable = function()
        frame = frame or CreateFrame("Frame")
        frame:SetScript("OnEvent", onEvent)
        frame:RegisterEvent("QUEST_COMPLETE")
        frame:RegisterEvent("QUEST_FINISHED")
        frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    end,
    disable = function()
        if frame then frame:UnregisterAllEvents() end
        clear()
    end,
})
