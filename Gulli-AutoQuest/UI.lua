-- The settings: what to do on its own, and a note about Shift and rewards.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame

local function build()
    frame = S.Window("GulliAutoQuestFrame", L.TITLE, 400, 230)
    local body = frame.body
    local y = 0
    for _, o in ipairs({ { "accept", L.OPT_ACCEPT }, { "turnIn", L.OPT_TURNIN }, { "skipTrivial", L.OPT_TRIVIAL } }) do
        local c = S.CheckRow(body, o[2], function() return ns.db[o[1]] end, function(v) ns.db[o[1]] = v end)
        c:SetPoint("TOPLEFT", 0, y)
        y = y - 32
    end
    local tip = S.Note(body, 11)
    tip:SetPoint("TOPLEFT", 0, y - 6)
    tip:SetPoint("RIGHT", 0, 0)
    tip:SetText(L.NOTE)
end

function ns.Toggle()
    if not frame then build() end
    frame:SetShown(not frame:IsShown())
end
