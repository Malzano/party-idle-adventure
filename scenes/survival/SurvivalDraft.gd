extends "res://scenes/camp/ModalShell.gd"
## STAGE-CLEAR enhancement draft: three cards, pick one. Vampire-survivors style.
## Not dismissable — the player MUST choose (scrim/Esc/✕ are no-ops here), so the
## run can't be left in limbo. Emits `chosen(id)` then closes.

signal chosen(id: String)

var choices: Array = []   # [{id, name, desc, kind}]
var stage_cleared: int = 1
var boss_reward := false
var _picked := false


func _build_body(body: VBoxContainer) -> void:
	var sub_text := "A world boss falls — claim a reward enhancement" if boss_reward else "Stage %d cleared — choose an enhancement" % stage_cleared
	var sub := Style.body_label(sub_text, 14, Palette.TX_MUTE)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(sub)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(row)
	for c in choices:
		row.add_child(_make_card(c as Dictionary))


func _make_card(c: Dictionary) -> Control:
	var kind := String(c.get("kind", "power"))
	var tint := {"shape": Palette.CYAN_BRIGHT, "power": Palette.EMBER_BRIGHT, "util": Palette.GOLD_BRIGHT}.get(kind, Palette.EMBER_BRIGHT) as Color

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(264, 250)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("17120c")
	sb.set_border_width_all(1)
	sb.border_color = tint
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 18
	sb.content_margin_bottom = 16
	card.add_theme_stylebox_override("panel", sb)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	card.add_child(col)

	var chip := Style.pixel_label(kind.to_upper(), 8, tint)
	col.add_child(chip)
	var nm := Style.display_label(String(c["name"]), 21, Palette.GOLD_BRIGHT, true)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(nm)
	var desc := Style.body_label(String(c["desc"]), 13, Palette.TX_MUTE)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(desc)

	var take := Style.make_button("CHOOSE", "ember", 12)
	take.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	take.pressed.connect(func() -> void: _pick(String(c["id"])))
	col.add_child(take)
	return card


func _pick(id: String) -> void:
	if _picked:
		return
	_picked = true
	chosen.emit(id)
	closed.emit()
	queue_free()


## Block the inherited scrim/Esc/✕ closers — a choice is mandatory.
func request_close() -> void:
	pass
