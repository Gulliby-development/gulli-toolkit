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
    shield = "lightning",
    weapon = "off",
    locked = false,
}
ns.WHO = { "group", "target", "off" }
ns.SHOW = { "missing", "always", "never" }
ns.LOW = { 0, 60, 180, 300 }
ns.GROUP_MIN = { 2, 3, 4, 5, 0 }
ns.THORNS = { "self", "tanks", "all" }

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
    end
    return db
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

-- The units to look at, you first: { unit = "raid3", group = 2 } (group: the party number,
-- nil for a target outside the group).
function ns.Units()
    local d = ns.DB()
    local list = {}
    if d.who == "off" then return list end
    local inRaid = IsInRaid and IsInRaid()
    if inRaid then
        local mine = 1
        local n = GetNumGroupMembers()
        local rest = {}
        for i = 1, n do
            local unit = "raid" .. i
            local _, _, sub = GetRaidRosterInfo(i)
            if UnitIsUnit(unit, "player") then mine = sub or 1
            else rest[#rest + 1] = { unit = unit, group = sub or 1 } end
        end
        list[1] = { unit = "player", group = mine }
        for _, u in ipairs(rest) do list[#list + 1] = u end
    else
        list[1] = { unit = "player", group = 1 }
        local n = GetNumSubgroupMembers and GetNumSubgroupMembers() or 0
        for i = 1, n do list[#list + 1] = { unit = "party" .. i, group = 1 } end
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
                        if c.key == d[f.choice] then id = c.id end
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
local function applies(fam, unit, ctx)
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

---- The plan --------------------------------------------------------------------

-- Every missing buff in casting order, you first, then each member in group order:
-- { unit, spell, icon, key, group = true when a group spell covers several }.
-- The second value lists the ones out of range now (they still go into the combat list).
function ns.Plan()
    local d = ns.DB()
    local units = ns.Units()
    local fams = ns.Families()
    local ctx = { db = d, tank = hasTank(units) }
    local need = {}
    for _, u in ipairs(units) do
        if alive(u.unit) then
            local auras = ns.Auras(u.unit)
            if auras then
                for _, fam in ipairs(fams) do
                    if fam.who == "blessing" then
                        local opt = fam.options[ns.BlessingFor(u.unit) or ""]
                        if opt and not present(opt.names, auras, d.low) then
                            need[#need + 1] = { unit = u.unit, sub = u.group, key = fam.key,
                                                spell = opt.name, id = opt.id, names = opt.names }
                        end
                    elseif applies(fam, u.unit, ctx) then
                        local missing
                        if fam.weapon then missing = weaponMissing(d.low)
                        else missing = not present(fam.names, auras, d.low) end
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

    -- A group spell replaces the single casts of one party when enough of it needs one.
    if d.groupMin and d.groupMin > 0 then
        for _, fam in ipairs(fams) do
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
                    if c >= d.groupMin then
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

    local plan, far = {}, {}
    for _, e in ipairs(need) do
        e.fam, e.removedAt = nil, nil
        e.icon = spellIcon(e.id)
        if inRange(e.spell, e.unit) then plan[#plan + 1] = e else far[#far + 1] = e end
    end
    return plan, far
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
    elseif msg == "help" then
        print("|cff9ad0ffGulli-GroupBuffs|r: " .. ns.L.HELP)
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
    })
end
