extends GutTest
## BAG tab: item footprints + the two-panel Tetris pack/move logic (no UI drag).
## On load every owned piece is loose; auto-sort packs them; pieces can be placed
## from the loose list, moved on the grid, and taken back off — never overlapping.


const _BagTab := preload("res://scenes/hero/BagTab.gd")


func before_each() -> void:
	GameState.reset_to_defaults()


func after_all() -> void:
	GameState.reset_to_defaults()


func test_item_footprint_by_slot_and_weapon_hands() -> void:
	assert_eq(GameContent.item_footprint({"slot": "Helm"}), Vector2i(2, 2))
	assert_eq(GameContent.item_footprint({"slot": "Body"}), Vector2i(2, 3))
	assert_eq(GameContent.item_footprint({"slot": "Off Hand"}), Vector2i(2, 3))
	assert_eq(GameContent.item_footprint({"slot": "Belt"}), Vector2i(2, 1))
	assert_eq(GameContent.item_footprint({"slot": "Ring"}), Vector2i(1, 1))
	assert_eq(GameContent.item_footprint({"slot": "Amulet"}), Vector2i(1, 1))
	assert_eq(GameContent.item_footprint({"slot": "Main Hand", "n": "Cindergrip Maul"}), Vector2i(2, 4))
	assert_eq(GameContent.item_footprint({"slot": "Main Hand", "n": "Ashen Blade"}), Vector2i(1, 3))


func test_loads_loose_then_auto_sort_packs_without_overlap() -> void:
	GameState.bag_equipment.clear()
	for g in GameContent.GEAR_L + GameContent.GEAR_R:
		GameState.bag_equipment.append(GameContent.gear_to_item(g))
	var bag = _BagTab.new()
	add_child_autofree(bag)
	bag._reload()
	assert_eq(bag._placements.size(), 0, "on load the grid is empty")
	assert_eq(bag._loose.size(), 10, "all ten owned pieces are listed loose")

	bag._auto_sort()
	assert_eq(bag._placements.size(), 10, "auto-sort packs every piece")
	assert_eq(bag._loose.size(), 0, "nothing is left loose")

	# Shapes can be non-rectangular, so check the ACTUAL occupied cells (not the
	# bounding box) — interlocking pieces may share each other's empty corners.
	var seen := {}
	var used := 0
	var expected := 0
	for p in bag._placements:
		var pos: Vector2i = p["pos"]
		var cells: Array = p["cells"]
		expected += cells.size()
		for c in cells:
			var key := Vector2i(pos.x + int(c.x), pos.y + int(c.y))
			assert_true(key.x >= 0 and key.y >= 0 and key.x < bag.GRID_W and key.y < bag.GRID_H,
				"every occupied cell is inside the grid")
			assert_false(seen.has(key), "no two pieces share a cell")
			seen[key] = true
			used += 1
	assert_eq(used, expected, "occupied-cell count matches the pieces' shapes")


func test_place_move_and_unplace_respect_occupancy() -> void:
	GameState.bag_equipment.clear()
	GameState.bag_equipment.append(GameContent.gear_to_item(GameContent.GEAR_L[0]))  # Helm 2×2
	GameState.bag_equipment.append(GameContent.gear_to_item(GameContent.GEAR_L[2]))  # Body 2×3
	var bag = _BagTab.new()
	add_child_autofree(bag)
	bag._reload()
	assert_eq(bag._loose.size(), 2)

	# Drop the first loose piece onto a free run.
	assert_true(bag._try_place_loose(0, Vector2i(0, 0)), "loose piece places on a free run")
	assert_eq(bag._placements.size(), 1)
	assert_eq(bag._loose.size(), 1)

	# The remaining loose piece cannot land on the occupied cells, nor out of bounds.
	var placed_pos: Vector2i = bag._placements[0]["pos"]
	assert_false(bag._try_place_loose(0, placed_pos), "placing onto occupied cells is rejected")
	assert_false(bag._try_place_loose(0, Vector2i(bag.GRID_W, 0)), "out-of-bounds placement is rejected")

	# Move the placed piece to a free corner, then take it back off the grid.
	assert_true(bag._try_move(0, Vector2i(bag.GRID_W - 2, bag.GRID_H - 2)), "moves to a free corner run")
	bag._unplace(0)
	assert_eq(bag._placements.size(), 0, "unplaced piece leaves the grid")
	assert_eq(bag._loose.size(), 2, "and returns to the loose list")


func test_right_click_auto_places_loose_piece() -> void:
	GameState.bag_equipment.clear()
	GameState.bag_equipment.append(GameContent.gear_to_item(GameContent.GEAR_L[0]))  # Helm 2x2
	var bag = _BagTab.new()
	add_child_autofree(bag)
	bag._reload()
	assert_eq(bag._loose.size(), 1)
	assert_eq(bag._placements.size(), 0)
	# Right-click insert: drops into the first run that fits.
	assert_true(bag._place_loose_auto(0), "auto-places into the first free run")
	assert_eq(bag._placements.size(), 1)
	assert_eq(bag._loose.size(), 0)
	assert_eq(Vector2i(bag._placements[0]["pos"]), Vector2i(0, 0), "lands at the first cell")


func test_worn_items_are_listed_and_stowing_unequips() -> void:
	GameState.bag_equipment.clear()
	GameState.equipped[0] = GameContent.gear_to_item(GameContent.GEAR_L[0])  # wear a Helm
	var bag = _BagTab.new()
	add_child_autofree(bag)
	bag._reload()

	# The worn piece shows in ALL ITEMS, flagged equipped.
	assert_eq(bag._loose.size(), 1, "the worn piece is listed")
	assert_true(bool(bag._loose[0]["equipped"]), "and flagged equipped")

	# Stowing it onto the grid takes it off the paperdoll and into the bag.
	assert_true(bag._try_place_loose(0, Vector2i(0, 0)), "worn piece stows onto the grid")
	assert_null(GameState.equipped[0], "the paperdoll slot is now empty")
	assert_eq(bag._placements.size(), 1, "and the piece sits on the grid")
	assert_eq(bag._loose.size(), 0, "and is no longer loose")


func test_gear_defines_shapes_with_matching_footprints() -> void:
	# Shapes can be non-rectangular (boots = L, two-hander = blade + crossguard)
	# but their bounding boxes still equal the slot footprints.
	var boots := {"slot": "Boots"}
	assert_eq(GameContent.item_shape_cells(boots).size(), 3, "boots are an L (3 cells in a 2×2)")
	assert_eq(GameContent.item_footprint(boots), Vector2i(2, 2))
	var maul := {"slot": "Main Hand", "n": "Cindergrip Maul"}
	assert_eq(GameContent.item_footprint(maul), Vector2i(2, 4))
	assert_eq(GameContent.item_shape_cells(maul).size(), 5, "two-hander is blade + crossguard")
	assert_eq(GameContent.item_shape_cells({"slot": "Ring"}).size(), 1, "a ring is 1 cell")


func test_every_equipment_defines_a_survival_stat() -> void:
	for g in GameContent.GEAR_L + GameContent.GEAR_R:
		var it := GameContent.gear_to_item(g)
		assert_false(GameContent.item_bullet_hell(it).is_empty(),
			"%s has a Survival stat" % String(it.get("n", "")))
	# Generated items carry an explicit bh + shape (and bh stays out of "s").
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var gen := GameContent.generate_item(60, "epic", rng)
	assert_true(gen.has("bh") and not (gen["bh"] as Array).is_empty(), "generated item stores a Survival stat")
	assert_true(gen.has("shape"), "generated item stores its shape name")
	for pair in (gen["s"] as Array):
		assert_false(GameContent._BH_AFFIXES.has(String(pair[0])), "Survival affixes never leak into idle stats")
	# tip_stats surfaces a Stampede (Survival-mode) section.
	var has_survival := false
	for r in GameContent.tip_stats(gen):
		if String(r[0]).contains("Stampede"):
			has_survival = true
	assert_true(has_survival, "tooltip stats include a Stampede section")
