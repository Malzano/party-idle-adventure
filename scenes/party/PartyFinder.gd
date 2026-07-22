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
var _forge_public := true
var _code_edit: LineEdit
var _social_body: VBoxContainer
var _my_code_lbl: Label
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


## Pull fresh truth from the backend (mine + open list + friends/guild).
func _refresh() -> void:
	if _refreshing:
		return
	_refreshing = true
	_status("Consulting the notice board…", Palette.TX_MUTE)
	await BackendClient.party_mine()
	var res: Dictionary = await BackendClient.party_list()
	var friends: Dictionary = await BackendClient.friends_get()
	var guild: Dictionary = await BackendClient.guild_get()
	_refreshing = false
	if not is_instance_valid(self):
		return
	_rebuild_social(friends, guild)
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
	x.add_theme_font_size_override("font_size", Style.fs(18))
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

	# --- Left: your party stacked over friends & guild ---
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(560, 0)
	left.add_theme_constant_override("separation", 18)

	var mine_panel := PanelContainer.new()
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
	_mine_body = VBoxContainer.new()
	_mine_body.add_theme_constant_override("separation", 8)
	mine_pad.add_child(_mine_body)
	mine_col.add_child(mine_pad)
	left.add_child(mine_panel)
	left.add_child(_build_social_panel())
	grid.add_child(left)

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
	lh_row.add_theme_constant_override("separation", 10)
	lh_row.add_child(Style.display_label("OPEN PARTIES", 14, Palette.GOLD))
	var lh_sp := Control.new()
	lh_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lh_sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lh_row.add_child(lh_sp)
	# Private parties join here, by code.
	_code_edit = _styled_edit("DELV-XXXX", 10)
	_code_edit.custom_minimum_size = Vector2(150, 34)
	_code_edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_code_edit.text_submitted.connect(func(_t: String) -> void: _join_by_code())
	lh_row.add_child(_code_edit)
	var code_btn := Style.make_button("JOIN BY CODE", "ghost", 10)
	code_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	code_btn.pressed.connect(_join_by_code)
	lh_row.add_child(code_btn)
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

	_count_lbl.text = "%d/3" % int(party["member_count"])
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	name_row.add_child(Style.display_label(String(party["name"]), 20, Palette.GOLD_BRIGHT))
	var vis := Style.pixel_label("PUBLIC" if bool(party["is_public"]) else "PRIVATE", 9, Palette.TX_FAINT)
	vis.size_flags_vertical = Control.SIZE_SHRINK_END
	name_row.add_child(vis)
	var nr_sp := Control.new()
	nr_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nr_sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_child(nr_sp)
	# Invite code (members-only payload) — how friends reach a private party.
	var code := String(party.get("join_code", ""))
	if code != "":
		var code_lbl := Style.pixel_label(code, 10, Palette.EMBER_BRIGHT)
		code_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		Tip.attach(code_lbl, {
			"name": "Invite code",
			"type": "",
			"rarity": "",
			"flavor": "Share it — friends join with JOIN BY CODE, even when the party is private.",
		})
		name_row.add_child(code_lbl)
	_mine_body.add_child(name_row)
	_mine_body.add_child(Style.rune_divider())

	var members: Array = party["members"]
	for m_v in members:
		_mine_body.add_child(_member_row(m_v))
	for _i in range(members.size(), BackendClient.PARTY_CAP):
		_mine_body.add_child(_recruiting_row())

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
		"You adventure alone. Start a party and other adventurers can hop in — everyone's progress stays in step while the fight runs.",
		13, Palette.TX_DIM)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mine_body.add_child(blurb)
	_mine_body.add_child(Style.rune_divider())

	_mine_body.add_child(Style.pixel_label("NAME YOUR PARTY", 9, Palette.TX_MUTE))
	_name_edit = _styled_edit("e.g. Ember Pact", 15)
	_name_edit.max_length = 24
	_name_edit.custom_minimum_size = Vector2(0, 40)
	_name_edit.text_submitted.connect(func(_t: String) -> void: _forge())
	_mine_body.add_child(_name_edit)

	# Visibility: PUBLIC lists it on the board; PRIVATE is invite-code only.
	var vis_btn := Style.make_button("BANNER · PUBLIC", "ghost", 11)
	vis_btn.pressed.connect(func() -> void:
		_forge_public = not _forge_public
		vis_btn.text = "BANNER · PUBLIC" if _forge_public else "BANNER · PRIVATE")
	Tip.attach(vis_btn, {
		"name": "Banner visibility",
		"type": "",
		"rarity": "",
		"flavor": "Public parties appear on the board. Private ones are joined only by invite code.",
	})
	_mine_body.add_child(vis_btn)

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
	var res: Dictionary = await BackendClient.party_create(pname, _forge_public)
	if not bool(res["ok"]):
		_status(_err_msg(res), Palette.HP)
	else:
		_status("The %s banner is raised." % pname, Palette.R_UNCOMMON)


func _join_by_code() -> void:
	var code := _code_edit.text.strip_edges()
	if code == "":
		return
	var res: Dictionary = await BackendClient.party_join("", code)
	if not bool(res["ok"]):
		_status(_err_msg(res), Palette.HP)
	else:
		_code_edit.text = ""
		_status("Joined by invite.", Palette.R_UNCOMMON)
	_refresh()


## The shared dark inset text field.
func _styled_edit(placeholder: String, font_size: int) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.add_theme_stylebox_override("normal", Style.inset_box())
	e.add_theme_stylebox_override("focus", Style.inset_box())
	e.add_theme_color_override("font_color", Palette.TX)
	e.add_theme_color_override("font_placeholder_color", Palette.TX_FAINT)
	e.add_theme_color_override("caret_color", Palette.EMBER_BRIGHT)
	e.add_theme_font_size_override("font_size", Style.fs(font_size))
	return e


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
			"The meadow is quiet — no open parties right now. Start your own and the banner goes up here.",
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
	nrow.add_child(Style.pixel_label("%d/3" % int(p["member_count"]), 9, Palette.R_UNCOMMON))
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
# FRIENDS & GUILD (left column, under your party)
# =========================================================================

func _build_social_panel() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", Style.panel_box())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	panel.add_child(col)

	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", Style.head_box())
	var hrow := HBoxContainer.new()
	hrow.add_child(Style.display_label("FRIENDS & GUILD", 14, Palette.GOLD))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hrow.add_child(sp)
	_my_code_lbl = Style.pixel_label("", 9, Palette.TX_MUTE)
	_my_code_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Tip.attach(_my_code_lbl, {
		"name": "Your friend code",
		"type": "",
		"rarity": "",
		"flavor": "Trade codes to add each other — adds are mutual.",
	})
	hrow.add_child(_my_code_lbl)
	head.add_child(hrow)
	col.add_child(head)

	var pad := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(m, 14)
	pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_social_body = VBoxContainer.new()
	_social_body.add_theme_constant_override("separation", 8)
	pad.add_child(_social_body)
	col.add_child(pad)
	return panel


func _rebuild_social(friends_res: Dictionary, guild_res: Dictionary) -> void:
	if _social_body == null:
		return
	for child in _social_body.get_children():
		_social_body.remove_child(child)
		child.queue_free()

	# --- Friends ---
	if bool(friends_res.get("ok", false)):
		var data: Dictionary = friends_res["data"]
		_my_code_lbl.text = "YOUR CODE · %s" % String(data.get("friend_code", ""))
		var friends: Array = data.get("friends", [])
		if friends.is_empty():
			_social_body.add_child(Style.body_label(
				"No friends yet — trade codes with other adventurers.", 12, Palette.TX_MUTE))
		for f_v in friends:
			_social_body.add_child(_friend_row(f_v))

	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 8)
	var code_edit := _styled_edit("GRIM-XXXX-XX", 12)
	code_edit.custom_minimum_size = Vector2(0, 36)
	code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(code_edit)
	var add_btn := Style.make_button("ADD FRIEND", "ghost", 10)
	add_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var do_add := func() -> void:
		if code_edit.text.strip_edges() == "":
			return
		var res: Dictionary = await BackendClient.friends_add(code_edit.text)
		if bool(res["ok"]):
			_status("%s answers the call." % String(res["data"]["added"]["name"]), Palette.R_UNCOMMON)
			_refresh()
		else:
			_status(_err_msg(res), Palette.HP)
	code_edit.text_submitted.connect(func(_t: String) -> void: do_add.call())
	add_btn.pressed.connect(do_add)
	add_row.add_child(add_btn)
	_social_body.add_child(add_row)

	_social_body.add_child(Style.rune_divider())

	# --- Guild ---
	if bool(guild_res.get("ok", false)):
		var g: Dictionary = guild_res["data"]["guild"]
		var grow := HBoxContainer.new()
		grow.add_theme_constant_override("separation", 10)
		var tag := PanelContainer.new()
		var tag_sb := StyleBoxFlat.new()
		tag_sb.bg_color = Palette.EMBER
		tag_sb.set_border_width_all(1)
		tag_sb.border_color = Color("3a1d08")
		tag_sb.set_corner_radius_all(3)
		tag_sb.content_margin_left = 7
		tag_sb.content_margin_right = 7
		tag_sb.content_margin_top = 4
		tag_sb.content_margin_bottom = 3
		tag.add_theme_stylebox_override("panel", tag_sb)
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tag.add_child(Style.pixel_label(String(g["tag"]), 9, Color("1c0f04")))
		grow.add_child(tag)
		var gmeta := VBoxContainer.new()
		gmeta.add_theme_constant_override("separation", 1)
		gmeta.add_child(Style.display_label(String(g["name"]), 15, Palette.GOLD_BRIGHT))
		gmeta.add_child(Style.body_label(
			"%d pals aboard" % (g["members"] as Array).size(), 11, Palette.TX_MUTE))
		grow.add_child(gmeta)
		_social_body.add_child(grow)
	else:
		_social_body.add_child(Style.body_label(
			"You are sworn to no guild.", 12, Palette.TX_MUTE))
		var jrow := HBoxContainer.new()
		jrow.add_theme_constant_override("separation", 8)
		var tag_edit := _styled_edit("Guild tag, e.g. ASH", 12)
		tag_edit.custom_minimum_size = Vector2(0, 36)
		tag_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		jrow.add_child(tag_edit)
		var join_btn := Style.make_button("JOIN GUILD", "ghost", 10)
		join_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var do_join := func() -> void:
			if tag_edit.text.strip_edges() == "":
				return
			var res: Dictionary = await BackendClient.guild_join(tag_edit.text)
			if bool(res["ok"]):
				_status("Sworn to %s." % String(res["data"]["guild"]["name"]), Palette.R_UNCOMMON)
				_refresh()
			else:
				_status(_err_msg(res), Palette.HP)
		tag_edit.text_submitted.connect(func(_t: String) -> void: do_join.call())
		join_btn.pressed.connect(do_join)
		jrow.add_child(join_btn)
		_social_body.add_child(jrow)


func _friend_row(f: Dictionary) -> Control:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", Style.row_box())
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	row.add_child(box)
	box.add_child(Style.display_label(String(f["name"]), 13, Palette.TX, true))
	box.add_child(Style.body_label("LV %d" % int(f["lv"]), 11, Palette.TX_MUTE))
	if String(f.get("guild", "")) != "":
		box.add_child(Style.pixel_label(String(f["guild"]), 8, Palette.GOLD_DIM))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(sp)
	box.add_child(Style.body_label(_power_label(int(f["power"])), 11, Palette.TX_DIM))
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
