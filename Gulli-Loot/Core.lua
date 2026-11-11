-- Group loot rolls by the player's rules: one rule per quality (gray, white, green) and one
-- per item. Bind-on-pickup items and items without a rule stay with the player, and so do
-- protected items (Gulli Toolkit) unless their own rule says otherwise.

local ADDON, ns = ...
local L = ns.L

ns.ROLL = { pass = 0, need = 1, greed = 2 }
ns.RULES = { "ask", "greed", "pass" } -- for a quality; an item may also say "need"
ns.ITEM_RULES = { "need", "greed", "pass" }
ns.QUALITIES = { 0, 1, 2 }

local function protected(id)
    return GulliToolkit and GulliToolkit.IsProtected and GulliToolkit.IsProtected(id) or false
end
local function say(msg) print("|cff9ad0ffGulli Loot|r: " .. msg) end

-- The rule for a roll: "need", "greed", "pass" or nil to leave it to the player.
function ns.Decide(id, quality, bop, canNeed, canGreed)
    local rule = id and ns.db.items[id]
    if not rule then
        if bop or (id and protected(id)) then return nil end
        rule = ns.db.quality[quality]
        if not rule or rule == "ask" then return nil end
    end
    if rule == "need" and not canNeed then rule = "greed" end
    if rule == "greed" and not canGreed then return nil end
    return rule
end

local pending = {}

function ns.OnRoll(rollID)
    local _, name, _, quality, bop, canNeed, canGreed = GetLootRollItemInfo(rollID)
    local link = GetLootRollItemLink(rollID)
    local id = link and tonumber(link:match("item:(%d+)"))
    local rule = ns.Decide(id, quality, bop, canNeed, canGreed)
    if not rule then return nil end
    pending[rollID] = ns.ROLL[rule]
    RollOnLoot(rollID, ns.ROLL[rule])
    if ns.db.report then say(L.ROLLED:format(L["RULE_" .. rule:upper()], link or name or "?")) end
    return rule
end

-- The game asks to confirm a roll on a bind-on-pickup item; only rolls we made are confirmed.
function ns.OnConfirm(rollID, rollType)
    if pending[rollID] ~= nil and pending[rollID] == rollType then
        pending[rollID] = nil
        ConfirmLootRoll(rollID, rollType)
        if StaticPopup_Hide then StaticPopup_Hide("CONFIRM_LOOT_ROLL") end
        return true
    end
    return false
end

function ns.SetItem(id, rule)
    ns.db.items[id] = rule
    if ns.Refresh then ns.Refresh() end
end

-- The item rules as a sorted list: { { id, rule } }.
function ns.Items()
    local out = {}
    for id, rule in pairs(ns.db.items) do out[#out + 1] = { id = id, rule = rule } end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1, a2)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliLootDB = GulliLootDB or {}
        ns.db = GulliLootDB
        ns.db.quality = ns.db.quality or { [0] = "pass", [1] = "ask", [2] = "ask" }
        ns.db.items = ns.db.items or {}
        if ns.db.report == nil then ns.db.report = true end
        self:RegisterEvent("START_LOOT_ROLL")
        self:RegisterEvent("CONFIRM_LOOT_ROLL")
        return
    end
    if event == "START_LOOT_ROLL" then ns.OnRoll(a1)
    elseif event == "CONFIRM_LOOT_ROLL" then ns.OnConfirm(a1, a2) end
end)

SLASH_GULLILOOT1 = "/glt"
SLASH_GULLILOOT2 = "/gulliloot"
SlashCmdList.GULLILOOT = function() ns.Toggle() end

function GulliLoot_Toggle() ns.Toggle() end

if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({
        key = "Loot",
        icon = "Interface\\AddOns\\Gulli-Loot\\icon",
        slash = "/glt",
        open = function() ns.Toggle() end,
    })
end
