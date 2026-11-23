-- Tests of the Quest item sparkle tweak (Gulli-Toolkit/Tweaks/QuestSparkle.lua) on a small fake
-- client: the game settings it changes and puts back, which objects and bag slots it lights, the
-- marker, the crosshair, the sound and the panel rows for the Tweaks page.

local failures, count = 0, 0
local function test(name, fn)
    count = count + 1
    local ok, err = pcall(fn)
    if not ok then failures = failures + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end

local W = {}

local function frame()
    local f = { shown = false, scripts = {}, events = {}, points = {}, w = 37 }
    local mt = {}
    mt.__index = function(t, k)
        if k == "EnumerateValidItems" or k == "GetBagID" or k == "GetID" then return nil end
        if k == "Show" then return function(s) s.shown = true end end
        if k == "Hide" then return function(s) s.shown = false end end
        if k == "IsShown" then return function(s) return s.shown end end
        if k == "SetScript" then return function(s, n, fn) s.scripts[n] = fn end end
        if k == "HookScript" then return function(s, n, fn) s.scripts["hook" .. n] = fn end end
        if k == "RegisterEvent" then return function(s, e) s.events[e] = true end end
        if k == "UnregisterAllEvents" then return function(s) s.events = {} end end
        if k == "SetPoint" then return function(s, ...) s.points[#s.points + 1] = { ... } end end
        if k == "ClearAllPoints" then return function(s) s.points = {} end end
        if k == "SetText" then return function(s, v) s.text = v end end
        if k == "SetVertexColor" then return function(s, r, g, b, a) s.color = { r, g, b, a } end end
        if k == "SetAlpha" then return function(s, a) s.alpha = a end end
        if k == "GetWidth" then return function(s) return s.w end end
        if k == "GetFrameLevel" then return function() return 3 end end
        if k == "CreateTexture" or k == "CreateFontString" then
            return function() local x = frame(); W.textures[#W.textures + 1] = x; return x end
        end
        return function() end
    end
    return setmetatable(f, mt)
end

local function reset()
    W.cvars = { SoftTargetInteract = "1", SoftTargetNameplateInteract = "0", SoftTargetInteractRange = "10",
        SoftTargetIconInteract = "0", SoftTargetIconGameObject = "0" }
    W.frames, W.textures, W.sounds = {}, {}, {}
    W.soft = nil     -- { guid, name, related, lines }
    W.plate = nil
    W.bags = {}      -- [bag][slot] = { isQuestItem, questID, isActive }
    W.time = 100
    GulliSparkleMarker, GulliSparkleCrosshair = nil, nil
    C_CVar = {
        GetCVar = function(n) return W.cvars[n] end,
        SetCVar = function(n, v) W.cvars[n] = v end,
    }
    CreateFrame = function(_, name)
        local f = frame(); W.frames[#W.frames + 1] = f
        if name then _G[name] = f end
        return f
    end
    UIParent = frame()
    UnitExists = function(u) return u == "softinteract" and W.soft ~= nil end
    UnitGUID = function(u) return u == "softinteract" and W.soft and W.soft.guid or nil end
    UnitName = function(u) return u == "softinteract" and W.soft and W.soft.name or nil end
    C_QuestLog = { UnitIsRelatedToActiveQuest = function() return W.soft and W.soft.related or false end }
    C_TooltipInfo = { GetUnit = function() return W.soft and { lines = W.soft.lines or {} } end }
    C_NamePlate = { GetNamePlateForUnit = function() return W.plate end }
    C_Container = { GetContainerItemQuestInfo = function(bag, slot)
        local b = W.bags[bag] and W.bags[bag][slot]
        return { isQuestItem = b and b[1] or false, questID = b and b[2], isActive = b and b[3] or false }
    end }
    C_Timer = nil
    GetTime = function() return W.time end
    GetBindingKey = function() return "F" end
    GetBindingText = function(k) return k end
    SOUNDKIT = { MAP_PING = 7 }
    PlaySound = function(id) W.sounds[#W.sounds + 1] = id end
    issecretvalue = nil
    UnitIsInInteractRange = nil
    W.calm = nil
    Enum = nil
    GulliToolkitDB = {}
    W.tweak = nil
    W.opts = {}
    ns = { L = setmetatable({}, { __index = function(_, k) return k end }) }
    ns.AddTweak = function(t) W.tweak = t end
    ns.TweakOn = function() return W.on end
    ns.TweakGet = function(_, opt) return W.opts[opt] end
    ns.Skin = { Calm = function() return W.calm end, SetFont = function() end }
    -- the game's own bag window with two slots of bag 0
    local bag = frame(); bag.shown = true
    local b1, b2 = frame(), frame()
    b1.GetBagID = function() return 0 end; b1.GetID = function() return 1 end
    b2.GetBagID = function() return 0 end; b2.GetID = function() return 2 end
    bag.Items = { b1, b2 }
    ContainerFrame1, ContainerFrameCombinedBags = bag, nil
    W.b1, W.b2 = b1, b2
    assert(loadfile("Gulli-Toolkit/Tweaks/QuestSparkle.lua"))("Gulli-Toolkit", ns)
    return ns.Sparkle
end

test("registers on the Tweaks page with its settings", function()
    reset()
    local t = W.tweak
    assert(t and t.key == "questSparkle" and t.group == "quests", "AddTweak not called")
    assert(t.defaults.world and t.defaults.bags and t.defaults.bright, "defaults")
    local kinds = {}
    for _, row in ipairs(t.panel) do
        kinds[row.kind] = true
        assert(row.label, "a row without a label")
        if row.key then assert(t.defaults[row.key] ~= nil, "no default for " .. row.key) end
        if row.kind == "choice" then
            for _, v in ipairs(row.values) do assert(v[1] and v[2], "a choice without a text") end
            local found = false
            for _, v in ipairs(row.values) do if v[1] == t.defaults[row.key] then found = true end end
            assert(found, "the default of " .. row.key .. " is no choice")
        end
        if row.kind == "step" then
            assert(t.defaults[row.key] >= row.min and t.defaults[row.key] <= row.max, row.key .. " default out of range")
        end
    end
    assert(kinds.switch and kinds.choice and kinds.step and kinds.head, "panel kinds")
end)

test("enable sets the interact settings and disable puts the player's values back", function()
    local Q = reset()
    Q.Enable(Q.Get)
    assert(W.cvars.SoftTargetInteract == "3", "keyboard soft interact")
    assert(W.cvars.SoftTargetNameplateInteract == "1", "nameplate on the object")
    assert(W.cvars.SoftTargetInteractRange == "15", "range")
    assert(GulliToolkitDB.sparkleSaved.SoftTargetInteract == "1", "the old value is kept")
    -- a reload enables again: the player's value must stay the saved one
    Q.Enable(Q.Get)
    assert(GulliToolkitDB.sparkleSaved.SoftTargetInteract == "1", "our value saved as the player's")
    Q.Disable()
    assert(W.cvars.SoftTargetInteract == "1" and W.cvars.SoftTargetInteractRange == "10", "not put back")
    assert(W.cvars.SoftTargetNameplateInteract == "0", "nameplate not put back")
    assert(GulliToolkitDB.sparkleSaved == nil, "saved values left")
end)

test("a setting that is unknown to the client is never set", function()
    local Q = reset()
    W.cvars.SoftTargetIconGameObject = nil
    Q.Enable(Q.Get)
    assert(W.cvars.SoftTargetIconGameObject == nil, "set a setting the client lacks")
    Q.Disable()
end)

test("the range is kept between 5 and 15 and switching icons off gives back their settings", function()
    local Q = reset()
    W.opts.range = 40
    assert(Q.CVars(Q.Get).SoftTargetInteractRange == "15")
    W.opts.range = 2
    assert(Q.CVars(Q.Get).SoftTargetInteractRange == "5")
    W.opts.range = nil
    Q.Enable(Q.Get)
    assert(W.cvars.SoftTargetIconInteract == "1")
    W.opts.icons = false
    Q.Changed("icons", false, Q.Get)
    assert(W.cvars.SoftTargetIconInteract == "0", "icon setting not put back")
    assert(W.cvars.SoftTargetInteract == "3", "the rest stays")
    Q.Disable()
end)

test("with world, crosshair and sound off no game setting changes", function()
    local Q = reset()
    W.opts.world, W.opts.crosshair, W.opts.sound = false, false, false
    Q.Enable(Q.Get)
    assert(W.cvars.SoftTargetInteract == "1" and GulliToolkitDB.sparkleSaved == nil)
    Q.Disable()
end)

test("a crash leaves our values: the next load with the tweak off puts them back", function()
    local Q = reset()
    Q.Enable(Q.Get)
    W.on = false
    Q.OnLoad()
    assert(W.cvars.SoftTargetInteract == "1", "not restored at load")
end)

test("tooltip rules: an open objective counts, a done one does not", function()
    local Q = reset()
    assert(Q.TooltipNeeds({ lines = { { type = 0 }, { type = 8, completed = false } } }))
    assert(not Q.TooltipNeeds({ lines = { { type = 8, completed = true } } }))
    assert(Q.TooltipNeeds({ lines = { { type = 17 } } }), "a quest title alone")
    assert(not Q.TooltipNeeds({ lines = { { type = 17 }, { type = 8, completed = true } } }))
    assert(not Q.TooltipNeeds(nil) and not Q.TooltipNeeds({ lines = {} }))
end)

test("marks a quest object on its nameplate, with the crosshair and one sound", function()
    local Q = reset()
    Q.Enable(Q.Get)
    W.plate = frame()
    W.soft = { guid = "GameObject-1", name = "Supply Crate", related = true }
    Q.Refresh()
    local m = _G.GulliSparkleMarker
    assert(m and m.shown, "no marker")
    assert(m.points[1][2] == W.plate, "not on the plate")
    local c = _G.GulliSparkleCrosshair
    assert(c and c.shown, "no crosshair")
    assert(#W.sounds == 1, "no sound")
    Q.Refresh()
    assert(#W.sounds == 1, "rang twice for one object")
    W.soft = nil
    Q.Refresh()
    assert(not m.shown and not c.shown, "left after the object is gone")
    W.soft = { guid = "GameObject-1", name = "Supply Crate", related = true }
    Q.Refresh()
    assert(#W.sounds == 1, "rang again within the gap")
    W.time = 200
    W.soft = nil; Q.Refresh()
    W.soft = { guid = "GameObject-1", name = "Supply Crate", related = true }
    Q.Refresh()
    assert(#W.sounds == 2, "no sound after the gap")
    Q.Disable()
    assert(not m.shown and not c.shown, "left after disable")
end)

test("an object no quest needs gets nothing", function()
    local Q = reset()
    Q.Enable(Q.Get)
    W.plate = frame()
    W.soft = { guid = "GameObject-2", name = "Mailbox", related = false, lines = { { type = 0 } } }
    Q.Refresh()
    assert(not (_G.GulliSparkleMarker and _G.GulliSparkleMarker.shown))
    assert(not (_G.GulliSparkleCrosshair and _G.GulliSparkleCrosshair.shown))
    assert(#W.sounds == 0)
    Q.Disable()
end)

test("a secret guid or name shows nothing it cannot read", function()
    local Q = reset()
    Q.Enable(Q.Get)
    W.plate = frame()
    issecretvalue = function(v) return v == "SECRET" end
    W.soft = { guid = "SECRET", name = "x", related = true }
    Q.Refresh()
    assert(not (_G.GulliSparkleMarker and _G.GulliSparkleMarker.shown), "marked a secret guid")
    W.soft = { guid = "GameObject-3", name = "SECRET", related = true }
    Q.Refresh()
    assert(_G.GulliSparkleCrosshair.text.text == string.format(ns.L.TWP_SPARKLE_PRESS, "F", ns.L.TWP_SPARKLE_OBJECT),
        "a secret name was shown")
    Q.Disable()
end)

test("switches: no marker without world, no crosshair without crosshair", function()
    local Q = reset()
    W.opts.world, W.opts.crosshair, W.opts.sound = false, true, false
    Q.Enable(Q.Get)
    W.plate = frame()
    W.soft = { guid = "GameObject-4", name = "Crate", related = true }
    Q.Refresh()
    assert(not (_G.GulliSparkleMarker and _G.GulliSparkleMarker.shown), "marker with world off")
    assert(_G.GulliSparkleCrosshair.shown, "crosshair")
    W.opts.crosshair = false
    Q.Changed("crosshair", false, Q.Get)
    assert(not _G.GulliSparkleCrosshair.shown, "crosshair with it off")
    assert(#W.sounds == 0, "sound with it off")
    Q.Disable()
end)

test("every style lays out and brightness and size grow", function()
    local Q = reset()
    Q.Enable(Q.Get)
    W.plate = frame()
    W.soft = { guid = "GameObject-5", name = "Crate", related = true }
    Q.Refresh()
    local m = _G.GulliSparkleMarker
    for _, style in ipairs(Q.STYLES) do
        W.opts.style = style
        Q.Style(m, Q.Get)
        local shown = 0
        for _, t in ipairs(m.parts) do if t.shown then shown = shown + 1 end end
        for _, t in ipairs(m.stars) do if t.shown then shown = shown + 1 end end
        assert(shown > 0, style .. " shows nothing")
        Q.Animate(m, 0.1)
    end
    assert(Q.Alpha(5) > Q.Alpha(1) and Q.Alpha(5) <= 1, "brightness")
    assert(Q.Scale(5) > Q.Scale(1), "size")
    W.calm = true
    Q.Animate(m, 0.1)
    assert(m.alpha == 1, "moves with Reduce motion")
    Q.Disable()
end)

test("the light arrives, flares in reach, fades where it stood, and stands still when calm", function()
    local Q = reset()
    Q.Enable(Q.Get)
    W.plate = frame()
    local reach = false
    UnitIsInInteractRange = function() return reach end
    W.soft = { guid = "GameObject-6", name = "Crate", related = true }
    Q.Refresh()
    local m = _G.GulliSparkleMarker
    assert(m.v.appear == 0, "a new object does not arrive")
    Q.Animate(m, 0.2)
    assert(m.v.state == false, "far at first")
    assert(m.v.appear > 0 and m.v.appear < 1, "arrives over time")
    for _ = 1, 10 do Q.Animate(m, 0.1) end
    assert(m.v.appear == 1, "arrived")
    -- in reach: only once it held, then a flare and a ring that closes in
    reach = true
    Q.Animate(m, 0.2)
    assert(m.v.state == false, "a change shows before it held")
    Q.Animate(m, 0.2)
    assert(m.v.state == true and m.v.flash > 0, "no flare in reach")
    local closing = false
    for _, w in ipairs(m.waves) do if w.age and w.inward then closing = true end end
    assert(closing, "no ring closes in")
    -- the same object again does not arrive again
    Q.Refresh()
    assert(m.v.appear == 1, "arrived again for the same object")
    -- gone: fades where it stood, then hides
    m.GetCenter = function() return 300, 200 end
    W.soft = nil
    Q.Refresh()
    assert(m.shown and m.v.leaving == 0, "does not fade where it stood")
    for _ = 1, 6 do Q.Animate(m, 0.1) end
    assert(not m.shown, "still shows after the fade")
    -- back: arrives again
    W.soft = { guid = "GameObject-7", name = "Crate", related = true }
    Q.Refresh()
    assert(m.shown and m.v.appear == 0 and not m.v.leaving)
    -- Reduce motion: whole at once, nothing turns, and it goes at once
    W.calm = true
    local spin = m.v.spin
    Q.Animate(m, 0.5)
    assert(m.v.appear == 1 and m.v.spin == spin, "moves with Reduce motion")
    W.soft = nil
    Q.Refresh()
    assert(not m.shown, "fades with Reduce motion")
    Q.Disable()
end)

test("every style draws the light brighter than its dark veil and whiter in the middle", function()
    local Q = reset()
    Q.Enable(Q.Get)
    W.plate = frame()
    W.soft = { guid = "GameObject-8", name = "Crate", related = true }
    Q.Refresh()
    local m = _G.GulliSparkleMarker
    for _, style in ipairs(Q.STYLES) do
        W.opts.style = style
        Q.Style(m, Q.Get)
        for _ = 1, 8 do Q.Animate(m, 0.1) end
        local c = Q.context
        assert(c.wr >= c.hr and c.hr >= c.r and c.wb > c.b, style .. ": the glint is not whiter")
        local star = false
        for _, t in ipairs(m.stars) do star = star or t.shown end
        assert(m.flare.shown or m.arrow.shown or star, style .. ": no glint")
        assert(m.shade.shown and m.shade.color[1] == 0, style .. ": no dark veil")
    end
    Q.Disable()
end)

test("bags: quest items glow, quest starters only with their switch, nothing when off", function()
    local Q = reset()
    W.bags[0] = { [1] = { true, nil, false }, [2] = { false, 77, false } }
    Q.Enable(Q.Get)
    assert(Q.BagState(0, 1, Q.Get) == "quest" and Q.BagState(0, 2, Q.Get) == "start")
    Q.PaintBags()
    local o1 = Q.state.overlays[W.b1]
    local o2 = Q.state.overlays[W.b2]
    assert(o1 and o1.shown and o2 and o2.shown, "no glow")
    W.opts.bagsStart = false
    Q.Changed("bagsStart", false, Q.Get)
    assert(not o2.shown, "a quest starter glows with its switch off")
    W.opts.bags = false
    Q.Changed("bags", false, Q.Get)
    assert(not o1.shown, "glows with bags off")
    W.opts.bags = nil
    Q.Changed("bags", true, Q.Get)
    assert(o1.shown)
    Q.Disable()
    assert(not o1.shown, "glow left after disable")
end)

test("texts: every key the tweak reads is in every language", function()
    local Q = reset()
    local lns = {}
    GetLocale = function() return "enUS" end
    assert(loadfile("Gulli-Toolkit/Locales.lua"))("Gulli-Toolkit", lns)
    local T = lns.T
    local src = io.open("Gulli-Toolkit/Tweaks/QuestSparkle.lua"):read("*a")
    local keys = {}
    for k in src:gmatch("L%.(TWP?_[%u_]+)") do keys[k] = true end
    for _, s in ipairs(Q.STYLES) do keys["TWP_SPARKLE_S_" .. s:upper()] = true end
    for _, c in ipairs(Q.COLOR_ORDER) do keys["TWP_SPARKLE_C_" .. c:upper()] = true end
    keys.TW_QUESTSPARKLE, keys.TW_QUESTSPARKLE_D = true, true
    for lang, t in pairs(T) do
        for k in pairs(keys) do assert(t[k], lang .. " lacks " .. k) end
        assert(select(2, t.TWP_SPARKLE_YD:gsub("%%d", "")) == 1, lang .. " YD")
        assert(select(2, t.TWP_SPARKLE_PRESS:gsub("%%s", "")) == 2, lang .. " PRESS")
    end
end)

print(string.format("sparkle: %d tests, %d failed", count, failures))
if failures > 0 then os.exit(1) end
