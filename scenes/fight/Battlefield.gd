extends Control
## FIGHT battlefield — a 2D left→right side-scroller presentation of the abstract
## CombatSim. The single delver holds the LEFT, facing right; enemies march in
## from the RIGHT to a clash line and are cut down; a parallax background scrolls
## left so the party reads as advancing through the dungeon (CLAUDE.md §6 motion).
##
## Combat truth lives in CombatSim — this layer is a COHERENT readout of it: the
## hero attacks the nearest enemy IN RANGE (melee waits for the foe to arrive,
## ranged fires at distance); a damage number pops ON the struck enemy when the
## hit lands and its HP bar drains; the enemy dies on the sim's authoritative
## `sim_enemy_killed` cadence (8 per normal wave). Boss HP is sim-owned.
##
## Positions are a scalar x (0..1 of width; smaller = nearer the hero) + a lane
## index (a y offset around the ground line). Re-laid out on resize.

# --- sprite sizes ---
const _HERO_SIZE := Vector2(98, 132)
const _ENEMY_SIZE := Vector2(72, 96)
const _ELITE_SIZE := Vector2(104, 134)
const _BOSS_SIZE := Vector2(150, 188)
const _CHEST_SIZE := Vector2(58, 48)
const _MAX_FLOATERS := 18

# --- 2D layout (fractions of the rect) ---
const GROUND_Y := 0.66                  # feet line for the center lane
const FLOOR_SURF := 0.73                # bg.reliquary floor.png: walking-surface fraction (maps to GROUND_Y)
const HERO_X := 0.20                    # the delver holds here
const CLASH_X := 0.28                   # enemies stop here to fight (right up against the hero at HERO_X)
const SPAWN_X := 1.10                   # enter from off the right edge
const DESPAWN_X := -0.12                # culled once scrolled off the left
const LANES: Array[float] = [-0.03, 0.0, 0.015]  # y offsets (fraction): ground units hug the floor line
const APPROACH_SPEED := 0.18            # rect-widths/sec at 1×: a calm, deliberate walk-in (kills are
                                        # deferred until a foe engages, so it needn't rush)
const MELEE_RANGE := 0.08               # x past CLASH a melee target must be within

# --- 2.5D render (Combat3DView): the combatants become 3D models on a tilted
# side-camera grid. The 2D entity/kill/wave/focus logic is UNTOUCHED — it stays
# the coherent sim readout; _pos_ground just projects the (x,lane) world point
# through the 3D camera, so the 2D overlays (HP bars, damage numbers, projectiles,
# clickable chests) land on the 3D models. Set false for the pure-2D side-scroller. ---
const USE_3D := false  # 2D side-scroller (2.5D needs .glb models in assets/models/)
const BF_BAND := 1400.0                 # x-fraction → sim-px across the side band (world X)
const BF_DEPTH := 150.0                 # lane → sim-px of depth (world Z; near lane toward camera)

# --- forward-travel parallax (replaces the iso scroll) ---
const SCROLL_SPEED := 150.0             # near-layer px/s at 1× speed
const PARALLAX := [0.18, 0.45, 1.0]     # far → near layer scroll factors

# --- battle caches (clickable chests; the BACKEND decides the contents) ---
const CHEST_MAX := 2
const CHEST_LIFE := 25.0

# --- environmental scenery: props drift past the party (behind the units) ---
const _PROP_KINDS: Array[String] = ["pillar", "tree", "brazier", "rubble", "rock", "tree", "pillar"]
const _PROP_SIZES := {
	"pillar": Vector2(86, 158), "brazier": Vector2(56, 84),
	"rubble": Vector2(94, 60), "tree": Vector2(94, 152), "rock": Vector2(72, 54),
}

# --- hero attacks (presentation only; never feeds the sim) ---
const FOCUS_RECOMPUTE_INTERVAL := 0.15
const FIRE_INTERVAL := 1.0              # ~1 attack/second at 1× speed (level-1 feel)
const MAX_PROJECTILES := 24             # hard cap (bounds 4×-speed bursts)

# --- coherence: the cosmetic HP drain is budgeted by HIT COUNT (not party_dps),
# calibrated so a monster takes ~3 hits at the ~1 attack/sec cadence — matching
# the sim's ~3s-per-monster kill pace at level 1. Floored ≥5% until the
# authoritative sim kill lands (the cosmetic bar never kills ahead of the sim). ---
const HP_DRAIN_PER_HIT := 0.34
const HP_FLOOR := 5.0
const DMG_FRAC_LO := 0.30
const DMG_FRAC_HI := 0.50
const CRIT_CHANCE := 0.22
const CRIT_MULT := 3.0

var _t: float = 0.0
var _rng := RandomNumberGenerator.new()
var _layouts: Array[Callable] = []
var _relayout_pending: bool = false

# holders (back → front children of self)
var _bg_holder: Control
var _units_holder: Control
var _proj_holder: Control
var _floater_holder: Control
var _world3d: Combat3DView   # the 2.5D world (null when USE_3D is off)

# per-frame registries — any node freed early MUST leave these the same instant
var _bobs: Array[Dictionary] = []
var _pulses: Array[Dictionary] = []

# entities
var _bg_layers: Array[Dictionary] = []    # {node, factor}
var _prop_holder: Control
var _props: Array[Dictionary] = []        # {node, x, lane, rate} — scenery drifting past
var _hero_units: Array[Control] = []
var _enemies: Array[Dictionary] = []      # {node, sprite, bar, state, elite, x, lane, start_x, engage_x, speed, hp_pct}
var _projectiles: Array[Dictionary] = []  # {node, from, to, t, dur, impact, target, spec}
var _chests: Array[Dictionary] = []       # {node, glow, x, lane, life, opening}
var _spawn_queue: Array[Dictionary] = []  # pending {at: _t deadline, plan: {name, elite}}
var _resort_accum: float = 0.0
var _next_chest_at: float = 8.0
var _lane_rr: int = 0                      # round-robin lane assignment

# targeting / cadence
var _focus: Dictionary = {}               # the hero's target: a reference into _enemies ({} = none)
var _focus_accum: float = 0.0
var _fire_accum: float = 0.0
var _boss_entry: Dictionary = {}          # the single on-field boss token during a boss wave
var _pending_kills: int = 0               # sim kills that arrived before any foe engaged (held)
var _kill_drain: float = 0.0              # paces the held-kill drain onto engaged foes


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_rng.seed = 0xF17E5
	_build()
	resized.connect(_request_relayout)
	EventBus.sim_floater.connect(_on_floater)
	EventBus.sim_enemy_killed.connect(_on_enemy_killed)
	# A real boss wave puts ONE distinct token on the field (Fight.gd keeps the
	# HUD banner). Normal waves never show a boss.
	EventBus.sim_boss_started.connect(_on_boss_started)
	EventBus.sim_boss_defeated.connect(_on_boss_defeated)
	EventBus.sim_boss_hp.connect(_on_boss_hp_field)
	EventBus.sim_stage_changed.connect(_on_stage_changed_clear_boss)
	# Discrete waves: a fresh batch marches in only once the previous wave clears.
	EventBus.sim_wave_changed.connect(_on_sim_wave_advanced)
	_request_relayout()


# =========================================================================
# Per-frame clock
# =========================================================================

func _process(delta: float) -> void:
	_t += delta
	# The party WALKS until it meets enemies, then STOPS to fight: while traveling
	# the background scrolls + the hero strides; in combat both freeze.
	var traveling := not _in_combat()
	# Looping motion: stride/lunge/idle bobs on sprites + opacity pulses.
	for b in _bobs:
		var n := b["node"] as Control
		var wv := 0.5 - 0.5 * cos(TAU * (_t - float(b["delay"])) / float(b["period"]))
		match String(b["kind"]):
			"stride":  # the hero's walk — only while traveling; stands still in combat
				if traveling:
					n.position = (b["base"] as Vector2) + Vector2(0.0, -5.0 * wv)
					n.rotation_degrees = lerpf(-1.4, 1.4, wv)
				else:
					n.position = b["base"]
					n.rotation_degrees = 0.0
			"lunge":
				n.position = (b["base"] as Vector2) + Vector2(0.0, 3.0 * wv)
			_:
				n.position = (b["base"] as Vector2) + Vector2(0.0, -3.0 * wv)
	for p in _pulses:
		var wv2 := 0.5 - 0.5 * cos(TAU * (_t - float(p["delay"])) / float(p["period"]))
		var ci := p["node"] as CanvasItem
		var m := ci.modulate
		m.a = lerpf(float(p["min"]), float(p["max"]), wv2)
		ci.modulate = m

	if size.x < 4.0:
		return
	var spd := float(CombatSim.speed)
	# Forward travel freezes while fighting (the party has stopped to clash).
	if traveling:
		_scroll_parallax(delta, spd)
	_update_enemies(delta, spd)  # foes keep walking in to join the fight
	# Sim kills that arrived before a foe engaged are held, then drained onto
	# engaged foes so deaths always land at the clash, never mid-runway.
	if _pending_kills > 0:
		_kill_drain += delta * spd
		if _kill_drain >= 0.3:
			_kill_drain = 0.0
			if _kill_engaged_victim():
				_pending_kills -= 1
	# Hero focusing: re-pick the nearest target on a throttle or when it's lost.
	_focus_accum += delta
	if _focus_accum >= FOCUS_RECOMPUTE_INTERVAL or not _focus_valid():
		_focus_accum = 0.0
		_retarget_focus()
	_update_attack_cadence(delta, spd)
	_update_projectiles(delta, spd)
	# Staggered batch spawns queued by _on_sim_wave_advanced.
	while not _spawn_queue.is_empty() and float(_spawn_queue[0]["at"]) <= _t:
		var q: Dictionary = _spawn_queue.pop_front()
		_spawn_enemy(false, q["plan"])
	if _t >= _next_chest_at:
		_next_chest_at = _t + _rng.randf_range(20.0, 40.0)
		if _chests.size() < CHEST_MAX:
			_spawn_chest()
	_update_chests(delta)
	_resort_accum += delta
	if _resort_accum >= 0.2:
		_resort_accum = 0.0
		_resort_depth()
	# 2.5D: drive the 3D models from the (now-current) entity positions.
	if _world3d != null:
		_render3d_fight()


# =========================================================================
# Build
# =========================================================================

func _build() -> void:
	# 2.5D: a tilted side-camera 3D world sits BEHIND the 2D HUD/overlays. The grid
	# + environment replace the parallax; the combatants render as 3D models.
	if USE_3D:
		_world3d = Combat3DView.new()
		_world3d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_world3d.set_camera_mode("side")
		add_child(_world3d)
		_world3d.auto_load_models()
		_world3d.focus(_bf_world(0.42, 1))

	# Background: a static cavern backdrop + 3 scrolling parallax layers.
	_bg_holder = Control.new()
	_bg_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg_holder)

	var backdrop := _Backdrop.new(GROUND_Y)
	_bg_holder.add_child(backdrop)
	# Textured parallax when the art bundle is present; else the procedural bands.
	var bg_bundle := "bg.reliquary"
	var have_bg := AssetManager.has(bg_bundle)
	var kinds := ["far", "mid", "near"]
	for i in 3:
		var tex: Texture2D = AssetManager.get_texture(bg_bundle, kinds[i]) if have_bg else null
		var layer := _ParallaxLayer.new(kinds[i], GROUND_Y, tex)
		_bg_holder.add_child(layer)
		_bg_layers.append({"node": layer, "factor": PARALLAX[i]})
	# The walkable floor strip (its painted floor-line sits on GROUND_Y); scrolls
	# with the near layer so the ground reads as moving under the party.
	if have_bg:
		var floor_tex: Texture2D = AssetManager.get_texture(bg_bundle, "floor")
		if floor_tex != null:
			var floor_layer := _ParallaxLayer.new("floor", GROUND_Y, floor_tex, FLOOR_SURF)
			_bg_holder.add_child(floor_layer)
			_bg_layers.append({"node": floor_layer, "factor": 1.0})

	# Scenery: environmental props that drift past the party (behind the units).
	_prop_holder = Control.new()
	_prop_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_prop_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_prop_holder)
	for i in 7:
		_spawn_prop(_rng.randf_range(0.25, 1.7))
	# 3D grid + environment stand in for the 2D backdrop/parallax/props.
	if _world3d != null:
		_bg_holder.visible = false
		_prop_holder.visible = false

	# Units (heroes + enemies + chests), depth-sorted by feet y.
	_units_holder = Control.new()
	_units_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_units_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_units_holder)

	# Projectiles draw above the units but are NOT depth-sorted (own holder).
	_proj_holder = Control.new()
	_proj_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_proj_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_proj_holder)

	# Floating numbers on top of everything.
	_floater_holder = Control.new()
	_floater_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_floater_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_floater_holder)

	# The hero(es) come from the LIVE lineup and rebuild on roster swaps. One
	# permanent layout closure reads the current unit list (per-unit closures
	# would dangle over freed nodes after a rebuild).
	_layouts.append(func(_bs: Vector2) -> void:
		for u in _hero_units:
			_pos_ground(u, HERO_X, 1))
	_spawn_party_heroes()
	EventBus.lineup_changed.connect(_spawn_party_heroes, CONNECT_DEFERRED)
	EventBus.loadout_changed.connect(_refresh_pet, CONNECT_DEFERRED)  # active-pet swaps

	# Open the field with the current wave's lineup already marching in.
	for entry in GameContent.wave_plan(CombatSim.act, CombatSim.stage, CombatSim.wave):
		_spawn_enemy(true, entry)


# =========================================================================
# Hero
# =========================================================================

## (Re)spawn the single delver. Freed sprites must leave _bobs or _process casts
## freed objects; in-flight projectiles + the stale focus drop with the origin.
func _spawn_party_heroes() -> void:
	for unit in _hero_units:
		var spr: Variant = unit.get_meta("sprite")
		_bobs = _bobs.filter(func(b: Dictionary) -> bool: return not is_same(b["node"], spr))
		unit.queue_free()
	_hero_units.clear()
	for p in _projectiles:
		var pn: Variant = p["node"]
		if is_instance_valid(pn):
			(pn as Node).queue_free()
	_projectiles.clear()
	_focus = {}
	var lineup := GameContent.active_party()
	for i in lineup.size():
		var hero := _make_hero(lineup[i], i)
		hero.set_meta("depth_bias", 40.0)  # heroes draw in front of same-lane foes
		_units_holder.add_child(hero)
		_hero_units.append(hero)
		_attach_pet(hero)  # active companion trots along behind
		if _world3d != null:
			_hide_2d_body(hero)
	_request_relayout()


## Hero: role ground ring, striding sprite (facing RIGHT), shadow, tooltip.
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
			["DPS", CombatSim.party_dps_label],
		],
	})

	var ring := _Ring.new(Palette.role_color(String(h["role"])))
	ring.size = Vector2(74, 34)
	ring.position = Vector2(_HERO_SIZE.x * 0.5 - 37.0, _HERO_SIZE.y - 27.0 - 17.0)
	unit.add_child(ring)

	var shadow := _Shadow.new(0.65)
	shadow.size = Vector2(66, 17)
	shadow.position = Vector2(_HERO_SIZE.x * 0.5 - 33.0, _HERO_SIZE.y - 11.0)
	unit.add_child(shadow)

	# UnitSprite per delver: animates when "class.<id>" has art, else the labeled
	# placeholder. Faces RIGHT (scale.x = +1, the default).
	var sprite := UnitSprite.new(GameContent.hero_bundle(String(h.get("id", ""))), "98×132\n%s" % String(h["name"]), true)
	sprite.size = _HERO_SIZE
	sprite.pivot_offset = _HERO_SIZE * 0.5
	unit.add_child(sprite)
	sprite.play("walk")
	_bobs.append({"node": sprite, "base": Vector2.ZERO, "kind": "stride", "period": 0.62, "delay": float(idx) * 0.15})

	unit.set_meta("sprite", sprite)
	return unit


## Active companion: a small pet glyph that trots along just behind the delver
## (it strides right, so the pet trails to the LEFT, down on the ground line).
func _attach_pet(hero_unit: Control) -> void:
	var idx := GameState.active_pet
	if idx < 0 or idx >= GameContent.PETS.size() or not GameContent.pet_owned(idx):
		return
	var pet: Dictionary = GameContent.PETS[idx]
	var col := Palette.rarity_color(String(pet.get("r", "common")))
	var psz := Vector2(52.0, 52.0)
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size = psz
	holder.position = Vector2(-62.0, _HERO_SIZE.y - psz.y - 2.0)
	hero_unit.add_child(holder)
	hero_unit.set_meta("pet", holder)

	var shadow := _Shadow.new(0.5)
	shadow.size = Vector2(40.0, 12.0)
	shadow.position = Vector2(psz.x * 0.5 - 20.0, psz.y - 9.0)
	holder.add_child(shadow)

	var ic := GearIcon.new("pet", col)
	ic.size = psz
	holder.add_child(ic)
	# A little trotting bob (self-contained; the tween dies with the freed sprite).
	var tw := ic.create_tween().set_loops()
	tw.tween_property(ic, "position:y", -6.0, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(ic, "position:y", 0.0, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


## Rebuild the companion when the active pet changes (loadout_changed).
func _refresh_pet() -> void:
	if _hero_units.is_empty():
		return
	var hero := _hero_units[0]
	if hero.has_meta("pet"):
		var old: Variant = hero.get_meta("pet")
		if is_instance_valid(old):
			(old as Node).queue_free()
		hero.remove_meta("pet")
	_attach_pet(hero)


func _hero_screen_center() -> Vector2:
	var h := _hero_units[0]
	return h.position + h.size * Vector2(0.62, 0.45)  # roughly the chest, off the lead hand


# =========================================================================
# Enemies: spawn at the right → walk left → engage at the clash line → die
# =========================================================================

## Spawn one foe at the right edge in a lane; it walks left to its engage slot.
## [param initial] foes fast-forward part-way in so the field opens populated.
## [param plan] (from GameContent.wave_plan) picks the name + elite flag; an empty
## plan falls back to a random roster pick (used by tests / safety).
func _spawn_enemy(initial: bool, plan: Dictionary = {}) -> void:
	var roster := GameContent.enemy_roster_for_floor(Balance.floor_index(CombatSim.act, CombatSim.stage))
	var trash: Array = roster["trash"]
	var elite: bool
	var enemy_name: String
	if plan.has("name"):
		enemy_name = String(plan["name"])
		elite = bool(plan.get("elite", false)) and _boss_entry.is_empty()
	else:
		var has_elite := false
		for e in _enemies:
			if bool(e["elite"]) and String(e["state"]) != "dying":
				has_elite = true
				break
		elite = (not has_elite) and _boss_entry.is_empty()
		enemy_name = String(roster["elite"]) if elite else String(trash[_rng.randi_range(0, trash.size() - 1)])
	var lunge := (not elite) and _rng.randf() < 0.45

	var lane := 1 if elite else _lane_rr % LANES.size()
	_lane_rr += 1
	# Engage slot: the clash line, fanned per lane + a touch of jitter so same-lane
	# foes don't stack perfectly.
	var engage_x := CLASH_X + float(lane - 1) * 0.028 + _rng.randf_range(-0.025, 0.025)
	if elite:
		engage_x = CLASH_X + 0.05
	var start_x := SPAWN_X + _rng.randf_range(0.0, 0.18)
	var x := start_x
	if initial:
		x = lerpf(engage_x, start_x, _rng.randf_range(0.0, 0.9))

	var unit := _make_enemy_node(enemy_name, elite, lunge)
	_units_holder.add_child(unit)
	var entry := {
		"node": unit,
		"sprite": unit.get_meta("sprite"),
		"bar": unit.get_meta("bar"),
		"x": x,
		"lane": lane,
		"start_x": start_x,
		"engage_x": engage_x,
		"speed": APPROACH_SPEED * _rng.randf_range(0.85, 1.15),
		"elite": elite,
		"hp_pct": 100.0,
		"state": "approach",
	}
	_enemies.append(entry)
	_update_enemy_visual(entry)
	_pos_ground(unit, x, lane)
	if _world3d != null:
		_hide_2d_body(unit)


## Build the enemy token (sprite facing LEFT / bar / glow / streak / shadow / tip);
## movement + depth are driven per-frame by _update_enemies.
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
			["HP", Style.group_int(int(CombatSim.base_wave_pool() / float(maxi(1, CombatSim._wave_count))))],
			["Range", "Closing"],
		],
	})

	if lunge:
		var streak := _Streak.new()
		streak.size = Vector2(68, 16)
		streak.pivot_offset = Vector2(34, 8)
		streak.scale.x = -1.0  # trails behind a left-moving foe
		streak.position = Vector2(usz.x * 0.5, usz.y * 0.42 - 8.0)
		unit.add_child(streak)

	var shadow := _Shadow.new(0.65)
	shadow.size = Vector2(84.0 if elite else 58.0, 16)
	shadow.position = Vector2(usz.x * 0.5 - shadow.size.x * 0.5, usz.y - 10.0)
	unit.add_child(shadow)

	# UnitSprite: real frames when the enemy's bundle has art, else the labeled
	# placeholder. Faces LEFT (toward the party) via outer scale.x = -1.
	var bundle := "enemy.elite" if elite else ("enemy.ghoul" if _rng.randf() < 0.5 else "enemy.skeleton")
	var sprite := UnitSprite.new(bundle, "elite" if elite else "foe", true)
	sprite.size = usz
	sprite.pivot_offset = usz * 0.5
	sprite.scale.x = -1.0
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
	bar.size = Vector2(84.0 if elite else 56.0, 5.0)
	bar.position = Vector2(usz.x * 0.5 - bar.size.x * 0.5, -10.0)
	unit.add_child(bar)

	unit.set_meta("sprite", sprite)
	unit.set_meta("bar", bar)
	return unit


## Walk approachers toward their engage slot; position everything. The cosmetic
## HP bar is drained on HIT (_on_impact), not here, so it tracks the sim's kills.
func _update_enemies(delta: float, spd: float) -> void:
	for e in _enemies:
		if String(e["state"]) == "dying":
			continue
		if String(e["state"]) == "approach":
			var ex := float(e["x"])
			var goal := float(e["engage_x"])
			ex = maxf(goal, ex - float(e["speed"]) * spd * delta)
			e["x"] = ex
			if ex <= goal + 0.001:
				e["state"] = "engaged"
			_update_enemy_visual(e)
		_pos_ground(e["node"], float(e["x"]), int(e["lane"]))


## Depth read: lane gives the base scale/opacity (far lane small/faint), and a
## foe grows as it closes the distance from its spawn to the clash line.
func _update_enemy_visual(e: Dictionary) -> void:
	if is_same(e, _boss_entry):
		return
	var lane_t := float(int(e["lane"])) / float(maxi(1, LANES.size() - 1))
	var span := maxf(0.05, float(e["start_x"]) - float(e["engage_x"]))
	var approach_t := clampf((float(e["start_x"]) - float(e["x"])) / span, 0.0, 1.0)
	var base_s := lerpf(0.74, 1.04, lane_t)
	var unit := e["node"] as Control
	var s := base_s * lerpf(0.86, 1.0, approach_t)
	unit.scale = Vector2(s, s)
	unit.modulate = Color(1, 1, 1, lerpf(0.7, 1.0, lane_t) * lerpf(0.62, 1.0, approach_t))


## True while the party has met enemies and stopped to fight (an engaged foe or
## a boss on the field). Travel (background scroll + hero stride) freezes here.
func _in_combat() -> bool:
	if not _boss_entry.is_empty():
		return true
	for e in _enemies:
		if String(e["state"]) == "engaged":
			return true
	return false


## A sim kill landed. Drop an ENGAGED foe (focus first, else most-worn, elite
## last). If nothing has engaged yet, HOLD the kill (deferred) rather than snipe
## an approacher mid-runway — _process drains held kills onto foes as they
## arrive, so deaths always land at the clash. NO mid-wave respawn.
func _on_enemy_killed() -> void:
	if not _kill_engaged_victim():
		_pending_kills += 1


## Kill one engaged foe (focus first, else most-worn, elite last). Returns false
## if none is engaged (nothing to kill yet).
func _kill_engaged_victim() -> bool:
	var victim: Dictionary = {}
	if _focus_valid() and String(_focus["state"]) == "engaged":
		victim = _focus
	if victim.is_empty():
		# No focus → drop the front-most engaged foe (smallest x at the clash), so
		# kills always land on the leading monster (elites engage a step back, so
		# they fall last on their own).
		var best_x := INF
		for e in _enemies:
			if String(e["state"]) != "engaged":
				continue
			if float(e["x"]) < best_x:
				best_x = float(e["x"])
				victim = e
	if victim.is_empty():
		return false
	if is_same(victim, _focus):
		_focus = {}  # focus died → retarget next frame
	_kill_entry(victim)
	return true


## Flatten-and-fade a token, then free it. Idempotent (safe for overlapping
## tweens, or a boss cleared by both defeat and a stage change).
func _kill_entry(entry: Dictionary) -> void:
	if entry.is_empty() or not _enemies.has(entry) or String(entry["state"]) == "dying":
		return
	entry["state"] = "dying"
	var unit := entry["node"] as Control
	var sprite: Variant = entry["sprite"]
	_bobs = _bobs.filter(func(b: Dictionary) -> bool: return not is_same(b["node"], sprite))
	var tw := unit.create_tween()
	tw.set_parallel(true)
	tw.tween_property(unit, "scale:y", 0.06, 0.3).set_ease(Tween.EASE_IN)
	tw.tween_property(unit, "modulate:a", 0.0, 0.32)
	tw.chain().tween_callback(func() -> void:
		_enemies.erase(entry)
		unit.queue_free())


## Discrete waves: a fresh batch of per_wave minions marches in when the wave
## advances — only once the previous wave is cleared (no mid-wave respawn), so
## the field empties between waves. Boss / mini-boss waves are a single token
## spawned by _on_boss_started, so they refill nothing here.
func _on_sim_wave_advanced(_wave: int) -> void:
	if size.x < 4.0 or not _boss_entry.is_empty():
		return  # a boss owns the field; trash refills once it is defeated
	# Fade any living straggler (a kill that found no victim) so the per-wave
	# count stays exact, then stage a fresh staggered batch.
	for e in _enemies.duplicate():
		if String(e["state"]) != "dying" and not is_same(e, _boss_entry):
			_kill_entry(e)
	_spawn_queue.clear()
	_pending_kills = 0  # held kills from the cleared wave don't carry over
	if Balance.wave_kind(CombatSim.act, CombatSim.stage, CombatSim.wave) != "normal":
		return  # the boss token spawns from sim_boss_started
	# Stage the data-driven monster lineup (count + types + spawn times) for this
	# wave; each entry marches in at its authored/auto time.
	for entry in GameContent.wave_plan(CombatSim.act, CombatSim.stage, CombatSim.wave):
		_spawn_queue.append({"at": _t + float(entry.get("at", 0.0)), "plan": entry})


# =========================================================================
# Hero focusing (presentation only — never feeds the sim)
# =========================================================================

func _focus_valid() -> bool:
	return not _focus.is_empty() and _enemies.has(_focus) and String(_focus["state"]) != "dying"


## Nearest non-dying enemy to the hero (smallest x); an engaged token always
## outranks an approaching one (the hero fights what's in front of it first).
func _nearest_enemy() -> Dictionary:
	var best: Dictionary = {}
	var best_score := INF
	for e in _enemies:
		if String(e["state"]) == "dying":
			continue
		var score := float(e["x"]) - (1000.0 if String(e["state"]) == "engaged" else 0.0)
		if score < best_score:
			best_score = score
			best = e
	return best


## Lock the front-most foe and hit it until it dies, then move to the next. Keep
## the current focus while it stays engaged (committed); otherwise grab the
## front-most engaged foe (smallest x at the clash), or the nearest approacher
## when nothing has reached the clash yet.
func _retarget_focus() -> void:
	if _focus_valid() and String(_focus["state"]) == "engaged":
		return
	_focus = _front_most_enemy()
	_face_hero_at_focus()


## The foe the hero should be shooting: the front-most ENGAGED token (closest to
## the hero at the clash line); if none has engaged yet, the nearest approacher.
func _front_most_enemy() -> Dictionary:
	var best: Dictionary = {}
	var best_x := INF
	for e in _enemies:
		if String(e["state"]) != "engaged":
			continue
		if float(e["x"]) < best_x:
			best_x = float(e["x"])
			best = e
	if not best.is_empty():
		return best
	return _nearest_enemy()


## Flip the hero sprite toward the focus. In the side view foes are always to the
## right, so this resolves to facing right — but it stays general + no-ops on an
## empty lineup (a lineup swap can clear the field mid-frame).
func _face_hero_at_focus() -> void:
	if _hero_units.is_empty():
		return
	var spr := _hero_units[0].get_meta("sprite") as Control
	if spr == null:
		return
	var face := 1.0
	if not _focus.is_empty() and float(_focus.get("x", 1.0)) < HERO_X:
		face = -1.0
	spr.scale.x = face


# =========================================================================
# Coherent attacks: ranged fire / melee range-gate → impact on the target
# =========================================================================

func _projectile_spec_for_active() -> Dictionary:
	var lineup := GameContent.active_party()
	if lineup.is_empty():
		return {}
	return GameContent.projectile_spec(String((lineup[0] as Dictionary).get("class_id", "")))


## The hero attacks the focus on a speed-scaled cadence: ranged fires at any
## distance; melee only strikes once the focus is within reach (it waits while
## the foe is still closing — range now matters).
func _update_attack_cadence(delta: float, spd: float) -> void:
	var spec := _projectile_spec_for_active()
	if _hero_units.is_empty() or spec.is_empty() or not _focus_valid():
		return
	_fire_accum += delta * spd
	var acts := 0
	while _fire_accum >= FIRE_INTERVAL and acts < 2:
		if bool(spec.get("ranged", false)):
			_fire_accum -= FIRE_INTERVAL
			acts += 1
			_fire_projectile(spec)
		elif _focus_in_melee_range():
			_fire_accum -= FIRE_INTERVAL
			acts += 1
			_melee_strike(spec)
		else:
			# Out of reach — the hero waits; cap the banked time so it can't burst
			# a flurry the instant the foe arrives.
			_fire_accum = minf(_fire_accum, FIRE_INTERVAL)
			break


func _focus_in_melee_range() -> bool:
	return _focus_valid() and String(_focus["state"]) == "engaged" and float(_focus["x"]) <= CLASH_X + MELEE_RANGE


func _enemy_screen_center(e: Dictionary) -> Vector2:
	var n := e["node"] as Control
	return n.position + n.size * Vector2(0.5, 0.42)


## A cosmetic projectile flying hero → focus. The TARGET entry is captured so the
## hit lands on it even if it dies mid-flight (reads as the killing blow).
func _fire_projectile(spec: Dictionary) -> void:
	if _hero_units.is_empty() or not _focus_valid() or _projectiles.size() >= MAX_PROJECTILES:
		return
	var target := _focus
	var from := _hero_screen_center()
	var to := _enemy_screen_center(target)
	var is_arrow := String(spec.get("shape", "orb")) == "arrow"
	var p := _Projectile.new(String(spec.get("shape", "orb")), _proj_color(String(spec.get("color_key", "ember"))), bool(spec.get("sparkle", false)))
	p.size = Vector2(34, 8) if is_arrow else Vector2(18, 18)
	p.pivot_offset = p.size * 0.5
	if is_arrow:
		p.rotation = (to - from).angle()
	_proj_holder.add_child(p)
	p.position = from - p.size * 0.5
	# Constant visual speed: dur scales with the real hero→foe distance, so the bolt
	# crosses pixels at a fixed rate whatever the range (near stops crawling, far
	# stops streaking). Anchored to the clash-line gap so a shot at the line keeps
	# today's pacing; spec.speed still sets the per-class rate (mage 3× slower).
	var dist := from.distance_to(to)
	var ref := maxf(1.0, (CLASH_X - HERO_X) * size.x)
	var dur := clampf(0.34 / maxf(0.1, float(spec.get("speed", 1.0))) * (dist / ref), 0.06, 2.0)
	_projectiles.append({"node": p, "from": from, "to": to, "t": 0.0, "dur": dur, "impact": String(spec.get("impact", "none")), "target": target, "spec": spec})


func _update_projectiles(delta: float, spd: float) -> void:
	var keep: Array[Dictionary] = []
	for p in _projectiles:
		var node: Variant = p["node"]
		if not is_instance_valid(node):
			continue
		var ctrl := node as Control
		p["t"] = float(p["t"]) + delta * spd / maxf(0.01, float(p["dur"]))
		if float(p["t"]) >= 1.0:
			ctrl.position = (p["to"] as Vector2) - ctrl.size * 0.5
			_on_impact(p["target"], p["spec"], p["to"])
			_impact(p)
			continue
		ctrl.position = (p["from"] as Vector2).lerp(p["to"], float(p["t"])) - ctrl.size * 0.5
		keep.append(p)
	_projectiles = keep


func _impact(p: Dictionary) -> void:
	var node: Variant = p["node"]
	if not is_instance_valid(node):
		return
	var ctrl := node as Control
	if String(p["impact"]) == "flash":
		var tw := ctrl.create_tween()
		tw.set_parallel(true)
		tw.tween_property(ctrl, "scale", ctrl.scale * 1.8, 0.14)
		tw.tween_property(ctrl, "modulate:a", 0.0, 0.16)
		tw.chain().tween_callback(ctrl.queue_free)
	else:
		ctrl.queue_free()


## Melee classes: a quick lunge of the hero toward the focus, with the hit
## landing at the apex.
func _melee_strike(spec: Dictionary) -> void:
	if _hero_units.is_empty() or not _focus_valid():
		return
	var target := _focus
	var hero := _hero_units[0]
	if not bool(hero.get_meta("lunging", false)):
		hero.set_meta("lunging", true)
		var base: Vector2 = hero.position
		# Dash most of the way to the foe (stopping just short), strike, dash back
		# — the warrior visibly closes the distance to land the blow.
		var reach := _enemy_screen_center(target) - (base + hero.size * 0.5)
		var dash := base + reach * 0.66
		var tw := hero.create_tween()
		tw.tween_property(hero, "position", dash, 0.11).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(hero, "position", base, 0.18).set_trans(Tween.TRANS_SINE)
		tw.tween_callback(func() -> void: hero.set_meta("lunging", false))
	_on_impact(target, spec, _enemy_screen_center(target))


## The coherence core: a landed hit mints a damage number ON the struck foe,
## flashes it, and drains its cosmetic HP bar by a hit-count budget (NOT
## party_dps — that would desync from the sim's 8-kill cadence). The kill itself
## stays authoritative (sim_enemy_killed); this only makes the hit READ true.
func _on_impact(entry: Variant, _spec: Dictionary, at: Vector2) -> void:
	var crit := _rng.randf() < CRIT_CHANCE
	var amount := int(CombatSim.party_dps * _rng.randf_range(DMG_FRAC_LO, DMG_FRAC_HI))
	if crit:
		amount = int(float(amount) * CRIT_MULT)
	_spawn_number(at, maxi(1, amount), crit)
	if typeof(entry) != TYPE_DICTIONARY or (entry as Dictionary).is_empty():
		return
	var e: Dictionary = entry
	if not _enemies.has(e) or String(e["state"]) == "dying":
		return
	# Flash the struck sprite.
	var spr: Variant = e.get("sprite")
	if is_instance_valid(spr):
		var sc := spr as CanvasItem
		var tw := sc.create_tween()
		sc.modulate = Color(1.7, 1.5, 1.4, sc.modulate.a)
		tw.tween_property(sc, "modulate", Color(1, 1, 1, 1), 0.18)
	# Drain the cosmetic bar (the boss bar is sim-owned — leave it).
	if not is_same(e, _boss_entry):
		e["hp_pct"] = maxf(HP_FLOOR, float(e["hp_pct"]) - HP_DRAIN_PER_HIT * 100.0)
		var bar: Variant = e.get("bar")
		if is_instance_valid(bar):
			(bar as StatBar).pct = float(e["hp_pct"])


## A damage number that pops at a screen point and floats up (reuses the floater
## idiom; anchored on the target rather than a fixed clash point).
func _spawn_number(at: Vector2, amount: int, crit: bool) -> void:
	if _floater_holder == null or size.x < 4.0:
		return
	if not UserSettings.get_bool("dmg_numbers"):  # Options · Combat
		return
	while _floater_holder.get_child_count() >= _MAX_FLOATERS:
		var old := _floater_holder.get_child(0)
		_floater_holder.remove_child(old)
		old.queue_free()
	var col := Palette.EMBER_BRIGHT if crit else Palette.DMG_CREAM
	var fsize := 24 if crit else 16
	var lbl := Style.pixel_label(Style.group_int(amount), fsize, col)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("shadow_offset_x", 0)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	if crit:
		lbl.add_theme_constant_override("outline_size", 10)
		lbl.add_theme_color_override("font_outline_color", Palette.with_alpha(Palette.EMBER, 0.4 * Palette.GLOW))
	_floater_holder.add_child(lbl)
	lbl.reset_size()
	lbl.pivot_offset = lbl.size * 0.5
	var jx := _rng.randf_range(-10.0, 10.0)
	var py := at.y
	lbl.position = Vector2(at.x - lbl.size.x * 0.5 + jx, py + 6.0)
	lbl.scale = Vector2(0.7, 0.7)
	lbl.modulate = Color(1, 1, 1, 0.0)
	var tw := lbl.create_tween()
	tw.tween_property(lbl, "position:y", py - 6.0, 0.198)
	tw.parallel().tween_property(lbl, "scale", Vector2(1.08, 1.08), 0.198)
	tw.parallel().tween_property(lbl, "modulate:a", 1.0, 0.198)
	tw.tween_property(lbl, "position:y", py - 16.0, 0.242)
	tw.parallel().tween_property(lbl, "scale", Vector2.ONE, 0.242)
	tw.tween_property(lbl, "position:y", py - 52.0, 0.62)
	tw.parallel().tween_property(lbl, "scale", Vector2(0.96, 0.96), 0.62)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.62)
	tw.tween_callback(lbl.queue_free)


# =========================================================================
# Real boss waves: ONE distinct token at the clash line (HUD banner unchanged)
# =========================================================================

func _on_boss_started(_id: String, boss_name: String, tier: String, _max_hp: float) -> void:
	# Clear ALL living minions (not just a cosmetic elite) so only the boss holds
	# the field — the wave reaper early-returns once a boss is up.
	for e in _enemies.duplicate():
		if String(e["state"]) != "dying":
			_kill_entry(e)
	_boss_entry = _spawn_boss_token(boss_name, tier)
	_focus = _boss_entry
	_face_hero_at_focus()


func _on_boss_defeated(_id: String) -> void:
	_clear_boss_token()


## Retreat / offline-collect change the stage WITHOUT a sim_boss_defeated, so
## clear any lingering boss token on a stage change too.
func _on_stage_changed_clear_boss(_label: String, _stage_name: String) -> void:
	_clear_boss_token()


func _clear_boss_token() -> void:
	if _boss_entry.is_empty():
		return
	if is_same(_focus, _boss_entry):
		_focus = {}
	_kill_entry(_boss_entry)
	_boss_entry = {}


## Mirror the HUD boss HP bar onto the field token (presentation only).
func _on_boss_hp_field(fill: float) -> void:
	if not _boss_entry.is_empty() and _enemies.has(_boss_entry):
		(_boss_entry["bar"] as StatBar).pct = clampf(fill, 0.0, 1.0) * 100.0


## One big, named, glowing boss token planted at the clash line (engaged — it
## doesn't approach, it IS the wave). Added to _enemies so the focus + projectile
## helpers target it unchanged.
func _spawn_boss_token(boss_name: String, tier: String) -> Dictionary:
	var col := Palette.R_MYTHIC if tier == "boss" else Palette.R_EPIC
	var usz := _BOSS_SIZE
	var unit := Control.new()
	unit.size = usz
	unit.pivot_offset = Vector2(usz.x * 0.5, usz.y)
	unit.mouse_filter = Control.MOUSE_FILTER_STOP
	unit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	Tip.attach(unit, func() -> Dictionary: return {
		"name": boss_name,
		"type": ("FLOOR BOSS" if tier == "boss" else "MINI-BOSS") + " · Stage " + CombatSim.stage_label(),
		"rarity": "mythic" if tier == "boss" else "epic",
		"stats": [["Threat", "Extreme" if tier == "boss" else "High"]],
	})

	var shadow := _Shadow.new(0.7)
	shadow.size = Vector2(120, 24)
	shadow.position = Vector2(usz.x * 0.5 - 60.0, usz.y - 14.0)
	unit.add_child(shadow)

	var sprite := UnitSprite.new("enemy.elite", boss_name, true)
	sprite.size = usz
	sprite.pivot_offset = usz * 0.5
	sprite.scale.x = -1.0  # face the party
	unit.add_child(sprite)
	sprite.play("walk")

	var glow := Panel.new()
	var gsb := StyleBoxFlat.new()
	gsb.draw_center = false
	gsb.set_border_width_all(2)
	gsb.border_color = col
	gsb.set_corner_radius_all(4)
	gsb.shadow_color = Palette.with_alpha(col, 0.55 * Palette.GLOW)
	gsb.shadow_size = int(30 * Palette.GLOW)
	glow.add_theme_stylebox_override("panel", gsb)
	glow.size = usz
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	unit.add_child(glow)

	var bar := StatBar.new("hp", 100.0, 7.0)
	bar.size = Vector2(usz.x, 7.0)
	bar.position = Vector2(0.0, -12.0)
	unit.add_child(bar)

	_units_holder.add_child(unit)
	unit.set_meta("sprite", sprite)
	unit.set_meta("bar", bar)
	unit.set_meta("depth_bias", 8.0)
	var bx := CLASH_X + 0.06
	var entry := {
		"node": unit, "sprite": sprite, "bar": bar,
		"x": bx, "lane": 1, "start_x": bx, "engage_x": bx,
		"speed": 0.0, "elite": true, "hp_pct": 100.0, "state": "engaged",
	}
	_enemies.append(entry)
	_pos_ground(unit, bx, 1)
	_bobs.append({"node": sprite, "base": Vector2.ZERO, "kind": "approach", "period": 2.4, "delay": 0.0})
	if _world3d != null:
		_hide_2d_body(unit)
	return entry


# =========================================================================
# Battle caches (clickable chests; contents decided by the backend)
# =========================================================================

## Drop a cache on the ground ahead of the party; it scrolls left with the world.
func _spawn_chest() -> void:
	var unit := _make_chest_node()
	_units_holder.add_child(unit)
	var lane := _rng.randi_range(0, LANES.size() - 1)
	var x := _rng.randf_range(0.6, 0.95)
	var entry := {"node": unit, "glow": unit.get_meta("glow"), "x": x, "lane": lane, "life": CHEST_LIFE, "opening": false}
	_chests.append(entry)
	_pos_ground(unit, x, lane)
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

	var sprite := PixelSlot.new("chest", true, "chest", "")
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


## The click: the backend rolls the reward (mock mirrors it), then the chest
## bursts and the result floats up where it stood.
func _open_chest(entry: Dictionary) -> void:
	if bool(entry["opening"]):
		return
	entry["opening"] = true
	var at := _chest_screen_point(entry)
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
	# Mirror the real chest reward into the right-side activity log.
	var who := GameState.player_name if GameState.player_name != "" else "You"
	match String(reward["kind"]):
		"gold":
			EventBus.sim_loot.emit([who, "looted", "+%s gold" % Style.group_int(int(reward["gold"])), "common"])
		"materials":
			EventBus.sim_loot.emit([who, "looted", "+%d iron ingots" % int(reward["iron"]), "uncommon"])
		"item":
			var it: Dictionary = reward["item"]
			if bool(reward["banked"]):
				EventBus.sim_loot.emit([who, "looted", String(it["n"]), String(it["r"])])
			else:
				EventBus.sim_loot.emit([who, "looted", "+%s gold" % Style.group_int(int(reward["gold"])), "common"])
	_despawn_chest(entry, true)


func _chest_screen_point(entry: Dictionary) -> Vector2:
	# Top-center of the chest wherever it sits — its node is placed by _pos_ground,
	# so this inherits the 2D or projected-3D placement.
	var n := entry["node"] as Control
	return n.position + Vector2(n.size.x * 0.5, 0.0)


## Opened: burst (flash + squash). Expired/missed: sink and fade. Idempotent —
## a chest can only leave _chests once (its glow pulse must be unregistered
## exactly when the node is freed, or _process casts a freed object).
func _despawn_chest(entry: Dictionary, opened: bool) -> void:
	if not _chests.has(entry):
		return
	_chests.erase(entry)
	var unit := entry["node"] as Control
	var glow := entry["glow"] as CanvasItem
	_pulses = _pulses.filter(func(p: Dictionary) -> bool: return not is_same(p["node"], glow))
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
func _chest_floater(at: Vector2, text: String, col: Color, fsize: int) -> void:
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
	var py := at.y
	lbl.position = Vector2(at.x - lbl.size.x * 0.5, py)
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


# =========================================================================
# Floating HEAL numbers (EventBus.sim_floater) — damage numbers are now minted
# on impact (_on_impact); only heals arrive via the sim, anchored on the hero.
# =========================================================================

func _on_floater(kind: String, amount: int, _hero_idx: int) -> void:
	if kind != "heal":
		return  # damage / crit numbers are self-minted on the struck enemy
	if _floater_holder == null or size.x < 4.0 or _hero_units.is_empty():
		return
	if not UserSettings.get_bool("dmg_numbers"):  # Options · Combat
		return
	while _floater_holder.get_child_count() >= _MAX_FLOATERS:
		var old := _floater_holder.get_child(0)
		_floater_holder.remove_child(old)
		old.queue_free()
	var lbl := Style.pixel_label("+" + str(amount), 16, Palette.HEAL_GREEN)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("shadow_offset_x", 0)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	_floater_holder.add_child(lbl)
	lbl.reset_size()
	lbl.pivot_offset = lbl.size * 0.5
	var at := _hero_screen_center() + Vector2(_rng.randf_range(-10.0, 10.0), -28.0)
	var py := at.y
	lbl.position = Vector2(at.x - lbl.size.x * 0.5, py + 6.0)
	lbl.scale = Vector2(0.7, 0.7)
	lbl.modulate = Color(1, 1, 1, 0.0)
	var tw := lbl.create_tween()
	tw.tween_property(lbl, "position:y", py - 6.0, 0.198)
	tw.parallel().tween_property(lbl, "scale", Vector2(1.08, 1.08), 0.198)
	tw.parallel().tween_property(lbl, "modulate:a", 1.0, 0.198)
	tw.tween_property(lbl, "position:y", py - 44.0, 0.78)
	tw.parallel().tween_property(lbl, "scale", Vector2(0.96, 0.96), 0.78)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.78)
	tw.tween_callback(lbl.queue_free)


# =========================================================================
# Forward-travel parallax + chest scroll
# =========================================================================

func _scroll_parallax(delta: float, spd: float) -> void:
	for layer in _bg_layers:
		var node := layer["node"] as _ParallaxLayer
		node.scroll_x += SCROLL_SPEED * float(layer["factor"]) * spd * delta
		node.queue_redraw()
	var drift_x := (SCROLL_SPEED / maxf(1.0, size.x)) * spd * delta
	# Scenery props drift past at lane-based rates (parallax depth) and WRAP back
	# to the right when they scroll off — never freed, so no per-frame-cast risk.
	for pr in _props:
		pr["x"] = float(pr["x"]) - drift_x * float(pr["rate"])
		if float(pr["x"]) < DESPAWN_X - 0.05:
			pr["x"] = float(pr["x"]) + _rng.randf_range(1.6, 2.2)
		_pos_ground(pr["node"], float(pr["x"]), int(pr["lane"]))
	# Chests are ground objects: they drift left with the near layer and are gone
	# once they scroll off behind the party.
	var gone: Array = []
	for ch in _chests:
		ch["x"] = float(ch["x"]) - drift_x
		_pos_ground(ch["node"], float(ch["x"]), int(ch["lane"]))
		if not bool(ch["opening"]) and float(ch["x"]) < DESPAWN_X:
			gone.append(ch)
	for ch in gone:
		ch["opening"] = true
		_despawn_chest(ch, false)


## Spawn one piece of drifting scenery at fraction [param x].
func _spawn_prop(x: float) -> void:
	var kind := _PROP_KINDS[_rng.randi_range(0, _PROP_KINDS.size() - 1)]
	var lane := _rng.randi_range(0, LANES.size() - 1)
	var node := _make_prop(kind, lane)
	_prop_holder.add_child(node)
	var lane_t := float(lane) / float(maxi(1, LANES.size() - 1))
	_props.append({"node": node, "x": x, "lane": lane, "rate": lerpf(0.55, 1.05, lane_t)})
	_pos_ground(node, x, lane)


## A scenery prop (sprite from props.dungeon, lane-scaled for depth). Braziers
## get a flame glow that pulses on the battlefield clock.
func _make_prop(kind: String, lane: int) -> Control:
	var lane_t := float(lane) / float(maxi(1, LANES.size() - 1))
	var base: Vector2 = _PROP_SIZES.get(kind, Vector2(72, 92))
	var sz := base * lerpf(0.72, 1.16, lane_t)
	var unit := Control.new()
	unit.size = sz
	unit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	unit.modulate = Color(1, 1, 1, lerpf(0.5, 0.95, lane_t))  # far props read hazier

	var shadow := _Shadow.new(0.5)
	shadow.size = Vector2(sz.x * 0.7, 13)
	shadow.position = Vector2(sz.x * 0.5 - shadow.size.x * 0.5, sz.y - 8.0)
	unit.add_child(shadow)

	var sprite := PixelSlot.new(kind, false, "props.dungeon", kind)
	sprite.size = sz
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	unit.add_child(sprite)

	if kind == "brazier":
		var border := Panel.new()
		var bsb := StyleBoxFlat.new()
		bsb.draw_center = false
		bsb.set_border_width_all(1)
		bsb.border_color = Palette.EMBER_DEEP
		bsb.set_corner_radius_all(3)
		bsb.shadow_color = Palette.with_alpha(Palette.EMBER, 0.35 * Palette.GLOW)
		bsb.shadow_size = int(20 * Palette.GLOW)
		border.add_theme_stylebox_override("panel", bsb)
		border.size = sz
		border.mouse_filter = Control.MOUSE_FILTER_IGNORE
		unit.add_child(border)
		var flame := _Flame.new()
		flame.size = Vector2(sz.x * 0.6, sz.y * 0.36)
		flame.position = Vector2(sz.x * 0.5 - flame.size.x * 0.5, -6.0)
		unit.add_child(flame)
		_pulses.append({"node": flame, "period": 1.8, "delay": _rng.randf(), "min": 0.5, "max": 1.0})
	return unit


# =========================================================================
# Layout
# =========================================================================

## Anchor a node's feet on the ground line of [param lane] at fraction [param x].
## In 2.5D the ground point is the projection of the (x, lane) world position
## through the 3D camera, so the 2D node (HP bar / chest / floater anchor) lands
## exactly on its 3D model; otherwise the flat 2D layout is used.
func _pos_ground(node: Control, x: float, lane: int) -> void:
	if _world3d != null and size.x >= 4.0:
		var gp := _world3d.project(_bf_world(x, lane))
		node.position = gp - Vector2(node.size.x * 0.5, node.size.y)
		return
	var y := GROUND_Y + LANES[clampi(lane, 0, LANES.size() - 1)]
	node.position = Vector2(size.x * x - node.size.x * 0.5, size.y * y - node.size.y)


# =========================================================================
# 2.5D world (Combat3DView): combatants as 3D models on a side-camera grid
# =========================================================================

## Map the side-scroller's (x fraction, lane) to a sim world position: x spreads
## along the band (world X, hero at 0); lane gives depth (world Z, near lane toward
## the camera). Fed to Combat3DView.to3 / .project / .focus so 2D + 3D agree.
func _bf_world(x: float, lane: int) -> Vector2:
	return Vector2((x - HERO_X) * BF_BAND, float(lane - 1) * BF_DEPTH)


## The 3D model key for an enemy entry (boss / elite / trash).
func _enemy_kind3d(e: Dictionary) -> String:
	if is_same(e, _boss_entry):
		return "boss"
	if bool(e.get("elite", false)):
		return "enemy_brute"
	return "enemy_grunt"


## Place the 3D combatants (hero + every enemy, incl. the boss) at their world
## positions, facing across the band. Pooled + trimmed by Combat3DView; the 2D
## bodies are hidden, so only the bars / numbers / chests remain on top.
func _render3d_fight() -> void:
	var v := _world3d
	var party := GameContent.active_party()
	for i in _hero_units.size():
		var cls := "class_warrior"
		if i < party.size():
			cls = "class_" + String((party[i] as Dictionary).get("class_id", "warrior"))
		var hn := v.node("hero", i, cls)
		hn.position = v.to3(_bf_world(HERO_X, 1))
		hn.look_at(hn.position + Vector3(1.0, 0.0, 0.0), Vector3.UP)  # face the foes (+X)
	v.trim("hero", _hero_units.size())
	for i in _enemies.size():
		var e: Dictionary = _enemies[i]
		var en := v.node("enemy", i, _enemy_kind3d(e))
		en.position = v.to3(_bf_world(float(e["x"]), int(e["lane"])))
		en.look_at(en.position + Vector3(-1.0, 0.0, 0.0), Vector3.UP)  # face the hero (-X)
	v.trim("enemy", _enemies.size())


## In 2.5D, hide a unit's 2D body (sprite / shadow / ring / glow / pet) but keep
## its HP bar — the 3D model is the body; the bar floats above it.
func _hide_2d_body(unit: Control) -> void:
	for c in unit.get_children():
		if c is StatBar:
			continue
		var ci := c as CanvasItem
		if ci != null:
			ci.visible = false


func _proj_color(key: String) -> Color:
	match key:
		"cyan":
			return Palette.CYAN_BRIGHT
		"gold":
			return Palette.GOLD_BRIGHT
		_:
			return Palette.EMBER_BRIGHT


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


## Painter re-sort: children ordered by feet y (+ bias) as units move.
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


# =========================================================================
# Draw-layer classes
# =========================================================================

## Static cavern backdrop: vertical gradient, a stone floor band, a warm hearth
## glow at the party (left) and a red danger glow where foes pour in (right).
class _Backdrop:
	extends Control

	var ground := 0.66

	func _init(p_ground: float) -> void:
		ground = p_ground
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		resized.connect(queue_redraw)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w < 2.0 or h < 2.0:
			return
		var gy := h * ground
		# Cavern gradient (top dark → warmer at the floor line).
		var top := Color("0c0a08")
		var low := Color("17110b")
		draw_polygon(
			PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, gy), Vector2(0, gy)]),
			PackedColorArray([top, top, low, low]))
		# Stone floor band.
		var floor_top := Color("1b150e")
		var floor_bot := Color("100b08")
		draw_polygon(
			PackedVector2Array([Vector2(0, gy), Vector2(w, gy), Vector2(w, h), Vector2(0, h)]),
			PackedColorArray([floor_top, floor_top, floor_bot, floor_bot]))
		draw_line(Vector2(0, gy), Vector2(w, gy), Color(0, 0, 0, 0.35), 2.0)
		# Hearth glow at the party (left), danger glow at the spawn side (right).
		_blob(Vector2(0.16 * w, gy), 0.34 * w, 0.30 * h, Palette.with_alpha(Palette.EMBER, 0.18))
		_blob(Vector2(0.92 * w, gy - 0.10 * h), 0.40 * w, 0.34 * h, Palette.with_alpha(Palette.HP, 0.13))

	func _blob(c: Vector2, rx: float, ry: float, col: Color, steps: int = 14) -> void:
		if rx < 1.0:
			return
		draw_set_transform(c, 0.0, Vector2(1.0, ry / rx))
		var a := col.a / float(steps)
		for i in steps:
			draw_circle(Vector2.ZERO, rx * (1.0 - float(i) / float(steps)), Color(col.r, col.g, col.b, a))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A scrolling silhouette band (far arches / mid pillars / near floor stones),
## tiled across the width and phase-shifted by scroll_x (fposmod wrap).
class _ParallaxLayer:
	extends Control

	var kind := "mid"
	var ground := 0.66
	var scroll_x := 0.0
	var _tile := 320.0
	var _col := Color("0a0807")
	var _tex: Texture2D = null
	var _surf := 0.0  # >0: image walking-surface fraction to pin onto the ground line

	func _init(p_kind: String, p_ground: float, p_tex: Texture2D = null, p_surf: float = 0.0) -> void:
		kind = p_kind
		ground = p_ground
		_tex = p_tex
		_surf = p_surf
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		match kind:
			"far":
				_tile = 300.0
				_col = Color(0.10, 0.08, 0.07, 0.6)
			"mid":
				_tile = 360.0
				_col = Color(0.07, 0.055, 0.045, 0.8)
			_:
				_tile = 130.0
				_col = Color(0.0, 0.0, 0.0, 0.4)

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		resized.connect(queue_redraw)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w < 2.0 or h < 2.0:
			return
		if _tex != null:
			_draw_texture_tiled(w, h)
			return
		var gy := h * ground
		var off := fposmod(scroll_x, _tile)
		var x := -off - _tile
		while x < w + _tile:
			match kind:
				"far":
					_arch(x + _tile * 0.5, gy, h)
				"mid":
					_pillar(x + _tile * 0.5, gy, h)
				_:
					_stones(x, gy)
			x += _tile

	## Tile the layer texture across the width at full height, so its painted
	## floor-line (two-thirds down the image) lands on the battlefield ground line.
	## Wrapped horizontally by scroll_x (fposmod), like the procedural bands.
	func _draw_texture_tiled(w: float, h: float) -> void:
		var ts := _tex.get_size()
		if ts.x <= 0.0 or ts.y <= 0.0:
			return
		var sh := h     # drawn height
		var ty := 0.0   # top y
		if _surf > 0.0 and _surf < 1.0:
			# Pin the image's walking-surface line onto the ground line and stretch
			# the part below it down to the screen bottom (so the floor fills under).
			sh = h * (1.0 - ground) / (1.0 - _surf)
			ty = h * ground - _surf * sh
		var tile := sh * ts.x / ts.y  # aspect-preserving width
		if tile < 1.0:
			return
		var off := fposmod(scroll_x, tile)
		var x := -off - tile
		while x < w + tile:
			draw_texture_rect(_tex, Rect2(x, ty, tile, sh), false)
			x += tile

	func _arch(cx: float, gy: float, h: float) -> void:
		# Faint pointed-arch silhouette set back above the floor.
		var top := gy - h * 0.34
		var half := _tile * 0.22
		var pts := PackedVector2Array([
			Vector2(cx - half, gy), Vector2(cx - half, top + 18.0),
			Vector2(cx, top), Vector2(cx + half, top + 18.0),
			Vector2(cx + half, gy)])
		var cols := PackedColorArray()
		for _i in pts.size():
			cols.append(_col)
		draw_polygon(pts, cols)

	func _pillar(cx: float, gy: float, h: float) -> void:
		var top := gy - h * 0.5
		var half := 16.0
		draw_rect(Rect2(cx - half, top, half * 2.0, gy - top), _col)
		# Capital + base.
		draw_rect(Rect2(cx - half - 5.0, top, half * 2.0 + 10.0, 12.0), _col)
		draw_rect(Rect2(cx - half - 5.0, gy - 12.0, half * 2.0 + 10.0, 12.0), _col)

	func _stones(x: float, gy: float) -> void:
		# Short ground seams just below the floor line.
		for i in 3:
			var sx := x + float(i) * (_tile / 3.0)
			draw_line(Vector2(sx, gy + 10.0), Vector2(sx + 26.0, gy + 10.0), _col, 2.0)


## Cosmetic attack projectile: "arrow" = bright streak + tip (rotated to its
## flight angle); "orb" = arcane bolt (glow ring + hot core + optional sparkle).
class _Projectile:
	extends Control

	var shape := "orb"
	var col := Color.WHITE
	var sparkle := false

	func _init(p_shape: String, p_col: Color, p_sparkle: bool) -> void:
		shape = p_shape
		col = p_col
		sparkle = p_sparkle
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var c := size * 0.5
		if shape == "arrow":
			draw_line(Vector2(2.0, c.y), Vector2(size.x - 2.0, c.y), Palette.with_alpha(col, 0.5), 5.0, true)
			draw_line(Vector2(size.x * 0.45, c.y), Vector2(size.x - 1.0, c.y), col, 3.0, true)
			draw_circle(Vector2(size.x - 2.0, c.y), 3.0, Color(1, 1, 1, 0.9))
		else:
			draw_circle(c, size.x * 0.5, Palette.with_alpha(col, 0.22))
			draw_circle(c, size.x * 0.3, Palette.with_alpha(col, 0.6))
			draw_circle(c, size.x * 0.17, Color(1, 1, 1, 0.95))
			if sparkle:
				draw_circle(c + Vector2(size.x * 0.22, -size.x * 0.18), 1.6, Color(1, 1, 1, 0.85))


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


## Elliptical ground shadow under units.
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


## Lunge motion trail: red streak fading along +x, mirrored by the caller.
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


## Brazier flame glow (alpha pulsed by the battlefield clock via _pulses).
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
