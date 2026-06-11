extends GutTest
## CombatSim: offline fast-forward math, cap, dungeon gold rush, wave fill.

const HOUR := 3600


func before_all() -> void:
	# Freeze the live sim so ticks cannot mutate state mid-assert.
	CombatSim.set_process(false)


func before_each() -> void:
	GameState.reset_to_defaults()
	PlayerStats.invalidate()
	CombatSim.act = 4
	CombatSim.stage = 7
	CombatSim.wave = 1
	CombatSim._recompute_stats()


func after_all() -> void:
	GameState.reset_to_defaults()
	PlayerStats.invalidate()
	CombatSim.act = GameState.act
	CombatSim.stage = GameState.stage
	CombatSim.wave = 1
	CombatSim._recompute_stats()
	CombatSim._reset_wave()
	CombatSim.set_process(true)


func test_party_dps_is_live() -> void:
	assert_gt(CombatSim.party_dps, 0.0, "sim must price the party from PlayerStats")
	assert_ne(CombatSim.party_dps_label, "0")


func test_simulate_offline_is_deterministic() -> void:
	var a := CombatSim.simulate_offline(HOUR)
	var b := CombatSim.simulate_offline(HOUR)
	assert_eq_deep(a, b)


func test_simulate_offline_respects_12h_cap() -> void:
	var d14 := CombatSim.simulate_offline(14 * HOUR)
	var d12 := CombatSim.simulate_offline(12 * HOUR)
	# "seconds" echoes the raw input; every earned reward must be identical.
	var a := d14.duplicate()
	var b := d12.duplicate()
	a.erase("seconds")
	b.erase("seconds")
	assert_eq_deep(a, b)
	assert_eq(int(d14["seconds"]), 14 * HOUR, "raw input seconds are echoed back")


func test_simulate_offline_grows_with_time() -> void:
	var d1 := CombatSim.simulate_offline(HOUR)
	var d2 := CombatSim.simulate_offline(2 * HOUR)
	assert_gt(int(d1["waves"]), 0, "an hour at stage 4-7 must clear waves")
	assert_gt(int(d2["gold"]), int(d1["gold"]), "more time away → more gold")
	assert_gt(int(d2["waves"]), int(d1["waves"]), "more time away → more waves")


func test_wave_gold_reward_applies_dungeon_gold_rush() -> void:
	var s_index := Balance.stage_index(4, 7)
	GameState.dungeon_buff_until = 0
	var unbuffed := CombatSim.wave_gold_reward(s_index)
	assert_gt(unbuffed, 0)

	GameState.dungeon_buff_until = GameState.now_utc() + 60
	var buffed := CombatSim.wave_gold_reward(s_index)
	GameState.dungeon_buff_until = 0

	var mult := Balance.num("energy.dungeon_gold_mult", 3.0)
	assert_almost_eq(float(buffed) / float(unbuffed), mult, 0.02,
		"gold rush should multiply wave gold by ~%.1f×" % mult)


func test_wave_fill_is_clamped_percentage() -> void:
	CombatSim.wave_pool = 200.0
	CombatSim.wave_damage = 50.0
	assert_almost_eq(CombatSim.wave_fill(), 25.0, 0.0001)
	CombatSim.wave_damage = 1000.0
	assert_eq(CombatSim.wave_fill(), 100.0, "fill clamps at 100%")
	CombatSim._reset_wave()
	assert_eq(CombatSim.wave_fill(), 0.0, "fresh wave starts at 0%")
