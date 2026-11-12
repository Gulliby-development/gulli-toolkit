-- The mailbox: Take all (money and items, never a letter with cash on delivery), and the
-- player's own characters and recent recipients as one-tap names for a new letter.

local ADDON, ns = ...
local L = ns.L

local STEP = 0.4 -- the server needs a moment between two takes
local RECENT_MAX = 10
local ATTACH = ATTACHMENTS_MAX_RECEIVE or 12

local TRIES = 3 -- a take that changes nothing this often is one the game refuses
local WAIT_MAX = 70 -- the server sends the next letters at most once a minute
local WAIT_STEP = 5

-- Game API wrappers.
local function numMail()
    if not GetInboxNumItems then return 0, 0 end
    local shown, total = GetInboxNumItems()
    return shown or 0, total or shown or 0
end
local function header(i)
    local _, _, sender, subject, money, cod, days, items, _, _, _, _, isGM = GetInboxHeaderInfo(i)
    return { sender = sender, subject = subject, money = money or 0, cod = cod or 0, items = items or 0, gm = isGM,
             days = days }
end
local function freeSlots()
    local free = 0
    for bag = 0, 4 do
        local f, family = ((C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots)(bag)
        if (family or 0) == 0 then free = free + (f or 0) end
    end
    return free
end
local function money() return GetMoney and GetMoney() or 0 end
local function checkInbox() if CheckInbox then CheckInbox() end end
local function say(msg) print("|cff9ad0ffGulli Mail|r: " .. msg) end
local function realm() return GetRealmName() or "" end

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

-- What Take all would get: money, item count, letters left out (cash on delivery) and the
-- letters still on the server (it shows at most 50 at a time).
function ns.Summary()
    local shown, total = numMail()
    local s = { money = 0, items = 0, cod = 0, letters = shown, more = math.max(0, total - shown) }
    for i = 1, shown do
        local h = header(i)
        if h.cod > 0 or h.gm then s.cod = s.cod + 1 else
            s.money = s.money + h.money
            s.items = s.items + h.items
        end
    end
    return s
end

-- A take is known by its place and what it is. Going from the last letter back, a take
-- that worked moves on to another place; the same key again means the game refused it.
-- `what` (without the place) counts each refused thing once.
local function takeKey(i, h, what)
    local w = (h.sender or "?") .. "\1" .. (h.subject or "") .. "\1" .. what
    return i .. "\1" .. w, w
end

-- The next thing to take, from the last letter back: { i, j, kind = "money"|"item", key,
-- amount }, "full" when the next one is an item and the bags are full, or nil. `skip` holds
-- the keys the game refused.
function ns.Next(skip)
    skip = skip or {}
    for i = numMail(), 1, -1 do
        local h = header(i)
        if h.cod == 0 and not h.gm then
            local k, what = takeKey(i, h, "money")
            if h.money > 0 and not skip[k] then
                return { i = i, kind = "money", key = k, what = what, amount = h.money }
            end
            if h.items > 0 then
                for j = 1, ATTACH do
                    local name, id = GetInboxItem(i, j)
                    if name then
                        k, what = takeKey(i, h, j .. ":" .. tostring(id or name))
                        if not skip[k] then
                            if freeSlots() == 0 then return "full" end
                            return { i = i, j = j, kind = "item", key = k, what = what }
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

-- Take all, one thing per step. A thing the game refuses (a unique item the bags already
-- hold) is tried TRIES times, then left in its letter and counted. When the mailbox shows
-- fewer letters than the server holds, it asks for the rest and goes on.
function ns.TakeAll()
    if ns.taking then return end
    local t = { items = 0, failed = 0, skip = {}, refused = {}, start = money() }
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
    step = function()
        if ns.taking ~= t or not ns.open then if ns.taking == t then ns.taking = nil end return end
        local c = ns.Next(t.skip)
        -- The last take is done once something else comes next; the same thing again means
        -- the game did not take it.
        if t.last and not (type(c) == "table" and c.key == t.last.key) then
            if t.last.kind == "item" then t.items = t.items + 1 end
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
            t.last, t.tries = c, t.tries or 0
            if ns.Refresh then ns.Refresh() end
            C_Timer.After(STEP, step)
            return
        end
        if c == nil then
            local shown, total = numMail()
            if total > shown then
                t.waitSince = t.waitSince or GetTime()
                if GetTime() - t.waitSince < WAIT_MAX then
                    t.waiting = total - shown
                    checkInbox()
                    if ns.Refresh then ns.Refresh() end
                    C_Timer.After(WAIT_STEP, step)
                    return
                end
            end
        end
        finish(c)
    end
    step()
end

-- Names for a new letter: the player's other characters on this realm and faction first,
-- then the recent recipients.
function ns.Names()
    local me = UnitName("player")
    local out, seen = {}, { [me] = true }
    local alts = ns.db.alts[realm()] and ns.db.alts[realm()][UnitFactionGroup("player")] or {}
    local sorted = {}
    for name in pairs(alts) do sorted[#sorted + 1] = name end
    table.sort(sorted)
    for _, name in ipairs(sorted) do
        if not seen[name] then seen[name] = true; out[#out + 1] = { name = name, alt = true } end
    end
    for _, name in ipairs(ns.db.recent[realm()] or {}) do
        if not seen[name] then seen[name] = true; out[#out + 1] = { name = name } end
    end
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

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliMailDB = GulliMailDB or {}
        ns.db = GulliMailDB
        ns.db.recent = ns.db.recent or {}
        ns.db.alts = ns.db.alts or {}
        if ns.db.panel == nil then ns.db.panel = true end
        self:RegisterEvent("PLAYER_LOGIN")
        self:RegisterEvent("MAIL_SHOW")
        self:RegisterEvent("MAIL_CLOSED")
        self:RegisterEvent("MAIL_INBOX_UPDATE")
        if SendMail then hooksecurefunc("SendMail", function(name) ns.Remember(name) end) end
        return
    end
    if event == "PLAYER_LOGIN" then
        local r, faction = realm(), UnitFactionGroup("player") or "?"
        ns.db.alts[r] = ns.db.alts[r] or {}
        ns.db.alts[r][faction] = ns.db.alts[r][faction] or {}
        ns.db.alts[r][faction][UnitName("player")] = true
    elseif event == "MAIL_SHOW" then
        ns.open = true
        if ns.db.panel and ns.ShowPanel then ns.ShowPanel() end
    elseif event == "MAIL_CLOSED" then
        ns.open, ns.taking = false, nil
        if ns.HidePanel then ns.HidePanel() end
    elseif event == "MAIL_INBOX_UPDATE" then
        if ns.taking then ns.taking.waiting = nil end
        if ns.Refresh then ns.Refresh() end
    end
end)

SLASH_GULLIMAIL1 = "/gml"
SLASH_GULLIMAIL2 = "/gullimail"
SlashCmdList.GULLIMAIL = function() ns.Toggle() end

function GulliMail_Toggle() ns.Toggle() end

if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({
        key = "Mail",
        icon = "Interface\\AddOns\\Gulli-Mail\\icon",
        slash = "/gml",
        open = function() ns.Toggle() end,
        window = function() return ns.Window and ns.Window() end,
    })
end
