-- Characters on the left with how many things wait for each; on the right what waits for
-- the selected one, its rested XP, money and when it was last played.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, chars, list, info, forget
local selected

local ICON = {
    CD = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    TRAINER = "Interface\\Icons\\INV_Misc_Book_09",
    MAIL = "Interface\\Icons\\INV_Letter_15",
    RESTED = "Interface\\Icons\\Spell_Nature_Sleep",
    REPAIR = "Interface\\Icons\\Trade_BlackSmithing",
    BAGS = "Interface\\Icons\\INV_Misc_Bag_08",
}

local function classColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return c and string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) or ""
end

local function money(copper)
    if GetCoinTextureString then return GetCoinTextureString(copper or 0) end
    return tostring(math.floor((copper or 0) / 10000)) .. "g"
end

local function makeChar(r)
    r.text = S.Text(r, 12)
    r.text:SetPoint("LEFT", 8, 0)
    r.text:SetPoint("RIGHT", -30, 0)
    r.text:SetWordWrap(false)
    r.count = S.Text(r, 12, S.Accent())
    r.count:SetPoint("RIGHT", -8, 0)
    r.click = CreateFrame("Button", nil, r)
    r.click:SetAllPoints()
    r.click:SetScript("OnClick", function(self) selected = self:GetParent().entry.key; ns.Refresh() end)
end

local function fillChar(r, e)
    r.entry = e
    r.text:SetText(classColor(e.char.class) .. e.char.name .. "|r " .. S.Hex(S.MUTED) .. (e.char.level or "") .. "|r")
    local n = #ns.Tasks(e.char)
    r.count:SetText(n > 0 and tostring(n) or "")
    S.Fill(r, e.key == selected and S.PANEL or S.ROW)
    S.SetBorder(r, e.key == selected and S.Accent() or { 0, 0, 0, 0 })
end

local function makeRow(r)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(22, 22)
    r.icon:SetPoint("LEFT", 8, 0)
    r.text = S.Text(r, 13)
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 10, 0)
    r.text:SetPoint("RIGHT", -8, 0)
    r.text:SetWordWrap(false)
end

local function fillRow(r, task)
    r.icon:SetTexture(ICON[task.key])
    r.text:SetText(task.text)
    S.Fill(r, S.ROW)
end

function ns.Refresh()
    if not frame or not frame:IsShown() then return end
    local all = ns.Chars()
    if not selected or not ns.db.chars[selected] then selected = all[1] and all[1].key end
    chars:SetData(all)
    local c = selected and ns.db.chars[selected]
    local tasks = c and ns.Tasks(c) or {}
    list:SetData(tasks)
    if c then
        local now = time()
        local lines = {}
        if not c.maxLevel then
            lines[#lines + 1] = L.RESTED:format(math.floor(ns.RestedNow(c, now) * 100))
        end
        lines[#lines + 1] = L.MONEY:format(money(c.money))
        if selected ~= ns.CharKey() then lines[#lines + 1] = L.SEEN:format(ns.Span(now - c.t)) end
        local nextCd = ns.NextReady(c, now)
        if nextCd then lines[#lines + 1] = L.NEXT_CD:format(ns.Span(nextCd - now)) end
        if #tasks == 0 then lines[#lines + 1] = S.Hex(S.Accent()) .. L.NOTHING .. "|r" end
        info:SetText(table.concat(lines, "\n"))
    else
        info:SetText("")
    end
    forget:SetEnabled(selected ~= nil and selected ~= ns.CharKey())
end

local function build()
    frame = S.Window("GulliChoresFrame", L.TITLE, 640, 420)
    local body = frame.body
    chars = S.List(body, 30, makeChar, fillChar)
    chars:SetPoint("TOPLEFT", 0, 0)
    chars:SetPoint("BOTTOMLEFT", 0, 40)
    chars:SetWidth(180)
    forget = S.Button(body, 180, 30)
    forget:SetPoint("BOTTOMLEFT", 0, 0)
    forget:SetText(L.FORGET)
    forget:SetScript("OnClick", function() if selected then ns.Forget(selected); selected = nil end end)
    info = S.Text(body, 12, S.MUTED)
    info:SetPoint("TOPLEFT", 200, -2)
    info:SetPoint("RIGHT", 0, 0)
    info:SetJustifyH("LEFT")
    list = S.List(body, 32, makeRow, fillRow)
    list:SetPoint("TOPLEFT", 200, -76)
    list:SetPoint("BOTTOMRIGHT", -12, 0)
    frame:SetScript("OnShow", function() ns.Snapshot(); ns.Refresh() end)
end

function ns.Toggle()
    if not frame then build() end
    frame:SetShown(not frame:IsShown())
end
