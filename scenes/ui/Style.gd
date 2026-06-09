class_name Style
extends RefCounted
## Grimhollow style factory — beveled-iron StyleBoxes and pre-styled labels.
##
## Centralizes the look so screens compose from these helpers instead of
## hand-tuning colors per node. Mirrors the design's .frame / .rail-btn /
## .res-strip / .key / .pixel-slot rules (.design_ref/project/*.css).

# ---- StyleBoxes ----

## Beveled iron panel (.frame). [param raised] uses the lighter raised base.
static func panel_box(raised: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.BG_3 if raised else Palette.BG_2
	sb.set_border_width_all(1)
	sb.border_color = Palette.IRON_EDGE
	sb.set_corner_radius_all(3)
	sb.shadow_color = Palette.GROOVE
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 6)
	return sb


## Panel heading bar (.panel-head): faint warm tint + bottom hairline.
static func head_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.235, 0.196, 0.125, 0.18)
	sb.border_width_bottom = 1
	sb.border_color = Palette.IRON_EDGE
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 11
	sb.content_margin_bottom = 10
	return sb


## Top-right resource strip pill (.res-strip).
static func strip_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("1c1812")
	sb.set_border_width_all(1)
	sb.border_color = Palette.IRON_EDGE
	sb.set_corner_radius_all(5)
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 8)
	sb.content_margin_left = 6
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


## Left rail base (.rail).
static func rail_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.BG_1
	sb.border_width_right = 1
	sb.border_color = Palette.IRON_EDGE
	return sb


## Rail nav button (.rail-btn / .rail-btn.active). Active glows ember.
static func rail_btn_box(active: bool, hover: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(4)
	sb.set_border_width_all(1)
	if active:
		sb.bg_color = Color8(120, 72, 28, 128)
		sb.border_color = Palette.EMBER_DEEP
		sb.shadow_color = Color(Palette.EMBER.r, Palette.EMBER.g, Palette.EMBER.b, 0.4 * Palette.GLOW)
		sb.shadow_size = int(18 * Palette.GLOW)
	else:
		sb.bg_color = Color8(70, 60, 44, 150) if hover else Color8(50, 44, 34, 128)
		sb.border_color = Palette.IRON_EDGE
	return sb


## Keycap hotkey chip (.key).
static func key_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("0c0a07")
	sb.set_border_width_all(1)
	sb.border_color = Palette.GOLD_DIM
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	sb.content_margin_top = 3
	sb.content_margin_bottom = 2
	return sb


## Pixel-art drop-slot (.pixel-slot). [param lit] adds the ember wash border.
static func pixel_slot_box(lit: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("16130e")
	sb.set_border_width_all(1)
	sb.border_color = Palette.GOLD_DIM if lit else Palette.TX_FAINT
	sb.set_corner_radius_all(3)
	if lit:
		sb.shadow_color = Color(Palette.EMBER.r, Palette.EMBER.g, Palette.EMBER.b, 0.25 * Palette.GLOW)
		sb.shadow_size = int(10 * Palette.GLOW)
	return sb


## Small ember "+" affordance (.res-plus).
static func plus_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.EMBER
	sb.set_border_width_all(1)
	sb.border_color = Color("3a1d08")
	sb.set_corner_radius_all(3)
	sb.shadow_color = Color(Palette.EMBER.r, Palette.EMBER.g, Palette.EMBER.b, 0.4 * Palette.GLOW)
	sb.shadow_size = int(8 * Palette.GLOW)
	return sb


# ---- Labels ----

## Display-font label (Spectral). Uppercase/letterspacing left to the caller.
static func display_label(text: String, size: int, color: Color, italic: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	var f := Fonts.display_italic() if italic else Fonts.display()
	if f != null:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## Pixel-font label (Silkscreen) — hotkeys, numerics, tickers.
static func pixel_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	var f := Fonts.pixel()
	if f != null:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## A faded rune-divider line (.rune-div).
static func rune_divider() -> ColorRect:
	var r := ColorRect.new()
	r.color = Palette.GOLD_DIM
	r.custom_minimum_size = Vector2(0, 2)
	r.modulate = Color(1, 1, 1, 0.5)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return r
