-- The icons on screen (drag the strip to move it, tap it for the settings), and the settings.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local strip, frame
local icons = {}
local SIZE = 40

local function buildStrip()
    strip = CreateFrame("Button", "GulliRemindersStrip", UIParent)
    strip:SetSize(SIZE, SIZE)
    strip:SetPoint("TOP", 0, -190)
    strip:SetMovable(true)
    strip:SetClampedToScreen(true)
    strip:RegisterForDrag("LeftButton")
    strip:SetScript("OnDragStart", strip.StartMoving)
    strip:SetScript("OnDragStop", strip.StopMovingOrSizing)
    strip:SetScript("OnClick", function() ns.Toggle() end)
    strip.text = S.Text(strip, 12)
    strip.text:SetPoint("TOP", strip, "BOTTOM", 0, -4)
    strip.text:SetJustifyH("CENTER")
end

local function icon(i)
    if icons[i] then return icons[i] end
    local b = CreateFrame("Frame", nil, strip)
    b:SetSize(SIZE, SIZE)
    S.Box(b)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetPoint("TOPLEFT", 1, -1)
    b.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icons[i] = b
    return b
end

function ns.Refresh()
    local missing = ns.Missing()
    if #missing == 0 then
        if strip then strip:Hide() end
        return missing
    end
    if not strip then buildStrip() end
    local width = #missing * (SIZE + 4) - 4
    strip:SetWidth(width)
    local texts = {}
    for i, m in ipairs(missing) do
        local b = icon(i)
        b:ClearAllPoints()
        b:SetPoint("LEFT", strip, "LEFT", (i - 1) * (SIZE + 4), 0)
        b.tex:SetTexture(m.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        b:Show()
        texts[#texts + 1] = m.text
    end
    for i = #missing + 1, #icons do icons[i]:Hide() end
    strip.text:SetText(table.concat(texts, "\n"))
    strip:Show()
    return missing
end

local function numberEdit(parent, key)
    local e = S.Edit(parent, 52)
    e:SetNumeric(true)
    e:SetMaxLetters(4)
    e:SetScript("OnShow", function(self) self:SetText(tostring(ns.db[key])) end)
    local function apply(self)
        local n = tonumber(self:GetText())
        if n then ns.db[key] = n end
        self:SetText(tostring(ns.db[key]))
        self:ClearFocus()
        ns.Refresh()
    end
    e:SetScript("OnEnterPressed", apply)
    e:SetScript("OnEditFocusLost", function(self) S.SetBorder(self, S.BORDER); apply(self) end)
    return e
end

local function build()
    frame = S.Window("GulliRemindersFrame", L.TITLE, 420, 300)
    local body = frame.body
    local y = 0
    local function check(key, label)
        local c = S.CheckRow(body, label, function() return ns.db[key] end, function(v) ns.db[key] = v; ns.Refresh() end)
        c:SetPoint("TOPLEFT", 0, y)
        y = y - 32
        return c
    end
    check("buffs", L.OPT_BUFFS)
    check("weapon", L.OPT_WEAPON)
    local ammo = check("ammo", L.OPT_AMMO)
    local ammoEdit = numberEdit(body, "ammoMin")
    ammoEdit:SetPoint("TOPRIGHT", 0, -(2 * 32))
    ammo.label:SetPoint("RIGHT", ammoEdit, "LEFT", -6, 0)
    local shards = check("shards", L.OPT_SHARDS)
    local shardEdit = numberEdit(body, "shardsMin")
    shardEdit:SetPoint("TOPRIGHT", 0, -(3 * 32))
    shards.label:SetPoint("RIGHT", shardEdit, "LEFT", -6, 0)
    check("notResting", L.OPT_RESTING)
    local note = S.Note(body, 11)
    note:SetPoint("TOPLEFT", 0, y - 6)
    note:SetPoint("RIGHT", 0, 0)
    note:SetText(L.NOTE)
end

function ns.Toggle()
    if not frame then build() end
    frame:SetShown(not frame:IsShown())
end
