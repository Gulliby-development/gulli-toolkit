-- The settings: which lines to add.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame

local function build()
    frame = S.Window("GulliTooltipFrame", L.TITLE, 380, 170)
    local y = 0
    for _, o in ipairs({ { "price", L.OPT_PRICE }, { "quest", L.OPT_QUEST }, { "id", L.OPT_ID } }) do
        local c = S.CheckRow(frame.body, o[2], function() return ns.db[o[1]] end, function(v) ns.db[o[1]] = v end)
        c:SetPoint("TOPLEFT", 0, y)
        y = y - 32
    end
end

function ns.Toggle()
    if not frame then build() end
    frame:SetShown(not frame:IsShown())
end
