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

-- An item from what the player typed: a link, an item id, or the name of an item in the bags,
-- in this session's loot or known to the client.
function ns.ParseItem(text)
    text = strtrim(text or "")
    if text == "" then return end
    local id = tonumber(text:match("item:(%d+)") or text:match("^#?(%d+)$"))
    if id then return id end
    local want = text:lower()
    local seen = ns.CountBags()
    for i in pairs(ns.s and ns.s.items or {}) do seen[i] = true end
    for i in pairs(seen) do
        local n = CI.GetItemNameByID and CI.GetItemNameByID(i)
        if n and n:lower() == want then return i end
    end
    local info = CI.GetItemInfo or GetItemInfo
    local link = info and select(2, info(text))
    return link and tonumber(link:match("item:(%d+)"))
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
-- A flag is set by the window's show event and cleared by its close event; since a close event can
-- go missing (another addon's frame, a walk away, a loading screen), a flag also ends as soon as the
-- game says that interaction is over, so the counter never stays deaf.
ns.busy = {}
local INTERACTION = { merchant = "Merchant", mail = "MailInfo", bank = "Banker", auction = "Auctioneer",
                      trade = "TradePartner" }
local FRAMES = { merchant = { "MerchantFrame" }, mail = { "MailFrame" }, bank = { "BankFrame" },
                 auction = { "AuctionHouseFrame", "AuctionFrame" }, trade = { "TradeFrame" } }

-- true or false when the game can tell whether the player still uses that window, else nil.
function ns.StillOpen(what)
    local PIM, E = C_PlayerInteractionManager, Enum and Enum.PlayerInteractionType
    local kind = E and E[INTERACTION[what] or ""]
    if PIM and PIM.IsInteractingWithNpcOfType and kind then
        local ok, on = pcall(PIM.IsInteractingWithNpcOfType, kind)
        if ok and on then return true end
    end
    for _, name in ipairs(FRAMES[what] or {}) do
        local fr = _G[name]
        if type(fr) == "table" and fr.IsShown then return fr:IsShown() and true or false end
    end
    if PIM and PIM.IsInteractingWithNpcOfType and kind then return false end
    return nil
end

-- The mailbox and the auction house count only with the mail switch: what comes from there
-- (auction buys, sold or expired auctions, letters) was not farmed.
local MAIL_KINDS = { mail = true, auction = true }
local MAIL_WAIT = 3 -- seconds after a take from a letter in which bag and money changes are the letter's

function ns.Blocks(what)
    return not (MAIL_KINDS[what] and ns.db and ns.db.mail)
end

-- A take from a letter, through any mail window (the game's, Gulli Mail or another addon's).
function ns.MailTake()
    ns.mailAt = now()
end

local function fromMail()
    return ns.mailAt ~= nil and not (ns.db and ns.db.mail) and now() < ns.mailAt + MAIL_WAIT
end

function ns.Busy()
    local any = false
    for what in pairs(ns.busy) do
        -- ns.last followed the bags all along, so only the flag goes.
        if ns.StillOpen(what) == false then ns.busy[what] = nil
        elseif ns.Blocks(what) then any = true end
    end
    return any or fromMail()
end

function ns.SetBusy(what, on)
    ns.busy[what] = on and true or nil
    if not on then
        if ns.Blocks(what) then ns.quietUntil = now() + QUIET end
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
    if fromMail() then return end
    ns.Busy()
    local other = false
    for what in pairs(ns.busy) do if what ~= "merchant" and ns.Blocks(what) then other = true end end
    if not other and (not ns.busy.merchant or ns.db.sales) then
        -- a sale's money is already in the worth of the loot it sold
        if ns.busy.merchant then ns.s.sold = (ns.s.sold or 0) + d end
        ns.Gain("gold", d, t)
    end
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

-- What the session's loot is worth ------------------------------------------------------------
-- An estimate of what everything looted would bring: grey and plain white things at a vendor,
-- trade goods, reagents and recipes at the auction, bind-on-equip blue and purple gear at the
-- auction, green gear disenchanted (with Enchanting, its cheapest result) or sold to a vendor,
-- whichever brings more. Without an auction price an item counts at the vendor's price.

local GEAR = { [2] = true, [4] = true }
local AUCTION = { [5] = true, [7] = true, [9] = true }
ns.QUEST_CLASS = 12

-- Disenchanting green gear: the dust and the lesser essence for its item level (Vanilla tiers).
ns.DE = {
    { 15, 10940, 10938 }, { 20, 10940, 10939 }, { 25, 11083, 10998 }, { 30, 11083, 11082 },
    { 35, 11137, 11134 }, { 40, 11137, 11135 }, { 45, 11176, 11174 }, { 50, 11176, 11175 },
    { 55, 16204, 16202 }, { 999, 16204, 16203 },
}

-- id -> name, quality, item level, sell price, class, bind type; nil until the client knows it.
function ns.ItemFacts(id)
    local info = CI.GetItemInfo or GetItemInfo
    if not info then return end
    local name, _, quality, ilvl, _, _, _, _, _, _, sell, class, _, bind = info(id)
    if not name then return end
    return { quality = quality or 1, ilvl = ilvl or 0, sell = sell or 0, class = class, bind = bind }
end

-- From any price addon (Auctionator, auxForever, Naowh Forever, ...), through the shared reader.
function ns.AuctionPrice(id)
    return ns.Skin and ns.Skin.AuctionPrice and (ns.Skin.AuctionPrice(id)) or nil
end

-- The player knows Enchanting (skill line 333).
function ns.CanDisenchant()
    if not (GetProfessions and GetProfessionInfo) then return false end
    for _, i in ipairs({ GetProfessions() }) do
        if i then
            local _, _, _, _, _, _, line = GetProfessionInfo(i)
            if line == 333 then return true end
        end
    end
    return false
end

-- The cheapest thing disenchanting a green item of this level gives, at the auction.
function ns.DisenchantValue(ilvl)
    for _, t in ipairs(ns.DE) do
        if ilvl <= t[1] then
            local a, b = ns.AuctionPrice(t[2]), ns.AuctionPrice(t[3])
            if a and b then return math.min(a, b) end
            return a or b
        end
    end
end

-- The worth of one item and how it was judged: "vendor", "auction", "disenchant", "quest" (a
-- quest item, worth nothing) or "noprice" (an auction item without a price, at the vendor's);
-- nil, nil while the client has no data for it.
function ns.ItemValue(id, enchanter)
    local f = ns.ItemFacts(id)
    if not f then return nil end
    if f.class == ns.QUEST_CLASS then return 0, "quest" end
    local vendor = f.sell
    if f.quality == 0 then return vendor, "vendor" end
    if AUCTION[f.class] or (GEAR[f.class] and f.quality >= 3 and f.bind == 2) then
        local ah = ns.AuctionPrice(id)
        if ah then return ah, "auction" end
        return vendor, "noprice"
    end
    if GEAR[f.class] and f.quality == 2 and enchanter then
        local de = ns.DisenchantValue(f.ilvl)
        if de and de > vendor then return de, "disenchant" end
    end
    -- An item a vendor pays nothing for that can be traded (a Craftsman's Writ) counts at the
    -- auction; a plain white item a vendor buys stays at the vendor's price.
    if vendor <= 1 and not GEAR[f.class] and f.bind ~= 1 and f.bind ~= 4 then
        local ah = ns.AuctionPrice(id)
        if ah and ah > vendor then return ah, "auction" end
    end
    return vendor, "vendor"
end

-- The items the session looted at their worth. Second value: items the client does not know
-- yet (they count as nothing until it does).
function ns.ItemsWorth()
    local total, unknown = 0, 0
    local enchanter = ns.CanDisenchant()
    for id, n in pairs(ns.s.items) do
        local v = ns.ItemValue(id, enchanter)
        if v then total = total + v * n else unknown = unknown + 1 end
    end
    return total, unknown
end

-- Everything the session looted at its worth, plus the gold looted.
function ns.SessionValue()
    local total, unknown = ns.ItemsWorth()
    return total + ns.s.money - (ns.s.sold or 0), unknown
end

-- How the estimate is made, item by item, for the Session tab: { id, n, unit, total, how }, the
-- most worth first, the items the client does not know yet (how "unknown") last.
function ns.WorthRows()
    local out = {}
    local enchanter = ns.CanDisenchant()
    for id, n in pairs(ns.s.items) do
        local v, how = ns.ItemValue(id, enchanter)
        out[#out + 1] = { id = id, n = n, unit = v, total = v and v * n, how = v and how or "unknown" }
    end
    table.sort(out, function(a, b)
        local x, y = a.total or -1, b.total or -1
        if x ~= y then return x > y end
        if a.n ~= b.n then return a.n > b.n end
        return a.id < b.id
    end)
    return out
end

-- The parts of the estimate: the gold looted (without vendor sales, since what was sold is in
-- the items already), the items by how they were judged, and the sum, which is SessionValue.
function ns.WorthParts()
    local p = { gold = ns.s.money - (ns.s.sold or 0), sold = ns.s.sold or 0, items = 0, unknown = 0,
                by = { vendor = 0, auction = 0, disenchant = 0, noprice = 0, quest = 0 },
                count = { vendor = 0, auction = 0, disenchant = 0, noprice = 0, quest = 0 } }
    for _, r in ipairs(ns.WorthRows()) do
        if r.total then
            p.items = p.items + r.total
            p.by[r.how] = p.by[r.how] + r.total
            p.count[r.how] = p.count[r.how] + r.n
        else
            p.unknown = p.unknown + 1
        end
    end
    p.total = p.gold + p.items
    return p
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

-- The hub's session card: the first item target that gained is a small tile there, and every
-- target a line of the card's tooltip. Gold is the hub's own number, so a gold target gives none;
-- `worth` is what the looted items would bring, which the hub adds to its gold.
function ns.Session()
    if not ns.s then return nil end
    local tile, rows = nil, {}
    for _, t in ipairs(ns.Targets()) do
        local i = ns.Info(t)
        if i.gained > 0 then
            rows[#rows + 1] = { i.name, ns.Amount(t.kind, i.gained) }
            if not tile and t.kind == "item" then tile = { icon = i.icon, value = ns.Short(i.gained), label = i.name } end
        end
    end
    local worth = ns.ItemsWorth()
    if not tile and worth <= 0 then return nil end
    return { tile = tile, worth = worth, tip = tile and { head = L.TITLE, value = "", rows = rows } or nil }
end

-- Settings -------------------------------------------------------------------------------------

ns.DEFAULTS = { panel = false, sales = true, mail = false, alert = true, value = false, alpha = 100, scale = 100 }
ns.OPT_ICON = {
    panel = "Interface\\Icons\\INV_Misc_Spyglass_02",
    sales = "Interface\\Icons\\INV_Misc_Coin_02",
    mail = "Interface\\Icons\\INV_Letter_15",
    alert = "Interface\\Icons\\INV_Misc_Bell_01",
    value = "Interface\\Icons\\INV_Misc_Gem_Pearl_04",
}

function ns.SetPref(key, value)
    ns.db[key] = value
    if ns.Refresh then ns.Refresh() end
end

-- Back to the defaults: settings, place and targets; the session goes on.
function ns.Reset()
    for k in pairs(ns.db) do ns.db[k] = nil end
    for k, v in pairs(ns.DEFAULTS) do ns.db[k] = v end
    ns.db.hudHidden = true
    if ns.Place then ns.Place() end
    if ns.Refresh then ns.Refresh() end
end

-- The hub's Unlock mode shows the panel to place it; the panel has no lock of its own.
ns.moving = false
function ns.Move(on)
    ns.moving = on and true or false
    if ns.Refresh then ns.Refresh() end
end

function ns.Unlocked()
    return ns.moving
end

-- Slash command ----------------------------------------------------------------------------------

local function say(text) print("|cff9ad0ffFarm Tracker|r " .. text) end

function ns.Slash(msg)
    msg = strtrim(msg or "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "add" then
        local goal = tonumber(rest:match("|r%s+(%d+)%s*$") or rest:match("^%d+%s+(%d+)%s*$"))
        local id = tonumber(rest:match("item:(%d+)") or rest:match("^(%d+)")) or ns.ParseItem(rest)
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
    elseif cmd == "debug" then
        local open = {}
        for what in pairs(ns.busy) do open[#open + 1] = what .. "=" .. tostring(ns.StillOpen(what)) end
        local kinds = 0
        for _ in pairs(ns.CountBags()) do kinds = kinds + 1 end
        say(L.DEBUG:format(#open > 0 and table.concat(open, ", ") or "-", kinds, money()))
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
        -- Frames on the screen start hidden: older saves hide the panel once.
        if not ns.db.hudHidden then ns.db.panel, ns.db.hudHidden = false, true end
        ns.db.locked = nil
        ns.cdb.targets = ns.cdb.targets or {}
        local events = { "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT", "BAG_UPDATE_DELAYED", "PLAYER_MONEY", "CURSOR_CHANGED", "LOOT_READY" }
        for e in pairs(BUSY) do events[#events + 1] = e end
        for _, e in ipairs(events) do self:RegisterEvent(e) end
        if hooksecurefunc then
            for _, fn in ipairs({ "TakeInboxItem", "TakeInboxMoney", "AutoLootMailItem" }) do
                if _G[fn] then hooksecurefunc(fn, ns.MailTake) end
            end
        end
        ns.Resume()
        return
    end
    if event == "LOOT_READY" or event == "PLAYER_ENTERING_WORLD" then
        -- Looting or a loading screen: no vendor, mailbox, bank or trade window is in use,
        -- unless the game still says it is open.
        for what in pairs(ns.busy) do
            if event == "PLAYER_ENTERING_WORLD" or ns.StillOpen(what) ~= true then ns.busy[what] = nil end
        end
    end
    if event == "PLAYER_ENTERING_WORLD" then
        -- a1: a real login; a2: a /reload. Only leaving the game ends the session.
        if ns.Skin.NewSession(a1, a2, ns.s.seen) then ns.Start() else ns.last, ns.lastMoney = ns.CountBags(), money() end
    elseif event == "PLAYER_LOGOUT" then
        ns.s.seen = time()
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

-- With the hub: its row and button there; alone: its own minimap button (Skin.lua).
do
    local register = GulliToolkit and GulliToolkit.Register or function(info) ns.alone = info end
    register({
        key = "FarmTrack",
        icon = "Interface\\AddOns\\Gulli-FarmTrack\\icon",
        slash = "/gft",
        open = function() ns.Toggle() end,
        window = function() return ns.Window and ns.Window() end,
        summary = function() return ns.Summary() end,
        session = function() return ns.Session() end,
        move = function(on) ns.Move(on) end,
        frames = { { key = "panel", icon = ns.OPT_ICON.panel,
                     get = function() return ns.db ~= nil and ns.db.panel == true end,
                     set = function(v) ns.SetPref("panel", v) end,
                     frame = function() return ns.PanelFrame and ns.PanelFrame() end } },
        reset = function() ns.Reset() end,
        options = {
            { label = L.OPT_SALES, icon = ns.OPT_ICON.sales, tip = L.OPT_SALES_TIP,
              get = function() return ns.db ~= nil and ns.db.sales == true end, set = function(v) ns.SetPref("sales", v) end },
            { label = L.OPT_MAIL, icon = ns.OPT_ICON.mail, tip = L.OPT_MAIL_TIP,
              get = function() return ns.db ~= nil and ns.db.mail == true end, set = function(v) ns.SetPref("mail", v) end },
            { label = L.OPT_VALUE, icon = ns.OPT_ICON.value, tip = L.OPT_VALUE_TIP,
              get = function() return ns.db ~= nil and ns.db.value == true end, set = function(v) ns.SetPref("value", v) end },
        },
    })
end
