-- Dungeons on the left (icon, name, level range in the game's difficulty colours); on the
-- right the checklist and the dungeon's quests: in the log, the stops of the way to take the
-- rest with the entrance last, and the ones that come later. A Settings tab holds the
-- checklist thresholds and the switches.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, dungeons, checks, list, tabs, search, laterPill, entranceBtn, settings, questPage
local checkLines = {}
local showHidden = false
local ICON_OK, ICON_NO = "Interface\\RaidFrame\\ReadyCheck-Ready", "Interface\\RaidFrame\\ReadyCheck-NotReady"
-- The game icon of each check in ns.Checklist; keys and class items show their own icon.
local CHECK_ICON = { REPAIR = "Trade_BlackSmithing", BAGS = "INV_Misc_Bag_10", FOOD = "INV_Misc_Food_14",
                     HEARTH = "INV_Misc_Rune_01", AMMO = "INV_Ammo_Arrow_02", KEY = "INV_Misc_Key_04",
                     SHARDS = "INV_Misc_Gem_Amethyst_02", REAGENT = "INV_Misc_Dust_02", RESTOCK = "INV_Misc_Bag_08" }
local MAX_CHECKS, CHECK_ROW = 8, 34
local REWARD_ICONS = 3

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

local function coords(stop)
    return string.format("%.1f, %.1f", stop.x, stop.y)
end

local function money(c)
    if not c or c <= 0 then return nil end
    local g, s, b = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    if g > 0 then return string.format("%dg %ds", g, s) end
    if s > 0 then return string.format("%ds %dc", s, b) end
    return b .. "c"
end

-- The hover card of a quest: where it starts and ends, its chain, the mobs, the rewards.
local function questTooltip(owner, item)
    local q = item.quest
    if not (GameTooltip and q) then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine("[" .. q.level .. "] " .. q.name, 1, 0.82, 0)
    local where = ns.Where(q)
    if where ~= "" then GameTooltip:AddLine(L.TT_FROM:format(where), 1, 1, 1) end
    if q.turnin and q.turnin.who ~= "" then
        GameTooltip:AddLine(L.TT_TO:format(ns.Where({ who = q.turnin.who, area = q.turnin.area })), 1, 1, 1)
    end
    if q.steps and q.steps > 1 then GameTooltip:AddLine(L.STEP:format(q.step, q.steps), 0.7, 0.7, 0.7) end
    if q.need then GameTooltip:AddLine(ns.NeedText(q.need), 1, 0.5, 0.25, true) end
    if q.targets and #q.targets > 0 then
        GameTooltip:AddLine(L.TT_MOBS:format(table.concat(q.targets, ", ")), 0.7, 0.7, 0.7, true)
    end
    if item.group == "log" then
        local xp, cash = ns.LogReward(q.id)
        if xp > 0 then GameTooltip:AddLine(L.TT_XP:format(xp), 0.6, 0.6, 1) end
        if money(cash) then GameTooltip:AddLine(L.TT_MONEY:format(money(cash)), 1, 1, 1) end
        local others = ns.GroupOn(q.id)
        if #others > 0 then GameTooltip:AddLine(L.TT_GROUP:format(table.concat(others, ", ")), 0.4, 0.8, 1, true) end
    end
    local rewards = ns.Rewards(q)
    if #rewards > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L.TT_REWARDS, 1, 0.82, 0)
        for _, r in ipairs(rewards) do
            local name = r.name and (S.QualityHex(r.quality) .. r.name .. "|r") or ("#" .. r.id)
            local mark = r.better and (" " .. S.Hex(S.GOOD) .. L.BETTER .. "|r")
                or (r.name and not r.fits and (" " .. S.Hex(S.MUTED) .. L.NOT_FOR_YOU .. "|r")) or ""
            GameTooltip:AddLine((r.icon and ("|T" .. r.icon .. ":14|t ") or "") .. name .. mark)
        end
    end
    GameTooltip:AddLine(" ")
    if item.group == "log" then GameTooltip:AddLine(L.TT_CLICK_SHARE, 0.6, 0.6, 0.6) end
    GameTooltip:AddLine(item.hidden and L.TT_RIGHT_SHOW or L.TT_RIGHT_HIDE, 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function onRowClick(self, button)
    local r = self:GetParent()
    local item = r.item
    if not item then return end
    if item.toggleHidden then
        showHidden = not showHidden
        ns.Refresh()
        return
    end
    if item.stop then ns.SetPin(item.stop) return end
    local q = item.quest
    if not q then return end
    if button == "RightButton" then
        ns.SetHidden(q.id, not ns.Hidden(q.id))
        return
    end
    if item.group == "log" then
        if not ns.Share(q.id) and q.turnin and q.turnin.x > 0 then ns.SetPin(q.turnin) end
    elseif item.group == "take" and q.x > 0 then
        ns.SetPin({ who = q.who, zone = q.area and C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(q.area), x = q.x, y = q.y })
    end
end

local function makeRow(r)
    r.num = S.Text(r, 12, S.Accent())
    r.num:SetPoint("LEFT", 10, 0)
    r.num:SetWidth(18)
    r.text = S.Text(r, 12)
    r.text:SetWordWrap(false)
    r.sub = S.Text(r, 11, S.MUTED)
    r.sub:SetPoint("TOPLEFT", r.text, "BOTTOMLEFT", 0, -3)
    r.sub:SetPoint("RIGHT", r.text, "RIGHT")
    r.sub:SetWordWrap(false)
    r.rewards = {}
    for i = 1, REWARD_ICONS do
        local ic = S.IconBox(r, 20)
        ic:SetPoint("RIGHT", -8 - (REWARD_ICONS - i) * 24, 0)
        r.rewards[i] = ic
    end
    r.click = CreateFrame("Button", nil, r)
    r.click:SetAllPoints()
    if r.click.RegisterForClicks then r.click:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    r.click:SetScript("OnClick", onRowClick)
    r.click:SetScript("OnEnter", function(self) questTooltip(self, self:GetParent().item) end)
    r.click:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

local function setRewards(r, q)
    local shown = 0
    local rewards = q and ns.Rewards(q) or {}
    for i = 1, REWARD_ICONS do
        local ic, x = r.rewards[i], rewards[i]
        ic:SetShown(x ~= nil)
        if x then
            shown = i
            ic:SetIcon(x.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            ic:SetAlpha((x.name and not x.fits) and 0.35 or 1)
            S.SetBorder(ic, x.better and S.GOOD or S.BORDER)
        end
    end
    return shown
end

local function fillRow(r, item)
    r.item = item
    r.text:ClearAllPoints()
    r.num:SetText("")
    setRewards(r, nil)
    if item.header then
        S.Fill(r, S.RAISED)
        r.text:SetPoint("LEFT", 10, 0)
        r.text:SetPoint("RIGHT", -8, 0)
        r.text:SetTextColor(unpack(item.toggleHidden and S.MUTED or S.TEXT))
        r.text:SetText(item.text)
        r.sub:SetText("")
        return
    end
    local indent = (item.indent or item.stop) and 32 or 10
    S.Fill(r, S.CLEAR)
    local stop = item.stop
    if stop then
        r.text:SetPoint("TOPLEFT", indent, -5)
        r.text:SetPoint("RIGHT", -8, 0)
        r.num:SetText(item.n)
        r.text:SetTextColor(unpack(stop.entrance and S.Accent() or S.TEXT))
        if stop.inside then
            r.text:ClearAllPoints()
            r.text:SetPoint("LEFT", indent, 0)
            r.text:SetPoint("RIGHT", -8, 0)
            r.text:SetText(L.INSIDE)
            r.sub:SetText("")
            return
        end
        if stop.entrance then
            r.text:SetText(L.ENTRANCE:format(stop.who))
            r.sub:SetText((stop.zone and (stop.zone .. "  ·  ") or "") .. coords(stop) .. "  ·  " .. L.STOP_PIN)
            return
        end
        r.text:SetText(stop.zone and L.WHERE:format(stop.who, stop.zone) or stop.who)
        local at = stop.here and L.STOP_HERE:format(coords(stop)) or L.STOP_AT:format(coords(stop))
        r.sub:SetText(at .. "  ·  " .. L.STOP_PIN)
        return
    end
    local q = item.quest
    local icons = setRewards(r, q)
    r.text:SetPoint("TOPLEFT", indent, -5)
    r.text:SetPoint("RIGHT", -12 - icons * 24, 0)
    local diff = ns.Difficulty(q.level, ns.level or 1)
    r.text:SetTextColor(unpack((item.group == "later" or item.hidden) and S.MUTED or ns.DiffColor(diff)))
    r.text:SetText("[" .. q.level .. "] " .. q.name)
    local parts = {}
    if item.group == "take" then
        parts[1] = L["DIFF_" .. diff]
    elseif item.group == "later" then
        parts[1] = q.why == "WHY_LEVEL" and L.WHY_LEVEL:format(q.minLevel) or ns.NeedText(q.need)
    elseif item.group == "log" then
        parts[1] = L.IN_LOG
        if q.turnin and q.turnin.who ~= "" then parts[2] = L.HAND_TO:format(q.turnin.who) end
        local others = ns.GroupOn(q.id)
        if #others > 0 then parts[#parts + 1] = L.ALSO:format(table.concat(others, ", ")) end
    end
    if q.steps and q.steps > 1 then table.insert(parts, 1, L.STEP:format(q.step, q.steps)) end
    r.sub:SetText(table.concat(parts, "  ·  "))
end

local function refreshChecks()
    local lines = ns.Checklist(ns.selected)
    local n = math.min(#lines, MAX_CHECKS)
    for i = 1, MAX_CHECKS do
        local line, c = checkLines[i], lines[i]
        local on = i <= n
        line.icon:SetShown(on)
        line.state:SetShown(on)
        line.text:SetShown(on)
        if on then
            line.state:SetTexture(c.ok and ICON_OK or ICON_NO)
            local icon = c.item and (((C_Item and C_Item.GetItemIconByID) or GetItemIcon or function() end)(c.item))
            line.icon:SetIcon(icon or ("Interface\\Icons\\" .. (CHECK_ICON[c.key] or "INV_Misc_QuestionMark")))
            line.text:SetText(c.text)
            line.text:SetTextColor(unpack(c.ok and S.TEXT or S.WARN))
        end
    end
    local rows = math.max(2, math.ceil(n / 2))
    checks:Fit(rows * CHECK_ROW - 8)
end

function ns.Refresh()
    if not frame or not frame:IsShown() then return end
    local level = UnitLevel("player") or 1
    ns.level = level
    if not ns.selected then
        local s = ns.Suggest(level)
        ns.selected = s and s.key
    end
    local all = ns.Dungeons(level)
    dungeons:SetData(all)
    laterPill:SetSelected(ns.Get("hideLater"))
    local current
    for _, d in ipairs(all) do if d.key == ns.selected then current = d end end
    entranceBtn:SetEnabled(current ~= nil and current.entrance ~= nil)
    if settings then
        for _, x in ipairs(settings) do
            if x.stepper then x.stepper:Refresh() else x.row:SetChecked(x.get()) end
        end
    end
    if tabs.selected ~= 1 then return end
    refreshChecks()
    local items = {}
    if ns.selected then
        local q = ns.Quests(ns.selected, level, search:GetText())
        local function section(key, group, list)
            if #list == 0 then return end
            items[#items + 1] = { header = true, text = L[key]:format(#list) }
            for _, x in ipairs(list) do items[#items + 1] = { quest = x, group = group } end
        end
        section("IN_LOG_N", "log", q.log)
        if #q.take > 0 or current then
            local route = ns.Route(q.take, ns.Here(), current)
            if #q.take > 0 then items[#items + 1] = { header = true, text = L.TAKE_N:format(#q.take) } end
            for n, stop in ipairs(route) do
                items[#items + 1] = { stop = stop, n = n }
                for _, x in ipairs(stop.quests) do items[#items + 1] = { quest = x, group = "take", indent = true } end
            end
        end
        if ns.Get("hideLater") then
            if #q.later > 0 then items[#items + 1] = { header = true, text = L.LATER_HIDDEN:format(#q.later) } end
        else
            section("LATER_N", "later", q.later)
        end
        if #q.hidden > 0 then
            items[#items + 1] = { header = true, toggleHidden = true,
                                  text = (showHidden and L.HIDDEN_OPEN or L.HIDDEN_N):format(#q.hidden) }
            if showHidden then
                for _, x in ipairs(q.hidden) do items[#items + 1] = { quest = x, group = "hidden", hidden = true } end
            end
        end
        if q.done > 0 then items[#items + 1] = { header = true, text = L.DONE_N:format(q.done) } end
        if #items == 0 then items[1] = { header = true, text = L.NO_QUESTS } end
    end
    list:SetData(items)
end

local function buildSettings(parent)
    local page = CreateFrame("Frame", nil, parent)
    local function stepper(key, step, min, max, fmt)
        return S.Stepper(parent, function() return ns.Get(key) end, function(v) ns.Set(key, v) end, step, min, max, fmt)
    end
    local pct = function(v) return v .. "%" end
    local steps = {
        { "durMin", L.SET_DUR, 10, 10, 100, pct, "Trade_BlackSmithing" },
        { "bagsMin", L.SET_BAGS, 1, 0, 30, nil, "INV_Misc_Bag_10" },
        { "foodMin", L.SET_FOOD, 5, 0, 100, nil, "INV_Misc_Food_14" },
        { "ammoMin", L.SET_AMMO, 100, 0, 3000, nil, "INV_Ammo_Arrow_02" },
        { "shardsMin", L.SET_SHARDS, 1, 0, 30, nil, "INV_Misc_Gem_Amethyst_02" },
        { "reagentMin", L.SET_REAGENT, 1, 0, 40, nil, "INV_Misc_Dust_02" },
    }
    settings = {}
    local rows = {}
    for _, s in ipairs(steps) do
        local st = stepper(s[1], s[3], s[4], s[5], s[6])
        rows[#rows + 1] = { s[2], nil, control = st, icon = "Interface\\Icons\\" .. s[7] }
    end
    local left, lh = S.SettingsCard(page, L.SET_CHECKS, rows)
    for i in ipairs(left.rows) do settings[#settings + 1] = { stepper = rows[i].control } end
    left:SetPoint("TOPLEFT")
    left:SetPoint("TOPRIGHT", page, "TOP", -S.GAP / 2, 0)
    left:SetHeight(lh)
    local sw = {}
    for _, o in ipairs({ { "remind", L.OPT_REMIND, L.OPT_REMIND_D }, { "keys", L.OPT_KEYS, L.OPT_KEYS_D },
                         { "classCheck", L.OPT_CLASS, L.OPT_CLASS_D }, { "tomtom", L.OPT_TOMTOM, L.OPT_TOMTOM_D } }) do
        local key = o[1]
        sw[#sw + 1] = { o[2], o[3], function() return ns.Get(key) end, function(v) ns.Set(key, v) end,
                        icon = ns.OPT_ICON[key] }
    end
    local right, rh = S.SettingsCard(page, L.SET_SWITCHES, sw)
    for i, row in ipairs(right.rows) do settings[#settings + 1] = { row = row, get = sw[i][3] } end
    right:SetPoint("TOPLEFT", page, "TOP", S.GAP / 2, 0)
    right:SetPoint("TOPRIGHT")
    right:SetHeight(rh)
    return page
end

local function showTab(i)
    questPage:SetShown(i == 1)
    ns.settingsPage:SetShown(i == 2)
    search:SetShown(i == 1)
    laterPill:SetShown(i == 1)
    entranceBtn:SetShown(i == 1)
    ns.Refresh()
end

-- Opens a tab: 1 quests, 2 settings.
function ns.ShowTab(i)
    ns.Window()
    tabs:Select(i)
end

local function build()
    frame = S.Window("GulliDungeonPrepFrame", L.TITLE, S.WIDE_W, S.DOCK_H)
    local body = frame.body
    local left = S.Card(body)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(220)
    dungeons = S.List(left.body, 30, makeDungeon, fillDungeon)
    dungeons:SetPoint("TOPLEFT")
    dungeons:SetPoint("BOTTOMRIGHT", -10, 0)

    local area = CreateFrame("Frame", nil, body)
    area:SetPoint("TOPLEFT", left, "TOPRIGHT", S.GAP, 0)
    area:SetPoint("BOTTOMRIGHT")
    tabs = S.Tabs(area, { L.TAB_QUESTS, L.TAB_SETTINGS }, nil, showTab)
    entranceBtn = S.FitButton(area, L.PIN_ENTRANCE, 30, 80)
    entranceBtn:SetPoint("TOPRIGHT")
    entranceBtn:SetScript("OnClick", function()
        for _, d in ipairs(ns.Dungeons(ns.level or 1)) do
            if d.key == ns.selected and d.entrance then
                ns.SetPin({ who = ns.DungeonName(d), zone = C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(d.entrance.area),
                            x = d.entrance.x, y = d.entrance.y })
            end
        end
    end)
    laterPill = S.Pill(area, 110, 30)
    laterPill:SetText(L.HIDE_LATER)
    laterPill:SetPoint("RIGHT", entranceBtn, "LEFT", -8, 0)
    laterPill:SetScript("OnClick", function() ns.Set("hideLater", not ns.Get("hideLater")) end)
    search = S.Edit(area, 140, 30)
    search:SetJustifyH("LEFT")
    S.Placeholder(search, L.SEARCH)
    search:SetPoint("RIGHT", laterPill, "LEFT", -8, 0)
    search:HookScript("OnTextChanged", function() ns.Refresh() end)

    questPage = CreateFrame("Frame", nil, area)
    questPage:SetPoint("TOPLEFT", 0, -30 - S.GAP)
    questPage:SetPoint("BOTTOMRIGHT")
    checks = S.Card(questPage)
    checks:SetPoint("TOPLEFT")
    checks:SetPoint("TOPRIGHT")
    checks:Fit(CHECK_ROW * 2 - 8)
    for i = 1, MAX_CHECKS do
        local line = {}
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        line.icon = S.IconBox(checks.body, 26)
        line.icon:SetPoint("TOPLEFT", col * 270, -row * CHECK_ROW)
        line.state = checks.body:CreateTexture(nil, "ARTWORK")
        line.state:SetSize(14, 14)
        line.state:SetPoint("LEFT", line.icon, "LEFT", 242, 0)
        line.text = S.Text(checks.body, 12)
        line.text:SetPoint("LEFT", line.icon, "RIGHT", 10, 0)
        line.text:SetPoint("RIGHT", line.state, "LEFT", -6, 0)
        line.text:SetWordWrap(false)
        checkLines[i] = line
    end

    local right = S.Card(questPage)
    right:SetPoint("TOPLEFT", checks, "BOTTOMLEFT", 0, -S.GAP)
    right:SetPoint("BOTTOMRIGHT")
    list = S.List(right.body, 40, makeRow, fillRow)
    list:SetPoint("TOPLEFT")
    list:SetPoint("BOTTOMRIGHT", -10, 0)

    ns.settingsPage = buildSettings(area)
    ns.settingsPage:SetPoint("TOPLEFT", 0, -30 - S.GAP)
    ns.settingsPage:SetPoint("BOTTOMRIGHT")
    ns.settingsPage:Hide()
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
