class_name ScreenBase
extends Control
## Base for the three top-level screens (Camp / Fight / Hero).
##
## For the skeleton each screen is a Grimhollow-styled placeholder: a screen-pad
## layout (.screen-pad — 84px top to clear the resource strip), a serif display
## title with a hotkey chip, and a beveled-iron "Planned" panel listing the
## sub-features CLAUDE.md §5 calls for. Real content replaces this milestone by
## milestone.

func build_placeholder(title: String, subtitle: String, sections: PackedStringArray, hotkey: String = "") -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var pad := MarginContainer.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 22)
	pad.add_theme_constant_override("margin_right", 22)
	pad.add_theme_constant_override("margin_top", 84)
	pad.add_theme_constant_override("margin_bottom", 22)
	add_child(pad)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	pad.add_child(column)

	# Title row: serif display + hotkey chip.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	var heading := Style.display_label(title, 30, Palette.GOLD_BRIGHT, true)
	header.add_child(heading)
	if hotkey != "":
		header.add_child(_keycap(hotkey))
	column.add_child(header)

	var sub := Label.new()
	sub.text = subtitle
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", Palette.TX_DIM)
	column.add_child(sub)

	column.add_child(Style.rune_divider())

	# "Planned" panel — beveled iron frame with a rune-divider heading.
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Style.panel_box())
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	column.add_child(panel)

	var panel_col := VBoxContainer.new()
	panel_col.add_theme_constant_override("separation", 0)
	panel.add_child(panel_col)

	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", Style.head_box())
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 10)
	head_row.add_child(_ember_mark(8))
	head_row.add_child(Style.display_label("PLANNED", 14, Palette.GOLD))
	head.add_child(head_row)
	panel_col.add_child(head)

	var body := MarginContainer.new()
	body.add_theme_constant_override("margin_left", 16)
	body.add_theme_constant_override("margin_right", 16)
	body.add_theme_constant_override("margin_top", 14)
	body.add_theme_constant_override("margin_bottom", 16)
	panel_col.add_child(body)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 9)
	body.add_child(list)

	for section in sections:
		list.add_child(_section_row(section))


func _keycap(text: String) -> Control:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", Style.key_box())
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var label := Style.pixel_label(text, 10, Palette.GOLD_BRIGHT)
	chip.add_child(label)
	return chip


func _section_row(text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(_ember_mark(7))
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Palette.TX)
	row.add_child(label)
	return row


## A small ember diamond marker (rotated square), glyph-independent.
func _ember_mark(px: float) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(px + 4, px + 4)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sq := ColorRect.new()
	sq.color = Palette.EMBER
	sq.size = Vector2(px, px)
	sq.pivot_offset = Vector2(px * 0.5, px * 0.5)
	sq.position = Vector2((px + 4) * 0.5 - px * 0.5, (px + 4) * 0.5 - px * 0.5)
	sq.rotation = deg_to_rad(45)
	sq.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(sq)
	return holder

