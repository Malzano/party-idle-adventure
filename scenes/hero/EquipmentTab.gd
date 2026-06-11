extends Control
## PROFILE · EQUIPMENT tab (profile.jsx EquipmentTab).
## 3-zone grid: 332px character sheet | 568px paperdoll | rest inventory.
## All combat/attribute/derived numbers are live from PlayerStats.compute(),
## refreshed on EventBus.sim_stats_changed while the tab is visible.

var _show_all := false
var _inv_tab: String = "equipment"
var _stats_dirty := false

var _det_list: VBoxContainer
var _det_toggle: Button
var _inv_grid: GridContainer
var _inv_tab_buttons: Dictionary = {}
var _cap_num: Label
var _gold_val: Label
var _soul_val: Label
var _dust_val: Label
var _combat_vals: Array[Label] = []
var _attr_vals: Array[Label] = []
var _plate_num: Label

var _pd_area: Control
var _pd_figure: Control
var _pd_plate: PanelContainer
var _pd_left: Array[Control] = []
var _pd_right: Array[Control] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_child(_build_char_sheet())
	row.add_child(_build_paperdoll())
	row.add_child(_build_inventory())
	EventBus.currencies_changed.connect(_refresh_currencies)
	EventBus.sim_stats_changed.connect(_on_stats_changed)
	visibility_changed.connect(_on_visibility_changed)
	_refresh_currencies()
	_refresh_stats()


func _on_stats_changed() -> void:
	if is_visible_in_tree():
		_refresh_stats()
	else:
		_stats_dirty = true


func _on_visibility_changed() -> void:
	if _stats_dirty and is_visible_in_tree():
		_refresh_stats()


## Pull the computed profile into every live readout.
func _refresh_stats() -> void:
	_stats_dirty = false
	var p := PlayerStats.compute()
	var derived: Dictionary = p["derived"]
	if _combat_vals.size() == 3:
		_combat_vals[0].text = String(p["dps_label"])
		_combat_vals[1].text = Style.group_int(int(derived["armour"]))
		_combat_vals[2].text = Style.group_int(int(derived["maximum_life"]))
	var attrs: Dictionary = p["attrs"]
	var keys: Array[String] = ["strength", "dexterity", "intelligence", "vitality", "luck"]
	for i in _attr_vals.size():
		_attr_vals[i].text = str(int(attrs[keys[i]]))
	if _plate_num != null:
		_plate_num.text = Style.group_int(int(p["gear_power"]))
	_rebuild_det()


# =========================================================================
# Character sheet (.char-sheet)
# =========================================================================

func _build_char_sheet() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(332, 0)
	panel.add_theme_stylebox_override("panel", Style.panel_box())

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	panel.add_child(col)

	# .cs-id — warm head tint + bottom hairline.
	var id_box := PanelContainer.new()
	var id_sb := StyleBoxFlat.new()
	id_sb.bg_color = Color(0.235, 0.196, 0.125, 0.18)
	id_sb.border_width_bottom = 1
	id_sb.border_color = Palette.IRON_EDGE
	id_sb.content_margin_left = 16
	id_sb.content_margin_right = 16
	id_sb.content_margin_top = 16
	id_sb.content_margin_bottom = 12
	id_box.add_theme_stylebox_override("panel", id_sb)
	var id_row := HBoxContainer.new()
	id_row.add_theme_constant_override("separation", 14)
	id_row.add_child(_build_level_badge())
	var id_meta := VBoxContainer.new()
	id_meta.add_theme_constant_override("separation", 4)
	id_meta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	id_meta.add_child(Style.display_label(GameState.player_name, 26, Palette.GOLD_BRIGHT, true))
	id_meta.add_child(Style.body_label("%s · %s" % [GameState.player_title, GameState.player_class], 12, Palette.TX_MUTE))
	id_row.add_child(id_meta)
	id_box.add_child(id_row)
	col.add_child(id_box)

	# .cs-combat — 3 combat summary rows.
	var combat_m := MarginContainer.new()
	combat_m.add_theme_constant_override("margin_left", 16)
	combat_m.add_theme_constant_override("margin_right", 16)
	combat_m.add_theme_constant_override("margin_top", 12)
	combat_m.add_theme_constant_override("margin_bottom", 10)
	var combat_col := VBoxContainer.new()
	combat_col.add_theme_constant_override("separation", 8)
	for entry_v in GameContent.COMBAT_SUMMARY:
		combat_col.add_child(_combat_row(entry_v))
	combat_m.add_child(combat_col)
	col.add_child(combat_m)

	# rune divider, margin 2px 16px.
	var div_m := MarginContainer.new()
	div_m.add_theme_constant_override("margin_left", 16)
	div_m.add_theme_constant_override("margin_right", 16)
	div_m.add_theme_constant_override("margin_top", 2)
	div_m.add_theme_constant_override("margin_bottom", 2)
	div_m.add_child(Style.rune_divider())
	col.add_child(div_m)

	# .cs-attrs — the 5 main attributes.
	var attrs_m := MarginContainer.new()
	attrs_m.add_theme_constant_override("margin_left", 16)
	attrs_m.add_theme_constant_override("margin_right", 16)
	attrs_m.add_theme_constant_override("margin_top", 10)
	attrs_m.add_theme_constant_override("margin_bottom", 6)
	var attrs_col := VBoxContainer.new()
	attrs_col.add_theme_constant_override("separation", 0)
	for s_v in GameContent.MAIN_STATS:
		attrs_col.add_child(_attr_row(s_v))
	attrs_m.add_child(attrs_col)
	col.add_child(attrs_m)

	# .cs-detail margin-top: 6.
	var det_gap := Control.new()
	det_gap.custom_minimum_size = Vector2(0, 6)
	det_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(det_gap)
	col.add_child(_build_detail())
	return panel


# .cs-lvl — rotated diamond level badge with ember glow.
func _build_level_badge() -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(58, 58)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var diamond := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("1f1a11")
	sb.set_border_width_all(1)
	sb.border_color = Palette.GOLD_DIM
	sb.set_corner_radius_all(4)
	sb.shadow_color = Palette.with_alpha(Palette.EMBER, 0.3 * Palette.GLOW)
	sb.shadow_size = int(14 * Palette.GLOW)
	diamond.add_theme_stylebox_override("panel", sb)
	diamond.position = Vector2(6, 6)
	diamond.size = Vector2(46, 46)
	diamond.pivot_offset = Vector2(23, 23)
	diamond.rotation = deg_to_rad(45.0)
	diamond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(diamond)
	var num := Style.pixel_label(str(GameState.player_level), 15, Palette.GOLD_BRIGHT)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	diamond.add_child(num)
	num.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	num.pivot_offset = Vector2(23, 23)
	num.rotation = deg_to_rad(-45.0)
	var tip_data := func() -> Dictionary:
		return {
			"name": "Level %d" % GameState.player_level,
			"type": "Prestige %s" % GameState.prestige,
			"rarity": "legendary",
			"stats": [["XP", "%s / %s" % [Style.group_int(GameState.xp), Style.group_int(GameState.xp_to_next)]]],
		}
	Tip.attach(holder, tip_data)
	return holder


func _summary_color(key: String) -> Color:
	match key:
		"ember":
			return Palette.EMBER_BRIGHT
		"gold":
			return Palette.GOLD
		_:
			return Color("e0584a")


func _combat_box(hover: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("131009")
	sb.set_border_width_all(1)
	sb.border_color = Palette.GOLD_DIM if hover else Palette.IRON_EDGE
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	return sb


func _combat_row(entry: Dictionary) -> Control:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _combat_box(false))
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var c := _summary_color(String(entry["c"]))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 11)
	var ico := Style.body_label(String(entry["ico"]), 16, c)
	ico.custom_minimum_size = Vector2(22, 0)
	ico.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ico.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ico)
	var lbl := Style.body_label(String(entry["lbl"]), 13, Palette.TX_DIM)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(lbl)
	var val := Style.pixel_label(String(entry["val"]), 14, c)
	val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(val)
	_combat_vals.append(val)
	row.add_child(h)
	row.mouse_entered.connect(func() -> void: row.add_theme_stylebox_override("panel", _combat_box(true)))
	row.mouse_exited.connect(func() -> void: row.add_theme_stylebox_override("panel", _combat_box(false)))
	Tip.attach(row, {"name": entry["lbl"], "type": "Combat summary", "rarity": "rare", "stats": entry["st"]})
	return row


func _attr_box(hover: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.275, 0.243, 0.188, 0.16) if hover else Color(0, 0, 0, 0)
	sb.content_margin_left = 2
	sb.content_margin_right = 2
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	return sb


func _attr_row(s: Dictionary) -> Control:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _attr_box(false))
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var c: Color = s["c"]
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	# .cs-attr-key — 36px pixel chip, colored text + border on near-black.
	var chip := PanelContainer.new()
	var chip_sb := StyleBoxFlat.new()
	chip_sb.bg_color = Color("0c0a07")
	chip_sb.set_border_width_all(1)
	chip_sb.border_color = c
	chip_sb.set_corner_radius_all(3)
	chip_sb.content_margin_top = 4
	chip_sb.content_margin_bottom = 4
	chip.add_theme_stylebox_override("panel", chip_sb)
	chip.custom_minimum_size = Vector2(36, 0)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var key_lbl := Style.pixel_label(String(s["k"]), 10, c)
	key_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.add_child(key_lbl)
	h.add_child(chip)
	var nm := Style.body_label(String(s["name"]), 13, Palette.TX_DIM)
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(nm)
	h.add_child(DotLeader.new())
	var val := Style.display_label(str(int(s["v"])), 19, c)
	val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(val)
	_attr_vals.append(val)
	row.add_child(h)
	row.mouse_entered.connect(func() -> void: row.add_theme_stylebox_override("panel", _attr_box(true)))
	row.mouse_exited.connect(func() -> void: row.add_theme_stylebox_override("panel", _attr_box(false)))
	Tip.attach(row, {"name": s["name"], "type": "Primary Attribute", "rarity": "rare", "flavor": s["d"]})
	return row


# .cs-detail — head + scrollable derived stats + show all/less toggle.
func _build_detail() -> Control:
	var wrap := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_width_top = 1
	sb.border_color = Palette.IRON_EDGE
	wrap.add_theme_stylebox_override("panel", sb)
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	wrap.add_child(col)

	var head_m := MarginContainer.new()
	head_m.add_theme_constant_override("margin_left", 16)
	head_m.add_theme_constant_override("margin_right", 16)
	head_m.add_theme_constant_override("margin_top", 10)
	head_m.add_theme_constant_override("margin_bottom", 4)
	head_m.add_child(Style.display_label("DETAILED STATS", 11, Palette.GOLD))
	col.add_child(head_m)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list_m := MarginContainer.new()
	list_m.add_theme_constant_override("margin_left", 16)
	list_m.add_theme_constant_override("margin_right", 16)
	list_m.add_theme_constant_override("margin_top", 2)
	list_m.add_theme_constant_override("margin_bottom", 2)
	list_m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_det_list = VBoxContainer.new()
	_det_list.add_theme_constant_override("separation", 0)
	_det_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_m.add_child(_det_list)
	scroll.add_child(list_m)
	col.add_child(scroll)

	_det_toggle = Button.new()
	_det_toggle.focus_mode = Control.FOCUS_NONE
	_det_toggle.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_det_toggle.add_theme_font_size_override("font_size", 11)
	_det_toggle.add_theme_color_override("font_color", Palette.GOLD)
	_det_toggle.add_theme_color_override("font_hover_color", Palette.EMBER_BRIGHT)
	_det_toggle.add_theme_color_override("font_pressed_color", Palette.GOLD)
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0, 0, 0, 0)
	tsb.border_width_top = 1
	tsb.border_color = Palette.IRON_EDGE
	tsb.content_margin_left = 9
	tsb.content_margin_right = 9
	tsb.content_margin_top = 9
	tsb.content_margin_bottom = 9
	for state in ["normal", "hover", "pressed", "focus"]:
		_det_toggle.add_theme_stylebox_override(state, tsb)
	_det_toggle.pressed.connect(_on_det_toggle)
	col.add_child(_det_toggle)

	_rebuild_det()
	return wrap


func _on_det_toggle() -> void:
	_show_all = not _show_all
	_rebuild_det()


func _rebuild_det() -> void:
	for child in _det_list.get_children():
		_det_list.remove_child(child)
		child.queue_free()
	var all_rows := _detailed_rows()
	var rows: Array = all_rows if _show_all else all_rows.slice(0, 8)
	for d in rows:
		var row := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_width_bottom = 1
		sb.border_color = Color(0, 0, 0, 0.28)
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		row.add_theme_stylebox_override("panel", sb)
		var h := HBoxContainer.new()
		var k := Style.body_label(String(d[0]), 12, Palette.TX_MUTE)
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(k)
		var neg := String(d[1]).begins_with("−")
		h.add_child(Style.body_label(String(d[1]), 12, Palette.HP if neg else Palette.CYAN_BRIGHT))
		row.add_child(h)
		_det_list.add_child(row)
	_det_toggle.text = "▲ Show less" if _show_all else "▼ Show all (%d)" % all_rows.size()


## GameContent.DETAILED order, but values computed from PlayerStats where
## modeled. "Spell DPS" / "Cast Speed" keep their design statics (unmodeled).
func _detailed_rows() -> Array:
	var p := PlayerStats.compute()
	var derived: Dictionary = p["derived"]
	var out: Array = []
	for d in GameContent.DETAILED:
		var label := String(d[0])
		out.append([label, _detail_value(label, p, derived, String(d[1]))])
	return out


func _detail_value(label: String, p: Dictionary, derived: Dictionary, fallback: String) -> String:
	match label:
		"Attack DPS":
			return String(p["dps_label"])
		"Crit Chance":
			return "%.1f%%" % (float(derived["crit_chance"]) * 100.0)
		"Crit Multiplier":
			return "%d%%" % roundi(float(derived["crit_multiplier"]) * 100.0)
		"Attack Speed":
			return _pct_inc(float(derived["attack_speed"]))
		"Movement Speed":
			return _pct_inc(float(derived["movement_speed"]))
		"Gold Find":
			return _pct_inc(float(derived["gold_find"]))
		"Item Rarity":
			return _pct_inc(float(derived["item_rarity"]))
		"XP Gain":
			return _pct_inc(float(derived["xp_gain"]))
		"Maximum Mana":
			return Style.group_int(int(derived["maximum_mana"]))
		"Life Regen":
			return Style.group_int(int(derived["life_regen"]))
		"Mana Regen":
			return Style.group_int(int(derived["mana_regen"]))
		"Evasion":
			return Style.group_int(int(derived["evasion"]))
		"Fire Resist":
			return _pct_inc(float(derived["fire_resist"]))
		"Cold Resist":
			return _pct_inc(float(derived["cold_resist"]))
		"Lightning Resist":
			return _pct_inc(float(derived["lightning_resist"]))
		"Chaos Resist":
			return _pct_inc(float(derived["chaos_resist"]))
		"Accuracy":
			return "%d%%" % roundi(float(derived["accuracy"]) * 100.0)
		"Block Chance":
			return "%d%%" % roundi(float(derived["block_chance"]) * 100.0)
		_:
			return fallback


## "+18%" / "−12%" (U+2212 minus renders red in the detail rows).
func _pct_inc(v: float) -> String:
	var n := roundi(v * 100.0)
	if n < 0:
		return "−%d%%" % absi(n)
	return "+%d%%" % n


# =========================================================================
# Paperdoll (.paperdoll)
# =========================================================================

func _build_paperdoll() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(568, 0)
	panel.add_theme_stylebox_override("panel", Style.panel_box())
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 14)
	pad.add_theme_constant_override("margin_right", 14)
	pad.add_theme_constant_override("margin_top", 16)
	pad.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(pad)

	_pd_area = Control.new()
	_pd_area.mouse_filter = Control.MOUSE_FILTER_PASS
	pad.add_child(_pd_area)

	# Figure column: silhouette + rune rings + gear power plate.
	_pd_figure = Control.new()
	_pd_figure.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pd_area.add_child(_pd_figure)
	var sil := PixelSlot.new("280×520\nhero silhouette\n(equipped look)", true)
	_pd_figure.add_child(sil)
	sil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sil_border := Panel.new()
	var sb_b := StyleBoxFlat.new()
	sb_b.draw_center = false
	sb_b.set_border_width_all(1)
	sb_b.border_color = Palette.GOLD_DIM
	sb_b.set_corner_radius_all(6)
	sb_b.shadow_color = Palette.with_alpha(Palette.EMBER, 0.12 * Palette.GLOW)
	sb_b.shadow_size = int(10 * Palette.GLOW)
	sil_border.add_theme_stylebox_override("panel", sb_b)
	sil_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pd_figure.add_child(sil_border)
	sil_border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var rings := RuneRings.new()
	_pd_figure.add_child(rings)
	rings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# .pd-power — Gear Power plate, bottom-center overlay.
	_pd_plate = PanelContainer.new()
	var plate_sb := StyleBoxFlat.new()
	plate_sb.bg_color = Color(0.07, 0.057, 0.039, 0.93)
	plate_sb.set_border_width_all(1)
	plate_sb.border_color = Palette.GOLD_DIM
	plate_sb.set_corner_radius_all(5)
	plate_sb.content_margin_left = 22
	plate_sb.content_margin_right = 22
	plate_sb.content_margin_top = 8
	plate_sb.content_margin_bottom = 8
	_pd_plate.add_theme_stylebox_override("panel", plate_sb)
	_pd_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plate_col := VBoxContainer.new()
	plate_col.add_theme_constant_override("separation", 3)
	_plate_num = Style.pixel_label("", 18, Palette.EMBER_BRIGHT)
	_plate_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plate_col.add_child(_plate_num)
	var pp_lbl := Style.body_label("GEAR POWER", 9, Palette.TX_MUTE)
	pp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plate_col.add_child(pp_lbl)
	_pd_plate.add_child(plate_col)
	_pd_figure.add_child(_pd_plate)
	_pd_plate.resized.connect(_position_plate)

	# Slot columns: 5 left + 5 right, overlapping the figure by 26px.
	for i in 5:
		var l := _gear_slot(GameContent.GEAR_L[i])
		_pd_area.add_child(l)
		_pd_left.append(l)
		var r := _gear_slot(GameContent.GEAR_R[i])
		_pd_area.add_child(r)
		_pd_right.append(r)

	_pd_area.resized.connect(_layout_paperdoll)
	return panel


func _layout_paperdoll() -> void:
	var s := _pd_area.size
	if s.x <= 0.0 or s.y <= 0.0:
		return
	var fig_w := minf(330.0, maxf(120.0, s.x - 136.0))
	var total_w := fig_w + 136.0
	var x0 := (s.x - total_w) * 0.5
	_pd_figure.position = Vector2(x0 + 68.0, 0.0)
	_pd_figure.size = Vector2(fig_w, s.y)
	for i in 5:
		var slot_y := (s.y - 84.0) * float(i) / 4.0
		_pd_left[i].position = Vector2(x0, slot_y)
		_pd_right[i].position = Vector2(x0 + fig_w + 52.0, slot_y)
	_position_plate()


func _position_plate() -> void:
	_pd_plate.position = Vector2(
		(_pd_figure.size.x - _pd_plate.size.x) * 0.5,
		_pd_figure.size.y - _pd_plate.size.y - 14.0)


func _gear_slot(g: Dictionary) -> Control:
	var cell := Control.new()
	cell.custom_minimum_size = Vector2(84, 84)
	cell.size = Vector2(84, 84)
	cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var rar := String(g["r"])
	var box := Panel.new()
	box.add_theme_stylebox_override("panel", Style.slot_box(rar, true))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ps := PixelSlot.new(String(g["slot"]), true)
	cell.add_child(ps)
	ps.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ps.offset_left = 4
	ps.offset_top = 4
	ps.offset_right = -4
	ps.offset_bottom = -4
	var il := Style.pixel_label(str(int(g["ilvl"])), 8, Palette.GOLD_BRIGHT)
	il.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	il.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(il)
	il.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	il.offset_left = 4
	il.offset_top = 64
	il.offset_right = -5
	il.offset_bottom = -3
	il.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	if String(g["name"]) == "Cindergrip Maul":
		# Live tooltip: forge-scaled weapon stats + the current forge level.
		Tip.attach(cell, func() -> Dictionary:
			var stats: Array = PlayerStats.forged_weapon_stats()
			stats.append(["Forge", "+%d" % GameState.forge_level])
			return {
				"name": g["name"],
				"type": "%s · iLvl %d · %s" % [g["slot"], int(g["ilvl"]), rar],
				"rarity": rar,
				"stats": stats,
				"flavor": "Right-click to unequip.",
			})
	else:
		Tip.attach(cell, {
			"name": g["name"],
			"type": "%s · iLvl %d · %s" % [g["slot"], int(g["ilvl"]), rar],
			"rarity": rar,
			"stats": g["stats"],
			"flavor": "Right-click to unequip.",
		})
	return cell


# =========================================================================
# Inventory (.inventory)
# =========================================================================

func _build_inventory() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", Style.panel_box())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	panel.add_child(col)

	# .inv-tabs — folder tabs.
	var bar := PanelContainer.new()
	var bar_sb := StyleBoxFlat.new()
	bar_sb.bg_color = Color(0.235, 0.196, 0.125, 0.15)
	bar_sb.border_width_bottom = 1
	bar_sb.border_color = Palette.IRON_EDGE
	bar_sb.content_margin_left = 10
	bar_sb.content_margin_right = 10
	bar_sb.content_margin_top = 8
	bar_sb.content_margin_bottom = 0
	bar.add_theme_stylebox_override("panel", bar_sb)
	var bar_h := HBoxContainer.new()
	bar_h.add_theme_constant_override("separation", 2)
	for pair in GameContent.INV_TABS:
		var b := Button.new()
		b.text = String(pair[1]).to_upper()
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var f := Fonts.display()
		if f != null:
			b.add_theme_font_override("font", f)
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(_set_inv_tab.bind(String(pair[0])))
		_inv_tab_buttons[String(pair[0])] = b
		bar_h.add_child(b)
	bar.add_child(bar_h)
	col.add_child(bar)

	# .inv-grid — 6-col scrollable grid of 30 cells.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var gm := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		gm.add_theme_constant_override(m, 14)
	gm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inv_grid = GridContainer.new()
	_inv_grid.columns = 6
	_inv_grid.add_theme_constant_override("h_separation", 9)
	_inv_grid.add_theme_constant_override("v_separation", 9)
	_inv_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inv_grid.resized.connect(func() -> void: _resize_square_cells(_inv_grid, 6, 9.0))
	gm.add_child(_inv_grid)
	scroll.add_child(gm)
	col.add_child(scroll)

	col.add_child(_build_inv_foot())
	_rebuild_inv()
	return panel


func _inv_tab_box(active: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 9
	sb.content_margin_bottom = 8
	if active:
		sb.bg_color = Color8(120, 72, 28, 115)
		sb.border_color = Palette.EMBER_DEEP
	else:
		sb.bg_color = Color8(50, 44, 34, 89)
		sb.border_color = Palette.IRON_EDGE
	return sb


func _apply_inv_tab_styles() -> void:
	for id in _inv_tab_buttons:
		var b: Button = _inv_tab_buttons[id]
		var active: bool = String(id) == _inv_tab
		b.add_theme_stylebox_override("normal", _inv_tab_box(active))
		b.add_theme_stylebox_override("hover", _inv_tab_box(active))
		b.add_theme_stylebox_override("pressed", _inv_tab_box(active))
		b.add_theme_color_override("font_color", Palette.EMBER_BRIGHT if active else Palette.TX_MUTE)
		b.add_theme_color_override("font_hover_color", Palette.EMBER_BRIGHT if active else Palette.TX_DIM)
		b.add_theme_color_override("font_pressed_color", Palette.EMBER_BRIGHT if active else Palette.TX_MUTE)


func _set_inv_tab(id: String) -> void:
	if id == _inv_tab:
		return
	_inv_tab = id
	_rebuild_inv()


func _rebuild_inv() -> void:
	_apply_inv_tab_styles()
	for child in _inv_grid.get_children():
		_inv_grid.remove_child(child)
		child.queue_free()
	var bag: Array = GameContent.BAG[_inv_tab]
	for i in GameContent.INV_CELLS:
		if i < bag.size():
			_inv_grid.add_child(_inv_cell(bag[i]))
		else:
			_inv_grid.add_child(_empty_cell())
	if _cap_num != null:
		_cap_num.text = "%d / %d" % [bag.size(), GameContent.INV_CELLS]
	_resize_square_cells(_inv_grid, 6, 9.0)


func _inv_cell(it: Dictionary) -> Control:
	var cell := Control.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var rar := String(it["r"])
	var box := Panel.new()
	box.add_theme_stylebox_override("panel", Style.inv_cell_box(rar, true))
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
	if it.has("q"):
		var qty := Style.pixel_label(str(int(it["q"])), 9, Color.WHITE)
		qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		qty.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		qty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(qty)
		qty.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		qty.offset_left = 3
		qty.offset_top = 3
		qty.offset_right = -4
		qty.offset_bottom = -2
	cell.mouse_entered.connect(func() -> void: box.add_theme_stylebox_override("panel", Style.inv_cell_box(rar, true, true)))
	cell.mouse_exited.connect(func() -> void: box.add_theme_stylebox_override("panel", Style.inv_cell_box(rar, true)))
	var stats: Array = []
	if it.has("s"):
		stats = it["s"]
	elif it.has("q"):
		stats = [["Stack", "×%d" % int(it["q"])]]
	var flavor := "Used in crafting & cooking."
	if _inv_tab == "equipment":
		flavor = "Right-click to equip."
	elif _inv_tab == "quest":
		flavor = "Cannot be discarded."
	Tip.attach(cell, {
		"name": it["n"],
		"type": "%s · %s" % [it["t"], rar],
		"rarity": rar,
		"stats": stats,
		"flavor": flavor,
	})
	return cell


func _empty_cell() -> Control:
	var cell := Control.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := Panel.new()
	box.add_theme_stylebox_override("panel", Style.inv_cell_box())
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return cell


# .inv-foot — currency readouts + capacity.
func _build_inv_foot() -> Control:
	var foot := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.235, 0.196, 0.125, 0.12)
	sb.border_width_top = 1
	sb.border_color = Palette.IRON_EDGE
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	foot.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	_gold_val = Style.pixel_label("", 12, Palette.TX)
	h.add_child(_currency_readout(_svg_icon("res://assets/icons/coin_gold.svg"), _gold_val,
		{"name": "Gold", "type": "Soft currency", "rarity": "legendary"}))
	_soul_val = Style.pixel_label("", 12, Palette.TX)
	h.add_child(_currency_readout(_svg_icon("res://assets/icons/soulstone.svg"), _soul_val,
		{"name": "Soulstone", "type": "Premium currency", "rarity": "epic"}))
	_dust_val = Style.pixel_label("", 12, Palette.TX)
	h.add_child(_currency_readout(_ember_diamond(10.0), _dust_val,
		{"name": "Ember Dust", "type": "Crafting material", "rarity": "rare"}))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(spacer)
	var cap := HBoxContainer.new()
	cap.add_theme_constant_override("separation", 6)
	_cap_num = Style.pixel_label("", 11, Palette.TX_DIM)
	_cap_num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cap.add_child(_cap_num)
	var cap_lbl := Style.body_label("SLOTS", 9, Palette.TX_FAINT)
	cap_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cap.add_child(cap_lbl)
	h.add_child(cap)
	foot.add_child(h)
	return foot


func _currency_readout(icon: Control, value_label: Label, tip: Dictionary) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(icon)
	value_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(value_label)
	Tip.attach(box, tip)
	return box


func _svg_icon(path: String) -> Control:
	var tr := TextureRect.new()
	tr.texture = load(path) as Texture2D
	tr.custom_minimum_size = Vector2(18, 18)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


func _ember_diamond(px: float) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(px + 4, px + 4)
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


func _refresh_currencies() -> void:
	_gold_val.text = Style.group_int(GameState.gold)
	_soul_val.text = Style.group_int(GameState.premium_currency)
	_dust_val.text = str(GameState.ember_dust)


func _resize_square_cells(grid: GridContainer, cols: int, gap: float) -> void:
	var cw := floorf((grid.size.x - gap * float(cols - 1)) / float(cols))
	if cw < 10.0:
		return
	for c in grid.get_children():
		var ctl := c as Control
		if ctl != null and absf(ctl.custom_minimum_size.y - cw) > 0.5:
			ctl.custom_minimum_size = Vector2(0, cw)


# =========================================================================
# Inner helpers
# =========================================================================

## .cs-attr-dots — expanding dotted leader between stat name and value.
class DotLeader:
	extends Control

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		custom_minimum_size = Vector2(8, 1)
		resized.connect(queue_redraw)

	func _draw() -> void:
		var y := size.y * 0.5
		draw_dashed_line(Vector2(4, y), Vector2(size.x - 4.0, y), Color(0.49, 0.439, 0.345, 0.35), 1.0, 2.0)


## .pd-runes — rotating dashed rune rings behind the silhouette.
class RuneRings:
	extends Control

	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)

	func _process(delta: float) -> void:
		_t += delta
		if is_visible_in_tree():
			queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		# r1: 300px dashed, CW over 80s.
		_dashed_circle(c, 150.0, Color(0.827, 0.678, 0.384, 0.28), TAU * _t / 80.0)
		# r2: 246px solid faint (CCW 60s in CSS — invisible on a solid ring).
		draw_arc(c, 123.0, 0.0, TAU, 64, Color(0.827, 0.678, 0.384, 0.14), 1.0, true)
		# r3: 348px static ember-faint.
		draw_arc(c, 174.0, 0.0, TAU, 80, Color(0.91, 0.518, 0.227, 0.12), 1.0, true)

	func _dashed_circle(c: Vector2, r: float, col: Color, rot: float) -> void:
		var n := 48
		for i in n:
			var a0 := rot + TAU * float(i) / float(n)
			draw_arc(c, r, a0, a0 + TAU / float(n) * 0.55, 4, col, 1.0, true)
