extends Control
## Dev utility: open the Hero window on the Equipment tab in the real game state
## (empty paperdoll + the mock bag seeded at class-select) and save a PNG, to
## eyeball the reverted 5+5 paperdoll, the slot glyphs, and the bag footprint
## badges. Run WINDOWED (headless can't render to texture):
##   godot --path . res://test/CaptureIcons.tscn


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	DirAccess.make_dir_recursive_absolute("res://_shots")
	var bg := ColorRect.new()
	bg.color = Palette.BG_0
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Real fresh-delver state: empty paperdoll, the mock bag (choose_class seeds it).
	GameState.reset_to_defaults()
	GameState.choose_class("warrior", "Iconsmith")
	PlayerStats.invalidate()

	var hero := preload("res://scenes/hero/Hero.tscn").instantiate() as Control
	add_child(hero)
	hero.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	call_deferred("_snap")


func _snap() -> void:
	await get_tree().create_timer(0.7).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://_shots/icons_hero_equipment.png")
	print("ICONS_SHOT_SAVED %dx%d" % [img.get_width(), img.get_height()])
	get_tree().quit()
