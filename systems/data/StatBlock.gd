class_name StatBlock
extends RefCounted
## Additive/multiplicative stat aggregation (CLAUDE.md §7): every source —
## gear, talents, pets, relics, food, aura — contributes FLAT adds and
## INCREASED percentages per stat key; final value = (base + Σflat) × (1 + Σinc).
##
## The effect parser turns the design's human-readable effect strings
## ("+10 Strength", "+6% Attack Speed", "+24% Melee Damage · +30 Strength",
## ["Physical DMG", "470–664"]) into stat mods, so all existing content is
## mechanically real without re-authoring.

var flat: Dictionary = {}  # stat key -> float
var inc: Dictionary = {}   # stat key -> float (0.12 == +12%)


func add_flat(stat: String, amount: float) -> void:
	flat[stat] = float(flat.get(stat, 0.0)) + amount


func add_inc(stat: String, amount: float) -> void:
	inc[stat] = float(inc.get(stat, 0.0)) + amount


func merge(other: StatBlock) -> void:
	for k in other.flat:
		add_flat(k, other.flat[k])
	for k in other.inc:
		add_inc(k, other.inc[k])


## Resolved value: (base + flats) * (1 + incs).
func value(stat: String, base: float = 0.0) -> float:
	return (base + float(flat.get(stat, 0.0))) * (1.0 + float(inc.get(stat, 0.0)))


func get_flat(stat: String) -> float:
	return float(flat.get(stat, 0.0))


func get_inc(stat: String) -> float:
	return float(inc.get(stat, 0.0))


# =========================================================================
# Effect parsing
# =========================================================================

## Stat-name aliases → canonical keys (lowercased input, see _stat_key).
const _ALIASES := {
	"party_atk": "all_damage",
	"atk": "all_damage",
	"all_stats": "all_damage",
	"all_attributes": "all_attributes",
	"crit": "crit_chance",
	"crit_multi": "crit_multiplier",
	"hp": "maximum_life",
	"life": "maximum_life",
	"max_life": "maximum_life",
	"maximum_life": "maximum_life",
	"mana": "maximum_mana",
	"max_mana": "maximum_mana",
	"physical_dmg": "physical_dmg",
	"move_speed": "movement_speed",
	"luck": "luck",
	"rarity": "item_rarity",
	"ignite_chance": "ignite_chance",
	"strength": "strength",
	"dexterity": "dexterity",
	"intelligence": "intelligence",
	"vitality": "vitality",
	# --- BinkBonk display names → the same canonical keys (the old gothic names
	# above stay as legacy aliases so items in existing saves keep parsing) ---
	"muscle": "strength",
	"nimbleness": "dexterity",
	"sparkle": "intelligence",
	"snuggle": "vitality",
	"toasty_resist": "fire_resist",
	"frosty_resist": "cold_resist",
	"zappy_resist": "lightning_resist",
	"gloomy_resist": "chaos_resist",
	"toasty_damage": "fire_damage",
	"coin_find": "gold_find",
	"bonk_damage": "melee_damage",
	"bonk_dmg": "physical_dmg",
	"sparkle_damage": "spell_damage",
	"life_nibble": "life_leech",
}

## The five attributes (for "+30 All Attributes" expansion).
const ATTRS: Array[String] = ["strength", "dexterity", "intelligence", "vitality", "luck"]


## Parse one effect string (possibly "·"-joined) into this block.
## Unparseable fragments (pure prose like "Curses spread to nearby foes")
## are ignored — they stay flavor.
func apply_effect(text: String) -> void:
	for raw_part in text.split("·"):
		_apply_fragment(raw_part.strip_edges())


## Parse a gear stats array ([["Armour", "+248"], ["Physical DMG", "470–664"]]).
func apply_stat_pairs(pairs: Array) -> void:
	for pair in pairs:
		if pair.size() < 2:
			continue
		_apply_named(String(pair[0]), String(pair[1]))


func _apply_fragment(fragment: String) -> void:
	if fragment.is_empty():
		return
	# Patterns: "+12% Name", "-30% Name", "+10 Name", "Name +12%".
	var re := RegEx.new()
	re.compile(r"^([+\-−])(\d+(?:\.\d+)?)(%?)\s+(.+)$")
	var m := re.search(fragment)
	if m == null:
		# Try trailing form: "Ignites deal +40% damage" → unsupported prose; skip.
		return
	var sgn := -1.0 if m.get_string(1) != "+" else 1.0
	var amount := float(m.get_string(2)) * sgn
	var is_pct := m.get_string(3) == "%"
	var stat := _stat_key(m.get_string(4))
	_add_parsed(stat, amount, is_pct)


func _apply_named(stat_name: String, value_text: String) -> void:
	var stat := _stat_key(stat_name)
	var t := value_text.strip_edges().replace("−", "-")
	# Range "470–664" (also "470-664"): use the average as a flat amount.
	var range_re := RegEx.new()
	range_re.compile(r"^(\d+(?:\.\d+)?)\s*[–-]\s*(\d+(?:\.\d+)?)$")
	var rm := range_re.search(t)
	if rm != null:
		_add_parsed(stat, (float(rm.get_string(1)) + float(rm.get_string(2))) * 0.5, false)
		return
	var re := RegEx.new()
	re.compile(r"^([+\-]?)(\d+(?:,\d{3})*(?:\.\d+)?)(%?)$")
	var m := re.search(t)
	if m == null:
		return
	var amount := float(m.get_string(2).replace(",", ""))
	if m.get_string(1) == "-":
		amount = -amount
	_add_parsed(stat, amount, m.get_string(3) == "%")


func _add_parsed(stat: String, amount: float, is_pct: bool) -> void:
	if stat == "all_attributes":
		for attr in ATTRS:
			if is_pct:
				add_inc(attr, amount / 100.0)
			else:
				add_flat(attr, amount)
		return
	if is_pct:
		add_inc(stat, amount / 100.0)
	else:
		add_flat(stat, amount)


## "Melee Damage" → "melee_damage"; resolves aliases ("party ATK" → all_damage).
static func _stat_key(stat_name: String) -> String:
	var key := stat_name.strip_edges().to_lower()
	key = key.replace("-", " ").replace("  ", " ").replace(" ", "_")
	return String(_ALIASES.get(key, key))
