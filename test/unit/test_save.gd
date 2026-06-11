extends GutTest
## Save serialization: to_dict/from_dict round-trip (incl. a JSON pass, like
## SaveManager does on disk) must preserve every profile field. Never touches
## user:// — SaveManager.save_game is deliberately not called.


func before_each() -> void:
	GameState.reset_to_defaults()


func after_all() -> void:
	GameState.reset_to_defaults()


func test_round_trip_preserves_all_fields() -> void:
	GameState.gold = 99999
	GameState.premium_currency = 777
	GameState.ember_dust = 21
	GameState.energy = 50
	GameState.player_level = 51
	GameState.xp = 1234
	GameState.xp_to_next = 16100
	GameState.act = 5
	GameState.stage = 12
	GameState.max_stage = 512
	GameState.pity = 63
	GameState.iron_ingots = 5
	GameState.forge_level = 11
	GameState.dungeon_attempts = 1
	GameState.dungeon_buff_until = 1_234_567_890
	GameState.daily_day = 20600
	GameState.daily_stages = 4
	GameState.daily_damage = 1_234_567.5
	GameState.daily_meals = 2
	GameState.daily_summons = 1
	GameState.daily_forges = 3
	GameState.food_buff = "Emberroot Stew"
	GameState.food_buff_effect = "+12% party ATK"
	GameState.food_buff_until = 1_234_567_999
	var talents: Array[int] = [0, 1, 2, 7]
	GameState.talents_allocated = talents
	GameState.roster_extra = [{"n": "Korr", "r": "rare", "role": "3★ DPS · Reaver"}]
	GameState.claim_quest(2)
	GameState.active_pet = 3
	GameState.last_played_utc = 1_750_000_000

	# Same shape as the on-disk save: dict → JSON text → dict.
	var text := JSON.stringify(GameState.to_dict())
	var parsed: Variant = JSON.parse_string(text)
	assert_eq(typeof(parsed), TYPE_DICTIONARY, "serialized profile must be valid JSON")

	GameState.reset_to_defaults()
	GameState.from_dict(parsed)

	assert_eq(GameState.gold, 99999)
	assert_eq(GameState.premium_currency, 777)
	assert_eq(GameState.ember_dust, 21)
	assert_eq(GameState.energy, 50)
	assert_eq(GameState.player_level, 51)
	assert_eq(GameState.xp, 1234)
	assert_eq(GameState.xp_to_next, 16100)
	assert_eq(GameState.act, 5)
	assert_eq(GameState.stage, 12)
	assert_eq(GameState.max_stage, 512)
	assert_eq(GameState.pity, 63)
	assert_eq(GameState.iron_ingots, 5)
	assert_eq(GameState.forge_level, 11)
	assert_eq(GameState.dungeon_attempts, 1)
	assert_eq(GameState.dungeon_buff_until, 1_234_567_890)
	assert_eq(GameState.daily_day, 20600)
	assert_eq(GameState.daily_stages, 4)
	assert_almost_eq(GameState.daily_damage, 1_234_567.5, 0.001)
	assert_eq(GameState.daily_meals, 2)
	assert_eq(GameState.daily_summons, 1)
	assert_eq(GameState.daily_forges, 3)
	assert_eq(GameState.food_buff, "Emberroot Stew")
	assert_eq(GameState.food_buff_effect, "+12% party ATK")
	assert_eq(GameState.food_buff_until, 1_234_567_999)
	assert_eq(GameState.talents_allocated.size(), 4)
	for id in [0, 1, 2, 7]:
		assert_true(GameState.talents_allocated.has(id), "talent %d survives the round-trip" % id)
	assert_eq(GameState.roster_extra.size(), 1)
	assert_eq(String(GameState.roster_extra[0]["n"]), "Korr")
	assert_eq(String(GameState.roster_extra[0]["r"]), "rare")
	assert_true(GameState.quests_claimed.has(2), "claimed quest survives")
	assert_eq(GameState.active_pet, 3)
	assert_eq(GameState.last_played_utc, 1_750_000_000)


func test_from_dict_missing_keys_keep_defaults() -> void:
	GameState.from_dict({"gold": 5})
	assert_eq(GameState.gold, 5)
	assert_eq(GameState.forge_level, 7, "missing forge_level keeps the default")
	assert_eq(GameState.iron_ingots, 46, "missing iron_ingots keeps the default")
	assert_eq(GameState.dungeon_attempts, 3, "missing dungeon_attempts keeps the default")
	assert_eq(GameState.pity, 47, "missing pity keeps the default")
