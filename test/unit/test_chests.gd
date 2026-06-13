extends GutTest
## Battle caches: the BackendClient mock must mirror the server contract —
## envelope shape, daily cap, grants applied to GameState — and the shared
## item generator must produce canonical save-schema items.


func before_each() -> void:
	# These tests validate the offline mock contract; force it on regardless of
	# the production default (which is now live — mock=false).
	BackendClient.mock = true
	GameState.reset_to_defaults()


func after_all() -> void:
	GameState.reset_to_defaults()


func test_mock_chest_opens_grant_and_count() -> void:
	var gold0 := GameState.gold
	var iron0 := GameState.iron_ingots
	var dust0 := GameState.ember_dust
	var bag0 := GameState.bag_equipment.size()
	for i in 6:
		var res: Dictionary = await BackendClient.chest_open()
		assert_true(bool(res["ok"]), "chest %d opens" % i)
		assert_eq(int(res["status"]), 200)
		var reward: Dictionary = res["data"]["reward"]
		assert_true(String(reward["kind"]) in ["gold", "materials", "item"],
			"reward kind is one of the contract's three")
	assert_eq(GameState.daily_chests, 6, "every open counts toward the daily cap")
	var gained := GameState.gold > gold0 or GameState.iron_ingots > iron0 \
		or GameState.ember_dust > dust0 or GameState.bag_equipment.size() > bag0
	assert_true(gained, "six chests grant something tangible")


func test_chest_daily_cap_blocks() -> void:
	GameState.daily_chests = 40
	var gold0 := GameState.gold
	var res: Dictionary = await BackendClient.chest_open()
	assert_false(bool(res["ok"]))
	assert_eq(int(res["status"]), 422)
	assert_eq(String(res["data"]["error"]["code"]), "chest_cap")
	assert_eq(GameState.daily_chests, 40, "the cap does not increment")
	assert_eq(GameState.gold, gold0, "nothing is granted past the cap")


func test_daily_reset_clears_chest_count() -> void:
	GameState.daily_chests = 12
	GameState.daily_day = 0  # force "new day"
	GameState.check_daily_reset()
	assert_eq(GameState.daily_chests, 0)


func test_generated_items_are_canonical() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xC4E57
	for i in 40:
		var rarity := GameContent.roll_chest_item_rarity(rng)
		assert_true(rarity in ["common", "uncommon", "rare", "epic", "legendary", "mythic"])
		var it := GameContent.generate_item(40, rarity, rng)
		for key in ["n", "r", "slot", "ilvl", "s"]:
			assert_true(it.has(key), "item has '%s'" % key)
		assert_eq(String(it["r"]), rarity)
		assert_true((it["s"] as Array).size() >= 1, "at least one stat line")
		# Every generated item must fit at least one paperdoll slot.
		var fits := false
		for slot_i in GameContent.EQUIP_SLOTS.size():
			if GameContent.slot_accepts(slot_i, String(it["slot"])):
				fits = true
				break
		assert_true(fits, "'%s' (%s) fits a paperdoll slot" % [it["n"], it["slot"]])


func test_mythic_items_carry_five_affixes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var it := GameContent.generate_item(60, "mythic", rng)
	assert_true((it["s"] as Array).size() >= 5, "mythics roll 5+ affixes")
	assert_true(String(it["n"]) in GameContent._MYTHIC_NAMES, "mythics use unique names")


func test_item_stats_parse_into_statblock() -> void:
	# The generator's affix strings must be mechanically real (StatBlock parses
	# them), not just flavor text — same rule as all design content.
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var it := GameContent.generate_item(45, "legendary", rng)
	var block := StatBlock.new()
	block.apply_stat_pairs(it["s"])
	assert_true(block.flat.size() + block.inc.size() > 0,
		"generated affixes contribute to the stat block")
