-- Tweaks: small switches that make the game nicer, on one page of the hub. Two kinds of rows:
-- the toolkit's own tweaks (each in its own file under Tweaks\, added through ns.AddTweak) and
-- the settings modules lend the page through the optional `tweaks` field of their Register.
-- This file holds the rules (the list, the filter, the counts, Recommended and Turn all off);
-- TweaksUI.lua only shows them.

local _, ns = ...
local L = ns.L

-- The groups in the order of the filter track. A new group needs room there: the Russian
-- track fills the centre already, so an eighth group needs a wrap or an overflow menu first.
ns.TWEAK_GROUPS = { "level", "quests", "combat", "loot", "people", "ui", "requests" }
ns.TWEAK_GROUP_ICON = {
    all = "Interface\\Icons\\INV_Scroll_02",
    on = "Interface\\Icons\\Spell_ChargePositive",
    level = "Interface\\Icons\\Ability_Rogue_Sprint",
    quests = "Interface\\Icons\\INV_Scroll_03",
    combat = "Interface\\Icons\\INV_Sword_04",
    loot = "Interface\\Icons\\INV_Misc_Bag_10",
    people = "Interface\\Icons\\INV_Misc_Head_Human_01",
    ui = "Interface\\Icons\\Trade_Engineering",
    requests = "Interface\\Icons\\INV_Letter_15",
}

-- The own tweaks in page order, whatever order their files load in. A key that no file adds
-- is skipped, so a tweak can join in a later release without a gap on the page.
ns.TWEAK_ORDER = {
    "levelShot", "spellRanks", "trainAll",
    "skipGossip", "questSparkle", "rewardValue", "hideTracker", "plateMarks", "questSounds",
    "macros", "swingStyle", "errorFilter",
    "appearances", "autoBags",
    "guildInvite", "guildMotd",
    "gameSettings", "cdNumbers", "muteSounds", "iconSearch",
}

ns.TWEAKS = {}
local byKey = {}

local function isGroup(g)
    for _, k in ipairs(ns.TWEAK_GROUPS) do if k == g then return true end end
end

-- A tweak: { key, group, icon, star (in the Recommended set), shift (it acts for the player,
-- so Shift skips it once), defaults = { opt = value }, panel = { parts under its row },
-- enable = function(get), disable = function(), changed = function(opt, value, get) }.
-- Texts: TW_<KEY> the name, TW_<KEY>_D one line, TW_<KEY>_T the tooltip (optional).
function ns.AddTweak(t)
    if type(t) ~= "table" or type(t.key) ~= "string" or not isGroup(t.group) then return false end
    if not byKey[t.key] then ns.TWEAKS[#ns.TWEAKS + 1] = t end
    byKey[t.key] = t
    local rank = {}
    for i, k in ipairs(ns.TWEAK_ORDER) do rank[k] = i end
    table.sort(ns.TWEAKS, function(a, b)
        local ra, rb = rank[a.key] or 999, rank[b.key] or 999
        if ra ~= rb then return ra < rb end
        return a.key < b.key
    end)
    -- A tweak added after login (a file that loads late) starts at once when it is on.
    if ns.tweaksStarted and ns.TweakOn(t.key) then ns.StartTweak(t) end
    return true
end

function ns.Tweak(key) return byKey[key] end

local function db()
    GulliToolkitDB = GulliToolkitDB or {}
    GulliToolkitDB.tweaks = GulliToolkitDB.tweaks or {}
    return GulliToolkitDB.tweaks
end

local function saved(key)
    local all = db()
    all[key] = all[key] or {}
    return all[key]
end

function ns.TweakOn(key)
    local s = GulliToolkitDB and GulliToolkitDB.tweaks and GulliToolkitDB.tweaks[key]
    return s ~= nil and s.on == true
end

-- A setting of a tweak: the saved one, else its default.
function ns.TweakGet(key, opt)
    local s = GulliToolkitDB and GulliToolkitDB.tweaks and GulliToolkitDB.tweaks[key]
    if s and s[opt] ~= nil then return s[opt] end
    local t = byKey[key]
    return t and t.defaults and t.defaults[opt]
end

local function getter(key) return function(opt) return ns.TweakGet(key, opt) end end
ns.TweakGetter = getter

-- Every tweak runs in a pcall: one that breaks never stops the others or the hub.
function ns.StartTweak(t)
    if t.running then return end
    t.running = true
    if type(t.enable) == "function" then
        local ok, err = pcall(t.enable, getter(t.key))
        if not ok and ns.RecordError then ns.RecordError("Tweak " .. t.key .. ": " .. tostring(err), nil, nil, "Gulli-Toolkit") end
    end
end

function ns.StopTweak(t)
    if not t.running then return end
    t.running = false
    if type(t.disable) == "function" then
        local ok, err = pcall(t.disable)
        if not ok and ns.RecordError then ns.RecordError("Tweak " .. t.key .. ": " .. tostring(err), nil, nil, "Gulli-Toolkit") end
    end
end

function ns.SetTweak(key, on)
    local t = byKey[key]
    if not t then return false end
    saved(key).on = on and true or nil
    if on then ns.StartTweak(t) else ns.StopTweak(t) end
    if ns.Refresh then ns.Refresh() end
    return true
end

function ns.SetTweakOpt(key, opt, value)
    local t = byKey[key]
    if not t then return false end
    saved(key)[opt] = value
    if t.running then
        if type(t.changed) == "function" then
            local ok, err = pcall(t.changed, opt, value, getter(key))
            if not ok and ns.RecordError then ns.RecordError("Tweak " .. key .. ": " .. tostring(err), nil, nil, "Gulli-Toolkit") end
        else
            ns.StopTweak(t)
            ns.StartTweak(t)
        end
    end
    return true
end

-- Shift held at the moment a tweak would act: it leaves this one alone.
function ns.TweakSkip()
    return IsShiftKeyDown ~= nil and IsShiftKeyDown() == true
end

-- Registers an event only when the client has it: one unknown name raises an error, and a
-- tweak may listen to a retail and a classic name for the same thing.
function ns.TweakListen(frame, event)
    if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then return false end
    return (pcall(frame.RegisterEvent, frame, event))
end

-- Starts the tweaks that are on, once the game has loaded the player.
function ns.StartTweaks()
    ns.tweaksStarted = true
    for _, t in ipairs(ns.TWEAKS) do
        if ns.TweakOn(t.key) then ns.StartTweak(t) end
    end
end

-- The settings a module lends the page: { key, group, label, desc, icon, tip, get, set, panel }.
-- panel: parts like an own tweak's, each (but a head) with its own get() and set(value).
local function moduleTweaks(info)
    local out = {}
    if not info or type(info.tweaks) ~= "table" then return out end
    for _, o in ipairs(info.tweaks) do
        if type(o) == "table" and type(o.key) == "string" and type(o.label) == "string"
            and type(o.get) == "function" and type(o.set) == "function" and isGroup(o.group) then
            out[#out + 1] = o
        end
    end
    return out
end

-- Every row of the page, own tweaks first in their order, then the modules' in the hub's
-- order: { kind = "own"|"module", key, group, icon, label, desc, tip, star, shift, on, live,
-- tweak (own), module = row of ns.List (module) }. A module row is live when the module runs
-- and is not paused; a row that is not live shows dim with a way to the module.
function ns.TweakRows(list)
    local out = {}
    for _, t in ipairs(ns.TWEAKS) do
        local K = t.key:upper()
        out[#out + 1] = {
            kind = "own", key = t.key, group = t.group, icon = t.icon, tweak = t,
            label = L["TW_" .. K], desc = L["TW_" .. K .. "_D"],
            tip = ns.T.en["TW_" .. K .. "_T"] and L["TW_" .. K .. "_T"] or nil,
            star = t.star == true, shift = t.shift == true, panel = t.panel,
            on = ns.TweakOn(t.key), live = true,
        }
    end
    for _, row in ipairs(list or ns.List()) do
        for _, o in ipairs(moduleTweaks(row.info)) do
            local live = row.state == "ready" and not row.paused
            local ok, on = pcall(o.get)
            out[#out + 1] = {
                kind = "module", key = row.key .. ":" .. o.key, group = o.group, icon = o.icon or row.icon,
                label = o.label, desc = o.desc or "", tip = o.tip, shift = o.shift == true,
                on = live and ok and on == true, live = live, module = row, set = o.set,
                panel = type(o.panel) == "table" and o.panel or nil,
            }
        end
    end
    return out
end

-- How a row's panel reads and sets its parts: get(opt), set(opt, value). An own tweak keeps them
-- in its saved options; a module's part carries its own get() and set(value), on the same saved
-- keys as the module's window.
function ns.TweakPanelAccess(r)
    if r.kind == "own" then
        return ns.TweakGetter(r.key), function(opt, value) return ns.SetTweakOpt(r.key, opt, value) end
    end
    local parts = {}
    for _, part in ipairs(r.panel or {}) do
        if type(part) == "table" and part.key then parts[part.key] = part end
    end
    local function get(opt)
        local part = parts[opt]
        if not part or type(part.get) ~= "function" then return nil end
        local ok, v = pcall(part.get)
        if ok then return v end
    end
    local function set(opt, value)
        local part = parts[opt]
        if not part or type(part.set) ~= "function" then return false end
        return (pcall(part.set, value))
    end
    return get, set
end

-- The rows one filter shows: "all", "on" or a group, and a search over the name, the line,
-- the tooltip and the module's name.
function ns.TweakFilter(rows, filter, query)
    query = (query or ""):lower():match("^%s*(.-)%s*$")
    local out = {}
    for _, r in ipairs(rows) do
        local ok = filter == "all" or (filter == "on" and r.on) or r.group == filter
        if ok and query ~= "" then
            local text = table.concat({ r.label or "", r.desc or "", r.tip or "",
                r.module and r.module.title or "" }, "\n"):lower()
            ok = text:find(query, 1, true) ~= nil
        end
        if ok then out[#out + 1] = r end
    end
    return out
end

-- On and total per group, and for "all": { all = { on, total }, level = { ... }, ... }.
function ns.TweakCounts(rows)
    local c = { all = { on = 0, total = 0 } }
    for _, g in ipairs(ns.TWEAK_GROUPS) do c[g] = { on = 0, total = 0 } end
    for _, r in ipairs(rows) do
        for _, t in ipairs({ c.all, c[r.group] }) do
            t.total = t.total + 1
            if r.on then t.on = t.on + 1 end
        end
    end
    c.on = { on = c.all.on, total = c.all.on }
    return c
end

-- The rows grouped for the page: { { key = "level", rows = { ... } }, ... }, empty groups left out.
function ns.TweakGroups(rows)
    local by, out = {}, {}
    for _, r in ipairs(rows) do
        by[r.group] = by[r.group] or {}
        table.insert(by[r.group], r)
    end
    for _, g in ipairs(ns.TWEAK_GROUPS) do
        if by[g] then out[#out + 1] = { key = g, rows = by[g] } end
    end
    return out
end

-- Recommended and Turn all off change only the own tweaks, never a module's settings. Each
-- returns what was on before, for Undo, and how many it changed.
local function snapshot()
    local was = {}
    for _, t in ipairs(ns.TWEAKS) do was[t.key] = ns.TweakOn(t.key) end
    return was
end

function ns.TweaksRecommended()
    local was, n = snapshot(), 0
    for _, t in ipairs(ns.TWEAKS) do
        if t.star and not was[t.key] then ns.SetTweak(t.key, true); n = n + 1 end
    end
    return was, n
end

function ns.TweaksAllOff()
    local was, n = snapshot(), 0
    for _, t in ipairs(ns.TWEAKS) do
        if was[t.key] then ns.SetTweak(t.key, false); n = n + 1 end
    end
    return was, n
end

function ns.TweaksRestore(was)
    for _, t in ipairs(ns.TWEAKS) do
        if was[t.key] ~= nil and was[t.key] ~= ns.TweakOn(t.key) then ns.SetTweak(t.key, was[t.key]) end
    end
end

function ns.RecommendedCount()
    local n = 0
    for _, t in ipairs(ns.TWEAKS) do if t.star then n = n + 1 end end
    return n
end

-- The tweaks start at PLAYER_LOGIN: the saved settings are there and the game knows the player.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    ns.StartTweaks()
end)
