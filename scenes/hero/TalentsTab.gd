extends Control
## PROFILE · TALENTS tab (talents.jsx TalentTree).
## Pan/zoom PoE-style node web drawn in one custom Control, with HUD overlays:
## points chip (top-center), zoom buttons (top-right), arm legend (top-left),
## hint pill (bottom-center) and a self-positioned node tooltip.

var _nodes: Array = []
var _edges: Array = []
var _adj: Dictionary = {}

var _tree: TreeView
var _chip: PanelContainer
var _spent_lbl: Label
var _power_lbl: Label  # live total-power readout so allocating visibly moves it
var _zoom_box: VBoxContainer
var _legend: PanelContainer
var _hint: PanelContainer

var _tip: PanelContainer
var _tip_name: Label
var _tip_type: Label
var _tip_eff: Label
var _tip_flavor: Label
var _last_hover := -1
var _last_mouse := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	# Build the web once and cache it.
	var data := GameContent.build_tree()
	_nodes = data["nodes"]
	_edges = data["edges"]
	for n in _nodes:
		_adj[int(n["id"])] = []
	for e in _edges:
		_adj[int(e[0])].append(int(e[1]))
		_adj[int(e[1])].append(int(e[0]))
	if GameState.talents_allocated.is_empty():
		GameState.talents_allocated = GameContent.default_allocation(_nodes, _edges)

	# .tree-wrap — iron-bordered dark panel hosting the web.
	var frame := Panel.new()
	var f_sb := StyleBoxFlat.new()
	f_sb.bg_color = Color("0a0807")
	f_sb.set_border_width_all(1)
	f_sb.border_color = Palette.IRON_EDGE
	f_sb.set_corner_radius_all(6)
	frame.add_theme_stylebox_override("panel", f_sb)
	add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_tree = TreeView.new()
	_tree.setup(_nodes, _edges, _adj)
	frame.add_child(_tree)
	_tree.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tree.offset_left = 1
	_tree.offset_top = 1
	_tree.offset_right = -1
	_tree.offset_bottom = -1
	_tree.node_clicked.connect(_on_node_clicked)
	_tree.hover_changed.connect(_on_hover)

	_build_chip()
	_build_zoom()
	_build_legend()
	_build_hint()
	_build_tip()

	resized.connect(_layout_overlays)
	EventBus.talents_changed.connect(_on_talents_changed)
	_update_points()
	call_deferred("_layout_overlays")


# =========================================================================
# Overlays
# =========================================================================

func _hud_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("15120e")
	sb.set_border_width_all(1)
	sb.border_color = Palette.IRON_EDGE
	sb.set_corner_radius_all(5)
	return sb


func _build_chip() -> void:
	_chip = PanelContainer.new()
	var sb := _hud_box()
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	_chip.add_theme_stylebox_override("panel", sb)
	_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 0)
	_spent_lbl = Style.pixel_label("0", 14, Palette.EMBER_BRIGHT)
	_spent_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_spent_lbl)
	var mid := Style.display_label(" spent · ", 14, Palette.TX_DIM)
	mid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(mid)
	var avail := Style.pixel_label(str(GameContent.TALENT_POINTS_AVAILABLE), 14, Palette.CYAN_BRIGHT)
	avail.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(avail)
	var tail := Style.display_label(" available", 14, Palette.TX_DIM)
	tail.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tail)
	# Live power readout: allocating a node visibly moves the character's power
	# (the talent tree already feeds combat — this closes the feedback gap).
	var dot := Style.display_label("   ·   ", 14, Palette.TX_DIM)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(dot)
	_power_lbl = Style.pixel_label("0", 14, Palette.GOLD)
	_power_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_power_lbl)
	var pwr := Style.display_label(" Power", 14, Palette.TX_DIM)
	pwr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(pwr)
	_chip.add_child(h)
	add_child(_chip)
	_chip.resized.connect(_layout_overlays)


func _build_zoom() -> void:
	_zoom_box = VBoxContainer.new()
	_zoom_box.add_theme_constant_override("separation", 6)
	for spec in [["+", 16, true], ["−", 16, true], ["RST", 9, false]]:
		var b := Button.new()
		b.text = String(spec[0])
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(34, 30)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		if bool(spec[2]):
			var f := Fonts.pixel()
			if f != null:
				b.add_theme_font_override("font", f)
		b.add_theme_font_size_override("font_size", Style.fs(int(spec[1])))
		b.add_theme_color_override("font_color", Palette.TX_DIM)
		b.add_theme_color_override("font_hover_color", Palette.TX)
		b.add_theme_color_override("font_pressed_color", Palette.TX_DIM)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Palette.STONE
		sb.set_border_width_all(1)
		sb.border_color = Palette.IRON_EDGE
		sb.set_corner_radius_all(3)
		var sb_h := sb.duplicate() as StyleBoxFlat
		sb_h.bg_color = Color("3f382b")
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb_h)
		b.add_theme_stylebox_override("pressed", sb)
		match String(spec[0]):
			"+":
				b.pressed.connect(func() -> void: _tree.zoom_by(1.18))
			"−":
				b.pressed.connect(func() -> void: _tree.zoom_by(0.85))
			_:
				b.pressed.connect(func() -> void: _tree.reset_view())
		_zoom_box.add_child(b)
	add_child(_zoom_box)
	_zoom_box.resized.connect(_layout_overlays)


func _build_legend() -> void:
	_legend = PanelContainer.new()
	var sb := _hud_box()
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	_legend.add_theme_stylebox_override("panel", sb)
	_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.custom_minimum_size = Vector2(150, 0)
	for arm_v in GameContent.ARMS:
		var arm: Dictionary = arm_v
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(LegendDot.new(9.0, arm["color"]))
		var nm := Style.body_label(String(arm["name"]), 11, Palette.TX_DIM)
		nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(nm)
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(sp)
		var stat := Style.pixel_label(String(arm["stat"]), 8, Palette.TX_FAINT)
		stat.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(stat)
		col.add_child(row)
	_legend.add_child(col)
	add_child(_legend)


func _build_hint() -> void:
	_hint = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.039, 0.031, 0.027, 0.6)
	sb.set_corner_radius_all(20)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	_hint.add_theme_stylebox_override("panel", sb)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_child(Style.body_label("Drag to pan · Scroll to zoom · Click a lit-adjacent node to allocate", 11, Palette.TX_FAINT))
	add_child(_hint)
	_hint.resized.connect(_layout_overlays)


func _layout_overlays() -> void:
	if _chip == null:
		return
	_chip.position = Vector2((size.x - _chip.size.x) * 0.5, 14.0)
	_zoom_box.position = Vector2(size.x - _zoom_box.size.x - 14.0, 14.0)
	_legend.position = Vector2(14.0, 14.0)
	_hint.position = Vector2((size.x - _hint.size.x) * 0.5, size.y - _hint.size.y - 12.0)


# =========================================================================
# Node tooltip (styled like Tip)
# =========================================================================

func _build_tip() -> void:
	_tip = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("15110d")
	sb.set_border_width_all(1)
	sb.border_color = Palette.IRON_EDGE
	sb.set_corner_radius_all(4)
	sb.shadow_color = Color(0, 0, 0, 0.7)
	sb.shadow_size = 14
	sb.shadow_offset = Vector2(0, 8)
	_tip.add_theme_stylebox_override("panel", sb)
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.visible = false
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var head := MarginContainer.new()
	head.add_theme_constant_override("margin_left", 12)
	head.add_theme_constant_override("margin_right", 12)
	head.add_theme_constant_override("margin_top", 9)
	head.add_theme_constant_override("margin_bottom", 7)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head_col := VBoxContainer.new()
	head_col.add_theme_constant_override("separation", 2)
	_tip_name = Style.display_label("", 15, Palette.GOLD, true)
	head_col.add_child(_tip_name)
	_tip_type = Style.body_label("", 10, Palette.TX_MUTE)
	head_col.add_child(_tip_type)
	head.add_child(head_col)
	col.add_child(head)

	col.add_child(_tip_hairline())

	var body := MarginContainer.new()
	body.add_theme_constant_override("margin_left", 12)
	body.add_theme_constant_override("margin_right", 12)
	body.add_theme_constant_override("margin_top", 9)
	body.add_theme_constant_override("margin_bottom", 9)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_eff = Style.body_label("", 12, Palette.CYAN_BRIGHT)
	_tip_eff.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_eff.custom_minimum_size = Vector2(220, 0)
	body.add_child(_tip_eff)
	col.add_child(body)

	col.add_child(_tip_hairline())

	var flav := MarginContainer.new()
	flav.add_theme_constant_override("margin_left", 12)
	flav.add_theme_constant_override("margin_right", 12)
	flav.add_theme_constant_override("margin_top", 7)
	flav.add_theme_constant_override("margin_bottom", 10)
	flav.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_flavor = Style.display_label("", 11, Palette.TX_MUTE, true)
	_tip_flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_flavor.custom_minimum_size = Vector2(220, 0)
	flav.add_child(_tip_flavor)
	col.add_child(flav)

	_tip.add_child(col)
	add_child(_tip)


func _tip_hairline() -> ColorRect:
	var h := ColorRect.new()
	h.color = Color(0, 0, 0, 0.5)
	h.custom_minimum_size = Vector2(0, 1)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


func _can_alloc(id: int) -> bool:
	if GameState.talents_allocated.has(id):
		return false
	for nb in _adj.get(id, []):
		if GameState.talents_allocated.has(int(nb)):
			return true
	return false


func _on_hover(id: int, at: Vector2) -> void:
	_last_hover = id
	_last_mouse = at
	if id < 0:
		_tip.visible = false
		return
	var n: Dictionary = _nodes[id]
	var node_type := String(n["type"])
	var ai := int(n["ai"])
	match node_type:
		"keystone":
			_tip_name.add_theme_color_override("font_color", Palette.R_LEGENDARY)
		"notable":
			_tip_name.add_theme_color_override("font_color", Palette.R_EPIC)
		_:
			_tip_name.add_theme_color_override("font_color", Palette.R_RARE)
	_tip_name.text = String(n["label"])
	var tname := "Minor Passive"
	match node_type:
		"keystone":
			tname = "Keystone"
		"notable":
			tname = "Notable"
		"start":
			tname = "Class Root"
	if ai >= 0:
		tname += " · %s" % String(GameContent.ARMS[ai]["name"])
	_tip_type.text = tname.to_upper()
	_tip_eff.text = String(n["eff"])
	if GameState.talents_allocated.has(id):
		_tip_flavor.text = "Allocated — click to refund (if at edge)."
	elif _can_alloc(id):
		_tip_flavor.text = "Click to allocate · 1 point"
	else:
		_tip_flavor.text = "Connect a path to allocate."
	_tip.visible = true
	_reposition_tip(at)


func _reposition_tip(at: Vector2) -> void:
	var sz := _tip.get_combined_minimum_size()
	var p := at + Vector2(18, 16)
	if p.x + sz.x > size.x - 8.0:
		p.x = at.x - sz.x - 16.0
	if p.y + sz.y > size.y - 8.0:
		p.y = size.y - sz.y - 8.0
	p.y = maxf(8.0, p.y)
	_tip.position = p


func _on_node_clicked(id: int) -> void:
	GameState.talent_toggle(id, _adj)
	_tree.queue_redraw()
	if _tip.visible and _last_hover == id:
		_on_hover(id, _last_mouse)


func _on_talents_changed() -> void:
	_update_points()
	_tree.queue_redraw()


func _update_points() -> void:
	_spent_lbl.text = str(maxi(0, GameState.talents_allocated.size() - 1))
	if _power_lbl != null:
		PlayerStats.invalidate()
		_power_lbl.text = Style.group_int(int(PlayerStats.compute()["total_power"]))


# =========================================================================
# The pan/zoom web view
# =========================================================================

class TreeView:
	extends Control

	signal node_clicked(id: int)
	signal hover_changed(id: int, at: Vector2)

	const RADII := {"start": 17.0, "keystone": 16.0, "notable": 11.0, "minor": 6.5}

	var nodes: Array = []
	var edges: Array = []
	var adj: Dictionary = {}

	var view_tx := 0.0
	var view_ty := 0.0
	var view_scale := 0.72

	var _dragging := false
	var _drag_moved := false
	var _drag_from := Vector2.ZERO
	var _drag_tx := 0.0
	var _drag_ty := 0.0
	var _hover_id := -1
	var _pulse := 0.0

	func setup(p_nodes: Array, p_edges: Array, p_adj: Dictionary) -> void:
		nodes = p_nodes
		edges = p_edges
		adj = p_adj

	func _ready() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_exited.connect(_on_exit)
		set_process(true)

	func _on_exit() -> void:
		_hover_id = -1
		hover_changed.emit(-1, Vector2.ZERO)

	func _process(delta: float) -> void:
		_pulse += delta
		if is_visible_in_tree():
			queue_redraw()

	func zoom_by(f: float) -> void:
		view_scale = clampf(view_scale * f, 0.4, 2.0)
		queue_redraw()

	func reset_view() -> void:
		view_tx = 0.0
		view_ty = 0.0
		view_scale = 0.72
		queue_redraw()

	func _center() -> Vector2:
		return Vector2(size.x * 0.5 + view_tx * view_scale, size.y * 0.5 + view_ty * view_scale)

	func _radius(node_type: String) -> float:
		return float(RADII.get(node_type, 7.0))

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb != null:
			if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				zoom_by(1.12)
				accept_event()
				return
			if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				zoom_by(0.89)
				accept_event()
				return
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_dragging = true
					_drag_moved = false
					_drag_from = mb.position
					_drag_tx = view_tx
					_drag_ty = view_ty
				else:
					if _dragging and not _drag_moved:
						var hit := _hit(mb.position)
						if hit >= 0:
							node_clicked.emit(hit)
					_dragging = false
				accept_event()
			return
		var mm := event as InputEventMouseMotion
		if mm != null:
			if _dragging:
				var d := mm.position - _drag_from
				if absf(d.x) + absf(d.y) > 3.0:
					_drag_moved = true
				view_tx = _drag_tx + d.x / view_scale
				view_ty = _drag_ty + d.y / view_scale
				queue_redraw()
			else:
				var h := _hit(mm.position)
				if h != _hover_id:
					_hover_id = h
					mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h >= 0 else Control.CURSOR_ARROW
				hover_changed.emit(_hover_id, mm.position)

	func _hit(at: Vector2) -> int:
		var c := _center()
		for n in nodes:
			var p := c + Vector2(float(n["x"]), float(n["y"])) * view_scale
			var rr := (_radius(String(n["type"])) + 4.0) * view_scale
			if at.distance_squared_to(p) <= rr * rr:
				return int(n["id"])
		return -1

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w <= 0.0 or h <= 0.0:
			return
		# Dark radial backdrop (#161109 → #0a0807) + faint 40px grid + ember glow.
		draw_rect(Rect2(Vector2.ZERO, size), Color("0a0807"))
		var rad_c := Vector2(w * 0.5, h * 0.45)
		var max_r := maxf(w, h) * 0.7
		var steps := 16
		for i in steps:
			var t := float(i) / float(steps)
			draw_circle(rad_c, max_r * (1.0 - t * 0.95), Color("0a0807").lerp(Color("161109"), t))
		var grid_col := Color(0.47, 0.408, 0.282, 0.04)
		var gx := 0.0
		while gx < w:
			draw_line(Vector2(gx, 0), Vector2(gx, h), grid_col, 1.0)
			gx += 40.0
		var gy := 0.0
		while gy < h:
			draw_line(Vector2(0, gy), Vector2(w, gy), grid_col, 1.0)
			gy += 40.0
		for i in 4:
			draw_circle(Vector2(w * 0.5, h * 0.5), minf(w, h) * 0.45 * (1.0 - float(i) * 0.22), Color(0.91, 0.518, 0.227, 0.025))

		var on_set := {}
		for tid in GameState.talents_allocated:
			on_set[int(tid)] = true
		var c := _center()

		# Edges: lit = arm color w/ glow underlay; else faint iron.
		for e in edges:
			var na: Dictionary = nodes[int(e[0])]
			var nb: Dictionary = nodes[int(e[1])]
			var pa := c + Vector2(float(na["x"]), float(na["y"])) * view_scale
			var pb := c + Vector2(float(nb["x"]), float(nb["y"])) * view_scale
			if (maxf(pa.x, pb.x) < -60.0 or maxf(pa.y, pb.y) < -60.0
					or minf(pa.x, pb.x) > w + 60.0 or minf(pa.y, pb.y) > h + 60.0):
				continue
			if on_set.has(int(na["id"])) and on_set.has(int(nb["id"])):
				var ai := int(nb["ai"]) if int(nb["ai"]) >= 0 else int(na["ai"])
				var col: Color = GameContent.ARMS[ai]["color"] if ai >= 0 else Palette.EMBER
				draw_line(pa, pb, Palette.with_alpha(col, 0.18), 7.0 * view_scale, true)
				draw_line(pa, pb, Palette.with_alpha(col, 0.9), 3.0 * view_scale, true)
			else:
				draw_line(pa, pb, Color(0.227, 0.204, 0.157, 0.5), 1.6 * view_scale, true)

		# Nodes by type.
		var pulse_a := 0.15 + 0.45 * (0.5 + 0.5 * sin(TAU * _pulse / 1.6))
		for n in nodes:
			var nid := int(n["id"])
			var p := c + Vector2(float(n["x"]), float(n["y"])) * view_scale
			if p.x < -60.0 or p.y < -60.0 or p.x > w + 60.0 or p.y > h + 60.0:
				continue
			var node_type := String(n["type"])
			var r := _radius(node_type)
			var ai := int(n["ai"])
			var col: Color = GameContent.ARMS[ai]["color"] if ai >= 0 else Color("e8843a")
			var lit: bool = on_set.has(nid)
			var able := false
			if not lit:
				for nb_id in adj.get(nid, []):
					if on_set.has(int(nb_id)):
						able = true
						break
			if lit:
				draw_circle(p, (r + 9.0) * view_scale, Palette.with_alpha(col, 0.10 * Palette.GLOW))
				draw_circle(p, (r + 4.0) * view_scale, Palette.with_alpha(col, 0.18 * Palette.GLOW))
			match node_type:
				"start", "keystone":
					var d := r * sqrt(2.0) * view_scale
					var pts := PackedVector2Array([
						p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0)])
					draw_colored_polygon(pts, col if lit else Color("15120d"))
					var closed := pts.duplicate()
					closed.append(pts[0])
					draw_polyline(closed, col if (lit or able) else Color("4a4234"), 2.0 * view_scale, true)
				"notable":
					draw_circle(p, r * view_scale, col if lit else Color("15120d"))
					draw_arc(p, r * view_scale, 0.0, TAU, 36, col if (lit or able) else Color("4a4234"), 2.2 * view_scale, true)
				_:
					draw_circle(p, r * view_scale, col if lit else Color("191510"))
					draw_arc(p, r * view_scale, 0.0, TAU, 28, col if (lit or able) else Color("3e382c"), 1.6 * view_scale, true)
			if able and not lit:
				draw_arc(p, (r + 4.0) * view_scale, 0.0, TAU, 36, Palette.with_alpha(col, pulse_a), maxf(1.0 * view_scale, 0.75), true)


## Glowing legend dot (.tl-dot).
class LegendDot:
	extends Control

	var dot_size := 9.0
	var dot_color := Color.WHITE

	func _init(p_size: float = 9.0, p_color: Color = Color.WHITE) -> void:
		dot_size = p_size
		dot_color = p_color
		custom_minimum_size = Vector2(dot_size, dot_size)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		draw_circle(c, dot_size * 0.5 + 3.0, Palette.with_alpha(dot_color, 0.25 * Palette.GLOW))
		draw_circle(c, dot_size * 0.5, dot_color)
