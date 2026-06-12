extends GutTest
## Battlefield chest lifecycle regression: a chest that scrolls off behind the
## party must unregister its glow pulse the moment its node is freed —
## otherwise the next _process casts a freed object (caught live via MCP).


func before_each() -> void:
	GameState.reset_to_defaults()


func after_all() -> void:
	GameState.reset_to_defaults()


func test_scrolled_off_chest_unregisters_its_pulse() -> void:
	var bf: Control = load("res://scenes/fight/Battlefield.gd").new()
	add_child_autofree(bf)
	bf.size = Vector2(1600, 900)
	await get_tree().process_frame

	bf._spawn_chest()
	assert_eq(bf._chests.size(), 1, "one cache spawned")
	var glow: Object = bf._chests[0]["glow"]

	# Drag it off behind the party and let the world-scroll pass collect it.
	bf._chests[0]["pct"] = Vector2(-20.0, 50.0)
	bf._scroll_world(Vector2.ZERO, Vector2.ZERO, 0.016)
	assert_eq(bf._chests.size(), 0, "off-screen cache despawns")
	for p in bf._pulses:
		assert_ne(p["node"], glow, "the glow pulse is unregistered with it")

	# The freed node must never be cast again by the pulse loop.
	await get_tree().process_frame
	await get_tree().process_frame
	bf._process(0.016)
	pass_test("no freed-object cast in _process")


func test_despawn_chest_is_idempotent() -> void:
	var bf: Control = load("res://scenes/fight/Battlefield.gd").new()
	add_child_autofree(bf)
	bf.size = Vector2(1600, 900)
	await get_tree().process_frame

	bf._spawn_chest()
	var entry: Dictionary = bf._chests[0]
	bf._despawn_chest(entry, false)
	bf._despawn_chest(entry, false)  # second call must be a no-op
	assert_eq(bf._chests.size(), 0)
	pass_test("double despawn does not double-free")
