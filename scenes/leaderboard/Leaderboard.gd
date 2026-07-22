extends Control
## GLOBAL RANKINGS window — season header, division ladder, category tabs,
## scope filter (Global / Friends / Guild), podium, ranked table, and the
## pinned YOU bar. Ported 1:1 from .design_ref/project/leaderboard.jsx +
## leaderboard.css. Lives in its own OS window (WindowManager.WIN_LEADERBOARD);
## the X button / Esc close it. Q/W/E/R switch ranking categories.

const _ICON_CROWN := "res://assets/icons/crown.svg"
const _ICON_DIVISIONS := "res://assets/icons/nav_hero.svg"
const _GUILD_HOME := "ASH"

var _cat: String = "power"
var _scope: String = "global"

var _cat_tabs: Dictionary = {}    # cat key -> Button
var _scope_btns: Dictionary = {}  # scope key -> Button
var _podium_box: HBoxContainer
var _rows_box: VBoxContainer
var _thead_score: Label
var _youbar: PanelContainer
var _youbar_holder: MarginContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	_rebuild()


## Q/W/E/R hotkeys switch the ranking category (consumed so the window-level
## fallback never sees them). Esc is handled by WindowManager's popup keys.
func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_Q:
			_set_cat("power")
			get_viewport().set_input_as_handled()
		KEY_W:
			_set_cat("stage")
			get_viewport().set_input_as_handled()
		KEY_E:
			_set_cat("boss")
			get_viewport().set_input_as_handled()
		KEY_R:
			_set_cat("weekly")
			get_viewport().set_input_as_handled()


# =========================================================================
# Build (static chrome; podium/table/youbar content rebuilt per cat/scope)
# =========================================================================

func _build() -> void:
	# Soft darkening over the window backdrop (the design's modal-scrim feel).
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.4)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var modal := PanelContainer.new()
	modal.add_theme_stylebox_override("panel", Style.modal_box())
	modal.custom_minimum_size = Vector2(1280, 0)
	center.add_child(modal)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	modal.add_child(col)

	col.add_child(_build_header())
	col.add_child(_build_body())
	_youbar = _build_youbar_shell()
	col.add_child(_youbar)

	# Corner rivets (.frame.riveted), purely decorative.
	var rivets := _Rivets.new()
	rivets.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal.add_child(rivets)


## Modal head: crown · GLOBAL RANKINGS · season chips · X.
func _build_header() -> Control:
	var head := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(70.0 / 255.0, 56.0 / 255.0, 32.0 / 255.0, 0.22)
	sb.border_width_bottom = 1
	sb.border_color = Palette.IRON_EDGE
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	head.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	head.add_child(row)

	var crown := _icon(_ICON_CROWN, 20, Color.WHITE)
	crown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(crown)

	var title := Style.display_label("Global Rankings".to_upper(), 26, Palette.GOLD_BRIGHT)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(title)

	# Season chips (.lb-season: margin-left 18 = head gap 14 + 4).
	var season_pad := MarginContainer.new()
	season_pad.add_theme_constant_override("margin_left", 4)
	season_pad.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(season_pad)
	var season := HBoxContainer.new()
	season.add_theme_constant_override("separation", 12)
	season_pad.add_child(season)

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
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_child(Style.pixel_label("SEASON %s" % String(GameContent.SEASON["num"]), 9, Color("1c0f04")))
	season.add_child(tag)

	var sname := Style.display_label(String(GameContent.SEASON["name"]), 16, Palette.GOLD_BRIGHT, true)
	sname.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	season.add_child(sname)

	var timer := HBoxContainer.new()
	timer.add_theme_constant_override("separation", 6)
	timer.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var flame := Style.body_label("◆", 10, Palette.EMBER)
	flame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	timer.add_child(flame)
	timer.add_child(Style.body_label("Ends %s" % String(GameContent.SEASON["ends"]), 11, Palette.TX_MUTE))
	season.add_child(timer)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

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
	x.pressed.connect(func() -> void: WindowManager.close(WindowManager.WIN_LEADERBOARD))
	row.add_child(x)
	return head


## Body: 264px side column | main column, gap 18, padding 18.
func _build_body() -> Control:
	var pad := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(m, 18)
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 18)
	pad.add_child(grid)
	grid.add_child(_build_side())
	grid.add_child(_build_main())
	return pad


## Left column: Season Reward frame + Divisions ladder frame.
func _build_side() -> Control:
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(264, 0)
	side.add_theme_constant_override("separation", 14)

	# ---- Season Reward ----
	var reward := PanelContainer.new()
	reward.add_theme_stylebox_override("panel", Style.panel_box())
	var rcol := VBoxContainer.new()
	rcol.add_theme_constant_override("separation", 0)
	reward.add_child(rcol)
	rcol.add_child(_panel_head("Season Reward", _ICON_CROWN, Color.WHITE))

	var rpad := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		rpad.add_theme_constant_override(m, 14)
	rcol.add_child(rpad)
	var rstack := VBoxContainer.new()
	rstack.add_theme_constant_override("separation", 11)
	rpad.add_child(rstack)

	# 110² epic-bordered lit chest slot.
	var chest_frame := PanelContainer.new()
	var cf := StyleBoxFlat.new()
	cf.draw_center = false
	cf.set_border_width_all(1)
	cf.border_color = Palette.R_EPIC
	cf.set_corner_radius_all(5)
	chest_frame.add_theme_stylebox_override("panel", cf)
	chest_frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	chest_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chest := PixelSlot.new("96²\nEmberlord\ncache", true)
	chest.custom_minimum_size = Vector2(108, 108)
	chest_frame.add_child(chest)
	rstack.add_child(chest_frame)

	var you_season: Dictionary = GameContent.SEASON["you"]
	var tier_lbl := Style.display_label(String(you_season["tier"]), 20, Palette.R_EPIC, true)
	tier_lbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rstack.add_child(tier_lbl)

	var prog := VBoxContainer.new()
	prog.add_theme_constant_override("separation", 6)
	prog.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bar := StatBar.new("xp", float(you_season["prog"]), 7.0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prog.add_child(bar)
	# "Climb 1 rank to Hollow Sovereign" — 1 ember pixel, target legendary.
	var lblrow := HBoxContainer.new()
	lblrow.alignment = BoxContainer.ALIGNMENT_CENTER
	lblrow.add_theme_constant_override("separation", 0)
	lblrow.add_child(Style.body_label("Climb ", 11, Palette.TX_MUTE))
	var to_next := Style.pixel_label(str(int(you_season["to_next"])), 11, Palette.EMBER_BRIGHT)
	to_next.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lblrow.add_child(to_next)
	lblrow.add_child(Style.body_label(" rank to ", 11, Palette.TX_MUTE))
	lblrow.add_child(Style.body_label(String(you_season["next"]), 11, Palette.R_LEGENDARY))
	prog.add_child(lblrow)
	rstack.add_child(prog)
	side.add_child(reward)

	# ---- Divisions ladder ----
	var ladder := PanelContainer.new()
	ladder.add_theme_stylebox_override("panel", Style.panel_box())
	var lcol := VBoxContainer.new()
	lcol.add_theme_constant_override("separation", 0)
	ladder.add_child(lcol)
	lcol.add_child(_panel_head("Divisions", _ICON_DIVISIONS, Palette.EMBER))

	var lpad := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		lpad.add_theme_constant_override(m, 8)
	lcol.add_child(lpad)
	var llist := VBoxContainer.new()
	llist.add_theme_constant_override("separation", 5)
	lpad.add_child(llist)
	for t: Dictionary in GameContent.TIERS:
		llist.add_child(_ladder_row(t))
	side.add_child(ladder)
	return side


## Main column: controls (cat tabs + scope segment), podium, ranked table.
func _build_main() -> Control:
	var main := VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 14)

	# Controls row.
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 14)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for c: Dictionary in GameContent.CATS:
		var key := String(c["key"])
		var b := Style.make_tab(String(c["label"]), String(c["hot"]))
		b.pressed.connect(func() -> void: _set_cat(key))
		Style.set_tab_active(b, key == _cat)
		_cat_tabs[key] = b
		tabs.add_child(b)
	controls.add_child(tabs)
	controls.add_child(_build_scope_seg())
	main.add_child(controls)

	# Podium (#2 #1 #3, columns 1fr / 1.18fr / 1fr, bottom-aligned).
	var ppad := MarginContainer.new()
	ppad.add_theme_constant_override("margin_left", 8)
	ppad.add_theme_constant_override("margin_right", 8)
	ppad.add_theme_constant_override("margin_top", 6)
	_podium_box = HBoxContainer.new()
	_podium_box.add_theme_constant_override("separation", 14)
	ppad.add_child(_podium_box)
	main.add_child(ppad)

	main.add_child(_build_table())
	return main


## Scope segmented control (Global / Friends / Guild) — joined button row.
func _build_scope_seg() -> Control:
	var seg := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("0c0a07")
	sb.set_border_width_all(1)
	sb.border_color = Palette.IRON_EDGE
	sb.set_corner_radius_all(4)
	seg.add_theme_stylebox_override("panel", sb)
	seg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	seg.add_child(row)
	for pair: Array in GameContent.SCOPES:
		var key := String(pair[0])
		var b := Button.new()
		b.text = String(pair[1])
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", Style.fs(12))
		b.pressed.connect(func() -> void: _set_scope(key))
		_scope_btns[key] = b
		row.add_child(b)
	_refresh_scope_styles()
	return seg


## Ranked table: inset frame, thead, scrollable rows.
func _build_table() -> Control:
	var table := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("0f0d09")
	sb.set_border_width_all(1)
	sb.border_color = Palette.IRON_EDGE
	sb.set_corner_radius_all(5)
	table.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	table.add_child(col)

	# thead — cols 64 / 44 / 1fr / 190 / 150.
	var thead := PanelContainer.new()
	var hb := StyleBoxFlat.new()
	hb.bg_color = Color(60.0 / 255.0, 50.0 / 255.0, 32.0 / 255.0, 0.18)
	hb.border_width_bottom = 1
	hb.border_color = Palette.IRON_EDGE
	hb.content_margin_left = 16
	hb.content_margin_right = 16
	thead.add_theme_stylebox_override("panel", hb)
	thead.custom_minimum_size = Vector2(0, 34)
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 8)
	thead.add_child(hrow)
	hrow.add_child(_thead_cell("Rank", 64))
	hrow.add_child(_thead_cell("", 44))
	var delver := _thead_cell("Adventurer", 0)
	delver.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hrow.add_child(delver)
	hrow.add_child(_thead_cell("Division", 190))
	_thead_score = _thead_cell("", 150)
	_thead_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hrow.add_child(_thead_score)
	col.add_child(thead)

	# Scrollable rows (max-height 270).
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 270)
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 0)
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows_box)
	col.add_child(scroll)
	return table


func _thead_cell(text: String, width: float) -> Label:
	var l := Style.body_label(text.to_upper(), 10, Palette.TX_MUTE)
	if width > 0.0:
		l.custom_minimum_size = Vector2(width, 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


## Pinned YOU bar shell (ember top border + warm wash); content per cat/scope.
func _build_youbar_shell() -> PanelContainer:
	var barpanel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(120.0 / 255.0, 72.0 / 255.0, 28.0 / 255.0, 0.24)
	sb.border_width_top = 1
	sb.border_color = Palette.EMBER_DEEP
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 0
	sb.content_margin_bottom = 13
	barpanel.add_theme_stylebox_override("panel", sb)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 0)
	barpanel.add_child(stack)
	# Inset top highlight (inset 0 1px 0 rgba(232,132,58,.3)).
	var hi := ColorRect.new()
	hi.color = Palette.with_alpha(Palette.EMBER, 0.3)
	hi.custom_minimum_size = Vector2(0, 1)
	hi.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(hi)
	_youbar_holder = MarginContainer.new()
	_youbar_holder.add_theme_constant_override("margin_top", 12)
	stack.add_child(_youbar_holder)
	return barpanel


# =========================================================================
# State + rebuild
# =========================================================================

func _set_cat(key: String) -> void:
	if _cat == key:
		return
	_cat = key
	for k in _cat_tabs:
		Style.set_tab_active(_cat_tabs[k], String(k) == _cat)
	_rebuild()


func _set_scope(key: String) -> void:
	if _scope == key:
		return
	_scope = key
	_refresh_scope_styles()
	_rebuild()


func _refresh_scope_styles() -> void:
	for i in GameContent.SCOPES.size():
		var key := String(GameContent.SCOPES[i][0])
		var b: Button = _scope_btns[key]
		var active := key == _scope
		var last := i == GameContent.SCOPES.size() - 1
		for state in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(state, _scope_box(active, last))
		b.add_theme_color_override("font_color", Palette.CYAN_BRIGHT if active else Palette.TX_MUTE)
		b.add_theme_color_override("font_hover_color", Palette.CYAN_BRIGHT if active else Palette.TX_DIM)
		b.add_theme_color_override("font_pressed_color", Palette.CYAN_BRIGHT if active else Palette.TX_MUTE)


## Fetch the ranked, scoped board from the backend seam. Entries arrive
## pre-shaped (GameContent.PLAYERS element shape) and pre-sorted; the mock
## sorts/filters the static dataset with the same rules the server uses.
func _ranked() -> Array:
	var res: Dictionary = await BackendClient.leaderboard(_cat, _scope)
	if not bool(res["ok"]):
		return []
	return res["data"].get("entries", [])


func _cur_cat() -> Dictionary:
	for c: Dictionary in GameContent.CATS:
		if String(c["key"]) == _cat:
			return c
	return GameContent.CATS[0]


func _rebuild() -> void:
	var ranked: Array = await _ranked()
	var cur := _cur_cat()

	# Podium: order #2 #1 #3 (skip missing entries defensively).
	_clear(_podium_box)
	var order: Array[int] = []
	if ranked.size() >= 2:
		order.append(1)
	if ranked.size() >= 1:
		order.append(0)
	if ranked.size() >= 3:
		order.append(2)
	for idx in order:
		_podium_box.add_child(_podium_col(ranked[idx], idx + 1))

	# Table rows (ranks 4+).
	_clear(_rows_box)
	if ranked.size() <= 3:
		var pad := MarginContainer.new()
		for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
			pad.add_theme_constant_override(m, 30)
		pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var empty := Style.display_label("No adventurers in this scope yet.", 13, Palette.TX_MUTE, true)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pad.add_child(empty)
		_rows_box.add_child(pad)
	else:
		for i in range(3, ranked.size()):
			_rows_box.add_child(_table_row(ranked[i], i + 1))

	_thead_score.text = String(cur["sub"]).to_upper()
	_rebuild_youbar(ranked)


func _rebuild_youbar(ranked: Array) -> void:
	_clear(_youbar_holder)
	var you: Dictionary = {}
	var you_rank := 0
	for i in ranked.size():
		if bool(ranked[i]["you"]):
			you = ranked[i]
			you_rank = i + 1
			break
	_youbar.visible = not you.is_empty()
	if you.is_empty():
		return
	var cur := _cur_cat()

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_youbar_holder.add_child(row)

	var rank_lbl := Style.pixel_label("#%d" % you_rank, 16, Palette.EMBER_BRIGHT)
	rank_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(rank_lbl)

	var trend := _make_trend(int(you["trend"]))
	trend.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(trend)

	# 34px ember-bordered portrait.
	var pframe := PanelContainer.new()
	var pf := StyleBoxFlat.new()
	pf.draw_center = false
	pf.set_border_width_all(1)
	pf.border_color = Palette.EMBER_DEEP
	pf.set_corner_radius_all(3)
	pframe.add_theme_stylebox_override("panel", pf)
	pframe.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pframe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var port := PixelSlot.new("34²", true)
	port.custom_minimum_size = Vector2(32, 32)
	pframe.add_child(port)
	row.add_child(pframe)

	var nrow := HBoxContainer.new()
	nrow.add_theme_constant_override("separation", 7)
	nrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nrow.add_child(Style.display_label(String(you["name"]), 17, Palette.GOLD_BRIGHT, true))
	var chip := _you_chip(7)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nrow.add_child(chip)
	row.add_child(nrow)

	var gtag := _make_guild_tag(String(you["guild"]))
	row.add_child(gtag)

	# Division dot + name (epic for Emberlord).
	var tier := GameContent.tier_of(String(you["tier"]))
	var rc := Palette.rarity_color(String(tier.get("rar", "")))
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 7)
	trow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	trow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot := _Dot.new(7.0, rc)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	trow.add_child(dot)
	trow.add_child(Style.body_label(String(you["tier"]), 12, rc))
	row.add_child(trow)

	var pct := Style.display_label(String(GameContent.SEASON["you"]["pct"]), 11, Palette.CYAN_BRIGHT, true)
	pct.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(pct)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	# Right block: score over category sub-label, right-aligned.
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 2)
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var score := Style.pixel_label(GameContent.lb_fmt_val(you, _cat), 16, Palette.EMBER_BRIGHT)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(score)
	var sub := Style.body_label(String(cur["sub"]).to_upper(), 9, Palette.TX_MUTE)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(sub)
	row.add_child(right)

	var cta := Style.make_button("Climb Higher", "ember")
	cta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(cta)


# =========================================================================
# Widgets
# =========================================================================

## Division ladder row: 3px rarity left bar, glowing pip, name, range, YOU.
func _ladder_row(t: Dictionary) -> Control:
	var rar := String(t["rar"])
	var rc := Palette.rarity_color(rar)
	var is_you := bool(t["you"])

	var row := PanelContainer.new()
	var normal := _ladder_row_box(is_you, false)
	var hover := _ladder_row_box(is_you, true)
	row.add_theme_stylebox_override("panel", normal)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.mouse_entered.connect(func() -> void: row.add_theme_stylebox_override("panel", hover))
	row.mouse_exited.connect(func() -> void: row.add_theme_stylebox_override("panel", normal))
	var tip := {
		"name": String(t["name"]),
		"type": "Division · %s" % String(t["range"]),
		"rarity": rar,
		"stats": [["Season Reward", String(t["reward"])]],
	}
	if is_you:
		tip["flavor"] = "Your current division."
	Tip.attach(row, tip)

	var wrap := HBoxContainer.new()
	wrap.add_theme_constant_override("separation", 0)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(wrap)

	# border-left: 3px rarity (ember when you).
	var lbar := ColorRect.new()
	lbar.color = Palette.EMBER if is_you else rc
	lbar.custom_minimum_size = Vector2(3, 0)
	lbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(lbar)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 11)
	pad.add_theme_constant_override("margin_right", 11)
	pad.add_theme_constant_override("margin_top", 9)
	pad.add_theme_constant_override("margin_bottom", 9)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(pad)

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(box)

	var pip := _Dot.new(9.0, rc)
	pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(pip)

	var meta := VBoxContainer.new()
	meta.add_theme_constant_override("separation", 1)
	meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_child(Style.display_label(String(t["name"]), 14, rc, true))
	meta.add_child(Style.body_label(String(t["range"]), 10, Palette.TX_MUTE))
	box.add_child(meta)

	if is_you:
		var chip := _you_chip(8)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(chip)
	return row


## One podium column. rank 1 raised + legendary; 2 silver; 3 bronze.
func _podium_col(p: Dictionary, rank: int) -> Control:
	var is_you := bool(p["you"])
	var metal: Color
	if rank == 1:
		metal = Palette.R_LEGENDARY
	elif rank == 2:
		metal = Palette.SILVER
	else:
		metal = Palette.BRONZE

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("161310")
	sb.set_border_width_all(1)
	sb.border_color = metal
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	if rank == 1:
		sb.shadow_color = Palette.with_alpha(Palette.R_LEGENDARY, 0.28 * Palette.GLOW)
		sb.shadow_size = int(26 * Palette.GLOW)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	Tip.attach(panel, _row_tip(p, rank))

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 22 if rank == 1 else 16)
	pad.add_theme_constant_override("margin_bottom", 22)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(col)

	# Crown (#1) or big serif rank digit in the metal color.
	if rank == 1:
		var crown := _icon(_ICON_CROWN, 20, Color.WHITE)
		crown.custom_minimum_size = Vector2(22, 22)
		crown.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(crown)
	else:
		var digit := Style.display_label(str(rank), 20, metal)
		digit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(digit)

	# Metal-bordered portrait (104 for #1, 84 otherwise).
	var psize := 104.0 if rank == 1 else 84.0
	var pframe := PanelContainer.new()
	var pf := StyleBoxFlat.new()
	pf.draw_center = false
	pf.set_border_width_all(2)
	pf.border_color = metal
	pf.set_corner_radius_all(6)
	if rank == 1:
		pf.shadow_color = Palette.with_alpha(Palette.R_LEGENDARY, 0.4 * Palette.GLOW)
		pf.shadow_size = int(20 * Palette.GLOW)
	pframe.add_theme_stylebox_override("panel", pf)
	pframe.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pframe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var port := PixelSlot.new("88²\n%s" % String(p["name"]), true)
	port.custom_minimum_size = Vector2(psize - 4.0, psize - 4.0)
	pframe.add_child(port)
	col.add_child(pframe)

	# Name (+ YOU chip).
	var nrow := HBoxContainer.new()
	nrow.add_theme_constant_override("separation", 7)
	nrow.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	nrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nrow.add_child(Style.display_label(String(p["name"]), 18, Palette.GOLD_BRIGHT, true))
	if is_you:
		var chip := _you_chip(7)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		nrow.add_child(chip)
	col.add_child(nrow)

	# Guild tag + level.
	var grow := HBoxContainer.new()
	grow.add_theme_constant_override("separation", 8)
	grow.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grow.add_child(_make_guild_tag(String(p["guild"])))
	var lv := Style.body_label("Lv %d" % int(p["lv"]), 10, Palette.TX_MUTE)
	lv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grow.add_child(lv)
	col.add_child(grow)

	# Glowing pixel score + category sub-label.
	var score := Style.pixel_label(GameContent.lb_fmt_val(p, _cat), 22 if rank == 1 else 18, Palette.EMBER_BRIGHT)
	score.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(score)
	var sub := Style.body_label(String(_cur_cat()["sub"]).to_upper(), 9, Palette.TX_MUTE)
	sub.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(sub)

	# Bottom metal base strip (gradient line; #1 glows).
	var base := _BaseStrip.new()
	base.color = metal
	base.glow = rank == 1
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(base)

	# YOU outline ring (outline: 1px ember).
	var holder: Control = panel
	if is_you:
		var outline := PanelContainer.new()
		var ob := StyleBoxFlat.new()
		ob.draw_center = false
		ob.set_border_width_all(1)
		ob.border_color = Palette.EMBER
		ob.set_corner_radius_all(7)
		outline.add_theme_stylebox_override("panel", ob)
		outline.add_child(panel)
		holder = outline

	# Column slot: stretch ratio + bottom alignment (#2/#3 lifted 8px).
	var slot := MarginContainer.new()
	if rank != 1:
		slot.add_theme_constant_override("margin_bottom", 8)
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.size_flags_stretch_ratio = 1.18 if rank == 1 else 1.0
	slot.size_flags_vertical = Control.SIZE_SHRINK_END
	slot.add_child(holder)
	return slot


## One ranked table row (ranks 4+), h50, hover tint, full-row tooltip.
func _table_row(p: Dictionary, rank: int) -> Control:
	var is_you := bool(p["you"])
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, 50)
	var normal := _row_line_box(is_you, false)
	var hover := _row_line_box(is_you, true)
	row.add_theme_stylebox_override("panel", normal)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.mouse_entered.connect(func() -> void: row.add_theme_stylebox_override("panel", hover))
	row.mouse_exited.connect(func() -> void: row.add_theme_stylebox_override("panel", normal))
	Tip.attach(row, _row_tip(p, rank))

	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 8)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(grid)

	# Rank (#N, gold for the top 10).
	var rk := Style.pixel_label("#%d" % rank, 13, Palette.GOLD_BRIGHT if rank <= 10 else Palette.TX_DIM)
	rk.custom_minimum_size = Vector2(64, 0)
	rk.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	grid.add_child(rk)

	# Trend.
	var trend := _make_trend(int(p["trend"]))
	trend.custom_minimum_size = Vector2(44, 0)
	trend.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_child(trend)

	# Delver: portrait · name (+YOU) · guild tag · level.
	var namec := HBoxContainer.new()
	namec.add_theme_constant_override("separation", 10)
	namec.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	namec.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var port := PixelSlot.new("28²", true)
	port.custom_minimum_size = Vector2(30, 30)
	port.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	namec.add_child(port)
	var nm := Style.display_label(String(p["name"]), 15, Palette.TX, true)
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	namec.add_child(nm)
	if is_you:
		var chip := _you_chip(7)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		namec.add_child(chip)
	namec.add_child(_make_guild_tag(String(p["guild"])))
	var lv := Style.body_label("Lv %d" % int(p["lv"]), 10, Palette.TX_MUTE)
	lv.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	namec.add_child(lv)
	grid.add_child(namec)

	# Division: glow dot + rarity-colored name.
	var tier := GameContent.tier_of(String(p["tier"]))
	var rc := Palette.rarity_color(String(tier.get("rar", "")))
	var tc := HBoxContainer.new()
	tc.add_theme_constant_override("separation", 7)
	tc.custom_minimum_size = Vector2(190, 0)
	tc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot := _Dot.new(7.0, rc)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tc.add_child(dot)
	var tname := Style.body_label(String(p["tier"]), 12, rc)
	tname.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tc.add_child(tname)
	grid.add_child(tc)

	# Score, right-aligned (+ legendary ★ for ranks ≤ 3).
	var sc := HBoxContainer.new()
	sc.add_theme_constant_override("separation", 6)
	sc.custom_minimum_size = Vector2(150, 0)
	sc.alignment = BoxContainer.ALIGNMENT_END
	sc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sl := Style.pixel_label(GameContent.lb_fmt_val(p, _cat), 13, Palette.TX)
	sl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sc.add_child(sl)
	if rank <= 3:
		var star := Style.body_label("★", 13, Palette.R_LEGENDARY)
		star.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		sc.add_child(star)
	grid.add_child(sc)
	return row


## Full-row hover tooltip (player card).
func _row_tip(p: Dictionary, rank: int) -> Dictionary:
	var gd: Dictionary = GameContent.GUILDS.get(String(p["guild"]), {})
	var gname := String(gd.get("name", String(p["guild"])))
	return {
		"name": String(p["name"]) + (" (You)" if bool(p["you"]) else ""),
		"name_color": Palette.EMBER_BRIGHT if bool(p["you"]) else Palette.GOLD,
		"type": "Rank #%d · %s · Lv %d" % [rank, String(p["tier"]), int(p["lv"])],
		"rarity": "legendary",
		"stats": [
			["Total Power", "%.1fM" % float(p["power"])],
			["Deepest Stage", "%d-%02d" % [int(p["stage"][0]), int(p["stage"][1])]],
			["Boss Damage", "%.1fM" % float(p["boss"])],
			["Weekly Climb", "+%d" % int(p["weekly"])],
		],
		"flavor": gname + (" · Friend" if bool(p["friend"]) else ""),
	}


## Guild tag chip ([ASH] etc.), guild-colored, with its own tooltip.
func _make_guild_tag(g: String) -> Control:
	var gd: Dictionary = GameContent.GUILDS.get(g, {})
	var c: Color = gd.get("c", Palette.TX_MUTE)
	var gname := String(gd.get("name", g))
	var chip := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(1)
	sb.border_color = c
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 3
	sb.content_margin_bottom = 2
	chip.add_theme_stylebox_override("panel", sb)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	chip.mouse_default_cursor_shape = Control.CURSOR_HELP
	chip.add_child(Style.pixel_label("[%s]" % g, 8, c))
	Tip.attach(chip, {"name": gname, "type": "Guild · [%s]" % g, "rarity": "rare"})
	return chip


## Trend indicator: ▲ green +n / ▼ red n / – faint.
func _make_trend(t: int) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var c: Color
	var glyph: String
	if t > 0:
		c = Palette.R_UNCOMMON
		glyph = "▲"
	elif t < 0:
		c = Palette.HP
		glyph = "▼"
	else:
		c = Palette.TX_FAINT
		glyph = "–"
	var g := Style.body_label(glyph, 11, c)
	g.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(g)
	if t != 0:
		var n := Style.pixel_label(str(absi(t)), 8, c)
		n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		box.add_child(n)
	return box


## "YOU" chip — dark pixel text on ember-bright.
func _you_chip(font_size: int) -> Control:
	var chip := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.EMBER_BRIGHT
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 5 if font_size >= 8 else 4
	sb.content_margin_right = 5 if font_size >= 8 else 4
	sb.content_margin_top = 3
	sb.content_margin_bottom = 2
	chip.add_theme_stylebox_override("panel", sb)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(Style.pixel_label("YOU", font_size, Color("1c0f04")))
	return chip


## Panel heading bar (.panel-head, fontSize 12 variant).
func _panel_head(text: String, icon_path: String, icon_color: Color) -> Control:
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", Style.head_box())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	head.add_child(row)
	if icon_path != "":
		var ic := _icon(icon_path, 14, icon_color)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)
	row.add_child(Style.display_label(text.to_upper(), 12, Palette.GOLD))
	return head


## White-authored icons tint via modulate; pre-colored ones pass WHITE.
func _icon(path: String, px: float, color: Color) -> TextureRect:
	var ic := TextureRect.new()
	ic.custom_minimum_size = Vector2(px, px)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.modulate = color
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(path):
		ic.texture = load(path) as Texture2D
	return ic


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


# =========================================================================
# StyleBoxes
# =========================================================================

## Division ladder row card (.ladder-row / .you).
func _ladder_row_box(is_you: bool, hover: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color8(31, 27, 18) if hover else Color("141109")
	sb.set_border_width_all(1)
	sb.border_color = Palette.EMBER_DEEP if is_you else Palette.IRON_EDGE
	sb.set_corner_radius_all(4)
	if is_you:
		sb.shadow_color = Palette.with_alpha(Palette.EMBER, 0.22 * Palette.GLOW)
		sb.shadow_size = int(12 * Palette.GLOW)
	return sb


## Table row line (.lbr-row / .you): hover tint, ember inset bar for you.
func _row_line_box(is_you: bool, hover: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	if is_you:
		sb.bg_color = Color(232.0 / 255.0, 132.0 / 255.0, 58.0 / 255.0, 0.14 if hover else 0.10)
		sb.border_width_left = 3
		sb.border_color = Palette.EMBER
		sb.content_margin_left = 13
	else:
		sb.bg_color = Color(70.0 / 255.0, 62.0 / 255.0, 48.0 / 255.0, 0.18) if hover else Color(0, 0, 0, 0)
		sb.border_width_bottom = 1
		sb.border_color = Color(0, 0, 0, 0.35)
		sb.content_margin_left = 16
	sb.content_margin_right = 16
	return sb


## Scope segmented button (.scope-btn / .on).
func _scope_box(active: bool, last: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(29.0 / 255.0, 111.0 / 255.0, 125.0 / 255.0, 0.33) if active else Color(0, 0, 0, 0)
	if not last:
		sb.border_width_right = 1
		sb.border_color = Palette.IRON_EDGE
	sb.content_margin_left = 15
	sb.content_margin_right = 15
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	return sb


# =========================================================================
# Tiny draw helpers
# =========================================================================

## Glowing circular pip (.ladder-pip / .tier-dot).
class _Dot:
	extends Control

	var color := Color.WHITE

	func _init(d: float, c: Color) -> void:
		color = c
		custom_minimum_size = Vector2(d, d)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c, r * 2.2, Palette.with_alpha(color, 0.10 * Palette.GLOW))
		draw_circle(c, r * 1.6, Palette.with_alpha(color, 0.16 * Palette.GLOW))
		draw_circle(c, r, color)


## Podium base strip: 5px metal gradient line along the bottom; #1 glows.
class _BaseStrip:
	extends Control

	var color := Color.WHITE
	var glow := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		if size.x < 4.0 or size.y < 8.0:
			return
		var h := 5.0
		var y0 := size.y - h
		var mid := size.x * 0.5
		var t := Palette.with_alpha(color, 0.0)
		draw_polygon(
			PackedVector2Array([Vector2(0, y0), Vector2(mid, y0), Vector2(mid, size.y), Vector2(0, size.y)]),
			PackedColorArray([t, color, color, t]))
		draw_polygon(
			PackedVector2Array([Vector2(mid, y0), Vector2(size.x, y0), Vector2(size.x, size.y), Vector2(mid, size.y)]),
			PackedColorArray([color, t, t, color]))
		if glow:
			draw_rect(
				Rect2(size.x * 0.25, y0 - 4.0, size.x * 0.5, 4.0),
				Palette.with_alpha(color, 0.16 * Palette.GLOW))


## Corner rivets for the modal frame (.frame.riveted).
class _Rivets:
	extends Control

	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		if size.x < 40.0:
			return
		for x in [10.0, size.x - 10.0]:
			draw_circle(Vector2(x, 10.0), 3.5, Color.BLACK)
			draw_circle(Vector2(x, 10.0), 3.0, Color("4a4234"))
			draw_circle(Vector2(x - 1.0, 9.0), 1.2, Color(1, 1, 1, 0.15))
