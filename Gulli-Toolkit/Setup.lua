-- The first-run window: which modules to use, with a start value that follows the addons the
-- player already runs. Here are the rules; UI.lua only shows them.

local _, ns = ...
local L = ns.L

-- Popular addons that do a module's job, or that a module works with. Folder names come from
-- the addon index and CurseForge (see AGENTS.md). Each entry:
--   name   what the window says ("Because you have <name>")
--   addons folder names; any one of them that runs or is switched on counts
--   same   module key -> true: the addon does the module's job, so the module starts off.
--          A list of keys instead of true: only these saved settings of the addon count
--          (db names its saved variable, a setting counts when it is "On" or true).
--   with   module key -> true: the module uses this addon, so it starts on.
ns.OTHERS = {
    { name = "Leatrix Plus", addons = { "Leatrix_Plus" }, db = "LeaPlusDB", same = {
        Merchant = { "AutoSellJunk", "AutoRepairGear" },
        AutoQuest = { "AutomateQuests" },
        Social = { "NoDuelRequests", "NoPartyInvites", "AcceptPartyFriends", "InviteFromWhisper",
                   "AutoAcceptSummon", "AutoAcceptRes" },
    } },
    -- Junk sellers.
    { name = "Scrap", addons = { "Scrap" }, same = { Merchant = true } },
    { name = "Vendor", addons = { "Vendor" }, same = { Merchant = true } },
    { name = "Dejunk", addons = { "Dejunk" }, same = { Merchant = true } },
    { name = "Peddler", addons = { "Peddler" }, same = { Merchant = true } },
    { name = "JunkMate", addons = { "JunkMate" }, same = { Merchant = true } },
    { name = "ItemFlow", addons = { "ItemFlow" }, same = { Merchant = true } },
    { name = "Valet", addons = { "Valet" }, same = { Merchant = true } },
    { name = "Improved Forever: Junk", addons = { "ImprovedForever_Junk" }, same = { Merchant = true } },
    -- Quest automation, and guides that accept and hand in the quests of their route.
    { name = "QuickQuest", addons = { "QuickQuest" }, same = { AutoQuest = true } },
    { name = "AutoTurnIn", addons = { "AutoTurnIn" }, same = { AutoQuest = true } },
    { name = "RestedXP", addons = { "RXPGuides" }, same = { AutoQuest = true } },
    { name = "Guidelime", addons = { "Guidelime" }, same = { AutoQuest = true } },
    { name = "Reckless Abandon", addons = { "RecklessAbandon" }, same = { QuestCleaner = true } },
    { name = "QuestPrune", addons = { "QuestPruneForever" }, same = { QuestCleaner = true } },
    -- Mailboxes.
    { name = "Postal", addons = { "Postal" }, same = { Mail = true } },
    { name = "Postbox", addons = { "Postbox" }, same = { Mail = true } },
    { name = "Parcel", addons = { "Parcel" }, same = { Mail = true } },
    { name = "BulkMail", addons = { "BulkMail2Inbox" }, same = { Mail = true } },
    { name = "TradeSkillMaster", addons = { "TradeSkillMaster" }, same = { Mail = true } },
    -- Rare finders.
    { name = "SilverDragon", addons = { "SilverDragon" }, same = { MobFinder = true } },
    { name = "RareScanner", addons = { "RareScanner" }, same = { MobFinder = true } },
    { name = "unitscan", addons = { "unitscan" }, same = { MobFinder = true } },
    { name = "NPCScan", addons = { "_NPCScan" }, same = { MobFinder = true } },
    -- Buffs and reminders.
    { name = "SmartBuff", addons = { "SmartBuff" }, same = { GroupBuffs = true, Reminders = true } },
    { name = "Buffsmith", addons = { "Buffsmith" }, same = { GroupBuffs = true, Reminders = true } },
    { name = "PallyPower", addons = { "PallyPower" }, same = { GroupBuffs = true } },
    { name = "Priestly", addons = { "Priestly" }, same = { GroupBuffs = true } },
    { name = "BuffReminder", addons = { "OpcowsBuffReminder" }, same = { Reminders = true } },
    { name = "EllesmereUI", addons = { "EllesmereUIAuraBuffReminders" }, same = { Reminders = true } },
    -- Groups and instances.
    { name = "LFG Bulletin Board", addons = { "GroupBulletinBoard" }, same = { Bulletin = true } },
    { name = "Nova Instance Tracker", addons = { "NovaInstanceTracker" }, same = { InstanceLimit = true } },
    { name = "Attune", addons = { "Attune" }, same = { Attune = true } },
    -- Experience bars.
    { name = "XToLevel", addons = { "XToLevel" }, same = { XP = true } },
    { name = "Experiencer", addons = { "Experiencer" }, same = { XP = true } },
    { name = "per-hour", addons = { "per-hour" }, same = { XP = true } },
    { name = "XPForever", addons = { "XPForever" }, same = { XP = true } },
    { name = "XPBarIsland", addons = { "XPBarIsland" }, same = { XP = true } },
    { name = "ForeverXP", addons = { "ForeverChallengeXP" }, same = { XP = true } },
    -- WoW Forever helpers.
    { name = "Legacy Navigator", addons = { "LegacyNavigator" }, same = { Legacy = true } },
    { name = "Waylaid Value", addons = { "WaylaidValue" }, same = { Crates = true } },
    -- Addons a module reads.
    { name = "Auctionator", addons = { "Auctionator" }, with = { CraftProfit = true, Crates = true, BagSpace = true } },
    { name = "TomTom", addons = { "TomTom" }, with = { DungeonPrep = true } },
}

-- A module that does nothing for a class starts off for it.
ns.CLASS_OFF = { GroupBuffs = { ROGUE = true } }

-- Whether a setting of the addon's saved variable is on.
local function settingOn(db, key)
    local v = type(db) == "table" and db[key]
    return v == "On" or v == true
end

-- Which entry of ns.OTHERS runs, by its folder names; a name list is passed by the tests.
local function active(entry, names)
    for _, a in ipairs(entry.addons) do
        if names then
            if names[a] then return true end
        elseif ns.AddonActive(a) then return true end
    end
end

-- For each installed module: { row, on = the start value, why = the grey line or nil }.
-- names (optional, for the tests): addon folder -> true for the addons that run.
function ns.SetupPlan(names)
    local same, with = {}, {}
    for _, e in ipairs(ns.OTHERS) do
        if active(e, names) then
            local db = e.db and _G[e.db]
            for key, keys in pairs(e.same or {}) do
                local hit = keys == true
                if type(keys) == "table" then
                    for _, k in ipairs(keys) do if settingOn(db, k) then hit = true end end
                end
                if hit then same[key] = same[key] or {}; table.insert(same[key], e.name) end
            end
            for key in pairs(e.with or {}) do
                with[key] = with[key] or {}
                table.insert(with[key], e.name)
            end
        end
    end
    local className, class = UnitClass("player")
    local out = {}
    for _, row in ipairs(ns.List()) do
        local p = { row = row, on = row.on and true or false }
        if same[row.key] then
            p.on, p.why = false, L.SETUP_SAME:format(table.concat(same[row.key], ", "))
        elseif ns.CLASS_OFF[row.key] and class and ns.CLASS_OFF[row.key][class] then
            p.on, p.why = false, L.SETUP_CLASS:format(className or class)
        elseif with[row.key] then
            p.on, p.why = true, L.SETUP_WITH:format(table.concat(with[row.key], ", "))
        end
        out[#out + 1] = p
    end
    return out
end

-- A pick needs a reload when its module cannot pause and start at once.
local function needsReload(row, on)
    if row.on == on then return false end
    if row.canPause and row.loadOn and row.running then return false end
    return true
end

function ns.SetupNeedsReload(plan)
    for _, p in ipairs(plan) do
        if p.row.addon and needsReload(p.row, p.on) then return true end
    end
    return false
end

-- The setup is done: the window does not open by itself again (/gulli setup opens it).
function ns.SetupDone()
    GulliToolkitDB = GulliToolkitDB or {}
    GulliToolkitDB.setup = true
end

-- Reads each module's row again after a switch, so a second Apply compares with the game's state.
function ns.SetupRows(plan)
    local by = {}
    for _, row in ipairs(ns.List()) do by[row.key] = row end
    for _, p in ipairs(plan) do p.row = by[p.row.key] or p.row end
end

-- Switches every module as picked. Returns how many switches changed and the titles of the
-- modules the game did not switch. One module that fails never stops the rest.
function ns.ApplySetup(plan)
    local n, failed = 0, {}
    ns.quietSwitch = true
    for _, p in ipairs(plan) do
        if p.row.addon and p.row.on ~= p.on then
            local ok, took = pcall(ns.Switch, p.row, p.on)
            if ok and took ~= false then n = n + 1
            else failed[#failed + 1] = p.row.title or p.row.key end
        end
    end
    ns.quietSwitch = nil
    if #failed > 0 then ns.Print(L.SWITCH_FAILED:format(table.concat(failed, ", "))) end
    ns.SetupDone()
    return n, failed
end
