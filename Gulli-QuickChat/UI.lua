-- Two pages. Phrases: the ring on the left (up to eight phrases, placed by direction) and every
-- phrase on the right, where the player adds their own, marks favourites for the panel and gives a
-- phrase its own channel order. Setup: the channel order, the wheel key and the favourites panel.
-- Outside the window: the wheel (the ring at the cursor while the key is held) and the panel.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, tabs, pages = nil, nil, {}
local current = 1
local held        -- a phrase picked on the right, waiting for a place on the ring
local chosen      -- the ring place picked in the editor
local editing     -- the phrase whose channel order the right card shows
local wheel, wheelButton, panel, ghost
local I = "Interface\\Icons\\"
local OWN_ICON = I .. "INV_Misc_Note_05"

ns.CH_ICON = { RAID = I .. "Spell_Holy_PrayerOfFortitude", PARTY = I .. "Spell_Holy_PrayerOfHealing02",
               GUILD = I .. "INV_Shirt_GuildTabard_01", SAY = I .. "INV_Misc_Note_01",
               YELL = I .. "Ability_Warrior_BattleShout", LFG = I .. "INV_Misc_Spyglass_02",
               TRADE = I .. "INV_Misc_Coin_02", GENERAL = I .. "INV_Misc_Map_01", WHISPER = I .. "INV_Letter_15" }

local function chanLabel(key) return key and L["CH_" .. key] or L.CH_DEFAULT end

-- Each default phrase has its own picture; the player's own phrases show a note.
local PHRASE_ICONS = { "INV_Letter_02", "Ability_Warrior_BattleShout", "INV_Misc_PocketWatch_01", "Ability_Rogue_Sprint",
                       "INV_Misc_Gift_01", "Ability_Mount_RidingHorse", "Spell_Holy_FlashHeal", "INV_Drink_18",
                       "INV_Misc_Coin_02", "INV_Misc_Coin_01" }

local function phraseIcon(text)
    for i, name in ipairs(PHRASE_ICONS) do
        if L["P" .. i] == text then return I .. name end
    end
    return OWN_ICON
end
ns.PhraseIcon = phraseIcon

-- Where a phrase goes now, for the ring and the rows: "Party", or a warning.
local function goesText(text)
    local key = ns.Route(text)
    if key then return L.GOES_TO:format(chanLabel(key)) end
    return S.Hex(S.WARN) .. L.GOES_NOWHERE .. "|r"
end

---- The channel order (Setup, and a phrase's own) ------------------------------------------------

local ORDER_ROW = 34

-- The channels that are on, numbered in order, then the ones that are off.
local function orderRows(list)
    local rows = {}
    for i, k in ipairs(list) do rows[#rows + 1] = { key = k, n = i } end
    for _, k in ipairs(ns.CHANNELS) do
        if not ns.IndexOf(list, k) then rows[#rows + 1] = { key = k } end
    end
    return rows
end

local function arrow(b, up)
    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetSize(16, 16)
    t:SetPoint("CENTER")
    t:SetTexture(up and "Interface\\Buttons\\Arrow-Up-Up" or "Interface\\Buttons\\Arrow-Down-Up")
    t:SetVertexColor(S.MUTED[1], S.MUTED[2], S.MUTED[3], 1)
    b.arrow = t
end

-- getList() gives the list to change (nil: read only), shown() the list to show.
local function orderBox(parent, width, getList, shown, onChange)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(width, #ns.CHANNELS * ORDER_ROW)
    box.rows = {}
    for i = 1, #ns.CHANNELS do
        local r = CreateFrame("Frame", nil, box)
        r:SetSize(width, ORDER_ROW)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * ORDER_ROW)
        r.num = S.Text(r, 12, S.Accent())
        r.num:SetPoint("LEFT", 2, 0)
        r.num:SetWidth(16)
        r.num:SetJustifyH("CENTER")
        r.icon = S.IconBox(r, 22)
        r.icon:SetPoint("LEFT", 24, 0)
        r.down = S.Ghost(S.Button(r, 28, 26))
        r.down:SetPoint("RIGHT", 0, 0)
        arrow(r.down, false)
        r.up = S.Ghost(S.Button(r, 28, 26))
        r.up:SetPoint("RIGHT", r.down, "LEFT", -2, 0)
        arrow(r.up, true)
        r.switch = S.Switch(r)
        r.switch:SetPoint("RIGHT", r.up, "LEFT", -6, 0)
        r.now = S.Text(r, 12, S.GOOD)
        r.now:SetPoint("RIGHT", r.switch, "LEFT", -6, 0)
        r.name = S.Text(r, 12)
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
        r.name:SetPoint("RIGHT", r.now, "LEFT", -6, 0)
        r.name:SetWordWrap(false)
        r.line = S.Divider(r)
        r.line:SetPoint("BOTTOMLEFT")
        r.line:SetPoint("BOTTOMRIGHT")
        r.line:SetHeight(1)
        r.switch:SetScript("OnClick", function()
            local list = getList()
            if not list then return end
            ns.ToggleChannel(list, r.key)
            onChange()
        end)
        r.up:SetScript("OnClick", function()
            local list = getList()
            if list and ns.MoveChannel(list, r.key, -1) then onChange() end
        end)
        r.down:SetScript("OnClick", function()
            local list = getList()
            if list and ns.MoveChannel(list, r.key, 1) then onChange() end
        end)
        box.rows[i] = r
    end
    function box:Refresh()
        local list = shown()
        local canEdit = getList() ~= nil
        for i, row in ipairs(orderRows(list)) do
            local r = self.rows[i]
            r.key = row.key
            local on = row.n ~= nil
            r.num:SetText(on and tostring(row.n) or "")
            r.icon.tex:SetTexture(ns.CH_ICON[row.key])
            r.icon:SetAlpha(on and 1 or 0.45)
            local c = on and S.TEXT or S.FAINT
            r.name:SetText(chanLabel(row.key))
            r.name:SetTextColor(c[1], c[2], c[3], 1)
            r.now:SetText(on and ns.CanUse(row.key) and L.NOW or "")
            r.switch:SetChecked(on)
            r.switch:SetEnabled(canEdit)
            r.up:SetShown(on and row.n > 1 and canEdit)
            r.down:SetShown(on and row.n < #list and canEdit)
            r.line:SetShown(i < #ns.CHANNELS)
        end
        self:SetAlpha(canEdit and 1 or 0.6)
    end
    return box
end

---- Phrases: the ring editor -------------------------------------------------------------------

local RING_R, SLOT = 118, 52
local ringEditor

-- The angle of ring place i: 1 at the top, then clockwise.
local function placeAngle(i) return math.rad(90 - (i - 1) * 360 / ns.RING_MAX) end

local function refreshRing()
    local ring = ns.Ring()
    for i, slot in ipairs(ringEditor.slots) do
        local text = ring[i]
        slot.phrase = text or nil
        slot.icon:SetIcon(text and phraseIcon(text) or nil)
        slot.icon.tex:SetShown(text ~= nil and text ~= false)
        slot.label:SetText(text or (S.Hex(S.FAINT) .. L.RING_EMPTY .. "|r"))
        local lit = (chosen == i) or (held ~= nil)
        slot.icon:SetRing((chosen == i or (held and not text)) and S.Accent() or S.EDGE)
        slot.icon:SetAlpha(text and 1 or (lit and 0.9 or 0.5))
    end
    local e = ringEditor
    if held then
        e.say:SetText(L.RING_PLACE:format(held))
        e.where:SetText("")
        e.remove:Hide()
    elseif chosen and ring[chosen] then
        e.say:SetText(ns.Fill(ring[chosen]))
        e.where:SetText(goesText(ring[chosen]))
        e.remove:Show()
    else
        e.say:SetText(L.RING_PICK)
        e.where:SetText("")
        e.remove:Hide()
    end
    local key = ns.db.wheelKey
    e.key:SetText(L.WHEEL_LINE:format(key and (S.Hex(S.Accent()) .. key .. "|r") or L.NO_KEY) .. "  " ..
        S.Hex(S.FAINT) .. (ns.db.wheelHold and L.WHEEL_HOLD_D or L.WHEEL_PRESS_D) .. "|r")
end

-- A click on ring place i: puts the picked phrase there, else picks the place; right-click empties it.
function ns.ClickSlot(i, button)
    if button == "RightButton" then
        ns.SetRing(i, nil)
        chosen = nil
    elseif held then
        ns.SetRing(i, held)
        held, chosen = nil, i
    else
        chosen = (chosen ~= i and ns.Ring()[i]) and i or nil
    end
    if ns.Refresh then ns.Refresh() end
end

local function buildRingEditor(card)
    local body = card.body
    local e = CreateFrame("Frame", nil, body)
    e:SetPoint("TOPLEFT")
    e:SetPoint("TOPRIGHT")
    e:SetHeight(2 * (RING_R + SLOT) + 40)
    ringEditor = e
    e.track = S.Circle(e, 2 * RING_R + 4, { 1, 1, 1, 0.06 }, "BACKGROUND", 1)
    e.track:SetPoint("CENTER", 0, 4)
    e.hole = S.Circle(e, 2 * RING_R - 4, { 0, 0, 0, 0.3 }, "BACKGROUND", 2)
    e.hole:SetPoint("CENTER", 0, 4)
    e.mid = S.Circle(e, 150, S.EDGE, "BORDER", 0)
    e.mid:SetPoint("CENTER", 0, 4)
    e.midFill = S.Circle(e, 146, S.BG, "BORDER", 1)
    e.midFill:SetPoint("CENTER", 0, 4)
    e.say = S.Text(e, 12)
    e.say:SetWidth(122)
    e.say:SetPoint("CENTER", 0, 14)
    e.say:SetJustifyH("CENTER")
    e.say:SetMaxLines(4)
    e.where = S.Text(e, 12, S.FAINT)
    e.where:SetWidth(122)
    e.where:SetJustifyH("CENTER")
    e.where:SetPoint("TOP", e.say, "BOTTOM", 0, -4)
    e.remove = S.Ghost(S.Button(e, 100, 26))
    e.remove:SetPoint("TOP", e.where, "BOTTOM", 0, -4)
    e.remove:SetText(L.RING_REMOVE)
    e.remove:SetScript("OnClick", function() if chosen then ns.ClickSlot(chosen, "RightButton") end end)
    e.slots = {}
    for i = 1, ns.RING_MAX do
        local slot = CreateFrame("Button", nil, e)
        slot:SetSize(SLOT, SLOT)
        local a = placeAngle(i)
        slot:SetPoint("CENTER", e, "CENTER", math.floor(math.cos(a) * RING_R), math.floor(math.sin(a) * RING_R) + 4)
        slot.icon = S.RoundIcon(slot, SLOT)
        slot.icon:SetPoint("CENTER")
        slot.label = S.Text(slot, 12, S.MUTED)
        slot.label:SetWidth(96)
        slot.label:SetJustifyH("CENTER")
        slot.label:SetMaxLines(2)
        -- The upper places write their name above, so it never runs into the middle.
        if math.sin(a) > 0.5 then slot.label:SetPoint("BOTTOM", slot, "TOP", 0, 2)
        else slot.label:SetPoint("TOP", slot, "BOTTOM", 0, -2) end
        slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        slot:SetScript("OnClick", function(_, button) ns.ClickSlot(i, button) end)
        e.slots[i] = slot
    end
    e.key = S.Note(body, 12)
    e.key:SetPoint("BOTTOMLEFT")
    e.key:SetPoint("BOTTOMRIGHT")
    e.key:SetHeight(32)
    e.key:SetMaxLines(2)
end

---- Phrases: the list ----------------------------------------------------------------------------

-- Dragging a phrase onto the ring: a small label follows the cursor until the button is let go.
local function slotUnderCursor()
    if not ringEditor then return nil end
    for i, slot in ipairs(ringEditor.slots) do
        if slot.IsMouseOver and slot:IsMouseOver() then return i end
    end
end

local function startDrag(text)
    held = text
    if not ghost then
        ghost = CreateFrame("Frame", nil, UIParent)
        ghost:SetFrameStrata("TOOLTIP")
        ghost:SetSize(200, 28)
        S.HudPanel(ghost)
        ghost.text = S.Text(ghost, 12)
        ghost.text:SetPoint("LEFT", 8, 0)
        ghost.text:SetPoint("RIGHT", -8, 0)
        ghost.text:SetWordWrap(false)
        ghost:SetScript("OnUpdate", function(self)
            if not GetCursorPosition then return end
            local x, y = GetCursorPosition()
            local s = UIParent:GetEffectiveScale()
            self:ClearAllPoints()
            self:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / s + 12, y / s - 14)
        end)
    end
    ghost.text:SetText(text)
    ghost:Show()
    ns.Refresh()
end

local function stopDrag()
    if ghost then ghost:Hide() end
    local i = slotUnderCursor()
    if i and held then ns.ClickSlot(i) else ns.Refresh() end
end

-- Picks a phrase for the ring (a second click puts it back), for the previews and the tests too.
function ns.PickPhrase(text)
    held = (held ~= text) and text or nil
    chosen = nil
    ns.Refresh()
end

-- Shows a phrase's channel order in the right card (nil: back to the list).
function ns.EditOrder(text)
    editing = text
    ns.Refresh()
end

-- A tooltip on a control: fn returns its text.
local function tip(b, fn)
    b:HookScript("OnEnter", function(self)
        if not (GameTooltip and GameTooltip.SetOwner) then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(fn(self), 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

-- A phrase's order in one line: "Raid » Party » Say".
local function orderLine(text)
    local names = {}
    for _, key in ipairs(ns.Order(text)) do names[#names + 1] = chanLabel(key) end
    return table.concat(names, " » ")
end

-- What the order button of a row shows: the phrase's own channels as icons, else "As in Setup".
function ns.OrderLabel(text)
    local list = ns.db.orderOf[text]
    if not list then return S.Hex(S.MUTED) .. S.IconTag(S.TAB.settings, 14) .. " " .. L.CH_DEFAULT .. "|r", false end
    if #list == 0 then return S.Hex(S.WARN) .. "-|r", true end
    local more = #list > 1 and (" " .. S.Hex(S.MUTED) .. "+" .. (#list - 1) .. "|r") or ""
    return S.IconTag(ns.CH_ICON[list[1]], 14) .. " " .. S.Hex(S.Accent()) .. chanLabel(list[1]) .. "|r" .. more, true
end

local STAR = "Interface\\Common\\FavoritesIcon"

local function makePhrase(r)
    r.btn = CreateFrame("Button", nil, r)
    r.btn:SetAllPoints()
    r.btn:RegisterForDrag("LeftButton")
    r.btn:SetScript("OnClick", function(self) ns.PickPhrase(self:GetParent().phrase) end)
    r.btn:SetScript("OnDragStart", function(self) startDrag(self:GetParent().phrase) end)
    r.btn:SetScript("OnDragStop", function() stopDrag() end)
    r.btn:SetScript("OnEnter", function(self) if self:GetParent().phrase ~= held then S.Fill(self:GetParent(), S.HOVER) end end)
    r.btn:SetScript("OnLeave", function(self) if self:GetParent().phrase ~= held then S.Fill(self:GetParent(), S.CLEAR) end end)
    r.icon = S.IconBox(r, 22)
    r.icon:SetPoint("LEFT", 6, 0)
    r.del = S.Ghost(S.Button(r, 28, 26))
    r.del:SetPoint("RIGHT", 0, 0)
    r.del:SetText("x")
    r.del:SetScript("OnClick", function(self)
        local text = self:GetParent().phrase
        ns.RemovePhrase(text)
        if held == text then held = nil end
        ns.Refresh()
        if ns.Panel then ns.Panel() end
    end)
    r.chan = S.Ghost(S.Button(r, 104, 26))
    r.chan:SetPoint("RIGHT", r.del, "LEFT", -4, 0)
    r.chan:SetScript("OnClick", function(self) ns.EditOrder(self:GetParent().phrase) end)
    tip(r.chan, function(self)
        local text = self:GetParent().phrase
        return (ns.HasOwnOrder(text) and L.TIP_OWN or L.TIP_SETUP):format(orderLine(text))
    end)
    r.fav = S.Ghost(S.Button(r, 28, 26))
    r.fav:SetPoint("RIGHT", r.chan, "LEFT", -4, 0)
    r.fav:SetText("")
    r.fav.star = r.fav:CreateTexture(nil, "ARTWORK")
    r.fav.star:SetSize(16, 16)
    r.fav.star:SetPoint("CENTER")
    r.fav.star:SetTexture(STAR)
    r.fav:SetScript("OnClick", function(self)
        ns.ToggleFav(self:GetParent().phrase)
        ns.Refresh()
        if ns.Panel then ns.Panel() end
    end)
    tip(r.fav, function() return L.TIP_FAV end)
    r.place = S.Text(r, 12, S.Accent())
    r.place:SetPoint("RIGHT", r.fav, "LEFT", -4, 0)
    r.place:SetWidth(18)
    r.place:SetJustifyH("CENTER")
    r.text = S.Text(r, 12)
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
    r.text:SetPoint("RIGHT", r.place, "LEFT", -4, 0)
    r.text:SetWordWrap(false)
    -- The row's own click area lies under its buttons, so they take their clicks.
    local base = r:GetFrameLevel()
    r.btn:SetFrameLevel(base + 1)
    for _, b in ipairs({ r.del, r.chan, r.fav }) do b:SetFrameLevel(base + 3) end
end

local function fillPhrase(r, text)
    r.phrase = text
    r.icon.tex:SetTexture(phraseIcon(text))
    r.text:SetText(text)
    local place = ns.RingPlace(text)
    r.place:SetText(place and tostring(place) or "")
    local fav = ns.db.fav[text] and true or false
    r.fav.star:SetDesaturated(not fav)
    r.fav.star:SetAlpha(fav and 1 or 0.3)
    r.chan:SetText((ns.OrderLabel(text)))
    S.Fill(r, text == held and S.RAISED or S.CLEAR)
end

local function buildPhrases(page, width)
    local leftW = 360
    local ringCard = S.Card(page, L.SEC_RING, nil, I .. "INV_Misc_EngGizmos_20")
    ringCard:SetPoint("TOPLEFT")
    ringCard:SetPoint("BOTTOMLEFT")
    ringCard:SetWidth(leftW)
    buildRingEditor(ringCard)

    local card = S.Card(page, L.SEC_PHRASES, nil, I .. "INV_Misc_Note_05")
    card:SetPoint("TOPLEFT", leftW + S.GAP, 0)
    card:SetPoint("BOTTOMRIGHT")
    page.card = card
    local body = card.body
    local listView = CreateFrame("Frame", nil, body)
    listView:SetAllPoints()
    page.listView = listView
    local add = S.Edit(listView, 200, 30)
    add:SetPoint("TOPLEFT")
    add:SetPoint("TOPRIGHT", -98, 0)
    add:SetJustifyH("LEFT")
    add:SetMaxLetters(200)
    S.Placeholder(add, L.ADD_HINT)
    local addBtn = S.Button(listView, 90, 30)
    addBtn:SetPoint("TOPRIGHT")
    addBtn:SetText(L.ADD)
    local function doAdd()
        local text = add:GetText()
        if ns.AddPhrase(text) then
            add:SetText("")
            held, chosen = strtrim(text), nil
        end
        add:ClearFocus()
        ns.Refresh()
    end
    addBtn:SetScript("OnClick", doAdd)
    add:SetScript("OnEnterPressed", doAdd)
    page.add = add
    local list = S.List(listView, 36, makePhrase, fillPhrase)
    list:SetPoint("TOPLEFT", 0, -38)
    list:SetPoint("BOTTOMRIGHT", -10, 54)
    page.list = list
    page.empty = S.Empty(list)
    page.empty:Set(L.NO_PHRASES)
    local reset = S.Ghost(S.Button(listView, 100, 30))
    reset:SetPoint("BOTTOMRIGHT")
    reset:SetText(L.RESET)
    reset:SetScript("OnClick", function()
        ns.ResetRing(); held, chosen = nil, nil
        ns.Refresh()
        if ns.Panel then ns.Panel() end
    end)
    local hint = S.Note(listView, 12)
    hint:SetPoint("BOTTOMLEFT")
    hint:SetPoint("RIGHT", reset, "LEFT", -10, 0)
    hint:SetHeight(46)
    hint:SetMaxLines(3)
    hint:SetText(L.TOKENS)

    -- A phrase's own channel order.
    local orderView = CreateFrame("Frame", nil, body)
    orderView:SetAllPoints()
    page.orderView = orderView
    local title = S.Text(orderView, 13)
    title:SetPoint("TOPLEFT")
    title:SetPoint("TOPRIGHT")
    title:SetWordWrap(false)
    page.orderTitle = title
    local ownSwitch = S.SwitchLabel(orderView, L.ORDER_OWN, function() return editing and ns.HasOwnOrder(editing) end,
        function(v) if editing then ns.SetOwnOrder(editing, v); ns.Refresh() end end, 300)
    ownSwitch:SetPoint("TOPLEFT", -4, -24)
    page.ownSwitch = ownSwitch
    local bw = width - leftW - S.GAP - 2 * S.INSET - 4
    page.order = orderBox(orderView, bw, function() return editing and ns.db.orderOf[editing] end,
        function() return ns.Order(editing) end, function() ns.Refresh() end)
    page.order:SetPoint("TOPLEFT", 0, -60)
    page.orderWhere = S.Note(orderView, 12)
    page.orderWhere:SetPoint("BOTTOMLEFT")
    page.orderWhere:SetPoint("RIGHT", -110, 0)
    page.orderWhere:SetHeight(30)
    local back = S.Button(orderView, 100, 30)
    back:SetPoint("BOTTOMRIGHT")
    back:SetText(L.BACK)
    back:SetScript("OnClick", function() ns.EditOrder(nil) end)

    page.Update = function()
        refreshRing()
        local editingNow = editing ~= nil
        listView:SetShown(not editingNow)
        orderView:SetShown(editingNow)
        if editingNow then
            card:SetTitle(L.SEC_WHERE)
            title:SetText(S.Hex(S.MUTED) .. "\"" .. editing .. "\"|r")
            ownSwitch:SetChecked(ns.HasOwnOrder(editing))
            page.order:Refresh()
            page.orderWhere:SetText(goesText(editing) ..
                (ns.HasOwnOrder(editing) and "" or ("\n" .. S.Hex(S.MUTED) .. L.ORDER_FROM_SETUP .. "|r")))
        else
            card:SetTitle(L.SEC_PHRASES)
            local items = ns.Phrases()
            list:SetData(items)
            page.empty:SetShown(#items == 0)
        end
    end
end

---- Setup ----------------------------------------------------------------------

local capture

local function keyText()
    return ns.db.wheelKey and (S.Hex(S.Accent()) .. ns.db.wheelKey .. "|r") or L.NO_KEY
end

local MODIFIERS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true }

-- The key (or gamepad button) that opens the wheel, with Shift, Ctrl or Alt.
function ns.SetKey(key)
    if key == "ESCAPE" then key = nil end
    if key and not key:find("^PAD") then
        if IsAltKeyDown and IsAltKeyDown() then key = "ALT-" .. key end
        if IsControlKeyDown and IsControlKeyDown() then key = "CTRL-" .. key end
        if IsShiftKeyDown and IsShiftKeyDown() then key = "SHIFT-" .. key end
    end
    ns.db.wheelKey = key
    ns.ApplyKey()
end

local function buildSetup(page, width)
    local scroll = S.Scroll(page)
    scroll:SetPoint("TOPLEFT")
    scroll:SetPoint("BOTTOMRIGHT", -12, 0)
    local c = scroll.child
    c:SetWidth(width - 12)
    local st = S.Stack(c)

    local orderCard = S.Card(c, L.SEC_ORDER, nil, I .. "INV_Misc_Note_01")
    local hint = S.Note(orderCard.body, 12)
    hint:SetPoint("TOPLEFT")
    hint:SetPoint("TOPRIGHT")
    hint:SetHeight(30)
    hint:SetMaxLines(2)
    hint:SetText(L.ORDER_HINT)
    local box = orderBox(orderCard.body, width - 12 - 2 * S.INSET, function() return ns.db.order end,
        function() return ns.db.order end, function() ns.Refresh() end)
    box:SetPoint("TOPLEFT", 0, -36)
    page.order = box
    st:Add(orderCard, orderCard:Fit(36 + #ns.CHANNELS * ORDER_ROW))

    local keyBtn = S.Button(c, 150, 28)
    keyBtn:SetScript("OnShow", function(self) self:SetText(keyText()) end)
    keyBtn:SetText(keyText())
    keyBtn:SetScript("OnClick", function(self)
        if InCombatLockdown and InCombatLockdown() then return end
        capture = self
        self:SetText(L.PRESS_KEY)
        self:EnableKeyboard(true)
        if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
        if self.EnableGamePadButton then self:EnableGamePadButton(true) end
    end)
    local function done(self, key)
        if capture ~= self or MODIFIERS[key] then return end
        capture = nil
        self:EnableKeyboard(false)
        if self.EnableGamePadButton then self:EnableGamePadButton(false) end
        ns.SetKey(key)
        self:SetText(keyText())
    end
    keyBtn:SetScript("OnKeyDown", done)
    keyBtn:SetScript("OnGamePadButtonDown", done)
    local open = S.Button(c, 110, 28)
    open:SetText(L.OPEN_WHEEL)
    open:SetScript("OnClick", function() ns.ToggleWheel() end)
    local wheelCard, h1 = S.SettingsCard(c, L.SEC_WHEEL, {
        { L.WHEEL_KEY, L.WHEEL_KEY_D, control = keyBtn, icon = I .. "INV_Misc_Key_03" },
        { L.WHEEL_HOLD, L.WHEEL_HOLD_D, function() return ns.db.wheelHold end,
          function(v) ns.db.wheelHold = v; ns.Refresh() end, icon = ns.OPT_ICON.wheelHold },
        { L.WHEEL_TRY, nil, control = open, icon = I .. "Spell_Holy_PrayerOfFortitude" },
    })
    st:Add(wheelCard, h1)

    local count = S.Stepper(c, function() return ns.db.panelCount end,
        function(v) ns.db.panelCount = v; ns.Panel() end, 1, 2, ns.PANEL_MAX, tostring, 110)
    local size = S.Stepper(c, function() return ns.db.panelScale end,
        function(v) ns.db.panelScale = v; ns.Panel() end, 10, 60, 150, function(v) return v .. "%" end, 110)
    local panelCard, h2 = S.SettingsCard(c, L.SEC_PANEL, {
        { L.PANEL_COUNT, nil, control = count, icon = I .. "INV_Misc_Note_06" },
        { L.PANEL_SIZE, nil, control = size, icon = I .. "INV_Misc_Spyglass_03" },
        { L.PANEL_ROW, nil, function() return ns.db.panelRow end,
          function(v) ns.db.panelRow = v; ns.Panel() end, icon = I .. "INV_Misc_Map_01" },
    })
    st:Add(panelCard, h2)
    c:SetHeight(st:Height())
    page.Update = function()
        box:Refresh()
        count:Refresh(); size:Refresh()
        scroll:Update(st:Height())
    end
end

---- Window ------------------------------------------------------------------------

function ns.Refresh()
    if not frame or not frame:IsShown() then return end
    for i, p in ipairs(pages) do p:SetShown(i == current) end
    pages[current].Update()
end

local function build()
    frame = S.Window("GulliQuickChatFrame", L.TITLE, S.WIDE_W, S.DOCK_H)
    local body, width = frame.body, frame.inner[1]
    tabs = S.PageTabs(body, { L.TAB_PHRASES, L.TAB_SETUP }, 150,
        function(i) current = i; ns.Refresh() end, nil, { S.TAB.chat, S.TAB.settings })
    for i, b in ipairs({ buildPhrases, buildSetup }) do
        local page = CreateFrame("Frame", nil, body)
        page:SetPoint("TOPLEFT", 0, -30 - S.GAP)
        page:SetPoint("BOTTOMRIGHT", 0, 0)
        b(page, width)
        pages[i] = page
    end
    frame:SetScript("OnShow", function() tabs:Select(current) end)
    frame:HookScript("OnHide", function() held, chosen, editing = nil, nil, nil end)
end

-- Picks a page (1 Phrases, 2 Setup), for the previews and the tests.
function ns.ShowPage(i)
    ns.Window():Show()
    tabs:Select(i)
end

function ns.Toggle()
    if S.ToggleWindow(ns.Window()) then
        ns.Refresh()
    end
end

-- The window, for the hub (/gulli) to show inside it.
function ns.Window()
    if not frame then
        build()
        -- In the hub the window is shown by the hub, not by ns.Toggle.
        frame:HookScript("OnShow", function(self)
            if not self.docked then return end
            ns.Refresh()
        end)
    end
    return frame
end

---- The wheel --------------------------------------------------------------------

-- The ring at the cursor: the eight places of the editor, the one in the pointed direction lit,
-- its text in the middle. While it shows, a frame over the whole screen takes every click, so a
-- click anywhere sends the lit phrase; letting go of the key does the same.
ns.WHEEL_R = 150
local WSLOT = 58
local hovered -- the lit place (kept outside the frame)

local function wheelSelect(i)
    hovered = i
    local a = S.Accent()
    for j, slot in ipairs(wheel.slots) do
        local on = j == i
        slot.icon:SetRing(on and a or S.EDGE)
        slot.icon.fill:SetVertexColor(unpack(on and S.RAISED or S.SURFACE))
        slot.icon:SetScale(on and 1.12 or 1)
        local c = on and S.TEXT or S.MUTED
        slot.label:SetTextColor(c[1], c[2], c[3], 1)
    end
    local slot = i and wheel.slots[i]
    wheel.dot:SetShown(slot ~= nil)
    if slot then
        wheel.dot:ClearAllPoints()
        wheel.dot:SetPoint("CENTER", wheel.ring, "CENTER", math.floor(math.cos(slot.angle) * 104),
            math.floor(math.sin(slot.angle) * 104))
        wheel.say:SetText(ns.Fill(slot.phrase))
        local where = goesText(slot.phrase)
        if ns.NeedsPress(slot.phrase) then where = where .. "\n" .. S.Hex(S.WARN) .. L.CLICK_SEND .. "|r" end
        wheel.where:SetText(where)
    else
        wheel.say:SetText(L.WHEEL_PICK)
        wheel.where:SetText("")
    end
end

-- The place the cursor points at: the shown place nearest in direction, once out of the middle.
local function pointedSlot()
    if not GetCursorPosition then return nil end
    local x, y = GetCursorPosition()
    local scale = wheel.ring:GetEffectiveScale()
    local cx, cy = wheel.ring:GetCenter()
    if not cx or not x then return nil end
    local dx, dy = x / scale - cx, y / scale - cy
    if dx * dx + dy * dy < 40 * 40 then return nil end
    local a = math.atan2(dy, dx)
    local best, bestD
    for i, slot in ipairs(wheel.slots) do
        if slot:IsShown() then
            local d = math.abs((a - slot.angle + math.pi) % (2 * math.pi) - math.pi)
            if not bestD or d < bestD then best, bestD = i, d end
        end
    end
    return best
end

-- Whether the wheel shows and the line under its text, for the tests.
function ns.WheelInfo()
    if not wheel then return false, nil end
    return wheel:IsShown() and true or false, wheel.where:GetText()
end

-- Lights a place, for the previews and the tests.
function ns.WheelHover(i) wheelSelect(i) end

function ns.WheelSend(i)
    local slot = wheel and wheel.slots[i]
    if not slot or not slot:IsShown() then return false end
    wheel:Hide()
    return ns.Say(slot.phrase) and true or false
end

local function buildWheel()
    local size = 2 * (ns.WHEEL_R + 80)
    -- A button over the whole screen takes every click while the ring shows.
    wheel = CreateFrame("Button", "GulliQuickChatWheel", UIParent)
    wheel:SetAllPoints(UIParent)
    wheel:SetFrameStrata("DIALOG")
    wheel:EnableMouse(true)
    wheel:RegisterForClicks("LeftButtonDown", "RightButtonDown")
    tinsert(UISpecialFrames, "GulliQuickChatWheel")
    local ring = CreateFrame("Frame", "GulliQuickChatRing", wheel)
    ring:SetSize(size, size)
    ring:SetPoint("CENTER")
    wheel.ring = ring
    wheel.disc = S.Circle(ring, size - 20, { 0, 0, 0, 0.55 }, "BACKGROUND", 0)
    wheel.disc:SetPoint("CENTER")
    wheel.track = S.Circle(ring, 2 * ns.WHEEL_R + 4, { 1, 1, 1, 0.06 }, "BACKGROUND", 1)
    wheel.track:SetPoint("CENTER")
    wheel.hole = S.Circle(ring, 2 * ns.WHEEL_R - 4, { 0, 0, 0, 0.35 }, "BACKGROUND", 2)
    wheel.hole:SetPoint("CENTER")
    -- The middle: what the lit place says and where it goes.
    wheel.mid = S.Circle(ring, 196, S.EDGE, "BORDER", 0)
    wheel.mid:SetPoint("CENTER")
    wheel.midFill = S.Circle(ring, 192, S.BG, "BORDER", 1)
    wheel.midFill:SetPoint("CENTER")
    wheel.say = S.Text(ring, 14)
    wheel.say:SetWidth(150)
    wheel.say:SetPoint("CENTER", 0, 8)
    wheel.say:SetJustifyH("CENTER")
    wheel.say:SetMaxLines(3)
    wheel.where = S.Text(ring, 12, S.FAINT)
    wheel.where:SetWidth(150)
    wheel.where:SetJustifyH("CENTER")
    wheel.where:SetPoint("TOP", wheel.say, "BOTTOM", 0, -6)
    wheel.dot = S.Circle(ring, 10, S.Accent(), "ARTWORK", 0)
    wheel.slots = {}
    for i = 1, ns.RING_MAX do
        local slot = CreateFrame("Frame", nil, ring)
        slot:SetSize(WSLOT, WSLOT)
        slot.angle = placeAngle(i)
        slot:SetPoint("CENTER", ring, "CENTER", math.floor(math.cos(slot.angle) * ns.WHEEL_R),
            math.floor(math.sin(slot.angle) * ns.WHEEL_R))
        slot.icon = S.RoundIcon(slot, WSLOT)
        slot.icon:SetPoint("CENTER")
        slot.label = S.Text(slot, 12, S.MUTED)
        slot.label:SetWidth(124)
        slot.label:SetJustifyH("CENTER")
        slot.label:SetMaxLines(2)
        slot.label:SetPoint("TOP", slot, "BOTTOM", 0, -4)
        wheel.slots[i] = slot
    end
    wheel:SetScript("OnUpdate", function()
        local i = pointedSlot()
        if i ~= hovered then wheelSelect(i) end
    end)
    -- Any click on the screen: the left button sends the lit phrase, the right one closes.
    wheel:SetScript("OnClick", function(_, button)
        if button == "RightButton" then wheel:Hide() else ns.WheelRelease() end
    end)
    wheel:Hide() -- a new frame starts shown
end

-- Opens the ring at the cursor. hold: it closes when the key is let go.
function ns.OpenWheel(hold)
    if not wheel then buildWheel() end
    local list = ns.Ring()
    local any = false
    for i, slot in ipairs(wheel.slots) do
        local text = list[i] or nil
        slot.phrase = text
        slot:SetShown(text ~= nil)
        if text then
            any = true
            slot.icon:SetIcon(phraseIcon(text))
            slot.label:SetText(text)
        end
    end
    if not any then return false end
    wheel.hold = hold and true or false
    wheelSelect(nil)
    wheel.ring:ClearAllPoints()
    local x, y
    if GetCursorPosition then x, y = GetCursorPosition() end
    if x and y and x > 0 then
        local scale = UIParent:GetEffectiveScale()
        wheel.ring:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    else
        wheel.ring:SetPoint("CENTER")
    end
    wheel:Show()
    -- The places open one after another around the ring (never in combat or with Reduce motion).
    for i, slot in ipairs(wheel.slots) do
        if slot:IsShown() then S.MotionIn(slot, 0, S.FAST, 0.7, (i - 1) * 0.02) end
    end
    return true
end

-- The key let go, or a click: sends the lit phrase (say, yell and channels into the chat box),
-- or just closes.
function ns.WheelRelease()
    if not wheel or not wheel:IsShown() then return false end
    if hovered then return ns.WheelSend(hovered) end
    wheel:Hide()
    return false
end

-- Opens the ring, or on an open ring sends the lit phrase (the slash command and Try).
function ns.ToggleWheel()
    if wheel and wheel:IsShown() then
        ns.WheelRelease()
        return false
    end
    return ns.OpenWheel(false)
end

-- The key press (down) and release (up) of the wheel key.
function ns.WheelKey(down)
    if down == nil or not ns.db.wheelHold then
        if down ~= false then ns.ToggleWheel() end
        return
    end
    if down then
        if not (wheel and wheel:IsShown()) then ns.OpenWheel(true) end
    elseif wheel and wheel.hold then
        ns.WheelRelease()
    end
end

-- The key: a hidden button the binding clicks, on press and on release. Bindings change only out
-- of combat.
function ns.ApplyKey()
    if not wheelButton then
        wheelButton = CreateFrame("Button", "GulliQuickChatWheelButton", UIParent)
        wheelButton:RegisterForClicks("AnyDown", "AnyUp")
        wheelButton:SetScript("OnClick", function(_, _, down) ns.WheelKey(down) end)
    end
    if InCombatLockdown and InCombatLockdown() then return false end
    if ClearOverrideBindings then ClearOverrideBindings(wheelButton) end
    if ns.db.wheelKey and SetOverrideBindingClick then
        SetOverrideBindingClick(wheelButton, true, ns.db.wheelKey, "GulliQuickChatWheelButton")
    end
    return true
end

---- The panel of favourites -------------------------------------------------------

ns.PANEL_MAX = 10
local PANEL_W = 190

local function phraseButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(PANEL_W - 8, 30)
    S.Box(b, S.CLEAR, S.CLEAR, S.R_MD)
    b.icon = S.IconBox(b, 18)
    b.icon:SetPoint("LEFT", 6, 0)
    b.text = S.Text(b, 12)
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
    b.text:SetPoint("RIGHT", -6, 0)
    b.text:SetWordWrap(false)
    b:SetScript("OnEnter", function(self) S.Fill(self, S.HOVER) end)
    b:SetScript("OnLeave", function(self) S.Fill(self, S.CLEAR) end)
    function b:SetPhrase(text)
        self.text:SetText(text or "")
        self.icon.tex:SetTexture(phraseIcon(text))
    end
    return b
end

local function buildPanel()
    panel = CreateFrame("Frame", "GulliQuickChatPanel", UIParent)
    panel:SetFrameStrata("MEDIUM")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    S.HudPanel(panel)
    panel.buttons = {}
    for i = 1, ns.PANEL_MAX do
        local b = phraseButton(panel)
        b:SetScript("OnClick", function(self) ns.Say(self.phrase) end)
        panel.buttons[i] = b
    end
    S.Mover(panel, { label = L.TITLE, save = function(point, rel, x, y) ns.db.panelPoint = { point, rel, x, y } end,
        reset = function() ns.db.panelPoint = nil; ns.Panel() end })
end

function ns.Panel()
    if not ns.db then return end
    if not ns.db.panelShow and not ns.movingPanel then
        if panel then panel:Hide() end
        return
    end
    if not panel then buildPanel() end
    local list = ns.Favorites(math.min(ns.db.panelCount or 6, ns.PANEL_MAX))
    local row = ns.db.panelRow
    for i, b in ipairs(panel.buttons) do
        b.phrase = list[i]
        b:SetShown(list[i] ~= nil)
        b:ClearAllPoints()
        if row then b:SetPoint("TOPLEFT", 4 + (i - 1) * (PANEL_W - 4), -4)
        else b:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 32) end
        if list[i] then b:SetPhrase(list[i]) end
    end
    local n = math.max(#list, 1)
    if row then panel:SetSize(n * (PANEL_W - 4) + 4, 38) else panel:SetSize(PANEL_W, n * 32 + 8) end
    panel:SetScale((ns.db.panelScale or 100) / 100)
    panel:SetMoving(ns.movingPanel)
    panel:ClearAllPoints()
    local p = ns.db.panelPoint
    if p then panel:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0) else panel:SetPoint("LEFT", 40, 0) end
    panel:Show()
end

-- The hub's Unlock mode: the panel shows and can be placed even when it is off.
function ns.MovePanel(on)
    ns.movingPanel = on and true or nil
    ns.Panel()
end

function ns.PanelFrame()
    if not panel and ns.db then buildPanel() end
    return panel
end

function ns.Setup()
    ns.ApplyKey()
    ns.Panel()
end
