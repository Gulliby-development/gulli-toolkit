-- Quest item sparkle: a bright mark over the quest object in front of the player, a crosshair
-- that lights while one is in reach, and a glow on the bag slots that hold quest items.
-- An addon cannot draw on a 3D object or see the objects around it: the game picks the nearest
-- interactable object for the interact key ("softinteract") and can give it a nameplate. We let
-- it do that for the keyboard too, check by its tooltip that a quest needs it, and lay our own
-- frame over that nameplate. The game settings we change are kept in GulliToolkitDB.sparkleSaved
-- and put back when the tweak goes off (or at the next load, after a crash).

local _, ns = ...
local L = ns.L

local Q = {}
ns.Sparkle = Q

Q.KEY = "questSparkle"
Q.DEFAULTS = {
    world = true, style = "glow", bright = 4, size = 3, color = "gold", pulse = true,
    crosshair = true, sound = true, range = 15, icons = true,
    bags = true, bagsStart = true,
}
Q.STYLES = { "glow", "ring", "beam", "arrow", "stars" }
Q.COLORS = {
    gold = { 1, 0.84, 0.25 }, green = { 0.45, 1, 0.35 }, blue = { 0.35, 0.75, 1 },
    purple = { 0.8, 0.45, 1 }, red = { 1, 0.38, 0.3 },
}
Q.COLOR_ORDER = { "gold", "green", "blue", "purple", "red" }
Q.RANGE_MIN, Q.RANGE_MAX = 5, 15
Q.SOUND_GAP = 30          -- seconds before the same object rings again
-- Quest lines of a tooltip (Enum.TooltipDataLineType, with the client's numbers as a fallback).
local LT = Enum and Enum.TooltipDataLineType or {}
local OBJECTIVE, TITLE, PLAYER = LT.QuestObjective or 8, LT.QuestTitle or 17, LT.QuestPlayer or 18

local MEDIA = "Interface\\AddOns\\Gulli-Toolkit\\Media\\"
local GLOW, RING, ROUND = MEDIA .. "Glow", MEDIA .. "Ring4", MEDIA .. "Round"
local STAR = "Interface\\Cooldown\\star4"
local BAG_GLOW = "Interface\\Buttons\\UI-ActionButton-Border"

-- Game wrappers --------------------------------------------------------------------------------

local function secret(v) return issecretvalue and issecretvalue(v) end

local function getCVar(name)
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    if not get then return nil end
    local ok, v = pcall(get, name)
    if ok then return v end
end

local function setCVar(name, value)
    local set = (C_CVar and C_CVar.SetCVar) or SetCVar
    if set then pcall(set, name, tostring(value)) end
end

local function now() return GetTime and GetTime() or time() end

local function questInfo(bag, slot)
    if C_Container and C_Container.GetContainerItemQuestInfo then
        local ok, info = pcall(C_Container.GetContainerItemQuestInfo, bag, slot)
        if ok and type(info) == "table" then return info.isQuestItem, info.questID, info.isActive end
        return nil
    end
    if GetContainerItemQuestInfo then return GetContainerItemQuestInfo(bag, slot) end
end

local function tooltipOf(unit)
    if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then return nil end
    local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
    if ok then return data end
end

local function plateOf(unit)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if ok then return plate end
end

-- Settings ---------------------------------------------------------------------------------------

local get = function(opt) return Q.DEFAULTS[opt] end

function Q.Get(opt)
    if ns.TweakGet then
        local v = ns.TweakGet(Q.KEY, opt)
        if v ~= nil then return v end
    end
    return Q.DEFAULTS[opt]
end

-- The game settings the tweak wants, by the switches that are on.
function Q.CVars(g)
    g = g or get
    local want = {}
    if g("world") or g("crosshair") or g("sound") then
        want.SoftTargetInteract = "3"            -- keyboard and gamepad pick objects
        want.SoftTargetNameplateInteract = "1"   -- the picked object gets a nameplate
        local r = tonumber(g("range")) or Q.DEFAULTS.range
        r = math.max(Q.RANGE_MIN, math.min(Q.RANGE_MAX, math.floor(r)))
        want.SoftTargetInteractRange = tostring(r)
        if g("icons") then
            want.SoftTargetIconInteract = "1"
            want.SoftTargetIconGameObject = "1"
        end
    end
    return want
end

-- Sets what `want` names and puts back what we set before and no longer want. The player's own
-- value is saved the first time, so a reload or a crash never saves our value as theirs.
function Q.ApplyCVars(want)
    GulliToolkitDB = GulliToolkitDB or {}
    local saved = GulliToolkitDB.sparkleSaved or {}
    for name, value in pairs(want) do
        local cur = getCVar(name)
        if cur ~= nil then
            if saved[name] == nil then saved[name] = cur end
            if cur ~= value then setCVar(name, value) end
        end
    end
    for name, old in pairs(saved) do
        if want[name] == nil then
            setCVar(name, old)
            saved[name] = nil
        end
    end
    GulliToolkitDB.sparkleSaved = next(saved) and saved or nil
end

function Q.RestoreCVars() Q.ApplyCVars({}) end

-- Rules --------------------------------------------------------------------------------------------

-- Whether a tooltip (C_TooltipInfo data) says a quest of the player needs the object: an
-- objective line that is not done, or a quest title with no objective under it.
function Q.TooltipNeeds(data)
    local lines = type(data) == "table" and data.lines
    if type(lines) ~= "table" then return false end
    local title, objective = false, false
    for _, line in ipairs(lines) do
        local t = line.type
        if t == OBJECTIVE then
            objective = true
            if not line.completed then return true end
        elseif t == TITLE or t == PLAYER then
            title = true
        end
    end
    return title and not objective
end

-- The object the game picked, when a quest needs it: guid, name (nil when hidden).
function Q.QuestObject()
    if not (UnitExists and UnitExists("softinteract")) then return nil end
    local guid = UnitGUID("softinteract")
    if guid == nil or secret(guid) then return nil end
    local need = false
    if C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest then
        local ok, related = pcall(C_QuestLog.UnitIsRelatedToActiveQuest, "softinteract")
        need = ok and related == true
    end
    if not need then need = Q.TooltipNeeds(tooltipOf("softinteract")) end
    if not need then return nil end
    local name = UnitName("softinteract")
    if secret(name) then name = nil end
    return guid, name
end

-- What a bag slot shows: "quest" (an item a quest needs), "start" (it starts a quest) or nil.
function Q.BagState(bag, slot, g)
    g = g or get
    local isQuest, questID, active = questInfo(bag, slot)
    if questID and not active then return g("bagsStart") and "start" or nil end
    if isQuest or questID then return "quest" end
    return nil
end

function Q.Alpha(bright)
    bright = math.max(1, math.min(5, tonumber(bright) or 3))
    return 0.35 + 0.13 * bright
end

function Q.Scale(size)
    size = math.max(1, math.min(5, tonumber(size) or 3))
    return 0.6 + 0.2 * size
end

function Q.Color(key) return Q.COLORS[key] or Q.COLORS.gold end

function Q.KeyText()
    local key = GetBindingKey and GetBindingKey("INTERACTTARGET")
    if not key or key == "" then return nil end
    return (GetBindingText and GetBindingText(key, "KEY_")) or key
end

-- Frames -------------------------------------------------------------------------------------------

local st = { on = false, guid = nil, rung = {}, overlays = setmetatable({}, { __mode = "k" }) }
Q.state = st

local function tex(f, path, layer, add)
    local t = f:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(path)
    if add then t:SetBlendMode("ADD") end
    return t
end

local function buildMarker()
    if st.marker then return st.marker end
    local m = CreateFrame("Frame", "GulliSparkleMarker", UIParent)
    m:SetFrameStrata("BACKGROUND")
    m:SetSize(96, 96)
    m:EnableMouse(false)
    m:Hide()
    m.glow = tex(m, GLOW, "ARTWORK", true)
    m.glow2 = tex(m, GLOW, "OVERLAY", true)
    m.core = tex(m, ROUND, "OVERLAY", true)
    m.ring = tex(m, RING, "ARTWORK", true)
    m.ring2 = tex(m, GLOW, "BACKGROUND", true)
    m.beam = tex(m, GLOW, "ARTWORK", true)
    m.beam2 = tex(m, GLOW, "OVERLAY", true)
    m.arrow = m:CreateTexture(nil, "OVERLAY")
    if m.arrow.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("NPE_ArrowDown") then
        m.arrow:SetAtlas("NPE_ArrowDown")
    else
        m.arrow:SetTexture("Interface\\Buttons\\UI-MicroStream-Yellow")
    end
    m.arrowGlow = tex(m, GLOW, "ARTWORK", true)
    m.stars = {}
    for i = 1, 6 do m.stars[i] = tex(m, STAR, "OVERLAY", true) end
    m.parts = { m.glow, m.glow2, m.core, m.ring, m.ring2, m.beam, m.beam2, m.arrow, m.arrowGlow }
    m:SetScript("OnUpdate", function(self, elapsed) Q.Animate(self, elapsed) end)
    st.marker = m
    return m
end

-- Lays the marker out for the style; the plate stands above the object, so the light goes under it.
function Q.Style(m, g)
    g = g or Q.Get
    local style, s = g("style"), Q.Scale(g("size")) * 96
    local c, a = Q.Color(g("color")), Q.Alpha(g("bright"))
    local strong = (tonumber(g("bright")) or 3) >= 4
    for _, t in ipairs(m.parts) do t:Hide(); t:ClearAllPoints() end
    for _, t in ipairs(m.stars) do t:Hide(); t:ClearAllPoints() end
    m:SetSize(s, s)
    local function show(t, w, h, x, y, alpha)
        t:SetSize(w, h)
        t:SetPoint("CENTER", m, "CENTER", x or 0, y or 0)
        t:SetVertexColor(c[1], c[2], c[3], alpha or a)
        t:Show()
    end
    if style == "ring" then
        show(m.ring, s * 1.3, s * 0.45, 0, -s * 0.35)
        show(m.ring2, s * 1.6, s * 0.6, 0, -s * 0.35, a * 0.7)
        if strong then show(m.glow, s, s * 0.7, 0, -s * 0.1, a * 0.5) end
    elseif style == "beam" then
        show(m.beam, s * 0.35, s * 3, 0, s * 0.9)
        show(m.beam2, s * 0.15, s * 3, 0, s * 0.9, math.min(1, a + 0.2))
        show(m.glow, s, s * 0.6, 0, -s * 0.3, a * 0.8)
    elseif style == "arrow" then
        show(m.arrow, s * 0.45, s * 0.6, 0, s * 0.75, 1)
        show(m.arrowGlow, s * 0.9, s * 0.9, 0, s * 0.75, a * 0.6)
        if strong then show(m.glow, s * 0.8, s * 0.6, 0, -s * 0.2, a * 0.6) end
    elseif style == "stars" then
        for i, t in ipairs(m.stars) do
            local ang = (i - 1) * math.pi / 3
            show(t, s * 0.35, s * 0.35, math.cos(ang) * s * 0.45, math.sin(ang) * s * 0.3 - s * 0.1)
        end
        show(m.glow, s * 0.9, s * 0.7, 0, -s * 0.1, a * 0.5)
    else
        show(m.glow, s * 1.3, s * 1.1, 0, -s * 0.15)
        show(m.core, s * 0.35, s * 0.3, 0, -s * 0.15, math.min(1, a + 0.15))
        if strong then show(m.glow2, s * 1.8, s * 1.5, 0, -s * 0.15, a * 0.6) end
    end
    m.style, m.size, m.alpha, m.pulse = style, s, a, g("pulse")
    m.t = 0
end

-- The pulse and the turning stars. Nothing moves with Reduce motion or in a fight.
function Q.Animate(m, elapsed)
    local S = ns.Skin
    if not m.pulse or (S and S.Calm and S.Calm()) then
        if m.moved then m:SetAlpha(1); m.moved = false end
        return
    end
    m.t = (m.t or 0) + (elapsed or 0)
    m.moved = true
    m:SetAlpha(0.65 + 0.35 * math.sin(m.t * 4))
    if m.style == "stars" then
        local s = m.size
        for i, t in ipairs(m.stars) do
            local ang = (i - 1) * math.pi / 3 + m.t * 1.5
            t:ClearAllPoints()
            t:SetPoint("CENTER", m, "CENTER", math.cos(ang) * s * 0.45, math.sin(ang) * s * 0.3 - s * 0.1)
            t:SetAlpha(0.5 + 0.5 * math.abs(math.sin(m.t * 3 + i)))
        end
    elseif m.style == "arrow" then
        m.arrow:ClearAllPoints()
        m.arrow:SetPoint("CENTER", m, "CENTER", 0, m.size * 0.75 + math.sin(m.t * 5) * 6)
    end
end

local function buildCross()
    if st.cross then return st.cross end
    local S = ns.Skin
    local f = CreateFrame("Frame", "GulliSparkleCrosshair", UIParent)
    f:SetSize(72, 72)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetFrameStrata("LOW")
    f:EnableMouse(false)
    f:Hide()
    f.halo = tex(f, GLOW, "BACKGROUND", true)
    f.halo:SetSize(110, 110); f.halo:SetPoint("CENTER")
    f.ring = tex(f, RING, "ARTWORK", true)
    f.ring:SetSize(64, 64); f.ring:SetPoint("CENTER")
    f.ticks = {}
    for i, p in ipairs({ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }) do
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        if p[1] == 0 then t:SetSize(3, 14) else t:SetSize(14, 3) end
        t:SetPoint("CENTER", f, "CENTER", p[1] * 38, p[2] * 38)
        f.ticks[i] = t
    end
    f.text = f:CreateFontString(nil, "OVERLAY")
    if S and S.SetFont then S.SetFont(f.text, 14, "OUTLINE", "bold") else f.text:SetFontObject("GameFontNormal") end
    f.text:SetPoint("TOP", f, "BOTTOM", 0, -6)
    st.cross = f
    return f
end

function Q.CrossText(key, name)
    name = name or L.TWP_SPARKLE_OBJECT
    if key then return string.format(L.TWP_SPARKLE_PRESS, key, name) end
    return name
end

local function paintCross(f, name)
    local c, a = Q.Color(Q.Get("color")), Q.Alpha(Q.Get("bright"))
    f.ring:SetVertexColor(c[1], c[2], c[3], a)
    f.halo:SetVertexColor(c[1], c[2], c[3], a * 0.5)
    for _, t in ipairs(f.ticks) do t:SetVertexColor(c[1], c[2], c[3], 1) end
    f.text:SetText(Q.CrossText(Q.KeyText(), name))
    f.text:SetTextColor(c[1], c[2], c[3], 1)
end

-- Follows what the game picked: shows the marker over its plate, the crosshair and the sound.
function Q.Refresh()
    local guid, name
    if st.on then guid, name = Q.QuestObject() end
    local m = st.marker
    local plate = guid and Q.Get("world") and plateOf("softinteract")
    if plate then
        m = buildMarker()
        if m.style ~= Q.Get("style") or m.dirty then Q.Style(m); m.dirty = false end
        m:ClearAllPoints()
        m:SetPoint("TOP", plate, "BOTTOM", 0, 0)
        m:Show()
    elseif m then
        m:Hide()
    end
    if guid and Q.Get("crosshair") then
        local f = buildCross()
        paintCross(f, name)
        f:Show()
    elseif st.cross then
        st.cross:Hide()
    end
    if guid and guid ~= st.guid and Q.Get("sound") then
        local t = now()
        if not st.rung[guid] or t - st.rung[guid] > Q.SOUND_GAP then
            st.rung[guid] = t
            local kit = SOUNDKIT and (SOUNDKIT.UI_MAP_WAYPOINT_SUPER_TRACK_ON or SOUNDKIT.MAP_PING)
            if kit and PlaySound then pcall(PlaySound, kit, "SFX") end
        end
    end
    st.guid = guid
end

-- Bags ---------------------------------------------------------------------------------------------

local function containerFrames()
    local list = {}
    if ContainerFrameCombinedBags then list[#list + 1] = ContainerFrameCombinedBags end
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do
        local f = _G["ContainerFrame" .. i]
        if f then list[#list + 1] = f end
    end
    return list
end

local function overlayFor(button)
    local o = st.overlays[button]
    if o then return o end
    o = CreateFrame("Frame", nil, button)
    o:SetAllPoints(button)
    o:SetFrameLevel((button:GetFrameLevel() or 1) + 5)
    o:EnableMouse(false)
    o.glow = tex(o, BAG_GLOW, "OVERLAY", true)
    o.glow:SetPoint("CENTER")
    o.glow2 = tex(o, GLOW, "ARTWORK", true)
    o.glow2:SetPoint("CENTER")
    o:Hide()
    st.overlays[button] = o
    return o
end

local function eachButton(frame, fn)
    if frame.EnumerateValidItems then
        for _, b in frame:EnumerateValidItems() do fn(b) end
    elseif frame.Items then
        for _, b in ipairs(frame.Items) do fn(b) end
    end
end

-- Lights the quest items in the game's own bag windows; other bag addons are left alone.
function Q.PaintBags()
    local on = st.on and Q.Get("bags")
    local c, a = Q.Color(Q.Get("color")), Q.Alpha(Q.Get("bright"))
    for _, frame in ipairs(containerFrames()) do
        if frame:IsShown() or not on then
            eachButton(frame, function(b)
                local bag = b.GetBagID and b:GetBagID()
                local slot = b.GetID and b:GetID()
                local state = on and bag and slot and Q.BagState(bag, slot, Q.Get)
                local o = st.overlays[b]
                if state then
                    o = overlayFor(b)
                    local w = (b:GetWidth() or 37)
                    o.glow:SetSize(w * 1.85, w * 1.85)
                    o.glow2:SetSize(w * 1.4, w * 1.4)
                    o.glow:SetVertexColor(c[1], c[2], c[3], math.min(1, a + 0.1))
                    o.glow2:SetVertexColor(c[1], c[2], c[3], a * (state == "start" and 0.4 or 0.7))
                    o:Show()
                elseif o then
                    o:Hide()
                end
            end)
        end
    end
end

local hooked = false
local function hookBags()
    if hooked then return end
    hooked = true
    for _, frame in ipairs(containerFrames()) do
        if frame.HookScript then frame:HookScript("OnShow", function() Q.SoonBags() end) end
    end
end

function Q.SoonBags()
    if st.bagsWait then return end
    st.bagsWait = true
    local run = function() st.bagsWait = false; Q.PaintBags() end
    if C_Timer and C_Timer.After then C_Timer.After(0.1, run) else run() end
end

-- On and off -----------------------------------------------------------------------------------

local events = {
    "PLAYER_SOFT_INTERACT_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
    "QUEST_LOG_UPDATE", "BAG_UPDATE_DELAYED", "UPDATE_BINDINGS",
}

local function listen()
    if st.ev then return st.ev end
    local f = CreateFrame("Frame")
    f:SetScript("OnEvent", function(_, event)
        if not st.on then return end
        if event == "BAG_UPDATE_DELAYED" then Q.SoonBags(); return end
        if event == "QUEST_LOG_UPDATE" then Q.SoonBags() end
        Q.Refresh()
    end)
    st.ev = f
    return f
end

function Q.Enable(g)
    st.on = true
    Q.ApplyCVars(Q.CVars(g or Q.Get))
    local f = listen()
    for _, e in ipairs(events) do pcall(f.RegisterEvent, f, e) end
    if st.marker then st.marker.dirty = true end
    hookBags()
    Q.Refresh()
    Q.PaintBags()
end

function Q.Disable()
    st.on = false
    if st.ev then st.ev:UnregisterAllEvents() end
    Q.RestoreCVars()
    if st.marker then st.marker:Hide() end
    if st.cross then st.cross:Hide() end
    st.guid = nil
    Q.PaintBags()
end

function Q.Changed(opt, value, g)
    if not st.on then return end
    if opt == "world" or opt == "crosshair" or opt == "sound" or opt == "range" or opt == "icons" then
        Q.ApplyCVars(Q.CVars(g or Q.Get))
    end
    if st.marker then st.marker.dirty = true end
    Q.Refresh()
    Q.PaintBags()
end

-- A crash or a lost logout can leave our values in the game: put the player's back at load
-- when the tweak is off.
function Q.OnLoad()
    if not (ns.TweakOn and ns.TweakOn(Q.KEY)) and GulliToolkitDB and GulliToolkitDB.sparkleSaved then
        Q.RestoreCVars()
    end
end

-- The tweak's row and its settings on the Tweaks page.
local function choices(list, prefix)
    local out = {}
    for _, k in ipairs(list) do out[#out + 1] = { k, L[prefix .. k:upper()] } end
    return out
end

local function world(g) return g("world") end
local function bags(g) return g("bags") end

Q.PANEL = {
    { kind = "head", label = L.TWP_SPARKLE_WORLD },
    { kind = "switch", key = "world", label = L.TWP_SPARKLE_MARK, tip = L.TWP_SPARKLE_MARK_T },
    { kind = "choice", key = "style", label = L.TWP_SPARKLE_STYLE, values = choices(Q.STYLES, "TWP_SPARKLE_S_"), when = world },
    { kind = "step", key = "bright", label = L.TWP_SPARKLE_BRIGHT, step = 1, min = 1, max = 5, when = world },
    { kind = "step", key = "size", label = L.TWP_SPARKLE_SIZE, step = 1, min = 1, max = 5, when = world },
    { kind = "choice", key = "color", label = L.TWP_SPARKLE_COLOR, values = choices(Q.COLOR_ORDER, "TWP_SPARKLE_C_") },
    { kind = "switch", key = "pulse", label = L.TWP_SPARKLE_PULSE, when = world },
    { kind = "switch", key = "crosshair", label = L.TWP_SPARKLE_CROSS, tip = L.TWP_SPARKLE_CROSS_T },
    { kind = "switch", key = "sound", label = L.TWP_SPARKLE_SOUND },
    { kind = "step", key = "range", label = L.TWP_SPARKLE_RANGE, step = 1, min = Q.RANGE_MIN, max = Q.RANGE_MAX,
      fmt = function(v) return string.format(L.TWP_SPARKLE_YD, v) end, tip = L.TWP_SPARKLE_RANGE_T },
    { kind = "switch", key = "icons", label = L.TWP_SPARKLE_ICONS },
    { kind = "head", label = L.TWP_SPARKLE_BAGS },
    { kind = "switch", key = "bags", label = L.TWP_SPARKLE_BAGGLOW, tip = L.TWP_SPARKLE_BAGGLOW_T },
    { kind = "switch", key = "bagsStart", label = L.TWP_SPARKLE_START, when = bags },
}

if ns.AddTweak then
    ns.AddTweak({
        key = Q.KEY, group = "quests", icon = "Interface\\Icons\\Spell_Nature_WispSplode",
        star = true, shift = false,
        defaults = Q.DEFAULTS,
        panel = Q.PANEL,
        enable = function(g) Q.Enable(g) end,
        disable = function() Q.Disable() end,
        changed = function(opt, value, g) Q.Changed(opt, value, g) end,
    })
end

do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:RegisterEvent("PLAYER_LOGOUT")
    f:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_LOGIN" then Q.OnLoad()
        elseif event == "PLAYER_LOGOUT" and st.on then Q.RestoreCVars() end
    end)
end
