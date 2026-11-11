-- The hub window: one row per module with its icon, name, a line about it, an on/off switch
-- and Open. It only shows ns.List() and calls ns.OpenModule and ns.SetEnabled.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local WIDTH, ROW_H, PAD = 500, 58, 12
local frame, list, footer, reloadBtn, reloadText
local rows = {}

local function makeRow(i)
    local r = CreateFrame("Frame", nil, list)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * (ROW_H + 4))
    r:SetPoint("TOPRIGHT", 0, -(i - 1) * (ROW_H + 4))
    S.Box(r, S.PANEL)

    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(36, 36)
    r.icon:SetPoint("LEFT", 10, 0)

    r.open = S.Button(r, 96, 30)
    r.open:SetPoint("RIGHT", -10, 0)
    r.open:SetText(L.OPEN)

    r.check = S.Check(r, 28)
    r.check:SetPoint("RIGHT", r.open, "LEFT", -6, 0)
    r.check:SetScript("OnClick", function(self)
        if self.row then ns.SetEnabled(self.row, not self.row.on) end
    end)
    r.check:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L.ON_TIP, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    r.check:HookScript("OnLeave", function() GameTooltip:Hide() end)

    r.status = S.Text(r, 12, S.MUTED)
    r.status:SetPoint("RIGHT", -12, 0)
    r.status:SetJustifyH("RIGHT")

    r.title = S.Text(r, 14)
    r.title:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 10, 0)
    r.title:SetPoint("RIGHT", r.check, "LEFT", -8, 0)
    r.title:SetWordWrap(false)

    r.desc = S.Text(r, 11, S.MUTED)
    r.desc:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -3)
    r.desc:SetPoint("RIGHT", r.check, "LEFT", -8, 0)
    r.desc:SetMaxLines(2)
    r.desc:SetJustifyV("TOP")

    r.open:SetScript("OnClick", function(self)
        local row = self:GetParent().row
        if row and ns.OpenModule(row.key) then frame:Hide() end
    end)
    rows[i] = r
    return r
end

local function fill(r, row)
    r.row = row
    r.check.row = row
    r.icon:SetTexture(row.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    r.icon:SetDesaturated(row.state ~= "ready")
    local slash = row.slash and ("  " .. S.Hex(S.MUTED) .. row.slash .. "|r") or ""
    r.title:SetText(row.title .. slash)
    r.desc:SetText(row.desc)
    local missing = row.state == "missing"
    r.check:SetShown(not missing)
    r.open:SetShown(not missing)
    r.status:SetShown(missing)
    r.status:SetText(missing and L.NOT_INSTALLED or "")
    if missing then
        r.title:SetPoint("RIGHT", r.status, "LEFT", -8, 0)
        r.desc:SetPoint("RIGHT", r.status, "LEFT", -8, 0)
    else
        r.title:SetPoint("RIGHT", r.check, "LEFT", -8, 0)
        r.desc:SetPoint("RIGHT", r.check, "LEFT", -8, 0)
    end
    r.check:SetChecked(row.on and true or false)
    local canOpen = row.state == "ready" and row.info and type(row.info.open) == "function"
    r.open:SetEnabled(canOpen and true or false)
    r.title:SetTextColor(unpack(row.state == "ready" and S.TEXT or S.MUTED))
    r:Show()
end

function ns.Refresh()
    if not frame or not frame:IsShown() then return end
    local data = ns.List()
    local anyMissing = false
    for i, row in ipairs(data) do
        fill(rows[i] or makeRow(i), row)
        if row.state == "missing" then anyMissing = true end
    end
    for i = #data + 1, #rows do rows[i]:Hide() end
    list:SetHeight(#data * (ROW_H + 4))
    local reload = ns.NeedsReload()
    reloadBtn:SetShown(reload)
    reloadText:SetText(reload and L.RELOAD_HINT or (anyMissing and L.GET or L.HELP))
    frame:SetHeight(60 + #data * (ROW_H + 4) + 50)
end

local function build()
    frame = CreateFrame("Frame", "GulliToolkitFrame", UIParent)
    frame:SetSize(WIDTH, 300)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    S.Box(frame)
    tinsert(UISpecialFrames, "GulliToolkitFrame")

    local accent = S.Accent()
    local title = S.Text(frame, 16, accent)
    title:SetPoint("TOPLEFT", PAD, -PAD)
    title:SetText(L.TITLE)
    local sub = S.Text(frame, 11, S.MUTED)
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    sub:SetPoint("RIGHT", -60, 0)
    sub:SetWordWrap(false)
    sub:SetText(L.SUBTITLE)

    local close = S.Button(frame, 32, 30)
    close:SetPoint("TOPRIGHT", -PAD, -PAD + 2)
    close:SetText("X")
    close:SetScript("OnClick", function() frame:Hide() end)

    list = CreateFrame("Frame", nil, frame)
    list:SetPoint("TOPLEFT", PAD, -60)
    list:SetPoint("TOPRIGHT", -PAD, -60)

    footer = CreateFrame("Frame", nil, frame)
    footer:SetPoint("BOTTOMLEFT", PAD, PAD)
    footer:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    footer:SetHeight(30)
    reloadBtn = S.Button(footer, 130, 30)
    reloadBtn:SetPoint("RIGHT")
    reloadBtn:SetText(L.RELOAD)
    reloadBtn:SetScript("OnClick", function() ReloadUI() end)
    reloadText = S.Text(footer, 11, S.MUTED)
    reloadText:SetPoint("LEFT")
    reloadText:SetPoint("RIGHT", reloadBtn, "LEFT", -8, 0)
    reloadText:SetMaxLines(2)

    frame:SetScript("OnShow", ns.Refresh)
    frame:Hide()
end

function ns.Toggle()
    if not frame then build() end
    frame:SetShown(not frame:IsShown())
end

-- A page under Options > AddOns with a button that opens the hub.
function ns.RegisterSettings()
    local panel = CreateFrame("Frame")
    panel.name = L.TITLE
    local title = S.Text(panel, 16, S.Accent())
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(L.TITLE)
    local sub = S.Text(panel, 12, S.MUTED)
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetText(L.SUBTITLE .. " " .. L.HELP)
    local open = S.Button(panel, 200, 30)
    open:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -12)
    open:SetText(L.OPEN_HUB)
    open:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel.Close then SettingsPanel:Close(true) end
        if not frame or not frame:IsShown() then ns.Toggle() end
    end)
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, L.TITLE)
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end
