-- Takes and hands in quests without the extra taps. It never picks a reward when there is a
-- choice (unless the player asks for the best vendor price), never pays gold to finish a
-- quest, and pauses with a key, a switch or for five minutes.

local ADDON, ns = ...
local L = ns.L

ns.DEFAULTS = {
    accept = true, turnIn = true, skipTrivial = true,
    shared = false,       -- accept quests a group member shares
    itemQuests = false,   -- hand in quests that take items other than quest items
    skipElite = false, skipDungeon = false, skipGroup = false,
    minFree = 0,          -- keep this many quest log places free (0: off)
    pickBest = false,     -- take the reward with the best vendor price
    targetKey = nil,      -- the key that targets a mob the quest log needs (none: off)
    mobRows = 3,          -- rows of the mob list under the quest mob button (0: none)
    gossip = true,        -- pick the only talk line of an NPC (a quest talk step)
    chat = false,         -- a chat line for each quest taken or handed in
    paused = false, pauseUntil = 0, pauseKey = "SHIFT",
}
ns.KEYS = { "SHIFT", "CTRL", "ALT", "NONE" }
ns.PAUSE_MINUTES = 5
local TAG_GROUP, TAG_RAID, TAG_DUNGEON, TAG_RAID10, TAG_RAID25 = 1, 62, 81, 88, 89
local QUEST_CLASS = 12

local function say(msg) print("|cff9ad0ffGulli AutoQuest|r: " .. msg) end
local function sellPrice(link)
    if not link then return 0 end
    return select(11, ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(link)) or 0
end
local function itemClass(link)
    local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not f or not link then return nil end
    return select(6, f(link))
end
-- The name of the player who shares the open quest, nil when an NPC offers it.
function ns.Sharer()
    if not UnitIsPlayer then return nil end
    local ok, isPlayer = pcall(UnitIsPlayer, "questnpc")
    if not ok or (issecretvalue and issecretvalue(isPlayer)) or not isPlayer then return nil end
    local name = UnitName("questnpc")
    if not name or (issecretvalue and issecretvalue(name)) then return nil end
    return name
end

-- Gulli Social may turn away quests strangers share; Auto Quest then never takes them.
function ns.SocialDeclines(name)
    return GulliSocial and GulliSocial.DeclinesShare and name and GulliSocial.DeclinesShare(name) or false
end

local function npcID()
    local guid = UnitGUID and UnitGUID("npc")
    if issecretvalue and issecretvalue(guid) then return nil end
    return guid and tonumber(guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
end
local function questTag(id)
    if id and C_QuestLog and C_QuestLog.GetQuestTagInfo then
        local info = C_QuestLog.GetQuestTagInfo(id)
        if info then return info.tagID, info.isElite end
    end
end
local function logFree()
    local Q = C_QuestLog or {}
    local _, n = (Q.GetNumQuestLogEntries or GetNumQuestLogEntries)()
    local max = (Q.GetMaxNumQuestsCanAccept and Q.GetMaxNumQuestsCanAccept()) or MAX_QUESTS or 20
    return max - (n or 0)
end
local function keyDown(key)
    if key == "SHIFT" then return IsShiftKeyDown and IsShiftKeyDown() end
    if key == "CTRL" then return IsControlKeyDown and IsControlKeyDown() end
    if key == "ALT" then return IsAltKeyDown and IsAltKeyDown() end
    return false
end

-- Why it waits now: "key", "switch", "timer" or nil.
function ns.Paused()
    local db = ns.db
    if keyDown(db.pauseKey) then return "key" end
    if db.paused then return "switch" end
    if (db.pauseUntil or 0) > time() then return "timer" end
end

function ns.SetPaused(on)
    ns.db.paused = on and true or false
    if not on then ns.db.pauseUntil = 0 end
    if ns.Refresh then ns.Refresh() end
end

function ns.PauseFor(minutes)
    ns.db.pauseUntil = time() + minutes * 60
    if ns.Refresh then ns.Refresh() end
end

-- Counters of this session, kept in the saved variables so a /reload does not lose them.
local function count(key, n)
    local s = ns.db.session
    s[key] = (s[key] or 0) + (n or 1)
    if ns.Refresh then ns.Refresh() end
end

-- One feed line after a quiet moment: "Taken 3, handed in 2".
local batch = { taken = 0, done = 0, waiting = false }
local function feed(kind, title)
    batch[kind] = batch[kind] + 1
    if ns.db.chat and title then say((kind == "taken" and L.TOOK or L.HANDED):format(title)) end
    if batch.waiting then return end
    batch.waiting = true
    C_Timer.After(10, function()
        batch.waiting = false
        if batch.taken + batch.done == 0 then return end
        local text = L.FEED:format(batch.taken, batch.done)
        batch.taken, batch.done = 0, 0
        if GulliToolkit and GulliToolkit.Notify then GulliToolkit.Notify("AutoQuest", text) end
    end)
end

-- Ignore list -------------------------------------------------------------------------------

ns.last = {} -- { npc = id, npcName, quest = id, questTitle, accepted = id, acceptedTitle }

function ns.IgnoreNpc(id, name)
    if not id then return false end
    ns.db.ignoreNpc[id] = name or tostring(id)
    if ns.Refresh then ns.Refresh() end
    return true
end
function ns.IgnoreQuest(id, title)
    if not id then return false end
    ns.db.ignoreQuest[id] = title or tostring(id)
    if ns.Refresh then ns.Refresh() end
    return true
end
function ns.Unignore(kind, id)
    ns.db[kind == "npc" and "ignoreNpc" or "ignoreQuest"][id] = nil
    if ns.Refresh then ns.Refresh() end
end

-- The ignore list for the window: { kind, id, name }, NPCs first.
function ns.Ignored()
    local out = {}
    for id, name in pairs(ns.db.ignoreNpc) do out[#out + 1] = { kind = "npc", id = id, name = name } end
    for id, name in pairs(ns.db.ignoreQuest) do out[#out + 1] = { kind = "quest", id = id, name = name } end
    table.sort(out, function(a, b)
        if a.kind ~= b.kind then return a.kind == "npc" end
        return tostring(a.name) < tostring(b.name)
    end)
    return out
end

-- Rules -------------------------------------------------------------------------------------

-- Quests at an NPC, the retail way (C_GossipInfo) with the old greeting as fallback:
-- { { kind = "active"|"available", ref, id, complete, trivial } }.
function ns.Offered(event)
    local out = {}
    if event == "GOSSIP_SHOW" and C_GossipInfo then
        for _, q in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
            out[#out + 1] = { kind = "active", ref = q.questID, id = q.questID, complete = q.isComplete }
        end
        for _, q in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
            out[#out + 1] = { kind = "available", ref = q.questID, id = q.questID, trivial = q.isTrivial }
        end
    elseif event == "QUEST_GREETING" then
        for i = 1, (GetNumActiveQuests and GetNumActiveQuests() or 0) do
            local _, complete = GetActiveTitle(i)
            out[#out + 1] = { kind = "active", ref = i, complete = complete }
        end
        for i = 1, (GetNumAvailableQuests and GetNumAvailableQuests() or 0) do
            local trivial = GetAvailableQuestInfo and GetAvailableQuestInfo(i)
            out[#out + 1] = { kind = "available", ref = i, trivial = trivial }
        end
    end
    return out
end

-- In a group with someone else: an escort or event quest (Events.lua) waits for the player,
-- since its NPC is busy for the others once one starts it.
local function withOthers()
    if IsInGroup and not IsInGroup() then return false end
    return ((GetNumGroupMembers and GetNumGroupMembers()) or (GetNumSubgroupMembers and GetNumSubgroupMembers() + 1) or 0) > 1
end

-- Why a new quest is not taken: a text key, or nil to take it. id may be nil (old greeting).
function ns.SkipNew(id, trivial, group)
    local db = ns.db
    if not db.accept then return "OFF" end
    if id and db.ignoreQuest[id] then return "WHY_IGNORED" end
    if id and ns.EVENT_QUESTS and ns.EVENT_QUESTS[id] and withOthers() then return "WHY_EVENT" end
    if db.skipTrivial and trivial then return "WHY_TRIVIAL" end
    if db.minFree > 0 and logFree() <= db.minFree then return "WHY_FULL" end
    local tag, elite = questTag(id)
    if db.skipDungeon and (tag == TAG_DUNGEON or tag == TAG_RAID or tag == TAG_RAID10 or tag == TAG_RAID25) then
        return "WHY_DUNGEON"
    end
    if db.skipElite and elite then return "WHY_ELITE" end
    if db.skipGroup and (tag == TAG_GROUP or (group or 0) > 1) then return "WHY_GROUP" end
end

-- What to open at an NPC: a finished quest first, then a new one. nil leaves the NPC alone.
function ns.Choose(offered)
    if ns.db.turnIn then
        for _, q in ipairs(offered) do
            if q.kind == "active" and q.complete and not (q.id and ns.db.ignoreQuest[q.id]) then return q end
        end
    end
    for _, q in ipairs(offered) do
        if q.kind == "available" and not ns.SkipNew(q.id, q.trivial) then return q end
    end
end

local function open(event, q)
    local G = event == "GOSSIP_SHOW" and C_GossipInfo
    if q.kind == "active" then
        if G then G.SelectActiveQuest(q.ref) else SelectActiveQuest(q.ref) end
    else
        if G then G.SelectAvailableQuest(q.ref) else SelectAvailableQuest(q.ref) end
    end
    count("clicks")
end

-- The reward with the best vendor price, to point at it when the player must choose.
function ns.BestChoice(n)
    local best, bestPrice, bestLink = nil, -1, nil
    for i = 1, n do
        local link = GetQuestItemLink("choice", i)
        local price = sellPrice(link)
        if price > bestPrice then best, bestPrice, bestLink = i, price, link end
    end
    return best, bestPrice, bestLink
end

-- The required items that are not quest items (cloth, ore...), as links.
function ns.TakesItems()
    local out = {}
    for i = 1, (GetNumQuestItems and GetNumQuestItems() or 0) do
        local link = GetQuestItemLink("required", i)
        local class = itemClass(link)
        if link and class and class ~= QUEST_CLASS then out[#out + 1] = link end
    end
    return out
end

-- A glow around the reward button with the best vendor price.
local glow
local function rewardButton(i)
    local f = QuestInfoRewardsFrame
    return (f and f.RewardButtons and f.RewardButtons[i]) or _G["QuestInfoRewardsFrameQuestInfoItem" .. i]
        or _G["QuestInfoItem" .. i]
end
function ns.MarkBest(i)
    local b = rewardButton(i)
    if not b then return end
    if not glow then
        glow = CreateFrame("Frame", nil, UIParent)
        glow.tex = glow:CreateTexture(nil, "OVERLAY")
        glow.tex:SetAllPoints()
        glow.tex:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        glow.tex:SetBlendMode("ADD")
        glow.tex:SetVertexColor(1, 0.82, 0.2, 1)
    end
    glow:SetParent(b)
    glow:ClearAllPoints()
    glow:SetPoint("TOPLEFT", b, "TOPLEFT", -14, 14)
    glow:SetPoint("BOTTOMRIGHT", b, "BOTTOMLEFT", 54, -14)
    glow:Show()
    return glow
end

local function detailID() return GetQuestID and GetQuestID() or nil end
local function detailTitle() return GetTitleText and GetTitleText() or nil end

-- The game's chat bubble (Interface\\GossipFrame\\GossipGossipIcon) and the newer chat bubble.
-- A vendor, flight master, trainer, bank, inn or battlemaster line has its own icon.
ns.TALK_ICONS = { [132053] = true, [1019848] = true }
ns.TALK_MAX = 12 -- talk lines picked at one NPC before the player clicks again
local QUEST_LABEL = 1 -- Enum.GossipOptionRecFlags.QuestLabelPrepend

-- Whether a gossip line is only talk: the chat bubble or a quest line, open, and no spell.
function ns.TalkLine(o)
    if type(o) ~= "table" then return false end
    if o.status and o.status ~= 0 then return false end
    if o.spellID then return false end
    if type(o.flags) == "number" and o.flags % 2 == QUEST_LABEL then return true end
    local icon = o.icon
    if type(icon) == "number" then return ns.TALK_ICONS[icon] == true end
    if type(icon) == "string" then
        icon = icon:lower()
        return icon:find("gossipgossipicon", 1, true) ~= nil or icon:find("chatbubble", 1, true) ~= nil
    end
    return false
end

ns.talk = { picks = 0 }
local function gossipOnly()
    if not ns.db.gossip or not C_GossipInfo or not C_GossipInfo.GetOptions then return end
    local opts = C_GossipInfo.GetOptions() or {}
    if #opts ~= 1 then return end
    local o = opts[1]
    if not ns.TalkLine(o) then return end
    local id = o.gossipOptionID or o.optionID
    local t = ns.talk
    -- A line that brings back the same line, or a talk that never ends, waits for the player.
    if t.picks >= ns.TALK_MAX or (id and id == t.last) then return end
    t.picks, t.last = t.picks + 1, id
    if C_GossipInfo.SelectOption then C_GossipInfo.SelectOption(id or 1) end
    count("clicks")
    return true
end

function ns.OnEvent(event, ...)
    local db = ns.db
    if event == "GOSSIP_CLOSED" then ns.talk = { picks = 0 }; return end
    if event == "GOSSIP_SHOW" or event == "QUEST_GREETING" then
        local npcName = UnitName and UnitName("npc")
        if issecretvalue and issecretvalue(npcName) then npcName = nil end
        ns.last.npc, ns.last.npcName = npcID(), npcName
        if ns.Refresh then ns.Refresh() end
    elseif event == "QUEST_DETAIL" or event == "QUEST_PROGRESS" or event == "QUEST_COMPLETE" then
        ns.last.quest, ns.last.questTitle = detailID(), detailTitle()
        if ns.Refresh then ns.Refresh() end
    end
    if event == "QUEST_ACCEPTED" then
        local a, b = ...
        local id = b or a -- classic sends (index, questID), retail (questID)
        if ns.pendingAccept and (id == ns.pendingAccept.id or not ns.pendingAccept.id) then
            ns.last.accepted, ns.last.acceptedTitle = id, ns.pendingAccept.title
            ns.pendingAccept = nil
            if ns.Refresh then ns.Refresh() end
        end
        return
    end
    if ns.Paused() then return end
    if ns.last.npc and db.ignoreNpc[ns.last.npc] and event ~= "QUEST_ACCEPT_CONFIRM" then return end
    if event == "GOSSIP_SHOW" or event == "QUEST_GREETING" then
        local offered = ns.Offered(event)
        local q = ns.Choose(offered)
        if q then open(event, q)
        elseif event == "GOSSIP_SHOW" and #offered == 0 then gossipOnly() end
    elseif event == "QUEST_DETAIL" then
        -- A quest a player shares: only with the switch, and never one Gulli Social turns away.
        local from = ns.Sharer()
        if from and (not db.shared or ns.SocialDeclines(from)) then return end
        local id = detailID()
        local why = ns.SkipNew(id, nil, GetSuggestedGroupNum and GetSuggestedGroupNum())
        if why then
            if why ~= "OFF" then say(L.SKIPPED:format(detailTitle() or "?", L[why])) end
            return
        end
        ns.pendingAccept = { id = id, title = detailTitle() }
        if QuestGetAutoAccept and QuestGetAutoAccept() then
            if AcknowledgeAutoAcceptQuest then AcknowledgeAutoAcceptQuest() end
        else
            AcceptQuest()
        end
        count("taken"); count("clicks")
        feed("taken", detailTitle())
    elseif event == "QUEST_ACCEPT_CONFIRM" then
        local starter = ...
        if db.accept and db.shared and ConfirmAcceptQuest and not ns.SocialDeclines(starter) then
            ConfirmAcceptQuest(); count("clicks")
        end
    elseif event == "QUEST_PROGRESS" then
        local id = detailID()
        if not db.turnIn or (id and db.ignoreQuest[id]) then return end
        if not IsQuestCompletable() or (GetQuestMoneyToGet and GetQuestMoneyToGet() or 0) > 0 then return end
        if not db.itemQuests then
            local items = ns.TakesItems()
            if #items > 0 then say(L.TAKES_ITEMS:format(items[1])); return end
        end
        CompleteQuest()
        count("clicks")
    elseif event == "QUEST_COMPLETE" then
        local id = detailID()
        if not db.turnIn or (id and db.ignoreQuest[id]) then return end
        local n = GetNumQuestChoices() or 0
        if n <= 1 then
            GetQuestReward(n)
        else
            local best, price, link = ns.BestChoice(n)
            if db.pickBest and best and price > 0 then
                GetQuestReward(best)
                say(L.PICKED:format(link))
            else
                if best and price > 0 then ns.MarkBest(best) end
                if link and price > 0 then say(L.CHOOSE:format(link)) else say(L.CHOOSE_ANY) end
                return
            end
        end
        count("done"); count("clicks")
        feed("done", detailTitle())
    end
end

-- Quest mob key ------------------------------------------------------------------------------

-- A key the player sets (targetKey) and the quest mob button click one secure button whose macro
-- targets a mob that a quest in the log still needs to kill; each row of the mob list under the
-- button clicks one of its own for one name (UI.lua sets them out of combat). Only names: the
-- game's /targetexact finds the mob, so it works at any range the game targets at.
ns.TARGET_MAX = 255 -- characters of the macro: a macro text longer than that may be cut by the game

local function escape(w) return (w:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")) end
local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- "Kobold Vermin slain: 3/10" or "3/10 Kobold Vermin slain" -> "Kobold Vermin". The words
-- around the name come from the client's own QUEST_MONSTERS_KILLED, so it works in every language.
function ns.MobName(text)
    if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return nil end
    local name = text:gsub("%d+%s*/%s*%d+", " "):gsub("[:：]", " ")
    local tpl = type(QUEST_MONSTERS_KILLED) == "string" and QUEST_MONSTERS_KILLED or "%s slain: %d/%d"
    tpl = tpl:gsub("%%%d*%$?[sd]", " "):gsub("[:：/]", " ")
    name = " " .. trim(name) .. " "
    for w in tpl:gmatch("%S+") do
        name = name:gsub("^%s*" .. escape(w) .. "%s", " "):gsub("%s" .. escape(w) .. "%s*$", " ")
    end
    name = trim(name)
    if name == "" or name:find("[\r\n]") then return nil end
    return name
end

local function count(o)
    local have, need = tonumber(o.numFulfilled), tonumber(o.numRequired)
    if not (have and need) and type(o.text) == "string" then
        local h, n = o.text:match("(%d+)%s*/%s*(%d+)")
        have, need = tonumber(h), tonumber(n)
    end
    return have or 0, need or 0
end

-- The row of ns.DROPS for an item objective: the one whose item the text names, else the k-th.
local function dropRow(rows, o, k)
    local name = C_Item and C_Item.GetItemNameByID
    for _, r in ipairs(name and rows or {}) do
        local ok, item = pcall(name, r[1])
        if ok and type(item) == "string" and item ~= "" and not (issecretvalue and issecretvalue(item))
            and type(o.text) == "string" and o.text:find(item, 1, true) then return r end
    end
    return rows[k]
end

-- Where the player is, by the data: true when the npc spawns in the zone named here (its area
-- ids of ns.NPC_AREAS, named by the client), false when it spawns only elsewhere, nil when nobody
-- can tell (no spawns in the data, or a client without C_Map.GetAreaInfo).
local areaNames = {}
local function areaName(a)
    if areaNames[a] == nil then
        local ok, name = pcall(C_Map.GetAreaInfo, a)
        areaNames[a] = ok and type(name) == "string" and name or false
    end
    return areaNames[a]
end

function ns.SpawnsHere(npc, here)
    local list = ns.NPC_AREAS and ns.NPC_AREAS[npc]
    if not list or not here or not (C_Map and C_Map.GetAreaInfo) then return nil end
    for _, a in ipairs(list) do
        if areaName(a) == here then return true end
    end
    return false
end

-- The droppers of an item to look for here: the ones that spawn here; for a quest of this zone's
-- header with none of them here, the ones nobody can place, else the first few (the quest zone's
-- come first in the data).
local function droppersHere(row, here, home)
    local out, unknown = {}, {}
    for j = 2, #row do
        local at = ns.SpawnsHere(row[j], here)
        if at then out[#out + 1] = row[j] elseif at == nil then unknown[#unknown + 1] = row[j] end
    end
    if #out > 0 or not home then return out end
    if #unknown > 0 then return unknown end
    for j = 2, math.min(#row, 6) do out[#out + 1] = row[j] end
    return out
end

-- The ns.KILLS row of a kill objective: the one with a mob of the text's name, else the k-th.
local function killRow(rows, name, k)
    for _, r in ipairs(rows or {}) do
        for _, id in ipairs(r) do
            if ns.CreatureName(id) == name then return r, true end
        end
    end
    return rows and rows[k], false
end

-- The mobs the quests still need where the player is: { { name, have, need, id, item }, ... },
-- the mobs to kill, then the mobs that drop an item to collect (ns.DROPS, with the item's count).
-- A quest counts under the quest log header of the player's zone (GetRealZoneText), and a quest of
-- another header too for the mobs of it that spawn here (Tanaris' Super Sticky in Un'Goro): the
-- key never reaches for a mob of a zone far away. A kill objective named by a group text ("Servants
-- of Grol Freed") looks for the mob the data names. A mob that two quests ask for is one entry.
-- The second value is true while a name is still asked from the client.
function ns.QuestMobList()
    local Q = C_QuestLog or {}
    if not Q.GetInfo or not Q.GetQuestObjectives then return {} end
    local here = GetRealZoneText and GetRealZoneText() or nil
    local near, seen, drops, pending = {}, {}, {}, false
    local ids = ns.db and ns.db.mobIds
    local function add(into, name, have, need, id, item)
        if seen[name] then return end
        seen[name] = true
        into[#into + 1] = { name = name, have = have, need = need, id = id or (ids and ids[name]), item = item }
        if id and ids and not ids[name] then ids[name] = id end
    end
    local zone
    local n = (Q.GetNumQuestLogEntries or GetNumQuestLogEntries)()
    for i = 1, n or 0 do
        local info = Q.GetInfo(i)
        if info and info.isHeader then
            zone = info.title
        elseif info and info.questID and not info.isHidden and here then
            local q, home = info.questID, zone == here
            local ki, k = 0, 0
            for _, o in ipairs(Q.GetQuestObjectives(q) or {}) do
                if o.type == "item" then k = k + 1 end
                if o.type == "monster" then ki = ki + 1 end
                if o.type == "monster" and not o.finished then
                    local name = ns.MobName(o.text)
                    local row, named = killRow(ns.KILLS and ns.KILLS[q], name, ki)
                    local have, need = count(o)
                    for _, id in ipairs(row or {}) do
                        local at = ns.SpawnsHere(id, here)
                        if at or home then
                            local real = named and name or ns.CreatureName(id)
                            if not real then pending = true; real = name end
                            if real then add(near, real, have, need, id) end
                        end
                    end
                    if not row and home and name then add(near, name, have, need) end
                elseif o.type == "item" and not o.finished and ns.DROPS and ns.DROPS[q] then
                    local row = dropRow(ns.DROPS[q], o, k)
                    local have, need = count(o)
                    for _, id in ipairs(row and droppersHere(row, here, home) or {}) do
                        local name = ns.CreatureName(id)
                        if not name then pending = true
                        else add(drops, name, have, need, id, row[1]) end
                    end
                end
            end
        end
    end
    for _, m in ipairs(drops) do near[#near + 1] = m end
    return near, pending
end

-- Only the names of ns.QuestMobList.
function ns.QuestMobs()
    local names = {}
    for i, m in ipairs(ns.QuestMobList()) do names[i] = m.name end
    return names
end

-- For other modules (Mob Finder): the quest mobs nearby as copies { name, have, need, item },
-- never the tables the button keeps.
GulliAutoQuest = GulliAutoQuest or {}
function GulliAutoQuest.QuestMobs()
    if not ns.db then return {} end
    local out = {}
    for i, m in ipairs(ns.QuestMobList()) do
        out[i] = { name = m.name, have = m.have, need = m.need, item = m.item }
    end
    return out
end

-- The macro for names, tried from names[first] on, round the list. Out of a fight it starts with
-- no target, so a target that is none of the names never stops it; in a fight the target stays
-- (clearing it would stop the attack). /targetexact takes the nearest of a name, a corpse too, so
-- a corpse is dropped at once, and each later name runs only while nothing is targeted: the first
-- living find wins. keep: no clear at the start, for a press while a living mob of names[first]
-- is the target: /targetexact then goes on to the next mob of that name. Names that do not fit
-- go from the end; the first one stays.
function ns.TargetMacro(names, first, keep)
    local n = #(names or {})
    if n == 0 then return nil end
    first = first or 1
    local lines, len = {}, -1
    if not keep then lines[1] = "/cleartarget [nocombat]"; len = #lines[1] end
    for k = 0, n - 1 do
        local name = names[(first - 1 + k) % n + 1]
        local cmd = (k == 0 and "/targetexact " or "/targetexact [noexists] ") .. name
        local add = 1 + #cmd + 1 + #"/cleartarget [dead]"
        if k > 0 and len + add > ns.TARGET_MAX then break end
        lines[#lines + 1] = cmd
        lines[#lines + 1] = "/cleartarget [dead]"
        len = len + add
    end
    return table.concat(lines, "\n")
end

local function readable(v)
    return v ~= nil and not (issecretvalue and issecretvalue(v))
end

-- The place in names of the target's name while the target is a living mob, else nil: then a
-- press goes on from it to the next mob of that name (ns.TargetMacro's keep).
function ns.CycleIndex(names)
    if not names or not (UnitExists and UnitExists("target")) then return nil end
    if UnitIsDead and UnitIsDead("target") then return nil end
    local ok, name = pcall(UnitName, "target")
    if not ok or not readable(name) then return nil end
    for i, n in ipairs(names) do
        if n == name then return i end
    end
    return nil
end

-- The npc id of a creature's GUID ("Creature-0-1-2-3-<id>-..."), else nil.
function ns.NpcId(guid)
    if type(guid) ~= "string" or (issecretvalue and issecretvalue(guid)) then return nil end
    local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
    return nil
end

-- What the player works on now: a kind whose count went up (a kill) or the mob fought when a
-- fight starts. ns.hot[name] = when; the mob list shows those kinds first, newest first.
ns.hot, ns.lastHave = {}, {}

function ns.NoteProgress(list, now)
    for _, m in ipairs(list) do
        local prev = ns.lastHave[m.name]
        if prev and m.have > prev then ns.hot[m.name] = now end
        ns.lastHave[m.name] = m.have
    end
end

-- The list in the order of the rows: the kinds worked on last first, then the log's order.
function ns.RowOrder(list)
    local out = {}
    for i, m in ipairs(list) do out[i] = { m = m, i = i } end
    table.sort(out, function(a, b)
        local ha, hb = ns.hot[a.m.name] or 0, ns.hot[b.m.name] or 0
        if ha ~= hb then return ha > hb end
        return a.i < b.i
    end)
    for i, e in ipairs(out) do out[i] = e.m end
    return out
end

-- The place of the kind the big button's next press tries first, among n kinds in ns.RowOrder:
-- a smooth weighted round robin where the kind at place r weighs 1/sqrt(r), so the top kinds (the
-- ones fought or killed last) come up more often and every kind still comes up in turn. With 19
-- kinds the first comes about every 7th press, the 19th about every 31st. Never the kind just
-- tried (now): the press after it goes to another kind.
ns.picks = {}
function ns.NextPick(n, now)
    if n < 2 then return 1 end
    local p = ns.picks
    if p.n ~= n then ns.picks = { n = n }; p = ns.picks end
    local best, total
    total = 0
    for r = 1, n do
        local w = 1 / math.sqrt(r)
        p[r] = (p[r] or 0) + w
        total = total + w
        if r ~= now and (not best or p[r] > p[best]) then best = r end
    end
    p[best] = p[best] - total
    return best
end

-- names[first] in front, then the others in their order: the macro's order for one press.
function ns.PressOrder(names, first)
    local out = { names[first] }
    for i, n in ipairs(names) do if i ~= first then out[#out + 1] = n end end
    return out
end

-- A creature's name in the client's language, from its link's tooltip; nil while the client
-- does not have it (asking makes it fetch the creature), false when the client cannot tell.
local known = {}
local function clientName(id)
    if known[id] then return known[id] end
    local get = C_TooltipInfo and C_TooltipInfo.GetHyperlink
    if not get then return false end
    local ok, data = pcall(get, ("unit:Creature-0-0-0-0-%d-0000000000"):format(id))
    local line = ok and type(data) == "table" and type(data.lines) == "table" and data.lines[1]
    local text = type(line) == "table" and line.leftText
    if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) or text == ""
        or text == UNKNOWNOBJECT or text == RETRIEVING_DATA then return nil end
    known[id] = text
    return text
end

-- Whether the client has a creature in its cache: a model drawn from an unknown one stays empty.
-- nil when the client cannot tell.
function ns.CreatureKnown(id)
    if not id then return false end
    local name = clientName(id)
    if name == false then return nil end
    return name ~= nil
end

-- The name /targetexact needs for an npc id: the client's own, else on an English client the
-- data's. nil while it is not known yet.
function ns.CreatureName(id)
    local name = clientName(id)
    if name then return name end
    local loc = GetLocale and GetLocale() or "enUS"
    if loc:sub(1, 2) == "en" and ns.NPC_NAME then return ns.NPC_NAME[id] end
    return nil
end

-- One line for the hub's home page, or nil.
function ns.Summary()
    if not ns.db then return nil end
    if ns.Paused() then return L.PAUSED, ns.OPT_ICON.paused end
    local s = ns.db.session
    if (s.taken or 0) + (s.done or 0) == 0 then return nil end
    return L.FEED:format(s.taken or 0, s.done or 0)
end

-- Every setting back to its default; the ignore lists and the counters stay.
function ns.Reset()
    for k, v in pairs(ns.DEFAULTS) do ns.db[k] = v end
    if ns.Refresh then ns.Refresh() end
end

-- Abandons the last quest this module took (undo), from a click.
function ns.Undo()
    local id = ns.last.accepted
    if not id or not C_QuestLog then return false end
    if C_QuestLog.SetSelectedQuest then C_QuestLog.SetSelectedQuest(id) end
    if C_QuestLog.SetAbandonQuest then C_QuestLog.SetAbandonQuest() end
    if C_QuestLog.AbandonQuest then C_QuestLog.AbandonQuest() end
    say(L.UNDONE:format(ns.last.acceptedTitle or tostring(id)))
    ns.last.accepted, ns.last.acceptedTitle = nil, nil
    if ns.Refresh then ns.Refresh() end
    return true
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1, ...)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliAutoQuestDB = GulliAutoQuestDB or {}
        ns.db = GulliAutoQuestDB
        for k, v in pairs(ns.DEFAULTS) do
            if ns.db[k] == nil then ns.db[k] = v end
        end
        ns.db.ignoreNpc = ns.db.ignoreNpc or {}
        ns.db.ignoreQuest = ns.db.ignoreQuest or {}
        ns.db.session = ns.db.session or {}
        ns.db.mobIds = ns.db.mobIds or {}
        -- 1.23.0 picks talk lines by default; older saves had the switch off by default.
        if not ns.db.talkOn then ns.db.gossip, ns.db.talkOn = true, true end
        for _, e in ipairs({ "GOSSIP_SHOW", "GOSSIP_CLOSED", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_ACCEPT_CONFIRM",
                             "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_ACCEPTED", "PLAYER_ENTERING_WORLD",
                             "PLAYER_LOGOUT" }) do
            self:RegisterEvent(e)
        end
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        -- Only leaving the game starts a new session; a /reload or a quick relog keeps it.
        if ns.Skin.NewSession(a1, select(1, ...), ns.db.seen) then ns.db.session = {} end
        return
    end
    if event == "PLAYER_LOGOUT" then
        ns.db.seen = time()
        return
    end
    if ns.paused then return end
    ns.OnEvent(event, a1, ...)
end)

SLASH_GULLIAUTOQUEST1 = "/gaq"
SLASH_GULLIAUTOQUEST2 = "/gulliautoquest"
SlashCmdList.GULLIAUTOQUEST = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "ignore" then
        if ns.IgnoreNpc(ns.last.npc, ns.last.npcName) then say(L.IGNORED:format(ns.last.npcName or "?"))
        else say(L.NO_NPC) end
    elseif msg == "pause" then
        ns.SetPaused(not ns.db.paused)
        say(ns.db.paused and L.PAUSED or L.RUNNING)
    else
        ns.Toggle()
    end
end

function GulliAutoQuest_Toggle() ns.Toggle() end

-- The same switches as in the window, so the Gulli Toolkit hub can show them.
-- The game icon of each switch, in the window and in the hub.
ns.OPT_ICON = {
    accept = "Interface\\Icons\\INV_Scroll_03",
    turnIn = "Interface\\Icons\\INV_Misc_Bag_10",
    skipTrivial = "Interface\\Icons\\Spell_ChargeNegative",
    paused = "Interface\\Icons\\Spell_Nature_TimeStop",
    shared = "Interface\\Icons\\INV_Letter_15",
    itemQuests = "Interface\\Icons\\INV_Fabric_Wool_01",
    skipElite = "Interface\\Icons\\Ability_Warrior_BattleShout",
    skipDungeon = "Interface\\Icons\\INV_Misc_Key_03",
    skipGroup = "Interface\\Icons\\Spell_Holy_PrayerOfHealing",
    minFree = "Interface\\Icons\\INV_Misc_Book_09",
    pickBest = "Interface\\Icons\\INV_Misc_Coin_02",
    gossip = "Interface\\Icons\\INV_Misc_Note_01",
    chat = "Interface\\Icons\\INV_Letter_02",
    targetKey = "Interface\\Icons\\Ability_Hunter_SniperShot",
}

local function option(key, label, tip)
    return { label = label, tip = tip, icon = ns.OPT_ICON[key], get = function() return ns.db ~= nil and ns.db[key] == true end,
             set = function(on)
                 if not ns.db then return end
                 if key == "paused" then ns.SetPaused(on) else ns.db[key] = on and true or false end
             end }
end

-- With the hub: its row and button there; alone: its own minimap button (Skin.lua).
do
    local register = GulliToolkit and GulliToolkit.Register or function(info) ns.alone = info end
    register({
        pause = function(on) ns.paused = on; if ns.ApplyTargetKey then ns.ApplyTargetKey() end end,
        move = function(on) if ns.MoveTarget then ns.MoveTarget(on) end end,
        frames = { { key = "target", label = ns.L.TARGET_BTN, icon = ns.OPT_ICON.targetKey,
                     get = function() return ns.db and ns.db.targetButton and true or false end,
                     set = function(on) if ns.SetTargetButton then ns.SetTargetButton(on) end end,
                     frame = function() return ns.TargetFrame and ns.TargetFrame() end } },
        key = "AutoQuest",
        icon = "Interface\\AddOns\\Gulli-AutoQuest\\icon",
        slash = "/gaq",
        open = function() ns.Toggle() end,
        window = function() return ns.Window and ns.Window() end,
        options = {
            option("paused", ns.L.OPT_PAUSED, ns.L.OPT_PAUSED_D),
            option("accept", ns.L.OPT_ACCEPT, ns.L.NOTE),
            option("turnIn", ns.L.OPT_TURNIN, ns.L.NOTE),
            option("skipTrivial", ns.L.OPT_TRIVIAL),
        },
        -- Rows on the hub's Tweaks page.
        tweaks = {
            { key = "gossip", group = "quests", label = ns.L.TWK_GOSSIP, desc = ns.L.TWK_GOSSIP_D,
              icon = "Interface\\Icons\\INV_Letter_02",
              get = function() return ns.db ~= nil and ns.db.gossip == true end,
              set = function(on) if ns.db then ns.db.gossip = on and true or false end end },
            { key = "quests", group = "quests", label = ns.L.TWK_QUESTS, desc = ns.L.TWK_QUESTS_D, tip = ns.L.NOTE,
              icon = "Interface\\Icons\\INV_Misc_Book_07", shift = true,
              get = function() return ns.db ~= nil and ns.db.accept == true and ns.db.turnIn == true end,
              set = function(on)
                  if not ns.db then return end
                  ns.db.accept, ns.db.turnIn = on and true or false, on and true or false
              end },
        },
        summary = function() return ns.Summary() end,
        reset = function() ns.Reset() end,
    })
end
