extends Control
## First-launch character creation, Path of Exile style: four figures stand
## around a campfire in the dark; clicking one steps it forward and reveals
## its lore panel (GameContent.CLASSES). Naming + "Begin the Delve" locks the
## class into GameState and routes to Main. Profiles that already exist skip
## straight to Main (SaveManager loads before any scene).

const FIG_W := 220.0
const FIG_H := 416.0
const FIG_GAP := 56.0

var _selected := ""
var _cards: Dictionary = {}        # class id -> card Control
var _card_base_y: Dictionary = {}  # class id -> resting y
var _hint: Label
var _desc_panel: PanelContainer
var _desc_name: Label
var _desc_title: Label
var _desc_tag: Label
var _desc_body: Label
var _desc_stats: VBoxContainer
var _name_edit: LineEdit
var _begin_btn: Button


func _ready() -> void:
	if GameState.has_profile():
		get_tree().change_scene_to_file.call_deferred("res://scenes/main/Main.tscn")
		return
	_build()


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Palette.BG_0
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Campfire: warm flickering glow low-center, figures lit from below.
	var fire := EmberFire.new()
	add_child(fire)
	fire.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var fire_sprite := PixelSlot.new("120×90\ncampfire", true)
	fire_sprite.custom_minimum_size = Vector2(120, 90)
	add_child(fire_sprite)
	fire_sprite.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	fire_sprite.offset_left = -60
	fire_sprite.offset_right = 60
	fire_sprite.offset_top = 836
	fire_sprite.offset_bottom = 926

	_build_title()
	_build_figures()
	_build_desc_panel()
	_build_begin_block()

	_hint = Style.body_label("The fire waits. Choose who walks into the Hollow.", 15, Palette.TX_MUTE)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_hint.offset_left = -400
	_hint.offset_right = 400
	_hint.offset_top = 952
	_hint.offset_bottom = 980


func _build_title() -> void:
	var title := Style.display_label("GRIMHOLLOW", 46, Palette.GOLD_BRIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.offset_left = -500
	title.offset_right = 500
	title.offset_top = 56
	title.offset_bottom = 116

	var sub := Style.body_label("— CHOOSE YOUR DELVER —", 13, Palette.TX_MUTE)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sub)
	sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	sub.offset_left = -300
	sub.offset_right = 300
	sub.offset_top = 122
	sub.offset_bottom = 146


func _build_figures() -> void:
	var n := GameContent.CLASSES.size()
	var total_w := FIG_W * float(n) + FIG_GAP * float(n - 1)
	var x0 := (1920.0 - total_w) * 0.5
	for i in n:
		var cls: Dictionary = GameContent.CLASSES[i]
		var id := String(cls["id"])
		var card := _figure_card(cls)
		# Outer figures stand a step back (depth around the fire).
		var y := 248.0 + (26.0 if (i == 0 or i == n - 1) else 0.0)
		card.position = Vector2(x0 + float(i) * (FIG_W + FIG_GAP), y)
		add_child(card)
		_cards[id] = card
		_card_base_y[id] = y
		_apply_card_state(id)


func _figure_card(cls: Dictionary) -> Control:
	var id := String(cls["id"])
	var card := Control.new()
	card.custom_minimum_size = Vector2(FIG_W, FIG_H)
	card.size = Vector2(FIG_W, FIG_H)
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# Selection ring behind the figure (hidden until chosen).
	var ring := Panel.new()
	ring.name = "Ring"
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.set_border_width_all(1)
	sb.border_color = Palette.EMBER_DEEP
	sb.set_corner_radius_all(8)
	sb.shadow_color = Palette.with_alpha(Palette.EMBER, 0.30 * Palette.GLOW)
	sb.shadow_size = int(16 * Palette.GLOW)
	ring.add_theme_stylebox_override("panel", sb)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.visible = false
	card.add_child(ring)
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Placeholder figure art (sprite swapped in later).
	var ps := PixelSlot.new(String(cls["sprite"]), true)
	ps.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(ps)
	ps.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ps.offset_left = 10
	ps.offset_top = 8
	ps.offset_right = -10
	ps.offset_bottom = -96

	# Caption: name / title / attribute chip.
	var cap := VBoxContainer.new()
	cap.add_theme_constant_override("separation", 2)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(cap)
	cap.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	cap.offset_top = -88
	cap.offset_bottom = -6

	var nm := Style.display_label(String(cls["name"]).to_upper(), 22, Palette.GOLD_BRIGHT)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_child(nm)
	var tt := Style.body_label(String(cls["title"]), 12, Palette.TX_MUTE)
	tt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_child(tt)
	var at := Style.pixel_label(String(cls["attrs"]), 9, Palette.EMBER_BRIGHT)
	at.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_child(at)

	card.gui_input.connect(func(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_select(id))
	card.mouse_entered.connect(func() -> void: _apply_card_state(id, true))
	card.mouse_exited.connect(func() -> void: _apply_card_state(id))
	return card


func _select(id: String) -> void:
	if _selected == id:
		return
	_selected = id
	if _hint != null:
		_hint.visible = false
	for cid in _cards:
		_apply_card_state(String(cid))
		var card: Control = _cards[cid]
		var target_y: float = _card_base_y[cid] - (22.0 if String(cid) == id else 0.0)
		var tw := create_tween()
		tw.tween_property(card, "position:y", target_y, 0.18) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_fill_desc(GameContent.class_by_id(id))
	_begin_btn.disabled = false
	_name_edit.grab_focus()


## Dim the row; the chosen one stands lit, hover brightens candidates.
func _apply_card_state(id: String, hovered: bool = false) -> void:
	var card: Control = _cards[id]
	var ring := card.get_node("Ring") as Panel
	ring.visible = _selected == id
	if _selected == id:
		card.modulate = Color.WHITE
	elif hovered:
		card.modulate = Color(0.92, 0.90, 0.86)
	elif _selected == "":
		card.modulate = Color(0.74, 0.72, 0.68)
	else:
		card.modulate = Color(0.52, 0.50, 0.48)


## PoE-style lore panel, bottom-left: name, epithet, tagline, story, facts.
func _build_desc_panel() -> void:
	_desc_panel = PanelContainer.new()
	_desc_panel.add_theme_stylebox_override("panel", Style.panel_box(true))
	add_child(_desc_panel)
	_desc_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_desc_panel.offset_left = 64
	_desc_panel.offset_right = 664
	_desc_panel.offset_top = -372
	_desc_panel.offset_bottom = -64
	_desc_panel.visible = false

	var pad := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(m, 20)
	_desc_panel.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	pad.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)
	_desc_name = Style.display_label("", 30, Palette.GOLD_BRIGHT)
	head.add_child(_desc_name)
	_desc_title = Style.display_label("", 16, Palette.TX_MUTE, true)
	_desc_title.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(_desc_title)

	_desc_tag = Style.body_label("", 14, Palette.EMBER_BRIGHT)
	col.add_child(_desc_tag)
	col.add_child(Style.rune_divider())

	_desc_body = Style.body_label("", 14, Palette.TX_DIM)
	_desc_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_desc_body)

	_desc_stats = VBoxContainer.new()
	_desc_stats.add_theme_constant_override("separation", 3)
	col.add_child(_desc_stats)


func _fill_desc(cls: Dictionary) -> void:
	_desc_panel.visible = true
	_desc_name.text = String(cls["name"]).to_upper()
	_desc_title.text = String(cls["title"])
	_desc_tag.text = "“%s”" % String(cls["tagline"])
	_desc_body.text = String(cls["desc"])
	for child in _desc_stats.get_children():
		child.queue_free()
	for pair in cls["stats"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var k := Style.pixel_label(String(pair[0]).to_upper(), 8, Palette.TX_FAINT)
		k.custom_minimum_size = Vector2(86, 0)
		row.add_child(k)
		row.add_child(Style.body_label(String(pair[1]), 13, Palette.TX))
		_desc_stats.add_child(row)


## Bottom-right: naming + the commit button.
func _build_begin_block() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Style.panel_box())
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.offset_left = -424
	panel.offset_right = -64
	panel.offset_top = -252
	panel.offset_bottom = -64

	var pad := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(m, 18)
	panel.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	pad.add_child(col)

	var lbl := Style.pixel_label("NAME YOUR DELVER", 9, Palette.TX_MUTE)
	col.add_child(lbl)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Delver"
	_name_edit.max_length = 16
	_name_edit.custom_minimum_size = Vector2(0, 42)
	_name_edit.add_theme_stylebox_override("normal", Style.inset_box())
	_name_edit.add_theme_stylebox_override("focus", Style.inset_box())
	_name_edit.add_theme_color_override("font_color", Palette.TX)
	_name_edit.add_theme_color_override("font_placeholder_color", Palette.TX_FAINT)
	_name_edit.add_theme_color_override("caret_color", Palette.EMBER_BRIGHT)
	_name_edit.add_theme_font_size_override("font_size", 16)
	_name_edit.text_submitted.connect(func(_t: String) -> void: _begin())
	col.add_child(_name_edit)

	_begin_btn = Style.make_button("BEGIN THE DELVE", "ember", 15)
	_begin_btn.custom_minimum_size = Vector2(0, 48)
	_begin_btn.disabled = true
	_begin_btn.pressed.connect(_begin)
	col.add_child(_begin_btn)


func _begin() -> void:
	if _selected == "" or GameState.has_profile():
		return
	GameState.choose_class(_selected, _name_edit.text)
	SaveManager.save_game()
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")


## Flickering campfire glow + drifting sparks (pure draw, no assets).
class EmberFire:
	extends Control

	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var c := Vector2(size.x * 0.5, size.y * 0.82)
		var flick := 1.0 + 0.05 * sin(_t * 9.0) + 0.035 * sin(_t * 23.7) + 0.02 * sin(_t * 41.3)
		draw_circle(c, 340.0 * flick, Color(0.91, 0.518, 0.227, 0.045))
		draw_circle(c, 220.0 * flick, Color(0.91, 0.518, 0.227, 0.07))
		draw_circle(c, 120.0 * flick, Color(0.96, 0.64, 0.30, 0.10))
		draw_circle(c, 56.0 * flick, Color(0.99, 0.76, 0.42, 0.13))
		# Rising sparks on stable per-spark phases (no RNG: deterministic boot).
		for i in 9:
			var ph := float(i) * 1.618
			var rise := fmod(_t * (28.0 + 7.0 * fmod(ph, 1.0)) + ph * 97.0, 240.0)
			var sway := sin(_t * 1.7 + ph * 3.1) * (10.0 + rise * 0.12)
			var p := c + Vector2(sway + (fmod(ph * 53.0, 60.0) - 30.0), -36.0 - rise)
			var a := clampf(1.0 - rise / 240.0, 0.0, 1.0) * 0.55
			draw_circle(p, 1.6, Color(0.99, 0.72, 0.36, a))
