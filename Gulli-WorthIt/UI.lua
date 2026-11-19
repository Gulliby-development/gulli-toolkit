-- The window (the bags worn, the rewards in groups, one reward's page with its chain and the
-- buttons that lead to it, the settings) and the guide's tracker on the screen. It only shows
-- what Core.lua worked out.

local _, ns = ...
local L = ns.L
local S = ns.Skin
local TI = "Interface\\Icons\\"

local frame, footer, leadAll, strip, tabs, better, list, empty, detail, kindTabs
local pages = {}
local kinds, kindFilter, selected = {}, nil, nil
local shown = {}        -- quest -> the entry the list shows now

local LIST_W, HEAD_H, ROW_H = 336, 28, 48
local PACK_ICON = "Interface\\Icons\\INV_Misc_Bag_08"
local NO_BAG_ICON = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"
local STATE_ICON = {
    ready = "Interface\\GossipFrame\\ActiveQuestIcon", log = "Interface\\GossipFrame\\IncompleteQuestIcon",
    take = "Interface\\GossipFrame\\AvailableQuestIcon", later = "Interface\\RaidFrame\\ReadyCheck-Waiting",
    done = "Interface\\RaidFrame\\ReadyCheck-Ready",
}
local ACT_ICON = { map = TI .. "INV_Misc_Map_01", lead = TI .. "Ability_Hunter_Pathfinding",
                   link = TI .. "INV_Misc_Book_09", hide = TI .. "Ability_Stealth" }

local function colour(text, c) return S.Hex(c) .. text .. "|r" end

-- "Ready to hand in", "From level 24"... for an entry.
function ns.StateText(e)
    if e.state == "later" then return L.FROM_LEVEL:format(e.req), S.MUTED end
    if e.state == "done" then return L.ST_DONE, S.FAINT end
    return L["ST_" .. e.state:upper()], e.state == "ready" and S.GOOD or S.TEXT
end

-- "+4 over your smallest bag (6)" for an entry against the bags worn.
function ns.GainText(e, bags)
    if e.state == "done" then return L.ST_DONE, S.FAINT end
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
        f:SetFrameStrata("DIALOG")
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

local function makeRow(r)
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
        if e then selected = e.quest; ns.Refresh() end
    end)
end

local function fillRow(r, it)
    local head = it.head ~= nil
    r.entry = not head and it or nil
    r.head:SetShown(head)
    r.icon:SetShown(not head)
    r.click:SetShown(not head)
    for _, t in ipairs({ r.gain, r.slots, r.name, r.sub }) do t:SetShown(not head) end
    r.line:SetShown(not head)
    if head then
        r:SetSelected(false)
        r.head:SetText(S.Upper(L["G_" .. it.head:upper()]) .. "  " .. colour(it.count, S.FAINT))
        return
    end
    r:SetSelected(it.quest == selected)
    r.icon:SetIcon(ns.ItemIcon(it.item))
    r.icon:SetAlpha(it.state == "done" and 0.5 or 1)
    r.name:SetText(S.QualityHex(ns.ItemQuality(it.item)) .. ns.ItemName(it.item) .. "|r")
    local text, c = ns.StateText(it)
    r.sub:SetText("|T" .. STATE_ICON[it.state] .. ":13|t " .. text)
    r.sub:SetTextColor(unpack(c))
    local up = it.state ~= "done" and it.gain and it.gain > 0
    r.gain:SetText(up and ("+" .. it.gain) or "")
    r.slots:SetText(it.slots and L.SLOTS:format(it.slots) or "")
end

-- One reward's page ----------------------------------------------------------------------------------

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

local function buildDetail(parent)
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
    d.chain = S.Text(d, 12, S.GOLD_DIM, nil, "bold")
    d.chain:SetPoint("TOPLEFT", 14, -186)
    d.stepsBox = CreateFrame("Frame", nil, d)
    d.stepsBox:SetPoint("TOPLEFT", 8, -204)
    d.stepsBox:SetPoint("BOTTOMRIGHT", -8, 84)
    d.steps = S.List(d.stepsBox, 24, function(r)
        r.mark = r:CreateTexture(nil, "ARTWORK")
        r.mark:SetSize(14, 14)
        r.mark:SetPoint("LEFT", 6, 0)
        r.level = S.Text(r, 12, S.FAINT)
        r.level:SetPoint("RIGHT", -8, 0)
        r.name = S.Text(r, 12)
        r.name:SetPoint("LEFT", 28, 0)
        r.name:SetPoint("RIGHT", r.level, "LEFT", -6, 0)
        r.name:SetJustifyH("LEFT")
        r.name:SetWordWrap(false)
    end, function(r, st)
        r.mark:SetTexture(st.done and STATE_ICON.done or (st.now and STATE_ICON.take) or STATE_ICON.later)
        r.mark:SetDesaturated(not st.done and not st.now)
        r.name:SetText(st.n .. ".  " .. st.name)
        r.name:SetTextColor(unpack(st.done and S.FAINT or (st.now and S.TEXT or S.MUTED)))
        r.level:SetText(tostring(st.level))
        r.level:SetTextColor(unpack(st.done and S.FAINT or S.LevelColor(st.level)))
    end)
    d.steps:SetAllPoints()

    d.lead = iconButton(d, L.LEAD, ACT_ICON.lead, true)
    d.lead:SetPoint("BOTTOMLEFT", 14, 48)
    d.lead:SetScript("OnClick", function()
        local e = shown[selected]
        if not e then return end
        if ns.Leads(e.quest) then ns.StopGuide() else ns.StartGuide({ e.quest }) end
    end)
    d.map = iconButton(d, L.MAP, ACT_ICON.map)
    d.map:SetPoint("LEFT", d.lead, "RIGHT", 8, 0)
    d.map:SetScript("OnClick", function()
        local e = shown[selected]
        local stop = e and ns.Stop(e)
        if not (stop and ns.SetPin(stop, true)) then footer:SetStatus(L.NO_PIN, S.WARN) end
    end)
    d.link = iconButton(d, L.WOWHEAD, ACT_ICON.link)
    d.link:SetPoint("BOTTOMLEFT", 14, 14)
    d.link:SetScript("OnClick", function()
        local e = shown[selected]
        if e then ns.ShowLink(ns.WowheadURL("quest", e.cur or e.quest), ns.QuestTitle(e.cur or e.quest)) end
    end)
    d.hide = iconButton(d, L.HIDE, ACT_ICON.hide)
    d.hide:SetPoint("LEFT", d.link, "RIGHT", 8, 0)
    d.hide:SetScript("OnClick", function()
        local e = shown[selected]
        if e then ns.SetHidden(e.quest, true) end
    end)
    d.parts = { d.icon, d.name, d.kind, d.gain, d.state, d.what, d.where, d.offers, d.chain, d.stepsBox,
                d.lead, d.map, d.link, d.hide }
    d.pick = S.Empty(d)
    d.pick:Set(L.PICK, "")
    return d
end

local function paintDetail(e, bags)
    for _, p in ipairs(detail.parts) do p:SetShown(e ~= nil) end
    detail.pick:SetShown(e == nil)
    if not e then return end
    detail.icon:SetIcon(ns.ItemIcon(e.item))
    detail.name:SetText(S.QualityHex(ns.ItemQuality(e.item)) .. ns.ItemName(e.item) .. "|r")
    detail.kind:SetText(L["KIND_" .. e.kind:upper()] .. (e.slots and (S.DOT .. S.Emph(L.SLOTS:format(e.slots))) or ""))
    local text, c = ns.GainText(e, bags)
    detail.gain:SetText(text)
    detail.gain:SetTextColor(unpack(c))
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
    if #e.options > 1 then
        local names = {}
        for _, o in ipairs(e.options) do
            names[#names + 1] = S.QualityHex(ns.ItemQuality(o.item)) .. ns.ItemName(o.item) .. "|r"
        end
        detail.offers:SetText(L.OFFERS:format(table.concat(names, ", ")))
    else
        detail.offers:SetText("")
    end
    detail.chain:SetText(S.Upper(L.CHAIN) .. (e.steps > 1 and
        ("  " .. colour(L.STEP_OF:format(math.min(e.step, e.steps), e.steps), S.FAINT)) or ""))
    detail.steps:SetData(ns.Steps(e))
    local leads = ns.Leads(e.quest)
    detail.lead:Fit(leads and L.STOP or L.LEAD, 150)
    detail.lead:SetEnabled(leads or (e.group == "now" and not ns.paused))
    detail.map:SetEnabled(stop ~= nil and stop.pin == true)
    detail.hide:SetShown(e.state ~= "done")
end

-- The pages ---------------------------------------------------------------------------------------------

local function rewardsPage(body)
    local p = CreateFrame("Frame", nil, body)
    local left = S.Card(p)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(LIST_W)
    local top = 6
    kinds = ns.Kinds()
    if #kinds > 1 then
        local labels, icons = { "" }, { S.TAB.list }
        for _, k in ipairs(kinds) do
            labels[#labels + 1] = ""
            icons[#icons + 1] = ns.KIND_ICON[k]
        end
        kindTabs = S.Tabs(left, labels, 44, function(i)
            kindFilter = i > 1 and kinds[i - 1] or nil
            ns.Refresh()
        end, 30, icons)
        kindTabs.frame:ClearAllPoints()
        kindTabs.frame:SetPoint("TOPLEFT", 8, -8)
        for i, b in ipairs(kindTabs.buttons) do
            b.tip = i == 1 and L.KIND_ALL or L["KIND_" .. kinds[i - 1]:upper()]
        end
        top = 44
    end
    local box = CreateFrame("Frame", nil, left)
    box:SetPoint("TOPLEFT", 4, -top)
    box:SetPoint("BOTTOMRIGHT", -4, 6)
    list = S.List(box, ROW_H, makeRow, fillRow)
    list:SetAllPoints()
    list.heightOf = function(it) return it.head and HEAD_H or ROW_H end
    empty = S.Empty(box)
    empty:Set(L.EMPTY, L.EMPTY_SUB)
    detail = buildDetail(p)
    detail:SetPoint("TOPLEFT", left, "TOPRIGHT", S.GAP, 0)
    detail:SetPoint("BOTTOMRIGHT")
    return p
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

local function paintWindow()
    local items, n = ns.List(kindFilter)
    local bags = ns.Bags()
    paintStrip(bags)
    shown = {}
    local first
    for _, it in ipairs(items) do
        if not it.head then
            shown[it.quest] = it
            first = first or it.quest
        end
    end
    if not shown[selected] then selected = first end
    list:SetData(items)
    empty:SetShown(n == 0)
    paintDetail(shown[selected], bags)
    better:SetChecked(ns.db.better)
    local targets = #ns.Targets()
    if ns.Guiding() then
        leadAll:SetText(L.STOP)
        leadAll:SetEnabled(true)
        local what = ns.stop and ns.StopText(ns.stop) or ""
        footer:SetStatus(L.STATUS_LEAD:format(what), S.Accent())
    else
        leadAll:SetText(L.LEAD_ALL:format(targets))
        leadAll:SetEnabled(targets > 0 and not ns.paused)
        footer:SetStatus(targets > 0 and L.STATUS_OPEN:format(targets) or L.STATUS_NONE)
    end
end

function ns.Refresh()
    if not ns.db then return end
    if frame and frame:IsShown() then paintWindow() end
end

local function build()
    frame = S.Window("GulliWorthItFrame", L.TITLE, S.WIDE_W, S.DOCK_H)
    local body, width = frame.body, frame.inner[1]
    footer = S.Footer(frame)
    leadAll = S.Primary(S.Button(frame, 250, 30))
    leadAll:SetScript("OnClick", function()
        if ns.Guiding() then ns.StopGuide() elseif not ns.StartGuide() then footer:SetStatus(L.NOTHING, S.WARN) end
    end)
    footer:Add(leadAll)
    local st = S.Stack(body)
    strip = buildStrip(body)
    st:Add(strip, 52)
    tabs = S.PageTabs(body, { L.TAB_REWARDS, L.TAB_SETTINGS }, nil, function(i)
        for j, p in ipairs(pages) do p:SetShown(j == i) end
        if better then better:SetShown(i == 1) end
        footer:SetShown(i == 1)
        ns.Refresh()
    end, nil, { S.TAB.list, S.TAB.settings })
    tabs.frame:ClearAllPoints()
    tabs.frame:SetPoint("TOPLEFT", 0, -st.y)
    better = S.SwitchLabel(body, L.ONLY_BETTER, function() return ns.db.better end,
        function(v) ns.SetPref("better", v) end, 220)
    better:SetPoint("TOPRIGHT", body, "TOPRIGHT", -224, -st.y + 3)
    st:Space(30 + S.GAP)
    pages[1] = rewardsPage(body)
    pages[2] = settingsPage(body, width)
    for i, p in ipairs(pages) do
        p:SetPoint("TOPLEFT", 0, -st.y)
        p:SetPoint("BOTTOMRIGHT")
        p:SetShown(i == 1)
    end
    frame:HookScript("OnShow", function() ns.Refresh() end)
end

function ns.Toggle()
    if S.ToggleWindow(ns.Window()) then ns.Refresh() end
end

-- Opens the window on one reward (a notice's button, a click on the tracker).
function ns.Show(quest)
    local f = ns.Window()
    if not f:IsShown() then ns.Toggle() end
    tabs:Select(1)
    selected = quest
    ns.Refresh()
end

-- The window, for the hub (/gulli) to show inside it.
function ns.Window()
    if not frame then build() end
    return frame
end

-- For the tests and the previews.
function ns.Parts() return frame, list, detail, tabs, leadAll, strip end
function ns.Selected() return selected end

-- The tracker -----------------------------------------------------------------------------------------------
-- A small Gulli HUD panel while the guide leads: a row per reward with what to do now and
-- where; the first row is the stop the pin is on. The map button pins a row's stop, a click
-- opens the reward in the window, the cross ends the guide. It shows by itself, so it has no
-- show switch; the hub's Unlock mode places it.

local TW, T_HEAD, T_ROW = 290, 28, 56
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
    for i = 1, ns.TRACK_MAX do
        local r = trackerRow(tracker)
        r:SetPoint("TOPLEFT", 1, -(T_HEAD + 2 + (i - 1) * T_ROW))
        r:SetPoint("TOPRIGHT", -1, -(T_HEAD + 2 + (i - 1) * T_ROW))
        tracker.rows[i] = r
    end
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
    local items = ns.Guiding() and ns.TrackerItems() or {}
    for i, r in ipairs(tracker.rows) do
        local it = items[i]
        r.item = it
        r:SetShown(it ~= nil)
        if it then
            r.icon:SetIcon(ns.ItemIcon(it.item))
            r.name:SetText(it.name)
            r.name:SetTextColor(unpack(it.first and S.Accent() or S.GOLD))
            r.what:SetText("|T" .. STATE_ICON[it.state] .. ":12|t " .. (it.what or ""))
            r.where:SetText(it.where or "")
            r.pin:SetShown(it.pin ~= nil)
        end
    end
    tracker.empty:SetShown(#items == 0)
    tracker:SetHeight(T_HEAD + 6 + (#items > 0 and #items * T_ROW or 34))
    tracker:SetMoving(moving and not (InCombatLockdown and InCombatLockdown()))
    tracker:Show()
end

-- The panel, for the hub's Unlock mode (built when it is asked for) and the tests.
function ns.TrackerFrame()
    if not tracker and ns.db then buildTracker() end
    return tracker
end
