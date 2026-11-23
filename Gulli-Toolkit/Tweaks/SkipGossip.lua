-- Skip NPC talk: an NPC whose talk leads to one service the player ticked (the flight map, the
-- shop, the bank, ...) opens it at once. An NPC with quests, or with two such services, keeps its
-- talk, and Shift shows it once.

local _, ns = ...

local frame, get

-- The gossip icon of each service (file ids of the retail client, then the classic paths).
ns.GOSSIP_KINDS = {
    taxi = { 132057, "taxigossipicon" },
    vendor = { 132060, "vendorgossipicon" },
    banker = { 132050, "bankergossipicon" },
    trainer = { 132058, "trainergossipicon" },
    binder = { 132052, "bindergossipicon" },
}
ns.GOSSIP_ORDER = { "taxi", "vendor", "banker", "trainer", "binder" }

local function kindOf(o)
    if type(o.type) == "string" and ns.GOSSIP_KINDS[o.type:lower()] then return o.type:lower() end
    local icon = o.icon
    for k, v in pairs(ns.GOSSIP_KINDS) do
        if icon == v[1] then return k end
        if type(icon) == "string" and icon:lower():find(v[2], 1, true) then return k end
    end
end

local function count(f)
    if not f then return 0 end
    local ok, n = pcall(f)
    if not ok then return 0 end
    if type(n) == "table" then return #n end
    return tonumber(n) or 0
end

-- The option to pick for these options, or nil: exactly one ticked service and no quests.
function ns.GossipPick(options, g)
    local pick
    for _, o in ipairs(options or {}) do
        local k = kindOf(o)
        if k and g(k) then
            if pick then return nil end
            pick = o
        end
    end
    return pick
end

local function onEvent()
    if not get or ns.TweakSkip() or not C_GossipInfo or not C_GossipInfo.GetOptions then return end
    if count(C_GossipInfo.GetNumAvailableQuests) > 0 or count(C_GossipInfo.GetNumActiveQuests) > 0 then return end
    local ok, options = pcall(C_GossipInfo.GetOptions)
    if not ok then return end
    local o = ns.GossipPick(options, get)
    if o and C_GossipInfo.SelectOption then
        C_GossipInfo.SelectOption(o.gossipOptionID or o.optionID or 1)
    end
end
ns.SkipGossipEvent = onEvent

local panel = { { kind = "head", label = ns.L.TWP_GOSSIP_HEAD } }
for _, k in ipairs(ns.GOSSIP_ORDER) do
    panel[#panel + 1] = { kind = "check", key = k, label = ns.L["TWP_GOSSIP_" .. k:upper()] }
end

ns.AddTweak({
    key = "skipGossip", group = "quests", icon = "Interface\\Icons\\Ability_Warrior_BattleShout",
    star = true, shift = true,
    defaults = { taxi = true, vendor = true, banker = true, trainer = false, binder = false },
    panel = panel,
    enable = function(g)
        get = g
        frame = frame or CreateFrame("Frame")
        frame:SetScript("OnEvent", onEvent)
        frame:RegisterEvent("GOSSIP_SHOW")
    end,
    disable = function()
        if frame then frame:UnregisterAllEvents() end
    end,
    changed = function(_, _, g) get = g end,
})
