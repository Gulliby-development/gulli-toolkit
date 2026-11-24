-- Reads the game for Core.lua: the profession window (recipes, reagents, colours), bags and
-- bank, vendor sell prices, Auctionator prices, and the prices seen at vendors and trainers.
-- Every game call goes through a small wrapper with a fallback to the old global API.

local ADDON, ns = ...

local CALLER = "Gulli-CraftProfit"
local OBS_MAX = 8 -- colours kept per recipe, newest skills first

-- Trade supplies every trade vendor sells without a limit (Data.vend). Their price is known
-- before the player ever saw one at a vendor: a vendor asks four times what it pays, less the
-- reputation discount (an estimate until seen).
ns.VENDOR_ITEMS = (ns.Data and ns.Data.vend) or {}
-- The capital factions: a trade vendor in a city gives the discount of the standing with it.
local CITY = { Horde = { 76, 68, 81, 530 }, Alliance = { 72, 47, 69, 54 } }
local function standingById(id)
    local R = C_Reputation
    if R and R.GetFactionDataByID then
        local ok, d = pcall(R.GetFactionDataByID, id)
        return ok and type(d) == "table" and d.reaction or nil
    elseif GetFactionInfoByID then
        local _, _, s = GetFactionInfoByID(id)
        return s
    end
end
-- The share a vendor of the player's best capital takes off: 5% per standing above Neutral.
function ns.VendorDiscount()
    local best = 4
    for _, id in ipairs(CITY[UnitFactionGroup and UnitFactionGroup("player") or ""] or {}) do
        local s = standingById(id)
        if type(s) == "number" and not (issecretvalue and issecretvalue(s)) and s > best then best = s end
    end
    return math.min(best - 4, 4) * 0.05
end

-- ---------- wrappers ----------

local function itemName(id)
    local n = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    if not n and GetItemInfo then n = GetItemInfo(id) end
    return n
end
-- An item whose name the client had not loaded when a state was built shows as "#<id>". It is
-- asked for, and once the game has it every "#<id>" of the result is renamed and the window drawn again.
ns.nameWaiting, ns.nameFound = {}, {}
ns.repWaiting = {} -- patterns not loaded yet: their reputation line could not be read
local function nameFor(id)
    local n = ns.nameFound[id] or itemName(id)
    if type(n) == "string" and n ~= "" then ns.nameFound[id] = n; return n end
    ns.nameWaiting[id] = true
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    return "#" .. id
end
ns.NameFor = nameFor
-- Renames every `name = "#<id>"` under `root` whose item is known by now.
function ns.FixNames(root)
    local seen = {}
    local function walk(t)
        if seen[t] then return end
        seen[t] = true
        local n = rawget(t, "name")
        if type(n) == "string" then
            local id = tonumber(n:match("^#(%d+)$"))
            if id and ns.nameFound[id] then rawset(t, "name", ns.nameFound[id]) end
        end
        for _, v in pairs(t) do if type(v) == "table" then walk(v) end end
    end
    if type(root) == "table" then walk(root) end
end
-- Looks again for the names still missing; one redraw for a burst of them.
local nameRedraw
function ns.CheckNames()
    local got
    for id in pairs(ns.nameWaiting) do
        local n = itemName(id)
        if type(n) == "string" and n ~= "" then ns.nameFound[id] = n; ns.nameWaiting[id] = nil; got = true
            -- the pattern's tooltip can be read now: the plan may have counted on a pattern it cannot learn
            -- (the same for a vendor supply: its price was not known either)
            if ns.repWaiting[id] or ns.VENDOR_ITEMS[id] then ns.repWaiting[id] = nil; if ns.view then ns.view.stale = true end end
        end
    end
    if not got or nameRedraw then return end
    nameRedraw = true
    local function redraw()
        nameRedraw = nil
        ns.FixNames(ns.view)
        if ns.Busy and ns.Busy() then ns.nameLate = true end -- a result still being built has the old names
        if ns.Refresh then ns.Refresh() end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.2, redraw) else redraw() end
end
function ns.ItemIcon(id)
    return (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or (GetItemIcon and GetItemIcon(id))
        or "Interface\\Icons\\INV_Misc_QuestionMark"
end
-- vendor sell price, bind type, quality
local function itemInfo(id)
    local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not f then return 0, 0, 1 end
    local _, _, quality, _, _, _, _, _, _, _, sell, _, _, bind = f(id)
    return sell or 0, bind or 0, quality or 1
end
local function count(id, bank)
    local f = (C_Item and C_Item.GetItemCount) or GetItemCount
    return f and (f(id, bank) or 0) or 0
end
local function idFromLink(link)
    return link and tonumber(link:match("item:(%d+)"))
end

-- Auctionator's API, or nil without Auctionator.
local function auctionator()
    return Auctionator and Auctionator.API and Auctionator.API.v1
end
-- Auction prices come from every price addon through the shared reader (S.AuctionPrice in Skin.lua).
function ns.AuctionPrice(id) return ns.Skin.AuctionPrice(id, ns.FRESH_DAYS) end
function ns.PriceAddons() return ns.Skin.PriceAddons() end
function ns.HasPrices() return ns.Skin.HasPrices() end
function ns.HasAuctionator() return auctionator() ~= nil end

-- ---------- the profession window ----------

local DIFF = { optimal = 0, medium = 1, easy = 2, trivial = 3 }

local function charDB() return ns.char end

-- Skill and cap of a profession from the spellbook, which knows them even when the profession
-- window reports 0 (the base line of a profession with expansion lines).
local function spellbookSkill(name)
    if not name or not GetProfessions or not GetProfessionInfo then return nil end
    local list = { GetProfessions() } -- may hold gaps (no second profession, no fishing)
    for k = 1, 6 do
        local i = list[k]
        if i then
            local n, _, skill, cap = GetProfessionInfo(i)
            if n == name then return skill, cap end
        end
    end
end

local function windowLine()
    local T = C_TradeSkillUI
    if T and T.GetChildProfessionInfo then
        local i = T.GetChildProfessionInfo()
        if i and i.professionName and (i.skillLevel or 0) > 0 then return i.professionName, i.skillLevel, i.maxSkillLevel end
    end
    if T and T.GetBaseProfessionInfo then
        local i = T.GetBaseProfessionInfo()
        if i and i.professionName then return i.professionName, i.skillLevel or 0, i.maxSkillLevel or 0 end
    end
    if T and T.GetTradeSkillLine then
        local _, name, rank, max = T.GetTradeSkillLine()
        if name then return name, rank or 0, max or 0 end
    end
    if GetTradeSkillLine then
        local name, rank, max = GetTradeSkillLine()
        if name and name ~= "UNKNOWN" then return name, rank or 0, max or 0 end
    end
end

-- Name, skill and cap of the open profession; nil while the game has no skill for it, so a
-- half-loaded window never saves a profession at 0/0.
local function professionLine()
    local name, skill, cap = windowLine()
    if not name then return nil end
    if (skill or 0) <= 0 or (cap or 0) <= 0 then
        local s2, c2 = spellbookSkill(name)
        if (skill or 0) <= 0 then skill = s2 or 0 end
        if (cap or 0) <= 0 then cap = c2 or 0 end
    end
    if skill <= 0 and cap <= 0 then return nil end
    return name, skill, cap
end

-- Whether this character has the profession, by the spellbook; nil when the spellbook lists none.
-- A profession saved from another player's window (a trade link) is not the character's.
local function owned(name)
    if not GetProfessions or not GetProfessionInfo then return nil end
    local list, any = { GetProfessions() }, false
    for k = 1, 6 do
        local i = list[k]
        if i then
            any = true
            if GetProfessionInfo(i) == name then return true end
        end
    end
    if any then return false end
end
ns.OwnsProfession = owned

-- The window shows another player's profession (a trade link, the guild) or an NPC's.
local function foreign()
    local T = C_TradeSkillUI
    if not T then return false end
    for _, f in ipairs({ "IsTradeSkillLinked", "IsTradeSkillGuild", "IsTradeSkillGuildMember", "IsNPCCrafting" }) do
        if T[f] then
            local ok, v = pcall(T[f])
            if ok and v then return true end
        end
    end
    return false
end

-- A saved profession the game gave no skill for (saved by version 1.1.0 and older).
local function empty(p) return (p.skill or 0) <= 0 and (p.cap or 0) <= 0 end

-- The profession's own icon from the spellbook, for the craft stops.
local function professionIcon(name)
    if not GetProfessions or not GetProfessionInfo then return nil end
    local list = { GetProfessions() } -- may hold gaps (no second profession, no fishing)
    for k = 1, 6 do
        local i = list[k]
        if i then
            local n, icon = GetProfessionInfo(i)
            if n == name then return icon end
        end
    end
end

local function remember(rec, skill, diff)
    if diff == nil then return end
    rec.obs = rec.obs or {}
    rec.obs[skill] = diff
    -- keep the newest few skills
    local ks = {}
    for s in pairs(rec.obs) do ks[#ks + 1] = s end
    if #ks > OBS_MAX then
        table.sort(ks)
        for i = 1, #ks - OBS_MAX do rec.obs[ks[i]] = nil end
    end
end

-- Whether a recipe is of the profession `name`: false only when the game names another one.
-- Right after a switch in the window the game can still list the other profession's recipes.
local function belongs(rid, name)
    local T = C_TradeSkillUI
    if type(rid) ~= "number" or not (T and T.GetProfessionInfoByRecipeID) then return true end
    local ok, i = pcall(T.GetProfessionInfoByRecipeID, rid)
    if not ok or type(i) ~= "table" then return true end
    local a, b = i.professionName, i.parentProfessionName
    if (a == nil or a == "") and (b == nil or b == "") then return true end
    return a == name or b == name
end
ns.RecipeBelongs = belongs

-- A cooldown the game shows (seconds left): when the craft is ready again, and for a recipe
-- ns.COOLDOWNS does not know, that it has one at all (at least as long as what is left, in hours).
local function noteCooldown(rec, left)
    left = tonumber(left)
    if not left or left <= 0 then rec.cdReady = nil; return end
    rec.cdReady = time() + math.ceil(left)
    rec.cd = math.max(rec.cd or 0, math.ceil(left / 3600) * 3600)
end
ns.NoteCooldown = noteCooldown

-- The modern API: every recipe of the profession, learned or not.
local function scanModern(prof, skill, name)
    local T = C_TradeSkillUI
    local ids = T.GetAllRecipeIDs() or {}
    local mine = {}
    for _, rid in ipairs(ids) do if belongs(rid, name) then mine[#mine + 1] = rid end end
    -- a list with none of this profession is the one shown before: wait for the next update
    if #ids > 0 and #mine == 0 then return 0 end
    for rid in pairs(prof.recipes) do
        if not belongs(rid, name) then prof.recipes[rid] = nil end
    end
    local n = 0
    for _, rid in ipairs(mine) do
        local info = T.GetRecipeInfo(rid)
        if info and not info.isDummyRecipe and not info.isGatheringRecipe then
            local rec = prof.recipes[rid] or {}
            rec.name = info.name
            rec.learned = info.learned and true or false
            rec.icon = info.icon
            if info.learned then remember(rec, skill, info.relativeDifficulty) end
            if info.maxTrivialLevel and info.maxTrivialLevel > 0 then rec.grey = info.maxTrivialLevel end
            local sch = T.GetRecipeSchematic and T.GetRecipeSchematic(rid, false)
            if sch then
                rec.out = sch.outputItemID
                rec.count = math.max(1, sch.quantityMin or 1)
                rec.r = {}
                for _, slot in ipairs(sch.reagentSlotSchematics or {}) do
                    local first = slot.reagents and slot.reagents[1]
                    if first and first.itemID and (slot.reagentType == nil or slot.reagentType == 1) then
                        rec.r[first.itemID] = slot.quantityRequired or 1
                    end
                end
            end
            if not rec.learned and T.GetRecipeSourceText then rec.source = T.GetRecipeSourceText(rid) end
            if rec.learned and T.GetRecipeCooldown then
                local ok, left = pcall(T.GetRecipeCooldown, rid)
                noteCooldown(rec, ok and left)
            end
            prof.recipes[rid] = rec
            n = n + 1
        end
    end
    return n
end

-- The classic API: the recipes the character knows, listed by index.
local function scanClassic(prof, skill)
    local n = 0
    for i = 1, GetNumTradeSkills() do
        local name, kind = GetTradeSkillInfo(i)
        local diff = DIFF[kind or ""]
        if name and diff then
            local out = idFromLink(GetTradeSkillItemLink and GetTradeSkillItemLink(i))
            local key = out or name
            local rec = prof.recipes[key] or {}
            rec.name, rec.learned, rec.out = name, true, out
            rec.count = math.max(1, (GetTradeSkillNumMade and GetTradeSkillNumMade(i)) or 1)
            rec.r = {}
            for j = 1, GetTradeSkillNumReagents(i) do
                local _, _, need = GetTradeSkillReagentInfo(i, j)
                local id = idFromLink(GetTradeSkillReagentItemLink(i, j))
                if id then rec.r[id] = need or 1 end
            end
            remember(rec, skill, diff)
            if GetTradeSkillCooldown then noteCooldown(rec, GetTradeSkillCooldown(i)) end
            prof.recipes[key] = rec
            n = n + 1
        end
    end
    return n
end

-- Saves the open profession for this character. Returns its name and the recipe count.
function ns.ScanProfession()
    if foreign() then return nil, 0 end
    local name, skill, cap = professionLine()
    if not name or owned(name) == false then return nil, 0 end
    local db = charDB()
    db.profs[name] = db.profs[name] or { recipes = {} }
    local prof = db.profs[name]
    prof.skill, prof.cap, prof.seen = skill, cap, time()
    prof.icon = professionIcon(name) or prof.icon
    local n
    if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs then n = scanModern(prof, skill, name)
    elseif GetNumTradeSkills then n = scanClassic(prof, skill)
    else n = 0 end
    db.current = db.current or name
    return name, n
end

-- ---------- the state for Core.lua ----------

function ns.Professions()
    local out = {}
    for name, p in pairs(charDB().profs) do if not empty(p) and owned(name) ~= false then out[#out + 1] = { name = name, skill = p.skill or 0, cap = p.cap or 0, icon = p.icon } end end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

function ns.SetProfession(name)
    if not charDB().profs[name] or owned(name) == false then return end
    local from = charDB().current
    charDB().current = name
    ns.SwitchView(from, name)
    ns.Rebuild(false, "pick")
end

local function itemFor(state, id)
    if state.items[id] then return end
    local sell, bind, quality = itemInfo(id)
    local ah, age = ns.AuctionPrice(id)
    local bags = count(id)
    local bank = math.max(0, count(id, true) - bags)
    local alts, who = ns.AltCount(id)
    local mail, gather = ns.char.mail and ns.char.mail[id] or 0, ns.Gathered()[id] == true
    -- the simulation with empty bags: a new character owns nothing and gathers nothing
    if ns.sim and ns.sim.empty then bags, bank, alts, who, mail, gather = 0, 0, 0, nil, 0, false end
    local buy = ns.db.vendor[id] or (ns.VENDOR_ITEMS[id] and sell > 0 and math.floor(sell * 4 * (1 - ns.VendorDiscount()) + 0.5)) or nil
    state.items[id] = { name = nameFor(id), vend = sell, bop = bind == 1, quality = quality,
                        ah = ah, age = age, buy = buy, buyEst = not ns.db.vendor[id] and buy ~= nil or nil, bags = bags, bank = bank,
                        mail = mail, alts = alts, altWho = who,
                        gather = gather, lots = ns.db.lots[id] }
end

-- ---------- the mailbox, the other characters, gathering ----------

-- What the mailbox holds: attachments of letters without cash on delivery. Read at the mailbox.
local function snapshotMail()
    if not GetInboxNumItems then return end
    local out = {}
    for i = 1, GetInboxNumItems() do
        local _, _, _, _, _, cod = GetInboxHeaderInfo(i)
        if (cod or 0) == 0 then
            for a = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
                local _, id, _, n = GetInboxItem(i, a)
                if id then out[id] = (out[id] or 0) + (n or 1) end
            end
        end
    end
    ns.char.mail = out
end
ns.SnapshotMail = snapshotMail

-- Units of an item on this account's other characters, from Gulli Chores (read only), and the
-- character with the most.
function ns.AltCount(id)
    local db = GulliChoresDB
    if type(db) ~= "table" or type(db.chars) ~= "table" then return 0, nil end
    -- this character: an empty realm name from the game means the realm Chores saved last
    local name = UnitName("player") or ""
    local realm = GetRealmName and GetRealmName() or ""
    if realm == "" then realm = type(db.realm) == "string" and db.realm or "" end
    local me, bare = name .. "-" .. realm, name .. "-"
    local n, who, most = 0, nil, 0
    for key, c in pairs(db.chars) do
        if key ~= me and key ~= bare and type(c) == "table" then
            local k = (c.items and c.items[id] or 0) + (c.bank and c.bank[id] or 0)
            n = n + k
            if k > most then who, most = c.name or key, k end
        end
    end
    return n, who
end

-- Marks an item the player gathers (herbs, ore, skins): the plan never buys it.
-- In the simulation the marks are the simulation's own copy and go with it.
function ns.Gathered() return ns.sim and ns.sim.gather or ns.db.gather end
function ns.SetGather(id, on)
    if not id then return end
    ns.Gathered()[id] = on and true or nil
    ns.Rebuild(true)
end

-- Takes a craft out of every route (learned, from a trainer or from a pattern alike), or puts it
-- back. Saved by recipe for every character.
function ns.SkipSet()
    if ns.sim then return ns.sim.skip end
    ns.db.skip = ns.db.skip or {}
    return ns.db.skip
end
function ns.SetSkip(rid, on)
    if not rid then return end
    ns.SkipSet()[rid] = on and true or nil
    ns.Rebuild(true)
end

-- The skill levels Data.lua has for a recipe. The modern API keys recipes by spell, the classic
-- one by the item made (then the key is the item and must not be read as a spell).
local function levels(rid, rec)
    local D = ns.Data or {}
    local byItem = rec.out and D.item and D.item[rec.out]
    local bySpell = rid ~= rec.out and D.spell and D.spell[rid]
    if bySpell then
        if byItem then return { byItem[1], bySpell[1], bySpell[2], bySpell[3] } end
        return bySpell
    end
    return byItem
end

-- Recipes the ordinary trainers do not teach: one trainer per faction does (the Shadoweave
-- tailors), named with the city's area id so the city shows in the client's language.
local SHADOWEAVE = { Horde = { "Josephine Lister", 1497 }, Alliance = { "Jalane Ayrole", 1519 } }
ns.TRAINERS = {}
for _, rid in ipairs({ 12052, 12055, 12071, 12076, 12082 }) do ns.TRAINERS[rid] = SHADOWEAVE end

-- TEMPORARY (2026-11-19): WoW Forever's Shadoweave trainers teach these only from skill 200,
-- not 175, which looks like a game bug. The learn level is raised to at least this; the
-- colours stay as the data says. Remove this table once the game teaches them at 175 again.
ns.LEARN_MIN = {}
for rid in pairs(ns.TRAINERS) do ns.LEARN_MIN[rid] = 200 end
local function trainerWho(rid)
    local t = ns.TRAINERS[rid]
    t = t and t[UnitFactionGroup and UnitFactionGroup("player") or ""]
    if not t then return nil end
    local city = C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(t[2])
    return { (type(city) == "string" and city ~= "") and (t[1] .. ", " .. city) or t[1] }, { t[1] }
end

-- ---------- profession specializations ----------

-- Recipes only one specialization of a profession can learn (owner's decision of 2026-11-19:
-- offered only when the character chose that specialization; with none, or another, never).
-- Key: the specialization's own spell (what the game gives when it is chosen). The Weaponsmith's
-- masters need the Weaponsmith too, which their spell implies. Tailoring has none in WoW Forever.
ns.SPECS = {
    [20219] = { 12899, 12895, 12897, 12902, 12903, 12905, 12906, 12907, 12759, 23489, 23129, 1266937 }, -- Gnomish Engineer
    [20222] = { 12718, 12717, 12716, 12715, 12760, 8895, 12755, 12754, 12908, 12758, 23486 }, -- Goblin Engineer
    [10656] = { 10619, 10650, 19060, 20855, 22926 }, -- Dragonscale Leatherworking
    [10658] = { 10630, 10632, 19078 }, -- Elemental Leatherworking
    [10660] = { 10621, 10647, 19073, 19080, 19086, 19104, 23709 }, -- Tribal Leatherworking
    [9788] = { 23637, 23636, 20876, 24399, 20873, 20872, 20874, 16745, 16742, 16744, 16741, 27829, 16724, 16729,
               16660, 16655, 16667, 15296, 9974, 9954 }, -- Armorsmith
    [9787] = { 23638, 23639, 16995, 15294, 10007, 15292, 10015, 10003 }, -- Weaponsmith
    [17041] = { 23653, 16991, 16994, 20897, 16970 }, -- Master Axesmith
    [17039] = { 16990, 23652, 20890, 27832, 16985, 16978 }, -- Master Swordsmith
    [17040] = { 23650, 16988, 16993, 27830, 16983, 16973 }, -- Master Hammersmith
}
ns.SPEC_OF = {}
for spec, list in pairs(ns.SPECS) do for _, rid in ipairs(list) do ns.SPEC_OF[rid] = spec end end

local function knowsSpell(id)
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        local ok, yes = pcall(C_SpellBook.IsSpellKnown, id)
        if ok and yes then return true end
    end
    if IsPlayerSpell then
        local ok, yes = pcall(IsPlayerSpell, id)
        if ok and yes then return true end
    end
    return false
end

-- Whether this character has the specialization: the game knows its spell, or the character
-- already knows one of its recipes (a client that names the spell otherwise still shows that).
function ns.HasSpec(spec)
    if knowsSpell(spec) then return true end
    for _, prof in pairs(ns.char and ns.char.profs or {}) do
        for _, rid in ipairs(ns.SPECS[spec] or {}) do
            local rec = prof.recipes and prof.recipes[rid]
            if rec and rec.learned then return true end
        end
    end
    return false
end

-- The specialization's name in the client's language.
function ns.SpecName(spec)
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spec)
    if type(name) ~= "string" or name == "" then name = GetSpellInfo and GetSpellInfo(spec) end
    return type(name) == "string" and name ~= "" and name or nil
end

-- ---------- where an NPC stands ----------

-- Data.npc has the place of every vendor and trainer the data names (area id, x, y in map
-- percent). The area's name comes from the game, so it shows in the client's language.
local MAP = C_Map or {}
local KALIMDOR, EASTERN = 1414, 1415
function ns.NpcSpot(name)
    local d = name and ns.Data and ns.Data.npc and ns.Data.npc[name]
    if not d then return nil end
    local zone = MAP.GetAreaInfo and MAP.GetAreaInfo(d[1])
    if type(zone) ~= "string" or zone == "" then zone = nil end
    return { who = name, area = d[1], zone = zone, x = d[2], y = d[3], label = zone and (name .. ", " .. zone) or name }
end

-- The one of `names` to go to: the one in the player's zone, else the first with a known place,
-- else only the first name. Returns { who, label, [area, zone, x, y] }.
function ns.PickNpc(names)
    if type(names) ~= "table" or not names[1] then return nil end
    local id = MAP.GetBestMapForUnit and MAP.GetBestMapForUnit("player")
    local info = id and MAP.GetMapInfo and MAP.GetMapInfo(id)
    local here = info and info.name
    local first
    for _, name in ipairs(names) do
        local s = ns.NpcSpot(name)
        if s and s.zone then
            if here and s.zone == here then return s end
            first = first or s
        end
    end
    return first or { who = names[1], label = names[1] }
end

-- A map pin on a spot of ns.PickNpc, through the world map's own waypoint (and TomTom's arrow
-- when it is installed). With `open` the world map opens there too. Returns true when it is set.
local mapOfZone
function ns.SetPin(spot, open)
    if not (spot and spot.zone and spot.x and MAP.SetUserWaypoint and UiMapPoint and MAP.GetMapChildrenInfo) then return false end
    if not mapOfZone then
        mapOfZone = {}
        for _, c in ipairs({ KALIMDOR, EASTERN }) do
            for _, m in ipairs(MAP.GetMapChildrenInfo(c, nil, true) or {}) do
                if m.name and not mapOfZone[m.name] then mapOfZone[m.name] = m.mapID end
            end
        end
    end
    local id = mapOfZone[spot.zone]
    if not id then return false end
    MAP.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(id, spot.x / 100, spot.y / 100))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    if TomTom and TomTom.AddWaypoint then
        TomTom:AddWaypoint(id, spot.x / 100, spot.y / 100, { title = spot.who, from = CALLER })
    end
    if open then ns.OpenMap(id) end
    return true
end

-- Opens the world map on a map id, out of combat only. C_Map.OpenWorldMap lets the game open it
-- from its own event, so the map's pins are made in secure code: an addon's call of
-- OpenWorldMap or SetMapID taints them and the game blocks SetPassThroughButtons.
function ns.OpenMap(id)
    if not id or (InCombatLockdown and InCombatLockdown()) then return false end
    if C_Map and C_Map.OpenWorldMap then
        C_Map.OpenWorldMap(id)
    elseif OpenWorldMap then
        OpenWorldMap(id)
    elseif WorldMapFrame and WorldMapFrame.SetMapID and ShowUIPanel then
        ShowUIPanel(WorldMapFrame)
        WorldMapFrame:SetMapID(id)
    else
        return false
    end
    if ns.BehindMap then ns.BehindMap() end
    return true
end

-- ---------- reputation ----------

-- "Requires %s - %s" of the client's language as a Lua pattern that catches the faction and the standing.
local function repPattern()
    local f = (ITEM_REQ_REPUTATION or "Requires %s - %s"):gsub("%%%d?%$?s", "\1")
    f = f:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("\1", "(.+)")
    return "^" .. f .. "$"
end

local function standingId(label)
    for i = 1, 8 do
        if label == _G["FACTION_STANDING_LABEL" .. i] or label == _G["FACTION_STANDING_LABEL" .. i .. "_FEMALE"] then return i end
    end
end

-- The reputation list as the game gives it now, merged into what this character saw before
-- (GulliCraftProfitCharDB.rep: faction name -> 1 Hated .. 8 Exalted). Before the reputation
-- window was opened the game may give a short list or none, so a pattern's line alone is no
-- proof; a faction read once stays known. `repFull` is set when no group of the list was folded,
-- so a faction missing from it then was never met. Returns whether anything changed.
function ns.ReadRep()
    local c = ns.char
    if not c then return false end
    c.rep = c.rep or {}
    local rep, changed, seen, folded = c.rep, false, 0, false
    local function note(name, reaction, header, collapsed, hasRep)
        if header and collapsed then folded = true end
        if type(name) ~= "string" or name == "" or type(reaction) ~= "number" or reaction < 1 then return end
        if header and not hasRep then return end
        seen = seen + 1
        if rep[name] ~= reaction then rep[name], changed = reaction, true end
    end
    local R = C_Reputation
    if R and R.GetNumFactions and R.GetFactionDataByIndex then
        local ok, num = pcall(R.GetNumFactions)
        for i = 1, ok and tonumber(num) or 0 do
            local okd, d = pcall(R.GetFactionDataByIndex, i)
            if okd and type(d) == "table" then note(d.name, d.reaction, d.isHeader, d.isCollapsed, d.isHeaderWithRep) end
        end
    elseif GetNumFactions and GetFactionInfo then
        for i = 1, GetNumFactions() or 0 do
            local n, _, s, _, _, _, _, _, header, collapsed, hasRep = GetFactionInfo(i)
            note(n, s, header, collapsed, hasRep)
        end
    end
    if seen > 0 and not folded and not c.repFull then c.repFull, changed = true, true end
    return changed
end

-- The character's standing with a faction by name: a number, false when the whole list was read
-- and the faction is not in it (never met), nil when Craft Profit cannot tell yet.
local function standingOf(name)
    local rep = ns.char and ns.char.rep
    if rep and rep[name] then return rep[name] end
    if ns.char and ns.char.repFull then return false end
    return nil
end

-- Factions of patterns left out because their standing is not known yet (filled by ns.State).
ns.repUnknown = {}

-- Whether a pattern asks for a reputation the character does not have, and the tooltip line that
-- says so. The game paints that line red when it is not met, but before the reputation window was
-- opened it may leave it white, so the saved standing decides; a faction whose standing is not
-- known yet counts as not met (and goes into ns.repUnknown for the banner). An item the client
-- has not loaded yet counts as no requirement until its name loads (ns.repWaiting marks the plan).
function ns.RepMissing(item)
    local T = C_TooltipInfo
    if not item or not T or not T.GetItemByID then return false end
    local ok, data = pcall(T.GetItemByID, item)
    if not ok or type(data) ~= "table" or not data.lines then
        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, item) end
        return false
    end
    local pat = repPattern()
    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if type(text) == "string" and not (issecretvalue and issecretvalue(text)) then
            local fac, label = text:match(pat)
            if fac then
                -- the simulated character is new: it has no reputation at all
                if ns.sim then return true, text end
                local err = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.ErrorLine
                if err and line.type == err then return true, text end
                local c = line.leftColor
                local red = type(c) == "table" and type(c.r) == "number" and c.r > 0.9 and c.g < 0.3 and c.b < 0.3
                if red then return true, text end
                local need = standingId(label)
                if not need then return false, text end
                local have = standingOf(fac)
                if have == nil then
                    ns.repUnknown[fac] = true
                    return true, text
                end
                return (have or 0) < need, text
            end
        end
    end
    return false
end

-- The factions whose standing the window waits for: left out of the last plan and still not read.
function ns.RepUnknown()
    local out = {}
    for fac in pairs(ns.repUnknown) do
        if standingOf(fac) == nil then out[#out + 1] = fac end
    end
    table.sort(out)
    return out
end

-- Where a recipe not learned yet comes from, and its price. Data.lua names the pattern and its
-- vendors; a pattern sells to a vendor for a quarter of what the vendor asks, so the price is
-- four times its sell price until the vendor was seen. A pattern on the auction costs its
-- Auctionator price. A recipe with no pattern comes from the trainer, whose price is known
-- once a trainer window was open, else from Wowhead (Data.train), and guessed from the skill
-- until then.
local function recipeSource(state, rid, rec, skill)
    -- a recipe the trainer teaches is learned there, even when a vendor also sells its pattern
    local cost = rec.name and ns.db.trainer[rec.name]
    local who, npc
    if rid ~= rec.out then who, npc = trainerWho(rid) end
    if cost then return { t = "trainer", cost = cost, est = false, who = who, npc = npc } end
    local train = ns.Data and ns.Data.train and rid ~= rec.out and ns.Data.train[rid]
    if train then return { t = "trainer", cost = train, est = false, who = who, npc = npc } end
    local D = ns.Data and ns.Data.src
    local d = D and rid ~= rec.out and D[rid]
    if d then
        local item = d[2]
        itemFor(state, item)
        local it = state.items[item]
        if ns.nameWaiting[item] then ns.repWaiting[item] = true end
        local fac = (UnitFactionGroup and UnitFactionGroup("player")) == "Horde" and "H" or "A"
        local who = {}
        for i = 3, #d do
            local name, f = d[i]:match("^(.-)|(%a+)$")
            if name and f:find(fac, 1, true) then who[#who + 1] = name end
        end
        local src
        -- a vendor Wowhead names without a faction ("|AH") or with no name at all sells to both
        if d[1] == "v" and (#who > 0 or #d == 2) then
            local seen = ns.db.vendor[item]
            src = { t = "vendor", cost = seen or ((it.vend or 0) > 0 and it.vend * 4 or nil), est = not seen, who = #who > 0 and who or nil,
                    npc = #who > 0 and who or nil }
        end
        if it.ah and (not src or not src.cost or it.ah < src.cost) then src = { t = "ah", cost = it.ah } end
        src = src or { t = d[1] == "q" and "quest" or "drop" }
        src.item, src.text = item, rec.source
        -- a pattern this character cannot learn yet for want of reputation is no way to get it
        local missing, line = ns.RepMissing(item)
        if missing then src = { t = "rep", item = item, text = line } end
        return src
    end
    if (rec.book and not rec.pattern) or (ns.Data and ns.Data.spell and rid ~= rec.out and ns.Data.spell[rid]) then
        return { t = "trainer", cost = ns.TrainerGuess(skill and skill[1]), est = true }
    end
    return { t = "text", text = rec.source }
end

-- The profession the window shows and its saved data; nil before any scan.
local function current()
    -- the simulation: a profession built from the recipe book, never saved
    if ns.sim then
        if not ns.sim.prof then return nil end -- still on its conditions page
        return ns.sim.name, ns.sim.prof
    end
    local db = charDB()
    local name = db.current
    local prof = name and db.profs[name]
    if not prof or empty(prof) or owned(name) == false then
        name, prof = nil, nil
        for n, p in pairs(db.profs) do
            if not empty(p) and owned(n) ~= false and (not name or n < name) then name, prof = n, p end
        end
        if not prof then return nil end
        db.current = name
    end
    return name, prof
end

-- Only the skill of that profession, without its recipes and items: cheap enough for the
-- settings column, which needs the target and the crafts cap on every click.
function ns.Skill()
    local name, prof = current()
    if not name then return nil end
    -- the simulation plans the whole way: the level a rank asks for is told, not a stop
    return { name = name, skill = prof.skill or 0, cap = prof.cap or 0, level = prof.sim and 60 or (UnitLevel("player") or 0),
             icon = prof.icon, items = {}, recipes = {}, sim = prof.sim or nil }
end

-- The profession the window shows, as a plain table for Core.lua; nil before any scan.
-- It reads counts and prices of every item, so it runs only in a calculation (ns.Tick).
function ns.State()
    local name, prof = current()
    if not name then return nil end
    local state = ns.Skill()
    -- no auction price addon: reagents at a guessed price, and no profit routes
    state.noPrices = not ns.HasPrices() or nil
    state.now = time and time() or nil -- how old the lots read at the auction are (ns.MarketTake)
    local gone = ns.Data and ns.Data.gone or {}
    local sim = prof.sim
    local skips = ns.SkipSet()
    ns.ReadRep()
    ns.repUnknown = {}
    for rid, rec in pairs(prof.recipes) do
        ns.Tick()
        -- a recipe the client lists but WoW Forever does not give (Season of Discovery, closed raids)
        if (rec.learned or not gone[rid]) and (sim or belongs(rid, name)) then
            local skill, guess
            -- a recipe of the book has its levels with it
            if rec.book then skill, guess = { rec.book[1], rec.book[2], rec.book[3] }, false
            else skill, guess = ns.Thresholds(levels(rid, rec), rec.obs, rec.grey, rec.learned) end
            -- a trainer that asks for another skill than the data says wins: the levels move with it
            local req = not rec.learned and rec.name and ns.db.trainerReq[rec.name]
            if req and skill and skill[1] and req ~= skill[1] then
                local d = req - skill[1]
                skill = { skill[1] + d, skill[2] and skill[2] + d, skill[3] and skill[3] + d, skill[4] and skill[4] + d }
            end
            local min = not rec.learned and ns.LEARN_MIN[rid]
            if min and skill and skill[1] and skill[1] < min then
                skill = { min, skill[2], skill[3], skill[4] }
            end
            local src = not rec.learned and recipeSource(state, rid, rec, skill) or nil
            -- a recipe that comes with the profession costs nothing
            if rec.free and src and src.t == "trainer" then src = { t = "trainer", cost = 0, est = false } end
            -- a recipe of a specialization this character did not choose is no way to go
            local spec = not rec.learned and ns.SPEC_OF[rid]
            if spec and (sim or not ns.HasSpec(spec)) then src = { t = "spec", spec = spec, text = ns.SpecName(spec) } end
            state.recipes[rid] = { name = rec.name or tostring(rid), skill = skill, guess = guess, r = rec.r or {},
                                   out = rec.out, count = rec.count, learned = rec.learned, src = src, icon = rec.icon,
                                   skip = skips[rid] == true or nil,
                                   cd = ns.COOLDOWNS[rid] or rec.cd, cdReady = rec.cdReady }
            for id in pairs(rec.r or {}) do itemFor(state, id) end
            if rec.out then itemFor(state, rec.out) end
        end
    end
    -- the character's other professions that make a reagent here (Smelting for Blacksmithing and
    -- Engineering): the plan may make that reagent itself when that is cheaper, never levels with it
    local need = {}
    for _, r in pairs(state.recipes) do for id in pairs(r.r) do need[id] = true end end
    for other, p in pairs(charDB().profs) do
        -- the simulated character has no other professions
        if not sim and other ~= name and not empty(p) and owned(other) ~= false then
            for rid, rec in pairs(p.recipes or {}) do
                if rec.learned and rec.out and need[rec.out] and not state.recipes[rid] and belongs(rid, other) then
                    state.recipes[rid] = { name = rec.name or tostring(rid), r = rec.r or {}, out = rec.out,
                                           count = rec.count, learned = true, icon = rec.icon, other = other,
                                           skip = skips[rid] == true or nil }
                    for id in pairs(rec.r or {}) do itemFor(state, id) end
                    itemFor(state, rec.out)
                end
            end
        end
    end
    return state
end

-- The newest auction price age among the profession's items, in days, or nil.
function ns.PriceAge(state)
    local best
    for _, it in pairs(state and state.items or {}) do
        if it.ah and (not best or (it.age or 0) < best) then best = it.age or 0 end
    end
    return best
end

-- ---------- learning prices at vendors and trainers ----------

-- Retail has only C_MerchantFrame.GetItemInfo; GetMerchantItemInfo is the classic one.
local function merchantInfo(i)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local t = C_MerchantFrame.GetItemInfo(i)
        if not t then return nil end
        return t.price, t.stackCount, t.hasExtendedCost, t.numAvailable
    end
    if GetMerchantItemInfo then
        local _, _, price, stack, avail, _, _, extended = GetMerchantItemInfo(i)
        return price, stack, extended, avail
    end
end
ns.MerchantInfo = merchantInfo

local function learnVendor()
    for i = 1, (GetMerchantNumItems and GetMerchantNumItems() or 0) do
        local id = GetMerchantItemID and GetMerchantItemID(i)
        local price, stack, extended = merchantInfo(i)
        if id and price and price > 0 and not extended then
            ns.db.vendor[id] = math.floor(price / math.max(1, stack or 1) + 0.5)
        end
    end
end

local function learnTrainer()
    for i = 1, (GetNumTrainerServices and GetNumTrainerServices() or 0) do
        local name = GetTrainerServiceInfo(i)
        local cost = GetTrainerServiceCost and GetTrainerServiceCost(i)
        if name and cost and cost > 0 then ns.db.trainer[name] = cost end
        -- the skill the trainer asks for: the game's own word on when the recipe can be learned
        if name and GetTrainerServiceSkillReq then
            local _, rank = GetTrainerServiceSkillReq(i)
            if type(rank) == "number" and rank > 0 then ns.db.trainerReq[name] = rank end
        end
    end
end

-- ---------- /gcp probe ----------

-- What this client offers, for the first try in WoW Forever.
function ns.Probe()
    local T = C_TradeSkillUI
    local lines = {}
    local function yes(v) return v and "yes" or "no" end
    lines[#lines + 1] = "Auctionator API v1: " .. yes(auctionator())
    lines[#lines + 1] = "Price addons: " .. (#ns.PriceAddons() > 0 and table.concat(ns.PriceAddons(), ", ") or "none")
    lines[#lines + 1] = "C_TradeSkillUI: " .. yes(T) .. ", GetAllRecipeIDs: " .. yes(T and T.GetAllRecipeIDs)
        .. ", GetRecipeSchematic: " .. yes(T and T.GetRecipeSchematic)
    lines[#lines + 1] = "classic GetTradeSkillInfo: " .. yes(GetTradeSkillInfo)
    local name, skill, cap = professionLine()
    lines[#lines + 1] = "open profession: " .. tostring(name) .. " " .. tostring(skill) .. "/" .. tostring(cap)
    if T and T.GetAllRecipeIDs and name then
        local ids = T.GetAllRecipeIDs() or {}
        local learned, first = 0, nil
        for _, rid in ipairs(ids) do
            local i = T.GetRecipeInfo(rid)
            if i and i.learned then learned = learned + 1; first = first or i end
        end
        lines[#lines + 1] = "recipes: " .. #ids .. ", learned " .. learned
        if first then
            lines[#lines + 1] = "first: " .. tostring(first.name) .. " difficulty " .. tostring(first.relativeDifficulty)
                .. " maxTrivialLevel " .. tostring(first.maxTrivialLevel) .. " numSkillUps " .. tostring(first.numSkillUps)
        end
    end
    local ah = ns.AuctionPrice(2589) -- Linen Cloth
    lines[#lines + 1] = "Linen Cloth price: " .. tostring(ah)
    return lines
end

-- ---------- the auction house: lots of the items a run buys ----------

local LOTS_MAX = 40
local scan = { queue = {}, busy = nil }
ns.scan = scan

local function saveLots(id, lots)
    table.sort(lots, function(a, b) return a[1] < b[1] end)
    while #lots > LOTS_MAX do table.remove(lots) end
    ns.db.lots[id] = { t = time(), l = lots }
end

-- Reads the answer to the search for `id` (modern commodities, else the classic list).
local function readLots(id)
    local A = C_AuctionHouse
    local lots = {}
    if A and A.GetNumCommoditySearchResults then
        for i = 1, A.GetNumCommoditySearchResults(id) or 0 do
            local r = A.GetCommoditySearchResultInfo(id, i)
            if r and r.unitPrice and r.quantity then lots[#lots + 1] = { r.unitPrice, r.quantity } end
        end
    elseif GetNumAuctionItems and GetAuctionItemInfo then
        for i = 1, (GetNumAuctionItems("list")) or 0 do
            local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = GetAuctionItemInfo("list", i)
            if itemID == id and buyout and buyout > 0 and (count or 0) > 0 then
                lots[#lots + 1] = { math.floor(buyout / count), count }
            end
        end
    end
    return lots
end

local function nextSearch()
    local id = table.remove(scan.queue, 1)
    scan.busy = id
    if not id then
        if ns.Toast then ns.Toast(ns.L.LOTS_DONE) end
        ns.Rebuild(true)
        return
    end
    local A = C_AuctionHouse
    if A and A.SendSearchQuery and C_AuctionHouse.MakeItemKey then
        A.SendSearchQuery(A.MakeItemKey(id), {}, false)
    elseif QueryAuctionItems then
        QueryAuctionItems(itemName(id) or "", nil, nil, 0, false, nil, false, true)
    else
        scan.queue, scan.busy = {}, nil
        return
    end
    -- no answer in time: the next item
    C_Timer.After(5, function() if scan.busy == id then nextSearch() end end)
end

function ns.OnLots()
    local id = scan.busy
    if not id then return end
    saveLots(id, readLots(id))
    C_Timer.After(0.5, function() if scan.busy == id then nextSearch() end end)
end

-- "Update the run's prices": searches each item the run buys at the auction, one at a time.
function ns.ScanLots(route)
    if not ns.atAH then return 0 end
    scan.queue = {}
    local seen = {}
    for _, e in ipairs(ns.Shopping(route)) do
        if e.id and not seen[e.id] then seen[e.id] = true; scan.queue[#scan.queue + 1] = e.id end
    end
    -- and what the run sells there: how many are on sale caps what the market takes (ns.MarketTake)
    local plan = ns.view and ns.view.plan
    for id, k in pairs(plan and plan.sellAH or {}) do
        if k > 0 and not seen[id] then seen[id] = true; scan.queue[#scan.queue + 1] = id end
    end
    local n = #scan.queue
    if n > 0 and not scan.busy then nextSearch() end
    return n
end

-- ---------- the run as the player walks it ----------

-- Where the player stands: the open place a stop can be done at.
function ns.Place()
    if ns.atAH then return "ah" end
    if ns.atVendor then return "vendor" end
    if ns.atBank then return "bank" end
    if ns.atMail then return "mail" end
    return nil
end

-- How far the current run is (ns.Progress on the bags as they are now). A later run of the
-- way has no progress: its plan starts from bags that are not there yet.
function ns.RunProgress()
    local v = ns.view
    if not v.route or not v.state then return {} end
    -- the simulation's shopping list is ticked off by what its buttons bought
    if v.state.sim and ns.SimShopOn(v) then return ns.SimShopProgress(v.route, v.state) end
    -- a simulated run is never walked: nothing of it is done
    if v.state.sim then
        local out = {}
        for i in ipairs(v.route) do out[i] = { lines = {}, segs = {}, left = 0, done = false } end
        return out
    end
    local prof = ns.char and ns.char.profs and ns.char.profs[v.state.name or ""]
    local leg = v.leg or 1
    if leg == 1 then return ns.Progress(v.route, v.state, count, v.made, v.marks, prof and prof.skill) end
    -- a later run: only its buy stops can be walked now (bought ahead, stage by stage). What came
    -- into the bags since the plan goes to the runs before it first, in their order.
    if not v.legs or not v.legs[leg] then return {} end
    local all, at = {}, 0
    for k = 1, leg - 1 do
        local l = v.legs[k]
        local plan = k == 1 and v.plan or (l and l.plan)
        local st = k == 1 and v.state or (l and l.state)
        if plan and st then
            for _, n in ipairs(ns.Route(st, plan)) do if ns.Gets(n) then all[#all + 1] = n end end
        end
    end
    at = #all
    for _, n in ipairs(v.route) do all[#all + 1] = n end
    local prog = ns.Progress(all, v.state, count)
    local out = {}
    for i, n in ipairs(v.route) do out[i] = ns.Gets(n) and prog[at + i] or { lines = {}, left = 0, done = false } end
    return out
end

-- Marks stop i done by hand, or not done again: the stops after it go on, whatever the bags say.
function ns.MarkDone(i, on)
    local v = ns.view
    if ns.sim then return end
    local n = v.route and v.route[i]
    if not n or not n.sig then return end
    v.marks = v.marks or {}
    v.marks[n.sig] = on and true or nil
    if ns.Refresh then ns.Refresh() end
end

-- A craft the game finished: it counts for the craft stops of the run. The recipe is the spell
-- (the modern API's recipe id), else the recipe of that name (a classic recipe keyed by its item).
function ns.OnCast(spell)
    local v = ns.view
    local st = v and v.state
    if not st or not spell or st.sim then return false end
    local rid = st.recipes[spell] and spell
    -- by name only while a profession window is open: every spell of a fight comes here too
    if not rid and ns.profOpen then
        local name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spell)) or (GetSpellInfo and GetSpellInfo(spell))
        if not name then return false end
        for id, r in pairs(st.recipes) do if r.name == name and r.learned then rid = id; break end end
    end
    if not rid then return false end
    v.made = v.made or {}
    v.made[rid] = (v.made[rid] or 0) + 1
    return true
end

-- ---------- buying at the auction house ----------

-- The game lets an addon buy only inside a click, and both steps are protected: asking the
-- price (StartCommoditiesPurchase) and buying (ConfirmCommoditiesPurchase). So each line takes
-- two clicks of the stop's button; nothing here runs from an event or a timer. An item that is
-- not a commodity (a pattern) takes two clicks too: the first searches its auctions
-- (SendSearchQuery), the second buys the cheapest one out (PlaceBid with its buyout).
local QUOTE_WAIT = 8
ns.buy = { queue = {}, i = 1, phase = "done", byHand = 0, bought = 0, spent = 0 }

local function AH() return C_AuctionHouse end
function ns.CanBuy()
    local a = AH()
    return a and a.StartCommoditiesPurchase and a.ConfirmCommoditiesPurchase and true or false
end
local function cancelQuote()
    local a = AH()
    if ns.buy.phase == "ready" and a and a.CancelCommoditiesPurchase then pcall(a.CancelCommoditiesPurchase) end
end

-- The queue of a stop: what is left of it to buy. Built when the stop or the plan changes.
function ns.BuyReset(node, p)
    local b = ns.buy
    cancelQuote()
    b.queue, b.byHand = ns.BuyQueue(node, p)
    b.sig, b.plan = node and node.sig, ns.view.plan
    b.i, b.quote, b.err, b.spent, b.bought, b.token = 1, nil, nil, 0, 0, nil
    b.phase = #b.queue > 0 and "idle" or "done"
end
-- The queue for this stop, built when it is another stop or another plan than before.
function ns.BuyFor(node, p)
    local b = ns.buy
    if not node or b.sig ~= node.sig or b.plan ~= ns.view.plan then ns.BuyReset(node, p) end
    return b
end
function ns.BuyLine() return ns.buy.queue[ns.buy.i] end

-- The price the auction answered is above the plan by more than the guard.
function ns.BuyDear()
    local b, line = ns.buy, ns.BuyLine()
    if b.phase ~= "ready" or not b.quote or not line then return false end
    return ns.Dear(b.quote.unit, line.unit, ns.Prefs(ns.SavedPrefs()).guard)
end

local function nextLine()
    local b = ns.buy
    b.i, b.quote = b.i + 1, nil
    b.phase = ns.BuyLine() and "idle" or "done"
end

-- Not sold as a commodity (gear, a pattern): bought as an auction of its own.
local function notCommodity(id)
    local a = AH()
    if not a or not a.GetItemCommodityStatus then return false end
    local ok, status = pcall(a.GetItemCommodityStatus, id)
    return ok and status == 1
end
local function canBuyItems()
    local a = AH()
    return a and a.MakeItemKey and a.SendSearchQuery and a.GetNumItemSearchResults and a.GetItemSearchResultInfo
        and a.PlaceBid and true or false
end

-- The cheapest auction of the line's item that has a buyout and is not the player's own: one
-- that holds no more than the line needs first, by its whole price.
function ns.ItemQuote(line)
    local a = AH()
    if not line or not line.key or not canBuyItems() then return nil end
    local best
    local ok, num = pcall(a.GetNumItemSearchResults, line.key)
    for i = 1, ok and tonumber(num) or 0 do
        local okr, r = pcall(a.GetItemSearchResultInfo, line.key, i)
        if okr and type(r) == "table" and r.auctionID and (r.buyoutAmount or 0) > 0 and not r.containsOwnerItem then
            local qty = math.max(1, r.quantity or 1)
            local fits = qty <= line.n
            local better = not best or (fits and not best.fits)
                or (fits == best.fits and r.buyoutAmount < best.total)
            if better then
                best = { auction = r.auctionID, total = r.buyoutAmount, qty = qty, unit = r.buyoutAmount / qty, fits = fits }
            end
        end
    end
    return best
end

-- The answer to the search of the line's item: its price is known now, or nobody sells it.
local function itemAnswer(final)
    local b, line = ns.buy, ns.BuyLine()
    if b.phase ~= "quote" or not line or not line.item then return end
    local q = ns.ItemQuote(line)
    if q then b.phase, b.quote = "ready", q
    elseif final then b.phase, b.err = "idle", "BUY_ERR_SOLD" end
end

local function ask()
    local b, line = ns.buy, ns.BuyLine()
    if not line then b.phase = "done"; return end
    if (line.pattern or notCommodity(line.id)) and canBuyItems() then
        local a = AH()
        local okk, key = pcall(a.MakeItemKey, line.id)
        line.item, line.key = true, okk and key or nil
        b.phase, b.quote, b.err = "quote", nil, nil
        local sort = { { sortOrder = 0, reverseSort = false } }
        if not line.key or not pcall(a.SendSearchQuery, line.key, sort, true) then
            b.phase, b.err = "idle", "BUY_ERR_START"
            return
        end
        itemAnswer(false) -- the client may have the auctions already
    elseif line.pattern or notCommodity(line.id) then
        line.hand = true
        b.byHand = b.byHand + 1
        nextLine()
        b.err = "BUY_ERR_HAND"
        return
    else
        b.phase, b.quote, b.err = "quote", nil, nil
        local ok = pcall(AH().StartCommoditiesPurchase, line.id, line.n)
        if not ok then b.phase, b.err = "idle", "BUY_ERR_START"; return end
    end
    if b.phase ~= "quote" then return end
    local token = {}
    b.token = token
    C_Timer.After(QUOTE_WAIT, function()
        if b.token == token and b.phase == "quote" then
            b.phase, b.err = "idle", "BUY_ERR_SILENT"
            if ns.Refresh then ns.Refresh() end
        end
    end)
end

-- The stop's button at the auction house: one step a click.
function ns.BuyClick()
    local b = ns.buy
    if not ns.atAH or not ns.CanBuy() then return end
    if b.phase == "idle" then ask()
    elseif b.phase == "ready" then
        local line = ns.BuyLine()
        b.phase = "buying"
        local ok
        if line.item then ok = pcall(AH().PlaceBid, b.quote.auction, b.quote.total)
        else ok = pcall(AH().ConfirmCommoditiesPurchase, line.id, line.n) end
        if not ok then b.phase, b.err = "idle", "BUY_ERR_BUY" end
    end
    if ns.Refresh then ns.Refresh() end
end

-- Leaves the current line (too dear, sold out) and goes on with the next.
function ns.BuySkip()
    local b = ns.buy
    if not ns.BuyLine() then return end
    cancelQuote()
    ns.BuyLine().skipped = true
    b.err = nil
    nextLine()
    if ns.Refresh then ns.Refresh() end
end

function ns.OnBuy(event, a1, a2)
    local b = ns.buy
    if event == "COMMODITY_PRICE_UPDATED" then
        if b.phase == "quote" then b.phase, b.quote = "ready", { unit = a1 or 0, total = a2 or 0 } end
    elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
        if b.phase == "quote" then b.phase, b.err = "idle", "BUY_ERR_SOLD" end
    elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
        if b.phase == "buying" then
            local line = ns.BuyLine()
            b.spent = b.spent + (b.quote and b.quote.total or (line.unit or 0) * line.n)
            b.bought = b.bought + 1
            if ns.SimShopOn() then ns.SimNoteBought(line.id, line.n) end
            line.done = true
            nextLine()
        end
    elseif event == "COMMODITY_PURCHASE_FAILED" then
        if b.phase == "buying" then b.phase, b.err = "idle", "BUY_ERR_BUY" end
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        itemAnswer(true)
    elseif event == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
        local line = ns.BuyLine()
        if b.phase == "buying" and line and line.item and b.quote and a1 == b.quote.auction then
            b.spent = b.spent + b.quote.total
            if ns.SimShopOn() then ns.SimNoteBought(line.id, math.min(line.n, b.quote.qty)) end
            line.n = line.n - b.quote.qty
            if line.n > 0 then
                -- an auction held fewer than the line needs: the next click searches again
                b.phase, b.quote = "idle", nil
            else
                b.bought = b.bought + 1
                line.done = true
                nextLine()
            end
        end
    elseif event == "AUCTION_HOUSE_SHOW_ERROR" then
        -- the auction is gone or the game refused the bid
        local line = ns.BuyLine()
        if b.phase == "buying" and line and line.item then b.phase, b.quote, b.err = "idle", nil, "BUY_ERR_BUY" end
    end
    if ns.Refresh then ns.Refresh() end
end

-- ---------- buying at a vendor ----------

local function goods()
    local out = {}
    for i = 1, (GetMerchantNumItems and GetMerchantNumItems() or 0) do
        local id = GetMerchantItemID and GetMerchantItemID(i)
        local price, stack, extended, avail = merchantInfo(i)
        if id and price and price > 0 and not extended then
            out[#out + 1] = { index = i, id = id, price = price, stack = stack or 1, avail = avail }
        end
    end
    return out
end

-- What a click would buy from the open vendor for this stop (ns.VendorPlan).
function ns.VendorNow(node, p)
    return ns.VendorPlan(node, p, goods(), GetMoney and GetMoney() or 0)
end

-- Buys it: everything of the stop this vendor sells, in whole stacks. Runs from the click.
function ns.BuyVendor(node, p)
    if not ns.atVendor or not BuyMerchantItem then return nil end
    local plan = ns.VendorNow(node, p)
    local shop = ns.SimShopOn()
    for _, e in ipairs(plan.buys) do
        if shop then ns.SimNoteBought(e.id, e.units) end
        if e.stack > 1 then
            -- sold in fixed stacks: one stack a call
            for _ = 1, e.stacks do BuyMerchantItem(e.index) end
        else
            local n = e.stacks
            local max = math.max(1, GetMerchantItemMaxStack and GetMerchantItemMaxStack(e.index) or 20)
            while n > 0 do
                local k = math.min(n, max)
                BuyMerchantItem(e.index, k)
                n = n - k
            end
        end
    end
    return plan
end

-- ---------- Auctionator shopping list ----------

-- Puts what the run buys at the auction into an Auctionator shopping list with the amounts.
-- Returns the number of lines, or nil without Auctionator.
function ns.ExportShopping(route, listName)
    local api = auctionator()
    if not api or not api.CreateShoppingList then return nil end
    local terms = {}
    for _, e in ipairs(ns.Shopping(route)) do
        local term = { searchString = e.name, isExact = true, quantity = e.n }
        local ok, text = false, nil
        if api.ConvertToSearchString then ok, text = pcall(api.ConvertToSearchString, CALLER, term) end
        terms[#terms + 1] = ok and text or ('"' .. e.name .. '"')
    end
    if #terms == 0 then return 0 end
    local ok = pcall(api.CreateShoppingList, CALLER, listName, terms)
    return ok and #terms or nil
end

-- ---------- crafting from a stop ----------

-- The classic profession window lists recipes by index: the index of a recipe by its name.
local function classicIndex(name)
    if not GetNumTradeSkills then return nil end
    for i = 1, GetNumTradeSkills() do
        if GetTradeSkillInfo(i) == name then return i end
    end
end

-- Shows the recipe in the open profession window. Returns false when the window is closed.
-- The profession a recipe of the plan is crafted in: the current one, or the other profession
-- of the character that makes one of its reagents.
function ns.ProfOf(rid)
    local cur = ns.char.current
    local p = ns.char.profs[cur or ""]
    if p and p.recipes[rid] then return cur end
    for name, q in pairs(ns.char.profs) do
        if name ~= cur and q.recipes and q.recipes[rid] and q.recipes[rid].learned then return name end
    end
    return cur
end
local function recOf(rid)
    local p = ns.char.profs[ns.ProfOf(rid) or ""]
    return p and p.recipes[rid]
end

function ns.OpenRecipe(rid)
    local rec = recOf(rid)
    local name = rec and rec.name
    if C_TradeSkillUI and C_TradeSkillUI.OpenRecipe and type(rid) == "number" and rid ~= (rec and rec.out) then
        C_TradeSkillUI.OpenRecipe(rid)
        return true
    end
    local i = name and classicIndex(name)
    if not i then return false end
    if TradeSkillFrame_SetSelection then TradeSkillFrame_SetSelection(i) elseif SelectTradeSkill then SelectTradeSkill(i) end
    if TradeSkillFrame_Update then TradeSkillFrame_Update() end
    return true
end

-- Crafts n of a recipe; runs from the Make click (the game wants a hardware event).
function ns.Craft(rid, n)
    local rec = recOf(rid)
    if not rec then return false end
    if C_TradeSkillUI and C_TradeSkillUI.CraftRecipe and type(rid) == "number" and rid ~= rec.out then
        C_TradeSkillUI.CraftRecipe(rid, n)
        return true
    end
    local i = classicIndex(rec.name)
    if not i or not DoTradeSkill then return false end
    DoTradeSkill(i, n)
    return true
end

-- ---------- the profession window ----------
-- Craft and CraftRecipe work only while the profession window is open, so a craft stop's first
-- click opens it (C_TradeSkillUI.OpenTradeSkill with the profession's skill line from the
-- spellbook) and shows the recipe once it is open; the next click crafts.

ns.profOpen = false
ns.pendingRecipe = nil

local function skillLineOf(name)
    if not name or not GetProfessions or not GetProfessionInfo then return nil end
    local list = { GetProfessions() } -- may hold gaps (no second profession, no fishing)
    for k = 1, 6 do
        local i = list[k]
        if i then
            local n, _, _, _, _, _, line = GetProfessionInfo(i)
            if n == name then return line end
        end
    end
end
ns.SkillLineOf = skillLineOf

-- The window of a profession (the current one by default) shows now.
-- The game's profession window is on the screen. The events alone can mislead: going from one
-- profession's window to another's may send its CLOSE after the new SHOW.
local function windowShown()
    for _, f in ipairs({ _G.ProfessionsFrame, _G.TradeSkillFrame }) do
        if f and f.IsShown and f:IsShown() then return true end
    end
    return false
end

function ns.ProfessionShown(prof)
    if not ns.profOpen and not windowShown() then return false end
    local name = windowLine()
    return name == nil or name == (prof or ns.char.current)
end

-- The client can open the profession window from a click (else the stop keeps Make).
function ns.CanOpenProfession(prof)
    return C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill and skillLineOf(prof or ns.char.current) and true or false
end

-- Opens the window of the profession `rid` is crafted in; `rid` is shown in it once it is open.
-- Another profession opened this way (Mining for its bars) does not become the current one.
function ns.OpenProfession(rid)
    local prof = rid and ns.ProfOf(rid) or ns.char.current
    local line = skillLineOf(prof)
    local T = C_TradeSkillUI
    if not line or not T or not T.OpenTradeSkill then return false end
    local ok, opened = pcall(T.OpenTradeSkill, line)
    if not ok or opened == false then return false end
    ns.pendingRecipe = rid
    ns.helperOpen = prof ~= ns.char.current and prof or nil
    return true
end

-- ---------- the run log ----------

function ns.StartRun()
    if ns.sim then return nil end
    local e = ns.LogStart(ns.view, GetMoney and GetMoney() or 0, time())
    if not e then return nil end
    ns.char.run = e
    return e
end

function ns.FinishRun()
    local e = ns.char.run
    if not e then return nil end
    local prof = ns.char.profs[e.prof]
    ns.LogFinish(e, prof and prof.skill or e.from, GetMoney and GetMoney() or 0, time())
    ns.char.run = nil
    table.insert(ns.char.log, 1, e)
    while #ns.char.log > 10 do table.remove(ns.char.log) end
    return e
end

-- ---------- events ----------

-- The player opened or left a place: the window shows the stop for it (UI.lua replaces this).
function ns.Arrive(place) if ns.Refresh then ns.Refresh() end end

-- Forever lacks some classic events (TRADE_SKILL_UPDATE, AUCTION_ITEM_LIST_UPDATE): an unknown
-- name must not stop the rest of the list.
function ns.Listen(frame, events)
    local valid = C_EventUtils and C_EventUtils.IsEventValid
    for _, e in ipairs(events) do
        if not valid or valid(e) then pcall(frame.RegisterEvent, frame, e) end
    end
end

-- The reputation list was read again: a standing the plan did not know makes it outdated, and the
-- banner that asks for the reputation window goes away.
function ns.RepChanged()
    local waited = #ns.RepUnknown() > 0
    if not ns.ReadRep() then return end
    if ns.view and ns.view.plan then ns.view.stale = true end
    if (waited or ns.view) and ns.Refresh then ns.Refresh() end
end

-- Opening the reputation window is what makes the game give the whole list: read it then.
function ns.HookRepWindow()
    local rf = ReputationFrame
    if rawget(ns, "repHooked") or type(rf) ~= "table" or not rf.HookScript then return end
    ns.repHooked = true
    rf:HookScript("OnShow", function()
        ns.RepChanged()
        if C_Timer and C_Timer.After then C_Timer.After(0.2, ns.RepChanged) end
    end)
end

local pending = false
-- A place closed (or the player walked away from it).
ns.PLACE_CLOSED = {
    merchant = function() ns.atVendor = false; ns.Arrive(nil) end,
    bank = function() ns.atBank = false; ns.Arrive(nil) end,
    mail = function() ns.atMail = false; ns.Arrive(nil) end,
    auction = function()
        cancelQuote()
        if ns.buy.phase ~= "done" then ns.buy.phase, ns.buy.quote = "idle", nil end
        ns.atAH, scan.queue, scan.busy = false, {}, nil
        ns.Arrive(nil)
    end,
}

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1, a2, a3)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliCraftProfitDB = GulliCraftProfitDB or {}
        ns.db = GulliCraftProfitDB
        ns.db.prefs = ns.db.prefs or {}
        ns.db.vendor = ns.db.vendor or {}
        ns.db.trainer = ns.db.trainer or {}
        ns.db.trainerReq = ns.db.trainerReq or {}
        ns.db.gather = ns.db.gather or {}
        ns.db.skip = ns.db.skip or {}
        ns.db.lots = ns.db.lots or {}
        GulliCraftProfitCharDB = GulliCraftProfitCharDB or {}
        ns.char = GulliCraftProfitCharDB
        ns.char.profs = ns.char.profs or {}
        ns.char.log = ns.char.log or {}
        for name, p in pairs(ns.char.profs) do if empty(p) then ns.char.profs[name] = nil end end
        ns.Listen(self, { "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_UPDATE",
                          "MERCHANT_SHOW", "TRAINER_SHOW", "BAG_UPDATE_DELAYED", "MAIL_INBOX_UPDATE",
                          "AUCTION_HOUSE_SHOW", "COMMODITY_SEARCH_RESULTS_UPDATED",
                          "AUCTION_ITEM_LIST_UPDATE", "BANKFRAME_OPENED",
                          "MAIL_SHOW", "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE",
                          "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED", "GET_ITEM_INFO_RECEIVED",
                          "ITEM_SEARCH_RESULTS_UPDATED", "AUCTION_HOUSE_PURCHASE_COMPLETED", "AUCTION_HOUSE_SHOW_ERROR",
                          "UPDATE_FACTION", "PLAYER_ENTERING_WORLD" })
        if self.RegisterUnitEvent then pcall(self.RegisterUnitEvent, self, "UNIT_SPELLCAST_SUCCEEDED", "player") end
        -- every way a place closes, walking away too: the stop and the window beside it follow
        if ns.Skin and ns.Skin.ClosesWith then
            for place, fn in pairs(ns.PLACE_CLOSED) do ns.Skin.ClosesWith(place, fn) end
        end
        local api = auctionator()
        if api and api.RegisterForDBUpdate then
            pcall(api.RegisterForDBUpdate, CALLER, function() ns.Rebuild(false, "event") end)
        end
        return
    end
    if next(ns.nameWaiting) then ns.CheckNames() end
    if event == "GET_ITEM_INFO_RECEIVED" then return end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if a1 == "player" and ns.OnCast(a3) and ns.Refresh then ns.Refresh() end
        return
    end
    if event == "UPDATE_FACTION" or event == "PLAYER_ENTERING_WORLD" then
        if event == "PLAYER_ENTERING_WORLD" then ns.HookRepWindow() end
        ns.RepChanged()
        return
    end
    if event == "MERCHANT_SHOW" then learnVendor(); ns.atVendor = true; ns.Arrive("vendor"); return end
    if event == "BANKFRAME_OPENED" then ns.atBank = true; ns.Arrive("bank"); return end
    if event == "MAIL_SHOW" then ns.atMail = true; ns.Arrive("mail"); return end
    if event == "TRAINER_SHOW" then learnTrainer(); return end
    if event == "TRADE_SKILL_CLOSE" then
        ns.profOpen, ns.pendingRecipe, ns.helperOpen = false, nil, nil
        if ns.Refresh then ns.Refresh() end
        return
    end
    if event == "TRADE_SKILL_SHOW" then ns.profOpen = true end
    if event == "MAIL_INBOX_UPDATE" then snapshotMail(); return end
    if event == "AUCTION_HOUSE_SHOW" then ns.atAH = true; ns.Arrive("ah"); return end
    if event:sub(1, 10) == "COMMODITY_" and event ~= "COMMODITY_SEARCH_RESULTS_UPDATED" then ns.OnBuy(event, a1, a2); return end
    if event == "ITEM_SEARCH_RESULTS_UPDATED" or event == "AUCTION_HOUSE_PURCHASE_COMPLETED"
        or event == "AUCTION_HOUSE_SHOW_ERROR" then ns.OnBuy(event, a1, a2); return end
    if event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "AUCTION_ITEM_LIST_UPDATE" then ns.OnLots(); return end
    -- the run's progress follows the bags at once; the plan itself only goes stale
    if event == "BAG_UPDATE_DELAYED" and ns.Refresh then ns.Refresh() end
    if pending then return end
    pending = true
    C_Timer.After(0.5, function()
        pending = false
        if event ~= "BAG_UPDATE_DELAYED" then
            local name = ns.ScanProfession()
            if name and event == "TRADE_SKILL_SHOW" and name ~= ns.helperOpen then ns.char.current = name end
            -- the window a craft stop opened: show its recipe there
            if ns.pendingRecipe and ns.profOpen then
                local rid = ns.pendingRecipe
                ns.pendingRecipe = nil
                ns.OpenRecipe(rid)
            end
        end
        ns.Rebuild(false, "event")
    end)
end)
