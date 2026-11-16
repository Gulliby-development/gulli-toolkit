-- What the player farms this session: up to three targets (an item or gold), each with an
-- optional goal, and everything that came into the bags. A gain is a bag count that went up
-- (or money that came in) away from a vendor, the mailbox, the bank, the auction house and a
-- trade. The session lives in GulliFarmTrackCharDB, so a /reload keeps it; a new login starts
-- a new one. The targets stay until the player changes them.

local ADDON, ns = ...
local L = ns.L

ns.MAX_TARGETS = 3
ns.IDLE = 600 -- a gap without gains longer than this counts only this much as play
local MIN_SPAN = 60 -- the rate looks at a minute at least
local QUIET = 1 -- seconds after a vendor or the mailbox closes in which bag changes do not count
ns.GOLD_ICON = "Interface\\Icons\\INV_Misc_Coin_01"

-- The kinds of target. A new kind gets a key here (its name, icon and what the session holds
-- of it), texts in every language and a test.
ns.KINDS = {
    item = {
        key = function(t) return "item:" .. t.id end,
        gained = function(s, t) return s.items[t.id] or 0 end,
        name = function(t) return ns.ItemName(t.id) end,
        icon = function(t) return ns.ItemIcon(t.id) end,
    },
    gold = {
        key = function() return "gold" end,
        gained = function(s) return s.money end,
        name = function() return L.GOLD end,
        icon = function() return ns.GOLD_ICON end,
    },
}

-- Game API wrappers -----------------------------------------------------------------------------

local CI = C_Item or {}
local CC = C_Container or {}

function ns.ItemName(id)
    local n = CI.GetItemNameByID and CI.GetItemNameByID(id)
    if not n and GetItemInfo then n = GetItemInfo(id) end
    if not n and CI.RequestLoadItemDataByID then CI.RequestLoadItemDataByID(id) end
    return n or ("#" .. tostring(id))
end

function ns.ItemIcon(id)
    return (CI.GetItemIconByID and CI.GetItemIconByID(id)) or (GetItemIcon and GetItemIcon(id))
        or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function numSlots(bag)
    if CC.GetContainerNumSlots then return CC.GetContainerNumSlots(bag) or 0 end
    return GetContainerNumSlots and GetContainerNumSlots(bag) or 0
end

-- id, count of one bag slot.
local function slotInfo(bag, slot)
    if CC.GetContainerItemInfo then
        local i = CC.GetContainerItemInfo(bag, slot)
        if i then return i.itemID, i.stackCount or 1 end
        return
    end
    if GetContainerItemInfo then
        local _, count, _, _, _, _, _, _, _, id = GetContainerItemInfo(bag, slot)
        return id, count
    end
end

local function money() return GetMoney and GetMoney() or 0 end
local function now() return GetTime and GetTime() or time() end

-- Item id -> count over the backpack, the bags and the reagent bag.
function ns.CountBags()
    local out = {}
    for bag = 0, 5 do
        for slot = 1, numSlots(bag) do
            local id, n = slotInfo(bag, slot)
            if id then out[id] = (out[id] or 0) + (n or 1) end
        end
    end
    return out
end

-- The session -----------------------------------------------------------------------------------

local function newSession(t)
    return { t = t, active = 0, lastActive = t, items = {}, money = 0, reached = {} }
end

function ns.Start(t)
    t = t or time()
    ns.s = newSession(t)
    if ns.cdb then ns.cdb.s = ns.s end
    ns.last, ns.lastMoney = ns.CountBags(), money()
end

-- After a /reload the saved session goes on.
function ns.Resume(t)
    local s = ns.cdb and ns.cdb.s
    if type(s) == "table" and s.t then
        s.items, s.reached = s.items or {}, s.reached or {}
        s.money, s.active, s.lastActive = s.money or 0, s.active or 0, s.lastActive or s.t
        ns.s = s
        ns.last, ns.lastMoney = ns.CountBags(), money()
    else
        ns.Start(t)
    end
end

local function step(t, last) return math.min(math.max(0, t - (last or t)), ns.IDLE) end

-- Seconds of farming in this session, a break counting only ns.IDLE.
function ns.Active(t)
    t = t or time()
    return ns.s.active + step(t, ns.s.lastActive)
end

local function played(t)
    local s = ns.s
    s.active = s.active + step(t, s.lastActive)
    s.lastActive = t
end

-- Vendors, the mailbox, the bank, the auction house and a trade move things without farming.
ns.busy = {}
function ns.Busy()
    return next(ns.busy) ~= nil
end

function ns.SetBusy(what, on)
    ns.busy[what] = on and true or nil
    if not on then
        ns.quietUntil = now() + QUIET
        ns.last, ns.lastMoney = ns.CountBags(), money()
    end
end

-- A gain of n of an item (or of copper with id "gold").
function ns.Gain(id, n, t)
    if n <= 0 then return end
    t = t or time()
    played(t)
    if id == "gold" then ns.s.money = ns.s.money + n
    else ns.s.items[id] = (ns.s.items[id] or 0) + n end
    ns.CheckGoals(t)
end

-- The bags changed: what went up counts, unless something else moved it.
function ns.OnBags(t)
    if CursorHasItem and CursorHasItem() then return end -- an item in the hand comes back later
    local cur = ns.CountBags()
    if not ns.Busy() and now() >= (ns.quietUntil or 0) then
        for id, n in pairs(cur) do
            local d = n - ((ns.last or {})[id] or 0)
            if d > 0 then ns.Gain(id, d, t) end
        end
    end
    ns.last = cur
end

-- Money came in: looted gold counts, and a vendor's when the player wants (sales).
function ns.OnMoney(t)
    local m = money()
    local d = m - (ns.lastMoney or m)
    ns.lastMoney = m
    if d <= 0 then return end
    local other = false
    for what in pairs(ns.busy) do if what ~= "merchant" then other = true end end
    if not other and (not ns.busy.merchant or ns.db.sales) then ns.Gain("gold", d, t) end
end

-- Targets ---------------------------------------------------------------------------------------

function ns.Targets()
    return ns.cdb and ns.cdb.targets or {}
end

local function keyOf(t) return ns.KINDS[t.kind].key(t) end

-- Adds a target (kind "item" with id, or "gold"), or sets the goal of one already there.
-- Returns false when the list is full.
function ns.AddTarget(kind, id, goal)
    local list = ns.cdb.targets
    local new = { kind = kind, id = kind == "item" and tonumber(id) or nil, goal = tonumber(goal) }
    if kind == "item" and not new.id then return false end
    for _, t in ipairs(list) do
        if keyOf(t) == keyOf(new) then
            if goal then t.goal = new.goal end
            if ns.Refresh then ns.Refresh() end
            return true
        end
    end
    if #list >= ns.MAX_TARGETS then return false end
    list[#list + 1] = new
    if ns.Refresh then ns.Refresh() end
    return true
end

function ns.RemoveTarget(i)
    local t = table.remove(ns.cdb.targets, i)
    if t and ns.s then ns.s.reached[keyOf(t)] = nil end
    if ns.Refresh then ns.Refresh() end
end

-- A goal of 0 or nil is no goal. Gold goals are in copper.
function ns.SetGoal(i, goal)
    local t = ns.cdb.targets[i]
    if not t then return end
    goal = tonumber(goal)
    t.goal = goal and goal > 0 and math.floor(goal) or nil
    ns.s.reached[keyOf(t)] = nil
    ns.CheckGoals()
    if ns.Refresh then ns.Refresh() end
end

-- Everything the panel and the window show about one target.
function ns.Info(t, at)
    at = at or time()
    local k = ns.KINDS[t.kind]
    local gained = k.gained(ns.s, t)
    local rate = gained * 3600 / math.max(MIN_SPAN, ns.Active(at))
    local goal = t.goal
    local info = { key = k.key(t), kind = t.kind, id = t.id, name = k.name(t), icon = k.icon(t),
                   gained = gained, goal = goal, rate = rate }
    if goal then
        info.pct = math.min(1, gained / goal)
        info.done = gained >= goal
        if not info.done and rate > 0 then info.eta = math.floor((goal - gained) / rate * 3600) end
    end
    return info
end

-- Tells once per target when its goal is reached.
function ns.CheckGoals(at)
    if not ns.s then return end
    for _, t in ipairs(ns.Targets()) do
        local i = ns.Info(t, at)
        if i.done and not ns.s.reached[i.key] then
            ns.s.reached[i.key] = true
            local text = L.GOAL_REACHED:format(i.name, ns.Amount(t.kind, i.goal), ns.Span(ns.Active(at)))
            if ns.db.alert then
                if ns.OnGoal then ns.OnGoal(i, text) end
                if PlaySound and SOUNDKIT and SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01 then
                    PlaySound(SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01, "Master")
                end
            end
            if GulliToolkit and GulliToolkit.Notify then GulliToolkit.Notify("FarmTrack", text) end
        end
    end
end

-- Everything looted this session, the most first: { { id, n } }; gold apart.
function ns.Looted()
    local out = {}
    for id, n in pairs(ns.s.items) do out[#out + 1] = { id = id, n = n } end
    table.sort(out, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.id < b.id end)
    return out
end

function ns.Tracked(kind, id)
    for _, t in ipairs(ns.Targets()) do
        if t.kind == kind and (kind ~= "item" or t.id == id) then return true end
    end
    return false
end

-- Text ------------------------------------------------------------------------------------------

-- "1.2k" for 1234.
function ns.Short(n)
    n = math.floor(n + 0.5)
    if n >= 10000 then return string.format("%dk", math.floor(n / 1000)) end
    if n >= 1000 then return string.format("%.1fk", n / 1000) end
    return tostring(n)
end

function ns.Span(sec)
    sec = math.max(0, math.floor(sec))
    if sec >= 3600 then return L.HM:format(math.floor(sec / 3600), math.floor(sec % 3600 / 60)) end
    return L.M:format(math.max(1, math.floor(sec / 60)))
end

-- Plain money for chat and the hub: "12g 30s".
function ns.Money(c)
    c = math.floor(c or 0)
    local g, s = math.floor(c / 10000), math.floor(c % 10000 / 100)
    if g > 0 then return s > 0 and string.format("%dg %ds", g, s) or string.format("%dg", g) end
    if s > 0 then return string.format("%ds", s) end
    return string.format("%dc", c % 100)
end

function ns.Amount(kind, n)
    if kind == "gold" then return ns.Money(n) end
    return ns.Short(n)
end

-- One line for the hub's home page: the first target.
function ns.Summary()
    local t = ns.s and ns.Targets()[1]
    if not t then return nil end
    local i = ns.Info(t)
    local rate = ns.Amount(t.kind, i.rate)
    if i.goal then
        return L.SUM_GOAL:format(i.name, ns.Amount(t.kind, i.gained), ns.Amount(t.kind, i.goal), rate), i.icon
    end
    return L.SUM:format(i.name, ns.Amount(t.kind, i.gained), rate), i.icon
end

-- Settings -------------------------------------------------------------------------------------

ns.DEFAULTS = { panel = true, locked = true, sales = true, alert = true, alpha = 100, scale = 100 }
ns.OPT_ICON = {
    panel = "Interface\\Icons\\INV_Misc_Spyglass_02",
    locked = "Interface\\Icons\\INV_Misc_Key_04",
    sales = "Interface\\Icons\\INV_Misc_Coin_02",
    alert = "Interface\\Icons\\INV_Misc_Bell_01",
}

function ns.SetPref(key, value)
    ns.db[key] = value
    if ns.Refresh then ns.Refresh() end
end

-- Back to the defaults: settings, place and targets; the session goes on.
function ns.Reset()
    for k in pairs(ns.db) do ns.db[k] = nil end
    for k, v in pairs(ns.DEFAULTS) do ns.db[k] = v end
    if ns.Place then ns.Place() end
    if ns.Refresh then ns.Refresh() end
end

-- /gulli move shows the panel to place it.
ns.moving = false
function ns.Move(on)
    ns.moving = on and true or false
    if ns.Refresh then ns.Refresh() end
end

function ns.Unlocked()
    return ns.moving or ns.db.locked == false
end

-- Slash command ----------------------------------------------------------------------------------

local function say(text) print("|cff9ad0ffFarm Tracker|r " .. text) end

function ns.Slash(msg)
    msg = strtrim(msg or "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "add" then
        local id = tonumber(rest:match("item:(%d+)") or rest:match("^(%d+)"))
        local goal = tonumber(rest:match("|r%s+(%d+)%s*$") or rest:match("^%d+%s+(%d+)%s*$"))
        if not id then say(L.UNKNOWN_ITEM) return end
        if ns.AddTarget("item", id, goal) then say(L.ADDED:format(ns.ItemName(id))) else say(L.FULL:format(ns.MAX_TARGETS)) end
    elseif cmd == "gold" then
        local g = tonumber(rest:match("^(%d+)"))
        if ns.AddTarget("gold", nil, g and g * 10000) then say(L.ADDED:format(L.GOLD)) else say(L.FULL:format(ns.MAX_TARGETS)) end
    elseif cmd == "clear" then
        ns.cdb.targets = {}
        if ns.Refresh then ns.Refresh() end
    elseif cmd == "reset" then
        ns.Start()
        say(L.NEW_SESSION_DONE)
        if ns.Refresh then ns.Refresh() end
    elseif cmd == "help" then
        say(L.HELP)
    else
        ns.Toggle()
    end
end

-- Events ---------------------------------------------------------------------------------------

local BUSY = {
    MERCHANT_SHOW = { "merchant", true }, MERCHANT_CLOSED = { "merchant", false },
    MAIL_SHOW = { "mail", true }, MAIL_CLOSED = { "mail", false },
    BANKFRAME_OPENED = { "bank", true }, BANKFRAME_CLOSED = { "bank", false },
    AUCTION_HOUSE_SHOW = { "auction", true }, AUCTION_HOUSE_CLOSED = { "auction", false },
    TRADE_SHOW = { "trade", true }, TRADE_CLOSED = { "trade", false },
}

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1, a2)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliFarmTrackDB = GulliFarmTrackDB or {}
        GulliFarmTrackCharDB = GulliFarmTrackCharDB or {}
        ns.db, ns.cdb = GulliFarmTrackDB, GulliFarmTrackCharDB
        for k, v in pairs(ns.DEFAULTS) do
            if ns.db[k] == nil then ns.db[k] = v end
        end
        ns.cdb.targets = ns.cdb.targets or {}
        local events = { "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "PLAYER_MONEY", "CURSOR_CHANGED" }
        for e in pairs(BUSY) do events[#events + 1] = e end
        for _, e in ipairs(events) do self:RegisterEvent(e) end
        ns.Resume()
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        -- a1: a real login, which starts a new session; a2: a /reload, which keeps it.
        if a1 and not a2 then ns.Start() else ns.last, ns.lastMoney = ns.CountBags(), money() end
    elseif event == "BAG_UPDATE_DELAYED" or event == "CURSOR_CHANGED" then
        ns.OnBags()
    elseif event == "PLAYER_MONEY" then
        ns.OnMoney()
    elseif BUSY[event] then
        ns.SetBusy(BUSY[event][1], BUSY[event][2])
    end
    if ns.Refresh then ns.Refresh() end
end)

SLASH_GULLIFARMTRACK1 = "/gft"
SLASH_GULLIFARMTRACK2 = "/gullifarm"
SlashCmdList.GULLIFARMTRACK = function(msg) ns.Slash(msg) end

function GulliFarmTrack_Toggle() ns.Toggle() end

if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({
        key = "FarmTrack",
        icon = "Interface\\AddOns\\Gulli-FarmTrack\\icon",
        slash = "/gft",
        open = function() ns.Toggle() end,
        window = function() return ns.Window and ns.Window() end,
        summary = function() return ns.Summary() end,
        move = function(on) ns.Move(on) end,
        reset = function() ns.Reset() end,
        options = {
            { label = L.OPT_PANEL, icon = ns.OPT_ICON.panel, tip = L.OPT_PANEL_TIP,
              get = function() return ns.db ~= nil and ns.db.panel == true end, set = function(v) ns.SetPref("panel", v) end },
            { label = L.OPT_LOCK, icon = ns.OPT_ICON.locked, tip = L.OPT_LOCK_D,
              get = function() return ns.db ~= nil and ns.db.locked == true end, set = function(v) ns.SetPref("locked", v) end },
            { label = L.OPT_SALES, icon = ns.OPT_ICON.sales, tip = L.OPT_SALES_TIP,
              get = function() return ns.db ~= nil and ns.db.sales == true end, set = function(v) ns.SetPref("sales", v) end },
        },
    })
end
