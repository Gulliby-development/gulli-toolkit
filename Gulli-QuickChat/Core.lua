-- Chat without a keyboard: ready phrases on big buttons, a group message built from a quest,
-- and the whispers that came while the player was fighting or away.

local ADDON, ns = ...
local L = ns.L

ns.CHANNELS = { "AUTO", "SAY", "PARTY", "GUILD", "WHISPER" }
ns.ROLES = { "TANK", "HEALER", "DPS" }
-- The LookingForGroup channel in each client language.
local LFG_NAMES = { "LookingForGroup", "ПоискСпутников", "SucheNachGruppe", "BuscarGrupo", "RechercheGroupe",
                    "ProcurandoGrupo", "寻求组队", "尋求組隊" }

local function secret(v) return issecretvalue and issecretvalue(v) end

-- The phrases: the player's own list, or the defaults of their language.
function ns.Phrases()
    if ns.db.phrases then return ns.db.phrases end
    local out = {}
    for i = 1, 8 do out[i] = L["P" .. i] end
    return out
end

function ns.AddPhrase(text)
    text = strtrim(text or "")
    if text == "" then return false end
    local list = ns.Phrases()
    local copy = {}
    for i, p in ipairs(list) do copy[i] = p end
    copy[#copy + 1] = text
    ns.db.phrases = copy
    return true
end

function ns.RemovePhrase(i)
    local copy = {}
    for j, p in ipairs(ns.Phrases()) do if j ~= i then copy[#copy + 1] = p end end
    ns.db.phrases = copy
end

function ns.ResetPhrases() ns.db.phrases = nil end

-- {target}, {zone}, {me}, {level} in a phrase.
function ns.Fill(text)
    local target = UnitName("target")
    if secret(target) then target = nil end
    local values = { target = target or "", zone = (GetZoneText and GetZoneText()) or "",
                     me = UnitName("player") or "", level = tostring(UnitLevel("player") or "") }
    return (text:gsub("{(%a+)}", function(k) return values[k:lower()] end):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

-- Where a phrase goes: the chosen channel, or (AUTO) raid, party or say.
function ns.Target(channel)
    channel = channel or ns.db.channel
    if channel == "AUTO" then
        if IsInRaid and IsInRaid() then return "RAID" end
        if IsInGroup and IsInGroup() then return "PARTY" end
        return "SAY"
    end
    return channel
end

function ns.Say(text)
    local msg = ns.Fill(text)
    if msg == "" then return false end
    local channel = ns.Target()
    if channel == "WHISPER" then
        local who = UnitName("target")
        if not who or secret(who) or not UnitIsPlayer("target") then
            who = ns.lastWhisper
        end
        if not who then return false end
        SendChatMessage(msg, "WHISPER", nil, who)
    else
        SendChatMessage(msg, channel)
    end
    return true
end

-- Quests in the log, group quests first: { id, title, level }.
function ns.Quests()
    local Q = C_QuestLog or {}
    local group, rest = {}, {}
    for i = 1, (Q.GetNumQuestLogEntries and Q.GetNumQuestLogEntries() or 0) do
        local info = Q.GetInfo(i)
        if info and not info.isHeader and not info.isHidden and info.questID then
            local q = { id = info.questID, title = info.title, level = info.level or 0 }
            if (info.suggestedGroup or 0) > 1 then group[#group + 1] = q else rest[#rest + 1] = q end
        end
    end
    for _, q in ipairs(rest) do group[#group + 1] = q end
    return group
end

-- "LFM 2 for <quest> (<zone>), need tank, healer".
function ns.LFM(quest, count, roles)
    local need = {}
    for _, r in ipairs(ns.ROLES) do if roles[r] then need[#need + 1] = L["ROLE_" .. r] end end
    local what = quest and quest.title or ((GetZoneText and GetZoneText()) or "")
    local msg = L.LFM_TEXT:format(count, what)
    if #need > 0 then msg = msg .. ", " .. L.NEED .. " " .. table.concat(need, ", ") end
    return msg
end

-- The LookingForGroup channel the player is in, else General (1).
function ns.LFGChannel()
    local list = { GetChannelList() }
    for i = 1, #list, 3 do
        local id, name = list[i], list[i + 1]
        if type(name) == "string" then
            local n = name:gsub("%s", "")
            for _, want in ipairs(LFG_NAMES) do
                if n:find(want, 1, true) or n:lower():find(want:lower(), 1, true) then return id end
            end
        end
    end
    return 1
end

function ns.PostLFM(msg)
    SendChatMessage(msg, "CHANNEL", nil, ns.LFGChannel())
end

-- Whispers kept while in combat or away; the newest first.
ns.missed = {}
function ns.Whispered(msg, sender)
    if secret(msg) or secret(sender) or type(sender) ~= "string" then return end
    ns.lastWhisper = sender
    local busy = (InCombatLockdown and InCombatLockdown()) or (UnitIsAFK and UnitIsAFK("player")) or ns.db.always
    if not busy then return end
    table.insert(ns.missed, 1, { from = sender, short = sender:match("^[^-]+") or sender, text = msg, t = time() })
    while #ns.missed > 30 do table.remove(ns.missed) end
    if ns.Refresh then ns.Refresh() end
end

function ns.Reply(entry)
    if ChatFrame_OpenChat then ChatFrame_OpenChat("/w " .. entry.from .. " ") end
end

function ns.Busy(entry)
    SendChatMessage(L.BUSY_TEXT, "WHISPER", nil, entry.from)
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1, a2)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliQuickChatDB = GulliQuickChatDB or {}
        ns.db = GulliQuickChatDB
        ns.db.channel = ns.db.channel or "AUTO"
        self:RegisterEvent("CHAT_MSG_WHISPER")
        return
    end
    ns.Whispered(a1, a2)
end)

SLASH_GULLIQUICKCHAT1 = "/gqk"
SLASH_GULLIQUICKCHAT2 = "/gulliquickchat"
SlashCmdList.GULLIQUICKCHAT = function() ns.Toggle() end

function GulliQuickChat_Toggle() ns.Toggle() end

if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({
        key = "QuickChat",
        icon = "Interface\\AddOns\\Gulli-QuickChat\\icon",
        slash = "/gqk",
        open = function() ns.Toggle() end,
    })
end
