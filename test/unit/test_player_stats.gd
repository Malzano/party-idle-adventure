extends GutTest
## PlayerStats: live profile computation from gear + talents + pets + relics.


func before_all() -> void:
	# Keep the live sim from ticking while tests assert on exact state.
	CombatSim.set_process(false)


func before_each() -> void:
	GameState.reset_to_defaults()
	PlayerStats.invalidate()


func after_all() -> void:
	GameState.reset_to_defaults()
	PlayerStats.invalidate()
	CombatSim.set_process(true)


func test_compute_returns_positive_party_dps() -> void:
	PlayerStats.invalidate()
	var profile := PlayerStats.compute()
	assert_gt(float(profile["party_dps"]), 0.0, "default loadout must produce real DPS")
	assert_ne(String(profile["dps_label"]), "", "dps label should be formatted")
	assert_gt(float(profile["total_power"]), 0.0)
	assert_gt(float(profile["gear_power"]), 0.0)


func test_party_aura_reflects_server_multiplier() -> void:
	# The local 1-tank/1-healer/2-DPS check is gone; the aura is the server's
	# real-party composition multiplier (1.0 = solo) and it scales party DPS.
	GameState.party_aura_mult = 1.0
	assert_false(PlayerStats.team_aura_optimal(), "solo: no composition aura")
	GameState.party_aura_mult = 1.2
	assert_true(PlayerStats.team_aura_optimal(), "a real-party aura activates it")

	GameState.party_aura_mult = 1.0
	PlayerStats.invalidate()
	var solo := float(PlayerStats.compute()["party_dps"])
	GameState.party_aura_mult = 1.25
	PlayerStats.invalidate()
	var partied := float(PlayerStats.compute()["party_dps"])
	assert_almost_eq(partied / solo, 1.25, 0.001, "party aura scales DPS by its multiplier")
	GameState.party_aura_mult = 1.0


func test_character_base_dps_is_class_keyed() -> void:
	GameState.party_aura_mult = 1.0
	GameState.class_id = "warrior"
	PlayerStats.invalidate()
	var w := float(PlayerStats.compute()["party_dps"])
	GameState.class_id = "mage"
	PlayerStats.invalidate()
	var m := float(PlayerStats.compute()["party_dps"])
	assert_gt(w, 0.0)
	assert_gt(m, 0.0)
	assert_ne(w, m, "different classes have different base DPS")
	GameState.class_id = ""


func test_party_dps_scales_with_character_level() -> void:
	# A fresh level-1 delver is intentionally weak (so floor 1-1 is a fight);
	# power grows with level and hits the demo-tuned base at the calibration level.
	var ref := Balance.inum("dps_model.level_ref", 47)
	assert_almost_eq(Balance.level_dps_mult(ref), 1.0, 0.0001, "calibration level = 1.0x")

	GameState.player_level = 1
	PlayerStats.invalidate()
	var lvl1 := float(PlayerStats.compute()["party_dps"])
	GameState.player_level = ref
	PlayerStats.invalidate()
	var lvl_ref := float(PlayerStats.compute()["party_dps"])
	GameState.player_level = ref + 10
	PlayerStats.invalidate()
	var lvl_hi := float(PlayerStats.compute()["party_dps"])

	assert_gt(lvl1, 0.0, "even a level-1 delver deals real DPS")
	assert_lt(lvl1, lvl_ref, "level 1 is far weaker than the calibration level")
	assert_lt(lvl_ref, lvl_hi, "DPS keeps growing past the calibration level")
	# Floor 1-1's pool must survive at least a few ticks at level 1 — not vanish
	# in one (that was the "10 stages a second" bug).
	var pool := Balance.wave_pool(Balance.stage_index(1, 1))
	assert_gt(pool / (lvl1 / CombatSim.TICK_RATE), 3.0,
		"floor 1-1 wave should take at least a few ticks for a level-1 party")


func test_extra_talent_node_never_lowers_stats() -> void:
	var tree := GameContent.build_tree()
	var nodes: Array = tree["nodes"]
	var edges: Array = tree["edges"]
	GameState.talents_allocated = GameContent.default_allocation(nodes, edges)
	PlayerStats.invalidate()
	var before := PlayerStats.compute()
	var dps_before := float(before["party_dps"])
	var power_before := float(before["total_power"])

	# Allocate the first un-allocated node adjacent to the current path.
	var extra := -1
	for e in edges:
		var a := int(e[0])
		var b := int(e[1])
		if GameState.talents_allocated.has(a) and not GameState.talents_allocated.has(b):
			extra = b
			break
		if GameState.talents_allocated.has(b) and not GameState.talents_allocated.has(a):
			extra = a
			break
	assert_gt(extra, -1, "tree must offer an adjacent unallocated node")
	GameState.talents_allocated.append(extra)
	PlayerStats.invalidate()
	var after := PlayerStats.compute()

	assert_gte(float(after["party_dps"]), dps_before, "extra node must not lower DPS")
	assert_gte(float(after["total_power"]), power_before, "extra node must not lower power")


func test_forged_weapon_stats_scale_with_forge_level() -> void:
	PlayerStats.invalidate()
	var base_pairs := PlayerStats.forged_weapon_stats()
	var base_block := StatBlock.new()
	base_block.apply_stat_pairs(base_pairs)

	GameState.forge_level += 1
	PlayerStats.invalidate()
	var up_pairs := PlayerStats.forged_weapon_stats()
	var up_block := StatBlock.new()
	up_block.apply_stat_pairs(up_pairs)

	assert_gt(up_block.get_flat("physical_dmg"), base_block.get_flat("physical_dmg"),
		"weapon damage must grow with forge level")
	assert_gt(up_block.get_flat("strength"), base_block.get_flat("strength"),
		"weapon strength must grow with forge level")


func test_forge_level_raises_total_power() -> void:
	PlayerStats.invalidate()
	var power_before := float(PlayerStats.compute()["total_power"])
	GameState.forge_level += 1
	PlayerStats.invalidate()
	var power_after := float(PlayerStats.compute()["total_power"])
	assert_gt(power_after, power_before, "forge upgrade must raise total power")
