-- The settings: which lines to add to the tooltip, in one card.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame
local I = "Interface\\Icons\\"

local function build()
    frame = S.Window("GulliTooltipFrame", L.TITLE, 420, 240)
    local rows = {}
    for _, o in ipairs({ { "price", L.OPT_PRICE, "INV_Misc_Coin_01" }, { "quest", L.OPT_QUEST, "INV_Misc_Note_01" },
                         { "id", L.OPT_ID, "INV_Misc_Gear_01" } }) do
        local key = o[1]
        rows[#rows + 1] = { o[2], nil, function() return ns.db[key] end, function(v) ns.db[key] = v end, icon = I .. o[3] }
    end
    local card, h = S.SettingsCard(frame.body, nil, rows)
    S.Stack(frame.body):Add(card, h)
    S.FitWindow(frame, h)
end

function ns.Toggle()
    if not frame then build() end
    frame:SetShown(not frame:IsShown())
end
