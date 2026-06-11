extends Control
## FIGHT battlefield — pure presentation of the roaming advance (fight.jsx
## ".battle"): iso floor, travel trail, path-ahead cue, environment props,
## edge spawn markers, enemies/heroes with depth + motion, floating combat
## numbers and the ADVANCING / INCOMING directional labels.
##
## All world positions are percentages of this control's rect (re-laid out on
## resize). Combat truth lives in CombatSim; floaters arrive via EventBus.

const _HERO_SIZE := Vector2(76, 104)
const _ENEMY_SIZE := Vector2(62, 82)
const _ELITE_SIZE := Vector2(92, 116)
const _MAX_FLOATERS := 15

var _t: float = 0.0
var _layouts: Array[Callable] = []
var _bobs: Array[Dictionary] = []
var _pulses: Array[Dictionary] = []
var _floater_holder: Control
var _relayout_pending: bool = false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_rng.seed = 0xF17E5
	_build()
	resized.connect(_request_relayout)
	EventBus.sim_floater.connect(_on_floater)
	_request_relayout()


## One clock drives every looping motion: stride/lunge/approach bobs on unit
## sprites plus all opacity pulses (chevrons, spawn arrows, labels, flame).
func _process(delta: float) -> void:
	_t += delta
	for b in _bobs:
		var n := b["node"] as Control
		var wv := 0.5 - 0.5 * cos(TAU * (_t - float(b["delay"])) / float(b["period"]))
		match String(b["kind"]):
			"stride":
				n.position = (b["base"] as Vector2) + Vector2(0.0, -5.0 * wv)
				n.rotation_degrees = lerpf(-1.6, 1.6, wv)
			"lunge":
				n.position = (b["base"] as Vector2) + Vector2(-5.0 * wv, 4.0 * wv)
			_:
				n.position = (b["base"] as Vector2) + Vector2(0.0, -3.0 * wv)
	for p in _pulses:
		var wv2 := 0.5 - 0.5 * cos(TAU * (_t - float(p["delay"])) / float(p["period"]))
		var ci := p["node"] as CanvasItem
		var m := ci.modulate
		m.a = lerpf(float(p["min"]), float(p["max"]), wv2)
		ci.modulate = m


# =========================================================================
# Build
# =========================================================================

func _build() -> void:
	add_child(_IsoFloor.new())
	add_child(_IsoFog.new())

	# ---- travel trail (where the party came from, bottom-left) ----
	var smear := _Blob.new(Color(120.0 / 255.0, 104.0 / 255.0, 72.0 / 255.0, 0.12))
	smear.size = Vector2(420, 240)
	add_child(smear)
	_place_center(smear, 20.0, 74.0)

	for i in GameContent.TRAIL.size():
		var tr: Dictionary = GameContent.TRAIL[i]
		var step := _Footstep.new()
		step.size = Vector2(18, 7)
		step.rotation_degrees = -35.0
		if i % 2 == 1:
			step.scale = Vector2(-1, 1)
		step.modulate = Color(1, 1, 1, float(tr["o"]))
		add_child(step)
		_place_center(step, float(tr["x"]), float(tr["y"]))

	# ---- path ahead: ember beam + pulsing chevrons toward the top-right ----
	var beam := _Beam.new()
	beam.size = Vector2(520, 46)
	beam.pivot_offset = Vector2(0, 23)
	beam.rotation_degrees = -41.0
	add_child(beam)
	_layouts.append(func(bs: Vector2) -> void:
		beam.position = Vector2(bs.x * 0.30 - 520.0 * 0.12, bs.y * 0.52 - 23.0))

	for i in GameContent.AHEAD.size():
		var c: Dictionary = GameContent.AHEAD[i]
		var ch := Style.body_label("❯", 26, Palette.EMBER_BRIGHT)
		ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ch.rotation_degrees = -41.0
		ch.add_theme_constant_override("outline_size", 8)
		ch.add_theme_color_override("font_outline_color", Palette.with_alpha(Palette.EMBER, 0.3 * Palette.GLOW))
		add_child(ch)
		_place_center(ch, float(c["x"]), float(c["y"]), true)
		_pulses.append({"node": ch, "period": 1.5, "delay": float(i) * 0.18, "min": 0.12, "max": 0.9})

	# ---- props + enemies + heroes, painter-sorted by depth (zIndex = y) ----
	var entries: Array = []
	for p: Dictionary in GameContent.PROPS:
		entries.append([roundi(float(p["y"])), _make_prop(p)])
	for e: Dictionary in GameContent.ENEMIES:
		entries.append([roundi(float(e["y"])), _make_enemy(e)])
	for i in GameContent.PARTY.size():
		entries.append([roundi(float(GameContent.PARTY[i]["y"])) + 12, _make_hero(GameContent.PARTY[i], i)])
	entries.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	for en: Array in entries:
		add_child(en[1])

	# ---- "ADVANCING ↗" at the party, rotated with the travel direction ----
	var adv := HBoxContainer.new()
	adv.add_theme_constant_override("separation", 7)
	adv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var adv_c := Palette.with_alpha(Palette.EMBER, 0.62)
	adv.add_child(Style.pixel_label("ADVANCING", 11, adv_c))
	adv.add_child(Style.pixel_label("↗", 15, adv_c))
	adv.rotation_degrees = -8.0
	add_child(adv)
	_place_center(adv, 30.0, 80.0, true)
	_pulses.append({"node": adv, "period": 2.4, "delay": 0.0, "min": 0.4, "max": 0.9})

	# ---- edge spawn markers (incoming foes), concentrated top-right ----
	for s: Dictionary in GameContent.SPAWNS:
		var marker := _make_spawn(s)
		add_child(marker)
		_place_center(marker, float(s["x"]), float(s["y"]))

	# ---- "✦ INCOMING" over the hottest spawn cluster ----
	var danger := HBoxContainer.new()
	danger.add_theme_constant_override("separation", 7)
	danger.mouse_filter = Control.MOUSE_FILTER_IGNORE
	danger.add_child(Style.pixel_label("✦", 13, Palette.EMBER_BRIGHT))
	danger.add_child(Style.pixel_label("INCOMING", 11, Palette.EMBER_HOT))
	add_child(danger)
	_place_center(danger, 71.0, 13.0, true)
	_pulses.append({"node": danger, "period": 1.5, "delay": 0.0, "min": 0.4, "max": 0.9})

	# ---- floating combat numbers live above everything in the battle ----
	_floater_holder = Control.new()
	_floater_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_floater_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_floater_holder)


# =========================================================================
# Unit factories
# =========================================================================

## Environment prop: pixel-slot sprite + elliptical ground shadow; the
## brazier adds an ember border and a flickering flame glow.
func _make_prop(p: Dictionary) -> Control:
	var w := float(p["w"])
	var h := float(p["h"])
	var unit := Control.new()
	unit.size = Vector2(w, h)
	unit.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var shadow := _Shadow.new(0.6)
	shadow.size = Vector2(w * 0.7, 13)
	shadow.position = Vector2(w * 0.5 - shadow.size.x * 0.5, h + 5.0 - 13.0)
	unit.add_child(shadow)

	var sprite := PixelSlot.new(String(p["label"]), false)
	sprite.size = Vector2(w, h)
	sprite.modulate = Color(1, 1, 1, 0.92)
	unit.add_child(sprite)

	if String(p["kind"]) == "brazier":
		var border := Panel.new()
		var bsb := StyleBoxFlat.new()
		bsb.draw_center = false
		bsb.set_border_width_all(1)
		bsb.border_color = Palette.EMBER_DEEP
		bsb.set_corner_radius_all(3)
		bsb.shadow_color = Palette.with_alpha(Palette.EMBER, 0.35 * Palette.GLOW)
		bsb.shadow_size = int(20 * Palette.GLOW)
		border.add_theme_stylebox_override("panel", bsb)
		border.size = Vector2(w, h)
		border.mouse_filter = Control.MOUSE_FILTER_IGNORE
		unit.add_child(border)

		var flame := _Flame.new()
		flame.size = Vector2(w * 0.6, h * 0.36)
		flame.position = Vector2(w * 0.5 - flame.size.x * 0.5, -6.0)
		unit.add_child(flame)
		_pulses.append({"node": flame, "period": 1.8, "delay": 0.0, "min": 0.5, "max": 1.0})

	_place_bottom(unit, float(p["x"]), float(p["y"]))
	return unit


## Enemy: depth scale/fade, hp bar overhead, elite epic glow, lunge streak +
## lunge/approach motion, ground shadow, hover tooltip.
func _make_enemy(e: Dictionary) -> Control:
	var elite := bool(e.get("elite", false))
	var dist := String(e["dist"])
	var lunge := bool(e.get("lunge", false))
	var usz := _ELITE_SIZE if elite else _ENEMY_SIZE
	var d: Dictionary = GameContent.DIST.get(dist, GameContent.DIST["mid"])

	var unit := Control.new()
	unit.size = usz
	unit.pivot_offset = Vector2(usz.x * 0.5, usz.y)  # scale from the feet
	unit.scale = Vector2(float(d["us"]), float(d["us"]))
	unit.modulate = Color(1, 1, 1, float(d["uo"]))
	unit.mouse_filter = Control.MOUSE_FILTER_STOP
	unit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var type_line := "Stage 4-7"
	if dist == "far":
		type_line = "Approaching · Stage 4-7"
	elif elite:
		type_line = "Elite · Stage 4-7"
	var range_lbl := "Engaged" if dist == "near" else ("Closing" if dist == "mid" else "Distant")
	Tip.attach(unit, {
		"name": String(e["name"]),
		"type": type_line,
		"rarity": "epic" if elite else "common",
		"stats": [["HP", "240,000" if elite else "84,000"], ["Range", range_lbl]],
	})

	if lunge:
		var streak := _Streak.new()
		streak.size = Vector2(68, 16)
		streak.pivot_offset = Vector2(0, 8)
		streak.rotation_degrees = float(e.get("trail_rot", 25.0))
		streak.position = Vector2(usz.x * 0.5 - 68.0 * 0.12, usz.y * 0.42 - 8.0)
		unit.add_child(streak)

	var shadow := _Shadow.new(0.65)
	shadow.size = Vector2(84.0 if elite else 56.0, 16)
	shadow.position = Vector2(usz.x * 0.5 - shadow.size.x * 0.5, usz.y - 10.0)
	unit.add_child(shadow)

	var sprite := PixelSlot.new("96×112\nelite" if elite else "64×80\nfoe", true)
	sprite.size = usz
	unit.add_child(sprite)
	if lunge:
		_bobs.append({"node": sprite, "base": Vector2.ZERO, "kind": "lunge", "period": 0.7, "delay": 0.0})
	elif dist != "near":
		_bobs.append({"node": sprite, "base": Vector2.ZERO, "kind": "approach", "period": 1.9, "delay": 0.0})

	if elite:
		var glow := Panel.new()
		var gsb := StyleBoxFlat.new()
		gsb.draw_center = false
		gsb.set_border_width_all(1)
		gsb.border_color = Palette.R_EPIC
		gsb.set_corner_radius_all(3)
		gsb.shadow_color = Palette.with_alpha(Palette.R_EPIC, 0.4 * Palette.GLOW)
		gsb.shadow_size = int(20 * Palette.GLOW)
		glow.add_theme_stylebox_override("panel", gsb)
		glow.size = usz
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		unit.add_child(glow)

	var bar := StatBar.new("hp", float(e["hp"]), 5.0)
	bar.size = Vector2(84.0 if elite else 54.0, 5.0)
	bar.position = Vector2(usz.x * 0.5 - bar.size.x * 0.5, -10.0)
	unit.add_child(bar)

	_place_bottom(unit, float(e["x"]), float(e["y"]))
	return unit


## Hero: role-colored ground ring, striding pixel-slot sprite, shadow, tip.
func _make_hero(h: Dictionary, idx: int) -> Control:
	var unit := Control.new()
	unit.size = _HERO_SIZE
	unit.mouse_filter = Control.MOUSE_FILTER_STOP
	unit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	Tip.attach(unit, {
		"name": String(h["name"]),
		"type": "%s · Lv %d" % [String(h["cls"]), int(h["lvl"])],
		"rarity": "legendary",
		"stats": [
			["Role", String(h["role_lbl"])],
			["HP", "%d / 184,000" % roundi(float(h["hp"]) * 1840.0)],
			["DPS", "%.1fM" % (1.2 + _rng.randf())],
		],
	})

	var ring := _Ring.new(Palette.role_color(String(h["role"])))
	ring.size = Vector2(70, 33)
	ring.position = Vector2(_HERO_SIZE.x * 0.5 - 35.0, _HERO_SIZE.y - 27.0 - 16.5)
	unit.add_child(ring)

	var shadow := _Shadow.new(0.65)
	shadow.size = Vector2(64, 16)
	shadow.position = Vector2(_HERO_SIZE.x * 0.5 - 32.0, _HERO_SIZE.y - 10.0)
	unit.add_child(shadow)

	var sprite := PixelSlot.new("64×96\n%s ↗" % String(h["name"]), true)
	sprite.size = _HERO_SIZE
	sprite.pivot_offset = _HERO_SIZE * 0.5
	unit.add_child(sprite)
	_bobs.append({"node": sprite, "base": Vector2.ZERO, "kind": "stride", "period": 0.62, "delay": float(idx) * 0.15})

	_place_bottom(unit, float(h["x"]), float(h["y"]))
	return unit


## Edge spawn marker: expanding ping ring + a "❯" arrow aimed at the party.
func _make_spawn(s: Dictionary) -> Control:
	var hot := bool(s.get("hot", false))
	var marker := Control.new()
	marker.size = Vector2(30, 30)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var ping := _Ping.new(hot)
	ping.size = Vector2(30, 30)
	marker.add_child(ping)

	var arrow := Style.body_label("❯", 22, Palette.EMBER_HOT if hot else Palette.EMBER_BRIGHT)
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow.add_theme_constant_override("outline_size", 8)
	var glow_c := Color("e0584a") if hot else Palette.EMBER
	arrow.add_theme_color_override("font_outline_color", Palette.with_alpha(glow_c, 0.35 * Palette.GLOW))
	arrow.position = Vector2(7, 2)
	arrow.rotation_degrees = float(s["a"])
	arrow.resized.connect(func() -> void: arrow.pivot_offset = arrow.size * 0.5)
	marker.add_child(arrow)
	_pulses.append({"node": arrow, "period": 1.3, "delay": 0.0, "min": 0.4, "max": 0.9})
	return marker


# =========================================================================
# Floating damage / heal numbers (EventBus.sim_floater)
# =========================================================================

func _on_floater(kind: String, amount: int, hero_idx: int) -> void:
	if _floater_holder == null or size.x < 4.0:
		return
	var bs := size
	var xp: float
	var yp: float
	if kind == "heal":
		var h: Dictionary = GameContent.PARTY[clampi(hero_idx, 0, GameContent.PARTY.size() - 1)]
		xp = float(h["x"]) + _rng.randf_range(-2.5, 2.5)
		yp = float(h["y"]) - 4.0 + _rng.randf_range(-2.0, 2.0)
	else:
		xp = float(GameContent.CLASH["x"]) + _rng.randf_range(-12.0, 12.0)
		yp = float(GameContent.CLASH["y"]) + _rng.randf_range(-11.0, 11.0)

	var text := ("+" + str(amount)) if kind == "heal" else Style.group_int(amount)
	var fsize := 26 if kind == "crit" else 16
	var col := Palette.DMG_CREAM
	if kind == "crit":
		col = Palette.EMBER_BRIGHT
	elif kind == "heal":
		col = Palette.HEAL_GREEN

	while _floater_holder.get_child_count() >= _MAX_FLOATERS:
		var old := _floater_holder.get_child(0)
		_floater_holder.remove_child(old)
		old.queue_free()

	var lbl := Style.pixel_label(text, fsize, col)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("shadow_offset_x", 0)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	if kind == "crit":
		lbl.add_theme_constant_override("outline_size", 10)
		lbl.add_theme_color_override("font_outline_color", Palette.with_alpha(Palette.EMBER, 0.4 * Palette.GLOW))
	_floater_holder.add_child(lbl)
	lbl.reset_size()
	lbl.pivot_offset = lbl.size * 0.5

	# float-up keyframes: pop in (0→18%), settle (→40%), rise + fade (→100%).
	var px := bs.x * xp / 100.0
	var py := bs.y * yp / 100.0
	lbl.position = Vector2(px - lbl.size.x * 0.5, py + 6.0)
	lbl.scale = Vector2(0.7, 0.7)
	lbl.modulate = Color(1, 1, 1, 0.0)
	var tw := lbl.create_tween()
	tw.tween_property(lbl, "position:y", py - 6.0, 0.198)
	tw.parallel().tween_property(lbl, "scale", Vector2(1.08, 1.08), 0.198)
	tw.parallel().tween_property(lbl, "modulate:a", 1.0, 0.198)
	tw.tween_property(lbl, "position:y", py - 16.0, 0.242)
	tw.parallel().tween_property(lbl, "scale", Vector2.ONE, 0.242)
	tw.tween_property(lbl, "position:y", py - 54.0, 0.66)
	tw.parallel().tween_property(lbl, "scale", Vector2(0.96, 0.96), 0.66)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.66)
	tw.tween_callback(lbl.queue_free)


# =========================================================================
# Percent-of-battlefield layout
# =========================================================================

## Anchor [param node]'s bottom-center at (x%, y%) — CSS translate(-50%,-100%).
func _place_bottom(node: Control, xp: float, yp: float) -> void:
	_layouts.append(func(bs: Vector2) -> void:
		node.position = Vector2(bs.x * xp / 100.0 - node.size.x * 0.5, bs.y * yp / 100.0 - node.size.y))


## Anchor [param node]'s center at (x%, y%) — CSS translate(-50%,-50%).
## [param autosize] nodes (labels/boxes) re-read their grown size each pass.
func _place_center(node: Control, xp: float, yp: float, autosize: bool = false) -> void:
	if autosize:
		node.resized.connect(_request_relayout)
	_layouts.append(func(bs: Vector2) -> void:
		node.pivot_offset = node.size * 0.5
		node.position = Vector2(bs.x * xp / 100.0, bs.y * yp / 100.0) - node.size * 0.5)


func _request_relayout() -> void:
	if _relayout_pending:
		return
	_relayout_pending = true
	call_deferred("_run_relayout")


func _run_relayout() -> void:
	_relayout_pending = false
	var bs := size
	for fn in _layouts:
		fn.call(bs)


# =========================================================================
# Draw-layer classes
# =========================================================================

## The iso dungeon floor: 150° charcoal gradient, warm hearth glow at the
## party, red danger glows top-right/right, and the 26.57° iso grid lines.
class _IsoFloor:
	extends Control

	const _GRID := Color(120.0 / 255.0, 104.0 / 255.0, 72.0 / 255.0, 0.10)

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w < 2.0 or h < 2.0:
			return
		draw_rect(Rect2(0, 0, w, h), Color("110d0a"))

		# linear-gradient(150deg, #20140d 0%, #120d0a 42%, #0a0807 100%)
		var dirv := Vector2(sin(deg_to_rad(150.0)), -cos(deg_to_rad(150.0)))
		var corners := PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)])
		var pmin := INF
		var pmax := -INF
		for c in corners:
			pmin = minf(pmin, c.dot(dirv))
			pmax = maxf(pmax, c.dot(dirv))
		var cols := PackedColorArray()
		for c in corners:
			cols.append(_grad((c.dot(dirv) - pmin) / (pmax - pmin)))
		draw_polygon(corners, cols)

		# Radial glows: hearth (party) + danger (top-right, right flank).
		_blob(Vector2(0.24 * w, 0.74 * h), 0.38 * w, 0.34 * h, Palette.with_alpha(Palette.EMBER, 0.20))
		_blob(Vector2(0.82 * w, 0.16 * h), 0.46 * w, 0.42 * h, Palette.with_alpha(Palette.HP, 0.16))
		_blob(Vector2(0.92 * w, 0.50 * h), 0.30 * w, 0.26 * h, Palette.with_alpha(Palette.HP, 0.10))

		# Iso grid: 1px lines at slope ±0.5 (26.57°), 58px gradient spacing.
		var spacing := 58.0 / cos(atan(0.5))
		var c1 := -0.5 * w
		while c1 < h:
			draw_line(Vector2(0, c1), Vector2(w, c1 + 0.5 * w), _GRID, 1.0)
			c1 += spacing
		var c2 := 0.0
		while c2 < h + 0.5 * w:
			draw_line(Vector2(0, c2), Vector2(w, c2 - 0.5 * w), _GRID, 1.0)
			c2 += spacing

	func _grad(t: float) -> Color:
		if t <= 0.42:
			return Color("20140d").lerp(Color("120d0a"), t / 0.42)
		return Color("120d0a").lerp(Color("0a0807"), (t - 0.42) / 0.58)

	func _blob(c: Vector2, rx: float, ry: float, col: Color, steps: int = 14) -> void:
		draw_set_transform(c, 0.0, Vector2(1.0, ry / rx))
		var a := col.a / float(steps)
		for i in steps:
			draw_circle(Vector2.ZERO, rx * (1.0 - float(i) / float(steps)), Color(col.r, col.g, col.b, a))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Elliptical edge-fog vignette (transparent center → black .6 edges).
class _IsoFog:
	extends Control

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w < 2.0 or h < 2.0:
			return
		var rx := 1.2 * w
		var ratio := (0.9 * h) / rx
		draw_set_transform(size * 0.5, 0.0, Vector2(1.0, ratio))
		var t0 := 0.46
		var t1 := 0.71
		var steps := 16
		for i in steps:
			var ta := t0 + (t1 - t0) * float(i) / float(steps)
			var tb := t0 + (t1 - t0) * float(i + 1) / float(steps)
			var alpha := 0.6 * ((ta + tb) * 0.5 - t0) / (1.0 - t0)
			draw_arc(Vector2.ZERO, (ta + tb) * 0.5 * rx, 0.0, TAU, 128, Color(0, 0, 0, alpha), (tb - ta) * rx + 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Soft radial blob (dust smear) — concentric ellipses approximate the blur.
class _Blob:
	extends Control

	var color := Color.WHITE

	func _init(c: Color) -> void:
		color = c
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var rx := size.x * 0.5 * 0.85
		var ry := size.y * 0.5 * 0.85
		if rx < 1.0 or ry < 1.0:
			return
		var steps := 10
		var a := color.a / float(steps)
		draw_set_transform(size * 0.5, 0.0, Vector2(1.0, ry / rx))
		for i in steps:
			draw_circle(Vector2.ZERO, rx * (1.0 - float(i) / float(steps)), Color(color.r, color.g, color.b, a))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## One scuffed footstep ellipse.
class _Footstep:
	extends Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var rx := size.x * 0.5
		var ry := size.y * 0.5
		var steps := 6
		draw_set_transform(size * 0.5, 0.0, Vector2(1.0, ry / rx))
		for i in steps:
			var t := 1.0 - float(i) / float(steps)
			var col := Color(150.0 / 255.0, 130.0 / 255.0, 90.0 / 255.0, 0.5 / float(steps))
			draw_circle(Vector2.ZERO, rx * t, col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Path-ahead ember beam: soft radial smear biased toward its left end.
class _Beam:
	extends Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		if size.x < 4.0:
			return
		var c := Vector2(size.x * 0.22, size.y * 0.5)
		var rx := size.x * 0.6 * 0.8
		var ry := size.y * 0.9
		var steps := 10
		var a := 0.20 * 0.65 * Palette.GLOW / float(steps)
		draw_set_transform(c, 0.0, Vector2(1.0, ry / rx))
		for i in steps:
			draw_circle(Vector2.ZERO, rx * (1.0 - float(i) / float(steps)), Palette.with_alpha(Palette.EMBER, a))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Lunge motion trail: red streak fading along +x, rotated by the caller.
class _Streak:
	extends Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var w := size.x * 0.78
		var h := size.y
		var solid := Color(192.0 / 255.0, 67.0 / 255.0, 58.0 / 255.0, 0.55)
		var clear := Color(solid.r, solid.g, solid.b, 0.0)
		draw_polygon(
			PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]),
			PackedColorArray([solid, clear, clear, solid]))


## Hero ground ring: flattened role-colored ellipse with a soft glow.
class _Ring:
	extends Control

	var color := Color.WHITE

	func _init(c: Color) -> void:
		color = c
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var rx := size.x * 0.5 - 1.0
		var ry := size.y * 0.5 - 1.0
		if rx < 2.0:
			return
		draw_set_transform(size * 0.5, 0.0, Vector2(1.0, ry / rx))
		draw_arc(Vector2.ZERO, rx, 0.0, TAU, 64, Palette.with_alpha(color, 0.25 * Palette.GLOW), 6.0)
		draw_arc(Vector2.ZERO, rx - 4.0, 0.0, TAU, 64, Palette.with_alpha(color, 0.18 * Palette.GLOW), 5.0)
		draw_arc(Vector2.ZERO, rx, 0.0, TAU, 64, Palette.with_alpha(color, 0.8), 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Elliptical ground shadow under units and props.
class _Shadow:
	extends Control

	var alpha := 0.65

	func _init(a: float) -> void:
		alpha = a
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var rx := size.x * 0.5 * 0.85
		var ry := size.y * 0.5 * 0.85
		if rx < 1.0 or ry < 1.0:
			return
		var steps := 5
		draw_set_transform(size * 0.5, 0.0, Vector2(1.0, ry / rx))
		for i in steps:
			draw_circle(Vector2.ZERO, rx * (1.0 - float(i) / float(steps)), Color(0, 0, 0, alpha / float(steps)))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Brazier flame glow (alpha pulsed by the battlefield clock).
class _Flame:
	extends Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var c := Vector2(size.x * 0.5, size.y * 0.7)
		var rx := size.x * 0.5
		var ry := size.y * 0.6
		if rx < 1.0:
			return
		var steps := 8
		var a := 0.85 / float(steps)
		draw_set_transform(c, 0.0, Vector2(1.0, ry / rx))
		for i in steps:
			draw_circle(Vector2.ZERO, rx * (1.0 - float(i) / float(steps)), Palette.with_alpha(Palette.EMBER_BRIGHT, a))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Expanding spawn-warning ping ring (scale .45→1.7 fading, 1.6 s loop).
class _Ping:
	extends Control

	var hot := false
	var _ph := 0.0

	func _init(p_hot: bool) -> void:
		hot = p_hot
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_ph = fmod(_ph + delta / 1.6, 1.0)
		queue_redraw()

	func _draw() -> void:
		var t := _ph
		var eased := 1.0 - (1.0 - t) * (1.0 - t)  # ease-out
		var s := lerpf(0.45, 1.7, eased)
		var base_a := 0.8 if hot else 0.7
		var col := Color("e0584a") if hot else Palette.EMBER
		draw_arc(size * 0.5, 12.0 * s, 0.0, TAU, 48, Palette.with_alpha(col, base_a * 0.85 * (1.0 - t)), 2.0)
