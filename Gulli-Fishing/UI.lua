-- The secure cast button the double-click binds to, the lure notice and the window: three tiles
-- (catches, the lure on the pole, whether the double-click casts now), what was caught this
-- session, and the settings.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, tiles, tabs, caughtList, caughtEmpty, castBtn
local pages = {}

-- The button a double right-click clicks: Fishing, or the lure onto the pole (attributes set by
-- ns.Arm, out of combat only).
function ns.CastButton()
    if castBtn then return castBtn end
    castBtn = CreateFrame("Button", "GulliFishingCast", UIParent, "SecureActionButtonTemplate")
    castBtn:SetSize(1, 1)
    castBtn:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 10, -10)
    castBtn:RegisterForClicks("AnyUp", "AnyDown")
    castBtn:SetScript("PostClick", function() ns.Disarm() end)
    castBtn:Show()
    return castBtn
end

-- A lure is missing: a Gulli HUD notice with the lure's own icon.
function ns.OnLureMissing(id, text)
    if S.Toast then
        S.Toast({ key = "Fishing:lure", icon = ns.ItemIcon(id), title = L.LURE_TITLE, text = text, kind = "warn", seconds = 8 })
    else
        print(L.TITLE .. ": " .. text)
    end
end

-- "12 min" left on the pole, or a dash.
function ns.LureText()
    local left = ns.LureLeft()
    if left > 0 then return ns.Span(left), S.GOOD end
    if ns.HasPole() then return L.NO_LURE, S.WARN end
    return "-", S.MUTED
end

-- Whether a double-click casts now, and why not.
function ns.StateText()
    if ns.paused then return L.STATE_PAUSED, S.MUTED end
    if not ns.db.cast then return L.STATE_OFF, S.MUTED end
    if not ns.FishingSpell() then return L.STATE_NO_SKILL, S.MUTED end
    if not ns.Active() then return L.STATE_NO_POLE, S.MUTED end
    return L.STATE_READY, S.GOOD
end

local function catchPage(body)
    local p = CreateFrame("Frame", nil, body)
    local card = S.Card(p, L.SEC_CAUGHT)
    card:SetPoint("TOPLEFT")
    card:SetPoint("BOTTOMRIGHT")
    caughtList = S.List(card.body, 34, function(r)
        r.icon = S.IconBox(r, 24)
        r.icon:SetPoint("LEFT", 2, 0)
        r.count = S.Text(r, 13)
        r.count:SetPoint("RIGHT", -4, 0)
        r.count:SetJustifyH("RIGHT")
        r.name = S.Text(r, 12)
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 10, 0)
        r.name:SetPoint("RIGHT", r.count, "LEFT", -8, 0)
        r.name:SetWordWrap(false)
    end, function(r, it)
        r.icon:SetIcon(ns.ItemIcon(it.id))
        r.name:SetText(ns.ItemName(it.id))
        r.count:SetText("+" .. it.n)
    end)
    caughtList:SetAllPoints()
    caughtEmpty = S.Empty(card.body)
    caughtEmpty:Set(L.NO_CATCH, L.NO_CATCH_SUB)
    return p
end

local function settingsPage(body, width)
    local page = S.ScrollPage(body, width)
    local p = page.inner
    local st = S.Stack(p)
    local function row(key)
        local up = key:upper()
        return { L["OPT_" .. up], L["OPT_" .. up .. "_TIP"], function() return ns.db[key] end,
                 function(v) ns.SetPref(key, v) end, icon = ns.OPT_ICON[key] }
    end
    for _, sec in ipairs({ { L.SEC_CAST, { "cast", "lure" } }, { L.SEC_SOUND, { "loud", "mute", "interact" } },
                           { L.SEC_MORE, { "loot", "remind" } } }) do
        local rows = {}
        for _, k in ipairs(sec[2]) do rows[#rows + 1] = row(k) end
        local card, h = S.SettingsCard(p, sec[1], rows)
        st:Add(card, h)
    end
    page:SetContent(st:Height())
    return page
end

local function paintWindow()
    local t = tiles.tiles
    t[1]:Set(tostring(ns.s.catches), ns.s.catches > 0 and S.TEXT or S.MUTED)
    t[2]:Set(ns.LureText())
    t[3]:Set(ns.StateText())
    local rows = ns.Caught()
    caughtList:SetData(rows)
    caughtEmpty:SetShown(#rows == 0)
end

function ns.Refresh()
    if not ns.s or not ns.db then return end
    if frame and frame:IsShown() then paintWindow() end
end

local function build()
    frame = S.Window("GulliFishingFrame", L.TITLE, S.NARROW_W, S.DOCK_H)
    local body, width = frame.body, frame.inner[1]
    local ft = S.Footer(frame)
    local new = S.Primary(S.FitButton(frame, L.NEW_SESSION, 30, 120))
    new:SetScript("OnClick", function() ns.Start(); ns.Refresh(); ft:SetStatus(L.NEW_SESSION_DONE) end)
    ft:Add(new)
    ft:SetStatus(L.STATUS)
    local st = S.Stack(body)
    tiles = S.StatRow(body, { L.ST_CATCHES, L.ST_LURE, L.ST_STATE }, 62,
        { "Interface\\Icons\\INV_Misc_Fish_02", ns.OPT_ICON.lure, ns.OPT_ICON.cast })
    st:Add(tiles, 62)
    tiles:Layout(width)
    tabs = S.PageTabs(body, { L.TAB_CATCH, L.TAB_SETTINGS }, nil, function(i)
        for j, p in ipairs(pages) do p:SetShown(j == i) end
        ns.Refresh()
    end, nil, { S.TAB.list, S.TAB.settings })
    tabs.frame:ClearAllPoints()
    tabs.frame:SetPoint("TOPLEFT", 0, -st.y)
    st:Space(30 + S.GAP)
    pages[1] = catchPage(body)
    pages[2] = settingsPage(body, width)
    for i, p in ipairs(pages) do
        p:SetPoint("TOPLEFT", 0, -st.y)
        p:SetPoint("BOTTOMRIGHT")
        p:SetShown(i == 1)
    end
    frame:HookScript("OnShow", function() ns.Refresh() end)
end

function ns.Toggle()
    if S.ToggleWindow(ns.Window()) then ns.Refresh() end
end

-- The window, for the hub (/gulli) to show inside it.
function ns.Window()
    if not frame then build() end
    return frame
end

-- For the tests and the previews.
function ns.Parts() return frame, tiles, pages, tabs end
