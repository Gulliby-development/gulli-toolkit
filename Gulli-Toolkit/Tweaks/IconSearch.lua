-- Icon search: a search box in the game's icon pickers (macros, equipment sets, guild bank tabs
-- and any addon picker built on IconSelectorPopupFrameTemplate). A picker reads its icons through
-- GetIconByIndex, GetNumIcons and GetIndexOfIcon on the frame; while a search runs, those serve
-- only the icons that match, so the game's own selection and OK button keep working.
-- The names come from the character: the spellbook, collected mounts, worn gear and the bags,
-- plus the icon's file id or path.

local _, ns = ...
local L = ns.L

local running, hooked = false, false
local states = {} -- picker frame -> { orig, filtered, box, empty }
local hay -- icon -> lower-case names, built when a picker shows

local function lower(s) return type(s) == "string" and s:lower() or nil end

local function add(t, icon, name)
    name = lower(name)
    if icon == nil or not name or name == "" then return end
    icon = tonumber(icon) or icon
    local old = t[icon]
    if not old then t[icon] = name
    elseif not old:find(name, 1, true) then t[icon] = old .. "|" .. name end
end

local function itemName(id)
    if not id then return nil end
    return ((C_Item and C_Item.GetItemNameByID) or GetItemInfo or function() end)(id)
end

-- icon -> the names of what this character has with that icon.
function ns.IconNames()
    local t = {}
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookItemInfo then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        for i = 1, C_SpellBook.GetNumSpellBookSkillLines() or 0 do
            local line = C_SpellBook.GetSpellBookSkillLineInfo(i)
            if line and line.itemIndexOffset and line.numSpellBookItems then
                for slot = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                    local info = C_SpellBook.GetSpellBookItemInfo(slot, bank)
                    if info then add(t, info.iconID, info.name) end
                end
            end
        end
    end
    if C_MountJournal and C_MountJournal.GetMountIDs then
        for _, id in ipairs(C_MountJournal.GetMountIDs() or {}) do
            local name, _, icon, _, _, _, _, _, _, _, collected = C_MountJournal.GetMountInfoByID(id)
            if collected then add(t, icon, name) end
        end
    end
    if GetInventoryItemTexture then
        for slot = 1, 19 do
            local icon = GetInventoryItemTexture("player", slot)
            if icon then add(t, icon, itemName(GetInventoryItemID("player", slot))) end
        end
    end
    if C_Container and C_Container.GetContainerNumSlots then
        for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
            for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info then add(t, info.iconFileID, itemName(info.itemID)) end
            end
        end
    end
    return t
end

-- The words of a search: { need = { ... }, without = { ... } }; nil for an empty one.
function ns.IconQuery(text)
    local need, without = {}, {}
    for w in (lower(text) or ""):gmatch("%S+") do
        if w:sub(1, 1) == "-" then
            if #w > 1 then without[#without + 1] = w:sub(2) end
        else need[#need + 1] = w end
    end
    if #need == 0 and #without == 0 then return nil end
    return { need = need, without = without }
end

-- Does this icon match? Its names, its path or its file id.
function ns.IconMatches(icon, names, q)
    local text = tostring(icon):lower() .. "|" .. (names or "")
    for _, w in ipairs(q.need) do
        if not text:find(w, 1, true) then return false end
    end
    for _, w in ipairs(q.without) do
        if text:find(w, 1, true) then return false end
    end
    return true
end

-- The icons of a picker that match the search, in the picker's order.
function ns.IconFilter(get, n, names, q)
    local out = {}
    for i = 1, n do
        local icon = get(i)
        if icon ~= nil and ns.IconMatches(icon, names[tonumber(icon) or icon], q) then out[#out + 1] = icon end
    end
    return out
end

local function refresh(frame)
    local st = states[frame]
    local sel = frame.IconSelector
    if sel and sel.SetSelectionsDataProvider and GenerateClosure then
        sel:SetSelectionsDataProvider(GenerateClosure(frame.GetIconByIndex, frame), GenerateClosure(frame.GetNumIcons, frame))
        if st.filtered and #st.filtered > 0 and sel.ScrollToElementDataIndex then pcall(sel.ScrollToElementDataIndex, sel, 1) end
    end
    if frame.ReevaluateSelectedIcon then pcall(frame.ReevaluateSelectedIcon, frame) end
    st.empty:SetShown(st.filtered ~= nil and #st.filtered == 0)
end

local function apply(frame)
    local st = states[frame]
    local q = running and ns.IconQuery(st.box:GetText())
    if not q then
        st.filtered = nil
    else
        hay = hay or ns.IconNames()
        st.filtered = ns.IconFilter(function(i) return st.orig.get(frame, i) end, st.orig.num(frame) or 0, hay, q)
    end
    refresh(frame)
end

local function later(frame)
    local st = states[frame]
    st.wait = (st.wait or 0) + 1
    local mine = st.wait
    if not (C_Timer and C_Timer.After) then return apply(frame) end
    C_Timer.After(0.15, function() if st.wait == mine then apply(frame) end end)
end

local function hook(frame)
    if states[frame] or type(frame) ~= "table" or not frame.IconSelector or not frame.BorderBox
        or type(frame.GetIconByIndex) ~= "function" or type(frame.GetNumIcons) ~= "function" then
        return states[frame]
    end
    local S = ns.Skin
    local st = { orig = { get = frame.GetIconByIndex, num = frame.GetNumIcons, index = frame.GetIndexOfIcon } }
    states[frame] = st
    -- The game's Update builds the selector from these methods, so it takes these at once.
    frame.GetIconByIndex = function(self, i)
        if st.filtered then return st.filtered[i] end
        return st.orig.get(self, i)
    end
    frame.GetNumIcons = function(self)
        if st.filtered then return #st.filtered end
        return st.orig.num(self)
    end
    frame.GetIndexOfIcon = function(self, icon)
        if st.filtered then
            for i, x in ipairs(st.filtered) do if x == icon then return i end end
            return nil
        end
        return st.orig.index and st.orig.index(self, icon) or nil
    end
    local border = frame.BorderBox
    local box = S.Edit(border, 150, 26)
    box:SetJustifyH("LEFT")
    box:SetMaxLetters(64)
    local level = border:GetFrameLevel()
    if type(level) == "number" then box:SetFrameLevel(level + 5) end
    if border.IconTypeDropdown then
        box:SetPoint("RIGHT", border.IconTypeDropdown, "LEFT", -12, 0)
    else
        box:SetPoint("TOPRIGHT", border, "TOPRIGHT", -40, -70)
    end
    S.Placeholder(box, L.TW_ICONSEARCH_BOX)
    box:HookScript("OnTextChanged", function() later(frame) end)
    st.box = box
    st.empty = S.Text(frame.IconSelector, 14, S.FAINT)
    st.empty:SetPoint("CENTER")
    st.empty:SetText(L.TW_ICONSEARCH_NONE)
    st.empty:Hide()
    if frame.SetIconFilterInternal then
        hooksecurefunc(frame, "SetIconFilterInternal", function(self) if st.filtered then apply(self) end end)
    end
    frame:HookScript("OnHide", function()
        st.wait = (st.wait or 0) + 1
        st.filtered, hay = nil, nil
        box:SetText("")
        box:ClearFocus()
        st.empty:Hide()
    end)
    return st
end
ns.IconSearchHook, ns.IconSearchApply = hook, apply

local function onShow(frame)
    local st = hook(frame)
    if st then st.box:SetShown(running) end
end

ns.AddTweak({
    key = "iconSearch", group = "ui", icon = "Interface\\Icons\\INV_Misc_Spyglass_02", star = true,
    enable = function()
        running = true
        if not hooked and IconSelectorPopupFrameTemplateMixin and IconSelectorPopupFrameTemplateMixin.OnShow then
            hooked = true
            -- Every picker calls the template's OnShow before its own Update.
            hooksecurefunc(IconSelectorPopupFrameTemplateMixin, "OnShow", onShow)
        end
        for _, st in pairs(states) do st.box:SetShown(true) end
    end,
    disable = function()
        running = false
        for frame, st in pairs(states) do
            st.box:SetText("")
            st.box:Hide()
            st.filtered = nil
            if frame:IsShown() then refresh(frame) end
        end
    end,
})
