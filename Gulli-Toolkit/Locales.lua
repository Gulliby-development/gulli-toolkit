local _, ns = ...

-- The same languages as the Runeloader app and every Gulli module. The addon follows the
-- game client's language; English is the base and the fallback.
ns.TAGS = { "en", "de", "es", "fr", "pl", "pt", "ru", "zh" }

local CLIENT = { enUS = "en", enGB = "en", deDE = "de", esES = "es", esMX = "es", frFR = "fr",
                 ptBR = "pt", ptPT = "pt", ruRU = "ru", zhCN = "zh", zhTW = "zh" }

local T = {}

T.en = {
    TITLE = "Gulli Toolkit",
    SUBTITLE = "Our small addons in one place.",
    OPEN = "Open",
    NOT_INSTALLED = "Not installed",
    OFF = "Off",
    ON_TIP = "Switch the module on or off for every character.",
    RELOAD = "Reload",
    RELOAD_HINT = "Reload the interface to apply the changes.",
    GET = "Install the modules with Runeloader.",
    HELP = "/gulli opens the toolkit, /gulli <module> opens a module.",
    UNKNOWN = "No module called \"%s\".",
    OPEN_HUB = "Open Gulli Toolkit",
    M_QuestCleaner = "Quest Cleaner",
    D_QuestCleaner = "Abandons low-level quests and deletes leftover quest items.",
    M_MobFinder = "Mob Finder",
    D_MobFinder = "Plays a sound when a mob you look for shows its nameplate.",
    M_GroupBuffs = "Group Buffs",
    D_GroupBuffs = "Shows who in your group misses your buffs and buffs them in one click.",
}

T.de = {
    TITLE = "Gulli Toolkit",
    SUBTITLE = "Unsere kleinen Addons an einem Ort.",
    OPEN = "Öffnen",
    NOT_INSTALLED = "Nicht installiert",
    OFF = "Aus",
    ON_TIP = "Schaltet das Modul für alle Charaktere ein oder aus.",
    RELOAD = "Neu laden",
    RELOAD_HINT = "Lade die Oberfläche neu, um die Änderungen zu übernehmen.",
    GET = "Installiere die Module mit Runeloader.",
    HELP = "/gulli öffnet das Toolkit, /gulli <Modul> öffnet ein Modul.",
    UNKNOWN = "Kein Modul namens \"%s\".",
    OPEN_HUB = "Gulli Toolkit öffnen",
    M_QuestCleaner = "Quest Cleaner",
    D_QuestCleaner = "Bricht Quests niedriger Stufe ab und löscht übrige Questgegenstände.",
    M_MobFinder = "Mob Finder",
    D_MobFinder = "Spielt einen Ton, wenn ein gesuchter Gegner seine Namensplakette zeigt.",
    M_GroupBuffs = "Group Buffs",
    D_GroupBuffs = "Zeigt, wem in deiner Gruppe deine Buffs fehlen, und bufft mit einem Klick.",
}

T.es = {
    TITLE = "Gulli Toolkit",
    SUBTITLE = "Nuestros pequeños addons en un solo lugar.",
    OPEN = "Abrir",
    NOT_INSTALLED = "No instalado",
    OFF = "Apagado",
    ON_TIP = "Activa o desactiva el módulo para todos los personajes.",
    RELOAD = "Recargar",
    RELOAD_HINT = "Recarga la interfaz para aplicar los cambios.",
    GET = "Instala los módulos con Runeloader.",
    HELP = "/gulli abre el toolkit, /gulli <módulo> abre un módulo.",
    UNKNOWN = "No hay ningún módulo llamado \"%s\".",
    OPEN_HUB = "Abrir Gulli Toolkit",
    M_QuestCleaner = "Quest Cleaner",
    D_QuestCleaner = "Abandona misiones de nivel bajo y borra los objetos de misión sobrantes.",
    M_MobFinder = "Mob Finder",
    D_MobFinder = "Suena cuando un enemigo que buscas muestra su placa de nombre.",
    M_GroupBuffs = "Group Buffs",
    D_GroupBuffs = "Muestra a quién de tu grupo le faltan tus beneficios y los lanza con un clic.",
}

T.fr = {
    TITLE = "Gulli Toolkit",
    SUBTITLE = "Nos petits addons au même endroit.",
    OPEN = "Ouvrir",
    NOT_INSTALLED = "Non installé",
    OFF = "Désactivé",
    ON_TIP = "Active ou désactive le module pour tous les personnages.",
    RELOAD = "Recharger",
    RELOAD_HINT = "Rechargez l'interface pour appliquer les changements.",
    GET = "Installez les modules avec Runeloader.",
    HELP = "/gulli ouvre le toolkit, /gulli <module> ouvre un module.",
    UNKNOWN = "Aucun module nommé \"%s\".",
    OPEN_HUB = "Ouvrir Gulli Toolkit",
    M_QuestCleaner = "Quest Cleaner",
    D_QuestCleaner = "Abandonne les quêtes de bas niveau et supprime les objets de quête restants.",
    M_MobFinder = "Mob Finder",
    D_MobFinder = "Joue un son quand un monstre recherché affiche sa barre de nom.",
    M_GroupBuffs = "Group Buffs",
    D_GroupBuffs = "Montre à qui il manque vos améliorations dans le groupe et les lance en un clic.",
}

T.pl = {
    TITLE = "Gulli Toolkit",
    SUBTITLE = "Nasze małe dodatki w jednym miejscu.",
    OPEN = "Otwórz",
    NOT_INSTALLED = "Niezainstalowany",
    OFF = "Wył.",
    ON_TIP = "Włącza lub wyłącza moduł dla wszystkich postaci.",
    RELOAD = "Przeładuj",
    RELOAD_HINT = "Przeładuj interfejs, aby zastosować zmiany.",
    GET = "Zainstaluj moduły przez Runeloader.",
    HELP = "/gulli otwiera toolkit, /gulli <moduł> otwiera moduł.",
    UNKNOWN = "Nie ma modułu \"%s\".",
    OPEN_HUB = "Otwórz Gulli Toolkit",
    M_QuestCleaner = "Quest Cleaner",
    D_QuestCleaner = "Porzuca zadania niskiego poziomu i usuwa zbędne przedmioty z zadań.",
    M_MobFinder = "Mob Finder",
    D_MobFinder = "Gra dźwięk, gdy szukany potwór pokaże swoją tabliczkę z nazwą.",
    M_GroupBuffs = "Group Buffs",
    D_GroupBuffs = "Pokazuje, komu w grupie brakuje twoich buffów, i buffuje jednym kliknięciem.",
}

T.pt = {
    TITLE = "Gulli Toolkit",
    SUBTITLE = "Nossos pequenos addons em um só lugar.",
    OPEN = "Abrir",
    NOT_INSTALLED = "Não instalado",
    OFF = "Desligado",
    ON_TIP = "Liga ou desliga o módulo para todos os personagens.",
    RELOAD = "Recarregar",
    RELOAD_HINT = "Recarregue a interface para aplicar as mudanças.",
    GET = "Instale os módulos com o Runeloader.",
    HELP = "/gulli abre o toolkit, /gulli <módulo> abre um módulo.",
    UNKNOWN = "Nenhum módulo chamado \"%s\".",
    OPEN_HUB = "Abrir Gulli Toolkit",
    M_QuestCleaner = "Quest Cleaner",
    D_QuestCleaner = "Abandona missões de nível baixo e apaga os itens de missão que sobraram.",
    M_MobFinder = "Mob Finder",
    D_MobFinder = "Toca um som quando um inimigo procurado mostra sua placa de nome.",
    M_GroupBuffs = "Group Buffs",
    D_GroupBuffs = "Mostra quem do grupo está sem seus bônus e os lança com um clique.",
}

T.ru = {
    TITLE = "Gulli Toolkit",
    SUBTITLE = "Все наши маленькие аддоны в одном месте.",
    OPEN = "Открыть",
    NOT_INSTALLED = "Не установлен",
    OFF = "Выкл.",
    ON_TIP = "Включает или выключает модуль для всех персонажей.",
    RELOAD = "Перезагрузить",
    RELOAD_HINT = "Перезагрузите интерфейс, чтобы применить изменения.",
    GET = "Модули можно установить через Runeloader.",
    HELP = "/gulli открывает toolkit, /gulli <модуль> открывает модуль.",
    UNKNOWN = "Нет модуля \"%s\".",
    OPEN_HUB = "Открыть Gulli Toolkit",
    M_QuestCleaner = "Quest Cleaner",
    D_QuestCleaner = "Бросает квесты низкого уровня и удаляет ненужные квестовые предметы.",
    M_MobFinder = "Mob Finder",
    D_MobFinder = "Играет звук, когда у искомого моба появляется полоска с именем.",
    M_GroupBuffs = "Group Buffs",
    D_GroupBuffs = "Показывает, у кого в группе нет ваших баффов, и баффает в один клик.",
}

T.zh = {
    TITLE = "Gulli Toolkit",
    SUBTITLE = "我们的小插件集中在一处。",
    OPEN = "打开",
    NOT_INSTALLED = "未安装",
    OFF = "关闭",
    ON_TIP = "为所有角色启用或停用此模块。",
    RELOAD = "重载",
    RELOAD_HINT = "重载界面以应用更改。",
    GET = "可用 Runeloader 安装模块。",
    HELP = "/gulli 打开工具箱，/gulli <模块> 打开一个模块。",
    UNKNOWN = "没有名为“%s”的模块。",
    OPEN_HUB = "打开 Gulli Toolkit",
    M_QuestCleaner = "Quest Cleaner",
    D_QuestCleaner = "放弃低等级任务并删除多余的任务物品。",
    M_MobFinder = "Mob Finder",
    D_MobFinder = "当你寻找的怪物显示姓名板时播放声音。",
    M_GroupBuffs = "Group Buffs",
    D_GroupBuffs = "显示队伍中谁缺少你的增益效果，一键施放。",
}

ns.T = T
ns.lang = CLIENT[GetLocale()] or "en"

ns.L = setmetatable({}, { __index = function(_, key)
    local t = T[ns.lang]
    return (t and t[key]) or T.en[key] or key
end })
