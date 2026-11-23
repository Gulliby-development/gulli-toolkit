-- Right-click guild invite: an "Invite to guild" item in the menu of a player's name (chat, the
-- target, the group). The game does not let an addon invite, so the item writes /ginvite with
-- the name into the chat box and the player's Enter sends it. Shown only to a player who may
-- invite, and never for the player's own name.

local _, ns = ...
local L = ns.L

local TAGS = { "MENU_UNIT_FRIEND", "MENU_UNIT_PLAYER", "MENU_UNIT_TARGET", "MENU_UNIT_PARTY",
    "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_COMMUNITIES_GUILD_MEMBER", "MENU_UNIT_CHAT_ROSTER" }
local running, added

local function readable(v)
    return type(v) == "string" and v ~= "" and not (issecretvalue and issecretvalue(v))
end

-- The name a menu is about, or nil when it is no player, the player, or not readable.
function ns.InviteName(context)
    if type(context) ~= "table" then return nil end
    local name = context.name
    if not readable(name) and context.unit and UnitIsPlayer and UnitIsPlayer(context.unit) then
        local n, realm = UnitName(context.unit)
        if readable(n) then name = (readable(realm) and (n .. "-" .. realm)) or n end
    end
    if not readable(name) then return nil end
    if context.unit and UnitIsPlayer and not UnitIsPlayer(context.unit) then return nil end
    local me = UnitName("player")
    if name:match("^([^%-]+)") == me then return nil end
    return name
end

function ns.CanInvite()
    if IsInGuild and not IsInGuild() then return false end
    if CanGuildInvite then return CanGuildInvite() == true end
    return false
end

-- The text the chat box gets.
function ns.InviteText(name) return "/ginvite " .. name end

local function openChat(text)
    if ChatFrameUtil and ChatFrameUtil.OpenChat then ChatFrameUtil.OpenChat(text)
    elseif ChatFrame_OpenChat then ChatFrame_OpenChat(text) end
end

function ns.GuildInviteMenu(_, root, context)
    if not running or not root then return end
    if not ns.CanInvite() then return end
    local name = ns.InviteName(context)
    if not name then return end
    root:CreateDivider()
    root:CreateButton(L.TW_GI_MENU, function() openChat(ns.InviteText(name)) end)
end

ns.AddTweak({
    key = "guildInvite", group = "people", icon = "Interface\\Icons\\INV_Shirt_GuildTabard_01", star = true,
    enable = function()
        running = true
        if added or not (Menu and Menu.ModifyMenu) then return end
        added = true
        for _, tag in ipairs(TAGS) do
            pcall(Menu.ModifyMenu, tag, function(...) return ns.GuildInviteMenu(...) end)
        end
    end,
    disable = function() running = false end,
})
