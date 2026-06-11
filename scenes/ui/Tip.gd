class_name Tip
extends RefCounted
## Gothic hover-tooltip system (the design's TipBus/ItemTip), multi-window
## aware: each OS window gets its own tooltip layer, created on demand.
##
## Usage:
##   Tip.attach(control, {"name": "Cindergrip Maul", "type": "Two-Handed · Epic",
##       "rarity": "epic", "stats": [["Physical DMG", "412–588"]],
##       "flavor": "Forged in the last ember of a dead star."})
## `data` may also be a Callable returning such a Dictionary (re-evaluated on
## every hover, for live values).

const _LAYER_META := "gh_tip_layer"


## Attach a tooltip to [param ctrl]. Safe to call once per control.
static func attach(ctrl: Control, data: Variant) -> void:
	ctrl.mouse_filter = Control.MOUSE_FILTER_STOP if ctrl.mouse_filter == Control.MOUSE_FILTER_IGNORE else ctrl.mouse_filter
	ctrl.mouse_entered.connect(func() -> void: _show(ctrl, data))
	ctrl.mouse_exited.connect(func() -> void: _hide(ctrl))
	ctrl.tree_exiting.connect(func() -> void: _hide(ctrl))


static func _show(ctrl: Control, data: Variant) -> void:
	var window := ctrl.get_window()
	if window == null:
		return
	var layer := _layer_for(window)
	var d: Dictionary = data.call() if data is Callable else data
	layer.show_tip(d)


static func _hide(ctrl: Control) -> void:
	var window := ctrl.get_window()
	if window == null:
		return
	if window.has_meta(_LAYER_META):
		(window.get_meta(_LAYER_META) as TipLayer).hide_tip()


static func _layer_for(window: Window) -> TipLayer:
	if window.has_meta(_LAYER_META):
		return window.get_meta(_LAYER_META) as TipLayer
	var canvas := CanvasLayer.new()
	canvas.layer = 99
	window.add_child(canvas)
	var layer := TipLayer.new()
	canvas.add_child(layer)
	window.set_meta(_LAYER_META, layer)
	return layer


## The per-window tooltip layer: a styled panel that follows the mouse.
class TipLayer:
	extends Control

	var _panel: PanelContainer
	var _column: VBoxContainer

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel = PanelContainer.new()
		_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("15110d")
		sb.set_border_width_all(1)
		sb.border_color = Palette.IRON_EDGE
		sb.set_corner_radius_all(4)
		sb.shadow_color = Color(0, 0, 0, 0.7)
		sb.shadow_size = 14
		sb.shadow_offset = Vector2(0, 8)
		_panel.add_theme_stylebox_override("panel", sb)
		_panel.custom_minimum_size = Vector2(0, 0)
		add_child(_panel)
		_column = VBoxContainer.new()
		_column.add_theme_constant_override("separation", 0)
		_column.custom_minimum_size = Vector2(0, 0)
		_panel.add_child(_column)
		visible = false
		set_process(false)

	func show_tip(d: Dictionary) -> void:
		_rebuild(d)
		visible = true
		set_process(true)
		_reposition()

	func hide_tip() -> void:
		visible = false
		set_process(false)

	func _process(_delta: float) -> void:
		_reposition()

	func _reposition() -> void:
		var mouse := get_viewport().get_mouse_position()
		var rect := get_viewport_rect()
		var sz := _panel.get_combined_minimum_size()
		var pos := mouse + Vector2(18, 16)
		if pos.x + sz.x > rect.size.x - 8.0:
			pos.x = mouse.x - sz.x - 16.0
		if pos.y + sz.y > rect.size.y - 8.0:
			pos.y = rect.size.y - sz.y - 8.0
		pos.y = maxf(8.0, pos.y)
		_panel.position = pos

	func _rebuild(d: Dictionary) -> void:
		for child in _column.get_children():
			child.queue_free()
		var rarity := String(d.get("rarity", ""))
		var name_color: Color = d.get("name_color", Palette.rarity_color(rarity) if rarity != "" else Palette.GOLD)

		# Head: name (italic serif, rarity-colored) + type line.
		var head := MarginContainer.new()
		_margins(head, 12, 12, 9, 7)
		var head_col := VBoxContainer.new()
		head_col.add_theme_constant_override("separation", 2)
		var name_lbl := Style.display_label(String(d.get("name", "")), 15, name_color, true)
		head_col.add_child(name_lbl)
		var type_text := String(d.get("type", ""))
		if type_text != "":
			var type_lbl := Label.new()
			type_lbl.text = type_text.to_upper()
			type_lbl.add_theme_font_size_override("font_size", 10)
			type_lbl.add_theme_color_override("font_color", Palette.TX_MUTE)
			head_col.add_child(type_lbl)
		head.add_child(head_col)
		_column.add_child(head)

		# Body: stat rows (label dim, value cyan).
		var stats: Array = d.get("stats", [])
		if not stats.is_empty():
			_column.add_child(_hairline())
			var body := MarginContainer.new()
			_margins(body, 12, 12, 9, 9)
			var body_col := VBoxContainer.new()
			body_col.add_theme_constant_override("separation", 3)
			for s in stats:
				var row := HBoxContainer.new()
				row.add_theme_constant_override("separation", 18)
				var k := Label.new()
				k.text = String(s[0])
				k.add_theme_font_size_override("font_size", 12)
				k.add_theme_color_override("font_color", Palette.TX_DIM)
				k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(k)
				var v := Label.new()
				v.text = String(s[1])
				v.add_theme_font_size_override("font_size", 12)
				v.add_theme_color_override("font_color", Palette.CYAN_BRIGHT)
				row.add_child(v)
				body_col.add_child(row)
			body.add_child(body_col)
			_column.add_child(body)

		# Flavor: italic muted quote.
		var flavor := String(d.get("flavor", ""))
		if flavor != "":
			_column.add_child(_hairline())
			var flav := MarginContainer.new()
			_margins(flav, 12, 12, 7, 10)
			var f := Style.display_label("“%s”" % flavor, 11, Palette.TX_MUTE, true)
			f.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			f.custom_minimum_size = Vector2(220, 0)
			flav.add_child(f)
			_column.add_child(flav)

	func _hairline() -> ColorRect:
		var h := ColorRect.new()
		h.color = Color(0, 0, 0, 0.5)
		h.custom_minimum_size = Vector2(0, 1)
		return h

	static func _margins(m: MarginContainer, l: int, r: int, t: int, b: int) -> void:
		m.add_theme_constant_override("margin_left", l)
		m.add_theme_constant_override("margin_right", r)
		m.add_theme_constant_override("margin_top", t)
		m.add_theme_constant_override("margin_bottom", b)
