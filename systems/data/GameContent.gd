class_name GameContent
extends RefCounted
## Static content/design data for Grimhollow, ported 1:1 from the design
## handoff (.design_ref/project/*.jsx). Pure data + a few static helpers; no
## scene-tree dependencies, so the CombatSim can use it headless.

# =========================================================================
# FIGHT — party, enemies, props, trail, spawn markers (fight.jsx)
# =========================================================================

## The 4-hero party: tight cluster lower-left third, tank leading toward TR.
## x/y are battlefield percentages.
const PARTY := [
	{"id": "brand", "name": "Brand", "role": "tank", "role_lbl": "Tank", "cls": "Bulwark", "hp": 100.0, "mana": 60.0, "x": 30.0, "y": 62.0, "lvl": 47},
	{"id": "ash", "name": "Ashling", "role": "dps", "role_lbl": "DPS", "cls": "Pyromancer", "hp": 74.0, "mana": 50.0, "x": 24.0, "y": 66.0, "lvl": 48},
	{"id": "hex", "name": "Hex", "role": "mage", "role_lbl": "Mage", "cls": "Hexcaster", "hp": 61.0, "mana": 90.0, "x": 20.0, "y": 63.0, "lvl": 44},
	{"id": "wren", "name": "Sister Wren", "role": "healer", "role_lbl": "Healer", "cls": "Lightbinder", "hp": 96.0, "mana": 82.0, "x": 24.0, "y": 72.0, "lvl": 45},
]

## Enemies converge from multiple edges; dist drives depth (size/fade).
const ENEMIES := [
	{"id": "boss", "name": "Bone Warden", "x": 71.0, "y": 15.0, "hp": 100.0, "elite": true, "dist": "mid"},
	{"id": "e1", "name": "Marrow Stalker", "x": 63.0, "y": 22.0, "hp": 88.0, "dist": "mid", "lunge": true, "trail_rot": 28.0},
	{"id": "e2", "name": "Hollow Ghoul", "x": 79.0, "y": 12.0, "hp": 60.0, "dist": "far"},
	{"id": "e3", "name": "Hollow Ghoul", "x": 83.0, "y": 30.0, "hp": 54.0, "dist": "far"},
	{"id": "e4", "name": "Hollow Ghoul", "x": 88.0, "y": 53.0, "hp": 70.0, "dist": "far", "lunge": true, "trail_rot": 0.0},
	{"id": "e5", "name": "Marrow Stalker", "x": 47.0, "y": 8.0, "hp": 80.0, "dist": "far"},
	{"id": "e6", "name": "Hollow Ghoul", "x": 58.0, "y": 91.0, "hp": 64.0, "dist": "mid", "lunge": true, "trail_rot": 95.0},
	{"id": "e7", "name": "Hollow Ghoul", "x": 45.0, "y": 49.0, "hp": 42.0, "dist": "near"},
	{"id": "e8", "name": "Marrow Stalker", "x": 40.0, "y": 57.0, "hp": 76.0, "dist": "near", "lunge": true, "trail_rot": 35.0},
]

## Depth tiers: us = unit scale, uo = unit opacity.
const DIST := {
	"far": {"us": 0.54, "uo": 0.5},
	"mid": {"us": 0.82, "uo": 0.92},
	"near": {"us": 1.0, "uo": 1.0},
}

## Environment props (iso dressing). w/h in px.
const PROPS := [
	{"id": "p1", "x": 46.0, "y": 44.0, "w": 50.0, "h": 64.0, "kind": "pillar", "label": "pillar"},
	{"id": "p2", "x": 62.0, "y": 60.0, "w": 48.0, "h": 60.0, "kind": "pillar", "label": "pillar"},
	{"id": "p3", "x": 78.0, "y": 38.0, "w": 40.0, "h": 48.0, "kind": "brazier", "label": "brazier"},
	{"id": "p4", "x": 70.0, "y": 70.0, "w": 64.0, "h": 44.0, "kind": "rubble", "label": "tomb"},
]

## Footstep trail behind the party, fading toward the bottom-left corner.
const TRAIL := [
	{"x": 8.0, "y": 92.0, "o": 0.10}, {"x": 11.0, "y": 87.0, "o": 0.16},
	{"x": 14.0, "y": 82.0, "o": 0.24}, {"x": 17.0, "y": 77.0, "o": 0.34},
	{"x": 20.0, "y": 72.0, "o": 0.46}, {"x": 24.0, "y": 68.0, "o": 0.58},
]

## Path-ahead chevrons pointing toward the top-right.
const AHEAD := [
	{"x": 38.0, "y": 51.0}, {"x": 46.0, "y": 44.0},
	{"x": 54.0, "y": 37.0}, {"x": 62.0, "y": 30.0},
]

## Edge spawn markers (rune-glints + arrows), concentrated top-right.
## a = degrees toward party so the arrow points where the foe will run.
const SPAWNS := [
	{"x": 84.0, "y": 6.0, "a": 141.0, "hot": true},
	{"x": 74.0, "y": 4.0, "a": 136.0, "hot": true},
	{"x": 90.0, "y": 22.0, "a": 150.0, "hot": true},
	{"x": 91.0, "y": 47.0, "a": 165.0, "hot": false},
	{"x": 46.0, "y": 4.0, "a": 113.0, "hot": false},
	{"x": 58.0, "y": 95.0, "a": 219.0, "hot": false},
]

## Where party meets enemies — damage numbers cluster here.
const CLASH := {"x": 40.0, "y": 54.0}

## Auto-loot ticker feed: [who, verb, item, rarity].
const LOOT_FEED := [
	["Ashling", "looted", "Cindergrip Maul", "epic"],
	["Party", "gained", "+240 Gold", "common"],
	["Hex", "looted", "Hexweave Cowl", "rare"],
	["Brand", "looted", "Bone Pauldron", "uncommon"],
	["Party", "found", "Relic Shard ×2", "epic"],
	["Wren", "looted", "Lightbinder Charm", "rare"],
	["Party", "gained", "+1,120 XP", "common"],
	["Ashling", "looted", "Emberglass Ring", "legendary"],
	["Party", "gained", "+180 Gold", "common"],
	["Hex", "looted", "Tattered Grimoire", "common"],
]

## Stage names rotate as the party advances.
const STAGE_NAMES := [
	"The Sunken Reliquary", "Gallows of the Pale", "Emberfall Crypts",
	"The Hollow Throat", "Marrowdeep", "Cinder Garden",
]

# =========================================================================
# CAMP — buildings, scene dressing, modals (camp.jsx)
# =========================================================================

## Building hotspots. x/y are scene percentages; w/h px.
const BUILDINGS := [
	{
		"id": "altar", "name": "Summoning Altar", "sub": "Skill Learning House",
		"x": 50.0, "y": 27.0, "w": 340.0, "h": 300.0, "hot": "Q", "featured": true,
		"sprite": "340×300 · altar", "tip_type": "Gacha · Featured banner active",
		"flavor": "Bind a wandering soul to your covenant. The altar hungers for soulstones.",
		"badge": "NEW BANNER",
	},
	{
		"id": "board", "name": "Notice Board", "sub": "Quests · Leaderboard · Daily",
		"x": 17.0, "y": 60.0, "w": 240.0, "h": 220.0, "hot": "E", "featured": false,
		"sprite": "240×220 · board", "tip_type": "Town bulletin",
		"flavor": "Bounties, rankings, and the rotating daily dungeon.",
		"badge": "3 NEW",
	},
	{
		"id": "forge", "name": "Crafting House", "sub": "Forge · Upgrade · Salvage",
		"x": 81.0, "y": 46.0, "w": 280.0, "h": 240.0, "hot": "R", "featured": false,
		"sprite": "280×240 · forge", "tip_type": "Smithing",
		"flavor": "Reforge iron and bone into something that bites back.",
		"badge": "",
	},
	{
		"id": "food", "name": "Hearthfire Kitchen", "sub": "Cook party-buff meals",
		"x": 34.0, "y": 74.0, "w": 230.0, "h": 200.0, "hot": "F", "featured": false,
		"sprite": "230×200 · kitchen", "tip_type": "Cooking · Buffs",
		"flavor": "A warm meal before the dark. Buffs the whole party for the next delve.",
		"badge": "",
	},
]

## Horizon ruin silhouettes: left %, width px, height px.
const RUINS := [
	{"l": 2.0, "w": 90.0, "h": 64.0}, {"l": 9.0, "w": 26.0, "h": 110.0},
	{"l": 23.0, "w": 70.0, "h": 44.0}, {"l": 43.0, "w": 30.0, "h": 88.0},
	{"l": 60.0, "w": 110.0, "h": 52.0}, {"l": 68.0, "w": 24.0, "h": 128.0},
	{"l": 88.0, "w": 80.0, "h": 70.0}, {"l": 95.0, "w": 34.0, "h": 100.0},
]

## Trodden-path glows radiating from the campfire: length px, rotation deg.
const WALKS := [
	{"len": 690.0, "rot": 180.0}, {"len": 380.0, "rot": -110.0},
	{"len": 465.0, "rot": -19.0}, {"len": 445.0, "rot": 161.0},
]

## Town crier ribbon entries: [lit, text_bbcode-ish parts kept simple].
const CRIER := [
	{"lit": true, "text": "Daily reset in ", "b": "06:12:40", "suffix": ""},
	{"lit": false, "text": "Ashen Covenant banner — ", "b": "5d left", "suffix": "", "b_ember": true},
	{"lit": true, "text": "Guild boss ", "b": "Maw of Ruin", "suffix": " now open"},
	{"lit": false, "text": "Friend ", "b": "Drossel", "suffix": " sent 5 energy"},
]

## Daily quests: title, progress, goal, reward (done derives from p >= g).
const QUESTS := [
	{"t": "Clear 3 dungeon stages", "p": 3.0, "g": 3.0, "rw": "240 Gold · 40 XP"},
	{"t": "Summon a hero", "p": 1.0, "g": 1.0, "rw": "1 Soulstone"},
	{"t": "Cook a party meal", "p": 0.0, "g": 1.0, "rw": "Hearth Token"},
	{"t": "Deal 5,000,000 damage", "p": 3.1, "g": 5.0, "rw": "120 Gold · Relic Shard"},
	{"t": "Salvage 5 items at the Forge", "p": 2.0, "g": 5.0, "rw": "Iron ×3"},
]

## Notice-board mini leaderboard.
const BOARD_RANKS := [
	{"r": 1, "n": "Mournheart", "lv": 88, "p": "412.6M", "me": false},
	{"r": 2, "n": "Vael (You)", "lv": 47, "p": "188.4M", "me": true},
	{"r": 3, "n": "Drossel", "lv": 52, "p": "176.0M", "me": false},
	{"r": 4, "n": "Ironwake", "lv": 61, "p": "162.9M", "me": false},
	{"r": 5, "n": "Lysa", "lv": 44, "p": "140.2M", "me": false},
]

## Kitchen recipes.
const RECIPES := [
	{"n": "Emberroot Stew", "r": "epic", "b": "+12% party ATK · 30 min", "have": true},
	{"n": "Gravewine Roast", "r": "rare", "b": "+8% Crit · 30 min", "have": true},
	{"n": "Frostberry Pie", "r": "rare", "b": "+15% Mana regen", "have": false},
	{"n": "Marrow Broth", "r": "uncommon", "b": "+10% HP · 30 min", "have": true},
	{"n": "Hollow Bread", "r": "common", "b": "+5% XP gain", "have": true},
	{"n": "Lantern Tea", "r": "legendary", "b": "+20% all stats · 15 min", "have": false},
]

# =========================================================================
# GACHA — pool + rates (camp.jsx)
# =========================================================================

const RARITY_RANK := {"common": 0, "uncommon": 1, "rare": 2, "epic": 3, "legendary": 4}

const HEROES_POOL := [
	{"n": "Ashling", "r": "legendary", "role": "5★ DPS · Pyromancer"},
	{"n": "Mordrake", "r": "epic", "role": "4★ Tank · Bulwark"},
	{"n": "Seraphine", "r": "epic", "role": "4★ Healer · Lightbinder"},
	{"n": "Korr", "r": "rare", "role": "3★ DPS · Reaver"},
	{"n": "Wisp", "r": "rare", "role": "3★ Support · Lantern"},
	{"n": "Grub", "r": "common", "role": "Shard · Iron"},
]

const GACHA_COST_X1 := 160
const GACHA_COST_X10 := 1600
const PITY_SOFT := 74
const PITY_HARD := 90

## One gacha roll. Soft pity ramps the legendary chance; hard pity guarantees.
## Rates/thresholds come from Balance (data/balance.json); the constants above
## are display fallbacks. Caller resets/increments the pity counter.
static func gacha_roll_rarity(pity: int, rng: RandomNumberGenerator) -> String:
	var base := Balance.num("gacha.base_legendary", 0.006)
	var soft := Balance.inum("gacha.soft_pity", PITY_SOFT)
	var hard := Balance.inum("gacha.hard_pity", PITY_HARD)
	var five_chance := base
	if pity >= soft:
		five_chance = base + float(pity - (soft - 1)) * Balance.num("gacha.soft_pity_step", 0.06)
	if pity >= hard:
		five_chance = 1.0
	var x := rng.randf()
	if x < five_chance:
		return "legendary"
	var epic := Balance.num("gacha.epic", 0.051)
	var rare := Balance.num("gacha.rare", 0.18)
	if x < five_chance + epic:
		return "epic"
	if x < five_chance + epic + rare:
		return "rare"
	return "uncommon" if rng.randf() < 0.5 else "common"


## Pick a hero of the given rarity from the pool (fallback: common).
static func gacha_pick(rarity: String, rng: RandomNumberGenerator) -> Dictionary:
	var cand: Array = []
	for h in HEROES_POOL:
		if h["r"] == rarity:
			cand.append(h)
	if cand.is_empty():
		for h in HEROES_POOL:
			if h["r"] == "common":
				cand.append(h)
	return cand[rng.randi_range(0, cand.size() - 1)]

# =========================================================================
# PROFILE — gear, stats, bag (profile.jsx)
# =========================================================================

## Equipped gear, left column then right column (paperdoll 5+5).
const GEAR_L := [
	{"slot": "Helm", "r": "epic", "name": "Cowl of the Hollow", "ilvl": 72, "stats": [["Armour", "+248"], ["Intelligence", "+42"], ["Spell Damage", "+12%"]]},
	{"slot": "Amulet", "r": "legendary", "name": "Emberglass Pendant", "ilvl": 80, "stats": [["All Attributes", "+30"], ["Fire Damage", "+24%"], ["Crit Multi", "+35%"]]},
	{"slot": "Body", "r": "epic", "name": "Gravewrought Plate", "ilvl": 75, "stats": [["Armour", "+612"], ["Maximum Life", "+184"], ["Fire Resist", "+38%"]]},
	{"slot": "Gloves", "r": "rare", "name": "Cinderweave Grips", "ilvl": 68, "stats": [["Attack Speed", "+9%"], ["Dexterity", "+24"]]},
	{"slot": "Boots", "r": "rare", "name": "Treads of Ash", "ilvl": 66, "stats": [["Movement Speed", "+18%"], ["Maximum Life", "+72"]]},
]
const GEAR_R := [
	{"slot": "Main Hand", "r": "legendary", "name": "Cindergrip Maul", "ilvl": 82, "stats": [["Physical DMG", "470–664"], ["Strength", "+72"], ["Crit Chance", "+8.5%"]]},
	{"slot": "Off Hand", "r": "epic", "name": "Bulwark of Cinders", "ilvl": 74, "stats": [["Block", "+32%"], ["Armour", "+288"], ["Life", "+96"]]},
	{"slot": "Ring I", "r": "rare", "name": "Band of Marrow", "ilvl": 64, "stats": [["Cold Resist", "+28%"], ["Mana", "+48"]]},
	{"slot": "Ring II", "r": "epic", "name": "Loop of Greed", "ilvl": 70, "stats": [["Item Rarity", "+14%"], ["Gold Find", "+22%"]]},
	{"slot": "Belt", "r": "uncommon", "name": "Girdle of Bone", "ilvl": 60, "stats": [["Maximum Life", "+64"], ["Stun Recovery", "+12%"]]},
]

## The 5 main attributes: key, name, value, color, description.
const MAIN_STATS := [
	{"k": "STR", "name": "Strength", "v": 642, "c": Color("e0584a"), "d": "Physical damage & armour."},
	{"k": "DEX", "name": "Dexterity", "v": 388, "c": Color("6fcf6a"), "d": "Attack speed, accuracy & evasion."},
	{"k": "INT", "name": "Intelligence", "v": 514, "c": Color("46c2d4"), "d": "Spell damage & maximum mana."},
	{"k": "VIT", "name": "Vitality", "v": 470, "c": Color("d6a24a"), "d": "Maximum life & recovery."},
	{"k": "LCK", "name": "Luck", "v": 196, "c": Color("a661d6"), "d": "Crit chance, item rarity & gold."},
]

## Detailed/derived stats: [label, value]. "−"-prefixed values render red.
const DETAILED := [
	["Attack DPS", "4.82M"], ["Spell DPS", "3.10M"], ["Crit Chance", "42.4%"], ["Crit Multiplier", "385%"],
	["Attack Speed", "1.86/s"], ["Cast Speed", "1.42/s"], ["Accuracy", "94%"], ["Life Regen", "2,140/s"],
	["Maximum Mana", "9,240"], ["Mana Regen", "880/s"], ["Evasion", "6,210"], ["Block Chance", "32%"],
	["Movement Speed", "+18%"], ["Fire Resist", "+58%"], ["Cold Resist", "+44%"], ["Lightning Resist", "+39%"],
	["Chaos Resist", "−12%"], ["Item Rarity", "+36%"], ["Gold Find", "+41%"], ["XP Gain", "+12%"],
]

## Combat summary rows for the character sheet: [icon, label, value, color_key, stats].
const COMBAT_SUMMARY := [
	{"ico": "⚔", "lbl": "Attack Power", "val": "4.82M", "c": "ember", "st": [["Attack DPS", "4.82M"], ["Spell DPS", "3.10M"]]},
	{"ico": "⛨", "lbl": "Armour", "val": "12,480", "c": "gold", "st": [["Physical mitigation", "62%"]]},
	{"ico": "❤", "lbl": "Life", "val": "184,200", "c": "hp", "st": [["Regen", "2,140/s"]]},
]

## Inventory bag, keyed by tab id. Items: n, r, t, optional q (stack), s (stats).
const BAG := {
	"equipment": [
		{"n": "Cinder Shard Blade", "r": "epic", "t": "Sword · iLvl 71", "s": [["Physical DMG", "388–520"], ["Fire Damage", "+18%"]]},
		{"n": "Gravewax Seal", "r": "epic", "t": "Amulet · iLvl 69", "s": [["Maximum Life", "+120"], ["Cast Speed", "+8%"]]},
		{"n": "Emberglass Band", "r": "legendary", "t": "Ring · iLvl 78", "s": [["Fire Damage", "+22%"], ["Crit Multi", "+28%"]]},
		{"n": "Hexweave Cowl", "r": "rare", "t": "Helm · iLvl 64", "s": [["Intelligence", "+28"], ["Mana", "+60"]]},
		{"n": "Ashplate Greaves", "r": "rare", "t": "Boots · iLvl 62", "s": [["Armour", "+180"], ["Move Speed", "+12%"]]},
		{"n": "Veilwoven Wrap", "r": "rare", "t": "Chest · iLvl 60", "s": [["Evasion", "+240"], ["Cold Resist", "+20%"]]},
		{"n": "Wyrmhide Belt", "r": "rare", "t": "Belt · iLvl 58", "s": [["Life", "+88"], ["Stun Recovery", "+15%"]]},
		{"n": "Pitiron Gauntlets", "r": "uncommon", "t": "Gloves · iLvl 55", "s": [["Strength", "+18"], ["Armour", "+96"]]},
		{"n": "Bone Pauldron", "r": "uncommon", "t": "Shoulder · iLvl 52", "s": [["Armour", "+120"]]},
		{"n": "Marrow Club", "r": "common", "t": "Mace · iLvl 41", "s": [["Physical DMG", "120–180"]]},
		{"n": "Tattered Grimoire", "r": "common", "t": "Offhand · iLvl 38", "s": [["Spell Damage", "+6%"]]},
		{"n": "Sigil of Embers", "r": "epic", "t": "Ring · iLvl 66", "s": [["Ignite Chance", "+12%"], ["Fire Resist", "+18%"]]},
	],
	"consumables": [
		{"n": "Greater Life Flask", "r": "rare", "t": "Flask", "q": 12, "s": [["Restores", "45% Life"]]},
		{"n": "Mana Draught", "r": "uncommon", "t": "Flask", "q": 8, "s": [["Restores", "60% Mana"]]},
		{"n": "Emberroot Stew", "r": "epic", "t": "Meal", "q": 3, "s": [["Party ATK", "+12% · 30m"]]},
		{"n": "Stoneskin Tonic", "r": "rare", "t": "Tonic", "q": 5, "s": [["Armour", "+25% · 10m"]]},
		{"n": "Scroll of Return", "r": "common", "t": "Scroll", "q": 14, "s": [["Effect", "Teleport to camp"]]},
		{"n": "Hollow Bread", "r": "common", "t": "Meal", "q": 9, "s": [["XP Gain", "+5% · 30m"]]},
	],
	"materials": [
		{"n": "Iron Ingot", "r": "common", "t": "Smithing", "q": 46},
		{"n": "Ember Dust", "r": "rare", "t": "Smithing", "q": 38},
		{"n": "Relic Shard", "r": "epic", "t": "Relic-craft", "q": 11},
		{"n": "Gravesilk Thread", "r": "uncommon", "t": "Tailoring", "q": 23},
		{"n": "Hollow Marrow", "r": "rare", "t": "Alchemy", "q": 17},
		{"n": "Cinder Core", "r": "legendary", "t": "Smithing · rare drop", "q": 2},
		{"n": "Bone Meal", "r": "common", "t": "Alchemy", "q": 64},
	],
	"quest": [
		{"n": "Warden's Rusted Key", "r": "epic", "t": "Quest · The Sunken Reliquary", "s": [["Opens", "Reliquary Gate 4-10"]]},
		{"n": "Pale Census Ledger", "r": "rare", "t": "Quest · Hollowreach Camp", "s": [["Deliver to", "Notice Board"]]},
		{"n": "Ashling's Locket", "r": "legendary", "t": "Quest · Personal", "s": [["Hint", "She won't speak of it."]]},
	],
}

const INV_TABS := [["equipment", "Equipment"], ["consumables", "Consumables"], ["materials", "Materials"], ["quest", "Quest"]]
const INV_CELLS := 30

# =========================================================================
# PETS + RELICS (petsrelics.jsx)
# =========================================================================

const PETS := [
	{"n": "Emberwhelp", "r": "legendary", "owned": true, "active": true, "eff": "+8% party Fire Damage", "role": "Drake"},
	{"n": "Cryptbat", "r": "epic", "owned": true, "active": false, "eff": "+6% Life Leech", "role": "Swarm"},
	{"n": "Gloomcat", "r": "epic", "owned": true, "active": false, "eff": "+10% Crit vs marked", "role": "Stalker"},
	{"n": "Tomb Beetle", "r": "rare", "owned": true, "active": false, "eff": "+12% Armour", "role": "Guard"},
	{"n": "Will-o-Wisp", "r": "rare", "owned": true, "active": false, "eff": "+8% Mana regen", "role": "Lantern"},
	{"n": "Bone Pup", "r": "uncommon", "owned": true, "active": false, "eff": "+5% Gold Find", "role": "Scout"},
	{"n": "Ash Sprite", "r": "uncommon", "owned": true, "active": false, "eff": "+4% Rarity", "role": "Spirit"},
	{"n": "Mire Toad", "r": "common", "owned": true, "active": false, "eff": "+10 Max Life", "role": "Croaker"},
	{"n": "Dread Owl", "r": "legendary", "owned": false, "active": false, "eff": "Reveals rare loot", "role": "Omen"},
	{"n": "Grave Worm", "r": "epic", "owned": false, "active": false, "eff": "+8% XP gain", "role": "Burrower"},
	{"n": "Cinder Fox", "r": "rare", "owned": false, "active": false, "eff": "+6% move speed", "role": "Trickster"},
	{"n": "Hex Imp", "r": "epic", "owned": false, "active": false, "eff": "Curses on hit", "role": "Fiend"},
]

const RELICS := [
	{"n": "Hollow Crown", "r": "legendary", "eff": "+12% All Damage · +60 Max Life", "owned": true, "empty": false},
	{"n": "Gravewrought Sigil", "r": "epic", "eff": "+18% Crit Multiplier", "owned": true, "empty": false},
	{"n": "Ashen Tear", "r": "epic", "eff": "+22% Fire Damage", "owned": true, "empty": false},
	{"n": "Coil of the Deep", "r": "rare", "eff": "+30 Mana · +8% Cast Speed", "owned": true, "empty": false},
	{"n": "", "r": "common", "eff": "", "owned": false, "empty": true},
	{"n": "", "r": "common", "eff": "", "owned": false, "empty": true},
]

const RELIC_COLL := [
	{"n": "Widow's Lantern", "r": "legendary"}, {"n": "Pale Idol", "r": "epic"},
	{"n": "Rusted Crown", "r": "rare"}, {"n": "Bog Charm", "r": "uncommon"},
	{"n": "Cracked Vial", "r": "common"}, {"n": "Sunken Bell", "r": "rare"},
	{"n": "Ember Knot", "r": "epic"}, {"n": "Marrow Die", "r": "uncommon"},
]

# =========================================================================
# LEADERBOARD (leaderboard.jsx)
# =========================================================================

const SEASON := {
	"num": "III", "name": "Emberfall", "ends": "12d 04h 38m",
	"you": {"tier": "Emberlord", "next": "Hollow Sovereign", "pct": "Top 0.2%", "to_next": 1, "prog": 88},
}

const TIERS := [
	{"name": "Hollow Sovereign", "rar": "legendary", "range": "Top 10", "reward": "Mythic Cache · Title", "you": false},
	{"name": "Emberlord", "rar": "epic", "range": "Top 50", "reward": "Epic Cache · 1,200 Gold", "you": true},
	{"name": "Goldmark", "rar": "rare", "range": "Top 500", "reward": "Rare Cache · 600 Gold", "you": false},
	{"name": "Ironclad", "rar": "uncommon", "range": "Top 5,000", "reward": "Uncommon Cache", "you": false},
	{"name": "Ashbound", "rar": "common", "range": "All Delvers", "reward": "Participation Cache", "you": false},
]

const CATS := [
	{"key": "power", "label": "Total Power", "hot": "Q", "sub": "Total Power"},
	{"key": "stage", "label": "Deepest Stage", "hot": "W", "sub": "Deepest Stage"},
	{"key": "boss", "label": "Boss Damage", "hot": "E", "sub": "Boss Damage"},
	{"key": "weekly", "label": "Weekly Climb", "hot": "R", "sub": "Ranks Climbed"},
]

const SCOPES := [["global", "Global"], ["friends", "Friends"], ["guild", "Guild"]]

const GUILDS := {
	"ASH": {"name": "Ashen Covenant", "c": Color("e8843a")},
	"VIG": {"name": "The Vigil", "c": Color("cdd2d6")},
	"HEX": {"name": "Hexbound", "c": Color("a661d6")},
	"GLD": {"name": "Gilded Hand", "c": Color("d3ad62")},
	"TMB": {"name": "Tombwardens", "c": Color("6fcf6a")},
}

## One dataset; each category sorts the same delvers differently.
## stage is [act, sub]; power/boss in millions.
const PLAYERS := [
	{"name": "Mournheart", "guild": "VIG", "lv": 88, "tier": "Hollow Sovereign", "power": 412.6, "stage": [9, 12], "boss": 88.4, "weekly": 142, "trend": 0, "you": false, "friend": false},
	{"name": "Sablewing", "guild": "HEX", "lv": 84, "tier": "Hollow Sovereign", "power": 388.0, "stage": [9, 4], "boss": 79.2, "weekly": 96, "trend": 1, "you": false, "friend": true},
	{"name": "Ironwake", "guild": "ASH", "lv": 81, "tier": "Hollow Sovereign", "power": 362.9, "stage": [8, 40], "boss": 91.0, "weekly": 210, "trend": 2, "you": false, "friend": false},
	{"name": "Drossel", "guild": "VIG", "lv": 79, "tier": "Hollow Sovereign", "power": 344.2, "stage": [8, 38], "boss": 71.5, "weekly": 54, "trend": -1, "you": false, "friend": true},
	{"name": "Lysa Vane", "guild": "GLD", "lv": 77, "tier": "Hollow Sovereign", "power": 318.7, "stage": [8, 44], "boss": 66.1, "weekly": 118, "trend": 1, "you": false, "friend": false},
	{"name": "Korrath", "guild": "TMB", "lv": 74, "tier": "Hollow Sovereign", "power": 289.4, "stage": [8, 22], "boss": 61.8, "weekly": 33, "trend": 0, "you": false, "friend": false},
	{"name": "Grimsel", "guild": "ASH", "lv": 72, "tier": "Hollow Sovereign", "power": 265.0, "stage": [8, 15], "boss": 58.2, "weekly": 175, "trend": 1, "you": false, "friend": false},
	{"name": "Hollowfen", "guild": "HEX", "lv": 70, "tier": "Hollow Sovereign", "power": 243.1, "stage": [8, 8], "boss": 54.0, "weekly": 60, "trend": -2, "you": false, "friend": false},
	{"name": "Thornard", "guild": "GLD", "lv": 67, "tier": "Hollow Sovereign", "power": 226.8, "stage": [7, 44], "boss": 49.7, "weekly": 88, "trend": 1, "you": false, "friend": true},
	{"name": "Mariss", "guild": "VIG", "lv": 64, "tier": "Hollow Sovereign", "power": 204.5, "stage": [7, 36], "boss": 45.2, "weekly": 41, "trend": 0, "you": false, "friend": false},
	{"name": "Vael", "guild": "ASH", "lv": 47, "tier": "Emberlord", "power": 188.4, "stage": [7, 40], "boss": 96.8, "weekly": 224, "trend": 3, "you": true, "friend": true},
	{"name": "Dunmore", "guild": "TMB", "lv": 61, "tier": "Emberlord", "power": 176.0, "stage": [7, 18], "boss": 37.1, "weekly": 22, "trend": -1, "you": false, "friend": false},
	{"name": "Ashveil", "guild": "ASH", "lv": 58, "tier": "Emberlord", "power": 162.9, "stage": [7, 10], "boss": 33.6, "weekly": 150, "trend": 1, "you": false, "friend": true},
	{"name": "Pyrrich", "guild": "HEX", "lv": 55, "tier": "Emberlord", "power": 150.2, "stage": [6, 40], "boss": 30.0, "weekly": 18, "trend": 0, "you": false, "friend": false},
	{"name": "Gravewend", "guild": "GLD", "lv": 52, "tier": "Goldmark", "power": 138.4, "stage": [6, 33], "boss": 27.4, "weekly": 73, "trend": 1, "you": false, "friend": false},
	{"name": "Sister Cael", "guild": "TMB", "lv": 49, "tier": "Goldmark", "power": 126.1, "stage": [6, 25], "boss": 24.2, "weekly": 29, "trend": -1, "you": false, "friend": true},
]

## Sort key for a player in a category.
static func lb_sort_key(p: Dictionary, cat: String) -> float:
	match cat:
		"stage":
			return float(p["stage"][0]) * 100.0 + float(p["stage"][1])
		"boss":
			return float(p["boss"])
		"weekly":
			return float(p["weekly"])
		_:
			return float(p["power"])


## Display value for a player in a category.
static func lb_fmt_val(p: Dictionary, cat: String) -> String:
	match cat:
		"stage":
			return "%d-%02d" % [p["stage"][0], p["stage"][1]]
		"boss":
			return "%.1fM" % float(p["boss"])
		"weekly":
			return "+%d" % int(p["weekly"])
		_:
			return "%.1fM" % float(p["power"])


## Tier record for a tier name ({} if unknown).
static func tier_of(tier_name: String) -> Dictionary:
	for t in TIERS:
		if t["name"] == tier_name:
			return t
	return {}

# =========================================================================
# TALENT TREE (talents.jsx) — deterministic procedural web
# =========================================================================

const ARMS := [
	{"name": "Might", "stat": "STR", "color": Color("e0584a")},
	{"name": "Precision", "stat": "DEX", "color": Color("6fcf6a")},
	{"name": "Arcana", "stat": "INT", "color": Color("46c2d4")},
	{"name": "Endurance", "stat": "VIT", "color": Color("d6a24a")},
	{"name": "Fortune", "stat": "LUCK", "color": Color("a661d6")},
	{"name": "Ruin", "stat": "STR", "color": Color("e8843a")},
]

const MINOR := {
	"STR": ["+10 Strength", "+8 Physical Damage", "+12 Armour", "+6% Melee Damage"],
	"DEX": ["+10 Dexterity", "+6% Attack Speed", "+8 Accuracy", "+4% Evasion"],
	"INT": ["+10 Intelligence", "+12 Maximum Mana", "+6% Spell Damage", "+5% Cast Speed"],
	"VIT": ["+14 Maximum Life", "+8 Life Regen", "+10 Armour", "+4% Life Recovery"],
	"LUCK": ["+8 Luck", "+4% Item Rarity", "+3% Crit Chance", "+5% Gold Find"],
}

const NOTABLE := {
	"Might": [["Reaver's Wrath", "+24% Melee Damage · +30 Strength"], ["Ironhide", "+18% Armour · +40 Max Life"]],
	"Precision": [["Deadeye", "+12% Crit Multiplier · +20 Accuracy"], ["Fleetfoot", "+10% Attack Speed · +8% Evasion"]],
	"Arcana": [["Manaweaver", "+30 Max Mana · +12% Spell Damage"], ["Hexbloom", "Curses spread to nearby foes"]],
	"Endurance": [["Bulwark", "+60 Max Life · +14% Block"], ["Last Stand", "+40% Recovery below 35% Life"]],
	"Fortune": [["Goldtongue", "+18% Gold Find · +6% Rarity"], ["Fated", "+8% Crit · +12% Rarity"]],
	"Ruin": [["Cinderbrand", "Ignites deal +40% damage"], ["Scorched Earth", "+25% Burn duration"]],
}

const KEYSTONE := {
	"Might": ["Avatar of Fury", "Cannot be Stunned. +20% damage, but -30% Life."],
	"Precision": ["Perfect Aim", "Critical strikes never miss and gain +50% multiplier."],
	"Arcana": ["Eldritch Battery", "Spend Life as Mana when Mana is depleted."],
	"Endurance": ["Unbreakable", "Armour also applies to elemental damage."],
	"Fortune": ["Hand of Fate", "Doubles rarity bonuses, halves quantity."],
	"Ruin": ["Pyre Heart", "Killing a burning enemy spreads the flames."],
}

const TREE_SEED := 20260608
const TALENT_POINTS_AVAILABLE := 12

## Mulberry32 PRNG state (32-bit), matching the prototype exactly so the tree
## layout is identical. Call _mulberry_next to advance.
class Mulberry:
	var state: int

	func _init(seed_value: int) -> void:
		state = seed_value & 0xFFFFFFFF

	func next() -> float:
		state = (state + 0x6D2B79F5) & 0xFFFFFFFF
		var t := state
		t = _imul(t ^ (t >> 15), t | 1)
		t = (t + (_imul(t ^ (t >> 7), t | 61) & 0xFFFFFFFF)) & 0xFFFFFFFF ^ t
		t = t & 0xFFFFFFFF
		return float((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0

	static func _imul(a: int, b: int) -> int:
		# JS Math.imul: 32-bit integer multiply (result kept unsigned here).
		return (a * b) & 0xFFFFFFFF

	func pick(arr: Array) -> Variant:
		return arr[int(next() * arr.size())]


## Build the talent web: returns {"nodes": Array[Dictionary], "edges": Array}.
## Node: {id, x, y, type ("start"/"minor"/"notable"/"keystone"), ai, label, eff}.
static func build_tree() -> Dictionary:
	var rng := Mulberry.new(TREE_SEED)
	var nodes: Array = []
	var edges: Array = []

	var add := func(x: float, y: float, type: String, ai: int, label: String, eff: String) -> int:
		var nid := nodes.size()
		nodes.append({"id": nid, "x": x, "y": y, "type": type, "ai": ai, "label": label, "eff": eff})
		return nid

	var center: int = add.call(0.0, 0.0, "start", -1, "The Hollow Core", "The seat of your power. Allocate outward.")

	# Recursive arm growth (lambda recursion via array holder).
	var grow_holder: Array = []
	var grow := func(from_id: int, ang: float, len_steps: int, ai: int, depth: int) -> void:
		var grow_self: Callable = grow_holder[0]
		var prev := from_id
		var px: float = nodes[from_id]["x"]
		var py: float = nodes[from_id]["y"]
		var arm: Dictionary = ARMS[ai]
		for s in range(1, len_steps + 1):
			var dist := 104.0 + rng.next() * 26.0
			var a := ang + (rng.next() * 0.46 - 0.23)
			px += cos(a) * dist
			py += sin(a) * dist
			var last := s == len_steps
			var notable := (not last) and (s % 2 == 0)
			var type := "minor"
			var label: String = String(arm["stat"]) + " Node"
			var eff: String = rng.pick(MINOR[arm["stat"]])
			if last and depth == 0:
				type = "keystone"
				var k: Array = KEYSTONE[arm["name"]]
				label = k[0]
				eff = k[1]
			elif notable:
				type = "notable"
				var nb: Array = rng.pick(NOTABLE[arm["name"]])
				label = nb[0]
				eff = nb[1]
			var nid: int = add.call(px, py, type, ai, label, eff)
			edges.append([prev, nid])
			prev = nid
			if notable:
				var cn := 2 + int(rng.next() * 3.0)
				for c in cn:
					var ca := a + (float(c) - float(cn) / 2.0) * 0.55 + (rng.next() * 0.3 - 0.15)
					var cd := 66.0 + rng.next() * 22.0
					var cid: int = add.call(px + cos(ca) * cd, py + sin(ca) * cd, "minor", ai, String(arm["stat"]) + " Node", rng.pick(MINOR[arm["stat"]]))
					edges.append([nid, cid])
			if depth == 0 and s == 2:
				grow_self.call(nid, a + 0.95, len_steps - 2, ai, 1)
				grow_self.call(nid, a - 0.95, len_steps - 2, ai, 1)
	grow_holder.append(grow)

	for ai in ARMS.size():
		grow.call(center, (float(ai) / float(ARMS.size())) * TAU - PI / 2.0, 5, ai, 0)

	return {"nodes": nodes, "edges": edges}


## Default initial allocation: center + a short path outward (matches design).
static func default_allocation(nodes: Array, edges: Array) -> Array[int]:
	var adj := {}
	for n in nodes:
		adj[int(n["id"])] = []
	for e in edges:
		adj[int(e[0])].append(int(e[1]))
		adj[int(e[1])].append(int(e[0]))
	var alloc: Array[int] = [0]
	var cur := 0
	var steps := 0
	while steps < 5:
		var nxt := -1
		for n in adj[cur]:
			if n > cur and not alloc.has(n):
				nxt = n
				break
		if nxt < 0:
			break
		alloc.append(nxt)
		cur = nxt
		steps += 1
	return alloc
