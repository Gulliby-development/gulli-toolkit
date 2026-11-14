-- Gulli-QuestCleaner: abandon low-level quests and delete quest items nothing needs.
-- WoW Forever runs Vanilla content on the Retail engine, so this uses the Retail API
-- (C_QuestLog, C_Container, C_Item) with fallbacks to the old globals.

local ADDON, ns = ...
local L = ns.L

local ITEM_CLASS_QUEST = 12 -- Enum.ItemClass.Questitem

-- Quest-class items that stay useful after their quest: dungeon keys, attunements,
-- raid summoning items. Never offered for deletion.
local PERMANENT = {
    [16309] = true, -- Drakefire Amulet (Onyxia's Lair)
    [12344] = true, -- Seal of Ascension (Upper Blackrock Spire)
    [17333] = true, -- Aqual Quintessence (Molten Core runes)
    [22754] = true, -- Eternal Quintessence
    [9240] = true,  -- Mallet of Zul'Farrak
    [17191] = true, -- Scepter of Celebras
    [11000] = true, -- Shadowforge Key
    [11140] = true, -- Prison Cell Key
    [18249] = true, -- Crescent Key
    [18250] = true, -- Gordok Shackle Key
    [18266] = true, -- Gordok Courtyard Key
    [18268] = true, -- Gordok Inner Door Key
    [13704] = true, -- Skeleton Key (Scholomance)
    [12382] = true, -- Key to the City (Stratholme)
    [7146] = true,  -- The Scarlet Key
    [5396] = true,  -- Key to Searing Gorge
    [6893] = true,  -- Workshop Key (Gnomeregan)
    [6948] = true,  -- Hearthstone
}

-- Generated from QuestieDB (Data.lua): which quests ask for each quest item, who can
-- still take them, and quest items that stay useful after their quest.
local function data()
    return ns.Data or { need = {}, quest = {}, keep = {}, itemStart = {}, chain = {}, class = {}, start = {}, giver = {} }
end

-- Account-wide: what to clean and what to protect, items the player kept.
local function db()
    GulliQuestCleanerDB = GulliQuestCleanerDB or {}
    local d = GulliQuestCleanerDB
    d.keep = d.keep or {}
    d.keepQuests = d.keepQuests or {} -- quest id -> title: quests the player unticked
    return d
end
ns.db = db

-- Per character: the level and the last cleaning. A character without a level takes the
-- one saved account-wide by older versions.
local function charDB()
    GulliQuestCleanerCharDB = GulliQuestCleanerCharDB or {}
    local c = GulliQuestCleanerCharDB
    if c.level == nil then c.level = db().level end
    return c
end
ns.charDB = charDB

function ns.Print(msg)
    print("|cff9ad0ffGulli-QuestCleaner|r: " .. msg)
end

---- Quests --------------------------------------------------------------------

local function numEntries()
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        return C_QuestLog.GetNumQuestLogEntries() or 0
    end
    return (GetNumQuestLogEntries()) or 0
end

local function entry(index)
    if C_QuestLog and C_QuestLog.GetInfo then
        local info = C_QuestLog.GetInfo(index)
        if not info then return nil end
        return info.title, info.level, info.isHeader, info.isHidden, info.questID, info.suggestedGroup
    end
    local title, level, group, isHeader, _, _, _, questID = GetQuestLogTitle(index)
    return title, level, isHeader, false, questID, tonumber(group)
end

-- "complete" when the objectives are done, "failed" when the quest failed, else nil.
local function questState(questID, index)
    if C_QuestLog and C_QuestLog.IsFailed and C_QuestLog.IsFailed(questID) then return "failed" end
    if C_QuestLog and C_QuestLog.IsComplete then
        if C_QuestLog.IsComplete(questID) then return "complete" end
        return nil
    end
    if GetQuestLogTitle then
        local c = select(7, GetQuestLogTitle(index))
        if c == 1 then return "complete" elseif c == -1 then return "failed" end
    end
end

-- Every quest in the log: { questID, title, level, index, zone, zoneOrder }. The zone is
-- the quest log header above the quest (in Vanilla content, the zone or a category).
function ns.Quests()
    local out = {}
    local zone, zoneOrder = nil, 0
    for i = 1, numEntries() do
        local title, level, isHeader, isHidden, questID, group = entry(i)
        if isHeader then
            zone, zoneOrder = title, zoneOrder + 1
        elseif title and not isHidden and questID and questID > 0 then
            out[#out + 1] = { questID = questID, title = title, level = level or 0, index = i,
                              zone = zone or "", zoneOrder = zoneOrder, group = group or 0,
                              state = questState(questID, i) }
        end
    end
    return out
end

-- The most quests the log holds.
function ns.MaxQuests()
    if C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept then
        return C_QuestLog.GetMaxNumQuestsCanAccept() or 20
    end
    return MAX_QUESTS or 20
end

-- tagID (Enum.QuestTag) and whether the quest is elite.
local function questTag(questID)
    if C_QuestLog and C_QuestLog.GetQuestTagInfo then
        local info = C_QuestLog.GetQuestTagInfo(questID)
        if info then return info.tagID, info.isElite end
    end
end

local TAG_GROUP, TAG_RAID, TAG_DUNGEON = 1, 62, 81
local TAG_RAID10, TAG_RAID25 = 88, 89

-- Why a quest is never planned, as a setting key, or nil. q is a quest of ns.Quests.
-- Group quests follow keepElite in saves from before keepGroup existed.
local function protectedBy(q)
    local d = db()
    local questID = q.questID
    if d.keepQuests[questID] then return "locked" end
    if d.keepComplete ~= false and q.state == "complete" then return "keepComplete" end
    if d.keepClass ~= false and data().class[questID] then return "keepClass" end
    local tag, elite = questTag(questID)
    if d.keepDungeon ~= false and (tag == TAG_DUNGEON or tag == TAG_RAID or tag == TAG_RAID10 or tag == TAG_RAID25) then
        return "keepDungeon"
    end
    if d.keepElite ~= false and elite then return "keepElite" end
    local keepGroup = d.keepGroup
    if keepGroup == nil then keepGroup = d.keepElite ~= false end
    if keepGroup and (tag == TAG_GROUP or (q.group or 0) > 1) then return "keepGroup" end
end
ns.ProtectedBy = protectedBy

-- The highest quest level that is green for the player: below yellow (two levels under
-- the player's own), above gray.
function ns.GreenLevel()
    return math.max(1, (UnitLevel("player") or 1) - 3)
end

-- The highest quest level that is gray (trivial) for the player.
function ns.GrayLevel()
    local level = UnitLevel("player") or 1
    local range = (UnitQuestTrivialLevelRange and UnitQuestTrivialLevelRange("player"))
        or (GetQuestGreenRange and GetQuestGreenRange())
    if range then return math.max(0, level - range - 1) end
    -- Vanilla's gray level when the client has neither call.
    if level <= 5 then return 0 end
    if level <= 39 then return level - 5 - math.floor(level / 10) end
    if level <= 59 then return level - 1 - math.floor(level / 5) end
    return level - 9
end

local function inLog(questID)
    for _, q in ipairs(ns.Quests()) do
        if q.questID == questID then return q end
    end
end

-- All text of a quest (objectives, summary, description), lowercased, to find the
-- items it asks for by name; plus the item ids of its usable quest item.
local function questNeeds(q, text, ids)
    if C_QuestLog and C_QuestLog.GetQuestObjectives then
        for _, o in ipairs(C_QuestLog.GetQuestObjectives(q.questID) or {}) do
            if o.text then text[#text + 1] = o.text end
        end
    end
    local prev = C_QuestLog and C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
    if C_QuestLog and C_QuestLog.SetSelectedQuest then
        C_QuestLog.SetSelectedQuest(q.questID)
    elseif SelectQuestLogEntry then
        SelectQuestLogEntry(q.index)
    end
    if GetQuestLogQuestText then
        local desc, objectives = GetQuestLogQuestText(q.index)
        text[#text + 1] = desc or ""
        text[#text + 1] = objectives or ""
    end
    if C_QuestLog and C_QuestLog.SetSelectedQuest then C_QuestLog.SetSelectedQuest(prev or 0) end
    if GetQuestLogSpecialItemInfo then
        local link = GetQuestLogSpecialItemInfo(q.index)
        local id = link and tonumber(link:match("item:(%d+)"))
        if id then ids[id] = true end
    end
end

local function needsOf(quests)
    local text, ids = {}, {}
    for _, q in ipairs(quests) do questNeeds(q, text, ids) end
    return table.concat(text, "\n"):lower(), ids
end

local function needed(item, blob, ids)
    if ids[item.itemID] then return true end
    return item.name ~= "" and blob:find(item.name:lower(), 1, true) ~= nil
end

---- Bags ----------------------------------------------------------------------

local function lastBag()
    return NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
end

local function slotInfo(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local i = C_Container.GetContainerItemInfo(bag, slot)
        if not i then return nil end
        return i.itemID, i.hyperlink, i.stackCount, i.isLocked, i.iconFileID, i.itemName
    end
    local icon, count, locked, _, _, _, link, _, _, id = GetContainerItemInfo(bag, slot)
    return id, link, count, locked, icon
end
ns.SlotInfo = slotInfo

local function numSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bag) or 0
    end
    return GetContainerNumSlots(bag) or 0
end

local function questInfo(bag, slot)
    if C_Container and C_Container.GetContainerItemQuestInfo then
        local q = C_Container.GetContainerItemQuestInfo(bag, slot)
        if q then return q.isQuestItem, q.questID, q.isActive end
        return
    end
    if GetContainerItemQuestInfo then return GetContainerItemQuestInfo(bag, slot) end
end

local function classOf(itemID)
    local getInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local _, _, _, _, _, classID = getInstant(itemID)
    return classID
end

local function questDone(questID)
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        return C_QuestLog.IsQuestFlaggedCompleted(questID)
    end
    return IsQuestFlaggedCompleted and IsQuestFlaggedCompleted(questID)
end

local function freeSlots()
    local free = 0
    for bag = 0, lastBag() do
        if C_Container and C_Container.GetContainerNumFreeSlots then
            free = free + (C_Container.GetContainerNumFreeSlots(bag) or 0)
        elseif GetContainerNumFreeSlots then
            free = free + (GetContainerNumFreeSlots(bag) or 0)
        end
    end
    return free
end
ns.FreeSlots = freeSlots

local function sellPrice(itemID)
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not getInfo then return 0 end
    return select(11, getInfo(itemID)) or 0
end

-- Whether bit `id` (1-based) is set in a race or class mask; 0 means everyone. Masks pass
-- 2^32 on Forever, past what bit.band takes, so this uses plain arithmetic.
local function hasBit(mask, id)
    if not mask or mask == 0 or not id then return true end
    return math.floor(mask / 2 ^ (id - 1)) % 2 == 1
end

-- A quest the player can still take: not done, not closed by a quest they did, and open
-- to their race, class and level.
local function canTake(questID)
    local q = data().quest[questID]
    if not q or questDone(questID) then return false end
    if not hasBit(q[2], select(3, UnitRace("player"))) then return false end
    if not hasBit(q[3], select(3, UnitClass("player"))) then return false end
    if q[4] > 0 and (UnitLevel("player") or 1) > q[4] then return false end
    for _, other in ipairs(q[5] or {}) do
        if questDone(other) then return false end
    end
    return true
end

-- The bank's containers while the bank is open: the bank tabs of the newer client, else
-- the old bank (-1) and its bag slots.
local function bankBags()
    if not ns.atBank then return {} end
    local B = Enum and Enum.BagIndex
    if B and B.CharacterBankTab_1 then
        local out = {}
        for i = 1, 6 do
            local b = B["CharacterBankTab_" .. i]
            if b then out[#out + 1] = b end
        end
        return out
    end
    local out = { BANK_CONTAINER or -1 }
    local first = (NUM_BAG_SLOTS or 4) + 1
    for b = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do out[#out + 1] = b end
    return out
end
ns.BankBags = bankBags

-- Quest items in the bags (and the bank while it is open):
-- { bag, slot, itemID, link, name, count, icon, starts, bank }.
local function bagQuestItems()
    local out = {}
    local bags, bank = {}, {}
    for bag = 0, lastBag() do bags[#bags + 1] = bag end
    for _, bag in ipairs(bankBags()) do bags[#bags + 1] = bag; bank[bag] = true end
    for _, bag in ipairs(bags) do
        for slot = 1, numSlots(bag) do
            local id, link, count, _, icon, name = slotInfo(bag, slot)
            if id then
                local isQuestItem, startsQuest = questInfo(bag, slot)
                if classOf(id) == ITEM_CLASS_QUEST or isQuestItem or startsQuest then
                    name = name or (link and link:match("%[(.-)%]")) or ""
                    out[#out + 1] = { bag = bag, slot = slot, itemID = id, link = link, name = name,
                                      count = count or 1, icon = icon, starts = startsQuest, bank = bank[bag] }
                end
            end
        end
    end
    return out
end

---- Plan ----------------------------------------------------------------------

-- Quests at or below maxLevel, except the kinds the player protects. A quest that an
-- item started is hard to take again, so it starts unticked; a quest in a chain gets a mark.
-- opts.zone keeps only the quests of that quest log zone. A failed quest is planned at any
-- level (unless the player locked it), since it cannot be finished.
function ns.PlanQuests(maxLevel, opts)
    opts = opts or {}
    local out = {}
    local D = data()
    local failed = db().offerFailed ~= false
    for _, q in ipairs(ns.Quests()) do
        local inZone = not opts.zone or q.zone == opts.zone
        local why = protectedBy(q)
        if inZone and failed and q.state == "failed" and why ~= "locked" then
            q.warn = "TAG_FAILED"
            q.checked = true
            out[#out + 1] = q
        elseif inZone and q.level > 0 and q.level <= maxLevel and not why then
            if D.itemStart[q.questID] then
                q.warn = "TAG_ITEM"
            elseif D.chain[q.questID] then
                q.warn = "TAG_CHAIN"
            end
            q.checked = q.warn ~= "TAG_ITEM"
            out[#out + 1] = q
        end
    end
    -- Zones in quest log order, then by level inside a zone.
    table.sort(out, function(a, b)
        if a.zoneOrder ~= b.zoneOrder then return a.zoneOrder < b.zoneOrder end
        if a.level ~= b.level then return a.level < b.level end
        return a.title < b.title
    end)
    return out
end

-- Where a quest starts: "NPC name (zone)", or nil when the data does not know.
function ns.WhereToTake(questID)
    local D = data()
    local g = D.start and D.giver and D.start[questID] and D.giver[D.start[questID]]
    if not g then return nil end
    local zone = g[2] and g[2] > 0 and C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(g[2])
    if zone and zone ~= "" then return L.WHERE:format(g[1], zone) end
    return g[1]
end

-- The planned quests grouped by zone, in plan order: { { name, quests = {...} }, ... }.
function ns.Zones(planned)
    local out, byName = {}, {}
    for _, q in ipairs(planned or {}) do
        local z = byName[q.zone]
        if not z then
            z = { name = q.zone, quests = {} }
            byName[q.zone] = z
            out[#out + 1] = z
        end
        z.quests[#z.quests + 1] = q
    end
    return out
end

-- Quest items that only the planned quests need, or no quest at all. Each item
-- lists the planned quests that need it (links). Quests outside the plan stay,
-- so their items are never offered. Items the player kept before stay out, and so do
-- items for a quest above maxLevel the player can still take. Returns the plan and
-- the items kept for such quests.
function ns.PlanItems(planned, maxLevel)
    if not maxLevel then
        maxLevel = 0
        for _, q in ipairs(planned or {}) do maxLevel = math.max(maxLevel, q.level) end
    end
    local D = data()
    local inPlan = {}
    for _, q in ipairs(planned or {}) do
        local text, ids = {}, {}
        questNeeds(q, text, ids)
        q.blob, q.ids = table.concat(text, "\n"):lower(), ids
        inPlan[q.questID] = true
    end
    local staying, logged = {}, {}
    for _, q in ipairs(ns.Quests()) do
        logged[q.questID] = true
        if not inPlan[q.questID] then staying[#staying + 1] = q end
    end
    -- What the data says about an item: a quest in the log that stays needs it, or a
    -- quest above the level still to take; else the planned quests that need it.
    local function fromData(it)
        local future
        for _, qid in ipairs(D.need[it.itemID] or {}) do
            if logged[qid] then
                if not inPlan[qid] then return "stays" end
            elseif not future then
                local q = D.quest[qid]
                if q and q[1] > maxLevel and canTake(qid) then future = qid end
            end
        end
        return future and "future"
    end
    local keepBlob, keepIds = needsOf(staying)
    local keep = db().keep

    local out, future = {}, {}
    for _, it in ipairs(bagQuestItems()) do
        local protected = GulliToolkit and GulliToolkit.IsProtected and GulliToolkit.IsProtected(it.itemID)
        if not PERMANENT[it.itemID] and not D.keep[it.itemID] and not keep[it.itemID] and not protected then
            it.links = {}
            local known = not it.starts and fromData(it)
            if known == "future" then
                future[#future + 1] = it
            elseif it.starts then
                if questDone(it.starts) then
                    it.why = "WHY_DONE"
                    out[#out + 1] = it
                end
            elseif not known and not needed(it, keepBlob, keepIds) then
                local wants = {}
                for _, qid in ipairs(D.need[it.itemID] or {}) do wants[qid] = true end
                for _, q in ipairs(planned or {}) do
                    if wants[q.questID] or needed(it, q.blob, q.ids) then it.links[#it.links + 1] = q end
                end
                it.why = #it.links > 0 and "WHY_ABANDONED" or "WHY_NO_QUEST"
                out[#out + 1] = it
            end
            it.checked = true
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out, future
end

-- An item goes only when the player ticked it and every quest it is for goes too.
function ns.ItemGoes(it)
    if not it.checked then return false end
    for _, q in ipairs(it.links or {}) do
        if not q.checked then return false end
    end
    return true
end

---- Run -----------------------------------------------------------------------

local function abandon(q)
    if C_QuestLog and C_QuestLog.SetAbandonQuest then
        C_QuestLog.SetSelectedQuest(q.questID)
        C_QuestLog.SetAbandonQuest()
        C_QuestLog.AbandonQuest()
    elseif AbandonQuest then
        local now = inLog(q.questID)
        if not now then return end
        SelectQuestLogEntry(now.index)
        SetAbandonQuest()
        AbandonQuest()
    end
end

local function useItem(bag, slot)
    if C_Container and C_Container.UseContainerItem then
        C_Container.UseContainerItem(bag, slot)
    else
        UseContainerItem(bag, slot)
    end
end

local function cursorItemID()
    local kind, id = GetCursorInfo()
    if kind == "item" then return id end
end

local function pickup(bag, slot)
    if C_Container and C_Container.PickupContainerItem then
        C_Container.PickupContainerItem(bag, slot)
    else
        PickupContainerItem(bag, slot)
    end
end

-- Runs from the OK click: the game lets an addon delete a picked-up item only
-- inside a hardware event. The game confirms a delete later, so the cursor can still
-- show the item right after DeleteCursorItem: never stop the run on that, clear the
-- cursor and go on to the next item. ns.Leftover tells afterwards what really went.
-- With a merchant open, an item that has a price is sold instead.
-- Returns the quests, the item stacks it tried to delete and the stacks it sold.
function ns.Run(quests, items)
    if InCombatLockdown() then
        ns.Print(L.IN_COMBAT)
        return 0, 0, 0
    end
    ClearCursor()
    local abandoned, deleted, sold = 0, 0, 0
    local last = { time = time and time() or 0, quests = {}, items = {} }
    for _, q in ipairs(quests or {}) do
        if q.checked and inLog(q.questID) then
            abandon(q)
            abandoned = abandoned + 1
            last.quests[#last.quests + 1] = q.title
            last.where = last.where or {}
            last.where[#last.quests] = ns.WhereToTake(q.questID)
        end
    end
    for _, it in ipairs(items or {}) do
        if ns.ItemGoes(it) then
            local id, _, _, locked = slotInfo(it.bag, it.slot)
            if id == it.itemID and not locked then
                last.items[#last.items + 1] = it.name
            end
            if id == it.itemID and not locked and ns.atMerchant and not it.bank and sellPrice(it.itemID) > 0 then
                useItem(it.bag, it.slot)
                sold = sold + 1
            elseif id == it.itemID and not locked then
                pickup(it.bag, it.slot)
                if cursorItemID() == it.itemID then
                    DeleteCursorItem()
                    deleted = deleted + 1
                end
                if GetCursorInfo() then ClearCursor() end
            end
        end
    end
    if #last.quests + #last.items > 0 then charDB().last = last end
    return abandoned, deleted, sold
end

-- What is still there of a plan after a run: ticked quests still in the log and
-- ticked items still in their slot.
function ns.Leftover(quests, items)
    local q2, i2 = {}, {}
    for _, q in ipairs(quests or {}) do
        if q.checked and inLog(q.questID) then q2[#q2 + 1] = q end
    end
    for _, it in ipairs(items or {}) do
        if ns.ItemGoes(it) and slotInfo(it.bag, it.slot) == it.itemID then i2[#i2 + 1] = it end
    end
    return q2, i2
end

---- Setup ---------------------------------------------------------------------

-- When the log is nearly full, say once in the chat how many old quests /gqc would
-- abandon. Only a hint: nothing goes without the window.
local hinted = false
local function logHint()
    local n, max = #ns.Quests(), ns.MaxQuests()
    if max - n > 2 then
        hinted = false
        return
    end
    local level = charDB().level
    if hinted or not level then return end
    local count = 0
    for _, q in ipairs(ns.PlanQuests(level)) do
        if q.checked then count = count + 1 end
    end
    if count > 0 then
        hinted = true
        ns.Print(L.LOG_FULL:format(n, max, count))
    end
end
ns.LogHint = logHint

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("MERCHANT_SHOW")
f:RegisterEvent("MERCHANT_CLOSED")
f:RegisterEvent("QUEST_ACCEPTED")
f:RegisterEvent("BANKFRAME_OPENED")
f:RegisterEvent("BANKFRAME_CLOSED")
f:RegisterEvent("QUEST_LOG_UPDATE")
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, name)
    if event == "BANKFRAME_OPENED" then
        ns.atBank = true
    elseif event == "BANKFRAME_CLOSED" then
        ns.atBank = false
    elseif event == "QUEST_LOG_UPDATE" or event == "BAG_UPDATE_DELAYED" then
        ns.verdicts = nil
    elseif event == "PLAYER_LOGIN" then
        ns.HookTooltip()
        ns.AddQuestLogButton()
        ns.ApplyKey()
    elseif event == "MERCHANT_SHOW" then
        ns.atMerchant = true
    elseif event == "MERCHANT_CLOSED" then
        ns.atMerchant = false
    elseif event == "QUEST_ACCEPTED" then
        logHint()
    elseif name == ADDON then
        f:UnregisterEvent("ADDON_LOADED")
        local d = db()
        if d.quests == nil then d.quests = true end
        if d.items == nil then d.items = true end
        charDB()
    end
end)

-- The last cleaning of this character, in the chat.
local function printLast()
    local last = charDB().last
    if not last then
        ns.Print(L.LAST_NONE)
        return
    end
    ns.Print(L.LAST:format(#last.quests, #last.items))
    for i, t in ipairs(last.quests) do
        local where = last.where and last.where[i]
        print("  " .. t .. (where and ("  |cff999999" .. L.TAKE_AGAIN:format(where) .. "|r") or ""))
    end
    for _, t in ipairs(last.items) do print("  " .. t) end
end

SLASH_GULLIQUESTCLEANER1 = "/gqc"
SLASH_GULLIQUESTCLEANER2 = "/questcleaner"
SlashCmdList.GULLIQUESTCLEANER = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "reset" then
        wipe(db().keep)
        wipe(db().keepQuests)
        ns.Print(L.KEEP_RESET)
    elseif msg == "zone" then
        ns.OpenForZone()
    elseif msg == "last" then
        printLast()
    elseif msg == "help" then
        ns.Print(L.HELP)
    else
        ns.Toggle()
    end
end

function GulliQuestCleaner_Toggle()
    ns.Toggle()
end

---- Tooltip -------------------------------------------------------------------

-- Why the cleaner keeps or offers a quest item, for its tooltip: { key, text } or nil for
-- an item that is not a quest item. Built once per quest log or bag change.
local function buildVerdicts()
    local D = data()
    local quests = ns.Quests()
    local logged = {}
    for _, q in ipairs(quests) do logged[q.questID] = q end
    local per = {}
    for _, q in ipairs(quests) do
        local text, ids = {}, {}
        questNeeds(q, text, ids)
        per[#per + 1] = { q = q, blob = table.concat(text, "\n"):lower(), ids = ids }
    end
    ns.verdicts = { per = per, logged = logged, D = D }
    return ns.verdicts
end

function ns.ItemVerdict(itemID, name)
    if not itemID then return nil end
    local starts
    local D = data()
    if classOf(itemID) ~= ITEM_CLASS_QUEST and not D.need[itemID] then return nil end
    local keep = db().keep
    local protected = GulliToolkit and GulliToolkit.IsProtected and GulliToolkit.IsProtected(itemID)
    if PERMANENT[itemID] or D.keep[itemID] or keep[itemID] or protected then return { "TT_KEPT" } end
    local v = ns.verdicts or buildVerdicts()
    for _, qid in ipairs(D.need[itemID] or {}) do
        if v.logged[qid] then return { "TT_NEEDED", v.logged[qid].title } end
    end
    local it = { itemID = itemID, name = name or "" }
    for _, e in ipairs(v.per) do
        if needed(it, e.blob, e.ids) then return { "TT_NEEDED", e.q.title } end
    end
    for _, qid in ipairs(D.need[itemID] or {}) do
        if canTake(qid) then
            local t = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(qid)
            return { "TT_LATER", t or ("#" .. qid) }
        end
    end
    return { "TT_OFFER" }
end

local function addVerdict(tt, itemID)
    if db().tooltip == false or not itemID then return end
    local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID))
        or (GetItemInfo and GetItemInfo(itemID))
    local v = ns.ItemVerdict(itemID, name)
    if not v then return end
    local text = v[2] and L[v[1]]:format(v[2]) or L[v[1]]
    local good = v[1] ~= "TT_OFFER"
    tt:AddLine("Quest Cleaner: " .. text, good and 0.42 or 1, good and 0.84 or 0.72, good and 0.5 or 0.3, true)
    tt:Show()
end

local hooked = false
function ns.HookTooltip()
    if hooked then return end
    hooked = true
    if TooltipDataProcessor and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, d)
            if d then addVerdict(tt, d.id) end
        end)
    elseif GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetItem", function(tt)
            local _, link = tt:GetItem()
            addVerdict(tt, link and tonumber(link:match("item:(%d+)")))
        end)
    end
end

---- Quest log button and key ---------------------------------------------------

-- Opens the window and plans only the quests of the zone the player is in.
function ns.OpenForZone(zone)
    ns.oneZone = zone or (GetRealZoneText and GetRealZoneText()) or nil
    local w = ns.Window()
    if not w:IsShown() then ns.Toggle() end
    if ns.Clear then ns.Clear() end
end

-- A small button on the game's quest log that opens the preview for this zone.
function ns.AddQuestLogButton()
    local parent = _G.QuestLogFrame or (_G.QuestMapFrame and _G.WorldMapFrame)
    if not parent or ns.logButton or not ns.Skin then return ns.logButton end
    local b = ns.Skin.FitButton(parent, L.LOG_BUTTON, 22, 60)
    b:SetFrameStrata("HIGH")
    if parent == _G.QuestLogFrame then
        b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -60, -16)
    else
        b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -70, -2)
    end
    b:SetScript("OnClick", function() ns.OpenForZone() end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L.LOG_BUTTON_TIP, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ns.logButton = b
    return b
end

-- The key that opens the window, through an override binding on a hidden button (an addon
-- may not add to the game's Key Bindings list without an XML file).
function ns.ApplyKey()
    if InCombatLockdown and InCombatLockdown() then return end
    if not ns.keyButton then
        ns.keyButton = CreateFrame("Button", "GulliQuestCleanerKey", UIParent)
        ns.keyButton:SetScript("OnClick", function() ns.Toggle() end)
    end
    if ClearOverrideBindings then ClearOverrideBindings(ns.keyButton) end
    local key = db().key
    if key and key ~= "" and SetOverrideBindingClick then
        SetOverrideBindingClick(ns.keyButton, true, key, "GulliQuestCleanerKey")
    end
end

-- In the Gulli Toolkit hub when it is installed; the addon works the same without it.
if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({
        key = "QuestCleaner",
        icon = "Interface\\AddOns\\Gulli-QuestCleaner\\icon",
        slash = "/gqc",
        open = function() ns.Toggle() end,
        window = function() return ns.Window and ns.Window() end,
        options = {
            { label = L.KEEP_COMPLETE, tip = L.KEEP_COMPLETE_D, icon = "Interface\\Icons\\INV_Misc_Book_09",
              get = function() return db().keepComplete ~= false end, set = function(v) db().keepComplete = v and true or false end },
            { label = L.OPT_TOOLTIP, tip = L.OPT_TOOLTIP_D, icon = "Interface\\Icons\\INV_Misc_Note_01",
              get = function() return db().tooltip ~= false end, set = function(v) db().tooltip = v and true or false end },
        },
        summary = function()
            local n, max = #ns.Quests(), ns.MaxQuests()
            if max - n > 2 then return nil end
            return L.SUM_FULL:format(n, max)
        end,
        reset = function()
            local d = db()
            for _, k in ipairs({ "quests", "items", "keepClass", "keepDungeon", "keepElite", "keepGroup",
                                 "keepComplete", "offerFailed", "zoneOnly", "tooltip" }) do d[k] = nil end
            d.quests, d.items = true, true
            if ns.ApplyTexts and ns.frameBuilt then ns.ApplyTexts() end
        end,
    })
end
