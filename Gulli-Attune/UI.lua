-- Characters on the left; on the right each raid or key with its steps, the next one highlighted.
-- A raid that is done shows only its line.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, chars, list, forget
local selected
local ICON = {
    done = "Interface\\RaidFrame\\ReadyCheck-Ready",
    active = "Interface\\RaidFrame\\ReadyCheck-Waiting",
    todo = "Interface\\RaidFrame\\ReadyCheck-NotReady",
}

local function classColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return c and string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) or ""
end

local function makeChar(r)
    r.text = S.Text(r, 12)
    r.text:SetPoint("LEFT", 8, 0)
    r.text:SetPoint("RIGHT", -4, 0)
    r.text:SetWordWrap(false)
    r.click = CreateFrame("Button", nil, r)
    r.click:SetAllPoints()
    r.click:SetScript("OnClick", function(self) selected = self:GetParent().entry.key; ns.Refresh() end)
end

local function fillChar(r, e)
    r.entry = e
    r.text:SetText(classColor(e.char.class) .. e.char.name .. "|r " .. S.Hex(S.MUTED) .. (e.char.level or "") .. "|r")
    S.Fill(r, e.key == selected and S.PANEL or S.ROW)
    S.SetBorder(r, e.key == selected and S.Accent() or { 0, 0, 0, 0 })
end

local function makeRow(r)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(16, 16)
    r.text = S.Text(r, 12)
    r.text:SetPoint("RIGHT", -8, 0)
    r.text:SetWordWrap(false)
    r.sub = S.Text(r, 10, S.MUTED)
    r.sub:SetPoint("RIGHT", -8, 0)
    r.sub:SetWordWrap(false)
end

local function fillRow(r, item)
    r.icon:ClearAllPoints()
    r.text:ClearAllPoints()
    r.text:SetPoint("RIGHT", -8, 0)
    if item.header then
        local p = item.progress
        r.icon:SetPoint("LEFT", 8, 0)
        r.icon:SetTexture(ICON[p.ready and "done" or (p.done > 0 and "active" or "todo")])
        r.text:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
        local state = p.ready and (S.Hex(S.Accent()) .. L.READY .. "|r") or
            (S.Hex(S.MUTED) .. L.STEPS:format(p.done, p.total) .. "|r")
        if p.raid.later then state = state .. "   " .. S.Hex(S.MUTED) .. L.LATER .. "|r" end
        r.text:SetText(ns.RaidName(p.raid) .. "   " .. state)
        r.sub:SetText("")
        S.Fill(r, S.PANEL)
        return
    end
    S.Fill(r, S.ROW)
    r.icon:SetPoint("TOPLEFT", 28, -5)
    r.icon:SetTexture(ICON[item.state])
    r.text:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, 1)
    local name = ns.QuestName(item.step)
    r.text:SetText(item.isNext and (S.Hex(S.Accent()) .. L.NEXT .. "|r " .. name) or name)
    r.sub:ClearAllPoints()
    r.sub:SetPoint("TOPLEFT", r.text, "BOTTOMLEFT", 0, -2)
    r.sub:SetPoint("RIGHT", -8, 0)
    r.sub:SetText(item.isNext and ns.Where(item.step) or "")
end

function ns.Refresh()
    if not frame or not frame:IsShown() then return end
    local all = ns.Chars()
    if not selected or not ns.db.chars[selected] then selected = all[1] and all[1].key end
    chars:SetData(all)
    local items = {}
    local c = selected and ns.db.chars[selected]
    if c then
        for _, raid in ipairs(ns.RaidsFor(c)) do
            local p = ns.Progress(c, raid)
            items[#items + 1] = { header = true, progress = p }
            if not p.ready then
                for _, s in ipairs(p.steps) do
                    items[#items + 1] = { step = s.step, state = s.state, isNext = s.step == p.next }
                end
            end
        end
    end
    list:SetData(items)
    forget:SetEnabled(selected ~= nil and selected ~= ns.CharKey())
end

local function build()
    frame = S.Window("GulliAttuneFrame", L.TITLE, 720, 480)
    local body = frame.body
    chars = S.List(body, 30, makeChar, fillChar)
    chars:SetPoint("TOPLEFT", 0, 0)
    chars:SetPoint("BOTTOMLEFT", 0, 40)
    chars:SetWidth(170)
    forget = S.Button(body, 170, 30)
    forget:SetPoint("BOTTOMLEFT", 0, 0)
    forget:SetText(L.FORGET)
    forget:SetScript("OnClick", function() if selected then ns.Forget(selected); selected = nil end end)
    list = S.List(body, 36, makeRow, fillRow)
    list:SetPoint("TOPLEFT", 190, 0)
    list:SetPoint("BOTTOMRIGHT", -12, 0)
    frame:SetScript("OnShow", function() ns.Scan() end)
end

function ns.Toggle()
    if not frame then build() end
    frame:SetShown(not frame:IsShown())
end
