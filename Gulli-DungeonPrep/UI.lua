-- Dungeons on the left (icon, name, level range in the game's difficulty colours); on the
-- right the checklist and the dungeon's quests: in the log, the stops of the way to take the
-- rest, and the ones that come later.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, dungeons, checks, list
local checkLines = {}
local ICON_OK, ICON_NO = "Interface\\RaidFrame\\ReadyCheck-Ready", "Interface\\RaidFrame\\ReadyCheck-NotReady"
-- The game icon of each check in ns.Checklist.
local CHECK_ICON = { REPAIR = "Trade_BlackSmithing", BAGS = "INV_Misc_Bag_10", FOOD = "INV_Misc_Food_14",
                     HEARTH = "INV_Misc_Rune_01", RESTOCK = "INV_Misc_Bag_08" }

local function makeDungeon(r)
    S.NavRow(r)
    r.line:Hide()
    r.icon = S.IconBox(r, 20)
    r.icon:SetPoint("LEFT", 8, 0)
    r.name = S.Text(r, 12)
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
    r.name:SetPoint("RIGHT", -40, 0)
    r.name:SetWordWrap(false)
    r.range = S.Text(r, 11, S.FAINT)
    r.range:SetPoint("RIGHT", -8, 0)
    r.range:SetJustifyH("RIGHT")
    r.click = CreateFrame("Button", nil, r)
    r.click:SetAllPoints()
    r.click:SetScript("OnClick", function(self) ns.selected = self:GetParent().d.key; ns.Refresh() end)
end

local function fillDungeon(r, d)
    r.d = d
    r.name:SetText(ns.DungeonName(d))
    r.name:SetTextColor(unpack(d.fits and S.TEXT or S.MUTED))
    r.icon:SetIcon(ns.Icon(d.key))
    r.range:SetText(d.min .. "-" .. d.max)
    r.range:SetTextColor(unpack(ns.DiffColor(ns.DungeonDifficulty(d, ns.level or 1))))
    r:SetSelected(d.key == ns.selected)
end

function ns.DiffColor(key) return ns.DIFF_COLOR[key] or S.TEXT end

local function makeRow(r)
    r.num = S.Text(r, 12, S.Accent())
    r.num:SetPoint("LEFT", 10, 0)
    r.num:SetWidth(18)
    r.text = S.Text(r, 12)
    r.text:SetWordWrap(false)
    r.sub = S.Text(r, 11, S.MUTED)
    r.sub:SetPoint("TOPLEFT", r.text, "BOTTOMLEFT", 0, -3)
    r.sub:SetPoint("RIGHT", -8, 0)
    r.sub:SetWordWrap(false)
    r.click = CreateFrame("Button", nil, r)
    r.click:SetAllPoints()
    r.click:SetScript("OnClick", function(self)
        local stop = self:GetParent().stop
        if stop then ns.SetPin(stop) end
    end)
end

local function coords(stop)
    return string.format("%.1f, %.1f", stop.x, stop.y)
end

local function fillRow(r, item)
    r.text:ClearAllPoints()
    r.stop = nil
    r.click:Hide()
    r.num:SetText("")
    if item.header then
        S.Fill(r, S.RAISED)
        r.text:SetPoint("LEFT", 10, 0)
        r.text:SetPoint("RIGHT", -8, 0)
        r.text:SetTextColor(unpack(S.TEXT))
        r.text:SetText(item.text)
        r.sub:SetText("")
        return
    end
    local indent = (item.indent or item.stop) and 32 or 10
    r.text:SetPoint("TOPLEFT", indent, -5)
    r.text:SetPoint("RIGHT", -8, 0)
    S.Fill(r, S.CLEAR)
    local stop = item.stop
    if stop then
        r.num:SetText(item.n)
        r.text:SetTextColor(unpack(S.TEXT))
        if stop.inside then
            r.text:ClearAllPoints()
            r.text:SetPoint("LEFT", indent, 0)
            r.text:SetPoint("RIGHT", -8, 0)
            r.text:SetText(L.INSIDE)
            r.sub:SetText("")
            return
        end
        r.text:SetText(stop.zone and L.WHERE:format(stop.who, stop.zone) or stop.who)
        local at = stop.here and L.STOP_HERE:format(coords(stop)) or L.STOP_AT:format(coords(stop))
        r.stop = stop
        r.click:Show()
        r.sub:SetText(at .. "  ·  " .. L.STOP_PIN)
        return
    end
    local q = item.quest
    local diff = ns.Difficulty(q.level, ns.level or 1)
    r.text:SetTextColor(unpack(item.group == "later" and S.MUTED or ns.DiffColor(diff)))
    r.text:SetText("[" .. q.level .. "] " .. q.name)
    if item.group == "take" then
        r.sub:SetText(L["DIFF_" .. diff])
    elseif item.group == "later" then
        r.sub:SetText(q.why == "WHY_LEVEL" and L.WHY_LEVEL:format(q.minLevel) or L.WHY_EARLIER)
    else
        r.sub:SetText(L.IN_LOG .. "  ·  " .. L["DIFF_" .. diff])
    end
end

function ns.Refresh()
    if not frame or not frame:IsShown() then return end
    local level = UnitLevel("player") or 1
    ns.level = level
    if not ns.selected then
        local s = ns.Suggest(level)
        ns.selected = s and s.key
    end
    dungeons:SetData(ns.Dungeons(level))
    for i, c in ipairs(ns.Checklist()) do
        local line = checkLines[i]
        if not line then break end
        line.state:SetTexture(c.ok and ICON_OK or ICON_NO)
        line.icon:SetIcon("Interface\\Icons\\" .. (CHECK_ICON[c.key] or "INV_Misc_QuestionMark"))
        line.text:SetText(c.text)
        line.text:SetTextColor(unpack(c.ok and S.TEXT or S.WARN))
    end
    local items = {}
    if ns.selected then
        local q = ns.Quests(ns.selected, level)
        local function section(key, group, list)
            if #list == 0 then return end
            items[#items + 1] = { header = true, text = L[key]:format(#list) }
            for _, x in ipairs(list) do items[#items + 1] = { quest = x, group = group } end
        end
        section("IN_LOG_N", "log", q.log)
        if #q.take > 0 then
            items[#items + 1] = { header = true, text = L.TAKE_N:format(#q.take) }
            for n, stop in ipairs(ns.Route(q.take, ns.Here())) do
                items[#items + 1] = { stop = stop, n = n }
                for _, x in ipairs(stop.quests) do items[#items + 1] = { quest = x, group = "take", indent = true } end
            end
        end
        section("LATER_N", "later", q.later)
        if q.done > 0 then items[#items + 1] = { header = true, text = L.DONE_N:format(q.done) } end
        if #items == 0 then items[1] = { header = true, text = L.NO_QUESTS } end
    end
    list:SetData(items)
end

local function build()
    frame = S.Window("GulliDungeonPrepFrame", L.TITLE, S.WIDE_W, 540)
    local body = frame.body
    local left = S.Card(body)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(220)
    dungeons = S.List(left.body, 30, makeDungeon, fillDungeon)
    dungeons:SetPoint("TOPLEFT")
    dungeons:SetPoint("BOTTOMRIGHT", -10, 0)

    checks = S.Card(body)
    checks:SetPoint("TOPLEFT", left, "TOPRIGHT", S.GAP, 0)
    checks:SetPoint("TOPRIGHT")
    local shown = #ns.Checklist()
    checks:Fit(34 * math.ceil(shown / 2) - 8)
    for i = 1, shown do
        local line = {}
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        line.icon = S.IconBox(checks.body, 26)
        line.icon:SetPoint("TOPLEFT", col * 250, -row * 34)
        line.state = checks.body:CreateTexture(nil, "ARTWORK")
        line.state:SetSize(14, 14)
        line.state:SetPoint("LEFT", line.icon, "LEFT", 222, 0)
        line.text = S.Text(checks.body, 12)
        line.text:SetPoint("LEFT", line.icon, "RIGHT", 10, 0)
        line.text:SetPoint("RIGHT", line.state, "LEFT", -6, 0)
        line.text:SetWordWrap(false)
        checkLines[i] = line
    end

    local right = S.Card(body)
    right:SetPoint("TOPLEFT", checks, "BOTTOMLEFT", 0, -S.GAP)
    right:SetPoint("BOTTOMRIGHT")
    list = S.List(right.body, 40, makeRow, fillRow)
    list:SetPoint("TOPLEFT")
    list:SetPoint("BOTTOMRIGHT", -10, 0)
    frame:SetScript("OnShow", ns.Refresh)
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
