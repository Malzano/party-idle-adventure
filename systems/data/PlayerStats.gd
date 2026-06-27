class_name PlayerStats
extends RefCounted
## Computes the live player profile from all stat sources (CLAUDE.md §7):
## equipped gear (incl. forge upgrades) + allocated talents + active pet +
## equipped relics + food buff + Team Aura + roster support. Pure functions of
## GameState + GameContent + Balance, so the CombatSim can use it headless.
##
## Cached; call invalidate() (or listen to the EventBus signals that mutate
## sources) and recompute lazily.

static var _cache: Dictionary = {}
static var _dirty := true


static func invalidate() -> void:
	_dirty = true


## Full computed profile:
## { block: StatBlock, party_dps: float, dps_label: String, attrs: Dictionary,
##   derived: Dictionary, total_power: float, gear_power: float }
static func compute() -> Dictionary:
	if not _dirty and not _cache.is_empty():
		return _cache
	_dirty = false

	var block := StatBlock.new()

	# --- Gear (live paperdoll, with forge growth on the upgraded weapon) ----
	for item_v in GameState.equipped:
		if item_v == null:
			continue
		var item: Dictionary = item_v
		var pairs: Array = item["s"]
		if String(item["n"]) == "Cindergrip Maul":
			pairs = forged_weapon_stats()
		var gb := StatBlock.new()
		gb.apply_stat_pairs(pairs)
		block.merge(gb)

	# --- Class identity bonus (first-login choice) ---------------------------
	var cls := GameContent.class_by_id(GameState.class_id)
	if not cls.is_empty():
		var bonus: Dictionary = cls["bonus"]
		for stat in bonus:
			block.add_flat(String(stat), float(bonus[stat]))

	# --- Talents (allocated node effects) ------------------------------------
	var tree := _tree()
	for node in tree["nodes"]:
		if GameState.talents_allocated.has(int(node["id"])):
			block.apply_effect(String(node["eff"]))

	# --- Active pet aura (ownership can be milestone-derived; -1 = none worn) ---
	var pet_idx := GameState.active_pet
	if pet_idx >= 0 and pet_idx < GameContent.PETS.size() and GameContent.pet_owned(pet_idx):
		block.apply_effect(String(GameContent.PETS[pet_idx]["eff"]))

	# --- Equipped relics (incl. stage-milestone unlocks) -----------------------
	for relic in GameContent.live_relics():
		if not bool(relic["empty"]):
			block.apply_effect(String(relic["eff"]))

	# --- Food buff (timed) ----------------------------------------------------
	if GameState.food_buff_active():
		block.apply_effect(GameState.food_buff_effect)

	# --- Character DPS (1 account = 1 character) ------------------------------
	# Base DPS is the chosen class's; gear/talents scale it via dps_mult; the
	# real-party composition aura (party_aura_mult, server-side, 1.0 solo)
	# multiplies on top. Calibrated so a solo player ≈ the old optimal 4-party.
	var char_bases: Dictionary = Balance.value("character.base_dps", {})
	var base_dps := float(char_bases.get(GameState.class_id, char_bases.get("default", 4000000.0)))

	var half := Balance.num("dps_model.half_coef", 0.5)
	var dps_mult := 1.0 + block.get_inc("all_damage") \
		+ half * (block.get_inc("melee_damage") + block.get_inc("spell_damage") \
		+ block.get_inc("fire_damage") + block.get_inc("attack_speed"))

	# Character level scales DPS (1.0 at the calibration level): a fresh delver is
	# weak enough that floor 1-1's tiny pool is a real fight, growing into the
	# deeper floors as it levels. Invalidated on every level_up so this reprices.
	var party_dps := base_dps * dps_mult * GameState.party_aura_mult \
		* Balance.level_dps_mult(GameState.player_level)

	# --- Attributes + derived -------------------------------------------------
	var attrs := {}
	for i in GameContent.MAIN_STATS.size():
		var ms: Dictionary = GameContent.MAIN_STATS[i]
		var canon: String = ["strength", "dexterity", "intelligence", "vitality", "luck"][i]
		attrs[canon] = block.value(canon, float(ms["v"]))

	var derived := {
		"attack_dps": party_dps,
		"maximum_life": block.value("maximum_life", Balance.num("derived_bases.maximum_life", 120000.0)),
		"armour": block.value("armour", Balance.num("derived_bases.armour", 9000.0)),
		"maximum_mana": block.value("maximum_mana", Balance.num("derived_bases.maximum_mana", 8000.0)),
		"crit_chance": Balance.num("derived_bases.crit_chance", 0.18) + block.get_inc("crit_chance"),
		"crit_multiplier": Balance.num("derived_bases.crit_multiplier", 2.5) * (1.0 + block.get_inc("crit_multiplier")),
		"gold_find": block.get_inc("gold_find"),
		"item_rarity": block.get_inc("item_rarity"),
		"xp_gain": block.get_inc("xp_gain"),
		"movement_speed": block.get_inc("movement_speed"),
		"attack_speed": block.get_inc("attack_speed"),
		"fire_resist": block.get_inc("fire_resist"),
		"cold_resist": block.get_inc("cold_resist"),
		"lightning_resist": block.get_inc("lightning_resist"),
		"chaos_resist": block.get_inc("chaos_resist"),
		"block_chance": Balance.num("derived_bases.block_chance", 0.0) + block.get_inc("block"),
		"life_regen": block.value("life_regen", Balance.num("derived_bases.life_regen", 1500.0)),
		"mana_regen": block.value("mana_regen", Balance.num("derived_bases.mana_regen", 700.0)) * (1.0 + block.get_inc("mana_regen")),
		"evasion": block.value("evasion", Balance.num("derived_bases.evasion", 5000.0)),
		"accuracy": Balance.num("derived_bases.accuracy", 0.90) + block.get_flat("accuracy") * 0.001,
	}

	# --- Powers ---------------------------------------------------------------
	var gear_power := compute_gear_power()
	var attr_sum := 0.0
	for a in attrs.values():
		attr_sum += float(a)
	var total_power := party_dps * Balance.num("power.dps_w", 0.012) \
		+ float(derived["maximum_life"]) * Balance.num("power.life_w", 0.2) \
		+ float(derived["armour"]) * Balance.num("power.armour_w", 1.0) \
		+ attr_sum * Balance.num("power.attr_w", 8.0) \
		+ gear_power

	_cache = {
		"block": block,
		"party_dps": party_dps,
		"dps_label": format_dps(party_dps),
		"attrs": attrs,
		"derived": derived,
		"total_power": total_power,
		"gear_power": gear_power,
	}
	return _cache


## Whether a real-party composition aura is currently active (server-computed;
## 1.0 = solo / no bonus). The old local 1-tank/1-healer/2-DPS check is gone —
## the aura now comes from your real party (party_aura_mult, set on the
## /party/mine heartbeat). Drives the Fight "Party Aura" badge.
static func team_aura_optimal() -> bool:
	return GameState.party_aura_mult > 1.0001


## The forge-upgraded weapon's stat pairs, scaled by stat_growth^(levels above
## base). Bound to the Cindergrip Maul by name wherever it currently sits
## (equipped or bag); falls back to the design baseline if it was discarded.
static func forged_weapon_stats() -> Array:
	var base_level := Balance.inum("forge.base_level", 7)
	var growth := pow(Balance.num("forge.stat_growth", 1.13), float(GameState.forge_level - base_level))
	var base_pairs: Array = GameContent.GEAR_R[0]["stats"]
	for item_v in GameState.equipped + GameState.bag_equipment:
		if item_v != null and String((item_v as Dictionary).get("n", "")) == "Cindergrip Maul":
			base_pairs = (item_v as Dictionary)["s"]
			break
	var out: Array = []
	for pair in base_pairs:
		out.append([pair[0], _scale_value_text(String(pair[1]), growth)])
	return out


## Scales "470–664" / "+72" / "+8.5%" value text by [param mult].
static func _scale_value_text(text: String, mult: float) -> String:
	var range_re := RegEx.new()
	range_re.compile(r"^(\d+(?:\.\d+)?)\s*[–-]\s*(\d+(?:\.\d+)?)$")
	var rm := range_re.search(text)
	if rm != null:
		return "%d–%d" % [int(float(rm.get_string(1)) * mult), int(float(rm.get_string(2)) * mult)]
	var re := RegEx.new()
	re.compile(r"^([+\-]?)(\d+(?:\.\d+)?)(%?)$")
	var m := re.search(text)
	if m == null:
		return text
	var v := float(m.get_string(2)) * mult
	if m.get_string(3) == "%":
		return "%s%.1f%%" % [m.get_string(1), v]
	return "%s%d" % [m.get_string(1), int(v)]


static func compute_gear_power() -> float:
	var mults: Dictionary = Balance.value("power.gear_rarity_mult", {})
	var ilvl_w := Balance.num("power.gear_ilvl_w", 110.0)
	var power := 0.0
	for item_v in GameState.equipped:
		if item_v == null:
			continue
		var item: Dictionary = item_v
		power += float(item["ilvl"]) / 80.0 * ilvl_w * float(mults.get(String(item["r"]), 1.0))
	var base_level := Balance.inum("forge.base_level", 7)
	power += float(GameState.forge_level - base_level) * Balance.num("power.forge_power_per_level", 900.0)
	return power


## "4.82M"-style label.
static func format_dps(dps: float) -> String:
	if dps >= 1_000_000_000.0:
		return "%.2fB" % (dps / 1_000_000_000.0)
	if dps >= 1_000_000.0:
		return "%.2fM" % (dps / 1_000_000.0)
	if dps >= 1_000.0:
		return "%.1fK" % (dps / 1_000.0)
	return str(int(dps))


static var _tree_cache: Dictionary = {}

static func _tree() -> Dictionary:
	if _tree_cache.is_empty():
		_tree_cache = GameContent.build_tree()
	return _tree_cache
