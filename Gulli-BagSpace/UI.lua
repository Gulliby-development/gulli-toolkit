-- The window: how many slots to free, the plan with a tick per item, and OK.

local _, ns = ...
local L = ns.L
local S = ns.Skin

local frame, space, want, list, empty, card, ok
local plan

local function makeRow(r)
    r.check = S.Check(r, 26)
    r.check:SetPoint("LEFT", -4, 0)
    r.check:SetScript("OnClick", function(self)
        local it = self:GetParent().item
        it.checked = not it.checked
        self:SetChecked(it.checked)
        -- An item unticked by the player stays out of later plans (until /gbs reset).
        if it.tier < 3 then ns.SetKept(it, not it.checked) end
        ns.Refresh(false)
    end)
    r.iconBox = S.IconBox(r, 22)
    r.iconBox:SetPoint("LEFT", r.check, "RIGHT", 4, 0)
    r.icon = r.iconBox.tex
    r.value = S.Text(r, 11, S.MUTED)
    r.value:SetPoint("RIGHT", -4, 0)
    r.value:SetJustifyH("RIGHT")
    r.name = S.Text(r, 12)
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
    r.name:SetPoint("RIGHT", r.value, "LEFT", -6, 0)
    r.name:SetWordWrap(false)
end

local function fillRow(r, it)
    r.item = it
    r.check:SetChecked(it.checked)
    r.icon:SetTexture(it.icon)
    local tags = {}
    if it.why == "always" then tags[#tags + 1] = L.TAG_ALWAYS end
    if it.why == "unusable" then tags[#tags + 1] = L.TAG_UNUSABLE end
    if it.ah then tags[#tags + 1] = L.TAG_AH:format(S.MoneyText(it.ah)) end
    if it.boe then tags[#tags + 1] = L.TAG_BOE end
    if it.tier == 3 and #tags == 0 then tags[#tags + 1] = L.MAYBE end
    r.name:SetText(S.QualityHex(it.quality) .. it.name .. "|r" .. (it.count > 1 and (" x" .. it.count) or "") ..
        (#tags > 0 and ("  " .. S.Hex(S.FAINT) .. table.concat(tags, ", ") .. "|r") or ""))
    r.value:SetText(it.value > 0 and S.MoneyText(it.value) or "")
end

-- rebuild: true makes a new plan from the bags, false keeps the ticks.
function ns.Refresh(rebuild)
    if not frame or not frame:IsShown() then return end
    if rebuild ~= false or not plan then plan = ns.Plan(ns.db.want) end
    space:SetText(L.SPACE:format(plan.free, plan.total))
    list:SetData(plan.items)
    local slots, value = ns.Summary(plan)
    empty:SetShown(#plan.items == 0)
    empty:Set(plan.merged > 0 and L.ONLY_MERGE:format(plan.merged) or L.NOTHING)
    card:SetTitle(L.SUMMARY:format(slots, plan.merged), value > 0 and S.MoneyText(value) or "")
    ok:SetText(ns.atMerchant and L.SELL or L.DELETE)
    if ns.atMerchant then S.Primary(ok) else S.Danger(ok) end
    ok:SetEnabled(slots > 0)
    local selling = ns.ToSell(plan)
    if plan.leftover then
        frame.footer:SetStatus(L.LEFTOVER:format(#plan.items), S.WARN)
    elseif selling > 12 then
        frame.footer:SetStatus(L.NOTE_SELL_MANY:format(selling), S.WARN)
    else
        local kept = ns.KeptCount()
        frame.footer:SetStatus((ns.atMerchant and L.NOTE_SELL or L.NOTE_DELETE) ..
            (kept > 0 and ("\n" .. L.KEPT:format(kept)) or ""))
    end
end

local function build()
    frame = S.Window("GulliBagSpaceFrame", L.TITLE, S.NARROW_W, S.DOCK_H)
    local ft = S.Footer(frame)
    ok = ft:Add(S.Button(ft, 120, 32))
    ok:SetScript("OnClick", function()
        local done = plan
        local sold = ns.Run(done)
        -- A moment later: what the game kept is offered again; else a fresh plan.
        C_Timer.After(sold > 0 and (1 + sold / 12 * 0.25) or 1, function()
            local left = ns.Leftover(done)
            if #left > 0 and frame:IsShown() then
                plan = { merges = {}, merged = 0, items = left, free = done.free, total = done.total,
                         want = done.want, leftover = true }
                local free, total = ns.Space()
                plan.free, plan.total = free, total
                ns.Refresh(false)
            else
                ns.Refresh(true)
            end
        end)
    end)

    local body = frame.body
    -- The toolbar: free slots on the left, "Free up [n] Plan" on the right.
    space = S.Text(body, 15)
    space:SetPoint("TOPLEFT", 0, -6)
    local planBtn = S.FitButton(body, L.PLAN, 30, 80)
    planBtn:SetPoint("TOPRIGHT", 0, 0)
    want = S.Edit(body, 48, 30)
    want:SetPoint("RIGHT", planBtn, "LEFT", -8, 0)
    want:SetNumeric(true)
    want:SetMaxLetters(3)
    local label = S.Text(body, 12, S.MUTED)
    label:SetPoint("RIGHT", want, "LEFT", -8, 0)
    label:SetText(L.WANT)
    local function apply()
        local n = tonumber(want:GetText())
        if n and n > 0 then ns.db.want = n end
        want:SetText(tostring(ns.db.want))
        want:ClearFocus()
        ns.Refresh(true)
    end
    want:SetScript("OnEnterPressed", apply)
    planBtn:SetScript("OnClick", apply)

    if ns.CanSort() then
        local sortBtn = S.FitButton(body, L.SORT, 30, 70)
        sortBtn:SetPoint("RIGHT", label, "LEFT", -12, 0)
        sortBtn:SetScript("OnClick", function() ns.SortBags() end)
    end

    local rows = {}
    for _, o in ipairs({ { "unusable", L.OPT_UNUSABLE }, { "counter", L.OPT_COUNTER }, { "popup", L.OPT_POPUP } }) do
        local key = o[1]
        rows[#rows + 1] = { o[2], nil, function() return ns.db[key] end, function(v)
            ns.db[key] = v
            if key == "counter" then ns.UpdateCounter() end
            ns.Refresh(true)
        end, icon = ns.OPT_ICON[key] }
    end
    local settingsCard, sh = S.SettingsCard(body, nil, rows)
    settingsCard:SetPoint("BOTTOMLEFT")
    settingsCard:SetPoint("BOTTOMRIGHT")
    settingsCard:SetHeight(sh)

    card = S.Card(body, " ")
    card:SetPoint("TOPLEFT", 0, -30 - S.GAP)
    card:SetPoint("BOTTOMRIGHT", settingsCard, "TOPRIGHT", 0, S.GAP)
    list = S.List(card.body, 34, makeRow, fillRow)
    list:SetPoint("TOPLEFT")
    list:SetPoint("BOTTOMRIGHT", -10, 0)
    empty = S.Empty(card.body)

    frame:SetScript("OnShow", function()
        want:SetText(tostring(ns.db.want))
        ns.Refresh(true)
    end)
end

function ns.Toggle()
    if S.ToggleWindow(ns.Window()) then
        ns.Refresh(true)
    end
end

-- The window, for the hub (/gulli) to show inside it.
function ns.Window()
    if not frame then
        build()
        -- In the hub the window is shown by the hub, not by ns.Toggle.
        frame:HookScript("OnShow", function(self)
            if not self.docked then return end
            ns.Refresh(true)
        end)
    end
    return frame
end

-- The free slots on the backpack button.
function ns.UpdateCounter()
    local b = MainMenuBarBackpackButton
    if not b or not b.CreateFontString then return end
    if not b.gulliFree then
        b.gulliFree = S.Text(b, 11, S.TEXT, "OUTLINE")
        b.gulliFree:SetPoint("TOP", 0, -2)
    end
    local free = ns.Space()
    b.gulliFree:SetText(ns.db.counter and tostring(free) or "")
    local c = free <= ns.db.warnAt and S.BAD or S.TEXT
    b.gulliFree:SetTextColor(c[1], c[2], c[3], 1)
end

-- "Inventory is full": a Gulli HUD notice whose button sells or deletes the cheapest junk item
-- in one click (the game lets an addon delete only inside a click).
local popup
function ns.ShowPopup()
    local it = ns.OneItem()
    if not it then return end
    popup = S.Toast({ key = "full", icon = it.icon, kind = "warn", title = L.POPUP_TITLE,
        text = L.POPUP_TEXT:format(it.name or "?"), seconds = 10,
        buttons = { { text = ns.atMerchant and L.SELL or L.DELETE, primary = true, onClick = function() ns.FreeOne() end } } })
    return popup
end

function ns.HidePopup() if popup then popup:Hide() end end
