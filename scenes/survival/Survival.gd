extends Control
## SURVIVAL — bullet-hell side mode (vampire-survivors style). Presentation +
## input for a headless SurvivalSim: enemies pour in from every angle, the
## delver auto-attacks (hunter/mage fire projectiles, warrior/rogue swing a
## blade aura), and every stage cleared offers a 3-card enhancement draft.
## Move with WASD / arrows. Combat is powered by the hero's idle gear loadout.
## Map art is a placeholder; the user supplies real assets later.

const _Sim := preload("res://systems/survival/SurvivalSim.gd")
const _Draft := preload("res://scenes/survival/SurvivalDraft.gd")
const _GameOver := preload("res://scenes/survival/SurvivalGameOver.gd")

var _sim: SurvivalSim
var _arena: _Arena
var _player_sprite: UnitSprite
var _font: Font

var _hp_fill: ColorRect
var _hp_lbl: Label
var _stage_lbl: Label
var _time_lbl: Label
var _score_lbl: Label
var _kills_lbl: Label
var _chips: HBoxContainer

var _draft_open := false
var _over_open := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_font = Fonts.pixel()

	var bg := ColorRect.new()
	bg.color = Color("0a0807")
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_arena = _Arena.new()
	_arena.host = self
	_arena.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_arena)
	_arena.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_player_sprite = UnitSprite.new(GameContent.hero_bundle("self"), "DELVER", true)
	_player_sprite.size = Vector2(108, 138)
	_player_sprite.pivot_offset = _player_sprite.size * 0.5
	_player_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_player_sprite)
	_player_sprite.play("walk")

	_build_hud()
	_start_run()
	set_process(true)


func _start_run() -> void:
	_sim = _Sim.new(PlayerStats.compute(), GameState.class_id)
	_draft_open = false
	_over_open = false
	_rebuild_chips()


func _process(delta: float) -> void:
	if _sim == null:
		return
	if _sim.alive and not _sim.awaiting_upgrade:
		_sim.tick(delta, _read_input())
		_age_floaters(delta)

	# Camera follows the delver: keep the sprite screen-centred (design centre
	# 960×540); the arena draws the world offset around it. Face the locked target.
	_player_sprite.position = Vector2(960.0, 540.0) - _player_sprite.size * 0.5
	_player_sprite.scale.x = -1.0 if cos(_sim.aim) < 0.0 else 1.0
	_refresh_hud()
	_arena.queue_redraw()

	if _sim.awaiting_upgrade and not _draft_open:
		_open_draft()
	if not _sim.alive and not _over_open:
		_open_gameover()


func _read_input() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		v.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		v.y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		v.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		v.x += 1.0
	return v


func _age_floaters(delta: float) -> void:
	var live: Array = []
	for f in _sim.floaters:
		f["t"] = float(f["t"]) + delta
		if float(f["t"]) < 0.7:
			live.append(f)
	_sim.floaters = live


func _open_draft() -> void:
	_draft_open = true
	var d := _Draft.new()
	d.modal_title = "Stage Cleared"
	d.modal_width = 880.0
	d.choices = _sim.offer_upgrades()
	d.stage_cleared = _sim.stage
	d.chosen.connect(func(id: String) -> void:
		_sim.choose_upgrade(id)
		_rebuild_chips())
	d.closed.connect(func() -> void: _draft_open = false)
	add_child(d)


func _open_gameover() -> void:
	_over_open = true
	var g := _GameOver.new()
	g.modal_title = "You Fell"
	g.modal_width = 900.0
	g.run_score = _sim.final_score()
	g.run_kills = _sim.kills
	g.run_stage = _sim.stage
	g.run_time = _sim.time
	g.retry_requested.connect(func() -> void: _start_run())
	g.closed.connect(func() -> void: _over_open = false)
	add_child(g)


# --- HUD --------------------------------------------------------------------

func _build_hud() -> void:
	# Top-left: stage + timer.
	var tl := VBoxContainer.new()
	tl.add_theme_constant_override("separation", 0)
	add_child(tl)
	tl.set_anchors_preset(Control.PRESET_TOP_LEFT)
	tl.offset_left = 28
	tl.offset_top = 24
	_stage_lbl = Style.display_label("STAGE 1", 26, Palette.GOLD_BRIGHT, true)
	tl.add_child(_stage_lbl)
	_time_lbl = Style.pixel_label("0:00", 18, Palette.EMBER_BRIGHT)
	tl.add_child(_time_lbl)

	# Upgrade chips row, under the stage block.
	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override("separation", 5)
	add_child(_chips)
	_chips.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_chips.offset_left = 28
	_chips.offset_top = 92

	# Top-center: powered-by line.
	var pc := VBoxContainer.new()
	pc.add_theme_constant_override("separation", 1)
	add_child(pc)
	pc.set_anchors_preset(Control.PRESET_CENTER_TOP)
	pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pc.offset_top = 26
	var atk := "Projectiles" if (GameState.class_id == "mage" or GameState.class_id == "hunter") else "Blade Aura"
	var dps := "—"
	if "party_dps_label" in CombatSim:
		dps = String(CombatSim.party_dps_label)
	var t := Style.body_label("%s · %s · DPS %s" % [GameState.player_class, atk, dps], 13, Palette.TX_MUTE)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pc.add_child(t)
	var hint := Style.pixel_label("WASD / ARROWS TO MOVE", 8, Palette.TX_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pc.add_child(hint)

	# Top-right: score/kills + return.
	var tr := VBoxContainer.new()
	tr.add_theme_constant_override("separation", 2)
	tr.alignment = BoxContainer.ALIGNMENT_END
	add_child(tr)
	tr.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tr.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tr.offset_top = 24
	tr.offset_right = -28
	_score_lbl = Style.pixel_label("0", 24, Palette.EMBER_BRIGHT)
	_score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tr.add_child(_score_lbl)
	_kills_lbl = Style.body_label("0 culled", 12, Palette.TX_MUTE)
	_kills_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tr.add_child(_kills_lbl)
	var ret := Style.make_button("RETURN", "ghost", 11)
	ret.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	ret.pressed.connect(func() -> void: WindowManager.close(WindowManager.WIN_SURVIVAL))
	tr.add_child(ret)

	# Bottom-center: HP bar.
	var hp_wrap := VBoxContainer.new()
	hp_wrap.add_theme_constant_override("separation", 3)
	add_child(hp_wrap)
	hp_wrap.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hp_wrap.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hp_wrap.offset_bottom = -22
	var bar_bg := Panel.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color("1a120e")
	bsb.set_border_width_all(1)
	bsb.border_color = Palette.IRON_EDGE
	bsb.set_corner_radius_all(3)
	bar_bg.add_theme_stylebox_override("panel", bsb)
	bar_bg.custom_minimum_size = Vector2(420, 24)
	hp_wrap.add_child(bar_bg)
	_hp_fill = ColorRect.new()
	_hp_fill.color = Palette.HP
	_hp_fill.position = Vector2(2, 2)
	_hp_fill.size = Vector2(416, 20)
	_hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_bg.add_child(_hp_fill)
	_hp_lbl = Style.pixel_label("100 / 100", 10, Palette.TX)
	_hp_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_bg.add_child(_hp_lbl)


func _refresh_hud() -> void:
	_stage_lbl.text = "STAGE %d" % _sim.stage
	var rem := maxi(0, int(ceil(_sim.STAGE_SECONDS - _sim.stage_time)))
	_time_lbl.text = "%d:%02d  ·  next in %ds" % [int(_sim.time) / 60, int(_sim.time) % 60, rem]
	_score_lbl.text = Style.group_int(_sim.final_score())
	_kills_lbl.text = "%d culled" % _sim.kills
	var ratio := clampf(_sim.hp / maxf(1.0, _sim.max_hp), 0.0, 1.0)
	_hp_fill.size.x = 416.0 * ratio
	_hp_fill.color = Palette.HP if ratio > 0.3 else Palette.EMBER_BRIGHT
	_hp_lbl.text = "%d / %d" % [int(_sim.hp), int(_sim.max_hp)]


func _rebuild_chips() -> void:
	if _chips == null:
		return
	for c in _chips.get_children():
		c.queue_free()
	var names := {}
	for u in _Sim.UPGRADES:
		names[String(u["id"])] = String(u["name"])
	var counts := {}
	for id in _sim.upgrades_taken:
		counts[id] = int(counts.get(id, 0)) + 1
	for id in counts:
		var txt := String(names.get(id, id))
		if int(counts[id]) > 1:
			txt += " ×%d" % int(counts[id])
		var chip := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.1, 0.08, 0.06, 0.8)
		sb.set_border_width_all(1)
		sb.border_color = Palette.CYAN_BRIGHT
		sb.set_corner_radius_all(3)
		sb.content_margin_left = 7
		sb.content_margin_right = 7
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		chip.add_theme_stylebox_override("panel", sb)
		chip.add_child(Style.pixel_label(txt, 8, Palette.CYAN_BRIGHT))
		_chips.add_child(chip)


# ===========================================================================
## Draw layer: enemies + projectiles + gems + the melee aura + damage floaters,
## beneath the player sprite. Reads the host's SurvivalSim each frame.
class _Arena:
	extends Control

	var host = null

	func _draw() -> void:
		if host == null or host._sim == null:
			return
		var sim: SurvivalSim = host._sim
		var c := Vector2(960.0, 540.0)   # screen centre = the delver
		var off := c - sim.player        # world → screen offset (the camera)

		# Scrolling ground grid — a placeholder "map" that makes movement read
		# (real art drops in later). Lines wrap with the camera via fposmod.
		var cell := 128.0
		var gcol := Palette.with_alpha(Palette.EMBER, 0.05)
		var gx := fposmod(off.x, cell) - cell
		while gx < 1920.0 + cell:
			draw_line(Vector2(gx, 0.0), Vector2(gx, 1080.0), gcol, 1.0)
			gx += cell
		var gy := fposmod(off.y, cell) - cell
		while gy < 1080.0 + cell:
			draw_line(Vector2(0.0, gy), Vector2(1920.0, gy), gcol, 1.0)
			gy += cell

		# Pickup magnet ring (around the delver / screen centre).
		draw_arc(c, sim.pickup_radius, 0.0, TAU, 48, Palette.with_alpha(Palette.CYAN_BRIGHT, 0.12), 1.5)

		# Melee blade aura (warrior/rogue): a glowing sector toward the locked aim.
		if not sim.is_ranged:
			var bright := 0.18 + (0.5 if sim.aura_flash > 0.0 else 0.0)
			var hw := PI if sim.backside else (0.95 + (0.55 if sim.diagonal else 0.0))
			_draw_sector(c, sim.aura_radius, sim.aim, hw, Palette.with_alpha(Palette.EMBER_BRIGHT, bright))
			draw_arc(c, sim.aura_radius, 0.0, TAU, 56, Palette.with_alpha(Palette.EMBER, 0.25), 2.0)

		# Gems (xp/score motes).
		for g in sim.gems:
			var gp := (g["pos"] as Vector2) + off
			draw_circle(gp, 6.0, Palette.with_alpha(Palette.CYAN_BRIGHT, 0.4))
			draw_circle(gp, 3.0, Color(0.6, 1.0, 0.7))

		# Enemies: blood motes with an HP ring.
		for e in sim.enemies:
			var ep := (e["pos"] as Vector2) + off
			var r := float(e["r"])
			draw_circle(ep, r + 3.0, Palette.with_alpha(Palette.HP, 0.2))
			draw_circle(ep, r, Palette.HP)
			draw_circle(ep, r * 0.45, Color(0.12, 0.03, 0.03))
			var frac := clampf(float(e["hp"]) / maxf(1.0, float(e["max"])), 0.0, 1.0)
			if frac < 0.999:
				draw_arc(ep, r + 5.0, -PI * 0.5, -PI * 0.5 + TAU * frac, 20, Palette.GOLD_BRIGHT, 2.0)

		# Projectiles.
		for s in sim.shots:
			var sp := (s["pos"] as Vector2) + off
			draw_circle(sp, float(s["r"]) + 4.0, Palette.with_alpha(Palette.CYAN_BRIGHT, 0.3))
			draw_circle(sp, float(s["r"]) * 0.5, Color(1, 1, 1, 0.95))

		# Delver footing ring (screen centre).
		draw_arc(c, host._player_sprite.size.x * 0.32, 0.0, TAU, 28, Palette.with_alpha(Palette.EMBER_BRIGHT, 0.55), 2.0)

		# Damage floaters.
		if host._font != null:
			for f in sim.floaters:
				var a := clampf(1.0 - float(f["t"]) / 0.7, 0.0, 1.0)
				var fp := (f["pos"] as Vector2) + off + Vector2(0.0, -38.0 * float(f["t"]))
				var col := Palette.GOLD_BRIGHT if bool(f["crit"]) else Palette.TX
				host._font.draw_string(get_canvas_item(), fp, str(int(f["amount"])),
					HORIZONTAL_ALIGNMENT_CENTER, -1, 22 if bool(f["crit"]) else 17, Palette.with_alpha(col, a))

	## A filled sector (pie slice) centered on [param center_ang] ± [param half].
	func _draw_sector(c: Vector2, radius: float, center_ang: float, half: float, col: Color) -> void:
		var pts := PackedVector2Array()
		pts.append(c)
		var steps := maxi(6, int(half / PI * 28.0))
		for i in steps + 1:
			var a := center_ang - half + 2.0 * half * float(i) / float(steps)
			pts.append(c + Vector2.RIGHT.rotated(a) * radius)
		draw_colored_polygon(pts, col)
