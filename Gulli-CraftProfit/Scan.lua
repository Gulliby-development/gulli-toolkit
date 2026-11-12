-- Reads the game for Core.lua: the profession window (recipes, reagents, colours), bags and
-- bank, vendor sell prices, Auctionator prices, and the prices seen at vendors and trainers.
-- Every game call goes through a small wrapper with a fallback to the old global API.

local ADDON, ns = ...

local CALLER = "Gulli-CraftProfit"
local OBS_MAX = 8 -- colours kept per recipe, newest skills first

-- ---------- wrappers ----------

local function itemName(id)
    local n = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    if not n and GetItemInfo then n = GetItemInfo(id) end
    return n
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
    state.items[id] = { name = itemName(id) or ("#" .. id), vend = sell, bop = bind == 1, quality = quality,
                        ah = ah, age = age, buy = ns.db.vendor[id], bags = bags, bank = bank,
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

-- Where a recipe not learned yet comes from, and its price. Data.lua names the pattern and its
-- vendors; a pattern sells to a vendor for a quarter of what the vendor asks, so the price is
-- four times its sell price until the vendor was seen. A pattern on the auction costs its
-- Auctionator price. A recipe with no pattern comes from the trainer, whose price is known
-- once the trainer window was open.
local function recipeSource(state, rid, rec)
    local D = ns.Data and ns.Data.src
    local d = D and rid ~= rec.out and D[rid]
    if d then
        local item = d[2]
        itemFor(state, item)
        local it = state.items[item]
        local fac = (UnitFactionGroup and UnitFactionGroup("player")) == "Horde" and "H" or "A"
        local who = {}
        for i = 3, #d do
            local name, f = d[i]:match("^(.-)|(%a+)$")
            if name and f:find(fac, 1, true) then who[#who + 1] = name end
        end
        local src
        if d[1] == "v" and #who > 0 then
            local seen = ns.db.vendor[item]
            src = { t = "vendor", cost = seen or ((it.vend or 0) > 0 and it.vend * 4 or nil), est = not seen, who = who }
        end
        if it.ah and (not src or not src.cost or it.ah < src.cost) then src = { t = "ah", cost = it.ah } end
        src = src or { t = d[1] == "q" and "quest" or "drop" }
        src.item, src.text = item, rec.source
        return src
    end
    local cost = rec.name and ns.db.trainer[rec.name]
    if cost then return { t = "trainer", cost = cost } end
    if ns.Data and ns.Data.spell and rid ~= rec.out and ns.Data.spell[rid] then return { t = "trainer" } end
    return { t = "text", text = rec.source }
end

-- The profession the window shows, as a plain table for Core.lua; nil before any scan.
function ns.State()
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
    local state = { name = name, skill = prof.skill or 0, cap = prof.cap or 0, level = UnitLevel("player") or 0,
                    icon = prof.icon, items = {}, recipes = {} }
    for rid, rec in pairs(prof.recipes) do
        local skill, guess = ns.Thresholds(levels(rid, rec), rec.obs, rec.grey, rec.learned)
        local src = not rec.learned and recipeSource(state, rid, rec) or nil
        state.recipes[rid] = { name = rec.name or tostring(rid), skill = skill, guess = guess, r = rec.r or {},
                               out = rec.out, count = rec.count, learned = rec.learned, src = src, icon = rec.icon }
        for id in pairs(rec.r or {}) do itemFor(state, id) end
        if rec.out then itemFor(state, rec.out) end
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

local function learnVendor()
    for i = 1, (GetMerchantNumItems and GetMerchantNumItems() or 0) do
        local id = GetMerchantItemID and GetMerchantItemID(i)
        local _, _, price, stack, _, _, _, extended = GetMerchantItemInfo(i)
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
    elseif GetNumAuctionItems then
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

local pending = false
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliCraftProfitDB = GulliCraftProfitDB or {}
        ns.db = GulliCraftProfitDB
        ns.db.prefs = ns.db.prefs or {}
        ns.db.vendor = ns.db.vendor or {}
        ns.db.trainer = ns.db.trainer or {}
        ns.db.gather = ns.db.gather or {}
        ns.db.lots = ns.db.lots or {}
        GulliCraftProfitCharDB = GulliCraftProfitCharDB or {}
        ns.char = GulliCraftProfitCharDB
        ns.char.profs = ns.char.profs or {}
        ns.char.log = ns.char.log or {}
        for name, p in pairs(ns.char.profs) do if empty(p) then ns.char.profs[name] = nil end end
        for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_UPDATE",
                             "MERCHANT_SHOW", "TRAINER_SHOW", "BAG_UPDATE_DELAYED", "MAIL_INBOX_UPDATE",
                             "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "COMMODITY_SEARCH_RESULTS_UPDATED",
                             "AUCTION_ITEM_LIST_UPDATE" }) do
            self:RegisterEvent(e)
        end
        local api = auctionator()
        if api and api.RegisterForDBUpdate then
            pcall(api.RegisterForDBUpdate, CALLER, function() ns.Rebuild(false, "event") end)
        end
        return
    end
    if event == "MERCHANT_SHOW" then learnVendor(); return end
    if event == "TRAINER_SHOW" then learnTrainer(); return end
    if event == "MAIL_INBOX_UPDATE" then snapshotMail(); return end
    if event == "AUCTION_HOUSE_SHOW" then ns.atAH = true; if ns.Refresh then ns.Refresh() end return end
    if event == "AUCTION_HOUSE_CLOSED" then
        ns.atAH, scan.queue, scan.busy = false, {}, nil
        if ns.Refresh then ns.Refresh() end
        return
    end
    if event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "AUCTION_ITEM_LIST_UPDATE" then ns.OnLots(); return end
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
