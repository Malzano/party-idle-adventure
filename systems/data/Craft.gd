class_name Craft
extends RefCounted
## The crafting economy — the single source of truth for materials, salvage,
## fusion, blacksmith crafting, gem sockets and the Endless Tower math. Pure
## data + deterministic helpers; all player-state mutation lives in GameState
## (salvage_item / fuse_* / craft_item / drill_socket / insert_gem / tower_*).
##
## Reuses the 5-rarity ladder (common..legendary; mythic = drop-only cap), the 9
## equip slots, the item dict {n,r,slot,ilvl,s,bh}, and GearIcon kinds.

const RARITIES := ["common", "uncommon", "rare", "epic", "legendary"]


# =========================================================================
# (1) MATERIALS — iron_ingots + ember_dust are existing GameState int fields;
# the other six live in GameState.materials (a Dictionary id→count).
# =========================================================================

const MATERIALS := {
	"iron_ingots":    {"n": "Iron Ingot",      "tier": "common",    "kind": "ingot",  "for": "Bulk metal; every craft & upgrade."},
	"tanned_leather": {"n": "Tanned Leather",   "tier": "common",    "kind": "ingot",  "for": "Light armour base; low-rarity crafts."},
	"gravesilk":      {"n": "Gravesilk Thread", "tier": "uncommon",  "kind": "scroll", "for": "Cloth & jewellery cord; mid tailoring."},
	"hollow_marrow":  {"n": "Hollow Marrow",    "tier": "rare",      "kind": "ingot",  "for": "Monster essence; binds rare+ affixes."},
	"ember_dust":     {"n": "Ember Dust",       "tier": "rare",      "kind": "gem",    "for": "Reactive reagent; rare+ crafts & fusion."},
	"rune_dust":      {"n": "Rune Dust",        "tier": "epic",      "kind": "gem",    "for": "Gem residue; sockets & epic crafts."},
	"arcane_shard":   {"n": "Arcane Shard",     "tier": "epic",      "kind": "relic",  "for": "Crystallised magic; epic/legendary crafts."},
	"cinder_core":    {"n": "Cinder Core",      "tier": "legendary", "kind": "relic",  "for": "Boss/legendary drop; gates legendary crafts."},
}
## Fixed display order (low → high tier) for material readouts.
const MATERIAL_ORDER := ["iron_ingots", "tanned_leather", "gravesilk", "hollow_marrow", "ember_dust", "rune_dust", "arcane_shard", "cinder_core"]


# =========================================================================
# (2) SALVAGE — consume an item, pay a smith's fee, get materials.
# =========================================================================

const SALVAGE := {
	"common":    {"gold": 40,  "mats": {"iron_ingots": [2, 4], "tanned_leather": [1, 3]}},
	"uncommon":  {"gold": 100, "mats": {"iron_ingots": [3, 6], "tanned_leather": [2, 4], "gravesilk": [1, 2]}},
	"rare":      {"gold": 160, "mats": {"iron_ingots": [5, 9], "gravesilk": [2, 4], "ember_dust": [1, 3], "hollow_marrow": [1, 2]}},
	"epic":      {"gold": 220, "mats": {"ember_dust": [2, 5], "hollow_marrow": [2, 4], "rune_dust": [1, 3], "arcane_shard": [1, 2]}},
	"legendary": {"gold": 280, "mats": {"ember_dust": [4, 8], "rune_dust": [2, 5], "arcane_shard": [2, 4], "cinder_core": [1, 1]}},
}
const SALVAGE_GEM := {
	"common":    {"gold": 30,  "mats": {"ember_dust": [1, 2]}},
	"uncommon":  {"gold": 60,  "mats": {"ember_dust": [2, 3]}},
	"rare":      {"gold": 100, "mats": {"ember_dust": [2, 4], "rune_dust": [1, 2]}},
	"epic":      {"gold": 150, "mats": {"rune_dust": [2, 4], "arcane_shard": [1, 2]}},
	"legendary": {"gold": 220, "mats": {"rune_dust": [3, 6], "arcane_shard": [2, 3]}},
}


# =========================================================================
# (3/4) FUSION — 5 → 1, result rarity shifts vs the highest input rarity.
# =========================================================================

const FUSE_GEAR := {
	"common":    {"down1": 0.00, "same": 0.62, "up1": 0.32, "up2": 0.06},
	"uncommon":  {"down1": 0.05, "same": 0.60, "up1": 0.30, "up2": 0.05},
	"rare":      {"down1": 0.08, "same": 0.58, "up1": 0.30, "up2": 0.04},
	"epic":      {"down1": 0.10, "same": 0.60, "up1": 0.30, "up2": 0.00},
	"legendary": {"down1": 0.30, "same": 0.70, "up1": 0.00, "up2": 0.00},
}
const FUSE_GEM := {
	"common":    {"down1": 0.00, "same": 0.65, "up1": 0.30, "up2": 0.05},
	"uncommon":  {"down1": 0.05, "same": 0.62, "up1": 0.30, "up2": 0.03},
	"rare":      {"down1": 0.08, "same": 0.60, "up1": 0.29, "up2": 0.03},
	"epic":      {"down1": 0.10, "same": 0.61, "up1": 0.29, "up2": 0.00},
	"legendary": {"down1": 0.30, "same": 0.70, "up1": 0.00, "up2": 0.00},
}
const FUSE_COUNT := 5  # items consumed per fusion


# =========================================================================
# (5) CRAFT — blacksmith: build a fresh item of a chosen slot + rarity.
# =========================================================================

const CRAFT_MATS := {
	"common":    {"iron_ingots": 6,  "tanned_leather": 4},
	"uncommon":  {"iron_ingots": 10, "tanned_leather": 6,  "gravesilk": 3},
	"rare":      {"iron_ingots": 16, "gravesilk": 5,       "ember_dust": 4,   "hollow_marrow": 2},
	"epic":      {"ember_dust": 8,   "hollow_marrow": 5,   "rune_dust": 4,    "arcane_shard": 2},
	"legendary": {"ember_dust": 14,  "rune_dust": 8,       "arcane_shard": 4, "cinder_core": 1},
}
## Craftable slots (Ring covers both ring slots).
const CRAFT_SLOTS := ["Helm", "Amulet", "Body", "Gloves", "Boots", "Main Hand", "Off Hand", "Ring", "Belt"]


# =========================================================================
# (6) SOCKETS — per-slot capacity + escalating drill cost.
# =========================================================================

const SOCKET_MAX := {
	"Main Hand": 3, "Body": 3, "Helm": 2, "Off Hand": 2, "Gloves": 2,
	"Boots": 2, "Belt": 1, "Amulet": 1, "Ring": 1,
}
const SOCKET_MATS := {
	1: {"iron_ingots": 4},
	2: {"ember_dust": 3, "hollow_marrow": 2},
	3: {"rune_dust": 4, "arcane_shard": 2},
}


# =========================================================================
# (7) THE 20 GEMS — weapon gems fit Main/Off Hand; armour gems fit worn gear.
# =========================================================================

const GEMS := [
	{"id": "cinder_ruby",      "n": "Cinderheart Ruby",    "cat": "weapon", "r": "common",    "eff": "+6% Fire DMG"},
	{"id": "keening_shard",    "n": "Keening Shard",       "cat": "weapon", "r": "common",    "eff": "+4% Attack Speed"},
	{"id": "vein_topaz",       "n": "Bloodvein Topaz",     "cat": "weapon", "r": "uncommon",  "eff": "+8% Physical DMG"},
	{"id": "frost_beryl",      "n": "Rimefang Beryl",      "cat": "weapon", "r": "uncommon",  "eff": "+9% Cold DMG"},
	{"id": "hollow_onyx",      "n": "Hollowpoint Onyx",    "cat": "weapon", "r": "rare",      "eff": "+5% Crit"},
	{"id": "leech_garnet",     "n": "Sanguine Garnet",     "cat": "weapon", "r": "rare",      "eff": "+4% Lifesteal"},
	{"id": "storm_citrine",    "n": "Stormbite Citrine",   "cat": "weapon", "r": "rare",      "eff": "+11% Lightning DMG"},
	{"id": "reaver_diamond",   "n": "Reaver's Diamond",    "cat": "weapon", "r": "epic",      "eff": "+40% Crit Multi"},
	{"id": "sunder_opal",      "n": "Sundering Opal",      "cat": "weapon", "r": "epic",      "eff": "+18% Armour Pen"},
	{"id": "wrath_star",       "n": "Wrathfire Starstone", "cat": "weapon", "r": "legendary", "eff": "+15% Ignite on Hit"},
	{"id": "warden_jade",      "n": "Warden's Jade",       "cat": "armour", "r": "common",    "eff": "+120 Max Life"},
	{"id": "quill_agate",      "n": "Thornquill Agate",    "cat": "armour", "r": "common",    "eff": "+40 Thorns"},
	{"id": "bulwark_slate",    "n": "Bulwark Slate",       "cat": "armour", "r": "uncommon",  "eff": "+160 Armour"},
	{"id": "mending_pearl",    "n": "Mending Pearl",       "cat": "armour", "r": "uncommon",  "eff": "+90 Life Regen"},
	{"id": "phantom_moon",     "n": "Phantom Moonstone",   "cat": "armour", "r": "rare",      "eff": "+6% Dodge"},
	{"id": "tower_sardonyx",   "n": "Towershell Sardonyx", "cat": "armour", "r": "rare",      "eff": "+8% Block"},
	{"id": "warding_lazuli",   "n": "Warding Lazuli",      "cat": "armour", "r": "rare",      "eff": "+22% All Resist"},
	{"id": "hearthstone_ruby", "n": "Hearthblood Ruby",    "cat": "armour", "r": "epic",      "eff": "+8% Max Life"},
	{"id": "midas_topaz",      "n": "Gravegilt Topaz",     "cat": "armour", "r": "epic",      "eff": "+18% Gold Find"},
	{"id": "covet_amethyst",   "n": "Covetous Amethyst",   "cat": "armour", "r": "legendary", "eff": "+14% Item Rarity"},
]
const GEM_WEAPON_SLOTS := ["Main Hand", "Off Hand"]
const GEM_ARMOUR_SLOTS := ["Helm", "Body", "Gloves", "Boots", "Belt", "Amulet", "Ring"]


# =========================================================================
# (8) ENDLESS TOWER — "The Spire": 100 floors × easy/hard/hell.
# =========================================================================

const TOWER_FLOORS := 100
const TOWER_BOSS_EVERY := 5
const TOWER_GRAND_EVERY := 25
const TOWER_MINIBOSS_MULT := 4.0
const TOWER_GRAND_MULT := 14.0
const TOWER_TIME := 180.0
const TOWER_GRAND_TIME := 300.0
const DIFF_HP := {"easy": 1.0, "hard": 6.0, "hell": 40.0}
const DIFF_EDPS := {"easy": 1.0, "hard": 5.0, "hell": 30.0}
const DIFF_CP := {"easy": 1.0, "hard": 4.0, "hell": 22.0}
const DIFF_REWARD := {"easy": 1.0, "hard": 3.0, "hell": 9.0}
const DIFFICULTIES := ["easy", "hard", "hell"]


# =========================================================================
# Helpers — pure, deterministic.
# =========================================================================

static func rarity_index(r: String) -> int:
	return clampi(int(GameContent.RARITY_RANK.get(r, 0)), 0, 4)


static func salvage_gold(r: String) -> int:
	return 40 + 60 * rarity_index(r)


static func fuse_gear_gold(r: String) -> int:
	return int(round(800.0 * pow(2.2, rarity_index(r))))


static func fuse_gem_gold(r: String) -> int:
	return int(round(500.0 * pow(2.0, rarity_index(r))))


static func craft_gold(r: String) -> int:
	return int(round(600.0 * pow(2.5, rarity_index(r))))


static func craft_ilvl(r: String) -> int:
	return 40 + 12 * rarity_index(r)


static func craft_affixes(r: String) -> int:
	return 1 + rarity_index(r)


static func socket_gold(nth: int) -> int:
	return int(round(500.0 * pow(4.0, maxi(0, nth - 1))))


static func socket_max(slot: String) -> int:
	return int(SOCKET_MAX.get(slot, 1))


static func gem_fits_slot(gem: Dictionary, slot: String) -> bool:
	if String(gem.get("cat", "")) == "weapon":
		return slot in GEM_WEAPON_SLOTS
	return slot in GEM_ARMOUR_SLOTS


static func gem_by_id(id: String) -> Dictionary:
	for g in GEMS:
		if String((g as Dictionary)["id"]) == id:
			return (g as Dictionary).duplicate(true)
	return {}


## A random gem of the given rarity tier and optional category ("" = any).
static func random_gem(tier: String, cat: String, rng: RandomNumberGenerator) -> Dictionary:
	var pool: Array = []
	for g in GEMS:
		var gd: Dictionary = g
		if String(gd["r"]) == tier and (cat == "" or String(gd["cat"]) == cat):
			pool.append(gd)
	if pool.is_empty():  # fall back to any gem of the tier
		for g in GEMS:
			if String((g as Dictionary)["r"]) == tier:
				pool.append(g)
	if pool.is_empty():
		return {}
	return (pool[rng.randi_range(0, pool.size() - 1)] as Dictionary).duplicate(true)


## Roll a fusion outcome delta (-1 / 0 / +1 / +2) from a probability row.
static func roll_shift(table: Dictionary, rng: RandomNumberGenerator) -> int:
	var x := rng.randf()
	var d1 := float(table.get("down1", 0.0))
	var sm := float(table.get("same", 0.0))
	var u1 := float(table.get("up1", 0.0))
	if x < d1:
		return -1
	if x < d1 + sm:
		return 0
	if x < d1 + sm + u1:
		return 1
	return 2


## Result rarity when fusing, given the highest input rarity and its table row.
static func fuse_result_rarity(highest_r: String, table: Dictionary, rng: RandomNumberGenerator) -> String:
	var idx := clampi(rarity_index(highest_r) + roll_shift(table, rng), 0, 4)
	return RARITIES[idx]


## Highest rarity across a set of item/gem dicts.
static func highest_rarity(items: Array) -> String:
	var best := 0
	for it in items:
		best = maxi(best, rarity_index(String((it as Dictionary).get("r", "common"))))
	return RARITIES[best]


# --- Tower math -----------------------------------------------------------

static func tower_hp(f: int, diff: String) -> float:
	return 9000.0 * pow(1.085, float(f - 1)) * float(DIFF_HP.get(diff, 1.0))


static func tower_edps(f: int, diff: String) -> float:
	return 220.0 * pow(1.075, float(f - 1)) * float(DIFF_EDPS.get(diff, 1.0))


static func tower_cp_gate(f: int, diff: String) -> float:
	return 2500.0 * pow(1.08, float(f - 1)) * float(DIFF_CP.get(diff, 1.0))


static func tower_waves(f: int) -> int:
	return 3 + ((f - 1) % 3)  # cycles 3,4,5


static func tower_is_grand(f: int) -> bool:
	return f % TOWER_GRAND_EVERY == 0


static func tower_is_boss(f: int) -> bool:
	return f % TOWER_BOSS_EVERY == 0


## "grand" | "boss" | "wave" — the floor's headline encounter.
static func tower_kind(f: int) -> String:
	if tower_is_grand(f):
		return "grand"
	if tower_is_boss(f):
		return "boss"
	return "wave"


static func tower_time_limit(f: int) -> float:
	return TOWER_GRAND_TIME if tower_is_grand(f) else TOWER_TIME


static func tower_boss_mult(f: int) -> float:
	if tower_is_grand(f):
		return TOWER_GRAND_MULT
	if tower_is_boss(f):
		return TOWER_MINIBOSS_MULT
	return 1.0


## CP-gate band label + colour key given the player's power vs the floor gate.
static func tower_gate_band(player_cp: float, f: int, diff: String) -> String:
	var ratio := player_cp / maxf(1.0, tower_cp_gate(f, diff))
	if ratio >= 1.25:
		return "Favored"
	if ratio >= 0.85:
		return "Even"
	if ratio >= 0.55:
		return "Risky"
	return "Under-powered"


## Deterministic floor run: player DPS vs each wave's HP pool within the time
## limit. Returns {cleared, waves_cleared, waves_total, time_used}.
static func run_tower_floor(f: int, diff: String, dps: float) -> Dictionary:
	var d := maxf(1.0, dps)
	var total := tower_waves(f)
	var limit := tower_time_limit(f)
	var used := 0.0
	var cleared_waves := 0
	for w in total:
		var pool := tower_hp(f, diff)
		var is_last := w == total - 1
		if is_last and tower_is_boss(f):
			pool *= tower_boss_mult(f)
		# Same tick quantization as the offline sim.
		var secs := ceilf(pool / d * float(CombatSim.TICK_RATE)) / float(CombatSim.TICK_RATE)
		if used + secs > limit:
			return {"cleared": false, "waves_cleared": cleared_waves, "waves_total": total, "time_used": used}
		used += secs
		cleared_waves += 1
	return {"cleared": true, "waves_cleared": cleared_waves, "waves_total": total, "time_used": used}


## Gear-rarity floor by depth (before the difficulty bump).
static func tower_gear_floor(f: int) -> String:
	if f < 20:
		return "common"
	if f < 40:
		return "uncommon"
	if f < 60:
		return "rare"
	if f < 80:
		return "epic"
	return "legendary"


## Rarity a Tower drop rolls at: depth floor + difficulty bump (hard +1, hell +2).
static func tower_drop_rarity(f: int, diff: String) -> String:
	var bump := 0
	if diff == "hard":
		bump = 1
	elif diff == "hell":
		bump = 2
	return RARITIES[clampi(rarity_index(tower_gear_floor(f)) + bump, 0, 4)]


## Gem tier index a Tower floor grants (0 common .. 4 legendary).
static func tower_gem_tier(f: int) -> String:
	return RARITIES[clampi(int(f / 20), 0, 4)]


static func tower_gold(f: int, diff: String) -> int:
	return int(round(80.0 * pow(1.06, float(f)) * float(DIFF_REWARD.get(diff, 1.0))))


static func tower_xp(f: int, diff: String) -> int:
	return int(round(40.0 * pow(1.05, float(f)) * float(DIFF_REWARD.get(diff, 1.0))))


static func tower_iron(f: int, diff: String) -> int:
	return int(round(float(8 + 2 * f) * float(DIFF_REWARD.get(diff, 1.0))))


static func tower_dust(f: int, diff: String) -> int:
	return int(round(float(3 + f) * float(DIFF_REWARD.get(diff, 1.0))))
