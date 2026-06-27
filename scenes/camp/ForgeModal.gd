extends "res://scenes/camp/ModalShell.gd"
## CRAFTING HOUSE modal. Drag a gear piece from the ALL ITEMS panel onto the left
## source slot to enhance THAT piece: the slot shows its current stats in white,
## and a successful upgrade scales them (and its item level), showing each gain as
## a green (+delta). Cost is gold + iron + ember dust, scaled by the piece's forge
## level; success is a roll (Balance.forge.success_rate). Enter triggers it.

var _rng := RandomNumberGenerator.new()

var _selected: Dictionary = {}   # the gear piece in the source slot (a live ref)
var _prev_stats: Array = []      # its stats before an upgrade, for the green deltas
var _show_delta := false

var _src_holder: Control
var _dst_holder: Control
var _stats_col: VBoxContainer
var _gold_lbl: Label
var _iron_qty: Label
var _iron_have: Label
var _dust_qty: Label
var _dust_have: Label
var _result_lbl: Label
var _upgrade_btn: Button


func _init() -> void:
	modal_title = "Crafting House"
	modal_width = 1340.0
	body_separation = 18
	_rng.randomize()


func _build_body(body: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 16)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.5
	row.add_child(left)
	left.add_child(_build_anvil())
	left.add_child(_build_stats())
	left.add_child(_build_cost())
	_result_lbl = Style.display_label("", 13, Palette.GOLD_BRIGHT, true)
	_result_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_lbl.visible = false
	left.add_child(_result_lbl)

	row.add_child(_build_all_items())

	# Start empty — the anvil slot is a drop target; the player puts a piece in.
	EventBus.currencies_changed.connect(_refresh_all)
	EventBus.equipment_changed.connect(_refresh_all)
	_refresh_anvil()
	_refresh_all()


func _exit_tree() -> void:
	if EventBus.currencies_changed.is_connected(_refresh_all):
		EventBus.currencies_changed.disconnect(_refresh_all)
	if EventBus.equipment_changed.is_connected(_refresh_all):
		EventBus.equipment_changed.disconnect(_refresh_all)


func _on_modal_key(keycode: Key) -> bool:
	if keycode == KEY_ENTER or keycode == KEY_KP_ENTER:
		if not _upgrade_btn.disabled:
			_do_upgrade()
		return true
	return false


# =========================================================================
# Anvil row — source slot (drop target) → result preview
# =========================================================================

func _build_anvil() -> Control:
	var anvil := Control.new()
	anvil.custom_minimum_size = Vector2(0, 170)
	anvil.mouse_filter = Control.MOUSE_FILTER_PASS

	var wash := _FX.Glow.new(
		[[0.0, Palette.with_alpha(Palette.EMBER, 0.08)], [1.0, Palette.with_alpha(Palette.EMBER, 0.0)]])
	wash.center_frac = Vector2(0.5, 0.4)
	wash.radius_frac = Vector2(0.6, 1.0)
	anvil.add_child(wash)
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	anvil.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	center.add_child(row)

	_src_holder = _SourceSlot.new()
	(_src_holder as _SourceSlot).modal = self
	_src_holder.custom_minimum_size = Vector2(130, 130)
	_src_holder.mouse_default_cursor_shape = Control.CURSOR_HELP
	row.add_child(_src_holder)
	Tip.attach(_src_holder, _src_tip)

	var arrow := Style.body_label("→", 30, Palette.EMBER)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	arrow.add_theme_color_override("font_shadow_color", Palette.with_alpha(Palette.EMBER, 0.5))
	arrow.add_theme_constant_override("shadow_outline_size", int(10 * Palette.GLOW))
	row.add_child(arrow)

	_dst_holder = Control.new()
	_dst_holder.custom_minimum_size = Vector2(130, 130)
	_dst_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_dst_holder)
	return anvil


func _src_tip() -> Dictionary:
	if _selected.is_empty():
		return {"name": "Empty slot", "type": "Forge", "rarity": "",
			"flavor": "Drag a gear piece from the right to enhance it."}
	return {
		"name": String(_selected.get("n", "")),
		"type": "%s · +%d" % [GameContent.item_type_line(_selected), int(_selected.get("lvl", 0))],
		"rarity": String(_selected.get("r", "")),
		"stats": _selected.get("s", []),
		"flavor": "Drop a different piece to swap it in.",
	}


## (Re)build the source + result slot visuals from the selected piece.
func _refresh_anvil() -> void:
	_fill_slot(_src_holder, false)
	_fill_slot(_dst_holder, true)


func _fill_slot(holder: Control, is_preview: bool) -> void:
	for c in holder.get_children():
		c.queue_free()
	if _selected.is_empty():
		var frame := Panel.new()
		frame.add_theme_stylebox_override("panel", Style.slot_box())
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(frame)
		frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		if not is_preview:
			var hint := Style.pixel_label("DRAG\nITEM\nHERE", 9, Palette.TX_FAINT)
			hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.add_child(hint)
			hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		return
	var rar := String(_selected.get("r", "common"))
	var frame := Panel.new()
	frame.add_theme_stylebox_override("panel", Style.slot_box("legendary" if is_preview else rar, true))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ic := GearIcon.new(GearIcon.kind_for_slot(String(_selected.get("slot", ""))),
		Palette.GOLD_BRIGHT if is_preview else Palette.rarity_color(rar))
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(ic)
	ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ic.offset_left = 8
	ic.offset_top = 8
	ic.offset_right = -8
	ic.offset_bottom = -8
	var lvl := int(_selected.get("lvl", 0)) + (1 if is_preview else 0)
	var tag := Style.pixel_label("+%d" % lvl, 11, Palette.GOLD_BRIGHT)
	tag.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	tag.add_theme_constant_override("shadow_offset_y", 1)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tag.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(tag)
	tag.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	tag.offset_left = -44
	tag.offset_top = -22
	tag.offset_right = -6
	tag.offset_bottom = -4


# =========================================================================
# Stats inset — current value (white) + green (+delta) after a success
# =========================================================================

func _build_stats() -> Control:
	var panel := PanelContainer.new()
	var sb := Style.inset_box(4)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", sb)
	_stats_col = VBoxContainer.new()
	_stats_col.add_theme_constant_override("separation", 10)
	panel.add_child(_stats_col)
	return panel


func _refresh_stats() -> void:
	for child in _stats_col.get_children():
		_stats_col.remove_child(child)
		child.queue_free()
	if _selected.is_empty():
		_stats_col.add_child(_fs_row("Drag an item from the right to forge it.", []))
		return
	var cur: Array = _selected.get("s", [])
	for i in cur.size():
		var pair: Array = cur[i]
		var parts: Array = [[String(pair[1]), Palette.TX]]
		if _show_delta and i < _prev_stats.size():
			var d := _delta_text(String((_prev_stats[i] as Array)[1]), String(pair[1]))
			if d != "":
				parts.append(["   %s" % d, Palette.R_UNCOMMON])
		_stats_col.add_child(_fs_row(String(pair[0]), parts))
	_stats_col.add_child(_fs_row("Success rate",
		[["%d%%" % roundi(Balance.num("forge.success_rate", 0.82) * 100.0), Palette.CYAN_BRIGHT]]))


func _fs_row(label: String, parts: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	var lbl := Style.body_label(label, 14, Palette.TX_DIM)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	for part: Array in parts:
		row.add_child(Style.body_label(String(part[0]), 14, part[1]))
	return row


## Scales "470–664" / "+72" / "+8.5%" value text by [param mult].
func _scale_text(text: String, mult: float) -> String:
	var range_re := RegEx.new()
	range_re.compile(r"^([+\-]?)(\d+(?:\.\d+)?)\s*[–-]\s*(\d+(?:\.\d+)?)$")
	var rm := range_re.search(text)
	if rm != null:
		return "%s%d–%d" % [rm.get_string(1), int(float(rm.get_string(2)) * mult), int(float(rm.get_string(3)) * mult)]
	var re := RegEx.new()
	re.compile(r"^([+\-]?)(\d+(?:\.\d+)?)(%?)$")
	var m := re.search(text)
	if m == null:
		return text
	var v := float(m.get_string(2)) * mult
	if m.get_string(3) == "%":
		return "%s%.1f%%" % [m.get_string(1), v]
	return "%s%d" % [m.get_string(1), int(v)]


## "(+N)" / "(+N–M)" / "(+N%)" gain from prev→new value text (empty if no gain).
func _delta_text(old_text: String, new_text: String) -> String:
	var range_re := RegEx.new()
	range_re.compile(r"(\d+)\s*[–-]\s*(\d+)")
	var ro := range_re.search(old_text)
	var rn := range_re.search(new_text)
	if ro != null and rn != null:
		var dlo := int(rn.get_string(1)) - int(ro.get_string(1))
		var dhi := int(rn.get_string(2)) - int(ro.get_string(2))
		if dlo > 0 or dhi > 0:
			return "(+%d–%d)" % [maxi(0, dlo), maxi(0, dhi)]
		return ""
	var num_re := RegEx.new()
	num_re.compile(r"(\d+(?:\.\d+)?)(%?)")
	var no := num_re.search(old_text)
	var nn := num_re.search(new_text)
	if no != null and nn != null:
		var d := float(nn.get_string(1)) - float(no.get_string(1))
		if d <= 0.0:
			return ""
		if nn.get_string(2) == "%":
			return "(+%.1f%%)" % d
		return "(+%d)" % int(round(d))
	return ""


# =========================================================================
# Cost row
# =========================================================================

func _build_cost() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	var iron := _material_item({"name": "Iron Ingot", "type": "Material", "rarity": "common"})
	_iron_qty = Style.pixel_label("", 12, Palette.TX_DIM)
	_iron_qty.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	iron.add_child(_iron_qty)
	_iron_have = Style.body_label("", 10, Palette.TX_MUTE)
	_iron_have.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	iron.add_child(_iron_have)
	row.add_child(iron)

	var dust := _material_item({"name": "Ember Dust", "type": "Material · Rare", "rarity": "rare"})
	_dust_qty = Style.pixel_label("", 12, Palette.TX_DIM)
	_dust_qty.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dust.add_child(_dust_qty)
	_dust_have = Style.body_label("", 10, Palette.TX_MUTE)
	_dust_have.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dust.add_child(_dust_have)
	row.add_child(dust)

	var gold := VBoxContainer.new()
	gold.add_theme_constant_override("separation", 0)
	gold.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_gold_lbl = Style.pixel_label("", 12, Palette.GOLD_BRIGHT)
	gold.add_child(_gold_lbl)
	gold.add_child(Style.body_label("GOLD", 9, Palette.TX_FAINT))
	row.add_child(gold)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	_upgrade_btn = Style.make_button("Upgrade   ↵", "ember")
	_upgrade_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_upgrade_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_upgrade_btn.pressed.connect(_do_upgrade)
	row.add_child(_upgrade_btn)
	return row


func _material_item(tip: Dictionary) -> HBoxContainer:
	var item := HBoxContainer.new()
	item.add_theme_constant_override("separation", 8)
	item.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var kind := "ingot" if String(tip.get("name", "")).contains("Iron") else "gem"
	var ps := GearIcon.new(kind, Palette.rarity_color(String(tip.get("rarity", "common"))))
	ps.custom_minimum_size = Vector2(40, 40)
	item.add_child(ps)
	Tip.attach(item, tip)
	item.mouse_default_cursor_shape = Control.CURSOR_HELP
	return item


# =========================================================================
# All Items panel — draggable owned gear
# =========================================================================

func _build_all_items() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Style.panel_box())
	panel.custom_minimum_size = Vector2(380, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pad := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(m, 14)
	panel.add_child(pad)
	var vc := VBoxContainer.new()
	vc.add_theme_constant_override("separation", 10)
	pad.add_child(vc)
	vc.add_child(Style.display_label("ALL ITEMS", 13, Palette.GOLD))
	var sub := Style.body_label("Drag a piece onto the anvil to forge it", 12, Palette.TX_MUTE)
	vc.add_child(sub)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	vc.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(grid)
	for it_v in GameState.equipped:
		if it_v != null:
			grid.add_child(_item_cell(it_v))
	for it in GameState.bag_equipment:
		grid.add_child(_item_cell(it))
	return panel


## A draggable, rarity-framed catalog cell (drag onto the anvil to forge it).
func _item_cell(item: Dictionary) -> Control:
	var rar := String(item.get("r", "common"))
	var cell := _ItemCell.new()
	cell.modal = self
	cell.item = item
	cell.custom_minimum_size = Vector2(76, 76)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var box := Panel.new()
	box.add_theme_stylebox_override("panel", Style.inv_cell_box(rar, true))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ic := GearIcon.new(GearIcon.kind_for_slot(String(item.get("slot", ""))), Palette.rarity_color(rar))
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(ic)
	ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ic.offset_left = 8
	ic.offset_top = 8
	ic.offset_right = -8
	ic.offset_bottom = -8
	Tip.attach(cell, func() -> Dictionary:
		return {
			"name": String(item.get("n", "")),
			"type": "%s · +%d" % [GameContent.item_type_line(item), int(item.get("lvl", 0))],
			"rarity": rar,
			"stats": item.get("s", []),
			"flavor": "Drag onto the anvil to forge it.",
		})
	return cell


# =========================================================================
# Logic
# =========================================================================

func _select_item(item: Dictionary) -> void:
	_selected = item
	_show_delta = false
	_prev_stats = []
	_refresh_anvil()
	_refresh_all()


## Right-click on the anvil slot clears it (takes the piece out).
func _clear_selection() -> void:
	_selected = {}
	_show_delta = false
	_prev_stats = []
	_refresh_anvil()
	_refresh_all()


func _do_upgrade() -> void:
	if _selected.is_empty():
		return
	var lvl := int(_selected.get("lvl", 0))
	var gold_cost := Balance.forge_gold_cost(lvl)
	var iron_cost := Balance.inum("forge.iron_cost", 12)
	var dust_cost := Balance.inum("forge.dust_cost", 3)
	if GameState.gold < gold_cost or GameState.iron_ingots < iron_cost or GameState.ember_dust < dust_cost:
		return
	GameState.gold -= gold_cost
	GameState.iron_ingots -= iron_cost
	GameState.ember_dust -= dust_cost
	_prev_stats = (_selected.get("s", []) as Array).duplicate(true)
	if _rng.randf() < Balance.num("forge.success_rate", 0.82):
		var growth := Balance.num("forge.stat_growth", 1.13)
		var new_s: Array = []
		for pair in (_selected["s"] as Array):
			new_s.append([String((pair as Array)[0]), _scale_text(String((pair as Array)[1]), growth)])
		_selected["s"] = new_s
		_selected["lvl"] = lvl + 1
		_selected["ilvl"] = int(_selected.get("ilvl", 1)) + Balance.inum("forge.ilvl_per_level", 3)
		_show_delta = true
		_show_result("+%d achieved!" % (lvl + 1), Palette.GOLD_BRIGHT)
	else:
		_show_delta = false
		_show_result("The forge spits sparks — materials lost.", Palette.EMBER_HOT)
	_refresh_anvil()
	EventBus.currencies_changed.emit()
	EventBus.equipment_changed.emit()  # gear power + the other gear views refresh
	_refresh_all()


func _show_result(text: String, color: Color) -> void:
	_result_lbl.text = text
	_result_lbl.add_theme_color_override("font_color", color)
	_result_lbl.visible = true
	_result_lbl.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_result_lbl, "modulate:a", 1.0, 0.14)


func _refresh_all() -> void:
	_refresh_stats()
	if _selected.is_empty():
		_gold_lbl.text = "—"
		_iron_qty.text = ""
		_dust_qty.text = ""
		_iron_have.text = ""
		_dust_have.text = ""
		_upgrade_btn.disabled = true
		return
	var lvl := int(_selected.get("lvl", 0))
	var gold_cost := Balance.forge_gold_cost(lvl)
	var iron_cost := Balance.inum("forge.iron_cost", 12)
	var dust_cost := Balance.inum("forge.dust_cost", 3)
	_gold_lbl.text = Style.group_int(gold_cost)
	_iron_qty.text = "×%d" % iron_cost
	_dust_qty.text = "×%d" % dust_cost
	_iron_have.text = "(have %d)" % GameState.iron_ingots
	_dust_have.text = "(have %d)" % GameState.ember_dust
	_iron_have.add_theme_color_override("font_color",
		Palette.HP if GameState.iron_ingots < iron_cost else Palette.TX_MUTE)
	_dust_have.add_theme_color_override("font_color",
		Palette.HP if GameState.ember_dust < dust_cost else Palette.TX_MUTE)
	_upgrade_btn.disabled = GameState.gold < gold_cost \
		or GameState.iron_ingots < iron_cost \
		or GameState.ember_dust < dust_cost


# =========================================================================
# Drag pieces in / drag-source cells
# =========================================================================
class _SourceSlot:
	extends Control

	var modal = null

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return typeof(data) == TYPE_DICTIONARY and (data as Dictionary).has("item")

	func _drop_data(_at: Vector2, data: Variant) -> void:
		modal._select_item((data as Dictionary)["item"])

	# Right-click clears the anvil (takes the piece out of the slot).
	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			modal._clear_selection()
			accept_event()


class _ItemCell:
	extends Control

	var modal = null
	var item: Dictionary = {}

	# Right-click puts the piece straight onto the anvil (same as the slot drop).
	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			modal._select_item(item)
			accept_event()

	func _get_drag_data(_at: Vector2) -> Variant:
		Tip.hide_now(self)
		var rar := String(item.get("r", "common"))
		var p := Panel.new()
		p.custom_minimum_size = Vector2(64, 64)
		p.size = Vector2(64, 64)
		p.add_theme_stylebox_override("panel", Style.slot_box(rar, true))
		p.modulate = Color(1, 1, 1, 0.85)
		var ic := GearIcon.new(GearIcon.kind_for_slot(String(item.get("slot", ""))), Palette.rarity_color(rar))
		p.add_child(ic)
		ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ic.offset_left = 8
		ic.offset_top = 8
		ic.offset_right = -8
		ic.offset_bottom = -8
		set_drag_preview(p)
		return {"item": item}
