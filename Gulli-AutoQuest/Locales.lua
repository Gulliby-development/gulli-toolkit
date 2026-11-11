local _, ns = ...

-- The same languages as the Runeloader app and every Gulli module. The addon follows the
-- game client's language; English is the base and the fallback.
ns.TAGS = { "en", "de", "es", "fr", "pl", "pt", "ru", "zh" }

local CLIENT = { enUS = "en", enGB = "en", deDE = "de", esES = "es", esMX = "es", frFR = "fr",
                 ptBR = "pt", ptPT = "pt", ruRU = "ru", zhCN = "zh", zhTW = "zh" }

local T = {}

T.en = {
    TITLE = "Gulli AutoQuest",
    CHOOSE = "choose your reward. The best vendor price: %s.",
    CHOOSE_ANY = "choose your reward.",
    OPT_ACCEPT = "Take quests",
    OPT_TURNIN = "Hand in finished quests",
    OPT_TRIVIAL = "Skip gray (low-level) quests",
    NOTE = "Hold Shift when you talk to an NPC to do it yourself. A reward with a choice is always yours to pick, and a quest that asks for gold is never handed in on its own.",
}

T.de = {
    TITLE = "Gulli AutoQuest",
    CHOOSE = "wähle deine Belohnung. Bester Händlerpreis: %s.",
    CHOOSE_ANY = "wähle deine Belohnung.",
    OPT_ACCEPT = "Quests annehmen",
    OPT_TURNIN = "Fertige Quests abgeben",
    OPT_TRIVIAL = "Graue (niedrige) Quests überspringen",
    NOTE = "Halte Umschalt beim Ansprechen eines NPCs, um es selbst zu tun. Eine Belohnung mit Auswahl wählst immer du, und eine Quest, die Gold kostet, wird nie allein abgegeben.",
}

T.es = {
    TITLE = "Gulli AutoQuest",
    CHOOSE = "elige tu recompensa. Mejor precio de venta: %s.",
    CHOOSE_ANY = "elige tu recompensa.",
    OPT_ACCEPT = "Aceptar misiones",
    OPT_TURNIN = "Entregar misiones terminadas",
    OPT_TRIVIAL = "Saltar misiones grises (de nivel bajo)",
    NOTE = "Mantén Mayús al hablar con un PNJ para hacerlo tú. Si hay que elegir recompensa, eliges tú, y una misión que pide oro nunca se entrega sola.",
}

T.fr = {
    TITLE = "Gulli AutoQuest",
    CHOOSE = "choisissez votre récompense. Meilleur prix de vente : %s.",
    CHOOSE_ANY = "choisissez votre récompense.",
    OPT_ACCEPT = "Accepter les quêtes",
    OPT_TURNIN = "Rendre les quêtes terminées",
    OPT_TRIVIAL = "Ignorer les quêtes grises (bas niveau)",
    NOTE = "Maintenez Maj en parlant à un PNJ pour le faire vous-même. Une récompense à choisir reste votre choix, et une quête qui demande de l'or n'est jamais rendue seule.",
}

T.pl = {
    TITLE = "Gulli AutoQuest",
    CHOOSE = "wybierz nagrodę. Najlepsza cena u handlarza: %s.",
    CHOOSE_ANY = "wybierz nagrodę.",
    OPT_ACCEPT = "Przyjmuj zadania",
    OPT_TURNIN = "Oddawaj ukończone zadania",
    OPT_TRIVIAL = "Pomijaj szare (niskie) zadania",
    NOTE = "Przytrzymaj Shift przy rozmowie z NPC, aby zrobić to sam. Nagrodę z wyborem zawsze wybierasz ty, a zadanie za złoto nigdy nie jest oddawane samo.",
}

T.pt = {
    TITLE = "Gulli AutoQuest",
    CHOOSE = "escolha sua recompensa. Melhor preço de venda: %s.",
    CHOOSE_ANY = "escolha sua recompensa.",
    OPT_ACCEPT = "Aceitar missões",
    OPT_TURNIN = "Entregar missões concluídas",
    OPT_TRIVIAL = "Pular missões cinza (de nível baixo)",
    NOTE = "Segure Shift ao falar com um PNJ para fazer você mesmo. Uma recompensa com escolha é sempre sua, e uma missão que pede ouro nunca é entregue sozinha.",
}

T.ru = {
    TITLE = "Gulli AutoQuest",
    CHOOSE = "выберите награду. Дороже всего у торговца: %s.",
    CHOOSE_ANY = "выберите награду.",
    OPT_ACCEPT = "Брать квесты",
    OPT_TURNIN = "Сдавать выполненные квесты",
    OPT_TRIVIAL = "Пропускать серые (низкие) квесты",
    NOTE = "Удерживайте Shift при разговоре с NPC, чтобы сделать всё самому. Награду с выбором всегда выбираете вы, а квест, который просит золото, сам не сдаётся.",
}

T.zh = {
    TITLE = "Gulli AutoQuest",
    CHOOSE = "请选择奖励。商人价格最高：%s。",
    CHOOSE_ANY = "请选择奖励。",
    OPT_ACCEPT = "接受任务",
    OPT_TURNIN = "交付完成的任务",
    OPT_TRIVIAL = "跳过灰色（低级）任务",
    NOTE = "与 NPC 对话时按住 Shift 可自己操作。有多个奖励时总是由你选择，需要金币的任务不会自动交付。",
}

ns.T = T
ns.lang = CLIENT[GetLocale()] or "en"

ns.L = setmetatable({}, { __index = function(_, key)
    local t = T[ns.lang]
    return (t and t[key]) or T.en[key] or key
end })
