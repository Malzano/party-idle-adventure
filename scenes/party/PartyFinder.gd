extends Control
## PARTY FINDER window (WindowManager.WIN_PARTY): browse open parties of
## other delvers, forge your own, and watch your members' live presence
## (level / stage / online) refresh with the combat sync heartbeat.
##
## All data flows through BackendClient.party_* — the server owns party
## membership; GameState.party is only the mirror this screen renders.

var _count_lbl: Label
var _status_lbl: Label
var _mine_body: VBoxContainer
var _list_body: VBoxContainer
var _name_edit: LineEdit
var _refreshing := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	add_child(col)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_child(_build_head())
	col.add_child(_build_body())
	EventBus.party_changed.connect(_rebuild_mine)
	visibility_changed.connect(_on_visibility_changed)
	_rebuild_mine()
	_refresh()


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		_refresh()


## Pull fresh truth from the backend (mine + open list).
func _refresh() -> void:
	if _refreshing:
		return
	_refreshing = true
	_status("Consulting the notice board…", Palette.TX_MUTE)
	await BackendClient.party_mine()
	var res: Dictionary = await BackendClient.party_list()
	_refreshing = false
	if not is_instance_valid(self):
		return
	if bool(res["ok"]):
		_rebuild_list(res["data"]["parties"])
		_status("", Palette.TX_MUTE)
	else:
		_status(_err_msg(res), Palette.HP)


# =========================================================================
# Header
# =========================================================================

func _build_head() -> Control:
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", Style.head_box())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	head.add_child(row)

	var title_col := VBoxContainer.new()
	title_col.add_theme_constant_override("separation", 1)
	title_col.add_child(Style.display_label("PARTY FINDER", 24, Palette.GOLD_BRIGHT))
	title_col.add_child(Style.body_label("Delve together — presence syncs while the party fights.", 12, Palette.TX_MUTE))
	row.add_child(title_col)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	_status_lbl = Style.body_label("", 12, Palette.TX_MUTE)
	_status_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_status_lbl)

	var refresh := Style.make_button("REFRESH", "ghost", 11)
	refresh.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	refresh.pressed.connect(_refresh)
	row.add_child(refresh)

	var x := Button.new()
	x.text = "✕"
	x.focus_mode = Control.FOCUS_NONE
	x.custom_minimum_size = Vector2(36, 36)
	x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	x.add_theme_font_size_override("font_size", 18)
	x.add_theme_color_override("font_color", Palette.TX_DIM)
	x.add_theme_color_override("font_hover_color", Palette.EMBER_BRIGHT)
	x.add_theme_color_override("font_pressed_color", Palette.EMBER_BRIGHT)
	var xsb := StyleBoxFlat.new()
	xsb.bg_color = Palette.STONE
	xsb.set_border_width_all(1)
	xsb.border_color = Palette.IRON_EDGE
	xsb.set_corner_radius_all(3)
	for state in ["normal", "hover", "pressed"]:
		x.add_theme_stylebox_override(state, xsb)
	x.pressed.connect(func() -> void: WindowManager.close(WindowManager.WIN_PARTY))
	row.add_child(x)
	return head


func _status(text: String, col: Color) -> void:
	if _status_lbl != null:
		_status_lbl.text = text
		_status_lbl.add_theme_color_override("font_color", col)


# =========================================================================
# Body: 560px YOUR PARTY | open parties list
# =========================================================================

func _build_body() -> Control:
	var pad := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(m, 18)
	pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 18)
	pad.add_child(grid)

	# --- Left: your party ---
	var mine_panel := PanelContainer.new()
	mine_panel.custom_minimum_size = Vector2(560, 0)
	mine_panel.add_theme_stylebox_override("panel", Style.panel_box())
	var mine_col := VBoxContainer.new()
	mine_col.add_theme_constant_override("separation", 0)
	mine_panel.add_child(mine_col)

	var mh := PanelContainer.new()
	mh.add_theme_stylebox_override("panel", Style.head_box())
	var mh_row := HBoxContainer.new()
	mh_row.add_child(Style.display_label("YOUR PARTY", 14, Palette.GOLD))
	var mh_sp := Control.new()
	mh_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mh_sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mh_row.add_child(mh_sp)
	_count_lbl = Style.pixel_label("—", 10, Palette.R_UNCOMMON)
	_count_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mh_row.add_child(_count_lbl)
	mh.add_child(mh_row)
	mine_col.add_child(mh)

	var mine_pad := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		mine_pad.add_theme_constant_override(m, 14)
	mine_pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_mine_body = VBoxContainer.new()
	_mine_body.add_theme_constant_override("separation", 8)
	mine_pad.add_child(_mine_body)
	mine_col.add_child(mine_pad)
	grid.add_child(mine_panel)

	# --- Right: open parties ---
	var list_panel := PanelContainer.new()
	list_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_panel.add_theme_stylebox_override("panel", Style.panel_box())
	var list_col := VBoxContainer.new()
	list_col.add_theme_constant_override("separation", 0)
	list_panel.add_child(list_col)

	var lh := PanelContainer.new()
	lh.add_theme_stylebox_override("panel", Style.head_box())
	var lh_row := HBoxContainer.new()
	lh_row.add_child(Style.display_label("OPEN PARTIES", 14, Palette.GOLD))
	var lh_sp := Control.new()
	lh_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lh_sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lh_row.add_child(lh_sp)
	lh_row.add_child(Style.body_label("presence refreshes every 45 s", 11, Palette.TX_FAINT))
	lh.add_child(lh_row)
	list_col.add_child(lh)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list_pad := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		list_pad.add_theme_constant_override(m, 14)
	list_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_body = VBoxContainer.new()
	_list_body.add_theme_constant_override("separation", 8)
	_list_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_pad.add_child(_list_body)
	scroll.add_child(list_pad)
	list_col.add_child(scroll)
	grid.add_child(list_panel)
	return pad


# =========================================================================
# YOUR PARTY column
# =========================================================================

func _rebuild_mine() -> void:
	if _mine_body == null:
		return
	for child in _mine_body.get_children():
		_mine_body.remove_child(child)
		child.queue_free()

	var party: Dictionary = GameState.party
	if party.is_empty():
		_count_lbl.text = "SOLO"
		_build_forge_form()
		return

	_count_lbl.text = "%d/4" % int(party["member_count"])
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	name_row.add_child(Style.display_label(String(party["name"]), 20, Palette.GOLD_BRIGHT))
	var vis := Style.pixel_label("PUBLIC" if bool(party["is_public"]) else "PRIVATE", 9, Palette.TX_FAINT)
	vis.size_flags_vertical = Control.SIZE_SHRINK_END
	name_row.add_child(vis)
	_mine_body.add_child(name_row)
	_mine_body.add_child(Style.rune_divider())

	var members: Array = party["members"]
	for m_v in members:
		_mine_body.add_child(_member_row(m_v))
	for _i in range(members.size(), 4):
		_mine_body.add_child(_recruiting_row())

	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mine_body.add_child(sp)

	var leave := Style.make_button("LEAVE PARTY", "ghost", 12)
	leave.pressed.connect(func() -> void:
		var res: Dictionary = await BackendClient.party_leave()
		if not bool(res["ok"]):
			_status(_err_msg(res), Palette.HP)
		else:
			_refresh())
	_mine_body.add_child(leave)


## Solo: name it and forge one.
func _build_forge_form() -> void:
	var blurb := Style.body_label(
		"You delve alone. Forge a party and other delvers can rally to your banner — everyone's progress stays in step while the fight runs.",
		13, Palette.TX_DIM)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mine_body.add_child(blurb)
	_mine_body.add_child(Style.rune_divider())

	_mine_body.add_child(Style.pixel_label("NAME YOUR PARTY", 9, Palette.TX_MUTE))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "e.g. Ember Pact"
	_name_edit.max_length = 24
	_name_edit.custom_minimum_size = Vector2(0, 40)
	_name_edit.add_theme_stylebox_override("normal", Style.inset_box())
	_name_edit.add_theme_stylebox_override("focus", Style.inset_box())
	_name_edit.add_theme_color_override("font_color", Palette.TX)
	_name_edit.add_theme_color_override("font_placeholder_color", Palette.TX_FAINT)
	_name_edit.add_theme_color_override("caret_color", Palette.EMBER_BRIGHT)
	_name_edit.add_theme_font_size_override("font_size", 15)
	_name_edit.text_submitted.connect(func(_t: String) -> void: _forge())
	_mine_body.add_child(_name_edit)

	var forge := Style.make_button("FORGE A PARTY", "ember", 13)
	forge.custom_minimum_size = Vector2(0, 44)
	forge.pressed.connect(_forge)
	_mine_body.add_child(forge)

	var hint := Style.body_label("…or join one from the notice board →", 12, Palette.TX_FAINT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mine_body.add_child(hint)


func _forge() -> void:
	var pname := _name_edit.text.strip_edges()
	if pname.length() < 3:
		_status("Party name must be 3-24 characters.", Palette.HP)
		return
	var res: Dictionary = await BackendClient.party_create(pname, true)
	if not bool(res["ok"]):
		_status(_err_msg(res), Palette.HP)
	else:
		_status("The %s banner is raised." % pname, Palette.R_UNCOMMON)


func _member_row(m: Dictionary) -> Control:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", Style.row_box())
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	row.add_child(box)

	var portrait := Control.new()
	portrait.custom_minimum_size = Vector2(40, 40)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ps := PixelSlot.new("36²\n%s" % String(m.get("class_id", "?")).left(4), true)
	portrait.add_child(ps)
	ps.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_child(portrait)

	var meta := VBoxContainer.new()
	meta.add_theme_constant_override("separation", 2)
	meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var nrow := HBoxContainer.new()
	nrow.add_theme_constant_override("separation", 7)
	var nm := String(m["name"]) + (" (you)" if _is_self(m) else "")
	nrow.add_child(Style.display_label(nm, 15, Palette.TX, true))
	if bool(m.get("leader", false)):
		nrow.add_child(Style.pixel_label("★ LEADER", 8, Palette.GOLD_BRIGHT))
	meta.add_child(nrow)
	meta.add_child(Style.body_label(
		"%s · LV %d" % [_class_name(String(m.get("class_id", ""))), int(m["level"])],
		11, _class_color(String(m.get("class_id", "")))))
	box.add_child(meta)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 2)
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var presence := HBoxContainer.new()
	presence.add_theme_constant_override("separation", 5)
	var online := bool(m.get("online", false))
	presence.add_child(Style.pixel_label("●", 9, Palette.R_UNCOMMON if online else Palette.TX_FAINT))
	presence.add_child(Style.body_label("Online" if online else "Away", 10, Palette.TX_MUTE))
	right.add_child(presence)
	var stage: Array = m["stage"]
	var srow := Style.body_label("Stage %d-%d · %s" % [int(stage[0]), int(stage[1]), _power_label(int(m["power"]))], 11, Palette.TX_DIM)
	srow.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(srow)
	box.add_child(right)
	return row


func _recruiting_row() -> Control:
	var row := PanelContainer.new()
	var sb := Style.row_box()
	sb.bg_color = Color(0, 0, 0, 0.12)
	row.add_theme_stylebox_override("panel", sb)
	var lbl := Style.body_label("— recruiting… the banner is on the board —", 12, Palette.TX_FAINT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(lbl)
	return row


# =========================================================================
# OPEN PARTIES column
# =========================================================================

func _rebuild_list(open_parties: Array) -> void:
	for child in _list_body.get_children():
		_list_body.remove_child(child)
		child.queue_free()

	if open_parties.is_empty():
		var empty := Style.body_label(
			"The Hollow is quiet — no open parties right now. Forge your own and the banner goes up here.",
			13, Palette.TX_MUTE)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list_body.add_child(empty)
		return

	for p_v in open_parties:
		_list_body.add_child(_party_row(p_v))


func _party_row(p: Dictionary) -> Control:
	var row := PanelContainer.new()
	var normal := Style.row_box()
	var hover := Style.row_box(true)
	row.add_theme_stylebox_override("panel", normal)
	row.mouse_entered.connect(func() -> void: row.add_theme_stylebox_override("panel", hover))
	row.mouse_exited.connect(func() -> void: row.add_theme_stylebox_override("panel", normal))
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	row.add_child(box)

	var meta := VBoxContainer.new()
	meta.add_theme_constant_override("separation", 3)
	meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var nrow := HBoxContainer.new()
	nrow.add_theme_constant_override("separation", 8)
	nrow.add_child(Style.display_label(String(p["name"]), 16, Palette.TX))
	nrow.add_child(Style.pixel_label("%d/4" % int(p["member_count"]), 9, Palette.R_UNCOMMON))
	meta.add_child(nrow)

	# Member minis: class-colored initials + online dots.
	var minis := HBoxContainer.new()
	minis.add_theme_constant_override("separation", 8)
	var online_n := 0
	for m_v in p["members"]:
		var m: Dictionary = m_v
		if bool(m.get("online", false)):
			online_n += 1
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 3)
		var cid := String(m.get("class_id", ""))
		chip.add_child(Style.pixel_label(_class_initial(cid), 10, _class_color(cid)))
		chip.add_child(Style.body_label("%s · LV %d" % [String(m["name"]), int(m["level"])], 10, Palette.TX_MUTE))
		minis.add_child(chip)
	meta.add_child(minis)
	box.add_child(meta)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 3)
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var key := int(p["avg_stage_key"])
	var stage_lbl := Style.body_label("≈ Stage %d-%d" % [int(key / 100.0), key % 100], 12, Palette.GOLD_BRIGHT)
	stage_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(stage_lbl)
	var online_lbl := Style.body_label("%d online" % online_n, 10, Palette.TX_MUTE)
	online_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(online_lbl)
	box.add_child(right)

	var join := Style.make_button("JOIN", "ember", 12)
	join.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	join.custom_minimum_size = Vector2(96, 40)
	join.disabled = GameState.in_party()
	if join.disabled:
		Tip.attach(join, {"name": "Already partied", "type": "", "rarity": "",
			"flavor": "Leave your current party first."})
	var pid := String(p["id"])
	join.pressed.connect(func() -> void:
		var res: Dictionary = await BackendClient.party_join(pid)
		if not bool(res["ok"]):
			_status(_err_msg(res), Palette.HP)
		_refresh())
	box.add_child(join)
	return row


# =========================================================================
# Helpers
# =========================================================================

func _is_self(m: Dictionary) -> bool:
	var uid := String(m.get("uid", ""))
	return uid == "me" or String(m.get("name", "")) == GameState.player_name


func _class_name(id: String) -> String:
	var cls := GameContent.class_by_id(id)
	return String(cls["name"]) if not cls.is_empty() else "Wanderer"


func _class_initial(id: String) -> String:
	return id.left(1).to_upper() if id != "" else "?"


func _class_color(id: String) -> Color:
	match id:
		"warrior":
			return Palette.HP
		"mage":
			return Palette.R_RARE
		"hunter":
			return Palette.R_UNCOMMON
		"rogue":
			return Palette.GOLD_BRIGHT
	return Palette.TX_MUTE


func _power_label(power: int) -> String:
	if power >= 1_000_000:
		return "%.1fM PWR" % (float(power) / 1_000_000.0)
	if power >= 1_000:
		return "%.0fK PWR" % (float(power) / 1_000.0)
	return "%d PWR" % power


func _err_msg(res: Dictionary) -> String:
	var data: Dictionary = res.get("data", {})
	return String((data.get("error", {}) as Dictionary).get("message", "The notice board is unreadable."))
