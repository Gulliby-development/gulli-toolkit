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
local ART = "Interface\\AddOns\\Gulli-Toolkit\\Art\\Sparkle\\"
local GLOW = MEDIA .. "Glow"
-- the light's own pictures, drawn by tools/skin/sparkle_art.py
local SOFT, HALO, WISP, RING = ART .. "Soft", ART .. "Halo", ART .. "Wisp", ART .. "Ring"
local COMET, FLARE, BEAM = ART .. "Comet", ART .. "Flare", ART .. "Beam"
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

-- The nameplate the game gave the picked object; some clients give it only under the plate's
-- own unit token, so the shown plates are looked through too.
local function plateOf(unit)
    if not C_NamePlate then return nil end
    if C_NamePlate.GetNamePlateForUnit then
        local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
        if ok and plate then return plate end
    end
    if not (C_NamePlate.GetNamePlates and UnitIsUnit) then return nil end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok or type(plates) ~= "table" then return nil end
    for _, p in ipairs(plates) do
        local token = p.namePlateUnitToken
        if token then
            local same, isSame = pcall(UnitIsUnit, token, unit)
            if same and isSame == true and not secret(isSame) then return p end
        end
    end
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

local st = { on = false, guid = nil, rung = {}, learned = {}, overlays = setmetatable({}, { __mode = "k" }) }

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

-- Objective text without its counter and edges: "0/6 Untainted Soil" -> "untainted soil".
function Q.Normalize(text)
    text = text:lower():gsub("\194\160", " "):gsub("\226\128\153", "'")
    text = text:gsub("%d+%s*/%s*%d+", "")
    text = text:gsub("^[%s:%-]+", ""):gsub("[%s:%-]+$", "")
    return text
end

-- The quest log's objectives that are not done yet (rebuilt on QUEST_LOG_UPDATE): `text`
-- normalized, `pick` when it is something to pick up or use (never a mob to kill), and the
-- titles of the quests in the log.
function Q.OpenObjectives()
    if st.objectives then return st.objectives, st.titles end
    local list, titles = {}, {}
    local log = C_QuestLog
    if log and log.GetNumQuestLogEntries and log.GetQuestObjectives then
        local n = log.GetNumQuestLogEntries() or 0
        for i = 1, n do
            local id, title
            if log.GetInfo then
                local info = log.GetInfo(i)
                if info and not info.isHeader then id, title = info.questID, info.title end
            elseif log.GetQuestIDForLogIndex then
                id = log.GetQuestIDForLogIndex(i)
            end
            if type(title) == "string" and not secret(title) then titles[Q.Normalize(title)] = true end
            if id then
                local ok, objs = pcall(log.GetQuestObjectives, id)
                if ok and type(objs) == "table" then
                    for _, o in ipairs(objs) do
                        local t = type(o) == "table" and o.text
                        if t and not o.finished and type(t) == "string" and not secret(t) then
                            t = Q.Normalize(t)
                            if #t >= 3 then
                                list[#list + 1] = { text = t, pick = o.type == nil or o.type == "item" or o.type == "object" }
                            end
                        end
                    end
                end
            end
        end
    end
    st.objectives, st.titles = list, titles
    return list, titles
end

-- Words too common to tie an object to an objective on their own.
Q.COMMON = { small = true, large = true, ancient = true, broken = true, old = true, strange = true,
    mysterious = true, pile = true, crate = true, sack = true, box = true, barrel = true }

local function sharedWord(a, b)
    local padded = " " .. b:gsub("%p", " ") .. " "
    for w in a:gmatch("[^%s%p]+") do
        if #w >= 4 and not Q.COMMON[w] and padded:find(" " .. w .. " ", 1, true) then return w end
    end
end

-- Whether an open objective names the object: "0/6 Untainted Soil" for "Untainted Soil", the
-- objective inside the name, or, for something to pick up, a word they share ("Prickly Pine
-- Cone" and "Prickly Pinecone" share "prickly"). A name learned from the object's tooltip counts.
function Q.NamedInObjectives(name)
    if type(name) ~= "string" or secret(name) or #name < 3 then return false end
    local low = Q.Normalize(name)
    local list, titles = Q.OpenObjectives()
    local learned = st.learned[low]
    if learned and titles[learned] then return true end
    for _, o in ipairs(list) do
        if o.text:find(low, 1, true) or (#o.text >= 5 and low:find(o.text, 1, true)) then return true end
    end
    for _, o in ipairs(list) do
        if o.pick and (sharedWord(low, o.text) or sharedWord(o.text, low)) then return true end
    end
    return false
end

-- The tooltip of an object under the mouse names its quest: remember that name for the session.
function Q.LearnFromCursor()
    if not (C_TooltipInfo and C_TooltipInfo.GetWorldCursor) then return end
    local ok, data = pcall(C_TooltipInfo.GetWorldCursor)
    local lines = ok and type(data) == "table" and data.lines
    if type(lines) ~= "table" or not lines[1] then return end
    local name = lines[1].leftText
    if type(name) ~= "string" or secret(name) then return end
    local _, titles = Q.OpenObjectives()
    for i = 2, #lines do
        local t = lines[i].leftText
        if type(t) == "string" and not secret(t) and titles[Q.Normalize(t)] then
            st.learned[Q.Normalize(name)] = Q.Normalize(t)
            return
        end
    end
end

local function ask(fn, ...)
    if not fn then return nil end
    local ok, v = pcall(fn, ...)
    if ok and not secret(v) then return v end
end

-- Only world objects get the mark: the game also picks NPCs (a quest giver is "related" to the
-- quest it takes back, and its tooltip shows the quest's title), and those must stay dark.
-- A world object is no unit for UnitExists, so it is asked by UnitIsGameObject and its guid.
function Q.IsObject(guid)
    if ask(UnitIsGameObject, "softinteract") == true then return true end
    return type(guid) == "string" and guid:find("^GameObject%-") ~= nil
end

-- The object the game picked, when a quest needs it: a key (its guid, else its name), name.
function Q.QuestObject()
    local guid = ask(UnitGUID, "softinteract")
    if not Q.IsObject(guid) then return nil end
    local name = ask(UnitName, "softinteract")
    if type(name) ~= "string" then name = nil end
    local key = guid or (name and "obj:" .. name)
    if not key then return nil end
    local need = false
    if C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest then
        need = ask(C_QuestLog.UnitIsRelatedToActiveQuest, "softinteract") == true
    end
    -- the game often says nothing about objects: the tooltip, then the objectives by name
    if not need then need = Q.TooltipNeeds(tooltipOf("softinteract")) end
    if not need then need = Q.NamedInObjectives(name) end
    if not need then return nil end
    return key, name
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

Q.state = st

local function tex(f, path, layer, add)
    local t = f:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(path)
    if add then t:SetBlendMode("ADD") end
    return t
end

-- The marker is several white pictures (tools/skin/sparkle_art.py) laid over each other with the
-- ADD blend and tinted: the wide ones in the colour, the thin ones closer to white, the glint in
-- the middle nearly white, over a dark veil so the light shows on snow and sand too. It arrives
-- (shrinks into place and lights up), breathes, flares when the object comes in reach, and fades
-- where it stood when the object goes.

Q.GROUND = 0.36        -- a circle lying on the ground, seen from the usual camera angle
Q.ARRIVE = 0.45        -- seconds to arrive
Q.BLEND = 0.30         -- seconds from far to in reach
Q.FLASH = 0.50         -- the flare when the object comes in reach
Q.LEAVE = 0.40         -- the fade where it stood
Q.STATE_DELAY = 0.15   -- a change of reach shows only once it held this long
Q.POLL = 0.2           -- how often the reach is read

local function lerp(a, b, t) return a + (b - a) * t end
local TWO_PI = math.pi * 2

local function layer(m, file, drawLayer, sub, blend)
    local t = m:CreateTexture(nil, drawLayer or "ARTWORK", nil, sub or 0)
    t:SetTexture(file)
    t:SetBlendMode(blend or "ADD")
    -- sizes and places move by fractions of a pixel: no snapping to the grid
    if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
    if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
    t:SetPoint("CENTER")
    t:Hide()
    m.parts[#m.parts + 1] = t
    return t
end

-- Shows a layer at a size and a place (from the marker's centre), tinted.
local function put(m, t, w, h, x, y, r, g, b, a)
    t:SetSize(math.max(w, 0.01), math.max(h or w, 0.01))
    t:ClearAllPoints()
    t:SetPoint("CENTER", m, "CENTER", x or 0, y or 0)
    t:SetVertexColor(r, g, b, a <= 0 and 0 or a >= 1 and 1 or a)
    t:Show()
end

local function turn(t, angle) if t.SetRotation then t:SetRotation(angle) end end

local function buildMarker()
    if st.marker then return st.marker end
    local m = CreateFrame("Frame", "GulliSparkleMarker", UIParent)
    m:SetFrameStrata("BACKGROUND")
    m:SetSize(96, 96)
    m:EnableMouse(false)
    m:Hide()
    m.parts, m.v = {}, {}   -- m.v: the light's state, apart from the frame's own fields
    m.shade = layer(m, SOFT, "BACKGROUND", -1, "BLEND")
    m.pool = layer(m, SOFT, "BACKGROUND")
    m.band = layer(m, HALO, "BACKGROUND", 1)
    m.wisps = { layer(m, WISP, "BACKGROUND", 2), layer(m, WISP, "BACKGROUND", 2) }
    m.ring = layer(m, RING, "ARTWORK")
    m.comet = layer(m, COMET, "ARTWORK", 1)
    m.shaft = layer(m, BEAM, "ARTWORK")
    m.core = layer(m, BEAM, "ARTWORK", 1)
    m.aura = layer(m, SOFT, "ARTWORK")
    m.arrow = m:CreateTexture(nil, "OVERLAY", nil, 1)
    if m.arrow.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("NPE_ArrowDown") then
        m.arrow:SetAtlas("NPE_ArrowDown")
    else
        m.arrow:SetTexture("Interface\\Buttons\\UI-MicroStream-Yellow")
    end
    m.arrow:Hide()
    m.parts[#m.parts + 1] = m.arrow
    m.motes = {}
    for i = 1, 4 do m.motes[i] = layer(m, SOFT, "OVERLAY") end
    m.stars = {}
    m.glints = {}   -- each star's place and life, apart from the texture's own fields
    for i = 1, 6 do m.stars[i] = layer(m, FLARE, "OVERLAY"); m.glints[i] = {} end
    m.ripples = {}
    for i = 1, 3 do m.ripples[i] = layer(m, RING, "ARTWORK", 2) end
    m.waves = {}
    for i = 1, 3 do m.waves[i] = { t = layer(m, RING, "BORDER") } end
    m.flare = layer(m, FLARE, "OVERLAY", 2)
    m:SetScript("OnUpdate", function(self, elapsed) Q.Animate(self, elapsed) end)
    st.marker = m
    return m
end

-- Takes the settings into the marker; the light itself is drawn each frame by Q.Draw.
function Q.Style(m, g)
    g = g or Q.Get
    m.v.style, m.v.size = g("style"), Q.Scale(g("size")) * 96
    m.v.color, m.v.alpha, m.v.pulse = Q.Color(g("color")), Q.Alpha(g("bright")), g("pulse")
    for _, t in ipairs(m.parts) do t:Hide() end
    for _, w in ipairs(m.waves) do w.age = nil end
    for _, gl in ipairs(m.glints) do gl.age, gl.life = nil, nil end
    m:SetSize(m.v.size, m.v.size)
    m:SetAlpha(1)
    m.v.phase, m.v.spin, m.v.ping = m.v.phase or 0, m.v.spin or 0, m.v.ping or 1
    m.v.appear = m.v.appear or 1
    m.v.ready, m.v.flash = m.v.ready or 1, m.v.flash or 0
    Q.Draw(m)
end

-- A new object: the light arrives again.
function Q.Arrive(m, guid)
    m.v.guid, m.v.appear, m.v.leaving = guid, 0, nil
    m.v.state, m.v.pending, m.v.ready, m.v.flash, m.v.poll = nil, nil, 0, 0, 0
end

-- In reach of the interact key: true, false, or nil when the game cannot say.
function Q.InReach()
    if not UnitIsInInteractRange then return nil end
    local ok, v = pcall(UnitIsInInteractRange, "softinteract")
    if not ok or secret(v) then return nil end
    return v
end

-- One ring that widens and fades (outward), or closes on the light (inward).
local function wave(m, from, to, duration, peak, inward)
    local pick
    for _, w in ipairs(m.waves) do
        if not w.age then pick = w; break end
        if not pick or w.age > pick.age then pick = w end
    end
    pick.age, pick.from, pick.to, pick.duration, pick.peak, pick.inward = 0, from, to, duration, peak, inward
end

-- What every style reads: c.r, c.g, c.b the colour, c.h* the colour 55% to white (thin lines),
-- c.w* 75% to white (the glint), c.a the brightness of this frame, c.ready 0 far to 1 in reach,
-- c.breath and c.twinkle 0..1, c.spin the turn, c.flash the flare of coming in reach.
local c = {}
Q.context = c

local STYLE = {}
Q.DRAW = STYLE

local GROUND, FOOT = Q.GROUND, -0.12

function STYLE.glow(m)
    local s = c.size * (1 + 0.45 * (1 - c.arrive))
    m.v.waveSize, m.v.waveY, m.v.flat = s, 0, 1
    put(m, m.shade, s * 1.15, nil, 0, 0, 0, 0, 0, c.a * 0.30)
    put(m, m.band, s * (0.96 + 0.07 * c.breath), nil, 0, 0, c.r, c.g, c.b, c.a * lerp(0.5, 0.8, c.ready) * (0.8 + 0.2 * c.breath))
    local w = c.a * (lerp(0.28, 0.45, c.ready) + 0.3 * c.flash)
    put(m, m.wisps[1], s * 1.03, nil, 0, 0, c.hr, c.hg, c.hb, w); turn(m.wisps[1], 0.22 * c.spin)
    put(m, m.wisps[2], s * 0.93, nil, 0, 0, c.hr, c.hg, c.hb, w * 0.8); turn(m.wisps[2], 2.1 - 0.31 * c.spin)
    put(m, m.ring, s, nil, 0, 0, c.hr, c.hg, c.hb, c.a * (lerp(0.25, 0.7, c.ready) + 0.25 * c.flash))
    put(m, m.comet, s, nil, 0, 0, c.hr, c.hg, c.hb, c.a * lerp(0.45, 0.95, c.ready)); turn(m.comet, c.spin)
    local orbit = s * 0.37
    for i = 1, 3 do
        local ang = -0.6 * c.spin + i * TWO_PI / 3
        local glint = 0.5 + 0.5 * math.sin(c.phase * 3.1 + i * 2.1)
        put(m, m.motes[i], s * (0.10 + 0.05 * glint), nil, math.cos(ang) * orbit, math.sin(ang) * orbit,
            c.hr, c.hg, c.hb, c.a * c.ready * (0.45 + 0.55 * glint))
    end
    put(m, m.flare, s * (0.34 + 0.1 * c.ready + 0.04 * c.twinkle + 0.3 * c.flash + 0.5 * (1 - c.arrive)), nil, 0, 0,
        c.wr, c.wg, c.wb, c.a * (lerp(0.35, 0.9, c.ready) * (0.7 + 0.3 * c.twinkle) + 0.4 * c.flash))
    turn(m.flare, 0.1 * math.sin(c.phase * 0.5))
end

-- Rings spread on the ground round the object.
function STYLE.ring(m)
    local s, foot = c.size, FOOT * c.size
    m.v.waveSize, m.v.waveY, m.v.flat, m.v.noPing = s * 1.1, foot, GROUND, true
    put(m, m.shade, s * 2.6, s * 2.6 * GROUND * 1.3, 0, foot, 0, 0, 0, c.a * 0.30)
    local pool = s * (1.2 + 0.12 * c.breath)
    put(m, m.pool, pool, pool * GROUND * 1.3, 0, foot, c.r, c.g, c.b, c.a * lerp(0.55, 0.9, c.ready))
    for i, t in ipairs(m.ripples) do
        local spread = (-c.spin * 0.4 + i / 3) % 1
        local w = s * lerp(0.3, 1.7, 1 - (1 - spread) ^ 2) * (0.6 + 0.4 * c.arrive)
        put(m, t, w, w * GROUND, 0, foot, c.hr, c.hg, c.hb, c.a * lerp(0.6, 1, c.ready) * math.min(spread * 6, 1) * (1 - spread) ^ 1.3)
    end
    put(m, m.flare, s * (0.26 + 0.08 * c.ready + 0.04 * c.twinkle + 0.3 * c.flash), nil, 0, foot,
        c.wr, c.wg, c.wb, c.a * (lerp(0.25, 0.8, c.ready) * (0.7 + 0.3 * c.twinkle) + 0.4 * c.flash))
end

-- A column of light rises from the object, sparks climb it.
function STYLE.beam(m)
    local s, foot = c.size, FOOT * c.size
    local h = s * (1.75 + 0.45 * c.ready + 0.25 * c.flash) * (0.25 + 0.75 * c.arrive)
    local mid = foot + h / 2
    m.v.waveSize, m.v.waveY, m.v.flat = s * 0.9, foot, GROUND
    put(m, m.shade, s * 1.5, h * 1.5, 0, mid - h * 0.12, 0, 0, 0, c.a * 0.22)
    local pool = s * (1.1 + 0.1 * c.breath)
    put(m, m.pool, pool, pool * GROUND * 1.3, 0, foot, c.r, c.g, c.b, c.a * lerp(0.55, 0.9, c.ready))
    put(m, m.shaft, s * (0.66 + 0.06 * c.breath + 0.22 * c.flash), h, 0, mid, c.r, c.g, c.b, c.a * lerp(0.5, 0.85, c.ready))
    put(m, m.core, s * (0.3 + 0.03 * c.breath + 0.14 * c.flash), h * 0.94, 0, foot + h * 0.47,
        c.wr, c.wg, c.wb, c.a * (lerp(0.5, 0.95, c.ready) + 0.3 * c.flash))
    for i = 1, 4 do
        local climb = (-c.spin * 0.3 + i / 4) % 1
        local glint = 0.5 + 0.5 * math.sin(c.phase * 3.1 + i * 2.1)
        put(m, m.motes[i], s * (0.13 + 0.05 * glint) * (1 - 0.5 * climb), nil,
            math.sin(-c.spin * 1.3 + i * 1.9) * s * 0.06, foot + climb * h * 0.8,
            c.hr, c.hg, c.hb, c.a * math.sin(math.pi * climb) * lerp(0.55, 1, c.ready))
    end
    put(m, m.flare, s * (0.3 + 0.08 * c.ready + 0.04 * c.twinkle + 0.3 * c.flash), nil, 0, foot,
        c.wr, c.wg, c.wb, c.a * (lerp(0.35, 0.9, c.ready) * (0.7 + 0.3 * c.twinkle) + 0.4 * c.flash))
end

-- An arrow bobs over the object, a light pool lies under it.
function STYLE.arrow(m)
    local s, foot = c.size, FOOT * c.size
    m.v.waveSize, m.v.waveY, m.v.flat = s * 0.9, foot, GROUND
    local hover = s * (0.75 + 0.45 * (1 - c.arrive)) + math.sin(c.phase * 1.5) * s * 0.05
    put(m, m.shade, s * 1.7, s * 1.7 * GROUND * 1.3, 0, foot, 0, 0, 0, c.a * 0.30)
    local pool = s * (0.95 + 0.1 * c.breath)
    put(m, m.pool, pool, pool * GROUND * 1.3, 0, foot, c.r, c.g, c.b, c.a * lerp(0.5, 0.85, c.ready))
    put(m, m.aura, s * (0.9 + 0.12 * c.breath), nil, 0, hover, c.r, c.g, c.b, c.a * lerp(0.45, 0.8, c.ready))
    local arrowA = c.arrive * (0.85 + 0.15 * c.ready)
    put(m, m.arrow, s * 0.45, s * 0.6, 0, hover, 1, 1, 1, arrowA)
    put(m, m.flare, s * (0.3 + 0.2 * c.twinkle + 0.4 * c.flash), nil, 0, hover + s * 0.12,
        c.wr, c.wg, c.wb, c.a * (lerp(0.2, 0.7, c.ready) * c.twinkle + 0.5 * c.flash))
end

-- Glints light up somewhere round the object, fade and come back elsewhere.
function STYLE.stars(m)
    local s = c.size
    m.v.waveSize, m.v.waveY, m.v.flat, m.v.noPing = s, 0, 1, true
    put(m, m.shade, s * 1.9, nil, 0, 0, 0, 0, 0, c.a * 0.28)
    put(m, m.aura, s * (1.55 + 0.12 * c.breath), nil, 0, 0, c.r, c.g, c.b, c.a * lerp(0.4, 0.62, c.ready) * (0.85 + 0.15 * c.breath))
    for i = 1, 3 do
        local climb = (-c.spin * 0.14 + i / 3) % 1
        put(m, m.motes[i], s * 0.11, nil, (i - 2) * s * 0.24 + math.sin(-c.spin * 0.9 + i * 2.3) * s * 0.05,
            (climb - 0.45) * s * 0.8, c.hr, c.hg, c.hb, c.a * math.sin(math.pi * climb) * 0.75)
    end
    local burst = c.flash > (m.v.lastFlash or 0)
    m.v.lastFlash = c.flash
    for i, t in ipairs(m.stars) do
        local gl = m.glints[i]
        if burst or not gl.life or (gl.age or 0) >= gl.life then
            local ang, reach = math.random() * TWO_PI, math.sqrt(math.random())
            gl.x, gl.y = math.cos(ang) * reach, math.sin(ang) * reach
            gl.life, gl.scale = 0.7 + 0.9 * math.random(), 0.55 + 0.75 * math.random()
            -- still (Reduce motion): each glint keeps a fixed place, half lit
            gl.age = c.still and gl.life * (0.3 + 0.07 * i) or (burst and 0 or -0.5 * math.random())
        end
        if not c.still then gl.age = gl.age + c.elapsed * lerp(1, 1.5, c.ready) end
        local shine = gl.age > 0 and math.sin(math.pi * gl.age / gl.life) or 0
        put(m, t, s * 0.55 * gl.scale * (0.4 + 0.6 * shine) * (1 + 0.25 * c.ready), nil, gl.x * s * 0.4, gl.y * s * 0.4,
            c.wr, c.wg, c.wb, c.a * shine * lerp(0.7, 1, c.ready))
    end
end

-- Lays the light out for this frame; `elapsed` 0 draws it as it is, without moving it.
function Q.Draw(m, elapsed)
    elapsed = math.min(elapsed or 0, 0.1)    -- no jump after a frame that stalled
    local S = ns.Skin
    local still = not m.v.pulse or (S and S.Calm and S.Calm()) or false
    if still then
        m.v.appear, m.v.flash = 1, 0
        m.v.ready = (m.v.state == false) and 0 or 1
    else
        m.v.appear = math.min(1, (m.v.appear or 1) + elapsed / Q.ARRIVE)
        local want = (m.v.state == false) and 0 or 1
        local step = elapsed / Q.BLEND
        m.v.ready = (m.v.ready or want) < want and math.min(want, m.v.ready + step) or math.max(want, (m.v.ready or want) - step)
        m.v.flash = math.max(0, (m.v.flash or 0) - elapsed / Q.FLASH)
        m.v.phase = (m.v.phase or 0) + elapsed * TWO_PI / lerp(3.4, 1.7, m.v.ready)
        m.v.spin = (m.v.spin or 0) - elapsed * lerp(0.55, 1.6, m.v.ready)
    end
    local r, g, b = m.v.color[1], m.v.color[2], m.v.color[3]
    c.size, c.elapsed, c.still = m.v.size, elapsed, still
    c.arrive = 1 - (1 - m.v.appear) ^ 3
    c.a = m.v.alpha * c.arrive
    if m.v.leaving then
        local p = m.v.leaving / Q.LEAVE
        c.a = c.a * (1 - p) ^ 2
        c.size = m.v.size * (1 + 0.35 * (1 - (1 - p) ^ 3))
    end
    c.ready, c.flash, c.phase, c.spin = m.v.ready, m.v.flash, m.v.phase or 0, still and 0 or (m.v.spin or 0)
    c.breath = still and 0.5 or 0.5 + 0.5 * math.sin(c.phase)
    c.twinkle = still and 0.7 or 0.5 + 0.5 * math.sin(c.phase * 2.3 + 1.3)
    c.r, c.g, c.b = r, g, b
    c.hr, c.hg, c.hb = lerp(r, 1, 0.55), lerp(g, 1, 0.55), lerp(b, 1, 0.55)
    c.wr, c.wg, c.wb = lerp(r, 1, 0.75), lerp(g, 1, 0.75), lerp(b, 1, 0.75)
    m.v.noPing = nil
    for _, t in ipairs(m.parts) do t:Hide() end
    local draw = STYLE[m.v.style] or STYLE.glow
    draw(m)
    -- the waves: a ring goes out now and then, and one closes on the light when it comes in reach
    if still then return end
    m.v.ping = (m.v.ping or 1) - elapsed
    if m.v.ping <= 0 then
        m.v.ping = lerp(3.8, 2.4, m.v.ready)
        if not m.v.noPing and not m.v.leaving then wave(m, 0.55, 1.45, 1.0, 0.55) end
    end
    for _, w in ipairs(m.waves) do
        if w.age then
            w.age = w.age + elapsed
            local p = w.age / w.duration
            if p >= 1 then
                w.age = nil
            else
                local fade = w.inward and (p < 0.7 and p / 0.7 or (1 - p) / 0.3) or (1 - p) ^ 1.5
                local width = (m.v.waveSize or c.size) * lerp(w.from, w.to, 1 - (1 - p) ^ 2)
                put(m, w.t, width, width * (m.v.flat or 1), 0, m.v.waveY or 0, c.hr, c.hg, c.hb, c.a * w.peak * fade)
            end
        end
    end
end

-- Each frame: reads the reach now and then, moves the light, ends the fade.
function Q.Animate(m, elapsed)
    elapsed = elapsed or 0
    if m.v.leaving then
        m.v.leaving = m.v.leaving + elapsed
        if m.v.leaving >= Q.LEAVE then
            m.v.leaving = nil
            m:Hide()
            return
        end
    else
        m.v.poll = (m.v.poll or 0) - elapsed
        if m.v.poll <= 0 then
            m.v.poll = Q.POLL
            local reach = Q.InReach()
            local want = reach ~= false
            if want ~= m.v.state then
                if m.v.pending ~= want then
                    m.v.pending, m.v.pendingAt = want, 0
                else
                    m.v.pendingAt = m.v.pendingAt + Q.POLL
                end
                -- the first answer counts at once; a change only once it held
                if m.v.state == nil or m.v.pendingAt >= Q.STATE_DELAY then
                    if want and m.v.state == false then
                        m.v.flash = 1
                        wave(m, 1.5, 1.0, 0.35, 0.9, true)
                    end
                    m.v.state, m.v.pending = want, nil
                end
            else
                m.v.pending = nil
            end
        end
    end
    Q.Draw(m, elapsed)
end

-- The object is gone: the light fades where it stood (at once with Reduce motion or in a fight).
function Q.Leave(m)
    if not m:IsShown() or m.v.leaving then return end
    local S = ns.Skin
    local still = not m.v.pulse or (S and S.Calm and S.Calm())
    local ok, x, y = pcall(m.GetCenter, m)
    if still or not ok or type(x) ~= "number" or type(y) ~= "number" or secret(x) or secret(y) then
        m:Hide()
        m.v.guid = nil
        return
    end
    m:ClearAllPoints()
    m:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    m.v.leaving, m.v.guid = 0, nil
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
    f.halo = tex(f, HALO, "BACKGROUND", true)
    f.halo:SetSize(96, 96); f.halo:SetPoint("CENTER")
    -- the picture's ring is 0.74 of its width: a ring 64 across
    f.ring = tex(f, RING, "ARTWORK", true)
    f.ring:SetSize(86, 86); f.ring:SetPoint("CENTER")
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
    -- the thin ring closer to white than the soft band under it, as on the marker
    f.ring:SetVertexColor(c[1] + (1 - c[1]) * 0.55, c[2] + (1 - c[2]) * 0.55, c[3] + (1 - c[3]) * 0.55, a)
    f.halo:SetVertexColor(c[1], c[2], c[3], a * 0.45)
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
        if guid ~= m.v.guid then Q.Arrive(m, guid) end
        m.v.leaving = nil
        if m.v.style ~= Q.Get("style") or m.v.dirty then Q.Style(m); m.v.dirty = false end
        m:ClearAllPoints()
        m:SetPoint("TOP", plate, "BOTTOM", 0, 0)
        m:Show()
    elseif m then
        Q.Leave(m)
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
    "QUEST_LOG_UPDATE", "BAG_UPDATE_DELAYED", "UPDATE_BINDINGS", "CURSOR_CHANGED",
}

local function listen()
    if st.ev then return st.ev end
    local f = CreateFrame("Frame")
    f:SetScript("OnEvent", function(_, event)
        if not st.on then return end
        if event == "BAG_UPDATE_DELAYED" then Q.SoonBags(); return end
        if event == "QUEST_LOG_UPDATE" then st.objectives = nil; Q.SoonBags() end
        if event == "CURSOR_CHANGED" then Q.LearnFromCursor() end
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
    if st.marker then st.marker.v.dirty = true end
    hookBags()
    Q.Refresh()
    Q.PaintBags()
end

function Q.Disable()
    st.on = false
    if st.ev then st.ev:UnregisterAllEvents() end
    Q.RestoreCVars()
    if st.marker then st.marker:Hide(); st.marker.v.leaving, st.marker.v.guid = nil, nil end
    if st.cross then st.cross:Hide() end
    st.guid = nil
    Q.PaintBags()
end

function Q.Changed(opt, value, g)
    if not st.on then return end
    if opt == "world" or opt == "crosshair" or opt == "sound" or opt == "range" or opt == "icons" then
        Q.ApplyCVars(Q.CVars(g or Q.Get))
    end
    if st.marker then st.marker.v.dirty = true end
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
