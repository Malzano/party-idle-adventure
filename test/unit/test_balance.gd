extends GutTest
## Balance: typed access to data/balance.json + derived helpers.


func test_stage_index_act4_stage7_is_157() -> void:
	assert_eq(Balance.stage_index(4, 7), 157, "(4-1)*50 + 7 == 157")
	assert_eq(Balance.stage_index(1, 1), 1, "act 1 stage 1 is global index 1")


func test_wave_pool_growth_is_monotonic() -> void:
	for i in range(1, 60):
		assert_lt(Balance.wave_pool(i), Balance.wave_pool(i + 1),
			"wave pool must strictly grow with stage index (index %d)" % i)


func test_forge_gold_cost_at_base_level() -> void:
	assert_eq(Balance.forge_gold_cost(7), 4200, "cost at the base level is gold_base")


func test_forge_gold_cost_growth() -> void:
	assert_eq(Balance.forge_gold_cost(8), int(4200.0 * 1.6), "one level above base scales by gold_growth")


func test_num_missing_path_returns_default() -> void:
	assert_eq(Balance.num("nonexistent.section.key", 42.5), 42.5)
	assert_eq(Balance.inum("forge.no_such_key", 7), 7)
	assert_eq(Balance.value("totally.absent", "fallback"), "fallback")


func test_num_reads_real_values() -> void:
	assert_eq(Balance.num("enemy.base_pool", -1.0), 1500.0)
	assert_eq(Balance.inum("enemy.stages_per_act", -1), 50)
	assert_eq(Balance.inum("rewards.offline_cap_hours", -1), 12)


# --- Floors, sub-stages & bosses --------------------------------------------

func test_stage_index_multiplier_is_frozen() -> void:
	# stages_per_act MUST stay 50 — it is the server-shared stage-index unit.
	assert_eq(Balance.inum("enemy.stages_per_act", -1), 50)
	assert_eq(Balance.stage_index(4, 7), 157, "floor restructure must not change the index math")


func test_floor_and_substage_mapping() -> void:
	# 50 stages_per_act / 10 substages_per_floor → 5 floors per act.
	assert_eq(Balance.floor_index(1, 1), 1)
	assert_eq(Balance.substage_in_floor(1, 1), 1)
	assert_eq(Balance.floor_index(1, 10), 1)
	assert_eq(Balance.substage_in_floor(1, 10), 10)
	assert_eq(Balance.floor_index(1, 11), 2)
	assert_eq(Balance.substage_in_floor(1, 11), 1)
	# The first 10 floors span acts 1-2 (act 2 stage 1 = global floor 6).
	assert_eq(Balance.floor_index(2, 1), 6)


func test_wave_kind_classification() -> void:
	var wps := Balance.inum("enemy.waves_per_stage", 5)
	# Mini-boss on the final wave of sub-stage 5; floor boss on sub-stage 10.
	assert_eq(Balance.wave_kind(1, 5, wps), "miniboss")
	assert_eq(Balance.wave_kind(1, 10, wps), "boss")
	# Earlier waves of a boss sub-stage stay normal trash.
	assert_eq(Balance.wave_kind(1, 5, wps - 1), "normal")
	assert_eq(Balance.wave_kind(1, 10, wps - 1), "normal")
	# Non-boss sub-stages are always normal.
	assert_eq(Balance.wave_kind(1, 1, wps), "normal")
	assert_eq(Balance.wave_kind(1, 3, wps), "normal")
	# Sub-stage index wraps per floor: stage 15 → sub-stage 5, stage 20 → 10.
	assert_eq(Balance.wave_kind(1, 15, wps), "miniboss")
	assert_eq(Balance.wave_kind(1, 20, wps), "boss")


func test_boss_multipliers() -> void:
	assert_gt(Balance.boss_hp_mult("boss"), Balance.boss_hp_mult("miniboss"))
	assert_gt(Balance.boss_hp_mult("miniboss"), 1.0)
	assert_eq(Balance.boss_hp_mult("normal"), 1.0)
	assert_eq(Balance.boss_reward_mult("normal"), 1.0)
	assert_gt(Balance.boss_reward_mult("boss"), Balance.boss_reward_mult("miniboss"))
	assert_gt(Balance.boss_reward_mult("miniboss"), 1.0)


func test_boss_skill_helpers() -> void:
	var kit := Balance.boss_kit("boss")
	assert_false(kit.is_empty(), "boss kit loads from bosses.json")
	# No mitigation / no enrage before the windows start.
	assert_eq(Balance.boss_dps_mult(kit, 0.0), 1.0)
	assert_eq(Balance.boss_enrage_factor(kit, 0.0), 0.0)
	# Enrage ramps after its start and is capped.
	var late := Balance.boss_enrage_factor(kit, 1.0e6)
	assert_almost_eq(late, float((kit["enrage"] as Dictionary)["cap"]), 0.0001)
	# DPS is reduced inside the shield window.
	var start := float((kit["shield"] as Dictionary)["start"])
	assert_lt(Balance.boss_dps_mult(kit, start + 0.01), 1.0)
