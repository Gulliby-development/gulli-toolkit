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

-- Crafting: every profession (not only the player's), by the words that name it. `who` names the
-- crafter or the service (an enchant, a lockbox); `also` only the trade. A post asks for a crafter
-- (LF: "lf enchanter", "need bs") or offers one (OFFER: "lfw", "can craft", an enchant link).
ns.PROFS = { "ENCH", "BS", "TAILOR", "LW", "ALCH", "ENGI", "COOK", "LOCK" }
local PROF_WORDS = {
    ENCH = { who = { "enchanter", "enchanters", "enchant", "enchants", "зачарователь", "зачарователя", "энчантер",
                     "чантер", "verzauberer", "encantador", "enchanteur", "zaklinacz", "附魔师" },
             also = { "ench", "enchanting", "зачарование", "зачарка", "verzauberkunst", "encantamiento",
                      "enchantement", "zaklinanie", "encantamento", "附魔" } },
    BS = { who = { "blacksmith", "кузнец", "кузнеца", "schmied", "herrero", "forgeron", "kowal", "ferreiro", "铁匠" },
           also = { "bs", "blacksmithing", "кузнечное", "schmiedekunst", "herrería", "forge", "kowalstwo",
                    "ferraria", "锻造" } },
    TAILOR = { who = { "tailor", "портной", "портного", "schneider", "sastre", "tailleur", "krawiec", "alfaiate", "裁缝" },
               also = { "tailoring", "портняжное", "schneiderei", "sastrería", "couture", "krawiectwo", "alfaiataria" } },
    LW = { who = { "leatherworker", "кожевник", "кожевника", "lederer", "peletero", "travailleur du cuir", "kaletnik",
                   "coureiro", "制皮师" },
           also = { "lw", "leatherworking", "кожевничество", "lederverarbeitung", "peletería", "travail du cuir",
                    "kaletnictwo", "couraria", "制皮" } },
    ALCH = { who = { "alchemist", "алхимик", "алхимика", "alchimist", "alquimista", "alchimiste", "alchemik", "炼金师" },
             also = { "alch", "alchemy", "алхимия", "alchemie", "alquimia", "alchimie", "炼金" } },
    ENGI = { who = { "engineer", "инженер", "инженера", "ingenieur", "ingeniero", "ingénieur", "inżynier",
                     "engenheiro", "工程师" },
             also = { "engi", "engy", "engineering", "инженерия", "ingenieurskunst", "ingeniería", "ingénierie",
                      "inżynieria", "engenharia", "工程学" } },
    COOK = { who = { "cook", "повар", "повара", "koch", "cocinero", "cuisinier", "kucharz", "cozinheiro", "厨师" },
             also = { "cooking", "кулинария", "kochkunst", "cocina", "cuisine", "gotowanie", "culinária", "烹饪" } },
    LOCK = { who = { "lockpick", "lockpicker", "lockpicking", "lockbox", "lockboxes", "взломщик", "вскрыть", "вскрою",
                     "schlossknacken", "forzar cerraduras", "crochetage", "otwieranie zamków", "arrombamento", "开锁" },
             also = {} },
}
-- Asks for a crafter when one of these comes right before a profession word.
local LF_WORDS = { "lf", "lf a", "lf an", "need", "need a", "need an", "needs", "looking for", "looking for a",
                   "looking for an", "any", "wtb", "ищу", "нужен", "нужна", "нужен ли", "suche", "suche einen", "busco",
                   "busco un", "cherche", "cherche un", "szukam", "procuro", "procuro um", "找" }
-- Offers a craft: work wanted, own mats, tips.
local OFFER_WORDS = { "lfw", "lf work", "lf job", "lf jobs", "can craft", "crafting", "your mats", "ur mats", "your mat",
                      "free enchants", "enchanting service", "скрафчу", "крафчу", "зачарую", "чарю",
                      "ваши реги", "твои реги", "kann herstellen", "fabrico", "je craft", "craftuję", "faço", "代工" }
-- Offer words that count only next to a profession ("enchants, tips welcome").
local OFFER_WEAK = { "tips", "tip", "tips welcome", "чаевые", "trinkgeld", "propina", "pourboire", "napiwek", "gorjeta" }
-- Generic crafting asks without a profession.
local ASK_WORDS = { "lf crafter", "need crafter", "ищу крафтера", "ищу зачарователя", "suche handwerker" }
-- Selling a recipe is selling an item, not a craft.
local RECIPE_WORDS = { "recipe", "formula", "pattern", "schematic", "plans", "рецепт", "формула", "выкройка",
                       "чертеж", "чертёж", "rezept", "receta", "recette", "przepis", "receita", "配方", "图纸" }

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

-- The profession a crafting post names, and whether that name comes after an LF word.
local function profOf(padded)
    for _, key in ipairs(ns.PROFS) do
        local w = PROF_WORDS[key]
        for _, list in ipairs({ w.who, w.also }) do
            for _, word in ipairs(list) do
                if has(padded, word) then
                    for _, lf in ipairs(LF_WORDS) do
                        if has(padded, lf .. " " .. word) then return key, true end
                    end
                    return key, false, list == w.who
                end
            end
        end
    end
end

-- "LF" (asks for a crafter) or "OFFER" (offers a craft) and the profession, or nil when the
-- message is not about crafting.
function ns.Craft(msg, padded)
    padded = padded or ns.Normalize(msg)
    local prof, asked, named = profOf(padded)
    local link = msg:find("|Henchant:") or msg:find("|Htrade:")
    if any(padded, RECIPE_WORDS) and not any(padded, OFFER_WORDS) then return nil end
    if any(padded, OFFER_WORDS) or link then
        return "OFFER", prof or (link and msg:find("|Henchant:") and "ENCH") or nil
    end
    if asked then return "LF", prof end
    if prof and any(padded, OFFER_WEAK) then return "OFFER", prof end
    if any(padded, ASK_WORDS) then return "LF", prof end
    -- "WTS enchants", "WTB lockbox opened": a service named after selling or buying words.
    if named then
        if any(padded, WORDS.WTS) then return "OFFER", prof end
        if any(padded, WORDS.WTB) then return "LF", prof end
    end
end

-- Returns kind ("GROUP", "WTS", ...), the dungeon key or nil, and for groups "LFM" or "LFG".
-- A crafting post returns "CRAFT", nil, "LF" or "OFFER", and the profession key or nil.
function ns.Classify(msg)
    if type(msg) ~= "string" or msg == "" then return nil end
    local padded = ns.Normalize(msg)
    if not any(padded, WORDS.GUILD) then
        local mode, prof = ns.Craft(msg, padded)
        if mode then return "CRAFT", nil, mode, prof end
    end
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

-- The roles an LFM message asks for, in the order tank, healer, damage.
ns.ROLES = { "TANK", "HEALER", "DPS" }
local ROLE_WORDS = {
    TANK = { "tank", "tanks", "танк", "танка", "tanque", "czołg", "坦克", "坦" },
    HEALER = { "heal", "heals", "healer", "healers", "хил", "хила", "хилл", "лекарь", "heiler", "sanador",
               "soigneur", "soin", "healera", "curador", "治疗", "奶" },
    DPS = { "dps", "dd", "дд", "дпс", "рдд", "мдд", "dmg", "damage", "dégâts", "伤害" },
}
function ns.Needs(msg)
    local padded = ns.Normalize(msg)
    local out = {}
    for _, r in ipairs(ns.ROLES) do
        if any(padded, ROLE_WORDS[r]) then out[#out + 1] = r end
    end
    return out
end

-- The first item link in a message: its id.
function ns.ItemOf(msg)
    return tonumber(msg:match("|Hitem:(%d+)"))
end

-- Comma lists the player types (blocked words, watched words), lowered.
function ns.Words(text)
    local out = {}
    for w in (text or ""):gmatch("[^,]+") do
        w = lowerUtf8(strtrim(w))
        if w ~= "" then out[#out + 1] = w end
    end
    return out
end

local function anyWord(padded, text)
    for _, w in ipairs(ns.Words(text)) do
        if padded:find(w, 1, true) then return w end
    end
end

-- Players and words the player hid.
function ns.Blocked(msg, short)
    if ns.db.blockNames[lowerUtf8(short or "")] then return true end
    return anyWord(ns.Normalize(msg), ns.db.blockWords) ~= nil
end

function ns.BlockPlayer(short)
    if not short or short == "" then return end
    ns.db.blockNames[lowerUtf8(short)] = true
    local name = lowerUtf8(short)
    for i = #ns.posts, 1, -1 do
        if lowerUtf8(ns.posts[i].short) == name then table.remove(ns.posts, i) end
    end
    if ns.Refresh then ns.Refresh() end
end

function ns.BlockedCount()
    local n = 0
    for _ in pairs(ns.db.blockNames) do n = n + 1 end
    return n
end

-- Posts: one per poster and kind, newest first. They live in the saved variables, so the board
-- is still there after a /reload.
ns.posts = {}
ns.MAX_POSTS = 200

local function secret(v)
    return issecretvalue and issecretvalue(v)
end

local function classOf(guid)
    if type(guid) ~= "string" or guid == "" or secret(guid) or not GetPlayerInfoByGUID then return nil end
    local _, class = GetPlayerInfoByGUID(guid)
    return class
end

function ns.Add(msg, author, channel, guid)
    if secret(msg) or secret(author) then return end
    if type(msg) ~= "string" or type(author) ~= "string" or author == "" then return end
    local kind, dungeon, role, prof = ns.Classify(msg)
    local craft
    if kind == "CRAFT" then craft, role = role or "OFFER", nil end
    if not kind then return end
    if kind == "OTHER" and not ns.db.other then return end
    local short = author:match("^[^-]+") or author
    if ns.Blocked(msg, short) then return end
    local repost = false
    for i = #ns.posts, 1, -1 do
        local p = ns.posts[i]
        if p.author == author and p.kind == kind then
            repost = repost or p.dungeon == dungeon
            table.remove(ns.posts, i)
        end
    end
    local post = { author = author, short = short, text = msg, kind = kind, dungeon = dungeon, role = role,
                   t = time(), channel = channel, class = classOf(guid), item = ns.ItemOf(msg),
                   craft = craft, prof = prof,
                   needs = role == "LFM" and ns.Needs(msg) or nil }
    table.insert(ns.posts, 1, post)
    while #ns.posts > ns.MAX_POSTS do table.remove(ns.posts) end
    if not repost then
        if not ns.Alert(post) then ns.Watch(post) end
    end
    if ns.Feed then ns.Feed() end
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
    return ns.Ring(L.ALERT:format(post.short, ns.DungeonName(post.dungeon)))
end

-- A post that has a word the player watches (an item, a profession...).
function ns.Watch(post)
    if post.short == UnitName("player") then return false end
    local w = anyWord(ns.Normalize(post.text), ns.db.watch)
    if not w then return false end
    return ns.Ring(L.WATCHED:format(post.short, w))
end

function ns.Ring(text)
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
ns.collapsed = {}

-- query: text the post or the poster must have (the search box).
function ns.View(kind, onlyMyLevel, level, query)
    ns.Expire()
    local out = {}
    query = query and query ~= "" and lowerUtf8(query) or nil
    local function match(p)
        return not query or lowerUtf8(p.text):find(query, 1, true) or lowerUtf8(p.short):find(query, 1, true)
            or (p.dungeon and lowerUtf8(ns.DungeonName(p.dungeon)):find(query, 1, true))
    end
    if kind ~= "GROUP" then
        for _, p in ipairs(ns.posts) do
            if p.kind == kind and match(p) and (kind ~= "CRAFT" or ns.CraftShown(p)) then out[#out + 1] = p end
        end
        return out
    end
    local groups, keys = {}, {}
    for _, p in ipairs(ns.posts) do
        if p.kind == "GROUP" and ns.Shown(p.dungeon) and match(p)
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
        local closed = ns.collapsed[k] == true
        out[#out + 1] = { header = true, dungeon = byKey[k] and k or nil, key = k, count = #groups[k], closed = closed }
        if not closed then
            for _, p in ipairs(groups[k]) do out[#out + 1] = p end
        end
    end
    return out
end

-- The Crafting tab: ALL, LF (people who look for a crafter) or OFFER (crafters), and the
-- professions picked (none = all). A post without a profession shows only while none is picked.
function ns.CraftShown(p, mode)
    mode = mode or ns.db.craftMode or "ALL"
    if mode ~= "ALL" and (p.craft or "OFFER") ~= mode then return false end
    if not next(ns.db.craftProfs) then return true end
    return p.prof ~= nil and ns.db.craftProfs[p.prof] == true
end

function ns.CraftCount(mode)
    local n = 0
    for _, p in ipairs(ns.posts) do
        if p.kind == "CRAFT" and ns.CraftShown(p, mode) then n = n + 1 end
    end
    return n
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

-- "Hi! Level 56 priest, healer. Can I join for Stratholme?"
function ns.AskText(post)
    local className = UnitClass("player") or ""
    local role = L["ROLE_" .. (ns.db.role or "DPS")]
    local where = post.dungeon and ns.DungeonName(post.dungeon) or L.YOUR_GROUP
    return L.ASK:format(UnitLevel("player") or 0, className, role, where)
end

function ns.Ask(post)
    if not post or not SendChatMessage then return false end
    SendChatMessage(ns.AskText(post), "WHISPER", nil, post.author)
    return true
end

-- The channels the board reads groups and trade from, in each client language.
local CHANNELS = {
    LFG = { "lookingforgroup", "поисксспутников", "поискспутников", "suchenachgruppe", "buscargrupo",
            "recherchegroupe", "procurandogrupo", "szukaniegrupy", "寻求组队", "尋求組隊" },
    TRADE = { "trade", "торговля", "handel", "comercio", "commerce", "comércio", "交易" },
}
-- Which of LookingForGroup and Trade the player has not joined: { "LFG", "TRADE" }.
function ns.MissingChannels()
    if not GetChannelList then return {} end
    local list = { GetChannelList() }
    local have = {}
    for i = 1, #list, 3 do
        local name = list[i + 1]
        if type(name) == "string" and not secret(name) then
            local n = lowerUtf8(name):gsub("%s", "")
            for key, names in pairs(CHANNELS) do
                for _, want in ipairs(names) do if n:find(want, 1, true) then have[key] = true end end
            end
        end
    end
    local out = {}
    for _, key in ipairs({ "LFG", "TRADE" }) do if not have[key] then out[#out + 1] = key end end
    return out
end

-- Opens Gulli Quick Chat's group message for a dungeon, when Quick Chat is installed.
function ns.CanPostLFM()
    return GulliQuickChat ~= nil and type(GulliQuickChat.OpenLFM) == "function"
end

function ns.PostLFM(key)
    if not ns.CanPostLFM() then return false end
    GulliQuickChat.OpenLFM(key)
    return true
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
f:SetScript("OnEvent", function(self, event, a1, a2, _, _, _, _, _, _, a9, _, _, a12)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliBulletinDB = GulliBulletinDB or {}
        ns.db = GulliBulletinDB
        if ns.db.minutes == nil then ns.db.minutes = 15 end
        if ns.db.myLevel == nil then ns.db.myLevel = true end
        if ns.db.other == nil then ns.db.other = false end
        ns.db.only = ns.db.only or {}
        ns.db.alert = ns.db.alert or {}
        ns.db.craftProfs = ns.db.craftProfs or {}
        ns.db.craftMode = ns.db.craftMode or "ALL"
        if ns.db.sound == nil then ns.db.sound = true end
        if ns.db.chat == nil then ns.db.chat = true end
        ns.db.blockNames = ns.db.blockNames or {}
        ns.db.blockWords = ns.db.blockWords or ""
        ns.db.watch = ns.db.watch or ""
        ns.db.role = ns.db.role or "DPS"
        ns.db.feed = ns.db.feed or {}
        local feed = ns.db.feed
        if feed.alpha == nil then feed.alpha = 80 end
        ns.db.posts = ns.db.posts or {}
        ns.posts = ns.db.posts
        ns.Expire()
        if ns.SetupFeed then ns.SetupFeed() end
        self:RegisterEvent("CHAT_MSG_CHANNEL")
        self:RegisterEvent("CHAT_MSG_SAY")
        self:RegisterEvent("CHAT_MSG_YELL")
        return
    end
    ns.Add(a1, a2, event == "CHAT_MSG_CHANNEL" and a9 or event, a12)
end)

SLASH_GULLIBULLETIN1 = "/gbul"
SLASH_GULLIBULLETIN2 = "/gullibulletin"
SlashCmdList.GULLIBULLETIN = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "clear" then
        wipe(ns.posts)
        if ns.Feed then ns.Feed() end
        print("|cff9ad0ffGulli Bulletin|r: " .. L.CLEARED)
        if ns.Refresh then ns.Refresh() end
    elseif msg == "help" then
        print("|cff9ad0ffGulli Bulletin|r: " .. L.HELP)
    else
        ns.Toggle()
    end
end

-- The hub's home line: groups for the shown dungeons and the trade posts on the board now.
function ns.HubSummary()
    if not ns.db then return nil end
    ns.Expire()
    local groups, trade = 0, 0
    for _, p in ipairs(ns.posts) do
        if p.kind == "GROUP" and p.role ~= "LFG" and ns.Shown(p.dungeon) then groups = groups + 1 end
        if p.kind == "WTS" or p.kind == "WTB" then trade = trade + 1 end
    end
    if groups + trade == 0 then return nil end
    return ns.L.HUB_SUMMARY:format(groups, trade)
end

function GulliBulletin_Toggle() ns.Toggle() end

if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({
        key = "Bulletin",
        icon = "Interface\\AddOns\\Gulli-Bulletin\\icon",
        slash = "/gbul",
        open = function() ns.Toggle() end,
        window = function() return ns.Window and ns.Window() end,
        summary = function() return ns.HubSummary() end,
    })
end
