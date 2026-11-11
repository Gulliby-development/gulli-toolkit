local _, ns = ...

-- The same languages as the Runeloader app and every Gulli module. The addon follows the
-- game client's language; English is the base and the fallback.
ns.TAGS = { "en", "de", "es", "fr", "pl", "pt", "ru", "zh" }

local CLIENT = { enUS = "en", enGB = "en", deDE = "de", esES = "es", esMX = "es", frFR = "fr",
                 ptBR = "pt", ptPT = "pt", ruRU = "ru", zhCN = "zh", zhTW = "zh" }

local T = {}

T.en = {
    TITLE = "Gulli Loot",
    ROLLED = "%s on %s.",
    RULE_ASK = "Ask me",
    RULE_NEED = "Need",
    RULE_GREED = "Greed",
    RULE_PASS = "Pass",
    Q0 = "Gray",
    Q1 = "White",
    Q2 = "Green",
    NOTE = "Bind-on-pickup and better items are always yours to roll. An item rule below wins over its quality.",
    NO_ITEMS = "No item rules yet. Drop an item below to add one.",
    DROP = "Drop an item here to give it a rule",
    OPT_REPORT = "Say in chat what was rolled",
}

T.de = {
    TITLE = "Gulli Loot",
    ROLLED = "%s auf %s.",
    RULE_ASK = "Fragen",
    RULE_NEED = "Bedarf",
    RULE_GREED = "Gier",
    RULE_PASS = "Passen",
    Q0 = "Grau",
    Q1 = "Weiß",
    Q2 = "Grün",
    NOTE = "Beim Aufheben gebundene und bessere Gegenstände würfelst immer du. Eine Gegenstandsregel unten geht vor ihrer Qualität.",
    NO_ITEMS = "Noch keine Gegenstandsregeln. Lege unten einen Gegenstand ab.",
    DROP = "Gegenstand hier ablegen, um ihm eine Regel zu geben",
    OPT_REPORT = "Im Chat sagen, was gewürfelt wurde",
}

T.es = {
    TITLE = "Gulli Loot",
    ROLLED = "%s en %s.",
    RULE_ASK = "Preguntar",
    RULE_NEED = "Necesidad",
    RULE_GREED = "Codicia",
    RULE_PASS = "Pasar",
    Q0 = "Gris",
    Q1 = "Blanco",
    Q2 = "Verde",
    NOTE = "Los objetos ligados al recogerlos y los mejores siempre los tiras tú. Una regla de objeto abajo manda sobre su calidad.",
    NO_ITEMS = "Aún no hay reglas de objetos. Suelta un objeto abajo.",
    DROP = "Suelta aquí un objeto para darle una regla",
    OPT_REPORT = "Decir en el chat qué se tiró",
}

T.fr = {
    TITLE = "Gulli Loot",
    ROLLED = "%s sur %s.",
    RULE_ASK = "Me demander",
    RULE_NEED = "Besoin",
    RULE_GREED = "Cupidité",
    RULE_PASS = "Passer",
    Q0 = "Gris",
    Q1 = "Blanc",
    Q2 = "Vert",
    NOTE = "Les objets liés quand ramassés et les meilleurs restent votre choix. Une règle d'objet ci-dessous l'emporte sur sa qualité.",
    NO_ITEMS = "Aucune règle d'objet. Déposez un objet ci-dessous.",
    DROP = "Déposez un objet ici pour lui donner une règle",
    OPT_REPORT = "Dire dans le chat ce qui a été tiré",
}

T.pl = {
    TITLE = "Gulli Loot",
    ROLLED = "%s na %s.",
    RULE_ASK = "Pytaj",
    RULE_NEED = "Potrzeba",
    RULE_GREED = "Chciwość",
    RULE_PASS = "Pas",
    Q0 = "Szare",
    Q1 = "Białe",
    Q2 = "Zielone",
    NOTE = "Przedmioty wiązane przy podniesieniu i lepsze zawsze losujesz sam. Reguła przedmiotu poniżej wygrywa z jego jakością.",
    NO_ITEMS = "Brak reguł przedmiotów. Upuść przedmiot poniżej.",
    DROP = "Upuść tu przedmiot, aby nadać mu regułę",
    OPT_REPORT = "Pisz na czacie, co wylosowano",
}

T.pt = {
    TITLE = "Gulli Loot",
    ROLLED = "%s em %s.",
    RULE_ASK = "Perguntar",
    RULE_NEED = "Necessidade",
    RULE_GREED = "Ganância",
    RULE_PASS = "Passar",
    Q0 = "Cinza",
    Q1 = "Branco",
    Q2 = "Verde",
    NOTE = "Itens vinculados ao pegar e melhores são sempre sua escolha. Uma regra de item abaixo vale mais que a qualidade.",
    NO_ITEMS = "Nenhuma regra de item ainda. Solte um item abaixo.",
    DROP = "Solte um item aqui para dar uma regra a ele",
    OPT_REPORT = "Dizer no chat o que foi rolado",
}

T.ru = {
    TITLE = "Gulli Loot",
    ROLLED = "%s: %s.",
    RULE_ASK = "Спросить",
    RULE_NEED = "Нужно",
    RULE_GREED = "Не откажусь",
    RULE_PASS = "Отказ",
    Q0 = "Серые",
    Q1 = "Белые",
    Q2 = "Зелёные",
    NOTE = "Предметы, которые становятся персональными при поднятии, и лучше всегда разыгрываете вы. Правило для предмета ниже важнее его качества.",
    NO_ITEMS = "Правил для предметов пока нет. Перетащите предмет вниз.",
    DROP = "Перетащите сюда предмет, чтобы задать ему правило",
    OPT_REPORT = "Писать в чат, что разыграно",
}

T.zh = {
    TITLE = "Gulli Loot",
    ROLLED = "%s：%s。",
    RULE_ASK = "询问我",
    RULE_NEED = "需求",
    RULE_GREED = "贪婪",
    RULE_PASS = "放弃",
    Q0 = "灰色",
    Q1 = "白色",
    Q2 = "绿色",
    NOTE = "拾取绑定和更好的物品总是由你掷骰。下方的物品规则优先于品质规则。",
    NO_ITEMS = "还没有物品规则。把物品拖到下方。",
    DROP = "把物品拖到这里设置规则",
    OPT_REPORT = "在聊天中显示掷骰结果",
}

ns.T = T
ns.lang = CLIENT[GetLocale()] or "en"

ns.L = setmetatable({}, { __index = function(_, key)
    local t = T[ns.lang]
    return (t and t[key]) or T.en[key] or key
end })
