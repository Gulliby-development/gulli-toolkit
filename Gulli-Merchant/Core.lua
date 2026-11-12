-- At a vendor: sells the gray items and repairs the gear, each only while its switch is on.
-- Protected items (Gulli Toolkit) are never sold.

local ADDON, ns = ...
local L = ns.L

local BATCH = 12 -- the vendor's buyback holds 12 items; sell in steps of that size
local STEP = 0.25

-- Game API wrappers.
local C = C_Container or {}
local function numSlots(bag) return (C.GetContainerNumSlots or GetContainerNumSlots)(bag) or 0 end
local function slotInfo(bag, slot)
    if C.GetContainerItemInfo then
        local i = C.GetContainerItemInfo(bag, slot)
        if not i then return nil end
        return i.itemID, i.stackCount, i.quality, i.hasNoValue, i.isLocked
    end
    local _, count, locked, quality, _, _, _, _, noValue, id = GetContainerItemInfo(bag, slot)
    return id, count, quality, noValue, locked
end
local function sellPrice(id)
    local price = select(11, ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(id))
    return price or 0
end
local function useItem(bag, slot) (C.UseContainerItem or UseContainerItem)(bag, slot) end
local function money() return GetMoney and GetMoney() or 0 end
local function protected(id)
    return GulliToolkit and GulliToolkit.IsProtected and GulliToolkit.IsProtected(id) or false
end
local function say(msg) print("|cff9ad0ffGulli Merchant|r: " .. msg) end

function ns.Money(copper)
    copper = math.floor(copper or 0)
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
    return table.concat(parts, " ")
end

-- Gray items with a price: { { bag, slot, id, count, value } } and their total value.
function ns.Junk()
    local out, total = {}, 0
    for bag = 0, 4 do
        for slot = 1, numSlots(bag) do
            local id, count, quality, noValue, locked = slotInfo(bag, slot)
            if id and quality == 0 and not noValue and not locked and not protected(id) then
                local value = sellPrice(id) * (count or 1)
                if value > 0 then
                    out[#out + 1] = { bag = bag, slot = slot, id = id, count = count or 1, value = value }
                    total = total + value
                end
            end
        end
    end
    return out, total
end

-- Sells the junk in steps, so the vendor keeps up. Returns how many items and their value.
function ns.SellJunk()
    local junk, total = ns.Junk()
    if #junk == 0 then return 0, 0 end
    local i = 1
    local function step()
        if not ns.atVendor then return end
        for _ = 1, BATCH do
            local it = junk[i]
            if not it then
                say(L.SOLD:format(#junk, ns.Money(total)))
                return
            end
            -- The slot can change while we sell; sell it only if it still holds the same item.
            if slotInfo(it.bag, it.slot) == it.id then useItem(it.bag, it.slot) end
            i = i + 1
        end
        C_Timer.After(STEP, step)
    end
    step()
    return #junk, total
end

-- Repairs everything: from the guild bank when allowed and the switch is on, else from
-- the player's money. Returns the cost and where it came from ("guild", "own"), or nil.
function ns.Repair()
    if not (CanMerchantRepair and CanMerchantRepair()) then return nil end
    local cost, can = GetRepairAllCost()
    if not can or (cost or 0) <= 0 then return nil end
    if ns.db.guild and IsInGuild and IsInGuild() and CanGuildBankRepair and CanGuildBankRepair() then
        local limit = GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney() or 0
        if limit == -1 or limit >= cost then
            RepairAllItems(true)
            say(L.REPAIRED_GUILD:format(ns.Money(cost)))
            return cost, "guild"
        end
    end
    if money() < cost then
        say(L.NO_MONEY:format(ns.Money(cost)))
        return nil
    end
    RepairAllItems()
    say(L.REPAIRED:format(ns.Money(cost)))
    return cost, "own"
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliMerchantDB = GulliMerchantDB or {}
        ns.db = GulliMerchantDB
        for k, v in pairs({ sell = true, repair = true, guild = true }) do
            if ns.db[k] == nil then ns.db[k] = v end
        end
        self:RegisterEvent("MERCHANT_SHOW")
        self:RegisterEvent("MERCHANT_CLOSED")
        return
    end
    if event == "MERCHANT_SHOW" then
        ns.atVendor = true
        if IsShiftKeyDown and IsShiftKeyDown() then return end -- Shift skips everything once
        if ns.db.repair then ns.Repair() end
        if ns.db.sell then ns.SellJunk() end
    else
        ns.atVendor = false
    end
    if ns.Refresh then ns.Refresh() end
end)

SLASH_GULLIMERCHANT1 = "/gmc"
SLASH_GULLIMERCHANT2 = "/gullimerchant"
SlashCmdList.GULLIMERCHANT = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "sell" then
        if ns.atVendor then ns.SellJunk() else say(L.NO_VENDOR) end
    else
        ns.Toggle()
    end
end

function GulliMerchant_Toggle() ns.Toggle() end

-- The same switches as in the window, so the Gulli Toolkit hub can show them.
-- The game icon of each switch, in the window and in the hub.
ns.OPT_ICON = {
    sell = "Interface\\Icons\\INV_Misc_Coin_02",
    repair = "Interface\\Icons\\Trade_BlackSmithing",
    guild = "Interface\\Icons\\INV_Shirt_GuildTabard_01",
}

local function option(key, label)
    return { label = label, icon = ns.OPT_ICON[key], get = function() return ns.db ~= nil and ns.db[key] == true end,
             set = function(on) if ns.db then ns.db[key] = on and true or false end end }
end

if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({
        key = "Merchant",
        icon = "Interface\\AddOns\\Gulli-Merchant\\icon",
        slash = "/gmc",
        open = function() ns.Toggle() end,
        window = function() return ns.Window and ns.Window() end,
        options = {
            option("sell", ns.L.OPT_SELL),
            option("repair", ns.L.OPT_REPAIR),
            option("guild", ns.L.OPT_GUILD),
        },
    })
end
