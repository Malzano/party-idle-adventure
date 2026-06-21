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

	var seen := {}
	var used := 0
	for p in bag._placements:
		var pos: Vector2i = p["pos"]
		var s: Vector2i = p["size"]
		used += s.x * s.y
		assert_true(pos.x >= 0 and pos.y >= 0 and pos.x + s.x <= bag.GRID_W and pos.y + s.y <= bag.GRID_H,
			"placement stays inside the grid")
		for dy in s.y:
			for dx in s.x:
				var key := Vector2i(pos.x + dx, pos.y + dy)
				assert_false(seen.has(key), "no two pieces share a cell")
				seen[key] = true
	assert_eq(used, 37, "the full loadout occupies 37 cells")


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
