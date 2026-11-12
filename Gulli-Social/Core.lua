-- Groups and strangers: invites a player who whispers the key word, accepts invites from
-- friends and the guild, and can turn away invites from strangers, duels and guild invites.
-- Every rule has its own switch.

local ADDON, ns = ...
local L = ns.L

local function secret(v) return issecretvalue and issecretvalue(v) end
local function say(msg) print("|cff9ad0ffGulli Social|r: " .. msg) end
local function short(name) return (name or ""):gsub("%-.*$", ""):lower() end
local function hide(which) if StaticPopup_Hide then StaticPopup_Hide(which) end end

-- Friends and guild members, by name without the realm.
function ns.Known(name)
    if not name or secret(name) then return false end
    local want = short(name)
    local F = C_FriendList
    for i = 1, (F and F.GetNumFriends and F.GetNumFriends() or 0) do
        local info = F.GetFriendInfoByIndex(i)
        if info and short(info.name) == want then return true end
    end
    if IsInGuild and IsInGuild() then
        for i = 1, (GetNumGuildMembers and GetNumGuildMembers() or 0) do
            if short((GetGuildRosterInfo(i))) == want then return true end
        end
    end
    return false
end

-- Whether a whisper asks for an invite: the whole message is one of the key words.
function ns.IsAsk(msg)
    if not msg or secret(msg) then return false end
    msg = strtrim(msg):lower()
    for word in (ns.db.words or ""):gmatch("[^,]+") do
        if msg == strtrim(word):lower() then return true end
    end
    return false
end

local function canInvite()
    if IsInRaid and IsInRaid() then return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") end
    if IsInGroup and IsInGroup() then
        return UnitIsGroupLeader("player") and (GetNumGroupMembers() or 0) < 5
    end
    return true
end

function ns.OnWhisper(msg, sender)
    if not ns.db.invite or not ns.IsAsk(msg) or secret(sender) then return nil end
    if ns.db.inviteKnown and not ns.Known(sender) then return nil end
    if not canInvite() then say(L.CANT_INVITE:format(sender)); return nil end
    local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    invite(sender)
    say(L.INVITED:format(sender))
    return true
end

function ns.OnInvite(name)
    if ns.Known(name) then
        if ns.db.acceptKnown then
            AcceptGroup()
            hide("PARTY_INVITE")
            say(L.ACCEPTED:format(name))
            return "accept"
        end
        return nil
    end
    if ns.db.blockStrangers then
        DeclineGroup()
        hide("PARTY_INVITE")
        say(L.BLOCKED:format(name or "?"))
        return "decline"
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1, a2)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliSocialDB = GulliSocialDB or {}
        ns.db = GulliSocialDB
        local defaults = { invite = true, words = "inv, invite, 123", inviteKnown = false, acceptKnown = true,
                           blockStrangers = false, noDuels = false, noGuildInvites = false }
        for k, v in pairs(defaults) do if ns.db[k] == nil then ns.db[k] = v end end
        for _, e in ipairs({ "CHAT_MSG_WHISPER", "PARTY_INVITE_REQUEST", "DUEL_REQUESTED",
                             "GUILD_INVITE_REQUEST" }) do
            self:RegisterEvent(e)
        end
        return
    end
    if event == "CHAT_MSG_WHISPER" then
        ns.OnWhisper(a1, a2)
    elseif event == "PARTY_INVITE_REQUEST" then
        ns.OnInvite(a1)
    elseif event == "DUEL_REQUESTED" then
        if ns.db.noDuels then CancelDuel(); hide("DUEL_REQUESTED"); say(L.NO_DUEL:format(a1 or "?")) end
    elseif event == "GUILD_INVITE_REQUEST" then
        if ns.db.noGuildInvites then DeclineGuild(); hide("GUILD_INVITE"); say(L.NO_GUILD:format(a1 or "?")) end
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
}

local function option(key, label)
    return { label = label, icon = ns.OPT_ICON[key], get = function() return ns.db ~= nil and ns.db[key] == true end,
             set = function(on) if ns.db then ns.db[key] = on and true or false end end }
end

if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({
        key = "Social",
        icon = "Interface\\AddOns\\Gulli-Social\\icon",
        slash = "/gso",
        open = function() ns.Toggle() end,
        options = {
            option("invite", ns.L.OPT_INVITE),
            option("inviteKnown", ns.L.OPT_INVITE_KNOWN),
            option("acceptKnown", ns.L.OPT_ACCEPT_KNOWN),
            option("blockStrangers", ns.L.OPT_BLOCK),
            option("noDuels", ns.L.OPT_DUELS),
            option("noGuildInvites", ns.L.OPT_GUILD),
        },
    })
end
