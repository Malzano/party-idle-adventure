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
