extends "res://scenes/camp/ModalShell.gd"
## NOTICE BOARD modal (camp.jsx BoardModal): underline-glow tabs for Daily
## Quests (live progress from GameState's daily counters; Claim grants the
## parsed reward), a mini Leaderboard (links to the full rankings window),
## and the Daily Dungeon card (live attempts, energy cost, timed Gold Rush).

const _TABS := [["quests", "Daily Quests"], ["leaders", "Leaderboard"], ["dungeon", "Daily Dungeon"], ["mail", "Mail"]]

var _tab := "quests"
var _tab_btns: Dictionary = {}     # id -> Button
var _pages: Dictionary = {}        # id -> Control

var _quests_list: VBoxContainer
var _attempts_lbl: Label
var _enter_btn: Button
var _rush_panel: PanelContainer
var _rush_lbl: Label
var _mail_list: VBoxContainer


func _init() -> void:
	modal_title = "Notice Board"
	modal_width = 880.0
	body_separation = 18


func _build_body(body: VBoxContainer) -> void:
	body.add_child(_build_tabbar())
	_pages["quests"] = _build_quests()
	_pages["leaders"] = _build_leaders()
	_pages["dungeon"] = _build_dungeon()
	_pages["mail"] = _build_mail()
	for id in _pages:
		body.add_child(_pages[id])
	_set_tab(_tab)
	# Deferred so a Claim press never frees its own button mid-signal.
	EventBus.quests_changed.connect(_on_quests_changed, CONNECT_DEFERRED)
	EventBus.currencies_changed.connect(_refresh_dungeon)


func _exit_tree() -> void:
	if EventBus.quests_changed.is_connected(_on_quests_changed):
		EventBus.quests_changed.disconnect(_on_quests_changed)
	if EventBus.currencies_changed.is_connected(_refresh_dungeon):
		EventBus.currencies_changed.disconnect(_refresh_dungeon)


func _on_quests_changed() -> void:
	_rebuild_quests()
	_refresh_dungeon()


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
		b.add_theme_font_size_override("font_size", Style.fs(13))
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


# =========================================================================
# Mail (season rewards — GET /v1/mail, POST /v1/mail/claim)
# =========================================================================

func _build_mail() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_mail_list = VBoxContainer.new()
	_mail_list.add_theme_constant_override("separation", 8)
	col.add_child(_mail_list)
	_rebuild_mail()
	return col


func _rebuild_mail() -> void:
	var res: Dictionary = await BackendClient.mail_list()
	if not is_instance_valid(self) or _mail_list == null:
		return
	for child in _mail_list.get_children():
		_mail_list.remove_child(child)
		child.queue_free()
	if not bool(res["ok"]):
		_mail_list.add_child(Style.body_label("The courier is lost in the fog.", 12, Palette.TX_MUTE))
		return
	var mail: Array = res["data"].get("mail", [])
	if mail.is_empty():
		_mail_list.add_child(Style.body_label("No letters yet. The mailbox is snoozing.", 12, Palette.TX_MUTE))
		return
	for m_v in mail:
		_mail_list.add_child(_mail_row(m_v))


func _mail_row(m: Dictionary) -> Control:
	var read := bool(m["read"])
	var row := PanelContainer.new()
	var sb := Style.row_box()
	if read:
		sb.bg_color = Color(0, 0, 0, 0.10)
	row.add_theme_stylebox_override("panel", sb)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	row.add_child(box)

	var meta := VBoxContainer.new()
	meta.add_theme_constant_override("separation", 2)
	meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var granted: Dictionary = m["granted"]
	var title := String(granted.get("label", "Letter"))
	meta.add_child(Style.display_label(title, 15, Palette.TX_FAINT if read else Palette.GOLD_BRIGHT))
	var bits: Array[String] = []
	if int(m.get("season", 0)) > 0:
		bits.append("Season %d" % int(m["season"]))
	if String(m.get("tier", "")) != "":
		bits.append(String(m["tier"]))
	var rewards: Array[String] = []
	if int(granted.get("gold", 0)) > 0:
		rewards.append("%s coins" % Style.group_int(int(granted["gold"])))
	for it in granted.get("items", []):
		rewards.append(String(it))
	if not rewards.is_empty():
		bits.append(" · ".join(rewards))
	meta.add_child(Style.body_label(" — ".join(bits) if not bits.is_empty() else "A notice.", 11, Palette.TX_MUTE))
	box.add_child(meta)

	if read:
		var claimed := Style.pixel_label("CLAIMED", 9, Palette.TX_FAINT)
		claimed.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(claimed)
	else:
		var claim := Style.make_button("CLAIM", "ember", 11)
		claim.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		claim.custom_minimum_size = Vector2(92, 38)
		var mail_id := String(m["id"])
		claim.pressed.connect(func() -> void:
			var res: Dictionary = await BackendClient.mail_claim(mail_id)
			if bool(res["ok"]):
				_rebuild_mail()
			)
		box.add_child(claim)
	return row


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
# Daily Quests (.quest-list) — live progress + claimable rewards
# =========================================================================

func _build_quests() -> Control:
	_quests_list = VBoxContainer.new()
	_quests_list.add_theme_constant_override("separation", 8)
	_rebuild_quests()
	return _quests_list


func _rebuild_quests() -> void:
	for child in _quests_list.get_children():
		_quests_list.remove_child(child)
		child.queue_free()
	for i in GameContent.QUESTS.size():
		_quests_list.add_child(_quest_row(i))


func _quest_row(i: int) -> Control:
	var q: Dictionary = GameContent.QUESTS[i]
	var g := float(q["g"])
	var p := GameState.quest_progress(i)
	var done := p >= g
	var claimed: bool = GameState.quests_claimed.has(i)
	var pct := minf(100.0, p / g * 100.0)

	var row := PanelContainer.new()
	var sb := Style.row_box()
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	row.add_theme_stylebox_override("panel", sb)
	if claimed:
		row.modulate = Color(1, 1, 1, 0.55)
	elif done:
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
	var shown := minf(p, g)
	var prog_text := "%.1f/%d" % [shown, int(g)] if i == 3 else "%d/%d" % [int(shown), int(g)]
	var prog := Style.pixel_label(prog_text, 8, Palette.TX_MUTE)
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

	# Claim button (live state; rows rebuild on quests_changed).
	var b: Button
	if done and not claimed:
		b = Style.make_button("Claim", "ember")
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.pressed.connect(_claim.bind(i))
	else:
		b = Style.make_button("Claimed" if claimed else "Claim", "ghost")
		b.disabled = true
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_child(b)
	return row


func _claim(i: int) -> void:
	if GameState.quests_claimed.has(i):
		return
	# Server-validated claim via the backend seam (mocked schema until the
	# API is deployed). Reward parsing/granting lives in BackendClient so the
	# mock matches the server's grants exactly; rows refresh on quests_changed.
	await BackendClient.quest_claim(i)


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
# Daily Dungeon (.daily-dgn) — live attempts + timed Gold Rush buff
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

	var mult := int(Balance.num("energy.dungeon_gold_mult", 3.0))

	var meta := VBoxContainer.new()
	meta.add_theme_constant_override("separation", 12)
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 2)
	head.add_child(Style.display_label("The Sunken Reliquary", 24, Palette.GOLD_BRIGHT, true))
	head.add_child(Style.body_label("Today · Coin Rush — %d× coin drops" % mult, 12, Palette.EMBER_DEEP))
	meta.add_child(head)

	var mods := HBoxContainer.new()
	mods.add_theme_constant_override("separation", 8)
	mods.add_child(Style.make_role_tag("tank", "+%d%% Coins" % ((mult - 1) * 100)))
	mods.add_child(Style.make_role_tag("mage", "Frost-warded foes"))
	var att_chip := Style.make_role_tag("dps", "%d attempts left" % GameState.dungeon_attempts)
	_attempts_lbl = att_chip.get_child(0) as Label
	mods.add_child(att_chip)
	meta.add_child(mods)

	# Gold Rush active status (ember, ticking countdown).
	_rush_panel = PanelContainer.new()
	var rsb := StyleBoxFlat.new()
	rsb.bg_color = Palette.with_alpha(Palette.EMBER, 0.1)
	rsb.set_border_width_all(1)
	rsb.border_color = Palette.EMBER_DEEP
	rsb.set_corner_radius_all(3)
	rsb.content_margin_left = 12
	rsb.content_margin_right = 12
	rsb.content_margin_top = 8
	rsb.content_margin_bottom = 8
	rsb.shadow_color = Palette.with_alpha(Palette.EMBER, 0.25 * Palette.GLOW)
	rsb.shadow_size = int(12 * Palette.GLOW)
	_rush_panel.add_theme_stylebox_override("panel", rsb)
	_rush_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_rush_lbl = Style.pixel_label("", 10, Palette.EMBER_BRIGHT)
	_rush_panel.add_child(_rush_lbl)
	_rush_panel.visible = false
	meta.add_child(_rush_panel)

	_enter_btn = Style.make_button("Enter Dungeon   ↵", "ember")
	_enter_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_enter_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_enter_btn.pressed.connect(_on_enter_dungeon)
	Tip.attach(_enter_btn, func() -> Dictionary:
		return {
			"name": "Daily Dungeon",
			"type": "Coin Rush · %d× coins for %ds" % [mult, Balance.inum("energy.dungeon_buff_seconds", 60)],
			"rarity": "epic",
			"stats": [
				["Energy cost", str(Balance.inum("energy.dungeon_cost", 20))],
				["Attempts left", str(GameState.dungeon_attempts)],
			],
		})
	meta.add_child(_enter_btn)
	page.add_child(meta)

	# 1s countdown tick while the modal is open.
	var tick := Timer.new()
	tick.wait_time = 1.0
	tick.autostart = true
	tick.timeout.connect(_refresh_dungeon)
	page.add_child(tick)

	_refresh_dungeon()
	return page


func _on_enter_dungeon() -> void:
	# Server-authoritative entry via the backend seam (mocked until deployed).
	var res: Dictionary = await BackendClient.dungeon_enter()
	if bool(res["ok"]):
		_refresh_dungeon()


func _refresh_dungeon() -> void:
	if _enter_btn == null:
		return
	var cost := Balance.inum("energy.dungeon_cost", 20)
	_attempts_lbl.text = ("%d attempts left" % GameState.dungeon_attempts).to_upper()
	var active := GameState.dungeon_buff_active()
	_rush_panel.visible = active
	if active:
		var left := maxi(0, GameState.dungeon_buff_until - GameState.now_utc())
		_rush_lbl.text = "GOLD RUSH ACTIVE · %d× GOLD · %ds" % [int(Balance.num("energy.dungeon_gold_mult", 3.0)), left]
		_enter_btn.disabled = true
		_enter_btn.text = "Enter Dungeon   ↵".to_upper()
	elif GameState.dungeon_attempts <= 0:
		_enter_btn.disabled = true
		_enter_btn.text = "No attempts left".to_upper()
	elif GameState.energy < cost:
		_enter_btn.disabled = true
		_enter_btn.text = ("Need %d Energy" % cost).to_upper()
	else:
		_enter_btn.disabled = false
		_enter_btn.text = "Enter Dungeon   ↵".to_upper()
