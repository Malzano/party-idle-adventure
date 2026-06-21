extends Control
## Dev utility: build the real Main (Fight HUD) and snap it — to eyeball the
## collapsed Auto-Loot dropdown button. Run WINDOWED:
##   godot --path . res://test/CaptureFight.tscn


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	DirAccess.make_dir_recursive_absolute("res://_shots")
	GameState.reset_to_defaults()
	GameState.choose_class("warrior", "Iconsmith")
	TutorialOverlay._done = true  # capture the HUD, not the first-run tour
	var main := preload("res://scenes/main/Main.tscn").instantiate() as Control
	add_child(main)
	main.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	call_deferred("_snap")


func _snap() -> void:
	await get_tree().create_timer(1.6).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://_shots/fight.png")
	print("FIGHT_SHOT_SAVED %dx%d" % [img.get_width(), img.get_height()])
	get_tree().quit()
