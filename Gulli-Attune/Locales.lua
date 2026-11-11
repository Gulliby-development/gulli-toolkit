local _, ns = ...

-- The same languages as the Runeloader app and every Gulli module. The addon follows the
-- game client's language; English is the base and the fallback.
ns.TAGS = { "en", "de", "es", "fr", "pl", "pt", "ru", "zh" }

local CLIENT = { enUS = "en", enGB = "en", deDE = "de", esES = "es", esMX = "es", frFR = "fr",
                 ptBR = "pt", ptPT = "pt", ruRU = "ru", zhCN = "zh", zhTW = "zh" }

local T = {}

T.en = {
    TITLE = "Attunements",
    READY = "Ready",
    STEPS = "%d of %d steps",
    NEXT = "Next:",
    WHERE = "%s, %s",
    FORGET = "Forget character",
    RAID_MC = "Molten Core",
    RAID_ONY = "Onyxia's Lair",
    RAID_BWL = "Blackwing Lair",
    RAID_NAXX = "Naxxramas",
    RAID_UBRS = "Upper Blackrock Spire",
}

T.de = {
    TITLE = "Zugänge",
    READY = "Bereit",
    STEPS = "%d von %d Schritten",
    NEXT = "Als Nächstes:",
    WHERE = "%s, %s",
    FORGET = "Charakter vergessen",
    RAID_MC = "Geschmolzener Kern",
    RAID_ONY = "Onyxias Hort",
    RAID_BWL = "Pechschwingenhort",
    RAID_NAXX = "Naxxramas",
    RAID_UBRS = "Obere Schwarzfelsspitze",
}

T.es = {
    TITLE = "Accesos",
    READY = "Listo",
    STEPS = "%d de %d pasos",
    NEXT = "Siguiente:",
    WHERE = "%s, %s",
    FORGET = "Olvidar personaje",
    RAID_MC = "Núcleo de Magma",
    RAID_ONY = "Guarida de Onyxia",
    RAID_BWL = "Guarida Alanegra",
    RAID_NAXX = "Naxxramas",
    RAID_UBRS = "Cumbre de Roca Negra Superior",
}

T.fr = {
    TITLE = "Accès",
    READY = "Prêt",
    STEPS = "%d étapes sur %d",
    NEXT = "Suivant :",
    WHERE = "%s, %s",
    FORGET = "Oublier le personnage",
    RAID_MC = "Cœur du Magma",
    RAID_ONY = "Repaire d'Onyxia",
    RAID_BWL = "Repaire de l'Aile noire",
    RAID_NAXX = "Naxxramas",
    RAID_UBRS = "Pic Rochenoire supérieur",
}

T.pl = {
    TITLE = "Dostępy",
    READY = "Gotowe",
    STEPS = "%d z %d kroków",
    NEXT = "Dalej:",
    WHERE = "%s, %s",
    FORGET = "Zapomnij postać",
    RAID_MC = "Molten Core",
    RAID_ONY = "Onyxia's Lair",
    RAID_BWL = "Blackwing Lair",
    RAID_NAXX = "Naxxramas",
    RAID_UBRS = "Upper Blackrock Spire",
}

T.pt = {
    TITLE = "Sintonizações",
    READY = "Pronto",
    STEPS = "%d de %d etapas",
    NEXT = "Próximo:",
    WHERE = "%s, %s",
    FORGET = "Esquecer personagem",
    RAID_MC = "Núcleo Derretido",
    RAID_ONY = "Covil da Onyxia",
    RAID_BWL = "Covil Asa Negra",
    RAID_NAXX = "Naxxramas",
    RAID_UBRS = "Pico da Rocha Negra Superior",
}

T.ru = {
    TITLE = "Допуски",
    READY = "Готово",
    STEPS = "%d из %d шагов",
    NEXT = "Дальше:",
    WHERE = "%s, %s",
    FORGET = "Забыть персонажа",
    RAID_MC = "Огненные Недра",
    RAID_ONY = "Логово Ониксии",
    RAID_BWL = "Логово Крыла Тьмы",
    RAID_NAXX = "Наксрамас",
    RAID_UBRS = "Верхняя часть пика Черной горы",
}

T.zh = {
    TITLE = "团队资格",
    READY = "已完成",
    STEPS = "%d / %d 步",
    NEXT = "下一步：",
    WHERE = "%s，%s",
    FORGET = "忘记角色",
    RAID_MC = "熔火之心",
    RAID_ONY = "奥妮克希亚的巢穴",
    RAID_BWL = "黑翼之巢",
    RAID_NAXX = "纳克萨玛斯",
    RAID_UBRS = "黑石塔上层",
}

ns.T = T
ns.lang = CLIENT[GetLocale()] or "en"

ns.L = setmetatable({}, { __index = function(_, key)
    local t = T[ns.lang]
    return (t and t[key]) or T.en[key] or key
end })
