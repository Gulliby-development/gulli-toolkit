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
        GulliToolkit.Notify("BagSpace", "Your bags are almost full: 2 free slots.")
        GulliToolkit.Notify("XP", "Level 42 in about 35 min at this pace.")
        SlashCmdList.GULLITOOLKIT("")
    end,
} }

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

S.xp = { default = {
    spec = { level = 41, xp = 12000, xpMax = 31000, rested = 4200, now = 0 },
    open = function(ns, W)
        W.Fire("PLAYER_LOGIN")
        for i = 1, 30 do W.now = i * 60; W.Fire("CHAT_MSG_COMBAT_XP_GAIN", "Wolf dies, you gain 215 experience."); W.Gain(215) end
        ns.Toggle()
    end,
} }

S.loot = { default = {
    spec = { db = { quality = { [0] = "pass", [1] = "greed" }, items = { [2589] = "need", [2592] = "greed" }, report = true } },
    before = function()
        C_Item = C_Item or {}
        C_Item.GetItemNameByID = function(id) return ({ [2589] = "Linen Cloth", [2592] = "Wool Cloth" })[id] end
    end,
} }

S.partyquests = { default = { spec = {
    quests = {
        { title = "Westfall", isHeader = true },
        { title = "The Defias Brotherhood", questID = 155, level = 18 },
        { title = "Red Leather Bandanas", questID = 153, level = 15 },
        { title = "Patrolling Westfall", questID = 102, level = 14 },
        { title = "Redridge Mountains", isHeader = true },
        { title = "Blackrock Menace", questID = 20, level = 21 },
    },
    party = { { name = "Ann", quests = { [155] = true, [20] = true } }, { name = "Bob", quests = { [155] = true, [153] = true } } },
} } }

S.bulletin = { default = {
    open = function(ns, W)
        local msgs = {
            { "LF2M Deadmines need tank and heal", "Thrall" }, { "Priest LFG Scholo or Strat", "Anduin" },
            { "LFM SM:GY pst, 1 dps left", "Varian" }, { "UBRS 8/10 need 2", "Jaina" },
            { "WTS [Linen Cloth] 20x 1g", "Gelbin" },
        }
        for _, m in ipairs(msgs) do W.Fire("CHAT_MSG_CHANNEL", m[1], m[2] .. "-Realm", "", "2. Trade") end
        ns.Toggle()
    end,
} }

S.quickchat = {
    default = {},
    group = { spec = { level = 12 }, open = function(ns) ns.Toggle() end },
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

S.chores = { default = {
    spec = { level = 42 },
    before = function(W)
        W.char.mail, W.char.free, W.char.durability = true, 2, { 22, 60 }
        W.char.spells[17187], W.char.rested = true, 90000
    end,
} }

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
S.craftprofit.unknown = { spec = S.craftprofit.default.spec, before = S.craftprofit.default.before,
    open = function(ns, W) S.craftprofit.default.open(ns, W); ns.SelectLeg(#ns.view.legs) end }
S.craftprofit.crafts = { spec = S.craftprofit.default.spec, before = S.craftprofit.default.before,
    open = function(ns, W) S.craftprofit.default.open(ns, W); ns.Tab(2) end }

S.craftprofit.recipes = { spec = S.craftprofit.default.spec, before = S.craftprofit.default.before,
    open = function(ns, W) S.craftprofit.default.open(ns, W); ns.Tab(4) end }

S.craftprofit.earn = { spec = S.craftprofit.default.spec, before = S.craftprofit.default.before,
    open = function(ns, W) S.craftprofit.default.open(ns, W); ns.SetPref("mode", "earn") end }

S.mail = { panel = {
    spec = { inbox = { { sender = "Auction House", money = 4210 }, { sender = "Auction House", items = { 2589 } } } },
    open = function(ns, W) W.Fire("PLAYER_LOGIN"); W.Fire("MAIL_SHOW") end,
    crop = "GulliMailPanel",
} }

return S