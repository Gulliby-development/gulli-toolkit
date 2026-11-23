-- Cooldown numbers: the retail engine can count cooldowns down on the action buttons
-- (countdownForCooldowns), but WoW Forever's settings window does not offer it. A client without
-- the setting never shows the tweak.

local _, ns = ...

local KEY, CVAR = "cdNumbers", "countdownForCooldowns"
local added

local function add()
    if added or not ns.HasCVar(CVAR) then return end
    added = true
    ns.AddTweak({
        key = KEY, group = "ui", icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
        enable = function() ns.TweakCVar(KEY, CVAR, 1) end,
        disable = function() ns.TweakCVarsRestore(KEY) end,
    })
end

add()
-- Some clients answer about settings only once the player is in the game.
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event)
    if event ~= "PLAYER_LOGIN" then return end
    self:UnregisterEvent("PLAYER_LOGIN")
    add()
end)
ns.CdNumbersAdd = add
