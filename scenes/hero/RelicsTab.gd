extends Control
## PROFILE · RELICS tab (petsrelics.jsx RelicsTab).
## Equipped Relics 3×2 grid | 360px side: Active Bonuses + Vault.

var _re_area: Control
var _re_cells: Array[Control] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_child(_build_equipped())
	row.add_child(_build_side())


# =========================================================================
# Equipped Relics (.relic-equipped)
# =========================================================================

func _build_equipped() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", Style.panel_box())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	panel.add_child(col)
	var filled := 0
	for rl in GameContent.RELICS:
		if not bool(rl["empty"]):
			filled += 1
	col.add_child(_panel_head("Equipped Relics", "%d / %d" % [filled, GameContent.RELICS.size()]))

	var pad := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(m, 22)
	pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_re_area = Control.new()
	_re_area.mouse_filter = Control.MOUSE_FILTER_PASS
	for rl_v in GameContent.RELICS:
		var cell := _re_cell(rl_v)
		_re_area.add_child(cell)
		_re_cells.append(cell)
	_re_area.resized.connect(_layout_equipped)
	pad.add_child(_re_area)
	col.add_child(pad)
	return panel


func _layout_equipped() -> void:
	var s := _re_area.size
	if s.x <= 0.0 or s.y <= 0.0:
		return
	var cs := minf((s.x - 32.0) / 3.0, (s.y - 16.0) / 2.0)
	cs = maxf(cs, 40.0)
	var total_w := cs * 3.0 + 32.0
	var total_h := cs * 2.0 + 16.0
	var x0 := (s.x - total_w) * 0.5
	var y0 := (s.y - total_h) * 0.5
	for i in _re_cells.size():
		var cx := i % 3
		var cy := int(floor(float(i) / 3.0))
		_re_cells[i].position = Vector2(x0 + float(cx) * (cs + 16.0), y0 + float(cy) * (cs + 16.0))
		_re_cells[i].size = Vector2(cs, cs)


func _re_cell(rl: Dictionary) -> Control:
	var cell := Control.new()
	var is_empty := bool(rl["empty"])
	var rar := String(rl["r"])
	var box := Panel.new()
	box.add_theme_stylebox_override("panel", Style.slot_box(rar, not is_empty))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if is_empty:
		# .re-empty — "＋ EMPTY" faint centered.
		var center := VBoxContainer.new()
		center.alignment = BoxContainer.ALIGNMENT_CENTER
		center.add_theme_constant_override("separation", 4)
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var plus := Style.body_label("＋", 30, Palette.TX_FAINT)
		plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		center.add_child(plus)
		var lbl := Style.body_label("EMPTY", 11, Palette.TX_FAINT)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		center.add_child(lbl)
		cell.add_child(center)
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var ps := PixelSlot.new("72²\n%s" % String(rl["n"]), true)
		cell.add_child(ps)
		ps.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ps.offset_left = 5
		ps.offset_top = 5
		ps.offset_right = -5
		ps.offset_bottom = -5
		Tip.attach(cell, {
			"name": rl["n"],
			"type": "Relic · %s" % rar,
			"rarity": rar,
			"stats": [["Bonus", rl["eff"]]],
			"flavor": "Relics carry the echoes of fallen delvers.",
		})
	return cell


# =========================================================================
# Side column (.relic-side): Active Bonuses + Vault
# =========================================================================

func _build_side() -> Control:
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(360, 0)
	side.add_theme_constant_override("separation", 14)

	# Active Bonuses (.relic-bonus).
	var bonus := PanelContainer.new()
	bonus.add_theme_stylebox_override("panel", Style.panel_box())
	bonus.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var b_col := VBoxContainer.new()
	b_col.add_theme_constant_override("separation", 0)
	bonus.add_child(b_col)
	b_col.add_child(_panel_head("Active Bonuses"))
	var list_m := MarginContainer.new()
	list_m.add_theme_constant_override("margin_left", 16)
	list_m.add_theme_constant_override("margin_right", 16)
	list_m.add_theme_constant_override("margin_top", 12)
	list_m.add_theme_constant_override("margin_bottom", 12)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 9)
	for rl_v in GameContent.RELICS:
		var rl: Dictionary = rl_v
		if bool(rl["empty"]):
			continue
		var rc := Palette.rarity_color(String(rl["r"]))
		var rrow := HBoxContainer.new()
		rrow.add_theme_constant_override("separation", 9)
		rrow.add_child(GlowDot.new(8.0, rc))
		var nm := Style.display_label(String(rl["n"]), 13, rc, true)
		nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rrow.add_child(nm)
		var eff := Style.body_label(String(rl["eff"]), 12, Palette.TX_MUTE)
		eff.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		eff.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		eff.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		eff.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rrow.add_child(eff)
		list.add_child(rrow)
	# .rb-set — top hairline + set bonus line.
	var set_row := PanelContainer.new()
	var set_sb := StyleBoxFlat.new()
	set_sb.bg_color = Color(0, 0, 0, 0)
	set_sb.border_width_top = 1
	set_sb.border_color = Palette.IRON_EDGE
	set_sb.content_margin_top = 10
	set_row.add_theme_stylebox_override("panel", set_sb)
	var set_h := HBoxContainer.new()
	set_h.add_theme_constant_override("separation", 0)
	set_h.add_child(Style.body_label("Set Bonus (4/6): ", 12, Palette.TX_DIM))
	set_h.add_child(Style.body_label("+15% Relic Power", 12, Palette.EMBER_BRIGHT))
	set_row.add_child(set_h)
	var set_m := MarginContainer.new()
	set_m.add_theme_constant_override("margin_top", 6)
	set_m.add_child(set_row)
	list.add_child(set_m)
	list_m.add_child(list)
	b_col.add_child(list_m)
	side.add_child(bonus)

	# Vault (.relic-coll).
	var vault := PanelContainer.new()
	vault.add_theme_stylebox_override("panel", Style.panel_box())
	vault.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v_col := VBoxContainer.new()
	v_col.add_theme_constant_override("separation", 0)
	vault.add_child(v_col)
	v_col.add_child(_panel_head("Vault"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var gm := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		gm.add_theme_constant_override(m, 14)
	gm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.resized.connect(func() -> void: _resize_square_cells(grid, 4, 10.0))
	for r_v in GameContent.RELIC_COLL:
		grid.add_child(_vault_cell(r_v))
	gm.add_child(grid)
	scroll.add_child(gm)
	v_col.add_child(scroll)
	side.add_child(vault)
	return side


func _vault_cell(r: Dictionary) -> Control:
	var cell := Control.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var rar := String(r["r"])
	var box := Panel.new()
	box.add_theme_stylebox_override("panel", Style.slot_box(rar, true))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ps := PixelSlot.new("48²", true)
	cell.add_child(ps)
	ps.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ps.offset_left = 3
	ps.offset_top = 3
	ps.offset_right = -3
	ps.offset_bottom = -3
	Tip.attach(cell, {
		"name": r["n"],
		"type": "Relic · %s" % rar,
		"rarity": rar,
		"flavor": "Drag to an equipped slot.",
	})
	return cell


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


## Glowing rarity dot (.rb-dot).
class GlowDot:
	extends Control

	var dot_size := 8.0
	var dot_color := Color.WHITE

	func _init(p_size: float = 8.0, p_color: Color = Color.WHITE) -> void:
		dot_size = p_size
		dot_color = p_color
		custom_minimum_size = Vector2(dot_size, dot_size)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		draw_circle(c, dot_size * 0.5 + 3.0, Palette.with_alpha(dot_color, 0.22 * Palette.GLOW))
		draw_circle(c, dot_size * 0.5, dot_color)
