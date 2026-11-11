-- Run from the repository root: lua5.1 tests/groupbuffs/test.lua
local W = dofile("tests/groupbuffs/wow.lua")
local failed, count = 0, 0

local function test(name, fn)
    count = count + 1
    local ok, err = pcall(fn)
    if ok then
        io.write("ok   ", name, "\n")
    else
        failed = failed + 1
        io.write("FAIL ", name, "\n     ", tostring(err), "\n")
    end
end

local function eq(a, b, what)
    if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

-- "spell@unit" for each entry, in order.
local function show(plan)
    local t = {}
    for _, e in ipairs(plan) do t[#t + 1] = e.spell .. "@" .. e.unit end
    return table.concat(t, ",")
end

local PRIEST = { [1243] = true, [21562] = true, [14752] = true, [976] = true, [588] = true }

local function party(extra)
    local units = {
        player = { name = "Me", class = "PRIEST", auras = {} },
        party1 = { name = "Tank", class = "WARRIOR", auras = {}, role = "TANK", inGroup = true },
        party2 = { name = "Mage", class = "MAGE", auras = {}, inGroup = true },
        party3 = { name = "Rogue", class = "ROGUE", auras = {}, inGroup = true },
    }
    for k, v in pairs(extra or {}) do units[k] = v end
    return units
end

test("solo priest: your own buffs, in the class order; unknown and default-off ones are left out", function()
    Fake { known = { [1243] = true, [588] = true, [976] = true }, units = { player = { name = "Me", class = "PRIEST", auras = {} } } }
    local ns = Load()
    eq(show(ns.Plan()), "Power Word: Fortitude@player,Inner Fire@player")
end)

test("you first, then the party; no Spirit for classes without mana; self buffs only on you", function()
    Fake { known = PRIEST, db = { groupMin = 0 }, units = party() }
    local ns = Load()
    eq(show(ns.Plan()), "Power Word: Fortitude@player,Divine Spirit@player,Inner Fire@player,"
        .. "Power Word: Fortitude@party1,Power Word: Fortitude@party2,Divine Spirit@party2,"
        .. "Power Word: Fortitude@party3")
end)

test("a buff that is there is skipped; one running low comes back", function()
    local units = party()
    units.player.auras = { ["Power Word: Fortitude"] = 1500, ["Inner Fire"] = 0, ["Divine Spirit"] = 30 }
    units.party1.auras = { ["Prayer of Fortitude"] = 40 }
    units.party2.auras = { ["Power Word: Fortitude"] = 1000, ["Divine Spirit"] = 1000 }
    units.party3.auras = { ["Power Word: Fortitude"] = 1000 }
    Fake { known = PRIEST, units = units, db = { low = 60 } }
    local ns = Load()
    eq(show(ns.Plan()), "Divine Spirit@player,Power Word: Fortitude@party1")
    ns.DB().low = 0
    eq(show(ns.Plan()), "", "only when gone")
end)

test("the group spell replaces single casts when enough need it, cast on you", function()
    Fake { known = PRIEST, units = party(), db = { groupMin = 3 } }
    local ns = Load()
    local plan = ns.Plan()
    eq(show(plan), "Prayer of Fortitude@player,Divine Spirit@player,Inner Fire@player,Divine Spirit@party2")
    eq(plan[1].group, true)
    eq(plan[1].covers, 4)
end)

test("no group spell without its reagent, below the threshold, or when not learned", function()
    Fake { known = PRIEST, units = party(), db = { groupMin = 3 }, unusable = { ["Prayer of Fortitude"] = true } }
    local ns = Load()
    eq(ns.Plan()[1].spell, "Power Word: Fortitude", "no reagent")
    Fake { known = PRIEST, units = party(), db = { groupMin = 5 } }
    ns = Load()
    eq(ns.Plan()[1].spell, "Power Word: Fortitude", "threshold")
    Fake { known = { [1243] = true }, units = party(), db = { groupMin = 2 } }
    ns = Load()
    eq(ns.Plan()[1].spell, "Power Word: Fortitude", "not learned")
end)

test("dead and offline members are skipped, those out of range go to the second list", function()
    local units = party()
    units.party1.dead = true
    units.party2.offline = true
    units.party3.far = true
    Fake { known = { [1243] = true }, units = units, db = { groupMin = 0 } }
    local ns = Load()
    local plan, far = ns.Plan()
    eq(show(plan), "Power Word: Fortitude@player")
    eq(show(far), "Power Word: Fortitude@party3")
    eq(show(ns.CombatList(plan, far)), "Power Word: Fortitude@player,Power Word: Fortitude@party3")
end)

test("a unit whose buffs the game hides is left alone", function()
    local units = party()
    units.party1.hidden = true
    Fake { known = { [1243] = true }, units = units, db = { groupMin = 0 } }
    local ns = Load()
    eq(show(ns.Plan()), "Power Word: Fortitude@player,Power Word: Fortitude@party2,Power Word: Fortitude@party3")
end)

test("in a raid the group spell is counted per party", function()
    local units = { player = { name = "Me", class = "PRIEST", auras = {} } }
    local raid = {}
    for i = 1, 7 do
        local unit = "raid" .. i
        local group = i <= 4 and 1 or 2
        if i == 1 then units[unit] = units.player
        else units[unit] = { name = "R" .. i, class = "WARRIOR", auras = {}, inGroup = true } end
        raid[i] = { name = "R" .. i, group = group }
    end
    Fake { known = { [1243] = true, [21562] = true }, units = units, raid = raid, db = { groupMin = 4 } }
    local ns = Load()
    eq(show(ns.Plan()), "Prayer of Fortitude@player,Power Word: Fortitude@raid5,"
        .. "Power Word: Fortitude@raid6,Power Word: Fortitude@raid7")
end)

test("thorns go on tanks, or on you when there is no tank", function()
    local units = party()
    units.player.class = "DRUID"
    Fake { known = { [467] = true }, units = units }
    local ns = Load()
    eq(show(ns.Plan()), "Thorns@party1")
    units.party1.role = nil
    eq(show(ns.Plan()), "Thorns@player")
    ns.DB().thorns = "all"
    eq(#ns.Plan(), 4)
end)

test("blessings follow role, then class; a Greater Blessing counts", function()
    local units = party()
    units.player.class = "PALADIN"
    units.party3.auras = { ["Greater Blessing of Might"] = 900 }
    Fake { known = { [19740] = true, [19742] = true, [20217] = true }, units = units }
    local ns = Load()
    eq(show(ns.Plan()), "Blessing of Might@player,Blessing of Kings@party1,Blessing of Wisdom@party2")
    ns.DB().bless.MAGE = "off"
    ns.DB().bless.TANK = "class"
    eq(show(ns.Plan()), "Blessing of Might@player,Blessing of Might@party1")
end)

test("a blessing you do not know is not asked for", function()
    local units = party()
    units.player.class = "PALADIN"
    Fake { known = { [19740] = true }, units = units }
    local ns = Load()
    eq(show(ns.Plan()), "Blessing of Might@player,Blessing of Might@party3")
end)

test("shaman: the chosen shield and a weapon imbue that is gone or running low", function()
    local units = { player = { name = "Me", class = "SHAMAN", auras = {} } }
    Fake { known = { [324] = true, [8024] = true }, units = units, db = { weapon = "flametongue" } }
    local ns = Load()
    eq(show(ns.Plan()), "Lightning Shield@player,Flametongue Weapon@player")
    Fake { known = { [324] = true, [8024] = true }, units = units, db = { weapon = "flametongue" }, weapon = 600 }
    ns = Load()
    eq(show(ns.Plan()), "Lightning Shield@player")
    Fake { known = { [324] = true, [8024] = true }, units = units, db = { weapon = "off" } }
    ns = Load()
    eq(show(ns.Plan()), "Lightning Shield@player", "weapon off")
end)

test("who it buffs: a friendly target outside the group, or nobody", function()
    local units = { player = { name = "Me", class = "PRIEST", auras = { ["Power Word: Fortitude"] = 0 } },
                    target = { name = "Stranger", class = "HUNTER", auras = {} } }
    Fake { known = { [1243] = true }, units = units, db = { who = "target" } }
    local ns = Load()
    eq(show(ns.Plan()), "Power Word: Fortitude@target")
    ns.DB().who = "group"
    eq(show(ns.Plan()), "")
    units.player.auras = {}
    ns.DB().who = "off"
    eq(show(ns.Plan()), "")
end)

-- Runs the combat snippet the way the restricted environment does: only the calls it has.
local function click(main, down)
    local f = assert(loadstring("local self, button, down = ...\n" .. main.wrapped))
    setfenv(f, {
        PlayerInCombat = function() return W.combat end,
        SecureCmdOptionParse = function(s)
            local unit = s:match("^%[@([%w]+),exists,nodead%] ok$")
            assert(unit, "unexpected conditional " .. s)
            return (UnitExists(unit) and not UnitIsDeadOrGhost(unit)) and "ok" or nil
        end,
    })
    return f(main, "LeftButton", down or false)
end

test("out of combat the button is aimed at the next buff and the key is bound", function()
    Fake { known = { [1243] = true }, units = party(), db = { groupMin = 0, key = "F" } }
    local ns = Load()
    Fire("PLAYER_LOGIN")
    local main = GulliGroupBuffsButton
    eq(main.attrs.type, "spell")
    eq(main.attrs.spell, "Power Word: Fortitude")
    eq(main.attrs.unit, "player")
    eq(W.bindings.F, "GulliGroupBuffsButton")
    eq(GulliGroupBuffsButtonMini1.attrs.unit, "party1")
    eq(GulliGroupBuffsBar.shown, true)
    eq(click(main), nil, "the snippet leaves an out-of-combat click alone")
    eq(main.attrs.unit, "player")
end)

test("in combat each press walks the list from before the fight, skips the dead, wraps", function()
    local units = party()
    Fake { known = { [1243] = true }, units = units, db = { groupMin = 0 } }
    local ns = Load()
    Fire("PLAYER_LOGIN")
    local main = GulliGroupBuffsButton
    Fire("PLAYER_REGEN_DISABLED")
    W.combat = true
    eq(main.attrs["gb-count"], 4)
    click(main)
    eq(main.attrs.unit, "player")
    units.party1.dead = true
    click(main)
    eq(main.attrs.unit, "party2", "dead tank skipped")
    click(main)
    eq(main.attrs.unit, "party3")
    click(main)
    eq(main.attrs.unit, "player", "wraps to the start")
    click(main, true)
    eq(main.attrs.unit, "player", "the other key edge does not move on")
    ns.Refresh()
    W.combat = false
end)

test("with in-combat buffing off, a press in combat casts nothing", function()
    Fake { known = { [1243] = true }, units = party(), db = { combat = false } }
    Load()
    Fire("PLAYER_LOGIN")
    Fire("PLAYER_REGEN_DISABLED")
    W.combat = true
    eq(click(GulliGroupBuffsButton), false)
    W.combat = false
end)

test("a key set in combat is bound after it", function()
    Fake { known = { [1243] = true }, units = party() }
    local ns = Load()
    Fire("PLAYER_LOGIN")
    W.combat = true
    ns.DB().key = "G"
    ns.ApplyKey()
    eq(W.bindings.G, nil)
    W.combat = false
    Fire("PLAYER_REGEN_ENABLED")
    eq(W.bindings.G, "GulliGroupBuffsButton")
end)

test("the bar hides when nothing is missing, or when set to never", function()
    local units = { player = { name = "Me", class = "PRIEST", auras = { ["Power Word: Fortitude"] = 0 } } }
    Fake { known = { [1243] = true }, units = units }
    local ns = Load()
    Fire("PLAYER_LOGIN")
    eq(GulliGroupBuffsBar.shown, false)
    ns.DB().show = "always"
    ns.Refresh()
    eq(GulliGroupBuffsBar.shown, true)
    units.player.auras = {}
    ns.DB().show = "never"
    ns.Refresh()
    eq(GulliGroupBuffsBar.shown, false)
    eq(GulliGroupBuffsButton.attrs.spell, "Power Word: Fortitude", "the key still works")
end)

test("registers with the toolkit when it is there", function()
    local got
    Fake { units = party(), toolkit = { Register = function(m) got = m end } }
    Load()
    eq(got.key, "GroupBuffs")
    eq(got.slash, "/ggb")
    eq(type(got.open), "function")
end)

test("the settings window builds for every class and its buttons cycle", function()
    for _, class in ipairs({ "PRIEST", "MAGE", "DRUID", "PALADIN", "SHAMAN", "WARRIOR" }) do
        local units = party()
        units.player.class = class
        Fake { units = units }
        local ns = Load()
        Fire("PLAYER_LOGIN")
        ns.Toggle()
        eq(GulliGroupBuffsSettings.shown, true, class)
    end
    local ns = Load()
    Fire("PLAYER_LOGIN")
    ns.Toggle()
    local who
    for _, f in ipairs(W.frames) do
        if rawget(f, "text") and f.text._text == "Your group" then who = f end
    end
    assert(who, "no 'Who it buffs' button")
    who.scripts.OnClick(who, "LeftButton")
    eq(ns.DB().who, "target")
    eq(who.text._text, "Group and target")
    who.scripts.OnClick(who, "RightButton")
    eq(ns.DB().who, "group", "right-click goes back")
    SlashCmdList.GULLIGROUPBUFFS("lock")
    eq(ns.DB().locked, true)
end)

test("every language has every key with the same placeholders", function()
    Fake {}
    local ns = Load()
    local function marks(s)
        local t = {}
        for m in s:gmatch("%%[ds]") do t[#t + 1] = m end
        return table.concat(t)
    end
    for _, tag in ipairs(ns.TAGS) do
        local t = assert(ns.T[tag], "no table for " .. tag)
        for key, en in pairs(ns.T.en) do
            assert(t[key], tag .. " misses " .. key)
            eq(marks(t[key]), marks(en), tag .. "." .. key)
        end
        for key in pairs(t) do assert(ns.T.en[key], tag .. " has extra " .. key) end
    end
end)

io.write(("\n%d tests, %d failed\n"):format(count, failed))
os.exit(failed == 0 and 0 or 1)
