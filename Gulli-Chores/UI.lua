-- Characters on the left with how many things wait for each; on the right what waits for
-- the selected one, its rested XP, money and when it was last played.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, chars, list, info, forget, head, empty
local selected

local ICON = {
    CD = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    TRAINER = "Interface\\Icons\\INV_Misc_Book_09",
    MAIL = "Interface\\Icons\\INV_Letter_15",
    RESTED = "Interface\\Icons\\Spell_Nature_Sleep",
    REPAIR = "Interface\\Icons\\Trade_BlackSmithing",
    BAGS = "Interface\\Icons\\INV_Misc_Bag_08",
}
-- Each cooldown shows the icon of what it makes; a new cooldown text key gets one here.
local CD_ICON = {
    CD_TRANSMUTE = "Interface\\Icons\\Trade_Alchemy",
    CD_MOONCLOTH = "Interface\\Icons\\INV_Fabric_Moonrag_01",
}
local function cdIcon(key)
    if key == "CD_SALT" then
        local get = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
        return get and get(15846) -- Salt Shaker
    end
    return CD_ICON[key]
end

local function classColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return c and string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) or ""
end

local function money(copper)
    if GetCoinTextureString then return GetCoinTextureString(copper or 0) end
    return tostring(math.floor((copper or 0) / 10000)) .. "g"
end

local function makeChar(r)
    S.NavRow(r)
    r.line:Hide()
    r.text = S.Text(r, 12)
    r.text:SetPoint("LEFT", 12, 0)
    r.text:SetPoint("RIGHT", -30, 0)
    r.text:SetWordWrap(false)
    r.count = S.Badge(r)
    r.count:SetPoint("RIGHT", -8, 0)
    r.click = CreateFrame("Button", nil, r)
    r.click:SetAllPoints()
    r.click:SetScript("OnClick", function(self) selected = self:GetParent().entry.key; ns.Refresh() end)
end

local function fillChar(r, e)
    r.entry = e
    r.text:SetText(classColor(e.char.class) .. e.char.name .. "|r " .. S.Hex(S.MUTED) .. (e.char.level or "") .. "|r")
    local n = #ns.Tasks(e.char)
    r.count:Set(n > 0 and tostring(n) or nil, S.Accent())
    r:SetSelected(e.key == selected)
end

local function makeRow(r)
    r.icon = S.IconBox(r, 26)
    r.icon:SetPoint("LEFT", 2, 0)
    r.text = S.Text(r, 12)
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 10, 0)
    r.text:SetPoint("RIGHT", -8, 0)
    r.text:SetWordWrap(false)
end

local function fillRow(r, task)
    r.icon:SetIcon(task.cd and cdIcon(task.cd) or ICON[task.key])
    r.text:SetText(task.text)
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
        info:SetText(table.concat(lines, "\n"))
        head:SetText(classColor(c.class) .. c.name .. "|r  " .. S.Hex(S.MUTED) .. (c.level or "") .. "|r")
    else
        info:SetText("")
        head:SetText("")
    end
    empty:SetShown(c ~= nil and #tasks == 0)
    empty:Set(L.NOTHING)
    forget:SetEnabled(selected ~= nil and selected ~= ns.CharKey())
end

local function build()
    frame = S.Window("GulliChoresFrame", L.TITLE, S.WIDE_W, 460)
    local body = frame.body
    local left = S.Card(body)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(200)
    forget = S.Ghost(S.Button(left.body, 1, 30))
    forget:SetPoint("BOTTOMLEFT")
    forget:SetPoint("BOTTOMRIGHT")
    forget:SetText(L.FORGET)
    forget:SetScript("OnClick", function() if selected then ns.Forget(selected); selected = nil end end)
    chars = S.List(left.body, 32, makeChar, fillChar)
    chars:SetPoint("TOPLEFT")
    chars:SetPoint("BOTTOMRIGHT", -10, 40)

    local top = S.Card(body)
    top:SetPoint("TOPLEFT", left, "TOPRIGHT", S.GAP, 0)
    top:SetPoint("TOPRIGHT")
    top:SetHeight(104)
    head = S.Text(top.body, 15)
    head:SetPoint("TOPLEFT")
    head:SetPoint("TOPRIGHT")
    head:SetWordWrap(false)
    info = S.Text(top.body, 12, S.MUTED)
    info:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -8)
    info:SetPoint("RIGHT")
    info:SetJustifyV("TOP")
    info:SetSpacing(3)

    local right = S.Card(body)
    right:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -S.GAP)
    right:SetPoint("BOTTOMRIGHT")
    list = S.List(right.body, 34, makeRow, fillRow)
    list:SetPoint("TOPLEFT")
    list:SetPoint("BOTTOMRIGHT", -10, 0)
    empty = S.Empty(right.body)
    frame:SetScript("OnShow", function() ns.Snapshot(); ns.Refresh() end)
end

function ns.Toggle()
    S.ToggleWindow(ns.Window())
end

-- The window, for the hub (/gulli) to show inside it.
function ns.Window()
    if not frame then build() end
    return frame
end
