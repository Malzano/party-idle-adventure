extends GutTest
## Gacha: pity guarantees, rate sanity, soulstone spending, pity clamping.

const ROLLS := 20000


func before_each() -> void:
	GameState.reset_to_defaults()


func after_all() -> void:
	GameState.reset_to_defaults()


func test_hard_pity_guarantees_legendary() -> void:
	for seed_val in [0, 1, 42, 999, 123456, 0xDEADBEEF]:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_val
		assert_eq(GameContent.gacha_roll_rarity(GameContent.PITY_HARD, rng), "legendary",
			"pity %d must guarantee a legendary (seed %d)" % [GameContent.PITY_HARD, seed_val])


func test_legendary_rate_sane_at_zero_pity() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var legendary := 0
	for i in ROLLS:
		if GameContent.gacha_roll_rarity(0, rng) == "legendary":
			legendary += 1
	var rate := float(legendary) / float(ROLLS)
	assert_between(rate, 0.002, 0.014,
		"base legendary rate over %d rolls should sit near 0.6%% (got %.3f%%)" % [ROLLS, rate * 100.0])


func test_rolls_only_return_known_rarities() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 500:
		var r := GameContent.gacha_roll_rarity(i % 91, rng)
		assert_true(GameContent.RARITY_RANK.has(r), "unknown rarity '%s'" % r)


func test_gacha_pull_rolls_gear_into_the_bag() -> void:
	# A pull now rolls GEAR for the single character (no roster). The item banks
	# into the bag and lifetime summons increment (the pet-unlock gate).
	BackendClient.mock = true
	GameState.reset_to_defaults()
	GameState.bag_equipment = []
	GameState.premium_currency = 5000
	var summons_before := GameState.total_summons
	var res: Dictionary = await BackendClient.gacha_pull(1)
	assert_true(bool(res["ok"]), "a pull with enough soulstones succeeds")
	var results: Array = res["data"]["results"]
	assert_eq(results.size(), 1, "a x1 pull yields one item")
	var item: Dictionary = results[0]
	assert_true(item.has("slot") and item.has("ilvl") and item.has("r"),
		"the pull rolls a canonical gear item, not a hero")
	assert_eq(GameState.total_summons, summons_before + 1, "lifetime summons increment")
	assert_eq(GameState.bag_equipment.size(), 1, "the item banks into the bag")


func test_spend_soulstones_refuses_when_poor() -> void:
	GameState.premium_currency = 100
	assert_false(GameState.spend_soulstones(160), "cannot afford 160 with 100")
	assert_eq(GameState.premium_currency, 100, "nothing deducted on refusal")


func test_spend_soulstones_deducts_when_rich() -> void:
	GameState.premium_currency = 2000
	assert_true(GameState.spend_soulstones(160))
	assert_eq(GameState.premium_currency, 1840)


func test_set_pity_clamps_to_hard_pity() -> void:
	GameState.set_pity(9999)
	assert_eq(GameState.pity, GameContent.PITY_HARD, "pity clamps at hard pity")
	GameState.set_pity(-5)
	assert_eq(GameState.pity, 0, "pity cannot go negative")
	GameState.set_pity(47)
	assert_eq(GameState.pity, 47)
