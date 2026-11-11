-- Dungeons on the left; on the right the checklist and the dungeon's quests in three groups.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, dungeons, checks, list
local checkLines = {}
local ICON_OK, ICON_NO = "Interface\\RaidFrame\\ReadyCheck-Ready", "Interface\\RaidFrame\\ReadyCheck-NotReady"

local function makeDungeon(r)
    r.name = S.Text(r, 12)
    r.name:SetPoint("LEFT", 8, 0)
    r.name:SetPoint("RIGHT", -40, 0)
    r.name:SetWordWrap(false)
    r.range = S.Text(r, 10, S.MUTED)
    r.range:SetPoint("RIGHT", -6, 0)
    r.click = CreateFrame("Button", nil, r)
    r.click:SetAllPoints()
    r.click:SetScript("OnClick", function(self) ns.selected = self:GetParent().d.key; ns.Refresh() end)
end

local function fillDungeon(r, d)
    r.d = d
    r.name:SetText(ns.DungeonName(d))
    r.name:SetTextColor(unpack(d.fits and S.TEXT or S.MUTED))
    r.range:SetText(d.min .. "-" .. d.max)
    S.Fill(r, d.key == ns.selected and S.PANEL or S.ROW)
    S.SetBorder(r, d.key == ns.selected and S.Accent() or { 0, 0, 0, 0 })
end

local function makeRow(r)
    r.text = S.Text(r, 12)
    r.text:SetPoint("TOPLEFT", 8, -4)
    r.text:SetPoint("RIGHT", -8, 0)
    r.text:SetWordWrap(false)
    r.sub = S.Text(r, 10, S.MUTED)
    r.sub:SetPoint("TOPLEFT", r.text, "BOTTOMLEFT", 0, -2)
    r.sub:SetPoint("RIGHT", -8, 0)
    r.sub:SetWordWrap(false)
end

local function fillRow(r, item)
    if item.header then
        S.Fill(r, S.PANEL)
        r.text:SetText(S.Hex(S.Accent()) .. item.text .. "|r")
        r.sub:SetText("")
        return
    end
    S.Fill(r, S.ROW)
    local q = item.quest
    local color = item.group == "later" and S.Hex(S.MUTED) or ""
    r.text:SetText(color .. "[" .. q.level .. "] " .. q.name .. "|r")
    if item.group == "take" then
        r.sub:SetText(ns.Where(q))
    elseif item.group == "later" then
        r.sub:SetText(q.why == "WHY_LEVEL" and L.WHY_LEVEL:format(q.minLevel) or L.WHY_EARLIER)
    else
        r.sub:SetText(L.IN_LOG)
    end
end

function ns.Refresh()
    if not frame or not frame:IsShown() then return end
    local level = UnitLevel("player") or 1
    if not ns.selected then
        local s = ns.Suggest(level)
        ns.selected = s and s.key
    end
    dungeons:SetData(ns.Dungeons(level))
    for i, c in ipairs(ns.Checklist()) do
        local line = checkLines[i]
        line.icon:SetTexture(c.ok and ICON_OK or ICON_NO)
        line.text:SetText(c.text)
    end
    local items = {}
    if ns.selected then
        local q = ns.Quests(ns.selected, level)
        local function section(key, group, list)
            if #list == 0 then return end
            items[#items + 1] = { header = true, text = L[key]:format(#list) }
            for _, x in ipairs(list) do items[#items + 1] = { quest = x, group = group } end
        end
        section("IN_LOG_N", "log", q.log)
        section("TAKE_N", "take", q.take)
        section("LATER_N", "later", q.later)
        if q.done > 0 then items[#items + 1] = { header = true, text = L.DONE_N:format(q.done) } end
        if #items == 0 then items[1] = { header = true, text = L.NO_QUESTS } end
    end
    list:SetData(items)
end

local function build()
    frame = S.Window("GulliDungeonPrepFrame", L.TITLE, 720, 500)
    local body = frame.body
    dungeons = S.List(body, 28, makeDungeon, fillDungeon)
    dungeons:SetPoint("TOPLEFT", 0, 0)
    dungeons:SetPoint("BOTTOMLEFT", 0, 0)
    dungeons:SetWidth(200)

    checks = CreateFrame("Frame", nil, body)
    checks:SetPoint("TOPLEFT", 222, 0)
    checks:SetPoint("TOPRIGHT", 0, 0)
    checks:SetHeight(56)
    S.Box(checks, S.PANEL)
    for i = 1, 4 do
        local line = {}
        line.icon = checks:CreateTexture(nil, "ARTWORK")
        line.icon:SetSize(14, 14)
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        line.icon:SetPoint("TOPLEFT", 8 + col * 230, -8 - row * 22)
        line.text = S.Text(checks, 12)
        line.text:SetPoint("LEFT", line.icon, "RIGHT", 6, 0)
        line.text:SetWidth(200)
        line.text:SetWordWrap(false)
        checkLines[i] = line
    end

    list = S.List(body, 36, makeRow, fillRow)
    list:SetPoint("TOPLEFT", 222, -64)
    list:SetPoint("BOTTOMRIGHT", -12, 0)
    frame:SetScript("OnShow", ns.Refresh)
end

function ns.Toggle()
    if not frame then build() end
    frame:SetShown(not frame:IsShown())
    ns.Refresh()
end
