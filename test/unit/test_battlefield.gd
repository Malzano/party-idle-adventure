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


func test_lineup_swap_reclaims_hero_bobs() -> void:
	# Swapping the fighting four frees the old hero sprites; their stride
	# bobs MUST be unregistered or the next _process casts a freed object.
	var bf: Control = load("res://scenes/fight/Battlefield.gd").new()
	add_child_autofree(bf)
	bf.size = Vector2(1600, 900)
	await get_tree().process_frame

	assert_eq(bf._hero_units.size(), 1, "1 account = 1 character on the field")
	assert_eq(bf._hero_units.size(), GameContent.active_party().size(), "matches active_party")
	var old_sprite: Object = bf._hero_units[0].get_meta("sprite")

	EventBus.lineup_changed.emit()  # e.g. a 409 server-save adoption rebuilds
	await get_tree().process_frame  # deferred connection fires
	await get_tree().process_frame

	for b in bf._bobs:
		assert_ne(b["node"], old_sprite, "the freed hero's bob is unregistered")
	assert_false(is_instance_valid(old_sprite), "old hero sprite was freed")

	# The freed sprites must never be touched by the per-frame bob loop.
	bf._process(0.016)
	pass_test("no freed-object cast after lineup swap")


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
