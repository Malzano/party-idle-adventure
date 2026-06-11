class_name StatBar
extends Control
## Inset status bar (the design's .bar): hp (red), mana (blue), xp (gold).
## Set [member pct] 0..100; optionally overlay a tiny pixel-font label.

@export_enum("hp", "mana", "xp") var kind: String = "hp"
@export var pct: float = 100.0:
	set(v):
		pct = clampf(v, 0.0, 100.0)
		queue_redraw()
@export var bar_height: float = 9.0

var _label: Label


func _init(p_kind: String = "hp", p_pct: float = 100.0, p_height: float = 9.0, p_label: String = "") -> void:
	kind = p_kind
	pct = p_pct
	bar_height = p_height
	custom_minimum_size = Vector2(0, p_height)
	if p_label != "":
		_label = Style.pixel_label(p_label, 8, Color.WHITE)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _label != null:
		_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_label)
	resized.connect(queue_redraw)


func set_label(text: String) -> void:
	if _label != null:
		_label.text = text


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	# Track.
	draw_rect(r, Color("0a0807"))
	draw_rect(r, Color.BLACK, false, 1.0)
	# Fill: vertical two-tone gradient approximated with two rects.
	var w := size.x * pct / 100.0
	if w > 0.5:
		var top: Color
		var bottom: Color
		match kind:
			"hp":
				top = Color("e0584a")
				bottom = Palette.HP_D
			"mana":
				top = Color("5cc0e8")
				bottom = Palette.MANA_D
			_:
				top = Palette.GOLD_BRIGHT
				bottom = Palette.GOLD_DIM
		var half := size.y * 0.5
		draw_rect(Rect2(1, 1, maxf(0.0, w - 2.0), maxf(0.0, half - 1.0)), top)
		draw_rect(Rect2(1, half, maxf(0.0, w - 2.0), maxf(0.0, half - 1.0)), bottom)
