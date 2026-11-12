-- Two cards of switches: the invites (with the key words a whisper must have) and what to
-- turn away.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame
local I = "Interface\\Icons\\"

local function switch(key, label, icon)
    return { label, nil, function() return ns.db[key] end, function(v) ns.db[key] = v end, icon = I .. icon }
end

local function build()
    frame = S.Window("GulliSocialFrame", L.TITLE, 460, 400)
    local body = frame.body
    local words = S.Edit(body, 170, 28)
    words:SetJustifyH("LEFT")
    words:SetScript("OnShow", function(self) self:SetText(ns.db.words or "") end)
    local function apply(self) ns.db.words = self:GetText(); self:ClearFocus() end
    words:SetScript("OnEnterPressed", apply)
    words:SetScript("OnEditFocusLost", function(self) S.SetBorder(self, S.EDGE); apply(self) end)
    words:SetText(ns.db.words or "")

    local st = S.Stack(body)
    local invites, h1 = S.SettingsCard(body, L.SEC_INVITE, {
        switch("invite", L.OPT_INVITE, "INV_Letter_02"),
        { L.WORDS, nil, control = words, icon = I .. "INV_Misc_Note_05" },
        switch("inviteKnown", L.OPT_INVITE_KNOWN, "Spell_Holy_SealOfSalvation"),
        switch("acceptKnown", L.OPT_ACCEPT_KNOWN, "Spell_Holy_PrayerOfHealing02"),
    })
    st:Add(invites, h1)
    local away, h2 = S.SettingsCard(body, L.SEC_AWAY, {
        switch("blockStrangers", L.OPT_BLOCK, "Ability_Warrior_ShieldWall"),
        switch("noDuels", L.OPT_DUELS, "Ability_DualWield"),
        switch("noGuildInvites", L.OPT_GUILD, "INV_Shirt_GuildTabard_01"),
    })
    st:Add(away, h2)
    S.FitWindow(frame, st:Height())
end

function ns.Toggle()
    if not frame then build() end
    frame:SetShown(not frame:IsShown())
end
