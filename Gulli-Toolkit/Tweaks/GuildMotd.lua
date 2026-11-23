-- Guild message of the day: a notice at login and whenever it changes, since the chat line is
-- easy to miss.

local _, ns = ...

local frame, last

local function show(text)
    if type(text) ~= "string" or text == "" or text == last then return end
    if issecretvalue and issecretvalue(text) then return end
    last = text
    local S = ns.Skin
    if not S or not S.Toast then return end
    S.Toast({ key = "guildMotd", icon = "Interface\\Icons\\INV_Misc_Note_01", title = ns.L.TW_GUILDMOTD,
        text = text, seconds = 20 })
end

local function current()
    if IsInGuild and not IsInGuild() then return nil end
    return GetGuildRosterMOTD and GetGuildRosterMOTD() or nil
end

local function onEvent(_, event, text)
    if event == "GUILD_MOTD" then show(text) else show(current()) end
end

ns.AddTweak({
    key = "guildMotd", group = "people", icon = "Interface\\Icons\\INV_Misc_Note_01",
    enable = function()
        frame = frame or CreateFrame("Frame")
        frame:SetScript("OnEvent", onEvent)
        frame:RegisterEvent("GUILD_MOTD")
        frame:RegisterEvent("PLAYER_GUILD_UPDATE")
        show(current())
    end,
    disable = function()
        if frame then frame:UnregisterAllEvents() end
        last = nil
    end,
})

ns.GuildMotdEvent = onEvent
