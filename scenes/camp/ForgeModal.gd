extends "res://scenes/camp/ModalShell.gd"
## CRAFTING HOUSE modal (camp.jsx ForgeModal): anvil row (source slot at the
## current forge level → glowing arrow → +N+1 preview) over a warm radial,
## upgrade-stats inset (current → next, scaled by forge.stat_growth), and the
## material/gold cost row. Upgrade rolls GameState.try_forge_upgrade; every
## number comes from Balance + PlayerStats.forged_weapon_stats(). Enter
## triggers the upgrade.

var _rng := RandomNumberGenerator.new()

var _upgrade_btn: Button
var _src_tag: Label
var _dst_tag: Label
var _stats_col: VBoxContainer
var _gold_lbl: Label
var _iron_qty: Label
var _iron_have: Label
var _dust_qty: Label
var _dust_have: Label
var _result_lbl: Label


func _init() -> void:
	modal_title = "Crafting House"
	modal_width = 900.0
	body_separation = 18
	_rng.randomize()


func _build_body(body: VBoxContainer) -> void:
	body.add_child(_build_anvil())
	body.add_child(_build_stats())
	body.add_child(_build_cost())
	_result_lbl = Style.display_label("", 13, Palette.GOLD_BRIGHT, true)
	_result_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_lbl.visible = false
	body.add_child(_result_lbl)
	EventBus.currencies_changed.connect(_refresh_all)
	_refresh_all()


func _exit_tree() -> void:
	if EventBus.currencies_changed.is_connected(_refresh_all):
		EventBus.currencies_changed.disconnect(_refresh_all)


func _on_modal_key(keycode: Key) -> bool:
	if keycode == KEY_ENTER or keycode == KEY_KP_ENTER:
		if not _upgrade_btn.disabled:
			_do_upgrade()
		return true
	return false


# =========================================================================
# Anvil row (.forge-anvil)
# =========================================================================

func _build_anvil() -> Control:
	var anvil := Control.new()
	anvil.custom_minimum_size = Vector2(0, 170)
	anvil.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var wash := _FX.Glow.new(
		[[0.0, Palette.with_alpha(Palette.EMBER, 0.08)], [1.0, Palette.with_alpha(Palette.EMBER, 0.0)]])
	wash.center_frac = Vector2(0.5, 0.4)
	wash.radius_frac = Vector2(0.6, 1.0)
	anvil.add_child(wash)
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	anvil.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	center.add_child(row)

	_src_tag = Style.pixel_label("+%d" % GameState.forge_level, 11, Palette.GOLD_BRIGHT)
	row.add_child(_forge_slot("epic", "96²\nweapon", _src_tag, _src_tip))

	var arrow := Style.body_label("→", 30, Palette.EMBER)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	arrow.add_theme_color_override("font_shadow_color", Palette.with_alpha(Palette.EMBER, 0.5))
	arrow.add_theme_constant_override("shadow_outline_size", int(10 * Palette.GLOW))
	row.add_child(arrow)

	_dst_tag = Style.pixel_label("+%d" % (GameState.forge_level + 1), 11, Palette.GOLD_BRIGHT)
	row.add_child(_forge_slot("legendary", "96²\nnext preview", _dst_tag, null))
	return anvil


## Live tooltip for the source weapon: forge-scaled stat pairs.
func _src_tip() -> Dictionary:
	return {
		"name": "Cindergrip Maul",
		"type": "Two-Handed · Epic · +%d" % GameState.forge_level,
		"rarity": "epic",
		"stats": PlayerStats.forged_weapon_stats(),
		"flavor": "Forged in the last ember of a dead star.",
	}


## 130² rarity-framed forge slot with an inset pixel sprite and a +N level tag.
func _forge_slot(rar: String, sprite_label: String, tag: Label, tip: Variant) -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(130, 130)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var frame := Panel.new()
	frame.add_theme_stylebox_override("panel", Style.slot_box(rar, true))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var ps := PixelSlot.new(sprite_label, true)
	slot.add_child(ps)
	ps.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ps.offset_left = 4
	ps.offset_top = 4
	ps.offset_right = -4
	ps.offset_bottom = -4

	tag.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	tag.add_theme_constant_override("shadow_offset_y", 1)
	slot.add_child(tag)
	tag.resized.connect(func() -> void:
		tag.position = Vector2(130.0 - 6.0 - tag.size.x, 130.0 - 4.0 - tag.size.y))

	if tip != null:
		Tip.attach(slot, tip)
		slot.mouse_default_cursor_shape = Control.CURSOR_HELP
	return slot


# =========================================================================
# Stats inset (.forge-stats) — current → next per forged stat pair
# =========================================================================

func _build_stats() -> Control:
	var panel := PanelContainer.new()
	var sb := Style.inset_box(4)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", sb)
	_stats_col = VBoxContainer.new()
	_stats_col.add_theme_constant_override("separation", 10)
	panel.add_child(_stats_col)
	return panel


func _refresh_stats() -> void:
	for child in _stats_col.get_children():
		_stats_col.remove_child(child)
		child.queue_free()
	var growth := Balance.num("forge.stat_growth", 1.13)
	for pair in PlayerStats.forged_weapon_stats():
		var cur := String(pair[1])
		_stats_col.add_child(_fs_row(String(pair[0]),
			[[cur, Palette.TX], [" → %s" % _scale_text(cur, growth), Palette.R_UNCOMMON]]))
	_stats_col.add_child(_fs_row("Success rate",
		[["%d%%" % roundi(Balance.num("forge.success_rate", 0.82) * 100.0), Palette.CYAN_BRIGHT]]))


func _fs_row(label: String, parts: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	var lbl := Style.body_label(label, 14, Palette.TX_DIM)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	for part: Array in parts:
		row.add_child(Style.body_label(String(part[0]), 14, part[1]))
	return row


## Scales "470–664" / "+72" / "+8.5%" value text by [param mult].
func _scale_text(text: String, mult: float) -> String:
	var range_re := RegEx.new()
	range_re.compile(r"^(\d+(?:\.\d+)?)\s*[–-]\s*(\d+(?:\.\d+)?)$")
	var rm := range_re.search(text)
	if rm != null:
		return "%d–%d" % [int(float(rm.get_string(1)) * mult), int(float(rm.get_string(2)) * mult)]
	var re := RegEx.new()
	re.compile(r"^([+\-]?)(\d+(?:\.\d+)?)(%?)$")
	var m := re.search(text)
	if m == null:
		return text
	var v := float(m.get_string(2)) * mult
	if m.get_string(3) == "%":
		return "%s%.1f%%" % [m.get_string(1), v]
	return "%s%d" % [m.get_string(1), int(v)]


# =========================================================================
# Cost row (.forge-cost)
# =========================================================================

func _build_cost() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	var iron := _material_item("32²", false, {"name": "Iron Ingot", "type": "Material", "rarity": "common"})
	_iron_qty = Style.pixel_label("", 12, Palette.TX_DIM)
	_iron_qty.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	iron.add_child(_iron_qty)
	_iron_have = Style.body_label("", 10, Palette.TX_MUTE)
	_iron_have.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	iron.add_child(_iron_have)
	row.add_child(iron)

	var dust := _material_item("32²", true, {"name": "Ember Dust", "type": "Material · Rare", "rarity": "rare"})
	_dust_qty = Style.pixel_label("", 12, Palette.TX_DIM)
	_dust_qty.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dust.add_child(_dust_qty)
	_dust_have = Style.body_label("", 10, Palette.TX_MUTE)
	_dust_have.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dust.add_child(_dust_have)
	row.add_child(dust)

	var gold := VBoxContainer.new()
	gold.add_theme_constant_override("separation", 0)
	gold.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_gold_lbl = Style.pixel_label("", 12, Palette.GOLD_BRIGHT)
	gold.add_child(_gold_lbl)
	gold.add_child(Style.body_label("GOLD", 9, Palette.TX_FAINT))
	row.add_child(gold)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	_upgrade_btn = Style.make_button("Upgrade   ↵", "ember")
	_upgrade_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_upgrade_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_upgrade_btn.pressed.connect(_do_upgrade)
	row.add_child(_upgrade_btn)
	return row


func _material_item(sprite_label: String, lit: bool, tip: Dictionary) -> HBoxContainer:
	var item := HBoxContainer.new()
	item.add_theme_constant_override("separation", 8)
	item.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ps := PixelSlot.new(sprite_label, lit)
	ps.custom_minimum_size = Vector2(40, 40)
	item.add_child(ps)
	Tip.attach(item, tip)
	item.mouse_default_cursor_shape = Control.CURSOR_HELP
	return item


# =========================================================================
# Logic
# =========================================================================

func _do_upgrade() -> void:
	var res := GameState.try_forge_upgrade(_rng)
	if not bool(res["ok"]):
		_show_result(String(res["reason"]), Palette.HP)
	elif bool(res["success"]):
		_show_result("+%d achieved!" % GameState.forge_level, Palette.GOLD_BRIGHT)
	else:
		_show_result("The forge spits sparks — materials lost.", Palette.EMBER_HOT)
	_refresh_all()


func _show_result(text: String, color: Color) -> void:
	_result_lbl.text = text
	_result_lbl.add_theme_color_override("font_color", color)
	_result_lbl.visible = true
	_result_lbl.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_result_lbl, "modulate:a", 1.0, 0.14)


func _refresh_all() -> void:
	var lvl := GameState.forge_level
	_src_tag.text = "+%d" % lvl
	_dst_tag.text = "+%d" % (lvl + 1)
	_refresh_stats()

	var gold_cost := Balance.forge_gold_cost(lvl)
	var iron_cost := Balance.inum("forge.iron_cost", 12)
	var dust_cost := Balance.inum("forge.dust_cost", 3)
	_gold_lbl.text = Style.group_int(gold_cost)
	_iron_qty.text = "×%d" % iron_cost
	_dust_qty.text = "×%d" % dust_cost
	_iron_have.text = "(have %d)" % GameState.iron_ingots
	_dust_have.text = "(have %d)" % GameState.ember_dust
	_iron_have.add_theme_color_override("font_color",
		Palette.HP if GameState.iron_ingots < iron_cost else Palette.TX_MUTE)
	_dust_have.add_theme_color_override("font_color",
		Palette.HP if GameState.ember_dust < dust_cost else Palette.TX_MUTE)
	_upgrade_btn.disabled = GameState.gold < gold_cost \
		or GameState.iron_ingots < iron_cost \
		or GameState.ember_dust < dust_cost
