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
	assert_eq(GameState.equipped.size(), GameContent.EQUIP_SLOTS.size(),
		"pre-equipment saves seed the default paperdoll")


func test_class_and_equipment_round_trip() -> void:
	GameState.choose_class("rogue", "  Nyx  ")
	assert_eq(GameState.player_name, "Nyx", "chosen name is trimmed")
	assert_eq(GameState.player_class, "Rogue")
	assert_eq(GameState.player_title, "the Twice-Hanged")
	assert_true(GameState.has_profile(), "choosing a class creates the profile")

	var bag_before := GameState.bag_equipment.size()
	assert_true(GameState.unequip_to_bag(0), "helm unequips into the bag")
	assert_null(GameState.equipped[0])
	assert_eq(GameState.bag_equipment.size(), bag_before + 1)
	GameState.daily_chests = 7

	var parsed: Variant = JSON.parse_string(JSON.stringify(GameState.to_dict()))
	GameState.reset_to_defaults()
	assert_false(GameState.has_profile(), "a fresh profile routes to Login")
	GameState.from_dict(parsed)

	assert_eq(GameState.class_id, "rogue")
	assert_eq(GameState.player_class, "Rogue")
	assert_true(GameState.has_profile())
	assert_eq(GameState.equipped.size(), GameContent.EQUIP_SLOTS.size())
	assert_null(GameState.equipped[0], "emptied slot survives the round-trip")
	assert_eq(GameState.bag_equipment.size(), bag_before + 1)
	assert_eq(GameState.daily_chests, 7)


func test_equip_from_bag_respects_slot_rules() -> void:
	var bag_before := GameState.bag_equipment.size()
	assert_true(GameState.unequip_to_bag(0))
	var idx := GameState.bag_equipment.size() - 1
	var helm: Dictionary = GameState.bag_equipment[idx]
	assert_true(GameContent.slot_accepts(0, String(helm["slot"])), "the helm fits its own slot")
	assert_false(GameState.equip_from_bag(idx, 5), "a helm cannot go in the main hand")
	assert_true(GameState.equip_from_bag(idx, 0), "the helm equips back")
	assert_eq(GameState.bag_equipment.size(), bag_before, "bag returns to baseline")
	assert_eq(String((GameState.equipped[0] as Dictionary)["n"]), String(helm["n"]))


func test_party_lineup_round_trip_and_rules() -> void:
	# Swap semantics: putting Mordrake in slot 0 keeps the lineup dupe-free.
	assert_true(GameState.set_party_slot(0, "mord"), "recruited hero slots in")
	assert_eq(GameState.party_ids[0], "mord")
	assert_false(GameState.party_ids.has("brand"), "brand left the lineup")
	assert_true(GameState.set_party_slot(1, "mord"), "moving an in-party hero swaps")
	assert_eq(GameState.party_ids[1], "mord")
	assert_eq(GameState.party_ids[0], "ash", "the displaced hero takes the old slot")
	assert_false(GameState.set_party_slot(0, "veyra"), "locked heroes cannot slot in")
	assert_false(GameState.set_party_slot(0, "nope"), "unknown ids are refused")

	var parsed: Variant = JSON.parse_string(JSON.stringify(GameState.to_dict()))
	GameState.reset_to_defaults()
	assert_eq(GameState.party_ids, GameContent.DEFAULT_PARTY_IDS, "defaults restore")
	GameState.from_dict(parsed)
	assert_eq(GameState.party_ids[1], "mord", "lineup survives the round-trip")

	# Tampered lineups (dupes / unknown ids) are rejected — the loader keeps
	# the current (default, in the real SaveManager flow) four.
	GameState.reset_to_defaults()
	GameState.from_dict({"party_lineup": ["mord", "mord", "hex", "wren"]})
	assert_eq(GameState.party_ids, GameContent.DEFAULT_PARTY_IDS, "dupes rejected")


func test_aura_check_diagnoses_compositions() -> void:
	assert_true(bool(GameContent.aura_check(["brand", "ash", "hex", "wren"])["ok"]))
	assert_eq(String(GameContent.aura_check(["brand", "mord", "ash", "wren"])["msg"]),
		"Too many tanks")
	assert_eq(String(GameContent.aura_check(["ash", "hex", "korr", "wren"])["msg"]),
		"Missing a tank")
	assert_eq(String(GameContent.aura_check(["brand", "ash", "hex", "korr"])["msg"]),
		"Missing a healer")
	assert_eq(String(GameContent.aura_check(["brand", "korr", "korr", "wren"])["msg"]),
		"DPS must differ")


func test_equip_swap_keeps_bag_position() -> void:
	# Unequip the helm, then equip it back while ANOTHER helm sits in the
	# slot: the occupant must swap into the same bag position.
	assert_true(GameState.unequip_to_bag(0))
	var idx := GameState.bag_equipment.size() - 1
	var first: Dictionary = GameState.bag_equipment[idx]
	var second := GameContent.generate_item(50, "rare", RandomNumberGenerator.new())
	second["slot"] = "Helm"
	GameState.equipped[0] = second
	assert_true(GameState.equip_from_bag(idx, 0), "occupied slot accepts a matching item")
	assert_eq(String((GameState.equipped[0] as Dictionary)["n"]), String(first["n"]))
	assert_eq(String((GameState.bag_equipment[idx] as Dictionary)["n"]), String(second["n"]),
		"the displaced helm lands in the same bag cell")
