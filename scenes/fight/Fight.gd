extends Control
## FIGHT screen (fight.jsx / fight.css) — the main window's permanent home.
##
## Hosts the roaming battlefield (Battlefield.gd) plus the full combat HUD:
## top wave bar, Party Finder, Team Aura badge, auto-loot ticker, four hero
## frames, the control cluster (speed / auto-toggles / retreat) and the
## "Welcome back, delver" offline-gains popup. Combat truth lives in the
## CombatSim autoload; this screen renders it and forwards intent (speed,
## toggles, retreat, collect). Hotkeys: Z auto-skill, X auto-advance,
## Esc retreat, Enter collects the offline rewards while the popup is open.
##
## Main.gd anchors this scene right of the nav rail, so (0,0)..(size) here is
## the whole battlefield + HUD area; the resource strip floats above (y 14).

const _BattlefieldScript := preload("res://scenes/fight/Battlefield.gd")

const _ICON_PROFILE := "res://assets/icons/nav_hero.svg"
const _ICON_GOLD := "res://assets/icons/coin_gold.svg"
const _ICON_CREST := "res://assets/icons/crest.svg"
const _ICON_SOULSTONE := "res://assets/icons/soulstone.svg"

var _stage_val: Label
var _stage_name_lbl: Label
var _wave_lbl: Label
var _wave_bar: StatBar
var _pips: Array = []

var _hp_bars: Array = []
var _mana_bars: Array = []

var _loot_list: VBoxContainer
var _speed_btns: Dictionary = {}
var _tog_skill: Dictionary = {}
var _tog_adv: Dictionary = {}

var _popup: PanelContainer

var _hud_layouts: Array[Callable] = []
var _layout_pending: bool = false


func _ready() -> void:
	# Main.gd already anchored this scene (full rect, x offset 96) — keep it.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true

	var battlefield := _BattlefieldScript.new() as Control
	add_child(battlefield)
	battlefield.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_build_wave_bar()
	_build_party_finder()
	_build_team_aura()
	_build_loot_ticker()
	_build_hero_hud()
	_build_controls()
	_build_popup()

	EventBus.sim_wave_progress.connect(_on_wave_progress)
	EventBus.sim_wave_changed.connect(_on_wave_changed)
	EventBus.sim_stage_changed.connect(_on_stage_changed)
	EventBus.sim_loot.connect(_on_loot)
	EventBus.sim_party_vitals.connect(_on_party_vitals)
	EventBus.sim_speed_changed.connect(_on_speed_changed)
	EventBus.sim_toggles_changed.connect(_on_toggles_changed)

	resized.connect(_request_layout)
	_request_layout()
	call_deferred("_animate_popup_in")


## Z / X / Esc / Enter combat hotkeys (consumed so nothing else sees them).
func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_Z:
			CombatSim.auto_skill = not CombatSim.auto_skill
			get_viewport().set_input_as_handled()
		KEY_X:
			CombatSim.auto_advance = not CombatSim.auto_advance
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			CombatSim.retreat()
			get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_KP_ENTER:
			if _popup != null and _popup.visible:
				_collect_rewards()
				get_viewport().set_input_as_handled()


# =========================================================================
# Wave bar (top center, 560px)
# =========================================================================

func _build_wave_bar() -> void:
	var panel := PanelContainer.new()
	var sb := Style.panel_box(true)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(560, 0)
	add_child(panel)
	panel.resized.connect(_request_layout)
	_hud_layouts.append(func(rs: Vector2) -> void:
		panel.position = Vector2((rs.x - panel.size.x) * 0.5, 78.0))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)

	# "STAGE 4-7" + italic stage name beneath.
	var stage_col := VBoxContainer.new()
	stage_col.add_theme_constant_override("separation", 1)
	stage_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 4)
	var stage_word := Style.display_label("STAGE", 13, Palette.TX_MUTE)
	stage_word.size_flags_vertical = Control.SIZE_SHRINK_END
	srow.add_child(stage_word)
	_stage_val = Style.display_label(CombatSim.stage_label(), 17, Palette.EMBER_BRIGHT)
	srow.add_child(_stage_val)
	stage_col.add_child(srow)
	_stage_name_lbl = Style.display_label(CombatSim.stage_name, 12, Palette.GOLD, true)
	stage_col.add_child(_stage_name_lbl)
	row.add_child(stage_col)

	# Wave label + Party DPS over the XP-gold progress bar.
	var prog := VBoxContainer.new()
	prog.add_theme_constant_override("separation", 5)
	prog.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prog.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	_wave_lbl = Style.body_label("Wave %d / 5" % CombatSim.wave, 11, Palette.TX_DIM)
	head.add_child(_wave_lbl)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(spacer)
	var dps := HBoxContainer.new()
	dps.add_theme_constant_override("separation", 4)
	dps.add_child(Style.body_label("Party DPS", 11, Palette.TX_DIM))
	var dps_val := Style.pixel_label(CombatSim.party_dps_label, 10, Palette.EMBER_BRIGHT)
	dps_val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dps.add_child(dps_val)
	head.add_child(dps)
	prog.add_child(head)
	_wave_bar = StatBar.new("xp", CombatSim.wave_fill, 9.0)
	prog.add_child(_wave_bar)
	row.add_child(prog)

	# 5 wave pips (done = gold-dim, current = glowing ember).
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 5)
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for n in 5:
		var pip := _Pip.new()
		_pips.append(pip)
		pips.add_child(pip)
	row.add_child(pips)
	_refresh_pips(CombatSim.wave)


func _refresh_pips(wave: int) -> void:
	for i in _pips.size():
		var n := i + 1
		(_pips[i] as _Pip).set_state("done" if n < wave else ("on" if n == wave else ""))


# =========================================================================
# Party Finder (top-left, 232px)
# =========================================================================

func _build_party_finder() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Style.panel_box(true))
	panel.custom_minimum_size = Vector2(232, 0)
	panel.position = Vector2(20, 80)
	add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	panel.add_child(col)

	# Head: icon · PARTY FINDER · 4/4.
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", Style.head_box())
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 10)
	var ico := _icon(_ICON_PROFILE, 14, Palette.EMBER)
	ico.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hrow.add_child(ico)
	hrow.add_child(Style.display_label("PARTY FINDER", 12, Palette.GOLD))
	var hsp := Control.new()
	hsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hsp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hrow.add_child(hsp)
	var online := Style.pixel_label("4/4", 10, Palette.R_UNCOMMON)
	online.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hrow.add_child(online)
	head.add_child(hrow)
	col.add_child(head)

	# 4 member rows.
	var pad := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(m, 8)
	var slots := VBoxContainer.new()
	slots.add_theme_constant_override("separation", 5)
	pad.add_child(slots)
	col.add_child(pad)
	for i in GameContent.PARTY.size():
		slots.add_child(_pf_slot(GameContent.PARTY[i], i))

	# Leave Team (ghost, full width).
	var bpad := MarginContainer.new()
	bpad.add_theme_constant_override("margin_left", 8)
	bpad.add_theme_constant_override("margin_right", 8)
	bpad.add_theme_constant_override("margin_bottom", 8)
	var leave := Style.make_button("Leave Team", "ghost", 11)
	for st in ["normal", "hover", "pressed", "disabled"]:
		var gsb := Style.btn_ghost_box("hover" if st == "hover" else "normal")
		gsb.content_margin_top = 7
		gsb.content_margin_bottom = 7
		leave.add_theme_stylebox_override(st, gsb)
	bpad.add_child(leave)
	col.add_child(bpad)

	var rivets := _Rivets.new()
	rivets.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(rivets)


func _pf_slot(h: Dictionary, idx: int) -> Control:
	var row := PanelContainer.new()
	var normal := _pf_slot_box(false)
	var hover := _pf_slot_box(true)
	row.add_theme_stylebox_override("panel", normal)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.mouse_entered.connect(func() -> void: row.add_theme_stylebox_override("panel", hover))
	row.mouse_exited.connect(func() -> void: row.add_theme_stylebox_override("panel", normal))
	Tip.attach(row, {
		"name": String(h["name"]),
		"type": "%s · %s" % [String(h["cls"]), String(h["role_lbl"])],
		"rarity": "rare",
		"stats": [["Status", "AFK" if idx == 3 else "Online"]],
	})

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(box)

	var portrait := Control.new()
	portrait.custom_minimum_size = Vector2(34, 34)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ps := PixelSlot.new("32²", true)
	portrait.add_child(ps)
	ps.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_child(portrait)

	var meta := VBoxContainer.new()
	meta.add_theme_constant_override("separation", 2)
	meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_child(Style.display_label(String(h["name"]), 13, Palette.TX, true))
	var tag := Style.make_role_tag(String(h["role"]), String(h["role_lbl"]))
	tag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	meta.add_child(tag)
	box.add_child(meta)

	var status: Label
	if idx == 3:
		status = Style.pixel_label("AFK", 8, Palette.TX_MUTE)
	else:
		status = Style.body_label("●", 11, Palette.R_UNCOMMON)
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(status)
	return row


func _pf_slot_box(hover: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("151109")
	sb.set_border_width_all(1)
	sb.border_color = Palette.GOLD_DIM if hover else Palette.IRON_EDGE
	sb.set_corner_radius_all(4)
	for m in ["content_margin_left", "content_margin_right", "content_margin_top", "content_margin_bottom"]:
		sb.set(m, 6.0)
	return sb


# =========================================================================
# Team Aura badge (top-right, below the floating resource strip)
# =========================================================================

func _build_team_aura() -> void:
	var optimal: bool = CombatSim.team_aura_optimal()
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("161210")
	sb.set_border_width_all(1)
	sb.border_color = Palette.GOLD_DIM if optimal else Palette.IRON_EDGE
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 12
	sb.content_margin_right = 16
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	if optimal:
		sb.shadow_color = Palette.with_alpha(Palette.EMBER, 0.3 * Palette.GLOW)
		sb.shadow_size = int(22 * Palette.GLOW)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_child(panel)
	panel.resized.connect(_request_layout)
	_hud_layouts.append(func(rs: Vector2) -> void:
		panel.position = Vector2(rs.x - 20.0 - panel.size.x, 80.0))

	var tip := {
		"name": "Team Aura: Optimal" if optimal else "Team Aura: Unbalanced",
		"type": "Composition bonus",
		"rarity": "legendary" if optimal else "common",
		"flavor": "A balanced delve burns brightest." if optimal else "Need 1 tank, 1 healer, 2 different DPS.",
	}
	if optimal:
		tip["stats"] = [["All stats", "+18%"], ["Comp", "1 Tank · 1 Healer · 2 DPS"]]
	Tip.attach(panel, tip)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 11)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)

	var glyph := Style.body_label("◆", 22, Palette.EMBER_BRIGHT if optimal else Palette.TX_MUTE)
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if optimal:
		glyph.add_theme_constant_override("outline_size", 8)
		glyph.add_theme_color_override("font_outline_color", Palette.with_alpha(Palette.EMBER, 0.5 * Palette.GLOW))
		var tw := glyph.create_tween().set_loops()
		tw.tween_property(glyph, "modulate:a", 1.0, 1.3).from(0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(glyph, "modulate:a", 0.5, 1.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	row.add_child(glyph)

	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 1)
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.add_child(Style.display_label("TEAM AURA · OPTIMAL" if optimal else "TEAM AURA", 12, Palette.GOLD_BRIGHT if optimal else Palette.TX_DIM))
	text.add_child(Style.body_label("+18% all stats" if optimal else "Comp unbalanced", 11, Palette.CYAN_BRIGHT if optimal else Palette.TX_MUTE))
	row.add_child(text)


# =========================================================================
# Auto-loot ticker (right edge, under the aura badge)
# =========================================================================

func _build_loot_ticker() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Style.panel_box(true))
	panel.custom_minimum_size = Vector2(232, 0)
	add_child(panel)
	_hud_layouts.append(func(rs: Vector2) -> void:
		panel.position = Vector2(rs.x - 20.0 - 232.0, 146.0))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	panel.add_child(col)

	var head := PanelContainer.new()
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = Color(60.0 / 255.0, 50.0 / 255.0, 32.0 / 255.0, 0.22)
	hsb.border_width_bottom = 1
	hsb.border_color = Palette.IRON_EDGE
	hsb.content_margin_left = 12
	hsb.content_margin_right = 12
	hsb.content_margin_top = 9
	hsb.content_margin_bottom = 9
	head.add_theme_stylebox_override("panel", hsb)
	head.add_child(Style.display_label("AUTO-LOOT", 11, Palette.GOLD))
	col.add_child(head)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 8)
	pad.add_theme_constant_override("margin_bottom", 8)
	_loot_list = VBoxContainer.new()
	_loot_list.add_theme_constant_override("separation", 6)
	pad.add_child(_loot_list)
	col.add_child(pad)

	# Seed with the first feed entries (matches the design's initial state).
	for i in 4:
		_push_loot(GameContent.LOOT_FEED[i], false)


func _push_loot(entry: Array, animate: bool) -> void:
	var row := RichTextLabel.new()
	row.bbcode_enabled = true
	row.fit_content = true
	row.scroll_active = false
	row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size"]:
		row.add_theme_font_size_override(k, 11)
	var italic := Fonts.display_italic()
	if italic != null:
		row.add_theme_font_override("italics_font", italic)
	row.text = "[color=#%s][b]%s[/b][/color] [color=#%s]%s[/color] [color=#%s][i]%s[/i][/color]" % [
		Palette.TX_DIM.to_html(false), String(entry[0]),
		Palette.TX_FAINT.to_html(false), String(entry[1]),
		Palette.rarity_color(String(entry[3])).to_html(false), String(entry[2]),
	]
	_loot_list.add_child(row)
	if animate:
		_loot_list.move_child(row, 0)
		row.modulate = Color(1, 1, 1, 0.0)
		call_deferred("_loot_slide_in", row)
	while _loot_list.get_child_count() > 9:
		var last := _loot_list.get_child(_loot_list.get_child_count() - 1)
		_loot_list.remove_child(last)
		last.queue_free()


func _loot_slide_in(row: Control) -> void:
	if not is_instance_valid(row):
		return
	var target_x := row.position.x
	row.position.x = target_x + 10.0
	var tw := row.create_tween()
	tw.set_parallel(true)
	tw.tween_property(row, "position:x", target_x, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(row, "modulate:a", 1.0, 0.3)


# =========================================================================
# Hero HUD (bottom-left, 4 × 216px frames)
# =========================================================================

func _build_hero_hud() -> void:
	var hud := HBoxContainer.new()
	hud.add_theme_constant_override("separation", 8)
	add_child(hud)
	hud.resized.connect(_request_layout)
	_hud_layouts.append(func(rs: Vector2) -> void:
		hud.position = Vector2(16.0, rs.y - 18.0 - hud.size.y))
	for i in GameContent.PARTY.size():
		hud.add_child(_hero_frame(GameContent.PARTY[i], i))


func _hero_frame(h: Dictionary, idx: int) -> Control:
	var frame := Control.new()
	frame.custom_minimum_size = Vector2(216, 72)
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	Tip.attach(frame, {
		"name": String(h["name"]),
		"type": "%s · Lv %d" % [String(h["cls"]), int(h["lvl"])],
		"rarity": "legendary",
		"stats": [["HP", "184,000"], ["Mana", "9,200"], ["Crit", "42%"]],
		"flavor": "Auto-casting skills when ready.",
	})

	var bg := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("161310")
	sb.set_border_width_all(1)
	sb.border_color = Palette.IRON_EDGE
	sb.set_corner_radius_all(5)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 11
	sb.shadow_offset = Vector2(0, 4)
	bg.add_theme_stylebox_override("panel", sb)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Role-colored 2px bottom edge.
	var strip := ColorRect.new()
	strip.color = Palette.role_color(String(h["role"]))
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(strip)
	strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	strip.offset_left = 1
	strip.offset_right = -1
	strip.offset_top = -3
	strip.offset_bottom = -1

	var pad := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(m, 9)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(pad)
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(row)

	# Portrait with the role tag chip hanging below center.
	var portrait := Control.new()
	portrait.custom_minimum_size = Vector2(54, 54)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ps := PixelSlot.new("56²\n%s" % String(h["name"]), true)
	portrait.add_child(ps)
	ps.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var chip := Style.make_role_tag(String(h["role"]), String(h["role_lbl"]))
	chip.resized.connect(func() -> void:
		chip.position = Vector2(27.0 - chip.size.x * 0.5, 54.0 + 6.0 - chip.size.y))
	portrait.add_child(chip)
	row.add_child(portrait)

	# Name + LV over live hp/mana bars.
	var bars := VBoxContainer.new()
	bars.add_theme_constant_override("separation", 4)
	bars.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nrow := HBoxContainer.new()
	nrow.add_theme_constant_override("separation", 6)
	var name_lbl := Style.display_label(String(h["name"]), 14, Palette.TX, true)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.clip_text = true
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nrow.add_child(name_lbl)
	var lv := Style.pixel_label(str(int(h["lvl"])), 9, Palette.EMBER_BRIGHT)
	lv.size_flags_vertical = Control.SIZE_SHRINK_END
	nrow.add_child(lv)
	bars.add_child(nrow)

	var hp0 := float(h["hp"])
	var mana0 := float(h["mana"])
	if idx < CombatSim.party_hp.size():
		hp0 = float(CombatSim.party_hp[idx])
	if idx < CombatSim.party_mana.size():
		mana0 = float(CombatSim.party_mana[idx])
	var hp_bar := StatBar.new("hp", hp0, 8.0)
	bars.add_child(hp_bar)
	_hp_bars.append(hp_bar)
	var mana_bar := StatBar.new("mana", mana0, 6.0)
	bars.add_child(mana_bar)
	_mana_bars.append(mana_bar)
	row.add_child(bars)

	# 3 skill pips: first ready (ember + glow), others shaded cooldowns.
	var skills := VBoxContainer.new()
	skills.add_theme_constant_override("separation", 4)
	skills.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	skills.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for s in 3:
		skills.add_child(_SkillPip.new(s == 0, float(s) * 0.3))
	row.add_child(skills)
	return frame


# =========================================================================
# Control cluster (bottom-right)
# =========================================================================

func _build_controls() -> void:
	var panel := PanelContainer.new()
	var sb := Style.panel_box(true)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	panel.resized.connect(_request_layout)
	_hud_layouts.append(func(rs: Vector2) -> void:
		panel.position = Vector2(rs.x - 20.0 - panel.size.x, rs.y - 18.0 - panel.size.y))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	# SPEED 1× / 2× / 4×.
	var group := HBoxContainer.new()
	group.add_theme_constant_override("separation", 5)
	var lbl := Style.body_label("SPEED", 10, Palette.TX_MUTE)
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	group.add_child(lbl)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(4, 0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_child(gap)
	for s in [1, 2, 4]:
		var b := Button.new()
		b.text = "%d×" % s
		b.focus_mode = Control.FOCUS_NONE
		var pf := Fonts.pixel()
		if pf != null:
			b.add_theme_font_override("font", pf)
		b.add_theme_font_size_override("font_size", 10)
		b.custom_minimum_size = Vector2(30, 28)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var speed := int(s)
		b.pressed.connect(func() -> void: CombatSim.speed = speed)
		_speed_btns[speed] = b
		group.add_child(b)
	row.add_child(group)
	_refresh_speed(CombatSim.speed)

	var div := ColorRect.new()
	div.color = Palette.IRON_EDGE
	div.custom_minimum_size = Vector2(1, 28)
	div.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(div)

	# Auto-Skill Z / Auto-Advance X toggle pills.
	_tog_skill = _make_toggle("Auto-Skill", "Z", func() -> void:
		CombatSim.auto_skill = not CombatSim.auto_skill)
	var skill_panel := _tog_skill["panel"] as Control
	Tip.attach(skill_panel, func() -> Dictionary: return {
		"name": "Auto-Skill",
		"type": "ON" if CombatSim.auto_skill else "OFF",
		"rarity": "rare",
		"flavor": "Heroes cast abilities automatically when off cooldown.",
	})
	row.add_child(skill_panel)

	_tog_adv = _make_toggle("Auto-Advance", "X", func() -> void:
		CombatSim.auto_advance = not CombatSim.auto_advance)
	var adv_panel := _tog_adv["panel"] as Control
	Tip.attach(adv_panel, func() -> Dictionary: return {
		"name": "Auto-Advance",
		"type": "ON" if CombatSim.auto_advance else "OFF",
		"rarity": "rare",
		"flavor": "Party pushes to the next stage on clear.",
	})
	row.add_child(adv_panel)
	_on_toggles_changed(CombatSim.auto_skill, CombatSim.auto_advance)

	# Retreat (ghost + Esc keycap).
	var retreat := PanelContainer.new()
	retreat.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var rnorm := Style.btn_ghost_box()
	var rhover := Style.btn_ghost_box("hover")
	for b2 in [rnorm, rhover]:
		b2.content_margin_left = 11
		b2.content_margin_right = 11
		b2.content_margin_top = 7
		b2.content_margin_bottom = 7
	retreat.add_theme_stylebox_override("panel", rnorm)
	var rrow := HBoxContainer.new()
	rrow.add_theme_constant_override("separation", 9)
	rrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rlbl := Style.display_label("RETREAT", 11, Palette.TX_DIM)
	rrow.add_child(rlbl)
	rrow.add_child(Style.make_keycap("Esc"))
	retreat.add_child(rrow)
	retreat.mouse_entered.connect(func() -> void:
		retreat.add_theme_stylebox_override("panel", rhover)
		rlbl.add_theme_color_override("font_color", Palette.TX))
	retreat.mouse_exited.connect(func() -> void:
		retreat.add_theme_stylebox_override("panel", rnorm)
		rlbl.add_theme_color_override("font_color", Palette.TX_DIM))
	_connect_press(retreat, func() -> void: CombatSim.retreat())
	row.add_child(retreat)

	var rivets := _Rivets.new()
	rivets.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(rivets)


func _make_toggle(text: String, hotkey: String, on_press: Callable) -> Dictionary:
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot := _Dot.new()
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(dot)
	var lbl := Style.body_label(text, 11, Palette.TX_MUTE)
	box.add_child(lbl)
	box.add_child(Style.make_keycap(hotkey))
	panel.add_child(box)
	_connect_press(panel, on_press)
	return {"panel": panel, "dot": dot, "label": lbl}


func _refresh_toggle(t: Dictionary, on: bool) -> void:
	if t.is_empty():
		return
	(t["panel"] as PanelContainer).add_theme_stylebox_override("panel", _toggle_box(on))
	(t["dot"] as _Dot).set_state(Palette.CYAN if on else Palette.TX_FAINT, on)
	(t["label"] as Label).add_theme_color_override("font_color", Palette.TX if on else Palette.TX_MUTE)


func _refresh_speed(current: int) -> void:
	for s in _speed_btns:
		var on := int(s) == current
		var b := _speed_btns[s] as Button
		for st in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, _cc_btn_box(on))
		var fc := Color("1c0f04") if on else Palette.TX_DIM
		b.add_theme_color_override("font_color", fc)
		b.add_theme_color_override("font_hover_color", Color("1c0f04") if on else Palette.TX)
		b.add_theme_color_override("font_pressed_color", fc)


func _cc_btn_box(on: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(3)
	sb.set_border_width_all(1)
	if on:
		sb.bg_color = Palette.EMBER
		sb.border_color = Color("3a1d08")
		sb.shadow_color = Palette.with_alpha(Palette.EMBER, 0.4 * Palette.GLOW)
		sb.shadow_size = int(12 * Palette.GLOW)
	else:
		sb.bg_color = Color("3c3529")
		sb.border_color = Palette.IRON_EDGE
	return sb


func _toggle_box(on: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(1)
	sb.border_color = Palette.CYAN_DEEP if on else Palette.IRON_EDGE
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	return sb


# =========================================================================
# "Welcome back, delver" offline-gains popup
# =========================================================================

func _build_popup() -> void:
	_popup = PanelContainer.new()
	_popup.add_theme_stylebox_override("panel", Style.modal_box())
	_popup.custom_minimum_size = Vector2(460, 0)
	add_child(_popup)
	_popup.resized.connect(_request_layout)
	_popup.position = Vector2(0, 290)
	_hud_layouts.append(func(rs: Vector2) -> void:
		_popup.position.x = rs.x * 0.5 - 30.0 - _popup.size.x * 0.5)

	# Reward numbers: live offline sim if any, else the design sample.
	var away := "2h 14m"
	var gold_s := "18,400"
	var levels_s := "+3"
	var items_s := "12"
	var rewards: Dictionary = CombatSim.offline_rewards
	if not rewards.is_empty():
		away = CombatSim.format_away(int(rewards["seconds"]))
		gold_s = Style.group_int(int(rewards["gold"]))
		levels_s = "+%d" % int(rewards["levels"])
		items_s = str(int(rewards["items"]))

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 26)
	pad.add_theme_constant_override("margin_right", 26)
	pad.add_theme_constant_override("margin_top", 22)
	pad.add_theme_constant_override("margin_bottom", 20)
	_popup.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	pad.add_child(col)

	var title := Style.display_label("Welcome back, delver", 26, Palette.GOLD_BRIGHT, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var sub_pad := MarginContainer.new()
	sub_pad.add_theme_constant_override("margin_top", 4)
	var sub := HBoxContainer.new()
	sub.alignment = BoxContainer.ALIGNMENT_CENTER
	sub.add_theme_constant_override("separation", 0)
	sub.add_child(Style.body_label("While away ", 13, Palette.TX_DIM))
	sub.add_child(Style.body_label(away, 13, Palette.EMBER_BRIGHT))
	sub.add_child(Style.body_label(", your party fought on:", 13, Palette.TX_DIM))
	sub_pad.add_child(sub)
	col.add_child(sub_pad)

	var gains_pad := MarginContainer.new()
	gains_pad.add_theme_constant_override("margin_top", 18)
	gains_pad.add_theme_constant_override("margin_bottom", 18)
	var gains := HBoxContainer.new()
	gains.add_theme_constant_override("separation", 14)
	gains.add_child(_gain_card(_ICON_GOLD, gold_s, "Gold"))
	gains.add_child(_gain_card(_ICON_CREST, levels_s, "Levels"))
	gains.add_child(_gain_card(_ICON_SOULSTONE, items_s, "Items"))
	gains_pad.add_child(gains)
	col.add_child(gains_pad)

	# Collect Rewards ↵ (ember CTA, full width).
	var collect := PanelContainer.new()
	var cnorm := Style.btn_ember_box()
	var chover := Style.btn_ember_box("hover")
	for b in [cnorm, chover]:
		b.content_margin_top = 12
		b.content_margin_bottom = 12
	collect.add_theme_stylebox_override("panel", cnorm)
	var crow := HBoxContainer.new()
	crow.alignment = BoxContainer.ALIGNMENT_CENTER
	crow.add_theme_constant_override("separation", 9)
	crow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crow.add_child(Style.display_label("COLLECT REWARDS", 13, Color("1c0f04")))
	crow.add_child(Style.make_keycap("↵"))
	collect.add_child(crow)
	collect.mouse_entered.connect(func() -> void: collect.add_theme_stylebox_override("panel", chover))
	collect.mouse_exited.connect(func() -> void: collect.add_theme_stylebox_override("panel", cnorm))
	_connect_press(collect, _collect_rewards)
	col.add_child(collect)

	var rivets := _Rivets.new()
	rivets.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup.add_child(rivets)

	# ✕ close, top-right.
	var x_holder := Control.new()
	x_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup.add_child(x_holder)
	var x := Button.new()
	x.text = "✕"
	x.focus_mode = Control.FOCUS_NONE
	x.add_theme_font_size_override("font_size", 18)
	x.add_theme_color_override("font_color", Palette.TX_DIM)
	x.add_theme_color_override("font_hover_color", Palette.EMBER_BRIGHT)
	x.add_theme_color_override("font_pressed_color", Palette.EMBER_BRIGHT)
	var xsb := StyleBoxFlat.new()
	xsb.bg_color = Palette.STONE
	xsb.set_border_width_all(1)
	xsb.border_color = Palette.IRON_EDGE
	xsb.set_corner_radius_all(3)
	for st in ["normal", "hover", "pressed"]:
		x.add_theme_stylebox_override(st, xsb)
	x.pressed.connect(func() -> void: _popup.visible = false)
	x_holder.add_child(x)
	x.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	x.offset_left = -46
	x.offset_top = 10
	x.offset_right = -10
	x.offset_bottom = 46

	_popup.modulate = Color(1, 1, 1, 0.0)


func _gain_card(icon_path: String, value: String, label_text: String) -> Control:
	var card := PanelContainer.new()
	var sb := Style.inset_box(5)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	card.add_theme_stylebox_override("panel", sb)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	card.add_child(col)
	var ico := _icon(icon_path, 18, Color.WHITE)
	ico.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(ico)
	var val := Style.pixel_label(value, 15, Palette.EMBER_BRIGHT)
	val.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(val)
	var lbl := Style.body_label(label_text.to_upper(), 10, Palette.TX_MUTE)
	lbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(lbl)
	return card


func _animate_popup_in() -> void:
	if _popup == null:
		return
	_popup.pivot_offset = _popup.size * 0.5
	_popup.position.y = 308.0
	_popup.scale = Vector2(0.985, 0.985)
	var tw := _popup.create_tween()
	tw.set_parallel(true)
	tw.tween_property(_popup, "modulate:a", 1.0, 0.3)
	tw.tween_property(_popup, "position:y", 290.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_popup, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _collect_rewards() -> void:
	CombatSim.collect_offline()
	_popup.visible = false


# =========================================================================
# EventBus → HUD
# =========================================================================

func _on_wave_progress(fill: float) -> void:
	_wave_bar.pct = fill


func _on_wave_changed(wave: int) -> void:
	_wave_lbl.text = "Wave %d / 5" % wave
	_refresh_pips(wave)


func _on_stage_changed(label_text: String, stage_name: String) -> void:
	_stage_val.text = label_text
	_stage_name_lbl.text = stage_name
	_on_wave_changed(CombatSim.wave)


func _on_loot(entry: Array) -> void:
	_push_loot(entry, true)


func _on_party_vitals(hp: Array, mana: Array) -> void:
	for i in mini(_hp_bars.size(), hp.size()):
		(_hp_bars[i] as StatBar).pct = float(hp[i])
	for i in mini(_mana_bars.size(), mana.size()):
		(_mana_bars[i] as StatBar).pct = float(mana[i])


func _on_speed_changed(speed: int) -> void:
	_refresh_speed(speed)


func _on_toggles_changed(auto_skill: bool, auto_advance: bool) -> void:
	_refresh_toggle(_tog_skill, auto_skill)
	_refresh_toggle(_tog_adv, auto_advance)


# =========================================================================
# Helpers
# =========================================================================

## Left-click handler for PanelContainer-based "buttons".
func _connect_press(c: Control, on_press: Callable) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	c.gui_input.connect(func(ev: InputEvent) -> void:
		var mb := ev as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			on_press.call())


func _icon(path: String, px: float, color: Color) -> TextureRect:
	var ic := TextureRect.new()
	ic.custom_minimum_size = Vector2(px, px)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.modulate = color
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(path):
		ic.texture = load(path) as Texture2D
	return ic


func _request_layout() -> void:
	if _layout_pending:
		return
	_layout_pending = true
	call_deferred("_run_layout")


func _run_layout() -> void:
	_layout_pending = false
	var rs := size
	for fn in _hud_layouts:
		fn.call(rs)


# =========================================================================
# Tiny draw classes
# =========================================================================

## Wave pip: dark socket / gold-dim done / glowing ember current.
class _Pip:
	extends Control

	var state := ""

	func _init() -> void:
		custom_minimum_size = Vector2(9, 9)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_state(s: String) -> void:
		state = s
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		match state:
			"on":
				draw_circle(c, 8.0, Palette.with_alpha(Palette.EMBER, 0.25 * Palette.GLOW))
				draw_circle(c, 4.5, Palette.EMBER_BRIGHT)
			"done":
				draw_circle(c, 4.5, Palette.GOLD_DIM)
			_:
				draw_circle(c, 4.5, Color("0c0a07"))
				draw_arc(c, 4.0, 0.0, TAU, 24, Palette.IRON_EDGE, 1.0)


## Skill pip (20×14): ready = ember fill + glow; cooling = dark with a
## black shade covering everything below the cooldown line.
class _SkillPip:
	extends Control

	var ready_state := false
	var shade_from := 0.0

	func _init(p_ready: bool, p_shade: float) -> void:
		ready_state = p_ready
		shade_from = p_shade
		custom_minimum_size = Vector2(20, 14)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if ready_state:
			var half := size.y * 0.5
			draw_rect(Rect2(0, 0, size.x, half), Palette.EMBER_BRIGHT)
			draw_rect(Rect2(0, half, size.x, size.y - half), Palette.EMBER_DEEP)
			draw_rect(Rect2(1, 1, size.x - 2.0, size.y - 2.0), Palette.with_alpha(Palette.EMBER, 0.35), false, 2.0)
			draw_rect(r, Palette.EMBER, false, 1.0)
		else:
			draw_rect(r, Color("0c0a07"))
			draw_rect(Rect2(0, size.y * shade_from, size.x, size.y * (1.0 - shade_from)), Color(0, 0, 0, 0.6))
			draw_rect(r, Palette.IRON_EDGE, false, 1.0)


## Toggle status dot (8px), cyan + glow when on.
class _Dot:
	extends Control

	var color := Color.WHITE
	var glow := false

	func _init() -> void:
		custom_minimum_size = Vector2(8, 8)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_state(c: Color, g: bool) -> void:
		color = c
		glow = g
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		if glow:
			draw_circle(c, 7.0, Palette.with_alpha(color, 0.25 * Palette.GLOW))
		draw_circle(c, 4.0, color)


## Corner rivets (.frame.riveted), purely decorative.
class _Rivets:
	extends Control

	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		if size.x < 40.0:
			return
		for x in [10.0, size.x - 10.0]:
			draw_circle(Vector2(x, 10.0), 3.5, Color.BLACK)
			draw_circle(Vector2(x, 10.0), 3.0, Color("4a4234"))
			draw_circle(Vector2(x - 1.0, 9.0), 1.2, Color(1, 1, 1, 0.15))
