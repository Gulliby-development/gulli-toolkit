local _, ns = ...

-- The same languages as the Runeloader app and every Gulli module. The addon follows the
-- game client's language; English is the base and the fallback.
ns.TAGS = { "en", "de", "es", "fr", "pl", "pt", "ru", "zh" }

local CLIENT = { enUS = "en", enGB = "en", deDE = "de", esES = "es", esMX = "es", frFR = "fr",
                 ptBR = "pt", ptPT = "pt", ruRU = "ru", zhCN = "zh", zhTW = "zh" }

local T = {}

T.en = {
    TITLE = "Gulli XP",
    RATE = "%s XP/h",
    KILLS = "%d kills",
    LEFT = "To the next level: %s XP (%d%% done)",
    TO_LEVEL = "Next level in %s",
    NO_RATE = "Next level: kill or quest a little first",
    FROM_KILLS = "Kills: %d, %s XP",
    FROM_QUESTS = "Quests: %d, %s XP",
    RESTED = "Rested: %s XP",
    SESSION = "This session: %s, %s XP",
    OPT_BAR = "Show the bar on screen",
    RESET = "Start again",
    HM = "%d h %d min",
    M = "%d min",
    STAT_RATE = "XP per hour",
    STAT_TIME = "To the next level",
    STAT_KILLS = "Kills to level",
    SEC_SESSION = "This session",
}

T.de = {
    TITLE = "Gulli XP",
    RATE = "%s EP/h",
    KILLS = "%d Kills",
    LEFT = "Bis zur nächsten Stufe: %s EP (%d%% geschafft)",
    TO_LEVEL = "Nächste Stufe in %s",
    NO_RATE = "Nächste Stufe: erst etwas töten oder questen",
    FROM_KILLS = "Kills: %d, %s EP",
    FROM_QUESTS = "Quests: %d, %s EP",
    RESTED = "Erholt: %s EP",
    SESSION = "Diese Sitzung: %s, %s EP",
    OPT_BAR = "Leiste auf dem Bildschirm zeigen",
    RESET = "Neu starten",
    HM = "%d Std %d Min",
    M = "%d Min",
    STAT_RATE = "EP pro Stunde",
    STAT_TIME = "Bis zur nächsten Stufe",
    STAT_KILLS = "Kills bis zur Stufe",
    SEC_SESSION = "Diese Sitzung",
}

T.es = {
    TITLE = "Gulli XP",
    RATE = "%s PX/h",
    KILLS = "%d muertes",
    LEFT = "Al siguiente nivel: %s PX (%d%% hecho)",
    TO_LEVEL = "Siguiente nivel en %s",
    NO_RATE = "Siguiente nivel: mata o haz misiones un poco antes",
    FROM_KILLS = "Muertes: %d, %s PX",
    FROM_QUESTS = "Misiones: %d, %s PX",
    RESTED = "Descanso: %s PX",
    SESSION = "Esta sesión: %s, %s PX",
    OPT_BAR = "Mostrar la barra en pantalla",
    RESET = "Empezar de nuevo",
    HM = "%d h %d min",
    M = "%d min",
    STAT_RATE = "PX por hora",
    STAT_TIME = "Hasta el siguiente nivel",
    STAT_KILLS = "Muertes hasta subir",
    SEC_SESSION = "Esta sesión",
}

T.fr = {
    TITLE = "Gulli XP",
    RATE = "%s XP/h",
    KILLS = "%d victimes",
    LEFT = "Jusqu'au niveau suivant : %s XP (%d%% fait)",
    TO_LEVEL = "Niveau suivant dans %s",
    NO_RATE = "Niveau suivant : tuez ou faites des quêtes d'abord",
    FROM_KILLS = "Victimes : %d, %s XP",
    FROM_QUESTS = "Quêtes : %d, %s XP",
    RESTED = "Repos : %s XP",
    SESSION = "Cette session : %s, %s XP",
    OPT_BAR = "Afficher la barre à l'écran",
    RESET = "Recommencer",
    HM = "%d h %d min",
    M = "%d min",
    STAT_RATE = "XP par heure",
    STAT_TIME = "Jusqu'au niveau suivant",
    STAT_KILLS = "Victimes avant le niveau",
    SEC_SESSION = "Cette session",
}

T.pl = {
    TITLE = "Gulli XP",
    RATE = "%s PD/h",
    KILLS = "%d zabójstw",
    LEFT = "Do następnego poziomu: %s PD (%d%% zrobione)",
    TO_LEVEL = "Następny poziom za %s",
    NO_RATE = "Następny poziom: najpierw trochę zabij lub zrób zadania",
    FROM_KILLS = "Zabójstwa: %d, %s PD",
    FROM_QUESTS = "Zadania: %d, %s PD",
    RESTED = "Odpoczynek: %s PD",
    SESSION = "Ta sesja: %s, %s PD",
    OPT_BAR = "Pokazuj pasek na ekranie",
    RESET = "Zacznij od nowa",
    HM = "%d godz. %d min",
    M = "%d min",
    STAT_RATE = "PD na godzinę",
    STAT_TIME = "Do następnego poziomu",
    STAT_KILLS = "Zabójstw do poziomu",
    SEC_SESSION = "Ta sesja",
}

T.pt = {
    TITLE = "Gulli XP",
    RATE = "%s XP/h",
    KILLS = "%d abates",
    LEFT = "Até o próximo nível: %s XP (%d%% feito)",
    TO_LEVEL = "Próximo nível em %s",
    NO_RATE = "Próximo nível: mate ou faça missões um pouco antes",
    FROM_KILLS = "Abates: %d, %s XP",
    FROM_QUESTS = "Missões: %d, %s XP",
    RESTED = "Descanso: %s XP",
    SESSION = "Esta sessão: %s, %s XP",
    OPT_BAR = "Mostrar a barra na tela",
    RESET = "Recomeçar",
    HM = "%d h %d min",
    M = "%d min",
    STAT_RATE = "XP por hora",
    STAT_TIME = "Até o próximo nível",
    STAT_KILLS = "Abates até o nível",
    SEC_SESSION = "Esta sessão",
}

T.ru = {
    TITLE = "Gulli XP",
    RATE = "%s опыта/ч",
    KILLS = "%d убийств",
    LEFT = "До уровня: %s опыта (пройдено %d%%)",
    TO_LEVEL = "Уровень через %s",
    NO_RATE = "До уровня: сначала убейте кого-нибудь или сдайте квест",
    FROM_KILLS = "Убийства: %d, %s опыта",
    FROM_QUESTS = "Квесты: %d, %s опыта",
    RESTED = "Отдых: %s опыта",
    SESSION = "Эта сессия: %s, %s опыта",
    OPT_BAR = "Показывать полосу на экране",
    RESET = "Начать заново",
    HM = "%d ч %d мин",
    M = "%d мин",
    STAT_RATE = "Опыта в час",
    STAT_TIME = "До уровня",
    STAT_KILLS = "Убийств до уровня",
    SEC_SESSION = "Эта сессия",
}

T.zh = {
    TITLE = "Gulli XP",
    RATE = "每小时 %s 经验",
    KILLS = "%d 次击杀",
    LEFT = "距下一级：%s 经验（已完成 %d%%）",
    TO_LEVEL = "%s 后升级",
    NO_RATE = "升级时间：先击杀或完成任务",
    FROM_KILLS = "击杀：%d 次，%s 经验",
    FROM_QUESTS = "任务：%d 个，%s 经验",
    RESTED = "休息：%s 经验",
    SESSION = "本次：%s，%s 经验",
    OPT_BAR = "在屏幕上显示经验条",
    RESET = "重新开始",
    HM = "%d 小时 %d 分钟",
    M = "%d 分钟",
    STAT_RATE = "每小时经验",
    STAT_TIME = "距下一级",
    STAT_KILLS = "升级所需击杀",
    SEC_SESSION = "本次登录",
}

ns.T = T
ns.lang = CLIENT[GetLocale()] or "en"

ns.L = setmetatable({}, { __index = function(_, key)
    local t = T[ns.lang]
    return (t and t[key]) or T.en[key] or key
end })
