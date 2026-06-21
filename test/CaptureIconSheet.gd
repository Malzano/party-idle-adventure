extends Control
## Dev utility: render every GearIcon glyph kind in a labeled, rarity-framed grid
## so the icon set can be eyeballed. Run WINDOWED:
##   godot --path . res://test/CaptureIconSheet.tscn


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	DirAccess.make_dir_recursive_absolute("res://_shots")
	var bg := ColorRect.new()
	bg.color = Palette.BG_0
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var kinds := ["helm", "amulet", "body", "gloves", "boots", "sword", "shield", "ring",
		"belt", "ingot", "gem", "relic", "flask", "food", "scroll", "key"]
	var rars := ["legendary", "epic", "rare", "uncommon", "common", "mythic"]

	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 24)
	add_child(grid)
	grid.position = Vector2(300, 360)
	for i in kinds.size():
		var rar: String = rars[i % rars.size()]
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 6)
		var box := Panel.new()
		box.custom_minimum_size = Vector2(132, 132)
		box.add_theme_stylebox_override("panel", Style.slot_box(rar, true))
		var ic := GearIcon.new(kinds[i], Palette.rarity_color(rar))
		box.add_child(ic)
		ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ic.offset_left = 16
		ic.offset_top = 16
		ic.offset_right = -16
		ic.offset_bottom = -16
		cell.add_child(box)
		var lbl := Style.pixel_label(String(kinds[i]).to_upper(), 10, Palette.TX_MUTE)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(lbl)
		grid.add_child(cell)
	call_deferred("_snap")


func _snap() -> void:
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://_shots/icon_sheet.png")
	print("ICON_SHEET_SAVED %dx%d" % [img.get_width(), img.get_height()])
	get_tree().quit()
