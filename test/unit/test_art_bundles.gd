extends GutTest
## Guards that the core art bundles wired from real Floor-1 art load through
## AssetManager: heroes/enemies animate via a built SpriteFrames (even when the
## art is a single static pose registered as a 1-frame walk), and props/chest
## expose their textures. Catches a broken meta.json / missing sheet regression.


func test_hero_class_bundles_build_frames() -> void:
	for cls in ["class.warrior", "class.mage", "class.hunter", "class.rogue"]:
		var sf := AssetManager.get_sprite_frames(cls)
		assert_not_null(sf, "%s should build SpriteFrames" % cls)
		if sf != null:
			assert_true(sf.has_animation("walk"), "%s needs a walk anim" % cls)
			assert_gt(sf.get_frame_count("walk"), 0, "%s walk needs >=1 frame" % cls)


func test_trash_enemy_bundles_build_frames() -> void:
	for en in ["enemy.skeleton", "enemy.ghoul"]:
		var sf := AssetManager.get_sprite_frames(en)
		assert_not_null(sf, "%s should build SpriteFrames" % en)
		if sf != null:
			assert_true(sf.has_animation("walk"), "%s needs a walk anim" % en)
			assert_gt(sf.get_frame_count("walk"), 0, "%s walk needs >=1 frame" % en)


func test_prop_and_chest_textures_present() -> void:
	for key in ["pillar", "brazier", "tomb", "tree", "rock"]:
		assert_not_null(AssetManager.get_texture("props.dungeon", key), "prop '%s' texture" % key)
	assert_not_null(AssetManager.get_texture("chest", "chest"), "chest texture")


func test_parallax_background_layers_present() -> void:
	# The battlefield draws textured parallax when this bundle resolves; missing
	# layers silently fall back to the procedural bands, so guard all four.
	for key in ["far", "mid", "near", "floor"]:
		assert_not_null(AssetManager.get_texture("bg.reliquary", key), "bg layer '%s' texture" % key)
