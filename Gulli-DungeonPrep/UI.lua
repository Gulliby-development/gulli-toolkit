-- Dungeons on the left (icon, name, level range in the game's difficulty colours); on the
-- right the dungeon's header and its pages: Bosses (the boss list, the boss's model, abilities,
-- note and loot), Loot (every drop of the dungeon with the wishlist), Quests (in the log, the
-- stops of the way to take the rest with the entrance last, the ones that come later, and the
-- guide), and Settings.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, dungeons, list, tabs, search, entranceBtn, settings, questPage, listCard
local detail, head, filterRow, guideBtn, bossPage, lootPage
local filters, lootFilters = {}, {}
local counts = {}
local bossCache = {}
local showHidden = false
local ICON_OK = "Interface\\RaidFrame\\ReadyCheck-Ready"
local REWARD_ICONS = 3
local OBJ_MAX = 5
local TI = "Interface\\Icons\\"
-- One icon per action; every map pin (start, turn-in, entrance) shares the map.
local ACT_ICON = { map = TI .. "INV_Misc_Map_01", track = TI .. "Ability_Hunter_Pathfinding", share = S.TAB.group,
                   hide = TI .. "Ability_Stealth", later = TI .. "INV_Misc_PocketWatch_01" }
-- The list filters, each with its icon: every quest, the ones to take, the log, the done ones.
local FILTERS = { { "all", "F_ALL", S.TAB.list }, { "take", "F_TAKE", TI .. "INV_Misc_Note_01" },
                  { "log", "F_LOG", S.TAB.quests }, { "done", "F_DONE", TI .. "INV_Misc_Ribbon_01" } }
local WAIT_ICON = "Interface\\RaidFrame\\ReadyCheck-Waiting"

-- A button with a game icon before its text, as wide as both need.
local function iconButton(parent, icon, height)
    local b = S.Button(parent, 110, height or 30)
    S.SetButtonIcon(b, icon)
    return b
end
local function fitIcon(b, text, min)
    b:SetText(text)
    b:SetWidth(math.max(min or 96, math.floor((b.text:GetStringWidth() or 0) + 42)))
end

local function makeDungeon(r)
    S.NavRow(r)
    r.line:Hide()
    r.icon = S.IconBox(r, 20)
    r.icon:SetPoint("LEFT", 8, 0)
    r.range = S.Text(r, 11, S.FAINT)
    r.range:SetPoint("RIGHT", -8, 0)
    r.range:SetJustifyH("RIGHT")
    r.count = S.Text(r, 10)
    r.count:SetPoint("RIGHT", r.range, "LEFT", -6, 0)
    r.count:SetJustifyH("RIGHT")
    r.name = S.Text(r, 12)
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
    r.name:SetPoint("RIGHT", r.count, "LEFT", -6, 0)
    r.name:SetWordWrap(false)
    r.click = CreateFrame("Button", nil, r)
    r.click:SetAllPoints()
    r.click:SetScript("OnClick", function(self)
        ns.selected = self:GetParent().d.key
        ns.openQuest = nil
        ns.Refresh()
    end)
    -- The full name (the row may cut it) and what waits there.
    r.click:SetScript("OnEnter", function(self)
        local d = self:GetParent().d
        if not (GameTooltip and d) then return end
        local c = counts[d.key] or { log = 0, take = 0, done = 0 }
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(ns.DungeonName(d) .. "  " .. d.min .. "-" .. d.max, 1, 0.82, 0)
        GameTooltip:AddLine(L.TT_DUNGEON:format(c.log, c.take, c.done), 1, 1, 1)
        GameTooltip:Show()
    end)
    r.click:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

local function fillDungeon(r, d)
    r.d = d
    r.name:SetText(ns.DungeonName(d))
    r.name:SetTextColor(unpack(d.fits and S.TEXT or S.MUTED))
    r.icon:SetIcon(ns.Icon(d.key))
    r.range:SetText(d.min .. "-" .. d.max)
    r.range:SetTextColor(unpack(ns.DiffColor(ns.DungeonDifficulty(d, ns.level or 1))))
    -- Quests in the log (accent) or to take (green) here.
    local c = counts[d.key]
    local n = c and (c.log + c.take) or 0
    r.count:SetText(n > 0 and tostring(n) or "")
    r.count:SetTextColor(unpack((c and c.log > 0) and S.Accent() or S.GOOD))
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
    GameTooltip:AddLine(L.TT_CLICK_OPEN, 0.6, 0.6, 0.6)
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
    ns.OpenQuest(q.id)
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

-- The dungeon's header: name, levels, bosses and quest counts, the keys, the entrance.
local function fillHead(current, level)
    local c = counts[ns.selected] or { log = 0, take = 0, later = 0, done = 0 }
    head.icon:SetIcon(ns.Icon(ns.selected or ""))
    head.name:SetText(current and ns.DungeonName(current) or "")
    head.range:SetText(current and (current.min .. "-" .. current.max) or "")
    if current then head.range:SetTextColor(unpack(ns.DiffColor(ns.DungeonDifficulty(current, level)))) end
    local parts = { L.HEAD_COUNTS:format(c.log, c.take, c.later, c.done) }
    local n = 0
    for _, b in ipairs(bossCache) do if not b.rare then n = n + 1 end end
    if n > 0 then table.insert(parts, 1, L.HEAD_BOSSES:format(n)) end
    if ns.Get("keys") then
        for _, k in ipairs(ns.KeyState(ns.selected)) do
            parts[#parts + 1] = S.Hex(k.have and S.GOOD or S.BAD) .. (k.have and L.CHECK_KEY or L.CHECK_NO_KEY):format(k.name) .. "|r"
        end
    end
    head.sub:SetText(table.concat(parts, "  ·  "))
    entranceBtn:SetEnabled(current ~= nil and current.entrance ~= nil)
end

-- The quests of the list for a filter, in the order the list shows them; ns.listIds keeps
-- that order for the arrows on a quest's page.
local function listItems(current, level)
    local items, ids = {}, {}
    local q = ns.Quests(ns.selected, level, search:GetText())
    local filter = ns.filter or "all"
    local function add(item)
        items[#items + 1] = item
        if item.quest then ids[#ids + 1] = item.quest.id end
    end
    local function section(key, group, quests)
        if #quests == 0 then return end
        add({ header = true, text = L[key]:format(#quests) })
        for _, x in ipairs(quests) do add({ quest = x, group = group }) end
    end
    if filter == "all" or filter == "log" then section("IN_LOG_N", "log", q.log) end
    if (filter == "all" or filter == "take") and (#q.take > 0 or current) then
        local route = ns.Route(q.take, ns.Here(), current)
        if #q.take > 0 then add({ header = true, text = L.TAKE_N:format(#q.take) }) end
        for n, stop in ipairs(route) do
            add({ stop = stop, n = n })
            for _, x in ipairs(stop.quests) do add({ quest = x, group = "take", indent = true }) end
        end
    end
    if filter == "all" then
        if ns.Get("hideLater") then
            if #q.later > 0 then add({ header = true, text = L.LATER_HIDDEN:format(#q.later) }) end
        else
            section("LATER_N", "later", q.later)
        end
        if #q.hidden > 0 then
            add({ header = true, toggleHidden = true, text = (showHidden and L.HIDDEN_OPEN or L.HIDDEN_N):format(#q.hidden) })
            if showHidden then
                for _, x in ipairs(q.hidden) do add({ quest = x, group = "hidden", hidden = true }) end
            end
        end
    end
    if filter == "done" then
        for _, x in ipairs(q.finished) do add({ quest = x, group = "done" }) end
        if #q.finished == 0 then add({ header = true, text = L.NO_DONE }) end
    end
    if #items == 0 then add({ header = true, text = L.NO_QUESTS }) end
    if filter == "take" and #q.take == 0 then items = { { header = true, text = L.NO_QUESTS } } end
    ns.listIds = ids
    ns.takeCount = #q.take
    return items
end

-- Bosses and loot -----------------------------------------------------------------------------

local WISH_ICON = "Interface\\Icons\\INV_Misc_Gem_Pearl_04"
local MAX_SPELLS = 6
local LOOT_FILTERS = { { "all", "F_LOOT_ALL", S.TAB.list }, { "mine", "F_MINE", TI .. "INV_Chest_Chain_05" },
                       { "wish", "F_WISH", WISH_ICON } }

-- The hover card of a loot line: the game's item tooltip, then where and how often it drops.
local function lootTooltip(owner, l)
    if not (GameTooltip and l) then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then GameTooltip:SetItemByID(l.item) end
    GameTooltip:AddLine(" ")
    local chance = l.pct > 0 and (L.CHANCE:format(l.pct) .. (l.own and ("  " .. L.CHANCE_OWN) or "")) or L.SEEN
    GameTooltip:AddLine(l.boss .. ":  " .. chance, 1, 0.82, 0)
    if l.runs then GameTooltip:AddLine(L.RUNS_TT:format(l.runs), 0.7, 0.7, 0.7) end
    GameTooltip:AddLine(L.TT_LOOT_CLICK, 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end

local function onLootClick(self, button)
    local l = self:GetParent().loot
    if not l then return end
    local link = l.link or select(2, ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(l.item))
    if IsShiftKeyDown and IsShiftKeyDown() and link and ChatEdit_InsertLink then
        ChatEdit_InsertLink(link)
    elseif IsControlKeyDown and IsControlKeyDown() and link and DressUpItemLink then
        DressUpItemLink(link)
    elseif button == "RightButton" then
        ns.SetWish(l.item, not l.wish)
    end
end

local function makeLoot(r)
    r.icon = S.IconBox(r, 24)
    r.icon:SetPoint("LEFT", 6, 0)
    r.wish = CreateFrame("Button", nil, r)
    r.wish:SetSize(22, 22)
    r.wish:SetPoint("RIGHT", -6, 0)
    r.wish.tex = r.wish:CreateTexture(nil, "ARTWORK")
    r.wish.tex:SetAllPoints()
    r.wish.tex:SetTexture(WISH_ICON)
    r.wish:SetScript("OnClick", function(self)
        local l = self:GetParent().loot
        if l then ns.SetWish(l.item, not l.wish) end
    end)
    r.wish:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(self:GetParent().loot and self:GetParent().loot.wish and L.WISH_REMOVE or L.WISH_ADD)
            GameTooltip:Show()
        end
    end)
    r.wish:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    r.pct = S.Text(r, 12)
    r.pct:SetPoint("TOPRIGHT", r.wish, "TOPLEFT", -10, 2)
    r.pct:SetJustifyH("RIGHT")
    r.pct:SetWidth(64)
    r.runs = S.Text(r, 10, S.FAINT)
    r.runs:SetPoint("TOPRIGHT", r.pct, "BOTTOMRIGHT", 0, -2)
    r.runs:SetJustifyH("RIGHT")
    r.runs:SetWidth(84)
    r.name = S.Text(r, 12)
    r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, 1)
    r.name:SetPoint("RIGHT", r.pct, "LEFT", -8, 0)
    r.name:SetWordWrap(false)
    r.sub = S.Text(r, 10, S.MUTED)
    r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
    r.sub:SetPoint("RIGHT", r.runs, "LEFT", -8, 0)
    r.sub:SetWordWrap(false)
    r.click = CreateFrame("Button", nil, r)
    r.click:SetPoint("TOPLEFT")
    r.click:SetPoint("BOTTOMRIGHT", r.wish, "BOTTOMLEFT", -4, -6)
    if r.click.RegisterForClicks then r.click:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    r.click:SetScript("OnClick", onLootClick)
    r.click:SetScript("OnEnter", function(self) lootTooltip(self, self:GetParent().loot) end)
    r.click:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

-- The slot or kind of an item, in the game's own words.
local function slotText(l)
    local loc = l.equipLoc
    if loc and loc ~= "" and _G[loc] then return _G[loc] end
    return ""
end

local function fillLoot(r, item)
    if item.header then
        r.loot = nil
        r.icon:Hide(); r.wish:Hide(); r.pct:SetText(""); r.runs:SetText("")
        r.name:SetText(item.text)
        r.name:SetTextColor(unpack(S.MUTED))
        r.sub:SetText("")
        return
    end
    local l = item.loot
    r.loot = l
    r.icon:Show(); r.wish:Show()
    r.icon:SetIcon(l.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    r.icon:SetAlpha(l.fits == false and 0.4 or 1)
    S.SetBorder(r.icon, l.better and S.GOOD or S.BORDER)
    r.name:SetText((S.QualityHex(l.quality or 1)) .. (l.name or ("item:" .. l.item)) .. "|r")
    local sub = {}
    if item.showBoss then sub[#sub + 1] = l.boss end
    local slot = slotText(l)
    if slot ~= "" then sub[#sub + 1] = slot end
    if l.better then sub[#sub + 1] = S.Hex(S.GOOD) .. L.BETTER .. "|r"
    elseif l.fits == false then sub[#sub + 1] = L.NOT_FOR_YOU end
    if l.seen then sub[#sub + 1] = S.Hex(S.Accent()) .. L.SEEN .. "|r" end
    r.sub:SetText(table.concat(sub, "  ·  "))
    if l.pct > 0 then
        r.pct:SetText(L.CHANCE:format(l.pct))
        r.pct:SetTextColor(unpack(l.own and S.Accent() or S.TEXT))
    else
        r.pct:SetText("-")
        r.pct:SetTextColor(unpack(S.MUTED))
    end
    r.runs:SetText(l.runs and L.RUNS:format(l.runs) or "")
    r.wish.tex:SetDesaturated(not l.wish)
    r.wish:SetAlpha(l.wish and 1 or 0.35)
end

local function makeBoss(r)
    S.NavRow(r)
    r.line:Hide()
    r.num = S.Text(r, 12, S.Accent())
    r.num:SetPoint("LEFT", 8, 0)
    r.num:SetWidth(16)
    r.name = S.Text(r, 12)
    r.name:SetPoint("TOPLEFT", 28, -5)
    r.name:SetPoint("RIGHT", -6, 0)
    r.name:SetWordWrap(false)
    r.sub = S.Text(r, 10, S.FAINT)
    r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
    r.sub:SetPoint("RIGHT", -6, 0)
    r.sub:SetWordWrap(false)
    r.click = CreateFrame("Button", nil, r)
    r.click:SetAllPoints()
    r.click:SetScript("OnClick", function(self)
        ns.boss = self:GetParent().b.npc
        ns.Refresh()
    end)
end

-- A boss's level, "??" for a skull boss (the data has 0).
local function bossLevel(b)
    if b.min <= 0 then return "??" end
    return b.min == b.max and tostring(b.min) or (b.min .. "-" .. b.max)
end

local function fillBoss(r, b)
    r.b = b
    r.num:SetText(b.rare and "R" or tostring(b.n))
    r.num:SetTextColor(unpack(b.rare and S.WARN or S.Accent()))
    r.name:SetText(b.name)
    local lv = bossLevel(b)
    local parts = { L.LEVEL:format(lv) }
    if b.tag ~= "" then table.insert(parts, 1, b.tag) end
    if b.kills > 0 then parts[#parts + 1] = L.KILLS:format(b.kills) end
    r.sub:SetText(table.concat(parts, "  ·  "))
    r:SetSelected(b.npc == ns.boss)
end

-- The boss page: the model, name, abilities and note on top, the loot under it.
local function fillBossPage()
    local list = bossCache
    bossPage.empty:SetShown(#list == 0)
    bossPage.left:SetShown(#list > 0)
    bossPage.info:SetShown(#list > 0)
    bossPage.lootCard:SetShown(#list > 0)
    if #list == 0 then return end
    local b
    for _, x in ipairs(list) do if x.npc == ns.boss then b = x end end
    if not b then b = list[1]; ns.boss = b.npc end
    bossPage.list:SetData(list)
    local p = bossPage
    if p.model.SetDisplayInfo and b.display > 0 and p.model.shown ~= b.display then
        p.model.shown = b.display
        if p.model.ClearModel then p.model:ClearModel() end
        p.model:SetDisplayInfo(b.display)
        if p.model.SetFacing then p.model:SetFacing(0) end
    end
    p.name:SetText(b.name)
    p.name:SetTextColor(unpack(b.rare and S.WARN or S.TEXT))
    local lv = bossLevel(b)
    local parts = { L.LEVEL:format(lv) }
    if b.tag ~= "" then table.insert(parts, 1, b.tag) end
    if b.rare then parts[#parts + 1] = L.RARE end
    p.sub:SetText(table.concat(parts, "  ·  "))
    p.kills:SetText(b.kills > 0 and L.KILLS:format(b.kills) or L.NO_KILLS)
    for i, ic in ipairs(p.spells) do
        local s = b.spells[i]
        ic:SetShown(s ~= nil)
        ic.spell = s
        if s then ic:SetIcon(s.icon or "Interface\\Icons\\INV_Misc_QuestionMark") end
    end
    p.spellLabel:SetShown(#b.spells > 0)
    if not p.note:HasFocus() then p.note:SetText(ns.Note("n" .. b.npc)) end
    p.noteKey = "n" .. b.npc
    p.lootCard:SetTitle(L.LOOT_OF, tostring(#b.loot))
    local items = {}
    for _, l in ipairs(b.loot) do items[#items + 1] = { loot = l } end
    if #items == 0 then items[1] = { header = true, text = L.NO_LOOT } end
    p.loot:SetData(items)
end

local function fillLootPage()
    local filter = ns.lootFilter or "all"
    local all = ns.Loot(ns.selected, "all", search:GetText())
    local n = { all = #all, mine = 0, wish = 0 }
    for _, l in ipairs(all) do
        if l.fits ~= false then n.mine = n.mine + 1 end
        if l.wish then n.wish = n.wish + 1 end
    end
    local x = 0
    for _, f in ipairs(LOOT_FILTERS) do
        local b = lootFilters[f[1]]
        b:SetText(f[1] == "mine" and L.F_MINE:format(n.mine) or L[f[2]]:format(n[f[1]]))
        b:SetWidth(math.floor((b.text:GetStringWidth() or 0) + 44))
        b:ClearAllPoints()
        b:SetPoint("LEFT", lootPage.filters, "LEFT", x, 0)
        x = x + b:GetWidth() + 6
        b:SetSelected(filter == f[1])
    end
    local items = {}
    for _, l in ipairs(ns.Loot(ns.selected, filter, search:GetText())) do items[#items + 1] = { loot = l, showBoss = true } end
    if #items == 0 then
        items[1] = { header = true, text = (#bossCache == 0 and L.NO_BOSSES) or (filter == "wish" and L.NO_WISH) or L.NO_LOOT }
    end
    lootPage.list:SetData(items)
end

function ns.Refresh()
    if not frame or not frame:IsShown() then return end
    local level = UnitLevel("player") or 1
    ns.level = level
    if not ns.selected then
        local here = ns.CurrentDungeon and ns.CurrentDungeon()
        local s = here or ns.Suggest(level)
        ns.selected = s and s.key
    end
    local all = ns.Dungeons(level)
    for _, d in ipairs(all) do counts[d.key] = ns.Counts(d.key, level) end
    dungeons:SetData(all)
    local current
    for _, d in ipairs(all) do if d.key == ns.selected then current = d end end
    bossCache = ns.Bosses(ns.selected)
    if settings then for _, x in ipairs(settings) do x.row:SetChecked(x.get()) end end
    local tab = tabs.selected
    head:SetShown(tab ~= 4)
    if tab == 4 then return end
    fillHead(current, level)
    if tab == 1 then return fillBossPage() end
    if tab == 2 then return fillLootPage() end
    local open = ns.openQuest ~= nil
    filterRow:SetShown(not open)
    listCard:SetShown(not open)
    detail:SetShown(open)
    local c = counts[ns.selected] or { log = 0, take = 0, later = 0, done = 0 }
    local n = { all = c.log + c.take + c.later, take = c.take, log = c.log, done = c.done }
    local x = 0
    for _, f in ipairs(FILTERS) do
        local b = filters[f[1]]
        b:SetText(L[f[2]]:format(n[f[1]]))
        b:SetWidth(math.floor((b.text:GetStringWidth() or 0) + 44))
        b:ClearAllPoints()
        b:SetPoint("LEFT", filterRow, "LEFT", x, 0)
        x = x + b:GetWidth() + 6
        b:SetSelected((ns.filter or "all") == f[1])
    end
    local guiding = ns.guide ~= nil and ns.guide.key == ns.selected
    fitIcon(guideBtn, guiding and L.GUIDE_STOP or L.GUIDE, 90)
    guideBtn:SetEnabled(guiding or c.take > 0)
    -- The list is computed even on a quest's page, so its arrows follow the list.
    local items = ns.selected and listItems(current, level) or {}
    if open then
        ns.FillDetail(level)
        return
    end
    list:SetData(items)
end

-- The page of one quest (like a dungeon journal): what to do, where it starts and ends with a
-- map pin for each, the whole chain as numbered steps, the rewards and the mobs, and Track,
-- Share and Hide. ns.openQuest is the quest shown; nil shows the list.
local REWARD_MAX, CHAIN_ROW = 4, 40
local SIDE_TEXT = { A = "FACTION_A", H = "FACTION_H" }
local SIDE_ICON = { A = "Interface\\Icons\\INV_BannerPVP_02", H = "Interface\\Icons\\INV_BannerPVP_01" }
local STATE_COLOR = { log = S.Accent and S.Accent() or S.TEXT, take = S.GOOD, done = S.MUTED, later = S.WARN,
                      closed = S.MUTED, hidden = S.MUTED }

function ns.OpenQuest(id)
    ns.openQuest = id
    ns.Refresh()
end

local function label(parent, text)
    local t = S.Text(parent, 11, S.FAINT)
    t:SetText(text)
    t:SetWordWrap(false)
    return t
end

local function makeStep(r)
    r.state = r:CreateTexture(nil, "ARTWORK")
    r.state:SetSize(14, 14)
    r.state:SetPoint("LEFT", 6, 0)
    r.text = S.Text(r, 12)
    r.text:SetPoint("TOPLEFT", 26, -6)
    r.text:SetPoint("RIGHT", -6, 0)
    r.text:SetWordWrap(false)
    r.sub = S.Text(r, 11, S.MUTED)
    r.sub:SetPoint("TOPLEFT", r.text, "BOTTOMLEFT", 0, -3)
    r.sub:SetPoint("RIGHT", -6, 0)
    r.sub:SetWordWrap(false)
    r.click = CreateFrame("Button", nil, r)
    r.click:SetAllPoints()
    r.click:SetScript("OnClick", function(self)
        local st = self:GetParent().step
        if not st then return end
        if st.dungeon and not st.this then ns.OpenQuest(st.id) return end
        ns.PinAt(st.who, st.area, st.x, st.y)
    end)
    r.click:SetScript("OnEnter", function(self)
        local st = self:GetParent().step
        if not (GameTooltip and st) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("[" .. (st.level or "?") .. "] " .. st.name, 1, 0.82, 0)
        local where = ns.Where({ who = st.who or "", area = st.area or 0 })
        if where ~= "" then GameTooltip:AddLine(L.TT_FROM:format(where), 1, 1, 1) end
        GameTooltip:AddLine(st.dungeon and not st.this and L.TT_CLICK_OPEN or L.CHAIN_PIN, 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    r.click:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

local function fillStep(r, st)
    r.step = st
    r.text:SetText(st.n .. ".  " .. st.name)
    -- Who gives the step and where.
    r.sub:SetText((st.who and st.who ~= "") and ns.Where({ who = st.who, area = st.area or 0 }) or "")
    local c = S.TEXT
    if st.this then c = S.Accent() elseif st.missing then c = S.BAD elseif st.done then c = S.MUTED end
    r.text:SetTextColor(unpack(c))
    S.Fill(r, st.this and S.RAISED or S.CLEAR)
    r.state:SetShown(st.done or st.active or st.missing)
    if st.done then r.state:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    elseif st.missing then r.state:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
    else r.state:SetTexture("Interface\\RaidFrame\\ReadyCheck-Waiting") end
end

local function buildDetail(parent)
    local d = CreateFrame("Frame", nil, parent)
    -- Header: back, title, faction and state.
    local top = S.Card(d)
    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT")
    top:Fit(44)
    -- Back to the list: the list icon, so it is not taken for the arrows on the right.
    d.back = S.Button(top.body, 30, 30)
    d.back:SetText("")
    S.SetButtonIcon(d.back, S.TAB.list, 18)
    d.back.btnIcon:ClearAllPoints()
    d.back.btnIcon:SetPoint("CENTER")
    d.back:SetPoint("LEFT")
    d.back:SetScript("OnClick", function() ns.openQuest = nil; ns.Refresh() end)
    d.back:HookScript("OnEnter", function(self)
        if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(L.BACK); GameTooltip:Show() end
    end)
    d.back:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    -- The quest before and after this one in the list.
    local function arrow(text, tip, step)
        local a = S.Button(top.body, 30, 30)
        a:SetText(text)
        a:SetScript("OnClick", function()
            local ids, at = ns.listIds or {}, nil
            for i, id in ipairs(ids) do if id == ns.openQuest then at = i end end
            if at and ids[at + step] then ns.OpenQuest(ids[at + step]) end
        end)
        a:HookScript("OnEnter", function(self)
            if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(tip); GameTooltip:Show() end
        end)
        a:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        return a
    end
    d.prev = arrow("<", L.PREV, -1)
    d.next = arrow(">", L.NEXT, 1)
    d.side = S.IconBox(top.body, 22)
    d.side:SetPoint("TOPRIGHT", 0, 0)
    d.next:SetPoint("RIGHT", d.side, "LEFT", -10, 0)
    d.prev:SetPoint("RIGHT", d.next, "LEFT", -4, 0)
    d.state = S.Badge(top.body, "")
    d.state.text:SetWordWrap(false)
    d.state:SetPoint("RIGHT", d.prev, "LEFT", -10, 0)
    d.title = S.Text(top.body, 14)
    d.title:SetPoint("TOPLEFT", d.back, "TOPRIGHT", 10, 0)
    d.title:SetPoint("RIGHT", d.state, "LEFT", -8, 0)
    d.title:SetWordWrap(false)
    d.sub = S.Text(top.body, 11, S.MUTED)
    d.sub:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -4)
    d.sub:SetPoint("RIGHT", top.body, "RIGHT")
    d.sub:SetWordWrap(false)

    -- Footer: the actions.
    local foot = CreateFrame("Frame", nil, d)
    foot:SetPoint("BOTTOMLEFT")
    foot:SetPoint("BOTTOMRIGHT")
    foot:SetHeight(30)
    d.track = iconButton(foot, ACT_ICON.track)
    d.track:SetPoint("LEFT")
    d.track:SetScript("OnClick", function() if ns.openQuest then ns.Track(ns.openQuest) end end)
    d.share = iconButton(foot, ACT_ICON.share)
    fitIcon(d.share, L.SHARE)
    d.share:SetPoint("LEFT", d.track, "RIGHT", 8, 0)
    d.share:SetScript("OnClick", function()
        if ns.openQuest and not ns.Share(ns.openQuest) then print("|cff9ad0ffGulli-DungeonPrep|r: " .. L.NOT_IN_GROUP) end
    end)
    d.hide = iconButton(foot, ACT_ICON.hide)
    d.hide:SetPoint("LEFT", d.share, "RIGHT", 8, 0)
    d.hide:SetScript("OnClick", function()
        if ns.openQuest then ns.SetHidden(ns.openQuest, not ns.Hidden(ns.openQuest)) end
    end)
    -- The player's own note on the quest.
    d.note = S.Edit(foot, 220, 28)
    d.note:SetPoint("RIGHT")
    d.note:SetJustifyH("LEFT")
    S.Placeholder(d.note, L.NOTE_QUEST)
    d.note:HookScript("OnTextChanged", function(self, user)
        if user and ns.openQuest then ns.SetNote("q" .. ns.openQuest, self:GetText()) end
    end)
    d.note:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    d.status = S.Text(foot, 11, S.MUTED)
    d.status:SetPoint("LEFT", d.hide, "RIGHT", 12, 0)
    d.status:SetPoint("RIGHT", d.note, "LEFT", -8, 0)
    d.status:SetWordWrap(false)

    -- Left: objective, start, turn-in, what it needs, rewards, mobs.
    local info = S.Card(d)
    info:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -S.GAP)
    info:SetPoint("BOTTOMLEFT", foot, "TOPLEFT", 0, S.GAP)
    info:SetPoint("RIGHT", d, "CENTER", 20, 0)
    local b = info.body
    d.infoBody = b
    d.objLabel = label(b, L.DETAIL_OBJECTIVE)
    d.objLabel:SetPoint("TOPLEFT")
    -- One row per objective: its state, the count, then what it asks for.
    d.objRows = {}
    for i = 1, OBJ_MAX do
        local r = {}
        r.state = b:CreateTexture(nil, "ARTWORK")
        r.state:SetSize(14, 14)
        r.state:SetPoint("TOP", i == 1 and d.objLabel or d.objRows[i - 1].text, "BOTTOM", 0, -6)
        r.state:SetPoint("LEFT", b, "LEFT")
        r.count = S.Text(b, 12)
        r.count:SetPoint("LEFT", r.state, "RIGHT", 6, 0)
        r.count:SetJustifyH("LEFT")
        r.text = S.Text(b, 12)
        r.text:SetPoint("TOPLEFT", r.count, "TOPRIGHT", 6, 0)
        r.text:SetPoint("RIGHT", b, "RIGHT")
        r.text:SetJustifyH("LEFT")
        r.text:SetJustifyV("TOP")
        d.objRows[i] = r
    end

    -- A place: its label, the giver and zone, then the spot with its map button.
    local function place(name, title)
        local l = label(b, title)
        local t = S.Text(b, 12)
        t:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 0, -5)
        t:SetPoint("RIGHT", b, "RIGHT")
        t:SetWordWrap(false)
        local btn = iconButton(b, ACT_ICON.map, 28)
        fitIcon(btn, L.SHOW_ON_MAP)
        btn:SetPoint("TOP", t, "BOTTOM", 0, -4)
        btn:SetPoint("RIGHT", b, "RIGHT")
        local xy = S.Text(b, 11, S.MUTED)
        xy:SetPoint("LEFT", t, "LEFT")
        xy:SetPoint("TOP", btn, "TOP")
        xy:SetPoint("BOTTOM", btn, "BOTTOM")
        xy:SetPoint("RIGHT", btn, "LEFT", -8, 0)
        xy:SetWordWrap(false)
        d[name .. "Label"], d[name], d[name .. "Map"], d[name .. "XY"] = l, t, btn, xy
        return t
    end
    place("start", L.DETAIL_START)
    d.startMap:SetScript("OnClick", function()
        local q = d.q
        if q then ns.PinAt(q.who, q.area, q.x, q.y) end
    end)
    place("turnin", L.DETAIL_TURNIN)
    d.turninLabel:SetPoint("TOP", d.startMap, "BOTTOM", 0, -10)
    d.turninLabel:SetPoint("LEFT", b, "LEFT")
    d.turninMap:SetScript("OnClick", function()
        local t = d.q and d.q.turnin
        if t then ns.PinAt(t.who, t.area, t.x, t.y) end
    end)
    d.need = S.Text(b, 12, S.BAD)
    d.need:SetPoint("TOP", d.turninMap, "BOTTOM", 0, -10)
    d.need:SetPoint("LEFT", b, "LEFT")
    d.need:SetPoint("RIGHT", b, "RIGHT")
    d.need:SetWordWrap(false)
    d.rewLabel = label(b, L.DETAIL_REWARDS)
    -- One row per reward: its icon, its name in its quality colour, and whether it is for you.
    d.rewards = {}
    for i = 1, REWARD_MAX do
        local row = CreateFrame("Frame", nil, b)
        row:SetHeight(24)
        row:SetPoint("TOP", i == 1 and d.rewLabel or d.rewards[i - 1], "BOTTOM", 0, i == 1 and -6 or -2)
        row:SetPoint("LEFT", b, "LEFT")
        row:SetPoint("RIGHT", b, "RIGHT")
        row.icon = S.IconBox(row, 22)
        row.icon:SetPoint("LEFT", 2, 0)
        row.name = S.Text(row, 12)
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.name:SetPoint("RIGHT")
        row.name:SetWordWrap(false)
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            if not (GameTooltip and self.id) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.id) end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        d.rewards[i] = row
    end
    d.mobLabel = label(b, L.DETAIL_MOBS)
    d.mobLabel:SetPoint("TOPLEFT", d.rewLabel, "BOTTOMLEFT", 0, -12)
    d.mobs = S.Text(b, 12)
    d.mobs:SetPoint("TOPLEFT", d.mobLabel, "BOTTOMLEFT", 0, -4)
    d.mobs:SetPoint("RIGHT", b, "RIGHT")
    d.mobs:SetWordWrap(false)

    -- Right: the chain.
    local chain = S.Card(d, L.DETAIL_CHAIN, nil, "Interface\\Icons\\INV_Scroll_03")
    chain:SetPoint("TOPLEFT", info, "TOPRIGHT", S.GAP, 0)
    chain:SetPoint("BOTTOMRIGHT", foot, "TOPRIGHT", 0, S.GAP)
    d.chainCard = chain
    d.chain = S.List(chain.body, CHAIN_ROW, makeStep, fillStep)
    d.chain:SetPoint("TOPLEFT")
    d.chain:SetPoint("BOTTOMRIGHT", -10, 0)
    return d
end

local function whereLine(who, area)
    return ns.Where({ who = who or "", area = area or 0 })
end
local function spot(x, y)
    return (x and x > 0) and string.format("%.1f, %.1f", x, y) or ""
end

-- Fills the page of ns.openQuest.
function ns.FillDetail(level)
    local d = detail
    local q = ns.Quest(ns.openQuest, level)
    d.q = q
    if not q then ns.openQuest = nil return end
    local diff = ns.Difficulty(q.level, level)
    d.title:SetText("[" .. q.level .. "] " .. q.name)
    d.title:SetTextColor(unpack(ns.DiffColor(diff)))
    local sub = { L.FROM_LEVEL:format(q.minLevel > 0 and q.minLevel or 1) }
    if q.steps and q.steps > 1 then sub[#sub + 1] = L.STEP:format(q.step, q.steps) end
    sub[#sub + 1] = L[SIDE_TEXT[q.side] or "FACTION_BOTH"]
    d.sub:SetText(table.concat(sub, "  ·  "))
    local state = q.state == "later" and q.why == "WHY_LEVEL" and "later" or q.state
    d.state:Set(L["STATE_" .. (state == "hidden" and "TAKE" or state):upper()] or "", STATE_COLOR[state] or S.MUTED)
    d.side:SetShown(SIDE_ICON[q.side] ~= nil)
    if SIDE_ICON[q.side] then d.side:SetIcon(SIDE_ICON[q.side]) end

    local objs, last = q.objectives, nil
    for i, r in ipairs(d.objRows) do
        local o = objs[i]
        local shown = o ~= nil or (i == 1)
        r.state:SetShown(shown)
        r.count:SetShown(shown)
        r.text:SetShown(shown)
        if shown then
            o = o or { text = "-" }
            local have, need, what = o.text:match("^(%d+)%s*/%s*(%d+)%s+(.+)$")
            if not have then what, have, need = o.text:match("^(.-):%s*(%d+)%s*/%s*(%d+)$") end
            local done = o.done or (have and tonumber(have) >= tonumber(need))
            r.state:SetTexture(done and ICON_OK or WAIT_ICON)
            r.state:SetAlpha((done or have) and 1 or 0.5)
            r.count:SetWidth(have and 38 or 1)
            if have then
                r.count:SetText(have .. "/" .. need)
                r.count:SetTextColor(unpack(done and S.GOOD or S.WARN))
                r.text:SetText(what)
            else
                r.count:SetText("")
                r.text:SetText(o.text)
            end
            r.text:SetTextColor(unpack(done and S.MUTED or S.TEXT))
            -- Only the quest's own text (no counts) may run over a few lines.
            r.text:SetWordWrap(not have)
            local lines = 1
            if not have then
                local w = math.max(100, (d.infoBody:GetWidth() or 0) - 20)
                lines = math.min(4, math.max(1, math.ceil((r.text:GetStringWidth() or 0) * 1.15 / w)))
                r.text:SetMaxLines(lines)
            end
            r.text:SetHeight(lines * 15)
            last = r
        end
    end
    d.startLabel:ClearAllPoints()
    d.startLabel:SetPoint("TOP", last.text, "BOTTOM", 0, -10)
    d.startLabel:SetPoint("LEFT", d.objLabel, "LEFT")

    if q.area and q.area > 0 then
        d.start:SetText(whereLine(q.who, q.area))
    elseif q.who ~= "" then
        d.start:SetText(L.FROM_ITEM:format(q.who))
    else
        d.start:SetText(L.INSIDE)
    end
    d.startXY:SetText(q.area > 0 and spot(q.x, q.y) or "")
    d.startMap:SetEnabled(q.area > 0 and q.x > 0)
    local t = q.turnin
    d.turnin:SetText(t and whereLine(t.who, t.area) or "-")
    d.turninXY:SetText(t and spot(t.x, t.y) or "")
    d.turninMap:SetEnabled(t ~= nil and t.area > 0 and t.x > 0)

    local need
    for _, st in ipairs(q.chain) do if st.missing then need = st end end
    if need then
        d.need:SetText(L.REQUIRES:format(need.name))
    elseif q.state == "later" and q.why == "WHY_LEVEL" then
        d.need:SetText(L.WHY_LEVEL:format(q.minLevel))
    elseif q.state == "later" then
        d.need:SetText(ns.NeedText(q.need))
    else
        d.need:SetText("")
    end
    d.rewLabel:ClearAllPoints()
    d.rewLabel:SetPoint("TOP", d.need:GetText() ~= "" and d.need or d.turninMap, "BOTTOM", 0, -12)
    d.rewLabel:SetPoint("LEFT", d.objLabel, "LEFT")

    local rewards = ns.Rewards(q)
    local lastRew
    for i, row in ipairs(d.rewards) do
        local r = rewards[i]
        row:SetShown(r ~= nil)
        if r then
            lastRew = row
            row.id = r.id
            row.icon:SetIcon(r.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.icon:SetAlpha((r.name and not r.fits) and 0.35 or 1)
            S.SetBorder(row.icon, r.better and S.GOOD or S.BORDER)
            local name = r.name and (S.QualityHex(r.quality) .. r.name .. "|r") or ("#" .. r.id)
            local mark = r.better and ("  " .. S.Hex(S.GOOD) .. L.BETTER .. "|r")
                or (r.name and not r.fits and ("  " .. S.Hex(S.MUTED) .. L.NOT_FOR_YOU .. "|r")) or ""
            row.name:SetText(name .. mark)
        end
    end
    d.mobLabel:ClearAllPoints()
    d.mobLabel:SetPoint("TOP", lastRew or d.rewLabel, "BOTTOM", 0, -12)
    d.mobLabel:SetPoint("LEFT", d.objLabel, "LEFT")
    d.rewLabel:SetText(#rewards > 0 and L.DETAIL_REWARDS or "")
    d.mobLabel:SetText(q.targets and #q.targets > 0 and L.DETAIL_MOBS or "")
    d.mobs:SetText(q.targets and table.concat(q.targets, ", ") or "")

    d.chainCard:SetTitle(L.DETAIL_CHAIN, #q.chain > 0 and tostring(#q.chain) or "")
    d.chain:SetData(#q.chain > 0 and q.chain or { { n = 1, name = q.name, this = true, id = q.id, level = q.level,
                                                    who = q.who, area = q.area, x = q.x, y = q.y } })

    local at
    for i, id in ipairs(ns.listIds or {}) do if id == q.id then at = i end end
    d.prev:SetEnabled(at ~= nil and at > 1)
    d.next:SetEnabled(at ~= nil and at < #(ns.listIds or {}))
    local inLog = q.state == "log"
    fitIcon(d.track, inLog and ns.Tracked(q.id) and L.UNTRACK or L.TRACK)
    d.track:SetEnabled(inLog)
    d.share:SetEnabled(inLog)
    fitIcon(d.hide, ns.Hidden(q.id) and L.UNHIDE or L.HIDE)
    local others = inLog and ns.GroupOn(q.id) or {}
    d.status:SetText(#others > 0 and L.TT_GROUP:format(table.concat(others, ", ")) or "")
    if not d.note:HasFocus() then d.note:SetText(ns.Note("q" .. q.id)) end
end

local function buildSettings(parent)
    local page = CreateFrame("Frame", nil, parent)
    local sw = {}
    for _, o in ipairs({ { "warnEnter", L.OPT_ENTER, L.OPT_ENTER_D }, { "remind", L.OPT_REMIND, L.OPT_REMIND_D },
                         { "wishAlert", L.OPT_WISH, L.OPT_WISH_D }, { "learn", L.OPT_LEARN, L.OPT_LEARN_D },
                         { "keys", L.OPT_KEYS, L.OPT_KEYS_D }, { "tomtom", L.OPT_TOMTOM, L.OPT_TOMTOM_D },
                         { "hideLater", L.OPT_LATER, L.OPT_LATER_D } }) do
        local key = o[1]
        sw[#sw + 1] = { o[2], o[3], function() return ns.Get(key) end, function(v) ns.Set(key, v) end,
                        icon = ns.OPT_ICON[key] }
    end
    local card, h = S.SettingsCard(page, L.SET_SWITCHES, sw)
    settings = {}
    for i, row in ipairs(card.rows) do settings[#settings + 1] = { row = row, get = sw[i][3] } end
    card:SetPoint("TOPLEFT")
    card:SetPoint("TOPRIGHT")
    card:SetHeight(h)
    local note = S.Note(page, 11)
    note:SetPoint("TOPLEFT", card, "BOTTOMLEFT", S.INSET, -S.GAP)
    note:SetPoint("RIGHT", -S.INSET, 0)
    note:SetText(L.READY_MOVED)
    return page
end

local PAGES
local function showTab(i)
    for n, p in ipairs(PAGES) do p:SetShown(n == i) end
    search:SetShown(i ~= 4)
    ns.Refresh()
end

-- Opens a tab: 1 bosses, 2 loot, 3 quests, 4 settings.
function ns.ShowTab(i)
    ns.Window()
    tabs:Select(i)
end

local function buildBossPage(parent)
    local p = CreateFrame("Frame", nil, parent)
    bossPage = p
    p.empty = S.Empty(p)
    p.empty.title:SetText(L.NO_BOSSES)
    p.empty.sub:SetText(L.NO_BOSSES_D)

    local left = S.Card(p)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(190)
    p.left = left
    p.list = S.List(left.body, 38, makeBoss, fillBoss)
    p.list:SetPoint("TOPLEFT")
    p.list:SetPoint("BOTTOMRIGHT", -10, 0)

    local info = S.Card(p)
    info:SetPoint("TOPLEFT", left, "TOPRIGHT", S.GAP, 0)
    info:SetPoint("TOPRIGHT")
    info:Fit(168)
    p.info = info
    local b = info.body
    -- The boss's own model from the game; drag to turn it.
    local holder = CreateFrame("Frame", nil, b)
    holder:SetPoint("TOPLEFT")
    holder:SetSize(150, 168)
    S.Box(holder, S.INPUT, S.CARD_EDGE, S.R_MD)
    local m = CreateFrame("PlayerModel", nil, holder)
    m:SetPoint("TOPLEFT", 2, -2)
    m:SetPoint("BOTTOMRIGHT", -2, 2)
    m:EnableMouse(true)
    m:SetScript("OnMouseDown", function(self) self.dragX = GetCursorPosition and GetCursorPosition() end)
    m:SetScript("OnMouseUp", function(self) self.dragX = nil end)
    m:SetScript("OnUpdate", function(self)
        if not self.dragX or not GetCursorPosition then return end
        local x = GetCursorPosition()
        self.facing = (self.facing or 0) + (x - self.dragX) / 80
        self.dragX = x
        if self.SetFacing then self:SetFacing(self.facing) end
    end)
    m:SetScript("OnEnter", function(self)
        if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(L.MODEL_TT); GameTooltip:Show() end
    end)
    m:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    p.model = m
    p.name = S.Text(b, 15)
    p.name:SetPoint("TOPLEFT", holder, "TOPRIGHT", 14, -2)
    p.name:SetPoint("RIGHT", b, "RIGHT")
    p.name:SetWordWrap(false)
    p.sub = S.Text(b, 11, S.MUTED)
    p.sub:SetPoint("TOPLEFT", p.name, "BOTTOMLEFT", 0, -5)
    p.sub:SetPoint("RIGHT", b, "RIGHT")
    p.sub:SetWordWrap(false)
    p.kills = S.Text(b, 11, S.FAINT)
    p.kills:SetPoint("TOPLEFT", p.sub, "BOTTOMLEFT", 0, -4)
    p.kills:SetPoint("RIGHT", b, "RIGHT")
    p.kills:SetWordWrap(false)
    p.spellLabel = S.Text(b, 10, S.FAINT)
    p.spellLabel:SetPoint("TOPLEFT", p.kills, "BOTTOMLEFT", 0, -10)
    p.spellLabel:SetText(S.Upper(L.ABILITIES))
    p.spells = {}
    for i = 1, MAX_SPELLS do
        local ic = S.IconBox(b, 26)
        ic:SetPoint("TOPLEFT", p.spellLabel, "BOTTOMLEFT", (i - 1) * 32, -6)
        ic:EnableMouse(true)
        ic:SetScript("OnEnter", function(self)
            if not (GameTooltip and self.spell) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(self.spell.id) else GameTooltip:AddLine(self.spell.name) end
            GameTooltip:Show()
        end)
        ic:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        p.spells[i] = ic
    end
    p.note = S.Edit(b, 200, 28)
    p.note:SetPoint("BOTTOMLEFT", holder, "BOTTOMRIGHT", 14, 0)
    p.note:SetPoint("RIGHT", b, "RIGHT")
    p.note:SetJustifyH("LEFT")
    S.Placeholder(p.note, L.NOTE_HINT)
    p.note:HookScript("OnTextChanged", function(self, user)
        if user and p.noteKey then ns.SetNote(p.noteKey, self:GetText()) end
    end)
    p.note:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    local loot = S.Card(p, L.LOOT_OF, "", "Interface\\Icons\\INV_Misc_Bag_10")
    loot:SetPoint("TOPLEFT", info, "BOTTOMLEFT", 0, -S.GAP)
    loot:SetPoint("BOTTOMRIGHT")
    p.lootCard = loot
    p.loot = S.List(loot.body, 38, makeLoot, fillLoot)
    p.loot:SetPoint("TOPLEFT")
    p.loot:SetPoint("BOTTOMRIGHT", -10, 0)
    return p
end

local function buildLootPage(parent)
    local p = CreateFrame("Frame", nil, parent)
    lootPage = p
    p.filters = CreateFrame("Frame", nil, p)
    p.filters:SetPoint("TOPLEFT")
    p.filters:SetPoint("TOPRIGHT")
    p.filters:SetHeight(28)
    for _, f in ipairs(LOOT_FILTERS) do
        local b = S.Pill(p.filters, 96, 28)
        S.SetButtonIcon(b, f[3], 14)
        b:SetScript("OnClick", function() ns.lootFilter = f[1]; ns.Refresh() end)
        lootFilters[f[1]] = b
    end
    local card = S.Card(p)
    card:SetPoint("TOPLEFT", p.filters, "BOTTOMLEFT", 0, -S.GAP)
    card:SetPoint("BOTTOMRIGHT")
    p.list = S.List(card.body, 38, makeLoot, fillLoot)
    p.list:SetPoint("TOPLEFT")
    p.list:SetPoint("BOTTOMRIGHT", -10, 0)
    return p
end

local function buildQuestPage(parent)
    questPage = CreateFrame("Frame", nil, parent)
    -- The filters: every quest, to take, in the log, done; the guide on the right.
    filterRow = CreateFrame("Frame", nil, questPage)
    filterRow:SetHeight(28)
    filterRow:SetPoint("TOPLEFT")
    filterRow:SetPoint("TOPRIGHT")
    for _, f in ipairs(FILTERS) do
        local b = S.Pill(filterRow, 96, 28)
        S.SetButtonIcon(b, f[3], 14)
        b:SetScript("OnClick", function() ns.filter = f[1]; ns.Refresh() end)
        filters[f[1]] = b
    end
    guideBtn = iconButton(filterRow, ACT_ICON.track, 28)
    guideBtn:SetPoint("RIGHT")
    guideBtn:SetScript("OnClick", function()
        if ns.guide and ns.guide.key == ns.selected then ns.StopGuide() else ns.StartGuide(ns.selected) end
    end)
    guideBtn:HookScript("OnEnter", function(self)
        if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(L.GUIDE_TT, 1, 1, 1, true); GameTooltip:Show() end
    end)
    guideBtn:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    local right = S.Card(questPage)
    listCard = right
    right:SetPoint("TOPLEFT", filterRow, "BOTTOMLEFT", 0, -S.GAP)
    right:SetPoint("BOTTOMRIGHT")
    list = S.List(right.body, 40, makeRow, fillRow)
    list:SetPoint("TOPLEFT")
    list:SetPoint("BOTTOMRIGHT", -10, 0)

    detail = buildDetail(questPage)
    detail:SetAllPoints()
    detail:Hide()
    return questPage
end

local function build()
    frame = S.Window("GulliDungeonPrepFrame", L.TITLE, S.WIDE_W, S.DOCK_H)
    local body = frame.body
    local left = S.Card(body)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(210)
    dungeons = S.List(left.body, 30, makeDungeon, fillDungeon)
    dungeons:SetPoint("TOPLEFT")
    dungeons:SetPoint("BOTTOMRIGHT", -10, 0)

    local area = CreateFrame("Frame", nil, body)
    area:SetPoint("TOPLEFT", left, "TOPRIGHT", S.GAP, 0)
    area:SetPoint("BOTTOMRIGHT")
    tabs = S.PageTabs(area, { L.TAB_BOSSES, L.TAB_LOOT, L.TAB_QUESTS, L.TAB_SETTINGS }, nil, showTab, nil,
        { TI .. "INV_Misc_Head_Dragon_01", TI .. "INV_Misc_Bag_10", S.TAB.quests, S.TAB.settings })
    search = S.Edit(area, 140, 30)
    search:SetJustifyH("LEFT")
    S.Placeholder(search, L.SEARCH)
    search:SetPoint("TOPRIGHT")
    search:SetPoint("LEFT", tabs.frame, "RIGHT", 8, 0)
    search:HookScript("OnTextChanged", function() ns.Refresh() end)

    -- The dungeon's header, like the top of a dungeon journal page.
    head = S.Card(area)
    head:SetPoint("TOPLEFT", 0, -30 - S.GAP)
    head:SetPoint("TOPRIGHT", 0, -30 - S.GAP)
    head:Fit(40)
    head.icon = S.IconBox(head.body, 36)
    head.icon:SetPoint("LEFT")
    entranceBtn = iconButton(head.body, ACT_ICON.map)
    fitIcon(entranceBtn, L.PIN_ENTRANCE, 80)
    entranceBtn:SetPoint("RIGHT")
    entranceBtn:SetScript("OnClick", function()
        for _, d in ipairs(ns.Dungeons(ns.level or 1)) do
            if d.key == ns.selected and d.entrance then
                ns.SetPin({ who = ns.DungeonName(d), zone = C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(d.entrance.area),
                            x = d.entrance.x, y = d.entrance.y })
            end
        end
    end)
    head.range = S.Text(head.body, 12)
    head.name = S.Text(head.body, 14)
    head.name:SetPoint("TOPLEFT", head.icon, "TOPRIGHT", 10, -2)
    head.name:SetWordWrap(false)
    head.range:SetPoint("LEFT", head.name, "RIGHT", 8, 0)
    head.range:SetPoint("RIGHT", entranceBtn, "LEFT", -8, 0)
    head.range:SetJustifyH("LEFT")
    head.range:SetWordWrap(false)
    head.sub = S.Text(head.body, 11, S.MUTED)
    head.sub:SetPoint("TOPLEFT", head.name, "BOTTOMLEFT", 0, -5)
    head.sub:SetPoint("RIGHT", entranceBtn, "LEFT", -8, 0)
    head.sub:SetWordWrap(false)

    local function page(p, under)
        p:SetPoint("TOPLEFT", under or head, "BOTTOMLEFT", 0, -S.GAP)
        p:SetPoint("BOTTOMRIGHT")
        p:Hide()
        return p
    end
    PAGES = { page(buildBossPage(area)), page(buildLootPage(area)), page(buildQuestPage(area)),
              buildSettings(area) }
    PAGES[4]:SetPoint("TOPLEFT", 0, -30 - S.GAP)
    PAGES[4]:SetPoint("BOTTOMRIGHT")
    PAGES[4]:Hide()
    PAGES[1]:Show()
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
