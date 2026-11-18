-- Chat without a keyboard: ready phrases on a ring that opens while a key is held, and a small
-- panel of favourites. Each phrase goes to the first channel of a priority list that the player
-- can write in now (raid, party, guild, say, LookingForGroup, Trade...); a phrase may keep its own.

local ADDON, ns = ...
local L = ns.L

-- Every channel a phrase can go to. A new one gets a CH_<KEY> text and a case in ns.CanUse.
ns.CHANNELS = { "RAID", "PARTY", "GUILD", "SAY", "YELL", "LFG", "TRADE", "GENERAL", "WHISPER" }
-- The order a new player starts with: the group when in one, else say.
ns.DEFAULT_ORDER = { "RAID", "PARTY", "SAY" }
ns.DEFAULT_COUNT = 10
ns.RING_MAX = 8

-- The public channels by name in each client language (lower case, no spaces).
local CHANNEL_NAMES = {
    LFG = { "lookingforgroup", "поисксспутников", "поискспутников", "suchenachgruppe", "buscargrupo",
            "recherchegroupe", "procurandogrupo", "szukaniegrupy", "寻求组队", "尋求組隊" },
    TRADE = { "trade", "торговля", "handel", "comercio", "commerce", "comércio", "交易" },
    GENERAL = { "general", "общий", "allgemein", "general", "général", "ogólny", "geral", "综合", "綜合" },
}

local function secret(v) return issecretvalue and issecretvalue(v) end

-- Lower case for Latin-1 and Cyrillic too (string.lower knows only A-Z).
local function lowerUtf8(s)
    s = s:lower()
    s = s:gsub("\208([\144-\159])", function(c) return "\208" .. string.char(c:byte() + 32) end)
    s = s:gsub("\208([\160-\175])", function(c) return "\209" .. string.char(c:byte() - 32) end)
    s = s:gsub("\208\129", "\209\145")
    s = s:gsub("\195([\128-\158])", function(c)
        if c == "\151" then return "\195\151" end
        return "\195" .. string.char(c:byte() + 32)
    end)
    return s
end

---- Phrases ------------------------------------------------------------------------------------

-- The phrases: the player's own list, or the defaults of their language.
function ns.Phrases()
    if ns.db.phrases then return ns.db.phrases end
    local out = {}
    for i = 1, ns.DEFAULT_COUNT do out[i] = L["P" .. i] end
    return out
end

function ns.IsDefault(text)
    for i = 1, ns.DEFAULT_COUNT do if L["P" .. i] == text then return true end end
    return false
end

local function own()
    if not ns.db.phrases then
        local copy = {}
        for i, p in ipairs(ns.Phrases()) do copy[i] = p end
        ns.db.phrases = copy
    end
    return ns.db.phrases
end

function ns.AddPhrase(text)
    text = strtrim(text or "")
    if text == "" then return false end
    for _, p in ipairs(ns.Phrases()) do if p == text then return false end end
    local list = own()
    list[#list + 1] = text
    return true
end

-- Removes a phrase from the list, the ring, the favourites and its own channel order.
function ns.RemovePhrase(text)
    local list = own()
    for i = #list, 1, -1 do if list[i] == text then table.remove(list, i) end end
    local ring = ns.Ring()
    for i = 1, ns.RING_MAX do if ring[i] == text then ns.SetRing(i, nil) end end
    ns.db.fav[text], ns.db.orderOf[text] = nil, nil
end

function ns.ResetPhrases()
    ns.db.phrases, ns.db.ring = nil, nil
    wipe(ns.db.fav); wipe(ns.db.orderOf)
end

-- Puts the default phrases back on the ring; the player's own phrases stay in the list.
function ns.ResetRing()
    ns.db.ring = nil
    if not ns.db.phrases then return end
    for i = 1, math.min(ns.RING_MAX, ns.DEFAULT_COUNT) do
        local p, found = L["P" .. i], false
        for _, q in ipairs(ns.db.phrases) do if q == p then found = true end end
        if not found then table.insert(ns.db.phrases, i, p) end
    end
end

function ns.ToggleFav(text)
    ns.db.fav[text] = (not ns.db.fav[text]) or nil
end

---- The ring -------------------------------------------------------------------------------------

-- Up to eight places; place i is a phrase or nil. A new player gets the first eight defaults.
function ns.Ring()
    if not ns.db.ring then
        local ring = {}
        for i = 1, ns.RING_MAX do ring[i] = L["P" .. i] end
        return ring
    end
    return ns.db.ring
end

local function ownRing()
    if not ns.db.ring then
        local ring = {}
        for i = 1, ns.RING_MAX do ring[i] = L["P" .. i] end
        ns.db.ring = ring
    end
    return ns.db.ring
end

-- Puts a phrase on place i (nil clears it). A phrase is on the ring once: it leaves its old place.
function ns.SetRing(i, text)
    if i < 1 or i > ns.RING_MAX then return false end
    local ring = ownRing()
    if text then
        for j = 1, ns.RING_MAX do if ring[j] == text then ring[j] = false end end
    end
    ring[i] = text or false
    return true
end

function ns.RingPlace(text)
    local ring = ns.Ring()
    for i = 1, ns.RING_MAX do if ring[i] == text then return i end end
end

-- The phrases of the ring in place order, without the empty places, with their place.
function ns.RingList()
    local out, places = {}, {}
    local ring = ns.Ring()
    for i = 1, ns.RING_MAX do
        if ring[i] then out[#out + 1] = ring[i]; places[#out] = i end
    end
    return out, places
end

-- The panel: the starred phrases, else the ring's; at most n.
function ns.Favorites(n)
    n = n or 8
    local out = {}
    for _, p in ipairs(ns.Phrases()) do
        if ns.db.fav[p] and #out < n then out[#out + 1] = p end
    end
    if #out == 0 then
        for _, p in ipairs((ns.RingList())) do if #out < n then out[#out + 1] = p end end
    end
    return out
end

---- Where a phrase goes ------------------------------------------------------------------------------

-- The channel order: a list of the channels that are on, first first. A phrase may have its own.
function ns.Order(text)
    return (text and ns.db.orderOf[text]) or ns.db.order
end

function ns.HasOwnOrder(text) return ns.db.orderOf[text] ~= nil end

-- Gives a phrase its own order (a copy of the default) or takes it away.
function ns.SetOwnOrder(text, on)
    if on then
        local copy = {}
        for i, k in ipairs(ns.db.order) do copy[i] = k end
        ns.db.orderOf[text] = copy
    else
        ns.db.orderOf[text] = nil
    end
end

local function indexOf(list, key)
    for i, k in ipairs(list) do if k == key then return i end end
end
ns.IndexOf = indexOf

-- Switches a channel on (to the end of the order) or off.
function ns.ToggleChannel(list, key)
    local i = indexOf(list, key)
    if i then table.remove(list, i) else list[#list + 1] = key end
end

-- Moves a channel that is on one place up (-1) or down (1).
function ns.MoveChannel(list, key, d)
    local i = indexOf(list, key)
    local j = i and i + d
    if not j or j < 1 or j > #list then return false end
    list[i], list[j] = list[j], list[i]
    return true
end

-- The id of a joined public channel (LFG, TRADE, GENERAL), by its name in any client language.
function ns.ChannelId(key)
    local names = CHANNEL_NAMES[key]
    if not names or not GetChannelList then return nil end
    local list = { GetChannelList() }
    for i = 1, #list, 3 do
        local id, name = list[i], list[i + 1]
        if type(name) == "string" and not secret(name) then
            local n = lowerUtf8(name):gsub("%s", "")
            for _, want in ipairs(names) do
                if n:find(want, 1, true) then return id end
            end
        end
    end
end

local function whisperTarget()
    local who = UnitName("target")
    if who and not secret(who) and UnitIsPlayer and UnitIsPlayer("target") then return who end
    return ns.lastWhisper
end

-- Whether the player can write in a channel now: the kind for SendChatMessage and its target.
function ns.CanUse(key)
    if key == "RAID" then
        if IsInRaid and IsInRaid() then return "RAID" end
    elseif key == "PARTY" then
        if IsInGroup and IsInGroup() then return "PARTY" end
    elseif key == "GUILD" then
        if IsInGuild and IsInGuild() then return "GUILD" end
    elseif key == "SAY" or key == "YELL" then
        return key
    elseif key == "WHISPER" then
        local who = whisperTarget()
        if who then return "WHISPER", who end
    else
        local id = ns.ChannelId(key)
        if id then return "CHANNEL", id end
    end
end

-- The game refuses say and yell from an addon outside an instance, and the numbered channels
-- whenever it does not count the call as the player's own press (ADDON_ACTION_BLOCKED): a phrase
-- for them goes into the chat box and the player sends it with Enter. Party, raid, guild and
-- whispers always go out at once.
ns.NEEDS_PRESS = { SAY = true, YELL = true, CHANNEL = true }
local function inInstance()
    local inside = IsInInstance and IsInInstance()
    return inside and true or false
end
function ns.ToBox(kind)
    if not ns.NEEDS_PRESS[kind] then return false end
    if (kind == "SAY" or kind == "YELL") and inInstance() then return false end
    return true
end
local SLASH = { SAY = "/s ", YELL = "/y " }

-- Opens the chat box with the message and the command of its channel (/s, /y, /2).
function ns.ToChatBox(msg, kind, to)
    local open = (ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat
    if not open then return false end
    open((SLASH[kind] or ("/" .. tostring(to) .. " ")) .. msg)
    return true
end

-- The first channel of the phrase's order that works now: key, kind, target.
function ns.Route(text)
    for _, key in ipairs(ns.Order(text)) do
        local kind, to = ns.CanUse(key)
        if kind then return key, kind, to end
    end
end

---- Filling and sending ------------------------------------------------------------------------

local function leaderName()
    if not (IsInGroup and IsInGroup()) then return nil end
    local raid = IsInRaid and IsInRaid()
    for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do
        local unit = (raid and "raid" or "party") .. i
        if UnitIsGroupLeader and UnitIsGroupLeader(unit) then
            local name = UnitName(unit)
            if not (issecretvalue and issecretvalue(name)) then return name end
        end
    end
end

-- {target}, {zone}, {me}, {level}, {targetclass}, {targetlevel}, {hp}, {mana}, {leader} and
-- {item} (the item the player last Shift-clicked).
function ns.Fill(text)
    local target = UnitName("target")
    if secret(target) then target = nil end
    local tclass = target and UnitClass and UnitClass("target") or nil
    local tlevel = target and UnitLevel("target") or nil
    if secret(tlevel) then tlevel = nil end
    -- Health and power are secret values in combat: no percent then, never arithmetic on them.
    local function pct(cur, max)
        if secret(cur) or secret(max) then return "" end
        cur, max = cur or 0, max or 0
        if max <= 0 then return "" end
        return tostring(math.floor(cur / max * 100 + 0.5)) .. "%"
    end
    local values = {
        target = target or "", zone = (GetZoneText and GetZoneText()) or "",
        me = UnitName("player") or "", level = tostring(UnitLevel("player") or ""),
        targetclass = (not secret(tclass) and tclass) or "", targetlevel = tlevel and tostring(tlevel) or "",
        hp = pct(UnitHealth and UnitHealth("player"), UnitHealthMax and UnitHealthMax("player")),
        mana = pct(UnitPower and UnitPower("player", 0), UnitPowerMax and UnitPowerMax("player", 0)),
        leader = leaderName() or "", item = ns.lastLink or "",
    }
    return (text:gsub("{(%a+)}", function(k) return values[k:lower()] end):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

-- A double tap sends a message once: the same text to the same place is held for 3 seconds.
ns.REPEAT_GAP = 3
local function tooSoon(key)
    local now = GetTime and GetTime() or time()
    if ns.lastSent and ns.lastSent.key == key and now - ns.lastSent.t < ns.REPEAT_GAP then return true end
    ns.lastSent = { key = key, t = now }
    return false
end

-- Sends a phrase to the first channel of its order that works now. Returns the channel key.
-- True when the phrase would go into the chat box (say, yell, a numbered channel) right now.
function ns.NeedsPress(text)
    local _, kind = ns.Route(text)
    return kind ~= nil and ns.ToBox(kind)
end

function ns.Say(text)
    local msg = ns.Fill(text)
    if msg == "" then return false end
    local key, kind, to = ns.Route(text)
    if not key then
        print("|cff9ad0ffGulli Quick Chat|r: " .. L.NO_CHANNEL)
        return false
    end
    if ns.ToBox(kind) then return ns.ToChatBox(msg, kind, to) and key or false end
    if tooSoon(kind .. "|" .. tostring(to) .. "|" .. msg) then return false end
    SendChatMessage(msg, kind, nil, to)
    return key
end

---- Setup --------------------------------------------------------------------------------------

ns.DEFAULTS = { wheelKey = nil, wheelHold = true, panelShow = false, panelCount = 6,
                panelScale = 100, panelRow = false }

-- Saves of 1.x had one channel for the window (AUTO = raid, party or say) and one per phrase.
local OLD = { AUTO = { "RAID", "PARTY", "SAY" }, SAY = { "SAY" }, PARTY = { "PARTY" }, GUILD = { "GUILD" },
              WHISPER = { "WHISPER" }, LEADER = { "PARTY" }, RAID = { "RAID" } }

local function copy(t)
    local out = {}
    for i, v in ipairs(t) do out[i] = v end
    return out
end

function ns.Defaults()
    local db = ns.db
    for k, v in pairs(ns.DEFAULTS) do if db[k] == nil then db[k] = v end end
    -- Frames on the screen start hidden (owner's decision): a panel shown before is hidden once;
    -- the hub's Unlock mode or the switch shows it again. The panel has no lock of its own.
    if not db.hudHidden then db.panelShow, db.hudHidden = false, true end
    db.panelLocked = nil
    db.fav = db.fav or {}
    db.orderOf = db.orderOf or {}
    if not db.order then
        db.order = copy(OLD[db.channel or "AUTO"] or ns.DEFAULT_ORDER)
        for text, ch in pairs(db.chan or {}) do
            if OLD[ch] and ch ~= "AUTO" then db.orderOf[text] = copy(OLD[ch]) end
        end
    end
    -- Gone with 2.0: categories, whispers, history, the group message reminder.
    for _, k in ipairs({ "channel", "chan", "cat", "history", "log", "autoBusy", "busyMinutes", "sound",
                         "remind", "keepLog", "always" }) do db[k] = nil end
end

function ns.ResetSettings()
    for k in pairs(ns.DEFAULTS) do ns.db[k] = nil end
    ns.db.panelPoint, ns.db.order = nil, nil
    ns.Defaults()
    if ns.ApplyKey then ns.ApplyKey() end
    if ns.Panel then ns.Panel() end
    if ns.Refresh then ns.Refresh() end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1, a2)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliQuickChatDB = GulliQuickChatDB or {}
        ns.db = GulliQuickChatDB
        ns.Defaults()
        self:RegisterEvent("CHAT_MSG_WHISPER")
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        -- {item}: the last item link the player Shift-clicked.
        if hooksecurefunc and ChatEdit_InsertLink then
            hooksecurefunc("ChatEdit_InsertLink", function(link)
                if type(link) == "string" and link:find("|Hitem:") then ns.lastLink = link end
            end)
        end
        if ns.Setup then ns.Setup() end
        return
    end
    if event == "CHAT_MSG_WHISPER" then
        -- The Whisper channel answers the last player who whispered when no player is targeted.
        if not secret(a2) and type(a2) == "string" then ns.lastWhisper = a2 end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if ns.ApplyKey then ns.ApplyKey() end
    end
end)

SLASH_GULLIQUICKCHAT1 = "/gqk"
SLASH_GULLIQUICKCHAT2 = "/gulliquickchat"
SlashCmdList.GULLIQUICKCHAT = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "wheel" then
        if ns.ToggleWheel then ns.ToggleWheel() end
    else
        ns.Toggle()
    end
end

function GulliQuickChat_Toggle() ns.Toggle() end

ns.OPT_ICON = {
    panelShow = "Interface\\Icons\\INV_Misc_Note_05",
    wheelHold = "Interface\\Icons\\INV_Misc_EngGizmos_20",
}

local function option(key, label, tip)
    return { label = label, icon = ns.OPT_ICON[key], tip = tip,
             get = function() return ns.db ~= nil and ns.db[key] == true end,
             set = function(on)
                 if not ns.db then return end
                 ns.db[key] = on and true or false
                 if ns.Panel then ns.Panel() end
             end }
end

if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({
        key = "QuickChat",
        icon = "Interface\\AddOns\\Gulli-QuickChat\\icon",
        slash = "/gqk",
        open = function() ns.Toggle() end,
        window = function() return ns.Window and ns.Window() end,
        options = {
            option("wheelHold", L.WHEEL_HOLD, L.WHEEL_HOLD_D),
        },
        move = function(on) if ns.MovePanel then ns.MovePanel(on) end end,
        frames = { { key = "panel", label = L.TITLE, icon = ns.OPT_ICON.panelShow,
                     get = function() return ns.db ~= nil and ns.db.panelShow == true end,
                     set = function(on) if ns.db then ns.db.panelShow = on and true or false; if ns.Panel then ns.Panel() end end end,
                     frame = function() return ns.PanelFrame and ns.PanelFrame() end } },
        reset = function() ns.ResetSettings() end,
    })
end
