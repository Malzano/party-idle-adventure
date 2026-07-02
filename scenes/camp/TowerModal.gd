extends "res://scenes/camp/ModalShell.gd"
## THE SPIRE — Endless Tower: 100 floors × easy / hard / hell. Boss every 5th
## floor (grand boss every 25th), monster waves between. Each climb runs the
## deterministic floor sim (party DPS vs a scaling HP pool within a time limit);
## clearing advances the floor and pays gold / xp / materials, with gear + gems
## on boss floors. A CP band warns when the player is under-powered.

const _DIFFS := [["easy", "Easy"], ["hard", "Hard"], ["hell", "Hell"]]

var _rng := RandomNumberGenerator.new()
var _diff := "easy"
var _diff_btns: Dictionary = {}
var _stage: VBoxContainer
var _result: VBoxContainer


func _init() -> void:
	modal_title = "The Spire"
	modal_width = 920.0
	body_separation = 14
	_rng.randomize()


func _build_body(body: VBoxContainer) -> void:
	var drow := HBoxContainer.new()
	drow.add_theme_constant_override("separation", 8)
	drow.alignment = BoxContainer.ALIGNMENT_CENTER
	for pair: Array in _DIFFS:
		var id := String(pair[0])
		var b := Style.make_button(String(pair[1]), "stone", 14)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.pressed.connect(_set_diff.bind(id))
		_diff_btns[id] = b
		drow.add_child(b)
	body.add_child(drow)

	_stage = VBoxContainer.new()
	_stage.add_theme_constant_override("separation", 12)
	body.add_child(_stage)

	_result = VBoxContainer.new()
	_result.add_theme_constant_override("separation", 6)
	body.add_child(_result)

	EventBus.equipment_changed.connect(_refresh)
	EventBus.sim_stats_changed.connect(_refresh)
	_set_diff("easy")


func _exit_tree() -> void:
	if EventBus.equipment_changed.is_connected(_refresh):
		EventBus.equipment_changed.disconnect(_refresh)
	if EventBus.sim_stats_changed.is_connected(_refresh):
		EventBus.sim_stats_changed.disconnect(_refresh)


func _set_diff(d: String) -> void:
	_diff = d
	for id in _diff_btns:
		(_diff_btns[id] as Button).modulate = Palette.EMBER_BRIGHT if String(id) == _diff else Color(1, 1, 1)
	_refresh()


func _band_color(band: String) -> Color:
	match band:
		"Favored": return Palette.R_UNCOMMON
		"Even": return Palette.TX
		"Risky": return Palette.EMBER_BRIGHT
		_: return Palette.HP


func _refresh() -> void:
	for c in _stage.get_children():
		c.queue_free()
	var high := int(GameState.tower_floor.get(_diff, 0))
	var floor := mini(high + 1, Craft.TOWER_FLOORS)
	var maxed := high >= Craft.TOWER_FLOORS
	var profile := PlayerStats.compute()
	var cp := float(profile["total_power"])
	var dps := float(profile["party_dps"])

	# Progress header + bar.
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 10)
	hdr.add_child(Style.display_label("HIGHEST FLOOR", 13, Palette.GOLD))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hdr.add_child(sp)
	hdr.add_child(Style.pixel_label("%d / %d" % [high, Craft.TOWER_FLOORS], 13, Palette.EMBER_BRIGHT))
	_stage.add_child(hdr)
	var bar := StatBar.new("xp", float(high) / float(Craft.TOWER_FLOORS) * 100.0, 8.0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage.add_child(bar)

	if maxed:
		var done := Style.display_label("The Spire is conquered on %s. The dark applauds." % _diff.capitalize(), 15, Palette.GOLD_BRIGHT, true)
		done.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_stage.add_child(done)
		return

	# Next-encounter card.
	var kind := Craft.tower_kind(floor)
	var kind_label := "Grand Boss" if kind == "grand" else ("Mini-Boss" if kind == "boss" else "Monster Wave")
	var kind_color := Palette.R_LEGENDARY if kind == "grand" else (Palette.EMBER_BRIGHT if kind == "boss" else Palette.TX)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Style.inset_box(5))
	var cpad := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		cpad.add_theme_constant_override(m, 14)
	card.add_child(cpad)
	var ccol := VBoxContainer.new()
	ccol.add_theme_constant_override("separation", 8)
	cpad.add_child(ccol)
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 10)
	var ki := GearIcon.new("boss" if kind != "wave" else "sword", kind_color)
	ki.custom_minimum_size = Vector2(34, 34)
	title.add_child(ki)
	title.add_child(Style.display_label("Floor %d — %s" % [floor, kind_label], 18, kind_color, true))
	ccol.add_child(title)
	ccol.add_child(_kv("Waves", "%d  (last %s)" % [Craft.tower_waves(floor), "= boss" if kind != "wave" else "wave"]))
	ccol.add_child(_kv("Enemy HP / wave", Style.group_int(int(Craft.tower_hp(floor, _diff) * Craft.tower_boss_mult(floor)))))
	ccol.add_child(_kv("Time limit", "%ds" % int(Craft.tower_time_limit(floor))))
	var band := Craft.tower_gate_band(cp, floor, _diff)
	ccol.add_child(_kv("Your Power", "%s   vs gate %s" % [Style.group_int(int(cp)), Style.group_int(int(Craft.tower_cp_gate(floor, _diff)))]))
	var bl := Style.display_label("● %s" % band, 14, _band_color(band), true)
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ccol.add_child(bl)
	_stage.add_child(card)

	var climb := Style.make_button("Climb Floor %d   ↵" % floor, "ember")
	climb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	climb.pressed.connect(_climb)
	_stage.add_child(climb)


func _kv(k: String, v: String) -> Control:
	var row := HBoxContainer.new()
	var kl := Style.body_label(k, 13, Palette.TX_DIM)
	kl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(kl)
	row.add_child(Style.body_label(v, 13, Palette.TX))
	return row


func _on_modal_key(keycode: Key) -> bool:
	if keycode == KEY_ENTER or keycode == KEY_KP_ENTER:
		_climb()
		return true
	return false


func _climb() -> void:
	if int(GameState.tower_floor.get(_diff, 0)) >= Craft.TOWER_FLOORS:
		return
	var profile := PlayerStats.compute()
	var res := GameState.tower_climb(_diff, float(profile["party_dps"]), _rng)
	_show_result(res)
	_refresh()


func _show_result(res: Dictionary) -> void:
	for c in _result.get_children():
		c.queue_free()
	var cleared := bool(res.get("cleared", false))
	var floor := int(res.get("floor", 0))
	var head := Style.display_label(
		"✦ Floor %d cleared!" % floor if cleared else "✗ Floor %d — the Spire threw you back (%d/%d waves)" % [floor, int(res.get("waves_cleared", 0)), int(res.get("waves_total", 0))],
		15, Palette.GOLD_BRIGHT if cleared else Palette.HP, true)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result.add_child(head)
	var rw: Dictionary = res.get("rewards", {})
	if rw.is_empty():
		return
	var bits: Array[String] = []
	if int(rw.get("gold", 0)) > 0:
		bits.append("%s gold" % Style.group_int(int(rw["gold"])))
	if int(rw.get("xp", 0)) > 0:
		bits.append("%d xp" % int(rw["xp"]))
	for mid in rw.get("mats", {}):
		bits.append("%s ×%d" % [String(Craft.MATERIALS[mid]["n"]), int(rw["mats"][mid])])
	for it in rw.get("items", []):
		bits.append("%s [%s]" % [String((it as Dictionary).get("n", "gear")), String((it as Dictionary).get("r", ""))])
	for gm in rw.get("gems", []):
		bits.append("gem: %s" % String((gm as Dictionary).get("n", "")))
	if not bits.is_empty():
		var line := Style.body_label(" · ".join(bits), 12, Palette.TX)
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_result.add_child(line)
