local addonName, ns = ...
local B = ns.Buffs

-- The rules: who is in the group, what each one is missing, and in which order to buff.
-- Nothing here casts; UI.lua puts the plan on the secure buttons.

ns.DEFAULTS = {
    who = "target",      -- off | group | target (the group and a friendly player you target)
    show = "missing",    -- missing | always | never
    combat = true,       -- keep buffing in combat from the list made before it
    low = 60,            -- seconds left at which a buff counts as running low (0: only when gone)
    groupMin = 3,        -- party members missing a buff before the group spell is used (0: never)
    thorns = "tanks",    -- self | tanks | all
    locked = true,       -- false shows the mover over the bar, to place it
    pets = true,         -- buff hunter and warlock pets too
    mana = 0,            -- below this share of mana (percent) only buff yourself (0: off)
    where = "always",    -- always | norest (not in cities and inns) | instance
    readyCheck = true,   -- on a ready check: show the bar and play a sound
    marks = true,        -- a small icon on the game's party and raid frames
    labels = true,       -- the caption beside the big button (spell and on whom); off: icons only
    focus = true,        -- the unit under the mouse, then the target, come first
    raidGroups = "all",  -- the raid groups you buff, see ns.RAID_GROUPS
    perSize = false,     -- "Buff again when" and "Group spells" kept per group size
}
for k, v in pairs(B.CHOICE_DEFAULT) do ns.DEFAULTS[k] = v end
ns.WHO = { "group", "target", "off" }
ns.SHOW = { "missing", "always", "never" }
ns.LOW = { 0, 60, 180, 300 }
ns.GROUP_MIN = { 2, 3, 4, 5, 0 }
ns.THORNS = { "self", "tanks", "all" }
ns.MANA = { 0, 20, 30, 40, 50 }
ns.WHERE = { "always", "norest", "instance" }
ns.SIZES = { "solo", "party", "raid" }
-- Raid groups to buff, as "first-last".
ns.RAID_GROUPS = { "all", "1-2", "3-4", "5-6", "7-8", "1-4", "5-8" }
ns.SKIP_SECONDS = 20

local db

function ns.DB()
    if not db then
        GulliGroupBuffsCharDB = GulliGroupBuffsCharDB or {}
        db = GulliGroupBuffsCharDB
        for k, v in pairs(ns.DEFAULTS) do
            if db[k] == nil then db[k] = v end
        end
        -- Gulli HUD: an unlocked bar now shows a mover that takes the clicks, so start locked.
        if not db.hud then db.hud, db.locked = 1, true end
        -- The owner wants a targeted friendly player offered by default: move the old default once.
        if not db.whoTarget then
            db.whoTarget = true
            if db.who == "group" then db.who = "target" end
        end
        db.watch = db.watch or {}
        db.bless = db.bless or {}
        db.size = db.size or {}
        for _, k in ipairs(ns.SIZES) do db.size[k] = db.size[k] or {} end
    end
    return db
end

-- The group size now: solo, party or raid.
function ns.Size()
    if IsInRaid and IsInRaid() then return "raid" end
    if GetNumSubgroupMembers and GetNumSubgroupMembers() > 0 then return "party" end
    return "solo"
end

-- A setting that can differ by group size ("low", "groupMin"), when perSize is on.
function ns.Setting(key, size)
    local d = ns.DB()
    if d.perSize then
        local v = d.size[size or ns.Size()][key]
        if v ~= nil then return v end
    end
    return d[key]
end

---- Game wrappers: the C_ call first, the old global as a fallback --------------

local function spellName(id)
    if not id then return nil end
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(id)
        return info and info.name
    end
    return GetSpellInfo and (GetSpellInfo(id))
end
ns.SpellName = spellName

local function spellIcon(id)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
    return GetSpellTexture and GetSpellTexture(id)
end
ns.SpellIcon = spellIcon

local function known(id)
    if not id then return false end
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    if IsSpellKnown and IsSpellKnown(id) then return true end
    return false
end
ns.Known = known

-- Usable now, or only short of mana (worth waiting for). False without the reagent.
-- A game answer, or nil when it is a secret value (the game hides it in some places).
local function val(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

-- Calls a game function; nil when it fails or answers with a secret value.
local function ask(fn, ...)
    if not fn then return nil end
    local ok, a, b = pcall(fn, ...)
    if not ok then return nil end
    return val(a), val(b)
end

ns.Ask = ask

local function usable(name)
    local ok, noMana
    if C_Spell and C_Spell.IsSpellUsable then ok, noMana = ask(C_Spell.IsSpellUsable, name)
    elseif IsUsableSpell then ok, noMana = ask(IsUsableSpell, name)
    else return true end
    return (ok or noMana) and true or false
end

-- False only when the game says the unit is out of range; nil (cannot tell) counts as in range.
local function inRange(name, unit)
    if unit == "player" then return true end
    local r
    if C_Spell and C_Spell.IsSpellInRange then r = ask(C_Spell.IsSpellInRange, name, unit)
    elseif IsSpellInRange then r = ask(IsSpellInRange, name, unit) end
    return not (r == false or r == 0)
end

local function now() return GetTime and GetTime() or 0 end

local function secret(v)
    return issecretvalue and issecretvalue(v) or false
end

-- The unit's buffs as name -> seconds left (math.huge: no end), and how many of them the
-- game hides (secret values). One hidden aura must not hide the rest.
local function readAuras(unit)
    local out, hidden, t = {}, 0, now()
    for i = 1, 40 do
        local name, expires
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local a = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
            if not a then break end
            name, expires = a.name, a.expirationTime
        elseif UnitBuff then
            local n, _, _, _, _, e = UnitBuff(unit, i)
            if not n then break end
            name, expires = n, e
        else
            break
        end
        if secret(name) then
            hidden = hidden + 1
        elseif name then
            local left = (secret(expires) or not expires or expires == 0) and math.huge or (expires - t)
            if not out[name] or out[name] < left then out[name] = left end
        end
    end
    return out, hidden
end

-- Asks the game for one buff by name: true and seconds left when the unit has it.
local function byName(unit, name)
    local ok, a = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, name, "HELPFUL")
    if not ok then return nil end
    if not a then return false end
    local e = a.expirationTime
    if secret(e) or not e or e == 0 then return true, math.huge end
    return true, e - now()
end

-- The unit's buffs, as readAuras. When the game hides some of them, each of `names` that
-- did not show is asked for by name; nil when the game cannot tell (the unit is left alone).
function ns.Auras(unit, names)
    local ok, out, hidden = pcall(readAuras, unit)
    if not ok then return nil end
    if hidden == 0 then return out end
    if not (names and C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) then return nil end
    -- In a fight the game hides names, so "not found" by name proves nothing: then only a
    -- found buff counts, and a unit with nothing found is left alone.
    local fighting = (InCombatLockdown and InCombatLockdown())
        or (UnitAffectingCombat and UnitAffectingCombat("player")) or false
    local found = false
    for _, n in ipairs(names) do
        if not out[n] then
            local has, left = byName(unit, n)
            if has == nil then return nil end
            if has then out[n], found = left, true end
        end
    end
    if fighting and not found then return nil end
    return out
end

local function role(unit)
    if UnitGroupRolesAssigned then
        local r = ask(UnitGroupRolesAssigned, unit)
        if r == "TANK" or r == "HEALER" then return r end
    end
    if ask(GetPartyAssignment, "MAINTANK", unit) then return "TANK" end
end
ns.Role = role

---- Units -----------------------------------------------------------------------

-- Is raid group n one of those you buff?
function ns.InRaidGroups(n, value)
    value = value or ns.DB().raidGroups
    if value == "all" or not n then return true end
    local a, b = (value or ""):match("^(%d)%-(%d)$")
    if not a then return true end
    return n >= tonumber(a) and n <= tonumber(b)
end

-- The units to look at, you first: { unit = "raid3", group = 2 } (group: the party number,
-- nil for a target outside the group; pet = true for a pet, right after its owner).
function ns.Units()
    local d = ns.DB()
    local list = {}
    if d.who == "off" then return list end
    local function add(unit, group, petUnit)
        list[#list + 1] = { unit = unit, group = group }
        if d.pets and petUnit and UnitExists(petUnit) then
            list[#list + 1] = { unit = petUnit, group = group, pet = true }
        end
    end
    local inRaid = IsInRaid and IsInRaid()
    if inRaid then
        local mine = 1
        local n = GetNumGroupMembers()
        local rest = {}
        for i = 1, n do
            local unit = "raid" .. i
            local _, _, sub = GetRaidRosterInfo(i)
            if ask(UnitIsUnit, unit, "player") then mine = sub or 1
            elseif ns.InRaidGroups(sub or 1) then rest[#rest + 1] = { unit = unit, group = sub or 1, i = i } end
        end
        add("player", mine, "pet")
        for _, u in ipairs(rest) do add(u.unit, u.group, "raidpet" .. u.i) end
    else
        add("player", 1, "pet")
        local n = GetNumSubgroupMembers and GetNumSubgroupMembers() or 0
        for i = 1, n do add("party" .. i, 1, "partypet" .. i) end
    end
    if d.who == "target" and ask(UnitExists, "target") and ask(UnitIsPlayer, "target")
        and ask(UnitIsFriend, "player", "target") and not ask(UnitIsUnit, "target", "player")
        and not ask(UnitInParty, "target") and not ask(UnitInRaid, "target") then
        list[#list + 1] = { unit = "target" }
    end
    return list
end

-- A check the game hides (a secret value) does not count against the unit.
local function alive(unit)
    if not ask(UnitExists, unit) then return false end
    if ask(UnitIsConnected, unit) == false then return false end
    if ask(UnitIsDeadOrGhost, unit) then return false end
    if ask(UnitIsVisible, unit) == false then return false end
    return true
end

---- What to watch ---------------------------------------------------------------

-- The player's buff families with names resolved: { key, name, cast, names = {..}, group, who }.
function ns.Families()
    local d = ns.DB()
    local _, class = UnitClass("player")
    local out = {}
    for _, f in ipairs(B.CLASS[class] or {}) do
        local on = d.watch[f.key]
        if on == nil then on = not f.off end
        if on then
            local fam = { key = f.key, who = f.who, weapon = f.weapon }
            if f.who == "blessing" then
                fam.options = {}
                for _, b in ipairs(B.BLESSINGS) do
                    if known(b.id) then
                        local names = { spellName(b.id) }
                        for _, a in ipairs(b.also) do names[#names + 1] = spellName(a) end
                        fam.options[b.key] = { name = spellName(b.id), id = b.id, names = names }
                    end
                end
                if next(fam.options) then out[#out + 1] = fam end
            else
                local id = f.id
                if f.choice then
                    id = nil
                    for _, c in ipairs(B.CHOICES[f.choice]) do
                        if c.key == d[f.choice] or (d[f.choice] == "auto" and known(c.id)) then id = c.id end
                    end
                end
                if id and not known(id) and f.ranks then
                    for _, r in ipairs(f.ranks) do if known(r) then id = r end end
                end
                if id and known(id) and spellName(id) then
                    fam.id, fam.name = id, spellName(id)
                    fam.names = { fam.name }
                    if f.group and known(f.group) and spellName(f.group) then
                        fam.group, fam.groupId = spellName(f.group), f.group
                        fam.names[2] = fam.group
                    end
                    out[#out + 1] = fam
                end
            end
        end
    end
    return out
end

-- The blessing this unit should get, or nil.
function ns.BlessingFor(unit)
    local d = ns.DB()
    local r = role(unit)
    local key = r and d.bless[r]
    if key == nil and r then key = B.BLESS_DEFAULT[r] end
    if key == "class" or key == nil then
        local _, class = UnitClass(unit)
        key = d.bless[class]
        if key == nil then key = B.BLESS_DEFAULT[class] end
    end
    if key ~= "off" then return key end
end

local function hasTank(units)
    for _, u in ipairs(units) do
        if role(u.unit) == "TANK" then return true end
    end
    return false
end

-- Does this family go on this unit at all?
local function applies(fam, unit, ctx, pet)
    if pet then
        -- Pets get the buffs for everyone, and the mana ones when they have mana.
        if fam.who == "all" then return true end
        if fam.who == "mana" then return ask(UnitPowerType, unit) == 0 end
        return false
    end
    if fam.who == "self" then return unit == "player" end
    if fam.who == "mana" then
        local _, class = ask(UnitClass, unit)
        return not (class and B.NO_MANA[class])
    end
    if fam.who == "thorns" then
        local t = ctx.db.thorns
        if t == "all" then return true end
        if t == "tanks" and ctx.tank then return role(unit) == "TANK" end
        return unit == "player"
    end
    return true
end

local function present(names, auras, low)
    if not names then return false end
    for _, n in ipairs(names) do
        local left = auras[n]
        if left and left > low then return true end
    end
    return false
end

ns.Present = present

local function weaponMissing(low)
    if not GetWeaponEnchantInfo then return false end
    local has, ms = GetWeaponEnchantInfo()
    if not has then return true end
    return (ms or 0) / 1000 <= low
end

---- Camp Benefits and other auras that block a weaker buff ------------------------

-- Forever's camp gives stats in one aura (spell CAMP_SPELL, lines such as "First Aid Kit:
-- Stamina increased by 34."). The game refuses a weaker buff of the same stat ("A more
-- powerful spell is already active"), so such a buff is not missing.
ns.CAMP_SPELL = 1229741
-- Rank 1 id -> the stat it raises (1 Strength .. 5 Spirit) and { spell id, amount, level } per rank.
ns.STAT_BUFFS = {
    [1243] = { stat = 3, ranks = { { 1243, 3, 1 }, { 1244, 8, 12 }, { 1245, 20, 24 }, { 2791, 32, 36 },
                                   { 10937, 43, 48 }, { 10938, 54, 60 } } },       -- Fortitude
    [21562] = { stat = 3, ranks = { { 21562, 43, 48 }, { 21564, 54, 60 } } },   -- Prayer of Fortitude
    [14752] = { stat = 5, ranks = { { 14752, 17, 30 }, { 14818, 23, 40 }, { 14819, 33, 50 },
                                    { 27841, 40, 60 } } },                        -- Divine Spirit
    [27681] = { stat = 5, ranks = { { 27681, 40, 60 } } },                      -- Prayer of Spirit
    [1459] = { stat = 4, ranks = { { 1459, 2, 1 }, { 1460, 7, 14 }, { 1461, 15, 28 }, { 10156, 22, 42 },
                                   { 10157, 31, 56 } } },                         -- Arcane Intellect
    [23028] = { stat = 4, ranks = { { 23028, 31, 56 } } },                      -- Arcane Brilliance
}
local STAT_EN = { "Strength", "Agility", "Stamina", "Intellect", "Spirit" }
local BLOCK_SECONDS = 600

local function statOf(text)
    local low = text:lower()
    for i = 1, 5 do
        for _, n in ipairs({ _G["SPELL_STAT" .. i .. "_NAME"], STAT_EN[i] }) do
            if type(n) == "string" and n ~= "" and (text:find(n, 1, true) or low:find(n:lower(), 1, true)) then
                return i
            end
        end
    end
end

-- The unit's camp aura: stat -> amount, and the seconds it has left; nil without one.
function ns.CampStats(unit)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
    for i = 1, 40 do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
        if not ok or not a then return nil end
        if not secret(a.spellId) and a.spellId == ns.CAMP_SPELL then
            local e = a.expirationTime
            local left = (e and not secret(e) and e > 0) and (e - now()) or math.huge
            local stats = {}
            local tip = C_TooltipInfo and C_TooltipInfo.GetUnitBuffByAuraInstanceID and a.auraInstanceID
                and C_TooltipInfo.GetUnitBuffByAuraInstanceID(unit, a.auraInstanceID)
            for _, line in ipairs(tip and tip.lines or {}) do
                local t = line.leftText
                if type(t) == "string" and not secret(t) then
                    local s, n = statOf(t), nil
                    for d in t:gmatch("%d+") do n = tonumber(d) end
                    if s and n then stats[s] = math.max(stats[s] or 0, n) end
                end
            end
            return stats, left
        end
    end
end

-- What the buff of this rank 1 id gives: the best rank the player knows, else (asking
-- someone else) the best rank for the player's level.
function ns.BuffAmount(id)
    local e = ns.STAT_BUFFS[id]
    if not e then return nil end
    local best
    for _, r in ipairs(e.ranks) do
        if IsPlayerSpell and IsPlayerSpell(r[1]) then best = r[2] end
    end
    if not best then
        local level = UnitLevel and UnitLevel("player") or 60
        for _, r in ipairs(e.ranks) do
            if r[3] <= level then best = r[2] end
        end
    end
    return best, e.stat
end

-- True when the unit already has an equal or stronger effect of this buff's stat.
function ns.Covered(unit, id, low)
    local amount, stat = ns.BuffAmount(id)
    if not amount then return false end
    local stats, left = ns.CampStats(unit)
    return stats ~= nil and (stats[stat] or 0) >= amount and left > (low or 0)
end

-- A buff the game refused on a unit ("A more powerful spell is already active") is left
-- alone while the camp aura lasts, or BLOCK_SECONDS when it is something else.
local bounced = {}
local function bounceKey(unit, spell)
    local g = UnitGUID and UnitGUID(unit)
    if not g or secret(g) then g = UnitName and UnitName(unit) end
    return g and spell and (tostring(g) .. "|" .. spell)
end

function ns.Bounced(unit, spell)
    local k = unit and bounceKey(unit, spell)
    if not k then return end
    local _, left = ns.CampStats(unit)
    bounced[k] = now() + ((left and left < math.huge) and left or BLOCK_SECONDS)
end

function ns.IsBounced(unit, spell)
    local k = bounceKey(unit, spell)
    local t = k and bounced[k]
    if t and t > now() then return true end
    if k then bounced[k] = nil end
    return false
end

---- Units skipped after a failed cast -------------------------------------------

local skipped = {}

local function unitKey(unit)
    local g = UnitGUID and UnitGUID(unit)
    if g and not secret(g) then return g end
    return UnitName(unit)
end

-- Leaves a unit out of the plan for a while after a cast on it failed (line of sight, a
-- stronger buff, a bad target), so the button does not stick on one person.
function ns.Skip(unit, seconds)
    local k = unit and unitKey(unit)
    if k then skipped[k] = now() + (seconds or ns.SKIP_SECONDS) end
end

function ns.Skipped(unit)
    local k = unitKey(unit)
    local t = k and skipped[k]
    if t and t > now() then return true end
    if k then skipped[k] = nil end
    return false
end

-- The player's mana share in percent, nil for a class without mana.
local function manaShare()
    if not UnitPower or not UnitPowerMax then return nil end
    if UnitPowerType and UnitPowerType("player") ~= 0 then return nil end
    local max, cur = UnitPowerMax("player", 0), UnitPower("player", 0)
    if secret(max) or secret(cur) then return nil end
    if not max or max <= 0 then return nil end
    return cur / max * 100
end

---- The plan --------------------------------------------------------------------

-- Every missing buff in casting order, you first, then each member in group order:
-- { unit, spell, icon, key, group = true when a group spell covers several }.
-- The second value lists the ones out of range now (they still go into the combat list).
function ns.Plan()
    local d = ns.DB()
    local units = ns.Units()
    local fams = ns.Families()
    local ctx = { db = d, tank = hasTank(units) }
    local low, groupMin = ns.Setting("low"), ns.Setting("groupMin")
    local info = { families = #fams, skipped = 0, hidden = 0, stronger = 0 }
    ns.info = info
    -- Every buff name the plan may look for, for units whose auras the game partly hides.
    local watched = {}
    for _, fam in ipairs(fams) do
        for _, n in ipairs(fam.names or {}) do watched[#watched + 1] = n end
        for _, opt in pairs(fam.options or {}) do
            for _, n in ipairs(opt.names or {}) do watched[#watched + 1] = n end
        end
    end
    local need = {}
    -- One unit's needs; an error from the game (a hidden value in an instance) leaves only
    -- that unit out.
    local function check(u, auras)
        local found = {}
        for _, fam in ipairs(fams) do
            if fam.who == "blessing" then
                local opt = not u.pet and fam.options[ns.BlessingFor(u.unit) or ""]
                if opt and not present(opt.names, auras, low) and not ns.IsBounced(u.unit, opt.name) then
                    found[#found + 1] = { unit = u.unit, sub = u.group, key = fam.key,
                                          spell = opt.name, id = opt.id, names = opt.names }
                end
            elseif applies(fam, u.unit, ctx, u.pet) then
                local missing
                if fam.weapon then missing = weaponMissing(low)
                else
                    missing = not present(fam.names, auras, low)
                    if missing and (ns.IsBounced(u.unit, fam.name) or ns.Covered(u.unit, fam.id, low)) then
                        missing = false
                        info.stronger = info.stronger + 1
                    end
                end
                if missing then
                    found[#found + 1] = { unit = u.unit, sub = u.group, key = fam.key,
                                          spell = fam.name, id = fam.id, fam = fam,
                                          names = not fam.weapon and fam.names or nil }
                end
            end
        end
        return found
    end
    for _, u in ipairs(units) do
        if alive(u.unit) and ns.Skipped(u.unit) then
            info.skipped = info.skipped + 1
        elseif alive(u.unit) then
            local auras = ns.Auras(u.unit, watched)
            local ok, found = false, nil
            if auras then ok, found = pcall(check, u, auras) end
            if ok then
                for _, e in ipairs(found) do need[#need + 1] = e end
            else
                info.hidden = info.hidden + 1
            end
        end
    end

    -- Who misses what, before group spells merge it: for the marks on the group frames.
    local byUnit = {}
    for _, e in ipairs(need) do
        if not byUnit[e.unit] then byUnit[e.unit] = spellIcon(e.id) end
    end

    -- A group spell replaces the single casts of one party when enough of it needs one.
    if groupMin and groupMin > 0 then
        for _, fam in ipairs(fams) do
            if fam.group and not usable(fam.group) then info.reagent = fam.group end
            if fam.group and usable(fam.group) then
                local count = {}
                for _, e in ipairs(need) do
                    if e.fam == fam and e.sub then count[e.sub] = (count[e.sub] or 0) + 1 end
                end
                local subs = {}
                for sub in pairs(count) do subs[#subs + 1] = sub end
                table.sort(subs)
                for _, sub in ipairs(subs) do
                    local c = count[sub]
                    if c >= groupMin then
                        -- Cast it on you when you are in that party, else on the first one in range.
                        local at, target, kept = nil, nil, {}
                        for i, e in ipairs(need) do
                            if e.fam == fam and e.sub == sub then
                                at = at or #kept + 1
                                if e.unit == "player" then target = e.unit
                                elseif not target and inRange(fam.group, e.unit) then target = e.unit end
                            else
                                kept[#kept + 1] = e
                            end
                        end
                        if not target then
                            for _, e in ipairs(need) do
                                if e.fam == fam and e.sub == sub then target = e.unit; break end
                            end
                        end
                        table.insert(kept, at, { unit = target, sub = sub, key = fam.key,
                            spell = fam.group, id = fam.groupId, group = true, covers = c,
                            names = fam.names })
                        need = kept
                    end
                end
            end
        end
    end

    -- Low on mana: only what goes on you.
    local share = d.mana and d.mana > 0 and manaShare()
    if share and share < d.mana then
        local mine = {}
        for _, e in ipairs(need) do
            if e.unit == "player" then mine[#mine + 1] = e end
        end
        info.mana = #mine < #need
        need = mine
    end

    -- The unit under the mouse, then the target, go first (a stable move to the front).
    if d.focus then
        local front, rest = {}, {}
        for _, focus in ipairs({ "mouseover", "target" }) do
            if ask(UnitExists, focus) then
                for i, e in ipairs(need) do
                    if e and e.unit ~= "player" and ask(UnitIsUnit, e.unit, focus) then
                        front[#front + 1] = e
                        need[i] = false
                    end
                end
            end
        end
        for _, e in ipairs(need) do if e then rest[#rest + 1] = e end end
        for _, e in ipairs(rest) do front[#front + 1] = e end
        need = front
    end

    local plan, far = {}, {}
    for _, e in ipairs(need) do
        e.fam, e.removedAt = nil, nil
        e.icon = spellIcon(e.id)
        if inRange(e.spell, e.unit) then plan[#plan + 1] = e else far[#far + 1] = e end
    end
    return plan, far, byUnit
end

-- Why the bar has nothing to cast, as text keys with their numbers: { { "ST_FAR", 2 }, ... }.
-- Empty when there is something to cast and nothing worth a word.
function ns.Status(plan, far)
    local d = ns.DB()
    local info = ns.info or {}
    local out = {}
    local function add(key, n) out[#out + 1] = { key, n } end
    if d.who == "off" then add("ST_OFF"); return out end
    local _, class = UnitClass("player")
    if not B.CLASS[class] then add("ST_NO_CLASS"); return out end
    if (info.families or 0) == 0 then add("ST_NONE_KNOWN"); return out end
    if info.mana then add("ST_MANA", d.mana) end
    if #plan == 0 and #far > 0 then add("ST_FAR", #far) end
    if (info.skipped or 0) > 0 then add("ST_SKIPPED", info.skipped) end
    if (info.hidden or 0) > 0 then add("ST_HIDDEN", info.hidden) end
    if (info.stronger or 0) > 0 then add("ST_STRONGER", info.stronger) end
    if info.reagent then add("ST_REAGENT", info.reagent) end
    if not ns.PlaceOK() then add("ST_PLACE") end
    return out
end

-- Does the bar show here? (The key works everywhere.)
function ns.PlaceOK()
    local w = ns.DB().where
    if w == "norest" then return not (IsResting and IsResting()) end
    if w == "instance" then
        local inside, kind = false, nil
        if IsInInstance then inside, kind = IsInInstance() end
        return inside and (kind == "party" or kind == "raid") or false
    end
    return true
end

-- The list the key walks through in combat: what is in range first, then the rest.
function ns.CombatList(plan, far, max)
    local list = {}
    for _, src in ipairs({ plan, far }) do
        for _, e in ipairs(src) do
            if #list < (max or 40) then list[#list + 1] = e end
        end
    end
    return list
end

---- Toolkit and slash commands -------------------------------------------------

SLASH_GULLIGROUPBUFFS1 = "/ggb"
SlashCmdList.GULLIGROUPBUFFS = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "lock" then
        ns.DB().locked = not ns.DB().locked
        if ns.Refresh then ns.Refresh() end
    elseif msg == "status" then
        local plan, far = ns.Plan()
        local lines = {}
        for _, st in ipairs(ns.Status(plan, far)) do
            lines[#lines + 1] = st[2] and ns.L[st[1]]:format(st[2]) or ns.L[st[1]]
        end
        if #plan > 0 then table.insert(lines, 1, ns.L.ST_NEXT:format(#plan)) end
        if #lines == 0 then lines[1] = ns.L.ALL_DONE end
        for _, line in ipairs(lines) do print("|cff9ad0ffGulli-GroupBuffs|r: " .. line) end
    elseif msg == "help" then
        print("|cff9ad0ffGulli-GroupBuffs|r: " .. ns.L.HELP .. " " .. ns.L.HELP_STATUS)
    elseif ns.Toggle then
        ns.Toggle()
    end
end

function GulliGroupBuffs_Toggle()
    if ns.Toggle then ns.Toggle() end
end

if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({
        key = "GroupBuffs",
        desc = ns.L.DESC,
        icon = "Interface\\AddOns\\Gulli-GroupBuffs\\icon",
        open = function() GulliGroupBuffs_Toggle() end,
        window = function() return ns.Window and ns.Window() end,
        slash = "/ggb",
        move = function(on) if ns.Move then ns.Move(on) end end,
        summary = function()
            local plan, far = ns.Plan()
            if #plan + #far == 0 then return ns.L.ALL_DONE end
            return ns.L.SUMMARY:format(#plan + #far)
        end,
    })
end
