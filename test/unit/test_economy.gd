extends GutTest
## Economy: forge upgrades, daily dungeon, food buffs, daily reset, quests.


func before_all() -> void:
	# Freeze the live sim so ticks cannot mutate currencies/counters mid-assert.
	CombatSim.set_process(false)


func before_each() -> void:
	GameState.reset_to_defaults()
	PlayerStats.invalidate()


func after_all() -> void:
	GameState.reset_to_defaults()
	PlayerStats.invalidate()
	CombatSim.set_process(true)


## First deterministic seed whose first randf() lands on the wanted side of
## the forge success threshold.
func _seed_where_first_randf(below: bool, threshold: float) -> int:
	for s in 10000:
		var probe := RandomNumberGenerator.new()
		probe.seed = s
		var hit := probe.randf() < threshold
		if hit == below:
			return s
	return -1


func test_forge_upgrade_success_spends_and_levels() -> void:
	var threshold := Balance.num("forge.success_rate", 0.82)
	var seed_val := _seed_where_first_randf(true, threshold)
	assert_gt(seed_val, -1, "must find a succeeding seed")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	# A fresh profile starts with no materials — grant enough to forge.
	GameState.gold = 100000
	GameState.iron_ingots = 50
	GameState.ember_dust = 20
	var gold_cost := Balance.forge_gold_cost(GameState.forge_level)
	var gold_before := GameState.gold
	var iron_before := GameState.iron_ingots
	var dust_before := GameState.ember_dust
	var level_before := GameState.forge_level

	var result := GameState.try_forge_upgrade(rng)
	assert_true(bool(result["ok"]), "attempt should proceed with full resources")
	assert_true(bool(result["success"]), "seeded roll below %.2f must succeed" % threshold)
	assert_eq(GameState.gold, gold_before - gold_cost, "gold spent")
	assert_eq(GameState.iron_ingots, iron_before - Balance.inum("forge.iron_cost", 12), "iron spent")
	assert_eq(GameState.ember_dust, dust_before - Balance.inum("forge.dust_cost", 3), "dust spent")
	assert_eq(GameState.forge_level, level_before + 1, "success raises the forge level")
	assert_eq(GameState.daily_forges, 1, "attempt counts toward the daily quest")


func test_forge_upgrade_failure_spends_but_keeps_level() -> void:
	var threshold := Balance.num("forge.success_rate", 0.82)
	var seed_val := _seed_where_first_randf(false, threshold)
	assert_gt(seed_val, -1, "must find a failing seed")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	# A fresh profile starts with no materials — grant enough to forge.
	GameState.gold = 100000
	GameState.iron_ingots = 50
	GameState.ember_dust = 20
	var gold_before := GameState.gold
	var level_before := GameState.forge_level
	var result := GameState.try_forge_upgrade(rng)
	assert_true(bool(result["ok"]))
	assert_false(bool(result["success"]), "seeded roll above %.2f must fail" % threshold)
	assert_eq(GameState.forge_level, level_before, "failure keeps the level")
	assert_lt(GameState.gold, gold_before, "materials are consumed even on failure")


func test_forge_upgrade_refuses_when_gold_short() -> void:
	GameState.gold = 10
	var iron_before := GameState.iron_ingots
	var dust_before := GameState.ember_dust
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var result := GameState.try_forge_upgrade(rng)
	assert_false(bool(result["ok"]))
	assert_string_contains(String(result["reason"]).to_lower(), "gold")
	assert_eq(GameState.gold, 10, "no gold deducted")
	assert_eq(GameState.iron_ingots, iron_before, "no iron deducted")
	assert_eq(GameState.ember_dust, dust_before, "no dust deducted")
	assert_eq(GameState.forge_level, 7, "level untouched")


func test_enter_daily_dungeon_spends_and_buffs() -> void:
	var energy_before := GameState.energy
	var attempts_before := GameState.dungeon_attempts
	assert_true(GameState.enter_daily_dungeon())
	assert_eq(GameState.energy, energy_before - Balance.inum("energy.dungeon_cost", 20), "energy spent")
	assert_eq(GameState.dungeon_attempts, attempts_before - 1, "attempt consumed")
	assert_true(GameState.dungeon_buff_active(), "gold rush is running")


func test_enter_daily_dungeon_refuses_without_attempts() -> void:
	GameState.dungeon_attempts = 0
	var energy_before := GameState.energy
	assert_false(GameState.enter_daily_dungeon())
	assert_eq(GameState.energy, energy_before, "no energy spent when refused")


func test_enter_daily_dungeon_refuses_without_energy() -> void:
	GameState.energy = 5
	assert_false(GameState.enter_daily_dungeon())
	assert_eq(GameState.energy, 5)
	assert_eq(GameState.dungeon_attempts, 3, "attempt refunded path never taken")


func test_food_buff_activates_and_expires() -> void:
	GameState.set_food_buff("Emberroot Stew", "+12% party ATK", 1800)
	assert_true(GameState.food_buff_active())
	assert_eq(GameState.daily_meals, 1, "meal counts toward the daily quest")
	GameState.food_buff_until = GameState.now_utc() - 10
	assert_false(GameState.food_buff_active(), "buff lapses after expiry")


func test_check_daily_reset_clears_counters_on_new_day() -> void:
	GameState.daily_day = 0  # long-ago stamp → reset must fire
	GameState.daily_stages = 5
	GameState.daily_damage = 1_000_000.0
	GameState.daily_meals = 2
	GameState.daily_summons = 1
	GameState.daily_forges = 3
	GameState.dungeon_attempts = 0
	GameState.claim_quest(0)

	GameState.check_daily_reset()

	assert_eq(GameState.daily_day, int(GameState.now_utc() / 86400.0), "day stamp updated")
	assert_eq(GameState.daily_stages, 0)
	assert_eq(GameState.daily_damage, 0.0)
	assert_eq(GameState.daily_meals, 0)
	assert_eq(GameState.daily_summons, 0)
	assert_eq(GameState.daily_forges, 0)
	assert_eq(GameState.quests_claimed.size(), 0, "claims cleared")
	assert_eq(GameState.dungeon_attempts, Balance.inum("energy.dungeon_attempts_per_day", 3), "attempts refilled")


func test_check_daily_reset_keeps_counters_same_day() -> void:
	GameState.daily_day = int(GameState.now_utc() / 86400.0)
	GameState.daily_stages = 4
	GameState.daily_meals = 1
	GameState.check_daily_reset()
	assert_eq(GameState.daily_stages, 4, "same day → counters survive")
	assert_eq(GameState.daily_meals, 1)


func test_quest_progress_mapping() -> void:
	GameState.daily_stages = 2
	GameState.daily_summons = 1
	GameState.daily_meals = 3
	GameState.daily_damage = 3_100_000.0
	GameState.daily_forges = 5
	assert_eq(GameState.quest_progress(0), 2.0, "quest 0 tracks stages")
	assert_eq(GameState.quest_progress(1), 1.0, "quest 1 tracks summons")
	assert_eq(GameState.quest_progress(2), 3.0, "quest 2 tracks meals")
	assert_almost_eq(GameState.quest_progress(3), 3.1, 0.0001, "quest 3 tracks damage in millions")
	assert_eq(GameState.quest_progress(4), 5.0, "quest 4 tracks forges")


func test_complete_quest_claims_grants_and_refuses_repeat() -> void:
	# A finished quest claims once: it flips to claimed, pays its parsed reward
	# (quest 0 = "240 Gold · 40 XP"), and a second claim is refused.
	BackendClient.mock = true
	GameState.reset_to_defaults()
	GameState.daily_stages = 3  # quest 0 goal is 3 → complete
	var gold_before := GameState.gold
	var res: Dictionary = await BackendClient.quest_claim(0)
	assert_true(bool(res["ok"]), "a completed quest claims")
	assert_true(GameState.quests_claimed.has(0), "quest 0 is marked claimed")
	assert_eq(GameState.gold, gold_before + 240, "the 240 gold reward is granted")
	var again: Dictionary = await BackendClient.quest_claim(0)
	assert_false(bool(again["ok"]), "a second claim on the same quest is refused")


func test_incomplete_quest_cannot_be_claimed() -> void:
	BackendClient.mock = true
	GameState.reset_to_defaults()
	GameState.daily_stages = 1  # quest 0 goal 3 → not complete
	var res: Dictionary = await BackendClient.quest_claim(0)
	assert_false(bool(res["ok"]), "an unfinished quest cannot be claimed")
	assert_false(GameState.quests_claimed.has(0), "nothing is marked claimed")
