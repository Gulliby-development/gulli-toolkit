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
                options = k == "QuestCleaner" and {
                    { label = "Keep class quests", get = function() return true end, set = function() end },
                    { label = "Keep dungeon and raid quests", get = function() return false end, set = function() end },
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

return S
