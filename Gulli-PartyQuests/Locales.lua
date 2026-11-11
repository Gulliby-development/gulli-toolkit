local _, ns = ...

-- The same languages as the Runeloader app and every Gulli module. The addon follows the
-- game client's language; English is the base and the fallback.
ns.TAGS = { "en", "de", "es", "fr", "pl", "pt", "ru", "zh" }

local CLIENT = { enUS = "en", enGB = "en", deDE = "de", esES = "es", esMX = "es", frFR = "fr",
                 ptBR = "pt", ptPT = "pt", ruRU = "ru", zhCN = "zh", zhTW = "zh" }

local T = {}

T.en = {
    TITLE = "Party Quests",
    TAB_OURS = "My quests",
    TAB_THEIRS = "Their quests",
    ME = "You",
    SHARE = "Share",
    ASK = "Ask",
    ASK_TEXT = "Can someone share %s with me?",
    GROUP = "group",
    QUEST_N = "Quest %d",
    LEGEND = "Green: has it. Gold: objectives done. Red: does not have it.",
    NO_GROUP = "You are not in a group. Join one to compare quests.",
    NONE_THEIRS = "No quests that only your group has. Members need Gulli Party Quests too for this list.",
}

T.de = {
    TITLE = "Gruppenquests",
    TAB_OURS = "Meine Quests",
    TAB_THEIRS = "Ihre Quests",
    ME = "Du",
    SHARE = "Teilen",
    ASK = "Fragen",
    ASK_TEXT = "Kann mir jemand %s teilen?",
    GROUP = "Gruppe",
    QUEST_N = "Quest %d",
    LEGEND = "Grün: hat sie. Gold: Ziele erfüllt. Rot: hat sie nicht.",
    NO_GROUP = "Du bist in keiner Gruppe. Tritt einer bei, um Quests zu vergleichen.",
    NONE_THEIRS = "Keine Quests, die nur deine Gruppe hat. Dafür brauchen die anderen auch Gulli Party Quests.",
}

T.es = {
    TITLE = "Misiones del grupo",
    TAB_OURS = "Mis misiones",
    TAB_THEIRS = "Sus misiones",
    ME = "Tú",
    SHARE = "Compartir",
    ASK = "Pedir",
    ASK_TEXT = "¿Alguien me comparte %s?",
    GROUP = "grupo",
    QUEST_N = "Misión %d",
    LEGEND = "Verde: la tiene. Dorado: objetivos hechos. Rojo: no la tiene.",
    NO_GROUP = "No estás en un grupo. Únete a uno para comparar misiones.",
    NONE_THEIRS = "No hay misiones que solo tenga tu grupo. Para esta lista también necesitan Gulli Party Quests.",
}

T.fr = {
    TITLE = "Quêtes du groupe",
    TAB_OURS = "Mes quêtes",
    TAB_THEIRS = "Leurs quêtes",
    ME = "Vous",
    SHARE = "Partager",
    ASK = "Demander",
    ASK_TEXT = "Quelqu'un peut me partager %s ?",
    GROUP = "groupe",
    QUEST_N = "Quête %d",
    LEGEND = "Vert : l'a. Or : objectifs faits. Rouge : ne l'a pas.",
    NO_GROUP = "Vous n'êtes pas en groupe. Rejoignez-en un pour comparer les quêtes.",
    NONE_THEIRS = "Aucune quête que seul votre groupe possède. Les membres doivent aussi avoir Gulli Party Quests.",
}

T.pl = {
    TITLE = "Zadania drużyny",
    TAB_OURS = "Moje zadania",
    TAB_THEIRS = "Ich zadania",
    ME = "Ty",
    SHARE = "Udostępnij",
    ASK = "Poproś",
    ASK_TEXT = "Czy ktoś może udostępnić mi %s?",
    GROUP = "grupowe",
    QUEST_N = "Zadanie %d",
    LEGEND = "Zielony: ma je. Złoty: cele wykonane. Czerwony: nie ma go.",
    NO_GROUP = "Nie jesteś w grupie. Dołącz do grupy, by porównać zadania.",
    NONE_THEIRS = "Brak zadań, które ma tylko twoja grupa. Do tej listy inni też potrzebują Gulli Party Quests.",
}

T.pt = {
    TITLE = "Missões do grupo",
    TAB_OURS = "Minhas missões",
    TAB_THEIRS = "Missões deles",
    ME = "Você",
    SHARE = "Compartilhar",
    ASK = "Pedir",
    ASK_TEXT = "Alguém pode compartilhar %s comigo?",
    GROUP = "grupo",
    QUEST_N = "Missão %d",
    LEGEND = "Verde: tem. Dourado: objetivos feitos. Vermelho: não tem.",
    NO_GROUP = "Você não está em um grupo. Entre em um para comparar missões.",
    NONE_THEIRS = "Nenhuma missão que só seu grupo tem. Para esta lista eles também precisam do Gulli Party Quests.",
}

T.ru = {
    TITLE = "Квесты группы",
    TAB_OURS = "Мои квесты",
    TAB_THEIRS = "Их квесты",
    ME = "Вы",
    SHARE = "Поделиться",
    ASK = "Попросить",
    ASK_TEXT = "Поделитесь, пожалуйста, квестом %s?",
    GROUP = "группа",
    QUEST_N = "Квест %d",
    LEGEND = "Зелёный: есть. Золотой: цели выполнены. Красный: нет.",
    NO_GROUP = "Вы не в группе. Вступите в группу, чтобы сравнить квесты.",
    NONE_THEIRS = "Нет квестов, которые есть только у группы. Для этого списка у остальных тоже должен быть Gulli Party Quests.",
}

T.zh = {
    TITLE = "队伍任务",
    TAB_OURS = "我的任务",
    TAB_THEIRS = "他们的任务",
    ME = "你",
    SHARE = "共享",
    ASK = "请求",
    ASK_TEXT = "谁能把%s共享给我？",
    GROUP = "组队",
    QUEST_N = "任务 %d",
    LEGEND = "绿色：有此任务。金色：目标已完成。红色：没有。",
    NO_GROUP = "你不在队伍中。加入队伍后可比较任务。",
    NONE_THEIRS = "没有只有队友才有的任务。队友也需要安装 Gulli Party Quests 才会显示。",
}

ns.T = T
ns.lang = CLIENT[GetLocale()] or "en"

ns.L = setmetatable({}, { __index = function(_, key)
    local t = T[ns.lang]
    return (t and t[key]) or T.en[key] or key
end })
