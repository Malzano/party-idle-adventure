extends Control
## Dev utility: open the Crafting House, select the worn weapon into the anvil,
## and simulate a successful upgrade so the stat lines show new values + green
## (+delta). Run WINDOWED:  godot --path . res://test/CaptureForge.tscn


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	DirAccess.make_dir_recursive_absolute("res://_shots")
	var bg := ColorRect.new()
	bg.color = Palette.BG_0
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	GameState.reset_to_defaults()
	GameState.choose_class("warrior", "Iconsmith")
	GameState.equipped[5] = GameContent.gear_to_item(GameContent.GEAR_R[0])  # Main Hand (Maul)
	GameState.equipped[0] = GameContent.gear_to_item(GameContent.GEAR_L[0])  # Helm
	# Gold + materials come from choose_class's mock seed — the Upgrade button
	# should be enabled without setting them here.
	PlayerStats.invalidate()

	var forge := preload("res://scenes/camp/ForgeModal.gd").new()
	add_child(forge)
	call_deferred("_snap", forge)


func _snap(_forge: Control) -> void:
	# Capture the just-opened state: the anvil slot must start EMPTY (drop target).
	await get_tree().create_timer(0.7).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://_shots/forge.png")
	print("FORGE_SHOT_SAVED %dx%d" % [img.get_width(), img.get_height()])
	get_tree().quit()
