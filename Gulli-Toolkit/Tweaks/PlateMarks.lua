-- Quest marks on mobs: a quest mark beside the nameplate of a mob a quest in the log still needs
-- (its tooltip shows an unfinished objective), and a silver star beside a rare one. Our own
-- small frame sits on the plate; the game's plate itself is never changed.

local _, ns = ...

local frame, get
local marks = {}
local QUEST_ATLAS, QUEST_TEX = "QuestNormal", "Interface\\GossipFrame\\AvailableQuestIcon"
local STAR = "Interface\\AddOns\\Gulli-Toolkit\\Art\\Star"

local LT = Enum and Enum.TooltipDataLineType or {}
local OBJECTIVE = LT.QuestObjective or 8

local function secret(v) return issecretvalue and issecretvalue(v) end

-- An objective line still to do: "Kobold Vermin slain: 3/10", or a line the game marks as such.
function ns.OpenObjective(line)
    if type(line) ~= "table" or secret(line.leftText) then return false end
    if line.type ~= OBJECTIVE then return false end
    if line.completed == true then return false end
    local text = line.leftText
    if type(text) ~= "string" then return false end
    local have, need = text:match("(%d+)%s*/%s*(%d+)")
    if have then return tonumber(have) < tonumber(need) end
    return line.completed == false
end

function ns.UnitQuestOpen(unit)
    if not C_TooltipInfo or not C_TooltipInfo.GetUnit then return false end
    local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
    if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return false end
    for _, line in ipairs(data.lines) do
        if ns.OpenObjective(line) then return true end
    end
    return false
end

local function isRare(unit)
    local ok, c = pcall(UnitClassification, unit)
    return ok and not secret(c) and (c == "rare" or c == "rareelite")
end

-- What one unit gets: "quest", "rare" or nil.
function ns.PlateMark(unit, g)
    if not UnitExists or not UnitExists(unit) then return nil end
    if UnitIsPlayer and UnitIsPlayer(unit) then return nil end
    if g("quest") and ns.UnitQuestOpen(unit) then return "quest" end
    if g("rare") and isRare(unit) then return "rare" end
    return nil
end

local function plateOf(unit)
    if not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then return nil end
    local ok, p = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if not ok or not p then return nil end
    if p.IsForbidden and p:IsForbidden() then return nil end
    return p
end

local function markFor(plate)
    local m = marks[plate]
    if m then return m end
    m = CreateFrame("Frame", nil, plate)
    m:SetSize(22, 22)
    m:SetPoint("BOTTOM", plate, "TOP", 0, -4)
    m.icon = m:CreateTexture(nil, "OVERLAY")
    m.icon:SetAllPoints()
    marks[plate] = m
    return m
end

local function update(unit)
    local plate = plateOf(unit)
    if not plate then return end
    local kind = get and ns.PlateMark(unit, get)
    local m = marks[plate]
    if not kind then
        if m then m:Hide() end
        return
    end
    m = markFor(plate)
    if kind == "quest" then
        m.icon:SetVertexColor(1, 1, 1)
        if not (m.icon.SetAtlas and m.icon:SetAtlas(QUEST_ATLAS)) then m.icon:SetTexture(QUEST_TEX) end
    else
        m.icon:SetTexture(STAR)
        m.icon:SetVertexColor(0.85, 0.88, 0.95)
    end
    m:Show()
end

local function all()
    for _, m in pairs(marks) do m:Hide() end
    if not C_NamePlate or not C_NamePlate.GetNamePlates then return end
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if unit then update(unit) end
    end
end

local soon
local function later()
    if soon then return end
    if not (C_Timer and C_Timer.After) then all(); return end
    soon = true
    C_Timer.After(0.3, function() soon = nil; all() end)
end

local function onEvent(_, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then update(unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local plate = plateOf(unit)
        if plate and marks[plate] then marks[plate]:Hide() end
    else later() end
end
ns.PlateMarksEvent = onEvent

ns.AddTweak({
    key = "plateMarks", group = "quests", icon = "Interface\\Icons\\Ability_Hunter_SniperShot", star = true,
    defaults = { quest = true, rare = true },
    panel = {
        { kind = "switch", key = "quest", label = ns.L.TWP_PLATE_QUEST },
        { kind = "switch", key = "rare", label = ns.L.TWP_PLATE_RARE },
    },
    enable = function(g)
        get = g
        frame = frame or CreateFrame("Frame")
        frame:SetScript("OnEvent", onEvent)
        frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
        frame:RegisterEvent("QUEST_LOG_UPDATE")
        all()
    end,
    disable = function()
        if frame then frame:UnregisterAllEvents() end
        get = nil
        for _, m in pairs(marks) do m:Hide() end
    end,
    changed = function(_, _, g) get = g; all() end,
})
