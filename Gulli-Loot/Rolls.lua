-- Who rolled what (switch `rollers`): a panel under the game's Need / Greed / Pass frames lists the
-- group's choices for the roll, Need first, with counts on top. The game tells the choices two
-- ways: the loot history (C_LootHistory, also Main spec or Off spec and the roll numbers) and the
-- loot chat ("Bob has selected Need for: [Item]"). Both feed one list per roll; the panel only reads
-- the game and never rolls.

local _, ns = ...
local L = ns.L
local S = ns.Skin

ns.ROLLERS_ROWS = 8     -- rows shown at most; the rest is one "+N" line
ns.ROLLERS_KEEP = 600   -- a roll the game never closed is forgotten after this many seconds
-- Choices in the order the panel lists them; greed, transmog and disenchant count as greed on top.
ns.CHOICES = { "need", "greed", "transmog", "disenchant", "pass", "wait" }
local RANK = {}
for i, c in ipairs(ns.CHOICES) do RANK[c] = i end
local HEAD = { need = "need", greed = "greed", transmog = "greed", disenchant = "greed", pass = "pass" }

-- The game's own roll pictures (atlas first, the old button textures where a client lacks it).
local ICON = {
    need = { "lootroll-icon-need", "Interface\\Buttons\\UI-GroupLoot-Dice-Up" },
    greed = { "lootroll-icon-greed", "Interface\\Buttons\\UI-GroupLoot-Coin-Up" },
    transmog = { "lootroll-icon-transmog", "Interface\\Buttons\\UI-GroupLoot-Coin-Up" },
    disenchant = { "lootroll-icon-disenchant", "Interface\\Buttons\\UI-GroupLoot-DE-Up" },
    pass = { "lootroll-icon-pass", "Interface\\Buttons\\UI-GroupLoot-Pass-Up" },
    wait = { nil, "Interface\\Icons\\INV_Misc_PocketWatch_01" },
}
ns.ROLLERS_ICON = ICON

local rolls = {}        -- rollID -> { id, link, at, by = { name -> entry }, drop }

local function now() return GetTime and GetTime() or 0 end
local function secret(v) return issecretvalue and issecretvalue(v) end
local function itemId(link) return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil end
local function short(name) return type(name) == "string" and (name:match("^([^%-]+)") or name) or nil end

function ns.RollersOn() return ns.db ~= nil and ns.db.rollers == true and not ns.paused end

---- The group, for the class of a name from the chat ------------------------------------------

-- The name and class file of a unit; nil for a secret or missing answer.
local function ask(unit)
    local ok, name = pcall(UnitName, unit)
    if not ok or name == nil or secret(name) then return nil end
    local ok2, _, class = pcall(UnitClass, unit)
    if not ok2 or secret(class) then class = nil end
    return name, class
end

local function classOf(name)
    local want = short(name)
    if not want then return nil end
    local units = { "player" }
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do units[#units + 1] = "raid" .. i end
    else
        for i = 1, 4 do units[#units + 1] = "party" .. i end
    end
    for _, u in ipairs(units) do
        local n, class = ask(u)
        if n and short(n) == want then return class end
    end
    return nil
end

local function me()
    local n = ask("player")
    return n
end

---- The list of each roll ------------------------------------------------------------------

-- A roll the game started: its list starts empty.
function ns.RollerStart(rollID)
    if rollID == nil then return nil end
    local link = GetLootRollItemLink and GetLootRollItemLink(rollID)
    local r = { id = itemId(link), link = link, at = now(), by = {} }
    rolls[rollID] = r
    for k, x in pairs(rolls) do
        if now() - x.at > ns.ROLLERS_KEEP then rolls[k] = nil end
    end
    return r
end

function ns.RollerEnd(rollID) rolls[rollID] = nil end
function ns.RollerData(rollID) return rolls[rollID] end

-- The open roll of an item: the oldest one that has no choice from this name yet, else the newest.
local function rollFor(id, name)
    if not id then return nil end
    local best, bestKey, any, anyKey
    for k, r in pairs(rolls) do
        if r.id == id then
            if not (name and r.by[short(name)]) and (not best or r.at < best.at) then best, bestKey = r, k end
            if not any or r.at > any.at then any, anyKey = r, k end
        end
    end
    if best then return best, bestKey end
    return any, anyKey
end

-- Notes one player's choice (need, greed, transmog, disenchant, pass, wait) on a roll; a known
-- choice is never taken back to "wait", and spec ("main", "off") and roll stay once known.
local function note(r, name, choice, class, spec, roll, self)
    local key = short(name)
    if not r or not key then return nil end
    local e = r.by[key]
    if not e then
        e = { name = key }
        r.by[key] = e
    end
    if choice and not (choice == "wait" and e.choice and e.choice ~= "wait") then e.choice = choice end
    e.class = class or e.class or classOf(key)
    e.spec = spec or e.spec
    e.roll = roll or e.roll
    if self then e.self = true end
    if key == short(me()) then e.self = true end
    return e
end

---- The loot chat ------------------------------------------------------------------------------

-- A pattern for a game format string such as "%s passed on: %s" or "%2$s ... %1$s", and the
-- order its captures stand for.
function ns.CompileFormat(fmt)
    if type(fmt) ~= "string" or fmt == "" then return nil end
    local pat, order, i, n = "^", {}, 1, 0
    while i <= #fmt do
        local a, b, pos, conv = fmt:find("^%%(%d*)%$?([sd])", i)
        if a then
            n = n + 1
            order[n] = tonumber(pos) or n
            pat = pat .. (conv == "d" and "(%-?%d+)" or "(.+)")
            i = b + 1
        elseif fmt:sub(i, i + 1) == "%%" then
            pat, i = pat .. "%%", i + 2
        else
            local c = fmt:sub(i, i)
            if c:find("[%^%$%(%)%%%.%[%]%*%+%-%?]") then c = "%" .. c end
            pat, i = pat .. c, i + 1
        end
    end
    return pat .. "$", order
end

local function parse(fmt, msg)
    local pat, order = ns.CompileFormat(fmt)
    if not pat then return nil end
    local caps = { msg:match(pat) }
    if #caps == 0 then return nil end
    local out = {}
    for k, v in ipairs(caps) do out[order[k] or k] = v end
    return out
end

-- The game's lines: the global's name, the choice, and what its arguments are.
local LINES = {
    { "LOOT_ROLL_NEED", "need", "name", "item" },
    { "LOOT_ROLL_GREED", "greed", "name", "item" },
    { "LOOT_ROLL_TRANSMOG", "transmog", "name", "item" },
    { "LOOT_ROLL_DISENCHANT", "disenchant", "name", "item" },
    { "LOOT_ROLL_PASSED", "pass", "name", "item" },
    { "LOOT_ROLL_PASSED_AUTO", "pass", "name", "item" },
    { "LOOT_ROLL_PASSED_AUTO_FEMALE", "pass", "name", "item" },
    { "LOOT_ROLL_NEED_SELF", "need", "item" },
    { "LOOT_ROLL_GREED_SELF", "greed", "item" },
    { "LOOT_ROLL_TRANSMOG_SELF", "transmog", "item" },
    { "LOOT_ROLL_DISENCHANT_SELF", "disenchant", "item" },
    { "LOOT_ROLL_PASSED_SELF", "pass", "item" },
    { "LOOT_ROLL_PASSED_SELF_AUTO", "pass", "item" },
    { "LOOT_ROLL_ROLLED_NEED", nil, "roll", "item", "name" },
    { "LOOT_ROLL_ROLLED_NEED_ROLE_BONUS", nil, "roll", "item", "name" },
    { "LOOT_ROLL_ROLLED_GREED", nil, "roll", "item", "name" },
    { "LOOT_ROLL_ROLLED_TRANSMOG", nil, "roll", "item", "name" },
    { "LOOT_ROLL_ROLLED_DE", nil, "roll", "item", "name" },
}

-- A loot chat line about a choice or a roll number; returns the entry it changed.
function ns.RollerChat(msg)
    if type(msg) ~= "string" or secret(msg) then return nil end
    for _, l in ipairs(LINES) do
        local fmt = _G[l[1]]
        local a = type(fmt) == "string" and parse(fmt, msg)
        if a then
            local f = {}
            for k = 3, #l do f[l[k]] = a[k - 2] end
            local name = f.name or me()
            local r = rollFor(itemId(f.item), f.name and name or nil)
            if r then
                local e = note(r, name, l[2], nil, nil, tonumber(f.roll), f.name == nil)
                ns.RollersPaint()
                return e
            end
            return nil
        end
    end
    return nil
end

---- The loot history ---------------------------------------------------------------------------

local function stateChoice(state)
    local E = Enum and Enum.EncounterLootDropRollState
    if not E or state == nil then return nil end
    if state == E.NeedMainSpec then return "need", "main" end
    if state == E.NeedOffSpec then return "need", "off" end
    if state == E.Transmog then return "transmog" end
    if state == E.Greed then return "greed" end
    if state == E.Pass then return "pass" end
    if state == E.NoRoll then return "wait" end
    return nil
end

-- The game's loot history of one drop: every member with a choice, waiting, spec and roll.
function ns.RollerHistory(encounterID, key)
    if not (C_LootHistory and C_LootHistory.GetSortedInfoForDrop) then return nil end
    local ok, info = pcall(C_LootHistory.GetSortedInfoForDrop, encounterID, key)
    if not ok or type(info) ~= "table" or secret(info.itemHyperlink) then return nil end
    local tag = tostring(encounterID) .. ":" .. tostring(key)
    local r
    for _, x in pairs(rolls) do
        if x.drop == tag then r = x end
    end
    if not r then
        local id = itemId(info.itemHyperlink)
        local best
        for _, x in pairs(rolls) do
            if x.id == id and not x.drop and (not best or x.at < best.at) then best = x end
        end
        r = best
        if not r then return nil end
        r.drop = tag
    end
    for _, ri in ipairs(info.rollInfos or {}) do
        local name = ri.playerName
        if name and not secret(name) then
            local choice, spec = stateChoice(ri.state)
            local class = ri.playerClass
            if secret(class) then class = nil end
            local roll = ri.roll
            if secret(roll) then roll = nil end
            note(r, ri.isSelf and (me() or name) or name, choice, class, spec, roll, ri.isSelf)
        end
    end
    ns.RollersPaint()
    return r
end

---- What the panel shows -----------------------------------------------------------------------

-- The rows of a roll in the panel's order and the counts on top: { need, greed, pass, wait }.
function ns.RollerRows(r)
    local list, counts = {}, { need = 0, greed = 0, pass = 0, wait = 0 }
    if not r then return list, counts end
    for _, e in pairs(r.by) do
        if e.choice then
            list[#list + 1] = e
            local h = HEAD[e.choice] or "wait"
            counts[h] = counts[h] + 1
        end
    end
    table.sort(list, function(a, b)
        local ra, rb = RANK[a.choice] or 99, RANK[b.choice] or 99
        if ra ~= rb then return ra < rb end
        if (a.spec == "main") ~= (b.spec == "main") then return a.spec == "main" end
        if (a.roll or 0) ~= (b.roll or 0) then return (a.roll or 0) > (b.roll or 0) end
        return a.name < b.name
    end)
    return list, counts
end

---- The panel ----------------------------------------------------------------------------------

local WIDTH, ROW_H, HEAD_H, PAD = 277, 22, 28, 6
local frame, rows, heads, itemBox, more, empty, sample, hooked

local function setIcon(tex, choice)
    local p = ICON[choice] or ICON.wait
    if p[1] and tex.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(p[1]) then
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetAtlas(p[1])
    else
        tex:SetTexture(p[2])
    end
end

local function classIcon(tex, class)
    if class and tex.SetAtlas and GetClassAtlas then
        local atlas = GetClassAtlas(class)
        if atlas then tex:SetAtlas(atlas); tex:Show(); return end
    end
    tex:Hide()
end

local function classHex(class)
    local c = class and ((C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class))
        or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]))
    if c and c.r then return string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) end
    return "|cffe8e0d0"
end

local function makeRow(i)
    local r = CreateFrame("Frame", nil, frame)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", PAD, -(HEAD_H + 4) - (i - 1) * ROW_H)
    r:SetPoint("RIGHT", -PAD - 4, 0)
    r.choice = r:CreateTexture(nil, "ARTWORK")
    r.choice:SetSize(18, 18)
    r.choice:SetPoint("LEFT", 4, 0)
    r.class = r:CreateTexture(nil, "ARTWORK")
    r.class:SetSize(16, 16)
    r.class:SetPoint("LEFT", r.choice, "RIGHT", 8, 0)
    r.right = S.Text(r, 12, S.MUTED)
    r.right:SetPoint("RIGHT", 0, 0)
    r.right:SetJustifyH("RIGHT")
    r.name = S.Text(r, 12)
    r.name:SetPoint("LEFT", r.class, "RIGHT", 6, 0)
    r.name:SetPoint("RIGHT", r.right, "LEFT", -6, 0)
    r.name:SetWordWrap(false)
    return r
end

local function build()
    frame = CreateFrame("Frame", "GulliLootRollers", UIParent)
    frame:SetFrameStrata("DIALOG")
    frame:SetSize(WIDTH, HEAD_H + 8 + ROW_H)
    S.HudPanel(frame)
    heads = {}
    local x = PAD + 4
    for i, c in ipairs({ "need", "greed", "pass" }) do
        local h = CreateFrame("Frame", nil, frame)
        h:SetSize(52, HEAD_H)
        h:SetPoint("TOPLEFT", x + (i - 1) * 56, 0)
        h.icon = h:CreateTexture(nil, "ARTWORK")
        h.icon:SetSize(16, 16)
        h.icon:SetPoint("LEFT", 0, 0)
        setIcon(h.icon, c)
        h.text = S.Text(h, 13, S.TEXT, nil, "bold")
        h.text:SetPoint("LEFT", h.icon, "RIGHT", 5, 0)
        heads[c] = h
    end
    itemBox = S.IconBox(frame, 20)
    itemBox:SetPoint("TOPRIGHT", -PAD - 2, -4)
    local line = S.Divider(frame)
    line:SetPoint("TOPLEFT", 1, -HEAD_H)
    line:SetPoint("TOPRIGHT", -1, -HEAD_H)
    line:SetHeight(1)
    rows = {}
    for i = 1, ns.ROLLERS_ROWS do rows[i] = makeRow(i) end
    more = S.Text(frame, 12, S.FAINT)
    more:SetPoint("BOTTOMLEFT", PAD + 4, 4)
    empty = S.Text(frame, 12, S.FAINT)
    empty:SetPoint("TOPLEFT", PAD + 4, -(HEAD_H + 8))
    empty:SetPoint("RIGHT", -PAD, 0)
    empty:SetText(L.ROLLERS_NONE)
    local acc = 0
    frame:SetScript("OnUpdate", function(_, dt)
        acc = acc + (dt or 0)
        if acc < 0.2 then return end
        acc = 0
        ns.RollersPaint()
    end)
    frame:Hide()
end

function ns.RollersFrame()
    if not frame then build() end
    return frame
end

-- The game's roll frames that show, lowest first (the panel sits under the lowest).
local function shownFrames()
    local out = {}
    for i = 1, 4 do
        local f = _G["GroupLootFrame" .. i]
        if f and f.IsShown and f:IsShown() == true and f.rollID then out[#out + 1] = f end
    end
    local c = GroupLootContainer
    local order = {}
    if c and type(c.rollFrames) == "table" then
        for idx, f in pairs(c.rollFrames) do order[f] = idx end
    end
    table.sort(out, function(a, b) return (order[a] or 99) < (order[b] or 99) end)
    return out
end

local function hookFrames()
    if hooked then return end
    hooked = true
    for i = 1, 4 do
        local f = _G["GroupLootFrame" .. i]
        if f and f.HookScript then
            f:HookScript("OnShow", function() ns.RollersPaint() end)
            f:HookScript("OnHide", function() ns.RollersPaint() end)
        end
    end
end

local function sampleRoll()
    local you = me() or L.YOU
    return { by = {
        a = { name = L.SAMPLE_P1, class = "WARRIOR", choice = "need", spec = "main" },
        b = { name = L.SAMPLE_P2, class = "PALADIN", choice = "need", spec = "off" },
        c = { name = you, class = select(2, UnitClass("player")) or "PRIEST", choice = "greed", self = true },
        d = { name = L.SAMPLE_P3, class = "MAGE", choice = "pass" },
    } }
end

-- Draws the panel for the roll under the mouse, else the lowest roll; hides it when off or idle.
function ns.RollersPaint()
    if not ns.RollersOn() and not sample then
        if frame then frame:Hide() end
        return nil
    end
    if not frame then build() end
    hookFrames()
    local r, anchor, many
    if sample then
        r, anchor = sample, ns.RollAnchor and ns.RollAnchor()
    else
        local list = shownFrames()
        anchor = list[1]
        many = #list > 1
        local pick = list[1]
        for _, f in ipairs(list) do
            if f.IsMouseOver and f:IsMouseOver() == true then pick = f end
        end
        r = pick and rolls[pick.rollID]
        if pick and not r then r = ns.RollerStart(pick.rollID) end
    end
    if not (r and anchor) then frame:Hide(); return nil end
    local list, counts = ns.RollerRows(r)
    for c, h in pairs(heads) do h.text:SetText(tostring(counts[c] or 0)) end
    itemBox:SetShown(many and r.id ~= nil)
    if many and r.id then
        itemBox:SetIcon(C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(r.id) or nil)
    end
    local you = me()
    local n = math.min(#list, ns.ROLLERS_ROWS)
    for i, row in ipairs(rows) do
        local e = list[i]
        row:SetShown(e ~= nil and i <= n)
        if e then
            setIcon(row.choice, e.choice)
            classIcon(row.class, e.class)
            local label = (e.self or (you and e.name == short(you))) and L.YOU or e.name
            row.name:SetText(classHex(e.class) .. label .. "|r")
            local right = ""
            if e.roll then right = tostring(e.roll)
            elseif e.spec == "main" then right = L.SPEC_MAIN
            elseif e.spec == "off" then right = L.SPEC_OFF
            elseif e.choice == "wait" then right = L.ROLLERS_WAIT end
            row.right:SetText(right)
        end
    end
    local rest = #list - n
    more:SetText(rest > 0 and L.MORE:format(rest) or "")
    empty:SetShown(#list == 0)
    local h = HEAD_H + 8 + math.max(1, n) * ROW_H + (rest > 0 and 16 or 0)
    frame:SetHeight(h)
    S.ApplyScale(frame, (ns.db and ns.db.rollScale or 100) / 100)
    frame:ClearAllPoints()
    frame:SetPoint("TOP", anchor, "BOTTOM", 0, -6)
    if not frame:IsShown() then frame:Show() end
    return r, list, counts
end

-- Unlock mode: a sample under the roll frames' place while the switch is on.
function ns.MoveRollers(on)
    sample = (on and ns.db and ns.db.rollers) and sampleRoll() or nil
    ns.RollersPaint()
end

function ns.SetRollers(on)
    if not on then sample = nil end
    ns.RollersPaint()
end

---- Events -------------------------------------------------------------------------------------

local ev = CreateFrame("Frame")
for _, e in ipairs({ "START_LOOT_ROLL", "CANCEL_LOOT_ROLL", "CANCEL_ALL_LOOT_ROLLS", "CHAT_MSG_LOOT",
                     "LOOT_HISTORY_UPDATE_DROP" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, a1, a2)
    if not ns.RollersOn() then return end
    if event == "START_LOOT_ROLL" then
        ns.RollerStart(a1)
        local mine = me()
        if mine then note(rolls[a1], mine, "wait", nil, nil, nil, true) end
        if C_Timer and C_Timer.After then C_Timer.After(0, function() ns.RollersPaint() end)
        else ns.RollersPaint() end
    elseif event == "CANCEL_LOOT_ROLL" then
        ns.RollerEnd(a1)
        ns.RollersPaint()
    elseif event == "CANCEL_ALL_LOOT_ROLLS" then
        wipe(rolls)
        ns.RollersPaint()
    elseif event == "CHAT_MSG_LOOT" then
        ns.RollerChat(a1)
    elseif event == "LOOT_HISTORY_UPDATE_DROP" then
        ns.RollerHistory(a1, a2)
    end
end)
