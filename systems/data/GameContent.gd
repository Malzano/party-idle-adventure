class_name GameContent
extends RefCounted
## Static content/design data, ported 1:1 from the design handoff
## (.design_ref/project/*.jsx — internal codename "Grimhollow"). Pure data +
## a few static helpers; no scene-tree dependencies, so the CombatSim can
## use it headless.

## Working title — the ONE place the product name lives (window titles, login
## logo, tooltips compose from it). Swap here when the final name lands. The
## in-world lore names (the Hollow, Hollowreach) are setting, not branding.
const GAME_TITLE := "BinkBonk Idle"

# =========================================================================
# FIGHT — party, enemies, props, trail, spawn markers (fight.jsx)
# =========================================================================

## The 4-hero party: tight cluster lower-left third, tank leading toward TR.
## x/y are battlefield percentages.
const PARTY := [
	{"id": "brand", "name": "Bonk", "role": "tank", "role_lbl": "Tank", "cls": "Shieldbud", "hp": 100.0, "mana": 60.0, "x": 30.0, "y": 62.0, "lvl": 47},
	{"id": "ash", "name": "Pyra", "role": "dps", "role_lbl": "DPS", "cls": "Emberpuff", "hp": 74.0, "mana": 50.0, "x": 24.0, "y": 66.0, "lvl": 48},
	{"id": "hex", "name": "Mimsy", "role": "mage", "role_lbl": "Mage", "cls": "Stargazer", "hp": 61.0, "mana": 90.0, "x": 20.0, "y": 63.0, "lvl": 44},
	{"id": "wren", "name": "Lulu", "role": "healer", "role_lbl": "Healer", "cls": "Moonpetal", "hp": 96.0, "mana": 82.0, "x": 24.0, "y": 72.0, "lvl": 45},
]

# =========================================================================
# HERO COLLECTION (design v2 roster.jsx) — the recruitable pool the party
# lineup (GameState.party_ids) draws from. The first four mirror PARTY;
# `locked` heroes recruit by being summoned at the altar (gacha → a
# roster_extra entry with the same name unlocks them).
# =========================================================================

const HEROES := [
	{"id": "brand", "name": "Bonk", "cls": "Shieldbud", "role": "tank", "role_lbl": "Tank", "r": "epic", "lvl": 47, "hp": 100.0, "mana": 60.0, "trait": "Boops foes and blocks 32% of hits."},
	{"id": "ash", "name": "Pyra", "cls": "Emberpuff", "role": "dps", "role_lbl": "DPS", "r": "legendary", "lvl": 48, "hp": 74.0, "mana": 50.0, "trait": "Toasty sparks melt armour. Featured banner pal!"},
	{"id": "hex", "name": "Mimsy", "cls": "Stargazer", "role": "mage", "role_lbl": "Mage", "r": "epic", "lvl": 44, "hp": 61.0, "mana": 90.0, "trait": "Sleepy stardust drifts to nearby foes."},
	{"id": "wren", "name": "Lulu", "cls": "Moonpetal", "role": "healer", "role_lbl": "Healer", "r": "epic", "lvl": 45, "hp": 96.0, "mana": 82.0, "trait": "Heals the sleepiest pal every 4s."},
	{"id": "mord", "name": "Brambles", "cls": "Thornhugger", "role": "tank", "role_lbl": "Tank", "r": "epic", "lvl": 41, "hp": 100.0, "mana": 44.0, "trait": "Grows a hedge wall at half health."},
	{"id": "sera", "name": "Sunny", "cls": "Dawnsprout", "role": "healer", "role_lbl": "Healer", "r": "epic", "lvl": 39, "hp": 88.0, "mana": 90.0, "trait": "Revives once per adventure."},
	{"id": "korr", "name": "Chomps", "cls": "Nibbler", "role": "dps", "role_lbl": "DPS", "r": "rare", "lvl": 36, "hp": 80.0, "mana": 38.0, "trait": "Gets the zoomies per bonk, up to +40% speed."},
	{"id": "tarn", "name": "Twig", "cls": "Acorn Archer", "role": "dps", "role_lbl": "DPS", "r": "rare", "lvl": 28, "hp": 64.0, "mana": 42.0, "trait": "Always bonks the farthest foe."},
	{"id": "wisp", "name": "Glow", "cls": "Firefly", "role": "healer", "role_lbl": "Healer", "r": "rare", "lvl": 30, "hp": 58.0, "mana": 96.0, "trait": "Mana lemonade aura for the party."},
	{"id": "grub", "name": "Pebble", "cls": "Rockling", "role": "tank", "role_lbl": "Tank", "r": "common", "lvl": 12, "hp": 90.0, "mana": 20.0, "trait": "Cheap, loyal, surprisingly sturdy."},
	{"id": "veyra", "name": "Zappy", "cls": "Stormbean", "role": "mage", "role_lbl": "Mage", "r": "legendary", "lvl": 1, "hp": 60.0, "mana": 100.0, "trait": "Chain sparkles arc to 5 targets.", "locked": true},
	{"id": "oszric", "name": "Goober", "cls": "Slimeling", "role": "mage", "role_lbl": "Mage", "r": "epic", "lvl": 1, "hp": 58.0, "mana": 92.0, "trait": "Goo stacks never expire.", "locked": true},
]

const DEFAULT_PARTY_IDS: Array[String] = ["brand", "ash", "hex", "wren"]


static func hero_by_id(id: String) -> Dictionary:
	for h in HEROES:
		if String(h["id"]) == id:
			return h
	return {}


## The asset bundle a hero renders from: its equipped skin if one is set,
## else the base "hero.<id>" bundle. AssetManager resolves art (or placeholder).
## The single character ("self") renders from its class bundle.
static func hero_bundle(hero_id: String) -> String:
	if hero_id == "self":
		var skin := String(GameState.hero_skins.get("self", ""))
		return skin if skin != "" else "class." + GameState.class_id
	var skin2 := String(GameState.hero_skins.get(hero_id, ""))
	return skin2 if skin2 != "" else "hero." + hero_id


## Battlefield role for a class id — no healer tier; mirrors the server's
## composition aura. Reused by active_party() and the party display.
static func class_role(class_id: String) -> Dictionary:
	match class_id:
		"warrior": return {"role": "tank", "lbl": "Tank"}
		"mage": return {"role": "mage", "lbl": "Mage"}
		"hunter": return {"role": "dps", "lbl": "Ranger"}
		"rogue": return {"role": "dps", "lbl": "Rogue"}
		_: return {"role": "dps", "lbl": "Adventurer"}


## Real-party composition aura — GD mirror of the server's compositionAura.ts so
## a MOCK party shows a bonus too. Over the ONLINE members' class/role spread
## (size + distinct classes + distinct roles, capped). Live mode reads the
## server's party_aura_mult directly; this is only the mock fallback.
static func composition_aura_mult(members: Array) -> float:
	var online: Array = []
	for m_v in members:
		var m := m_v as Dictionary
		if bool(m.get("online", false)) and String(m.get("class_id", "")) != "":
			online.append(m)
	if online.size() <= 1:
		return 1.0
	var classes := {}
	var roles := {}
	for m in online:
		var cid := String((m as Dictionary)["class_id"])
		classes[cid] = true
		roles[String(class_role(cid)["role"])] = true
	var c: Dictionary = Balance.value("composition", {})
	var bonus := float(c.get("size_step", 0.03)) * float(online.size() - 1) \
		+ float(c.get("class_step", 0.035)) * float(classes.size() - 1) \
		+ float(c.get("role_step", 0.025)) * float(roles.size() - 1)
	return 1.0 + minf(float(c.get("cap", 0.28)), bonus)


## Locked heroes join the collection once the altar gives them back: any
## gacha summon (roster_extra) carrying the same name recruits them.
static func hero_recruited(id: String) -> bool:
	var hero := hero_by_id(id)
	if hero.is_empty():
		return false
	if not bool(hero.get("locked", false)):
		return true
	for summoned in GameState.roster_extra:
		if String((summoned as Dictionary).get("n", "")) == String(hero["name"]):
			return true
	return false


## The single character you play (1 account = 1 character). The battlefield,
## the Fight HUD frame, the party-finder dock and the sim vitals all read this,
## so returning one entry renders one delver everywhere. Wears the cluster's
## lead anchor. (The 12-hero HEROES pool + aura_check are dormant — pruned in a
## later cleanup once no v2 saves reference them.)
static func active_party() -> Array:
	var cls := class_by_id(GameState.class_id)
	var cr := class_role(GameState.class_id)
	var nm := GameState.player_name if GameState.player_name != "" else String(cls.get("name", "Adventurer"))
	return [{
		"id": "self",
		"name": nm,
		"role": String(cr["role"]),
		"role_lbl": String(cr["lbl"]),
		"class_id": GameState.class_id,  # battlefield reads this for facing + projectile spec
		"cls": String(cls.get("name", "Adventurer")),
		"hp": 100.0,
		"mana": 80.0,
		"x": 26.0,
		"y": 66.0,
		"lvl": GameState.player_level,
	}]


# --- Floor-themed enemy rosters (the names the battlefield spawns; wraps per
# floor like the boss-name tables in bosses.json). Floor 1 = weak early foes. --
const ENEMY_ROSTER := [
	{"elite": "Royal Gloop", "trash": ["Gloopy Slime", "Crumb Mouse"]},       # floor 1
	{"elite": "Toasty Twig", "trash": ["Warm Puff", "Ember Bunny"]},          # floor 2
	{"elite": "Grumpy Boulder", "trash": ["Pebble Pal", "Rolly Poly"]},       # floor 3
	{"elite": "Dizzy Duke", "trash": ["Silly Sprout", "Twirly Wisp"]},        # floor 4
	{"elite": "Mushroom Knight", "trash": ["Sneaky Snail", "Puffball"]},      # floor 5
	{"elite": "Soggy Froggy", "trash": ["Puddle Pup", "Mire Minnow"]},        # floor 6
]


## Enemy roster for a floor (1-indexed); wraps so deeper floors recycle themes.
static func enemy_roster_for_floor(floor_i: int) -> Dictionary:
	if ENEMY_ROSTER.is_empty():
		return {"elite": "Mushroom King", "trash": ["Gloopy Slime"]}
	return ENEMY_ROSTER[(maxi(1, floor_i) - 1) % ENEMY_ROSTER.size()]


## The monster lineup for a NORMAL wave: an ordered list of {name, elite, at}.
## Uses the authored def's explicit monsters when present, else fills the wave's
## monster count from the floor roster (the first one an elite on bigger waves),
## trickling in at the spawn stagger. Boss waves return [] (the boss token
## spawns separately). The battlefield kills them front-to-back; the sim's kill
## cadence (sim_enemy_killed) stays the authority.
static func wave_plan(act: int, stage: int, wave: int) -> Array:
	var plan: Array = []
	if Balance.wave_kind(act, stage, wave) != "normal":
		return plan
	var roster := enemy_roster_for_floor(Balance.floor_index(act, stage))
	var trash: Array = roster["trash"]
	var elite_name := String(roster["elite"])
	var wd := Balance.wave_def(act, stage, wave)
	if wd.has("monsters") and typeof(wd["monsters"]) == TYPE_ARRAY:
		for m in (wd["monsters"] as Array):
			var md: Dictionary = m
			var nm := String(md.get("type", trash[0]))
			plan.append({"name": nm, "elite": nm == elite_name, "at": float(md.get("at", 0.0))})
		return plan
	var count := Balance.wave_monster_count(act, stage, wave)
	var stagger := Balance.spawn_stagger()
	for i in count:
		var is_elite := i == 0 and count >= 4  # an elite leads the bigger waves
		var nm := elite_name if is_elite else String(trash[i % trash.size()])
		plan.append({"name": nm, "elite": is_elite, "at": float(i) * stagger})
	return plan


# --- Attack / projectile specs per class: ranged classes fire a projectile,
# melee classes lunge. Built to be overridden by gear/skill later. ------------
const PROJECTILE_SPECS := {
	"mage": {"ranged": true, "shape": "orb", "color_key": "cyan", "speed": 0.467, "trail": 0.45, "impact": "flash", "sparkle": true, "count": 1},  # orb drifts 3× slower than the hunter's arrow (1.4 / 3)
	"hunter": {"ranged": true, "shape": "arrow", "color_key": "ember", "speed": 1.4, "trail": 0.3, "impact": "flash", "sparkle": false, "count": 1},
	"warrior": {"ranged": false, "shape": "lunge", "color_key": "ember", "speed": 1.0, "trail": 0.0, "impact": "none", "sparkle": false, "count": 1},
	"rogue": {"ranged": false, "shape": "lunge", "color_key": "cyan", "speed": 1.2, "trail": 0.0, "impact": "none", "sparkle": false, "count": 1},
	"default": {"ranged": false, "shape": "lunge", "color_key": "ember", "speed": 1.0, "trail": 0.0, "impact": "none", "sparkle": false, "count": 1},
}


## Resolve the attack/projectile spec for a class. The two hooks let a future
## equipped weapon or an active skill cast override the base effect — the
## battlefield renderer only ever consumes the RESOLVED dict, so the visual can
## change per gear/skill without any change to the firing loop or draw class.
static func projectile_spec(class_id: String, overrides: Dictionary = {}) -> Dictionary:
	var base: Dictionary = (PROJECTILE_SPECS.get(class_id, PROJECTILE_SPECS["default"]) as Dictionary).duplicate(true)
	# HOOK 1 (future): equipped weapon → base.merge(weapon_projectile_override(class_id), true)
	# HOOK 2 (future): active skill cast → base.merge(skill_projectile_override(skill_id), true)
	if not overrides.is_empty():
		base.merge(overrides, true)
	return base


## Team Aura diagnostics (design v2 PartyStore.aura): exactly 1 tank +
## 1 healer + 2 damage dealers of DIFFERENT classes. msg explains the gap.
static func aura_check(ids: Array) -> Dictionary:
	var tanks := 0
	var heals := 0
	var dps_classes := {}
	var dps_count := 0
	for id in ids:
		var h := hero_by_id(String(id))
		if h.is_empty():
			continue
		match String(h["role"]):
			"tank":
				tanks += 1
			"healer":
				heals += 1
			_:
				dps_count += 1
				dps_classes[h["cls"]] = true
	var ok := tanks == 1 and heals == 1 and dps_count == 2 and dps_classes.size() == 2
	var msg := "+18% all stats"
	if not ok:
		if tanks == 0:
			msg = "Missing a tank"
		elif tanks > 1:
			msg = "Too many tanks"
		elif heals == 0:
			msg = "Missing a healer"
		elif heals > 1:
			msg = "Too many healers"
		elif dps_classes.size() < 2 and dps_count >= 2:
			msg = "DPS must differ"
		else:
			msg = "Need 2 damage dealers"
	return {"ok": ok, "msg": msg}


## Enemies converge from multiple edges; dist drives depth (size/fade).
const ENEMIES := [
	{"id": "boss", "name": "Mushroom King", "x": 71.0, "y": 15.0, "hp": 100.0, "elite": true, "dist": "mid"},
	{"id": "e1", "name": "Sneaky Snail", "x": 63.0, "y": 22.0, "hp": 88.0, "dist": "mid", "lunge": true, "trail_rot": 28.0},
	{"id": "e2", "name": "Gloopy Slime", "x": 79.0, "y": 12.0, "hp": 60.0, "dist": "far"},
	{"id": "e3", "name": "Gloopy Slime", "x": 83.0, "y": 30.0, "hp": 54.0, "dist": "far"},
	{"id": "e4", "name": "Gloopy Slime", "x": 88.0, "y": 53.0, "hp": 70.0, "dist": "far", "lunge": true, "trail_rot": 0.0},
	{"id": "e5", "name": "Sneaky Snail", "x": 47.0, "y": 8.0, "hp": 80.0, "dist": "far"},
	{"id": "e6", "name": "Gloopy Slime", "x": 58.0, "y": 91.0, "hp": 64.0, "dist": "mid", "lunge": true, "trail_rot": 95.0},
	{"id": "e7", "name": "Gloopy Slime", "x": 45.0, "y": 49.0, "hp": 42.0, "dist": "near"},
	{"id": "e8", "name": "Sneaky Snail", "x": 40.0, "y": 57.0, "hp": 76.0, "dist": "near", "lunge": true, "trail_rot": 35.0},
]

## Depth tiers: us = unit scale, uo = unit opacity.
const DIST := {
	"far": {"us": 0.54, "uo": 0.5},
	"mid": {"us": 0.82, "uo": 0.92},
	"near": {"us": 1.0, "uo": 1.0},
}

## Environment props (iso dressing). w/h in px. Trees and rocks are sprite
## placeholders the user will replace with pixellab.ai art later.
const PROPS := [
	{"id": "p1", "x": 46.0, "y": 44.0, "w": 50.0, "h": 64.0, "kind": "pillar", "label": "pillar"},
	{"id": "p2", "x": 62.0, "y": 60.0, "w": 48.0, "h": 60.0, "kind": "pillar", "label": "pillar"},
	{"id": "p3", "x": 78.0, "y": 38.0, "w": 40.0, "h": 48.0, "kind": "brazier", "label": "brazier"},
	{"id": "p4", "x": 70.0, "y": 70.0, "w": 64.0, "h": 44.0, "kind": "rubble", "label": "tomb"},
	{"id": "t1", "x": 12.0, "y": 30.0, "w": 58.0, "h": 92.0, "kind": "tree", "label": "tree"},
	{"id": "t2", "x": 88.0, "y": 78.0, "w": 52.0, "h": 84.0, "kind": "tree", "label": "tree"},
	{"id": "t3", "x": 34.0, "y": 16.0, "w": 46.0, "h": 74.0, "kind": "tree", "label": "tree"},
	{"id": "r1", "x": 54.0, "y": 82.0, "w": 44.0, "h": 30.0, "kind": "rock", "label": "rock"},
	{"id": "r2", "x": 22.0, "y": 52.0, "w": 36.0, "h": 26.0, "kind": "rock", "label": "rock"},
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
	["Pyra", "looted", "Bonk Hammer", "epic"],
	["Party", "gained", "+240 Coins", "common"],
	["Mimsy", "looted", "Starweave Cap", "rare"],
	["Bonk", "looted", "Acorn Pauldron", "uncommon"],
	["Party", "found", "Charm Shard ×2", "epic"],
	["Lulu", "looted", "Moonpetal Charm", "rare"],
	["Party", "gained", "+1,120 XP", "common"],
	["Pyra", "looted", "Starglass Ring", "legendary"],
	["Party", "gained", "+180 Coins", "common"],
	["Mimsy", "looted", "Doodled Grimoire", "common"],
]

## Stage names rotate as the party advances.
const STAGE_NAMES := [
	"The Glimmer Grove", "Buttercup Pass", "Starfall Slopes",
	"The Snoozy Meadow", "Mushroom Hollow", "Firefly Garden",
]

# =========================================================================
# CAMP — buildings, scene dressing, modals (camp.jsx)
# =========================================================================

## Building hotspots. x/y are scene percentages; w/h px.
const BUILDINGS := [
	{
		"id": "altar", "name": "Wishing Well", "sub": "Make a wish · meet new pals",
		"x": 50.0, "y": 27.0, "w": 340.0, "h": 300.0, "hot": "Q", "featured": true,
		"sprite": "340×300 · wishing well", "tip_type": "Gacha · Featured banner active",
		"flavor": "Toss in a stardrop and a new friend might splash right out!",
		"badge": "NEW BANNER",
	},
	{
		"id": "board", "name": "Bulletin Board", "sub": "Quests · Rankings · Daily",
		"x": 17.0, "y": 60.0, "w": 240.0, "h": 220.0, "hot": "E", "featured": false,
		"sprite": "240×220 · board", "tip_type": "Town bulletin",
		"flavor": "Sticky notes, stickers, and today's special adventure.",
		"badge": "3 NEW",
	},
	{
		"id": "forge", "name": "Tinker Shop", "sub": "Craft · Upgrade · Recycle",
		"x": 81.0, "y": 46.0, "w": 280.0, "h": 240.0, "hot": "R", "featured": false,
		"sprite": "280×240 · tinker shop", "tip_type": "Tinkering",
		"flavor": "Hammer, glue, and a little sparkle — good as new, but better.",
		"badge": "",
	},
	{
		"id": "food", "name": "Snack Shack", "sub": "Cook party-buff snacks",
		"x": 34.0, "y": 74.0, "w": 230.0, "h": 200.0, "hot": "F", "featured": false,
		"sprite": "230×200 · snack shack", "tip_type": "Cooking · Buffs",
		"flavor": "A warm snack before bedtime adventures. Buffs the whole party!",
		"badge": "",
	},
	{
		"id": "arena", "name": "Stampede Gate", "sub": "Star Stampede · solo runs",
		"x": 69.0, "y": 82.0, "w": 250.0, "h": 190.0, "hot": "T", "featured": false,
		"sprite": "250×190 · stampede gate", "tip_type": "Survival · Bullet-heaven",
		"flavor": "A shimmering gate to the starlit meadow. Bring your best backpack!",
		"badge": "SOLO MODE", "screen": "survival",
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
## (5th path → the Stampede Gate.)
const WALKS := [
	{"len": 690.0, "rot": 180.0}, {"len": 380.0, "rot": -110.0},
	{"len": 465.0, "rot": -19.0}, {"len": 445.0, "rot": 161.0},
	{"len": 320.0, "rot": 48.0},
]

## Town crier ribbon entries: [lit, text_bbcode-ish parts kept simple].
const CRIER := [
	{"lit": true, "text": "Daily reset in ", "b": "06:12:40", "suffix": ""},
	{"lit": false, "text": "Starfall Friends banner — ", "b": "5d left", "suffix": "", "b_ember": true},
	{"lit": true, "text": "Guild boss ", "b": "Grumpy Gus", "suffix": " now open"},
	{"lit": false, "text": "Friend ", "b": "Doodle", "suffix": " sent 5 energy"},
]

## Daily quests: title, progress, goal, reward (done derives from p >= g).
const QUESTS := [
	{"t": "Clear 3 adventure stages", "p": 3.0, "g": 3.0, "rw": "240 Coins · 40 XP"},
	{"t": "Make a wish at the well", "p": 1.0, "g": 1.0, "rw": "1 Stardrop"},
	{"t": "Cook a party snack", "p": 0.0, "g": 1.0, "rw": "Hearth Token"},
	{"t": "Deal 5,000,000 bonk damage", "p": 3.1, "g": 5.0, "rw": "120 Coins · Charm Shard"},
	{"t": "Recycle 5 items at the Tinker Shop", "p": 2.0, "g": 5.0, "rw": "Tin Bits ×3"},
]

## Notice-board mini leaderboard.
const BOARD_RANKS := [
	{"r": 1, "n": "Marshmallow", "lv": 88, "p": "412.6M", "me": false},
	{"r": 2, "n": "Pip (You)", "lv": 47, "p": "188.4M", "me": true},
	{"r": 3, "n": "Doodle", "lv": 52, "p": "176.0M", "me": false},
	{"r": 4, "n": "Waffles", "lv": 61, "p": "162.9M", "me": false},
	{"r": 5, "n": "Luna Bee", "lv": 44, "p": "140.2M", "me": false},
]

## Kitchen recipes.
const RECIPES := [
	{"n": "Honeyroot Stew", "r": "epic", "b": "+12% party ATK · 30 min", "have": true},
	{"n": "Berry Glaze Roast", "r": "rare", "b": "+8% Crit · 30 min", "have": true},
	{"n": "Frostberry Pie", "r": "rare", "b": "+15% Mana regen", "have": false},
	{"n": "Snuggle Broth", "r": "uncommon", "b": "+10% HP · 30 min", "have": true},
	{"n": "Butter Bun", "r": "common", "b": "+5% XP gain", "have": true},
	{"n": "Moonbeam Tea", "r": "legendary", "b": "+20% all stats · 15 min", "have": false},
]

# =========================================================================
# GACHA — pool + rates (camp.jsx)
# =========================================================================

const RARITY_RANK := {"common": 0, "uncommon": 1, "rare": 2, "epic": 3, "legendary": 4, "mythic": 5}

const HEROES_POOL := [
	{"n": "Pyra", "r": "legendary", "role": "5★ DPS · Emberpuff"},
	{"n": "Brambles", "r": "epic", "role": "4★ Tank · Thornhugger"},
	{"n": "Sunny", "r": "epic", "role": "4★ Healer · Dawnsprout"},
	{"n": "Chomps", "r": "rare", "role": "3★ DPS · Nibbler"},
	{"n": "Glow", "r": "rare", "role": "3★ Support · Firefly"},
	{"n": "Pebble", "r": "common", "role": "Shard · Rockling"},
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
	{"slot": "Helm", "r": "epic", "name": "Cap of the Meadow", "ilvl": 72, "stats": [["Armour", "+248"], ["Sparkle", "+42"], ["Sparkle Damage", "+12%"]]},
	{"slot": "Amulet", "r": "legendary", "name": "Starglass Pendant", "ilvl": 80, "stats": [["All Attributes", "+30"], ["Toasty Damage", "+24%"], ["Crit Multi", "+35%"]]},
	{"slot": "Body", "r": "epic", "name": "Snugwrought Plate", "ilvl": 75, "stats": [["Armour", "+612"], ["Maximum Life", "+184"], ["Toasty Resist", "+38%"]]},
	{"slot": "Gloves", "r": "rare", "name": "Berryweave Grips", "ilvl": 68, "stats": [["Attack Speed", "+9%"], ["Nimbleness", "+24"]]},
	{"slot": "Boots", "r": "rare", "name": "Treads of Fluff", "ilvl": 66, "stats": [["Movement Speed", "+18%"], ["Maximum Life", "+72"]]},
]
const GEAR_R := [
	{"slot": "Main Hand", "r": "legendary", "name": "Bonk Hammer Maul", "ilvl": 82, "stats": [["Bonk DMG", "470–664"], ["Muscle", "+72"], ["Crit Chance", "+8.5%"]]},
	{"slot": "Off Hand", "r": "epic", "name": "Marshmallow Bulwark", "ilvl": 74, "stats": [["Block", "+32%"], ["Armour", "+288"], ["Life", "+96"]]},
	{"slot": "Ring I", "r": "rare", "name": "Moonbeam Band", "ilvl": 64, "stats": [["Frosty Resist", "+28%"], ["Mana", "+48"]]},
	{"slot": "Ring II", "r": "epic", "name": "Berry Loop", "ilvl": 70, "stats": [["Item Rarity", "+14%"], ["Coin Find", "+22%"]]},
	{"slot": "Belt", "r": "uncommon", "name": "Honey Girdle", "ilvl": 60, "stats": [["Maximum Life", "+64"], ["Stun Recovery", "+12%"]]},
]

## The 5 main attributes: key, name, value, color, description.
const MAIN_STATS := [
	{"k": "STR", "name": "Muscle", "v": 642, "c": Color("f25c4c"), "d": "Bonk damage & armour."},
	{"k": "DEX", "name": "Nimbleness", "v": 388, "c": Color("2bab74"), "d": "Attack speed, accuracy & evasion."},
	{"k": "INT", "name": "Sparkle", "v": 514, "c": Color("3d95e8"), "d": "Sparkle damage & maximum mana."},
	{"k": "VIT", "name": "Snuggle", "v": 470, "c": Color("d98d16"), "d": "Maximum life & recovery."},
	{"k": "LCK", "name": "Luck", "v": 196, "c": Color("b46ef5"), "d": "Crit chance, item rarity & coins."},
]

## Detailed/derived stats: [label, value]. "−"-prefixed values render red.
const DETAILED := [
	["Attack DPS", "4.82M"], ["Spell DPS", "3.10M"], ["Crit Chance", "42.4%"], ["Crit Multiplier", "385%"],
	["Attack Speed", "1.86/s"], ["Cast Speed", "1.42/s"], ["Accuracy", "94%"], ["Life Regen", "2,140/s"],
	["Maximum Mana", "9,240"], ["Mana Regen", "880/s"], ["Evasion", "6,210"], ["Block Chance", "32%"],
	["Movement Speed", "+18%"], ["Toasty Resist", "+58%"], ["Frosty Resist", "+44%"], ["Zappy Resist", "+39%"],
	["Gloomy Resist", "−12%"], ["Item Rarity", "+36%"], ["Coin Find", "+41%"], ["XP Gain", "+12%"],
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
		{"n": "Twinkle Shard Blade", "r": "epic", "t": "Sword · iLvl 71", "s": [["Bonk DMG", "388–520"], ["Toasty Damage", "+18%"]]},
		{"n": "Honeywax Seal", "r": "epic", "t": "Amulet · iLvl 69", "s": [["Maximum Life", "+120"], ["Cast Speed", "+8%"]]},
		{"n": "Starglass Band", "r": "legendary", "t": "Ring · iLvl 78", "s": [["Toasty Damage", "+22%"], ["Crit Multi", "+28%"]]},
		{"n": "Starweave Cap", "r": "rare", "t": "Helm · iLvl 64", "s": [["Sparkle", "+28"], ["Mana", "+60"]]},
		{"n": "Puddleplate Greaves", "r": "rare", "t": "Boots · iLvl 62", "s": [["Armour", "+180"], ["Move Speed", "+12%"]]},
		{"n": "Cloudwoven Wrap", "r": "rare", "t": "Chest · iLvl 60", "s": [["Evasion", "+240"], ["Frosty Resist", "+20%"]]},
		{"n": "Snailhide Belt", "r": "rare", "t": "Belt · iLvl 58", "s": [["Life", "+88"], ["Stun Recovery", "+15%"]]},
		{"n": "Tinplate Gauntlets", "r": "uncommon", "t": "Gloves · iLvl 55", "s": [["Muscle", "+18"], ["Armour", "+96"]]},
		{"n": "Acorn Pauldron", "r": "uncommon", "t": "Shoulder · iLvl 52", "s": [["Armour", "+120"]]},
		{"n": "Marshmallow Club", "r": "common", "t": "Mace · iLvl 41", "s": [["Bonk DMG", "120–180"]]},
		{"n": "Doodled Grimoire", "r": "common", "t": "Offhand · iLvl 38", "s": [["Sparkle Damage", "+6%"]]},
		{"n": "Sigil of Sunbeams", "r": "epic", "t": "Ring · iLvl 66", "s": [["Ignite Chance", "+12%"], ["Toasty Resist", "+18%"]]},
	],
	"consumables": [
		{"n": "Big Berry Fizz", "r": "rare", "t": "Flask", "q": 12, "s": [["Restores", "45% Life"]]},
		{"n": "Mana Lemonade", "r": "uncommon", "t": "Flask", "q": 8, "s": [["Restores", "60% Mana"]]},
		{"n": "Honeyroot Stew", "r": "epic", "t": "Meal", "q": 3, "s": [["Party ATK", "+12% · 30m"]]},
		{"n": "Pebbleskin Tonic", "r": "rare", "t": "Tonic", "q": 5, "s": [["Armour", "+25% · 10m"]]},
		{"n": "Scroll of Homecoming", "r": "common", "t": "Scroll", "q": 14, "s": [["Effect", "Skip back to the meadow"]]},
		{"n": "Butter Bun", "r": "common", "t": "Meal", "q": 9, "s": [["XP Gain", "+5% · 30m"]]},
	],
	"materials": [
		{"n": "Tin Bits", "r": "common", "t": "Tinkering", "q": 46},
		{"n": "Sparkle Dust", "r": "rare", "t": "Tinkering", "q": 38},
		{"n": "Charm Shard", "r": "epic", "t": "Charm-craft", "q": 11},
		{"n": "Ribbon Thread", "r": "uncommon", "t": "Tailoring", "q": 23},
		{"n": "Moon Syrup", "r": "rare", "t": "Snack-craft", "q": 17},
		{"n": "Star Core", "r": "legendary", "t": "Tinkering · rare drop", "q": 2},
		{"n": "Cookie Crumbs", "r": "common", "t": "Snack-craft", "q": 64},
	],
	"quest": [
		{"n": "Wobbly Old Key", "r": "epic", "t": "Quest · The Glimmer Grove", "s": [["Opens", "Glimmer Gate 4-10"]]},
		{"n": "Meadow Census Ledger", "r": "rare", "t": "Quest · BinkBonk Meadow", "s": [["Deliver to", "Bulletin Board"]]},
		{"n": "Pyra's Locket", "r": "legendary", "t": "Quest · Personal", "s": [["Hint", "She won't say where she found it."]]},
	],
}

const INV_TABS := [["equipment", "Equipment"], ["consumables", "Consumables"], ["materials", "Materials"], ["quest", "Quest"]]
const INV_CELLS := 30

# =========================================================================
# PETS + RELICS (petsrelics.jsx)
# =========================================================================

const PETS := [
	{"n": "Toasty", "r": "legendary", "owned": true, "active": true, "eff": "+8% party Toasty Damage", "role": "Dragonpuff"},
	{"n": "Flappy", "r": "epic", "owned": true, "active": false, "eff": "+6% Life Nibble", "role": "Batling"},
	{"n": "Mittens", "r": "epic", "owned": true, "active": false, "eff": "+10% Crit vs marked", "role": "Kitty"},
	{"n": "Clicky", "r": "rare", "owned": true, "active": false, "eff": "+12% Armour", "role": "Beetle Buddy"},
	{"n": "Glimmer", "r": "rare", "owned": true, "active": false, "eff": "+8% Mana regen", "role": "Wisp"},
	{"n": "Waggles", "r": "uncommon", "owned": true, "active": false, "eff": "+5% Coin Find", "role": "Puppy"},
	{"n": "Twinkle", "r": "uncommon", "owned": true, "active": false, "eff": "+4% Rarity", "role": "Sprite"},
	{"n": "Ribbit", "r": "common", "owned": true, "active": false, "eff": "+10 Max Life", "role": "Toad"},
	{"n": "Hootie", "r": "legendary", "owned": false, "active": false, "eff": "Sniffs out rare loot", "role": "Owl", "unlock_summons": 12},
	{"n": "Wiggles", "r": "epic", "owned": false, "active": false, "eff": "+8% XP gain", "role": "Bookworm", "unlock_summons": 6},
	{"n": "Foxtrot", "r": "rare", "owned": false, "active": false, "eff": "+6% move speed", "role": "Fox", "unlock_summons": 3},
	{"n": "Impy", "r": "epic", "owned": false, "active": false, "eff": "Pranks foes on hit", "role": "Imp", "unlock_summons": 9},
]


## ACQUISITION LOOPS — both derive from server-authoritative state, so the
## mock and live games agree with zero extra save schema:
##   pets   → unlocked by total gacha summons (roster_extra.size())
##   relics → the empty slots fill at max_stage milestones

## Pet [param i] is owned when the design says so, or once enough heroes have
## been summoned (the companion follows a newcomer into camp).
static func pet_owned(i: int) -> bool:
	var pet: Dictionary = PETS[clampi(i, 0, PETS.size() - 1)]
	if bool(pet["owned"]):
		return true
	# Gated on lifetime summons (the roster is gone — gacha rolls gear now).
	return GameState.total_summons >= int(pet.get("unlock_summons", 1 << 30))


static func pet_unlock_need(i: int) -> int:
	return int((PETS[clampi(i, 0, PETS.size() - 1)] as Dictionary).get("unlock_summons", 0))


## Stage-milestone relics that materialize into the empty equipped slots.
const RELIC_STAGE_UNLOCKS := [
	{"idx": 4, "at": 450, "n": "Firefly Lantern", "r": "legendary",
		"eff": "+10% Coin Find · +6% Item Rarity"},
	{"idx": 5, "at": 520, "n": "Moon Idol", "r": "epic",
		"eff": "+9% All Damage"},
]


## RELICS with every earned stage-unlock filled in (max_stage milestones).
static func live_relics() -> Array:
	var out: Array = RELICS.duplicate(true)
	for ru_v in RELIC_STAGE_UNLOCKS:
		var ru: Dictionary = ru_v
		if GameState.max_stage >= int(ru["at"]):
			out[int(ru["idx"])] = {"n": String(ru["n"]), "r": String(ru["r"]),
				"eff": String(ru["eff"]), "owned": true, "empty": false}
	return out

const RELICS := [
	{"n": "Sunny Crown", "r": "legendary", "eff": "+12% All Damage · +60 Max Life", "owned": true, "empty": false},
	{"n": "Star Sigil", "r": "epic", "eff": "+18% Crit Multiplier", "owned": true, "empty": false},
	{"n": "Honey Drop", "r": "epic", "eff": "+22% Toasty Damage", "owned": true, "empty": false},
	{"n": "Ribbon of Tides", "r": "rare", "eff": "+30 Mana · +8% Cast Speed", "owned": true, "empty": false},
	{"n": "", "r": "common", "eff": "", "owned": false, "empty": true},
	{"n": "", "r": "common", "eff": "", "owned": false, "empty": true},
]

const RELIC_COLL := [
	{"n": "Firefly Lantern", "r": "legendary"}, {"n": "Moon Idol", "r": "epic"},
	{"n": "Tin Crown", "r": "rare"}, {"n": "Clover Charm", "r": "uncommon"},
	{"n": "Fizzy Vial", "r": "common"}, {"n": "Jingle Bell", "r": "rare"},
	{"n": "Sun Knot", "r": "epic"}, {"n": "Lucky Die", "r": "uncommon"},
]

# =========================================================================
# LEADERBOARD (leaderboard.jsx)
# =========================================================================

const SEASON := {
	"num": "III", "name": "Starfall", "ends": "12d 04h 38m",
	"you": {"tier": "Honey Knight", "next": "Star Sovereign", "pct": "Top 0.2%", "to_next": 1, "prog": 88},
}

const TIERS := [
	{"name": "Star Sovereign", "rar": "legendary", "range": "Top 10", "reward": "Mythic Gift Box · Title", "you": false},
	{"name": "Honey Knight", "rar": "epic", "range": "Top 50", "reward": "Epic Gift Box · 1,200 Coins", "you": true},
	{"name": "Minty Mate", "rar": "rare", "range": "Top 500", "reward": "Rare Gift Box · 600 Coins", "you": false},
	{"name": "Cozy Cub", "rar": "uncommon", "range": "Top 5,000", "reward": "Uncommon Gift Box", "you": false},
	{"name": "Sleepy Snail", "rar": "common", "range": "All Adventurers", "reward": "Participation Gift Box", "you": false},
]

const CATS := [
	{"key": "power", "label": "Total Power", "hot": "Q", "sub": "Total Power"},
	{"key": "stage", "label": "Deepest Stage", "hot": "W", "sub": "Deepest Stage"},
	{"key": "boss", "label": "Boss Damage", "hot": "E", "sub": "Boss Damage"},
	{"key": "weekly", "label": "Weekly Climb", "hot": "R", "sub": "Ranks Climbed"},
	{"key": "stampede", "label": "Stampede", "hot": "T", "sub": "Best Run Score"},
]

const SCOPES := [["global", "Global"], ["friends", "Friends"], ["guild", "Guild"]]

const GUILDS := {
	"ASH": {"name": "Waffle Squad", "c": Color("e8843a")},
	"VIG": {"name": "Moon Beams", "c": Color("cdd2d6")},
	"HEX": {"name": "Berry Bunch", "c": Color("a661d6")},
	"GLD": {"name": "Golden Geese", "c": Color("d3ad62")},
	"TMB": {"name": "Snug Bugs", "c": Color("6fcf6a")},
}

## One dataset; each category sorts the same adventurers differently.
## stage is [act, sub]; power/boss in millions; stampede = best Star Stampede run.
const PLAYERS := [
	{"name": "Marshmallow", "guild": "VIG", "lv": 88, "tier": "Star Sovereign", "power": 412.6, "stage": [9, 12], "boss": 88.4, "weekly": 142, "stampede": 48210, "trend": 0, "you": false, "friend": false},
	{"name": "Sprinkles", "guild": "HEX", "lv": 84, "tier": "Star Sovereign", "power": 388.0, "stage": [9, 4], "boss": 79.2, "weekly": 96, "stampede": 36400, "trend": 1, "you": false, "friend": true},
	{"name": "Waffles", "guild": "ASH", "lv": 81, "tier": "Star Sovereign", "power": 362.9, "stage": [8, 40], "boss": 91.0, "weekly": 210, "stampede": 41050, "trend": 2, "you": false, "friend": false},
	{"name": "Doodle", "guild": "VIG", "lv": 79, "tier": "Star Sovereign", "power": 344.2, "stage": [8, 38], "boss": 71.5, "weekly": 54, "stampede": 31220, "trend": -1, "you": false, "friend": true},
	{"name": "Luna Bee", "guild": "GLD", "lv": 77, "tier": "Star Sovereign", "power": 318.7, "stage": [8, 44], "boss": 66.1, "weekly": 118, "stampede": 27800, "trend": 1, "you": false, "friend": false},
	{"name": "Biscuit", "guild": "TMB", "lv": 74, "tier": "Star Sovereign", "power": 289.4, "stage": [8, 22], "boss": 61.8, "weekly": 33, "stampede": 9400, "trend": 0, "you": false, "friend": false},
	{"name": "Gumdrop", "guild": "ASH", "lv": 72, "tier": "Star Sovereign", "power": 265.0, "stage": [8, 15], "boss": 58.2, "weekly": 175, "stampede": 22150, "trend": 1, "you": false, "friend": false},
	{"name": "Hoppy", "guild": "HEX", "lv": 70, "tier": "Star Sovereign", "power": 243.1, "stage": [8, 8], "boss": 54.0, "weekly": 60, "stampede": 18700, "trend": -2, "you": false, "friend": false},
	{"name": "Toffee", "guild": "GLD", "lv": 67, "tier": "Star Sovereign", "power": 226.8, "stage": [7, 44], "boss": 49.7, "weekly": 88, "stampede": 15300, "trend": 1, "you": false, "friend": true},
	{"name": "Mochi", "guild": "VIG", "lv": 64, "tier": "Star Sovereign", "power": 204.5, "stage": [7, 36], "boss": 45.2, "weekly": 41, "stampede": 7900, "trend": 0, "you": false, "friend": false},
	{"name": "Pip", "guild": "ASH", "lv": 47, "tier": "Honey Knight", "power": 188.4, "stage": [7, 40], "boss": 96.8, "weekly": 224, "stampede": 0, "trend": 3, "you": true, "friend": true},
	{"name": "Dumpling", "guild": "TMB", "lv": 61, "tier": "Honey Knight", "power": 176.0, "stage": [7, 18], "boss": 37.1, "weekly": 22, "stampede": 5200, "trend": -1, "you": false, "friend": false},
	{"name": "Acorn", "guild": "ASH", "lv": 58, "tier": "Honey Knight", "power": 162.9, "stage": [7, 10], "boss": 33.6, "weekly": 150, "stampede": 12300, "trend": 1, "you": false, "friend": true},
	{"name": "Pickle", "guild": "HEX", "lv": 55, "tier": "Honey Knight", "power": 150.2, "stage": [6, 40], "boss": 30.0, "weekly": 18, "stampede": 3100, "trend": 0, "you": false, "friend": false},
	{"name": "Gingersnap", "guild": "GLD", "lv": 52, "tier": "Minty Mate", "power": 138.4, "stage": [6, 33], "boss": 27.4, "weekly": 73, "stampede": 6800, "trend": 1, "you": false, "friend": false},
	{"name": "Cocoa", "guild": "TMB", "lv": 49, "tier": "Minty Mate", "power": 126.1, "stage": [6, 25], "boss": 24.2, "weekly": 29, "stampede": 2400, "trend": -1, "you": false, "friend": true},
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
		"stampede":
			return float(p.get("stampede", 0))
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
		"stampede":
			var v := int(p.get("stampede", 0))
			return Style.group_int(v) if v > 0 else "—"
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
	"STR": ["+10 Muscle", "+8 Bonk Damage", "+12 Armour", "+6% Bonk Damage"],
	"DEX": ["+10 Nimbleness", "+6% Attack Speed", "+8 Accuracy", "+4% Evasion"],
	"INT": ["+10 Sparkle", "+12 Maximum Mana", "+6% Sparkle Damage", "+5% Cast Speed"],
	"VIT": ["+14 Maximum Life", "+8 Life Regen", "+10 Armour", "+4% Life Recovery"],
	"LUCK": ["+8 Luck", "+4% Item Rarity", "+3% Crit Chance", "+5% Coin Find"],
}

# Unique NOTABLE talents (PoE-style): named nodes with strong, distinct
# effects. The first parseable "+X% Y / +X Y" clauses feed StatBlock (real
# stats); trailing prose is flavor the parser ignores. ~10 per arm so the
# tree reads as a web of distinct skills (assigned without repetition).
const NOTABLE := {
	"Might": [
		["Reaver's Wrath", "+24% Bonk Damage · +30 Muscle"],
		["Ironhide", "+18% Armour · +40 Maximum Life"],
		["Bonecrusher", "+20% Bonk Damage · +8% Stun"],
		["Titan's Grip", "+35 Muscle · +12% Bonk Damage"],
		["Bloodhunger", "+15% Bonk Damage · Leech 4% of damage as Life"],
		["Warbringer", "+10% Attack Speed · +18% Bonk Damage"],
		["Crushing Blows", "+25% Crit Multiplier · +6% Bonk Damage"],
		["Unflinching", "+60 Maximum Life · Cannot be knocked back"],
		["Berserker's Call", "+22% Bonk Damage · stronger below half Life"],
		["Mountainous", "+24% Armour · +20 Muscle"],
	],
	"Precision": [
		["Deadeye", "+12% Crit Multiplier · +20 Accuracy"],
		["Fleetfoot", "+10% Attack Speed · +8% Evasion"],
		["Hawkeye", "+18% Accuracy · +6% Crit Chance"],
		["Phantom Step", "+12% Evasion · +6% Movement Speed"],
		["Lacerate", "+15 Nimbleness · +12% Attack Speed · Bleed on hit"],
		["Twinstrike", "+12% Attack Speed · chance to strike twice"],
		["Vital Aim", "+8% Crit Chance · +20% damage to full-life foes"],
		["Windrunner", "+14% Movement Speed · +8% Attack Speed"],
		["Pinpoint", "+25% Crit Multiplier · +15 Accuracy"],
		["Evasive Dance", "+16% Evasion · +20 Nimbleness"],
	],
	"Arcana": [
		["Manaweaver", "+30 Maximum Mana · +12% Sparkle Damage"],
		["Hexbloom", "+20 Sparkle · Curses spread to nearby foes"],
		["Spellfire", "+18% Sparkle Damage · +6% Cast Speed"],
		["Mind Over Matter", "+24 Sparkle · pay 20% of damage from Mana"],
		["Arcane Surge", "+25% Sparkle Damage after spending Mana"],
		["Frostbite", "+18% Cold Damage · +8% Freeze chance"],
		["Soul Siphon", "+12% Sparkle Damage · cursed kills restore Mana"],
		["Runescarred", "+24 Sparkle · +10% Sparkle Damage"],
		["Overcharge", "+30% Sparkle Damage · -10% Cast Speed"],
		["Whispering Doom", "+15 Sparkle · apply an additional Curse"],
	],
	"Endurance": [
		["Bulwark", "+60 Maximum Life · +14% Block"],
		["Last Stand", "+40% Life Recovery below 35% Life"],
		["Stonewall", "+20% Armour · +10% Block"],
		["Sanguine", "+80 Maximum Life · +6% Life Regen"],
		["Indomitable", "+12% Block · Cannot be Frozen"],
		["Wellspring", "+20% Life Regen · +40 Maximum Life"],
		["Thick Skin", "+24% Armour · +30 Snuggle"],
		["Second Wind", "+50 Maximum Life · recover Life on a killing blow"],
		["Bastion", "+18% Block · +50 Maximum Life"],
		["Lifeblood", "+30% Life Recovery · +20 Snuggle"],
	],
	"Fortune": [
		["Goldtongue", "+18% Coin Find · +6% Item Rarity"],
		["Fated", "+8% Crit Chance · +12% Item Rarity"],
		["Greedy", "+24% Coin Find · +10 Luck"],
		["Treasurehunter", "+14% Item Rarity · +8% Coin Find"],
		["Lucky Strike", "+10% Crit Chance · +8 Luck"],
		["Windfall", "+10% Item Rarity · slain foes drop more"],
		["Silver Tongue", "+30% Coin Find · -5% Item Rarity"],
		["Charmed", "+12% Item Rarity · +6% Crit Multiplier"],
		["Prospector", "+20% Coin Find · +5% XP Gain"],
		["Cardsharp", "+14% Crit Chance · +10% Item Rarity"],
	],
	"Ruin": [
		["Cinderbrand", "+18% Toasty Damage · Ignites deal +40% damage"],
		["Scorched Earth", "+12% Toasty Damage · +25% Burn duration"],
		["Immolate", "+20% Toasty Damage · Ignite on Crit"],
		["Pyroclasm", "+28% Toasty Damage · -8% Maximum Life"],
		["Wildfire", "+15% Toasty Damage · Ignites spread to nearby foes"],
		["Emberheart", "+15% Toasty Damage · recover Life when igniting"],
		["Conflagration", "+10% Toasty Damage · +30% Burn damage"],
		["Ashbringer", "+22% Toasty Damage · +20 Muscle"],
		["Searing Touch", "+18% Toasty Damage · +6% Cast Speed"],
		["Funeral Pyre", "+12% Toasty Damage · burning kills heal you"],
	],
}

# KEYSTONES: game-changing nodes with a real tradeoff. 2-3 per arm; one is
# placed at each arm's tip (chosen without repetition).
const KEYSTONE := {
	"Might": [
		["Avatar of Fury", "Cannot be Stunned. +20% Bonk Damage, but -30% Maximum Life."],
		["Glass Cannon", "+40% Bonk Damage, but -25% Armour."],
		["Endless Onslaught", "+2% Bonk Damage per nearby foe (no life on the wall)."],
	],
	"Precision": [
		["Perfect Aim", "Critical strikes never miss and gain +50% Crit Multiplier."],
		["Resolute Technique", "Your hits can't be evaded — but you can never Crit."],
		["Far Shot", "+35% damage to distant foes, -20% to adjacent."],
	],
	"Arcana": [
		["Eldritch Battery", "Spend Life as Mana when Mana is depleted."],
		["Blood Magic", "Skills cost Life instead of Mana. +40 Maximum Life."],
		["Archmage", "+1% Sparkle Damage per 10 unreserved Mana."],
	],
	"Endurance": [
		["Unbreakable", "Armour also mitigates elemental damage."],
		["Pain Attunement", "+35% damage while below half Life."],
		["Eternal Vigil", "Cannot drop below 1 Life for 4s (60s cooldown)."],
	],
	"Fortune": [
		["Hand of Fate", "Doubles rarity bonuses, halves item quantity."],
		["Gambler's Ruin", "Crits deal +100%, but non-crits deal -30%."],
		["Midas Touch", "+60% Coin Find, but you cannot pick up items."],
	],
	"Ruin": [
		["Pyre Heart", "Killing a burning enemy spreads the flames."],
		["Chaos Incarnate", "All your damage is converted to Fire."],
		["Rite of Ruin", "+50% Toasty Damage, but you also Burn each tick."],
	],
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
## Fisher-Yates shuffle using the deterministic tree RNG (stable layout).
static func _shuffled(arr: Array, rng) -> Array:
	for i in range(arr.size() - 1, 0, -1):
		var j := int(rng.next() * float(i + 1))
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
	return arr


static func build_tree() -> Dictionary:
	var rng := Mulberry.new(TREE_SEED)
	var nodes: Array = []
	var edges: Array = []

	var add := func(x: float, y: float, type: String, ai: int, label: String, eff: String) -> int:
		var nid := nodes.size()
		nodes.append({"id": nid, "x": x, "y": y, "type": type, "ai": ai, "label": label, "eff": eff})
		return nid

	var center: int = add.call(0.0, 0.0, "start", -1, "The Snug Heart", "The seat of your power. Allocate outward.")

	# Per-arm shuffled pools so every NOTABLE / KEYSTONE in the tree is UNIQUE
	# (PoE-style: no two nodes share a name). Pop as we place; if a pool runs
	# dry the builder falls back to a generic minor.
	var notable_pools: Dictionary = {}
	var keystone_pools: Dictionary = {}
	for arm_def in ARMS:
		var an := String(arm_def["name"])
		notable_pools[an] = _shuffled(NOTABLE[an].duplicate(), rng)
		keystone_pools[an] = _shuffled(KEYSTONE[an].duplicate(), rng)

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
			# Denser notable placement (odd steps from the 2nd on) so the tree
			# is full of distinct skills, drawn without repetition per arm.
			var arm_name: String = arm["name"]
			var pool: Array = notable_pools[arm_name]
			var notable := (not last) and s >= 2 and not pool.is_empty()
			var type := "minor"
			var label: String = String(arm["stat"]) + " Node"
			var eff: String = rng.pick(MINOR[arm["stat"]])
			if last and depth == 0:
				type = "keystone"
				var kpool: Array = keystone_pools[arm_name]
				var k: Array = kpool.pop_back() if not kpool.is_empty() else KEYSTONE[arm_name][0]
				label = k[0]
				eff = k[1]
			elif notable:
				type = "notable"
				var nb: Array = pool.pop_back()
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


# =========================================================================
# CLASSES — first-login hero selection (PoE-style character choice)
# =========================================================================

## The four starting heroes. Descriptions are written for the selection
## screen's narrator panel (Path of Exile character-select tone).
const CLASSES := [
	{
		"id": "warrior", "name": "Warrior", "title": "the Big-Hearted",
		"attrs": "STR · VIT", "sprite": "200×320\nwarrior",
		"bonus": {"strength": 60, "vitality": 30},
		"tagline": "A hug that hits back.",
		"desc": "Raised on porridge and pillow forts, the Warrior walks in front so nobody else has to. Baddies bounce off that big shield, then get a friendly BONK to think about. Steady, snuggly, and completely unbudgeable.",
		"stats": [["Role", "Melee · Bruiser"], ["Favors", "Muscle, Snuggle"], ["Weapon", "Big Bonk Hammers"]],
	},
	{
		"id": "mage", "name": "Mage", "title": "the Plucky",
		"attrs": "INT", "sprite": "200×320\nmage",
		"bonus": {"intelligence": 70, "maximum_mana": 800},
		"tagline": "Sparkles solve everything.",
		"desc": "A certified Sparkmage with a wand full of fizzy starlight. Every bolt pops like a tiny firework and smells faintly of toasted marshmallow. Keep the mana lemonade coming and stand back — it gets glittery.",
		"stats": [["Role", "Ranged · Burst"], ["Favors", "Sparkle"], ["Weapon", "Star Wands & Storybooks"]],
	},
	{
		"id": "hunter", "name": "Hunter", "title": "the Keen-Eyed",
		"attrs": "DEX", "sprite": "200×320\nhunter",
		"bonus": {"dexterity": 60, "attack_speed_flat": 0},
		"tagline": "Never misses snack time.",
		"desc": "Grew up in the berry brambles playing hide-and-seek with the fireflies. Arrows tipped with acorns arrive right on schedule, every time. Nothing in the meadow outruns that aim — some things just nap mid-chase.",
		"stats": [["Role", "Ranged · Sustained"], ["Favors", "Nimbleness"], ["Weapon", "Twig Bows & Acorn Arrows"]],
	},
	{
		"id": "rogue", "name": "Rogue", "title": "the Sneaky",
		"attrs": "LCK · DEX", "sprite": "200×320\nrogue",
		"bonus": {"luck": 50, "dexterity": 30},
		"tagline": "Finders keepers, giggling.",
		"desc": "Tiptoes everywhere, even at breakfast. The Rogue treats luck like a cookie jar with a loose lid — crits land oftener, loot gleams brighter, and locked doors mysteriously wander open. Shares the loot. Usually.",
		"stats": [["Role", "Melee · Crit & Giggles"], ["Favors", "Luck, Nimbleness"], ["Weapon", "Butter Knives & Bonk Sticks"]],
	},
]


static func class_by_id(id: String) -> Dictionary:
	for c in CLASSES:
		if String(c["id"]) == id:
			return c
	return {}


# =========================================================================
# FACTIONS — designed in docs/lore.md §3 (mid-game allegiance, NOT yet
# choosable in-game). Stat effects are StatBlock-parsable so wiring the
# OATHS tab later is mechanical; "special" keys name the system they hook.
# =========================================================================

const FACTIONS := [
	{
		"id": "EMB", "name": "Emberwatch",
		"creed": "Keep the fire. The fire keeps you.",
		"pros": ["+15% Maximum Life", "+12% Armour"],
		"cons": ["-8% Attack Speed", "-10% Coin Find"],
		"special": {"offline_cap_bonus_hours": 2},
		"fit": "warrior", "rival": "HLW",
	},
	{
		"id": "ASH", "name": "Waffle Squad",
		"creed": "What burns, purifies.",
		"pros": ["+14% Toasty Damage", "+8% All Damage", "+6% Crit Chance"],
		"cons": ["-12% Armour"],
		"special": {"forge_iron_cost_mult": 1.25},
		"fit": "mage", "rival": "EMB",
	},
	{
		"id": "HLW", "name": "The Hollowed",
		"creed": "It only keeps what you still want.",
		"pros": ["+18% Coin Find", "+12% Item Rarity"],
		"cons": ["-10% Maximum Life"],
		"special": {"chest_rarity_band_bonus": 1, "enemy_hp_mult": 1.06},
		"fit": "rogue", "rival": "LNT",
	},
	{
		"id": "LNT", "name": "The Last Lantern",
		"creed": "Forward is the only door.",
		"pros": ["+12% Movement Speed", "+10% XP Gain"],
		"cons": ["-8% Maximum Mana"],
		"special": {"party_online_all_damage_pct": 2, "daily_chest_cap_delta": -10},
		"fit": "hunter", "rival": "HLW",
	},
]


# =========================================================================
# PARTY FINDER — mock-world pools (live mode reads /v1/party/* instead)
# =========================================================================

## Fake delvers populating mock open parties (BackendClient mock mode).
const MOCK_DELVERS := [
	{"name": "Poppy", "class_id": "hunter", "lv": 52},
	{"name": "Basil", "class_id": "warrior", "lv": 49},
	{"name": "Clover", "class_id": "mage", "lv": 55},
	{"name": "Jinx", "class_id": "rogue", "lv": 44},
	{"name": "Barley", "class_id": "warrior", "lv": 58},
	{"name": "Tulip", "class_id": "mage", "lv": 41},
	{"name": "Fennel", "class_id": "hunter", "lv": 47},
	{"name": "Minty", "class_id": "rogue", "lv": 51},
	{"name": "Gus", "class_id": "warrior", "lv": 38},
	{"name": "Nutmeg", "class_id": "mage", "lv": 60},
	{"name": "Pudding", "class_id": "hunter", "lv": 45},
	{"name": "Velvet", "class_id": "rogue", "lv": 53},
	{"name": "Alfie", "class_id": "warrior", "lv": 50},
	{"name": "Taffy", "class_id": "hunter", "lv": 42},
]

const MOCK_PARTY_NAMES := [
	"Snack Attackers", "Star Hoppers", "The Cozy Crew", "Meadow Mates",
	"Firefly Friends", "Sleepy Snails", "Bonk Brigade", "Waffle Wanderers",
]

# =========================================================================
# EQUIPMENT — canonical item helpers + slot model
# =========================================================================

## Paperdoll slot names, index-aligned with GameState.equipped.
## 0–4 = left column, 5–9 = right column (matches the design layout).
const EQUIP_SLOTS: Array[String] = [
	"Helm", "Amulet", "Body", "Gloves", "Boots",
	"Main Hand", "Off Hand", "Ring I", "Ring II", "Belt",
]

## Maps legacy bag type-prefixes ("Sword · iLvl 71") to equip slot types.
const _TYPE_TO_SLOT := {
	"helm": "Helm", "amulet": "Amulet", "chest": "Body", "body": "Body",
	"gloves": "Gloves", "boots": "Boots", "belt": "Belt", "ring": "Ring",
	"sword": "Main Hand", "mace": "Main Hand", "maul": "Main Hand",
	"offhand": "Off Hand", "off hand": "Off Hand",
}


## Can [param item_slot] (the item's type, e.g. "Ring") go into the paperdoll
## slot at [param slot_index]?
static func slot_accepts(slot_index: int, item_slot: String) -> bool:
	if slot_index < 0 or slot_index >= EQUIP_SLOTS.size():
		return false
	var slot_name := EQUIP_SLOTS[slot_index]
	if item_slot == "Ring":
		return slot_name == "Ring I" or slot_name == "Ring II"
	return slot_name == item_slot or (item_slot == "Chest" and slot_name == "Body")


## Convert a design-era GEAR_L/GEAR_R entry to the canonical item shape.
static func gear_to_item(g: Dictionary) -> Dictionary:
	var slot := String(g["slot"])
	if slot == "Ring I" or slot == "Ring II":
		slot = "Ring"
	return {"n": String(g["name"]), "r": String(g["r"]), "slot": slot,
		"ilvl": int(g["ilvl"]), "s": (g["stats"] as Array).duplicate(true)}


## Convert a design-era BAG.equipment entry ({n, r, t, s}) to canonical shape.
## Returns {} when the type doesn't map to an equip slot (e.g. "Shoulder").
static func bag_to_item(b: Dictionary) -> Dictionary:
	var t := String(b.get("t", ""))
	var head := t.split("·")[0].strip_edges().to_lower()
	if not _TYPE_TO_SLOT.has(head):
		return {}
	var ilvl := 1
	var re := RegEx.new()
	re.compile(r"iLvl\s*(\d+)")
	var m := re.search(t)
	if m != null:
		ilvl = int(m.get_string(1))
	return {"n": String(b["n"]), "r": String(b["r"]), "slot": String(_TYPE_TO_SLOT[head]),
		"ilvl": ilvl, "s": (b.get("s", []) as Array).duplicate(true)}


## Display type line for a canonical item ("Main Hand · iLvl 82 · legendary").
static func item_type_line(item: Dictionary) -> String:
	return "%s · iLvl %d · %s" % [String(item["slot"]), int(item["ilvl"]), String(item["r"])]


## --- Tetris-bag shapes -------------------------------------------------------
## Every equipment DEFINES a bag shape: the set of cells it occupies inside its
## bounding box, so packing the bag is a real puzzle (drag-to-bag for Survival
## mode). Bounding boxes match the old per-slot footprints; some shapes are
## non-rectangular (boots = L, two-hander = blade + crossguard) so pieces
## interlock. Cells are (col, row) offsets from the piece's top-left.
const GEAR_SHAPES := {
	"square2": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],                                    # helm — 2×2 O
	"body":    [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 2), Vector2i(1, 2)],    # chest — 2×3 full
	"gloves":  [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)],                                                    # gloves — corner (2×2 bbox)
	"boots":   [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)],                                                    # boots — L (2×2 bbox)
	"belt":    [Vector2i(0, 0), Vector2i(1, 0)],                                                                    # belt — I2 (2×1)
	"offhand": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2)],                    # shield (2×3 bbox)
	"single":  [Vector2i(0, 0)],                                                                                    # ring / amulet — 1×1
	"wpn1h":   [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)],                                                    # one-hander — I3 (1×3)
	"wpn2h":   [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(1, 1)],                    # two-hander — blade + crossguard (2×4 bbox)
}


## The defined shape NAME for an equipment (slot- and weapon-driven).
static func slot_shape_name(item: Dictionary) -> String:
	match String(item.get("slot", "")):
		"Helm": return "square2"
		"Body", "Chest": return "body"
		"Gloves": return "gloves"
		"Boots": return "boots"
		"Belt": return "belt"
		"Off Hand": return "offhand"
		"Amulet": return "single"
		"Ring", "Ring I", "Ring II": return "single"
		"Main Hand":
			var n := String(item.get("n", "")).to_lower()
			if n.contains("maul") or n.contains("scourge") or n.contains("staff") or n.contains("greataxe"):
				return "wpn2h"
			return "wpn1h"
	return "single"


## The occupied cells of an item's bag shape: explicit "shape" name if the item
## defines one, else derived from its slot (so legacy/design gear works too).
static func item_shape_cells(item: Dictionary) -> Array:
	var nm := String(item.get("shape", ""))
	if nm == "" or not GEAR_SHAPES.has(nm):
		nm = slot_shape_name(item)
	return (GEAR_SHAPES.get(nm, [Vector2i.ZERO]) as Array).duplicate()


## Bounding-box footprint (width × height in cells) of the gear shape — bag tile
## sizing + layout. A two-hander is 2×4; a one-hander 1×3; jewellery 1×1.
static func item_footprint(item: Dictionary) -> Vector2i:
	var w := 1
	var h := 1
	for c in item_shape_cells(item):
		w = maxi(w, int(c.x) + 1)
		h = maxi(h, int(c.y) + 1)
	return Vector2i(w, h)


## --- Bullet-hell (Star Stampede) stat ---------------------------------------
## Every equipment also DEFINES one Survival-only stat. It is stored apart from
## the idle "s" stats (so it never leaks into idle power) and only feeds the
## bullet-hell side mode. Vampire-survivors-flavoured affixes.
## "Cozy Vitality" (+% max HP) is the BinkBonk-era addition.
const _BH_AFFIXES := ["Surge Damage", "Blast Area", "Projectile Speed", "Pickup Radius", "Fire Rate", "Dash Charge", "Cozy Vitality"]

## Backpack adjacency synergies (Star Stampede loadout): when two packed pieces
## of these SLOT kinds sit orthogonally adjacent in the bag grid, the pair grants
## a bonus affix. Mirrors the prototype's charm pairs, mapped onto gear slots.
const BAG_SYNERGIES := [
	{"a": "Main Hand", "b": "Boots", "desc": "Runny-bonk combo", "affix": ["Surge Damage", 8]},
	{"a": "Amulet", "b": "Ring", "desc": "Sticky splash zone", "affix": ["Pickup Radius", 15]},
	{"a": "Gloves", "b": "Belt", "desc": "Featherlight bolts", "affix": ["Fire Rate", 10]},
	{"a": "Helm", "b": "Off Hand", "desc": "Cozy and lucky", "affix": ["Cozy Vitality", 10]},
]


## The bag pieces currently PACKED into the backpack grid (they carry a "bp"
## [x, y] cell stamped by the Bag tab; layout persists in the save).
static func survival_packed_items() -> Array:
	var out: Array = []
	for it_v in GameState.bag_equipment:
		var it: Dictionary = it_v
		if it.has("bp") and it["bp"] is Array and (it["bp"] as Array).size() == 2:
			out.append(it)
	return out


## The occupied grid cells of a packed item (from its "bp" anchor + shape).
static func _packed_cells(it: Dictionary) -> Array:
	var bp: Array = it["bp"]
	var out: Array = []
	for c in item_shape_cells(it):
		out.append(Vector2i(int(bp[0]) + int(c.x), int(bp[1]) + int(c.y)))
	return out


## Normalize a slot for synergy matching ("Ring I/II" → "Ring").
static func _syn_slot(it: Dictionary) -> String:
	var s := String(it.get("slot", ""))
	if s.begins_with("Ring"):
		return "Ring"
	return s


## Live adjacency synergies among the packed pieces:
## [{a_item, b_item, desc, affix:[name, percent]}]. Each pair rule fires at most
## once (the first adjacent pair found), mirroring the prototype.
static func survival_synergies(packed: Array = []) -> Array:
	var items := packed if not packed.is_empty() else survival_packed_items()
	var out: Array = []
	for rule_v in BAG_SYNERGIES:
		var rule: Dictionary = rule_v
		var found := false
		for i in items.size():
			if found:
				break
			var a: Dictionary = items[i]
			if _syn_slot(a) != String(rule["a"]):
				continue
			var a_cells := _packed_cells(a)
			for j in items.size():
				if j == i:
					continue
				var b: Dictionary = items[j]
				if _syn_slot(b) != String(rule["b"]):
					continue
				if _cells_adjacent(a_cells, _packed_cells(b)):
					out.append({"a_item": a, "b_item": b, "desc": String(rule["desc"]),
						"affix": (rule["affix"] as Array).duplicate()})
					found = true
					break
	return out


static func _cells_adjacent(a_cells: Array, b_cells: Array) -> bool:
	for a in a_cells:
		for b in b_cells:
			var d: Vector2i = (a as Vector2i) - (b as Vector2i)
			if absi(d.x) + absi(d.y) == 1:
				return true
	return false


static func _bh_value(ilvl: int, power: float, seed_i: int) -> int:
	return maxi(3, int(round((6.0 + float(ilvl) * 0.25) * power)) + (absi(seed_i) % 7))


## The Survival stat rows for an item: explicit "bh" if present, else a
## deterministic one derived from the item so all equipment has one.
static func item_bullet_hell(item: Dictionary) -> Array:
	if item.has("bh") and item["bh"] is Array and not (item["bh"] as Array).is_empty():
		return (item["bh"] as Array).duplicate()
	var nm := String(item.get("n", "?"))
	var idx := absi(nm.hash()) % _BH_AFFIXES.size()
	var power: float = float(_RARITY_POWER.get(String(item.get("r", "common")), 1.0))
	return [[_BH_AFFIXES[idx], "+%d%%" % _bh_value(int(item.get("ilvl", 1)), power, nm.hash())]]


## Tooltip stat rows: the idle "s" stats, then a Survival section, then extras.
static func tip_stats(item: Dictionary, extra: Array = []) -> Array:
	var out := (item.get("s", []) as Array).duplicate()
	var bh := item_bullet_hell(item)
	if not bh.is_empty():
		out.append(["✦ Stampede", ""])
		for pair in bh:
			out.append([String(pair[0]), String(pair[1])])
	for e in extra:
		out.append(e)
	return out

# =========================================================================
# CHEST LOOT — mirror of the server's lib/itemGen.ts (mock mode only;
# the deployed backend is authoritative). Keep in sync.
# =========================================================================

const _ITEM_SLOTS := ["Helm", "Amulet", "Body", "Gloves", "Boots", "Main Hand", "Off Hand", "Ring", "Belt"]
const _ITEM_BASES := {
	"Helm": ["Cowl", "Casque", "Hood", "Visage"],
	"Amulet": ["Pendant", "Locket", "Sigil", "Torc"],
	"Body": ["Plate", "Wrap", "Hauberk", "Shroud"],
	"Gloves": ["Grips", "Gauntlets", "Talons", "Fists"],
	"Boots": ["Treads", "Greaves", "Striders", "Soles"],
	"Main Hand": ["Maul", "Blade", "Scourge", "Fang"],
	"Off Hand": ["Bulwark", "Grimoire", "Effigy", "Ward"],
	"Ring": ["Band", "Loop", "Coil", "Knot"],
	"Belt": ["Girdle", "Cord", "Chain", "Sash"],
}
const _ITEM_PREFIXES := ["Sunny", "Moonbeam", "Berry", "Honey", "Twinkle", "Cozy", "Sprout", "Puddle", "Marshmallow", "Clover", "Tin", "Snug"]
const _MYTHIC_NAMES := ["Starsplitter", "Crown of the First Star", "Heart of the Meadow King", "The Legendary Spatula", "Blanket of Endless Naps", "Sovereign's Snuggie"]
# Flat coefficients calibrated against the design gear anchors (epic ilvl
# 72-75: Armour 248-612, Life 184, attrs 42; legendary 82: STR 72; rare 64:
# Mana 48): value ≈ coef × ilvl × rarity_power × 0.8-1.2.
const _FLAT_AFFIXES := [["Armour", 4.0], ["Maximum Life", 2.2], ["Muscle", 0.6], ["Nimbleness", 0.6], ["Sparkle", 0.6], ["Snuggle", 0.6], ["Luck", 0.4], ["Maximum Mana", 0.8], ["Evasion", 3.0], ["Life Regen", 1.4]]
const _PCT_AFFIXES := [["Attack Speed", 4.0, 14.0], ["Crit Chance", 3.0, 10.0], ["Crit Multi", 8.0, 35.0], ["Toasty Damage", 6.0, 26.0], ["Sparkle Damage", 6.0, 24.0], ["Bonk Damage", 6.0, 24.0], ["Coin Find", 6.0, 28.0], ["Item Rarity", 4.0, 18.0], ["Movement Speed", 4.0, 18.0], ["Toasty Resist", 8.0, 38.0], ["Frosty Resist", 8.0, 38.0], ["Zappy Resist", 8.0, 38.0]]
const _AFFIX_COUNT := {"common": 1, "uncommon": 2, "rare": 2, "epic": 3, "legendary": 4, "mythic": 5}
const _RARITY_POWER := {"common": 0.7, "uncommon": 0.85, "rare": 1.0, "epic": 1.25, "legendary": 1.6, "mythic": 2.2}


## Chest item rarity (~0.5% mythic of item rewards) — mirrors the server.
static func roll_chest_item_rarity(rng: RandomNumberGenerator) -> String:
	var x := rng.randf()
	if x < 0.005:
		return "mythic"
	if x < 0.005 + 0.035:
		return "legendary"
	if x < 0.005 + 0.035 + 0.11:
		return "epic"
	if x < 0.005 + 0.035 + 0.11 + 0.25:
		return "rare"
	if x < 0.005 + 0.035 + 0.11 + 0.25 + 0.3:
		return "uncommon"
	return "common"


## Generate one equipment item — mirrors the server's generateItem.
static func generate_item(ilvl: int, rarity: String, rng: RandomNumberGenerator, forced_slot: String = "") -> Dictionary:
	var slot: String = forced_slot if forced_slot != "" and forced_slot in _ITEM_SLOTS else _ITEM_SLOTS[rng.randi_range(0, _ITEM_SLOTS.size() - 1)]
	var bases: Array = _ITEM_BASES[slot]
	var item_name: String
	if rarity == "mythic":
		item_name = _MYTHIC_NAMES[rng.randi_range(0, _MYTHIC_NAMES.size() - 1)]
	else:
		item_name = "%s %s" % [_ITEM_PREFIXES[rng.randi_range(0, _ITEM_PREFIXES.size() - 1)], bases[rng.randi_range(0, bases.size() - 1)]]

	var power: float = _RARITY_POWER[rarity]
	var stats: Array = []
	if slot == "Main Hand":
		var lo := roundi((20.0 + float(ilvl) * 6.0) * power)
		var hi := roundi(float(lo) * (1.35 + rng.randf() * 0.2))
		stats.append(["Bonk DMG", "%d–%d" % [lo, hi]])

	var used := {}
	var want: int = int(_AFFIX_COUNT[rarity]) + (1 if slot == "Main Hand" else 0)
	while stats.size() < want:
		if rng.randf() < 0.5:
			var fa: Array = _FLAT_AFFIXES[rng.randi_range(0, _FLAT_AFFIXES.size() - 1)]
			if used.has(fa[0]):
				continue
			used[fa[0]] = true
			var v := maxi(1, roundi(float(fa[1]) * float(ilvl) * power * (0.8 + rng.randf() * 0.4)))
			stats.append([fa[0], "+%d" % v])
		else:
			var pa: Array = _PCT_AFFIXES[rng.randi_range(0, _PCT_AFFIXES.size() - 1)]
			if used.has(pa[0]):
				continue
			used[pa[0]] = true
			var pv := roundi((float(pa[1]) + rng.randf() * (float(pa[2]) - float(pa[1]))) * power)
			stats.append([pa[0], "+%d%%" % pv])

	var bh_idx := rng.randi_range(0, _BH_AFFIXES.size() - 1)
	return {"n": item_name, "r": rarity, "slot": slot, "ilvl": ilvl, "s": stats,
		"shape": slot_shape_name({"slot": slot, "n": item_name}),
		"bh": [[_BH_AFFIXES[bh_idx], "+%d%%" % _bh_value(ilvl, power, rng.randi())]]}


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
