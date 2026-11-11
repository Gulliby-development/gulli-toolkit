-- The mailbox: Take all (money and items, never a letter with cash on delivery), and the
-- player's own characters and recent recipients as one-tap names for a new letter.

local ADDON, ns = ...
local L = ns.L

local STEP = 0.4 -- the server needs a moment between two takes
local RECENT_MAX = 10
local ATTACH = ATTACHMENTS_MAX_RECEIVE or 12

-- Game API wrappers.
local function numMail() return (GetInboxNumItems and GetInboxNumItems()) or 0 end
local function header(i)
    local _, _, sender, subject, money, cod, _, items, _, _, _, _, isGM = GetInboxHeaderInfo(i)
    return { sender = sender, subject = subject, money = money or 0, cod = cod or 0, items = items or 0, gm = isGM }
end
local function freeSlots()
    local free = 0
    for bag = 0, 4 do
        local f, family = ((C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots)(bag)
        if (family or 0) == 0 then free = free + (f or 0) end
    end
    return free
end
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

-- What Take all would get: money, item count, and letters left out (cash on delivery).
function ns.Summary()
    local s = { money = 0, items = 0, cod = 0, letters = numMail() }
    for i = 1, numMail() do
        local h = header(i)
        if h.cod > 0 or h.gm then s.cod = s.cod + 1 else
            s.money = s.money + h.money
            s.items = s.items + h.items
        end
    end
    return s
end

-- One take: the money or the first attachment of the last letter that has any.
-- Returns "money", "item", "full" (bags are full) or nil when nothing is left.
function ns.TakeOne()
    for i = numMail(), 1, -1 do
        local h = header(i)
        if h.cod == 0 and not h.gm then
            if h.money > 0 then
                TakeInboxMoney(i)
                return "money", h.money
            end
            if h.items > 0 then
                for j = 1, ATTACH do
                    if GetInboxItem(i, j) then
                        if freeSlots() == 0 then return "full" end
                        TakeInboxItem(i, j)
                        return "item"
                    end
                end
            end
        end
    end
    return nil
end

function ns.TakeAll()
    if ns.taking then return end
    ns.taking = { money = 0, items = 0 }
    local function step()
        if not ns.taking or not ns.open then ns.taking = nil; return end
        local what, amount = ns.TakeOne()
        if what == "money" then ns.taking.money = ns.taking.money + amount
        elseif what == "item" then ns.taking.items = ns.taking.items + 1 end
        if what == "money" or what == "item" then
            if ns.Refresh then ns.Refresh() end
            C_Timer.After(STEP, step)
            return
        end
        local t = ns.taking
        ns.taking = nil
        say(L.TAKEN:format(t.items, ns.Money(t.money)) .. (what == "full" and (" " .. L.FULL) or ""))
        if ns.Refresh then ns.Refresh() end
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
    })
end
