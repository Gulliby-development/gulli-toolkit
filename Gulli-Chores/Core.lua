-- A to-do list for every character. Each character saves a snapshot when it plays; the list
-- works out what is waiting now: rested XP, mail, bag space, repairs, crafting cooldowns
-- and new spells at the trainer.

local ADDON, ns = ...
local L = ns.L

-- Crafting cooldowns worth coming back for: spell id -> text key. One shared cooldown for
-- the transmutes, so one key is enough.
ns.COOLDOWNS = {
    [17187] = "CD_TRANSMUTE", [11479] = "CD_TRANSMUTE", [11480] = "CD_TRANSMUTE", [17559] = "CD_TRANSMUTE",
    [17560] = "CD_TRANSMUTE", [17561] = "CD_TRANSMUTE", [17562] = "CD_TRANSMUTE", [17563] = "CD_TRANSMUTE",
    [17564] = "CD_TRANSMUTE", [17565] = "CD_TRANSMUTE", [17566] = "CD_TRANSMUTE", [25146] = "CD_TRANSMUTE",
    [18560] = "CD_MOONCLOTH",
}
ns.ITEM_COOLDOWNS = { [15846] = "CD_SALT" } -- Salt Shaker

local RESTED_PER_8H = 0.05 -- of a level, in an inn; a quarter of it outside
local RESTED_MAX = 1.5

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
    local start, duration = ((C_Container and C_Container.GetItemCooldown) or GetItemCooldown)(id)
    return start or 0, duration or 0
end
local function itemCount(id)
    return ((C_Item and C_Item.GetItemCount) or GetItemCount)(id) or 0
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

function ns.CharKey()
    return UnitName("player") .. "-" .. (GetRealmName() or "")
end

-- Takes this character's snapshot.
function ns.Snapshot()
    local key = ns.CharKey()
    local old = ns.db.chars[key] or {}
    local _, class = UnitClass("player")
    local c = { name = UnitName("player"), class = class, level = UnitLevel("player"), t = time(),
                trainer = old.trainer, money = GetMoney and GetMoney() or 0 }
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
    -- Cooldowns as real time, so they can be checked from another character.
    c.cooldowns = {}
    local now, clock = time(), GetTime()
    for spell, text in pairs(ns.COOLDOWNS) do
        if knows(spell) then
            local start, duration = spellCooldown(spell)
            if not secret(start) and not secret(duration) then
                local left = (start > 0 and duration > 1.5) and (start + duration - clock) or 0
                local ready = now + math.max(0, math.floor(left))
                if not c.cooldowns[text] or ready < c.cooldowns[text] then c.cooldowns[text] = ready end
            end
        end
    end
    for item, text in pairs(ns.ITEM_COOLDOWNS) do
        if itemCount(item) > 0 then
            local start, duration = itemCooldown(item)
            local left = (start > 0 and duration > 1.5) and (start + duration - clock) or 0
            c.cooldowns[text] = now + math.max(0, math.floor(left))
        end
    end
    ns.db.chars[key] = c
    return c
end

-- A short time span: "3 d", "5 h", "12 min".
function ns.Span(sec)
    sec = math.max(0, math.floor(sec))
    if sec >= 86400 then return L.DAYS:format(math.floor(sec / 86400)) end
    if sec >= 3600 then return L.HOURS:format(math.floor(sec / 3600)) end
    return L.MINUTES:format(math.max(1, math.floor(sec / 60)))
end

-- Rested XP now, as a share of a level, counting the time since the snapshot.
function ns.RestedNow(c, now)
    local hours = math.max(0, (now or time()) - c.t) / 3600
    local rate = RESTED_PER_8H / 8 * (c.resting and 1 or 0.25)
    return math.min(RESTED_MAX, (c.rested or 0) + hours * rate)
end

-- What is waiting for a character: { { key, text, cd } }, the most useful first; cd is the
-- cooldown's text key.
function ns.Tasks(c, now)
    now = now or time()
    local out = {}
    local function add(key, text, cd) out[#out + 1] = { key = key, text = text, cd = cd } end
    for text, ready in pairs(c.cooldowns or {}) do
        if ready <= now then add("CD", L[text], text) end
    end
    table.sort(out, function(a, b) return a.text < b.text end)
    if c.trainer and c.level > c.trainer then add("TRAINER", L.TASK_TRAINER) end
    if c.mail then add("MAIL", L.TASK_MAIL) end
    if not c.maxLevel and ns.RestedNow(c, now) >= RESTED_MAX then add("RESTED", L.TASK_RESTED) end
    if (c.durability or 100) < 30 then add("REPAIR", L.TASK_REPAIR:format(c.durability)) end
    if (c.free or 99) <= 2 then add("BAGS", L.TASK_BAGS:format(c.free)) end
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

function ns.Chars()
    local me = ns.CharKey()
    local list = {}
    for key, c in pairs(ns.db.chars) do list[#list + 1] = { key = key, char = c, me = key == me } end
    table.sort(list, function(a, b)
        if a.me ~= b.me then return a.me end
        return (a.char.level or 0) > (b.char.level or 0) or ((a.char.level or 0) == (b.char.level or 0) and a.key < b.key)
    end)
    return list
end

function ns.Forget(key)
    ns.db.chars[key] = nil
    if ns.Refresh then ns.Refresh() end
end

-- At login: one line about what waits on the other characters.
function ns.LoginSummary()
    local parts = {}
    for _, e in ipairs(ns.Chars()) do
        if not e.me then
            local tasks = ns.Tasks(e.char)
            if #tasks > 0 then parts[#parts + 1] = e.char.name .. ": " .. tasks[1].text end
        end
    end
    if #parts == 0 then return nil end
    local msg = L.LOGIN:format(table.concat(parts, ", "))
    print("|cff9ad0ffGulli Chores|r: " .. msg)
    if GulliToolkit and GulliToolkit.Notify then GulliToolkit.Notify("Chores", msg) end
    return msg
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
f:SetScript("OnEvent", function(self, event, a1)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliChoresDB = GulliChoresDB or {}
        ns.db = GulliChoresDB
        ns.db.chars = ns.db.chars or {}
        for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT", "TRAINER_SHOW", "PLAYER_LEVEL_UP",
                             "UPDATE_PENDING_MAIL", "MAIL_CLOSED", "BAG_UPDATE_DELAYED", "PLAYER_UPDATE_RESTING",
                             "UPDATE_INVENTORY_DURABILITY", "TRADE_SKILL_CLOSE", "PLAYER_MONEY" }) do
            self:RegisterEvent(e)
        end
        return
    end
    if event == "PLAYER_LOGOUT" then ns.Snapshot(); return end
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
    end
    soon()
end)

SLASH_GULLICHORES1 = "/gch"
SLASH_GULLICHORES2 = "/gullichores"
SlashCmdList.GULLICHORES = function() ns.Toggle() end

function GulliChores_Toggle() ns.Toggle() end

if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({
        key = "Chores",
        icon = "Interface\\AddOns\\Gulli-Chores\\icon",
        slash = "/gch",
        open = function() ns.Toggle() end,
    })
end
