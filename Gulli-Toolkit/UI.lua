-- The hub window: one row per module with its icon, name, a line about it, an on/off switch
-- and Open. It only shows ns.List() and calls ns.OpenModule and ns.SetEnabled.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local WIDTH, ROW_H, PAD = 500, 58, 12
local frame, scroll, list, footer, reloadBtn, reloadText, feedBox, protectBtn, protectFrame
local rows, feedLines = {}, {}
local FEED_LINES = 3

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
    local contentH = #data * (ROW_H + 4)
    list:SetHeight(contentH)
    local reload = ns.NeedsReload()
    reloadBtn:SetShown(reload)
    reloadText:SetText(reload and L.RELOAD_HINT or (anyMissing and L.GET or L.HELP))
    protectBtn:SetText(L.PROTECTED_N:format(#ns.Protected()))

    local feed = ns.Feed()
    local shown = math.min(#feed, FEED_LINES)
    for i = 1, FEED_LINES do
        local e = feed[i]
        local who = e and tostring(e.key or "")
        if who and ns.T.en["M_" .. who] then who = L["M_" .. who] end
        feedLines[i]:SetText(e and (S.Hex(S.Accent()) .. who .. "|r  " .. e.text) or "")
    end
    feedBox:SetShown(shown > 0)
    feedBox:SetHeight(22 + shown * 16)
    local feedH = shown > 0 and (22 + shown * 16 + 8) or 0
    -- Twenty modules do not fit a handheld screen: the list scrolls inside 85% of the screen.
    local screen = (UIParent.GetHeight and tonumber(UIParent:GetHeight())) or 768
    local listH = math.max(ROW_H + 4, math.min(contentH, screen * 0.85 - 60 - feedH - 50))
    scroll:SetHeight(listH)
    scroll:Update(contentH)
    frame:SetHeight(60 + listH + feedH + 50)
    if protectFrame and protectFrame:IsShown() then ns.RefreshProtected() end
end

-- The list of protected items with a drop zone: drag an item from the bags onto it.
local protRows = {}
function ns.RefreshProtected()
    local ids = ns.Protected()
    for i, id in ipairs(ids) do
        local r = protRows[i]
        if not r then
            r = CreateFrame("Frame", nil, protectFrame.list)
            r:SetHeight(30)
            r:SetPoint("TOPLEFT", 0, -(i - 1) * 32)
            r:SetPoint("TOPRIGHT", 0, -(i - 1) * 32)
            S.Box(r, S.PANEL)
            r.icon = r:CreateTexture(nil, "ARTWORK")
            r.icon:SetSize(22, 22)
            r.icon:SetPoint("LEFT", 4, 0)
            r.remove = S.Button(r, 80, 26)
            r.remove:SetPoint("RIGHT", -2, 0)
            r.remove:SetText(L.REMOVE)
            r.remove:SetScript("OnClick", function(self) GulliToolkit.Protect(self:GetParent().id, false) end)
            r.name = S.Text(r, 12)
            r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
            r.name:SetPoint("RIGHT", r.remove, "LEFT", -6, 0)
            r.name:SetWordWrap(false)
            protRows[i] = r
        end
        r.id = id
        local name, _, _, _, _, _, _, _, _, icon = (C_Item and C_Item.GetItemInfo or GetItemInfo)(id)
        r.name:SetText(name or ("item:" .. id))
        r.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        r:Show()
    end
    for i = #ids + 1, #protRows do protRows[i]:Hide() end
    protectFrame.list:SetHeight(math.max(1, #ids * 32))
    protectFrame:SetHeight(130 + #ids * 32)
end

local function dropItem()
    local kind, id = GetCursorInfo()
    if kind == "item" and id then
        GulliToolkit.Protect(id, true)
        ClearCursor()
    end
end

local function buildProtected()
    protectFrame = CreateFrame("Frame", "GulliToolkitProtected", frame)
    protectFrame:SetWidth(360)
    protectFrame:SetPoint("TOPLEFT", frame, "TOPRIGHT", 4, 0)
    S.Box(protectFrame)
    local title = S.Text(protectFrame, 14, S.Accent())
    title:SetPoint("TOPLEFT", PAD, -PAD)
    title:SetText(L.PROTECTED)
    local close = S.Button(protectFrame, 32, 28)
    close:SetPoint("TOPRIGHT", -PAD + 4, -PAD + 4)
    close:SetText("X")
    close:SetScript("OnClick", function() protectFrame:Hide() end)
    local hint = S.Text(protectFrame, 11, S.MUTED)
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    hint:SetPoint("RIGHT", -PAD, 0)
    hint:SetText(L.PROTECT_HINT)
    local drop = CreateFrame("Button", nil, protectFrame)
    drop:SetHeight(34)
    drop:SetPoint("TOPLEFT", PAD, -70)
    drop:SetPoint("TOPRIGHT", -PAD, -70)
    S.Box(drop, { 0.02, 0.02, 0.02, 1 }, { 0.25, 0.25, 0.27, 1 })
    local dropText = S.Text(drop, 12, S.MUTED)
    dropText:SetPoint("CENTER")
    dropText:SetText(L.DROP)
    drop:SetScript("OnReceiveDrag", dropItem)
    drop:SetScript("OnClick", dropItem)
    protectFrame.list = CreateFrame("Frame", nil, protectFrame)
    protectFrame.list:SetPoint("TOPLEFT", drop, "BOTTOMLEFT", 0, -8)
    protectFrame.list:SetPoint("TOPRIGHT", drop, "BOTTOMRIGHT", 0, -8)
    protectFrame:SetScript("OnShow", ns.RefreshProtected)
    protectFrame:Hide()
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

    scroll = S.Scroll(frame)
    scroll:SetPoint("TOPLEFT", PAD, -60)
    scroll:SetPoint("TOPRIGHT", -PAD - 12, -60)
    list = scroll.child
    list:SetWidth(WIDTH - 2 * PAD - 12)

    footer = CreateFrame("Frame", nil, frame)
    footer:SetPoint("BOTTOMLEFT", PAD, PAD)
    footer:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    footer:SetHeight(30)
    reloadBtn = S.Button(footer, 130, 30)
    reloadBtn:SetPoint("RIGHT")
    reloadBtn:SetText(L.RELOAD)
    reloadBtn:SetScript("OnClick", function() ReloadUI() end)
    protectBtn = S.Button(footer, 170, 30)
    protectBtn:SetPoint("LEFT")
    protectBtn:SetScript("OnClick", function()
        if not protectFrame then buildProtected() end
        protectFrame:SetShown(not protectFrame:IsShown())
    end)
    reloadText = S.Text(footer, 11, S.MUTED)
    reloadText:SetPoint("LEFT", protectBtn, "RIGHT", 8, 0)
    reloadText:SetPoint("RIGHT", reloadBtn, "LEFT", -8, 0)
    reloadText:SetMaxLines(2)

    feedBox = CreateFrame("Frame", nil, frame)
    feedBox:SetPoint("BOTTOMLEFT", footer, "TOPLEFT", 0, 8)
    feedBox:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", 0, 8)
    S.Box(feedBox, S.PANEL)
    local feedTitle = S.Text(feedBox, 11, S.MUTED)
    feedTitle:SetPoint("TOPLEFT", 8, -5)
    feedTitle:SetText(L.RECENT)
    for i = 1, FEED_LINES do
        local t = S.Text(feedBox, 11)
        t:SetPoint("TOPLEFT", 8, -5 - i * 16)
        t:SetPoint("RIGHT", -8, 0)
        t:SetWordWrap(false)
        feedLines[i] = t
    end

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
