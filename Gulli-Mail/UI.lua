-- A panel next to the mailbox: Take all with what it would get, and the names for a new
-- letter. /gml opens the settings when no mailbox is open.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local panel, summary, takeBtn, names, settings

local function makeName(r)
    r.text = S.Text(r, 13)
    r.text:SetPoint("LEFT", 8, 0)
    r.text:SetPoint("RIGHT", -8, 0)
    r.text:SetWordWrap(false)
    r.click = CreateFrame("Button", nil, r)
    r.click:SetAllPoints()
    r.click:SetScript("OnClick", function(self) ns.Pick(self:GetParent().entry.name) end)
end

local function fillName(r, e)
    r.entry = e
    r.text:SetText(e.name .. (e.alt and (" " .. S.Hex(S.MUTED) .. L.ALT .. "|r") or ""))
    S.Fill(r, S.ROW)
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
    panel = S.Window("GulliMailPanel", L.TITLE, 260, 420)
    local body = panel.body
    takeBtn = S.Button(body, 1, 34)
    takeBtn:SetPoint("TOPLEFT", 0, 0)
    takeBtn:SetPoint("TOPRIGHT", 0, 0)
    takeBtn:SetScript("OnClick", function() ns.TakeAll(); ns.Refresh() end)
    summary = S.Note(body, 11)
    summary:SetPoint("TOPLEFT", takeBtn, "BOTTOMLEFT", 0, -8)
    summary:SetPoint("RIGHT", 0, 0)
    local head = S.Text(body, 11, S.MUTED)
    head:SetPoint("TOPLEFT", 0, -92)
    head:SetText(L.SEND_TO)
    names = S.List(body, 30, makeName, fillName)
    names:SetPoint("TOPLEFT", 0, -110)
    names:SetPoint("BOTTOMRIGHT", -12, 0)
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
    settings = S.Window("GulliMailFrame", L.TITLE, 360, 160)
    local c = S.CheckRow(settings.body, L.OPT_PANEL, function() return ns.db.panel end, function(v) ns.db.panel = v end)
    c:SetPoint("TOPLEFT", 0, 0)
    local tip = S.Note(settings.body, 11)
    tip:SetPoint("TOPLEFT", 0, -36)
    tip:SetPoint("RIGHT", 0, 0)
    tip:SetText(L.HELP)
end

function ns.Toggle()
    if ns.open then
        if panel and panel:IsShown() then panel:Hide() else ns.ShowPanel() end
        return
    end
    if not settings then buildSettings() end
    settings:SetShown(not settings:IsShown())
end
