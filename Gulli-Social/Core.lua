-- Groups and strangers: invites a player who whispers the key word, accepts invites from
-- friends and the guild, and can turn away invites, duels, guild invites, trades and charters
-- from strangers, accept summons and resurrections, and hide spam whispers. Every rule has its
-- own switch. What it did goes into a Recent log.

local ADDON, ns = ...
local L = ns.L

local function secret(v) return issecretvalue and issecretvalue(v) end
local function say(msg) print("|cff9ad0ffGulli Social|r: " .. msg) end
local function short(name) return (name or ""):gsub("%-.*$", ""):lower() end
local function hide(which) if StaticPopup_Hide then StaticPopup_Hide(which) end end
local function inCombat() return InCombatLockdown and InCombatLockdown() end
local function notify(msg)
    if GulliToolkit and GulliToolkit.Notify then GulliToolkit.Notify("Social", msg) end
end

-- Comma lists of names (always allow, always turn away), by name without the realm.
function ns.NameSet(text)
    local out = {}
    for w in (text or ""):gmatch("[^,]+") do
        w = short(strtrim(w))
        if w ~= "" then out[w] = true end
    end
    return out
end

function ns.Listed(key, name)
    return ns.NameSet(ns.db[key])[short(name)] == true
end

-- Adds a name to the allow or deny list (and takes it off the other one).
function ns.AddTo(key, name)
    local other = key == "allow" and "deny" or "allow"
    local function without(text, n)
        local keep = {}
        for w in (text or ""):gmatch("[^,]+") do
            w = strtrim(w)
            if w ~= "" and short(w) ~= short(n) then keep[#keep + 1] = w end
        end
        return keep
    end
    local list = without(ns.db[key], name)
    list[#list + 1] = (name:gsub("%-.*$", ""))
    ns.db[key] = table.concat(list, ", ")
    ns.db[other] = table.concat(without(ns.db[other], name), ", ")
    if ns.Refresh then ns.Refresh() end
end

local function bnetFriend(want)
    local B = C_BattleNet
    if not (B and B.GetFriendNumGameAccounts and B.GetFriendGameAccountInfo) then return false end
    local n = (BNGetNumFriends and BNGetNumFriends()) or 0
    for i = 1, n do
        for j = 1, (B.GetFriendNumGameAccounts(i) or 0) do
            local g = B.GetFriendGameAccountInfo(i, j)
            if g and g.characterName and not secret(g.characterName) and short(g.characterName) == want then
                return true
            end
        end
    end
    return false
end

-- Friends, Battle.net friends (a switch), guild members and the allow list, by name without
-- the realm. A name on the deny list is never known.
function ns.Known(name)
    if not name or secret(name) then return false end
    local want = short(name)
    if ns.Listed("deny", want) then return false end
    if ns.Listed("allow", want) then return true end
    local F = C_FriendList
    for i = 1, (F and F.GetNumFriends and F.GetNumFriends() or 0) do
        local info = F.GetFriendInfoByIndex(i)
        if info and short(info.name) == want then return true end
    end
    if ns.db.bnet and bnetFriend(want) then return true end
    if IsInGuild and IsInGuild() and GetGuildRosterInfo then
        for i = 1, (GetNumGuildMembers and GetNumGuildMembers() or 0) do
            if short((GetGuildRosterInfo(i))) == want then return true end
        end
    end
    return false
end

---- The Recent log and today's count -------------------------------------------------------

ns.LOG_MAX = 20

function ns.Log(what, who)
    table.insert(ns.db.log, 1, { t = time(), what = what, who = who })
    while #ns.db.log > ns.LOG_MAX do table.remove(ns.db.log) end
    if ns.Refresh then ns.Refresh() end
end

local function today() return date and date("%Y%m%d") or "0" end

-- Counts what was turned away today: duels, invites, guild, trade, charters, spam.
function ns.Count(kind)
    local s = ns.db.stats
    if s.day ~= today() then wipe(s); s.day = today() end
    s[kind] = (s[kind] or 0) + 1
end

function ns.Today()
    local s = ns.db.stats
    if s.day ~= today() then return 0, {} end
    local n = 0
    for k, v in pairs(s) do if k ~= "day" then n = n + v end end
    return n, s
end

-- Turned something away: chat, the log, today's count and the hub's Recent feed.
local function away(kind, text, who)
    say(text)
    ns.Log(kind, who)
    ns.Count(kind)
    notify(text)
end

---- Invites ------------------------------------------------------------------------------------

-- Whether a whisper asks for an invite: the whole message is a key word, or (START) it begins
-- with one.
function ns.IsAsk(msg)
    if not msg or secret(msg) then return false end
    msg = strtrim(msg):lower()
    for word in (ns.db.words or ""):gmatch("[^,]+") do
        word = strtrim(word):lower()
        if word ~= "" then
            if msg == word then return true end
            if ns.db.match == "START" and msg:sub(1, #word + 1) == word .. " " then return true end
        end
    end
    return false
end

-- Whether the player can invite now: "ok", "full" (a full party and no raid switch),
-- "lead" (someone else leads) or "raid" (a full party that turns into a raid first).
function ns.InviteState()
    if IsInRaid and IsInRaid() then
        if UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") then
            return (GetNumGroupMembers() or 0) < 40 and "ok" or "full"
        end
        return "lead"
    end
    if IsInGroup and IsInGroup() then
        if not UnitIsGroupLeader("player") then return "lead" end
        if (GetNumGroupMembers() or 0) < 5 then return "ok" end
        return ns.db.toRaid and "raid" or "full"
    end
    return "ok"
end

local function reply(who, text)
    if ns.db.reply and SendChatMessage then SendChatMessage(text, "WHISPER", nil, who) end
end

function ns.OnWhisper(msg, sender)
    if not ns.db.invite or secret(sender) or not ns.IsAsk(msg) then return nil end
    if ns.Listed("deny", sender) then return nil end
    if ns.db.inviteKnown and not ns.Known(sender) then
        reply(sender, L.REPLY_KNOWN)
        return nil
    end
    local state = ns.InviteState()
    if state == "full" or state == "lead" then
        say(L.CANT_INVITE:format(sender))
        reply(sender, state == "full" and L.REPLY_FULL or L.REPLY_LEAD)
        return nil
    end
    if state == "raid" then
        local convert = (C_PartyInfo and C_PartyInfo.ConvertToRaid) or ConvertToRaid
        if convert then convert() end
        say(L.TO_RAID)
    end
    local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    invite(sender)
    say(L.INVITED:format(sender))
    ns.Log("invited", sender)
    return true
end

function ns.OnInvite(name)
    if ns.Listed("deny", name) then
        DeclineGroup()
        hide("PARTY_INVITE")
        away("invite", L.BLOCKED:format(name or "?"), name)
        return "decline"
    end
    if ns.Known(name) then
        if ns.db.acceptKnown then
            AcceptGroup()
            hide("PARTY_INVITE")
            say(L.ACCEPTED:format(name))
            ns.Log("joined", name)
            return "accept"
        end
        return nil
    end
    if ns.db.blockStrangers then
        DeclineGroup()
        hide("PARTY_INVITE")
        away("invite", L.BLOCKED:format(name or "?"), name)
        return "decline"
    end
end

---- Duels, guilds, trades, charters ---------------------------------------------------------

function ns.OnDuel(name)
    if not ns.db.noDuels or (ns.db.duelKnown and ns.Known(name)) then return nil end
    CancelDuel()
    hide("DUEL_REQUESTED")
    away("duel", L.NO_DUEL:format(name or "?"), name)
    return true
end

function ns.OnGuild(name)
    if not ns.db.noGuildInvites then return nil end
    DeclineGuild()
    hide("GUILD_INVITE")
    away("guild", L.NO_GUILD:format(name or "?"), name)
    return true
end

-- A trade window opened by a stranger closes at once.
function ns.OnTrade()
    if not ns.db.noTrade then return nil end
    local name = UnitName("NPC")
    if not name or secret(name) or ns.Known(name) then return nil end
    CancelTrade()
    away("trade", L.NO_TRADE:format(name), name)
    return true
end

-- A guild charter or arena petition from a stranger closes at once.
function ns.OnPetition()
    if not ns.db.noPetition or not GetPetitionInfo then return nil end
    local _, _, _, _, originator = GetPetitionInfo()
    if not originator or secret(originator) or ns.Known(originator) or short(originator) == short(UnitName("player")) then
        return nil
    end
    ClosePetition()
    away("petition", L.NO_PETITION:format(originator), originator)
    return true
end

---- Summons and resurrections ----------------------------------------------------------------

function ns.OnSummon()
    if not ns.db.summon or inCombat() then return nil end
    local S = C_SummonInfo
    local who = S and S.GetSummonConfirmSummoner and S.GetSummonConfirmSummoner()
    if S and S.ConfirmSummon then S.ConfirmSummon() elseif ConfirmSummon then ConfirmSummon() end
    hide("CONFIRM_SUMMON")
    say(L.SUMMONED:format(who or "?"))
    ns.Log("summon", who)
    return true
end

function ns.OnResurrect(name)
    if not ns.db.res or inCombat() then return nil end
    AcceptResurrect()
    hide("RESURRECT"); hide("RESURRECT_NO_SICKNESS"); hide("RESURRECT_NO_TIMER")
    say(L.RESSED:format(name or "?"))
    ns.Log("res", name)
    return true
end

---- Spam whispers ------------------------------------------------------------------------------

-- Words of gold sellers and scams; a whisper from a stranger with one of them is hidden.
ns.SPAM = { "www", "http", ".com", ".net", "%d+%s*g%s*=", "gold", "cheap", "discount", "boost", "powerlevel",
            "золото", "дешево", "дёшево", "金币" }

function ns.IsSpam(msg, sender)
    if not ns.db.spam or secret(msg) or secret(sender) or type(msg) ~= "string" then return false end
    if ns.Known(sender) then return false end
    local low = msg:lower()
    for _, p in ipairs(ns.SPAM) do
        if low:find(p, 1, not p:find("%%")) then return true end
    end
    return false
end

local function spamFilter(_, _, msg, sender)
    if ns.db and not ns.paused and ns.IsSpam(msg, sender) then
        if ns.lastSpam ~= sender then
            ns.lastSpam = sender
            ns.Log("spam", sender)
            ns.Count("spam")
        end
        return true
    end
    return false
end

---- Setup ------------------------------------------------------------------------------------

ns.DEFAULTS = { invite = true, words = "inv, invite, 123", match = "WHOLE", inviteKnown = false, acceptKnown = true,
                bnet = true, reply = true, toRaid = false, blockStrangers = false, noDuels = false,
                duelKnown = true, noGuildInvites = false, noTrade = false, noPetition = false, summon = false,
                res = false, spam = false, allow = "", deny = "" }

function ns.Defaults()
    for k, v in pairs(ns.DEFAULTS) do if ns.db[k] == nil then ns.db[k] = v end end
    ns.db.log = ns.db.log or {}
    ns.db.stats = ns.db.stats or {}
end

function ns.ResetSettings()
    for k in pairs(ns.DEFAULTS) do ns.db[k] = nil end
    ns.Defaults()
    if ns.Refresh then ns.Refresh() end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1, a2)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliSocialDB = GulliSocialDB or {}
        ns.db = GulliSocialDB
        ns.Defaults()
        for _, e in ipairs({ "CHAT_MSG_WHISPER", "PARTY_INVITE_REQUEST", "DUEL_REQUESTED", "GUILD_INVITE_REQUEST",
                             "TRADE_SHOW", "PETITION_SHOW", "CONFIRM_SUMMON", "RESURRECT_REQUEST" }) do
            self:RegisterEvent(e)
        end
        if ChatFrame_AddMessageEventFilter then ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", spamFilter) end
        return
    end
    if ns.paused then return end
    if event == "CHAT_MSG_WHISPER" then
        ns.OnWhisper(a1, a2)
    elseif event == "PARTY_INVITE_REQUEST" then
        ns.OnInvite(a1)
    elseif event == "DUEL_REQUESTED" then
        ns.OnDuel(a1)
    elseif event == "GUILD_INVITE_REQUEST" then
        ns.OnGuild(a1)
    elseif event == "TRADE_SHOW" then
        ns.OnTrade()
    elseif event == "PETITION_SHOW" then
        ns.OnPetition()
    elseif event == "CONFIRM_SUMMON" then
        ns.OnSummon()
    elseif event == "RESURRECT_REQUEST" then
        ns.OnResurrect(a1)
    end
end)

SLASH_GULLISOCIAL1 = "/gso"
SLASH_GULLISOCIAL2 = "/gullisocial"
SlashCmdList.GULLISOCIAL = function() ns.Toggle() end

function GulliSocial_Toggle() ns.Toggle() end

-- The same switches as in the window, so the Gulli Toolkit hub can show them.
-- The game icon of each switch, in the window and in the hub.
ns.OPT_ICON = {
    invite = "Interface\\Icons\\INV_Letter_02",
    inviteKnown = "Interface\\Icons\\Spell_Holy_SealOfSalvation",
    acceptKnown = "Interface\\Icons\\Spell_Holy_PrayerOfHealing02",
    blockStrangers = "Interface\\Icons\\Ability_Warrior_ShieldWall",
    noDuels = "Interface\\Icons\\Ability_DualWield",
    noGuildInvites = "Interface\\Icons\\INV_Shirt_GuildTabard_01",
    bnet = "Interface\\Icons\\INV_Misc_GroupNeedMore",
    reply = "Interface\\Icons\\INV_Letter_15",
    toRaid = "Interface\\Icons\\INV_Misc_GroupLooking",
    noTrade = "Interface\\Icons\\INV_Misc_Coin_01",
    noPetition = "Interface\\Icons\\INV_Misc_Note_06",
    summon = "Interface\\Icons\\Spell_Shadow_Twilight",
    res = "Interface\\Icons\\Spell_Holy_Resurrection",
    spam = "Interface\\Icons\\Spell_Holy_Silence",
    duelKnown = "Interface\\Icons\\Ability_Warrior_Challange",
}

local function option(key, label, tip)
    return { label = label, icon = ns.OPT_ICON[key], tip = tip,
             get = function() return ns.db ~= nil and ns.db[key] == true end,
             set = function(on) if ns.db then ns.db[key] = on and true or false end end }
end

if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({
        pause = function(on) ns.paused = on end,
        key = "Social",
        icon = "Interface\\AddOns\\Gulli-Social\\icon",
        slash = "/gso",
        open = function() ns.Toggle() end,
        window = function() return ns.Window and ns.Window() end,
        options = {
            option("invite", L.OPT_INVITE, L.TIP_INVITE),
            option("acceptKnown", L.OPT_ACCEPT_KNOWN, L.TIP_ACCEPT),
            option("blockStrangers", L.OPT_BLOCK, L.TIP_BLOCK),
            option("noDuels", L.OPT_DUELS),
            option("noTrade", L.OPT_TRADE),
            option("spam", L.OPT_SPAM, L.TIP_SPAM),
        },
        -- The hub's home page: what was turned away today.
        summary = function()
            if not ns.db then return nil end
            local n = ns.Today()
            if n == 0 then return nil end
            return L.SUM_TODAY:format(n), "Interface\\Icons\\Ability_Warrior_ShieldWall"
        end,
        reset = function() ns.ResetSettings() end,
    })
end
