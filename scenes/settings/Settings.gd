extends Control
## OPTIONS window (design v2 settings.jsx): Audio / Display / Combat panels
## with gothic sliders + toggle pills, Restore Defaults, version footer.
## Values live in the UserSettings autoload (persisted + engine-applied).


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	add_child(col)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 220
	col.offset_right = -220
	col.offset_top = 120
	col.offset_bottom = -120
	col.add_child(_build_head())
	col.add_child(_build_body())


func _build_head() -> Control:
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", Style.head_box())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	head.add_child(row)
	row.add_child(Style.display_label("OPTIONS", 24, Palette.GOLD_BRIGHT))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sp)
	var x := Button.new()
	x.text = "✕"
	x.focus_mode = Control.FOCUS_NONE
	x.custom_minimum_size = Vector2(36, 36)
	x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	x.add_theme_font_size_override("font_size", Style.fs(18))
	x.add_theme_color_override("font_color", Palette.TX_DIM)
	x.add_theme_color_override("font_hover_color", Palette.EMBER_BRIGHT)
	var xsb := StyleBoxFlat.new()
	xsb.bg_color = Palette.STONE
	xsb.set_border_width_all(1)
	xsb.border_color = Palette.IRON_EDGE
	xsb.set_corner_radius_all(3)
	for state in ["normal", "hover", "pressed"]:
		x.add_theme_stylebox_override(state, xsb)
	x.pressed.connect(func() -> void: WindowManager.close(WindowManager.WIN_SETTINGS))
	row.add_child(x)
	return head


func _build_body() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", Style.panel_box())
	var pad := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(m, 18)
	panel.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	pad.add_child(col)

	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 14)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# --- Audio ---
	var audio := _panel("AUDIO")
	var audio_list: VBoxContainer = audio.get_meta("list")
	audio_list.add_child(_slider_row("Master", "master"))
	audio_list.add_child(_slider_row("Music", "music"))
	audio_list.add_child(_slider_row("Effects", "sfx"))
	grid.add_child(audio)

	# --- Display ---
	var display := _panel("DISPLAY")
	var display_list: VBoxContainer = display.get_meta("list")
	display_list.add_child(_quality_row())
	display_list.add_child(_toggle_row("V-Sync", "vsync"))
	display_list.add_child(_toggle_row("Fullscreen", "fullscreen"))
	grid.add_child(display)

	# --- Combat ---
	var combat := _panel("COMBAT")
	var combat_list: VBoxContainer = combat.get_meta("list")
	combat_list.add_child(_toggle_row("Damage numbers", "dmg_numbers"))
	combat_list.add_child(_toggle_row("Screen shake", "screen_shake"))
	combat_list.add_child(_toggle_row("Pause on boss", "boss_pause"))
	grid.add_child(combat)
	col.add_child(grid)

	# --- Footer ---
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	var restore := Style.make_button("RESTORE DEFAULTS", "ghost", 11)
	restore.pressed.connect(func() -> void:
		UserSettings.restore_defaults()
		_rebuild())
	foot.add_child(restore)
	# Replay the first-session tutorial any time — close Options, then start it.
	var replay := Style.make_button("REPLAY TUTORIAL", "ember", 11)
	replay.pressed.connect(func() -> void:
		WindowManager.close(WindowManager.WIN_SETTINGS)
		TutorialOverlay.start())
	foot.add_child(replay)
	var fsp := Control.new()
	fsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fsp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_child(fsp)
	var version := Style.pixel_label("%s · PROTOTYPE" % GameContent.GAME_TITLE.to_upper(), 6, Palette.TX_FAINT)
	version.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(version)
	col.add_child(foot)
	return panel


## Settings windows are cheap — full rebuild keeps every readout honest.
func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_ready()


func _panel(title: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_theme_stylebox_override("panel", Style.panel_box(true))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	p.add_child(col)
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", Style.head_box())
	var hrow := HBoxContainer.new()
	hrow.add_child(Style.display_label(title, 14, Palette.GOLD))
	head.add_child(hrow)
	col.add_child(head)
	var pad := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(m, 14)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	pad.add_child(list)
	col.add_child(pad)
	p.set_meta("list", list)
	return p


func _slider_row(label_text: String, key: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var lbl := Style.body_label(label_text, 9, Palette.TX_DIM)
	lbl.custom_minimum_size = Vector2(110, 0)
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lbl)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.value = float(UserSettings.get_value(key))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(0, 24)
	row.add_child(slider)
	var val := Style.pixel_label(str(int(slider.value)), 8, Palette.EMBER_BRIGHT)
	val.custom_minimum_size = Vector2(44, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(val)
	slider.value_changed.connect(func(v: float) -> void:
		val.text = str(int(v))
		UserSettings.set_value(key, int(v)))
	return row


## Gothic toggle pill (design .set-toggle): label left, ember pill right.
func _toggle_row(label_text: String, key: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var lbl := Style.body_label(label_text, 9, Palette.TX_DIM)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lbl)
	var pill := Button.new()
	pill.toggle_mode = true
	pill.button_pressed = UserSettings.get_bool(key)
	pill.focus_mode = Control.FOCUS_ALL
	pill.add_theme_stylebox_override("focus", Style.focus_ring())
	pill.custom_minimum_size = Vector2(64, 30)
	pill.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var restyle := func() -> void:
		var on := pill.button_pressed
		pill.text = "ON" if on else "OFF"
		var psb := StyleBoxFlat.new()
		psb.bg_color = Color(120.0 / 255.0, 72.0 / 255.0, 28.0 / 255.0, 0.5) if on else Color("0c0a07")
		psb.set_border_width_all(1)
		psb.border_color = Palette.EMBER_DEEP if on else Palette.IRON_EDGE
		psb.set_corner_radius_all(12)
		if on:
			psb.shadow_color = Palette.with_alpha(Palette.EMBER, 0.3 * Palette.GLOW)
			psb.shadow_size = int(10 * Palette.GLOW)
		for state in ["normal", "hover", "pressed"]:
			pill.add_theme_stylebox_override(state, psb)
		pill.add_theme_color_override("font_color", Palette.EMBER_BRIGHT if on else Palette.TX_FAINT)
		pill.add_theme_color_override("font_hover_color", Palette.EMBER_BRIGHT if on else Palette.TX_DIM)
	var f := Fonts.pixel()
	if f != null:
		pill.add_theme_font_override("font", f)
	pill.add_theme_font_size_override("font_size", Style.fs(6))
	pill.toggled.connect(func(on: bool) -> void:
		UserSettings.set_value(key, on)
		restyle.call())
	restyle.call()
	row.add_child(pill)
	return row


func _quality_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var lbl := Style.body_label("Quality", 9, Palette.TX_DIM)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lbl)
	var seg := HBoxContainer.new()
	seg.add_theme_constant_override("separation", 4)
	var btns: Dictionary = {}
	var restyle := func() -> void:
		var current := String(UserSettings.get_value("quality"))
		for q in btns:
			var b: Button = btns[q]
			b.add_theme_color_override("font_color",
				Palette.EMBER_BRIGHT if String(q) == current else Palette.TX_DIM)
	for q in ["Low", "Med", "High"]:
		var b := Style.make_button(q, "ghost", 9)
		b.pressed.connect(func() -> void:
			UserSettings.set_value("quality", q)
			restyle.call())
		btns[q] = b
		seg.add_child(b)
	restyle.call()
	row.add_child(seg)
	return row
