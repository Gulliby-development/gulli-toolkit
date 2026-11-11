local _, ns = ...

-- The same languages as the Runeloader app and every Gulli module. The addon follows the
-- game client's language; English is the base and the fallback.
ns.TAGS = { "en", "de", "es", "fr", "pl", "pt", "ru", "zh" }

local CLIENT = { enUS = "en", enGB = "en", deDE = "de", esES = "es", esMX = "es", frFR = "fr",
                 ptBR = "pt", ptPT = "pt", ruRU = "ru", zhCN = "zh", zhTW = "zh" }

local T = {}

T.en = {
    TITLE = "Gulli Merchant",
    SOLD = "sold %d gray items for %s.",
    REPAIRED = "repaired for %s.",
    REPAIRED_GUILD = "repaired from the guild bank for %s.",
    NO_MONEY = "not enough money to repair (%s).",
    NO_VENDOR = "open a vendor first.",
    JUNK = "Gray items in your bags: %d, worth %s.",
    NO_JUNK = "No gray items in your bags.",
    OPT_SELL = "Sell gray items at a vendor",
    OPT_REPAIR = "Repair at a vendor",
    OPT_GUILD = "Use guild money for repairs when allowed",
    SHIFT = "Hold Shift while you open a vendor to skip both once. Protected items are never sold.",
    SELL_NOW = "Sell now",
}

T.de = {
    TITLE = "Gulli Merchant",
    SOLD = "%d graue Gegenstände für %s verkauft.",
    REPAIRED = "für %s repariert.",
    REPAIRED_GUILD = "aus der Gildenbank für %s repariert.",
    NO_MONEY = "nicht genug Geld zum Reparieren (%s).",
    NO_VENDOR = "öffne zuerst einen Händler.",
    JUNK = "Graue Gegenstände in den Taschen: %d, Wert %s.",
    NO_JUNK = "Keine grauen Gegenstände in den Taschen.",
    OPT_SELL = "Graue Gegenstände beim Händler verkaufen",
    OPT_REPAIR = "Beim Händler reparieren",
    OPT_GUILD = "Für Reparaturen Gildengeld nutzen, wenn erlaubt",
    SHIFT = "Halte Umschalt beim Öffnen eines Händlers, um beides einmal zu überspringen. Geschützte Gegenstände werden nie verkauft.",
    SELL_NOW = "Jetzt verkaufen",
}

T.es = {
    TITLE = "Gulli Merchant",
    SOLD = "vendidos %d objetos grises por %s.",
    REPAIRED = "reparado por %s.",
    REPAIRED_GUILD = "reparado con el banco de hermandad por %s.",
    NO_MONEY = "no hay dinero para reparar (%s).",
    NO_VENDOR = "abre primero un vendedor.",
    JUNK = "Objetos grises en tus bolsas: %d, valen %s.",
    NO_JUNK = "No hay objetos grises en tus bolsas.",
    OPT_SELL = "Vender objetos grises al vendedor",
    OPT_REPAIR = "Reparar en el vendedor",
    OPT_GUILD = "Usar dinero de la hermandad para reparar si se permite",
    SHIFT = "Mantén Mayús al abrir un vendedor para saltar ambas cosas una vez. Los objetos protegidos nunca se venden.",
    SELL_NOW = "Vender ahora",
}

T.fr = {
    TITLE = "Gulli Merchant",
    SOLD = "%d objets gris vendus pour %s.",
    REPAIRED = "réparé pour %s.",
    REPAIRED_GUILD = "réparé avec la banque de guilde pour %s.",
    NO_MONEY = "pas assez d'argent pour réparer (%s).",
    NO_VENDOR = "ouvrez d'abord un marchand.",
    JUNK = "Objets gris dans vos sacs : %d, valeur %s.",
    NO_JUNK = "Aucun objet gris dans vos sacs.",
    OPT_SELL = "Vendre les objets gris au marchand",
    OPT_REPAIR = "Réparer chez le marchand",
    OPT_GUILD = "Utiliser l'argent de la guilde pour réparer si permis",
    SHIFT = "Maintenez Maj en ouvrant un marchand pour tout sauter une fois. Les objets protégés ne sont jamais vendus.",
    SELL_NOW = "Vendre",
}

T.pl = {
    TITLE = "Gulli Merchant",
    SOLD = "sprzedano %d szarych przedmiotów za %s.",
    REPAIRED = "naprawiono za %s.",
    REPAIRED_GUILD = "naprawiono z banku gildii za %s.",
    NO_MONEY = "za mało pieniędzy na naprawę (%s).",
    NO_VENDOR = "najpierw otwórz handlarza.",
    JUNK = "Szare przedmioty w torbach: %d, warte %s.",
    NO_JUNK = "Brak szarych przedmiotów w torbach.",
    OPT_SELL = "Sprzedawaj szare przedmioty u handlarza",
    OPT_REPAIR = "Naprawiaj u handlarza",
    OPT_GUILD = "Naprawiaj z pieniędzy gildii, gdy wolno",
    SHIFT = "Przytrzymaj Shift przy otwieraniu handlarza, aby raz pominąć oba. Chronione przedmioty nigdy nie są sprzedawane.",
    SELL_NOW = "Sprzedaj teraz",
}

T.pt = {
    TITLE = "Gulli Merchant",
    SOLD = "%d itens cinza vendidos por %s.",
    REPAIRED = "reparado por %s.",
    REPAIRED_GUILD = "reparado com o banco da guilda por %s.",
    NO_MONEY = "dinheiro insuficiente para reparar (%s).",
    NO_VENDOR = "abra um vendedor primeiro.",
    JUNK = "Itens cinza nas bolsas: %d, valem %s.",
    NO_JUNK = "Nenhum item cinza nas bolsas.",
    OPT_SELL = "Vender itens cinza no vendedor",
    OPT_REPAIR = "Reparar no vendedor",
    OPT_GUILD = "Usar dinheiro da guilda para reparar quando permitido",
    SHIFT = "Segure Shift ao abrir um vendedor para pular os dois uma vez. Itens protegidos nunca são vendidos.",
    SELL_NOW = "Vender agora",
}

T.ru = {
    TITLE = "Gulli Merchant",
    SOLD = "продано серых предметов: %d на %s.",
    REPAIRED = "починено за %s.",
    REPAIRED_GUILD = "починено за счёт гильдии: %s.",
    NO_MONEY = "не хватает денег на ремонт (%s).",
    NO_VENDOR = "сначала откройте торговца.",
    JUNK = "Серых предметов в сумках: %d, на %s.",
    NO_JUNK = "В сумках нет серых предметов.",
    OPT_SELL = "Продавать серое у торговца",
    OPT_REPAIR = "Чиниться у торговца",
    OPT_GUILD = "Чиниться за счёт гильдии, если можно",
    SHIFT = "Удерживайте Shift при открытии торговца, чтобы один раз пропустить и то и другое. Защищённые предметы не продаются.",
    SELL_NOW = "Продать сейчас",
}

T.zh = {
    TITLE = "Gulli Merchant",
    SOLD = "已出售 %d 件灰色物品，获得 %s。",
    REPAIRED = "已修理，花费 %s。",
    REPAIRED_GUILD = "已用公会银行修理，花费 %s。",
    NO_MONEY = "金钱不足以修理（%s）。",
    NO_VENDOR = "请先打开商人。",
    JUNK = "背包中的灰色物品：%d 件，价值 %s。",
    NO_JUNK = "背包中没有灰色物品。",
    OPT_SELL = "在商人处出售灰色物品",
    OPT_REPAIR = "在商人处修理",
    OPT_GUILD = "允许时使用公会资金修理",
    SHIFT = "打开商人时按住 Shift 可跳过一次。受保护的物品永不出售。",
    SELL_NOW = "立即出售",
}

ns.T = T
ns.lang = CLIENT[GetLocale()] or "en"

ns.L = setmetatable({}, { __index = function(_, key)
    local t = T[ns.lang]
    return (t and t[key]) or T.en[key] or key
end })
