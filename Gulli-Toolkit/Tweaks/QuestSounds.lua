-- Quest progress sounds: a sound when an objective of a quest in the log is done, another when
-- the whole quest is ready to hand in. It compares the log with the last look, so nothing rings
-- for what was done before the switch or the login.

local _, ns = ...

local frame, get
local last

local SOUNDS = {
    objective = function() return SOUNDKIT and SOUNDKIT.MAP_PING or 3175 end,
    complete = function() return SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_COMPLETE or 878 end,
}

-- The log as { [questID] = { done = bool, obj = { [i] = finished } } }.
function ns.QuestSnapshot()
    local out = {}
    local Q = C_QuestLog
    if not Q or not Q.GetNumQuestLogEntries then return out end
    for i = 1, Q.GetNumQuestLogEntries() or 0 do
        local info = Q.GetInfo and Q.GetInfo(i)
        local id = info and not info.isHeader and info.questID
        if id and id > 0 then
            local e = { done = Q.IsComplete and Q.IsComplete(id) == true or false, obj = {} }
            local list = Q.GetQuestObjectives and Q.GetQuestObjectives(id) or {}
            for k, o in ipairs(list) do e.obj[k] = o.finished == true end
            out[id] = e
        end
    end
    return out
end

-- What rang between two looks: "complete", "objective" or nil. A quest new to the log rings
-- nothing, since taking a quest is no progress.
function ns.QuestProgress(before, now)
    local what
    for id, e in pairs(now) do
        local b = before[id]
        if b then
            if e.done and not b.done then return "complete" end
            for k, fin in pairs(e.obj) do
                if fin and b.obj[k] == false then what = "objective" end
            end
        end
    end
    return what
end

local function play(kind)
    if not get or not get(kind) or not PlaySound then return end
    PlaySound(SOUNDS[kind](), "Master")
end

local function look()
    local now = ns.QuestSnapshot()
    if last then
        local what = ns.QuestProgress(last, now)
        if what then play(what) end
    end
    last = now
end

local soon
local function onEvent()
    if soon then return end
    if not (C_Timer and C_Timer.After) then look(); return end
    soon = true
    C_Timer.After(0.2, function() soon = nil; look() end)
end
ns.QuestSoundsEvent = onEvent

ns.AddTweak({
    key = "questSounds", group = "quests", icon = "Interface\\Icons\\INV_Misc_Bell_01",
    defaults = { objective = true, complete = true },
    panel = {
        { kind = "switch", key = "objective", label = ns.L.TWP_SOUND_OBJ },
        { kind = "switch", key = "complete", label = ns.L.TWP_SOUND_DONE },
    },
    enable = function(g)
        get = g
        last = ns.QuestSnapshot()
        frame = frame or CreateFrame("Frame")
        frame:SetScript("OnEvent", onEvent)
        frame:RegisterEvent("QUEST_LOG_UPDATE")
    end,
    disable = function()
        if frame then frame:UnregisterAllEvents() end
        last = nil
    end,
    changed = function(_, _, g) get = g end,
})
