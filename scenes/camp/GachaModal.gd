extends "res://scenes/camp/ModalShell.gd"
## WISHING WELL modal (camp.jsx GachaModal): banner header, results stage with
## jiggle → pop-flip card reveals, rates + pity footer, ×1 / ×10 wish actions.
## Wishes roll through GameContent.gacha_roll_rarity with a running pity
## counter (legendary resets to 0) and spend stardrops via GameState. A big
## pull (epic+) ends in a CELEBRATION: sunburst spin, confetti rain, best-pull
## bounce, a "✦ joins the party! ✦" cheer ribbon, and the stage border glowing
## in the best rarity. Q / E wish while the modal is open.

var _rng := RandomNumberGenerator.new()
var _rolling := false
var _has_results := false
var _last_count := 1  # the ×N of the most recent wish — drives "Wish again ×N"

var _idle_box: VBoxContainer
var _stage_center: CenterContainer
var _stage_panel: PanelContainer
var _grid: GridContainer = null
var _celebrate_fx: _Celebrate = null
var _cheer: Label = null
var _again_btn: Button
var _back_btn: Button
var _x1_btn: Button
var _x10_btn: Button
var _pity_bar: StatBar
var _pity_num: Label
var _soft_lbl: Label
var _notice: Label  # transient status flash (e.g. not enough stardrops)
var _notice_tw: Tween


func _init() -> void:
	modal_title = "Wishing Well"
	modal_width = 1120.0
	body_separation = 16
	_rng.randomize()


func _build_body(body: VBoxContainer) -> void:
	body.add_child(_build_banner())
	body.add_child(_build_stage())
	body.add_child(_build_foot())
	EventBus.pity_changed.connect(_refresh_pity)
	_refresh_pity(GameState.pity)


func _on_modal_key(keycode: Key) -> bool:
	match keycode:
		KEY_Q:
			_do_pull(1)
			return true
		KEY_E:
			_do_pull(10)
			return true
	return false


# =========================================================================
# Banner (.gacha-banner)
# =========================================================================

func _build_banner() -> Control:
	var banner := HBoxContainer.new()
	banner.add_theme_constant_override("separation", 18)

	# Art: flex-1 × 200, gold-dim border, pulsing altar glow.
	var art := Control.new()
	art.custom_minimum_size = Vector2(0, 200)
	art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ps := PixelSlot.new("560×300\nbanner splash — featured pal", true)
	art.add_child(ps)
	ps.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var glow := _FX.Glow.new(
		[[0.0, Palette.with_alpha(Palette.EMBER, 0.55)], [0.68, Palette.with_alpha(Palette.EMBER, 0.0)]],
		3.4, 0.5, 1.0)
	art.add_child(glow)
	glow.anchor_left = 0.2
	glow.anchor_right = 0.8
	glow.anchor_top = 0.33
	glow.anchor_bottom = 0.83
	var border := Panel.new()
	var bsb := StyleBoxFlat.new()
	bsb.draw_center = false
	bsb.set_border_width_all(1)
	bsb.border_color = Palette.GOLD_DIM
	bsb.set_corner_radius_all(5)
	border.add_theme_stylebox_override("panel", bsb)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.add_child(border)
	border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	banner.add_child(art)

	# Meta column, 300 wide, vertically centered.
	var meta := VBoxContainer.new()
	meta.custom_minimum_size = Vector2(300, 0)
	meta.add_theme_constant_override("separation", 7)
	meta.alignment = BoxContainer.ALIGNMENT_CENTER
	meta.add_child(Style.pixel_label("Limited Banner", 9, Palette.EMBER_DEEP))
	meta.add_child(Style.display_label("Starfall Friends", 30, Palette.GOLD_DIM, true))
	var sub := HBoxContainer.new()
	sub.add_theme_constant_override("separation", 0)
	sub.add_child(Style.body_label("Rate-up: ", 13, Palette.TX_DIM))
	sub.add_child(Style.body_label("Pyra, the Emberpuff", 13, Palette.R_LEGENDARY))
	meta.add_child(sub)
	var timer := HBoxContainer.new()
	timer.add_theme_constant_override("separation", 8)
	timer.add_child(Style.make_keycap("⏳"))
	var ends := Style.body_label("Ends in 5d 12h 40m", 12, Palette.TX_MUTE)
	ends.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	timer.add_child(ends)
	meta.add_child(timer)
	banner.add_child(meta)
	return banner


# =========================================================================
# Stage (.gacha-stage): idle altar OR pull-card grid
# =========================================================================

func _build_stage() -> Control:
	var stage := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(1)
	sb.border_color = Palette.IRON_EDGE
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	stage.add_theme_stylebox_override("panel", sb)
	stage.custom_minimum_size = Vector2(0, 260)
	_stage_panel = stage

	# Faint warm radial behind everything.
	var wash := _FX.Glow.new(
		[[0.0, Palette.with_alpha(Palette.EMBER, 0.08)], [0.7, Palette.with_alpha(Palette.EMBER, 0.0)]])
	wash.center_frac = Vector2(0.5, 0.45)
	wash.radius_frac = Vector2(0.6, 0.8)
	stage.add_child(wash)

	_stage_center = CenterContainer.new()
	stage.add_child(_stage_center)

	# Idle: 220×200 altar + hint.
	_idle_box = VBoxContainer.new()
	_idle_box.add_theme_constant_override("separation", 12)
	_idle_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var altar := Control.new()
	altar.custom_minimum_size = Vector2(220, 200)
	altar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	altar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var aps := PixelSlot.new("300×260\nwell idle", true)
	altar.add_child(aps)
	aps.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var aglow := _FX.Glow.new(
		[[0.0, Palette.with_alpha(Palette.EMBER, 0.55)], [0.68, Palette.with_alpha(Palette.EMBER, 0.0)]],
		3.4, 0.5, 1.0)
	altar.add_child(aglow)
	aglow.anchor_left = 0.15
	aglow.anchor_right = 0.85
	aglow.anchor_top = 0.28
	aglow.anchor_bottom = 0.88
	var aborder := Panel.new()
	var absb := StyleBoxFlat.new()
	absb.draw_center = false
	absb.set_border_width_all(1)
	absb.border_color = Palette.GOLD_DIM
	absb.set_corner_radius_all(6)
	aborder.add_theme_stylebox_override("panel", absb)
	aborder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	altar.add_child(aborder)
	aborder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_idle_box.add_child(altar)
	var hint := Style.display_label("Toss in stardrops to wish for wonderful gear.", 13, Palette.TX_MUTE, true)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_idle_box.add_child(hint)
	_stage_center.add_child(_idle_box)
	return stage


## One pull card: gold-dim "?" back that flips to a rarity-framed front.
func _make_card(hero: Dictionary, card_size: Vector2, delay: float) -> Control:
	var rar := String(hero["r"])
	var rc := Palette.rarity_color(rar)

	var card := Control.new()
	card.custom_minimum_size = card_size
	card.pivot_offset = card_size * 0.5
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Back face (.pull-back): gold-dim border + "?" keycap.
	var back := Panel.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color("181410")
	bsb.set_border_width_all(1)
	bsb.border_color = Palette.GOLD_DIM
	bsb.set_corner_radius_all(5)
	back.add_theme_stylebox_override("panel", bsb)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(back)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bcenter := CenterContainer.new()
	bcenter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(bcenter)
	bcenter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bcenter.add_child(Style.make_keycap("?", 14))

	# Front face (.pull-front): rarity border + glow, sprite, name, role.
	var front := Panel.new()
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color("141209").lerp(rc, 0.08)
	fsb.set_border_width_all(1)
	fsb.border_color = rc
	fsb.set_corner_radius_all(5)
	fsb.shadow_color = Palette.with_alpha(rc, 0.45 * Palette.GLOW)
	fsb.shadow_size = int(16 * Palette.GLOW)
	front.add_theme_stylebox_override("panel", fsb)
	front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	front.visible = false
	card.add_child(front)
	front.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fpad := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		fpad.add_theme_constant_override(m, 8)
	fpad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	front.add_child(fpad)
	fpad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fcol := VBoxContainer.new()
	fcol.add_theme_constant_override("separation", 6)
	fcol.alignment = BoxContainer.ALIGNMENT_CENTER
	fpad.add_child(fcol)
	# The pull is GEAR — show its slot glyph, rarity-tinted, like the rest of the UI.
	var sprite := GearIcon.new(GearIcon.kind_for_slot(String(hero.get("slot", ""))), rc)
	var sd := card_size.x * 0.8
	sprite.custom_minimum_size = Vector2(sd, sd)
	sprite.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	fcol.add_child(sprite)
	var nm := Style.display_label(String(hero["n"]), 16, rc, true)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fcol.add_child(nm)
	# A pull rolls GEAR now: show its slot + item level (not a hero role).
	var sub := Style.body_label("%s · ilvl %d" % [String(hero.get("slot", "Gear")), int(hero.get("ilvl", 0))], 9, Palette.TX_MUTE)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fcol.add_child(sub)

	# Shine sweep on epic+ reveals: a white wash that flashes then fades.
	var shine: ColorRect = null
	if GameContent.RARITY_RANK.get(rar, 0) >= 3:
		shine = ColorRect.new()
		shine.color = Color(1, 1, 1, 0.0)
		shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
		front.add_child(shine)
		shine.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# REVEAL: excited jiggle, squash-flip, pop-overshoot, settle (design's
	# card jiggle → pop flip). The shine sweeps as the front lands.
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_property(card, "rotation_degrees", -4.0, 0.05)
	tw.tween_property(card, "rotation_degrees", 4.0, 0.09)
	tw.tween_property(card, "rotation_degrees", -2.5, 0.08)
	tw.tween_property(card, "rotation_degrees", 0.0, 0.06)
	tw.tween_property(card, "scale:x", 0.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		back.visible = false
		front.visible = true
		if shine != null:
			var stw := shine.create_tween()
			stw.tween_property(shine, "color:a", 0.55, 0.1)
			stw.tween_property(shine, "color:a", 0.0, 0.35))
	tw.tween_property(card, "scale:x", 1.12, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "scale:x", 1.0, 0.12).set_trans(Tween.TRANS_SINE)
	return card


func _show_results(pulls: Array) -> void:
	if _grid != null:
		_grid.queue_free()
	_clear_celebration_fx()  # a fresh wish clears the previous fireworks
	_idle_box.visible = false
	_has_results = true
	var single := pulls.size() == 1
	_grid = GridContainer.new()
	_grid.columns = 1 if single else 5
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	var card_size := Vector2(180, 240) if single else Vector2(168, 224)
	for i in pulls.size():
		var delay := 0.36 if single else 0.36 + float(i) * 0.15
		_grid.add_child(_make_card(pulls[i], card_size, delay))
	_stage_center.add_child(_grid)


# =========================================================================
# Footer (.gacha-foot): rates + pity | action column
# =========================================================================

func _build_foot() -> Control:
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 18)

	# Rates inset box.
	var rates := PanelContainer.new()
	var rb := Style.inset_box(5)
	rb.content_margin_left = 16
	rb.content_margin_right = 16
	rb.content_margin_top = 12
	rb.content_margin_bottom = 12
	rates.add_theme_stylebox_override("panel", rb)
	rates.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rcol := VBoxContainer.new()
	rcol.add_theme_constant_override("separation", 6)
	rates.add_child(rcol)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 6)
	grid.add_child(_rate_row(Palette.R_LEGENDARY, "5★ Legendary", "0.60%"))
	grid.add_child(_rate_row(Palette.R_EPIC, "4★ Epic", "5.10%"))
	grid.add_child(_rate_row(Palette.R_RARE, "3★ Rare", "18.0%"))
	rcol.add_child(grid)

	# Pity block.
	var pity := VBoxContainer.new()
	pity.add_theme_constant_override("separation", 5)
	rcol.add_child(pity)
	pity.add_child(Style.body_label("PITY TO GUARANTEED 5★", 10, Palette.TX_MUTE))
	var hard_pity := Balance.inum("gacha.hard_pity", GameContent.PITY_HARD)
	_pity_bar = StatBar.new("xp", float(GameState.pity) / float(hard_pity) * 100.0, 8.0)
	_pity_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pity.add_child(_pity_bar)
	var num_row := HBoxContainer.new()
	num_row.add_theme_constant_override("separation", 0)
	_pity_num = Style.pixel_label(str(GameState.pity), 11, Palette.EMBER_BRIGHT)
	_pity_num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	num_row.add_child(_pity_num)
	num_row.add_child(Style.body_label(" / %d " % hard_pity, 11, Palette.TX_DIM))
	_soft_lbl = Style.body_label("· soft pity active", 11, Palette.EMBER_BRIGHT)
	_soft_lbl.visible = false
	num_row.add_child(_soft_lbl)
	pity.add_child(num_row)
	foot.add_child(rates)

	# Action column (280 wide).
	var actions := VBoxContainer.new()
	actions.custom_minimum_size = Vector2(280, 0)
	actions.add_theme_constant_override("separation", 10)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	# "Wish again" repeats whatever count you last wished (×1 or ×10).
	_again_btn = Style.make_button("Wish again ×1", "ghost")
	_again_btn.visible = false
	_again_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_again_btn.pressed.connect(func() -> void: _do_pull(_last_count))
	actions.add_child(_again_btn)
	_x1_btn = Style.make_button("×1 Wish   Q", "stone", 14)
	_x1_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_x1_btn.pressed.connect(func() -> void: _do_pull(1))
	Tip.attach(_x1_btn, {
		"name": "Single Wish",
		"type": "Cost: %s Stardrops" % Style.group_int(Balance.inum("gacha.cost_x1", GameContent.GACHA_COST_X1)),
		"rarity": "rare"})
	actions.add_child(_x1_btn)
	_x10_btn = Style.make_button("×10 Multi-Wish   E", "ember", 14)
	_x10_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_x10_btn.pressed.connect(func() -> void: _do_pull(10))
	Tip.attach(_x10_btn, {
		"name": "Ten Wishes",
		"type": "Cost: %s Stardrops" % Style.group_int(Balance.inum("gacha.cost_x10", GameContent.GACHA_COST_X10)),
		"rarity": "legendary",
		"flavor": "Guarantees at least one 4★ or higher!"})
	actions.add_child(_x10_btn)
	# Shown only while results are on screen — return to the pre-wish well.
	_back_btn = Style.make_button("← Back to the Well", "stone", 14)
	_back_btn.visible = false
	_back_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_back_btn.pressed.connect(_back_to_altar)
	actions.add_child(_back_btn)
	_notice = Style.body_label("", 12, Palette.EMBER_BRIGHT)
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.modulate.a = 0.0
	actions.add_child(_notice)
	foot.add_child(actions)
	return foot


func _rate_row(c: Color, label: String, value: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var dot := _FX.Dot.new(8.0, c)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	var lbl := Style.body_label(label, 12, Palette.TX_DIM)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var val := Style.pixel_label(value, 10, Palette.TX)
	val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(val)
	return row


# =========================================================================
# Logic
# =========================================================================

func _do_pull(count: int) -> void:
	if _rolling:
		return
	# Server-authoritative summons (BackendClient mocks the same schema until
	# the backend is deployed): all side effects — soulstone spend, pity,
	# roster — are applied by the client seam; this modal only renders.
	var res: Dictionary = await BackendClient.gacha_pull(count)
	if not bool(res["ok"]):
		# Don't fail silently — tell the delver why nothing happened. Guard the
		# shape: a live/out-of-contract body may not nest {error:{code}}.
		var edata: Dictionary = res.get("data", {})
		var ev: Variant = edata.get("error", {})
		var err := ""
		if ev is Dictionary:
			err = String((ev as Dictionary).get("code", ""))
		_flash_notice("Not enough stardrops" if err == "insufficient_funds" else "The well is napping")
		return
	var pulls: Array = res["data"].get("results", [])
	if pulls.is_empty():
		return
	_last_count = count  # remember for "Wish again ×N"
	_show_results(pulls)
	_rolling = true
	_update_buttons()
	var total := 0.36 + float(count) * 0.15 + 0.7  # + the jiggle/pop reveal
	var tw := create_tween()
	tw.tween_interval(total)
	tw.tween_callback(func() -> void:
		_rolling = false
		_update_buttons()
		_celebrate(pulls))


## The all-revealed celebration: for an epic+ best pull, spin a sunburst, rain
## confetti, bounce the best card, glow the stage border in the best rarity, and
## cheer "✦ {name} joins the party! ✦".
func _celebrate(pulls: Array) -> void:
	var best: Dictionary = {}
	var best_rank := -1
	var best_idx := 0
	for i in pulls.size():
		var rank := int(GameContent.RARITY_RANK.get(String((pulls[i] as Dictionary)["r"]), 0))
		if rank > best_rank:
			best_rank = rank
			best = pulls[i]
			best_idx = i
	if best.is_empty() or best_rank < 3:
		return  # a modest wish — no fireworks
	var rc := Palette.rarity_color(String(best["r"]))

	# Stage border glows in the best rarity.
	if _stage_panel != null:
		var gsb := StyleBoxFlat.new()
		gsb.bg_color = Color(0, 0, 0, 0)
		gsb.set_border_width_all(2)
		gsb.border_color = rc
		gsb.set_corner_radius_all(6)
		gsb.shadow_color = Palette.with_alpha(rc, 0.4 * Palette.GLOW)
		gsb.shadow_size = int(16 * Palette.GLOW)
		for m in ["content_margin_left", "content_margin_right", "content_margin_top", "content_margin_bottom"]:
			gsb.set(m, 18.0)
		_stage_panel.add_theme_stylebox_override("panel", gsb)

	# Sunburst + confetti overlay on the stage.
	_clear_celebration_fx()
	_celebrate_fx = _Celebrate.new()
	_celebrate_fx.tint = rc
	_celebrate_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_panel.add_child(_celebrate_fx)
	_celebrate_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Best-pull bounce.
	if _grid != null and best_idx < _grid.get_child_count():
		var card := _grid.get_child(best_idx) as Control
		if card != null:
			var btw := card.create_tween()
			btw.tween_property(card, "scale", Vector2(1.12, 1.12), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			btw.tween_property(card, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			btw.set_loops(3)

	# Cheer ribbon.
	_cheer = Style.display_label("✦ %s joins the party! ✦" % String(best.get("n", "?")), 22, rc, true)
	_cheer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cheer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_panel.add_child(_cheer)
	_cheer.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_cheer.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_cheer.offset_top = -34
	_cheer.offset_bottom = -8
	_cheer.scale = Vector2(0.6, 0.6)
	_cheer.pivot_offset = Vector2(0.0, 20.0)
	_cheer.modulate.a = 0.0
	var ctw := _cheer.create_tween()
	ctw.set_parallel(true)
	ctw.tween_property(_cheer, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	ctw.tween_property(_cheer, "modulate:a", 1.0, 0.25)


func _clear_celebration_fx() -> void:
	if _celebrate_fx != null and is_instance_valid(_celebrate_fx):
		_celebrate_fx.queue_free()
	_celebrate_fx = null
	if _cheer != null and is_instance_valid(_cheer):
		_cheer.queue_free()
	_cheer = null
	if _stage_panel != null:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.set_border_width_all(1)
		sb.border_color = Palette.IRON_EDGE
		sb.set_corner_radius_all(6)
		for m in ["content_margin_left", "content_margin_right", "content_margin_top", "content_margin_bottom"]:
			sb.set(m, 18.0)
		_stage_panel.add_theme_stylebox_override("panel", sb)


func _update_buttons() -> void:
	# Idle → the two summon buttons. After a pull → "Summon again ×N" + Back.
	_x1_btn.visible = not _has_results
	_x10_btn.visible = not _has_results
	_again_btn.visible = _has_results
	_back_btn.visible = _has_results
	_x1_btn.disabled = _rolling
	_x10_btn.disabled = _rolling
	_again_btn.disabled = _rolling
	_back_btn.disabled = _rolling
	_again_btn.text = "Wish again ×%d" % _last_count


## Back to the idle well (the state before the wish): drop the cards + the
## celebration, restore ×1/×10.
func _back_to_altar() -> void:
	if _rolling:
		return
	if _grid != null:
		_grid.queue_free()
		_grid = null
	_clear_celebration_fx()
	_has_results = false
	_idle_box.visible = true
	_update_buttons()


## Briefly surface a status line under the summon buttons, then fade it out.
func _flash_notice(text: String) -> void:
	if _notice == null:
		return
	_notice.text = text
	_notice.modulate.a = 1.0
	if _notice_tw != null and _notice_tw.is_valid():
		_notice_tw.kill()  # a fresh flash cancels the previous fade (no flicker)
	_notice_tw = create_tween()
	_notice_tw.tween_interval(1.4)
	_notice_tw.tween_property(_notice, "modulate:a", 0.0, 0.6)


func _refresh_pity(p: int) -> void:
	_pity_bar.pct = float(p) / float(Balance.inum("gacha.hard_pity", GameContent.PITY_HARD)) * 100.0
	_pity_num.text = str(p)
	_soft_lbl.visible = p >= Balance.inum("gacha.soft_pity", GameContent.PITY_SOFT)


# ===========================================================================
## Celebration overlay: a slowly spinning sunburst behind the cards + a one-shot
## confetti rain in candy colors. Purely decorative; frees itself after ~3s.
class _Celebrate:
	extends Control

	const _COLORS := [Color("ffc84a"), Color("ff8a4a"), Color("3dc98a"), Color("4da3ff"), Color("b46ef5"), Color("ff6b5e")]
	var tint := Color("ffab2e")
	var _t := 0.0
	var _bits: Array = []

	func _ready() -> void:
		clip_contents = true
		for i in 26:
			_bits.append({
				"x": randf(), "delay": randf() * 0.5,
				"dur": 1.6 + randf() * 1.6,
				"drift": (randf() * 2.0 - 1.0) * 90.0,
				"spin": deg_to_rad(300.0 + randf() * 420.0),
				"s": 7.0 + randf() * 7.0,
				"c": _COLORS[i % _COLORS.size()],
			})
		set_process(true)

	func _process(delta: float) -> void:
		_t += delta
		if _t > 3.2:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		# Sunburst: 12 spinning rays, fading out over the celebration.
		var fade := clampf(1.0 - _t / 3.0, 0.0, 1.0)
		for i in 12:
			var a := _t * 0.6 + TAU * float(i) / 12.0
			var col := Color(tint.r, tint.g, tint.b, 0.10 * fade)
			draw_colored_polygon(PackedVector2Array([
				c, c + Vector2.RIGHT.rotated(a) * 900.0, c + Vector2.RIGHT.rotated(a + 0.16) * 900.0,
			]), col)
		# Confetti rain: rotated candy rectangles falling with drift + spin.
		for b in _bits:
			var ph := (_t - float(b["delay"])) / float(b["dur"])
			if ph < 0.0 or ph > 1.0:
				continue
			var p := Vector2(float(b["x"]) * size.x + float(b["drift"]) * ph, -12.0 + (size.y + 24.0) * ph)
			var s := float(b["s"])
			draw_set_transform(p, float(b["spin"]) * ph, Vector2.ONE)
			draw_rect(Rect2(-s * 0.5, -s * 0.275, s, s * 0.55), (b["c"] as Color) * Color(1, 1, 1, 1.0 - ph * 0.4))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
