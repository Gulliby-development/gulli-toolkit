local _, ns = ...

-- The same languages as the Runeloader app and every Gulli module. The addon follows the
-- game client's language; English is the base and the fallback.
ns.TAGS = { "en", "de", "es", "fr", "pl", "pt", "ru", "zh" }

local CLIENT = { enUS = "en", enGB = "en", deDE = "de", esES = "es", esMX = "es", frFR = "fr",
                 ptBR = "pt", ptPT = "pt", ruRU = "ru", zhCN = "zh", zhTW = "zh" }

local T = {}

T.en = {
    TITLE = "Bag Space",
    SPACE = "Free: %d of %d slots",
    WANT = "Free up",
    PLAN = "Plan",
    MAYBE = "maybe",
    SUMMARY = "Frees %d slots (%d by merging stacks).",
    SELL = "Sell",
    DELETE = "Delete",
    NOTE_SELL = "You are at a vendor: the ticked items are sold. You can buy back the last 12.",
    NOTE_DELETE = "The ticked items are deleted. Open a vendor first to sell them instead.",
    NOTHING = "No junk to remove. Gray items and white gear show up here.",
    ONLY_MERGE = "Merging stacks frees %d slots.",
    ALMOST_FULL = "Your bags are almost full: %d free slots. /gbs frees space.",
    NOTE_SELL_MANY = "%d items will be sold: only the last 12 can be bought back.",
    LEFTOVER = "The game kept %d items. Press OK again for them.",
}

T.de = {
    TITLE = "Taschenplatz",
    SPACE = "Frei: %d von %d Plätzen",
    WANT = "Freimachen:",
    PLAN = "Planen",
    MAYBE = "vielleicht",
    SUMMARY = "Macht %d Plätze frei (%d durch Stapeln).",
    SELL = "Verkaufen",
    DELETE = "Löschen",
    NOTE_SELL = "Du bist beim Händler: angehakte Gegenstände werden verkauft. Die letzten 12 kannst du zurückkaufen.",
    NOTE_DELETE = "Angehakte Gegenstände werden gelöscht. Öffne erst einen Händler, um sie zu verkaufen.",
    NOTHING = "Kein Kram zum Entfernen. Graue Gegenstände und weiße Ausrüstung erscheinen hier.",
    ONLY_MERGE = "Stapeln macht %d Plätze frei.",
    ALMOST_FULL = "Deine Taschen sind fast voll: %d freie Plätze. /gbs schafft Platz.",
    NOTE_SELL_MANY = "%d Gegenstände werden verkauft: nur die letzten 12 lassen sich zurückkaufen.",
    LEFTOVER = "Das Spiel hat %d Gegenstände behalten. Drücke noch einmal OK dafür.",
}

T.es = {
    TITLE = "Espacio en bolsas",
    SPACE = "Libres: %d de %d huecos",
    WANT = "Liberar",
    PLAN = "Planear",
    MAYBE = "quizá",
    SUMMARY = "Libera %d huecos (%d juntando montones).",
    SELL = "Vender",
    DELETE = "Borrar",
    NOTE_SELL = "Estás en un vendedor: se venden los objetos marcados. Puedes recomprar los últimos 12.",
    NOTE_DELETE = "Los objetos marcados se borran. Abre un vendedor antes para venderlos.",
    NOTHING = "No hay basura que quitar. Aquí salen los objetos grises y el equipo blanco.",
    ONLY_MERGE = "Juntar montones libera %d huecos.",
    ALMOST_FULL = "Tus bolsas están casi llenas: %d huecos libres. /gbs libera espacio.",
    NOTE_SELL_MANY = "Se venderán %d objetos: solo los últimos 12 se pueden recomprar.",
    LEFTOVER = "El juego se quedó %d objetos. Pulsa OK otra vez para ellos.",
}

T.fr = {
    TITLE = "Place dans les sacs",
    SPACE = "Libres : %d emplacements sur %d",
    WANT = "Libérer",
    PLAN = "Préparer",
    MAYBE = "peut-être",
    SUMMARY = "Libère %d emplacements (%d en regroupant les piles).",
    SELL = "Vendre",
    DELETE = "Supprimer",
    NOTE_SELL = "Vous êtes chez un marchand : les objets cochés sont vendus. Vous pouvez racheter les 12 derniers.",
    NOTE_DELETE = "Les objets cochés sont supprimés. Ouvrez d'abord un marchand pour les vendre.",
    NOTHING = "Rien à retirer. Les objets gris et l'équipement blanc s'affichent ici.",
    ONLY_MERGE = "Regrouper les piles libère %d emplacements.",
    ALMOST_FULL = "Vos sacs sont presque pleins : %d emplacements libres. /gbs fait de la place.",
    NOTE_SELL_MANY = "%d objets seront vendus : seuls les 12 derniers pourront être rachetés.",
    LEFTOVER = "Le jeu a gardé %d objets. Appuyez encore sur OK pour eux.",
}

T.pl = {
    TITLE = "Miejsce w torbach",
    SPACE = "Wolne: %d z %d miejsc",
    WANT = "Zwolnij",
    PLAN = "Zaplanuj",
    MAYBE = "może",
    SUMMARY = "Zwalnia %d miejsc (%d przez łączenie stosów).",
    SELL = "Sprzedaj",
    DELETE = "Usuń",
    NOTE_SELL = "Jesteś u handlarza: zaznaczone przedmioty zostaną sprzedane. Ostatnie 12 możesz odkupić.",
    NOTE_DELETE = "Zaznaczone przedmioty zostaną usunięte. Otwórz najpierw handlarza, by je sprzedać.",
    NOTHING = "Brak śmieci do usunięcia. Tu pojawiają się szare przedmioty i biały ekwipunek.",
    ONLY_MERGE = "Łączenie stosów zwalnia %d miejsc.",
    ALMOST_FULL = "Torby są prawie pełne: %d wolnych miejsc. /gbs zwalnia miejsce.",
    NOTE_SELL_MANY = "Zostanie sprzedanych %d przedmiotów: odkupić można tylko ostatnie 12.",
    LEFTOVER = "Gra zatrzymała %d przedmiotów. Naciśnij OK jeszcze raz.",
}

T.pt = {
    TITLE = "Espaço nas bolsas",
    SPACE = "Livres: %d de %d espaços",
    WANT = "Liberar",
    PLAN = "Planejar",
    MAYBE = "talvez",
    SUMMARY = "Libera %d espaços (%d juntando pilhas).",
    SELL = "Vender",
    DELETE = "Apagar",
    NOTE_SELL = "Você está num vendedor: os itens marcados são vendidos. Dá para recomprar os últimos 12.",
    NOTE_DELETE = "Os itens marcados são apagados. Abra um vendedor antes para vendê-los.",
    NOTHING = "Nenhum lixo para tirar. Itens cinza e equipamento branco aparecem aqui.",
    ONLY_MERGE = "Juntar pilhas libera %d espaços.",
    ALMOST_FULL = "Suas bolsas estão quase cheias: %d espaços livres. /gbs libera espaço.",
    NOTE_SELL_MANY = "%d itens serão vendidos: só os últimos 12 podem ser recomprados.",
    LEFTOVER = "O jogo manteve %d itens. Aperte OK de novo para eles.",
}

T.ru = {
    TITLE = "Место в сумках",
    SPACE = "Свободно: %d из %d ячеек",
    WANT = "Освободить",
    PLAN = "Подобрать",
    MAYBE = "возможно",
    SUMMARY = "Освободит %d ячеек (%d за счёт стопок).",
    SELL = "Продать",
    DELETE = "Удалить",
    NOTE_SELL = "Вы у торговца: отмеченное будет продано. Последние 12 можно выкупить обратно.",
    NOTE_DELETE = "Отмеченное будет удалено. Откройте торговца, чтобы продать вместо этого.",
    NOTHING = "Хлама нет. Здесь появляются серые предметы и белая экипировка.",
    ONLY_MERGE = "Объединение стопок освободит %d ячеек.",
    ALMOST_FULL = "Сумки почти полны: свободно %d ячеек. /gbs освободит место.",
    NOTE_SELL_MANY = "Будет продано предметов: %d. Выкупить можно только последние 12.",
    LEFTOVER = "Игра не убрала предметов: %d. Нажмите OK ещё раз.",
}

T.zh = {
    TITLE = "背包空间",
    SPACE = "空格：%d / %d",
    WANT = "腾出",
    PLAN = "计算",
    MAYBE = "可选",
    SUMMARY = "可腾出 %d 格（合并堆叠 %d 格）。",
    SELL = "出售",
    DELETE = "删除",
    NOTE_SELL = "你在商人处：勾选的物品会被出售，最后 12 件可以买回。",
    NOTE_DELETE = "勾选的物品会被删除。先打开商人即可改为出售。",
    NOTHING = "没有可清理的杂物。灰色物品和白色装备会显示在这里。",
    ONLY_MERGE = "合并堆叠可腾出 %d 格。",
    ALMOST_FULL = "背包快满了：剩余 %d 格。/gbs 可腾出空间。",
    NOTE_SELL_MANY = "将出售 %d 件物品：只有最后 12 件可以买回。",
    LEFTOVER = "游戏保留了 %d 件物品。再按一次确定处理它们。",
}

ns.T = T
ns.lang = CLIENT[GetLocale()] or "en"

ns.L = setmetatable({}, { __index = function(_, key)
    local t = T[ns.lang]
    return (t and t[key]) or T.en[key] or key
end })
