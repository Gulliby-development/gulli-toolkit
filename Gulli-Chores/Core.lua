-- A to-do list for every character. Each character saves a snapshot when it plays; the list
-- works out what is waiting now: mail that runs out, crafting cooldowns, the trainer, rested
-- XP, repairs and bag space. It also keeps the bags and the bank for Gulli Tooltip.

local ADDON, ns = ...
local L = ns.L

local DAY = 86400
-- Crafting cooldowns worth coming back for. key: CD_<X> ("... is ready") or a CRAFT_<X> name;
-- line: the profession's skill line; spells: recipe spell -> seconds of its cooldown (the
-- transmutes share one, so one entry is enough); made: the item it makes, for the icon; item: an
-- item with a cooldown of its own. A cooldown of another recipe comes from Gulli Craft Profit,
-- which learns it from the game. A new cooldown goes here, with its CRAFT_ text.
ns.CRAFTS = {
    { key = "CD_TRANSMUTE", line = 171, spells = {
        [11479] = 2 * DAY, [11480] = 2 * DAY, [17187] = 2 * DAY,          -- Iron to Gold, Mithril to Truesilver, Arcanite
        [17559] = DAY, [17560] = DAY, [17561] = DAY, [17562] = DAY,       -- the elemental transmutes
        [17563] = DAY, [17564] = DAY, [17565] = DAY, [17566] = DAY,
        [25146] = DAY } },                                                -- Elemental Fire
    { key = "CD_LEGIONITE", line = 171, made = 251290, spells = { [1317279] = DAY } }, -- WoW Forever
    { key = "CD_MOONCLOTH", line = 197, made = 14342, spells = { [18560] = 4 * DAY } },
    { key = "CD_HIDE", line = 165, made = 15407, spells = { [19047] = 3 * DAY } },     -- Cured Rugged Hide
    { key = "CD_SALT", line = 165, item = 15846 },                                      -- Salt Shaker
}
-- recipe spell -> its cooldown's key and seconds
ns.CD_KEY, ns.CD_SECONDS = {}, {}
for _, cr in ipairs(ns.CRAFTS) do
    for spell, sec in pairs(cr.spells or {}) do ns.CD_KEY[spell], ns.CD_SECONDS[spell] = cr.key, sec end
end

local RESTED_PER_8H = 0.05 -- of a level, in an inn; a quarter of it outside
local RESTED_MAX = 1.5
local HEARTHSTONE = 6948
ns.RESTED_MAX = RESTED_MAX

-- The tasks in the order the list shows them; each one has a switch in the settings.
ns.TASKS = { "EXPIRE", "CD", "TRAINER", "PROF", "MAIL", "RESTED", "REPAIR", "BAGS" }
-- Settings in GulliChoresDB; each change goes through ns.SetPref.
ns.DEFAULTS = { login = true, alerts = true, repairAt = 30, bagsAt = 2, mailDays = 3, filter = "all" }
ns.FILTERS = { "all", "realm", "faction" }

-- Game API wrappers.
local function knows(spell) return IsPlayerSpell and IsPlayerSpell(spell) or false end
local function spellCooldown(spell)
    if C_Spell and C_Spell.GetSpellCooldown then
        local c = C_Spell.GetSpellCooldown(spell)
        if c then return c.startTime or 0, c.duration or 0 end
        return 0, 0
    end
    local start, duration = GetSpellCooldown(spell)
    return start or 0, duration or 0
end
local function itemCooldown(id)
    local get = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    if not get then return 0, 0 end
    local start, duration = get(id)
    return start or 0, duration or 0
end
local function itemCount(id)
    return ((C_Item and C_Item.GetItemCount) or GetItemCount)(id) or 0
end
local function numSlots(bag)
    local get = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    return get and get(bag) or 0
end
-- The item id and count in a bag slot.
local function slotItem(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then return info.itemID, info.stackCount or 1 end
        return nil
    end
    if GetContainerItemInfo then
        local _, count, _, _, _, _, _, _, _, id = GetContainerItemInfo(bag, slot)
        return id, count
    end
end
local function freeSlots()
    local free = 0
    for bag = 0, 4 do
        local f, family = ((C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots)(bag)
        if (family or 0) == 0 then free = free + (f or 0) end
    end
    return free
end
local function secret(v) return issecretvalue and issecretvalue(v) end
local function bindLocation() return GetBindLocation and GetBindLocation() or nil end
local function faction() return UnitFactionGroup and UnitFactionGroup("player") or nil end
-- { { name, skill, cap } } of the professions, from the game, else from Gulli Craft Profit.
local function professions()
    local out = {}
    if GetProfessions and GetProfessionInfo then
        for _, i in ipairs({ GetProfessions() }) do
            local name, icon, rank, max, _, _, line = GetProfessionInfo(i)
            if name then out[#out + 1] = { name = name, icon = icon, skill = rank or 0, cap = max or 0, line = line } end
        end
        if #out > 0 then return out end
    end
    local db = GulliCraftProfitCharDB
    for name, p in pairs(type(db) == "table" and type(db.profs) == "table" and db.profs or {}) do
        if type(p) == "table" and p.skill then out[#out + 1] = { name = name, icon = p.icon, skill = p.skill, cap = p.cap or 0 } end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end
-- Raid and dungeon lockouts that hold now: { { name, til } } in real time.
local function lockouts(now)
    if not (GetNumSavedInstances and GetSavedInstanceInfo) then return nil end
    local out = {}
    for i = 1, GetNumSavedInstances() or 0 do
        local name, _, reset, _, locked = GetSavedInstanceInfo(i)
        if name and locked and (reset or 0) > 0 then out[#out + 1] = { name = name, til = now + reset } end
    end
    return out
end
-- Bag slots in the bank: the bank itself and its bags.
local function bankBags()
    local out = { BANK_CONTAINER or -1 }
    local first = (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) + 1
    for b = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do out[#out + 1] = b end
    return out
end
local function countItems(bags)
    local out = {}
    for _, bag in ipairs(bags) do
        for slot = 1, numSlots(bag) do
            local id, n = slotItem(bag, slot)
            if id and not secret(id) then out[id] = (out[id] or 0) + (n or 1) end
        end
    end
    return out
end

-- The realm the game gives now, or nil: some WoW Forever sessions give an empty realm name.
local function liveRealm()
    local r = GetRealmName and GetRealmName()
    if type(r) == "string" and r ~= "" then return r end
end

-- The one realm saved for this name, or nil when there is none or more than one.
local function savedRealm(chars, name)
    local found
    for key in pairs(chars or {}) do
        local n, r = key:match("^(.-)%-(.+)$")
        if n == name then
            if found and found ~= r then return nil end
            found = r
        end
    end
    return found
end

-- This character's realm: the game's, else the one saved for this name, else the last one seen.
function ns.Realm()
    local realm = liveRealm()
    if realm then
        if ns.db then ns.db.realm = realm end
        return realm
    end
    return ns.db and (savedRealm(ns.db.chars, UnitName("player")) or ns.db.realm) or nil
end

function ns.CharKey()
    return (UnitName("player") or "?") .. "-" .. (ns.Realm() or "")
end

-- Moves entries saved with an empty realm ("Name-") onto that name's realm: the newer snapshot
-- wins and keeps what only the older one has; hidden and told marks move with it.
function ns.MergeRealmless()
    local chars = ns.db and ns.db.chars
    if not chars then return end
    ns.Realm() -- notes the realm the game gives now
    local moves = {}
    for key, c in pairs(chars) do
        local name = key:match("^(.-)%-$")
        local realm = name and (savedRealm(chars, name) or ns.db.realm)
        if realm then moves[#moves + 1] = { key, name .. "-" .. realm, c, realm } end
    end
    for _, m in ipairs(moves) do
        local from, to, c, realm = m[1], m[2], m[3], m[4]
        local other = chars[to]
        if other then
            local new, old = c, other
            if (other.t or 0) > (c.t or 0) then new, old = other, c end
            for k, v in pairs(old) do if new[k] == nil then new[k] = v end end
            chars[to] = new
        else
            chars[to] = c
        end
        chars[to].realm = realm
        chars[from] = nil
        local hidden = ns.db.hidden
        if hidden and hidden[from] then hidden[to], hidden[from] = true, nil end
        local told, renamed = ns.db.alerted or {}, {}
        for id, v in pairs(told) do
            if id:sub(1, #from + 1) == from .. ":" then renamed[id] = v end
        end
        for id, v in pairs(renamed) do
            local nid = to .. id:sub(#from + 1)
            if (told[nid] or 0) < v then told[nid] = v end
            told[id] = nil
        end
    end
end

-- The learned recipes with a cooldown that Gulli Craft Profit saw: recipe spell -> { name, prof, cd, ready }.
local function craftProfitCooldowns()
    local out = {}
    local db = GulliCraftProfitCharDB
    for prof, p in pairs(type(db) == "table" and type(db.profs) == "table" and db.profs or {}) do
        for rid, r in pairs(type(p) == "table" and type(p.recipes) == "table" and p.recipes or {}) do
            if type(rid) == "number" and type(r) == "table" and r.learned then
                out[rid] = { name = r.name, prof = prof, cd = tonumber(r.cd), ready = tonumber(r.cdReady) }
            end
        end
    end
    return out
end

-- GetTime counts milliseconds in 32 bits: a start the game gives ahead of the clock began
-- 2^32 ms (about 49.7 days) earlier. Time left is never more than the cooldown itself (max).
ns.CLOCK_WRAP = 4294967.296
local function readyAt(start, duration, now, clock, max)
    if secret(start) or secret(duration) then return nil end
    if start > clock then start = start - ns.CLOCK_WRAP end
    local left = (start > 0 and duration > 1.5) and (start + duration - clock) or 0
    left = math.min(left, duration, max or duration)
    return now + math.max(0, math.floor(left)), left > 0
end

function ns.HasProf(profs, name)
    for _, p in ipairs(profs or {}) do if p.name == name then return true end end
    return false
end

local function profName(profs, line)
    for _, p in ipairs(profs or {}) do if line and p.line == line then return p.name end end
end
-- false when the profession of that skill line is surely gone (every profession tells its line).
local function hasLine(profs, line)
    if #profs == 0 then return true end
    for _, p in ipairs(profs) do
        if p.line == nil or p.line == line then return true end
    end
    return false
end

-- The game's name of a cooldown, saved so another character shows it in the same words.
local function gameName(cr)
    if cr.key == "CD_TRANSMUTE" then return nil end
    if cr.item then
        local get = (C_Item and C_Item.GetItemNameByID) or GetItemInfo
        local n = get and get(cr.item)
        return type(n) == "string" and n ~= "" and n or nil
    end
    local spell = next(cr.spells)
    local n = (C_Spell and C_Spell.GetSpellName) and C_Spell.GetSpellName(spell) or (GetSpellInfo and GetSpellInfo(spell))
    return type(n) == "string" and n ~= "" and n or nil
end

-- Every crafting cooldown of this character as real time, so another character can check it:
-- c.cooldowns key -> ready, c.cdProf key -> profession, c.cdNames key -> name. A recipe counts as
-- learned once the game, its cooldown, Gulli Craft Profit or the profession window said so
-- (c.cdSpells, kept until the profession is gone); c.cdTrade keeps what the profession window or
-- a craft said (spell -> ready), since the spell cooldown may not show a recipe's.
function ns.ReadCooldowns(c, old, now, clock)
    old = old or {}
    local spells, trade = old.cdSpells or {}, old.cdTrade or {}
    local cp = craftProfitCooldowns()
    c.cooldowns, c.cdProf, c.cdNames, c.cdSpells, c.cdTrade = {}, {}, {}, {}, {}
    local function spellReady(spell)
        local s, d = spellCooldown(spell)
        local r, running = readyAt(s, d, now, clock, ns.CD_SECONDS[spell])
        local t = trade[spell]
        if t and t > now then
            c.cdTrade[spell] = t
            if not r or t > r then r = t end
        end
        return r, running
    end
    for _, cr in ipairs(ns.CRAFTS) do
        local best
        if cr.item then
            if itemCount(cr.item) > 0 then
                local s, d = itemCooldown(cr.item)
                best = readyAt(s, d, now, clock)
            end
        elseif hasLine(c.profs, cr.line) then
            for spell in pairs(cr.spells) do
                local r, running = spellReady(spell)
                if knows(spell) or running or spells[spell] or cp[spell] or c.cdTrade[spell] then
                    c.cdSpells[spell] = true
                    if r and (not best or r < best) then best = r end
                end
            end
        end
        if best then
            c.cooldowns[cr.key] = best
            c.cdProf[cr.key] = profName(c.profs, cr.line)
            c.cdNames[cr.key] = gameName(cr)
        end
    end
    -- A recipe the profession window showed with a cooldown stays while its profession does.
    c.cdOther = {}
    for rid, o in pairs(old.cdOther or {}) do
        if not ns.CD_KEY[rid] and not cp[rid] and (o.prof == nil or #c.profs == 0 or ns.HasProf(c.profs, o.prof)) then
            c.cdOther[rid] = o
            local key = "R" .. rid
            c.cooldowns[key], c.cdProf[key], c.cdNames[key] = spellReady(rid) or now, o.prof, o.name
        end
    end
    for rid, r in pairs(cp) do
        if not ns.CD_KEY[rid] and (r.cd or 0) > 0 then
            local key = "R" .. rid
            local ready = spellReady(rid) or now
            if r.ready and r.ready > ready then ready = r.ready end
            c.cooldowns[key], c.cdProf[key], c.cdNames[key] = ready, r.prof, r.name
        end
    end
end

-- Once: 1.14.0 and 1.14.1 did not undo the game's clock wrap, so they saved cooldowns of
-- 50 days. Drop what is longer than it can be.
function ns.FixCooldowns()
    if ns.db.cdFix then return end
    local longest = {}
    for spell, sec in pairs(ns.CD_SECONDS) do
        local k = ns.CD_KEY[spell]
        if sec > (longest[k] or 0) then longest[k] = sec end
    end
    for _, c in pairs(ns.db.chars) do
        local t = c.t or 0
        for k, ready in pairs(c.cooldowns or {}) do
            local most = longest[k] or 7 * 86400
            if ready - t > most then
                c.cooldowns[k] = nil
                if c.cdProf then c.cdProf[k] = nil end
                if c.cdNames then c.cdNames[k] = nil end
            end
        end
        for spell, ready in pairs(c.cdTrade or {}) do
            if ready - t > (ns.CD_SECONDS[spell] or 7 * 86400) then c.cdTrade[spell] = nil end
        end
        if c.hearth and c.hearth - t > 3600 then c.hearth = t end
    end
    ns.db.cdFix = 1
end

-- Takes this character's snapshot. What the game only shows at the mailbox or the bank, and
-- what the player wrote, stays from the last one.
function ns.Snapshot()
    ns.MergeRealmless()
    local key = ns.CharKey()
    local old = ns.db.chars[key] or {}
    local _, class = UnitClass("player")
    local now, clock = time(), GetTime()
    local c = { name = UnitName("player"), class = class, level = UnitLevel("player"), t = now,
                realm = ns.Realm(), faction = faction(),
                trainer = old.trainer, note = old.note, bank = old.bank, mailUntil = old.mailUntil,
                mailItems = old.mailItems, cod = old.cod, played = old.played, lockouts = old.lockouts,
                money = GetMoney and GetMoney() or 0 }
    local max = UnitXPMax and UnitXPMax("player") or 0
    local rested = GetXPExhaustion and GetXPExhaustion() or 0
    c.rested = max > 0 and (rested or 0) / max or 0
    c.resting = IsResting and IsResting() or false
    c.maxLevel = (GetMaxPlayerLevel and GetMaxPlayerLevel() or 60) <= c.level
    c.mail = HasNewMail and HasNewMail() or false
    c.free = freeSlots()
    local lowest = 100
    for slot = 1, 18 do
        local cur, mx = GetInventoryItemDurability(slot)
        if cur and mx and mx > 0 then lowest = math.min(lowest, math.floor(cur * 100 / mx)) end
    end
    c.durability = lowest
    c.profs = professions()
    ns.ReadCooldowns(c, old, now, clock)
    if itemCount(HEARTHSTONE) > 0 then
        local start, duration = itemCooldown(HEARTHSTONE)
        c.hearth = readyAt(start, duration, now, clock) or now
    end
    c.bind = bindLocation()
    c.lockouts = lockouts(now) or old.lockouts
    local worn = {}
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do worn[#worn + 1] = bag end
    c.items = countItems(worn)
    ns.db.chars[key] = c
    return c
end

-- The profession window: which of the cooldown recipes this character learned, and when each
-- is ready (the window tells a recipe's cooldown even where the spell cooldown does not).
function ns.ReadTrade()
    local T = C_TradeSkillUI
    local c = ns.db and ns.db.chars[ns.CharKey()]
    if not (c and T and T.GetRecipeInfo) then return end
    -- Another player's window (a link, the guild, an NPC) says nothing about this character.
    for _, f in ipairs({ "IsTradeSkillLinked", "IsTradeSkillGuild", "IsNPCCrafting" }) do
        if T[f] then
            local ok, yes = pcall(T[f])
            if ok and yes then return end
        end
    end
    c.cdSpells, c.cdTrade, c.cdOther = c.cdSpells or {}, c.cdTrade or {}, c.cdOther or {}
    local now = time()
    -- Every other learned recipe of this window whose cooldown runs: c.cdOther rid -> name, prof.
    if T.GetAllRecipeIDs and T.GetRecipeCooldown then
        local ok, ids = pcall(T.GetAllRecipeIDs)
        local prof
        if T.GetBaseProfessionInfo then
            local ok2, pi = pcall(T.GetBaseProfessionInfo)
            prof = ok2 and type(pi) == "table" and pi.professionName or nil
        end
        for _, rid in ipairs(ok and type(ids) == "table" and ids or {}) do
            if not ns.CD_KEY[rid] then
                local ok2, info = pcall(T.GetRecipeInfo, rid)
                local ok3, left = pcall(T.GetRecipeCooldown, rid)
                left = ok3 and tonumber(left)
                if ok2 and type(info) == "table" and info.learned and left and left > 0 then
                    c.cdOther[rid] = { name = info.name, prof = prof }
                    c.cdTrade[rid] = now + math.ceil(left)
                end
            end
        end
    end
    for spell in pairs(ns.CD_KEY) do
        local ok, info = pcall(T.GetRecipeInfo, spell)
        if ok and type(info) == "table" and info.learned then
            c.cdSpells[spell] = true
            if T.GetRecipeCooldown then
                local ok2, left = pcall(T.GetRecipeCooldown, spell)
                left = ok2 and tonumber(left)
                c.cdTrade[spell] = (left and left > 0) and now + math.ceil(left) or nil
            end
        end
    end
end

-- A craft of this character that has a cooldown: it is learned and waits from now on.
function ns.OnCast(spell)
    if secret(spell) then return false end
    local sec = ns.CD_SECONDS[spell]
    if not sec then
        local r = craftProfitCooldowns()[spell]
        sec = r and r.cd
    end
    local c = ns.db and ns.db.chars[ns.CharKey()]
    if not (sec and sec > 0 and c) then return false end
    c.cdSpells, c.cdTrade = c.cdSpells or {}, c.cdTrade or {}
    c.cdSpells[spell], c.cdTrade[spell] = true, time() + sec
    return true
end

-- A cooldown's name: the game's, saved with the character, else ours.
function ns.CdName(c, key)
    local n = c and c.cdNames and c.cdNames[key]
    if n then return n end
    return L["CRAFT_" .. key:gsub("^CD_", "")]
end

-- The task line of a ready cooldown.
function ns.CdTask(c, key)
    if ns.T.en[key] then return L[key] end
    return L.CD_READY:format(ns.CdName(c, key))
end

-- The cooldowns of a character: { { key, name, prof, ready } }, ready first, then the soonest.
function ns.Cooldowns(c, now)
    now = now or time()
    local out = {}
    for key, ready in pairs(c.cooldowns or {}) do
        out[#out + 1] = { key = key, name = ns.CdName(c, key), prof = c.cdProf and c.cdProf[key],
                          ready = ready, done = ready <= now }
    end
    table.sort(out, function(a, b)
        if a.done ~= b.done then return a.done end
        if not a.done and a.ready ~= b.ready then return a.ready < b.ready end
        return a.name < b.name
    end)
    return out
end

-- Every visible character's cooldowns for the Cooldowns tab: { { charKey, char, key, name, prof,
-- ready, done } }, ready first, then the soonest; and how many are ready and on how many characters.
function ns.CdList(now)
    now = now or time()
    local out, ready, crafters, waiting = {}, 0, 0, {}
    for _, e in ipairs(ns.Chars()) do
        local list = ns.Cooldowns(e.char, now)
        if #list > 0 then crafters = crafters + 1 end
        for _, cd in ipairs(list) do
            cd.charKey, cd.char, cd.me = e.key, e.char, e.me
            out[#out + 1] = cd
            if cd.done then ready = ready + 1; waiting[e.key] = true end
        end
    end
    table.sort(out, function(a, b)
        if a.done ~= b.done then return a.done end
        if not a.done and a.ready ~= b.ready then return a.ready < b.ready end
        if a.charKey ~= b.charKey then return a.charKey < b.charKey end
        return a.name < b.name
    end)
    local chars = 0
    for _ in pairs(waiting) do chars = chars + 1 end
    return out, ready, chars, crafters
end

-- At the mailbox: when the first letter with items or money runs out, and how many ask for COD.
function ns.ReadMail()
    local c = ns.db.chars[ns.CharKey()] or ns.Snapshot()
    local n = GetInboxNumItems and GetInboxNumItems() or 0
    local soonest, items, cod
    items, cod = 0, 0
    for i = 1, n do
        local _, _, _, _, money, codAmount, daysLeft, itemCount = GetInboxHeaderInfo(i)
        if (itemCount or 0) > 0 or (money or 0) > 0 then
            items = items + 1
            if daysLeft and (not soonest or daysLeft < soonest) then soonest = daysLeft end
        end
        if (codAmount or 0) > 0 then cod = cod + 1 end
    end
    c.mailUntil = soonest and (time() + math.floor(soonest * 86400)) or nil
    c.mailItems, c.cod = items, cod
    return c
end

-- At the bank: what the bank holds, for the tooltip of Gulli Tooltip.
function ns.ReadBank()
    local c = ns.db.chars[ns.CharKey()] or ns.Snapshot()
    c.bank = countItems(bankBags())
    return c
end

-- A short time span: "3 d", "5 h", "12 min".
-- A cooldown's time left: days with hours, hours, or under an hour.
function ns.CdSpan(sec)
    sec = math.max(0, math.floor(sec))
    local d, h = math.floor(sec / 86400), math.floor(sec % 86400 / 3600)
    if d > 0 then return h > 0 and (L.DAYS:format(d) .. " " .. L.HOURS:format(h)) or L.DAYS:format(d) end
    if h > 0 then return L.HOURS:format(h) end
    return "< " .. L.HOURS:format(1)
end

function ns.Span(sec)
    sec = math.max(0, math.floor(sec))
    if sec >= 86400 then return L.DAYS:format(math.floor(sec / 86400)) end
    if sec >= 3600 then return L.HOURS:format(math.floor(sec / 3600)) end
    return L.MINUTES:format(math.max(1, math.floor(sec / 60)))
end

local function restRate(c) return RESTED_PER_8H / 8 * (c.resting and 1 or 0.25) end

-- Rested XP now, as a share of a level, counting the time since the snapshot.
function ns.RestedNow(c, now)
    local hours = math.max(0, (now or time()) - c.t) / 3600
    return math.min(RESTED_MAX, (c.rested or 0) + hours * restRate(c))
end

-- Seconds until rested XP is full (0 when it is; nil at the top level).
function ns.RestedFullIn(c, now)
    if c.maxLevel then return nil end
    local left = RESTED_MAX - ns.RestedNow(c, now)
    if left <= 0 then return 0 end
    return math.ceil(left / restRate(c) * 3600)
end

-- New class spells come at even levels, so an odd level alone does not send you to the trainer.
function ns.TrainerDue(c)
    return c.trainer ~= nil and (c.level or 0) > c.trainer and math.floor(c.level / 2) * 2 > c.trainer
end

local function on(key) return not (ns.db and ns.db.off and ns.db.off[key]) end
local function pref(key)
    local v = ns.db and ns.db[key]
    if v == nil then return ns.DEFAULTS[key] end
    return v
end

-- What is waiting for a character: { { key, text, cd, icon } }, the most useful first; cd is the
-- cooldown's text key, icon the profession's own for a full rank.
function ns.Tasks(c, now)
    now = now or time()
    local out = {}
    local function add(key, text, cd, icon)
        if on(key) then out[#out + 1] = { key = key, text = text, cd = cd, icon = icon } end
    end
    if c.mailUntil and c.mailUntil > now and c.mailUntil - now < pref("mailDays") * 86400 then
        add("EXPIRE", L.TASK_EXPIRE:format(ns.Span(c.mailUntil - now)))
    end
    local cds = {}
    for text, ready in pairs(c.cooldowns or {}) do
        if ready <= now then cds[#cds + 1] = { key = "CD", text = ns.CdTask(c, text), cd = text } end
    end
    table.sort(cds, function(a, b) return a.text < b.text end)
    for _, t in ipairs(cds) do add(t.key, t.text, t.cd) end
    if ns.TrainerDue(c) then add("TRAINER", L.TASK_TRAINER) end
    for _, p in ipairs(c.profs or {}) do
        if (p.cap or 0) > 0 and p.cap < 300 and (p.skill or 0) >= p.cap then
            add("PROF", L.TASK_PROF:format(p.name, p.skill, p.cap), nil, p.icon)
        end
    end
    if c.mail then add("MAIL", L.TASK_MAIL) end
    if not c.maxLevel and ns.RestedNow(c, now) >= RESTED_MAX then add("RESTED", L.TASK_RESTED) end
    if (c.durability or 100) < pref("repairAt") then add("REPAIR", L.TASK_REPAIR:format(c.durability)) end
    if (c.free or 99) <= pref("bagsAt") then add("BAGS", L.TASK_BAGS:format(c.free)) end
    return out
end

-- When the next cooldown of a character is ready (nil when none is running).
function ns.NextReady(c, now)
    now = now or time()
    local best
    for _, ready in pairs(c.cooldowns or {}) do
        if ready > now and (not best or ready < best) then best = ready end
    end
    return best
end

-- The region a realm name tells, to show instead of the realm: WoW Forever is realmless, so
-- "CAMWOW EU5 Realm 4 PvP" is just EU. Its region word (EU5, US1, CN2, ...) gives EU, US or CH
-- (China); a realm without one shows as it is.
local REGIONS = { EU = "EU", US = "US", NA = "US", CN = "CH", CH = "CH" }
function ns.Region(realm)
    if type(realm) ~= "string" or realm == "" then return nil end
    for word in realm:gmatch("[%w]+") do
        local r = REGIONS[(word:match("^(%a%a)%d*$") or ""):upper()]
        if r then return r end
    end
    return realm
end

-- Does a character pass the region or faction filter?
function ns.Passes(c, filter)
    filter = filter or pref("filter")
    if filter == "realm" then return c.realm == nil or ns.Region(c.realm) == ns.Region(ns.Realm()) end
    if filter == "faction" then return c.faction == nil or c.faction == faction() end
    return true
end

-- The characters, this one first. Hidden ones (bank alts) come last, and only with all = true.
function ns.Chars(all)
    local me = ns.CharKey()
    local hidden = ns.db.hidden or {}
    local list = {}
    for key, c in pairs(ns.db.chars) do
        if key == me or ((all or not hidden[key]) and ns.Passes(c)) then
            list[#list + 1] = { key = key, char = c, me = key == me, hidden = hidden[key] == true }
        end
    end
    table.sort(list, function(a, b)
        if a.me ~= b.me then return a.me end
        if a.hidden ~= b.hidden then return b.hidden end
        return (a.char.level or 0) > (b.char.level or 0) or ((a.char.level or 0) == (b.char.level or 0) and a.key < b.key)
    end)
    return list
end

-- The overview table: one row per visible character, sorted by a column of ns.COLUMNS.
ns.COLUMNS = { "name", "level", "rested", "money", "durability", "free", "cd", "tasks" }
function ns.Overview(col, desc, now)
    now = now or time()
    local rows = {}
    for _, e in ipairs(ns.Chars()) do
        local c = e.char
        rows[#rows + 1] = { key = e.key, char = c, me = e.me,
            name = c.name or e.key, level = c.level or 0,
            rested = c.maxLevel and -1 or ns.RestedNow(c, now), money = c.money or 0,
            durability = c.durability or 100, free = c.free or 0,
            cd = ns.NextReady(c, now) or math.huge, tasks = #ns.Tasks(c, now) }
        for _, ready in pairs(c.cooldowns or {}) do
            if ready <= now then rows[#rows].cd = 0 end
        end
    end
    col = col or "name"
    table.sort(rows, function(a, b)
        local x, y = a[col], b[col]
        if x == y then return a.key < b.key end
        if desc then return x > y end
        return x < y
    end)
    return rows
end

-- The state colour of an overview cell: "GOOD", "WARN", "BAD", "MUTED" or nil (plain).
-- Gear and bags turn red at the player's own task limits, or below a floor that always warns.
ns.TONE_GEAR_GOOD, ns.TONE_FREE_GOOD, ns.TONE_FREE_BAD = 90, 10, 5
ns.TONE_TASKS_WARN, ns.TONE_TASKS_BAD = 3, 6
function ns.Tone(col, v)
    if col == "durability" then
        if v >= ns.TONE_GEAR_GOOD then return "GOOD" end
        return v < pref("repairAt") and "BAD" or "WARN"
    elseif col == "free" then
        if v > ns.TONE_FREE_GOOD then return "GOOD" end
        return (v < ns.TONE_FREE_BAD or v <= pref("bagsAt")) and "BAD" or "WARN"
    elseif col == "tasks" then
        if v >= ns.TONE_TASKS_BAD then return "BAD" end
        return v >= ns.TONE_TASKS_WARN and "WARN" or nil
    elseif col == "rested" then
        if v >= RESTED_MAX then return "GOOD" end
        return v <= 0 and "MUTED" or nil
    elseif col == "cd" then
        if v == 0 then return "GOOD" end
        return v ~= math.huge and "BAD" or nil
    end
end

-- Money per region of the visible characters: { { realm = region, money } }, the most first.
function ns.RealmGold()
    local by = {}
    for _, e in ipairs(ns.Chars()) do
        local r = ns.Region(e.char.realm or e.key:match("%-(.*)$")) or "?"
        by[r] = (by[r] or 0) + (e.char.money or 0)
    end
    local out = {}
    for r, m in pairs(by) do out[#out + 1] = { realm = r, money = m } end
    table.sort(out, function(a, b) return a.money > b.money end)
    return out
end

function ns.Forget(key)
    ns.db.chars[key] = nil
    if ns.db.hidden then ns.db.hidden[key] = nil end
    if ns.Refresh then ns.Refresh() end
end

function ns.SetHidden(key, hide)
    ns.db.hidden = ns.db.hidden or {}
    ns.db.hidden[key] = hide and true or nil
    if ns.Refresh then ns.Refresh() end
end

function ns.SetNote(key, text)
    local c = ns.db.chars[key]
    if not c then return end
    text = strtrim(text or "")
    c.note = text ~= "" and text:sub(1, 60) or nil
    if ns.Refresh then ns.Refresh() end
end

function ns.SetPref(key, value)
    ns.db[key] = value
    if ns.Refresh then ns.Refresh() end
end

function ns.SetTask(key, value)
    ns.db.off = ns.db.off or {}
    ns.db.off[key] = (not value) and true or nil
    if ns.Refresh then ns.Refresh() end
end
function ns.TaskOn(key) return on(key) end
function ns.Pref(key) return pref(key) end

function ns.Reset()
    for k, v in pairs(ns.DEFAULTS) do ns.db[k] = v end
    ns.db.off, ns.db.hidden = {}, {}
    if ns.Refresh then ns.Refresh() end
end

-- What waits on the other characters: { "Name: task" }, the first task of each.
local function waiting(now)
    local parts = {}
    for _, e in ipairs(ns.Chars()) do
        if not e.me then
            local tasks = ns.Tasks(e.char, now)
            if #tasks > 0 then parts[#parts + 1] = e.char.name .. ": " .. tasks[1].text end
        end
    end
    return parts
end

-- At login: one line about what waits on the other characters.
function ns.LoginSummary()
    if not pref("login") then return nil end
    local parts = waiting()
    if #parts == 0 then return nil end
    local msg = L.LOGIN:format(table.concat(parts, ", "))
    print("|cff9ad0ffGulli Chores|r: " .. msg)
    if GulliToolkit and GulliToolkit.Notify then GulliToolkit.Notify("Chores", msg) end
    return msg
end

-- One line for the hub's home page.
function ns.Summary()
    if not ns.db then return nil end
    local tasks, chars = 0, 0
    for _, e in ipairs(ns.Chars()) do
        local n = #ns.Tasks(e.char)
        if n > 0 then tasks, chars = tasks + n, chars + 1 end
    end
    -- nothing to do: the hub's tile is the first to give way to others
    if tasks == 0 then return L.NOTHING_ALL, nil, { quiet = true } end
    return L.SUMMARY:format(tasks, chars)
end

-- While playing: a cooldown that became ready or rested XP that became full, on any character,
-- is told once (chat and the hub's Recent). quiet only marks what is ready now as told.
function ns.CheckAlerts(now, quiet)
    now = now or time()
    ns.db.alerted = ns.db.alerted or {}
    local told = ns.db.alerted
    local out = {}
    for _, e in ipairs(ns.Chars()) do
        local c = e.char
        for text, ready in pairs(c.cooldowns or {}) do
            local id = e.key .. ":" .. text
            if ready <= now and told[id] ~= ready then
                told[id] = ready
                if on("CD") then out[#out + 1] = L.ALERT:format(c.name, ns.CdTask(c, text)) end
            end
        end
        local id = e.key .. ":RESTED"
        if ns.RestedFullIn(c, now) == 0 then
            if told[id] ~= c.t then
                told[id] = c.t
                if on("RESTED") then out[#out + 1] = L.ALERT:format(c.name, L.TASK_RESTED) end
            end
        end
    end
    table.sort(out)
    if quiet or not pref("alerts") then return {} end
    for _, msg in ipairs(out) do
        print("|cff9ad0ffGulli Chores|r: " .. msg)
        if GulliToolkit and GulliToolkit.Notify then GulliToolkit.Notify("Chores", msg) end
    end
    return out
end

-- Played time without the two lines the game prints in chat for it.
local askedPlayed
function ns.AskPlayed()
    if not RequestTimePlayed or askedPlayed then return end
    askedPlayed = ChatFrame_DisplayTimePlayed or false
    ChatFrame_DisplayTimePlayed = function() end
    RequestTimePlayed()
end
function ns.OnPlayed(total)
    if askedPlayed ~= nil then
        ChatFrame_DisplayTimePlayed = askedPlayed or nil
        askedPlayed = nil
    end
    local c = ns.db.chars[ns.CharKey()]
    if c and tonumber(total) then c.played = tonumber(total) end
end

local pending = false
local function soon()
    if pending then return end
    pending = true
    C_Timer.After(2, function()
        pending = false
        ns.Snapshot()
        if ns.Refresh then ns.Refresh() end
    end)
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1, ...)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliChoresDB = GulliChoresDB or {}
        ns.db = GulliChoresDB
        ns.db.chars = ns.db.chars or {}
        ns.db.off, ns.db.hidden, ns.db.alerted = ns.db.off or {}, ns.db.hidden or {}, ns.db.alerted or {}
        for k, v in pairs(ns.DEFAULTS) do if ns.db[k] == nil then ns.db[k] = v end end
        ns.MergeRealmless()
        ns.FixCooldowns()
        for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT", "TRAINER_SHOW", "PLAYER_LEVEL_UP",
                             "UPDATE_PENDING_MAIL", "MAIL_CLOSED", "BAG_UPDATE_DELAYED", "PLAYER_UPDATE_RESTING",
                             "UPDATE_INVENTORY_DURABILITY", "TRADE_SKILL_CLOSE", "PLAYER_MONEY",
                             "MAIL_INBOX_UPDATE", "BANKFRAME_OPENED", "PLAYERBANKSLOTS_CHANGED",
                             "UPDATE_INSTANCE_INFO", "TIME_PLAYED_MSG", "SKILL_LINES_CHANGED",
                             "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "UNIT_SPELLCAST_SUCCEEDED" }) do
            self:RegisterEvent(e)
        end
        return
    end
    if event == "PLAYER_LOGOUT" then ns.Snapshot(); return end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local spell = select(2, ...)
        if a1 ~= "player" or not ns.OnCast(spell) then return end
    end
    if event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" then ns.ReadTrade() end
    if event == "TIME_PLAYED_MSG" then ns.OnPlayed(a1); return end
    if event == "MAIL_INBOX_UPDATE" then ns.ReadMail(); if ns.Refresh then ns.Refresh() end; return end
    if event == "BANKFRAME_OPENED" or event == "PLAYERBANKSLOTS_CHANGED" then ns.ReadBank(); return end
    if event == "TRAINER_SHOW" then
        local c = ns.db.chars[ns.CharKey()] or ns.Snapshot()
        c.trainer = UnitLevel("player")
    end
    if event == "PLAYER_ENTERING_WORLD" and not ns.greeted then
        ns.greeted = true
        local c = ns.db.chars[ns.CharKey()]
        if not c or not c.trainer then
            -- First time: count the trainer as visited now, so only new levels ask for it.
            ns.Snapshot().trainer = UnitLevel("player")
        end
        ns.LoginSummary()
        -- What is ready at login was just said; the ticker tells only what becomes ready later.
        ns.CheckAlerts(nil, true)
        if RequestRaidInfo then RequestRaidInfo() end
        C_Timer.After(5, function() ns.AskPlayed() end)
        C_Timer.NewTicker(60, function() ns.CheckAlerts() end)
    end
    soon()
end)

SLASH_GULLICHORES1 = "/gch"
SLASH_GULLICHORES2 = "/gullichores"
SlashCmdList.GULLICHORES = function() ns.Toggle() end

function GulliChores_Toggle() ns.Toggle() end

-- The game icon of each switch, in the window and in the hub.
ns.OPT_ICON = {
    login = "Interface\\Icons\\INV_Scroll_03",
    alerts = "Interface\\Icons\\Ability_Warrior_BattleShout",
    EXPIRE = "Interface\\Icons\\INV_Letter_15",
    CD = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    TRAINER = "Interface\\Icons\\INV_Misc_Book_09",
    PROF = "Interface\\Icons\\Trade_Tailoring",
    MAIL = "Interface\\Icons\\INV_Letter_15",
    RESTED = "Interface\\Icons\\Spell_Nature_Sleep",
    REPAIR = "Interface\\Icons\\Trade_BlackSmithing",
    BAGS = "Interface\\Icons\\INV_Misc_Bag_08",
}

local function option(key, task)
    local get = task and function() return ns.db ~= nil and on(key) end
        or function() return ns.db ~= nil and pref(key) == true end
    local set = task and function(v) if ns.db then ns.SetTask(key, v) end end
        or function(v) if ns.db then ns.SetPref(key, v and true or false) end end
    return { label = L["OPT_" .. key:upper()], tip = L["TIP_" .. key:upper()], icon = ns.OPT_ICON[key], get = get, set = set }
end
ns.Option = option

-- With the hub: its row and button there; alone: its own minimap button (Skin.lua).
do
    local register = GulliToolkit and GulliToolkit.Register or function(info) ns.alone = info end
    register({
        key = "Chores",
        icon = "Interface\\AddOns\\Gulli-Chores\\icon",
        slash = "/gch",
        open = function() ns.Toggle() end,
        window = function() return ns.Window and ns.Window() end,
        summary = function() return ns.Summary() end,
        reset = function() ns.Reset() end,
        options = { option("login"), option("alerts"), option("EXPIRE", true), option("RESTED", true) },
    })
end
