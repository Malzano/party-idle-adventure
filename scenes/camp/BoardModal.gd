extends "res://scenes/camp/ModalShell.gd"
## NOTICE BOARD modal (camp.jsx BoardModal): underline-glow tabs for Daily
## Quests (claimable via GameState), a mini Leaderboard (links to the full
## rankings window), and the rotating Daily Dungeon card.

const _TABS := [["quests", "Daily Quests"], ["leaders", "Leaderboard"], ["dungeon", "Daily Dungeon"]]

var _tab := "quests"
var _tab_btns: Dictionary = {}     # id -> Button
var _pages: Dictionary = {}        # id -> Control
var _claim_holders: Array = []     # quest index -> HBoxContainer


func _init() -> void:
	modal_title = "Notice Board"
	modal_width = 880.0
	body_separation = 18


func _build_body(body: VBoxContainer) -> void:
	body.add_child(_build_tabbar())
	_pages["quests"] = _build_quests()
	_pages["leaders"] = _build_leaders()
	_pages["dungeon"] = _build_dungeon()
	for id in _pages:
		body.add_child(_pages[id])
	_set_tab(_tab)


# =========================================================================
# Tab bar (.tabbar / .tab.on with the glowing underline)
# =========================================================================

func _build_tabbar() -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for pair: Array in _TABS:
		var id := String(pair[0])
		var b := Button.new()
		b.text = String(pair[1]).to_upper()
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var f := Fonts.display()
		if f != null:
			b.add_theme_font_override("font", f)
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(_set_tab.bind(id))
		_tab_btns[id] = b
		row.add_child(b)
	wrap.add_child(row)
	var hairline := ColorRect.new()
	hairline.color = Palette.IRON_EDGE
	hairline.custom_minimum_size = Vector2(0, 1)
	hairline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(hairline)
	return wrap


func _tab_box(on: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(120.0 / 255.0, 72.0 / 255.0, 28.0 / 255.0, 0.18) if on else Color(0, 0, 0, 0)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	if on:
		sb.corner_radius_top_left = 4
		sb.corner_radius_top_right = 4
		sb.border_width_bottom = 2
		sb.border_color = Palette.EMBER
	return sb


func _set_tab(id: String) -> void:
	_tab = id
	for key in _tab_btns:
		var b: Button = _tab_btns[key]
		var on := String(key) == _tab
		b.add_theme_stylebox_override("normal", _tab_box(on))
		b.add_theme_stylebox_override("hover", _tab_box(on))
		b.add_theme_stylebox_override("pressed", _tab_box(on))
		b.add_theme_color_override("font_color", Palette.EMBER_BRIGHT if on else Palette.TX_MUTE)
		b.add_theme_color_override("font_hover_color", Palette.EMBER_BRIGHT if on else Palette.TX_DIM)
		b.add_theme_color_override("font_pressed_color", Palette.EMBER_BRIGHT if on else Palette.TX_MUTE)
	for key in _pages:
		(_pages[key] as Control).visible = String(key) == _tab


# =========================================================================
# Daily Quests (.quest-list)
# =========================================================================

func _build_quests() -> Control:
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	for i in GameContent.QUESTS.size():
		list.add_child(_quest_row(i))
	return list


func _quest_row(i: int) -> Control:
	var q: Dictionary = GameContent.QUESTS[i]
	var p := float(q["p"])
	var g := float(q["g"])
	var done := p >= g or i == 1
	var pct := minf(100.0, p / g * 100.0)

	var row := PanelContainer.new()
	var sb := Style.row_box()
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	row.add_theme_stylebox_override("panel", sb)
	if done:
		row.modulate = Color(1, 1, 1, 0.85)

	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 14)
	row.add_child(grid)

	# Check square.
	var check := PanelContainer.new()
	var csb := StyleBoxFlat.new()
	csb.set_corner_radius_all(4)
	csb.set_border_width_all(1)
	if done:
		csb.bg_color = Color(95.0 / 255.0, 166.0 / 255.0, 78.0 / 255.0, 0.18)
		csb.border_color = Palette.R_UNCOMMON
		csb.shadow_color = Color(95.0 / 255.0, 166.0 / 255.0, 78.0 / 255.0, 0.4 * Palette.GLOW)
		csb.shadow_size = int(8 * Palette.GLOW)
	else:
		csb.bg_color = Color("0e0c09")
		csb.border_color = Palette.IRON_EDGE
	check.add_theme_stylebox_override("panel", csb)
	check.custom_minimum_size = Vector2(26, 26)
	check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tick := Style.body_label("✓" if done else "", 14, Palette.R_UNCOMMON)
	tick.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tick.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	check.add_child(tick)
	grid.add_child(check)

	# Title + progress bar.
	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 6)
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	main.add_child(Style.body_label(String(q["t"]), 14, Palette.TX))
	var bar_row := HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 8)
	var bar := StatBar.new("xp", pct, 6.0)
	bar.custom_minimum_size = Vector2(240, 6)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar_row.add_child(bar)
	var prog := Style.pixel_label("%s/%s" % [str(minf(p, g)), str(g)], 8, Palette.TX_MUTE)
	prog.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar_row.add_child(prog)
	main.add_child(bar_row)
	grid.add_child(main)

	# Reward (gold, italic, right).
	var reward := Style.display_label(String(q["rw"]), 11, Palette.GOLD, true)
	reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	reward.custom_minimum_size = Vector2(130, 0)
	reward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reward.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_child(reward)

	# Claim button (swapped in place after claiming).
	var holder := HBoxContainer.new()
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.add_child(_make_claim(i, done))
	_claim_holders.append(holder)
	grid.add_child(holder)
	return row


func _make_claim(i: int, done: bool) -> Button:
	var claimed: bool = GameState.quests_claimed.has(i)
	var b: Button
	if done and not claimed:
		b = Style.make_button("Claim", "ember")
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.pressed.connect(func() -> void:
			GameState.claim_quest(i)
			_replace_claim(i))
	elif claimed:
		b = Style.make_button("Claimed", "ghost")
		b.disabled = true
	else:
		b = Style.make_button("Claim", "ghost")
		b.disabled = true
	return b


func _replace_claim(i: int) -> void:
	var holder: HBoxContainer = _claim_holders[i]
	for child in holder.get_children():
		holder.remove_child(child)
		child.queue_free()
	holder.add_child(_make_claim(i, true))


# =========================================================================
# Leaderboard (.lb)
# =========================================================================

func _build_leaders() -> Control:
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	for r: Dictionary in GameContent.BOARD_RANKS:
		list.add_child(_leader_row(r))

	var btn_pad := MarginContainer.new()
	btn_pad.add_theme_constant_override("margin_top", 6)
	var btn := Style.make_button("View Full Rankings   L", "ember")
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(func() -> void:
		request_close()
		WindowManager.open(WindowManager.WIN_LEADERBOARD))
	btn_pad.add_child(btn)
	list.add_child(btn_pad)
	return list


func _leader_row(r: Dictionary) -> Control:
	var me := bool(r.get("me", false))
	var row := PanelContainer.new()
	var sb := Style.row_box(me)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	row.add_theme_stylebox_override("panel", sb)

	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 14)
	row.add_child(grid)

	var rank_n := int(r["r"])
	var rank_c := Palette.TX_MUTE
	if rank_n == 1:
		rank_c = Palette.R_LEGENDARY
	elif rank_n == 2:
		rank_c = Palette.SILVER_TEXT
	elif rank_n == 3:
		rank_c = Palette.BRONZE
	var rank := Style.display_label(str(rank_n), 20, rank_c)
	rank.custom_minimum_size = Vector2(30, 0)
	rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	grid.add_child(rank)

	var port := PixelSlot.new("40²", true)
	port.custom_minimum_size = Vector2(38, 38)
	port.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_child(port)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	name_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(Style.display_label(String(r["n"]), 16, Palette.TX, true))
	var lv := Style.body_label("LV %d" % int(r["lv"]), 10, Palette.TX_MUTE)
	lv.size_flags_vertical = Control.SIZE_SHRINK_END
	name_row.add_child(lv)
	grid.add_child(name_row)

	var power := VBoxContainer.new()
	power.add_theme_constant_override("separation", 1)
	power.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pv := Style.pixel_label(String(r["p"]), 13, Palette.EMBER_BRIGHT)
	pv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	power.add_child(pv)
	var pl := Style.body_label("POWER", 9, Palette.TX_FAINT)
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	power.add_child(pl)
	grid.add_child(power)
	return row


# =========================================================================
# Daily Dungeon (.daily-dgn)
# =========================================================================

func _build_dungeon() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)

	var art := Control.new()
	art.custom_minimum_size = Vector2(0, 220)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ps := PixelSlot.new("800×260\ndaily dungeon — rotating iso map", true)
	art.add_child(ps)
	ps.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_child(art)

	var meta := VBoxContainer.new()
	meta.add_theme_constant_override("separation", 12)
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 2)
	head.add_child(Style.display_label("The Sunken Reliquary", 24, Palette.GOLD_BRIGHT, true))
	head.add_child(Style.body_label("Today · Gold Rush — 3× gold drops", 12, Palette.EMBER))
	meta.add_child(head)

	var mods := HBoxContainer.new()
	mods.add_theme_constant_override("separation", 8)
	mods.add_child(Style.make_role_tag("tank", "+200% Gold"))
	mods.add_child(Style.make_role_tag("mage", "Frost-warded foes"))
	mods.add_child(Style.make_role_tag("dps", "3 attempts left"))
	meta.add_child(mods)

	var enter := Style.make_button("Enter Dungeon   ↵", "ember")
	enter.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	enter.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	meta.add_child(enter)
	page.add_child(meta)
	return page
