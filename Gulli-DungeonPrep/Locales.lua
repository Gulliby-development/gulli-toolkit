local _, ns = ...

-- The same languages as the Runeloader app and every Gulli module. The addon follows the
-- game client's language; English is the base and the fallback.
ns.TAGS = { "en", "de", "es", "fr", "pl", "pt", "ru", "zh" }

local CLIENT = { enUS = "en", enGB = "en", deDE = "de", esES = "es", esMX = "es", frFR = "fr",
                 ptBR = "pt", ptPT = "pt", ruRU = "ru", zhCN = "zh", zhTW = "zh" }

local T = {}

T.en = {
    TITLE = "Dungeon Prep",
    IN_LOG_N = "In your quest log (%d)",
    TAKE_N = "You can take now (%d)",
    LATER_N = "Not yet (%d)",
    DONE_N = "Done already: %d",
    IN_LOG = "In your quest log",
    WHERE = "%s, %s",
    WHY_LEVEL = "From level %d",
    WHY_EARLIER = "Needs an earlier quest",
    NO_QUESTS = "No quests for you in this dungeon.",
    CHECK_REPAIR = "Gear at %d%%",
    CHECK_BAGS = "%d free bag slots",
    CHECK_FOOD = "%d food and drink",
    CHECK_HEARTH = "Hearthstone ready",
    CHECK_HEARTH_CD = "Hearthstone in %d min",
}

T.de = {
    TITLE = "Dungeon-Vorbereitung",
    IN_LOG_N = "In deinem Questlog (%d)",
    TAKE_N = "Jetzt annehmbar (%d)",
    LATER_N = "Noch nicht (%d)",
    DONE_N = "Schon erledigt: %d",
    IN_LOG = "In deinem Questlog",
    WHERE = "%s, %s",
    WHY_LEVEL = "Ab Stufe %d",
    WHY_EARLIER = "Braucht eine frühere Quest",
    NO_QUESTS = "Keine Quests für dich in diesem Dungeon.",
    CHECK_REPAIR = "Ausrüstung bei %d%%",
    CHECK_BAGS = "%d freie Taschenplätze",
    CHECK_FOOD = "%d Essen und Trinken",
    CHECK_HEARTH = "Ruhestein bereit",
    CHECK_HEARTH_CD = "Ruhestein in %d Min.",
}

T.es = {
    TITLE = "Preparar mazmorra",
    IN_LOG_N = "En tu registro (%d)",
    TAKE_N = "Puedes cogerlas ya (%d)",
    LATER_N = "Todavía no (%d)",
    DONE_N = "Ya hechas: %d",
    IN_LOG = "En tu registro de misiones",
    WHERE = "%s, %s",
    WHY_LEVEL = "Desde el nivel %d",
    WHY_EARLIER = "Necesita una misión anterior",
    NO_QUESTS = "No hay misiones para ti en esta mazmorra.",
    CHECK_REPAIR = "Equipo al %d%%",
    CHECK_BAGS = "%d huecos libres",
    CHECK_FOOD = "%d de comida y bebida",
    CHECK_HEARTH = "Piedra de hogar lista",
    CHECK_HEARTH_CD = "Piedra de hogar en %d min",
}

T.fr = {
    TITLE = "Préparer un donjon",
    IN_LOG_N = "Dans votre journal (%d)",
    TAKE_N = "À prendre maintenant (%d)",
    LATER_N = "Pas encore (%d)",
    DONE_N = "Déjà faites : %d",
    IN_LOG = "Dans votre journal de quêtes",
    WHERE = "%s, %s",
    WHY_LEVEL = "À partir du niveau %d",
    WHY_EARLIER = "Demande une quête précédente",
    NO_QUESTS = "Aucune quête pour vous dans ce donjon.",
    CHECK_REPAIR = "Équipement à %d%%",
    CHECK_BAGS = "%d emplacements libres",
    CHECK_FOOD = "%d nourriture et boisson",
    CHECK_HEARTH = "Pierre de foyer prête",
    CHECK_HEARTH_CD = "Pierre de foyer dans %d min",
}

T.pl = {
    TITLE = "Przed lochem",
    IN_LOG_N = "W dzienniku (%d)",
    TAKE_N = "Do wzięcia teraz (%d)",
    LATER_N = "Jeszcze nie (%d)",
    DONE_N = "Już zrobione: %d",
    IN_LOG = "W dzienniku zadań",
    WHERE = "%s, %s",
    WHY_LEVEL = "Od poziomu %d",
    WHY_EARLIER = "Wymaga wcześniejszego zadania",
    NO_QUESTS = "Brak zadań dla ciebie w tym lochu.",
    CHECK_REPAIR = "Ekwipunek: %d%%",
    CHECK_BAGS = "%d wolnych miejsc",
    CHECK_FOOD = "%d jedzenia i picia",
    CHECK_HEARTH = "Kamień powrotu gotowy",
    CHECK_HEARTH_CD = "Kamień powrotu za %d min",
}

T.pt = {
    TITLE = "Preparar masmorra",
    IN_LOG_N = "No seu registro (%d)",
    TAKE_N = "Dá para pegar agora (%d)",
    LATER_N = "Ainda não (%d)",
    DONE_N = "Já feitas: %d",
    IN_LOG = "No seu registro de missões",
    WHERE = "%s, %s",
    WHY_LEVEL = "A partir do nível %d",
    WHY_EARLIER = "Precisa de uma missão anterior",
    NO_QUESTS = "Nenhuma missão para você nesta masmorra.",
    CHECK_REPAIR = "Equipamento em %d%%",
    CHECK_BAGS = "%d espaços livres",
    CHECK_FOOD = "%d de comida e bebida",
    CHECK_HEARTH = "Pedra de regresso pronta",
    CHECK_HEARTH_CD = "Pedra de regresso em %d min",
}

T.ru = {
    TITLE = "Сборы в подземелье",
    IN_LOG_N = "В журнале (%d)",
    TAKE_N = "Можно взять сейчас (%d)",
    LATER_N = "Пока нельзя (%d)",
    DONE_N = "Уже сделано: %d",
    IN_LOG = "В журнале заданий",
    WHERE = "%s, %s",
    WHY_LEVEL = "С %d уровня",
    WHY_EARLIER = "Нужен предыдущий квест",
    NO_QUESTS = "Для вас в этом подземелье квестов нет.",
    CHECK_REPAIR = "Прочность %d%%",
    CHECK_BAGS = "%d свободных ячеек",
    CHECK_FOOD = "%d еды и питья",
    CHECK_HEARTH = "Камень возвращения готов",
    CHECK_HEARTH_CD = "Камень через %d мин",
}

T.zh = {
    TITLE = "副本准备",
    IN_LOG_N = "任务日志中（%d）",
    TAKE_N = "现在可接（%d）",
    LATER_N = "暂不可接（%d）",
    DONE_N = "已完成：%d",
    IN_LOG = "在你的任务日志中",
    WHERE = "%s，%s",
    WHY_LEVEL = "%d 级可接",
    WHY_EARLIER = "需要先完成前置任务",
    NO_QUESTS = "这个副本没有适合你的任务。",
    CHECK_REPAIR = "装备耐久 %d%%",
    CHECK_BAGS = "背包空格 %d",
    CHECK_FOOD = "食物和饮料 %d",
    CHECK_HEARTH = "炉石可用",
    CHECK_HEARTH_CD = "炉石 %d 分钟后可用",
}

ns.T = T
ns.lang = CLIENT[GetLocale()] or "en"

ns.L = setmetatable({}, { __index = function(_, key)
    local t = T[ns.lang]
    return (t and t[key]) or T.en[key] or key
end })
