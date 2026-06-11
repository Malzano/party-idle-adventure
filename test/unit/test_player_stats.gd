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


func test_team_aura_optimal_for_default_party() -> void:
	assert_true(PlayerStats.team_aura_optimal(),
		"1 tank + 1 healer + 2 different DPS classes should activate the aura")


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
