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

## The roaming advance: the party reads as walking toward the top-right while
## the world scrolls past underneath (CLAUDE.md §6 endless-travel feel).
const TRAVEL_DIR := Vector2(0.7547, -0.656)  # unit vector at -41°
const SCROLL_SPEED := 26.0                   # world px/s at 1× sim speed
const PARTY_CENTER := Vector2(24.5, 65.75)   # cluster centroid (battlefield %)
const STEP_SPACING := 26.0                   # px walked between footsteps
const STEP_LIFE := 6.0                       # seconds before a footstep fades out

# Battle caches: clickable chests scattered along the route. The BACKEND
# decides the contents (BackendClient.chest_open; mock mirrors the server).
const _CHEST_SIZE := Vector2(56, 46)
const CHEST_MAX := 2                          # alive at once
const CHEST_LIFE := 25.0                      # seconds before it sinks away

var _t: float = 0.0
var _layouts: Array[Callable] = []
var _bobs: Array[Dictionary] = []
var _pulses: Array[Dictionary] = []
var _floater_holder: Control
var _relayout_pending: bool = false
var _rng := RandomNumberGenerator.new()

# --- living-world state ---
var _floor: _IsoFloor
var _steps_holder: Control
var _units_holder: Control
var _props: Array[Dictionary] = []      # {node, pct}
var _enemies: Array[Dictionary] = []    # {node, sprite, bar, pct, engage, start_d, speed, elite, state}
var _footsteps: Array[Dictionary] = []  # {node, pct, life}
var _respawn_at: Array[float] = []      # _t deadlines for replacement spawns
var _step_accum: float = 0.0
var _step_side: bool = false
var _resort_accum: float = 0.0
var _chests: Array[Dictionary] = []     # {node, glow, pct, life, opening}
var _next_chest_at: float = 8.0         # _t deadline for the next cache
var _hero_units: Array[Control] = []    # the fighting four (lineup-rebuilt)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_rng.seed = 0xF17E5
	_build()
	resized.connect(_request_relayout)
	EventBus.sim_floater.connect(_on_floater)
	EventBus.sim_enemy_killed.connect(_on_enemy_killed)
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

	# ---- living world: scroll, enemy approach, deaths, respawns ----
	if size.x < 4.0:
		return
	var spd := float(CombatSim.speed)
	var drift_px := TRAVEL_DIR * SCROLL_SPEED * spd * delta
	var drift_pct := Vector2(drift_px.x / size.x, drift_px.y / size.y) * 100.0
	_scroll_world(drift_px, drift_pct, delta)
	_update_enemies(delta, spd)
	while not _respawn_at.is_empty() and _respawn_at[0] <= _t:
		_respawn_at.pop_front()
		_spawn_enemy(false)
	if _t >= _next_chest_at:
		_next_chest_at = _t + _rng.randf_range(20.0, 40.0)
		if _chests.size() < CHEST_MAX:
			_spawn_chest()
	_update_chests(delta)
	_resort_accum += delta
	if _resort_accum >= 0.2:
		_resort_accum = 0.0
		_resort_depth()


# =========================================================================
# Build
# =========================================================================

func _build() -> void:
	_floor = _IsoFloor.new()
	add_child(_floor)
	add_child(_IsoFog.new())

	# ---- travel trail (where the party came from, bottom-left) ----
	var smear := _Blob.new(Color(120.0 / 255.0, 104.0 / 255.0, 72.0 / 255.0, 0.12))
	smear.size = Vector2(420, 240)
	add_child(smear)
	_place_center(smear, 20.0, 74.0)

	# Dynamic footsteps: seeded from the design's TRAIL, then continuously
	# laid down behind the striding party and drifted away with the world.
	_steps_holder = Control.new()
	_steps_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_steps_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_steps_holder)
	for i in GameContent.TRAIL.size():
		var step_def: Dictionary = GameContent.TRAIL[i]
		_add_footstep(Vector2(float(step_def["x"]), float(step_def["y"])), i % 2 == 1, STEP_LIFE * float(step_def["o"]))

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

	# ---- props + enemies + heroes live in one holder, re-depth-sorted as
	# they move (painter order by feet y, heroes biased +12 like the design) ----
	_units_holder = Control.new()
	_units_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_units_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_units_holder)

	for p: Dictionary in GameContent.PROPS:
		var prop := _make_prop(p)
		_units_holder.add_child(prop)
		_props.append({"node": prop, "pct": Vector2(float(p["x"]), float(p["y"]))})

	# Heroes come from the LIVE lineup and are rebuilt on roster swaps. One
	# permanent layout closure reads the current unit list (per-unit closures
	# would dangle over freed nodes after a rebuild).
	_layouts.append(func(bs: Vector2) -> void:
		for u in _hero_units:
			var pct: Vector2 = u.get_meta("pct")
			u.position = Vector2(bs.x * pct.x / 100.0 - u.size.x * 0.5, bs.y * pct.y / 100.0 - u.size.y))
	_spawn_party_heroes()
	EventBus.lineup_changed.connect(_spawn_party_heroes, CONNECT_DEFERRED)

	# Initial enemy wave: one elite + regulars, staggered along their approach
	# so the field opens with the design's far/mid/near depth mix.
	for i in Balance.inum("enemy.per_wave", 8):
		_spawn_enemy(true)

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

	# Prop art from the props.dungeon bundle (keyed by kind), placeholder else.
	var sprite := PixelSlot.new(String(p["label"]), false, "props.dungeon", String(p.get("kind", "")))
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

	# Position is driven per-frame by the world scroll (_scroll_world).
	return unit


## Spawn one enemy at a screen edge and send it at the party. [param initial]
## fast-forwards it a random way down its approach so the opening frame has
## the design's far/mid/near depth mix.
func _spawn_enemy(initial: bool) -> void:
	var has_elite := false
	for e in _enemies:
		if bool(e["elite"]) and String(e["state"]) != "dying":
			has_elite = true
			break
	var elite := not has_elite
	var lunge := (not elite) and _rng.randf() < 0.45
	var enemy_name := "Bone Warden" if elite else ("Marrow Stalker" if _rng.randf() < 0.4 else "Hollow Ghoul")

	# Edge spawn point: hot (top-right) markers weighted ×3, elite always TR.
	var spawn: Dictionary = GameContent.SPAWNS[0]
	if not elite:
		var pool: Array = []
		for s: Dictionary in GameContent.SPAWNS:
			var weight := 3 if bool(s.get("hot", false)) else 1
			for _i in weight:
				pool.append(s)
		spawn = pool[_rng.randi_range(0, pool.size() - 1)]
	var pct := Vector2(float(spawn["x"]) + _rng.randf_range(-3.0, 3.0), float(spawn["y"]) + _rng.randf_range(-3.0, 3.0))

	# Engage slot: a spot on a loose ring around the clash zone.
	var ang := _rng.randf_range(0.0, TAU)
	var radius := _rng.randf_range(3.5, 8.5)
	var engage := Vector2(
		float(GameContent.CLASH["x"]) + cos(ang) * radius,
		float(GameContent.CLASH["y"]) + sin(ang) * radius * 0.7)
	if elite:
		engage = Vector2(float(GameContent.CLASH["x"]) + 6.0, float(GameContent.CLASH["y"]) - 5.0)

	if initial:
		pct = pct.lerp(engage, _rng.randf_range(0.0, 0.85))

	var unit := _make_enemy_node(enemy_name, elite, lunge)
	_units_holder.add_child(unit)
	var entry := {
		"node": unit,
		"sprite": unit.get_meta("sprite"),
		"bar": unit.get_meta("bar"),
		"pct": pct,
		"engage": engage,
		"start_d": maxf(1.0, pct.distance_to(engage)),
		"speed": _rng.randf_range(5.0, 7.5),
		"elite": elite,
		"state": "approach",
	}
	_enemies.append(entry)
	_update_enemy_visual(entry)


## Build the enemy token (sprite/bar/glow/streak/shadow/tooltip); movement and
## depth are driven per-frame by _update_enemies.
func _make_enemy_node(enemy_name: String, elite: bool, lunge: bool) -> Control:
	var usz := _ELITE_SIZE if elite else _ENEMY_SIZE
	var unit := Control.new()
	unit.size = usz
	unit.pivot_offset = Vector2(usz.x * 0.5, usz.y)  # scale from the feet
	unit.mouse_filter = Control.MOUSE_FILTER_STOP
	unit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	Tip.attach(unit, func() -> Dictionary: return {
		"name": enemy_name,
		"type": ("Elite · Stage %s" if elite else "Stage %s") % CombatSim.stage_label(),
		"rarity": "epic" if elite else "common",
		"stats": [
			["HP", Style.group_int(int(CombatSim.base_wave_pool() / Balance.inum("enemy.per_wave", 8) * (2.0 if elite else 1.0)))],
			["Range", "Closing"],
		],
	})

	if lunge:
		var streak := _Streak.new()
		streak.size = Vector2(68, 16)
		streak.pivot_offset = Vector2(0, 8)
		streak.rotation_degrees = _rng.randf_range(10.0, 40.0)
		streak.position = Vector2(usz.x * 0.5 - 68.0 * 0.12, usz.y * 0.42 - 8.0)
		unit.add_child(streak)

	var shadow := _Shadow.new(0.65)
	shadow.size = Vector2(84.0 if elite else 56.0, 16)
	shadow.position = Vector2(usz.x * 0.5 - shadow.size.x * 0.5, usz.y - 10.0)
	unit.add_child(shadow)

	# UnitSprite: real frames when the enemy's bundle has art, else the labeled
	# placeholder. The code-driven approach/lunge bob is unchanged.
	var bundle := "enemy.elite" if elite else ("enemy.ghoul" if enemy_name == "Hollow Ghoul" else "enemy.skeleton")
	var sprite := UnitSprite.new(bundle, "96×112\nelite" if elite else "64×80\nfoe", true)
	sprite.size = usz
	unit.add_child(sprite)
	sprite.play("walk")
	if lunge:
		_bobs.append({"node": sprite, "base": Vector2.ZERO, "kind": "lunge", "period": 0.7, "delay": _rng.randf()})
	else:
		_bobs.append({"node": sprite, "base": Vector2.ZERO, "kind": "approach", "period": 1.9, "delay": _rng.randf()})

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

	var bar := StatBar.new("hp", 100.0, 5.0)
	bar.size = Vector2(84.0 if elite else 54.0, 5.0)
	bar.position = Vector2(usz.x * 0.5 - bar.size.x * 0.5, -10.0)
	unit.add_child(bar)

	unit.set_meta("sprite", sprite)
	unit.set_meta("bar", bar)
	return unit


# =========================================================================
# Living world: scroll, approach, death, respawn
# =========================================================================

## Drift everything the party walks past: floor grid, props (wrapping back in
## ahead of the travel direction), and the fading footstep trail.
func _scroll_world(drift_px: Vector2, drift_pct: Vector2, delta: float) -> void:
	_floor.scroll += drift_px
	_floor.queue_redraw()

	for p in _props:
		var pct: Vector2 = p["pct"] - drift_pct
		# Wrapped off the bottom-left → re-enter ahead (top-right), new lane.
		if pct.x < -10.0 or pct.y > 115.0:
			pct += Vector2(_rng.randf_range(115.0, 140.0), -_rng.randf_range(65.0, 90.0))
			pct.y = clampf(pct.y + _rng.randf_range(-8.0, 8.0), -8.0, 108.0)
		p["pct"] = pct
		_pos_bottom(p["node"], pct)

	# Chests are ground objects too: they drift past and are missed for good
	# once they scroll off behind the party.
	var gone: Array = []
	for ch in _chests:
		ch["pct"] = (ch["pct"] as Vector2) - drift_pct
		_pos_bottom(ch["node"], ch["pct"])
		var cp: Vector2 = ch["pct"]
		if not bool(ch["opening"]) and (cp.x < -6.0 or cp.y > 112.0):
			gone.append(ch)
	for ch in gone:
		ch["opening"] = true
		_despawn_chest(ch, false)

	# Footsteps drift + fade; fresh prints appear under the striding party.
	var dead: Array = []
	for f in _footsteps:
		f["pct"] = (f["pct"] as Vector2) - drift_pct
		f["life"] = float(f["life"]) - delta
		var node := f["node"] as Control
		var a := clampf(float(f["life"]) / STEP_LIFE, 0.0, 1.0) * 0.62
		node.modulate = Color(1, 1, 1, a)
		_pos_center(node, f["pct"])
		if float(f["life"]) <= 0.0 or (f["pct"] as Vector2).x < -4.0 or (f["pct"] as Vector2).y > 108.0:
			dead.append(f)
	for f in dead:
		(f["node"] as Control).queue_free()
		_footsteps.erase(f)

	_step_accum += drift_px.length()
	while _step_accum >= STEP_SPACING:
		_step_accum -= STEP_SPACING
		_step_side = not _step_side
		var perp := Vector2(-TRAVEL_DIR.y, TRAVEL_DIR.x) * (1.3 if _step_side else -1.3)
		var at := PARTY_CENTER - Vector2(TRAVEL_DIR.x, TRAVEL_DIR.y) * 2.4 + perp + Vector2(_rng.randf_range(-0.6, 0.6), _rng.randf_range(-0.4, 0.4))
		_add_footstep(at, _step_side, STEP_LIFE)


func _add_footstep(at_pct: Vector2, flip: bool, life: float) -> void:
	var step := _Footstep.new()
	step.size = Vector2(18, 7)
	step.pivot_offset = step.size * 0.5
	step.rotation_degrees = -35.0
	if flip:
		step.scale = Vector2(-1, 1)
	_steps_holder.add_child(step)
	_footsteps.append({"node": step, "pct": at_pct, "life": life})
	_pos_center(step, at_pct)


## Approach + engage + cosmetic HP drain at the real time-to-kill rate.
func _update_enemies(delta: float, spd: float) -> void:
	var per_wave := Balance.inum("enemy.per_wave", 8)
	# Cosmetic time-to-kill uses the BASE (un-boss-multiplied) pool so the field
	# enemy bars keep draining at the normal rate during boss waves.
	var ttk := maxf(0.5, (CombatSim.base_wave_pool() / float(per_wave)) / maxf(1.0, CombatSim.party_dps))
	for e in _enemies:
		if String(e["state"]) == "dying":
			continue
		var pct: Vector2 = e["pct"]
		var engage: Vector2 = e["engage"]
		if String(e["state"]) == "approach":
			var to_go := engage - pct
			var d := to_go.length()
			if d < 0.8:
				e["state"] = "engaged"
			else:
				pct += to_go / d * minf(d, float(e["speed"]) * spd * delta)
				e["pct"] = pct
			_update_enemy_visual(e)
		else:
			var bar := e["bar"] as StatBar
			bar.pct = maxf(5.0, bar.pct - 100.0 / ttk * spd * delta)
		_pos_bottom(e["node"], e["pct"])


# =========================================================================
# Battle caches (clickable chests; contents decided by the backend)
# =========================================================================

## Drop a cache somewhere ahead of the party, clear of the clash zone.
func _spawn_chest() -> void:
	var pct := Vector2.ZERO
	for _attempt in 8:
		pct = Vector2(_rng.randf_range(30.0, 90.0), _rng.randf_range(16.0, 90.0))
		if pct.distance_to(PARTY_CENTER) > 20.0 \
				and pct.distance_to(Vector2(float(GameContent.CLASH["x"]), float(GameContent.CLASH["y"]))) > 14.0:
			break
	var unit := _make_chest_node()
	_units_holder.add_child(unit)
	var entry := {"node": unit, "glow": unit.get_meta("glow"), "pct": pct, "life": CHEST_LIFE, "opening": false}
	_chests.append(entry)
	_pos_bottom(unit, pct)
	# Pop in from the ground.
	unit.scale = Vector2(0.2, 0.2)
	unit.modulate = Color(1, 1, 1, 0.0)
	var tw := unit.create_tween()
	tw.set_parallel(true)
	tw.tween_property(unit, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(unit, "modulate:a", 1.0, 0.25)
	unit.gui_input.connect(func(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_open_chest(entry))


func _make_chest_node() -> Control:
	var unit := Control.new()
	unit.size = _CHEST_SIZE
	unit.pivot_offset = Vector2(_CHEST_SIZE.x * 0.5, _CHEST_SIZE.y)
	unit.mouse_filter = Control.MOUSE_FILTER_STOP
	unit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	Tip.attach(unit, {
		"name": "Battle Cache",
		"type": "Click to open",
		"rarity": "rare",
		"flavor": "Left behind on the route. The Hollow decides what's inside.",
	})

	var shadow := _Shadow.new(0.6)
	shadow.size = Vector2(46, 13)
	shadow.position = Vector2(_CHEST_SIZE.x * 0.5 - 23.0, _CHEST_SIZE.y - 8.0)
	unit.add_child(shadow)

	var sprite := PixelSlot.new("48×40\nchest", true)
	sprite.size = _CHEST_SIZE
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	unit.add_child(sprite)

	# Gold glint border; brightens on hover, pulses while waiting.
	var glow := Panel.new()
	var gsb := StyleBoxFlat.new()
	gsb.draw_center = false
	gsb.set_border_width_all(1)
	gsb.border_color = Palette.GOLD_BRIGHT
	gsb.set_corner_radius_all(4)
	gsb.shadow_color = Palette.with_alpha(Palette.GOLD_BRIGHT, 0.35 * Palette.GLOW)
	gsb.shadow_size = int(14 * Palette.GLOW)
	glow.add_theme_stylebox_override("panel", gsb)
	glow.size = _CHEST_SIZE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	unit.add_child(glow)
	_pulses.append({"node": glow, "period": 1.6, "delay": 0.0, "min": 0.35, "max": 0.95})

	unit.mouse_entered.connect(func() -> void: unit.scale = Vector2(1.08, 1.08))
	unit.mouse_exited.connect(func() -> void: unit.scale = Vector2.ONE)
	unit.set_meta("glow", glow)
	return unit


## Lifetime tick: blink when about to vanish, sink away at 0.
func _update_chests(delta: float) -> void:
	var expired: Array = []
	for ch in _chests:
		if bool(ch["opening"]):
			continue
		ch["life"] = float(ch["life"]) - delta
		var left := float(ch["life"])
		if left <= 0.0:
			expired.append(ch)
		elif left < 4.0:
			var node := ch["node"] as Control
			node.modulate.a = 0.45 + 0.55 * (0.5 + 0.5 * sin(_t * 9.0))
	for ch in expired:
		ch["opening"] = true  # block clicks during the sink-out
		_despawn_chest(ch, false)


## The click: the backend rolls the reward (mock mirrors it exactly), then the
## chest bursts and the result floats up where it stood.
func _open_chest(entry: Dictionary) -> void:
	if bool(entry["opening"]):
		return
	entry["opening"] = true
	var at: Vector2 = entry["pct"]
	var res: Dictionary = await BackendClient.chest_open()
	if not is_instance_valid(self) or not is_instance_valid(entry["node"]):
		return
	var data: Dictionary = res["data"]
	if not bool(res["ok"]):
		var msg := String((data.get("error", {}) as Dictionary).get("message", "The cache is sealed."))
		_chest_floater(at, msg, Palette.TX_MUTE, 13)
		_despawn_chest(entry, false)
		return
	var reward: Dictionary = data["reward"]
	match String(reward["kind"]):
		"gold":
			_chest_floater(at, "+%s gold" % Style.group_int(int(reward["gold"])), Palette.GOLD_BRIGHT, 17)
		"materials":
			var txt := "+%d iron ingots" % int(reward["iron"])
			if int(reward["dust"]) > 0:
				txt += " · +%d ember dust" % int(reward["dust"])
			_chest_floater(at, txt, Palette.TX, 15)
		"item":
			var item: Dictionary = reward["item"]
			if bool(reward["banked"]):
				_chest_floater(at, String(item["n"]), Palette.rarity_color(String(item["r"])), 17)
			else:
				_chest_floater(at, "Bag full → +%s gold" % Style.group_int(int(reward["gold"])), Palette.GOLD_BRIGHT, 15)
	_despawn_chest(entry, true)


## Opened: burst (flash + squash). Expired/missed: sink and fade. Idempotent —
## a chest can only leave _chests once (its glow pulse must be unregistered
## exactly when the node is freed, or _process casts a freed object).
func _despawn_chest(entry: Dictionary, opened: bool) -> void:
	if not _chests.has(entry):
		return
	_chests.erase(entry)
	var unit := entry["node"] as Control
	var glow := entry["glow"] as CanvasItem
	_pulses = _pulses.filter(func(p: Dictionary) -> bool: return p["node"] != glow)
	var tw := unit.create_tween()
	if opened:
		unit.modulate = Color(1.6, 1.45, 1.1, 1.0)  # gold flash
		tw.set_parallel(true)
		tw.tween_property(unit, "scale", Vector2(1.25, 0.06), 0.34).set_ease(Tween.EASE_IN)
		tw.tween_property(unit, "modulate:a", 0.0, 0.36)
	else:
		tw.set_parallel(true)
		tw.tween_property(unit, "scale:y", 0.1, 0.5).set_ease(Tween.EASE_IN)
		tw.tween_property(unit, "modulate:a", 0.0, 0.5)
	tw.chain().tween_callback(unit.queue_free)


## Reward readout that pops where the chest stood (bigger, slower floater).
func _chest_floater(pct: Vector2, text: String, col: Color, fsize: int) -> void:
	if _floater_holder == null or size.x < 4.0:
		return
	var lbl := Style.pixel_label(text, fsize, col)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("shadow_offset_x", 0)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	lbl.add_theme_constant_override("outline_size", 8)
	lbl.add_theme_color_override("font_outline_color", Palette.with_alpha(col, 0.25 * Palette.GLOW))
	_floater_holder.add_child(lbl)
	lbl.reset_size()
	lbl.pivot_offset = lbl.size * 0.5
	var px := size.x * pct.x / 100.0
	var py := size.y * pct.y / 100.0 - _CHEST_SIZE.y
	lbl.position = Vector2(px - lbl.size.x * 0.5, py)
	lbl.scale = Vector2(0.6, 0.6)
	lbl.modulate = Color(1, 1, 1, 0.0)
	var tw := lbl.create_tween()
	tw.tween_property(lbl, "scale", Vector2(1.1, 1.1), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(lbl, "modulate:a", 1.0, 0.2)
	tw.tween_property(lbl, "scale", Vector2.ONE, 0.18)
	tw.tween_interval(1.1)
	tw.tween_property(lbl, "position:y", py - 46.0, 0.8)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.8)
	tw.tween_callback(lbl.queue_free)


## Depth tier from approach progress: far (small/faint) → near (full).
func _update_enemy_visual(e: Dictionary) -> void:
	var d := (e["pct"] as Vector2).distance_to(e["engage"])
	var t := clampf(1.0 - d / float(e["start_d"]), 0.0, 1.0)
	var unit := e["node"] as Control
	var s := lerpf(0.5, 1.0, t)
	unit.scale = Vector2(s, s)
	unit.modulate = Color(1, 1, 1, lerpf(0.45, 1.0, t))


## A sim kill landed: drop the most-worn-down engaged token (elite last) with
## a flatten-and-fade, then queue a replacement from the edges.
func _on_enemy_killed() -> void:
	var victim: Dictionary = {}
	for e in _enemies:
		if String(e["state"]) != "engaged":
			continue
		if victim.is_empty():
			victim = e
			continue
		var v_better := (bool(victim["elite"]) and not bool(e["elite"])) \
			or ((bool(victim["elite"]) == bool(e["elite"])) and (victim["bar"] as StatBar).pct > (e["bar"] as StatBar).pct)
		if v_better:
			victim = e
	if victim.is_empty():
		# Nothing engaged yet — take the closest approacher instead.
		var best_d := INF
		for e in _enemies:
			if String(e["state"]) != "approach":
				continue
			var d := (e["pct"] as Vector2).distance_to(e["engage"])
			if d < best_d:
				best_d = d
				victim = e
	if victim.is_empty():
		return

	victim["state"] = "dying"
	var unit := victim["node"] as Control
	var sprite := victim["sprite"] as Control
	_bobs = _bobs.filter(func(b: Dictionary) -> bool: return b["node"] != sprite)
	var tw := unit.create_tween()
	tw.set_parallel(true)
	tw.tween_property(unit, "scale:y", 0.06, 0.3).set_ease(Tween.EASE_IN)
	tw.tween_property(unit, "modulate:a", 0.0, 0.32)
	tw.chain().tween_callback(func() -> void:
		_enemies.erase(victim)
		unit.queue_free())
	_respawn_at.append(_t + _rng.randf_range(0.4, 1.3) / maxf(1.0, float(CombatSim.speed) * 0.6))


## Painter re-sort: children ordered by feet y (+ hero bias) as units move.
func _resort_depth() -> void:
	var entries: Array = []
	for child in _units_holder.get_children():
		var c := child as Control
		if c == null:
			continue
		var bias := float(c.get_meta("depth_bias", 0.0))
		entries.append([c.position.y + c.size.y + bias, c])
	entries.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for i in entries.size():
		_units_holder.move_child(entries[i][1], i)


## Bottom-center anchor at pct of the battlefield (CSS translate(-50%,-100%)).
func _pos_bottom(node: Control, pct: Vector2) -> void:
	node.position = Vector2(size.x * pct.x / 100.0 - node.size.x * 0.5, size.y * pct.y / 100.0 - node.size.y)


## Center anchor at pct of the battlefield.
func _pos_center(node: Control, pct: Vector2) -> void:
	node.position = Vector2(size.x * pct.x / 100.0, size.y * pct.y / 100.0) - node.size * 0.5


## (Re)spawn the four lineup heroes (design v2: the party is editable).
## Freed sprites must leave _bobs or _process casts freed objects.
func _spawn_party_heroes() -> void:
	for unit in _hero_units:
		var spr: Variant = unit.get_meta("sprite")
		_bobs = _bobs.filter(func(b: Dictionary) -> bool: return b["node"] != spr)
		unit.queue_free()
	_hero_units.clear()
	var lineup := GameContent.active_party()
	for i in lineup.size():
		var hero := _make_hero(lineup[i], i)
		hero.set_meta("depth_bias", 12.0)
		_units_holder.add_child(hero)
		_hero_units.append(hero)
	_request_relayout()


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

	# UnitSprite per lineup hero: animates when "hero.<id>" has art, else the
	# placeholder. The code stride-bob + advance/scroll stay as-is.
	var sprite := UnitSprite.new(GameContent.hero_bundle(String(h.get("id", ""))), "64×96\n%s ↗" % String(h["name"]), true)
	sprite.size = _HERO_SIZE
	sprite.pivot_offset = _HERO_SIZE * 0.5
	unit.add_child(sprite)
	sprite.play("walk")
	_bobs.append({"node": sprite, "base": Vector2.ZERO, "kind": "stride", "period": 0.62, "delay": float(idx) * 0.15})

	unit.set_meta("sprite", sprite)
	unit.set_meta("pct", Vector2(float(h["x"]), float(h["y"])))
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
	if not UserSettings.get_bool("dmg_numbers"):  # Options · Combat
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

	## Accumulated world travel (px); phase-shifts the iso grid so the floor
	## streams past under the advancing party.
	var scroll := Vector2.ZERO

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
		# The world translation is -scroll, so each family's intercept shifts
		# by (T.y ∓ 0.5·T.x); fposmod keeps the streaming loop seamless.
		var spacing := 58.0 / cos(atan(0.5))
		var ph1 := fposmod(-scroll.y + 0.5 * scroll.x, spacing)
		var c1 := -0.5 * w - spacing + ph1
		while c1 < h:
			draw_line(Vector2(0, c1), Vector2(w, c1 + 0.5 * w), _GRID, 1.0)
			c1 += spacing
		var ph2 := fposmod(-scroll.y - 0.5 * scroll.x, spacing)
		var c2 := -spacing + ph2
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
