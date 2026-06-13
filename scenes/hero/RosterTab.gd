extends Control
## PROFILE · ROSTER tab (design v2 roster.jsx): pick the fighting four.
## Top: the active party as four slot cards + a live Team Aura banner with
## diagnostics ("Missing a healer", "DPS must differ", …). Below: the hero
## collection — role filters, rarity-bordered cards, locked heroes recruit
## by being summoned at the altar. Click a slot, then a hero, to swap.

const ROLE_FILTERS := [["all", "All"], ["tank", "Tanks"], ["healer", "Healers"], ["dps", "DPS"], ["mage", "Mages"]]

var _sel := 0
var _filter := "all"
var _slots_row: HBoxContainer
var _aura_holder: Control
var _grid: GridContainer
var _count_lbl: Label
var _filter_btns: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	add_child(col)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Head strip: title + recruited count.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.add_child(Style.display_label("HERO ROSTER", 18, Palette.GOLD_BRIGHT))
	_count_lbl = Style.pixel_label("", 9, Palette.TX_MUTE)
	_count_lbl.size_flags_vertical = Control.SIZE_SHRINK_END
	Tip.attach(_count_lbl, {
		"name": "Recruitment",
		"type": "",
		"rarity": "",
		"flavor": "Locked heroes join the Watch when the Summoning Altar gives them back.",
	})
	head.add_child(_count_lbl)
	col.add_child(head)

	# Active party row: 4 slot cards + the aura banner.
	var party_row := HBoxContainer.new()
	party_row.add_theme_constant_override("separation", 12)
	_slots_row = HBoxContainer.new()
	_slots_row.add_theme_constant_override("separation", 12)
	_slots_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	party_row.add_child(_slots_row)
	_aura_holder = Control.new()
	_aura_holder.custom_minimum_size = Vector2(250, 0)
	party_row.add_child(_aura_holder)
	col.add_child(party_row)

	col.add_child(Style.rune_divider())

	# Controls: role filter segment + the how-to hint.
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 14)
	for pair in ROLE_FILTERS:
		var key := String(pair[0])
		var b := Style.make_button(String(pair[1]), "ghost", 10)
		b.pressed.connect(func() -> void:
			_filter = key
			_apply_filter_styles()
			_rebuild_grid())
		_filter_btns[key] = b
		controls.add_child(b)
	var hsp := Control.new()
	hsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hsp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	controls.add_child(hsp)
	var hint := Style.body_label("Select a slot above, then a hero below to swap them in", 12, Palette.TX_FAINT)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	controls.add_child(hint)
	col.add_child(controls)

	# Collection grid.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var gm := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		gm.add_theme_constant_override(m, 2)
	gm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid = GridContainer.new()
	_grid.columns = 6
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gm.add_child(_grid)
	scroll.add_child(gm)
	col.add_child(scroll)

	_apply_filter_styles()
	_rebuild_all()
	# Lineup swaps refresh the slots; summons can recruit locked heroes.
	EventBus.lineup_changed.connect(_rebuild_all, CONNECT_DEFERRED)
	EventBus.loadout_changed.connect(_rebuild_all, CONNECT_DEFERRED)


func _rebuild_all() -> void:
	_rebuild_slots()
	_rebuild_aura()
	_rebuild_grid()
	var recruited := 0
	for h in GameContent.HEROES:
		if GameContent.hero_recruited(String(h["id"])):
			recruited += 1
	_count_lbl.text = "%d / %d RECRUITED" % [recruited, GameContent.HEROES.size()]


# =========================================================================
# Active party slots
# =========================================================================

func _rebuild_slots() -> void:
	for child in _slots_row.get_children():
		_slots_row.remove_child(child)
		child.queue_free()
	for i in GameState.party_ids.size():
		_slots_row.add_child(_party_slot(i))


func _party_slot(i: int) -> Control:
	var hero := GameContent.hero_by_id(GameState.party_ids[i])
	var rar := String(hero.get("r", "common"))
	var rc := Palette.rarity_color(rar)
	var selected := i == _sel

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("171310")
	sb.set_border_width_all(1)
	sb.border_width_bottom = 3
	sb.border_color = Palette.EMBER_DEEP if selected else Palette.IRON_EDGE
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	if selected:
		sb.shadow_color = Palette.with_alpha(Palette.EMBER, 0.35 * Palette.GLOW)
		sb.shadow_size = int(18 * Palette.GLOW)
	else:
		# Role-colored footer line (.party-slot.role-border-*).
		sb.border_color = Palette.IRON_EDGE
	card.add_theme_stylebox_override("panel", sb)

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)

	var portrait := Control.new()
	portrait.custom_minimum_size = Vector2(64, 64)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ps := PixelSlot.new("96²\n%s" % String(hero.get("name", "?")), true)
	portrait.add_child(ps)
	ps.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pb := Panel.new()
	var pb_sb := StyleBoxFlat.new()
	pb_sb.draw_center = false
	pb_sb.set_border_width_all(1)
	pb_sb.border_color = rc
	pb_sb.set_corner_radius_all(4)
	pb.add_theme_stylebox_override("panel", pb_sb)
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.add_child(pb)
	pb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_child(portrait)

	var meta := VBoxContainer.new()
	meta.add_theme_constant_override("separation", 2)
	meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_child(Style.display_label(String(hero.get("name", "?")), 13, rc, true))
	meta.add_child(Style.body_label(String(hero.get("cls", "")), 7, Palette.TX_MUTE))
	var tags := HBoxContainer.new()
	tags.add_theme_constant_override("separation", 8)
	var tag := Style.make_role_tag(String(hero.get("role", "dps")), String(hero.get("role_lbl", "DPS")))
	tags.add_child(tag)
	tags.add_child(Style.pixel_label("LV %d" % int(hero.get("lvl", 1)), 6, Palette.GOLD_BRIGHT))
	meta.add_child(tags)
	box.add_child(meta)

	var slot_num := Style.pixel_label(str(i + 1), 6, Palette.EMBER_BRIGHT if selected else Palette.TX_FAINT)
	slot_num.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	slot_num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(slot_num)

	Tip.attach(card, {
		"name": String(hero.get("name", "?")),
		"type": "%s · %s · %s" % [hero.get("cls", ""), hero.get("role_lbl", ""), rar],
		"rarity": rar,
		"stats": [["Level", str(int(hero.get("lvl", 1)))], ["Base DPS", _power_label(String(hero.get("id", "")))]],
		"flavor": "Selected slot — pick a hero below to swap in." if selected else "Click to select this slot.",
	})
	card.gui_input.connect(func(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_sel = i
			_rebuild_slots()
			_rebuild_grid())  # grid tooltips quote the selected slot number
	return card


# =========================================================================
# Team Aura banner (live diagnostics)
# =========================================================================

func _rebuild_aura() -> void:
	for child in _aura_holder.get_children():
		_aura_holder.remove_child(child)
		child.queue_free()
	var aura := GameContent.aura_check(GameState.party_ids)
	var ok := bool(aura["ok"])

	var banner := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("161210")
	sb.set_border_width_all(1)
	sb.border_color = Palette.GOLD_DIM if ok else Palette.IRON_EDGE
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	if ok:
		sb.shadow_color = Palette.with_alpha(Palette.EMBER, 0.3 * Palette.GLOW)
		sb.shadow_size = int(20 * Palette.GLOW)
	banner.add_theme_stylebox_override("panel", sb)
	_aura_holder.add_child(banner)
	banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 11)
	banner.add_child(row)
	var glyph := Style.body_label("◆", 19, Palette.EMBER_BRIGHT if ok else Palette.TX_MUTE)
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(glyph)
	var meta := VBoxContainer.new()
	meta.add_theme_constant_override("separation", 1)
	meta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	meta.add_child(Style.display_label("TEAM AURA", 8, Palette.GOLD_BRIGHT if ok else Palette.TX_DIM))
	meta.add_child(Style.body_label(String(aura["msg"]), 8, Palette.CYAN_BRIGHT if ok else Palette.TX_MUTE))
	row.add_child(meta)

	Tip.attach(banner, {
		"name": "Team Aura: Optimal" if ok else "Team Aura: Unbalanced",
		"type": "Composition bonus",
		"rarity": "legendary" if ok else "common",
		"stats": [["Required", "1 Tank · 1 Healer · 2 different DPS"]],
		"flavor": "A balanced delve burns brightest." if ok else String(aura["msg"]),
	})


# =========================================================================
# Collection grid
# =========================================================================

func _apply_filter_styles() -> void:
	for key in _filter_btns:
		var b: Button = _filter_btns[key]
		var on := String(key) == _filter
		b.add_theme_color_override("font_color", Palette.EMBER_BRIGHT if on else Palette.TX_DIM)
		b.add_theme_color_override("font_hover_color", Palette.EMBER_BRIGHT if on else Palette.TX)


func _rebuild_grid() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	for h_v in GameContent.HEROES:
		var h: Dictionary = h_v
		if _filter != "all" and String(h["role"]) != _filter:
			continue
		_grid.add_child(_hero_card(h))


func _hero_card(h: Dictionary) -> Control:
	var id := String(h["id"])
	var rar := String(h["r"])
	var rc := Palette.rarity_color(rar)
	var recruited := GameContent.hero_recruited(id)
	var in_party := GameState.party_ids.has(id)

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if recruited else Control.CURSOR_FORBIDDEN
	var sb := Style.slot_box(rar, recruited)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 12
	sb.content_margin_bottom = 10
	if in_party:
		sb.border_color = Palette.EMBER_DEEP
	card.add_theme_stylebox_override("panel", sb)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not recruited:
		inner.modulate = Color(1, 1, 1, 0.55)
	card.add_child(inner)

	var portrait := Control.new()
	portrait.custom_minimum_size = Vector2(84, 84)
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ps := PixelSlot.new("???" if not recruited else "96²\n%s" % String(h["name"]), recruited)
	portrait.add_child(ps)
	ps.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.add_child(portrait)

	var nm := Style.display_label(String(h["name"]), 12, rc if recruited else Palette.TX_FAINT, true)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(nm)
	var cls := Style.body_label(String(h["cls"]), 7, Palette.TX_MUTE)
	cls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(cls)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_child(Style.make_role_tag(String(h["role"]), String(h["role_lbl"])))
	foot.add_child(Style.pixel_label("LOCKED" if not recruited else _power_label(id), 6,
		Palette.TX_FAINT if not recruited else Palette.EMBER_BRIGHT))
	inner.add_child(foot)

	# Corner badges. PanelContainer stretches every Control child to its
	# content rect, so absolute-positioned chips need a transparent overlay
	# (a plain Control stretches harmlessly; ITS children place freely).
	if in_party or not recruited:
		var overlay := Control.new()
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(overlay)
		if in_party:
			var badge := Style.pixel_label("IN PARTY", 4, Color("1c0f04"))
			var bsb := StyleBoxFlat.new()
			bsb.bg_color = Palette.EMBER_BRIGHT
			bsb.set_corner_radius_all(2)
			bsb.content_margin_left = 5
			bsb.content_margin_right = 5
			bsb.content_margin_top = 3
			bsb.content_margin_bottom = 2
			var holder := PanelContainer.new()
			holder.add_theme_stylebox_override("panel", bsb)
			holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.add_child(badge)
			overlay.add_child(holder)
			holder.position = Vector2(6, 6)
		if not recruited:
			var lock := Style.body_label("🔒", 9, Palette.TX_DIM)
			lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
			overlay.add_child(lock)
			lock.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
			lock.offset_left = -28
			lock.offset_top = 6
			lock.offset_right = -8
			lock.offset_bottom = 28

	var flavor := String(h["trait"])
	if not recruited:
		flavor = "Summon at the altar to recruit. " + flavor
	elif in_party:
		flavor = "In party — click to move into slot %d. %s" % [_sel + 1, flavor]
	else:
		flavor = "Click to place in slot %d. %s" % [_sel + 1, flavor]
	Tip.attach(card, {
		"name": String(h["name"]),
		"type": "%s · %s · %s" % [h["cls"], h["role_lbl"], rar],
		"rarity": rar,
		"stats": [["Level", str(int(h["lvl"]))], ["Base DPS", _power_label(id)],
			["HP", "%d%%" % int(h["hp"])], ["Mana", "%d%%" % int(h["mana"])]],
		"flavor": flavor,
	})
	card.gui_input.connect(func(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and recruited:
			GameState.set_party_slot(_sel, id))
	return card


func _power_label(id: String) -> String:
	var bases: Dictionary = Balance.value("heroes.base_dps", {})
	return PlayerStats.format_dps(float(bases.get(id, 0.0)))
