-- The settings: what to do on its own, in one card, and a note about Shift and rewards.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame
local I = "Interface\\Icons\\"

local function build()
    frame = S.Window("GulliAutoQuestFrame", L.TITLE, 440, 300)
    local body = frame.body
    local rows = {}
    for _, o in ipairs({ { "accept", L.OPT_ACCEPT, "INV_Scroll_03" }, { "turnIn", L.OPT_TURNIN, "INV_Misc_Bag_10" },
                         { "skipTrivial", L.OPT_TRIVIAL, "Spell_ChargeNegative" } }) do
        local key = o[1]
        rows[#rows + 1] = { o[2], nil, function() return ns.db[key] end, function(v) ns.db[key] = v end, icon = I .. o[3] }
    end
    local st = S.Stack(body)
    local card, h = S.SettingsCard(body, nil, rows)
    st:Add(card, h)
    local tip, th = S.Paragraph(body, L.NOTE, frame.inner[1])
    st:Add(tip, th)
    S.FitWindow(frame, st:Height())
end

function ns.Toggle()
    if not frame then build() end
    frame:SetShown(not frame:IsShown())
end
