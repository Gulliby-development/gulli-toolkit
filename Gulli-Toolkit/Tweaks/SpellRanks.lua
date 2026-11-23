-- New spell ranks on bars: when the player learns a higher rank, every action button that holds
-- a lower rank of the same spell gets the new one. Buttons change only out of combat; a rank
-- learned in a fight waits for its end.

local _, ns = ...

local frame, get
local pending = {}

local function spellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if GetSpellInfo then return (GetSpellInfo(id)) end
end

-- The rank number of a spell ("Rank 3", "Ранг 3"), nil when the client shows none.
local function rankOf(id)
    local sub = C_Spell and C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(id)
    if not sub and GetSpellSubtext then sub = GetSpellSubtext(id) end
    return type(sub) == "string" and tonumber(sub:match("(%d+)")) or nil
end

local function pickup(id)
    if C_Spell and C_Spell.PickupSpell then C_Spell.PickupSpell(id) elseif PickupSpell then PickupSpell(id) end
end

local SLOTS = 180

-- The action slots that hold a lower rank of `id`: same name, another spell, not a higher rank.
function ns.LowerRankSlots(id)
    local name, rank = spellName(id), rankOf(id)
    local out = {}
    if not name or not GetActionInfo then return out end
    for slot = 1, SLOTS do
        local kind, old = GetActionInfo(slot)
        if kind == "spell" and old and old ~= id and spellName(old) == name then
            local r = rankOf(old)
            if not (rank and r and r >= rank) then out[#out + 1] = slot end
        end
    end
    return out
end

local function upgrade(id)
    if InCombatLockdown and InCombatLockdown() then pending[id] = true; return 0 end
    if GetCursorInfo and GetCursorInfo() then pending[id] = true; return 0 end
    local slots = ns.LowerRankSlots(id)
    for _, slot in ipairs(slots) do
        pickup(id)
        if PlaceAction then PlaceAction(slot) end
        if ClearCursor then ClearCursor() end
    end
    if #slots > 0 and get and get("chat") and DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(ns.L.TW_RANKS_DONE:format(spellName(id) or "?", #slots))
    end
    return #slots
end
ns.UpgradeRank = upgrade

local function onEvent(_, event, id)
    if event == "PLAYER_REGEN_ENABLED" then
        local list = pending
        pending = {}
        for spell in pairs(list) do upgrade(spell) end
    elseif type(id) == "number" then
        upgrade(id)
    end
end
ns.SpellRanksEvent = onEvent

ns.AddTweak({
    key = "spellRanks", group = "level", icon = "Interface\\Icons\\Spell_Fire_FlameBolt", star = true,
    defaults = { chat = true },
    panel = {
        { kind = "switch", key = "chat", label = ns.L.TWP_RANKS_CHAT },
    },
    enable = function(g)
        get = g
        frame = frame or CreateFrame("Frame")
        frame:SetScript("OnEvent", onEvent)
        ns.TweakListen(frame, "LEARNED_SPELL_IN_SKILL_LINE")
        ns.TweakListen(frame, "LEARNED_SPELL_IN_TAB")
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    end,
    disable = function()
        if frame then frame:UnregisterAllEvents() end
        pending = {}
    end,
    changed = function(_, _, g) get = g end,
})
