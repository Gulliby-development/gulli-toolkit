-- Compares the quest logs of the group: which of my quests each member has, which they
-- can get from me, and which quests only they have (when they run this module too).

local ADDON, ns = ...
local L = ns.L

local PREFIX = "GulliPQ"
ns.remote = {} -- sender -> { ids = { [questID] = true }, done = { [questID] = true }, t = time }

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
local function sendAddon(msg, channel)
    local send = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
    if send then send(PREFIX, msg, channel) end
end
local function members()
    local n = (GetNumSubgroupMembers and GetNumSubgroupMembers()) or 0
    local out = {}
    for i = 1, math.min(n, 4) do
        local unit = "party" .. i
        local name = UnitName(unit)
        if name then out[#out + 1] = { unit = unit, name = name } end
    end
    return out
end
ns.Members = members

-- My quests: { id, title, level, zone, pushable, done }, in quest log order.
function ns.MyQuests()
    local out, zone = {}, nil
    for i = 1, numEntries() do
        local info = Q.GetInfo and Q.GetInfo(i)
        if info then
            if info.isHeader then
                zone = info.title
            elseif not info.isHidden and info.questID and info.questID > 0 then
                out[#out + 1] = { id = info.questID, title = info.title, level = info.level or 0, zone = zone,
                                  pushable = pushable(info.questID), done = complete(info.questID),
                                  group = (info.suggestedGroup or 0) > 1 }
            end
        end
    end
    return out
end

local function remoteFor(name)
    return ns.remote[name] or ns.remote[(name or ""):match("^[^-]+") or ""]
end

-- One row per quest of mine with a cell per member: "has", "done" or "no".
-- Rows the whole group can do together come first, then by how many have it.
function ns.Ours()
    local party = members()
    local rows = {}
    for i, q in ipairs(ns.MyQuests()) do
        local row = { quest = q, cells = {}, have = 1, order = i }
        for j, m in ipairs(party) do
            local has = onQuest(m.unit, q.id)
            local r = remoteFor(m.name)
            local state = has and "has" or "no"
            if has and r and r.done[q.id] then state = "done" end
            row.cells[j] = state
            if has then row.have = row.have + 1 end
        end
        row.missing = #party + 1 - row.have
        row.canShare = q.pushable and row.missing > 0
        rows[#rows + 1] = row
    end
    table.sort(rows, function(a, b)
        if a.have ~= b.have then return a.have > b.have end
        return a.order < b.order
    end)
    return rows, party
end

-- Quests members have that I do not, from their messages: { id, title, who = { names } }.
function ns.Theirs()
    local mine = {}
    for _, q in ipairs(ns.MyQuests()) do mine[q.id] = true end
    local found, list = {}, {}
    for _, m in ipairs(members()) do
        local r = remoteFor(m.name)
        if r then
            for id in pairs(r.ids) do
                if not mine[id] then
                    if not found[id] then
                        found[id] = { id = id, title = questTitle(id) or L.QUEST_N:format(id), who = {} }
                        list[#list + 1] = found[id]
                    end
                    table.insert(found[id].who, m.name)
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if #a.who ~= #b.who then return #a.who > #b.who end
        return a.id < b.id
    end)
    return list
end

-- The message format: "Q" then quest ids, "id" or "id*" when its objectives are done, in
-- parts of at most 240 characters. "B" starts a new list, "E" ends it.
function ns.Encode(quests)
    local parts, cur = { "B" }, "Q"
    for _, q in ipairs(quests) do
        local token = tostring(q.id) .. (q.done and "*" or "")
        if #cur + #token + 1 > 240 then parts[#parts + 1] = cur; cur = "Q" end
        cur = cur .. (cur == "Q" and "" or ",") .. token
    end
    if cur ~= "Q" then parts[#parts + 1] = cur end
    parts[#parts + 1] = "E"
    return parts
end

local incoming = {}
function ns.Receive(msg, sender)
    if type(msg) ~= "string" or type(sender) ~= "string" then return end
    local short = sender:match("^[^-]+") or sender
    if short == UnitName("player") then return end
    local kind, rest = msg:sub(1, 1), msg:sub(2)
    if kind == "B" then
        incoming[short] = { ids = {}, done = {} }
    elseif kind == "Q" and incoming[short] then
        for token in rest:gmatch("[^,]+") do
            local id, star = token:match("^(%d+)(%*?)$")
            id = tonumber(id)
            if id then
                incoming[short].ids[id] = true
                if star == "*" then incoming[short].done[id] = true end
            end
        end
    elseif kind == "E" and incoming[short] then
        incoming[short].t = time()
        ns.remote[short] = incoming[short]
        incoming[short] = nil
        if ns.Refresh then ns.Refresh() end
    end
end

function ns.Broadcast()
    if #members() == 0 then return end
    for _, part in ipairs(ns.Encode(ns.MyQuests())) do sendAddon(part, "PARTY") end
end

-- One broadcast at most every 3 seconds, however many quest updates come in.
local pending = false
function ns.SoonBroadcast()
    if pending then return end
    pending = true
    C_Timer.After(3, function() pending = false; ns.Broadcast() end)
end

function ns.Share(id)
    if Q.SetSelectedQuest then Q.SetSelectedQuest(id) end
    if QuestLogPushQuest then QuestLogPushQuest() end
end

function ns.Ask(title)
    if SendChatMessage then SendChatMessage(L.ASK_TEXT:format(title), "PARTY") end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1, a2, a3, a4)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
        self:RegisterEvent("CHAT_MSG_ADDON")
        self:RegisterEvent("GROUP_ROSTER_UPDATE")
        self:RegisterEvent("QUEST_LOG_UPDATE")
        self:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
        return
    end
    if event == "CHAT_MSG_ADDON" then
        if a1 == PREFIX then ns.Receive(a2, a4) end
        return
    end
    if event == "GROUP_ROSTER_UPDATE" then
        local here = {}
        for _, m in ipairs(members()) do here[m.name] = true end
        for name in pairs(ns.remote) do if not here[name] then ns.remote[name] = nil end end
    end
    if event ~= "UNIT_QUEST_LOG_CHANGED" then ns.SoonBroadcast() end
    if ns.Refresh then ns.Refresh() end
end)

SLASH_GULLIPARTYQUESTS1 = "/gpq"
SLASH_GULLIPARTYQUESTS2 = "/gullipartyquests"
SlashCmdList.GULLIPARTYQUESTS = function() ns.Toggle() end

function GulliPartyQuests_Toggle() ns.Toggle() end

if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({
        key = "PartyQuests",
        icon = "Interface\\AddOns\\Gulli-PartyQuests\\icon",
        slash = "/gpq",
        open = function() ns.Toggle() end,
        window = function() return ns.Window and ns.Window() end,
    })
end
