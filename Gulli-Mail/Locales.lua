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
    SEND_TO = "Write a letter to",
    NO_NAMES = "No names yet",
    NO_NAMES_SUB = "Your other characters on this realm appear here after you log in with them once, and so do the players you send mail to. Tap a name to start a letter.",
    ALT = "your character",
    OPT_PANEL = "Show the panel at the mailbox",
    HELP = "At a mailbox the panel opens next to it. Tap a name to start a letter to that player.",
    FAILED = "%d items could not be taken (unique or the game refused them); they stay in their letters.",
    MORE = "%d more letters wait on the server. Take all asks for them.",
    WAITING = "Waiting for the server to send the next letters (up to a minute)...",
}

T.de = {
    TITLE = "Gulli Mail",
    TAKEN = "%d Gegenstände und %s genommen.",
    FULL = "Deine Taschen sind voll.",
    SUMMARY = "Im Briefkasten: %d Gegenstände und %s.",
    COD = "Ausgelassen: %d Briefe mit Nachnahme. Öffne sie selbst.",
    TAKE_ALL = "Alles nehmen",
    TAKING = "Nehme...",
    SEND_TO = "Brief schreiben an",
    NO_NAMES = "Noch keine Namen",
    NO_NAMES_SUB = "Deine anderen Charaktere auf diesem Realm erscheinen hier, nachdem du dich einmal mit ihnen eingeloggt hast, ebenso die Spieler, denen du Post schickst. Tippe auf einen Namen, um einen Brief zu beginnen.",
    ALT = "dein Charakter",
    OPT_PANEL = "Das Feld am Briefkasten zeigen",
    HELP = "Am Briefkasten öffnet sich das Feld daneben. Tippe auf einen Namen, um einen Brief an ihn zu beginnen.",
    FAILED = "%d Gegenstände ließen sich nicht nehmen (einzigartig oder vom Spiel abgelehnt); sie bleiben in ihren Briefen.",
    MORE = "%d weitere Briefe warten auf dem Server. Alles nehmen holt sie.",
    WAITING = "Warte, bis der Server die nächsten Briefe schickt (bis zu einer Minute)...",
}

T.es = {
    TITLE = "Gulli Mail",
    TAKEN = "recogidos %d objetos y %s.",
    FULL = "Tus bolsas están llenas.",
    SUMMARY = "En el buzón: %d objetos y %s.",
    COD = "Sin tocar: %d cartas contra reembolso. Ábrelas tú.",
    TAKE_ALL = "Recoger todo",
    TAKING = "Recogiendo...",
    SEND_TO = "Escribir una carta a",
    NO_NAMES = "Aún no hay nombres",
    NO_NAMES_SUB = "Tus otros personajes de este reino aparecen aquí cuando entras una vez con ellos, y también los jugadores a los que envías correo. Toca un nombre para empezar una carta.",
    ALT = "tu personaje",
    OPT_PANEL = "Mostrar el panel en el buzón",
    HELP = "En el buzón el panel se abre al lado. Toca un nombre para empezar una carta a ese jugador.",
    FAILED = "%d objetos no se pudieron recoger (únicos o el juego los rechazó); siguen en sus cartas.",
    MORE = "%d cartas más esperan en el servidor. Recoger todo las pide.",
    WAITING = "Esperando a que el servidor envíe las siguientes cartas (hasta un minuto)...",
}

T.fr = {
    TITLE = "Gulli Mail",
    TAKEN = "%d objets et %s récupérés.",
    FULL = "Vos sacs sont pleins.",
    SUMMARY = "Dans la boîte : %d objets et %s.",
    COD = "Ignorées : %d lettres contre remboursement. Ouvrez-les vous-même.",
    TAKE_ALL = "Tout prendre",
    TAKING = "En cours...",
    SEND_TO = "Écrire une lettre à",
    NO_NAMES = "Pas encore de noms",
    NO_NAMES_SUB = "Vos autres personnages de ce royaume apparaissent ici après une connexion avec eux, ainsi que les joueurs à qui vous envoyez du courrier. Touchez un nom pour commencer une lettre.",
    ALT = "votre personnage",
    OPT_PANEL = "Afficher le panneau à la boîte aux lettres",
    HELP = "À la boîte aux lettres, le panneau s'ouvre à côté. Touchez un nom pour écrire à ce joueur.",
    FAILED = "%d objets n'ont pas pu être pris (uniques ou refusés par le jeu) ; ils restent dans leurs lettres.",
    MORE = "%d lettres de plus attendent sur le serveur. Tout prendre les demande.",
    WAITING = "En attente des lettres suivantes du serveur (jusqu'à une minute)...",
}

T.pl = {
    TITLE = "Gulli Mail",
    TAKEN = "zabrano %d przedmiotów i %s.",
    FULL = "Twoje torby są pełne.",
    SUMMARY = "W skrzynce: %d przedmiotów i %s.",
    COD = "Pominięto: %d listów za pobraniem. Otwórz je sam.",
    TAKE_ALL = "Zabierz wszystko",
    TAKING = "Zabieram...",
    SEND_TO = "Napisz list do",
    NO_NAMES = "Jeszcze brak imion",
    NO_NAMES_SUB = "Twoje inne postacie z tego serwera pojawią się tu, gdy raz się nimi zalogujesz, tak samo gracze, do których wysyłasz pocztę. Dotknij imienia, aby zacząć list.",
    ALT = "twoja postać",
    OPT_PANEL = "Pokazuj panel przy skrzynce",
    HELP = "Przy skrzynce panel otwiera się obok. Dotknij imienia, aby zacząć list do tego gracza.",
    FAILED = "Nie udało się wziąć %d przedmiotów (unikatowe lub gra odmówiła); zostają w listach.",
    MORE = "Na serwerze czeka jeszcze %d listów. Weź wszystko je pobierze.",
    WAITING = "Czekam, aż serwer wyśle kolejne listy (do minuty)...",
}

T.pt = {
    TITLE = "Gulli Mail",
    TAKEN = "pegos %d itens e %s.",
    FULL = "Suas bolsas estão cheias.",
    SUMMARY = "No correio: %d itens e %s.",
    COD = "Ignoradas: %d cartas com pagamento na entrega. Abra-as você.",
    TAKE_ALL = "Pegar tudo",
    TAKING = "Pegando...",
    SEND_TO = "Escrever uma carta para",
    NO_NAMES = "Ainda sem nomes",
    NO_NAMES_SUB = "Seus outros personagens deste reino aparecem aqui depois que você entra com eles uma vez, assim como os jogadores para quem você envia correio. Toque num nome para começar uma carta.",
    ALT = "seu personagem",
    OPT_PANEL = "Mostrar o painel no correio",
    HELP = "No correio o painel abre ao lado. Toque num nome para começar uma carta a esse jogador.",
    FAILED = "%d itens não puderam ser pegos (únicos ou recusados pelo jogo); ficam nas cartas.",
    MORE = "Mais %d cartas esperam no servidor. Pegar tudo pede por elas.",
    WAITING = "Esperando o servidor enviar as próximas cartas (até um minuto)...",
}

T.ru = {
    TITLE = "Gulli Mail",
    TAKEN = "забрано предметов: %d и %s.",
    FULL = "Сумки заполнены.",
    SUMMARY = "В почте: %d предметов и %s.",
    COD = "Пропущено писем с наложенным платежом: %d. Откройте их сами.",
    TAKE_ALL = "Забрать всё",
    TAKING = "Забираю...",
    SEND_TO = "Написать письмо",
    NO_NAMES = "Пока никого нет",
    NO_NAMES_SUB = "Здесь появятся ваши другие персонажи с этого сервера, когда вы хотя бы раз зайдёте за них, и игроки, которым вы отправляли почту. Нажмите на имя, чтобы начать письмо.",
    ALT = "ваш персонаж",
    OPT_PANEL = "Показывать панель у почтового ящика",
    HELP = "У почтового ящика панель открывается рядом. Нажмите на имя, чтобы начать письмо этому игроку.",
    FAILED = "Не удалось взять предметов: %d (уникальные или игра отказала); они остались в письмах.",
    MORE = "Ещё писем на сервере: %d. «Забрать всё» их запросит.",
    WAITING = "Ждём, пока сервер пришлёт следующие письма (до минуты)...",
}

T.zh = {
    TITLE = "Gulli Mail",
    TAKEN = "已收取 %d 件物品和 %s。",
    FULL = "你的背包已满。",
    SUMMARY = "邮箱中：%d 件物品和 %s。",
    COD = "已跳过 %d 封货到付款邮件，请自己打开。",
    TAKE_ALL = "全部收取",
    TAKING = "收取中...",
    SEND_TO = "写信给",
    NO_NAMES = "还没有名字",
    NO_NAMES_SUB = "你在此服务器的其他角色登录一次后会显示在这里，你寄过信的玩家也会显示。点击名字即可开始写信。",
    ALT = "你的角色",
    OPT_PANEL = "在邮箱旁显示面板",
    HELP = "在邮箱处，面板会在旁边打开。点击名字即可给该玩家写信。",
    FAILED = "有 %d 件物品无法收取（唯一物品或被游戏拒绝），它们留在信中。",
    MORE = "服务器上还有 %d 封信。全部收取会去请求它们。",
    WAITING = "正在等待服务器发送后续信件（最多一分钟）……",
}

ns.T = T
ns.lang = CLIENT[GetLocale()] or "en"

ns.L = setmetatable({}, { __index = function(_, key)
    local t = T[ns.lang]
    return (t and t[key]) or T.en[key] or key
end })
