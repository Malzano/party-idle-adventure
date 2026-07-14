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

# --- Tabs -----------------------------------------------------------------
const _TABS := [["upgrade", "Upgrade"], ["craft", "Blacksmith"], ["socket", "Socket"], ["salvage", "Salvage"], ["fusion", "Fusion"]]
var _tab := "upgrade"
var _tab_btns: Dictionary = {}
var _pages: Dictionary = {}
var _mat_readout: HBoxContainer
var _rebuilders: Array = []  # per-page callables to refresh their item/gem grids

# Salvage page
var _salvage_picks: Array = []          # multi-select for batch salvage
var _salvage_grid: GridContainer
var _salvage_detail: VBoxContainer
var _salvage_summary: Dictionary = {}   # last batch result {gold, mats, count}
# Fusion page
var _fusion_mode := "gear"          # "gear" | "gem"
var _fusion_picks: Array = []       # up to 5 chosen items/gems
var _fusion_grid: GridContainer
var _fusion_slot_row: HBoxContainer
var _fusion_status: Label
var _fusion_btn: Button
var _fusion_result: VBoxContainer
# Craft page
var _craft_slot := "Main Hand"
var _craft_rarity := "rare"
var _craft_cost: VBoxContainer
var _craft_status: Label
var _craft_slot_btns: Dictionary = {}
var _craft_rar_btns: Dictionary = {}
var _craft_result: Control
var _craft_forge_btn: Button
# Socket page
var _socket_sel: Dictionary = {}
var _socket_grid: GridContainer
var _socket_detail: VBoxContainer


func _init() -> void:
	modal_title = "Crafting House"
	modal_width = 1340.0
	body_separation = 14
	_rng.randomize()


func _build_body(body: VBoxContainer) -> void:
	body.add_child(_build_tabbar())
	_mat_readout = _build_mat_readout()
	body.add_child(_mat_readout)
	_pages["upgrade"] = _build_upgrade_page()
	_pages["craft"] = _build_craft_page()
	_pages["socket"] = _build_socket_page()
	_pages["salvage"] = _build_salvage_page()
	_pages["fusion"] = _build_fusion_page()
	for pair: Array in _TABS:
		var pg: Control = _pages[String(pair[0])]
		pg.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body.add_child(pg)
	_set_tab("upgrade")

	EventBus.currencies_changed.connect(_refresh_all)
	EventBus.equipment_changed.connect(_on_inv_changed)
	EventBus.materials_changed.connect(_on_inv_changed)
	_refresh_anvil()
	_refresh_all()


func _exit_tree() -> void:
	if EventBus.currencies_changed.is_connected(_refresh_all):
		EventBus.currencies_changed.disconnect(_refresh_all)
	if EventBus.equipment_changed.is_connected(_on_inv_changed):
		EventBus.equipment_changed.disconnect(_on_inv_changed)
	if EventBus.materials_changed.is_connected(_on_inv_changed):
		EventBus.materials_changed.disconnect(_on_inv_changed)


## The upgrade anvil, extracted into its own tab page.
func _build_upgrade_page() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
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
	return row


# =========================================================================
# Tab bar + material readout (shared across tabs)
# =========================================================================

func _build_tabbar() -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for pair: Array in _TABS:
		var id := String(pair[0])
		var b := Button.new()
		b.text = String(pair[1]).to_upper()
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var f := Fonts.display()
		if f != null:
			b.add_theme_font_override("font", f)
		b.add_theme_font_size_override("font_size", Style.fs(13))
		b.pressed.connect(_set_tab.bind(id))
		_tab_btns[id] = b
		row.add_child(b)
	wrap.add_child(row)
	var hairline := ColorRect.new()
	hairline.color = Palette.IRON_EDGE
	hairline.custom_minimum_size = Vector2(0, 1)
	hairline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(hairline)
	return wrap


func _tab_box(on: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(120.0 / 255.0, 72.0 / 255.0, 28.0 / 255.0, 0.18) if on else Color(0, 0, 0, 0)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	if on:
		sb.corner_radius_top_left = 4
		sb.corner_radius_top_right = 4
		sb.border_width_bottom = 2
		sb.border_color = Palette.EMBER
	return sb


func _set_tab(id: String) -> void:
	_tab = id
	for key in _tab_btns:
		var b: Button = _tab_btns[key]
		var on := String(key) == _tab
		b.add_theme_stylebox_override("normal", _tab_box(on))
		b.add_theme_stylebox_override("hover", _tab_box(on))
		b.add_theme_stylebox_override("pressed", _tab_box(on))
		b.add_theme_color_override("font_color", Palette.EMBER_BRIGHT if on else Palette.TX_MUTE)
		b.add_theme_color_override("font_hover_color", Palette.EMBER_BRIGHT if on else Palette.TX_DIM)
		b.add_theme_color_override("font_pressed_color", Palette.EMBER_BRIGHT if on else Palette.TX_MUTE)
	for key in _pages:
		(_pages[key] as Control).visible = String(key) == _tab


## A live strip of owned crafting materials (updates on materials_changed).
func _build_mat_readout() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_fill_mat_readout(row)
	return row


func _fill_mat_readout(row: HBoxContainer) -> void:
	for c in row.get_children():
		c.queue_free()
	for id in Craft.MATERIAL_ORDER:
		var m: Dictionary = Craft.MATERIALS[id]
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 5)
		cell.mouse_default_cursor_shape = Control.CURSOR_HELP
		var ic := GearIcon.new(String(m["kind"]), Palette.rarity_color(String(m["tier"])))
		ic.custom_minimum_size = Vector2(26, 26)
		cell.add_child(ic)
		var qty := Style.pixel_label(str(GameState.mat_count(id)), 11, Palette.TX)
		qty.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cell.add_child(qty)
		Tip.attach(cell, {"name": String(m["n"]), "type": "Material · %s" % String(m["tier"]),
			"rarity": String(m["tier"]), "flavor": String(m["for"])})
		row.add_child(cell)


func _on_inv_changed() -> void:
	# The anvil piece may have been salvaged/fused/crafted-over in another tab —
	# drop it if it no longer exists in the paperdoll or bag.
	if not _selected.is_empty():
		var alive := false
		for e in GameState.equipped:
			if e != null and is_same(e, _selected):
				alive = true
				break
		if not alive:
			for b in GameState.bag_equipment:
				if is_same(b, _selected):
					alive = true
					break
		if not alive:
			_selected = {}
			_show_delta = false
			_prev_stats = []
			_refresh_anvil()
	if _mat_readout != null:
		_fill_mat_readout(_mat_readout)
	for r in _rebuilders:
		if (r as Callable).is_valid():
			(r as Callable).call()
	_refresh_all()


# =========================================================================
# Shared FX — a bright ember pulse on a slot when a craft resolves.
# =========================================================================

func _glow_flash(node: Control, tint: Color) -> void:
	if node == null or not is_instance_valid(node):
		return
	var glow := _FX.Glow.new([[0.0, Palette.with_alpha(tint, 0.85)], [0.7, Palette.with_alpha(tint, 0.0)]])
	glow.center_frac = Vector2(0.5, 0.5)
	glow.radius_frac = Vector2(1.1, 1.1)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(glow)
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.modulate.a = 0.0
	var tw := glow.create_tween()
	tw.tween_property(glow, "modulate:a", 1.0, 0.12)
	tw.tween_property(glow, "modulate:a", 0.0, 0.5)
	tw.tween_callback(glow.queue_free)


func _on_modal_key(keycode: Key) -> bool:
	if (keycode == KEY_ENTER or keycode == KEY_KP_ENTER) and _tab == "upgrade":
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
# Shared page helpers
# =========================================================================

func _pad(m: int) -> MarginContainer:
	var pad := MarginContainer.new()
	for s in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(s, m)
	return pad


func _titled_panel(title: String, sub: String) -> Dictionary:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Style.panel_box())
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pad := _pad(14)
	panel.add_child(pad)
	var vc := VBoxContainer.new()
	vc.add_theme_constant_override("separation", 8)
	pad.add_child(vc)
	vc.add_child(Style.display_label(title, 13, Palette.GOLD))
	if sub != "":
		vc.add_child(Style.body_label(sub, 12, Palette.TX_MUTE))
	var body := VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vc.add_child(body)
	return {"panel": panel, "body": body}


func _grid_in(parent: Control, cols: int) -> GridContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# A real minimum height so the item grid doesn't collapse to nothing on tabs
	# that have no tall sibling (Salvage/Fusion/Socket) — items were invisible.
	scroll.custom_minimum_size = Vector2(0, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	return grid


## Bag gear only (has a slot; excludes gems, which live in GameState.gems).
func _bag_gear() -> Array:
	var out: Array = []
	for it in GameState.bag_equipment:
		if it != null and String((it as Dictionary).get("slot", "")) != "":
			out.append(it)
	return out


func _rarity_mark(cell: Control) -> void:
	var m := Panel.new()
	var msb := StyleBoxFlat.new()
	msb.draw_center = false
	msb.set_border_width_all(2)
	msb.border_color = Palette.EMBER
	msb.set_corner_radius_all(4)
	m.add_theme_stylebox_override("panel", msb)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(m)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _gear_cell(item: Dictionary, cb: Callable, mark: bool) -> Control:
	var rar := String(item.get("r", "common"))
	var cell := _ClickCell.new()
	cell.on_click = cb
	cell.custom_minimum_size = Vector2(72, 72)
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
	var sc := (item.get("sockets", []) as Array).size()
	if sc > 0:
		var dots := Style.pixel_label("◈".repeat(sc), 8, Palette.CYAN_BRIGHT)
		dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(dots)
		dots.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		dots.offset_left = 5
		dots.offset_top = -16
		dots.offset_bottom = -3
		dots.offset_right = 46
	if mark:
		_rarity_mark(cell)
	Tip.attach(cell, {"name": String(item.get("n", "")), "type": GameContent.item_type_line(item),
		"rarity": rar, "stats": item.get("s", [])})
	return cell


func _gem_cell(gem: Dictionary, cb: Callable, mark: bool) -> Control:
	var rar := String(gem.get("r", "common"))
	var cell := _ClickCell.new()
	cell.on_click = cb
	cell.custom_minimum_size = Vector2(72, 72)
	cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var box := Panel.new()
	box.add_theme_stylebox_override("panel", Style.inv_cell_box(rar, true))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ic := GearIcon.new("gem", Palette.rarity_color(rar))
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(ic)
	ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ic.offset_left = 10
	ic.offset_top = 10
	ic.offset_right = -10
	ic.offset_bottom = -10
	var tag := Style.pixel_label("W" if String(gem.get("cat", "")) == "weapon" else "A", 8,
		Palette.EMBER_BRIGHT if String(gem.get("cat", "")) == "weapon" else Palette.CYAN_BRIGHT)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(tag)
	tag.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	tag.offset_left = 5
	tag.offset_top = 3
	tag.offset_right = 20
	tag.offset_bottom = 18
	if mark:
		_rarity_mark(cell)
	Tip.attach(cell, {"name": String(gem.get("n", "")), "type": "Gem · %s · %s" % [String(gem.get("cat", "")), rar],
		"rarity": rar, "stats": [["Effect", String(gem.get("eff", ""))]]})
	return cell


# =========================================================================
# SALVAGE page — break gear down into crafting materials.
# =========================================================================

func _build_salvage_page() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	var lp := _titled_panel("ALL ITEMS", "Pick a piece to break down for materials")
	_salvage_grid = _grid_in(lp["body"], 4)
	row.add_child(lp["panel"])
	var right := PanelContainer.new()
	right.add_theme_stylebox_override("panel", Style.panel_box())
	right.custom_minimum_size = Vector2(370, 0)
	var pad := _pad(16)
	right.add_child(pad)
	_salvage_detail = VBoxContainer.new()
	_salvage_detail.add_theme_constant_override("separation", 12)
	pad.add_child(_salvage_detail)
	row.add_child(right)
	_rebuilders.append(_rebuild_salvage)
	_rebuild_salvage()
	return row


func _rebuild_salvage() -> void:
	if _salvage_grid == null:
		return
	for c in _salvage_grid.get_children():
		c.queue_free()
	var gear := _bag_gear()
	if gear.is_empty():
		_salvage_grid.add_child(Style.body_label("No spare gear in your bag.\nUnequip pieces, or pull / craft more.", 12, Palette.TX_FAINT))
		_salvage_picks = []
		_refresh_salvage_detail()
		return
	# Drop stale picks (pieces salvaged/moved elsewhere).
	var kept: Array = []
	for p in _salvage_picks:
		for g in gear:
			if is_same(g, p):
				kept.append(p)
				break
	_salvage_picks = kept
	for it in gear:
		var picked := false
		for p in _salvage_picks:
			if is_same(p, it):
				picked = true
				break
		_salvage_grid.add_child(_gear_cell(it, _toggle_salvage_pick.bind(it), picked))
	_refresh_salvage_detail()


func _toggle_salvage_pick(item: Dictionary) -> void:
	var idx := -1
	for i in _salvage_picks.size():
		if is_same(_salvage_picks[i], item):
			idx = i
			break
	if idx >= 0:
		_salvage_picks.remove_at(idx)
	else:
		_salvage_picks.append(item)
	_rebuild_salvage()


func _salvage_select_all() -> void:
	_salvage_picks = _bag_gear().duplicate()
	_rebuild_salvage()


func _refresh_salvage_detail() -> void:
	for c in _salvage_detail.get_children():
		c.queue_free()
	_salvage_detail.add_child(Style.display_label("SALVAGE", 13, Palette.GOLD))
	var n := _salvage_picks.size()
	var total_gold := 0
	for it in _salvage_picks:
		var r := String((it as Dictionary).get("r", "common"))
		if not Craft.SALVAGE.has(r):
			r = "legendary"
		total_gold += int(Craft.SALVAGE[r]["gold"])
	if n == 0:
		_salvage_detail.add_child(Style.body_label("Tap pieces on the left to select — multiple at once.", 12, Palette.TX_MUTE))
	else:
		_salvage_detail.add_child(Style.body_label("%d selected · %s gold total" % [n, Style.group_int(total_gold)], 13, Palette.TX))
	var btnrow := HBoxContainer.new()
	btnrow.add_theme_constant_override("separation", 8)
	var allb := Style.make_button("Select all", "stone", 12)
	allb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	allb.pressed.connect(_salvage_select_all)
	btnrow.add_child(allb)
	var sb := Style.make_button("Salvage %d" % n if n > 0 else "Salvage", "ember", 12)
	sb.disabled = n == 0 or GameState.gold < total_gold
	sb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	sb.pressed.connect(_do_salvage)
	btnrow.add_child(sb)
	_salvage_detail.add_child(btnrow)
	# Last batch summary — what the previous salvage returned.
	if not _salvage_summary.is_empty():
		_salvage_detail.add_child(_hairline())
		_salvage_detail.add_child(Style.body_label("Broke down %d piece(s) · −%s gold" % [int(_salvage_summary["count"]), Style.group_int(int(_salvage_summary["gold"]))], 12, Palette.TX_MUTE))
		_salvage_detail.add_child(Style.body_label("Gained:", 12, Palette.GOLD))
		var mats: Dictionary = _salvage_summary["mats"]
		for mid in Craft.MATERIAL_ORDER:
			if mats.has(mid):
				var mrow := HBoxContainer.new()
				mrow.add_theme_constant_override("separation", 6)
				var mic := GearIcon.new(String(Craft.MATERIALS[mid]["kind"]), Palette.rarity_color(String(Craft.MATERIALS[mid]["tier"])))
				mic.custom_minimum_size = Vector2(22, 22)
				mrow.add_child(mic)
				mrow.add_child(Style.body_label("%s ×%d" % [String(Craft.MATERIALS[mid]["n"]), int(mats[mid])], 12, Palette.R_UNCOMMON))
				_salvage_detail.add_child(mrow)


func _hairline() -> Control:
	var h := ColorRect.new()
	h.color = Palette.IRON_EDGE
	h.custom_minimum_size = Vector2(0, 1)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


func _do_salvage() -> void:
	if _salvage_picks.is_empty():
		return
	var res := GameState.salvage_items(_salvage_picks.duplicate(), _rng)
	if not bool(res["ok"]):
		return
	_salvage_summary = {"gold": int(res["gold"]), "mats": res["mats"], "count": int(res["count"])}
	_salvage_picks = []
	_glow_flash(_salvage_grid, Palette.CYAN_BRIGHT)
	_refresh_salvage_detail()  # _on_inv_changed also rebuilds the grid


func _big_slot(kind: String, rar: String) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(120, 120)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var box := Panel.new()
	box.add_theme_stylebox_override("panel", Style.slot_box(rar, true))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ic := GearIcon.new(kind, Palette.rarity_color(rar))
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(ic)
	ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ic.offset_left = 12
	ic.offset_top = 12
	ic.offset_right = -12
	ic.offset_bottom = -12
	return holder


func _mini_slot(kind: String, rar: String) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(58, 58)
	var box := Panel.new()
	box.add_theme_stylebox_override("panel", Style.slot_box(rar, true) if kind != "" else Style.slot_box())
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if kind != "":
		var ic := GearIcon.new(kind, Palette.rarity_color(rar))
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(ic)
		ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ic.offset_left = 7
		ic.offset_top = 7
		ic.offset_right = -7
		ic.offset_bottom = -7
	return holder


func _cost_line(label: String, value: String, ok: bool) -> Control:
	var row := HBoxContainer.new()
	var l := Style.body_label(label, 12, Palette.TX_DIM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	row.add_child(Style.body_label(value, 12, Palette.TX if ok else Palette.HP))
	return row


# =========================================================================
# FUSION page — 5 gear (or 5 gems) → 1, rarity shifts vs the highest input.
# =========================================================================

func _build_fusion_page() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	var lp := _titled_panel("SOURCE", "Tap to add up to 5 of the same type")
	var toggle := HBoxContainer.new()
	toggle.add_theme_constant_override("separation", 6)
	for m: Array in [["gear", "Gear"], ["gem", "Gems"]]:
		var b := Style.make_button(String(m[1]), "stone", 13)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.pressed.connect(_set_fusion_mode.bind(String(m[0])))
		toggle.add_child(b)
	(lp["body"] as VBoxContainer).add_child(toggle)
	_fusion_grid = _grid_in(lp["body"], 4)
	row.add_child(lp["panel"])
	var right := PanelContainer.new()
	right.add_theme_stylebox_override("panel", Style.panel_box())
	right.custom_minimum_size = Vector2(400, 0)
	var pad := _pad(16)
	right.add_child(pad)
	var rc := VBoxContainer.new()
	rc.add_theme_constant_override("separation", 12)
	pad.add_child(rc)
	rc.add_child(Style.display_label("FUSION CAULDRON", 13, Palette.GOLD))
	_fusion_slot_row = HBoxContainer.new()
	_fusion_slot_row.add_theme_constant_override("separation", 8)
	_fusion_slot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	rc.add_child(_fusion_slot_row)
	_fusion_status = Style.body_label("", 12, Palette.TX_MUTE)
	_fusion_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rc.add_child(_fusion_status)
	_fusion_btn = Style.make_button("Fuse ×5", "ember")
	_fusion_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_fusion_btn.pressed.connect(_do_fuse)
	rc.add_child(_fusion_btn)
	_fusion_result = VBoxContainer.new()
	_fusion_result.add_theme_constant_override("separation", 8)
	rc.add_child(_fusion_result)
	row.add_child(right)
	_rebuilders.append(_rebuild_fusion)
	_rebuild_fusion()
	return row


func _set_fusion_mode(mode: String) -> void:
	_fusion_mode = mode
	_fusion_picks = []
	_rebuild_fusion()


func _fusion_source() -> Array:
	return GameState.gems if _fusion_mode == "gem" else _bag_gear()


func _rebuild_fusion() -> void:
	if _fusion_grid == null:
		return
	for c in _fusion_grid.get_children():
		c.queue_free()
	var src := _fusion_source()
	if src.is_empty():
		_fusion_grid.add_child(Style.body_label("No %s to fuse yet." % ("gems" if _fusion_mode == "gem" else "spare gear"), 12, Palette.TX_FAINT))
		_fusion_picks = []
		_refresh_fusion_slots()
		return
	var kept: Array = []
	for p in _fusion_picks:
		for s in src:
			if is_same(s, p):
				kept.append(p)
				break
	_fusion_picks = kept
	for it in src:
		var picked := false
		for p in _fusion_picks:
			if is_same(p, it):
				picked = true
				break
		var cell: Control = _gem_cell(it, _toggle_fusion_pick.bind(it), picked) if _fusion_mode == "gem" else _gear_cell(it, _toggle_fusion_pick.bind(it), picked)
		_fusion_grid.add_child(cell)
	_refresh_fusion_slots()


func _toggle_fusion_pick(it: Dictionary) -> void:
	var idx := -1
	for i in _fusion_picks.size():
		if is_same(_fusion_picks[i], it):
			idx = i
			break
	if idx >= 0:
		_fusion_picks.remove_at(idx)
	elif _fusion_picks.size() < Craft.FUSE_COUNT:
		_fusion_picks.append(it)
	_rebuild_fusion()


func _refresh_fusion_slots() -> void:
	for c in _fusion_slot_row.get_children():
		c.queue_free()
	for i in Craft.FUSE_COUNT:
		if i < _fusion_picks.size():
			var it: Dictionary = _fusion_picks[i]
			var rar := String(it.get("r", "common"))
			var kind := "gem" if _fusion_mode == "gem" else GearIcon.kind_for_slot(String(it.get("slot", "")))
			_fusion_slot_row.add_child(_mini_slot(kind, rar))
		else:
			_fusion_slot_row.add_child(_mini_slot("", ""))
	if _fusion_picks.size() == Craft.FUSE_COUNT:
		var hi := Craft.highest_rarity(_fusion_picks)
		var table: Dictionary = Craft.FUSE_GEM[hi] if _fusion_mode == "gem" else Craft.FUSE_GEAR[hi]
		var cost := Craft.fuse_gem_gold(hi) if _fusion_mode == "gem" else Craft.fuse_gear_gold(hi)
		_fusion_status.text = "Highest %s · %s gold\nsame %d%%  ·  +1 tier %d%%  ·  +2 %d%%  ·  -1 %d%%" % [
			hi, Style.group_int(cost), roundi(float(table["same"]) * 100.0), roundi(float(table["up1"]) * 100.0),
			roundi(float(table["up2"]) * 100.0), roundi(float(table["down1"]) * 100.0)]
		_fusion_status.add_theme_color_override("font_color", Palette.TX_MUTE)
		_fusion_btn.disabled = GameState.gold < cost
	else:
		_fusion_status.text = "Add %d more." % (Craft.FUSE_COUNT - _fusion_picks.size())
		_fusion_status.add_theme_color_override("font_color", Palette.TX_MUTE)
		_fusion_btn.disabled = true


func _do_fuse() -> void:
	if _fusion_picks.size() != Craft.FUSE_COUNT:
		return
	var picks := _fusion_picks.duplicate()
	var res: Dictionary = GameState.fuse_gems(picks, _rng) if _fusion_mode == "gem" else GameState.fuse_gear(picks, _rng)
	if not bool(res["ok"]):
		return
	_fusion_picks = []
	var up := bool(res.get("up", false))
	var rr := String(res.get("rarity", ""))
	# _on_inv_changed rebuilds the grid + slots; set the headline + result card after.
	_fusion_status.text = ("★ UP-TIER → %s!" % rr.capitalize()) if up else ("Result: %s" % rr.capitalize())
	_fusion_status.add_theme_color_override("font_color", Palette.R_UNCOMMON if up else Palette.TX)
	_render_fusion_result(res)


## Show what the fusion produced — the rolled item/gem with its icon + name.
func _render_fusion_result(res: Dictionary) -> void:
	for c in _fusion_result.get_children():
		c.queue_free()
	var obj: Dictionary = res.get("gem", res.get("item", {}))
	if obj.is_empty():
		return
	var up := bool(res.get("up", false))
	var rar := String(obj.get("r", "common"))
	_fusion_result.add_child(_hairline())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var kind := "gem" if _fusion_mode == "gem" else GearIcon.kind_for_slot(String(obj.get("slot", "")))
	row.add_child(_mini_slot(kind, rar))
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_child(Style.body_label(String(obj.get("n", "")), 14, Palette.rarity_color(rar)))
	if _fusion_mode == "gem":
		info.add_child(Style.body_label(String(obj.get("eff", "")), 12, Palette.CYAN_BRIGHT))
	else:
		info.add_child(Style.body_label("%s · iLvl %d" % [String(obj.get("slot", "")), int(obj.get("ilvl", 0))], 12, Palette.TX_MUTE))
	row.add_child(info)
	_fusion_result.add_child(row)
	_glow_flash(_fusion_result, Palette.EMBER_BRIGHT if up else Palette.CYAN_BRIGHT)


# =========================================================================
# BLACKSMITH page — craft a fresh piece of a chosen slot + rarity.
# =========================================================================

func _build_craft_page() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	var lp := _titled_panel("BLACKSMITH", "Forge a fresh piece from materials")
	var body: VBoxContainer = lp["body"]
	body.add_child(Style.body_label("Slot", 12, Palette.TX_MUTE))
	var sgrid := GridContainer.new()
	sgrid.columns = 3
	sgrid.add_theme_constant_override("h_separation", 6)
	sgrid.add_theme_constant_override("v_separation", 6)
	for s in Craft.CRAFT_SLOTS:
		var b := Style.make_button(s, "stone", 12)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.pressed.connect(_set_craft_slot.bind(s))
		_craft_slot_btns[s] = b
		sgrid.add_child(b)
	body.add_child(sgrid)
	body.add_child(Style.body_label("Rarity", 12, Palette.TX_MUTE))
	var rrow := HBoxContainer.new()
	rrow.add_theme_constant_override("separation", 6)
	for r in Craft.RARITIES:
		var b := Style.make_button(String(r).capitalize(), "stone", 12)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.pressed.connect(_set_craft_rarity.bind(r))
		_craft_rar_btns[r] = b
		rrow.add_child(b)
	body.add_child(rrow)
	row.add_child(lp["panel"])
	var right := PanelContainer.new()
	right.add_theme_stylebox_override("panel", Style.panel_box())
	right.custom_minimum_size = Vector2(360, 0)
	var pad := _pad(16)
	right.add_child(pad)
	var rc := VBoxContainer.new()
	rc.add_theme_constant_override("separation", 12)
	pad.add_child(rc)
	rc.add_child(Style.display_label("FORGE ORDER", 13, Palette.GOLD))
	_craft_result = Control.new()
	_craft_result.custom_minimum_size = Vector2(0, 128)
	rc.add_child(_craft_result)
	_craft_cost = VBoxContainer.new()
	_craft_cost.add_theme_constant_override("separation", 5)
	rc.add_child(_craft_cost)
	_craft_status = Style.body_label("", 12, Palette.TX_MUTE)
	rc.add_child(_craft_status)
	_craft_forge_btn = Style.make_button("Forge", "ember")
	_craft_forge_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_craft_forge_btn.pressed.connect(_do_craft)
	rc.add_child(_craft_forge_btn)
	row.add_child(right)
	_rebuilders.append(_refresh_craft)
	_refresh_craft()
	return row


func _set_craft_slot(s: String) -> void:
	_craft_slot = s
	_refresh_craft()


func _set_craft_rarity(r: String) -> void:
	_craft_rarity = r
	_refresh_craft()


func _refresh_craft() -> void:
	if _craft_result == null:
		return
	for s in _craft_slot_btns:
		(_craft_slot_btns[s] as Button).modulate = Color(1.0, 0.82, 0.42) if String(s) == _craft_slot else Color(1, 1, 1)
	for r in _craft_rar_btns:
		(_craft_rar_btns[r] as Button).modulate = Palette.rarity_color(String(r)) if String(r) == _craft_rarity else Color(1, 1, 1)
	for c in _craft_result.get_children():
		c.queue_free()
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_craft_result.add_child(cc)
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.add_child(_big_slot(GearIcon.kind_for_slot(_craft_slot), _craft_rarity))
	for c in _craft_cost.get_children():
		c.queue_free()
	var g := Craft.craft_gold(_craft_rarity)
	var afford_gold := GameState.gold >= g
	_craft_cost.add_child(_cost_line("Gold", Style.group_int(g), afford_gold))
	var costs: Dictionary = Craft.CRAFT_MATS[_craft_rarity]
	var afford_mats := GameState.mat_afford(costs)
	for mid in costs:
		var have := GameState.mat_count(String(mid))
		_craft_cost.add_child(_cost_line(String(Craft.MATERIALS[mid]["n"]), "×%d  (have %d)" % [int(costs[mid]), have], have >= int(costs[mid])))
	_craft_forge_btn.disabled = not (afford_gold and afford_mats)
	_craft_status.text = "%s %s · iLvl %d" % [_craft_rarity.capitalize(), _craft_slot, Craft.craft_ilvl(_craft_rarity)]
	_craft_status.add_theme_color_override("font_color", Palette.TX_MUTE)


func _do_craft() -> void:
	var res := GameState.craft_item(_craft_slot, _craft_rarity, _rng)
	if not bool(res["ok"]):
		return
	_glow_flash(_craft_result, Palette.rarity_color(_craft_rarity))
	_craft_status.text = "Forged: %s" % String((res["item"] as Dictionary).get("n", ""))
	_craft_status.add_theme_color_override("font_color", Palette.GOLD_BRIGHT)


# =========================================================================
# SOCKET page — drill sockets (per-slot limit) + insert type-locked gems.
# =========================================================================

func _build_socket_page() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	var lp := _titled_panel("ITEMS", "Pick a piece to drill & socket")
	_socket_grid = _grid_in(lp["body"], 4)
	row.add_child(lp["panel"])
	var right := PanelContainer.new()
	right.add_theme_stylebox_override("panel", Style.panel_box())
	right.custom_minimum_size = Vector2(430, 0)
	var pad := _pad(16)
	right.add_child(pad)
	_socket_detail = VBoxContainer.new()
	_socket_detail.add_theme_constant_override("separation", 10)
	pad.add_child(_socket_detail)
	row.add_child(right)
	_rebuilders.append(_rebuild_socket)
	_rebuild_socket()
	return row


func _socket_items() -> Array:
	var out: Array = []
	for it in GameState.equipped:
		if it != null:
			out.append(it)
	for it in _bag_gear():
		out.append(it)
	return out


func _rebuild_socket() -> void:
	if _socket_grid == null:
		return
	for c in _socket_grid.get_children():
		c.queue_free()
	var items := _socket_items()
	var still := false
	for i in items:
		if not _socket_sel.is_empty() and is_same(i, _socket_sel):
			still = true
			break
	if not still:
		_socket_sel = {}
	for it in items:
		var picked := not _socket_sel.is_empty() and is_same(it, _socket_sel)
		_socket_grid.add_child(_gear_cell(it, _sel_socket.bind(it), picked))
	_refresh_socket_detail()


func _sel_socket(it: Dictionary) -> void:
	_socket_sel = it
	_rebuild_socket()


func _refresh_socket_detail() -> void:
	for c in _socket_detail.get_children():
		c.queue_free()
	_socket_detail.add_child(Style.display_label("SOCKETS", 13, Palette.GOLD))
	if _socket_sel.is_empty():
		_socket_detail.add_child(Style.body_label("Select a piece on the left.", 12, Palette.TX_MUTE))
		return
	var slot := String(_socket_sel.get("slot", ""))
	var maxs := Craft.socket_max(slot)
	var sockets: Array = _socket_sel.get("sockets", [])
	_socket_detail.add_child(Style.body_label("%s · %d / %d sockets" % [String(_socket_sel.get("n", "")), sockets.size(), maxs],
		13, Palette.rarity_color(String(_socket_sel.get("r", "common")))))
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 8)
	_socket_detail.add_child(srow)
	if sockets.is_empty():
		srow.add_child(Style.body_label("No sockets yet.", 12, Palette.TX_FAINT))
	for i in sockets.size():
		srow.add_child(_socket_slot_cell(i, sockets[i]))
	if sockets.size() < maxs:
		var nth := sockets.size() + 1
		var g := Craft.socket_gold(nth)
		var mats: Dictionary = Craft.SOCKET_MATS.get(nth, {})
		var parts: Array = []
		for k in mats:
			parts.append("%s×%d" % [String(Craft.MATERIALS[k]["n"]), int(mats[k])])
		var extra := ("  +  " + ", ".join(parts)) if not parts.is_empty() else ""
		var db := Style.make_button("Drill socket %d · %s gold%s" % [nth, Style.group_int(g), extra], "ember")
		db.disabled = GameState.gold < g or not GameState.mat_afford(mats)
		db.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		db.pressed.connect(_do_drill)
		_socket_detail.add_child(db)
	else:
		_socket_detail.add_child(Style.body_label("Fully socketed (max %d for %s)." % [maxs, slot], 12, Palette.TX_MUTE))
	_socket_detail.add_child(Style.body_label("Your %s gems — click to socket:" % ("weapon" if slot in Craft.GEM_WEAPON_SLOTS else "armour"), 12, Palette.TX_MUTE))
	var glist := GridContainer.new()
	glist.columns = 6
	glist.add_theme_constant_override("h_separation", 6)
	glist.add_theme_constant_override("v_separation", 6)
	_socket_detail.add_child(glist)
	var any := false
	for gem in GameState.gems:
		if Craft.gem_fits_slot(gem, slot):
			glist.add_child(_gem_cell(gem, _do_insert_gem.bind(gem), false))
			any = true
	if not any:
		_socket_detail.add_child(Style.body_label("(no fitting gems — fuse or salvage for more)", 11, Palette.TX_FAINT))


func _socket_slot_cell(i: int, gem: Variant) -> Control:
	var cell := _ClickCell.new()
	cell.custom_minimum_size = Vector2(58, 58)
	var rar := String((gem as Dictionary).get("r", "common")) if gem != null else ""
	var box := Panel.new()
	box.add_theme_stylebox_override("panel", Style.slot_box(rar, true) if gem != null else Style.slot_box())
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if gem != null:
		cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var ic := GearIcon.new("gem", Palette.rarity_color(rar))
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(ic)
		ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ic.offset_left = 8
		ic.offset_top = 8
		ic.offset_right = -8
		ic.offset_bottom = -8
		cell.on_click = _do_remove_gem.bind(i)
		Tip.attach(cell, {"name": String((gem as Dictionary).get("n", "")), "type": "Socketed · click to remove",
			"rarity": rar, "stats": [["Effect", String((gem as Dictionary).get("eff", ""))]]})
	return cell


func _do_drill() -> void:
	var res := GameState.drill_socket(_socket_sel)
	if bool(res["ok"]):
		_glow_flash(_socket_detail, Palette.EMBER_BRIGHT)


func _do_insert_gem(gem: Dictionary) -> void:
	var sockets: Array = _socket_sel.get("sockets", [])
	for i in sockets.size():
		if sockets[i] == null:
			GameState.insert_gem(_socket_sel, i, gem)
			return


func _do_remove_gem(i: int) -> void:
	GameState.remove_gem(_socket_sel, i)


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


## A lightweight left-click cell for the salvage/fusion/socket grids.
class _ClickCell:
	extends Control

	var on_click: Callable = Callable()

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and on_click.is_valid():
			on_click.call()
			accept_event()
