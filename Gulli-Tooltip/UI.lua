-- The settings: which lines to add to the tooltip, in one card.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame

local function build()
    frame = S.Window("GulliTooltipFrame", L.TITLE, S.NARROW_W, 240)
    local rows = {}
    for _, o in ipairs({ { "price", L.OPT_PRICE }, { "quest", L.OPT_QUEST },
                         { "id", L.OPT_ID } }) do
        local key = o[1]
        rows[#rows + 1] = { o[2], nil, function() return ns.db[key] end, function(v) ns.db[key] = v end, icon = ns.OPT_ICON[key] }
    end
    local card, h = S.SettingsCard(frame.body, nil, rows)
    S.Stack(frame.body):Add(card, h)
    S.FitWindow(frame, h)
end

function ns.Toggle()
    S.ToggleWindow(ns.Window())
end

-- The window, for the hub (/gulli) to show inside it.
function ns.Window()
    if not frame then build() end
    return frame
end
