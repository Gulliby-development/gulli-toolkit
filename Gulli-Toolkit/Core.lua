-- The hub of the Gulli modules. A module is a normal addon that also works alone; when this
-- addon is loaded, the module registers here and the hub can open it, list it and switch it.

local ADDON, ns = ...
local L = ns.L

local Toolkit = GulliToolkit or {}
GulliToolkit = Toolkit
Toolkit.modules = Toolkit.modules or {}
Toolkit.api = 1

-- Modules we make, shown in the hub even before they are installed.
ns.KNOWN = { "QuestCleaner", "MobFinder", "GroupBuffs", "Bulletin", "PartyQuests", "InstanceLimit",
             "Attune", "BagSpace", "DungeonPrep", "QuickChat", "Chores", "Restock", "Merchant", "Mail",
             "AutoQuest", "Tooltip", "XP", "Loot", "Social", "Reminders", "CraftProfit" }

-- The hub's categories in sidebar order. A known module has its category here; another module
-- names one of these keys in Register (category = "Items") or in its TOC (## X-Gulli-Category).
ns.CATEGORIES = { "Quests", "Group", "Items", "Social", "Info" }
ns.CATEGORY_OF = {
    QuestCleaner = "Quests", AutoQuest = "Quests", PartyQuests = "Quests",
    GroupBuffs = "Group", DungeonPrep = "Group", InstanceLimit = "Group", Attune = "Group", Loot = "Group",
    BagSpace = "Items", Restock = "Items", Merchant = "Items", Mail = "Items", CraftProfit = "Items",
    Bulletin = "Social", QuickChat = "Social", Social = "Social",
    XP = "Info", Tooltip = "Info", MobFinder = "Info", Reminders = "Info", Chores = "Info",
}

-- Game API wrappers: the C_AddOns namespace with a fallback to the old globals.
local A = C_AddOns or {}
local function numAddOns() return (A.GetNumAddOns or GetNumAddOns)() end
local function addOnInfo(i) return (A.GetAddOnInfo or GetAddOnInfo)(i) end
local function metadata(name, field) return (A.GetAddOnMetadata or GetAddOnMetadata)(name, field) end
local function isLoaded(name) return (A.IsAddOnLoaded or IsAddOnLoaded)(name) end
local function player() return UnitName("player") end
-- Clients differ on how they name "this character" in the enable calls: by name, or by GUID.
-- Both forms are tried; a form the client does not know only fails or changes nothing.
local function charForms()
    local out = {}
    local guid = UnitGUID and UnitGUID("player")
    if type(guid) == "string" and guid ~= "" then out[#out + 1] = guid end
    out[#out + 1] = player()
    return out
end
-- The enable state for this character: 0 off, above 0 on. The lowest answer of the forms wins,
-- so an answer for "some characters" never hides that this one is off.
local function enableState(name)
    local low
    for _, c in ipairs(charForms()) do
        local ok, s
        if A.GetAddOnEnableState then ok, s = pcall(A.GetAddOnEnableState, name, c)
        elseif GetAddOnEnableState then ok, s = pcall(GetAddOnEnableState, c, name) end
        if ok and type(s) == "number" and (not low or s < low) then low = s end
    end
    return low or 0
end
local function version() return metadata(ADDON, "Version") end
local function memoryKB(name)
    local update = A.UpdateAddOnMemoryUsage or UpdateAddOnMemoryUsage
    local get = A.GetAddOnMemoryUsage or GetAddOnMemoryUsage
    if not (update and get) then return nil end
    pcall(update)
    local ok, kb = pcall(get, name)
    return ok and tonumber(kb) or nil
end
-- Whether the game would load the addon for this character, and why not ("DISABLED",
-- "INTERFACE_VERSION", "DEP_DISABLED"...).
local function loadable(name)
    local f = A.IsAddOnLoadable or IsAddOnLoadable
    if not f then return true end
    local first, firstReason
    for _, c in ipairs(charForms()) do
        local ok, can, reason = pcall(f, name, c)
        if ok then
            if reason == "DISABLED" then return false, reason end
            if first == nil then first, firstReason = can, reason end
        end
    end
    if first == nil then return true end
    return first, firstReason
end
-- One state: the game's. The change goes to this character by name and to every character
-- (clients differ on what a call without a name means), and it is saved at once: without
-- SaveAddOns the game can drop it, and the module stays off after the reload.
local function setEnabled(name, on)
    local f = on and (A.EnableAddOn or EnableAddOn) or (A.DisableAddOn or DisableAddOn)
    for _, c in ipairs(charForms()) do pcall(f, name, c) end
    pcall(f, name)
    local save = A.SaveAddOns or SaveAddOns
    if save then save() end
end
-- On for this character, as the game's AddOns list shows it.
local function isOn(name)
    local _, reason = loadable(name)
    return enableState(name) > 0 and reason ~= "DISABLED"
end

function ns.Print(msg)
    print("|cff9ad0ffGulli Toolkit|r: " .. msg)
end

-- GulliToolkit.Register(info) or GulliToolkit:Register(info).
-- info: key (required, "QuestCleaner"), open (function), and optional title, desc, icon, slash,
-- category (a key of ns.CATEGORIES) and options: switches the hub shows beside the module,
-- { { label = "Sell gray items", get = function() return db.sell end, set = function(on) ... end,
--     icon = "Interface\\Icons\\INV_Misc_Coin_02", tip = "Sells gray items at a vendor." } }
-- (icon and tip optional). More optional fields: window (see AGENTS.md), summary = function()
-- return text[, icon] end (one short line for the hub's home page), move = function(on) end
-- (unlock or lock the module's frames on the screen, /gulli move) and reset = function() end
-- (back to the defaults).
function Toolkit.Register(a, b)
    local info = (a == Toolkit) and b or a
    if type(info) ~= "table" or type(info.key) ~= "string" or info.key == "" then return false end
    Toolkit.modules[info.key] = info
    if ns.Refresh then ns.Refresh() end
    return true
end

-- Items no module may sell, delete or move: GulliToolkitDB.protected[itemID] = true.
-- A module asks with GulliToolkit.IsProtected(itemID) before it touches a bag item.
local function itemID(item)
    if type(item) == "number" then return item end
    if type(item) == "string" then return tonumber(item:match("item:(%d+)") or item) end
end

function Toolkit.IsProtected(item)
    local id = itemID(item)
    local db = GulliToolkitDB
    return id ~= nil and db ~= nil and db.protected ~= nil and db.protected[id] == true
end

function Toolkit.Protect(item, on)
    local id = itemID(item)
    if not id then return false end
    GulliToolkitDB = GulliToolkitDB or {}
    GulliToolkitDB.protected = GulliToolkitDB.protected or {}
    GulliToolkitDB.protected[id] = on and true or nil
    if ns.Refresh then ns.Refresh() end
    return true
end

function ns.Protected()
    local ids = {}
    for id in pairs((GulliToolkitDB and GulliToolkitDB.protected) or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end

-- A short line from a module for the hub ("2 dungeon entries left"). The newest come first.
ns.FEED_MAX = 20
function Toolkit.Notify(key, text)
    if type(text) ~= "string" or text == "" then return false end
    GulliToolkitDB = GulliToolkitDB or {}
    local feed = GulliToolkitDB.feed or {}
    GulliToolkitDB.feed = feed
    table.insert(feed, 1, { t = time(), key = key, text = text })
    while #feed > ns.FEED_MAX do table.remove(feed) end
    if ns.Refresh then ns.Refresh() end
    return true
end

function ns.Feed()
    return (GulliToolkitDB and GulliToolkitDB.feed) or {}
end

function Toolkit.ClearFeed()
    if GulliToolkitDB then GulliToolkitDB.feed = {} end
    if ns.Refresh then ns.Refresh() end
end

-- How long ago a feed line came, short: "now", "5 min", "3 h", "2 d".
function ns.Ago(t, now)
    local s = math.max(0, (now or time()) - (tonumber(t) or 0))
    if s < 60 then return L.AGO_NOW end
    if s < 3600 then return L.AGO_MIN:format(math.floor(s / 60)) end
    if s < 86400 then return L.AGO_H:format(math.floor(s / 3600)) end
    return L.AGO_D:format(math.floor(s / 86400))
end

function Toolkit.Open(key)
    if key then return ns.OpenModule(key) end
    ns.Toggle()
    return true
end

-- Addons on disk that say they are Gulli modules: key -> addon folder name.
local function installed()
    local found = {}
    for i = 1, numAddOns() do
        local name = addOnInfo(i)
        local key = name and metadata(name, "X-Gulli-Module")
        if key and key ~= "" then found[key] = name end
    end
    return found
end

local function stripColors(s)
    return s and s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end

local function isCategory(c)
    for _, k in ipairs(ns.CATEGORIES) do if k == c then return true end end
end

local function categoryOf(key, info, addon)
    if info and isCategory(info.category) then return info.category end
    if ns.CATEGORY_OF[key] then return ns.CATEGORY_OF[key] end
    local toc = addon and metadata(addon, "X-Gulli-Category")
    if isCategory(toc) then return toc end
    return "Other"
end

-- The module's switches that the hub can show: each needs a label, get and set.
local function optionsOf(info)
    local out = {}
    if not info or type(info.options) ~= "table" then return out end
    for _, o in ipairs(info.options) do
        if type(o) == "table" and type(o.label) == "string" and type(o.get) == "function"
            and type(o.set) == "function" then
            out[#out + 1] = o
        end
    end
    return out
end

local function known(key)
    for _, k in ipairs(ns.KNOWN) do if k == key then return true end end
end

-- One row per module for the hub, the known ones first:
-- { key, addon, title, desc, icon, slash, category, options,
--   state = "ready" | "off" | "reload" | "blocked" | "missing", on, info, reason }.
function ns.List()
    local disk = installed()
    local keys, seen = {}, {}
    local function add(k) if not seen[k] then seen[k] = true; keys[#keys + 1] = k end end
    for _, k in ipairs(ns.KNOWN) do add(k) end
    local extra = {}
    for k in pairs(disk) do if not known(k) then extra[#extra + 1] = k end end
    for k in pairs(Toolkit.modules) do if not known(k) and not disk[k] then extra[#extra + 1] = k end end
    table.sort(extra)
    for _, k in ipairs(extra) do add(k) end

    local rows = {}
    for _, k in ipairs(keys) do
        local info, addon = Toolkit.modules[k], disk[k]
        local row = { key = k, addon = addon, info = info }
        local title = info and info.title
        if not title and ns.T.en["M_" .. k] then title = L["M_" .. k] end
        if not title and addon then title = stripColors(metadata(addon, "Title")) end
        row.title = title or k
        row.desc = (info and info.desc) or (ns.T.en["D_" .. k] and L["D_" .. k]) or (addon and metadata(addon, "Notes")) or ""
        row.icon = (info and info.icon) or (addon and metadata(addon, "IconTexture"))
        row.slash = info and info.slash
        row.category = categoryOf(k, info, addon)
        row.options = optionsOf(info)
        row.version = addon and metadata(addon, "Version") or nil
        -- New after an update: the version differs from the one the player last opened. The
        -- first version seen is only noted, so a fresh install does not mark everything.
        local seenDB = GulliToolkitDB and GulliToolkitDB.seen
        if row.version and seenDB then
            if seenDB[k] == nil then seenDB[k] = row.version
            elseif seenDB[k] ~= row.version then row.new = true end
        end
        if addon then
            -- The switch is the game's enable state, never a copy of our own. A module that
            -- runs but is switched off, or is switched on but not running, waits for a reload.
            local ok, reason = loadable(addon)
            local loaded = info ~= nil or isLoaded(addon)
            row.on, row.running = isOn(addon), loaded
            if loaded then
                row.state = row.on and "ready" or "reload"
            elseif not row.on then
                row.state = "off"
            elseif ok ~= false then
                row.state = "reload"
            else
                -- Switched on but the game will not load it (out of date, a missing dependency).
                row.state, row.reason = "blocked", reason
            end
        elseif info then
            row.state, row.on, row.running = "ready", true, true
        else
            row.state = "missing"
        end
        rows[#rows + 1] = row
    end
    return rows
end

-- Rows grouped by category in sidebar order, "Other" last: { { key = "Quests", rows = {...} } }.
function ns.Groups(rows)
    local by, out = {}, {}
    for _, r in ipairs(rows) do
        by[r.category] = by[r.category] or {}
        table.insert(by[r.category], r)
    end
    for _, c in ipairs(ns.CATEGORIES) do
        if by[c] then out[#out + 1] = { key = c, rows = by[c] } end
    end
    if by.Other then out[#out + 1] = { key = "Other", rows = by.Other } end
    return out
end

-- Switched-on and total modules per category and for "All": { All = { on = 3, total = 20 }, ... }.
function ns.Counts(rows)
    local c = { All = { on = 0, total = 0 } }
    for _, r in ipairs(rows) do
        c[r.category] = c[r.category] or { on = 0, total = 0 }
        for _, t in ipairs({ c.All, c[r.category] }) do
            t.total = t.total + 1
            if r.on then t.on = t.on + 1 end
        end
    end
    return c
end

-- The rows the hub shows: category ("All" or a key), state ("all", "on", "off") and a search
-- over the name, the line about it, the key, the slash command and the module's switches.
function ns.Filter(rows, category, state, query)
    query = (query or ""):lower():match("^%s*(.-)%s*$")
    local out = {}
    for _, r in ipairs(rows) do
        local ok = (query ~= "" or category == "All" or r.category == category)
            and (state == "all" or (state == "on") == (r.on == true))
        if ok and query ~= "" then
            local parts = { r.title or "", r.desc or "", r.key, r.slash or "" }
            for _, o in ipairs(r.options or {}) do
                parts[#parts + 1] = o.label
                if type(o.tip) == "string" then parts[#parts + 1] = o.tip end
            end
            local text = table.concat(parts, "\n"):lower()
            ok = text:find(query, 1, true) ~= nil
        end
        if ok then out[#out + 1] = r end
    end
    return out
end

-- The hub's scale: the player's own (0.7 to 1.3), made smaller when the window would not fit.
function ns.HubScale(user, screenW, screenH, w, h)
    user = math.max(0.7, math.min(1.3, tonumber(user) or 1))
    local fit = math.min(1, (screenW or w) * 0.96 / w, (screenH or h) * 0.9 / h)
    return user * fit
end

-- The game's own name for why it did not load an addon (ADDON_INTERFACE_VERSION is "Out of
-- date"), else the code itself.
function ns.ReasonText(reason)
    if not reason then return "?" end
    local text = _G["ADDON_" .. reason]
    return type(text) == "string" and text or reason
end

-- The minimap button: GulliToolkitDB.minimap = { hide = true|nil, angle = degrees }.
-- 0 degrees is right of the minimap, 90 is above it; the default sits at the lower left.
ns.MINIMAP_ANGLE = 225

function ns.MinimapAngle()
    local m = GulliToolkitDB and GulliToolkitDB.minimap
    return (m and tonumber(m.angle)) or ns.MINIMAP_ANGLE
end

function ns.MinimapShown()
    local m = GulliToolkitDB and GulliToolkitDB.minimap
    return not (m and m.hide)
end

function ns.SetMinimap(field, value)
    GulliToolkitDB = GulliToolkitDB or {}
    GulliToolkitDB.minimap = GulliToolkitDB.minimap or {}
    GulliToolkitDB.minimap[field] = value
    if ns.PlaceMinimap then ns.PlaceMinimap() end
end

-- Where the button goes: its offset from the minimap's centre. A square minimap puts it on
-- the edge of the square, a round one on the circle.
function ns.MinimapOffset(angle, radius, square)
    local a = math.rad(angle)
    local x, y = math.cos(a), math.sin(a)
    if square then
        local m = math.max(math.abs(x), math.abs(y))
        x, y = x / m, y / m
    end
    return x * radius, y * radius
end

-- The angle of the cursor around the minimap's centre, 0 to 360.
function ns.AngleTo(cx, cy, px, py)
    return math.deg(math.atan2(py - cy, px - cx)) % 360
end

function ns.Version()
    return version() or ""
end

function ns.OpenModule(key)
    local want = (key or ""):lower()
    for k, info in pairs(Toolkit.modules) do
        if k:lower() == want and type(info.open) == "function" then
            info.open()
            return true
        end
    end
    return false
end

-- Switch a module on or off in the game's AddOns list; it takes effect after a reload.
-- Returns false when the game did not take the change.
function ns.SetEnabled(row, on)
    if not row.addon then return end
    setEnabled(row.addon, on)
    local took = isOn(row.addon) == on
    if not took then ns.Print(L.SWITCH_FAILED:format(row.title or row.key)) end
    if ns.Refresh then ns.Refresh() end
    return took
end

-- What the game answers about one module, for a bug report (/gulli debug <module>).
function ns.Debug(key)
    local want = (key or ""):lower()
    for _, row in ipairs(ns.List()) do
        if row.addon and (row.key:lower() == want or row.addon:lower() == want) then
            local lines = { row.addon .. ": loaded=" .. tostring(isLoaded(row.addon)) .. " on=" .. tostring(row.on)
                            .. " state=" .. tostring(row.state) }
            for _, c in ipairs(charForms()) do
                local okS, st = pcall(A.GetAddOnEnableState or function() end, row.addon, c)
                local okL, can, why = pcall(A.IsAddOnLoadable or IsAddOnLoadable or function() end, row.addon, c)
                lines[#lines + 1] = (c:find("%-") and "guid" or "name") .. ": enable=" .. tostring(okS and st or "error")
                    .. " loadable=" .. tostring(okL and can or "error") .. " " .. tostring(why)
            end
            local okA, all = pcall(A.GetAddOnEnableState or function() end, row.addon)
            lines[#lines + 1] = "all: enable=" .. tostring(okA and all or "error")
            for _, l in ipairs(lines) do ns.Print(l) end
            return lines
        end
    end
end

-- A reload is needed when a row's switch and what runs disagree.
function ns.NeedsReload()
    for _, row in ipairs(ns.List()) do
        if row.state == "reload" then return true end
    end
    return false
end

-- The home page ---------------------------------------------------------------------------------

-- One short line per module that gives a summary ("Level 24 in 1 h 10 min"), for the hub's home
-- page: { { row, text, icon } }. Every module that runs counts, also one that waits for a reload
-- after it was switched off. A summary that fails or says nothing is left out.
function ns.Summaries(rows)
    local out = {}
    for _, r in ipairs(rows or ns.List()) do
        local fn = r.info and r.info.summary
        if type(fn) == "function" then
            local ok, text, icon = pcall(fn)
            if ok and type(text) == "string" and text ~= "" then
                out[#out + 1] = { row = r, text = text, icon = (type(icon) == "string" and icon) or r.icon }
            end
        end
    end
    return out
end

-- The state of the whole set for the home page: how many modules are on and run, which wait for
-- a reload, which the game refuses, which were updated, and the memory they use (heaviest first).
function ns.Overview(rows)
    rows = rows or ns.List()
    local o = { on = 0, total = 0, running = 0, reload = {}, blocked = {}, new = {}, heavy = {}, kb = 0 }
    local update = A.UpdateAddOnMemoryUsage or UpdateAddOnMemoryUsage
    local get = A.GetAddOnMemoryUsage or GetAddOnMemoryUsage
    if update and get then pcall(update) end
    for _, r in ipairs(rows) do
        if r.state ~= "missing" or r.info then
            o.total = o.total + 1
            if r.on then o.on = o.on + 1 end
            if r.running then o.running = o.running + 1 end
        end
        if r.state == "reload" then o.reload[#o.reload + 1] = r end
        if r.state == "blocked" then o.blocked[#o.blocked + 1] = r end
        if r.new and r.running then o.new[#o.new + 1] = r end
        if r.running and r.addon and get then
            local ok, kb = pcall(get, r.addon)
            kb = ok and tonumber(kb)
            if kb and kb > 0 then
                o.kb = o.kb + kb
                o.heavy[#o.heavy + 1] = { row = r, kb = kb }
            end
        end
    end
    table.sort(o.heavy, function(a, b) return a.kb > b.kb end)
    return o
end

-- Kilobytes as "820 KB" or "2.4 MB".
function ns.Size(kb)
    if kb >= 1024 then return string.format("%.1f MB", kb / 1024) end
    return string.format("%d KB", math.floor(kb + 0.5))
end

-- The module the hub showed last (it opens there next time), nil for the home page.
function ns.Last()
    return GulliToolkitDB and GulliToolkitDB.last
end

function ns.SetLast(key)
    GulliToolkitDB = GulliToolkitDB or {}
    GulliToolkitDB.last = key
end

-- The player opened the module: it is no longer new.
function ns.MarkSeen(row)
    if not (row and row.version) then return end
    GulliToolkitDB = GulliToolkitDB or {}
    GulliToolkitDB.seen = GulliToolkitDB.seen or {}
    GulliToolkitDB.seen[row.key] = row.version
end

-- Sets of modules for a kind of play, switched on together; the other modules go off.
ns.PRESETS = {
    { key = "Quests", modules = { "QuestCleaner", "AutoQuest", "PartyQuests", "DungeonPrep", "Tooltip", "XP", "Merchant" } },
    { key = "Trade", modules = { "BagSpace", "Restock", "Merchant", "Mail", "CraftProfit", "Tooltip", "Chores" } },
    { key = "Dungeons", modules = { "GroupBuffs", "DungeonPrep", "InstanceLimit", "Attune", "Loot", "Bulletin",
                                    "PartyQuests", "Reminders", "Merchant" } },
    { key = "Minimum", modules = { "Merchant", "Tooltip", "XP" } },
}

local function presetOf(key)
    for _, p in ipairs(ns.PRESETS) do if p.key == key then return p end end
end

-- Switches the preset's modules on and every other installed module off. Returns how many
-- switches changed; they take effect after a reload.
function ns.ApplyPreset(key)
    local p = presetOf(key)
    if not p then return 0 end
    local want = {}
    for _, k in ipairs(p.modules) do want[k] = true end
    local n = 0
    for _, row in ipairs(ns.List()) do
        if row.addon and row.on ~= (want[row.key] == true) then
            ns.SetEnabled(row, want[row.key] == true)
            n = n + 1
        end
    end
    return n
end

-- Every installed module of a category on or off at once.
function ns.SetGroup(category, on)
    local n = 0
    for _, row in ipairs(ns.List()) do
        if row.addon and row.category == category and row.on ~= on then
            ns.SetEnabled(row, on)
            n = n + 1
        end
    end
    return n
end

-- One place to move every frame on the screen: each module with move(on) unlocks its frames.
ns.moving = false
function ns.SetMoving(on)
    ns.moving = on and true or false
    local n = 0
    for _, info in pairs(Toolkit.modules) do
        if type(info.move) == "function" and pcall(info.move, ns.moving) then n = n + 1 end
    end
    if ns.MoveOverlay then ns.MoveOverlay(ns.moving and n > 0) end
    if ns.Refresh then ns.Refresh() end
    return n
end

-- The module's own defaults again.
function ns.Reset(row)
    local fn = row and row.info and row.info.reset
    if type(fn) ~= "function" then return false end
    local ok = pcall(fn)
    if ns.Refresh then ns.Refresh() end
    return ok
end

function ns.Memory(row)
    local kb = row and row.addon and memoryKB(row.addon)
    if not kb then return nil end
    return ns.Size(kb)
end

-- Export and import of every Gulli setting as one line of text --------------------------------

-- The saved variables of the toolkit and every installed module.
function ns.SavedNames()
    local names, seen = { "GulliToolkitDB" }, { GulliToolkitDB = true }
    local addons = { ADDON }
    for _, a in pairs(installed()) do addons[#addons + 1] = a end
    for _, a in ipairs(addons) do
        for _, field in ipairs({ "SavedVariables", "SavedVariablesPerCharacter" }) do
            for n in tostring(metadata(a, field) or ""):gmatch("[%w_]+") do
                if n:match("^Gulli") and not seen[n] then seen[n] = true; names[#names + 1] = n end
            end
        end
    end
    table.sort(names)
    return names
end

-- "|" starts an escape in the game's edit boxes, so it never appears in the text.
local ESC = { ["\\"] = "\\\\", ['"'] = '\\"', ["\n"] = "\\n", ["|"] = "\\p" }
local UNESC = { ["\\"] = "\\", ['"'] = '"', n = "\n", p = "|" }

local function write(v, out, depth)
    local t = type(v)
    if t == "string" then
        out[#out + 1] = '"' .. v:gsub('[\\"\n|]', ESC) .. '"'
    elseif t == "number" then
        out[#out + 1] = (v == math.floor(v) and math.abs(v) < 2 ^ 53) and string.format("%d", v)
            or string.format("%.14g", v)
    elseif t == "boolean" then
        out[#out + 1] = v and "T" or "F"
    elseif t == "table" and depth < 30 then
        local keys = {}
        for k in pairs(v) do
            if type(k) == "string" or type(k) == "number" then keys[#keys + 1] = k end
        end
        table.sort(keys, function(a, b)
            if type(a) == type(b) then return a < b end
            return type(a) == "number"
        end)
        out[#out + 1] = "{"
        for _, k in ipairs(keys) do
            local before = #out
            write(k, out, depth + 1)
            out[#out + 1] = "="
            write(v[k], out, depth + 1)
            if out[#out] == "=" then
                for i = #out, before + 1, -1 do out[i] = nil end
            else
                out[#out + 1] = ";"
            end
        end
        out[#out + 1] = "}"
    end
end

function ns.Serialize(v)
    local out = {}
    write(v, out, 0)
    return table.concat(out)
end

-- Reads what ns.Serialize wrote; anything else is refused. Never runs the text.
function ns.Deserialize(s)
    local pos = 1
    local function fail() error("bad", 0) end
    local value
    local function str()
        local buf = {}
        pos = pos + 1
        while true do
            local c = s:sub(pos, pos)
            if c == "" then fail() end
            if c == '"' then pos = pos + 1; return table.concat(buf) end
            if c == "\\" then
                local e = UNESC[s:sub(pos + 1, pos + 1)]
                if not e then fail() end
                buf[#buf + 1] = e
                pos = pos + 2
            else
                buf[#buf + 1] = c
                pos = pos + 1
            end
        end
    end
    value = function(depth)
        if depth > 30 then fail() end
        local c = s:sub(pos, pos)
        if c == '"' then return str() end
        if c == "T" then pos = pos + 1; return true end
        if c == "F" then pos = pos + 1; return false end
        if c == "{" then
            pos = pos + 1
            local t = {}
            while s:sub(pos, pos) ~= "}" do
                local k = value(depth + 1)
                if type(k) ~= "string" and type(k) ~= "number" then fail() end
                if s:sub(pos, pos) ~= "=" then fail() end
                pos = pos + 1
                t[k] = value(depth + 1)
                if s:sub(pos, pos) ~= ";" then fail() end
                pos = pos + 1
            end
            pos = pos + 1
            return t
        end
        local num = s:match("^%-?[%d%.]+[eE]?[%-+]?%d*", pos)
        if not num or not tonumber(num) then fail() end
        pos = pos + #num
        return tonumber(num)
    end
    local ok, v = pcall(value, 0)
    if not ok or pos ~= #s + 1 then return nil end
    return v
end

local PREFIX = "GULLI1:"

-- Every Gulli setting as one line to copy to another computer, phone or handheld.
function ns.Export()
    local all = {}
    for _, n in ipairs(ns.SavedNames()) do
        if type(_G[n]) == "table" then all[n] = _G[n] end
    end
    return PREFIX .. ns.Serialize(all)
end

-- Loads a line from ns.Export. Returns the number of saved variables set, or nil when the text
-- is not ours. The modules read them after a reload.
function ns.Import(text)
    text = tostring(text or ""):match("^%s*(.-)%s*$")
    if text:sub(1, #PREFIX) ~= PREFIX then return nil end
    local all = ns.Deserialize(text:sub(#PREFIX + 1))
    if type(all) ~= "table" then return nil end
    local n = 0
    for name, v in pairs(all) do
        if type(name) == "string" and name:match("^Gulli[%w_]*DB$") and type(v) == "table" then
            _G[name] = v
            n = n + 1
        end
    end
    return n
end

-- Versions in the group --------------------------------------------------------------------------

-- -1, 0 or 1 by the numbers of two versions ("1.10.0" is newer than "1.9.2").
function ns.CompareVersions(a, b)
    local pa, pb = {}, {}
    for n in tostring(a or ""):gmatch("%d+") do pa[#pa + 1] = tonumber(n) end
    for n in tostring(b or ""):gmatch("%d+") do pb[#pb + 1] = tonumber(n) end
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x < y and -1 or 1 end
    end
    return 0
end

ns.VERSION_PREFIX = "GulliTK"

-- Our versions as addon messages, at most 240 characters each: "V|Core=1.6.0|XP=1.4.0".
function ns.VersionMessages()
    local parts = { "Core=" .. (version() or "0") }
    for _, row in ipairs(ns.List()) do
        if row.state == "ready" and row.version then parts[#parts + 1] = row.key .. "=" .. row.version end
    end
    local out, cur = {}, "V"
    for _, p in ipairs(parts) do
        if #cur + 1 + #p > 240 then out[#out + 1] = cur; cur = "V" end
        cur = cur .. "|" .. p
    end
    out[#out + 1] = cur
    return out
end

-- Newer versions a group member has: { { key, theirs, ours } }, each told once per session.
local told = {}
function ns.ReadVersions(msg)
    local newer = {}
    if type(msg) ~= "string" or msg:sub(1, 2) ~= "V|" then return newer end
    local mine = { Core = version() }
    for _, row in ipairs(ns.List()) do
        if row.state == "ready" then mine[row.key] = row.version end
    end
    for key, ver in msg:gmatch("|([%w_]+)=([%d%.]+)") do
        if mine[key] and ns.CompareVersions(ver, mine[key]) > 0
            and (not told[key] or ns.CompareVersions(ver, told[key]) > 0) then
            told[key] = ver
            newer[#newer + 1] = { key = key, theirs = ver, ours = mine[key] }
        end
    end
    return newer
end

local function sendVersions()
    local C = C_ChatInfo
    if not (C and C.SendAddonMessage) or not IsInGroup or not IsInGroup() then return end
    local channel = (IsInRaid and IsInRaid()) and "RAID" or "PARTY"
    for _, m in ipairs(ns.VersionMessages()) do pcall(C.SendAddonMessage, ns.VERSION_PREFIX, m, channel) end
end

function ns.OnVersions(msg)
    for _, n in ipairs(ns.ReadVersions(msg)) do
        local name = n.key == "Core" and L.TITLE or (ns.T.en["M_" .. n.key] and L["M_" .. n.key]) or n.key
        ns.Print(L.NEWER_VERSION:format(name, n.theirs, n.ours))
    end
end

-- /gulli help: the toolkit's commands, then each module's.
function ns.HelpLines()
    local lines = { L.HELP, L.HELP_MORE }
    for _, row in ipairs(ns.List()) do
        if row.slash and row.state == "ready" then lines[#lines + 1] = row.slash .. "  " .. row.title end
    end
    return lines
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("CHAT_MSG_ADDON")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
local lastSent = 0
events:SetScript("OnEvent", function(self, event, a, b, c, d)
    if event == "PLAYER_REGEN_DISABLED" then
        -- Nothing moves in combat: a fight ends the move mode.
        if ns.moving then ns.SetMoving(false) end
        return
    end
    if event == "CHAT_MSG_ADDON" then
        local who = type(d) == "string" and d:match("^[^%-]+")
        if a == ns.VERSION_PREFIX and who and who ~= player() then ns.OnVersions(b) end
        return
    end
    if event ~= "ADDON_LOADED" then
        -- At most once a minute, so a busy raid roster does not flood the channel.
        if time() - lastSent >= 60 then lastSent = time(); sendVersions() end
        return
    end
    if a ~= ADDON then return end
    self:UnregisterEvent("ADDON_LOADED")
    GulliToolkitDB = GulliToolkitDB or {}
    GulliToolkitDB.seen = GulliToolkitDB.seen or {}
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, ns.VERSION_PREFIX)
    end
    if ns.RegisterSettings then ns.RegisterSettings() end
    if ns.BuildMinimap then ns.BuildMinimap() end
end)

SLASH_GULLITOOLKIT1 = "/gulli"
SLASH_GULLITOOLKIT2 = "/gullitoolkit"
SlashCmdList.GULLITOOLKIT = function(msg)
    msg = (msg or ""):match("^%s*(.-)%s*$")
    if msg == "" then
        ns.Toggle()
    elseif msg:lower():match("^protect") then
        local link = msg:match("^%S+%s+(.+)$")
        local id = link and itemID(link)
        if not id then ns.Print(L.PROTECT_HINT); return end
        local on = not Toolkit.IsProtected(id)
        Toolkit.Protect(id, on)
        ns.Print((on and L.PROTECT_ON or L.PROTECT_OFF):format(link))
    elseif msg:lower() == "minimap" then
        local on = not ns.MinimapShown()
        ns.SetMinimap("hide", (not on) or nil)
        ns.Print(on and L.MINIMAP_ON or L.MINIMAP_OFF)
    elseif msg:lower() == "move" then
        local n = ns.SetMoving(not ns.moving)
        ns.Print(n == 0 and L.MOVE_NONE or (ns.moving and L.MOVE_ON or L.MOVE_OFF))
    elseif msg:lower():match("^debug%s") then
        if not ns.Debug(msg:match("^%S+%s+(.+)$")) then ns.Print(L.UNKNOWN:format(msg)) end
    elseif msg:lower() == "help" then
        for _, l in ipairs(ns.HelpLines()) do ns.Print(l) end
    elseif not ns.OpenModule(msg) then
        ns.Print(L.UNKNOWN:format(msg))
        ns.Print(L.HELP)
    end
end

function GulliToolkit_Toggle()
    ns.Toggle()
end
