extends GutTest
## SURVIVAL bullet-hell: the headless SurvivalSim (deterministic combat, all-angle
## spawns, class auto-attacks, stage-clear draft, upgrades, death) + a smoke that
## the Survival scene builds and ticks without a runtime error.

const _SurvivalScene := preload("res://scenes/survival/Survival.gd")


func before_each() -> void:
	GameState.reset_to_defaults()
	GameState.choose_class("hunter", "Tester")  # ranged + stocks the bag
	PlayerStats.invalidate()


func after_all() -> void:
	GameState.reset_to_defaults()


func _run(sim: SurvivalSim, seconds: float, input := Vector2.ZERO) -> void:
	var steps := int(seconds / 0.05)
	for _i in steps:
		sim.tick(0.05, input)


func test_ranged_auto_fire_culls_enemies() -> void:
	var sim := SurvivalSim.new(PlayerStats.compute(), "hunter", 4242)
	assert_true(sim.is_ranged, "hunter is a projectile class")
	sim.max_hp = 1.0e9  # isolate offence: don't let contact end the run
	sim.hp = sim.max_hp
	_run(sim, 16.0)
	assert_gt(sim.enemies.size(), 0, "enemies pour in from every angle")
	assert_gt(sim.kills, 0, "auto-fire culls enemies over 12s")


func test_ranged_fire_still_hits_when_roamed_off_arena() -> void:
	# Regression: a roaming delver leaves the 1920×1080 arena (ROAM=2200), so bolts
	# are born past the old arena-box cull and used to vanish instantly — the hero
	# looked like it stopped attacking the moment it walked off the arena.
	var sim := SurvivalSim.new(PlayerStats.compute(), "hunter", 8181)
	sim.max_hp = 1.0e9
	sim.hp = sim.max_hp
	_run(sim, 16.0, Vector2(1, 1))  # roam hard toward the lower-right corner
	assert_true(sim.player.x > sim.ARENA.x or sim.player.y > sim.ARENA.y,
		"the delver roamed outside the arena box")
	assert_gt(sim.enemies.size(), 0, "enemies still chase the roaming delver")
	assert_gt(sim.kills, 0, "bolts still reach and kill foes off the arena (not culled at the arena edge)")


func test_melee_blade_aura_culls_enemies() -> void:
	GameState.choose_class("warrior", "Tester")
	PlayerStats.invalidate()
	var sim := SurvivalSim.new(PlayerStats.compute(), "warrior", 99)
	assert_false(sim.is_ranged, "warrior uses the blade aura")
	sim.max_hp = 1.0e9
	sim.hp = sim.max_hp
	_run(sim, 16.0)
	assert_gt(sim.kills, 0, "the blade aura culls enemies it sweeps over")


func test_stage_clear_offers_three_upgrades_then_advances() -> void:
	var sim := SurvivalSim.new(PlayerStats.compute(), "hunter", 7)
	sim.max_hp = 1.0e9
	sim.hp = sim.max_hp
	_run(sim, sim.STAGE_SECONDS + 0.5)
	assert_true(sim.awaiting_upgrade, "clearing a stage pauses for the draft")
	var offer := sim.offer_upgrades()
	assert_eq(offer.size(), 3, "exactly three enhancement choices")
	var before := sim.base_hit
	sim.choose_upgrade("dmg")
	assert_eq(sim.stage, 2, "choosing advances to the next stage")
	assert_false(sim.awaiting_upgrade, "and resumes the run")
	assert_gt(sim.base_hit, before, "the +damage enhancement applied")


func test_shape_upgrades_change_attack() -> void:
	var sim := SurvivalSim.new(PlayerStats.compute(), "hunter", 1)
	sim.apply_upgrade("double")
	assert_eq(sim.proj_extra, 1, "double adds a projectile / widens the swing")
	sim.apply_upgrade("diagonal")
	assert_true(sim.diagonal, "diagonal attack enabled")
	sim.apply_upgrade("backside")
	assert_true(sim.backside, "backside attack enabled")
	# Diagonal + backside produce extra ranged angles beyond the forward shot.
	assert_gt(sim._attack_offsets().size(), 1, "more attack angles after shape upgrades")


func test_once_upgrades_do_not_repeat() -> void:
	var sim := SurvivalSim.new(PlayerStats.compute(), "hunter", 3)
	sim.upgrades_taken.append("backside")
	sim.upgrades_taken.append("diagonal")
	for _i in 30:
		for u in sim.offer_upgrades():
			assert_false(String(u["id"]) in ["backside", "diagonal"], "once-only upgrades never re-offer")


func test_player_can_die() -> void:
	var sim := SurvivalSim.new(PlayerStats.compute(), "hunter", 5)
	sim.hp = 5.0
	sim.enemies.append({"pos": sim.player, "hp": 99.0, "max": 99.0, "spd": 0.0, "r": 22.0, "dmg": 50.0})
	sim.tick(0.05, Vector2.ZERO)
	assert_false(sim.alive, "a foe on top of a near-dead delver ends the run")
	assert_eq(sim.hp, 0.0, "HP floored at zero")


func test_final_score_grows_with_progress() -> void:
	var sim := SurvivalSim.new(PlayerStats.compute(), "hunter", 2)
	var base := sim.final_score()
	sim.kills = 20
	sim.stage = 3
	sim.time = 60.0
	assert_gt(sim.final_score(), base, "score reflects kills + stage + time")


func test_secondary_weapons_apply() -> void:
	var sim := SurvivalSim.new(PlayerStats.compute(), "hunter", 11)
	sim.apply_upgrade("orbs")
	assert_eq(sim.orbs, 2, "first Warding Orbs pick gives 2 orbs")
	sim.apply_upgrade("orbs")
	assert_eq(sim.orbs, 3, "and stacks +1")
	sim.apply_upgrade("nova")
	assert_eq(sim.nova_level, 1, "Pyre Nova enabled")


func test_orbs_damage_nearby_enemies() -> void:
	var sim := SurvivalSim.new(PlayerStats.compute(), "hunter", 12)
	sim.orbs = 2
	sim.orb_angle = 0.0
	var e := {"pos": sim.player + Vector2(sim.orb_radius, 0.0), "hp": 9999.0, "max": 9999.0,
		"spd": 0.0, "r": 20.0, "dmg": 0.0, "kind": "grunt", "tint": "a83a33"}
	sim.enemies.append(e)
	for _i in 20:  # per-frame steps: an orb sweeps onto the ring-adjacent foe
		sim._update_orbs(0.05)
	assert_lt(float(e["hp"]), 9999.0, "an orbiting orb sweeps the adjacent foe")


func test_spawn_director_mixes_archetypes() -> void:
	var sim := SurvivalSim.new(PlayerStats.compute(), "hunter", 99)
	sim.max_hp = 1.0e9
	sim.hp = sim.max_hp
	sim.stage = 6  # brutes are weighted in by this stage
	var seen := {}
	for _i in 400:  # ~20s, short of a stage clear
		sim.tick(0.05, Vector2.ZERO)
		for en in sim.enemies:
			seen[String(en.get("kind", "?"))] = true
	assert_gt(seen.size(), 1, "the spawn director mixes enemy archetypes")


func test_world_boss_spawns_and_rewards() -> void:
	var sim := SurvivalSim.new(PlayerStats.compute(), "hunter", 7)
	sim.max_hp = 1.0e9
	sim.hp = sim.max_hp
	# Run until the world boss appears, auto-resolving any stage-clear drafts so
	# the clock keeps moving (an unresolved draft pauses the sim).
	var t := 0.0
	while t < sim.BOSS_DELAY + 3.0 and not sim.boss_alive:
		if sim.awaiting_upgrade:
			sim.choose_upgrade(String(sim.offer_upgrades()[0]["id"]))
		else:
			sim.tick(0.05, Vector2.ZERO)
			t += 0.05
	assert_true(sim.boss_alive, "a world boss spawns after BOSS_DELAY")
	var bosses := 0
	var boss: Dictionary = {}
	for e in sim.enemies:
		if String(e.get("kind", "")) == "boss":
			bosses += 1
			boss = e
	assert_eq(bosses, 1, "exactly one world boss at a time")

	if sim.awaiting_upgrade:
		sim.choose_upgrade(String(sim.offer_upgrades()[0]["id"]))
	var stage_before := sim.stage
	sim._kill_enemy(boss)
	assert_false(sim.boss_alive, "the boss is cleared")
	assert_eq(sim.bosses_slain, 1)
	assert_true(sim.awaiting_upgrade, "a bonus upgrade draft opens on the boss kill")
	assert_eq(sim._draft_reason, "boss")
	sim.choose_upgrade("dmg")
	assert_eq(sim.stage, stage_before, "a boss reward does NOT advance the stage timer")
	assert_false(sim.awaiting_upgrade, "and resumes the run")


func test_scene_builds_and_ticks() -> void:
	var s := _SurvivalScene.new()
	add_child_autofree(s)
	await get_tree().process_frame
	for _i in 24:  # ~1.2s — short of a stage clear, so no modal opens
		s._process(0.05)
	assert_not_null(s._sim, "the scene owns a live sim")
	assert_true(s._sim.alive, "delver survives the brief smoke window")
