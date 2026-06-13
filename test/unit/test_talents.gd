extends GutTest
## Talent tree: PoE-style breadth. Every NOTABLE / KEYSTONE in the built tree
## must be UNIQUE (no two nodes share a name), there should be many of them,
## and their effects must be mechanically real (StatBlock parses them).


func test_tree_has_many_unique_notables() -> void:
	var tree := GameContent.build_tree()
	var notable_names: Array = []
	var keystone_names: Array = []
	for node in tree["nodes"]:
		match String(node["type"]):
			"notable":
				notable_names.append(String(node["label"]))
			"keystone":
				keystone_names.append(String(node["label"]))

	assert_gt(notable_names.size(), 12, "the tree is full of distinct notable skills")
	# Unique: no repeated notable name anywhere in the tree.
	var seen := {}
	for n in notable_names:
		assert_false(seen.has(n), "notable '%s' appears only once" % n)
		seen[n] = true
	# One keystone per arm, all distinct.
	assert_eq(keystone_names.size(), GameContent.ARMS.size(), "one keystone per arm")
	var kseen := {}
	for k in keystone_names:
		assert_false(kseen.has(k), "keystone '%s' is unique" % k)
		kseen[k] = true


func test_notable_effects_are_mechanically_real() -> void:
	# Each notable's leading "+X% Y / +X Y" clauses must apply to a StatBlock
	# (trailing prose is flavor the parser ignores).
	var applied := 0
	for arm in GameContent.NOTABLE:
		for nb in GameContent.NOTABLE[arm]:
			var block := StatBlock.new()
			block.apply_effect(String(nb[1]))
			if block.flat.size() + block.inc.size() > 0:
				applied += 1
	# All 60 notables carry at least one parseable stat clause.
	assert_eq(applied, 60, "every notable grants a real stat")


func test_allocated_notable_changes_player_power() -> void:
	GameState.reset_to_defaults()
	var tree := GameContent.build_tree()
	# Find a notable node and allocate it; power must move.
	var notable_id := -1
	for node in tree["nodes"]:
		if String(node["type"]) == "notable":
			notable_id = int(node["id"])
			break
	assert_gt(notable_id, -1, "the tree has a notable to allocate")
	PlayerStats.invalidate()
	var before := float(PlayerStats.compute()["total_power"])
	GameState.talents_allocated.append(notable_id)
	PlayerStats.invalidate()
	var after := float(PlayerStats.compute()["total_power"])
	assert_ne(after, before, "allocating a notable changes total power")
	GameState.reset_to_defaults()
