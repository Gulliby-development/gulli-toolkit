-- The settings: which lines to add to the tooltip and how it looks, with an example tooltip
-- beside them that shows only what is switched on.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, example
local LEFT_W = 500

local QUEST, MUTED, GOOD, WHITE = { 1, 0.82, 0 }, { 0.6, 0.6, 0.62 }, { 0.42, 0.84, 0.50 }, { 1, 1, 1 }

local function row(key)
    local K = key:upper()
    return { L["OPT_" .. K], nil, function() return ns.db[key] end, function(v) ns.Set(key, v) end,
             icon = ns.OPT_ICON[key] }
end

-- The example tooltip: an item, then an NPC, each with the lines that are on.
local function exampleLines()
    local d = ns.db
    local shift = d.shift
    local out = { { L.EX_ITEM, "", WHITE, nil, 14 } }
    if d.protect then out[#out + 1] = { L.PROTECTED, "", GOOD } end
    if d.price and not shift then out[#out + 1] = { L.STACK:format(20), "2s 60c", MUTED } end
    if d.auction and not shift then out[#out + 1] = { L.AUCTION, "1s 5c", MUTED } end
    if d.quest then out[#out + 1] = { L.QUEST:format(L.EX_QUEST), "3/10", QUEST } end
    if d.alts then out[#out + 1] = { L.EX_ALT, L.BAGS_BANK:format(12, 5), MUTED } end
    if d.reagent then out[#out + 1] = { L.REAGENT:format(L.EX_PROF), "", MUTED } end
    if d.id and not shift then out[#out + 1] = { L.ITEM_ID, "2589", MUTED } end
    out[#out + 1] = { " ", "" }
    out[#out + 1] = { L.EX_MOB, "", WHITE, nil, 14 }
    if d.mobs then out[#out + 1] = { L.QUEST:format(L.EX_MOB_QUEST), "1/5", QUEST } end
    if d.id and not shift then out[#out + 1] = { L.NPC_ID, "113", MUTED } end
    if shift and (d.price or d.auction or d.id) then out[#out + 1] = { L.SHIFT_NOTE, "", MUTED } end
    return out
end

function ns.Refresh()
    if not frame or not frame:IsShown() then return end
    local lines = exampleLines()
    for i, l in ipairs(lines) do
        local fs = example.lines[i]
        if not fs then
            fs = { left = S.Text(example.box, 12), right = S.Text(example.box, 12) }
            fs.left:SetPoint("TOPLEFT", 10, -10 - (i - 1) * 20)
            fs.left:SetPoint("RIGHT", example.box, "RIGHT", -80, 0)
            fs.left:SetWordWrap(false)
            fs.right:SetPoint("TOPRIGHT", -10, -10 - (i - 1) * 20)
            fs.right:SetJustifyH("RIGHT")
            example.lines[i] = fs
        end
        local c = l[3] or WHITE
        fs.left:SetText(l[1])
        fs.left:SetTextColor(c[1], c[2], c[3], 1)
        fs.right:SetText(l[2])
        local rc = (c == QUEST) and WHITE or c
        fs.right:SetTextColor(rc[1], rc[2], rc[3], 1)
        fs.left:Show(); fs.right:Show()
    end
    for i = #lines + 1, #example.lines do example.lines[i].left:Hide(); example.lines[i].right:Hide() end
    example.box:SetHeight(20 + #lines * 20)
    local q = ns.db.quality and { 0.12, 1, 0, 1 } or { 0.3, 0.3, 0.33, 1 }
    S.SetBorder(example.box, q)
    for _, r in ipairs(frame.rows) do if r.SetChecked and r.key then r:SetChecked(ns.db[r.key]) end end
end

local function build()
    frame = S.Window("GulliTooltipFrame", L.TITLE, S.WIDE_W, 300)
    local body = frame.body
    local left = CreateFrame("Frame", nil, body)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(LEFT_W)
    local st = S.Stack(left)
    local lineRows = {}
    for _, k in ipairs(ns.LINES) do lineRows[#lineRows + 1] = row(k) end
    local lines, h1 = S.SettingsCard(left, L.SEC_LINES, lineRows)
    st:Add(lines, h1)
    local lookRows = {}
    for _, k in ipairs(ns.LOOK) do lookRows[#lookRows + 1] = row(k) end
    local look, h2 = S.SettingsCard(left, L.SEC_LOOK, lookRows)
    st:Add(look, h2)
    frame.rows = {}
    for i, r in ipairs(lines.rows) do r.key = ns.LINES[i]; frame.rows[#frame.rows + 1] = r end
    for i, r in ipairs(look.rows) do r.key = ns.LOOK[i]; frame.rows[#frame.rows + 1] = r end

    example = S.Card(body, L.SEC_EXAMPLE)
    example:SetPoint("TOPLEFT", left, "TOPRIGHT", S.GAP, 0)
    example:SetPoint("BOTTOMRIGHT")
    example.box = CreateFrame("Frame", nil, example.body)
    example.box:SetPoint("TOPLEFT")
    example.box:SetPoint("TOPRIGHT")
    S.Box(example.box, { 0.03, 0.03, 0.05, 0.95 }, S.EDGE)
    example.lines = {}
    S.FitWindow(frame, st:Height())
    frame:SetScript("OnShow", function() ns.Refresh() end)
end

function ns.Toggle()
    if S.ToggleWindow(ns.Window()) then ns.Refresh() end
end

-- The window, for the hub (/gulli) to show inside it.
function ns.Window()
    if not frame then
        build()
        frame:HookScript("OnShow", function(self) if self.docked then ns.Refresh() end end)
    end
    return frame
end
