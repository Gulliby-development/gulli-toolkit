-- The window: my quests against each group member with their progress, the quests only they
-- have, and the settings.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, tabs, head, listOurs, listTheirs, empty, card, detail, settings, search, zonePill, footer, shareAll
local current = 1
local selected -- quest id shown in the detail card
local COL_W, COLS = 76, 5
local DETAIL_H = 96
local ICON = {
    has = "Interface\\RaidFrame\\ReadyCheck-Ready",
    done = "Interface\\RaidFrame\\ReadyCheck-Ready",
    no = "Interface\\RaidFrame\\ReadyCheck-NotReady",
    turned = "Interface\\RaidFrame\\ReadyCheck-Waiting",
}
local LEADER = "|TInterface\\GroupFrame\\UI-Group-LeaderIcon:12:12|t "
local STATUS = { fresh = { "ST_FRESH", S.GOOD }, stale = { "ST_STALE", S.WARN }, none = { "ST_NONE", S.FAINT },
                 offline = { "ST_OFFLINE", S.BAD } }

local function classHex(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if not c then return "" end
    return string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
end

local function filter()
    return { zone = ns.Get("zoneOnly") and GetRealZoneText and GetRealZoneText() or nil,
             text = search and search:GetText() or nil }
end

-- One cell: the ready-check icon, or "3/8" when the member's module sent the objectives.
local function setCell(c, s)
    c.icon:Hide(); c.text:SetText("")
    if not s then return end
    if s.state == "unknown" then
        c.text:SetText("?"); c.text:SetTextColor(S.FAINT[1], S.FAINT[2], S.FAINT[3], 1)
    elseif (s.state == "has" or s.state == "done") and s.need then
        local col = s.state == "done" and S.GOOD or S.TEXT
        c.text:SetText(s.have .. "/" .. s.need); c.text:SetTextColor(col[1], col[2], col[3], 1)
    else
        c.icon:Show()
        c.icon:SetTexture(ICON[s.state] or ICON.no)
        if s.state == "done" then c.icon:SetVertexColor(1, 0.82, 0, 1) else c.icon:SetVertexColor(1, 1, 1, 1) end
    end
end

local function makeOurs(r)
    r:EnableMouse(true)
    r:SetScript("OnMouseDown", function(self) selected = self.row.quest.id; ns.Refresh() end)
    r.share = S.Button(r, 80, 28)
    r.share:SetPoint("RIGHT", 0, 0)
    r.share:SetText(L.SHARE)
    r.share:SetScript("OnClick", function(self) ns.Share(self:GetParent().row.quest.id); ns.Refresh() end)
    r.cells = {}
    for i = COLS, 1, -1 do
        local c = CreateFrame("Frame", nil, r)
        c:SetSize(COL_W - 4, 30)
        c:SetPoint("RIGHT", r.share, "LEFT", -((COLS - i) * COL_W) - 2, 0)
        c.icon = c:CreateTexture(nil, "ARTWORK")
        c.icon:SetSize(18, 18)
        c.icon:SetPoint("CENTER")
        c.text = S.Text(c, 12)
        c.text:SetPoint("CENTER")
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
    S.Fill(r, q.id == selected and S.RAISED or S.CLEAR)
    local title = q.level and q.level > 0 and (S.Hex(S.LevelColor(q.level)) .. q.title .. "|r") or q.title
    r.title:SetText(title .. (q.group and (" " .. S.Hex(S.Accent()) .. L.GROUP .. "|r") or ""))
    local sub = string.format("[%d] %s", q.level, q.zone or "")
    if q.spare and q.spare > 0 then sub = sub .. "  ·  " .. L.SPARE:format(q.spare) end
    r.sub:SetText(sub)
    setCell(r.cells[1], row.mine)
    for i = 2, COLS do setCell(r.cells[i], row.cells[i - 1]) end
    r.share:SetShown(row.canShare)
end

local function makeTheirs(r)
    r.ask = S.Button(r, 96, 28)
    r.ask:SetPoint("RIGHT", 0, 0)
    r.ask:SetText(L.REQUEST_BTN)
    r.ask:SetScript("OnClick", function(self)
        local item = self:GetParent().item
        local how = ns.Request(item.id, item.title, item.who[1])
        footer:SetStatus((how == "addon" and L.REQUEST_SENT or L.REQUEST_WHISPER):format(item.who[1]), S.GOOD)
    end)
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
    r.sub:SetText(table.concat(item.who, ", ") .. (item.turned and ("  ·  " .. S.Hex(S.WARN) .. L.YOU_DID .. "|r") or ""))
    r.ask:SetShown(not item.turned)
end

local function fillHead(party)
    for i = 1, COLS do
        local col = head.cols[i]
        local m = i > 1 and party[i - 1] or nil
        col.member = m
        if i == 1 then
            col.name:SetText(L.ME); col.status:SetText("")
        elseif m then
            col.name:SetText((m.leader and LEADER or "") .. classHex(m.class) .. m.name .. "|r")
            local st = STATUS[ns.Status(m)]
            col.status:SetText(L[st[1]]); col.status:SetTextColor(st[2][1], st[2][2], st[2][3], 1)
        else
            col.name:SetText(""); col.status:SetText("")
        end
    end
end

local function fillDetail(rows)
    local row
    for _, r in ipairs(rows) do if r.quest.id == selected then row = r end end
    if not row then
        detail.title:SetText(L.PICK_QUEST)
        detail.lines:SetText("")
        detail.track:Hide()
        return
    end
    detail.title:SetText(row.quest.title)
    local parts = {}
    for i, o in ipairs(row.quest.obj) do
        parts[#parts + 1] = L.ME .. ": " .. (o.text or (o.have .. "/" .. o.need))
        if i >= 2 then break end
    end
    for _, d in ipairs(ns.Detail(selected)) do
        local s
        if d.obj then
            local o = {}
            for i, x in ipairs(d.obj) do o[i] = x[1] .. "/" .. x[2] end
            s = table.concat(o, ", ")
        else
            s = L["CELL_" .. d.state:upper()] or d.state
        end
        parts[#parts + 1] = d.name .. ": " .. s
    end
    detail.lines:SetText(table.concat(parts, "   ·   "))
    detail.track:Show()
end

local function footerStatus(rows, party)
    local last = ns.lastShare
    if last and time() - last.t < 30 and next(last.replies) then
        local out = {}
        for name, what in pairs(last.replies) do out[#out + 1] = name .. ": " .. (L["SH_" .. what:upper()] or what) end
        footer:SetStatus(last.title .. " — " .. table.concat(out, ", "), S.MUTED)
        return
    end
    local text, synced = ns.Summary(rows, party)
    footer:SetStatus(text or "", synced and S.GOOD or S.MUTED)
end

function ns.Refresh()
    if not frame or not frame:IsShown() then return end
    local rows, party = ns.Ours(filter())
    local theirs = ns.Theirs(filter())
    tabs.buttons[2]:SetText(L.TAB_THEIRS .. (#theirs > 0 and (" " .. #theirs) or ""))
    fillHead(party)
    zonePill:SetSelected(ns.Get("zoneOnly"))
    local lists = current ~= 3
    card:SetShown(lists)
    search:SetShown(lists)
    zonePill:SetShown(current == 1)
    settings:SetShown(current == 3)
    detail:SetShown(current == 1)
    listOurs:SetShown(current == 1)
    head:SetShown(current == 1)
    listTheirs:SetShown(current == 2)
    shareAll:SetShown(current == 1)
    card:SetPoint("BOTTOMRIGHT", 0, current == 1 and (DETAIL_H + S.GAP) or 0)
    if current == 1 then
        listOurs:SetData(rows)
        fillDetail(rows)
        local canShare = false
        for _, r in ipairs(rows) do if r.canShare then canShare = true end end
        shareAll:SetEnabled(canShare)
        if #party == 0 then empty:Set(L.NO_GROUP)
        elseif #rows == 0 then empty:Set(ns.Get("zoneOnly") and L.NONE_ZONE or L.NONE_MINE) end
        empty:SetShown(#party == 0 or #rows == 0)
        footerStatus(rows, party)
    elseif current == 2 then
        listTheirs:SetData(theirs)
        empty:Set(L.NONE_THEIRS)
        empty:SetShown(#theirs == 0)
        footer:SetStatus(L.THEIRS_HINT, S.MUTED)
    else
        empty:Hide()
        footer:SetStatus("")
    end
end

local function buildSettings(body)
    settings = CreateFrame("Frame", nil, body)
    settings:SetPoint("TOPLEFT", 0, -30 - S.GAP)
    settings:SetPoint("BOTTOMRIGHT")
    local function row(key, label, desc, icon)
        return { label, desc, function() return ns.Get(key) end, function(v) ns.Set(key, v) end, icon = icon }
    end
    local group = S.SettingsCard(settings, L.SET_GROUP, {
        row("zoneOnly", L.OPT_ZONE, L.OPT_ZONE_D, "Interface\\Icons\\INV_Misc_Map_01"),
        row("autoShare", L.OPT_AUTOSHARE, L.OPT_AUTOSHARE_D, ns.OPT_ICON.autoShare),
        row("track", L.OPT_TRACK, L.OPT_TRACK_D, "Interface\\Icons\\INV_Misc_Spyglass_02"),
        row("tooltip", L.OPT_TOOLTIP, L.OPT_TOOLTIP_D, ns.OPT_ICON.tooltip),
    })
    local half = (S.WIDE_W - 2 * S.PAD - S.GAP) / 2
    group:SetPoint("TOPLEFT")
    group:SetWidth(half)
    local note = S.SettingsCard(settings, L.SET_NOTIFY, {
        row("sound", L.OPT_SOUND, nil, "Interface\\Icons\\INV_Misc_Bell_01"),
        row("nAccept", L.N_ACCEPT, nil, "Interface\\Icons\\INV_Scroll_03"),
        row("nObjective", L.N_OBJECTIVE, nil, "Interface\\Icons\\INV_Misc_Bag_10"),
        row("nComplete", L.N_COMPLETE, nil, "Interface\\Icons\\INV_Misc_Book_09"),
        row("nTurnin", L.N_TURNIN, nil, "Interface\\Icons\\INV_Misc_Coin_01"),
        row("nAll", L.N_ALL, nil, "Interface\\Icons\\Ability_Warrior_BattleShout"),
    })
    note:SetPoint("TOPRIGHT")
    note:SetWidth(half)
end

local function build()
    frame = S.Window("GulliPartyQuestsFrame", L.TITLE, S.WIDE_W, S.DOCK_H)
    local body = frame.body
    footer = S.Footer(frame)
    shareAll = S.FitButton(frame, L.SHARE_ALL, 32, 110)
    S.Primary(shareAll)
    footer:Add(shareAll)
    shareAll:SetScript("OnClick", function()
        footer:SetStatus(L.SHARED_N:format(ns.ShareAll()), S.GOOD)
    end)

    tabs = S.Tabs(body, { L.TAB_OURS, L.TAB_THEIRS, L.TAB_SETTINGS }, 150, function(i) current = i; ns.Refresh() end)

    zonePill = S.Pill(body, 110, 30)
    zonePill:SetText(L.THIS_ZONE)
    zonePill:SetPoint("TOPRIGHT", 0, 0)
    zonePill:SetScript("OnClick", function() ns.Set("zoneOnly", not ns.Get("zoneOnly")) end)
    search = S.Edit(body, 180, 30)
    search:SetJustifyH("LEFT")
    search:SetPoint("RIGHT", zonePill, "LEFT", -8, 0)
    S.Placeholder(search, L.SEARCH)
    search:HookScript("OnTextChanged", function() ns.Refresh() end)

    card = S.Card(body)
    card:SetPoint("TOPLEFT", 0, -30 - S.GAP)
    card:SetPoint("BOTTOMRIGHT", 0, DETAIL_H + S.GAP)
    local cb = card.body
    head = CreateFrame("Frame", nil, cb)
    head:SetPoint("TOPLEFT", 0, 0)
    head:SetPoint("TOPRIGHT", -10, 0)
    head:SetHeight(32)
    head.cols = {}
    for i = COLS, 1, -1 do
        local col = CreateFrame("Frame", nil, head)
        col:SetSize(COL_W - 4, 32)
        col:SetPoint("RIGHT", -80 - (COLS - i) * COL_W - 2, 0)
        col.name = S.Text(col, 11)
        col.name:SetPoint("TOPLEFT"); col.name:SetPoint("TOPRIGHT")
        col.name:SetJustifyH("CENTER"); col.name:SetWordWrap(false)
        col.status = S.Text(col, 10, S.FAINT)
        col.status:SetPoint("TOPLEFT", col.name, "BOTTOMLEFT", 0, -3)
        col.status:SetPoint("TOPRIGHT", col.name, "BOTTOMRIGHT", 0, -3)
        col.status:SetJustifyH("CENTER"); col.status:SetWordWrap(false)
        col:EnableMouse(true)
        col:SetScript("OnEnter", function(self)
            local m = self.member
            if not m or not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine(m.name)
            GameTooltip:AddLine(L.LEVEL_N:format(m.level or 0), 1, 1, 1)
            GameTooltip:AddLine(L[STATUS[ns.Status(m)][1] .. "_D"], 0.6, 0.6, 0.6, true)
            GameTooltip:Show()
        end)
        col:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        head.cols[i] = col
    end
    local legend = S.Text(head, 11, S.FAINT)
    legend:SetPoint("LEFT", 10, 0)
    legend:SetPoint("RIGHT", head.cols[1], "LEFT", -8, 0)
    legend:SetWordWrap(true)
    legend:SetMaxLines(2)
    legend:SetText(L.LEGEND)
    local rule = S.Divider(head, S.EDGE)
    rule:SetPoint("BOTTOMLEFT", 0, -4)
    rule:SetPoint("BOTTOMRIGHT", 0, -4)
    rule:SetHeight(1)

    listOurs = S.List(cb, 42, makeOurs, fillOurs)
    listOurs:SetPoint("TOPLEFT", 0, -40)
    listOurs:SetPoint("BOTTOMRIGHT", -10, 0)
    listTheirs = S.List(cb, 42, makeTheirs, fillTheirs)
    listTheirs:SetPoint("TOPLEFT", 0, 0)
    listTheirs:SetPoint("BOTTOMRIGHT", -10, 0)
    empty = S.Empty(cb)

    detail = S.Card(body)
    detail:SetPoint("BOTTOMLEFT")
    detail:SetPoint("BOTTOMRIGHT")
    detail:SetHeight(DETAIL_H)
    detail.track = S.FitButton(detail.body, L.TRACK_ALL, 28, 120)
    detail.track:SetPoint("TOPRIGHT")
    detail.track:SetScript("OnClick", function()
        if selected then ns.TrackForAll(selected); footer:SetStatus(L.TRACKED, S.GOOD) end
    end)
    detail.title = S.Text(detail.body, 13)
    detail.title:SetPoint("TOPLEFT")
    detail.title:SetPoint("RIGHT", detail.track, "LEFT", -8, 0)
    detail.title:SetWordWrap(false)
    detail.lines = S.Note(detail.body, 11)
    detail.lines:SetPoint("TOPLEFT", detail.title, "BOTTOMLEFT", 0, -10)
    detail.lines:SetPoint("RIGHT", detail.body, "RIGHT")
    detail.lines:SetMaxLines(3)

    buildSettings(body)

    frame:SetScript("OnShow", function()
        ns.Broadcast()
        tabs:Select(current)
    end)
end

-- A Gulli HUD notice when a member asks for one of my quests.
function ns.ShowRequest()
    local req = ns.requests[#ns.requests]
    if not req then return end
    local mine = false
    for _, q in ipairs(ns.MyQuests()) do if q.id == req.id and q.pushable then mine = true end end
    local buttons = mine and { { text = L.SHARE, primary = true, onClick = function() ns.Share(req.id) end } } or nil
    return S.Toast({ key = "request", icon = "Interface\\Icons\\INV_Letter_15", title = L.REQUEST_TITLE:format(req.from),
        text = req.title, buttons = buttons, seconds = 30 })
end

-- Opens one tab (1 my quests, 2 theirs, 3 settings).
function ns.ShowTab(i)
    local f = ns.Window()
    if not f:IsShown() then ns.Toggle() end
    tabs:Select(i)
end

function ns.Toggle()
    S.ToggleWindow(ns.Window())
end

-- The window, for the hub (/gulli) to show inside it.
function ns.Window()
    if not frame then build() end
    return frame
end
