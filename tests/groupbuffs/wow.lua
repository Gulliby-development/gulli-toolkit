-- A fake WoW client for tests: just the API Gulli-GroupBuffs calls.
-- Fake{ class = "PRIEST", known = {...}, units = {...}, raid = {...} } sets the globals,
-- Load() runs the addon files on it in TOC order and returns the addon table.

local W = {}
W.SECRET = setmetatable({}, { __tostring = function() return "secret" end })

W.SPELLS = {
    [1243] = "Power Word: Fortitude", [21562] = "Prayer of Fortitude",
    [14752] = "Divine Spirit", [27681] = "Prayer of Spirit",
    [976] = "Shadow Protection", [27683] = "Prayer of Shadow Protection",
    [588] = "Inner Fire",
    [1459] = "Arcane Intellect", [23028] = "Arcane Brilliance",
    [1126] = "Mark of the Wild", [21849] = "Gift of the Wild", [467] = "Thorns",
    [19740] = "Blessing of Might", [19742] = "Blessing of Wisdom", [20217] = "Blessing of Kings",
    [20911] = "Blessing of Sanctuary", [25782] = "Greater Blessing of Might",
    [25894] = "Greater Blessing of Wisdom", [25898] = "Greater Blessing of Kings",
    [25899] = "Greater Blessing of Sanctuary",
    [324] = "Lightning Shield", [8017] = "Rockbiter Weapon", [8024] = "Flametongue Weapon",
    [6673] = "Battle Shout", [168] = "Frost Armor", [7302] = "Ice Armor", [6117] = "Mage Armor",
    [687] = "Demon Skin", [706] = "Demon Armor", [16864] = "Omen of Clarity", [25780] = "Righteous Fury",
    [465] = "Devotion Aura", [7294] = "Retribution Aura", [13165] = "Aspect of the Hawk",
}

-- A frame that remembers its attributes, scripts and wrapped snippets.
local function frame()
    local f = { attrs = {}, scripts = {}, hooks = {}, shown = true }
    return setmetatable(f, { __index = function(t, k)
        if k == "SetAttribute" then return function(self, n, v) self.attrs[n] = v end end
        if k == "GetAttribute" then return function(self, n) return self.attrs[n] end end
        if k == "SetScript" then return function(self, n, fn) self.scripts[n] = fn end end
        if k == "HookScript" then return function(self, n, fn) self.hooks[n] = fn end end
        if k == "WrapScript" then return function(_, target, n, pre) target.wrapped = pre end end
        if k == "Show" then return function(self) self.shown = true end end
        if k == "Hide" then return function(self) self.shown = false end end
        if k == "SetShown" then return function(self, v) self.shown = v and true or false end end
        if k == "IsShown" then return function(self) return self.shown end end
        if k == "SetText" then return function(self, v) self._text = v end end
        if k == "GetText" then return function(self) return self._text end end
        if k == "GetHeight" then return function() return 32 end end
        if k == "GetValue" or k == "GetWidth" then return function() return 0 end end
        if k == "GetPoint" then return function() return "CENTER", nil, "CENTER", 0, -180 end end
        if k == "CreateTexture" or k == "CreateFontString" or k == "CreateLine" then return function() return frame() end end
        -- Widget methods are CamelCase; a lowercase key is a field the addon never set.
        if type(k) == "string" and k:match("^%l") then return nil end
        return function() end
    end })
end
W.frame = frame

function Fake(spec)
    W.spec = spec
    W.frames, W.printed, W.bindings = {}, {}, {}
    W.combat = false
    local units = spec.units or {}
    W.units = units

    local function u(unit)
        if unit == "player" then return units.player end
        return units[unit]
    end

    GetTime = function() return spec.time or 100 end
    C_Spell = {
        GetSpellInfo = function(id)
            local name = W.SPELLS[id]
            return name and { name = name, spellID = id }
        end,
        GetSpellTexture = function(id) return "icon" .. id end,
        IsSpellUsable = function(name)
            if spec.unusable and spec.unusable[name] then return false, false end
            return true, false
        end,
        IsSpellInRange = function(_, unit)
            local x = u(unit)
            if x and x.far then return false end
            return true
        end,
    }
    IsPlayerSpell = function(id) return spec.known and spec.known[id] == true end
    C_UnitAuras = {
        GetAuraDataByIndex = function(unit, i)
            local x = u(unit)
            if not x or not x.auras then return nil end
            if x.hidden then return { name = W.SECRET, expirationTime = 0 } end
            local names = {}
            for name in pairs(x.auras) do names[#names + 1] = name end
            table.sort(names)
            local name = names[i]
            if not name then return nil end
            local left = x.auras[name]
            return { name = name, expirationTime = left == 0 and 0 or GetTime() + left }
        end,
    }
    issecretvalue = function(v) return v == W.SECRET end

    UnitExists = function(unit) return u(unit) ~= nil end
    UnitName = function(unit) local x = u(unit); return x and x.name end
    UnitClass = function(unit)
        local x = u(unit)
        local c = x and x.class or "PRIEST"
        return c, c
    end
    UnitIsDeadOrGhost = function(unit) local x = u(unit); return x and x.dead or false end
    UnitIsConnected = function(unit) local x = u(unit); return not (x and x.offline) end
    UnitIsVisible = function() return true end
    UnitIsUnit = function(a, b)
        if a == b then return true end
        local x, y = u(a), u(b)
        return x ~= nil and x == y
    end
    UnitIsPlayer = function(unit) return u(unit) ~= nil end
    UnitIsFriend = function(_, unit) local x = u(unit); return x and not x.enemy end
    UnitInParty = function(unit) local x = u(unit); return x and x.inGroup or false end
    UnitInRaid = function() return nil end
    UnitGroupRolesAssigned = function(unit) local x = u(unit); return x and x.role or "NONE" end
    GetPartyAssignment = function() return false end
    IsInRaid = function() return spec.raid ~= nil end
    GetNumGroupMembers = function() return spec.raid and #spec.raid or 0 end
    GetRaidRosterInfo = function(i)
        local r = spec.raid[i]
        return r.name, 0, r.group
    end
    GetNumSubgroupMembers = function()
        local n = 0
        for i = 1, 4 do if units["party" .. i] then n = i end end
        return n
    end
    GetWeaponEnchantInfo = function()
        local w = spec.weapon
        if not w then return false end
        return true, w * 1000
    end

    UnitPowerType = function(unit)
        local x = u(unit)
        if x and x.powerType then return x.powerType end
        return (x and (x.class == "WARRIOR" or x.class == "ROGUE")) and 1 or 0
    end
    UnitPower = function() return spec.mana or 100 end
    UnitPowerMax = function() return 100 end
    IsResting = function() return spec.resting or false end
    IsInInstance = function() return spec.instance ~= nil, spec.instance or "none" end
    W.sounds = {}
    PlaySound = function(id) W.sounds[#W.sounds + 1] = id end
    SPELL_FAILED_LINE_OF_SIGHT = "Target not in line of sight"

    InCombatLockdown = function() return W.combat end
    GetLocale = function() return spec.locale or "enUS" end
    GetCVarBool = function() return spec.keyDown or false end
    SlashCmdList = {}
    CreateFrame = function(_, name)
        local f = frame()
        f.name = name
        W.frames[#W.frames + 1] = f
        if name then _G[name] = f end
        return f
    end
    UIParent, GameTooltip, UISpecialFrames = frame(), frame(), {}
    tinsert = table.insert
    ClearOverrideBindings = function() W.bindings = {} end
    SetOverrideBindingClick = function(_, _, key, button) W.bindings[key] = button end
    RAID_CLASS_COLORS = { PRIEST = { r = 1, g = 1, b = 1 } }
    STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    print = function(...) W.printed[#W.printed + 1] = table.concat({ ... }, " ") end
    GulliToolkit = spec.toolkit
    GulliGroupBuffsCharDB = spec.db
    return W
end

function Load(dir)
    dir = dir or "Gulli-GroupBuffs/"
    local ns = {}
    for line in io.lines(dir .. "Gulli-GroupBuffs.toc") do
        line = line:gsub("\r", "")
        if line:match("%.lua$") then assert(loadfile(dir .. line))("Gulli-GroupBuffs", ns) end
    end
    return ns
end

-- Sends a game event to every frame that listens.
function Fire(event, ...)
    for _, f in ipairs(W.frames) do
        local onEvent = f.scripts.OnEvent
        if onEvent then onEvent(f, event, ...) end
    end
end

return W
