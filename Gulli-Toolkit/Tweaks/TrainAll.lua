-- Train all: one button on the trainer's window that learns every available skill the money
-- covers, cheapest first. It buys only inside the player's click.

local _, ns = ...

local frame, button

-- The trainer's available skills that the money covers, cheapest first: { { index, cost } }.
function ns.TrainPlan(money)
    local list = {}
    if not GetNumTrainerServices or not GetTrainerServiceInfo then return list, 0 end
    for i = 1, GetNumTrainerServices() or 0 do
        local _, _, kind = GetTrainerServiceInfo(i)
        if kind == "available" then
            local cost = GetTrainerServiceCost and GetTrainerServiceCost(i) or 0
            list[#list + 1] = { index = i, cost = tonumber(cost) or 0 }
        end
    end
    table.sort(list, function(a, b)
        if a.cost ~= b.cost then return a.cost < b.cost end
        return a.index < b.index
    end)
    local out, total = {}, 0
    for _, s in ipairs(list) do
        if total + s.cost <= (money or 0) then out[#out + 1] = s; total = total + s.cost end
    end
    return out, total
end

local function money() return GetMoney and GetMoney() or 0 end

local function refresh()
    if not button then return end
    local plan, total = ns.TrainPlan(money())
    local S = ns.Skin
    button:SetText(#plan > 0 and ns.L.TW_TRAIN_BTN:format(S.MoneyIcons(total, true)) or ns.L.TW_TRAIN_NONE)
    button:SetEnabled(#plan > 0)
    button:SetWidth(math.max(150, math.ceil((button.text:GetStringWidth() or 0) + 24)))
end

-- Buys from the highest index down, so the indexes still to buy do not move.
function ns.TrainAll()
    local plan = ns.TrainPlan(money())
    table.sort(plan, function(a, b) return a.index > b.index end)
    for _, s in ipairs(plan) do
        if BuyTrainerService then BuyTrainerService(s.index) end
    end
    return #plan
end

local function host()
    return ClassTrainerFrame
end

local function build()
    local f = host()
    local S = ns.Skin
    if button or not f or not S then return end
    button = S.Button(f, 170, 28)
    S.Primary(button)
    -- Beside the game's Train button, else over the window's bottom right corner.
    local train = rawget(_G, "ClassTrainerTrainButton")
    if train then
        button:SetHeight(math.max(28, train:GetHeight() or 0))
        button:SetPoint("RIGHT", train, "LEFT", -4, 0)
    else
        button:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, 4)
    end
    button:SetScript("OnClick", function()
        ns.TrainAll()
        if C_Timer and C_Timer.After then C_Timer.After(0.3, refresh) end
    end)
    button:HookScript("OnEnter", function(self)
        local plan, total = ns.TrainPlan(money())
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(ns.L.TW_TRAINALL)
        GameTooltip:AddLine(ns.L.TW_TRAIN_TIP:format(#plan, S.MoneyText(total)), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function onEvent(_, event)
    if event == "TRAINER_SHOW" then build() end
    if button then
        if event == "TRAINER_CLOSED" then button:Hide()
        elseif event == "TRAINER_SHOW" or button:IsShown() then button:Show(); refresh() end
    end
end
ns.TrainAllEvent = onEvent
ns.TrainAllButton = function() return button end

ns.AddTweak({
    key = "trainAll", group = "level", icon = "Interface\\Icons\\INV_Misc_Book_11", star = true,
    enable = function()
        frame = frame or CreateFrame("Frame")
        frame:SetScript("OnEvent", onEvent)
        frame:RegisterEvent("TRAINER_SHOW")
        frame:RegisterEvent("TRAINER_UPDATE")
        frame:RegisterEvent("TRAINER_CLOSED")
        frame:RegisterEvent("PLAYER_MONEY")
        if button and host() and host():IsShown() then button:Show(); refresh() end
    end,
    disable = function()
        if frame then frame:UnregisterAllEvents() end
        if button then button:Hide() end
    end,
})
