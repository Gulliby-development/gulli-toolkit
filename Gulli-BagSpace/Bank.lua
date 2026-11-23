-- The bank helper (switch `bank`): at the bank, a list beside it of the bag items that belong
-- there. A click puts one away, **Bank all** puts the whole list away step by step from that
-- click, a right-click keeps an item out of the list for good (`bankNever`). It never moves
-- quest items, keys, tools, set items, protected items or what Gulli Restock keeps in the bags.

local _, ns = ...
local L = ns.L
local S = ns.Skin
local J = ns.J

ns.BANK_ROWS = 10        -- rows shown before "+N more"
ns.BANK_STEP = 0.2       -- seconds between two moves of Bank all
-- The reasons, in list order. A new reason gets a key here, a BANK_<KEY> text and a test.
ns.BANK_WHY = { "stack", "goods", "recipe", "later", "alt" }
local ORDER = {}
for i, k in ipairs(ns.BANK_WHY) do ORDER[k] = i end

local ITEM_CONSUMABLE, ITEM_GEM, ITEM_WEAPON, ITEM_ARMOR, ITEM_GOODS, ITEM_RECIPE = 0, 3, 2, 4, 7, 9
-- Gear every class wears: never "for another character".
local ANYONE = { INVTYPE_CLOAK = true, INVTYPE_NECK = true, INVTYPE_FINGER = true, INVTYPE_TRINKET = true,
                 INVTYPE_HOLDABLE = true, INVTYPE_BODY = true, INVTYPE_TABARD = true }

local C = C_Container or {}
local function numSlots(bag) return (C.GetContainerNumSlots or GetContainerNumSlots)(bag) or 0 end
local function useItem(bag, slot) (C.UseContainerItem or UseContainerItem)(bag, slot) end
local function minLevel(id)
    local _, _, _, _, req = ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(id)
    return req or 0
end

-- The bank's containers: the bank tabs of the newer client, else the old bank and its bags.
function ns.BankContainers()
    local B = Enum and Enum.BagIndex
    if B and B.CharacterBankTab_1 then
        local out = {}
        for i = 1, 6 do if B["CharacterBankTab_" .. i] then out[#out + 1] = B["CharacterBankTab_" .. i] end end
        return out
    end
    local out = { BANK_CONTAINER or -1 }
    local first = (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) + 1
    for b = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do out[#out + 1] = b end
    return out
end

-- What Gulli Restock keeps in the bags (its list for this character), item id -> true.
local function restocked()
    local out = {}
    local list = GulliRestockCharDB and GulliRestockCharDB.list
    if type(list) == "table" then
        for key in pairs(list) do if type(key) == "number" then out[key] = true end end
    end
    return out
end

local function cannotWear(it)
    local _, class = UnitClass("player")
    local can = J.CAN_USE[class or ""]
    if not can or ANYONE[it.equipLoc or ""] then return false end
    if it.classID == ITEM_ARMOR then return it.subclassID ~= nil and it.subclassID ~= 0 and not can.armor[it.subclassID] end
    if it.classID == ITEM_WEAPON then return it.subclassID ~= nil and not can.weapon[it.subclassID] end
    return false
end

-- Why an item belongs in the bank, or nil. inBank: item id -> true for what the bank holds.
function ns.BankWhy(it, inBank, keep)
    if not it or it.locked or J.Never(it) or (it.quality or 1) == 0 or J.IsAlways(it.id) then return nil end
    if (ns.db.bankNever or {})[it.id] or (keep and keep[it.id]) then return nil end
    if inBank[it.id] and it.classID ~= ITEM_WEAPON and it.classID ~= ITEM_ARMOR then return "stack" end
    if it.classID == ITEM_GOODS or it.classID == ITEM_GEM then return "goods" end
    if it.classID == ITEM_RECIPE then return "recipe" end
    local level = UnitLevel("player") or 1
    if (it.classID == ITEM_WEAPON or it.classID == ITEM_ARMOR or it.classID == ITEM_CONSUMABLE)
        and minLevel(it.id) > level then
        return "later"
    end
    -- Bound gear the class cannot wear is junk (sold); unbound gear may go to another character.
    if (it.classID == ITEM_WEAPON or it.classID == ITEM_ARMOR) and it.bound == false and cannotWear(it) then
        return "alt"
    end
    return nil
end

-- The list: { bag, slot, id, name, icon, count, quality, link, why }, by reason, then name.
function ns.BankPlan()
    local inBank = {}
    for _, b in ipairs(ns.BankContainers()) do
        for slot = 1, numSlots(b) do
            local id = J.SlotInfo(b, slot)
            if id then inBank[id] = true end
        end
    end
    local keep, out = restocked(), {}
    for _, b in ipairs(ns.Bags()) do
        for slot = 1, numSlots(b) do
            local it = J.Item(b, slot)
            local why = ns.BankWhy(it, inBank, keep)
            if why then
                out[#out + 1] = { bag = b, slot = slot, id = it.id, name = it.name, icon = it.icon, count = it.count,
                                  quality = it.quality, link = it.link, why = why }
            end
        end
    end
    table.sort(out, function(a, c)
        if a.why ~= c.why then return ORDER[a.why] < ORDER[c.why] end
        if a.name ~= c.name then return a.name < c.name end
        return a.bag * 100 + a.slot < c.bag * 100 + c.slot
    end)
    return out
end

-- Puts one entry into the bank (the game puts a used bag item there while the bank is open).
function ns.BankOne(e)
    if not ns.atBank or (InCombatLockdown and InCombatLockdown()) then return false end
    local id = J.SlotInfo(e.bag, e.slot)
    if id ~= e.id then return false end
    useItem(e.bag, e.slot)
    return true
end

-- Bank all, from its click: one move per short step, stopped when the bank closes.
local queue = {}
local function step()
    local e = table.remove(queue, 1)
    if not e or not ns.atBank then wipe(queue); if ns.RefreshBank then ns.RefreshBank() end return end
    ns.BankOne(e)
    if C_Timer then C_Timer.After(ns.BANK_STEP, step) else step() end
end
function ns.BankAll(list)
    local idle = #queue == 0
    for _, e in ipairs(list or ns.BankPlan()) do queue[#queue + 1] = e end
    if idle and #queue > 0 then step() end
    return #queue
end
function ns.BankQueued() return #queue end

-- Right-click: never offer this item again (until /gbs reset).
function ns.NeverBank(id)
    ns.db.bankNever = ns.db.bankNever or {}
    ns.db.bankNever[id] = true
    if ns.RefreshBank then ns.RefreshBank() end
end

---- The list beside the bank -----------------------------------------------------------------

local ROW_H, WIDTH, HEAD_H = 32, 270, 36
local panel

local function makeRow(i)
    local b = CreateFrame("Button", nil, panel)
    b:SetHeight(ROW_H)
    b:SetPoint("TOPLEFT", 6, -HEAD_H - (i - 1) * ROW_H)
    b:SetPoint("RIGHT", -6, 0)
    b.icon = S.IconBox(b, 24)
    b.icon:SetPoint("LEFT", 2, 0)
    b.name = S.Text(b, 12)
    b.name:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 8, 1)
    b.name:SetPoint("RIGHT", -4, 0)
    b.name:SetWordWrap(false)
    b.why = S.Text(b, 12, S.FAINT)
    b.why:SetPoint("BOTTOMLEFT", b.icon, "BOTTOMRIGHT", 8, -2)
    b.why:SetPoint("RIGHT", -4, 0)
    b.why:SetWordWrap(false)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0.05)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, mouse)
        if not self.entry then return end
        if mouse == "RightButton" then ns.NeverBank(self.entry.id) return end
        ns.BankOne(self.entry)
    end)
    b:SetScript("OnEnter", function(self)
        if not self.entry or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetBagItem then GameTooltip:SetBagItem(self.entry.bag, self.entry.slot) end
        GameTooltip:AddLine(L.BANK_TIP, 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return b
end

local function place()
    panel:ClearAllPoints()
    local bank = BankFrame
    if bank and bank.IsShown and bank:IsShown() then panel:SetPoint("TOPLEFT", bank, "TOPRIGHT", 8, 0)
    else panel:SetPoint("LEFT", UIParent, "LEFT", 420, 60) end
end

local function build()
    panel = CreateFrame("Frame", "GulliBagSpaceBank", UIParent)
    panel:SetFrameStrata("HIGH")
    panel:SetSize(WIDTH, HEAD_H + ROW_H + 8)
    panel:EnableMouse(true)
    S.HudPanel(panel)
    panel.title = S.Text(panel, 12, S.GOLD, nil, "bold")
    panel.title:SetPoint("TOPLEFT", 10, -11)
    panel.close = S.Close(panel, function() panel:Hide() end)
    panel.close:SetPoint("TOPRIGHT", -4, -4)
    panel.all = S.Primary(S.Button(panel, 96, 28))
    panel.all:SetPoint("RIGHT", panel.close, "LEFT", -4, 0)
    panel.all:SetText(L.BANK_ALL)
    panel.all:SetScript("OnClick", function() ns.BankAll() end)
    panel.more = S.Text(panel, 12, S.FAINT)
    panel.more:SetPoint("BOTTOMLEFT", 10, 6)
    panel.rows = {}
    for i = 1, ns.BANK_ROWS do panel.rows[i] = makeRow(i) end
    panel:Hide()
end

function ns.BankFrame()
    if not panel then build() end
    return panel
end

-- Draws the list; hides the panel when nothing is left or the bank is closed.
function ns.RefreshBank(open)
    if not ns.db or not ns.db.bank or not ns.atBank then if panel then panel:Hide() end return end
    if not open and not (panel and panel:IsShown()) then return end
    local list = ns.BankPlan()
    if #list == 0 then if panel then panel:Hide() end return end
    ns.BankFrame()
    panel.title:SetText(L.BANK_TITLE:format(#list))
    for i, b in ipairs(panel.rows) do
        local e = list[i]
        b.entry = e
        b:SetShown(e ~= nil)
        if e then
            b.icon:SetIcon(e.icon)
            b.name:SetText(S.QualityHex(e.quality) .. (e.name or "?") .. "|r" .. ((e.count or 1) > 1 and (" x" .. e.count) or ""))
            b.why:SetText(L["BANK_" .. e.why:upper()])
        end
    end
    local shown = math.min(#list, ns.BANK_ROWS)
    local extra = #list - shown
    panel.more:SetText(extra > 0 and L.MORE_ROWS:format(extra) or "")
    panel:SetHeight(HEAD_H + shown * ROW_H + (extra > 0 and 22 or 8))
    place()
    panel:Show()
end

function ns.BankOpened()
    ns.atBank = true
    ns.RefreshBank(true)
end
function ns.BankClosed()
    ns.atBank = false
    wipe(queue)
    if panel then panel:Hide() end
end

if S.ClosesWith then S.ClosesWith("bank", ns.BankClosed) end
