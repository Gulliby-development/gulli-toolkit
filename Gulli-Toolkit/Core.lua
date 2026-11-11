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
             "AutoQuest", "Tooltip", "XP", "Loot", "Social", "Reminders" }

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
local function setEnabled(name, on)
    local f = on and (A.EnableAddOn or EnableAddOn) or (A.DisableAddOn or DisableAddOn)
    f(name)
end

function ns.Print(msg)
    print("|cff9ad0ffGulli Toolkit|r: " .. msg)
end

-- GulliToolkit.Register(info) or GulliToolkit:Register(info).
-- info: key (required, "QuestCleaner"), open (function), and optional title, desc, icon, slash.
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

local function known(key)
    for _, k in ipairs(ns.KNOWN) do if k == key then return true end end
end

-- Pending on/off changes that need a reload, by key.
ns.pending = {}

-- One row per module for the hub, the known ones first:
-- { key, addon, title, desc, icon, slash, state = "ready" | "off" | "reload" | "missing", info }.
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
        if ns.pending[k] ~= nil then
            row.state = "reload"
            row.on = ns.pending[k]
        elseif info then
            row.state, row.on = "ready", true
        elseif addon then
            row.on = enableState(addon) > 0
            row.state = (row.on and not isLoaded(addon)) and "reload" or (row.on and "ready" or "off")
        else
            row.state = "missing"
        end
        rows[#rows + 1] = row
    end
    return rows
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
