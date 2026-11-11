-- The switches, and the key words a whisper must be to get an invite.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame

local function build()
    frame = S.Window("GulliSocialFrame", L.TITLE, 440, 360)
    local body = frame.body
    local y = 0
    local function check(key, label)
        local c = S.CheckRow(body, label, function() return ns.db[key] end, function(v) ns.db[key] = v end)
        c:SetPoint("TOPLEFT", 0, y)
        y = y - 32
    end
    check("invite", L.OPT_INVITE)
    local words = S.Edit(body, 200)
    words:SetPoint("TOPLEFT", 32, y)
    words:SetJustifyH("LEFT")
    words:SetScript("OnShow", function(self) self:SetText(ns.db.words or "") end)
    local function apply(self) ns.db.words = self:GetText(); self:ClearFocus() end
    words:SetScript("OnEnterPressed", apply)
    words:SetScript("OnEditFocusLost", function(self) S.SetBorder(self, S.BORDER); apply(self) end)
    local wt = S.Note(body, 11)
    wt:SetPoint("LEFT", words, "RIGHT", 8, 0)
    wt:SetPoint("RIGHT", 0, 0)
    wt:SetText(L.WORDS)
    y = y - 34
    check("inviteKnown", L.OPT_INVITE_KNOWN)
    check("acceptKnown", L.OPT_ACCEPT_KNOWN)
    check("blockStrangers", L.OPT_BLOCK)
    check("noDuels", L.OPT_DUELS)
    check("noGuildInvites", L.OPT_GUILD)
end

function ns.Toggle()
    if not frame then build() end
    frame:SetShown(not frame:IsShown())
end
