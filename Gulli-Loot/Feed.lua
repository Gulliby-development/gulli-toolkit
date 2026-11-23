-- The loot feed (switch `feed`): a small panel of what the player just looted, the gold and each
-- item with its icon, count and quality colour. It works with fast loot and auto loot, whatever
-- loot window shows, and every line fades away after a few seconds. Items come from the loot chat
-- (the game's own "You receive loot" lines), money from the money that came in while loot was open.
-- Each item line also says what it is worth (a vendor, the auction or disenchanting, whichever
-- brings most) and one note: the quest that needs it, better gear, a farm goal, how many the bags
-- hold. Two looks: detailed (the note on a second line) and compact (one line, switch feedCompact).

local _, ns = ...
local L = ns.L
local S = ns.Skin

ns.FEED_ROWS = 5        -- lines shown at most by default (the player's `feedRows`), newest on top
ns.FEED_ROWS_MAX = 8    -- the most the player can ask for
ns.FEED_KEEP = 20       -- lines kept for the total while they are not too old
ns.FEED_SECONDS = 6     -- how long a line stays
ns.FEED_FADE = 1.5      -- the last part of that it fades
ns.FEED_MONEY_WAIT = 2  -- money that comes in this long after the loot closed still counts
ns.FEED_STALE = 0.5     -- the facts of a line are read again this long after the bags or the log changed
local ROW_H, ROW_H2, FOOT_H, PAD = 26, 40, 24, 6
local WIDTH_MIN, WIDTH_MAX = 150, 320   -- the panel is as wide as its longest line, within these

local entries = {}      -- newest first: { kind = "item"|"money", id, icon, name, quality, count, copper, at }
local frame, rows, sample, foot
local staleAt
local lootOpen, lootUntil, lastMoney

local function now() return GetTime and GetTime() or 0 end
local function secret(v) return issecretvalue and issecretvalue(v) end

function ns.FeedOn() return ns.db ~= nil and ns.db.feed == true and not ns.paused end

-- How many lines show at most: the player's number, 1 to FEED_ROWS_MAX.
function ns.FeedRows()
    local n = tonumber(ns.db and ns.db.feedRows) or ns.FEED_ROWS
    return math.max(1, math.min(ns.FEED_ROWS_MAX, math.floor(n)))
end

-- A Lua pattern from a game format string such as "You receive loot: %sx%d.".
local function pattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local p = fmt:gsub("%%(%d)%$", "%%"):gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
    return "^" .. p .. "$"
end

-- The item link and count of a loot chat line of the player, or nil.
function ns.FeedParse(msg)
    if type(msg) ~= "string" or secret(msg) then return nil end
    local many = pattern(LOOT_ITEM_SELF_MULTIPLE)
    if many then
        local link, n = msg:match(many)
        if link then return link, tonumber(n) or 1 end
    end
    local one = pattern(LOOT_ITEM_SELF)
    local link = one and msg:match(one)
    if link then return link, 1 end
    return nil
end

local function itemFacts(link)
    local id = tonumber(link:match("item:(%d+)"))
    local name = link:match("%[(.-)%]")
    local icon, quality
    if id then
        if C_Item and C_Item.GetItemIconByID then icon = C_Item.GetItemIconByID(id)
        elseif GetItemIcon then icon = GetItemIcon(id) end
        if C_Item and C_Item.GetItemQualityByID then quality = C_Item.GetItemQualityByID(id) end
        if not quality then
            local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
            if f then
                local n, _, q = f(id)
                quality, name = q, name or n
            end
        end
    end
    return id, name or "?", icon, quality or 1
end

---- What a line says about its item ---------------------------------------------------------

local GEAR = { [2] = true, [4] = true }
local AUCTION = { [5] = true, [7] = true, [9] = true }   -- reagents, trade goods, recipes
local QUEST_CLASS = 12
-- Disenchanting green gear: the dust and the lesser essence for its item level (Vanilla tiers).
ns.FEED_DE = {
    { 15, 10940, 10938 }, { 20, 10940, 10939 }, { 25, 11083, 10998 }, { 30, 11083, 11082 },
    { 35, 11137, 11134 }, { 40, 11137, 11135 }, { 45, 11176, 11174 }, { 50, 11176, 11175 },
    { 55, 16204, 16202 }, { 999, 16204, 16203 },
}
ns.FEED_SRC_ICON = {
    vendor = "Interface\\Icons\\INV_Misc_Coin_02",
    auction = "Interface\\Minimap\\Tracking\\Auctioneer",
    disenchant = "Interface\\Icons\\INV_Enchant_Disenchant",
}

local function info(id)
    local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not f then return nil end
    local name, _, quality, ilvl, _, _, _, _, _, _, sell, class, _, bind = f(id)
    if not name then return nil end
    return { name = name, quality = quality or 1, ilvl = ilvl or 0, sell = sell or 0, class = class, bind = bind }
end

-- From any price addon (Auctionator, auxForever, Naowh Forever, ...), through the shared reader.
local function auction(id)
    if not (S.AuctionPrice and id) then return nil end
    local ok, price = pcall(S.AuctionPrice, id)
    return ok and type(price) == "number" and price > 0 and price or nil
end

-- The player knows Enchanting (skill line 333).
local function enchanter()
    if not (GetProfessions and GetProfessionInfo) then return false end
    for _, i in ipairs({ GetProfessions() }) do
        if i then
            local _, _, _, _, _, _, line = GetProfessionInfo(i)
            if line == 333 then return true end
        end
    end
    return false
end

local function disenchant(ilvl)
    for _, t in ipairs(ns.FEED_DE) do
        if ilvl <= t[1] then
            local a, b = auction(t[2]), auction(t[3])
            if a and b then return math.min(a, b) end
            return a or b
        end
    end
end

-- What one of the item brings and where: "vendor", "auction" or "disenchant", the most of them.
-- Grey things and bound gear only go to a vendor; cloth, leather, ore, reagents, recipes and gear
-- that binds when equipped may go to the auction; green gear of an enchanter may be worth more as
-- dust. nil when it brings nothing or the client does not know the item yet.
function ns.FeedValue(id)
    local f = id and info(id)
    if not f then return nil end
    local best, how = f.sell, "vendor"
    if f.quality > 0 then
        local gear = GEAR[f.class]
        local tradeable = f.bind ~= 1 and f.bind ~= 4
        if AUCTION[f.class] or (gear and f.quality >= 2 and f.bind == 2)
            or (not gear and tradeable and f.class ~= QUEST_CLASS and f.sell <= 1) then
            local ah = auction(id)
            if ah and ah > best then best, how = ah, "auction" end
        end
        if gear and f.quality == 2 and enchanter() then
            local de = disenchant(f.ilvl)
            if de and de > best then best, how = de, "disenchant" end
        end
    end
    if best <= 0 then return nil end
    return best, how
end

-- "Wolf Pelt: 3/10" and "3/10 Wolf Pelt" are both "Wolf Pelt".
local function objectiveName(text)
    local name = text:gsub("^%s*%d+%s*/%s*%d+%s+", ""):gsub("%s*:?%s*%d+%s*/%s*%d+%s*$", "")
    return (name:match("^%s*(.-)%s*$"))
end

-- The quest in the log that asks for the item, by the whole name of an item objective:
-- { title, have, need, done }, or nil.
function ns.FeedQuest(name)
    local Q = C_QuestLog
    if type(name) ~= "string" or not (Q and Q.GetNumQuestLogEntries and Q.GetInfo and Q.GetQuestObjectives) then return nil end
    for i = 1, Q.GetNumQuestLogEntries() or 0 do
        local q = Q.GetInfo(i)
        if q and not q.isHeader and not q.isHidden and q.questID and not secret(q.title) then
            for _, o in ipairs(Q.GetQuestObjectives(q.questID) or {}) do
                if o.type == "item" and type(o.text) == "string" and not secret(o.text) and objectiveName(o.text) == name then
                    local have, need = o.numFulfilled or 0, o.numRequired or 0
                    return { title = q.title, have = have, need = need, done = o.finished == true or (need > 0 and have >= need) }
                end
            end
        end
    end
end

-- The farm goal of Gulli Farm Tracker for the item: gained, goal; nil without one.
local function farmGoal(id)
    local c = GulliFarmTrackCharDB
    if type(c) ~= "table" or type(c.targets) ~= "table" then return nil end
    for _, t in ipairs(c.targets) do
        if type(t) == "table" and t.kind == "item" and t.id == id and (tonumber(t.goal) or 0) > 0 then
            local got = type(c.s) == "table" and type(c.s.items) == "table" and c.s.items[id] or 0
            return got, t.goal
        end
    end
end

local function inBags(id)
    local f = (C_Item and C_Item.GetItemCount) or GetItemCount
    return f and f(id) or 0
end

local function canUse(id)
    if C_PlayerInfo and C_PlayerInfo.CanUseItem then
        local ok, yes = pcall(C_PlayerInfo.CanUseItem, id)
        if ok and yes == false then return false end
    end
    return true
end

-- Everything a line says about its item: `unit` and `how` (ns.FeedValue), `total` for the count,
-- and `notes`, the most telling first: { key, text, color, right }. The keys: "quest" (a quest in
-- the log asks for it, `right` its count), "sell" (a quest item no quest in the log asks for that
-- a vendor buys), "questitem", "upgrade", "goal", "bags", "junk".
function ns.FeedFacts(e)
    local out = { notes = {} }
    local id = e.id
    if not id then return out end
    local f = info(id)
    local notes = out.notes
    local quest = ns.FeedQuest(f and f.name or e.name)
    local isQuest = f and f.class == QUEST_CLASS
    if ns.db.feedPrice ~= false and not (quest and not quest.done) then
        out.unit, out.how = ns.FeedValue(id)
        if out.unit then out.total = out.unit * (e.count or 1) end
    end
    if ns.db.feedNotes == false then return out end
    if quest then
        notes[#notes + 1] = { key = "quest", text = S.Hex(S.GOLD) .. L.FEED_QUEST .. "|r " .. quest.title,
                              right = quest.need > 0 and (quest.have .. "/" .. quest.need) or nil, done = quest.done }
        out.quest = quest
    elseif isQuest then
        if f.sell > 0 then notes[#notes + 1] = { key = "sell", text = L.FEED_SELL, color = S.WARN }
        else notes[#notes + 1] = { key = "questitem", text = L.FEED_QUESTITEM, color = S.GOLD_DIM } end
    end
    if f and GEAR[f.class] and e.link and ns.Upgrade and canUse(id) and ns.Upgrade(e.link, id) then
        notes[#notes + 1] = { key = "upgrade", text = L.FEED_UPGRADE, color = S.GOOD }
    end
    local got, goal = farmGoal(id)
    if got then
        notes[#notes + 1] = { key = "goal", text = L.FEED_GOAL:format(got, goal), color = got >= goal and S.GOOD or nil }
    end
    local have = inBags(id)
    if have > (e.count or 1) then notes[#notes + 1] = { key = "bags", text = L.FEED_BAGS:format(have) } end
    if f and f.quality == 0 then notes[#notes + 1] = { key = "junk", text = L.FEED_JUNK, color = S.FAINT } end
    return out
end

-- The facts of a line, read again only after the bags or the quest log changed.
local function factsOf(e)
    if e.kind ~= "item" then return nil end
    if e.fixed then return e.facts end
    if not e.facts or (staleAt and (e.factsAt or 0) < staleAt) then
        e.facts, e.factsAt = ns.FeedFacts(e), now()
    end
    return e.facts
end

-- What the lines that show are worth together: the gold and every priced item.
function ns.FeedTotal(list)
    local total, parts = 0, 0
    for _, e in ipairs(list or entries) do
        if e.kind == "money" then total, parts = total + e.copper, parts + 1
        else
            local f = factsOf(e)
            if f and f.total then total, parts = total + f.total, parts + 1 end
        end
    end
    return total, parts
end

local function trim()
    local cut = now() - ns.FEED_SECONDS
    for i = #entries, 1, -1 do
        if entries[i].at <= cut then table.remove(entries, i) end
    end
    for i = #entries, ns.FEED_KEEP + 1, -1 do entries[i] = nil end
end

local function top(e)
    for i, x in ipairs(entries) do
        if x == e then table.remove(entries, i) break end
    end
    table.insert(entries, 1, e)
    trim()
end

-- Adds a looted item; the same item again while its line shows adds to its count.
function ns.FeedItem(link, count)
    if not ns.FeedOn() or type(link) ~= "string" then return nil end
    local id, name, icon, quality = itemFacts(link)
    local e
    for _, x in ipairs(entries) do
        if x.kind == "item" and ((id and x.id == id) or (not id and x.name == name)) then e = x break end
    end
    if e then e.count = e.count + (count or 1)
    else e = { kind = "item", id = id, name = name, icon = icon, quality = quality, count = count or 1, link = link } end
    e.at, e.facts = now(), nil
    top(e)
    ns.FeedPaint()
    return e
end

-- Adds looted money; it joins the money line that still shows.
function ns.FeedMoney(copper)
    if not ns.FeedOn() or type(copper) ~= "number" or copper <= 0 then return nil end
    local e
    for _, x in ipairs(entries) do if x.kind == "money" then e = x break end end
    if e then e.copper = e.copper + copper
    else e = { kind = "money", copper = copper, icon = "Interface\\Icons\\INV_Misc_Coin_02" } end
    e.at = now()
    top(e)
    ns.FeedPaint()
    return e
end

function ns.FeedEntries() trim(); return entries end
function ns.FeedClear() wipe(entries); ns.FeedPaint() end

---- Events --------------------------------------------------------------------------------

local function money() return GetMoney and GetMoney() or nil end

function ns.OnFeedEvent(event, a1)
    if event == "LOOT_READY" or event == "LOOT_OPENED" then
        if not lootOpen then lastMoney = money() end
        lootOpen = true
    elseif event == "LOOT_CLOSED" then
        lootOpen = false
        lootUntil = now() + ns.FEED_MONEY_WAIT
    elseif event == "PLAYER_MONEY" then
        local m = money()
        if m and lastMoney and (lootOpen or (lootUntil and now() <= lootUntil)) and m > lastMoney then
            ns.FeedMoney(m - lastMoney)
        end
        lastMoney = m
    elseif event == "BAG_UPDATE_DELAYED" or event == "QUEST_LOG_UPDATE" then
        -- the count in the bags and the quest's count follow a moment after the loot line
        if #entries > 0 then staleAt = now() end
    elseif event == "CHAT_MSG_LOOT" then
        local link, n = ns.FeedParse(a1)
        if link then ns.FeedItem(link, n) end
    end
end

---- The panel -----------------------------------------------------------------------------

local function place()
    if not frame then return end
    frame:ClearAllPoints()
    local p = ns.db and ns.db.feedPoint
    if p then frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else frame:SetPoint("RIGHT", UIParent, "CENTER", -180, -40) end
end

local function compact() return ns.db ~= nil and ns.db.feedCompact == true end

local function makeRow()
    local r = CreateFrame("Frame", nil, frame)
    r:SetHeight(ROW_H)
    r:SetPoint("RIGHT", -PAD, 0)
    r.icon = S.IconBox(r, 20)
    r.icon:SetPoint("LEFT", 2, 0)
    r.price = S.Text(r, 12)
    r.price:SetJustifyH("RIGHT")
    r.text = S.Text(r, 12)
    r.text:SetWordWrap(false)
    r.src = S.Text(r, 12, S.FAINT)
    r.src:SetJustifyH("RIGHT")
    r.note = S.Text(r, 12, S.MUTED)
    r.note:SetWordWrap(false)
    -- the mouse only reads: clicks go through to the game world
    if r.SetMouseClickEnabled then
        r:EnableMouse(true)
        r:SetMouseClickEnabled(false)
        r:SetScript("OnEnter", function(self) ns.FeedTip(self, self.entry) end)
        r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end
    return r
end

-- The item's own tooltip with every note of the line under it (the compact look shows only one).
function ns.FeedTip(owner, e)
    if not (e and GameTooltip and GameTooltip.SetOwner) then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if e.kind == "money" then
        GameTooltip:SetText(S.MoneyText(e.copper))
    else
        if e.link and GameTooltip.SetHyperlink then GameTooltip:SetHyperlink(e.link)
        else GameTooltip:SetText(e.name or "?") end
        local f = factsOf(e)
        if f then
            if f.total then
                GameTooltip:AddDoubleLine(L["FEED_SRC_" .. f.how:upper()], S.MoneyText(f.total), S.MUTED[1], S.MUTED[2], S.MUTED[3], 1, 1, 1)
            end
            for _, n in ipairs(f.notes) do
                local c = n.color or S.MUTED
                GameTooltip:AddDoubleLine(n.text, n.right or "", c[1], c[2], c[3], 1, 1, 1)
            end
        end
    end
    GameTooltip:Show()
end

local function build()
    frame = CreateFrame("Frame", "GulliLootFeed", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetSize(WIDTH_MIN, PAD * 2 + ROW_H)
    -- the panel's look is a frame of its own behind the lines, so the bare look can take it away
    frame.back = CreateFrame("Frame", nil, frame)
    frame.back:SetAllPoints()
    if frame.back.SetFrameLevel and frame.GetFrameLevel then
        local lvl = frame:GetFrameLevel()
        frame.back:SetFrameLevel(math.max(0, (type(lvl) == "number" and lvl or 1) - 1))
    end
    S.HudPanel(frame.back)
    rows = {}
    for i = 1, ns.FEED_ROWS_MAX do rows[i] = makeRow() end
    foot = CreateFrame("Frame", nil, frame)
    foot:SetHeight(FOOT_H)
    foot:SetPoint("BOTTOMLEFT", PAD, PAD - 2)
    foot:SetPoint("BOTTOMRIGHT", -PAD, PAD - 2)
    foot.line = foot:CreateTexture(nil, "ARTWORK")
    foot.line:SetHeight(1)
    foot.line:SetPoint("TOPLEFT", 2, 0)
    foot.line:SetPoint("TOPRIGHT", -2, 0)
    foot.line:SetColorTexture(S.GOLD_DIM[1], S.GOLD_DIM[2], S.GOLD_DIM[3], 0.45)
    foot.label = S.Text(foot, 12, S.GOLD_DIM, nil, "bold")
    foot.label:SetPoint("LEFT", 4, -1)
    foot.value = S.Text(foot, 12)
    foot.value:SetPoint("RIGHT", -4, -1)
    foot.value:SetJustifyH("RIGHT")
    S.Mover(frame, { label = L.FR_FEED, hint = L.TIP_MOVE,
        save = function(p, rp, x, y) ns.db.feedPoint = { p, rp, x, y } end,
        reset = function() ns.db.feedPoint = nil; place() end })
    local acc = 0
    frame:SetScript("OnUpdate", function(_, dt)
        acc = acc + (dt or 0)
        if acc < 0.1 then return end
        acc = 0
        ns.FeedTick()
    end)
    place()
    frame:Hide()
end

local function nameText(e)
    local text = S.QualityHex(e.quality) .. (e.name or "?") .. "|r"
    if (e.count or 1) > 1 then text = text .. " |cffffffffx" .. e.count .. "|r" end
    return text
end

local function priceText(f)
    return S.IconTag(ns.FEED_SRC_ICON[f.how], 12) .. " " .. S.MoneyText(f.total)
end

-- What a line shows: `left` and `right` of its first line and, in the detailed look, `note` and
-- `src` of its second (nil: the line is one line high). The compact look puts a quest's count on
-- the right of the first line instead of a price.
function ns.FeedLine(e)
    if e.kind == "money" then return { left = S.MoneyText(e.copper) } end
    local f = factsOf(e) or { notes = {} }
    local out = { left = nameText(e) }
    local n = f.notes[1]
    if f.total then out.right = priceText(f) end
    if compact() then
        if n and n.key == "quest" then
            out.right = S.Hex(S.GOLD) .. L.FEED_QUEST .. "|r" .. (n.right and (" |cffffffff" .. n.right .. "|r") or "")
        end
        return out
    end
    if n then
        out.note, out.noteColor = n.text, n.color or S.MUTED
        if n.key == "quest" and n.right and not f.total then
            out.right = (n.done and S.Hex(S.GOOD) or "|cffffffff") .. n.right .. "|r"
        end
    end
    -- the source's word only beside a note: the price's icon says it on a one-line row
    if f.total and out.note then out.src = L["FEED_SRC_" .. f.how:upper()] end
    return out
end

function ns.FeedFrame()
    if not frame then build() end
    return frame
end

-- Draws the lines; a line in its last FEED_FADE seconds fades, an empty feed hides.
function ns.FeedPaint()
    if not frame then build() end
    local list = sample or ns.FeedEntries()
    local t = now()
    local y, wide = PAD, 0
    local limit = ns.FeedRows()
    -- the bare look: no background and no frame, only the lines (the Unlock mode shows the panel)
    frame.back:SetShown(not (ns.db and ns.db.feedBare == true) or sample ~= nil)
    local function width(fs)
        local w = (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or (fs.GetStringWidth and fs:GetStringWidth()) or 0
        return type(w) == "number" and w or 0
    end
    for i, r in ipairs(rows) do
        local e = i <= limit and list[i] or nil
        r:SetShown(e ~= nil)
        r.entry = e
        if e then
            local ln = ns.FeedLine(e)
            local two = ln.note ~= nil
            local h = two and ROW_H2 or ROW_H
            r:SetHeight(h)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", PAD, -y)
            r:SetPoint("RIGHT", -PAD, 0)
            y = y + h
            r.icon:SetIcon(e.icon)
            r.price:ClearAllPoints(); r.text:ClearAllPoints(); r.note:ClearAllPoints(); r.src:ClearAllPoints()
            r.price:SetPoint("RIGHT", -4, two and 8 or 0)
            r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, two and 8 or 0)
            r.text:SetPoint("RIGHT", r.price, "LEFT", -6, 0)
            r.src:SetPoint("RIGHT", -4, -8)
            r.note:SetPoint("LEFT", r.icon, "RIGHT", 6, -8)
            r.note:SetPoint("RIGHT", r.src, "LEFT", -6, 0)
            r.text:SetText(ln.left)
            r.price:SetText(ln.right or "")
            r.note:SetShown(two); r.src:SetShown(two)
            if two then
                local c = ln.noteColor or S.MUTED
                r.note:SetTextColor(c[1], c[2], c[3], 1)
                r.note:SetText(ln.note)
                r.src:SetText(ln.src or "")
            end
            local w1 = width(r.text) + ((ln.right and ln.right ~= "") and (width(r.price) + 10) or 0)
            local w2 = two and (width(r.note) + ((ln.src and ln.src ~= "") and (width(r.src) + 10) or 0)) or 0
            wide = math.max(wide, 28 + math.max(w1, w2) + 6)
            local left = sample and ns.FEED_SECONDS or (e.at + ns.FEED_SECONDS - t)
            r:SetAlpha(math.max(0, math.min(1, left / ns.FEED_FADE)))
        end
    end
    if #list == 0 then frame:Hide() return end
    local total, parts = ns.FeedTotal(list)
    local showFoot = ns.db ~= nil and ns.db.feedTotal ~= false and ns.db.feedPrice ~= false and parts >= 2
    foot:SetShown(showFoot)
    if showFoot then
        foot.label:SetText(S.Upper and S.Upper(L.FEED_TOTAL) or L.FEED_TOTAL)
        foot.value:SetText(S.MoneyText(total))
        wide = math.max(wide, width(foot.label) + width(foot.value) + 24)
        y = y + FOOT_H
    end
    ns.feedWidth = math.max(WIDTH_MIN, math.min(WIDTH_MAX, math.ceil(wide + PAD * 2)))
    frame:SetSize(ns.feedWidth, y + PAD)
    if not frame:IsShown() then
        frame:Show()
        if S.MotionIn then S.MotionIn(frame, 6) end
    end
end

-- Takes out what is too old and draws again (from the panel's OnUpdate and the tests).
function ns.FeedTick()
    if sample then return end
    trim()
    ns.FeedPaint()
end

-- Unlock mode: sample lines so the player can place it; the real lines come back after.
function ns.MoveFeed(on)
    local f = ns.FeedFrame()
    if on then
        local price, notes = ns.db.feedPrice ~= false, ns.db.feedNotes ~= false
        sample = {
            { kind = "money", copper = 1682, icon = "Interface\\Icons\\INV_Misc_Coin_02" },
            { kind = "item", name = L.SAMPLE_ITEM, quality = 3, count = 1, fixed = true, icon = "Interface\\Icons\\INV_Misc_Gem_Ruby_01",
              facts = { total = price and 18500 or nil, how = "auction", notes = {} } },
            { kind = "item", name = L.SAMPLE_CLOTH, quality = 1, count = 4, fixed = true, icon = "Interface\\Icons\\INV_Fabric_Linen_01",
              facts = { total = price and 620 or nil, how = "vendor",
                        notes = notes and { { key = "bags", text = L.FEED_BAGS:format(43) } } or {} } },
        }
    else
        sample = nil
    end
    ns.FeedPaint()
    if f.SetMoving then f:SetMoving(on) end
end

function ns.SetFeed(on)
    if not ns.db then return end
    ns.db.feed = on and true or false
    if not on then wipe(entries) end
    if frame then ns.FeedPaint() end
end

-- A look or a part of the lines changed: read every line again and draw.
function ns.FeedRestyle()
    for _, e in ipairs(entries) do e.facts = nil end
    if frame and (sample or #entries > 0) then
        if sample then ns.MoveFeed(true) else ns.FeedPaint() end
    end
end
