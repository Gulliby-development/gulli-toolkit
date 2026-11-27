-- Compares the quest logs of the group: which of my quests each member has, how far they
-- are, which they can get from me, and which quests only they have (when they run this
-- module too).

local ADDON, ns = ...
local L = ns.L

local PREFIX = "GulliPQ"
local STALE = 300      -- data older than this (seconds) is marked old
local HEARTBEAT = 120  -- while in a group, the list goes out this often
local SHARE_GAP = 1    -- seconds between two shares of Share all

-- sender -> { ids, done, obj = { [id] = { {have, need}, ... } }, turned, t }
ns.remote = {}
ns.turnedByShare = {} -- name -> { [questID] = true }, from the game's share replies

ns.DEFAULTS = {
    zoneOnly = true,      -- My quests: only the quests of the zone I am in
    autoShare = false,    -- share my quests with a member who joins
    track = true,         -- follow "track for all" from a member
    tooltip = true,       -- group progress in the tooltip of a mob or an item
    sound = true,
    nAccept = true, nObjective = false, nComplete = true, nTurnin = true, nAll = true,
    escort = true,        -- an escort or event quest in a group: who is ready before it starts
}

local function db()
    GulliPartyQuestsDB = GulliPartyQuestsDB or {}
    return GulliPartyQuestsDB
end
function ns.Get(key)
    local v = db()[key]
    if v == nil then return ns.DEFAULTS[key] end
    return v
end
function ns.Set(key, value)
    db()[key] = value
    if ns.Refresh then ns.Refresh() end
end

-- Game API wrappers: the C_ namespaces with a fallback to the old globals.
local Q = C_QuestLog or {}
local function numEntries() return (Q.GetNumQuestLogEntries or GetNumQuestLogEntries)() end
local function onQuest(unit, id) return Q.IsUnitOnQuest and Q.IsUnitOnQuest(unit, id) or false end
local function pushable(id) return Q.IsPushableQuest and Q.IsPushableQuest(id) or false end
local function complete(id) return Q.IsComplete and Q.IsComplete(id) or false end
local function questTitle(id)
    local t = Q.GetTitleForQuestID and Q.GetTitleForQuestID(id)
    return (t and t ~= "") and t or nil
end
local function loadQuest(id) if Q.RequestLoadQuestByID then Q.RequestLoadQuestByID(id) end end
local function turnedIn(id)
    local f = Q.IsQuestFlaggedCompleted or IsQuestFlaggedCompleted
    return f and f(id) or false
end
local function objectives(id)
    return (Q.GetQuestObjectives and Q.GetQuestObjectives(id)) or {}
end
local function watch(id)
    if Q.AddQuestWatch then Q.AddQuestWatch(id) elseif AddQuestWatch then AddQuestWatch(id) end
end
local function online(unit) return not UnitIsConnected or UnitIsConnected(unit) ~= false end
local function zoneName() return GetRealZoneText and GetRealZoneText() or nil end
local function sendAddon(msg, channel, target)
    local send = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
    if send then send(PREFIX, msg, channel, target) end
end
local CB = C_Container or {}
local function numSlots(b) return (CB.GetContainerNumSlots or GetContainerNumSlots or function() return 0 end)(b) end
local function slotItem(b, s)
    if CB.GetContainerItemInfo then
        local i = CB.GetContainerItemInfo(b, s)
        return i and i.itemID, i and i.stackCount
    end
    if GetContainerItemInfo then
        local _, count, _, _, _, _, link = GetContainerItemInfo(b, s)
        return link and tonumber(link:match("item:(%d+)")), count
    end
end
local function itemName(id)
    local n = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or (GetItemInfo and GetItemInfo(id))
    return n
end

local function short(name) return (name or ""):match("^[^-]+") or name end

local function members()
    local n = (GetNumSubgroupMembers and GetNumSubgroupMembers()) or 0
    local out = {}
    for i = 1, math.min(n, 4) do
        local unit = "party" .. i
        local name = UnitName(unit)
        if issecretvalue and issecretvalue(name) then name = nil end
        if name then
            local _, class = UnitClass(unit)
            out[#out + 1] = { unit = unit, name = name, class = class, level = UnitLevel(unit),
                              leader = UnitIsGroupLeader and UnitIsGroupLeader(unit) or false,
                              online = online(unit) }
        end
    end
    return out
end
ns.Members = members

local function remoteFor(name)
    return ns.remote[name] or ns.remote[short(name)]
end

-- How much we know about a member: "fresh" (the module answered lately), "stale" (it
-- answered, but long ago), "none" (no module) or "offline".
function ns.Status(m)
    if not m.online then return "offline" end
    local r = remoteFor(m.name)
    if not r then return "none" end
    if time() - (r.t or 0) > STALE then return "stale" end
    return "fresh"
end

-- "Wolf Pelt: 3/8" or "Defias Pillager slain: 3/8" -> "Wolf Pelt", "Defias Pillager".
local function objectiveName(text)
    local name = (text or ""):match("^(.-):%s*%d+%s*/%s*%d+") or text or ""
    name = name:gsub("%s+slain$", "")
    return name
end
ns.ObjectiveName = objectiveName

-- Objectives of one of my quests as { {have, need, text, item}, ... }.
function ns.MyObjectives(id)
    local out = {}
    for i, o in ipairs(objectives(id)) do
        local need = o.numRequired or 0
        local have = o.numFulfilled or 0
        if need == 0 then need, have = 1, o.finished and 1 or 0 end
        out[i] = { have = have, need = need, text = o.text, item = o.type == "item" }
    end
    return out
end

-- Quest items in the bags above what my objectives need: { [objective name] = extra }.
local function bagCounts()
    local counts = {}
    for b = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
        for s = 1, numSlots(b) do
            local id, count = slotItem(b, s)
            if id then
                local n = itemName(id)
                if n then counts[n] = (counts[n] or 0) + (count or 1) end
            end
        end
    end
    return counts
end
ns.BagCounts = bagCounts

-- My quests: { id, title, level, zone, pushable, done, group, obj, spare }, in quest log order.
function ns.MyQuests(withSpare)
    local out, zone = {}, nil
    local bags = withSpare and bagCounts() or nil
    for i = 1, numEntries() do
        local info = Q.GetInfo and Q.GetInfo(i)
        if info then
            if info.isHeader then
                zone = info.title
            elseif not info.isHidden and info.questID and info.questID > 0 then
                local q = { id = info.questID, title = info.title, level = info.level or 0, zone = zone,
                            pushable = pushable(info.questID), done = complete(info.questID),
                            group = (info.suggestedGroup or 0) > 1 }
                q.obj = ns.MyObjectives(q.id)
                if bags then
                    q.spare = 0
                    for _, o in ipairs(q.obj) do
                        local n = bags[objectiveName(o.text)]
                        if o.item and n and n > o.need then q.spare = q.spare + n - o.need end
                    end
                end
                out[#out + 1] = q
            end
        end
    end
    return out
end

local function sum(obj)
    if not obj or #obj == 0 then return nil end
    local have, need = 0, 0
    for _, o in ipairs(obj) do have = have + math.min(o[1] or o.have, o[2] or o.need); need = need + (o[2] or o.need) end
    return have, need
end
ns.Sum = sum

-- One member's state for one of my quests: { state, have, need }. States: "has", "done",
-- "no", "turned" (did it before, cannot take it again) and "unknown" (offline).
local function cell(m, id)
    if not m.online then return { state = "unknown" } end
    local r = remoteFor(m.name)
    local has = onQuest(m.unit, id)
    if not has then
        local by = ns.turnedByShare[short(m.name)]
        if (r and r.turned[id]) or (by and by[id]) then return { state = "turned" } end
        return { state = "no" }
    end
    local c = { state = "has" }
    if r then
        if r.done[id] then c.state = "done" end
        c.have, c.need = sum(r.obj[id])
    end
    return c
end

-- One row per quest of mine with a cell per member. Rows the whole group can do together
-- come first, then by how many have it. filter: { zone = name, text = "words" }.
function ns.Ours(filter)
    filter = filter or {}
    local party = members()
    local rows = {}
    local text = filter.text and filter.text ~= "" and filter.text:lower() or nil
    for i, q in ipairs(ns.MyQuests(true)) do
        local keep = (not filter.zone or q.zone == filter.zone)
            and (not text or (q.title or ""):lower():find(text, 1, true) ~= nil)
        if keep then
            local row = { quest = q, cells = {}, have = 1, order = i, missing = 0, done = q.done and 1 or 0 }
            row.mine = { state = q.done and "done" or "has" }
            row.mine.have, row.mine.need = sum(q.obj)
            for j, m in ipairs(party) do
                local c = cell(m, q.id)
                row.cells[j] = c
                if c.state == "has" or c.state == "done" then row.have = row.have + 1 end
                if c.state == "done" then row.done = row.done + 1 end
                if c.state == "no" then row.missing = row.missing + 1 end
            end
            row.canShare = q.pushable and row.missing > 0
            row.allDone = row.done == row.have and row.have == #party + 1
            rows[#rows + 1] = row
        end
    end
    table.sort(rows, function(a, b)
        if a.have ~= b.have then return a.have > b.have end
        return a.order < b.order
    end)
    return rows, party
end

-- The line above the table: the group is in sync, or what can be shared and handed in.
function ns.Summary(rows, party)
    if #party == 0 then return nil end
    local share, ready, apart = 0, 0, 0
    for _, r in ipairs(rows) do
        if r.canShare then share = share + 1 end
        if r.allDone then ready = ready + 1 end
        if r.have < #party + 1 then apart = apart + 1 end
    end
    if apart == 0 and share == 0 then
        return ready > 0 and L.SYNC_READY:format(ready) or L.SYNCED, true
    end
    return L.SUMMARY:format(share, ready), false
end

-- Quests members have that I do not, from their messages: { id, title, who = { names } }.
function ns.Theirs(filter)
    filter = filter or {}
    local text = filter.text and filter.text ~= "" and filter.text:lower() or nil
    local mine = {}
    for _, q in ipairs(ns.MyQuests()) do mine[q.id] = true end
    local found, list = {}, {}
    for _, m in ipairs(members()) do
        local r = remoteFor(m.name)
        if r then
            for id in pairs(r.ids) do
                if not mine[id] then
                    if not found[id] then
                        local t = questTitle(id)
                        if not t then loadQuest(id) end
                        found[id] = { id = id, title = t or L.QUEST_N:format(id), who = {}, turned = turnedIn(id) }
                        list[#list + 1] = found[id]
                    end
                    -- an older module sends no zones: the first member who names one wins
                    if r.zone and not found[id].zone then
                        found[id].zone, found[id].level = r.zone[id], r.level[id]
                    end
                    table.insert(found[id].who, m.name)
                end
            end
        end
    end
    local out = {}
    for _, item in ipairs(list) do
        if not text or item.title:lower():find(text, 1, true) then out[#out + 1] = item end
    end
    table.sort(out, function(a, b)
        if #a.who ~= #b.who then return #a.who > #b.who end
        return a.id < b.id
    end)
    return out
end

-- Every member's objectives for one of my quests, for the detail line under the table.
-- A list cut into zones for the window: a { head = true, zone, count, here } entry, then that
-- zone's entries. The zone the player is in comes first, entries without a zone last; the rest
-- by orderOf (the lowest of a zone's entries), else by name. zoneOf(item) names an entry's zone.
function ns.ByZone(items, zoneOf, orderOf)
    local here = zoneName()
    local groups, by = {}, {}
    for _, item in ipairs(items) do
        local z = zoneOf(item)
        if z == "" then z = nil end
        local g = by[z or 0]
        if not g then
            g = { zone = z, items = {} }
            by[z or 0] = g
            groups[#groups + 1] = g
        end
        g.items[#g.items + 1] = item
        local o = orderOf and orderOf(item)
        if o and (not g.order or o < g.order) then g.order = o end
    end
    local function rank(g) return (g.zone and g.zone == here) and 0 or (g.zone and 1 or 2) end
    table.sort(groups, function(a, b)
        if rank(a) ~= rank(b) then return rank(a) < rank(b) end
        if a.order and b.order and a.order ~= b.order then return a.order < b.order end
        return (a.zone or "") < (b.zone or "")
    end)
    local out = {}
    for _, g in ipairs(groups) do
        out[#out + 1] = { head = true, zone = g.zone, count = #g.items, here = g.zone ~= nil and g.zone == here }
        for _, item in ipairs(g.items) do out[#out + 1] = item end
    end
    return out
end

function ns.Detail(id)
    local out = {}
    for _, m in ipairs(members()) do
        local c = cell(m, id)
        local r = remoteFor(m.name)
        out[#out + 1] = { name = m.name, state = c.state, obj = r and r.obj[id], status = ns.Status(m) }
    end
    return out
end

-- My quest ids that members have turned in already, among the quests they have and I sent.
-- Ids of quests the members have that I turned in before: they go out as "C".
function ns.TurnedForOthers()
    local ids = {}
    for _, r in pairs(ns.remote) do
        for id in pairs(r.ids) do if turnedIn(id) then ids[id] = true end end
    end
    local list = {}
    for id in pairs(ids) do list[#list + 1] = id end
    table.sort(list)
    return list
end

-- The message format. A list goes out as "B", then parts that each fit 240 characters, then
-- "E". Parts: "Q" quest ids ("id*" when its objectives are done), "O" objectives
-- ("id:have/need.have/need"), "C" quest ids of the others that I turned in before. Old
-- versions read only "B", "Q" and "E" and skip the rest. Outside a list: "R<id>:<name>"
-- asks <name> to share a quest, "T<id>" asks everyone to track it. Never change a type; add one.
-- "Z<zone>|id:level,id:level" (since 1.13) names the zone and level of quests of the list.
-- "X<id>:<title>" (since 1.16) asks the group whether it is ready for an event quest,
-- "Y<id>:1" or "Y<id>:0" answers ready or not yet.
local ZONE_MAX = 60
local function pack(parts, kind, tokens, sep)
    local cur = kind
    for _, token in ipairs(tokens) do
        if #cur + #token + 1 > 240 then parts[#parts + 1] = cur; cur = kind end
        cur = cur .. (cur == kind and "" or sep) .. token
    end
    if cur ~= kind then parts[#parts + 1] = cur end
end

function ns.Encode(quests, turned)
    local parts = { "B" }
    local ids, objs = {}, {}
    for _, q in ipairs(quests) do
        ids[#ids + 1] = tostring(q.id) .. (q.done and "*" or "")
        if q.obj and #q.obj > 0 then
            local o = {}
            for i, x in ipairs(q.obj) do o[i] = math.min(x.have, x.need) .. "/" .. x.need end
            objs[#objs + 1] = q.id .. ":" .. table.concat(o, ".")
        end
    end
    pack(parts, "Q", ids, ",")
    pack(parts, "O", objs, ",")
    -- The zone (the quest log header) and level of each quest, one zone per part.
    local zones, byZone = {}, {}
    for _, q in ipairs(quests) do
        local z = q.zone
        if z and z ~= "" and #z <= ZONE_MAX and not z:find("|", 1, true) then
            if not byZone[z] then byZone[z] = {}; zones[#zones + 1] = z end
            table.insert(byZone[z], q.id .. ":" .. (q.level or 0))
        end
    end
    for _, z in ipairs(zones) do pack(parts, "Z" .. z .. "|", byZone[z], ",") end
    local c = {}
    for i, id in ipairs(turned or {}) do c[i] = tostring(id) end
    pack(parts, "C", c, ",")
    parts[#parts + 1] = "E"
    return parts
end

-- What changed for one member between two lists: { { kind, id } }. kinds: accept,
-- objective, complete, turnin.
function ns.Diff(old, new)
    local out = {}
    if not old then return out end
    for id in pairs(new.ids) do
        if not old.ids[id] then
            out[#out + 1] = { "accept", id }
        elseif new.done[id] and not old.done[id] then
            out[#out + 1] = { "complete", id }
        else
            local a, b = old.obj[id], new.obj[id]
            if a and b then
                for i, o in ipairs(b) do
                    local p = a[i]
                    if p and p[1] < p[2] and o[1] >= o[2] then out[#out + 1] = { "objective", id, i }; break end
                end
            end
        end
    end
    for id in pairs(old.ids) do
        if not new.ids[id] and old.done[id] then out[#out + 1] = { "turnin", id } end
    end
    table.sort(out, function(x, y) return x[2] < y[2] end)
    return out
end

local NOTIFY = { accept = "nAccept", objective = "nObjective", complete = "nComplete", turnin = "nTurnin", all = "nAll" }
local TEXT = { accept = "EV_ACCEPT", objective = "EV_OBJECTIVE", complete = "EV_COMPLETE", turnin = "EV_TURNIN" }
ns.allNotified = {}

local function say(kind, text)
    if not ns.Get(NOTIFY[kind]) then return end
    print("|cff9ad0ffParty Quests|r: " .. text)
    if GulliToolkit and GulliToolkit.Notify then GulliToolkit.Notify("PartyQuests", text) end
    if ns.Get("sound") and PlaySound then PlaySound(SOUNDKIT and SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01 or 567, "Master") end
end

local function titleOf(id) return questTitle(id) or L.QUEST_N:format(id) end

-- After a member's list arrives: one line per change, and "the whole group finished".
function ns.Announce(name, events)
    for _, e in ipairs(events) do
        say(e[1], L[TEXT[e[1]]]:format(name, titleOf(e[2])))
    end
    local rows, party = ns.Ours()
    if #party == 0 then return end
    for _, r in ipairs(rows) do
        local id = r.quest.id
        if r.allDone and not ns.allNotified[id] then
            ns.allNotified[id] = true
            say("all", L.EV_ALL:format(r.quest.title))
        elseif not r.allDone then
            ns.allNotified[id] = nil
        end
    end
end

local incoming = {}
function ns.Receive(msg, sender)
    if type(msg) ~= "string" or type(sender) ~= "string" then return end
    local who = short(sender)
    if who == UnitName("player") then return end
    local kind, rest = msg:sub(1, 1), msg:sub(2)
    local cur = incoming[who]
    if kind == "B" then
        incoming[who] = { ids = {}, done = {}, obj = {}, turned = {}, zone = {}, level = {} }
    elseif kind == "Q" and cur then
        for token in rest:gmatch("[^,]+") do
            local id, star = token:match("^(%d+)(%*?)$")
            id = tonumber(id)
            if id then
                cur.ids[id] = true
                if star == "*" then cur.done[id] = true end
            end
        end
    elseif kind == "O" and cur then
        for token in rest:gmatch("[^,]+") do
            local id, list = token:match("^(%d+):(.+)$")
            id = tonumber(id)
            if id then
                local obj = {}
                for a, b in list:gmatch("(%d+)/(%d+)") do obj[#obj + 1] = { tonumber(a), tonumber(b) } end
                cur.obj[id] = obj
            end
        end
    elseif kind == "C" and cur then
        for id in rest:gmatch("%d+") do cur.turned[tonumber(id)] = true end
    elseif kind == "Z" and cur then
        local zone, list = rest:match("^([^|]+)|(.*)$")
        if zone and #zone <= ZONE_MAX then
            for id, level in list:gmatch("(%d+):(%d+)") do
                id = tonumber(id)
                cur.zone[id] = zone
                cur.level[id] = tonumber(level)
            end
        end
    elseif kind == "E" and cur then
        cur.t = time()
        local old = ns.remote[who]
        ns.remote[who] = cur
        incoming[who] = nil
        local fresh = not old
        for id in pairs(cur.ids) do if not (old and old.ids[id]) then fresh = true end end
        -- New quests of theirs may be ones I did before: tell them.
        if fresh then ns.SoonBroadcast() end
        ns.Announce(who, ns.Diff(old, cur))
        if ns.Refresh then ns.Refresh() end
    elseif kind == "R" then
        local id, target = rest:match("^(%d+):(.+)$")
        if id and short(target) == UnitName("player") then ns.OnRequest(who, tonumber(id)) end
    elseif kind == "X" then
        local id, title = rest:match("^(%d+):(.*)$")
        if id then ns.OnEscortAsk(who, tonumber(id), title) end
    elseif kind == "Y" then
        local id, yes = rest:match("^(%d+):([01])$")
        if id then ns.OnEscortAnswer(who, tonumber(id), yes == "1") end
    elseif kind == "T" then
        local id = tonumber(rest)
        if id and ns.Get("track") then
            for _, q in ipairs(ns.MyQuests()) do if q.id == id then watch(id) end end
        end
    end
end

function ns.Broadcast()
    if #members() == 0 then return end
    for _, part in ipairs(ns.Encode(ns.MyQuests(), ns.TurnedForOthers())) do sendAddon(part, "PARTY") end
end

-- One broadcast at most every 3 seconds, however many quest updates come in.
local pending = false
function ns.SoonBroadcast()
    if pending then return end
    pending = true
    C_Timer.After(3, function() pending = false; ns.Broadcast() end)
end

-- Escort and event quests ----------------------------------------------------------------------

-- Once one player starts such a quest its NPC walks off or starts a scene, and a member who did
-- not have it yet is left out. ns.EVENT_QUESTS (Events.lua) lists them.
ns.escort = nil -- { id, title, answers = { [name] = true|false } }, the one I am about to start

function ns.IsEvent(id) return id ~= nil and ns.EVENT_QUESTS ~= nil and ns.EVENT_QUESTS[id] == true end

-- Who the group is waiting for: { ready = names, wait = names, lack = names, noAddon, allReady }.
-- Ready is a member who has the quest, did it before or said ready; wait said not yet; lack has
-- not answered and does not have it. noAddon counts the members in lack without this module.
function ns.EscortState(id)
    local st = { ready = {}, wait = {}, lack = {}, noAddon = 0 }
    local answers = ns.escort and ns.escort.id == id and ns.escort.answers or {}
    for _, m in ipairs(members()) do
        if m.online then
            local c = cell(m, id)
            local said = answers[short(m.name)]
            if c.state == "has" or c.state == "done" or c.state == "turned" or said == true then
                st.ready[#st.ready + 1] = m.name
            elseif said == false then
                st.wait[#st.wait + 1] = m.name
            else
                st.lack[#st.lack + 1] = m.name
                if ns.Status(m) == "none" then st.noAddon = st.noAddon + 1 end
            end
        end
    end
    st.allReady = #st.wait == 0 and #st.lack == 0
    return st
end

-- The quest page of an event quest opened while in a group: show who it waits for, unless
-- every member has it already. Returns the state when the card shows.
function ns.OnEventDetail(id, title)
    if not ns.Get("escort") or not ns.IsEvent(id) or #members() == 0 then return end
    if not (ns.escort and ns.escort.id == id) then ns.escort = { id = id, title = title or titleOf(id), answers = {} } end
    local st = ns.EscortState(id)
    if st.allReady and not next(ns.escort.answers) then ns.escort = nil; return end
    if ns.ShowEscort then ns.ShowEscort() end
    return st
end

-- Asks the group: the members with this module get a card, the others one line in the chat.
function ns.AskEscort()
    local e = ns.escort
    if not e then return end
    local title = (e.title or ""):gsub("[\r\n|]", ""):sub(1, 200)
    sendAddon("X" .. e.id .. ":" .. title, "PARTY")
    if ns.EscortState(e.id).noAddon > 0 and SendChatMessage then
        SendChatMessage(L.ESC_CHAT:format(title), "PARTY")
    end
    e.asked = true
end

function ns.AnswerEscort(id, yes)
    sendAddon("Y" .. id .. ":" .. (yes and "1" or "0"), "PARTY")
end

-- A member asks: with the quest in my log the answer is ready at once, else a card asks me.
ns.escortAsk = nil -- { from, id, title }
function ns.OnEscortAsk(from, id, title)
    for _, q in ipairs(ns.MyQuests()) do
        if q.id == id then ns.AnswerEscort(id, true); return "has" end
    end
    if title == nil or title == "" then title = titleOf(id) end
    ns.escortAsk = { from = from, id = id, title = title }
    if ns.ShowEscortAsk then ns.ShowEscortAsk() end
    return "asked"
end

function ns.OnEscortAnswer(from, id, yes)
    local e = ns.escort
    if not e or e.id ~= id then return end
    e.answers[short(from)] = yes and true or false
    if ns.ShowEscort then ns.ShowEscort() end
end

-- The card's two lines: who is ready, who still has to say or take it.
function ns.EscortText(st)
    if st.allReady then return L.ESC_ALL_READY end
    local parts = {}
    if #st.lack > 0 then parts[#parts + 1] = L.ESC_LACK:format(table.concat(st.lack, ", ")) end
    if #st.wait > 0 then parts[#parts + 1] = L.ESC_WAIT:format(table.concat(st.wait, ", ")) end
    if #st.ready > 0 then parts[#parts + 1] = L.ESC_READY:format(table.concat(st.ready, ", ")) end
    return table.concat(parts, "  ")
end

-- Sharing -------------------------------------------------------------------------------------

ns.lastShare = nil -- { id, title, t } for the game's reply
function ns.Share(id)
    if Q.SetSelectedQuest then Q.SetSelectedQuest(id) end
    if QuestLogPushQuest then QuestLogPushQuest() end
    ns.lastShare = { id = id, title = titleOf(id), t = time(), replies = {} }
end

-- Shares every quest someone lacks, one per second.
function ns.ShareAll()
    local ids = {}
    for _, r in ipairs(ns.Ours()) do if r.canShare then ids[#ids + 1] = r.quest.id end end
    local function step(i)
        if not ids[i] then return end
        ns.Share(ids[i])
        if ids[i + 1] then C_Timer.After(SHARE_GAP, function() step(i + 1) end) end
    end
    step(1)
    return #ids
end

-- The game's replies to a share, as patterns built from its own texts.
local SHARE_REPLIES = {
    { "ERR_QUEST_PUSH_SUCCESS_S", "sent" }, { "ERR_QUEST_PUSH_ACCEPTED_S", "accepted" },
    { "ERR_QUEST_PUSH_ALREADY_DONE_S", "turned" }, { "ERR_QUEST_PUSH_ONQUEST_S", "has" },
    { "ERR_QUEST_PUSH_LOW_LEVEL_S", "low" }, { "ERR_QUEST_PUSH_INVALID_S", "invalid" },
    { "ERR_QUEST_PUSH_LOG_FULL_S", "full" }, { "ERR_QUEST_PUSH_BUSY_S", "busy" },
    { "ERR_QUEST_PUSH_DECLINED_S", "declined" }, { "ERR_QUEST_PUSH_NOT_IN_PARTY_S", "invalid" },
}
local function toPattern(s)
    return "^" .. s:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)") .. "$"
end

-- Reads one system message; returns the member and what happened when it is a share reply.
function ns.ShareReply(msg)
    if type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then return end
    for _, r in ipairs(SHARE_REPLIES) do
        local g = _G[r[1]]
        if type(g) == "string" then
            local name = msg:match(toPattern(g))
            if name then
                name = short(name)
                if r[2] == "turned" and ns.lastShare then
                    ns.turnedByShare[name] = ns.turnedByShare[name] or {}
                    ns.turnedByShare[name][ns.lastShare.id] = true
                end
                if ns.lastShare then ns.lastShare.replies[name] = r[2] end
                return name, r[2]
            end
        end
    end
end

-- Requests -----------------------------------------------------------------------------------

-- Asks the member who has a quest to share it: through the module when they run it, else in
-- a whisper.
function ns.Request(id, title, owner)
    if remoteFor(owner) then
        sendAddon("R" .. id .. ":" .. short(owner), "PARTY")
        return "addon"
    end
    if SendChatMessage then SendChatMessage(L.ASK_TEXT:format(title), "WHISPER", nil, owner) end
    return "whisper"
end

-- The old Ask: one line in the group chat.
function ns.Ask(title)
    if SendChatMessage then SendChatMessage(L.ASK_TEXT:format(title), "PARTY") end
end

ns.requests = {} -- { { from, id, title } }, newest last
function ns.OnRequest(from, id)
    local title = titleOf(id)
    ns.requests[#ns.requests + 1] = { from = from, id = id, title = title }
    local text = L.REQUEST:format(from, title)
    print("|cff9ad0ffParty Quests|r: " .. text)
    if GulliToolkit and GulliToolkit.Notify then GulliToolkit.Notify("PartyQuests", text) end
    if ns.ShowRequest then ns.ShowRequest() end
end

function ns.TrackForAll(id)
    watch(id)
    if #members() > 0 then sendAddon("T" .. id, "PARTY") end
end

-- The tooltip: what the group has of a mob or an item that one of my quests asks for.
local function secret(v) return issecretvalue and issecretvalue(v) end

function ns.TooltipLines(name)
    if not name or secret(name) or type(name) ~= "string" or name == "" or not ns.Get("tooltip") then return {} end
    local party = members()
    if #party == 0 then return {} end
    local out = {}
    for _, q in ipairs(ns.MyQuests()) do
        for i, o in ipairs(q.obj) do
            if objectiveName(o.text) == name then
                for _, m in ipairs(party) do
                    local r = remoteFor(m.name)
                    local x = r and r.obj[q.id] and r.obj[q.id][i]
                    if x then
                        out[#out + 1] = { m.name, x[1] .. "/" .. x[2], x[1] >= x[2], m.class }
                    elseif onQuest(m.unit, q.id) then
                        out[#out + 1] = { m.name, "?", false, m.class }
                    end
                end
            end
        end
    end
    return out
end

-- The lines for the Gulli block (see S.TipCollect in the skin): each member in the class colour
-- under the quest, a finished count green with a check mark.
local QUEST_ICON, DONE_ICON = "Interface\\GossipFrame\\AvailableQuestIcon", "Interface\\RaidFrame\\ReadyCheck-Ready"
local function tipLines(name)
    local S = ns.Skin
    local out = {}
    for _, l in ipairs(ns.TooltipLines(name)) do
        local c = l[4] and RAID_CLASS_COLORS and RAID_CLASS_COLORS[l[4]]
        out[#out + 1] = { group = "quest", sub = true, icon = QUEST_ICON, left = l[1],
                          color = c and { c.r, c.g, c.b } or S.TEXT,
                          right = l[3] and (S.TipIcon(DONE_ICON) .. l[2]) or l[2], rcolor = l[3] and S.GOOD or S.TEXT }
    end
    return out
end
ns.TipLines = tipLines

-- The world cursor tooltip can carry a secret unit token or name (WoW 12): skip those.
function ns.UnitTip(unit)
    if not unit or secret(unit) or not UnitName then return {} end
    local okName, name = pcall(UnitName, unit)
    if okName and name and not secret(name) then return tipLines(name) end
    return {}
end

local function hookTooltip()
    local S = ns.Skin
    S.TipProvider("item", "PartyQuests", function(id) return tipLines(id and itemName(id)) end)
    S.TipProvider("unit", "PartyQuests", function(_, _, unit) return ns.UnitTip(unit) end)
end

-- Events -------------------------------------------------------------------------------------

local known = nil -- names in the group at the last roster update
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1, a2, a3, a4)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        db()
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
        for _, e in ipairs({ "CHAT_MSG_ADDON", "GROUP_ROSTER_UPDATE", "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED",
                             "CHAT_MSG_SYSTEM", "QUEST_DATA_LOAD_RESULT", "ZONE_CHANGED_NEW_AREA",
                             "QUEST_DETAIL", "QUEST_ACCEPTED" }) do
            self:RegisterEvent(e)
        end
        hookTooltip()
        if C_Timer.NewTicker then C_Timer.NewTicker(HEARTBEAT, function() ns.Broadcast() end) end
        return
    end
    if event == "CHAT_MSG_ADDON" then
        if a1 == PREFIX then ns.Receive(a2, a4) end
        return
    end
    if event == "QUEST_DETAIL" then
        local id = GetQuestID and GetQuestID()
        ns.OnEventDetail(id, GetTitleText and GetTitleText())
        return
    end
    if event == "QUEST_ACCEPTED" then
        local id = a2 or a1 -- classic sends (index, questID), retail (questID)
        if ns.escort and ns.escort.id == id then
            ns.escort = nil
            if ns.HideEscort then ns.HideEscort() end
        end
    end
    if event == "CHAT_MSG_SYSTEM" then
        if ns.ShareReply(a1) and ns.Refresh then ns.Refresh() end
        return
    end
    if event == "QUEST_DATA_LOAD_RESULT" or event == "ZONE_CHANGED_NEW_AREA" then
        if ns.Refresh then ns.Refresh() end
        return
    end
    if event == "GROUP_ROSTER_UPDATE" then
        local here, joined = {}, false
        for _, m in ipairs(members()) do
            here[m.name] = true
            if known and not known[m.name] then joined = true end
        end
        for name in pairs(ns.remote) do if not here[name] then ns.remote[name] = nil end end
        known = here
        if joined and ns.Get("autoShare") then C_Timer.After(3, function() ns.ShareAll() end) end
    end
    if event ~= "UNIT_QUEST_LOG_CHANGED" then ns.SoonBroadcast() end
    if ns.Refresh then ns.Refresh() end
end)

SLASH_GULLIPARTYQUESTS1 = "/gpq"
SLASH_GULLIPARTYQUESTS2 = "/gullipartyquests"
SlashCmdList.GULLIPARTYQUESTS = function(msg)
    if strtrim(msg or ""):lower() == "share" then
        print("|cff9ad0ffParty Quests|r: " .. L.SHARED_N:format(ns.ShareAll()))
        return
    end
    ns.Toggle()
end

function GulliPartyQuests_Toggle() ns.Toggle() end

ns.OPT_ICON = {
    autoShare = "Interface\\Icons\\INV_Letter_15",
    tooltip = "Interface\\Icons\\INV_Misc_Note_01",
    track = "Interface\\Icons\\INV_Misc_Spyglass_02",
    escort = "Interface\\Icons\\Ability_Warrior_RallyingCry",
}

-- With the hub: its row and button there; alone: its own minimap button (Skin.lua).
do
    local register = GulliToolkit and GulliToolkit.Register or function(info) ns.alone = info end
    register({
        key = "PartyQuests",
        icon = "Interface\\AddOns\\Gulli-PartyQuests\\icon",
        slash = "/gpq",
        open = function() ns.Toggle() end,
        window = function() return ns.Window and ns.Window() end,
        summary = function()
            local rows, party = ns.Ours()
            return (ns.Summary(rows, party))
        end,
        options = {
            { label = L.OPT_AUTOSHARE, icon = ns.OPT_ICON.autoShare,
              get = function() return ns.Get("autoShare") end, set = function(v) ns.Set("autoShare", v) end },
            { label = L.OPT_TOOLTIP, icon = ns.OPT_ICON.tooltip,
              get = function() return ns.Get("tooltip") end, set = function(v) ns.Set("tooltip", v) end },
        },
        -- Rows of the hub's Tweaks page, on the window's own saved keys.
        tweaks = {
            { key = "autoShare", group = "quests", label = L.OPT_AUTOSHARE, desc = L.OPT_AUTOSHARE_D,
              icon = ns.OPT_ICON.autoShare,
              get = function() return ns.Get("autoShare") end, set = function(v) ns.Set("autoShare", v and true or false) end },
            { key = "track", group = "quests", label = L.OPT_TRACK, desc = L.OPT_TRACK_D, icon = ns.OPT_ICON.track,
              get = function() return ns.Get("track") end, set = function(v) ns.Set("track", v and true or false) end },
        },
    })
end
