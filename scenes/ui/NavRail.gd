extends Control
## Persistent left navigation rail (Grimhollow .rail) on the MAIN window.
## Crest at top, three icon buttons (CAMP 1 / FIGHT 2 / HERO 3), options gear
## at the bottom. Fight is the main window itself (always lit); Camp and Hero
## open their own OS windows — their buttons light while the window is open.

## Display order. id strings mirror the GameState.SCREEN_* constants.
const _ENTRIES := [
	{"id": "camp", "label": "Camp", "hotkey": "1", "icon": "res://assets/icons/nav_camp.svg"},
	{"id": "fight", "label": "Fight", "hotkey": "2", "icon": "res://assets/icons/nav_fight.svg"},
	{"id": "hero", "label": "Hero", "hotkey": "3", "icon": "res://assets/icons/nav_hero.svg"},
]

var _entries_ui: Dictionary = {}  # id -> {button, icon, label, hot, indicator}


func _ready() -> void:
	custom_minimum_size = Vector2(Palette.RAIL_W, 0)
	_build()
	_apply_button_state("fight", true)  # the main window IS the fight scene
	EventBus.window_state_changed.connect(_on_window_state_changed)
	# Tutorial spotlight anchors (nav steps 10/13).
	if _entries_ui.has("hero"):
		TutorialOverlay.register_anchor("nav.hero", _entries_ui["hero"]["button"])
	if _entries_ui.has("camp"):
		TutorialOverlay.register_anchor("nav.camp", _entries_ui["camp"]["button"])


func _build() -> void:
	# Rail backing panel + gold right-edge line.
	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", Style.rail_box())
	add_child(panel)

	var edge := ColorRect.new()
	edge.color = Palette.GOLD_DIM
	edge.modulate = Color(1, 1, 1, 0.35)
	edge.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	edge.custom_minimum_size = Vector2(2, 0)
	edge.offset_left = -2
	edge.offset_right = 0
	add_child(edge)

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_BEGIN
	column.add_theme_constant_override("separation", 10)
	column.offset_top = 14
	column.offset_bottom = -16
	add_child(column)

	column.add_child(_make_crest())

	var nav_spacer_top := Control.new()
	nav_spacer_top.custom_minimum_size = Vector2(0, 6)
	column.add_child(nav_spacer_top)

	for entry in _ENTRIES:
		column.add_child(_make_rail_button(entry))

	# Push the options button to the bottom.
	var flex := Control.new()
	flex.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(flex)

	column.add_child(_make_options_button())


func _make_crest() -> Control:
	var crest := TextureRect.new()
	crest.custom_minimum_size = Vector2(56, 56)
	crest.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	crest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_set_texture(crest, "res://assets/icons/crest.svg")
	crest.tooltip_text = "%s — Idle Crawler" % GameContent.GAME_TITLE
	return crest


func _make_rail_button(entry: Dictionary) -> Button:
	var id: String = entry["id"]
	var button := Button.new()
	button.custom_minimum_size = Vector2(84, 80)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.focus_mode = Control.FOCUS_ALL  # keep keyboard/controller nav alive
	button.tooltip_text = "%s  (Press %s)" % [entry["label"], entry["hotkey"]]
	button.pressed.connect(_on_button_pressed.bind(id))

	# Icon + label stack, centered, transparent to clicks.
	var stack := VBoxContainer.new()
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 3)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(stack)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(28, 28)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_texture(icon, entry["icon"])
	stack.add_child(icon)

	var label := Style.display_label(String(entry["label"]).to_upper(), 10, Palette.TX_MUTE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(label)

	# Hotkey chip, top-right.
	var hot := Style.pixel_label(String(entry["hotkey"]), 8, Palette.TX_FAINT)
	hot.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hot.offset_left = -18
	hot.offset_top = 4
	hot.offset_right = -5
	hot.offset_bottom = 16
	hot.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(hot)

	# Left ember indicator (shown when active).
	var indicator := ColorRect.new()
	indicator.color = Palette.EMBER_BRIGHT
	indicator.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	indicator.offset_left = -12
	indicator.offset_top = -19
	indicator.offset_right = -8
	indicator.offset_bottom = 19
	indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	indicator.visible = false
	button.add_child(indicator)

	_entries_ui[id] = {"button": button, "icon": icon, "label": label, "hot": hot, "indicator": indicator}
	_apply_button_state(id, false)
	return button


func _make_options_button() -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(56, 54)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.focus_mode = Control.FOCUS_ALL
	button.modulate = Color(1, 1, 1, 0.7)
	button.tooltip_text = "Options"
	button.pressed.connect(func() -> void: WindowManager.open(WindowManager.WIN_SETTINGS))
	for slot in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(slot, Style.rail_btn_box(false))

	var icon := TextureRect.new()
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 13
	icon.offset_top = 13
	icon.offset_right = -13
	icon.offset_bottom = -13
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = Palette.TX_MUTE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_texture(icon, "res://assets/icons/gear.svg")
	button.add_child(icon)
	return button


## Nav action: Fight focuses the main window; Camp/Hero open/focus their windows.
func select(screen: String) -> void:
	match screen:
		"camp":
			WindowManager.open(WindowManager.WIN_CAMP)
		"hero":
			WindowManager.open(WindowManager.WIN_HERO)
		_:
			WindowManager.focus_main()


func _on_window_state_changed(id: String, open: bool) -> void:
	if _entries_ui.has(id):
		_apply_button_state(id, open)
	# Fight stays lit regardless — the main window never closes.
	_apply_button_state("fight", true)


func _apply_button_state(id: String, active: bool) -> void:
	var ui: Dictionary = _entries_ui[id]
	var button: Button = ui["button"]
	button.add_theme_stylebox_override("normal", Style.rail_btn_box(active))
	button.add_theme_stylebox_override("hover", Style.rail_btn_box(active, true))
	button.add_theme_stylebox_override("pressed", Style.rail_btn_box(active))
	button.add_theme_stylebox_override("focus", Style.rail_btn_box(active))
	(ui["icon"] as TextureRect).modulate = Palette.EMBER_BRIGHT if active else Palette.TX_MUTE
	(ui["label"] as Label).add_theme_color_override("font_color", Palette.EMBER_BRIGHT if active else Palette.TX_MUTE)
	(ui["hot"] as Label).add_theme_color_override("font_color", Palette.EMBER if active else Palette.TX_FAINT)
	(ui["indicator"] as ColorRect).visible = active


func _on_button_pressed(screen: String) -> void:
	select(screen)


func _set_texture(tex_rect: TextureRect, path: String) -> void:
	if ResourceLoader.exists(path):
		tex_rect.texture = load(path) as Texture2D


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_1:
			select("camp")
		KEY_2:
			select("fight")
		KEY_3:
			select("hero")
		KEY_L:
			WindowManager.open(WindowManager.WIN_LEADERBOARD)
		KEY_P:
			WindowManager.open(WindowManager.WIN_PARTY)
