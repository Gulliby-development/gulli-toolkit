-- The simulation mode: any profession from any skill, planned like the character's own, for the
-- question "is this profession worth levelling". The simulated profession is built from the
-- recipe book (Data.book, every recipe not learned), the settings are a copy of the player's,
-- and everything lives in ns.sim: memory only, never a saved variable, gone on exit or reload.

local _, ns = ...

-- The professions offered, by skill line, in the order of the tiles (Mining is its smelting).
ns.SIM_LINES = { 171, 164, 333, 202, 165, 197, 185, 129, 186 }
-- The mark of everything simulated: one icon and one colour, used for nothing else.
ns.SIM_ICON = "Interface\\Icons\\INV_Misc_Orb_03"
ns.SIM_COLOR = { 0.56, 0.59, 0.96, 1 }
ns.SIM_PROF_ICON = {
    [171] = "Interface\\Icons\\Trade_Alchemy", [164] = "Interface\\Icons\\Trade_BlackSmithing",
    [333] = "Interface\\Icons\\Trade_Engraving", [202] = "Interface\\Icons\\Trade_Engineering",
    [165] = "Interface\\Icons\\INV_Misc_ArmorKit_17", [197] = "Interface\\Icons\\Trade_Tailoring",
    [185] = "Interface\\Icons\\INV_Misc_Food_15", [129] = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
    [186] = "Interface\\Icons\\Trade_Mining",
}
-- The skill the conditions start with and may reach.
ns.SIM_MAX = 300
-- Settings that mean nothing for a new character's whole way, fixed while the simulation runs:
-- it always levels, learns from the trainer (every recipe is still to learn) and has no crafts
-- limit (owner's decision of 2026-11-23: the question is the cost, not the clicks).
ns.SIM_FIXED = { level = true, trainer = true, maxCrafts = -1 }
-- The settings the simulation does not read: the fixed ones, the buying of later runs (the
-- shopping list is always the whole way) and the profit runs' (the simulation plans none).
-- The Settings tab dims them.
ns.SIM_IGNORED = { level = true, trainer = true, maxCrafts = true, ahead = true, minGain = true, maxBuy = true }
-- The leg of the shopping list: everything the whole way buys, bought here for another character.
ns.SIM_SHOP = -1

local function copy(t)
    local c = {}
    for k, v in pairs(t or {}) do c[k] = v end
    return c
end

-- ---------- wrappers ----------

local function spellName(id)
    local n = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    if type(n) ~= "string" or n == "" then n = GetSpellInfo and GetSpellInfo(id) end
    return type(n) == "string" and n ~= "" and n or nil
end
local function spellIcon(id)
    local t = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
    if not t and GetSpellTexture then t = GetSpellTexture(id) end
    return t
end

-- The profession's name in the client's language: the game's own, else ours.
function ns.SimProfName(line)
    local T = C_TradeSkillUI
    if T and T.GetTradeSkillDisplayName then
        local ok, n = pcall(T.GetTradeSkillDisplayName, line)
        if ok and type(n) == "string" and n ~= "" then return n end
    end
    return ns.L["PROF_" .. line] or tostring(line)
end

-- The character's own profession of that line (name, skill, cap), or nil.
function ns.SimOwn(line)
    local name = ns.SimProfName(line)
    for _, p in ipairs(ns.Professions and ns.Professions() or {}) do
        if p.name == name or (ns.SkillLineOf and ns.SkillLineOf(p.name) == line) then return p end
    end
end

-- ---------- the simulated profession ----------

-- A recipe's name: the spell's, else the name of what it makes (asked for when not loaded yet).
local function recipeName(spell, out)
    return spellName(spell) or (out and out > 0 and ns.NameFor(out)) or ("#" .. spell)
end

-- The profession of `line` at skill `from` as Scan.lua saves one: every recipe of the book,
-- none learned. `book` of a recipe is { learn, yellow, grey }.
function ns.SimBook(line, from)
    local rows = ns.Data and ns.Data.book and ns.Data.book[line]
    if not rows then return nil end
    local prof = { skill = from, cap = 0, icon = ns.SIM_PROF_ICON[line], sim = true, recipes = {} }
    for _, row in ipairs(rows) do
        local spell, out = row[1], row[2] > 0 and row[2] or nil
        local r = {}
        for k = 9, #row, 2 do r[row[k]] = row[k + 1] end
        prof.recipes[spell] = { name = recipeName(spell, out), learned = false, out = out, count = row[3],
                                icon = out and ns.ItemIcon(out) or spellIcon(spell), r = r,
                                book = { row[4], row[5], row[6] }, free = row[7] == 1 or nil, pattern = row[8] == 1 or nil }
    end
    return prof
end

-- The recipes of `line` whose name has `text` (or whose spell or item id it is), for the goal
-- box: { { recipe, name, learn, out } }, the lowest learn level first, at most `max`.
function ns.SimFind(line, text, max)
    local rows = ns.Data and ns.Data.book and ns.Data.book[line]
    local out = {}
    text = type(text) == "string" and text:match("^%s*(.-)%s*$") or ""
    if not rows or text == "" then return out, 0 end
    local gone = ns.Data.gone or {}
    local id = tonumber(text) or tonumber(text:match("item:(%d+)")) or tonumber(text:match("enchant:(%d+)"))
    for _, row in ipairs(rows) do
        if not gone[row[1]] then
            local name = recipeName(row[1], row[2] > 0 and row[2] or nil)
            if (id and (row[1] == id or row[2] == id)) or (not id and ns.Matches(name, text)) then
                out[#out + 1] = { recipe = row[1], name = name, learn = row[4], out = row[2] > 0 and row[2] or nil }
            end
        end
    end
    table.sort(out, function(a, b) if a.learn ~= b.learn then return a.learn < b.learn end return a.name < b.name end)
    local all = #out
    for i = all, (max or all) + 1, -1 do out[i] = nil end
    return out, all
end

-- One recipe of the book by its spell, as ns.SimFind gives it.
function ns.SimRecipe(line, rid)
    for _, row in ipairs(ns.Data and ns.Data.book and ns.Data.book[line] or {}) do
        if row[1] == rid then
            local out = row[2] > 0 and row[2] or nil
            return { recipe = rid, name = recipeName(rid, out), learn = row[4], out = out }
        end
    end
end

-- ---------- on and off ----------

-- The view of the real profession waits here while the simulation runs.
local stash

-- Turns the simulation on: the conditions are still to choose (ns.sim.prof is nil until
-- ns.SimStart). The settings, the avoided crafts and the gathered items are copies.
function ns.SimOpen()
    if ns.sim or not ns.db then return ns.sim end
    if ns.StopCalc then ns.StopCalc() end
    stash = {}
    for k, v in pairs(ns.view) do stash[k] = v; ns.view[k] = nil end
    ns.view.route, ns.view.changed = {}, {}
    local line = 197
    -- the profession chosen in the window, when the simulation offers it
    for _, l in ipairs(ns.SIM_LINES) do
        local own = ns.SimOwn(l)
        if own and ns.char and own.name == ns.char.current then line = l end
    end
    ns.sim = { line = line, name = ns.SimProfName(line), from = 1, to = ns.SIM_MAX, goal = nil, empty = false,
               prefs = copy(ns.db.prefs), skip = copy(ns.db.skip), gather = copy(ns.db.gather), bought = {} }
    if ns.Refresh then ns.Refresh() end
    return ns.sim
end

-- The conditions of the simulation, each optional: { line, from, to, goal, empty }. A goal recipe
-- lifts the target to the skill it is learned at. Changing them drops the result.
function ns.SimSet(opts)
    local sim = ns.sim
    if not sim then return end
    if opts.line and opts.line ~= sim.line then
        sim.line, sim.name, sim.goal, sim.bought = opts.line, ns.SimProfName(opts.line), nil, {}
    end
    if opts.from then sim.from = math.max(1, math.min(ns.SIM_MAX - 1, opts.from)) end
    if opts.to then sim.to = math.max(2, math.min(ns.SIM_MAX, opts.to)) end
    if opts.empty ~= nil then sim.empty = opts.empty and true or false end
    if opts.goal ~= nil then
        sim.goal = opts.goal or nil
        local g = sim.goal and ns.SimRecipe(sim.line, sim.goal)
        if not g then sim.goal = nil
        elseif g.learn > sim.to then sim.to = math.min(ns.SIM_MAX, g.learn)
        elseif opts.goal and not opts.to then sim.to = math.max(sim.from + 1, math.min(ns.SIM_MAX, g.learn)) end
    end
    if sim.to <= sim.from then
        if opts.from and not opts.to then sim.to = math.min(ns.SIM_MAX, sim.from + 1) else sim.from = math.max(1, sim.to - 1) end
    end
    sim.prof = nil
    -- other conditions are another route: the saved one stays in the list, this one is free
    if next(opts) then sim.pin = nil end
    for k in pairs(ns.view) do ns.view[k] = nil end
    ns.view.route, ns.view.changed = {}, {}
    if ns.Refresh then ns.Refresh() end
end

-- Builds the simulated profession from the conditions; the window then calculates.
function ns.SimStart()
    local sim = ns.sim
    if not sim then return false end
    sim.prof = ns.SimBook(sim.line, sim.from)
    if not sim.prof then return false end
    sim.prefs.target, sim.prefs.level = sim.to, true
    for k in pairs(ns.view) do ns.view[k] = nil end
    ns.view.route, ns.view.changed = {}, {}
    return true
end

-- Back to the conditions, with the result dropped.
function ns.SimSetup()
    if ns.sim then ns.SimSet({}) end
end

-- Ends the simulation: everything of it is forgotten and the real profession's view is back.
function ns.SimStop()
    if not ns.sim then return false end
    if ns.StopCalc then ns.StopCalc() end
    -- the one thing a simulation may leave: a route saved by its button (Pin.lua)
    ns.simKept = ns.sim.pin ~= nil and not ns.sim.pin.gone
    ns.sim = nil
    for k in pairs(ns.view) do ns.view[k] = nil end
    for k, v in pairs(stash or {}) do ns.view[k] = v end
    stash = nil
    ns.view.route, ns.view.changed = ns.view.route or {}, ns.view.changed or {}
    -- a route unpinned from the list meanwhile
    if ns.view.pin and ns.view.pin.gone then ns.view.pin = nil; ns.view.stale = ns.view.stale or true end
    -- the profession chosen meanwhile (a profession window was opened) shows its own result
    local st = ns.view.state
    if st and ns.char and ns.char.current and st.name ~= ns.char.current then ns.SwitchView(st.name, ns.char.current) end
    if ns.SimEnded then ns.SimEnded() end
    if ns.Refresh then ns.Refresh() end
    return true
end

-- The settings changed inside the simulation, as keys (the target and the route are its own).
local OWN = { target = true, level = true, mode = true }
function ns.SimChanged()
    local out = {}
    if not ns.sim or not ns.db then return out end
    local mine, sim = ns.Prefs(ns.db.prefs), ns.Prefs(ns.sim.prefs)
    for k in pairs(ns.DEFAULTS) do
        if not OWN[k] and not ns.SIM_IGNORED[k] and mine[k] ~= sim[k] then out[#out + 1] = k end
    end
    table.sort(out)
    return out
end

-- The player's own settings again, inside the simulation.
function ns.SimRevert()
    local sim = ns.sim
    if not sim then return end
    local mode = sim.prefs.mode
    sim.prefs = copy(ns.db.prefs)
    sim.prefs.target, sim.prefs.level, sim.prefs.mode = sim.to, true, mode
    ns.Rebuild(true)
end

-- ---------- the whole way and what comes after it ----------

-- The character level the rank of that skill asks for.
function ns.SimLevel(skill)
    for _, r in ipairs(ns.RANKS) do if r[1] >= skill then return r[3] end end
    return ns.RANKS[#ns.RANKS][3]
end

-- The whole way in money: what the materials cost (bought, and own stock at what it would sell
-- for), what learning costs (recipes, patterns, ranks), what the sales bring, and the result.
function ns.SimTotals(full)
    local learn = full.learnCost or 0
    return { materials = (full.spend or 0) - learn + (full.own or 0), learn = learn, sales = full.income or 0,
             net = full.net or 0, crafts = ns.Ceil(full.crafts or 0), reached = full.reached, target = full.target,
             level = ns.SimLevel(full.reached or 1) }
end

-- The profession as it stands at the end of the way: the skill reached, and every recipe the
-- settings can get by then learned. The lists and the payback read this state.
function ns.SimAfter(state, P, full)
    local st = copy(state)
    st.skill = full and full.reached or ns.Target(state, P)
    st.cap = 0
    st.recipes = {}
    for rid, r in pairs(state.recipes) do
        local c = copy(r)
        if not c.learned and c.skill and c.skill[1] <= st.skill and ns.CanGet(c, P) then c.learned, c.taught = true, true end
        st.recipes[rid] = c
    end
    return st
end

-- What one craft of a recipe gains at the end of the way, with everything bought, and when that
-- pays the levelling back: { recipe, cost, value, how, gain, lines = { { id, n, cost } },
-- crafts, days, cd, need (the skill it is learned at), reach (the way gets there), extra (the
-- price of the recipe when the way did not buy it) }. `loss`: what the way costs (positive).
-- nil for a recipe the state lacks.
function ns.SimPayback(after, P, rid, loss, bought)
    local r = after.recipes[rid]
    if not r then return nil end
    local known = {}
    for id, x in pairs(after.recipes) do if x.learned and not x.skip then known[id] = true end end
    known[rid] = true
    local p = { recipe = rid, lines = {}, cd = r.cd, need = r.skill and r.skill[1] or nil }
    p.reach = p.need ~= nil and p.need <= after.skill
    p.src = not r.learned and r.src and r.src.t or nil
    local cost = 0
    local ids = {}
    for id in pairs(r.r) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
    for _, id in ipairs(ids) do
        local unit, how = ns.UnitCost(after, P, {}, known, id)
        p.lines[#p.lines + 1] = { id = id, n = r.r[id], cost = unit * r.r[id], how = how }
        cost = cost + unit * r.r[id]
    end
    p.cost = cost
    p.value, p.how = 0, "vendor"
    if r.out then p.value, p.how = ns.SellValue(after, P, r.out, 0) end
    p.value = p.value * (r.count or 1)
    if cost == math.huge then return p end
    p.gain = p.value - cost
    -- a recipe the way did not pay for is paid for first
    p.extra = (not (bought and bought[rid]) and r.src and (r.taught or not r.learned) and r.src.cost) or 0
    local owed = math.max(0, loss or 0) + p.extra
    if p.gain > 0 then
        p.crafts = ns.Ceil(owed / p.gain)
        if r.cd and p.crafts > 0 then p.days = ns.Ceil(p.crafts * r.cd / ns.DAY) end
    end
    return p
end

-- The recipe that gains the most per craft at the end of the way, when no goal was chosen.
function ns.SimBest(after, P)
    local best, gain
    for rid, r in pairs(after.recipes) do
        if r.learned and not r.skip and not r.other and r.out then
            local p = ns.SimPayback(after, P, rid, 0, {})
            if p and p.gain and (not gain or p.gain > gain + 1e-9 or (math.abs(p.gain - gain) <= 1e-9 and tostring(rid) < tostring(best))) then
                best, gain = rid, p.gain
            end
        end
    end
    return best
end

-- Everything the result card shows, from the current view: the totals of the whole way and the
-- payback of the goal recipe (or of the best one). nil outside a calculated simulation.
function ns.SimResult()
    local v, sim = ns.view, ns.sim
    if not sim or not v.state or not v.plan or not v.state.sim then return nil end
    local full = v.plan.full or v.plan
    local out = { totals = ns.SimTotals(full), from = v.state.skill, warn = full.warn }
    local after = ns.SimAfter(v.state, v.prefs, full)
    out.after = after
    local rid = sim.goal
    if rid and not after.recipes[rid] then rid = nil end
    out.goal = rid ~= nil
    rid = rid or ns.SimBest(after, v.prefs)
    if rid then
        local bought = {}
        for _, l in ipairs(v.legs or {}) do for id in pairs(l.plan and l.plan.buyRecipes or {}) do bought[id] = true end end
        for id in pairs(full.buyRecipes or {}) do bought[id] = true end
        out.pay = ns.SimPayback(after, v.prefs, rid, -out.totals.net, bought)
    end
    return out
end

-- ---------- buying for another character ----------

-- The shopping list of the whole way: one auction stop and one vendor stop with every line the
-- runs buy, added up (a pattern once). The player buys it here and mails it to the character
-- who levels (owner's request of 2026-11-23). Empty without a calculated simulation.
function ns.SimShopping(v)
    v = v or ns.view
    if not ns.sim or not v.state or not v.state.sim or not v.legs then return {} end
    -- ns.BuyAhead adds the buy stops of every run after the first to a route: an empty first
    local legs = { {} }
    for _, l in ipairs(v.legs) do
        if l.plan and l.state and not l.unknown then legs[#legs + 1] = l end
    end
    local route = ns.BuyAhead({}, legs)
    -- every line is for this list: no "also for the run to" note
    for _, n in ipairs(route) do for _, l in ipairs(n.lines or {}) do l.ahead = nil end end
    return route
end

-- What was bought for the list in this simulation: the AH and vendor buttons note it here, so the
-- list is ticked off whatever the bags say (the items may be in the mail already).
function ns.SimNoteBought(id, n)
    local sim = ns.sim
    if not sim or not id or not n or n <= 0 then return end
    sim.bought = sim.bought or {}
    sim.bought[id] = (sim.bought[id] or 0) + n
    if sim.pin then ns.PinNote(ns.view) end
end

-- How far the shopping list is: ns.Progress on what was bought for it.
function ns.SimShopProgress(route, state)
    local bought = ns.sim and ns.sim.bought or {}
    return ns.Progress(route, state, function(id)
        return (((state and state.items[id]) or {}).bags or 0) + (bought[id] or 0)
    end)
end

-- The shopping list is the leg shown.
function ns.SimShopOn(v)
    v = v or ns.view
    return ns.sim ~= nil and v.state ~= nil and v.state.sim ~= nil and v.leg == ns.SIM_SHOP
end
