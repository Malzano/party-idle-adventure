extends Control
## PROFILE · ROSTER tab: every hero summoned from the gacha. The fixed party
## of four does the fighting; roster heroes lend flat support DPS by rarity
## (Balance roster.support_dps). Dismissing one returns a pinch of ember dust.

const _DISMISS_DUST := {"common": 1, "uncommon": 1, "rare": 2, "epic": 4, "legendary": 8}

var _list: VBoxContainer
var _count_lbl: Label
var _support_lbl: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_child(_build_summary())
	row.add_child(_build_list_panel())
	EventBus.loadout_changed.connect(_rebuild, CONNECT_DEFERRED)
	_rebuild()


# =========================================================================
# Left: summary card
# =========================================================================

func _build_summary() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(340, 0)
	panel.add_theme_stylebox_override("panel", Style.panel_box())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	panel.add_child(col)
	col.add_child(_panel_head("The Watch"))

	var pad := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(m, 18)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	pad.add_child(body)
	col.add_child(pad)

	var blurb := Style.body_label(
		"Summoned heroes don't march — they hold the camp. Every delver in " +
		"the Watch lends support DPS to the party, scaled by rarity.",
		13, Palette.TX_DIM)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(blurb)
	body.add_child(Style.rune_divider())

	_count_lbl = Style.pixel_label("", 16, Palette.GOLD_BRIGHT)
	body.add_child(_count_lbl)
	body.add_child(Style.body_label("HEROES SWORN", 10, Palette.TX_MUTE))

	_support_lbl = Style.pixel_label("", 16, Palette.EMBER_BRIGHT)
	body.add_child(_support_lbl)
	body.add_child(Style.body_label("SUPPORT DPS", 10, Palette.TX_MUTE))

	var hint := Style.body_label(
		"New heroes answer at the Summoning Altar (Camp · Q).", 11, Palette.TX_FAINT)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(hint)
	return panel


# =========================================================================
# Right: roster rows
# =========================================================================

func _build_list_panel() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", Style.panel_box())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	panel.add_child(col)
	col.add_child(_panel_head("Summoned Heroes"))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var pad := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(m, 14)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(_list)
	scroll.add_child(pad)
	col.add_child(scroll)
	return panel


func _rebuild() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()

	var roster: Array = GameState.roster_extra
	_count_lbl.text = str(roster.size())
	var support: Dictionary = Balance.value("roster.support_dps", {})
	var total := 0.0
	for hero in roster:
		total += float(support.get(String((hero as Dictionary).get("r", "common")), 0.0))
	_support_lbl.text = "+" + PlayerStats.format_dps(total)

	if roster.is_empty():
		var empty := Style.body_label(
			"The Watch stands empty. Summon heroes at the altar and they muster here.",
			13, Palette.TX_MUTE)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(empty)
		return
	for i in roster.size():
		_list.add_child(_hero_row(i, roster[i]))


func _hero_row(idx: int, hero: Dictionary) -> Control:
	var rar := String(hero.get("r", "common"))
	var rc := Palette.rarity_color(rar)
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", Style.row_box())
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	row.add_child(box)

	var portrait := Control.new()
	portrait.custom_minimum_size = Vector2(44, 44)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ps := PixelSlot.new("40²", true)
	portrait.add_child(ps)
	ps.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var border := Panel.new()
	var b_sb := StyleBoxFlat.new()
	b_sb.draw_center = false
	b_sb.set_border_width_all(1)
	b_sb.border_color = rc
	b_sb.set_corner_radius_all(4)
	border.add_theme_stylebox_override("panel", b_sb)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.add_child(border)
	border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_child(portrait)

	var meta := VBoxContainer.new()
	meta.add_theme_constant_override("separation", 2)
	meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var nrow := HBoxContainer.new()
	nrow.add_theme_constant_override("separation", 8)
	nrow.add_child(Style.display_label(String(hero.get("n", "?")), 15, rc, true))
	nrow.add_child(Style.pixel_label(rar.to_upper(), 8, rc))
	meta.add_child(nrow)
	meta.add_child(Style.body_label(String(hero.get("role", "")), 11, Palette.TX_MUTE))
	box.add_child(meta)

	var support: Dictionary = Balance.value("roster.support_dps", {})
	var dps := Style.body_label(
		"+%s DPS" % PlayerStats.format_dps(float(support.get(rar, 0.0))), 12, Palette.TX_DIM)
	dps.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(dps)

	var dust := int(_DISMISS_DUST.get(rar, 1))
	var dismiss := Style.make_button("DISMISS", "ghost", 10)
	dismiss.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Tip.attach(dismiss, {
		"name": "Dismiss",
		"type": "",
		"rarity": "",
		"flavor": "Release %s from the Watch for +%d ember dust." % [String(hero.get("n", "?")), dust],
	})
	dismiss.pressed.connect(func() -> void: _dismiss(idx))
	box.add_child(dismiss)
	return row


func _dismiss(idx: int) -> void:
	if idx < 0 or idx >= GameState.roster_extra.size():
		return
	var hero: Dictionary = GameState.roster_extra[idx]
	GameState.roster_extra.remove_at(idx)
	GameState.ember_dust += int(_DISMISS_DUST.get(String(hero.get("r", "common")), 1))
	EventBus.currencies_changed.emit()
	EventBus.loadout_changed.emit()  # reprices the party + rebuilds this list


func _panel_head(title: String) -> Control:
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", Style.head_box())
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.add_child(Style.display_label(title.to_upper(), 14, Palette.GOLD))
	head.add_child(h)
	return head
