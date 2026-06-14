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
	CombatSim._wave_kind = "normal"
	assert_almost_eq(CombatSim.wave_fill(), 25.0, 0.0001)
	CombatSim.wave_damage = 1000.0
	assert_eq(CombatSim.wave_fill(), 100.0, "fill clamps at 100%")
	CombatSim._reset_wave()
	assert_eq(CombatSim.wave_fill(), 0.0, "fresh wave starts at 0%")


# --- Bosses: live/offline parity + no-stall ---------------------------------

func test_floor_boss_clear_matches_live_tick() -> void:
	# The live tick and the offline sim must clear a boss in the SAME number of
	# ticks at EVERY DPS — the kit's skill windows fall on integer-second
	# boundaries (enrage 20s, shield 9s / period 15s), so an accumulating float
	# clock would drift across a boundary at some DPS and diverge. Sweep several
	# DPS values whose clear times cross those boundaries differently.
	var kit := Balance.boss_kit("boss")
	var cap := Balance.boss_time_cap()
	var wps := Balance.inum("enemy.waves_per_stage", 5)
	for div: float in [20.0, 28.0, 30.0, 37.0, 45.0]:
		GameState.reset_to_defaults()
		CombatSim.act = 1
		CombatSim.stage = 10  # floor-boss sub-stage
		CombatSim.wave = wps  # final wave
		CombatSim._reset_wave()
		assert_eq(CombatSim._wave_kind, "boss", "stage 10 final wave is the floor boss")

		var pool := CombatSim.wave_pool
		var dps := pool / div
		CombatSim.party_dps = dps
		var off_secs := CombatSim._boss_clear_secs(pool, kit, dps)
		assert_gt(off_secs, 9.0, "fight crosses at least the shield window")
		assert_lt(off_secs, cap, "on-curve DPS clears before the cap")

		# Live: re-arm the same boss wave and tick until defeated; count ticks.
		CombatSim.wave = wps
		CombatSim._reset_wave()
		var defeated := [false]
		var cb := func(_id: String) -> void: defeated[0] = true
		EventBus.sim_boss_defeated.connect(cb)
		var ticks := 0
		var guard := int(cap * CombatSim.TICK_RATE) + 5
		while not defeated[0] and ticks < guard:
			CombatSim._tick()
			ticks += 1
		EventBus.sim_boss_defeated.disconnect(cb)

		var live_secs := float(ticks) / CombatSim.TICK_RATE
		assert_almost_eq(live_secs, off_secs, 0.0001,
			"live vs offline boss clear must match exactly at dps=pool/%.0f" % div)


func test_follow_mode_mirrors_session_without_persisting() -> void:
	# Stage 5: a follower renders the leader's shared position but never advances
	# or persists — its own saved act/stage stay put for when the delve ends.
	GameState.reset_to_defaults()
	GameState.act = 4
	GameState.stage = 7
	CombatSim.act = 4
	CombatSim.stage = 7
	CombatSim.wave = 1
	CombatSim._reset_wave()

	CombatSim.set_follow_mode(true)
	assert_true(CombatSim.follow_mode, "follower mode engaged")

	CombatSim.apply_session({"act": 5, "stage": 12, "wave": 3, "wave_fill": 50.0})
	assert_eq(CombatSim.act, 5, "follower displays the party's act")
	assert_eq(CombatSim.stage, 12, "follower displays the party's stage")
	assert_eq(CombatSim.wave, 3)
	assert_almost_eq(CombatSim.wave_fill(), 50.0, 0.5, "follower shows the shared wave progress")
	# The player's OWN saved position is untouched.
	assert_eq(GameState.act, 4, "the follower's own act is NOT changed by the delve")
	assert_eq(GameState.stage, 7, "the follower's own stage is NOT changed by the delve")

	# Leaving the delve restores the player's own solo position.
	CombatSim.set_follow_mode(false)
	assert_false(CombatSim.follow_mode)
	assert_eq(CombatSim.act, 4, "solo resumes from the player's own act")
	assert_eq(CombatSim.stage, 7, "solo resumes from the player's own stage")


func test_boss_never_stalls() -> void:
	var cap := Balance.boss_time_cap()
	for kind in ["miniboss", "boss"]:
		var kit := Balance.boss_kit(kind)
		var pool := 1.0e9  # an absurd pool no weak party can chew through
		# Tiny DPS: force-clears at the cap (slowed, never walled).
		var weak := CombatSim._boss_clear_secs(pool, kit, 1.0)
		assert_almost_eq(weak, cap, 0.0001,
			"%s force-clears at the time cap for a too-weak party" % kind)
		# Ample DPS: clears well before the cap.
		var strong := CombatSim._boss_clear_secs(pool, kit, pool)
		assert_gt(strong, 0.0)
		assert_lt(strong, cap, "%s clears quickly at high DPS" % kind)
