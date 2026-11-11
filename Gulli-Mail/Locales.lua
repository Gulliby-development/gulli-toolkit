local _, ns = ...

-- The same languages as the Runeloader app and every Gulli module. The addon follows the
-- game client's language; English is the base and the fallback.
ns.TAGS = { "en", "de", "es", "fr", "pl", "pt", "ru", "zh" }

local CLIENT = { enUS = "en", enGB = "en", deDE = "de", esES = "es", esMX = "es", frFR = "fr",
                 ptBR = "pt", ptPT = "pt", ruRU = "ru", zhCN = "zh", zhTW = "zh" }

local T = {}

T.en = {
    TITLE = "Gulli Mail",
    TAKEN = "took %d items and %s.",
    FULL = "Your bags are full.",
    SUMMARY = "In the mailbox: %d items and %s.",
    COD = "Left out: %d letters with cash on delivery. Open them yourself.",
    TAKE_ALL = "Take all",
    TAKING = "Taking...",
    SEND_TO = "Send to",
    ALT = "your character",
    OPT_PANEL = "Show the panel at the mailbox",
    HELP = "At a mailbox the panel opens next to it. Tap a name to start a letter to that player.",
}

T.de = {
    TITLE = "Gulli Mail",
    TAKEN = "%d Gegenstände und %s genommen.",
    FULL = "Deine Taschen sind voll.",
    SUMMARY = "Im Briefkasten: %d Gegenstände und %s.",
    COD = "Ausgelassen: %d Briefe mit Nachnahme. Öffne sie selbst.",
    TAKE_ALL = "Alles nehmen",
    TAKING = "Nehme...",
    SEND_TO = "Senden an",
    ALT = "dein Charakter",
    OPT_PANEL = "Das Feld am Briefkasten zeigen",
    HELP = "Am Briefkasten öffnet sich das Feld daneben. Tippe auf einen Namen, um einen Brief an ihn zu beginnen.",
}

T.es = {
    TITLE = "Gulli Mail",
    TAKEN = "recogidos %d objetos y %s.",
    FULL = "Tus bolsas están llenas.",
    SUMMARY = "En el buzón: %d objetos y %s.",
    COD = "Sin tocar: %d cartas contra reembolso. Ábrelas tú.",
    TAKE_ALL = "Recoger todo",
    TAKING = "Recogiendo...",
    SEND_TO = "Enviar a",
    ALT = "tu personaje",
    OPT_PANEL = "Mostrar el panel en el buzón",
    HELP = "En el buzón el panel se abre al lado. Toca un nombre para empezar una carta a ese jugador.",
}

T.fr = {
    TITLE = "Gulli Mail",
    TAKEN = "%d objets et %s récupérés.",
    FULL = "Vos sacs sont pleins.",
    SUMMARY = "Dans la boîte : %d objets et %s.",
    COD = "Ignorées : %d lettres contre remboursement. Ouvrez-les vous-même.",
    TAKE_ALL = "Tout prendre",
    TAKING = "En cours...",
    SEND_TO = "Envoyer à",
    ALT = "votre personnage",
    OPT_PANEL = "Afficher le panneau à la boîte aux lettres",
    HELP = "À la boîte aux lettres, le panneau s'ouvre à côté. Touchez un nom pour écrire à ce joueur.",
}

T.pl = {
    TITLE = "Gulli Mail",
    TAKEN = "zabrano %d przedmiotów i %s.",
    FULL = "Twoje torby są pełne.",
    SUMMARY = "W skrzynce: %d przedmiotów i %s.",
    COD = "Pominięto: %d listów za pobraniem. Otwórz je sam.",
    TAKE_ALL = "Zabierz wszystko",
    TAKING = "Zabieram...",
    SEND_TO = "Wyślij do",
    ALT = "twoja postać",
    OPT_PANEL = "Pokazuj panel przy skrzynce",
    HELP = "Przy skrzynce panel otwiera się obok. Dotknij imienia, aby zacząć list do tego gracza.",
}

T.pt = {
    TITLE = "Gulli Mail",
    TAKEN = "pegos %d itens e %s.",
    FULL = "Suas bolsas estão cheias.",
    SUMMARY = "No correio: %d itens e %s.",
    COD = "Ignoradas: %d cartas com pagamento na entrega. Abra-as você.",
    TAKE_ALL = "Pegar tudo",
    TAKING = "Pegando...",
    SEND_TO = "Enviar para",
    ALT = "seu personagem",
    OPT_PANEL = "Mostrar o painel no correio",
    HELP = "No correio o painel abre ao lado. Toque num nome para começar uma carta a esse jogador.",
}

T.ru = {
    TITLE = "Gulli Mail",
    TAKEN = "забрано предметов: %d и %s.",
    FULL = "Сумки заполнены.",
    SUMMARY = "В почте: %d предметов и %s.",
    COD = "Пропущено писем с наложенным платежом: %d. Откройте их сами.",
    TAKE_ALL = "Забрать всё",
    TAKING = "Забираю...",
    SEND_TO = "Отправить",
    ALT = "ваш персонаж",
    OPT_PANEL = "Показывать панель у почтового ящика",
    HELP = "У почтового ящика панель открывается рядом. Нажмите на имя, чтобы начать письмо этому игроку.",
}

T.zh = {
    TITLE = "Gulli Mail",
    TAKEN = "已收取 %d 件物品和 %s。",
    FULL = "你的背包已满。",
    SUMMARY = "邮箱中：%d 件物品和 %s。",
    COD = "已跳过 %d 封货到付款邮件，请自己打开。",
    TAKE_ALL = "全部收取",
    TAKING = "收取中...",
    SEND_TO = "发送给",
    ALT = "你的角色",
    OPT_PANEL = "在邮箱旁显示面板",
    HELP = "在邮箱处，面板会在旁边打开。点击名字即可给该玩家写信。",
}

ns.T = T
ns.lang = CLIENT[GetLocale()] or "en"

ns.L = setmetatable({}, { __index = function(_, key)
    local t = T[ns.lang]
    return (t and t[key]) or T.en[key] or key
end })
