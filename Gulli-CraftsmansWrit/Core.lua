-- Craftsman's Writ: the Craftsman's Writs of WoW Forever. Each writ is a daily quest that asks for one
-- crafted item and pays reputation with the trade camp (75, 125 or 200) and a Coin Pouch. This
-- file tracks what is done today, plans the cheapest way to a standing in a number of days from
-- the bags, the bank and the auction house, buys what the plan needs (one click a step), learns
-- what the pouches pay and where the customers stand, and leads to them. The planner (ns.Plan)
-- is plain Lua; the game calls go through the wrappers at the top.

local ADDON, ns = ...
local L = ns.L

local CALLER = "Gulli-CraftsmansWrit"
local QUOTE_WAIT = 8 -- seconds the auction house has to answer a price request

ns.DEFAULTS = { bank = true, sealed = true, pouch = true, live = true, auto = true, tooltip = true,
                goal = 0, days = 3, writSort = "gain" }

local function say(msg) print("|cff9ad0ffCraftsman's Writ|r: " .. msg) end
local function notify(msg) if GulliToolkit and GulliToolkit.Notify then GulliToolkit.Notify("CraftsmansWrit", msg) end end
ns.Say = say

-- ---------- the rules of the writs ----------

ns.RANKS = { "J", "E", "A" }
ns.REP = { J = 75, E = 125, A = 200 }
-- The Coin Pouch each rank's turn-in gives, and what one holds (Wowhead's average, 2026-11-19)
-- until the pouches opened on this account tell more: the average counts as POUCH_PRIOR pouches.
ns.POUCH = { J = 284584, E = 284585, A = 284586 }
ns.POUCH_AVG = { J = 3490, E = 7507, A = 15179 }
ns.POUCH_PRIOR = 10
local POUCH_RANK = {}
for r, id in pairs(ns.POUCH) do POUCH_RANK[id] = r end
ns.POUCH_RANK = POUCH_RANK
ns.FACTION = { Alliance = 2586, Horde = 2587 }
-- Where each standing starts (absolute reputation), by the game's reaction index.
ns.REACTION_AT = { [4] = 0, [5] = 3000, [6] = 9000, [7] = 21000, [8] = 42000 }
ns.GOALS = { 5, 6, 7, 8 }
ns.DAYS_MAX = 31
local UNIT = 25 -- 75, 125 and 200 are all multiples of 25

-- ---------- game wrappers ----------

local I = C_Item or {}
local Q = C_QuestLog or {}
local MAP = C_Map or {}

local function itemName(id)
    local n = I.GetItemNameByID and I.GetItemNameByID(id)
    if not n and GetItemInfo then n = GetItemInfo(id) end
    return n
end
ns.ItemName = itemName
function ns.ItemIcon(id)
    return (I.GetItemIconByID and I.GetItemIconByID(id)) or (GetItemIcon and GetItemIcon(id))
        or "Interface\\Icons\\INV_Misc_QuestionMark"
end
local function itemCount(id, bank)
    local f = I.GetItemCount or GetItemCount
    return f and (f(id, bank) or 0) or 0
end
-- Asks the client for an item once a minute at most: every request the server answers is a
-- GET_ITEM_INFO_RECEIVED for every addon, and the lists ask for each name they show.
local asked = {}
local function requestItem(id)
    local now = GetTime and GetTime() or 0
    if asked[id] and now - asked[id] < 60 then return end
    asked[id] = now
    if I.RequestLoadItemDataByID then pcall(I.RequestLoadItemDataByID, id) end
end
function ns.DisplayName(id)
    local n = id and itemName(id)
    if n then return n end
    if id then requestItem(id) end
    return L.ITEM_LOADING
end
-- "Craftsman's Writ: Golden Rod" -> "Golden Rod"
function ns.ShortName(name)
    name = name or ""
    return name:match("^[^:：]+[:：]%s*(.+)$") or name
end
-- The writ's name without its prefix: the client's, else the item it asks for.
function ns.WritName(w)
    local n = itemName(w.id)
    if n then return ns.ShortName(n) end
    requestItem(w.id)
    return ns.DisplayName(w.item)
end

local function doneToday(quest)
    if Q.IsQuestFlaggedCompleted then return Q.IsQuestFlaggedCompleted(quest) and true or false end
    return IsQuestFlaggedCompleted and IsQuestFlaggedCompleted(quest) and true or false
end
local function inLog(quest)
    if Q.GetLogIndexForQuestID then return Q.GetLogIndexForQuestID(quest) ~= nil end
    return false
end
ns.InLog = inLog

-- Seconds to the daily reset, or nil.
function ns.ResetIn()
    local D = C_DateAndTime
    if D and D.GetSecondsUntilDailyReset then return D.GetSecondsUntilDailyReset() end
    return GetQuestResetTime and GetQuestResetTime() or nil
end

-- What a writ handed in today says: when it can be handed in again, else "Handed in".
function ns.DoneText()
    local r = ns.ResetIn()
    if r and r > 0 and ns.TimeText then return L.AGAIN_IN:format(ns.TimeText(r)) end
    return L.ST_DONE
end

local function side()
    local f = UnitFactionGroup and UnitFactionGroup("player")
    return f == "Horde" and "H" or (f == "Alliance" and "A" or nil)
end
ns.Side = side

-- The camp's standing: { id, name, reaction, value } (value is absolute reputation), or nil.
function ns.Rep()
    local id = ns.FACTION[UnitFactionGroup and UnitFactionGroup("player") or ""]
    if not id then return nil end
    local R = C_Reputation
    if R and R.GetFactionDataByID then
        local ok, d = pcall(R.GetFactionDataByID, id)
        if ok and type(d) == "table" and d.reaction then
            return { id = id, name = d.name, reaction = d.reaction, value = d.currentStanding or 0 }
        end
    end
    if GetFactionInfoByID then
        local name, _, reaction, _, _, value = GetFactionInfoByID(id)
        if reaction then return { id = id, name = name, reaction = reaction, value = value or 0 } end
    end
    return nil
end

-- What is left to a goal (a reaction index; 0 = the next standing): reputation and the goal.
function ns.Need(rep, goal)
    if not rep then return 0, goal end
    if not goal or goal == 0 then goal = math.min(8, math.max(5, (rep.reaction or 4) + 1)) end
    local at = ns.REACTION_AT[goal] or 0
    return math.max(0, at - (rep.value or 0)), goal
end

-- ---------- the writs ----------

-- A writ by its item id: { id, quest, rank, prof, item, count, side, npc, map, x, y, rep }.
local cacheW = {}
function ns.Writ(id)
    if cacheW[id] then return cacheW[id] end
    local d = ns.WRITS[id]
    if not d then return nil end
    local w = { id = id, quest = d[1], rank = d[2], prof = d[3], item = d[4], count = d[5], side = d[6],
                npc = d[7], map = d[8], x = d[9], y = d[10], rep = ns.REP[d[2]] }
    cacheW[id] = w
    return w
end

local byQuest
function ns.WritOfQuest(quest)
    if not byQuest then
        byQuest = {}
        for id, d in pairs(ns.WRITS) do byQuest[d[1]] = id end
    end
    return byQuest[quest] and ns.Writ(byQuest[quest]) or nil
end
local byItem
-- The writs that ask for an item.
function ns.WritsFor(item)
    if not byItem then
        byItem = {}
        for id, d in pairs(ns.WRITS) do
            byItem[d[4]] = byItem[d[4]] or {}
            table.insert(byItem[d[4]], id)
        end
    end
    local out = {}
    for _, id in ipairs(byItem[item] or {}) do out[#out + 1] = ns.Writ(id) end
    return out
end

-- Every writ this character's side can do, by rank then name of the item id.
local writsOf = {}
function ns.Writs()
    local me = side()
    if writsOf[me or "?"] then return writsOf[me or "?"] end
    local out = {}
    for id in pairs(ns.WRITS) do
        local w = ns.Writ(id)
        if not w.side or not me or w.side == me then out[#out + 1] = w end
    end
    local order = { J = 1, E = 2, A = 3 }
    table.sort(out, function(a, b)
        if a.rank ~= b.rank then return order[a.rank] < order[b.rank] end
        return a.id < b.id
    end)
    writsOf[me or "?"] = out
    return out
end

-- How many of an item: in the bags, and in the bank.
function ns.Stock(id)
    local bags = itemCount(id, false)
    return bags, math.max(0, itemCount(id, true) - bags)
end

-- Where a writ stands now: { w, bags, bank, log, done, have, haveBank, status }. status:
-- done (handed in today), ready (taken or carried, the item is in the bags), item (taken or
-- carried, the item is missing), bank (only in the bank), none.
function ns.StateOf(w)
    local bags, bank = ns.Stock(w.id)
    local have, haveBank = ns.Stock(w.item)
    local s = { w = w, bags = bags, bank = bank, log = inLog(w.quest), done = doneToday(w.quest),
                have = have, haveBank = haveBank }
    if s.done then s.status = "done"
    elseif s.log or bags > 0 then s.status = have >= w.count and "ready" or "item"
    elseif bank > 0 then s.status = "bank"
    else s.status = "none" end
    return s
end

-- What the bags, the bank, the quest log and the prices say is read once and kept until one of
-- them changes (ns.Invalidate from the events), else at most CACHE_TTL seconds: the window, the
-- hub's line and the tooltips ask for it many times a second.
local CACHE_TTL = 30
local cache = { at = 0 }
function ns.Invalidate()
    cache = { at = time and time() or 0 }
end
-- Events come in bursts (a bag change, the quest log, a page of auctions): the window is drawn
-- again once, a moment after the last one.
function ns.RefreshSoon()
    if not (C_Timer and C_Timer.After) then if ns.Refresh then ns.Refresh() end return end
    if ns.refreshQueued then return end
    ns.refreshQueued = true
    C_Timer.After(0.2, function()
        ns.refreshQueued = nil
        if ns.Refresh then ns.Refresh() end
    end)
end
local function cached(key, make)
    local now = time and time() or 0
    if now - cache.at > CACHE_TTL then ns.Invalidate() end
    local v = cache[key]
    if v == nil then v = make(); cache[key] = v end
    return v
end
ns.Cached = cached

function ns.States()
    return cached("states", function()
        local out = {}
        for _, w in ipairs(ns.Writs()) do out[#out + 1] = ns.StateOf(w) end
        return out
    end)
end

-- The Sealed Writs in the bags (and the bank): { [rank] = n }.
function ns.SealedHeld(bank)
    local out = {}
    for id, r in pairs(ns.SEALED) do
        local b, k = ns.Stock(id)
        local n = b + (bank and k or 0)
        if n > 0 then out[r] = (out[r] or 0) + n end
    end
    return out
end
function ns.SealedOf(rank)
    for id, r in pairs(ns.SEALED) do if r == rank then return id end end
end

-- What today looks like: counts for the tiles.
function ns.Today(states)
    states = states or ns.States()
    local t = { done = 0, doneRep = 0, ready = 0, readyRep = 0, item = 0, itemRep = 0 }
    for _, s in ipairs(states) do
        local r = math.floor(s.w.rep * ns.Mult() + 0.5)
        if s.status == "done" then t.done, t.doneRep = t.done + 1, t.doneRep + r
        elseif s.status == "ready" then t.ready, t.readyRep = t.ready + 1, t.readyRep + r
        elseif s.status == "item" then t.item, t.itemRep = t.item + 1, t.itemRep + r end
    end
    local sealed = ns.SealedHeld(false)
    t.sealed = (sealed.J or 0) + (sealed.E or 0) + (sealed.A or 0)
    t.pouchGold = ns.cdb and ns.cdb.pouchDay and ns.cdb.pouchDay.day == ns.DayKey() and ns.cdb.pouchDay.gold or 0
    return t
end

-- A key for the game day: the time of the next reset, rounded to the hour.
function ns.DayKey()
    local left = ns.ResetIn() or 0
    return math.floor((time() + left) / 3600 + 0.5)
end

-- ---------- coin pouches ----------

-- What a rank's pouch holds on average (copper), and how many pouches told it.
function ns.PouchAvg(rank)
    local base = ns.POUCH_AVG[rank] or 0
    local r = ns.db and ns.db.pouches and ns.db.pouches[rank]
    local n, total = r and r.n or 0, r and r.total or 0
    return math.floor((ns.POUCH_PRIOR * base + total) / (ns.POUCH_PRIOR + n) + 0.5), n
end
-- The pouch the plan takes off a writ's cost: 0 when the player turned it off.
function ns.PouchOf(rank)
    if ns.db and ns.db.pouch == false then return 0 end
    return (ns.PouchAvg(rank))
end

-- One opened pouch: notes what it held (an amount far above the average is something else).
function ns.NotePouch(rank, copper)
    if not ns.db or not ns.POUCH_AVG[rank] or not copper or copper <= 0 then return false end
    if copper > 20 * ns.POUCH_AVG[rank] then return false end
    ns.db.pouches = ns.db.pouches or {}
    local r = ns.db.pouches[rank] or { n = 0, total = 0 }
    r.n, r.total = r.n + 1, r.total + copper
    ns.Invalidate()
    r.min, r.max = math.min(r.min or copper, copper), math.max(r.max or copper, copper)
    ns.db.pouches[rank] = r
    if ns.cdb then
        local day = ns.DayKey()
        if not ns.cdb.pouchDay or ns.cdb.pouchDay.day ~= day then ns.cdb.pouchDay = { day = day, gold = 0 } end
        ns.cdb.pouchDay.gold = ns.cdb.pouchDay.gold + copper
    end
    return true
end

-- Opening a pouch opens a loot window with its gold: money that comes in while a loot window
-- is open (and no vendor) and a pouch that leaves the bags within a few seconds go together.
local pouchWatch = { counts = {}, gain = 0, at = 0 }
local POUCH_WAIT = 3
local function pouchCounts()
    local t = {}
    for id in pairs(POUCH_RANK) do t[id] = itemCount(id, false) end
    return t
end
function ns.PouchMoney(delta)
    if delta > 0 and ns.looting and not ns.atVendor then
        pouchWatch.gain, pouchWatch.at = pouchWatch.gain + delta, time()
        ns.PouchCheck()
    end
end
function ns.PouchCheck()
    local now, was = pouchCounts(), pouchWatch.counts
    for id, n in pairs(now) do
        if was[id] and n < was[id] then pouchWatch.left = { rank = POUCH_RANK[id], t = time() } end
    end
    pouchWatch.counts = now
    local left = pouchWatch.left
    if left and pouchWatch.gain > 0 and math.abs(time() - pouchWatch.at) <= POUCH_WAIT
        and math.abs(time() - left.t) <= POUCH_WAIT then
        ns.NotePouch(left.rank, pouchWatch.gain)
        pouchWatch.gain, pouchWatch.left = 0, nil
        if ns.Refresh then ns.Refresh() end
    end
end
function ns.PouchReset() pouchWatch.counts, pouchWatch.gain, pouchWatch.left = pouchCounts(), 0, nil end

-- ---------- the reputation a turn-in really gives ----------
-- The Legacy perk Diplomat adds up to 10%: the gain the game reports after a turn-in, against
-- the writ's base, is kept per character, so the plan counts what the player really gets.

function ns.Mult()
    local m = ns.cdb and ns.cdb.mult
    return (type(m) == "number" and m >= 1 and m <= 1.25) and m or 1
end
local repWas
function ns.NoteRep(value)
    local p = ns.pendingRep
    if p and repWas and value and value > repWas then
        local m = (value - repWas) / p.base
        if m >= 1 and m <= 1.25 and ns.cdb then ns.cdb.mult = math.floor(m * 100 + 0.5) / 100 end
        if p.entry then p.entry.rep = value - repWas end
        ns.pendingRep = nil
    end
    repWas = value
end

-- ---------- where the customers stand ----------

-- A writ's customer spot: the data's, else one learned in the game. { map, x, y, npc, learned }.
function ns.Spot(w)
    if w.map then return { map = w.map, x = w.x, y = w.y, npc = w.npc } end
    local s = ns.db and ns.db.spots and ns.db.spots[w.quest]
    if s and s.map then return { map = s.map, x = s.x, y = s.y, name = s.name, learned = true } end
    return nil
end
function ns.Customer(w)
    local s = ns.Spot(w)
    if not s then return nil end
    return (s.npc and ns.NPCS[s.npc]) or s.name
end
function ns.ZoneName(map)
    local info = map and MAP.GetMapInfo and MAP.GetMapInfo(map)
    return info and info.name or nil
end

local function playerSpot()
    local map = MAP.GetBestMapForUnit and MAP.GetBestMapForUnit("player")
    local pos = map and MAP.GetPlayerMapPosition and MAP.GetPlayerMapPosition(map, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    if not x or x <= 0 then return nil end
    return map, x * 100, y * 100
end
ns.PlayerSpot = playerSpot

-- A writ was taken: the quest's map marker shows where the customer is, until a turn-in tells.
function ns.LearnFromMarker(quest)
    local w = ns.WritOfQuest(quest)
    if not w or w.map or not ns.db or not Q.GetNextWaypoint then return end
    local s = ns.db.spots[quest]
    if s and s.src == "turnin" then return end
    local ok, map, x, y = pcall(Q.GetNextWaypoint, quest)
    if ok and map and x and x > 0 then ns.db.spots[quest] = { map = map, x = x * 100, y = y * 100, src = "marker" } end
end
-- A writ was handed in: the player stands at the customer.
function ns.LearnFromTurnIn(quest)
    local w = ns.WritOfQuest(quest)
    if not w or w.map or not ns.db then return end
    local map, x, y = playerSpot()
    if not map then return end
    local name
    local ok, n = pcall(UnitName, "npc")
    if ok and type(n) == "string" and not (issecretvalue and issecretvalue(n)) then name = n end
    ns.db.spots[quest] = { map = map, x = math.floor(x * 10 + 0.5) / 10, y = math.floor(y * 10 + 0.5) / 10,
                           name = name, src = "turnin" }
end

-- ---------- other characters ----------
-- Each character's writs and the items writs ask for (bags and bank), for the tooltips and the
-- list: db.chars[Name-Realm] = { side, class, at, writs = { id = n }, items = { id = n } }.

local function charKey()
    local name = UnitName and UnitName("player") or "?"
    local r = GetRealmName and GetRealmName()
    if type(r) == "string" and r ~= "" then
        if ns.db then ns.db.realm = r end
    else
        r = ns.db and ns.db.realm
        if not r and ns.db then
            for key in pairs(ns.db.chars or {}) do
                local n, kr = key:match("^(.-)%-(.+)$")
                if n == name then
                    if r and r ~= kr then r = nil; break end
                    r = kr
                end
            end
        end
    end
    return name .. "-" .. (r or "")
end
ns.CharKey = charKey

-- An entry saved as "Name-" (an empty realm) joins the realm one on load.
function ns.MergeRealmless()
    if not ns.db then return end
    local key = charKey()
    local name = key:match("^(.-)%-")
    local stray = ns.db.chars[name .. "-"]
    if stray and key ~= name .. "-" then
        if not ns.db.chars[key] then ns.db.chars[key] = stray end
        ns.db.chars[name .. "-"] = nil
    end
    for _, key2 in ipairs({ "lots" }) do
        local t = ns.db[key2]
        if t and t[name .. "-"] and key ~= name .. "-" then
            t[key] = t[key] or {}
            for id, list in pairs(t[name .. "-"]) do
                t[key][id] = t[key][id] or {}
                for _, lot in ipairs(list) do table.insert(t[key][id], lot) end
            end
            t[name .. "-"] = nil
        end
    end
end

function ns.Snapshot()
    if not ns.db then return end
    local key = charKey()
    if key:sub(-1) == "-" then return end -- no realm known yet: nothing is saved under "Name-"
    local writs, items = {}, {}
    for id in pairs(ns.WRITS) do
        local n = itemCount(id, true)
        if n > 0 then writs[id] = n end
        local w = ns.Writ(id)
        local k = itemCount(w.item, true)
        if k > 0 then items[w.item] = k end
    end
    local _, class = UnitClass("player")
    ns.db.chars[key] = { side = side(), class = class, at = time(), writs = writs, items = items }
end

-- Looting sends a bag update per item: the snapshot (300 counts with the bank) waits for the
-- bags to be still a few seconds.
function ns.SnapshotSoon()
    if not (C_Timer and C_Timer.After) then return ns.Snapshot() end
    if ns.snapQueued then return end
    ns.snapQueued = true
    C_Timer.After(5, function() ns.snapQueued = nil; ns.Snapshot() end)
end

-- Other characters of this side that hold an item (a writ or an item a writ asks for).
function ns.AltCounts(id)
    local me, mine, out = charKey(), side(), {}
    for key, c in pairs(ns.db and ns.db.chars or {}) do
        if key ~= me and key:sub(-1) ~= "-" and (not mine or c.side == mine) then
            local n = (c.writs and c.writs[id]) or (c.items and c.items[id]) or 0
            if n > 0 then out[#out + 1] = { name = key:match("^(.-)%-") or key, class = c.class, n = n } end
        end
    end
    table.sort(out, function(a, b) return a.n > b.n end)
    return out
end

-- ---------- auction prices ----------

function ns.HasPrices() return ns.Skin and ns.Skin.HasPrices and ns.Skin.HasPrices() or false end
function ns.AuctionPrice(id)
    if not id then return nil end
    local prices = cached("prices", function() return {} end)
    local p = prices[id]
    if p == nil then
        p = ns.Skin and ns.Skin.AuctionPrice and (ns.Skin.AuctionPrice(id)) or false
        prices[id] = p
    end
    return p or nil
end

ns.LOTS_FRESH = 10 * 60
ns.lots = {} -- item id -> { t = time read, l = { { unit price, count } } cheapest first }
ns.flat = {} -- the items the last plan priced from a price addon's lowest price

-- Mean unit price of n units after the first skip ones from lots (cheapest first), or nil.
function ns.LadderPrice(lots, n, skip)
    n, skip = n or 1, skip or 0
    local cost, pos, got = 0, 0, 0
    for _, l in ipairs(lots or {}) do
        local from, to = math.max(pos, skip), math.min(pos + l[2], skip + n)
        if to > from then cost, got = cost + (to - from) * l[1], got + (to - from) end
        pos = pos + l[2]
        if got >= n then break end
    end
    if n <= 0 or got < n then return nil end
    return cost / n
end

-- The price the plan uses: mean unit price of n units after skip ones, from the lots read here
-- or else the lowest price a price addon knows (the plan is then an estimate).
function ns.Price(id, n, skip)
    local lots = ns.atAH and ns.lots[id]
    if lots and time() - lots.t <= ns.LOTS_FRESH then return ns.LadderPrice(lots.l, n, skip) end
    local unit = ns.AuctionPrice(id)
    if unit then ns.flat[id] = true end
    return unit
end

-- What one turn-in of a writ costs now: { writ, item, pouch, total } (copper; nil parts are not
-- for sale), counting what the bags and the bank hold as free.
function ns.CostOf(w, useBank)
    local costs = cached(useBank and "costsBank" or "costs", function() return {} end)
    if costs[w.id] then return costs[w.id] end
    local c = ns.CostNow(w, useBank)
    costs[w.id] = c
    return c
end
function ns.CostNow(w, useBank)
    local bags, bank = ns.Stock(w.id)
    local own = bags + (useBank and bank or 0)
    local have, haveBank = ns.Stock(w.item)
    local items = have + (useBank and haveBank or 0)
    local c = { pouch = ns.PouchOf(w.rank) }
    c.writ = own > 0 and 0 or ns.Price(w.id, 1, 0)
    local need = math.max(0, w.count - items)
    c.item = need == 0 and 0 or (ns.Price(w.item, need, 0) and math.floor(ns.Price(w.item, need, 0) * need + 0.5))
    if c.writ and c.item then c.total = c.writ + c.item - c.pouch end
    local function fresh(id) local l = ns.atAH and ns.lots[id]; return l and time() - l.t <= ns.LOTS_FRESH end
    c.estimate = (c.writ ~= 0 and not fresh(w.id)) or (need > 0 and not fresh(w.item)) or false
    return c
end

-- What handing in a writ the character holds costs from here: the item still to buy (bags and
-- bank count as owned, so does the writ) less its pouch. A negative total is gold won.
function ns.CloseCost(s)
    if s.status == "done" or s.status == "none" then return nil end
    return ns.CostOf(s.w, true)
end

-- Asks the client for every writ and item name of this side once, so the lists show names
-- instead of "..." when the window opens; GET_ITEM_INFO_RECEIVED repaints it.
-- The requests go out PREFETCH_STEP at a time, so the answers do not come in one burst.
local PREFETCH_STEP = 25
function ns.Prefetch()
    if ns.prefetching then return end
    local ids = {}
    for _, w in ipairs(ns.Writs()) do ids[#ids + 1] = w.id; ids[#ids + 1] = w.item end
    for id in pairs(ns.SEALED) do ids[#ids + 1] = id end
    for _, id in pairs(ns.POUCH) do ids[#ids + 1] = id end
    local i = 1
    local function step()
        local n = 0
        while i <= #ids and n < PREFETCH_STEP do
            local id = ids[i]
            i = i + 1
            if not itemName(id) then requestItem(id); n = n + 1 end
        end
        if i <= #ids and C_Timer and C_Timer.After then C_Timer.After(0.1, step)
        elseif i <= #ids then return step()
        else ns.prefetching = nil end
    end
    ns.prefetching = true
    step()
end

-- ---------- the plan (no game calls) ----------
-- Every writ type gets the cost of its 1st, 2nd, ... copy, one a day: the writ from the bags and
-- the bank first, else the auction house (the k-th copy pays the k-th cheapest lot), the item it
-- asks for the same way, less the pouch the turn-in gives. A Sealed Writ is a type too: its
-- envelope plus the mean item cost of its rank, less the pouch, marked an estimate since what is
-- inside is random. A knapsack over the reputation (in steps of 25) picks the copies that reach
-- the goal for the least gold; a copy that pays more than it costs is always taken. Copy k of a
-- writ goes to day k (to day k + 1 when it was handed in today already).
--
-- input: { need = reputation, days = n, mult = 1.05, writs = { { id, rank, rep, item, count,
--   own = writs held, done = handed in today } }, sealed = { { id, rank, own = held } },
--   price = function(id, n, skip) mean unit price or nil, stock = function(item) -> held,
--   pouch = function(rank) -> copper, tick = optional function(share 0..1) called in the long loops,
--   which lets a job give the frame back }
-- returns { lines = { { kind = "writ"|"sealed", id, w, k, day, writ, item, pouch, cost,
--   writFrom = "own"|"ah", itemFrom = "own"|"ah", estimate } }, total, buy, pouch, rep, short,
--   byDay = { [d] = { n, rep, cost } }, profit = n }

function ns.Plan(input)
    local days = math.max(1, math.min(ns.DAYS_MAX, input.days or 1))
    local mult = input.mult or 1
    local U = math.max(0, math.ceil((input.need or 0) / mult / UNIT))
    local result = { lines = {}, total = 0, buy = 0, pouch = 0, rep = 0, short = 0, byDay = {}, profit = 0 }
    if U == 0 then return result end
    local price, stock, pouch = input.price, input.stock, input.pouch or function() return 0 end

    -- one pool of the items the bags hold, shared by the writ types as they are settled
    local function pool()
        local p, bought = {}, {}
        local function take(id, n)
            if p[id] == nil then p[id] = stock(id) or 0 end
            local own = math.min(n, p[id])
            local need = n - own
            -- (never `need > 0 and price() or 0`: an item sold out would come out free)
            local unit = 0
            if need > 0 then
                unit = price(id, need, bought[id] or 0)
                if not unit then return nil end
            end
            p[id] = p[id] - own
            bought[id] = (bought[id] or 0) + need
            return math.floor(need * unit + 0.5), own == n, need
        end
        return take
    end

    local tick = input.tick or function() end
    local nWrits = math.max(1, #(input.writs or {}))
    local types = {}
    for wi, w in ipairs(input.writs or {}) do
        local take = pool()
        local cap = days - (w.done and 1 or 0)
        local own, got, steps = w.own or 0, 0, {}
        for k = 1, cap do
            local wc, wfrom
            if own > 0 then wc, wfrom, own = 0, "own", own - 1
            else
                local unit = price(w.id, 1, got)
                if not unit then break end
                wc, wfrom, got = math.floor(unit + 0.5), "ah", got + 1
            end
            local ic, mine, need = take(w.item, w.count)
            if not ic then break end
            local p = pouch(w.rank)
            steps[#steps + 1] = { k = k, day = k + (w.done and 1 or 0), writ = wc, item = ic, pouch = p,
                                  cost = wc + ic - p, writFrom = wfrom, itemFrom = mine and "own" or "ah", itemN = need }
        end
        if #steps > 0 then
            types[#types + 1] = { kind = "writ", id = w.id, w = w, u = math.floor(w.rep / UNIT), steps = steps }
        end
        tick(0.25 * wi / nWrits)
    end
    -- the mean item cost of a rank, over the writs of that rank with a price
    local mean = {}
    for _, w in ipairs(input.writs or {}) do
        local unit = price(w.item, w.count, 0)
        local m = mean[w.rank] or { n = 0, sum = 0, all = 0 }
        m.all = m.all + 1
        if unit then m.n, m.sum = m.n + 1, m.sum + unit * w.count end
        mean[w.rank] = m
    end
    for _, s in ipairs(input.sealed or {}) do
        local m = mean[s.rank]
        if m and m.n > 0 and m.n * 2 >= m.all then
            local itemMean = math.floor(m.sum / m.n + 0.5)
            local rep = ns.REP[s.rank]
            local steps, own, got = {}, s.own or 0, 0
            for k = 1, math.ceil(U * UNIT / rep) do
                local wc, wfrom
                if own > 0 then wc, wfrom, own = 0, "own", own - 1
                else
                    local unit = price(s.id, 1, got)
                    if not unit then break end
                    wc, wfrom, got = math.floor(unit + 0.5), "ah", got + 1
                end
                local p = pouch(s.rank)
                steps[#steps + 1] = { k = k, day = 1, writ = wc, item = itemMean, pouch = p, cost = wc + itemMean - p,
                                      writFrom = wfrom, itemFrom = "ah", estimate = true }
            end
            if #steps > 0 then
                types[#types + 1] = { kind = "sealed", id = s.id, rank = s.rank, u = math.floor(rep / UNIT), steps = steps }
            end
        end
    end

    -- knapsack: dp[x] = least gold for at least x units (x capped at U)
    local INF = math.huge
    local dp, picks = { [0] = 0 }, {}
    for x = 1, U do dp[x] = INF end
    for t, ty in ipairs(types) do
        local nd, np = {}, {}
        for x = 0, U do nd[x], np[x] = dp[x], 0 end
        for x = 0, U do
            if x % 64 == 0 then tick() end
            if dp[x] < INF then
                local sum = 0
                for k, st in ipairs(ty.steps) do
                    sum = sum + st.cost
                    local y = math.min(U, x + k * ty.u)
                    if dp[x] + sum < nd[y] then nd[y], np[y] = dp[x] + sum, k * 1000000 + x end
                end
            end
        end
        dp, picks[t] = nd, np
        tick(0.3 + 0.7 * t / #types)
    end
    -- the best reachable: the goal, else the most units the priced copies give
    local best = U
    if dp[U] == INF then
        best = 0
        for x = U, 0, -1 do if dp[x] < INF then best = x; break end end
        result.short = (U - best) * UNIT
    end
    local count = {}
    local x = best
    for t = #types, 1, -1 do
        local v = picks[t][x] or 0
        local k = math.floor(v / 1000000)
        if k > 0 then count[t] = k; x = v % 1000000 end
    end
    for t, ty in ipairs(types) do
        for k = 1, count[t] or 0 do
            local st = ty.steps[k]
            local line = { kind = ty.kind, id = ty.id, w = ty.w, rank = ty.w and ty.w.rank or ty.rank, k = k,
                           day = st.day, writ = st.writ, item = st.item, pouch = st.pouch, cost = st.cost,
                           writFrom = st.writFrom, itemFrom = st.itemFrom, itemN = st.itemN, estimate = st.estimate,
                           rep = math.floor(ty.u * UNIT * mult + 0.5) }
            result.lines[#result.lines + 1] = line
            result.total = result.total + st.cost
            result.buy = result.buy + st.writ + st.item
            result.pouch = result.pouch + st.pouch
            result.rep = result.rep + line.rep
            if st.cost < 0 then result.profit = result.profit + 1 end
            if st.estimate then result.estimate = true end
            local d = result.byDay[st.day] or { n = 0, rep = 0, cost = 0 }
            d.n, d.rep, d.cost = d.n + 1, d.rep + line.rep, d.cost + st.cost
            result.byDay[st.day] = d
        end
    end
    table.sort(result.lines, function(a, b)
        if a.day ~= b.day then return a.day < b.day end
        if (a.writFrom == "own") ~= (b.writFrom == "own") then return a.writFrom == "own" end
        if a.cost ~= b.cost then return a.cost < b.cost end
        return a.id < b.id
    end)
    return result
end

-- What a plan buys at the auction house, one line per item: { { id, n, unit, cost } }.
function ns.ShoppingList(plan)
    local out, at = {}, {}
    local function add(id, n, cost)
        if n <= 0 then return end
        local line = at[id]
        if not line then
            line = { id = id, n = 0, cost = 0 }
            at[id] = line
            out[#out + 1] = line
        end
        line.n, line.cost = line.n + n, line.cost + cost
        line.unit = line.cost / line.n
    end
    for _, l in ipairs(plan and plan.lines or {}) do
        if l.writFrom == "ah" then add(l.id, 1, l.writ) end
        if l.kind == "writ" and (l.itemN or 0) > 0 then add(l.w.item, l.itemN, l.item) end
    end
    return out
end

-- The ways to earn 100 reputation, cheapest first, for the comparison card: { { key, cost } }.
function ns.Ways(plan)
    local sum = {}
    for _, l in ipairs(plan and plan.lines or {}) do
        local key = (l.kind == "sealed" and "SEALED_" or "WRIT_") .. l.rank
        local s = sum[key] or { cost = 0, rep = 0, estimate = l.kind == "sealed" }
        s.cost, s.rep = s.cost + l.cost, s.rep + l.rep
        sum[key] = s
    end
    local out = {}
    for key, s in pairs(sum) do
        if s.rep > 0 then out[#out + 1] = { key = key, cost = math.floor(s.cost * 100 / s.rep + 0.5), estimate = s.estimate } end
    end
    table.sort(out, function(a, b) return a.cost < b.cost end)
    return out
end

-- The planner's input from the game now.
function ns.PlanInput()
    local useBank = ns.db.bank
    local writs = {}
    for _, w in ipairs(ns.Writs()) do
        local bags, bank = ns.Stock(w.id)
        local own = bags + (useBank and bank or 0)
        if inLog(w.quest) then own = own + 1 end -- a taken writ needs no writ item
        writs[#writs + 1] = { id = w.id, rank = w.rank, rep = w.rep, item = w.item, count = w.count,
                              own = own, done = doneToday(w.quest), w = w }
    end
    local sealed = {}
    if ns.db.sealed then
        local held = ns.SealedHeld(useBank)
        for _, r in ipairs(ns.RANKS) do
            sealed[#sealed + 1] = { id = ns.SealedOf(r), rank = r, own = held[r] or 0 }
        end
    end
    local need, goal = ns.Need(ns.Rep(), ns.db.goal)
    return { need = need, goal = goal, days = ns.db.days, mult = ns.Mult(), writs = writs, sealed = sealed,
             price = ns.Price, pouch = ns.PouchOf,
             stock = function(id) local b, k = ns.Stock(id); return b + (useBank and k or 0) end }
end

-- The writs in Plan.lines keep their own w; give them back the full writ.
local function fixLines(plan, input)
    local byId = {}
    for _, w in ipairs(input.writs) do byId[w.id] = w.w end
    for _, l in ipairs(plan.lines) do if l.kind == "writ" then l.w = byId[l.id] or l.w end end
end

ns.plan = nil
ns.tried = {}
local live, busy, cancelQuote, canSearch

-- Calculate (and Recalculate) plans the whole way anew from what the bags and the bank hold now.
-- At the auction house it reads again every lot the plan buys, so what is sold out or dearer now
-- shows; away from it the plan takes the price addon's prices and checks nothing on sale.
--
-- A plan of many days and a far goal is a long knapsack, so it runs as a job over several frames
-- (S.Job) with a progress bar; the window keeps the last plan meanwhile. Returns the plan when it
-- was done at once (no frame clock, as in the tests), else nil: the plan comes a few frames later.
ns.perf = {}
local JOB = "CraftsmansWritPlan"
function ns.Calculating()
    local S = ns.Skin
    if not (S and S.JobRunning) then return false, 0 end
    return S.JobRunning(JOB)
end
function ns.Calculate(round)
    if not ns.db or ns.paused then return end
    if not round then
        if busy() then cancelQuote() end
        if ns.atAH and ns.db.live and canSearch() then ns.lots = {}; ns.StopScan() end
    end
    round = round or 1
    if round == 1 then ns.flat, ns.tried = {}, {} end
    ns.Invalidate()
    local S = ns.Skin
    local t0 = debugprofilestop and debugprofilestop()
    local function work()
        local input = ns.PlanInput()
        -- each price once: the knapsack asks for the same copies again and again
        local memo, price = {}, input.price
        input.price = function(id, n, skip)
            local key = id .. ":" .. n .. ":" .. skip
            local v = memo[key]
            if v == nil then v = price(id, n, skip) or false; memo[key] = v end
            return v or nil
        end
        input.tick = S and S.JobTick
        return { input = input, plan = ns.Plan(input) }
    end
    local result
    local function done(r)
        local input, plan = r.input, r.plan
        fixLines(plan, input)
        for id in pairs(ns.flat) do
            local lots = ns.atAH and ns.lots[id]
            if not lots or time() - lots.t > ns.LOTS_FRESH then plan.estimate = true; break end
        end
        plan.goal, plan.need, plan.days = input.goal, input.need, input.days
        ns.plan, ns.stale = plan, nil
        if t0 and debugprofilestop then ns.perf.calc = debugprofilestop() - t0 end
        ns.ResetBuy()
        result = plan
        if live then live(round) end
        if ns.Refresh then ns.Refresh() end
    end
    if S and S.Job then
        S.Job(JOB, work, done, function() if ns.Refresh then ns.Refresh() end end)
    else
        done(work())
    end
    if not result and ns.Refresh then ns.Refresh() end
    return result
end

-- A change of the goal or the days marks the plan outdated; Calculate plans anew.
function ns.SetPref(key, value)
    if not ns.db then return end
    ns.db[key] = value
    ns.Invalidate()
    if ns.plan then ns.stale = true end
    if ns.Refresh then ns.Refresh() end
end

-- ---------- reading the lots at the auction house ----------

local SEARCH_WAIT, SEARCH_GAP, LIVE_ROUNDS = 5, 0.3, 4
local scan = { queue = {}, busy = nil, n = 0, done = 0 }
ns.scan = scan

canSearch = function()
    local a = C_AuctionHouse
    return a and a.SendSearchQuery and a.MakeItemKey and true or false
end
ns.CanSearch = canSearch

local function readLots(id)
    local a, lots = C_AuctionHouse, {}
    if a.GetNumCommoditySearchResults then
        for i = 1, a.GetNumCommoditySearchResults(id) or 0 do
            local r = a.GetCommoditySearchResultInfo(id, i)
            if r and r.unitPrice and (r.quantity or 0) > 0 then lots[#lots + 1] = { r.unitPrice, r.quantity } end
        end
    end
    if #lots == 0 and a.GetNumItemSearchResults and a.GetItemSearchResultInfo then
        local key = a.MakeItemKey(id)
        for i = 1, a.GetNumItemSearchResults(key) or 0 do
            local r = a.GetItemSearchResultInfo(key, i)
            if r and r.buyoutAmount and r.buyoutAmount > 0 and not r.containsOwnerItem then
                -- an item result is one price for `quantity` items, buyoutAmount is the price of one
                lots[#lots + 1] = { r.buyoutAmount, math.max(1, r.quantity or 1) }
            end
        end
    end
    table.sort(lots, function(x, y) return x[1] < y[1] end)
    return lots
end

local nextSearch
nextSearch = function()
    local id = table.remove(scan.queue, 1)
    scan.busy = id
    if not id or not ns.atAH then
        scan.busy, scan.queue = nil, {}
        local after = scan.after
        scan.after = nil
        ns.Invalidate()
        if after and ns.atAH then after() elseif ns.Refresh then ns.Refresh() end
        return
    end
    local a = C_AuctionHouse
    if not pcall(a.SendSearchQuery, a.MakeItemKey(id), {}, false) then
        scan.done = scan.done + 1
        return nextSearch()
    end
    C_Timer.After(SEARCH_WAIT, function()
        if scan.busy == id then scan.done = scan.done + 1; nextSearch() end
    end)
    ns.RefreshSoon()
end

function ns.OnSearch(arg)
    local id = scan.busy
    if not id then return end
    local got = type(arg) == "table" and arg.itemID or arg
    if got ~= nil and got ~= id then return end -- the player's own search
    ns.lots[id] = { t = time(), l = readLots(id) }
    ns.Invalidate()
    scan.done = scan.done + 1
    C_Timer.After(SEARCH_GAP, function() if scan.busy == id then nextSearch() end end)
end

function ns.ScanLots(ids, after)
    if not ns.atAH or not canSearch() or #ids == 0 then return 0 end
    for _, id in ipairs(ids) do scan.queue[#scan.queue + 1] = id end
    scan.n = scan.busy and scan.n + #ids or #ids
    if not scan.busy then scan.done = 0 end
    scan.after = after
    if not scan.busy then nextSearch() end
    return #ids
end
function ns.StopScan() scan.queue, scan.busy, scan.after, scan.n, scan.done = {}, nil, nil, 0, 0 end
function ns.Scanning() return scan.busy ~= nil end

live = function(round)
    if not ns.db.live or not ns.atAH or not canSearch() or round > LIVE_ROUNDS then return end
    local ids = {}
    for _, line in ipairs(ns.ShoppingList(ns.plan)) do
        if ns.flat[line.id] and not ns.tried[line.id] then
            ns.tried[line.id] = true
            ids[#ids + 1] = line.id
        end
    end
    ns.ScanLots(ids, function()
        if ns.Busy() then return end
        ns.Calculate(round + 1)
    end)
end

-- ---------- buying at the auction house ----------
-- The plan is bought step by step, one writ type a step: its writs, then the item it asks for.
-- What the bags and the bank hold counts as done from the start. The game runs the purchase
-- calls only inside a click, and asking a commodity's price is protected too, so a commodity
-- takes two clicks (the price, then all units of the step at once). An item that is no commodity
-- (gear, the writs themselves) is one auction per unit: the first click finds the cheapest lot,
-- each further click buys one, and the next lot comes from the same results, without the auction
-- just bought. An item the client does not know yet is tried as a commodity first and, when the
-- auction house has no commodity of it, searched as an item at once. Never call the purchase
-- calls from an event or a timer.

ns.buy = { queue = {}, steps = {}, i = 1, phase = "done", bought = 0, spent = 0 }
ns.pending = {} -- auction id -> line: item purchases sent and not confirmed yet

local function AH() return C_AuctionHouse end
function ns.CanBuy()
    local a = AH()
    return a and a.StartCommoditiesPurchase and a.ConfirmCommoditiesPurchase and true or false
end
cancelQuote = function()
    local a = AH()
    if ns.buy.phase == "ready" and ns.buy.quote and not ns.buy.quote.auction and a and a.CancelCommoditiesPurchase then
        pcall(a.CancelCommoditiesPurchase)
    end
end
local function ready()
    local a = AH()
    return not (a and a.IsThrottledMessageSystemReady) or a.IsThrottledMessageSystemReady() and true or false
end

-- The plan as buying steps, one a writ type in the plan's order: { kind, id, w, rank, copies,
-- writOwn, itemOwn, writ = { id, n, got, cost }, item = { id, n, got, cost, copies } }.
-- n is what the auction house sells the step, got what was bought of it here.
function ns.BuySteps(plan)
    local steps, at = {}, {}
    for _, l in ipairs(plan and plan.lines or {}) do
        local key = l.kind .. ":" .. l.id
        local s = at[key]
        if not s then
            s = { kind = l.kind, id = l.id, w = l.w, rank = l.rank, copies = 0, writOwn = 0, itemOwn = 0,
                  writ = { id = l.id, n = 0, got = 0, cost = 0, part = "writ" } }
            if l.kind == "writ" then s.item = { id = l.w.item, n = 0, got = 0, cost = 0, copies = 0, part = "item" } end
            s.writ.step = s
            if s.item then s.item.step = s end
            at[key] = s
            steps[#steps + 1] = s
        end
        s.copies = s.copies + 1
        if l.writFrom == "ah" then s.writ.n, s.writ.cost = s.writ.n + 1, s.writ.cost + l.writ
        else s.writOwn = s.writOwn + 1 end
        if s.item then
            if (l.itemN or 0) > 0 then
                s.item.n, s.item.cost, s.item.copies = s.item.n + l.itemN, s.item.cost + l.item, s.item.copies + 1
            else s.itemOwn = s.itemOwn + 1 end
        end
    end
    for _, s in ipairs(steps) do
        for _, line in ipairs({ s.writ, s.item }) do
            if line.n > 0 then line.unit = line.cost / line.n end
        end
    end
    return steps
end

-- How far a step is: { writ = { done, of }, item = { done, of } } in copies (one node a day).
function ns.StepNodes(s)
    local out = { writ = { done = math.min(s.copies, s.writOwn + s.writ.got), of = s.copies } }
    if s.item then
        local bought = s.item.n > 0 and math.floor(s.item.got * s.item.copies / s.item.n) or 0
        out.item = { done = math.min(s.copies, s.itemOwn + bought), of = s.copies }
    end
    return out
end

-- The step a line belongs to and its place: step index, steps.
function ns.StepOf(line)
    if not line then return nil end
    for i, s in ipairs(ns.buy.steps) do if s == line.step then return i, #ns.buy.steps end end
end

local function left(line) return line and (line.n - line.got) or 0 end
ns.Left = left

function ns.ResetBuy()
    local b = ns.buy
    cancelQuote()
    b.steps = ns.BuySteps(ns.plan)
    b.queue = {}
    for _, s in ipairs(b.steps) do
        if s.writ.n > 0 then b.queue[#b.queue + 1] = s.writ end
        if s.item and s.item.n > 0 then b.queue[#b.queue + 1] = s.item end
    end
    b.i, b.quote, b.err, b.spent, b.bought, b.token = 1, nil, nil, 0, 0, nil
    b.phase = #b.queue > 0 and "idle" or "done"
end
function ns.Current() return ns.buy.queue[ns.buy.i] end

busy = function()
    local p = ns.buy.phase
    return p == "quote" or p == "ready" or p == "buying"
end
ns.Busy = busy

function ns.Dear()
    local b, line = ns.buy, ns.Current()
    if b.phase ~= "ready" or not b.quote or not line or not line.unit or line.unit <= 0 then return false end
    return b.quote.unit > line.unit * 1.5
end

local function nextLine()
    local b = ns.buy
    b.i, b.quote = b.i + 1, nil
    if ns.Current() then b.phase = "idle" else
        b.phase = "done"
        say(L.ALL_BOUGHT:format(b.bought, ns.Money(b.spent)))
        notify(L.ALL_BOUGHT:format(b.bought, ns.Money(b.spent)))
    end
end

-- "c" a commodity, "i" an item sold one auction at a time, nil while the client does not know.
local function modeOf(line)
    if line.mode then return line.mode end
    local a = AH()
    if a and a.GetItemCommodityStatus then
        local ok, status = pcall(a.GetItemCommodityStatus, line.id)
        if ok and status == 1 then line.mode = "i" elseif ok and status == 2 then line.mode = "c" end
    end
    if not line.mode and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, line.id) end
    return line.mode
end
ns.ModeOf = modeOf

local function canBuyItems()
    local a = AH()
    return a and a.MakeItemKey and a.SendSearchQuery and a.GetNumItemSearchResults and a.GetItemSearchResultInfo
        and a.PlaceBid and true or false
end

-- The cheapest auction of the line's item with a buyout that is not the player's own and was not
-- bought or refused already (line.gone). An item result is one price for `quantity` items;
-- PlaceBid with that buyout buys one of them.
function ns.ItemQuote(line)
    local a = AH()
    if not line or not line.key or not canBuyItems() then return nil end
    local best
    local ok, num = pcall(a.GetNumItemSearchResults, line.key)
    for i = 1, ok and tonumber(num) or 0 do
        local okr, r = pcall(a.GetItemSearchResultInfo, line.key, i)
        if okr and type(r) == "table" and r.auctionID and (r.buyoutAmount or 0) > 0 and not r.containsOwnerItem
            and not (line.gone and line.gone[r.auctionID]) then
            if not best or r.buyoutAmount < best.total then
                best = { auction = r.auctionID, total = r.buyoutAmount, unit = r.buyoutAmount, n = 1 }
            end
        end
    end
    return best
end

local function fullResults(line)
    local a = AH()
    if not (a and a.HasFullItemSearchResults) then return true end
    local ok, full = pcall(a.HasFullItemSearchResults, line.key)
    return not ok or full
end

local function wait()
    local b, token = ns.buy, {}
    b.token = token
    C_Timer.After(QUOTE_WAIT, function()
        if b.token == token and (b.phase == "quote" or b.phase == "buying") then
            b.phase, b.err = "idle", "ERR_NO_ANSWER"
            if ns.Refresh then ns.Refresh() end
        end
    end)
end

-- An item line: the next lot from the results the client holds, else a new search.
local function askItem(line)
    local b = ns.buy
    if not canBuyItems() then b.phase, b.err = "idle", "ERR_HAND"; return end
    line.mode = "i"
    if not line.key then
        local ok, key = pcall(AH().MakeItemKey, line.id)
        line.key = ok and key or nil
    end
    -- the first unit searches for today's lots; the next ones come from those results
    local q = line.searched and ns.ItemQuote(line)
    if q then b.phase, b.quote = "ready", q; return end
    b.phase = "quote"
    line.searched = true
    if not line.key or not pcall(AH().SendSearchQuery, line.key, { { sortOrder = 0, reverseSort = false } }, true) then
        b.phase, b.err = "idle", "ERR_START"
        return
    end
    wait()
end

local function itemAnswer()
    local b, line = ns.buy, ns.Current()
    if not line or line.mode ~= "i" or not line.key or (b.phase ~= "quote" and b.phase ~= "idle") then return end
    if b.phase == "idle" and (b.err or not line.searched) then return end
    local q = ns.ItemQuote(line)
    if q then b.phase, b.quote, b.err = "ready", q, nil
    elseif b.phase == "quote" and fullResults(line) then b.phase, b.err = "idle", "ERR_SOLD_OUT" end
end

local function ask()
    local b, line = ns.buy, ns.Current()
    if not line then b.phase = "done"; return end
    b.quote, b.err = nil, nil
    if not ready() then b.err = "ERR_WAIT"; return end
    local mode = modeOf(line)
    if mode == "i" then return askItem(line) end
    line.guess = mode == nil
    b.phase = "quote"
    if not pcall(AH().StartCommoditiesPurchase, line.id, left(line)) then
        if line.guess and canBuyItems() then return askItem(line) end
        b.phase, b.err = "idle", "ERR_START"
        return
    end
    wait()
end

-- The Buy button: one step a click.
function ns.BuyClick()
    local b = ns.buy
    if not ns.atAH or not ns.CanBuy() or ns.paused then return end
    if b.phase == "idle" then ask()
    elseif b.phase == "ready" then
        local line = ns.Current()
        local q = b.quote
        b.phase = "buying"
        local ok
        if q.auction then
            ok = pcall(AH().PlaceBid, q.auction, q.total)
            if ok then ns.pending[q.auction] = line end
        else
            ok = pcall(AH().ConfirmCommoditiesPurchase, line.id, q.n or left(line))
        end
        if ok then wait() else b.phase, b.err = "idle", "ERR_BUY" end
    end
    if ns.Refresh then ns.Refresh() end
end

function ns.Skip()
    if not ns.Current() then return end
    cancelQuote()
    ns.Current().skipped = true
    ns.buy.err = nil
    nextLine()
    if ns.Refresh then ns.Refresh() end
end

-- n units of a line were bought for paid copper.
local function gotUnits(line, n, paid)
    local b = ns.buy
    b.spent, b.bought = b.spent + paid, b.bought + n
    line.got = math.min(line.n, line.got + n)
    ns.AddLot(line.id, n, paid)
end

function ns.OnAuction(event, a1, a2)
    local b = ns.buy
    local line = ns.Current()
    if event == "COMMODITY_PRICE_UPDATED" then
        if b.phase == "quote" and line and line.mode ~= "i" then
            line.mode, line.guess = "c", nil
            b.phase, b.quote = "ready", { unit = (a1 or 0), total = a2 or 0, n = left(line) }
        end
    elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
        if b.phase == "quote" and line and line.mode ~= "i" then
            -- not known as a commodity: it is sold one auction at a time, search it as such
            if line.guess and canBuyItems() then line.guess = nil; askItem(line)
            else b.phase, b.err = "idle", "ERR_SOLD_OUT" end
        end
    elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
        if b.phase == "buying" and line and line.mode ~= "i" then
            gotUnits(line, b.quote and b.quote.n or left(line), b.quote and b.quote.total or line.cost)
            if left(line) > 0 then b.phase, b.quote = "idle", nil else nextLine() end
        end
    elseif event == "COMMODITY_PURCHASE_FAILED" then
        if b.phase == "buying" then b.phase, b.quote, b.err = "idle", nil, "ERR_BUY" end
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_ADDED" then
        itemAnswer()
    elseif event == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
        local l = a1 and ns.pending[a1]
        if l then
            ns.pending[a1] = nil
            l.gone = l.gone or {}
            l.gone[a1] = true
            local paid = (b.quote and b.quote.auction == a1) and b.quote.total or l.unit or 0
            gotUnits(l, 1, paid)
            if l == line and (b.phase == "buying" or b.phase == "idle") then
                b.err = nil
                if left(line) > 0 then
                    -- the next unit: the next lot of the same results, one click
                    local q = ns.ItemQuote(line)
                    if q then b.phase, b.quote = "ready", q else b.phase, b.quote = "idle", nil end
                else nextLine() end
            end
        end
    elseif event == "AUCTION_HOUSE_SHOW_ERROR" then
        if b.phase == "buying" and line and b.quote and b.quote.auction then
            -- that lot is gone (sold to someone else): the next click takes the next one
            ns.pending[b.quote.auction] = nil
            line.gone = line.gone or {}
            line.gone[b.quote.auction] = true
            b.phase, b.quote, b.err = "idle", nil, "ERR_GONE"
        end
    end
    if ns.Refresh then ns.Refresh() end
end

function ns.Money(copper)
    copper = math.floor(copper or 0)
    local neg = copper < 0
    copper = math.abs(copper)
    local text
    if GetCoinTextureString then text = GetCoinTextureString(copper >= 10000 and copper - copper % 100 or copper) else
        local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
        local parts = {}
        if g > 0 then parts[#parts + 1] = g .. "g" end
        if s > 0 then parts[#parts + 1] = s .. "s" end
        if (c > 0 and g == 0) or #parts == 0 then parts[#parts + 1] = c .. "c" end
        text = table.concat(parts, " ")
    end
    return (neg and "-" or "") .. text
end

-- ---------- what was paid, and the history ----------

-- Units bought here and not used yet: db.lots[char][item] = { { n, total } }.
function ns.AddLot(id, n, total)
    if not ns.db or not n or n <= 0 then return end
    local key = charKey()
    ns.db.lots[key] = ns.db.lots[key] or {}
    local list = ns.db.lots[key][id] or {}
    ns.db.lots[key][id] = list
    list[#list + 1] = { n, total or 0 }
end
function ns.TakeLots(id, n)
    local mine = ns.db and ns.db.lots[charKey()]
    local list = mine and mine[id]
    local paid, got = 0, 0
    while list and list[1] and got < n do
        local lot = list[1]
        local take = math.min(n - got, lot[1])
        local part = math.floor(lot[2] * take / lot[1] + 0.5)
        paid, got = paid + part, got + take
        lot[1], lot[2] = lot[1] - take, lot[2] - part
        if lot[1] <= 0 then table.remove(list, 1) end
    end
    if list and not list[1] then mine[id] = nil end
    return paid, got
end

ns.HISTORY_MAX = 300

-- A writ was handed in: logged with what the auction house got for it and the reputation.
function ns.TurnedIn(quest)
    local w = ns.WritOfQuest(quest)
    if not w or not ns.db then return nil end
    local paid = ns.TakeLots(w.id, 1) + ns.TakeLots(w.item, w.count)
    local e = { at = time(), writ = w.id, rep = math.floor(w.rep * ns.Mult() + 0.5), paid = paid,
                pouch = ns.PouchAvg(w.rank), who = UnitName and UnitName("player") or nil }
    local h = ns.db.history
    table.insert(h, 1, e)
    while #h > ns.HISTORY_MAX do table.remove(h) end
    ns.pendingRep = { base = w.rep, entry = e }
    ns.LearnFromTurnIn(quest)
    if ns.StepGuide then ns.StepGuide() end
    return e
end

ns.PERIODS = { "day", "week", "all" }
local PERIOD_SECONDS = { day = 86400, week = 7 * 86400 }
function ns.History(period)
    local out, spent, rep, pouch = {}, 0, 0, 0
    local since = PERIOD_SECONDS[period] and (time() - PERIOD_SECONDS[period]) or nil
    for _, e in ipairs(ns.db and ns.db.history or {}) do
        if not since or e.at >= since then
            out[#out + 1] = e
            spent, rep, pouch = spent + (e.paid or 0), rep + (e.rep or 0), pouch + (e.pouch or 0)
        end
    end
    local net = spent - pouch
    return out, { count = #out, rep = rep, spent = spent, pouch = pouch,
                  per100 = rep > 0 and math.floor(net * 100 / rep + 0.5) or 0 }
end

-- ---------- leading to the customers ----------
-- One stop per customer with writs ready (taken or carried, the item in the bags): the nearest
-- by distance in the world first, the same continent before the other one, the ones with no
-- known spot last. One guide leads at a time, whatever module it is of (GulliHUD.guide).

ns.TRACK_MAX = 6

local function onKalimdor(map)
    for _, m in ipairs(ns.KALIMDOR) do if m == map then return true end end
    return false
end
ns.OnKalimdor = onKalimdor

-- A point in the world (yards) for a spot, or nil.
local function worldPos(map, x, y)
    if not (MAP.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local ok, cont, pos = pcall(MAP.GetWorldPosFromMapPos, map, CreateVector2D(x / 100, y / 100))
    if ok and cont and pos then local a, b = pos:GetXY(); return cont, a, b end
end

function ns.Stops(states)
    local stops, at = {}, {}
    for _, s in ipairs(states or ns.States()) do
        if s.status == "ready" then
            local spot = ns.Spot(s.w)
            local key = spot and (spot.npc or (spot.map .. ":" .. spot.x .. ":" .. spot.y)) or ("?" .. s.w.id)
            local stop = at[key]
            if not stop then
                stop = { key = tostring(key), spot = spot, who = ns.Customer(s.w), zone = spot and ns.ZoneName(spot.map),
                         writs = {}, rep = 0 }
                at[key] = stop
                stops[#stops + 1] = stop
            end
            stop.writs[#stop.writs + 1] = s.w
            stop.rep = stop.rep + math.floor(s.w.rep * ns.Mult() + 0.5)
        end
    end
    return stops
end

function ns.RankStops(stops, here)
    for i, st in ipairs(stops) do
        st.order = i
        if not st.spot then st.tier, st.dist = 3, 0
        else
            local k = onKalimdor(st.spot.map)
            st.tier = (here.map and here.kalimdor ~= nil and k ~= here.kalimdor) and 2 or 1
            st.dist = 0
            if here.cont then
                local c, x, y = worldPos(st.spot.map, st.spot.x, st.spot.y)
                if c == here.cont and x then st.dist = math.sqrt((x - here.wx) ^ 2 + (y - here.wy) ^ 2)
                elseif c then st.tier = 2 end
            elseif here.map == st.spot.map and here.x then
                st.dist = math.sqrt((here.x - st.spot.x) ^ 2 + (here.y - st.spot.y) ^ 2)
            elseif here.map ~= st.spot.map then st.dist = 1000 end
        end
    end
    table.sort(stops, function(a, b)
        if a.tier ~= b.tier then return a.tier < b.tier end
        if a.dist ~= b.dist then return a.dist < b.dist end
        return a.order < b.order
    end)
    return stops
end

function ns.Here()
    local map, x, y = playerSpot()
    local here = { map = map, x = x, y = y }
    if map then
        here.kalimdor = onKalimdor(map)
        local c, wx, wy = worldPos(map, x, y)
        if c then here.cont, here.wx, here.wy = c, wx, wy end
    end
    return here
end

function ns.OpenMap(id)
    if not id or (InCombatLockdown and InCombatLockdown()) then return false end
    if MAP.OpenWorldMap then MAP.OpenWorldMap(id)
    elseif OpenWorldMap then OpenWorldMap(id)
    else return false end
    return true
end

-- A map pin on a stop (the world map's waypoint, and TomTom's arrow when it is loaded).
function ns.SetPin(stop, open)
    local spot = stop and stop.spot
    if not (spot and MAP.SetUserWaypoint and UiMapPoint) then return false end
    MAP.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(spot.map, spot.x / 100, spot.y / 100))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    if TomTom and TomTom.AddWaypoint then
        TomTom:AddWaypoint(spot.map, spot.x / 100, spot.y / 100, { title = stop.who, from = CALLER })
    end
    ns.pinned = true
    if open then ns.OpenMap(spot.map) end
    return true
end

local function claim()
    GulliHUD = GulliHUD or {}
    local g = GulliHUD.guide
    if g and g.owner ~= "CraftsmansWrit" and g.stop then pcall(g.stop) end
    GulliHUD.guide = { owner = "CraftsmansWrit", stop = function() ns.StopGuide() end }
end

function ns.Guiding() return ns.guide ~= nil end

function ns.StartGuide()
    if ns.paused then return false end
    if #ns.Stops() == 0 then return false end
    claim()
    ns.guide = { last = nil }
    return ns.StepGuide()
end

function ns.StopGuide()
    ns.guide = nil
    if GulliHUD and GulliHUD.guide and GulliHUD.guide.owner == "CraftsmansWrit" then GulliHUD.guide = nil end
    if ns.pinned and MAP.ClearUserWaypoint then MAP.ClearUserWaypoint() end
    ns.pinned, ns.stop = nil, nil
    if ns.RefreshTracker then ns.RefreshTracker() end
    if ns.Refresh then ns.Refresh() end
end

-- Pins the nearest stop; the stop it leads to stays while it is still in the same group, so
-- walking nearer to another one never moves the pin back and forth.
function ns.StepGuide()
    if not ns.guide then return false end
    local stops = ns.RankStops(ns.Stops(), ns.Here())
    if #stops == 0 then
        say(L.GUIDE_DONE)
        ns.StopGuide()
        return false
    end
    local pick = stops[1]
    for _, st in ipairs(stops) do
        if st.tier ~= pick.tier then break end
        if st.key == ns.guide.last then pick = st break end
    end
    if pick.key ~= ns.guide.last then
        ns.guide.last = pick.key
        if pick.spot then ns.SetPin(pick) end
    end
    ns.stop, ns.stops = pick, stops
    if ns.RefreshTracker then ns.RefreshTracker() end
    if ns.Refresh then ns.Refresh() end
    return true
end

-- ---------- tooltips ----------

local function writLines(w, S)
    local s = ns.StateOf(w)
    local out = {}
    local rep = math.floor(w.rep * ns.Mult() + 0.5)
    out[#out + 1] = { group = "quest", left = S.Cap(L["RANK_" .. w.rank]), right = L.TIP_REP:format(rep),
                      color = S.MUTED, rcolor = S.TEXT, icon = "Interface\\Icons\\INV_Scroll_03" }
    local item = ns.ShortName(ns.DisplayName(w.item))
    local have = s.have + s.haveBank
    out[#out + 1] = { group = "quest", sub = true, left = L.TIP_NEEDS:format(w.count, item),
                      right = have >= w.count and L.TIP_HAVE:format(have) or L.TIP_MISSING,
                      color = S.MUTED, rcolor = have >= w.count and S.GOOD or S.WARN }
    out[#out + 1] = { group = "quest", sub = true, left = L.TIP_TODAY,
                      right = s.done and ns.DoneText() or L.TIP_CAN, color = S.MUTED, rcolor = s.done and S.BAD or S.GOOD }
    local who = ns.Customer(w)
    if who then
        local zone = ns.ZoneName(ns.Spot(w).map)
        out[#out + 1] = { group = "quest", sub = true, left = L.TIP_CUSTOMER, right = zone and L.WHO_WHERE:format(who, zone) or who,
                          color = S.MUTED, rcolor = S.GOLD }
    end
    local held = ns.CloseCost(s)
    if held and held.total then
        local parts = held.item > 0 and L.PART_ITEM:format(S.MoneyText(held.item, true)) or L.PART_ITEM_OWN
        parts = parts .. "  " .. L.PART_POUCH:format(S.MoneyText(held.pouch, true))
        local right = held.total < 0 and (S.Hex(S.GOOD) .. "+|r" .. S.MoneyText(-held.total)) or S.MoneyText(held.total)
        out[#out + 1] = { group = "price", left = S.Cap(L.TIP_CLOSE), right = right,
                          color = S.MUTED, icon = "Interface\\Icons\\INV_Misc_Bag_10" }
        out[#out + 1] = { group = "price", sub = true, left = parts, color = S.FAINT }
    end
    local c = ns.CostOf(w, ns.db.bank)
    if c.total then
        out[#out + 1] = { group = "price", left = S.Cap(L.TIP_PER100), right = S.MoneyText(math.floor(c.total * 100 / rep + 0.5)),
                          color = S.MUTED, icon = "Interface\\Icons\\INV_Misc_Coin_02" }
        if c.total < 0 then out[#out].right = S.Hex(S.GOOD) .. L.PROFIT .. "|r " .. S.MoneyText(-c.total) end
    end
    for _, a in ipairs(ns.AltCounts(w.id)) do
        out[#out + 1] = { group = "stock", left = a.name, right = tostring(a.n), color = S.MUTED }
    end
    return out
end

function ns.TipLines(id)
    if not ns.db or ns.paused or ns.db.tooltip == false or not id or not ns.Skin then return nil end
    local S = ns.Skin
    local w = ns.WRITS[id] and ns.Writ(id)
    if w then return writLines(w, S) end
    local rank = ns.SEALED[id]
    if rank then
        local avg = ns.PouchAvg(rank)
        return { { group = "note", left = S.Cap(L.TIP_SEALED:format(L["RANK_" .. rank])), right = L.TIP_REP:format(ns.REP[rank]),
                   color = S.MUTED, icon = "Interface\\Icons\\INV_Scroll_03" },
                 { group = "note", sub = true, left = L.TIP_POUCH, right = S.MoneyText(avg), color = S.MUTED } }
    end
    if POUCH_RANK[id] then
        local avg, n = ns.PouchAvg(POUCH_RANK[id])
        return { { group = "price", left = S.Cap(L.TIP_POUCH_AVG), right = S.MoneyText(avg), color = S.MUTED,
                   icon = "Interface\\Icons\\INV_Misc_Coin_02" },
                 { group = "price", sub = true, left = L.TIP_POUCH_SEEN:format(n), color = S.FAINT } }
    end
    local list = ns.WritsFor(id)
    if #list == 0 then return nil end
    local out = {}
    for _, w2 in ipairs(list) do
        if not w2.side or w2.side == side() then
            local s = ns.StateOf(w2)
            local mark = s.done and ns.DoneText() or ((s.bags > 0 or s.log) and L.TIP_CARRIED or nil)
            out[#out + 1] = { group = "quest", left = S.Cap(L.TIP_FOR_WRIT:format(ns.WritName(w2))),
                              right = L.TIP_REP:format(math.floor(w2.rep * ns.Mult() + 0.5)) .. (mark and (S.DOT .. mark) or ""),
                              color = S.MUTED, rcolor = s.done and S.FAINT or S.TEXT, sub = #out > 0,
                              icon = #out == 0 and "Interface\\Icons\\INV_Scroll_03" or nil }
        end
    end
    return #out > 0 and out or nil
end

-- ---------- events ----------

local function listen(frame, events)
    local valid = C_EventUtils and C_EventUtils.IsEventValid
    for _, e in ipairs(events) do
        if not valid or valid(e) then pcall(frame.RegisterEvent, frame, e) end
    end
end

function ns.AuctionClosed()
    ns.atAH = false
    ns.Invalidate()
    ns.StopScan()
    if ns.buy.phase ~= "done" then ns.buy.phase, ns.buy.quote = "idle", nil end
    if ns.HideAtAH then ns.HideAtAH() end
end

-- Something to do at the auction house: the plan buys something, or writs in the bags lack
-- their item.
function ns.WorkAtAH()
    if ns.plan and #ns.buy.queue > 0 and ns.buy.phase ~= "done" then return true end
    for _, s in ipairs(ns.States()) do if s.status == "item" then return true end end
    return false
end

local money
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1, a2)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliCraftsmansWritDB = GulliCraftsmansWritDB or {}
        GulliCraftsmansWritCharDB = GulliCraftsmansWritCharDB or {}
        ns.db, ns.cdb = GulliCraftsmansWritDB, GulliCraftsmansWritCharDB
        for k, v in pairs(ns.DEFAULTS) do if ns.db[k] == nil then ns.db[k] = v end end
        ns.db.history = ns.db.history or {}
        ns.db.lots = ns.db.lots or {}
        ns.db.spots = ns.db.spots or {}
        ns.db.chars = ns.db.chars or {}
        ns.db.pouches = ns.db.pouches or {}
        ns.MergeRealmless()
        listen(self, { "AUCTION_HOUSE_SHOW", "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED",
                       "PLAYER_ENTERING_WORLD", "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_LOG_UPDATE",
                       "UPDATE_FACTION", "PLAYER_MONEY", "LOOT_OPENED", "LOOT_CLOSED", "MERCHANT_SHOW",
                       "MERCHANT_CLOSED", "ZONE_CHANGED_NEW_AREA", "BANKFRAME_OPENED",
                       "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE",
                       "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_ADDED",
                       "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED",
                       "AUCTION_HOUSE_PURCHASE_COMPLETED", "AUCTION_HOUSE_SHOW_ERROR" })
        if ns.Skin then
            if ns.Skin.ClosesWith then ns.Skin.ClosesWith("auction", ns.AuctionClosed) end
            if ns.Skin.TipProvider then ns.Skin.TipProvider("item", "CraftsmansWrit", function(id) return ns.TipLines(id) end) end
        end
        money = GetMoney and GetMoney() or 0
        return
    end
    if event == "PLAYER_MONEY" then
        local now = GetMoney and GetMoney() or 0
        local delta = now - (money or now)
        money = now
        ns.PouchMoney(delta)
        return
    elseif event == "LOOT_OPENED" then ns.looting = true; return
    elseif event == "LOOT_CLOSED" then
        C_Timer.After(POUCH_WAIT, function() ns.looting = false end)
        return
    elseif event == "MERCHANT_SHOW" then ns.atVendor = true; return
    elseif event == "MERCHANT_CLOSED" then ns.atVendor = false; return
    end
    if event == "UPDATE_FACTION" or event == "PLAYER_ENTERING_WORLD" then
        local r = ns.Rep()
        ns.NoteRep(r and r.value)
        if event == "PLAYER_ENTERING_WORLD" then ns.PouchReset(); ns.Snapshot(); ns.Prefetch() end
        ns.Invalidate()
        ns.RefreshSoon()
        return
    end
    if event == "QUEST_TURNED_IN" then
        ns.Invalidate()
        if ns.TurnedIn(a1) then
            local r = ns.Rep()
            repWas = repWas or (r and r.value)
            if ns.Refresh then ns.Refresh() end
        end
        return
    elseif event == "QUEST_ACCEPTED" then
        ns.LearnFromMarker(a2 or a1)
        if ns.guide then ns.StepGuide() end
        return
    end
    if ns.paused then return end
    if event == "AUCTION_HOUSE_SHOW" then
        ns.atAH = true
        ns.Invalidate()
        if ns.plan and not busy() then ns.Calculate() end
        if ns.db.auto and ns.WorkAtAH() and ns.ShowAtAH then ns.ShowAtAH() end
        if ns.Refresh then ns.Refresh() end
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_UPDATED" then
        ns.OnSearch(a1)
        if event == "ITEM_SEARCH_RESULTS_UPDATED" then ns.OnAuction(event, a1, a2) end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if not ns.namesPending and C_Timer and ns.Refresh then
            ns.namesPending = true
            C_Timer.After(0.3, function()
                ns.namesPending = nil
                if ns.Refresh then ns.Refresh() end
            end)
        end
    elseif event == "BAG_UPDATE_DELAYED" or event == "QUEST_LOG_UPDATE" then
        ns.Invalidate()
        if event == "BAG_UPDATE_DELAYED" then ns.PouchCheck(); ns.SnapshotSoon() end
        if ns.guide and event == "BAG_UPDATE_DELAYED" then ns.StepGuide() end
        ns.RefreshSoon()
    elseif event == "BANKFRAME_OPENED" then
        ns.Snapshot()
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        if ns.guide then ns.StepGuide() end
    else
        ns.OnAuction(event, a1, a2)
    end
end)

-- ---------- slash command and hub ----------

SLASH_GULLICRAFTSMANSWRIT1 = "/gcw"
SLASH_GULLICRAFTSMANSWRIT2 = "/gwr" -- the name of 1.0.0
SlashCmdList.GULLICRAFTSMANSWRIT = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "lead" then if not ns.StartGuide() then say(L.GUIDE_NONE) end return end
    if msg == "stop" then ns.StopGuide() return end
    if msg == "plan" then ns.Calculate(); if ns.ShowTab then ns.ShowTab(2) end return end
    if msg == "perf" then
        local p = ns.perf
        say(L.PERF_LINE:format(math.floor(p.redraw or 0), p.tab or 0, math.floor(p.calc or 0)))
        return
    end
    if msg == "pouches" then
        for _, r in ipairs(ns.RANKS) do
            local avg, n = ns.PouchAvg(r)
            say(L.POUCH_LINE:format(L["RANK_" .. r], ns.Money(avg), n))
        end
        return
    end
    if ns.Toggle then ns.Toggle() end
end
function GulliCraftsmansWrit_Toggle() if ns.Toggle then ns.Toggle() end end

ns.OPT_ICON = {
    bank = "Interface\\Minimap\\Tracking\\Banker",
    sealed = "Interface\\Icons\\INV_Scroll_03",
    pouch = "Interface\\Icons\\INV_Misc_Coin_02",
    live = "Interface\\Icons\\INV_Misc_Spyglass_03",
    auto = "Interface\\Minimap\\Tracking\\Auctioneer",
    tooltip = "Interface\\Icons\\INV_Misc_Note_01",
}

local function option(key)
    return { label = L["OPT_" .. key], icon = ns.OPT_ICON[key], tip = L["TIP_" .. key],
             get = function() return ns.db ~= nil and ns.db[key] == true end,
             set = function(on) if ns.db then ns.SetPref(key, on and true or false) end end }
end

do
    local register = GulliToolkit and GulliToolkit.Register or function(info) ns.alone = info end
    register({
        key = "CraftsmansWrit",
        icon = "Interface\\AddOns\\Gulli-CraftsmansWrit\\icon",
        slash = "/gcw",
        category = "Items",
        open = function() if ns.Toggle then ns.Toggle() end end,
        window = function() return ns.Window and ns.Window() end,
        options = { option("bank"), option("sealed"), option("pouch"), option("live") },
        move = function(on) if ns.MoveTracker then ns.MoveTracker(on) end end,
        frames = { { key = "tracker", icon = "Interface\\Icons\\INV_Misc_Map_02",
                     frame = function() return ns.TrackerFrame and ns.TrackerFrame() end } },
        pause = function(on)
            ns.paused = on
            if on then
                if ns.guide then ns.StopGuide() end
                if ns.HideAtAH then ns.HideAtAH() end
            end
        end,
        summary = function()
            if not ns.db then return nil end
            local t = ns.Today()
            if t.ready == 0 then return nil end
            return L.SUMMARY:format(t.ready), ns.OPT_ICON.sealed
        end,
        reset = function()
            if not ns.db then return end
            for k, v in pairs(ns.DEFAULTS) do ns.db[k] = v end
            ns.plan = nil
            ns.ResetBuy()
            if ns.Refresh then ns.Refresh() end
        end,
    })
end
