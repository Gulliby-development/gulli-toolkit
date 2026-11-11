local _, ns = ...

-- The same languages as the Runeloader app and every Gulli module. The addon follows the
-- game client's language; English is the base and the fallback.
ns.TAGS = { "en", "de", "es", "fr", "pl", "pt", "ru", "zh" }

local CLIENT = { enUS = "en", enGB = "en", deDE = "de", esES = "es", esMX = "es", frFR = "fr",
                 ptBR = "pt", ptPT = "pt", ruRU = "ru", zhCN = "zh", zhTW = "zh" }

local T = {}

T.en = {
    TITLE = "Bulletin Board",
    TAB_GROUPS = "Groups", TAB_WTS = "Selling", TAB_WTB = "Buying", TAB_CRAFT = "Crafting",
    TAB_GUILD = "Guilds", TAB_OTHER = "Other",
    MY_LEVEL = "Only dungeons for my level",
    EMPTY = "Nothing here yet. Messages from Trade, General, LookingForGroup, /say and /yell show up here as they come.",
    WHISPER = "Whisper", INVITE = "Invite",
    OTHER_GROUPS = "Other groups",
    LFG = "LFG", LFM = "LFM",
    NOW = "now", AGO_M = "%d min",
    HELP = "/gbul opens the board, /gbul clear empties it.",
    CLEARED = "The board is empty.",
}

T.de = {
    TITLE = "Schwarzes Brett",
    TAB_GROUPS = "Gruppen", TAB_WTS = "Verkauf", TAB_WTB = "Ankauf", TAB_CRAFT = "Handwerk",
    TAB_GUILD = "Gilden", TAB_OTHER = "Sonstiges",
    MY_LEVEL = "Nur Dungeons für meine Stufe",
    EMPTY = "Noch nichts da. Nachrichten aus Handel, Allgemein, SucheNachGruppe, /sagen und /schreien erscheinen hier.",
    WHISPER = "Flüstern", INVITE = "Einladen",
    OTHER_GROUPS = "Andere Gruppen",
    LFG = "LFG", LFM = "LFM",
    NOW = "jetzt", AGO_M = "%d Min.",
    HELP = "/gbul öffnet das Brett, /gbul clear leert es.",
    CLEARED = "Das Brett ist leer.",
}

T.es = {
    TITLE = "Tablón de anuncios",
    TAB_GROUPS = "Grupos", TAB_WTS = "Venta", TAB_WTB = "Compra", TAB_CRAFT = "Oficios",
    TAB_GUILD = "Hermandades", TAB_OTHER = "Otros",
    MY_LEVEL = "Solo mazmorras de mi nivel",
    EMPTY = "Aún no hay nada. Aquí aparecen los mensajes de Comercio, General, BuscarGrupo, /decir y /gritar.",
    WHISPER = "Susurrar", INVITE = "Invitar",
    OTHER_GROUPS = "Otros grupos",
    LFG = "LFG", LFM = "LFM",
    NOW = "ahora", AGO_M = "%d min",
    HELP = "/gbul abre el tablón, /gbul clear lo vacía.",
    CLEARED = "El tablón está vacío.",
}

T.fr = {
    TITLE = "Tableau d'annonces",
    TAB_GROUPS = "Groupes", TAB_WTS = "Ventes", TAB_WTB = "Achats", TAB_CRAFT = "Artisanat",
    TAB_GUILD = "Guildes", TAB_OTHER = "Autres",
    MY_LEVEL = "Seulement les donjons de mon niveau",
    EMPTY = "Rien pour l'instant. Les messages de Commerce, Général, RechercheGroupe, /dire et /crier s'affichent ici.",
    WHISPER = "Chuchoter", INVITE = "Inviter",
    OTHER_GROUPS = "Autres groupes",
    LFG = "LFG", LFM = "LFM",
    NOW = "à l'instant", AGO_M = "%d min",
    HELP = "/gbul ouvre le tableau, /gbul clear le vide.",
    CLEARED = "Le tableau est vide.",
}

T.pl = {
    TITLE = "Tablica ogłoszeń",
    TAB_GROUPS = "Grupy", TAB_WTS = "Sprzedaż", TAB_WTB = "Kupno", TAB_CRAFT = "Rzemiosło",
    TAB_GUILD = "Gildie", TAB_OTHER = "Inne",
    MY_LEVEL = "Tylko lochy na mój poziom",
    EMPTY = "Na razie pusto. Tu pojawiają się wiadomości z Handlu, Ogólnego, SzukamGrupy, /say i /yell.",
    WHISPER = "Szepnij", INVITE = "Zaproś",
    OTHER_GROUPS = "Inne grupy",
    LFG = "LFG", LFM = "LFM",
    NOW = "teraz", AGO_M = "%d min",
    HELP = "/gbul otwiera tablicę, /gbul clear ją czyści.",
    CLEARED = "Tablica jest pusta.",
}

T.pt = {
    TITLE = "Mural de anúncios",
    TAB_GROUPS = "Grupos", TAB_WTS = "Venda", TAB_WTB = "Compra", TAB_CRAFT = "Profissões",
    TAB_GUILD = "Guildas", TAB_OTHER = "Outros",
    MY_LEVEL = "Só masmorras do meu nível",
    EMPTY = "Nada ainda. Aqui aparecem as mensagens de Comércio, Geral, ProcurandoGrupo, /dizer e /gritar.",
    WHISPER = "Sussurrar", INVITE = "Convidar",
    OTHER_GROUPS = "Outros grupos",
    LFG = "LFG", LFM = "LFM",
    NOW = "agora", AGO_M = "%d min",
    HELP = "/gbul abre o mural, /gbul clear o esvazia.",
    CLEARED = "O mural está vazio.",
}

T.ru = {
    TITLE = "Доска объявлений",
    TAB_GROUPS = "Группы", TAB_WTS = "Продажа", TAB_WTB = "Покупка", TAB_CRAFT = "Ремесло",
    TAB_GUILD = "Гильдии", TAB_OTHER = "Прочее",
    MY_LEVEL = "Только подземелья моего уровня",
    EMPTY = "Пока пусто. Сюда попадают сообщения из каналов Торговля, Общий, ПоискСпутников, /сказать и /крик.",
    WHISPER = "Шёпот", INVITE = "Пригласить",
    OTHER_GROUPS = "Другие группы",
    LFG = "LFG", LFM = "LFM",
    NOW = "сейчас", AGO_M = "%d мин",
    HELP = "/gbul открывает доску, /gbul clear очищает её.",
    CLEARED = "Доска очищена.",
}

T.zh = {
    TITLE = "公告板",
    TAB_GROUPS = "组队", TAB_WTS = "出售", TAB_WTB = "收购", TAB_CRAFT = "制造",
    TAB_GUILD = "公会", TAB_OTHER = "其他",
    MY_LEVEL = "只看适合我等级的副本",
    EMPTY = "暂无内容。交易、综合、寻求组队频道以及说话和大喊的消息会显示在这里。",
    WHISPER = "密语", INVITE = "邀请",
    OTHER_GROUPS = "其他队伍",
    LFG = "求组", LFM = "缺人",
    NOW = "刚刚", AGO_M = "%d 分钟",
    HELP = "/gbul 打开公告板，/gbul clear 清空。",
    CLEARED = "公告板已清空。",
}

ns.T = T
ns.lang = CLIENT[GetLocale()] or "en"

ns.L = setmetatable({}, { __index = function(_, key)
    local t = T[ns.lang]
    return (t and t[key]) or T.en[key] or key
end })
