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
        mod("Attune"), mod("XP"), mod("Restock"), mod("Mail") } },
    open = function(ns)
        for _, k in ipairs({ "QuestCleaner", "BagSpace", "Merchant", "Bulletin", "Attune", "XP", "Restock", "Mail" }) do
            GulliToolkit.Register({ key = k, open = function() end, slash = "/g" .. k:sub(1, 2):lower(),
                icon = "Interface\\AddOns\\Gulli-" .. k .. "\\icon",
                options = k == "QuestCleaner" and {
                    { label = "Keep class quests", get = function() return true end, set = function() end,
                      icon = "Interface\\Icons\\INV_Misc_Book_09" },
                    { label = "Keep dungeon and raid quests", get = function() return false end, set = function() end,
                      icon = "Interface\\Icons\\INV_Misc_Key_14" },
                } or nil })
        end
        local sums = { XP = "Level 42 in 35 min (8.4k XP/h)", Attune = "Onyxia: 3 of 7 steps",
            BagSpace = "2 free slots", Mail = "3 letters, 1 back in 2 days", Bulletin = "4 groups for Scarlet Monastery" }
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

S.attune = { default = { spec = { name = "Gulliby", done = { [7848] = true, [4182] = true, [4183] = true },
    active = { [4184] = true } } } }

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
    W.char.profs = { { "Tailoring", 150, 150 }, { "Cooking", 112, 225 } }
    W.char.inbox = { { 0, 0, 1.6, 2 } }
    GulliChoresDB = { chars = {
        ["Lirra-Realm"] = { name = "Lirra", class = "MAGE", level = 38, t = W.now - 30 * 3600, realm = "Realm",
            faction = "Alliance", rested = 0.9, resting = true, money = 1234500, durability = 88, free = 9,
            trainer = 38, cooldowns = { CD_MOONCLOTH = W.now - 60 } },
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
        ns.Toggle()
    end,
} }

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

S.mail = { panel = {
    spec = { inbox = { { sender = "Auction House", subject = "Auction successful: Linen Cloth", invoice = "seller", money = 4210 },
                       { sender = "Auction House", subject = "Auction won: Silk Cloth", invoice = "buyer", items = { 2589 } },
                       { sender = "Bob", subject = "Herbs", items = { 765, 785 }, days = 2.4 },
                       { sender = "Auction House", subject = "Auction expired: Copper Ore", items = { 2770 }, days = 25, player = false } } },
    open = function(ns, W) W.Fire("PLAYER_LOGIN"); W.Fire("MAIL_SHOW") end,
    crop = "GulliMailPanel",
}, write = {
    spec = { friends = { "Amy", "Zed" }, guild = { "Gil" }, inbox = {} },
    open = function(ns, W) W.Fire("PLAYER_LOGIN"); W.Fire("MAIL_SHOW"); ns.ShowTab(2) end,
    crop = "GulliMailPanel",
}, settings = {
    spec = {},
    open = function(ns) ns.Toggle() end,
} }

-- A level 33 Horde tauren in Orgrimmar, Gnomeregan chosen.
S.dungeonprep = { default = {
    spec = { level = 33, raceID = 6, faction = "Horde",
             areas = { [1637] = "Orgrimmar", [33] = "Stranglethorn Vale", [721] = "Gnomeregan", [1497] = "Undercity" },
             map = { best = 1454, pos = { 0.70, 0.30 },
                     maps = { [1414] = { "Kalimdor", 2 }, [1454] = { "Orgrimmar", 3, 1414 } } },
             bags = { [0] = { size = 16, slots = { [1] = { 4540, 4 } } } } },
    open = function(ns) ns.selected = "GNOMER"; ns.Toggle() end,
} }

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

return S
