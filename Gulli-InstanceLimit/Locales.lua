local _, ns = ...

-- The same languages as the Runeloader app and every Gulli module. The addon follows the
-- game client's language; English is the base and the fallback.
ns.TAGS = { "en", "de", "es", "fr", "pl", "pt", "ru", "zh" }

local CLIENT = { enUS = "en", enGB = "en", deDE = "de", esES = "es", esMX = "es", frFR = "fr",
                 ptBR = "pt", ptPT = "pt", ruRU = "ru", zhCN = "zh", zhTW = "zh" }

local T = {}

T.en = {
    TITLE = "Instance Limit",
    LEFT_HOUR = "%d of %d entries left this hour",
    LEFT_DAY = "%d of %d today",
    NEXT_FREE = "Next entry free in %s.",
    ALL_FREE = "You can enter a new dungeon now.",
    ENTRIES = "Entries in the last hour",
    NONE = "No dungeon entries in the last hour.",
    LIMIT = "per hour",
    DAY_LIMIT = "per day",
    BADGE = "Show a small counter on the screen",
    RESET = "Reset dungeons",
    RESET_TIP = "Works outside the dungeon, for the group leader or when you play alone.",
    WARN_LAST = "One dungeon entry left this hour.",
    WARN_NONE = "No dungeon entries left. The next one is free in %s.",
    LEARNED = "The game refused a new dungeon. The limit is now %d an hour.",
    AGO = "%s ago",
}

T.de = {
    TITLE = "Instanzlimit",
    LEFT_HOUR = "Noch %d von %d Betretungen diese Stunde",
    LEFT_DAY = "%d von %d heute",
    NEXT_FREE = "Nächste Betretung frei in %s.",
    ALL_FREE = "Du kannst jetzt einen neuen Dungeon betreten.",
    ENTRIES = "Betretungen der letzten Stunde",
    NONE = "Keine Dungeon-Betretungen in der letzten Stunde.",
    LIMIT = "pro Stunde",
    DAY_LIMIT = "pro Tag",
    BADGE = "Einen kleinen Zähler auf dem Bildschirm zeigen",
    RESET = "Dungeons zurücksetzen",
    RESET_TIP = "Geht außerhalb des Dungeons, als Gruppenleiter oder allein.",
    WARN_LAST = "Noch eine Dungeon-Betretung diese Stunde.",
    WARN_NONE = "Keine Dungeon-Betretung mehr frei. Die nächste ist frei in %s.",
    LEARNED = "Das Spiel hat einen neuen Dungeon abgelehnt. Das Limit ist jetzt %d pro Stunde.",
    AGO = "vor %s",
}

T.es = {
    TITLE = "Límite de mazmorras",
    LEFT_HOUR = "Quedan %d de %d entradas esta hora",
    LEFT_DAY = "%d de %d hoy",
    NEXT_FREE = "Siguiente entrada libre en %s.",
    ALL_FREE = "Ya puedes entrar en una mazmorra nueva.",
    ENTRIES = "Entradas de la última hora",
    NONE = "Ninguna entrada a mazmorras en la última hora.",
    LIMIT = "por hora",
    DAY_LIMIT = "por día",
    BADGE = "Mostrar un pequeño contador en pantalla",
    RESET = "Reiniciar mazmorras",
    RESET_TIP = "Funciona fuera de la mazmorra, para el líder o si juegas solo.",
    WARN_LAST = "Queda una entrada a mazmorra esta hora.",
    WARN_NONE = "No quedan entradas. La siguiente estará libre en %s.",
    LEARNED = "El juego rechazó una mazmorra nueva. El límite ahora es %d por hora.",
    AGO = "hace %s",
}

T.fr = {
    TITLE = "Limite d'instances",
    LEFT_HOUR = "%d entrées sur %d restantes cette heure",
    LEFT_DAY = "%d sur %d aujourd'hui",
    NEXT_FREE = "Prochaine entrée libre dans %s.",
    ALL_FREE = "Vous pouvez entrer dans un nouveau donjon.",
    ENTRIES = "Entrées de la dernière heure",
    NONE = "Aucune entrée en donjon dans la dernière heure.",
    LIMIT = "par heure",
    DAY_LIMIT = "par jour",
    BADGE = "Afficher un petit compteur à l'écran",
    RESET = "Réinitialiser les donjons",
    RESET_TIP = "Fonctionne hors du donjon, pour le chef de groupe ou en solo.",
    WARN_LAST = "Il reste une entrée en donjon cette heure.",
    WARN_NONE = "Plus d'entrée en donjon. La prochaine se libère dans %s.",
    LEARNED = "Le jeu a refusé un nouveau donjon. La limite est maintenant %d par heure.",
    AGO = "il y a %s",
}

T.pl = {
    TITLE = "Limit lochów",
    LEFT_HOUR = "Zostało %d z %d wejść w tej godzinie",
    LEFT_DAY = "%d z %d dziś",
    NEXT_FREE = "Następne wejście za %s.",
    ALL_FREE = "Możesz teraz wejść do nowego lochu.",
    ENTRIES = "Wejścia z ostatniej godziny",
    NONE = "Brak wejść do lochów w ostatniej godzinie.",
    LIMIT = "na godzinę",
    DAY_LIMIT = "na dzień",
    BADGE = "Pokaż mały licznik na ekranie",
    RESET = "Resetuj lochy",
    RESET_TIP = "Działa poza lochem, dla lidera grupy lub gdy grasz sam.",
    WARN_LAST = "Zostało jedno wejście do lochu w tej godzinie.",
    WARN_NONE = "Brak wolnych wejść. Następne za %s.",
    LEARNED = "Gra odmówiła nowego lochu. Limit wynosi teraz %d na godzinę.",
    AGO = "%s temu",
}

T.pt = {
    TITLE = "Limite de masmorras",
    LEFT_HOUR = "Restam %d de %d entradas nesta hora",
    LEFT_DAY = "%d de %d hoje",
    NEXT_FREE = "Próxima entrada livre em %s.",
    ALL_FREE = "Você já pode entrar em uma nova masmorra.",
    ENTRIES = "Entradas da última hora",
    NONE = "Nenhuma entrada em masmorra na última hora.",
    LIMIT = "por hora",
    DAY_LIMIT = "por dia",
    BADGE = "Mostrar um pequeno contador na tela",
    RESET = "Reiniciar masmorras",
    RESET_TIP = "Funciona fora da masmorra, para o líder do grupo ou jogando sozinho.",
    WARN_LAST = "Resta uma entrada em masmorra nesta hora.",
    WARN_NONE = "Sem entradas livres. A próxima fica livre em %s.",
    LEARNED = "O jogo recusou uma nova masmorra. O limite agora é %d por hora.",
    AGO = "há %s",
}

T.ru = {
    TITLE = "Лимит подземелий",
    LEFT_HOUR = "Осталось %d из %d входов за час",
    LEFT_DAY = "%d из %d за день",
    NEXT_FREE = "Следующий вход через %s.",
    ALL_FREE = "Можно заходить в новое подземелье.",
    ENTRIES = "Входы за последний час",
    NONE = "За последний час входов в подземелья не было.",
    LIMIT = "в час",
    DAY_LIMIT = "в день",
    BADGE = "Показывать маленький счётчик на экране",
    RESET = "Сбросить подземелья",
    RESET_TIP = "Работает вне подземелья, у лидера группы или в одиночку.",
    WARN_LAST = "Остался один вход в подземелье на этот час.",
    WARN_NONE = "Входов не осталось. Следующий освободится через %s.",
    LEARNED = "Игра не пустила в новое подземелье. Лимит теперь %d в час.",
    AGO = "%s назад",
}

T.zh = {
    TITLE = "副本次数",
    LEFT_HOUR = "本小时还剩 %d / %d 次",
    LEFT_DAY = "今天 %d / %d",
    NEXT_FREE = "下一次可用还需 %s。",
    ALL_FREE = "现在可以进入新副本。",
    ENTRIES = "最近一小时的进入记录",
    NONE = "最近一小时没有进入副本。",
    LIMIT = "每小时",
    DAY_LIMIT = "每天",
    BADGE = "在屏幕上显示小计数器",
    RESET = "重置副本",
    RESET_TIP = "需在副本外，由队长或单人操作。",
    WARN_LAST = "本小时只剩一次进入副本的机会。",
    WARN_NONE = "没有剩余次数。下一次可用还需 %s。",
    LEARNED = "游戏拒绝了新副本。上限改为每小时 %d 次。",
    AGO = "%s 前",
}

ns.T = T
ns.lang = CLIENT[GetLocale()] or "en"

ns.L = setmetatable({}, { __index = function(_, key)
    local t = T[ns.lang]
    return (t and t[key]) or T.en[key] or key
end })
