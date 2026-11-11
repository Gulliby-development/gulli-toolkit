local _, ns = ...

-- The same languages as the Runeloader app and every Gulli module. The addon follows the
-- game client's language; English is the base and the fallback.
ns.TAGS = { "en", "de", "es", "fr", "pl", "pt", "ru", "zh" }

local CLIENT = { enUS = "en", enGB = "en", deDE = "de", esES = "es", esMX = "es", frFR = "fr",
                 ptBR = "pt", ptPT = "pt", ruRU = "ru", zhCN = "zh", zhTW = "zh" }

local T = {}

T.en = {
    TITLE = "Gulli Tooltip",
    STACK = "Stack of %d",
    QUEST = "Quest: %s",
    ITEM_ID = "Item ID",
    NPC_ID = "NPC ID",
    OPT_PRICE = "Vendor price of a full stack",
    OPT_QUEST = "Quests in your log that need the item",
    OPT_ID = "Item and NPC ids",
}

T.de = {
    TITLE = "Gulli Tooltip",
    STACK = "Stapel von %d",
    QUEST = "Quest: %s",
    ITEM_ID = "Gegenstands-ID",
    NPC_ID = "NPC-ID",
    OPT_PRICE = "Händlerpreis eines vollen Stapels",
    OPT_QUEST = "Quests im Log, die den Gegenstand brauchen",
    OPT_ID = "Gegenstands- und NPC-IDs",
}

T.es = {
    TITLE = "Gulli Tooltip",
    STACK = "Montón de %d",
    QUEST = "Misión: %s",
    ITEM_ID = "ID de objeto",
    NPC_ID = "ID de PNJ",
    OPT_PRICE = "Precio de venta de un montón entero",
    OPT_QUEST = "Misiones del registro que necesitan el objeto",
    OPT_ID = "IDs de objetos y PNJ",
}

T.fr = {
    TITLE = "Gulli Tooltip",
    STACK = "Pile de %d",
    QUEST = "Quête : %s",
    ITEM_ID = "ID d'objet",
    NPC_ID = "ID de PNJ",
    OPT_PRICE = "Prix de vente d'une pile pleine",
    OPT_QUEST = "Quêtes du journal qui demandent l'objet",
    OPT_ID = "IDs d'objets et de PNJ",
}

T.pl = {
    TITLE = "Gulli Tooltip",
    STACK = "Stos %d",
    QUEST = "Zadanie: %s",
    ITEM_ID = "ID przedmiotu",
    NPC_ID = "ID NPC",
    OPT_PRICE = "Cena pełnego stosu u handlarza",
    OPT_QUEST = "Zadania z dziennika, które potrzebują przedmiotu",
    OPT_ID = "ID przedmiotów i NPC",
}

T.pt = {
    TITLE = "Gulli Tooltip",
    STACK = "Pilha de %d",
    QUEST = "Missão: %s",
    ITEM_ID = "ID do item",
    NPC_ID = "ID do PNJ",
    OPT_PRICE = "Preço de venda de uma pilha cheia",
    OPT_QUEST = "Missões do registro que precisam do item",
    OPT_ID = "IDs de itens e PNJs",
}

T.ru = {
    TITLE = "Gulli Tooltip",
    STACK = "Стопка из %d",
    QUEST = "Квест: %s",
    ITEM_ID = "ID предмета",
    NPC_ID = "ID NPC",
    OPT_PRICE = "Цена полной стопки у торговца",
    OPT_QUEST = "Квесты в журнале, которым нужен предмет",
    OPT_ID = "ID предметов и NPC",
}

T.zh = {
    TITLE = "Gulli Tooltip",
    STACK = "%d 个一组",
    QUEST = "任务：%s",
    ITEM_ID = "物品 ID",
    NPC_ID = "NPC ID",
    OPT_PRICE = "整组物品的商人价格",
    OPT_QUEST = "任务日志中需要该物品的任务",
    OPT_ID = "物品和 NPC 的 ID",
}

ns.T = T
ns.lang = CLIENT[GetLocale()] or "en"

ns.L = setmetatable({}, { __index = function(_, key)
    local t = T[ns.lang]
    return (t and t[key]) or T.en[key] or key
end })
