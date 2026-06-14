extends Control
## CAMP hub screen (camp.jsx CampScreen) — lives in its own OS window.
##
## Torchlit Hollowreach Camp: night-sky radial, twinkling stars, horizon ruin
## silhouettes, ground plane with column striping, central campfire with
## trodden-path glows, drifting embers, four clickable buildings (hover lift +
## ember glow, nameplates, hotkey chips), the Town Crier ribbon, and the four
## building modals (Summoning Altar / Notice Board / Crafting House /
## Hearthfire Kitchen). Q/E/R/F open buildings; Esc inside a modal closes the
## modal (consumed), Esc with no modal falls through so the window shell
## closes the Camp window.

const _FX := preload("res://scenes/camp/CampFx.gd")
const _GachaModalScript := preload("res://scenes/camp/GachaModal.gd")
const _BoardModalScript := preload("res://scenes/camp/BoardModal.gd")
const _ForgeModalScript := preload("res://scenes/camp/ForgeModal.gd")
const _KitchenModalScript := preload("res://scenes/camp/KitchenModal.gd")

const W := 1920.0
const H := 1080.0
const FIRE_CENTER := Vector2(0.57 * W, 0.60 * H)  # campfire anchor (57%, 60%)

var _modal: Control = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build_backdrop()
	_build_campfire()
	_build_title()
	for b: Dictionary in GameContent.BUILDINGS:
		add_child(_make_building(b))
	add_child(_build_crier())


## Building hotkeys (Q/E/R/F). Only when no modal is open — open modals grab
## their own keys at the _input stage. Esc is deliberately NOT consumed here.
func _unhandled_key_input(event: InputEvent) -> void:
	if _modal != null:
		return
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_Q:
			_open("altar")
			get_viewport().set_input_as_handled()
		KEY_E:
			_open("board")
			get_viewport().set_input_as_handled()
		KEY_R:
			_open("forge")
			get_viewport().set_input_as_handled()
		KEY_F:
			_open("food")
			get_viewport().set_input_as_handled()


func _open(id: String) -> void:
	if _modal != null:
		return
	var m: Control = null
	match id:
		"altar":
			m = _GachaModalScript.new()
		"board":
			m = _BoardModalScript.new()
		"forge":
			m = _ForgeModalScript.new()
		"food":
			m = _KitchenModalScript.new()
	if m == null:
		return
	add_child(m)
	m.closed.connect(func() -> void: _modal = null)
	_modal = m


# =========================================================================
# Scene backdrop (sky → stars → ruins → ground → walks → embers)
# =========================================================================

func _build_backdrop() -> void:
	var sky := _Sky.new()
	sky.position = Vector2.ZERO
	sky.size = Vector2(W, H * 0.62)
	add_child(sky)

	var stars := _Stars.new()
	stars.position = Vector2.ZERO
	stars.size = Vector2(W, H * 0.40)
	add_child(stars)

	var ruins := _Ruins.new()
	ruins.position = Vector2.ZERO
	ruins.size = Vector2(W, H * 0.575)
	add_child(ruins)

	var ground := _Ground.new()
	ground.position = Vector2(0.0, H * 0.56)
	ground.size = Vector2(W, H * 0.44)
	add_child(ground)

	var walks := _Walks.new()
	walks.position = Vector2.ZERO
	walks.size = Vector2(W, H)
	walks.origin = FIRE_CENTER
	add_child(walks)

	var embers := _Embers.new()
	embers.position = Vector2.ZERO
	embers.size = Vector2(W, H)
	add_child(embers)


# =========================================================================
# Campfire (.campfire) + title (.camp-title)
# =========================================================================

func _build_campfire() -> void:
	# Big pulsing warm glow (360×200 at 50%/64% of the campfire box).
	var glow := _FX.Glow.new(
		[[0.0, Palette.with_alpha(Palette.EMBER, 0.30)],
		 [0.48, Palette.with_alpha(Palette.EMBER, 0.08)],
		 [0.70, Palette.with_alpha(Palette.EMBER, 0.0)]],
		3.0, 0.5, 1.0)
	glow.position = FIRE_CENTER + Vector2(-180.0, -60.0 + 76.8 - 100.0)
	glow.size = Vector2(360, 200)
	add_child(glow)

	# Sprite hotspot (150×120 centered on the anchor).
	var fire := Control.new()
	fire.position = FIRE_CENTER - Vector2(75.0, 60.0)
	fire.size = Vector2(150, 120)
	fire.mouse_filter = Control.MOUSE_FILTER_STOP
	fire.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var ps := PixelSlot.new("150×120\ncampfire", true)
	fire.add_child(ps)
	ps.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Tip.attach(fire, {
		"name": "Hollow Hearth",
		"type": "Camp centerpiece",
		"rarity": "legendary",
		"stats": [["Rested bonus", "+5% XP"]],
		"flavor": "The fire that holds the dark at bay. Heroes gather here between delves.",
	})
	add_child(fire)

	# Bright flame core (70×56 at 50%/30% of the campfire box).
	var light := _FX.Glow.new(
		[[0.0, Color(1.0, 190.0 / 255.0, 120.0 / 255.0, 0.5)],
		 [0.70, Color(1.0, 190.0 / 255.0, 120.0 / 255.0, 0.0)]],
		2.1, 0.5, 1.0)
	light.position = FIRE_CENTER + Vector2(-35.0, -60.0 + 36.0 - 28.0)
	light.size = Vector2(70, 56)
	add_child(light)


func _build_title() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(28, 84)
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := Style.display_label("Hollowreach Camp", 40, Palette.GOLD_BRIGHT, true)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 3)
	title.add_theme_constant_override("shadow_outline_size", 8)
	box.add_child(title)
	box.add_child(Style.body_label("Camp Level 8 · 4 buildings · 2 expansions locked", 13, Palette.TX_MUTE))
	add_child(box)


# =========================================================================
# Buildings (.bld)
# =========================================================================

func _make_building(b: Dictionary) -> Control:
	var w := float(b["w"])
	var h := float(b["h"])
	var featured := bool(b["featured"])
	var id := String(b["id"])
	var hot := String(b["hot"])

	var root := Control.new()
	root.size = Vector2(w, h + 78.0)
	root.position = Vector2(float(b["x"]) / 100.0 * W - w * 0.5, float(b["y"]) / 100.0 * H - h * 0.5)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var base_y := root.position.y

	# Sprite — real building art from buildings.camp when present (id "food"
	# maps to the kitchen key), placeholder otherwise.
	var sprite := PixelSlot.new(String(b["sprite"]), true, "buildings.camp", "kitchen" if id == "food" else id)
	sprite.position = Vector2.ZERO
	sprite.size = Vector2(w, h)
	root.add_child(sprite)

	# Featured altar: extra pulsing glow over the sprite.
	if featured:
		var fglow := _FX.Glow.new(
			[[0.0, Palette.with_alpha(Palette.EMBER, 0.55)], [0.68, Palette.with_alpha(Palette.EMBER, 0.0)]],
			3.4, 0.5, 1.0)
		fglow.size = Vector2(w * 0.6, h * 0.5)
		fglow.position = Vector2(w * 0.5 - fglow.size.x * 0.5, h * 0.58 - fglow.size.y * 0.5)
		root.add_child(fglow)
		# Tutorial finale (step 14) spotlights the featured Summoning Altar.
		TutorialOverlay.register_anchor("camp.altar", root)

	# Sprite border (hover → ember glow).
	var border := Panel.new()
	border.position = Vector2.ZERO
	border.size = Vector2(w, h)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box_normal := _bld_border_box(featured, false)
	var box_hover := _bld_border_box(featured, true)
	border.add_theme_stylebox_override("panel", box_normal)
	root.add_child(border)

	# Badge chip (top-right) when present.
	if String(b["badge"]) != "":
		var badge := PanelContainer.new()
		var bsb := StyleBoxFlat.new()
		bsb.bg_color = Palette.EMBER
		bsb.set_border_width_all(1)
		bsb.border_color = Color("3a1d08")
		bsb.set_corner_radius_all(2)
		bsb.content_margin_left = 6
		bsb.content_margin_right = 6
		bsb.content_margin_top = 4
		bsb.content_margin_bottom = 3
		bsb.shadow_color = Palette.with_alpha(Palette.EMBER, 0.6 * Palette.GLOW)
		bsb.shadow_size = int(12 * Palette.GLOW)
		badge.add_theme_stylebox_override("panel", bsb)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_child(Style.pixel_label(String(b["badge"]), 8, Color("1c0f04")))
		root.add_child(badge)
		badge.resized.connect(func() -> void:
			badge.position = Vector2(w - badge.size.x + 6.0, -8.0))

	# Nameplate (overlaps the sprite by 16px).
	var plate := PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color("191510")
	psb.set_border_width_all(1)
	psb.border_color = Palette.IRON_EDGE
	psb.set_corner_radius_all(4)
	psb.content_margin_left = 16
	psb.content_margin_right = 16
	psb.content_margin_top = 9
	psb.content_margin_bottom = 8
	psb.shadow_color = Color(0, 0, 0, 0.6)
	psb.shadow_size = 8
	psb.shadow_offset = Vector2(0, 6)
	plate.add_theme_stylebox_override("panel", psb)
	plate.custom_minimum_size = Vector2(150, 0)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.position = Vector2(0.0, h - 16.0)
	var pcol := VBoxContainer.new()
	pcol.add_theme_constant_override("separation", 2)
	pcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(pcol)
	var nm := Style.display_label(String(b["name"]), 17, Palette.GOLD_BRIGHT, true)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pcol.add_child(nm)
	var sub := Style.body_label(String(b["sub"]), 10, Palette.TX_MUTE)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pcol.add_child(sub)
	var enter_row := HBoxContainer.new()
	enter_row.add_theme_constant_override("separation", 6)
	enter_row.alignment = BoxContainer.ALIGNMENT_CENTER
	enter_row.visible = false
	enter_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var enter_pad := MarginContainer.new()
	enter_pad.add_theme_constant_override("margin_top", 4)
	enter_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	enter_pad.visible = false
	enter_pad.add_child(enter_row)
	enter_row.add_child(Style.make_keycap(hot))
	var enter_lbl := Style.body_label("ENTER", 10, Palette.EMBER)
	enter_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	enter_row.add_child(enter_lbl)
	pcol.add_child(enter_pad)
	root.add_child(plate)
	plate.resized.connect(func() -> void:
		plate.position.x = (w - plate.size.x) * 0.5)

	# Hover: lift 6px, ember border, reveal ENTER row, raise z.
	root.mouse_entered.connect(func() -> void:
		border.add_theme_stylebox_override("panel", box_hover)
		enter_pad.visible = true
		enter_row.visible = true
		root.z_index = 1
		_lift(root, base_y - 6.0))
	root.mouse_exited.connect(func() -> void:
		border.add_theme_stylebox_override("panel", box_normal)
		enter_pad.visible = false
		enter_row.visible = false
		root.z_index = 0
		_lift(root, base_y))

	Tip.attach(root, {
		"name": String(b["name"]),
		"type": String(b["tip_type"]),
		"rarity": "legendary" if featured else "rare",
		"flavor": String(b["flavor"]),
	})
	root.gui_input.connect(func(ev: InputEvent) -> void:
		var mb := ev as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_open(id))
	return root


func _bld_border_box(featured: bool, hover: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(5)
	if hover:
		sb.border_color = Palette.EMBER_DEEP
		sb.shadow_color = Palette.with_alpha(Palette.EMBER, 0.35 * Palette.GLOW)
		sb.shadow_size = int(24 * Palette.GLOW)
	elif featured:
		sb.border_color = Palette.GOLD_DIM
	else:
		sb.border_color = Color(150.0 / 255.0, 130.0 / 255.0, 90.0 / 255.0, 0.28)
	return sb


func _lift(node: Control, to_y: float) -> void:
	if node.has_meta("lift_tween"):
		var prev: Tween = node.get_meta("lift_tween")
		if prev != null and prev.is_valid():
			prev.kill()
	var tw := create_tween()
	tw.tween_property(node, "position:y", to_y, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	node.set_meta("lift_tween", tw)


# =========================================================================
# Town Crier (.camp-events)
# =========================================================================

func _build_crier() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Style.panel_box())
	panel.custom_minimum_size = Vector2(320, 0)
	panel.resized.connect(func() -> void:
		panel.position = Vector2(W - 16.0 - panel.size.x, H - 18.0 - panel.size.y))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	panel.add_child(col)

	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", Style.head_box())
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 10)
	head.add_child(head_row)
	var ico := Style.body_label("◆", 12, Palette.EMBER)
	ico.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head_row.add_child(ico)
	head_row.add_child(Style.display_label("TOWN CRIER", 12, Palette.GOLD))
	col.add_child(head)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 8)
	pad.add_theme_constant_override("margin_bottom", 12)
	col.add_child(pad)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	pad.add_child(list)
	for e: Dictionary in GameContent.CRIER:
		list.add_child(_crier_row(e))

	var rivets := _FX.Rivets.new()
	panel.add_child(rivets)
	return panel


func _crier_row(e: Dictionary) -> Control:
	var lit := bool(e["lit"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var dot := _FX.Dot.new(7.0, Palette.CYAN if lit else Palette.TX_FAINT, lit)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	var text := HBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.add_child(Style.body_label(String(e["text"]), 12, Palette.TX_DIM))
	var b_color := Palette.EMBER_BRIGHT if bool(e.get("b_ember", false)) else Palette.TX
	text.add_child(Style.body_label(String(e["b"]), 12, b_color))
	if String(e["suffix"]) != "":
		text.add_child(Style.body_label(String(e["suffix"]), 12, Palette.TX_DIM))
	row.add_child(text)
	return row


# =========================================================================
# Backdrop layers (draw-driven, decorative — all MOUSE_FILTER_IGNORE)
# =========================================================================

## Night sky: radial from warm horizon-brown at top-center to near-black.
class _Sky:
	extends Control

	const _CFX := preload("res://scenes/camp/CampFx.gd")

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("0a0807"))
		_CFX.radial(self, Vector2(size.x * 0.5, 0.0), Vector2(size.x * 0.8, size.y * 1.2),
			[[0.0, Color("2a1d12")], [0.45, Color("140f0a")], [1.0, Color("0a0807")]])


## 18 twinkling 2px stars in the top 40% band (y within its top 80%).
class _Stars:
	extends Control

	var _stars: Array = []
	var _t: float = 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		for i in 18:
			_stars.append({
				"x": rng.randf(),
				"y": rng.randf() * 0.8,
				"dur": 2.4 + rng.randf() * 3.6,
				"phase": rng.randf() * 6.0,
			})

	func _process(delta: float) -> void:
		_t += delta
		if is_visible_in_tree():
			queue_redraw()

	func _draw() -> void:
		for s: Dictionary in _stars:
			var f := 0.5 - 0.5 * cos(TAU * (_t + float(s["phase"])) / float(s["dur"]))
			var a := lerpf(0.18, 0.65, f)
			draw_rect(
				Rect2(float(s["x"]) * size.x, float(s["y"]) * size.y, 2.0, 2.0),
				Color(207.0 / 255.0, 195.0 / 255.0, 164.0 / 255.0, a))


## Horizon ruin silhouettes, bottom-aligned to the 57.5% line.
class _Ruins:
	extends Control

	const _CFX := preload("res://scenes/camp/CampFx.gd")

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		for r: Dictionary in GameContent.RUINS:
			var w := float(r["w"])
			var h := float(r["h"])
			var x := float(r["l"]) / 100.0 * size.x
			var rect := Rect2(x, size.y - h, w, h)
			_CFX.vgrad(self, rect,
				Color(14.0 / 255.0, 12.0 / 255.0, 9.0 / 255.0, 0.9),
				Color(10.0 / 255.0, 8.0 / 255.0, 7.0 / 255.0, 0.9))
			draw_rect(Rect2(rect.position, Vector2(w, 1.0)),
				Color(120.0 / 255.0, 104.0 / 255.0, 72.0 / 255.0, 0.072))


## Ground plane: warm radial at top-center over a dark vertical gradient,
## top inner shadow, and faint 64px column striping fading in from the top.
class _Ground:
	extends Control

	const _CFX := preload("res://scenes/camp/CampFx.gd")

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		_CFX.vgrad(self, Rect2(Vector2.ZERO, size), Color("1a1610"), Color("0c0a08"))
		_CFX.radial(self, Vector2(size.x * 0.5, 0.0), Vector2(size.x * 0.6, size.y * 0.8),
			[[0.0, Palette.with_alpha(Palette.EMBER, 0.10)], [0.7, Palette.with_alpha(Palette.EMBER, 0.0)]])
		# Inset top shadow.
		_CFX.vgrad(self, Rect2(0.0, 0.0, size.x, 70.0), Color(0, 0, 0, 0.5), Color(0, 0, 0, 0.0))
		# 64px column striping, masked so it fades in over the first 40%.
		var mask_end := size.y * 0.4
		var a := 0.25 * 0.4
		var x := 0.0
		while x < size.x:
			draw_polygon(
				PackedVector2Array([
					Vector2(x, 0.0), Vector2(x + 2.0, 0.0),
					Vector2(x + 2.0, mask_end), Vector2(x, mask_end),
				]),
				PackedColorArray([
					Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0),
					Color(0, 0, 0, a), Color(0, 0, 0, a),
				]))
			draw_rect(Rect2(x, mask_end, 2.0, size.y - mask_end), Color(0, 0, 0, a))
			x += 64.0


## Trodden-path glows radiating from the campfire (.camp-walk).
class _Walks:
	extends Control

	var origin := Vector2.ZERO

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		for wlk: Dictionary in GameContent.WALKS:
			var length := float(wlk["len"])
			var rot := deg_to_rad(float(wlk["rot"]))
			draw_set_transform(origin, rot, Vector2.ONE)
			# Two stacked ellipses approximate the 9px blur.
			_walk_ellipse(length, 21.0, 0.5)
			_walk_ellipse(length, 15.0, 0.85)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _walk_ellipse(length: float, ry: float, mult: float) -> void:
		const N := 40
		var hl := length * 0.5
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		for i in N:
			var ang := TAU * float(i) / float(N)
			var px := hl + cos(ang) * hl
			pts.append(Vector2(px, sin(ang) * ry))
			cols.append(Color(150.0 / 255.0, 130.0 / 255.0, 90.0 / 255.0, _alpha_at(px / length) * mult))
		draw_polygon(pts, cols)

	func _alpha_at(f: float) -> float:
		if f < 0.7:
			return lerpf(0.16, 0.05, f / 0.7)
		return lerpf(0.05, 0.0, (f - 0.7) / 0.3)


## 22 drifting embers rising bottom → top over 6–16s with ±40px drift.
class _Embers:
	extends Control

	var _embers: Array = []
	var _t: float = 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		for i in 22:
			_embers.append({
				"x": rng.randf(),
				"drift": (rng.randf() * 2.0 - 1.0) * 40.0,
				"size": 1.0 + rng.randf() * 2.4,
				"dur": 6.0 + rng.randf() * 10.0,
				"delay": rng.randf() * 12.0,
			})

	func _process(delta: float) -> void:
		_t += delta
		if is_visible_in_tree():
			queue_redraw()

	func _draw() -> void:
		for e: Dictionary in _embers:
			var ph := fposmod((_t + float(e["delay"])) / float(e["dur"]), 1.0)
			var a: float
			if ph < 0.1:
				a = lerpf(0.0, 0.9, ph / 0.1)
			elif ph < 0.9:
				a = lerpf(0.9, 0.7, (ph - 0.1) / 0.8)
			else:
				a = lerpf(0.7, 0.0, (ph - 0.9) / 0.1)
			var s := float(e["size"])
			var pos := Vector2(
				float(e["x"]) * size.x + float(e["drift"]) * ph,
				size.y + 10.0 - ph * 1080.0)
			draw_circle(pos, s * 2.4, Palette.with_alpha(Palette.EMBER, a * 0.18 * Palette.GLOW))
			draw_circle(pos, maxf(s * 0.7, 0.8), Palette.with_alpha(Palette.EMBER_BRIGHT, a))
