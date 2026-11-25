-- The window: the gear page (the slots worn round a card with the chosen slot's list), the sets
-- page (the sets of a class, and the chosen one piece by piece) and the settings. It only shows what Core.lua worked out.

local _, ns = ...
local L = ns.L
local S = ns.Skin
local D = ns.Data

local frame, footer, tabs, mainBtn, autoBtn, copyBtn, delBtn, statBar
local pages = {}
local gear = {}         -- the gear page's parts
local sets = {}         -- the sets page's parts
local SETS, SETTINGS = 2, 3
ns.setClass = nil       -- the class whose sets are shown; nil is the character's
ns.setId = nil          -- the set shown
local current = 1       -- the page tab shown
ns.view = nil           -- the list shown (a ref); nil shows the main list
ns.slot = "head"        -- the slot whose list the card shows

local SLOT_W, SLOT_H, SLOT_GAP, ROW_H = 196, 44, 4, 40
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
local OWN_ICON = "Interface\\Icons\\INV_Misc_Note_05"
local DEL = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"
local TARGET = "Interface\\Icons\\Ability_Hunter_SniperShot"
local SEP_H = 16        -- the line over what is worn when it is not on the list

function ns.ClassIcon(class)
    return "Interface\\Icons\\ClassIcon_" .. class:sub(1, 1) .. class:sub(2):lower()
end

local function colour(text, c) return S.Hex(c) .. text .. "|r" end

-- The state of a slot as a short line and its colour (never by colour alone: a word goes with it).
-- Where the list's first item is: its colour and the word for the tooltip.
ns.AT_COLOR = { worn = S.GOOD, bag = S.WARN, alt = S.WARN, miss = S.BAD }

-- The slot's tooltip lines of where the first item is; with "alt", which item of the list the
-- player has instead and where.
function ns.AtLines(r)
    local at = r and r.topAt
    if not at then return {} end
    if at ~= "alt" then return { { L["AT_" .. at:upper()], ns.AT_COLOR[at] } } end
    local name = S.QualityHex(ns.ItemQuality(r.alt)) .. ns.ItemName(r.alt) .. "|r"
    return { { L.AT_MISS, S.BAD }, { L.AT_ALT:format(r.altRank, name), S.WARN },
             { L["AT_" .. r.altAt:upper()], S.MUTED } }
end
function ns.TopText(r)
    if r.state == "covered" then return L.ST_COVERED, S.FAINT end
    if not r.top then return L.ST_NONE, S.FAINT end
    return S.QualityHex(ns.ItemQuality(r.top)) .. ns.ItemName(r.top) .. "|r", ns.AT_COLOR[r.topAt]
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

-- Shows a list by its ref (an own list, or a site ref).
function ns.ViewRefSet(ref)
    if not ns.Resolve(ref) then return end
    ns.view = ref
    ns.Refresh()
end

-- Shows a site list of a spec at a stage.
function ns.ViewList(spec, stage)
    if not ns.SpecInfo(spec) then return end
    stage = stage or (ns.Shown() or {}).stage or ns.AutoStage()
    if not (D.lists[spec] and D.lists[spec][stage]) then stage = "PRE" end
    ns.view = ns.Ref(spec, stage)
    ns.Refresh()
end

-- The site ref of what is shown (the main list may be "auto").
function ns.ShownRef() return ns.RefOf(ns.Shown()) end

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
    b.dot = S.Circle(b, 8, S.BAD, "OVERLAY")
    b.dot:SetPoint("BOTTOMLEFT", b.icon, "BOTTOMRIGHT", 8, 4)
    b.state = S.Text(b, 12, S.MUTED)
    b.state:SetPoint("BOTTOMLEFT", b.icon, "BOTTOMRIGHT", 20, 1)
    b.state:SetPoint("RIGHT", -8, 0)
    b.state:SetJustifyH("LEFT")
    b.state:SetWordWrap(false)
    -- the list's enchant of the slot: its icon in the corner, bright in a green ring when the worn
    -- item has an enchant, grey in a red ring when it has none (the words are in the tooltip)
    b.ench = S.IconBox(b, 16)
    b.ench:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", 5, -3)
    b.ench:SetFrameLevel((tonumber(b.icon:GetFrameLevel()) or 1) + 2)
    b.ench:Hide()
    b:SetScript("OnClick", function(self) ns.slot = self.slot; ns.Refresh() end)
    b:SetScript("OnEnter", function(self)
        local e = self.enchant
        if self.itemId then
            itemTip(self)
            if GameTooltip then
                for _, line in ipairs(ns.AtLines(self.row)) do
                    local c = line[2]
                    GameTooltip:AddLine(line[1], c[1], c[2], c[3])
                end
            end
        elseif e and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["SLOT_" .. self.slot])
        end
        if e and GameTooltip then
            -- the Gulli block names the enchant itself for an item of the main list
            if not (self.itemId and ns.EnchantInTip()) then
                GameTooltip:AddLine(S.Cap(L.TIP_ENCH) .. ": " .. colour(e.name, S.TEXT), S.MUTED[1], S.MUTED[2], S.MUTED[3])
            end
            local c = ns.ENCH_COLOR[e.state or "empty"]
            GameTooltip:AddLine(L["ENCH_" .. (e.state or "empty"):upper()], c[1], c[2], c[3])
        end
        if GameTooltip and (self.itemId or e) then GameTooltip:Show() end
        if not self.selected then S.Fill(self, S.RAISED) end
    end)
    b:SetScript("OnLeave", function(self)
        hideTip()
        S.Fill(self, self.selected and { S.FILL[1], S.FILL[2], S.FILL[3], 0.34 } or S.SURFACE)
    end)
    return b
end

-- The badge and the row of an enchant: its icon, bright or grey, in a ring of its state's colour.
ns.ENCH_COLOR = { on = S.GOOD, none = S.BAD, empty = S.MUTED }
local function paintEnchant(box, e)
    box:SetIcon(e.icon)
    if box.tex.SetDesaturated then box.tex:SetDesaturated(e.state ~= "on") end
    box.tex:SetAlpha(e.state == "on" and 1 or 0.7)
    box:SetGlow(e.state and ns.ENCH_COLOR[e.state] or nil)
end

-- Whether the Gulli block of an item's tooltip already names the shown list's enchants.
function ns.EnchantInTip()
    return ns.db ~= nil and ns.db.tooltip == true and not ns.paused and ns.ShownRef() == ns.RefOf(ns.Main())
end

local function paintSlot(b, r, list)
    b.row = r
    local e = r.state ~= "covered" and ns.Enchant(list, r.slot) or nil
    b.enchant = e
    b.ench:SetShown(e ~= nil)
    if e then paintEnchant(b.ench, e) end
    local top = r.state ~= "covered" and r.top or nil
    b.itemId = top
    b.icon:SetIcon(top and ns.ItemIcon(top) or (PD .. SLOT_ART[r.slot]))
    local text, c = ns.TopText(r)
    b.state:SetText(text)
    b.state:SetTextColor(1, 1, 1, 1)
    if top then
        b.dot:SetVertexColor(c[1], c[2], c[3], 1)
        b.state:SetPoint("BOTTOMLEFT", b.icon, "BOTTOMRIGHT", 20, 1)
    else
        b.state:SetTextColor(c[1], c[2], c[3], 1)
        b.state:SetPoint("BOTTOMLEFT", b.icon, "BOTTOMRIGHT", 8, 1)
    end
    b.dot:SetShown(top ~= nil)
    b.icon:SetGlow(top and c or nil)
    b.icon:SetAlpha(r.counted and 1 or 0.45)
    b.selected = ns.slot == r.slot
    S.Fill(b, b.selected and { S.FILL[1], S.FILL[2], S.FILL[3], 0.34 } or S.SURFACE)
    S.SetBorder(b, b.selected and S.FILL_EDGE or S.CARD_EDGE)
end

-- The card of the chosen slot --------------------------------------------------------------------------

local function makeRow(r)
    r.body = CreateFrame("Frame", nil, r)
    r.body:SetPoint("BOTTOMLEFT")
    r.body:SetPoint("BOTTOMRIGHT")
    r.body:SetHeight(ROW_H)
    r.rank = S.Text(r, 14, S.MUTED, nil, "bold")
    r.rank:SetPoint("LEFT", r.body, "LEFT", 4, 0)
    r.rank:SetWidth(22)
    r.rank:SetJustifyH("CENTER")
    r.icon = S.IconBox(r, 30)
    r.icon:SetPoint("LEFT", r.body, "LEFT", 30, 0)
    -- an own list's row: up, down, remove (the hit area lies under them)
    r.tools = CreateFrame("Frame", nil, r)
    r.tools:SetPoint("RIGHT", r.body, "RIGHT", -4, 0)
    r.tools:SetSize(1, 26)
    local function tool(icon, tip, fn)
        local b = S.Button(r.tools, 26, 26)
        S.SetButtonIcon(b, icon, 14)
        b.btnIcon:ClearAllPoints()
        b.btnIcon:SetPoint("CENTER")
        b:SetScript("OnClick", function() local it = r.item; if it then fn(it) end end)
        b:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(tip)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", hideTip)
        return b
    end
    -- "My target": the same button on every row but the first
    r.aim = tool(TARGET, L.TARGET, function(it) ns.SetTarget(ns.ShownRef(), it.slot, it.id) end)
    r.aim:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L.TARGET)
        GameTooltip:AddLine(L.TARGET_TIP, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    r.sep = S.Text(r, 12, S.MUTED, nil, "bold")
    r.sep:SetPoint("TOPLEFT", 4, -2)
    r.sep:SetPoint("TOPRIGHT", -4, -2)
    r.sep:SetJustifyH("LEFT")
    r.sep:SetWordWrap(false)
    r.sep:SetText(S.Upper(L.WORN_NOW))
    r.sepLine = S.Divider(r)
    r.sepLine:SetPoint("TOPLEFT", 0, 0)
    r.sepLine:SetPoint("TOPRIGHT", 0, 0)
    r.sepLine:SetHeight(1)
    r.del = tool(DEL, L.REMOVE, function(it) ns.OwnRemove(it.ref, it.slot, it.id) end)
    r.aim:SetPoint("LEFT", 0, 0)
    r.del:SetPoint("LEFT", r.aim, "RIGHT", 2, 0)
    r.tag = S.Text(r, 12, S.MUTED)
    r.tag:SetPoint("TOPRIGHT", r.tools, "TOPLEFT", -4, 3)
    r.tag:SetJustifyH("RIGHT")
    r.tag:SetWordWrap(false)
    r.dot = S.Circle(r, 8, S.BAD, "OVERLAY")
    r.dot:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 9, -4)
    r.name = S.Text(r, 13)
    r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 21, 0)
    r.name:SetPoint("RIGHT", r.tag, "LEFT", -6, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.src = S.Text(r, 12, S.MUTED)
    r.src:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 9, 0)
    r.src:SetPoint("RIGHT", r.tools, "LEFT", -6, 0)
    r.src:SetJustifyH("LEFT")
    r.src:SetWordWrap(false)
    r.hit = CreateFrame("Button", nil, r)
    r.hit:SetAllPoints()
    r.hit:SetFrameLevel((tonumber(r:GetFrameLevel()) or 1))
    r.tools:SetFrameLevel((tonumber(r:GetFrameLevel()) or 1) + 2)
    r.hit:SetScript("OnEnter", function(self)
        S.Fill(r, S.HOVER)
        itemTip(self)
        local c = self.at and ns.AT_COLOR[self.at]
        if c and GameTooltip then
            GameTooltip:AddLine(L["AT_" .. self.at:upper()], c[1], c[2], c[3])
            GameTooltip:Show()
        end
    end)
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
    r.item = it
    r.hit.itemId = it.id
    local own = it.ref ~= nil
    local onList = it.rank ~= nil
    r.sep:SetShown(it.sep == true)
    r.sepLine:SetShown(it.sep == true)
    -- every row but the first: "My target"; an own list's rows also up, down, remove
    local edit = own and onList
    local aim = it.rank ~= 1
    r.aim:SetShown(aim)
    r.del:SetShown(edit)
    r.del:ClearAllPoints()
    if aim then r.del:SetPoint("LEFT", r.aim, "RIGHT", 2, 0) else r.del:SetPoint("LEFT", 0, 0) end
    r.tools:SetWidth((aim and 28 or 0) + (edit and 28 or 0) + 1)
    r.rank:SetText(onList and tostring(it.rank) or "")
    r.rank:SetTextColor(unpack(it.rank == 1 and S.GOLD or S.MUTED))
    r.icon:SetIcon(ns.ItemIcon(it.id))
    r.icon:SetGlow(S.QUALITY[ns.ItemQuality(it.id)])
    r.name:SetText(S.QualityHex(ns.ItemQuality(it.id)) .. ns.ItemName(it.id) .. "|r")
    local src = ns.SourceText(it.id)
    r.src:SetText(src)
    local need = ns.NeedsLevel(it.id)
    -- where it is: a dot (its word in the tooltip), and the level it needs while too high
    r.at = it.worn and "worn" or (it.have and "bag") or "miss"
    local c = ns.AT_COLOR[r.at]
    r.dot:SetVertexColor(c[1], c[2], c[3], 1)
    r.hit.at = r.at
    r.tag:SetText(need and colour(L.TAG_LEVEL:format(need), S.MUTED) or "")
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
    c.list.heightOf = function(it) return it.sep and ROW_H + SEP_H or ROW_H end
    c.list:SetPoint("TOPLEFT", 0, -44)
    c.list:SetPoint("BOTTOMRIGHT", 0, 0)
    c.empty = S.Text(c.body, 12, S.MUTED)
    c.empty:SetPoint("TOPLEFT", 0, -56)
    c.empty:SetPoint("RIGHT", 0, 0)
    c.empty:SetJustifyH("LEFT")
    c.news = S.Banner(c.body, "Interface\\Icons\\INV_Misc_Note_01")
    c.news:SetPoint("TOPLEFT", 0, -44)
    c.news:SetPoint("TOPRIGHT", 0, -44)
    c.news.onClose = function() ns.AckNews(ns.ShownRef()) end
    c.add = S.FitButton(c.body, L.ADD_ITEM, 26, 100)
    S.SetButtonIcon(c.add, "Interface\\Icons\\INV_Misc_Spyglass_03", 14)
    c.add:SetWidth(c.add:GetWidth() + 22)
    c.add:SetPoint("TOPRIGHT", 0, 2)
    c.add:SetScript("OnClick", function(self) ns.OpenAdd(self) end)
    -- the slot's enchant, under the list: who makes it, its icon and name, and what is on the worn item
    local e = CreateFrame("Button", nil, c.body)
    e:SetHeight(ROW_H)
    e:SetPoint("BOTTOMLEFT", 0, 0)
    e:SetPoint("BOTTOMRIGHT", 0, 0)
    e.line = S.Divider(e)
    e.line:SetPoint("TOPLEFT", 0, 0)
    e.line:SetPoint("TOPRIGHT", 0, 0)
    e.line:SetHeight(1)
    e.kind = S.IconBox(e, 16)
    e.kind:SetPoint("LEFT", 7, 0)
    e.icon = S.IconBox(e, 30)
    e.icon:SetPoint("LEFT", 30, 0)
    e.src = S.Text(e, 12, S.MUTED)
    e.src:SetPoint("TOPRIGHT", -4, -6)
    e.src:SetJustifyH("RIGHT")
    e.src:SetWordWrap(false)
    e.name = S.Text(e, 13)
    e.name:SetPoint("TOPLEFT", e.icon, "TOPRIGHT", 9, 0)
    e.name:SetPoint("RIGHT", e.src, "LEFT", -6, 0)
    e.name:SetJustifyH("LEFT")
    e.name:SetWordWrap(false)
    e.dot = S.Circle(e, 8, S.BAD, "OVERLAY")
    e.dot:SetPoint("BOTTOMLEFT", e.icon, "BOTTOMRIGHT", 9, 3)
    e.state = S.Text(e, 12, S.MUTED)
    e.state:SetPoint("BOTTOMLEFT", e.icon, "BOTTOMRIGHT", 21, 0)
    e.state:SetPoint("RIGHT", -4, 0)
    e.state:SetJustifyH("LEFT")
    e.state:SetWordWrap(false)
    e:SetScript("OnEnter", function(self)
        local it = self.enchant
        if not (GameTooltip and it) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(it.id) else GameTooltip:SetText(it.name) end
        GameTooltip:Show()
    end)
    e:SetScript("OnLeave", hideTip)
    c.ench = e
    return c
end

-- The rows of a slot's list for the card: { rank, id, worn, have }, and for an own list its ref,
-- slot and last (the tools of the row). What is worn and not on the list comes last, under a
-- line, without a rank (sep), so it can be made the target too.
function ns.CardItems(list, r)
    local out = {}
    local ref = list.own and ns.RefOf(list) or nil
    for i, id in ipairs(r.ids) do
        out[#out + 1] = { rank = i, id = id, worn = r.worn == id, have = ns.Carried(id),
                          ref = ref, slot = r.slot, last = i == #r.ids }
    end
    if r.worn and not r.rank and r.state ~= "covered" then
        out[#out + 1] = { id = r.worn, worn = true, sep = true, ref = ref, slot = r.slot }
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
        if it.ref then ns.ViewRefSet(it.ref)
        elseif it.stage then ns.ViewList(it.spec, it.stage) else ns.ViewList(it.spec) end
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
    local shown = ns.Shown()
    if it.ref then
        r.icon:SetIcon(OWN_ICON)
        r.name:SetText(it.name .. "  " .. colour(ns.StageName(it.stage), S.FAINT))
        r:SetSelected(shown ~= nil and ns.RefOf(shown) == it.ref)
        return
    end
    r.icon:SetIcon(ns.SpecIcon(it.spec))
    local text = ns.SpecName(it.spec) .. "  " .. colour(ns.ClassName(s[2]), S.FAINT)
    if it.stage then text = text .. colour(S.DOT .. ns.StageName(it.stage), S.FAINT) end
    r.name:SetText(text)
    r:SetSelected(shown ~= nil and not shown.own and shown.spec == it.spec and (not it.stage or shown.stage == it.stage) or false)
end

-- Own lists first, then favourites, then this class's specs, then every other class.
function ns.PickItems()
    local out = {}
    local own = ns.OwnLists()
    if #own > 0 then
        out[#out + 1] = { head = L.PICK_OWN }
        for _, o in ipairs(own) do out[#out + 1] = o end
    end
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

-- A menu over the window. The hub is a toplevel window in FULLSCREEN_DIALOG whose level climbs with
-- every raise, and a page docked in it follows, so a menu that is a child of the window, or sits at
-- a fixed level of that strata, ends up under the page's cards. A menu is a frame of UIParent in
-- TOOLTIP, the one strata over every window: no level of the hub can reach it. It takes the
-- window's scale each time it shows, and the window's OnHide and the page tabs close it.
ns.MENU_STRATA, ns.MENU_LEVEL = "TOOLTIP", 10
local function newMenu(w, h)
    local p = CreateFrame("Frame", nil, UIParent)
    p:SetSize(w, h)
    -- The game ignores SetFrameStrata and SetFrameLevel while they are fixed: unfix, set, fix again.
    local function raise(self)
        if self.SetFixedFrameStrata then self:SetFixedFrameStrata(false) end
        if self.SetFixedFrameLevel then self:SetFixedFrameLevel(false) end
        self:SetFrameStrata(ns.MENU_STRATA)
        self:SetFrameLevel(ns.MENU_LEVEL)
        if self.SetFixedFrameStrata then self:SetFixedFrameStrata(true) end
        if self.SetFixedFrameLevel then self:SetFixedFrameLevel(true) end
        local mine = frame and frame.GetEffectiveScale and tonumber(frame:GetEffectiveScale())
        local base = UIParent.GetEffectiveScale and tonumber(UIParent:GetEffectiveScale())
        if mine and base and mine > 0 and base > 0 then self:SetScale(mine / base) end
    end
    raise(p)
    p:HookScript("OnShow", raise)
    p:EnableMouse(true)
    S.Box(p, S.SOLID, S.EDGE, S.R_LG)
    ns.menus = ns.menus or {}
    ns.menus[#ns.menus + 1] = p
    return p
end
-- The game's tooltip lives in the same strata: over a menu's rows it goes above the menu.
local function tipOverMenu()
    if GameTooltip and GameTooltip.SetFrameLevel and GameTooltip.IsShown and GameTooltip:IsShown() then
        GameTooltip:SetFrameLevel(ns.MENU_LEVEL + 100)
    end
end

local function buildPicker(anchor)
    local p = newMenu(300, 380)
    p:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    p.list = S.List(p, 30, pickRow, pickFill)
    p.list:SetPoint("TOPLEFT", 6, -6)
    p.list:SetPoint("BOTTOMRIGHT", -6, 6)
    p:Hide()
    return p
end

-- The search to add an item to a slot of an own list -------------------------------------------------

local adder
local function addRow(r)
    S.NavRow(r)
    r.icon = S.IconBox(r, 26)
    r.icon:SetPoint("LEFT", 6, 0)
    r.name = S.Text(r, 13)
    r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, 1)
    r.name:SetPoint("RIGHT", -8, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.lvl = S.Text(r, 12, S.FAINT)
    r.lvl:SetPoint("BOTTOMRIGHT", -8, 3)
    r.src = S.Text(r, 12, S.MUTED)
    r.src:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 8, -1)
    r.src:SetPoint("RIGHT", r.lvl, "LEFT", -6, 0)
    r.src:SetJustifyH("LEFT")
    r.src:SetWordWrap(false)
    r.hit = CreateFrame("Button", nil, r)
    r.hit:SetAllPoints()
    r.hit:SetScript("OnEnter", function(self) itemTip(self); tipOverMenu() end)
    r.hit:SetScript("OnLeave", hideTip)
    r.hit:SetScript("OnClick", function(self)
        if self.itemId then ns.AddTo(ns.ShownRef(), ns.slot, self.itemId) end
        adder:Hide()
    end)
end
local function addFill(r, id)
    r.hit.itemId = id
    r.icon:SetIcon(ns.ItemIcon(id))
    r.icon:SetGlow(S.QUALITY[ns.ItemQuality(id)])
    r.name:SetText(S.QualityHex(ns.ItemQuality(id)) .. ns.ItemName(id) .. "|r")
    local it = D.item[id]
    r.lvl:SetText(it and it[3] and L.ILVL:format(it[3]) or "")
    r.src:SetText(ns.SourceText(id))
end

function ns.AddItems(query)
    local list = ns.Shown()
    if not list then return {} end
    local ids = ns.Candidates(ns.RefOf(list), ns.slot, query)
    local out = {}
    for i = 1, math.min(#ids, 60) do out[i] = ids[i] end
    return out
end

local function buildAdder()
    local p = newMenu(420, 400)
    p.title = S.Text(p, 13, S.GOLD, nil, "bold")
    p.title:SetPoint("TOPLEFT", 12, -12)
    p.title:SetPoint("RIGHT", -40, 0)
    p.title:SetJustifyH("LEFT")
    p.title:SetWordWrap(false)
    p.close = S.Close(p, function() p:Hide() end)
    p.close:SetPoint("TOPRIGHT", -6, -6)
    p.search = S.Edit(p, 396, 28)
    p.search:SetJustifyH("LEFT")
    p.search:SetPoint("TOPLEFT", 12, -36)
    S.Placeholder(p.search, L.SEARCH)
    p.list = S.List(p, 40, addRow, addFill)
    p.list:SetPoint("TOPLEFT", 6, -72)
    p.list:SetPoint("BOTTOMRIGHT", -6, 46)
    p.empty = S.Text(p, 12, S.MUTED)
    p.empty:SetPoint("TOPLEFT", 12, -80)
    p.empty:SetPoint("RIGHT", -12, 0)
    p.empty:SetJustifyH("LEFT")
    p.empty:SetText(L.ADD_NONE)
    p.hint = S.Text(p, 12, S.FAINT)
    p.hint:SetPoint("BOTTOMLEFT", 12, 10)
    p.hint:SetPoint("RIGHT", -12, 0)
    p.hint:SetJustifyH("LEFT")
    p.hint:SetText(L.ADD_HINT)
    p.search:SetScript("OnTextChanged", function(self)
        local items = ns.AddItems(self:GetText() or "")
        p.list:SetData(items)
        p.empty:SetShown(#items == 0)
    end)
    p:Hide()
    return p
end

-- A Shift-click on an item while the search box has the focus puts the item's id there.
function ns.OnLink(link)
    if not (adder and adder:IsShown() and adder.search:HasFocus()) then return end
    local id = ns.ParseId(link)
    if id then adder.search:SetText(tostring(id)) end
end
do
    local util = ChatFrameUtil
    if hooksecurefunc and util and util.InsertLink then
        hooksecurefunc(util, "InsertLink", function(link) ns.OnLink(link) end)
    elseif hooksecurefunc and ChatEdit_InsertLink then
        hooksecurefunc("ChatEdit_InsertLink", function(link) ns.OnLink(link) end)
    end
end

function ns.OpenAdd(anchor)
    adder = adder or buildAdder()
    adder:ClearAllPoints()
    adder:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -6)
    adder.title:SetText(L.ADD_TITLE:format(L["SLOT_" .. ns.slot]))
    adder.search:SetText("")
    local items = ns.AddItems("")
    adder.list:SetData(items)
    adder.empty:SetShown(#items == 0)
    adder:Show()
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
    -- an own list has one stage: its name goes where the stage tabs are, to rename it
    gear.name = S.Edit(p, 360, 30)
    gear.name:SetJustifyH("LEFT")
    gear.name:SetPoint("LEFT", chip, "RIGHT", S.GAP, 0)
    gear.name:SetScript("OnEnterPressed", function(self)
        local list = ns.Shown()
        if list and list.own then ns.RenameOwn(ns.RefOf(list), self:GetText()) end
        self:ClearFocus()
    end)
    gear.name:SetScript("OnEditFocusLost", function(self)
        S.SetBorder(self, S.EDGE)
        local list = ns.Shown()
        if list and list.own then self:SetText(ns.ListName(list)) end
    end)
    gear.nameHint = S.Text(p, 12, S.FAINT)
    gear.nameHint:SetPoint("LEFT", gear.name, "RIGHT", S.GAP, 0)
    gear.nameHint:SetPoint("RIGHT", -S.GAP, 0)
    gear.nameHint:SetJustifyH("LEFT")
    gear.nameHint:SetWordWrap(false)

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

-- The stats beside the page tabs ------------------------------------------------------------------
-- Hit, crit, attack power or spell damage, healing: now, and what the shown list's first items
-- change. Only on the Gear page.

local STAT_FULL = {
    melee = { hit = "STAT_HIT", crit = "STAT_CRIT", ap = "STAT_AP" },
    ranged = { hit = "STAT_RHIT", crit = "STAT_RCRIT", ap = "STAT_RAP" },
    spell = { hit = "STAT_SHIT", crit = "STAT_SCRIT" },
    heal = { crit = "STAT_SCRIT" },
}
local PERCENT = { hit = true, crit = true }
local STAT_MAX_ITEMS = 8

function ns.StatFull(kind, key)
    return L[(STAT_FULL[kind] or {})[key] or ("STAT_" .. key:upper())]
end
function ns.StatNumber(key, v)
    if v == nil then return "?" end
    if PERCENT[key] then return ("%.1f%%"):format(v) end
    return ("%d"):format(math.floor(v + 0.5))
end
-- A change with its sign, in the colour of good or bad news; a change of nothing is a faint 0.
function ns.StatGain(key, v)
    local small = PERCENT[key] and 0.05 or 0.5
    if not v or math.abs(v) < small then return colour("0", S.FAINT) end
    local text = PERCENT[key] and ("%+.1f"):format(v) or ("%+d"):format(math.floor(v + (v > 0 and 0.5 or -0.5)))
    return colour(text, v > 0 and S.GOOD or S.BAD)
end
-- One cell's text: short label, the value now, the change.
function ns.StatCell(st)
    return colour(L["STATS_" .. st.key:upper()], S.MUTED) .. " " .. colour(ns.StatNumber(st.key, st.now), S.TEXT)
        .. " " .. ns.StatGain(st.key, st.gain)
end

-- The tooltip of one stat: now, with the list, the hit cap, the items behind the change.
function ns.StatTipLines(sum, st, list)
    local out = {}
    local with = st.now and (st.now + st.gain) or nil
    out[#out + 1] = { L.STATS_NOW, ns.StatNumber(st.key, st.now) }
    out[#out + 1] = { L.STATS_WITH, ns.StatNumber(st.key, with) .. " " .. ns.StatGain(st.key, st.gain) }
    if st.cap then
        local cap = ("%d%%"):format(st.cap)
        local base = with or st.now
        local state = ""
        if base then
            state = base >= st.cap - 0.05 and colour(L.STATS_CAP_DONE, S.GOOD)
                or colour(L.STATS_CAP_LEFT:format(("%.1f%%"):format(st.cap - base)), S.WARN)
        end
        out[#out + 1] = { L.STATS_CAP:format(cap), state }
        if st.talent then
            local pct = ("%d%%"):format(st.talent)
            if st.talentSchool then
                out[#out + 1] = { L.STATS_TALENT_SCHOOL:format(pct, L["SCHOOL_" .. st.talentSchool]) }
            else
                out[#out + 1] = { L.STATS_TALENT:format(pct, ("%d%%"):format(st.cap - st.talent)) }
            end
        end
        if st.dual then out[#out + 1] = { L.STATS_DUAL:format(("%d%%"):format(st.dual)) } end
    end
    local items = sum.items[st.key] or {}
    if #items > 0 then
        out[#out + 1] = { head = L.STATS_CHANGES }
        for i, it in ipairs(items) do
            if i > STAT_MAX_ITEMS then
                out[#out + 1] = { L.STATS_MORE:format(#items - STAT_MAX_ITEMS), "" }
                break
            end
            local q = ns.ItemQuality(it.id)
            out[#out + 1] = { S.QualityHex(q) .. ns.ItemName(it.id) .. "|r", ns.StatGain(st.key, it.gain), id = it.id }
        end
    elseif not sum.wait then
        out[#out + 1] = { L.STATS_SAME }
    end
    if sum.wait then out[#out + 1] = { L.STATS_WAIT } end
    if list then out[#out + 1] = { foot = L.STATS_LIST:format(ns.ListName(list)) } end
    return out
end

local function statTip(self)
    if not (self.st and GameTooltip and GameTooltip.SetOwner) then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText(ns.StatFull(self.sum.kind, self.st.key), S.GOLD[1], S.GOLD[2], S.GOLD[3])
    for _, l in ipairs(ns.StatTipLines(self.sum, self.st, self.list)) do
        if l.head then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(S.Upper(l.head), S.GOLD_DIM[1], S.GOLD_DIM[2], S.GOLD_DIM[3])
        elseif l.foot then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(l.foot, S.FAINT[1], S.FAINT[2], S.FAINT[3], true)
        elseif l[2] then
            GameTooltip:AddDoubleLine(l[1], l[2], S.MUTED[1], S.MUTED[2], S.MUTED[3], 1, 1, 1)
        else
            GameTooltip:AddLine(l[1], S.MUTED[1], S.MUTED[2], S.MUTED[3], true)
        end
    end
    GameTooltip:Show()
end

local function buildStats(body)
    local bar = CreateFrame("Frame", nil, body)
    -- beside the page tabs, its text level with theirs and clear of the hairline under them
    bar:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -1)
    bar:SetSize(10, 28)
    bar.cells, bar.dots = {}, {}
    for i = 1, 5 do
        local c = CreateFrame("Button", nil, bar)
        c:SetHeight(28)
        c.text = S.Text(c, 12, S.TEXT)
        c.text:SetPoint("LEFT")
        c.text:SetWordWrap(false)
        c:SetScript("OnEnter", statTip)
        c:SetScript("OnLeave", hideTip)
        bar.cells[i] = c
        local d = S.Text(bar, 12, S.FAINT)
        d:SetJustifyH("CENTER")
        d:SetText(S.DOT_MARK)
        bar.dots[i] = d
    end
    return bar
end

-- room: how wide the bar may be (the page row less the tabs).
local function paintStats(bar, list, room)
    local sum = list and ns.StatSummary(list)
    if not sum then bar:Hide(); return end
    bar:Show()
    local widths, total, gap = {}, 0, 16
    for i, c in ipairs(bar.cells) do
        local st = sum.stats[i]
        c.st, c.sum, c.list = st, sum, list
        if st then
            c.text:SetText(ns.StatCell(st))
            widths[i] = math.ceil(c.text:GetStringWidth() or 0)
        end
    end
    -- the last stats give way when the row is too narrow
    local n = 0
    for i = 1, #sum.stats do
        local w = total + (i > 1 and gap or 0) + widths[i]
        if room and w > room then break end
        total, n = w, i
    end
    local x = 0
    for i, c in ipairs(bar.cells) do
        local show = i <= n
        c:SetShown(show)
        bar.dots[i]:SetShown(show and i > 1)
        if show then
            if i > 1 then
                bar.dots[i]:ClearAllPoints()
                bar.dots[i]:SetPoint("LEFT", bar, "LEFT", x, 0)
                bar.dots[i]:SetWidth(gap)
                x = x + gap
            end
            c:ClearAllPoints()
            c:SetPoint("LEFT", bar, "LEFT", x, 0)
            c:SetWidth(widths[i])
            x = x + widths[i]
        end
    end
    bar:SetWidth(math.max(1, x))
    bar.shown = n
end
ns.PaintStats = paintStats

local function paintGear()
    local list = ns.Shown()
    if not list then return end
    local rows = ns.SlotRows(list)
    local byslot = {}
    for _, r in ipairs(rows) do
        byslot[r.slot] = r
        paintSlot(gear.slots[r.slot], r, list)
    end
    if statBar then paintStats(statBar, list, ns.StatRoom and ns.StatRoom()) end
    local spec = ns.SpecInfo(list.spec)
    gear.chip:SetText(ns.SpecName(list.spec))
    if gear.chip.btnIcon then gear.chip.btnIcon:SetTexture(ns.SpecIcon(list.spec)) end
    local own = list.own ~= nil
    gear.stages.frame:SetShown(not own)
    gear.star:SetShown(not own)
    gear.name:SetShown(own)
    gear.nameHint:SetShown(own)
    if own then
        if not gear.name:HasFocus() then gear.name:SetText(ns.ListName(list)) end
        gear.nameHint:SetText(ns.StageName(list.stage))
    end
    local stage = list.stage == "REAL" and "PRE" or list.stage
    for i, s in ipairs(STAGE_TABS) do
        if s == stage then gear.stages:Select(i, true) end
        gear.stages.buttons[i]:SetEnabled(D.lists[list.spec][s] ~= nil)
    end
    local pre = list.stage == "PRE" or list.stage == "REAL"
    gear.real:SetShown(not own and pre and D.lists[list.spec].REAL ~= nil)
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
    c.empty:SetText(r.state == "covered" and L.EMPTY_COVERED or (own and L.EMPTY_OWN) or L.EMPTY_SLOT)
    local ench = r.state ~= "covered" and ns.Enchant(list, r.slot) or nil
    c.ench.enchant = ench
    c.ench:SetShown(ench ~= nil)
    if ench then
        local e = c.ench
        e.kind:SetIcon(ns.ENCH_ICON[ench.kind])
        e.icon:SetIcon(ench.icon)
        e.name:SetText(ench.name)
        e.src:SetText(ench.kind ~= "other" and L["ENCH_SRC_" .. ench.kind:upper()] or "")
        local col = ns.ENCH_COLOR[ench.state or "empty"]
        e.dot:SetShown(ench.state ~= nil)
        e.dot:SetVertexColor(col[1], col[2], col[3], 1)
        e.state:SetText(L["ENCH_" .. (ench.state or "empty"):upper()])
        e.state:SetPoint("BOTTOMLEFT", e.icon, "BOTTOMRIGHT", ench.state and 21 or 9, 0)
    end
    c.list:SetPoint("BOTTOMRIGHT", 0, ench and ROW_H + 4 or 0)
    c.add:SetShown(r.state ~= "covered" and (not own or #r.ids < ns.OWN_MAX))
    c.countLabel:SetPoint("RIGHT", c.add:IsShown() and -(c.add:GetWidth() + 8) or 0, 0)
    local news = own and ns.SiteNews(ns.RefOf(list)) or {}
    if #news > 0 then
        local names = {}
        for i, slot in ipairs(news) do if i <= 3 then names[#names + 1] = L["SLOT_" .. slot] end end
        c.news:Set(L.NEWS:format(table.concat(names, ", ")))
        c.news:Show()
    else
        c.news:Hide()
    end
    c.list:SetPoint("TOPLEFT", 0, c.news:IsShown() and -(44 + S.BANNER_H + 6) or -44)
end

-- The sets page ----------------------------------------------------------------------------------------

local SET_LEFT, SET_ROW, PIECE_H, PIECE_ROWS = 236, 44, 36, 4
-- the bonuses never scroll: every row gets its share of the room left, two lines of text while
-- a row is BONUS_TWO high or more, and no more than BONUS_MAX of it
local BONUS_ROWS, BONUS_MAX, BONUS_TWO, PIECES_Y = 8, 34, 28, 80
local PIP = 7

function ns.SetClass()
    local _, mine = UnitClass("player")
    return ns.setClass or mine
end

local function codeName(code) return L["SLOT_" .. (ns.CODE_SLOT[code] or code)] or code end

-- Where a set piece comes from: the data's line, else the boss Dungeon Journal knows.
function ns.PieceSource(id)
    local text = ns.SourceText(id)
    if text ~= "" then return text end
    local dj = GulliDungeonJournal
    local d = dj and dj.DropsOf and dj.DropsOf(id)
    d = d and d[1]
    if d and d.boss then
        local where = dj.Name and dj.Name(d.key)
        return where and (d.boss .. S.DOT .. where) or d.boss
    end
    return ""
end

-- The second line of a piece: the tier 0 piece it is made from and whether it is there, else
-- where the piece comes from.
function ns.PieceLine(g)
    if g.from then
        local have = g.fromHave and colour(L.SET_HAVE, S.GOOD) or colour(L.SET_NOT, S.FAINT)
        return L.SET_FROM:format(S.QualityHex(ns.ItemQuality(g.from)) .. ns.ItemName(g.from) .. "|r") .. S.DOT .. have
    end
    return ns.PieceSource(g.id)
end

local function pips(parent, n)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(n * (PIP + 2), PIP)
    f.dots = {}
    for i = 1, n do
        local d = S.Circle(f, PIP, S.FAINT, "OVERLAY")
        d:SetPoint("LEFT", (i - 1) * (PIP + 2), 0)
        f.dots[i] = d
    end
    function f:Set(have, of)
        of = math.min(of, #self.dots)
        for i, d in ipairs(self.dots) do
            d:SetShown(i <= of)
            local c = i <= have and S.GOOD or S.FAINT
            d:SetVertexColor(c[1], c[2], c[3], i <= have and 1 or 0.45)
        end
        self:SetWidth(math.max(1, of * (PIP + 2)))
    end
    return f
end

local function setRowMake(r)
    S.NavRow(r)
    r.head = S.Text(r, 12, S.GOLD_DIM, nil, "bold")
    r.head:SetPoint("BOTTOMLEFT", 8, 5)
    r.head:SetPoint("RIGHT", -8, 0)
    r.head:SetJustifyH("LEFT")
    r.head:SetWordWrap(false)
    r.icon = S.IconBox(r, 32)
    r.icon:SetPoint("LEFT", 6, 0)
    r.name = S.Text(r, 13)
    r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, 0)
    r.name:SetPoint("RIGHT", -6, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.pips = pips(r, 8)
    r.pips:SetPoint("BOTTOMRIGHT", -8, 8)
    r.sub = S.Text(r, 12, S.MUTED)
    r.sub:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 8, 0)
    r.sub:SetPoint("RIGHT", r.pips, "LEFT", -6, 0)
    r.sub:SetJustifyH("LEFT")
    r.sub:SetWordWrap(false)
    r.hit = CreateFrame("Button", nil, r)
    r.hit:SetAllPoints()
    r.hit:SetScript("OnClick", function(self)
        local it = self:GetParent().item
        if it then ns.setId = it.set; ns.Refresh() end
    end)
    r.hit:SetScript("OnEnter", function(self)
        local row = self:GetParent()
        if not (GameTooltip and row.item and row.full) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(row.full)
        if row.where then GameTooltip:AddLine(row.where, S.MUTED[1], S.MUTED[2], S.MUTED[3]) end
        GameTooltip:Show()
    end)
    r.hit:SetScript("OnLeave", hideTip)
end

local function setRowFill(r, it)
    local head = it.head ~= nil
    r.item = not head and it or nil
    r.head:SetShown(head)
    for _, k in ipairs({ "icon", "name", "sub", "pips", "hit" }) do r[k]:SetShown(not head) end
    if r.line then r.line:SetShown(not head) end
    if head then r.head:SetText(S.Upper(L["SETS_" .. it.head])); r:SetSelected(false); return end
    local info = ns.SetInfo(it.set)
    local first = info.groups[1]
    local q = first and ns.ItemQuality(first.id) or 3
    r.icon:SetIcon(first and ns.ItemIcon(first.id) or ns.SET_ICON)
    r.icon:SetGlow(S.QUALITY[q])
    r.full = info.name
    r.name:SetText(S.QualityHex(q) .. info.name .. "|r")
    -- a set for anyone says where its first piece comes from, when the data knows
    local where = info.kind == "any" and first and ns.PieceSource(first.id) or ""
    local place = info.kind == "any" and first and ns.SourcePlace(first.id) or ""
    r.where = where ~= "" and where or nil
    r.sub:SetText(place ~= "" and place or L["SET_KIND_" .. info.kind:upper()])
    r.pips:Set(info.worn, info.of)
    r:SetSelected(ns.setId == it.set)
end

local function pieceCell(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(PIECE_H)
    S.Box(b, S.CLEAR, S.CLEAR, S.R_MD)
    b.line = S.Divider(b)
    b.line:SetPoint("TOPLEFT", 0, 0)
    b.line:SetPoint("TOPRIGHT", 0, 0)
    b.line:SetHeight(1)
    b.icon = S.IconBox(b, 28)
    b.icon:SetPoint("LEFT", 4, 0)
    b.tag = S.Text(b, 12, S.MUTED)
    b.tag:SetPoint("TOPRIGHT", -4, -4)
    b.tag:SetJustifyH("RIGHT")
    b.tag:SetWordWrap(false)
    b.dot = S.Circle(b, 8, S.BAD, "OVERLAY")
    b.dot:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 8, -4)
    b.name = S.Text(b, 13)
    b.name:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 20, 0)
    b.name:SetPoint("RIGHT", b.tag, "LEFT", -6, 0)
    b.name:SetJustifyH("LEFT")
    b.name:SetWordWrap(false)
    b.sub = S.Text(b, 12, S.MUTED)
    b.sub:SetPoint("BOTTOMLEFT", b.icon, "BOTTOMRIGHT", 8, 0)
    b.sub:SetPoint("RIGHT", -4, 0)
    b.sub:SetJustifyH("LEFT")
    b.sub:SetWordWrap(false)
    b:SetScript("OnEnter", function(self)
        local g = self.group
        if not g then return end
        S.Fill(self, S.HOVER)
        self.itemId = g.id
        itemTip(self)
        -- the tooltip makes the client load the piece: the bonuses it waits for come with it
        if ns.bonusWait and ns.Later then ns.Later() end
        if not GameTooltip then return end
        local c = ns.AT_COLOR[self.at]
        GameTooltip:AddLine(L["AT_" .. self.at:upper()], c[1], c[2], c[3])
        local line = ns.PieceLine(g)
        if line ~= "" then GameTooltip:AddLine(line, S.MUTED[1], S.MUTED[2], S.MUTED[3]) end
        if g.step then
            GameTooltip:AddLine(L.SRC_QUEST:format(D.setSteps[g.step]), S.MUTED[1], S.MUTED[2], S.MUTED[3])
        end
        if #g.ids > 1 then
            GameTooltip:AddLine(L.SET_TURN:format(g.at, #g.ids), S.MUTED[1], S.MUTED[2], S.MUTED[3])
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self) S.Fill(self, S.CLEAR); hideTip() end)
    b:SetScript("OnClick", function(self)
        local g = self.group
        if g and #g.ids > 1 and not (g.worn or g.have) then ns.SetTurn(ns.setId, g.code, #g.ids) end
    end)
    return b
end

local function paintPiece(b, g)
    b.group = g
    local q = ns.ItemQuality(g.id)
    b.icon:SetIcon(ns.ItemIcon(g.id))
    b.icon:SetGlow(S.QUALITY[q])
    b.name:SetText(S.QualityHex(q) .. ns.ItemName(g.id) .. "|r")
    b.at = g.worn and "worn" or (g.have and "bag") or "miss"
    local c = ns.AT_COLOR[b.at]
    b.dot:SetVertexColor(c[1], c[2], c[3], 1)
    -- a place with variants says which one is shown; a tier 0.5 piece its step of the chain
    local tag = ""
    if #g.ids > 1 then tag = g.at .. "/" .. #g.ids
    elseif g.step then tag = L.SET_STEP:format(g.step) end
    b.tag:SetText(tag)
    b.sub:SetText(ns.PieceLine(g))
end

local function bonusRow(parent)
    local r = CreateFrame("Frame", nil, parent)
    r.line = S.Divider(r)
    r.line:SetPoint("TOPLEFT", 0, 0)
    r.line:SetPoint("TOPRIGHT", 0, 0)
    r.line:SetHeight(1)
    r.pill = CreateFrame("Frame", nil, r)
    r.pill:SetSize(30, 20)
    r.pill:SetPoint("LEFT", 2, 0)
    -- a filled chip with no outline: a 1 pixel edge drops out at some window scales
    S.Box(r.pill, S.INPUT, S.CLEAR, S.R_MD)
    r.n = S.Text(r.pill, 12, S.MUTED, nil, "bold")
    r.n:SetPoint("CENTER")
    r.state = S.Text(r, 12, S.MUTED)
    r.state:SetPoint("RIGHT", -4, 0)
    r.state:SetJustifyH("RIGHT")
    r.state:SetWordWrap(false)
    r.text = S.Text(r, 12)
    r.text:SetPoint("LEFT", r.pill, "RIGHT", 8, 0)
    r.text:SetPoint("RIGHT", r.state, "LEFT", -8, 0)
    r.text:SetJustifyH("LEFT")
    r.hit = CreateFrame("Button", nil, r)
    r.hit:SetAllPoints()
    r.hit:SetScript("OnEnter", function(self)
        local it = self:GetParent().item
        if not (GameTooltip and it and it.text) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(it.text, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    r.hit:SetScript("OnLeave", hideTip)
    return r
end

-- How high each of n bonus rows is in a box of that height, and how many lines its text takes.
function ns.BonusLayout(n, height)
    if n < 1 then return BONUS_MAX, 2 end
    local h = math.max(1, math.min(BONUS_MAX, math.floor(height / n)))
    return h, h >= BONUS_TWO and 2 or 1
end

local function layBonuses(box)
    local n = box.n or 0
    local h, lines = ns.BonusLayout(n, box:GetHeight() or 0)
    for i, r in ipairs(box.rows) do
        r:SetShown(i <= n)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -(i - 1) * h)
        r:SetPoint("RIGHT", 0, 0)
        r:SetHeight(h)
        if r.text.SetMaxLines then r.text:SetMaxLines(lines) end
        r.text:SetWordWrap(lines > 1)
    end
end

local function bonusFill(r, b)
    r.item = b
    r.n:SetText(b.count and tostring(b.count) or "")
    S.Fill(r.pill, b.on and S.GOOD or S.INPUT)
    r.n:SetTextColor(unpack(b.on and S.BG or S.MUTED))
    r.text:SetText(b.text or L.SET_BONUS_WAIT)
    r.text:SetTextColor(unpack((b.on and S.TEXT) or (b.text and S.MUTED) or S.FAINT))
    if b.on then
        r.state:SetText(colour(L.SET_ACTIVE, S.GOOD))
    else
        r.state:SetText(b.count and L.SET_MORE:format(b.count - b.worn) or "")
    end
end

local classMenu
local function classRow(r)
    S.NavRow(r)
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
        classMenu:Hide()
        ns.PickSetClass(self:GetParent().class)
    end)
end
local function classFill(r, class)
    r.class = class
    r.icon:SetIcon(ns.ClassIcon(class))
    r.name:SetText(ns.ClassName(class))
    r:SetSelected(ns.SetClass() == class)
end

-- Shows the sets of a class (nil: the character's) and the first of them.
function ns.PickSetClass(class)
    local _, mine = UnitClass("player")
    ns.setClass = class ~= mine and class or nil
    ns.setId = nil
    ns.Refresh()
end

local function setsPage(body)
    local p = CreateFrame("Frame", nil, body)
    local chip = S.Button(p, SET_LEFT, 30)
    S.SetButtonIcon(chip, ns.ClassIcon("WARRIOR"))
    chip:SetPoint("TOPLEFT", 0, 0)
    chip:SetScript("OnClick", function(self)
        if not classMenu then
            classMenu = newMenu(SET_LEFT, 9 * 30 + 12)
            classMenu:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -4)
            classMenu.list = S.List(classMenu, 30, classRow, classFill)
            classMenu.list:SetPoint("TOPLEFT", 6, -6)
            classMenu.list:SetPoint("BOTTOMRIGHT", -6, 6)
            classMenu:Hide()
        end
        if classMenu:IsShown() then classMenu:Hide(); return end
        classMenu:Show()
        classMenu.list:SetData(ns.CLASSES)
    end)
    sets.chip = chip
    local left = CreateFrame("Frame", nil, p)
    left:SetPoint("TOPLEFT", 0, -(30 + S.GAP))
    left:SetPoint("BOTTOMLEFT", 0, 0)
    left:SetWidth(SET_LEFT)
    S.Box(left, S.SURFACE, S.CARD_EDGE, S.R_LG)
    sets.list = S.List(left, SET_ROW, setRowMake, setRowFill)
    sets.list.heightOf = function(it) return it.head and 26 or SET_ROW end
    sets.list:SetPoint("TOPLEFT", 4, -4)
    sets.list:SetPoint("BOTTOMRIGHT", -4, 4)
    sets.none = S.Text(left, 12, S.MUTED)
    sets.none:SetPoint("TOPLEFT", 12, -14)
    sets.none:SetPoint("RIGHT", -12, 0)
    sets.none:SetJustifyH("LEFT")
    sets.none:SetText(L.SETS_EMPTY)

    local c = CreateFrame("Frame", nil, p)
    c:SetPoint("TOPLEFT", SET_LEFT + S.GAP, 0)
    c:SetPoint("BOTTOMRIGHT", 0, 0)
    S.Box(c, S.SURFACE, S.CARD_EDGE, S.R_LG)
    S.Depth(c, S.R_LG)
    c.body = CreateFrame("Frame", nil, c)
    c.body:SetPoint("TOPLEFT", S.INSET, -S.INSET)
    c.body:SetPoint("BOTTOMRIGHT", -S.INSET, S.INSET)
    local b = c.body
    c.icon = S.IconBox(b, 40)
    c.icon:SetPoint("TOPLEFT", 0, 0)
    c.count = S.Text(b, 20, S.TEXT, nil, "bold")
    c.count:SetPoint("TOPRIGHT", 0, -2)
    c.countLabel = S.Text(b, 12, S.MUTED)
    c.countLabel:SetPoint("TOPRIGHT", 0, -26)
    c.name = S.Text(b, 16, S.GOLD, nil, "title")
    c.name:SetPoint("TOPLEFT", c.icon, "TOPRIGHT", 10, -1)
    c.name:SetPoint("RIGHT", c.count, "LEFT", -12, 0)
    c.name:SetJustifyH("LEFT")
    c.name:SetWordWrap(false)
    c.sub = S.Text(b, 12, S.MUTED)
    c.sub:SetPoint("BOTTOMLEFT", c.icon, "BOTTOMRIGHT", 10, 2)
    c.sub:SetPoint("RIGHT", c.countLabel, "LEFT", -12, 0)
    c.sub:SetJustifyH("LEFT")
    c.sub:SetWordWrap(false)
    c.bar = S.Progress(b, 6)
    c.bar:SetPoint("TOPLEFT", 0, -46)
    c.bar:SetPoint("TOPRIGHT", 0, -46)
    c.piecesHead = S.Text(b, 12, S.GOLD_DIM, nil, "bold")
    c.piecesHead:SetPoint("TOPLEFT", 0, -60)
    c.piecesHead:SetJustifyH("LEFT")
    c.piecesHead:SetWordWrap(false)
    c.piecesHead:SetText(S.Upper(L.SET_PIECES))
    c.cells = {}
    for i = 1, PIECE_ROWS * 2 do
        local cell = pieceCell(b)
        local row, right = math.floor((i - 1) / 2), i % 2 == 0
        if right then
            cell:SetPoint("TOPLEFT", b, "TOP", S.GAP / 2, -(PIECES_Y + row * PIECE_H))
            cell:SetPoint("RIGHT", 0, 0)
        else
            cell:SetPoint("TOPLEFT", 0, -(PIECES_Y + row * PIECE_H))
            cell:SetPoint("RIGHT", b, "CENTER", -S.GAP / 2, 0)
        end
        c.cells[i] = cell
    end
    c.bonusHead = S.Text(b, 12, S.GOLD_DIM, nil, "bold")
    c.bonusHead:SetText(S.Upper(L.SET_BONUSES))
    c.bonusHead:SetJustifyH("LEFT")
    c.bonusHead:SetWordWrap(false)
    local box = CreateFrame("Frame", nil, b)
    box.rows = {}
    for i = 1, BONUS_ROWS do box.rows[i] = bonusRow(box) end
    box:SetScript("OnSizeChanged", layBonuses)
    c.bonuses = box
    -- the tier 0.5 chain, on the line of the pieces' head: the step the character is at
    local ch = CreateFrame("Button", nil, b)
    ch:SetHeight(18)
    ch:SetPoint("LEFT", c.piecesHead, "RIGHT", 12, 0)
    ch:SetPoint("RIGHT", b, "RIGHT", 0, 0)
    ch.text = S.Text(ch, 12, S.MUTED)
    ch.text:SetPoint("LEFT", 0, 0)
    ch.text:SetPoint("RIGHT", 0, 0)
    ch.text:SetJustifyH("RIGHT")
    ch.text:SetWordWrap(false)
    ch:SetScript("OnEnter", function(self)
        if not (GameTooltip and self.title) then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(self.title, S.GOLD[1], S.GOLD[2], S.GOLD[3])
        GameTooltip:AddLine(self.quest, 1, 1, 1, true)
        GameTooltip:AddLine(self.slots, S.MUTED[1], S.MUTED[2], S.MUTED[3], true)
        GameTooltip:Show()
    end)
    ch:SetScript("OnLeave", hideTip)
    c.chain = ch
    sets.card = c
    return p
end

-- The set shown: the chosen one while the class has it, else the class's first.
function ns.ShownSet()
    local items = ns.SetList(ns.SetClass())
    local first
    for _, it in ipairs(items) do
        if it.set then
            first = first or it.set
            if it.set == ns.setId then return ns.setId, items end
        end
    end
    ns.setId = first
    return first, items
end

local function paintSets()
    local class = ns.SetClass()
    sets.chip:SetText(ns.ClassName(class))
    if sets.chip.btnIcon then sets.chip.btnIcon:SetTexture(ns.ClassIcon(class)) end
    local id, items = ns.ShownSet()
    sets.list:SetData(items)
    sets.none:SetShown(#items == 0)
    local c = sets.card
    c:SetShown(id ~= nil)
    if not id then return end
    local info = ns.SetInfo(id, ns.Shown())
    sets.info = info
    local first = info.groups[1]
    c.icon:SetIcon(first and ns.ItemIcon(first.id) or ns.SET_ICON)
    c.icon:SetGlow(first and S.QUALITY[ns.ItemQuality(first.id)] or nil)
    c.name:SetText(info.name)
    c.sub:SetText(L.SET_SUB:format(L["SET_KIND_" .. info.kind:upper()], info.of))
    c.count:SetText(info.worn .. "/" .. info.of)
    c.countLabel:SetText(L.SET_WORN)
    c.bar:Set(info.of > 0 and info.worn / info.of or 0, info.worn == info.of and info.of > 0 and S.GOOD or nil)
    for i, cell in ipairs(c.cells) do
        local g = info.groups[i]
        cell:SetShown(g ~= nil)
        if g then paintPiece(cell, g) end
    end
    local rows = math.ceil(math.min(#info.groups, #c.cells) / 2)
    local y = PIECES_Y + rows * PIECE_H + 8
    c.bonusHead:ClearAllPoints()
    c.bonusHead:SetPoint("TOPLEFT", 0, -y)
    c.bonusHead:SetPoint("RIGHT", 0, 0)
    local chain = ns.SetChain(info)
    c.chain:SetShown(chain ~= nil)
    if chain then
        local names = {}
        for _, code in ipairs(chain.codes) do names[#names + 1] = codeName(code) end
        c.chain.title = L.SET_CHAIN:format(chain.step, chain.of)
        c.chain.quest, c.chain.slots = chain.quest, table.concat(names, ", ")
        c.chain.text:SetText(c.chain.title .. S.DOT .. colour(chain.quest, S.TEXT))
    end
    local bonuses = ns.SetBonuses(info)
    for _, x in ipairs(bonuses) do x.worn = info.worn end
    c.bonuses:ClearAllPoints()
    c.bonuses:SetPoint("TOPLEFT", 0, -(y + 18))
    c.bonuses:SetPoint("BOTTOMRIGHT", 0, 0)
    c.bonuses.n = math.min(#bonuses, BONUS_ROWS)
    for i, r in ipairs(c.bonuses.rows) do
        if bonuses[i] then bonusFill(r, bonuses[i]) end
    end
    layBonuses(c.bonuses)
end

-- The footer's button on the sets page: the set's pieces go on the list shown on the gear page.
function ns.AddShownSet()
    local info = sets.info or (ns.ShownSet() and ns.SetInfo(ns.ShownSet(), ns.Shown()))
    if not (info and ns.SetMine(info)) then return 0 end
    local n = ns.SetAdd(info, ns.ViewRef())
    if S.Toast then
        S.Toast({ key = "setadd", icon = ns.ICON, title = L.TITLE,
                  text = n > 0 and L.SET_ADDED:format(n) or L.SET_ADD_NONE, seconds = 6 })
    end
    return n
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
    for _, sec in ipairs({ { L.SEC_MAIN, { "real" } }, { L.SEC_NOTICES, { "tooltip", "notify", "drop" } } }) do
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
    if current == SETS then
        local info = sets.info
        footer:SetStatus(L.SETS_STATUS)
        mainBtn:SetText(L.SET_ADD)
        mainBtn:SetEnabled(info ~= nil and ns.SetMine(info))
        mainBtn:SetWidth(math.max(150, math.floor((mainBtn.text:GetStringWidth() or 0) + 40)))
        autoBtn:Hide(); copyBtn:Hide(); delBtn:Hide()
        footer.status:SetPoint("RIGHT", mainBtn, "LEFT", -12, 0)
        return
    end
    copyBtn:Show()
    local isMain = ns.ShownRef() == ns.MainRef() or (ns.view == nil)
    local sim = list.simmed and L.SIMMED or L.NOT_SIMMED
    footer:SetStatus(L.STATUS:format(D.ver, sim))
    if isMain then
        mainBtn:SetText(ns.MainRef() == "auto" and L.MAIN_AUTO or L.MAIN_IS)
        mainBtn:SetEnabled(false)
    else
        mainBtn:SetText(L.TRACK)
        mainBtn:SetEnabled(true)
    end
    mainBtn:SetWidth(math.max(150, math.floor((mainBtn.text:GetStringWidth() or 0) + 40)))
    autoBtn:SetShown(ns.MainRef() ~= "auto")
    delBtn:SetShown(list.own ~= nil)
    -- the shown buttons from the right, the status line left of the last one
    local last = mainBtn
    for _, x in ipairs({ { autoBtn, ns.MainRef() ~= "auto" }, { copyBtn, true }, { delBtn, list.own ~= nil } }) do
        if x[2] then
            x[1]:ClearAllPoints()
            x[1]:SetPoint("RIGHT", last, "LEFT", -8, 0)
            last = x[1]
        end
    end
    footer.status:SetPoint("RIGHT", last, "LEFT", -12, 0)
end

function ns.SetsShown() return frame ~= nil and frame:IsShown() and current == SETS end

function ns.Refresh()
    if not ns.db then return end
    if not (frame and frame:IsShown()) then return end
    if current == 1 then paintGear() elseif current == SETS then paintSets() end
    paintFooter()
end

local function build()
    frame = S.Window("GulliMyBisListFrame", L.TITLE, S.WIDE_W, S.DOCK_H)
    local body, width = frame.body, frame.inner[1]
    footer = S.Footer(frame)
    mainBtn = S.Primary(S.Button(frame, 180, 30))
    mainBtn:SetScript("OnClick", function()
        if current == SETS then ns.AddShownSet(); return end
        local ref = ns.ShownRef()
        if ref then ns.SetMain(ref); ns.view = nil; ns.Refresh() end
    end)
    footer:Add(mainBtn)
    autoBtn = S.Button(frame, 150, 30)
    autoBtn:SetText(L.BACK_AUTO)
    autoBtn:SetWidth(math.max(120, math.floor((autoBtn.text:GetStringWidth() or 0) + 32)))
    autoBtn:SetScript("OnClick", function() ns.SetMain("auto"); ns.view = nil; ns.Refresh() end)
    footer:Add(autoBtn)
    copyBtn = S.FitButton(frame, L.COPY, 30, 110)
    S.SetButtonIcon(copyBtn, OWN_ICON, 14)
    copyBtn:SetWidth(copyBtn:GetWidth() + 20)
    copyBtn:SetScript("OnClick", function()
        local ref = ns.CopyList(ns.ShownRef())
        if ref then ns.ViewRefSet(ref) end
    end)
    footer:Add(copyBtn)
    delBtn = S.Danger(S.FitButton(frame, L.DELETE, 30, 100))
    delBtn:SetScript("OnClick", function()
        local list = ns.Shown()
        if not (list and list.own) then return end
        local name = ns.ListName(list)
        local undo = ns.DeleteOwn(ns.RefOf(list))
        if undo and S.Toast then
            S.Toast({ key = "deleted", icon = OWN_ICON, title = L.TITLE, text = L.DELETED:format(name), seconds = 10,
                      buttons = { { text = L.UNDO, onClick = function() ns.RestoreOwn(undo); ns.ViewRefSet("own:" .. undo.n) end } } })
        end
    end)
    footer:Add(delBtn)
    tabs = S.PageTabs(body, { L.TAB_GEAR, L.TAB_SETS, L.TAB_SETTINGS }, nil, function(i)
        current = i
        for j, p in ipairs(pages) do p:SetShown(j == i) end
        if picker then picker:Hide() end
        if adder then adder:Hide() end
        if classMenu then classMenu:Hide() end
        footer:SetShown(i ~= SETTINGS)
        if statBar then statBar:SetShown(i == 1) end
        ns.Refresh()
    end, nil, { "Interface\\Icons\\INV_Chest_Plate06", ns.SET_ICON, S.TAB.settings })
    statBar = buildStats(body)
    -- the room beside the tabs: the page row less the tabs and a gap
    function ns.StatRoom()
        local last = tabs.buttons[#tabs.buttons]
        local w = tonumber(body:GetWidth()) or 0
        if w <= 0 then w = (tonumber(width) or 0) > 0 and width or S.WIDE_W end
        return w - ((last.x or 0) + (tonumber(last:GetWidth()) or 0)) - 24
    end
    pages[1] = gearPage(body)
    pages[SETS] = setsPage(body)
    pages[SETTINGS] = settingsPage(body, width)
    for i, p in ipairs(pages) do
        p:SetPoint("TOPLEFT", 0, -(30 + S.GAP))
        p:SetPoint("BOTTOMRIGHT")
        p:SetShown(i == 1)
    end
    frame:HookScript("OnShow", function() ns.Refresh() end)
    frame:HookScript("OnHide", function()
        if classMenu then classMenu:Hide() end
        if picker then picker:Hide() end
        if adder then adder:Hide() end
    end)
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
function ns.Parts() return gear, footer, mainBtn, tabs, sets end
function ns.StatBar() return statBar end
function ns.ShowTab(i) ns.Window(); tabs:Select(i) end
