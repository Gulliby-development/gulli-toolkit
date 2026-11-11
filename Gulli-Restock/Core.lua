-- Keeps reagents, ammo, food and water at the amount the player sets for each character.
-- At a vendor it shows what it would buy and what it costs; only OK buys.

local ADDON, ns = ...
local L = ns.L

-- Class reagents: item, amount to keep, level the spell that needs it comes at.
-- A later entry with the same group replaces an earlier one once the level is reached.
ns.PRESETS = {
    MAGE = { { 17031, 10, 20 }, { 17032, 10, 40 }, { 17020, 20, 56 } },
    PRIEST = { { 17028, 20, 48, "candle" }, { 17029, 20, 56, "candle" } },
    PALADIN = { { 17033, 5, 30 }, { 21177, 40, 52 } },
    DRUID = { { 17034, 5, 20, "seed" }, { 17035, 5, 30, "seed" }, { 17036, 5, 40, "seed" },
              { 17037, 5, 50, "seed" }, { 17038, 5, 60, "seed" },
              { 17021, 20, 50, "gift" }, { 17026, 20, 60, "gift" } },
    SHAMAN = { { 17030, 5, 30 } },
    WARLOCK = { { 5565, 5, 50 }, { 16583, 2, 60 } },
    ROGUE = { { 5140, 10, 22 } },
}

local LOW_SHARE = 0.25 -- warn when an item drops to a quarter of what is kept

-- Game API wrappers.
local function count(id) return ((C_Item and C_Item.GetItemCount) or GetItemCount)(id) or 0 end
function ns.ItemName(id)
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    if not name and GetItemInfo then name = GetItemInfo(id) end
    return name or ("#" .. id)
end
function ns.ItemIcon(id)
    return (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or (GetItemIcon and GetItemIcon(id))
        or "Interface\\Icons\\INV_Misc_QuestionMark"
end
local function merchantCount() return GetMerchantNumItems and GetMerchantNumItems() or 0 end
local function merchantItem(i)
    local id = GetMerchantItemID and GetMerchantItemID(i)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local t = C_MerchantFrame.GetItemInfo(i)
        if not t then return nil end
        return id, t.price or 0, t.stackCount or 1, t.numAvailable or -1, t.hasExtendedCost
    end
    local _, _, price, stack, available, _, _, extended = GetMerchantItemInfo(i)
    return id, price or 0, stack or 1, available or -1, extended
end
local function maxStack(i) return GetMerchantItemMaxStack and GetMerchantItemMaxStack(i) or 20 end
local function money() return GetMoney and GetMoney() or 0 end

-- The keep list of this character: { { id, want, have } } by name.
function ns.List()
    local out = {}
    for id, want in pairs(ns.char.list) do
        out[#out + 1] = { id = id, want = want, have = count(id) }
    end
    table.sort(out, function(a, b) return ns.ItemName(a.id) < ns.ItemName(b.id) end)
    return out
end

function ns.Set(id, want)
    id = tonumber(id)
    if not id then return end
    want = math.floor(tonumber(want) or 0)
    ns.char.list[id] = want > 0 and want or nil
    ns.char.warned[id] = nil
    if ns.Refresh then ns.Refresh() end
end

-- Adds the reagents of the player's class for its level. Returns how many were added.
function ns.AddPreset()
    local _, class = UnitClass("player")
    local level = UnitLevel("player")
    local best = {}
    local added = 0
    for _, p in ipairs(ns.PRESETS[class] or {}) do
        if level >= p[3] then
            if p[4] then best[p[4]] = p else
                if not ns.char.list[p[1]] then ns.char.list[p[1]] = p[2]; added = added + 1 end
            end
        end
    end
    for _, p in pairs(best) do
        if not ns.char.list[p[1]] then ns.char.list[p[1]] = p[2]; added = added + 1 end
    end
    if ns.Refresh then ns.Refresh() end
    return added
end

-- What to buy from the open vendor: { { index, id, buy, cost, purchases, stack } } and the total.
-- Items with another price than gold (tokens, marks) are left out.
function ns.Plan()
    local plan, total = {}, 0
    local seen = {}
    for i = 1, merchantCount() do
        local id, price, stack, available, extended = merchantItem(i)
        local want = id and ns.char.list[id]
        if want and not extended and not seen[id] then
            seen[id] = true
            local need = want - count(id)
            if need > 0 then
                stack = math.max(1, stack)
                local purchases = math.ceil(need / stack)
                if available >= 0 then purchases = math.min(purchases, available) end
                if purchases > 0 then
                    local cost = purchases * price
                    plan[#plan + 1] = { index = i, id = id, buy = purchases * stack, cost = cost,
                                        purchases = purchases, stack = stack }
                    total = total + cost
                end
            end
        end
    end
    return plan, total
end

-- Buys the plan. Runs from the OK click. Stops before an item the money no longer covers.
function ns.Buy(plan)
    local left = money()
    local bought = 0
    for _, e in ipairs(plan) do
        if e.cost > left then
            print("|cff9ad0ffGulli Restock|r: " .. L.NO_MONEY:format(ns.ItemName(e.id)))
            break
        end
        if e.stack > 1 then
            -- Sold in fixed stacks (arrows, some food): one purchase per call.
            for _ = 1, e.purchases do BuyMerchantItem(e.index) end
        else
            local n, max = e.purchases, maxStack(e.index)
            while n > 0 do
                local k = math.min(n, max)
                BuyMerchantItem(e.index, k)
                n = n - k
            end
        end
        left = left - e.cost
        bought = bought + 1
        ns.char.warned[e.id] = nil
    end
    return bought
end

-- Prints one warning when an item drops low; again only after it was restocked.
function ns.CheckLow()
    local low = {}
    for id, want in pairs(ns.char.list) do
        local have = count(id)
        if have <= math.floor(want * LOW_SHARE) then
            if not ns.char.warned[id] then
                ns.char.warned[id] = true
                low[#low + 1] = ns.ItemName(id) .. " (" .. have .. ")"
            end
        elseif have >= want then
            ns.char.warned[id] = nil
        end
    end
    if #low == 0 then return nil end
    table.sort(low)
    local msg = L.LOW:format(table.concat(low, ", "))
    print("|cff9ad0ffGulli Restock|r: " .. msg)
    if GulliToolkit and GulliToolkit.Notify then GulliToolkit.Notify("Restock", msg) end
    return msg
end

local pending = false
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliRestockDB = GulliRestockDB or {}
        ns.db = GulliRestockDB
        if ns.db.auto == nil then ns.db.auto = false end
        GulliRestockCharDB = GulliRestockCharDB or {}
        ns.char = GulliRestockCharDB
        ns.char.list = ns.char.list or {}
        ns.char.warned = ns.char.warned or {}
        self:RegisterEvent("MERCHANT_SHOW")
        self:RegisterEvent("MERCHANT_CLOSED")
        self:RegisterEvent("BAG_UPDATE_DELAYED")
        return
    end
    if event == "MERCHANT_SHOW" then
        local plan, total = ns.Plan()
        if #plan == 0 then return end
        if ns.db.auto and total <= money() then
            ns.Buy(plan)
        elseif ns.ShowPlan then
            ns.ShowPlan(plan, total)
        end
    elseif event == "MERCHANT_CLOSED" then
        if ns.HidePlan then ns.HidePlan() end
    elseif event == "BAG_UPDATE_DELAYED" then
        if pending then return end
        pending = true
        C_Timer.After(1, function()
            pending = false
            ns.CheckLow()
            if ns.Refresh then ns.Refresh() end
        end)
    end
end)

SLASH_GULLIRESTOCK1 = "/grs"
SLASH_GULLIRESTOCK2 = "/gullirestock"
SlashCmdList.GULLIRESTOCK = function() ns.Toggle() end

function GulliRestock_Toggle() ns.Toggle() end

if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({
        key = "Restock",
        icon = "Interface\\AddOns\\Gulli-Restock\\icon",
        slash = "/grs",
        open = function() ns.Toggle() end,
    })
end
