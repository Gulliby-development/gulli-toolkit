-- A panel next to the mailbox: Take all with what it would get, and the names for a new
-- letter. /gml opens the settings when no mailbox is open.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local panel, summary, takeBtn, names, settings

local function makeName(r)
    r.text = S.Text(r, 12)
    r.text:SetPoint("LEFT", 10, 0)
    r.text:SetPoint("RIGHT", -8, 0)
    r.text:SetWordWrap(false)
    r.click = CreateFrame("Button", nil, r)
    r.click:SetAllPoints()
    r.click:SetScript("OnClick", function(self) ns.Pick(self:GetParent().entry.name) end)
    r.click:SetScript("OnEnter", function(self) S.Fill(self:GetParent(), S.HOVER) end)
    r.click:SetScript("OnLeave", function(self) S.Fill(self:GetParent(), S.CLEAR) end)
end

local function fillName(r, e)
    r.entry = e
    r.text:SetText(e.name .. (e.alt and ("  " .. S.Hex(S.FAINT) .. L.ALT .. "|r") or ""))
end

function ns.Refresh()
    if not panel or not panel:IsShown() then return end
    local s = ns.Summary()
    local text = L.SUMMARY:format(s.items, ns.Money(s.money))
    if s.cod > 0 then text = text .. "\n" .. L.COD:format(s.cod) end
    summary:SetText(text)
    takeBtn:SetEnabled(not ns.taking and (s.items > 0 or s.money > 0))
    takeBtn:SetText(ns.taking and L.TAKING or L.TAKE_ALL)
    names:SetData(ns.Names())
end

local function buildPanel()
    panel = S.Window("GulliMailPanel", L.TITLE, 280, 440)
    local body = panel.body
    takeBtn = S.Primary(S.Button(body, 1, 34))
    takeBtn:SetPoint("TOPLEFT", 0, 0)
    takeBtn:SetPoint("TOPRIGHT", 0, 0)
    takeBtn:SetScript("OnClick", function() ns.TakeAll(); ns.Refresh() end)
    summary = S.Note(body, 11)
    summary:SetPoint("TOPLEFT", takeBtn, "BOTTOMLEFT", 0, -8)
    summary:SetPoint("RIGHT", 0, 0)
    summary:SetMaxLines(3)
    local card = S.Card(body, L.SEND_TO)
    card:SetPoint("TOPLEFT", 0, -90)
    card:SetPoint("BOTTOMRIGHT")
    names = S.List(card.body, 30, makeName, fillName)
    names:SetPoint("TOPLEFT")
    names:SetPoint("BOTTOMRIGHT", -10, 0)
    panel:SetScript("OnShow", function() ns.Refresh() end)
end

function ns.ShowPanel()
    if not panel then buildPanel() end
    panel:ClearAllPoints()
    if MailFrame then panel:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 8, 0) else panel:SetPoint("CENTER") end
    panel:Show()
end

function ns.HidePanel() if panel then panel:Hide() end end

local function buildSettings()
    settings = S.Window("GulliMailFrame", L.TITLE, 420, 220)
    local st = S.Stack(settings.body)
    local card, h = S.SettingsCard(settings.body, nil, {
        { L.OPT_PANEL, nil, function() return ns.db.panel end, function(v) ns.db.panel = v end,
          icon = "Interface\\Icons\\INV_Letter_15" } })
    st:Add(card, h)
    local tip, th = S.Paragraph(settings.body, L.HELP, settings.inner[1])
    st:Add(tip, th)
    S.FitWindow(settings, st:Height())
end

function ns.Toggle()
    if ns.open then
        if panel and panel:IsShown() then panel:Hide() else ns.ShowPanel() end
        return
    end
    if not settings then buildSettings() end
    settings:SetShown(not settings:IsShown())
end
