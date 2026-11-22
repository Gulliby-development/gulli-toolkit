-- Dungeons on the left (icon, name, level range in the game's difficulty colours); on the
-- right the dungeon's header and its pages: Bosses (the bosses in the order a group meets them and
-- the rares under them, the boss's model, kills, abilities, note and loot), Loot (what the mobs
-- drop, what the bosses have for the class, the wishlist), Quests (in the log, the
-- stops of the way to take the rest with the entrance last, the ones that come later, and the
-- guide), and Settings.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, list, tabs, search, entranceBtn, settings, questPage, listCard
local detail, head, filterRow, guideBtn, mainSwitch, bossPage, lootPage
local grid, areaFrame, homeBtn
local EDGE_SHADE = 3 -- the height of one step of the shadow under the grid's title
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
                   hide = TI .. "Ability_Stealth", link = TI .. "INV_Misc_Book_09", later = TI .. "INV_Misc_PocketWatch_01" }
-- The list filters, each with its icon: every quest, the ones to take, the log, the done ones.
local FILTERS = { { "all", "F_ALL", S.TAB.list }, { "take", "F_TAKE", TI .. "INV_Misc_Note_01" },
                  { "log", "F_LOG", S.TAB.quests }, { "done", "F_DONE", TI .. "INV_Misc_Ribbon_01" } }
local WAIT_ICON = "Interface\\RaidFrame\\ReadyCheck-Waiting"

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
        f.close = S.Button(f, 28, 22)
        f.close:SetPoint("TOPRIGHT", -8, -6)
        f.close:SetText("x")
        local function close() f:Hide() end
        local function whole(self)
            if self.HighlightText then self:HighlightText() end
        end
        f.close:SetScript("OnClick", close)
        f.edit:SetScript("OnEscapePressed", close)
        f.edit:SetScript("OnEnterPressed", close)
        -- the link stays as it is, and stays selected, whatever the player types
        f.edit:HookScript("OnTextChanged", function(self, user)
            if user and f.url then self:SetText(f.url); whole(self) end
        end)
        f.edit:HookScript("OnMouseUp", whole)
        f.edit:HookScript("OnKeyDown", function(_, key)
            if key == "C" and IsControlKeyDown and IsControlKeyDown() then
                if C_Timer and C_Timer.After then C_Timer.After(0.15, close) else close() end
            end
        end)
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

-- A texture file that the client has: SetTexture answers false for a missing one.
local function setFile(t, path)
    if not path then return false end
    return t:SetTexture(path) ~= false
end

-- The dungeon's game icon. The dungeon finder's portraits (ns.Portraits) are missing from some
-- clients, and SetTexture does not say so: the ring stayed empty.
local function setPortrait(box, key)
    box:SetIcon(ns.Icon(key))
end

-- The journal banner, faded in from the left so the text keeps a dark ground.
-- The start page: every dungeon as a tile, three to a row, the ones for the player's level
-- first. A tile is the name in capitals, the dungeon picture (its loading screen) at full light, then the levels on
-- the left and the quests waiting there on the right. A click opens the dungeon's pages.
local GRID_COLS, TILE_H, TILE_NAME, TILE_FOOT = 3, 150, 30, 26

local function makeTile(parent)
    local t = CreateFrame("Frame", nil, parent)
    S.Box(t, S.SURFACE, S.CARD_EDGE, S.R_LG)
    t.name = S.Text(t, 14)
    t.name:SetPoint("TOPLEFT", 12, -9)
    t.name:SetPoint("RIGHT", -12, 0)
    t.name:SetJustifyH("LEFT")
    t.name:SetWordWrap(false)
    t.pic = CreateFrame("Frame", nil, t)
    t.pic:SetPoint("TOPLEFT", 6, -TILE_NAME)
    t.pic:SetPoint("BOTTOMRIGHT", -6, TILE_FOOT)
    S.Box(t.pic, S.SOLID, S.CARD_EDGE, S.R_MD)
    t.art = t.pic:CreateTexture(nil, "ARTWORK")
    t.art:SetPoint("TOPLEFT", 1, -1)
    t.art:SetPoint("BOTTOMRIGHT", -1, 1)
    S.RoundMask(t.pic, t.art, S.ROUND_SQ)
    -- A dungeon without a journal picture shows its portrait in the middle.
    t.icon = S.IconBox(t.pic, 52)
    t.icon:SetPoint("CENTER")
    t.range = S.Text(t, 12)
    t.range:SetPoint("BOTTOMLEFT", 12, 8)
    t.count = S.Text(t, 12)
    t.count:SetPoint("BOTTOMRIGHT", -12, 8)
    t.count:SetJustifyH("RIGHT")
    t.click = CreateFrame("Button", nil, t)
    t.click:SetAllPoints()
    t.click:SetScript("OnClick", function(self)
        local d = self:GetParent().d
        if not d then return end
        ns.selected, ns.openQuest, ns.home = d.key, nil, false
        ns.Refresh()
    end)
    -- What waits there.
    t.click:SetScript("OnEnter", function(self)
        local tile = self:GetParent()
        S.SetBorder(tile, S.Accent())
        local d = tile.d
        if not (GameTooltip and d) then return end
        local c = counts[d.key] or { log = 0, take = 0, done = 0 }
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(ns.DungeonName(d) .. "  " .. d.min .. "-" .. d.max, 1, 0.82, 0)
        GameTooltip:AddLine(L.TT_DUNGEON:format(c.log, c.take, c.done), 1, 1, 1)
        GameTooltip:Show()
    end)
    t.click:SetScript("OnLeave", function(self)
        S.SetBorder(self:GetParent(), S.CARD_EDGE)
        if GameTooltip then GameTooltip:Hide() end
    end)
    return t
end

local function fillTile(t, d)
    t.d = d
    if not d then t:Hide() return end
    t:Show()
    t.name:SetText(S.Upper(ns.DungeonName(d)))
    t.name:SetTextColor(unpack(d.fits and S.TEXT or S.MUTED))
    t.range:SetText(L.LEVEL:format(d.min .. "-" .. d.max))
    t.range:SetTextColor(unpack(ns.DiffColor(ns.DungeonDifficulty(d, ns.level or 1))))
    local w, h = t.art:GetWidth() or 0, t.art:GetHeight() or 0
    local art
    for _, b in ipairs(ns.Banners(d.key, (w > 0 and h > 0) and w / h or nil)) do
        if setFile(t.art, b[1]) then art = b; break end
    end
    t.art:SetShown(art ~= nil)
    t.icon:SetShown(art == nil)
    if art then t.art:SetTexCoord(unpack(art[2])) else setPortrait(t.icon, d.key) end
    local c = counts[d.key]
    local n = c and (c.log + c.take) or 0
    t.count:SetText(n > 0 and (S.IconTag(S.TAB.quests, 14) .. " " .. n) or "")
    t.count:SetTextColor(unpack((c and c.log > 0) and S.Accent() or S.GOOD))
end

local function makeGridRow(r)
    r.line:Hide()
    r.title = S.Text(r, 12, S.GOLD_DIM, nil, "bold")
    r.title:SetPoint("BOTTOMLEFT", 4, 4)
    r.title:SetPoint("RIGHT", -4, 0)
    r.title:SetJustifyH("LEFT")
    r.title:SetWordWrap(false)
    r.tiles = {}
    for i = 1, GRID_COLS do r.tiles[i] = makeTile(r) end
    r:SetScript("OnSizeChanged", function(self, w)
        local tw = ((w or 0) - (GRID_COLS - 1) * S.GAP) / GRID_COLS
        for i, t in ipairs(self.tiles) do
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", (i - 1) * (tw + S.GAP), 0)
            t:SetSize(math.max(tw, 1), TILE_H)
        end
    end)
end

local function fillGridRow(r, row)
    r.title:SetText(row.title and S.Upper(row.title) or "")
    local w = r:GetWidth()
    if not w or w <= 1 then w = (grid and grid.list and grid.list:GetWidth()) or 800 end
    r:GetScript("OnSizeChanged")(r, w)
    for i = 1, GRID_COLS do fillTile(r.tiles[i], row[i]) end
end

-- Dungeons for the player's level first, each part by level.
function ns.GridOrder(all)
    local list = {}
    for _, d in ipairs(all) do list[#list + 1] = d end
    table.sort(list, function(a, b)
        if (a.fits and 1 or 0) ~= (b.fits and 1 or 0) then return a.fits and true or false end
        if a.min ~= b.min then return a.min < b.min end
        return a.key < b.key
    end)
    return list
end

local function fillGrid(all)
    local rows, row, part = {}, nil, nil
    for _, d in ipairs(ns.GridOrder(all)) do
        if d.fits ~= part then
            part = d.fits
            rows[#rows + 1] = { title = part and L.GRID_FITS or L.GRID_OTHER }
            row = nil
        end
        if not row or #row == GRID_COLS then row = {}; rows[#rows + 1] = row end
        row[#row + 1] = d
    end
    grid.list:SetData(rows)
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
    local xpText = item.group ~= "done" and ns.XPText(q.id, ns.level)
    if xpText then GameTooltip:AddLine(xpText) end
    if item.group == "log" then
        local _, cash = ns.LogReward(q.id)
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
    if item.toggleSet then
        ns.showSet = not ns.showSet
        ns.Refresh()
        return
    end
    if item.stop then ns.SetPin(item.stop, true) return end
    local q = item.quest
    if not q then return end
    if button == "RightButton" then
        ns.SetHidden(q.id, not ns.Hidden(q.id))
        return
    end
    ns.OpenQuest(q.id)
end

-- A pin button targets and marks who it is for when they are near. Only a secure click may
-- target, so while the mouse is on a pin button out of combat one secure button lies over it:
-- its click runs /targetexact, then the pin button's own click. In combat it never shows, and
-- the pin button works alone. It never sets a raid mark: SetRaidTarget is forbidden to addons.
local overlay
local function buildOverlay()
    overlay = CreateFrame("Button", "GulliDungeonPrepTarget", UIParent, "SecureActionButtonTemplate")
    overlay:SetFrameStrata("TOOLTIP")
    overlay:RegisterForClicks("AnyUp", "AnyDown")
    overlay:SetAttribute("type", "macro")
    overlay:SetScript("PostClick", function(self, button, down)
        if down then return end
        local owner = self.owner
        local click = owner and owner:GetScript("OnClick")
        if click then click(owner, button) end
    end)
    overlay:SetScript("OnEnter", function(self) if self.tip then self.tip(self) end end)
    overlay:SetScript("OnLeave", function(self)
        if GameTooltip then GameTooltip:Hide() end
        if not (InCombatLockdown and InCombatLockdown()) then self:Hide() end
    end)
    overlay:SetScript("OnUpdate", function(self)
        if self.owner and not self.owner:IsVisible() and not (InCombatLockdown and InCombatLockdown()) then self:Hide() end
    end)
    overlay:SetScript("OnEvent", function(self) self:Hide() end)
    overlay:RegisterEvent("PLAYER_REGEN_DISABLED")
    overlay:Hide()
end

function ns.TargetOver(btn, who, tip)
    if not who or who == "" or who == "?" or (InCombatLockdown and InCombatLockdown()) then return false end
    if not overlay then buildOverlay() end
    local x, y = btn:GetCenter()
    if not x then return false end
    overlay:SetScale(btn:GetEffectiveScale() / UIParent:GetEffectiveScale())
    overlay:ClearAllPoints()
    overlay:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    overlay:SetSize(btn:GetWidth(), btn:GetHeight())
    overlay:SetAttribute("macrotext", "/targetexact " .. who)
    overlay.owner, overlay.who, overlay.tip = btn, who, tip
    overlay:Show()
    return true
end
function ns.TargetOverlay() return overlay end

-- Quests are cards: a status icon, the name, a status tag, the levels and the chain, and what
-- comes next (the earlier quest to do first, where to hand in). Headers and route stops stay short.
local HEAD_H, STOP_H, CARD_H, STEP_H, STEPS_MAX = 28, 40, 64, 16, 8
-- "Priest only" in the class colour, for a class quest (the list holds only the player's own).
function ns.ClassTag()
    local name, file = UnitClass("player")
    if not name then return "" end
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[file or ""]
    local text = L.CLASS_ONLY:format(name)
    return c and S.Hex({ c.r, c.g, c.b }) .. text .. "|r" or text
end

local STATUS = {
    log = { "Q_LOG", S.TAB.quests }, take = { "Q_TAKE", TI .. "INV_Misc_Note_01" },
    later = { "Q_LATER", ACT_ICON.later }, done = { "Q_DONE", TI .. "INV_Misc_Ribbon_01" },
    hidden = { "Q_HIDDEN", ACT_ICON.hide },
}
-- The steps of the quest's chain, under each other in its card (nil for a single quest).
function ns.CardSteps(item)
    if item.steps == nil then
        local chain = ns.Chain(item.quest.id)
        item.steps = #chain > 1 and chain or false
    end
    return item.steps or nil
end

local function rowHeight(item)
    if item.header then return HEAD_H end
    if item.stop then return STOP_H end
    local steps = ns.CardSteps(item)
    return CARD_H + (steps and (math.min(#steps, STEPS_MAX) * STEP_H + 4) or 0)
end

local STEP_ICON = { done = "Interface\\RaidFrame\\ReadyCheck-Ready", missing = "Interface\\RaidFrame\\ReadyCheck-NotReady",
                    active = "Interface\\RaidFrame\\ReadyCheck-Waiting" }

-- One line per step: its state, its number and name; this quest in the accent, the step to do
-- first in red. A longer chain ends in "+N" on the last line.
local function fillSteps(r, steps)
    for i = 1, STEPS_MAX do
        local line, st = r.steps[i], steps and steps[i]
        line:SetShown(st ~= nil)
        if st then
            local key = (st.done and "done") or (st.missing and "missing") or (st.active and "active")
            local mark = key and ("|T" .. STEP_ICON[key] .. ":12|t ") or "|cff666666·|r  "
            local text = mark .. st.n .. ".  " .. st.name
            if i == STEPS_MAX and #steps > STEPS_MAX then text = text .. "  |cff888888+" .. (#steps - STEPS_MAX) .. "|r" end
            line:SetText(text)
            local c = S.TEXT
            if st.this then c = S.Accent() elseif st.missing then c = S.BAD elseif st.done then c = S.MUTED end
            line:SetTextColor(unpack(c))
        end
    end
end

local function makeRow(r)
    r.num = S.Text(r, 12, S.Accent())
    r.num:SetPoint("LEFT", 10, 0)
    r.num:SetWidth(18)
    r.badge = S.IconBox(r, 30)
    r.badge:SetPoint("LEFT", 10, 0)
    r.tag = S.Text(r, 12)
    r.tag:SetPoint("TOPRIGHT", -10, -9)
    r.tag:SetJustifyH("RIGHT")
    r.tag:SetWordWrap(false)
    r.text = S.Text(r, 12)
    r.text:SetWordWrap(false)
    r.sub = S.Text(r, 12, S.MUTED)
    r.sub:SetPoint("TOPLEFT", r.text, "BOTTOMLEFT", 0, -3)
    r.sub:SetWordWrap(false)
    r.chain = S.Text(r, 12, S.FAINT)
    r.chain:SetPoint("TOPLEFT", r.sub, "BOTTOMLEFT", 0, -3)
    r.chain:SetWordWrap(false)
    r.steps = {}
    for i = 1, STEPS_MAX do
        local line = S.Text(r, 12)
        line:SetPoint("TOPLEFT", r.badge, "TOPRIGHT", 10, -(CARD_H - 12) - (i - 1) * STEP_H)
        line:SetPoint("RIGHT", -12, 0)
        line:SetJustifyH("LEFT")
        line:SetWordWrap(false)
        line:Hide()
        r.steps[i] = line
    end
    r.rewards = {}
    for i = 1, REWARD_ICONS do
        local ic = S.IconBox(r, 20)
        ic:SetPoint("BOTTOMRIGHT", -10 - (REWARD_ICONS - i) * 24, 8)
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

-- A plain row (a header or a route stop): no card, no badge, no tag.
local function plainRow(r)
    S.Fill(r, S.CLEAR)
    S.SetBorder(r, S.CLEAR)
    r.line:Show()
    r.badge:Hide()
    r.tag:SetText("")
    r.chain:SetText("")
    fillSteps(r, nil)
    r.sub:ClearAllPoints()
    r.sub:SetPoint("TOPLEFT", r.text, "BOTTOMLEFT", 0, -3)
    r.sub:SetPoint("RIGHT", r.text, "RIGHT")
end

local function fillRow(r, item)
    r.item = item
    r.text:ClearAllPoints()
    r.num:SetText("")
    setRewards(r, nil)
    if item.header then
        plainRow(r)
        r.text:SetPoint("LEFT", 10, 0)
        r.text:SetPoint("RIGHT", -8, 0)
        r.text:SetTextColor(unpack((item.toggleHidden or item.toggleSet) and S.Accent() or S.GOLD_DIM))
        r.text:SetText(S.Upper(item.text))
        r.sub:SetText("")
        return
    end
    local stop = item.stop
    if stop then
        plainRow(r)
        r.text:SetPoint("TOPLEFT", 32, -5)
        r.text:SetPoint("RIGHT", -8, 0)
        r.num:SetText(item.n)
        r.text:SetTextColor(unpack(stop.entrance and S.Accent() or S.TEXT))
        if stop.inside then
            r.text:ClearAllPoints()
            r.text:SetPoint("LEFT", 32, 0)
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
    -- A quest card.
    local q = item.quest
    local group = item.hidden and "hidden" or item.group
    local status = STATUS[group] or STATUS.take
    local faded = group == "later" or group == "hidden" or group == "done"
    S.Fill(r, S.RAISED)
    S.SetBorder(r, S.CARD_EDGE)
    r.line:Hide()
    local left = item.indent and 32 or 10
    r.badge:ClearAllPoints()
    r.badge:SetPoint("TOPLEFT", left, -10)
    r.badge:Show()
    r.badge:SetIcon(status[2])
    r.badge:SetAlpha(faded and 0.55 or 1)
    local tagColor = (group == "log" and S.Accent()) or (group == "take" and S.GOOD)
        or (group == "later" and S.WARN) or S.MUTED
    r.tag:SetText(S.Upper(L[status[1]]))
    r.tag:SetTextColor(unpack(tagColor))
    local icons = setRewards(r, q)
    r.text:SetPoint("TOPLEFT", r.badge, "TOPRIGHT", 10, 1)
    r.text:SetPoint("RIGHT", r.tag, "LEFT", -8, 0)
    local diff = ns.Difficulty(q.level, ns.level or 1)
    r.text:SetTextColor(unpack(faded and S.MUTED or S.TEXT))
    -- A chain is named by its last step in the dungeon; its steps under it show where it is.
    r.text:SetText(q.head and q.head.name or q.name)
    r.sub:ClearAllPoints()
    r.sub:SetPoint("TOPLEFT", r.text, "BOTTOMLEFT", 0, -4)
    r.sub:SetPoint("RIGHT", -12 - icons * 24, 0)
    r.chain:SetPoint("RIGHT", -12 - icons * 24, 0)
    for _, line in ipairs(r.steps) do line:SetPoint("RIGHT", -12 - icons * 24, 0) end
    -- The quest's level in its colour, the level it opens at, the step of its chain.
    local parts = { S.Hex(ns.DiffColor(diff)) .. L.LEVEL:format(q.level) .. "|r" }
    if q.minLevel and q.minLevel > 0 then parts[2] = L.FROM_LEVEL:format(q.minLevel) end
    if q.class then parts[#parts + 1] = ns.ClassTag() end
    if q.steps and q.steps > 1 then parts[#parts + 1] = L.STEP:format(q.step, q.steps) end
    if group ~= "done" then parts[#parts + 1] = ns.XPText(q.id, ns.level) end
    r.sub:SetText(table.concat(parts, "  ·  "))
    -- What comes next: the earlier quest first, where to hand in, how hard.
    local ahead = {}
    if group == "take" then
        ahead[1] = L["DIFF_" .. diff]
        -- Under a route stop the giver is the stop itself.
        local where = not item.indent and ns.Where(q) or ""
        if where ~= "" then ahead[2] = where end
    elseif group == "later" then
        ahead[1] = "» " .. (q.why == "WHY_LEVEL" and L.WHY_LEVEL:format(q.minLevel) or ns.NeedText(q.need))
    elseif group == "log" then
        if q.turnin and q.turnin.who ~= "" then ahead[1] = L.HAND_TO:format(q.turnin.who) end
        local others = ns.GroupOn(q.id)
        if #others > 0 then ahead[#ahead + 1] = L.ALSO:format(table.concat(others, ", ")) end
    end
    -- What it asks for now happens in the dungeon: the dungeon's icon and name first.
    local ins = (group == "take" or group == "log") and ns.selected and ns.Inside(ns.selected, q.id)
    if ins then
        local ready = C_QuestLog and C_QuestLog.IsComplete and C_QuestLog.IsComplete(q.id) == true
        local now = (group == "take" and ins.take) or (group == "log" and ((ready and ins.turnin) or (not ready and ins.work)))
        if now then
            table.insert(ahead, 1, S.IconTag(ns.Icon(ns.selected)) .. " " .. S.Hex(S.Accent())
                .. L.INSIDE_OF:format(ns.dungeonName or "") .. "|r")
        end
    end
    r.chain:SetTextColor(unpack(group == "later" and S.WARN or S.FAINT))
    r.chain:SetText(table.concat(ahead, "  ·  "))
    fillSteps(r, ns.CardSteps(item))
end

-- The dungeon's header: name, levels, bosses and quest counts, the keys, the entrance.
-- A plate in the dungeon's header: a text, with an icon before it or a thin bar after it.
local function headChip(parent)
    local c = CreateFrame("Frame", nil, parent)
    c:SetHeight(26)
    S.Box(c, S.RAISED, S.CARD_EDGE, S.R_MD)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetSize(14, 14)
    c.icon:SetPoint("LEFT", 8, 0)
    c.text = S.Text(c, 12, S.MUTED)
    c.text:SetWordWrap(false)
    c.bar = S.Progress(c, 4)
    c.bar:SetWidth(40)
    c.bar:SetPoint("RIGHT", -9, 0)
    function c:Set(text, icon, share)
        self.icon:SetShown(icon ~= nil)
        if icon then self.icon:SetTexture(icon) end
        self.text:ClearAllPoints()
        self.text:SetPoint("LEFT", icon and 28 or 9, 0)
        self.text:SetText(text)
        self.bar:SetShown(share ~= nil)
        if share then self.bar:Set(share, S.GOOD) end
        self:SetWidth(math.floor(self.text:GetStringWidth() or 0) + (icon and 28 or 9) + (share and 58 or 9))
        self:Show()
    end
    return c
end

-- The header's plates: the bosses killed, the quests done (with what is in the log and to
-- take while there is room) and each key, from the right edge leftwards.
local KEY_ICON = TI .. "INV_Misc_Key_03"
local function fillHead(current, level)
    local c = counts[ns.selected] or { log = 0, take = 0, later = 0, done = 0 }
    setPortrait(head.icon, ns.selected or "")
    head.name:SetText(current and ns.DungeonName(current) or "")
    head.range:SetText(current and (current.min .. "-" .. current.max) or "")
    if current then head.range:SetTextColor(unpack(ns.DiffColor(ns.DungeonDifficulty(current, level)))) end
    for _, chip in ipairs(head.chips) do chip:Hide() end
    local shown = {}
    local killed, bosses = ns.BossProgress(ns.selected)
    if bosses > 0 then
        head.chips[1]:Set(S.Emph(L.HEAD_BOSSES:format(killed, bosses)), nil, killed / bosses)
        shown[#shown + 1] = head.chips[1]
    end
    local total = c.log + c.take + c.later + c.done
    local quests = total > 0 and S.Emph(L.HEAD_QUESTS:format(c.done, total)) or nil
    if quests then
        local more = quests
        if c.log > 0 then more = more .. "  ·  " .. L.HEAD_LOG:format(c.log) end
        if c.take > 0 then more = more .. "  ·  " .. L.HEAD_TAKE:format(c.take) end
        head.chips[2]:Set(more)
        shown[#shown + 1] = head.chips[2]
    end
    if ns.Get("keys") then
        for i, k in ipairs(ns.KeyState(ns.selected)) do
            local chip = head.chips[2 + i]
            if chip then
                chip:Set(S.Hex(k.have and S.GOOD or S.BAD) .. (k.have and k.name or L.CHECK_NO_KEY:format(k.name)) .. "|r",
                         k.have and ICON_OK or KEY_ICON)
                shown[#shown + 1] = chip
            end
        end
    end
    -- What does not fit beside the name goes: first the quest plate's extras, then the plate.
    local function width()
        local w = 0
        for _, chip in ipairs(shown) do w = w + chip:GetWidth() + 6 end
        return w
    end
    local room = (tonumber(head.body:GetWidth()) or 0)
    if room > 1 then
        room = room - 46 - (head.name:GetStringWidth() or 0) - 8 - (head.range:GetStringWidth() or 0) - 14
               - entranceBtn:GetWidth() - 8
        if quests and width() > room then head.chips[2]:Set(quests) end
        if quests and width() > room then
            head.chips[2]:Hide()
            for i, chip in ipairs(shown) do if chip == head.chips[2] then table.remove(shown, i) break end end
        end
    end
    local at = entranceBtn
    for i = #shown, 1, -1 do
        shown[i]:ClearAllPoints()
        shown[i]:SetPoint("RIGHT", at, "LEFT", at == entranceBtn and -8 or -6, 0)
        at = shown[i]
    end
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
        -- The tier 0.5 set chain, only at the top level and folded until clicked.
        local set = q.set
        local n = set and (#set.log + #set.take + #set.later) or 0
        if n > 0 then
            add({ header = true, toggleSet = true, text = (ns.showSet and L.SET_OPEN or L.SET_N):format(n) })
            if ns.showSet then
                for _, g in ipairs({ "log", "take", "later" }) do
                    for _, x in ipairs(set[g]) do add({ quest = x, group = g }) end
                end
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
    ns.listItems = items
    ns.dungeonName = current and ns.DungeonName(current) or ""
    ns.takeCount = #q.take
    return items
end

-- Bosses and loot -----------------------------------------------------------------------------

local MAX_SPELLS = 6
local OWN_PIPS = 10
local LOOT_ROW, HEAD_ROW = 38, 26
-- A boss's loot card holds this many rows of this height.
local BOSS_LOOT, BOSS_LOOT_ROW = 5, 36
local STAR = "PetJournal-FavoritesIcon"
local WISH_ICON = "Interface\\Icons\\INV_Misc_Gem_Pearl_04"
local EMPTY_PIP = { 1, 0.93, 0.78, 0.13 }
local LOOT_FILTERS = { { "mobs", "F_MOBS", TI .. "INV_Misc_Bone_01" }, { "mine", "F_MINE", TI .. "INV_Chest_Chain_05" },
                       { "wish", "F_WISH", WISH_ICON } }

-- A plain coloured texture of a frame.
local function plain(f, layer, c)
    local t = f:CreateTexture(nil, layer or "ARTWORK")
    t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    return t
end
local function paint(t, c) t:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end

-- The wishlist mark: the game's star where the client has it, else the pearl.
local function setStar(t)
    local has = C_Texture and C_Texture.GetAtlasInfo and t.SetAtlas and C_Texture.GetAtlasInfo(STAR)
    if has then t:SetAtlas(STAR) else t:SetTexture(WISH_ICON) end
end

-- An item's tooltip beside a row, with what is worn in that slot: the item pointed at always on
-- the left, the worn one (the game's "Equipped") to its right. The game picks the side by the
-- room on the screen, so the worn item could stand first and read as the one pointed at.
local function placeCompare()
    local tip = GameTooltip
    local owner = tip and tip.GetOwner and tip:GetOwner()
    if type(owner) ~= "table" or not rawget(owner, "gulliCompare") then return end
    local a, b = ShoppingTooltip1, ShoppingTooltip2
    a = a and a:IsShown() and a or nil
    b = a and b and b:IsShown() and b or nil
    local function num(v) return tonumber(v) or 0 end
    local worn = (a and num(a:GetWidth()) or 0) + (b and num(b:GetWidth()) or 0)
    local scale = num(tip.GetEffectiveScale and tip:GetEffectiveScale())
    local oscale = num(owner.GetEffectiveScale and owner:GetEffectiveScale())
    local screen = num(UIParent and UIParent.GetRight and UIParent:GetRight())
        * num(UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale())
    local right = num(owner.GetRight and owner:GetRight()) * oscale + (num(tip:GetWidth()) + worn + 4) * scale
    tip:ClearAllPoints()
    if screen > 0 and right > screen then
        -- no room to the right of the row: both stand to its left, in the same order
        tip:SetPoint("TOPRIGHT", owner, "TOPLEFT", -(worn + 4), 0)
    else
        tip:SetPoint("TOPLEFT", owner, "TOPRIGHT", 4, 0)
    end
    if a then
        a:ClearAllPoints()
        a:SetPoint("TOPLEFT", tip, "TOPRIGHT", 0, 0)
    end
    if b then
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", a, "TOPRIGHT", 0, 0)
    end
end
local compareHooked
-- Open the tooltip of an item for a row; ns.ItemTip for the tests.
local function itemTip(owner, id)
    if not (GameTooltip and id) then return false end
    rawset(owner, "gulliCompare", true)
    GameTooltip:SetOwner(owner, "ANCHOR_NONE")
    if GameTooltip.SetItemByID then GameTooltip:SetItemByID(id) end
    return true
end
-- Show it, with the worn item beside it. The game lays the two out again when Shift goes down
-- or up, so the order is set after each of its own passes too.
local function showItemTip()
    GameTooltip:Show()
    if not compareHooked and hooksecurefunc and GameTooltip_ShowCompareItem then
        compareHooked = true
        hooksecurefunc("GameTooltip_ShowCompareItem", placeCompare)
    end
    if GameTooltip_ShowCompareItem then pcall(GameTooltip_ShowCompareItem, GameTooltip) end
    placeCompare()
end
function ns.ItemTip(owner, id)
    if itemTip(owner, id) then showItemTip() end
end

-- The hover card of a loot line: the game's item tooltip, then where and how often it drops.
local function lootTooltip(owner, l)
    if not (l and itemTip(owner, l.item)) then return end
    GameTooltip:AddLine(" ")
    if l.zone then
        GameTooltip:AddLine(L.ZONE_DROP, 1, 0.82, 0)
    else
        local chance = l.pct > 0 and (L.CHANCE:format(l.pct) .. (l.own and ("  " .. L.CHANCE_OWN) or ""))
            or (l.seen and L.SEEN or L.CHANCE_NONE)
        GameTooltip:AddLine(l.boss .. ":  " .. chance, 1, 0.82, 0)
    end
    GameTooltip:AddLine(l.wish and L.WISH_REMOVE or L.WISH_ADD, 0.7, 0.7, 0.7)
    showItemTip()
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

local BAR_W = 44
local function makeLoot(r)
    r.head = S.Text(r, 12, S.MUTED, nil, "bold")
    r.head:SetPoint("BOTTOMLEFT", 6, 5)
    r.head:SetPoint("RIGHT", -6, 0)
    r.head:SetWordWrap(false)
    r.icon = S.IconBox(r, 24)
    r.icon:SetPoint("LEFT", 6, 0)
    r.wish = CreateFrame("Button", nil, r)
    r.wish:SetSize(22, 22)
    r.wish:SetPoint("RIGHT", -6, 0)
    r.wish.tex = r.wish:CreateTexture(nil, "ARTWORK")
    r.wish.tex:SetPoint("CENTER")
    r.wish.tex:SetSize(18, 18)
    setStar(r.wish.tex)
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
    -- The chance: the number, and a thin bar under it filled by that share.
    r.pct = S.Text(r, 12, nil, nil, "bold")
    r.pct:SetPoint("RIGHT", r.wish, "LEFT", -10, 4)
    r.pct:SetJustifyH("RIGHT")
    r.pct:SetWordWrap(false)
    r.track = plain(r, "ARTWORK", EMPTY_PIP)
    r.track:SetSize(BAR_W, 3)
    r.track:SetPoint("TOPRIGHT", r.pct, "BOTTOMRIGHT", 0, -3)
    r.fill = plain(r, "OVERLAY", S.Accent())
    r.fill:SetHeight(3)
    r.fill:SetPoint("LEFT", r.track, "LEFT")
    r.name = S.Text(r, 12)
    r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, 1)
    r.name:SetPoint("RIGHT", r.pct, "LEFT", -8, 0)
    r.name:SetWordWrap(false)
    r.sub = S.Text(r, 12, S.MUTED)
    r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
    r.sub:SetPoint("RIGHT", r.pct, "LEFT", -8, 0)
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

-- A chance under this is told quietly: the eye finds what really drops.
local LOW_PCT = 15

local function fillLoot(r, item)
    local header = item.header == true
    r.head:SetShown(header)
    r.icon:SetShown(not header); r.wish:SetShown(not header); r.click:SetShown(not header)
    r.name:SetShown(not header); r.sub:SetShown(not header); r.pct:SetShown(not header)
    r.line:SetShown(not header)
    if header then
        r.loot = nil
        r.track:Hide(); r.fill:Hide()
        r.head:SetText(item.text)
        return
    end
    local l = item.loot
    r.loot = l
    local mine = l.fits ~= false
    r.icon:SetIcon(l.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    r.icon:SetAlpha(mine and 1 or 0.4)
    S.SetBorder(r.icon, l.better and S.GOOD or S.BORDER)
    r.name:SetText((S.QualityHex(l.quality or 1)) .. (l.name or ("item:" .. l.item)) .. "|r")
    r.name:SetAlpha(mine and 1 or 0.55)
    r.sub:SetAlpha(mine and 1 or 0.7)
    local sub = {}
    local slot = slotText(l)
    if slot ~= "" then sub[#sub + 1] = slot end
    if l.zone then sub[#sub + 1] = L.ZONE_DROP end
    if l.better then sub[#sub + 1] = S.Hex(S.GOOD) .. L.BETTER .. "|r"
    elseif not mine then sub[#sub + 1] = L.NOT_FOR_YOU end
    if l.seen then sub[#sub + 1] = S.Hex(S.Accent()) .. L.SEEN .. "|r" end
    r.sub:SetText(table.concat(sub, "  ·  "))
    local bar = not l.zone and l.pct > 0
    r.track:SetShown(bar); r.fill:SetShown(bar)
    r.pct:ClearAllPoints()
    r.pct:SetPoint("RIGHT", r.wish, "LEFT", -10, bar and 4 or 0)
    if bar then
        local c = l.own and S.TEXT or (l.pct < LOW_PCT and S.FAINT or S.Accent())
        r.pct:SetText(L.CHANCE:format(l.pct))
        r.pct:SetTextColor(unpack(c))
        paint(r.fill, c)
        r.fill:SetWidth(math.max(2, BAR_W * math.min(l.pct, 100) / 100))
    else
        r.pct:SetText(l.zone and L.RARE_DROP or "-")
        r.pct:SetTextColor(unpack(S.FAINT))
    end
    r.wish.tex:SetDesaturated(not l.wish)
    r.wish:SetAlpha(l.wish and 1 or 0.45)
end
local function lootHeight(item) return item.header and HEAD_ROW or LOOT_ROW end

local function makeBoss(r)
    S.NavRow(r)
    r.line:Hide()
    -- A header of the list: the bosses, a wing, the rares.
    r.head = S.Text(r, 12, S.GOLD_DIM, nil, "bold")
    r.head:SetPoint("BOTTOMLEFT", 6, 5)
    r.head:SetWordWrap(false)
    r.note = S.Text(r, 12, S.FAINT)
    r.note:SetPoint("BOTTOMRIGHT", -6, 5)
    r.note:SetJustifyH("RIGHT")
    r.note:SetWordWrap(false)
    -- The boss's picture in a round ring: the journal's, else its portrait, else its number.
    r.pic = S.IconBox(r, 28)
    r.pic:SetPoint("LEFT", 6, 0)
    r.num = S.Text(r, 13, S.Accent(), nil, "bold")
    r.num:SetPoint("CENTER", r.pic, "CENTER", 0, 0)
    r.num:SetJustifyH("CENTER")
    -- Killed by the player: a green ring and a check on the picture's corner.
    local over = CreateFrame("Frame", nil, r.pic)
    over:SetAllPoints()
    r.done = over:CreateTexture(nil, "OVERLAY")
    r.done:SetSize(15, 15)
    r.done:SetPoint("BOTTOMRIGHT", r.pic, "BOTTOMRIGHT", 6, -5)
    r.done:SetTexture(ICON_OK)
    r.name = S.Text(r, 12)
    r.name:SetPoint("TOPLEFT", 44, -4)
    r.name:SetPoint("RIGHT", -6, 0)
    r.name:SetWordWrap(false)
    r.sub = S.Text(r, 12, S.FAINT)
    r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
    r.sub:SetPoint("RIGHT", -6, 0)
    r.sub:SetWordWrap(false)
    r.click = CreateFrame("Button", nil, r)
    r.click:SetAllPoints()
    r.click:SetScript("OnClick", function(self)
        local b = self:GetParent().b
        if not b then return end
        ns.boss = b.npc
        ns.modelBoss = ns.boss
        ns.Refresh()
    end)
end

-- A boss's level, "??" for a skull boss (the data has 0), and its colour against the player's
-- level, as the game colours a mob (a skull is always red).
local function bossLevel(b)
    if b.min <= 0 then return "??" end
    return b.min == b.max and tostring(b.min) or (b.min .. "-" .. b.max)
end
local function bossColor(b)
    if b.min <= 0 then return S.BAD end
    return ns.DiffColor(ns.Difficulty(b.max, ns.level or 1))
end

local function fillBoss(r, item)
    local b = item.b
    r.b = b
    local header = b == nil
    r.head:SetShown(header); r.note:SetShown(header)
    r.pic:SetShown(not header); r.num:SetShown(not header); r.name:SetShown(not header)
    r.sub:SetShown(not header); r.click:SetShown(not header)
    if header then
        r.done:Hide()
        r.head:SetText(S.Upper(item.text))
        r.head:SetTextColor(unpack(item.rare and S.WARN or S.GOLD_DIM))
        r.note:SetText(item.note or "")
        r:SetSelected(false)
        return
    end
    local icon = ns.selected and ns.BossIcon(ns.selected, b)
    local portrait = not icon and b.display > 0 and SetPortraitTextureFromCreatureDisplayID
    if icon then
        r.pic.tex:SetTexture(icon)
    elseif portrait then
        r.pic.tex:SetTexture(nil)
        portrait(r.pic.tex, b.display)
    else
        r.pic.tex:SetTexture(nil)
    end
    local killed = b.kills > 0
    r.pic:SetGlow(b.rare and S.WARN or (killed and S.GOOD or S.RING))
    r.done:SetShown(killed)
    r.num:SetText((icon or portrait) and "" or (b.rare and "R" or tostring(b.n)))
    r.num:SetTextColor(unpack(b.rare and S.WARN or S.Accent()))
    r.name:SetText(b.name)
    -- The level on its own line, so the name keeps the row's width.
    local sub = S.Hex(bossColor(b)) .. bossLevel(b) .. "|r"
    if killed then sub = sub .. "  ·  " .. S.Hex(S.GOOD) .. "×" .. b.kills .. "|r" end
    r.sub:SetText(sub)
    r:SetSelected(b.npc == ns.boss)
end
local function bossHeight(item) return item.b and LOOT_ROW or HEAD_ROW end

-- The rows of the boss list: the bosses under one header, or under their wings, in the order a
-- group meets them; the rares under their own header at the end.
local function bossItems(list)
    local items, wings, wing, rares = {}, false, nil, false
    for _, b in ipairs(list) do if not b.rare and b.wing ~= "" then wings = true end end
    for _, b in ipairs(list) do
        if b.rare then
            if not rares then
                rares = true
                items[#items + 1] = { header = true, rare = true, text = L.RARE, note = L.RARE_NOTE }
            end
        elseif wings then
            if b.wing ~= wing then
                wing = b.wing
                items[#items + 1] = { header = true, text = wing ~= "" and (L["WING_" .. wing] or wing) or L.TAB_BOSSES }
            end
        elseif #items == 0 then
            local walk = ns.Data and ns.Data.walk and ns.Data.walk[ns.selected]
            items[1] = { header = true, text = L.TAB_BOSSES, note = walk and L.IN_ORDER or nil }
        end
        items[#items + 1] = { b = b }
    end
    return items
end
ns.BossItems = bossItems

-- The model of the boss shown: at once after a click on it, a moment later for the boss the
-- page opened on, so the window shows before the game loads the model (a load stalls it).
local modelWait
local function wantModel(b)
    if b.display <= 0 then return 0 end
    if ns.modelBoss == b.npc then return b.display end
    if not modelWait then
        modelWait = true
        local function load()
            modelWait = nil
            if ns.boss and frame and frame:IsShown() and tabs.selected == 1 and not ns.home then
                ns.modelBoss = ns.boss
                ns.Refresh()
            end
        end
        if C_Timer and C_Timer.After then C_Timer.After(0.2, load) else load() end
    end
    return ns.modelBoss == b.npc and b.display or 0
end

-- The note of a boss: a quiet line until the player writes one, then the edit box.
local function showNote(p, b)
    local text = ns.Note("n" .. b.npc)
    local open = text ~= "" or p.noteOpen == b.npc or p.note:HasFocus()
    p.note:SetShown(open)
    p.noteBtn:SetShown(not open)
    if not p.note:HasFocus() then p.note:SetText(text) end
    p.noteKey = "n" .. b.npc
end

-- The boss page: the model, name, kills, abilities and note on top, the loot under it.
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
    bossPage.list:SetData(bossItems(list))
    local p = bossPage
    local want = wantModel(b)
    if p.model.SetDisplayInfo and p.model.shown ~= want then
        p.model.shown = want
        if p.model.ClearModel then p.model:ClearModel() end
        if want > 0 then
            p.model:SetDisplayInfo(want)
            if p.model.SetFacing then p.model:SetFacing(0) end
        end
    end
    p.name:SetText(b.name)
    p.name:SetTextColor(unpack(b.rare and S.WARN or S.TEXT))
    local parts = { S.Hex(bossColor(b)) .. L.LEVEL:format(bossLevel(b)) .. "|r" }
    if b.tag ~= "" then parts[#parts + 1] = b.tag end
    if b.rare then parts[#parts + 1] = L.RARE
    elseif b.of then parts[#parts + 1] = L.BOSS_N:format(b.n, b.of) end
    p.sub:SetText(table.concat(parts, "  ·  "))
    -- Kills: the count, and how far the player's own drop chances are (ns.OWN_AFTER kills).
    local killed = b.kills > 0
    p.kills:SetText(killed and (S.Hex(S.GOOD) .. L.KILLS:format(b.kills) .. "|r") or L.NO_KILLS)
    local got = math.min(b.kills, ns.OWN_AFTER)
    for i, pip in ipairs(p.pips) do paint(pip, i <= got * OWN_PIPS / ns.OWN_AFTER and S.GOOD or EMPTY_PIP) end
    p.own:SetText(got .. "/" .. ns.OWN_AFTER)
    p.pipBox.kills = b.kills
    for i, row in ipairs(p.spells) do
        local s = b.spells[i]
        row:SetShown(s ~= nil)
        row.spell = s
        if s then
            row.icon:SetIcon(s.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.name:SetText(s.name)
        end
    end
    showNote(p, b)
    p.lootCard:SetTitle(L.LOOT_OF, tostring(#b.loot))
    local items = {}
    for _, l in ipairs(b.loot) do items[#items + 1] = { loot = l } end
    if #items == 0 then items[1] = { header = true, text = L.NO_LOOT } end
    p.loot:SetData(items)
end

-- The Loot page: what the ordinary mobs drop, what the bosses have for this class and the
-- wishlist; the last two boss by boss in their order.
local function fillLootPage()
    local text = search:GetText()
    local lists = {}
    for _, f in ipairs(LOOT_FILTERS) do lists[f[1]] = ns.Loot(ns.selected, f[1], text) end
    -- Opens on the mobs' loot; a dungeon without any opens on the class's.
    local filter = ns.lootFilter or (#lists.mobs > 0 and "mobs" or "mine")
    local x = 0
    for _, f in ipairs(LOOT_FILTERS) do
        local b = lootFilters[f[1]]
        b:SetText(L[f[2]]:format(#lists[f[1]]))
        b:SetWidth(math.floor((b.text:GetStringWidth() or 0) + 44))
        b:ClearAllPoints()
        b:SetPoint("LEFT", lootPage.filters, "LEFT", x, 0)
        x = x + b:GetWidth() + 6
        b:SetSelected(filter == f[1])
    end
    local items, group = {}, nil
    for _, l in ipairs(lists[filter]) do
        local g = l.zone and "mobs" or l.npc
        if filter ~= "mobs" and g ~= group then
            group = g
            local head = l.zone and L.MOBS or (l.rare and (L.RARE .. "  ·  " .. l.boss)) or (l.bossN .. "  ·  " .. l.boss)
            items[#items + 1] = { header = true, text = head }
        end
        items[#items + 1] = { loot = l }
    end
    if #items == 0 then
        local none = #((ns.Data and ns.Data.boss and ns.Data.boss[ns.selected]) or {}) == 0 and L.NO_BOSSES
        items[1] = { header = true, text = none or (filter == "wish" and L.NO_WISH) or (filter == "mobs" and L.NO_MOB_LOOT) or L.NO_LOOT }
    end
    lootPage.list:SetData(items)
end

function ns.Refresh()
    if not frame or not frame:IsShown() then return end
    local level = UnitLevel("player") or 1
    ns.level = level
    if ns.home == nil then
        local here = ns.CurrentDungeon and ns.CurrentDungeon()
        ns.home = here == nil
        if here then ns.selected = here.key end
    end
    if not ns.selected then
        local s = ns.Suggest(level)
        ns.selected = s and s.key
    end
    local all = ns.Dungeons(level)
    for _, d in ipairs(all) do counts[d.key] = ns.Counts(d.key, level) end
    grid:SetShown(ns.home)
    areaFrame:SetShown(not ns.home)
    if ns.home then return fillGrid(all) end
    local current
    for _, d in ipairs(all) do if d.key == ns.selected then current = d end end
    -- The bosses and their loot only for the pages that show them (big dungeons have hundreds of items).
    bossCache = tabs.selected == 1 and ns.Bosses(ns.selected) or {}
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
    mainSwitch:SetShown(ns.MainSet(ns.selected) ~= nil)
    mainSwitch:ClearAllPoints()
    mainSwitch:SetPoint("LEFT", filterRow, "LEFT", x + 6, 0)
    mainSwitch:SetChecked(ns.Get("mainOnly"))
    local guiding = ns.guide ~= nil and ns.guide.key == ns.selected
    fitIcon(guideBtn, guiding and L.GUIDE_STOP or L.GUIDE, 90)
    -- Something to lead to: a quest to take, or one in the log (who takes it back, the entrance).
    guideBtn:SetEnabled(guiding or c.take > 0 or c.log > 0)
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
local REWARD_MAX, CHAIN_ROW, REWARD_ROW = 4, 40, 26
-- A stage of the quest's way: its round icon, and the least height of one.
local STAGE_ICON, STAGE_MIN = 30, 72
-- The way's parts: a tip box, an objective row (with its bar), a boss row, the summary strip.
local TIP_ICON, TIP_LINE, OBJ_ROW, BOSS_ROW, BOSS_MAX = "Interface\\FriendsFrame\\InformationIcon", 15, 32, 42, 2
local LABEL_Y = 4 -- a stage's label below its top, so its Done/Now tag is not cut
-- A row of the page's list of the dungeon's other quests, and the game's quest mark per group.
local OTHER_ROW = 26
local OTHER_MARK = { log = "Interface\\GossipFrame\\IncompleteQuestIcon", take = "Interface\\GossipFrame\\AvailableQuestIcon",
                     later = "Interface\\GossipFrame\\AvailableQuestIcon", hidden = "Interface\\GossipFrame\\AvailableQuestIcon",
                     done = "Interface\\RaidFrame\\ReadyCheck-Ready" }
local STAGE_ICONS = { take = TI .. "INV_Misc_Note_01", turnin = TI .. "INV_Misc_Ribbon_01" }
local SIDE_TEXT = { A = "FACTION_A", H = "FACTION_H" }
local SIDE_ICON = { A = "Interface\\Icons\\INV_BannerPVP_02", H = "Interface\\Icons\\INV_BannerPVP_01" }
local STATE_COLOR = { log = S.Accent and S.Accent() or S.TEXT, take = S.GOOD, done = S.MUTED, later = S.WARN,
                      closed = S.MUTED, hidden = S.MUTED }

-- `from` is the dungeon quest whose chain a step outside the dungeon was opened from.
function ns.OpenQuest(id, from)
    ns.openQuest, ns.openFrom = id, from
    ns.Refresh()
end

local function label(parent, text)
    local t = S.Text(parent, 12, S.FAINT)
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
    r.sub = S.Text(r, 12, S.MUTED)
    r.sub:SetPoint("TOPLEFT", r.text, "BOTTOMLEFT", 0, -3)
    r.sub:SetPoint("RIGHT", -6, 0)
    r.sub:SetWordWrap(false)
    r.click = CreateFrame("Button", nil, r)
    r.click:SetAllPoints()
    r.click.row = r
    r.click:SetScript("OnClick", function(self)
        local st = self.row.step
        if not st then return end
        -- A step opens its own page; the map is only on the page's Show on map.
        if st.this then return end
        local shown = detail and detail.q
        ns.OpenQuest(st.id, shown and (shown.from or shown.id))
    end)
    r.click:SetScript("OnEnter", function(self)
        local st = self.row.step
        if not (GameTooltip and st) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("[" .. (st.level or "?") .. "] " .. st.name, 1, 0.82, 0)
        local where = ns.Where({ who = st.who or "", area = st.area or 0 })
        if where ~= "" then GameTooltip:AddLine(L.TT_FROM:format(where), 1, 1, 1) end
        if not st.this then GameTooltip:AddLine(L.TT_CLICK_OPEN, 0.6, 0.6, 0.6) end
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
    d.topCard = top
    -- Back to the list: a gold button with its words, so it is found at once.
    d.back = S.Return(S.FitButton(top.body, "« " .. L.BACK, 30, 72))
    d.back:SetPoint("LEFT")
    d.back:SetScript("OnClick", function() ns.openQuest = nil; ns.Refresh() end)
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
    d.sub = S.Text(top.body, 12, S.MUTED)
    d.sub:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -4)
    d.sub:SetPoint("RIGHT", top.body, "RIGHT")
    d.sub:SetWordWrap(false)

    -- Footer: the actions.
    local foot = CreateFrame("Frame", nil, d)
    foot:SetPoint("BOTTOMLEFT")
    foot:SetPoint("BOTTOMRIGHT")
    foot:SetHeight(30)
    d.foot = foot
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
    d.link = iconButton(foot, ACT_ICON.link)
    fitIcon(d.link, L.WOWHEAD)
    d.link:SetPoint("LEFT", d.hide, "RIGHT", 8, 0)
    d.link:SetScript("OnClick", function()
        local q = detail and detail.q
        if q then ns.ShowLink(ns.WowheadURL("quest", q.id), q.name) end
    end)
    d.note = S.Edit(foot, 220, 28)
    d.note:SetPoint("RIGHT")
    d.note:SetJustifyH("LEFT")
    S.Placeholder(d.note, L.NOTE_QUEST)
    d.note:HookScript("OnTextChanged", function(self, user)
        if user and ns.openQuest then ns.SetNote("q" .. ns.openQuest, self:GetText()) end
    end)
    d.note:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    d.status = S.Text(foot, 12, S.MUTED)
    d.status:SetPoint("LEFT", d.link, "RIGHT", 12, 0)
    d.status:SetPoint("RIGHT", d.note, "LEFT", -8, 0)
    d.status:SetWordWrap(false)

    -- Left: the quest's way as three stages under each other, joined by a rail: taking it,
    -- its work (the objectives, inside the dungeon or not), handing it in. Each stage says
    -- whether it is done or the one to do now.
    local info = S.Card(d)
    info:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -S.GAP)
    info:SetPoint("BOTTOMLEFT", foot, "TOPLEFT", 0, S.GAP)
    d.infoCard = info
    -- A long objective and many objectives outgrow the card: its body scrolls.
    d.infoPage = S.ScrollPage(info.body, 380)
    d.infoPage:SetAllPoints()
    local b = d.infoPage.inner
    d.infoBody = b
    local TEXT_X = STAGE_ICON + 14
    local function stage(kind, title)
        local s = CreateFrame("Frame", nil, b)
        s:SetPoint("LEFT", b, "LEFT")
        s:SetPoint("RIGHT", b, "RIGHT")
        s.kind = kind
        s.rail = s:CreateTexture(nil, "BACKGROUND")
        s.rail:SetWidth(2)
        s.rail:SetPoint("TOP", s, "TOPLEFT", STAGE_ICON / 2, -STAGE_ICON - 3)
        s.rail:SetPoint("BOTTOM", s, "BOTTOMLEFT", STAGE_ICON / 2, 3)
        s.icon = S.IconBox(s, STAGE_ICON)
        s.icon:SetPoint("TOPLEFT")
        s.label = S.Text(s, 12, S.GOLD_DIM, nil, "bold")
        -- The tag beside the label is higher than the label: both sit low enough for it to fit.
        s.label:SetPoint("TOPLEFT", TEXT_X, -LABEL_Y)
        s.label:SetWordWrap(false)
        s.label:SetText(S.Upper(title))
        s.tag = S.Badge(s, "")
        s.tag.text:SetWordWrap(false)
        s.tag:SetPoint("LEFT", s.label, "RIGHT", 8, 0)
        s.map = iconButton(s, ACT_ICON.map, 28)
        s.map:SetPoint("TOPRIGHT", 0, -16)
        s.title = S.Text(s, 14)
        s.title:SetPoint("TOPLEFT", s.label, "BOTTOMLEFT", 0, -5)
        s.title:SetPoint("RIGHT", s.map, "LEFT", -8, 0)
        s.title:SetWordWrap(false)
        s.sub = S.Text(s, 12, S.MUTED)
        s.sub:SetPoint("TOPLEFT", s.title, "BOTTOMLEFT", 0, -4)
        s.sub:SetPoint("RIGHT", s.map, "LEFT", -8, 0)
        s.sub:SetWordWrap(false)
        -- A tip from the quest's guide for this stage (D.tips), shown only when there is one.
        s.tip = CreateFrame("Frame", nil, s)
        S.Box(s.tip, S.SURFACE, S.EDGE, S.R_MD)
        s.tip:SetPoint("LEFT", s, "LEFT", TEXT_X, 0)
        s.tip:SetPoint("RIGHT", s, "RIGHT")
        s.tip.icon = s.tip:CreateTexture(nil, "ARTWORK")
        s.tip.icon:SetSize(14, 14)
        s.tip.icon:SetPoint("TOPLEFT", 6, -5)
        s.tip.icon:SetTexture(TIP_ICON)
        s.tip.text = S.Text(s.tip, 12, S.MUTED)
        s.tip.text:SetPoint("TOPLEFT", 26, -5)
        s.tip.text:SetPoint("RIGHT", -6, 0)
        s.tip.text:SetJustifyH("LEFT")
        s.tip.text:SetJustifyV("TOP")
        s.tip:EnableMouse(true)
        s.tip:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L.TIP_GUIDE, 1, 1, 1)
            GameTooltip:AddLine("Guidelime_DungeonQuests", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        s.tip:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        s.tip:Hide()
        d.stages[#d.stages + 1] = s
        return s
    end
    d.stages = {}
    local take = stage("take", L.DETAIL_START)
    local work = stage("work", L.DETAIL_OBJECTIVE)
    local turn = stage("turnin", L.DETAIL_TURNIN)
    take:SetPoint("TOP", b, "TOP")
    work:SetPoint("TOP", take, "BOTTOM")
    turn:SetPoint("TOP", work, "BOTTOM")
    turn.rail:Hide()
    d.start, d.startXY, d.startMap = take.title, take.sub, take.map
    d.turnin, d.turninXY, d.turninMap = turn.title, turn.sub, turn.map
    d.work = work
    fitIcon(take.map, L.SHOW_ON_MAP)
    fitIcon(turn.map, L.SHOW_ON_MAP)
    fitIcon(work.map, L.PIN_ENTRANCE, 80)
    -- Higher than the others: the quest's sentence runs under it.
    work.map:SetPoint("TOPRIGHT", 0, -4)
    take.map:SetScript("OnClick", function()
        local q = d.q
        if q then ns.PinAt(q.who, q.area, q.x, q.y, true) end
    end)
    turn.map:SetScript("OnClick", function()
        local t = d.q and d.q.turnin
        if t then ns.PinAt(t.who, t.area, t.x, t.y, true) end
    end)
    -- The work is in the dungeon: the way in.
    work.map:SetScript("OnClick", function() ns.PinEntrance(ns.selected) end)
    -- Near by, the map buttons also target the giver (ns.TargetOver).
    local function targets(btn, whoOf)
        local function tip(owner)
            if not GameTooltip then return end
            GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L.SHOW_ON_MAP, 1, 1, 1)
            GameTooltip:AddLine(L.TR_TARGET, 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end
        btn:HookScript("OnEnter", function(self)
            local who = whoOf()
            if who and who ~= "" then tip(self); ns.TargetOver(self, who, tip) end
        end)
        btn:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end
    targets(take.map, function() return d.q and d.q.who end)
    targets(turn.map, function() return d.q and d.q.turnin and d.q.turnin.who end)

    -- The work: what the quest says, one row per objective (its state, the count, what it
    -- asks for), the dungeon mobs it needs and what still stands in its way.
    d.objText = S.Text(work, 12, S.MUTED)
    d.objText:SetPoint("LEFT", work, "LEFT", TEXT_X, 0)
    d.objText:SetPoint("RIGHT", work, "RIGHT")
    d.objText:SetJustifyH("LEFT")
    d.objText:SetJustifyV("TOP")
    -- One row per objective: the item's icon (else the state's), what it asks for, the count
    -- and a bar of it.
    d.objRows = {}
    for i = 1, OBJ_MAX do
        local r = CreateFrame("Frame", nil, work)
        r:SetHeight(OBJ_ROW - 4)
        r:SetPoint("LEFT", work, "LEFT", TEXT_X, 0)
        r:SetPoint("RIGHT", work, "RIGHT")
        r.icon = S.IconBox(r, 24)
        r.icon:SetPoint("LEFT")
        r.state = r:CreateTexture(nil, "OVERLAY")
        r.state:SetSize(12, 12)
        r.state:SetPoint("BOTTOMRIGHT", r.icon, "BOTTOMRIGHT", 4, -3)
        r.count = S.Text(r, 12)
        r.count:SetPoint("TOPRIGHT", 0, -1)
        r.count:SetJustifyH("RIGHT")
        r.text = S.Text(r, 12)
        r.text:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, 0)
        r.text:SetPoint("RIGHT", r.count, "LEFT", -8, 0)
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(false)
        r.bar = S.Progress(r, 4)
        r.bar:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 8, 1)
        r.bar:SetPoint("RIGHT")
        r:EnableMouse(true)
        r:SetScript("OnEnter", function(self) if self.item then ns.ItemTip(self, self.item) end end)
        r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        r:Hide()
        d.objRows[i] = r
    end
    -- The dungeon's bosses the quest needs: picture, level, place in the order, a click opens
    -- the boss's page.
    d.bossRows = {}
    for i = 1, BOSS_MAX do
        local r = CreateFrame("Button", nil, work)
        r:SetHeight(BOSS_ROW - 4)
        r:SetPoint("LEFT", work, "LEFT", TEXT_X, 0)
        r:SetPoint("RIGHT", work, "RIGHT")
        S.Box(r, S.SURFACE, S.EDGE, S.R_MD)
        r.pic = S.IconBox(r, 30)
        r.pic:SetPoint("LEFT", 4, 0)
        r.num = S.Text(r.pic, 12, S.Accent(), nil, "bold")
        r.num:SetPoint("CENTER")
        r.go = S.Text(r, 12, S.Accent())
        r.go:SetPoint("RIGHT", -8, 0)
        r.go:SetJustifyH("RIGHT")
        r.go:SetWordWrap(false)
        r.name = S.Text(r, 12, S.GOLD)
        r.name:SetPoint("TOPLEFT", r.pic, "TOPRIGHT", 8, 1)
        r.name:SetPoint("RIGHT", r.go, "LEFT", -8, 0)
        r.name:SetJustifyH("LEFT")
        r.name:SetWordWrap(false)
        r.sub = S.Text(r, 12, S.FAINT)
        r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -2)
        r.sub:SetPoint("RIGHT", r.go, "LEFT", -8, 0)
        r.sub:SetJustifyH("LEFT")
        r.sub:SetWordWrap(false)
        r:SetScript("OnClick", function(self)
            if not self.b then return end
            ns.boss, ns.modelBoss = self.b.npc, self.b.npc
            ns.ShowTab(1)
        end)
        r:Hide()
        d.bossRows[i] = r
    end
    d.mobs = S.Text(work, 12, S.MUTED)
    d.mobs:SetPoint("LEFT", work, "LEFT", TEXT_X, 0)
    d.mobs:SetPoint("RIGHT", work, "RIGHT")
    d.mobs:SetJustifyH("LEFT")
    d.mobs:SetWordWrap(false)
    d.need = S.Text(work, 12, S.BAD)
    d.need:SetPoint("LEFT", work, "LEFT", TEXT_X, 0)
    d.need:SetPoint("RIGHT", work, "RIGHT")
    d.need:SetJustifyH("LEFT")
    d.need:SetWordWrap(false)
    -- Under the way: what the quest gives and where its chain goes on.
    d.summary = CreateFrame("Frame", nil, b)
    S.Box(d.summary, S.SURFACE, S.EDGE, S.R_MD)
    d.summary:SetPoint("LEFT", b, "LEFT")
    d.summary:SetPoint("RIGHT", b, "RIGHT")
    d.summary.gives = S.Text(d.summary, 12, S.MUTED)
    d.summary.gives:SetPoint("TOPLEFT", 10, -7)
    d.summary.gives:SetPoint("RIGHT", -10, 0)
    d.summary.gives:SetJustifyH("LEFT")
    d.summary.gives:SetWordWrap(false)
    d.summary.next = S.Text(d.summary, 12, S.MUTED)
    d.summary.next:SetPoint("TOPLEFT", d.summary.gives, "BOTTOMLEFT", 0, -4)
    d.summary.next:SetPoint("RIGHT", -10, 0)
    d.summary.next:SetJustifyH("LEFT")
    d.summary.next:SetWordWrap(false)
    d.summary:Hide()

    -- Right, only for a quest that has them: the chain, as high as its steps, and the rewards
    -- (each with its icon, its name in its quality colour, and whether it is for you).
    local chain = S.Card(d, L.DETAIL_CHAIN, nil, "Interface\\Icons\\INV_Scroll_03")
    d.chainCard = chain
    d.chain = S.List(chain.body, CHAIN_ROW, makeStep, fillStep)
    d.chain:SetPoint("TOPLEFT")
    d.chain:SetPoint("BOTTOMRIGHT", -10, 0)
    -- Under them, as far as there is room: the dungeon's other quests, a click away.
    local others = S.Card(d, L.DETAIL_OTHERS, nil, S.TAB.list)
    d.othersCard = others
    d.others = S.List(others.body, OTHER_ROW, function(r)
        r.mark = r:CreateTexture(nil, "ARTWORK")
        r.mark:SetSize(16, 16)
        r.mark:SetPoint("LEFT", 4, 0)
        r.tag = S.Text(r, 12, S.FAINT)
        r.tag:SetPoint("RIGHT", -6, 0)
        r.tag:SetWidth(96)
        r.tag:SetJustifyH("RIGHT")
        r.tag:SetWordWrap(false)
        r.text = S.Text(r, 12)
        r.text:SetPoint("LEFT", 28, 0)
        r.text:SetPoint("RIGHT", r.tag, "LEFT", -8, 0)
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(false)
        r.click = CreateFrame("Button", nil, r)
        r.click:SetAllPoints()
        r.click:SetScript("OnClick", function(self)
            local it = self:GetParent().item
            if it then ns.OpenQuest(it.quest.id) end
        end)
    end, function(r, it)
        r.item = it
        local q, group = it.quest, it.hidden and "hidden" or it.group
        r.mark:SetTexture(OTHER_MARK[group] or OTHER_MARK.take)
        r.mark:SetDesaturated(group == "later" or group == "hidden")
        r.mark:SetAlpha((group == "later" or group == "hidden" or group == "done") and 0.6 or 1)
        r.text:SetText(q.head and q.head.name or q.name)
        r.text:SetTextColor(unpack((group == "done" or group == "hidden") and S.MUTED
            or ns.DiffColor(ns.Difficulty(q.level, ns.level or 1))))
        r.tag:SetText(L[(STATUS[group] or STATUS.take)[1]])
    end)
    d.others:SetPoint("TOPLEFT")
    d.others:SetPoint("BOTTOMRIGHT", -10, 0)
    local rew = S.Card(d, L.DETAIL_REWARDS, nil, TI .. "INV_Misc_Bag_10")
    d.rewardCard = rew
    d.rewards = {}
    for i = 1, REWARD_MAX do
        local row = CreateFrame("Frame", nil, rew.body)
        row:SetHeight(REWARD_ROW - 2)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * REWARD_ROW)
        row:SetPoint("RIGHT")
        row.icon = S.IconBox(row, 22)
        row.icon:SetPoint("LEFT", 2, 0)
        row.name = S.Text(row, 12)
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.name:SetPoint("RIGHT")
        row.name:SetWordWrap(false)
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            ns.ItemTip(self, self.id)
        end)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        d.rewards[i] = row
    end
    return d
end

local function dungeonOf(key, level)
    for _, x in ipairs(ns.Dungeons(level or 1)) do if x.key == key then return x end end
end

-- The quest page, for the tests.
function ns.DetailFrame() return detail end

local function whereLine(who, area)
    return ns.Where({ who = who or "", area = area or 0 })
end
local function spot(x, y)
    return (x and x > 0) and string.format("%.1f, %.1f", x, y) or ""
end

-- Fills the page of ns.openQuest.
function ns.FillDetail(level)
    local d = detail
    local q = ns.Quest(ns.openQuest, level, ns.openFrom)
    d.q = q
    if not q then ns.openQuest = nil return end
    local diff = ns.Difficulty(q.level, level)
    d.title:SetText("[" .. q.level .. "] " .. q.name)
    d.title:SetTextColor(unpack(ns.DiffColor(diff)))
    -- A step outside the dungeon: the data has neither its level to take nor its faction.
    local sub = {}
    if not q.outside then sub[1] = L.FROM_LEVEL:format(q.minLevel > 0 and q.minLevel or 1) end
    if q.steps and q.steps > 1 then sub[#sub + 1] = L.STEP:format(q.step, q.steps) end
    if not q.outside then sub[#sub + 1] = L[SIDE_TEXT[q.side] or "FACTION_BOTH"] end
    if q.class then sub[#sub + 1] = ns.ClassTag() end
    sub[#sub + 1] = ns.XPText(q.id, level)
    d.sub:SetText(table.concat(sub, "  ·  "))
    local state = q.state == "later" and q.why == "WHY_LEVEL" and "later" or q.state
    d.state:Set(L["STATE_" .. (state == "hidden" and "TAKE" or state):upper()] or "", STATE_COLOR[state] or S.MUTED)
    d.side:SetShown(SIDE_ICON[q.side] ~= nil)
    if SIDE_ICON[q.side] then d.side:SetIcon(SIDE_ICON[q.side]) end

    -- The three stages: whose turn it is, where each happens.
    local key = ns.selected
    local dungeon = ns.DungeonName(dungeonOf(key, level) or {}) or ""
    local insideText = S.IconTag(ns.Icon(key)) .. " " .. L.INSIDE_OF:format(dungeon)
    local stages = ns.Stages(q, key)
    for i, s in ipairs(d.stages) do
        local st = stages[i]
        s.tag:Set((st.state == "done" and L.STATE_DONE) or (st.state == "now" and L.STAGE_NOW) or nil,
                  st.state == "done" and S.GOOD or S.Accent())
        S.SetBorder(s.icon, (st.state == "done" and S.GOOD) or (st.state == "now" and S.Accent()) or S.RING)
        s.icon:SetAlpha(st.state == "wait" and 0.6 or 1)
        local rc = st.state == "done" and S.GOOD or S.EDGE
        s.rail:SetColorTexture(rc[1], rc[2], rc[3], st.state == "done" and 0.8 or rc[4] or 1)
        local faded = st.state == "done"
        s.title:SetTextColor(unpack(faded and S.MUTED or S.TEXT))
        if st.kind == "work" then
            s.icon:SetIcon(st.inside and ns.Icon(key) or S.TAB.quests)
            s.title:SetText(st.inside and L.INSIDE_OF:format(dungeon) or "")
            s.title:SetTextColor(unpack(faded and S.MUTED or S.GOLD))
            s.sub:SetText("")
            s.map:SetShown(st.inside and ns.PinEntrance(key, true))
        else
            s.icon:SetIcon(STAGE_ICONS[st.kind])
            local pin = st.area > 0 and st.x > 0
            if st.inside then
                s.title:SetText(st.who ~= "" and st.who or L.INSIDE)
                s.sub:SetText(insideText)
            elseif st.area > 0 then
                s.title:SetText(st.who ~= "" and st.who or "-")
                local zone, xy = whereLine("", st.area), spot(st.x, st.y)
                s.sub:SetText(zone .. ((zone ~= "" and xy ~= "") and "  ·  " or "") .. xy)
            elseif st.who ~= "" then
                s.title:SetText(st.kind == "take" and L.FROM_ITEM:format(st.who) or st.who)
                s.sub:SetText("")
            else
                s.title:SetText(st.kind == "take" and L.INSIDE or "-")
                s.sub:SetText("")
            end
            s.map:SetShown(pin)
        end
        -- Without the map button, the place takes the stage's whole width.
        local edge = s.map:IsShown() and s.map or s
        local gap = s.map:IsShown() and -8 or 0
        s.title:SetPoint("RIGHT", edge, s.map:IsShown() and "LEFT" or "RIGHT", gap, 0)
        s.sub:SetPoint("RIGHT", edge, s.map:IsShown() and "LEFT" or "RIGHT", gap, 0)
    end

    -- The right column: the chain, the rewards, the dungeon's other quests.
    local rewards = ns.Rewards(q)
    local shownRew = math.min(#rewards, #d.rewards)
    for i, row in ipairs(d.rewards) do
        local r = rewards[i]
        row:SetShown(r ~= nil)
        if r then
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
    local hasChain, hasRew = #q.chain > 1, shownRew > 0
    local info, chain, rew, others = d.infoCard, d.chainCard, d.rewardCard, d.othersCard
    local room = (info:GetHeight() or 0) > 80 and info:GetHeight() or 306
    local rewH = hasRew and (36 + shownRew * REWARD_ROW + S.INSET) or 0
    local chainH = 0
    if hasChain then
        -- As high as its steps, at most down to the rewards (or the buttons).
        chainH = math.min(36 + #q.chain * CHAIN_ROW + S.INSET, room - (hasRew and (rewH + S.GAP) or 0))
    end
    -- The other quests of the list, in its order.
    local rest = {}
    for _, it in ipairs(ns.listItems or {}) do
        if it.quest and it.quest.id ~= q.id then rest[#rest + 1] = it end
    end
    local used = chainH + rewH + (hasChain and S.GAP or 0) + (hasRew and S.GAP or 0)
    local hasOthers = #rest > 0 and room - used >= 36 + S.INSET + 2 * OTHER_ROW
    local prev
    local function put(card, shown, height)
        card:SetShown(shown)
        if not shown then return end
        card:ClearAllPoints()
        if prev then card:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -S.GAP)
        else card:SetPoint("TOPLEFT", info, "TOPRIGHT", S.GAP, 0) end
        card:SetPoint("RIGHT", d, "RIGHT")
        if height then card:SetHeight(height) else card:SetPoint("BOTTOM", d.foot, "TOP", 0, S.GAP) end
        prev = card
    end
    put(chain, hasChain, chainH)
    put(rew, hasRew, rewH)
    put(others, hasOthers)
    if hasChain then
        chain:SetTitle(L.DETAIL_CHAIN, tostring(#q.chain))
        d.chain:SetData(q.chain)
        -- keep the shown step in sight
        local bar, view = rawget(d.chain, "bar"), tonumber(d.chain:GetHeight()) or 0
        for i, st in ipairs(q.chain) do
            if st.this and bar and view > 0 then
                local top, at = (i - 1) * CHAIN_ROW, tonumber(bar:GetValue()) or 0
                if top < at then bar:SetValue(top)
                elseif top + CHAIN_ROW > at + view then bar:SetValue(top + CHAIN_ROW - view) end
            end
        end
    end
    if hasOthers then
        others:SetTitle(L.DETAIL_OTHERS, tostring(#rest))
        d.others:SetData(rest)
        d.othersData = rest
    end
    -- With nothing for the right column, the way takes the whole page.
    local full = not (hasChain or hasRew or hasOthers)
    info:ClearAllPoints()
    info:SetPoint("TOPLEFT", d.topCard, "BOTTOMLEFT", 0, -S.GAP)
    info:SetPoint("BOTTOMLEFT", d.foot, "TOPLEFT", 0, S.GAP)
    if full then info:SetPoint("RIGHT", d, "RIGHT") else info:SetPoint("RIGHT", d, "CENTER", 20, 0) end

    -- The page's scroll takes its width from a resize; set it here too, for the first show.
    local cardW = (d:GetWidth() or 0) > 200 and (full and d:GetWidth() or d:GetWidth() / 2 + 20) or 0
    if cardW > 0 then d.infoBody:SetWidth(cardW - 2 * S.INSET - 10) end

    -- The work stage: the quest's own text, the objectives, the bosses, the mobs, what stands
    -- in the way, and its tip.
    local work = d.work
    local wide = math.max(160, (d.infoBody:GetWidth() or 0) - STAGE_ICON - 14)
    local function linesOf(t, width)
        return math.min(4, math.max(1, math.ceil((t:GetStringWidth() or 0) * 1.12 / width)))
    end
    -- A stage's tip under what is above it, at y; returns the y under it.
    local function placeTip(st, text, y)
        local tip = st.tip
        tip:SetShown(text ~= nil and text ~= "")
        if not tip:IsShown() then return y end
        tip.text:SetText(text)
        local lines = linesOf(tip.text, wide - 32)
        tip.text:SetMaxLines(lines)
        tip.text:SetHeight(lines * TIP_LINE)
        tip:SetHeight(lines * TIP_LINE + 10)
        tip:ClearAllPoints()
        tip:SetPoint("TOP", st, "TOP", 0, -y - 2)
        tip:SetPoint("LEFT", st, "LEFT", STAGE_ICON + 14, 0)
        tip:SetPoint("RIGHT", st, "RIGHT")
        return y + lines * TIP_LINE + 16
    end
    local y = LABEL_Y + (work.title:GetText() ~= "" and 40 or 20)
    local goals = ns.Goals(q)
    -- The game gives counted lines while the quest is in the log; the data's sentence says
    -- what it is about, over them or alone.
    local sentence = q.text or ""
    if #goals == 0 and #q.objectives > 0 then sentence = q.objectives[1].text end
    d.objText:SetText(sentence)
    d.objText:SetShown(sentence ~= "")
    if sentence ~= "" then
        local lines = linesOf(d.objText, wide)
        d.objText:SetMaxLines(lines)
        d.objText:SetHeight(lines * 16)
        d.objText:ClearAllPoints()
        d.objText:SetPoint("TOP", work, "TOP", 0, -y)
        d.objText:SetPoint("LEFT", work, "LEFT", STAGE_ICON + 14, 0)
        d.objText:SetPoint("RIGHT", work, "RIGHT")
        y = y + lines * 16 + 6
    end
    for i, r in ipairs(d.objRows) do
        local o = goals[i]
        r:SetShown(o ~= nil)
        if o then
            r.item = o.item
            r.icon:SetIcon(o.icon or (o.item and "Interface\\Icons\\INV_Misc_QuestionMark") or S.TAB.quests)
            r.icon:SetGlow(o.done and S.GOOD or S.RING)
            r.state:SetShown(o.have ~= nil or o.done)
            r.state:SetTexture(o.done and ICON_OK or WAIT_ICON)
            r.text:SetText(o.text or "")
            r.text:SetTextColor(unpack(o.done and S.MUTED or S.TEXT))
            r.count:SetText(o.have and (o.have .. "/" .. o.need) or "")
            r.count:SetTextColor(unpack(o.done and S.GOOD or S.WARN))
            r.bar:Set(o.done and 1 or (o.have and o.need > 0 and o.have / o.need) or 0, o.done and S.GOOD or nil)
            r:ClearAllPoints()
            r:SetPoint("TOP", work, "TOP", 0, -y)
            r:SetPoint("LEFT", work, "LEFT", STAGE_ICON + 14, 0)
            r:SetPoint("RIGHT", work, "RIGHT")
            y = y + OBJ_ROW
        end
    end
    local bosses = ns.QuestBosses(q, key)
    local named = {}
    for i, r in ipairs(d.bossRows) do
        local bo = bosses[i]
        r.b = bo
        r:SetShown(bo ~= nil)
        if bo then
            named[bo.name] = true
            local icon = ns.BossIcon(key, bo)
            local portrait = not icon and bo.display > 0 and SetPortraitTextureFromCreatureDisplayID
            if icon then r.pic.tex:SetTexture(icon)
            elseif portrait then r.pic.tex:SetTexture(nil); portrait(r.pic.tex, bo.display)
            else r.pic.tex:SetTexture(nil) end
            r.num:SetText((icon or portrait) and "" or tostring(bo.n))
            local level = bo.min <= 0 and "??" or (bo.min == bo.max and tostring(bo.min) or (bo.min .. "-" .. bo.max))
            local color = bo.min <= 0 and S.BAD or ns.DiffColor(ns.Difficulty(bo.max, ns.level or 1))
            r.name:SetText(bo.name)
            r.sub:SetText(S.Hex(color) .. level .. "|r" .. (bo.rare and "" or ("  ·  " .. L.BOSS_N:format(bo.n, bo.of))))
            r.go:SetText(L.BOSS_PAGE .. " »")
            r:ClearAllPoints()
            r:SetPoint("TOP", work, "TOP", 0, -y)
            r:SetPoint("LEFT", work, "LEFT", STAGE_ICON + 14, 0)
            r:SetPoint("RIGHT", work, "RIGHT")
            y = y + BOSS_ROW
        end
    end
    local function lineAt(t, text)
        t:SetText(text)
        t:SetShown(text ~= "")
        if text == "" then return end
        t:ClearAllPoints()
        t:SetPoint("TOP", work, "TOP", 0, -y - 2)
        t:SetPoint("LEFT", work, "LEFT", STAGE_ICON + 14, 0)
        t:SetPoint("RIGHT", work, "RIGHT")
        y = y + 20
    end
    -- The mobs that are no boss of the list above.
    local mobs = {}
    for _, m in ipairs(q.targets or {}) do if not named[m] then mobs[#mobs + 1] = m end end
    lineAt(d.mobs, #mobs > 0 and (L.DETAIL_MOBS .. ":  " .. S.Hex(S.TEXT) .. table.concat(mobs, ", ") .. "|r") or "")
    local need
    for _, st in ipairs(q.chain) do if st.missing then need = st end end
    if need then
        lineAt(d.need, L.REQUIRES:format(need.name))
    elseif q.state == "later" and q.why == "WHY_LEVEL" then
        lineAt(d.need, L.WHY_LEVEL:format(q.minLevel))
    elseif q.state == "later" then
        lineAt(d.need, ns.NeedText(q.need))
    else
        lineAt(d.need, "")
    end
    -- A stage that is done needs no tip any more.
    local function tipOf(i) return stages[i].state ~= "done" and stages[i].tip or nil end
    y = placeTip(work, tipOf(2), y)

    -- The two ends: who and where, then the tip.
    local function endHeight(i)
        local st = d.stages[i]
        local h = LABEL_Y + 37 + (st.sub:GetText() ~= "" and 18 or 0)
        return math.max(i == 3 and STAGE_MIN - 14 or STAGE_MIN, placeTip(st, tipOf(i), h) + 4)
    end
    local takeH, turnH = endHeight(1), endHeight(3)
    local workH = math.max(y + 8, STAGE_MIN)

    -- Under the way: the XP and the first reward, then the chain's next steps.
    local gives = {}
    gives[#gives + 1] = ns.XPText(q.id, level)
    local r1 = rewards[1]
    if r1 then
        gives[#gives + 1] = (r1.name and (S.QualityHex(r1.quality) .. r1.name .. "|r") or ("#" .. r1.id))
            .. (#rewards > 1 and ("  " .. S.Hex(S.FAINT) .. "+" .. (#rewards - 1) .. "|r") or "")
    end
    local after, seen = {}, false
    for _, st in ipairs(q.chain) do
        if seen and #after < 2 then after[#after + 1] = S.Hex(S.TEXT) .. st.name .. "|r" end
        if st.this then seen = true end
    end
    d.summary.gives:SetText(table.concat(gives, "  ·  "))
    d.summary.next:SetText(#after > 0 and L.THEN_STEPS:format(table.concat(after, " » ")) or "")
    local sumLines = (#gives > 0 and 1 or 0) + (#after > 0 and 1 or 0)
    local sumH = sumLines > 0 and (sumLines * 16 + 12) or 0
    d.summary:SetShown(sumH > 0)
    if sumLines == 1 and #gives == 0 then
        d.summary.gives:SetText(d.summary.next:GetText()); d.summary.next:SetText("")
    end

    -- The stages fill the card's height, so the way reaches its bottom; a long one scrolls.
    room = room - 2 * S.INSET
    local total = takeH + workH + turnH + (sumH > 0 and sumH + S.GAP or 0)
    if room > total then
        local spare = math.min(room - total, 60)
        takeH, workH = takeH + math.floor(spare / 3), workH + math.floor(spare / 3)
        total = total + 2 * math.floor(spare / 3)
    end
    d.stages[1]:SetHeight(takeH)
    d.stages[2]:SetHeight(workH)
    d.stages[3]:SetHeight(turnH)
    if sumH > 0 then
        d.summary:SetHeight(sumH)
        d.summary:ClearAllPoints()
        d.summary:SetPoint("TOP", d.infoBody, "TOP", 0, -math.max(total - sumH, room - sumH))
        d.summary:SetPoint("LEFT", d.infoBody, "LEFT")
        d.summary:SetPoint("RIGHT", d.infoBody, "RIGHT")
    end
    d.infoPage:SetContent(math.max(total, sumH > 0 and room or 0))
    if d.shownId ~= q.id then
        d.shownId = q.id
        local bar = d.infoPage.scroll.bar
        if bar then bar:SetValue(0) end
    end

    local at
    for i, id in ipairs(ns.listIds or {}) do if id == q.id then at = i end end
    d.prev:SetEnabled(at ~= nil and at > 1)
    d.next:SetEnabled(at ~= nil and at < #(ns.listIds or {}))
    local inLog = q.state == "log"
    fitIcon(d.track, inLog and ns.Tracked(q.id) and L.UNTRACK or L.TRACK)
    d.track:SetEnabled(inLog)
    d.share:SetEnabled(inLog)
    fitIcon(d.hide, ns.Hidden(q.id) and L.UNHIDE or L.HIDE)
    d.hide:SetEnabled(not q.outside)
    local others = inLog and ns.GroupOn(q.id) or {}
    d.status:SetText(#others > 0 and L.TT_GROUP:format(table.concat(others, ", ")) or "")
    if not d.note:HasFocus() then d.note:SetText(ns.Note("q" .. q.id)) end
end

local function buildSettings(parent)
    -- It scrolls: long texts in some languages take two lines and the hub may be short.
    local page = S.ScrollPage(parent, S.WIDE_W - 2 * S.PAD)
    local inner = page.inner
    local sw = {}
    for _, o in ipairs({ { "warnEnter", L.OPT_ENTER, L.OPT_ENTER_D }, { "remind", L.OPT_REMIND, L.OPT_REMIND_D },
                         { "wishAlert", L.OPT_WISH, L.OPT_WISH_D }, { "learn", L.OPT_LEARN, L.OPT_LEARN_D },
                         { "keys", L.OPT_KEYS, L.OPT_KEYS_D }, { "tomtom", L.OPT_TOMTOM, L.OPT_TOMTOM_D },
                         { "hideLater", L.OPT_LATER, L.OPT_LATER_D } }) do
        local key = o[1]
        sw[#sw + 1] = { o[2], o[3], function() return ns.Get(key) end, function(v) ns.Set(key, v) end,
                        icon = ns.OPT_ICON[key] }
    end
    local card, h = S.SettingsCard(inner, L.SET_SWITCHES, sw)
    settings = {}
    for i, row in ipairs(card.rows) do settings[#settings + 1] = { row = row, get = sw[i][3] } end
    card:SetPoint("TOPLEFT")
    card:SetPoint("TOPRIGHT")
    card:SetHeight(h)
    local note = S.Note(inner, 12)
    note:SetPoint("TOPLEFT", card, "BOTTOMLEFT", S.INSET, -S.GAP)
    note:SetPoint("RIGHT", -S.INSET, 0)
    note:SetText(L.READY_MOVED)
    page:SetContent(h + S.GAP + 34)
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
    left:SetWidth(248)
    p.left = left
    p.list = S.List(left.body, LOOT_ROW, makeBoss, fillBoss)
    p.list:SetPoint("TOPLEFT")
    p.list:SetPoint("BOTTOMRIGHT", -10, 0)
    p.list.heightOf = bossHeight

    -- The loot keeps the bottom, as high as BOSS_LOOT rows: most bosses fit without a scroll bar.
    local loot = S.Card(p, L.LOOT_OF, "", "Interface\\Icons\\INV_Misc_Bag_10")
    loot:SetPoint("BOTTOMLEFT", left, "BOTTOMRIGHT", S.GAP, 0)
    loot:SetPoint("BOTTOMRIGHT")
    loot:Fit(BOSS_LOOT * BOSS_LOOT_ROW)
    p.lootCard = loot
    p.loot = S.List(loot.body, BOSS_LOOT_ROW, makeLoot, fillLoot)
    p.loot:SetPoint("TOPLEFT")
    p.loot:SetPoint("BOTTOMRIGHT", -10, 0)

    local info = S.Card(p)
    info:SetPoint("TOPLEFT", left, "TOPRIGHT", S.GAP, 0)
    info:SetPoint("TOPRIGHT")
    info:SetPoint("BOTTOM", loot, "TOP", 0, S.GAP)
    p.info = info
    local b = info.body
    -- The boss's own model from the game; drag to turn it.
    local holder = CreateFrame("Frame", nil, b)
    holder:SetPoint("TOPLEFT")
    holder:SetPoint("BOTTOMLEFT")
    holder:SetWidth(150)
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
    p.link = iconButton(b, ACT_ICON.link, 28)
    fitIcon(p.link, L.WOWHEAD)
    p.link:SetPoint("TOPRIGHT")
    p.link:SetScript("OnClick", function()
        if ns.boss then ns.ShowLink(ns.WowheadURL("npc", ns.boss), p.name:GetText()) end
    end)
    p.name = S.Text(b, 16, nil, nil, "title")
    p.name:SetPoint("TOPLEFT", holder, "TOPRIGHT", 14, -1)
    p.name:SetPoint("RIGHT", p.link, "LEFT", -8, 0)
    p.name:SetWordWrap(false)
    p.sub = S.Text(b, 12, S.MUTED)
    p.sub:SetPoint("TOPLEFT", p.name, "BOTTOMLEFT", 0, -5)
    p.sub:SetPoint("RIGHT", p.link, "LEFT", -8, 0)
    p.sub:SetWordWrap(false)
    -- Kills, and a bar of pips: full when the chances shown are the player's own.
    p.kills = S.Text(b, 12, S.FAINT, nil, "bold")
    p.kills:SetPoint("TOPLEFT", p.sub, "BOTTOMLEFT", 0, -7)
    p.kills:SetWordWrap(false)
    local box = CreateFrame("Frame", nil, b)
    box:SetSize(OWN_PIPS * 13 + 40, 16)
    box:SetPoint("LEFT", p.kills, "RIGHT", 10, 0)
    box:EnableMouse(true)
    box:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local k = self.kills or 0
        GameTooltip:AddLine(k >= ns.OWN_AFTER and L.OWN_DONE or L.OWN_HINT:format(k, ns.OWN_AFTER), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    box:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    p.pipBox = box
    p.pips = {}
    for i = 1, OWN_PIPS do
        local pip = plain(box, "ARTWORK", EMPTY_PIP)
        pip:SetSize(10, 4)
        pip:SetPoint("LEFT", (i - 1) * 13, 0)
        p.pips[i] = pip
    end
    p.own = S.Text(box, 12, S.FAINT)
    p.own:SetPoint("LEFT", OWN_PIPS * 13 + 4, 0)
    -- The abilities by name, two to a line.
    p.spells = {}
    for i = 1, MAX_SPELLS do
        local row = CreateFrame("Frame", nil, b)
        row:SetHeight(22)
        local col, line = (i - 1) % 2, math.floor((i - 1) / 2)
        if col == 0 then
            row:SetPoint("TOPLEFT", p.kills, "BOTTOMLEFT", 0, -9 - line * 23)
            row:SetPoint("RIGHT", b, "RIGHT", -178, 0)
        else
            row:SetPoint("TOPLEFT", p.kills, "BOTTOMLEFT", 178, -9 - line * 23)
            row:SetPoint("RIGHT", b, "RIGHT")
        end
        row.icon = S.IconBox(row, 20)
        row.icon:SetPoint("LEFT")
        row.name = S.Text(row, 12, S.MUTED)
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 7, 0)
        row.name:SetPoint("RIGHT")
        row.name:SetWordWrap(false)
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            if not (GameTooltip and self.spell) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(self.spell.id) else GameTooltip:AddLine(self.spell.name) end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        p.spells[i] = row
    end
    p.note = S.Edit(b, 200, 26)
    p.note:SetPoint("BOTTOMLEFT", holder, "BOTTOMRIGHT", 14, 0)
    p.note:SetPoint("RIGHT", b, "RIGHT")
    p.note:SetJustifyH("LEFT")
    S.Placeholder(p.note, L.NOTE_HINT)
    p.note:HookScript("OnTextChanged", function(self, user)
        if user and p.noteKey then ns.SetNote(p.noteKey, self:GetText()) end
    end)
    p.note:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    p.note:HookScript("OnEditFocusLost", function()
        p.noteOpen = nil
        if ns.Refresh then ns.Refresh() end
    end)
    p.noteBtn = CreateFrame("Button", nil, b)
    p.noteBtn:SetHeight(26)
    p.noteBtn:SetPoint("BOTTOMLEFT", holder, "BOTTOMRIGHT", 14, 0)
    p.noteBtn.text = S.Text(p.noteBtn, 12, S.Accent())
    p.noteBtn.text:SetPoint("LEFT")
    p.noteBtn.text:SetText(L.NOTE_ADD)
    p.noteBtn:SetWidth(math.max(80, math.floor((p.noteBtn.text:GetStringWidth() or 0) + 8)))
    p.noteBtn:SetScript("OnClick", function()
        p.noteOpen = ns.boss
        p.note:Show()
        p.noteBtn:Hide()
        if p.note.SetFocus then p.note:SetFocus() end
    end)
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
        if f[1] == "wish" and rawget(b, "btnIcon") then setStar(b.btnIcon) end
        b:SetScript("OnClick", function() ns.lootFilter = f[1]; ns.Refresh() end)
        lootFilters[f[1]] = b
    end
    local card = S.Card(p)
    card:SetPoint("TOPLEFT", p.filters, "BOTTOMLEFT", 0, -S.GAP)
    card:SetPoint("BOTTOMRIGHT")
    p.list = S.List(card.body, LOOT_ROW, makeLoot, fillLoot)
    p.list:SetPoint("TOPLEFT")
    p.list:SetPoint("BOTTOMRIGHT", -10, 0)
    p.list.heightOf = lootHeight
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
    -- Only the levelling chains (D.main), or every quest that touches the dungeon.
    mainSwitch = S.SwitchLabel(filterRow, L.F_MAIN, function() return ns.Get("mainOnly") end,
                               function(v) ns.Set("mainOnly", v) end, 110)
    mainSwitch:HookScript("OnEnter", function(self)
        if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(L.OPT_MAIN_D, 1, 1, 1, true); GameTooltip:Show() end
    end)
    mainSwitch:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
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
    list = S.List(right.body, CARD_H, makeRow, fillRow, 4)
    list.heightOf = rowHeight
    list:SetPoint("TOPLEFT")
    list:SetPoint("BOTTOMRIGHT", -10, 0)

    detail = buildDetail(questPage)
    detail:SetAllPoints()
    detail:Hide()
    return questPage
end

-- The world map the journal opened must not hide behind it: while that map shows, the window
-- (and the hub around it) lies under the map, and comes back up when the map or the window
-- closes. Only our own frames change strata, never the game's map.
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

local function build()
    frame = S.Window("GulliDungeonPrepFrame", L.TITLE, S.WIDE_W, S.DOCK_H)
    local body = frame.body
    grid = CreateFrame("Frame", nil, body)
    grid:SetAllPoints()
    grid:Hide()
    -- The tiles scroll inside a card, so the edge where they leave the view shows.
    grid.card = S.Card(grid, L.ALL_DUNGEONS, nil, TI .. "INV_Misc_Map_02")
    grid.card:SetAllPoints()
    grid.list = S.List(grid.card.body, TILE_H, makeGridRow, fillGridRow, S.GAP)
    grid.list:SetPoint("TOPLEFT")
    grid.list:SetPoint("BOTTOMRIGHT", -10, 0)
    grid.list.heightOf = function(row) return row.title and 24 or TILE_H end
    -- The edge the tiles scroll under: a line across the card below its title, and a short
    -- shadow under it, drawn over the tiles.
    local edge = CreateFrame("Frame", nil, grid.card)
    edge:SetPoint("TOPLEFT", grid.card.body, "TOPLEFT", -S.INSET + 1, 0)
    edge:SetPoint("TOPRIGHT", grid.card.body, "TOPRIGHT", S.INSET - 1, 0)
    edge:SetHeight(EDGE_SHADE * 3 + 1)
    edge:SetFrameLevel((tonumber(grid.list:GetFrameLevel()) or 1) + 10)
    local line = S.Divider(edge, S.EDGE)
    line:SetPoint("TOPLEFT")
    line:SetPoint("TOPRIGHT")
    line:SetHeight(1)
    for i = 1, 3 do
        local shade = S.Divider(edge, { 0, 0, 0, 0.36 - i * 0.1 })
        shade:SetPoint("TOPLEFT", 0, -1 - (i - 1) * EDGE_SHADE)
        shade:SetPoint("TOPRIGHT", 0, -1 - (i - 1) * EDGE_SHADE)
        shade:SetHeight(EDGE_SHADE)
    end
    -- The same line where they leave the view at the bottom.
    local foot = S.Divider(edge, S.EDGE)
    foot:SetPoint("BOTTOMLEFT", grid.card.body, "BOTTOMLEFT", -S.INSET + 1, 0)
    foot:SetPoint("BOTTOMRIGHT", grid.card.body, "BOTTOMRIGHT", S.INSET - 1, 0)
    foot:SetHeight(1)
    grid.edge = edge

    -- Inside a dungeon its pages take the whole width; « All dungeons goes back to the tiles.

    local area = CreateFrame("Frame", nil, body)
    areaFrame = area
    area:SetAllPoints()
    homeBtn = S.Return(S.FitButton(area, "« " .. L.ALL_DUNGEONS, 30, 96))
    homeBtn:SetPoint("TOPLEFT")
    homeBtn:SetScript("OnClick", function() ns.home, ns.openQuest = true, nil; ns.Refresh() end)
    tabs = S.PageTabs(area, { L.TAB_BOSSES, L.TAB_LOOT, L.TAB_QUESTS, L.TAB_SETTINGS }, nil, showTab, nil,
        { TI .. "INV_Misc_Head_Dragon_01", TI .. "INV_Misc_Bag_10", S.TAB.quests, S.TAB.settings })
    tabs.frame:ClearAllPoints()
    tabs.frame:SetPoint("TOPLEFT", homeBtn, "TOPRIGHT", S.GAP, 0)
    -- beside the page tabs: lower than them and lifted, clear of the hairline under the tabs
    search = S.Edit(area, 140, 28)
    search:SetJustifyH("LEFT")
    S.Placeholder(search, L.SEARCH)
    search:SetPoint("TOPRIGHT", 0, 3)
    search:SetPoint("TOPLEFT", tabs.frame, "TOPRIGHT", 8, 3)
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
        ns.PinEntrance(ns.selected)
    end)
    head.range = S.Text(head.body, 13, nil, nil, "bold")
    head.name = S.Text(head.body, 16, nil, nil, "title")
    head.name:SetPoint("LEFT", head.icon, "RIGHT", 10, 0)
    head.name:SetWordWrap(false)
    head.range:SetPoint("LEFT", head.name, "RIGHT", 8, 0)
    head.range:SetJustifyH("LEFT")
    head.range:SetWordWrap(false)
    head.chips = {}
    for i = 1, 4 do head.chips[i] = headChip(head.body) end

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
