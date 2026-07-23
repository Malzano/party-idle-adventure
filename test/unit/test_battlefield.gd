extends GutTest
## 2D side-scroller battlefield: lifecycle + coherence regressions. Positions are
## a scalar x (0..1 of width; smaller = nearer the hero) + a lane index. Combat
## truth lives in CombatSim; this layer renders a coherent readout of it.


func before_each() -> void:
	GameState.reset_to_defaults()
	GameState.class_id = "mage"  # a ranged class so projectile paths are exercised
	CombatSim.act = 1
	CombatSim.stage = 1
	CombatSim.wave = 1


func after_all() -> void:
	GameState.reset_to_defaults()


func _bf() -> Control:
	var bf := load("res://scenes/fight/Battlefield.gd").new() as Control
	add_child_autofree(bf)
	bf.size = Vector2(1600, 900)
	return bf


# --- Freed-object hygiene -----------------------------------------------------

func test_scrolled_off_chest_unregisters_its_pulse() -> void:
	var bf := _bf()
	await get_tree().process_frame
	bf.set_process(false)

	bf._spawn_chest()
	assert_eq(bf._chests.size(), 1, "one cache spawned")
	var glow: Object = bf._chests[0]["glow"]

	# Drag it off behind the party and let the parallax scroll collect it.
	bf._chests[0]["x"] = -0.2
	bf._scroll_parallax(0.016, 1.0)
	assert_eq(bf._chests.size(), 0, "off-screen cache despawns")
	for p in bf._pulses:
		assert_ne(p["node"], glow, "the glow pulse is unregistered with it")

	# The freed node must never be cast again by the pulse loop.
	await get_tree().process_frame
	await get_tree().process_frame
	bf._process(0.016)
	pass_test("no freed-object cast in _process")


func test_lineup_swap_reclaims_hero_bobs() -> void:
	var bf := _bf()
	await get_tree().process_frame
	bf.set_process(false)

	assert_eq(bf._hero_units.size(), 1, "1 account = 1 character on the field")
	assert_eq(bf._hero_units.size(), GameContent.active_party().size(), "matches active_party")
	var old_sprite: Object = bf._hero_units[0].get_meta("sprite")

	EventBus.lineup_changed.emit()  # e.g. a 409 server-save adoption rebuilds
	await get_tree().process_frame  # deferred connection fires
	await get_tree().process_frame

	for b in bf._bobs:
		assert_ne(b["node"], old_sprite, "the freed hero's bob is unregistered")
	assert_false(is_instance_valid(old_sprite), "old hero sprite was freed")

	bf._process(0.016)
	pass_test("no freed-object cast after lineup swap")


func test_render_path_ticks_without_error() -> void:
	# Drive real frames (process enabled) through whichever render path the USE_3D
	# flag selects: the 2.5D world (_render3d_fight + projected _pos_ground + look_at)
	# when on, or the 2D side-scroller when off. Either way the scene must tick cleanly,
	# and the 3D world must exist iff the flag is on.
	var bf := _bf()
	for _i in 10:
		await get_tree().process_frame
	assert_eq(bf._world3d != null, bf.USE_3D, "the 2.5D world is built iff USE_3D is on")
	assert_gt(bf._enemies.size(), 0, "the field opens populated and keeps ticking")
	pass_test("the fight render path ticks cleanly")


func test_despawn_chest_is_idempotent() -> void:
	var bf := _bf()
	await get_tree().process_frame
	bf.set_process(false)

	bf._spawn_chest()
	var entry: Dictionary = bf._chests[0]
	bf._despawn_chest(entry, false)
	bf._despawn_chest(entry, false)  # second call must be a no-op
	assert_eq(bf._chests.size(), 0)
	pass_test("double despawn does not double-free")


# --- Floor-1 start + floor roster (data) -------------------------------------

func test_default_profile_starts_at_floor_1_1() -> void:
	GameState.reset_to_defaults()
	assert_eq(GameState.act, 1)
	assert_eq(GameState.stage, 1)
	assert_eq(GameState.max_stage, 101, "max_stage encodes act*100 + stage")
	assert_eq(Balance.floor_index(1, 1), 1, "1-1 is floor 1")
	assert_eq(Balance.wave_kind(1, 1, 1), "normal", "floor 1 wave 1 is not a boss")


func test_enemy_roster_is_floor_themed_and_wraps() -> void:
	var f1: Dictionary = GameContent.enemy_roster_for_floor(1)
	assert_true(f1.has("elite") and f1.has("trash"), "roster carries an elite + trash names")
	assert_false((f1["trash"] as Array).is_empty())
	var n := GameContent.ENEMY_ROSTER.size()
	assert_eq(GameContent.enemy_roster_for_floor(n + 1), GameContent.enemy_roster_for_floor(1), "wraps per floor count")


# --- Hero focusing (nearest = smallest x; engaged outranks approaching) -------

func test_focus_prefers_engaged_over_nearer_approacher() -> void:
	var bf := _bf()
	await get_tree().process_frame
	bf.set_process(false)
	var en: Array = bf._enemies
	en[0]["state"] = "engaged"
	en[0]["x"] = 0.62   # engaged but far
	en[1]["state"] = "approach"
	en[1]["x"] = 0.42   # approaching but right on the party
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
	en[1]["x"] = 0.25   # nearer than en[0]
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


func test_kill_with_no_engaged_foe_is_deferred() -> void:
	var bf := _bf()
	await get_tree().process_frame
	bf.set_process(false)
	# Initial spawns are all approaching — a sim kill must NOT snipe one mid-runway.
	for e in bf._enemies:
		e["state"] = "approach"
	bf._pending_kills = 0
	bf._on_enemy_killed()
	assert_eq(bf._pending_kills, 1, "a kill with no engaged foe is held, not applied to an approacher")
	for e in bf._enemies:
		assert_ne(String(e["state"]), "dying", "no approacher was sniped")
	# Once a foe engages, the held kill drains onto it.
	bf._enemies[0]["state"] = "engaged"
	assert_true(bf._kill_engaged_victim(), "the held kill lands on the engaged foe")
	assert_eq(String(bf._enemies[0]["state"]), "dying", "the engaged foe dies at the clash")


func test_in_combat_freezes_travel_state() -> void:
	var bf := _bf()
	await get_tree().process_frame
	bf.set_process(false)
	for e in bf._enemies:
		e["state"] = "approach"
	assert_false(bf._in_combat(), "approaching foes only → the party is still traveling")
	bf._enemies[0]["state"] = "engaged"
	assert_true(bf._in_combat(), "an engaged foe → in combat (background + hero walk freeze)")
	# A boss also counts as combat.
	bf._enemies[0]["state"] = "approach"
	EventBus.sim_boss_started.emit("miniboss", "Marrow Knight", "miniboss", 6000.0)
	assert_true(bf._in_combat(), "a boss on the field → in combat")


func test_focus_handles_empty_lineup() -> void:
	var bf := _bf()
	await get_tree().process_frame
	bf.set_process(false)
	bf._hero_units.clear()
	bf._face_hero_at_focus()  # must not crash with no hero
	pass_test("facing with an empty lineup is a no-op")


# --- Projectiles --------------------------------------------------------------

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


# --- Approach → engage → stop at the clash line -------------------------------

func test_approach_stops_at_the_clash_line() -> void:
	var bf := _bf()
	await get_tree().process_frame
	bf.set_process(false)
	# A fresh foe far to the right walks in and must STOP at its engage slot —
	# never overrun toward the hero at HERO_X.
	bf._enemies.clear()
	bf._spawn_enemy(false)
	var e: Dictionary = bf._enemies[0]
	assert_eq(String(e["state"]), "approach", "spawns approaching from the right")
	for _i in 200:
		bf._update_enemies(0.1, 4.0)
	assert_eq(String(e["state"]), "engaged", "reaches the clash line and engages")
	assert_almost_eq(float(e["x"]), float(e["engage_x"]), 0.01, "stops exactly at its engage slot")
	assert_gt(float(e["x"]), bf.HERO_X, "never overruns the hero")


func test_enemies_spread_across_lanes() -> void:
	var bf := _bf()
	await get_tree().process_frame
	bf.set_process(false)
	var lanes := {}
	for e in bf._enemies:
		if not bool(e["elite"]):
			lanes[int(e["lane"])] = true
	assert_gt(lanes.size(), 1, "trash spreads across more than one lane (no single-file stack)")


# --- Coherent attacks: range gating + impact mints a number + drains HP -------

func test_melee_waits_for_range_then_strikes() -> void:
	var bf := _bf()
	await get_tree().process_frame
	bf.set_process(false)
	GameState.class_id = "warrior"  # melee: must wait for the foe to arrive
	var e: Dictionary = bf._enemies[0]

	# Out of reach (still approaching far to the right): no strike.
	e["state"] = "approach"
	e["x"] = 0.7
	e["hp_pct"] = 100.0
	bf._focus = e
	bf._fire_accum = bf.FIRE_INTERVAL + 0.01
	bf._update_attack_cadence(0.0, 1.0)
	assert_almost_eq(float(e["hp_pct"]), 100.0, 0.01, "a melee hero does NOT hit a foe that is out of range")

	# In reach (engaged at the clash line): it strikes.
	e["state"] = "engaged"
	e["x"] = bf.CLASH_X
	bf._fire_accum = bf.FIRE_INTERVAL + 0.01
	bf._update_attack_cadence(0.0, 1.0)
	assert_lt(float(e["hp_pct"]), 100.0, "once the foe is in range the melee hero strikes it")


func test_impact_mints_a_number_and_drains_the_target() -> void:
	var bf := _bf()
	await get_tree().process_frame
	bf.set_process(false)
	var e: Dictionary = bf._enemies[0]
	e["state"] = "engaged"
	e["hp_pct"] = 100.0
	var floaters_before: int = bf._floater_holder.get_child_count()
	bf._on_impact(e, GameContent.projectile_spec("mage"), Vector2(800.0, 500.0))
	assert_lt(float(e["hp_pct"]), 100.0, "a landed hit drains the struck foe's cosmetic HP")
	# The damage number is anchored on the target (gated on the dmg-numbers
	# setting — only assert when it's on, so the test is setting-agnostic).
	if UserSettings.get_bool("dmg_numbers"):
		assert_gt(bf._floater_holder.get_child_count(), floaters_before, "mints a number on the struck foe")


func test_cosmetic_drain_never_kills_ahead_of_the_sim() -> void:
	var bf := _bf()
	await get_tree().process_frame
	bf.set_process(false)
	var e: Dictionary = bf._enemies[0]
	e["state"] = "engaged"
	e["hp_pct"] = 100.0
	for _i in 20:  # hammer it well past empty
		bf._on_impact(e, GameContent.projectile_spec("mage"), Vector2(800.0, 500.0))
	assert_gte(float(e["hp_pct"]), bf.HP_FLOOR, "the bar floors at HP_FLOOR — only sim_enemy_killed actually kills")
	assert_eq(String(e["state"]), "engaged", "the foe is alive until the sim says otherwise")


# --- Discrete waves -----------------------------------------------------------

func test_normal_wave_advance_stages_a_full_batch() -> void:
	var bf := _bf()
	await get_tree().process_frame
	bf.set_process(false)
	CombatSim.act = 1
	CombatSim.stage = 1
	CombatSim.wave = 2  # a normal wave (sub-stage 1, not a boss)
	bf._spawn_queue.clear()
	bf._on_sim_wave_advanced(2)
	assert_eq(bf._spawn_queue.size(), Balance.wave_monster_count(1, 1, 2),
		"a normal wave advance stages this wave's full monster lineup")
	for e in bf._enemies:
		assert_eq(String(e["state"]), "dying", "the previous wave's minions are cleared first")


func test_boss_wave_advance_does_not_stage_trash() -> void:
	var bf := _bf()
	await get_tree().process_frame
	bf.set_process(false)
	CombatSim.act = 1
	CombatSim.stage = 10  # floor-boss sub-stage
	CombatSim.wave = Balance.inum("enemy.waves_per_stage", 5)  # the boss wave
	bf._spawn_queue.clear()
	bf._on_sim_wave_advanced(CombatSim.wave)
	assert_eq(bf._spawn_queue.size(), 0, "a boss wave refills no trash (the boss token spawns separately)")


func test_kill_does_not_respawn_mid_wave() -> void:
	var bf := _bf()
	await get_tree().process_frame
	bf.set_process(false)
	bf._spawn_queue.clear()
	bf._enemies[0]["state"] = "engaged"
	bf._focus = bf._enemies[0]
	bf._on_enemy_killed()
	assert_eq(bf._spawn_queue.size(), 0,
		"no mid-wave respawn — the field refills only when the wave advances")


# --- Data-driven stage definitions (auto-generated defaults) -----------------

func test_wave_monster_count_authored_default_and_boss() -> void:
	assert_eq(Balance.wave_monster_count(1, 1, 1), 4, "authored Floor 1-1 wave 1 = 4 monsters (stages.json)")
	assert_eq(Balance.wave_monster_count(2, 1, 1), Balance.inum("enemy.monsters_per_wave", 5),
		"an un-authored stage auto-generates the default monster count")
	var wps := Balance.inum("enemy.waves_per_stage", 5)
	assert_eq(Balance.wave_monster_count(1, 10, wps), 1, "a floor-boss wave is a single token")
	assert_eq(Balance.stage_theme(1, 1), "Buttercup Steps", "authored theme is read from stages.json")


func test_wave_plan_assembles_named_monsters_with_times() -> void:
	var plan := GameContent.wave_plan(1, 1, 1)
	assert_eq(plan.size(), Balance.wave_monster_count(1, 1, 1), "one plan entry per monster")
	assert_true((plan[0] as Dictionary).has("name") and (plan[0] as Dictionary).has("at"),
		"entries carry a name + spawn time")
	var wps := Balance.inum("enemy.waves_per_stage", 5)
	assert_true(GameContent.wave_plan(1, 10, wps).is_empty(), "a boss wave stages no trash plan")


# --- Boss token: HP mirrors the sim, not our cosmetic hits --------------------

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


func test_boss_bar_mirrors_sim_not_hits() -> void:
	var bf := _bf()
	await get_tree().process_frame
	bf.set_process(false)
	EventBus.sim_boss_started.emit("boss", "Embermaw", "boss", 9000.0)
	EventBus.sim_boss_hp.emit(0.5)
	var bar := bf._boss_entry["bar"] as StatBar
	assert_almost_eq(bar.pct, 50.0, 0.5, "the field boss bar mirrors sim_boss_hp")
	# An impact on the boss mints a decorative number but must NOT move its bar.
	bf._on_impact(bf._boss_entry, GameContent.projectile_spec("mage"), Vector2(900.0, 400.0))
	assert_almost_eq(bar.pct, 50.0, 0.5, "boss HP is sim-owned — cosmetic hits never drain it")
