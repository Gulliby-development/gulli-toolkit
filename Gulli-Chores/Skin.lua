-- The Gulli look (Gulli Hearth), shared by every Gulli addon: dense dark-brown windows in the
-- classic WoW palette (gold for names and titles, blue for what can be clicked, red for what
-- removes), soft 3 to 6 pixel corners, the game's Friz Quadrata for titles and Fira Sans for
-- text, and a scale that grows with the screen. Built from plain textures, so it needs no
-- template and no library. This file is the same in every addon folder: edit
-- Gulli-Toolkit/Skin.lua and run tools/skin/sync.sh (CI checks that the copies match).

local addon, ns = ...

local S = {}
ns.Skin = S

local WHITE = "Interface\\Buttons\\WHITE8X8"
-- Fonts by face: "body" (Fira Sans Medium), "bold" (Fira Sans Bold) and "title" (the game's
-- Friz Quadrata). Paths are explicit: STANDARD_TEXT_FONT is replaced by other UI addons. Fira
-- Sans (OFL 1.1, Media/Fonts) has Latin, Polish and Cyrillic; Korean and Chinese keep the
-- game's fonts. A font file the client cannot load falls back to the game's font.
local GAME_FONT = "Fonts\\FRIZQT__.TTF"
local GAME_CYR = "Fonts\\FRIZQT___CYR.TTF"
local FONT_DIR = "Interface\\AddOns\\" .. tostring(addon) .. "\\Media\\Fonts\\"
local FACES = {
    body = { roman = FONT_DIR .. "FiraSans-Medium.ttf", russian = FONT_DIR .. "FiraSans-Medium.ttf" },
    bold = { roman = FONT_DIR .. "FiraSans-Bold.ttf", russian = FONT_DIR .. "FiraSans-Bold.ttf" },
    title = { roman = GAME_FONT, russian = GAME_CYR },
}
local ALPHABETS = { "roman", "russian", "korean", "simplifiedchinese", "traditionalchinese" }
local OTHER = { korean = "Fonts\\2002.TTF", simplifiedchinese = "Fonts\\ARKai_T.ttf",
    traditionalchinese = "Fonts\\blei00d.TTF" }
local FALLBACK = { roman = GAME_FONT, russian = GAME_CYR }
-- The smallest text size of the look.
S.MIN_TEXT = 12

-- Whether the client loads a font file (SetFont answers false when it cannot).
local loads = {}
local function canLoad(file)
    if loads[file] == nil then
        loads[file] = true
        if CreateFrame then
            local ok, probe = pcall(function() return CreateFrame("Frame"):CreateFontString(nil, "OVERLAY") end)
            if ok and probe and probe.SetFont then
                local fine, answer = pcall(probe.SetFont, probe, file, 12, "")
                if not fine or answer == false then loads[file] = false end
            end
        end
    end
    return loads[file]
end
local function fileFor(face, alphabet)
    local f = (FACES[face] or FACES.body)[alphabet] or OTHER[alphabet]
    if f and not canLoad(f) then f = FALLBACK[alphabet] or GAME_FONT end
    return f or GAME_FONT
end
S.FontFile = fileFor

local families = {}
local function family(size, flags, face)
    if not CreateFontFamily then return nil end
    flags = flags or ""
    local key = "GulliHearth" .. face .. size .. flags:gsub("%W", "")
    if families[key] == nil then
        local f = _G[key]
        if not f then
            local members = {}
            for _, a in ipairs(ALPHABETS) do
                members[#members + 1] = { alphabet = a, file = fileFor(face, a), height = size, flags = flags }
            end
            local ok, made = pcall(CreateFontFamily, key, members)
            f = ok and made or false
        end
        families[key] = f
    end
    return families[key] or nil
end
-- S.SetFont(region, size, flags, face): face is "body" (the default), "bold" or "title". Text is
-- never smaller than S.MIN_TEXT, in whole units.
function S.SetFont(region, size, flags, face)
    size = math.max(S.MIN_TEXT, math.floor(size or 13))
    face = FACES[face] and face or "body"
    local f = family(size, flags, face)
    if f then region:SetFontObject(f) else region:SetFont(fileFor(face, "roman"), size, flags or "") end
end

-- Colours (Gulli Hearth). The window is the darkest warm brown, the module list and headers
-- darker still, cards and tiles a step lighter (no edge), buttons and chips lighter again.
-- Roles never mix: S.GOLD for names and titles only, the accent (S.Accent, S.FILL) for what can
-- be clicked or is chosen, S.BAD/S.Danger red for what removes or hurts, S.GOOD/S.WARN for state.
S.BG = { 0.090, 0.071, 0.055, 0.98 }
S.SIDE = { 0.063, 0.047, 0.035, 1 }
S.HEAD = S.SIDE
S.SURFACE = { 0.137, 0.106, 0.082, 1 }
S.SCRIM = { 0, 0, 0, 0 }
S.RAISED = { 0.180, 0.141, 0.106, 1 }
S.RAISED_HOVER = { 0.227, 0.180, 0.133, 1 }
-- Depth: cards, tiles and chips let the window's paper show through. "bevel" lights their top
-- like a WoW panel and fades them out downwards; "flat" is a faint light veil with a thin edge.
S.DEPTH = rawget(_G, "GULLI_DEPTH") or "flat"
if S.DEPTH == "flat" then
    S.SURFACE = { 1, 0.90, 0.75, 0.045 }
    S.RAISED = { 1, 0.90, 0.75, 0.075 }
    S.RAISED_HOVER = { 1, 0.90, 0.75, 0.12 }
elseif S.DEPTH == "bevel" then
    S.SURFACE = { 0.200, 0.153, 0.110, 0.50 }
    S.RAISED = { 0.247, 0.192, 0.141, 0.55 }
    S.RAISED_HOVER = { 0.310, 0.243, 0.176, 0.62 }
end
S.PRESSED = { 0.110, 0.086, 0.063, 1 }
S.INPUT = { 0.055, 0.043, 0.031, 1 }
S.EDGE = { 1, 0.925, 0.784, 0.16 }
S.LINE = { 1, 0.925, 0.784, 0.09 }
S.HOVER = { 1, 0.925, 0.784, 0.06 }
S.BORDER = { 0, 0, 0, 1 }
S.TEXT = { 0.957, 0.929, 0.886, 1 }
S.MUTED = { 0.769, 0.722, 0.651, 1 }
S.FAINT = { 0.612, 0.561, 0.486, 1 }
S.GOOD = { 0.404, 0.831, 0.486, 1 }
S.WARN = { 1, 0.624, 0.251, 1 }
S.BAD = { 1, 0.416, 0.361, 1 }
S.CLEAR = { 0, 0, 0, 0 }
-- The game's own gold (NORMAL_FONT_COLOR): names and titles. GOLD_DIM: section labels.
S.GOLD = { 1, 0.82, 0, 1 }
S.GOLD_DIM = { 0.788, 0.651, 0.275, 1 }
-- The accent fill: the main button, a switch that is on, the chosen row (at 0.34). A muted
-- bronze in tone with the brown, so what can be clicked stands out without shouting.
S.FILL = { 0.416, 0.318, 0.180, 1 }
S.FILL_EDGE = { 0.643, 0.514, 0.310, 1 }
S.DANGER_FILL = { 0.557, 0.133, 0.094, 1 }
S.DANGER_EDGE = { 0.851, 0.345, 0.298, 1 }
-- The thin dark gold ring around round icons, and the off state of a switch.
S.RING = { 0.561, 0.455, 0.125, 1 }
S.OFF = { 0.290, 0.239, 0.188, 1 }
S.OFF_KNOB = { 0.725, 0.671, 0.588, 1 }
-- Coin colours: money as coloured text, "28g 42s 5c", empty parts left out.
-- Silver is a cool blue-grey, so it does not read as plain text (S.TEXT).
S.SILVER = { 0.72, 0.82, 0.97, 1 }
S.COPPER = { 0.93, 0.65, 0.37, 1 }
-- The parts of a stat line ("12:30 · 3400 XP · 1g 20s · 25 kills"), each in its own colour:
-- time, experience (the XP bar's purple) and kills. Join the parts with S.DOT.
S.TIME = { 0.45, 0.85, 0.80, 1 }
S.XP = { 0.79, 0.63, 1.00, 1 }
S.KILLS = { 0.95, 0.55, 0.50, 1 }
S.DOT = "  |cff9c8f7c·|r  "
-- A window, a HUD panel or a notice: the dense brown of S.BG (the names stay from Gulli Glass,
-- so older calls keep working). A frame that must hide what is behind it uses S.SOLID.
S.GLASS = S.BG
S.HUD_GLASS = { 0.090, 0.071, 0.055, 0.96 }
S.GLASS_EDGE = S.EDGE
S.GLASS_HI = S.CLEAR
S.CARD_EDGE = S.DEPTH == "flat" and { 1, 0.90, 0.75, 0.10 } or S.CLEAR
S.SOLID = { 0.090, 0.071, 0.055, 1 }
-- The one gold line under a window's header.
S.HEAD_LINE = { 1, 0.82, 0, 0.28 }
-- Older names, still used by some windows.
S.PANEL = S.RAISED
S.ROW = { 1, 0.925, 0.784, 0.03 }

-- Spacing: 4, 8, 12, 16, 24. Window padding, gap between cards, padding inside a card.
S.PAD, S.GAP, S.INSET = 16, 12, 12
S.HEADER_H, S.FOOTER_H, S.ROW_H, S.ROW_DESC_H = 44, 56, 40, 56
-- Window sizes that fit the hub (/gulli): a narrow window takes the place of the module list and
-- leaves the module card beside it, a wide one takes both. No window is taller than DOCK_H.
S.NARROW_W, S.WIDE_W, S.DOCK_H = 540, 832, 624
-- Corner radii: small controls (check boxes), buttons and inputs, cards and tiles, windows.
S.R_SM, S.R_MD, S.R_LG, S.R_XL = 3, 4, 4, 6
-- The ring around round icons (the name stays from the blue glow of Gulli Glass).
S.GLOW = S.RING

-- The accent text: a light warm parchment for links and the chosen thing.
function S.Accent()
    return { 0.937, 0.808, 0.588, 1 }
end

-- Scale. At a small UI scale one unit is one pixel and text came out tiny, so windows and
-- notices grow with the screen: 1 on a 768 unit high screen, at most 1.6 times. A window also
-- takes the player's hub scale (-/+, GulliToolkitDB.scale) and always fits the screen.
local function screen()
    local w = UIParent and tonumber((UIParent:GetWidth())) or 1366
    local h = UIParent and tonumber((UIParent:GetHeight())) or 768
    if not w or w <= 0 then w = 1366 end
    if not h or h <= 0 then h = 768 end
    return w, h
end
function S.BaseScale()
    local _, h = screen()
    return math.max(1, math.min(1.6, h / 768))
end
function S.UIScale()
    local user = GulliToolkitDB and tonumber(GulliToolkitDB.scale) or 1
    return S.BaseScale() * math.max(0.7, math.min(1.3, user))
end
-- The scale for a window w by h units: S.UIScale(), made smaller when it would not fit.
function S.FitScale(w, h)
    local sw, sh = screen()
    w, h = tonumber(w) or 0, tonumber(h) or 0
    local k = S.UIScale()
    if w > 0 then k = math.min(k, sw * 0.96 / w) end
    if h > 0 then k = math.min(k, sh * 0.9 / h) end
    return k
end
-- Sets a frame's scale, never on a protected frame in combat (the game refuses it).
local scaled = setmetatable({}, { __mode = "k" })
local function canScale(f)
    if not (InCombatLockdown and InCombatLockdown()) then return true end
    return not (f.IsProtected and f:IsProtected())
end
function S.ApplyScale(f, k)
    if canScale(f) then f:SetScale(k) end
end
-- A window that stands alone gets S.FitScale on each show and when the screen changes.
local function scaleWindow(f)
    if f.docked then return end
    local own = rawget(f, "rescale")
    if own then return own(f) end
    S.ApplyScale(f, S.FitScale(f:GetWidth(), f:GetHeight()))
end
S.ScaleWindow = scaleWindow
do
    local ok, ev = pcall(CreateFrame, "Frame")
    if ok and ev and ev.RegisterEvent then
        pcall(ev.RegisterEvent, ev, "UI_SCALE_CHANGED")
        pcall(ev.RegisterEvent, ev, "DISPLAY_SIZE_CHANGED")
        ev:SetScript("OnEvent", function()
            for f in pairs(scaled) do
                if f.IsShown and f:IsShown() then scaleWindow(f) end
            end
        end)
    end
end
function S.TrackScale(f, fn)
    scaled[f] = true
    if fn then rawset(f, "rescale", fn) end
end

-- Capital letters for a label in every language of the addons: string.upper only knows A-Z,
-- so Cyrillic, the Latin-1 letters (e, a, o with accents) and the Polish ones are mapped here.
local UPPER = { ["\209\145"] = "\208\129", ["\196\133"] = "\196\132", ["\196\135"] = "\196\134",
    ["\196\153"] = "\196\152", ["\197\130"] = "\197\129", ["\197\132"] = "\197\131",
    ["\197\155"] = "\197\154", ["\197\186"] = "\197\185", ["\197\188"] = "\197\187" }
for b = 176, 191 do UPPER["\208" .. string.char(b)] = "\208" .. string.char(b - 32) end -- а..п
for b = 128, 143 do UPPER["\209" .. string.char(b)] = "\208" .. string.char(b + 32) end -- р..я
for b = 160, 190 do if b ~= 183 then UPPER["\195" .. string.char(b)] = "\195" .. string.char(b - 32) end end
local function upperPlain(text)
    text = text:upper()
    return (text:gsub("[\195-\209][\128-\191]", function(c) return UPPER[c] end))
end
-- Colour codes (|cff..., |r), links (|H...|h) and textures (|T...|t) keep their case.
function S.Upper(text)
    if text == nil then return nil end
    text = tostring(text)
    if not text:find("|", 1, true) then return upperPlain(text) end
    local out, i, n = {}, 1, #text
    while i <= n do
        local a = text:find("|", i, true)
        if not a then out[#out + 1] = upperPlain(text:sub(i)); break end
        out[#out + 1] = upperPlain(text:sub(i, a - 1))
        local k = text:sub(a + 1, a + 1)
        local stop = a + 1
        if k == "c" then stop = a + 9
        elseif k == "H" then stop = (text:find("|h", a + 2, true) or n) + 1
        elseif k == "T" or k == "A" then stop = (text:find("|" .. k:lower(), a + 2, true) or n) + 1 end
        out[#out + 1] = text:sub(a, stop)
        i = stop + 1
    end
    return table.concat(out)
end

function S.Hex(c)
    return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255)
end

-- The numbers of a muted line in white, so the key figure reads first: "Level |cffffffff24|r
-- in 1 h". Colour codes (|c..|r), links (|H..|h) and textures (|T..|t) stay as they are, and
-- digits are only coloured in plain text outside a colour code.
function S.Emph(text, color)
    if text == nil then return nil end
    text = tostring(text)
    local open = color and S.Hex(color) or "|cffffffff"
    local out, i, n, depth = {}, 1, #text, 0
    local function plain(s)
        if depth > 0 then return s end
        return (s:gsub("%d[%d.,:]*", function(d) return open .. d .. "|r" end))
    end
    while i <= n do
        local a = text:find("|", i, true)
        if not a then out[#out + 1] = plain(text:sub(i)); break end
        out[#out + 1] = plain(text:sub(i, a - 1))
        local k = text:sub(a + 1, a + 1)
        local stop
        if k == "c" then stop = a + 9; depth = depth + 1
        elseif k == "r" then stop = a + 1; depth = math.max(0, depth - 1)
        elseif k == "H" then stop = (text:find("|h", a + 2, true) or n) + 1
        elseif k == "h" then stop = a + 1
        elseif k == "T" or k == "A" then stop = (text:find("|" .. k:lower(), a + 2, true) or n) + 1
        else stop = a + 1 end
        out[#out + 1] = text:sub(a, stop)
        i = stop + 1
    end
    return table.concat(out)
end

-- The width of a text, or 0 where the game cannot tell yet.
local function strw(fs) return tonumber((fs:GetStringWidth())) or 0 end

local function tex(f, layer, sub, color)
    local t = f:CreateTexture(nil, layer, nil, sub)
    t:SetTexture(WHITE)
    t:SetVertexColor(color[1], color[2], color[3], color[4])
    return t
end
S.Tex = tex

-- Round shapes are white textures from the addon's Media folder, tinted: Round is a disc, Glow
-- a soft halo, Ring<R> the 1 pixel border of a corner of radius R (tools/skin/media.py draws
-- them; RADII lists the ones there are).
local MEDIA = "Interface\\AddOns\\" .. tostring(addon) .. "\\Media\\"
S.ROUND, S.ROUND_SQ, S.GLOW_TEX = MEDIA .. "Round", MEDIA .. "RoundSq", MEDIA .. "Glow"
S.SHEEN, S.RADIAL = MEDIA .. "Sheen", MEDIA .. "Radial"
local RADII = { 2, 3, 4, 6, 8, 9, 10, 11, 14 }
local QUAD = { TOPLEFT = { 0, 0.5, 0, 0.5 }, TOPRIGHT = { 0.5, 1, 0, 0.5 },
               BOTTOMLEFT = { 0, 0.5, 0.5, 1 }, BOTTOMRIGHT = { 0.5, 1, 0.5, 1 } }
local CORNERS = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
local WHICH = { top = { TOPLEFT = true, TOPRIGHT = true }, bottom = { BOTTOMLEFT = true, BOTTOMRIGHT = true },
    bottomleft = { BOTTOMLEFT = true } }

-- The largest radius there is a ring for, at most r.
local function ringRadius(r)
    local best = 0
    for _, x in ipairs(RADII) do if x <= r then best = x end end
    return best
end

-- One corner piece of size r, i pixels in from the corner (out when i < 0): a quarter of
-- `file`, or a plain square for a corner that stays sharp.
local function corner(f, layer, sub, color, point, r, i, file)
    local t = f:CreateTexture(nil, layer, nil, sub)
    if file then
        t:SetTexture(file)
        local q = QUAD[point]
        t:SetTexCoord(q[1], q[2], q[3], q[4])
    else
        t:SetTexture(WHITE)
    end
    t:SetVertexColor(color[1], color[2], color[3], color[4])
    t:SetSize(r, r)
    t:SetPoint(point, point:find("LEFT") and i or -i, point:find("TOP") and -i or i)
    return t
end

-- A filled shape with corners of radius r, i pixels in from the frame's edges: three bands and
-- four corners that never overlap, so a see-through colour stays even. Returns the textures.
local function roundRect(f, layer, sub, color, r, i, round)
    local list = {}
    local function band(a, ax, ay, b, rel, bx, by)
        local t = tex(f, layer, sub, color)
        t:SetPoint(a, ax, ay)
        t:SetPoint(b, f, rel, bx, by)
        list[#list + 1] = t
    end
    local k = i + r
    band("TOPLEFT", i, -k, "BOTTOMRIGHT", "BOTTOMRIGHT", -i, k)
    band("TOPLEFT", k, -i, "BOTTOMRIGHT", "TOPRIGHT", -k, -k)
    band("BOTTOMLEFT", k, i, "TOPRIGHT", "BOTTOMRIGHT", -k, k)
    for _, p in ipairs(CORNERS) do
        list[#list + 1] = corner(f, layer, sub, color, p, r, i, round[p] and S.ROUND or nil)
    end
    return list
end

-- A filled rectangle with a 1 pixel border around it. radius (optional) rounds its corners;
-- corners = "top" or "bottom" rounds only those two, "bottomleft" only that one. f.fills and f.edges are its textures.
function S.Box(f, bg, border, radius, corners)
    local b = border or S.BORDER
    radius = ringRadius(math.floor(radius or 0))
    f.edges, f.radius = {}, radius
    if radius < 2 then
        f.bg = tex(f, "BACKGROUND", -7, bg or S.BG)
        f.bg:SetAllPoints()
        f.fills = { f.bg }
        for i, p in ipairs({ { "TOPLEFT", "TOPRIGHT", 0, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 0, 1 },
                             { "TOPLEFT", "BOTTOMLEFT", 1, 0 }, { "TOPRIGHT", "BOTTOMRIGHT", 1, 0 } }) do
            local e = tex(f, "BORDER", 7, b)
            e:SetPoint(p[1])
            e:SetPoint(p[2])
            if p[3] == 1 then e:SetWidth(1) else e:SetHeight(1) end
            f.edges[i] = e
        end
        return f
    end
    local round = WHICH[corners or ""] or { TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }
    -- The fill sits inside the border; its corners are discs of radius - 1, the ring takes the rest.
    f.fills = roundRect(f, "BACKGROUND", -7, bg or S.BG, radius - 1, 1, round)
    f.bg = f.fills[1]
    local r = radius
    for i, p in ipairs({ { "TOPLEFT", r, 0, "TOPRIGHT", -r, 0, "h" }, { "BOTTOMLEFT", r, 0, "BOTTOMRIGHT", -r, 0, "h" },
                         { "TOPLEFT", 0, -r, "BOTTOMLEFT", 0, r, "v" }, { "TOPRIGHT", 0, -r, "BOTTOMRIGHT", 0, r, "v" } }) do
        local e = tex(f, "BORDER", 7, b)
        e:SetPoint(p[1], p[2], p[3])
        e:SetPoint(p[4], p[5], p[6])
        if p[7] == "v" then e:SetWidth(1) else e:SetHeight(1) end
        f.edges[i] = e
    end
    for _, p in ipairs(CORNERS) do
        if round[p] then
            f.edges[#f.edges + 1] = corner(f, "BORDER", 7, b, p, r, 0, MEDIA .. "Ring" .. r)
        else
            -- A sharp corner: the two edges run on to the corner.
            local e1 = tex(f, "BORDER", 7, b)
            e1:SetSize(r, 1)
            e1:SetPoint(p, 0, 0)
            local e2 = tex(f, "BORDER", 7, b)
            e2:SetSize(1, r)
            e2:SetPoint(p, 0, 0)
            f.edges[#f.edges + 1] = e1
            f.edges[#f.edges + 1] = e2
        end
    end
    return f
end

function S.SetBorder(f, c)
    for _, e in ipairs(f.edges) do e:SetVertexColor(c[1], c[2], c[3], c[4]) end
end

function S.Fill(f, c)
    for _, t in ipairs(f.fills or { f.bg }) do t:SetVertexColor(c[1], c[2], c[3], c[4]) end
end

-- A soft shadow around a box with corners of radius r (0 = square): n rings that fade out.
function S.Shadow(f, r, n, strength)
    local list = {}
    local all = { TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }
    for i = 1, n or 4 do
        local a = (strength or 0.16) - i * ((strength or 0.16) / ((n or 4) + 1))
        for _, t in ipairs(roundRect(f, "BACKGROUND", -8, { 0, 0, 0, a }, (r or 0) + i, -i, r and r > 0 and all or {})) do
            list[#list + 1] = t
        end
    end
    return list
end

-- Glass ---------------------------------------------------------------------------------------

-- The paper of Gulli Hearth: a faint warm grain over a window, card, tile or HUD panel
-- (Media/Grain, drawn by tools/skin/hearth_art.py), kept clear of the rounded corners. The name
-- stays from Gulli Glass, so every older call draws it.
S.GRAIN = MEDIA .. "Grain"
S.GRAIN_ALPHA = 0.07
function S.Glass(f, r)
    local g = {}
    local t = f:CreateTexture(nil, "BACKGROUND", nil, -6)
    t:SetTexture(S.GRAIN, "REPEAT", "REPEAT")
    if t.SetHorizTile then t:SetHorizTile(true); t:SetVertTile(true) end
    local i = math.max(1, tonumber(r) or 0)
    t:SetPoint("TOPLEFT", i, -i)
    t:SetPoint("BOTTOMRIGHT", -i, i)
    t:SetVertexColor(1, 0.86, 0.66, S.GRAIN_ALPHA)
    g[1] = t
    rawset(f, "glass", g)
    return g
end

-- The relief of a card, tile or chip with corners of radius r (S.DEPTH): with "bevel" a sheen
-- from the top, a light line along the top and a dark one along the bottom, kept clear of the
-- corners; with "flat" only the thin edge (S.CARD_EDGE). f.depth holds the textures.
function S.Depth(f, r)
    r = math.max(1, tonumber(r) or 0)
    local d = {}
    if S.DEPTH == "flat" then
        if f.edges then S.SetBorder(f, S.CARD_EDGE) end
    elseif S.DEPTH == "bevel" then
        local sh = f:CreateTexture(nil, "BACKGROUND", nil, -5)
        sh:SetTexture(S.SHEEN)
        sh:SetPoint("TOPLEFT", 1, -1)
        sh:SetPoint("BOTTOMRIGHT", -1, 1)
        sh:SetVertexColor(1, 0.86, 0.62, 0.10)
        d[1] = sh
        local hi = tex(f, "BORDER", 6, { 1, 0.90, 0.72, 0.16 })
        hi:SetPoint("TOPLEFT", r, -1)
        hi:SetPoint("TOPRIGHT", -r, -1)
        hi:SetHeight(1)
        d[2] = hi
        local lo = tex(f, "BORDER", 6, { 0, 0, 0, 0.40 })
        lo:SetPoint("BOTTOMLEFT", r, 1)
        lo:SetPoint("BOTTOMRIGHT", -r, 1)
        lo:SetHeight(1)
        d[3] = lo
    end
    rawset(f, "depth", d)
    return d
end

-- A window header of its own: darker than the body, a warm bronze light from the left and a
-- sheen from the top, so it reads as a band of leather and not as a black bar.
function S.HeadArt(bar, r)
    local g = {}
    local glow = bar:CreateTexture(nil, "BACKGROUND", nil, -5)
    glow:SetTexture(S.RADIAL)
    glow:SetPoint("TOPLEFT", 1, -1)
    glow:SetPoint("BOTTOMRIGHT", bar, "BOTTOM", 0, 1)
    glow:SetVertexColor(0.78, 0.55, 0.26, 0.20)
    g[1] = glow
    local grain = bar:CreateTexture(nil, "BACKGROUND", nil, -6)
    grain:SetTexture(S.GRAIN, "REPEAT", "REPEAT")
    if grain.SetHorizTile then grain:SetHorizTile(true); grain:SetVertTile(true) end
    grain:SetPoint("TOPLEFT", r or 1, -1)
    grain:SetPoint("BOTTOMRIGHT", -(r or 1), 1)
    grain:SetVertexColor(1, 0.86, 0.66, 0.12)
    g[2] = grain
    local sh = bar:CreateTexture(nil, "BACKGROUND", nil, -4)
    sh:SetTexture(S.SHEEN)
    sh:SetPoint("TOPLEFT", r or 1, -1)
    sh:SetPoint("BOTTOMRIGHT", -(r or 1), 1)
    sh:SetVertexColor(1, 0.86, 0.62, 0.06)
    g[3] = sh
    rawset(bar, "glass", g)
    return g
end

function S.ShowGlass(f, on)
    for _, t in ipairs(rawget(f, "glass") or {}) do t:SetShown(on and true or false) end
end

-- Motion ------------------------------------------------------------------------------------

-- Every move is short (S.FAST 120 ms, S.BASE 180, S.SLOW 240) and slows down at its end.
-- "Reduce motion" in the hub (GulliToolkitDB.calm) stops them all: things then only appear.
-- Nothing animates in combat, so a protected frame never moves or hides there.
S.FAST, S.BASE, S.SLOW = 0.12, 0.18, 0.24
function S.Calm()
    if GulliToolkitDB and GulliToolkitDB.calm then return true end
    return InCombatLockdown and InCombatLockdown() and true or false
end

-- An animation group on a frame or texture, or nil where the client (or a test) has none.
local function group(r)
    if not r or type(r.CreateAnimationGroup) ~= "function" then return nil end
    local ok, g = pcall(r.CreateAnimationGroup, r)
    if ok and type(g) == "table" and type(g.CreateAnimation) == "function" then return g end
end

local function step(g, kind, order, dur, smooth)
    local a = g:CreateAnimation(kind)
    if not a then return nil end
    if a.SetOrder then a:SetOrder(order) end
    if a.SetDuration then a:SetDuration(dur) end
    if smooth and a.SetSmoothing then a:SetSmoothing(smooth) end
    return a
end

local function scaleFrom(a, from)
    if not a then return end
    if a.SetScaleFrom then a:SetScaleFrom(from, from); a:SetScaleTo(1, 1)
    elseif a.SetFromScale then a:SetFromScale(from, from); a:SetToScale(1, 1) end
end

-- Plays one cached group of r, made by build(g) the first time; stops it first.
local function play(r, key, build, onDone)
    local cache = rawget(r, "gulliMotion")
    if type(cache) ~= "table" then cache = {}; rawset(r, "gulliMotion", cache) end
    local g = cache[key]
    if g == nil then
        g = group(r) or false
        if g then
            build(g)
            g:SetScript("OnFinished", function(self) if self.done then local d = self.done; self.done = nil; d() end end)
        end
        cache[key] = g
    end
    if not g then if onDone then onDone() end return false end
    if g.IsPlaying and g:IsPlaying() then g:Stop() end
    g.done = onDone
    g:Play()
    return true
end

-- r appears: it fades in while it moves dy pixels up into place (dy < 0: down into place) and,
-- with scale, grows from that size. Calm: shows at once.
function S.MotionIn(r, dy, dur, scale, delay)
    if S.Calm() then return end
    local key = "in" .. tostring(dy or 0) .. tostring(scale or 1) .. tostring(delay or 0)
    play(r, key, function(g)
        local wait = (delay or 0) > 0 and step(g, "Alpha", 1, delay) or nil
        if wait and wait.SetFromAlpha then wait:SetFromAlpha(0); wait:SetToAlpha(0) end
        if dy and dy ~= 0 then
            local back = step(g, "Translation", 1, 0.001)
            if back then back:SetOffset(0, -dy) end
            local go = step(g, "Translation", 2, dur or S.BASE, "OUT")
            if go then go:SetOffset(0, dy) end
        end
        local fade = step(g, "Alpha", 2, dur or S.BASE, "OUT")
        if fade and fade.SetFromAlpha then fade:SetFromAlpha(0); fade:SetToAlpha(1) end
        if scale then scaleFrom(step(g, "Scale", 2, dur or S.BASE, "OUT"), scale) end
    end)
end

-- r fades out (and shrinks a little), then done() runs; calm: done() at once.
function S.MotionOut(r, done, dur)
    if S.Calm() then if done then done() end return end
    play(r, "out", function(g)
        local fade = step(g, "Alpha", 1, dur or 0.14, "IN")
        if fade and fade.SetFromAlpha then fade:SetFromAlpha(1); fade:SetToAlpha(0) end
        scaleFrom(step(g, "Scale", 1, dur or 0.14, "IN"), 1)
        if g.SetToFinalAlpha then g:SetToFinalAlpha(false) end
    end, done)
end

-- r was moved dx, dy pixels (its new place is already set): it slides there from the old one.
function S.MotionSlide(r, dx, dy, dur)
    if S.Calm() or ((dx or 0) == 0 and (dy or 0) == 0) then return end
    local key = "slide" .. tostring(dx) .. "," .. tostring(dy)
    play(r, key, function(g)
        local back = step(g, "Translation", 1, 0.001)
        if back then back:SetOffset(-(dx or 0), -(dy or 0)) end
        local go = step(g, "Translation", 2, dur or S.BASE, "OUT")
        if go then go:SetOffset(dx or 0, dy or 0) end
    end)
end

-- r grows from `from` to its size (a tick, a new icon).
function S.MotionPop(r, from, dur)
    if S.Calm() then return end
    play(r, "pop" .. tostring(from), function(g)
        scaleFrom(step(g, "Scale", 1, dur or S.BASE, "OUT"), from or 0.6)
        local fade = step(g, "Alpha", 1, dur or S.BASE, "OUT")
        if fade and fade.SetFromAlpha then fade:SetFromAlpha(0.2); fade:SetToAlpha(1) end
    end)
end

-- Gulli Glass ran one pass of light over a window as it opened; Gulli Hearth does not.
local function sweep() end
S.Sweep = sweep

-- A value that moves to its target over dur seconds: S.Tween(owner, key, from, to, dur, apply).
-- apply(v) runs each frame; calm or without OnUpdate it runs once with the target.
function S.Tween(owner, key, from, to, dur, apply)
    if S.Calm() or not from or from == to or not CreateFrame then apply(to) return end
    local list = rawget(owner, "gulliTweens")
    if type(list) ~= "table" then list = {}; rawset(owner, "gulliTweens", list) end
    local d = list[key]
    if not d then
        d = CreateFrame("Frame", nil, owner)
        rawset(d, "gulliTween", true)
        list[key] = d
    end
    local t = 0
    d:SetScript("OnUpdate", function(self, dt)
        t = t + (dt or 1)
        local x = math.min(1, t / (dur or 0.4))
        local e = 1 - (1 - x) * (1 - x) * (1 - x)
        apply(from + (to - from) * e)
        if x >= 1 then self:SetScript("OnUpdate", nil) end
    end)
end

-- S.Text(parent, size, color, flags, face): face as in S.SetFont ("body", "bold", "title").
function S.Text(parent, size, color, flags, face)
    local t = parent:CreateFontString(nil, "OVERLAY")
    S.SetFont(t, size or 13, flags, face)
    t:SetShadowOffset(1, -1)
    t:SetShadowColor(0, 0, 0, 1)
    local c = color or S.TEXT
    t:SetTextColor(c[1], c[2], c[3], c[4])
    t:SetJustifyH("LEFT")
    return t
end

-- A muted line of text; anchor it on both sides and it wraps.
function S.Note(parent, size)
    local t = S.Text(parent, size or 12, S.MUTED)
    t:SetJustifyV("TOP")
    return t
end

-- A grey paragraph of a known width; returns it and its height, for S.Stack.
function S.Paragraph(parent, text, width, size)
    local t = S.Note(parent, size or 12)
    t:SetWidth(width)
    t:SetText(text or "")
    return t, math.ceil(tonumber(t:GetStringHeight()) or 14)
end

-- A thin line across its parent, for separating rows.
function S.Divider(parent, color)
    return tex(parent, "BORDER", 0, color or S.LINE)
end

-- A short "Gulli Merchant" becomes "Merchant": the icon already says it is ours.
local function shortTitle(title)
    title = tostring(title or "")
    return (title:gsub("^Gulli[%s%-]+", ""))
end

-- Buttons ------------------------------------------------------------------------------------

local function paint(b)
    local hover = b.hover and b:IsEnabled()
    if (b.kind == "primary" or b.kind == "danger") and not b:IsEnabled() then
        -- a main action that cannot run now looks like a plain dim button, not a lit one
        S.Fill(b, S.RAISED)
        S.SetBorder(b, S.LINE)
        b.text:SetTextColor(S.MUTED[1], S.MUTED[2], S.MUTED[3], 1)
    elseif b.kind == "primary" or b.kind == "danger" then
        local c = b.kind == "danger" and S.DANGER_FILL or S.FILL
        local e = b.kind == "danger" and S.DANGER_EDGE or S.FILL_EDGE
        local k = hover and 1.18 or 1
        S.Fill(b, { math.min(1, c[1] * k), math.min(1, c[2] * k), math.min(1, c[3] * k), 1 })
        S.SetBorder(b, e)
        b.text:SetTextColor(1, 1, 1, 1)
        b.text:SetShadowColor(0, 0, 0, 1)
    elseif b.kind == "ghost" then
        S.Fill(b, hover and S.HOVER or S.CLEAR)
        S.SetBorder(b, S.CLEAR)
    else
        S.Fill(b, hover and S.RAISED_HOVER or S.RAISED)
        S.SetBorder(b, hover and S.EDGE or S.LINE)
    end
end

-- A flat button: the edge lights up in the accent colour under the cursor.
function S.Button(parent, width, height)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 110, height or 30)
    S.Box(b, S.RAISED, S.LINE, S.R_MD)
    -- Gulli Glass had a light along the top of a button; b.hi stays for older code, hidden.
    b.hi = tex(b, "BORDER", 6, S.CLEAR)
    b.hi:SetPoint("TOPLEFT", S.R_MD, -1)
    b.hi:SetPoint("TOPRIGHT", -S.R_MD, -1)
    b.hi:SetHeight(1)
    b.hi:Hide()
    b.text = S.Text(b, 13)
    b.text:SetPoint("LEFT", 6, 0)
    b.text:SetPoint("RIGHT", -6, 0)
    b.text:SetJustifyH("CENTER")
    b.text:SetWordWrap(false)
    b.kind = "normal"
    b.SetText = function(self, s) self.text:SetText(s) end
    b.GetText = function(self) return self.text:GetText() end
    b:SetScript("OnEnter", function(self) self.hover = true; paint(self) end)
    b:SetScript("OnLeave", function(self) self.hover = false; paint(self) end)
    b:SetScript("OnDisable", function(self) self.text:SetAlpha(0.4); paint(self) end)
    b:SetScript("OnEnable", function(self) self.text:SetAlpha(1); paint(self) end)
    -- A press shrinks it a little.
    b:HookScript("OnMouseDown", function(self)
        if self:IsEnabled() and not S.Calm() then
            play(self, "press", function(g)
                local a = step(g, "Scale", 1, 0.08, "OUT")
                if a then
                    if a.SetScaleFrom then a:SetScaleFrom(1, 1); a:SetScaleTo(0.97, 0.97)
                    elseif a.SetFromScale then a:SetFromScale(1, 1); a:SetToScale(0.97, 0.97) end
                end
                local back = step(g, "Scale", 2, 0.08, "IN")
                if back then
                    if back.SetScaleFrom then back:SetScaleFrom(0.97, 0.97); back:SetScaleTo(1, 1)
                    elseif back.SetFromScale then back:SetFromScale(0.97, 0.97); back:SetToScale(1, 1) end
                end
            end)
        end
    end)
    return b
end

-- Tab icons with one meaning in every module (pass them as the icons of S.Tabs).
local TI = "Interface\\Icons\\"
S.TAB = {
    settings = TI .. "Trade_Engineering", rules = TI .. "INV_Scroll_05", recent = TI .. "INV_Misc_PocketWatch_01",
    list = TI .. "INV_Scroll_02", group = TI .. "INV_Misc_GroupNeedMore", char = TI .. "INV_Misc_Head_Human_01",
    overview = TI .. "INV_Misc_Spyglass_02", quests = TI .. "INV_Scroll_03", items = TI .. "INV_Misc_Bag_10",
    search = TI .. "INV_Misc_Spyglass_03", mail = TI .. "INV_Letter_15", write = TI .. "INV_Letter_01",
    vendor = TI .. "INV_Misc_Coin_01", chat = TI .. "INV_Letter_02", more = TI .. "INV_Misc_Note_05",
}

-- Group roles, in every module that names one.
S.ROLE_ICON = { TANK = TI .. "Ability_Warrior_DefensiveStance", HEALER = TI .. "Spell_Holy_FlashHeal",
                DPS = TI .. "INV_Sword_04" }

-- A game icon inside a line of text (|T...|t), cropped like the icon boxes.
function S.IconTag(path, size)
    size = size or 14
    return "|T" .. path .. ":" .. size .. ":" .. size .. ":0:0:64:64:5:59:5:59|t"
end

-- A small game icon on the left of a button or tab, before its text (nil removes it). Only for
-- tabs, filters and pick-one choices (a kind, a role, a roll); main actions stay text.
function S.SetButtonIcon(b, path, size)
    size = size or 16
    if not rawget(b, "btnIcon") then
        b.btnIcon = b:CreateTexture(nil, "ARTWORK")
        b.btnIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        S.RoundMask(b, b.btnIcon)
    end
    b.btnIcon:SetSize(size, size)
    b.btnIcon:ClearAllPoints()
    b.btnIcon:SetPoint("LEFT", 7, 0)
    b.btnIcon:SetTexture(path)
    b.btnIcon:SetShown(path ~= nil)
    b.text:ClearAllPoints()
    b.text:SetPoint("LEFT", path and size + 11 or 6, 0)
    b.text:SetPoint("RIGHT", -6, 0)
    return b
end

-- A choice with a game icon: the icon (with a count in its corner) on the left, a title and a
-- muted line under it; `vertical` puts the icon on top and the title under it (no line).
-- tile:Set{ icon, title, sub, count, quality }; SetEnabled greys it out.
function S.IconTile(parent, width, height, vertical)
    height = height or (vertical and 54 or 36)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 110, height)
    S.Box(b, S.RAISED, S.EDGE, S.R_MD)
    b.kind = "normal"
    b.title = S.Text(b, 12)
    b.title:SetWordWrap(false)
    b.sub = S.Text(b, 12, S.MUTED)
    b.sub:SetWordWrap(false)
    if vertical then
        b.item = S.ItemIcon(b, height - 24)
        b.item:SetPoint("TOP", 0, -4)
        b.title:SetPoint("BOTTOMLEFT", 3, 4)
        b.title:SetPoint("BOTTOMRIGHT", -3, 4)
        b.title:SetJustifyH("CENTER")
        b.sub:Hide()
    else
        b.item = S.ItemIcon(b, height - 8)
        b.item:SetPoint("LEFT", 4, 0)
        b.title:SetPoint("TOPLEFT", b.item, "TOPRIGHT", 5, -1)
        b.title:SetPoint("RIGHT", -4, 0)
        b.title:SetJustifyH("LEFT")
        b.sub:SetPoint("BOTTOMLEFT", b.item, "BOTTOMRIGHT", 5, 1)
        b.sub:SetPoint("RIGHT", -4, 0)
        b.sub:SetJustifyH("LEFT")
    end
    b.text = b.title
    function b:Set(o)
        self.item:Set(o.icon, o.count, o.quality)
        self.item.count:SetText(o.count and o.count > 0 and tostring(o.count) or "")
        self.title:SetText(o.title or "")
        self.sub:SetText(o.sub or "")
    end
    b.SetText = function(self, s) self.title:SetText(s) end
    b.GetText = function(self) return self.title:GetText() end
    local function dim(self, a) self.item:SetAlpha(a); self.title:SetAlpha(a); self.sub:SetAlpha(a) end
    b:SetScript("OnEnter", function(self) self.hover = true; paint(self) end)
    b:SetScript("OnLeave", function(self) self.hover = false; paint(self) end)
    b:SetScript("OnDisable", function(self) dim(self, 0.4); paint(self) end)
    b:SetScript("OnEnable", function(self) dim(self, 1); paint(self) end)
    return b
end

-- The one main action of a view: filled with the accent colour.
function S.Primary(b)
    b.kind = "primary"
    paint(b)
    return b
end

-- An action that removes something for good: filled red.
function S.Danger(b)
    b.kind = "danger"
    paint(b)
    return b
end

-- A button without a box, for small actions inside a row.
function S.Ghost(b)
    b.kind = "ghost"
    if b.hi then b.hi:Hide() end
    b.text:SetTextColor(S.MUTED[1], S.MUTED[2], S.MUTED[3], 1)
    paint(b)
    return b
end

-- A button that fits its text: S.Button with the width of the label plus padding.
function S.FitButton(parent, text, height, minWidth)
    local b = S.Button(parent, 10, height or 30)
    b:SetText(text)
    b:SetWidth(math.max(minWidth or 72, math.floor(strw(b.text) + 28)))
    return b
end

-- A round close button with an X drawn from two lines.
local function closeButton(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(28, 28)
    S.Box(b, S.CLEAR, S.CLEAR, 14)
    local lines = {}
    for i, d in ipairs({ { "TOPLEFT", 9, -9, "BOTTOMRIGHT", -9, 9 }, { "BOTTOMLEFT", 9, 9, "TOPRIGHT", -9, -9 } }) do
        local l = b:CreateLine(nil, "ARTWORK")
        l:SetThickness(1.5)
        l:SetColorTexture(S.MUTED[1], S.MUTED[2], S.MUTED[3], 1)
        l:SetStartPoint(d[1], b, d[2], d[3])
        l:SetEndPoint(d[4], b, d[5], d[6])
        lines[i] = l
    end
    local function color(c) for _, l in ipairs(lines) do l:SetColorTexture(c[1], c[2], c[3], 1) end end
    b:SetScript("OnEnter", function(self) S.Fill(self, { S.BAD[1], S.BAD[2], S.BAD[3], 0.25 }); color(S.TEXT) end)
    b:SetScript("OnLeave", function(self) S.Fill(self, S.CLEAR); color(S.MUTED) end)
    b:SetScript("OnClick", onClick)
    return b
end
S.Close = closeButton

-- Inputs -------------------------------------------------------------------------------------

-- A flat check box: a dark rounded square that fills with the accent colour and shows a tick
-- when ticked. It is 26 pixels so it is easy to hit by touch. state: true, false or "some"
-- (part of a group: a dash instead of the tick).
function S.Check(parent, size)
    local c = CreateFrame("Button", nil, parent)
    size = size or 26
    c:SetSize(size, size)
    local box = CreateFrame("Frame", nil, c)
    box:SetSize(16, 16)
    box:SetPoint("CENTER")
    S.Box(box, S.INPUT, S.EDGE, S.R_SM)
    c.box = box
    local ink = { 1, 1, 1, 1 }
    local function line(x1, y1, x2, y2)
        local l = box:CreateLine(nil, "OVERLAY")
        l:SetThickness(2)
        l:SetColorTexture(ink[1], ink[2], ink[3], 1)
        l:SetStartPoint("TOPLEFT", box, x1, y1)
        l:SetEndPoint("TOPLEFT", box, x2, y2)
        return l
    end
    c.tick = { line(3.5, -8, 6.5, -11), line(6.5, -11, 12.5, -4.5) }
    c.dash = line(4, -8, 12, -8)
    c.state = false
    function c:SetChecked(state)
        -- A tick the player sets (the cursor is on it) springs in.
        if state == true and self.state ~= true and self.IsMouseOver and self:IsMouseOver() then
            S.MotionPop(self.box, 0.7)
        end
        self.state = state
        local on = state and true or false
        S.Fill(self.box, on and S.FILL or S.INPUT)
        S.SetBorder(self.box, on and S.FILL_EDGE or S.EDGE)
        for _, l in ipairs(self.tick) do l:SetShown(state == true) end
        self.dash:SetShown(state == "some")
    end
    function c:GetChecked() return self.state == true end
    c:SetScript("OnEnter", function(self) S.SetBorder(self.box, S.Accent()) end)
    c:SetScript("OnLeave", function(self) S.SetBorder(self.box, self.state and S.FILL_EDGE or S.EDGE) end)
    c:SetChecked(false)
    return c
end

-- An on/off switch like a phone's: a pill that fills with the accent colour and a round knob
-- with a soft shadow that slides over. The button is 44 by 28 so it is easy to hit by touch.
function S.Switch(parent)
    local s = CreateFrame("Button", nil, parent)
    s:SetSize(44, 28)
    local track = CreateFrame("Frame", nil, s)
    track:SetSize(38, 22)
    track:SetPoint("CENTER")
    S.Box(track, S.OFF, S.CLEAR, 11)
    s.track = track
    s.shade = track:CreateTexture(nil, "ARTWORK", nil, 0)
    s.shade:SetTexture(S.GLOW_TEX)
    s.shade:SetVertexColor(0, 0, 0, 0.55)
    s.shade:SetSize(26, 26)
    s.knob = track:CreateTexture(nil, "ARTWORK", nil, 1)
    s.knob:SetTexture(S.ROUND)
    s.knob:SetSize(18, 18)
    s.shade:SetPoint("CENTER", s.knob, "CENTER", 0, -1)
    local function edge(self)
        if self.on then S.SetBorder(self.track, S.FILL_EDGE)
        else S.SetBorder(self.track, self.hover and S.Accent() or S.CLEAR) end
    end
    function s:SetChecked(on)
        local was = rawget(self, "on")
        self.on = on and true or false
        self.knob:ClearAllPoints()
        if self.on then
            self.knob:SetPoint("RIGHT", -2, 0)
            self.knob:SetVertexColor(1, 1, 1, 1)
            S.Fill(self.track, S.FILL)
        else
            self.knob:SetPoint("LEFT", 2, 0)
            self.knob:SetVertexColor(S.OFF_KNOB[1], S.OFF_KNOB[2], S.OFF_KNOB[3], 1)
            S.Fill(self.track, S.OFF)
        end
        edge(self)
        -- A change the player can see slides the knob over (16 pixels).
        if was ~= nil and was ~= self.on and self:IsVisible() then
            local dx = self.on and 16 or -16
            S.MotionSlide(self.knob, dx, 0)
            S.MotionSlide(self.shade, dx, 0)
        end
    end
    function s:GetChecked() return self.on end
    s:SetScript("OnEnter", function(self) self.hover = true; edge(self) end)
    s:SetScript("OnLeave", function(self) self.hover = false; edge(self) end)
    s:SetScript("OnDisable", function(self) self:SetAlpha(0.4) end)
    s:SetScript("OnEnable", function(self) self:SetAlpha(1) end)
    s:SetChecked(false)
    return s
end

function S.Edit(parent, width, height)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(width or 44, height or 28)
    S.Box(e, S.INPUT, S.EDGE, S.R_MD)
    S.SetFont(e, 13)
    e:SetTextInsets(8, 8, 0, 0)
    e:SetJustifyH("CENTER")
    e:SetAutoFocus(false)
    e:SetScript("OnEditFocusGained", function(self) S.SetBorder(self, S.Accent()) end)
    e:SetScript("OnEditFocusLost", function(self) S.SetBorder(self, S.EDGE) end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return e
end

-- A grey hint inside an empty edit box, like "Search".
function S.Placeholder(edit, text)
    local p = S.Text(edit, 12, S.FAINT)
    p:SetPoint("LEFT", 8, 0)
    p:SetPoint("RIGHT", -8, 0)
    p:SetWordWrap(false)
    p:SetText(text)
    local function update(self) p:SetShown((self:GetText() or "") == "") end
    edit:HookScript("OnTextChanged", update)
    -- A later SetScript("OnTextChanged") would drop the hook and leave the hint over the text.
    local set = edit.SetScript
    edit.SetScript = function(self, name, fn, ...)
        if name == "OnTextChanged" then
            return set(self, name, function(e, ...) update(e); if fn then return fn(e, ...) end end)
        end
        return set(self, name, fn, ...)
    end
    edit.placeholder = p
    return p
end

-- A scroll area with a thin scroll bar that can be dragged by mouse or touch.
function S.Scroll(parent)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(1, 1)
    sf:SetScrollChild(child)
    local bar = CreateFrame("Slider", nil, parent)
    bar:SetWidth(6)
    bar:SetPoint("TOPLEFT", sf, "TOPRIGHT", 4, 0)
    bar:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 4, 0)
    bar:SetOrientation("VERTICAL")
    S.Box(bar, { 1, 1, 1, 0.03 }, S.CLEAR, 3)
    local thumb = bar:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(WHITE)
    thumb:SetVertexColor(1, 1, 1, 0.22)
    thumb:SetSize(6, 40)
    bar:SetThumbTexture(thumb)
    bar:SetMinMaxValues(0, 0)
    bar:SetValueStep(1)
    bar:SetScript("OnValueChanged", function(_, v) sf:SetVerticalScroll(v) end)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        bar:SetValue(bar:GetValue() - delta * (self.step or 40))
    end)
    -- The bar shows only when the content is taller than the view; the thumb is as long as the
    -- share in view. The view's own size can change later (docked in the hub), so it counts again.
    function sf:Update(contentHeight)
        self.content = contentHeight or self.content or 0
        local view = self:GetHeight()
        local range = self.content - view
        if range < 2 then range = 0 end
        bar:SetMinMaxValues(0, range)
        bar:SetShown(range > 0)
        if range > 0 and view > 0 then
            thumb:SetHeight(math.max(24, math.floor(view * view / self.content)))
        end
        if bar:GetValue() > range then bar:SetValue(range) end
        if range == 0 then self:SetVerticalScroll(0) end
    end
    sf:SetScript("OnSizeChanged", function(self, w)
        if self.onResize then self.onResize(self, w) end
        if self.content then self:Update() end
    end)
    function sf:Top() bar:SetValue(0); self:SetVerticalScroll(0) end
    sf.child, sf.bar = child, bar
    return sf
end

-- A page that scrolls when what it holds is taller than the window (settings in a language
-- with long texts, a short hub). Build into page.inner, as wide as `width` until the page has
-- its own width, then call page:SetContent(height).
function S.ScrollPage(parent, width)
    local page = CreateFrame("Frame", nil, parent)
    local sf = S.Scroll(page)
    sf:SetPoint("TOPLEFT")
    sf:SetPoint("BOTTOMRIGHT", -10, 0)
    page.inner, page.scroll = sf.child, sf
    sf.child:SetWidth(math.max(1, (width or 400) - 10))
    sf.onResize = function(_, w) if w and w > 0 then sf.child:SetWidth(w) end end
    function page:SetContent(h)
        self.inner:SetHeight(math.max(1, h))
        self.scroll:Update(h)
    end
    return page
end

-- A multi-line text box that scrolls, for lists typed one entry per line.
function S.Memo(parent, width, height)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(width, height)
    S.Box(box, S.INPUT, S.EDGE, S.R_MD)
    local sf = S.Scroll(box)
    sf:SetPoint("TOPLEFT", 8, -8)
    sf:SetPoint("BOTTOMRIGHT", -16, 8)
    local e = CreateFrame("EditBox", nil, sf)
    e:SetMultiLine(true)
    e:SetAutoFocus(false)
    S.SetFont(e, 13)
    e:SetWidth(width - 28)
    e:SetHeight(height - 16)
    sf:SetScrollChild(e)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEditFocusGained", function() S.SetBorder(box, S.Accent()) end)
    e:SetScript("OnEditFocusLost", function() S.SetBorder(box, S.EDGE) end)
    -- Keep the line with the cursor in view.
    e:SetScript("OnCursorChanged", function(self, _, y, _, h)
        sf:Update(self:GetHeight())
        local top, view = sf:GetVerticalScroll(), sf:GetHeight()
        y = -y
        if y < top then sf.bar:SetValue(y)
        elseif y + h > top + view then sf.bar:SetValue(y + h - view) end
    end)
    -- A click anywhere in the box starts typing, also below the last line.
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() e:SetFocus() end)
    box.edit, box.scroll = e, sf
    return box
end

-- Choosers -----------------------------------------------------------------------------------

-- A flat pill that can be selected, for filters such as All / On / Off.
function S.Pill(parent, width, height)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 110, height or 28)
    S.Box(b, S.RAISED, S.EDGE, math.floor((height or 28) / 2))
    b.text = S.Text(b, 12)
    b.text:SetPoint("LEFT", 8, 0)
    b.text:SetPoint("RIGHT", -8, 0)
    b.text:SetJustifyH("CENTER")
    b.text:SetWordWrap(false)
    b.kind = "normal"
    b.SetText = function(self, s) self.text:SetText(s) end
    b.GetText = function(self) return self.text:GetText() end
    b:SetScript("OnDisable", function(self) self.text:SetAlpha(0.4) end)
    b:SetScript("OnEnable", function(self) self.text:SetAlpha(1) end)
    function b:SetSelected(on)
        self.selected = on
        local a = S.Accent()
        if on then
            S.Fill(self, { a[1], a[2], a[3], 0.20 })
            S.SetBorder(self, a)
            self.text:SetTextColor(a[1], a[2], a[3], 1)
        else
            S.Fill(self, S.RAISED)
            S.SetBorder(self, S.EDGE)
            self.text:SetTextColor(S.TEXT[1], S.TEXT[2], S.TEXT[3], 1)
        end
    end
    b:SetScript("OnEnter", function(self) if not self.selected then S.SetBorder(self, S.Accent()) end end)
    b:SetScript("OnLeave", function(self) self:SetSelected(self.selected) end)
    return b
end

-- A segmented control: one track with a part per label, the chosen one lit by a plate that
-- slides to it. width is the width of each part (nil fits each label). onSelect(i) runs on a
-- click and on Select(i). t.frame is the track (anchored to the top left of parent; move it
-- freely), t.buttons the parts.
-- icons (optional) is a list of game icon paths, one per label, shown left of the text; with
-- an empty label the icon alone fills the part (set button.tip so the cursor names it).
-- style "line" makes page tabs instead (S.PageTabs): no track, a hairline under them and a
-- glowing accent line under the chosen one.
function S.Tabs(parent, labels, width, onSelect, height, icons, style)
    local line = style == "line"
    height = height or (line and 34 or 30)
    local t = { buttons = {}, selected = 1 }
    local track = CreateFrame("Frame", nil, parent)
    track:SetPoint("TOPLEFT")
    if line then
        S.Box(track, S.CLEAR, S.CLEAR)
        local rule = tex(track, "BORDER", 0, S.LINE)
        rule:SetPoint("BOTTOMLEFT")
        rule:SetHeight(1)
        track.rule = rule
    else
        S.Box(track, S.INPUT, S.LINE, S.R_LG)
    end
    t.frame = track
    -- The plate (or line) under the chosen part, one for the whole control so it can slide.
    local ind = CreateFrame("Frame", nil, track)
    if ind.SetFrameLevel then ind:SetFrameLevel((tonumber(track:GetFrameLevel()) or 0) + 1) end
    local a = S.Accent()
    if line then
        ind.bar = tex(ind, "ARTWORK", 1, a)
        ind.bar:SetPoint("BOTTOMLEFT", 0, 0)
        ind.bar:SetPoint("BOTTOMRIGHT", 0, 0)
        ind.bar:SetHeight(2)
        ind.glow = ind:CreateTexture(nil, "ARTWORK", nil, 0)
        ind.glow:SetTexture(S.GLOW_TEX)
        if ind.glow.SetBlendMode then ind.glow:SetBlendMode("ADD") end
        ind.glow:SetVertexColor(a[1], a[2], a[3], 0.3)
        ind.glow:SetPoint("BOTTOMLEFT", -4, -3)
        ind.glow:SetPoint("BOTTOMRIGHT", 4, -3)
        ind.glow:SetHeight(8)
    else
        S.Box(ind, { S.FILL[1], S.FILL[2], S.FILL[3], 0.34 }, { S.FILL_EDGE[1], S.FILL_EDGE[2], S.FILL_EDGE[3], 0.6 }, S.R_MD)
        ind.hi = tex(ind, "BORDER", 6, S.CLEAR)
        ind.hi:SetPoint("TOPLEFT", S.R_MD, -1)
        ind.hi:SetPoint("TOPRIGHT", -S.R_MD, -1)
        ind.hi:SetHeight(1)
    end
    t.indicator = ind
    local x = line and 0 or 2
    for i, label in ipairs(labels) do
        local b = CreateFrame("Button", nil, track)
        if b.SetFrameLevel then b:SetFrameLevel((tonumber(track:GetFrameLevel()) or 0) + 2) end
        S.Box(b, S.CLEAR, S.CLEAR, S.R_MD)
        b.text = S.Text(b, line and 13 or 12, S.MUTED)
        b.text:SetPoint("LEFT", 6, 0)
        b.text:SetPoint("RIGHT", -6, 0)
        b.text:SetJustifyH("CENTER")
        b.text:SetWordWrap(false)
        b.text:SetText(label)
        b.SetText = function(self, s) self.text:SetText(s) end
        b.GetText = function(self) return self.text:GetText() end
        if icons and icons[i] and label == "" then
            S.SetButtonIcon(b, icons[i], 18)
            b.btnIcon:ClearAllPoints()
            b.btnIcon:SetPoint("CENTER")
        elseif icons and icons[i] then
            S.SetButtonIcon(b, icons[i], 14)
        end
        local w = width or math.floor(strw(b.text) + 28 + (icons and icons[i] and 18 or 0))
        b:SetSize(w, line and height - 1 or height - 4)
        b:SetPoint("TOPLEFT", x, line and 0 or -2)
        b.x = x
        x = x + w + (line and 2 or 0)
        -- Kept for older code that reads it; the indicator shows the choice now.
        b.bar = tex(b, "ARTWORK", 0, a)
        b.bar:SetHeight(2)
        b.bar:SetPoint("BOTTOMLEFT", 6, 0)
        b.bar:SetPoint("BOTTOMRIGHT", -6, 0)
        b.bar:Hide()
        b:SetScript("OnClick", function() t:Select(i) end)
        b:SetScript("OnEnter", function(self)
            if t.selected ~= i then
                if line then self.text:SetTextColor(S.TEXT[1], S.TEXT[2], S.TEXT[3], 1)
                else S.Fill(self, S.HOVER) end
            end
            if self.tip and GameTooltip and GameTooltip.SetOwner then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(self.tip)
                GameTooltip:Show()
            end
        end)
        b:SetScript("OnLeave", function(self)
            if t.selected ~= i then
                S.Fill(self, S.CLEAR)
                self.text:SetTextColor(S.MUTED[1], S.MUTED[2], S.MUTED[3], 1)
            end
            if self.tip and GameTooltip then GameTooltip:Hide() end
        end)
        t.buttons[i] = b
    end
    track:SetSize(x + (line and 0 or 2), height)
    -- The hairline under page tabs runs on to the right edge of their parent.
    local function fitRule()
        if not line then return end
        local w = x
        local pr, tl = tonumber((parent:GetRight())), tonumber((track:GetLeft()))
        if pr and tl and pr - tl > w then w = pr - tl end
        track.rule:SetWidth(w)
    end
    if line then
        track:HookScript("OnShow", fitRule)
        track:HookScript("OnSizeChanged", fitRule)
    end
    local function place(b, slide)
        local old = rawget(ind, "x")
        ind:ClearAllPoints()
        ind:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
        ind:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, line and -1 or 0)
        ind.x = b.x
        if slide and old and old ~= b.x and ind:IsVisible() then S.MotionSlide(ind, b.x - old, 0) end
    end
    function t:Select(i, quiet)
        self.selected = i
        for j, b in ipairs(self.buttons) do
            local on = j == i
            S.Fill(b, S.CLEAR)
            S.SetBorder(b, S.CLEAR)
            local c = on and S.TEXT or S.MUTED
            b.text:SetTextColor(c[1], c[2], c[3], 1)
            if rawget(b, "btnIcon") then b.btnIcon:SetAlpha(on and 1 or 0.55) end
            if on then place(b, not quiet) end
        end
        fitRule()
        if onSelect and not quiet then onSelect(i) end
    end
    t:Select(1, true)
    return t
end

-- Page tabs over a window's body: S.Tabs with the "line" look.
function S.PageTabs(parent, labels, width, onSelect, height, icons)
    return S.Tabs(parent, labels, width, onSelect, height or 30, icons, "line")
end

-- Layout -------------------------------------------------------------------------------------

-- Places frames under each other with a fixed gap, so no window counts pixels by hand.
-- st:Add(frame, height[, gap]) puts frame across the parent; st.y is the height used so far.
function S.Stack(parent, gap, startY)
    local st = { y = startY or 0, gap = gap or S.GAP, items = {} }
    function st:Add(frame, height, gapAfter)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -self.y)
        frame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -self.y)
        if height then frame:SetHeight(height) end
        self.items[#self.items + 1] = frame
        self.y = self.y + (height or frame:GetHeight()) + (gapAfter or self.gap)
        return frame
    end
    function st:Space(n) self.y = self.y + n end
    function st:Height() return math.max(0, self.y - self.gap) end
    return st
end

-- A card: a lighter panel with an optional title (a game icon before it, a grey hint on the
-- right) for one group of things. card.body is the area inside the padding, under the title.
function S.Card(parent, title, hint, icon)
    local c = CreateFrame("Frame", nil, parent)
    S.Box(c, S.SURFACE, S.CARD_EDGE, S.R_LG)
    S.Depth(c, S.R_LG)
    c.body = CreateFrame("Frame", nil, c)
    c.body:SetPoint("BOTTOMRIGHT", -S.INSET, S.INSET)
    if title then
        c.title = S.Text(c, 12, S.GOLD_DIM, nil, "bold")
        if icon then
            c.icon = S.IconBox(c, 18, icon)
            c.icon:SetPoint("TOPLEFT", S.INSET, -10)
            c.title:SetPoint("TOPLEFT", S.INSET + 26, -12)
        else
            c.title:SetPoint("TOPLEFT", S.INSET, -12)
        end
        c.title:SetWordWrap(false)
        c.title:SetText(title)
        c.hint = S.Text(c, 12, S.FAINT)
        c.hint:SetPoint("TOPRIGHT", -S.INSET, -13)
        c.hint:SetJustifyH("RIGHT")
        c.hint:SetWordWrap(false)
        c.hint:SetText(hint or "")
        c.title:SetPoint("RIGHT", c.hint, "LEFT", -8, 0)
        c.body:SetPoint("TOPLEFT", S.INSET, -36)
    else
        c.body:SetPoint("TOPLEFT", S.INSET, -S.INSET)
    end
    -- Card titles are dim gold bold capitals: section labels.
    if title then
        local set = c.title.SetText
        c.title.SetText = function(self, t) set(self, S.Upper(t)) end
        c.title:SetText(title)
    end
    function c:SetTitle(t, h)
        if self.title then self.title:SetText(t) end
        if h and self.hint then self.hint:SetText(h) end
    end
    -- The card height that fits a body of h pixels.
    function c:Fit(h)
        local total = h + (title and 36 or S.INSET) + S.INSET
        self:SetHeight(total)
        return total
    end
    return c
end

-- The width a frame will likely get: its own, else the nearest parent's that has one, less a
-- window's and a card's padding for each step that had none.
function S.GuessWidth(f)
    local steps = 0
    while f and steps < 12 do
        local w = tonumber((f.GetWidth and f:GetWidth())) or 0
        if w > 100 then return math.max(200, w - 2 * (S.PAD + S.INSET) * math.min(steps, 1)) end
        steps = steps + 1
        f = f.GetParent and f:GetParent() or nil
    end
    return 400
end

-- A settings row: the label and an optional grey line under it on the left, a control on the
-- right (a switch, an edit box, a button...). row.control is that control.
function S.SettingRow(parent, label, desc, control, controlWidth, icon)
    local row = CreateFrame("Frame", nil, parent)
    local left = 0
    if icon then
        row.icon = S.IconBox(row, 26, icon)
        row.icon:SetPoint("LEFT", 0, 0)
        left = 26 + 12
    end
    row.label = S.Text(row, 12)
    row.label:SetWordWrap(false)
    row.label:SetText(label)
    local right = -((controlWidth or (control and control:GetWidth()) or 0) + 12)
    if desc and desc ~= "" then
        row.label:SetPoint("TOPLEFT", left, -9)
        row.label:SetPoint("TOPRIGHT", right, -9)
        row.desc = S.Note(row, 12)
        row.desc:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -3)
        row.desc:SetPoint("TOPRIGHT", row.label, "BOTTOMRIGHT", 0, -3)
        row.desc:SetMaxLines(2)
        row.desc:SetText(desc)
        -- The card is placed after its rows, so its width may be a guess: the nearest frame up
        -- the chain that has a width, less the paddings. A second line that the guess misses
        -- still fits the row, only tightly.
        local pw = tonumber((parent:GetWidth())) or 0
        if pw <= 100 then pw = S.rowWidth or S.GuessWidth(parent) end
        local avail = pw - left + right
        local two = (tonumber((row.desc:GetStringWidth())) or 0) > avail
        row.height = S.ROW_DESC_H + (two and 14 or 0)
    else
        row.label:SetPoint("LEFT", left, 0)
        row.label:SetPoint("RIGHT", right, 0)
        row.height = S.ROW_H
    end
    if control then
        control:SetParent(row)
        control:ClearAllPoints()
        control:SetPoint("RIGHT", 0, 0)
        row.control = control
    end
    row.line = S.Divider(row)
    row.line:SetPoint("BOTTOMLEFT")
    row.line:SetPoint("BOTTOMRIGHT")
    row.line:SetHeight(1)
    return row
end

-- A settings row with an on/off switch. get() and set(value) read and write the setting.
-- extra (an edit box for a number...) sits left of the switch.
function S.SwitchRow(parent, label, desc, get, set, extra, icon)
    local sw = S.Switch(parent)
    local row = S.SettingRow(parent, label, desc, sw, 44 + (extra and (extra:GetWidth() + 8) or 0), icon)
    row.switch = sw
    if extra then
        extra:SetParent(row)
        extra:ClearAllPoints()
        extra:SetPoint("RIGHT", sw, "LEFT", -8, 0)
        row.extra = extra
    end
    sw:SetScript("OnClick", function(self)
        set(not get())
        self:SetChecked(get())
    end)
    row:SetScript("OnShow", function() sw:SetChecked(get()) end)
    sw:SetChecked(get())
    function row:SetChecked(v) sw:SetChecked(v) end
    function row:GetChecked() return sw:GetChecked() end
    return row
end

-- A card full of settings rows, stacked with their dividers. rows: { label, desc, get, set }
-- for a switch, or { label, desc, control = frame } for any other control; icon = a game icon
-- path shows it at the start of the row. Returns the card
-- and its height; card.rows has the rows in order.
function S.SettingsCard(parent, title, rows, hint, icon)
    local card = S.Card(parent, title, hint, icon)
    card.rows = {}
    local st = S.Stack(card.body, 0)
    S.rowWidth = S.GuessWidth(parent) - 2 * S.INSET
    for i, r in ipairs(rows) do
        local row = r.control and S.SettingRow(card.body, r[1], r[2], r.control, nil, r.icon)
            or S.SwitchRow(card.body, r[1], r[2], r[3], r[4], r.extra, r.icon)
        st:Add(row, row.height)
        row.line:SetShown(i < #rows)
        card.rows[i] = row
    end
    S.rowWidth = nil
    return card, card:Fit(st:Height() - (title and 6 or 0))
end

-- An on/off switch with its label to the right, for a setting outside a settings card (a list
-- filter). get() and set(value) read and write the setting. The label is anchored to the switch,
-- so put the switch where the row goes. Check boxes are for picking entries of a list, never for
-- a setting.
function S.SwitchLabel(parent, label, get, set, width)
    local s = S.Switch(parent)
    s.label = S.Text(s, 12)
    s.label:SetPoint("LEFT", s, "RIGHT", 4, 0)
    s.label:SetWidth(width or 300)
    s.label:SetWordWrap(false)
    s.label:SetText(label)
    s:SetScript("OnClick", function(self)
        set(not get())
        self:SetChecked(get())
    end)
    s:SetScript("OnShow", function(self) self:SetChecked(get()) end)
    s:SetChecked(get())
    return s
end

-- Showing state ------------------------------------------------------------------------------

-- A message in the middle of an empty area: a title and a grey line under it.
-- A one-line notice across the top of a body: a tinted rounded bar in a state colour (S.WARN
-- by default) with an icon, the text and a small close button. b:Set(text); b.onClose runs
-- after the bar hides itself.
S.BANNER_H = 40
function S.Banner(parent, icon, color)
    color = color or S.WARN
    local b = CreateFrame("Frame", nil, parent)
    b:SetHeight(S.BANNER_H)
    S.Box(b, { color[1] * 0.22, color[2] * 0.22, color[3] * 0.22, 1 }, { color[1] * 0.6, color[2] * 0.6, color[3] * 0.6, 1 }, S.R_LG)
    b.icon = S.IconBox(b, 24, icon)
    b.icon:SetPoint("LEFT", S.INSET, 0)
    b.close = S.Close(b, function() b:Hide(); if b.onClose then b.onClose() end end)
    b.close:SetPoint("RIGHT", -6, 0)
    b.text = S.Text(b, 12, color)
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
    b.text:SetPoint("RIGHT", b.close, "LEFT", -6, 0)
    b.text:SetJustifyH("LEFT")
    function b:Set(text) self.text:SetText(text or "") end
    b:Hide()
    return b
end

function S.Empty(parent)
    local e = CreateFrame("Frame", nil, parent)
    e:SetAllPoints()
    e.title = S.Text(e, 13, S.MUTED)
    e.title:SetPoint("BOTTOMLEFT", e, "LEFT", 24, 4)
    e.title:SetPoint("BOTTOMRIGHT", e, "RIGHT", -24, 4)
    e.title:SetJustifyH("CENTER")
    e.sub = S.Note(e, 12)
    e.sub:SetTextColor(S.FAINT[1], S.FAINT[2], S.FAINT[3], 1)
    e.sub:SetPoint("TOPLEFT", e, "LEFT", 24, -4)
    e.sub:SetPoint("TOPRIGHT", e, "RIGHT", -24, -4)
    e.sub:SetJustifyH("CENTER")
    function e:Set(title, sub)
        self.title:SetText(title or "")
        self.sub:SetText(sub or "")
    end
    return e
end

-- Money in the coin colours, so gold, silver and copper read at a glance. `short` drops the
-- copper from 1 gold up (for tiles). A negative amount starts with a minus.
function S.MoneyText(copper, short)
    copper = tonumber(copper) or 0
    if copper ~= copper or copper == math.huge or copper == -math.huge then return "?" end
    copper = math.floor(copper + 0.5)
    local sign = copper < 0 and "-" or ""
    copper = math.abs(copper)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = S.Hex(S.GOLD) .. g .. "g|r" end
    if s > 0 then parts[#parts + 1] = S.Hex(S.SILVER) .. s .. "s|r" end
    if (c > 0 and not (short and g > 0)) or #parts == 0 then parts[#parts + 1] = S.Hex(S.COPPER) .. c .. "c|r" end
    return sign .. table.concat(parts, " ")
end

-- Money with the game's coin pictures after plain numbers, for text on a coloured fill (a Primary
-- button): the coin colours of S.MoneyText would melt into it, the numbers keep the text's colour.
local COIN = "Interface\\MoneyFrame\\UI-%sIcon"
function S.MoneyIcons(copper, short)
    copper = tonumber(copper) or 0
    if copper ~= copper or copper == math.huge or copper == -math.huge then return "?" end
    copper = math.floor(copper + 0.5)
    local sign = copper < 0 and "-" or ""
    copper = math.abs(copper)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local function coin(n, kind) return n .. "|T" .. COIN:format(kind) .. ":0:0:2:0|t" end
    local parts = {}
    if g > 0 then parts[#parts + 1] = coin(g, "Gold") end
    if s > 0 then parts[#parts + 1] = coin(s, "Silver") end
    if (c > 0 and not (short and g > 0)) or #parts == 0 then parts[#parts + 1] = coin(c, "Copper") end
    return sign .. table.concat(parts, " ")
end

-- A tile with a game icon, a small label, one value and a line under it, and an optional bar:
-- tile:Set(value, color, sub[, fraction, barColor]). For a card's key facts side by side.
function S.InfoTile(parent, label, icon)
    local t = CreateFrame("Frame", nil, parent)
    S.Box(t, S.SURFACE, S.CARD_EDGE, S.R_LG)
    S.Depth(t, S.R_LG)
    -- The icon and the label share the top line, so the value and the sub line get the
    -- tile's whole width: a narrow tile still fits "33g 49s" and a long place name.
    t.icon = S.IconBox(t, 22, icon)
    t.icon:SetPoint("TOPLEFT", 8, -8)
    t.label = S.Text(t, 12, S.MUTED)
    t.label:SetPoint("LEFT", t.icon, "RIGHT", 7, 0)
    t.label:SetPoint("RIGHT", -8, 0)
    t.label:SetWordWrap(false)
    t.label:SetText(S.Upper(label) or "")
    t.value = S.Text(t, 15)
    t.value:SetPoint("TOPLEFT", t.icon, "BOTTOMLEFT", 0, -5)
    t.value:SetPoint("RIGHT", -8, 0)
    t.value:SetWordWrap(false)
    t.bar = S.Progress(t, 5)
    t.bar:SetPoint("TOPLEFT", t.value, "BOTTOMLEFT", 0, -4)
    t.bar:SetPoint("RIGHT", -8, 0)
    t.sub = S.Text(t, 12, S.MUTED)
    t.sub:SetPoint("TOPLEFT", t.value, "BOTTOMLEFT", 0, -4)
    t.sub:SetPoint("RIGHT", -8, 0)
    t.sub:SetWordWrap(false)
    function t:Set(value, color, sub, fraction, barColor)
        self.value:SetText(value or "")
        local c = color or S.TEXT
        self.value:SetTextColor(c[1], c[2], c[3], 1)
        self.sub:SetText(sub or "")
        self.sub:ClearAllPoints()
        if fraction then
            self.bar:Show()
            self.bar:Set(fraction, barColor)
            self.sub:SetPoint("TOPLEFT", self.bar, "BOTTOMLEFT", 0, -3)
        else
            self.bar:Hide()
            self.sub:SetPoint("TOPLEFT", self.value, "BOTTOMLEFT", 0, -4)
        end
        self.sub:SetPoint("RIGHT", -8, 0)
    end
    return t
end

-- A tile with one big number and its name under it, for counters.
S.STAT_SIZE, S.STAT_MIN = 20, 11
function S.Stat(parent, label, icon)
    local t = CreateFrame("Frame", nil, parent)
    S.Box(t, S.SURFACE, S.CARD_EDGE, S.R_LG)
    S.Depth(t, S.R_LG)
    local right = -S.INSET
    if icon then
        t.icon = S.IconBox(t, 30, icon)
        t.icon:SetPoint("RIGHT", -S.INSET, 0)
        right = -S.INSET - 38
    end
    t.value = S.Text(t, S.STAT_SIZE)
    t.value:SetPoint("TOPLEFT", S.INSET, -12)
    t.value:SetPoint("TOPRIGHT", right, -12)
    t.value:SetWordWrap(false)
    t.label = S.Text(t, 12, S.MUTED)
    t.label:SetPoint("TOPLEFT", t.value, "BOTTOMLEFT", 0, -6)
    t.label:SetPoint("TOPRIGHT", t.value, "BOTTOMRIGHT", 0, -6)
    t.label:SetWordWrap(false)
    t.label:SetText(label or "")
    -- A long value (money such as "2g 56s 76c") shrinks to fit the tile instead of ending in "...".
    function t:Fit()
        local v = self.value
        S.SetFont(v, S.STAT_SIZE)
        local avail = (tonumber(self:GetWidth()) or 0) - S.INSET + right
        if avail <= 0 then return end
        local w = tonumber((v.GetUnboundedStringWidth and v:GetUnboundedStringWidth()) or v:GetStringWidth()) or 0
        if w > avail then S.SetFont(v, math.max(S.STAT_MIN, math.floor(S.STAT_SIZE * avail / w))) end
    end
    function t:Set(value, color, label2)
        self.value:SetText(value)
        self:Fit()
        local c = color or S.TEXT
        self.value:SetTextColor(c[1], c[2], c[3], 1)
        if label2 then self.label:SetText(label2) end
    end
    return t
end

-- Tiles side by side, all the same width: holder:Layout(width) places them. holder.tiles.
-- icons (optional) gives each tile a game icon.
function S.StatRow(parent, labels, height, icons)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(height or 62)
    holder.tiles = {}
    for i, label in ipairs(labels) do holder.tiles[i] = S.Stat(holder, label, icons and icons[i]) end
    function holder:Layout(width)
        local n = #self.tiles
        local w = math.floor((width - (n - 1) * 8) / n)
        for i, t in ipairs(self.tiles) do
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", (i - 1) * (w + 8), 0)
            t:SetSize(w, self:GetHeight())
            t:Fit()
        end
    end
    return holder
end

-- A place to drop an item from the bags (or click with one on the cursor). onDrop() reads the
-- cursor itself.
function S.DropZone(parent, text, onDrop, height)
    local d = CreateFrame("Button", nil, parent)
    d:SetHeight(height or 40)
    S.Box(d, S.INPUT, S.EDGE, S.R_LG)
    d.text = S.Text(d, 12, S.MUTED)
    d.text:SetPoint("LEFT", 10, 0)
    d.text:SetPoint("RIGHT", -10, 0)
    d.text:SetJustifyH("CENTER")
    d.text:SetText("+  " .. (text or ""))
    d:SetScript("OnReceiveDrag", onDrop)
    d:SetScript("OnClick", onDrop)
    d:SetScript("OnEnter", function(self)
        S.SetBorder(self, S.Accent())
        self.text:SetTextColor(S.TEXT[1], S.TEXT[2], S.TEXT[3], 1)
    end)
    d:SetScript("OnLeave", function(self)
        S.SetBorder(self, S.EDGE)
        self.text:SetTextColor(S.MUTED[1], S.MUTED[2], S.MUTED[3], 1)
    end)
    return d
end

-- A thin rounded bar that fills from the left: bar:Set(fraction[, color]).
function S.Progress(parent, height)
    height = height or 6
    local p = CreateFrame("Frame", nil, parent)
    p:SetHeight(height)
    S.Box(p, S.INPUT, S.EDGE, math.floor(height / 2))
    local r = math.floor((height - 2) / 2)
    p.fill = CreateFrame("Frame", nil, p)
    p.fill:SetPoint("TOPLEFT", 1, -1)
    p.fill:SetPoint("BOTTOMLEFT", 1, 1)
    local a = S.Accent()
    S.Box(p.fill, a, a, r)
    function p.fill:SetVertexColor(cr, cg, cb, ca)
        local c = { cr, cg, cb, ca or 1 }
        S.Fill(self, c)
        S.SetBorder(self, c)
    end
    function p:Set(f, c)
        f = math.max(0, math.min(1, f or 0))
        local w = (tonumber(self:GetWidth()) or 0) - 2
        local to = math.max(2 * math.max(r, 1), w * f)
        local from = rawget(self, "shownWidth")
        self.shownWidth = to
        self.fill:SetShown(f > 0)
        -- The bar grows to its new length (400 ms) when it is in view; else it is set at once.
        if from and self:IsVisible() then
            S.Tween(self, "fill", from, to, 0.4, function(v) self.fill:SetWidth(v) end)
        else
            self.fill:SetWidth(to)
        end
        if c then self.fill:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end
    end
    return p
end

-- A small coloured label, like "On" or "3 new".
function S.Badge(parent, text, color)
    local b = CreateFrame("Frame", nil, parent)
    S.Box(b, S.CLEAR, S.CLEAR, 9)
    b.text = S.Text(b, 12)
    b.text:SetPoint("CENTER")
    function b:Set(s, c)
        c = c or S.MUTED
        self.text:SetText(s or "")
        self.text:SetTextColor(c[1], c[2], c[3], 1)
        S.Fill(self, { c[1], c[2], c[3], 0.14 })
        S.SetBorder(self, { c[1], c[2], c[3], 0.35 })
        self:SetSize(math.floor(strw(self.text) + 12), 18)
        self:SetShown(s ~= nil and s ~= "")
    end
    b:Set(text, color)
    return b
end

-- Clips texture t to a circle (or to the shape of `file`), where the client has masks.
function S.RoundMask(owner, t, file)
    if not owner.CreateMaskTexture then return end
    local m = owner:CreateMaskTexture()
    if not m then return end
    m:SetTexture(file or S.ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m:SetAllPoints(t)
    t:AddMaskTexture(m)
    return m
end

-- A disc of one colour; size is the diameter.
function S.Circle(parent, size, color, layer, sub)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
    t:SetTexture(S.ROUND)
    t:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    t:SetSize(size, size)
    return t
end

-- A round game icon with a ring around it (r.ring, r.fill, r.tex); r:SetIcon(path).
function S.RoundIcon(parent, size, path)
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(size, size)
    b.ring = S.Circle(b, size, S.EDGE, "BACKGROUND", 1)
    b.ring:SetPoint("CENTER")
    b.fill = S.Circle(b, size - 4, S.SURFACE, "BACKGROUND", 2)
    b.fill:SetPoint("CENTER")
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetSize(size - 12, size - 12)
    b.tex:SetPoint("CENTER")
    b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    S.RoundMask(b, b.tex)
    function b:SetIcon(p) self.tex:SetTexture(p or "Interface\\Icons\\INV_Misc_QuestionMark") end
    function b:SetRing(c) self.ring:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end
    b:SetIcon(path)
    return b
end

-- A game icon (an item or a spell, "Interface\\Icons\\...") cut round, in a thin blue ring
-- with a soft blue glow. box.tex is the texture; S.SetBorder(box, c) colours the ring and
-- box:SetGlow(c) the glow.
function S.IconBox(parent, size, path)
    size = size or 26
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(size, size)
    local g = S.GLOW
    b.glow = b:CreateTexture(nil, "BACKGROUND", nil, -8)
    b.glow:SetTexture(S.GLOW_TEX)
    b.glow:SetSize(size + math.max(8, math.floor(size * 0.4)), size + math.max(8, math.floor(size * 0.4)))
    b.glow:SetPoint("CENTER")
    b.glow:SetVertexColor(g[1], g[2], g[3], 0)
    b.ring = S.Circle(b, size, { g[1], g[2], g[3], 1 }, "BACKGROUND", -7)
    b.ring:SetPoint("CENTER")
    b.bg = S.Circle(b, size - 2, S.INPUT, "BACKGROUND", -6)
    b.bg:SetPoint("CENTER")
    b.edges, b.fills = { b.ring }, { b.bg }
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetSize(size - 2, size - 2)
    b.tex:SetPoint("CENTER")
    b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    S.RoundMask(b, b.tex)
    -- Gulli Hearth has no glow; a state colour (c) shows on the ring instead.
    function b:SetGlow(c)
        c = c or S.GLOW
        self.ring:SetVertexColor(c[1], c[2], c[3], 1)
    end
    function b:SetIcon(p) self.tex:SetTexture(p or "Interface\\Icons\\INV_Misc_QuestionMark") end
    b:SetIcon(path)
    return b
end

-- An item in a game icon frame, with a stack count in the corner and the border in the
-- item's quality colour: icon:Set(texture, count, quality).
S.QUALITY = { [2] = { 0.12, 1, 0, 1 }, [3] = { 0, 0.44, 0.87, 1 }, [4] = { 0.64, 0.21, 0.93, 1 } }
-- The game's item quality colour (0 grey .. 5 orange) as a "|cff..." prefix.
local QUALITY_HEX = { [0] = "|cff9d9d9d", [1] = "|cffffffff", [2] = "|cff1eff00", [3] = "|cff0070dd",
                      [4] = "|cffa335ee", [5] = "|cffff8000" }
function S.QualityHex(q)
    local c = ITEM_QUALITY_COLORS and q and ITEM_QUALITY_COLORS[q]
    if c and c.hex then return c.hex end
    return QUALITY_HEX[q or 1] or QUALITY_HEX[1]
end

-- The quest log colour of a level against the player's: grey, green, yellow, orange, red.
-- The game's own rule when it has it, else the same steps by hand.
function S.LevelColor(level, mine)
    if not level then return S.MUTED end
    if GetQuestDifficultyColor and not mine then
        local c = GetQuestDifficultyColor(level)
        if c and c.r then return { c.r, c.g, c.b, 1 } end
    end
    mine = mine or (UnitLevel and UnitLevel("player")) or 60
    local d = level - mine
    if d >= 5 then return { 1, 0.1, 0.1, 1 } end
    if d >= 3 then return { 1, 0.5, 0.25, 1 } end
    if d >= -2 then return { 1, 1, 0, 1 } end
    local gray = mine <= 5 and 0 or (mine <= 39 and mine - math.floor(mine / 10) - 5 or mine - math.floor(mine / 5) - 1)
    if level > gray then return { 0.25, 0.75, 0.25, 1 } end
    return { 0.5, 0.5, 0.5, 1 }
end

function S.ItemIcon(parent, size)
    local b = S.IconBox(parent, size)
    b.count = S.Text(b, math.max(8, math.floor((size or 26) * 0.45)), S.TEXT, "OUTLINE")
    b.count:SetPoint("BOTTOMRIGHT", 0, 1)
    function b:Set(texture, n, quality)
        self:SetIcon(texture)
        self.count:SetText((n and n > 1) and (n > 999 and (math.floor(n / 100) / 10 .. "k") or tostring(n)) or "")
        local q = S.QUALITY[quality or 1]
        S.SetBorder(self, q or { S.GLOW[1], S.GLOW[2], S.GLOW[3], 0.9 })
        self:SetGlow(q)
        self:Show()
    end
    return b
end

-- A number with - and + buttons: get() reads it, set(value) writes it; fmt(value) shows it.
-- stepper.minus, stepper.plus and stepper.value; stepper:Refresh() redraws the number.
function S.Stepper(parent, get, set, step, min, max, fmt, width)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width or 110, 28)
    f.minus = S.Button(f, 28, 28)
    f.minus:SetPoint("LEFT")
    f.minus:SetText("-")
    f.plus = S.Button(f, 28, 28)
    f.plus:SetPoint("RIGHT")
    f.plus:SetText("+")
    f.value = S.Text(f, 12)
    f.value:SetPoint("LEFT", f.minus, "RIGHT", 2, 0)
    f.value:SetPoint("RIGHT", f.plus, "LEFT", -2, 0)
    f.value:SetJustifyH("CENTER")
    f.value:SetWordWrap(false)
    function f:Refresh() self.value:SetText((fmt or tostring)(get())) end
    -- The new number drops in from a few pixels above.
    f.minus:SetScript("OnClick", function() set(math.max(min, get() - step)); f:Refresh(); S.MotionIn(f.value, -5, S.BASE) end)
    f.plus:SetScript("OnClick", function() set(math.min(max, get() + step)); f:Refresh(); S.MotionIn(f.value, -5, S.BASE) end)
    f:Refresh()
    return f
end

-- The module icon, from the addon folder.
function S.Icon(parent, size)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetSize(size or 20, size or 20)
    t:SetTexture("Interface\\AddOns\\" .. tostring(addon) .. "\\icon")
    t:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    S.RoundMask(parent, t)
    return t
end

-- Windows ------------------------------------------------------------------------------------

-- A round back button with a < drawn from two lines.
local function backButton(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(28, 28)
    S.Box(b, S.CLEAR, S.EDGE, 14)
    local lines = {}
    for i, d in ipairs({ { "LEFT", 10, 0, "TOPRIGHT", -11, -8 }, { "LEFT", 10, 0, "BOTTOMRIGHT", -11, 8 } }) do
        local l = b:CreateLine(nil, "ARTWORK")
        l:SetThickness(1.5)
        l:SetColorTexture(S.MUTED[1], S.MUTED[2], S.MUTED[3], 1)
        l:SetStartPoint(d[1], b, d[2], d[3])
        l:SetEndPoint(d[4], b, d[5], d[6])
        lines[i] = l
    end
    local function color(c) for _, l in ipairs(lines) do l:SetColorTexture(c[1], c[2], c[3], 1) end end
    b:SetScript("OnEnter", function(self) S.SetBorder(self, S.Accent()); color(S.TEXT) end)
    b:SetScript("OnLeave", function(self) S.SetBorder(self, S.EDGE); color(S.MUTED) end)
    b:SetScript("OnClick", onClick)
    return b
end
S.Back = backButton

-- Puts a window inside another frame (the hub): no shadow, no dragging, a back button instead
-- of the close button, and opts.right (the hub's own controls) on the right of the header.
-- opts: { back = fn, popOut = fn, onHide = fn, onResize = fn, right = { frames }, width, height }
local function dock(f, host, opts)
    opts = opts or {}
    f.size = f.size or { f:GetWidth(), f:GetHeight() }
    f.dockOpts = opts
    f.docked = true
    f:StopMovingOrSizing()
    f:SetParent(host)
    -- The hub is scaled already: a page inside it at its own scale would be scaled twice.
    S.ApplyScale(f, 1)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    f:SetWidth(opts.width or f.size[1])
    f:SetHeight(opts.height or f.size[2])
    f:SetFrameStrata(host:GetFrameStrata())
    f:SetFrameLevel((tonumber(host:GetFrameLevel()) or 0) + 5)
    for _, sh in ipairs(f.shadow or {}) do sh:Hide() end
    -- Inside the hub the page sits on the hub's own glass: no second fill, edge or light.
    S.Fill(f, S.CLEAR)
    S.SetBorder(f, S.CLEAR)
    S.ShowGlass(f, false)
    S.Fill(f.bar, S.CLEAR)
    S.ShowGlass(f.bar, false)
    -- The hub's header has the gold line; a page inside it gets a plain one.
    if rawget(f, "headLine") then f.headLine:SetVertexColor(S.LINE[1], S.LINE[2], S.LINE[3], S.LINE[4]) end
    f.close:Hide()
    if not f.back then
        f.back = backButton(f.bar, function() if f.dockOpts and f.dockOpts.back then f.dockOpts.back(f) end end)
        f.back:SetPoint("LEFT", 10, 0)
    end
    f.back:Show()
    f.iconBox:ClearAllPoints()
    f.iconBox:SetPoint("LEFT", f.back, "RIGHT", 10, 0)
    local last
    for _, b in ipairs(opts.right or {}) do
        b:SetParent(f.bar)
        b:ClearAllPoints()
        if last then b:SetPoint("RIGHT", last, "LEFT", -8, 0) else b:SetPoint("RIGHT", -12, 0) end
        b:Show()
        last = b
    end
    -- Header buttons of the window (help, size...) move left of the hub's controls.
    local first = rawget(f.close, "dockNext")
    if first and last then
        first:ClearAllPoints()
        first:SetPoint("RIGHT", last, "LEFT", -8, 0)
    end
    if not f.dockHooked then
        f.dockHooked = true
        f:HookScript("OnHide", function(self)
            if self.docked and self.dockOpts and self.dockOpts.onHide then self.dockOpts.onHide(self) end
        end)
    end
    f:Show()
end

-- Takes a window out of the hub again: back to its own size in the middle of the screen. It
-- stays hidden; the caller shows it when it should stand alone.
local function undock(f)
    if not f.docked then return end
    local opts = f.dockOpts or {}
    f.docked = false
    f.dockOpts = false
    f:Hide()
    for _, b in ipairs(opts.right or {}) do b:Hide() end
    f:SetParent(UIParent)
    f:ClearAllPoints()
    f:SetPoint("CENTER")
    f:SetWidth(f.size[1])
    f:SetHeight(f.size[2])
    f:SetFrameStrata(f.strata or "DIALOG")
    for _, sh in ipairs(f.shadow or {}) do sh:Show() end
    S.Fill(f, S.GLASS)
    S.SetBorder(f, S.GLASS_EDGE)
    S.ShowGlass(f, true)
    S.Fill(f.bar, S.HEAD)
    S.ShowGlass(f.bar, true)
    if rawget(f, "headLine") then
        local c = S.HEAD_LINE
        f.headLine:SetVertexColor(c[1], c[2], c[3], c[4])
    end
    if f.back then f.back:Hide() end
    f.close:Show()
    f.iconBox:ClearAllPoints()
    f.iconBox:SetPoint("LEFT", 14, 0)
    local first = rawget(f.close, "dockNext")
    if first then
        first:ClearAllPoints()
        first:SetPoint("RIGHT", f.close, "LEFT", -6, 0)
    end
end

-- A movable window: a header with the addon icon, the title, a grey subtitle (the slash
-- command) and a close button. frame.body is the padded area under the header; S.Footer adds
-- a bar for the buttons at the bottom. opts: { sub = "/gmc", icon = path, strata, fullTitle }.
function S.Window(name, title, width, height, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(width, height)
    f:SetPoint("CENTER")
    f.strata = opts.strata or "DIALOG"
    f:SetFrameStrata(f.strata)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    -- A deep soft shadow, then the glass: see-through dark, a light edge, the sheen and light.
    f.shadow = S.Shadow(f, S.R_XL, 6, 0.24)
    S.Box(f, S.GLASS, S.GLASS_EDGE, S.R_XL)
    S.Glass(f, S.R_XL)
    if name then tinsert(UISpecialFrames, name) end

    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    bar:SetHeight(S.HEADER_H)
    S.Box(bar, S.HEAD, S.CLEAR, S.R_XL - 1, "top")
    S.HeadArt(bar, S.R_XL)
    -- The one gold line of the look, under the header.
    local line = S.Divider(bar, S.HEAD_LINE)
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(1)
    f.headLine = line
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() if not f.docked then f:StartMoving() end end)
    bar:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    f.bar = bar

    -- The module's icon, round in a ring like every icon in a window; f.icon is its texture.
    f.iconBox = S.IconBox(bar, 26)
    f.iconBox:SetPoint("LEFT", 14, 0)
    f.icon = f.iconBox.tex
    f.icon:SetTexture(opts.icon or ("Interface\\AddOns\\" .. tostring(addon) .. "\\icon"))
    f.title = S.Text(bar, 16, S.GOLD, nil, "title")
    f.title:SetPoint("LEFT", f.iconBox, "RIGHT", 10, 0)
    f.title:SetWordWrap(false)
    f.title:SetText(opts.fullTitle and title or shortTitle(title))
    f.sub = S.Text(bar, 12, S.FAINT)
    f.sub:SetPoint("LEFT", f.title, "RIGHT", 8, -1)
    f.sub:SetWordWrap(false)
    local slash = _G["SLASH_" .. tostring(addon):gsub("%-", ""):upper() .. "1"]
    f.sub:SetText(opts.sub or slash or "")
    -- opts.pill: the sub text (a version) sits in a small rounded pill.
    if opts.pill and opts.sub then
        local p = CreateFrame("Frame", nil, bar)
        S.Box(p, S.RAISED, S.LINE, S.R_SM)
        p:SetHeight(18)
        p:SetWidth(math.floor(strw(f.sub) + 14))
        p:SetPoint("LEFT", f.title, "RIGHT", 8, 0)
        f.sub:ClearAllPoints()
        f.sub:SetPoint("CENTER", p, "CENTER", 0, 0)
        f.subPill = p
    end

    f.close = closeButton(bar, function() S.MotionOut(f, function() f:Hide() end) end)
    -- Opening: it grows in from 96.5% and fades in, and one pass of light runs over the glass.
    S.TrackScale(f)
    f:HookScript("OnShow", function(self)
        if self.docked then return end
        scaleWindow(self)
        S.MotionIn(self, 8, S.SLOW, 0.965)
        sweep(self)
    end)
    f.close:SetPoint("RIGHT", -8, 0)
    -- Small header buttons (help, scale...) go left of the close button: f:AddHeaderButton(b).
    f.headerRight = f.close
    function f:AddHeaderButton(b)
        b:SetParent(bar)
        b:ClearAllPoints()
        b:SetPoint("RIGHT", self.headerRight, "LEFT", -6, 0)
        if self.headerRight == self.close then self.close.dockNext = b end
        self.headerRight = b
        return b
    end

    f.body = CreateFrame("Frame", nil, f)
    f.body:SetPoint("TOPLEFT", S.PAD, -(S.HEADER_H + S.PAD))
    f.body:SetPoint("BOTTOMRIGHT", -S.PAD, S.PAD)
    f.inner = { width - 2 * S.PAD, height - S.HEADER_H - 2 * S.PAD }
    f.size = { width, height }
    f.docked, f.dockOpts, f.dockHooked, f.back, f.footer = false, false, false, false, false
    f.Dock, f.Undock = dock, undock
    f:Hide()
    return f
end

-- Sets the height of a window. A window that sits in the hub keeps the hub's height and only
-- remembers its own for when it stands alone again.
function S.SetWindowHeight(f, h)
    f.size = f.size or { f:GetWidth(), h }
    f.size[2] = h
    if f.docked then
        if f.dockOpts and f.dockOpts.onResize then f.dockOpts.onResize(f) end
        return
    end
    f:SetHeight(h)
end

-- Sets the window height so the body is exactly h pixels high.
function S.FitWindow(f, h)
    S.SetWindowHeight(f, S.HEADER_H + 2 * S.PAD + h + (f.footer and S.FOOTER_H or 0))
end

-- A slash command opens the window alone. When the window sits in the hub, the command takes
-- it out of the hub instead of closing it.
function S.ToggleWindow(f)
    if f.docked and f.dockOpts and f.dockOpts.popOut then
        f.dockOpts.popOut(f)
    else
        f:SetShown(not f:IsShown())
    end
    return f:IsShown()
end

-- A bar at the bottom of a window for its buttons: the main one on the right, a grey status
-- line on the left. footer:Add(button) puts buttons from the right to the left.
function S.Footer(f)
    local ft = CreateFrame("Frame", nil, f)
    ft:SetPoint("BOTTOMLEFT", 1, 1)
    ft:SetPoint("BOTTOMRIGHT", -1, 1)
    ft:SetHeight(S.FOOTER_H)
    S.Box(ft, S.CLEAR, S.CLEAR, S.R_XL - 1, "bottom")
    local line = S.Divider(ft, S.LINE)
    line:SetPoint("TOPLEFT")
    line:SetPoint("TOPRIGHT")
    line:SetHeight(1)
    ft.status = S.Note(ft, 12)
    ft.status:SetJustifyV("MIDDLE")
    ft.status:SetPoint("TOPLEFT", S.PAD, -8)
    ft.status:SetPoint("BOTTOMLEFT", S.PAD, 8)
    ft.status:SetMaxLines(2)
    ft.last = nil
    function ft:Add(b)
        b:SetParent(self)
        b:ClearAllPoints()
        if self.last then b:SetPoint("RIGHT", self.last, "LEFT", -8, 0)
        else b:SetPoint("RIGHT", -S.PAD, 0) end
        self.last = b
        self.status:SetPoint("RIGHT", b, "LEFT", -12, 0)
        return b
    end
    function ft:SetStatus(s, c)
        c = c or S.MUTED
        self.status:SetText(s or "")
        self.status:SetTextColor(c[1], c[2], c[3], 1)
    end
    f.body:SetPoint("BOTTOMRIGHT", -S.PAD, S.FOOTER_H + S.PAD)
    f.inner[2] = f.inner[2] - S.FOOTER_H
    f.footer = ft
    -- A page that hides the footer gets its height back (IsShown, not visibility: the window may be hidden).
    local function fit(self)
        f.body:SetPoint("BOTTOMRIGHT", -S.PAD, (self:IsShown() and S.FOOTER_H or 0) + S.PAD)
    end
    ft:HookScript("OnShow", fit)
    ft:HookScript("OnHide", fit)
    return ft
end

-- A column of choices on the left of a window (characters, dungeons...). Like S.List, with
-- the chosen row marked by the accent bar.
function S.NavRow(r)
    S.Fill(r, S.CLEAR)
    r.mark = tex(r, "ARTWORK", 0, S.Accent())
    r.mark:SetPoint("TOPLEFT", 1, -8)
    r.mark:SetPoint("BOTTOMLEFT", 1, 8)
    r.mark:SetWidth(2)
    r.mark:Hide()
    function r:SetSelected(on)
        self.selected = on
        S.Fill(self, on and { S.FILL[1], S.FILL[2], S.FILL[3], 0.34 } or S.CLEAR)
        self.mark:SetShown(on)
    end
    return r
end

-- A scrolling list of rows that are made once and reused. make(row) builds a row frame,
-- fill(row, item, i) shows one item in it. list:SetData(items) redraws. Rows are separated by
-- a hairline and light up under the cursor when they are buttons. list.heightOf(item), when
-- set, gives a row its own height (cards between short headers).
function S.List(parent, rowHeight, make, fill, gap)
    gap = gap or 0
    local sf = S.Scroll(parent)
    local rows = {}
    sf.step = rowHeight + gap
    sf.onResize = function(self, w) if w and w > 1 then self.child:SetWidth(w) end end
    function sf:SetData(items)
        local width = self:GetWidth()
        self.child:SetWidth(width > 1 and width or 400)
        local y = 0
        for i, item in ipairs(items) do
            local r = rows[i]
            if not r then
                r = CreateFrame("Frame", nil, self.child)
                S.Box(r, S.CLEAR, S.CLEAR, S.R_MD)
                r.line = S.Divider(r)
                r.line:SetPoint("BOTTOMLEFT")
                r.line:SetPoint("BOTTOMRIGHT")
                r.line:SetHeight(1)
                make(r)
                rows[i] = r
            end
            local heightOf = rawget(self, "heightOf")
            local rh = heightOf and heightOf(item) or rowHeight
            r:SetHeight(rh)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, -y)
            r:SetPoint("TOPRIGHT", 0, -y)
            y = y + rh + gap
            fill(r, item, i)
            r:Show()
        end
        for i = #items + 1, #rows do rows[i]:Hide() end
        local h = y
        self.child:SetHeight(math.max(h, 1))
        self:Update(h)
    end
    sf.rows = rows
    return sf
end

-- HUD: what sits on the game screen outside a window ----------------------------------------
-- One look for every popup and overlay (Gulli HUD): game icons framed like the action bars,
-- a coloured ring for their state, translucent panels, one card for notices (S.Toast) and one
-- way to move things (S.Mover, shown by /gulli move).

S.HUD_BG = { 0.055, 0.059, 0.071, 0.88 }
S.TOAST_W, S.TOAST_H = 360, 64

-- Edges of one width and colour around f, inside (inset >= 0) or outside (inset < 0) it.
local function frameLines(f, layer, sub, color, width, inset)
    local t = {}
    local o = inset or 0
    for i, p in ipairs({ { "TOPLEFT", "TOPRIGHT", o, -o, -o, -o, "h" }, { "BOTTOMLEFT", "BOTTOMRIGHT", o, o, -o, o, "h" },
                         { "TOPLEFT", "BOTTOMLEFT", o, -o, o, o, "v" }, { "TOPRIGHT", "BOTTOMRIGHT", -o, -o, -o, o, "v" } }) do
        local e = tex(f, layer, sub, color)
        e:SetPoint(p[1], p[3], p[4])
        e:SetPoint(p[2], p[5], p[6])
        if p[7] == "h" then e:SetHeight(width) else e:SetWidth(width) end
        t[i] = e
    end
    return t
end

local function colorLines(lines, c, a)
    for _, e in ipairs(lines) do e:SetVertexColor(c[1], c[2], c[3], a or c[4] or 1) end
end

local function showLines(lines, on)
    for _, e in ipairs(lines) do e:SetShown(on and true or false) end
end

-- A translucent HUD panel with rounded corners: a faint edge and a soft shadow.
function S.HudPanel(f)
    S.Box(f, S.HUD_GLASS, S.GLASS_EDGE, S.R_LG)
    S.Glass(f, S.R_LG, 0.8)
    f.inner = {}
    f.shadow = S.Shadow(f, S.R_LG, 5, 0.28)
    return f
end

-- "SHIFT-F" -> "sF", "BUTTON4" -> "M4": the short key text in the corner of an icon.
function S.ShortKey(key)
    if not key or key == "" then return "" end
    key = tostring(key):upper()
    key = key:gsub("SHIFT%-", "s"):gsub("CTRL%-", "c"):gsub("ALT%-", "a"):gsub("META%-", "m")
    key = key:gsub("MOUSEWHEELUP", "WU"):gsub("MOUSEWHEELDOWN", "WD"):gsub("BUTTON", "M")
    key = key:gsub("NUMPAD", "N"):gsub("SPACE", "Sp")
    return key
end

local STATE = { need = "BAD", soon = "WARN", ok = "GOOD" }

-- A game icon on the screen: cropped like the action bars, a black 1 pixel frame, a coloured
-- ring for its state (need = red and pulsing, soon = yellow, ok = green), the key in the top
-- left corner, a count in the bottom right and a big text in the middle (time left).
-- b is any frame, secure buttons too; the look is only textures and texts on it.
-- b:SetIcon(path), b:SetState(state), b:SetDone(on), b:SetKey(key), b:SetCount(s), b:SetMid(s, color).
function S.HudIcon(b, size)
    size = size or 40
    b:SetSize(size, size)
    local r = size >= 32 and S.R_LG or S.R_MD
    S.Box(b, { 0, 0, 0, 1 }, { 1, 1, 1, 0.14 }, r)
    b.outline = {}
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    S.RoundMask(b, b.icon, S.ROUND_SQ)
    -- The state ring: one or two rounded 1 pixel rings on a frame above the icon.
    b.ring = {}
    for k = 1, size >= 32 and 2 or 1 do
        local rf = CreateFrame("Frame", nil, b)
        rf:SetPoint("TOPLEFT", k - 1, -(k - 1))
        rf:SetPoint("BOTTOMRIGHT", -(k - 1), k - 1)
        S.Box(rf, S.CLEAR, S.BAD, r - (k - 1))
        for _, e in ipairs(rf.edges) do b.ring[#b.ring + 1] = e end
    end
    showLines(b.ring, false)
    b.glow = roundRect(b, "BACKGROUND", -7, S.BAD, r + 3, -3,
        { TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true })
    showLines(b.glow, false)
    b.key = S.Text(b, math.max(12, math.floor(size * 0.22)), S.TEXT, "OUTLINE")
    b.key:SetPoint("TOPLEFT", 3, -3)
    b.count = S.Text(b, math.max(12, math.floor(size * 0.27)), S.TEXT, "OUTLINE")
    b.count:SetPoint("BOTTOMRIGHT", -2, 3)
    b.mid = S.Text(b, math.max(12, math.floor(size * 0.32)), S.WARN, "OUTLINE")
    b.mid:SetPoint("CENTER", 0, 0)
    b.mid:SetJustifyH("CENTER")
    -- The pulse runs on a child frame, so a secure button keeps its own scripts.
    local pulser = CreateFrame("Frame", nil, b)
    pulser:Hide()
    local t = 0
    -- The light breathes from full to 35% and back every 2.4 s; with "Reduce motion" it stays lit.
    pulser:SetScript("OnUpdate", function(_, dt)
        t = t + (dt or 0)
        local a = 1
        if not (GulliToolkitDB and GulliToolkitDB.calm) then
            a = 0.35 + 0.65 * (0.5 + 0.5 * math.cos(t * math.pi / 1.2))
        end
        for _, e in ipairs(b.glow) do e:SetAlpha(a) end
        for _, e in ipairs(b.ring) do e:SetAlpha(0.35 + 0.65 * a) end
    end)
    b.pulser = pulser
    function b:SetIcon(p) self.icon:SetTexture(p or "Interface\\Icons\\INV_Misc_QuestionMark") end
    function b:SetState(st)
        self.state = st
        local c = st and S[STATE[st] or ""]
        showLines(self.ring, c ~= nil)
        if c then colorLines(self.ring, c) end
        local pulse = st == "need"
        showLines(self.glow, pulse)
        if pulse then colorLines(self.glow, S.BAD, 0.5) end
        if not pulse then for _, e in ipairs(self.ring) do e:SetAlpha(1) end end
        self.pulser:SetShown(pulse)
    end
    function b:SetDone(on)
        self.icon:SetDesaturated(on and true or false)
        self.icon:SetVertexColor(on and 0.6 or 1, on and 0.6 or 1, on and 0.6 or 1, 1)
    end
    function b:SetKey(k) self.key:SetText(S.ShortKey(k)) end
    function b:SetCount(s) self.count:SetText(s or "") end
    function b:SetMid(s, c)
        c = c or S.WARN
        self.mid:SetText(s or "")
        self.mid:SetTextColor(c[1], c[2], c[3], 1)
    end
    return b
end

-- What an icon is about, in a panel next to it: a white line and a grey one.
-- cap:Set(title, sub) sizes it to the longer line.
function S.HudCaption(parent, height)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(150, height or 40)
    S.HudPanel(f)
    f.title = S.Text(f, 13)
    f.title:SetPoint("TOPLEFT", 10, -((height or 40) / 2 - 13))
    f.title:SetWordWrap(false)
    f.sub = S.Text(f, 12, S.MUTED)
    f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
    f.sub:SetWordWrap(false)
    function f:Set(title, sub)
        self.title:SetText(title or "")
        self.sub:SetText(sub or "")
        self.sub:SetShown(sub ~= nil and sub ~= "")
        if sub == nil or sub == "" then
            self.title:SetPoint("TOPLEFT", 10, -((self:GetHeight() or 40) / 2 - 7))
        else
            self.title:SetPoint("TOPLEFT", 10, -((self:GetHeight() or 40) / 2 - 13))
        end
        self:SetWidth(math.max(120, math.floor(math.max(strw(self.title), strw(self.sub)) + 22)))
    end
    return f
end

-- A small counter on the screen: an icon, a value, up to 10 marks and a grey note, such as
-- "3/5 [marks] 18 m". chip:Set(icon, value, color, filled, total, note).
function S.Chip(parent, name)
    local f = CreateFrame("Button", name, parent or UIParent)
    f:SetSize(120, 30)
    S.HudPanel(f)
    f.ico = S.IconBox(f, 24)
    f.ico:SetPoint("LEFT", 3, 0)
    f.value = S.Text(f, 14, S.TEXT, "OUTLINE")
    f.value:SetPoint("LEFT", f.ico, "RIGHT", 8, 0)
    f.marks = {}
    f.note = S.Text(f, 12, S.MUTED)
    f.note:SetWordWrap(false)
    function f:Set(icon, value, color, filled, total, note)
        self.ico:SetIcon(icon)
        local c = color or S.TEXT
        self.value:SetText(value or "")
        self.value:SetTextColor(c[1], c[2], c[3], 1)
        total = math.min(total or 0, 10)
        local x = 3 + 24 + 8 + strw(self.value) + 8
        for i = 1, math.max(total, #self.marks) do
            local m = self.marks[i]
            if not m and i <= total then
                m = tex(self, "ARTWORK", 0, S.LINE)
                m:SetSize(8, 10)
                self.marks[i] = m
            end
            if m then
                m:SetShown(i <= total)
                m:ClearAllPoints()
                m:SetPoint("LEFT", x + (i - 1) * 10, 0)
                local on = i <= (filled or 0)
                local mc = on and (color or S.Accent()) or { 1, 1, 1, 0.12 }
                m:SetVertexColor(mc[1], mc[2], mc[3], mc[4] or 1)
            end
        end
        if total > 0 then x = x + total * 10 + 6 end
        self.note:ClearAllPoints()
        self.note:SetPoint("LEFT", x, 0)
        self.note:SetText(note or "")
        self:SetWidth(math.floor(x + ((note and note ~= "") and (strw(self.note) + 10) or 4)))
    end
    return f
end

-- A small list on the screen: a header (icon, title, a grey note on the right) and rows of a
-- coloured tag, a text and a grey note. list:SetRows({ { tag, tagColor, text, right } }, empty).
function S.HudList(name, width, rows, parent)
    local f = CreateFrame("Button", name, parent or UIParent)
    f:SetSize(width or 330, 26 + (rows or 3) * 22)
    S.HudPanel(f)
    f.ico = f:CreateTexture(nil, "ARTWORK")
    f.ico:SetSize(16, 16)
    f.ico:SetPoint("TOPLEFT", 8, -5)
    f.ico:SetTexture("Interface\\AddOns\\" .. tostring(addon) .. "\\icon")
    f.title = S.Text(f, 12)
    f.title:SetPoint("LEFT", f.ico, "RIGHT", 6, 0)
    f.right = S.Text(f, 12, S.FAINT)
    f.right:SetPoint("TOPRIGHT", -8, -7)
    f.right:SetJustifyH("RIGHT")
    local line = S.Divider(f)
    line:SetPoint("TOPLEFT", 1, -26)
    line:SetPoint("TOPRIGHT", -1, -26)
    line:SetHeight(1)
    f.rows = {}
    for i = 1, rows or 3 do
        local r = CreateFrame("Frame", nil, f)
        r:SetHeight(22)
        r:SetPoint("TOPLEFT", 1, -26 - (i - 1) * 22)
        r:SetPoint("TOPRIGHT", -1, -26 - (i - 1) * 22)
        r.tag = S.Badge(r)
        r.tag:SetPoint("LEFT", 7, 0)
        r.text = S.Text(r, 12)
        r.text:SetWordWrap(false)
        r.right = S.Text(r, 12, S.FAINT)
        r.right:SetPoint("RIGHT", -7, 0)
        r.right:SetJustifyH("RIGHT")
        f.rows[i] = r
    end
    function f:SetRows(list, empty)
        for i, r in ipairs(self.rows) do
            local it = list[i]
            r.text:ClearAllPoints()
            if it then
                r.tag:Set(it.tag, it.tagColor)
                r.right:SetText(it.right or "")
                if it.tag and it.tag ~= "" then r.text:SetPoint("LEFT", r.tag, "RIGHT", 6, 0)
                else r.text:SetPoint("LEFT", 8, 0) end
                r.text:SetPoint("RIGHT", r.right, "LEFT", -6, 0)
                r.text:SetText(it.text or "")
                r.text:SetTextColor(S.TEXT[1], S.TEXT[2], S.TEXT[3], 1)
                r:Show()
            elseif i == 1 and empty then
                r.tag:Set(nil)
                r.right:SetText("")
                r.text:SetPoint("LEFT", 8, 0)
                r.text:SetPoint("RIGHT", -8, 0)
                r.text:SetText(empty)
                r.text:SetTextColor(S.FAINT[1], S.FAINT[2], S.FAINT[3], 1)
                r:Show()
            else
                r:Hide()
            end
        end
    end
    return f
end

-- Notices -----------------------------------------------------------------------------------

local KIND = { bad = "BAD", warn = "WARN", good = "GOOD" }

-- A notice card: a coloured stripe on the left (o.kind: bad, warn, good, or the accent), an
-- icon, a title, a grey line, buttons on the right, a close button, and a thin line at the
-- bottom that runs out when the card hides by itself.
-- card:Set{ icon, portrait (a unit), title, text, kind, buttons = { { text, onClick, primary } },
--          seconds, reserve (pixels kept free on the right for a frame of the caller's own) }
function S.ToastFrame(name, parent)
    local t = CreateFrame("Frame", name, parent or UIParent)
    t:SetSize(S.TOAST_W, S.TOAST_H)
    t:SetFrameStrata("DIALOG")
    t:SetClampedToScreen(true)
    t:EnableMouse(true)
    S.HudPanel(t)
    -- The kind shows in the time line and the icon's ring (Gulli Glass has no side stripe).
    t.stripe = tex(t, "ARTWORK", 1, S.Accent())
    t.stripe:SetSize(1, 1)
    t.stripe:SetPoint("TOPLEFT")
    t.stripe:Hide()
    t.ico = S.IconBox(t, 40)
    t.ico:SetPoint("LEFT", 13, 0)
    t.title = S.Text(t, 13)
    t.title:SetWordWrap(false)
    t.text = S.Note(t, 12)
    t.text:SetMaxLines(2)
    t.close = closeButton(t, function() t:Dismiss() end)
    t.close:SetPoint("TOPRIGHT", 0, 0)
    t.track = tex(t, "ARTWORK", 0, { 1, 1, 1, 0.06 })
    t.track:SetPoint("BOTTOMLEFT", S.R_LG, 2)
    t.track:SetPoint("BOTTOMRIGHT", -S.R_LG, 2)
    t.track:SetHeight(2)
    t.timer = tex(t, "ARTWORK", 1, S.Accent())
    t.timer:SetPoint("BOTTOMLEFT", S.R_LG, 2)
    t.timer:SetHeight(2)
    t.buttons = {}
    t:SetScript("OnUpdate", function(self, dt)
        if not self.left then return end
        self.left = self.left - (dt or 0)
        local w = (self:GetWidth() or S.TOAST_W) - 2 * S.R_LG
        self.timer:SetWidth(math.max(1, w * math.max(0, self.left) / self.seconds))
        if self.left <= 0 then self:Dismiss() end
    end)
    function t:Dismiss()
        self.left = nil
        self:Hide()
        if self.restack then self.restack() end
        if self.onClose then self.onClose(self) end
    end
    function t:Set(o)
        local c = o.kind and S[KIND[o.kind] or ""] or S.Accent()
        self.stripe:SetVertexColor(c[1], c[2], c[3], 1)
        self.timer:SetVertexColor(c[1], c[2], c[3], 0.8)
        if o.kind then S.SetBorder(self.ico, c) else S.SetBorder(self.ico, S.RING) end
        if o.portrait and SetPortraitTexture and UnitExists and UnitExists(o.portrait) then
            SetPortraitTexture(self.ico.tex, o.portrait)
            self.ico.tex:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        else
            self.ico.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            self.ico:SetIcon(o.icon)
        end
        self.title:SetText(o.title or "")
        self.text:SetText(o.text or "")
        self.onClose = o.onClose
        local right = -32 - (o.reserve or 0)
        local last
        for i = 1, math.max(#(o.buttons or {}), #self.buttons) do
            local spec = (o.buttons or {})[i]
            local b = self.buttons[i]
            if spec then
                if not b then
                    b = S.Button(self, 60, 28)
                    self.buttons[i] = b
                end
                b.kind = spec.primary and "primary" or "normal"
                paint(b)
                if not spec.primary then b.text:SetTextColor(S.TEXT[1], S.TEXT[2], S.TEXT[3], 1) end
                b:SetText(spec.text)
                b:SetWidth(math.max(56, math.floor(strw(b.text) + 22)))
                b:ClearAllPoints()
                if last then b:SetPoint("RIGHT", last, "LEFT", -5, 0) else b:SetPoint("RIGHT", right, 0) end
                b:SetScript("OnClick", function()
                    if spec.onClick then spec.onClick(self) end
                    if not spec.keep then self:Dismiss() end
                end)
                b:Show()
                last = b
            elseif b then
                b:Hide()
            end
        end
        self.title:ClearAllPoints()
        -- Without a second line the title sits in the middle of the icon.
        self.title:SetPoint("TOPLEFT", self.ico, "TOPRIGHT", 10, (o.text and o.text ~= "") and -3 or -13)
        self.title:SetPoint("RIGHT", last or self.close, "LEFT", last and -8 or (-4 - (o.reserve or 0)), 0)
        self.text:ClearAllPoints()
        self.text:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -3)
        self.text:SetPoint("RIGHT", self.title, "RIGHT", 0, 0)
        self.seconds = o.seconds
        self.left = (o.seconds or 0) > 0 and o.seconds or nil
        self.track:SetShown(self.left ~= nil)
        self.timer:SetShown(self.left ~= nil)
        if self.left then self.timer:SetWidth((self:GetWidth() or S.TOAST_W) - 2 * S.R_LG) end
        self:Show()
    end
    t:Hide()
    return t
end

-- Notices of every Gulli addon share one stack at the top of the screen, so they never cover
-- each other. Each copy of this file uses the same global list.
local function stack()
    GulliHUD = GulliHUD or {}
    GulliHUD.toasts = GulliHUD.toasts or {}
    return GulliHUD
end

local function restack()
    local H = stack()
    -- The hub's Unlock mode can move the stack (GulliHUD.toastAt, from S.ToastPlace).
    local at = H.toastAt
    local x0, y = tonumber(at and at[1]) or 0, tonumber(at and at[2]) or -150
    local keep = {}
    for _, t in ipairs(H.toasts) do
        if t:IsShown() then
            keep[#keep + 1] = t
            -- y counts in screen units; each card has its own scale.
            local k = tonumber((t:GetScale())) or 1
            if k <= 0 then k = 1 end
            local ty = y / k
            local was = rawget(t, "stackY")
            t:ClearAllPoints()
            t:SetPoint("TOP", UIParent, "TOP", x0 / k, ty)
            t.stackY = ty
            -- A card that moves in the stack slides there.
            if was and was ~= ty then S.MotionSlide(t, 0, ty - was, S.SLOW) end
            y = y - ((t:GetHeight() or S.TOAST_H) + 8) * k
        end
    end
    H.toasts = keep
end
S.RestackToasts = restack

-- Shows a notice in the shared stack; the same key replaces its card. Returns the card.
-- o as in ToastFrame:Set, plus key.
function S.Toast(o)
    local H = stack()
    H.byKey = H.byKey or {}
    local key = tostring(addon) .. ":" .. tostring(o.key or "")
    local t = H.byKey[key]
    if not t then
        t = S.ToastFrame(nil, UIParent)
        H.byKey[key] = t
        t.restack = restack
        t:HookScript("OnHide", function() restack() end)
    end
    local onClose = o.onClose
    local fresh = not t:IsShown()
    if fresh then rawset(t, "stackY", nil) end
    S.ApplyScale(t, S.BaseScale())
    t:Set(o)
    t.onClose = onClose
    local found = false
    for _, x in ipairs(H.toasts) do if x == t then found = true end end
    if not found then table.insert(H.toasts, 1, t) end
    restack()
    -- A new card comes down into its place.
    if fresh then S.MotionIn(t, -14, S.SLOW) end
    return t
end

-- Moving ------------------------------------------------------------------------------------

-- Every placeable frame of every Gulli addon goes into one list that all copies of this file
-- share, so the hub's Unlock mode can select, nudge, snap and put back any of them.
local function hud()
    GulliHUD = GulliHUD or {}
    GulliHUD.movers = GulliHUD.movers or {}
    GulliHUD.touched = GulliHUD.touched or {}
    return GulliHUD
end

-- f's scale against UIParent's: the offsets of f's points count in f's own units.
local function ratio(f)
    local k = tonumber((f.GetEffectiveScale and f:GetEffectiveScale()))
    local u = tonumber((UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()))
    if not (k and u) or k <= 0 or u <= 0 then return 1 end
    return k / u
end

local function pointOf(f)
    local p, rel, rp, x, y = f:GetPoint()
    return { p or "CENTER", rel or UIParent, rp or p or "CENTER", tonumber(x) or 0, tonumber(y) or 0 }
end

local function setPoint(f, at)
    f:ClearAllPoints()
    f:SetPoint(at[1], at[2], at[3], at[4], at[5])
end

-- Keeps where the frame stood before its first change in this Unlock session, for Cancel.
local function touch(m)
    local H = hud()
    if not H.touched[m] then H.touched[m] = pointOf(m.frame) end
end

local function saveMover(m)
    local at = pointOf(m.frame)
    if m.opts.save then m.opts.save(at[1], at[3], at[4], at[5]) end
    m:ShowCoords()
end

-- Moves f by dx, dy screen units.
local function shift(f, dx, dy)
    local at = pointOf(f)
    local k = ratio(f)
    at[4], at[5] = at[4] + dx / k, at[5] + dy / k
    setPoint(f, at)
end

-- Puts f's top left corner on the nearest line of a grid whose lines run every step units out
-- from the middle of the screen, like the one the hub draws.
local function snap(f, step)
    local l, t = tonumber((f:GetLeft())), tonumber((f:GetTop()))
    local w, h = tonumber((UIParent:GetWidth())), tonumber((UIParent:GetHeight()))
    if not (l and t and w and h and step and step > 0) then return end
    local k = ratio(f)
    l, t = l * k, t * k
    local nl = w / 2 + math.floor((l - w / 2) / step + 0.5) * step
    local nt = h / 2 + math.floor((t - h / 2) / step + 0.5) * step
    shift(f, nl - l, nt - t)
end

-- Where f's middle is, in screen units from the middle of the screen (x right, y up).
function S.MoverOffset(f)
    local x, y = f:GetCenter()
    local w, h = tonumber((UIParent:GetWidth())), tonumber((UIParent:GetHeight()))
    x, y = tonumber(x), tonumber(y)
    if not (x and y and w and h) then return 0, 0 end
    local k = ratio(f)
    return math.floor(x * k - w / 2 + 0.5), math.floor(y * k - h / 2 + 0.5)
end

-- Makes a frame placeable in the hub's Unlock mode: f:SetMoving(true) lays an accent frame with
-- the name over it. Dragging it moves f (onto the grid while GulliHUD.snap is on), a left click
-- selects it (the arrow keys then move it), a right click puts it back (opts.reset). Each change
-- is saved at once, and the place before the first one is kept, so Cancel can put it back
-- (S.MoversRestore). opts: { label, hint, save = function(point, relPoint, x, y),
-- reset = function() }. Nothing moves in combat.
function S.Mover(f, opts)
    opts = opts or {}
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    local m = CreateFrame("Button", nil, f)
    m:SetPoint("TOPLEFT", -4, 4)
    m:SetPoint("BOTTOMRIGHT", 4, -4)
    m:SetFrameLevel((tonumber((f:GetFrameLevel())) or 0) + 20)
    local a = S.Accent()
    S.Box(m, { a[1], a[2], a[3], 0.12 }, a, S.R_MD)
    m.name = CreateFrame("Frame", nil, m)
    m.name:SetPoint("BOTTOMLEFT", m, "TOPLEFT", 0, 2)
    m.name:SetHeight(18)
    S.Box(m.name, a, a, S.R_SM)
    m.name.text = S.Text(m.name, 12, { 0.05, 0.05, 0.06, 1 })
    m.name.text:SetShadowColor(0, 0, 0, 0)
    m.name.text:SetPoint("LEFT", 5, 0)
    m.name.text:SetText(shortTitle(opts.label))
    m.name:SetWidth(math.floor(strw(m.name.text) + 10))
    -- The selected frame shows where it stands, under its bottom right corner.
    m.coords = CreateFrame("Frame", nil, m)
    m.coords:SetPoint("TOPRIGHT", m, "BOTTOMRIGHT", 0, -2)
    m.coords:SetHeight(18)
    S.Box(m.coords, S.SOLID, S.EDGE, S.R_SM)
    m.coords.text = S.Text(m.coords, 12, S.TEXT)
    m.coords.text:SetPoint("CENTER")
    m.coords:Hide()
    m.frame, m.opts = f, opts
    function m:ShowCoords()
        if not self.selected then self.coords:Hide() return end
        local x, y = S.MoverOffset(self.frame)
        self.coords.text:SetText("X " .. x .. "  Y " .. y)
        self.coords:SetWidth(math.floor(strw(self.coords.text) + 12))
        self.coords:Show()
    end
    local function paint(self)
        if self.off then S.Fill(self, { 0, 0, 0, self.selected and 0.5 or 0.62 })
        else S.Fill(self, { a[1], a[2], a[3], self.selected and 0.3 or 0.12 }) end
    end
    function m:SetSelected(on)
        self.selected = on and true or false
        paint(self)
        self:ShowCoords()
    end
    -- A frame switched off in the Unlock panel stays placeable, but darkened and with `word`
    -- ("hidden") after its name, so the switch shows at once.
    function m:SetOff(off, word)
        off = off and true or false
        if self.off == off and self.offWord == word then return end
        self.off, self.offWord = off, word
        paint(self)
        local name = shortTitle(opts.label)
        self.name.text:SetText(off and word and (name .. "  |cff8a8a8a" .. word .. "|r") or name)
        self.name:SetWidth(math.floor(strw(self.name.text) + 10))
    end
    m:RegisterForDrag("LeftButton")
    m:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    m:SetScript("OnDragStart", function(self)
        if InCombatLockdown and InCombatLockdown() then return end
        S.SelectMover(self)
        touch(self)
        f:StartMoving()
    end)
    m:SetScript("OnDragStop", function(self)
        f:StopMovingOrSizing()
        local H = hud()
        if H.snap then snap(f, H.step or 32) end
        saveMover(self)
    end)
    m:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            S.ResetMover(self)
        else
            S.SelectMover(self)
        end
    end)
    m:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(opts.label or "")
        if opts.hint then GameTooltip:AddLine(opts.hint, S.MUTED[1], S.MUTED[2], S.MUTED[3], true) end
        GameTooltip:Show()
    end)
    m:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    m:Hide()
    f.mover = m
    function f:SetMoving(on)
        self.mover:SetShown(on and true or false)
        if not on and self.mover.selected then S.SelectMover(nil) end
    end
    local H = hud()
    H.movers[#H.movers + 1] = m
    return m
end

-- The mover the arrow keys move (nil for none); GulliHUD.onSelect hears about it.
function S.SelectMover(m)
    local H = hud()
    for _, x in ipairs(H.movers) do
        if x ~= m and x.selected then x:SetSelected(false) end
    end
    if m then m:SetSelected(true) end
    H.selected = m
    if H.onSelect then H.onSelect(m) end
end

-- Moves a mover's frame by dx, dy screen units and saves the place.
function S.NudgeMover(m, dx, dy)
    if not m or (InCombatLockdown and InCombatLockdown()) then return end
    touch(m)
    shift(m.frame, dx, dy)
    saveMover(m)
end

-- Puts a mover's frame back to its module's default place (opts.reset).
function S.ResetMover(m)
    if not (m and m.opts.reset) or (InCombatLockdown and InCombatLockdown()) then return end
    touch(m)
    m.opts.reset()
    m:ShowCoords()
end

-- Cancel: every frame moved in this Unlock session goes back where it stood, and that place is
-- saved again. Commit forgets those places. Both clear the selection.
function S.MoversRestore()
    local H = hud()
    for m, at in pairs(H.touched) do
        setPoint(m.frame, at)
        if m.opts.save then m.opts.save(at[1], at[3], at[4], at[5]) end
    end
    H.touched = {}
    S.SelectMover(nil)
end

function S.MoversCommit()
    hud().touched = {}
    S.SelectMover(nil)
end

-- The notices' place for the stack: { x, y } of the first card's top middle, in screen units from
-- the top middle of the screen, read from a frame placed there (the hub's sample notice).
function S.ToastPlace(f)
    local l, r, t = tonumber((f:GetLeft())), tonumber((f:GetRight())), tonumber((f:GetTop()))
    local w, h = tonumber((UIParent:GetWidth())), tonumber((UIParent:GetHeight()))
    if not (l and r and t and w and h) then return nil end
    local k = ratio(f)
    return { math.floor((l + r) / 2 * k - w / 2 + 0.5), math.floor(t * k - h + 0.5) }
end
