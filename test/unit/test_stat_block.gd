extends GutTest
## StatBlock: effect-string parsing, stat-pair parsing, aliases, value() math.

const StatBlockScript := preload("res://systems/data/StatBlock.gd")


func _block() -> StatBlock:
	return StatBlockScript.new()


func test_flat_effect_parses() -> void:
	var b := _block()
	b.apply_effect("+10 Strength")
	assert_eq(b.get_flat("strength"), 10.0, "+10 Strength should add 10 flat strength")
	assert_eq(b.get_inc("strength"), 0.0, "flat effect must not touch inc")


func test_percent_effect_parses_as_inc() -> void:
	var b := _block()
	b.apply_effect("+6% Attack Speed")
	assert_almost_eq(b.get_inc("attack_speed"), 0.06, 0.0001, "+6% should become inc 0.06")
	assert_eq(b.get_flat("attack_speed"), 0.0, "percent effect must not touch flat")


func test_joined_effect_parses_both_fragments() -> void:
	var b := _block()
	b.apply_effect("+24% Melee Damage · +30 Strength")
	assert_almost_eq(b.get_inc("melee_damage"), 0.24, 0.0001)
	assert_eq(b.get_flat("strength"), 30.0)


func test_all_attributes_expands_to_five_attrs() -> void:
	var b := _block()
	b.apply_effect("+30 All Attributes")
	for attr in ["strength", "dexterity", "intelligence", "vitality", "luck"]:
		assert_eq(b.get_flat(attr), 30.0, "+30 All Attributes should grant 30 flat %s" % attr)


func test_stat_pairs_flat_and_range() -> void:
	var b := _block()
	b.apply_stat_pairs([["Armour", "+248"], ["Physical DMG", "470–664"]])
	assert_eq(b.get_flat("armour"), 248.0)
	assert_eq(b.get_flat("physical_dmg"), 567.0, "range 470–664 should average to 567 flat")


func test_party_atk_aliases_to_all_damage() -> void:
	var b := _block()
	b.apply_effect("+12% party ATK")
	assert_almost_eq(b.get_inc("all_damage"), 0.12, 0.0001, "party ATK is an alias for all_damage")


func test_negative_percent_pair() -> void:
	var b := _block()
	b.apply_stat_pairs([["Chaos Resist", "-12%"]])
	assert_almost_eq(b.get_inc("chaos_resist"), -0.12, 0.0001)


func test_negative_unicode_minus_pair() -> void:
	var b := _block()
	b.apply_stat_pairs([["Chaos Resist", "−12%"]])
	assert_almost_eq(b.get_inc("chaos_resist"), -0.12, 0.0001, "unicode minus should parse like ASCII")


func test_prose_fragment_is_ignored() -> void:
	var b := _block()
	b.apply_effect("Curses spread to nearby foes")
	assert_eq(b.flat.size(), 0, "pure prose must not create flat mods")
	assert_eq(b.inc.size(), 0, "pure prose must not create inc mods")


func test_value_math_base_plus_flat_times_inc() -> void:
	var b := _block()
	b.add_flat("armour", 100.0)
	b.add_inc("armour", 0.5)
	assert_almost_eq(b.value("armour", 200.0), 450.0, 0.0001, "(200+100)*(1+0.5) == 450")
	assert_almost_eq(b.value("armour"), 150.0, 0.0001, "(0+100)*(1+0.5) == 150")
	assert_eq(b.value("missing_stat", 42.0), 42.0, "unknown stat resolves to base")


func test_merge_sums_flats_and_incs() -> void:
	var a := _block()
	a.add_flat("strength", 10.0)
	a.add_inc("fire_damage", 0.1)
	var b := _block()
	b.add_flat("strength", 5.0)
	b.add_inc("fire_damage", 0.2)
	b.add_flat("armour", 50.0)
	a.merge(b)
	assert_eq(a.get_flat("strength"), 15.0)
	assert_almost_eq(a.get_inc("fire_damage"), 0.3, 0.0001)
	assert_eq(a.get_flat("armour"), 50.0)
