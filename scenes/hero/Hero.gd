extends Control
## HERO / PROFILE screen (profile.jsx) — own OS window.
##
## Header: portrait + "Vael, the Forsaken" + Total Power block + tab strip
## (Equipment Q / Pets W / Relics E / Talents R). The four tab pages are
## built once and kept alive (hidden/shown) so per-tab state — inventory tab,
## detailed-stats toggle, pet selection, talent pan/zoom — survives switching.

const _EquipmentTabScript := preload("res://scenes/hero/EquipmentTab.gd")
const _PetsTabScript := preload("res://scenes/hero/PetsTab.gd")
const _RelicsTabScript := preload("res://scenes/hero/RelicsTab.gd")
const _TalentsTabScript := preload("res://scenes/hero/TalentsTab.gd")
const _RosterTabScript := preload("res://scenes/hero/RosterTab.gd")

const _TAB_DEFS := [["Equipment", "Q"], ["Pets", "W"], ["Relics", "E"], ["Talents", "R"], ["Roster", "T"]]

var _tab_buttons: Array[Button] = []
var _pages: Array[Control] = []
var _current: int = -1
var _power_num: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS

	# .profile padding: 78px top / 22px sides / 18px bottom.
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 22)
	pad.add_theme_constant_override("margin_right", 22)
	pad.add_theme_constant_override("margin_top", 78)
	pad.add_theme_constant_override("margin_bottom", 18)
	add_child(pad)
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	pad.add_child(column)

	column.add_child(_build_header())

	# .prof-body — the tab container.
	var body := Control.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_child(body)

	var scripts: Array = [_EquipmentTabScript, _PetsTabScript, _RelicsTabScript, _TalentsTabScript, _RosterTabScript]
	for s in scripts:
		var page := (s as GDScript).new() as Control
		page.visible = false
		body.add_child(page)
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_pages.append(page)

	_select_tab(0)
	EventBus.sim_stats_changed.connect(_refresh_power)


func _refresh_power() -> void:
	_power_num.text = Style.group_int(int(PlayerStats.compute()["total_power"]))


# .prof-header: portrait · name/sub · Total Power · spacer · tabs.
func _build_header() -> Control:
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_left", 4)
	wrap.add_theme_constant_override("margin_right", 4)
	wrap.add_theme_constant_override("margin_top", 0)
	wrap.add_theme_constant_override("margin_bottom", 14)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	wrap.add_child(row)

	# .ph-portrait — 60px lit pixel slot with a gold-dim border.
	var portrait := Control.new()
	portrait.custom_minimum_size = Vector2(60, 60)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ps := PixelSlot.new("72²\n%s" % GameState.player_name, true)
	portrait.add_child(ps)
	ps.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pborder := Panel.new()
	var pb_sb := StyleBoxFlat.new()
	pb_sb.draw_center = false
	pb_sb.set_border_width_all(1)
	pb_sb.border_color = Palette.GOLD_DIM
	pb_sb.set_corner_radius_all(4)
	pborder.add_theme_stylebox_override("panel", pb_sb)
	pborder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.add_child(pborder)
	pborder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_child(portrait)

	# .ph-meta — name + sub line.
	var meta := VBoxContainer.new()
	meta.add_theme_constant_override("separation", 4)
	meta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	meta.add_child(Style.display_label("%s, %s" % [GameState.player_name, GameState.player_title], 28, Palette.GOLD_BRIGHT, true))
	meta.add_child(Style.body_label("%s · Level %d · Prestige %s" % [GameState.player_class, GameState.player_level, GameState.prestige], 13, Palette.TX_MUTE))
	row.add_child(meta)

	# .ph-power margin-left 16 on top of the 16px gap.
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(gap)

	# .ph-power — hairline left+right borders, padded 22.
	var power := PanelContainer.new()
	var pw_sb := StyleBoxFlat.new()
	pw_sb.bg_color = Color(0, 0, 0, 0)
	pw_sb.border_width_left = 1
	pw_sb.border_width_right = 1
	pw_sb.border_color = Palette.IRON_EDGE
	pw_sb.content_margin_left = 22
	pw_sb.content_margin_right = 22
	pw_sb.content_margin_top = 2
	pw_sb.content_margin_bottom = 2
	power.add_theme_stylebox_override("panel", pw_sb)
	power.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pcol := VBoxContainer.new()
	pcol.add_theme_constant_override("separation", 3)
	_power_num = Style.pixel_label(Style.group_int(int(PlayerStats.compute()["total_power"])), 20, Palette.EMBER_BRIGHT)
	_power_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pcol.add_child(_power_num)
	var plbl := Style.body_label("TOTAL POWER", 10, Palette.TX_MUTE)
	plbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pcol.add_child(plbl)
	power.add_child(pcol)
	row.add_child(power)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	# .prof-tabs — Equipment Q / Pets W / Relics E / Talents R.
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	tabs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for i in _TAB_DEFS.size():
		var b := Style.make_tab(String(_TAB_DEFS[i][0]), String(_TAB_DEFS[i][1]))
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.pressed.connect(_select_tab.bind(i))
		tabs.add_child(b)
		_tab_buttons.append(b)
	row.add_child(tabs)
	return wrap


func _select_tab(index: int) -> void:
	if index == _current:
		return
	_current = index
	for i in _pages.size():
		_pages[i].visible = i == index
		Style.set_tab_active(_tab_buttons[i], i == index)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	var idx := -1
	match k.keycode:
		KEY_Q:
			idx = 0
		KEY_W:
			idx = 1
		KEY_E:
			idx = 2
		KEY_R:
			idx = 3
		KEY_T:
			idx = 4
	if idx >= 0:
		_select_tab(idx)
		get_viewport().set_input_as_handled()
