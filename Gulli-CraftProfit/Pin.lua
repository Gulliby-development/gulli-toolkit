-- A pinned route: the recipes and the sources a route had when the player started on it, kept
-- in the saved variables. While a route is pinned every calculation plans the same recipes again
-- from the stock as it is now (Core.lua reads P.pin), so buying or crafting along it, a price
-- that moved or a pattern that was bought never changes the way. One pinned route per character
-- and profession, at most ns.PIN_MAX in all; the simulation saves one per profession by a button.
-- Pure rules but for the few game reads at the top; PinUI.lua shows them.

local _, ns = ...

ns.PIN_MAX = 10      -- pinned routes that still go on, on the whole account
ns.PIN_DONE = 5      -- finished ones kept in the list
ns.PIN_SAME = 0.05   -- a new calculation this close to the pinned route is "no real difference"
ns.PIN_ICON = "Interface\\Icons\\INV_Misc_Map_01"

local function copy(t)
    local c = {}
    for k, v in pairs(t or {}) do c[k] = v end
    return c
end
local function now() return time and time() or 0 end

-- Who the character is: the GUID (a realm name may be empty on WoW Forever), else the name.
function ns.PinMe()
    local guid = UnitGUID and UnitGUID("player")
    if type(guid) == "string" and guid ~= "" then return guid end
    return (UnitName and UnitName("player")) or "?"
end

function ns.Pins()
    if not ns.db then return {} end
    ns.db.pins = ns.db.pins or {}
    return ns.db.pins
end

function ns.PinKey(state)
    if state.sim then return "sim|" .. tostring(ns.sim and ns.sim.line) end
    return ns.PinMe() .. "|" .. tostring(state.name)
end

function ns.PinFind(key)
    for _, p in ipairs(ns.Pins()) do if p.key == key then return p end end
end

-- How many routes still go on.
function ns.PinCount()
    local n = 0
    for _, p in ipairs(ns.Pins()) do if not p.done then n = n + 1 end end
    return n
end

-- The route is walked: it stays in the list as finished, the oldest finished ones go.
function ns.PinFinish(pin)
    pin.done = now()
    pin.skill = pin.to
    local pins, done = ns.Pins(), 0
    for i = 1, #pins do if pins[i].done then done = done + 1 end end
    for i = #pins, 1, -1 do
        if done > ns.PIN_DONE and pins[i].done and pins[i] ~= pin then
            pins[i].gone = true
            table.remove(pins, i)
            done = done - 1
        end
    end
end

-- The pinned route a calculation of `state` follows, or nil. A simulation follows only the one
-- it saved or was opened from; a real profession the one of this character and profession.
function ns.PinFor(state)
    if not ns.db or not state then return nil end
    if state.sim then
        local p = ns.sim and ns.sim.pin
        return (p and not p.gone) and p or nil
    end
    local pin = ns.PinFind(ns.PinKey(state))
    if not pin or pin.done then return nil end
    if (state.skill or 0) >= pin.to then ns.PinFinish(pin); return nil end
    return pin
end

-- The pinned route of the profession the window shows, without reading the whole profession.
function ns.PinHere()
    if ns.view.pin and not ns.view.pin.gone then return ns.view.pin end
    local st = ns.Skill and ns.Skill()
    return st and ns.PinFor(st) or nil
end

-- The settings a pinned route is planned with: the ones it was pinned with, its target, its
-- time weight, and the pin itself for the planner.
function ns.PinPrefs(pin)
    local saved = pin.prefs
    if pin.sim and ns.sim then saved = ns.sim.prefs end
    local P = ns.Prefs(saved)
    P.target, P.level, P.w, P.pin = pin.to, true, pin.w, pin
    return P
end

-- The recipe the pinned route crafts at skill s, or nil where it had none.
function ns.PinRecipeAt(pin, s)
    for _, sg in ipairs(pin.segs or {}) do
        if sg.from <= s and s < sg.to then return sg.rid end
    end
end

-- A recipe of the pinned route that the game now shows grey where the route still crafts it:
-- the colours the profession window saved since the plan (`obs`, `grey`) against each stretch
-- that is not done yet. Its recipe id, else nil. The route is then calculated again, and
-- planWith passes over a pinned recipe that can no longer take the point.
function ns.PinGreyed(pin, prof)
    if not (pin and prof and prof.recipes and ns.RecipeSkill) then return nil end
    local skill = prof.skill or 0
    for _, sg in ipairs(pin.segs or {}) do
        local s = math.max(sg.from, skill)
        local rec = prof.recipes[sg.rid]
        if s < sg.to and rec then
            local sk = ns.RecipeSkill(sg.rid, rec)
            if sk and sk[3] and ns.Chance({ skill = sk }, s) <= 0 then return sg.rid end
        end
    end
end

local function buyKey(l) return l.recipe and ("r" .. tostring(l.recipe)) or ("i" .. tostring(l.id)) end
local function buyStop(n)
    return (n.kind == "ah" and n.title == "STOP_AH_BUY") or (n.kind == "vendor" and n.title == "STOP_VENDOR_BUY")
end
ns.PinBuyStop = buyStop

local function totals(pin)
    local spent, left, planLeft, haveN, ofN = 0, 0, 0, 0, 0
    pin.leftList = {}
    for _, b in pairs(pin.buys) do
        ofN = ofN + 1
        if b.left <= 0 then haveN = haveN + 1 end
        spent = spent + (b.n - b.left) * (b.price or 0)
        left = left + b.left * (b.now or b.price or 0)
        planLeft = planLeft + b.left * (b.price or 0)
        if b.left > 0 then pin.leftList[#pin.leftList + 1] = { name = b.name, n = b.left, id = b.id } end
    end
    table.sort(pin.leftList, function(a, b) return tostring(a.name) < tostring(b.name) end)
    pin.spent, pin.left, pin.planLeft, pin.haveN, pin.ofN = spent, left, planLeft, haveN, ofN
end

-- Sets the route's purchases of the whole way (`route`: the first run's stops with the later
-- runs' buys in them) beside what the pin had: each line gets `pinOf` (units the way buys in
-- all), `pinHave` (of them not to buy any more) and `pinPrice` (the unit price when pinned); a
-- stop gets `bought`, the lines that are all there. A need that grew raises the line's total.
-- `shown`: the stops on the screen when they are not `route` (one run's, with `ahead` off).
function ns.PinSync(pin, route, state, shown)
    pin.buys = pin.buys or {}
    local seen = {}
    for _, node in ipairs(route or {}) do
        if buyStop(node) then
            for _, l in ipairs(node.lines or {}) do
                local key = buyKey(l)
                local b = pin.buys[key]
                if not b then
                    b = { n = l.n, price = l.price or 0, name = l.pname or l.name, id = l.id or l.pattern, recipe = l.recipe, kind = node.kind }
                    pin.buys[key] = b
                end
                if l.n > b.n then b.n = l.n end
                b.left, b.now, b.kind = l.n, l.price or b.price, node.kind
                if not b.name or b.name:sub(1, 1) == "#" then b.name = l.pname or l.name end
                seen[key] = true
            end
        end
    end
    for key, b in pairs(pin.buys) do if not seen[key] then b.left = 0 end end
    -- the stops on the screen (the whole way's, or with `ahead` off one run's)
    for _, node in ipairs(shown or route or {}) do
        if buyStop(node) then
            for _, l in ipairs(node.lines or {}) do
                local b = pin.buys[buyKey(l)]
                if b then l.pinOf, l.pinHave, l.pinPrice = b.n, b.n - b.left, b.price end
            end
            node.bought = {}
            local keys = {}
            for key, b in pairs(pin.buys) do if b.left <= 0 and b.kind == node.kind then keys[#keys + 1] = key end end
            table.sort(keys)
            for _, key in ipairs(keys) do node.bought[#node.bought + 1] = pin.buys[key] end
        end
    end
    totals(pin)
    if state then pin.skill = state.skill end
    return pin
end

-- A saved simulation: its shopping list of the whole way, ticked off by what its buttons bought.
local function syncSim(pin, v)
    local route = ns.SimShopping(v)
    local prog = ns.SimShopProgress(route, v.state)
    pin.buys = {}
    for i, node in ipairs(route) do
        for k, l in ipairs(node.lines or {}) do
            local e = prog[i] and prog[i].lines[k]
            pin.buys[buyKey(l)] = { n = l.n, left = e and e.left or l.n, price = l.price or 0, now = l.price or 0,
                                    name = l.pname or l.name, id = l.id or l.pattern, recipe = l.recipe, kind = node.kind }
        end
    end
    totals(pin)
    pin.skill = pin.from
end

-- After a result is shown: the pin's numbers for the list of routes.
function ns.PinNote(v)
    local pin = v.pin
    if not pin or not v.state then return end
    if pin.sim and v.state.sim and v.legs then syncSim(pin, v) end
end

-- The numbers of the pinned route as they stand now: what came into the bags since the plan
-- counts at once. { spent, left, planLeft, haveN, ofN, skill, from, to }.
function ns.PinStatus(v)
    v = v or ns.view
    local pin = v.pin
    if not pin then return nil end
    local out = { spent = pin.spent or 0, left = pin.left or 0, planLeft = pin.planLeft or 0, haveN = pin.haveN or 0,
                  ofN = pin.ofN or 0, from = pin.from, to = pin.to, skill = pin.skill or pin.from }
    if not pin.sim and v.state and not v.state.sim then
        local prof = ns.char and ns.char.profs and ns.char.profs[pin.prof]
        if prof and prof.skill then out.skill = prof.skill end
        if (v.leg or 1) == 1 and ns.RunProgress then
            local prog = ns.RunProgress()
            for i, node in ipairs(v.route or {}) do
                if buyStop(node) then
                    for k, l in ipairs(node.lines or {}) do
                        local e = prog[i] and prog[i].lines[k]
                        if e and e.got > 0 and l.pinOf then
                            out.spent = out.spent + e.got * (l.pinPrice or l.price or 0)
                            out.left = out.left - e.got * (l.price or 0)
                            out.planLeft = out.planLeft - e.got * (l.pinPrice or l.price or 0)
                            if e.done then out.haveN = out.haveN + 1 end
                        end
                    end
                end
            end
        end
    end
    out.left, out.planLeft = math.max(0, out.left), math.max(0, out.planLeft)
    return out
end

-- Pins the route the window shows. Returns the pin, or nil and why not: "none" (nothing to
-- pin: no result, a profit route, the runs still being built), "full" (ns.PIN_MAX routes go on).
function ns.PinNow(auto)
    local v = ns.view
    if v.pin and not v.pin.gone then return v.pin end
    if not ns.db or not v.state or not v.plan or v.plan.earn or ns.EARN[v.mode or ""] or not v.legs then return nil, "none" end
    local full = v.plan.full or v.plan
    local sim = v.state.sim and ns.sim or nil
    if v.state.sim and not sim then return nil, "none" end
    local pin = { at = now(), prof = v.state.name, icon = v.state.icon, from = v.state.skill, to = full.target, skill = v.state.skill,
                  mode = v.mode, w = full.w, auto = auto or nil, segs = {}, how = {}, rids = {}, buys = {} }
    -- the recipes stretch by stretch, as the runs of the way craft them
    local plans = {}
    for _, l in ipairs(v.legs) do if l.plan and not l.unknown then plans[#plans + 1] = { l.plan, l.state or v.state } end end
    if #plans == 0 then plans[1] = { full, v.state } end
    for _, e in ipairs(plans) do
        local p, st = e[1], e[2]
        for _, sg in ipairs(p.segs or {}) do
            local last = pin.segs[#pin.segs]
            if last and last.rid == sg.rid and last.to == sg.from then last.to = sg.to
            else pin.segs[#pin.segs + 1] = { rid = sg.rid, from = sg.from, to = sg.to, name = (st.recipes[sg.rid] or {}).name } end
            pin.rids[sg.rid] = true
        end
        for rid in pairs(p.buyRecipes or {}) do pin.rids[rid] = true end
        -- where each item came from: made, or bought
        for rid in pairs(p.prep or {}) do
            pin.rids[rid] = true
            local out = (st.recipes[rid] or {}).out
            if out then pin.how[out] = "craft" end
        end
        for id in pairs(p.ahBuy or {}) do pin.how[id] = pin.how[id] or "buy" end
        for id in pairs(p.vendorBuy or {}) do pin.how[id] = pin.how[id] or "buy" end
    end
    if #pin.segs == 0 then return nil, "none" end
    -- it goes as far as its last stretch: a target no recipe reaches is not waited for
    pin.to = math.min(pin.to or 0, pin.segs[#pin.segs].to)
    if pin.to <= pin.from then return nil, "none" end
    if sim then
        pin.key = "sim|" .. tostring(sim.line)
        pin.sim = { line = sim.line, from = sim.from, to = sim.to, goal = sim.goal, empty = sim.empty,
                    skip = copy(sim.skip), gather = copy(sim.gather) }
        pin.prefs = copy(sim.prefs)
        pin.icon = ns.SIM_PROF_ICON and ns.SIM_PROF_ICON[sim.line] or pin.icon
        sim.bought = sim.bought or {}
        pin.bought = sim.bought
    else
        pin.key = ns.PinKey(v.state)
        pin.guid = ns.PinMe()
        pin.who = UnitName and UnitName("player") or "?"
        pin.class = UnitClass and select(2, UnitClass("player")) or nil
        pin.prefs = copy(ns.SavedPrefs())
    end
    local pins = ns.Pins()
    local others = 0
    for _, p in ipairs(pins) do if not p.done and p.key ~= pin.key then others = others + 1 end end
    if others >= ns.PIN_MAX then return nil, "full" end
    -- the route this one replaces (the same character and profession, or the same simulation)
    for i = #pins, 1, -1 do
        if pins[i].key == pin.key then pins[i].gone = true; table.remove(pins, i) end
    end
    table.insert(pins, 1, pin)
    v.pin = pin
    if sim then sim.pin = pin; ns.PinNote(v)
    else v.route = ns.LegRoute(v) end
    return pin
end

-- Takes a pinned route away (also a finished one from the list). The result on the screen
-- stays, marked outdated: the next calculation is free again.
function ns.Unpin(pin)
    pin = pin or ns.view.pin
    if not pin then return false end
    pin.gone = true
    local pins = ns.Pins()
    for i = #pins, 1, -1 do if pins[i] == pin then table.remove(pins, i) end end
    if ns.sim and ns.sim.pin == pin then ns.sim.pin = nil end
    for _, v in pairs(ns.views or {}) do if v.pin == pin then v.pin = nil end end
    local v = ns.view
    if v.pin == pin then
        v.pin, v.compare = nil, nil
        if v.state and v.plan then
            if not v.state.sim then v.route = ns.LegRoute(v); v.stale = v.stale or true end
        end
    end
    return true
end

-- The route pins itself when the player starts on it: the first purchase or craft. Never in
-- the simulation, never with the switch off, and not again in this session after Undo.
ns.pinUndone = {}

-- The recipe is one the route on the screen crafts (a stretch of the skill or an intermediate).
function ns.PinPartOf(v, rid)
    local full = v.plan and (v.plan.full or v.plan)
    if not full or not rid then return false end
    if (full.prep or {})[rid] or (v.plan.prep or {})[rid] then return true end
    for _, sg in ipairs(full.segs or {}) do if sg.rid == rid then return true end end
    return false
end
function ns.AutoPin()
    local v = ns.view
    if ns.sim or not ns.db or not v.state or v.state.sim or v.pin then return nil end
    if not ns.Prefs(ns.SavedPrefs()).autoPin then return nil end
    local key = ns.PinKey(v.state)
    if ns.pinUndone[key] then return nil end
    local pin = ns.PinNow(true)
    if pin and ns.PinToast then ns.PinToast(pin) end
    return pin
end

function ns.PinUndo(pin)
    if not pin or pin.gone then return end
    ns.pinUndone[pin.key] = true
    ns.Unpin(pin)
    if ns.Refresh then ns.Refresh() end
end

-- ---------- is there a better route ----------

local function side(x)
    local full = x.plan.full or x.plan
    local buys = 0
    for _ in pairs(full.ahBuy or {}) do buys = buys + 1 end
    for _ in pairs(full.vendorBuy or {}) do buys = buys + 1 end
    for _ in pairs(full.buyRecipes or {}) do buys = buys + 1 end
    return { full = full, spend = full.spend or 0, income = full.income or 0, cost = (full.spend or 0) - (full.income or 0),
             crafts = ns.Ceil(full.crafts or 0), reached = full.reached, buys = buys }
end

-- The pinned route of view `v` beside a new calculation `out` (built without the pin). What is
-- in the bags counts as paid for in both, since both are planned from the stock as it is.
-- { mine, fresh, rows, diff (what the new one saves), verdict = "better"|"same"|"worse", unused }.
function ns.PinCompare(v, out)
    if not v.plan or not out or not out.plan or not out.state then return nil end
    local c = { out = out, mine = side(v), fresh = side(out), rows = {} }
    local a, b = c.mine.full, c.fresh.full
    local function name(st, rid) return (st.recipes[rid] or {}).name or tostring(rid) end
    -- the stretches where the two craft another recipe
    local function at(p, s)
        for _, sg in ipairs(p.segs or {}) do if sg.from <= s and s < sg.to then return sg.rid end end
    end
    local cur
    for s = v.state.skill, math.max(a.reached or 0, b.reached or 0) - 1 do
        local ra, rb = at(a, s), at(b, s)
        if ra ~= rb then
            if cur and cur.a == ra and cur.b == rb and cur.to == s then cur.to = s + 1
            else
                cur = { kind = "recipe", from = s, to = s + 1, a = ra, b = rb,
                        nameA = ra and name(v.state, ra) or nil, nameB = rb and name(out.state, rb) or nil }
                c.rows[#c.rows + 1] = cur
            end
        else
            cur = nil
        end
    end
    -- what the new one does not buy, and what it buys more
    local function bought(p, id) return ns.Ceil(((p.ahBuy or {})[id] or 0) + ((p.vendorBuy or {})[id] or 0)) end
    local ids, seen = {}, {}
    for _, p in ipairs({ a, b }) do
        for _, m in ipairs({ p.ahBuy or {}, p.vendorBuy or {} }) do
            for id in pairs(m) do if not seen[id] then seen[id] = true; ids[#ids + 1] = id end end
        end
    end
    table.sort(ids, function(x, y) return tostring(x) < tostring(y) end)
    for _, id in ipairs(ids) do
        local na, nb = bought(a, id), bought(b, id)
        local it = out.state.items[id] or v.state.items[id] or {}
        if na > nb then c.rows[#c.rows + 1] = { kind = "drop", id = id, name = it.name or tostring(id), n = na - nb }
        elseif nb > na then c.rows[#c.rows + 1] = { kind = "add", id = id, name = it.name or tostring(id), n = nb - na } end
    end
    -- bought for the pinned route, of no use to the new one
    c.unused = 0
    local keys = {}
    for key in pairs((v.pin and v.pin.buys) or {}) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local x = v.pin.buys[key]
        local have = x.n - (x.left or 0)
        if x.id and not x.recipe and have > 0 then
            local uses = ns.Ceil(((b.bags or {})[x.id] or 0) + ((b.bank or {})[x.id] or 0))
            local mine = ns.Ceil(((a.bags or {})[x.id] or 0) + ((a.bank or {})[x.id] or 0))
            local extra = math.min(have, mine) - uses
            if extra > 0 then
                c.unused = c.unused + extra * (x.price or 0)
                c.rows[#c.rows + 1] = { kind = "unused", id = x.id, name = x.name, n = extra }
            end
        end
    end
    if c.mine.crafts ~= c.fresh.crafts then c.rows[#c.rows + 1] = { kind = "crafts", a = c.mine.crafts, b = c.fresh.crafts } end
    c.diff = c.mine.cost - c.fresh.cost
    local short = (c.fresh.reached or 0) < (c.mine.reached or 0)
    local small = math.max(100, ns.PIN_SAME * math.max(math.abs(c.mine.cost), c.mine.spend))
    if short or c.diff <= -small then c.verdict = "worse"
    elseif c.diff < small then c.verdict = "same"
    else c.verdict = "better" end
    return c
end

-- Goes over to the new calculation of the comparison and pins it.
function ns.PinSwitch()
    local v = ns.view
    local c = v.compare
    if not c or not v.pin then return false end
    ns.Unpin(v.pin)
    ns.ApplyResult(c.out)
    ns.PinNow(false)
    return true
end

-- ---------- the list of routes ----------

-- What a row of the list can do for the character who looks at it: "here" (it is the one
-- shown), "prof" (this character's other profession), "sim" (a saved simulation: open it),
-- nil (another character's: only to look at).
function ns.PinOpens(pin)
    if pin.done then return nil end
    if ns.view.pin == pin then return "here" end
    if pin.sim then return "sim" end
    if pin.guid == ns.PinMe() and ns.char and ns.char.profs and ns.char.profs[pin.prof] then
        return (not ns.sim and ns.char.current == pin.prof) and "here" or "prof"
    end
    return nil
end

-- The saved simulation this character could walk for real: its own profession of that line,
-- with the skill inside the route. Returns the profession { name, skill }.
function ns.PinAdoptable(pin)
    if not pin.sim or pin.done or not ns.SimOwn then return nil end
    local own = ns.SimOwn(pin.sim.line)
    if not own or (own.skill or 0) < pin.from or (own.skill or 0) >= pin.to then return nil end
    return own
end

-- The rows: { head = "active"|"done" } and { pin, opens, adopt, progress, skill }.
function ns.PinRows()
    local rows, done = {}, {}
    local any = false
    for _, p in ipairs(ns.Pins()) do
        if p.done then done[#done + 1] = p
        else
            if not any then any = true; rows[#rows + 1] = { head = "active" } end
            local skill = p.skill or p.from
            if not p.sim and p.guid == ns.PinMe() and ns.char and ns.char.profs and ns.char.profs[p.prof] then
                skill = ns.char.profs[p.prof].skill or skill
            end
            rows[#rows + 1] = { pin = p, opens = ns.PinOpens(p), adopt = ns.PinAdoptable(p) ~= nil, skill = skill,
                                progress = math.max(0, math.min(1, (skill - p.from) / math.max(1, p.to - p.from))) }
        end
    end
    if #done > 0 then
        rows[#rows + 1] = { head = "done" }
        for _, p in ipairs(done) do rows[#rows + 1] = { pin = p, progress = 1, skill = p.to } end
    end
    return rows
end

-- Opens a saved simulation again: its conditions, its settings and what was bought for it.
function ns.PinOpenSim(pin)
    if not pin.sim or not ns.SimOpen then return false end
    local sim = ns.sim or ns.SimOpen()
    if not sim then return false end
    local c = pin.sim
    ns.SimSet({ line = c.line })
    ns.SimSet({ from = c.from, to = c.to, empty = c.empty })
    sim.from, sim.to, sim.goal = c.from, c.to, c.goal
    sim.prefs, sim.skip, sim.gather = copy(pin.prefs), copy(c.skip), copy(c.gather)
    pin.bought = pin.bought or {}
    sim.bought, sim.pin = pin.bought, pin
    if not ns.SimStart() then sim.pin = nil; return false end
    return true
end

-- A saved simulation becomes this character's own pinned route: the same recipes and sources
-- from the skill the character has. The window then calculates it.
function ns.PinAdopt(pin)
    local own = ns.PinAdoptable(pin)
    if not own or not ns.db then return nil end
    local key = ns.PinMe() .. "|" .. own.name
    local pins = ns.Pins()
    local others = 0
    for _, p in ipairs(pins) do if not p.done and p.key ~= key then others = others + 1 end end
    if others >= ns.PIN_MAX then return nil, "full" end
    for i = #pins, 1, -1 do if pins[i].key == key then pins[i].gone = true; table.remove(pins, i) end end
    local mine = { key = key, at = now(), prof = own.name, icon = own.icon or pin.icon, from = own.skill, to = pin.to, skill = own.skill,
                   mode = pin.mode, w = pin.w, segs = {}, how = copy(pin.how), rids = copy(pin.rids), buys = {},
                   guid = ns.PinMe(), who = UnitName and UnitName("player") or "?",
                   class = UnitClass and select(2, UnitClass("player")) or nil, prefs = copy(pin.prefs), from_sim = true }
    for _, sg in ipairs(pin.segs) do mine.segs[#mine.segs + 1] = copy(sg) end
    -- the simulation's own fixed settings are not the character's
    mine.prefs.target, mine.prefs.level = pin.to, true
    table.insert(pins, 1, mine)
    return mine
end
