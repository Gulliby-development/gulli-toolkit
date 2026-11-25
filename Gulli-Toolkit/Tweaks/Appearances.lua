-- Appearance collector: a line in the item tooltip and a mark on the bag slot of gear whose look
-- the account has not collected yet, and (keep) junk selling leaves such items alone.

local _, ns = ...

local MARK = "Interface\\Icons\\INV_Chest_Cloth_17"
local ICON = "Interface\\Icons\\INV_Chest_Cloth_17"
local get                         -- the tweak's option reader while it runs
local cache = {}                  -- item id -> state, or false for "nothing to collect"
local marks = setmetatable({}, { __mode = "k" })   -- the game's bag buttons -> our texture
local frame, hooked, queued

local function opt(key)
    if get then return get(key) end
    return ns.TweakGet("appearances", key)
end

-- What collecting an item would bring: "new" (no item of its look is known), "source" (the look
-- is known from another item), "alt" (another class could collect it), or nil (known already,
-- or no look at all). Items the client has not loaded yet are not cached.
function ns.AppearanceState(item)
    local TC = C_TransmogCollection
    if item == nil or not TC or not TC.GetItemInfo then return nil end
    local c = cache[item]
    if c ~= nil then return c or nil end
    local ok, look, source = pcall(TC.GetItemInfo, item)
    if not ok or not source then return nil end
    local state = false
    if not (TC.PlayerKnowsSource and TC.PlayerKnowsSource(source)) then
        local hasData, canCollect = true, true
        if TC.PlayerCanCollectSource then hasData, canCollect = TC.PlayerCanCollectSource(source) end
        if not hasData then return nil end
        local lookKnown = false
        if look and TC.GetAllAppearanceSources then
            for _, other in ipairs(TC.GetAllAppearanceSources(look) or {}) do
                if other ~= source and TC.PlayerKnowsSource and TC.PlayerKnowsSource(other) then
                    lookKnown = true
                    break
                end
            end
        end
        if not canCollect then state = not lookKnown and "alt" or false
        elseif lookKnown then state = "source"
        else state = "new" end
    end
    if type(item) == "number" then cache[item] = state end
    return state or nil
end

-- Does the player want this state marked? "new" always, the others behind their switches.
local function wanted(state)
    return state == "new" or (state == "source" and opt("source") == true)
        or (state == "alt" and opt("alts") == true)
end

-- For other code (the junk rules): an item whose look the player still collects stays.
local function keeps(item)
    if not ns.TweakOn("appearances") or opt("keep") ~= true then return false end
    return wanted(ns.AppearanceState(item))
end

ns.AppearanceKeeps = keeps

local TIP = { new = "TWP_LOOK_NEW", source = "TWP_LOOK_SOURCE", alt = "TWP_LOOK_ALT" }

-- The tooltip line of an item, in the Gulli block.
function ns.AppearanceTip(id)
    if not ns.TweakOn("appearances") then return {} end
    local state = ns.AppearanceState(id)
    if not wanted(state) then return {} end
    local S = ns.Skin
    return { { group = "state", icon = ICON, left = ns.L[TIP[state]], color = S and S.GOOD } }
end

local function containerItem(bag, slot)
    if C_Container and C_Container.GetContainerItemID then return C_Container.GetContainerItemID(bag, slot) end
    return GetContainerItemID and GetContainerItemID(bag, slot)
end

-- Each item button of the open bags (the game's combined bag and its single bag frames).
local function eachButton(fn)
    local frames = {}
    if ContainerFrameCombinedBags then frames[#frames + 1] = ContainerFrameCombinedBags end
    for i = 1, 13 do
        local f = _G["ContainerFrame" .. i]
        if f then frames[#frames + 1] = f end
    end
    for _, f in ipairs(frames) do
        if f.IsShown and f:IsShown() and f.EnumerateValidItems then
            for _, b in f:EnumerateValidItems() do fn(b) end
        end
    end
end

function ns.UpdateAppearanceMarks()
    queued = false
    local on = ns.TweakOn("appearances")
    eachButton(function(b)
        local bag = b.GetBagID and b:GetBagID()
        local slot = b.GetID and b:GetID()
        local id = on and bag and slot and containerItem(bag, slot)
        local show = id and wanted(ns.AppearanceState(id)) or false
        local t = marks[b]
        if show and not t then
            t = b:CreateTexture(nil, "OVERLAY")
            t:SetTexture(MARK)
            t:SetSize(14, 14)
            t:SetPoint("TOPRIGHT", -2, -2)
            marks[b] = t
        end
        if t then t:SetShown(show) end
    end)
end

local function queue()
    if queued then return end
    queued = true
    if C_Timer then C_Timer.After(0, ns.UpdateAppearanceMarks) else ns.UpdateAppearanceMarks() end
end

local function onEvent(_, event)
    if event == "TRANSMOG_COLLECTION_UPDATED" or event == "TRANSMOG_COLLECTION_SOURCE_ADDED"
        or event == "GET_ITEM_INFO_RECEIVED" then
        wipe(cache)
    end
    queue()
end

ns.AppearancesEvent = onEvent

ns.AddTweak({
    key = "appearances", group = "loot", icon = ICON, star = true,
    defaults = { keep = true, source = false, alts = false },
    panel = {
        { kind = "switch", key = "keep", label = ns.L.TWP_LOOK_KEEP },
        { kind = "head", label = ns.L.TWP_LOOK_ALSO },
        { kind = "switch", key = "source", label = ns.L.TWP_LOOK_SOURCES },
        { kind = "switch", key = "alts", label = ns.L.TWP_LOOK_ALTS },
    },
    enable = function(g)
        get = g
        wipe(cache)
        local S = ns.Skin
        if not hooked then
            hooked = true
            if S and S.TipProvider then
                S.TipProvider("item", "Appearances", function(id) return ns.AppearanceTip(id) end)
            end
            if ContainerFrame_Update then hooksecurefunc("ContainerFrame_Update", queue) end
        end
        frame = frame or CreateFrame("Frame")
        frame:SetScript("OnEvent", onEvent)
        frame:RegisterEvent("BAG_UPDATE_DELAYED")
        frame:RegisterEvent("TRANSMOG_COLLECTION_UPDATED")
        frame:RegisterEvent("TRANSMOG_COLLECTION_SOURCE_ADDED")
        frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        queue()
    end,
    disable = function()
        if frame then frame:UnregisterAllEvents() end
        get = nil
        ns.UpdateAppearanceMarks()
    end,
    changed = function(_, _, g) get = g; queue() end,
})

-- The global the junk rules of Merchant and BagSpace ask (behind a check that the core is there).
if GulliToolkit then GulliToolkit.KeepsAppearance = keeps end
