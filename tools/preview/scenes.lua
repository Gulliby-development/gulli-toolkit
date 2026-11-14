-- Sample data for each window in tools/preview. scenes[test folder][scene] =
-- { spec = Fake() spec, before = fn(W, R), open = fn(ns, W, R), crop = global frame name }.
local S = {}

local function mod(name, key, enabled)
    return { name = "Gulli-" .. name, enabled = enabled ~= false, loaded = enabled ~= false,
             meta = { ["X-Gulli-Module"] = key or name, Version = "1.0.0" } }
end
S.toolkit = { default = {
    spec = { addons = { { name = "Gulli-Toolkit", enabled = true, loaded = true, meta = { Version = "1.3.0" } },
        mod("QuestCleaner"), mod("BagSpace"), mod("Merchant"), mod("MobFinder", nil, false), mod("Bulletin"),
        mod("Attune"), mod("XP"), mod("Restock"), mod("Mail"),
        { name = "Gulli-Loot", enabled = false, loaded = true, meta = { ["X-Gulli-Module"] = "Loot", Version = "1.0.0" } } } },
    open = function(ns)
        UpdateAddOnMemoryUsage = function() end
        GetAddOnMemoryUsage = function(name)
            return ({ ["Gulli-QuestCleaner"] = 1900, ["Gulli-XP"] = 360, ["Gulli-Mail"] = 240 })[name] or 120
        end
        GulliToolkit.Register({ key = "Loot", open = function() end, slash = "/glt",
            icon = "Interface\\AddOns\\Gulli-Loot\\icon", summary = function() return "12 item rules" end })
        for _, k in ipairs({ "QuestCleaner", "BagSpace", "Merchant", "Bulletin", "Attune", "XP", "Restock", "Mail" }) do
            GulliToolkitDB.paused = { Restock = true }
            GulliToolkit.Register({ key = k, open = function() end, slash = "/g" .. k:sub(1, 2):lower(),
                pause = function() end,
                icon = "Interface\\AddOns\\Gulli-" .. k .. "\\icon",
                options = k == "QuestCleaner" and {
                    { label = "Keep class quests", get = function() return true end, set = function() end,
                      icon = "Interface\\Icons\\INV_Misc_Book_09" },
                    { label = "Keep dungeon and raid quests", get = function() return false end, set = function() end,
                      icon = "Interface\\Icons\\INV_Misc_Key_14" },
                } or nil })
        end
        local sums = { XP = "Level 42 in 35 min (8.4k XP/h)", Attune = "Onyxia: 3 of 7 steps",
            BagSpace = "2 free slots", Mail = "3 letters, 1 back in 2 days", Bulletin = "4 groups looking for players, 6 trade posts",
            Merchant = "5 junk items, 1g 20s", Restock = "3 items to buy", QuestCleaner = "Quest log 23 of 25" }
        for k, text in pairs(sums) do GulliToolkit.modules[k].summary = function() return text end end
        GulliToolkit.Notify("BagSpace", "Your bags are almost full: 2 free slots.")
        GulliToolkit.Notify("XP", "Level 42 in about 35 min at this pace.")
        GulliToolkitDB.feed[2].t = 1000 - 1500
        SlashCmdList.GULLITOOLKIT("")
    end,
} }

-- A narrow module open inside the hub, with the card beside it.
S.toolkit.inside = { spec = S.toolkit.default.spec,
    open = function(ns, W, R)
        S.toolkit.default.open(ns, W, R)
        local Sk = ns.Skin
        local win = Sk.Window("GulliPreviewMerchant", "Gulli Merchant", Sk.NARROW_W, 400, { sub = "/gmc",
            icon = "Interface\\AddOns\\Gulli-Merchant\\icon" })
        local c = Sk.SettingsCard(win.body, "Settings", {
            { "Sell gray items", nil, function() return true end, function() end, icon = "Interface\\Icons\\INV_Misc_Coin_02" },
            { "Repair", nil, function() return true end, function() end, icon = "Interface\\Icons\\Trade_BlackSmithing" } })
        c:SetPoint("TOPLEFT"); c:SetPoint("TOPRIGHT")
        GulliToolkit.modules.Merchant.window = function() return win end
        GulliToolkit.modules.Merchant.reset = function() end
        ns.Enter("Merchant")
    end,
}

-- The minimap button on a stand-in minimap, after a drag to the lower left.
S.toolkit.minimap = {
    spec = { addons = { { name = "Gulli-Toolkit", enabled = true, loaded = true, meta = { Version = "1.5.0" } } } },
    crop = "GulliToolkitMinimapStage",
    before = function()
        local stage = CreateFrame("Frame", "GulliToolkitMinimapStage", UIParent)
        stage:SetSize(220, 220)
        stage:SetPoint("CENTER")
        local bg = stage:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.067, 0.071, 0.082, 1)
        Minimap = CreateFrame("Frame", "Minimap", stage)
        Minimap:SetSize(140, 140)
        Minimap:SetPoint("CENTER")
        local map = Minimap:CreateTexture(nil, "BACKGROUND")
        map:SetAllPoints()
        map:SetColorTexture(0.32, 0.38, 0.26, 1)
        map:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    end,
    open = function() end,
}

S.merchant = { default = {
    spec = { slots = { { 0, 1, 10, 3, 0 }, { 0, 2, 11, 1, 0 }, { 0, 4, 13, 1, 0 } },
             prices = { [10] = 125, [11] = 4210, [13] = 80 }, db = { sell = true, repair = true, guild = false } },
    open = function(ns) ns.atVendor = true; ns.Toggle() end,
}, rich = {
    -- a long money value in the junk tile
    spec = { slots = { { 0, 1, 10, 3, 0 }, { 0, 2, 11, 1, 0 }, { 0, 4, 13, 1, 0 } },
             prices = { [10] = 4892, [11] = 8189, [13] = 112 }, db = { sell = true, repair = true, guild = false } },
    open = function(ns) ns.atVendor = true; ns.Toggle() end,
} }

local BAG_ITEMS = {
    [1] = { name = "Broken Fang", quality = 0, price = 5, maxStack = 20 },
    [2] = { name = "Torn Hide", quality = 0, price = 50 },
    [3] = { name = "Worn Shortsword", quality = 1, price = 30, classID = 2 },
    [4] = { name = "Linen Cloth", quality = 1, price = 10, maxStack = 20, classID = 7 },
    [5] = { name = "Tough Jerky", quality = 1, price = 1, maxStack = 20, classID = 0 },
    [9] = { name = "Cracked Pottery", quality = 0, price = 12 },
    [10] = { name = "Patched Leather Boots", quality = 1, price = 45, classID = 4 },
    [11] = { name = "Chipped Claw", quality = 0, price = 8, maxStack = 20 },
    [6948] = { name = "Hearthstone", quality = 1, price = 0, classID = 15 },
}
S.bagspace = { default = {
    spec = { items = BAG_ITEMS, bags = {
        [0] = { size = 16, slots = {
            [1] = { id = 1, count = 3 }, [2] = { id = 2, count = 1 }, [3] = { id = 3, count = 1 },
            [4] = { id = 4, count = 15 }, [5] = { id = 4, count = 8 }, [6] = { id = 9, count = 1 },
            [7] = { id = 10, count = 1 }, [8] = { id = 6948, count = 1 }, [9] = { id = 11, count = 4 },
            [10] = { id = 5, count = 6 }, [11] = { id = 11, count = 2 }, [12] = { id = 3, count = 1 },
            [13] = { id = 4, count = 3 }, [14] = { id = 1, count = 1 } } },
    }, db = { want = 6 } },
} }

local atSpec = { name = "Gulliby", faction = "Horde", party = { "Thorn", "Mirela" }, guild = true,
    done = { [4903] = true, [4941] = true, [4974] = true, [6566] = true, [6567] = true, [6568] = true, [6569] = true,
             [6570] = true, [6583] = true, [4742] = true, [3801] = true, [3802] = true },
    db = { chars = {
        ["Thorn-Realm"] = { name = "Thorn", class = "WARRIOR", level = 60, faction = "Horde", done = { [4742] = true, [4743] = true }, active = {} },
        ["Bank-Realm"] = { name = "Bankalt", class = "MAGE", level = 12, faction = "Horde", done = {}, active = {} },
    } } }
local function atOthers(ns)
    ns.Scan()
    ns.Receive("GulliAT", "S\tONY=14/14,UBRS=R,BRD=R,SCHOLO=3/8,MARA=0/2", "PARTY", "Thorn")
    ns.Receive("GulliAT", "S\tONY=R,UBRS=R,BRD=R,SCHOLO=R,MARA=R", "GUILD", "Oldguard")
end
S.attune = {
    default = { spec = atSpec, open = function(ns) atOthers(ns); ns.Toggle() end },
    all = { spec = atSpec, open = function(ns) atOthers(ns); ns.Toggle(); ns.ShowTab(2) end },
    group = { spec = atSpec, open = function(ns) atOthers(ns); ns.Toggle(); ns.ShowTab(3) end },
    settings = { spec = atSpec, open = function(ns) atOthers(ns); ns.Toggle(); ns.ShowTab(4) end },
}

local function xpQuests()
    local quests = { { questID = 1, xp = 2450 }, { questID = 2, xp = 1800 } }
    C_QuestLog = { GetNumQuestLogEntries = function() return #quests end, GetInfo = function(i) return quests[i] end,
                   IsComplete = function() return true end }
    GetQuestLogRewardXP = function(id) return quests[id].xp end
end
local function xpPlay(W)
    W.Fire("PLAYER_ENTERING_WORLD", true, false)
    for i = 1, 30 do W.now = i * 120; W.Fire("CHAT_MSG_COMBAT_XP_GAIN", "Wolf dies, you gain 215 experience."); W.Gain(215) end
    W.now = 3700; W.Fire("QUEST_TURNED_IN", 1, 1450, 0); W.Gain(1450)
end
S.xp = { default = {
    spec = { level = 41, xp = 12000, xpMax = 31000, rested = 4200, now = 0,
             cdb = { levels = { { level = 40, time = 4380, kills = 212, killXP = 38100, questXP = 21400 },
                                { level = 39, time = 3900, kills = 190, killXP = 33000, questXP = 22800 },
                                { level = 38, time = 5100, kills = 260, killXP = 37200, questXP = 15900, partial = true } } } },
    before = xpQuests,
    open = function(ns, W) xpPlay(W); ns.Toggle() end,
}, levels = {
    before = xpQuests,
    open = function(ns, W) S.xp.default.open(ns, W); ns.Tabs():Select(2) end,
}, settings = {
    before = xpQuests,
    open = function(ns, W) S.xp.default.open(ns, W); ns.Tabs():Select(3) end,
}, bar = {
    spec = { level = 41, xp = 12000, xpMax = 31000, rested = 6200, now = 0, db = { alpha = 60, scale = 140 } },
    before = xpQuests,
    open = function(ns, W) xpPlay(W); ns.Refresh() end,
    crop = "GulliXPBar",
} }
S.xp.bar = { before = xpQuests, crop = "GulliXPBar",
    open = function(ns, W) xpPlay(W); ns.SetPref("wide", false); ns.Refresh() end }
S.xp.bar.spec = S.xp.default.spec
S.xp.levels.spec = S.xp.default.spec
S.xp.settings.spec = S.xp.default.spec

S.loot = { default = {
    spec = { db = { quality = { [0] = "pass", [1] = "greed" }, items = { [2589] = "need", [2592] = "greed" }, report = true } },
    before = function()
        C_Item = C_Item or {}
        C_Item.GetItemNameByID = function(id) return ({ [2589] = "Linen Cloth", [2592] = "Wool Cloth" })[id] end
    end,
} }

S.partyquests = { default = { spec = { level = 17,
    quests = {
        { title = "Westfall", isHeader = true },
        { title = "The Defias Brotherhood", questID = 155, level = 18 },
        { title = "Red Leather Bandanas", questID = 153, level = 15 },
        { title = "Patrolling Westfall", questID = 102, level = 14 },
        { title = "Redridge Mountains", isHeader = true },
        { title = "Blackrock Menace", questID = 20, level = 21 },
    },
    party = { { name = "Ann", quests = { [155] = true, [20] = true } }, { name = "Bob", quests = { [155] = true, [153] = true } } },
    objectives = { [155] = { { text = "Defias Pillager slain: 3/8", type = "monster", numFulfilled = 3, numRequired = 8 } },
                   [153] = { { text = "Red Leather Bandana: 15/15", type = "item", numFulfilled = 15, numRequired = 15 } } },
    items = { [10] = "Red Leather Bandana" }, bags = { { id = 10, count = 17 } },
    zone = "Westfall",
}, open = function(ns)
    for _, p in ipairs({ "B", "Q155,20", "O155:6/8", "E" }) do ns.Receive(p, "Ann") end
    ns.Toggle()
end }, settings = { spec = { party = { { name = "Ann", quests = {} } } }, open = function(ns)
    ns.ShowTab(3)
end } }

S.bulletin = { default = { spec = { level = 56, guids = { P1 = "WARRIOR", P2 = "PRIEST", P3 = "MAGE", P4 = "ROGUE" } },
    open = function(ns, W)
        local msgs = {
            { "LF2M Deadmines need tank and heal", "Thrall" }, { "Priest LFG Scholo or Strat", "Anduin" },
            { "LFM SM:GY pst, 1 dps left", "Varian" }, { "UBRS 8/10 need 2", "Jaina" }, { "LF1M Strat UD need heals", "Sylvanas" },
            { "WTS |cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|r 20x 1g", "Gelbin" },
        }
        for i, m in ipairs(msgs) do
            W.Fire("CHAT_MSG_CHANNEL", m[1], m[2] .. "-Realm", "", "2. Trade", "", "", 0, 2, "Trade", nil, i, "P" .. i)
        end
        ns.Toggle()
    end,
}, trade = { spec = { level = 56 },
    open = function(ns, W)
        ns.Add("WTS |cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|r 20x 1g, |cff1eff00|Hitem:7909::::::::|h[Aquamarine]|h|r 3g", "Gelbin")
        ns.Add("WTS [Arcanite Bar] cheap, pst", "Rexxar")
        ns.ShowTab(2)
    end,
}, craft = { spec = { level = 56 },
    open = function(ns)
        ns.Add("LF enchanter for Crusader, have mats", "Ann")
        ns.Add("Tailor LFW, your mats, tips welcome", "Bob")
        ns.Add("need a BS to make Arcanite Reaper", "Cid")
        ns.Add("WTS |cffffd000|Henchant:13644|h[Enchant Boots - Lesser Stamina]|h|r 1s/each", "Dan")
        ns.Add("any lockpick around? got a lockbox", "Eve")
        ns.ShowTab(4)
    end,
}, setup = { spec = { level = 56, channels = { 1, "General", false, 2, "Trade", false } },
    open = function(ns)
        ns.db.only.STRAT, ns.db.only.SCHOLO, ns.db.alert.STRAT, ns.db.alert.HYJAL = true, true, true, true
        ns.ShowTab(7)
    end,
} }

S.quickchat = {
    default = {},
    edit = { open = function(ns)
        ns.ToggleFav("Ready!"); ns.ToggleFav("brb"); ns.db.chan["Need a heal!"] = "PARTY"
        ns.ShowPage(1, { editing = true })
    end },
    group = { spec = { level = 12 }, open = function(ns) ns.Toggle() end },
    dungeon = { spec = { level = 57, areas = { [2017] = "Stratholme" } }, open = function(ns)
        ns.ShowPage(2, { mode = 2 })
    end },
    whispers = { open = function(ns, W)
        W.combat = true
        W.Fire("CHAT_MSG_WHISPER", "can you craft a bag?", "Ann-Realm")
        W.Fire("CHAT_MSG_WHISPER", "inv for ST?", "Bob")
        W.combat = false
        ns.ShowPage(3)
    end },
    more = { open = function(ns)
        ns.Say("Ready!"); ns.Say("brb", "GUILD")
        ns.ShowPage(4)
    end },
    setup = { open = function(ns) ns.db.wheelKey = "F5"; ns.ShowPage(5) end },
    wheel = { crop = "GulliQuickChatWheel", open = function(ns)
        for _, p in ipairs({ "inv please", "Ready!", "brb", "Back", "Thanks for the group!", "On my way",
                             "Need a heal!", "WTS {item}, pst" }) do ns.ToggleFav(p) end
        ns.ToggleWheel()
        ns.WheelHover(2)
    end },
}

local QC = {
    quests = {
        { title = "Elwynn Forest", isHeader = true },
        { title = "Wolves Across the Border", level = 6, questID = 101, objectives = { { text = "Tough Wolf Meat: 3/8" } } },
        { title = "Kobold Candles", level = 8, questID = 102, objectives = { { text = "Large Candle: 2/8" } } },
        { title = "Westfall", isHeader = true },
        { title = "The Killing Fields", level = 14, questID = 103, objectives = { { text = "Harvest Watcher: 4/20" } } },
        { title = "Red Leather Bandanas", level = 15, questID = 104, objectives = { { text = "Red Leather Bandana: 5/15" } } },
        { title = "Redridge Mountains", isHeader = true },
        { title = "Blackrock Menace", level = 21, questID = 105 },
    },
    bag = {
        { id = 1, name = "Tough Wolf Meat", class = 12, count = 3 },
        { id = 2, name = "Large Candle", class = 12, count = 2 },
        { id = 3, name = "Red Leather Bandana", class = 12, count = 5 },
        { id = 4, name = "Old Note", class = 12 },
    },
    level = 22,
}
S.questcleaner = {
    default = { spec = QC, open = function(ns) ns.Toggle() end },
    preview = { spec = QC, open = function(ns, W, R)
        ns.Toggle()
        ns.charDB().level = 16
        GulliQuestCleanerFrame:GetScript("OnShow")()
        local function find(f)
            if f.GetText and f:GetText() == ns.L.CLEAR and rawget(f, "_OnClick") then return f end
            for _, c in ipairs(f.__children) do local x = find(c); if x then return x end end
        end
        find(GulliQuestCleanerFrame):GetScript("OnClick")()
    end },
}

local function gbUnits(class)
    return { player = { name = "Me", class = class, auras = {} },
             party1 = { name = "Tank", class = "WARRIOR", auras = {}, role = "TANK", inGroup = true },
             party2 = { name = "Mage", class = "MAGE", auras = {}, inGroup = true } }
end
local function gbOpen(ns) ns.Toggle() end
S.groupbuffs = {
    default = { spec = { units = gbUnits("PRIEST") }, open = gbOpen, crop = "GulliGroupBuffsSettings" },
    shaman = { spec = { units = gbUnits("SHAMAN") }, open = gbOpen, crop = "GulliGroupBuffsSettings" },
}

local function choresChars(W)
    W.char.mail, W.char.free, W.char.durability = true, 2, { 22, 60 }
    W.char.spells[17187], W.char.rested = true, 600
    W.char.items[6948], W.char.bind = 1, "Goldshire"
    W.char.profs = { { "Tailoring", 150, 150, "Interface\\Icons\\Trade_Tailoring" }, { "Cooking", 112, 225, "Interface\\Icons\\INV_Misc_Food_15" },
                     { "First Aid", 1, 75, "Interface\\Icons\\Spell_Holy_SealOfSacrifice" } }
    W.char.inbox = { { 0, 0, 1.6, 2 } }
    GulliChoresDB = { chars = {
        ["Lirra-Realm"] = { name = "Lirra", class = "MAGE", level = 38, t = W.now - 30 * 3600, realm = "Realm",
            faction = "Alliance", rested = 0.9, resting = true, money = 1234500, durability = 88, free = 9,
            trainer = 38, cooldowns = { CD_MOONCLOTH = W.now - 60 }, hearth = W.now - 10, bind = "Shadowprey Village",
            played = 3 * 86400 + 14 * 3600, mailUntil = W.now + 2 * 86400, mailItems = 3,
            profs = { { name = "Tailoring", icon = "Interface\\Icons\\Trade_Tailoring", skill = 171, cap = 225 },
                      { name = "Enchanting", icon = "Interface\\Icons\\Trade_Engraving", skill = 164, cap = 225 },
                      { name = "Fishing", icon = "Interface\\Icons\\Trade_Fishing", skill = 198, cap = 225 },
                      { name = "Cooking", icon = "Interface\\Icons\\INV_Misc_Food_15", skill = 150, cap = 150 },
                      { name = "First Aid", icon = "Interface\\Icons\\Spell_Holy_SealOfSacrifice", skill = 1, cap = 75 } } },
        ["Bankie-Realm"] = { name = "Bankie", class = "ROGUE", level = 6, t = W.now - 5 * 86400, realm = "Realm",
            faction = "Alliance", rested = 1.5, resting = true, money = 40000, durability = 100, free = 1,
            trainer = 6, cooldowns = {}, note = "bank" },
        ["Thorn-Realm"] = { name = "Thorn", class = "WARRIOR", level = 60, maxLevel = true, t = W.now - 2 * 86400,
            realm = "Realm", faction = "Alliance", money = 8705000, durability = 54, free = 14, trainer = 60,
            cooldowns = { CD_TRANSMUTE = W.now + 9 * 3600 } },
    } }
end
local function choresTab(i)
    return function(ns) ns.Toggle(); ns.ReadMail(); ns.Tabs():Select(i) end
end
S.chores = {
    default = { spec = { level = 42, class = "PRIEST" }, before = choresChars, open = choresTab(1) },
    overview = { spec = { level = 42, class = "PRIEST" }, before = choresChars, open = choresTab(2) },
    settings = { spec = { level = 42, class = "PRIEST" }, before = choresChars, open = choresTab(3) },
}

S.craftprofit = { default = {
    spec = {
        items = {
            [1] = { name = "Silk Cloth", ah = 160, sell = 38, bags = 120, bank = 80, icon = "Interface\\Icons\\INV_Fabric_Silk_01" },
            [2] = { name = "Bolt of Silk Cloth", ah = 900, sell = 150, icon = "Interface\\Icons\\INV_Fabric_Silk_02" },
            [3] = { name = "Blue Dye", sell = 12, icon = "Interface\\Icons\\INV_Potion_13" },
            [4] = { name = "Azure Silk Hood", ah = 1500, sell = 420, quality = 2, icon = "Interface\\Icons\\INV_Helmet_29" },
            [5] = { name = "Fine Thread", sell = 25, icon = "Interface\\Icons\\INV_Fabric_Linen_02" },
            [6] = { name = "Silk Headband", ah = 2600, sell = 520, quality = 2, icon = "Interface\\Icons\\INV_Misc_Bandana_03" },
            [7] = { name = "Pattern: Crimson Silk Vest", sell = 1, icon = "Interface\\Icons\\INV_Scroll_03" },
        },
        prof = { name = "Tailoring", skill = 150, cap = 225, recipes = {
            { id = 101, name = "Bolt of Silk Cloth", learned = true, diff = 3, grey = 145, out = 2, r = { [1] = 4 } },
            { id = 102, name = "Azure Silk Hood", learned = true, diff = 0, grey = 175, out = 4, r = { [2] = 2, [3] = 2 } },
            { id = 103, name = "Silk Headband", learned = true, diff = 0, grey = 185, out = 6, r = { [2] = 3, [5] = 2 } },
            { id = 104, name = "Crimson Silk Vest", learned = false, out = 7, r = { [1] = 1 }, source = "Vendor: Somebody" },
        } },
        vendor = { { 3, 50 }, { 5, 100 } },
        trainer = { { "Silk Headband", 300 } },
    },
    before = function()
        GetProfessions = function() return 1, 2 end
        GetProfessionInfo = function(i)
            if i == 1 then return "Tailoring", "Interface\\Icons\\Trade_Tailoring", 150, 225 end
            return "Enchanting", "Interface\\Icons\\Trade_Engraving", 92, 150
        end
    end,
    open = function(ns, W)
        W.Fire("MERCHANT_SHOW")
        W.Fire("TRADE_SKILL_SHOW")
        W.RunTimers()
        ns.Toggle(); ns.Calculate()
    end,
} }

S.craftprofit.prompt = { spec = S.craftprofit.default.spec, before = S.craftprofit.default.before,
    open = function(ns, W) W.Fire("MERCHANT_SHOW"); W.Fire("TRADE_SKILL_SHOW"); W.RunTimers(); ns.Toggle() end }
S.craftprofit.busy = { spec = S.craftprofit.default.spec, before = S.craftprofit.default.before,
    open = function(ns, W)
        S.craftprofit.prompt.open(ns, W)
        local t = 0
        debugprofilestop = function() t = t + 3; return t end
        ns.Calculate()
        for _ = 1, 3 do if ns.Busy() then ns.calcDriver:GetScript("OnUpdate")() end end
        debugprofilestop = nil
    end }
S.craftprofit.many = { spec = S.craftprofit.default.spec, before = S.craftprofit.default.before,
    open = function(ns, W)
        S.craftprofit.default.open(ns, W)
        for _, x in ipairs(ns.view.variants) do x.plan = x.plan or ns.view.plan end
        ns.Refresh()
    end }
S.craftprofit.legs = { spec = S.craftprofit.default.spec, before = S.craftprofit.default.before,
    open = function(ns, W) S.craftprofit.default.open(ns, W); ns.SelectLeg(2) end }
S.craftprofit.nolimit = { spec = S.craftprofit.default.spec, before = S.craftprofit.default.before,
    open = function(ns, W) S.craftprofit.default.open(ns, W); ns.SetPref("maxSell", 0); ns.SetPref("maxBuy", 0) end }
S.craftprofit.unknown = { spec = S.craftprofit.default.spec, before = S.craftprofit.default.before,
    open = function(ns, W) S.craftprofit.default.open(ns, W); ns.SelectLeg(#ns.view.legs) end }
S.craftprofit.crafts = { spec = S.craftprofit.default.spec, before = S.craftprofit.default.before,
    open = function(ns, W) S.craftprofit.default.open(ns, W); ns.Tab(2) end }

S.craftprofit.recipes = { spec = S.craftprofit.default.spec, before = S.craftprofit.default.before,
    open = function(ns, W) S.craftprofit.default.open(ns, W); ns.Tab(4) end }

S.craftprofit.earn = { spec = S.craftprofit.default.spec, before = S.craftprofit.default.before,
    open = function(ns, W) S.craftprofit.default.open(ns, W); ns.SetPref("mode", "earn") end }

S.craftprofit.auction = { spec = S.craftprofit.default.spec, before = S.craftprofit.default.before,
    open = function(ns, W) S.craftprofit.default.open(ns, W); ns.atAH = true; ns.Select(2) end }
S.craftprofit.craft = { spec = S.craftprofit.default.spec, before = S.craftprofit.default.before,
    open = function(ns, W)
        S.craftprofit.default.open(ns, W)
        for i, n in ipairs(ns.view.route) do if n.segs then ns.Select(i) break end end
    end }

S.mail = { panel = {
    spec = { inbox = { { sender = "Auction House", subject = "Auction successful: Linen Cloth", invoice = "seller", money = 4210 },
                       { sender = "Auction House", subject = "Auction won: Silk Cloth", invoice = "buyer", items = { 2589 } },
                       { sender = "Bob", subject = "Herbs", items = { 765, 785 }, days = 2.4 },
                       { sender = "Auction House", subject = "Auction expired: Copper Ore", items = { 2770 }, days = 25, player = false } } },
    open = function(ns, W) W.Fire("PLAYER_LOGIN"); W.Fire("MAIL_SHOW"); ns.visit.items, ns.visit.money, ns.visit.sold = 3, 26664, 26664; ns.Refresh() end,
    crop = "GulliMailPanel",
}, write = {
    spec = { friends = { "Amy", "Zed" }, guild = { "Gil" }, inbox = {},
             bags = { [0] = { { id = 2589, count = 20 }, { id = 2589, count = 20 }, { id = 4306, count = 12 },
                              { id = 2770, count = 10 }, { id = 2318, count = 8 }, { id = 2318, count = 4 },
                              { id = 10940, count = 6 }, { id = 774, count = 1 } } },
             classes = { [2589] = { 7, 5 }, [4306] = { 7, 5 }, [2770] = { 7, 7 }, [2318] = { 7, 6 },
                         [10940] = { 7, 12 }, [774] = { 3, 0 } } },
    open = function(ns, W)
        local icons = { [2589] = "Interface\\Icons\\INV_Fabric_Linen_01", [4306] = "Interface\\Icons\\INV_Fabric_Silk_01", [2770] = "Interface\\Icons\\INV_Ore_Copper_01",
                        [2318] = "Interface\\Icons\\INV_Misc_LeatherScrap_03", [10940] = "Interface\\Icons\\INV_Enchant_DustStrange", [774] = "Interface\\Icons\\INV_Misc_Gem_Emerald_03",
                        [2447] = "Interface\\Icons\\INV_Misc_Flower_02", [7067] = "Interface\\Icons\\INV_Stone_02" }
        C_Item.GetItemIconByID = function(id) return icons[id] end
        W.Fire("PLAYER_LOGIN"); W.Fire("MAIL_SHOW"); SendMailFrame:Show(); ns.ShowTab(2)
    end,
    crop = "GulliMailPanel",
}, settings = {
    spec = {},
    open = function(ns) ns.Toggle() end,
} }

-- A level 33 Horde tauren in Orgrimmar, Gnomeregan chosen.
local dpIcons = { "INV_Pants_03", "INV_Weapon_Rifle_05", "INV_Chest_Chain_05", "INV_Gauntlets_04", "INV_Boots_05" }
local dpItems = setmetatable({ [6893] = { "Workshop Key", 1, 1, "", 13, 0, "Interface\\Icons\\INV_Misc_Key_06" } },
    { __index = function(_, id)
        return { "Reward " .. id, 2, 34 + id % 4, ({ "INVTYPE_LEGS", "INVTYPE_RANGEDRIGHT", "INVTYPE_CHEST" })[id % 3 + 1],
                 id % 3 == 1 and 2 or 4, id % 3 == 1 and 3 or (id % 2 == 0 and 3 or 1),
                 "Interface\\Icons\\" .. dpIcons[id % #dpIcons + 1] }
    end })
local dpSpec = { level = 33, raceID = 6, faction = "Horde", className = "HUNTER", ammo = 320, counts = { [6893] = 1 },
    items = dpItems, active = { [2841] = true }, party = { { name = "Thorn", quests = { [2841] = true } } },
    areas = { [1637] = "Orgrimmar", [33] = "Stranglethorn Vale", [721] = "Gnomeregan", [1497] = "Undercity", [1] = "Dun Morogh" },
    map = { best = 1454, pos = { 0.70, 0.30 },
            maps = { [1414] = { "Kalimdor", 2 }, [1454] = { "Orgrimmar", 3, 1414 } } },
    bags = { [0] = { size = 16, slots = { [1] = { 4540, 4 } } } } }
S.dungeonprep = {
    default = { spec = dpSpec, open = function(ns) ns.selected = "GNOMER"; ns.Toggle() end },
    settings = { spec = dpSpec, open = function(ns) ns.selected = "GNOMER"; ns.Toggle(); ns.ShowTab(2) end },
}

-- Spell icons by id for the Reminders previews (the fake client has none).
local REM_ICONS = { [1243] = "Interface\\Icons\\Spell_Holy_WordFortitude", [588] = "Interface\\Icons\\Spell_Holy_InnerFire",
    [14752] = "Interface\\Icons\\Spell_Holy_DivineSpirit", [976] = "Interface\\Icons\\Spell_Shadow_AntiShadow",
    [13165] = "Interface\\Icons\\Spell_Nature_RavenForm", [19506] = "Interface\\Icons\\Ability_TrueShot",
    [883] = "Interface\\Icons\\Ability_Hunter_BeastCall", [324] = "Interface\\Icons\\Spell_Nature_LightningShield" }
local function remIcons()
    C_Spell.GetSpellTexture = function(id) return REM_ICONS[id] end
end
-- The panel on a dark stand-in screen, with room for its names.
local function remStage(W)
    remIcons()
    local stage = CreateFrame("Frame", "GulliRemindersStage", UIParent)
    stage:SetSize(460, 260)
    stage:SetPoint("CENTER")
    local bg = stage:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.16, 0.2, 0.16, 1)
end
S.reminders = {
    -- The panel goes to a corner, out of the window's picture.
    default = { spec = { class = "PRIEST", known = { 1243, 588, 976 }, auras = { "Spell1243" },
                         left = { Spell1243 = 140 }, db = { point = { "BOTTOMLEFT", 0, 0 } } }, before = remIcons },
    panel = { spec = { class = "PRIEST", known = { 1243, 588, 976 }, auras = { "Spell1243" },
                       left = { Spell1243 = 140 } },
              before = remStage, open = function(ns) ns.db.point = { "CENTER", 0, 20 }; ns.Refresh() end,
              crop = "GulliRemindersStage" },
    unlocked = { spec = { class = "HUNTER", known = { 13165, 19506, 883 }, auras = { "Spell13165" }, ammo = 120,
                          db = { locked = false, vertical = true } },
                 before = remStage, open = function(ns) ns.db.point = { "CENTER", -60, 0 }; ns.Refresh() end,
                 crop = "GulliRemindersStage" },
    hunter = { spec = { class = "HUNTER", known = { 13165, 19506, 883 }, ammo = 120,
                        db = { point = { "BOTTOMLEFT", 0, 0 } } }, before = remIcons },
}

S.autoquest = {
    default = { spec = { db = { session = { taken = 12, done = 9, clicks = 63 } } } },
    rules = { spec = {}, open = function(ns) ns.ShowTab(2) end },
    ignored = { spec = { db = { ignoreNpc = { [500] = "Marshal Dughan" }, ignoreQuest = { [7] = "Kobold Camp Cleanup" } } },
                open = function(ns) ns.ShowTab(3) end },
}

S.instancelimit = { default = { spec = { name = "Gulliby" },
    open = function(ns, W)
        local now = W.now
        ns.db.entries = {
            { t = now - 3000, name = "The Deadmines", char = "Gulliby", class = "MAGE", out = now - 1500, secs = 1500, xp = 4200, money = 13250, kills = 41 },
            { t = now - 1200, name = "Wailing Caverns", char = "Gulliby", class = "MAGE", out = now - 200, secs = 1000, xp = 3100, money = 870, kills = 28 },
            { t = now - 900, name = "Shadowfang Keep", char = "Thorn", class = "WARRIOR", out = now - 100, secs = 800, xp = 2500, kills = 30 },
            { t = now - 60, name = "Blackfathom Deeps", char = "Gulliby", class = "MAGE" },
        }
        ns.group = { Bob = { leftHour = 1, leftDay = 20, wait = 0, t = now } }
        ns.Toggle()
    end,
}, settings = { open = function(ns) ns.ShowPage(2) end } }

local RESTOCK_SPEC = { level = 42, class = "MAGE", money = 254000,
    bags = { [17031] = 3, [17032] = 8, [17020] = 34, [1708] = 12, [4599] = 30, [8766] = 0 },
    bank = { [17020] = 40, [17031] = 10 },
    items = { [17031] = { stack = 20, classID = 5 }, [17032] = { stack = 20, classID = 5 },
              [17020] = { stack = 20, classID = 5 }, [4599] = { stack = 20, classID = 0 } },
    vendor = { { 17031, 1000 }, { 17032, 2000 }, { 17020, 1000 }, { 1708, 200, 5 }, { 1645, 400, 5 }, { 3927, 500, 5 },
               { 8766, 800, 5 } },
    char = { sets = { Main = { [17031] = 10, [17032] = 10, [17020] = 40, ["best:water"] = 40, [4599] = 20 },
                      Raid = { [17020] = 60 } }, set = "Main" } }
S.restock = { default = { spec = RESTOCK_SPEC, open = function(ns) ns.Toggle() end },
    vendor = { spec = RESTOCK_SPEC, open = function(ns) ns.atVendor = true; ns.Toggle(); ns.ShowTab(2) end },
    settings = { spec = RESTOCK_SPEC, open = function(ns) ns.Toggle(); ns.ShowTab(3) end },
    plan = { spec = RESTOCK_SPEC, crop = "GulliRestockPlan", open = function(ns) ns.atVendor = true; ns.ShowPlan(ns.Plan()) end },
}
S.social = { default = {}, recent = { spec = { group = { 3, true } },
    open = function(ns, W)
        ns.db.blockStrangers, ns.db.noDuels = true, true
        W.Fire("PARTY_INVITE_REQUEST", "Randomguy")
        W.Fire("DUEL_REQUESTED", "Ganker")
        W.Fire("CHAT_MSG_WHISPER", "inv", "Thrall")
        ns.Log("spam", "Goldseller")
        ns.ShowPage(2)
    end,
} }


-- Gulli HUD: things on the game screen, each on a dark stand-in screen named GulliHudStage.
local function hudStage(w, h)
    return function()
        local stage = CreateFrame("Frame", "GulliHudStage", UIParent)
        stage:SetSize(w or 460, h or 220)
        stage:SetPoint("CENTER")
        local bg = stage:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.13, 0.16, 0.12, 1)
    end
end
local function fire(W, event, ...)
    for _, f in ipairs(W.frames) do
        local fn = f:GetScript("OnEvent")
        if fn then fn(f, event, ...) end
    end
end
local GB_ICONS = { [1243] = "Interface\\Icons\\Spell_Holy_WordFortitude", [588] = "Interface\\Icons\\Spell_Holy_InnerFire",
    [14752] = "Interface\\Icons\\Spell_Holy_DivineSpirit", [976] = "Interface\\Icons\\Spell_Shadow_AntiShadow",
    [21562] = "Interface\\Icons\\Spell_Holy_PrayerOfFortitude" }
local function gbBar(W)
    hudStage(460, 200)()
    C_Spell.GetSpellTexture = function(id) return GB_ICONS[id] end
end
S.groupbuffs.bar = { spec = { units = gbUnits("PRIEST"), known = { [1243] = true, [588] = true, [14752] = true, [976] = true },
    db = { point = { "CENTER", -40, 20 }, key = "F" } },
    before = gbBar, open = function(ns, W) fire(W, "PLAYER_LOGIN") end, crop = "GulliHudStage" }
S.groupbuffs.move = { spec = S.groupbuffs.bar.spec, before = gbBar,
    open = function(ns, W) fire(W, "PLAYER_LOGIN"); ns.Move(true) end, crop = "GulliHudStage" }

-- Every Gulli HUD widget on one stand-in screen: notices, an action icon, reminders, a counter,
-- a feed and the move bar.
S.toolkit.hud = { spec = S.toolkit.default.spec, before = hudStage(900, 470), crop = "GulliHudStage",
    open = function(ns)
        local Sk = ns.Skin
        local stage = GulliHudStage
        GulliHUD = nil
        local I = "Interface\\Icons\\"
        Sk.Toast({ key = "1", icon = I .. "INV_Misc_Bag_08", kind = "warn", title = "Bags are full",
            text = "Free 1 slot: Cracked Pottery", seconds = 10, buttons = { { text = "Sell", primary = true } } })
        Sk.Toast({ key = "2", icon = I .. "INV_Letter_15", title = "Ann asks for a quest", text = "The Defias Brotherhood",
            seconds = 30, buttons = { { text = "Share", primary = true } } })
        Sk.Toast({ key = "3", icon = I .. "Spell_Nature_TimeStop", kind = "good", title = "A dungeon entry is free again.",
            text = "2 of 5 entries left this hour", seconds = 12 })
        for _, t in ipairs(GulliHUD.toasts) do
            local p = { t:GetPoint() }
            t:ClearAllPoints()
            t:SetPoint("TOP", stage, "TOP", 0, (p[5] or 0) + 130)
        end
        local act = Sk.HudIcon(CreateFrame("Button", nil, stage), 52)
        act:SetPoint("TOPLEFT", 24, -40)
        act:SetIcon(I .. "Spell_Holy_WordFortitude"); act:SetState("need"); act:SetKey("F"); act:SetCount("+3")
        local cap = Sk.HudCaption(stage, 52)
        cap:SetPoint("TOPLEFT", act, "TOPRIGHT", -1, 0)
        cap:Set("Power Word: Fortitude", "|cffc79c6eHero|r")
        for i, ic in ipairs({ "Spell_Holy_InnerFire", "Spell_Holy_DivineSpirit", "Spell_Shadow_AntiShadow" }) do
            local m = Sk.HudIcon(CreateFrame("Button", nil, stage), 28)
            m:SetPoint("TOPLEFT", act, "BOTTOMLEFT", (i - 1) * 32, -5)
            m:SetIcon(I .. ic)
            m:SetDone(i == 3)
        end
        local rem = { { "Spell_Holy_InnerFire", "need" }, { "Spell_Holy_WordFortitude", "soon", "4m" },
                      { "INV_Misc_Food_14", "need" }, { "INV_Ammo_Arrow_02", "soon" } }
        for i, r in ipairs(rem) do
            local b = Sk.HudIcon(CreateFrame("Button", nil, stage), 40)
            b:SetPoint("BOTTOMLEFT", 24 + (i - 1) * 44, 24)
            b:SetIcon(I .. r[1]); b:SetState(r[2]); b:SetMid(r[3])
            if i == 4 then b:SetCount("120") end
        end
        local chip = Sk.Chip(stage)
        chip:SetPoint("BOTTOMLEFT", 220, 30)
        chip:Set(I .. "Spell_Nature_TimeStop", "3/5", nil, 3, 5, "18 m")
        local list = Sk.HudList(nil, 300, 3, stage)
        list:SetPoint("BOTTOMRIGHT", -24, 24)
        list.title:SetText("Bulletin Board")
        list.right:SetText("3")
        list:SetRows({ { tag = "Deadmines", tagColor = Sk.LevelColor(20), text = "|cff3fc7ebLFM|r heal  Thorn", right = "1 m" },
            { tag = "Shadowfang", tagColor = Sk.LevelColor(24), text = "|cff3fc7ebLFM|r tank  Mirela", right = "3 m" },
            { tag = "Wailing Caverns", tagColor = Sk.LevelColor(19), text = "|cff3fc7ebLFG|r dps  Ann", right = "6 m" } })
    end }
S.mobfinder = S.mobfinder or {}
S.mobfinder.card = { spec = { level = 14 }, before = hudStage(460, 140), crop = "GulliHudStage",
    open = function(ns)
        ns.db.cardPoint = { "CENTER", 0, 0 }
        ns.ShowFind({ { name = "Foreman Grills" } })
    end }
S.instancelimit.badge = { spec = S.instancelimit.default.spec, before = function(W, R)
        hudStage(300, 120)()
        if S.instancelimit.default.before then S.instancelimit.default.before(W, R) end
    end, crop = "GulliInstanceLimitBadge",
    open = function(ns, W, R)
        ns.db.badgePoint = { "CENTER", "CENTER", 0, 0 }
        ns.db.badgeMode = ns.BADGE_MODES[1]
        ns.SetupBadge()
    end }
-- Legacy: the sample account of its test, with an alt and the XP module's pace.
local function lgSpec()
    local W = dofile("tests/legacy/wow.lua")
    return W.World({ db = { chars = { ["Gulliwar-Realm"] = { name = "Gulliwar", class = "WARLOCK", level = 22, skills = { [333] = 61 }, rate = 9800, spent = 4 },
                                       ["Gullihunt-Realm"] = { name = "Gullihunt", class = "HUNTER", level = 14, skills = {} } } },
                     xpdb = { s = { active = 3600, gained = 11800 } } })
end
local function lgOpen(tab)
    return function(ns)
        ns.Scan(); ns.Snapshot()
        ns.Pin(70010)
        ns.Toggle()
        if tab then ns.ShowTab(tab) end
    end
end
S.legacy = { default = { open = lgOpen() }, chars = { open = lgOpen(2) }, all = { open = lgOpen(3) },
    settings = { open = lgOpen(4) },
    goal = { open = function(ns) lgOpen()(ns); ns.SetGoal(15) end },
    tracker = { crop = "GulliLegacyTracker", open = function(ns) ns.Scan(); ns.Snapshot(); ns.Refresh() end },
    explore = { open = function(ns) lgOpen()(ns); ns.ShowDetail(70040) end },
    detail = { open = function(ns) lgOpen()(ns); ns.ShowDetail(70010) end } }
for _, sc in pairs(S.legacy) do sc.spec = lgSpec() end
-- Explore Azeroth with zones of every level, and Lord Valthalak for a level 37 character.
local function lgWorld(spec)
    spec.cats[7].achs = { 80000, 80010 }
    spec.ach[80010] = { name = "Lord Valthalak Laid to Rest", points = 1, crit = {}, icon = "Interface\\Icons\\INV_Jewelry_Amulet_07" }
    spec.ach[80000] = { name = "Explorer", points = 1, crit = { { "Explore Eastern Kingdoms", 8, false, 0, 1, 80001 } } }
    local zones = { { "Redridge Mountains", 15, 25, 11, 0 }, { "Silverpine Forest", 10, 20, 15, 11 }, { "Stranglethorn Vale", 30, 45, 27, 2 },
        { "Swamp of Sorrows", 35, 45, 11, 0 }, { "Searing Gorge", 43, 50, 7, 0 }, { "Western Plaguelands", 51, 58, 13, 0 },
        { "Tirisfal Glades", 1, 10, 16, 16 } }
    local crit, levels = {}, {}
    for i, z in ipairs(zones) do
        local id = 80100 + i
        local c = {}
        for j = 1, z[4] do c[j] = { z[1] .. " area " .. j, 0, j <= z[5] } end
        spec.ach[id] = { name = "Explore " .. z[1], points = 0, done = z[5] == z[4], crit = c }
        crit[i] = { "Explore " .. z[1], 8, z[5] == z[4], 0, 1, id }
        levels[i] = { mapID = i, name = z[1], lo = z[2], hi = z[3] }
    end
    spec.ach[80001] = { name = "Explore Eastern Kingdoms", points = 0, crit = crit }
    return levels
end
local function lgExplore(id)
    local spec = lgSpec()
    local levels = lgWorld(spec)
    return { spec = spec, open = function(ns)
        C_Map = { GetMapChildrenInfo = function(root) return root == 947 and levels or {} end,
                  GetMapLevels = function(m) return levels[m].lo, levels[m].hi end }
        lgOpen()(ns)
        ns.ShowDetail(id)
    end }
end
S.legacy.zones = lgExplore(80000)
S.legacy.valthalak = lgExplore(80010)
-- The settings pages with the Lock switch of their frame on the screen.
S.bulletin.setup = { spec = S.bulletin.default.spec, open = function(ns) ns.ShowTab(7) end }
S.instancelimit.settings = { spec = S.instancelimit.default.spec, open = function(ns) ns.ShowPage(2) end }
S.mobfinder.search = { spec = { level = 14 }, open = function(ns) ns.Toggle(); ns.ShowPage(1) end }
-- Crates: two Flowering crates, Apprentice Herbs and Expert Ore at the auction house, with some
-- herbs in the bags and the bank, after Calculate and the first price asked.
local function crSpec(locale)
    return { locale = locale, order = { 248691, 248682, 248692, 3819, 2447 },
        bags = { [248691] = 2, [248682] = 1, [248692] = 1, [3819] = 6, [2447] = 20 },
        bank = { [3819] = 4, [3858] = 8 },
        names = { [248691] = "Waylaid Crate: Flowering Expert Herbs", [248682] = "Waylaid Crate: Apprentice Herbs",
                  [248692] = "Waylaid Crate: Expert Ore", [3819] = "Wintersbite", [4625] = "Firebloom", [8831] = "Purple Lotus",
                  [8836] = "Arthas' Tears", [2447] = "Peacebloom", [765] = "Silverleaf", [2449] = "Earthroot", [785] = "Mageroyal",
                  [2450] = "Briarthorn", [2776] = "Gold Ore", [3858] = "Mithril Ore" },
        prices = { [3819] = 2450, [4625] = 3100, [8831] = 1890, [8836] = 2900, [2447] = 35, [765] = 40, [2449] = 120,
                   [785] = 160, [2450] = 210, [2776] = 6900, [3858] = 1350 } }
end
local function crIcons(W)
    local icons = { [248691] = "INV_Crate_01", [248682] = "INV_Crate_01", [248692] = "INV_Crate_01", [3819] = "INV_Misc_Herb_14",
        [4625] = "INV_Misc_Herb_19", [8831] = "INV_Misc_Herb_17", [8836] = "INV_Misc_Herb_13", [2447] = "INV_Misc_Flower_02",
        [765] = "INV_Misc_Herb_10", [2776] = "INV_Ore_Copper_01", [3858] = "INV_Ore_Mithril_02" }
    C_Item.GetItemIconByID = function(id) return "Interface\\Icons\\" .. (icons[id] or "INV_Misc_QuestionMark") end
end
local function crOpen(quote)
    return function(ns, W)
        crIcons(W)
        AuctionHouseFrame = nil -- the preview has no auction window to stand beside
        W.Fire("AUCTION_HOUSE_SHOW")
        ns.Calculate()
        if quote then ns.BuyClick(); W.Fire("COMMODITY_PRICE_UPDATED", 2450, 24500) end
        ns.Refresh()
    end
end
S.crates = { default = { spec = crSpec(), open = crOpen(true) }, plan = { spec = crSpec(), open = crOpen(false) },
    ru = { spec = crSpec("ruRU"), open = crOpen(true) } }
return S
