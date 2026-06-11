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


func test_gacha_pick_matches_requested_rarity() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var hero := GameContent.gacha_pick("epic", rng)
	assert_eq(String(hero["r"]), "epic")
	# Unknown rarity falls back to the common pool.
	var fallback := GameContent.gacha_pick("mythic", rng)
	assert_eq(String(fallback["r"]), "common")


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
