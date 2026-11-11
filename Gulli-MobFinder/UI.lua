local _, ns = ...
local L = ns.L
local S = ns.Skin

-- One small window: the switch, the list of mobs, how often to look and which sound to
-- play. Every change is saved at once; the search itself lives in Core.lua.
local W, H = 400, 540
local TITLE_H = 28
local PAD = 16

local frame, enable, memo, interval, soundName, again, banner, status

local labels = {}
local function say(obj, key)
    labels[#labels + 1] = { obj, key }
    obj:SetText(L[key])
end

local function button(parent, key, width)
    local b = S.Button(parent, width, 30)
    if key then say(b, key) end
    return b
end

local function checkbox(parent, key, onClick)
    local c = S.Check(parent, 26)
    local label = S.Text(c, 13)
    label:SetPoint("LEFT", c, "RIGHT", 2, 0)
    say(label, key)
    c.label = label
    c:SetHitRectInsets(0, -(label:GetStringWidth() + 8), 0, 0)
    c:SetScript("OnClick", function(self)
        self:SetChecked(not self:GetChecked())
        onClick(self:GetChecked())
    end)
    return c
end

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
end

ns.OnState = ns.Refresh
ns.OnFound = ns.Refresh

local function saveInterval(self)
    if ns.SetInterval(self:GetText()) then
        ns.Refresh()
    else
        status:SetText(L.BAD_INTERVAL)
        self:SetText(intervalText(ns.db.interval))
    end
end

local function build()
    local accent = S.Accent()
    frame = CreateFrame("Frame", "GulliMobFinderFrame", UIParent)
    S.Box(frame, S.BG)
    frame:SetSize(W, H)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:Hide()
    tinsert(UISpecialFrames, "GulliMobFinderFrame")

    -- Title bar: drag to move, a flat close button.
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    bar:SetHeight(TITLE_H)
    S.Box(bar, S.PANEL, { 0, 0, 0, 0 })
    local line = bar:CreateTexture(nil, "ARTWORK")
    line:SetTexture("Interface\\Buttons\\WHITE8X8")
    line:SetVertexColor(accent[1], accent[2], accent[3], 0.8)
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(1)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() frame:StartMoving() end)
    bar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    local title = S.Text(bar, 14)
    title:SetPoint("LEFT", 10, 0)
    title:SetText(S.Hex(accent) .. "Gulli|r-MobFinder")
    local close = S.Button(bar, 24, 22)
    close:SetPoint("RIGHT", -3, 0)
    close:SetText("×")
    close:SetScript("OnEnter", function(self) S.Fill(self, { 0.6, 0.1, 0.1, 1 }) end)
    close:SetScript("OnLeave", function(self) S.Fill(self, S.PANEL) end)
    close:SetScript("OnClick", function() frame:Hide() end)

    enable = checkbox(frame, "ENABLE", function(on) ns.SetEnabled(on) end)
    enable:SetPoint("TOPLEFT", PAD - 6, -(TITLE_H + 12))
    enable.label:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 15, "")

    local mobs = S.Text(frame, 12, S.MUTED)
    mobs:SetPoint("TOPLEFT", enable, "BOTTOMLEFT", 6, -10)
    mobs:SetPoint("RIGHT", -PAD, 0)
    say(mobs, "MOBS")

    memo = S.Memo(frame, W - 2 * PAD, 150)
    memo:SetPoint("TOPLEFT", mobs, "BOTTOMLEFT", 0, -6)
    memo.edit:SetScript("OnTextChanged", function(self, user)
        if user then
            ns.SetNames(ns.ParseNames(self:GetText()))
            ns.Refresh()
        end
    end)

    local add = button(frame, "ADD_TARGET", 150)
    add:SetPoint("TOPLEFT", memo, "BOTTOMLEFT", 0, -8)
    add:SetScript("OnClick", function()
        local name = ns.AddTarget()
        memo.edit:ClearFocus()
        ns.Refresh()
        if not name then status:SetText(L.NO_TARGET) end
    end)

    -- How often to look.
    local every = S.Text(frame, 13)
    every:SetPoint("TOPLEFT", add, "BOTTOMLEFT", 0, -18)
    say(every, "EVERY")
    interval = S.Edit(frame, 50)
    interval:SetPoint("LEFT", every, "RIGHT", 10, 0)
    interval:SetMaxLetters(4)
    interval:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    interval:SetScript("OnEditFocusLost", function(self)
        S.SetBorder(self, S.BORDER)
        saveInterval(self)
    end)
    local sec = S.Text(frame, 13)
    sec:SetPoint("LEFT", interval, "RIGHT", 8, 0)
    say(sec, "SECONDS")

    -- Which sound: arrows step through the list and play the new sound.
    local sound = S.Text(frame, 13)
    sound:SetPoint("TOPLEFT", every, "BOTTOMLEFT", 0, -24)
    say(sound, "SOUND")
    local prev = S.Button(frame, 30, 30)
    prev:SetPoint("LEFT", sound, "RIGHT", 10, 0)
    prev:SetText("<")
    prev:SetScript("OnClick", function() stepSound(-1) end)
    soundName = S.Text(frame, 13)
    soundName:SetPoint("LEFT", prev, "RIGHT", 6, 0)
    soundName:SetWidth(150)
    soundName:SetJustifyH("CENTER")
    soundName:SetWordWrap(false)
    local nextB = S.Button(frame, 30, 30)
    nextB:SetPoint("LEFT", soundName, "RIGHT", 6, 0)
    nextB:SetText(">")
    nextB:SetScript("OnClick", function() stepSound(1) end)
    local play = button(frame, "PLAY", 90)
    play:SetPoint("TOPRIGHT", memo, "BOTTOMRIGHT", 0, -8)
    play:SetScript("OnClick", function() ns.PlayAlert() end)

    again = checkbox(frame, "AGAIN", function(on) ns.db.again = on end)
    again:SetPoint("TOPLEFT", sound, "BOTTOMLEFT", -6, -16)
    banner = checkbox(frame, "BANNER", function(on) ns.db.banner = on end)
    banner:SetPoint("TOPLEFT", again, "BOTTOMLEFT", 0, -2)

    local note = S.Text(frame, 11, S.MUTED)
    note:SetPoint("TOPLEFT", banner, "BOTTOMLEFT", 6, -10)
    note:SetPoint("RIGHT", -PAD, 0)
    note:SetWordWrap(true)
    say(note, "NOTE")

    status = S.Text(frame, 12)
    status:SetPoint("BOTTOMLEFT", PAD, 14)
    status:SetPoint("RIGHT", -PAD, 0)
    status:SetWordWrap(true)

    frame:SetScript("OnShow", ns.Refresh)
end

function ns.Toggle()
    if not frame then build() end
    frame:SetShown(not frame:IsShown())
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
        slash = "/gmf",
    })
end
