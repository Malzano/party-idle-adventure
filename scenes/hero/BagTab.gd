extends Control
## HERO · BAG tab — two panels:
##   LEFT  : the Tetris grid the player arranges pieces in (cell rails visible).
##   RIGHT : EVERY gear item the hero owns — both bag pieces and the ones worn on
##           the paperdoll (those carry an EQUIPPED tag). Drag a worn piece onto
##           the grid to take it off and stow it; drag a bag piece to place it.
## Pieces can't overlap. Drag within the grid to rearrange, or back onto the
## right panel to take a piece off the grid.
##
## Pieces own a defined SHAPE (GameContent.item_shape_cells) — some are
## non-rectangular, so they interlock. A top-right preview shows the drag shape
## of whatever piece is hovered. Grid layout is session-local; unequipping
## (worn → grid) is a real, persisted change. This bag is what feeds the
## bullet-hell Survival side mode.

const GRID_W := 7
const GRID_H := 6
const CELL := 80.0
const GAP := 6.0

var _grid_host: Control
var _tiles_holder: Control
var _loose_grid: GridContainer
var _cap_lbl: Label
var _preview: _ShapePreview
var _placements: Array = []   # [{item, pos:Vector2i, size:Vector2i, cells:Array}]
var _loose: Array = []        # [{item, equipped:bool, slot:int}] — the right list
var _occ: Array = []          # GRID_H rows × GRID_W bools
var _suppress_reload := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	add_child(col)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 22
	col.offset_top = 12
	col.offset_right = -22
	col.offset_bottom = -16
	col.add_child(_build_header())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	body.add_child(_build_grid_panel())
	body.add_child(_build_loose_panel())

	# Floating drag-shape preview, top-right of the tab.
	_preview = _ShapePreview.new()
	add_child(_preview)
	_preview.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_preview.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_preview.offset_top = 6
	_preview.offset_right = -6
	_preview.visible = false

	EventBus.equipment_changed.connect(_on_equipment_changed)
	_reload()


func _grid_px() -> Vector2:
	return Vector2(GRID_W * CELL + (GRID_W - 1) * GAP, GRID_H * CELL + (GRID_H - 1) * GAP)


func _cell_pos(c: Vector2i) -> Vector2:
	return Vector2(c.x * (CELL + GAP), c.y * (CELL + GAP))


func _tile_px(size: Vector2i) -> Vector2:
	return Vector2(size.x * CELL + (size.x - 1) * GAP, size.y * CELL + (size.y - 1) * GAP)


# --- hover preview (top-right) ----------------------------------------------

func _preview_shape(item: Dictionary) -> void:
	if _preview != null:
		_preview.show_item(item)


func _preview_clear() -> void:
	if _preview != null:
		_preview.visible = false


func _drag_ghost(item: Dictionary) -> Control:
	var fp := GameContent.item_footprint(item)
	var holder := Control.new()
	holder.custom_minimum_size = _tile_px(fp)
	holder.size = holder.custom_minimum_size
	holder.modulate = Color(1, 1, 1, 0.8)
	_Paint.cells(holder, item, CELL, GAP)
	return holder


# --- panels -----------------------------------------------------------------

func _build_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var title := Style.display_label("BAG", 22, Palette.GOLD_BRIGHT)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(title)
	var sub := Style.body_label("Pack pieces by shape — worn pieces come off when stowed. This loadout powers Survival.", 13, Palette.TX_MUTE)
	sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sub)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	var sort_btn := Style.make_button("Auto-sort", "ghost", 12)
	sort_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	sort_btn.pressed.connect(_auto_sort)
	row.add_child(sort_btn)
	return row


func _build_grid_panel() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Style.panel_box())
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var pad := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(m, 14)
	panel.add_child(pad)
	var vc := VBoxContainer.new()
	vc.add_theme_constant_override("separation", 10)
	pad.add_child(vc)
	# Cell counter sits at the top of the bag.
	_cap_lbl = Style.pixel_label("", 12, Palette.TX_DIM)
	vc.add_child(_cap_lbl)
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vc.add_child(center)
	_grid_host = _BagGrid.new()
	(_grid_host as _BagGrid).bag = self
	_grid_host.custom_minimum_size = _grid_px()
	center.add_child(_grid_host)
	for gy in GRID_H:
		for gx in GRID_W:
			var rcell := Panel.new()
			rcell.add_theme_stylebox_override("panel", Style.slot_box())
			rcell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_grid_host.add_child(rcell)
			rcell.position = _cell_pos(Vector2i(gx, gy))
			rcell.size = Vector2(CELL, CELL)
	_tiles_holder = Control.new()
	_tiles_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid_host.add_child(_tiles_holder)
	_tiles_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return panel


func _build_loose_panel() -> Control:
	var drop := _LooseDrop.new()
	drop.bag = self
	drop.custom_minimum_size = Vector2(360, 0)
	drop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drop.add_theme_stylebox_override("panel", Style.panel_box())
	var pad := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(m, 14)
	drop.add_child(pad)
	var vc := VBoxContainer.new()
	vc.add_theme_constant_override("separation", 10)
	pad.add_child(vc)
	vc.add_child(Style.display_label("ALL ITEMS", 13, Palette.GOLD))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	vc.add_child(scroll)
	_loose_grid = GridContainer.new()
	_loose_grid.columns = 6
	_loose_grid.add_theme_constant_override("h_separation", 9)
	_loose_grid.add_theme_constant_override("v_separation", 9)
	_loose_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_loose_grid.mouse_filter = Control.MOUSE_FILTER_PASS
	_loose_grid.resized.connect(_resize_square_loose)
	scroll.add_child(_loose_grid)
	return drop


## Keep the ALL ITEMS cells square (like the Equipment inventory grid).
func _resize_square_loose() -> void:
	if _loose_grid == null:
		return
	var cols := _loose_grid.columns
	var cw := floorf((_loose_grid.size.x - 9.0 * float(cols - 1)) / float(cols))
	if cw < 10.0:
		return
	for c in _loose_grid.get_children():
		var ctl := c as Control
		if ctl != null and absf(ctl.custom_minimum_size.y - cw) > 0.5:
			ctl.custom_minimum_size = Vector2(0, cw)


# --- occupancy + packing (cell-mask based) ----------------------------------

func _clear_occ() -> void:
	_occ.clear()
	for gy in GRID_H:
		var r: Array = []
		r.resize(GRID_W)
		r.fill(false)
		_occ.append(r)


func _mark(pos: Vector2i, cells: Array, val: bool) -> void:
	for c in cells:
		_occ[pos.y + int(c.y)][pos.x + int(c.x)] = val


func _fits(pos: Vector2i, cells: Array) -> bool:
	for c in cells:
		var x := pos.x + int(c.x)
		var y := pos.y + int(c.y)
		if x < 0 or y < 0 or x >= GRID_W or y >= GRID_H:
			return false
		if bool(_occ[y][x]):
			return false
	return true


func _first_fit(cells: Array) -> Vector2i:
	for gy in GRID_H:
		for gx in GRID_W:
			if _fits(Vector2i(gx, gy), cells):
				return Vector2i(gx, gy)
	return Vector2i(-1, -1)


func _on_equipment_changed() -> void:
	if not _suppress_reload:
		_reload()


## Fresh load: the grid is empty; the right list holds every owned piece —
## bag pieces plus the ones worn on the paperdoll (flagged equipped).
func _reload() -> void:
	_clear_occ()
	_placements.clear()
	_loose.clear()
	for it in GameState.bag_equipment:
		_loose.append({"item": it, "equipped": false, "slot": -1})
	for slot in GameState.equipped.size():
		var it_v: Variant = GameState.equipped[slot]
		if it_v != null:
			_loose.append({"item": it_v, "equipped": true, "slot": slot})
	_rebuild_tiles()
	_rebuild_loose()
	_update_cap()


## Auto-sort: pack the BAG pieces (placed + loose, never the worn ones) into the
## grid, largest-first (by occupied-cell count). Worn pieces stay in the right list.
func _auto_sort() -> void:
	var bag_items: Array = []
	for p in _placements:
		bag_items.append(p["item"])
	var keep_loose: Array = []
	for e in _loose:
		if bool(e["equipped"]):
			keep_loose.append(e)
		else:
			bag_items.append(e["item"])
	bag_items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return GameContent.item_shape_cells(a).size() > GameContent.item_shape_cells(b).size())
	_clear_occ()
	_placements.clear()
	for it in bag_items:
		var cells := GameContent.item_shape_cells(it)
		var pos := _first_fit(cells)
		if pos.x < 0:
			keep_loose.append({"item": it, "equipped": false, "slot": -1})
			continue
		_mark(pos, cells, true)
		_placements.append({"item": it, "pos": pos, "size": GameContent.item_footprint(it), "cells": cells})
	_loose = keep_loose
	_rebuild_tiles()
	_rebuild_loose()
	_update_cap()


func _update_cap() -> void:
	if _cap_lbl == null:
		return
	var used := 0
	for p in _placements:
		used += (p["cells"] as Array).size()
	_cap_lbl.text = "%d / %d cells used" % [used, GRID_W * GRID_H]


# --- moves (drag targets delegate here) -------------------------------------

func _can_place(pidx: int, target: Vector2i) -> bool:
	if pidx < 0 or pidx >= _placements.size():
		return false
	var p: Dictionary = _placements[pidx]
	var cells: Array = p["cells"]
	_mark(p["pos"], cells, false)
	var ok := _fits(target, cells)
	_mark(p["pos"], cells, true)
	return ok


func _try_move(pidx: int, target: Vector2i) -> bool:
	if not _can_place(pidx, target):
		return false
	var p: Dictionary = _placements[pidx]
	var cells: Array = p["cells"]
	_mark(p["pos"], cells, false)
	p["pos"] = target
	_mark(target, cells, true)
	_rebuild_tiles()
	return true


func _can_place_loose(lidx: int, target: Vector2i) -> bool:
	if lidx < 0 or lidx >= _loose.size():
		return false
	return _fits(target, GameContent.item_shape_cells(_loose[lidx]["item"]))


func _try_place_loose(lidx: int, target: Vector2i) -> bool:
	if not _can_place_loose(lidx, target):
		return false
	var entry: Dictionary = _loose[lidx]
	var it: Dictionary = entry["item"]
	var cells := GameContent.item_shape_cells(it)
	# Worn piece → stowing it means taking it off (a real, persisted unequip).
	if bool(entry["equipped"]):
		_suppress_reload = true
		var ok := GameState.unequip_to_bag(int(entry["slot"]))
		_suppress_reload = false
		if not ok:
			return false
	_loose.remove_at(lidx)
	_mark(target, cells, true)
	_placements.append({"item": it, "pos": target, "size": GameContent.item_footprint(it), "cells": cells})
	_rebuild_tiles()
	_rebuild_loose()
	_update_cap()
	return true


## Take a placed piece off the grid and back into the loose (bag) list.
func _unplace(pidx: int) -> void:
	if pidx < 0 or pidx >= _placements.size():
		return
	var p: Dictionary = _placements[pidx]
	_mark(p["pos"], p["cells"], false)
	_loose.append({"item": p["item"], "equipped": false, "slot": -1})
	_placements.remove_at(pidx)
	_rebuild_tiles()
	_rebuild_loose()
	_update_cap()


# --- rendering --------------------------------------------------------------

func _rebuild_tiles() -> void:
	for c in _tiles_holder.get_children():
		c.queue_free()
	for i in _placements.size():
		var p: Dictionary = _placements[i]
		var tile := _BagTile.new()
		tile.bag = self
		tile.pidx = i
		tile.item = p["item"]
		tile.size_cells = p["size"]
		_tiles_holder.add_child(tile)
		tile.position = _cell_pos(p["pos"])
		tile.size = _tile_px(p["size"])
		tile.build()


func _rebuild_loose() -> void:
	if _loose_grid == null:
		return
	for c in _loose_grid.get_children():
		c.queue_free()
	for i in _loose.size():
		var lc := _LooseCell.new()
		lc.bag = self
		lc.lidx = i
		lc.item = _loose[i]["item"]
		lc.equipped = bool(_loose[i]["equipped"])
		lc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_loose_grid.add_child(lc)
		lc.build()
	call_deferred("_resize_square_loose")


# ===========================================================================
## Shape painter: one rarity-framed cell per occupied cell + a centered glyph
## over the bounding box. Non-rectangular shapes show their real silhouette.
class _Paint:
	extends RefCounted

	static func cells(node: Control, item: Dictionary, cell_px: float, gap: float) -> void:
		var rar := String(item.get("r", "common"))
		var col := Palette.rarity_color(rar)
		for c in GameContent.item_shape_cells(item):
			var p := Panel.new()
			p.add_theme_stylebox_override("panel", Style.slot_box(rar, true))
			p.mouse_filter = Control.MOUSE_FILTER_IGNORE
			node.add_child(p)
			p.position = Vector2(int(c.x) * (cell_px + gap), int(c.y) * (cell_px + gap))
			p.size = Vector2(cell_px, cell_px)
		var fp := GameContent.item_footprint(item)
		var ic := GearIcon.new(GearIcon.kind_for_slot(String(item.get("slot", ""))), col)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.add_child(ic)
		var bw := float(fp.x) * cell_px + float(fp.x - 1) * gap
		var bh := float(fp.y) * cell_px + float(fp.y - 1) * gap
		var g := minf(bw, bh) * 0.78
		ic.position = Vector2((bw - g) * 0.5, (bh - g) * 0.5)
		ic.size = Vector2(g, g)


# ===========================================================================
class _BagGrid:
	extends Control

	var bag = null

	func _can_drop_data(at: Vector2, data: Variant) -> bool:
		if typeof(data) != TYPE_DICTIONARY:
			return false
		var d: Dictionary = data
		var target := _target_cell(at, d)
		if String(d.get("src", "")) == "grid":
			return bag._can_place(int(d["pidx"]), target)
		if String(d.get("src", "")) == "loose":
			return bag._can_place_loose(int(d["lidx"]), target)
		return false

	func _drop_data(at: Vector2, data: Variant) -> void:
		var d: Dictionary = data
		var target := _target_cell(at, d)
		if String(d.get("src", "")) == "grid":
			bag._try_move(int(d["pidx"]), target)
		elif String(d.get("src", "")) == "loose":
			bag._try_place_loose(int(d["lidx"]), target)

	func _target_cell(at: Vector2, d: Dictionary) -> Vector2i:
		var step: float = bag.CELL + bag.GAP
		var c := Vector2i(int(floor(at.x / step)), int(floor(at.y / step)))
		var grab: Vector2i = d.get("grab", Vector2i.ZERO)
		return c - grab


# ===========================================================================
class _BagTile:
	extends Control

	var bag = null
	var pidx := -1
	var item: Dictionary = {}
	var size_cells: Vector2i = Vector2i.ONE

	func build() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_Paint.cells(self, item, bag.CELL, bag.GAP)
		var fp := GameContent.item_footprint(item)
		var fp_lbl := Style.pixel_label("%d×%d" % [fp.x, fp.y], 8, Palette.GOLD_DIM)
		fp_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(fp_lbl)
		fp_lbl.position = Vector2(4, 3)
		Tip.attach(self, {
			"name": item.get("n", ""),
			"type": GameContent.item_type_line(item),
			"rarity": String(item.get("r", "")),
			"stats": GameContent.tip_stats(item, [["Bag size", "%d×%d" % [fp.x, fp.y]]]),
			"flavor": "Drag to rearrange, or onto the right panel to take it out.",
		})
		mouse_entered.connect(func() -> void: bag._preview_shape(item))
		mouse_exited.connect(func() -> void: bag._preview_clear())

	func _get_drag_data(at: Vector2) -> Variant:
		var step: float = bag.CELL + bag.GAP
		var grab := Vector2i(int(floor(at.x / step)), int(floor(at.y / step)))
		grab.x = clampi(grab.x, 0, size_cells.x - 1)
		grab.y = clampi(grab.y, 0, size_cells.y - 1)
		Tip.hide_now(self)
		bag._preview_clear()
		set_drag_preview(bag._drag_ghost(item))
		return {"src": "grid", "pidx": pidx, "grab": grab}

	# Drops landing on a placed piece convert to grid space and reuse grid logic.
	func _can_drop_data(at: Vector2, data: Variant) -> bool:
		return bag._grid_host._can_drop_data(position + at, data)

	func _drop_data(at: Vector2, data: Variant) -> void:
		bag._grid_host._drop_data(position + at, data)


# ===========================================================================
class _LooseCell:
	extends Control

	var bag = null
	var lidx := -1
	var item: Dictionary = {}
	var equipped := false

	# Compact square: inv_cell_box frame, glyph, top-left footprint badge, hover
	# highlight + the EQUIPPED tag. Hovering shows the real shape in the preview.
	func build() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var rar := String(item.get("r", "common"))
		var box := Panel.new()
		box.add_theme_stylebox_override("panel", Style.inv_cell_box(rar, true))
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(box)
		box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var ic := GearIcon.new(GearIcon.kind_for_slot(String(item.get("slot", ""))), Palette.rarity_color(rar))
		add_child(ic)
		ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ic.offset_left = 8
		ic.offset_top = 6
		ic.offset_right = -8
		ic.offset_bottom = (-18 if equipped else -8)
		var fp := GameContent.item_footprint(item)
		var fp_lbl := Style.pixel_label("%d×%d" % [fp.x, fp.y], 8, Palette.GOLD_DIM)
		fp_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(fp_lbl)
		fp_lbl.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		fp_lbl.offset_left = 4
		fp_lbl.offset_top = 3
		fp_lbl.offset_right = 44
		fp_lbl.offset_bottom = 16
		if equipped:
			var tag := Style.pixel_label("EQUIPPED", 7, Palette.EMBER_BRIGHT)
			tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			tag.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(tag)
			tag.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
			tag.offset_top = -14
			tag.offset_bottom = -3
		mouse_entered.connect(func() -> void:
			box.add_theme_stylebox_override("panel", Style.inv_cell_box(rar, true, true))
			bag._preview_shape(item))
		mouse_exited.connect(func() -> void:
			box.add_theme_stylebox_override("panel", Style.inv_cell_box(rar, true))
			bag._preview_clear())
		Tip.attach(self, {
			"name": item.get("n", ""),
			"type": GameContent.item_type_line(item),
			"rarity": rar,
			"stats": GameContent.tip_stats(item, [["Bag size", "%d×%d" % [fp.x, fp.y]]]),
			"flavor": "Worn — drag onto the grid to take it off." if equipped else "Drag onto the grid to place it.",
		})

	func _get_drag_data(_at: Vector2) -> Variant:
		Tip.hide_now(self)
		bag._preview_clear()
		set_drag_preview(bag._drag_ghost(item))
		return {"src": "loose", "lidx": lidx, "grab": Vector2i.ZERO}


# ===========================================================================
## The right "all items" panel; dropping a placed piece here takes it off the grid.
class _LooseDrop:
	extends PanelContainer

	var bag = null

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return typeof(data) == TYPE_DICTIONARY and String((data as Dictionary).get("src", "")) == "grid"

	func _drop_data(_at: Vector2, data: Variant) -> void:
		bag._unplace(int((data as Dictionary)["pidx"]))


# ===========================================================================
## Top-right preview of the hovered piece's drag shape — a small grid of its
## cells plus name + bag size, so you read the shape before dragging it.
class _ShapePreview:
	extends PanelContainer

	const PCELL := 20.0
	const PGAP := 3.0
	var _shape_host: Control
	var _name_lbl: Label
	var _size_lbl: Label

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("15110d")
		sb.set_border_width_all(1)
		sb.border_color = Palette.IRON_EDGE
		sb.set_corner_radius_all(4)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 9
		sb.content_margin_bottom = 9
		add_theme_stylebox_override("panel", sb)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		add_child(box)
		box.add_child(Style.pixel_label("DRAG SHAPE", 9, Palette.GOLD_DIM))
		var center := CenterContainer.new()
		center.custom_minimum_size = Vector2(2 * (PCELL + PGAP) + 40, 4 * (PCELL + PGAP))
		box.add_child(center)
		_shape_host = Control.new()
		_shape_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(_shape_host)
		_name_lbl = Style.body_label("", 12, Palette.TX)
		_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(_name_lbl)
		_size_lbl = Style.pixel_label("", 8, Palette.TX_MUTE)
		_size_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(_size_lbl)

	func show_item(item: Dictionary) -> void:
		for c in _shape_host.get_children():
			c.queue_free()
		var fp := GameContent.item_footprint(item)
		_shape_host.custom_minimum_size = Vector2(fp.x * (PCELL + PGAP) - PGAP, fp.y * (PCELL + PGAP) - PGAP)
		_shape_host.size = _shape_host.custom_minimum_size
		_Paint.cells(_shape_host, item, PCELL, PGAP)
		_name_lbl.text = String(item.get("n", ""))
		_name_lbl.add_theme_color_override("font_color", Palette.rarity_color(String(item.get("r", "common"))))
		_size_lbl.text = "%d×%d  ·  %d cells" % [fp.x, fp.y, GameContent.item_shape_cells(item).size()]
		visible = true
