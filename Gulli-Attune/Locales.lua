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
    RAID_ONY = "Onyxia's Lair",
    RAID_UBRS = "Upper Blackrock Spire",
    RAID_BRD = "Blackrock Depths",
    RAID_SCHOLO = "Scholomance",
    RAID_MARA = "Maraudon",
}

T.de = {
    TITLE = "Zugänge",
    READY = "Bereit",
    STEPS = "%d von %d Schritten",
    NEXT = "Als Nächstes:",
    WHERE = "%s, %s",
    FORGET = "Charakter vergessen",
    RAID_ONY = "Onyxias Hort",
    RAID_UBRS = "Obere Schwarzfelsspitze",
    RAID_BRD = "Schwarzfelstiefen",
    RAID_SCHOLO = "Scholomance",
    RAID_MARA = "Maraudon",
}

T.es = {
    TITLE = "Accesos",
    READY = "Listo",
    STEPS = "%d de %d pasos",
    NEXT = "Siguiente:",
    WHERE = "%s, %s",
    FORGET = "Olvidar personaje",
    RAID_ONY = "Guarida de Onyxia",
    RAID_UBRS = "Cumbre de Roca Negra Superior",
    RAID_BRD = "Profundidades de Roca Negra",
    RAID_SCHOLO = "Scholomance",
    RAID_MARA = "Maraudon",
}

T.fr = {
    TITLE = "Accès",
    READY = "Prêt",
    STEPS = "%d étapes sur %d",
    NEXT = "Suivant :",
    WHERE = "%s, %s",
    FORGET = "Oublier le personnage",
    RAID_ONY = "Repaire d'Onyxia",
    RAID_UBRS = "Pic Rochenoire supérieur",
    RAID_BRD = "Profondeurs de Rochenoire",
    RAID_SCHOLO = "Scholomance",
    RAID_MARA = "Maraudon",
}

T.pl = {
    TITLE = "Dostępy",
    READY = "Gotowe",
    STEPS = "%d z %d kroków",
    NEXT = "Dalej:",
    WHERE = "%s, %s",
    FORGET = "Zapomnij postać",
    RAID_ONY = "Onyxia's Lair",
    RAID_UBRS = "Upper Blackrock Spire",
    RAID_BRD = "Blackrock Depths",
    RAID_SCHOLO = "Scholomance",
    RAID_MARA = "Maraudon",
}

T.pt = {
    TITLE = "Sintonizações",
    READY = "Pronto",
    STEPS = "%d de %d etapas",
    NEXT = "Próximo:",
    WHERE = "%s, %s",
    FORGET = "Esquecer personagem",
    RAID_ONY = "Covil da Onyxia",
    RAID_UBRS = "Pico da Rocha Negra Superior",
    RAID_BRD = "Abismo Rocha Negra",
    RAID_SCHOLO = "Scolomântia",
    RAID_MARA = "Maraudon",
}

T.ru = {
    TITLE = "Допуски",
    READY = "Готово",
    STEPS = "%d из %d шагов",
    NEXT = "Дальше:",
    WHERE = "%s, %s",
    FORGET = "Забыть персонажа",
    RAID_ONY = "Логово Ониксии",
    RAID_UBRS = "Верхняя часть пика Черной горы",
    RAID_BRD = "Глубины Черной горы",
    RAID_SCHOLO = "Некроситет",
    RAID_MARA = "Мародон",
}

T.zh = {
    TITLE = "团队资格",
    READY = "已完成",
    STEPS = "%d / %d 步",
    NEXT = "下一步：",
    WHERE = "%s，%s",
    FORGET = "忘记角色",
    RAID_ONY = "奥妮克希亚的巢穴",
    RAID_UBRS = "黑石塔上层",
    RAID_BRD = "黑石深渊",
    RAID_SCHOLO = "通灵学院",
    RAID_MARA = "玛拉顿",
}

ns.T = T
ns.lang = CLIENT[GetLocale()] or "en"

ns.L = setmetatable({}, { __index = function(_, key)
    local t = T[ns.lang]
    return (t and t[key]) or T.en[key] or key
end })
