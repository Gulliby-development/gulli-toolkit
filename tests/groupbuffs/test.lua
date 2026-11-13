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

test("racial self buffs: Touch of Weakness by any known rank, only on you", function()
    Fake { known = { [588] = true, [19262] = true }, db = { groupMin = 0 }, units = party() }
    local ns = Load()
    eq(show(ns.Plan()), "Inner Fire@player,Touch of Weakness@player")
    W.units.player.auras["Touch of Weakness"] = 600
    eq(show(ns.Plan()), "Inner Fire@player")
    local keys = {}
    for _, f in ipairs(ns.Families()) do keys[#keys + 1] = f.key end
    eq(table.concat(keys, ","), "innerfire,touch", "Shadowguard is not known, so it is left out")
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

test("one hidden buff does not hide the rest: the missing buff is still offered", function()
    local units = party()
    units.party1.auras = { ["Some Secret Buff"] = 0 }
    units.party1.secret = { ["Some Secret Buff"] = true }
    units.party2.auras = { ["Power Word: Fortitude"] = 600 }
    units.party2.secret = { ["Power Word: Fortitude"] = true }
    Fake { known = { [1243] = true }, units = units, db = { groupMin = 0 }, byName = true }
    local ns = Load()
    eq(show(ns.Plan()), "Power Word: Fortitude@player,Power Word: Fortitude@party1,Power Word: Fortitude@party3",
        "party1 misses it, party2 has it hidden")
    Fake { known = { [1243] = true }, units = units, db = { groupMin = 0 } }
    ns = Load()
    eq(show(ns.Plan()), "Power Word: Fortitude@player,Power Word: Fortitude@party3",
        "without a by-name lookup both are left alone")
    Fake { known = { [1243] = true }, units = units, db = { groupMin = 0 }, byName = true }
    ns = Load()
    W.combat = true
    eq(show(ns.Plan()), "Power Word: Fortitude@player,Power Word: Fortitude@party3",
        "in a fight a hidden unit with nothing found is left alone")
    W.combat = false
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

test("a friendly target outside the group is offered by default, also for older saves, until you pick Group", function()
    local function units()
        return { player = { name = "Me", class = "PRIEST", auras = { ["Power Word: Fortitude"] = 0 } },
                 target = { name = "Stranger", class = "HUNTER", auras = {} } }
    end
    Fake { known = { [1243] = true }, units = units() }
    local ns = Load()
    eq(show(ns.Plan()), "Power Word: Fortitude@target", "new save")
    Fake { known = { [1243] = true }, units = units(), db = { who = "group" } }
    ns = Load()
    eq(show(ns.Plan()), "Power Word: Fortitude@target", "old default moved once")
    ns.DB().who = "group"
    Fake { known = { [1243] = true }, units = units(), db = ns.DB() }
    ns = Load()
    eq(show(ns.Plan()), "", "a later pick of Group stays")
end)

test("other classes: Battle Shout, the best armor known, an aura, Omen of Clarity; Righteous Fury starts off", function()
    Fake { known = { [6673] = true }, units = { player = { name = "Me", class = "WARRIOR", auras = {} } } }
    local ns = Load()
    eq(show(ns.Plan()), "Battle Shout@player")
    Fake { known = { [1459] = true, [168] = true, [7302] = true }, units = { player = { name = "Me", class = "MAGE", auras = {} } } }
    ns = Load()
    eq(show(ns.Plan()), "Arcane Intellect@player,Ice Armor@player", "auto takes the last one known")
    ns.DB().magearmor = "frost"
    eq(show(ns.Plan()), "Arcane Intellect@player,Frost Armor@player")
    ns.DB().magearmor = "off"
    eq(show(ns.Plan()), "Arcane Intellect@player")
    Fake { known = { [687] = true, [706] = true }, units = { player = { name = "Me", class = "WARLOCK", auras = {} } } }
    ns = Load()
    eq(show(ns.Plan()), "Demon Armor@player")
    Fake { known = { [19740] = true, [465] = true, [25780] = true }, units = { player = { name = "Me", class = "PALADIN", auras = {} } } }
    ns = Load()
    eq(show(ns.Plan()), "Blessing of Might@player,Devotion Aura@player")
    ns.DB().watch.fury = true
    eq(show(ns.Plan()), "Blessing of Might@player,Devotion Aura@player,Righteous Fury@player")
    Fake { known = { [1126] = true, [16864] = true }, units = { player = { name = "Me", class = "DRUID", auras = {} } } }
    ns = Load()
    eq(show(ns.Plan()), "Mark of the Wild@player,Omen of Clarity@player")
    Fake { known = { [13165] = true }, units = { player = { name = "Me", class = "HUNTER", auras = {} } } }
    ns = Load()
    eq(show(ns.Plan()), "", "no aspect until one is picked")
    ns.DB().aspect = "hawk"
    eq(show(ns.Plan()), "Aspect of the Hawk@player")
end)

test("pets get the buffs for everyone, mana ones only with mana, and can be switched off", function()
    local units = party({
        pet = { name = "Imp", class = "WARLOCK", auras = {}, powerType = 0 },
        partypet2 = { name = "Wolf", class = "HUNTER", auras = {}, powerType = 2 },
    })
    Fake { known = { [1243] = true, [14752] = true }, units = units, db = { groupMin = 0 } }
    local ns = Load()
    local s = show(ns.Plan())
    assert(s:find("Power Word: Fortitude@pet", 1, true), s)
    assert(s:find("Divine Spirit@pet", 1, true), s)
    assert(s:find("Power Word: Fortitude@partypet2", 1, true), s)
    assert(not s:find("Divine Spirit@partypet2", 1, true), "no Spirit for a pet without mana")
    ns.DB().pets = false
    assert(not show(ns.Plan()):find("pet", 1, true), "pets off")
end)

test("a unit is skipped for a while after a cast on it fails, and the bar says why", function()
    local units = party()
    Fake { known = { [1243] = true }, units = units, db = { groupMin = 0 }, time = 100 }
    local ns = Load()
    Fire("PLAYER_LOGIN")
    local main = GulliGroupBuffsButton
    units.player.auras = { ["Power Word: Fortitude"] = 0 }
    ns.Refresh()
    eq(main.attrs.unit, "party1")
    main.hooks.OnClick(main)
    Fire("UI_ERROR_MESSAGE", 50, "Target not in line of sight")
    ns.Refresh()
    eq(main.attrs.unit, "party2", "the tank is skipped")
    eq(ns.Status(ns.Plan())[1][1], "ST_SKIPPED")
    W.spec.time = 125
    ns.Refresh()
    eq(main.attrs.unit, "party1", "back after the wait")
end)

test("Camp Benefits with as much Stamina or more covers Fortitude; a weaker camp does not", function()
    local units = party()
    -- Rank 4 (2791) gives 32 Stamina; the camp gives 34.
    Fake { known = { [1243] = true, [2791] = true }, units = units, db = { groupMin = 0 },
           camp = { player = { "Gained the following camp benefits:", "First Aid Kit: Stamina increased by 34." } } }
    local ns = Load()
    units.player.auras = { ["Camp Benefits"] = 7200 }
    local plan = ns.Plan()
    assert(not show(plan):find("@player", 1, true), "covered on you: " .. show(plan))
    assert(show(plan):find("Power Word: Fortitude@party1", 1, true), "the others still need it")
    W.camp.player = { "First Aid Kit: Stamina increased by 20." }
    assert(show(ns.Plan()):find("Power Word: Fortitude@player", 1, true), "a weaker camp leaves the buff")
    W.camp.player = { "Sharpening Wheel: Strength increased by 11." }
    assert(show(ns.Plan()):find("Power Word: Fortitude@player", 1, true), "another stat")
end)

test("a buff the game refuses as weaker is left alone on that unit", function()
    local units = party()
    Fake { known = { [1243] = true }, units = units, db = { groupMin = 0 }, time = 100 }
    local ns = Load()
    Fire("PLAYER_LOGIN")
    local main = GulliGroupBuffsButton
    ns.Refresh()
    eq(main.attrs.unit, "player")
    main.hooks.OnClick(main)
    Fire("UI_ERROR_MESSAGE", 50, "A more powerful spell is already active")
    ns.Refresh()
    eq(main.attrs.unit, "party1", "you are left alone")
    W.spec.time = 400
    ns.Refresh()
    eq(main.attrs.unit, "party1", "still blocked after five minutes")
    W.spec.time = 800
    ns.Refresh()
    eq(main.attrs.unit, "player", "back after ten minutes")
end)

test("the big button counts what waits and shows the state by colour", function()
    Fake { known = { [1243] = true }, units = party(), db = { groupMin = 0 } }
    local ns = Load()
    Fire("PLAYER_LOGIN")
    eq(GulliGroupBuffsButton.count._text, "+3")
end)

test("secret mana in combat never limits the plan", function()
    Fake { known = { [1243] = true }, units = party(), db = { groupMin = 0, mana = 30 }, mana = W.SECRET }
    local ns = Load()
    local plan, far = ns.Plan()
    assert(#plan > 1, "the group is still buffed")
    local st = ns.Status(plan, far)
    assert(not (st[1] and st[1][1] == "ST_MANA"), "no low-mana reason")
end)

test("low on mana only buffs you; /ggb status prints the reason", function()
    Fake { known = { [1243] = true }, units = party(), db = { groupMin = 0, mana = 30 }, mana = 20 }
    local ns = Load()
    local plan, far = ns.Plan()
    eq(show(plan), "Power Word: Fortitude@player")
    eq(ns.Status(plan, far)[1][1], "ST_MANA")
    SlashCmdList.GULLIGROUPBUFFS("status")
    local out = table.concat(W.printed, "\n")
    assert(out:find("only buffing you", 1, true), out)
end)

test("why it is empty: no class buffs, nothing learned, a missing reagent, all out of range", function()
    Fake { units = { player = { name = "Me", class = "ROGUE", auras = {} } } }
    local ns = Load()
    eq(ns.Status(ns.Plan())[1][1], "ST_NO_CLASS")
    Fake { units = { player = { name = "Me", class = "PRIEST", auras = {} } } }
    ns = Load()
    eq(ns.Status(ns.Plan())[1][1], "ST_NONE_KNOWN")
    local units = party()
    units.player.auras = { ["Power Word: Fortitude"] = 0 }
    units.party1.far, units.party2.far, units.party3.far = true, true, true
    Fake { known = { [1243] = true, [21562] = true }, units = units, unusable = { ["Prayer of Fortitude"] = true } }
    ns = Load()
    local plan, far = ns.Plan()
    local keys = {}
    for _, st in ipairs(ns.Status(plan, far)) do keys[#keys + 1] = st[1] end
    eq(table.concat(keys, ","), "ST_FAR,ST_REAGENT")
end)

test("where it shows: hidden in an inn when set, shown on a ready check with a sound", function()
    Fake { known = { [1243] = true }, units = party(), db = { where = "norest" }, resting = true }
    local ns = Load()
    Fire("PLAYER_LOGIN")
    eq(GulliGroupBuffsBar.shown, false, "hidden while resting")
    eq(GulliGroupBuffsButton.attrs.spell ~= nil, true, "the key still works")
    Fire("READY_CHECK")
    eq(GulliGroupBuffsBar.shown, true, "ready check shows it")
    eq(#W.sounds, 1)
    ns.DB().where = "instance"
    W.spec.resting = false
    W.spec.time = 200
    ns.Refresh()
    eq(GulliGroupBuffsBar.shown, false, "only in instances")
    W.spec.instance = "party"
    ns.Refresh()
    eq(GulliGroupBuffsBar.shown, true)
end)

test("the caption beside the big button can be switched off: icons only", function()
    local units = party()
    Fake { known = { [1243] = true }, units = units, db = { groupMin = 0 } }
    local ns = Load()
    Fire("PLAYER_LOGIN")
    local wide = GulliGroupBuffsBar:GetWidth()
    ns.DB().labels = false
    ns.Refresh()
    assert(GulliGroupBuffsBar:GetWidth() < wide, "the bar gets narrower without the caption")
    eq(GulliGroupBuffsBar.shown, true, "the icons stay")
    ns.DB().labels = true
    ns.Refresh()
    eq(GulliGroupBuffsBar:GetWidth(), wide)
end)

test("marks on the game's party frames show the first missing buff", function()
    local units = party()
    units.party2.auras = { ["Power Word: Fortitude"] = 0 }
    Fake { known = { [1243] = true }, units = units, db = { groupMin = 0 } }
    CompactPartyFrameMember1 = W.frame(); CompactPartyFrameMember1.unit = "party1"
    CompactPartyFrameMember2 = W.frame(); CompactPartyFrameMember2.unit = "party2"
    local made = {}
    for i = 1, 2 do
        local f = _G["CompactPartyFrameMember" .. i]
        rawset(f, "CreateTexture", function() local t = W.frame(); made[i] = t; return t end)
    end
    local ns = Load()
    Fire("PLAYER_LOGIN")
    assert(made[1] and made[1].shown, "mark on the tank")
    eq(made[2], nil, "no mark on the buffed mage")
    ns.DB().marks = false
    ns.Refresh()
    eq(made[1].shown, false)
    CompactPartyFrameMember1, CompactPartyFrameMember2 = nil, nil
end)

test("a buff that lands or falls off shows on the next frame, not the next tick", function()
    local units = party()
    Fake { known = { [1243] = true }, units = units, db = { groupMin = 0 } }
    Load()
    Fire("PLAYER_LOGIN")
    local function frame(dt)
        for _, f in ipairs(W.frames) do
            if f.scripts.OnUpdate then f.scripts.OnUpdate(f, dt) end
        end
    end
    frame(1)
    eq(GulliGroupBuffsButton.attrs.unit, "player")
    units.player.auras["Power Word: Fortitude"] = 1800
    Fire("UNIT_AURA", "player")
    frame(0.016)
    eq(GulliGroupBuffsButton.attrs.unit, "party1", "the next one at once")
    units.player.auras["Power Word: Fortitude"] = nil
    Fire("UNIT_AURA", "player")
    frame(0.016)
    eq(GulliGroupBuffsButton.attrs.unit, "player", "a lost buff at once")
    W.combat = true
    units.player.auras["Power Word: Fortitude"] = 1800
    Fire("UNIT_AURA", "player")
    frame(0.016)
    eq(GulliGroupBuffsButton.attrs.unit, "player", "in combat the buttons stay")
    W.combat = false
end)

test("marks also go on other addons' party frames, found by their unit attribute", function()
    local units = party()
    units.party2.auras = { ["Power Word: Fortitude"] = 0 }
    Fake { known = { [1243] = true }, units = units, db = { groupMin = 0 } }
    local theirs, made = {}, {}
    for i = 1, 3 do
        local f = W.frame()
        f.attrs.unit = ({ "party1", "party2", "nameplate1" })[i]
        rawset(f, "CreateTexture", function() local t = W.frame(); made[i] = t; return t end)
        theirs[i] = f
    end
    local forbidden = W.frame()
    forbidden.attrs.unit = "party1"
    rawset(forbidden, "IsForbidden", function() return true end)
    rawset(forbidden, "CreateTexture", function() error("touched a forbidden frame") end)
    theirs[4] = forbidden
    EnumerateFrames = function(f)
        if not f then return theirs[1] end
        for i, x in ipairs(theirs) do if x == f then return theirs[i + 1] end end
    end
    local ns = Load()
    Fire("PLAYER_LOGIN")
    assert(made[1] and made[1].shown, "mark on party1's frame of another addon")
    eq(made[2], nil, "no mark on the buffed one")
    eq(made[3], nil, "nameplates are not group frames")
    EnumerateFrames = nil
end)

test("settings by group size: a raid can use other values than a party", function()
    local units = party()
    units.player.auras = { ["Power Word: Fortitude"] = 30 }
    Fake { known = { [1243] = true }, units = units, db = { groupMin = 0, perSize = true, low = 60 } }
    local ns = Load()
    eq(ns.Size(), "party")
    eq(show(ns.Plan()):find("@player", 1, true) ~= nil, true, "30 s left counts as low in a party")
    ns.DB().size.party.low = 0
    eq(show(ns.Plan()):find("@player", 1, true), nil, "party: only when gone")
    ns.DB().perSize = false
    eq(show(ns.Plan()):find("@player", 1, true) ~= nil, true, "back to the shared value")
end)

test("raid groups: only the chosen groups are buffed, and you always", function()
    local units = { player = { name = "Me", class = "PRIEST", auras = {} } }
    local raid = {}
    for i = 1, 4 do
        local unit = "raid" .. i
        if i == 1 then units[unit] = units.player
        else units[unit] = { name = "R" .. i, class = "WARRIOR", auras = {}, inGroup = true } end
        raid[i] = { name = "R" .. i, group = i }
    end
    Fake { known = { [1243] = true }, units = units, raid = raid, db = { groupMin = 0, raidGroups = "3-4" } }
    local ns = Load()
    eq(show(ns.Plan()), "Power Word: Fortitude@player,Power Word: Fortitude@raid3,Power Word: Fortitude@raid4")
end)

test("the unit under the mouse, then the target, go first", function()
    local units = party()
    units.player.auras = { ["Power Word: Fortitude"] = 0 }
    units.mouseover = units.party3
    units.target = units.party2
    Fake { known = { [1243] = true }, units = units, db = { groupMin = 0 } }
    local ns = Load()
    eq(show(ns.Plan()), "Power Word: Fortitude@party3,Power Word: Fortitude@party2,Power Word: Fortitude@party1")
    ns.DB().focus = false
    eq(show(ns.Plan()), "Power Word: Fortitude@party1,Power Word: Fortitude@party2,Power Word: Fortitude@party3")
end)

-- Runs the combat snippet the way the restricted environment does: only the calls it has.
local function click(main, down)
    local f = assert(loadstring("local self, button, down = ...\n" .. main.wrapped))
    setfenv(f, {
        PlayerInCombat = function() return W.combat end,
        GetTime = GetTime,
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
    local function later() W.spec.time = (W.spec.time or 100) + 2 end
    click(main)
    eq(main.attrs.unit, "player")
    units.party1.dead = true
    later(); click(main)
    eq(main.attrs.unit, "party2", "dead tank skipped")
    later(); click(main)
    eq(main.attrs.unit, "party3")
    later(); click(main)
    eq(main.attrs.unit, "player", "wraps to the start")
    later(); click(main, true)
    eq(main.attrs.unit, "player", "the other key edge does not move on")
    ns.Refresh()
    W.combat = false
end)

test("in combat, presses spammed within a global cooldown stay on the same unit", function()
    local units = party()
    Fake { known = { [1243] = true }, units = units, db = { groupMin = 0 }, time = 100 }
    local ns = Load()
    Fire("PLAYER_LOGIN")
    local main = GulliGroupBuffsButton
    Fire("PLAYER_REGEN_DISABLED")
    W.combat = true
    click(main)
    eq(main.attrs.unit, "player")
    for k = 1, 5 do
        W.spec.time = 100 + k * 0.2
        click(main)
        eq(main.attrs.unit, "player", "press " .. k .. " in the cooldown")
    end
    W.spec.time = 101.6
    click(main)
    eq(main.attrs.unit, "party1", "after the cooldown the next one")
    W.spec.time = 101.7
    click(main)
    eq(main.attrs.unit, "party1")
    W.combat = false
end)

test("in combat a buff our press landed counts as done, even when the auras are hidden", function()
    local units = party()
    units.party1.auras = { ["Power Word: Fortitude"] = 0 }
    units.party2.auras = { ["Power Word: Fortitude"] = 0 }
    units.player.auras = { ["Power Word: Fortitude"] = 0 }
    Fake { known = { [1243] = true }, units = units, db = { groupMin = 0 }, time = 100 }
    local ns = Load()
    Fire("PLAYER_LOGIN")
    local main = GulliGroupBuffsButton
    Fire("PLAYER_REGEN_DISABLED")
    W.combat = true
    eq(main.attrs["gb-count"], 1)
    eq(main.attrs["gb-unit1"], "party3")
    units.party3.hidden = true          -- the game hides its auras in the fight
    click(main)
    main.hooks.OnClick(main)
    Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 1243)
    ns.Refresh()
    eq(main.state, "ok", "nothing left to buff")
    W.combat = false
    Fire("PLAYER_REGEN_ENABLED")
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
    for _, class in ipairs({ "PRIEST", "MAGE", "DRUID", "PALADIN", "SHAMAN", "WARRIOR", "WARLOCK", "HUNTER", "ROGUE" }) do
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
        if rawget(f, "text") and f.text._text == "Group and target" then who = f end
    end
    assert(who, "no 'Who it buffs' button")
    who.scripts.OnClick(who, "LeftButton")
    eq(ns.DB().who, "off")
    who.scripts.OnClick(who, "RightButton")
    eq(ns.DB().who, "target", "right-click goes back")
    eq(who.text._text, "Group and target")
    eq(ns.DB().locked, true, "a new bar starts locked")
    SlashCmdList.GULLIGROUPBUFFS("lock")
    eq(ns.DB().locked, false)
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
