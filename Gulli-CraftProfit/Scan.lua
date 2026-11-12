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
    ns.Recalc(false)
    if ns.Refresh then ns.Refresh() end
end

local function itemFor(state, id)
    if state.items[id] then return end
    local sell, bind, quality = itemInfo(id)
    local ah, age = ns.AuctionPrice(id)
    local bags = count(id)
    local bank = math.max(0, count(id, true) - bags)
    state.items[id] = { name = itemName(id) or ("#" .. id), vend = sell, bop = bind == 1, quality = quality,
                        ah = ah, age = age, buy = ns.db.vendor[id], bags = bags, bank = bank }
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
        local skill = ns.Estimate(rec.obs, rec.grey)
        local src
        if not rec.learned then
            local cost = rec.name and ns.db.trainer[rec.name]
            if cost then src = { t = "trainer", cost = cost } else src = { t = "text", text = rec.source } end
        end
        state.recipes[rid] = { name = rec.name or tostring(rid), skill = skill, guess = true, r = rec.r or {},
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
        GulliCraftProfitCharDB = GulliCraftProfitCharDB or {}
        ns.char = GulliCraftProfitCharDB
        ns.char.profs = ns.char.profs or {}
        for name, p in pairs(ns.char.profs) do if empty(p) then ns.char.profs[name] = nil end end
        for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_UPDATE",
                             "MERCHANT_SHOW", "TRAINER_SHOW", "BAG_UPDATE_DELAYED" }) do
            self:RegisterEvent(e)
        end
        local api = auctionator()
        if api and api.RegisterForDBUpdate then
            pcall(api.RegisterForDBUpdate, CALLER, function() if ns.Visible and ns.Visible() then ns.Recalc(false); ns.Refresh() end end)
        end
        return
    end
    if event == "MERCHANT_SHOW" then learnVendor(); return end
    if event == "TRAINER_SHOW" then learnTrainer(); return end
    if pending then return end
    pending = true
    C_Timer.After(0.5, function()
        pending = false
        if event ~= "BAG_UPDATE_DELAYED" then
            local name = ns.ScanProfession()
            if name and event == "TRADE_SKILL_SHOW" then ns.char.current = name end
        end
        if ns.Visible and ns.Visible() then ns.Recalc(false); ns.Refresh() end
    end)
end)
