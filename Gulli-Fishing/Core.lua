-- Fishing made easy: a double right-click casts Fishing (or puts a lure on the pole when it has
-- none), the bobber's splash is loud while fishing, fishing loot is taken at once, and a missing
-- lure is told once. The sound settings the module changes are kept in GulliFishingDB.saved and
-- put back a while after the last cast, at logout, and at the next login after a crash.

local ADDON, ns = ...
local L = ns.L

ns.DOUBLE = 0.4      -- seconds between the two presses of a double-click
ns.RECENT = 300      -- without a pole equipped, a cast this recent keeps the double-click on
ns.RESTORE = 20      -- seconds after the last cast before the sound settings go back
ns.CAST_GAP = 90     -- a longer gap between casts or catches is a break, not fishing time
ns.CHANNEL = 21      -- seconds a cast lasts when the game does not say
ns.BAR_GOT = 2       -- seconds the bar shows what was just caught
ns.BAR_IDLE = 10     -- seconds the bar asks for the next cast
ns.BAR_LOW = 5       -- seconds left when the bar turns to its warning colour
ns.SPELLS = { 131474, 7620, 7731, 7732, 18248 } -- Fishing: the retail spell, then the ranks
ns.POLE_CLASS, ns.POLE_SUBCLASS = 2, 20
ns.MAIN_HAND = 16
-- Lures, best first: item id and the fishing skill it needs.
ns.LURES = {
    { 6533, 100 }, -- Aquadynamic Fish Attractor
    { 6532, 100 }, -- Bright Baubles
    { 7307, 100 }, -- Flesh Eating Worm
    { 6530, 50 },  -- Nightcrawlers
    { 6811, 50 },  -- Aquadynamic Fish Lens
    { 6529, 0 },   -- Shiny Bauble
}

-- What the splash switches set while fishing. A new setting gets its CVars here and a switch.
ns.BOOST = {
    loud = { Sound_EnableAllSound = "1", Sound_EnableSFX = "1", Sound_SFXVolume = "1",
             Sound_EnableSoundWhenGameIsInBG = "1", Sound_MasterVolume = function(v) return math.max(v or 0, 0.8) end },
    mute = { Sound_MusicVolume = "0", Sound_AmbienceVolume = "0" },
    interact = { SoftTargetInteract = "3", SoftTargetInteractRange = "30" },
}

-- Game API wrappers -----------------------------------------------------------------------------

local CI = C_Item or {}
local function now() return GetTime and GetTime() or time() end
local function combat() return InCombatLockdown and InCombatLockdown() end

local function getCVar(name)
    if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(name) end
    return GetCVar and GetCVar(name)
end

local function setCVar(name, value)
    local set = (C_CVar and C_CVar.SetCVar) or SetCVar
    if set then pcall(set, name, tostring(value)) end
end

local function spellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return GetSpellInfo and (GetSpellInfo(id))
end

local function knows(id)
    if C_SpellBook and C_SpellBook.IsSpellKnown then return C_SpellBook.IsSpellKnown(id) end
    if IsPlayerSpell then return IsPlayerSpell(id) end
    return IsSpellKnown and IsSpellKnown(id)
end

function ns.ItemName(id)
    local n = CI.GetItemNameByID and CI.GetItemNameByID(id)
    if not n and CI.RequestLoadItemDataByID then CI.RequestLoadItemDataByID(id) end
    return n or ("#" .. tostring(id))
end

function ns.ItemIcon(id)
    return (CI.GetItemIconByID and CI.GetItemIconByID(id)) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function itemCount(id)
    if CI.GetItemCount then return CI.GetItemCount(id) or 0 end
    return GetItemCount and GetItemCount(id) or 0
end

local function usable(id)
    if CI.IsUsableItem then return CI.IsUsableItem(id) and true or false end
    return true
end

-- Bags and equipping: only the retail calls, a client without them has no Equip button.
local CC = C_Container or {}

-- A fishing pole in the bags: its item id, or nil.
function ns.PoleInBags()
    if not (CC.GetContainerNumSlots and CC.GetContainerItemID and CI.GetItemInfoInstant) then return nil end
    for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or 5 do
        for slot = 1, CC.GetContainerNumSlots(bag) or 0 do
            local id = CC.GetContainerItemID(bag, slot)
            if id then
                local _, _, _, _, _, class, sub = CI.GetItemInfoInstant(id)
                if class == ns.POLE_CLASS and sub == ns.POLE_SUBCLASS then return id end
            end
        end
    end
end

-- The Equip button of the window: puts the pole from the bags into the hand. Never in a fight.
function ns.EquipPole()
    if combat() or ns.HasPole() or not CI.EquipItemByName then return false end
    local id = ns.PoleInBags()
    if not id then return false end
    CI.EquipItemByName(id)
    return true
end

-- The game's own Interact key as the player reads it ("F"), or nil when none is bound.
function ns.InteractKey()
    if not GetBindingKey then return nil end
    local key = GetBindingKey("INTERACTTARGET") or GetBindingKey("INTERACTMOUSEOVER")
    if not key or key == "" then return nil end
    return GetBindingText and GetBindingText(key) or key
end

-- The fishing skill: rank, the rank's cap and what the lure and pole add; nil when unknown.
function ns.Skill()
    if not (GetProfessions and GetProfessionInfo) then return nil end
    local _, _, _, fishing = GetProfessions()
    if not fishing then return nil end
    local _, _, rank, cap, _, _, _, bonus = GetProfessionInfo(fishing)
    if type(rank) ~= "number" then return nil end
    return rank, cap, bonus
end

-- The Fishing spell's name in the client's language, or nil when the character cannot fish.
function ns.FishingSpell()
    for _, id in ipairs(ns.SPELLS) do
        if knows(id) then return spellName(id), id end
    end
end

function ns.IsFishing(spellID)
    for _, id in ipairs(ns.SPELLS) do if id == spellID then return true end end
    return false
end

function ns.HasPole()
    local id = GetInventoryItemID and GetInventoryItemID("player", ns.MAIN_HAND)
    if not id or not CI.GetItemInfoInstant then return false end
    local _, _, _, _, _, class, sub = CI.GetItemInfoInstant(id)
    return class == ns.POLE_CLASS and sub == ns.POLE_SUBCLASS
end

-- Seconds of lure left on the pole, 0 when it has none.
function ns.LureLeft()
    if CI.GetWeaponEnchantInfo then
        local ok, e = pcall(CI.GetWeaponEnchantInfo, 0)
        if ok and type(e) == "table" then
            if e.hasEnchant == nil then e = e[1] end
            if e and e.hasEnchant then return math.floor((e.timeLeft or 0) / 1000) end
            return 0
        end
    end
    if GetWeaponEnchantInfo then
        local has, ms = GetWeaponEnchantInfo()
        if has then return math.floor((ms or 0) / 1000) end
    end
    return 0
end

-- The best lure in the bags the character can use, or nil.
function ns.BestLure()
    for _, l in ipairs(ns.LURES) do
        if itemCount(l[1]) > 0 and usable(l[1]) then return l[1] end
    end
end

-- The lure a double-click should put on: a pole without a lure and one in the bags.
function ns.LureToApply()
    if not ns.HasPole() or ns.LureLeft() > 0 then return nil end
    return ns.BestLure()
end

-- The player is fishing now: a pole in the hand, or a cast not long ago.
function ns.Active(t)
    if ns.HasPole() then return true end
    return ns.lastCast ~= nil and (t or now()) - ns.lastCast <= ns.RECENT
end

-- Double-click to cast --------------------------------------------------------------------------

-- A double right-click casts only out of combat, on the ground, with nothing under the mouse
-- that the right-click is meant for (a unit, an item on the cursor).
function ns.CanCast()
    if ns.paused or not ns.db.cast or combat() then return false end
    if not ns.Active() or not ns.FishingSpell() then return false end
    if IsMounted and IsMounted() then return false end
    if IsFlying and IsFlying() then return false end
    if UnitExists and UnitExists("mouseover") then return false end
    if CursorHasItem and CursorHasItem() then return false end
    return true
end

-- What the next click of the cast button does: { "item", id } or { "spell", name }.
function ns.NextAction()
    local lure = ns.db.lure and ns.LureToApply()
    if lure then return "item", lure end
    return "spell", (ns.FishingSpell())
end

-- Sets a secure cast button to the next action (out of combat only); returns its kind.
function ns.SetAction(b)
    if not b or combat() then return nil end
    local kind, what = ns.NextAction()
    if not what then return nil end
    b:SetAttribute("type", kind)
    if kind == "item" then
        b:SetAttribute("item", "item:" .. what)
        b:SetAttribute("target-slot", ns.MAIN_HAND)
        b:SetAttribute("spell", nil)
    else
        b:SetAttribute("spell", what)
        b:SetAttribute("item", nil)
        b:SetAttribute("target-slot", nil)
    end
    return kind
end

function ns.OnMouseDown(button)
    if button ~= "RightButton" then return end
    local t = now()
    local double = ns.lastDown and t - ns.lastDown <= ns.DOUBLE
    ns.lastDown = (not double) and t or nil
    if double and ns.CanCast() then ns.Arm() end
end

-- The second press's release goes to the secure cast button through a binding of the mouse
-- button, which is taken away again right after (or when no click came).
function ns.Arm()
    local b = ns.CastButton and ns.CastButton()
    local kind = ns.SetAction(b)
    if not kind then return end
    if SetOverrideBindingClick then SetOverrideBindingClick(b, true, "BUTTON2", b:GetName()) end
    ns.armed = kind
    if C_Timer then C_Timer.After(1, ns.Disarm) end
end

function ns.Disarm()
    if not ns.armed then return end
    if combat() then ns.disarmLater = true return end
    local b = ns.CastButton and ns.CastButton()
    if b and ClearOverrideBindings then ClearOverrideBindings(b) end
    ns.armed, ns.disarmLater = nil, nil
end

-- The cast key ---------------------------------------------------------------------------------

-- The key the player set casts like the double-click: bound to its own secure button while the
-- player is fishing (a pole in the hand, or a cast not long ago), and free the rest of the time.
local keyOwner
function ns.ApplyKey()
    if combat() then ns.keyLater = true return end
    ns.keyLater = nil
    if keyOwner and ClearOverrideBindings then ClearOverrideBindings(keyOwner) end
    ns.keyBound = nil
    local key = ns.db and ns.db.castKey
    if not key or ns.paused or not ns.Active() or not ns.FishingSpell() then return end
    local b = ns.KeyCastButton and ns.KeyCastButton()
    if not b then return end
    keyOwner = keyOwner or CreateFrame("Frame")
    ns.SetAction(b)
    ns.Skin.BindKey(keyOwner, true, key, b:GetName(), "LeftButton")
    ns.keyBound = key
end

function ns.SetCastKey(key)
    ns.db.castKey = key and ns.Skin.KeyBase(key) or nil
    ns.ApplyKey()
    if ns.Refresh then ns.Refresh() end
end

-- The cast key as the player reads it, or nil.
function ns.CastKeyText()
    local key = ns.db and ns.db.castKey
    if not key then return nil end
    return GetBindingText and GetBindingText(key) or key
end

-- Sound while fishing ---------------------------------------------------------------------------

-- Sets what the switches ask for and keeps the player's own values to put back.
function ns.Boost()
    if ns.paused then return end
    ns.db.saved = ns.db.saved or {}
    for key, set in pairs(ns.BOOST) do
        if ns.db[key] then
            for cvar, v in pairs(set) do
                local old = getCVar(cvar)
                if old ~= nil then
                    if ns.db.saved[cvar] == nil then ns.db.saved[cvar] = old end
                    if type(v) == "function" then v = v(tonumber(ns.db.saved[cvar])) end
                    setCVar(cvar, v)
                end
            end
        end
    end
    if next(ns.db.saved) == nil then ns.db.saved = nil end
    ns.boosted = ns.db.saved ~= nil
end

-- Puts every value the module changed back; in a fight it waits for the fight to end.
function ns.Restore()
    if not (ns.db and ns.db.saved) then ns.boosted = false return end
    if combat() then ns.restoreLater = true return end
    for cvar, v in pairs(ns.db.saved) do setCVar(cvar, v) end
    ns.db.saved, ns.boosted, ns.restoreLater = nil, false, nil
end

-- A cast of Fishing started.
function ns.OnCast(t)
    t = t or now()
    ns.lastCast = t
    ns.Fished()
    local start, finish = ns.ChannelTimes()
    ns.cast = { start = start or t, finish = finish or t + ns.CHANNEL }
    ns.got, ns.idleUntil = nil, nil
    ns.Boost()
    ns.CheckLure()
    if C_Timer then
        C_Timer.After(ns.RESTORE + 1, function()
            if ns.lastCast and now() - ns.lastCast >= ns.RESTORE then ns.Restore() end
        end)
        -- the cast key lets go once the player stopped fishing
        C_Timer.After(ns.RECENT + 1, function() ns.ApplyKey() end)
    end
    if not ns.keyBound then ns.ApplyKey() end
    if ns.Refresh then ns.Refresh() end
end

-- When the cast under way began and ends, in GetTime seconds; nil when the game does not say.
function ns.ChannelTimes()
    if not UnitChannelInfo then return nil end
    local ok, _, _, _, startMS, endMS = pcall(UnitChannelInfo, "player")
    if not ok or type(startMS) ~= "number" or type(endMS) ~= "number" then return nil end
    if issecretvalue and (issecretvalue(startMS) or issecretvalue(endMS)) then return nil end
    if endMS <= startMS then return nil end
    return startMS / 1000, endMS / 1000
end

-- The bobber is out of the water: caught, time up or cast again.
function ns.OnStop(t)
    if not ns.cast then return end
    ns.cast = nil
    ns.idleUntil = (t or now()) + ns.BAR_IDLE
    if ns.Refresh then ns.Refresh() end
end

-- Fishing time: the seconds between casts and catches, without the breaks.
function ns.Fished(t)
    local s = ns.s
    if not s then return end
    t = t or time()
    if s.lastAt and t >= s.lastAt and t - s.lastAt <= ns.CAST_GAP then s.secs = (s.secs or 0) + (t - s.lastAt) end
    s.lastAt = t
end

-- Catches per hour of fishing, once there is enough to tell.
function ns.PerHour()
    local s = ns.s
    if not s or (s.secs or 0) < 120 or s.catches < 2 then return nil end
    return math.floor(s.catches * 3600 / s.secs + 0.5)
end

-- What the bar on the screen shows at time t: "got" (the catch), "cast" (the bobber is out),
-- "idle" (cast again) or nil (hidden). A new state gets its case here and in the test.
function ns.BarState(t)
    if ns.paused or not ns.db or not ns.db.bar then return nil end
    t = t or now()
    if ns.got and t < ns.got.till then return "got" end
    if ns.cast and t < ns.cast.finish then return "cast" end
    if ns.idleUntil and t < ns.idleUntil then return "idle" end
    return nil
end

-- Lure reminder ---------------------------------------------------------------------------------

-- Tells once when the pole has no lure and one is in the bags; again after the next lure ran out.
function ns.CheckLure()
    if ns.paused or not ns.db.remind or not ns.HasPole() then return end
    if ns.LureLeft() > 0 then ns.told = nil return end
    local lure = ns.BestLure()
    if not lure or ns.told then return end
    ns.told = true
    local text = (ns.db.lure and (ns.db.cast or ns.db.castKey) and L.LURE_DOUBLE or L.LURE_PUT):format(ns.ItemName(lure))
    if ns.OnLureMissing then ns.OnLureMissing(lure, text) else print(L.TITLE .. ": " .. text) end
end

-- Fishing loot ----------------------------------------------------------------------------------

function ns.IsFishingLoot()
    return IsFishingLoot and IsFishingLoot() and true or false
end

-- The loot window opened on a catch: count it, and take it all unless the game does already.
function ns.OnLoot(autoLoot)
    if ns.paused or ns.looting or not ns.IsFishingLoot() then return end
    ns.looting = true
    local n = GetNumLootItems and GetNumLootItems() or 0
    local s = ns.s
    s.catches = s.catches + 1
    ns.Fished()
    local first
    for i = 1, n do
        local link = GetLootSlotLink and GetLootSlotLink(i)
        local id = link and tonumber(link:match("item:(%d+)"))
        if id then
            local _, _, count = GetLootSlotInfo(i)
            s.items[id] = (s.items[id] or 0) + (count or 1)
            first = first or { id = id, n = count or 1 }
        end
    end
    if first then
        first.till = now() + ns.BAR_GOT
        ns.got = first
        ns.idleUntil = now() + ns.BAR_IDLE
    end
    if ns.db.loot and not autoLoot and LootSlot then
        for i = n, 1, -1 do LootSlot(i) end
    end
    if ns.Refresh then ns.Refresh() end
end

-- The session -----------------------------------------------------------------------------------

function ns.Start(t)
    ns.s = { t = t or time(), catches = 0, items = {}, secs = 0 }
    if ns.cdb then ns.cdb.s = ns.s end
end

function ns.Resume(t)
    local s = ns.cdb and ns.cdb.s
    if type(s) == "table" and s.t then
        s.catches, s.items, s.secs = s.catches or 0, s.items or {}, s.secs or 0
        ns.s = s
    else
        ns.Start(t)
    end
end

-- What was caught this session, the most first: { { id, n } }.
function ns.Caught()
    local out = {}
    for id, n in pairs(ns.s.items) do out[#out + 1] = { id = id, n = n } end
    table.sort(out, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.id < b.id end)
    return out
end

-- One line for the hub's home page while something was caught.
function ns.Summary()
    if not ns.s or ns.s.catches == 0 then return nil end
    return L.SUM:format(ns.s.catches), "Interface\\Icons\\Trade_Fishing", { label = L.ST_CATCHES }
end

function ns.Span(sec)
    sec = math.max(0, math.floor(sec))
    if sec >= 3600 then return L.HM:format(math.floor(sec / 3600), math.floor(sec % 3600 / 60)) end
    return L.M:format(math.max(1, math.ceil(sec / 60)))
end

-- Settings -------------------------------------------------------------------------------------

-- castKey (the player's cast key) has no default. The bar starts shown (owner's decision of
-- 2026-11-25: it is on the screen only while fishing); its switch is the hub's.
ns.DEFAULTS = { cast = true, lure = true, loud = true, mute = false, interact = true, loot = true, remind = true,
                bar = true, hideCast = true }
ns.OPT_ICON = {
    cast = "Interface\\Icons\\Trade_Fishing",
    lure = "Interface\\Icons\\INV_Misc_Orb_03",
    loud = "Interface\\Icons\\INV_Misc_Horn_01",
    mute = "Interface\\Icons\\INV_Misc_Drum_01",
    interact = "Interface\\Icons\\INV_Misc_Spyglass_02",
    loot = "Interface\\Icons\\INV_Misc_Bag_10",
    remind = "Interface\\Icons\\INV_Misc_Note_01",
    castKey = "Interface\\Icons\\INV_Misc_Key_03",
    hideCast = "Interface\\Icons\\Spell_Nature_TimeStop",
    bar = "Interface\\Icons\\Trade_Fishing",
    catches = "Interface\\Icons\\INV_Misc_Fish_02",
    skill = "Interface\\Icons\\INV_Fishingpole_02",
}

-- The steps of the "How to fish" card: { key, done, state, tone } with state a text key and
-- its argument. A new step goes here, with its texts in every language and a case in the test.
function ns.Steps()
    local pole, bag = ns.HasPole(), nil
    if not pole then bag = ns.PoleInBags() end
    local key, interact = ns.CastKeyText(), ns.InteractKey()
    local out = {}
    out[1] = { key = "POLE", done = pole, equip = bag,
               state = pole and "STEP_POLE_OK" or bag and "STEP_POLE_BAG" or "STEP_POLE_NONE",
               arg = bag and ns.ItemName(bag) or nil, tone = pole and "good" or "warn" }
    out[2] = { key = "CAST", desc = ns.db.cast and "STEP_CAST_D" or "STEP_CAST_KEY_D",
               state = key and "STEP_CAST_KEY" or "STEP_CAST_NOKEY", arg = key,
               tone = (ns.db.cast or key) and "muted" or "warn" }
    out[3] = { key = "CATCH", desc = interact and ns.db.interact and "STEP_CATCH_D" or "STEP_CATCH_CLICK_D",
               arg = interact, state = (not interact) and "STEP_CATCH_UNSET" or nil, tone = "warn" }
    return out
end

-- The strip on top of the window: a title key, a sub text and a tone ("good", "warn", "muted").
function ns.Status()
    local L = ns.L
    if ns.paused then return L.STATE_PAUSED, L.STATUS_PAUSED, "muted" end
    if not ns.FishingSpell() then return L.STATE_NO_SKILL, L.STATUS_NO_SKILL, "warn" end
    local key = ns.CastKeyText()
    if not ns.db.cast and not key then return L.STATUS_NO_WAY, L.STATUS_NO_WAY_D, "warn" end
    if not ns.Active() then return L.STATUS_POLE, L.STATUS_POLE_D, "warn" end
    local how = ns.db.cast and (key and L.HOW_BOTH:format(key) or L.HOW_CLICK) or L.HOW_KEY:format(key)
    local interact = ns.db.interact and ns.InteractKey()
    return L.STATUS_READY, how .. " " .. (interact and L.HOW_CATCH:format(interact) or L.HOW_CATCH_CLICK), "good"
end

-- "14 caught in 38 min" for the footer.
function ns.SessionLine()
    local s = ns.s
    if not s or s.catches == 0 then return ns.L.FOOT_NONE end
    if (s.secs or 0) < 60 then return ns.L.SUM:format(s.catches) end
    return ns.L.FOOT_SUM:format(s.catches, ns.Span(s.secs))
end

function ns.SetPref(key, value)
    ns.db[key] = value
    -- a sound switch turned while fishing takes effect now
    if ns.BOOST[key] and ns.boosted then ns.Restore(); ns.Boost() end
    if key == "hideCast" and not value and ns.ShowGameBar then ns.ShowGameBar() end
    if ns.Refresh then ns.Refresh() end
end

function ns.Reset()
    ns.Restore()
    for k in pairs(ns.DEFAULTS) do ns.db[k] = ns.DEFAULTS[k] end
    ns.db.castKey, ns.db.barPoint = nil, nil
    ns.ApplyKey()
    if ns.PlaceBar then ns.PlaceBar() end
    if ns.Refresh then ns.Refresh() end
end

-- The hub's switch: a paused module casts, loots and changes nothing, and puts the sound back.
function ns.Pause(on)
    ns.paused = on and true or false
    if on then ns.Restore(); ns.Disarm(); ns.cast, ns.got, ns.idleUntil = nil, nil, nil end
    ns.ApplyKey()
    if ns.Refresh then ns.Refresh() end
end

-- The hub's Unlock mode shows the bar to place it.
ns.moving = false
function ns.Move(on)
    ns.moving = on and true or false
    if ns.Refresh then ns.Refresh() end
end

-- Slash command ----------------------------------------------------------------------------------

function ns.Slash(msg)
    local cmd = strtrim(msg or ""):lower()
    if cmd == "reset" then
        ns.Start()
        print(L.TITLE .. ": " .. L.NEW_SESSION_DONE)
        if ns.Refresh then ns.Refresh() end
    elseif cmd == "help" then
        print(L.TITLE .. ": " .. L.HELP)
    else
        ns.Toggle()
    end
end

-- Events ---------------------------------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, a1, a2, a3)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        GulliFishingDB = GulliFishingDB or {}
        GulliFishingCharDB = GulliFishingCharDB or {}
        ns.db, ns.cdb = GulliFishingDB, GulliFishingCharDB
        for k, v in pairs(ns.DEFAULTS) do
            if ns.db[k] == nil then ns.db[k] = v end
        end
        -- the game closed while fishing: the player's own sound comes back
        ns.Restore()
        for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP", "LOOT_READY", "LOOT_CLOSED",
                             "PLAYER_REGEN_ENABLED", "PLAYER_LOGOUT", "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED" }) do
            self:RegisterEvent(e)
        end
        ns.Resume()
        if WorldFrame and WorldFrame.HookScript then
            WorldFrame:HookScript("OnMouseDown", function(_, button) ns.OnMouseDown(button) end)
        end
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        -- Only leaving the game ends the session.
        if ns.Skin.NewSession(a1, a2, ns.s.seen) then ns.Start() end
        ns.ApplyKey()
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if a1 == "player" then ns.OnStop() end
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        if a1 == "player" and ns.IsFishing(a3) and not ns.paused then ns.OnCast() end
    elseif event == "LOOT_READY" then
        ns.OnLoot(a1)
    elseif event == "LOOT_CLOSED" then
        ns.looting = nil
    elseif event == "PLAYER_REGEN_ENABLED" then
        if ns.restoreLater then ns.Restore() end
        if ns.disarmLater then ns.Disarm() end
        if ns.keyLater then ns.ApplyKey() end
    elseif event == "PLAYER_LOGOUT" then
        ns.s.seen = time()
        ns.Restore()
    elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "UNIT_INVENTORY_CHANGED" then
        if (event ~= "UNIT_INVENTORY_CHANGED" or a1 == "player") and ns.HasPole() and ns.LureLeft() > 0 then ns.told = nil end
        if event ~= "UNIT_INVENTORY_CHANGED" or a1 == "player" then ns.ApplyKey() end
        if ns.Refresh then ns.Refresh() end
    end
end)

SLASH_GULLIFISHING1 = "/gfi"
SLASH_GULLIFISHING2 = "/gullifish"
SlashCmdList.GULLIFISHING = function(msg) ns.Slash(msg) end

function GulliFishing_Toggle() ns.Toggle() end

-- With the hub: its row and button there; alone: its own minimap button (Skin.lua).
do
    local register = GulliToolkit and GulliToolkit.Register or function(info) ns.alone = info end
    register({
        key = "Fishing",
        icon = "Interface\\AddOns\\Gulli-Fishing\\icon",
        slash = "/gfi",
        open = function() ns.Toggle() end,
        window = function() return ns.Window and ns.Window() end,
        summary = function() return ns.Summary() end,
        pause = function(on) ns.Pause(on) end,
        reset = function() ns.Reset() end,
        move = function(on) ns.Move(on) end,
        frames = { { key = "bar", icon = ns.OPT_ICON.bar,
                     get = function() return ns.db ~= nil and ns.db.bar == true end,
                     set = function(v) ns.SetPref("bar", v and true or false) end,
                     frame = function() return ns.BarFrame and ns.BarFrame() end } },
        options = {
            { label = L.OPT_CAST, icon = ns.OPT_ICON.cast, tip = L.OPT_CAST_TIP,
              get = function() return ns.db ~= nil and ns.db.cast == true end, set = function(v) ns.SetPref("cast", v) end },
            { label = L.OPT_LOUD, icon = ns.OPT_ICON.loud, tip = L.OPT_LOUD_TIP,
              get = function() return ns.db ~= nil and ns.db.loud == true end, set = function(v) ns.SetPref("loud", v) end },
            { label = L.OPT_LOOT, icon = ns.OPT_ICON.loot, tip = L.OPT_LOOT_TIP,
              get = function() return ns.db ~= nil and ns.db.loot == true end, set = function(v) ns.SetPref("loot", v) end },
            { label = L.OPT_REMIND, icon = ns.OPT_ICON.remind, tip = L.OPT_REMIND_TIP,
              get = function() return ns.db ~= nil and ns.db.remind == true end, set = function(v) ns.SetPref("remind", v) end },
        },
        -- Rows of the hub's Tweaks page, on the window's own saved keys.
        tweaks = {
            { key = "cast", group = "ui", label = L.OPT_CAST, desc = L.TWK_CAST_D, tip = L.OPT_CAST_TIP, icon = ns.OPT_ICON.cast,
              get = function() return ns.db ~= nil and ns.db.cast == true end, set = function(v) ns.SetPref("cast", v and true or false) end },
            { key = "loud", group = "ui", label = L.OPT_LOUD, desc = L.TWK_LOUD_D, tip = L.OPT_LOUD_TIP, icon = ns.OPT_ICON.loud,
              get = function() return ns.db ~= nil and ns.db.loud == true end, set = function(v) ns.SetPref("loud", v and true or false) end },
            { key = "loot", group = "loot", label = L.OPT_LOOT, desc = L.OPT_LOOT_TIP, icon = ns.OPT_ICON.loot,
              get = function() return ns.db ~= nil and ns.db.loot == true end, set = function(v) ns.SetPref("loot", v and true or false) end },
        },
    })
end
