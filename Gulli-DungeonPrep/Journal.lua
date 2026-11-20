-- The journal part: each dungeon's bosses and rares (from JournalData.lua, collected from
-- Wowhead's WoW Forever pages), their loot with drop chances, the wishlist with its alert, the
-- player's own kills and drops (which take over the chances after ns.OWN_AFTER kills and add
-- loot the table lacks), the notes, the warning on entering a dungeon with quests not taken,
-- and the guide that pins one stop of the quest route after another.

local ADDON, ns = ...
local L = ns.L

ns.OWN_AFTER = 10

local function data() return ns.Data or {} end

local function db(field)
    if not ns.db then return {} end
    ns.db[field] = ns.db[field] or {}
    return ns.db[field]
end

-- Game API wrappers.
local function itemInfo(id)
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not get then return nil end
    local name, link, quality, ilvl, _, _, _, _, equipLoc, icon = get(id)
    if not name and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
    return name, link, quality, ilvl, equipLoc, icon
end
local function itemInstant(id)
    local get = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not get then return nil end
    local _, _, _, equipLoc, icon, classID, subclassID = get(id)
    return classID, subclassID, equipLoc, icon
end
local function spellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return GetSpellInfo and (GetSpellInfo(id)) or nil
end
local function spellIcon(id)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
    return GetSpellTexture and GetSpellTexture(id) or nil
end
local function secret(v) return issecretvalue and issecretvalue(v) end

-- The npc id inside a creature GUID ("Creature-0-1-2-3-<npc>-<spawn>"), or nil.
function ns.NpcOf(guid)
    if type(guid) ~= "string" or secret(guid) then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    return tonumber(id)
end

-- Every boss and rare by npc id: { key (dungeon), row }.
local byNpc
local function npcIndex()
    if byNpc then return byNpc end
    byNpc = {}
    for key, list in pairs(data().boss or {}) do
        for _, b in ipairs(list) do byNpc[b[1]] = { key = key, row = b } end
    end
    return byNpc
end
function ns.BossDungeon(npc)
    local x = npcIndex()[npc]
    return x and x.key
end

-- The player's own numbers for one boss: kills, and drops by item.
function ns.Kills(npc) return db("kills")[npc] or 0 end
local function ownDrops(npc) return db("drops")[npc] or {} end

-- The chance of an item from a boss: the table's, or the player's own after ns.OWN_AFTER kills.
-- Returns the percent and whether it is the player's own.
function ns.Chance(npc, item, pct)
    local kills = ns.Kills(npc)
    if kills >= ns.OWN_AFTER then
        return math.floor((ownDrops(npc)[item] or 0) * 1000 / kills + 0.5) / 10, true
    end
    return pct, false
end

function ns.Wished(item) return db("wish")[item] == true end
function ns.SetWish(item, on)
    db("wish")[item] = on and true or nil
    if ns.Refresh then ns.Refresh() end
end
function ns.WishCount()
    local n = 0
    for _ in pairs(db("wish")) do n = n + 1 end
    return n
end

function ns.Note(key) return db("notes")[key] or "" end
function ns.SetNote(key, text)
    text = text and text:gsub("^%s+", ""):gsub("%s+$", "") or ""
    db("notes")[key] = text ~= "" and text:sub(1, 300) or nil
end

-- One loot line: { item, npc, boss, pct, own, quality, name, link, icon, fits, better,
-- wish, seen }. `seen` marks an item only the player's own loot showed.
local function lootLine(npc, bossName, item, quality, pct, seen)
    local chance, own = ns.Chance(npc, item, pct)
    local name, link, q, _, equipLoc, icon = itemInfo(item)
    local classID, subclassID, eloc, iconI = itemInstant(item)
    local line = { item = item, npc = npc, boss = bossName, pct = chance, own = own,
                   quality = q or quality, name = name, link = link, icon = icon or iconI,
                   wish = ns.Wished(item), seen = seen, equipLoc = equipLoc or eloc,
                   classID = classID, subclassID = subclassID }
    if ns.ItemFor then line.fits, line.better = ns.ItemFor(item) end
    return line
end

-- The Encounter Journal's round boss pictures of a classic dungeon (ns.ART), read once: creature
-- display id -> icon, and the creature's name -> icon for a boss the data gives another display.
local bossIcons = {}
function ns.BossIcons(key)
    if bossIcons[key] then return bossIcons[key] end
    local map, a = {}, ns.ART and ns.ART[key]
    if a and EJ_GetEncounterInfoByIndex and EJ_GetCreatureInfo then
        for i = 1, 40 do
            local ok, _, _, encounter = pcall(EJ_GetEncounterInfoByIndex, i, a[1])
            if not ok or not encounter then break end
            for j = 1, 8 do
                local fine, _, name, _, display, icon = pcall(EJ_GetCreatureInfo, j, encounter)
                if not fine or not name then break end
                if icon and icon ~= 0 and icon ~= "" then
                    if display and display ~= 0 then map[display] = map[display] or icon end
                    map[name] = map[name] or icon
                end
            end
        end
    end
    bossIcons[key] = map
    return map
end

-- A boss's picture: the journal's when it has one, else nil (the window then draws the
-- creature's portrait or its number).
function ns.BossIcon(key, b)
    local map = ns.BossIcons(key)
    return map[b.display] or map[b.name]
end

-- What the player's class can use first, then the better item, then the likelier one.
local function lootOrder(a, c)
    local fa, fc = a.fits ~= false, c.fits ~= false
    if fa ~= fc then return fa end
    if (a.quality or 0) ~= (c.quality or 0) then return (a.quality or 0) > (c.quality or 0) end
    if a.pct ~= c.pct then return a.pct > c.pct end
    return a.item < c.item
end

-- How many of a dungeon's bosses (not its rares) the player has killed: killed, all.
function ns.BossProgress(key)
    local killed, all = 0, 0
    for _, b in ipairs((data().boss or {})[key] or {}) do
        if b[7] ~= 1 then
            all = all + 1
            if ns.Kills(b[1]) > 0 then killed = killed + 1 end
        end
    end
    return killed, all
end

-- A dungeon's bosses in the order a group meets them (the data's), then its rares, with their
-- loot, the player's class first:
-- { npc, name, tag, min, max, display, rare, wing, n, of, spells = { {id, name, icon} }, kills, loot }.
function ns.Bosses(key)
    local out = {}
    for i, b in ipairs((data().boss or {})[key] or {}) do
        local x = { npc = b[1], name = b[2], tag = b[3] or "", min = b[4] or 0, max = b[5] or 0,
                    display = b[6] or 0, rare = b[7] == 1, n = i, wing = b[10] or "", spells = {}, loot = {} }
        x.kills = ns.Kills(x.npc)
        -- One line per name: the data has a spell's ranks under several ids.
        local named = {}
        for _, s in ipairs(b[8] or {}) do
            local name = spellName(s)
            if name and not named[name] then
                named[name] = true
                x.spells[#x.spells + 1] = { id = s, name = name, icon = spellIcon(s) }
            end
        end
        local known = {}
        for _, l in ipairs(b[9] or {}) do
            known[l[1]] = true
            local line = lootLine(x.npc, x.name, l[1], l[2], l[3], false)
            -- Quality 0: the data does not know it (an ATT item); a white one the game names stays out.
            if l[2] > 0 or not line.name or (line.quality or 0) >= 2 then x.loot[#x.loot + 1] = line end
        end
        for item in pairs(ownDrops(x.npc)) do
            if not known[item] then x.loot[#x.loot + 1] = lootLine(x.npc, x.name, item, 2, 0, true) end
        end
        table.sort(x.loot, lootOrder)
        out[#out + 1] = x
    end
    -- Bosses in the order of the data, rares after them.
    local bosses, rares = {}, {}
    for _, x in ipairs(out) do if x.rare then rares[#rares + 1] = x else bosses[#bosses + 1] = x end end
    for i, x in ipairs(bosses) do x.n, x.of = i, #bosses end
    for _, x in ipairs(rares) do bosses[#bosses + 1] = x end
    return bosses
end

-- What the ordinary mobs of a dungeon drop (D.zone), uncommon or better and no quest items;
-- an item the game does not know yet waits until it does. Lines like a boss's, with zone = true.
function ns.ZoneLoot(key)
    local out = {}
    for _, z in ipairs((data().zone or {})[key] or {}) do
        local l = lootLine(0, "", z[1], z[2], 0, false)
        l.zone = true
        if l.name and (l.quality or 0) >= 2 and l.classID ~= 12 then out[#out + 1] = l end
    end
    table.sort(out, lootOrder)
    return out
end

-- The loot of a dungeon in one list. Filter "mobs": what the ordinary mobs drop. "mine": what
-- the bosses drop for this class, boss by boss in their order. "wish": the wishlist, bosses then
-- mobs. "all": every boss drop, wished first, then the best chance. `text` finds a name or a boss.
function ns.Loot(key, filter, text)
    local out = {}
    text = text and text ~= "" and text:lower() or nil
    local function add(l, boss)
        local keep = true
        if filter == "mine" then keep = l.fits ~= false end
        if filter == "wish" then keep = l.wish end
        if keep and text then
            keep = ((l.name or ""):lower():find(text, 1, true) or boss:lower():find(text, 1, true)) ~= nil
        end
        if keep then out[#out + 1] = l end
    end
    if filter ~= "mobs" then
        for _, b in ipairs(ns.Bosses(key)) do
            for _, l in ipairs(b.loot) do
                l.bossN, l.rare = b.n, b.rare
                add(l, b.name)
            end
        end
    end
    if filter == "mobs" or filter == "wish" then
        for _, l in ipairs(ns.ZoneLoot(key)) do add(l, "") end
    end
    if filter == "all" then
        table.sort(out, function(a, c)
            if a.wish ~= c.wish then return a.wish end
            if a.pct ~= c.pct then return a.pct > c.pct end
            return a.item < c.item
        end)
    end
    return out
end

-- Where an item drops: { key, boss, pct } for every boss that has it (for the item tooltip).
function ns.DropsOf(item)
    local out = {}
    for npc, x in pairs(npcIndex()) do
        for _, l in ipairs(x.row[9] or {}) do
            if l[1] == item then
                out[#out + 1] = { key = x.key, boss = x.row[2], pct = (ns.Chance(npc, item, l[3])) }
            end
        end
    end
    table.sort(out, function(a, b) return a.pct > b.pct end)
    return out
end

-- The dungeon whose bosses or name match a search text, for the search box: the first match.
function ns.FindDungeon(text)
    if not text or text == "" then return nil end
    text = text:lower()
    for key, list in pairs(data().boss or {}) do
        for _, b in ipairs(list) do
            if b[2]:lower():find(text, 1, true) then return key, b[1] end
            for _, l in ipairs(b[9] or {}) do
                local name = itemInfo(l[1])
                if name and name:lower():find(text, 1, true) then return key, b[1], l[1] end
            end
        end
    end
end

-- Loot from a corpse: counts the kill of a known boss once per corpse, keeps what dropped, and
-- tells about a wished item. Called on LOOT_READY.
local looted = {}
function ns.OnLoot()
    if not (GetNumLootItems and GetLootSlotLink) then return end
    local counted = {}
    for slot = 1, GetNumLootItems() do
        local link = GetLootSlotLink(slot)
        local item = type(link) == "string" and not secret(link) and tonumber(link:match("item:(%d+)"))
        local quality
        if GetLootSlotInfo then quality = select(5, GetLootSlotInfo(slot)) end
        local sources = GetLootSourceInfo and { GetLootSourceInfo(slot) } or {}
        for i = 1, #sources, 2 do
            local guid = sources[i]
            local npc = ns.NpcOf(guid)
            if npc and npcIndex()[npc] and ns.Get("learn") then
                if not looted[guid] then
                    looted[guid] = true
                    counted[guid] = true
                    db("kills")[npc] = ns.Kills(npc) + 1
                end
                if item and counted[guid] and (quality or 0) >= 2 then
                    local d = db("drops")
                    d[npc] = d[npc] or {}
                    d[npc][item] = (d[npc][item] or 0) + 1
                end
            end
        end
        if item and ns.Wished(item) and ns.Get("wishAlert") then ns.WishDropped(item, link) end
    end
end

function ns.WishDropped(item, link)
    local name = itemInfo(item) or link or ("item:" .. item)
    print("|cff9ad0ffGulli-DungeonPrep|r: " .. L.WISH_DROPPED:format(link or name))
    if PlaySound then pcall(PlaySound, 8959) end
    if GulliToolkit and GulliToolkit.Notify then GulliToolkit.Notify("DungeonPrep", L.WISH_DROPPED:format(name)) end
    if ns.Skin and ns.Skin.Toast then
        local _, _, _, _, _, icon = itemInfo(item)
        ns.Skin.Toast({ key = "wish" .. item, icon = icon, title = L.WISH_TITLE, text = link or name, kind = "ok", seconds = 12 })
    end
end

-- The dungeon the player is in (by the instance's name), or nil.
function ns.CurrentDungeon()
    if not (IsInInstance and GetInstanceInfo) then return nil end
    local inside, kind = IsInInstance()
    if not inside or (kind ~= "party" and kind ~= "raid") then return nil end
    local name = GetInstanceInfo()
    if type(name) ~= "string" or name == "" then return nil end
    for _, d in ipairs(ns.Dungeons(UnitLevel("player") or 1)) do
        if ns.DungeonName(d) == name or d.en == name then return d end
    end
end

-- Entering a dungeon whose quests wait to be taken: one line in chat and a notice, once per entry.
local warnedFor
function ns.CheckEnter()
    local d = ns.CurrentDungeon()
    if not d then warnedFor = nil return end
    if warnedFor == d.key then return end
    warnedFor = d.key
    ns.selected, ns.openQuest, ns.home = d.key, nil, false
    if not ns.Get("warnEnter") then return end
    local q = ns.Quests(d.key, UnitLevel("player") or 1)
    local outside = 0
    for _, x in ipairs(q.take) do if x.area and x.area > 0 then outside = outside + 1 end end
    if outside == 0 then return end
    local text = L.ENTER_WARN:format(outside, ns.DungeonName(d))
    print("|cff9ad0ffGulli-DungeonPrep|r: " .. text)
    if ns.Skin and ns.Skin.Toast then
        ns.Skin.Toast({ key = "enter", icon = ns.Icon(d.key), title = ns.DungeonName(d), text = text, kind = "warn",
                        seconds = 10 })
    end
end

-- The guide: pins the first stop of the dungeon's quest route and, as quests are taken, the
-- next one; with nothing left to take, who takes back a finished quest, one after another as
-- they are handed in; then the entrance. ns.guide = { key, last }.
function ns.StartGuide(key)
    -- One guide leads at a time, whatever module it is of (GulliHUD.guide = { owner, stop }).
    GulliHUD = GulliHUD or {}
    local other = GulliHUD.guide
    if other and other.owner ~= "DungeonPrep" and other.stop then pcall(other.stop) end
    GulliHUD.guide = { owner = "DungeonPrep", stop = function() ns.StopGuide() end }
    ns.guide = { key = key }
    if ns.ShowTracker then ns.ShowTracker(key) end
    return ns.StepGuide()
end

function ns.StopGuide()
    ns.guide = nil
    if GulliHUD and GulliHUD.guide and GulliHUD.guide.owner == "DungeonPrep" then GulliHUD.guide = nil end
    if ns.Refresh then ns.Refresh() end
end

function ns.StepGuide()
    local g = ns.guide
    if not g then return false end
    local d
    for _, x in ipairs(ns.Dungeons(UnitLevel("player") or 1)) do if x.key == g.key then d = x end end
    if not d then ns.guide = nil return false end
    local q = ns.Quests(g.key, UnitLevel("player") or 1)
    local route = ns.Route(q.take, ns.Here(), d)
    local stop
    for _, s in ipairs(route) do
        if not s.inside then stop = s break end
    end
    if not stop then ns.guide = nil return false end
    if stop.entrance then
        for _, it in ipairs(ns.TrackerItems(g.key, UnitLevel("player") or 1)) do
            local p = it.pin
            if it.state == "ready" and p then
                stop = { who = p.who, area = p.area, x = p.x, y = p.y, turnin = true }
                break
            end
        end
    end
    local id = (stop.who or "") .. "@" .. (stop.area or 0)
    if id ~= g.last then
        g.last = id
        g.stop = stop
        if stop.turnin then ns.PinAt(stop.who, stop.area, stop.x, stop.y) else ns.SetPin(stop) end
    end
    -- At the entrance the guide is done.
    if stop.entrance then ns.guide = nil end
    if ns.Refresh then ns.Refresh() end
    return true
end
