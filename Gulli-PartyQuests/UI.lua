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
local ROW_H, ZONE_H, THEIRS_H = 34, 30, 44
local SIDE_H, SIDE_Y = 28, 3
local SHARE_W = 104 -- fits "Поделиться" and "Udostępnij"
-- The cells speak the game's quest marks: a grey "?" is a quest in the log, a yellow "?" one
-- ready to hand in, a yellow "!" one the member can still take.
local ICON = {
    has = "Interface\\GossipFrame\\IncompleteQuestIcon",
    done = "Interface\\GossipFrame\\ActiveQuestIcon",
    no = "Interface\\GossipFrame\\AvailableQuestIcon",
    turned = "Interface\\RaidFrame\\ReadyCheck-Ready",
    unknown = "Interface\\CharacterFrame\\Disconnect-Icon",
}
local CELL_TEXT = { has = "CELL_HAS", done = "CELL_DONE", no = "CELL_NO", turned = "CELL_TURNED", unknown = "ST_OFFLINE" }
local LEGEND = { "has", "done", "no", "turned", "unknown" }
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

-- "5 Quest title" with the level and the title in the level's colour.
local function levelTitle(level, title)
    if not level or level <= 0 then return title end
    return S.Hex(S.LevelColor(level)) .. level .. "  " .. title .. "|r"
end

-- One cell: "3/8" while the member's module sends the objectives, else the quest mark of its
-- state. who is the member (nil for me), for the tooltip.
local function setCell(c, s, who)
    c.s, c.who = s, who
    c.icon:Hide(); c.text:SetText("")
    if not s then return end
    if s.state == "has" and s.need then
        c.text:SetText(s.have .. "/" .. s.need)
    else
        c.icon:Show()
        c.icon:SetTexture(ICON[s.state] or ICON.no)
        c.icon:SetAlpha(s.state == "unknown" and 0.6 or 1)
    end
end

local function cellTip(self)
    local s = self.s
    if not s or not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    local who = self.who
    GameTooltip:AddLine(who and (classHex(who.class) .. who.name .. "|r") or L.ME)
    GameTooltip:AddLine(L[CELL_TEXT[s.state]] or s.state, 1, 1, 1)
    if s.need then GameTooltip:AddLine(s.have .. "/" .. s.need, 0.77, 0.72, 0.65) end
    GameTooltip:Show()
end

-- A list row is a zone header (item.head) or an entry: r.zone and r.c take turns.
local function makeZone(r)
    r.zone = CreateFrame("Frame", nil, r)
    r.zone:SetAllPoints()
    r.zone.text = S.Text(r.zone, 12, S.GOLD_DIM, nil, "bold")
    r.zone.text:SetPoint("LEFT", 10, 0)
    r.zone.text:SetPoint("RIGHT", -10, 0)
    r.zone.text:SetJustifyH("LEFT")
    r.zone.text:SetWordWrap(false)
    r.c = CreateFrame("Frame", nil, r)
    r.c:SetAllPoints()
end

local function fillZone(r, item)
    r.zone:SetShown(item.head and true or false)
    r.c:SetShown(not item.head)
    if not item.head then return false end
    S.Fill(r, S.SIDE)
    r.zone.text:SetText(S.Upper(item.zone or L.ZONE_UNKNOWN) .. "  |r" .. S.Hex(S.FAINT) .. item.count .. "|r"
        .. (item.here and (S.DOT .. S.Hex(S.Accent()) .. L.HERE .. "|r") or ""))
    return true
end

local function makeOurs(r)
    makeZone(r)
    local c = r.c
    local function pick() selected = r.row.quest.id; ns.Refresh() end
    c:EnableMouse(true)
    c:SetScript("OnMouseDown", pick)
    r.share = S.Button(c, SHARE_W, 28)
    r.share:SetPoint("RIGHT", 0, 0)
    r.share:SetText(L.SHARE)
    r.share:SetScript("OnClick", function() ns.Share(r.row.quest.id); ns.Refresh() end)
    r.cells = {}
    for i = COLS, 1, -1 do
        local cell = CreateFrame("Frame", nil, c)
        cell:SetSize(COL_W - 4, 30)
        cell:SetPoint("RIGHT", r.share, "LEFT", -((COLS - i) * COL_W) - 2, 0)
        cell.icon = cell:CreateTexture(nil, "ARTWORK")
        cell.icon:SetSize(18, 18)
        cell.icon:SetPoint("CENTER")
        cell.text = S.Text(cell, 12)
        cell.text:SetPoint("CENTER")
        cell:EnableMouse(true)
        cell:SetScript("OnMouseDown", pick)
        cell:SetScript("OnEnter", cellTip)
        cell:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        r.cells[i] = cell
    end
    r.title = S.Text(c, 12)
    r.title:SetPoint("LEFT", 10, 0)
    r.title:SetPoint("RIGHT", r.share, "LEFT", -(COLS * COL_W) - 6, 0)
    r.title:SetJustifyH("LEFT")
    r.title:SetWordWrap(false)
end

local function fillOurs(r, row)
    if fillZone(r, row) then return end
    r.row = row
    local q = row.quest
    S.Fill(r, q.id == selected and S.RAISED or S.CLEAR)
    local title = levelTitle(q.level, q.title)
    if q.group then title = title .. "  " .. S.Hex(S.Accent()) .. L.GROUP .. "|r" end
    if q.spare and q.spare > 0 then title = title .. S.DOT .. S.Hex(S.MUTED) .. L.SPARE:format(q.spare) .. "|r" end
    r.title:SetText(title)
    setCell(r.cells[1], row.mine)
    for i = 2, COLS do setCell(r.cells[i], row.cells[i - 1], row.party and row.party[i - 1]) end
    r.share:SetShown(row.canShare)
end

local function makeTheirs(r)
    makeZone(r)
    local c = r.c
    r.ask = S.Button(c, 96, 28)
    r.ask:SetPoint("RIGHT", 0, 0)
    r.ask:SetText(L.REQUEST_BTN)
    r.ask:SetScript("OnClick", function()
        local item = r.item
        local how = ns.Request(item.id, item.title, item.who[1])
        footer:SetStatus((how == "addon" and L.REQUEST_SENT or L.REQUEST_WHISPER):format(item.who[1]), S.GOOD)
    end)
    r.title = S.Text(c, 12)
    r.title:SetPoint("TOPLEFT", 10, -6)
    r.title:SetPoint("RIGHT", r.ask, "LEFT", -6, 0)
    r.title:SetJustifyH("LEFT")
    r.title:SetWordWrap(false)
    r.sub = S.Text(c, 12, S.MUTED)
    r.sub:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -4)
    r.sub:SetPoint("RIGHT", r.title, "RIGHT")
    r.sub:SetJustifyH("LEFT")
    r.sub:SetWordWrap(false)
end

local classOf = {} -- member name -> class, for the names on the Their quests tab

local function fillTheirs(r, item)
    if fillZone(r, item) then return end
    r.item = item
    S.Fill(r, S.CLEAR)
    r.title:SetText(levelTitle(item.level, item.title))
    local who = {}
    for i, name in ipairs(item.who) do who[i] = classHex(classOf[name]) .. name .. (classOf[name] and "|r" or "") end
    r.sub:SetText(table.concat(who, ", ") .. (item.turned and (S.DOT .. S.Hex(S.WARN) .. L.YOU_DID .. "|r") or ""))
    r.ask:SetShown(not item.turned)
end

local function fillHead(party)
    for i = 1, COLS do
        local col = head.cols[i]
        local m = i > 1 and party[i - 1] or nil
        col.member = m
        if i == 1 then
            col.name:SetText(L.ME); col.status:SetText("")
            col.name:ClearAllPoints()
            if #party == 0 then col.name:SetPoint("LEFT"); col.name:SetPoint("RIGHT")
            else col.name:SetPoint("TOPLEFT"); col.name:SetPoint("TOPRIGHT") end
        elseif m then
            col.name:SetText((m.leader and LEADER or "") .. classHex(m.class) .. m.name .. "|r")
            local st = STATUS[ns.Status(m)]
            col.status:SetText(L[st[1]]); col.status:SetTextColor(st[2][1], st[2][2], st[2][3], 1)
        else
            col.name:SetText(""); col.status:SetText("")
        end
    end
end

local function fillDetail(rows, inGroup)
    local row
    for _, r in ipairs(rows) do if r.quest.id == selected then row = r end end
    detail.legend:SetShown(not row and inGroup)
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
    detail.lines:SetText(table.concat(parts, S.DOT))
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
    if #party == 0 then footer:SetStatus(L.NO_GROUP, S.MUTED); return end
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
    -- Settings has nothing for the footer: it hides, so the page reaches the bottom
    footer:SetShown(current ~= 3)
    frame.body:SetPoint("BOTTOMRIGHT", -S.PAD, (current ~= 3 and S.FOOTER_H or 0) + S.PAD)
    card:SetPoint("BOTTOMRIGHT", 0, current == 1 and (DETAIL_H + S.GAP) or 0)
    if current == 1 then
        for _, r in ipairs(rows) do r.party = party end
        head.count:SetText(S.Upper(L.TAB_OURS) .. "  |r" .. S.Hex(S.FAINT) .. #rows .. "|r")
        listOurs:SetData(ns.ByZone(rows, function(r) return r.quest.zone end, function(r) return r.order end))
        fillDetail(rows, #party > 0)
        local canShare = false
        for _, r in ipairs(rows) do if r.canShare then canShare = true end end
        shareAll:SetEnabled(canShare)
        -- The empty state sits over the list, so it shows only when the list is empty;
        -- with quests but no group, the footer says so instead.
        if #rows == 0 then
            empty:Set(#party == 0 and L.NO_GROUP or (ns.Get("zoneOnly") and L.NONE_ZONE or L.NONE_MINE))
        end
        empty:SetShown(#rows == 0)
        footerStatus(rows, party)
    elseif current == 2 then
        for _, m in ipairs(party) do classOf[m.name] = m.class end
        listTheirs:SetData(ns.ByZone(theirs, function(item) return item.zone end))
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
        row("escort", L.OPT_ESCORT, L.OPT_ESCORT_D, ns.OPT_ICON.escort),
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

    tabs = S.PageTabs(body, { L.TAB_OURS, L.TAB_THEIRS, L.TAB_SETTINGS }, 150, function(i) current = i; ns.Refresh() end, nil, { S.TAB.quests, S.TAB.group, S.TAB.settings })

    -- beside the page tabs: lower than them and lifted, clear of the hairline under the tabs
    zonePill = S.Pill(body, 110, SIDE_H)
    zonePill:SetText(L.THIS_ZONE)
    zonePill:SetPoint("TOPRIGHT", 0, SIDE_Y)
    zonePill:SetScript("OnClick", function() ns.Set("zoneOnly", not ns.Get("zoneOnly")) end)
    search = S.Edit(body, 180, SIDE_H)
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
        col:SetPoint("RIGHT", -SHARE_W - (COLS - i) * COL_W - 2, 0)
        col.name = S.Text(col, 12)
        col.name:SetPoint("TOPLEFT"); col.name:SetPoint("TOPRIGHT")
        col.name:SetJustifyH("CENTER"); col.name:SetWordWrap(false)
        col.status = S.Text(col, 12, S.FAINT)
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
    head.count = S.Text(head, 12, S.GOLD_DIM, nil, "bold")
    head.count:SetPoint("LEFT", 10, 0)
    local rule = S.Divider(head, S.EDGE)
    rule:SetPoint("BOTTOMLEFT", 0, -4)
    rule:SetPoint("BOTTOMRIGHT", 0, -4)
    rule:SetHeight(1)

    listOurs = S.List(cb, ROW_H, makeOurs, fillOurs)
    listOurs.heightOf = function(item) return item.head and ZONE_H or ROW_H end
    listOurs:SetPoint("TOPLEFT", 0, -40)
    listOurs:SetPoint("BOTTOMRIGHT", -10, 0)
    listTheirs = S.List(cb, THEIRS_H, makeTheirs, fillTheirs)
    listTheirs.heightOf = function(item) return item.head and ZONE_H or THEIRS_H end
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
    detail.lines = S.Note(detail.body, 12)
    detail.lines:SetPoint("TOPLEFT", detail.title, "BOTTOMLEFT", 0, -10)
    detail.lines:SetPoint("RIGHT", detail.body, "RIGHT")
    detail.lines:SetMaxLines(3)
    -- With nothing picked, the card explains the marks of the member columns.
    local marks = {}
    for i, state in ipairs(LEGEND) do marks[i] = "|T" .. ICON[state] .. ":16:16|t " .. L[CELL_TEXT[state]] end
    detail.legend = S.Note(detail.body, 12)
    detail.legend:SetPoint("TOPLEFT", detail.title, "BOTTOMLEFT", 0, -10)
    detail.legend:SetPoint("RIGHT", detail.body, "RIGHT")
    detail.legend:SetJustifyH("LEFT")
    detail.legend:SetMaxLines(3)
    detail.legend:SetText(table.concat(marks, S.DOT))

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

-- An escort or event quest about to start: who the group still waits for, and Ask the group.
function ns.ShowEscort()
    local e = ns.escort
    if not e then return end
    local st = ns.EscortState(e.id)
    local buttons
    if not st.allReady then
        buttons = { { text = e.asked and L.ESC_ASK_AGAIN or L.ESC_ASK_BTN, primary = not e.asked, keep = true,
                      onClick = function() ns.AskEscort(); ns.ShowEscort() end } }
    end
    ns.escortCard = S.Toast({ key = "escort", icon = ns.OPT_ICON.escort, kind = st.allReady and "good" or "warn",
        title = L.ESC_TITLE:format(e.title or ""), text = ns.EscortText(st), buttons = buttons, seconds = 0,
        onClose = function() if ns.escort == e then ns.escort = nil end end })
    return ns.escortCard
end

function ns.HideEscort()
    local t = ns.escortCard
    if t and t:IsShown() then t:Dismiss() end
end

-- A member asks whether I am ready for their escort or event quest.
function ns.ShowEscortAsk()
    local a = ns.escortAsk
    if not a then return end
    return S.Toast({ key = "escortAsk", icon = ns.OPT_ICON.escort, title = L.ESC_ASKED:format(a.from),
        text = a.title, seconds = 60, buttons = {
            { text = L.ESC_NOT_YET, onClick = function() ns.AnswerEscort(a.id, false) end },
            { text = L.ESC_IM_READY, primary = true, onClick = function() ns.AnswerEscort(a.id, true) end },
        } })
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
