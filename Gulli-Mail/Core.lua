-- The mailbox: Take all with switches for what to take, one letter's Take and Return, a
-- visit total, warnings about letters that run out (on every character), a log, and the
-- send side: names to tap, quick attach by kind, gold to another character and mailing rules.
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
local TRIES = 3 -- a take that changes nothing this often is one the game refuses
local WAIT_MAX = 70 -- the server sends the next letters at most once a minute
local WAIT_STEP_SERVER = 5

-- What Take all takes, by kind of letter. `money` also covers the money of every letter.
ns.KINDS = { "money", "sold", "bought", "expired", "player" }
ns.OPT_ICON = {
    money = "Interface\\Icons\\INV_Misc_Coin_02",
    sold = "Interface\\Minimap\\Tracking\\Auctioneer",
    bought = "Interface\\Icons\\INV_Misc_Bag_10",
    expired = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    player = "Interface\\Icons\\INV_Letter_15",
    panel = "Interface\\Icons\\INV_Letter_15",
    keepFree = "Interface\\Icons\\INV_Misc_Bag_08",
    keepGold = "Interface\\Icons\\INV_Misc_Coin_02",
}

-- Quick attach: item class 7 (trade goods) subclasses, and class 3 (gems).
ns.ATTACH_KINDS = {
    { key = "cloth", class = 7, sub = 5 },
    { key = "herb", class = 7, sub = 9 },
    { key = "ore", class = 7, sub = 7 },
    { key = "leather", class = 7, sub = 6 },
    { key = "elemental", class = 7, sub = 10 },
    { key = "enchanting", class = 7, sub = 12 },
    { key = "gem", class = 3 },
}

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
    for bag = 0, 4 do
        local f, family = (C.GetContainerNumFreeSlots or GetContainerNumFreeSlots)(bag)
        if (family or 0) == 0 then free = free + (f or 0) end
    end
    return free
end
local function numSlots(bag) return (C.GetContainerNumSlots or GetContainerNumSlots)(bag) or 0 end
local function slotItem(bag, slot)
    if C.GetContainerItemInfo then
        local i = C.GetContainerItemInfo(bag, slot)
        if i then return i.itemID, i.isLocked end
        return nil
    end
    local _, _, locked, _, _, _, _, _, _, id = GetContainerItemInfo(bag, slot)
    return id, locked
end
local function itemClass(id)
    local _, _, _, _, _, _, _, _, _, _, _, classID, subclassID = ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(id)
    return classID, subclassID
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
local function realm() return GetRealmName() or "" end
local function me() return UnitName("player") or "?" end
local function protected(id)
    return GulliToolkit and GulliToolkit.IsProtected and GulliToolkit.IsProtected(id) or false
end
local function sendOpen() return SendMailFrame and SendMailFrame.IsShown and SendMailFrame:IsShown() end

function ns.Money(copper)
    copper = math.floor(copper or 0)
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
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
    if h.cod > 0 or h.gm or kind == "system" then return false end
    return ns.db[kind] ~= false
end

-- What Take all would get: money, item count, letters left out (cash on delivery, switched
-- off), and the letters still on the server (it shows at most 50 at a time).
function ns.Summary()
    local shown, total = numMail()
    local s = { money = 0, items = 0, cod = 0, off = 0, letters = shown, more = math.max(0, total - shown) }
    for i = 1, shown do
        local h = header(i)
        local kind = ns.Kind(i, h)
        if h.cod > 0 or h.gm then s.cod = s.cod + 1
        elseif not ns.Allowed(kind, h) then s.off = s.off + 1
        else
            if ns.db.money then s.money = s.money + h.money end
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
-- amount, letter }, "full" when the next one is an item and the bags are full (or at the
-- free slots to keep), or nil. `skip` holds the keys the game refused; `only` limits it to
-- one letter (its index), `force` takes from it whatever the switches say.
function ns.Next(skip, only, force)
    skip = skip or {}
    local from, to = numMail(), 1
    if only then
        if only > from then return nil end
        from, to = only, only
    end
    for i = from, to, -1 do
        local h = header(i)
        local kind = ns.Kind(i, h)
        if h.cod == 0 and not h.gm and (force or ns.Allowed(kind, h)) then
            local k, what = takeKey(i, h, "money")
            if h.money > 0 and (force or ns.db.money) and not skip[k] then
                return { i = i, kind = "money", key = k, what = what, amount = h.money, letter = kind, sender = h.sender }
            end
            if h.items > 0 then
                for j = 1, ATTACH do
                    local name, id, _, count = GetInboxItem(i, j)
                    if name then
                        k, what = takeKey(i, h, j .. ":" .. tostring(id or name))
                        if not skip[k] then
                            if freeSlots() <= (ns.db.keepFree or 0) then return "full" end
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
-- those letters, whatever the switches say.
function ns.TakeAll(letters)
    if ns.taking then return end
    local t = { items = 0, failed = 0, skip = {}, refused = {}, start = money(), tries = 0 }
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
                c = ns.Next(t.skip, i, true)
                if c ~= nil then break end
                table.remove(t.queue, 1)
            end
        else
            c = ns.Next(t.skip)
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
    local out, seen = {}, { [me()] = true }
    filter = filter and filter ~= "" and filter:lower() or nil
    local function add(name, group)
        name = short(name)
        if not name or name == "" or seen[name] then return end
        if filter and not name:lower():find(filter, 1, true) then return end
        seen[name] = true
        out[#out + 1] = { name = name, alt = group == "alt", group = group }
    end
    local alts = ns.db.alts[realm()] and ns.db.alts[realm()][UnitFactionGroup("player")] or {}
    local sorted = {}
    for name in pairs(alts) do sorted[#sorted + 1] = name end
    table.sort(sorted)
    for _, name in ipairs(sorted) do add(name, "alt") end
    for _, name in ipairs(ns.db.recent[realm()] or {}) do add(name, "recent") end
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

function ns.Pick(name)
    if MailFrameTab2 and MailFrameTab2.Click then MailFrameTab2:Click() end
    if SendMailNameEditBox then SendMailNameEditBox:SetText(name) end
end

-- Sending ------------------------------------------------------------------------------------

local function kindOf(key)
    for _, k in ipairs(ns.ATTACH_KINDS) do if k.key == key then return k end end
end

-- Bag items of one quick-attach kind that can go by mail: not bound, not protected, not
-- locked. { { bag, slot, id } }
function ns.ItemsOfKind(key)
    local k = kindOf(key)
    local out = {}
    if not k then return out end
    for bag = 0, 4 do
        for slot = 1, numSlots(bag) do
            local id, locked = slotItem(bag, slot)
            if id and not locked and not protected(id) then
                local class, sub = itemClass(id)
                if class == k.class and (not k.sub or sub == k.sub) and not bound(bag, slot) then
                    out[#out + 1] = { bag = bag, slot = slot, id = id }
                end
            end
        end
    end
    return out
end

-- Puts items of one kind into the letter being written (a right-click on a bag item does that
-- while the send tab is open), up to the free attachment places. Returns how many.
function ns.AttachKind(key)
    if not sendOpen() then return 0 end
    local room = SEND_MAX
    if GetSendMailItem then
        for j = 1, SEND_MAX do if GetSendMailItem(j) then room = room - 1 end end
    end
    local n = 0
    for _, it in ipairs(ns.ItemsOfKind(key)) do
        if n >= room then break end
        useItem(it.bag, it.slot)
        n = n + 1
    end
    return n
end

-- Fills the money of the letter with all the gold but `keepGold` (gold, not copper).
function ns.FillGold()
    local amount = math.max(0, money() - (ns.db.keepGold or 0) * 10000)
    if SendMailMoney and MoneyInputFrame_SetCopper then MoneyInputFrame_SetCopper(SendMailMoney, amount) end
    return amount
end

-- Mailing rules: { kind = "cloth", to = "Name" }. Apply fills the letter for the first rule
-- with something to send: the recipient and the items. The player presses Send.
function ns.NextRule()
    for _, r in ipairs(ns.db.rules) do
        if r.to and r.to ~= "" and short(r.to) ~= me() and #ns.ItemsOfKind(r.kind) > 0 then return r end
    end
end

function ns.ApplyRule()
    local r = ns.NextRule()
    if not r or not sendOpen() then return nil end
    if SendMailNameEditBox then SendMailNameEditBox:SetText(r.to) end
    local n = ns.AttachKind(r.kind)
    return r, n
end

function ns.AddRule(kind, to) ns.db.rules[#ns.db.rules + 1] = { kind = kind or ns.ATTACH_KINDS[1].key, to = to or "" } end
function ns.RemoveRule(i) table.remove(ns.db.rules, i) end

-- Events -------------------------------------------------------------------------------------

ns.DEFAULTS = { panel = true, money = true, sold = true, bought = true, expired = true, player = true,
                keepFree = 0, keepGold = 0 }

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
        for k, v in pairs(ns.DEFAULTS) do if ns.db[k] == nil then ns.db[k] = v end end
        self:RegisterEvent("PLAYER_LOGIN")
        self:RegisterEvent("MAIL_SHOW")
        self:RegisterEvent("MAIL_CLOSED")
        self:RegisterEvent("MAIL_INBOX_UPDATE")
        self:RegisterEvent("BAG_UPDATE_DELAYED")
        if SendMail then hooksecurefunc("SendMail", function(name) if not ns.paused then ns.Remember(name) end end) end
        return
    end
    -- Paused from the hub: only the closing events still run, so nothing stays open.
    if ns.paused and not event:find("_CLOSED$") then return end
    if event == "PLAYER_LOGIN" then
        local r, faction = realm(), UnitFactionGroup("player") or "?"
        ns.db.alts[r] = ns.db.alts[r] or {}
        ns.db.alts[r][faction] = ns.db.alts[r][faction] or {}
        ns.db.alts[r][faction][me()] = true
        warnOthers()
    elseif event == "MAIL_SHOW" then
        ns.open = true
        ns.visit = { money = 0, sold = 0, items = 0 }
        ns.warned = false
        if ns.db.panel and ns.ShowPanel then ns.ShowPanel() end
    elseif event == "MAIL_CLOSED" then
        if ns.open and (ns.visit.money > 0 or ns.visit.items > 0) then
            notify(L.VISIT:format(ns.visit.items, ns.Money(ns.visit.money), ns.Money(ns.visit.sold)))
        end
        ns.open, ns.taking = false, nil
        if ns.HidePanel then ns.HidePanel() end
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

if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({
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
            option("money", ns.L.OPT_MONEY),
            option("sold", ns.L.OPT_SOLD),
            option("bought", ns.L.OPT_BOUGHT),
            option("expired", ns.L.OPT_EXPIRED),
            option("player", ns.L.OPT_PLAYER),
        },
        -- letters with things in them that run out soon, on any character of this realm
        summary = function()
            if not ns.db or not ns.db.chars then return nil end
            local n, soonest = 0, nil
            for _, c in pairs(ns.db.chars[GetRealmName and GetRealmName() or ""] or {}) do
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
