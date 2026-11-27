-- The mailbox: Take all, take by kind, one letter's Take and Return, a visit total, warnings
-- about letters that run out (on every character), a log, and the send side: names to tap,
-- quick attach by kind, all gold to another character, mailing rules (by default: the goods go to
-- the own character whose profession uses them) and a Send button of its own.
-- Nothing is ever sent without the player's own click on Send.

local ADDON, ns = ...
local L = ns.L

local WAIT_STEP = 0.1  -- after the inbox says it changed, a short breath before the next take
local TIMEOUT = 1.5    -- the next take at the latest, when no inbox event comes
local RECENT_MAX = 10
local LOG_MAX = 50
local SOON_DAYS = 3    -- a letter with items or money this close to its end gets a warning
local ATTACH = ATTACHMENTS_MAX_RECEIVE or 12
local SEND_MAX = ATTACHMENTS_MAX_SEND or 12
ns.POSTAGE = 30   -- copper, a letter without items
local TRIES = 3 -- a take that changes nothing this often is one the game refuses
local WAIT_MAX = 70 -- the server sends the next letters at most once a minute
local WAIT_STEP_SERVER = 5

ns.OPT_ICON = { panel = "Interface\\Icons\\INV_Letter_15" }

-- Quick attach: item class 7 (trade goods) subclasses, and class 3 (gems). `sample` is a
-- typical item whose icon the tile shows when the bags hold none; `all` takes every kind above it.
ns.ATTACH_KINDS = {
    { key = "cloth", class = 7, sub = 5, sample = 2589 },       -- Linen Cloth
    { key = "herb", class = 7, sub = 9, sample = 2447 },        -- Peacebloom
    { key = "ore", class = 7, sub = 7, sample = 2770 },         -- Copper Ore
    { key = "leather", class = 7, sub = 6, sample = 2318 },     -- Light Leather
    { key = "elemental", class = 7, sub = 10, sample = 7067 },  -- Elemental Earth
    { key = "enchanting", class = 7, sub = 12, sample = 10940 }, -- Strange Dust
    -- WoW Forever files the mining gems under Trade Goods, Other (7/11), with spices, mojo and
    -- crate quest items, so the gems go by id (and class 3 Gem for a client that has it).
    { key = "gem", class = 3, ids = {
        [774] = true, [818] = true, [1206] = true, [1210] = true, [1529] = true, [1705] = true,
        [3864] = true, [5498] = true, [5500] = true, [7909] = true, [7910] = true, [7971] = true,
        [11382] = true, [12361] = true, [12363] = true, [12364] = true, [12799] = true,
        [12800] = true, [13926] = true,
    }, sample = 774 },                                          -- Malachite
    -- Potions, elixirs, flasks, scrolls, oils and stones (Consumable 0: 1-4, 6 and 8 for the
    -- temporary weapon buffs); not food, bandages or explosives, and not in "all goods".
    { key = "consumable", class = 0, subs = { [1] = true, [2] = true, [3] = true, [4] = true, [6] = true, [8] = true },
      goods = false, sample = 13446 },                          -- Major Healing Potion
    { key = "all", all = true, icon = "Interface\\Icons\\INV_Misc_Bag_10" },
    -- Any item a price addon values above what a vendor pays, after the auction's cut: for the
    -- character who sells at the auction. Only on the send side.
    { key = "auction", auction = true, send = true, icon = "Interface\\Minimap\\Tracking\\Auctioneer" },
}
ns.AH_CUT = 0.05

-- Game API wrappers.
local C = C_Container or {}
local function numMail()
    if not GetInboxNumItems then return 0, 0 end
    local shown, total = GetInboxNumItems()
    return shown or 0, total or shown or 0
end
local function header(i)
    local _, _, sender, subject, money, cod, days, items, wasRead, wasReturned, _, canReply, isGM =
        GetInboxHeaderInfo(i)
    return { sender = sender, subject = subject, money = money or 0, cod = cod or 0, items = items or 0, gm = isGM,
             days = days or 30, read = wasRead, returned = wasReturned, canReply = canReply }
end
local function invoice(i)
    if not GetInboxInvoiceInfo then return nil end
    return (GetInboxInvoiceInfo(i))
end
local function freeSlots()
    local free = 0
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
        local f, family = (C.GetContainerNumFreeSlots or GetContainerNumFreeSlots)(bag)
        if (family or 0) == 0 then free = free + (f or 0) end
    end
    return free
end
local function numSlots(bag) return (C.GetContainerNumSlots or GetContainerNumSlots)(bag) or 0 end
-- The last bag the player wears: WoW Forever has the reagent bag (5) after the four bags.
local function lastBag() return NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 end
local function slotItem(bag, slot)
    if C.GetContainerItemInfo then
        local i = C.GetContainerItemInfo(bag, slot)
        if i then return i.itemID, i.isLocked end
        return nil
    end
    local _, _, locked, _, _, _, _, _, _, id = GetContainerItemInfo(bag, slot)
    return id, locked
end
local function itemIcon(id)
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
    return GetItemIcon and GetItemIcon(id) or nil
end
local function itemName(id)
    return (((C_Item and C_Item.GetItemInfo) or GetItemInfo)(id))
end
local function stackCount(bag, slot)
    if C.GetContainerItemInfo then
        local i = C.GetContainerItemInfo(bag, slot)
        return i and i.stackCount or 1
    end
    local _, n = GetContainerItemInfo(bag, slot)
    return n or 1
end
local function itemClass(id)
    local _, _, _, _, _, _, _, _, _, _, _, classID, subclassID = ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(id)
    return classID, subclassID
end
-- The class of an item the client may not have loaded yet (mail items often are not):
-- GetItemInfoInstant knows it at once.
local function classNow(id)
    if C_Item and C_Item.GetItemInfoInstant then
        local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(id)
        if classID then return classID, subclassID end
    end
    return itemClass(id)
end
local function bound(bag, slot)
    if C_Item and C_Item.IsBound and ItemLocation and ItemLocation.CreateFromBagAndSlot then
        return C_Item.IsBound(ItemLocation:CreateFromBagAndSlot(bag, slot)) and true or false
    end
    return false
end
local function useItem(bag, slot) (C.UseContainerItem or UseContainerItem)(bag, slot) end
local function money() return GetMoney and GetMoney() or 0 end
local function checkInbox() if CheckInbox then CheckInbox() end end
local function say(msg) print("|cff9ad0ffGulli Mail|r: " .. msg) end
local function notify(msg) if GulliToolkit and GulliToolkit.Notify then GulliToolkit.Notify("Mail", msg) end end
-- The one realm saved in the tables per realm, or nil when there is none or more than one.
local function savedRealm()
    local found
    for _, t in ipairs({ ns.db.alts, ns.db.chars, ns.db.recent }) do
        for r in pairs(t or {}) do
            if r ~= "" then
                if found and found ~= r then return nil end
                found = r
            end
        end
    end
    return found
end
-- Some WoW Forever sessions give an empty realm name: then the last realm seen stands in, else
-- the one realm saved, so one realm never splits into two.
local function realm()
    local r = GetRealmName and GetRealmName()
    if type(r) == "string" and r ~= "" then
        if ns.db then ns.db.realm = r end
        return r
    end
    return ns.db and (ns.db.realm or savedRealm()) or ""
end
ns.Realm = realm
-- The player's whole name. WoW Forever names have a surname ("Bullet Rainy"): UnitName gives the
-- first name alone, and a letter to the first name alone finds nobody. The game's own NameUtil
-- joins the surname on such a client and leaves the name alone elsewhere.
local function me()
    local first = UnitName("player")
    if NameUtil and NameUtil.GetUnmodifiedUnitFullName then
        local ok, full = pcall(NameUtil.GetUnmodifiedUnitFullName, "player")
        if ok and type(full) == "string" and not (issecretvalue and issecretvalue(full)) and full ~= "" then
            return full
        end
    end
    return first or "?"
end
ns.Me = me
local function protected(id)
    return GulliToolkit and GulliToolkit.IsProtected and GulliToolkit.IsProtected(id) or false
end
local function sendOpen() return SendMailFrame and SendMailFrame.IsShown and SendMailFrame:IsShown() end

function ns.Money(copper)
    copper = math.floor(copper or 0)
    if GetCoinTextureString then return GetCoinTextureString(copper >= 10000 and copper - copper % 100 or copper) end
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if (c > 0 and g == 0) or #parts == 0 then parts[#parts + 1] = c .. "c" end
    return table.concat(parts, " ")
end

-- The kind of a letter: "sold", "bought", "expired" (other auction house mail: expired,
-- cancelled, outbid), "player", or "system" (GM and other letters nobody can answer).
function ns.Kind(i, h)
    h = h or header(i)
    local inv = invoice(i)
    if inv == "seller" or inv == "seller_temp_invoice" then return "sold" end
    if inv == "buyer" then return "bought" end
    if h.gm then return "system" end
    if h.canReply then return "player" end
    return "expired"
end

-- Does Take all take from this letter? Cash on delivery and GM letters never.
function ns.Allowed(kind, h)
    return not (h.cod > 0 or h.gm or kind == "system")
end

-- What Take all would get: money, item count, letters left out (cash on delivery, GM), and
-- the letters still on the server (it shows at most 50 at a time).
function ns.Summary()
    local shown, total = numMail()
    local s = { money = 0, items = 0, cod = 0, letters = shown, more = math.max(0, total - shown) }
    for i = 1, shown do
        local h = header(i)
        if not ns.Allowed(ns.Kind(i, h), h) then s.cod = s.cod + 1
        else
            s.money = s.money + h.money
            s.items = s.items + h.items
        end
    end
    return s
end

-- The letters for the panel: { i, sender, subject, money, items, cod, days, kind, canReturn }.
function ns.Letters()
    local out = {}
    for i = 1, (numMail()) do
        local h = header(i)
        h.i = i
        h.kind = ns.Kind(i, h)
        h.canReturn = h.canReply and not h.returned and not h.gm and ReturnInboxItem ~= nil
        out[#out + 1] = h
    end
    return out
end

-- A take is known by its place and what it is. Going from the last letter back, a take
-- that worked moves on to another place; the same key again means the game refused it.
-- `what` (without the place) counts each refused thing once.
local function takeKey(i, h, what)
    local w = (h.sender or "?") .. "\1" .. (h.subject or "") .. "\1" .. what
    return i .. "\1" .. w, w
end

-- The next thing to take, from the last letter back: { i, j, kind = "money"|"item", key,
-- amount, letter }, "full" when the next one is an item and the bags are full, or nil.
-- `skip` holds the keys the game refused; `only` limits it to one letter (its index).
-- `kind` (a key of ns.ATTACH_KINDS) takes only the items of that kind, and no money.
function ns.Next(skip, only, kind)
    local want = kind and ns.KindOf(kind)
    if kind and not want then return nil end
    skip = skip or {}
    local from, to = numMail(), 1
    if only then
        if only > from then return nil end
        from, to = only, only
    end
    for i = from, to, -1 do
        local h = header(i)
        local kind = ns.Kind(i, h)
        if ns.Allowed(kind, h) then
            local k, what = takeKey(i, h, "money")
            if h.money > 0 and not want and not skip[k] then
                return { i = i, kind = "money", key = k, what = what, amount = h.money, letter = kind, sender = h.sender }
            end
            if h.items > 0 then
                for j = 1, ATTACH do
                    local name, id, _, count = GetInboxItem(i, j)
                    if name and want then
                        local class, sub = classNow(id)
                        if not (id and ns.KindHas(want, class, sub, id)) then name = nil end
                    end
                    if name then
                        k, what = takeKey(i, h, j .. ":" .. tostring(id or name))
                        if not skip[k] then
                            if freeSlots() <= 0 then return "full" end
                            return { i = i, j = j, kind = "item", key = k, what = what, letter = kind,
                                     sender = h.sender, name = name, count = count or 1 }
                        end
                    end
                end
            end
        end
    end
    return nil
end

-- One take. Returns "money", "item", "full" or nil when nothing is left.
function ns.TakeOne(skip)
    local c = ns.Next(skip)
    if type(c) ~= "table" then return c end
    if c.kind == "money" then TakeInboxMoney(c.i) else TakeInboxItem(c.i, c.j) end
    return c.kind, c.amount, c
end

-- This visit: money and items taken, and the share of money from auction sales.
ns.visit = { money = 0, sold = 0, items = 0 }

local function logTake(c)
    -- a player who sent a letter is someone to write back to
    if c.letter == "player" and type(c.sender) == "string" then ns.Remember(c.sender) end
    local log = ns.db.log
    local last = log[1]
    -- One line per letter: the takes of one letter join.
    if last and last.sender == c.sender and last.kind == c.letter and last.t and time() - last.t < 5 then
        last.money = last.money + (c.kind == "money" and c.amount or 0)
        last.items = last.items + (c.kind == "item" and (c.count or 1) or 0)
        last.t = time()
        return
    end
    table.insert(log, 1, { t = time(), sender = c.sender or "?", kind = c.letter,
                           money = c.kind == "money" and c.amount or 0, items = c.kind == "item" and (c.count or 1) or 0 })
    while #log > LOG_MAX do table.remove(log) end
end

-- A take worked: count it.
local function done(t, c)
    if c.kind == "item" then
        t.items = t.items + 1
        ns.visit.items = ns.visit.items + 1
    else
        ns.visit.money = ns.visit.money + (c.amount or 0)
        if c.letter == "sold" then ns.visit.sold = ns.visit.sold + (c.amount or 0) end
    end
    logTake(c)
end

-- Take all, one thing per step, the next step when the inbox says it changed (or after
-- TIMEOUT). A thing the game refuses (a unique item the bags already hold) is tried TRIES
-- times, then left in its letter and counted. When the mailbox shows fewer letters than the
-- server holds, it asks for the rest and goes on. `letters` (indices, any order) limits it to
-- those letters, whatever the switches say. `kind` (a key of ns.ATTACH_KINDS) takes only
-- the items of that kind from every letter, whatever the switches say, and no money.
function ns.TakeAll(letters, kind)
    if ns.taking then return end
    local t = { items = 0, failed = 0, skip = {}, refused = {}, start = money(), tries = 0, kind = kind }
    if letters then
        t.queue = {}
        for _, i in ipairs(letters) do t.queue[#t.queue + 1] = i end
        table.sort(t.queue, function(a, b) return a > b end)
        t.count = numMail()
    end
    ns.taking = t
    local function finish(why)
        ns.taking = nil
        local got = math.max(0, money() - t.start)
        local msg = L.TAKEN:format(t.items, ns.Money(got))
        if t.failed > 0 then msg = msg .. " " .. L.FAILED:format(t.failed) end
        if why == "full" then msg = msg .. " " .. L.FULL end
        say(msg)
        if ns.Refresh then ns.Refresh() end
    end
    local step
    local function later(delay)
        t.token = (t.token or 0) + 1
        local token = t.token
        t.waitEvent = delay == nil
        C_Timer.After(delay or TIMEOUT, function() if t.token == token then step() end end)
    end
    t.later = later
    -- The letter Take selected works on now; a letter that went (its count dropped) is done.
    local function current()
        if not t.queue then return nil end
        local n = numMail()
        if n < t.count then table.remove(t.queue, 1); t.count = n end
        return t.queue[1]
    end
    step = function()
        if ns.taking ~= t or not ns.open then if ns.taking == t then ns.taking = nil end return end
        local c
        if t.queue then
            while true do
                local i = current()
                if not i then c = nil break end
                c = ns.Next(t.skip, i)
                if c ~= nil then break end
                table.remove(t.queue, 1)
            end
        else
            c = ns.Next(t.skip, nil, t.kind)
        end
        -- The last take is done once something else comes next; the same thing again means
        -- the game did not take it.
        if t.last and not (type(c) == "table" and c.key == t.last.key) then
            done(t, t.last)
            t.last, t.tries = nil, 0
        end
        if type(c) == "table" and t.last and c.key == t.last.key then
            t.tries = t.tries + 1
            if t.tries >= TRIES then
                t.skip[c.key] = true
                if not t.refused[c.what] then t.refused[c.what] = true; t.failed = t.failed + 1 end
                t.last, t.tries = nil, 0
                return step()
            end
        end
        if type(c) == "table" then
            t.waitSince = nil
            if c.kind == "money" then TakeInboxMoney(c.i) else TakeInboxItem(c.i, c.j) end
            t.last = c
            if ns.Refresh then ns.Refresh() end
            later()
            return
        end
        if c == nil and not t.queue then
            local shown, total = numMail()
            if total > shown then
                t.waitSince = t.waitSince or GetTime()
                if GetTime() - t.waitSince < WAIT_MAX then
                    t.waiting = total - shown
                    checkInbox()
                    if ns.Refresh then ns.Refresh() end
                    later(WAIT_STEP_SERVER)
                    return
                end
            end
        end
        finish(c)
    end
    step()
end

-- The inbox changed: the take is through, go on after a short breath.
-- The mailbox interaction type (Enum.PlayerInteractionType.MailInfo).

-- The mailbox closed (left, walked away, or its frame hid): tell the visit once, stop taking
-- and hide the panel. Every way of closing comes here; a second call does nothing new.
function ns.Closed()
    if ns.open and ns.visit and (ns.visit.money > 0 or ns.visit.items > 0) then
        notify(L.VISIT:format(ns.visit.items, ns.Money(ns.visit.money), ns.Money(ns.visit.sold)))
    end
    ns.open, ns.taking = false, nil
    if ns.HidePanel then ns.HidePanel() end
end

function ns.InboxChanged()
    local t = ns.taking
    if not t then return end
    t.waiting = nil
    if t.waitEvent and t.later then t.later(WAIT_STEP) end
end

-- Sends a player's letter back. Only letters a player sent, not yet returned.
function ns.Return(i)
    local h = header(i)
    if not h.canReply or h.returned or h.gm or not ReturnInboxItem then return false end
    ReturnInboxItem(i)
    return true
end

-- Letters ------------------------------------------------------------------------------------

-- Letters with items or money that run out within SOON_DAYS: { n, days } of this mailbox.
function ns.Expiring()
    local n, soonest = 0, nil
    for i = 1, (numMail()) do
        local h = header(i)
        if (h.items > 0 or h.money > 0) and h.days < SOON_DAYS then
            n = n + 1
            soonest = math.min(soonest or h.days, h.days)
        end
    end
    return n, soonest
end

-- Moves what was saved under an empty realm name onto the realm.
function ns.MergeRealmless()
    local r = realm()
    if r == "" then return end
    local alts = ns.db.alts[""]
    if alts then
        ns.db.alts[r] = ns.db.alts[r] or {}
        for faction, names in pairs(alts) do
            ns.db.alts[r][faction] = ns.db.alts[r][faction] or {}
            for name in pairs(names) do ns.db.alts[r][faction][name] = true end
        end
        ns.db.alts[""] = nil
    end
    local chars = ns.db.chars[""]
    if chars then
        ns.db.chars[r] = ns.db.chars[r] or {}
        for name, c in pairs(chars) do
            local other = ns.db.chars[r][name]
            if not other or (other.seen or 0) < (c.seen or 0) then ns.db.chars[r][name] = c end
        end
        ns.db.chars[""] = nil
    end
    local recent = ns.db.recent[""]
    if recent then
        -- the names sent to without a realm are the newer ones
        local list, have = {}, {}
        for _, part in ipairs({ recent, ns.db.recent[r] or {} }) do
            for _, name in ipairs(part) do
                if not have[name:lower()] and #list < RECENT_MAX then
                    list[#list + 1] = name; have[name:lower()] = true
                end
            end
        end
        ns.db.recent[r], ns.db.recent[""] = list, nil
    end
end

-- Saves when this character's letters with things in them run out, for the other characters'
-- warnings: chars[realm][name] = { ends = { time, ... } }.
function ns.Snapshot()
    local r = realm()
    ns.db.chars[r] = ns.db.chars[r] or {}
    local ends = {}
    for i = 1, (numMail()) do
        local h = header(i)
        if h.items > 0 or h.money > 0 then ends[#ends + 1] = time() + math.floor(h.days * 86400) end
    end
    ns.db.chars[r][me()] = { ends = ends, seen = time() }
end

-- Other characters of this realm with letters that run out within SOON_DAYS:
-- { { name, n, days } }.
function ns.OthersExpiring()
    local out = {}
    for name, c in pairs(ns.db.chars[realm()] or {}) do
        if name ~= me() then
            local n, soonest = 0, nil
            for _, e in ipairs(c.ends or {}) do
                local days = (e - time()) / 86400
                if days > 0 and days < SOON_DAYS then
                    n = n + 1
                    soonest = math.min(soonest or days, days)
                end
            end
            if n > 0 then out[#out + 1] = { name = name, n = n, days = soonest } end
        end
    end
    table.sort(out, function(a, b) return a.days < b.days end)
    return out
end

local function warnOthers()
    for _, o in ipairs(ns.OthersExpiring()) do
        local msg = L.ALT_EXPIRING:format(o.name, o.n, math.max(1, math.floor(o.days + 0.5)))
        say(msg)
        notify(msg)
    end
end

-- Names --------------------------------------------------------------------------------------

local function short(name) return name and (name:match("^([^%-]+)") or name) end

-- Names for a new letter: the player's other characters on this realm and faction, then the
-- recent recipients, friends and guild members. `filter` keeps the names that contain it.
function ns.Names(filter)
    local out, seen = {}, { [me():lower()] = true }
    filter = filter and filter ~= "" and filter:lower() or nil
    local function add(name, group)
        name = short(name)
        local key = name and name:lower()
        if not name or name == "" or seen[key] then return end
        if filter and not key:find(filter, 1, true) then return end
        seen[key] = true
        out[#out + 1] = { name = name, alt = group == "alt", group = group }
    end
    local alts = ns.db.alts[realm()] and ns.db.alts[realm()][UnitFactionGroup("player")] or {}
    local sorted = {}
    for name in pairs(alts) do sorted[#sorted + 1] = name end
    table.sort(sorted)
    for _, name in ipairs(sorted) do add(name, "alt") end
    for _, name in ipairs(ns.db.recent[realm()] or {}) do add(name, "recent") end
    -- players whose letters were taken here, newest first
    for _, e in ipairs(ns.db.log or {}) do
        if e.kind == "player" and type(e.sender) == "string" then add(e.sender, "recent") end
    end
    local friends = {}
    if C_FriendList and C_FriendList.GetNumFriends then
        for i = 1, C_FriendList.GetNumFriends() or 0 do
            local f = C_FriendList.GetFriendInfoByIndex(i)
            if f and f.name then friends[#friends + 1] = f.name end
        end
    end
    table.sort(friends)
    for _, name in ipairs(friends) do add(name, "friend") end
    local guild = {}
    if IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
        for i = 1, GetNumGuildMembers() or 0 do
            local name = GetGuildRosterInfo(i)
            if name then guild[#guild + 1] = name end
        end
    end
    table.sort(guild)
    for _, name in ipairs(guild) do add(name, "guild") end
    return out
end

function ns.Remember(name)
    name = name and strtrim(name)
    if not name or name == "" then return end
    local list = ns.db.recent[realm()] or {}
    ns.db.recent[realm()] = list
    for i = #list, 1, -1 do if list[i]:lower() == name:lower() then table.remove(list, i) end end
    table.insert(list, 1, name)
    while #list > RECENT_MAX do table.remove(list) end
end

-- Opens the game's send tab when it is not open. Returns whether it is open now.
function ns.OpenSend()
    if sendOpen() then return true end
    if not ns.open or ns.paused then return false end
    if MailFrameTab2 and MailFrameTab2.Click then MailFrameTab2:Click() end
    return sendOpen() and true or false
end

function ns.Pick(name)
    ns.to = name
    ns.OpenSend()
    if SendMailNameEditBox then SendMailNameEditBox:SetText(name) end
    if ns.RefreshSend then ns.RefreshSend() end
end

-- Sending ------------------------------------------------------------------------------------

function ns.KindOf(key)
    for _, k in ipairs(ns.ATTACH_KINDS) do if k.key == key then return k end end
end
local kindOf = ns.KindOf

-- Whether an item sells for more at the auction (after its cut) than at a vendor. Needs a
-- price addon: without one nothing counts.
function ns.WorthAuction(id)
    local S = ns.Skin
    if not (id and S and S.AuctionPrice) then return false end
    local price = S.AuctionPrice(id)
    if not price or price <= 0 then return false end
    local sell = select(11, ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(id)) or 0
    return price * (1 - ns.AH_CUT) > sell
end

-- Whether an item of this class and subclass (and id) belongs to the kind (`all`: to any
-- trade goods kind above it).
function ns.KindHas(k, class, sub, id)
    if k.auction then return ns.WorthAuction(id) end
    if k.all then
        for _, o in ipairs(ns.ATTACH_KINDS) do
            if not o.all and not o.auction and o.goods ~= false and ns.KindHas(o, class, sub, id) then return true end
        end
        return false
    end
    if k.ids and id and k.ids[id] then return true end
    if k.subs then return class == k.class and sub ~= nil and k.subs[sub] == true end
    return class == k.class and (not k.sub or sub == k.sub)
end

-- Free attachment places in the letter being written.
function ns.Room()
    local room = SEND_MAX
    if GetSendMailItem then
        for j = 1, SEND_MAX do if GetSendMailItem(j) then room = room - 1 end end
    end
    return room
end

-- The icon of a kind without looking in the bags: its sample item, or its own icon.
function ns.KindIcon(key)
    local k = kindOf(key)
    if not k then return nil end
    return k.icon or (k.sample and itemIcon(k.sample)) or nil
end

-- What a quick-attach tile shows: { icon, stacks, going (stacks that fit), total (items),
-- top (name of the item with most), items = { { id, name, count } } most first }.
function ns.KindInfo(key)
    local k = kindOf(key)
    local info = { stacks = 0, total = 0, items = {} }
    if not k then return info end
    local by = {}
    for _, it in ipairs(ns.ItemsOfKind(key)) do
        local n = stackCount(it.bag, it.slot)
        local e = by[it.id]
        if not e then
            e = { id = it.id, name = itemName(it.id) or ("#" .. it.id), count = 0, stacks = 0 }
            by[it.id] = e
            info.items[#info.items + 1] = e
        end
        e.count, e.stacks = e.count + n, e.stacks + 1
        info.stacks, info.total = info.stacks + 1, info.total + n
    end
    table.sort(info.items, function(a, b) if a.count ~= b.count then return a.count > b.count end return a.id < b.id end)
    local top = info.items[1]
    info.top = top and top.name
    info.icon = k.icon or (top and itemIcon(top.id)) or ns.KindIcon(key)
    info.going = math.min(info.stacks, sendOpen() and ns.Room() or SEND_MAX)
    return info
end

-- What a take-by-kind tile shows: the items of that kind in the letters Take all can open
-- (no cash on delivery, no GM letters), { icon, stacks, total, items } like ns.KindInfo.
function ns.InboxKindInfo(key)
    local k = kindOf(key)
    local info = { stacks = 0, total = 0, items = {} }
    if not k then return info end
    local by = {}
    for i = 1, (numMail()) do
        local h = header(i)
        if h.cod == 0 and not h.gm and h.items > 0 then
            for j = 1, ATTACH do
                local name, id, _, count = GetInboxItem(i, j)
                if name and id then
                    local class, sub = classNow(id)
                    if ns.KindHas(k, class, sub, id) then
                        count = count or 1
                        local e = by[id]
                        if not e then
                            e = { id = id, name = name, count = 0, stacks = 0 }
                            by[id] = e
                            info.items[#info.items + 1] = e
                        end
                        e.count, e.stacks = e.count + count, e.stacks + 1
                        info.stacks, info.total = info.stacks + 1, info.total + count
                    end
                end
            end
        end
    end
    table.sort(info.items, function(a, b) if a.count ~= b.count then return a.count > b.count end return a.id < b.id end)
    local top = info.items[1]
    info.top = top and top.name
    info.icon = k.icon or (top and itemIcon(top.id)) or ns.KindIcon(key)
    return info
end

-- Bag items of one quick-attach kind that can go by mail: not bound, not protected, not
-- locked. { { bag, slot, id } }
function ns.ItemsOfKind(key)
    local k = kindOf(key)
    local out = {}
    if not k then return out end
    for bag = 0, lastBag() do
        for slot = 1, numSlots(bag) do
            local id, locked = slotItem(bag, slot)
            if id and not locked and not protected(id) then
                local class, sub = itemClass(id)
                if ns.KindHas(k, class, sub, id) and not bound(bag, slot) then
                    out[#out + 1] = { bag = bag, slot = slot, id = id }
                end
            end
        end
    end
    return out
end

-- Puts items of one kind into the letter being written (a right-click on a bag item does that
-- while the send tab is open, so it opens that tab first), up to the free attachment places.
-- Returns how many.
function ns.AttachKind(key)
    if not ns.OpenSend() then return 0 end
    local room = ns.Room()
    local n = 0
    for _, it in ipairs(ns.ItemsOfKind(key)) do
        if n >= room then break end
        useItem(it.bag, it.slot)
        n = n + 1
    end
    return n
end

-- All the gold that can go by mail: everything less the postage, since a letter that takes
-- every copper cannot pay for itself and the game refuses it.
function ns.GoldToSend()
    local postage = sendOpen() and GetSendMailPrice and GetSendMailPrice() or ns.POSTAGE
    return math.max(0, money() - (postage or 0))
end

-- Puts all that gold into the letter (opening the send tab first).
function ns.FillGold()
    if not ns.OpenSend() then return 0 end
    local amount = ns.GoldToSend()
    if SendMailMoney and MoneyInputFrame_SetCopper then MoneyInputFrame_SetCopper(SendMailMoney, amount) end
    return amount
end

-- The subject of a letter with only money (the game names a letter with items itself, and
-- Send stays grey without a subject). The plain amount, in the client's words when it has them.
function ns.SubjectFor(copper)
    copper = math.floor(copper or 0)
    if GetCoinText then
        local t = GetCoinText(copper >= 10000 and copper - copper % 100 or copper, " ")
        if type(t) == "string" and t ~= "" then return t:sub(1, 64) end
    end
    local g, sv, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if sv > 0 then parts[#parts + 1] = sv .. "s" end
    if (c > 0 and g == 0) or #parts == 0 then parts[#parts + 1] = c .. "c" end
    return table.concat(parts, " ")
end

-- The game's own name of a letter with items: its first item, with the count of a stack.
function ns.ItemSubject()
    if not GetSendMailItem then return "" end
    for j = 1, SEND_MAX do
        local name, _, _, count = GetSendMailItem(j)
        if type(name) == "string" and name ~= "" then
            if type(count) == "number" and count > 1 then name = name .. " (" .. count .. ")" end
            return name:sub(1, 64)
        end
    end
    return ""
end

-- Fills an empty subject, since Send stays grey without one: the amount for
-- a letter of money alone, the first item's name for a letter with items when the game left it
-- empty. A subject it filled follows the letter; one the player typed stays.
function ns.AutoSubject()
    if ns.paused or not ns.db or not sendOpen() then return nil end
    local box = SendMailSubjectEditBox
    if not box or not SendMailMoney or not MoneyInputFrame_GetCopper then return nil end
    local text = box:GetText() or ""
    local ours = ns.autoSubject
    if text ~= "" and text ~= ours then ns.autoSubject = nil; return nil end
    local want
    if ns.Room() < SEND_MAX then
        want = ns.ItemSubject()
    else
        local cod = SendMailCODButton and SendMailCODButton.GetChecked and SendMailCODButton:GetChecked()
        local copper = not cod and MoneyInputFrame_GetCopper(SendMailMoney) or 0
        want = copper > 0 and ns.SubjectFor(copper) or ""
    end
    ns.autoSubject = want ~= "" and want or nil
    if want == text then return want end
    ns.filling = true
    box:SetText(want)
    ns.filling = nil
    return want
end

-- Hooks the send side once the game's mail frame exists.
function ns.HookSubject()
    if ns.subjectHooked or not SendMailFrame then return end
    ns.subjectHooked = true
    local function changed()
        if ns.filling then return end
        ns.AutoSubject()
        if ns.RefreshSend then ns.RefreshSend() end
    end
    for _, part in ipairs({ "Gold", "Silver", "Copper" }) do
        local box = _G["SendMailMoney" .. part]
        if box and box.HookScript then box:HookScript("OnTextChanged", changed) end
    end
    if SendMailFrame.HookScript then SendMailFrame:HookScript("OnShow", changed) end
    if hooksecurefunc and SendMailFrame_Update then
        hooksecurefunc("SendMailFrame_Update", changed)
    end
    if hooksecurefunc and SendMailRadioButton_OnClick then hooksecurefunc("SendMailRadioButton_OnClick", changed) end
    -- the game decides here whether Send works: our button and status line follow it
    if hooksecurefunc and SendMailFrame_CanSend then
        hooksecurefunc("SendMailFrame_CanSend", function() if ns.RefreshSend then ns.RefreshSend() end end)
    end
end

-- The letter being written, for the panel's status line and its Send button: { to, items,
-- money, can }. `can` is the game's own Send button: we never decide that ourselves.
function ns.SendState()
    local st = { to = "", items = 0, money = 0, can = false }
    if not sendOpen() then
        st.to = ns.to or ""
        return st
    end
    local name = SendMailNameEditBox and SendMailNameEditBox.GetText and SendMailNameEditBox:GetText()
    st.to = type(name) == "string" and strtrim(name) or ""
    st.items = SEND_MAX - ns.Room()
    local cod = SendMailCODButton and SendMailCODButton.GetChecked and SendMailCODButton:GetChecked()
    if not cod and SendMailMoney and MoneyInputFrame_GetCopper then st.money = MoneyInputFrame_GetCopper(SendMailMoney) or 0 end
    local b = SendMailMailButton
    st.can = b ~= nil and b.IsEnabled ~= nil and b:IsEnabled() and true or false
    return st
end

-- Our Send button: a click on the game's own, only inside the player's click and only while
-- the game would take it.
function ns.Send()
    if ns.paused or not ns.SendState().can then return false end
    SendMailMailButton:Click()
    return true
end

-- The game empties the letter after it went; the name stays, so the next letter to the same
-- character needs no new pick.
function ns.Sent()
    local name = ns.sentTo or ns.to
    if not name or name == "" or not sendOpen() or not SendMailNameEditBox then return end
    ns.to = name
    SendMailNameEditBox:SetText(name)
    if ns.RefreshSend then ns.RefreshSend() end
end

-- Mailing rules -------------------------------------------------------------------------------
-- A rule sends one kind of goods to one character: { kind = "herb", to = "Name", off = true }.
-- A kind with no rule of its own goes to the player's own character with the profession that
-- uses it (by skill line, the highest rank first), unless the player turned that one off
-- (db.ruleOff) or this character has the profession itself.
ns.PROF_KINDS = { herb = { 171 }, cloth = { 197 }, leather = { 165 }, ore = { 164, 202 }, enchanting = { 333 } }

local function first(name) return name and (name:match("^(%S+)") or name) end

-- This character's professions as skill line -> rank, kept per realm and faction by its whole
-- name, so the other characters know who crafts what.
function ns.NoteProfs()
    if not (GetProfessions and GetProfessionInfo) then return end
    local out = {}
    for _, i in ipairs({ GetProfessions() }) do
        local _, _, rank, _, _, _, line = GetProfessionInfo(i)
        if line then out[line] = rank or 0 end
    end
    local r, faction = realm(), UnitFactionGroup("player") or "?"
    ns.db.profs = ns.db.profs or {}
    ns.db.profs[r] = ns.db.profs[r] or {}
    ns.db.profs[r][faction] = ns.db.profs[r][faction] or {}
    ns.db.profs[r][faction][me()] = out
end

-- Skill line -> rank of one of the player's characters: Mail's own note, else what Gulli
-- Chores saved of a character of that first name (read only).
function ns.ProfsOf(name)
    local r, faction = realm(), UnitFactionGroup("player") or "?"
    local own = ns.db.profs and ns.db.profs[r] and ns.db.profs[r][faction] and ns.db.profs[r][faction][name]
    if own then return own end
    local db = GulliChoresDB
    if type(db) ~= "table" or type(db.chars) ~= "table" then return {} end
    for key, c in pairs(db.chars) do
        local n, kr = tostring(key):match("^(.-)%-(.*)$")
        if (n == name or n == first(name)) and (kr == r or kr == "") and type(c) == "table" and type(c.profs) == "table"
            and (not c.faction or c.faction == faction) then
            local out = {}
            for _, p in ipairs(c.profs) do if p.line then out[p.line] = p.skill or 0 end end
            return out
        end
    end
    return {}
end

-- The player's own character that should get a kind: (name, skill line, rank) or nil.
function ns.ProfAlt(key)
    local lines = ns.PROF_KINDS[key]
    if not lines then return nil end
    local self = ns.ProfsOf(me())
    for _, line in ipairs(lines) do if self[line] then return nil end end
    local r, faction = realm(), UnitFactionGroup("player") or "?"
    local alts = ns.db.alts[r] and ns.db.alts[r][faction] or {}
    local best, bestLine, bestRank
    local names = {}
    for name in pairs(alts) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        if name:lower() ~= me():lower() then
            local p = ns.ProfsOf(name)
            for _, line in ipairs(lines) do
                local rank = p[line]
                if rank and (not bestRank or rank > bestRank) then best, bestLine, bestRank = name, line, rank end
            end
        end
    end
    return best, bestLine, bestRank
end

-- Every rule in order: the player's own ({ kind, to, off, index }), then a profession rule
-- ({ kind, to, auto, line, rank, off }) for each kind that has none.
function ns.Rules()
    local out, has = {}, {}
    for i, r in ipairs(ns.db.rules or {}) do
        out[#out + 1] = { kind = r.kind, to = r.to or "", off = r.off and true or nil, index = i }
        has[r.kind] = true
    end
    for _, k in ipairs(ns.ATTACH_KINDS) do
        if ns.PROF_KINDS[k.key] and not has[k.key] then
            local to, line, rank = ns.ProfAlt(k.key)
            if to then
                out[#out + 1] = { kind = k.key, to = to, auto = true, line = line, rank = rank,
                                  off = ns.db.ruleOff and ns.db.ruleOff[k.key] or nil }
            end
        end
    end
    return out
end

-- What the rules would send now, one entry per rule with something in the bags:
-- { rule, to, kind, items = { { bag, slot, id } }, stacks, total, letters }. An item goes to the
-- first rule that takes it; nothing goes to the character playing.
function ns.RuleLetters()
    local out, claimed = {}, {}
    for _, r in ipairs(ns.Rules()) do
        if not r.off and r.to ~= "" and r.to:lower() ~= me():lower() and r.to:lower() ~= (UnitName("player") or ""):lower() then
            local e = { rule = r, to = r.to, kind = r.kind, items = {}, stacks = 0, total = 0 }
            for _, it in ipairs(ns.ItemsOfKind(r.kind)) do
                local key = it.bag .. ":" .. it.slot
                if not claimed[key] then
                    claimed[key] = true
                    e.items[#e.items + 1] = it
                    e.total = e.total + stackCount(it.bag, it.slot)
                end
            end
            e.stacks = #e.items
            if e.stacks > 0 then
                e.letters = math.ceil(e.stacks / SEND_MAX)
                out[#out + 1] = e
            end
        end
    end
    return out
end

-- Puts one letter of a rule together: the recipient and as many of its items as fit. The
-- player presses Send. Returns how many items went in.
function ns.FillRule(i)
    local e = ns.RuleLetters()[i]
    if not e or not ns.OpenSend() then return 0 end
    ns.Pick(e.to)
    local room, n = ns.Room(), 0
    for _, it in ipairs(e.items) do
        if n >= room then break end
        if slotItem(it.bag, it.slot) == it.id then
            useItem(it.bag, it.slot)
            n = n + 1
        end
    end
    if ns.RefreshSend then ns.RefreshSend() end
    return n
end

-- Editing. A profession rule becomes the player's own once its recipient changes.
function ns.AddRule(kind, to)
    ns.db.rules = ns.db.rules or {}
    ns.db.rules[#ns.db.rules + 1] = { kind = kind or ns.ATTACH_KINDS[1].key, to = to or "" }
    return #ns.db.rules
end
function ns.RemoveRule(i) if ns.db.rules and ns.db.rules[i] then table.remove(ns.db.rules, i) end end
function ns.SetRuleTo(r, to)
    to = strtrim(to or "")
    if r.auto then
        if to == r.to then return end
        r.index = ns.AddRule(r.kind, to)
        r.auto = nil
    end
    if ns.db.rules[r.index] then ns.db.rules[r.index].to = to end
    r.to = to
end
function ns.SetRuleOn(r, on)
    if r.auto then
        ns.db.ruleOff = ns.db.ruleOff or {}
        ns.db.ruleOff[r.kind] = (not on) or nil
    elseif ns.db.rules[r.index] then
        ns.db.rules[r.index].off = (not on) or nil
    end
    r.off = (not on) or nil
end
-- The next (or, with back, the one before) kind of the player's own rule.
function ns.CycleRuleKind(i, back)
    local r = ns.db.rules[i]
    if not r then return end
    local idx = 1
    for k, kind in ipairs(ns.ATTACH_KINDS) do if kind.key == r.kind then idx = k end end
    local n = #ns.ATTACH_KINDS
    r.kind = ns.ATTACH_KINDS[(idx - 1 + (back and -1 or 1)) % n + 1].key
end
-- The player's other characters, for the recipient picker.
function ns.OwnNames()
    local out = {}
    for _, e in ipairs(ns.Names()) do if e.group == "alt" then out[#out + 1] = e.name end end
    return out
end
-- The next own character after the rule's recipient.
function ns.CycleRuleTo(r)
    local names = ns.OwnNames()
    if #names == 0 then return end
    local at = 0
    for k, n in ipairs(names) do if n:lower() == (r.to or ""):lower() then at = k end end
    ns.SetRuleTo(r, names[at % #names + 1])
end

-- Events -------------------------------------------------------------------------------------

ns.DEFAULTS = { panel = true }
-- Settings of older versions: Take all takes everything, the subject is always filled. Dropped
-- on load.
local GONE = { "money", "sold", "bought", "expired", "player", "keepFree", "keepGold", "subject" }

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliMailDB = GulliMailDB or {}
        ns.db = GulliMailDB
        ns.db.recent = ns.db.recent or {}
        ns.db.alts = ns.db.alts or {}
        ns.db.chars = ns.db.chars or {}
        ns.db.log = ns.db.log or {}
        ns.db.rules = ns.db.rules or {}
        ns.db.ruleOff = ns.db.ruleOff or {}
        ns.db.profs = ns.db.profs or {}
        for _, k in ipairs(GONE) do ns.db[k] = nil end
        for k, v in pairs(ns.DEFAULTS) do if ns.db[k] == nil then ns.db[k] = v end end
        ns.MergeRealmless()
        self:RegisterEvent("PLAYER_LOGIN")
        self:RegisterEvent("MAIL_SHOW")
        -- every way the mailbox closes, walking away too (the client may send no MAIL_CLOSED then)
        if ns.Skin and ns.Skin.ClosesWith then ns.Skin.ClosesWith("mail", function() ns.Closed() end) end
        self:RegisterEvent("MAIL_INBOX_UPDATE")
        self:RegisterEvent("BAG_UPDATE_DELAYED")
        self:RegisterEvent("MAIL_SEND_SUCCESS")
        if SendMail then
            hooksecurefunc("SendMail", function(name)
                if ns.paused then return end
                ns.sentTo = name
                ns.Remember(name)
            end)
        end
        return
    end
    -- Paused from the hub: only the closing events still run, so nothing stays open.
    if ns.paused and not event:find("_CLOSED$") then return end
    if event == "PLAYER_LOGIN" then
        ns.MergeRealmless()
        local r, faction = realm(), UnitFactionGroup("player") or "?"
        ns.db.alts[r] = ns.db.alts[r] or {}
        ns.db.alts[r][faction] = ns.db.alts[r][faction] or {}
        local full, first = me(), UnitName("player")
        -- older versions saved this character by its first name alone
        if first and first ~= full then
            ns.db.alts[r][faction][first] = nil
            local chars = ns.db.chars[r]
            if chars and chars[first] then
                chars[full] = chars[full] or chars[first]
                chars[first] = nil
            end
        end
        ns.db.alts[r][faction][full] = true
        ns.NoteProfs()
        warnOthers()
    elseif event == "MAIL_SEND_SUCCESS" then
        -- after the game's own handler emptied the letter
        if C_Timer and C_Timer.After then C_Timer.After(0, ns.Sent) else ns.Sent() end
    elseif event == "MAIL_SHOW" then
        ns.open = true
        ns.to, ns.sentTo = nil, nil
        ns.visit = { money = 0, sold = 0, items = 0 }
        ns.warned = false
        ns.NoteProfs()
        ns.HookSubject()
        if ns.db.panel and ns.ShowPanel then ns.ShowPanel() end
    elseif event == "MAIL_INBOX_UPDATE" then
        ns.InboxChanged()
        if ns.open then
            ns.Snapshot()
            if not ns.warned then
                ns.warned = true
                local n, days = ns.Expiring()
                if n > 0 then say(L.EXPIRING:format(n, math.max(0, math.floor(days * 24 + 0.5)))) end
            end
        end
        if ns.Refresh then ns.Refresh() end
    elseif event == "BAG_UPDATE_DELAYED" then
        if ns.Refresh and ns.open then ns.Refresh() end
    end
end)

SLASH_GULLIMAIL1 = "/gml"
SLASH_GULLIMAIL2 = "/gullimail"
SlashCmdList.GULLIMAIL = function() ns.Toggle() end

function GulliMail_Toggle() ns.Toggle() end

local function option(key, label)
    return { label = label, icon = ns.OPT_ICON[key], tip = ns.L["TIP_" .. key], get = function() return ns.db ~= nil and ns.db[key] == true end,
             set = function(on) if ns.db then ns.db[key] = on and true or false end end }
end

-- With the hub: its row and button there; alone: its own minimap button (Skin.lua).
do
    local register = GulliToolkit and GulliToolkit.Register or function(info) ns.alone = info end
    register({
        pause = function(on)
            ns.paused = on
            if on then
                ns.taking = nil
                if ns.HidePanel then ns.HidePanel() end
            elseif ns.open and ns.db and ns.db.panel and ns.ShowPanel then
                ns.ShowPanel()
            end
        end,
        key = "Mail",
        icon = "Interface\\AddOns\\Gulli-Mail\\icon",
        slash = "/gml",
        open = function() ns.Toggle() end,
        window = function() return ns.Window and ns.Window() end,
        options = {
            option("panel", ns.L.OPT_PANEL),
        },
        -- letters with things in them that run out soon, on any character of this realm
        summary = function()
            if not ns.db or not ns.db.chars then return nil end
            local n, soonest = 0, nil
            for _, c in pairs(ns.db.chars[realm()] or {}) do
                for _, e in ipairs(c.ends or {}) do
                    local days = (e - time()) / 86400
                    if days > 0 and days < 7 then n = n + 1; soonest = math.min(soonest or days, days) end
                end
            end
            if n == 0 then return nil end
            return ns.L.HUB_SUMMARY:format(n, math.max(1, math.ceil(soonest))), "Interface\\Icons\\INV_Letter_15"
        end,
        reset = function()
            if not ns.db then return end
            for k, v in pairs(ns.DEFAULTS) do ns.db[k] = v end
            if ns.Refresh then ns.Refresh() end
            if ns.RefreshSettings then ns.RefreshSettings() end
        end,
    })
end
