-- Chat without a keyboard: ready phrases on big buttons, a wheel and a small panel of
-- favourites, group messages from a quest or a WoW Forever dungeon, emotes and raid marks, and
-- the whispers that came while the player was fighting or away (with a busy auto-reply).

local ADDON, ns = ...
local L = ns.L

-- AUTO is raid, party or say; LEADER whispers the group leader.
ns.CHANNELS = { "AUTO", "SAY", "PARTY", "GUILD", "WHISPER", "LEADER" }
ns.ROLES = { "TANK", "HEALER", "DPS" }
ns.CATS = { "GROUP", "TRADE", "SOCIAL", "OWN" }
ns.DEFAULT_COUNT = 10
-- The category of each default phrase (P1..P10).
local DEFAULT_CAT = { "GROUP", "GROUP", "SOCIAL", "SOCIAL", "SOCIAL", "GROUP", "GROUP", "GROUP", "TRADE", "TRADE" }
-- The LookingForGroup channel in each client language.
local LFG_NAMES = { "LookingForGroup", "ПоискСпутников", "SucheNachGruppe", "BuscarGrupo", "RechercheGroupe",
                    "ProcurandoGrupo", "寻求组队", "尋求組隊" }

-- WoW Forever dungeons and raids for the group messages: key, area id (the game's own name; nil
-- for an area new in Forever, named by DG_<KEY> in Locales), English name, level range.
ns.DUNGEONS = {
    { "RFC", 2437, "Ragefire Chasm", 13, 18 }, { "WC", 718, "Wailing Caverns", 17, 24 },
    { "DM", 1581, "The Deadmines", 17, 26 }, { "SFK", 209, "Shadowfang Keep", 22, 30 },
    { "BFD", 719, "Blackfathom Deeps", 24, 32 }, { "STOCKS", 717, "The Stockade", 24, 32 },
    { "GNOMER", 721, "Gnomeregan", 29, 38 }, { "RFK", 491, "Razorfen Kraul", 30, 40 },
    { "SM", 796, "Scarlet Monastery", 34, 45 }, { "RFD", 722, "Razorfen Downs", 37, 46 },
    { "ULDA", 1337, "Uldaman", 41, 51 }, { "ZF", 1176, "Zul'Farrak", 44, 54 },
    { "MARA", 2100, "Maraudon", 46, 55 }, { "ST", 1417, "Sunken Temple", 50, 56 },
    { "BRD", 1584, "Blackrock Depths", 52, 60 }, { "LBRS", 1583, "Lower Blackrock Spire", 55, 60 },
    { "UBRS", 1583, "Upper Blackrock Spire", 58, 60 }, { "DIREMAUL", 2557, "Dire Maul", 56, 60 },
    { "SCHOLO", 2057, "Scholomance", 58, 60 }, { "STRAT", 2017, "Stratholme", 58, 60 },
    { "BARROW", nil, "Barrow Deeps", 60, 60 }, { "HYJAL", nil, "Hyjal Summit", 60, 60 },
    { "ONY", 2159, "Onyxia's Lair", 60, 60 },
}

-- Emotes on buttons (the game's emote tokens).
ns.EMOTES = { "WAVE", "THANK", "CHEER", "DANCE", "BOW", "HELLO", "BYE", "APPLAUD" }

local function secret(v) return issecretvalue and issecretvalue(v) end
local function notify(msg)
    if GulliToolkit and GulliToolkit.Notify then GulliToolkit.Notify("QuickChat", msg) end
end

---- Phrases ------------------------------------------------------------------------------------

-- The phrases: the player's own list, or the defaults of their language.
function ns.Phrases()
    if ns.db.phrases then return ns.db.phrases end
    local out = {}
    for i = 1, ns.DEFAULT_COUNT do out[i] = L["P" .. i] end
    return out
end

-- A phrase's category: the one the player set, the default one, or OWN.
function ns.Category(text)
    if ns.db.cat[text] then return ns.db.cat[text] end
    for i = 1, ns.DEFAULT_COUNT do if L["P" .. i] == text then return DEFAULT_CAT[i] end end
    return "OWN"
end

function ns.PhrasesIn(cat)
    if not cat or cat == "ALL" then return ns.Phrases() end
    local out = {}
    for _, p in ipairs(ns.Phrases()) do if ns.Category(p) == cat then out[#out + 1] = p end end
    return out
end

function ns.AddPhrase(text, cat)
    text = strtrim(text or "")
    if text == "" then return false end
    local list = ns.Phrases()
    local copy = {}
    for i, p in ipairs(list) do copy[i] = p end
    copy[#copy + 1] = text
    ns.db.phrases = copy
    if cat and cat ~= "ALL" then ns.db.cat[text] = cat end
    return true
end

function ns.RemovePhrase(i)
    local copy = {}
    for j, p in ipairs(ns.Phrases()) do if j ~= i then copy[#copy + 1] = p end end
    ns.db.phrases = copy
end

function ns.ResetPhrases()
    ns.db.phrases = nil
    wipe(ns.db.chan); wipe(ns.db.fav); wipe(ns.db.cat)
end

-- A phrase's own channel (nil: the window's channel), switched through nil and every channel.
function ns.CycleChannel(text)
    local cur = ns.db.chan[text]
    local nextCh
    if not cur then nextCh = ns.CHANNELS[1] else
        for i, ch in ipairs(ns.CHANNELS) do if ch == cur then nextCh = ns.CHANNELS[i + 1] end end
    end
    ns.db.chan[text] = nextCh
    return nextCh
end

function ns.ToggleFav(text)
    ns.db.fav[text] = (not ns.db.fav[text]) or nil
end

-- The wheel and the panel: the favourites, else the first phrases; at most n.
function ns.Favorites(n)
    n = n or 8
    local out = {}
    for _, p in ipairs(ns.Phrases()) do
        if ns.db.fav[p] then out[#out + 1] = p end
        if #out >= n then return out end
    end
    if #out == 0 then
        for i, p in ipairs(ns.Phrases()) do if i <= n then out[i] = p end end
    end
    return out
end

---- Filling and sending ------------------------------------------------------------------------

local function leaderName()
    if not (IsInGroup and IsInGroup()) then return nil end
    local raid = IsInRaid and IsInRaid()
    for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do
        local unit = (raid and "raid" or "party") .. i
        if UnitIsGroupLeader and UnitIsGroupLeader(unit) then return UnitName(unit) end
    end
end

-- {target}, {zone}, {me}, {level}, {targetclass}, {targetlevel}, {hp}, {mana}, {leader},
-- {item} (the item the player last Shift-clicked) and {quest} (the quest picked on Find group).
function ns.Fill(text)
    local target = UnitName("target")
    if secret(target) then target = nil end
    local tclass = target and UnitClass and UnitClass("target") or nil
    local tlevel = target and UnitLevel("target") or nil
    if secret(tlevel) then tlevel = nil end
    -- Health and power are secret values in combat: no percent then, never arithmetic on them.
    local function pct(cur, max)
        if secret(cur) or secret(max) then return "" end
        cur, max = cur or 0, max or 0
        if max <= 0 then return "" end
        return tostring(math.floor(cur / max * 100 + 0.5)) .. "%"
    end
    local values = {
        target = target or "", zone = (GetZoneText and GetZoneText()) or "",
        me = UnitName("player") or "", level = tostring(UnitLevel("player") or ""),
        targetclass = (not secret(tclass) and tclass) or "", targetlevel = tlevel and tostring(tlevel) or "",
        hp = pct(UnitHealth and UnitHealth("player"), UnitHealthMax and UnitHealthMax("player")),
        mana = pct(UnitPower and UnitPower("player", 0), UnitPowerMax and UnitPowerMax("player", 0)),
        leader = leaderName() or "", item = ns.lastLink or "", quest = ns.pickedQuest or "",
    }
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

-- The last 20 messages sent, for History and Repeat.
ns.HISTORY_MAX = 20
local function remember(text, kind, to)
    table.insert(ns.db.history, 1, { text = text, kind = kind, to = to, t = time() })
    while #ns.db.history > ns.HISTORY_MAX do table.remove(ns.db.history) end
end

-- A double tap sends a message once: the same text to the same place is held for 3 seconds.
ns.REPEAT_GAP = 3
local function tooSoon(key)
    local now = GetTime and GetTime() or time()
    if ns.lastSent and ns.lastSent.key == key and now - ns.lastSent.t < ns.REPEAT_GAP then return true end
    ns.lastSent = { key = key, t = now }
    return false
end

local function send(msg, kind, to)
    if tooSoon(kind .. "|" .. tostring(to) .. "|" .. msg) then return false end
    SendChatMessage(msg, kind, nil, to)
    remember(msg, kind, to)
    return true
end

-- Sends a phrase where it belongs: its own channel or the window's.
function ns.Say(text, channel)
    local msg = ns.Fill(text)
    if msg == "" then return false end
    channel = ns.Target(channel or ns.db.chan[text])
    if channel == "LEADER" then
        local who = leaderName()
        if not who then return false end
        return send(msg, "WHISPER", who)
    elseif channel == "WHISPER" then
        local who = UnitName("target")
        if not who or secret(who) or not UnitIsPlayer("target") then
            who = ns.lastWhisper
        end
        if not who then return false end
        return send(msg, "WHISPER", who)
    end
    return send(msg, channel)
end

function ns.Repeat(entry)
    if entry.kind == "CHANNEL" then return send(entry.text, "CHANNEL", entry.to) end
    return send(entry.text, entry.kind, entry.to)
end

function ns.Emote(token)
    if DoEmote then DoEmote(token) end
end

function ns.Mark(i)
    if SetRaidTarget and UnitExists and UnitExists("target") then SetRaidTarget("target", i) end
end

---- Group messages -----------------------------------------------------------------------------

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

function ns.DungeonName(key)
    for _, d in ipairs(ns.DUNGEONS) do
        if d[1] == key then
            local info = d[2] and C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(d[2])
            if type(info) == "string" and info ~= "" and key ~= "LBRS" and key ~= "UBRS" then return info end
            return (not d[2] and L["DG_" .. key]) or d[3]
        end
    end
    return key
end

-- The dungeons around the player's level first (the window starts on the first one).
function ns.DungeonsFor(level)
    local fit, rest, dist = {}, {}, {}
    for i, d in ipairs(ns.DUNGEONS) do
        local off = (level < d[4] and d[4] - level) or (level > d[5] and level - d[5]) or 0
        if off <= 3 then fit[#fit + 1] = d; dist[d] = off * 100 + i else rest[#rest + 1] = d[1] end
    end
    -- Inside the level range first, then the nearest; the list order breaks a tie.
    table.sort(fit, function(a, b) return dist[a] < dist[b] end)
    for i, d in ipairs(fit) do fit[i] = d[1] end
    for _, k in ipairs(rest) do fit[#fit + 1] = k end
    return fit
end

local function needText(roles)
    local need = {}
    for _, r in ipairs(ns.ROLES) do if roles[r] then need[#need + 1] = L["ROLE_" .. r] end end
    return need
end

-- "LFM 2 for <quest or dungeon>, need tank, healer". what: a quest, a dungeon key, or nil (zone).
function ns.LFM(what, count, roles)
    local name
    if type(what) == "table" then name = what.title
    elseif type(what) == "string" then name = ns.DungeonName(what)
    else name = (GetZoneText and GetZoneText()) or "" end
    local msg = L.LFM_TEXT:format(count, name)
    local need = needText(roles)
    if #need > 0 then msg = msg .. ", " .. L.NEED .. " " .. table.concat(need, ", ") end
    return msg
end

-- "LFG Stratholme, healer, level 58".
function ns.LFG(key, role)
    return L.LFG_TEXT:format(ns.DungeonName(key), L["ROLE_" .. (role or "DPS")], UnitLevel("player") or 0)
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

-- Posts in LookingForGroup; with the reminder on, says when it is fine to post again.
ns.REMIND_AFTER = 120
function ns.PostLFM(msg)
    if not send(msg, "CHANNEL", ns.LFGChannel()) then return false end
    ns.lastLFM = { text = msg, t = time() }
    if ns.db.remind and C_Timer then
        local stamp = ns.lastLFM.t
        C_Timer.After(ns.REMIND_AFTER, function()
            if ns.lastLFM and ns.lastLFM.t == stamp then
                print("|cff9ad0ffGulli Quick Chat|r: " .. L.REPOST)
                notify(L.REPOST)
                if ns.Refresh then ns.Refresh() end
            end
        end)
    end
    return true
end

---- Whispers ------------------------------------------------------------------------------------

-- Whispers kept while in combat or away; the newest first. Every whisper in and out also goes
-- into the history by player.
ns.missed = {}
ns.LOG_MAX = 100

local function logWhisper(who, text, out)
    if not ns.db.keepLog then return end
    table.insert(ns.db.log, 1, { who = who, short = who:match("^[^-]+") or who, text = text, out = out, t = time() })
    while #ns.db.log > ns.LOG_MAX do table.remove(ns.db.log) end
end

function ns.Whispered(msg, sender)
    if secret(msg) or secret(sender) or type(sender) ~= "string" then return end
    ns.lastWhisper = sender
    logWhisper(sender, msg, false)
    local busy = (InCombatLockdown and InCombatLockdown()) or (UnitIsAFK and UnitIsAFK("player")) or ns.db.always
    if not busy then
        if ns.Refresh then ns.Refresh() end
        return
    end
    local short = sender:match("^[^-]+") or sender
    table.insert(ns.missed, 1, { from = sender, short = short, text = msg, t = time() })
    while #ns.missed > 30 do table.remove(ns.missed) end
    if ns.db.sound and PlaySound then PlaySound((SOUNDKIT and SOUNDKIT.TELL_MESSAGE) or 3081) end
    notify(L.MISSED_FROM:format(short))
    ns.AutoBusy(sender)
    if ns.Refresh then ns.Refresh() end
end

function ns.SentWhisper(msg, to)
    if secret(msg) or secret(to) or type(to) ~= "string" then return end
    logWhisper(to, msg, true)
end

-- The busy answer goes once per player every busyMinutes, and only with the switch on.
ns.busySent = {}
function ns.AutoBusy(sender, now)
    if not ns.db.autoBusy then return false end
    now = now or time()
    local last = ns.busySent[sender]
    if last and now - last < ns.db.busyMinutes * 60 then return false end
    ns.busySent[sender] = now
    SendChatMessage(L.BUSY_TEXT, "WHISPER", nil, sender)
    return true
end

-- The log of one player, or of everyone.
function ns.Log(who)
    if not who then return ns.db.log end
    local out = {}
    for _, e in ipairs(ns.db.log) do if e.who == who then out[#out + 1] = e end end
    return out
end

function ns.Reply(entry)
    if ChatFrame_OpenChat then ChatFrame_OpenChat("/w " .. entry.from .. " ") end
end

-- Answers a whisper with a ready phrase.
function ns.ReplyWith(entry, text)
    local msg = ns.Fill(text)
    if msg == "" then return false end
    return send(msg, "WHISPER", entry.from)
end

function ns.Busy(entry)
    SendChatMessage(L.BUSY_TEXT, "WHISPER", nil, entry.from)
end

-- Own text: the chat box. ConsolePort's and PadChat's keyboards open with it when installed.
function ns.Type(prefix)
    if ChatFrame_OpenChat then ChatFrame_OpenChat(prefix or "") end
end

---- Setup --------------------------------------------------------------------------------------

ns.DEFAULTS = { channel = "AUTO", autoBusy = false, busyMinutes = 5, sound = true, remind = true, keepLog = true,
                always = false, wheelKey = nil, panelShow = false, panelLocked = false }

function ns.Defaults()
    for k, v in pairs(ns.DEFAULTS) do if ns.db[k] == nil then ns.db[k] = v end end
    for _, k in ipairs({ "chan", "fav", "cat" }) do ns.db[k] = ns.db[k] or {} end
    ns.db.history = ns.db.history or {}
    ns.db.log = ns.db.log or {}
end

function ns.ResetSettings()
    for k in pairs(ns.DEFAULTS) do ns.db[k] = nil end
    ns.db.panelPoint = nil
    ns.Defaults()
    if ns.ApplyKey then ns.ApplyKey() end
    if ns.Panel then ns.Panel() end
    if ns.Refresh then ns.Refresh() end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1, a2)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliQuickChatDB = GulliQuickChatDB or {}
        ns.db = GulliQuickChatDB
        ns.Defaults()
        self:RegisterEvent("CHAT_MSG_WHISPER")
        self:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        -- {item}: the last item link the player Shift-clicked.
        if hooksecurefunc and ChatEdit_InsertLink then
            hooksecurefunc("ChatEdit_InsertLink", function(link)
                if type(link) == "string" and link:find("|Hitem:") then ns.lastLink = link end
            end)
        end
        if ns.Setup then ns.Setup() end
        return
    end
    if event == "CHAT_MSG_WHISPER" then
        ns.Whispered(a1, a2)
    elseif event == "CHAT_MSG_WHISPER_INFORM" then
        ns.SentWhisper(a1, a2)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if ns.ApplyKey then ns.ApplyKey() end
    end
end)

SLASH_GULLIQUICKCHAT1 = "/gqk"
SLASH_GULLIQUICKCHAT2 = "/gulliquickchat"
SlashCmdList.GULLIQUICKCHAT = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "wheel" then
        if ns.ToggleWheel then ns.ToggleWheel() end
    else
        ns.Toggle()
    end
end

function GulliQuickChat_Toggle() ns.Toggle() end

-- Other Gulli modules call this: Bulletin's "My LFM" opens the group message for a dungeon.
GulliQuickChat = GulliQuickChat or {}
function GulliQuickChat.OpenLFM(key)
    if ns.OpenLFM then ns.OpenLFM(key) end
end

ns.OPT_ICON = {
    autoBusy = "Interface\\Icons\\INV_Letter_15",
    panelShow = "Interface\\Icons\\INV_Misc_Note_05",
    sound = "Interface\\Icons\\INV_Misc_Bell_01",
}

local function option(key, label, tip)
    return { label = label, icon = ns.OPT_ICON[key], tip = tip,
             get = function() return ns.db ~= nil and ns.db[key] == true end,
             set = function(on)
                 if not ns.db then return end
                 ns.db[key] = on and true or false
                 if key == "panelShow" and ns.Panel then ns.Panel() end
             end }
end

if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({
        key = "QuickChat",
        icon = "Interface\\AddOns\\Gulli-QuickChat\\icon",
        slash = "/gqk",
        open = function() ns.Toggle() end,
        window = function() return ns.Window and ns.Window() end,
        options = {
            option("panelShow", L.OPT_PANEL, L.TIP_PANEL),
            option("autoBusy", L.OPT_AUTOBUSY, L.TIP_AUTOBUSY),
            option("sound", L.OPT_SOUND),
        },
        -- The hub's home page: whispers missed in a fight or while away.
        summary = function()
            if #ns.missed == 0 then return nil end
            return L.SUM_MISSED:format(#ns.missed), "Interface\\Icons\\INV_Letter_15"
        end,
        move = function(on) if ns.MovePanel then ns.MovePanel(on) end end,
        reset = function() ns.ResetSettings() end,
    })
end
