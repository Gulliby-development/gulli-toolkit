local _, ns = ...

-- The same languages as the Runeloader app and every Gulli module. The addon follows the
-- game client's language; English is the base and the fallback.
ns.TAGS = { "en", "de", "es", "fr", "pl", "pt", "ru", "zh" }

local CLIENT = { enUS = "en", enGB = "en", deDE = "de", esES = "es", esMX = "es", frFR = "fr",
                 ptBR = "pt", ptPT = "pt", ruRU = "ru", zhCN = "zh", zhTW = "zh" }

local T = {}

T.en = {
    TITLE = "Gulli Social",
    INVITED = "invited %s.",
    CANT_INVITE = "%s asked for an invite, but you cannot invite now.",
    ACCEPTED = "joined the group of %s.",
    BLOCKED = "turned away a group invite from %s.",
    NO_DUEL = "turned away a duel from %s.",
    NO_GUILD = "turned away a guild invite from %s.",
    OPT_INVITE = "Invite players who whisper a key word",
    WORDS = "key words, with commas",
    OPT_INVITE_KNOWN = "Only friends and guild get that invite",
    OPT_ACCEPT_KNOWN = "Accept invites from friends and guild",
    OPT_BLOCK = "Turn away group invites from strangers",
    OPT_DUELS = "Turn away duels",
    OPT_GUILD = "Turn away guild invites",
    SEC_INVITE = "Invites",
    SEC_AWAY = "Turn away",
}

T.de = {
    TITLE = "Gulli Social",
    INVITED = "%s eingeladen.",
    CANT_INVITE = "%s wollte eine Einladung, aber du kannst gerade nicht einladen.",
    ACCEPTED = "der Gruppe von %s beigetreten.",
    BLOCKED = "Gruppeneinladung von %s abgelehnt.",
    NO_DUEL = "Duell von %s abgelehnt.",
    NO_GUILD = "Gildeneinladung von %s abgelehnt.",
    OPT_INVITE = "Spieler einladen, die ein Schlüsselwort flüstern",
    WORDS = "Schlüsselwörter, mit Kommas",
    OPT_INVITE_KNOWN = "Nur Freunde und Gilde bekommen diese Einladung",
    OPT_ACCEPT_KNOWN = "Einladungen von Freunden und Gilde annehmen",
    OPT_BLOCK = "Gruppeneinladungen von Fremden ablehnen",
    OPT_DUELS = "Duelle ablehnen",
    OPT_GUILD = "Gildeneinladungen ablehnen",
    SEC_INVITE = "Einladungen",
    SEC_AWAY = "Ablehnen",
}

T.es = {
    TITLE = "Gulli Social",
    INVITED = "invitado %s.",
    CANT_INVITE = "%s pidió invitación, pero ahora no puedes invitar.",
    ACCEPTED = "te uniste al grupo de %s.",
    BLOCKED = "rechazada invitación de grupo de %s.",
    NO_DUEL = "rechazado duelo de %s.",
    NO_GUILD = "rechazada invitación de hermandad de %s.",
    OPT_INVITE = "Invitar a quien susurre una palabra clave",
    WORDS = "palabras clave, con comas",
    OPT_INVITE_KNOWN = "Solo amigos y hermandad reciben esa invitación",
    OPT_ACCEPT_KNOWN = "Aceptar invitaciones de amigos y hermandad",
    OPT_BLOCK = "Rechazar invitaciones de grupo de desconocidos",
    OPT_DUELS = "Rechazar duelos",
    OPT_GUILD = "Rechazar invitaciones de hermandad",
    SEC_INVITE = "Invitaciones",
    SEC_AWAY = "Rechazar",
}

T.fr = {
    TITLE = "Gulli Social",
    INVITED = "%s invité.",
    CANT_INVITE = "%s demande une invitation, mais vous ne pouvez pas inviter.",
    ACCEPTED = "groupe de %s rejoint.",
    BLOCKED = "invitation de groupe de %s refusée.",
    NO_DUEL = "duel de %s refusé.",
    NO_GUILD = "invitation de guilde de %s refusée.",
    OPT_INVITE = "Inviter les joueurs qui chuchotent un mot clé",
    WORDS = "mots clés, avec des virgules",
    OPT_INVITE_KNOWN = "Seuls amis et guilde reçoivent cette invitation",
    OPT_ACCEPT_KNOWN = "Accepter les invitations des amis et de la guilde",
    OPT_BLOCK = "Refuser les invitations de groupe des inconnus",
    OPT_DUELS = "Refuser les duels",
    OPT_GUILD = "Refuser les invitations de guilde",
    SEC_INVITE = "Invitations",
    SEC_AWAY = "Refuser",
}

T.pl = {
    TITLE = "Gulli Social",
    INVITED = "zaproszono %s.",
    CANT_INVITE = "%s prosi o zaproszenie, ale teraz nie możesz zapraszać.",
    ACCEPTED = "dołączono do grupy %s.",
    BLOCKED = "odrzucono zaproszenie do grupy od %s.",
    NO_DUEL = "odrzucono pojedynek od %s.",
    NO_GUILD = "odrzucono zaproszenie do gildii od %s.",
    OPT_INVITE = "Zapraszaj graczy, którzy szepną słowo klucz",
    WORDS = "słowa klucze, po przecinku",
    OPT_INVITE_KNOWN = "Tylko znajomi i gildia dostają to zaproszenie",
    OPT_ACCEPT_KNOWN = "Przyjmuj zaproszenia od znajomych i gildii",
    OPT_BLOCK = "Odrzucaj zaproszenia do grupy od obcych",
    OPT_DUELS = "Odrzucaj pojedynki",
    OPT_GUILD = "Odrzucaj zaproszenia do gildii",
    SEC_INVITE = "Zaproszenia",
    SEC_AWAY = "Odrzucanie",
}

T.pt = {
    TITLE = "Gulli Social",
    INVITED = "%s convidado.",
    CANT_INVITE = "%s pediu convite, mas agora você não pode convidar.",
    ACCEPTED = "entrou no grupo de %s.",
    BLOCKED = "convite de grupo de %s recusado.",
    NO_DUEL = "duelo de %s recusado.",
    NO_GUILD = "convite de guilda de %s recusado.",
    OPT_INVITE = "Convidar quem sussurrar uma palavra-chave",
    WORDS = "palavras-chave, com vírgulas",
    OPT_INVITE_KNOWN = "Só amigos e guilda recebem esse convite",
    OPT_ACCEPT_KNOWN = "Aceitar convites de amigos e da guilda",
    OPT_BLOCK = "Recusar convites de grupo de desconhecidos",
    OPT_DUELS = "Recusar duelos",
    OPT_GUILD = "Recusar convites de guilda",
    SEC_INVITE = "Convites",
    SEC_AWAY = "Recusar",
}

T.ru = {
    TITLE = "Gulli Social",
    INVITED = "приглашён %s.",
    CANT_INVITE = "%s просит инвайт, но вы сейчас не можете приглашать.",
    ACCEPTED = "вы в группе %s.",
    BLOCKED = "отклонено приглашение в группу от %s.",
    NO_DUEL = "отклонена дуэль от %s.",
    NO_GUILD = "отклонено приглашение в гильдию от %s.",
    OPT_INVITE = "Приглашать тех, кто шепчет ключевое слово",
    WORDS = "ключевые слова через запятую",
    OPT_INVITE_KNOWN = "Такой инвайт только друзьям и гильдии",
    OPT_ACCEPT_KNOWN = "Принимать приглашения от друзей и гильдии",
    OPT_BLOCK = "Отклонять приглашения в группу от незнакомцев",
    OPT_DUELS = "Отклонять дуэли",
    OPT_GUILD = "Отклонять приглашения в гильдию",
    SEC_INVITE = "Приглашения",
    SEC_AWAY = "Отклонять",
}

T.zh = {
    TITLE = "Gulli Social",
    INVITED = "已邀请 %s。",
    CANT_INVITE = "%s 请求邀请，但你现在无法邀请。",
    ACCEPTED = "已加入 %s 的队伍。",
    BLOCKED = "已拒绝 %s 的组队邀请。",
    NO_DUEL = "已拒绝 %s 的决斗。",
    NO_GUILD = "已拒绝 %s 的公会邀请。",
    OPT_INVITE = "邀请密语关键词的玩家",
    WORDS = "关键词，用逗号分隔",
    OPT_INVITE_KNOWN = "只有好友和公会成员会被邀请",
    OPT_ACCEPT_KNOWN = "接受好友和公会的邀请",
    OPT_BLOCK = "拒绝陌生人的组队邀请",
    OPT_DUELS = "拒绝决斗",
    OPT_GUILD = "拒绝公会邀请",
    SEC_INVITE = "邀请",
    SEC_AWAY = "拒绝",
}

ns.T = T
ns.lang = CLIENT[GetLocale()] or "en"

ns.L = setmetatable({}, { __index = function(_, key)
    local t = T[ns.lang]
    return (t and t[key]) or T.en[key] or key
end })
