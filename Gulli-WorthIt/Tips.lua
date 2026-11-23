-- What to do for each reward, step by step, in every language. Written by hand from the quest
-- texts and the players' comments on Wowhead's WoW Forever pages
-- (tools/worthit/wowhead-comments.json); `python3 tools/worthit/comments.py` shows what is new.
-- Quest -> two to four short steps. Names of NPCs, quests and items stay English.
local _, ns = ...
local T = {}

T.en = {
[97583] = {
    "Buy Nutritious Slime Sludge from Boyle by the canal in Undercity, 56, 64.",
    "Find an Excitable Slime that patrols the canals. Stand on the canal steps, not in the water, target it and type /dance.",
    "It can take from 5 to 100 dances. When it wriggles in place and faces you, take its quest, WRIGGLE., and give it the sludge for the pet.",
},
[95534] = {
    "Loot a Singed Note from the Syndicate Wizards or Argus Shadow Mages in Alterac Mountains. It starts the quest.",
    "In the Strahnbrad forge, 59, 46, set both bellows on fire close together: a Mage's Flamestrike, Easy Throw Dynamite, a Hunter's fire trap, Rain of Fire or Hellfire, or two players at once.",
    "The fire elemental lands between the bellows. Stay where it lands, or it vanishes, and kill it. Standing by the forge pulls the Syndicate nearby.",
    "Hand it in at Southshore (Alliance, Kundric Zanden) or Tarren Mill (Horde, Shara Blazen) for the Brilliant Cloak.",
},
[93176] = {
    "Amaryllis Webb in the west of Swamp of Sorrows, 25, 53, gives the quest and an Entomology Starter Kit, from level 25.",
    "Catch one of each with the kit: an Arbor Tarantula at the logging camp of northern Stranglethorn, 44, 20, a Hay Weevil on the Arathi farms, 31, 28, and a Flesh Picker at Desolace's Kodo Graveyard, 52, 58.",
    "Bring the three specimens back to Amaryllis for the pet Weevil K. Neevil.",
},
[97029] = {
    "Get the Ancient Heirloom ring: Skyborne take Coming of Age from Ailee Farheart; anyone else loots it on the top floor of the building at Zephras Isle 41.7, 23.4.",
    "Take a Night Watchman's Torch from the guard's body in Duskwood (An Unfortunate End), light it and use it in the Ruins of Ban'aethal, Zephras Isle 58, 24, while the dragon there sleeps. The Ancient Hilt appears.",
    "Bring the hilt to Ealaane Nimbuswalker in Valanaar, 66, 74, then find the Ancient Skyborne Blade: one at a time lies at 49, 73, 50, 44, 66, 43 or 60, 82.",
    "Bring the blade back to Ealaane for Eluvi'ana. The rest of the Dawn Waker secret is not solved yet: keep the sword and the ring.",
},
[-221315] = {
    "In Blackrock Depths take the bridge just east of the Ring of Law that runs north over the lava.",
    "On its left side, by a small brazier, jump from the railing onto the platform against the wall. Walk to its end and run along the wall, left shoulder to it, until you drop onto the ledge below.",
    "The toy Traveler's Symbols lies on the ledge. The door there only takes you down to Lord Incendius.",
},
[-268109] = {
    "Go to the rock at the top of the waterfall on Zephras Isle, 51, 72, where frogs sing.",
    "Wait until at least two frogs sit on the rock, target one and type /sing.",
    "The frogs vanish and a Musical Gustjumper appears on the log beside you: click it to get the pet.",
},
[-282047] = {
    "The Sewer Beast, level 50, swims in the Stormwind canals, 71, 49 and 71, 68.",
    "It drops the Baby Crocolisk pet, but not every time: kill it again when it comes back.",
},
[95805] = {
    "Do both parts of A Humble Task first: the chief's mother stands at the water well, 50, 81.",
    "Seer Graytongue is in the hills south of Camp Narache, 42, 92. Any Horde race can take the quest.",
    "Carry the incense to the shrine in the southeastern hills within ten minutes. Stay out of the water.",
},
[91775] = {
    "The Nibbled-On Book drops from kobolds in Northshire. The three kobold quests there give all 8 Stolen Books too.",
    "Shinyfinder Narf, a level 3 elite, is in the Echo Ridge Mine: take the second turn to the right.",
    "On the way to Goldshire click 6 kobold tracks near the trees south of Northshire. They count even when the tracking kit refuses to work.",
    "Fun with Elementals drops from Nimsy in the Fargodeep Mine: upper entrance, east from the big room and up the stairs. He has guards, so bring a friend.",
},
[92515] = {
    "The quest opens after Welcome to Shen'dar Village: speak with Illaya Amberwind in the middle of the village and Coriella Calmbreeze at the inn.",
    "Then kill Prideclaws in the Shen'dar Highlands around the village for 10 pelts.",
},
[97277] = {
    "From Anvilmar's front door take the road to the left. On its right side a faint snowy trail climbs the mountain, past the first tree and some crates.",
    "The path is steep, but you can climb it. The camp is right behind the ridge.",
    "Kill the Snow Leopard Prowler, pick up the log from the ground and go back the same way.",
},
[791] = {
    "Furl Scornbrow stands in the watchtower of Razor Hill.",
    "Canvas Scraps drop often from the humans of Tiragarde Keep, 58, 53. Sailors drop more than the others.",
},
[86784] = {
    "Dry Branches lie near groups of trees and look like the ground. Move the mouse around: the cursor turns into a gear over a branch.",
    "Three lie around the trees at 55, 55 and come back after about 30 seconds.",
    "Eleanor Shackleton's camp is in the hills to the west, 57, 55.",
},
[87288] = {
    "Only the level 5-6 Nightsabers drop the pelts, and there are few of them.",
    "Walk in zigzags through the woods east of Dolanaar and leave the furbolg village aside.",
    "The pelts drop rarely, so it takes a while. Any Alliance race can do the quest.",
},
[99053] = {
    "Sentinel Lynessa waits on the lowest level of the Ban'ethil Barrow Den, in an alcove.",
    "Finish your other quests in the den first and clear the way out: you walk her all the way to the road.",
    "Stay close to her. She runs at every enemy nearby, and the quest fails when she gets too far from you.",
},
[151] = {
    "The oats are in Sacks of Oats on the fields and farms of Westfall.",
    "Saldean's Farm: (56, 31), (52, 34), (52, 32). The Molsen Farm: (46, 38), (45, 35). Furlbrow's Pumpkin Farm: (49, 21), (50, 18).",
    "A sack comes back only after 5 to 10 minutes, so go on to the next farm.",
},
[97253] = {
    "The parts look like trash on the ground of the upper pirate camp south of Ratchet.",
    "Look beside the tents, not inside them.",
},
[140] = {
    "The treasure map drops from murlocs on the coast of Westfall.",
    "The footlocker is on the beach at 26, 48, by the anchor near the sunken ship.",
    "The broken barrel stands by the road at 40, 47, near the ruined chimney. The jug lies beside a log at the windmill, 40, 17.",
    "The chest is on the biggest of the three islands west of the jug, 26, 17.",
},
[1003] = {
    "Buzzbox 827 is in Auberdine at 37, 46, next to the hippogryph platform. Crawlers further north on the coast drop legs more often.",
    "Buzzbox 411 is on the beach north of Auberdine, just east of the shipwrecks. The threshers swim in deep water.",
    "Buzzbox 323: follow the road northeast and cross the bridge over the Cliffspring River. The box is left of the road.",
    "Buzzbox 525 is at 41, 80, right of the road south to Ashenvale. Scalps drop rarely, so expect many bears.",
},
[1486] = {
    "Nalpak is in the cave above the entrance of the Wailing Caverns: climb on top of the entrance, turn around at the edge and take the left hole.",
    "Deviate beasts in the caverns drop the hides. 20 hides take more than one round.",
    "Fastest inside the dungeon: kill the raptors on the way to the water and the crocolisks, reset the dungeon and repeat.",
},
[97926] = {
    "Set your hearthstone in Auberdine, then take the new boat from Auberdine to Stormwind.",
    "Give the letter to Baros Alexston in Stormwind and take his reply.",
    "Use the hearthstone back to Auberdine and hand in the reply.",
},
[531] = {
    "The first two quests run on a timer. Buzzards fly around 78, 65, that one is easy.",
    "There are only about 7 Elder Mountain Boars in the zone, and you have 12 minutes for 5. Find them before you take the quest.",
    "Ol' Sooty walks between his cave south of Thelsamar (37, 62) and the lake. He may take 10 to 20 minutes to come back.",
},
[1474] = {
    "Dalin Forgewright stands at the Greymane Wall in the south of Silverpine Forest, about 46, 86.",
    "Comar Villard is in the Wetlands at Dun Modr, right behind the bridge from Arathi, 50, 12.",
    "Summon the succubus with your voidwalker already out.",
    "The chain that starts in Orgrimmar gives the same reward and is easier.",
},
[1513] = {
    "Zankaja is west of the wind rider tower in Orgrimmar, not of the zeppelin tower as the quest says: cross the bridge and turn right.",
    "Gazrog stands in front of the inn at the Crossroads, 51, 30. Ken'zigla is at Malaka'jin in Stonetalon, 73, 95.",
    "Dogran is held in the Barrens at 43, 47, west of the bridge between the Crossroads and Camp Taurajo. Quilboars guard the huts, sometimes an elite.",
    "The summoning circle is in Neeru's tent, outside the Cleft of Shadow to the left. Call your voidwalker first.",
},
[1739] = {
    "Takar the Seer has a tent beside two trees near Camp Taurajo in the Barrens. Come from Theramore and walk on the hilltops, away from the Horde guards.",
    "The Heartswood is the big tree in the Ruins of Ordil'Aran in Ashenvale, 31, 31, near Maestra's Post. Right-click the tree.",
    "Bring it to Gakin in Stormwind, not back to the Barrens. Summon the succubus with your voidwalker out.",
},
[470] = {
    "The bag is a random drop from the oozes of the Wetlands, of any kind.",
    "Some get it after 3 kills, some after 100. Oozes away from Ironbeard's Tomb can drop it too.",
},
[79192] = {
    "Horde: take the note from the burned-out fire in the Barrens, 46, 73, and bring it to the same kind of fire in Westfall, 37, 50. Alliance: the other way round.",
    "The next note sends you to Stonetalon. From the road at about 51, 51 go through the opening into the mountains and follow the path up to the camp.",
    "The Pocket Litter that ends the quest lies at that camp.",
},
[79976] = {
    "First do Stepping Stones (see that reward). The camp's next note, Scramble, sends you north up the hill to a Mound of Dirt in Stonetalon, 39, 49.",
    "Wet Job: in Loch Modan go to the middle of the big dam in the north and drop onto the ledge with the Carved Figurine, 49, 12. Horde: the guards there are strong.",
    "Eagle's Fist: the Messenger Bag is on Thoradin's Wall, Arathi 22, 24. North of the gate, on the Hillsbrad side, jump from a broken cart: the barrel, the plank on the right, the cart, the ladder, then the rocks.",
    "Hand it in and open the Hastily Rolled-Up Satchel beside it for the Cozy Sleeping Bag. Each minute of sleep in it gives +1% XP, up to +3%.",
},
[93269] = {
    "Sebelia at the top of Mount Hyjal, 71, 52, gives Mending Communications. The way up is closed: Evie Whirlbrew in Everlook, 61, 38, makes the Potion of Winterspring Shrouding that gets you there.",
    "Bring the parcels down to Innkeeper Vizzie in Everlook, 61, 39.",
    "Unfrozen Deliveries: the Missing Mail drops only from Ice Thistle Yetis (not Rogue ones, Matriarchs or Patriarchs), north of Everlook and by the yeti cave to the southeast. Do it with Are We There, Yeti?",
    "Top of the Post: carry the mail back up to Sebelia. She gives the 18-slot Hyjal Postal Satchel.",
},
[96260] = {
    "Gloomrise can be reached from Mulgore at 40, 17, from Malaka'jin in Stonetalon (the path starts at 73, 96) and from Desolace at 77, 36.",
    "Gloomrise Spinners drop the Crystalline Silk. You need 3 strands.",
    "You choose a bag or a reagent sack. Players take the sack when they craft: an ordinary silk bag is cheap at the auction house.",
},
[58] = {
    "Skeletal Warriors and Mages walk in the Tranquil Gardens Cemetery, 80, 70.",
    "Skeletal Fiends and Horrors are at the Raven Hill cemetery, around 16, 44.",
    "Plague Spreaders are in the east of Raven Hill. When there are too few, go down into the crypt: more of them walk in its big rooms.",
},
[1795] = {
    "The Moldy Tome lies in a murloc camp on the coast southwest of Southshore in Hillsbrad, a bluish book by the water.",
    "The Tattered Manuscript is in a small chest in Splithoof Hold in Thousand Needles, 44, 37: inside take the first way to the right.",
    "Rods of Channeling drop from the Dragonmaw orcs of the Angerfang Encampment in the Wetlands. The back way in is at 51, 45.",
    "Your own demon may fight the felhunter with you. If you fail, abandon the quest and take it again.",
},
[96109] = {
    "Neza Bloodsnout at Rog'mar gives three quests one after another.",
    "A feather drops from about one buzzard in three, for some players far fewer.",
    "The vipers are by the pools south of Rog'mar, the lions on the hill to the south that you can see from the camp.",
},
[2439] = {
    "In Uldaman kill Archaedas, the last boss. The door behind him opens to the treasure room.",
    "Click the Discs of Norgannon, talk to the stone watcher that appears until he has nothing more to say, then click the discs again.",
    "Bring the small discs to the Explorers' League in the Hall of Explorers in Ironforge.",
    "Dinita Stonemantle, who takes the voucher, stands on the left side of the Ironforge bank.",
},
[2440] = {
    "In Uldaman kill Archaedas, the last boss. The door behind him opens to the treasure room.",
    "Click the Discs of Norgannon, talk to the stone watcher that appears until he has nothing more to say, then click the discs again.",
    "Bring the small discs to Sage Truthseeker in Thunder Bluff, 35, 47.",
    "Bena Winterhoof, who takes the voucher, is at 46, 33 in Thunder Bluff.",
},
[626] = {
    "The first scroll lies in the lower hold of a Bloodsail ship off the coast of Stranglethorn. There are many pirates, so bring a group.",
    "Swamp of Sorrows: under the bridge right after the fork in the road, 22, 48. The scroll is hard to see, move the mouse over the water.",
    "Dustwallow Marsh: the raptor cave at 31, 66. The scroll lies on a rock at the back.",
    "The Hinterlands: the chest is under the big waterfall on the coast, 81, 47. Follow the river east, jump down from the rocks at the top and leave with the hearthstone.",
},
[3628] = {
    "Kirith is a level 55 elite in a cave in the east of the Blasted Lands. Do not loot on the way in, so the cave stays empty longer. Then talk to his spirit.",
    "Azshara: Loramus is on an island at 60, 66, Lord Arkkoroc in his temple at 77, 42. Hetaera swims past 56, 44 about every 15 minutes. The azsharite is on the southern cliffs around 51, 71.",
    "Galvan in Stranglethorn, 50, 20, forges the weapon. You need not wield it: tell the Fallen Hero you lost it and he gives a Fel Salve that works as well.",
    "In the Blasted Lands Allistarj is at 65, 33, Lady Sevine at 40, 30 and Grol at 43, 14. Bring five players for Razelikh.",
},
[84146] = {
    "Nami gives the quest only after a hidden chain. It starts on the south shore of Tanaris at 59, 91: walk along the shore from 63, 64.",
    "Keep the swim potion from the first quest. Swim south toward the lighthouse, then to the island: behind it is an oil rig with Sebastian Jurgens. Swim on through the fatigue with a healing potion ready.",
    "Then fly to Everlook, where Nami is. The bag lies up a hill beside a tent in the Burning Steppes.",
},
}

T.de = {
[97583] = {
    "Kaufe Nutritious Slime Sludge bei Boyle am Kanal in Undercity, 56, 64.",
    "Suche einen Excitable Slime, der durch die Kanäle zieht. Stell dich auf die Kanalstufen, nicht ins Wasser, nimm ihn ins Ziel und tippe /dance.",
    "Es kann 5 bis 100 Tänze dauern. Wenn er sich auf der Stelle windet und dich ansieht, nimm seine Quest WRIGGLE. an und gib ihm den Schleim für das Haustier.",
},
[95534] = {
    "Erbeute eine Singed Note von den Syndicate Wizards oder Argus Shadow Mages im Alterac-Gebirge. Sie startet die Quest.",
    "Setze in der Schmiede von Strahnbrad, 59, 46, beide Blasebälge kurz nacheinander in Brand: Flammenstoß des Magiers, Easy Throw Dynamite, eine Feuerfalle des Jägers, Feuerregen oder Höllenfeuer, oder zwei Spieler zugleich.",
    "Der Feuerelementar landet zwischen den Blasebälgen. Bleib dort stehen, sonst verschwindet er, und töte ihn. Wer an der Schmiede steht, zieht das Syndikat in der Nähe an.",
    "Gib sie in Southshore (Allianz, Kundric Zanden) oder Tarren Mill (Horde, Shara Blazen) ab: dafür gibt es den Brilliant Cloak.",
},
[93176] = {
    "Amaryllis Webb im Westen der Sümpfe des Elends, 25, 53, gibt ab Stufe 25 die Quest und ein Entomology Starter Kit.",
    "Fange mit dem Kit je eins: eine Arbor Tarantula am Holzfällerlager im Norden von Stranglethorn, 44, 20, einen Hay Weevil auf den Höfen von Arathi, 31, 28, und einen Flesh Picker auf dem Kodofriedhof in Desolace, 52, 58.",
    "Bring die drei Proben zu Amaryllis zurück: dafür gibt es das Haustier Weevil K. Neevil.",
},
[97029] = {
    "Hol dir den Ring Ancient Heirloom: Skyborne nehmen Coming of Age bei Ailee Farheart an, alle anderen finden ihn im obersten Stock des Gebäudes auf Zephras Isle, 41.7, 23.4.",
    "Nimm eine Night Watchman's Torch von der Leiche der Wache in Duskwood (An Unfortunate End), entzünde sie und benutze sie in den Ruins of Ban'aethal, Zephras Isle 58, 24, während der Drache dort schläft. Der Ancient Hilt erscheint.",
    "Bring den Griff zu Ealaane Nimbuswalker in Valanaar, 66, 74, und suche dann die Ancient Skyborne Blade: sie liegt immer an einer Stelle von 49, 73, 50, 44, 66, 43 oder 60, 82.",
    "Bring die Klinge zu Ealaane zurück: dafür gibt es Eluvi'ana. Der Rest des Dawn-Waker-Geheimnisses ist noch ungelöst: behalte Schwert und Ring.",
},
[-221315] = {
    "Nimm in den Schwarzfelstiefen die Brücke gleich östlich vom Ring des Gesetzes, die nach Norden über die Lava führt.",
    "Spring auf ihrer linken Seite beim kleinen Kohlebecken vom Geländer auf die Plattform an der Wand. Geh bis zu ihrem Ende und lauf mit der linken Schulter an der Wand entlang, bis du auf den Vorsprung darunter fällst.",
    "Das Spielzeug Traveler's Symbols liegt auf dem Vorsprung. Die Tür dort führt nur hinunter zu Lord Incendius.",
},
[-268109] = {
    "Geh zum Felsen oben am Wasserfall auf Zephras Isle, 51, 72, wo Frösche singen.",
    "Warte, bis mindestens zwei Frösche auf dem Felsen sitzen, nimm einen ins Ziel und tippe /sing.",
    "Die Frösche verschwinden und ein Musical Gustjumper erscheint auf dem Baumstamm neben dir: klick ihn an, um das Haustier zu bekommen.",
},
[-282047] = {
    "Das Sewer Beast, Stufe 50, schwimmt in den Kanälen von Stormwind, 71, 49 und 71, 68.",
    "Es lässt das Haustier Baby Crocolisk fallen, aber nicht jedes Mal: töte es wieder, wenn es zurückkommt.",
},
[95805] = {
    "Erledige zuerst beide Teile von A Humble Task: Die Mutter des Häuptlings steht am Brunnen, 50, 81.",
    "Seer Graytongue wohnt in den Hügeln südlich von Camp Narache, 42, 92. Jedes Volk der Horde kann die Quest annehmen.",
    "Trage den Weihrauch innerhalb von zehn Minuten zum Schrein in den südöstlichen Hügeln. Geh nicht ins Wasser.",
},
[91775] = {
    "Das Nibbled-On Book lassen Kobolde in Nordhain fallen. Die drei Koboldquests dort bringen auch alle 8 Stolen Books.",
    "Shinyfinder Narf, ein Elitegegner der Stufe 3, sitzt in der Echo Ridge Mine: zweite Abzweigung rechts.",
    "Klicke auf dem Weg nach Goldhain 6 Koboldspuren bei den Bäumen südlich von Nordhain an. Sie zählen auch, wenn das Spurenset nicht funktioniert.",
    "Fun with Elementals lässt Nimsy in der Fargodeep Mine fallen: oberer Eingang, vom großen Raum nach Osten und die Treppe hinauf. Er hat Wachen, nimm jemanden mit.",
},
[92515] = {
    "Die Quest gibt es nach Welcome to Shen'dar Village: Sprich mit Illaya Amberwind in der Dorfmitte und mit Coriella Calmbreeze im Gasthaus.",
    "Töte dann Prideclaws im Hochland von Shen'dar rund ums Dorf, bis du 10 Felle hast.",
},
[97277] = {
    "Nimm vor dem Haupttor von Anvilmar die Straße nach links. Rechts davon führt ein kaum sichtbarer Schneepfad den Berg hinauf, am ersten Baum und an Kisten vorbei.",
    "Der Pfad ist steil, aber begehbar. Das Lager liegt gleich hinter dem Kamm.",
    "Töte den Snow Leopard Prowler, heb das Logbuch vom Boden auf und geh denselben Weg zurück.",
},
[791] = {
    "Furl Scornbrow steht im Wachturm von Klingenhügel.",
    "Canvas Scraps lassen die Menschen der Burg Tiragarde oft fallen, 58, 53. Matrosen öfter als die anderen.",
},
[86784] = {
    "Dry Branches liegen bei Baumgruppen und sehen aus wie der Boden. Bewege die Maus: Über einem Ast wird der Zeiger zum Zahnrad.",
    "Drei liegen bei den Bäumen an 55, 55 und sind nach etwa 30 Sekunden wieder da.",
    "Das Lager von Eleanor Shackleton liegt in den Hügeln im Westen, 57, 55.",
},
[87288] = {
    "Nur Nightsabers der Stufe 5-6 lassen die Felle fallen, und es gibt wenige davon.",
    "Lauf im Zickzack durch den Wald östlich von Dolanaar und lass das Furbolgdorf aus.",
    "Die Felle fallen selten, es dauert also. Jedes Volk der Allianz kann die Quest machen.",
},
[99053] = {
    "Sentinel Lynessa wartet auf der untersten Ebene des Ban'ethil Barrow Den, in einer Nische.",
    "Erledige erst deine anderen Quests im Bau und räume den Weg nach draußen frei: Du begleitest sie bis zur Straße.",
    "Bleib bei ihr. Sie rennt auf jeden Gegner in der Nähe los, und die Quest scheitert, wenn sie zu weit von dir weg ist.",
},
[151] = {
    "Der Hafer steckt in den Sacks of Oats auf den Feldern und Höfen von Westfall.",
    "Saldeans Hof: (56, 31), (52, 34), (52, 32). Molsens Hof: (46, 38), (45, 35). Furlbrows Kürbishof: (49, 21), (50, 18).",
    "Ein Sack ist erst nach 5 bis 10 Minuten wieder da, geh also zum nächsten Hof.",
},
[97253] = {
    "Die Teile sehen aus wie Müll auf dem Boden des oberen Piratenlagers südlich von Ratschet.",
    "Such neben den Zelten, nicht in ihnen.",
},
[140] = {
    "Die Schatzkarte lassen Murlocs an der Küste von Westfall fallen.",
    "Die Truhe steht am Strand bei 26, 48, am Anker neben dem Schiffswrack.",
    "Das kaputte Fass steht an der Straße bei 40, 47, beim zerfallenen Kamin. Der Krug liegt neben einem Baumstamm an der Windmühle, 40, 17.",
    "Die Kiste steht auf der größten der drei Inseln westlich vom Krug, 26, 17.",
},
[1003] = {
    "Buzzbox 827 steht in Auberdine bei 37, 46, neben der Hippogryphenplattform. Krabben weiter nördlich an der Küste lassen öfter Beine fallen.",
    "Buzzbox 411 steht am Strand nördlich von Auberdine, gleich östlich der Wracks. Die Drescher schwimmen im tiefen Wasser.",
    "Buzzbox 323: Folge der Straße nach Nordosten über die Brücke am Cliffspring River. Die Box steht links der Straße.",
    "Buzzbox 525 steht bei 41, 80, rechts der Straße nach Süden ins Eschental. Skalps fallen selten, rechne mit vielen Bären.",
},
[1486] = {
    "Nalpak sitzt in der Höhle über dem Eingang der Höhlen des Wehklagens: Klettere auf den Eingang, dreh dich am Rand um und nimm das linke Loch.",
    "Die Felle lassen die Deviate-Tiere in den Höhlen fallen. 20 Felle brauchen mehr als eine Runde.",
    "Am schnellsten im Dungeon: Töte die Raptoren auf dem Weg zum Wasser und die Krokilisken, setz den Dungeon zurück und wiederhole.",
},
[97926] = {
    "Setze deinen Ruhestein in Auberdine und nimm dort das neue Schiff nach Sturmwind.",
    "Gib den Brief Baros Alexston in Sturmwind und nimm seine Antwort mit.",
    "Reise mit dem Ruhestein zurück nach Auberdine und gib die Antwort ab.",
},
[531] = {
    "Die ersten beiden Quests laufen auf Zeit. Bussarde fliegen um 78, 65, das ist leicht.",
    "Es gibt nur etwa 7 Elder Mountain Boars im Gebiet, und du hast 12 Minuten für 5. Such sie, bevor du die Quest annimmst.",
    "Ol' Sooty läuft zwischen seiner Höhle südlich von Thelsamar (37, 62) und dem See. Es kann 10 bis 20 Minuten dauern, bis er wieder da ist.",
},
[1474] = {
    "Dalin Forgewright steht am Graumähnenwall im Süden des Silberwalds, etwa 46, 86.",
    "Comar Villard ist im Sumpfland bei Dun Modr, gleich hinter der Brücke aus Arathi, 50, 12.",
    "Beschwöre den Sukkubus erst, wenn dein Leerwandler schon da ist.",
    "Die Kette, die in Orgrimmar beginnt, gibt dieselbe Belohnung und ist leichter.",
},
[1513] = {
    "Zankaja steht westlich vom Windreiterturm in Orgrimmar, nicht vom Zeppelinturm, wie die Quest sagt: über die Brücke und dann rechts.",
    "Gazrog steht vor dem Gasthaus im Wegekreuz, 51, 30. Ken'zigla ist in Malaka'jin im Steinkrallengebirge, 73, 95.",
    "Dogran wird im Brachland bei 43, 47 gefangen gehalten, westlich der Brücke zwischen Wegekreuz und Camp Taurajo. Stacheleber bewachen die Hütten, manchmal ein Elitegegner.",
    "Der Beschwörungskreis ist in Neerus Zelt, draußen links von der Kluft der Schatten. Ruf zuerst deinen Leerwandler.",
},
[1739] = {
    "Takar the Seer hat ein Zelt neben zwei Bäumen bei Camp Taurajo im Brachland. Komm von Theramore und lauf oben über die Hügel, weg von den Wachen der Horde.",
    "Das Heartswood ist der große Baum in den Ruinen von Ordil'Aran im Eschental, 31, 31, bei Maestras Posten. Rechtsklick auf den Baum.",
    "Bring es zu Gakin nach Sturmwind, nicht zurück ins Brachland. Beschwöre den Sukkubus mit dem Leerwandler an deiner Seite.",
},
[470] = {
    "Die Tasche fällt zufällig von den Schlammen im Sumpfland, egal von welchen.",
    "Manche haben sie nach 3 Kills, manche nach 100. Auch Schlamme fern von Ironbeard's Tomb lassen sie fallen.",
},
[79192] = {
    "Horde: Nimm die Notiz am erloschenen Feuer im Brachland, 46, 73, und bring sie zum gleichen Feuer in Westfall, 37, 50. Allianz: andersherum.",
    "Die nächste Notiz schickt dich ins Steinkrallengebirge. Geh von der Straße bei etwa 51, 51 durch die Öffnung in die Berge und folge dem Pfad hinauf zum Lager.",
    "Das Pocket Litter, das die Quest abschließt, liegt in diesem Lager.",
},
[79976] = {
    "Mach zuerst Stepping Stones (siehe diese Belohnung). Die nächste Notiz im Lager, Scramble, schickt dich nach Norden den Hügel hinauf zu einem Mound of Dirt im Steinkrallengebirge, 39, 49.",
    "Wet Job: Geh in Loch Modan zur Mitte des großen Damms im Norden und lass dich auf den Vorsprung mit der Carved Figurine fallen, 49, 12. Horde: Die Wachen dort sind stark.",
    "Eagle's Fist: Die Messenger Bag liegt auf Thoradins Wall, Arathi 22, 24. Nördlich des Tores, auf der Seite von Hillsbrad, spring von einem kaputten Karren hoch: Fass, Brett rechts, Karren, Leiter, dann die Felsen.",
    "Gib sie ab und öffne die Hastily Rolled-Up Satchel daneben: darin ist der Cozy Sleeping Bag. Jede Minute Schlaf darin gibt +1% EP, bis zu +3%.",
},
[93269] = {
    "Sebelia auf dem Gipfel des Hyjal, 71, 52, gibt Mending Communications. Der Weg hinauf ist versperrt: Evie Whirlbrew in Ewige Warte, 61, 38, braut den Potion of Winterspring Shrouding, der euch hinaufbringt.",
    "Bringt die Pakete hinunter zu Innkeeper Vizzie in Ewige Warte, 61, 39.",
    "Unfrozen Deliveries: Die 4 Missing Mail droppen nur Ice Thistle Yetis (nicht die Rogue, Matriarchs oder Patriarchs), in den Hügeln nördlich von Ewige Warte und bei der Yetihöhle im Südosten. Erledigt es zusammen mit Are We There, Yeti?",
    "Top of the Post: Bringt die Post wieder hinauf zu Sebelia. Sie gibt die Hyjal Postal Satchel mit 18 Plätzen.",
},
[96260] = {
    "Nach Gloomrise kommst du von Mulgore bei 40, 17, von Malaka'jin im Steinkrallengebirge (der Pfad beginnt bei 73, 96) und von Desolace bei 77, 36.",
    "Crystalline Silk lassen die Gloomrise Spinners fallen. Du brauchst 3 Fäden.",
    "Du wählst eine Tasche oder einen Reagenzienbeutel. Wer herstellt, nimmt den Beutel: Eine normale Seidentasche ist im Auktionshaus billig.",
},
[58] = {
    "Skeletal Warriors und Skeletal Mages laufen auf dem Friedhof Tranquil Gardens, 80, 70.",
    "Skeletal Fiends und Skeletal Horrors sind auf dem Friedhof von Rabenflucht, um 16, 44.",
    "Plague Spreaders sind im Osten von Rabenflucht. Sind es zu wenige, geh hinunter in die Gruft: In ihren großen Räumen laufen mehr.",
},
[1795] = {
    "Das Moldy Tome liegt in einem Murloclager an der Küste südwestlich von Süderstade im Hügelland, ein bläuliches Buch am Wasser.",
    "Das Tattered Manuscript liegt in einer kleinen Truhe im Splithoof Hold in Tausend Nadeln, 44, 37: drinnen den ersten Weg nach rechts.",
    "Rods of Channeling lassen die Drachenmalorcs im Lager Angerfang im Sumpfland fallen. Der Hintereingang ist bei 51, 45.",
    "Dein eigener Dämon darf gegen den Teufelsjäger mitkämpfen. Wenn es scheitert, brich die Quest ab und nimm sie neu an.",
},
[96109] = {
    "Neza Bloodsnout in Rog'mar gibt drei Quests nacheinander.",
    "Eine Feder fällt etwa von jedem dritten Bussard, bei manchen Spielern viel seltener.",
    "Die Vipern sind an den Teichen südlich von Rog'mar, die Löwen auf dem Hügel im Süden, den du vom Lager aus siehst.",
},
[2439] = {
    "Töte in Uldaman Archaedas, den letzten Boss. Die Tür hinter ihm führt in die Schatzkammer.",
    "Klicke die Discs of Norgannon an, sprich mit dem Steinwächter, der erscheint, bis er nichts mehr sagt, und klicke die Scheiben noch einmal an.",
    "Bring die kleinen Scheiben zur Forscherliga in der Halle der Forscher in Eisenschmiede.",
    "Dinita Stonemantle, die den Gutschein nimmt, steht links in der Bank von Eisenschmiede.",
},
[2440] = {
    "Töte in Uldaman Archaedas, den letzten Boss. Die Tür hinter ihm führt in die Schatzkammer.",
    "Klicke die Discs of Norgannon an, sprich mit dem Steinwächter, der erscheint, bis er nichts mehr sagt, und klicke die Scheiben noch einmal an.",
    "Bring die kleinen Scheiben zu Sage Truthseeker in Donnerfels, 35, 47.",
    "Bena Winterhoof, die den Gutschein nimmt, steht bei 46, 33 in Donnerfels.",
},
[626] = {
    "Die erste Schriftrolle liegt im unteren Laderaum eines Blutsegelschiffs vor der Küste des Schlingendorntals. Es sind viele Piraten, nimm eine Gruppe mit.",
    "Sümpfe des Elends: unter der Brücke gleich nach der Weggabelung, 22, 48. Die Rolle ist schwer zu sehen, fahr mit der Maus über das Wasser.",
    "Düstermarschen: die Raptorhöhle bei 31, 66. Die Rolle liegt hinten auf einem Felsen.",
    "Hinterland: Die Truhe steht unter dem großen Wasserfall an der Küste, 81, 47. Folge dem Fluss nach Osten, spring oben von den Felsen und geh mit dem Ruhestein.",
},
[3628] = {
    "Kirith ist ein Elitegegner der Stufe 55 in einer Höhle im Osten der Verwüsteten Lande. Plündere auf dem Weg hinein nicht, dann bleibt die Höhle länger leer. Sprich danach mit seinem Geist.",
    "Azshara: Loramus ist auf einer Insel bei 60, 66, Lord Arkkoroc in seinem Tempel bei 77, 42. Hetaera schwimmt etwa alle 15 Minuten bei 56, 44 vorbei. Das Azsharit liegt auf den südlichen Klippen um 51, 71.",
    "Galvan im Schlingendorntal, 50, 20, schmiedet die Waffe. Du musst sie nicht tragen: Sag dem Fallen Hero, du hast sie verloren, und er gibt dir eine Fel Salve, die genauso wirkt.",
    "In den Verwüsteten Landen ist Allistarj bei 65, 33, Lady Sevine bei 40, 30 und Grol bei 43, 14. Nimm für Razelikh fünf Spieler mit.",
},
[84146] = {
    "Nami gibt die Quest erst nach einer versteckten Kette. Sie beginnt am Südufer von Tanaris bei 59, 91: Geh ab 63, 64 am Ufer entlang.",
    "Behalte den Schwimmtrank aus der ersten Quest. Schwimm nach Süden zum Leuchtturm, dann zur Insel: Dahinter liegt eine Bohrinsel mit Sebastian Jurgens. Schwimm durch die Erschöpfung weiter und halte einen Heiltrank bereit.",
    "Flieg dann zur Ewigen Warte, dort ist Nami. Die Tasche liegt auf einem Hügel neben einem Zelt in der Brennenden Steppe.",
},
}

T.es = {
[97583] = {
    "Compra Nutritious Slime Sludge a Boyle junto al canal de Entrañas, 56, 64.",
    "Busca un Excitable Slime que patrulla los canales. Ponte en los escalones del canal, no en el agua, selecciónalo y escribe /dance.",
    "Puede llevar de 5 a 100 bailes. Cuando se retuerce en el sitio mirándote, acepta su misión, WRIGGLE., y dale el lodo para conseguir la mascota.",
},
[95534] = {
    "Despoja una Singed Note de los Syndicate Wizards o Argus Shadow Mages de las Montañas de Alterac. Inicia la misión.",
    "En la forja de Strahnbrad, 59, 46, prende fuego a los dos fuelles casi a la vez: Fogonazo de mago, Easy Throw Dynamite, una trampa de fuego de cazador, Lluvia de fuego o Llamas infernales, o dos jugadores a la vez.",
    "El elemental de fuego cae entre los fuelles. Quédate donde cae, o desaparece, y mátalo. Estar junto a la forja atrae a la Hermandad cercana.",
    "Entrégala en Costasur (Alianza, Kundric Zanden) o Molino Tarren (Horda, Shara Blazen) para obtener la Brilliant Cloak.",
},
[93176] = {
    "Amaryllis Webb, al oeste del Pantano de las Penas, 25, 53, da la misión y un Entomology Starter Kit desde el nivel 25.",
    "Atrapa uno de cada con el kit: una Arbor Tarantula en el campamento maderero del norte de Tuercespina, 44, 20, un Hay Weevil en las granjas de Arathi, 31, 28, y un Flesh Picker en el Cementerio de Kodos de Desolace, 52, 58.",
    "Lleva los tres ejemplares a Amaryllis para conseguir la mascota Weevil K. Neevil.",
},
[97029] = {
    "Consigue el anillo Ancient Heirloom: los Skyborne hacen Coming of Age de Ailee Farheart; los demás lo cogen en el piso de arriba del edificio de Zephras Isle, 41.7, 23.4.",
    "Toma una Night Watchman's Torch del cuerpo del guardia en Bosque del Ocaso (An Unfortunate End), enciéndela y úsala en las Ruins of Ban'aethal, Zephras Isle 58, 24, mientras el dragón de allí duerme. Aparece el Ancient Hilt.",
    "Lleva la empuñadura a Ealaane Nimbuswalker en Valanaar, 66, 74, y busca la Ancient Skyborne Blade: aparece en un solo sitio cada vez, 49, 73, 50, 44, 66, 43 o 60, 82.",
    "Devuelve la hoja a Ealaane para obtener Eluvi'ana. El resto del secreto Dawn Waker aún no se ha resuelto: guarda la espada y el anillo.",
},
[-221315] = {
    "En las Profundidades de Roca Negra toma el puente justo al este del Anillo de la Ley que va al norte sobre la lava.",
    "En su lado izquierdo, junto a un pequeño brasero, salta de la barandilla a la plataforma pegada al muro. Ve hasta su final y corre pegado al muro, con el hombro izquierdo, hasta caer en la cornisa de abajo.",
    "El juguete Traveler's Symbols está en la cornisa. La puerta de allí solo baja hasta Lord Incendius.",
},
[-268109] = {
    "Ve a la roca en lo alto de la cascada de Zephras Isle, 51, 72, donde cantan las ranas.",
    "Espera a que haya al menos dos ranas en la roca, selecciona una y escribe /sing.",
    "Las ranas desaparecen y un Musical Gustjumper aparece en el tronco a tu lado: haz clic en él para conseguir la mascota.",
},
[-282047] = {
    "La Sewer Beast, de nivel 50, nada en los canales de Ventormenta, 71, 49 y 71, 68.",
    "Suelta la mascota Baby Crocolisk, pero no siempre: mátala otra vez cuando vuelva.",
},
[95805] = {
    "Haz primero las dos partes de A Humble Task: la madre del jefe está junto al pozo, 50, 81.",
    "Seer Graytongue vive en las colinas al sur de Campamento Narache, 42, 92. Cualquier raza de la Horda puede aceptar la misión.",
    "Lleva el incienso al santuario de las colinas del sureste en diez minutos. No entres en el agua.",
},
[91775] = {
    "El Nibbled-On Book cae de los kóbolds de Villanorte. Las tres misiones de kóbolds de allí dan también los 8 Stolen Books.",
    "Shinyfinder Narf, un élite de nivel 3, está en la mina Echo Ridge: segundo desvío a la derecha.",
    "De camino a Villadorada haz clic en 6 huellas de kóbold junto a los árboles al sur de Villanorte. Cuentan aunque el kit de rastreo no funcione.",
    "Fun with Elementals cae de Nimsy en la mina Fargodeep: entrada de arriba, al este desde la sala grande y por las escaleras. Tiene guardias, ve acompañado.",
},
[92515] = {
    "La misión se abre tras Welcome to Shen'dar Village: habla con Illaya Amberwind en el centro de la aldea y con Coriella Calmbreeze en la posada.",
    "Después mata Prideclaws en las tierras altas de Shen'dar, alrededor de la aldea, hasta tener 10 pieles.",
},
[97277] = {
    "Desde la puerta principal de Anvilmar toma el camino a la izquierda. A su derecha sube por la montaña un sendero nevado apenas visible, junto al primer árbol y unas cajas.",
    "El sendero es empinado, pero se puede subir. El campamento está justo tras la cresta.",
    "Mata al Snow Leopard Prowler, recoge el cuaderno del suelo y vuelve por el mismo camino.",
},
[791] = {
    "Furl Scornbrow está en la torre de vigilancia de Cerrotajo.",
    "Los Canvas Scraps caen a menudo de los humanos del Fuerte de Tiragarde, 58, 53. Los marineros sueltan más que los demás.",
},
[86784] = {
    "Las Dry Branches están junto a grupos de árboles y se confunden con el suelo. Mueve el ratón: sobre una rama el cursor se vuelve un engranaje.",
    "Hay tres junto a los árboles de 55, 55 y vuelven a salir en unos 30 segundos.",
    "El campamento de Eleanor Shackleton está en las colinas del oeste, 57, 55.",
},
[87288] = {
    "Solo los Nightsabers de nivel 5-6 sueltan las pieles, y hay pocos.",
    "Recorre en zigzag el bosque al este de Dolanaar y evita la aldea fúrbolg.",
    "Las pieles caen poco, así que lleva un rato. Cualquier raza de la Alianza puede hacer la misión.",
},
[99053] = {
    "Sentinel Lynessa espera en el nivel más bajo de Ban'ethil Barrow Den, en un hueco.",
    "Termina antes tus otras misiones del túmulo y despeja la salida: la acompañas hasta el camino.",
    "Quédate cerca. Se lanza contra cada enemigo cercano, y la misión falla si se aleja demasiado de ti.",
},
[151] = {
    "La avena está en los Sacks of Oats de los campos y granjas de Páramos de Poniente.",
    "Granja de Saldean: (56, 31), (52, 34), (52, 32). Granja de Molsen: (46, 38), (45, 35). Granja de calabazas de Furlbrow: (49, 21), (50, 18).",
    "Un saco tarda de 5 a 10 minutos en volver, así que ve a la granja siguiente.",
},
[97253] = {
    "Las piezas parecen basura en el suelo del campamento pirata de arriba, al sur de Trinquete.",
    "Busca junto a las tiendas, no dentro.",
},
[140] = {
    "El mapa del tesoro cae de los múrlocs de la costa de Páramos de Poniente.",
    "El baúl está en la playa, 26, 48, junto al ancla cerca del barco hundido.",
    "El barril roto está junto al camino en 40, 47, cerca de la chimenea en ruinas. La jarra está junto a un tronco en el molino, 40, 17.",
    "El cofre está en la mayor de las tres islas al oeste de la jarra, 26, 17.",
},
[1003] = {
    "Buzzbox 827 está en Auberdine, 37, 46, junto a la plataforma de hipogrifos. Los cangrejos de más al norte en la costa sueltan patas más a menudo.",
    "Buzzbox 411 está en la playa al norte de Auberdine, justo al este de los naufragios. Los trilladores nadan en aguas profundas.",
    "Buzzbox 323: sigue el camino al noreste y cruza el puente del río Cliffspring. La caja está a la izquierda del camino.",
    "Buzzbox 525 está en 41, 80, a la derecha del camino al sur hacia Vallefresno. Las cabelleras caen poco, harán falta muchos osos.",
},
[1486] = {
    "Nalpak está en la cueva sobre la entrada de las Cuevas de los Lamentos: sube encima de la entrada, date la vuelta en el borde y entra por el hueco izquierdo.",
    "Las pieles caen de las bestias Deviate de las cuevas. 20 pieles piden más de una vuelta.",
    "Lo más rápido es dentro de la mazmorra: mata los raptores camino del agua y los crocoliscos, reinicia la mazmorra y repite.",
},
[97926] = {
    "Fija tu piedra de hogar en Auberdine y toma allí el nuevo barco a Ventormenta.",
    "Entrega la carta a Baros Alexston en Ventormenta y recoge su respuesta.",
    "Vuelve a Auberdine con la piedra de hogar y entrega la respuesta.",
},
[531] = {
    "Las dos primeras misiones van con tiempo. Los buitres vuelan cerca de 78, 65, esa es fácil.",
    "Solo hay unos 7 Elder Mountain Boars en la zona y tienes 12 minutos para 5. Localízalos antes de aceptar la misión.",
    "Ol' Sooty camina entre su cueva al sur de Thelsamar (37, 62) y el lago. Puede tardar de 10 a 20 minutos en volver.",
},
[1474] = {
    "Dalin Forgewright está en la Muralla de Cringris, al sur del Bosque de Argénteos, hacia 46, 86.",
    "Comar Villard está en Los Humedales, en Dun Modr, justo tras el puente de Arathi, 50, 12.",
    "Invoca a la súcubo con tu abisario ya fuera.",
    "La cadena que empieza en Orgrimmar da la misma recompensa y es más fácil.",
},
[1513] = {
    "Zankaja está al oeste de la torre de dracoleones de Orgrimmar, no de la torre del zepelín como dice la misión: cruza el puente y gira a la derecha.",
    "Gazrog está delante de la posada de El Cruce, 51, 30. Ken'zigla está en Malaka'jin, en Sierra Espolón, 73, 95.",
    "Dogran está preso en Los Baldíos, 43, 47, al oeste del puente entre El Cruce y Campamento Taurajo. Jabaespines vigilan las chozas, a veces un élite.",
    "El círculo de invocación está en la tienda de Neeru, fuera de la Grieta de las Sombras a la izquierda. Llama antes a tu abisario.",
},
[1739] = {
    "Takar the Seer tiene una tienda junto a dos árboles cerca de Campamento Taurajo, en Los Baldíos. Ven desde Theramore y camina por lo alto de las colinas, lejos de los guardias de la Horda.",
    "El Heartswood es el árbol grande de las Ruinas de Ordil'Aran en Vallefresno, 31, 31, cerca del Puesto de Maestra. Haz clic derecho en el árbol.",
    "Llévalo a Gakin en Ventormenta, no de vuelta a Los Baldíos. Invoca a la súcubo con tu abisario fuera.",
},
[470] = {
    "La bolsa cae al azar de los mocos de Los Humedales, de cualquier tipo.",
    "A unos les sale tras 3 muertes, a otros tras 100. También cae de mocos lejos de Ironbeard's Tomb.",
},
[79192] = {
    "Horda: toma la nota de la hoguera apagada de Los Baldíos, 46, 73, y llévala a una hoguera igual en Páramos de Poniente, 37, 50. Alianza: al revés.",
    "La nota siguiente te manda a Sierra Espolón. Desde el camino, hacia 51, 51, entra por la abertura en las montañas y sigue el sendero hasta el campamento.",
    "El Pocket Litter que termina la misión está en ese campamento.",
},
[79976] = {
    "Haz primero Stepping Stones (mira esa recompensa). La nota siguiente del campamento, Scramble, te manda al norte, cuesta arriba, a un Mound of Dirt en Sierra Espolón, 39, 49.",
    "Wet Job: en Loch Modan ve al centro de la gran presa del norte y déjate caer a la cornisa con la Carved Figurine, 49, 12. Horda: los guardias de allí son fuertes.",
    "Eagle's Fist: la Messenger Bag está en la Muralla de Thoradin, Arathi 22, 24. Al norte de la puerta, del lado de Trabalomas, sube desde un carro roto: el barril, el tablón de la derecha, el carro, la escalera y las rocas.",
    "Entrégala y abre la Hastily Rolled-Up Satchel de al lado: dentro está el Cozy Sleeping Bag. Cada minuto de sueño en él da +1% de PX, hasta +3%.",
},
[93269] = {
    "Sebelia, en la cima del monte Hyjal, 71, 52, da Mending Communications. El camino está cerrado: Evie Whirlbrew en Vista Eterna, 61, 38, prepara la Potion of Winterspring Shrouding que te lleva arriba.",
    "Baja los paquetes a Innkeeper Vizzie en Vista Eterna, 61, 39.",
    "Unfrozen Deliveries: los 4 Missing Mail solo caen de Ice Thistle Yetis (no de los Rogue, Matriarchs ni Patriarchs), en las colinas al norte de Vista Eterna y junto a la cueva de yetis del sureste. Hazla junto con Are We There, Yeti?",
    "Top of the Post: sube el correo otra vez a Sebelia. Ella da la Hyjal Postal Satchel de 18 casillas.",
},
[96260] = {
    "A Gloomrise se llega desde Mulgore en 40, 17, desde Malaka'jin en Sierra Espolón (el sendero empieza en 73, 96) y desde Desolace en 77, 36.",
    "La Crystalline Silk cae de los Gloomrise Spinners. Necesitas 3 hebras.",
    "Eliges una bolsa o un saco de componentes. Quien fabrica toma el saco: una bolsa de seda normal es barata en la subasta.",
},
[58] = {
    "Los Skeletal Warriors y Skeletal Mages andan por el cementerio Tranquil Gardens, 80, 70.",
    "Los Skeletal Fiends y Skeletal Horrors están en el cementerio de Cerro del Cuervo, hacia 16, 44.",
    "Los Plague Spreaders están al este de Cerro del Cuervo. Si hay pocos, baja a la cripta: en sus salas grandes hay más.",
},
[1795] = {
    "El Moldy Tome está en un campamento múrloc de la costa al suroeste de Costasur, en Trabalomas: un libro azulado junto al agua.",
    "El Tattered Manuscript está en un cofre pequeño de Splithoof Hold, en Las Mil Agujas, 44, 37: dentro toma el primer camino a la derecha.",
    "Las Rods of Channeling caen de los orcos Faucedraco del campamento Angerfang, en Los Humedales. La entrada trasera está en 51, 45.",
    "Tu propio demonio puede luchar contigo contra el manáfago. Si fallas, abandona la misión y acéptala otra vez.",
},
[96109] = {
    "Neza Bloodsnout, en Rog'mar, da tres misiones seguidas.",
    "Cae una pluma de más o menos un buitre de cada tres, y a algunos jugadores mucho menos.",
    "Las víboras están junto a las charcas al sur de Rog'mar; los leones, en la colina del sur que se ve desde el campamento.",
},
[2439] = {
    "En Uldaman mata a Archaedas, el último jefe. La puerta de detrás lleva a la sala del tesoro.",
    "Haz clic en los Discs of Norgannon, habla con el vigía de piedra que aparece hasta que no diga nada más y haz clic otra vez en los discos.",
    "Lleva los discos pequeños a la Liga de Expedicionarios, en la Sala de los Expedicionarios de Forjaz.",
    "Dinita Stonemantle, que recoge el vale, está en el lado izquierdo del banco de Forjaz.",
},
[2440] = {
    "En Uldaman mata a Archaedas, el último jefe. La puerta de detrás lleva a la sala del tesoro.",
    "Haz clic en los Discs of Norgannon, habla con el vigía de piedra que aparece hasta que no diga nada más y haz clic otra vez en los discos.",
    "Lleva los discos pequeños a Sage Truthseeker en Cima del Trueno, 35, 47.",
    "Bena Winterhoof, que recoge el vale, está en 46, 33 en Cima del Trueno.",
},
[626] = {
    "El primer pergamino está en la bodega de un barco Velasangre frente a la costa de Tuercespina. Hay muchos piratas, ve en grupo.",
    "Pantano de las Penas: bajo el puente justo tras la bifurcación del camino, 22, 48. El pergamino se ve mal, pasa el ratón por el agua.",
    "Marjal Revolcafango: la cueva de raptores en 31, 66. El pergamino está sobre una roca al fondo.",
    "Tierras del Interior: el cofre está bajo la gran cascada de la costa, 81, 47. Sigue el río al este, salta desde las rocas de arriba y sal con la piedra de hogar.",
},
[3628] = {
    "Kirith es un élite de nivel 55 en una cueva al este de Las Tierras Devastadas. No saquees al entrar, así la cueva sigue vacía más tiempo. Luego habla con su espíritu.",
    "Azshara: Loramus está en una isla en 60, 66 y Lord Arkkoroc en su templo en 77, 42. Hetaera pasa nadando por 56, 44 cada 15 minutos más o menos. La azsharita está en los acantilados del sur, hacia 51, 71.",
    "Galvan, en Tuercespina, 50, 20, forja el arma. No hace falta empuñarla: di al Fallen Hero que la perdiste y te da una Fel Salve que sirve igual.",
    "En Las Tierras Devastadas, Allistarj está en 65, 33, Lady Sevine en 40, 30 y Grol en 43, 14. Lleva cinco jugadores para Razelikh.",
},
[84146] = {
    "Nami solo da la misión tras una cadena oculta. Empieza en la orilla sur de Tanaris, 59, 91: camina por la orilla desde 63, 64.",
    "Guarda la poción de nado de la primera misión. Nada al sur hacia el faro y luego a la isla: detrás hay una plataforma petrolífera con Sebastian Jurgens. Sigue nadando con la fatiga y ten lista una poción de sanación.",
    "Después vuela a Vista Eterna, donde está Nami. La bolsa está en lo alto de una colina, junto a una tienda, en Las Estepas Ardientes.",
},
}

T.fr = {
[97583] = {
    "Achetez de la Nutritious Slime Sludge à Boyle près du canal de Fossoyeuse, 56, 64.",
    "Trouvez un Excitable Slime qui patrouille dans les canaux. Placez-vous sur les marches du canal, pas dans l'eau, ciblez-le et tapez /dance.",
    "Il peut falloir de 5 à 100 danses. Quand il se tortille sur place en vous regardant, acceptez sa quête WRIGGLE. et donnez-lui la vase pour obtenir la mascotte.",
},
[95534] = {
    "Récupérez une Singed Note sur les Syndicate Wizards ou Argus Shadow Mages des montagnes d'Alterac. Elle lance la quête.",
    "Dans la forge de Strahnbrad, 59, 46, mettez le feu aux deux soufflets presque en même temps : Choc de flammes de mage, Easy Throw Dynamite, piège de feu de chasseur, Pluie de feu ou Flammes infernales, ou deux joueurs à la fois.",
    "L'élémentaire de feu atterrit entre les soufflets. Restez là où il atterrit, sinon il disparaît, et tuez-le. Rester près de la forge attire le Syndicat alentour.",
    "Rendez-la à Austrivage (Alliance, Kundric Zanden) ou à Moulin-de-Tarren (Horde, Shara Blazen) pour la Brilliant Cloak.",
},
[93176] = {
    "Amaryllis Webb, à l'ouest du marais des Chagrins, 25, 53, donne la quête et un Entomology Starter Kit dès le niveau 25.",
    "Attrapez-en un de chaque avec le kit : une Arbor Tarantula au camp de bûcherons au nord de Strangleronce, 44, 20, un Hay Weevil dans les fermes d'Arathi, 31, 28, et un Flesh Picker au cimetière des Kodos en Désolace, 52, 58.",
    "Rapportez les trois spécimens à Amaryllis pour la mascotte Weevil K. Neevil.",
},
[97029] = {
    "Obtenez l'anneau Ancient Heirloom : les Skyborne font Coming of Age d'Ailee Farheart, les autres le ramassent au dernier étage du bâtiment de Zephras Isle, 41.7, 23.4.",
    "Prenez une Night Watchman's Torch sur le corps du garde au bois de la Pénombre (An Unfortunate End), allumez-la et utilisez-la aux Ruins of Ban'aethal, Zephras Isle 58, 24, pendant que le dragon y dort. L'Ancient Hilt apparaît.",
    "Apportez la poignée à Ealaane Nimbuswalker à Valanaar, 66, 74, puis trouvez l'Ancient Skyborne Blade : elle est à un seul endroit à la fois, 49, 73, 50, 44, 66, 43 ou 60, 82.",
    "Rapportez la lame à Ealaane pour Eluvi'ana. La suite du secret Dawn Waker n'est pas encore résolue : gardez l'épée et l'anneau.",
},
[-221315] = {
    "Dans les profondeurs de Rochenoire, prenez le pont juste à l'est de l'Arène de la Loi qui part vers le nord au-dessus de la lave.",
    "Sur son côté gauche, près d'un petit brasero, sautez de la rambarde sur la plateforme contre le mur. Allez au bout et courez le long du mur, épaule gauche contre lui, jusqu'à tomber sur la corniche en dessous.",
    "Le jouet Traveler's Symbols est sur la corniche. La porte là-bas mène seulement en bas, chez Lord Incendius.",
},
[-268109] = {
    "Allez au rocher en haut de la cascade de Zephras Isle, 51, 72, où chantent des grenouilles.",
    "Attendez qu'au moins deux grenouilles soient sur le rocher, ciblez-en une et tapez /sing.",
    "Les grenouilles disparaissent et un Musical Gustjumper apparaît sur le tronc à côté de vous : cliquez dessus pour obtenir la mascotte.",
},
[-282047] = {
    "La Sewer Beast, niveau 50, nage dans les canaux de Hurlevent, 71, 49 et 71, 68.",
    "Elle laisse la mascotte Baby Crocolisk, mais pas à chaque fois : tuez-la encore quand elle revient.",
},
[95805] = {
    "Faites d'abord les deux parties de A Humble Task : la mère du chef se tient près du puits, 50, 81.",
    "Seer Graytongue vit dans les collines au sud du Camp Narache, 42, 92. Toute race de la Horde peut prendre la quête.",
    "Portez l'encens au sanctuaire des collines du sud-est en dix minutes. N'entrez pas dans l'eau.",
},
[91775] = {
    "Le Nibbled-On Book tombe sur les kobolds de Comté-du-Nord. Les trois quêtes de kobolds du lieu donnent aussi les 8 Stolen Books.",
    "Shinyfinder Narf, un élite de niveau 3, est dans la mine Echo Ridge : deuxième tournant à droite.",
    "En allant à Comté-de-l'Or, cliquez sur 6 traces de kobold près des arbres au sud de Comté-du-Nord. Elles comptent même si le kit de pistage ne marche pas.",
    "Fun with Elementals tombe sur Nimsy dans la mine Fargodeep : entrée du haut, à l'est depuis la grande salle puis l'escalier. Il a des gardes, venez à deux.",
},
[92515] = {
    "La quête s'ouvre après Welcome to Shen'dar Village : parlez à Illaya Amberwind au centre du village et à Coriella Calmbreeze à l'auberge.",
    "Tuez ensuite des Prideclaws dans les hautes terres de Shen'dar, autour du village, pour 10 peaux.",
},
[97277] = {
    "Devant la porte principale d'Anvilmar, prenez la route à gauche. Sur sa droite, une piste enneigée à peine visible monte dans la montagne, après le premier arbre et des caisses.",
    "Le chemin est raide, mais on peut le gravir. Le camp est juste derrière la crête.",
    "Tuez le Snow Leopard Prowler, ramassez le journal au sol et revenez par le même chemin.",
},
[791] = {
    "Furl Scornbrow se tient dans la tour de guet de Tranchecolline.",
    "Les Canvas Scraps tombent souvent sur les humains du donjon de Tiragarde, 58, 53. Les marins en donnent plus que les autres.",
},
[86784] = {
    "Les Dry Branches sont près des groupes d'arbres et se confondent avec le sol. Bougez la souris : sur une branche, le curseur devient un engrenage.",
    "Il y en a trois près des arbres en 55, 55 ; elles reviennent après environ 30 secondes.",
    "Le camp d'Eleanor Shackleton est dans les collines à l'ouest, 57, 55.",
},
[87288] = {
    "Seuls les Nightsabers de niveau 5-6 donnent les peaux, et ils sont rares.",
    "Parcourez en zigzag les bois à l'est de Dolanaar et évitez le village furbolg.",
    "Les peaux tombent rarement, cela prend du temps. Toute race de l'Alliance peut faire la quête.",
},
[99053] = {
    "Sentinel Lynessa attend au niveau le plus bas de Ban'ethil Barrow Den, dans une alcôve.",
    "Finissez d'abord vos autres quêtes du refuge et dégagez la sortie : vous l'escortez jusqu'à la route.",
    "Restez près d'elle. Elle fonce sur chaque ennemi proche, et la quête échoue si elle s'éloigne trop de vous.",
},
[151] = {
    "L'avoine se trouve dans les Sacks of Oats des champs et fermes de la Marche de l'Ouest.",
    "Ferme des Saldean : (56, 31), (52, 34), (52, 32). Ferme des Molsen : (46, 38), (45, 35). Ferme aux potirons des Furlbrow : (49, 21), (50, 18).",
    "Un sac ne revient qu'après 5 à 10 minutes, passez donc à la ferme suivante.",
},
[97253] = {
    "Les pièces ressemblent à des déchets au sol dans le camp pirate du haut, au sud de Cabestan.",
    "Cherchez à côté des tentes, pas dedans.",
},
[140] = {
    "La carte au trésor tombe sur les murlocs de la côte de la Marche de l'Ouest.",
    "La cantine est sur la plage en 26, 48, près de l'ancre à côté de l'épave.",
    "Le tonneau cassé est au bord de la route en 40, 47, près de la cheminée en ruine. La cruche est à côté d'un tronc au moulin, 40, 17.",
    "Le coffre est sur la plus grande des trois îles à l'ouest de la cruche, 26, 17.",
},
[1003] = {
    "Buzzbox 827 est à Auberdine en 37, 46, près de la plateforme des hippogriffes. Les crabes plus au nord sur la côte donnent plus souvent des pattes.",
    "Buzzbox 411 est sur la plage au nord d'Auberdine, juste à l'est des épaves. Les batteurs nagent en eau profonde.",
    "Buzzbox 323 : suivez la route au nord-est et traversez le pont de la rivière Cliffspring. La boîte est à gauche de la route.",
    "Buzzbox 525 est en 41, 80, à droite de la route du sud vers Orneval. Les scalps tombent rarement, il faudra beaucoup d'ours.",
},
[1486] = {
    "Nalpak est dans la grotte au-dessus de l'entrée des Cavernes des Lamentations : montez sur l'entrée, retournez-vous au bord et prenez le trou de gauche.",
    "Les peaux tombent sur les bêtes Deviate des cavernes. Il faut plus d'un passage pour 20 peaux.",
    "Le plus rapide est dans le donjon : tuez les raptors sur le chemin de l'eau et les crocilisques, réinitialisez le donjon et recommencez.",
},
[97926] = {
    "Liez votre pierre de foyer à Auberdine, puis prenez-y le nouveau bateau pour Hurlevent.",
    "Donnez la lettre à Baros Alexston à Hurlevent et prenez sa réponse.",
    "Revenez à Auberdine avec la pierre de foyer et rendez la réponse.",
},
[531] = {
    "Les deux premières quêtes sont chronométrées. Les busards volent vers 78, 65, celle-là est facile.",
    "Il n'y a qu'environ 7 Elder Mountain Boars dans la zone, et vous avez 12 minutes pour 5. Repérez-les avant de prendre la quête.",
    "Ol' Sooty marche entre sa grotte au sud de Thelsamar (37, 62) et le lac. Il peut mettre 10 à 20 minutes à revenir.",
},
[1474] = {
    "Dalin Forgewright se tient au mur de Grisetête, au sud de la forêt des Pins-Argentés, vers 46, 86.",
    "Comar Villard est dans les Paluns à Dun Modr, juste après le pont d'Arathi, 50, 12.",
    "Invoquez la succube avec votre marcheur du Vide déjà sorti.",
    "La suite qui commence à Orgrimmar donne la même récompense et est plus facile.",
},
[1513] = {
    "Zankaja est à l'ouest de la tour des coursiers du vent d'Orgrimmar, pas de la tour des zeppelins comme le dit la quête : traversez le pont et tournez à droite.",
    "Gazrog est devant l'auberge de la Croisée, 51, 30. Ken'zigla est à Malaka'jin dans les Serres-Rocheuses, 73, 95.",
    "Dogran est retenu dans les Tarides en 43, 47, à l'ouest du pont entre la Croisée et le Camp Taurajo. Des huran gardent les huttes, parfois un élite.",
    "Le cercle d'invocation est dans la tente de Neeru, dehors à gauche de la Faille de l'Ombre. Appelez d'abord votre marcheur du Vide.",
},
[1739] = {
    "Takar the Seer a une tente près de deux arbres, non loin du Camp Taurajo dans les Tarides. Venez de Theramore et marchez sur les crêtes, loin des gardes de la Horde.",
    "Le Heartswood est le grand arbre des ruines d'Ordil'Aran à Orneval, 31, 31, près de l'avant-poste de Maestra. Clic droit sur l'arbre.",
    "Apportez-le à Gakin à Hurlevent, pas dans les Tarides. Invoquez la succube avec votre marcheur du Vide sorti.",
},
[470] = {
    "Le sac tombe au hasard sur les limons des Paluns, de n'importe quelle sorte.",
    "Certains l'ont après 3 morts, d'autres après 100. Les limons loin d'Ironbeard's Tomb le donnent aussi.",
},
[79192] = {
    "Horde : prenez la note au feu éteint des Tarides, 46, 73, et portez-la au même genre de feu dans la Marche de l'Ouest, 37, 50. Alliance : dans l'autre sens.",
    "La note suivante vous envoie dans les Serres-Rocheuses. Depuis la route, vers 51, 51, passez par l'ouverture dans les montagnes et suivez le sentier jusqu'au camp.",
    "Le Pocket Litter qui termine la quête se trouve dans ce camp.",
},
[79976] = {
    "Faites d'abord Stepping Stones (voir cette récompense). La note suivante du camp, Scramble, vous envoie au nord, en haut de la colline, vers un Mound of Dirt dans les Serres-Rocheuses, 39, 49.",
    "Wet Job : dans le Loch Modan, allez au milieu du grand barrage au nord et laissez-vous tomber sur la corniche de la Carved Figurine, 49, 12. Horde : les gardes y sont forts.",
    "Eagle's Fist : le Messenger Bag est sur le mur de Thoradin, Arathi 22, 24. Au nord de la porte, côté Hautebrande, montez depuis une charrette cassée : le tonneau, la planche à droite, la charrette, l'échelle, puis les rochers.",
    "Rendez-la et ouvrez la Hastily Rolled-Up Satchel à côté : le Cozy Sleeping Bag est dedans. Chaque minute de sommeil dedans donne +1% d'XP, jusqu'à +3%.",
},
[93269] = {
    "Sebelia, au sommet du mont Hyjal, 71, 52, donne Mending Communications. Le chemin est fermé : Evie Whirlbrew à Long-Guet, 61, 38, prépare la Potion of Winterspring Shrouding qui vous y mène.",
    "Descendez les colis à Innkeeper Vizzie à Long-Guet, 61, 39.",
    "Unfrozen Deliveries : les 4 Missing Mail ne tombent que des Ice Thistle Yetis (pas des Rogue, Matriarchs ni Patriarchs), dans les collines au nord de Long-Guet et près de la grotte des yétis au sud-est. Faites-la avec Are We There, Yeti?",
    "Top of the Post : remontez le courrier à Sebelia. Elle donne la Hyjal Postal Satchel de 18 emplacements.",
},
[96260] = {
    "On rejoint Gloomrise depuis Mulgore en 40, 17, depuis Malaka'jin dans les Serres-Rocheuses (le sentier part de 73, 96) et depuis Désolace en 77, 36.",
    "La Crystalline Silk tombe sur les Gloomrise Spinners. Il en faut 3 fils.",
    "Vous choisissez un sac ou un sac de composants. Les artisans prennent le second : un sac en soie ordinaire coûte peu à l'hôtel des ventes.",
},
[58] = {
    "Les Skeletal Warriors et Skeletal Mages rôdent au cimetière Tranquil Gardens, 80, 70.",
    "Les Skeletal Fiends et Skeletal Horrors sont au cimetière de Colline-aux-Corbeaux, vers 16, 44.",
    "Les Plague Spreaders sont à l'est de Colline-aux-Corbeaux. S'il y en a trop peu, descendez dans la crypte : ses grandes salles en ont plus.",
},
[1795] = {
    "Le Moldy Tome est dans un camp murloc sur la côte au sud-ouest d'Austrivage, à Hautebrande : un livre bleuté au bord de l'eau.",
    "Le Tattered Manuscript est dans un petit coffre de Splithoof Hold aux Mille pointes, 44, 37 : à l'intérieur, premier passage à droite.",
    "Les Rods of Channeling tombent sur les orcs Gueule-de-dragon du campement Angerfang dans les Paluns. L'entrée de derrière est en 51, 45.",
    "Votre propre démon peut combattre le chasseur corrompu avec vous. En cas d'échec, abandonnez la quête et reprenez-la.",
},
[96109] = {
    "Neza Bloodsnout à Rog'mar donne trois quêtes à la suite.",
    "Une plume tombe sur environ un busard sur trois, bien moins pour certains joueurs.",
    "Les vipères sont près des mares au sud de Rog'mar, les lions sur la colline au sud que l'on voit du camp.",
},
[2439] = {
    "À Uldaman, tuez Archaedas, le dernier boss. La porte derrière lui mène à la salle du trésor.",
    "Cliquez sur les Discs of Norgannon, parlez au gardien de pierre qui apparaît jusqu'à ce qu'il n'ait plus rien à dire, puis recliquez sur les disques.",
    "Apportez les petits disques à la Ligue des explorateurs, dans le Hall des explorateurs de Forgefer.",
    "Dinita Stonemantle, qui prend le bon, se tient du côté gauche de la banque de Forgefer.",
},
[2440] = {
    "À Uldaman, tuez Archaedas, le dernier boss. La porte derrière lui mène à la salle du trésor.",
    "Cliquez sur les Discs of Norgannon, parlez au gardien de pierre qui apparaît jusqu'à ce qu'il n'ait plus rien à dire, puis recliquez sur les disques.",
    "Apportez les petits disques à Sage Truthseeker aux Pitons-du-Tonnerre, 35, 47.",
    "Bena Winterhoof, qui prend le bon, est en 46, 33 aux Pitons-du-Tonnerre.",
},
[626] = {
    "Le premier parchemin est dans la cale d'un navire de la Voile sanglante au large de Strangleronce. Les pirates sont nombreux, venez en groupe.",
    "Marais des Chagrins : sous le pont juste après la fourche de la route, 22, 48. Le parchemin se voit mal, passez la souris sur l'eau.",
    "Marécage d'Âprefange : la grotte des raptors en 31, 66. Le parchemin est sur un rocher au fond.",
    "Les Hinterlands : le coffre est sous la grande cascade de la côte, 81, 47. Suivez la rivière vers l'est, sautez des rochers du haut et repartez avec la pierre de foyer.",
},
[3628] = {
    "Kirith est un élite de niveau 55 dans une grotte à l'est des Terres Foudroyées. Ne fouillez pas les corps en entrant, la grotte reste vide plus longtemps. Parlez ensuite à son esprit.",
    "Azshara : Loramus est sur une île en 60, 66, Lord Arkkoroc dans son temple en 77, 42. Hetaera passe à la nage vers 56, 44 toutes les 15 minutes environ. L'azsharite est sur les falaises du sud, vers 51, 71.",
    "Galvan, à Strangleronce, 50, 20, forge l'arme. Inutile de la manier : dites au Fallen Hero que vous l'avez perdue et il donne une Fel Salve qui marche aussi bien.",
    "Dans les Terres Foudroyées, Allistarj est en 65, 33, Lady Sevine en 40, 30 et Grol en 43, 14. Venez à cinq pour Razelikh.",
},
[84146] = {
    "Nami ne donne la quête qu'après une suite cachée. Elle commence sur la rive sud de Tanaris en 59, 91 : longez la rive depuis 63, 64.",
    "Gardez la potion de nage de la première quête. Nagez au sud vers le phare, puis vers l'île : derrière se trouve une plateforme pétrolière avec Sebastian Jurgens. Continuez à nager malgré la fatigue, une potion de soins à portée de main.",
    "Volez ensuite à Long-Guet, où se trouve Nami. Le sac est en haut d'une colline, près d'une tente, dans les Steppes Ardentes.",
},
}

T.pl = {
[97583] = {
    "Kup Nutritious Slime Sludge u Boyle'a przy kanale w Undercity, 56, 64.",
    "Znajdź Excitable Slime, który krąży po kanałach. Stań na schodach kanału, nie w wodzie, wybierz go i wpisz /dance.",
    "Może to zająć od 5 do 100 tańców. Gdy wije się w miejscu, zwrócony do ciebie, przyjmij jego zadanie WRIGGLE. i daj mu szlam, a dostaniesz zwierzaka.",
},
[95534] = {
    "Zdobądź Singed Note z Syndicate Wizards lub Argus Shadow Mages w Alterac Mountains. Ta notatka zaczyna zadanie.",
    "W kuźni Strahnbrad, 59, 46, podpal oba miechy niemal naraz: Flamestrike maga, Easy Throw Dynamite, ognista pułapka łowcy, Rain of Fire albo Hellfire, albo dwóch graczy jednocześnie.",
    "Ognisty żywiołak ląduje między miechami. Stój tam, gdzie wylądował, bo inaczej zniknie, i zabij go. Stanie przy kuźni ściąga pobliski Syndykat.",
    "Oddaj zadanie w Southshore (Przymierze, Kundric Zanden) lub w Tarren Mill (Horda, Shara Blazen), a dostaniesz Brilliant Cloak.",
},
[93176] = {
    "Amaryllis Webb na zachodzie Swamp of Sorrows, 25, 53, daje zadanie i Entomology Starter Kit od poziomu 25.",
    "Złap zestawem po jednym: Arbor Tarantula przy obozie drwali na północy Stranglethorn, 44, 20, Hay Weevil na farmach Arathi, 31, 28, i Flesh Picker na Cmentarzysku Kodo w Desolace, 52, 58.",
    "Zanieś trzy okazy do Amaryllis, a dostaniesz zwierzaka Weevil K. Neevil.",
},
[97029] = {
    "Zdobądź pierścień Ancient Heirloom: Skyborne robią Coming of Age od Ailee Farheart, reszta podnosi go na najwyższym piętrze budynku na Zephras Isle, 41.7, 23.4.",
    "Weź Night Watchman's Torch z ciała strażnika w Duskwood (An Unfortunate End), zapal ją i użyj w Ruins of Ban'aethal, Zephras Isle 58, 24, gdy smok tam śpi. Pojawi się Ancient Hilt.",
    "Zanieś rękojeść do Ealaane Nimbuswalker w Valanaar, 66, 74, a potem znajdź Ancient Skyborne Blade: leży naraz tylko w jednym z miejsc 49, 73, 50, 44, 66, 43 lub 60, 82.",
    "Oddaj ostrze Ealaane, a dostaniesz Eluvi'ana. Reszta sekretu Dawn Waker nie jest jeszcze rozwiązana: zachowaj miecz i pierścień.",
},
[-221315] = {
    "W Blackrock Depths wejdź na most tuż na wschód od Ring of Law, który biegnie na północ nad lawą.",
    "Po jego lewej stronie, przy małym koksowniku, skocz z barierki na platformę przy ścianie. Dojdź do jej końca i biegnij wzdłuż ściany, lewym ramieniem przy niej, aż spadniesz na półkę niżej.",
    "Zabawka Traveler's Symbols leży na tej półce. Drzwi tam prowadzą tylko w dół, do Lorda Incendiusa.",
},
[-268109] = {
    "Idź na skałę na szczycie wodospadu na Zephras Isle, 51, 72, gdzie śpiewają żaby.",
    "Poczekaj, aż na skale siedzą co najmniej dwie żaby, wybierz jedną i wpisz /sing.",
    "Żaby znikną, a na kłodzie obok pojawi się Musical Gustjumper: kliknij go, by dostać zwierzaka.",
},
[-282047] = {
    "Sewer Beast, poziom 50, pływa w kanałach Stormwind, 71, 49 i 71, 68.",
    "Wypada z niej zwierzak Baby Crocolisk, ale nie za każdym razem: zabij ją znowu, gdy wróci.",
},
[95805] = {
    "Najpierw zrób obie części A Humble Task: matka wodza stoi przy studni, 50, 81.",
    "Seer Graytongue mieszka na wzgórzach na południe od Camp Narache, 42, 92. Zadanie może wziąć każda rasa Hordy.",
    "Zanieś kadzidło do kapliczki na południowo-wschodnich wzgórzach w dziesięć minut. Nie wchodź do wody.",
},
[91775] = {
    "Nibbled-On Book wypada z koboldów w Northshire. Trzy tamtejsze zadania na koboldy dają też wszystkie 8 Stolen Books.",
    "Shinyfinder Narf, elita 3. poziomu, siedzi w kopalni Echo Ridge: drugi zakręt w prawo.",
    "W drodze do Goldshire kliknij 6 śladów koboldów przy drzewach na południe od Northshire. Liczą się, nawet gdy zestaw tropiciela nie działa.",
    "Fun with Elementals wypada z Nimsy'ego w kopalni Fargodeep: górne wejście, z dużej sali na wschód i schodami w górę. Ma straż, weź kogoś ze sobą.",
},
[92515] = {
    "Zadanie otwiera się po Welcome to Shen'dar Village: porozmawiaj z Illayą Amberwind na środku wioski i z Coriellą Calmbreeze w gospodzie.",
    "Potem zabijaj Prideclawy na wyżynach Shen'dar wokół wioski, aż zbierzesz 10 skór.",
},
[97277] = {
    "Sprzed głównej bramy Anvilmar idź drogą w lewo. Po jej prawej stronie w górę prowadzi ledwo widoczna śnieżna ścieżka, obok pierwszego drzewa i skrzyń.",
    "Ścieżka jest stroma, ale da się wejść. Obóz leży tuż za grzbietem.",
    "Zabij Snow Leopard Prowlera, podnieś dziennik z ziemi i wróć tą samą drogą.",
},
[791] = {
    "Furl Scornbrow stoi na wieży strażniczej w Razor Hill.",
    "Canvas Scraps często wypadają z ludzi w Tiragarde Keep, 58, 53. Z marynarzy częściej niż z pozostałych.",
},
[86784] = {
    "Dry Branches leżą przy grupach drzew i zlewają się z ziemią. Ruszaj myszą: nad gałęzią kursor zmienia się w zębatkę.",
    "Trzy leżą przy drzewach na 55, 55 i wracają po około 30 sekundach.",
    "Obóz Eleanor Shackleton jest na wzgórzach na zachodzie, 57, 55.",
},
[87288] = {
    "Skóry wypadają tylko z Nightsaberów 5-6 poziomu, a jest ich mało.",
    "Chodź zygzakiem po lesie na wschód od Dolanaar i omiń wioskę furbolgów.",
    "Skóry wypadają rzadko, więc to potrwa. Zadanie może zrobić każda rasa Przymierza.",
},
[99053] = {
    "Sentinel Lynessa czeka na najniższym poziomie Ban'ethil Barrow Den, we wnęce.",
    "Najpierw skończ inne zadania w kurhanie i oczyść drogę do wyjścia: odprowadzasz ją aż do drogi.",
    "Trzymaj się blisko. Rzuca się na każdego wroga w pobliżu, a zadanie przepada, gdy za bardzo się od ciebie oddali.",
},
[151] = {
    "Owies jest w workach Sack of Oats na polach i farmach Westfall.",
    "Farma Saldeanów: (56, 31), (52, 34), (52, 32). Farma Molsenów: (46, 38), (45, 35). Dyniowa farma Furlbrowów: (49, 21), (50, 18).",
    "Worek wraca dopiero po 5-10 minutach, więc idź na następną farmę.",
},
[97253] = {
    "Części wyglądają jak śmieci na ziemi w górnym obozie piratów na południe od Ratchet.",
    "Szukaj obok namiotów, nie w środku.",
},
[140] = {
    "Mapa skarbu wypada z murloków na wybrzeżu Westfall.",
    "Kuferek stoi na plaży na 26, 48, przy kotwicy obok zatopionego statku.",
    "Rozbita beczka stoi przy drodze na 40, 47, obok zrujnowanego komina. Dzban leży przy kłodzie koło wiatraka, 40, 17.",
    "Skrzynia jest na największej z trzech wysp na zachód od dzbana, 26, 17.",
},
[1003] = {
    "Buzzbox 827 stoi w Auberdine na 37, 46, obok platformy hipogryfów. Kraby dalej na północ na wybrzeżu częściej dają nogi.",
    "Buzzbox 411 stoi na plaży na północ od Auberdine, tuż na wschód od wraków. Threshery pływają na głębokiej wodzie.",
    "Buzzbox 323: idź drogą na północny wschód i przejdź most na rzece Cliffspring. Skrzynka stoi po lewej stronie drogi.",
    "Buzzbox 525 jest na 41, 80, po prawej stronie drogi na południe do Ashenvale. Skalpy wypadają rzadko, trzeba wielu niedźwiedzi.",
},
[1486] = {
    "Nalpak jest w jaskini nad wejściem do Wailing Caverns: wejdź na wejście, odwróć się na krawędzi i idź w lewy otwór.",
    "Skóry wypadają z bestii Deviate w jaskiniach. 20 skór to więcej niż jedno podejście.",
    "Najszybciej w lochu: zabij raptory po drodze do wody i krokoliski, zresetuj loch i powtórz.",
},
[97926] = {
    "Ustaw kamień powrotu w Auberdine i wsiądź tam na nowy statek do Stormwind.",
    "Oddaj list Barosowi Alexstonowi w Stormwind i weź jego odpowiedź.",
    "Wróć kamieniem powrotu do Auberdine i oddaj odpowiedź.",
},
[531] = {
    "Dwa pierwsze zadania są na czas. Myszołowy latają koło 78, 65, to łatwe.",
    "W strefie jest tylko około 7 Elder Mountain Boarów, a masz 12 minut na 5. Znajdź je, zanim weźmiesz zadanie.",
    "Ol' Sooty chodzi między swoją jaskinią na południe od Thelsamar (37, 62) a jeziorem. Na jego powrót czeka się 10-20 minut.",
},
[1474] = {
    "Dalin Forgewright stoi przy Greymane Wall na południu Silverpine Forest, około 46, 86.",
    "Comar Villard jest w Wetlands przy Dun Modr, tuż za mostem z Arathi, 50, 12.",
    "Przyzwij sukuba, mając już przy sobie voidwalkera.",
    "Łańcuch zaczynający się w Orgrimmarze daje tę samą nagrodę i jest łatwiejszy.",
},
[1513] = {
    "Zankaja stoi na zachód od wieży wiwern w Orgrimmarze, a nie wieży sterowców, jak mówi zadanie: przejdź most i skręć w prawo.",
    "Gazrog stoi przed gospodą w Crossroads, 51, 30. Ken'zigla jest w Malaka'jin w Stonetalon, 73, 95.",
    "Dogran jest więziony w Barrens na 43, 47, na zachód od mostu między Crossroads a Camp Taurajo. Chat pilnują quilboary, czasem elita.",
    "Krąg przyzwania jest w namiocie Neeru, na zewnątrz Cleft of Shadow po lewej. Najpierw przywołaj voidwalkera.",
},
[1739] = {
    "Takar the Seer ma namiot przy dwóch drzewach koło Camp Taurajo w Barrens. Idź od Theramore szczytami wzgórz, z dala od strażników Hordy.",
    "Heartswood to wielkie drzewo w Ruins of Ordil'Aran w Ashenvale, 31, 31, koło Maestra's Post. Kliknij drzewo prawym przyciskiem.",
    "Zanieś je do Gakina w Stormwind, nie z powrotem do Barrens. Przyzwij sukuba z voidwalkerem u boku.",
},
[470] = {
    "Torba wypada losowo ze szlamów w Wetlands, z każdego rodzaju.",
    "Jedni mają ją po 3 zabiciach, inni po 100. Wypada też ze szlamów z dala od Ironbeard's Tomb.",
},
[79192] = {
    "Horda: weź notatkę z wypalonego ogniska w Barrens, 46, 73, i zanieś ją do takiego samego ogniska w Westfall, 37, 50. Przymierze: odwrotnie.",
    "Następna notatka wysyła cię do Stonetalon. Z drogi koło 51, 51 wejdź w przejście w górach i idź ścieżką w górę do obozu.",
    "Pocket Litter, który kończy zadanie, leży w tym obozie.",
},
[79976] = {
    "Najpierw zrób Stepping Stones (zobacz tę nagrodę). Następna notatka z obozu, Scramble, wysyła cię na północ, w górę wzgórza, do Mound of Dirt w Stonetalon, 39, 49.",
    "Wet Job: w Loch Modan idź na środek dużej tamy na północy i zeskocz na półkę z Carved Figurine, 49, 12. Horda: tamtejsi strażnicy są silni.",
    "Eagle's Fist: Messenger Bag leży na Thoradin's Wall, Arathi 22, 24. Na północ od bramy, po stronie Hillsbrad, wskocz z rozbitego wozu: beczka, deska po prawej, wóz, drabina, potem skały.",
    "Oddaj zadanie i otwórz Hastily Rolled-Up Satchel obok: w środku jest Cozy Sleeping Bag. Każda minuta snu w nim daje +1% PD, do +3%.",
},
[93269] = {
    "Sebelia na szczycie góry Hyjal, 71, 52, daje Mending Communications. Droga na górę jest zamknięta: Evie Whirlbrew w Everlook, 61, 38, warzy Potion of Winterspring Shrouding, która cię tam zabierze.",
    "Zanieś paczki do Innkeeper Vizzie w Everlook, 61, 39.",
    "Unfrozen Deliveries: 4 Missing Mail wypadają tylko z Ice Thistle Yeti (nie z Rogue, Matriarch ani Patriarch), na wzgórzach na północ od Everlook i przy jaskini yeti na południowym wschodzie. Zrób to razem z Are We There, Yeti?",
    "Top of the Post: zanieś pocztę z powrotem na górę do Sebelii. Daje ona Hyjal Postal Satchel na 18 miejsc.",
},
[96260] = {
    "Do Gloomrise dojdziesz z Mulgore na 40, 17, od Malaka'jin w Stonetalon (ścieżka zaczyna się na 73, 96) i z Desolace na 77, 36.",
    "Crystalline Silk wypada z Gloomrise Spinnerów. Potrzebujesz 3 nici.",
    "Wybierasz torbę albo worek na odczynniki. Rzemieślnicy biorą worek: zwykła jedwabna torba jest tania na aukcji.",
},
[58] = {
    "Skeletal Warriors i Skeletal Mages chodzą po cmentarzu Tranquil Gardens, 80, 70.",
    "Skeletal Fiends i Skeletal Horrors są na cmentarzu Raven Hill, koło 16, 44.",
    "Plague Spreaders są na wschodzie Raven Hill. Gdy jest ich za mało, zejdź do krypty: w jej dużych salach chodzi ich więcej.",
},
[1795] = {
    "Moldy Tome leży w obozie murloków na wybrzeżu na południowy zachód od Southshore w Hillsbrad: niebieskawa księga przy wodzie.",
    "Tattered Manuscript jest w małej skrzynce w Splithoof Hold w Thousand Needles, 44, 37: w środku pierwsza droga w prawo.",
    "Rods of Channeling wypadają z orków Dragonmaw w obozie Angerfang w Wetlands. Tylne wejście jest na 51, 45.",
    "Twój własny demon może walczyć z felhunterem razem z tobą. Gdy się nie uda, porzuć zadanie i weź je ponownie.",
},
[96109] = {
    "Neza Bloodsnout w Rog'mar daje trzy zadania jedno po drugim.",
    "Pióro wypada mniej więcej z co trzeciego myszołowa, u niektórych graczy dużo rzadziej.",
    "Żmije są przy stawach na południe od Rog'mar, lwy na wzgórzu na południu, które widać z obozu.",
},
[2439] = {
    "W Uldaman zabij Archaedasa, ostatniego bossa. Drzwi za nim prowadzą do skarbca.",
    "Kliknij Discs of Norgannon, rozmawiaj z kamiennym strażnikiem, który się pojawi, aż nie będzie miał nic do powiedzenia, i kliknij dyski jeszcze raz.",
    "Zanieś małe dyski do Explorers' League w Hall of Explorers w Ironforge.",
    "Dinita Stonemantle, która bierze kupon, stoi po lewej stronie banku w Ironforge.",
},
[2440] = {
    "W Uldaman zabij Archaedasa, ostatniego bossa. Drzwi za nim prowadzą do skarbca.",
    "Kliknij Discs of Norgannon, rozmawiaj z kamiennym strażnikiem, który się pojawi, aż nie będzie miał nic do powiedzenia, i kliknij dyski jeszcze raz.",
    "Zanieś małe dyski do Sage'a Truthseekera w Thunder Bluff, 35, 47.",
    "Bena Winterhoof, która bierze kupon, stoi na 46, 33 w Thunder Bluff.",
},
[626] = {
    "Pierwszy zwój leży w dolnej ładowni statku Bloodsail u wybrzeża Stranglethorn. Piratów jest dużo, weź grupę.",
    "Swamp of Sorrows: pod mostem tuż za rozwidleniem drogi, 22, 48. Zwój słabo widać, przesuwaj mysz nad wodą.",
    "Dustwallow Marsh: jaskinia raptorów na 31, 66. Zwój leży na skale w głębi.",
    "Hinterlands: skrzynia jest pod wielkim wodospadem na wybrzeżu, 81, 47. Idź rzeką na wschód, zeskocz ze skał na górze i wróć kamieniem powrotu.",
},
[3628] = {
    "Kirith to elita 55. poziomu w jaskini na wschodzie Blasted Lands. Po drodze nie zbieraj łupów, wtedy jaskinia dłużej jest pusta. Potem porozmawiaj z jego duchem.",
    "Azshara: Loramus jest na wyspie na 60, 66, Lord Arkkoroc w swojej świątyni na 77, 42. Hetaera przepływa koło 56, 44 mniej więcej co 15 minut. Azsharyt jest na południowych klifach koło 51, 71.",
    "Galvan w Stranglethorn, 50, 20, wykuwa broń. Nie musisz jej nosić: powiedz Fallen Hero, że ją zgubiłeś, a da Fel Salve, która działa tak samo.",
    "W Blasted Lands Allistarj jest na 65, 33, Lady Sevine na 40, 30, a Grol na 43, 14. Na Razelikha weź pięciu graczy.",
},
[84146] = {
    "Nami daje zadanie dopiero po ukrytym łańcuchu. Zaczyna się na południowym brzegu Tanaris na 59, 91: idź brzegiem od 63, 64.",
    "Zachowaj miksturę pływania z pierwszego zadania. Płyń na południe do latarni, potem do wyspy: za nią jest platforma wiertnicza z Sebastianem Jurgensem. Płyń dalej mimo zmęczenia, z miksturą leczenia pod ręką.",
    "Potem leć do Everlook, tam jest Nami. Torba leży na wzgórzu obok namiotu w Burning Steppes.",
},
}

T.pt = {
[97583] = {
    "Compre Nutritious Slime Sludge com Boyle junto ao canal da Cidade Baixa, 56, 64.",
    "Encontre um Excitable Slime que patrulha os canais. Fique nos degraus do canal, não na água, selecione-o e digite /dance.",
    "Pode levar de 5 a 100 danças. Quando ele se contorcer no lugar olhando para você, aceite a missão dele, WRIGGLE., e entregue a gosma para ganhar o mascote.",
},
[95534] = {
    "Saqueie uma Singed Note dos Syndicate Wizards ou Argus Shadow Mages nas Montanhas de Alterac. Ela inicia a missão.",
    "Na forja de Strahnbrad, 59, 46, ponha fogo nos dois foles quase juntos: Golpe Flamejante de mago, Easy Throw Dynamite, armadilha de fogo de caçador, Chuva de Fogo ou Fogo do Inferno, ou dois jogadores ao mesmo tempo.",
    "O elemental de fogo cai entre os foles. Fique onde ele cai, senão some, e mate-o. Ficar junto à forja atrai o Sindicato por perto.",
    "Entregue em Southshore (Aliança, Kundric Zanden) ou em Tarren Mill (Horda, Shara Blazen) para ganhar a Brilliant Cloak.",
},
[93176] = {
    "Amaryllis Webb, no oeste do Pântano das Mágoas, 25, 53, dá a missão e um Entomology Starter Kit a partir do nível 25.",
    "Capture um de cada com o kit: uma Arbor Tarantula no acampamento madeireiro do norte de Selva do Espinhaço, 44, 20, um Hay Weevil nas fazendas de Arathi, 31, 28, e um Flesh Picker no Cemitério dos Kodos em Desolação, 52, 58.",
    "Leve os três espécimes de volta a Amaryllis para ganhar o mascote Weevil K. Neevil.",
},
[97029] = {
    "Pegue o anel Ancient Heirloom: os Skyborne fazem Coming of Age de Ailee Farheart; os outros o pegam no último andar do prédio em Zephras Isle, 41.7, 23.4.",
    "Pegue uma Night Watchman's Torch do corpo do guarda em Floresta do Crepúsculo (An Unfortunate End), acenda e use nas Ruins of Ban'aethal, Zephras Isle 58, 24, enquanto o dragão de lá dorme. O Ancient Hilt aparece.",
    "Leve o punho a Ealaane Nimbuswalker em Valanaar, 66, 74, e depois encontre a Ancient Skyborne Blade: ela fica em um lugar por vez, 49, 73, 50, 44, 66, 43 ou 60, 82.",
    "Devolva a lâmina a Ealaane para ganhar Eluvi'ana. O resto do segredo Dawn Waker ainda não foi resolvido: guarde a espada e o anel.",
},
[-221315] = {
    "Nas Profundezas Rocha Negra, pegue a ponte logo a leste do Anel da Lei que segue para o norte sobre a lava.",
    "No lado esquerdo dela, perto de um pequeno braseiro, pule do parapeito para a plataforma junto à parede. Vá até o fim e corra rente à parede, ombro esquerdo nela, até cair na saliência abaixo.",
    "O brinquedo Traveler's Symbols fica na saliência. A porta ali só leva para baixo, até Lord Incendius.",
},
[-268109] = {
    "Vá até a pedra no alto da cachoeira de Zephras Isle, 51, 72, onde os sapos cantam.",
    "Espere até haver pelo menos dois sapos na pedra, selecione um e digite /sing.",
    "Os sapos somem e um Musical Gustjumper aparece no tronco ao seu lado: clique nele para ganhar o mascote.",
},
[-282047] = {
    "A Sewer Beast, nível 50, nada nos canais de Ventobravo, 71, 49 e 71, 68.",
    "Ela dá o mascote Baby Crocolisk, mas não sempre: mate-a de novo quando ela voltar.",
},
[95805] = {
    "Faça antes as duas partes de A Humble Task: a mãe do chefe fica junto ao poço, 50, 81.",
    "Seer Graytongue vive nas colinas ao sul da Aldeia Narache, 42, 92. Qualquer raça da Horda pode aceitar a missão.",
    "Leve o incenso ao santuário nas colinas do sudeste em dez minutos. Não entre na água.",
},
[91775] = {
    "O Nibbled-On Book cai dos kobolds de Vila Norte. As três missões de kobolds de lá também dão os 8 Stolen Books.",
    "Shinyfinder Narf, um elite de nível 3, está na mina Echo Ridge: segunda curva à direita.",
    "A caminho de Vila d'Ouro, clique em 6 pegadas de kobold perto das árvores ao sul de Vila Norte. Elas contam mesmo quando o kit de rastreio não funciona.",
    "Fun with Elementals cai de Nimsy na mina Fargodeep: entrada de cima, a leste da sala grande e escada acima. Ele tem guardas, leve alguém.",
},
[92515] = {
    "A missão abre depois de Welcome to Shen'dar Village: fale com Illaya Amberwind no centro da vila e com Coriella Calmbreeze na estalagem.",
    "Depois mate Prideclaws nas terras altas de Shen'dar, em volta da vila, até ter 10 peles.",
},
[97277] = {
    "Da porta principal de Anvilmar, siga a estrada para a esquerda. À direita dela, uma trilha de neve quase invisível sobe a montanha, passando pela primeira árvore e por caixas.",
    "A trilha é íngreme, mas dá para subir. O acampamento fica logo atrás da crista.",
    "Mate o Snow Leopard Prowler, pegue o diário do chão e volte pelo mesmo caminho.",
},
[791] = {
    "Furl Scornbrow fica na torre de vigia de Monte Navalha.",
    "Os Canvas Scraps caem com frequência dos humanos da Bastilha Tiragarde, 58, 53. Os marinheiros dão mais que os outros.",
},
[86784] = {
    "Os Dry Branches ficam perto de grupos de árvores e se confundem com o chão. Mexa o mouse: sobre um galho o cursor vira uma engrenagem.",
    "Há três perto das árvores em 55, 55, e eles voltam em cerca de 30 segundos.",
    "O acampamento de Eleanor Shackleton fica nas colinas a oeste, 57, 55.",
},
[87288] = {
    "Só os Nightsabers de nível 5-6 dão as peles, e há poucos.",
    "Ande em zigue-zague pela mata a leste de Dolanaar e evite a aldeia dos furbolgs.",
    "As peles caem pouco, então demora. Qualquer raça da Aliança pode fazer a missão.",
},
[99053] = {
    "Sentinel Lynessa espera no nível mais baixo de Ban'ethil Barrow Den, em um nicho.",
    "Termine antes suas outras missões no local e limpe o caminho de saída: você a acompanha até a estrada.",
    "Fique perto dela. Ela corre para cada inimigo próximo, e a missão falha se ela se afastar demais de você.",
},
[151] = {
    "A aveia está nos Sacks of Oats dos campos e fazendas de Cerro Oeste.",
    "Fazenda dos Saldean: (56, 31), (52, 34), (52, 32). Fazenda dos Molsen: (46, 38), (45, 35). Fazenda de abóboras dos Furlbrow: (49, 21), (50, 18).",
    "Um saco só volta depois de 5 a 10 minutos, então vá para a fazenda seguinte.",
},
[97253] = {
    "As peças parecem lixo no chão do acampamento pirata de cima, ao sul de Vila Catraca.",
    "Procure ao lado das tendas, não dentro delas.",
},
[140] = {
    "O mapa do tesouro cai dos murlocs da costa de Cerro Oeste.",
    "O baú fica na praia em 26, 48, junto à âncora perto do navio afundado.",
    "O barril quebrado fica à beira da estrada em 40, 47, perto da chaminé em ruínas. O jarro fica ao lado de um tronco no moinho, 40, 17.",
    "A arca fica na maior das três ilhas a oeste do jarro, 26, 17.",
},
[1003] = {
    "Buzzbox 827 fica em Auberdine, 37, 46, ao lado da plataforma dos hipogrifos. Os caranguejos mais ao norte na costa dão patas com mais frequência.",
    "Buzzbox 411 fica na praia ao norte de Auberdine, logo a leste dos naufrágios. Os debulhadores nadam em águas fundas.",
    "Buzzbox 323: siga a estrada para nordeste e cruze a ponte do rio Cliffspring. A caixa fica à esquerda da estrada.",
    "Buzzbox 525 fica em 41, 80, à direita da estrada para o sul rumo ao Vale Gris. Os escalpos caem pouco, conte com muitos ursos.",
},
[1486] = {
    "Nalpak está na caverna acima da entrada das Cavernas Ululantes: suba em cima da entrada, vire-se na beirada e entre pelo buraco da esquerda.",
    "As peles caem das feras Deviate das cavernas. 20 peles pedem mais de uma rodada.",
    "O mais rápido é dentro da masmorra: mate os raptores no caminho até a água e os crocoliscos, reinicie a masmorra e repita.",
},
[97926] = {
    "Defina sua pedra de regresso em Auberdine e pegue lá o novo barco para Ventobravo.",
    "Entregue a carta a Baros Alexston em Ventobravo e pegue a resposta.",
    "Volte a Auberdine com a pedra de regresso e entregue a resposta.",
},
[531] = {
    "As duas primeiras missões têm tempo. Os abutres voam perto de 78, 65, essa é fácil.",
    "Há só uns 7 Elder Mountain Boars na zona, e você tem 12 minutos para 5. Encontre-os antes de aceitar a missão.",
    "Ol' Sooty anda entre sua caverna ao sul de Thelsamar (37, 62) e o lago. Ele pode levar de 10 a 20 minutos para voltar.",
},
[1474] = {
    "Dalin Forgewright fica na Muralha Greymane, no sul da Floresta de Pinhaprata, perto de 46, 86.",
    "Comar Villard está no Pantanal, em Dun Modr, logo depois da ponte de Arathi, 50, 12.",
    "Invoque a súcubo com seu emissário do caos já ao seu lado.",
    "A cadeia que começa em Orgrimmar dá a mesma recompensa e é mais fácil.",
},
[1513] = {
    "Zankaja fica a oeste da torre dos mantícoras de Orgrimmar, não da torre do zepelim como diz a missão: cruze a ponte e vire à direita.",
    "Gazrog fica em frente à estalagem da Encruzilhada, 51, 30. Ken'zigla está em Malaka'jin, na Serra das Torres de Pedra, 73, 95.",
    "Dogran está preso nos Sertões em 43, 47, a oeste da ponte entre a Encruzilhada e a Aldeia Taurajo. Javatuscos guardam as cabanas, às vezes um elite.",
    "O círculo de invocação fica na tenda de Neeru, fora da Fenda das Sombras, à esquerda. Chame antes seu emissário do caos.",
},
[1739] = {
    "Takar the Seer tem uma tenda ao lado de duas árvores perto da Aldeia Taurajo, nos Sertões. Venha de Theramore e ande pelo alto das colinas, longe dos guardas da Horda.",
    "O Heartswood é a árvore grande das Ruínas de Ordil'Aran no Vale Gris, 31, 31, perto do Posto de Maestra. Clique na árvore com o botão direito.",
    "Leve-o a Gakin em Ventobravo, não de volta aos Sertões. Invoque a súcubo com seu emissário do caos ao lado.",
},
[470] = {
    "A bolsa cai ao acaso das gosmas do Pantanal, de qualquer tipo.",
    "Uns conseguem em 3 abates, outros em 100. Gosmas longe de Ironbeard's Tomb também a dão.",
},
[79192] = {
    "Horda: pegue o bilhete na fogueira apagada dos Sertões, 46, 73, e leve-o a uma fogueira igual em Cerro Oeste, 37, 50. Aliança: o contrário.",
    "O bilhete seguinte manda você à Serra das Torres de Pedra. Da estrada, perto de 51, 51, entre pela abertura nas montanhas e siga a trilha até o acampamento.",
    "O Pocket Litter que termina a missão fica nesse acampamento.",
},
[79976] = {
    "Faça primeiro Stepping Stones (veja essa recompensa). O bilhete seguinte do acampamento, Scramble, manda você ao norte, morro acima, até um Mound of Dirt na Serra das Torres de Pedra, 39, 49.",
    "Wet Job: em Loch Modan vá ao meio da grande represa do norte e desça até a saliência com a Carved Figurine, 49, 12. Horda: os guardas de lá são fortes.",
    "Eagle's Fist: a Messenger Bag fica na Muralha de Thoradin, Arathi 22, 24. Ao norte do portão, do lado de Eira dos Montes, suba por uma carroça quebrada: o barril, a tábua à direita, a carroça, a escada e as rochas.",
    "Entregue e abra a Hastily Rolled-Up Satchel ao lado: dentro está o Cozy Sleeping Bag. Cada minuto de sono nele dá +1% de XP, até +3%.",
},
[93269] = {
    "Sebelia, no topo do monte Hyjal, 71, 52, dá Mending Communications. O caminho está fechado: Evie Whirlbrew em Visteterna, 61, 38, faz a Potion of Winterspring Shrouding que leva você lá.",
    "Leve os pacotes até Innkeeper Vizzie em Visteterna, 61, 39.",
    "Unfrozen Deliveries: os 4 Missing Mail caem só de Ice Thistle Yetis (não dos Rogue, Matriarchs nem Patriarchs), nas colinas ao norte de Visteterna e perto da caverna dos yetis a sudeste. Faça junto com Are We There, Yeti?",
    "Top of the Post: leve a correspondência de volta a Sebelia. Ela dá a Hyjal Postal Satchel de 18 espaços.",
},
[96260] = {
    "Chega-se a Gloomrise por Mulgore em 40, 17, por Malaka'jin na Serra das Torres de Pedra (a trilha começa em 73, 96) e por Desolação em 77, 36.",
    "A Crystalline Silk cai dos Gloomrise Spinners. Você precisa de 3 fios.",
    "Você escolhe uma bolsa ou um saco de reagentes. Quem fabrica pega o saco: uma bolsa de seda comum é barata no leilão.",
},
[58] = {
    "Os Skeletal Warriors e Skeletal Mages andam pelo cemitério Tranquil Gardens, 80, 70.",
    "Os Skeletal Fiends e Skeletal Horrors ficam no cemitério do Morro dos Corvos, perto de 16, 44.",
    "Os Plague Spreaders ficam no leste do Morro dos Corvos. Se houver poucos, desça à cripta: nas salas grandes há mais.",
},
[1795] = {
    "O Moldy Tome fica em um acampamento murloc na costa a sudoeste de Costa Sul, em Eira dos Montes: um livro azulado junto à água.",
    "O Tattered Manuscript está em um baú pequeno em Splithoof Hold, em Mil Agulhas, 44, 37: lá dentro, primeiro caminho à direita.",
    "As Rods of Channeling caem dos orcs Presa do Dragão do acampamento Angerfang, no Pantanal. A entrada dos fundos fica em 51, 45.",
    "Seu próprio demônio pode lutar com você contra o caçador vil. Se falhar, abandone a missão e aceite de novo.",
},
[96109] = {
    "Neza Bloodsnout, em Rog'mar, dá três missões seguidas.",
    "Cai uma pena de mais ou menos um abutre em cada três, e para alguns jogadores bem menos.",
    "As víboras ficam nos lagos ao sul de Rog'mar; os leões, na colina ao sul que se vê do acampamento.",
},
[2439] = {
    "Em Uldaman, mate Archaedas, o último chefe. A porta atrás dele leva à sala do tesouro.",
    "Clique nos Discs of Norgannon, fale com o vigia de pedra que aparece até ele não ter mais nada a dizer e clique nos discos de novo.",
    "Leve os discos pequenos à Liga dos Exploradores, no Salão dos Exploradores de Altaforja.",
    "Dinita Stonemantle, que recebe o vale, fica no lado esquerdo do banco de Altaforja.",
},
[2440] = {
    "Em Uldaman, mate Archaedas, o último chefe. A porta atrás dele leva à sala do tesouro.",
    "Clique nos Discs of Norgannon, fale com o vigia de pedra que aparece até ele não ter mais nada a dizer e clique nos discos de novo.",
    "Leve os discos pequenos a Sage Truthseeker no Penhasco do Trovão, 35, 47.",
    "Bena Winterhoof, que recebe o vale, fica em 46, 33 no Penhasco do Trovão.",
},
[626] = {
    "O primeiro pergaminho fica no porão de um navio dos Vela Sangrenta, na costa da Selva do Espinhaço. Há muitos piratas, vá em grupo.",
    "Pântano das Mágoas: debaixo da ponte logo depois da bifurcação da estrada, 22, 48. O pergaminho é difícil de ver, passe o mouse sobre a água.",
    "Pântano Vadeoso: a caverna dos raptores em 31, 66. O pergaminho fica sobre uma pedra no fundo.",
    "Terras Agrestes: a arca fica sob a grande cachoeira da costa, 81, 47. Siga o rio para leste, pule das pedras do alto e saia com a pedra de regresso.",
},
[3628] = {
    "Kirith é um elite de nível 55 em uma caverna no leste da Barreira do Inferno. Não saqueie na entrada, assim a caverna fica vazia por mais tempo. Depois fale com o espírito dele.",
    "Azshara: Loramus fica em uma ilha em 60, 66 e Lord Arkkoroc em seu templo em 77, 42. Hetaera passa nadando por 56, 44 a cada 15 minutos mais ou menos. A azsharita fica nos penhascos do sul, perto de 51, 71.",
    "Galvan, na Selva do Espinhaço, 50, 20, forja a arma. Não é preciso empunhá-la: diga ao Fallen Hero que a perdeu e ele dá uma Fel Salve que funciona igual.",
    "Na Barreira do Inferno, Allistarj fica em 65, 33, Lady Sevine em 40, 30 e Grol em 43, 14. Leve cinco jogadores para Razelikh.",
},
[84146] = {
    "Nami só dá a missão depois de uma cadeia oculta. Ela começa na margem sul de Tanaris, 59, 91: ande pela margem a partir de 63, 64.",
    "Guarde a poção de natação da primeira missão. Nade para o sul até o farol e depois até a ilha: atrás dela há uma plataforma de petróleo com Sebastian Jurgens. Continue nadando mesmo com fadiga, com uma poção de cura à mão.",
    "Depois voe para Visteterna, onde está Nami. A bolsa fica no alto de uma colina, ao lado de uma tenda, nas Estepes Ardentes.",
},
}

T.ru = {
[97583] = {
    "Купите Nutritious Slime Sludge у Boyle у канала в Подгороде, 56, 64.",
    "Найдите Excitable Slime, который ползает по каналам. Встаньте на ступени канала, не в воду, возьмите его в цель и наберите /dance.",
    "Танцевать может понадобиться от 5 до 100 раз. Когда он извивается на месте, глядя на вас, возьмите его задание WRIGGLE. и отдайте ему слизь: за неё дают питомца.",
},
[95534] = {
    "Добудьте Singed Note с Syndicate Wizards или Argus Shadow Mages в Альтеракских горах. Записка начинает задание.",
    "В кузнице Стрэнбрэда, 59, 46, подожгите оба меха почти одновременно: «Огненный столб» мага, Easy Throw Dynamite, огненная ловушка охотника, «Огненный ливень» или «Адское пламя», или два игрока сразу.",
    "Огненный элементаль приземлится между мехами. Стойте там, где он приземлился, иначе он исчезнет, и убейте его. У кузницы на вас сбегается Синдикат вокруг.",
    "Сдайте задание в Южнобережье (Альянс, Kundric Zanden) или в Мельнице Таррен (Орда, Shara Blazen): награда Brilliant Cloak.",
},
[93176] = {
    "Amaryllis Webb на западе Болота Печали, 25, 53, с 25 уровня даёт задание и Entomology Starter Kit.",
    "Поймайте набором по одному: Arbor Tarantula у лагеря лесорубов на севере Тернистой долины, 44, 20, Hay Weevil на фермах Арати, 31, 28, и Flesh Picker на Кладбище кодо в Пустошах, 52, 58.",
    "Принесите три образца Amaryllis: за них дают питомца Weevil K. Neevil.",
},
[97029] = {
    "Добудьте кольцо Ancient Heirloom: Skyborne получают его за Coming of Age у Ailee Farheart, остальные подбирают на верхнем этаже здания на Zephras Isle, 41.7, 23.4.",
    "Возьмите Night Watchman's Torch с тела стражника в Сумеречном лесу (An Unfortunate End), зажгите и примените в Ruins of Ban'aethal, Zephras Isle 58, 24, пока дракон там спит. Появится Ancient Hilt.",
    "Отнесите рукоять Ealaane Nimbuswalker в Valanaar, 66, 74, и найдите Ancient Skyborne Blade: он лежит в одном месте за раз, 49, 73, 50, 44, 66, 43 или 60, 82.",
    "Принесите клинок Ealaane: награда Eluvi'ana. Остальная часть секрета Dawn Waker ещё не разгадана: не выбрасывайте меч и кольцо.",
},
[-221315] = {
    "В Глубинах Черной горы идите на мост сразу к востоку от Круга Закона, который ведёт на север над лавой.",
    "На его левой стороне, у маленькой жаровни, прыгните с перил на площадку у стены. Дойдите до её конца и бегите вдоль стены, левым плечом к ней, пока не упадёте на уступ ниже.",
    "Игрушка Traveler's Symbols лежит на уступе. Дверь там ведёт только вниз, к Lord Incendius.",
},
[-268109] = {
    "Идите к камню на вершине водопада на Zephras Isle, 51, 72, где поют лягушки.",
    "Дождитесь, пока на камне сидят хотя бы две лягушки, возьмите одну в цель и наберите /sing.",
    "Лягушки исчезнут, а на бревне рядом появится Musical Gustjumper: нажмите на него, чтобы получить питомца.",
},
[-282047] = {
    "Sewer Beast 50 уровня плавает в каналах Штормграда, 71, 49 и 71, 68.",
    "С него падает питомец Baby Crocolisk, но не каждый раз: убейте его снова, когда он вернётся.",
},
[95805] = {
    "Сначала сделайте обе части A Humble Task: мать вождя стоит у колодца, 50, 81.",
    "Seer Graytongue живёт в холмах к югу от Лагеря Нараче, 42, 92. Задание берёт любая раса Орды.",
    "Донесите благовония до святилища в юго-восточных холмах за десять минут. В воду не заходите.",
},
[91775] = {
    "Nibbled-On Book падает с кобольдов в Североземье. Три задания на кобольдов там же дадут и все 8 Stolen Books.",
    "Shinyfinder Narf, элитный 3-го уровня, сидит в руднике Echo Ridge: второй поворот направо.",
    "По дороге в Златоземье нажмите на 6 следов кобольдов у деревьев к югу от Североземья. Они засчитываются, даже если набор следопыта не срабатывает.",
    "Fun with Elementals падает с Nimsy в руднике Fargodeep: верхний вход, из большого зала на восток и вверх по лестнице. С ним охрана, возьмите напарника.",
},
[92515] = {
    "Задание открывается после Welcome to Shen'dar Village: поговорите с Illaya Amberwind в центре деревни и с Coriella Calmbreeze в таверне.",
    "Затем убивайте Prideclaw в нагорье Шен'дар вокруг деревни, нужно 10 шкур.",
},
[97277] = {
    "От главных ворот Anvilmar идите по дороге налево. Справа от неё в гору уходит едва заметная снежная тропа, мимо первого дерева и ящиков.",
    "Подъём крутой, но пройти можно. Лагерь сразу за гребнем.",
    "Убейте Snow Leopard Prowler, поднимите журнал с земли и вернитесь тем же путём.",
},
[791] = {
    "Furl Scornbrow стоит на сторожевой башне Колючего Холма.",
    "Canvas Scraps часто падают с людей в крепости Тирагард, 58, 53. С матросов чаще, чем с остальных.",
},
[86784] = {
    "Dry Branches лежат у групп деревьев и сливаются с землёй. Водите мышью: над веткой курсор становится шестерёнкой.",
    "Три ветки лежат у деревьев на 55, 55 и появляются снова примерно через 30 секунд.",
    "Лагерь Eleanor Shackleton в холмах на западе, 57, 55.",
},
[87288] = {
    "Шкуры падают только с Nightsaber 5-6 уровня, а их мало.",
    "Ходите зигзагами по лесу к востоку от Доланаара, деревню фурболгов обходите.",
    "Шкуры падают редко, придётся потерпеть. Задание доступно любой расе Альянса.",
},
[99053] = {
    "Sentinel Lynessa ждёт на нижнем ярусе Ban'ethil Barrow Den, в нише.",
    "Сначала закончите другие задания в пещере и расчистите выход: её нужно довести до самой дороги.",
    "Держитесь рядом. Она бросается на каждого врага поблизости, а если уйдёт далеко от вас, задание провалится.",
},
[151] = {
    "Овёс лежит в мешках Sack of Oats на полях и фермах Западного Края.",
    "Ферма Сальдена: (56, 31), (52, 34), (52, 32). Ферма Молсена: (46, 38), (45, 35). Тыквенная ферма Фурлброу: (49, 21), (50, 18).",
    "Мешок появляется снова только через 5-10 минут, так что идите к следующей ферме.",
},
[97253] = {
    "Детали похожи на мусор на земле в верхнем лагере пиратов к югу от Кабестана.",
    "Ищите рядом с палатками, а не внутри.",
},
[140] = {
    "Карта сокровищ падает с мурлоков на побережье Западного Края.",
    "Сундучок стоит на пляже, 26, 48, у якоря рядом с затонувшим кораблём.",
    "Сломанная бочка стоит у дороги, 40, 47, возле разрушенной трубы. Кувшин лежит у бревна рядом с мельницей, 40, 17.",
    "Сундук на самом большом из трёх островов к западу от кувшина, 26, 17.",
},
[1003] = {
    "Buzzbox 827 стоит в Аубердине, 37, 46, рядом с площадкой гиппогрифов. С крабов севернее по берегу ноги падают чаще.",
    "Buzzbox 411 на пляже к северу от Аубердина, чуть восточнее затонувших кораблей. Молотильщики плавают на глубине.",
    "Buzzbox 323: идите по дороге на северо-восток и перейдите мост через реку Cliffspring. Ящик слева от дороги.",
    "Buzzbox 525 на 41, 80, справа от дороги на юг в Ясеневый лес. Скальпы падают редко, медведей понадобится много.",
},
[1486] = {
    "Nalpak сидит в пещере над входом в Пещеры Стенаний: заберитесь на вход, у края развернитесь и идите в левый проход.",
    "Шкуры падают с тварей Deviate в пещерах. 20 шкур за один заход не набрать.",
    "Быстрее всего в подземелье: убейте ящеров по пути к воде и кроколисков, сбросьте подземелье и повторите.",
},
[97926] = {
    "Привяжите камень возвращения в Аубердине и сядьте там на новый корабль до Штормграда.",
    "Отдайте письмо Baros Alexston в Штормграде и возьмите ответ.",
    "Вернитесь камнем в Аубердин и сдайте ответ.",
},
[531] = {
    "Первые два задания на время. Канюки летают около 78, 65, это легко.",
    "Elder Mountain Boar в зоне всего около 7, а на 5 штук даётся 12 минут. Найдите их до того, как возьмёте задание.",
    "Ol' Sooty ходит между своей пещерой к югу от Телсамара (37, 62) и озером. Ждать его приходится 10-20 минут.",
},
[1474] = {
    "Dalin Forgewright стоит у Стены Седогрива на юге Серебряного бора, около 46, 86.",
    "Comar Villard в Болотине у Дун Модра, сразу за мостом из Арати, 50, 12.",
    "Призывайте суккуба, когда демон Бездны уже вызван.",
    "Цепочка из Оргриммара даёт ту же награду и проще.",
},
[1513] = {
    "Zankaja стоит к западу от башни ветрокрылов в Оргриммаре, а не башни дирижаблей, как сказано в задании: перейдите мост и поверните направо.",
    "Gazrog стоит перед таверной в Перекрёстке, 51, 30. Ken'zigla в Малака'джине в Когтистых горах, 73, 95.",
    "Dogran в плену в Степях, 43, 47, к западу от моста между Перекрёстком и Лагерем Таурахо. Хижины охраняют свинобразы, иногда элитный.",
    "Круг призыва в палатке Neeru, снаружи Расселины Теней слева. Сначала вызовите демона Бездны.",
},
[1739] = {
    "Палатка Takar the Seer стоит у двух деревьев рядом с Лагерем Таурахо в Степях. Идите от Терамора по верху холмов, подальше от стражи Орды.",
    "Heartswood это большое дерево в Руинах Ордил'Аран в Ясеневом лесу, 31, 31, рядом с Заставой Мейстры. Нажмите на дерево правой кнопкой.",
    "Несите сердцевину к Gakin в Штормград, а не обратно в Степи. Призывайте суккуба с вызванным демоном Бездны.",
},
[470] = {
    "Сумка случайно падает со слизней Болотины, с любых.",
    "Кому-то хватает 3 убийств, кому-то нужно 100. Падает и со слизней вдали от Ironbeard's Tomb.",
},
[79192] = {
    "Орда: возьмите записку у потухшего костра в Степях, 46, 73, и отнесите к такому же костру в Западном Крае, 37, 50. Альянс: наоборот.",
    "Следующая записка ведёт в Когтистые горы. С дороги примерно на 51, 51 сверните в проход в горы и поднимайтесь по тропе до лагеря.",
    "Pocket Litter, которым завершается задание, лежит в этом лагере.",
},
[79976] = {
    "Сначала пройдите Stepping Stones (см. эту награду). Следующая записка в лагере, Scramble, ведёт на север вверх по холму к Mound of Dirt в Когтистых горах, 39, 49.",
    "Wet Job: в Лок Модане идите на середину большой плотины на севере и спрыгните на уступ с Carved Figurine, 49, 12. Орде: стража там сильная.",
    "Eagle's Fist: Messenger Bag на Стене Торадина, Арати 22, 24. К северу от ворот, со стороны Хилсбрада, лезьте со сломанной телеги: бочка, доска справа, телега, лестница, потом камни.",
    "Сдайте задание и откройте Hastily Rolled-Up Satchel рядом: в нём Cozy Sleeping Bag. Каждая минута сна в нём даёт +1% опыта, до +3%.",
},
[93269] = {
    "Sebelia на вершине горы Хиджал, 71, 52, даёт Mending Communications. Наверх так просто не пройти: Evie Whirlbrew в Круговзоре, 61, 38, варит Potion of Winterspring Shrouding, которое туда переносит.",
    "Отнесите посылки вниз, Innkeeper Vizzie в Круговзоре, 61, 39.",
    "Unfrozen Deliveries: 4 Missing Mail падают только с Ice Thistle Yeti (не с Rogue, Matriarch и Patriarch), на холмах к северу от Круговзора и у пещеры йети на юго-востоке. Удобно делать вместе с Are We There, Yeti?",
    "Top of the Post: поднимите почту обратно к Sebelia. Она даёт почтовую сумку Хиджала (Hyjal Postal Satchel) на 18 ячеек.",
},
[96260] = {
    "В Gloomrise можно попасть из Мулгора (40, 17), от Малака'джина в Когтистых горах (тропа начинается на 73, 96) и из Пустошей (77, 36).",
    "Crystalline Silk падает с Gloomrise Spinner. Нужно 3 нити.",
    "На выбор сумка или сумка для реагентов. Кто крафтит, берёт вторую: обычная шёлковая сумка на аукционе стоит дёшево.",
},
[58] = {
    "Skeletal Warrior и Skeletal Mage ходят на кладбище Tranquil Gardens, 80, 70.",
    "Skeletal Fiend и Skeletal Horror на кладбище Вороньего Холма, около 16, 44.",
    "Plague Spreader на востоке Вороньего Холма. Если их мало, спуститесь в склеп: в его больших залах их больше.",
},
[1795] = {
    "Moldy Tome лежит в лагере мурлоков на берегу к юго-западу от Южнобережья в Хилсбраде, синеватая книга у воды.",
    "Tattered Manuscript в сундучке в Splithoof Hold в Тысяче Игл, 44, 37: внутри первый поворот направо.",
    "Rod of Channeling падают с орков Драконьей Пасти в лагере Angerfang в Болотине. Задний вход на 51, 45.",
    "Ваш демон может драться с охотником Скверны вместе с вами. Если не вышло, откажитесь от задания и возьмите заново.",
},
[96109] = {
    "Neza Bloodsnout в Rog'mar даёт три задания подряд.",
    "Перо падает примерно с каждого третьего канюка, у некоторых игроков гораздо реже.",
    "Змеи у прудов к югу от Rog'mar, львы на холме южнее, его видно из лагеря.",
},
[2439] = {
    "В Ульдамане убейте Archaedas, последнего босса. За ним откроется дверь в сокровищницу.",
    "Нажмите на Discs of Norgannon, поговорите с появившимся каменным стражем до конца, затем нажмите на диски ещё раз.",
    "Отнесите малые диски в Лигу исследователей в Зале исследователей в Стальгорне.",
    "Dinita Stonemantle, которая принимает ваучер, стоит в банке Стальгорна слева.",
},
[2440] = {
    "В Ульдамане убейте Archaedas, последнего босса. За ним откроется дверь в сокровищницу.",
    "Нажмите на Discs of Norgannon, поговорите с появившимся каменным стражем до конца, затем нажмите на диски ещё раз.",
    "Отнесите малые диски к Sage Truthseeker в Громовой Утёс, 35, 47.",
    "Bena Winterhoof, которая принимает ваучер, стоит на 46, 33 в Громовом Утёсе.",
},
[626] = {
    "Первый свиток лежит в нижнем трюме корабля Кровавого Паруса у берега Тернистой долины. Пиратов много, идите группой.",
    "Болото Печали: под мостом сразу после развилки дороги, 22, 48. Свиток плохо видно, водите мышью по воде.",
    "Пылевые топи: пещера ящеров на 31, 66. Свиток лежит на камне в глубине.",
    "Внутренние земли: сундук под большим водопадом на побережье, 81, 47. Идите по реке на восток, спрыгните со скал наверху и уходите камнем возвращения.",
},
[3628] = {
    "Kirith, элитный 55-го уровня, сидит в пещере на востоке Выжженных земель. По пути не обыскивайте трупы, тогда пещера дольше пуста. Затем поговорите с его духом.",
    "Азшара: Loramus на острове, 60, 66, Lord Arkkoroc в своём храме, 77, 42. Hetaera проплывает у 56, 44 примерно раз в 15 минут. Азшарит на южных скалах около 51, 71.",
    "Galvan в Тернистой долине, 50, 20, куёт оружие. Носить его не обязательно: скажите Fallen Hero, что потеряли, и он даст Fel Salve, она работает так же.",
    "В Выжженных землях Allistarj на 65, 33, Lady Sevine на 40, 30, Grol на 43, 14. На Razelikh зовите пятерых.",
},
[84146] = {
    "Nami даёт задание только после скрытой цепочки. Она начинается на южном берегу Танариса, 59, 91: идите вдоль берега от 63, 64.",
    "Сохраните зелье плавания из первого задания. Плывите на юг к маяку, затем к острову: за ним нефтяная вышка с Sebastian Jurgens. Плывите сквозь усталость, держите зелье здоровья наготове.",
    "Потом летите в Круговзор, там Nami. Сумка лежит на холме у палатки в Пылающих степях.",
},
}

T.zh = {
[97583] = {
    "在幽暗城运河边向 Boyle 购买 Nutritious Slime Sludge，56, 64。",
    "找一只在运河里游荡的 Excitable Slime。站在运河台阶上，不要站在水里，选中它并输入 /dance。",
    "可能要跳 5 到 100 次舞。当它在原地扭动并面向你时，接受它的任务 WRIGGLE.，把软泥交给它就能得到宠物。",
},
[95534] = {
    "从奥特兰克山脉的 Syndicate Wizards 或 Argus Shadow Mages 身上拾取 Singed Note，它会开启任务。",
    "在斯坦恩布莱德的锻炉，59, 46，几乎同时点燃两个风箱：法师的烈焰风暴、Easy Throw Dynamite、猎人的火焰陷阱、火焰之雨或地狱烈焰，或者两名玩家一起点。",
    "火元素会落在两个风箱之间。站在它落下的地方，否则它会消失，然后杀死它。站在锻炉旁会引来附近的辛迪加。",
    "在南海镇（联盟，Kundric Zanden）或塔伦米尔（部落，Shara Blazen）交任务，奖励 Brilliant Cloak。",
},
[93176] = {
    "悲伤沼泽西部的 Amaryllis Webb，25, 53，25 级起给任务和一个 Entomology Starter Kit。",
    "用工具包各抓一只：荆棘谷北部伐木营地的 Arbor Tarantula，44, 20；阿拉希农场的 Hay Weevil，31, 28；凄凉之地科多兽坟场的 Flesh Picker，52, 58。",
    "把三个标本带回给 Amaryllis，奖励宠物 Weevil K. Neevil。",
},
[97029] = {
    "拿到戒指 Ancient Heirloom：Skyborne 做 Ailee Farheart 的 Coming of Age，其他人到 Zephras Isle 41.7, 23.4 那座建筑的顶层拾取。",
    "从暮色森林卫兵的尸体上拿 Night Watchman's Torch（An Unfortunate End），点燃后趁那里的龙睡着时在 Ruins of Ban'aethal（Zephras Isle 58, 24）使用。Ancient Hilt 会出现。",
    "把剑柄交给 Valanaar 的 Ealaane Nimbuswalker，66, 74，然后寻找 Ancient Skyborne Blade：每次只在一处出现，49, 73、50, 44、66, 43 或 60, 82。",
    "把剑刃交回 Ealaane，得到 Eluvi'ana。Dawn Waker 秘密的其余部分还没人解开：留着这把剑和戒指。",
},
[-221315] = {
    "在黑石深渊走法律之环东边那座向北跨过熔岩的桥。",
    "在桥的左侧小火盆旁，从栏杆跳到贴墙的平台上。走到尽头，左肩贴着墙一直跑，直到掉到下面的岩架上。",
    "玩具 Traveler's Symbols 就在岩架上。那里的门只会把你带下去，到 Lord Incendius 那里。",
},
[-268109] = {
    "前往 Zephras Isle 瀑布顶上的岩石，51, 72，青蛙在那里唱歌。",
    "等至少两只青蛙坐在岩石上，选中一只并输入 /sing。",
    "青蛙消失后，你旁边的木头上会出现一只 Musical Gustjumper：点击它得到宠物。",
},
[-282047] = {
    "50 级的 Sewer Beast 在暴风城的运河里游动，71, 49 和 71, 68。",
    "它会掉落宠物 Baby Crocolisk，但不是每次都掉：它刷新后再杀。",
},
[95805] = {
    "先完成 A Humble Task 的两个部分：酋长的母亲在水井旁，50, 81。",
    "Seer Graytongue 在纳拉其营地以南的山丘上，42, 92。部落任何种族都能接这个任务。",
    "十分钟内把熏香送到东南山丘上的神龛。不要下水。",
},
[91775] = {
    "Nibbled-On Book 由北郡的狗头人掉落。那里的三个狗头人任务也能凑齐 8 本 Stolen Books。",
    "Shinyfinder Narf 是 3 级精英，在 Echo Ridge 矿洞里：第二个路口右转。",
    "去闪金镇的路上，点击北郡以南树旁的 6 处狗头人足迹。追踪工具用不了也照样计数。",
    "Fun with Elementals 由 Fargodeep 矿洞里的 Nimsy 掉落：走上层入口，从大厅向东再上楼梯。他有护卫，最好带个队友。",
},
[92515] = {
    "完成 Welcome to Shen'dar Village 后才能接：与村子中央的 Illaya Amberwind 和旅店的 Coriella Calmbreeze 交谈。",
    "然后在村子周围的 Shen'dar 高地击杀 Prideclaw，收集 10 张毛皮。",
},
[97277] = {
    "从 Anvilmar 正门沿路向左走。路的右侧有一条不显眼的雪道上山，经过第一棵树和几个箱子。",
    "山路很陡，但能爬上去。营地就在山脊后面。",
    "杀死 Snow Leopard Prowler，捡起地上的日志，原路返回。",
},
[791] = {
    "Furl Scornbrow 站在剃刀岭的瞭望塔上。",
    "Canvas Scraps 常由提拉加德城堡的人类掉落，58, 53。水手掉得比其他人多。",
},
[86784] = {
    "Dry Branches 在树丛附近，和地面很像。移动鼠标：指到树枝上时光标会变成齿轮。",
    "55, 55 的树旁有三根，大约 30 秒后刷新。",
    "Eleanor Shackleton 的营地在西边的山丘上，57, 55。",
},
[87288] = {
    "只有 5-6 级的 Nightsaber 掉毛皮，而且数量很少。",
    "在多兰纳尔以东的树林里来回走，绕开熊怪村。",
    "毛皮掉率低，需要花些时间。联盟任何种族都能做这个任务。",
},
[99053] = {
    "Sentinel Lynessa 在 Ban'ethil Barrow Den 最底层的一个壁龛里等候。",
    "先做完洞里的其他任务并清出一条出路：你要把她一路护送到大路上。",
    "跟紧她。她会冲向附近的每个敌人，离你太远任务就会失败。",
},
[151] = {
    "燕麦在西部荒野田地和农场的 Sack of Oats 里。",
    "萨丁农场：(56, 31)、(52, 34)、(52, 32)。摩尔森农场：(46, 38)、(45, 35)。法布隆南瓜农场：(49, 21)、(50, 18)。",
    "一袋燕麦要 5 到 10 分钟才刷新，所以去下一个农场。",
},
[97253] = {
    "零件看起来像垃圾，散落在棘齿城以南上层海盗营地的地面上。",
    "在帐篷旁边找，不要进帐篷里找。",
},
[140] = {
    "藏宝图由西部荒野海岸的鱼人掉落。",
    "小箱子在海滩上，26, 48，沉船附近的船锚旁。",
    "破桶在路边，40, 47，靠近倒塌的烟囱。罐子在风车旁的一根原木边，40, 17。",
    "宝箱在罐子以西三座小岛中最大的一座上，26, 17。",
},
[1003] = {
    "Buzzbox 827 在奥伯丁，37, 46，角鹰兽平台旁边。沿海岸往北的螃蟹更容易掉蟹腿。",
    "Buzzbox 411 在奥伯丁以北的海滩上，就在沉船的东边。蛇颈龙在深水里游动。",
    "Buzzbox 323：沿路向东北走，过 Cliffspring 河上的桥。盒子在路的左边。",
    "Buzzbox 525 在 41, 80，南下灰谷的路右侧。头皮掉率低，要杀很多熊。",
},
[1486] = {
    "Nalpak 在哀嚎洞穴入口上方的山洞里：爬到入口顶上，在边缘转身，走左边的洞口。",
    "毛皮由洞穴里的 Deviate 野兽掉落。20 张毛皮一趟凑不齐。",
    "最快的办法是进副本：清掉去水边路上的迅猛龙和鳄鱼，重置副本再来。",
},
[97926] = {
    "把炉石绑定在奥伯丁，然后在那里乘新开的船去暴风城。",
    "把信交给暴风城的 Baros Alexston，拿到他的回信。",
    "用炉石回奥伯丁，交回信。",
},
[531] = {
    "前两个任务限时。秃鹫在 78, 65 附近，这个很容易。",
    "整个地区只有大约 7 头 Elder Mountain Boar，而你要在 12 分钟内杀 5 头。接任务前先找好它们。",
    "Ol' Sooty 在塞尔萨玛以南的洞穴 (37, 62) 和湖之间走动。可能要等 10 到 20 分钟。",
},
[1474] = {
    "Dalin Forgewright 在银松森林南部的格雷迈恩之墙，约 46, 86。",
    "Comar Villard 在湿地的丹莫德，从阿拉希过桥后就是，50, 12。",
    "先召唤出虚空行者，再召唤魅魔。",
    "从奥格瑞玛开始的任务线奖励相同，也更容易。",
},
[1513] = {
    "Zankaja 在奥格瑞玛双足飞龙塔的西边，不是任务里说的飞艇塔：过桥后右转。",
    "Gazrog 站在十字路口旅店门前，51, 30。Ken'zigla 在石爪山脉的玛拉卡金，73, 95。",
    "Dogran 被关在贫瘠之地 43, 47，十字路口和陶拉祖营地之间那座桥的西边。野猪人看守着小屋，有时有精英。",
    "召唤法阵在 Neeru 的帐篷里，暗影裂口外面左侧。先召唤出虚空行者。",
},
[1739] = {
    "Takar the Seer 的帐篷在贫瘠之地陶拉祖营地附近的两棵树旁。从塞拉摩出发，沿山顶走，避开部落卫兵。",
    "Heartswood 是灰谷奥迪拉兰废墟里的大树，31, 31，靠近迈斯特拉岗哨。右键点击这棵树。",
    "把它交给暴风城的 Gakin，不要送回贫瘠之地。带着虚空行者召唤魅魔。",
},
[470] = {
    "包随机由湿地的软泥怪掉落，哪种都行。",
    "有人杀 3 只就出，有人要 100 只。远离 Ironbeard's Tomb 的软泥怪也会掉。",
},
[79192] = {
    "部落：在贫瘠之地 46, 73 熄灭的营火处拿纸条，送到西部荒野 37, 50 同样的营火处。联盟：顺序相反。",
    "下一张纸条指向石爪山脉。从大约 51, 51 的路边穿过山口进山，沿小路上到营地。",
    "结束任务的 Pocket Litter 就在那个营地里。",
},
[79976] = {
    "先完成 Stepping Stones（见那个奖励）。营地里的下一张纸条 Scramble 让你往北上山，到石爪山脉 39, 49 的 Mound of Dirt。",
    "Wet Job：在洛克莫丹走到北边大坝的中间，跳到放着 Carved Figurine 的岩架上，49, 12。部落：那里的卫兵很强。",
    "Eagle's Fist：Messenger Bag 在索拉丁之墙上，阿拉希 22, 24。大门北边、希尔斯布莱德一侧，从破马车往上跳：木桶、右边的木板、马车、梯子，再爬石头。",
    "交任务后打开旁边的 Hastily Rolled-Up Satchel，里面就是 Cozy Sleeping Bag。在里面每睡一分钟经验值 +1%，最多 +3%。",
},
[93269] = {
    "海加尔山顶的 Sebelia（71, 52）给出 Mending Communications。上山的路是封闭的：永望镇的 Evie Whirlbrew（61, 38）会做 Potion of Winterspring Shrouding，能把你送上去。",
    "把包裹带下山交给永望镇的 Innkeeper Vizzie（61, 39）。",
    "Unfrozen Deliveries：4 个 Missing Mail 只从 Ice Thistle Yeti 身上掉落（Rogue、Matriarch 和 Patriarch 不掉），在永望镇北边的山丘和东南的雪人洞附近。可以和 Are We There, Yeti? 一起做。",
    "Top of the Post：把邮件送回山顶给 Sebelia。她给 18 格的 Hyjal Postal Satchel。",
},
[96260] = {
    "去 Gloomrise 可以从莫高雷 40, 17、石爪山脉的玛拉卡金（小路起点 73, 96）或凄凉之地 77, 36 进入。",
    "Crystalline Silk 由 Gloomrise Spinner 掉落。需要 3 根。",
    "奖励在背包和材料包中二选一。做专业的玩家选材料包：普通丝绸包在拍卖行很便宜。",
},
[58] = {
    "Skeletal Warrior 和 Skeletal Mage 在 Tranquil Gardens 墓地，80, 70。",
    "Skeletal Fiend 和 Skeletal Horror 在乌鸦岭墓地，16, 44 附近。",
    "Plague Spreader 在乌鸦岭东部。数量不够就下到墓穴里：那里的大厅中更多。",
},
[1795] = {
    "Moldy Tome 在希尔斯布莱德南海镇西南海岸的鱼人营地里，是水边一本发蓝的书。",
    "Tattered Manuscript 在千针石林 Splithoof Hold 的一个小箱子里，44, 37：进去后走第一条右边的路。",
    "Rod of Channeling 由湿地 Angerfang 营地的龙喉兽人掉落。后门在 51, 45。",
    "你自己的恶魔可以和你一起打地狱猎犬。失败了就放弃任务重新接。",
},
[96109] = {
    "Rog'mar 的 Neza Bloodsnout 会连续给三个任务。",
    "大约每三只秃鹫掉一根羽毛，有些玩家掉得少得多。",
    "毒蛇在 Rog'mar 以南的水塘边，狮子在南边的小山上，从营地就能看到。",
},
[2439] = {
    "在奥达曼击杀最终首领 Archaedas。他身后的门通向宝藏室。",
    "点击 Discs of Norgannon，与出现的石头守望者把话全部说完，然后再点一次圆盘。",
    "把小圆盘带到铁炉堡探险者大厅的探险者协会。",
    "收兑换券的 Dinita Stonemantle 在铁炉堡银行左侧。",
},
[2440] = {
    "在奥达曼击杀最终首领 Archaedas。他身后的门通向宝藏室。",
    "点击 Discs of Norgannon，与出现的石头守望者把话全部说完，然后再点一次圆盘。",
    "把小圆盘带给雷霆崖的 Sage Truthseeker，35, 47。",
    "收兑换券的 Bena Winterhoof 在雷霆崖 46, 33。",
},
[626] = {
    "第一张卷轴在荆棘谷海岸外一艘血帆海盗船的底舱里。海盗很多，最好组队。",
    "悲伤沼泽：道路分岔后那座桥的下面，22, 48。卷轴很难看见，用鼠标在水面上扫。",
    "尘泥沼泽：31, 66 的迅猛龙洞穴。卷轴在洞底的一块石头上。",
    "辛特兰：宝箱在海岸大瀑布下面，81, 47。沿河向东，从顶上的岩石跳下去，用炉石离开。",
},
[3628] = {
    "Kirith 是 55 级精英，在诅咒之地东部的山洞里。进去时不要拾取尸体，这样洞里空得更久。之后与他的灵魂交谈。",
    "艾萨拉：Loramus 在 60, 66 的岛上，Lord Arkkoroc 在 77, 42 的神殿里。Hetaera 大约每 15 分钟游过 56, 44。艾萨拉水晶在南边的悬崖上，51, 71 附近。",
    "荆棘谷 50, 20 的 Galvan 打造武器。不必装备它：告诉 Fallen Hero 你弄丢了，他会给一份效果相同的 Fel Salve。",
    "在诅咒之地，Allistarj 在 65, 33，Lady Sevine 在 40, 30，Grol 在 43, 14。打 Razelikh 要带五个人。",
},
[84146] = {
    "Nami 要在一条隐藏任务线之后才给这个任务。起点在塔纳利斯南岸 59, 91：从 63, 64 沿岸走过去。",
    "留着第一个任务给的游泳药水。向南游向灯塔，再游到小岛：岛后面的石油平台上有 Sebastian Jurgens。顶着疲劳继续游，备好治疗药水。",
    "然后飞到永望镇找 Nami。包在燃烧平原一座小山上的帐篷旁。",
},
}

ns.TIPS = T
