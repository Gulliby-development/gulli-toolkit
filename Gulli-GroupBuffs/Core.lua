local addonName, ns = ...
local B = ns.Buffs

-- The rules: who is in the group, what each one is missing, and in which order to buff.
-- Nothing here casts; UI.lua puts the plan on the secure buttons.

ns.DEFAULTS = {
    who = "group",       -- off | group | target
    show = "missing",    -- missing | always | never
    combat = true,       -- keep buffing in combat from the list made before it
    low = 60,            -- seconds left at which a buff counts as running low (0: only when gone)
    groupMin = 3,        -- party members missing a buff before the group spell is used (0: never)
    thorns = "tanks",    -- self | tanks | all
    locked = false,
    pets = true,         -- buff hunter and warlock pets too
    mana = 0,            -- below this share of mana (percent) only buff yourself (0: off)
    where = "always",    -- always | norest (not in cities and inns) | instance
    readyCheck = true,   -- on a ready check: show the bar and play a sound
    marks = true,        -- a small icon on the game's party and raid frames
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
local function usable(name)
    local ok, noMana
    if C_Spell and C_Spell.IsSpellUsable then ok, noMana = C_Spell.IsSpellUsable(name)
    elseif IsUsableSpell then ok, noMana = IsUsableSpell(name)
    else return true end
    return (ok or noMana) and true or false
end

-- False only when the game says the unit is out of range; nil (cannot tell) counts as in range.
local function inRange(name, unit)
    if unit == "player" then return true end
    local r
    if C_Spell and C_Spell.IsSpellInRange then r = C_Spell.IsSpellInRange(name, unit)
    elseif IsSpellInRange then r = IsSpellInRange(name, unit) end
    return not (r == false or r == 0)
end

local function now() return GetTime and GetTime() or 0 end

local function secret(v)
    return issecretvalue and issecretvalue(v) or false
end

-- The unit's buffs as name -> seconds left (math.huge: no end). Nil when the game hides
-- them (secret values, a battleground): then the unit is left alone rather than nagged.
local function readAuras(unit)
    local out, t = {}, now()
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
        if secret(name) or secret(expires) then return nil end
        if name then
            local left = (not expires or expires == 0) and math.huge or (expires - t)
            if not out[name] or out[name] < left then out[name] = left end
        end
    end
    return out
end

function ns.Auras(unit)
    local ok, res = pcall(readAuras, unit)
    if ok then return res end
end

local function role(unit)
    if UnitGroupRolesAssigned then
        local r = UnitGroupRolesAssigned(unit)
        if r == "TANK" or r == "HEALER" then return r end
    end
    if GetPartyAssignment and GetPartyAssignment("MAINTANK", unit) then return "TANK" end
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
            if UnitIsUnit(unit, "player") then mine = sub or 1
            elseif ns.InRaidGroups(sub or 1) then rest[#rest + 1] = { unit = unit, group = sub or 1, i = i } end
        end
        add("player", mine, "pet")
        for _, u in ipairs(rest) do add(u.unit, u.group, "raidpet" .. u.i) end
    else
        add("player", 1, "pet")
        local n = GetNumSubgroupMembers and GetNumSubgroupMembers() or 0
        for i = 1, n do add("party" .. i, 1, "partypet" .. i) end
    end
    if d.who == "target" and UnitExists("target") and UnitIsPlayer("target")
        and UnitIsFriend("player", "target") and not UnitIsUnit("target", "player")
        and not (UnitInParty and UnitInParty("target")) and not (UnitInRaid and UnitInRaid("target")) then
        list[#list + 1] = { unit = "target" }
    end
    return list
end

local function alive(unit)
    if not UnitExists(unit) then return false end
    if UnitIsConnected and UnitIsConnected(unit) == false then return false end
    if UnitIsDeadOrGhost(unit) then return false end
    if UnitIsVisible and UnitIsVisible(unit) == false then return false end
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
        if fam.who == "mana" then return UnitPowerType and UnitPowerType(unit) == 0 or false end
        return false
    end
    if fam.who == "self" then return unit == "player" end
    if fam.who == "mana" then
        local _, class = UnitClass(unit)
        return not B.NO_MANA[class]
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
    local max = UnitPowerMax("player", 0)
    if not max or max <= 0 then return nil end
    return UnitPower("player", 0) / max * 100
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
    local info = { families = #fams, skipped = 0 }
    ns.info = info
    local need = {}
    for _, u in ipairs(units) do
        if alive(u.unit) and ns.Skipped(u.unit) then
            info.skipped = info.skipped + 1
        elseif alive(u.unit) then
            local auras = ns.Auras(u.unit)
            if auras then
                for _, fam in ipairs(fams) do
                    if fam.who == "blessing" then
                        local opt = not u.pet and fam.options[ns.BlessingFor(u.unit) or ""]
                        if opt and not present(opt.names, auras, low) then
                            need[#need + 1] = { unit = u.unit, sub = u.group, key = fam.key,
                                                spell = opt.name, id = opt.id, names = opt.names }
                        end
                    elseif applies(fam, u.unit, ctx, u.pet) then
                        local missing
                        if fam.weapon then missing = weaponMissing(low)
                        else missing = not present(fam.names, auras, low) end
                        if missing then
                            need[#need + 1] = { unit = u.unit, sub = u.group, key = fam.key,
                                                spell = fam.name, id = fam.id, fam = fam,
                                                names = not fam.weapon and fam.names or nil }
                        end
                    end
                end
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
            if UnitExists(focus) then
                for i, e in ipairs(need) do
                    if e and e.unit ~= "player" and UnitIsUnit(e.unit, focus) then
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
        title = ns.L.TITLE,
        desc = ns.L.DESC,
        icon = "Interface\\AddOns\\Gulli-GroupBuffs\\icon",
        open = function() GulliGroupBuffs_Toggle() end,
        window = function() return ns.Window and ns.Window() end,
        slash = "/ggb",
        summary = function()
            local plan, far = ns.Plan()
            if #plan + #far == 0 then return ns.L.ALL_DONE end
            return ns.L.SUMMARY:format(#plan + #far)
        end,
    })
end
