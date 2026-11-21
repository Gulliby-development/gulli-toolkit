-- Sample data for each window in tools/preview. scenes[test folder][scene] =
-- { spec = Fake() spec, before = fn(W, R), open = fn(ns, W, R), crop = global frame name }.
local S = {}

local function mod(name, key, enabled)
    return { name = "Gulli-" .. name, enabled = enabled ~= false, loaded = enabled ~= false,
             meta = { ["X-Gulli-Module"] = key or name, Version = "1.0.0" } }
end
local HUB_MODS = { "QuestCleaner", "PartyQuests", "AutoQuest", "GroupBuffs", "InstanceLimit", "Attune", "DungeonPrep",
    "BagSpace", "Restock", "Merchant", "Mail", "CraftProfit", "Bulletin", "Chores", "XP", "FarmTrack" }
local function hubAddons()
    local out = { { name = "Gulli-Toolkit", enabled = true, loaded = true, meta = { Version = "1.3.0" } } }
    for _, k in ipairs(HUB_MODS) do out[#out + 1] = mod(k) end
    out[#out + 1] = mod("MobFinder", nil, false)
    out[#out + 1] = { name = "Gulli-Loot", enabled = false, loaded = true, meta = { ["X-Gulli-Module"] = "Loot", Version = "1.0.0" } }
    return out
end
S.toolkit = { default = {
    spec = { addons = hubAddons() },
    open = function(ns)
        UpdateAddOnMemoryUsage = function() end
        GetAddOnMemoryUsage = function(name)
            return ({ ["Gulli-CraftProfit"] = 14540, ["Gulli-DungeonPrep"] = 11570, ["Gulli-QuestCleaner"] = 6350,
                      ["Gulli-XP"] = 360 })[name] or 900
        end
        GulliToolkit.Register({ key = "Loot", open = function() end, slash = "/glt",
            icon = "Interface\\AddOns\\Gulli-Loot\\icon", summary = function() return "12 item rules" end })
        GulliToolkitDB.paused = { Restock = true }
        for _, k in ipairs(HUB_MODS) do
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
        local ru = os.getenv("LOCALE") == "ruRU"
        local sums = ru and {
            GroupBuffs = { "1 бафф не наложен", { tone = "bad" } },
            DungeonPrep = { "Мародон: 0 в журнале, 8 можно взять", { value = 8, tone = "warn" } },
            InstanceLimit = { "5 из 5 входов осталось", { pips = { 5, 5 }, tone = "good" } },
            Bulletin = { "3 группы ищут игроков, 45 объявлений торговли" },
            Merchant = { "3 предмета хлама на 1з 10с" },
            AutoQuest = { "12 сдано, 8 взято" },
            BagSpace = { "26 свободных ячеек", { ready = "BAGS" } },
            Chores = { "У персонажей ничего не ждёт", { quiet = true } },
            XP = { "Уровень 48 через 1 ч 30 мин (19k опыта/ч)" },
        } or {
            GroupBuffs = { "1 buffs missing", { tone = "bad" } },
            DungeonPrep = { "Maraudon: 0 in log, 8 to pick up", { value = 8, tone = "warn" } },
            InstanceLimit = { "5 of 5 entries left", { pips = { 5, 5 }, tone = "good" } },
            Bulletin = { "3 groups looking for players, 45 trade posts" },
            Merchant = { "3 junk items worth 1g 10s" },
            AutoQuest = { "12 handed in, 8 taken" },
            BagSpace = { "26 free bag slots", { ready = "BAGS" } },
            Chores = { "Nothing waits on your characters", { quiet = true } },
            XP = { "Level 48 in 1 h 30 min (19k XP/h)" },
        }
        for k, v in pairs(sums) do GulliToolkit.modules[k].summary = function() return v[1], nil, v[2] end end
        GulliToolkit.modules.XP.session = function()
            return { value = "19k", unit = ru and "опыта / ч" or "XP / h",
                     line = ru and "Уровень 48 через 1 ч 30 мин" or "Level 48 in 1 h 30 min",
                     span = ru and "2 ч 40 мин" or "2 h 40 min", at = 1000,
                     bars = { 1100, 1500, 1900, 1700, 2400, 2700, 2200, 3000, 2600, 3100, 2900, 2800 },
                     progress = { value = 0.77, extra = 0.12, left = 47, right = "77%" },
                     tile = { value = "+50k", label = ru and "Опыт" or "XP" },
                     tip = { head = ru and "Опыт" or "Experience", value = "50.6k",
                             rows = { { ru and "Убийства" or "Kills", "61%" }, { ru and "Квесты" or "Quests", "39%" } } } }
        end
        GulliToolkit.modules.InstanceLimit.session = function()
            return { value = "2", unit = ru and "подземелья" or "dungeons", at = 400, bars = { 41, 36 },
                     line = ru and "В среднем 38 мин" or "38 min on average",
                     tile = { value = "2", label = ru and "Подземелья" or "Dungeons", icon = "Interface\\Icons\\INV_Misc_Key_03" },
                     tip = { head = ru and "Подземелья" or "Dungeons", value = "2", icon = "Interface\\Icons\\INV_Misc_Key_03",
                             rows = { { ru and "Мародон" or "Maraudon", "41:10" }, { ru and "Мародон" or "Maraudon", "36:02" } } } }
        end
        -- What the core counted itself: two hours and forty minutes of everything.
        ns.SesStart(1000 - 9600)
        local ses = ns.ses
        ses.active, ses.lastActive = 9600, 1000
        ses.honor, ses.hk, ses.honorAt, ses.honorB = 1240, 18, 700, { [28] = 300, [29] = 520, [30] = 420 }
        ses.gold = { loot = 81000, quest = 30000, vendor = 21500, repair = 8500 }
        ses.goldAt, ses.goldB = 990, { [25] = 9000, [27] = 14000, [29] = 11000, [30] = 16000, [31] = 21000, [32] = 18000, [33] = 24000 }
        ses.kills, ses.quests, ses.deaths = 214, 6, 1
        ses.best = { name = ru and "Посох Природной Ярости" or "Staff of Nature's Fury", q = 3 }
        -- Sample checks for the Ready card, as a mage of 47 on the road has them.
        local L, I = ns.L, "Interface\\Icons\\"
        local function check(key, ok, value, text, frac, mark, label)
            return { key = key, ok = ok, value = value, text = text, icon = ns.READY_ICON[key], frac = frac, mark = mark,
                     label = label or L["RD_L_" .. key] }
        end
        ns.Readiness = function()
            local bf, bm = ns.ReadyBar(26, 6)
            local ff, fm = ns.ReadyBar(50, 20)
            local df, dm = ns.ReadyBar(71, 20)
            return {
                check("REPAIR", false, "42%", L.RD_REPAIR:format(42), 0.42, 0.5),
                check("BAGS", true, "26", L.RD_BAGS:format(26), bf, bm),
                check("FOOD", true, "50", L.RD_FOOD:format(50), ff, fm),
                check("DRINK", true, "71", L.RD_DRINK:format(71), df, dm),
                check("HEARTH", false, L.RD_MIN:format(29), L.RD_HEARTH_CD:format(29), 0.52),
                check("RESTOCK", false, "0/20", L.RD_RESTOCK:format("Morning Glory Dew 0/20"), 0, nil,
                    ru and "Утренняя роса" or "Morning Glory Dew"),
            }
        end
        local feed = ru and {
            { "Mail", "Забрано 6 писем, 12з 40с", 18000 }, { "Bulletin", "Ищут в Мародон, нужен лекарь", 14400 },
            { "Merchant", "Продано 14 предметов хлама за 3з 20с", 11000 }, { "XP", "Уровень 47 за 2 ч 05 мин", 10800 },
            { "InstanceLimit", "Вход снова свободен", 7300 }, { "AutoQuest", "Взято 1, сдано 0", 4000 },
            { "AutoQuest", "Взято 0, сдано 1", 3900 }, { "AutoQuest", "Сдано 2, взято 2", 3700 },
        } or {
            { "Mail", "Took 6 letters, 12g 40s", 18000 }, { "Bulletin", "LFM Maraudon, need healer", 14400 },
            { "Merchant", "Sold 14 junk items for 3g 20s", 11000 }, { "XP", "Level 47 in 2 h 05 min", 10800 },
            { "InstanceLimit", "An entry is free again", 7300 }, { "AutoQuest", "Taken 1, handed in 0", 4000 },
            { "AutoQuest", "Taken 0, handed in 1", 3900 }, { "AutoQuest", "Handed in 2, taken 2", 3700 },
        }
        for _, e in ipairs(feed) do
            GulliToolkit.Notify(e[1], e[2])
            GulliToolkitDB.feed[1].t = 1000 - e[3]
        end
        SlashCmdList.GULLITOOLKIT("")
    end,
} }

-- The Setup page: the presets, the tools and the hub's own switches.
S.toolkit.setuppage = { spec = S.toolkit.default.spec,
    open = function(ns, W, R)
        S.toolkit.default.open(ns, W, R)
        ns.SetPinned("DungeonPrep", true)
        ns.SetPinned("QuestCleaner", true)
        ns.OpenSetupPage()
    end,
}

-- The session card in other sessions: nothing yet, honor and dungeons at the top level, only
-- dungeons, only gold with a Farm Tracker goal.
local function sessionScene(change)
    return { spec = S.toolkit.default.spec,
        open = function(ns, W, R)
            S.toolkit.default.open(ns, W, R)
            GulliToolkit.modules.XP.session = nil
            change(ns, os.getenv("LOCALE") == "ruRU")
            ns.Refresh()
        end }
end
S.toolkit.nosession = sessionScene(function(ns)
    GulliToolkit.modules.InstanceLimit.session = nil
    ns.SesStart(1000 - 120)
end)
S.toolkit.seshonor = sessionScene(function(ns)
    local s = ns.ses
    s.honor, s.hk, s.honorAt, s.kills, s.quests, s.deaths = 6820, 74, 950, 0, 0, 7
    s.honorB = { [21] = 300, [22] = 500, [23] = 900, [24] = 1200, [25] = 1000, [28] = 150, [29] = 900, [30] = 1300, [31] = 1400, [32] = 1100 }
    s.best = { name = "Blade of Eternal Darkness", q = 4 }
end)
S.toolkit.sesdungeon = sessionScene(function(ns, ru)
    local s = ns.ses
    s.honor, s.kills, s.quests = 0, 0, 0
    GulliToolkit.modules.InstanceLimit.session = function()
        return { value = "3", unit = ru and "подземелья" or "dungeons", at = 1000, bars = { 41, 36, 38, 12 },
                 line = ru and "В среднем 38 мин, сейчас Мародон 12 мин" or "38 min on average, now Maraudon 12 min",
                 tip = { head = ru and "Подземелья" or "Dungeons", value = "3", rows = {} } }
    end
end)
S.toolkit.sesgold = sessionScene(function(ns, ru)
    local s = ns.ses
    s.honor, s.quests, s.deaths, s.kills, s.best = 0, 0, 0, 0, nil
    s.gold = { loot = 352000, quest = 0, vendor = 41000, repair = 10500 }
    GulliToolkit.modules.InstanceLimit.session = nil
    GulliToolkit.modules.FarmTrack.session = function()
        return { tile = { value = "86", label = ru and "Руническая ткань" or "Runecloth", icon = "Interface\\Icons\\INV_Fabric_PurpleFire_01" } }
    end
end)

-- The Unlock mode: the panel of every frame on the screen, with the grid behind it.
S.toolkit.unlock = { spec = S.toolkit.default.spec, crop = "GulliToolkitUnlock",
    open = function(ns, W, R)
        S.toolkit.default.open(ns, W, R)
        local shown = { XP = true, Bulletin = false, Attune = true }
        for k, label in pairs({ XP = "XP bar", Bulletin = "Group feed" }) do
            GulliToolkit.modules[k].frames = { { key = k, label = label,
                get = function() return shown[k] end, set = function(v) shown[k] = v end } }
        end
        GulliToolkit.modules.MobFinder = nil
        GulliToolkit.modules.Attune.frames = { { key = "card", label = "Rare card" } }
        ns.SetMoving(true)
    end,
}

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

-- The home page with errors saved, and the errors page.
local function sampleErrors(ns)
    ns.RecordError("Interface/AddOns/Gulli-Crates/Core.lua:412: attempt to compare nil with number",
        "[string \"@Interface/AddOns/Gulli-Crates/Core.lua\"]:412: in function 'Plan'\n[string \"@Interface/AddOns/Gulli-Crates/UI.lua\"]:88: in function <...>")
    ns.RecordError("ADDON_ACTION_BLOCKED: C_AuctionHouse.ConfirmCommoditiesPurchase()", nil, "blocked", "Gulli-Crates")
    ns.RecordError("Interface/AddOns/Gulli-XP/Core.lua:120: bad argument #1 to 'format'", nil)
end
S.toolkit.errors = { spec = S.toolkit.default.spec,
    open = function(ns, W, R)
        sampleErrors(ns)
        S.toolkit.default.open(ns, W, R)
    end,
}
S.toolkit.errorspage = { spec = S.toolkit.default.spec,
    open = function(ns, W, R)
        sampleErrors(ns)
        S.toolkit.default.open(ns, W, R)
        ns.OpenErrors()
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
    open = function(ns, W) xpPlay(W); ns.SetPref("bar", true); ns.SetPref("wide", false); ns.Refresh() end }
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

-- PartyQuests: a level 47 character with quests in several zones, and a group of three: Ann runs
-- the module (progress and zones), Bob does not, Cid is offline.
local function pqSpec(party)
    return { level = 47,
        quests = {
            { title = "Tanaris", isHeader = true },
            { title = "Overseas Delivery", questID = 301, level = 38 },
            { title = "Screecher Spirits", questID = 302, level = 44 },
            { title = "Gadgetzan Water Survey", questID = 303, level = 46 },
            { title = "Dunemaul Dues", questID = 304, level = 47 },
            { title = "The Dunemaul Compound", questID = 305, level = 49, suggestedGroup = 3 },
            { title = "Thistleshrub Valley", questID = 306, level = 50 },
            { title = "Riverglades", isHeader = true },
            { title = "I Know a Guy", questID = 311, level = 40 },
            { title = "On the Other Side", questID = 312, level = 41 },
            { title = "The Hinterlands", isHeader = true },
            { title = "A Sticky Situation", questID = 321, level = 48 },
            { title = "Summoning Shadra", questID = 322, level = 55 },
            { title = "Sunken Temple", isHeader = true },
            { title = "Jammal'an the Prophet", questID = 331, level = 53 },
        },
        party = party or {},
        complete = { [304] = true, [305] = true },
        turned = { [402] = true },
        titles = { [401] = "Super Sticky", [402] = "The Thirsty Goblin", [403] = "Rescue OOX-09/HL!", [404] = "Into the Temple" },
        objectives = {
            [302] = { { text = "Screecher Spirits collected: 0/3", type = "monster", numFulfilled = 0, numRequired = 3 } },
            [303] = { { text = "Tapped Dowsing Widget: 0/1", type = "item", numFulfilled = 0, numRequired = 1 } },
            [304] = { { text = "Dunemaul Ogres slain: 1/1", type = "monster", numFulfilled = 1, numRequired = 1 } },
            [305] = { { text = "Dunemaul Brutes slain: 21/21", type = "monster", numFulfilled = 21, numRequired = 21 } },
            [306] = { { text = "Thistleshrub Dew Collector slain: 4/16", type = "monster", numFulfilled = 4, numRequired = 16 } },
            [321] = { { text = "Hinterlands Honey Ripple: 0/10", type = "item", numFulfilled = 0, numRequired = 10 } },
            [322] = { { text = "Shadra's Venom: 0/1", type = "item", numFulfilled = 0, numRequired = 1 } },
            [331] = { { text = "Head of Jammal'an: 0/1", type = "item", numFulfilled = 0, numRequired = 1 } },
        },
        zone = "Tanaris" }
end
local PQ_PARTY = {
    { name = "Ann", quests = { [302] = true, [303] = true, [304] = true, [305] = true, [321] = true, [331] = true } },
    { name = "Bob", quests = { [302] = true, [305] = true, [306] = true, [331] = true } },
    { name = "Cid", quests = {}, offline = true },
}
local function pqOpen(tab, zoneOnly)
    return function(ns)
        RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 }, HUNTER = { r = 0.67, g = 0.83, b = 0.45 },
                              PRIEST = { r = 1, g = 1, b = 1 } }
        local classes = { party1 = "MAGE", party2 = "HUNTER", party3 = "PRIEST" }
        UnitClass = function(u) return "", classes[u] or "MAGE" end
        for _, p in ipairs({ "B", "Q302,303,304*,305,321,331,401,402,403,404", "O302:2/3,303:0/1,304:1/1,305:9/21,321:6/10,331:0/1",
                             "C311,312", "ZTanaris|401:45,402:46", "ZThe Hinterlands|403:48", "ZSunken Temple|404:50", "E" }) do
            ns.Receive(p, "Ann")
        end
        ns.Set("zoneOnly", zoneOnly and true or false)
        ns.ShowTab(tab)
    end
end
S.partyquests = {
    default = { spec = pqSpec(PQ_PARTY), open = pqOpen(1) },
    zone = { spec = pqSpec(PQ_PARTY), open = pqOpen(1, true) },
    solo = { spec = pqSpec(), open = pqOpen(1) },
    theirs = { spec = pqSpec(PQ_PARTY), open = pqOpen(2) },
    settings = { spec = { party = { { name = "Ann", quests = {} } } }, open = function(ns) ns.ShowTab(3) end },
}

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
        ns.AddWord("Arcanite Bar"); ns.AddWord("Strat"); ns.AddWord("enchanter")
        ns.Add("LFM Strat UD need heals", "Ann"); ns.Add("WTS [Arcanite Bar] 20g", "Bob")
        ns.ShowTab(7)
    end,
} }

S.quickchat = {
    default = {},
    picked = { open = function(ns)
        ns.AddPhrase("Pull in 5, ready?"); ns.ToggleFav("Ready!"); ns.db.orderOf["Need a heal!"] = { "PARTY" }
        ns.Toggle(); ns.PickPhrase("Pull in 5, ready?")
    end },
    order = { spec = { channels = { 1, "General - Elwynn", false, 2, "Trade - City", false } }, open = function(ns)
        ns.db.orderOf["WTS {item}, pst"] = { "TRADE", "GENERAL", "SAY" }
        ns.Toggle(); ns.EditOrder("WTS {item}, pst")
    end },
    setup = { spec = { channels = { 1, "General - Elwynn", false, 4, "LookingForGroup", false } }, open = function(ns)
        ns.db.wheelKey = "F5"; ns.db.order = { "RAID", "PARTY", "LFG", "SAY" }; ns.ShowPage(2)
    end },
    wheel = { crop = "GulliQuickChatRing", open = function(ns)
        ns.OpenWheel(true)
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
-- no auction addon: the auction stop buys at guessed prices
do
    local spec = {}
    for k, v in pairs(S.craftprofit.default.spec) do spec[k] = v end
    spec.auctionator = false
    spec.items = {}
    for id, it in pairs(S.craftprofit.default.spec.items) do
        local c = {}
        for k, v in pairs(it) do c[k] = v end
        c.bags, c.bank = nil, nil
        spec.items[id] = c
    end
    S.craftprofit.noprices = { spec = spec, before = S.craftprofit.default.before,
        open = function(ns, W)
            S.craftprofit.default.open(ns, W)
            for i, n in ipairs(ns.view.route or {}) do if n.kind == "ah" then ns.Select(i) end end
        end }
end
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

-- A vendor stop whose patterns name who sells them, with Show on map (`trainer`: the trainer stop).
local function cpPin(trainer)
    return function(ns, W)
        S.craftprofit.default.open(ns, W)
        ns.Data.npc["Quartermaster Miranda Breechlock"] = { 33, 50, 50 }
        ns.view.route = {
            { kind = "vendor", title = "STOP_VENDOR_BUY", index = 1, sig = "v", cost = 9000, lines = {
                { recipe = 104, name = "Pattern: Black Swashbuckler's Shirt", n = 1, src = "vendor", price = 6000, npc = { "Narkk" } },
                { recipe = 104, name = "Pattern: Crimson Silk Vest", n = 1, src = "vendor", price = 3000,
                  npc = { "Quartermaster Miranda Breechlock" } },
                { id = 5, name = "Fine Thread", n = 6, src = "vendor", price = 100 } } },
            { kind = "trainer", title = "STOP_TRAINER", index = 2, sig = "t", cost = 5000, at = 175, lines = {
                { recipe = 12052, name = "Shadoweave Pants", n = 1, src = "trainer", price = 5000, npc = { "Jalane Ayrole" } } } },
        }
        ns.atVendor = false
        ns.Refresh(); ns.Select(trainer and 2 or 1)
    end
end
S.craftprofit.pin = { spec = S.craftprofit.default.spec, before = S.craftprofit.default.before, open = cpPin() }
S.craftprofit.pintrainer = { spec = S.craftprofit.default.spec, before = S.craftprofit.default.before, open = cpPin(true) }
-- Patterns left out because the reputation was not read yet: the banner over the route.
S.craftprofit.rep = { spec = S.craftprofit.default.spec, before = S.craftprofit.default.before,
    open = function(ns, W)
        S.craftprofit.default.open(ns, W)
        ns.repUnknown = { ["Thorium Brotherhood"] = true, ["Cenarion Circle"] = true, ["Timbermaw Hold"] = true }
        ns.Refresh()
    end }

-- The run with nothing in the bags, so it has an auction stop of several lines.
local function cpSpec(extra)
    local spec = {}
    for k, v in pairs(S.craftprofit.default.spec) do spec[k] = v end
    spec.db = { prefs = { useBags = false, useBank = false } }
    -- the thread comes from the auction too, so the auction stop has two lines
    spec.items = {}
    for id, it in pairs(S.craftprofit.default.spec.items) do
        spec.items[id] = {}
        for k, v in pairs(it) do spec.items[id][k] = v end
    end
    spec.items[5].ah = 90
    spec.vendor = { { 3, 50 } }
    for k, v in pairs(extra or {}) do spec[k] = v end
    return spec
end
local function cpStop(ns, title)
    for i, n in ipairs(ns.view.route) do if n.title == title then return i end end
end
-- At the auction house: the first line bought, the second priced (`over`: that much above the plan).
local function cpBuying(ns, W, over)
    W.Fire("AUCTION_HOUSE_SHOW")
    local node = ns.view.route[cpStop(ns, "STOP_AH_BUY")]
    local l = node.lines[1]
    ns.BuyClick()
    local first = math.floor(l.price * ((#node.lines == 1 and over) or 1))
    W.Fire("COMMODITY_PRICE_UPDATED", first, first * l.n)
    if #node.lines > 1 then
        ns.BuyClick()
        W.Fire("COMMODITY_PURCHASE_SUCCEEDED")
        l = node.lines[2]
        ns.BuyClick()
        local unit = math.floor(l.price * (over or 1))
        W.Fire("COMMODITY_PRICE_UPDATED", unit, unit * l.n)
    end
end
S.craftprofit.buy = { spec = cpSpec(), before = S.craftprofit.default.before,
    open = function(ns, W) S.craftprofit.default.open(ns, W); cpBuying(ns, W) end }
S.craftprofit.dear = { spec = cpSpec(), before = S.craftprofit.default.before,
    open = function(ns, W) S.craftprofit.default.open(ns, W); cpBuying(ns, W, 1.4) end }
S.craftprofit.away = { spec = cpSpec(), before = S.craftprofit.default.before,
    open = function(ns, W)
        S.craftprofit.default.open(ns, W)
        W.Fire("MERCHANT_CLOSED")
        ns.Select(cpStop(ns, "STOP_AH_BUY"))
    end }
S.craftprofit.vendor = { spec = cpSpec({ vendor = { { 3, 50 }, { 5, 500, 5 } }, items = S.craftprofit.default.spec.items }), before = S.craftprofit.default.before,
    open = function(ns, W) S.craftprofit.default.open(ns, W); ns.Select(cpStop(ns, "STOP_VENDOR_BUY")) end }
S.craftprofit.settings = { spec = S.craftprofit.default.spec, before = S.craftprofit.default.before,
    open = function(ns, W) S.craftprofit.default.open(ns, W); ns.Tab(5) end }
-- A craft stop with its "Without this craft" tool, and the Settings card of the avoided crafts.
S.craftprofit.craft = { spec = S.craftprofit.default.spec, before = S.craftprofit.default.before,
    open = function(ns, W)
        S.craftprofit.default.open(ns, W)
        for i, n in ipairs(ns.view.route) do if n.segs then ns.Select(i); break end end
    end }
S.craftprofit.skip = { spec = S.craftprofit.default.spec, before = S.craftprofit.default.before,
    open = function(ns, W)
        S.craftprofit.default.open(ns, W)
        local ids = {}
        for rid in pairs(ns.view.state.recipes) do ids[#ids + 1] = rid end
        table.sort(ids, function(x, y) return tostring(x) < tostring(y) end)
        for k = 1, math.min(2, #ids) do ns.SetSkip(ids[k], true) end
        ns.Tab(5)
    end }
-- The window beside the auction house, alone and as a tab next to another module's.
local function cpSide(ns, W, over)
    AuctionHouseFrame = nil -- the preview has no auction window to stand beside
    W.Fire("MERCHANT_SHOW"); W.Fire("TRADE_SKILL_SHOW"); W.RunTimers()
    ns.Recalc(false)
    cpBuying(ns, W, over)
end
S.craftprofit.side = { spec = cpSpec(), before = S.craftprofit.default.before, crop = "GulliCraftProfitSide",
    open = function(ns, W) cpSide(ns, W) end }
S.craftprofit.sidedear = { spec = cpSpec(), before = S.craftprofit.default.before, crop = "GulliCraftProfitSide",
    open = function(ns, W) cpSide(ns, W, 1.4) end }
S.craftprofit.sidetabs = { spec = cpSpec(), before = S.craftprofit.default.before, crop = "GulliCraftProfitSide",
    open = function(ns, W)
        cpSide(ns, W)
        local other = ns.Skin.Window(nil, "Gulli Waylaid Crates", ns.Skin.NARROW_W, ns.Skin.DOCK_H)
        ns.Skin.SideAdd({ key = "Crates", order = 10, title = "Gulli Waylaid Crates",
                          icon = "Interface\\Icons\\INV_Crate_01", window = function() return other end,
                          badge = function() return 1 end })
        ns.Skin.SideOpen("Crates")
        ns.Skin.SideOpen("CraftProfit", true)
    end }
-- A craft stop while the profession window is closed: the button opens it first.
-- A craft stop part made: the first craft done, the button on the next one, and Mark done.
S.craftprofit.made = { spec = S.craftprofit.default.spec, before = S.craftprofit.default.before,
    open = function(ns, W)
        S.craftprofit.default.open(ns, W)
        for i, n in ipairs(ns.view.route) do
            if n.kind == "craft" then
                local rid = n.segs and n.segs[1].rid or n.lines[1].recipe
                ns.view.made[rid] = 2
                ns.Select(i)
                break
            end
        end
    end }
S.craftprofit.craftopen = { spec = S.craftprofit.default.spec, before = S.craftprofit.default.before,
    open = function(ns, W)
        S.craftprofit.craft.open(ns, W)
        ns.CanOpenProfession = function() return true end
        ns.profOpen = false
        ns.char.current = ns.char.current or "Tailoring"
        ns.Refresh()
    end }

S.mail = { panel = {
    spec = { inbox = { { sender = "Auction House", subject = "Auction successful: Linen Cloth", invoice = "seller", money = 4210 },
                       { sender = "Auction House", subject = "Auction won: Silk Cloth", invoice = "buyer", items = { 2589 } },
                       { sender = "Bob", subject = "Herbs", items = { 765, 785 }, days = 2.4 },
                       { sender = "Auction House", subject = "Auction expired: Copper Ore", items = { 2770 }, days = 25, player = false } },
             classes = { [2589] = { 7, 5 }, [765] = { 7, 9 }, [785] = { 7, 9 }, [2770] = { 7, 7 } } },
    open = function(ns, W)
        local icons = { [2589] = "Interface\\Icons\\INV_Fabric_Linen_01", [765] = "Interface\\Icons\\INV_Misc_Flower_02",
                        [785] = "Interface\\Icons\\INV_Misc_Flower_01", [2770] = "Interface\\Icons\\INV_Ore_Copper_01",
                        [2318] = "Interface\\Icons\\INV_Misc_LeatherScrap_03", [10940] = "Interface\\Icons\\INV_Enchant_DustStrange",
                        [774] = "Interface\\Icons\\INV_Misc_Gem_Emerald_03", [7067] = "Interface\\Icons\\INV_Stone_02" }
        C_Item.GetItemIconByID = function(id) return icons[id] end
        W.Fire("PLAYER_LOGIN"); W.Fire("MAIL_SHOW"); ns.visit.items, ns.visit.money, ns.visit.sold = 3, 26664, 26664; ns.Refresh() end,
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
-- The Gnomeregan boss loot by name, for the journal pages.
local DP_LOOT = { [9445] = { "Grubbis Paws", "INVTYPE_HAND", "INV_Gauntlets_04" },
    [9446] = { "Electrocutioner Leg", "INVTYPE_2HWEAPON", "INV_Mace_04" },
    [9454] = { "Acidic Walkers", "INVTYPE_FEET", "INV_Boots_05" }, [9452] = { "Hydrocane", "INVTYPE_2HWEAPON", "INV_Staff_08" },
    [9453] = { "Toxic Revenger", "INVTYPE_WEAPON", "INV_Weapon_ShortBlade_05" },
    [9447] = { "Electrocutioner Lagnut", "INVTYPE_FINGER", "INV_Jewelry_Ring_15" },
    [9448] = { "Spidertank Oilrag", "INVTYPE_WRIST", "INV_Bracer_07" },
    [9449] = { "Manual Crowd Pummeler", "INVTYPE_2HWEAPON", "INV_Hammer_05" },
    [9450] = { "Gnomebot Operating Boots", "INVTYPE_FEET", "INV_Boots_02" },
    [9492] = { "Electromagnetic Gigaflux Reactivator", "INVTYPE_HEAD", "INV_Helmet_49" },
    [9459] = { "Thermaplugg's Left Arm", "INVTYPE_2HWEAPON", "INV_Axe_09" },
    [9461] = { "Charged Gear", "INVTYPE_FINGER", "INV_Misc_Gear_01" },
    [9458] = { "Thermaplugg's Central Core", "INVTYPE_SHIELD", "INV_Shield_05" },
    [4415] = { "Schematic: Craftsman's Monocle", "", "INV_Scroll_03" },
    [9455] = { "Emissary Cuffs", "INVTYPE_WRIST", "INV_Bracer_04" },
    [9457] = { "Royal Diplomatic Scepter", "INVTYPE_WEAPON", "INV_Mace_06" } }
local dpItems = setmetatable({ [6893] = { "Workshop Key", 1, 1, "", 13, 0, "Interface\\Icons\\INV_Misc_Key_06" } },
    { __index = function(_, id)
        local l = DP_LOOT[id]
        if l then return { l[1], 3, 34, l[2], l[2] == "" and 9 or 4, id % 3, "Interface\\Icons\\" .. l[3] } end
        return { "Reward " .. id, 2, 34 + id % 4, ({ "INVTYPE_LEGS", "INVTYPE_RANGEDRIGHT", "INVTYPE_CHEST" })[id % 3 + 1],
                 id % 3 == 1 and 2 or 4, id % 3 == 1 and 3 or (id % 2 == 0 and 3 or 1),
                 "Interface\\Icons\\" .. dpIcons[id % #dpIcons + 1] }
    end })
local dpSpec = { level = 33, raceID = 6, faction = "Horde", className = "HUNTER", ammo = 320, counts = { [6893] = 1 },
    items = dpItems, active = { [2841] = true },
    objectives = { [2841] = { { text = "0/1 Rig Blueprints", finished = false },
                              { text = "Thermaplugg's Safe Combination: 1/1", finished = true } } },
    party = { { name = "Thorn", quests = { [2841] = true } } },
    areas = { [1637] = "Orgrimmar", [33] = "Stranglethorn Vale", [721] = "Gnomeregan", [1497] = "Undercity", [1] = "Dun Morogh" },
    map = { best = 1454, pos = { 0.70, 0.30 },
            maps = { [1414] = { "Kalimdor", 2 }, [1454] = { "Orgrimmar", 3, 1414 } } },
    bags = { [0] = { size = 16, slots = { [1] = { 4540, 4 } } } } }
-- Maraudon at level 48: two quests in the log whose work is inside, one chain step taken inside.
local dpMara = { level = 48, raceID = 6, faction = "Horde", className = "PRIEST", items = dpItems,
    active = { [96776] = true, [93404] = true }, done = { [7044] = true, [93594] = true },
    objectives = { [96776] = { { text = "0/1 An'she's Radiance", finished = false } },
                   [93404] = { { text = "0/1 Vial of Earth Song Water", finished = false },
                               { text = "0/1 Woodwyrd extinguished", finished = false } } },
    areas = { [1637] = "Orgrimmar", [405] = "Desolace", [215] = "Mulgore", [2100] = "Maraudon", [493] = "Moonglade",
              [16651] = "Forlorn Gardens" },
    map = { best = 1454, pos = { 0.70, 0.30 },
            maps = { [1414] = { "Kalimdor", 2 }, [1454] = { "Orgrimmar", 3, 1414 } } } }
-- Sample bosses for the journal pages (the real ones come from JournalData.lua).
local function dpBosses(ns)
    ns.Data.boss = ns.Data.boss or {}
    ns.Data.boss.GNOMER = {
        { 7361, "Grubbis", "", 32, 32, 6533, 0, { 9143 }, { { 9445, 3, 21.4 }, { 9446, 3, 18.9 } } },
        { 7079, "Viscous Fallout", "", 30, 30, 6531, 0, { 9459 }, { { 9454, 3, 34.2 }, { 9452, 3, 29.8 }, { 9453, 3, 27.1 } } },
        { 6235, "Electrocutioner 6000", "", 32, 32, 6942, 0, { 11085 }, { { 9447, 3, 31.5 }, { 9446, 3, 24.6 }, { 9448, 3, 22 } } },
        { 6229, "Crowd Pummeler 9-60", "", 32, 32, 6774, 0, { 10887 }, { { 9449, 3, 41.3 }, { 9450, 3, 37 } } },
        { 7800, "Mekgineer Thermaplugg", "Leper Gnome King", 34, 34, 6980, 0, { 10101, 11518 },
          { { 9492, 3, 18.7 }, { 9459, 3, 17.2 }, { 9461, 3, 16.4 }, { 9458, 3, 15.3 }, { 4415, 3, 4.1 } } },
        { 6228, "Dark Iron Ambassador", "", 33, 33, 6669, 1, {}, { { 9455, 3, 33.3 }, { 9457, 3, 30.6 } } },
    }
    ns.Data.zone = ns.Data.zone or {}
    ns.Data.zone.GNOMER = { { 9445, 3 }, { 9450, 3 } }
    ns.db.kills = { [7800] = 3, [7361] = 2, [7079] = 2, [6235] = 12 }
    ns.SetWish(9492, true)
end
S.dungeonprep = {
    home = { spec = dpSpec, open = function(ns) ns.Toggle() end },
    default = { spec = dpSpec, open = function(ns) dpBosses(ns); ns.home = false; ns.selected = "GNOMER"; ns.Toggle() end },
    boss = { spec = dpSpec, open = function(ns) dpBosses(ns); ns.home = false; ns.selected = "GNOMER"; ns.boss = 7800; ns.modelBoss = 7800; ns.Toggle() end },
    wings = { spec = dpSpec, open = function(ns) ns.home = false; ns.selected = "SM"; ns.Toggle() end },
    loot = { spec = dpSpec, open = function(ns) dpBosses(ns); ns.home = false; ns.selected = "GNOMER"; ns.Toggle(); ns.ShowTab(2) end },
    lootmine = { spec = dpSpec, open = function(ns) dpBosses(ns); ns.home = false; ns.selected = "GNOMER"; ns.lootFilter = "mine"; ns.Toggle(); ns.ShowTab(2) end },
    quests = { spec = dpSpec, open = function(ns) ns.home = false; ns.selected = "GNOMER"; ns.Toggle(); ns.ShowTab(3) end },
    settings = { spec = dpSpec, open = function(ns) ns.home = false; ns.selected = "GNOMER"; ns.Toggle(); ns.ShowTab(4) end },
    real = { spec = dpSpec, open = function(ns) ns.home = false; ns.selected = "THANES"; ns.Toggle() end },
    levels = { spec = dpSpec, open = function(ns) ns.home = false; ns.selected = "SM"; ns.Toggle() end },
    empty = { spec = dpSpec, open = function(ns) ns.home = false; ns.selected = "DALARAN"; ns.Toggle() end },
    quest = { spec = dpSpec, open = function(ns) ns.home = false; ns.selected = "GNOMER"; ns.Toggle(); ns.ShowTab(3); ns.OpenQuest(2841) end },
    -- A quest with many rewards: the left column scrolls instead of running over the buttons.
    rewards = { spec = dpSpec, open = function(ns)
        ns.Data.reward = ns.Data.reward or {}
        ns.Data.reward[2841] = { 9492, 9445, 9450, 6893, 9446, 9447 }
        ns.home = false; ns.selected = "GNOMER"; ns.Toggle(); ns.ShowTab(3); ns.OpenQuest(2841)
    end },
    forever = { spec = dpSpec, open = function(ns) ns.home = false; ns.selected = "DROWNED"; ns.Toggle(); ns.ShowTab(3) end },
    scholo = { spec = { level = 58, raceID = 2, faction = "Horde", className = "WARRIOR", areas = { [28] = "Western Plaguelands", [85] = "Tirisfal Glades" } },
               open = function(ns) ns.home = false; ns.selected = "SCHOLO"; ns.Toggle(); ns.ShowTab(3) end },
    chain = { spec = dpSpec, open = function(ns) ns.home = false; ns.selected = "DROWNED"; ns.Toggle(); ns.ShowTab(3); ns.OpenQuest(95775) end },
    -- A single quest with no chain and no rewards, done inside the dungeon: the way takes the page.
    inside = { spec = dpMara, open = function(ns) ns.home = false; ns.selected = "MARA"; ns.Toggle(); ns.ShowTab(3); ns.OpenQuest(96776) end },
    -- A chain whose step is taken and handed in inside the dungeon.
    outside = { spec = dpMara, open = function(ns) ns.home = false; ns.selected = "MARA"; ns.Toggle(); ns.ShowTab(3); ns.OpenQuest(93601, 93404) end },
    wowhead = { spec = dpMara, open = function(ns) ns.home = false; ns.selected = "MARA"; ns.Toggle(); ns.ShowTab(3); ns.OpenQuest(7046)
                    local d = ns.DetailFrame(); d.link:GetScript("OnClick")(d.link) end },
    -- Alcaz Prison: guide tips on every stage, the quest item, the boss row and the summary.
    alcaz = { spec = { level = 50, raceID = 2, faction = "Horde", className = "WARRIOR", active = { [96335] = true },
                       objectives = { [96335] = { { text = "Ornate Shackle Key: 0/1", finished = false } } } },
              open = function(ns) ns.home = false; ns.selected = "ALCAZ"; ns.Toggle(); ns.ShowTab(3); ns.OpenQuest(96335) end },
    alcaztake = { spec = { level = 50, raceID = 2, faction = "Horde", className = "WARRIOR" },
              open = function(ns) ns.home = false; ns.selected = "ALCAZ"; ns.Toggle(); ns.ShowTab(3); ns.OpenQuest(96335) end },
    insidechain = { spec = dpMara, open = function(ns) ns.home = false; ns.selected = "MARA"; ns.Toggle(); ns.ShowTab(3); ns.OpenQuest(7046) end },
    insidelist = { spec = dpMara, open = function(ns) ns.home = false; ns.selected = "MARA"; ns.Toggle(); ns.ShowTab(3) end },
    insidetracker = { spec = dpMara, crop = "GulliDungeonPrepTrackerStage",
                before = function()
                    local stage = CreateFrame("Frame", "GulliDungeonPrepTrackerStage", UIParent)
                    stage:SetSize(360, 460)
                    stage:SetPoint("CENTER")
                    local bg = stage:CreateTexture(nil, "BACKGROUND")
                    bg:SetAllPoints()
                    bg:SetColorTexture(0.16, 0.2, 0.16, 1)
                end,
                open = function(ns)
                    ns.db.trackerPoint = { "CENTER", "CENTER", 0, 0 }
                    ns.ShowTracker("MARA")
                end },
    -- The tracker of Lead me on its own, on a dark stand-in screen.
    tracker = { spec = dpSpec, crop = "GulliDungeonPrepTrackerStage",
                before = function()
                    local stage = CreateFrame("Frame", "GulliDungeonPrepTrackerStage", UIParent)
                    stage:SetSize(360, 420)
                    stage:SetPoint("CENTER")
                    local bg = stage:CreateTexture(nil, "BACKGROUND")
                    bg:SetAllPoints()
                    bg:SetColorTexture(0.16, 0.2, 0.16, 1)
                end,
                open = function(ns)
                    ns.db.trackerPoint = { "CENTER", "CENTER", 0, 0 }
                    ns.ShowTracker("GNOMER")
                end },    -- The tracker on the Drowned City, with one chain opened to show its steps.
    trackchain = { spec = { level = 40, raceID = 2, faction = "Horde", className = "WARRIOR",
                            areas = { [33] = "Stranglethorn Vale" }, done = { [629] = true }, active = { [95748] = true } },
                   crop = "GulliDungeonPrepTrackerStage",
                   before = function()
                       local stage = CreateFrame("Frame", "GulliDungeonPrepTrackerStage", UIParent)
                       stage:SetSize(360, 420)
                       stage:SetPoint("CENTER")
                       local bg = stage:CreateTexture(nil, "BACKGROUND")
                       bg:SetAllPoints()
                       bg:SetColorTexture(0.16, 0.2, 0.16, 1)
                   end,
                   open = function(ns)
                       ns.db.trackerPoint = { "CENTER", "CENTER", 0, 0 }
                       ns.ShowTracker("DROWNED")
                       for _, it in ipairs(ns.TrackerItems("DROWNED", 40)) do
                           if it.steps then ns.ToggleTracked(it.key) break end
                       end
                   end },
}

-- Spell icons by id for the Reminders previews (the fake client has none).
local REM_ICONS = { [1243] = "Interface\\Icons\\Spell_Holy_WordFortitude", [588] = "Interface\\Icons\\Spell_Holy_InnerFire",
    [14752] = "Interface\\Icons\\Spell_Holy_DivineSpirit", [976] = "Interface\\Icons\\Spell_Shadow_AntiShadow",
    [13165] = "Interface\\Icons\\Spell_Nature_RavenForm", [19506] = "Interface\\Icons\\Ability_TrueShot",
    [883] = "Interface\\Icons\\Ability_Hunter_BeastCall", [324] = "Interface\\Icons\\Spell_Nature_LightningShield" }
-- Items and imbues of the class supplies, with their names, for the same previews.
local REM_ITEMS = { [2892] = { "Deadly Poison", "Interface\\Icons\\Ability_Rogue_DualWeild" },
    [6949] = { "Instant Poison II", "Interface\\Icons\\Ability_Poisons" },
    [13928] = { "Grilled Squid", "Interface\\Icons\\INV_Misc_Fish_13" },
    [12404] = { "Dense Sharpening Stone", "Interface\\Icons\\INV_Stone_SharpeningStone_05" },
    [12643] = { "Dense Weightstone", "Interface\\Icons\\INV_Stone_WeightStone_05" },
    [20749] = { "Brilliant Wizard Oil", "Interface\\Icons\\INV_Potion_105" } }
local REM_SPELLS = { [8232] = { "Windfury Weapon", "Interface\\Icons\\Spell_Nature_Cyclone" },
    [8024] = { "Flametongue Weapon", "Interface\\Icons\\Spell_Fire_FlameTounge" },
    [8017] = { "Rockbiter Weapon", "Interface\\Icons\\Spell_Nature_RockBiter" },
    [3552] = { "Conjure Mana Jade", "Interface\\Icons\\INV_Misc_Gem_Emerald_02" },
    [759] = { "Conjure Mana Agate", "Interface\\Icons\\INV_Misc_Gem_Emerald_01" },
    [1459] = { "Arcane Intellect", "Interface\\Icons\\Spell_Holy_MagicalSentry" },
    [168] = { "Frost Armor", "Interface\\Icons\\Spell_Frost_FrostArmor02" },
    [324] = { "Lightning Shield", "Interface\\Icons\\Spell_Nature_LightningShield" } }
local function remIcons()
    C_Spell.GetSpellTexture = function(id) return REM_ICONS[id] or (REM_SPELLS[id] or {})[2] end
    C_Spell.GetSpellName = function(id) return (REM_SPELLS[id] or {})[1] or ("Spell" .. id) end
    C_Item.GetItemIconByID = function(id) return (REM_ITEMS[id] or {})[2] end
    C_Item.GetItemNameByID = function(id) return (REM_ITEMS[id] or {})[1] or ("Item" .. id) end
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
    -- A row with captions: each short caption sits under its own icon.
    captions = { spec = { class = "ROGUE", level = 30, items = { [6949] = 5, [13928] = 3 }, offHand = 50,
                          weapon = { false, 0, false, 0 }, db = { labels = true, food = true, foodItem = 13928 } },
                 before = remStage, open = function(ns) ns.db.point = { "CENTER", 0, 20 }; ns.Refresh() end,
                 crop = "GulliRemindersStage" },
    unlocked = { spec = { class = "HUNTER", known = { 13165, 19506, 883 }, auras = { "Spell13165" }, ammo = 120,
                          db = { vertical = true } },
                 before = remStage, open = function(ns) ns.db.point = { "CENTER", -60, 0 }; ns.Move(true) end,
                 crop = "GulliRemindersStage" },
    hunter = { spec = { class = "HUNTER", known = { 13165, 19506, 883 }, ammo = 120,
                        db = { point = { "BOTTOMLEFT", 0, 0 } } }, before = remIcons },
    -- Class supplies: the picks show the item or imbue a click uses.
    rogue = { spec = { class = "ROGUE", items = { [6949] = 5, [2892] = 5, [13928] = 3 }, offHand = 50,
                       db = { point = { "BOTTOMLEFT", 0, 0 }, foodItem = 13928, classes = { ROGUE = { main = 2892 } } } },
              before = remIcons },
    warrior = { spec = { class = "WARRIOR", items = { [12404] = 5, [12643] = 5 }, mainHand = 70, offHand = 71,
                         sub = { [70] = 7, [71] = 4 }, db = { point = { "BOTTOMLEFT", 0, 0 }, classes = { WARRIOR = { weapon = true } } } },
                before = remIcons },
    shaman = { spec = { class = "SHAMAN", known = { 324, 8017, 8024, 8232 }, db = { point = { "BOTTOMLEFT", 0, 0 } } },
               before = remIcons },
    mage = { spec = { class = "MAGE", known = { 1459, 168, 759, 3552 }, items = { [20749] = 2 },
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
        ns.group = { Bob = { leftHour = 1, wait = 0, t = now }, Fernard = { leftHour = 4, wait = 0, t = now } }
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
S.mobfinder.card = { spec = { level = 14 }, before = hudStage(500, 170), crop = "GulliHudStage",
    open = function(ns)
        ns.db.cardPoint = { "CENTER", 0, 0 }
        ns.ShowFind({ { name = "Foreman Grills" } })
    end }
-- A long name found in a fight while in a group: Tell and Pin, Target waits for the fight's end.
S.mobfinder.cardcombat = { spec = { level = 14 }, before = hudStage(500, 170), crop = "GulliHudStage",
    open = function(ns, W)
        ns.db.cardPoint = { "CENTER", 0, 0 }
        IsInGroup = function() return true end
        InCombatLockdown = function() return true end
        ns.ShowFind({ { name = "Nascent Pylon Protector", vignette = true }, { name = "Second" } })
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
    tracker = { crop = "GulliLegacyTracker", open = function(ns) ns.Scan(); ns.Snapshot(); ns.SetPref("tracker", true); ns.Refresh() end },
    explore = { open = function(ns) lgOpen()(ns); ns.ShowDetail(70040) end },
    detail = { open = function(ns) lgOpen()(ns); ns.ShowDetail(70010) end } }
-- The compact window that stands beside the game's Legacy window: the plan and its settings.
local function lgCompact(settings, goal)
    return function(ns)
        ns.Scan(); ns.Snapshot()
        ns.Pin(70010)
        if goal then ns.SetGoal(goal) end
        local c = ns.Compact()
        c:Show()
        ns.Refresh()
        if settings then c.ShowSettings(true) end
    end
end
S.legacy.compact = { crop = "GulliLegacyCompact", open = lgCompact() }
S.legacy.compactgoal = { crop = "GulliLegacyCompact", open = lgCompact(false, 15) }
S.legacy.compactset = { crop = "GulliLegacyCompact", open = lgCompact(true) }
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
S.instancelimit.settings = { spec = S.instancelimit.default.spec, open = function(ns) ns.ShowPage(2) end }
S.instancelimit.free = { spec = S.instancelimit.default.spec, open = function(ns) ns.db.entries = {}; ns.Toggle() end }
S.mobfinder.mobs = { spec = { level = 14 }, open = function(ns)
    ns.db.names = { "Sandfury Guardian", "firebird" }
    ns.db.ids = { [5400] = "Cyclok the Mad" }
    ns.Info("Sandfury Guardian").count = 2; ns.Info("Sandfury Guardian").zone = "Tanaris"
    ns.Toggle(); ns.ShowPage(1)
end }
S.mobfinder.settings = { spec = { level = 14 }, open = function(ns) ns.Toggle(); ns.ShowPage(3) end }
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
S.crates = { default = { spec = crSpec(), open = crOpen(true) },
    done = { spec = crSpec(), open = function(ns, W)
        crOpen(false)(ns, W)
        ns.buy.phase, ns.buy.spent = "done", 3760
        ns.Refresh()
    end }, plan = { spec = crSpec(), open = crOpen(false) },
    ru = { spec = crSpec("ruRU"), open = crOpen(true) },
    stale = { spec = (function() local sp = crSpec(); sp.now = 1000000; return sp end)(), open = function(ns, W)
        Auctionator.SavedState = { TimeOfLastReplicateScan = W.now - 6 * 3600 }
        crOpen(false)(ns, W)
    end },
    history = { spec = (function()
        local sp = crSpec()
        sp.db = { history = {
            { at = 99600, crate = 248691, item = 3819, n = 10, paid = 1920, bought = 6, who = "Gulliby" },
            { at = 99000, crate = 248682, item = 2447, n = 20, paid = 700, bought = 20, who = "Gulliby" },
            { at = 60000, crate = 248692, item = 2776, n = 10, paid = 0, bought = 0, who = "Tinkerbolt" },
            { at = 10000, crate = 248691, item = 8831, n = 20, paid = 37800, bought = 20, who = "Gulliby" } } }
        return sp
    end)(), open = function(ns, W)
        crIcons(W)
        ns.Window():Show()
        ns.ShowTab(3)
    end } }
-- Away from the auction house: the longest footer line (the estimate) in German.
S.crates.estimate_de = { spec = crSpec("deDE"), open = function(ns, W)
    crIcons(W)
    ns.Window():Show()
    ns.Calculate()
    ns.Refresh()
end }
-- The Favor tab: 30 Merchant's Favor from the crates in the bags and the auction house.
local function crFavor(locale)
    local sp = crSpec(locale)
    sp.level = 40
    for id, p in pairs({ [248682] = 9000, [248686] = 12000, [248690] = 15000, [248691] = 14000, [248692] = 11000,
                         [248683] = 8000, [2770] = 60, [2771] = 90, [2775] = 300, [2772] = 140 }) do sp.prices[id] = p end
    sp.names[248683], sp.names[2770], sp.names[2771] = "Waylaid Crate: Apprentice Ore", "Copper Ore", "Tin Ore"
    sp.db = { goal = 30 }
    return sp
end
local function crFavorOpen(ns, W)
    crIcons(W)
    AuctionHouseFrame = nil
    W.Fire("AUCTION_HOUSE_SHOW")
    ns.Window():Show()
    ns.ShowTab(2)
    ns.TokenCalculate()
    ns.Refresh()
end
S.crates.favor = { spec = crFavor(), open = crFavorOpen }
S.crates.favor_ru = { spec = crFavor("ruRU"), open = crFavorOpen }
local function crSettings(ns, W)
    crIcons(W)
    ns.Window():Show()
    ns.ShowTab(4)
end
S.crates.settings = { spec = crSpec(), open = crSettings }
S.crates.settings_ru = { spec = crSpec("ruRU"), open = crSettings }
-- The first-run window: Leatrix Plus sells junk, SilverDragon finds rares, Auctionator is on.
S.toolkit.setup = {
    spec = { addons = { { name = "Gulli-Toolkit", enabled = true, loaded = true, meta = { Version = "1.20.0" } },
        mod("QuestCleaner"), mod("AutoQuest"), mod("PartyQuests"), mod("GroupBuffs"), mod("DungeonPrep"),
        mod("InstanceLimit"), mod("Loot"), mod("BagSpace"), mod("Merchant"), mod("Mail"), mod("Crates"),
        mod("CraftProfit"), mod("Bulletin"), mod("Social"), mod("XP"), mod("MobFinder"), mod("Tooltip"),
        { name = "Leatrix_Plus", enabled = true, loaded = true }, { name = "SilverDragon", enabled = true, loaded = true },
        { name = "Auctionator", enabled = true, loaded = true } } },
    crop = "GulliToolkitSetup",
    open = function(ns)
        LeaPlusDB = { AutoSellJunk = "On", AutoRepairGear = "On" }
        for _, k in ipairs({ "QuestCleaner", "AutoQuest", "PartyQuests", "GroupBuffs", "DungeonPrep", "InstanceLimit",
                             "Loot", "BagSpace", "Merchant", "Mail", "Crates", "CraftProfit", "Bulletin", "Social",
                             "XP", "MobFinder", "Tooltip" }) do
            GulliToolkit.Register({ key = k, open = function() end, pause = function() end,
                icon = "Interface\\AddOns\\Gulli-" .. k .. "\\icon" })
        end
        ns.OpenSetup()
    end,
}
-- FarmTrack: an hour of farming Mageweave and gold, with a goal for each, plus other loot.
local function ftItems()
    local names = { [4338] = "Mageweave Cloth", [4306] = "Silk Cloth", [3858] = "Mithril Ore", [4304] = "Thick Leather",
                    [8838] = "Sungrass", [10285] = "Shadow Silk" }
    local icons = { [4338] = "INV_Fabric_Mageweave_01", [4306] = "INV_Fabric_Silk_01", [3858] = "INV_Ore_Mithril_02",
                    [4304] = "INV_Misc_LeatherScrap_08", [8838] = "INV_Misc_Herb_18", [10285] = "INV_Fabric_Silk_02" }
    C_Item.GetItemNameByID = function(id) return names[id] end
    C_Item.GetItemIconByID = function(id) return "Interface\\Icons\\" .. (icons[id] or "INV_Misc_QuestionMark") end
end
local function ftPlay(ns, W)
    ftItems()
    ns.AddTarget("item", 4338, 200)
    ns.AddTarget("gold", nil, 500000)
    for i = 1, 30 do
        W.now = i * 110
        W.Loot(4338, 3 + i % 3)
        if i % 4 == 0 then W.Loot(4306, 2) end
        if i % 7 == 0 then W.Loot(10285, 1) end
        if i % 5 == 0 then W.Loot(8838, 1) end
        W.Money(2150 + i * 37)
    end
    ns.Refresh()
end
-- Beside the auction house with another module's work there: the strip of tabs over the header.
S.crates.tabs = { spec = crSpec(), open = function(ns, W)
    crOpen(true)(ns, W)
    local other = ns.Skin.Window(nil, "Gulli Craft Profit", ns.Skin.NARROW_W, ns.Skin.DOCK_H)
    ns.Skin.SideAdd({ key = "CraftProfit", order = 20, title = "Gulli Craft Profit",
                      icon = "Interface\\Icons\\Trade_Tailoring", window = function() return other end,
                      badge = function() return 2 end })
    ns.Skin.SideOpen("CraftProfit")
    ns.Refresh()
end }

S.farmtrack = { default = { spec = { now = 0 }, open = function(ns, W) ftPlay(ns, W); ns.Toggle() end },
    settings = { spec = { now = 0 }, open = function(ns, W) ftPlay(ns, W); ns.Toggle(); select(3, ns.Parts()):Select(2) end },
    panel = { spec = { now = 0 }, open = function(ns, W) ftPlay(ns, W); ns.AddTarget("item", 3858) ; ns.Refresh() end,
              crop = "GulliFarmTrackPanel" },
    worth = { spec = { now = 0, ah = { [4338] = 1800, [4306] = 400, [10285] = 3500, [8838] = 900 },
                       items = { [4338] = { class = 7 }, [4306] = { class = 7 }, [10285] = { class = 7 },
                                 [8838] = { class = 7 } } },
              open = function(ns, W) ftPlay(ns, W); ns.SetPref("panel", true); ns.SetPref("value", true) end,
              crop = "GulliFarmTrackPanel" },
    empty = { spec = { now = 0 }, open = function(ns) ns.Toggle() end } }

-- Fishing: half an hour at a pool, a lure on the pole.
local function fiPlay(ns, W)
    local names = { [6303] = "Raw Slitherskin Mackerel", [6291] = "Raw Brilliant Smallfish", [6358] = "Oily Blackmouth",
                    [6643] = "Bloated Smallfish", [6299] = "Sickly Looking Fish" }
    local icons = { [6303] = "INV_Misc_Fish_14", [6291] = "INV_Misc_Fish_02", [6358] = "INV_Misc_Fish_07",
                    [6643] = "INV_Misc_Fish_17", [6299] = "INV_Misc_Fish_09" }
    C_Item.GetItemNameByID = function(id) return names[id] end
    C_Item.GetItemIconByID = function(id) return "Interface\\Icons\\" .. (icons[id] or "INV_Misc_QuestionMark") end
    for i = 1, 23 do
        local id = (i % 5 == 0 and 6358) or (i % 7 == 0 and 6643) or (i % 3 == 0 and 6291) or 6303
        W.Catch({ { id, 1 } })
    end
    W.Catch({ { 6299, 1 } })
    W.lureLeft = 420
    ns.Refresh()
end
S.fishing = { default = { open = function(ns, W) ns.Toggle(); fiPlay(ns, W) end },
    settings = { open = function(ns, W) ns.Toggle(); fiPlay(ns, W); select(4, ns.Parts()):Select(2) end },
    empty = { spec = { pole = false }, open = function(ns) ns.Toggle() end } }

-- Worth It: a level 20 hunter in Westfall with small bags, one chain in the log.
local wiNames = { [1537] = "Old Blanchy's Feed Pouch", [3343] = "Captain Sander's Booty Bag", [1729] = "Gunnysack of the Night Watch",
    [3604] = "Bandolier of the Night Watch", [3605] = "Quiver of the Night Watch", [918] = "Deviate Hide Pack",
    [3573] = "Hunting Quiver", [3574] = "Hunting Ammo Sack", [270017] = "Hunting Satchel", [2082] = "Wizbang's Gunnysack",
    [277977] = "Canvas Latchbag", [279936] = "Book Bag", [280088] = "Soft Saber Sack", [286734] = "Ban'ethil Quiver",
    [277332] = "Scuffed Shipping Crate", [3352] = "Ooze-covered Bag", [221498] = "Old Toolbox", [11324] = "Explorer's Knapsack",
    [9587] = "Thawpelt Sack", [10959] = "Demon Hide Sack", [226697] = "Red Bag", [282286] = "Shipwright's Satchel" }
local wiSpec = { level = 20, class = "HUNTER", zone = 40, x = 52, y = 30, bags = { 6, 6, 8, 8 }, family = { [4] = 1 },
    done = { [136] = true, [138] = true, [97277] = true, [87288] = true }, log = { [139] = true, [151] = true }, ready = { [151] = true },
    slots = { [1537] = 8, [3343] = 8, [1729] = 10, [3604] = 12, [3605] = 12, [918] = 10, [3573] = 10, [3574] = 10, [270017] = 8,
              [2082] = 8, [277977] = 6, [279936] = 6, [280088] = 6, [286734] = 8, [277332] = 8, [3352] = 10, [221498] = 10,
              [11324] = 14, [9587] = 14, [10959] = 16, [226697] = 16, [282286] = 12 } }
local function wiOpen(ns)
    local icons = { ammo = "INV_Misc_Quiver_03", bag = "INV_Misc_Bag_10" }
    C_Item.GetItemNameByID = function(id) return wiNames[id] or ("Bag " .. id) end
    C_Item.GetItemIconByID = function(id)
        local n = wiNames[id] or ""
        return "Interface\\Icons\\" .. ((n:find("Quiver") and "INV_Misc_Quiver_03") or (n:find("Bandolier") and "INV_Misc_AmmoSack_02")
            or (id > 5000 and id < 5100 and "INV_Misc_Bag_09") or "INV_Misc_Bag_10")
    end
    C_Item.GetItemQualityByID = function(id) return (id == 3604 or id == 3605 or id == 918) and 2 or 1 end
    C_Map.GetAreaInfo = function(id)
        return ({ [40] = "Westfall", [10] = "Duskwood", [12] = "Elwynn Forest", [38] = "Loch Modan", [17] = "The Barrens",
                  [141] = "Teldrassil", [148] = "Darkshore", [1] = "Dun Morogh", [1519] = "Stormwind City" })[id] or ("Area " .. id)
    end
    ns.Toggle()
end
-- The library: book names from the comments of Data.lua, a few handed in, two in the bags.
local function wiLibrary(ns, W)
    local names = {}
    for line in io.lines("Gulli-WorthIt/Data.lua") do
        local item, name = line:match("^{%d+,(%d+),.-}, %-%- (.+)$")
        if item then names[tonumber(item)] = name end
    end
    local name, icon = C_Item.GetItemNameByID, C_Item.GetItemIconByID
    C_Item.GetItemNameByID = function(id) return names[id] or name(id) end
    C_Item.GetItemIconByID = function(id)
        if names[id] then return "Interface\\Icons\\INV_Misc_Book_0" .. (id % 9 + 1) end
        return icon(id)
    end
    for i = 1, 11 do W.done[ns.Data.books[i][1]] = true end
    W.done[78150] = true
    W.items = { [ns.Data.books[14][2]] = 1, [ns.Data.books[15][2]] = 1 }
end
local wiLibSpec = { level = 38, class = "MAGE", zone = 38, x = 60, y = 30, bags = { 10, 10, 12, 12 } }
S.worthit = { default = { spec = wiSpec, open = function(ns) wiOpen(ns); ns.Show(140) end },
    rest = { spec = wiSpec, open = function(ns) wiOpen(ns); ns.Show(79976) end },
    lead = { spec = wiSpec, open = function(ns) wiOpen(ns); ns.StartGuide(); ns.Refresh() end },
    settings = { spec = wiSpec, open = function(ns) wiOpen(ns); select(4, ns.Parts()):Select(4) end },
    library = { spec = wiLibSpec, open = function(ns, W) wiOpen(ns); wiLibrary(ns, W); ns.Show(79093) end },
    libraryLead = { spec = wiLibSpec, open = function(ns, W) wiOpen(ns); wiLibrary(ns, W); ns.Show(79093); ns.StartLibrary(); ns.Refresh() end },
    libraryGoal = { spec = wiLibSpec, open = function(ns, W) wiOpen(ns); wiLibrary(ns, W); ns.SetLibGoal(79536); ns.Show(79093) end },
    class = { spec = { level = 30, class = "WARRIOR", faction = "Horde", raceId = 2, zone = 17, bags = { 6, 6, 8, 8 },
                       done = { [1505] = true, [1498] = true, [1502] = true, [1503] = true, [1823] = true, [1824] = true },
                       log = { [1825] = true } },
              open = function(ns) wiOpen(ns); ns.Show(1845) end },
    other = { spec = { level = 30, class = "WARRIOR", faction = "Horde", raceId = 2, zone = 17, bags = { 6, 6, 8, 8 } },
              open = function(ns) wiOpen(ns); ns.Show(1845); ns.ViewClass(9) end },
    empty = { spec = { level = 60, bags = { 18, 18, 18, 18 } }, open = function(ns) ns.Toggle() end } }
-- Vendor Flip: the market after a scan, the belt bought, a price asked for the copper ore.
local VF_ICONS = { [2770] = "INV_Ore_Copper_01", [3300] = "INV_Misc_Bone_08", [5001] = "INV_Belt_03", [5002] = "INV_Misc_Cape_01",
    [2318] = "INV_Misc_LeatherScrap_03", [765] = "INV_Misc_Herb_10", [2449] = "INV_Misc_Herb_07", [5003] = "INV_Staff_02",
    [5004] = "INV_Gauntlets_04", [5005] = "INV_Bracer_07", [4234] = "INV_Misc_LeatherScrap_07", [2862] = "INV_Stone_SharpeningStone_01",
    [5006] = "INV_Helmet_08", [5007] = "INV_Misc_Cape_02", [3667] = "INV_Misc_Ribbon_01", [4304] = "INV_Misc_Pelt_Wolf_01" }
local function vfSpec(locale)
    local items = {
        [2770] = { "Copper Ore", 1, 10, 20 }, [3300] = { "Broken Fang", 0, 230, 10 }, [5001] = { "Chain Belt of the Warrior", 2, 11200, 1 },
        [5002] = { "Cloak of the Dark Shore", 2, 3500, 1 }, [5003] = { "Woodland Staff", 2, 7100, 1 },
        [2318] = { "Light Leather", 1, 15, 20 }, [765] = { "Silverleaf", 1, 5, 20 }, [2449] = { "Earthroot", 1, 10, 20 },
        [5004] = { "Hunter's Leather Gloves", 2, 2600, 1 }, [5005] = { "Nighthaven Bracers", 2, 4100, 1 },
        [4234] = { "Heavy Leather", 1, 150, 20 }, [2862] = { "Rough Sharpening Stone", 1, 50, 20 },
        [5006] = { "Thelsamar Guard Helm", 2, 9400, 1 }, [3667] = { "Chitin Shard", 0, 155, 20 }, [4304] = { "Soft Fur", 0, 100, 10 } }
    local browse = { { 2770, 4 }, { 3300, 75 }, { 5001, 4800 }, { 5003, 5500 }, { 765, 1 }, { 4234, 70 }, { 5004, 1900 },
        { 3667, 47 }, { 2862, 12 }, { 5005, 3000 }, { 4304, 24 }, { 2449, 1 }, { 5006, 6200 }, { 5002, 2000 } }
    return { locale = locale, items = items, browse = browse, money = 2340000, free = 11,
        commodity = { [2770] = { { 4, 30 }, { 6, 12 } }, [3300] = { { 75, 12 } }, [765] = { { 1, 20 } }, [4234] = { { 70, 15 } },
                      [3667] = { { 47, 31 } }, [2862] = { { 12, 20 } }, [4304] = { { 24, 8 } }, [2449] = { { 1, 10 } } },
        lots = { [5001] = { { 901, 1, 4800 } }, [5003] = { { 902, 1, 5500 } }, [5004] = { { 903, 1, 1900 } },
                 [5005] = { { 904, 1, 3000 } }, [5006] = { { 905, 1, 6200 } }, [5002] = { { 906, 1, 2000 } } },
        db = { minGain = 100, history = {
            { at = 99950, id = 5006, n = 1, paid = 6200, value = 9400, sold = 0, who = "Tester-Realm" },
            { at = 99900, id = 2770, n = 40, paid = 168, value = 400, sold = 40, who = "Tester-Realm" },
            { at = 98600, id = 3300, n = 12, paid = 900, value = 2760, sold = 12, who = "Tester-Realm" },
            { at = 60000, id = 4304, n = 8, paid = 192, value = 800, sold = 8, keep = true, who = "Tester-Realm" } } } }
end
local function vfIcons()
    local get = C_Item.GetItemInfo
    C_Item.GetItemInfo = function(item)
        local r = { get(item) }
        local id = type(item) == "number" and item or tonumber(tostring(item):match("item:(%d+)"))
        if r[1] then r[10] = "Interface\\Icons\\" .. (VF_ICONS[id] or "INV_Misc_QuestionMark") end
        return unpack(r, 1, 11)
    end
end
local function vfOpen(tab, quote)
    return function(ns, W)
        vfIcons()
        AuctionHouseFrame = nil -- the preview has no auction window to stand beside
        W.ScanAll(ns)
        for _, line in ipairs(ns.lines) do
            if line.id == 5006 then line.state = "bought" end
            if line.id == 5002 then line.state = "gone" end
        end
        if quote then
            for _, line in ipairs(ns.lines) do if line.id == 2770 then ns.Click(line) end end
            W.Fire("COMMODITY_PRICE_UPDATED", 4, 168)
        end
        W.now = W.now + 42
        ns.Window():Show()
        ns.ShowTab(tab)
        ns.Refresh()
    end
end
S.vendorflip = { default = { spec = vfSpec(), open = vfOpen(1) },
    quote = { spec = vfSpec(), open = vfOpen(1, true) },
    ru = { spec = vfSpec("ruRU"), open = vfOpen(1, true) },
    history = { spec = vfSpec(), open = vfOpen(2) },
    queue = { spec = vfSpec(), open = function(ns, W)
        vfOpen(1, true)(ns, W)
        local n = 0
        for _, line in ipairs(ns.Shown()) do
            if not line.state and line ~= ns.buy.line and n < 2 then n = n + 1; ns.Click(line) end
        end
        ns.Refresh()
    end },
    settings = { spec = vfSpec(), open = vfOpen(3) },
    filters = { spec = vfSpec(), open = function(ns, W)
        vfOpen(3)(ns, W)
        local sc = ns.Window().settingsPage.scroll
        local sf = sc.scroll or sc
        sf:SetVerticalScroll(560)
    end },
    empty = { spec = { items = {} }, open = function(ns) ns.Window():Show(); ns.Refresh() end },
    sidetabs = { spec = vfSpec("ruRU"), open = function(ns, W)
        vfOpen(1)(ns, W)
        local S2 = ns.Skin
        local crates = S2.Window(nil, "Gulli Waylaid Crates", S2.NARROW_W, S2.DOCK_H)
        local cp = S2.Window(nil, "Gulli Craft Profit", S2.NARROW_W, S2.DOCK_H)
        S2.SideAdd({ key = "Crates", order = 10, title = "Ящики", icon = "Interface\\Icons\\INV_Crate_01",
                     window = function() return crates end, badge = function() return 3 end })
        S2.SideAdd({ key = "CraftProfit", order = 20, title = "Craft Profit", icon = "Interface\\Icons\\INV_Misc_Herb_10",
                     window = function() return cp end })
        S2.SideOpen("Crates")
        S2.SideOpen("CraftProfit")
        S2.SideOpen("VendorFlip", true)
        ns.Refresh()
    end } }

-- My BiS List: an arms warrior at 60 wearing part of the pre-raid list, two better items in the bags.
local MB_ICON = { head = "INV_Helmet_03", neck = "INV_Jewelry_Necklace_07", shoulder = "INV_Shoulder_29", back = "INV_Misc_Cape_18",
    chest = "INV_Chest_Plate06", wrist = "INV_Bracer_07", hands = "INV_Gauntlets_26", waist = "INV_Belt_27", legs = "INV_Pants_04",
    feet = "INV_Boots_Plate_06", finger = "INV_Jewelry_Ring_15", trinket = "INV_Misc_Orb_02", ["2h"] = "INV_Sword_50",
    mh = "INV_Sword_27", ["1h"] = "INV_Sword_27", oh = "INV_Shield_05", held = "INV_Misc_Book_09", ranged = "INV_Weapon_Bow_08" }
local function mbOpen(ns, W, slot)
    local D = ns.Data
    C_Item.GetItemNameByID = function(id) return D.item[id] and D.item[id][7] or ("Item " .. id) end
    C_Item.GetItemIconByID = function(id) return "Interface\\Icons\\" .. (MB_ICON[D.item[id] and D.item[id][1]] or "INV_Misc_QuestionMark") end
    C_Item.GetItemQualityByID = function(id) return D.item[id] and D.item[id][2] or 1 end
    local l = D.lists.WARRIOR_ARMS.PRE
    W.worn = { [1] = l.head[1], [2] = l.neck[3], [3] = l.shoulder[3], [15] = l.back[1], [5] = l.chest[2], [9] = l.wrist[1],
               [16] = l.main[1], [11] = l.finger1[1], [13] = l.trinket1[2], [8] = l.feet[4] }
    W.items = { [l.legs[1]] = 1, [l.hands[3]] = 1 }
    for _, id in pairs(W.worn) do W.items[id] = (W.items[id] or 0) + 1 end
    ns.SetMySpec("WARRIOR_ARMS")
    ns.Toggle()
    ns.Show(slot or "head")
end
local mbSpec = function() return { level = 60, class = "WARRIOR", faction = "Alliance", spec = 71 } end
S.mybislist = { default = { spec = mbSpec(), open = function(ns, W) mbOpen(ns, W, "legs") end },
    head = { spec = mbSpec(), open = function(ns, W) mbOpen(ns, W, "head") end },
    level = { spec = { level = 34, class = "PRIEST", faction = "Horde", spec = 258 }, open = function(ns, W)
        mbOpen(ns, W); W.worn = {}; ns.SetMySpec("PRIEST_SHADOW"); ns.SetMain("auto"); ns.Show("main") end },
    settings = { spec = mbSpec(), open = function(ns, W) mbOpen(ns, W); ns.ShowTab(2) end },
    four = { spec = mbSpec(), open = function(ns, W)
        mbOpen(ns, W, "neck")
        local ref = ns.CopyList("site:WARRIOR_ARMS:PRE")
        ns.ViewRefSet(ref)
        ns.OwnRemove(ref, "neck", ns.Resolve(ref).slots.neck[5])
        W.worn[2] = 18723
        ns.Refresh()
    end },
    offlist = { spec = mbSpec(), open = function(ns, W)
        mbOpen(ns, W, "neck")
        W.worn[2] = 18723
        ns.Refresh()
    end },
    own = { spec = mbSpec(), open = function(ns, W)
        mbOpen(ns, W, "legs")
        local ref = ns.CopyList("site:WARRIOR_ARMS:PRE")
        ns.RenameOwn(ref, "Arms: my dungeon set")
        ns.db.own[1].snap.head = 1
        ns.ViewRefSet(ref)
    end },
    add = { spec = mbSpec(), open = function(ns, W)
        mbOpen(ns, W, "legs")
        local ref = ns.CopyList("site:WARRIOR_ARMS:PRE")
        ns.ViewRefSet(ref)
        ns.OwnRemove(ref, "legs", ns.Resolve(ref).slots.legs[5])
        ns.OpenAdd(select(1, ns.Parts()).card.add)
    end } }

-- Writ Runner: a Friendly character with writs in the bags, two of them ready, and a plan.
local WR_NAMES = { [264011] = "Craftsman's Writ: Elixir of Ogre's Strength", [3391] = "Elixir of Ogre's Strength",
    [264012] = "Craftsman's Writ: Elixir of Wisdom", [3383] = "Elixir of Wisdom",
    [264056] = "Craftsman's Writ: Frost Protection Potion", [6050] = "Frost Protection Potion",
    [264037] = "Craftsman's Writ: Crafted Solid Shot", [8069] = "Crafted Solid Shot",
    [264116] = "Craftsman's Writ: Potion of Demonslaying", [9224] = "Potion of Demonslaying",
    [262888] = "Sealed Journeyman's Writ", [262889] = "Sealed Expert's Writ", [262890] = "Sealed Artisan's Writ" }
local function wrSpec(locale)
    return { locale = locale, names = WR_NAMES, rep = { 5, 6240 }, reset = 4 * 3600 + 23 * 60,
             bags = { [264011] = 1, [3391] = 1, [264012] = 1, [3383] = 1, [264056] = 1, [264037] = 1, [262889] = 2 },
             done = { [94316] = true },
             prices = { [264011] = 9000, [3391] = 2500, [264012] = 12000, [3383] = 4200, [264056] = 26000, [6050] = 9800,
                        [264037] = 14000, [8069] = 6, [264116] = 41000, [9224] = 22000, [262888] = 15000,
                        [262889] = 30000, [262890] = 52000 },
             db = { days = 3, goal = 6, history = {
                 { at = 90000, writ = 264116, rep = 200, paid = 63000, pouch = 15179, who = "Tester" },
                 { at = 80000, writ = 264011, rep = 75, paid = 0, pouch = 3490, who = "Tester" } } } }
end
local WR_ZONES = { [1416] = "Alterac Mountains", [1417] = "Arathi Highlands", [1418] = "Badlands", [1437] = "Wetlands",
    [1440] = "Ashenvale", [1447] = "Azshara" }
local function wrOpen(tab, plan)
    return function(ns)
        C_Map.GetMapInfo = function(id) return { name = WR_ZONES[id] or "Stranglethorn Vale" } end
        local get = C_Reputation.GetFactionDataByID
        C_Reputation.GetFactionDataByID = function(id)
            local d = get(id)
            if d then d.name = "Azeroth Commerce Authority" end
            return d
        end
        if plan then ns.Calculate() end
        ns.Window():Show()
        ns.ShowTab(tab)
        ns.Refresh()
    end
end
S.writrunner = { default = { spec = wrSpec(), open = wrOpen(1) },
    ru = { spec = wrSpec("ruRU"), open = wrOpen(1) },
    de = { spec = wrSpec("deDE"), open = wrOpen(1) },
    plan = { spec = wrSpec(), open = wrOpen(2, true) },
    plan_ru = { spec = wrSpec("ruRU"), open = wrOpen(2, true) },
    plan_de = { spec = wrSpec("deDE"), open = wrOpen(2, true) },
    empty = { spec = { rep = { 5, 6240 } }, open = wrOpen(2) },
    writs = { spec = wrSpec(), open = wrOpen(3) },
    history = { spec = wrSpec(), open = wrOpen(4) },
    settings = { spec = wrSpec(), open = wrOpen(5) },
    settings_ru = { spec = wrSpec("ruRU"), open = wrOpen(5) } }

return S
