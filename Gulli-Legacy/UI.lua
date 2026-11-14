-- Four tabs. Plan: the Progress Track with its rewards, the goal, and the next steps fastest
-- first. Characters: each saved character with its fastest step. Challenges: every Legacy
-- challenge and how far it is. Settings: what the plan may suggest and the tracker.
-- On screen: a Gulli HUD list of the pinned (or first) steps, and a notice for a new point.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, tabs, footer, gameBtn
local pages = {}
local track, goalText, goalSub, goalBtn, stepList, stepsCard, emptySteps
local charList, chalList, switchRows = nil, nil, {}
local tracker
local detail, detailID, partList, partEmpty, sortTabs
local TRACK_W = 520
local GUIDE_LINES = 7
local PART_ICON = { done = "Interface\\RaidFrame\\ReadyCheck-Ready", open = "Interface\\RaidFrame\\ReadyCheck-Waiting" }
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local ACTIVITY_ICON = {
    level = "Interface\\Icons\\Spell_Holy_SurgeOfLight", skill = "Interface\\Icons\\INV_Misc_Note_01",
    dungeon = "Interface\\Icons\\INV_Misc_Key_14", raid = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
    pvp = "Interface\\Icons\\INV_BannerPVP_02", solo = "Interface\\Icons\\INV_Misc_Map_01",
}

local function classColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return c and string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) or ""
end

local function tagColor(s)
    if s.new then return S.Accent() end
    local a = s.ch.activity
    if a == "dungeon" or a == "raid" then return S.WARN end
    if a == "pvp" then return S.BAD end
    return S.GOOD
end

local function stepIcon(s)
    return s.ch.icon or ACTIVITY_ICON[s.ch.kind] or DEFAULT_ICON
end

-- The Progress Track ------------------------------------------------------------------------

local function buildTrack(parent)
    local c = S.Card(parent, L.TRACK, nil, "Interface\\AddOns\\Gulli-Legacy\\icon")
    c.bar = S.Progress(c.body, 8)
    c.bar:SetPoint("TOPLEFT", 0, -26)
    c.bar:SetWidth(TRACK_W)
    c.marks = {}
    for i in ipairs(ns.REWARDS) do
        local m = CreateFrame("Frame", nil, c.body)
        m:SetSize(30, 30)
        m.icon = S.IconBox(m, 22)
        m.icon:SetPoint("TOP", 0, 0)
        m.level = S.Text(m, 10, S.MUTED)
        m.level:SetPoint("TOP", m.icon, "BOTTOM", 0, -14)
        m:EnableMouse(true)
        m:SetScript("OnEnter", function(self)
            if not GameTooltip or not self.reward then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.reward.name or "")
            GameTooltip:AddLine(L.REWARD_AT:format(self.reward.level), S.MUTED[1], S.MUTED[2], S.MUTED[3])
            GameTooltip:Show()
        end)
        m:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        c.marks[i] = m
    end
    c.next = S.Text(c.body, 12)
    c.next:SetPoint("TOPLEFT", TRACK_W + 24, 2)
    c.next:SetPoint("RIGHT", 0, 0)
    c.next:SetWordWrap(false)
    c.spent = S.Text(c.body, 11, S.MUTED)
    c.spent:SetPoint("TOPLEFT", c.next, "BOTTOMLEFT", 0, -6)
    c.spent:SetPoint("RIGHT", 0, 0)
    c.spent:SetWordWrap(false)
    c.avail = S.Text(c.body, 11, S.MUTED)
    c.avail:SetPoint("TOPLEFT", c.spent, "BOTTOMLEFT", 0, -4)
    c.avail:SetPoint("RIGHT", 0, 0)
    c.avail:SetWordWrap(false)
    return c
end

local function fillTrack(p)
    local rewards = ns.Rewards(p.earned)
    local top = ns.REWARDS[#ns.REWARDS]
    track:SetTitle(L.TRACK, L.EARNED_OF:format(p.earned, ns.TOTAL))
    track.bar:Set(p.earned / top)
    local nextR
    for i, r in ipairs(rewards) do
        local m = track.marks[i]
        m.reward = r
        m:ClearAllPoints()
        m:SetPoint("TOP", track.body, "TOPLEFT", math.floor(TRACK_W * r.level / top) - (i == #rewards and 12 or 0), 0)
        m.icon:SetIcon(r.icon)
        m.icon.tex:SetDesaturated(not r.got)
        m.icon:SetAlpha(r.got and 1 or 0.75)
        if not r.got and not nextR then nextR = r end
        m.level:SetText(r.level)
        local c = r.got and S.GOOD or (r == nextR and S.GOLD or S.MUTED)
        m.level:SetTextColor(c[1], c[2], c[3], 1)
        S.SetBorder(m.icon, r.got and S.GOOD or (r == nextR and S.GOLD or S.BORDER))
    end
    track.next:SetText(nextR and L.TO_REWARD:format(nextR.level - p.earned, nextR.name) or L.ALL_REWARDS)
    track.spent:SetText(p.spent and L.SPENT:format(p.spent, ns.MAX_SPEND) or L.SPENT_UNKNOWN)
    if p.avail and p.avail > 0 then
        track.avail:SetText(S.Hex(S.GOOD) .. L.AVAIL:format(p.avail) .. "|r")
    else
        track.avail:SetText("")
    end
end

-- Steps -------------------------------------------------------------------------------------

local function makeStep(r)
    -- A click on the row (outside its buttons) shows how to do the step.
    r.click = CreateFrame("Button", nil, r)
    r.click:SetAllPoints()
    r.click:SetScript("OnClick", function(self) ns.ShowDetail(self:GetParent().step.ch.id) end)
    r.icon = S.IconBox(r, 34)
    r.icon:SetPoint("LEFT", 4, 0)
    r.helper = S.Button(r, 108, 26)
    r.helper:SetPoint("RIGHT", -6, 0)
    r.helper:SetScript("OnClick", function(self) ns.OpenHelper(self:GetParent().helperKey or nil) end)
    r.game = S.Ghost(S.FitButton(r, L.IN_GAME, 26, 64))
    r.game:SetPoint("RIGHT", r.helper, "LEFT", -4, 0)
    r.game:SetScript("OnClick", function(self) ns.OpenInGame(self:GetParent().step.ch.id) end)
    r.pin = S.FitButton(r, L.PIN, 26, 64)
    r.pin:SetPoint("RIGHT", r.game, "LEFT", -4, 0)
    r.pin:SetScript("OnClick", function(self) ns.Pin(self:GetParent().step.ch.id) end)
    r.eta = S.Text(r, 13)
    r.eta:SetPoint("TOPRIGHT", r.pin, "TOPLEFT", -12, 2)
    r.eta:SetJustifyH("RIGHT")
    r.eta:SetWidth(90)
    r.etaSub = S.Text(r, 10, S.FAINT)
    r.etaSub:SetPoint("TOPRIGHT", r.eta, "BOTTOMRIGHT", 0, -3)
    r.etaSub:SetJustifyH("RIGHT")
    r.etaSub:SetWidth(110)
    r.etaSub:SetWordWrap(false)
    r.name = S.Text(r, 12)
    r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 10, 0)
    r.name:SetWordWrap(false)
    r.tag = S.Badge(r)
    r.tag:SetPoint("LEFT", r.name, "RIGHT", 6, 0)
    r.sub = S.Text(r, 10, S.MUTED)
    r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
    r.sub:SetPoint("RIGHT", r.eta, "LEFT", -12, 0)
    r.sub:SetWordWrap(false)
    r.bar = S.Progress(r, 4)
    r.bar:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 10, 1)
    r.bar:SetPoint("RIGHT", r.eta, "LEFT", -12, 0)
    local lvl = (tonumber((r:GetFrameLevel())) or 0) + 3
    for _, b in ipairs({ r.helper, r.game, r.pin }) do b:SetFrameLevel(lvl) end
end

-- A pin button in its pinned or normal look.
local function paintPin(b, pinned)
    b:SetText(pinned and L.UNPIN or L.PIN)
    if pinned then
        S.Primary(b)
    elseif b.kind ~= "normal" then
        b.kind = "normal"
        b.text:SetTextColor(S.TEXT[1], S.TEXT[2], S.TEXT[3], 1)
        b.text:SetShadowColor(0, 0, 0, 1)
        b:GetScript("OnLeave")(b)
    end
end

-- The helper button of a step: the other module that helps, with its icon.
local function paintHelper(b, s)
    local helper = s and ns.Helper(s)
    b.helperKey = helper or false
    b:SetShown(helper ~= nil)
    if helper then
        local mods = GulliToolkit and GulliToolkit.modules
        local info = mods and mods[helper]
        b:SetText(L["HELP_" .. helper])
        if info and info.icon then S.SetButtonIcon(b, info.icon, 14) end
    end
end

-- How far a step is: the levels or skill of its character, else the open parts.
local function stepFraction(s)
    if s.from and s.to and s.to > 0 then return (s.new and 0 or s.from) / s.to end
    return 1 - s.ch.open / math.max(1, s.ch.total)
end

local function fillStep(r, s)
    r.step = s
    r.icon:SetIcon(stepIcon(s))
    r.name:SetText(s.ch.name)
    r.name:SetWidth(math.min(300, math.max(60, (tonumber(r.name:GetStringWidth()) or 0) + 4)))
    r.tag:Set(ns.Tag(s), tagColor(s))
    r.sub:SetText(ns.Detail(s))
    r.bar:Set(stepFraction(s), S.Accent())
    r.eta:SetText(s.eta and ("~" .. ns.Span(s.eta)) or ns.Span(nil))
    r.etaSub:SetText(s.new and L.ETA_NEW or (not s.me and s.char) and (classColor(s.char.class) .. (s.char.name or "") .. "|r")
        or (s.others and s.others > 0) and L.ETA_OTHERS:format(s.others) or "")
    paintPin(r.pin, ns.db.pins[s.ch.id])
    paintHelper(r.helper, s)
    r.helperKey = r.helper.helperKey
end

-- Characters --------------------------------------------------------------------------------

local function makeChar(r)
    r.name = S.Text(r, 12)
    r.name:SetPoint("TOPLEFT", 10, -7)
    r.name:SetWidth(170)
    r.name:SetWordWrap(false)
    r.points = S.Text(r, 10, S.FAINT)
    r.points:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
    r.points:SetWidth(170)
    r.points:SetWordWrap(false)
    r.profs = S.Text(r, 11, S.MUTED)
    r.profs:SetPoint("LEFT", 190, 0)
    r.profs:SetWidth(200)
    r.profs:SetWordWrap(false)
    r.forget = S.Ghost(S.FitButton(r, L.FORGET, 26, 64))
    r.forget:SetPoint("RIGHT", -6, 0)
    r.forget:SetScript("OnClick", function(self) ns.Forget(self:GetParent().entry.key) end)
    r.best = S.Text(r, 12)
    r.best:SetPoint("TOPLEFT", 400, -7)
    r.best:SetPoint("RIGHT", r.forget, "LEFT", -10, 0)
    r.best:SetWordWrap(false)
    r.bestSub = S.Text(r, 10, S.MUTED)
    r.bestSub:SetPoint("TOPLEFT", r.best, "BOTTOMLEFT", 0, -3)
    r.bestSub:SetPoint("RIGHT", r.forget, "LEFT", -10, 0)
    r.bestSub:SetWordWrap(false)
end

local function fillChar(r, e)
    r.entry = e
    local c = e.char
    r.name:SetText(classColor(c.class) .. (c.name or "?") .. "|r  " .. S.Hex(S.LevelColor(c.level or 1)) .. (c.level or "?") .. "|r"
        .. (e.me and ("  " .. S.Hex(S.FAINT) .. L.YOU .. "|r") or ""))
    r.points:SetText(c.spent and L.SPENT:format(c.spent, ns.MAX_SPEND) or "")
    local profs = {}
    for id, rank in pairs(c.skills or {}) do
        if ns.PRIMARY[id] then profs[#profs + 1] = ns.SkillName(id) .. " " .. rank end
    end
    table.sort(profs)
    r.profs:SetText(#profs > 0 and table.concat(profs, ", ") or S.Hex(S.FAINT) .. L.NO_PROFS .. "|r")
    local best = ns.BestFor(e.key)
    if best then
        r.best:SetText(best.ch.name .. "  " .. S.Hex(S.FAINT) .. "~" .. ns.Span(best.eta) .. "|r")
        r.bestSub:SetText(ns.Detail(best))
    else
        r.best:SetText(S.Hex(S.FAINT) .. L.NOTHING .. "|r")
        r.bestSub:SetText("")
    end
    r.forget:SetShown(not e.me)
end

-- Challenges --------------------------------------------------------------------------------

local function makeChal(r)
    r.icon = S.IconBox(r, 24)
    r.icon:SetPoint("LEFT", 4, 0)
    r.name = S.Text(r, 12)
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 10, 0)
    r.name:SetWidth(330)
    r.name:SetWordWrap(false)
    r.tag = S.Badge(r)
    r.tag:SetPoint("LEFT", 380, 0)
    r.state = S.Text(r, 11)
    r.state:SetPoint("RIGHT", -10, 0)
    r.state:SetJustifyH("RIGHT")
    r.state:SetWidth(120)
    r.bar = S.Progress(r, 4)
    r.bar:SetPoint("LEFT", 480, 0)
    r.bar:SetPoint("RIGHT", r.state, "LEFT", -12, 0)
    r.click = CreateFrame("Button", nil, r)
    r.click:SetAllPoints()
    r.click:SetScript("OnClick", function(self) ns.ShowDetail(self:GetParent().ch.id) end)
end

local KIND_TAG = { level = "TAG_LEVEL", skill = "TAG_SKILL", dungeon = "TAG_GROUP", raid = "TAG_RAID",
                   pvp = "TAG_PVP", solo = "TAG_SOLO" }

local function fillChal(r, ch)
    r.ch = ch
    r.icon:SetIcon(ch.icon or ACTIVITY_ICON[ch.kind] or DEFAULT_ICON)
    r.icon.tex:SetDesaturated(ch.done)
    r.name:SetText(ch.name)
    local c = ch.done and S.MUTED or S.TEXT
    r.name:SetTextColor(c[1], c[2], c[3], 1)
    r.tag:Set(L[KIND_TAG[ch.kind] or "TAG_SOLO"], ch.done and S.FAINT or S.MUTED)
    if ch.done then
        r.state:SetText(S.Hex(S.GOOD) .. L.DONE .. "|r")
        r.bar:Set(1, S.GOOD)
    else
        local off = not ns.Allowed(ch)
        r.state:SetText((off and (S.Hex(S.FAINT) .. L.OFF .. "  |r") or "") .. (ch.total - ch.open) .. "/" .. ch.total)
        r.bar:Set(1 - ch.open / math.max(1, ch.total), S.Accent())
    end
end

local ORDER = { level = 1, skill = 2, dungeon = 3, raid = 4, solo = 5, pvp = 6 }
ns.SORTS = { "progress", "kind", "name" }
local function share(ch) return ch.done and 1 or (ch.total - ch.open) / math.max(1, ch.total) end
local function byKind(a, b)
    local oa, ob = ORDER[a.kind] or 9, ORDER[b.kind] or 9
    if oa ~= ob then return oa < ob end
    return a.id < b.id
end
local SORT = {
    -- Done first, then the most finished: what is closest to a point comes right after.
    progress = function(a, b)
        local sa, sb = share(a), share(b)
        if sa ~= sb then return sa > sb end
        return byKind(a, b)
    end,
    kind = function(a, b)
        if a.done ~= b.done then return not a.done end
        return byKind(a, b)
    end,
    name = function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end,
}
function ns.Challenges()
    local out = {}
    for _, ch in ipairs(ns.list or {}) do out[#out + 1] = ch end
    table.sort(out, SORT[ns.db.sort] or SORT.progress)
    return out
end
local challenges = ns.Challenges

-- The detail page ---------------------------------------------------------------------------

local function makePart(r)
    r.icon = S.IconBox(r, 22)
    r.icon:SetPoint("LEFT", 4, 0)
    r.count = S.Text(r, 11, S.MUTED)
    r.count:SetPoint("TOPRIGHT", -8, -7)
    r.count:SetJustifyH("RIGHT")
    r.count:SetWidth(70)
    r.name = S.Text(r, 12)
    r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 10, 3)
    r.name:SetPoint("RIGHT", r.count, "LEFT", -8, 0)
    r.name:SetWordWrap(false)
    r.sub = S.Text(r, 10, S.MUTED)
    r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
    r.sub:SetPoint("RIGHT", -8, 0)
    r.sub:SetWordWrap(false)
    r:EnableMouse(true)
    r:SetScript("OnEnter", function(self)
        local part = self.part
        if not GameTooltip or not part or #part.left == 0 then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(part.text)
        for _, t in ipairs(part.left) do GameTooltip:AddLine(t, S.MUTED[1], S.MUTED[2], S.MUTED[3]) end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

local function fillPart(r, part)
    r.part = part
    r.icon:SetIcon(part.done and PART_ICON.done or PART_ICON.open)
    r.name:SetText(part.text)
    local c = part.done and S.MUTED or S.TEXT
    r.name:SetTextColor(c[1], c[2], c[3], 1)
    if part.total then
        local col = part.done and S.GOOD or S.MUTED
        r.count:SetText(S.Hex(col) .. L.PARTS_N:format(part.got or 0, part.total) .. "|r")
    else
        r.count:SetText(part.done and (S.Hex(S.GOOD) .. L.DONE .. "|r") or "")
    end
    r.sub:SetText(#part.left > 0 and L.LEFT_N:format(table.concat(part.left, ", ")) or "")
end

local function buildDetail(p)
    local d = {}
    d.head = S.Card(p)
    d.head:SetPoint("TOPLEFT")
    d.head:SetPoint("TOPRIGHT")
    d.head:SetHeight(72)
    local hb = d.head.body
    d.icon = S.IconBox(hb, 40)
    d.icon:SetPoint("LEFT", 0, 0)
    d.back = S.FitButton(hb, L.BACK, 30, 80)
    d.back:SetPoint("RIGHT", 0, 0)
    d.back:SetScript("OnClick", function() ns.ShowTab(d.from or 1) end)
    d.game = S.Ghost(S.FitButton(hb, L.IN_GAME, 30, 80))
    d.game:SetPoint("RIGHT", d.back, "LEFT", -6, 0)
    d.game:SetScript("OnClick", function() if detailID then ns.OpenInGame(detailID) end end)
    d.pin = S.FitButton(hb, L.PIN, 30, 70)
    d.pin:SetPoint("RIGHT", d.game, "LEFT", -6, 0)
    d.pin:SetScript("OnClick", function() if detailID then ns.Pin(detailID) end end)
    d.helper = S.Button(hb, 118, 30)
    d.helper:SetPoint("RIGHT", d.pin, "LEFT", -6, 0)
    d.helper:SetScript("OnClick", function(self) ns.OpenHelper(self.helperKey or nil) end)
    d.name = S.Text(hb, 15)
    d.name:SetPoint("TOPLEFT", d.icon, "TOPRIGHT", 12, -2)
    d.name:SetPoint("RIGHT", d.helper, "LEFT", -12, 0)
    d.name:SetWordWrap(false)
    d.sub = S.Text(hb, 11, S.MUTED)
    d.sub:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -6)
    d.sub:SetPoint("RIGHT", d.helper, "LEFT", -12, 0)
    d.sub:SetWordWrap(false)

    -- Left: how to do it, then the Wowhead link to copy.
    d.how = S.Card(p, L.HOW)
    d.how:SetPoint("TOPLEFT", d.head, "BOTTOMLEFT", 0, -S.GAP)
    d.how:SetPoint("BOTTOMRIGHT", p, "BOTTOM", -S.GAP / 2, 0)
    local body = d.how.body
    d.desc = S.Text(body, 12, S.TEXT)
    d.desc:SetPoint("TOPLEFT", 0, 0)
    d.desc:SetPoint("RIGHT", 0, 0)
    d.desc:SetJustifyH("LEFT")
    d.desc:SetWordWrap(true)
    d.lines = {}
    local prev = d.desc
    for i = 1, GUIDE_LINES do
        local t = S.Text(body, 12, S.MUTED)
        t:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -8)
        t:SetPoint("RIGHT", 0, 0)
        t:SetJustifyH("LEFT")
        t:SetWordWrap(true)
        d.lines[i] = t
        prev = t
    end
    d.url = S.Edit(body, 200, 28)
    d.url:SetPoint("BOTTOMLEFT", 0, 0)
    d.url:SetPoint("BOTTOMRIGHT", 0, 0)
    d.url:SetJustifyH("LEFT")
    S.SetFont(d.url, 11)
    -- The text stays the link: a key press puts it back, a focus selects it for Ctrl+C.
    d.url:SetScript("OnTextChanged", function(self, user)
        if user and self.link and self:GetText() ~= self.link then self:SetText(self.link); self:HighlightText() end
    end)
    d.url:HookScript("OnEditFocusGained", function(self) self:HighlightText() end)
    d.urlHint = S.Text(body, 10, S.FAINT)
    d.urlHint:SetPoint("BOTTOMLEFT", d.url, "TOPLEFT", 0, 6)
    d.urlHint:SetPoint("RIGHT", 0, 0)
    d.urlHint:SetJustifyH("LEFT")
    d.urlHint:SetWordWrap(true)
    d.urlHint:SetText(L.WOWHEAD_D)
    d.urlTitle = S.Text(body, 12, S.TEXT)
    d.urlTitle:SetPoint("BOTTOMLEFT", d.urlHint, "TOPLEFT", 0, 4)
    d.urlTitle:SetText(L.WOWHEAD)

    -- Right: what is left, part by part.
    d.left = S.Card(p, L.WHAT_LEFT, "")
    d.left:SetPoint("TOPLEFT", d.head, "BOTTOM", S.GAP / 2, -S.GAP)
    d.left:SetPoint("BOTTOMRIGHT")
    partList = S.List(d.left.body, 40, makePart, fillPart)
    partList:SetPoint("TOPLEFT")
    partList:SetPoint("BOTTOMRIGHT", -10, 0)
    partEmpty = S.Empty(d.left.body)
    return d
end

local function stepOf(id)
    for _, s in ipairs((ns.Steps())) do if s.ch.id == id then return s end end
end

local function fillDetail()
    local ch = detailID and ns.byID and ns.byID[detailID]
    if not ch then return end
    local d = detail
    local step = stepOf(ch.id)
    d.icon:SetIcon(ch.icon or ACTIVITY_ICON[ch.kind] or DEFAULT_ICON)
    d.name:SetText(ch.name)
    local state = ch.done and (S.Hex(S.GOOD) .. L.DONE .. "|r")
        or L.PARTS_N:format(ch.total - ch.open, ch.total)
    local tag = L[KIND_TAG[ch.kind] or "TAG_SOLO"]
    d.sub:SetText(tag .. "  " .. S.Hex(S.FAINT) .. "·|r  " .. state
        .. (step and step.eta and ("  " .. S.Hex(S.FAINT) .. "·|r  ~" .. ns.Span(step.eta)) or ""))
    paintPin(d.pin, ns.db.pins[ch.id])
    d.pin:SetShown(not ch.done)
    paintHelper(d.helper, step)
    d.desc:SetText(ch.desc or "")
    d.desc:SetShown(ch.desc ~= nil)
    d.lines[1]:ClearAllPoints()
    if ch.desc then d.lines[1]:SetPoint("TOPLEFT", d.desc, "BOTTOMLEFT", 0, -8)
    else d.lines[1]:SetPoint("TOPLEFT", d.how.body, "TOPLEFT", 0, 0) end
    d.lines[1]:SetPoint("RIGHT", d.how.body, "RIGHT", 0, 0)
    local lines, kind = ns.Guide(ch, step)
    for i, t in ipairs(d.lines) do
        local text = lines[i]
        if text and kind == "valthalak" and i <= 4 and not ch.done then
            text = S.Hex(S.Accent()) .. i .. ".|r " .. text
        end
        t:SetText(text or "")
        t:SetShown(text ~= nil)
    end
    d.url.link = ns.WowheadURL(ch)
    d.url:SetText(d.url.link)
    d.url:SetCursorPosition(0)
    local parts = ns.Parts(ch)
    local done = 0
    for _, x in ipairs(parts) do if x.done then done = done + 1 end end
    d.left:SetTitle(L.WHAT_LEFT, #parts > 0 and L.PARTS_N:format(done, #parts) or "")
    partList:SetData(parts)
    partEmpty:SetShown(#parts == 0)
    partEmpty:Set(L.ALL_DONE_PARTS, "")
end

-- Shows how to do one challenge (from a step or the Challenges list); Back returns to the tab.
function ns.ShowDetail(id)
    ns.Window()
    if not (ns.byID and ns.byID[id]) then return end
    detail.from = detailID and detail.from or tabs.selected
    detailID = id
    for j, p in ipairs(pages) do p:SetShown(j == #pages) end
    fillDetail()
end
function ns.DetailID() return detailID end

-- The tracker -------------------------------------------------------------------------------

local function placeTracker()
    tracker:ClearAllPoints()
    local p = ns.db.point
    if p then tracker:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
    else tracker:SetPoint("RIGHT", -60, 120) end
end

local function buildTracker()
    tracker = S.HudList("GulliLegacyTracker", 380, 4)
    tracker:SetFrameStrata("MEDIUM")
    tracker:SetScript("OnClick", function() ns.Toggle() end)
    S.Mover(tracker, { label = L.TITLE, save = function(point, rel, x, y) ns.db.point = { point, rel, x, y } end,
        reset = function() ns.db.point = nil; placeTracker() end,
        lock = function() ns.SetPref("locked", true) end, lockTip = L.OPT_LOCK })
end

function ns.TrackerFrame() return tracker end

function ns.Tracker(steps, p)
    local d = ns.db
    if not d then return end
    -- Unlocked (its switch or /gulli move), the tracker shows even when it is off, to be placed.
    local moving = ns.moving or d.locked == false
    if (not d.tracker or ns.paused or not ns.list or #ns.list == 0) and not moving then
        if tracker then tracker:SetMoving(false); tracker:Hide() end
        return
    end
    if not tracker then buildTracker() end
    placeTracker()
    tracker:SetAlpha(moving and 1 or (d.alpha or 80) / 100)
    tracker:SetMoving(moving and not (InCombatLockdown and InCombatLockdown()))
    local list, pinned = ns.Tracked(steps or {})
    local rows = {}
    for i, s in ipairs(list) do
        if i > 4 then break end
        rows[i] = { tag = ns.Tag(s), tagColor = tagColor(s), text = s.ch.name .. "  " .. S.Hex(S.MUTED) .. ns.Detail(s) .. "|r",
                    right = s.eta and ("~" .. ns.Span(s.eta)) or "" }
    end
    tracker:SetRows(rows, L.TRACKER_EMPTY)
    local r = p and ns.NextReward(p.earned)
    tracker.title:SetText(L.TITLE .. "  " .. S.Hex(S.MUTED) .. (p and p.earned or 0) .. "/" .. ns.TOTAL .. "|r")
    tracker.right:SetText(r and L.TO_REWARD_SHORT:format(r.level - p.earned) or (pinned and L.PINNED or ""))
    tracker:Show()
end

-- A new point.
function ns.Announce(title, name, text, icon)
    return S.Toast({ key = "earned", icon = icon or "Interface\\AddOns\\Gulli-Legacy\\icon", kind = "good",
        title = title .. ": " .. name, text = text, seconds = 12 })
end

-- The window --------------------------------------------------------------------------------

function ns.Refresh()
    if ns.paused then ns.Tracker(); return end
    local steps, hidden = ns.Steps()
    local p = ns.Points()
    ns.Tracker(steps, p)
    if not frame or not frame:IsShown() then return end
    local ready = ns.list and #ns.list > 0
    local page = tabs.selected
    if detailID then
        fillDetail()
    elseif page == 1 then
        fillTrack(p)
        local plan, need, total = ns.GoalPlan(steps, p.earned)
        local goal = tonumber(ns.db.goal) or 0
        if goal > 0 then
            local r
            for _, x in ipairs(ns.Rewards(p.earned)) do if x.level == goal then r = x end end
            goalText:SetText(L.GOAL:format(goal, r and r.name or ""))
            if need == 0 then goalSub:SetText(S.Hex(S.GOOD) .. L.GOAL_DONE .. "|r")
            else goalSub:SetText(L.GOAL_LEFT:format(need, #plan, ns.Span(total))) end
            stepsCard:SetTitle(L.GOAL_STEPS, L.BY_TIME)
            stepList:SetData(need > 0 and plan or {})
        else
            goalText:SetText(L.NO_GOAL)
            goalSub:SetText(L.NO_GOAL_D)
            stepsCard:SetTitle(L.NEXT_STEPS, L.BY_TIME)
            stepList:SetData(steps)
        end
        emptySteps:SetShown(#steps == 0)
        if not ready then emptySteps:Set(L.LOADING, L.LOADING_D)
        else emptySteps:Set(L.NO_STEPS, hidden > 0 and L.NO_STEPS_HIDDEN or L.NO_STEPS_D) end
    elseif page == 2 then
        charList:SetData(ns.Chars())
    elseif page == 3 then
        for i, k in ipairs(ns.SORTS) do if k == (ns.db.sort or "progress") then sortTabs:Select(i, true) end end
        chalList:SetData(challenges())
    else
        for _, x in ipairs(switchRows) do x.row:SetChecked(x.get()) end
    end
    footer:SetStatus(not ready and L.LOADING or hidden > 0 and L.HIDDEN:format(hidden) or "")
end

local function page(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetPoint("TOPLEFT", 0, -30 - S.GAP)
    p:SetPoint("BOTTOMRIGHT")
    p:Hide()
    pages[#pages + 1] = p
    return p
end

local function showTab(i)
    detailID = nil
    for j, p in ipairs(pages) do p:SetShown(j == i) end
    ns.Refresh()
end

-- Opens a tab: 1 plan, 2 characters, 3 challenges, 4 settings.
function ns.ShowTab(i)
    ns.Window()
    tabs:Select(i)
end

local function build()
    frame = S.Window("GulliLegacyFrame", L.TITLE, S.WIDE_W, S.DOCK_H)
    footer = S.Footer(frame)
    gameBtn = footer:Add(S.FitButton(frame, L.OPEN_GAME, 30, 120))
    gameBtn:SetScript("OnClick", function() ns.OpenInGame() end)
    local body = frame.body
    tabs = S.Tabs(body, { L.TAB_PLAN, L.TAB_CHARS, L.TAB_ALL, L.TAB_SETTINGS }, nil, showTab, nil,
        { S.TAB.overview, S.TAB.char, S.TAB.list, S.TAB.settings })

    -- Plan
    local p1 = page(body)
    local st = S.Stack(p1)
    track = buildTrack(p1)
    st:Add(track, 104)
    local goal = S.Card(p1)
    st:Add(goal, 56)
    goalBtn = S.FitButton(goal.body, L.CHANGE_GOAL, 30, 110)
    goalBtn:SetPoint("RIGHT", 0, 0)
    goalBtn:SetScript("OnClick", function() ns.SetGoal(ns.NextGoal()) end)
    goalText = S.Text(goal.body, 12)
    goalText:SetPoint("TOPLEFT", 0, 0)
    goalText:SetPoint("RIGHT", goalBtn, "LEFT", -12, 0)
    goalText:SetWordWrap(false)
    goalSub = S.Text(goal.body, 11, S.MUTED)
    goalSub:SetPoint("TOPLEFT", goalText, "BOTTOMLEFT", 0, -4)
    goalSub:SetPoint("RIGHT", goalBtn, "LEFT", -12, 0)
    goalSub:SetWordWrap(false)
    stepsCard = S.Card(p1, L.NEXT_STEPS, L.BY_TIME)
    stepsCard:SetPoint("TOPLEFT", 0, -st.y)
    stepsCard:SetPoint("BOTTOMRIGHT")
    stepList = S.List(stepsCard.body, 48, makeStep, fillStep)
    stepList:SetPoint("TOPLEFT")
    stepList:SetPoint("BOTTOMRIGHT", -10, 0)
    emptySteps = S.Empty(stepsCard.body)

    -- Characters
    local p2 = page(body)
    local cc = S.Card(p2, L.CHARS, L.CHARS_HINT)
    cc:SetPoint("TOPLEFT")
    cc:SetPoint("BOTTOMRIGHT")
    charList = S.List(cc.body, 44, makeChar, fillChar)
    charList:SetPoint("TOPLEFT")
    charList:SetPoint("BOTTOMRIGHT", -10, 0)

    -- Challenges
    local p3 = page(body)
    local ac = S.Card(p3, L.ALL)
    ac:SetPoint("TOPLEFT")
    ac:SetPoint("BOTTOMRIGHT")
    local sortLabels = {}
    for i, k in ipairs(ns.SORTS) do sortLabels[i] = L["SORT_" .. k:upper()] end
    sortTabs = S.Tabs(ac, sortLabels, 92, function(i) ns.SetPref("sort", ns.SORTS[i]) end, 26)
    sortTabs.frame:ClearAllPoints()
    sortTabs.frame:SetPoint("TOPRIGHT", -S.INSET, -6)
    local hint = S.Text(ac, 11, S.MUTED)
    hint:SetPoint("RIGHT", sortTabs.frame, "LEFT", -10, 0)
    hint:SetText(L.ALL_HINT)
    chalList = S.List(ac.body, 34, makeChal, fillChal)
    chalList:SetPoint("TOPLEFT")
    chalList:SetPoint("BOTTOMRIGHT", -10, 0)

    -- Settings
    local p4 = page(body)
    local function rows(list)
        local out = {}
        for _, o in ipairs(list) do
            local key = o[1]
            out[#out + 1] = { o[2], o[3], function() return ns.db[key] == true end, function(v) ns.SetPref(key, v) end,
                              icon = ns.OPT_ICON[key] }
        end
        return out
    end
    local suggest = rows({ { "dungeon", L.OPT_DUNGEON, L.OPT_DUNGEON_D }, { "raid", L.OPT_RAID, L.OPT_RAID_D },
                           { "pvp", L.OPT_PVP, L.OPT_PVP_D }, { "alts", L.OPT_ALTS, L.OPT_ALTS_D },
                           { "newClass", L.OPT_NEW, L.OPT_NEW_D } })
    local screen = rows({ { "tracker", L.OPT_TRACKER, L.OPT_TRACKER_D }, { "locked", L.OPT_LOCK, L.OPT_LOCK_D }, { "announce", L.OPT_ANNOUNCE, L.OPT_ANNOUNCE_D } })
    local alpha = S.Stepper(p4, function() return ns.db.alpha end, function(v) ns.SetPref("alpha", v) end,
        10, 20, 100, function(v) return v .. "%" end)
    screen[#screen + 1] = { L.OPT_ALPHA, L.OPT_ALPHA_D, control = alpha, icon = ns.OPT_ICON.alpha }
    -- Two columns: what the plan suggests on the left, the screen on the right.
    local c1, h1 = S.SettingsCard(p4, L.SUGGEST, suggest)
    c1:SetPoint("TOPLEFT")
    c1:SetPoint("TOPRIGHT", p4, "TOP", -S.GAP / 2, 0)
    c1:SetHeight(h1)
    local c2, h2 = S.SettingsCard(p4, L.ON_SCREEN, screen)
    c2:SetPoint("TOPLEFT", p4, "TOP", S.GAP / 2, 0)
    c2:SetPoint("TOPRIGHT")
    c2:SetHeight(h2)
    for i, row in ipairs(c1.rows) do switchRows[#switchRows + 1] = { row = row, get = suggest[i][3] } end
    for i, row in ipairs(c2.rows) do
        if screen[i][3] then switchRows[#switchRows + 1] = { row = row, get = screen[i][3] } end
    end

    -- The detail page: not a tab, the last page; a step or a challenge opens it.
    detail = buildDetail(page(body))

    tabs.frame:SetPoint("TOPLEFT")
    pages[1]:Show()
    -- The hub shows the window itself, so the scan runs on show, not only from Toggle.
    frame:SetScript("OnShow", function()
        if not ns.paused then ns.Scan(); ns.Snapshot() end
        alpha:Refresh()
        ns.Refresh()
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
