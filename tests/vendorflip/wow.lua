-- A fake WoW client for the Gulli-VendorFlip tests: the shared basics plus bags, money, item info and the auction house (browse, search, buy).
local W = {}

local function stub()
    return setmetatable({}, { __index = function(t, k)
        if k == "GetWidth" then return function() return 400 end end
        if k == "GetHeight" then return function() return 300 end end
        if k == "GetStringWidth" or k == "GetValue" then return function() return 0 end end
        if k == "IsShown" then return function() return rawget(t, "_shown") == true end end
        if k == "Show" then return function() rawset(t, "_shown", true) end end
        if k == "Hide" then return function() rawset(t, "_shown", false) end end
        if k == "SetShown" then return function(_, v) rawset(t, "_shown", v and true or false) end end
        if k == "IsEnabled" then return function() return rawget(t, "_enabled") ~= false end end
        if k == "SetEnabled" then return function(_, v) rawset(t, "_enabled", v and true or false) end end
        if k == "GetText" then return function() return rawget(t, "_text") end end
        if k == "SetText" then return function(_, v) rawset(t, "_text", v) end end
        if k == "GetNumber" then return function() return tonumber(rawget(t, "_text")) or 0 end end
        if k == "SetScript" then return function(_, n, f) rawset(t, "_" .. n, f) end end
        if k == "HookScript" then return function(_, n, f) rawset(t, "_" .. n, f) end end
        if k == "GetScript" then return function(_, n) return rawget(t, "_" .. n) end end
        if k == "RegisterEvent" then return function(_, e) rawget(t, "_events")[e] = true end end
        if k == "UnregisterEvent" then return function(_, e) rawget(t, "_events")[e] = nil end end
        return function() return stub() end
    end })
end
W.stub = stub

-- The globals every Gulli module uses. spec: locale, level, class, now, combat.
function W.Base(spec)
    W.frames, W.printed, W.timers, W.sent = {}, {}, {}, {}
    W.now = spec.now or 100000
    W.combat = spec.combat or false
    W.level = spec.level or 60
    GetLocale = function() return spec.locale or "enUS" end
    UnitName = function(u) if u == "player" then return spec.name or "Tester" end end
    UnitClass = function() return "Priest", spec.class or "PRIEST" end
    UnitLevel = function(u) if u == "player" then return W.level end return 60 end
    UnitRace = function() return "Human", spec.race or "Human" end
    UnitFactionGroup = function() return spec.faction or "Alliance" end
    GetRealmName = function() return "Realm" end
    InCombatLockdown = function() return W.combat end
    time = function() return W.now end
    GetTime = function() return W.now end
    SlashCmdList = {}
    CreateFrame = function()
        local f = stub()
        rawset(f, "_events", {})
        W.frames[#W.frames + 1] = f
        return f
    end
    UIParent, GameTooltip, UISpecialFrames = stub(), stub(), {}
    tinsert, tremove, wipe = table.insert, table.remove, function(t) for k in pairs(t) do t[k] = nil end return t end
    strtrim = function(s) return (s or ""):match("^%s*(.-)%s*$") end
    C_Timer = { After = function(_, fn) W.timers[#W.timers + 1] = fn end,
                NewTicker = function(_, fn) W.timers[#W.timers + 1] = fn; return stub() end }
    hooksecurefunc = function() end
    PlaySound = function() end
    SOUNDKIT = {}
    RAID_CLASS_COLORS = nil
    issecretvalue = nil
    ChatFrame_OpenChat = function() end
    print = function(...) W.printed[#W.printed + 1] = table.concat({ ... }, " ") end
    GulliToolkit = nil
end

-- Runs the addon files in TOC order with one shared addon table, then ADDON_LOADED.
function W.Load(addon, files)
    local ns = {}
    for _, f in ipairs(files) do
        assert(loadfile(addon .. "/" .. f))(addon, ns)
    end
    W.Fire("ADDON_LOADED", addon)
    return ns
end

-- Sends an event to every frame that registered it (ADDON_LOADED always).
function W.Fire(event, ...)
    for _, f in ipairs(W.frames) do
        local on = rawget(f, "_OnEvent")
        if on and (event == "ADDON_LOADED" or rawget(f, "_events")[event]) then on(f, event, ...) end
    end
end

function W.RunTimers()
    local t = W.timers
    W.timers = {}
    for _, fn in ipairs(t) do fn() end
end

-- Every language has every English key, with the same placeholders, and no extra key.
function W.CheckLocales(ns)
    for _, tag in ipairs(ns.TAGS) do
        local t = ns.T[tag]
        assert(t, "no table for " .. tag)
        for key, text in pairs(ns.T.en) do
            assert(t[key], tag .. " misses " .. key)
            for _, p in ipairs({ "%%d", "%%s" }) do
                local _, a = text:gsub(p, "")
                local _, b = t[key]:gsub(p, "")
                assert(a == b, tag .. "." .. key .. " placeholders differ")
            end
        end
        for key in pairs(t) do assert(ns.T.en[key], tag .. " has an extra key " .. key) end
    end
end

-- A tiny test runner: W.test(name, fn), W.eq(a, b, what), W.finish().
local failed, count = 0, 0
function W.test(name, fn)
    count = count + 1
    local ok, err = pcall(fn)
    if ok then io.write("ok   ", name, "\n")
    else failed = failed + 1; io.write("FAIL ", name, "\n     ", tostring(err), "\n") end
end
function W.eq(a, b, what)
    if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end
function W.finish()
    io.write(string.format("%d/%d passed\n", count - failed, count))
    os.exit(failed == 0 and 0 or 1)
end

-- spec.items = { [id] = { name, quality, sell, stack, class, item level } }, spec.bags = { { id, count } } (one slot
-- each in bag 0), spec.free (free slots), spec.quiver (free slots of a quiver in bag 1), spec.money (copper), spec.browse = { { id, minPrice } },
-- spec.commodity = { [id] = { { unit, count, own } } }, spec.lots = { [id] = { { auction, n, buyout, own } } }.
function Fake(spec)
    W.Base(spec)
    if GulliHUD then GulliHUD.side = nil; GulliHUD.toasts = nil; GulliHUD.byKey = nil end
    W.items = spec.items or {}
    W.bags = spec.bags or {}
    W.free = spec.free or 10
    W.quiver = spec.quiver
    NUM_BAG_SLOTS, NUM_TOTAL_EQUIPPED_BAG_SLOTS = 4, 5   -- WoW Forever wears a reagent bag
    W.money = spec.money or 1000000
    W.browse = spec.browse or {}
    W.commodity = spec.commodity or {}
    W.lots = spec.lots or {}
    W.calls, W.queries, W.searches, W.used = {}, {}, {}, {}
    W.throttled, W.loads = false, 0
    GetMoney = function() return W.money end
    -- spec.enchanter: the character knows Enchanting
    GulliAuction = nil
    GetProfessions = function() return spec.enchanter and 1 or nil end
    GetProfessionInfo = function() return "Enchanting", "icon", 300, 300, 0, 0, 333 end
    C_Container = {
        GetContainerNumSlots = function(b) return b == 0 and math.max(#W.bags, 1) or 0 end,
        -- free slots and the bag family: 0 for a normal bag, spec.quiver for a quiver (bag 1)
        GetContainerNumFreeSlots = function(b)
            if b == 0 then return W.free, 0 end
            if b == 1 and W.quiver then return W.quiver, 1 end
            return 0, 0
        end,
        GetContainerItemInfo = function(b, s)
            local e = b == 0 and W.bags[s]
            return e and e[2] > 0 and { itemID = e[1], stackCount = e[2] } or nil
        end,
        UseContainerItem = function(b, s)
            local e = W.bags[s]
            W.used[#W.used + 1] = { id = e[1], n = e[2] }
            W.money = W.money + (W.items[e[1]] and W.items[e[1]][3] or 0) * e[2]
            e[2] = 0
        end,
    }
    C_Item = {
        GetItemInfo = function(item)
            local id = type(item) == "number" and item or tonumber(tostring(item):match("item:(%d+)"))
            local i = W.items[id]
            if not i then return nil end
            return i[1], "item:" .. id, i[2] or 1, i[6] or 10, 1, "Misc", "Misc", i[4] or 20, "", "icon" .. id, i[3] or 0, i[5] or 15
        end,
        RequestLoadItemDataByID = function() W.loads = W.loads + 1 end,
    }
    if spec.ah == false then C_AuctionHouse = nil else
        local A = {}
        C_AuctionHouse = A
        A.IsThrottledMessageSystemReady = function() return not W.throttled end
        A.SendBrowseQuery = function(q) W.queries[#W.queries + 1] = q end
        A.GetBrowseResults = function()
            local out = {}
            for _, b in ipairs(W.browse) do
                out[#out + 1] = { itemKey = { itemID = b[1], itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 },
                                  minPrice = b[2], totalQuantity = b[3] or 1, containsOwnerItem = false }
            end
            return out
        end
        A.HasFullBrowseResults = function() return true end
        A.RequestMoreBrowseResults = function() W.calls[#W.calls + 1] = "more" end
        A.GetItemKeyInfo = function(key) return { itemID = key.itemID, isCommodity = W.commodity[key.itemID] ~= nil } end
        A.SendSearchQuery = function(key) W.searches[#W.searches + 1] = key end
        A.GetNumCommoditySearchResults = function(id) return #(W.commodity[id] or {}) end
        A.GetCommoditySearchResultInfo = function(id, i)
            local l = W.commodity[id][i]
            return { itemID = id, unitPrice = l[1], quantity = l[2], numOwnerItems = l[3] or 0, auctionID = i }
        end
        A.GetNumItemSearchResults = function(key) return #(W.lots[key.itemID] or {}) end
        A.GetItemSearchResultInfo = function(key, i)
            local l = W.lots[key.itemID][i]
            return { auctionID = l[1], quantity = l[2], buyoutAmount = l[3], containsOwnerItem = l[4] or false,
                     itemLink = "item:" .. key.itemID, itemKey = key }
        end
        A.StartCommoditiesPurchase = function(id, n) W.calls[#W.calls + 1] = "start " .. id .. " " .. n end
        A.ConfirmCommoditiesPurchase = function(id, n) W.calls[#W.calls + 1] = "buy " .. id .. " " .. n end
        A.CancelCommoditiesPurchase = function() W.calls[#W.calls + 1] = "cancel" end
        A.PlaceBid = function(id, amount) W.calls[#W.calls + 1] = "bid " .. id .. " " .. amount end
    end
    AuctionHouseFrame = W.stub()
    GulliVendorFlipDB = spec.db
    return W
end

-- Answers every search the addon sends, one at a time.
function W.AnswerSearches()
    local answered = 0
    for _ = 1, 200 do
        local key = W.searches[answered + 1]
        if not key then break end
        answered = answered + 1
        if W.commodity[key.itemID] then W.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", key.itemID)
        else W.Fire("ITEM_SEARCH_RESULTS_UPDATED", key) end
        W.RunTimers()
    end
    return answered
end

-- Opens the auction house and runs one whole scan.
function W.ScanAll(ns)
    W.Fire("AUCTION_HOUSE_SHOW")
    assert(ns.Scan(true), "scan did not start")
    W.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    W.AnswerSearches()
    W.RunTimers()
end

function Load()
    return W.Load("Gulli-VendorFlip", { "Locales.lua", "Prices.lua", "Core.lua", "Skin.lua", "UI.lua" })
end

return W
