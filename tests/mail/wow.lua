-- A fake WoW client for the Gulli-Mail tests: the shared basics plus a mailbox.
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

-- W.inbox = { { sender, money, cod, items = { id, ... }, gm } }; W.free = free bag slots.
function Fake(spec)
    W.Base(spec)
    W.inbox, W.free, W.taken, W.money = spec.inbox or {}, spec.free or 20, {}, 0
    W.server, W.refuse, W.checks = spec.server or {}, spec.refuse or {}, 0
    GetInboxNumItems = function() return #W.inbox, #W.inbox + #W.server end
    GetMoney = function() return W.money end
    -- The server tops the shown letters up to 50.
    CheckInbox = function()
        W.checks = W.checks + 1
        while #W.inbox < 50 and #W.server > 0 do table.insert(W.inbox, 1, table.remove(W.server, 1)) end
    end
    GetInboxHeaderInfo = function(i)
        local m = W.inbox[i]
        local n = 0
        for _ in pairs(m.items or {}) do n = n + 1 end
        return nil, nil, m.sender, m.subject or "Subject", m.money or 0, m.cod or 0, m.days or 30, n, false, m.returned,
            false, m.player ~= false and not m.gm and not m.invoice and m.sender ~= "AH", m.gm
    end
    GetInboxItem = function(i, j)
        local id = W.inbox[i].items and W.inbox[i].items[j]
        if id then return "Item" .. id, id, 1, 1 end
    end
    -- A letter with nothing left and no text (auction mail) goes away.
    local function gone(i)
        local m = W.inbox[i]
        if m.text or (m.money or 0) > 0 or next(m.items or {}) then return end
        table.remove(W.inbox, i)
    end
    TakeInboxMoney = function(i) W.money = W.money + W.inbox[i].money; W.inbox[i].money = 0; gone(i) end
    TakeInboxItem = function(i, j)
        if W.refuse[W.inbox[i].items[j]] then return end
        W.taken[#W.taken + 1] = W.inbox[i].items[j]
        W.inbox[i].items[j] = nil
        W.free = W.free - 1
        gone(i)
    end
    -- spec.bags = { [bag] = { [slot] = { id, bound } } }, spec.classes = { [id] = { class, subclass } }
    W.bags, W.classes, W.used = spec.bags or {}, spec.classes or {}, {}
    C_Container = {
        GetContainerNumFreeSlots = function(b) if b == 0 then return W.free, 0 end return 0, 0 end,
        GetContainerNumSlots = function(b) return W.bags[b] and 16 or 0 end,
        GetContainerItemInfo = function(b, s)
            local x = W.bags[b] and W.bags[b][s]
            if x then return { itemID = x.id, isLocked = false } end
        end,
        UseContainerItem = function(b, s) W.used[#W.used + 1] = W.bags[b][s].id; W.bags[b][s] = nil end,
    }
    C_Item = { GetItemInfo = function(id)
        local c = W.classes[id] or {}
        return "Item" .. id, nil, 1, nil, nil, nil, nil, 1, nil, nil, 1, c[1], c[2]
    end, IsBound = function(loc) local x = W.bags[loc.bag][loc.slot] return x and x.bound end }
    ItemLocation = { CreateFromBagAndSlot = function(_, b, s) return { bag = b, slot = s } end }
    SendMailFrame = W.stub()
    W.sendMoney = nil
    SendMailMoney = {}
    MoneyInputFrame_SetCopper = function(_, c) W.sendMoney = c end
    W.returned = {}
    ReturnInboxItem = function(i) W.returned[#W.returned + 1] = W.inbox[i].sender end
    W.invoices = spec.invoices or {}
    GetInboxInvoiceInfo = function(i) return W.inbox[i].invoice end
    W.friends, W.guild = spec.friends or {}, spec.guild or {}
    C_FriendList = { GetNumFriends = function() return #W.friends end,
                     GetFriendInfoByIndex = function(i) return { name = W.friends[i] } end }
    IsInGuild = function() return #W.guild > 0 end
    GetNumGuildMembers = function() return #W.guild end
    GetGuildRosterInfo = function(i) return W.guild[i] end
    MailFrameTab2 = { Click = function() W.tab = 2 end }
    SendMailNameEditBox = { SetText = function(_, t) W.to = t end }
    SendMail = function() end
    W.hooks = {}
    hooksecurefunc = function(name, fn) W.hooks[name] = fn end
    GulliMailDB = spec.db
    return W
end

-- Runs the timed steps until none are left.
function W.Drain()
    for _ = 1, 100 do
        if #W.timers == 0 then return end
        local t = W.timers; W.timers = {}
        for _, fn in ipairs(t) do fn() end
    end
end

function Load()
    return W.Load("Gulli-Mail", { "Locales.lua", "Core.lua", "Skin.lua", "UI.lua" })
end

return W
