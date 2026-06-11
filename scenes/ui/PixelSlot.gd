class_name PixelSlot
extends Control
## Pixel-art drop-slot (the design's .pixel-slot): a 16px two-tone checker
## with a dashed border and a small uppercase pixel-font label, marking where
## a real sprite (pixellab.ai) will be dropped. `lit` adds a faint ember wash.

const _DARK := Color("14110d")
const _LIGHT := Color("1a1712")
const _LIT_LIGHT := Color("1c1813")
const _BORDER := Color(0.588, 0.51, 0.353, 0.32)

@export var label_text: String = ""
@export var lit: bool = false

var _label: Label


func _init(p_label: String = "", p_lit: bool = false) -> void:
	label_text = p_label
	lit = p_lit


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if label_text != "":
		_label = Style.pixel_label(label_text.to_upper(), 8, Palette.TX_MUTE)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_label)
	resized.connect(queue_redraw)


func _draw() -> void:
	var light := _LIT_LIGHT if lit else _LIGHT
	# 16px checker (two 8px tones per tile).
	var tile := 8.0
	var cols := int(ceil(size.x / tile))
	var rows := int(ceil(size.y / tile))
	for cy in rows:
		for cx in cols:
			var c := light if (cx + cy) % 2 == 0 else _DARK
			draw_rect(Rect2(cx * tile, cy * tile, tile, tile).intersection(Rect2(Vector2.ZERO, size)), c)
	# Ember wash (lit): cheap radial approximation via concentric circles.
	if lit:
		var center := Vector2(size.x * 0.5, size.y * 0.4)
		var max_r := minf(size.x, size.y) * 0.45
		for i in 4:
			var t := 1.0 - float(i) / 4.0
			draw_circle(center, max_r * t, Color(0.91, 0.52, 0.23, 0.03))
	# Dashed border.
	var d := 4.0
	_dashed(Vector2(0, 0), Vector2(size.x, 0), d)
	_dashed(Vector2(size.x, 0), Vector2(size.x, size.y), d)
	_dashed(Vector2(size.x, size.y), Vector2(0, size.y), d)
	_dashed(Vector2(0, size.y), Vector2(0, 0), d)


func _dashed(from: Vector2, to: Vector2, dash: float) -> void:
	draw_dashed_line(from, to, _BORDER, 1.0, dash)
