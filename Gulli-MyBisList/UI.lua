-- The window: the gear page (the slots worn round a card with the chosen slot's list) and the
-- settings. It only shows what Core.lua worked out.

local _, ns = ...
local L = ns.L
local S = ns.Skin
local D = ns.Data

local frame, footer, tabs, mainBtn, autoBtn
local pages = {}
local gear = {}         -- the gear page's parts
local current = 1       -- the page tab shown
ns.view = nil           -- the list shown (a ref); nil shows the main list
ns.slot = "head"        -- the slot whose list the card shows

local SLOT_W, SLOT_H, SLOT_GAP, ROW_H = 196, 44, 4, 46
local LEFT = { "head", "neck", "shoulder", "back", "chest", "wrist", "hands" }
local RIGHT = { "waist", "legs", "feet", "finger1", "finger2", "trinket1", "trinket2" }
local WEAPONS = { "main", "off", "ranged" }
local PD = "Interface\\PaperDoll\\UI-PaperDoll-Slot-"
local SLOT_ART = {
    head = "Head", neck = "Neck", shoulder = "Shoulder", back = "Chest", chest = "Chest", wrist = "Wrists",
    hands = "Hands", waist = "Waist", legs = "Legs", feet = "Feet", finger1 = "Finger", finger2 = "Finger",
    trinket1 = "Trinket", trinket2 = "Trinket", main = "MainHand", off = "SecondaryHand", ranged = "Ranged",
}
local STAR_ON, STAR_OFF = "Interface\\Icons\\INV_Misc_Gem_Topaz_02", "Interface\\Icons\\INV_Misc_Gem_Topaz_01"

function ns.ClassIcon(class)
    return "Interface\\Icons\\ClassIcon_" .. class:sub(1, 1) .. class:sub(2):lower()
end

local function colour(text, c) return S.Hex(c) .. text .. "|r" end

-- The state of a slot as a short line and its colour (never by colour alone: a word goes with it).
function ns.StateText(r)
    if r.state == "bis" then return L.ST_BIS, S.GOOD end
    if r.state == "bag" then return L.ST_BAG:format(r.haveRank), S.WARN end
    if r.state == "rank" then return L.ST_RANK:format(r.rank, #r.ids), S.TEXT end
    if r.state == "miss" then return r.worn and L.ST_OFF or L.ST_EMPTY, S.MUTED end
    if r.state == "covered" then return L.ST_COVERED, S.FAINT end
    return L.ST_NONE, S.FAINT
end

local function itemTip(self)
    local id = self.itemId
    if not (GameTooltip and id) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then GameTooltip:SetItemByID(id) end
    GameTooltip:Show()
end
local function hideTip() if GameTooltip then GameTooltip:Hide() end end

-- The list shown --------------------------------------------------------------------------------------

function ns.ViewRef() return ns.view or ns.MainRef() end
function ns.Shown() return ns.Resolve(ns.ViewRef()) or ns.Resolve("auto") end

-- Shows a site list of a spec at a stage.
function ns.ViewList(spec, stage)
    if not ns.SpecInfo(spec) then return end
    stage = stage or (ns.Shown() or {}).stage or ns.AutoStage()
    if not (D.lists[spec] and D.lists[spec][stage]) then stage = "PRE" end
    ns.view = ns.Ref(spec, stage)
    ns.Refresh()
end

-- The site ref of what is shown (the main list may be "auto").
function ns.ShownRef()
    local list = ns.Shown()
    return list and ns.Ref(list.spec, list.stage)
end

-- The slot buttons -------------------------------------------------------------------------------------

local function slotButton(parent, slot)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(SLOT_W, SLOT_H)
    S.Box(b, S.SURFACE, S.CARD_EDGE, S.R_LG)
    b.slot = slot
    b.icon = S.IconBox(b, 34)
    b.icon:SetPoint("LEFT", 8, 0)
    b.name = S.Text(b, 12, S.GOLD_DIM, nil, "bold")
    b.name:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 8, -1)
    b.name:SetPoint("RIGHT", -8, 0)
    b.name:SetJustifyH("LEFT")
    b.name:SetWordWrap(false)
    b.name:SetText(S.Upper(L["SLOT_" .. slot]))
    b.state = S.Text(b, 12, S.MUTED)
    b.state:SetPoint("BOTTOMLEFT", b.icon, "BOTTOMRIGHT", 8, 1)
    b.state:SetPoint("RIGHT", -8, 0)
    b.state:SetJustifyH("LEFT")
    b.state:SetWordWrap(false)
    b:SetScript("OnClick", function(self) ns.slot = self.slot; ns.Refresh() end)
    b:SetScript("OnEnter", function(self)
        if self.itemId then itemTip(self) end
        if not self.selected then S.Fill(self, S.RAISED) end
    end)
    b:SetScript("OnLeave", function(self)
        hideTip()
        S.Fill(self, self.selected and { S.FILL[1], S.FILL[2], S.FILL[3], 0.34 } or S.SURFACE)
    end)
    return b
end

local function paintSlot(b, r)
    b.row = r
    b.itemId = r.worn
    b.icon:SetIcon(r.worn and ns.ItemIcon(r.worn) or (PD .. SLOT_ART[r.slot]))
    local text, c = ns.StateText(r)
    b.state:SetText(text)
    b.state:SetTextColor(c[1], c[2], c[3], 1)
    b.icon:SetGlow((r.state == "bis" and S.GOOD) or (r.state == "bag" and S.WARN) or nil)
    b.icon:SetAlpha(r.counted and 1 or 0.45)
    b.selected = ns.slot == r.slot
    S.Fill(b, b.selected and { S.FILL[1], S.FILL[2], S.FILL[3], 0.34 } or S.SURFACE)
    S.SetBorder(b, b.selected and S.FILL_EDGE or S.CARD_EDGE)
end

-- The card of the chosen slot --------------------------------------------------------------------------

local function makeRow(r)
    r.rank = S.Text(r, 14, S.MUTED, nil, "bold")
    r.rank:SetPoint("LEFT", 4, 0)
    r.rank:SetWidth(22)
    r.rank:SetJustifyH("CENTER")
    r.icon = S.IconBox(r, 32)
    r.icon:SetPoint("LEFT", 30, 0)
    r.tag = S.Text(r, 12, S.MUTED)
    r.tag:SetPoint("RIGHT", -8, 0)
    r.tag:SetJustifyH("RIGHT")
    r.tag:SetWordWrap(false)
    r.name = S.Text(r, 13)
    r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 9, 0)
    r.name:SetPoint("RIGHT", r.tag, "LEFT", -6, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.src = S.Text(r, 12, S.MUTED)
    r.src:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 9, 0)
    r.src:SetPoint("RIGHT", r.tag, "LEFT", -6, 0)
    r.src:SetJustifyH("LEFT")
    r.src:SetWordWrap(false)
    r.hit = CreateFrame("Button", nil, r)
    r.hit:SetAllPoints()
    r.hit:SetScript("OnEnter", function(self) S.Fill(r, S.HOVER); itemTip(self) end)
    r.hit:SetScript("OnLeave", function() S.Fill(r, S.CLEAR); hideTip() end)
    r.hit:SetScript("OnClick", function(self)
        -- Shift-click links the item in chat, like the game's own lists
        if IsModifiedClick and IsModifiedClick("CHATLINK") and self.itemId then
            local info = C_Item and C_Item.GetItemInfo
            local _, link
            if info then _, link = info(self.itemId) elseif GetItemInfo then _, link = GetItemInfo(self.itemId) end
            local insert = ChatFrameUtil and ChatFrameUtil.InsertLink or ChatEdit_InsertLink
            if link and insert then insert(link) end
        end
    end)
end

local function fillRow(r, it)
    r.hit.itemId = it.id
    r.rank:SetText(tostring(it.rank))
    r.rank:SetTextColor(unpack(it.rank == 1 and S.GOLD or S.MUTED))
    r.icon:SetIcon(ns.ItemIcon(it.id))
    r.icon:SetGlow(S.QUALITY[ns.ItemQuality(it.id)])
    r.name:SetText(S.QualityHex(ns.ItemQuality(it.id)) .. ns.ItemName(it.id) .. "|r")
    local src = ns.SourceText(it.id)
    r.src:SetText(src)
    local need = ns.NeedsLevel(it.id)
    if it.worn then
        r.tag:SetText(colour(L.TAG_WORN, S.GOOD))
    elseif it.have then
        r.tag:SetText(colour(L.TAG_BAG, S.WARN))
    elseif need then
        r.tag:SetText(colour(L.TAG_LEVEL:format(need), S.MUTED))
    else
        r.tag:SetText("")
    end
end

local function buildCard(parent)
    local c = S.Card(parent, L["SLOT_head"])
    c.count = S.Text(c.body, 20, S.TEXT, nil, "bold")
    c.count:SetPoint("TOPLEFT", 0, 0)
    c.countLabel = S.Text(c.body, 12, S.MUTED)
    c.countLabel:SetPoint("LEFT", c.count, "RIGHT", 8, -1)
    c.countLabel:SetPoint("RIGHT", 0, 0)
    c.countLabel:SetJustifyH("LEFT")
    c.countLabel:SetWordWrap(false)
    c.bar = S.Progress(c.body, 6)
    c.bar:SetPoint("TOPLEFT", 0, -28)
    c.bar:SetPoint("TOPRIGHT", 0, -28)
    c.list = S.List(c.body, ROW_H, makeRow, fillRow)
    c.list:SetPoint("TOPLEFT", 0, -44)
    c.list:SetPoint("BOTTOMRIGHT", 0, 24)
    c.empty = S.Text(c.body, 12, S.MUTED)
    c.empty:SetPoint("TOPLEFT", 0, -56)
    c.empty:SetPoint("RIGHT", 0, 0)
    c.empty:SetJustifyH("LEFT")
    c.ench = S.Text(c.body, 12, S.MUTED)
    c.ench:SetPoint("BOTTOMLEFT", 0, 2)
    c.ench:SetPoint("RIGHT", 0, 0)
    c.ench:SetJustifyH("LEFT")
    c.ench:SetWordWrap(false)
    return c
end

-- The rows of a slot's list for the card: { rank, id, worn, have }.
function ns.CardItems(list, r)
    local out = {}
    for i, id in ipairs(r.ids) do
        out[#out + 1] = { rank = i, id = id, worn = r.worn == id, have = r.have == id }
    end
    return out
end

-- The spec picker ------------------------------------------------------------------------------------

local picker
local function pickRow(r)
    S.NavRow(r)
    r.head = S.Text(r, 12, S.GOLD_DIM, nil, "bold")
    r.head:SetPoint("BOTTOMLEFT", 8, 4)
    r.head:SetPoint("RIGHT", -8, 0)
    r.head:SetJustifyH("LEFT")
    r.icon = S.IconBox(r, 20)
    r.icon:SetPoint("LEFT", 8, 0)
    r.name = S.Text(r, 13)
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
    r.name:SetPoint("RIGHT", -8, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.hit = CreateFrame("Button", nil, r)
    r.hit:SetAllPoints()
    r.hit:SetScript("OnClick", function(self)
        local it = self:GetParent().item
        if not it then return end
        picker:Hide()
        if it.stage then ns.ViewList(it.spec, it.stage) else ns.ViewList(it.spec) end
    end)
end
local function pickFill(r, it)
    r.item = not it.head and it or nil
    r.head:SetShown(it.head ~= nil)
    r.icon:SetShown(not it.head)
    r.name:SetShown(not it.head)
    r.hit:SetShown(not it.head)
    r.line:SetShown(not it.head)
    if it.head then r.head:SetText(S.Upper(it.head)); r:SetSelected(false); return end
    local s = ns.SpecInfo(it.spec)
    r.icon:SetIcon(it.stage and STAR_ON or ns.ROLE_ICON[s[3]])
    local text = ns.SpecName(it.spec) .. "  " .. colour(ns.ClassName(s[2]), S.FAINT)
    if it.stage then text = text .. colour(" · " .. ns.StageName(it.stage), S.FAINT) end
    r.name:SetText(text)
    local shown = ns.Shown()
    r:SetSelected(shown and shown.spec == it.spec and (not it.stage or shown.stage == it.stage) or false)
end

-- Favourites first, then this class's specs, then every other class.
function ns.PickItems()
    local out = {}
    local favs = ns.Favs()
    if #favs > 0 then
        out[#out + 1] = { head = L.PICK_FAV }
        for _, f in ipairs(favs) do out[#out + 1] = { spec = f.spec, stage = f.stage } end
    end
    local _, mine = UnitClass("player")
    local order = { mine }
    for _, c in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
        if c ~= mine then order[#order + 1] = c end
    end
    for _, class in ipairs(order) do
        local specs = ns.Specs(class)
        if #specs > 0 then
            out[#out + 1] = { head = ns.ClassName(class) }
            for _, s in ipairs(specs) do out[#out + 1] = { spec = s[1] } end
        end
    end
    return out
end

local function buildPicker(anchor)
    local p = CreateFrame("Frame", nil, frame)
    p:SetSize(300, 380)
    p:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    if p.SetToplevel then p:SetToplevel(true) end
    p:EnableMouse(true)
    S.Box(p, S.SOLID, S.EDGE, S.R_LG)
    p.list = S.List(p, 30, pickRow, pickFill)
    p.list:SetPoint("TOPLEFT", 6, -6)
    p.list:SetPoint("BOTTOMRIGHT", -6, 6)
    p:Hide()
    return p
end

-- The gear page ----------------------------------------------------------------------------------------

local STAGE_TABS = { "L20", "L30", "L40", "L50", "PRE" }

local function gearPage(body)
    local p = CreateFrame("Frame", nil, body)
    -- the bar over the slots: which list, its stage, the star
    local chip = S.Button(p, 200, 30)
    S.SetButtonIcon(chip, ns.ROLE_ICON.dps)
    chip:SetPoint("TOPLEFT", 0, 0)
    chip:SetScript("OnClick", function(self)
        picker = picker or buildPicker(self)
        if picker:IsShown() then picker:Hide(); return end
        picker:Show()
        picker.list:SetData(ns.PickItems())
    end)
    gear.chip = chip
    local labels = {}
    for i, s in ipairs(STAGE_TABS) do labels[i] = L["STAGE_TAB_" .. s] end
    gear.stages = S.Tabs(p, labels, 72, function(i)
        local list = ns.Shown()
        if list then ns.ViewList(list.spec, STAGE_TABS[i]) end
    end, 30)
    gear.stages.frame:ClearAllPoints()
    gear.stages.frame:SetPoint("LEFT", chip, "RIGHT", S.GAP, 0)
    gear.star = S.Button(p, 30, 30)
    S.SetButtonIcon(gear.star, STAR_OFF, 18)
    gear.star.btnIcon:ClearAllPoints()
    gear.star.btnIcon:SetPoint("CENTER")
    gear.star:SetPoint("TOPRIGHT", 0, 0)
    gear.star:SetScript("OnClick", function()
        local ref = ns.ShownRef()
        if ref then ns.SetFav(ref, not ns.IsFav(ref)) end
    end)
    gear.star:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(ns.IsFav(ns.ShownRef()) and L.FAV_OFF or L.FAV_ON)
        GameTooltip:Show()
    end)
    gear.star:SetScript("OnLeave", hideTip)
    gear.real = S.SwitchLabel(p, L.REALISTIC, function()
        local list = ns.Shown()
        return list ~= nil and list.stage == "REAL"
    end, function(v)
        local list = ns.Shown()
        if list then ns.ViewList(list.spec, v and "REAL" or "PRE") end
    end, 140)
    gear.real:SetPoint("RIGHT", gear.star, "LEFT", -152, 0)

    local area = CreateFrame("Frame", nil, p)
    area:SetPoint("TOPLEFT", 0, -30 - S.GAP)
    area:SetPoint("BOTTOMRIGHT")
    gear.slots = {}
    for i, slot in ipairs(LEFT) do
        local b = slotButton(area, slot)
        b:SetPoint("TOPLEFT", 0, -(i - 1) * (SLOT_H + SLOT_GAP))
        gear.slots[slot] = b
    end
    for i, slot in ipairs(RIGHT) do
        local b = slotButton(area, slot)
        b:SetPoint("TOPRIGHT", 0, -(i - 1) * (SLOT_H + SLOT_GAP))
        gear.slots[slot] = b
    end
    local card = buildCard(area)
    card:SetPoint("TOPLEFT", SLOT_W + S.GAP, 0)
    card:SetPoint("BOTTOMRIGHT", -(SLOT_W + S.GAP), SLOT_H + S.GAP)
    gear.card = card
    -- the weapons under everything, as wide as the page, so their lines fit in every language
    local ww = math.floor((S.WIDE_W - 2 * S.PAD - 2 * S.GAP) / 3)
    for i, slot in ipairs(WEAPONS) do
        local b = slotButton(area, slot)
        b:SetWidth(ww)
        b:SetPoint("BOTTOMLEFT", (i - 1) * (ww + S.GAP), 0)
        gear.slots[slot] = b
    end
    return p
end

local function paintGear()
    local list = ns.Shown()
    if not list then return end
    local rows = ns.SlotRows(list)
    local byslot = {}
    for _, r in ipairs(rows) do
        byslot[r.slot] = r
        paintSlot(gear.slots[r.slot], r)
    end
    local spec = ns.SpecInfo(list.spec)
    gear.chip:SetText(ns.SpecName(list.spec))
    if gear.chip.btnIcon then gear.chip.btnIcon:SetTexture(ns.ClassIcon(spec[2])) end
    local stage = list.stage == "REAL" and "PRE" or list.stage
    for i, s in ipairs(STAGE_TABS) do
        if s == stage then gear.stages:Select(i, true) end
        gear.stages.buttons[i]:SetEnabled(D.lists[list.spec][s] ~= nil)
    end
    local pre = list.stage == "PRE" or list.stage == "REAL"
    gear.real:SetShown(pre and D.lists[list.spec].REAL ~= nil)
    gear.real:SetChecked(list.stage == "REAL")
    local fav = ns.IsFav(ns.Ref(list.spec, list.stage))
    if gear.star.btnIcon then
        gear.star.btnIcon:SetTexture(fav and STAR_ON or STAR_OFF)
        gear.star.btnIcon:SetAlpha(fav and 1 or 0.5)
    end

    local r = byslot[ns.slot] or rows[1]
    local c = gear.card
    local have, of = ns.Progress(list)
    c:SetTitle(L["SLOT_" .. r.slot], ns.ListName(list))
    c.count:SetText(have .. "/" .. of)
    c.countLabel:SetText(L.BIS_WORN)
    c.bar:Set(of > 0 and have / of or 0, have == of and of > 0 and S.GOOD or nil)
    local items = ns.CardItems(list, r)
    c.list:SetData(items)
    c.list:SetShown(#items > 0)
    c.empty:SetShown(#items == 0)
    c.empty:SetText(r.state == "covered" and L.EMPTY_COVERED or L.EMPTY_SLOT)
    local ench = list.ench[r.slot]
    c.ench:SetText(ench and (L.ENCHANT .. " " .. colour(ench, S.TEXT)) or "")
end

-- Settings ---------------------------------------------------------------------------------------------

local function settingsPage(body, width)
    local page = S.ScrollPage(body, width)
    local st = S.Stack(page.inner)
    local function row(key)
        local up = key:upper()
        return { L["OPT_" .. up], L["OPT_" .. up .. "_TIP"], function() return ns.db[key] end,
                 function(v) ns.SetPref(key, v) end, icon = ns.OPT_ICON[key] }
    end
    for _, sec in ipairs({ { L.SEC_MAIN, { "real" } }, { L.SEC_NOTICES, { "tooltip", "notify" } } }) do
        local rows = {}
        for _, k in ipairs(sec[2]) do rows[#rows + 1] = row(k) end
        local card, h = S.SettingsCard(page.inner, sec[1], rows)
        st:Add(card, h)
    end
    local about = S.Card(page.inner, L.SEC_ABOUT, nil, ns.ICON)
    about.text = S.Text(about.body, 12, S.MUTED)
    about.text:SetPoint("TOPLEFT")
    about.text:SetPoint("RIGHT")
    about.text:SetJustifyH("LEFT")
    about.text:SetText(L.ABOUT:format(D.ver))
    st:Add(about, about:Fit(54))
    page:SetContent(st:Height())
    return page
end

-- The window -------------------------------------------------------------------------------------------

local function paintFooter()
    local list = ns.Shown()
    if not list then return end
    local isMain = ns.ShownRef() == ns.MainRef() or (ns.view == nil)
    local sim = list.simmed and L.SIMMED or L.NOT_SIMMED
    footer:SetStatus(L.STATUS:format(D.ver, sim))
    if isMain then
        mainBtn:SetText(ns.MainRef() == "auto" and L.MAIN_AUTO or L.MAIN_IS)
        mainBtn:SetEnabled(false)
    else
        mainBtn:SetText(L.MAKE_MAIN)
        mainBtn:SetEnabled(true)
    end
    mainBtn:SetWidth(math.max(150, math.floor((mainBtn.text:GetStringWidth() or 0) + 40)))
    autoBtn:SetShown(ns.MainRef() ~= "auto")
end

function ns.Refresh()
    if not ns.db then return end
    if not (frame and frame:IsShown()) then return end
    if current == 1 then paintGear() end
    paintFooter()
end

local function build()
    frame = S.Window("GulliMyBisListFrame", L.TITLE, S.WIDE_W, S.DOCK_H)
    local body, width = frame.body, frame.inner[1]
    footer = S.Footer(frame)
    mainBtn = S.Primary(S.Button(frame, 180, 30))
    mainBtn:SetScript("OnClick", function()
        local ref = ns.ShownRef()
        if ref then ns.SetMain(ref); ns.view = nil; ns.Refresh() end
    end)
    footer:Add(mainBtn)
    autoBtn = S.Button(frame, 150, 30)
    autoBtn:SetText(L.BACK_AUTO)
    autoBtn:SetWidth(math.max(120, math.floor((autoBtn.text:GetStringWidth() or 0) + 32)))
    autoBtn:SetScript("OnClick", function() ns.SetMain("auto"); ns.view = nil; ns.Refresh() end)
    footer:Add(autoBtn)
    tabs = S.PageTabs(body, { L.TAB_GEAR, L.TAB_SETTINGS }, nil, function(i)
        current = i
        for j, p in ipairs(pages) do p:SetShown(j == i) end
        if picker then picker:Hide() end
        footer:SetShown(i ~= 2)
        ns.Refresh()
    end, nil, { "Interface\\Icons\\INV_Chest_Plate06", S.TAB.settings })
    pages[1] = gearPage(body)
    pages[2] = settingsPage(body, width)
    for i, p in ipairs(pages) do
        p:SetPoint("TOPLEFT", 0, -(30 + S.GAP))
        p:SetPoint("BOTTOMRIGHT")
        p:SetShown(i == 1)
    end
    frame:HookScript("OnShow", function() ns.Refresh() end)
    frame:HookScript("OnHide", function() if picker then picker:Hide() end end)
end

function ns.Toggle()
    if S.ToggleWindow(ns.Window()) then ns.Refresh() end
end

-- Opens the window on the main list at one slot (a notice's button).
function ns.Show(slot)
    local f = ns.Window()
    if not f:IsShown() then ns.Toggle() end
    tabs:Select(1)
    ns.view = nil
    if slot then ns.slot = slot end
    ns.Refresh()
end

-- The window, for the hub (/gulli) to show inside it.
function ns.Window()
    if not frame then build() end
    return frame
end

-- For the tests and the previews.
function ns.Parts() return gear, footer, mainBtn, tabs end
function ns.ShowTab(i) ns.Window(); tabs:Select(i) end
