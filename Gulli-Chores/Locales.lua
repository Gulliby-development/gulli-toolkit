local _, ns = ...

-- The same languages as the Runeloader app and every Gulli module. The addon follows the
-- game client's language; English is the base and the fallback.
ns.TAGS = { "en", "de", "es", "fr", "pl", "pt", "ru", "zh" }

local CLIENT = { enUS = "en", enGB = "en", deDE = "de", esES = "es", esMX = "es", frFR = "fr",
                 ptBR = "pt", ptPT = "pt", ruRU = "ru", zhCN = "zh", zhTW = "zh" }

local T = {}

T.en = {
    TITLE = "Gulli Chores",
    CD_TRANSMUTE = "Transmute is ready",
    CD_MOONCLOTH = "Mooncloth is ready",
    CD_SALT = "Salt Shaker is ready",
    TASK_TRAINER = "New spells at your trainer",
    TASK_MAIL = "You have mail",
    TASK_RESTED = "Rested XP is full",
    TASK_REPAIR = "Repair: gear at %d%%",
    TASK_BAGS = "Free bag slots: %d",
    LOGIN = "waiting on your other characters: %s",
    FORGET = "Forget character",
    NOTHING = "Nothing to do here.",
    NEXT_CD = "Next cooldown in %s",
    RESTED = "Rested XP: %d%% of a level",
    MONEY = "Money: %s",
    SEEN = "Last played %s ago",
    DAYS = "%d d",
    HOURS = "%d h",
    MINUTES = "%d min",
}

T.de = {
    TITLE = "Gulli Chores",
    CD_TRANSMUTE = "Transmutation ist bereit",
    CD_MOONCLOTH = "Mondstoff ist bereit",
    CD_SALT = "Salzstreuer ist bereit",
    TASK_TRAINER = "Neue Zauber beim Lehrer",
    TASK_MAIL = "Du hast Post",
    TASK_RESTED = "Erholung ist voll",
    TASK_REPAIR = "Reparieren: Ausrüstung bei %d%%",
    TASK_BAGS = "Taschen: %d Plätze frei",
    LOGIN = "bei deinen anderen Charakteren wartet: %s",
    FORGET = "Charakter vergessen",
    NOTHING = "Hier ist nichts zu tun.",
    NEXT_CD = "Nächste Abklingzeit in %s",
    RESTED = "Erholung: %d%% einer Stufe",
    MONEY = "Gold: %s",
    SEEN = "Zuletzt gespielt vor %s",
    DAYS = "%d T",
    HOURS = "%d Std",
    MINUTES = "%d Min",
}

T.es = {
    TITLE = "Gulli Chores",
    CD_TRANSMUTE = "La transmutación está lista",
    CD_MOONCLOTH = "El paño lunar está listo",
    CD_SALT = "El salero está listo",
    TASK_TRAINER = "Hechizos nuevos en tu instructor",
    TASK_MAIL = "Tienes correo",
    TASK_RESTED = "El descanso está lleno",
    TASK_REPAIR = "Reparar: equipo al %d%%",
    TASK_BAGS = "Bolsas: %d huecos libres",
    LOGIN = "pendiente en tus otros personajes: %s",
    FORGET = "Olvidar personaje",
    NOTHING = "Nada que hacer aquí.",
    NEXT_CD = "Siguiente tiempo de reutilización en %s",
    RESTED = "Descanso: %d%% de un nivel",
    MONEY = "Dinero: %s",
    SEEN = "Jugado por última vez hace %s",
    DAYS = "%d d",
    HOURS = "%d h",
    MINUTES = "%d min",
}

T.fr = {
    TITLE = "Gulli Chores",
    CD_TRANSMUTE = "La transmutation est prête",
    CD_MOONCLOTH = "L'étoffe lunaire est prête",
    CD_SALT = "La salière est prête",
    TASK_TRAINER = "Nouveaux sorts chez votre maître",
    TASK_MAIL = "Vous avez du courrier",
    TASK_RESTED = "Le repos est plein",
    TASK_REPAIR = "Réparer : équipement à %d%%",
    TASK_BAGS = "Sacs : %d emplacements libres",
    LOGIN = "en attente sur vos autres personnages : %s",
    FORGET = "Oublier le personnage",
    NOTHING = "Rien à faire ici.",
    NEXT_CD = "Prochain temps de recharge dans %s",
    RESTED = "Repos : %d%% d'un niveau",
    MONEY = "Argent : %s",
    SEEN = "Joué il y a %s",
    DAYS = "%d j",
    HOURS = "%d h",
    MINUTES = "%d min",
}

T.pl = {
    TITLE = "Gulli Chores",
    CD_TRANSMUTE = "Transmutacja gotowa",
    CD_MOONCLOTH = "Księżycowa tkanina gotowa",
    CD_SALT = "Solniczka gotowa",
    TASK_TRAINER = "Nowe zaklęcia u trenera",
    TASK_MAIL = "Masz pocztę",
    TASK_RESTED = "Odpoczynek jest pełny",
    TASK_REPAIR = "Naprawa: ekwipunek na %d%%",
    TASK_BAGS = "Torby: %d wolnych miejsc",
    LOGIN = "czeka na innych postaciach: %s",
    FORGET = "Zapomnij postać",
    NOTHING = "Nic tu do zrobienia.",
    NEXT_CD = "Następny czas odnowienia za %s",
    RESTED = "Odpoczynek: %d%% poziomu",
    MONEY = "Pieniądze: %s",
    SEEN = "Ostatnio grana %s temu",
    DAYS = "%d d",
    HOURS = "%d godz.",
    MINUTES = "%d min",
}

T.pt = {
    TITLE = "Gulli Chores",
    CD_TRANSMUTE = "A transmutação está pronta",
    CD_MOONCLOTH = "O pano lunar está pronto",
    CD_SALT = "O saleiro está pronto",
    TASK_TRAINER = "Feitiços novos no seu instrutor",
    TASK_MAIL = "Você tem correio",
    TASK_RESTED = "O descanso está cheio",
    TASK_REPAIR = "Reparar: equipamento em %d%%",
    TASK_BAGS = "Bolsas: %d espaços livres",
    LOGIN = "esperando nos seus outros personagens: %s",
    FORGET = "Esquecer personagem",
    NOTHING = "Nada a fazer aqui.",
    NEXT_CD = "Próxima recarga em %s",
    RESTED = "Descanso: %d%% de um nível",
    MONEY = "Dinheiro: %s",
    SEEN = "Jogado pela última vez há %s",
    DAYS = "%d d",
    HOURS = "%d h",
    MINUTES = "%d min",
}

T.ru = {
    TITLE = "Gulli Chores",
    CD_TRANSMUTE = "Трансмутация готова",
    CD_MOONCLOTH = "Луноткань готова",
    CD_SALT = "Солонка готова",
    TASK_TRAINER = "У учителя новые заклинания",
    TASK_MAIL = "У вас есть почта",
    TASK_RESTED = "Отдых полон",
    TASK_REPAIR = "Ремонт: снаряжение на %d%%",
    TASK_BAGS = "Сумки: свободно %d",
    LOGIN = "ждёт на других персонажах: %s",
    FORGET = "Забыть персонажа",
    NOTHING = "Здесь делать нечего.",
    NEXT_CD = "Следующее восстановление через %s",
    RESTED = "Отдых: %d%% уровня",
    MONEY = "Деньги: %s",
    SEEN = "Был в игре %s назад",
    DAYS = "%d д",
    HOURS = "%d ч",
    MINUTES = "%d мин",
}

T.zh = {
    TITLE = "Gulli Chores",
    CD_TRANSMUTE = "转化已就绪",
    CD_MOONCLOTH = "月布已就绪",
    CD_SALT = "盐瓶已就绪",
    TASK_TRAINER = "训练师处有新法术",
    TASK_MAIL = "你有新邮件",
    TASK_RESTED = "休息经验已满",
    TASK_REPAIR = "修理：装备耐久 %d%%",
    TASK_BAGS = "背包：剩余 %d 格",
    LOGIN = "其他角色待办：%s",
    FORGET = "忘记角色",
    NOTHING = "这里没有要做的事。",
    NEXT_CD = "下次冷却就绪：%s 后",
    RESTED = "休息经验：一级的 %d%%",
    MONEY = "金钱：%s",
    SEEN = "上次游戏：%s 前",
    DAYS = "%d 天",
    HOURS = "%d 小时",
    MINUTES = "%d 分钟",
}

ns.T = T
ns.lang = CLIENT[GetLocale()] or "en"

ns.L = setmetatable({}, { __index = function(_, key)
    local t = T[ns.lang]
    return (t and t[key]) or T.en[key] or key
end })
