-- The dungeon tracker: a small Gulli HUD panel on the right of the screen for the dungeon of
-- Lead me (ns.ShowTracker). It lists the dungeon's quests (ns.TrackerItems): ready to hand in,
-- in the log with their objectives, to take, and chain quests that wait for an earlier step.
-- A chain is one row with the step it is at; a click opens it to show every step, a right-click
-- opens the quest in the journal; the map button pins who to go to (and targets and marks them
-- when they are near, ns.TargetOver). The dungeon's icon under a row's mark says that what the
-- row asks for now (taking it, its work, handing it in) happens inside the dungeon. The cross closes it. Unlocked (its switch or /gulli move) it shows with its mover to be placed.

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
local opened = {}
local STEP_ICON = { done = "Interface\\RaidFrame\\ReadyCheck-Ready", missing = "Interface\\RaidFrame\\ReadyCheck-NotReady",
                    active = "Interface\\RaidFrame\\ReadyCheck-Waiting" }

-- Whether a chain's row shows its steps, and a switch for it.
function ns.TrackerOpen(key) return opened[key] == true end
function ns.ToggleTracked(key)
    opened[key] = not opened[key] or nil
    ns.RefreshTracker()
end

-- The lines of a row: its own, then its chain's steps while it is open.
local function rowLines(it)
    local lines = {}
    for _, l in ipairs(it.lines) do lines[#lines + 1] = l end
    if it.steps and opened[it.key] then
        for _, st in ipairs(it.steps) do
            local k = (st.done and "done") or (st.missing and "missing") or (st.active and "active")
            local mark = k and ("|T" .. STEP_ICON[k] .. ":12|t ") or "|cff666666·|r  "
            lines[#lines + 1] = { text = mark .. st.n .. ".  " .. st.name, stepOf = st }
        end
    end
    return lines
end

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
    return PAD + NAME_H + #rowLines(it) * LINE_H + PAD
end

local function lineOf(r, i)
    if not r.lines[i] then
        local t = S.Text(r, 12, S.MUTED)
        t:SetPoint("TOPLEFT", 30, -(PAD + NAME_H + (i - 1) * LINE_H))
        t:SetPoint("RIGHT", -32, 0)
        t:SetJustifyH("LEFT")
        t:SetWordWrap(false)
        r.lines[i] = t
    end
    return r.lines[i]
end

local function makeRow(parent)
    local r = CreateFrame("Button", nil, parent)
    if r.RegisterForClicks then r:RegisterForClicks("LeftButtonUp") end
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(16, 16)
    r.icon:SetPoint("TOPLEFT", 8, -PAD)
    -- Under the mark: the dungeon's icon, when what the row asks for now is done inside it.
    r.inside = S.IconBox(r, 16)
    r.inside:SetPoint("TOP", r.icon, "BOTTOM", 0, -2)
    r.name = S.Text(r, 12)
    r.name:SetPoint("TOPLEFT", 30, -PAD)
    r.name:SetPoint("RIGHT", -32, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
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
        if not (GameTooltip and it and it.pin) then return end
        GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
        GameTooltip:AddLine(L.TR_PIN:format(it.pin.who), 1, 1, 1)
        GameTooltip:AddLine(L.TR_TARGET, 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end
    r.pin:SetScript("OnEnter", function(self)
        local it = self:GetParent().item
        if not (it and it.pin) then return end
        pinTip(self, it)
        if ns.TargetOver then ns.TargetOver(self, it.pin.who, function(o) pinTip(o, it) end) end
    end)
    r.pin:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    if r.RegisterForClicks then r:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    r:SetScript("OnClick", function(self, button)
        local it = self.item
        if not (it and tracker.key) then return end
        if it.steps and button ~= "RightButton" then ns.ToggleTracked(it.key) return end
        ns.OpenTracked(tracker.key, it.id)
    end)
    r:SetScript("OnEnter", function(self)
        if not (GameTooltip and self.item) then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(self.item.name, 1, 0.82, 0)
        if self.item.inside and tracker.key then
            local c = S.Accent()
            GameTooltip:AddLine(S.IconTag(ns.Icon(tracker.key)) .. " " .. L.INSIDE_OF:format(tracker.title:GetText() or ""),
                c[1], c[2], c[3])
        end
        if self.item.steps then
            GameTooltip:AddLine(opened[self.item.key] and L.TR_FOLD or L.TR_UNFOLD, 1, 1, 1)
            GameTooltip:AddLine(L.TR_OPEN_RIGHT, 1, 1, 1)
        else
            GameTooltip:AddLine(L.TR_OPEN, 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
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
    r.name:SetTextColor(unpack(ns.DiffColor(diff)))
    local lines = rowLines(it)
    for i = 1, #lines do lineOf(r, i) end
    for i, t in ipairs(r.lines) do
        local line = lines[i]
        t:SetShown(line ~= nil)
        if line then
            t:SetText(line.text)
            local c, st = S.MUTED, line.stepOf
            if st then
                c = (st.this and S.Accent()) or (st.missing and S.BAD) or (st.done and S.FAINT) or S.MUTED
            elseif line.step then c = S.Accent()
            elseif it.state == "ready" then c = S.GOOD elseif it.state == "chain" then c = S.WARN
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
        reset = function() if ns.db then ns.db.trackerPoint = nil end; place() end })
    tracker:Hide()
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

-- The panel, for the hub's Unlock mode (built when it is asked for) and the tests.
function ns.TrackerFrame()
    if not tracker and ns.db then build() end
    return tracker
end
