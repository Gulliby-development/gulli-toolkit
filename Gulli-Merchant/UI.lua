-- A small window: the switches in one card, the gray items in the bags in the footer with
-- Sell now as the main button.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, sellBtn

function ns.Refresh()
    if not frame or not frame:IsShown() then return end
    local junk, total = ns.Junk()
    frame.footer:SetStatus(#junk > 0 and L.JUNK:format(#junk, ns.Money(total)) or L.NO_JUNK,
        #junk > 0 and S.TEXT or S.MUTED)
    sellBtn:SetEnabled(ns.atVendor and #junk > 0)
end

local function build()
    frame = S.Window("GulliMerchantFrame", L.TITLE, S.NARROW_W, 300)
    local ft = S.Footer(frame)
    sellBtn = S.Primary(S.FitButton(ft, L.SELL_NOW, 32, 110))
    ft:Add(sellBtn)
    sellBtn:SetScript("OnClick", function() ns.SellJunk() end)

    local body, width = frame.body, frame.inner[1]
    local st = S.Stack(body)
    local rows = {}
    for _, o in ipairs({ { "sell", L.OPT_SELL }, { "repair", L.OPT_REPAIR },
                         { "guild", L.OPT_GUILD }, { "safe", L.OPT_SAFE } }) do
        local key = o[1]
        rows[#rows + 1] = { o[2], nil, function() return ns.db[key] end, function(v) ns.db[key] = v end, icon = ns.OPT_ICON[key] }
    end
    local card, h = S.SettingsCard(body, nil, rows)
    st:Add(card, h)
    local tip, th = S.Paragraph(body, L.SHIFT, width)
    st:Add(tip, th)
    S.FitWindow(frame, st:Height())
    frame:SetScript("OnShow", function() ns.Refresh() end)
end

function ns.Toggle()
    S.ToggleWindow(ns.Window())
end

-- The window, for the hub (/gulli) to show inside it.
function ns.Window()
    if not frame then build() end
    return frame
end
