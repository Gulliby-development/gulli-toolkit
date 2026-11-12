-- The window: my quests against each group member, or the quests only they have.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, tabs, head, listOurs, listTheirs, empty
local current = 1
local COL_W, COLS = 64, 5
local ICON = {
    has = "Interface\\RaidFrame\\ReadyCheck-Ready",
    done = "Interface\\RaidFrame\\ReadyCheck-Ready",
    no = "Interface\\RaidFrame\\ReadyCheck-NotReady",
}

local function makeOurs(r)
    r.share = S.Button(r, 80, 28)
    r.share:SetPoint("RIGHT", 0, 0)
    r.share:SetText(L.SHARE)
    r.share:SetScript("OnClick", function(self) ns.Share(self:GetParent().row.quest.id) end)
    r.cells = {}
    for i = COLS, 1, -1 do
        local c = r:CreateTexture(nil, "ARTWORK")
        c:SetSize(18, 18)
        c:SetPoint("RIGHT", r.share, "LEFT", -((COLS - i) * COL_W) - (COL_W - 18) / 2, 0)
        r.cells[i] = c
    end
    r.title = S.Text(r, 12)
    r.title:SetPoint("TOPLEFT", 10, -6)
    r.title:SetPoint("RIGHT", r.share, "LEFT", -(COLS * COL_W) - 6, 0)
    r.title:SetWordWrap(false)
    r.sub = S.Text(r, 11, S.MUTED)
    r.sub:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -4)
    r.sub:SetPoint("RIGHT", r.title, "RIGHT")
    r.sub:SetWordWrap(false)
end

local function fillOurs(r, row)
    r.row = row
    local q = row.quest
    -- The title in the quest log colour of its level.
    local title = q.level and q.level > 0 and (S.Hex(S.LevelColor(q.level)) .. q.title .. "|r") or q.title
    r.title:SetText(title .. (q.group and (" " .. S.Hex(S.Accent()) .. L.GROUP .. "|r") or ""))
    r.sub:SetText(string.format("[%d] %s", q.level, q.zone or ""))
    local states = { q.done and "done" or "has" }
    for i, s in ipairs(row.cells) do states[i + 1] = s end
    for i = 1, COLS do
        local s = states[i]
        r.cells[i]:SetShown(s ~= nil)
        if s then
            r.cells[i]:SetTexture(ICON[s])
            if s == "done" then r.cells[i]:SetVertexColor(1, 0.82, 0, 1) else r.cells[i]:SetVertexColor(1, 1, 1, 1) end
        end
    end
    r.share:SetShown(row.canShare)
end

local function makeTheirs(r)
    r.ask = S.Button(r, 80, 28)
    r.ask:SetPoint("RIGHT", 0, 0)
    r.ask:SetText(L.ASK)
    r.ask:SetScript("OnClick", function(self) ns.Ask(self:GetParent().item.title) end)
    r.title = S.Text(r, 12)
    r.title:SetPoint("TOPLEFT", 10, -6)
    r.title:SetPoint("RIGHT", r.ask, "LEFT", -6, 0)
    r.title:SetWordWrap(false)
    r.sub = S.Text(r, 11, S.MUTED)
    r.sub:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -4)
    r.sub:SetPoint("RIGHT", r.title, "RIGHT")
    r.sub:SetWordWrap(false)
end

local function fillTheirs(r, item)
    r.item = item
    r.title:SetText(item.title)
    r.sub:SetText(table.concat(item.who, ", "))
end

function ns.Refresh()
    if not frame or not frame:IsShown() then return end
    local rows, party = ns.Ours()
    local theirs = ns.Theirs()
    tabs.buttons[2]:SetText(L.TAB_THEIRS .. (#theirs > 0 and (" " .. #theirs) or ""))
    for i = 1, COLS do
        local name = i == 1 and L.ME or (party[i - 1] and party[i - 1].name)
        head.cols[i]:SetText(name or "")
    end
    listOurs:SetShown(current == 1)
    head:SetShown(current == 1)
    listTheirs:SetShown(current == 2)
    if current == 1 then
        listOurs:SetData(rows)
        empty:Set(#party == 0 and L.NO_GROUP or "")
        empty:SetShown(#party == 0)
    else
        listTheirs:SetData(theirs)
        empty:Set(L.NONE_THEIRS)
        empty:SetShown(#theirs == 0)
    end
end

local function build()
    frame = S.Window("GulliPartyQuestsFrame", L.TITLE, S.WIDE_W, 500)
    local body = frame.body
    tabs = S.Tabs(body, { L.TAB_OURS, L.TAB_THEIRS }, 160, function(i) current = i; ns.Refresh() end)

    local card = S.Card(body)
    card:SetPoint("TOPLEFT", 0, -30 - S.GAP)
    card:SetPoint("BOTTOMRIGHT")
    local cb = card.body
    head = CreateFrame("Frame", nil, cb)
    head:SetPoint("TOPLEFT", 0, 0)
    head:SetPoint("TOPRIGHT", -10, 0)
    head:SetHeight(20)
    head.cols = {}
    for i = COLS, 1, -1 do
        local t = S.Text(head, 11, S.FAINT)
        t:SetWidth(COL_W - 4)
        t:SetJustifyH("CENTER")
        t:SetWordWrap(false)
        t:SetPoint("RIGHT", -80 - (COLS - i) * COL_W, 0)
        head.cols[i] = t
    end
    local legend = S.Text(head, 11, S.FAINT)
    legend:SetPoint("LEFT", 10, 0)
    legend:SetPoint("RIGHT", head.cols[1], "LEFT", -8, 0)
    legend:SetWordWrap(false)
    legend:SetText(L.LEGEND)
    local rule = S.Divider(head, S.EDGE)
    rule:SetPoint("BOTTOMLEFT", 0, -4)
    rule:SetPoint("BOTTOMRIGHT", 0, -4)
    rule:SetHeight(1)

    listOurs = S.List(cb, 42, makeOurs, fillOurs)
    listOurs:SetPoint("TOPLEFT", 0, -28)
    listOurs:SetPoint("BOTTOMRIGHT", -10, 0)
    listTheirs = S.List(cb, 42, makeTheirs, fillTheirs)
    listTheirs:SetPoint("TOPLEFT", 0, 0)
    listTheirs:SetPoint("BOTTOMRIGHT", -10, 0)
    empty = S.Empty(cb)

    frame:SetScript("OnShow", function()
        ns.Broadcast()
        tabs:Select(current)
    end)
end

function ns.Toggle()
    S.ToggleWindow(ns.Window())
end

-- The window, for the hub (/gulli) to show inside it.
function ns.Window()
    if not frame then build() end
    return frame
end
