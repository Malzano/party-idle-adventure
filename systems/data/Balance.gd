class_name Balance
extends RefCounted
## Typed access to res://data/balance.json (CLAUDE.md: balance stays
## data-driven so tuning needs no code changes). Loaded once, cached.
## Every getter takes the dotted path "section.key" and a default.

const PATH := "res://data/balance.json"
const BOSS_PATH := "res://data/bosses.json"

static var _data: Dictionary = {}
static var _loaded := false
static var _bosses: Dictionary = {}
static var _bosses_loaded := false


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PATH):
		push_error("Balance: %s missing — using code defaults." % PATH)
		return
	var file := FileAccess.open(PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		_data = parsed
	else:
		push_error("Balance: %s is malformed JSON — using code defaults." % PATH)


static func _ensure_bosses() -> void:
	if _bosses_loaded:
		return
	_bosses_loaded = true
	if not FileAccess.file_exists(BOSS_PATH):
		push_error("Balance: %s missing — bosses disabled." % BOSS_PATH)
		return
	var file := FileAccess.open(BOSS_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		_bosses = parsed
	else:
		push_error("Balance: %s is malformed JSON — bosses disabled." % BOSS_PATH)


## Raw value at "section.key" (or "section.sub.key"), else [param default].
static func value(path: String, default: Variant) -> Variant:
	_ensure()
	var node: Variant = _data
	for part in path.split("."):
		if typeof(node) != TYPE_DICTIONARY or not (node as Dictionary).has(part):
			return default
		node = node[part]
	return node


static func num(path: String, default: float) -> float:
	return float(value(path, default))


static func inum(path: String, default: int) -> int:
	return int(value(path, default))


## Test seam: force-reload (e.g. after writing a temp balance file).
static func reset_cache() -> void:
	_loaded = false
	_data = {}
	_bosses_loaded = false
	_bosses = {}


## Live-ops overrides from GET /v1/config: deep-merge section dictionaries
## over the local file (server wins per key). Callers must invalidate
## PlayerStats afterwards so live values reprice.
static func apply_overrides(overrides: Dictionary) -> void:
	_ensure()
	for section in overrides:
		var vals: Variant = overrides[section]
		if typeof(vals) != TYPE_DICTIONARY:
			continue
		if not _data.has(section) or typeof(_data[section]) != TYPE_DICTIONARY:
			_data[section] = {}
		var target: Dictionary = _data[section]
		for key in (vals as Dictionary):
			target[key] = vals[key]


# --- Frequently used derived helpers ----------------------------------------

## Global stage index: act 1 stage 1 → 1; act 4 stage 7 → 157.
static func stage_index(act: int, stage: int) -> int:
	var per_act := inum("enemy.stages_per_act", 50)
	return (act - 1) * per_act + stage


## Total enemy HP pool for one wave at the given stage index.
static func wave_pool(s_index: int) -> float:
	return num("enemy.base_pool", 1500.0) * pow(num("enemy.pool_growth", 1.076), float(s_index - 1))


## Base gold for clearing one wave at the given stage index.
static func wave_gold(s_index: int) -> float:
	return num("rewards.gold_base", 12.0) * pow(num("rewards.gold_growth", 1.024), float(s_index - 1))


## Base XP for clearing one wave at the given stage index.
static func wave_xp(s_index: int) -> float:
	return num("rewards.xp_base", 4.0) * pow(num("rewards.xp_growth", 1.022), float(s_index - 1))


## Forge gold cost to go from [param level] to level+1.
static func forge_gold_cost(level: int) -> int:
	var base_level := inum("forge.base_level", 7)
	return int(num("forge.gold_base", 4200.0) * pow(num("forge.gold_growth", 1.6), float(level - base_level)))


# --- Floors, sub-stages & bosses --------------------------------------------
# The flat stage_index (1..) is grouped into floors of `substages_per_floor`
# sub-stages. The mini-boss rides the final wave of sub-stage 5, the floor boss
# the final wave of sub-stage 10. stages_per_act stays the (server-shared)
# index multiplier; this layer is purely client-side cadence.

static func substages_per_floor() -> int:
	return inum("enemy.substages_per_floor", 10)


## 1-based global floor for a stage (act 1 stages 1-10 → floor 1, etc.).
static func floor_index(act: int, stage: int) -> int:
	@warning_ignore("integer_division")
	return (stage_index(act, stage) - 1) / substages_per_floor() + 1


## 1-based sub-stage within its floor (1..substages_per_floor).
static func substage_in_floor(act: int, stage: int) -> int:
	return (stage_index(act, stage) - 1) % substages_per_floor() + 1


## "normal" | "miniboss" | "boss" — bosses only on the final wave of their
## sub-stage so the earlier waves stay normal trash.
static func wave_kind(act: int, stage: int, wave: int) -> String:
	if wave < inum("enemy.waves_per_stage", 5):
		return "normal"
	var sub := substage_in_floor(act, stage)
	if sub == inum("enemy.boss_substage", 10):
		return "boss"
	if sub == inum("enemy.miniboss_substage", 5):
		return "miniboss"
	return "normal"


## HP-pool multiplier for a boss wave (1.0 for "normal").
static func boss_hp_mult(kind: String) -> float:
	match kind:
		"boss": return num("enemy.boss_hp_mult", 9.0)
		"miniboss": return num("enemy.miniboss_hp_mult", 4.0)
		_: return 1.0


## Gold/XP reward multiplier for a boss wave (1.0 for "normal").
static func boss_reward_mult(kind: String) -> float:
	match kind:
		"boss": return num("rewards.boss_reward_mult", 10.0)
		"miniboss": return num("rewards.miniboss_reward_mult", 4.0)
		_: return 1.0


static func boss_time_cap() -> float:
	_ensure_bosses()
	return float(_bosses.get("boss_time_cap", 600.0))


## The skill kit dict for a boss tier ({} when none / "normal").
static func boss_kit(kind: String) -> Dictionary:
	_ensure_bosses()
	var kits: Variant = _bosses.get("kits", {})
	if typeof(kits) == TYPE_DICTIONARY and (kits as Dictionary).has(kind):
		return (kits as Dictionary)[kind]
	return {}


## Flavour name for a boss tier on a given floor (wraps past the list length).
static func boss_name(kind: String, floor_i: int) -> String:
	_ensure_bosses()
	var key := "boss_names" if kind == "boss" else "miniboss_names"
	var names: Variant = _bosses.get(key, [])
	if typeof(names) == TYPE_ARRAY and not (names as Array).is_empty():
		var arr := names as Array
		return String(arr[(floor_i - 1) % arr.size()])
	return "Floor Boss" if kind == "boss" else "Mini-Boss"


# --- Boss skill modulations (pure; shared by live tick + offline) ------------
# t is the boss wave's elapsed time in seconds. These are the ONLY source of
# boss pacing, so the live sim and simulate_offline stay identical.

## Multiplier on party DPS at time t (shield/debuff windows < 1.0).
static func boss_dps_mult(kit: Dictionary, t: float) -> float:
	var sh: Variant = kit.get("shield", {})
	if typeof(sh) != TYPE_DICTIONARY or (sh as Dictionary).is_empty():
		return 1.0
	var start := float((sh as Dictionary).get("start", 1.0e12))
	if t < start:
		return 1.0
	var period := maxf(0.001, float((sh as Dictionary).get("period", 1.0e12)))
	var dur := float((sh as Dictionary).get("duration", 0.0))
	var phase := fmod(t - start, period)
	return float((sh as Dictionary).get("leak", 1.0)) if phase < dur else 1.0


## Added fraction to the clear threshold at time t from enrage (0.0 before it
## starts; capped). effective_pool = wave_pool * (1 + this) [+ adds].
static func boss_enrage_factor(kit: Dictionary, t: float) -> float:
	var en: Variant = kit.get("enrage", {})
	if typeof(en) != TYPE_DICTIONARY or (en as Dictionary).is_empty():
		return 0.0
	var start := float((en as Dictionary).get("start", 1.0e12))
	if t < start:
		return 0.0
	return minf(float((en as Dictionary).get("cap", 0.0)),
		float((en as Dictionary).get("ramp", 0.0)) * (t - start))


## Boss HP recovered per second (absolute), 0.0 when the kit has no regen.
static func boss_regen_per_sec(kit: Dictionary, wave_pool: float) -> float:
	var rg: Variant = kit.get("regen", {})
	if typeof(rg) != TYPE_DICTIONARY:
		return 0.0
	return float((rg as Dictionary).get("per_sec_frac", 0.0)) * wave_pool
