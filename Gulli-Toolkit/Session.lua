-- The session of the hub's home page: what the core counts by itself since the login (honor,
-- the gold earned, kills, quests, deaths, the best loot) and the card that puts it together with
-- what the modules give through `session` (ns.SessionCard). It only reads the game.
-- The session lives in GulliToolkitCharDB.session: a /reload keeps it, a new login starts one.

local _, ns = ...
local L = ns.L

ns.SES_IDLE = 300    -- a break counts as play only up to this many seconds
ns.SES_BUCKET = 300  -- seconds per column of the graph
ns.SES_RECENT = 900  -- a source that gained this many seconds ago still leads the card
ns.SES_STATS = 3     -- tiles under the big number
ns.SES_BEST = 3      -- the lowest item quality that counts as the best loot (rare)
local MIN_SPAN = 60
local QUEST_WAIT = 5 -- seconds a quest's money may take to arrive

ns.SES_ICON = {
    Gold = "Interface\\Icons\\INV_Misc_Coin_02",
    Honor = "Interface\\Icons\\INV_BannerPVP_01",
    kills = "Interface\\Icons\\Ability_DualWield",
    quests = "Interface\\Icons\\INV_Scroll_03",
    deaths = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
    empty = "Interface\\Icons\\INV_Misc_PocketWatch_01",
}

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end
local function money()
    local m = GetMoney and GetMoney() or 0
    if secret(m) then return nil end
    return tonumber(m)
end
local function repairCost()
    if not GetRepairAllCost then return 0 end
    local ok, cost = pcall(GetRepairAllCost)
    if not ok or secret(cost) then return 0 end
    return tonumber(cost) or 0
end
local function lifetimeKills()
    if not GetPVPLifetimeStats then return nil end
    local ok, hk = pcall(GetPVPLifetimeStats)
    if not ok or secret(hk) then return nil end
    return tonumber(hk)
end
local function unitHonor()
    if not UnitHonor then return nil end
    local ok, cur, max = pcall(function() return UnitHonor("player"), UnitHonorMax and UnitHonorMax("player") end)
    if not ok or secret(cur) or secret(max) then return nil end
    return tonumber(cur), tonumber(max)
end
local function honorCurrency()
    local c = Constants and Constants.CurrencyConsts
    return c and c.HONOR_CURRENCY_ID or 1792
end
local function itemQuality(link)
    local q
    if C_Item and C_Item.GetItemInfo then q = select(3, C_Item.GetItemInfo(link))
    elseif GetItemInfo then q = select(3, GetItemInfo(link)) end
    if secret(q) then return nil end
    return tonumber(q)
end

-- "1 240": thousands apart, so a long number reads at a glance.
function ns.Num(n)
    local s = tostring(math.floor((tonumber(n) or 0) + 0.5))
    local sign, digits = s:match("^(%-?)(%d+)$")
    if not digits then return s end
    digits = digits:reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", "")
    return sign .. digits
end

-- "19k", "3.4k", "240": a pace, short.
function ns.ShortNum(n)
    n = math.floor((tonumber(n) or 0) + 0.5)
    if n >= 10000 then return string.format("%dk", math.floor(n / 1000)) end
    if n >= 1000 then return string.format("%.1fk", n / 1000) end
    return tostring(n)
end

function ns.SesSpan(sec)
    sec = math.max(0, math.floor(tonumber(sec) or 0))
    if sec >= 3600 then return L.SES_HM:format(math.floor(sec / 3600), math.floor(sec % 3600 / 60)) end
    return L.SES_M:format(math.max(1, math.floor(sec / 60)))
end

-- The session -----------------------------------------------------------------------------------

local function fresh(t)
    return { t = t, active = 0, lastActive = t, honor = 0, hk = 0, honorB = {},
             gold = { loot = 0, quest = 0, vendor = 0, repair = 0 }, goldB = {},
             kills = 0, quests = 0, deaths = 0 }
end

local function baselines()
    ns.sesMoney = money()
    ns.sesHonor, ns.sesHonorMax = unitHonor()
    ns.sesRepair = repairCost()
    ns.sesPending, ns.sesSpent, ns.sesLoot = nil, nil, nil
    ns.sesBusy = {}
end

function ns.SesStart(t)
    t = t or time()
    GulliToolkitCharDB = GulliToolkitCharDB or {}
    ns.ses = fresh(t)
    ns.ses.hk0 = lifetimeKills()
    GulliToolkitCharDB.session = ns.ses
    baselines()
end

-- After a /reload the saved session goes on.
function ns.SesResume(t)
    GulliToolkitCharDB = GulliToolkitCharDB or {}
    local s = GulliToolkitCharDB.session
    if type(s) ~= "table" or not tonumber(s.t) then return ns.SesStart(t) end
    local d = fresh(s.t)
    for k, v in pairs(d) do
        if type(s[k]) ~= type(v) then s[k] = v end
    end
    for k, v in pairs(d.gold) do s.gold[k] = tonumber(s.gold[k]) or v end
    ns.ses = s
    baselines()
end

local function step(t, last) return math.min(math.max(0, t - (last or t)), ns.SES_IDLE) end

-- Seconds played in this session, a break counting only ns.SES_IDLE.
function ns.SesActive(t)
    local s = ns.ses
    if not s then return 0 end
    return s.active + step(t or time(), s.lastActive)
end

local function played(s, t)
    s.active = s.active + step(t, s.lastActive)
    s.lastActive = t
end

local function bucket(s, list, n, t)
    local b = math.floor(math.max(0, t - s.t) / ns.SES_BUCKET) + 1
    list[b] = (list[b] or 0) + n
end

local function barsOf(s, list, t)
    local last = math.floor(math.max(0, t - s.t) / ns.SES_BUCKET) + 1
    local bars = {}
    for b = math.max(1, last - ns.SESSION_BARS + 1), last do bars[#bars + 1] = math.max(0, list[b] or 0) end
    return bars
end

local function refresh() if ns.Refresh then ns.Refresh() end end

-- Honor -----------------------------------------------------------------------------------------
-- The game tells about honor in three ways and clients differ in which they have: the honor
-- currency, the honor bar (UnitHonor) and the chat line. The first one that reports a gain is the
-- session's source and the others are ignored, so one kill never counts twice.

function ns.SesHonor(n, src, t)
    local s = ns.ses
    n = tonumber(n)
    if not s or not n or n <= 0 then return false end
    if s.honorSrc and s.honorSrc ~= src then return false end
    t = t or time()
    s.honorSrc = src
    played(s, t)
    s.honor = s.honor + n
    s.honorAt = t
    bucket(s, s.honorB, n, t)
    return true
end

-- The honor of a chat line: its last number ("... (Estimated Honor Points: 12)", "awarded 1,240
-- honor"). Two digits after a point are a fraction, three are thousands.
function ns.HonorIn(msg)
    if type(msg) ~= "string" or secret(msg) then return nil end
    local num
    for m in msg:gmatch("%d[%d%.,]*") do num = m end
    if not num then return nil end
    num = num:gsub("[%.,]+$", "")
    local whole, frac = num:match("^(.*)[%.,](%d+)$")
    if whole and #frac ~= 3 then num = whole end
    return tonumber((num:gsub("[%.,]", "")))
end

function ns.SesHonorBar(t)
    local cur, max = unitHonor()
    if not cur then return end
    local last, lastMax = ns.sesHonor, ns.sesHonorMax
    ns.sesHonor, ns.sesHonorMax = cur, max
    if not last then return end
    local d = cur - last
    if d < 0 then d = (lastMax or last) - last + cur end -- a new honor level
    ns.SesHonor(d, "bar", t)
end

function ns.SesHonorKill()
    local s = ns.ses
    if not s then return end
    local hk = lifetimeKills()
    if hk and s.hk0 then s.hk = math.max(s.hk, hk - s.hk0)
    else s.hk = s.hk + 1 end
end

-- Gold ------------------------------------------------------------------------------------------
-- What the character earned: loot, quest rewards and what a vendor paid, less the repairs. The
-- mailbox, the auction house, the bank and a trade only move money, so nothing counts there.

local INTERACTION = { merchant = "Merchant", mail = "MailInfo", bank = "Banker", auction = "Auctioneer",
                      trade = "TradePartner" }
local FRAMES = { merchant = { "MerchantFrame" }, mail = { "MailFrame" }, bank = { "BankFrame" },
                 auction = { "AuctionHouseFrame", "AuctionFrame" }, trade = { "TradeFrame" } }

-- A close event can go missing, so a flag also ends when the game says the window is gone.
local function stillOpen(what)
    local PIM, E = C_PlayerInteractionManager, Enum and Enum.PlayerInteractionType
    local kind = E and E[INTERACTION[what] or ""]
    if PIM and PIM.IsInteractingWithNpcOfType and kind then
        local ok, on = pcall(PIM.IsInteractingWithNpcOfType, kind)
        if ok and on then return true end
    end
    for _, name in ipairs(FRAMES[what] or {}) do
        local fr = _G[name]
        if type(fr) == "table" and fr.IsShown then return fr:IsShown() and true or false end
    end
    if PIM and PIM.IsInteractingWithNpcOfType and kind then return false end
    return nil
end

local function busy()
    local at = ns.sesBusy or {}
    for what in pairs(at) do
        if stillOpen(what) == false then at[what] = nil end
    end
    local other = false
    for what in pairs(at) do if what ~= "merchant" then other = true end end
    return other, at.merchant == true
end

function ns.SesSetBusy(what, on)
    ns.sesBusy = ns.sesBusy or {}
    ns.sesBusy[what] = on and true or nil
    ns.sesMoney = money() or ns.sesMoney
    if what == "merchant" then ns.sesRepair, ns.sesSpent = repairCost(), nil end
end

local function earn(s, kind, n, t)
    played(s, t)
    s.gold[kind] = s.gold[kind] + n
    s.goldAt = t
    bucket(s, s.goldB, n, t)
end

-- A repair: the bill went down right after money left at a vendor.
function ns.SesRepairCheck(t)
    local s = ns.ses
    if not s then return end
    t = t or time()
    local cost = repairCost()
    local was = ns.sesRepair or cost
    ns.sesRepair = cost
    local spent = ns.sesSpent
    if cost < was and spent and t - spent.t <= 2 then
        s.gold.repair = s.gold.repair + math.min(was - cost, spent.n)
        ns.sesSpent = nil
    end
end

function ns.SesMoney(t)
    local s = ns.ses
    local m = money()
    if not s or not m then return end
    t = t or time()
    local d = m - (ns.sesMoney or m)
    ns.sesMoney = m
    if d == 0 then return end
    local other, merchant = busy()
    if d < 0 then
        if merchant and not other then
            ns.sesSpent = { n = -d, t = t }
            ns.SesRepairCheck(t)
        end
        return
    end
    -- a quest's reward was counted when the quest was handed in
    local p = ns.sesPending
    if p and t - p.t <= QUEST_WAIT then
        local take = math.min(d, p.n)
        p.n, d = p.n - take, d - take
        if p.n <= 0 then ns.sesPending = nil end
    else
        ns.sesPending = nil
    end
    if d <= 0 or other then return end
    earn(s, merchant and "vendor" or "loot", d, t)
    ns.sesLoot = (not merchant) and { n = d, t = t } or nil
end

function ns.SesEarned(s)
    s = s or ns.ses
    if not s then return 0 end
    local g = s.gold
    return g.loot + g.quest + g.vendor - g.repair
end

-- The rest --------------------------------------------------------------------------------------

function ns.SesQuest(reward, t)
    local s = ns.ses
    if not s then return end
    t = t or time()
    played(s, t)
    s.quests = s.quests + 1
    if secret(reward) then return end
    reward = tonumber(reward) or 0
    if reward <= 0 then return end
    -- The money may have come a moment before the quest's event: then it was taken for loot.
    local last = ns.sesLoot
    if last and t - last.t <= 2 and last.n >= reward and s.gold.loot >= reward then
        s.gold.loot, s.gold.quest = s.gold.loot - reward, s.gold.quest + reward
        ns.sesLoot = nil
        return
    end
    earn(s, "quest", reward, t)
    ns.sesPending = { n = reward + ((ns.sesPending and t - ns.sesPending.t <= QUEST_WAIT) and ns.sesPending.n or 0), t = t }
end

function ns.SesKill(msg, t)
    local s = ns.ses
    if not s or type(msg) ~= "string" or secret(msg) or not msg:match("%d") then return end
    played(s, t or time())
    s.kills = s.kills + 1
end

function ns.SesDeath()
    if ns.ses then ns.ses.deaths = ns.ses.deaths + 1 end
end

-- The best thing looted: the highest quality from rare up, the newer one of two alike.
function ns.SesLoot(msg, who, guid)
    local s = ns.ses
    if not s or type(msg) ~= "string" or secret(msg) then return end
    local mine
    if type(guid) == "string" and not secret(guid) and guid ~= "" then
        mine = guid == UnitGUID("player")
    elseif type(who) == "string" and not secret(who) then
        mine = who:match("^[^%-]+") == UnitName("player")
    end
    if not mine then return end
    local link = msg:match("|c%x+|Hitem:.-|h%[.-%]|h|r") or msg:match("|Hitem:.-|h%[.-%]|h")
    local name = link and link:match("%[(.-)%]")
    if not name then return end
    local q = itemQuality(link)
    if not q or q < ns.SES_BEST then return end
    if not s.best or q >= (s.best.q or 0) then s.best = { name = name, q = q } end
end

-- The core's own sources -------------------------------------------------------------------------

local function S() return ns.Skin end
local function moneyText(n, short)
    local sk = S()
    if sk and sk.MoneyText then return sk.MoneyText(n, short) end
    return tostring(math.floor(n / 10000)) .. "g"
end
local function signed(text, n) return (n > 0 and "+" or "") .. text end

local function honorSource(s, t)
    if s.honor <= 0 then return nil end
    local rate = s.honor * 3600 / math.max(MIN_SPAN, ns.SesActive(t))
    local rows = {}
    if s.hk > 0 then rows[1] = { L.SES_HK, ns.Num(s.hk) } end
    return {
        key = "Honor", value = ns.ShortNum(rate), unit = L.SES_HONOR_H,
        line = L.SES_TOTAL:format("+" .. ns.Num(s.honor)), bars = barsOf(s, s.honorB, t), at = s.honorAt,
        tile = { icon = ns.SES_ICON.Honor, value = "+" .. ns.Num(s.honor), label = L.SES_HONOR },
        facts = s.hk > 0 and { L.SES_FACT:format(L.SES_HK, ns.Num(s.hk)) } or nil,
        tip = { icon = ns.SES_ICON.Honor, head = L.SES_HONOR, value = "+" .. ns.Num(s.honor), rows = rows },
    }
end

-- `worth` is what the looted items would bring (a module's `session` gives it, Farm Tracker
-- today). With it the gold is an estimate: the vendor sales step back, since what was sold is
-- in the worth already.
local function goldSource(s, t, worth)
    local g = s.gold
    worth = worth or 0
    local earned = ns.SesEarned(s)
    if worth > 0 then earned = earned - g.vendor + worth end
    if g.loot + g.quest + g.vendor + g.repair + worth <= 0 then return nil end
    local rate = earned * 3600 / math.max(MIN_SPAN, ns.SesActive(t))
    local rows = {}
    for _, k in ipairs(worth > 0 and { "loot", "quest" } or { "loot", "quest", "vendor" }) do
        if g[k] > 0 then rows[#rows + 1] = { L["SES_G_" .. k:upper()], "+" .. moneyText(g[k]) } end
    end
    if worth > 0 then rows[#rows + 1] = { L.SES_G_WORTH, "+" .. moneyText(worth) } end
    if g.repair > 0 then rows[#rows + 1] = { L.SES_G_REPAIR, moneyText(-g.repair), true } end
    local total = signed(moneyText(earned), earned)
    return {
        key = "Gold", value = moneyText(rate, true), unit = L.SES_PER_H,
        line = L.SES_TOTAL:format(total), bars = barsOf(s, s.goldB, t), at = s.goldAt,
        tile = { icon = ns.SES_ICON.Gold, value = signed(moneyText(earned, true), earned), label = L.SES_GOLD },
        facts = g.repair > 0 and { L.SES_FACT:format(L.SES_G_REPAIR, moneyText(-g.repair)) } or nil,
        tip = { icon = ns.SES_ICON.Gold, head = L.SES_GOLD, value = total, rows = rows },
    }
end

ns.SESSION_OWN = { Honor = honorSource, Gold = goldSource }
-- Who leads the card (the first that gained in the last ns.SES_RECENT seconds, else the first
-- with a number), and the order of the tiles under it. Honor and Gold are the core's own.
ns.SESSION_FIRST = { "XP", "Honor", "InstanceLimit", "Gold", "FarmTrack" }
ns.SESSION_TILES = { "Gold", "Honor", "InstanceLimit", "FarmTrack", "XP" }

local function ordered(by, order, rest)
    local out, seen = {}, {}
    for _, k in ipairs(order) do
        if by[k] then out[#out + 1] = by[k]; seen[k] = true end
    end
    for _, src in ipairs(rest) do
        if not seen[src.key] then out[#out + 1] = src; seen[src.key] = true end
    end
    return out
end

-- Everything the session card shows:
-- { span, hero = { key, row, value, unit, line, bars, progress }, stats = { { key, row, icon, value,
--   label } }, facts = { text }, tip = { { icon, head, value, rows = { { left, right, bad } } } } },
-- or { span, empty = true } while nothing happened yet.
function ns.SessionCard(rows, t)
    t = t or time()
    rows = rows or ns.List()
    local s = ns.ses
    local by, all = {}, {}
    local worth = 0
    for _, r in ipairs(rows) do
        local src = ns.SessionOf(r)
        if src then
            src.key = r.key; by[r.key] = src; all[#all + 1] = src
            worth = worth + (src.worth or 0)
        end
    end
    if s then
        for key, fn in pairs(ns.SESSION_OWN) do
            local src = fn(s, t, worth)
            if src then by[key] = src; all[#all + 1] = src end
        end
    end
    table.sort(all, function(a, b) return a.key < b.key end)

    local hero, first
    for _, src in ipairs(ordered(by, ns.SESSION_FIRST, all)) do
        if src.value then
            first = first or src
            if not hero and (not src.at or t - src.at <= ns.SES_RECENT) then hero = src end
        end
    end
    hero = hero or first

    local stats = {}
    for _, src in ipairs(ordered(by, ns.SESSION_TILES, all)) do
        if src ~= hero and src.tile and #stats < ns.SES_STATS then
            stats[#stats + 1] = { key = src.key, row = src.row, icon = src.tile.icon, value = src.tile.value,
                                  label = src.tile.label }
        end
    end
    -- What is left of the row goes to the core's small counters; the others become facts.
    local facts, other = {}, {}
    if s then
        for _, k in ipairs({ "kills", "quests", "deaths" }) do
            local n = s[k] or 0
            if n > 0 then
                local label = L["SES_" .. k:upper()]
                other[#other + 1] = { label, ns.Num(n) }
                if #stats < ns.SES_STATS then
                    stats[#stats + 1] = { key = k, icon = ns.SES_ICON[k], value = ns.Num(n), label = label }
                else
                    facts[#facts + 1] = L.SES_FACT:format(label, ns.Num(n))
                end
            end
        end
    end
    if not hero and stats[1] then
        local top = table.remove(stats, 1)
        hero = { key = top.key, row = top.row, value = top.value, unit = top.label, line = "", bars = {} }
    end
    local span = (hero and hero.span and hero.span ~= "") and hero.span or ns.SesSpan(ns.SesActive(t))
    if not hero then return { span = span, empty = true } end

    for _, src in ipairs(ordered(by, ns.SESSION_FIRST, all)) do
        for _, f in ipairs(src.facts or {}) do facts[#facts + 1] = f end
    end
    local best = s and s.best
    local sk = S()
    local bestText = best and ((sk and sk.QualityHex and sk.QualityHex(best.q) or "") .. best.name .. "|r")
    if best then facts[#facts + 1] = L.SES_FACT:format(L.SES_BEST, bestText) end

    local tip = {}
    for _, src in ipairs(ordered(by, ns.SESSION_FIRST, all)) do
        if src.tip then tip[#tip + 1] = src.tip end
    end
    if best then other[#other + 1] = { L.SES_BEST, bestText } end
    if #other > 0 then tip[#tip + 1] = { icon = ns.SES_ICON.kills, head = L.SES_OTHER, value = "", rows = other } end

    return { span = span, hero = hero, stats = stats, facts = facts, tip = tip }
end

-- Events ----------------------------------------------------------------------------------------

local BUSY = {
    MERCHANT_SHOW = { "merchant", true }, MERCHANT_CLOSED = { "merchant", false },
    MAIL_SHOW = { "mail", true }, MAIL_CLOSED = { "mail", false },
    BANKFRAME_OPENED = { "bank", true }, BANKFRAME_CLOSED = { "bank", false },
    AUCTION_HOUSE_SHOW = { "auction", true }, AUCTION_HOUSE_CLOSED = { "auction", false },
    TRADE_SHOW = { "trade", true }, TRADE_CLOSED = { "trade", false },
}

function ns.SesEvent(event, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12)
    if event == "PLAYER_ENTERING_WORLD" then
        -- a1: a real login, which starts a new session; a2: a /reload, which keeps it.
        if a1 and not a2 then ns.SesStart() elseif not ns.ses then ns.SesResume() else baselines() end
        return
    end
    if not ns.ses then return end
    if event == "PLAYER_MONEY" then
        ns.SesMoney()
    elseif event == "UPDATE_INVENTORY_DURABILITY" then
        ns.SesRepairCheck()
    elseif event == "QUEST_TURNED_IN" then
        ns.SesQuest(a3)
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        ns.SesKill(a1)
    elseif event == "PLAYER_DEAD" then
        ns.SesDeath()
    elseif event == "CHAT_MSG_LOOT" then
        -- every looter of a raid passes here: no redraw for it
        ns.SesLoot(a1, a2, a12)
        return
    elseif event == "CHAT_MSG_COMBAT_HONOR_GAIN" then
        ns.SesHonor(ns.HonorIn(a1), "chat")
    elseif event == "CURRENCY_DISPLAY_UPDATE" then
        if not secret(a1) and a1 == honorCurrency() and not secret(a3) then ns.SesHonor(a3, "currency") end
    elseif event == "HONOR_XP_UPDATE" then
        ns.SesHonorBar()
    elseif event == "PLAYER_PVP_KILLS_CHANGED" then
        ns.SesHonorKill()
    elseif BUSY[event] then
        ns.SesSetBusy(BUSY[event][1], BUSY[event][2])
    elseif event == "LOOT_READY" then
        -- Looting: no vendor, mailbox, bank or trade window is in use.
        ns.sesBusy = {}
    end
    refresh()
end

local f = CreateFrame("Frame")
local EVENTS = { "PLAYER_ENTERING_WORLD", "PLAYER_MONEY", "UPDATE_INVENTORY_DURABILITY", "QUEST_TURNED_IN",
                 "CHAT_MSG_COMBAT_XP_GAIN", "PLAYER_DEAD", "CHAT_MSG_LOOT", "CHAT_MSG_COMBAT_HONOR_GAIN",
                 "CURRENCY_DISPLAY_UPDATE", "HONOR_XP_UPDATE", "PLAYER_PVP_KILLS_CHANGED", "LOOT_READY" }
for e in pairs(BUSY) do EVENTS[#EVENTS + 1] = e end
-- One name a client lacks must not stop the rest.
for _, e in ipairs(EVENTS) do
    if not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(e) then
        pcall(f.RegisterEvent, f, e)
    end
end
f:SetScript("OnEvent", function(_, event, ...) ns.SesEvent(event, ...) end)
