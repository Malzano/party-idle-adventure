extends "res://scenes/camp/ModalShell.gd"
## SUMMONING ALTAR modal (camp.jsx GachaModal): banner header, results stage
## with staggered card flips, rates + pity footer, ×1 / ×10 summon actions.
## Pulls roll through GameContent.gacha_roll_rarity with a running pity
## counter (legendary resets to 0), spend soulstones via GameState, and add
## every hero to the roster. Q / E pull while the modal is open.

var _rng := RandomNumberGenerator.new()
var _rolling := false
var _has_results := false

var _idle_box: VBoxContainer
var _stage_center: CenterContainer
var _grid: GridContainer = null
var _again_btn: Button
var _x1_btn: Button
var _x10_btn: Button
var _pity_bar: StatBar
var _pity_num: Label
var _soft_lbl: Label


func _init() -> void:
	modal_title = "Summoning Altar"
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
	var ps := PixelSlot.new("560×300\nbanner splash — featured hero", true)
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
	meta.add_child(Style.pixel_label("Limited Banner", 9, Palette.EMBER_BRIGHT))
	meta.add_child(Style.display_label("Ashen Covenant", 30, Palette.GOLD_BRIGHT, true))
	var sub := HBoxContainer.new()
	sub.add_theme_constant_override("separation", 0)
	sub.add_child(Style.body_label("Rate-up: ", 13, Palette.TX_DIM))
	sub.add_child(Style.body_label("Ashling, the Cinderborn", 13, Palette.R_LEGENDARY))
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
	var aps := PixelSlot.new("300×260\naltar idle", true)
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
	var hint := Style.display_label("Offer soulstones to summon gear for your delver.", 13, Palette.TX_MUTE, true)
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
	var sprite := PixelSlot.new("96²\n%s" % String(hero["n"]), true)
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

	# FLIP: squash to 0, swap faces, expand back out.
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_property(card, "scale:x", 0.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		back.visible = false
		front.visible = true)
	tw.tween_property(card, "scale:x", 1.0, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return card


func _show_results(pulls: Array) -> void:
	if _grid != null:
		_grid.queue_free()
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


func _clear_results() -> void:
	if _rolling:
		return
	if _grid != null:
		_grid.queue_free()
		_grid = null
	_has_results = false
	_idle_box.visible = true
	_update_buttons()


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
	_again_btn = Style.make_button("Summon again", "ghost")
	_again_btn.visible = false
	_again_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_again_btn.pressed.connect(_clear_results)
	actions.add_child(_again_btn)
	_x1_btn = Style.make_button("×1 Summon   Q", "stone", 14)
	_x1_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_x1_btn.pressed.connect(func() -> void: _do_pull(1))
	Tip.attach(_x1_btn, {
		"name": "Single Summon",
		"type": "Cost: %s Soulstone" % Style.group_int(Balance.inum("gacha.cost_x1", GameContent.GACHA_COST_X1)),
		"rarity": "rare"})
	actions.add_child(_x1_btn)
	_x10_btn = Style.make_button("×10 Multi-Summon   E", "ember", 14)
	_x10_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_x10_btn.pressed.connect(func() -> void: _do_pull(10))
	Tip.attach(_x10_btn, {
		"name": "Ten Summon",
		"type": "Cost: %s Soulstone" % Style.group_int(Balance.inum("gacha.cost_x10", GameContent.GACHA_COST_X10)),
		"rarity": "legendary",
		"flavor": "Guarantees at least one 4★ or higher."})
	actions.add_child(_x10_btn)
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
		return  # insufficient funds (or network error) — buttons stay enabled
	var pulls: Array = res["data"].get("results", [])
	if pulls.is_empty():
		return
	_show_results(pulls)
	_rolling = true
	_update_buttons()
	var total := 0.36 + float(count) * 0.15 + 0.4
	var tw := create_tween()
	tw.tween_interval(total)
	tw.tween_callback(func() -> void:
		_rolling = false
		_update_buttons())


func _update_buttons() -> void:
	_x1_btn.disabled = _rolling
	_x10_btn.disabled = _rolling
	_again_btn.visible = _has_results
	_again_btn.disabled = _rolling


func _refresh_pity(p: int) -> void:
	_pity_bar.pct = float(p) / float(Balance.inum("gacha.hard_pity", GameContent.PITY_HARD)) * 100.0
	_pity_num.text = str(p)
	_soft_lbl.visible = p >= Balance.inum("gacha.soft_pity", GameContent.PITY_SOFT)
