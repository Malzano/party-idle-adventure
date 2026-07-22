extends Control
## STAR STAMPEDE — bullet-hell side mode (vampire-survivors style, BinkBonk).
## Two phases:
##   LOADOUT — pack the charm backpack (the real Bag grid, persisted "bp" cells;
##             only packed pieces + adjacency synergies power the run) and see
##             live Run Power totals, then Start the Stampede.
##   RUN     — presentation + input for a headless SurvivalSim: squishy baddies
##             pour in from every angle, the hero auto-bonks (hunter/mage fire
##             sparkle bolts, warrior/rogue swing a sparkle sweep), gems grant
##             real XP levels, and every stage cleared offers a 3-card draft.
## Move with WASD / arrows. Screen shake + hurt vignette on hits (world-only —
## the HUD never shakes). Map art is a placeholder; real assets drop in later.

const _Sim := preload("res://systems/survival/SurvivalSim.gd")
const _Draft := preload("res://scenes/survival/SurvivalDraft.gd")
const _GameOver := preload("res://scenes/survival/SurvivalGameOver.gd")
const _BagTab := preload("res://scenes/hero/BagTab.gd")

## Render the world in 2.5D (tilted 3D Combat3DView) vs the flat 2D fallback.
const USE_3D := false  # 2D meadow (2.5D needs .glb models in assets/models/)

var _sim: SurvivalSim
var _world3d: Combat3DView   # set when USE_3D — the 2.5D world (HUD stays 2D on top)
var _arena: _Arena
var _player_sprite: UnitSprite
var _font: Font

var _phase := "loadout"      # "loadout" | "run"
var _loadout: Control
var _power_list: VBoxContainer
var _hud: Control

var _hp_fill: ColorRect
var _hp_lbl: Label
var _stage_lbl: Label
var _time_lbl: Label
var _score_lbl: Label
var _kills_lbl: Label
var _chips: HBoxContainer
var _xp_fill: ColorRect
var _xp_track: Panel
var _lv_lbl: Label

var _draft_open := false
var _over_open := false
var _minimap: _Minimap
var _boss_lbl: Label
var _boss_seen := 0
var _boss_banner_t := 0.0
var _shake_off := Vector2.ZERO


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_font = Fonts.pixel()

	var bg := ColorRect.new()
	bg.color = Color("24413a")  # starlit meadow green
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	if USE_3D:
		# 2.5D world (tilted camera + 3D entities). The HUD/minimap/modals built
		# below sit on top as 2D Control. Models drop in via _register_models().
		_world3d = Combat3DView.new()
		add_child(_world3d)
		_world3d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_register_models()
	else:
		_arena = _Arena.new()
		_arena.host = self
		_arena.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_arena)
		_arena.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		_player_sprite = UnitSprite.new(GameContent.hero_bundle("self"), "HERO", true)
		_player_sprite.size = Vector2(62, 80)  # small hero on a huge map
		_player_sprite.pivot_offset = _player_sprite.size * 0.5
		_player_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_player_sprite)
		_player_sprite.play("walk")

	_build_hud()
	_build_loadout()
	# A sim exists from the start (the loadout preview + tests read it); Start
	# builds a FRESH one so packing changes always apply.
	_sim = _Sim.new(PlayerStats.compute(), GameState.class_id)
	_show_loadout()
	set_process(true)


# ===========================================================================
# Phase flow: loadout ⇄ run
# ===========================================================================

func _show_loadout() -> void:
	_phase = "loadout"
	_loadout.visible = true
	_hud.visible = false
	if _arena != null:
		_arena.visible = false
	if _world3d != null:
		_world3d.visible = false
	if _player_sprite != null:
		_player_sprite.visible = false
	_refresh_power()


func _start_run() -> void:
	_sim = _Sim.new(PlayerStats.compute(), GameState.class_id)
	_draft_open = false
	_over_open = false
	_boss_seen = 0
	_phase = "run"
	_loadout.visible = false
	_hud.visible = true
	if _arena != null:
		_arena.visible = true
	if _world3d != null:
		_world3d.visible = true
	if _player_sprite != null:
		_player_sprite.visible = true
	_rebuild_chips()


## Enter starts the run from the loadout.
func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if _phase == "loadout" and (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER):
		_start_run()
		get_viewport().set_input_as_handled()


## Drop real 3D models here once you have them (else tinted placeholders show):
##   _world3d.set_model("class_warrior", load("res://assets/models/warrior.glb"))
## Keys: class_<id>, enemy_swarmer/grunt/brute, boss, shot, gem. Model forward = -Z,
## origin at the feet. Just drop res://assets/models/<key>.glb and re-import —
## auto_load_models picks it up; no code edit needed.
func _register_models() -> void:
	_world3d.auto_load_models()


## Drive the 2.5D world from the sim each frame (positions only; the sim is
## unchanged). Pooled 3D nodes are reused/hidden so the swarm is cheap.
func _render3d() -> void:
	var v := _world3d
	v.focus(_sim.player)
	var pn := v.node("player", 0, "class_" + GameState.class_id)
	pn.position = v.to3(_sim.player)
	var heading := Vector3(cos(_sim.aim), 0.0, sin(_sim.aim))
	pn.look_at(pn.position + heading, Vector3.UP)
	for i in _sim.enemies.size():
		var e: Dictionary = _sim.enemies[i]
		var ek := "boss" if String(e.get("kind", "")) == "boss" else "enemy_" + String(e.get("kind", "grunt"))
		v.node("enemy", i, ek).position = v.to3(e["pos"])
	v.trim("enemy", _sim.enemies.size())
	for i in _sim.shots.size():
		v.node("shot", i, "shot").position = v.to3(_sim.shots[i]["pos"])
	v.trim("shot", _sim.shots.size())
	for i in _sim.gems.size():
		v.node("gem", i, "gem").position = v.to3(_sim.gems[i]["pos"])
	v.trim("gem", _sim.gems.size())


func _process(delta: float) -> void:
	if _sim == null or _phase != "run":
		return
	if _sim.alive and not _sim.awaiting_upgrade:
		_sim.tick(delta, _read_input())
		_age_floaters(delta)

	# Screen shake (world-only): magnitude²·11 px of jitter, decayed by the sim.
	if _sim.shake > 0.01:
		var m := _sim.shake * _sim.shake * 11.0
		_shake_off = Vector2(randf_range(-m, m), randf_range(-m, m))
	else:
		_shake_off = Vector2.ZERO

	# Camera follows the hero: keep the sprite screen-centred (design centre
	# 960×540); the arena draws the world offset around it. Face the locked target.
	if _world3d != null:
		_world3d.position = _shake_off
		_render3d()
	else:
		_player_sprite.position = Vector2(960.0, 540.0) - _player_sprite.size * 0.5 + _shake_off
		_player_sprite.scale.x = -1.0 if cos(_sim.aim) < 0.0 else 1.0
		_arena.queue_redraw()
	_refresh_hud()
	if _minimap != null:
		_minimap.queue_redraw()

	# World-boss banner on each new spawn (Crownfall "a boss appeared on the map").
	if _sim.boss_spawns > _boss_seen:
		_boss_seen = _sim.boss_spawns
		_boss_banner_t = 3.5
	if _boss_banner_t > 0.0:
		_boss_banner_t = maxf(0.0, _boss_banner_t - delta)
		_boss_lbl.visible = true
		_boss_lbl.modulate.a = clampf(_boss_banner_t, 0.0, 1.0)
	elif _boss_lbl.visible:
		_boss_lbl.visible = false

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
	var boss := _sim._draft_reason == "boss"
	var d := _Draft.new()
	d.modal_title = "Boss Bonked!" if boss else "Stage Clear!"
	d.boss_reward = boss
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
	g.modal_title = "All Tuckered Out!"
	g.modal_width = 900.0
	g.run_score = _sim.final_score()
	g.run_kills = _sim.kills
	g.run_stage = _sim.stage
	g.run_time = _sim.time
	g.retry_requested.connect(func() -> void: _start_run())
	g.loadout_requested.connect(func() -> void: _show_loadout())
	g.closed.connect(func() -> void: _over_open = false)
	add_child(g)


# ===========================================================================
# LOADOUT — the pre-run backpack screen (Backpack + Run Power + Start)
# ===========================================================================

func _build_loadout() -> void:
	_loadout = Control.new()
	_loadout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loadout.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_loadout)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_loadout.add_child(col)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 30
	col.offset_top = 18
	col.offset_right = -30
	col.offset_bottom = -20

	# Header: title + run summary line.
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 0)
	col.add_child(head)
	var title := Style.display_label("Star Stampede", 34, Palette.GOLD_BRIGHT, true)
	title.add_theme_color_override("font_shadow_color", Color(0.08, 0.1, 0.1, 0.8))
	title.add_theme_constant_override("shadow_offset_y", 3)
	head.add_child(title)
	var cls := GameContent.class_by_id(GameState.class_id)
	var atk := "Sparkle Bolts" if (GameState.class_id == "mage" or GameState.class_id == "hunter") else "Sparkle Sweep"
	var who := GameState.player_name if GameState.player_name != "" else String(cls.get("name", "Adventurer"))
	head.add_child(Style.body_label(
		"Solo run · %s, %s · %s · where each charm sits matters!" % [who, String(cls.get("title", "the Plucky")), atk],
		13, Palette.TX_FAINT))

	# Body: the real Bag grid (persisted packing) + the Run Power panel.
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)

	var bag_frame := PanelContainer.new()
	bag_frame.add_theme_stylebox_override("panel", Style.panel_box())
	bag_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(bag_frame)
	var bag := _BagTab.new()
	bag_frame.add_child(bag)

	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 12)
	side.custom_minimum_size = Vector2(360, 0)
	body.add_child(side)

	var power_frame := PanelContainer.new()
	power_frame.add_theme_stylebox_override("panel", Style.panel_box(true))
	power_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(power_frame)
	var pcol := VBoxContainer.new()
	pcol.add_theme_constant_override("separation", 8)
	power_frame.add_child(pcol)
	var phead := PanelContainer.new()
	phead.add_theme_stylebox_override("panel", Style.head_box())
	phead.add_child(Style.display_label("RUN POWER", 14, Color("7c4c12")))
	pcol.add_child(phead)
	var ppad := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_bottom"]:
		ppad.add_theme_constant_override(m, 12)
	ppad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pcol.add_child(ppad)
	_power_list = VBoxContainer.new()
	_power_list.add_theme_constant_override("separation", 5)
	ppad.add_child(_power_list)

	var start := Style.make_button("START THE STAMPEDE!  ↵", "ember", 15)
	start.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	start.pressed.connect(_start_run)
	side.add_child(start)
	var back := Style.make_button("BACK", "ghost", 11)
	back.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	back.pressed.connect(func() -> void: WindowManager.close(WindowManager.WIN_SURVIVAL))
	side.add_child(back)

	EventBus.loadout_changed.connect(_refresh_power)
	EventBus.equipment_changed.connect(_refresh_power)


## Rebuild the Run Power readout: packed affix totals + live synergy lines
## (or the everything-counts fallback note when nothing is packed yet).
func _refresh_power() -> void:
	if _power_list == null or not is_instance_valid(_power_list):
		return
	for c in _power_list.get_children():
		c.queue_free()
	var packed := GameContent.survival_packed_items()
	var totals: Dictionary = {}
	var sources: Array = packed
	if packed.is_empty():
		sources = GameState.bag_equipment.duplicate()
		for it in GameState.equipped:
			if it != null:
				sources.append(it)
	for it_v in sources:
		if it_v == null:
			continue
		for pair in GameContent.item_bullet_hell(it_v):
			var nm := String(pair[0])
			totals[nm] = float(totals.get(nm, 0.0)) + float(String(pair[1]).replace("+", "").replace("%", ""))
	var syns: Array = GameContent.survival_synergies(packed) if not packed.is_empty() else []
	for syn_v in syns:
		var af: Array = (syn_v as Dictionary)["affix"]
		totals[String(af[0])] = float(totals.get(String(af[0]), 0.0)) + float(af[1])

	if packed.is_empty():
		_power_list.add_child(Style.body_label(
			"Nothing packed — the whole bag powers the run. Pack the grid to focus your build (and unlock synergies)!",
			12, Palette.TX_MUTE))
	else:
		_power_list.add_child(Style.body_label("%d charm%s packed" % [packed.size(), "" if packed.size() == 1 else "s"], 12, Palette.TX_DIM))
	for nm in totals:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var l := Style.body_label(String(nm), 12, Palette.TX_DIM)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(Style.pixel_label("+%d%%" % int(totals[nm]), 11, Palette.CYAN_DEEP))
		_power_list.add_child(row)
	for syn_v in syns:
		var syn: Dictionary = syn_v
		var af: Array = syn["affix"]
		var line := Style.body_label("✦ %s + %s — %s  +%d%% %s" % [
			String((syn["a_item"] as Dictionary).get("n", "?")), String((syn["b_item"] as Dictionary).get("n", "?")),
			String(syn["desc"]), int(af[1]), String(af[0])], 11, Palette.GOLD_DIM)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_power_list.add_child(line)


# ===========================================================================
# RUN HUD
# ===========================================================================

func _build_hud() -> void:
	_hud = Control.new()
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_hud)

	# Full-width XP bar at the very top (VS-style); flashes gold on a level-up.
	_xp_track = Panel.new()
	var xsb := StyleBoxFlat.new()
	xsb.bg_color = Color(0.1, 0.16, 0.14, 0.85)
	xsb.border_width_bottom = 2
	xsb.border_color = Palette.with_alpha(Palette.GOLD_DIM, 0.6)
	_xp_track.add_theme_stylebox_override("panel", xsb)
	_hud.add_child(_xp_track)
	_xp_track.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_xp_track.offset_bottom = 14
	_xp_fill = ColorRect.new()
	_xp_fill.color = Palette.XP
	_xp_fill.position = Vector2.ZERO
	_xp_fill.size = Vector2(0, 12)
	_xp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_track.add_child(_xp_fill)
	_lv_lbl = Style.pixel_label("LV 1", 9, Color("6b5210"))
	_lv_lbl.position = Vector2(8, -1)
	_lv_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_track.add_child(_lv_lbl)

	# Top-left: stage + timer.
	var tl := VBoxContainer.new()
	tl.add_theme_constant_override("separation", 0)
	_hud.add_child(tl)
	tl.set_anchors_preset(Control.PRESET_TOP_LEFT)
	tl.offset_left = 28
	tl.offset_top = 30
	_stage_lbl = Style.display_label("STAGE 1", 26, Palette.GOLD_BRIGHT, true)
	tl.add_child(_stage_lbl)
	_time_lbl = Style.pixel_label("0:00", 18, Palette.EMBER_BRIGHT)
	tl.add_child(_time_lbl)

	# Upgrade chips row, under the stage block.
	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override("separation", 5)
	_hud.add_child(_chips)
	_chips.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_chips.offset_left = 28
	_chips.offset_top = 98

	# Top-center: powered-by line.
	var pc := VBoxContainer.new()
	pc.add_theme_constant_override("separation", 1)
	_hud.add_child(pc)
	pc.set_anchors_preset(Control.PRESET_CENTER_TOP)
	pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pc.offset_top = 32
	var atk := "Sparkle Bolts" if (GameState.class_id == "mage" or GameState.class_id == "hunter") else "Sparkle Sweep"
	var t := Style.body_label("%s · %s · powered by your backpack" % [GameState.player_class, atk], 13, Palette.TX_FAINT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pc.add_child(t)
	var hint := Style.pixel_label("WASD / ARROWS TO SKIP AROUND", 8, Palette.with_alpha(Palette.IRON_HI, 0.6))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pc.add_child(hint)

	# Top-right: score/bonks + return.
	var tr := VBoxContainer.new()
	tr.add_theme_constant_override("separation", 2)
	tr.alignment = BoxContainer.ALIGNMENT_END
	_hud.add_child(tr)
	tr.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tr.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tr.offset_top = 30
	tr.offset_right = -28
	_score_lbl = Style.pixel_label("0", 24, Palette.GOLD_BRIGHT)
	_score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tr.add_child(_score_lbl)
	_kills_lbl = Style.body_label("0 bonked", 12, Palette.TX_FAINT)
	_kills_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tr.add_child(_kills_lbl)
	var ret := Style.make_button("RETURN", "ghost", 11)
	ret.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	ret.pressed.connect(func() -> void: _show_loadout())
	tr.add_child(ret)

	# Bottom-center: HP bar (440px, numeric readout).
	var hp_wrap := VBoxContainer.new()
	hp_wrap.add_theme_constant_override("separation", 3)
	_hud.add_child(hp_wrap)
	hp_wrap.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hp_wrap.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hp_wrap.offset_bottom = -22
	var bar_bg := Panel.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.12, 0.2, 0.17, 0.9)
	bsb.set_border_width_all(2)
	bsb.border_color = Palette.IRON_EDGE
	bsb.set_corner_radius_all(9)
	bar_bg.add_theme_stylebox_override("panel", bsb)
	bar_bg.custom_minimum_size = Vector2(440, 24)
	hp_wrap.add_child(bar_bg)
	_hp_fill = ColorRect.new()
	_hp_fill.color = Palette.HP
	_hp_fill.position = Vector2(2, 2)
	_hp_fill.size = Vector2(436, 20)
	_hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_bg.add_child(_hp_fill)
	_hp_lbl = Style.pixel_label("100 / 100", 10, Color.WHITE)
	_hp_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_bg.add_child(_hp_lbl)

	# Minimap, bottom-left (232×152, Crownfall style): the whole map at a glance
	# with the hero, the swarm, and the marked Grumble King.
	_minimap = _Minimap.new()
	_minimap.host = self
	_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_minimap)
	_minimap.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_minimap.offset_left = 18
	_minimap.offset_right = 250
	_minimap.offset_top = -170
	_minimap.offset_bottom = -18

	# World-boss banner (centred, fades after a spawn).
	_boss_lbl = Style.display_label("★ GRUMBLE KING appeared — find him on the map!", 22, Palette.HP, true)
	_boss_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_lbl.visible = false
	_boss_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_boss_lbl)
	_boss_lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boss_lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_boss_lbl.offset_top = 98


func _refresh_hud() -> void:
	_stage_lbl.text = "STAGE %d" % _sim.stage
	var rem := maxi(0, int(ceil(_sim.STAGE_SECONDS - _sim.stage_time)))
	_time_lbl.text = "%d:%02d  ·  next in %ds" % [int(_sim.time) / 60, int(_sim.time) % 60, rem]
	_score_lbl.text = Style.group_int(_sim.final_score())
	_kills_lbl.text = "%d bonked" % _sim.kills
	var ratio := clampf(_sim.hp / maxf(1.0, _sim.max_hp), 0.0, 1.0)
	_hp_fill.size.x = 436.0 * ratio
	_hp_fill.color = Palette.HP if ratio > 0.3 else Palette.EMBER_BRIGHT
	_hp_lbl.text = "%d / %d" % [int(_sim.hp), int(_sim.max_hp)]
	# XP bar + gold level-up flash.
	var need := _Sim.xp_need(_sim.level)
	_xp_fill.size = Vector2(_xp_track.size.x * clampf(float(_sim.xp) / float(maxi(1, need)), 0.0, 1.0), 12.0)
	_lv_lbl.text = "LV %d" % _sim.level
	_xp_fill.color = Palette.GOLD_BRIGHT if _sim.level_flash > 0.0 else Palette.XP


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
		sb.bg_color = Color(1.0, 0.97, 0.88, 0.9)
		sb.set_border_width_all(2)
		sb.border_color = Palette.GOLD_DIM
		sb.set_corner_radius_all(8)
		sb.content_margin_left = 7
		sb.content_margin_right = 7
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		chip.add_theme_stylebox_override("panel", sb)
		chip.add_child(Style.pixel_label(txt, 8, Color("7c4c12")))
		_chips.add_child(chip)


# ===========================================================================
## Draw layer: the starlit meadow, squishy baddies + bolts + gems + the sparkle
## sweep + damage floaters, beneath the hero sprite. Reads the host's
## SurvivalSim each frame. World points shift by the host's shake offset; the
## hurt vignette + level-up ring draw in screen space (never shake).
class _Arena:
	extends Control

	var host = null

	func _draw() -> void:
		if host == null or host._sim == null:
			return
		var sim: SurvivalSim = host._sim
		var c := Vector2(960.0, 540.0) + (host._shake_off as Vector2)  # the hero
		var off := c - sim.player        # world → screen offset (the camera)

		# Meadow grid + deterministic sparkle tufts — a placeholder "map" that
		# makes movement read (real art drops in later). Wraps via fposmod.
		var cell := 120.0
		var gcol := Color(0.59, 0.9, 0.75, 0.07)
		var gx := fposmod(off.x, cell) - cell
		while gx < 1920.0 + cell:
			draw_line(Vector2(gx, 0.0), Vector2(gx, 1080.0), gcol, 1.0)
			gx += cell
		var gy := fposmod(off.y, cell) - cell
		while gy < 1080.0 + cell:
			draw_line(Vector2(0.0, gy), Vector2(1920.0, gy), gcol, 1.0)
			gy += cell
		var tuft := Color(0.67, 0.94, 0.78, 0.13)
		for tgx in range(int(-off.x / cell) - 1, int((-off.x + 1920.0) / cell) + 1):
			for tgy in range(int(-off.y / cell) - 1, int((-off.y + 1080.0) / cell) + 1):
				var hsh := absf(sin(float(tgx) * 127.1 + float(tgy) * 311.7) * 43758.5)
				hsh -= floorf(hsh)
				if hsh > 0.72:
					var px := float(tgx) * cell + hsh * 90.0 + off.x
					var py := float(tgy) * cell + fmod(hsh * 53.0, 1.0) * 90.0 + off.y
					draw_set_transform(Vector2(px, py), 0.0, Vector2(1.0, 0.52))
					draw_circle(Vector2.ZERO, 5.0, tuft)
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		# World bound — a soft honey rope around the roamable meadow.
		var wr := sim.world_rect()
		draw_rect(Rect2(wr.position + off, wr.size), Color(1.0, 0.87, 0.59, 0.22), false, 6.0)

		# Pickup magnet ring (around the hero / screen centre).
		draw_arc(c, sim.pickup_radius, 0.0, TAU, 48, Color(0.51, 0.79, 1.0, 0.12), 1.5)

		# Melee sparkle sweep (warrior/rogue): a glowing sector toward the aim.
		if not sim.is_ranged:
			var bright := 0.16 + (0.4 if sim.aura_flash > 0.0 else 0.0)
			var hw := PI if sim.backside else (0.95 + (0.55 if sim.diagonal else 0.0))
			_draw_sector(c, sim.aura_radius, sim.aim, hw, Color(1.0, 0.84, 0.45, bright))
			draw_arc(c, sim.aura_radius, 0.0, TAU, 56, Color(1.0, 0.78, 0.4, 0.25), 2.0)

		# Star Burst flash (secondary weapon) — an expanding gold ring.
		if sim.nova_flash > 0.0:
			var nt := 1.0 - sim.nova_flash / 0.3
			draw_arc(c, sim.nova_radius * nt, 0.0, TAU, 64, Color(1.0, 0.78, 0.29, sim.nova_flash * 1.8), 4.0)

		# Twinkle Buddies (orbiting stars).
		if sim.orbs > 0:
			for i in sim.orbs:
				var op := c + Vector2.RIGHT.rotated(sim.orb_angle + TAU * float(i) / float(sim.orbs)) * sim.orb_radius
				draw_circle(op, 11.0, Color(0.79, 0.91, 1.0, 0.6))
				draw_circle(op, 6.0, Color("4da3ff"))

		# Gems — mint diamonds with a shine.
		for g in sim.gems:
			var gp := (g["pos"] as Vector2) + off
			draw_set_transform(gp, PI * 0.25, Vector2.ONE)
			draw_rect(Rect2(-5.0, -5.0, 10.0, 10.0), Color("7ef0c8"))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			draw_rect(Rect2(gp + Vector2(-1.5, -4.0), Vector2(3.0, 3.0)), Color(1, 1, 1, 0.8))

		# Baddies: squishy blobs with eyes (breathing squash) + a health sliver.
		for e in sim.enemies:
			var ep := (e["pos"] as Vector2) + off
			var r := float(e["r"])
			var ecol := Color(String(e.get("tint", "e06868")))
			var sq := 1.0 + sin(float(e.get("wob", 0.0))) * 0.07
			# Shadow.
			draw_set_transform(ep + Vector2(0.0, r * 0.85), 0.0, Vector2(1.0, 0.35))
			draw_circle(Vector2.ZERO, r * 0.8, Color(0.04, 0.07, 0.14, 0.35))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			# Body (squash/stretch) + highlight.
			draw_set_transform(ep, 0.0, Vector2(sq, 1.0 / sq))
			draw_circle(Vector2.ZERO, r, ecol)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			draw_set_transform(ep + Vector2(-r * 0.25, -r * 0.3), -0.5, Vector2(1.0, 0.7))
			draw_circle(Vector2.ZERO, r * 0.4, Color(1, 1, 1, 0.35))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			# Eyes.
			var er := maxf(1.8, r * 0.11)
			draw_circle(ep + Vector2(-r * 0.3, -r * 0.08), er, Color("2a2038"))
			draw_circle(ep + Vector2(r * 0.3, -r * 0.08), er, Color("2a2038"))
			# Grumble King gets angry brows + an aura ring.
			if String(e.get("kind", "")) == "boss":
				draw_line(ep + Vector2(-r * 0.45, -r * 0.32), ep + Vector2(-r * 0.14, -r * 0.2), Color("2a2038"), 2.4)
				draw_line(ep + Vector2(r * 0.45, -r * 0.32), ep + Vector2(r * 0.14, -r * 0.2), Color("2a2038"), 2.4)
				draw_arc(ep, r + 9.0, 0.0, TAU, 40, Color(1.0, 0.42, 0.37, 0.6), 3.0)
			var frac := clampf(float(e["hp"]) / maxf(1.0, float(e["max"])), 0.0, 1.0)
			if frac < 0.999:
				var bw := r * 2.0
				draw_rect(Rect2(ep + Vector2(-bw * 0.5, -r - 12.0), Vector2(bw, 5.0)), Color(0.16, 0.12, 0.2, 0.55))
				draw_rect(Rect2(ep + Vector2(-bw * 0.5, -r - 12.0), Vector2(bw * frac, 5.0)),
					Color("ff6b5e") if String(e.get("kind", "")) == "boss" else Color("7ef0a8"))

		# Bolts — gold sparkle ovals pointed along their flight.
		for s in sim.shots:
			var sp := (s["pos"] as Vector2) + off
			var ang := (s["vel"] as Vector2).angle()
			var sr := float(s["r"])
			draw_set_transform(sp, ang, Vector2(1.0, 0.55))
			draw_circle(Vector2.ZERO, sr * 0.8, Color("ffd24a"))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			draw_circle(sp + Vector2.RIGHT.rotated(ang) * sr * 0.3, sr * 0.22, Color(1, 1, 1, 0.85))

		# Hero footing ring (screen centre).
		draw_arc(c, host._player_sprite.size.x * 0.4, 0.0, TAU, 28, Color(1.0, 0.84, 0.45, 0.55), 2.0)

		# Off-screen Grumble King marker — an edge arrow pointing toward him.
		for e in sim.enemies:
			if String(e.get("kind", "")) != "boss":
				continue
			var bs := (e["pos"] as Vector2) + off
			if bs.x < 50.0 or bs.x > 1870.0 or bs.y < 50.0 or bs.y > 1030.0:
				var dir := (bs - c).normalized()
				var edge := c + dir * 520.0
				edge.x = clampf(edge.x, 70.0, 1850.0)
				edge.y = clampf(edge.y, 70.0, 1010.0)
				draw_circle(edge, 17.0, Color(1.0, 0.42, 0.37, 0.5))
				draw_colored_polygon(PackedVector2Array([
					edge + dir * 24.0, edge + dir.rotated(2.5) * 13.0, edge + dir.rotated(-2.5) * 13.0,
				]), Palette.EMBER_BRIGHT)

		# Damage floaters — chunky white, gold crits, dark soft shadow.
		if host._font != null:
			for f in sim.floaters:
				var a := clampf(1.0 - float(f["t"]) / 0.7, 0.0, 1.0)
				var fp := (f["pos"] as Vector2) + off + Vector2(0.0, -46.0 * float(f["t"]))
				var fs := 26 if bool(f["crit"]) else 17
				host._font.draw_string(get_canvas_item(), fp + Vector2(1.5, 2.0), str(int(f["amount"])),
					HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color(0.16, 0.12, 0.22, a))
				host._font.draw_string(get_canvas_item(), fp, str(int(f["amount"])),
					HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color("ffd24a" if bool(f["crit"]) else "ffffff") * Color(1, 1, 1, a))

		# Level-up burst: expanding gold ring + "LEVEL UP!" (screen space).
		if sim.level_flash > 0.0:
			var p := 1.0 - sim.level_flash / 1.1
			var sc := Vector2(960.0, 540.0)
			draw_arc(sc, 30.0 + p * 130.0, 0.0, TAU, 48, Color(1.0, 0.78, 0.29, (1.0 - p) * 0.9), 5.0)
			draw_arc(sc, 30.0 + p * 90.0, 0.0, TAU, 40, Color(1, 1, 1, (1.0 - p) * 0.5), 2.0)
			if host._font != null:
				host._font.draw_string(get_canvas_item(), sc + Vector2(0.0, -70.0 - p * 30.0), "LEVEL UP!",
					HORIZONTAL_ALIGNMENT_CENTER, -1, 26, Color(1.0, 0.82, 0.29, 1.0 - p))

		# Hurt vignette (screen space, never shakes): red edges while iframes run.
		if sim._iframe > 0.3:
			var va := (sim._iframe - 0.3) * 1.4
			var vcol := Color(0.95, 0.36, 0.3, 0.0)
			var vedge := Color(0.95, 0.36, 0.3, va * 0.55)
			var band := 190.0
			draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(1920, 0), Vector2(1920, band), Vector2(0, band)]),
				PackedColorArray([vedge, vedge, vcol, vcol]))
			draw_polygon(PackedVector2Array([Vector2(0, 1080 - band), Vector2(1920, 1080 - band), Vector2(1920, 1080), Vector2(0, 1080)]),
				PackedColorArray([vcol, vcol, vedge, vedge]))
			draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(band, 0), Vector2(band, 1080), Vector2(0, 1080)]),
				PackedColorArray([vedge, vcol, vcol, vedge]))
			draw_polygon(PackedVector2Array([Vector2(1920 - band, 0), Vector2(1920, 0), Vector2(1920, 1080), Vector2(1920 - band, 1080)]),
				PackedColorArray([vcol, vedge, vedge, vcol]))

	## A filled sector (pie slice) centered on [param center_ang] ± [param half].
	func _draw_sector(c: Vector2, radius: float, center_ang: float, half: float, col: Color) -> void:
		var pts := PackedVector2Array()
		pts.append(c)
		var steps := maxi(6, int(half / PI * 28.0))
		for i in steps + 1:
			var a := center_ang - half + 2.0 * half * float(i) / float(steps)
			pts.append(c + Vector2.RIGHT.rotated(a) * radius)
		draw_colored_polygon(pts, col)


# ===========================================================================
## Bottom-left minimap (232×152, Crownfall style): the whole world at a glance —
## the hero, the swarm, the pulsing Grumble King marker, and the camera box.
class _Minimap:
	extends Control

	var host = null

	func _draw() -> void:
		if host == null or host._sim == null:
			return
		var sim: SurvivalSim = host._sim
		var wr: Rect2 = sim.world_rect()
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.12, 0.21, 0.18, 0.92))
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.87, 0.59, 0.4), false, 2.0)

		for e in sim.enemies:
			if String(e.get("kind", "")) == "boss":
				continue
			draw_circle(_w2m(e["pos"], wr), 1.5, Color(0.88, 0.41, 0.41, 0.9))
		# Camera viewport box.
		var vsize := Vector2(1920.0, 1080.0) / wr.size * size
		draw_rect(Rect2(_w2m(sim.player, wr) - vsize * 0.5, vsize), Color(1, 1, 1, 0.35), false, 1.0)
		# The hero.
		draw_circle(_w2m(sim.player, wr), 3.6, Palette.GOLD_BRIGHT)
		draw_arc(_w2m(sim.player, wr), 6.0, 0.0, TAU, 16, Color(1.0, 0.78, 0.29, 0.6), 1.0)
		# Grumble King — pulsing triangle marker on top.
		for e in sim.enemies:
			if String(e.get("kind", "")) == "boss":
				var bp := _w2m(e["pos"], wr)
				draw_colored_polygon(PackedVector2Array([
					bp + Vector2(0, -6), bp + Vector2(5.5, 4), bp + Vector2(-5.5, 4),
				]), Color("ff6b5e"))
				var pulse := 0.5 + 0.5 * sin(sim.time * 5.0)
				draw_arc(bp, 9.0 + pulse * 2.0, 0.0, TAU, 16, Color(1.0, 0.42, 0.37, 0.5 + 0.5 * pulse), 1.6)
		if host._font != null:
			host._font.draw_string(get_canvas_item(), Vector2(7.0, 15.0), "MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.87, 0.59, 0.8))

	func _w2m(wp: Vector2, wr: Rect2) -> Vector2:
		return (wp - wr.position) / wr.size * size
