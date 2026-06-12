extends Control
## PROFILE · PETS tab (petsrelics.jsx PetsTab).
## 340px Active Companion panel | collection grid (4 cols).

var _sel: int = 0
var _active_body: VBoxContainer
var _marks: Array[Control] = []
var _pc_grid: GridContainer
var _coll_count: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_sel = clampi(GameState.active_pet, 0, GameContent.PETS.size() - 1)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_child(_build_active_panel())
	row.add_child(_build_collection())
	# Summons can tame new companions (GameContent.pet_owned milestones), so
	# loadout changes refresh both the grid and the active panel.
	EventBus.loadout_changed.connect(_on_loadout_changed, CONNECT_DEFERRED)
	_refresh_active()


func _on_loadout_changed() -> void:
	_rebuild_collection()
	_refresh_active()


# =========================================================================
# Active Companion (.pet-active)
# =========================================================================

func _build_active_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(340, 0)
	panel.add_theme_stylebox_override("panel", Style.panel_box())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	panel.add_child(col)
	col.add_child(_panel_head("Active Companion"))
	var body_m := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		body_m.add_theme_constant_override(m, 18)
	_active_body = VBoxContainer.new()
	_active_body.add_theme_constant_override("separation", 8)
	body_m.add_child(_active_body)
	col.add_child(body_m)
	return panel


func _refresh_active() -> void:
	for child in _active_body.get_children():
		_active_body.remove_child(child)
		child.queue_free()
	var pet: Dictionary = GameContent.PETS[_sel]
	var rar := String(pet["r"])
	var rc := Palette.rarity_color(rar)
	var owned := GameContent.pet_owned(_sel)
	var is_active := _sel == GameState.active_pet and owned

	# .pa-portrait — 190px rarity-bordered pixel slot.
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(190, 190)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ps := PixelSlot.new("160²\n%s" % String(pet["n"]), true)
	holder.add_child(ps)
	ps.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var border := Panel.new()
	var b_sb := StyleBoxFlat.new()
	b_sb.draw_center = false
	b_sb.set_border_width_all(2)
	b_sb.border_color = rc
	b_sb.set_corner_radius_all(6)
	b_sb.shadow_color = Palette.with_alpha(rc, 0.36 * Palette.GLOW)
	b_sb.shadow_size = int(20 * Palette.GLOW)
	border.add_theme_stylebox_override("panel", b_sb)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(border)
	border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_active_body.add_child(holder)

	# .pa-name / .pa-role
	var nm := Style.display_label(String(pet["n"]), 26, rc, true)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_active_body.add_child(nm)
	var role := Style.body_label(("%s · %s" % [pet["role"], rar]).to_upper(), 12, Palette.TX_MUTE)
	role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_active_body.add_child(role)

	# .pa-eff — AURA keycap + effect.
	var aura := HBoxContainer.new()
	aura.add_theme_constant_override("separation", 8)
	aura.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	aura.add_child(Style.make_keycap("AURA"))
	var eff := Style.body_label(String(pet["eff"]), 13, Palette.CYAN_BRIGHT)
	eff.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	aura.add_child(eff)
	_active_body.add_child(aura)

	# .pa-stats — 3 inset rows.
	var stats_col := VBoxContainer.new()
	stats_col.add_theme_constant_override("separation", 7)
	stats_col.add_child(_pa_stat("Bond Level", "Lv 6", Palette.TX))
	stats_col.add_child(_pa_stat("Active Skill", "Cinder Breath", Palette.CYAN_BRIGHT))
	stats_col.add_child(_pa_stat("Cooldown", "12s", Palette.TX))
	_active_body.add_child(stats_col)

	# State row: equipped / set-active / locked.
	if is_active:
		var on := Style.body_label("● Currently Active", 13, Palette.R_UNCOMMON)
		on.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_active_body.add_child(on)
	elif owned:
		var btn := Style.make_button("Set Active", "ember")
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.pressed.connect(_on_set_active)
		_active_body.add_child(btn)
	else:
		var need := GameContent.pet_unlock_need(_sel)
		var text := "Not yet tamed"
		if need > 0:
			text = "Follows after %d summons (%d/%d)" % [need, GameState.roster_extra.size(), need]
		var locked := Style.display_label(text, 13, Palette.TX_MUTE, true)
		locked.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_active_body.add_child(locked)


func _on_set_active() -> void:
	GameState.set_active_pet(_sel)


func _pa_stat(label_text: String, value_text: String, value_color: Color) -> Control:
	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("100d09")
	sb.set_border_width_all(1)
	sb.border_color = Palette.IRON_EDGE
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	row.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	var k := Style.body_label(label_text, 13, Palette.TX_DIM)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(k)
	h.add_child(Style.body_label(value_text, 13, value_color))
	row.add_child(h)
	return row


# =========================================================================
# Collection (.pet-collection)
# =========================================================================

func _build_collection() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", Style.panel_box())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	panel.add_child(col)
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", Style.head_box())
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.add_child(_ember_diamond(8.0))
	h.add_child(Style.display_label("COLLECTION", 14, Palette.GOLD))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(sp)
	_coll_count = Style.pixel_label("", 10, Palette.TX_MUTE)
	_coll_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_coll_count)
	head.add_child(h)
	col.add_child(head)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var gm := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		gm.add_theme_constant_override(m, 16)
	gm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pc_grid = GridContainer.new()
	_pc_grid.columns = 4
	_pc_grid.add_theme_constant_override("h_separation", 12)
	_pc_grid.add_theme_constant_override("v_separation", 12)
	_pc_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pc_grid.resized.connect(func() -> void: _resize_square_cells(_pc_grid, 4, 12.0))
	_rebuild_collection()
	gm.add_child(_pc_grid)
	scroll.add_child(gm)
	col.add_child(scroll)
	return panel


## (Re)fill the grid — ownership is live (design flags + summon milestones).
func _rebuild_collection() -> void:
	for child in _pc_grid.get_children():
		_pc_grid.remove_child(child)
		child.queue_free()
	_marks.clear()
	var owned_count := 0
	for i in GameContent.PETS.size():
		if GameContent.pet_owned(i):
			owned_count += 1
		_pc_grid.add_child(_pc_cell(i))
	if _coll_count != null:
		_coll_count.text = "%d / %d" % [owned_count, GameContent.PETS.size()]
	_resize_square_cells(_pc_grid, 4, 12.0)


func _pc_cell(index: int) -> Control:
	var p: Dictionary = GameContent.PETS[index]
	var owned := GameContent.pet_owned(index)
	var rar := String(p["r"])
	var cell := Control.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# Faded inner visuals when unowned (.pc-cell:not(.filled) opacity .5).
	var inner := Control.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not owned:
		inner.modulate = Color(1, 1, 1, 0.5)
	cell.add_child(inner)
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := Panel.new()
	box.add_theme_stylebox_override("panel", Style.slot_box(rar, owned))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ps := PixelSlot.new("64²" if owned else "?", owned)
	inner.add_child(ps)
	ps.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ps.offset_left = 4
	ps.offset_top = 4
	ps.offset_right = -4
	ps.offset_bottom = -4
	if not owned:
		var lock := Style.body_label("🔒", 20, Palette.TX_DIM)
		lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(lock)
		lock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# .pc-cell.sel — ember outline, offset 2.
	var mark := SelOutline.new()
	mark.visible = index == _sel
	cell.add_child(mark)
	mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_marks.append(mark)

	cell.gui_input.connect(_on_cell_input.bind(index))
	var tip := {
		"name": p["n"],
		"type": "%s · %s" % [p["role"], rar],
		"rarity": rar,
		"stats": [["Aura", p["eff"]]],
	}
	if not owned:
		var need := GameContent.pet_unlock_need(index)
		tip["flavor"] = ("Follows after %d summons (%d/%d)." % [need, GameState.roster_extra.size(), need]) \
			if need > 0 else "Tame this companion in the wild."
	Tip.attach(cell, tip)
	return cell


func _on_cell_input(event: InputEvent, index: int) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_select(index)


func _select(index: int) -> void:
	_sel = index
	for i in _marks.size():
		_marks[i].visible = i == _sel
	_refresh_active()


# =========================================================================
# Shared bits
# =========================================================================

func _panel_head(title: String, right_text: String = "") -> Control:
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", Style.head_box())
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.add_child(_ember_diamond(8.0))
	h.add_child(Style.display_label(title.to_upper(), 14, Palette.GOLD))
	if right_text != "":
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(sp)
		var r := Style.pixel_label(right_text, 10, Palette.TX_MUTE)
		r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(r)
	head.add_child(h)
	return head


func _ember_diamond(px: float) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(px + 4, px + 4)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sq := ColorRect.new()
	sq.color = Palette.EMBER
	sq.size = Vector2(px, px)
	sq.pivot_offset = Vector2(px * 0.5, px * 0.5)
	sq.position = Vector2((px + 4.0) * 0.5 - px * 0.5, (px + 4.0) * 0.5 - px * 0.5)
	sq.rotation = deg_to_rad(45.0)
	sq.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(sq)
	return holder


func _resize_square_cells(grid: GridContainer, cols: int, gap: float) -> void:
	var cw := floorf((grid.size.x - gap * float(cols - 1)) / float(cols))
	if cw < 10.0:
		return
	for c in grid.get_children():
		var ctl := c as Control
		if ctl != null and absf(ctl.custom_minimum_size.y - cw) > 0.5:
			ctl.custom_minimum_size = Vector2(0, cw)


## Ember selection outline drawn 2px outside the cell bounds.
class SelOutline:
	extends Control

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		draw_rect(Rect2(Vector2(-2, -2), size + Vector2(4, 4)), Palette.EMBER, false, 2.0)
