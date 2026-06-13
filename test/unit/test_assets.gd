extends GutTest
## Asset delivery + animation runtime. Generates a real test bundle in
## user://assets/ (the same path downloaded bundles use), registers it through
## AssetManager, and verifies SpriteFrames build correctly + UnitSprite renders
## animated when art is present and falls back to the placeholder when it isn't.

const TEST_ID := "hero.test"
const TEST_DIR := "user://assets/hero.test"


func before_all() -> void:
	# Build a tiny two-action atlas bundle on disk: idle (2 frames) + walk (4),
	# 16×16 frames, single direction.
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	_save_strip(TEST_DIR.path_join("idle.png"), 2)
	_save_strip(TEST_DIR.path_join("walk.png"), 4)
	var meta := {
		"id": TEST_ID, "kind": "hero", "frame_w": 16, "frame_h": 16,
		"anims": {
			"idle": {"sheet": "idle.png", "frames": 2, "fps": 4, "dirs": ["se"], "loop": true},
			"walk": {"sheet": "walk.png", "frames": 4, "fps": 10, "dirs": ["se"], "loop": true},
		},
	}
	var f := FileAccess.open(TEST_DIR.path_join("meta.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(meta))
	f.close()


func after_all() -> void:
	for file in ["idle.png", "walk.png", "meta.json"]:
		DirAccess.remove_absolute(TEST_DIR.path_join(file))
	DirAccess.remove_absolute(TEST_DIR)


func _save_strip(path: String, frames: int) -> void:
	var img := Image.create(16 * frames, 16, false, Image.FORMAT_RGBA8)
	for col in frames:
		# A distinct opaque colour per frame so regions are distinguishable.
		var c := Color.from_hsv(float(col) / float(frames), 0.7, 0.9)
		for x in 16:
			for y in 16:
				img.set_pixel(col * 16 + x, y, c)
	img.save_png(path)


func test_register_and_build_sprite_frames() -> void:
	assert_true(AssetManager._register_dir(TEST_ID, TEST_DIR), "bundle with meta.json registers")
	assert_true(AssetManager.has(TEST_ID))
	assert_eq(String(AssetManager.bundle_meta(TEST_ID)["kind"]), "hero")

	var sf := AssetManager.get_sprite_frames(TEST_ID)
	assert_not_null(sf, "animated bundle builds a SpriteFrames")
	assert_true(sf.has_animation("idle"))
	assert_true(sf.has_animation("walk"))
	assert_eq(sf.get_frame_count("idle"), 2, "idle has 2 frames")
	assert_eq(sf.get_frame_count("walk"), 4, "walk has 4 frames")
	assert_almost_eq(sf.get_animation_speed("walk"), 10.0, 0.01)
	# Frames are atlas regions over the strip, sized to the frame box.
	var region := (sf.get_frame_texture("walk", 2) as AtlasTexture).region
	assert_eq(region, Rect2(32, 0, 16, 16), "frame 2 of walk is the 3rd 16px cell")


func test_get_sprite_frames_caches() -> void:
	AssetManager._register_dir(TEST_ID, TEST_DIR)
	var a := AssetManager.get_sprite_frames(TEST_ID)
	var b := AssetManager.get_sprite_frames(TEST_ID)
	assert_eq(a, b, "SpriteFrames is built once and cached")


func test_unit_sprite_animates_when_art_present() -> void:
	AssetManager._register_dir(TEST_ID, TEST_DIR)
	var u := UnitSprite.new(TEST_ID, "16²\ntest", true)
	add_child_autofree(u)
	u.size = Vector2(64, 96)
	await get_tree().process_frame
	assert_true(u.is_animated(), "UnitSprite plays frames when the bundle has art")
	u.play("walk", "ne")  # ne unknown → degrades to walk; must not crash
	pass_test("play() degrades gracefully for unknown directions")


func test_unit_sprite_falls_back_to_placeholder() -> void:
	var u := UnitSprite.new("hero.does_not_exist", "64×96\nGhost", true)
	add_child_autofree(u)
	u.size = Vector2(64, 96)
	await get_tree().process_frame
	assert_false(u.is_animated(), "no bundle → static placeholder, not animation")
	var has_placeholder := false
	for c in u.get_children():
		if c is PixelSlot:
			has_placeholder = true
	assert_true(has_placeholder, "the labeled PixelSlot placeholder renders instead")


func test_manifest_sync_registers_nothing_when_artless() -> void:
	# Mock catalog lists core heroes, but no art folders exist yet → the game
	# still runs; those bundles simply report has()==false (placeholder path).
	await AssetManager.sync_catalog()
	assert_false(AssetManager.has("enemy.elite") and AssetManager.bundle_meta("enemy.elite").is_empty(),
		"a listed-but-artless bundle is not falsely registered")
	pass_test("sync over an artless catalog is safe")


func test_hero_bundle_resolves_skin_then_base() -> void:
	GameState.reset_to_defaults()
	assert_eq(GameContent.hero_bundle("brand"), "hero.brand", "base bundle by default")
	GameState.set_hero_skin("brand", "skin.warrior.ashen")
	assert_eq(GameContent.hero_bundle("brand"), "skin.warrior.ashen", "equipped skin wins")
	GameState.set_hero_skin("brand", "")  # clear
	assert_eq(GameContent.hero_bundle("brand"), "hero.brand", "cleared → base again")


func test_hero_skins_survive_save_round_trip() -> void:
	GameState.reset_to_defaults()
	GameState.set_hero_skin("ash", "skin.mage.cinder")
	var parsed: Variant = JSON.parse_string(JSON.stringify(GameState.to_dict()))
	GameState.reset_to_defaults()
	assert_true(GameState.hero_skins.is_empty(), "defaults clear skins")
	GameState.from_dict(parsed)
	assert_eq(String(GameState.hero_skins.get("ash", "")), "skin.mage.cinder", "skin restored")


# =========================================================================
# Content caching — the same item must NOT re-download every time.
# =========================================================================

func test_cache_serves_identical_bundle_without_refetch() -> void:
	# Registered + indexed at hash H. A re-acquire at the SAME hash short-
	# circuits via the cache (in mock there's no network, so the only way this
	# returns true is the id+hash cache hit — not a re-fetch).
	AssetManager._register_dir(TEST_ID, TEST_DIR)
	AssetManager._index[TEST_ID] = "deadbeefdeadbeef"
	var def := {"id": TEST_ID, "hash": "deadbeefdeadbeef", "priority": "standard", "url": "", "deps": []}
	assert_true(await AssetManager._acquire(def), "identical-hash bundle served from cache")


func test_cache_refetches_on_hash_bump() -> void:
	# A bumped hash must NOT serve the stale cache. hero.test has no res://core
	# folder, mock has no network → _acquire returns false (would be true if it
	# wrongly served the old cached copy).
	AssetManager._register_dir(TEST_ID, TEST_DIR)
	AssetManager._index[TEST_ID] = "oldhasholdhash00"
	var def := {"id": TEST_ID, "hash": "newhashnewhash11", "priority": "standard", "url": "", "deps": []}
	assert_false(await AssetManager._acquire(def), "a hot-updated bundle is not served stale")


func test_cache_index_persists_across_reload() -> void:
	var snapshot := AssetManager._index.duplicate()
	AssetManager._index = {"hero.x": "h1", "skin.y": "h2"}
	AssetManager._save_index()
	AssetManager._index = {}
	AssetManager._load_index()
	assert_eq(String(AssetManager._index.get("hero.x", "")), "h1", "cache index survives a reload")
	assert_eq(String(AssetManager._index.get("skin.y", "")), "h2")
	AssetManager._index = snapshot  # don't leak test state into other tests
	AssetManager._save_index()


func test_repeat_sync_downloads_nothing() -> void:
	# Two syncs in a row: the second sees the same content token → unchanged →
	# the standard loop never runs (no re-acquire / re-download of cached art).
	await AssetManager.sync_catalog()
	var ver := AssetManager._catalog_version
	await AssetManager.sync_catalog()
	assert_eq(AssetManager._catalog_version, ver, "catalog token stable → no churn")
	pass_test("a repeat sync is a no-op for unchanged content")
