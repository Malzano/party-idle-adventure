extends RefCounted
## Camp visual-FX toolkit: radial-gradient rendering, pulsing glow ellipses,
## glowing status dots, and decorative corner rivets. Shared by the camp scene
## and its building modals. No class_name — load via
## preload("res://scenes/camp/CampFx.gd").


## Vertical two-color gradient rectangle (per-vertex colors).
static func vgrad(ci: CanvasItem, rect: Rect2, top: Color, bottom: Color) -> void:
	ci.draw_polygon(
		PackedVector2Array([
			rect.position,
			rect.position + Vector2(rect.size.x, 0.0),
			rect.end,
			rect.position + Vector2(0.0, rect.size.y),
		]),
		PackedColorArray([top, top, bottom, bottom]))


## CSS radial-gradient approximation. stops: [[t, Color], ...], t 0..1 sorted.
static func radial(ci: CanvasItem, center: Vector2, radius: Vector2, stops: Array) -> void:
	Glow.render(ci, center, radius, stops)


## Radial-gradient ellipse filling this control; optional opacity pulse
## (the design's pulse-glow keyframes: amin ↔ amax over period seconds).
class Glow:
	extends Control

	var stops: Array = []
	var period: float = 0.0
	var amin: float = 0.5
	var amax: float = 1.0
	## Ellipse center / radii as fractions of the control size.
	var center_frac := Vector2(0.5, 0.5)
	var radius_frac := Vector2(0.5, 0.5)

	var _t: float = 0.0

	func _init(p_stops: Array, p_period: float = 0.0, p_min: float = 0.5, p_max: float = 1.0) -> void:
		stops = p_stops
		period = p_period
		amin = p_min
		amax = p_max
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		_t = randf() * maxf(period, 1.0)
		set_process(period > 0.0)
		resized.connect(queue_redraw)

	func _process(delta: float) -> void:
		_t += delta
		var f := 0.5 - 0.5 * cos(TAU * _t / period)
		modulate.a = lerpf(amin, amax, f)

	func _draw() -> void:
		render(self, size * center_frac, size * radius_frac, stops)

	## Draw a radial gradient as triangle/quad bands with per-vertex colors.
	static func render(ci: CanvasItem, center: Vector2, radius: Vector2, stop_list: Array) -> void:
		const SEGS := 40
		for s in range(stop_list.size() - 1):
			var t0 := float(stop_list[s][0])
			var c0: Color = stop_list[s][1]
			var t1 := float(stop_list[s + 1][0])
			var c1: Color = stop_list[s + 1][1]
			if t1 <= t0:
				continue
			for i in SEGS:
				var a0 := TAU * float(i) / float(SEGS)
				var a1 := TAU * float(i + 1) / float(SEGS)
				var p10 := center + Vector2(cos(a0), sin(a0)) * radius * t1
				var p11 := center + Vector2(cos(a1), sin(a1)) * radius * t1
				if t0 <= 0.0:
					ci.draw_polygon(
						PackedVector2Array([center, p10, p11]),
						PackedColorArray([c0, c1, c1]))
				else:
					var p00 := center + Vector2(cos(a0), sin(a0)) * radius * t0
					var p01 := center + Vector2(cos(a1), sin(a1)) * radius * t0
					ci.draw_polygon(
						PackedVector2Array([p00, p10, p11, p01]),
						PackedColorArray([c0, c1, c1, c0]))


## Glowing circular pip (.ce-dot / .gr-row .dot).
class Dot:
	extends Control

	var color := Color.WHITE
	var glow := true

	func _init(d: float, c: Color, g: bool = true) -> void:
		color = c
		glow = g
		custom_minimum_size = Vector2(d, d)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		if glow:
			draw_circle(c, r * 2.2, Palette.with_alpha(color, 0.10 * Palette.GLOW))
			draw_circle(c, r * 1.6, Palette.with_alpha(color, 0.18 * Palette.GLOW))
		draw_circle(c, r, color)


## Corner rivets for .frame.riveted panels (top-left + top-right).
class Rivets:
	extends Control

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		if size.x < 40.0:
			return
		for x in [10.0, size.x - 10.0]:
			draw_circle(Vector2(x, 10.0), 3.5, Color.BLACK)
			draw_circle(Vector2(x, 10.0), 3.0, Color("4a4234"))
			draw_circle(Vector2(x - 1.0, 9.0), 1.2, Color(1, 1, 1, 0.15))
