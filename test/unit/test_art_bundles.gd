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


func test_single_figure_frame_spans_the_whole_texture() -> void:
	# Regression: a re-rendered single-figure sheet (class.warrior fig.png is now
	# 1254×1254) must slice the WHOLE image as its one frame, not crop to a stale
	# meta frame_w/frame_h (was 385×512) — which showed only a corner of the delver.
	var sf := AssetManager.get_sprite_frames("class.warrior")
	assert_not_null(sf)
	if sf == null:
		return
	var at := sf.get_frame_texture("walk", 0) as AtlasTexture
	assert_not_null(at, "the warrior walk frame is an AtlasTexture")
	if at == null:
		return
	assert_eq(at.region.size, at.atlas.get_size(),
		"the single frame spans the full re-rendered texture, not a stale crop")


func test_prop_and_chest_textures_present() -> void:
	for key in ["pillar", "brazier", "tomb", "tree", "rock"]:
		assert_not_null(AssetManager.get_texture("props.dungeon", key), "prop '%s' texture" % key)
	assert_not_null(AssetManager.get_texture("chest", "chest"), "chest texture")


func test_parallax_background_layers_present() -> void:
	# The battlefield draws textured parallax when this bundle resolves; missing
	# layers silently fall back to the procedural bands, so guard all four.
	for key in ["far", "mid", "near", "floor"]:
		assert_not_null(AssetManager.get_texture("bg.reliquary", key), "bg layer '%s' texture" % key)
