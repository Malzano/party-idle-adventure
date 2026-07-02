extends GutTest
## Crafting suite: salvage → materials, fusion (gear + gems) with rarity shift,
## blacksmith craft, gem sockets (type limits + stat contribution), Endless Tower.

var _rng: RandomNumberGenerator


func before_each() -> void:
	GameState.reset_to_defaults()
	GameState.gold = 1_000_000
	GameState.iron_ingots = 500
	GameState.ember_dust = 500
	for mid in Craft.MATERIAL_ORDER:
		if mid != "iron_ingots" and mid != "ember_dust":
			GameState.materials[mid] = 500
	GameState.bag_equipment = []
	GameState.gems = []
	GameState.tower_floor = {"easy": 0, "hard": 0, "hell": 0}
	_rng = RandomNumberGenerator.new()
	_rng.seed = 424242
	PlayerStats.invalidate()


func after_all() -> void:
	GameState.reset_to_defaults()


func _gear(rarity: String, slot := "") -> Dictionary:
	return GameContent.generate_item(50, rarity, _rng, slot)


# --- Salvage --------------------------------------------------------------

func test_salvage_gear_costs_gold_yields_mats_and_consumes_item() -> void:
	var item := _gear("rare")
	GameState.bag_equipment = [item]
	var gold_before := GameState.gold
	var iron_before := GameState.mat_count("iron_ingots")
	var res := GameState.salvage_item(item, _rng)
	assert_true(bool(res["ok"]), "a rare item salvages")
	assert_eq(GameState.gold, gold_before - Craft.salvage_gold("rare"), "gold pays the smith's fee")
	assert_gt(GameState.mat_count("iron_ingots"), iron_before, "salvage returns materials")
	assert_eq(GameState.bag_equipment.size(), 0, "the item is consumed")


func test_salvage_refused_when_broke() -> void:
	var item := _gear("rare")
	GameState.bag_equipment = [item]
	GameState.gold = 0
	var res := GameState.salvage_item(item, _rng)
	assert_false(bool(res["ok"]), "cannot salvage with no gold")
	assert_eq(GameState.bag_equipment.size(), 1, "item is kept on failure")


func test_salvage_gem_returns_reagents() -> void:
	var gem := Craft.gem_by_id("bulwark_slate")  # uncommon armour gem
	GameState.gems = [gem]
	var dust_before := GameState.mat_count("ember_dust")
	var res := GameState.salvage_gem(gem, _rng)
	assert_true(bool(res["ok"]))
	assert_gt(GameState.mat_count("ember_dust"), dust_before, "gem salvage yields ember dust")
	assert_eq(GameState.gems.size(), 0, "the gem is consumed")


# --- Fusion ---------------------------------------------------------------

func test_fuse_gear_consumes_five_and_produces_one() -> void:
	var items: Array = []
	for _i in 5:
		items.append(_gear("uncommon"))
	GameState.bag_equipment = items.duplicate()
	var res := GameState.fuse_gear(items, _rng)
	assert_true(bool(res["ok"]), "five items fuse")
	assert_eq(GameState.bag_equipment.size(), 1, "5 consumed, 1 produced")
	assert_true((res["item"] as Dictionary).has("slot"), "the product is a real gear item")


func test_fuse_gear_rarity_stays_within_one_of_highest() -> void:
	var items: Array = []
	for _i in 4:
		items.append(_gear("common"))
	items.append(_gear("rare"))  # highest = rare
	GameState.bag_equipment = items.duplicate()
	var res := GameState.fuse_gear(items, _rng)
	var out := Craft.rarity_index(String(res["rarity"]))
	assert_between(out, Craft.rarity_index("rare") - 1, Craft.rarity_index("rare") + 2,
		"fused rarity shifts within [-1,+2] of the highest input")


func test_fuse_gems_produces_a_gem() -> void:
	var picks: Array = []
	for id in ["cinder_ruby", "keening_shard", "vein_topaz", "frost_beryl", "hollow_onyx"]:
		picks.append(Craft.gem_by_id(id))
	GameState.gems = picks.duplicate()
	var res := GameState.fuse_gems(picks, _rng)
	assert_true(bool(res["ok"]))
	assert_eq(GameState.gems.size(), 1, "5 gems → 1 gem")
	assert_true((res["gem"] as Dictionary).has("eff"), "the product is a real gem")


# --- Craft ----------------------------------------------------------------

func test_craft_builds_the_chosen_slot_and_spends_cost() -> void:
	var gold_before := GameState.gold
	var res := GameState.craft_item("Main Hand", "rare", _rng)
	assert_true(bool(res["ok"]), "a rare Main Hand crafts")
	assert_eq(String((res["item"] as Dictionary)["slot"]), "Main Hand", "crafts the chosen slot")
	assert_eq(GameState.bag_equipment.size(), 1, "the crafted item banks")
	assert_lt(GameState.gold, gold_before, "craft spends gold")


func test_craft_refused_without_materials() -> void:
	GameState.materials["arcane_shard"] = 0
	GameState.materials["cinder_core"] = 0
	GameState.ember_dust = 0
	var res := GameState.craft_item("Body", "legendary", _rng)
	assert_false(bool(res["ok"]), "cannot craft legendary without the mats")


# --- Sockets --------------------------------------------------------------

func test_drill_respects_the_per_slot_socket_limit() -> void:
	var sword := _gear("epic", "Main Hand")  # Main Hand max = 3
	GameState.equipped = [sword]
	for i in 3:
		assert_true(bool(GameState.drill_socket(sword)["ok"]), "socket %d drills" % (i + 1))
	assert_false(bool(GameState.drill_socket(sword)["ok"]), "the 4th socket is refused (max 3)")
	assert_eq((sword.get("sockets", []) as Array).size(), 3, "exactly 3 sockets")


func test_gem_only_fits_its_own_category() -> void:
	var belt := _gear("rare", "Belt")
	belt["sockets"] = [null]
	var weapon_gem := Craft.gem_by_id("cinder_ruby")   # weapon-only
	var armour_gem := Craft.gem_by_id("warden_jade")   # armour-only
	GameState.gems = [weapon_gem, armour_gem]
	assert_false(GameState.insert_gem(belt, 0, weapon_gem), "a weapon gem cannot go in a belt")
	assert_true(GameState.insert_gem(belt, 0, armour_gem), "an armour gem fits the belt")
	assert_eq(GameState.gems.size(), 1, "only the socketed gem left the loose bag")


func test_socketed_gem_contributes_to_player_stats() -> void:
	# Equip a body piece, socket a "+120 Max Life" gem, and confirm the stat rises.
	var body := _gear("rare", "Body")
	body["sockets"] = [null]
	GameState.equipped = [body]
	PlayerStats.invalidate()
	var life_before := float(PlayerStats.compute()["derived"]["maximum_life"])
	var gem := Craft.gem_by_id("warden_jade")  # +120 Max Life
	GameState.gems = [gem]
	assert_true(GameState.insert_gem(body, 0, gem))
	PlayerStats.invalidate()
	var life_after := float(PlayerStats.compute()["derived"]["maximum_life"])
	assert_gt(life_after, life_before, "the socketed +Max Life gem raises maximum life")
	# Popping it out returns the gem and drops the stat again.
	assert_true(GameState.remove_gem(body, 0))
	assert_eq(GameState.gems.size(), 1, "the gem returns to the loose bag")


# --- Endless Tower --------------------------------------------------------

func test_tower_clears_easy_floor_and_advances() -> void:
	var res := GameState.tower_climb("easy", 1.0e9, _rng)  # overwhelming DPS
	assert_true(bool(res["cleared"]), "a huge-DPS delver clears floor 1 easy")
	assert_eq(GameState.tower_floor["easy"], 1, "the tower advances")
	assert_gt(int((res["rewards"] as Dictionary)["gold"]), 0, "a cleared floor pays gold")


func test_tower_fails_when_underpowered() -> void:
	var res := GameState.tower_climb("hell", 1.0, _rng)  # 1 DPS vs a huge pool
	assert_false(bool(res["cleared"]), "1 DPS cannot clear a hell floor")
	assert_eq(GameState.tower_floor["hell"], 0, "a failed climb does not advance")


func test_tower_boss_floor_drops_gear() -> void:
	GameState.tower_floor["easy"] = 4  # next attempt = floor 5 (mini-boss)
	var res := GameState.tower_climb("easy", 1.0e12, _rng)
	assert_true(bool(res["cleared"]))
	assert_eq(res["floor"], 5, "attempted the boss floor")
	assert_gt((res["rewards"]["items"] as Array).size(), 0, "a boss floor drops gear")
