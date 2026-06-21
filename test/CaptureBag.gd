extends Control
## Dev utility: a mixed loadout — a few pieces worn on the paperdoll, the rest in
## the bag — then open the Hero window on the Bag tab and snap. Verifies the ALL
## ITEMS list shows both, with worn pieces tagged EQUIPPED. Run WINDOWED:
##   godot --path . res://test/CaptureBag.tscn


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	DirAccess.make_dir_recursive_absolute("res://_shots")
	var bg := ColorRect.new()
	bg.color = Palette.BG_0
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	GameState.reset_to_defaults()
	GameState.choose_class("warrior", "Iconsmith")
	GameState.bag_equipment.clear()
	# Wear four pieces; the rest sit in the bag — ALL ITEMS lists both.
	GameState.equipped[0] = GameContent.gear_to_item(GameContent.GEAR_L[0])  # Helm
	GameState.equipped[2] = GameContent.gear_to_item(GameContent.GEAR_L[2])  # Body
	GameState.equipped[5] = GameContent.gear_to_item(GameContent.GEAR_R[0])  # Main Hand
	GameState.equipped[6] = GameContent.gear_to_item(GameContent.GEAR_R[1])  # Off Hand
	for g in [GameContent.GEAR_L[1], GameContent.GEAR_L[3], GameContent.GEAR_L[4],
			GameContent.GEAR_R[2], GameContent.GEAR_R[3], GameContent.GEAR_R[4]]:
		GameState.bag_equipment.append(GameContent.gear_to_item(g))
	PlayerStats.invalidate()

	var hero := preload("res://scenes/hero/Hero.tscn").instantiate() as Control
	add_child(hero)
	hero.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hero.call("_select_tab", 4)  # Bag tab
	call_deferred("_snap")


func _snap() -> void:
	await get_tree().create_timer(0.7).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://_shots/bag_tab.png")
	print("BAG_SHOT_SAVED %dx%d" % [img.get_width(), img.get_height()])
	get_tree().quit()
