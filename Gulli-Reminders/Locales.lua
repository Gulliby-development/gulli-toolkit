local _, ns = ...

-- The same languages as the Runeloader app and every Gulli module. The addon follows the
-- game client's language; English is the base and the fallback.
ns.TAGS = { "en", "de", "es", "fr", "pl", "pt", "ru", "zh" }

local CLIENT = { enUS = "en", enGB = "en", deDE = "de", esES = "es", esMX = "es", frFR = "fr",
                 ptBR = "pt", ptPT = "pt", ruRU = "ru", zhCN = "zh", zhTW = "zh" }

local T = {}

T.en = {
    TITLE = "Gulli Reminders",
    BUFF_INTELLECT = "No Arcane Intellect",
    BUFF_ARMOR = "No armor spell",
    BUFF_FORTITUDE = "No Fortitude",
    BUFF_INNER_FIRE = "No Inner Fire",
    BUFF_WILD = "No Mark of the Wild",
    BUFF_DEMON_ARMOR = "No Demon Armor",
    BUFF_BLESSING = "No blessing",
    BUFF_AURA = "No aura",
    BUFF_ASPECT = "No aspect",
    BUFF_SHIELD = "No Lightning Shield",
    WEAPON = "Weapon buff missing or ends soon",
    AMMO = "Ammo: %d left",
    SHARDS = "Soul shards: %d",
    OPT_BUFFS = "Your class's long buffs",
    OPT_WEAPON = "Poisons and weapon imbues",
    OPT_AMMO = "Hunter ammo below",
    OPT_SHARDS = "Soul shards below",
    OPT_RESTING = "Not in towns and inns",
    NOTE = "Checked only out of combat. Tap the icons to open these settings; drag them to move them.",
}

T.de = {
    TITLE = "Gulli Reminders",
    BUFF_INTELLECT = "Keine Arkane Intelligenz",
    BUFF_ARMOR = "Kein Rüstungszauber",
    BUFF_FORTITUDE = "Keine Seelenstärke",
    BUFF_INNER_FIRE = "Kein Inneres Feuer",
    BUFF_WILD = "Kein Mal der Wildnis",
    BUFF_DEMON_ARMOR = "Keine Dämonenrüstung",
    BUFF_BLESSING = "Kein Segen",
    BUFF_AURA = "Keine Aura",
    BUFF_ASPECT = "Kein Aspekt",
    BUFF_SHIELD = "Kein Blitzschlagschild",
    WEAPON = "Waffenbuff fehlt oder endet bald",
    AMMO = "Munition: noch %d",
    SHARDS = "Seelensplitter: %d",
    OPT_BUFFS = "Die langen Buffs deiner Klasse",
    OPT_WEAPON = "Gifte und Waffenverzauberungen",
    OPT_AMMO = "Jägermunition unter",
    OPT_SHARDS = "Seelensplitter unter",
    OPT_RESTING = "Nicht in Städten und Gasthäusern",
    NOTE = "Nur außerhalb des Kampfes geprüft. Tippe auf die Symbole für diese Einstellungen; ziehe sie, um sie zu verschieben.",
}

T.es = {
    TITLE = "Gulli Reminders",
    BUFF_INTELLECT = "Sin Intelecto Arcano",
    BUFF_ARMOR = "Sin hechizo de armadura",
    BUFF_FORTITUDE = "Sin Entereza",
    BUFF_INNER_FIRE = "Sin Fuego interno",
    BUFF_WILD = "Sin Marca de lo Salvaje",
    BUFF_DEMON_ARMOR = "Sin Armadura demoníaca",
    BUFF_BLESSING = "Sin bendición",
    BUFF_AURA = "Sin aura",
    BUFF_ASPECT = "Sin aspecto",
    BUFF_SHIELD = "Sin Escudo de relámpagos",
    WEAPON = "Falta el buff de arma o termina pronto",
    AMMO = "Munición: quedan %d",
    SHARDS = "Fragmentos de alma: %d",
    OPT_BUFFS = "Los buffs largos de tu clase",
    OPT_WEAPON = "Venenos e imbuiciones de arma",
    OPT_AMMO = "Munición de cazador por debajo de",
    OPT_SHARDS = "Fragmentos de alma por debajo de",
    OPT_RESTING = "No en ciudades ni posadas",
    NOTE = "Solo fuera de combate. Toca los iconos para abrir estos ajustes; arrástralos para moverlos.",
}

T.fr = {
    TITLE = "Gulli Reminders",
    BUFF_INTELLECT = "Pas d'Intelligence des Arcanes",
    BUFF_ARMOR = "Pas de sort d'armure",
    BUFF_FORTITUDE = "Pas de Robustesse",
    BUFF_INNER_FIRE = "Pas de Feu intérieur",
    BUFF_WILD = "Pas de Marque du fauve",
    BUFF_DEMON_ARMOR = "Pas d'Armure démoniaque",
    BUFF_BLESSING = "Pas de bénédiction",
    BUFF_AURA = "Pas d'aura",
    BUFF_ASPECT = "Pas d'aspect",
    BUFF_SHIELD = "Pas de Bouclier de foudre",
    WEAPON = "Buff d'arme absent ou bientôt fini",
    AMMO = "Munitions : %d restantes",
    SHARDS = "Fragments d'âme : %d",
    OPT_BUFFS = "Les longs buffs de votre classe",
    OPT_WEAPON = "Poisons et enchantements d'arme",
    OPT_AMMO = "Munitions de chasseur sous",
    OPT_SHARDS = "Fragments d'âme sous",
    OPT_RESTING = "Pas en ville ni à l'auberge",
    NOTE = "Vérifié hors combat seulement. Touchez les icônes pour ces réglages ; faites-les glisser pour les déplacer.",
}

T.pl = {
    TITLE = "Gulli Reminders",
    BUFF_INTELLECT = "Brak Tajemnego Intelektu",
    BUFF_ARMOR = "Brak zaklęcia pancerza",
    BUFF_FORTITUDE = "Brak Hartu Ducha",
    BUFF_INNER_FIRE = "Brak Wewnętrznego Ognia",
    BUFF_WILD = "Brak Znaku Dziczy",
    BUFF_DEMON_ARMOR = "Brak Demonicznego Pancerza",
    BUFF_BLESSING = "Brak błogosławieństwa",
    BUFF_AURA = "Brak aury",
    BUFF_ASPECT = "Brak aspektu",
    BUFF_SHIELD = "Brak Tarczy Błyskawic",
    WEAPON = "Brak wzmocnienia broni lub zaraz się skończy",
    AMMO = "Amunicja: zostało %d",
    SHARDS = "Odłamki dusz: %d",
    OPT_BUFFS = "Długie wzmocnienia twojej klasy",
    OPT_WEAPON = "Trucizny i nasycenia broni",
    OPT_AMMO = "Amunicja łowcy poniżej",
    OPT_SHARDS = "Odłamki dusz poniżej",
    OPT_RESTING = "Nie w miastach i karczmach",
    NOTE = "Sprawdzane tylko poza walką. Dotknij ikon, aby otworzyć ustawienia; przeciągnij, aby przesunąć.",
}

T.pt = {
    TITLE = "Gulli Reminders",
    BUFF_INTELLECT = "Sem Intelecto Arcano",
    BUFF_ARMOR = "Sem feitiço de armadura",
    BUFF_FORTITUDE = "Sem Fortitude",
    BUFF_INNER_FIRE = "Sem Fogo Interior",
    BUFF_WILD = "Sem Marca da Natureza",
    BUFF_DEMON_ARMOR = "Sem Armadura Demoníaca",
    BUFF_BLESSING = "Sem bênção",
    BUFF_AURA = "Sem aura",
    BUFF_ASPECT = "Sem aspecto",
    BUFF_SHIELD = "Sem Escudo de Raios",
    WEAPON = "Bônus de arma faltando ou acabando",
    AMMO = "Munição: restam %d",
    SHARDS = "Fragmentos de alma: %d",
    OPT_BUFFS = "Os bônus longos da sua classe",
    OPT_WEAPON = "Venenos e encantamentos de arma",
    OPT_AMMO = "Munição de caçador abaixo de",
    OPT_SHARDS = "Fragmentos de alma abaixo de",
    OPT_RESTING = "Não em cidades e estalagens",
    NOTE = "Verificado só fora de combate. Toque nos ícones para abrir estes ajustes; arraste para mover.",
}

T.ru = {
    TITLE = "Gulli Reminders",
    BUFF_INTELLECT = "Нет Чародейского интеллекта",
    BUFF_ARMOR = "Нет брони",
    BUFF_FORTITUDE = "Нет Слова силы: Стойкость",
    BUFF_INNER_FIRE = "Нет Внутреннего огня",
    BUFF_WILD = "Нет Знака дикой природы",
    BUFF_DEMON_ARMOR = "Нет Демонической брони",
    BUFF_BLESSING = "Нет благословения",
    BUFF_AURA = "Нет ауры",
    BUFF_ASPECT = "Нет дуплета",
    BUFF_SHIELD = "Нет Щита молний",
    WEAPON = "Нет яда или чар на оружии, или скоро кончится",
    AMMO = "Боеприпасы: осталось %d",
    SHARDS = "Осколки души: %d",
    OPT_BUFFS = "Долгие бафы вашего класса",
    OPT_WEAPON = "Яды и чары оружия",
    OPT_AMMO = "Боеприпасы охотника меньше",
    OPT_SHARDS = "Осколки души меньше",
    OPT_RESTING = "Не в городах и тавернах",
    NOTE = "Проверяется только вне боя. Нажмите на значки, чтобы открыть настройки; перетащите, чтобы сдвинуть.",
}

T.zh = {
    TITLE = "Gulli Reminders",
    BUFF_INTELLECT = "没有奥术智慧",
    BUFF_ARMOR = "没有护甲法术",
    BUFF_FORTITUDE = "没有真言术：韧",
    BUFF_INNER_FIRE = "没有心灵之火",
    BUFF_WILD = "没有野性印记",
    BUFF_DEMON_ARMOR = "没有魔甲术",
    BUFF_BLESSING = "没有祝福",
    BUFF_AURA = "没有光环",
    BUFF_ASPECT = "没有守护",
    BUFF_SHIELD = "没有闪电盾",
    WEAPON = "武器增益缺失或即将结束",
    AMMO = "弹药：剩余 %d",
    SHARDS = "灵魂碎片：%d",
    OPT_BUFFS = "你职业的长效增益",
    OPT_WEAPON = "毒药和武器附魔",
    OPT_AMMO = "猎人弹药少于",
    OPT_SHARDS = "灵魂碎片少于",
    OPT_RESTING = "不在城市和旅店中",
    NOTE = "仅在战斗外检查。点击图标打开设置，拖动图标可移动。",
}

ns.T = T
ns.lang = CLIENT[GetLocale()] or "en"

ns.L = setmetatable({}, { __index = function(_, key)
    local t = T[ns.lang]
    return (t and t[key]) or T.en[key] or key
end })
