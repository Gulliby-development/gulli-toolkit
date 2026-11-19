-- Reads the game for Core.lua: the profession window (recipes, reagents, colours), bags and
-- bank, vendor sell prices, Auctionator prices, and the prices seen at vendors and trainers.
-- Every game call goes through a small wrapper with a fallback to the old global API.

local ADDON, ns = ...

local CALLER = "Gulli-CraftProfit"
local OBS_MAX = 8 -- colours kept per recipe, newest skills first

-- Trade supplies every trade vendor sells without a limit. Their price is known before the
-- player ever saw one at a vendor: a vendor asks four times what it pays (an estimate until seen).
-- Only items that are never in limited supply belong here.
ns.VENDOR_ITEMS = {}
for _, id in ipairs({
    2320, 2321, 4291, 8343, 14341,                              -- threads
    2324, 2325, 2604, 2605, 4340, 4341, 4342, 6260, 6261, 10290, -- bleach and dyes
    4289, 2880, 3466, 3857, 18567,                              -- salt, fluxes, coal
    3371, 3372, 8925, 18256,                                    -- vials
    2678, 2692, 3713, 2665, 159, 1179, 2596, 2594, 2894, 4536,  -- cooking supplies
    4399, 4400, 4470, 6217, 11291, 10647, 10648, 6530,          -- stocks, wood, rod, ink, parchment, bait
}) do ns.VENDOR_ITEMS[id] = true end

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

-- Auctionator's price (copper) and its age in days, or nil without Auctionator.
local function auctionator()
    return Auctionator and Auctionator.API and Auctionator.API.v1
end
function ns.AuctionPrice(id)
    local api = auctionator()
    if not api or not api.GetAuctionPriceByItemID then return nil end
    local ok, price = pcall(api.GetAuctionPriceByItemID, CALLER, id)
    if not ok or not price or price <= 0 then return nil end
    local age = 0
    if api.GetAuctionAgeByItemID then
        local ok2, a = pcall(api.GetAuctionAgeByItemID, CALLER, id)
        if ok2 and a then age = a end
    end
    return price, age
end
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

-- The modern API: every recipe of the profession, learned or not.
local function scanModern(prof, skill)
    local T = C_TradeSkillUI
    local ids = T.GetAllRecipeIDs() or {}
    local n = 0
    for _, rid in ipairs(ids) do
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
            prof.recipes[key] = rec
            n = n + 1
        end
    end
    return n
end

-- Saves the open profession for this character. Returns its name and the recipe count.
function ns.ScanProfession()
    local name, skill, cap = professionLine()
    if not name then return nil, 0 end
    local db = charDB()
    db.profs[name] = db.profs[name] or { recipes = {} }
    local prof = db.profs[name]
    prof.skill, prof.cap, prof.seen = skill, cap, time()
    prof.icon = professionIcon(name) or prof.icon
    local n
    if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs then n = scanModern(prof, skill)
    elseif GetNumTradeSkills then n = scanClassic(prof, skill)
    else n = 0 end
    db.current = db.current or name
    return name, n
end

-- ---------- the state for Core.lua ----------

function ns.Professions()
    local out = {}
    for name, p in pairs(charDB().profs) do if not empty(p) then out[#out + 1] = { name = name, skill = p.skill or 0, cap = p.cap or 0, icon = p.icon } end end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

function ns.SetProfession(name)
    if not charDB().profs[name] then return end
    charDB().current = name
    ns.Rebuild(false, "pick")
end

local function itemFor(state, id)
    if state.items[id] then return end
    local sell, bind, quality = itemInfo(id)
    local ah, age = ns.AuctionPrice(id)
    local bags = count(id)
    local bank = math.max(0, count(id, true) - bags)
    local alts, who = ns.AltCount(id)
    local buy = ns.db.vendor[id] or (ns.VENDOR_ITEMS[id] and sell > 0 and sell * 4) or nil
    state.items[id] = { name = nameFor(id), vend = sell, bop = bind == 1, quality = quality,
                        ah = ah, age = age, buy = buy, buyEst = not ns.db.vendor[id] and buy ~= nil or nil, bags = bags, bank = bank,
                        mail = ns.char.mail and ns.char.mail[id] or 0, alts = alts, altWho = who,
                        gather = ns.db.gather[id] == true, lots = ns.db.lots[id] }
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
    local me = (UnitName("player") or "") .. "-" .. (GetRealmName and GetRealmName() or "")
    local n, who, most = 0, nil, 0
    for key, c in pairs(db.chars) do
        if key ~= me and type(c) == "table" then
            local k = (c.items and c.items[id] or 0) + (c.bank and c.bank[id] or 0)
            n = n + k
            if k > most then who, most = c.name or key, k end
        end
    end
    return n, who
end

-- Marks an item the player gathers (herbs, ore, skins): the plan never buys it.
function ns.SetGather(id, on)
    if not id then return end
    ns.db.gather[id] = on and true or nil
    ns.Rebuild(true)
end

-- Takes a craft out of every route (learned, from a trainer or from a pattern alike), or puts it
-- back. Saved by recipe for every character.
function ns.SetSkip(rid, on)
    if not rid then return end
    ns.db.skip = ns.db.skip or {}
    ns.db.skip[rid] = on and true or nil
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

-- The character's standing (1 Hated .. 8 Exalted) with a faction by name, or 0 when the list lacks it.
local function standingOf(name)
    local R = C_Reputation
    if R and R.GetNumFactions and R.GetFactionDataByIndex then
        for i = 1, R.GetNumFactions() or 0 do
            local d = R.GetFactionDataByIndex(i)
            if d and d.name == name then return d.reaction or 0 end
        end
    elseif GetNumFactions and GetFactionInfo then
        for i = 1, GetNumFactions() or 0 do
            local n, _, s = GetFactionInfo(i)
            if n == name then return s or 0 end
        end
    end
    return 0
end

-- Whether a pattern asks for a reputation the character does not have, and the tooltip line that
-- says so. The game paints that line red when it is not met; without a colour, the standing from
-- the reputation list decides. An item the client has not loaded yet counts as no requirement.
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
                local err = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.ErrorLine
                if err and line.type == err then return true, text end
                local c = line.leftColor
                if type(c) == "table" and type(c.r) == "number" then
                    return c.r > 0.9 and c.g < 0.3 and c.b < 0.3, text
                end
                local need = standingId(label)
                return need ~= nil and standingOf(fac) < need, text
            end
        end
    end
    return false
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
    if cost then return { t = "trainer", cost = cost, est = false } end
    local train = ns.Data and ns.Data.train and rid ~= rec.out and ns.Data.train[rid]
    if train then return { t = "trainer", cost = train, est = false } end
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
            src = { t = "vendor", cost = seen or ((it.vend or 0) > 0 and it.vend * 4 or nil), est = not seen, who = #who > 0 and who or nil }
        end
        if it.ah and (not src or not src.cost or it.ah < src.cost) then src = { t = "ah", cost = it.ah } end
        src = src or { t = d[1] == "q" and "quest" or "drop" }
        src.item, src.text = item, rec.source
        -- a pattern this character cannot learn yet for want of reputation is no way to get it
        local missing, line = ns.RepMissing(item)
        if missing then src = { t = "rep", item = item, text = line } end
        return src
    end
    if ns.Data and ns.Data.spell and rid ~= rec.out and ns.Data.spell[rid] then
        return { t = "trainer", cost = ns.TrainerGuess(skill and skill[1]), est = true }
    end
    return { t = "text", text = rec.source }
end

-- The profession the window shows and its saved data; nil before any scan.
local function current()
    local db = charDB()
    local name = db.current
    local prof = name and db.profs[name]
    if not prof or empty(prof) then
        name, prof = nil, nil
        for n, p in pairs(db.profs) do
            if not empty(p) and (not name or n < name) then name, prof = n, p end
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
    return { name = name, skill = prof.skill or 0, cap = prof.cap or 0, level = UnitLevel("player") or 0,
             icon = prof.icon, items = {}, recipes = {} }
end

-- The profession the window shows, as a plain table for Core.lua; nil before any scan.
-- It reads counts and prices of every item, so it runs only in a calculation (ns.Tick).
function ns.State()
    local name, prof = current()
    if not name then return nil end
    local state = ns.Skill()
    local gone = ns.Data and ns.Data.gone or {}
    for rid, rec in pairs(prof.recipes) do
        ns.Tick()
        -- a recipe the client lists but WoW Forever does not give (Season of Discovery, closed raids)
        if rec.learned or not gone[rid] then
            local skill, guess = ns.Thresholds(levels(rid, rec), rec.obs, rec.grey, rec.learned)
            local src = not rec.learned and recipeSource(state, rid, rec, skill) or nil
            state.recipes[rid] = { name = rec.name or tostring(rid), skill = skill, guess = guess, r = rec.r or {},
                                   out = rec.out, count = rec.count, learned = rec.learned, src = src, icon = rec.icon,
                                   skip = ns.db.skip and ns.db.skip[rid] == true or nil }
            for id in pairs(rec.r or {}) do itemFor(state, id) end
            if rec.out then itemFor(state, rec.out) end
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
    end
end

-- ---------- /gcp probe ----------

-- What this client offers, for the first try in WoW Forever.
function ns.Probe()
    local T = C_TradeSkillUI
    local lines = {}
    local function yes(v) return v and "yes" or "no" end
    lines[#lines + 1] = "Auctionator API v1: " .. yes(auctionator())
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
    for _, e in ipairs(ns.Shopping(route)) do if e.id then scan.queue[#scan.queue + 1] = e.id end end
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
    if not v.route or not v.state or (v.leg or 1) > 1 then return {} end
    return ns.Progress(v.route, v.state, count)
end

-- ---------- buying at the auction house ----------

-- The game lets an addon buy only inside a click, and both steps are protected: asking the
-- price (StartCommoditiesPurchase) and buying (ConfirmCommoditiesPurchase). So each line takes
-- two clicks of the stop's button; nothing here runs from an event or a timer.
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
    return ns.Dear(b.quote.unit, line.unit, ns.Prefs(ns.db and ns.db.prefs).guard)
end

local function nextLine()
    local b = ns.buy
    b.i, b.quote = b.i + 1, nil
    b.phase = ns.BuyLine() and "idle" or "done"
end

-- Not sold as a commodity (gear, a pattern): the button cannot buy it.
local function byHand(id)
    local a = AH()
    if not a or not a.GetItemCommodityStatus then return false end
    local ok, status = pcall(a.GetItemCommodityStatus, id)
    return ok and status == 1
end

local function ask()
    local b, line = ns.buy, ns.BuyLine()
    if not line then b.phase = "done"; return end
    if byHand(line.id) then
        line.hand = true
        b.byHand = b.byHand + 1
        nextLine()
        b.err = "BUY_ERR_HAND"
        return
    end
    b.phase, b.quote, b.err = "quote", nil, nil
    local ok = pcall(AH().StartCommoditiesPurchase, line.id, line.n)
    if not ok then b.phase, b.err = "idle", "BUY_ERR_START"; return end
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
        local ok = pcall(AH().ConfirmCommoditiesPurchase, line.id, line.n)
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
            line.done = true
            nextLine()
        end
    elseif event == "COMMODITY_PURCHASE_FAILED" then
        if b.phase == "buying" then b.phase, b.err = "idle", "BUY_ERR_BUY" end
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
    for _, e in ipairs(plan.buys) do
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
function ns.OpenRecipe(rid)
    local rec = ns.char.profs[ns.char.current or ""] and ns.char.profs[ns.char.current].recipes[rid]
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
    local rec = ns.char.profs[ns.char.current or ""] and ns.char.profs[ns.char.current].recipes[rid]
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

-- ---------- the run log ----------

function ns.StartRun()
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

local pending = false
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1, a2)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliCraftProfitDB = GulliCraftProfitDB or {}
        ns.db = GulliCraftProfitDB
        ns.db.prefs = ns.db.prefs or {}
        ns.db.vendor = ns.db.vendor or {}
        ns.db.trainer = ns.db.trainer or {}
        ns.db.gather = ns.db.gather or {}
        ns.db.skip = ns.db.skip or {}
        ns.db.lots = ns.db.lots or {}
        GulliCraftProfitCharDB = GulliCraftProfitCharDB or {}
        ns.char = GulliCraftProfitCharDB
        ns.char.profs = ns.char.profs or {}
        ns.char.log = ns.char.log or {}
        for name, p in pairs(ns.char.profs) do if empty(p) then ns.char.profs[name] = nil end end
        ns.Listen(self, { "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_UPDATE",
                          "MERCHANT_SHOW", "TRAINER_SHOW", "BAG_UPDATE_DELAYED", "MAIL_INBOX_UPDATE",
                          "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "COMMODITY_SEARCH_RESULTS_UPDATED",
                          "AUCTION_ITEM_LIST_UPDATE", "MERCHANT_CLOSED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
                          "MAIL_SHOW", "MAIL_CLOSED", "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE",
                          "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED", "GET_ITEM_INFO_RECEIVED" })
        local api = auctionator()
        if api and api.RegisterForDBUpdate then
            pcall(api.RegisterForDBUpdate, CALLER, function() ns.Rebuild(false, "event") end)
        end
        return
    end
    if next(ns.nameWaiting) then ns.CheckNames() end
    if event == "GET_ITEM_INFO_RECEIVED" then return end
    if event == "MERCHANT_SHOW" then learnVendor(); ns.atVendor = true; ns.Arrive("vendor"); return end
    if event == "MERCHANT_CLOSED" then ns.atVendor = false; ns.Arrive(nil); return end
    if event == "BANKFRAME_OPENED" then ns.atBank = true; ns.Arrive("bank"); return end
    if event == "BANKFRAME_CLOSED" then ns.atBank = false; ns.Arrive(nil); return end
    if event == "MAIL_SHOW" then ns.atMail = true; ns.Arrive("mail"); return end
    if event == "MAIL_CLOSED" then ns.atMail = false; ns.Arrive(nil); return end
    if event == "TRAINER_SHOW" then learnTrainer(); return end
    if event == "MAIL_INBOX_UPDATE" then snapshotMail(); return end
    if event == "AUCTION_HOUSE_SHOW" then ns.atAH = true; ns.Arrive("ah"); return end
    if event == "AUCTION_HOUSE_CLOSED" then
        cancelQuote()
        if ns.buy.phase ~= "done" then ns.buy.phase, ns.buy.quote = "idle", nil end
        ns.atAH, scan.queue, scan.busy = false, {}, nil
        ns.Arrive(nil)
        return
    end
    if event:sub(1, 10) == "COMMODITY_" and event ~= "COMMODITY_SEARCH_RESULTS_UPDATED" then ns.OnBuy(event, a1, a2); return end
    if event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "AUCTION_ITEM_LIST_UPDATE" then ns.OnLots(); return end
    -- the run's progress follows the bags at once; the plan itself only goes stale
    if event == "BAG_UPDATE_DELAYED" and ns.Refresh then ns.Refresh() end
    if pending then return end
    pending = true
    C_Timer.After(0.5, function()
        pending = false
        if event ~= "BAG_UPDATE_DELAYED" then
            local name = ns.ScanProfession()
            if name and event == "TRADE_SKILL_SHOW" then ns.char.current = name end
        end
        ns.Rebuild(false, "event")
    end)
end)
