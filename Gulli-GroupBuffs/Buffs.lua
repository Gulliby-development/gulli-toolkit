local _, ns = ...

-- The buffs each class can give, by rank 1 spell id. The game gives the names in the
-- client's language, so nothing here needs a translation. A spell the client does not
-- know (an id Forever lacks, or a talent not taken) is left out at run time.
--   who:   "all" (everyone), "mana" (classes with mana), "self", "thorns" (a setting),
--          "blessing" (a setting per class and role)
--   also:  other spells whose buff counts as this one (the group versions, Greater Blessings)
--   group: the spell that buffs a whole party at once
local B = {}
ns.Buffs = B

B.CLASS = {
    PRIEST = {
        { key = "fort", id = 1243, group = 21562, who = "all" },
        { key = "spirit", id = 14752, group = 27681, who = "mana" },
        { key = "shadow", id = 976, group = 27683, who = "all", off = true },
        { key = "innerfire", id = 588, who = "self" },
    },
    MAGE = {
        { key = "int", id = 1459, group = 23028, who = "mana" },
    },
    DRUID = {
        { key = "motw", id = 1126, group = 21849, who = "all" },
        { key = "thorns", id = 467, who = "thorns" },
    },
    PALADIN = {
        { key = "blessing", who = "blessing" },
    },
    SHAMAN = {
        { key = "shield", who = "self", choice = "shield" },
        { key = "weapon", who = "self", choice = "weapon", weapon = true },
    },
}

-- Blessings: the plain spell and its Greater version, which counts as the same buff.
-- Forever has no Blessing of Salvation or Light.
B.BLESSINGS = {
    { key = "might", id = 19740, also = { 25782 } },
    { key = "wisdom", id = 19742, also = { 25894 } },
    { key = "kings", id = 20217, also = { 25898 } },
    { key = "sanctuary", id = 20911, also = { 25899 } },
}

-- Shaman self buffs picked in the settings.
B.CHOICES = {
    shield = {
        { key = "lightning", id = 324 },
        { key = "water", id = 24398 },
    },
    weapon = {
        { key = "rockbiter", id = 8017 },
        { key = "flametongue", id = 8024 },
        { key = "frostbrand", id = 8033 },
        { key = "windfury", id = 8232 },
    },
}

-- Classes without mana get no Intellect or Spirit.
B.NO_MANA = { WARRIOR = true, ROGUE = true, DEATHKNIGHT = true, DEMONHUNTER = true }

B.CLASSES = { "WARRIOR", "ROGUE", "HUNTER", "MAGE", "WARLOCK", "PRIEST", "DRUID", "SHAMAN", "PALADIN" }

-- Blessing defaults: Might for melee, Wisdom for casters and hunters, Kings for tanks.
B.BLESS_DEFAULT = {
    WARRIOR = "might", ROGUE = "might", HUNTER = "wisdom", MAGE = "wisdom", WARLOCK = "wisdom",
    PRIEST = "wisdom", DRUID = "might", SHAMAN = "might", PALADIN = "might",
    TANK = "kings", HEALER = "wisdom",
}
