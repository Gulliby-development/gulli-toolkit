-- At a vendor: sells the gray items and repairs the gear, each only while its switch is on.
-- Protected items (Gulli Toolkit) are never sold.

local ADDON, ns = ...
local L = ns.L

local J = ns.J
local BATCH = J.BATCH
local STEP = J.STEP
local LEARN = 2 -- an item sold by hand this often is suggested for the "always sell" list

local function money() return GetMoney and GetMoney() or 0 end
local function say(msg) print("|cff9ad0ffGulli Merchant|r: " .. msg) end
local function notify(msg) if GulliToolkit and GulliToolkit.Notify then GulliToolkit.Notify("Merchant", msg) end end

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

-- For the stat tiles: copper is left out once there is gold, so the value stays big.
function ns.ShortMoney(copper)
    copper = math.floor(copper or 0)
    if copper >= 10000 then copper = copper - copper % 100 end
    return ns.Money(copper)
end

-- What a visit sells and earns, for the window.
ns.session = { sold = 0, value = 0, repair = 0 }
ns.DEFAULTS = { sell = true, repair = true, guild = true, safe = false, unusable = false }
-- Items unticked in the window: kept this session.
ns.skip = {}

-- What a sale sells: gray items and the "always sell" list, and bound gear the class cannot
-- use while that switch is on; only items with a price, never protected ones.
-- Returns { { bag, slot, id, count, value, why, ... } } and their total value.
function ns.Junk()
    local out, total = {}, 0
    for _, it in ipairs(J.Scan()) do
        local tier, why = J.Tier(it, { unusable = ns.db and ns.db.unusable })
        if (tier == 1 or why == "unusable") and it.price > 0 and not it.locked then
            it.why = why
            it.checked = not ns.skip[it.id]
            if it.checked then total = total + it.value end
            out[#out + 1] = it
        end
    end
    table.sort(out, function(a, b)
        if a.checked ~= b.checked then return a.checked end
        if a.value ~= b.value then return a.value > b.value end
        return a.name < b.name
    end)
    return out, total
end

-- The ticked part of ns.Junk, cut to 12 with the safe switch.
function ns.ToSell()
    local junk = ns.Junk()
    local out, total = {}, 0
    for _, it in ipairs(junk) do
        if it.checked and not (ns.db.safe and #out >= BATCH) then
            out[#out + 1] = it
            total = total + it.value
        end
    end
    return out, total
end

-- Sells the junk in steps, then calls done(sold, value). With the safe switch on it sells no
-- more than the 12 the vendor can buy back. Returns how many items and their value.
function ns.SellJunk(done, quiet)
    local junk, total = ns.ToSell()
    if #junk == 0 then if done then done(0, 0) end return 0, 0 end
    J.Sell(junk, function(sold, value)
        ns.session.sold = ns.session.sold + sold
        ns.session.value = ns.session.value + value
        if not quiet and sold > 0 then
            local msg = L.SOLD:format(sold, ns.Money(value))
            if sold > BATCH then msg = msg .. " " .. L.BUYBACK end
            say(msg)
        end
        if ns.Refresh then ns.Refresh() end
        if done then done(sold, value) end
    end)
    return #junk, total
end

-- Repairs everything: from the guild bank when allowed and the switch is on, else from
-- the player's money. Returns the cost and where it came from ("guild", "own"), or nil and
-- "money" when the money is short. `quiet` leaves the chat line out (the visit prints one).
function ns.Repair(quiet)
    if not (CanMerchantRepair and CanMerchantRepair()) then return nil end
    local cost, can = GetRepairAllCost()
    if not can or (cost or 0) <= 0 then return nil end
    if ns.db.guild and IsInGuild and IsInGuild() and CanGuildBankRepair and CanGuildBankRepair() then
        local limit = GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney() or 0
        if limit == -1 or limit >= cost then
            RepairAllItems(true)
            ns.session.repair = ns.session.repair + cost
            if not quiet then say(L.REPAIRED_GUILD:format(ns.Money(cost))) end
            notify(L.REPAIRED_GUILD:format(ns.Money(cost)))
            return cost, "guild"
        end
    end
    if money() < cost then
        if not quiet then say(L.NO_MONEY:format(ns.Money(cost))) end
        return nil, "money", cost
    end
    RepairAllItems()
    ns.session.repair = ns.session.repair + cost
    if not quiet then say(L.REPAIRED:format(ns.Money(cost))) end
    return cost, "own"
end

-- One chat line for a visit: what was sold and what the repair cost.
function ns.VisitLine(sold, value, cost, from, short)
    local parts = {}
    if sold > 0 then
        parts[#parts + 1] = L.SOLD:format(sold, ns.Money(value)) .. (sold > BATCH and (" " .. L.BUYBACK) or "")
    end
    if cost then parts[#parts + 1] = (from == "guild" and L.REPAIRED_GUILD or L.REPAIRED):format(ns.Money(cost)) end
    if short then parts[#parts + 1] = L.NO_MONEY:format(ns.Money(short)) end
    if #parts == 0 then return nil end
    return table.concat(parts, " ")
end

-- A vendor opens: repair now if the money is there, else sell first, since the junk may pay
-- for it. One chat line at the end.
function ns.Visit()
    local cost, from, need
    if ns.db.repair then cost, from, need = ns.Repair(true) end
    local short = from == "money"
    if short then cost, from = nil, nil end
    local function report(sold, value)
        local missing = nil
        if short then
            cost, from, missing = ns.Repair(true)
            if from == "money" then missing = missing or need; cost, from = nil, nil else missing = nil end
        end
        local line = ns.VisitLine(sold, value, cost, from, missing)
        if line then say(line) end
        if missing then notify(L.NO_MONEY:format(ns.Money(missing))) end
        if ns.Refresh then ns.Refresh() end
    end
    if ns.db.sell then
        ns.SellJunk(function(sold, value)
            if short and sold > 0 then
                -- The money of the sale comes a moment later.
                C_Timer.After(STEP * 2, function() if J.atVendor then report(sold, value) end end)
            else
                report(sold, value)
            end
        end, true)
    else
        report(0, 0)
    end
end

-- Learning: an item the player sells by hand at a vendor, LEARN times, is suggested for the
-- "always sell" list. Only a suggestion: the player adds it in the window.
function ns.SoldByHand(id)
    if not id or J.selling or J.IsAlways(id) or J.Protected(id) then return end
    local _, _, quality = ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(id)
    if quality == 0 then return end
    ns.db.manual[id] = (ns.db.manual[id] or 0) + 1
end

function ns.Suggestions()
    local out = {}
    for id, n in pairs(ns.db.manual) do
        if n >= LEARN and not J.IsAlways(id) and not ns.db.dismissed[id] and not J.Protected(id) then
            out[#out + 1] = id
        end
    end
    table.sort(out)
    return out
end

function ns.Dismiss(id) ns.db.dismissed[id] = true; ns.db.manual[id] = nil end

-- Adds or removes an item of the "always sell" list from an item link or id.
function ns.MarkFromText(text)
    local id = tonumber(text) or tonumber((text or ""):match("item:(%d+)"))
    if not id then return nil end
    if J.Protected(id) then say(L.IS_PROTECTED) return nil end
    local on = not J.IsAlways(id)
    J.SetAlways(id, on)
    return id, on
end

local function hookManualSales()
    local function onUse(bag, slot)
        if ns.paused or not J.atVendor or J.selling then return end
        ns.SoldByHand((J.SlotInfo(bag, slot)))
    end
    if C_Container and C_Container.UseContainerItem then hooksecurefunc(C_Container, "UseContainerItem", onUse)
    elseif UseContainerItem then hooksecurefunc("UseContainerItem", onUse) end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliMerchantDB = GulliMerchantDB or {}
        ns.db = GulliMerchantDB
        for k, v in pairs(ns.DEFAULTS) do
            if ns.db[k] == nil then ns.db[k] = v end
        end
        ns.db.junk = ns.db.junk or {}
        ns.db.manual = ns.db.manual or {}
        ns.db.dismissed = ns.db.dismissed or {}
        J.Attach(ns.db.junk)
        J.OnChange(function() if ns.Refresh then ns.Refresh() end end)
        J.InstallMarks({ JUNK_TIP = L.JUNK_TIP, ALWAYS_TIP = L.ALWAYS_TIP, MARKED = L.MARKED, UNMARKED = L.UNMARKED })
        hookManualSales()
        self:RegisterEvent("MERCHANT_SHOW")
        self:RegisterEvent("MERCHANT_CLOSED")
        self:RegisterEvent("BAG_UPDATE_DELAYED")
        return
    end
    -- Paused from the hub: only the closing events still run, so nothing stays open.
    if ns.paused and not event:find("_CLOSED$") then return end
    if event == "MERCHANT_SHOW" then
        ns.atVendor = true
        J.atVendor = true
        if ns.ShowVendorButton then ns.ShowVendorButton() end
        -- Shift skips everything once.
        if not (IsShiftKeyDown and IsShiftKeyDown()) then ns.Visit() end
    elseif event == "MERCHANT_CLOSED" then
        ns.atVendor = false
        J.atVendor = false
    end
    if ns.Refresh then ns.Refresh() end
end)

SLASH_GULLIMERCHANT1 = "/gmc"
SLASH_GULLIMERCHANT2 = "/gullimerchant"
SlashCmdList.GULLIMERCHANT = function(msg)
    msg = strtrim(msg or "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "sell" then
        if ns.atVendor then ns.SellJunk() else say(L.NO_VENDOR) end
    elseif cmd == "junk" and rest ~= "" then
        local id, on = ns.MarkFromText(rest)
        if id then say((on and L.MARKED or L.UNMARKED):format(rest)) end
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
    safe = "Interface\\Icons\\Spell_Nature_TimeStop",
    unusable = "Interface\\Icons\\INV_Gauntlets_04",
}

local function option(key, label)
    return { label = label, icon = ns.OPT_ICON[key], tip = ns.L["TIP_" .. key], get = function() return ns.db ~= nil and ns.db[key] == true end,
             set = function(on) if ns.db then ns.db[key] = on and true or false end end }
end

if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({
        pause = function(on)
            ns.paused = on
            if on and ns.HideVendorButton then ns.HideVendorButton() end
        end,
        key = "Merchant",
        icon = "Interface\\AddOns\\Gulli-Merchant\\icon",
        slash = "/gmc",
        open = function() ns.Toggle() end,
        window = function() return ns.Window and ns.Window() end,
        options = {
            option("sell", ns.L.OPT_SELL),
            option("repair", ns.L.OPT_REPAIR),
            option("guild", ns.L.OPT_GUILD),
            option("safe", ns.L.OPT_SAFE),
            option("unusable", ns.L.OPT_UNUSABLE),
        },
        -- what this session sold, else the junk waiting in the bags
        summary = function()
            if not ns.db then return nil end
            if ns.session.sold > 0 then
                return ns.L.SUMMARY_SOLD:format(ns.session.sold, ns.Money(ns.session.value)), ns.OPT_ICON.sell
            end
            local junk = ns.Junk()
            if #junk == 0 then return nil end
            local value = 0
            for _, it in ipairs(junk) do if it.checked then value = value + it.value end end
            return ns.L.SUMMARY_JUNK:format(#junk, ns.Money(value)), ns.OPT_ICON.sell
        end,
        reset = function()
            if not ns.db then return end
            for k, v in pairs(ns.DEFAULTS) do ns.db[k] = v end
            if ns.Refresh then ns.Refresh() end
        end,
    })
end
