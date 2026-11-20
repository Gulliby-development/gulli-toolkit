-- The settings: which lines to add to the tooltip and how it looks, with an example tooltip
-- beside them that shows only what is switched on.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, example
local LEFT_W = 500

local function row(key)
    local K = key:upper()
    return { L["OPT_" .. K], nil, function() return ns.db[key] end, function(v) ns.Set(key, v) end,
             icon = ns.OPT_ICON[key] }
end

local QUEST_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"
local function faint(t) return S.Hex(S.FAINT) .. t .. "|r" end

-- The example: an item, a boss drop and an NPC, each with the lines that are on, as block lines
-- like the real ones (see S.TipDraw). `head` is the game's own first line.
local function exampleLines()
    local d = ns.db
    local shift = d.shift
    local I = ns.OPT_ICON
    local out = { { head = true, left = L.EX_ITEM, color = S.TEXT } }
    local function add(l) out[#out + 1] = l end
    if d.protect then add({ group = "state", icon = I.protect, left = L.PROTECTED, color = S.GOOD }) end
    if d.quest then
        add({ group = "quest", icon = QUEST_ICON, left = L.EX_QUEST, right = "3" .. faint("/10"), color = S.GOLD })
    end
    if d.alts then
        add({ group = "stock", icon = I.alts, left = L.YOU_HAVE, right = "34", color = S.MUTED })
        add({ group = "stock", sub = true, left = (UnitName("player")) or "", right = "12" .. faint(" · " .. L.BANK_N:format(5)) })
        add({ group = "stock", sub = true, left = "|cff3fc7eb" .. L.EX_ALT .. "|r", right = "17" })
    end
    if d.price and not shift then
        add({ group = "price", icon = I.price, left = L.VENDOR .. faint(" ×20"), right = S.MoneyText(260), color = S.MUTED })
    end
    if d.auction and not shift and S.HasPrices() then
        add({ group = "price", icon = I.auction, left = L.AUCTION .. faint(" ×20"), right = S.MoneyText(2100), color = S.MUTED })
    end
    if d.reagent then add({ group = "craft", icon = I.reagent, left = L.EX_PROF, color = S.MUTED }) end
    if d.id and not shift then add({ group = "id", left = L.ID:format(2589), color = S.FAINT }) end
    if d.drops then
        add({ gap = true })
        add({ head = true, left = L.EX_GEAR, color = { 0.64, 0.21, 0.93 } })
        add({ group = "source", icon = I.drops, left = L.EX_BOSS, right = "0.3" .. faint("%"), color = S.GOLD })
        add({ group = "source", sub = true, left = L.EX_DUNGEON .. faint(" · ") .. S.Hex(S.GOOD) .. L.WISHED .. "|r",
              color = S.MUTED })
    end
    if d.id and not shift then
        add({ gap = true })
        add({ head = true, left = L.EX_MOB, color = S.TEXT })
        add({ group = "id", left = L.ID:format(113), color = S.FAINT })
    end
    if shift and (d.price or d.auction or d.id) then
        add({ gap = true })
        add({ left = L.SHIFT_NOTE, color = S.MUTED, note = true })
    end
    return out
end
ns.ExampleLines = exampleLines

local ROW_H, SUB_X = 20, 20

function ns.Refresh()
    if not frame or not frame:IsShown() then return end
    local lines = exampleLines()
    local group, blockStart
    for i, l in ipairs(lines) do
        local fs = example.lines[i]
        if not fs then
            fs = { left = S.Text(example.box, 12), right = S.Text(example.box, 12) }
            fs.left:SetWordWrap(false)
            fs.right:SetPoint("TOPRIGHT", -10, -10 - (i - 1) * ROW_H)
            fs.right:SetJustifyH("RIGHT")
            fs.rule = S.Tex(example.box, "ARTWORK", 0, { 1, 1, 1, 0.16 })
            fs.rule:SetHeight(1)
            example.lines[i] = fs
        end
        local c = l.color or S.TEXT
        local x = 10 + (l.sub and SUB_X or 0)
        fs.left:ClearAllPoints()
        fs.left:SetPoint("TOPLEFT", x, -10 - (i - 1) * ROW_H)
        fs.left:SetPoint("RIGHT", example.box, "RIGHT", -70, 0)
        S.SetFont(fs.left, l.head and 14 or 12)
        fs.left:SetText(l.gap and "" or ((l.icon and S.IconTag(l.icon, 14) .. " " or "") .. (l.left or "")))
        fs.left:SetTextColor(c[1], c[2], c[3], 1)
        fs.right:SetText(l.right or "")
        fs.right:SetTextColor(S.TEXT[1], S.TEXT[2], S.TEXT[3], 1)
        fs.left:Show(); fs.right:Show()
        -- The same lines as in the game: gold above the block, faint between its groups.
        local g = l.group
        if l.head or l.gap or l.note then group, blockStart = nil, true end
        local rule = g and g ~= group and (blockStart and "gold" or (g ~= "id" and "faint"))
        if g then group, blockStart = g, false end
        fs.rule:ClearAllPoints()
        fs.rule:SetPoint("TOPLEFT", example.box, "TOPLEFT", 10 + (rule == "faint" and SUB_X or 0), -8 - (i - 1) * ROW_H)
        fs.rule:SetPoint("RIGHT", example.box, "RIGHT", -10, 0)
        if rule == "gold" then fs.rule:SetColorTexture(1, 0.82, 0, 0.34)
        else fs.rule:SetColorTexture(1, 0.925, 0.784, 0.13) end
        fs.rule:SetShown(rule and true or false)
    end
    for i = #lines + 1, #example.lines do
        local fs = example.lines[i]
        fs.left:Hide(); fs.right:Hide(); fs.rule:Hide()
    end
    example.box:SetHeight(20 + #lines * ROW_H)
    local q = ns.db.quality and { 0.64, 0.21, 0.93, 1 } or { 0.3, 0.3, 0.33, 1 }
    S.SetBorder(example.box, q)
    -- without a price addon the auction line can show nothing: off and grey, the choice kept
    local priced = S.HasPrices()
    for _, r in ipairs(frame.rows) do
        if r.SetChecked and r.key then
            local grey = r.key == "auction" and not priced
            r:SetChecked(not grey and ns.db[r.key])
            if r.switch then r.switch:SetEnabled(not grey) end
        end
    end
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
    S.Box(example.box, { 0.03, 0.03, 0.05, 0.95 }, S.EDGE, S.R_MD)
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
