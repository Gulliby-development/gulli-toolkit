-- The loot feed (switch `feed`): a small panel of what the player just looted, the gold and each
-- item with its icon, count and quality colour. It works with fast loot and auto loot, whatever
-- loot window shows, and every line fades away after a few seconds. Items come from the loot chat
-- (the game's own "You receive loot" lines), money from the money that came in while loot was open.

local _, ns = ...
local L = ns.L
local S = ns.Skin

ns.FEED_ROWS = 6        -- lines shown at most, newest on top
ns.FEED_SECONDS = 6     -- how long a line stays
ns.FEED_FADE = 1.5      -- the last part of that it fades
ns.FEED_MONEY_WAIT = 2  -- money that comes in this long after the loot closed still counts
local ROW_H, WIDTH, PAD = 26, 240, 6

local entries = {}      -- newest first: { kind = "item"|"money", id, icon, name, quality, count, copper, at }
local frame, rows, sample
local lootOpen, lootUntil, lastMoney

local function now() return GetTime and GetTime() or 0 end
local function secret(v) return issecretvalue and issecretvalue(v) end

function ns.FeedOn() return ns.db ~= nil and ns.db.feed == true and not ns.paused end

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

local function trim()
    local cut = now() - ns.FEED_SECONDS
    for i = #entries, 1, -1 do
        if entries[i].at <= cut then table.remove(entries, i) end
    end
    for i = #entries, ns.FEED_ROWS + 1, -1 do entries[i] = nil end
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
    else e = { kind = "item", id = id, name = name, icon = icon, quality = quality, count = count or 1 } end
    e.at = now()
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

local function makeRow(i)
    local r = CreateFrame("Frame", nil, frame)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", PAD, -PAD - (i - 1) * ROW_H)
    r:SetPoint("RIGHT", -PAD, 0)
    r.icon = S.IconBox(r, 20)
    r.icon:SetPoint("LEFT", 2, 0)
    r.text = S.Text(r, 12)
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.text:SetPoint("RIGHT", -2, 0)
    r.text:SetWordWrap(false)
    return r
end

local function build()
    frame = CreateFrame("Frame", "GulliLootFeed", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetSize(WIDTH, PAD * 2 + ROW_H)
    S.HudPanel(frame)
    rows = {}
    for i = 1, ns.FEED_ROWS do rows[i] = makeRow(i) end
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

local function line(e)
    if e.kind == "money" then return S.MoneyText(e.copper) end
    local text = S.QualityHex(e.quality) .. (e.name or "?") .. "|r"
    if (e.count or 1) > 1 then text = text .. " |cffffffffx" .. e.count .. "|r" end
    return text
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
    for i, r in ipairs(rows) do
        local e = list[i]
        r:SetShown(e ~= nil)
        if e then
            r.icon:SetIcon(e.icon)
            r.text:SetText(line(e))
            local left = sample and ns.FEED_SECONDS or (e.at + ns.FEED_SECONDS - t)
            r:SetAlpha(math.max(0, math.min(1, left / ns.FEED_FADE)))
        end
    end
    if #list == 0 then frame:Hide() return end
    frame:SetHeight(PAD * 2 + math.min(#list, ns.FEED_ROWS) * ROW_H)
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
        sample = {
            { kind = "money", copper = 1682, icon = "Interface\\Icons\\INV_Misc_Coin_02" },
            { kind = "item", name = L.SAMPLE_ITEM, quality = 3, count = 1, icon = "Interface\\Icons\\INV_Misc_Gem_Ruby_01" },
            { kind = "item", name = L.SAMPLE_CLOTH, quality = 1, count = 4, icon = "Interface\\Icons\\INV_Fabric_Linen_01" },
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
