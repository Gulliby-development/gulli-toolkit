-- The loot window of our own (switch `window`) and the group loot rolls the player places in the
-- hub's Unlock mode. The rules are plain functions (ns.LootRows, ns.TakeAll); the frames only
-- show them. The game's loot window stays the fallback: it comes back as soon as the switch goes
-- off or the hub pauses the module.

local _, ns = ...
local L = ns.L
local S = ns.Skin

ns.LOOT_ROWS = 8          -- rows shown before "+N more"
ns.PICKED_SECONDS = 3     -- how long the list of what auto loot took stays
local ROW_H, WIDTH, HEAD_H = 34, 250, 34

---- Rules ---------------------------------------------------------------------------------

-- Every slot of the open loot: { slot, icon, name, count, quality, locked, coin, quest }.
-- A slot the game already emptied is left out.
function ns.LootRows()
    local out = {}
    if not GetNumLootItems or not GetLootSlotInfo then return out end
    for i = 1, GetNumLootItems() or 0 do
        local icon, name, count, _, quality, locked, isQuest, _, _, isCoin = GetLootSlotInfo(i)
        if icon or name then
            out[#out + 1] = { slot = i, icon = icon, name = name, count = count or 1, quality = quality or 1,
                              locked = locked and true or false, coin = isCoin and true or false,
                              quest = isQuest and true or false }
        end
    end
    return out
end

-- Takes every slot that is not locked, last first (the slot numbers stay right).
function ns.TakeAll()
    if not LootSlot then return 0 end
    local rows, n = ns.LootRows(), 0
    for i = #rows, 1, -1 do
        if not rows[i].locked then LootSlot(rows[i].slot); n = n + 1 end
    end
    return n
end

-- Whether our window replaces the game's now.
function ns.OwnWindow()
    return ns.db ~= nil and ns.db.window == true and not ns.paused
end

-- The game's loot window shows from its own LOOT_OPENED: on = it hears the event.
local function gameWindow(on)
    local f = LootFrame
    if not f or not f.RegisterEvent then return end
    if on then f:RegisterEvent("LOOT_OPENED") else f:UnregisterEvent("LOOT_OPENED") end
end

-- The game's loot window opens only when ours does not.
function ns.ApplyWindow()
    local f = LootFrame
    if not f or not f.RegisterEvent then return end
    if ns.OwnWindow() then
        gameWindow(false)
        if f.IsShown and f:IsShown() and f.Hide then f:Hide() end
    else
        gameWindow(true)
        if ns.HideLoot then ns.HideLoot() end
    end
end

-- LOOT_READY comes before LOOT_OPENED. While Fast loot takes this loot, the game's window does not
-- hear LOOT_OPENED, so it never flashes; what is still there after ns.QUIET_WAIT (full bags, a
-- locked slot, a bind question) gets a window after all.
ns.QUIET_WAIT = 0.5

function ns.QuietLoot()
    if ns.OwnWindow() then return false end
    local quiet = ns.FastLootNow and ns.FastLootNow() or false
    gameWindow(not quiet)
    ns.quiet = quiet
    return quiet
end

-- What Fast loot could not take: the game's window, or ours when the game's cannot open.
function ns.ShowLeftover()
    if not ns.quiet or not ns.lootOpen or #ns.LootRows() == 0 then return false end
    ns.quiet = false
    local f = LootFrame
    if f and f.Open and not (f.IsShown and f:IsShown()) then
        f.isAutoLoot = false
        if pcall(f.Open, f) then return true end
    end
    ns.ShowLoot(false)
    return true
end

---- The window -------------------------------------------------------------------------------

local win
-- The window's state, kept here (the fake frames of the tests answer any field).
local picked, sample = false, false

local function rowName(r)
    if r.coin then return (r.name or ""):gsub("\n", " ") end
    return S.QualityHex(r.quality) .. (r.name or "?") .. "|r"
end

local function makeRow(i)
    local b = CreateFrame("Button", nil, win)
    b:SetHeight(ROW_H)
    b:SetPoint("TOPLEFT", 6, -HEAD_H - (i - 1) * ROW_H)
    b:SetPoint("RIGHT", -6, 0)
    b.icon = S.IconBox(b, 26)
    b.icon:SetPoint("LEFT", 2, 0)
    b.name = S.Text(b, 12)
    b.name:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
    b.name:SetPoint("RIGHT", -34, 0)
    b.name:SetWordWrap(false)
    b.count = S.Text(b, 12, S.MUTED)
    b.count:SetPoint("RIGHT", -4, 0)
    b.count:SetJustifyH("RIGHT")
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0.05)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self)
        if not self.row or picked then return end
        if IsModifiedClick and IsModifiedClick() and GetLootSlotLink and HandleModifiedItemClick then
            HandleModifiedItemClick(GetLootSlotLink(self.row.slot))
            return
        end
        LootSlot(self.row.slot)
    end)
    b:SetScript("OnEnter", function(self)
        if not self.row or self.row.coin or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetLootItem and not picked then GameTooltip:SetLootItem(self.row.slot) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return b
end

local function place()
    if not win then return end
    win:ClearAllPoints()
    local p = ns.db and ns.db.lootPoint
    if p then win:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else win:SetPoint("LEFT", UIParent, "LEFT", 260, 80) end
end

local function build()
    win = CreateFrame("Frame", "GulliLootWindow", UIParent)
    win:SetFrameStrata("HIGH")
    win:SetSize(WIDTH, HEAD_H + ROW_H + 8)
    win:EnableMouse(true)
    S.HudPanel(win)
    win.title = S.Text(win, 12, S.GOLD, nil, "bold")
    win.title:SetPoint("TOPLEFT", 10, -10)
    win.close = S.Close(win, function() if CloseLoot then CloseLoot() end ns.HideLoot() end)
    win.close:SetPoint("TOPRIGHT", -4, -4)
    win.take = S.Primary(S.Button(win, 90, 28))
    win.take:SetPoint("RIGHT", win.close, "LEFT", -4, 0)
    win.take:SetText(L.TAKE_ALL)
    win.take:SetScript("OnClick", function() ns.TakeAll() end)
    win.more = S.Text(win, 12, S.FAINT)
    win.more:SetPoint("BOTTOMLEFT", 10, 6)
    win.rows = {}
    for i = 1, ns.LOOT_ROWS do win.rows[i] = makeRow(i) end
    S.Mover(win, { label = L.FR_WINDOW, hint = L.TIP_MOVE,
        save = function(p, rp, x, y) ns.db.lootPoint = { p, rp, x, y } end,
        reset = function() ns.db.lootPoint = nil; place() end })
    if UISpecialFrames then tinsert(UISpecialFrames, "GulliLootWindow") end
    win:SetScript("OnHide", function(self)
        -- Escape or a close of our window closes the loot, like the game's window does.
        if not picked and not sample and CloseLoot and ns.lootOpen then CloseLoot() end
    end)
    place()
    win:Hide()
end

-- Draws rows; picked = the list of what auto loot just took (no clicks, it fades on its own).
local function paint(rows, isPicked)
    if not win then build() end
    picked = isPicked and true or false
    win.title:SetText(picked and L.PICKED or L.LOOT_TITLE)
    win.take:SetShown(not picked and #rows > 0)
    for i, b in ipairs(win.rows) do
        local r = rows[i]
        b.row = r
        b:SetShown(r ~= nil)
        if r then
            b.icon:SetIcon(r.icon)
            b.name:SetText(rowName(r))
            b.count:SetText((not r.coin and (r.count or 1) > 1) and ("x" .. r.count) or "")
            b:SetAlpha(r.locked and 0.5 or 1)
        end
    end
    local shown = math.min(#rows, ns.LOOT_ROWS)
    local extra = #rows - shown
    win.more:SetText(extra > 0 and L.MORE:format(extra) or "")
    win:SetHeight(HEAD_H + math.max(1, shown) * ROW_H + (extra > 0 and 22 or 8))
    win:Show()
end

function ns.ShowLoot(autoLoot)
    ns.lootOpen = true
    local rows = ns.LootRows()
    if autoLoot then
        -- The game (or Fast loot) takes everything: show what came, for a moment.
        if #rows == 0 then return end
        paint(rows, true)
        local token = {}
        ns.pickedToken = token
        if C_Timer then
            C_Timer.After(ns.PICKED_SECONDS, function()
                if ns.pickedToken == token and win and picked then win:Hide(); picked = false end
            end)
        end
        return
    end
    paint(rows, false)
end

function ns.RefreshLoot()
    if not win or not win:IsShown() or picked or sample then return end
    local rows = ns.LootRows()
    if #rows == 0 then win:Hide() return end
    paint(rows, false)
end

function ns.HideLoot()
    ns.lootOpen = false
    if win and win:IsShown() and not picked and not sample then win:Hide() end
end

function ns.OnLootEvent(event, a1)
    if event == "LOOT_OPENED" then
        if ns.OwnWindow() then ns.ShowLoot(a1)
        elseif ns.quiet then
            ns.lootOpen = true
            local token = {}
            ns.quietToken = token   -- a wait of an earlier loot shows nothing
            if C_Timer then C_Timer.After(ns.QUIET_WAIT, function() if ns.quietToken == token then ns.ShowLeftover() end end)
            else ns.ShowLeftover() end
        end
    elseif event == "LOOT_SLOT_CLEARED" or event == "LOOT_SLOT_CHANGED" then
        ns.RefreshLoot()
    elseif event == "LOOT_CLOSED" then
        if ns.quiet then ns.quiet = false; gameWindow(true) end
        ns.HideLoot()
    end
end

-- For the Unlock mode and the tests.
function ns.LootWindowFrame()
    if not win then build() end
    return win
end
function ns.LootPicked() return picked end

---- Rolls --------------------------------------------------------------------------------------

-- The game anchors its roll frames above the action bars on every layout. With `rollMove` (on once
-- the player placed them), every such anchor is followed by ours: the container sits at our place.
local anchor, hooked, busy

local function rollAnchor()
    if anchor then return anchor end
    anchor = CreateFrame("Frame", "GulliLootRollAnchor", UIParent)
    anchor:SetSize(280, 84)
    S.HudPanel(anchor)
    anchor.text = S.Text(anchor, 12, S.MUTED)
    anchor.text:SetPoint("CENTER")
    anchor.text:SetText(L.ROLL_SAMPLE)
    S.Mover(anchor, { label = L.FR_ROLLS, hint = L.TIP_MOVE,
        save = function(p, rp, x, y) ns.db.rollPoint = { p, rp, x, y }; ns.db.rollMove = true; ns.PlaceRolls() end,
        reset = function() ns.db.rollPoint = nil; ns.PlaceRolls() end })
    anchor:Hide()
    return anchor
end
ns.RollAnchor = function() return rollAnchor() end

local function placeAnchor()
    local a = rollAnchor()
    a:ClearAllPoints()
    local p = ns.db and ns.db.rollPoint
    if p then a:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else a:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 220) end
end

-- Puts the game's roll container on our anchor (only with `rollMove`) at its scale.
function ns.PlaceRolls()
    placeAnchor()
    local c = GroupLootContainer
    if not c then return false end
    if InCombatLockdown and InCombatLockdown() and c.IsProtected and c:IsProtected() then return false end
    S.ApplyScale(c, (ns.db and ns.db.rollScale or 100) / 100)
    if not (ns.db and ns.db.rollMove) or ns.paused then return false end
    busy = true
    c:ClearAllPoints()
    c:SetPoint("BOTTOM", anchor, "BOTTOM", 0, 0)
    busy = false
    if not hooked and hooksecurefunc then
        hooked = true
        hooksecurefunc(c, "SetPoint", function()
            if not busy and ns.db and ns.db.rollMove and not ns.paused then ns.PlaceRolls() end
        end)
    end
    return true
end

---- Unlock mode --------------------------------------------------------------------------------

function ns.MoveFrames(on)
    if InCombatLockdown and InCombatLockdown() then return end
    local w = ns.LootWindowFrame()
    if on then
        paint({ { slot = 0, icon = "Interface\\Icons\\INV_Misc_Coin_02", name = L.SAMPLE_COIN, coin = true, count = 1 },
                { slot = 0, icon = "Interface\\Icons\\INV_Misc_Gem_Ruby_01", name = L.SAMPLE_ITEM, quality = 3, count = 1 } }, false)
        sample = true
    elseif sample then
        w:Hide()
        sample = false
    end
    if w.SetMoving then w:SetMoving(on) end
    local a = rollAnchor()
    placeAnchor()
    a:SetShown(on and true or false)
    if a.SetMoving then a:SetMoving(on) end
end
