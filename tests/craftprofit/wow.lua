-- A fake WoW client for the Gulli-CraftProfit tests: the shared basics plus items, bags and bank,
-- Auctionator, the profession window, a vendor and a trainer.
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

-- spec.items: id -> { name, sell, bind, quality, bags, bank, ah, age, icon }.
-- spec.prof: { name, skill, cap, recipes = { { id, name, learned, diff, grey, out, count, r = { [id] = n }, source } } }
-- or spec.classic = true to offer only the old GetTradeSkillInfo API.
-- spec.auctionator = false: no Auctionator. spec.vendor: { { id, price, stack, extended } }.
-- spec.trainer: { { name, cost } }.
function Fake(spec)
    W.Base(spec)
    W.items = spec.items or {}
    C_Item = {
        GetItemNameByID = function(id) return W.items[id] and W.items[id].name or ("Item" .. id) end,
        GetItemIconByID = function(id) return W.items[id] and W.items[id].icon or ("icon" .. id) end,
        GetItemInfo = function(id)
            local it = W.items[id] or {}
            return it.name or ("Item" .. id), nil, it.quality or 1, nil, nil, nil, nil, nil, nil, nil, it.sell or 0, nil, nil, it.bind or 0
        end,
        GetItemCount = function(id, bank)
            local it = W.items[id] or {}
            return (it.bags or 0) + (bank and (it.bank or 0) or 0)
        end,
    }
    if spec.auctionator ~= false then
        W.dbUpdate = nil
        Auctionator = { API = { v1 = {
            GetAuctionPriceByItemID = function(caller, id)
                assert(caller == "Gulli-CraftProfit")
                return W.items[id] and W.items[id].ah
            end,
            GetAuctionAgeByItemID = function(_, id) return W.items[id] and W.items[id].age or 0 end,
            RegisterForDBUpdate = function(_, fn) W.dbUpdate = fn end,
        } } }
    else
        Auctionator = nil
    end
    local prof = spec.prof
    C_TradeSkillUI, GetTradeSkillLine, GetNumTradeSkills = nil, nil, nil
    if prof and not spec.classic then
        C_TradeSkillUI = {
            GetChildProfessionInfo = function() return { professionName = prof.name, skillLevel = prof.skill, maxSkillLevel = prof.cap } end,
            GetAllRecipeIDs = function()
                local ids = {}
                for _, r in ipairs(prof.recipes) do ids[#ids + 1] = r.id end
                return ids
            end,
            GetRecipeInfo = function(id)
                for _, r in ipairs(prof.recipes) do
                    if r.id == id then
                        return { recipeID = id, name = r.name, learned = r.learned, relativeDifficulty = r.diff,
                                 maxTrivialLevel = r.grey or 0, icon = "ricon" .. id }
                    end
                end
            end,
            GetRecipeSchematic = function(id)
                for _, r in ipairs(prof.recipes) do
                    if r.id == id then
                        local slots = {}
                        for item, n in pairs(r.r) do slots[#slots + 1] = { reagents = { { itemID = item } }, quantityRequired = n, reagentType = 1 } end
                        return { outputItemID = r.out, quantityMin = r.count or 1, reagentSlotSchematics = slots }
                    end
                end
            end,
            GetRecipeSourceText = function(id)
                for _, r in ipairs(prof.recipes) do if r.id == id then return r.source end end
            end,
        }
    elseif prof then
        local kinds = { [0] = "optimal", "medium", "easy", "trivial" }
        GetTradeSkillLine = function() return prof.name, prof.skill, prof.cap end
        GetNumTradeSkills = function() return #prof.recipes end
        GetTradeSkillInfo = function(i) local r = prof.recipes[i]; return r.name, kinds[r.diff] end
        GetTradeSkillItemLink = function(i) return "|Hitem:" .. prof.recipes[i].out .. ":0|h" end
        GetTradeSkillNumMade = function(i) return prof.recipes[i].count or 1 end
        local function reagents(i)
            local list = {}
            for id, n in pairs(prof.recipes[i].r) do list[#list + 1] = { id, n } end
            table.sort(list, function(a, b) return a[1] < b[1] end)
            return list
        end
        GetTradeSkillNumReagents = function(i) return #reagents(i) end
        GetTradeSkillReagentInfo = function(i, j) local x = reagents(i)[j]; return "R" .. x[1], nil, x[2] end
        GetTradeSkillReagentItemLink = function(i, j) return "|Hitem:" .. reagents(i)[j][1] .. ":0|h" end
    end
    W.vendor = spec.vendor or {}
    GetMerchantNumItems = function() return #W.vendor end
    GetMerchantItemID = function(i) return W.vendor[i][1] end
    GetMerchantItemInfo = function(i)
        local v = W.vendor[i]
        return "Item" .. v[1], 1, v[2], v[3] or 1, -1, true, true, v[4] or false
    end
    W.trainer = spec.trainer or {}
    GetNumTrainerServices = function() return #W.trainer end
    GetTrainerServiceInfo = function(i) return W.trainer[i][1], "available" end
    GetTrainerServiceCost = function(i) return W.trainer[i][2] end
    GetCoinTextureString = nil
    GulliCraftProfitDB, GulliCraftProfitCharDB = spec.db, spec.char
    return W
end

function Load()
    return W.Load("Gulli-CraftProfit", { "Locales.lua", "Core.lua", "Scan.lua", "Skin.lua", "UI.lua" })
end

-- Calls a frame's script as a click or a press would.
function W.Click(f, script) local fn = rawget(f, "_" .. (script or "OnClick")); assert(fn, "no script"); fn(f) end

return W
