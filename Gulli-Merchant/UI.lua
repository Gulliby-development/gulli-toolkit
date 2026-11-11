-- A small window: the switches, the gray items in the bags with their value, and Sell now.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, junkText, sellBtn

function ns.Refresh()
    if not frame or not frame:IsShown() then return end
    local junk, total = ns.Junk()
    junkText:SetText(#junk > 0 and L.JUNK:format(#junk, ns.Money(total)) or L.NO_JUNK)
    sellBtn:SetEnabled(ns.atVendor and #junk > 0)
end

local function build()
    frame = S.Window("GulliMerchantFrame", L.TITLE, 380, 260)
    local body = frame.body
    local y = 0
    for _, o in ipairs({ { "sell", L.OPT_SELL }, { "repair", L.OPT_REPAIR }, { "guild", L.OPT_GUILD } }) do
        local c = S.CheckRow(body, o[2], function() return ns.db[o[1]] end, function(v) ns.db[o[1]] = v end)
        c:SetPoint("TOPLEFT", 0, y)
        y = y - 32
    end
    local tip = S.Note(body, 11)
    tip:SetPoint("TOPLEFT", 0, y - 4)
    tip:SetPoint("RIGHT", 0, 0)
    tip:SetText(L.SHIFT)
    junkText = S.Text(body, 12)
    junkText:SetPoint("BOTTOMLEFT", 0, 44)
    junkText:SetPoint("RIGHT", 0, 0)
    sellBtn = S.Button(body, 160, 32)
    sellBtn:SetPoint("BOTTOMLEFT", 0, 0)
    sellBtn:SetText(L.SELL_NOW)
    sellBtn:SetScript("OnClick", function() ns.SellJunk() end)
    frame:SetScript("OnShow", function() ns.Refresh() end)
end

function ns.Toggle()
    if not frame then build() end
    frame:SetShown(not frame:IsShown())
end
