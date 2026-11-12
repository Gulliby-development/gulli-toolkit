-- Reads the public chat channels and sorts each message: groups (LFG and LFM, by dungeon),
-- selling, buying, crafting, guilds and the rest. One poster keeps one message per kind.

local ADDON, ns = ...
local L = ns.L

ns.KINDS = { "GROUP", "WTS", "WTB", "CRAFT", "GUILD", "OTHER" }

-- Dungeons and raids of WoW Forever: key, area id (for the game's own localized name; nil when
-- the area is new in Forever and its name comes from Locales), English name, level range, and
-- the words players use for it. Only what Forever has: a raid comes in when Blizzard opens it.
-- A word that starts with "~" is weak: short or common, so it names the dungeon only in a
-- message that already looks for a group.
ns.DUNGEONS = {
    { "RFC", 2437, "Ragefire Chasm", 13, 18, { "rfc", "ragefire" } },
    { "WC", 718, "Wailing Caverns", 17, 24, { "~wc", "wailing" } },
    { "DM", 1581, "The Deadmines", 17, 26, { "~dm", "deadmines", "deadmine", "~vc", "vancleef", "мертвые копи", "мёртвые копи" } },
    { "SFK", 209, "Shadowfang Keep", 22, 30, { "sfk", "shadowfang" } },
    { "BFD", 719, "Blackfathom Deeps", 24, 32, { "bfd", "blackfathom" } },
    { "STOCKS", 717, "The Stockade", 24, 32, { "~stocks", "stockade", "stockades", "~stock" } },
    { "GNOMER", 721, "Gnomeregan", 29, 38, { "gnomer", "gnomeregan", "gnomer run" } },
    { "RFK", 491, "Razorfen Kraul", 30, 40, { "rfk", "kraul" } },
    { "SM", 796, "Scarlet Monastery", 34, 45, { "~sm", "~scarlet", "smgy", "sm gy", "smlib", "sm lib", "smarm", "sm arm", "smcath", "sm cath", "~cath", "~armory", "scarlet monastery" } },
    { "RFD", 722, "Razorfen Downs", 37, 46, { "rfd", "~downs" } },
    { "ULDA", 1337, "Uldaman", 41, 51, { "ulda", "~uld", "uldaman" } },
    { "ZF", 1176, "Zul'Farrak", 44, 54, { "zf", "zul farrak", "zulfarrak", "farrak" } },
    { "MARA", 2100, "Maraudon", 46, 55, { "~mara", "maraudon" } },
    { "ST", 1417, "Sunken Temple", 50, 56, { "~st", "~sunken", "sunken temple", "atal hakkar" } },
    { "BRD", 1584, "Blackrock Depths", 52, 60, { "brd", "blackrock depths", "emp run", "arena run" } },
    { "LBRS", 1583, "Lower Blackrock Spire", 55, 60, { "lbrs" } },
    { "UBRS", 1583, "Upper Blackrock Spire", 58, 60, { "ubrs", "rend run" } },
    { "DIREMAUL", 2557, "Dire Maul", 56, 60, { "dme", "dmw", "dmn", "~dm e", "~dm w", "~dm n", "dm east", "dm west", "dm north", "dire maul", "diremaul", "~tribute" } },
    { "SCHOLO", 2057, "Scholomance", 58, 60, { "scholo", "scholomance", "sholo", "некроситет" } },
    { "STRAT", 2017, "Stratholme", 58, 60, { "strat", "strath", "stratholme", "ud strat", "live strat", "стратхольм" } },
    { "BARROW", nil, "Barrow Deeps", 60, 60, { "barrow deeps", "barrow", "barrows", "~bd" } },
    { "HYJAL", nil, "Hyjal Summit", 60, 60, { "hyjal", "hyjal summit", "mount hyjal", "хиджал" } },
    { "ONY", 2159, "Onyxia's Lair", 60, 60, { "ony", "onyxia", "onyxia s lair" } },
}
local byKey = {}
for i, d in ipairs(ns.DUNGEONS) do
    byKey[d[1]] = { key = d[1], area = d[2], name = d[3], min = d[4], max = d[5], words = d[6], order = i }
end
ns.Dungeon = function(key) return byKey[key] end

-- Words for each kind, in the languages players write in. Checked in this order.
local WORDS = {
    GUILD = { "recruit", "recruiting", "recruits", "guild", "гильдия", "гильдию", "набор в", "gilde", "hermandad",
              "guilde", "gildia", "gildii", "guilda", "公会" },
    CRAFT = { "lf enchanter", "lf ench", "lfw", "lf blacksmith", "lf bs", "lf alch", "lf alchemist", "lf tailor",
              "lf leatherworker", "lf lw", "lf engi", "can craft", "crafting", "your mats", "ur mats", "your mat",
              "lf crafter", "крафт", "скрафчу", "зачарую", "ищу зачарователя", "kann herstellen", "verzauberer",
              "fabrico", "je craft", "craftuję", "faço", "代工", "附魔" },
    WTB = { "wtb", "buying", "куплю", "покупаю", "kaufe", "compro", "achète", "achete", "kupię", "kupie", "收购", "收" },
    WTS = { "wts", "wtt", "selling", "продам", "продаю", "verkaufe", "vendo", "vends", "sprzedam", "出售", "卖" },
    LFM = { "lfm", "lf1m", "lf2m", "lf3m", "lf4m", "lf tank", "lf heal", "lf healer", "lf heals", "lf dps",
            "need tank", "need heal", "need healer", "need heals", "need dps", "need 1", "need 2", "need 3",
            "нужен", "нужны", "нужна", "лфм", "suchen", "buscamos", "cherchons", "szukamy", "procuramos", "缺" },
    LFG = { "lfg", "лфг", "ищу группу", "ищу пати", "suche gruppe", "busco grupo", "cherche groupe",
            "szukam grupy", "procuro grupo", "求组" },
}
local ORDER = { "GUILD", "CRAFT", "WTB", "WTS", "LFM", "LFG" }

-- string.lower only knows ASCII: Cyrillic and Latin-1 capitals are lowered by hand.
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
ns.Lower = lowerUtf8

-- Lower case, punctuation as spaces, padded with spaces so " word " matches whole words.
-- Item links keep only their name.
function ns.Normalize(msg)
    local s = msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")
    s = lowerUtf8(s):gsub("[%p]", " "):gsub("%s+", " ")
    return " " .. s .. " ", s
end

local function has(padded, word)
    if word:byte(1) >= 0xE4 then
        return padded:find(word, 1, true) ~= nil -- Chinese has no spaces between words
    end
    return padded:find(" " .. word .. " ", 1, true) ~= nil
end

local function any(padded, list, weakToo)
    for _, w in ipairs(list) do
        if w:sub(1, 1) == "~" then
            -- "dm me" and "pm me" ask for a private message, not for the Deadmines.
            w = w:sub(2)
            if weakToo and has(padded, w) and not has(padded, w .. " me") then return w end
        elseif has(padded, w) then
            return w
        end
    end
end

-- Returns kind ("GROUP", "WTS", ...), the dungeon key or nil, and for groups "LFM" or "LFG".
function ns.Classify(msg)
    if type(msg) ~= "string" or msg == "" then return nil end
    local padded = ns.Normalize(msg)
    local kind
    for _, k in ipairs(ORDER) do
        if any(padded, WORDS[k]) or (k == "LFM" and padded:find(" lf%dm ")) then kind = k; break end
    end
    local group = kind == "LFM" or kind == "LFG"
    local dungeon
    for _, d in ipairs(ns.DUNGEONS) do
        if any(padded, d[6], group) then dungeon = d[1]; break end
    end
    if group then return "GROUP", dungeon, kind end
    if not kind and dungeon then return "GROUP", dungeon, "LFM" end
    return kind or "OTHER", dungeon
end

-- Posts: one per poster and kind, newest first.
ns.posts = {}
ns.MAX_POSTS = 200

local function secret(v)
    return issecretvalue and issecretvalue(v)
end

function ns.Add(msg, author, channel)
    if secret(msg) or secret(author) then return end
    if type(msg) ~= "string" or type(author) ~= "string" or author == "" then return end
    local kind, dungeon, role = ns.Classify(msg)
    if not kind then return end
    if kind == "OTHER" and not ns.db.other then return end
    local repost = false
    for i = #ns.posts, 1, -1 do
        local p = ns.posts[i]
        if p.author == author and p.kind == kind then
            repost = repost or p.dungeon == dungeon
            table.remove(ns.posts, i)
        end
    end
    local post = { author = author, short = author:match("^[^-]+") or author, text = msg, kind = kind,
                   dungeon = dungeon, role = role, t = time(), channel = channel }
    table.insert(ns.posts, 1, post)
    while #ns.posts > ns.MAX_POSTS do table.remove(ns.posts) end
    if not repost then ns.Alert(post) end
    if ns.Refresh then ns.Refresh() end
    return post
end

-- Whether the group list shows a dungeon: every one while none is picked, else the picked.
function ns.Shown(key)
    if not next(ns.db.only) then return true end
    return key ~= nil and ns.db.only[key] == true
end

-- A new group for a dungeon the player watches: a sound, a chat line and a line in the hub.
-- The same poster posting again for the same dungeon is not new.
function ns.Alert(post)
    if post.kind ~= "GROUP" or not post.dungeon or not ns.db.alert[post.dungeon] then return false end
    if post.short == UnitName("player") then return false end
    local text = L.ALERT:format(post.short, ns.DungeonName(post.dungeon))
    if ns.db.sound and PlaySound then PlaySound((SOUNDKIT and SOUNDKIT.TELL_MESSAGE) or 3081) end
    if ns.db.chat then print("|cff9ad0ffGulli Bulletin|r: " .. text) end
    if GulliToolkit and GulliToolkit.Notify then GulliToolkit.Notify("Bulletin", text) end
    ns.lastAlert = text
    return true
end

function ns.Expire()
    local limit = time() - (ns.db.minutes or 15) * 60
    for i = #ns.posts, 1, -1 do
        if ns.posts[i].t < limit then table.remove(ns.posts, i) end
    end
end

function ns.FitsLevel(key, level)
    local d = byKey[key]
    if not d then return true end
    return level >= d.min - 3 and level <= d.max + 3
end

-- The posts of one kind for the window. Groups are sorted by dungeon level and get a header
-- row before each dungeon; posts without a dungeon go last.
function ns.View(kind, onlyMyLevel, level)
    ns.Expire()
    local out = {}
    if kind ~= "GROUP" then
        for _, p in ipairs(ns.posts) do if p.kind == kind then out[#out + 1] = p end end
        return out
    end
    local groups, keys = {}, {}
    for _, p in ipairs(ns.posts) do
        if p.kind == "GROUP" and ns.Shown(p.dungeon)
            and (not onlyMyLevel or not p.dungeon or ns.FitsLevel(p.dungeon, level)) then
            local k = p.dungeon or "?"
            if not groups[k] then groups[k] = {}; keys[#keys + 1] = k end
            table.insert(groups[k], p)
        end
    end
    table.sort(keys, function(a, b)
        local da, db = byKey[a], byKey[b]
        if not da then return false end
        if not db then return true end
        return da.order < db.order
    end)
    for _, k in ipairs(keys) do
        out[#out + 1] = { header = true, dungeon = byKey[k] and k or nil, count = #groups[k] }
        for _, p in ipairs(groups[k]) do out[#out + 1] = p end
    end
    return out
end

function ns.Count(kind)
    local n = 0
    for _, p in ipairs(ns.posts) do if p.kind == kind then n = n + 1 end end
    return n
end

-- The dungeon name in the client's language when the game knows the area, else English.
function ns.DungeonName(key)
    local d = byKey[key]
    if not d then return L.OTHER_GROUPS end
    local info = d.area and C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(d.area)
    local name = (type(info) == "string" and info ~= "" and info) or (not d.area and L["DG_" .. key]) or d.name
    if key == "LBRS" or key == "UBRS" then name = d.name end
    return name
end

-- Game calls.
function ns.Whisper(name)
    if ChatFrame_OpenChat then ChatFrame_OpenChat("/w " .. name .. " ") end
end

function ns.Invite(name)
    local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    if invite then invite(name) end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1, a2, _, _, _, _, _, _, a9)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliBulletinDB = GulliBulletinDB or {}
        ns.db = GulliBulletinDB
        if ns.db.minutes == nil then ns.db.minutes = 15 end
        if ns.db.myLevel == nil then ns.db.myLevel = true end
        if ns.db.other == nil then ns.db.other = false end
        ns.db.only = ns.db.only or {}
        ns.db.alert = ns.db.alert or {}
        if ns.db.sound == nil then ns.db.sound = true end
        if ns.db.chat == nil then ns.db.chat = true end
        self:RegisterEvent("CHAT_MSG_CHANNEL")
        self:RegisterEvent("CHAT_MSG_SAY")
        self:RegisterEvent("CHAT_MSG_YELL")
        return
    end
    ns.Add(a1, a2, event == "CHAT_MSG_CHANNEL" and a9 or event)
end)

SLASH_GULLIBULLETIN1 = "/gbul"
SLASH_GULLIBULLETIN2 = "/gullibulletin"
SlashCmdList.GULLIBULLETIN = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "clear" then
        wipe(ns.posts)
        print("|cff9ad0ffGulli Bulletin|r: " .. L.CLEARED)
        if ns.Refresh then ns.Refresh() end
    elseif msg == "help" then
        print("|cff9ad0ffGulli Bulletin|r: " .. L.HELP)
    else
        ns.Toggle()
    end
end

function GulliBulletin_Toggle() ns.Toggle() end

if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({
        key = "Bulletin",
        icon = "Interface\\AddOns\\Gulli-Bulletin\\icon",
        slash = "/gbul",
        open = function() ns.Toggle() end,
        window = function() return ns.Window and ns.Window() end,
    })
end
