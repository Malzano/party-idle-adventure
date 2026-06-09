extends PanelContainer
## Top-right resource strip (Grimhollow .res-strip). Rank badge, player block
## (portrait + name + level + XP), then Gold / Soulstone / Energy. Pinned by
## Main to the top-right; sizes to its content. Refreshes from GameState on
## EventBus.currencies_changed / game_loaded.
##
## The rank badge and "+" affordances are chrome only for now — the leaderboard
## and shop are deferred (CLAUDE.md §9), so they carry "coming soon" tooltips.

var _name_label: Label
var _level_label: Label
var _xp_fill: ColorRect
var _gold_label: Label
var _soul_label: Label
var _energy_label: Label


func _ready() -> void:
	add_theme_stylebox_override("panel", Style.strip_box())
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_build()
	EventBus.currencies_changed.connect(_refresh)
	EventBus.game_loaded.connect(_refresh)
	_refresh()


func _build() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(row)

	row.add_child(_make_rank_badge())
	row.add_child(_make_divider())
	row.add_child(_make_player_block())
	row.add_child(_make_divider())
	row.add_child(_make_resource("res://assets/icons/coin_gold.svg", Palette.GOLD_BRIGHT, "gold"))
	row.add_child(_make_resource("res://assets/icons/soulstone.svg", Color("c98bea"), "soul"))
	row.add_child(_make_resource("res://assets/icons/energy.svg", Palette.CYAN_BRIGHT, "energy"))


func _make_divider() -> Control:
	var d := ColorRect.new()
	d.color = Palette.IRON_EDGE
	d.custom_minimum_size = Vector2(1, 38)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return d


func _make_rank_badge() -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	box.tooltip_text = "Global Rankings — coming soon"
	box.mouse_filter = Control.MOUSE_FILTER_STOP

	box.add_child(_make_icon("res://assets/icons/crown.svg", 18, Color.WHITE))

	var meta := VBoxContainer.new()
	meta.add_theme_constant_override("separation", 1)
	meta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var num := Style.display_label("#—", 15, Palette.GOLD_BRIGHT)
	var lbl := Style.pixel_label("RANK", 8, Palette.TX_MUTE)
	meta.add_child(num)
	meta.add_child(lbl)
	box.add_child(meta)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 4)
	pad.add_theme_constant_override("margin_right", 6)
	pad.add_child(box)
	return pad


func _make_player_block() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# Portrait (pixel-art drop-slot for a 48² face sprite).
	var portrait := PanelContainer.new()
	portrait.add_theme_stylebox_override("panel", Style.pixel_slot_box(true))
	portrait.custom_minimum_size = Vector2(44, 44)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ps := Style.pixel_label("48²\nface", 7, Palette.TX_MUTE)
	ps.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ps.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	portrait.add_child(ps)
	row.add_child(portrait)

	var meta := VBoxContainer.new()
	meta.add_theme_constant_override("separation", 3)
	meta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_name_label = Style.display_label(GameState.player_name, 15, Palette.GOLD_BRIGHT, true)
	meta.add_child(_name_label)
	_level_label = Style.pixel_label("LV 1", 9, Palette.EMBER_BRIGHT)
	meta.add_child(_level_label)
	meta.add_child(_make_bar(92, 5, 0.0, Palette.XP))
	row.add_child(meta)
	return row


func _make_resource(icon_path: String, value_color: Color, key: String) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	box.add_child(_make_icon(icon_path, 18, Color.WHITE))

	var value := Style.pixel_label("0", 13, value_color)
	value.custom_minimum_size = Vector2(56, 0)
	box.add_child(value)
	match key:
		"gold": _gold_label = value
		"soul": _soul_label = value
		"energy": _energy_label = value

	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(18, 18)
	plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plus.focus_mode = Control.FOCUS_NONE
	plus.tooltip_text = "Shop — coming soon"
	plus.add_theme_color_override("font_color", Color("1c0f04"))
	plus.add_theme_font_size_override("font_size", 13)
	for slot in ["normal", "hover", "pressed"]:
		plus.add_theme_stylebox_override(slot, Style.plus_box())
	box.add_child(plus)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 4)
	pad.add_theme_constant_override("margin_right", 4)
	pad.add_child(box)
	return pad


## Icon textures are authored white where tintable; [param color] modulates them.
func _make_icon(path: String, px: float, color: Color) -> TextureRect:
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(px, px)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = color
	if ResourceLoader.exists(path):
		icon.texture = load(path) as Texture2D
	return icon


func _make_bar(width: float, height: float, pct: float, fill_color: Color) -> Control:
	var bg := ColorRect.new()
	bg.color = Color("0a0807")
	bg.custom_minimum_size = Vector2(width, height)
	bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var fill := ColorRect.new()
	fill.color = fill_color
	fill.anchor_left = 0.0
	fill.anchor_top = 0.0
	fill.anchor_bottom = 1.0
	fill.anchor_right = clampf(pct, 0.0, 1.0)
	fill.offset_left = 0
	fill.offset_top = 0
	fill.offset_right = 0
	fill.offset_bottom = 0
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(fill)
	_xp_fill = fill
	return bg


func _refresh() -> void:
	if _name_label == null:
		return
	_name_label.text = GameState.player_name
	_level_label.text = "LV %d" % GameState.player_level
	_gold_label.text = _group(GameState.gold)
	_soul_label.text = _group(GameState.premium_currency)
	_energy_label.text = "%d/%d" % [GameState.energy, GameState.energy_max]
	var pct := 0.0
	if GameState.xp_to_next > 0:
		pct = float(GameState.xp) / float(GameState.xp_to_next)
	_xp_fill.anchor_right = clampf(pct, 0.0, 1.0)


## Thousands-grouped integer ("248910" -> "248,910").
func _group(value: int) -> String:
	var s := str(absi(value))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" + out) if value < 0 else out
