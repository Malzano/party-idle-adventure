extends "res://scenes/camp/ModalShell.gd"
## HEARTHFIRE KITCHEN modal (camp.jsx FoodModal): 3×2 recipe grid (96px
## rarity slots, locked recipes disabled at 50%) | cook panel with the
## selected dish, its buff, and a Cook Meal CTA that applies the party food
## buff via GameState.set_food_buff. Enter cooks the selected meal.

var _sel := 0
var _outlines: Array[Control] = []
var _panel_col: VBoxContainer
var _buff_lbl: Label


func _init() -> void:
	modal_title = "Hearthfire Kitchen"
	modal_width = 880.0
	body_separation = 0


func _build_body(body: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	body.add_child(row)

	# Recipe grid (3 × 96px columns).
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	for i in GameContent.RECIPES.size():
		grid.add_child(_make_cell(i))
	row.add_child(grid)

	# Cook panel (left hairline, centered column).
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_width_left = 1
	sb.border_color = Palette.IRON_EDGE
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel_col = VBoxContainer.new()
	_panel_col.add_theme_constant_override("separation", 10)
	_panel_col.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(_panel_col)
	row.add_child(panel)

	# 1s tick so the active-buff countdown stays live while the modal is open.
	var tick := Timer.new()
	tick.wait_time = 1.0
	tick.autostart = true
	tick.timeout.connect(_update_buff_line)
	add_child(tick)

	_refresh_panel()


func _on_modal_key(keycode: Key) -> bool:
	if keycode == KEY_ENTER or keycode == KEY_KP_ENTER:
		_cook()
		return true
	return false


# =========================================================================
# Recipe cells (.recipe)
# =========================================================================

func _make_cell(i: int) -> Control:
	var rc: Dictionary = GameContent.RECIPES[i]
	var rar := String(rc["r"])
	var have := bool(rc["have"])

	var cell := Control.new()
	cell.custom_minimum_size = Vector2(96, 96)

	var frame := Panel.new()
	frame.add_theme_stylebox_override("panel", Style.slot_box(rar, have))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var ps := PixelSlot.new("64²\ndish" if have else "locked", true)
	cell.add_child(ps)
	ps.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ps.offset_left = 4
	ps.offset_top = 4
	ps.offset_right = -4
	ps.offset_bottom = -4

	# Selection outline (2px ember, 2px outside the slot).
	var outline := Panel.new()
	var osb := StyleBoxFlat.new()
	osb.draw_center = false
	osb.set_border_width_all(2)
	osb.border_color = Palette.EMBER
	osb.set_corner_radius_all(4)
	outline.add_theme_stylebox_override("panel", osb)
	outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outline.position = Vector2(-4, -4)
	outline.size = Vector2(104, 104)
	outline.visible = _sel == i
	cell.add_child(outline)
	_outlines.append(outline)

	if not have:
		cell.modulate = Color(1, 1, 1, 0.5)
	else:
		cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		cell.gui_input.connect(func(ev: InputEvent) -> void:
			var mb := ev as InputEventMouseButton
			if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				_select(i))

	var tip := {
		"name": String(rc["n"]),
		"type": "Recipe · Party buff",
		"rarity": rar,
		"stats": [["Effect", String(rc["b"])]],
	}
	if not have:
		tip["flavor"] = "Recipe not yet discovered."
	Tip.attach(cell, tip)
	return cell


func _select(i: int) -> void:
	_sel = i
	for j in _outlines.size():
		_outlines[j].visible = j == _sel
	_refresh_panel()


# =========================================================================
# Cook panel (.cook-panel)
# =========================================================================

func _refresh_panel() -> void:
	for child in _panel_col.get_children():
		_panel_col.remove_child(child)
		child.queue_free()
	var rc: Dictionary = GameContent.RECIPES[_sel]

	var dish := Control.new()
	dish.custom_minimum_size = Vector2(150, 150)
	dish.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	dish.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ps := PixelSlot.new("128²\n%s" % String(rc["n"]), true)
	dish.add_child(ps)
	ps.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var border := Panel.new()
	var bsb := StyleBoxFlat.new()
	bsb.draw_center = false
	bsb.set_border_width_all(1)
	bsb.border_color = Palette.GOLD_DIM
	bsb.set_corner_radius_all(5)
	border.add_theme_stylebox_override("panel", bsb)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dish.add_child(border)
	border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel_col.add_child(dish)

	var nm := Style.display_label(String(rc["n"]), 22, Palette.GOLD_BRIGHT, true)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel_col.add_child(nm)

	var buff := Style.body_label(String(rc["b"]), 14, Palette.CYAN_BRIGHT)
	buff.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel_col.add_child(buff)

	var note := Style.display_label("Applies to all 4 party members on next delve.", 12, Palette.TX_MUTE, true)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(260, 0)
	note.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_panel_col.add_child(note)

	_buff_lbl = Style.body_label("", 12, Palette.CYAN_BRIGHT)
	_buff_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel_col.add_child(_buff_lbl)
	_update_buff_line()

	var cook := Style.make_button("Cook Meal   ↵", "ember")
	cook.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cook.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	cook.pressed.connect(_cook)
	_panel_col.add_child(cook)


## "<name> active · <m>m <s>s left" while a meal buff runs, else "No meal active".
func _update_buff_line() -> void:
	if _buff_lbl == null or not is_instance_valid(_buff_lbl):
		return
	if GameState.food_buff_active():
		var left := maxi(0, GameState.food_buff_until - GameState.now_utc())
		_buff_lbl.text = "%s active · %dm %ds left" % [GameState.food_buff, int(left / 60.0), left % 60]
		_buff_lbl.add_theme_color_override("font_color", Palette.CYAN_BRIGHT)
	else:
		_buff_lbl.text = "No meal active"
		_buff_lbl.add_theme_color_override("font_color", Palette.TX_MUTE)


func _cook() -> void:
	var rc: Dictionary = GameContent.RECIPES[_sel]
	if not bool(rc["have"]):
		return
	var b := String(rc["b"])
	GameState.set_food_buff(String(rc["n"]), b, _parse_duration(b))
	_update_buff_line()


## "+12% party ATK · 30 min" → 1800; "… · 15 min" → 900; no duration → 1800.
func _parse_duration(b: String) -> int:
	var re := RegEx.new()
	re.compile(r"(\d+)\s*min")
	var m := re.search(b)
	if m == null:
		return 1800
	return int(m.get_string(1)) * 60
