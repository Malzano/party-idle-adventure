extends GutTest
## Battlefield chest lifecycle regression: a chest that scrolls off behind the
## party must unregister its glow pulse the moment its node is freed —
## otherwise the next _process casts a freed object (caught live via MCP).


func before_each() -> void:
	GameState.reset_to_defaults()
	GameState.class_id = "mage"  # a ranged class so projectile paths are exercised


func after_all() -> void:
	GameState.reset_to_defaults()


func _bf() -> Control:
	var bf := load("res://scenes/fight/Battlefield.gd").new() as Control
	add_child_autofree(bf)
	bf.size = Vector2(1600, 900)
	return bf


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


# --- Feature 3a: floor-1 start ----------------------------------------------

func test_default_profile_starts_at_floor_1_1() -> void:
	GameState.reset_to_defaults()
	assert_eq(GameState.act, 1)
	assert_eq(GameState.stage, 1)
	assert_eq(GameState.max_stage, 101, "max_stage encodes act*100 + stage")
	assert_eq(Balance.floor_index(1, 1), 1, "1-1 is floor 1")
	assert_eq(Balance.wave_kind(1, 1, 1), "normal", "floor 1 wave 1 is not a boss")


# --- Feature 3b: floor-aware roster -----------------------------------------

func test_enemy_roster_is_floor_themed_and_wraps() -> void:
	var f1: Dictionary = GameContent.enemy_roster_for_floor(1)
	assert_true(f1.has("elite") and f1.has("trash"), "roster carries an elite + trash names")
	assert_false((f1["trash"] as Array).is_empty())
	var n := GameContent.ENEMY_ROSTER.size()
	assert_eq(GameContent.enemy_roster_for_floor(n + 1), GameContent.enemy_roster_for_floor(1), "wraps per floor count")


# --- Feature 1: hero focusing -----------------------------------------------

func test_focus_prefers_engaged_over_nearer_approacher() -> void:
	var bf := _bf()
	await get_tree().process_frame
	bf.set_process(false)
	var en: Array = bf._enemies
	en[0]["state"] = "engaged"
	en[0]["pct"] = Vector2(60, 30)   # engaged but far
	en[1]["state"] = "approach"
	en[1]["pct"] = Vector2(26, 66)   # approaching but right on the party
	bf._focus = {}
	bf._retarget_focus()
	assert_true(is_same(bf._focus, en[0]), "an engaged token outranks a nearer approacher")


func test_focus_is_sticky_until_invalid() -> void:
	var bf := _bf()
	await get_tree().process_frame
	bf.set_process(false)
	var en: Array = bf._enemies
	en[0]["state"] = "engaged"
	en[1]["state"] = "engaged"
	en[1]["pct"] = Vector2(25, 66)   # nearer than en[0]
	bf._focus = en[0]
	bf._retarget_focus()
	assert_true(is_same(bf._focus, en[0]), "keeps the current focus even if another is nearer")


func test_on_enemy_killed_drops_focus_first() -> void:
	var bf := _bf()
	await get_tree().process_frame
	bf.set_process(false)
	var en: Array = bf._enemies
	en[0]["state"] = "engaged"
	bf._focus = en[0]
	bf._on_enemy_killed()
	assert_eq(String(en[0]["state"]), "dying", "the focused token is the one that dies")
	assert_true((bf._focus as Dictionary).is_empty(), "focus cleared → retargets next frame")


func test_focus_handles_empty_lineup() -> void:
	var bf := _bf()
	await get_tree().process_frame
	bf.set_process(false)
	bf._hero_units.clear()
	bf._face_hero_at_focus()  # must not crash with no hero
	pass_test("facing with an empty lineup is a no-op")


# --- Feature 2: projectiles --------------------------------------------------

func test_spec_ranged_by_class() -> void:
	assert_true(bool(GameContent.projectile_spec("mage")["ranged"]), "mage is ranged")
	assert_true(bool(GameContent.projectile_spec("hunter")["ranged"]), "hunter is ranged")
	assert_false(bool(GameContent.projectile_spec("warrior")["ranged"]), "warrior is melee")
	assert_false(bool(GameContent.projectile_spec("rogue")["ranged"]), "rogue is melee")
	assert_eq(String(GameContent.projectile_spec("mage", {"color_key": "gold"})["color_key"]), "gold", "override hook wins")


func test_mage_fires_a_projectile_at_the_focus() -> void:
	var bf := _bf()
	await get_tree().process_frame
	bf.set_process(false)
	bf._enemies[0]["state"] = "engaged"
	bf._focus = bf._enemies[0]
	bf._fire_projectile(GameContent.projectile_spec("mage"))
	assert_eq((bf._projectiles as Array).size(), 1, "a mage shot spawned")


func test_projectile_count_is_capped() -> void:
	var bf := _bf()
	await get_tree().process_frame
	bf.set_process(false)
	bf._enemies[0]["state"] = "engaged"
	bf._focus = bf._enemies[0]
	for i in bf.MAX_PROJECTILES + 8:
		bf._fire_projectile(GameContent.projectile_spec("mage"))
	assert_lte((bf._projectiles as Array).size(), bf.MAX_PROJECTILES, "never exceeds the hard cap")


func test_projectiles_cleared_on_lineup_swap() -> void:
	var bf := _bf()
	await get_tree().process_frame
	bf.set_process(false)
	bf._enemies[0]["state"] = "engaged"
	bf._focus = bf._enemies[0]
	bf._fire_projectile(GameContent.projectile_spec("mage"))
	bf._spawn_party_heroes()  # a lineup rebuild frees the hero origin
	assert_eq((bf._projectiles as Array).size(), 0, "in-flight shots dropped on a lineup swap")
	assert_true((bf._focus as Dictionary).is_empty(), "focus reset on a lineup swap")


# --- Feature 3c: boss-wave reaction -----------------------------------------

func test_boss_started_spawns_one_token_and_targets_it() -> void:
	var bf := _bf()
	await get_tree().process_frame
	bf.set_process(false)
	var before: int = (bf._enemies as Array).size()
	EventBus.sim_boss_started.emit("boss", "The Bone Warden", "boss", 9000.0)
	assert_false((bf._boss_entry as Dictionary).is_empty(), "a boss token is on the field")
	assert_true(is_same(bf._focus, bf._boss_entry), "the hero targets the boss")
	assert_eq((bf._enemies as Array).size(), before + 1, "exactly one boss token added")


func test_boss_defeated_removes_the_token() -> void:
	var bf := _bf()
	await get_tree().process_frame
	bf.set_process(false)
	EventBus.sim_boss_started.emit("boss", "Embermaw", "boss", 9000.0)
	EventBus.sim_boss_defeated.emit("boss")
	assert_true((bf._boss_entry as Dictionary).is_empty(), "boss token cleared on defeat")


# --- Discrete waves: clear the field, then the next wave marches in ----------

func test_normal_wave_advance_stages_a_full_batch() -> void:
	var bf := _bf()
	await get_tree().process_frame
	bf.set_process(false)
	CombatSim.act = 1
	CombatSim.stage = 1
	CombatSim.wave = 2  # a normal wave (sub-stage 1, not a boss)
	bf._respawn_at.clear()
	bf._on_sim_wave_advanced(2)
	assert_eq(bf._respawn_at.size(), Balance.inum("enemy.per_wave", 8),
		"a normal wave advance stages a full fresh batch of minions")
	# Every living straggler from the previous wave is being cleared.
	for e in bf._enemies:
		assert_eq(String(e["state"]), "dying", "the previous wave's minions are cleared first")


func test_boss_wave_advance_does_not_stage_trash() -> void:
	var bf := _bf()
	await get_tree().process_frame
	bf.set_process(false)
	CombatSim.act = 1
	CombatSim.stage = 10  # floor-boss sub-stage
	CombatSim.wave = Balance.inum("enemy.waves_per_stage", 5)  # the boss wave
	bf._respawn_at.clear()
	bf._on_sim_wave_advanced(CombatSim.wave)
	assert_eq(bf._respawn_at.size(), 0, "a boss wave refills no trash (the boss token spawns separately)")


func test_kill_does_not_respawn_mid_wave() -> void:
	var bf := _bf()
	await get_tree().process_frame
	bf.set_process(false)
	bf._respawn_at.clear()
	bf._enemies[0]["state"] = "engaged"
	bf._focus = bf._enemies[0]
	bf._on_enemy_killed()
	assert_eq(bf._respawn_at.size(), 0,
		"no mid-wave respawn — the field refills only when the wave advances")
