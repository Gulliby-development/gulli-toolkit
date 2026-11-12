local _, ns = ...

-- The same languages as the Runeloader app and every Gulli module. The addon follows the
-- game client's language; English is the base and the fallback.
ns.TAGS = { "en", "de", "es", "fr", "pl", "pt", "ru", "zh" }

local CLIENT = { enUS = "en", enGB = "en", deDE = "de", esES = "es", esMX = "es", frFR = "fr",
                 ptBR = "pt", ptPT = "pt", ruRU = "ru", zhCN = "zh", zhTW = "zh" }

local T = {}

T.en = {
    TITLE = "Gulli Restock",
    NO_MONEY = "not enough money for %s; stopped there.",
    LOW = "running low: %s",
    HAVE = "have %d",
    EMPTY = "Nothing to keep yet. Drop an item below, or add your class reagents.",
    DROP = "Drop an item here to keep it stocked",
    PRESET = "Add class reagents",
    PRESET_NONE = "No class reagents for your class and level.",
    AUTO = "Buy at once when a vendor opens (no preview)",
    PLAN_TITLE = "Restock",
    BUY = "Buy",
    CANCEL = "Cancel",
    TOTAL = "Total: %s",
    SHORT = "not enough money",
    SEC_KEEP = "Keep in the bags",
}

T.de = {
    TITLE = "Gulli Restock",
    NO_MONEY = "nicht genug Geld für %s; dort angehalten.",
    LOW = "wird knapp: %s",
    HAVE = "hast %d",
    EMPTY = "Noch nichts zu halten. Lege unten einen Gegenstand ab oder füge die Reagenzien deiner Klasse hinzu.",
    DROP = "Gegenstand hier ablegen, um ihn vorrätig zu halten",
    PRESET = "Klassenreagenzien hinzufügen",
    PRESET_NONE = "Keine Klassenreagenzien für deine Klasse und Stufe.",
    AUTO = "Sofort kaufen, wenn ein Händler öffnet (ohne Vorschau)",
    PLAN_TITLE = "Auffüllen",
    BUY = "Kaufen",
    CANCEL = "Abbrechen",
    TOTAL = "Gesamt: %s",
    SHORT = "nicht genug Geld",
    SEC_KEEP = "In den Taschen halten",
}

T.es = {
    TITLE = "Gulli Restock",
    NO_MONEY = "no hay dinero suficiente para %s; se detuvo ahí.",
    LOW = "queda poco: %s",
    HAVE = "tienes %d",
    EMPTY = "Aún no hay nada que mantener. Suelta un objeto abajo o añade los componentes de tu clase.",
    DROP = "Suelta aquí un objeto para mantenerlo",
    PRESET = "Añadir componentes de clase",
    PRESET_NONE = "No hay componentes para tu clase y nivel.",
    AUTO = "Comprar al abrir un vendedor (sin vista previa)",
    PLAN_TITLE = "Reponer",
    BUY = "Comprar",
    CANCEL = "Cancelar",
    TOTAL = "Total: %s",
    SHORT = "no hay dinero suficiente",
    SEC_KEEP = "Mantener en las bolsas",
}

T.fr = {
    TITLE = "Gulli Restock",
    NO_MONEY = "pas assez d'argent pour %s ; arrêt ici.",
    LOW = "bientôt épuisé : %s",
    HAVE = "vous avez %d",
    EMPTY = "Rien à garder pour l'instant. Déposez un objet ci-dessous ou ajoutez les composants de votre classe.",
    DROP = "Déposez un objet ici pour le garder en stock",
    PRESET = "Ajouter les composants de classe",
    PRESET_NONE = "Aucun composant pour votre classe et votre niveau.",
    AUTO = "Acheter dès qu'un marchand s'ouvre (sans aperçu)",
    PLAN_TITLE = "Réapprovisionner",
    BUY = "Acheter",
    CANCEL = "Annuler",
    TOTAL = "Total : %s",
    SHORT = "pas assez d'argent",
    SEC_KEEP = "Garder dans les sacs",
}

T.pl = {
    TITLE = "Gulli Restock",
    NO_MONEY = "za mało pieniędzy na %s; zatrzymano.",
    LOW = "kończy się: %s",
    HAVE = "masz %d",
    EMPTY = "Nic jeszcze nie trzymasz. Upuść przedmiot poniżej albo dodaj odczynniki swojej klasy.",
    DROP = "Upuść tu przedmiot, aby trzymać jego zapas",
    PRESET = "Dodaj odczynniki klasy",
    PRESET_NONE = "Brak odczynników dla twojej klasy i poziomu.",
    AUTO = "Kupuj od razu u handlarza (bez podglądu)",
    PLAN_TITLE = "Uzupełnij",
    BUY = "Kup",
    CANCEL = "Anuluj",
    TOTAL = "Razem: %s",
    SHORT = "za mało pieniędzy",
    SEC_KEEP = "Trzymaj w torbach",
}

T.pt = {
    TITLE = "Gulli Restock",
    NO_MONEY = "dinheiro insuficiente para %s; parou aí.",
    LOW = "acabando: %s",
    HAVE = "você tem %d",
    EMPTY = "Nada para manter ainda. Solte um item abaixo ou adicione os reagentes da sua classe.",
    DROP = "Solte um item aqui para mantê-lo em estoque",
    PRESET = "Adicionar reagentes da classe",
    PRESET_NONE = "Não há reagentes para sua classe e nível.",
    AUTO = "Comprar logo que um vendedor abrir (sem prévia)",
    PLAN_TITLE = "Reabastecer",
    BUY = "Comprar",
    CANCEL = "Cancelar",
    TOTAL = "Total: %s",
    SHORT = "dinheiro insuficiente",
    SEC_KEEP = "Manter nas bolsas",
}

T.ru = {
    TITLE = "Gulli Restock",
    NO_MONEY = "не хватает денег на %s; остановлено.",
    LOW = "заканчивается: %s",
    HAVE = "есть %d",
    EMPTY = "Пока нечего пополнять. Перетащите предмет вниз или добавьте реагенты класса.",
    DROP = "Перетащите сюда предмет, чтобы держать запас",
    PRESET = "Добавить реагенты класса",
    PRESET_NONE = "Для вашего класса и уровня реагентов нет.",
    AUTO = "Покупать сразу у торговца (без просмотра)",
    PLAN_TITLE = "Пополнить",
    BUY = "Купить",
    CANCEL = "Отмена",
    TOTAL = "Итого: %s",
    SHORT = "не хватает денег",
    SEC_KEEP = "Держать в сумках",
}

T.zh = {
    TITLE = "Gulli Restock",
    NO_MONEY = "金钱不足以购买 %s，已停止。",
    LOW = "即将用完：%s",
    HAVE = "拥有 %d",
    EMPTY = "还没有要补充的物品。把物品拖到下方，或添加职业材料。",
    DROP = "把物品拖到这里以保持库存",
    PRESET = "添加职业材料",
    PRESET_NONE = "你的职业和等级没有职业材料。",
    AUTO = "打开商人时立即购买（不预览）",
    PLAN_TITLE = "补货",
    BUY = "购买",
    CANCEL = "取消",
    TOTAL = "总计：%s",
    SHORT = "金钱不足",
    SEC_KEEP = "保持在背包中",
}

ns.T = T
ns.lang = CLIENT[GetLocale()] or "en"

ns.L = setmetatable({}, { __index = function(_, key)
    local t = T[ns.lang]
    return (t and t[key]) or T.en[key] or key
end })
