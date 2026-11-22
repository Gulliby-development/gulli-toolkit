-- The window (the bags worn, the rewards in groups, one reward's page with its chain and the
-- buttons that lead to it, the settings) and the guide's tracker on the screen. It only shows
-- what Core.lua worked out.

local _, ns = ...
local L = ns.L
local S = ns.Skin
local TI = "Interface\\Icons\\"

local frame, footer, leadAll, strip, tabs, better, kindTabs, classTabs
local pages = {}
local kinds = {}

local LIST_W, HEAD_H, ROW_H = 336, 28, 48
local PACK_ICON = "Interface\\Icons\\INV_Misc_Bag_08"
local NO_BAG_ICON = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"
local STATE_ICON = {
    ready = "Interface\\GossipFrame\\ActiveQuestIcon", log = "Interface\\GossipFrame\\IncompleteQuestIcon",
    take = "Interface\\GossipFrame\\AvailableQuestIcon", later = "Interface\\RaidFrame\\ReadyCheck-Waiting",
    done = "Interface\\RaidFrame\\ReadyCheck-Ready", other = "Interface\\RaidFrame\\ReadyCheck-Waiting",
    bag = "Interface\\GossipFrame\\ActiveQuestIcon",
}
local ACT_ICON = { map = TI .. "INV_Misc_Map_01", lead = TI .. "Ability_Hunter_Pathfinding",
                   link = TI .. "INV_Misc_Book_09", hide = TI .. "Ability_Stealth" }

local function colour(text, c) return S.Hex(c) .. text .. "|r" end

-- "Ready to hand in", "From level 24"... for an entry.
function ns.StateText(e)
    if e.state == "later" or e.state == "other" then return L.FROM_LEVEL:format(e.req), S.MUTED end
    if e.state == "done" then return L.ST_DONE, S.FAINT end
    return L["ST_" .. e.state:upper()], e.state == "ready" and S.GOOD or S.TEXT
end

-- "+4 over your smallest bag (6)" for an entry against the bags worn.
function ns.GainText(e, bags)
    if e.state == "done" then return L.ST_DONE, S.FAINT end
    if ns.PERKS[e.kind] then return L["GAIN_" .. ns.Perk(e.item):upper()], S.GOOD end
    if not e.slots then return L.GAIN_UNKNOWN, S.MUTED end
    if not e.gain or e.gain <= 0 then return L.GAIN_NONE, S.MUTED end
    local same = bags.smallest[e.kind] or bags.smallest.bag
    if e.gain == e.slots or not same then return L.GAIN_FREE:format(e.gain), S.GOOD end
    return L.GAIN_OVER:format(e.gain, same.slots), S.GOOD
end

-- A small box over the window with a link to copy (Ctrl+C); the game cannot open a link.
local linkBox
function ns.ShowLink(url, title)
    if not url or not frame then return end
    local f = linkBox
    if not f then
        f = CreateFrame("Frame", nil, frame)
        linkBox = f
        f:SetSize(440, 104)
        f:SetPoint("CENTER")
        -- over the hub and every window: they are in DIALOG and raise their own children
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        if f.SetToplevel then f:SetToplevel(true) end
        f:EnableMouse(true)
        S.Box(f, S.SOLID, S.EDGE, S.R_LG)
        f.title = S.Text(f, 12, S.GOLD)
        f.title:SetPoint("TOPLEFT", 14, -12)
        f.title:SetPoint("RIGHT", -44, 0)
        f.title:SetWordWrap(false)
        f.edit = S.Edit(f, 412, 28)
        f.edit:SetPoint("TOPLEFT", 14, -34)
        f.edit:SetPoint("RIGHT", -14, 0)
        f.edit:SetJustifyH("LEFT")
        f.hint = S.Text(f, 12, S.MUTED)
        f.hint:SetPoint("BOTTOMLEFT", 14, 12)
        f.hint:SetPoint("RIGHT", -14, 0)
        f.hint:SetWordWrap(false)
        f.hint:SetText(L.LINK_HINT)
        local function close() f:Hide() end
        local function whole(self) if self.HighlightText then self:HighlightText() end end
        f.close = S.Close(f, close)
        f.close:SetPoint("TOPRIGHT", -4, -2)
        f.edit:SetScript("OnEscapePressed", close)
        f.edit:SetScript("OnEnterPressed", close)
        -- the link stays as it is, and stays selected, whatever the player types
        f.edit:HookScript("OnTextChanged", function(self, user)
            if user and f.url then self:SetText(f.url); whole(self) end
        end)
        f.edit:HookScript("OnMouseUp", whole)
    end
    f.url = url
    f.title:SetText(title and (L.WOWHEAD .. " " .. S.DOT .. " " .. title) or L.WOWHEAD)
    f.edit:SetText(url)
    f:Show()
    if f.Raise then f:Raise() end
    if f.edit.SetFocus then f.edit:SetFocus() end
    if f.edit.HighlightText then f.edit:HighlightText() end
    return f
end

-- The world map a click opened must not hide behind the window: while that map shows, the
-- window (and the hub around it) lies under it. Only our own frames change strata.
local lowered
function ns.MapClosed()
    if not lowered then return end
    for _, e in ipairs(lowered) do e[1]:SetFrameStrata(e[2]) end
    lowered = nil
end

function ns.BehindMap()
    local map = _G.WorldMapFrame
    if lowered or not frame or not frame:IsShown() or not map then return end
    lowered = {}
    local f = frame
    while f and f ~= UIParent and #lowered < 6 do
        local strata = f:GetFrameStrata()
        lowered[#lowered + 1] = { f, type(strata) == "string" and strata or "DIALOG" }
        f:SetFrameStrata("LOW")
        f = f:GetParent()
    end
    if not rawget(ns, "mapHooked") and map.HookScript then
        ns.mapHooked = true
        map:HookScript("OnHide", ns.MapClosed)
        frame:HookScript("OnHide", ns.MapClosed)
    end
end

-- The bags worn ---------------------------------------------------------------------------------

local function buildStrip(body)
    local c = S.Card(body)
    c.slots = {}
    for i = 1, 5 do
        local b = CreateFrame("Frame", nil, c)
        b:SetSize(62, 34)
        b:SetPoint("LEFT", 14 + (i - 1) * 64, 0)
        b.icon = S.IconBox(b, 30)
        b.icon:SetPoint("LEFT")
        b.n = S.Text(b, 13)
        b.n:SetPoint("LEFT", b.icon, "RIGHT", 5, 0)
        c.slots[i] = b
    end
    c.total = S.Text(c, 14)
    c.total:SetPoint("TOPLEFT", 344, -11)
    c.total:SetPoint("RIGHT", -14, 0)
    c.total:SetJustifyH("RIGHT")
    c.total:SetWordWrap(false)
    c.gain = S.Text(c, 12, S.MUTED)
    c.gain:SetPoint("BOTTOMLEFT", 344, 11)
    c.gain:SetPoint("RIGHT", -14, 0)
    c.gain:SetJustifyH("RIGHT")
    c.gain:SetWordWrap(false)
    return c
end

local function paintStrip(bags)
    local by = {}
    for _, b in ipairs(bags.list) do by[b.bag] = b end
    local small = bags.open == 0 and bags.smallest.bag or nil
    for i, slot in ipairs(strip.slots) do
        local b = by[i - 1]
        local least = b ~= nil and b == small
        slot.icon:SetIcon(b and (b.pack and PACK_ICON or (b.item and ns.ItemIcon(b.item)) or ns.KIND_ICON[b.kind]) or NO_BAG_ICON)
        slot.icon:SetAlpha(b and 1 or 0.45)
        slot.icon:SetGlow(least and S.WARN or nil)
        slot.n:SetText(b and tostring(b.slots) or "0")
        slot.n:SetTextColor(unpack(least and S.WARN or (b and S.TEXT or S.FAINT)))
    end
    strip.total:SetText(L.BAGS_TOTAL:format(bags.total))
    local gain, count = ns.Potential()
    if count > 0 then
        strip.gain:SetText(S.Emph(L.BAGS_GAIN:format(gain, count)))
        strip.gain:SetTextColor(unpack(S.GOOD))
    else
        strip.gain:SetText(L.BAGS_NONE)
        strip.gain:SetTextColor(unpack(S.MUTED))
    end
end

-- The list ----------------------------------------------------------------------------------------
-- Two pages show a list and one entry's page: the bag rewards and the class quests. Each page
-- keeps its own list, filter and choice in its table `P`.

local function makeRow(P)
    return function(r)
        S.NavRow(r)
        r.head = S.Text(r, 12, S.GOLD_DIM, nil, "bold")
        r.head:SetPoint("BOTTOMLEFT", 8, 6)
        r.head:SetPoint("RIGHT", -8, 0)
        r.head:SetJustifyH("LEFT")
        r.head:SetWordWrap(false)
        r.icon = S.IconBox(r, 32)
        r.icon:SetPoint("LEFT", 8, 0)
        r.gain = S.Text(r, 14, S.GOOD)
        r.gain:SetPoint("TOPRIGHT", -10, -8)
        r.gain:SetJustifyH("RIGHT")
        r.slots = S.Text(r, 12, S.FAINT)
        r.slots:SetPoint("BOTTOMRIGHT", -10, 8)
        r.slots:SetJustifyH("RIGHT")
        r.name = S.Text(r, 13)
        r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 9, 0)
        r.name:SetPoint("RIGHT", r.gain, "LEFT", -6, 0)
        r.name:SetJustifyH("LEFT")
        r.name:SetWordWrap(false)
        r.sub = S.Text(r, 12, S.MUTED)
        r.sub:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 9, 0)
        r.sub:SetPoint("RIGHT", r.slots, "LEFT", -6, 0)
        r.sub:SetJustifyH("LEFT")
        r.sub:SetWordWrap(false)
        r.click = CreateFrame("Button", nil, r)
        r.click:SetAllPoints()
        r.click:SetScript("OnClick", function(self)
            local e = self:GetParent().entry
            if e then P.selected = e.quest; ns.Refresh() end
        end)
    end
end

-- A class quest's row: the quest's name in gold, its level on the right, and the reward (or
-- how many it lets you choose from) under it.
local function fillRow(P)
    return function(r, it)
        local head = it.head ~= nil
        r.entry = not head and it or nil
        r.head:SetShown(head)
        r.icon:SetShown(not head)
        r.click:SetShown(not head)
        for _, t in ipairs({ r.gain, r.slots, r.name, r.sub }) do t:SetShown(not head) end
        r.line:SetShown(not head)
        if head then
            r:SetSelected(false)
            local name = (it.head == "all" and L.CQ_ALL:format(ns.ClassName(P.viewClass)))
                or (it.head == "level" and L.G_LEVEL:format(UnitLevel("player") or 1))
                or L["G_" .. it.head:upper()]
            r.head:SetText(S.Upper(name) .. "  " .. colour(it.count, S.FAINT))
            return
        end
        r:SetSelected(it.quest == P.selected)
        r.icon:SetIcon(ns.ItemIcon(it.item))
        r.icon:SetAlpha(it.state == "done" and 0.5 or 1)
        local text, c = ns.StateText(it)
        r.sub:SetText("|T" .. STATE_ICON[it.state] .. ":13|t " .. text)
        r.sub:SetTextColor(unpack(c))
        if it.class then
            r.name:SetText(ns.QuestTitle(it.quest))
            r.name:SetTextColor(unpack(it.state == "done" and S.FAINT or S.GOLD))
            r.gain:SetText(tostring(it.level))
            r.gain:SetTextColor(unpack(it.state == "done" and S.FAINT or S.LevelColor(it.level)))
            r.slots:SetText(#it.options > 1 and L.CQ_CHOICES:format(#it.options) or "")
            return
        end
        r.name:SetText(S.QualityHex(ns.ItemQuality(it.item)) .. ns.ItemName(it.item) .. "|r")
        r.name:SetTextColor(unpack(S.TEXT))
        r.gain:SetTextColor(unpack(S.GOOD))
        local up = it.state ~= "done" and it.gain and it.gain > 0
        r.gain:SetText(up and ("+" .. it.gain) or (it.state ~= "done" and ns.PERKS[it.kind] and L["SHORT_" .. ns.Perk(it.item):upper()]) or "")
        r.slots:SetText(it.slots and L.SLOTS:format(it.slots) or "")
    end
end

-- One entry's page ----------------------------------------------------------------------------------

local function iconButton(parent, text, icon, primary)
    local b = S.Button(parent, 110, 30)
    S.SetButtonIcon(b, icon)
    if primary then S.Primary(b) end
    function b:Fit(t, min)
        self:SetText(t)
        self:SetWidth(math.max(min or 96, math.floor((self.text:GetStringWidth() or 0) + 44)))
    end
    b:Fit(text)
    return b
end

-- The rows under an entry: a quest of the chain, a head, a reward item and a wrapped "what to
-- do" line.
local STEP_H, ITEM_H, TIP_LEFT, TIP_RIGHT, TIP_PAD, TIP_WIDTH = 24, 30, 28, 12, 5, 420

-- The game's tooltip of an item, or while the client has no data for it (it would only say
-- "Retrieving item information") its name and what is going on.
local function setItemTip(id)
    if ns.Known(id) and GameTooltip.SetItemByID then GameTooltip:SetItemByID(id) return end
    GameTooltip:AddLine(S.QualityHex(ns.ItemQuality(id)) .. ns.ItemName(id) .. "|r")
    GameTooltip:AddLine(ns.failed[id] and L.ITEM_UNKNOWN or L.ITEM_LOADING, unpack(S.MUTED))
end

local function itemTip(self)
    local id = self:GetParent().itemId
    if not (GameTooltip and id) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    setItemTip(id)
    GameTooltip:Show()
end

local function buildDetail(parent, P)
    local d = S.Card(parent)
    d.icon = S.IconBox(d, 44)
    d.icon:SetPoint("TOPLEFT", 14, -14)
    d.name = S.Text(d, 16, S.GOLD, nil, "title")
    d.name:SetPoint("TOPLEFT", d.icon, "TOPRIGHT", 12, -2)
    d.name:SetPoint("RIGHT", -14, 0)
    d.name:SetJustifyH("LEFT")
    d.name:SetWordWrap(false)
    d.kind = S.Text(d, 12, S.MUTED)
    d.kind:SetPoint("BOTTOMLEFT", d.icon, "BOTTOMRIGHT", 12, 2)
    d.kind:SetPoint("RIGHT", -14, 0)
    d.kind:SetJustifyH("LEFT")
    d.kind:SetWordWrap(false)
    local function line(y, size, c, lines)
        local t = S.Text(d, size, c)
        t:SetPoint("TOPLEFT", 14, y)
        t:SetPoint("RIGHT", -14, 0)
        t:SetJustifyH("LEFT")
        if lines then t:SetMaxLines(lines) else t:SetWordWrap(false) end
        return t
    end
    d.gain = line(-70, 13, S.GOOD)
    d.state = line(-92, 12, S.MUTED)
    d.what = line(-120, 13, S.TEXT)
    d.where = line(-139, 12, S.MUTED)
    d.offers = line(-160, 12, S.MUTED)
    -- One scrolling list: the rewards (class quests), what to do (wrapped lines), then the chain.
    d.stepsBox = CreateFrame("Frame", nil, d)
    d.stepsBox:SetPoint("TOPLEFT", 8, -180)
    d.stepsBox:SetPoint("BOTTOMRIGHT", -8, 84)
    d.measure = S.Text(d, 12)
    d.measure:SetJustifyH("LEFT")
    d.measure:Hide()
    d.steps = S.List(d.stepsBox, STEP_H, function(r)
        r.mark = r:CreateTexture(nil, "ARTWORK")
        r.mark:SetSize(14, 14)
        r.mark:SetPoint("LEFT", 6, 0)
        r.level = S.Text(r, 12, S.FAINT)
        r.level:SetPoint("RIGHT", -8, 0)
        r.name = S.Text(r, 12)
        r.name:SetPoint("LEFT", TIP_LEFT, 0)
        r.name:SetPoint("RIGHT", r.level, "LEFT", -6, 0)
        r.name:SetJustifyH("LEFT")
        r.name:SetWordWrap(false)
        r.head = S.Text(r, 12, S.GOLD_DIM, nil, "bold")
        r.head:SetPoint("BOTTOMLEFT", 6, 4)
        r.head:SetPoint("RIGHT", -8, 0)
        r.head:SetJustifyH("LEFT")
        r.head:SetWordWrap(false)
        r.num = S.Text(r, 12, S.FAINT)
        r.num:SetPoint("TOPLEFT", 8, -TIP_PAD)
        r.tip = S.Text(r, 12, S.TEXT)
        r.tip:SetPoint("TOPLEFT", TIP_LEFT, -TIP_PAD)
        r.tip:SetPoint("RIGHT", -TIP_RIGHT, 0)
        r.tip:SetJustifyH("LEFT")
        r.tip:SetJustifyV("TOP")
        r.item = S.IconBox(r, 22)
        r.item:SetPoint("LEFT", 4, 0)
        r.itemName = S.Text(r, 12)
        r.itemName:SetPoint("LEFT", r.item, "RIGHT", 8, 0)
        r.itemName:SetPoint("RIGHT", -8, 0)
        r.itemName:SetJustifyH("LEFT")
        r.itemName:SetWordWrap(false)
        r.hover = CreateFrame("Button", nil, r)
        r.hover:SetAllPoints()
        r.hover:SetScript("OnEnter", itemTip)
        r.hover:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end, function(r, st)
        local item = st.item ~= nil
        local step = not st.head and not st.tip and not item
        r.mark:SetShown(step)
        r.level:SetShown(step)
        r.name:SetShown(step)
        r.head:SetShown(st.head ~= nil)
        r.num:SetShown(st.tip ~= nil)
        r.tip:SetShown(st.tip ~= nil)
        r.item:SetShown(item)
        r.itemName:SetShown(item)
        r.hover:SetShown(item)
        r.itemId = st.item
        r.line:SetShown(not st.head)
        if st.head then
            r.head:SetText(st.head)
            return
        elseif st.tip then
            r.num:SetText(st.n .. ".")
            r.tip:SetText(st.tip)
            return
        elseif item then
            r.item:SetIcon(ns.ItemIcon(st.item))
            r.itemName:SetText(S.QualityHex(ns.ItemQuality(st.item)) .. ns.ItemName(st.item) .. "|r")
            return
        end
        r.mark:SetTexture(st.done and STATE_ICON.done or (st.now and STATE_ICON.take) or STATE_ICON.later)
        r.mark:SetDesaturated(not st.done and not st.now)
        r.name:SetText(st.n .. ".  " .. st.name)
        r.name:SetTextColor(unpack(st.done and S.FAINT or (st.now and S.TEXT or S.MUTED)))
        r.level:SetText(tostring(st.level))
        r.level:SetTextColor(unpack(st.done and S.FAINT or S.LevelColor(st.level)))
    end)
    d.steps.heightOf = function(st)
        if st.item then return ITEM_H end
        if st.head or not st.tip then return STEP_H end
        local w = d.stepsBox:GetWidth() or 0
        d.measure:SetWidth((w > 60 and w or TIP_WIDTH) - TIP_LEFT - TIP_RIGHT)
        d.measure:SetText(st.tip)
        return math.ceil(tonumber(d.measure:GetStringHeight()) or 14) + 2 * TIP_PAD
    end
    d.steps:SetAllPoints()

    d.lead = iconButton(d, L.LEAD, ACT_ICON.lead, true)
    d.lead:SetPoint("BOTTOMLEFT", 14, 48)
    d.lead:SetScript("OnClick", function()
        local e = P.shown[P.selected]
        if not e then return end
        if ns.Leads(e.quest) then ns.StopGuide() else ns.StartGuide({ e.quest }) end
    end)
    d.map = iconButton(d, L.MAP, ACT_ICON.map)
    d.map:SetPoint("LEFT", d.lead, "RIGHT", 8, 0)
    d.map:SetScript("OnClick", function()
        local e = P.shown[P.selected]
        local stop = e and ns.Stop(e)
        if not (stop and ns.SetPin(stop, true)) then footer:SetStatus(L.NO_PIN, S.WARN) end
    end)
    d.link = iconButton(d, L.WOWHEAD, ACT_ICON.link)
    d.link:SetPoint("BOTTOMLEFT", 14, 14)
    d.link:SetScript("OnClick", function()
        local e = P.shown[P.selected]
        local id = e and (e.cur or e.quest)
        -- a secret no quest gives links its item
        if id and id < 0 then ns.ShowLink(ns.WowheadURL("item", -id), ns.ItemName(-id))
        elseif id then ns.ShowLink(ns.WowheadURL("quest", id), ns.QuestTitle(id)) end
    end)
    d.hide = iconButton(d, L.HIDE, ACT_ICON.hide)
    d.hide:SetPoint("LEFT", d.link, "RIGHT", 8, 0)
    d.hide:SetScript("OnClick", function()
        local e = P.shown[P.selected]
        if e then ns.SetHidden(e.quest, true) end
    end)
    d.parts = { d.icon, d.name, d.kind, d.gain, d.state, d.what, d.where, d.offers, d.stepsBox,
                d.lead, d.map, d.link, d.hide }
    d.pick = S.Empty(d)
    d.pick:Set(P.class and L.CQ_PICK or L.PICK, "")
    return d
end

local function paintDetail(P, e, bags)
    local detail = P.detail
    for _, p in ipairs(detail.parts) do p:SetShown(e ~= nil) end
    detail.pick:SetShown(e == nil)
    if not e then return end
    detail.icon:SetIcon(ns.ItemIcon(e.item))
    local text, c
    if e.class then
        detail.name:SetText(ns.QuestTitle(e.quest))
        detail.kind:SetText(L.CQ_KIND:format(ns.ClassName(e.classId), e.level))
        detail.gain:SetText(#e.options > 1 and L.CQ_CHOOSE:format(#e.options) or L.CQ_GIVES)
        detail.gain:SetTextColor(unpack(S.GOOD))
    else
        detail.name:SetText(S.QualityHex(ns.ItemQuality(e.item)) .. ns.ItemName(e.item) .. "|r")
        detail.kind:SetText(L["KIND_" .. e.kind:upper()] .. (e.slots and (S.DOT .. S.Emph(L.SLOTS:format(e.slots))) or ""))
        text, c = ns.GainText(e, bags)
        detail.gain:SetText(text)
        detail.gain:SetTextColor(unpack(c))
    end
    text, c = ns.StateText(e)
    detail.state:SetText("|T" .. STATE_ICON[e.state] .. ":13|t " .. text)
    detail.state:SetTextColor(unpack(c))
    local stop = ns.Stop(e)
    if stop then
        local what, where = ns.StopText(stop)
        detail.what:SetText(what)
        detail.where:SetText(where)
    else
        detail.what:SetText("")
        detail.where:SetText("")
    end
    local offers = not e.class and #e.options > 1
    if offers then
        local names = {}
        for _, o in ipairs(e.options) do
            names[#names + 1] = S.QualityHex(ns.ItemQuality(o.item)) .. ns.ItemName(o.item) .. "|r"
        end
        detail.offers:SetText(L.OFFERS:format(table.concat(names, ", ")))
    else
        detail.offers:SetText("")
    end
    -- Without the line of the other rewards the list starts higher.
    detail.stepsBox:SetPoint("TOPLEFT", 8, offers and -180 or -160)
    detail.steps:SetData(ns.DetailRows(e, S.Upper(L.CHAIN) .. ((e.steps > 1 and not e.other) and
        ("  " .. colour(L.STEP_OF:format(math.min(e.step, e.steps), e.steps), S.FAINT)) or ""), S.Upper(L.TIPS),
        S.Upper(#e.options > 1 and L.CQ_CHOOSE_HEAD or L.CQ_REWARD_HEAD)))
    local leads = ns.Leads(e.quest)
    detail.lead:Fit(leads and L.STOP or L.LEAD, 150)
    detail.lead:SetEnabled(leads or (e.group == "now" and not ns.paused))
    -- another class's quest only shows where it starts: nothing to lead to or hide
    detail.lead:SetShown(not e.other)
    detail.map:ClearAllPoints()
    if e.other then detail.map:SetPoint("BOTTOMLEFT", 14, 48)
    else detail.map:SetPoint("LEFT", detail.lead, "RIGHT", 8, 0) end
    detail.map:SetEnabled(stop ~= nil and stop.pin == true)
    detail.hide:SetShown(e.state ~= "done" and not e.other)
end

-- The pages ---------------------------------------------------------------------------------------------

local rewardsP = { shown = {} }
local classP = { shown = {}, class = true }

local function listPage(body, P)
    local p = CreateFrame("Frame", nil, body)
    local left = S.Card(p)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(LIST_W)
    local top = 6
    if P.class then
        -- a round icon per class, this character's class chosen first
        local own = select(3, UnitClass("player"))
        local labels, icons, at = {}, {}, 1
        for i, id in ipairs(ns.CLASSES) do
            labels[i], icons[i] = "", ns.ClassIcon(id)
            if id == own then at = i end
        end
        classTabs = S.Tabs(left, labels, 34, function(i)
            P.viewClass = ns.CLASSES[i] ~= own and ns.CLASSES[i] or nil
            P.selected = nil
            ns.Refresh()
        end, 30, icons)
        classTabs.frame:ClearAllPoints()
        classTabs.frame:SetPoint("TOPLEFT", 8, -8)
        for i, b in ipairs(classTabs.buttons) do
            local id = ns.CLASSES[i]
            b.tip = id == own and L.CQ_YOURS:format(ns.ClassName(id)) or ns.ClassName(id)
        end
        classTabs:Select(at, true)
        top = 44
    else
        kinds = ns.Kinds()
        if #kinds > 1 then
            local labels, icons = { "" }, { S.TAB.list }
            for _, k in ipairs(kinds) do
                labels[#labels + 1] = ""
                icons[#icons + 1] = ns.KIND_ICON[k]
            end
            kindTabs = S.Tabs(left, labels, 44, function(i)
                P.kind = i > 1 and kinds[i - 1] or nil
                ns.Refresh()
            end, 30, icons)
            kindTabs.frame:ClearAllPoints()
            kindTabs.frame:SetPoint("TOPLEFT", 8, -8)
            for i, b in ipairs(kindTabs.buttons) do
                b.tip = i == 1 and L.KIND_ALL or L["KIND_" .. kinds[i - 1]:upper()]
            end
            top = 44
        end
    end
    local box = CreateFrame("Frame", nil, left)
    box:SetPoint("TOPLEFT", 4, -top)
    box:SetPoint("BOTTOMRIGHT", -4, 6)
    P.list = S.List(box, ROW_H, makeRow(P), fillRow(P))
    P.list:SetAllPoints()
    P.list.heightOf = function(it) return it.head and HEAD_H or ROW_H end
    P.empty = S.Empty(box)
    if P.class then P.empty:Set(L.CQ_EMPTY, L.CQ_EMPTY_SUB) else P.empty:Set(L.EMPTY, L.EMPTY_SUB) end
    P.detail = buildDetail(p, P)
    P.detail:SetPoint("TOPLEFT", left, "TOPRIGHT", S.GAP, 0)
    P.detail:SetPoint("BOTTOMRIGHT")
    return p
end

-- The library -------------------------------------------------------------------------------------
-- On top the books handed in and the four library rewards; under it the books in groups on the
-- left and one book's page on the right.

local libP = { shown = {}, library = true }
local LADDER_H, LEFT_W = 92, 186

local TIER_STATE = { done = "done", ready = "ready", log = "log", wait = "later", later = "later" }

local function tierText(t)
    if t.state == "done" then return L.LIB_T_DONE, S.FAINT end
    if t.state == "ready" then return L.LIB_T_READY, S.GOOD end
    if t.state == "log" then return L.ST_LOG, S.TEXT end
    if t.state == "wait" and t.left == 0 then return L.DO_HANDIN:format(t.hand), S.GOOD end
    if t.state == "wait" then return L.LIB_T_WAIT:format(t.left), S.MUTED end
    return L.FROM_LEVEL:format(t.req), S.MUTED
end

local GOAL_STAR = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"

local function tierTip(self)
    local t = self.tierData
    if not (GameTooltip and t) then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(L.LIB_TIER:format(t.need), 1, 0.82, 0)
    if self.goal then GameTooltip:AddLine(L.LIB_GOAL, S.Accent()[1], S.Accent()[2], S.Accent()[3]) end
    local text, c = tierText(t)
    GameTooltip:AddLine(text, c[1], c[2], c[3])
    GameTooltip:AddLine(L.WHERE:format(t.giver[1], ns.AreaName(t.giver[2]) or ""), 1, 1, 1)
    for _, id in ipairs(t.items) do
        GameTooltip:AddLine(S.QualityHex(ns.ItemQuality(id)) .. ns.ItemName(id) .. "|r")
    end
    if t.state ~= "done" or self.goal then
        local hint = self.goal and L.LIB_GOAL_CLEAR or L.LIB_GOAL_SET
        GameTooltip:AddLine(hint, S.MUTED[1], S.MUTED[2], S.MUTED[3])
    end
    GameTooltip:Show()
end

-- A click on a reward makes it the goal of the guide; a click on the goal takes it away.
local function tierClick(self)
    local t = self.tierData
    if not t or (t.state == "done" and not self.goal) then return end
    ns.SetLibGoal(t.quest)
    if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(self) then tierTip(self) end
end

local function buildLadder(p)
    local c = S.Card(p)
    c.label = S.Text(c, 12, S.MUTED)
    c.label:SetPoint("TOPLEFT", 14, -14)
    c.label:SetWidth(LEFT_W - 14)
    c.label:SetJustifyH("LEFT")
    c.label:SetWordWrap(false)
    c.label:SetText(S.Upper(L.LIB_HANDED))
    c.value = S.Text(c, 28, S.TEXT, nil, "title")
    c.value:SetPoint("TOPLEFT", 14, -32)
    c.bar = S.Progress(c, 6)
    c.bar:SetPoint("TOPLEFT", 14, -70)
    c.bar:SetWidth(LEFT_W - 28)
    c.tiles = {}
    for i = 1, 4 do
        local t = CreateFrame("Frame", nil, c)
        S.Box(t, S.RAISED, S.CARD_EDGE, S.R_LG)
        t.icons = {}
        for j = 1, 3 do
            local b = CreateFrame("Button", nil, t)
            b:SetSize(24, 24)
            b:SetPoint("TOPLEFT", 8 + (j - 1) * 27, -8)
            b.icon = S.IconBox(b, 24)
            b.icon:SetAllPoints()
            b:SetScript("OnEnter", function(self)
                if not (GameTooltip and self.itemId) then return end
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                setItemTip(self.itemId)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
            t.icons[j] = b
        end
        t.mark = t:CreateTexture(nil, "ARTWORK")
        t.mark:SetSize(14, 14)
        t.mark:SetPoint("TOPRIGHT", -8, -13)
        -- the goal: a gold star beside the state mark, so no word has to fit the tile
        t.star = t:CreateTexture(nil, "OVERLAY")
        t.star:SetSize(18, 18)
        t.star:SetPoint("RIGHT", t.mark, "LEFT", -4, 0)
        t.star:SetTexture(GOAL_STAR)
        t.star:Hide()
        t.need = S.Text(t, 12, S.GOLD_DIM, nil, "bold")
        t.need:SetPoint("TOPLEFT", 8, -38)
        t.need:SetPoint("RIGHT", -8, 0)
        t.need:SetJustifyH("LEFT")
        t.need:SetWordWrap(false)
        t.state = S.Text(t, 12)
        t.state:SetPoint("TOPLEFT", 8, -55)
        t.state:SetPoint("RIGHT", -8, 0)
        t.state:SetJustifyH("LEFT")
        t.state:SetWordWrap(false)
        t:EnableMouse(true)
        t:SetScript("OnEnter", tierTip)
        t:SetScript("OnMouseUp", tierClick)
        t:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        c.tiles[i] = t
    end
    function c:Layout(width)
        local n, gap = #self.tiles, 8
        local w = math.floor((width - LEFT_W - 14 - (n - 1) * gap) / n)
        for i, t in ipairs(self.tiles) do
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", LEFT_W + (i - 1) * (w + gap), -10)
            t:SetSize(w, LADDER_H - 20)
        end
    end
    return c
end

local function paintLadder(lib)
    local c = libP.ladder
    c.value:SetText(S.Emph(tostring(lib.handed)) .. colour(" / " .. lib.total, S.FAINT))
    c.bar:Set(lib.total > 0 and lib.handed / lib.total or 0, S.GOOD)
    local goal = ns.cdb and ns.cdb.libGoal
    for i, t in ipairs(c.tiles) do
        local d = lib.tiers[i]
        t.tierData = d
        t:SetShown(d ~= nil)
        if d then
            for j, b in ipairs(t.icons) do
                local id = d.items[j]
                b.itemId = id
                b:SetShown(id ~= nil)
                if id then
                    b.icon:SetIcon(ns.ItemIcon(id))
                    b.icon:SetAlpha(d.state == "done" and 0.5 or 1)
                end
            end
            t.goal = goal == d.quest
            local need = S.Upper(L.LIB_TIER:format(d.need))
            t.need:SetText(need)
            t.star:SetShown(t.goal)
            local text, col = tierText(d)
            t.state:SetText(text)
            t.state:SetTextColor(unpack(col))
            t.mark:SetTexture(STATE_ICON[TIER_STATE[d.state]])
            t.mark:SetDesaturated(d.state == "wait" or d.state == "later")
            S.SetBorder(t, (t.goal and S.Accent()) or (d.state == "ready" and S.GOOD) or S.CARD_EDGE)
        end
    end
end

-- A book's row: its name, its level on the right, and where it stands under it.
local function bookSub(e)
    if e.state == "bag" then return L.ST_BAG, S.GOOD end
    if e.state == "done" then return L.LG_DONE, S.FAINT end
    if e.state == "later" then return L.FROM_LEVEL:format(e.level - ns.BOOK_EARLY), S.MUTED end
    local place = ns.BookPlace(e)
    return place and ns.AreaName(place.area) or "", S.TEXT
end
ns.BookSub = bookSub

local function fillBook(r, it)
    local head = it.head ~= nil
    r.entry = not head and it or nil
    r.head:SetShown(head)
    r.icon:SetShown(not head)
    r.click:SetShown(not head)
    for _, t in ipairs({ r.gain, r.slots, r.name, r.sub }) do t:SetShown(not head) end
    r.line:SetShown(not head)
    if head then
        r:SetSelected(false)
        r.head:SetText(S.Upper(L["LG_" .. it.head:upper()]) .. "  " .. colour(it.count, S.FAINT))
        return
    end
    r:SetSelected(it.quest == libP.selected)
    r.itemId = it.item
    if not rawget(r, "bookTip") then
        rawset(r, "bookTip", true)
        r.click:SetScript("OnEnter", itemTip)
        r.click:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end
    r.icon:SetIcon(ns.ItemIcon(it.item))
    r.icon:SetAlpha(it.state == "done" and 0.5 or 1)
    r.name:SetText(S.QualityHex(ns.ItemQuality(it.item)) .. ns.ItemName(it.item) .. "|r")
    r.name:SetTextColor(unpack(S.TEXT))
    local text, c = bookSub(it)
    r.sub:SetText("|T" .. STATE_ICON[it.state] .. ":13|t " .. text)
    r.sub:SetTextColor(unpack(c))
    r.gain:SetText(tostring(it.level))
    r.gain:SetTextColor(unpack(it.state == "done" and S.FAINT or S.LevelColor(it.level)))
    r.slots:SetText("")
end

local function buildBook(parent)
    local d = S.Card(parent)
    d.icon = S.IconBox(d, 44)
    d.icon:SetPoint("TOPLEFT", 14, -14)
    d.name = S.Text(d, 16, S.GOLD, nil, "title")
    d.name:SetPoint("TOPLEFT", d.icon, "TOPRIGHT", 12, -2)
    d.name:SetPoint("RIGHT", -14, 0)
    d.name:SetJustifyH("LEFT")
    d.name:SetWordWrap(false)
    d.kind = S.Text(d, 12, S.MUTED)
    d.kind:SetPoint("BOTTOMLEFT", d.icon, "BOTTOMRIGHT", 12, 2)
    d.kind:SetPoint("RIGHT", -14, 0)
    d.kind:SetJustifyH("LEFT")
    d.kind:SetWordWrap(false)
    local function line(y, size, c, lines)
        local t = S.Text(d, size, c)
        t:SetPoint("TOPLEFT", 14, y)
        t:SetPoint("RIGHT", -14, 0)
        t:SetJustifyH("LEFT")
        if lines then t:SetMaxLines(lines) else t:SetWordWrap(false) end
        return t
    end
    -- the book's name may be long: the icon and the name show the book's tooltip
    d.hover = CreateFrame("Button", nil, d)
    d.hover:SetPoint("TOPLEFT", 14, -14)
    d.hover:SetPoint("RIGHT", -14, 0)
    d.hover:SetHeight(44)
    d.hover:SetScript("OnEnter", itemTip)
    d.hover:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    d.state = line(-72, 12, S.MUTED)
    d.placesHead = line(-102, 12, S.GOLD_DIM)
    d.places = {}
    for i = 1, 3 do d.places[i] = line(-102 - i * 19, 12, S.TEXT) end
    d.takerHead = line(-160, 12, S.GOLD_DIM)
    d.taker = line(-179, 12, S.TEXT)
    d.cage = line(-204, 12, S.WARN, 2)
    d.map = iconButton(d, L.MAP, ACT_ICON.map)
    d.map:SetPoint("BOTTOMLEFT", 14, 14)
    d.map:SetScript("OnClick", function()
        local e = libP.shown[libP.selected]
        local stop = e and ns.BookStop(e)
        if not (stop and ns.SetPin(stop, true)) then footer:SetStatus(L.NO_PIN, S.WARN) end
    end)
    d.link = iconButton(d, L.WOWHEAD, ACT_ICON.link)
    d.link:SetPoint("LEFT", d.map, "RIGHT", 8, 0)
    d.link:SetScript("OnClick", function()
        local e = libP.shown[libP.selected]
        if e then ns.ShowLink(ns.WowheadURL("item", e.item), ns.ItemName(e.item)) end
    end)
    d.parts = { d.icon, d.name, d.kind, d.hover, d.state, d.placesHead, d.takerHead, d.taker,
                d.cage, d.map, d.link }
    for _, t in ipairs(d.places) do d.parts[#d.parts + 1] = t end
    d.pick = S.Empty(d)
    d.pick:Set(L.LIB_PICK, "")
    return d
end

local function paintBook(e)
    local d = libP.detail
    for _, p in ipairs(d.parts) do p:SetShown(e ~= nil) end
    d.pick:SetShown(e == nil)
    if not e then return end
    d.itemId = e.item
    d.icon:SetIcon(ns.ItemIcon(e.item))
    d.name:SetText(S.QualityHex(ns.ItemQuality(e.item)) .. ns.ItemName(e.item) .. "|r")
    d.kind:SetText(L.LIB_KIND .. S.DOT .. L.LEVEL_N:format(e.level))
    local text, c = bookSub(e)
    if e.state == "take" then text, c = L.ST_TAKE, S.TEXT end
    d.state:SetText("|T" .. STATE_ICON[e.state] .. ":13|t " .. text)
    d.state:SetTextColor(unpack(c))
    local stop = ns.BookStop(e)
    d.placesHead:SetText(S.Upper(L.LIB_PLACES))
    for i, t in ipairs(d.places) do
        local p = e.places[i]
        t:SetShown(p ~= nil)
        if p then t:SetText((ns.AreaName(p.area) or "?") .. colour(string.format("  %.1f, %.1f", p.x, p.y), S.FAINT)) end
    end
    local n = math.min(#e.places, #d.places)
    d.takerHead:SetPoint("TOPLEFT", 14, -102 - (n + 1) * 19 - 10)
    d.taker:SetPoint("TOPLEFT", 14, -102 - (n + 2) * 19 - 10)
    d.cage:SetPoint("TOPLEFT", 14, -102 - (n + 3) * 19 - 14)
    d.takerHead:SetText(S.Upper(L.LIB_TAKER))
    local who = ns.Taker(e.taker)
    d.taker:SetText(L.WHERE:format(who[1], ns.AreaName(who[2]) or ""))
    d.cage:SetText(e.quest == ns.CAGE_KEY_BOOK and e.state ~= "done" and L.LIB_CAGE or "")
    d.map:SetEnabled(stop ~= nil and stop.pin == true)
end

local function libraryPage(body)
    local p = CreateFrame("Frame", nil, body)
    libP.ladder = buildLadder(p)
    libP.ladder:SetPoint("TOPLEFT")
    libP.ladder:SetPoint("TOPRIGHT")
    libP.ladder:SetHeight(LADDER_H)
    local left = S.Card(p)
    left:SetPoint("TOPLEFT", libP.ladder, "BOTTOMLEFT", 0, -S.GAP)
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(LIST_W)
    local box = CreateFrame("Frame", nil, left)
    box:SetPoint("TOPLEFT", 4, -6)
    box:SetPoint("BOTTOMRIGHT", -4, 6)
    libP.list = S.List(box, ROW_H, makeRow(libP), fillBook)
    libP.list:SetAllPoints()
    libP.list.heightOf = function(it) return it.head and HEAD_H or ROW_H end
    libP.empty = S.Empty(box)
    libP.empty:Set(L.LIB_EMPTY, L.LIB_EMPTY_SUB)
    libP.detail = buildBook(p)
    libP.detail:SetPoint("TOPLEFT", left, "TOPRIGHT", S.GAP, 0)
    libP.detail:SetPoint("BOTTOMRIGHT")
    return p
end

local function paintLibrary()
    local lib = ns.Library()
    local w = tonumber(libP.ladder:GetWidth()) or 0
    libP.ladder:Layout(w > 300 and w or 800)
    paintLadder(lib)
    local items, n = ns.BookList()
    libP.shown = {}
    local first
    for _, it in ipairs(items) do
        if not it.head then
            libP.shown[it.quest] = it
            first = first or it.quest
        end
    end
    if not libP.shown[libP.selected] then libP.selected = first end
    libP.list:SetData(items)
    libP.empty:SetShown(n == 0)
    paintBook(libP.shown[libP.selected])
    return lib
end

local function settingsPage(body, width)
    local page = S.ScrollPage(body, width)
    local st = S.Stack(page.inner)
    local function row(key)
        local up = key:upper()
        return { L["OPT_" .. up], L["OPT_" .. up .. "_TIP"], function() return ns.db[key] end,
                 function(v) ns.SetPref(key, v) end, icon = ns.OPT_ICON[key] }
    end
    for _, sec in ipairs({ { L.SEC_LIST, { "better", "showDone" } }, { L.SEC_NOTICES, { "notify" } } }) do
        local rows = {}
        for _, k in ipairs(sec[2]) do rows[#rows + 1] = row(k) end
        local card, h = S.SettingsCard(page.inner, sec[1], rows)
        st:Add(card, h)
    end
    page:SetContent(st:Height())
    return page
end

local current = 1       -- the page tab shown

local function paintList(P, bags)
    local items, n
    if P.class then items, n = ns.List("class", P.viewClass) else items, n = ns.List(P.kind) end
    P.shown = {}
    local first
    for _, it in ipairs(items) do
        if not it.head then
            P.shown[it.quest] = it
            first = first or it.quest
        end
    end
    if not P.shown[P.selected] then P.selected = first end
    P.list:SetData(items)
    P.count = n
    P.empty:SetShown(n == 0)
    paintDetail(P, P.shown[P.selected], bags)
end

local function paintWindow()
    local bags = ns.Bags()
    paintStrip(bags)
    better:SetChecked(ns.db.better)
    if current == 3 then
        leadAll:SetShown(true)
        local lib = paintLibrary()
        local open = ns.LeadCount()
        if ns.Guiding() then
            leadAll:SetText(L.STOP)
            leadAll:SetEnabled(true)
            footer:SetStatus(L.STATUS_LEAD:format(ns.stop and ns.StopText(ns.stop) or ""), S.Accent())
        else
            leadAll:SetText(L.LIB_LEAD:format(open))
            leadAll:SetEnabled(open > 0 and not ns.paused)
            local goal = ns.LibGoal(lib)
            if goal and goal.left > 0 then
                footer:SetStatus(L.LIB_GOAL_STATUS:format(goal.need, goal.left))
            elseif goal then
                footer:SetStatus(L.LIB_GOAL_ENOUGH:format(goal.need), S.GOOD)
            else
                footer:SetStatus(L.LIB_STATUS:format(lib.handed, lib.total))
            end
        end
        return
    end
    local class = current == 2
    paintList(class and classP or rewardsP, bags)
    local targets = #ns.Targets(class)
    local other = class and classP.viewClass
    -- another class's quests are only to look at: no Lead through all
    leadAll:SetShown(not (other and not ns.Guiding()))
    if other and not ns.Guiding() then
        footer:SetStatus(L.CQ_STATUS_OTHER:format(ns.ClassName(other), classP.count or 0))
    elseif ns.Guiding() then
        leadAll:SetText(L.STOP)
        leadAll:SetEnabled(true)
        local what = ns.stop and ns.StopText(ns.stop) or ""
        footer:SetStatus(L.STATUS_LEAD:format(what), S.Accent())
    else
        leadAll:SetText(L.LEAD_ALL:format(targets))
        leadAll:SetEnabled(targets > 0 and not ns.paused)
        local open = class and L.CQ_STATUS_OPEN or L.STATUS_OPEN
        footer:SetStatus(targets > 0 and open:format(targets) or L.STATUS_NONE)
    end
end

function ns.Refresh()
    if not ns.db then return end
    if frame and frame:IsShown() then paintWindow() end
end

-- A class's round icon by its id (nil is this character's class).
function ns.ClassIcon(id)
    local file = id and ns.CLASS_TOKEN[id] or select(2, UnitClass("player"))
    if type(file) ~= "string" or file == "" then return S.TAB.quests end
    return "Interface\\Icons\\ClassIcon_" .. file:sub(1, 1) .. file:sub(2):lower()
end
local function classIcon() return ns.ClassIcon() end

local function build()
    frame = S.Window("GulliWorthItFrame", L.TITLE, S.WIDE_W, S.DOCK_H)
    local body, width = frame.body, frame.inner[1]
    footer = S.Footer(frame)
    leadAll = S.Primary(S.Button(frame, 250, 30))
    leadAll:SetScript("OnClick", function()
        if ns.Guiding() then
            ns.StopGuide()
        elseif current == 3 then
            if not ns.StartLibrary() then footer:SetStatus(L.LIB_NOTHING, S.WARN) end
        elseif not ns.StartGuide(nil, current == 2) then
            footer:SetStatus(current == 2 and L.CQ_NOTHING or L.NOTHING, S.WARN)
        end
    end)
    footer:Add(leadAll)
    local st = S.Stack(body)
    strip = buildStrip(body)
    st:Add(strip, 52)
    tabs = S.PageTabs(body, { L.TAB_REWARDS, L.TAB_CLASS, L.TAB_LIBRARY, L.TAB_SETTINGS }, nil, function(i)
        current = i
        for j, p in ipairs(pages) do p:SetShown(j == i) end
        if better then better:SetShown(i == 1) end
        footer:SetShown(i ~= 4)
        ns.Refresh()
    end, nil, { S.TAB.list, classIcon(), ns.BOOK_ICON, S.TAB.settings })
    tabs.frame:ClearAllPoints()
    tabs.frame:SetPoint("TOPLEFT", 0, -st.y)
    better = S.SwitchLabel(body, L.ONLY_BETTER, function() return ns.db.better end,
        function(v) ns.SetPref("better", v) end, 220)
    better:SetPoint("TOPRIGHT", body, "TOPRIGHT", -224, -st.y + 3)
    st:Space(30 + S.GAP)
    pages[1] = listPage(body, rewardsP)
    pages[2] = listPage(body, classP)
    pages[3] = libraryPage(body)
    pages[4] = settingsPage(body, width)
    for i, p in ipairs(pages) do
        p:SetPoint("TOPLEFT", 0, -st.y)
        p:SetPoint("BOTTOMRIGHT")
        p:SetShown(i == 1)
    end
    frame:HookScript("OnShow", function() ns.Prefetch(); ns.Refresh() end)
end

function ns.Toggle()
    if S.ToggleWindow(ns.Window()) then ns.Refresh() end
end

-- Opens the window on one entry (a notice's button, a click on the tracker): a class quest on
-- its own page, a library book or reward on the library's, a bag reward on the first.
function ns.Show(quest)
    local f = ns.Window()
    if not f:IsShown() then ns.Toggle() end
    local book = ns.Book(quest)
    local tier = false
    for _, t in ipairs(ns.Data.tiers or {}) do if t[1] == quest then tier = true end end
    if book or tier then
        tabs:Select(3)
        if book then libP.selected = quest end
        ns.Refresh()
        return
    end
    local class = false
    for _, e in ipairs(ns.ClassQuests()) do if e.quest == quest then class = true end end
    if class and classP.viewClass then
        -- back to this character's own class, where the quest is
        classP.viewClass = nil
        local own = select(3, UnitClass("player"))
        for i, id in ipairs(ns.CLASSES) do if id == own then classTabs:Select(i, true) end end
    end
    tabs:Select(class and 2 or 1)
    if class then classP.selected = quest else rewardsP.selected = quest end
    ns.Refresh()
end

-- The window, for the hub (/gulli) to show inside it.
function ns.Window()
    if not frame then build() end
    return frame
end

-- For the tests and the previews.
local function pageP() return (current == 2 and classP) or (current == 3 and libP) or rewardsP end
function ns.Parts()
    local P = pageP()
    return frame, P.list, P.detail, tabs, leadAll, strip, libP.ladder
end
function ns.Selected() return pageP().selected end
ns.ShowBook = function(quest) ns.Show(quest) end
function ns.ViewClass(id)
    ns.Window()
    for i, c in ipairs(ns.CLASSES) do if c == id then classTabs:Select(i) end end
end

-- The tracker -----------------------------------------------------------------------------------------------
-- A small Gulli HUD panel while the guide leads: a row per reward with what to do now and
-- where; the first row is the stop the pin is on. The map button pins a row's stop, a click
-- opens the reward in the window, the cross ends the guide. It shows by itself, so it has no
-- show switch; the hub's Unlock mode places it.

local TW, T_HEAD, T_ROW, T_BOOK, T_MORE = 290, 28, 56, 40, 22
local tracker

function ns.PlaceTracker()
    if not tracker then return end
    tracker:ClearAllPoints()
    local p = ns.db and ns.db.trackerPoint
    if p then tracker:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
    else tracker:SetPoint("RIGHT", UIParent, "RIGHT", -260, -120) end
end

local function trackerRow(parent)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(T_ROW)
    r.icon = S.IconBox(r, 24)
    r.icon:SetPoint("TOPLEFT", 8, -7)
    r.pin = CreateFrame("Button", nil, r)
    r.pin:SetSize(22, 22)
    r.pin:SetPoint("TOPRIGHT", -6, -6)
    r.pin.icon = S.IconBox(r.pin, 22, ACT_ICON.map)
    r.pin.icon:SetAllPoints()
    r.pin:SetScript("OnClick", function(self)
        local it = self:GetParent().item
        if it and it.pin then ns.SetPin(it.pin, true) end
    end)
    r.pin:SetScript("OnEnter", function(self)
        local it = self:GetParent().item
        if not (GameTooltip and it and it.pin) then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(L.TR_PIN:format(it.pin.who), 1, 1, 1)
        GameTooltip:Show()
    end)
    r.pin:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    local function text(y, size, c)
        local t = S.Text(r, size, c)
        t:SetPoint("TOPLEFT", 40, y)
        t:SetPoint("RIGHT", -32, 0)
        t:SetJustifyH("LEFT")
        t:SetWordWrap(false)
        return t
    end
    r.name = text(-6, 12)
    r.what = text(-22, 12, S.TEXT)
    r.where = text(-36, 12, S.MUTED)
    r:SetScript("OnClick", function(self) if self.item then ns.Show(self.item.quest) end end)
    -- a book's name may be cut: its row shows the book's tooltip
    r:SetScript("OnEnter", function(self)
        local it = self.item
        if not (GameTooltip and it and it.book and it.item) then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        setItemTip(it.item)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return r
end

local function buildTracker()
    tracker = CreateFrame("Frame", "GulliWorthItTracker", UIParent)
    tracker:SetSize(TW, T_HEAD + 40)
    tracker:SetFrameStrata("MEDIUM")
    tracker:SetClampedToScreen(true)
    tracker:EnableMouse(true)
    S.HudPanel(tracker)
    tracker.icon = S.IconBox(tracker, 18, ns.ICON)
    tracker.icon:SetPoint("TOPLEFT", 8, -5)
    tracker.close = S.Close(tracker, function() ns.StopGuide() end)
    tracker.close:SetSize(24, 24)
    tracker.close:SetPoint("TOPRIGHT", -2, -2)
    tracker.title = S.Text(tracker, 12)
    tracker.title:SetPoint("LEFT", tracker.icon, "RIGHT", 8, 0)
    tracker.title:SetPoint("RIGHT", tracker.close, "LEFT", -6, 0)
    tracker.title:SetJustifyH("LEFT")
    tracker.title:SetWordWrap(false)
    tracker.title:SetText(L.TR_TITLE)
    local line = S.Divider(tracker)
    line:SetPoint("TOPLEFT", 1, -T_HEAD)
    line:SetPoint("TOPRIGHT", -1, -T_HEAD)
    line:SetHeight(1)
    tracker.empty = S.Text(tracker, 12, S.FAINT)
    tracker.empty:SetPoint("TOPLEFT", 10, -T_HEAD - 10)
    tracker.empty:SetPoint("RIGHT", -10, 0)
    tracker.empty:SetJustifyH("LEFT")
    tracker.empty:SetText(L.TR_EMPTY)
    tracker.rows = {}
    for i = 1, math.max(ns.TRACK_MAX, ns.TRACK_BOOKS) do tracker.rows[i] = trackerRow(tracker) end
    -- through the library only the nearest stops show: the rest is one line under them
    tracker.more = S.Text(tracker, 12, S.FAINT)
    tracker.more:SetJustifyH("LEFT")
    tracker.more:SetWordWrap(false)
    S.Mover(tracker, { label = L.TR_TITLE,
        save = function(p, rp, x, y) if ns.db then ns.db.trackerPoint = { p, rp, x, y } end end,
        reset = function() if ns.db then ns.db.trackerPoint = nil end; ns.PlaceTracker() end })
    tracker:Hide()
end

function ns.MoveTracker(on)
    ns.movingTracker = on and true or nil
    ns.RefreshTracker()
end

function ns.RefreshTracker()
    if not ns.db then return end
    local moving = ns.movingTracker
    if not ((ns.Guiding() and not ns.paused) or moving) then
        if tracker then tracker:SetMoving(false); tracker:Hide() end
        return
    end
    if not tracker then buildTracker() end
    ns.PlaceTracker()
    local items, more = {}, 0
    if ns.Guiding() then items, more = ns.TrackerItems() end
    tracker.title:SetText(ns.LeadsLibrary() and L.TR_LIB or L.TR_TITLE)
    local y = T_HEAD + 2
    for i, r in ipairs(tracker.rows) do
        local it = items[i]
        r.item = it
        r:SetShown(it ~= nil)
        if it then
            local h = it.book and T_BOOK or T_ROW
            r:SetHeight(h)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 1, -y)
            r:SetPoint("TOPRIGHT", -1, -y)
            y = y + h
            r.icon:SetIcon(ns.ItemIcon(it.item))
            r.name:SetText(it.name)
            r.name:SetTextColor(unpack(it.first and S.Accent() or S.GOLD))
            r.what:SetShown(not it.book)
            r.what:SetText("|T" .. STATE_ICON[it.state] .. ":12|t " .. (it.what or ""))
            r.where:ClearAllPoints()
            r.where:SetPoint("TOPLEFT", 40, it.book and -22 or -36)
            r.where:SetPoint("RIGHT", -32, 0)
            r.where:SetText(it.book and ("|T" .. STATE_ICON[it.state] .. ":12|t " .. (it.where or "")) or (it.where or ""))
            r.pin:SetShown(it.pin ~= nil)
        end
    end
    tracker.more:SetShown(more > 0)
    if more > 0 then
        tracker.more:ClearAllPoints()
        tracker.more:SetPoint("TOPLEFT", 40, -y - 4)
        tracker.more:SetPoint("RIGHT", -10, 0)
        tracker.more:SetText(L.TR_MORE:format(more))
        y = y + T_MORE
    end
    tracker.empty:SetShown(#items == 0)
    tracker:SetHeight(#items > 0 and (y + 4) or (T_HEAD + 40))
    tracker:SetMoving(moving and not (InCombatLockdown and InCombatLockdown()))
    tracker:Show()
end

-- The panel, for the hub's Unlock mode (built when it is asked for) and the tests.
function ns.TrackerFrame()
    if not tracker and ns.db then buildTracker() end
    return tracker
end
