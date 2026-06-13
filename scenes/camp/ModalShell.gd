extends Control
## Shared centered-modal shell for the Camp building popups (camp.jsx
## ModalShell + styles.css .modal-*): full-rect scrim (click on the scrim
## closes), centered riveted frame with head (ember diamond · uppercase serif
## title · ✕) and a padded body column. Entrance: fade + 18px rise over .22s.
##
## Esc closes the modal and CONSUMES the event at the _input stage, so
## WindowManager's per-window popup keys never see it and the Camp window
## itself survives. Subclasses override _build_body() and _on_modal_key().

const _FX := preload("res://scenes/camp/CampFx.gd")

signal closed

var modal_title: String = "Modal"
var modal_width: float = 1180.0
## Default gap between body sections; subclasses tweak before _ready.
var body_separation: int = 16

var _frame: PanelContainer
var _frame_base_y: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Scrim — click directly on it closes (the frame swallows its own clicks).
	var scrim := ColorRect.new()
	scrim.color = Style.scrim_color()
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.gui_input.connect(_on_scrim_input)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_frame = PanelContainer.new()
	_frame.add_theme_stylebox_override("panel", Style.modal_box())
	_frame.custom_minimum_size = Vector2(modal_width, 0)
	center.add_child(_frame)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	_frame.add_child(col)
	col.add_child(_build_head())

	var body_pad := MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		body_pad.add_theme_constant_override(m, 20)
	col.add_child(body_pad)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", body_separation)
	body_pad.add_child(body)
	_build_body(body)

	var rivets := _FX.Rivets.new()
	_frame.add_child(rivets)

	modulate.a = 0.0
	call_deferred("_play_entrance")


## Subclasses fill the padded body column here.
func _build_body(_body: VBoxContainer) -> void:
	pass


## Subclasses handle extra hotkeys; return true to consume the event.
func _on_modal_key(_keycode: Key) -> bool:
	return false


func request_close() -> void:
	closed.emit()
	queue_free()


## _input (not unhandled input) so the modal beats WindowManager._PopupKeys:
## Esc must close the modal, not the whole Camp window.
func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		request_close()
	elif _on_modal_key(k.keycode):
		get_viewport().set_input_as_handled()


# =========================================================================
# Internals
# =========================================================================

func _on_scrim_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		request_close()


## .modal-head: warm gradient strip, icon · uppercase title · spacer · ✕.
func _build_head() -> Control:
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

	var ico := Style.body_label("◆", 14, Palette.EMBER)
	ico.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ico)

	var title := Style.display_label(modal_title.to_upper(), 26, Palette.GOLD_BRIGHT)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	var x := Button.new()
	x.text = "✕"
	x.focus_mode = Control.FOCUS_NONE
	x.custom_minimum_size = Vector2(36, 36)
	x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	x.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
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
	x.pressed.connect(request_close)
	row.add_child(x)
	return head


## Fade the whole modal in while the frame rises 18px and unsquashes .985 → 1.
func _play_entrance() -> void:
	_frame_base_y = _frame.position.y
	_frame.pivot_offset = _frame.size * 0.5
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.18)
	tw.tween_method(_apply_rise, 0.0, 1.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _apply_rise(t: float) -> void:
	_frame.position.y = _frame_base_y + 18.0 * (1.0 - t)
	_frame.scale = Vector2.ONE * (0.985 + 0.015 * t)
