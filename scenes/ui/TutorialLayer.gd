extends Control
## The visual layer for the first-session spotlight tutorial (see TutorialOverlay).
## A full design-space (1920×1080) Control mounted into the active window's stage.
## It dims everything with click-swallowing "bands", punches a spotlight ring
## around the target rect(s), draws an optional drag arrow, and shows the wording
## box (step / progress / headline / body / Skip + Next-or-hint) with a diamond
## tail pointing at the spotlight.
##
## Ported 1:1 from the Claude Design handoff (tutorial.jsx / tutorial.css), adapted
## to Godot Controls. TutorialOverlay drives it via render(); it emits next/skip.

signal next_pressed
signal skip_pressed

const _SCRIM := Color(8.0 / 255.0, 7.0 / 255.0, 5.0 / 255.0)  # rgba(8,7,5,a)
const _PAD := 12.0
const _BW := 376.0
const _BW_INTRO := 432.0

var _bands: Array[ColorRect] = []
var _ring: Panel
var _sec: Panel
var _arrow: Control
var _box: PanelContainer
var _tail: Panel

var _step_lbl: Label
var _prog_track: Panel
var _prog_fill: ColorRect
var _head: Label
var _body: Label
var _skip_btn: Button
var _next_btn: Button
var _hint: Label

var _mode := "next"
var _arrow_from: Rect2
var _arrow_to: Rect2
var _arrow_on := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 4096
	_build()


func _build() -> void:
	# Four dim shutters around the spotlight; STOP filter swallows clicks on the
	# darkened area (the hole between them passes clicks to the real control).
	for i in 4:
		var band := ColorRect.new()
		band.color = Palette.with_alpha(_SCRIM, 0.78)
		band.mouse_filter = Control.MOUSE_FILTER_STOP
		band.visible = false
		add_child(band)
		_bands.append(band)

	_ring = Panel.new()
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.visible = false
	_ring.add_theme_stylebox_override("panel", _ring_box(true))
	add_child(_ring)
	# Gentle ember pulse on the spotlight ring.
	var tw := create_tween().set_loops()
	tw.tween_property(_ring, "modulate:a", 0.72, 1.05).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_ring, "modulate:a", 1.0, 1.05).set_trans(Tween.TRANS_SINE)

	_sec = Panel.new()
	_sec.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sec.visible = false
	_sec.add_theme_stylebox_override("panel", _ring_box(false))
	add_child(_sec)

	_arrow = Control.new()
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_arrow.draw.connect(_draw_arrow)
	add_child(_arrow)

	_build_box()


func _ring_box(primary: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.set_border_width_all(2)
	sb.border_color = Palette.EMBER_BRIGHT if primary else Palette.EMBER
	sb.set_corner_radius_all(8)
	sb.shadow_color = Palette.with_alpha(Palette.EMBER_BRIGHT, 0.5 if primary else 0.35)
	sb.shadow_size = int((24 if primary else 16) * Palette.GLOW)
	return sb


func _build_box() -> void:
	_box = PanelContainer.new()
	_box.mouse_filter = Control.MOUSE_FILTER_STOP
	_box.visible = false
	var bx := StyleBoxFlat.new()
	bx.bg_color = Palette.BG_3
	bx.set_border_width_all(1)
	bx.border_color = Palette.IRON_EDGE
	bx.set_corner_radius_all(8)
	bx.shadow_color = Color(0, 0, 0, 0.7)
	bx.shadow_size = 22
	bx.shadow_offset = Vector2(0, 14)
	_box.add_theme_stylebox_override("panel", bx)
	add_child(_box)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 15)
	_box.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 7)
	margin.add_child(col)

	_step_lbl = Style.pixel_label("STEP 1 / 14", 6, Palette.TX_MUTE)
	col.add_child(_step_lbl)

	_prog_track = Panel.new()
	_prog_track.custom_minimum_size = Vector2(0, 4)
	_prog_track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pt := StyleBoxFlat.new()
	pt.bg_color = Palette.BG_4
	pt.set_corner_radius_all(2)
	_prog_track.add_theme_stylebox_override("panel", pt)
	col.add_child(_prog_track)
	_prog_fill = ColorRect.new()
	_prog_fill.color = Palette.EMBER_BRIGHT
	_prog_fill.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_prog_fill.offset_right = 0
	_prog_track.add_child(_prog_fill)

	_head = Style.display_label("Headline", 17, Palette.GOLD_BRIGHT, true)
	_head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_head)

	_body = Style.body_label("Body copy.", 11, Palette.TX)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_body)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	foot.custom_minimum_size = Vector2(0, 8)
	col.add_child(foot)

	_skip_btn = Style.make_button("Skip tour", "ghost", 9)
	_skip_btn.pressed.connect(func() -> void: skip_pressed.emit())
	foot.add_child(_skip_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(spacer)

	_hint = Style.pixel_label("▸ Do it to continue", 7, Palette.EMBER_BRIGHT)
	_hint.visible = false
	foot.add_child(_hint)

	_next_btn = Style.make_button("Next ›", "ember", 10)
	_next_btn.pressed.connect(func() -> void: next_pressed.emit())
	foot.add_child(_next_btn)

	_tail = Panel.new()
	_tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tail.custom_minimum_size = Vector2(14, 14)
	_tail.size = Vector2(14, 14)
	_tail.pivot_offset = Vector2(7, 7)
	_tail.rotation = deg_to_rad(45)
	_tail.visible = false
	var tb := StyleBoxFlat.new()
	tb.bg_color = Palette.BG_3
	tb.set_border_width_all(1)
	tb.border_color = Palette.IRON_EDGE
	_tail.add_theme_stylebox_override("panel", tb)
	add_child(_tail)


## Configure for the current step. `state` keys:
##  alpha:float, hole:Variant(Rect2|null), sec:Variant(Rect2|null), arrow:bool,
##  prefer:String, headline, body, mode, cta, hint, skip_label, big:bool,
##  step_idx:int, total:int
func render(state: Dictionary) -> void:
	_mode = String(state.get("mode", "next"))
	var alpha := float(state.get("alpha", 0.78))
	var hole: Variant = state.get("hole", null)
	var sec: Variant = state.get("sec", null)

	# --- content (set first so the box measures at the right height) ---
	var total := int(state.get("total", 14))
	var idx := int(state.get("step_idx", 0))
	_step_lbl.text = "STEP %d / %d" % [idx + 1, total]
	var big := bool(state.get("big", false))
	_head.add_theme_font_size_override("font_size", Style.fs(23 if big else 17))
	_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if big else HORIZONTAL_ALIGNMENT_LEFT
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if big else HORIZONTAL_ALIGNMENT_LEFT
	_head.text = String(state.get("headline", ""))
	_body.text = String(state.get("body", ""))
	_skip_btn.text = String(state.get("skip_label", "Skip tour")).to_upper()
	if _mode == "do":
		_hint.visible = true
		_next_btn.visible = false
		_hint.text = String(state.get("hint", "▸ Do it to continue"))
	else:
		_hint.visible = false
		_next_btn.visible = true
		_next_btn.text = String(state.get("cta", "Next ›")).to_upper()

	for b in _bands:
		b.color = Palette.with_alpha(_SCRIM, alpha)

	var bw := _BW_INTRO if big else _BW
	# Pin the wrapping width on the autowrap labels (box has 18px L/R margins).
	# Without this, get_combined_minimum_size wraps the body one-word-per-line and
	# the box balloons to full screen height.
	var content_w := bw - 36.0
	_head.custom_minimum_size.x = content_w
	_body.custom_minimum_size.x = content_w
	_box.custom_minimum_size = Vector2(bw, 0)
	_prog_fill.offset_right = content_w * (float(idx + 1) / float(total))

	# --- geometry ---
	# Labels are width-constrained above, so min height is the correctly wrapped
	# height and reads synchronously. Cap defensively so the box can never balloon.
	var bh := clampf(_box.get_combined_minimum_size().y, 150.0, 560.0)
	var hole_rect: Rect2 = hole if hole is Rect2 else Rect2()
	var has_hole := hole is Rect2

	# bands around the padded hole (or one full-screen band)
	if has_hole:
		var hx := hole_rect.position.x - _PAD
		var hy := hole_rect.position.y - _PAD
		var hw := hole_rect.size.x + 2.0 * _PAD
		var hh := hole_rect.size.y + 2.0 * _PAD
		_place_band(0, 0, 0, 1920, maxf(0, hy))
		_place_band(1, 0, hy + hh, 1920, maxf(0, 1080 - (hy + hh)))
		_place_band(2, 0, hy, maxf(0, hx), hh)
		_place_band(3, hx + hw, hy, maxf(0, 1920 - (hx + hw)), hh)
		_ring.visible = true
		_ring.position = Vector2(hx, hy)
		_ring.size = Vector2(hw, hh)
	else:
		_place_band(0, 0, 0, 1920, 1080)
		for i in [1, 2, 3]:
			_bands[i].visible = false
		_ring.visible = false

	# secondary ring (drag-target)
	if sec is Rect2:
		var sr: Rect2 = sec
		_sec.visible = true
		_sec.position = sr.position - Vector2(_PAD, _PAD)
		_sec.size = sr.size + Vector2(2.0 * _PAD, 2.0 * _PAD)
	else:
		_sec.visible = false

	# drag arrow (step 11)
	_arrow_on = bool(state.get("arrow", false)) and has_hole and sec is Rect2
	if _arrow_on:
		_arrow_from = hole_rect
		_arrow_to = sec
	_arrow.queue_redraw()

	# wording box placement (auto-flipping, safe-area clamped)
	var prefer := String(state.get("prefer", "below"))
	var p := _place(hole if has_hole else null, prefer, bw, bh)
	_box.visible = true
	_box.position = Vector2(float(p["x"]), float(p["y"]))
	_box.size = Vector2(bw, bh)

	# tail
	var tail: Variant = p["tail"]
	if tail == null:
		_tail.visible = false
	else:
		_tail.visible = true
		var side := String(tail["side"])
		var pos := float(tail["pos"])
		var bp := _box.position
		match side:
			"top":
				_tail.position = bp + Vector2(pos - 7, -8)
			"bottom":
				_tail.position = bp + Vector2(pos - 7, bh - 6)
			"left":
				_tail.position = bp + Vector2(-8, pos - 7)
			_:
				_tail.position = bp + Vector2(bw - 6, pos - 7)


func _unhandled_key_input(event: InputEvent) -> void:
	if not _box.visible:
		return
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	# Esc skips the tour. accept_event() consumes it so the popup window's
	# Esc-to-close handler (WindowManager._PopupKeys) can't tear down the window
	# hosting the spotlight instead.
	if k.keycode == KEY_ESCAPE:
		accept_event()
		skip_pressed.emit()
	elif (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER) and _mode != "do":
		accept_event()
		next_pressed.emit()


func hide_all() -> void:
	for b in _bands:
		b.visible = false
	_ring.visible = false
	_sec.visible = false
	_box.visible = false
	_tail.visible = false
	_arrow_on = false
	_arrow.queue_redraw()


func _place_band(i: int, x: float, y: float, w: float, h: float) -> void:
	var b := _bands[i]
	b.visible = w > 0.5 and h > 0.5
	b.position = Vector2(x, y)
	b.size = Vector2(w, h)


func _draw_arrow() -> void:
	if not _arrow_on:
		return
	var a := Vector2(_arrow_from.position.x, _arrow_from.position.y + _arrow_from.size.y / 2.0)
	var b := Vector2(_arrow_to.position.x + _arrow_to.size.x, _arrow_to.position.y + _arrow_to.size.y / 2.0)
	var c1 := a + Vector2(-120, -40)
	var c2 := b + Vector2(120, -30)
	var pts := PackedVector2Array()
	var steps := 28
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		pts.append(a.bezier_interpolate(c1, c2, b, t))
	# dashed
	for i in range(0, pts.size() - 1, 2):
		_arrow.draw_line(pts[i], pts[i + 1], Palette.EMBER_BRIGHT, 3.0, true)
	# arrowhead at b
	var dir := (b - c2).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var tip := b
	_arrow.draw_line(tip, tip - dir * 14 + perp * 8, Palette.EMBER_BRIGHT, 3.0, true)
	_arrow.draw_line(tip, tip - dir * 14 - perp * 8, Palette.EMBER_BRIGHT, 3.0, true)


## Ported placement: prefer side, auto-flip to fit, clamp to a 46px safe-area.
func _place(hole: Variant, prefer: String, bw: float, bh: float) -> Dictionary:
	var inset := 46.0
	var gap := 20.0
	var w := 1920.0
	var h := 1080.0
	if not (hole is Rect2) or prefer == "center":
		return {"x": (w - bw) / 2.0, "y": (h - bh) / 2.0, "tail": null}
	var hr: Rect2 = hole
	var cx := hr.position.x + hr.size.x / 2.0
	var cy := hr.position.y + hr.size.y / 2.0
	var cand := {
		"below": {"x": clampf(cx - bw / 2.0, inset, w - inset - bw), "y": hr.position.y + hr.size.y + gap, "fit": hr.position.y + hr.size.y + gap + bh <= h - inset, "tail": "top"},
		"above": {"x": clampf(cx - bw / 2.0, inset, w - inset - bw), "y": hr.position.y - gap - bh, "fit": hr.position.y - gap - bh >= inset, "tail": "bottom"},
		"right": {"x": hr.position.x + hr.size.x + gap, "y": clampf(cy - bh / 2.0, inset, h - inset - bh), "fit": hr.position.x + hr.size.x + gap + bw <= w - inset, "tail": "left"},
		"left": {"x": hr.position.x - gap - bw, "y": clampf(cy - bh / 2.0, inset, h - inset - bh), "fit": hr.position.x - gap - bw >= inset, "tail": "right"},
	}
	var pick: Dictionary = {}
	for k in [prefer, "below", "above", "right", "left"]:
		if cand.has(k) and bool(cand[k]["fit"]):
			pick = cand[k]
			break
	if pick.is_empty():
		pick = cand.get(prefer, cand["below"])
		pick["x"] = clampf(float(pick["x"]), inset, w - inset - bw)
		pick["y"] = clampf(float(pick["y"]), inset, h - inset - bh)
	var side := String(pick["tail"])
	var tail: Dictionary
	if side == "top" or side == "bottom":
		tail = {"side": side, "pos": clampf(cx - float(pick["x"]), 20, bw - 20)}
	else:
		tail = {"side": side, "pos": clampf(cy - float(pick["y"]), 20, bh - 20)}
	return {"x": float(pick["x"]), "y": float(pick["y"]), "tail": tail}
