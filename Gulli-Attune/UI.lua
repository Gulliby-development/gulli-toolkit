-- Characters on the left; on the right each raid with its steps, the next one highlighted.
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
    S.NavRow(r)
    r.line:Hide()
    r.text = S.Text(r, 12)
    r.text:SetPoint("LEFT", 12, 0)
    r.text:SetPoint("RIGHT", -4, 0)
    r.text:SetWordWrap(false)
    r.click = CreateFrame("Button", nil, r)
    r.click:SetAllPoints()
    r.click:SetScript("OnClick", function(self) selected = self:GetParent().entry.key; ns.Refresh() end)
end

local function fillChar(r, e)
    r.entry = e
    r.text:SetText(classColor(e.char.class) .. e.char.name .. "|r " .. S.Hex(S.MUTED) .. (e.char.level or "") .. "|r")
    r:SetSelected(e.key == selected)
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
        r.text:SetText(ns.RaidName(p.raid) .. "   " .. state)
        r.text:SetTextColor(unpack(S.TEXT))
        r.sub:SetText("")
        S.Fill(r, S.RAISED)
        return
    end
    S.Fill(r, S.CLEAR)
    local name = ns.QuestName(item.step)
    r.text:SetText(item.isNext and (S.Hex(S.Accent()) .. L.NEXT .. "|r " .. name) or name)
    r.text:SetTextColor(unpack(item.state == "done" and S.MUTED or S.TEXT))
    r.icon:SetTexture(ICON[item.state])
    r.sub:ClearAllPoints()
    if item.isNext then
        r.icon:SetPoint("TOPLEFT", 28, -5)
        r.text:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, 1)
        r.sub:SetPoint("TOPLEFT", r.text, "BOTTOMLEFT", 0, -3)
        r.sub:SetPoint("RIGHT", -8, 0)
        r.sub:SetText(ns.Where(item.step) or "")
    else
        r.icon:SetPoint("LEFT", 28, 0)
        r.text:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
        r.sub:SetText("")
    end
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
    frame = S.Window("GulliAttuneFrame", L.TITLE, 760, 500)
    local body = frame.body
    local left = S.Card(body)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(190)
    forget = S.Ghost(S.Button(left.body, 166, 30))
    forget:SetPoint("BOTTOMLEFT", 0, 0)
    forget:SetPoint("BOTTOMRIGHT", 0, 0)
    forget:SetText(L.FORGET)
    forget:SetScript("OnClick", function() if selected then ns.Forget(selected); selected = nil end end)
    chars = S.List(left.body, 32, makeChar, fillChar)
    chars:SetPoint("TOPLEFT", 0, 0)
    chars:SetPoint("BOTTOMRIGHT", -10, 40)

    local right = S.Card(body)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", S.GAP, 0)
    right:SetPoint("BOTTOMRIGHT")
    list = S.List(right.body, 38, makeRow, fillRow)
    list:SetPoint("TOPLEFT", 0, 0)
    list:SetPoint("BOTTOMRIGHT", -10, 0)
    frame:SetScript("OnShow", function() ns.Scan() end)
end

function ns.Toggle()
    if not frame then build() end
    frame:SetShown(not frame:IsShown())
end
