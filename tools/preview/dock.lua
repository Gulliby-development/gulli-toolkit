-- Builds a module window inside the hub (/gulli) on the fake frames and writes it as HTML.
-- Run from the repository root: lua5.1 tools/preview/dock.lua <test folder> <out.html> [scene]
-- The module's scene (tools/preview/scenes.lua) fills its fake client; then the hub is loaded
-- next to it, the module registers its window and the hub opens it inside.
local name, out, scene = arg[1], arg[2], arg[3] or "default"
local R = dofile("tools/preview/frames.lua")
local scenes = dofile("tools/preview/scenes.lua")
local W = dofile("tests/" .. name .. "/wow.lua")

local s = scenes[name] and scenes[name][scene]
local spec = s and s.spec or {}
spec.class = spec.class or "MAGE"
spec.locale = os.getenv("LOCALE") or spec.locale
if Fake then Fake(spec) end
R.Install(W)
if s and s.before then s.before(W, R) end
local mod = Load()
if s and s.open then s.open(mod, W, R) else mod.Toggle() end
if W.RunTimers then pcall(W.RunTimers) end
local win = assert(mod.Window, name .. " has no ns.Window")()
win:Hide()

-- The hub, loaded as the game would load Gulli-Toolkit beside the module.
local key = name
for _, k in ipairs({ "QuestCleaner", "MobFinder", "GroupBuffs", "Bulletin", "PartyQuests", "InstanceLimit",
    "Attune", "BagSpace", "DungeonPrep", "QuickChat", "Chores", "Restock", "Merchant", "Mail", "AutoQuest",
    "Tooltip", "XP", "Loot", "Social", "Reminders", "CraftProfit" }) do
    if k:lower() == name then key = k end
end
local addons = { { "Gulli-Toolkit" }, { "Gulli-" .. key, key } }
C_AddOns = {
    GetNumAddOns = function() return #addons end,
    GetAddOnInfo = function(i) return addons[i] and addons[i][1] end,
    GetAddOnMetadata = function(n, field)
        for _, a in ipairs(addons) do
            if a[1] == n then
                if field == "X-Gulli-Module" then return a[2] end
                if field == "Version" then return "1.4.0" end
            end
        end
    end,
    IsAddOnLoaded = function() return true end,
    GetAddOnEnableState = function() return 2 end,
    EnableAddOn = function() end, DisableAddOn = function() end,
}
local savedSlash = SlashCmdList
SlashCmdList = SlashCmdList or {}
local hub = { }
for _, f in ipairs({ "Locales.lua", "Core.lua", "Skin.lua", "UI.lua" }) do
    assert(loadfile("Gulli-Toolkit/" .. f))("Gulli-Toolkit", hub)
end
SlashCmdList = savedSlash or SlashCmdList
GulliToolkit.Register({ key = key, open = function() end, window = function() return win end,
    slash = win.sub and win.sub:GetText() or nil, icon = "Interface\\AddOns\\Gulli-" .. key .. "\\icon" })
hub.Toggle()
hub.Enter(key)
if W.RunTimers then pcall(W.RunTimers) end

local fh = assert(io.open(out, "w"))
fh:write(R.Html(_G.GulliToolkitFrame, 24))
fh:close()
for _, o in ipairs(R.Overlaps(_G.GulliToolkitFrame)) do
    io.stderr:write(name .. ": overlap: " .. o[1]:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. " / " ..
        o[2]:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. "\n")
end
