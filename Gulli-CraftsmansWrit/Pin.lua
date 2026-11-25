-- A pinned plan: the plan of the Plan tab kept by days. Day 1 is the game day it was pinned (the
-- daily reset, ns.DayKey, not midnight). It keeps the writ copies the plan picked, each with the
-- day the plan gave it (p), the day it stands on now (day) and, once handed in, when (done). A
-- copy that was not handed in on its day moves on by itself: copy k of a writ type always comes
-- after copy k - 1, so a miss shifts that type's queue by a day, and the plan's end moves only
-- when that queue was the longest (owner's decision of 2026-11-25). Do not catch up drops the
-- missed copies instead. Anything handed in counts as done (a writ from the bags or bought, from
-- a Sealed Writ too); a hand-in the plan does not have counts its reputation, so the plan ends
-- early. One running plan per character (GulliCraftsmansWritDB.plans, for the whole account);
-- finished plans are kept with their result. Recalculate prices prices what is left and never
-- changes the steps; a free calculation aside (Is there a cheaper plan?) is set beside it.
--
-- Plain rules: no frames. The game is read only through Core.lua.

local _, ns = ...
local L = ns.L

ns.PIN_MAX, ns.PIN_DONE = 10, 10 -- running plans, finished plans kept
ns.PIN_SAME = 0.05 -- a new calculation within 5% of the plan is "about the same"
ns.PIN_DEAR = 0.10 -- a price this much over the plan's shows in the warning colour
ns.pinUndone = {} -- character -> true: an auto-pin was undone, so not again this session

local function plans()
    if not ns.db then return {} end
    ns.db.plans = ns.db.plans or {}
    return ns.db.plans
end
function ns.Plans() return plans() end

local function me() return ns.CharKey() end

-- The day number of a pin on game day `key` (ns.DayKey), day 1 = the day it was pinned.
function ns.PinDay(pin, key)
    key = key or ns.DayKey()
    return math.floor((key - pin.day1) / 24 + 0.5) + 1
end

-- When game day d of a pin began: the daily reset before it (seconds).
function ns.PinDate(pin, d) return (pin.day1 - 24 + 24 * (d - 1)) * 3600 end

local fmtDate = date or (os and os.date)
local function split(s)
    local out = {}
    for w in tostring(s or ""):gmatch("%S+") do out[#out + 1] = w end
    return out
end
-- "26 Nov" in the client's language (L.DATE_DM with {d} and {m}).
function ns.DateText(t)
    local d = fmtDate and fmtDate("*t", math.floor(t + 60))
    if type(d) ~= "table" then return "" end
    local m = split(L.MONTHS)[d.month] or tostring(d.month)
    return (L.DATE_DM:gsub("{d}", tostring(d.day)):gsub("{m}", m))
end
function ns.WeekdayText(t)
    local d = fmtDate and fmtDate("*t", math.floor(t + 60))
    if type(d) ~= "table" then return "" end
    return split(L.WEEKDAYS)[d.wday] or ""
end
function ns.PinDateText(pin, d) return ns.DateText(ns.PinDate(pin, d)) end

local function pending(c) return not c.done and not c.dropped end

-- Every copy goes to its day: a writ type's queue in order (one a day, never before the day the
-- plan gave it, never before today), a Sealed Writ on its day or today.
local function schedule(pin, today)
    local mine = pin.key == me()
    local byType, order = {}, {}
    for _, c in ipairs(pin.copies) do
        local key = c.kind .. ":" .. c.id
        local t = byType[key]
        if not t then t = {}; byType[key] = t; order[#order + 1] = t end
        t[#t + 1] = c
    end
    for _, t in ipairs(order) do
        table.sort(t, function(a, b) return a.k < b.k end)
        local prev = 0
        -- handed in today before the plan knew (before it was pinned): the first copy waits
        local first = t[1]
        if mine and first.kind == "writ" and first.quest and ns.DoneToday(first.quest) then prev = today end
        for _, c in ipairs(t) do
            if c.done then prev = math.max(prev, c.done.day)
            elseif not c.dropped then
                local d = math.max(c.p, today)
                if c.kind == "writ" then d = math.max(d, prev + 1) end
                c.day, prev = d, d
            end
        end
    end
end
ns.PinSchedule = schedule

-- What each day that is over held: { n, done, miss = { copy index } }, written once the day is
-- over, so a later shift never rewrites what happened. Then every copy goes to its day.
function ns.PinRoll(pin, today)
    if pin.finished then return end
    today = today or ns.PinDay(pin)
    pin.days = pin.days or {}
    for d = (pin.rolled or 0) + 1, today - 1 do
        local n, done, miss = 0, 0, {}
        for i, c in ipairs(pin.copies) do
            if not c.dropped then
                local day = c.done and c.done.day or c.day
                if day == d then
                    n = n + 1
                    if c.done then done = done + 1 else miss[#miss + 1] = i end
                end
            end
        end
        pin.days[d] = { n = n, done = done, miss = miss }
    end
    if today - 1 > (pin.rolled or 0) then pin.rolled = today - 1 end
    schedule(pin, today)
end

-- The running plan of a character (this one by default), rolled to today. Its reputation is
-- read when it is this character's.
function ns.PinFor(key)
    key = key or me()
    for _, pin in ipairs(plans()) do
        if pin.key == key and not pin.finished then
            ns.PinRoll(pin)
            if key == me() then
                local r = ns.Rep()
                if r and r.value then pin.rep = r.value end
                ns.PinCheckEnd(pin)
                if pin.finished then return nil end
            end
            return pin
        end
    end
end

-- The plan this window shows: another character's chosen from the list, else this one's.
function ns.PinShown()
    local v = ns.viewPin
    if v and not v.finished then
        for _, pin in ipairs(plans()) do
            if pin == v then
                if pin.key == me() then return ns.PinFor() end
                ns.PinRoll(pin)
                return pin
            end
        end
        ns.viewPin = nil
    end
    return ns.PinFor()
end

local function count(pred)
    local n = 0
    for _, pin in ipairs(plans()) do if pred(pin) then n = n + 1 end end
    return n
end

-- A pin from a plan (ns.Plan's result with goal and need): nil when there is nothing to pin, the
-- character has a running plan already, or the list of running plans is full.
function ns.PinMake(plan)
    if not (ns.db and plan and plan.lines and #plan.lines > 0) then return nil end
    if plan.need == 0 then return nil end
    local key = me()
    for _, p in ipairs(plans()) do if p.key == key and not p.finished then return nil, "mine" end end
    if count(function(p) return not p.finished end) >= ns.PIN_MAX then return nil, "full" end
    local rep = ns.Rep()
    local value = rep and rep.value or 0
    local class
    if UnitClass then class = select(2, UnitClass("player")) end
    local pin = { key = key, who = UnitName and UnitName("player") or key, class = class, side = ns.Side(),
                  at = time(), day1 = ns.DayKey(), goal = plan.goal, goalAt = value + (plan.need or 0),
                  repStart = value, rep = value, mult = ns.Mult(),
                  total = plan.total, buy = plan.buy, pouch = plan.pouch, copies = {}, days = {}, rolled = 0 }
    for _, l in ipairs(plan.lines) do
        local w = l.w
        pin.copies[#pin.copies + 1] = {
            kind = l.kind, id = l.id, rank = l.rank, k = l.k, p = l.day, day = l.day, rep = l.rep,
            writ = l.writ, item = l.item, pouch = l.pouch, cost = l.cost, writFrom = l.writFrom,
            itemFrom = l.itemFrom, itemN = l.itemN, estimate = l.estimate,
            itemId = w and w.item, count = w and w.count, quest = w and w.quest }
    end
    table.insert(plans(), 1, pin)
    ns.Invalidate()
    return pin
end

local function remove(pin)
    for i, p in ipairs(plans()) do if p == pin then table.remove(plans(), i); return i end end
end

-- Pins the plan shown now, by the pin button.
function ns.PinNow()
    local pin, why = ns.PinMake(ns.plan)
    if why == "full" then ns.Say(L.PIN_FULL:format(ns.PIN_MAX)) end
    if pin then ns.ResetBuy() end
    if ns.Refresh then ns.Refresh() end
    return pin
end

-- Takes a running plan away (the strip's Unpin, the list's cross). Returns what Undo needs.
function ns.Unpin(pin)
    pin = pin or ns.PinFor()
    if not pin then return nil end
    local at = remove(pin)
    if ns.viewPin == pin then ns.viewPin = nil end
    ns.compare = nil
    ns.Invalidate()
    ns.ResetBuy()
    if ns.Refresh then ns.Refresh() end
    return { pin = pin, at = at }
end
function ns.PinRestore(undo)
    if not (undo and undo.pin) then return end
    table.insert(plans(), math.min(undo.at or 1, #plans() + 1), undo.pin)
    ns.Invalidate()
    ns.ResetBuy()
    if ns.Refresh then ns.Refresh() end
end

-- The plan pins itself at the first purchase through the Buy button or the first hand-in of one
-- of its writs, with a notice whose Undo also keeps it from pinning again this session.
function ns.AutoPin(why)
    if not ns.db or ns.db.autoPin == false or ns.pinUndone[me()] then return nil end
    if not ns.plan or ns.stale or ns.viewPin or ns.PinFor() then return nil end
    local pin = ns.PinMake(ns.plan)
    if not pin then return nil end
    local S = ns.Skin
    if S and S.Toast then
        S.Toast({ key = "CraftsmansWritPin", icon = ns.ICON or "Interface\\Icons\\INV_Scroll_03",
                  title = L.PIN_AUTO, text = why == "turnin" and L.PIN_AUTO_TURNIN or L.PIN_AUTO_BUY, seconds = 12,
                  buttons = { { text = L.UNDO, onClick = function() ns.PinUndo(pin) end } } })
    end
    if ns.Refresh then ns.Refresh() end
    return pin
end
function ns.PinUndo(pin)
    ns.pinUndone[me()] = true
    remove(pin)
    ns.Invalidate()
    if ns.Refresh then ns.Refresh() end
end

-- A writ was handed in: the plan's copy of it (the first one still open), else a Sealed Writ of
-- its rank, is done today. Returns the copy, or nil for a hand-in the plan does not have.
function ns.PinHandIn(w)
    local pin = ns.PinFor()
    if not (pin and w) then return nil end
    local today = ns.PinDay(pin)
    local best
    for _, c in ipairs(pin.copies) do
        if pending(c) and c.kind == "writ" and c.id == w.id and (not best or c.k < best.k) then best = c end
    end
    if not best then
        for _, c in ipairs(pin.copies) do
            if pending(c) and c.kind == "sealed" and c.rank == w.rank and (not best or c.day < best.day) then best = c end
        end
    end
    if not best then
        pin.off = (pin.off or 0) + 1
        return nil, pin
    end
    best.done, best.day = { at = time(), day = today }, today
    schedule(pin, today)
    ns.Invalidate()
    return best, pin
end

-- Called from ns.TurnedIn: pins the plan when this is one of its writs, then marks the copy.
function ns.PinTurnIn(w)
    if not w then return end
    if not ns.PinFor() and ns.plan and not ns.stale then
        for _, l in ipairs(ns.plan.lines) do
            if l.kind == "writ" and l.id == w.id then ns.AutoPin("turnin"); break end
        end
    end
    local c, pin = ns.PinHandIn(w)
    if pin then ns.PinCheckEnd(pin) end
    return c
end

-- The copies planned for a day that is over and still not handed in: { copy }.
local function missed(pin, today)
    local out = {}
    for _, c in ipairs(pin.copies) do if pending(c) and c.p < today then out[#out + 1] = c end end
    return out
end

-- Do not catch up: the missed copies leave the plan, the copies after them go back to the days
-- the plan gave them.
function ns.PinNoCatchUp(pin)
    pin = pin or ns.PinFor()
    if not pin then return 0 end
    local today = ns.PinDay(pin)
    local list = missed(pin, today)
    for _, c in ipairs(list) do c.dropped = true end
    pin.seenMiss = today - 1
    schedule(pin, today)
    ns.PinCheckEnd(pin)
    ns.Invalidate()
    ns.ResetBuy()
    if ns.Refresh then ns.Refresh() end
    return #list
end

function ns.PinDismissMiss(pin)
    pin = pin or ns.PinShown()
    if pin then pin.seenMiss = ns.PinDay(pin) - 1 end
    if ns.Refresh then ns.Refresh() end
end

-- What a finished plan did: { days, n, spent, pouch, rep } from the history since it was pinned.
local function result(pin)
    local r = { days = ns.PinDay(pin), n = 0, spent = 0, pouch = 0, rep = (pin.rep or 0) - (pin.repStart or 0) }
    for _, e in ipairs(ns.db and ns.db.history or {}) do
        if e.at >= pin.at and (not pin.who or e.who == pin.who) then
            r.n, r.spent, r.pouch = r.n + 1, r.spent + (e.paid or 0), r.pouch + (e.pouch or 0)
        end
    end
    return r
end

-- A plan ends when the goal is reached or nothing is left in it. The oldest finished ones past
-- ns.PIN_DONE go.
function ns.PinCheckEnd(pin)
    if not pin or pin.finished then return false end
    local open = 0
    for _, c in ipairs(pin.copies) do if pending(c) then open = open + 1 end end
    if (pin.rep or 0) < (pin.goalAt or 0) and open > 0 then return false end
    pin.finished = time()
    pin.result = result(pin)
    local reached = (pin.rep or 0) >= (pin.goalAt or 0)
    local msg = reached and L.PIN_REACHED:format(L["STAND_" .. (pin.goal or 5)] or "", pin.result.days)
        or L.PIN_ENDED
    ns.Say(msg)
    if GulliToolkit and GulliToolkit.Notify then GulliToolkit.Notify("CraftsmansWrit", msg) end
    local done = {}
    for i, p in ipairs(plans()) do if p.finished then done[#done + 1] = i end end
    for j = #done, ns.PIN_DONE + 1, -1 do table.remove(plans(), done[j]) end
    if ns.viewPin == pin then ns.viewPin = nil end
    ns.ResetBuy()
    return true
end

-- Everything the window shows of a pin: today, the days, the reputation, what was missed.
function ns.PinView(pin)
    local today = ns.PinDay(pin)
    local v = { pin = pin, today = today, mine = pin.key == me() }
    local last, planEnd = 1, 1
    local expected, behind, behindN = pin.repStart or 0, 0, 0
    v.todayList, v.doneToday, v.ofToday, v.repToday = {}, 0, 0, 0
    for _, c in ipairs(pin.copies) do
        if c.p <= today then expected = expected + (c.rep or 0) end
        planEnd = math.max(planEnd, c.p)
        if not c.dropped then
            local day = c.done and c.done.day or c.day
            last = math.max(last, day)
            if day == today then
                v.todayList[#v.todayList + 1] = c
                v.ofToday = v.ofToday + 1
                if c.done then v.doneToday = v.doneToday + 1 else v.repToday = v.repToday + (c.rep or 0) end
            end
            if pending(c) and c.p < today then behind, behindN = behind + (c.rep or 0), behindN + 1 end
        end
    end
    table.sort(v.todayList, function(a, b)
        if (a.done ~= nil) ~= (b.done ~= nil) then return b.done ~= nil end
        if a.rank ~= b.rank then return (a.rank or "") < (b.rank or "") end
        return a.id < b.id
    end)
    v.endDay, v.planEnd = math.max(last, today), planEnd
    v.now = pin.rep or pin.repStart or 0
    v.gained = v.now - (pin.repStart or 0)
    v.need = (pin.goalAt or 0) - (pin.repStart or 0)
    v.expected = math.min(expected, pin.goalAt or expected)
    v.behind, v.behindN = behind, behindN
    -- what was missed since the player last closed the notice
    v.miss, v.missDays = {}, 0
    local from = math.max((pin.seenMiss or 0) + 1, 1)
    for d = from, today - 1 do
        local day = pin.days and pin.days[d]
        local any
        for _, i in ipairs(day and day.miss or {}) do
            local c = pin.copies[i]
            if c and pending(c) then v.miss[#v.miss + 1] = c; any = true end
        end
        if any then v.missDays, v.missDay = v.missDays + 1, v.missDay or d end
    end
    if v.missDays == 1 and v.missDay == today - 1 then
        local day = pin.days[today - 1]
        v.missYesterday = { n = #v.miss, of = day and day.n or #v.miss }
    end
    -- copies past what the goal still needs: "no longer needed"
    local left = (pin.goalAt or 0) - v.now
    local open = {}
    for _, c in ipairs(pin.copies) do if pending(c) then open[#open + 1] = c end end
    table.sort(open, function(a, b) if a.day ~= b.day then return a.day < b.day end return a.k < b.k end)
    v.extra = {}
    for _, c in ipairs(open) do
        if left <= 0 then v.extra[c] = true end
        left = left - (c.rep or 0)
    end
    v.open = #open
    return v
end

-- The ribbon of days: { { d, t, n, done, today, past, miss, extra } } from day 1 to the end.
function ns.PinDays(pin, v)
    v = v or ns.PinView(pin)
    local out = {}
    for d = 1, v.endDay do
        local row = { d = d, t = ns.PinDate(pin, d), today = d == v.today, past = d < v.today, n = 0, done = 0 }
        local frozen = d < v.today and pin.days and pin.days[d]
        if frozen then
            row.n, row.done, row.miss = frozen.n, frozen.done, #frozen.miss
        else
            for _, c in ipairs(pin.copies) do
                if not c.dropped and (c.done and c.done.day or c.day) == d then
                    row.n = row.n + 1
                    if c.done then row.done = row.done + 1 end
                end
            end
        end
        row.extra = d > v.planEnd
        out[#out + 1] = row
    end
    return out
end

-- What is left to buy for the open copies, from today ("today") or the whole plan ("all"). The
-- bags, the bank (with the setting) and a writ in the quest log go to the earliest copies first.
-- Returns { lines = { { id, part = "writ"|"item", need, have, left, unit, plan, dear } }, left,
--   planLeft, pouch, total, missing, buy = a plan-like table for ns.BuySteps }.
function ns.PinBuys(pin, scope)
    local v = ns.PinView(pin)
    local today = v.today
    local useBank = ns.db and ns.db.bank
    local mine = pin.key == me()
    local open = {}
    for _, c in ipairs(pin.copies) do if pending(c) then open[#open + 1] = c end end
    table.sort(open, function(a, b) if a.day ~= b.day then return a.day < b.day end return a.k < b.k end)
    local stock = {}
    local function held(id)
        if stock[id] == nil then
            local b, k = ns.Stock(id)
            stock[id] = b + (useBank and k or 0)
        end
        return stock[id]
    end
    local sealedHeld = ns.SealedHeld(useBank)
    local logged = {}
    local out = { lines = {}, left = 0, planLeft = 0, pouch = 0, missing = 0, buy = { lines = {} } }
    local at = {}
    local function line(id, part)
        local l = at[id]
        if not l then
            l = { id = id, part = part, need = 0, have = 0, left = 0, planCost = 0, planUnits = 0 }
            at[id] = l
            out.lines[#out.lines + 1] = l
        end
        return l
    end
    for _, c in ipairs(open) do
        local inScope = scope == "all" or c.day <= today
        -- the writ
        local own = false
        if c.kind == "sealed" then
            if (sealedHeld[c.rank] or 0) > 0 then sealedHeld[c.rank], own = sealedHeld[c.rank] - 1, true end
        else
            if mine and c.quest and not logged[c.id] and ns.InLog(c.quest) then logged[c.id], own = true, true
            elseif held(c.id) > 0 then stock[c.id], own = stock[c.id] - 1, true end
        end
        -- its item (a Sealed Writ's item is not known before it is opened)
        local itemNeed, itemHave = 0, 0
        if c.kind == "writ" and c.itemId then
            itemNeed = c.count or 1
            itemHave = math.min(itemNeed, held(c.itemId))
            stock[c.itemId] = stock[c.itemId] - itemHave
        end
        if inScope then
            out.pouch = out.pouch + (c.pouch or 0)
            local wl = line(c.id, "writ")
            wl.need, wl.have = wl.need + 1, wl.have + (own and 1 or 0)
            if not own then
                wl.left = wl.left + 1
                if c.writFrom == "ah" then wl.planCost, wl.planUnits = wl.planCost + (c.writ or 0), wl.planUnits + 1 end
            end
            if itemNeed > 0 then
                local il = line(c.itemId, "item")
                il.need, il.have, il.left = il.need + itemNeed, il.have + itemHave, il.left + itemNeed - itemHave
                if (c.itemN or 0) > 0 then il.planCost, il.planUnits = il.planCost + (c.item or 0), il.planUnits + c.itemN end
            end
            out.buy.lines[#out.buy.lines + 1] = {
                kind = c.kind, id = c.id, w = c.kind == "writ" and ns.Writ(c.id) or nil, rank = c.rank, k = c.k,
                day = c.day, writFrom = own and "own" or "ah", writ = 0, itemN = itemNeed - itemHave, item = 0,
                itemFrom = itemNeed - itemHave > 0 and "ah" or "own", pouch = c.pouch or 0, rep = c.rep }
        end
    end
    for _, l in ipairs(out.lines) do
        if l.planUnits > 0 then l.plan = l.planCost / l.planUnits end
        if l.left > 0 then
            l.unit = ns.Price(l.id, l.left, 0)
            if l.unit then
                l.cost = math.floor(l.unit * l.left + 0.5)
                out.left = out.left + l.cost
                if l.plan and l.plan > 0 and l.unit > l.plan * (1 + ns.PIN_DEAR) then
                    l.dear = math.floor((l.unit / l.plan - 1) * 100 + 0.5)
                end
            else out.missing = out.missing + 1 end
            out.planLeft = out.planLeft + math.floor((l.plan or l.unit or 0) * l.left + 0.5)
        end
    end
    -- the buying steps price each copy at today's unit price
    for _, bl in ipairs(out.buy.lines) do
        if bl.writFrom == "ah" then bl.writ = math.floor((at[bl.id].unit or 0) + 0.5) end
        if bl.itemN > 0 and bl.w then bl.item = math.floor((at[bl.w.item] and at[bl.w.item].unit or 0) * bl.itemN + 0.5) end
        bl.cost = bl.writ + bl.item - bl.pouch
    end
    table.sort(out.lines, function(a, b)
        if (a.left > 0) ~= (b.left > 0) then return a.left > 0 end
        if a.part ~= b.part then return a.part == "writ" end
        return a.id < b.id
    end)
    out.total = out.left - out.pouch
    return out
end

-- What the Buy button works through: the pinned plan's purchases while this character has one,
-- else the plan of the Plan tab.
function ns.BuyPlan()
    local pin = ns.PinShown and ns.PinShown()
    if pin then return ns.PinBuys(pin, ns.db.pinScope or "today").buy end
    return ns.plan
end

-- Recalculate prices: the prices of what is left, read again at the auction house (with live),
-- else from the price addon. The steps of the plan never change.
function ns.PinRecalc()
    local pin = ns.PinFor()
    if not pin or ns.Busy() then return end
    local function done()
        pin.priced = time()
        ns.Invalidate()
        ns.ResetBuy()
        if ns.Refresh then ns.Refresh() end
    end
    if ns.atAH and ns.db.live and ns.CanSearch() then
        local ids = {}
        for _, l in ipairs(ns.PinBuys(pin, "all").lines) do
            if l.left > 0 then ns.lots[l.id] = nil; ids[#ids + 1] = l.id end
        end
        if ns.ScanLots(ids, done) > 0 then
            if ns.Refresh then ns.Refresh() end
            return
        end
    end
    done()
end

-- Is there a cheaper plan? A free calculation to the same goal over the days the pinned plan has
-- left, from the bags as they are; ns.PinCompare sets it beside the pin.
function ns.PinCompareStart()
    local pin = ns.PinFor()
    if not pin then return end
    local v = ns.PinView(pin)
    ns.compare = { pin = pin, goal = pin.goal, days = math.max(1, math.min(ns.DAYS_MAX, v.endDay - v.today + 1)) }
    ns.Calculate(nil, "compare")
    if ns.Refresh then ns.Refresh() end
end
function ns.PinCompareStop()
    ns.compare = nil
    if ns.Refresh then ns.Refresh() end
end

-- The pinned plan's rest beside the new calculation: { mine, fresh, diff, verdict, changes }.
-- What was bought for the pin is in the bags, so both count it as paid.
function ns.PinCompare(pin, fresh)
    if not (pin and fresh) then return nil end
    local v = ns.PinView(pin)
    local buys = ns.PinBuys(pin, "all")
    local maxDay = 0
    for _, l in ipairs(fresh.lines) do maxDay = math.max(maxDay, l.day) end
    local mine = { n = v.open, buy = buys.left, pouch = buys.pouch, total = buys.total, endDay = v.endDay,
                   missing = buys.missing }
    local new = { n = #fresh.lines, buy = fresh.buy, pouch = fresh.pouch, total = fresh.total,
                  endDay = v.today + math.max(1, maxDay) - 1, short = fresh.short }
    local diff = mine.total - new.total
    local verdict
    if (new.short or 0) > 0 then verdict = "worse"
    elseif math.abs(diff) <= ns.PIN_SAME * math.max(math.abs(mine.total), 1) then verdict = "same"
    elseif diff > 0 then verdict = "better" else verdict = "worse" end
    -- the writ types each plan still hands in, and what it changes
    local a, b, ids = {}, {}, {}
    for _, c in ipairs(pin.copies) do
        if pending(c) then
            a[c.id] = (a[c.id] or 0) + 1
            if not ids[c.id] then ids[c.id] = c.kind end
        end
    end
    for _, l in ipairs(fresh.lines) do
        b[l.id] = (b[l.id] or 0) + 1
        if not ids[l.id] then ids[l.id] = l.kind end
    end
    local changes = {}
    for id, kind in pairs(ids) do
        local x, y = a[id] or 0, b[id] or 0
        if x ~= y then changes[#changes + 1] = { id = id, kind = kind, from = x, to = y } end
    end
    -- held for the pin and of no use to the new calculation
    local uses = {}
    for _, l in ipairs(fresh.lines) do
        uses[l.id] = true
        if l.w then uses[l.w.item] = true end
    end
    for _, l in ipairs(buys.lines) do
        if l.have > 0 and not uses[l.id] then changes[#changes + 1] = { id = l.id, kind = l.part, held = l.have } end
    end
    table.sort(changes, function(x, y)
        if (x.held ~= nil) ~= (y.held ~= nil) then return y.held ~= nil end
        return x.id < y.id
    end)
    return { mine = mine, fresh = new, diff = diff, verdict = verdict, changes = changes }
end

-- Go over to the new calculation: its writs take the place of the open copies from today on;
-- what was handed in, day 1 and the goal stay.
function ns.PinSwitch(pin, fresh)
    pin = pin or ns.PinFor()
    fresh = fresh or ns.fresh
    if not (pin and fresh) then return false end
    local today = ns.PinDay(pin)
    local keep, topK = {}, {}
    for _, c in ipairs(pin.copies) do
        if c.done then
            keep[#keep + 1] = c
            local key = c.kind .. ":" .. c.id
            topK[key] = math.max(topK[key] or 0, c.k)
        end
    end
    for _, l in ipairs(fresh.lines) do
        local w = l.w
        local key = l.kind .. ":" .. l.id
        keep[#keep + 1] = {
            kind = l.kind, id = l.id, rank = l.rank, k = (topK[key] or 0) + l.k, p = today + l.day - 1,
            day = today + l.day - 1, rep = l.rep, writ = l.writ, item = l.item, pouch = l.pouch, cost = l.cost,
            writFrom = l.writFrom, itemFrom = l.itemFrom, itemN = l.itemN, estimate = l.estimate,
            itemId = w and w.item, count = w and w.count, quest = w and w.quest }
    end
    pin.copies = keep
    pin.switched = time()
    pin.seenMiss = today - 1
    schedule(pin, today)
    ns.compare, ns.fresh = nil, nil
    ns.Invalidate()
    ns.ResetBuy()
    if ns.Refresh then ns.Refresh() end
    return true
end

-- The list of plans: running first (this character's on top), then finished, newest first.
function ns.PinRows()
    local run, done = {}, {}
    local key = me()
    for _, pin in ipairs(plans()) do
        if pin.finished then done[#done + 1] = pin
        else
            ns.PinRoll(pin)
            run[#run + 1] = pin
        end
    end
    table.sort(run, function(a, b)
        if (a.key == key) ~= (b.key == key) then return a.key == key end
        return a.at > b.at
    end)
    table.sort(done, function(a, b) return a.finished > b.finished end)
    return run, done
end

-- Once a game day, at login: the plan's day, what it holds today and what was missed.
function ns.PinLoginNote()
    if not (ns.db and ns.cdb) or ns.db.planNote == false or ns.paused then return end
    local pin = ns.PinFor()
    if not pin then return end
    local key = ns.DayKey()
    if ns.cdb.pinNote == key then return end
    ns.cdb.pinNote = key
    local v = ns.PinView(pin)
    local S = ns.Skin
    if not (S and S.Toast) then return end
    local text = L.NOTE_TODAY:format(v.ofToday - v.doneToday, v.repToday)
    if v.missYesterday then text = L.NOTE_MISSED:format(v.missYesterday.n, v.missYesterday.of) .. " " .. text end
    S.Toast({ key = "CraftsmansWritDay", icon = ns.ICON or "Interface\\Icons\\INV_Scroll_03",
              title = L.NOTE_TITLE:format(v.today, v.endDay), text = text, kind = v.missYesterday and "warn" or nil,
              seconds = 15,
              buttons = { { text = L.OPEN_PLAN, onClick = function() if ns.ShowTab then ns.ShowTab(2) end end } } })
end

-- The hub's line and tile while a plan runs: "2 of 5 today", day 3 of 10.
function ns.PinSummary()
    local pin = ns.PinFor()
    if not pin then return nil end
    local v = ns.PinView(pin)
    local tile = { value = v.doneToday .. "/" .. v.ofToday, pips = { v.doneToday, v.ofToday },
                   label = L.SUM_PIN_DAY:format(v.today, v.endDay) .. ", "
                       .. (v.behindN > 0 and L.BEHIND_SHORT or L.ON_PLAN),
                   tone = v.behindN > 0 and "warn" or (v.ofToday > 0 and v.doneToday >= v.ofToday and "good" or nil),
                   quiet = v.ofToday > 0 and v.doneToday >= v.ofToday and v.behindN == 0 or nil }
    return L.SUM_PIN:format(v.doneToday, v.ofToday), tile
end

-- The writ ids the plan hands in today, for the Today tab and the guide.
function ns.PinTodayIds()
    local pin = ns.PinFor()
    if not pin then return nil end
    local today, ids = ns.PinDay(pin), {}
    for _, c in ipairs(pin.copies) do
        if pending(c) and c.day == today and c.kind == "writ" then ids[c.id] = (ids[c.id] or 0) + 1 end
    end
    return ids, pin
end
