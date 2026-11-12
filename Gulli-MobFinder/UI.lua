local _, ns = ...
local L = ns.L
local S = ns.Skin

-- One small window: the switch, the list of mobs, how often to look and which sound to
-- play. Every change is saved at once; the search itself lives in Core.lua.
local W = S.NARROW_W

local frame, enable, memo, interval, soundName, again, banner, status

local function soundIndex()
    for i, s in ipairs(ns.SOUNDS) do
        if s.key == ns.db.sound then return i end
    end
    return 1
end

local function stepSound(delta)
    local n = #ns.SOUNDS
    local i = (soundIndex() - 1 + delta) % n + 1
    ns.db.sound = ns.SOUNDS[i].key
    ns.Refresh()
    ns.PlayAlert()
end

local function intervalText(v)
    return (v == math.floor(v)) and tostring(math.floor(v)) or tostring(v)
end

-- Shows the saved settings and the search state.
function ns.Refresh()
    if not frame then return end
    local d = ns.db
    enable:SetChecked(d.enabled)
    again:SetChecked(d.again)
    banner:SetChecked(d.banner)
    if not memo.edit:HasFocus() then memo.edit:SetText(table.concat(d.names, "\n")) end
    if not interval:HasFocus() then interval:SetText(intervalText(d.interval)) end
    soundName:SetText(L["SND_" .. ns.SOUNDS[soundIndex()].key])
    local text = d.enabled and L.STATUS_ON:format(#d.names, intervalText(d.interval)) or L.STATUS_OFF
    if ns.lastFound then
        text = text .. "\n" .. L.STATUS_LAST:format(table.concat(ns.lastFound.names, ", "))
    end
    status:SetText(text)
    local c = d.enabled and S.GOOD or S.MUTED
    status:SetTextColor(c[1], c[2], c[3], 1)
end

ns.OnState = ns.Refresh
ns.OnFound = ns.Refresh

local function saveInterval(self)
    if ns.SetInterval(self:GetText()) then
        ns.Refresh()
    else
        status:SetText(L.BAD_INTERVAL)
        status:SetTextColor(S.BAD[1], S.BAD[2], S.BAD[3], 1)
        self:SetText(intervalText(ns.db.interval))
    end
end

local function build()
    frame = S.Window("GulliMobFinderFrame", L.TITLE, W, S.DOCK_H, { sub = "/gmf" })
    local ft = S.Footer(frame)
    local play = ft:Add(S.FitButton(ft, L.PLAY, 30, 80))
    play:SetScript("OnClick", function() ns.PlayAlert() end)
    status = ft.status
    local body, width = frame.body, frame.inner[1]
    local st = S.Stack(body)

    local main, mh = S.SettingsCard(body, nil, {
        { L.ENABLE, nil, function() return ns.db.enabled end, function(on) ns.SetEnabled(on) end,
          icon = "Interface\\Icons\\Ability_Hunter_SniperShot" } })
    enable = main.rows[1]
    enable.label:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 14, "")
    st:Add(main, mh)

    local mobs = S.Card(body, L.MOBS)
    memo = S.Memo(mobs.body, width - 2 * S.INSET, 90)
    memo:SetPoint("TOPLEFT")
    memo:SetPoint("TOPRIGHT")
    memo.edit:SetScript("OnTextChanged", function(self, user)
        if user then
            ns.SetNames(ns.ParseNames(self:GetText()))
            ns.Refresh()
        end
    end)
    local add = S.FitButton(mobs.body, L.ADD_TARGET, 30, 120)
    add:SetPoint("TOPLEFT", memo, "BOTTOMLEFT", 0, -10)
    add:SetScript("OnClick", function()
        local name = ns.AddTarget()
        memo.edit:ClearFocus()
        ns.Refresh()
        if not name then status:SetText(L.NO_TARGET) end
    end)
    st:Add(mobs, mobs:Fit(90 + 10 + 30))

    -- How often to look: [n] sec.
    local every = CreateFrame("Frame", nil, body)
    every:SetSize(96, 28)
    interval = S.Edit(every, 52, 28)
    interval:SetPoint("LEFT")
    interval:SetMaxLetters(4)
    interval:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    interval:SetScript("OnEditFocusLost", function(self)
        S.SetBorder(self, S.EDGE)
        saveInterval(self)
    end)
    local sec = S.Text(every, 12, S.MUTED)
    sec:SetPoint("LEFT", interval, "RIGHT", 8, 0)
    sec:SetText(L.SECONDS)

    -- Which sound: arrows step through the list and play the new sound.
    local sound = CreateFrame("Frame", nil, body)
    sound:SetSize(30 + 140 + 30, 28)
    local prev = S.Button(sound, 28, 28)
    prev:SetPoint("LEFT")
    prev:SetText("<")
    prev:SetScript("OnClick", function() stepSound(-1) end)
    local nextB = S.Button(sound, 28, 28)
    nextB:SetPoint("RIGHT")
    nextB:SetText(">")
    nextB:SetScript("OnClick", function() stepSound(1) end)
    soundName = S.Text(sound, 12)
    soundName:SetPoint("LEFT", prev, "RIGHT", 4, 0)
    soundName:SetPoint("RIGHT", nextB, "LEFT", -4, 0)
    soundName:SetJustifyH("CENTER")
    soundName:SetWordWrap(false)

    local opts, oh = S.SettingsCard(body, nil, {
        { L.EVERY, nil, control = every, icon = "Interface\\Icons\\INV_Misc_PocketWatch_01" },
        { L.SOUND, nil, control = sound, icon = "Interface\\Icons\\INV_Misc_Horn_01" },
        { L.AGAIN, nil, function() return ns.db.again end, function(on) ns.db.again = on end,
          icon = "Interface\\Icons\\Spell_Nature_TimeStop" },
        { L.BANNER, nil, function() return ns.db.banner end, function(on) ns.db.banner = on end,
          icon = "Interface\\Icons\\Ability_Warrior_BattleShout" },
    })
    again, banner = opts.rows[3], opts.rows[4]
    st:Add(opts, oh)
    local note, nh = S.Paragraph(body, L.NOTE, width)
    st:Add(note, nh)
    S.FitWindow(frame, st:Height())
    frame:SetScript("OnShow", ns.Refresh)
end

function ns.Toggle()
    S.ToggleWindow(ns.Window())
end

-- The window, for the hub (/gulli) to show inside it.
function ns.Window()
    if not frame then build() end
    return frame
end

-- The addon compartment (the minimap addon menu) opens the window too.
function GulliMobFinder_Toggle() ns.Toggle() end

-- A module of Gulli Toolkit: the hub lists it when the core is loaded.
if GulliToolkit and GulliToolkit.Register then
    GulliToolkit.Register({
        key = "MobFinder",
        title = L.TITLE,
        desc = L.DESC,
        icon = "Interface\\AddOns\\Gulli-MobFinder\\icon",
        open = ns.Toggle,
        window = function() return ns.Window and ns.Window() end,
        slash = "/gmf",
    })
end
