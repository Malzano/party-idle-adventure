class_name Balance
extends RefCounted
## Typed access to res://data/balance.json (CLAUDE.md: balance stays
## data-driven so tuning needs no code changes). Loaded once, cached.
## Every getter takes the dotted path "section.key" and a default.

const PATH := "res://data/balance.json"

static var _data: Dictionary = {}
static var _loaded := false


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
