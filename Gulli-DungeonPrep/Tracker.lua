-- The dungeon tracker: a small Gulli HUD panel on the right of the screen for the dungeon of
-- Lead me (ns.ShowTracker). It lists the dungeon's quests (ns.TrackerItems): ready to hand in,
-- in the log with their objectives, to take, and chain quests that wait for an earlier step.
-- A click on a row opens the quest in the journal; the map button pins who to go to. The cross
-- closes it. Unlocked (its switch or /gulli move) it shows with its mover to be placed.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local W, HEAD_H, NAME_H, LINE_H, PAD = 290, 28, 16, 14, 6
local STATE_ICON = {
    ready = "Interface\\GossipFrame\\ActiveQuestIcon",
    log = "Interface\\GossipFrame\\IncompleteQuestIcon",
    take = "Interface\\GossipFrame\\AvailableQuestIcon",
    chain = "Interface\\GossipFrame\\AvailableQuestIcon",
}
local PIN_ICON = "Interface\\Icons\\INV_Misc_Map_01"

local tracker

-- Opens the journal on the quest's page.
function ns.OpenTracked(key, id)
    ns.selected, ns.home = key, false
    local f = ns.Window()
    if not f:IsShown() then ns.Toggle() end
    ns.ShowTab(3)
    ns.OpenQuest(id)
end

local function place()
    tracker:ClearAllPoints()
    local p = ns.db and ns.db.trackerPoint
    if p then tracker:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
    else tracker:SetPoint("RIGHT", UIParent, "RIGHT", -260, 40) end
end

local function rowHeight(it)
    return PAD + NAME_H + #it.lines * LINE_H + PAD
end

local function makeRow(parent)
    local r = CreateFrame("Button", nil, parent)
    if r.RegisterForClicks then r:RegisterForClicks("LeftButtonUp") end
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(16, 16)
    r.icon:SetPoint("TOPLEFT", 8, -PAD)
    r.name = S.Text(r, 12)
    r.name:SetPoint("TOPLEFT", 30, -PAD)
    r.name:SetPoint("RIGHT", -32, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.lines = {}
    for i = 1, 3 do
        local t = S.Text(r, 12, S.MUTED)
        t:SetPoint("TOPLEFT", 30, -(PAD + NAME_H + (i - 1) * LINE_H))
        t:SetPoint("RIGHT", -32, 0)
        t:SetJustifyH("LEFT")
        t:SetWordWrap(false)
        r.lines[i] = t
    end
    r.pin = CreateFrame("Button", nil, r)
    r.pin:SetSize(22, 22)
    r.pin:SetPoint("TOPRIGHT", -6, -PAD + 2)
    r.pin.icon = S.IconBox(r.pin, 22, PIN_ICON)
    r.pin.icon:SetAllPoints()
    r.pin:SetScript("OnClick", function(self)
        local it = self:GetParent().item
        if it and it.pin then ns.PinAt(it.pin.who, it.pin.area, it.pin.x, it.pin.y, true) end
    end)
    r.pin:SetScript("OnEnter", function(self)
        local it = self:GetParent().item
        if not (GameTooltip and it and it.pin) then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(L.TR_PIN:format(it.pin.who), 1, 1, 1)
        GameTooltip:Show()
    end)
    r.pin:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    r:SetScript("OnClick", function(self)
        if self.item and tracker.key then ns.OpenTracked(tracker.key, self.item.id) end
    end)
    r:SetScript("OnEnter", function(self)
        if not (GameTooltip and self.item) then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(self.item.name, 1, 0.82, 0)
        GameTooltip:AddLine(L.TR_OPEN, 1, 1, 1)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return r
end

local function fillRow(r, it)
    r.item = it
    r.icon:SetTexture(STATE_ICON[it.state])
    r.icon:SetDesaturated(it.state == "chain")
    r.name:SetText(it.name)
    local diff = ns.Difficulty(it.level or 1, ns.level or UnitLevel("player") or 1)
    r.name:SetTextColor(unpack(ns.DiffColor(diff)))
    for i, t in ipairs(r.lines) do
        local line = it.lines[i]
        t:SetShown(line ~= nil)
        if line then
            t:SetText(line.text)
            local c = S.MUTED
            if it.state == "ready" then c = S.GOOD elseif it.state == "chain" then c = S.WARN
            elseif line.done then c = S.FAINT end
            t:SetTextColor(unpack(c))
        end
    end
    r.pin:SetShown(it.pin ~= nil)
    r:SetHeight(rowHeight(it))
end

local function build()
    tracker = CreateFrame("Frame", "GulliDungeonPrepTracker", UIParent)
    tracker:SetSize(W, HEAD_H + 40)
    tracker:SetFrameStrata("MEDIUM")
    tracker:SetClampedToScreen(true)
    tracker:EnableMouse(true)
    S.HudPanel(tracker)
    tracker.icon = S.IconBox(tracker, 18)
    tracker.icon:SetPoint("TOPLEFT", 8, -5)
    tracker.count = S.Text(tracker, 12, S.FAINT)
    tracker.count:SetPoint("LEFT", tracker.icon, "RIGHT", 6, 0)
    tracker.close = S.Close(tracker, function() ns.HideTracker() end)
    tracker.close:SetSize(24, 24)
    tracker.close:SetPoint("TOPRIGHT", -2, -2)
    tracker.title = S.Text(tracker, 12)
    tracker.title:SetPoint("LEFT", tracker.count, "RIGHT", 8, 0)
    tracker.title:SetPoint("RIGHT", tracker.close, "LEFT", -6, 0)
    tracker.title:SetJustifyH("LEFT")
    tracker.title:SetWordWrap(false)
    local line = S.Divider(tracker)
    line:SetPoint("TOPLEFT", 1, -HEAD_H)
    line:SetPoint("TOPRIGHT", -1, -HEAD_H)
    line:SetHeight(1)
    tracker.empty = S.Text(tracker, 12, S.FAINT)
    tracker.empty:SetPoint("TOPLEFT", 10, -HEAD_H - 10)
    tracker.empty:SetPoint("RIGHT", -10, 0)
    tracker.empty:SetJustifyH("LEFT")
    tracker.empty:SetText(L.TR_EMPTY)
    tracker.rows = {}
    for i = 1, ns.TRACK_MAX do tracker.rows[i] = makeRow(tracker) end
    S.Mover(tracker, { label = L.TR_TITLE,
        save = function(p, rp, x, y) if ns.db then ns.db.trackerPoint = { p, rp, x, y } end end,
        reset = function() if ns.db then ns.db.trackerPoint = nil end; place() end,
        lock = function() ns.Set("trackerLocked", true) end, lockTip = L.OPT_TRACK_LOCK })
end

-- Shows the tracker for a dungeon (kept over a reload) or, with nil, the one shown before.
function ns.ShowTracker(key)
    if ns.db and key then ns.db.tracker = key end
    ns.RefreshTracker()
end

function ns.HideTracker()
    if ns.db then ns.db.tracker = nil end
    ns.RefreshTracker()
end

function ns.MoveTracker(on)
    ns.movingTracker = on and true or nil
    ns.RefreshTracker()
end

function ns.RefreshTracker()
    if not ns.db then return end
    local moving = ns.movingTracker or not ns.Get("trackerLocked")
    local key = ns.db.tracker
    -- Unlocked with nothing to track, it shows the dungeon for the level, to be placed.
    if not key and moving then
        local s = ns.Suggest(UnitLevel("player") or 1)
        key = s and s.key
    end
    if not key then
        if tracker then tracker:SetMoving(false); tracker:Hide() end
        return
    end
    if not tracker then build() end
    local d
    for _, x in ipairs(ns.Dungeons(UnitLevel("player") or 1)) do if x.key == key then d = x end end
    if not d then ns.db.tracker = nil; tracker:Hide() return end
    tracker.key = key
    place()
    tracker.icon:SetIcon(ns.Icon(key))
    tracker.title:SetText(ns.DungeonName(d))
    local items, ready, total = ns.TrackerItems(key, UnitLevel("player") or 1)
    tracker.count:SetText(ready .. "/" .. total)
    local y = HEAD_H + 2
    for i, r in ipairs(tracker.rows) do
        local it = items[i]
        r:SetShown(it ~= nil)
        if it then
            fillRow(r, it)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 1, -y)
            r:SetPoint("TOPRIGHT", -1, -y)
            y = y + rowHeight(it)
        end
    end
    tracker.empty:SetShown(#items == 0)
    if #items == 0 then y = y + 34 end
    tracker:SetHeight(y + 4)
    tracker:SetMoving(moving and not (InCombatLockdown and InCombatLockdown()))
    tracker:Show()
end

-- The panel, for the tests.
function ns.TrackerFrame() return tracker end
