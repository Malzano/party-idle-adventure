extends GutTest
## Workshop (Crafting House) modal smoke: builds all five tabs, switches between
## them, and performs a craft through the UI path without a runtime error.

const _Forge := preload("res://scenes/camp/ForgeModal.gd")
const _Tower := preload("res://scenes/camp/TowerModal.gd")


func before_each() -> void:
	GameState.reset_to_defaults()
	GameState.choose_class("warrior", "Tester")  # seeds gold + materials + gems + bag
	PlayerStats.invalidate()


func after_all() -> void:
	GameState.reset_to_defaults()


func _modal() -> Node:
	var m := _Forge.new()
	add_child_autofree(m)
	return m


func test_workshop_builds_and_switches_all_tabs() -> void:
	var m := _modal()
	await get_tree().process_frame
	assert_eq((m._pages as Dictionary).size(), 5, "all five workshop tabs are built")
	for tab in ["upgrade", "craft", "socket", "salvage", "fusion"]:
		m._set_tab(tab)
		await get_tree().process_frame
		assert_eq(m._tab, tab, "switched to the %s tab" % tab)


func test_craft_tab_forges_an_item_via_ui() -> void:
	var m := _modal()
	await get_tree().process_frame
	m._set_tab("craft")
	m._set_craft_slot("Main Hand")
	m._set_craft_rarity("rare")
	var before := GameState.bag_equipment.size()
	m._do_craft()
	assert_eq(GameState.bag_equipment.size(), before + 1, "the craft tab banks a fresh item")


func test_salvage_tab_breaks_down_a_selected_piece() -> void:
	var m := _modal()
	await get_tree().process_frame
	m._set_tab("salvage")
	await get_tree().process_frame
	var gear: Array = m._bag_gear()
	assert_gt(gear.size(), 1, "the seeded bag has gear to salvage")
	assert_gt(m._salvage_grid.get_child_count(), 0, "the salvage grid actually renders the bag gear (not an empty/collapsed panel)")
	# Multi-select two pieces, then batch-salvage them.
	m._toggle_salvage_pick(gear[0])
	m._toggle_salvage_pick(gear[1])
	assert_eq(m._salvage_picks.size(), 2, "two pieces selected")
	var bag_before := GameState.bag_equipment.size()
	m._do_salvage()
	assert_eq(GameState.bag_equipment.size(), bag_before - 2, "batch salvage consumes every selected piece")
	assert_eq(int(m._salvage_summary["count"]), 2, "the summary reports the batch count")
	assert_gt((m._salvage_summary["mats"] as Dictionary).size(), 0, "the summary lists the gained materials")


func test_tower_modal_builds_and_climbs_each_difficulty() -> void:
	var m := _Tower.new()
	add_child_autofree(m)
	await get_tree().process_frame
	for d in ["easy", "hard", "hell"]:
		m._set_diff(d)
		await get_tree().process_frame
		assert_eq(m._diff, d, "tower shows the %s track" % d)
	# A climb resolves (clear or fail) without a runtime error.
	m._set_diff("easy")
	m._climb()
	await get_tree().process_frame
	assert_between(int(GameState.tower_floor["easy"]), 0, 1, "an easy climb resolves to floor 0 (failed) or 1 (cleared)")
