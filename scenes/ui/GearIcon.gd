class_name GearIcon
extends Control
## Procedural equip-slot / item glyph — the icon that replaces the "48²" and
## slot-name PixelSlot placeholders so collected gear and weapons read at a
## glance. Pure _draw(): no texture import, crisp at any size, and recolored
## live by rarity. Sits inside a Style.slot_box() / inv_cell_box() frame.
##
##   GearIcon.new(GearIcon.kind_for_slot(item["slot"]), Palette.rarity_color(r))
##   GearIcon.new("sword", Palette.GOLD_DIM, true)   # ghost (empty slot)

var kind: String = "gem"
var color: Color = Color(0.86, 0.7, 0.4)
var ghost: bool = false


func _init(p_kind: String = "gem", p_color: Color = Color(0.86, 0.7, 0.4), p_ghost: bool = false) -> void:
	kind = p_kind
	color = p_color
	ghost = p_ghost


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


## Map an equip-slot / item-slot string ("Main Hand", "Ring II", …) to a glyph.
static func kind_for_slot(slot: String) -> String:
	match slot:
		"Helm": return "helm"
		"Amulet": return "amulet"
		"Body", "Chest": return "body"
		"Gloves": return "gloves"
		"Boots": return "boots"
		"Main Hand": return "sword"
		"Off Hand": return "shield"
		"Ring", "Ring I", "Ring II": return "ring"
		"Belt": return "belt"
		_: return "gem"


## Pick the glyph for an inventory item given its tab — equipment uses the slot
## glyph; consumables/materials/quest map their type ("Flask", "Meal", "Smithing"…)
## to a fitting icon so each item reads as what it is.
static func kind_for_item(it: Dictionary, tab: String) -> String:
	if tab == "equipment":
		return kind_for_slot(String(it.get("slot", "")))
	var t := String(it.get("t", "")).to_lower()
	match tab:
		"consumables":
			if t.contains("meal"): return "food"
			if t.contains("scroll"): return "scroll"
			return "flask"  # Flask / Tonic / draught
		"materials":
			if t.contains("smith"): return "ingot"
			if t.contains("relic"): return "relic"
			return "gem"  # Alchemy / Tailoring
		"quest":
			return "key"
	return "gem"


func _draw() -> void:
	var s := minf(size.x, size.y)
	if s <= 0.0:
		return
	var o := (size - Vector2(s, s)) * 0.5
	var col := Color(color, 0.42) if ghost else color
	var cut := Palette.BG_0
	var edge := col.darkened(0.5)
	var P := func(fx: float, fy: float) -> Vector2: return o + Vector2(fx, fy) * s
	match kind:
		"sword":
			_fill([P.call(0.5, 0.06), P.call(0.57, 0.5), P.call(0.5, 0.63), P.call(0.43, 0.5)], col, edge)
			_fill([P.call(0.30, 0.54), P.call(0.70, 0.54), P.call(0.70, 0.60), P.call(0.30, 0.60)], col, edge)
			_fill([P.call(0.46, 0.60), P.call(0.54, 0.60), P.call(0.54, 0.82), P.call(0.46, 0.82)], col, edge)
			draw_circle(P.call(0.5, 0.85), 0.05 * s, col)
		"shield":
			_fill([P.call(0.22, 0.16), P.call(0.78, 0.16), P.call(0.78, 0.46), P.call(0.5, 0.84), P.call(0.22, 0.46)], col, edge)
			if not ghost:
				draw_line(P.call(0.5, 0.18), P.call(0.5, 0.8), cut, maxf(1.0, 0.03 * s))
		"helm":
			_fill([P.call(0.32, 0.34), P.call(0.36, 0.26), P.call(0.64, 0.26), P.call(0.68, 0.34), P.call(0.68, 0.64), P.call(0.6, 0.76), P.call(0.4, 0.76), P.call(0.32, 0.64)], col, edge)
			if not ghost:
				_fill([P.call(0.37, 0.45), P.call(0.63, 0.45), P.call(0.63, 0.51), P.call(0.37, 0.51)], cut, cut)
				_fill([P.call(0.47, 0.51), P.call(0.53, 0.51), P.call(0.53, 0.66), P.call(0.47, 0.66)], cut, cut)
		"body":
			_fill([P.call(0.3, 0.3), P.call(0.42, 0.3), P.call(0.5, 0.4), P.call(0.58, 0.3), P.call(0.7, 0.3), P.call(0.73, 0.74), P.call(0.27, 0.74)], col, edge)
			if not ghost:
				draw_line(P.call(0.5, 0.42), P.call(0.5, 0.74), cut, maxf(1.0, 0.025 * s))
		"gloves":
			_fill([P.call(0.35, 0.44), P.call(0.65, 0.44), P.call(0.66, 0.75), P.call(0.34, 0.75)], col, edge)
			for fx in [0.41, 0.5, 0.59]:
				draw_circle(P.call(fx, 0.44), 0.06 * s, col)
			draw_circle(P.call(0.32, 0.56), 0.06 * s, col)
		"boots":
			_fill([P.call(0.36, 0.22), P.call(0.5, 0.22), P.call(0.5, 0.6), P.call(0.74, 0.6), P.call(0.74, 0.78), P.call(0.36, 0.78)], col, edge)
		"belt":
			_fill([P.call(0.18, 0.43), P.call(0.82, 0.43), P.call(0.82, 0.57), P.call(0.18, 0.57)], col, edge)
			if not ghost:
				_fill([P.call(0.43, 0.39), P.call(0.57, 0.39), P.call(0.57, 0.61), P.call(0.43, 0.61)], cut, cut)
				_fill([P.call(0.46, 0.42), P.call(0.54, 0.42), P.call(0.54, 0.58), P.call(0.46, 0.58)], col, col)
		"amulet":
			draw_line(P.call(0.33, 0.26), P.call(0.5, 0.55), col, maxf(1.5, 0.045 * s))
			draw_line(P.call(0.67, 0.26), P.call(0.5, 0.55), col, maxf(1.5, 0.045 * s))
			_fill([P.call(0.5, 0.5), P.call(0.62, 0.64), P.call(0.5, 0.82), P.call(0.38, 0.64)], col, edge)
		"ring":
			draw_arc(P.call(0.5, 0.6), 0.2 * s, 0.0, TAU, 40, col, maxf(2.0, 0.08 * s))
			_fill([P.call(0.5, 0.26), P.call(0.6, 0.4), P.call(0.5, 0.5), P.call(0.4, 0.4)], col, edge)
		"relic":
			draw_circle(P.call(0.5, 0.55), 0.22 * s, col)
			if not ghost:
				_fill([P.call(0.5, 0.43), P.call(0.61, 0.64), P.call(0.39, 0.64)], cut, cut)
		"flask":  # Flask / Tonic / potion
			_fill([P.call(0.44, 0.13), P.call(0.56, 0.13), P.call(0.56, 0.2), P.call(0.44, 0.2)], col, edge)
			_fill([P.call(0.45, 0.2), P.call(0.55, 0.2), P.call(0.55, 0.4), P.call(0.45, 0.4)], col, edge)
			draw_circle(P.call(0.5, 0.62), 0.22 * s, col)
			if not ghost:
				draw_line(P.call(0.34, 0.6), P.call(0.66, 0.6), edge, maxf(1.0, 0.02 * s))
		"food":  # Meal — bowl of food
			_fill([P.call(0.26, 0.5), P.call(0.74, 0.5), P.call(0.66, 0.74), P.call(0.34, 0.74)], col, edge)
			_fill([P.call(0.3, 0.5), P.call(0.4, 0.42), P.call(0.5, 0.4), P.call(0.6, 0.42), P.call(0.7, 0.5)], col, edge)
			if not ghost:
				draw_line(P.call(0.22, 0.5), P.call(0.78, 0.5), col, maxf(1.5, 0.04 * s))
		"scroll":  # rolled parchment
			_fill([P.call(0.34, 0.3), P.call(0.66, 0.3), P.call(0.66, 0.7), P.call(0.34, 0.7)], col, edge)
			_fill([P.call(0.3, 0.24), P.call(0.7, 0.24), P.call(0.7, 0.32), P.call(0.3, 0.32)], col, edge)
			_fill([P.call(0.3, 0.68), P.call(0.7, 0.68), P.call(0.7, 0.76), P.call(0.3, 0.76)], col, edge)
			if not ghost:
				draw_line(P.call(0.4, 0.44), P.call(0.6, 0.44), cut, maxf(1.0, 0.02 * s))
				draw_line(P.call(0.4, 0.52), P.call(0.6, 0.52), cut, maxf(1.0, 0.02 * s))
		"key":  # quest key
			draw_arc(P.call(0.5, 0.3), 0.13 * s, 0.0, TAU, 28, col, maxf(2.0, 0.07 * s))
			_fill([P.call(0.47, 0.4), P.call(0.53, 0.4), P.call(0.53, 0.8), P.call(0.47, 0.8)], col, edge)
			_fill([P.call(0.53, 0.64), P.call(0.62, 0.64), P.call(0.62, 0.7), P.call(0.53, 0.7)], col, edge)
			_fill([P.call(0.53, 0.73), P.call(0.64, 0.73), P.call(0.64, 0.79), P.call(0.53, 0.79)], col, edge)
		"ingot":  # metal bar (smithing material)
			_fill([P.call(0.2, 0.46), P.call(0.8, 0.46), P.call(0.72, 0.66), P.call(0.28, 0.66)], col, edge)
			_fill([P.call(0.28, 0.46), P.call(0.72, 0.46), P.call(0.64, 0.38), P.call(0.36, 0.38)], col.lightened(0.12), edge)
		_:  # "gem" / crafting material
			_fill([P.call(0.5, 0.22), P.call(0.74, 0.46), P.call(0.5, 0.8), P.call(0.26, 0.46)], col, edge)
			if not ghost:
				draw_line(P.call(0.26, 0.46), P.call(0.74, 0.46), edge, maxf(1.0, 0.02 * s))
				draw_line(P.call(0.5, 0.22), P.call(0.5, 0.8), edge, maxf(1.0, 0.02 * s))


## Filled simple polygon with an optional crisp outline.
func _fill(pts: Array, fill: Color, outline: Color) -> void:
	var pv := PackedVector2Array(pts)
	draw_colored_polygon(pv, fill)
	if outline != fill:
		var loop := pv.duplicate()
		loop.append(pv[0])
		draw_polyline(loop, outline, 1.0, true)
