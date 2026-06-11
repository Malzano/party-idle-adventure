extends "res://scenes/camp/ModalShell.gd"
## CRAFTING HOUSE modal (camp.jsx ForgeModal): anvil row (epic source slot →
## glowing arrow → legendary +8 preview) over a warm radial, upgrade-stats
## inset, and the material/gold cost row. Upgrade spends 4,200 gold via
## GameState (disabled while unaffordable). Enter triggers the upgrade.

const _UPGRADE_COST := 4200

var _upgrade_btn: Button


func _init() -> void:
	modal_title = "Crafting House"
	modal_width = 900.0
	body_separation = 18


func _build_body(body: VBoxContainer) -> void:
	body.add_child(_build_anvil())
	body.add_child(_build_stats())
	body.add_child(_build_cost())
	EventBus.currencies_changed.connect(_refresh_afford)
	_refresh_afford()


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

	row.add_child(_forge_slot("epic", "96²\nweapon", "+7", {
		"name": "Cindergrip Maul", "type": "Two-Handed · Epic", "rarity": "epic",
		"stats": [["Physical DMG", "412–588"], ["+ Strength", "64"], ["Crit Chance", "8.5%"]],
		"flavor": "Forged in the last ember of a dead star."}))

	var arrow := Style.body_label("→", 30, Palette.EMBER)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	arrow.add_theme_color_override("font_shadow_color", Palette.with_alpha(Palette.EMBER, 0.5))
	arrow.add_theme_constant_override("shadow_outline_size", int(10 * Palette.GLOW))
	row.add_child(arrow)

	row.add_child(_forge_slot("legendary", "96²\n+8 preview", "+8", {}))
	return anvil


## 130² rarity-framed forge slot with an inset pixel sprite and a +N level tag.
func _forge_slot(rar: String, sprite_label: String, lv: String, tip: Dictionary) -> Control:
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

	var tag := Style.pixel_label(lv, 11, Palette.GOLD_BRIGHT)
	tag.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	tag.add_theme_constant_override("shadow_offset_y", 1)
	slot.add_child(tag)
	tag.resized.connect(func() -> void:
		tag.position = Vector2(130.0 - 6.0 - tag.size.x, 130.0 - 4.0 - tag.size.y))

	if not tip.is_empty():
		Tip.attach(slot, tip)
		slot.mouse_default_cursor_shape = Control.CURSOR_HELP
	return slot


# =========================================================================
# Stats inset (.forge-stats)
# =========================================================================

func _build_stats() -> Control:
	var panel := PanelContainer.new()
	var sb := Style.inset_box(4)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	col.add_child(_fs_row("Physical Damage", [["412–588", Palette.TX], [" → 470–664", Palette.R_UNCOMMON]]))
	col.add_child(_fs_row("Strength", [["64", Palette.TX], [" → 72", Palette.R_UNCOMMON]]))
	col.add_child(_fs_row("Success rate", [["82%", Palette.CYAN_BRIGHT]]))
	return panel


func _fs_row(label: String, parts: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	var lbl := Style.body_label(label, 14, Palette.TX_DIM)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	for part: Array in parts:
		row.add_child(Style.body_label(String(part[0]), 14, part[1]))
	return row


# =========================================================================
# Cost row (.forge-cost)
# =========================================================================

func _build_cost() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	row.add_child(_cost_item("32²", false, "×12", {"name": "Iron Ingot", "type": "Material", "rarity": "common"}))
	row.add_child(_cost_item("32²", true, "×3", {"name": "Ember Dust", "type": "Material · Rare", "rarity": "rare"}))

	var gold := VBoxContainer.new()
	gold.add_theme_constant_override("separation", 0)
	gold.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gold.add_child(Style.pixel_label("4,200", 12, Palette.GOLD_BRIGHT))
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


func _cost_item(sprite_label: String, lit: bool, qty: String, tip: Dictionary) -> Control:
	var item := HBoxContainer.new()
	item.add_theme_constant_override("separation", 8)
	item.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ps := PixelSlot.new(sprite_label, lit)
	ps.custom_minimum_size = Vector2(40, 40)
	item.add_child(ps)
	var q := Style.pixel_label(qty, 12, Palette.TX_DIM)
	q.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	item.add_child(q)
	Tip.attach(item, tip)
	item.mouse_default_cursor_shape = Control.CURSOR_HELP
	return item


# =========================================================================
# Logic
# =========================================================================

func _do_upgrade() -> void:
	if GameState.gold < _UPGRADE_COST:
		return
	GameState.add_gold(-_UPGRADE_COST)


func _refresh_afford() -> void:
	_upgrade_btn.disabled = GameState.gold < _UPGRADE_COST
