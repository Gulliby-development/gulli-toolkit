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
local function enableState(name)
    if A.GetAddOnEnableState then return A.GetAddOnEnableState(name, player()) end
    return GetAddOnEnableState(player(), name)
end
local function version() return metadata(ADDON, "Version") end
-- Whether the game would load the addon for this character, and why not ("DISABLED",
-- "INTERFACE_VERSION", "DEP_DISABLED"...).
local function loadable(name)
    local f = A.IsAddOnLoadable or IsAddOnLoadable
    if not f then return true end
    return f(name, player())
end
-- The change is saved at once: without SaveAddOns the game can drop it (the AddOns list resets
-- unsaved changes when it closes), and the module stays off after the reload.
local function setEnabled(name, on)
    local f = on and (A.EnableAddOn or EnableAddOn) or (A.DisableAddOn or DisableAddOn)
    f(name)
    local save = A.SaveAddOns or SaveAddOns
    if save then save() end
end

function ns.Print(msg)
    print("|cff9ad0ffGulli Toolkit|r: " .. msg)
end

-- GulliToolkit.Register(info) or GulliToolkit:Register(info).
-- info: key (required, "QuestCleaner"), open (function), and optional title, desc, icon, slash,
-- category (a key of ns.CATEGORIES) and options: switches the hub shows beside the module,
-- { { label = "Sell gray items", get = function() return db.sell end, set = function(on) ... end,
--     icon = "Interface\\Icons\\INV_Misc_Coin_02" } } (icon optional: a game icon beside the switch).
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

-- Pending on/off changes that need a reload, by key.
ns.pending = {}

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
        if ns.pending[k] ~= nil then
            row.state = "reload"
            row.on = ns.pending[k]
        elseif info then
            row.state, row.on = "ready", true
        elseif addon then
            -- The game's own loader decides: an addon it calls DISABLED is off, whatever the
            -- enable state says for the other characters.
            local ok, reason = loadable(addon)
            row.on = enableState(addon) > 0 and reason ~= "DISABLED"
            if not row.on then
                row.state = "off"
            elseif isLoaded(addon) then
                row.state = "ready"
            elseif ok ~= false then
                row.state = "reload"
            else
                -- Switched on but the game will not load it (out of date, a missing dependency).
                row.state, row.reason = "blocked", reason
            end
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
-- over the name, the line about it, the key and the slash command.
function ns.Filter(rows, category, state, query)
    query = (query or ""):lower():match("^%s*(.-)%s*$")
    local out = {}
    for _, r in ipairs(rows) do
        local ok = (query ~= "" or category == "All" or r.category == category)
            and (state == "all" or (state == "on") == (r.on == true))
        if ok and query ~= "" then
            local text = table.concat({ r.title or "", r.desc or "", r.key, r.slash or "" }, "\n"):lower()
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

-- Switch a module on or off for every character; it takes effect after a reload.
function ns.SetEnabled(row, on)
    if not row.addon then return end
    setEnabled(row.addon, on)
    local now = row.info ~= nil
    if on == now then ns.pending[row.key] = nil else ns.pending[row.key] = on end
    if ns.Refresh then ns.Refresh() end
end

function ns.NeedsReload()
    return next(ns.pending) ~= nil
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON then return end
    self:UnregisterEvent("ADDON_LOADED")
    GulliToolkitDB = GulliToolkitDB or {}
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
    elseif msg:lower() == "help" then
        ns.Print(L.HELP)
    elseif not ns.OpenModule(msg) then
        ns.Print(L.UNKNOWN:format(msg))
        ns.Print(L.HELP)
    end
end

function GulliToolkit_Toggle()
    ns.Toggle()
end
