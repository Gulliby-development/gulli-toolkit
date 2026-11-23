-- The dungeon tracker: a small Gulli HUD panel on the right of the screen for the dungeon of
-- Lead me (ns.ShowTracker). It lists the dungeon's chains (ns.TrackerItems) in groups by what
-- to do: hand in, doing, take, later. The four numbers on top count the groups and add up to
-- every row there is; a click on one goes to its group. A row is named by the quest to do
-- now; under it the chain's steps as dots, the step's number and the quest the chain ends
-- with. The panel keeps its size: rows that do not fit are reached by the mouse wheel or the
-- line at the bottom, which says which rows show. A click on a chain shows its steps in a card
-- beside the panel (done, now, later, where each is, and the quests a step opens when it
-- opens more than one), a right-click opens the quest in the journal; the map button pins who
-- to go to (and targets them when they are near, ns.TargetOver). The dungeon's icon under a
-- row's mark says that what the row asks for now happens inside the dungeon. The cross closes
-- it. In the hub's Unlock mode it shows with its mover to be placed.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local W, HEAD_H, NAME_H, LINE_H, PAD = 290, 28, 16, 14, 6
local CHIPS_H, CHAIN_H, GROUP_H, FOOT_H, PIPS_MAX = 40, 15, 20, 22, 8
-- The room for rows: a list taller than this scrolls.
ns.TRACK_H = 430
local STATE_ICON = {
    ready = "Interface\\GossipFrame\\ActiveQuestIcon",
    log = "Interface\\GossipFrame\\IncompleteQuestIcon",
    take = "Interface\\GossipFrame\\AvailableQuestIcon",
    chain = "Interface\\GossipFrame\\AvailableQuestIcon",
}
local PIN_ICON = "Interface\\Icons\\INV_Misc_Map_01"
-- The room the map button takes at a row's right edge, and how far down it reaches.
local PIN_ROOM, PIN_BOTTOM = 34, PAD - 2 + 22
ns.TRACK_PIN_ROOM = PIN_ROOM
local DONE_ICON = "Interface\\RaidFrame\\ReadyCheck-Ready"
local PIP_TODO = { 1, 1, 1, 0.22 }

local tracker, flyout
local opened
local offset = 0         -- how far the list is scrolled, in pixels
local goTo               -- a group to scroll to on the next refresh
local view = { first = 0, last = 0, total = 0, tops = {}, max = 0 }
-- One notch of the mouse wheel, in pixels.
ns.TRACK_STEP = 44

-- Whether a chain's steps show beside the panel, and a switch for it: one chain at a time.
function ns.TrackerOpen(key) return opened == key end
function ns.ToggleTracked(key)
    if opened == key then opened = nil else opened = key end
    ns.RefreshTracker()
end

-- The rows in view (the first and the last that show whole, how many there are, how far the
-- list is scrolled and how far it can be), and moving through the list: by notches of the
-- mouse wheel (the list moves by pixels, so the panel is always full to its bottom), to the
-- next page (the line at the bottom: the first row cut off goes to the top, and back to the
-- top after the end) or to a group (a number on top).
function ns.TrackerView() return view.first, view.last, view.total, offset, view.max end
function ns.TrackerScroll(by)
    offset = offset + by * ns.TRACK_STEP
    ns.RefreshTracker()
end
function ns.TrackerNextPage()
    if offset >= view.max then offset = 0
    else offset = view.tops[view.last + 1] or view.max end
    ns.RefreshTracker()
end
function ns.TrackerGoTo(group)
    if not tracker or not tracker.key then return end
    goTo = group
    ns.RefreshTracker()
end

-- The line under a chain's name: its place in the chain and the quest it ends with.
local function chainText(it)
    local text = it.at .. "/" .. it.of
    if it.goal then return text .. "  » " .. it.goal end
    if it.at == it.of then return text .. S.DOT .. L.TR_LAST end
    return text
end

-- Opens the journal on the quest's page (`from`: the dungeon quest whose chain a step
-- outside the dungeon is in).
function ns.OpenTracked(key, id, from)
    ns.selected, ns.home = key, false
    local f = ns.Window()
    if not f:IsShown() then ns.Toggle() end
    ns.ShowTab(3)
    ns.OpenQuest(id, from)
end

local function place()
    tracker:ClearAllPoints()
    local p = ns.db and ns.db.trackerPoint
    if p then tracker:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
    else tracker:SetPoint("RIGHT", UIParent, "RIGHT", -260, 40) end
end

local function rowHeight(it)
    return PAD + NAME_H + (it.steps and CHAIN_H or 0) + #it.lines * LINE_H + PAD
end

local function lineOf(r, i)
    if not r.lines[i] then
        local t = S.Text(r, 12, S.MUTED)
        t:SetPoint("RIGHT", -10, 0)
        t:SetJustifyH("LEFT")
        t:SetWordWrap(false)
        r.lines[i] = t
    end
    return r.lines[i]
end

-- A tooltip stands beside the panel (and beside the chain's card when that is open), at the
-- height of what the mouse is on, so it never covers the rows.
local function tipPlace(owner)
    local base = tracker
    local cx, sw = base.GetCenter and base:GetCenter(), UIParent.GetWidth and UIParent:GetWidth()
    local right = type(cx) == "number" and type(sw) == "number" and cx < sw / 2
    if flyout and flyout:IsShown() then base = flyout end
    local dy = 0
    local top, mine = base.GetTop and base:GetTop(), owner.GetTop and owner:GetTop()
    if type(top) == "number" and type(mine) == "number" then dy = math.min(0, mine - top) end
    if right then return "TOPLEFT", base, "TOPRIGHT", 6, dy end
    return "TOPRIGHT", base, "TOPLEFT", -6, dy
end
ns.TrackerTipPlace = tipPlace
local function tip(owner, fn)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_NONE")
    if tracker and GameTooltip.SetPoint then
        if GameTooltip.ClearAllPoints then GameTooltip:ClearAllPoints() end
        GameTooltip:SetPoint(tipPlace(owner))
    end
    fn(GameTooltip)
    GameTooltip:Show()
end
local function hideTip() if GameTooltip then GameTooltip:Hide() end end

local function wheel(f)
    if f.EnableMouseWheel then f:EnableMouseWheel(true) end
    f:SetScript("OnMouseWheel", function(_, delta) ns.TrackerScroll(delta > 0 and -1 or 1) end)
end

local function makeRow(parent)
    local r = CreateFrame("Button", nil, parent)
    wheel(r)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(16, 16)
    r.icon:SetPoint("TOPLEFT", 8, -PAD)
    -- Under the mark: the dungeon's icon, when what the row asks for now is done inside it.
    r.inside = S.IconBox(r, 16)
    r.inside:SetPoint("TOP", r.icon, "BOTTOM", 0, -2)
    r.name = S.Text(r, 12, nil, nil, "bold")
    r.name:SetPoint("TOPLEFT", 30, -PAD)
    r.name:SetPoint("RIGHT", -32, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    -- The chain: a dot per step, then where the row is in it and where it leads.
    r.pips = {}
    for i = 1, PIPS_MAX do r.pips[i] = S.Circle(r, 6, PIP_TODO, "ARTWORK") end
    r.fork = S.Text(r, 12, S.TEXT)
    r.fork:SetPoint("TOPRIGHT", -10, -(PAD + NAME_H))
    r.chain = S.Text(r, 12, S.MUTED)
    r.chain:SetJustifyH("LEFT")
    r.chain:SetWordWrap(false)
    r.lines = {}
    r.pin = CreateFrame("Button", nil, r)
    r.pin:SetSize(22, 22)
    r.pin:SetPoint("TOPRIGHT", -6, -PAD + 2)
    r.pin.icon = S.IconBox(r.pin, 22, PIN_ICON)
    r.pin.icon:SetAllPoints()
    r.pin:SetScript("OnClick", function(self)
        local it = self:GetParent().item
        if it and it.pin then ns.PinAt(it.pin.who, it.pin.area, it.pin.x, it.pin.y, true) end
    end)
    local function pinTip(owner, it)
        if not it.pin then return end
        tip(owner, function(t)
            t:AddLine(L.TR_PIN:format(it.pin.who), 1, 1, 1)
            t:AddLine(L.TR_TARGET, 0.7, 0.7, 0.7)
        end)
    end
    r.pin:SetScript("OnEnter", function(self)
        local it = self:GetParent().item
        if not (it and it.pin) then return end
        pinTip(self, it)
        if ns.TargetOver then ns.TargetOver(self, it.pin.who, function(o) pinTip(o, it) end) end
    end)
    r.pin:SetScript("OnLeave", hideTip)
    if r.RegisterForClicks then r:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    r:SetScript("OnClick", function(self, button)
        local it = self.item
        if not (it and tracker.key) then return end
        if it.steps and button ~= "RightButton" then ns.ToggleTracked(it.key) return end
        ns.OpenTracked(tracker.key, it.id)
    end)
    r:SetScript("OnEnter", function(self)
        local it = self.item
        if not it then return end
        tip(self, function(t)
            t:AddLine(it.name, 1, 0.82, 0)
            if it.steps then
                t:AddLine(L.STEP:format(it.at or 1, it.of) .. (it.goal and ("  » " .. it.goal) or ""), 0.8, 0.8, 0.8)
            end
            if it.inside and tracker.key then
                local c = S.Accent()
                t:AddLine(S.IconTag(ns.Icon(tracker.key)) .. " " .. L.INSIDE_OF:format(tracker.title:GetText() or ""),
                    c[1], c[2], c[3])
            end
            for _, st in ipairs(it.steps or {}) do
                if st.id == it.id and st.opens then
                    t:AddLine(L.CS_OPENS:format(#st.opens), 1, 0.82, 0)
                    for _, o in ipairs(st.opens) do t:AddLine("» " .. o.name, 1, 1, 1) end
                end
            end
            if it.steps then
                t:AddLine(opened == it.key and L.TR_FOLD or L.TR_UNFOLD, 1, 1, 1)
                t:AddLine(L.TR_OPEN_RIGHT, 1, 1, 1)
            else
                t:AddLine(L.TR_OPEN, 1, 1, 1)
            end
        end)
    end)
    r:SetScript("OnLeave", hideTip)
    return r
end

local function fillRow(r, it)
    r.item = it
    r.icon:SetTexture(STATE_ICON[it.state])
    r.icon:SetDesaturated(it.state == "chain")
    r.inside:SetShown(it.inside == true)
    if it.inside then r.inside:SetIcon(ns.Icon(tracker.key)) end
    r.name:SetText(it.name)
    local diff = ns.Difficulty(it.level or 1, ns.level or UnitLevel("player") or 1)
    r.name:SetTextColor(unpack(it.state == "chain" and S.MUTED or ns.DiffColor(diff)))
    -- The map button stands at the right over the row's first lines: nothing runs under it.
    local right = it.pin and -PIN_ROOM or -10
    r.name:SetPoint("RIGHT", right, 0)
    local y = PAD + NAME_H
    local dots = it.steps and #it.steps <= PIPS_MAX and #it.steps or 0
    local x = 30
    for i, p in ipairs(r.pips) do
        local st = i <= dots and it.steps[i]
        p:SetShown(st ~= false)
        if st then
            local now = st.this == true
            local size = now and 9 or 6
            p:SetSize(size, size)
            local c = (now and S.GOLD) or (st.state == "done" and S.GOOD) or PIP_TODO
            p:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
            p:ClearAllPoints()
            p:SetPoint("LEFT", r, "TOPLEFT", x, -(y + CHAIN_H / 2) + 1)
            x = x + size + 3
        end
    end
    r.chain:SetShown(it.steps ~= nil)
    r.fork:SetShown(it.steps ~= nil and it.fork ~= nil)
    if it.steps then
        r.fork:SetText(it.fork and ("|T" .. STATE_ICON.take .. ":12|t" .. it.fork) or "")
        r.chain:ClearAllPoints()
        r.chain:SetPoint("TOPLEFT", x + (dots > 0 and 3 or 0), -y)
        r.fork:ClearAllPoints()
        r.fork:SetPoint("TOPRIGHT", right, -y)
        if it.fork then r.chain:SetPoint("RIGHT", r.fork, "LEFT", -4, 0) else r.chain:SetPoint("RIGHT", right, 0) end
        r.chain:SetText(chainText(it))
        y = y + CHAIN_H
    end
    for i = 1, #it.lines do lineOf(r, i) end
    for i, t in ipairs(r.lines) do
        local line = it.lines[i]
        t:SetShown(line ~= nil)
        if line then
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", 30, -(y + (i - 1) * LINE_H))
            t:SetPoint("RIGHT", (y + (i - 1) * LINE_H < PIN_BOTTOM) and right or -10, 0)
            t:SetText(line.text)
            local c = S.TEXT
            if it.state == "ready" then c = S.GOOD elseif it.state == "chain" then c = S.FAINT
            elseif it.state == "take" then c = S.MUTED
            elseif line.done then c = S.FAINT end
            t:SetTextColor(unpack(c))
        end
    end
    r.pin:SetShown(it.pin ~= nil)
    r:SetHeight(rowHeight(it))
end

-- The card beside the panel with the steps of the chain that is open: a rail of marks (a
-- tick for a step done, a gold disc for the one in the log, the game's "!" for one to take,
-- its number for a later one), each step with where it is, and under a step that opens more
-- than one quest the quests it opens. Many steps done fold into one line.
local STEP_H, OPEN_H, FOLD_AT = 32, 15, 3
local TAG = { done = { "STATE_DONE", "GOOD" }, now = { "STAGE_NOW", "GOLD" }, take = { "Q_TAKE", "GOLD" } }

local function cardRows(it)
    local rows, done = {}, 0
    for _, st in ipairs(it.steps) do if st.state == "done" then done = done + 1 end end
    local fold = done > FOLD_AT and done - 1 or 0
    if fold > 0 then rows[1] = { folded = fold } end
    for i, st in ipairs(it.steps) do
        if i > fold then
            rows[#rows + 1] = { step = st }
            for _, o in ipairs((st.state ~= "done" and st.opens) or {}) do
                if #rows > 0 and not rows[#rows].open then rows[#rows + 1] = { opens = #st.opens } end
                rows[#rows + 1] = { open = o }
            end
        end
    end
    return rows
end
-- The same rows for the tests.
function ns.TrackerCardRows(it) return cardRows(it) end

local function makeCardRow(parent)
    local r = CreateFrame("Button", nil, parent)
    r.rail = S.Divider(r, S.EDGE)
    r.rail:SetWidth(2)
    r.disc = S.Circle(r, 18, S.EDGE, "ARTWORK")
    r.disc:SetPoint("TOPLEFT", 10, -2)
    r.mark = r:CreateTexture(nil, "OVERLAY")
    r.mark:SetSize(14, 14)
    r.mark:SetPoint("CENTER", r.disc)
    r.num = S.Text(r, 12, S.TEXT, nil, "bold")
    r.num:SetPoint("CENTER", r.disc)
    r.tag = S.Text(r, 12, S.MUTED, nil, "bold")
    r.tag:SetPoint("TOPRIGHT", -10, -2)
    r.tag:SetWordWrap(false)
    r.name = S.Text(r, 12, S.TEXT, nil, "bold")
    r.name:SetPoint("TOPLEFT", 36, -2)
    r.name:SetPoint("RIGHT", r.tag, "LEFT", -6, 0)
    r.name:SetWordWrap(false)
    r.sub = S.Text(r, 12, S.MUTED)
    r.sub:SetPoint("TOPLEFT", 36, -16)
    r.sub:SetPoint("RIGHT", -10, 0)
    r.sub:SetWordWrap(false)
    r.pin = CreateFrame("Button", nil, r)
    r.pin:SetSize(20, 20)
    r.pin:SetPoint("RIGHT", -8, 0)
    r.pin.icon = S.IconBox(r.pin, 20, PIN_ICON)
    r.pin.icon:SetAllPoints()
    r.pin:SetScript("OnClick", function(self)
        local st = self:GetParent().step
        if st then ns.PinAt(st.who, st.area, st.x, st.y, true) end
    end)
    r.pin:SetScript("OnEnter", function(self)
        local st = self:GetParent().step
        if st then tip(self, function(t) t:AddLine(L.TR_PIN:format(st.who), 1, 1, 1) end) end
    end)
    r.pin:SetScript("OnLeave", hideTip)
    r:SetScript("OnClick", function(self)
        local id = (self.step and self.step.id) or (self.open and self.open.id)
        if id and tracker.key and flyout.item then ns.OpenTracked(tracker.key, id, flyout.item.id) end
    end)
    r:SetScript("OnEnter", function(self)
        if self.step or self.open then tip(self, function(t) t:AddLine(L.TR_OPEN, 1, 1, 1) end) end
    end)
    r:SetScript("OnLeave", hideTip)
    return r
end

local function fillCardRow(r, row, last)
    local st, o = row.step, row.open
    r.step, r.open = st, o
    for _, x in ipairs({ r.rail, r.disc, r.mark, r.num, r.tag, r.sub, r.pin }) do x:Hide() end
    r.name:ClearAllPoints()
    r.name:SetPoint("RIGHT", r.tag, "LEFT", -6, 0)
    if st then
        local done, now = st.state == "done", st.state == "now"
        r:SetHeight(STEP_H)
        r.rail:ClearAllPoints()
        r.rail:SetPoint("TOP", r.disc, "BOTTOM", 0, 0)
        r.rail:SetPoint("BOTTOM", r, "BOTTOMLEFT", 19, -2)
        r.rail:SetShown(not last)
        r.rail:SetVertexColor(unpack(done and S.GOOD or S.EDGE))
        r.disc:SetShown(not done and st.state ~= "take")
        r.disc:SetVertexColor(unpack(now and S.GOLD or S.EDGE))
        r.mark:SetShown(done or st.state == "take")
        r.mark:SetTexture(done and DONE_ICON or STATE_ICON.take)
        r.num:SetShown(not done and st.state ~= "take")
        r.num:SetText(st.n)
        r.num:SetTextColor(unpack(now and { 0.10, 0.07, 0.03, 1 } or S.MUTED))
        local tag = TAG[st.state] or (st.goal and { "CS_GOAL", "GOLD_DIM" })
        r.tag:SetShown(tag ~= nil)
        r.tag:SetText(tag and L[tag[1]] or "")
        if tag then r.tag:SetTextColor(unpack(S[tag[2]])) end
        r.name:SetPoint("TOPLEFT", 36, -2)
        r.name:SetText(st.name)
        r.name:SetTextColor(unpack((done and S.MUTED) or (st.state == "later" and S.MUTED) or S.TEXT))
        local where = ns.WhereTag({ who = st.who or "", area = st.area or 0 })
        if where == "" then where = st.inside and L.INSIDE or "" end
        if st.inside and tracker.key then where = S.IconTag(ns.Icon(tracker.key)) .. " " .. where end
        r.sub:Show()
        r.sub:SetText(where)
        local pin = st.state == "take" and st.who ~= "" and st.area > 0 and (st.x > 0 or st.y > 0)
        r.pin:SetShown(pin)
        r.tag:ClearAllPoints()
        r.tag:SetPoint("TOPRIGHT", pin and -34 or -10, -2)
        r.sub:SetPoint("RIGHT", pin and -32 or -10, 0)
    else
        r:SetHeight(OPEN_H + (row.folded and 4 or 0))
        r.name:SetPoint("TOPLEFT", o and 48 or 36, 0)
        r.name:SetPoint("RIGHT", -10, 0)
        if row.folded then
            r.mark:Show()
            r.mark:SetTexture(DONE_ICON)
            r.name:SetText(L.DONE_N:format(row.folded))
            r.name:SetTextColor(unpack(S.MUTED))
        elseif row.opens then
            r.name:SetText(L.CS_OPENS:format(row.opens))
            r.name:SetTextColor(unpack(S.GOLD_DIM))
        else
            r.name:SetText("» " .. o.name .. S.DOT .. (o.main and L.CS_MAIN or L.CS_SIDE))
            r.name:SetTextColor(unpack(S.TEXT))
        end
    end
end

local function buildFlyout()
    flyout = CreateFrame("Frame", "GulliDungeonPrepTrackerChain", UIParent)
    flyout:SetSize(W + 20, HEAD_H + 40)
    flyout:SetFrameStrata("MEDIUM")
    flyout:SetClampedToScreen(true)
    flyout:EnableMouse(true)
    S.HudPanel(flyout)
    flyout.close = S.Close(flyout, function() opened = nil; ns.RefreshTracker() end)
    flyout.close:SetSize(24, 24)
    flyout.close:SetPoint("TOPRIGHT", -2, -2)
    flyout.title = S.Text(flyout, 12, S.GOLD, nil, "bold")
    flyout.title:SetPoint("TOPLEFT", 10, -8)
    flyout.title:SetPoint("RIGHT", flyout.close, "LEFT", -6, 0)
    flyout.title:SetJustifyH("LEFT")
    flyout.title:SetWordWrap(false)
    local line = S.Divider(flyout)
    line:SetPoint("TOPLEFT", 1, -HEAD_H)
    line:SetPoint("TOPRIGHT", -1, -HEAD_H)
    line:SetHeight(1)
    flyout.rows = {}
    flyout:Hide()
end

local function showFlyout(row, it)
    if not flyout then buildFlyout() end
    flyout.item = it
    flyout.title:SetText(L.STEP:format(it.at or 1, it.of) .. (it.goal and ("  » " .. it.goal) or ""))
    local rows = cardRows(it)
    local y = HEAD_H + PAD + 2
    for i, row in ipairs(rows) do
        local r = flyout.rows[i]
        if not r then r = makeCardRow(flyout); flyout.rows[i] = r end
        fillCardRow(r, row, i == #rows)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 1, -y)
        r:SetPoint("TOPRIGHT", -1, -y)
        r:Show()
        y = y + r:GetHeight() + ((row.open and (not rows[i + 1] or not rows[i + 1].open)) and 6 or 0)
    end
    for i = #rows + 1, #flyout.rows do flyout.rows[i]:Hide() end
    flyout:SetHeight(y + PAD)
    -- Beside the row, on the side of the screen with room: left of a panel on the right half.
    flyout:ClearAllPoints()
    local cx = tracker.GetCenter and tracker:GetCenter()
    local sw = UIParent.GetWidth and UIParent:GetWidth()
    if type(cx) == "number" and type(sw) == "number" and cx < sw / 2 then
        flyout:SetPoint("TOPLEFT", row, "TOPRIGHT", 6, 0)
    else
        flyout:SetPoint("TOPRIGHT", row, "TOPLEFT", -6, 0)
    end
    flyout:SetScale(tracker.GetScale and tracker:GetScale() or 1)
    flyout:Show()
end

local function hideFlyout() if flyout then flyout:Hide() end end

-- A number on top: how many rows its group has; a click goes to the group.
local function makeChip(parent, group)
    local c = CreateFrame("Button", nil, parent)
    c:SetHeight(CHIPS_H - 6)
    S.Box(c, S.SURFACE, S.CARD_EDGE, S.R_MD)
    c.num = S.Text(c, 13, S.TEXT, nil, "bold")
    c.num:SetPoint("TOP", 0, -3)
    c.label = S.Text(c, 12, S.MUTED)
    c.label:SetPoint("BOTTOM", 0, 3)
    c.label:SetText(L["TG_" .. group:upper()])
    c.group = group
    c:SetScript("OnClick", function() ns.TrackerGoTo(group) end)
    c:SetScript("OnEnter", function(self)
        tip(self, function(t) t:AddLine(L["TG_" .. group:upper() .. "_D"], 1, 1, 1) end)
    end)
    c:SetScript("OnLeave", hideTip)
    wheel(c)
    return c
end

local function makeGroup(parent)
    local g = CreateFrame("Frame", nil, parent)
    g:SetHeight(GROUP_H)
    g.text = S.Text(g, 12, S.GOLD_DIM, nil, "bold")
    g.text:SetPoint("BOTTOMLEFT", 9, 3)
    g.line = S.Divider(g, S.EDGE)
    g.line:SetHeight(1)
    g.line:SetPoint("LEFT", g.text, "RIGHT", 6, 0)
    g.line:SetPoint("RIGHT", -9, 0)
    return g
end

local function build()
    tracker = CreateFrame("Frame", "GulliDungeonPrepTracker", UIParent)
    tracker:SetSize(W, HEAD_H + 40)
    tracker:SetFrameStrata("MEDIUM")
    tracker:SetClampedToScreen(true)
    tracker:EnableMouse(true)
    S.HudPanel(tracker)
    wheel(tracker)
    tracker.icon = S.IconBox(tracker, 18)
    tracker.icon:SetPoint("TOPLEFT", 8, -5)
    tracker.close = S.Close(tracker, function() ns.HideTracker() end)
    tracker.close:SetSize(24, 24)
    tracker.close:SetPoint("TOPRIGHT", -2, -2)
    tracker.title = S.Text(tracker, 12, S.GOLD, nil, "bold")
    tracker.title:SetPoint("LEFT", tracker.icon, "RIGHT", 8, 0)
    tracker.title:SetPoint("RIGHT", tracker.close, "LEFT", -6, 0)
    tracker.title:SetJustifyH("LEFT")
    tracker.title:SetWordWrap(false)
    local line = S.Divider(tracker)
    line:SetPoint("TOPLEFT", 1, -HEAD_H)
    line:SetPoint("TOPRIGHT", -1, -HEAD_H)
    line:SetHeight(1)
    tracker.chips = {}
    local cw = (W - 16 - 3 * 4) / 4
    for i, group in ipairs(ns.TRACK_GROUPS) do
        local c = makeChip(tracker, group)
        c:SetWidth(cw)
        c:SetPoint("TOPLEFT", 8 + (i - 1) * (cw + 4), -(HEAD_H + 6))
        tracker.chips[i] = c
    end
    tracker.empty = S.Text(tracker, 12, S.FAINT)
    tracker.empty:SetPoint("TOPLEFT", 10, -(HEAD_H + CHIPS_H + 12))
    tracker.empty:SetPoint("RIGHT", -10, 0)
    tracker.empty:SetJustifyH("LEFT")
    tracker.empty:SetText(L.TR_EMPTY)
    tracker.rows, tracker.groups = {}, {}
    -- The list: every row on one sheet that moves behind a window as high as the room for rows.
    local clip = CreateFrame("Frame", nil, tracker)
    clip:SetPoint("TOPLEFT", 0, -(HEAD_H + CHIPS_H + 2))
    clip:SetPoint("TOPRIGHT", 0, -(HEAD_H + CHIPS_H + 2))
    if clip.SetClipsChildren then clip:SetClipsChildren(true) end
    local sheet = CreateFrame("Frame", nil, clip)
    sheet:SetHeight(1)
    wheel(clip)
    tracker.clip, tracker.sheet = clip, sheet
    -- A thin bar at the right edge: how much of the list is in view, and where.
    tracker.bar = S.Divider(tracker, S.EDGE)
    tracker.bar:SetWidth(2)
    -- The line at the bottom while rows are out of view: which rows show; a click turns the page.
    local foot = CreateFrame("Button", nil, tracker)
    foot:SetHeight(FOOT_H)
    foot:SetPoint("BOTTOMLEFT", 1, 1)
    foot:SetPoint("BOTTOMRIGHT", -1, 1)
    foot.line = S.Divider(foot, S.EDGE)
    foot.line:SetHeight(1)
    foot.line:SetPoint("TOPLEFT")
    foot.line:SetPoint("TOPRIGHT")
    foot.more = S.Text(foot, 12, S.Accent())
    foot.more:SetPoint("RIGHT", -9, 0)
    foot.more:SetWordWrap(false)
    foot.text = S.Text(foot, 12, S.MUTED)
    foot.text:SetPoint("LEFT", 9, 0)
    foot.text:SetPoint("RIGHT", foot.more, "LEFT", -6, 0)
    foot.text:SetWordWrap(false)
    foot:SetScript("OnClick", function() ns.TrackerNextPage() end)
    foot:SetScript("OnEnter", function(self) tip(self, function(t) t:AddLine(L.TR_SCROLL, 1, 1, 1) end) end)
    foot:SetScript("OnLeave", hideTip)
    wheel(foot)
    tracker.foot = foot
    S.Mover(tracker, { label = L.TR_TITLE,
        save = function(p, rp, x, y) if ns.db then ns.db.trackerPoint = { p, rp, x, y } end end,
        reset = function() if ns.db then ns.db.trackerPoint = nil end; place() end })
    tracker:Hide()
end

-- Shows the tracker for a dungeon (kept over a reload) or, with nil, the one shown before.
function ns.ShowTracker(key)
    if ns.db and key then
        if ns.db.tracker ~= key then offset, opened = 0, nil end
        ns.db.tracker = key
    end
    ns.RefreshTracker()
end

function ns.HideTracker()
    if ns.db then ns.db.tracker = nil end
    ns.RefreshTracker()
end

-- The hub's switch: on shows the dungeon the player chose last, or the one for the level.
function ns.SetTrackerShown(on)
    if not on then ns.HideTracker(); return end
    local key = ns.selected
    if not key then
        local s = ns.Suggest(UnitLevel("player") or 1)
        key = s and s.key
    end
    ns.ShowTracker(key)
end

function ns.MoveTracker(on)
    ns.movingTracker = on and true or nil
    ns.RefreshTracker()
end

function ns.RefreshTracker()
    if not ns.db then return end
    local moving = ns.movingTracker
    local key = ns.db.tracker
    -- In the Unlock mode with nothing to track, it shows the dungeon for the level, to be placed.
    if not key and moving then
        local s = ns.Suggest(UnitLevel("player") or 1)
        key = s and s.key
    end
    if not key then
        if tracker then tracker:SetMoving(false); tracker:Hide() end
        hideFlyout()
        return
    end
    if not tracker then build() end
    local d
    for _, x in ipairs(ns.Dungeons(UnitLevel("player") or 1)) do if x.key == key then d = x end end
    if not d then ns.db.tracker = nil; tracker:Hide(); hideFlyout() return end
    tracker.key = key
    place()
    tracker.icon:SetIcon(ns.Icon(key))
    tracker.title:SetText(ns.DungeonName(d))
    local items, _, total, counts = ns.TrackerItems(key, UnitLevel("player") or 1)
    for _, c in ipairs(tracker.chips) do
        local n = counts[c.group]
        c.num:SetText(n)
        c.num:SetTextColor(unpack(n > 0 and S.TEXT or S.FAINT))
    end
    -- Every row lies on one sheet, a group's name over its first row. A list higher than the
    -- room for rows scrolls by pixels behind the window, so the panel is full to its bottom
    -- and a row may show in part; a list that fits makes the panel as high as it is.
    local top = HEAD_H + CHIPS_H + 2
    local sheet = tracker.sheet
    local y, groups, group = 0, 0, nil
    local tops, ends, groupTop = {}, {}, {}
    for i, it in ipairs(items) do
        if it.group ~= group then
            group, groups = it.group, groups + 1
            local g = tracker.groups[groups]
            if not g then g = makeGroup(sheet); wheel(g); tracker.groups[groups] = g end
            g.text:SetText(S.Upper(L["TG_" .. group:upper()]) .. "  |cffffffff" .. counts[group] .. "|r")
            g:ClearAllPoints()
            g:SetPoint("TOPLEFT", 1, -y)
            g:SetPoint("TOPRIGHT", -1, -y)
            g:Show()
            groupTop[group] = y
            tops[i] = y
            y = y + GROUP_H
        end
        tops[i] = tops[i] or y
        local r = tracker.rows[i]
        if not r then r = makeRow(sheet); tracker.rows[i] = r end
        fillRow(r, it)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 1, -y)
        r:SetPoint("TOPRIGHT", -1, -y)
        y = y + rowHeight(it)
        ends[i] = y
    end
    for i = total + 1, #tracker.rows do tracker.rows[i]:Hide() end
    for i = groups + 1, #tracker.groups do tracker.groups[i]:Hide() end
    local all = y
    local paged = all > ns.TRACK_H
    local room = paged and ns.TRACK_H or all
    view.max = math.max(0, all - room)
    if goTo then offset, goTo = groupTop[goTo] or offset, nil end
    offset = math.max(0, math.min(offset, view.max))
    -- The first and the last row that show whole (a row higher than the room counts as it shows).
    local firstIn, lastIn, firstSeen, openRow = 0, 0, 0, nil
    for i, it in ipairs(items) do
        local r = tracker.rows[i]
        local seen = ends[i] > offset and tops[i] < offset + room
        r:SetShown(seen)
        if seen then
            if firstSeen == 0 then firstSeen = i end
            if tops[i] >= offset - 1 and ends[i] <= offset + room + 1 then
                if firstIn == 0 then firstIn = i end
                lastIn = i
            end
            if it.steps and opened == it.key then openRow = { r, it } end
        end
    end
    if firstIn == 0 then firstIn, lastIn = firstSeen, firstSeen end
    view.first, view.last, view.total, view.tops = firstIn, lastIn, total, tops
    tracker.clip:SetHeight(math.max(1, room))
    sheet:ClearAllPoints()
    sheet:SetPoint("TOPLEFT", 0, offset)
    sheet:SetPoint("TOPRIGHT", 0, offset)
    sheet:SetHeight(math.max(1, all))
    for _, c in ipairs(tracker.chips) do
        local here = firstIn > 0 and items[firstIn].group == c.group
        S.SetBorder(c, here and S.Accent() or S.CARD_EDGE)
    end
    tracker.empty:SetShown(total == 0)
    y = top + room
    if total == 0 then y = y + 34 end
    tracker.foot:SetShown(paged)
    tracker.bar:SetShown(paged)
    if paged then
        tracker.foot.text:SetText(L.TR_RANGE:format(view.first, view.last, total))
        tracker.foot.more:SetText(offset >= view.max and L.TR_TOP or L.TR_NEXT)
        local h = math.max(18, room * room / all)
        tracker.bar:ClearAllPoints()
        tracker.bar:SetPoint("TOPRIGHT", -2, -(top + (room - h) * (view.max > 0 and offset / view.max or 0)))
        tracker.bar:SetHeight(h)
        y = y + FOOT_H
    end
    tracker:SetHeight(y + 4)
    tracker:SetMoving(moving and not (InCombatLockdown and InCombatLockdown()))
    tracker:Show()
    -- A chain that left the panel (done, or past the rows shown) closes its card.
    if openRow and not moving then showFlyout(openRow[1], openRow[2]) else hideFlyout() end
end

-- The card with the open chain's steps, for the tests and the preview.
function ns.TrackerChainFrame() return flyout end

-- The panel, for the hub's Unlock mode (built when it is asked for) and the tests.
function ns.TrackerFrame()
    if not tracker and ns.db then build() end
    return tracker
end
