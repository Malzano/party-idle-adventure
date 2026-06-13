class_name Style
extends RefCounted
## Grimhollow style factory — beveled-iron StyleBoxes, buttons, tabs, and
## pre-styled labels. Centralizes the look so screens compose from these
## helpers instead of hand-tuning colors per node. Mirrors the design's
## .frame / .btn / .tab / .slot / .modal rules (.design_ref/project/*.css).

# =========================================================================
# Panels & chrome
# =========================================================================

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
		sb.shadow_color = Palette.with_alpha(Palette.EMBER, 0.4 * Palette.GLOW)
		sb.shadow_size = int(18 * Palette.GLOW)
	else:
		sb.bg_color = Color8(70, 60, 44, 150) if hover else Color8(50, 44, 34, 128)
		sb.border_color = Palette.IRON_EDGE
	return sb


## Modal panel (.modal frame): raised panel with a heavier drop shadow.
static func modal_box() -> StyleBoxFlat:
	var sb := panel_box(true)
	sb.shadow_size = 26
	sb.shadow_offset = Vector2(0, 14)
	return sb


## Modal scrim color (.modal-scrim).
static func scrim_color() -> Color:
	return Color(0, 0, 0, 0.72)


## Dark inset card (#100d09 bordered) used for rates boxes / quest rows etc.
static func inset_box(radius: int = 4) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("100d09")
	sb.set_border_width_all(1)
	sb.border_color = Palette.IRON_EDGE
	sb.set_corner_radius_all(radius)
	return sb


## Row card (linear-gradient #1a1610 → #131009 approximated flat).
static func row_box(highlight: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("171310")
	sb.set_border_width_all(1)
	sb.border_color = Palette.EMBER_DEEP if highlight else Palette.IRON_EDGE
	sb.set_corner_radius_all(4)
	if highlight:
		sb.shadow_color = Palette.with_alpha(Palette.EMBER, 0.2 * Palette.GLOW)
		sb.shadow_size = int(12 * Palette.GLOW)
	return sb


# =========================================================================
# Buttons & tabs
# =========================================================================

## Stone button (.btn) StyleBox per state.
static func btn_box(state: String = "normal") -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("3f382b") if state == "hover" else Palette.STONE
	sb.set_border_width_all(1)
	sb.border_color = Palette.IRON_EDGE
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	if state == "hover":
		sb.shadow_color = Palette.with_alpha(Palette.EMBER, 0.3 * Palette.GLOW)
		sb.shadow_size = int(10 * Palette.GLOW)
	return sb


## Ember CTA button (.btn-ember) StyleBox per state.
static func btn_ember_box(state: String = "normal") -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.EMBER_BRIGHT if state == "hover" else Palette.EMBER
	sb.set_border_width_all(1)
	sb.border_color = Color("3a1d08")
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	sb.shadow_color = Palette.with_alpha(Palette.EMBER, 0.45 * Palette.GLOW)
	sb.shadow_size = int(16 * Palette.GLOW)
	return sb


## Ghost button (.btn-ghost) StyleBox.
static func btn_ghost_box(state: String = "normal") -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.22, 0.19, 0.14, 0.55 if state == "hover" else 0.4)
	sb.set_border_width_all(1)
	sb.border_color = Palette.IRON_EDGE
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	return sb


## A fully styled Grimhollow button. kind: "stone" | "ember" | "ghost".
static func make_button(text: String, kind: String = "stone", font_size: int = 13) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	# Keyboard/controller reachable (Steam Deck, CLAUDE.md §1): Tab/arrows move
	# focus, Enter/Space activates. Mouse-only feel is preserved by an ember
	# focus ring instead of the engine's default grey box.
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_stylebox_override("focus", focus_ring())
	var f := Fonts.display()
	if f != null:
		b.add_theme_font_override("font", f)
	b.add_theme_font_size_override("font_size", fs(font_size))
	match kind:
		"ember":
			b.add_theme_stylebox_override("normal", btn_ember_box())
			b.add_theme_stylebox_override("hover", btn_ember_box("hover"))
			b.add_theme_stylebox_override("pressed", btn_ember_box())
			b.add_theme_stylebox_override("disabled", btn_ghost_box())
			b.add_theme_color_override("font_color", Color("1c0f04"))
			b.add_theme_color_override("font_hover_color", Color("1c0f04"))
			b.add_theme_color_override("font_pressed_color", Color("1c0f04"))
		"ghost":
			b.add_theme_stylebox_override("normal", btn_ghost_box())
			b.add_theme_stylebox_override("hover", btn_ghost_box("hover"))
			b.add_theme_stylebox_override("pressed", btn_ghost_box())
			b.add_theme_stylebox_override("disabled", btn_ghost_box())
			b.add_theme_color_override("font_color", Palette.TX_DIM)
			b.add_theme_color_override("font_hover_color", Palette.TX)
		_:
			b.add_theme_stylebox_override("normal", btn_box())
			b.add_theme_stylebox_override("hover", btn_box("hover"))
			b.add_theme_stylebox_override("pressed", btn_box())
			b.add_theme_stylebox_override("disabled", btn_ghost_box())
			b.add_theme_color_override("font_color", Palette.TX)
			b.add_theme_color_override("font_hover_color", Palette.TX)
	b.add_theme_color_override("font_disabled_color", Palette.TX_FAINT)
	return b


## Keyboard-focus ring: subtle ember outline drawn over the control's own
## stylebox (the "focus" theme slot draws on top of normal/hover).
static func focus_ring() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.set_border_width_all(1)
	sb.border_color = Palette.with_alpha(Palette.EMBER_BRIGHT, 0.85)
	sb.set_corner_radius_all(4)
	sb.shadow_color = Palette.with_alpha(Palette.EMBER, 0.25 * Palette.GLOW)
	sb.shadow_size = int(6 * Palette.GLOW)
	return sb


## Tab button styleboxes (.tab/.ptab/.inv-tab/.cat-tab family).
static func tab_box(active: bool, hover: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(4)
	sb.set_border_width_all(1)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	if active:
		sb.bg_color = Color8(120, 72, 28, 122)
		sb.border_color = Palette.EMBER_DEEP
		sb.shadow_color = Palette.with_alpha(Palette.EMBER, 0.22 * Palette.GLOW)
		sb.shadow_size = int(12 * Palette.GLOW)
	else:
		sb.bg_color = Color8(50, 44, 34, 150 if hover else 100)
		sb.border_color = Palette.IRON_EDGE
	return sb


## A fully styled tab button; caller connects pressed + calls set_active.
static func make_tab(text: String, hotkey: String = "") -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.text = text.to_upper() + ("   %s" % hotkey if hotkey != "" else "")
	var f := Fonts.display()
	if f != null:
		b.add_theme_font_override("font", f)
	b.add_theme_font_size_override("font_size", fs(13))
	set_tab_active(b, false)
	return b


static func set_tab_active(b: Button, active: bool) -> void:
	b.add_theme_stylebox_override("normal", tab_box(active))
	b.add_theme_stylebox_override("hover", tab_box(active, true))
	b.add_theme_stylebox_override("pressed", tab_box(active))
	b.add_theme_color_override("font_color", Palette.EMBER_BRIGHT if active else Palette.TX_MUTE)
	b.add_theme_color_override("font_hover_color", Palette.EMBER_BRIGHT if active else Palette.TX_DIM)
	b.add_theme_color_override("font_pressed_color", Palette.EMBER_BRIGHT if active else Palette.TX_MUTE)


# =========================================================================
# Slots & chips
# =========================================================================

## Keycap hotkey chip (.key) StyleBox.
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


## A keycap chip control (.key): pixel font on near-black.
static func make_keycap(text: String, font_size: int = 9) -> Control:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", key_box())
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := pixel_label(text, font_size, Palette.GOLD_BRIGHT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.add_child(label)
	return chip


## Item slot frame (.slot / .slot.filled). Filled slots glow their rarity.
static func slot_box(rarity: String = "", filled: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("131008")
	sb.set_corner_radius_all(3)
	sb.set_border_width_all(1)
	if filled:
		var rc := Palette.rarity_color(rarity)
		sb.border_color = rc
		sb.bg_color = Color("14110c").lerp(rc, 0.10)
		sb.shadow_color = Palette.with_alpha(rc, 0.4 * Palette.GLOW)
		sb.shadow_size = int(11 * Palette.GLOW)
	else:
		sb.border_color = Palette.IRON_EDGE
	return sb


## Inventory grid cell (.inv-cell). Hover handled by caller re-applying.
static func inv_cell_box(rarity: String = "", filled: bool = false, hover: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(3)
	if not filled:
		sb.bg_color = Color("110e09")
		sb.set_border_width_all(1)
		sb.border_color = Color(0, 0, 0, 0.55)
		return sb
	var rc := Palette.rarity_color(rarity)
	sb.bg_color = Color("14110c").lerp(rc, 0.16)
	sb.set_border_width_all(1)
	sb.border_color = rc.lerp(Color.BLACK, 0.3)
	if hover:
		sb.shadow_color = Palette.with_alpha(rc, 0.45 * Palette.GLOW)
		sb.shadow_size = int(12 * Palette.GLOW)
	return sb


## Pixel-art drop-slot StyleBox (kept for simple panels; prefer PixelSlot node).
static func pixel_slot_box(lit: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("16130e")
	sb.set_border_width_all(1)
	sb.border_color = Palette.GOLD_DIM if lit else Palette.TX_FAINT
	sb.set_corner_radius_all(3)
	if lit:
		sb.shadow_color = Palette.with_alpha(Palette.EMBER, 0.25 * Palette.GLOW)
		sb.shadow_size = int(10 * Palette.GLOW)
	return sb


## Small ember "+" affordance (.res-plus).
static func plus_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.EMBER
	sb.set_border_width_all(1)
	sb.border_color = Color("3a1d08")
	sb.set_corner_radius_all(3)
	sb.shadow_color = Palette.with_alpha(Palette.EMBER, 0.4 * Palette.GLOW)
	sb.shadow_size = int(8 * Palette.GLOW)
	return sb


## Role tag chip (.tag.role-*): tiny pixel-font outline chip.
static func make_role_tag(role: String, label: String) -> Control:
	var chip := PanelContainer.new()
	var c := Palette.role_color(role)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.25)
	sb.set_border_width_all(1)
	sb.border_color = c
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	sb.content_margin_top = 3
	sb.content_margin_bottom = 2
	chip.add_theme_stylebox_override("panel", sb)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := pixel_label(label.to_upper(), 8, c)
	chip.add_child(l)
	return chip


# =========================================================================
# Labels & misc
# =========================================================================

## READABILITY SCALE (design handoff v2, 2026-06: "every text is so small").
## All factory sizes are quoted at the ORIGINAL design scale; fs() lifts them
## to the readability scale the v2 handoff applied (~+5px, nothing below 11).
## Callers keep passing the old numbers — hierarchy is preserved, just larger.
static func fs(size: int) -> int:
	return maxi(11, size + 5)


## Display-font label (Spectral). Uppercase/letterspacing left to the caller.
static func display_label(text: String, size: int, color: Color, italic: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	var f := Fonts.display_italic() if italic else Fonts.display()
	if f != null:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", fs(size))
	l.add_theme_color_override("font_color", color)
	return l


## Pixel-font label (Silkscreen) — hotkeys, numerics, tickers.
static func pixel_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	var f := Fonts.pixel()
	if f != null:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", fs(size))
	l.add_theme_color_override("font_color", color)
	return l


## Body-font label (system UI face) — descriptions, sublabels.
static func body_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs(size))
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


## Thousands-grouped integer ("248910" → "248,910").
static func group_int(value: int) -> String:
	var s := str(absi(value))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" + out) if value < 0 else out
