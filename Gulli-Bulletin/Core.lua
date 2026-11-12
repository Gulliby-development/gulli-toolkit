-- Reads the public chat channels and sorts each message: groups (LFG and LFM, by dungeon),
-- selling, buying, crafting, guilds and the rest. One poster keeps one message per kind.

local ADDON, ns = ...
local L = ns.L

ns.KINDS = { "GROUP", "WTS", "WTB", "CRAFT", "GUILD", "OTHER" }

-- Dungeons and raids: key, area id (for the game's own localized name), English name,
-- level range, and the words players use for it.
ns.DUNGEONS = {
    { "RFC", 2437, "Ragefire Chasm", 13, 18, { "rfc", "ragefire" } },
    { "WC", 718, "Wailing Caverns", 17, 24, { "wc", "wailing" } },
    { "DM", 1581, "The Deadmines", 17, 26, { "dm", "deadmines", "deadmine", "vc", "vancleef", "мертвые копи", "мёртвые копи" } },
    { "SFK", 209, "Shadowfang Keep", 22, 30, { "sfk", "shadowfang" } },
    { "BFD", 719, "Blackfathom Deeps", 24, 32, { "bfd", "blackfathom" } },
    { "STOCKS", 717, "The Stockade", 24, 32, { "stocks", "stockade", "stockades", "stock" } },
    { "GNOMER", 721, "Gnomeregan", 29, 38, { "gnomer", "gnomeregan", "gnomer run" } },
    { "RFK", 491, "Razorfen Kraul", 30, 40, { "rfk", "kraul" } },
    { "SM", 796, "Scarlet Monastery", 34, 45, { "sm", "scarlet", "smgy", "sm gy", "smlib", "sm lib", "smarm", "sm arm", "smcath", "sm cath", "cath", "armory" } },
    { "RFD", 722, "Razorfen Downs", 37, 46, { "rfd", "downs" } },
    { "ULDA", 1337, "Uldaman", 41, 51, { "ulda", "uld", "uldaman" } },
    { "ZF", 1176, "Zul'Farrak", 44, 54, { "zf", "zul farrak", "zulfarrak", "farrak" } },
    { "MARA", 2100, "Maraudon", 46, 55, { "mara", "maraudon" } },
    { "ST", 1417, "Sunken Temple", 50, 56, { "st", "sunken", "atal hakkar" } },
    { "BRD", 1584, "Blackrock Depths", 52, 60, { "brd", "blackrock depths", "emp run", "arena run" } },
    { "LBRS", 1583, "Lower Blackrock Spire", 55, 60, { "lbrs" } },
    { "UBRS", 1583, "Upper Blackrock Spire", 58, 60, { "ubrs", "rend run" } },
    { "DIREMAUL", 2557, "Dire Maul", 56, 60, { "dme", "dmw", "dmn", "dm e", "dm w", "dm n", "dm east", "dm west", "dm north", "dire maul", "diremaul", "tribute" } },
    { "SCHOLO", 2057, "Scholomance", 58, 60, { "scholo", "scholomance", "sholo", "некроситет" } },
    { "STRAT", 2017, "Stratholme", 58, 60, { "strat", "strath", "stratholme", "ud strat", "live strat", "стратхольм" } },
    { "ZG", 1977, "Zul'Gurub", 60, 60, { "zg", "zul gurub", "zulgurub" } },
    { "AQ20", 3429, "Ruins of Ahn'Qiraj", 60, 60, { "aq20", "aq 20", "ruins of ahn qiraj" } },
    { "MC", 2717, "Molten Core", 60, 60, { "mc", "molten core", "огненные недра" } },
    { "ONY", 2159, "Onyxia's Lair", 60, 60, { "ony", "onyxia", "onyxia s lair" } },
    { "BWL", 2677, "Blackwing Lair", 60, 60, { "bwl", "blackwing" } },
    { "AQ40", 3428, "Temple of Ahn'Qiraj", 60, 60, { "aq40", "aq 40", "aq" } },
    { "NAXX", 3456, "Naxxramas", 60, 60, { "naxx", "naxxramas" } },
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

local function any(padded, list)
    for _, w in ipairs(list) do if has(padded, w) then return w end end
end

-- Returns kind ("GROUP", "WTS", ...), the dungeon key or nil, and for groups "LFM" or "LFG".
function ns.Classify(msg)
    if type(msg) ~= "string" or msg == "" then return nil end
    local padded = ns.Normalize(msg)
    local kind
    for _, k in ipairs(ORDER) do
        if any(padded, WORDS[k]) or (k == "LFM" and padded:find(" lf%dm ")) then kind = k; break end
    end
    local dungeon
    for _, d in ipairs(ns.DUNGEONS) do
        if any(padded, d[6]) then dungeon = d[1]; break end
    end
    if kind == "LFM" or kind == "LFG" then return "GROUP", dungeon, kind end
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
    for i = #ns.posts, 1, -1 do
        local p = ns.posts[i]
        if p.author == author and p.kind == kind then table.remove(ns.posts, i) end
    end
    local post = { author = author, short = author:match("^[^-]+") or author, text = msg, kind = kind,
                   dungeon = dungeon, role = role, t = time(), channel = channel }
    table.insert(ns.posts, 1, post)
    while #ns.posts > ns.MAX_POSTS do table.remove(ns.posts) end
    if ns.Refresh then ns.Refresh() end
    return post
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
        if p.kind == "GROUP" and (not onlyMyLevel or not p.dungeon or ns.FitsLevel(p.dungeon, level)) then
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
    local info = C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(d.area)
    local name = (type(info) == "string" and info ~= "" and info) or d.name
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
