-- The craft bar: a batch of crafts on the screen in place of the game's cast bar. What is made,
-- how many of how many, how long the rest takes and when it ends. This file keeps the batch
-- (ns.run) from the cast events and says what the bar shows (ns.BarState, ns.BarView);
-- BarUI.lua only draws it. It reads the game's casts and never crafts anything itself.

local _, ns = ...
local L = ns.L

ns.BAR_GAP = 2.5 -- seconds after a craft with no next cast: the batch stopped
ns.BAR_HALT = 0.3 -- the same once the game said the batch stopped
ns.BAR_HOLD = 5 -- seconds the end of a batch stays on the screen
ns.BAR_TICKS = 60 -- up to so many crafts the bar is cut into crafts
ns.BAR_KEYS = { bar = true, barHide = true, barOne = true }
local SAMPLE = { made = 12, of = 40, left = 84, frac = 0.3125, cast = 0.5 }

local function now() return GetTime and GetTime() or time() end
local function secret(v) return issecretvalue and issecretvalue(v) end

-- The player's own setting: the simulation has its own copy of the settings, and the bar is
-- about the crafts the character really makes.
function ns.BarPref(key)
    local p = ns.db and ns.db.prefs
    local v = p and p[key]
    if v == nil then v = ns.DEFAULTS[key] end
    return v == true
end
function ns.SetBarPref(key, on)
    if not ns.db or not ns.BAR_KEYS[key] then return end
    ns.db.prefs[key] = on and true or false
    if ns.RefreshBar then ns.RefreshBar() end
    if ns.Refresh then ns.Refresh() end
end

-- ---------- what the game says ----------

-- The cast that runs: times in seconds of the game's clock, `trade` when it is a craft.
local function castInfo()
    if not UnitCastingInfo then return nil end
    local name, _, icon, from, to, trade, id, _, spell = UnitCastingInfo("player")
    if not name or secret(name) or secret(from) or secret(to) or secret(spell) then return nil end
    from, to = tonumber(from), tonumber(to)
    if not from or not to or to <= from then return nil end
    return { name = name, icon = icon, from = from / 1000, to = to / 1000, trade = trade == true, id = id, spell = spell }
end

-- The crafts the game still repeats, this one counted; nil when it does not tell. A craft the
-- game repeats nothing after (one press of Create or Enchant) is 1.
local function recasts()
    local T = C_TradeSkillUI
    if not (T and T.GetRemainingRecasts) then return nil end
    local ok, n = pcall(T.GetRemainingRecasts)
    if not ok or secret(n) then return nil end
    n = tonumber(n)
    return n and n > 1 and n or 1
end

-- The profession of a recipe and its skill now.
local function profession(spell)
    local T = C_TradeSkillUI
    if not (T and T.GetProfessionInfoByRecipeID) then return nil end
    local ok, i = pcall(T.GetProfessionInfoByRecipeID, spell)
    if not ok or type(i) ~= "table" then return nil end
    local name = i.parentProfessionName
    if name == nil or name == "" then name = i.professionName end
    if name == nil or name == "" then return nil end
    local skill = tonumber(i.skillLevel)
    return name, skill and skill > 0 and skill or nil
end

-- The icon of what the craft makes: the item the profession window saved for the recipe, else
-- the recipe's own picture; nil leaves the spell's.
function ns.BarIcon(spell)
    for _, prof in pairs(ns.char and ns.char.profs or {}) do
        local rec = prof.recipes and prof.recipes[spell]
        if rec and rec.out and ns.ItemIcon then return ns.ItemIcon(rec.out) end
    end
    local T = C_TradeSkillUI
    if T and T.GetRecipeInfo then
        local ok, i = pcall(T.GetRecipeInfo, spell)
        if ok and type(i) == "table" and i.icon then return i.icon end
    end
    return nil
end

-- How many more crafts the bags hold reagents for, from the recipe the profession window saved;
-- nil for a recipe it never saw.
function ns.BarMats(spell)
    local f = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not f or not ns.char then return nil end
    for _, prof in pairs(ns.char.profs or {}) do
        local rec = prof.recipes and prof.recipes[spell]
        if rec and rec.r and next(rec.r) then
            local can
            for id, need in pairs(rec.r) do
                local have = tonumber(f(id)) or 0
                local k = math.floor(have / math.max(1, need))
                can = can and math.min(can, k) or k
            end
            return can
        end
    end
    return nil
end

-- ---------- the batch ----------

-- { spell, name, icon, of, made, known (the game told how many), state = run|stop|done,
--   began, first, last, starts (the casts started and when), cast = { from, to, id }, len,
--   doneAt, haltAt, endAt, took, prof, skill0 }
ns.run = nil

local function halt(r, state)
    r.state, r.cast = state, nil
    r.endAt = now()
    r.took = r.endAt - r.began
end

-- A cast of the player began.
function ns.BarCastStart()
    local c = castInfo()
    local r = ns.run
    if not c or not c.trade then
        -- another spell while the batch waits for its next craft: the batch is over
        if c and r and r.state == "run" then halt(r, r.made > 0 and "stop" or "done"); if r.made == 0 then ns.run = nil end end
        return c ~= nil and r ~= nil
    end
    local left = recasts()
    local b = ns.batch
    if not left and b and ns.CastRecipe and ns.CastRecipe(c.spell) == b.rid then left = b.of - b.made end
    local t = now()
    -- The same batch goes on only while the game still repeats it: a craft the player starts
    -- by hand after the last one is a batch of its own, however soon it comes. Without a count
    -- from the game the next cast in time is all there is to go by.
    local same = r and r.spell == c.spell and r.state == "run"
    if same and r.known then same = (r.leftAt or 0) - (r.cast and 1 or 0) > 0 end
    if not same then
        r = { spell = c.spell, name = c.name, icon = ns.BarIcon(c.spell) or c.icon, of = left or 1, made = 0, known = left ~= nil,
              began = t, starts = 0 }
        r.prof, r.skill0 = profession(c.spell)
        ns.run = r
    else
        -- crafts nobody reported as made still count: the game repeats fewer than it did, or
        -- the cast before ran to its end
        if left and r.leftAt and left < r.leftAt then
            r.made = r.made + (r.leftAt - left)
        elseif r.cast and c.from >= r.cast.to - 0.5 then
            r.made = r.made + 1
        end
        if left then r.of, r.known = r.made + left, true end
    end
    r.leftAt = left
    if r.made >= r.of then r.of = r.made + 1 end
    r.state, r.endAt, r.took, r.haltAt = "run", nil, nil, nil
    r.starts = r.starts + 1
    r.first = r.first or c.from
    r.last = c.from
    r.len = c.to - c.from
    r.cast = { from = c.from, to = c.to, id = c.id }
    return true
end

-- A craft was made.
function ns.BarCastDone(spell, id)
    local r = ns.run
    if not r or r.state ~= "run" or not r.cast then return false end
    -- the game may name the made craft by another spell id than the cast: the cast id tells too
    local mine = r.cast.id
    local byId = mine ~= nil and id ~= nil and not secret(mine) and not secret(id) and id == mine
    if not byId and (secret(spell) or spell ~= r.spell) then return false end
    r.made, r.cast, r.doneAt = r.made + 1, nil, now()
    if r.leftAt then r.leftAt = r.leftAt - 1 end
    if r.known and r.made >= r.of then halt(r, "done") end
    return true
end

-- The cast was cut or failed: the batch stops there.
function ns.BarCastBreak(id, spell)
    local r = ns.run
    if not r or r.state ~= "run" or not r.cast or secret(spell) or spell ~= r.spell then return false end
    local mine = r.cast.id
    if mine ~= nil and id ~= nil and not secret(mine) and not secret(id) and id ~= mine then return false end
    halt(r, "stop")
    return true
end

-- The game says its batch stopped: no need to wait long for a next cast.
function ns.BarHalted()
    local r = ns.run
    if r and r.state == "run" then r.haltAt = now() end
end

-- Whether a batch belongs on the screen: the switch, and one craft alone only when asked.
local function wanted(r)
    if not ns.BarPref("bar") then return false end
    return r.of > 1 or r.made > 1 or ns.BarPref("barOne")
end

-- "run", "stop", "done", or nil when the bar has nothing to show. Time alone ends a batch that
-- waits for a cast that does not come, and takes a finished one away.
function ns.BarState(t)
    local r = ns.run
    if not r then return nil end
    t = t or now()
    if r.state == "run" then
        local since
        if not r.cast then since = t - (r.doneAt or r.began)
        elseif t > r.cast.to then since = t - r.cast.to end
        if since and (since > ns.BAR_GAP or (not r.cast and r.haltAt and t - r.haltAt > ns.BAR_HALT)) then
            -- a cast that ran to its end and was never cut was made, also when nobody said so
            if r.cast then r.made, r.cast = r.made + 1, nil end
            if r.made == 0 then ns.run = nil; return nil end
            halt(r, (r.made >= r.of or not r.known) and "done" or "stop")
        end
    end
    if r.state ~= "run" and t - r.endAt > ns.BAR_HOLD then ns.run = nil; return nil end
    if not wanted(r) then return nil end
    return r.state
end

-- Seconds until the batch ends: the cast that runs, then the crafts after it at the pace the
-- batch really goes (the time from cast to cast, which has the pause between two crafts in it).
function ns.BarLeft(r, t)
    if not r.known or not r.len then return nil end
    t = t or now()
    local per = r.len
    if r.starts > 1 and r.last > r.first then per = math.max(per, (r.last - r.first) / (r.starts - 1)) end
    local cur = r.cast and math.max(0, math.min(r.len, r.cast.to - t)) or 0
    local after = r.of - r.made - (r.cast and 1 or 0)
    return cur + math.max(0, after) * per
end

-- "24 s", "12 min 40 s", "1 h 21 min": a long batch shows no seconds.
function ns.BarSpan(s)
    s = math.max(0, math.ceil(s or 0))
    if s >= 3600 then
        local m = math.ceil(s / 60)
        return L.BAR_HM:format(math.floor(m / 60), m % 60)
    elseif s >= 60 then
        return L.BAR_MS:format(math.floor(s / 60), s % 60)
    end
    return L.BAR_S:format(s)
end

local function clock(left)
    return date and date("%H:%M", time() + math.floor(left + 0.5)) or ""
end

-- What the bar says: { icon, name, made, of (nil: unknown), sub, left, frac, cast, ticks,
-- tone (nil|warn|good), foot, right }. state nil: the sample for the Unlock mode.
function ns.BarView(state, t)
    local r = state and ns.run
    if not r then
        return { icon = ns.OPT_ICON.bar, name = L.P_bar, made = SAMPLE.made, of = SAMPLE.of, sub = "",
                 left = ns.BarSpan(SAMPLE.left), frac = SAMPLE.frac, cast = SAMPLE.cast, ticks = SAMPLE.of,
                 foot = L.BAR_LEFT, right = L.BAR_END:format(clock(SAMPLE.left)) }
    end
    t = t or now()
    local v = { icon = r.icon, name = r.name, made = r.made, of = r.known and r.of or nil, left = "", cast = 0 }
    local _, skill = profession(r.spell)
    local parts = {}
    if r.prof then parts[#parts + 1] = skill and (r.prof .. " " .. skill) or r.prof end
    local cur = 0
    if state == "run" then
        if r.cast and r.len > 0 then cur = math.max(0, math.min(1, (t - r.cast.from) / r.len)) end
        v.cast = cur
        local left = ns.BarLeft(r, t)
        local need = r.known and (r.of - r.made) or nil
        local can = need and ns.BarMats(r.spell)
        if can then
            if can >= need then parts[#parts + 1] = L.BAR_MATS_ALL
            else parts[#parts + 1] = "|cffff9f40" .. L.BAR_MATS_N:format(can) .. "|r"; v.subTone = "warn" end
        end
        if left then
            v.left = ns.BarSpan(left)
            v.foot, v.right = L.BAR_LEFT, L.BAR_END:format(clock(left))
        else
            v.foot, v.right = L.BAR_GOING, ""
        end
    elseif state == "stop" then
        v.tone, v.foot = "warn", L.BAR_STOPPED
        v.right = r.known and L.BAR_STOP_D:format(r.made, r.of - r.made) or ""
    else
        v.tone, v.foot = "good", L.BAR_DONE
        v.right = L.BAR_TOOK:format(ns.BarSpan(r.took or 0))
        if skill and r.skill0 and skill > r.skill0 then
            v.right = v.right .. ns.Dot() .. L.BAR_SKILL:format(skill, skill - r.skill0)
        end
    end
    v.sub = table.concat(parts, ns.Dot())
    local of = r.known and r.of or math.max(1, r.made + (r.cast and 1 or 0))
    v.frac = math.max(0, math.min(1, (r.made + cur) / of))
    v.doneFrac = math.max(0, math.min(1, r.made / of))
    v.ticks = (r.known and r.of > 1 and r.of <= ns.BAR_TICKS) and r.of or nil
    return v
end

-- ---------- the events ----------

-- From the module's event frame (Scan.lua). Returns nothing: the bar repaints itself.
function ns.OnBarEvent(event, id, spell)
    if event == "UNIT_SPELLCAST_START" then ns.BarCastStart()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then ns.BarCastDone(spell, id)
    elseif event == "UPDATE_TRADESKILL_CAST_STOPPED" then ns.BarHalted()
    else ns.BarCastBreak(id, spell) end
    if ns.RefreshBar then ns.RefreshBar() end
end

ns.moving = false
function ns.Move(on)
    ns.moving = on and true or false
    if ns.RefreshBar then ns.RefreshBar() end
end
