extends SceneTree
## DEV TOOL (not shipped). Generates crude-but-recognisable placeholder sprite
## bundles into res://assets/core/ so the game renders real moving art instead
## of labeled checker slots. Replace any <id>/ folder with real art later — the
## meta.json schema stays the same.
##
## Run:  godot --headless --script res://tools/gen_placeholder_art.gd
## Then: godot --headless --import   (so Godot imports the PNGs)

const ROOT := "res://assets/core"

# Role → body palette (base, trim).
const ROLE_COL := {
	"tank": [Color("b5403a"), Color("e8c87a")],
	"dps": [Color("e0843a"), Color("ffd28a")],
	"mage": [Color("7a5ad0"), Color("9ad0ff")],
	"healer": [Color("d6b84a"), Color("fff2cc")],
}

# The 12 collection heroes (id → role) + the 4 login classes.
const HEROES := [
	["brand", "tank"], ["ash", "dps"], ["hex", "mage"], ["wren", "healer"],
	["mord", "tank"], ["sera", "healer"], ["korr", "dps"], ["tarn", "dps"],
	["wisp", "healer"], ["grub", "tank"], ["veyra", "mage"], ["oszric", "mage"],
]
const CLASSES := [
	["warrior", "tank"], ["mage", "mage"], ["hunter", "dps"], ["rogue", "dps"],
]


func _initialize() -> void:
	var made := 0
	for h in HEROES:
		_hero_bundle("hero." + String(h[0]), ROLE_COL[h[1]], String(h[0]))
		made += 1
	for c in CLASSES:
		_class_bundle("class." + String(c[0]), ROLE_COL[c[1]], String(c[0]))
		made += 1
	_enemy_bundle("enemy.ghoul", Color("6a8c4a"), Color("9fd06a"), 32, 44)
	_enemy_bundle("enemy.skeleton", Color("d8d0b8"), Color("ffffff"), 32, 44)
	_enemy_bundle("enemy.elite", Color("8a2a2a"), Color("ff7a4a"), 44, 56)
	made += 3
	_props_bundle()
	_chest_bundle()
	_campfire_bundle()
	_buildings_bundle()
	made += 4
	print("Generated %d placeholder bundles under %s" % [made, ROOT])
	quit()


# =========================================================================
# Bundle builders
# =========================================================================

## Animated hero: idle (2 frames) + walk (4 frames), single SE direction.
func _hero_bundle(id: String, pal: Array, seed_name: String) -> void:
	var dir := ROOT.path_join(id)
	DirAccess.make_dir_recursive_absolute(dir)
	var fw := 32
	var fh := 48
	var accent := _accent_for(seed_name)
	_save_strip(dir.path_join("idle.png"), fw, fh, 2, func(img: Image, fx: int, phase: float) -> void:
		_draw_humanoid(img, fx, fw, fh, pal[0], pal[1], accent, sin(phase * TAU) * 1.0, 0.0))
	_save_strip(dir.path_join("walk.png"), fw, fh, 4, func(img: Image, fx: int, phase: float) -> void:
		_draw_humanoid(img, fx, fw, fh, pal[0], pal[1], accent, sin(phase * TAU) * 1.5, sin(phase * TAU) * 3.0))
	_write_meta(dir, {
		"id": id, "kind": "hero", "frame_w": fw, "frame_h": fh,
		"anims": {
			"idle": {"sheet": "idle.png", "frames": 2, "fps": 3, "dirs": ["se"], "loop": true},
			"walk": {"sheet": "walk.png", "frames": 4, "fps": 8, "dirs": ["se"], "loop": true},
		},
	})


## Animated enemy: a hunched figure, walk (4) + a small idle (2).
func _enemy_bundle(id: String, base: Color, trim: Color, fw: int, fh: int) -> void:
	var dir := ROOT.path_join(id)
	DirAccess.make_dir_recursive_absolute(dir)
	_save_strip(dir.path_join("idle.png"), fw, fh, 2, func(img: Image, fx: int, phase: float) -> void:
		_draw_enemy(img, fx, fw, fh, base, trim, sin(phase * TAU) * 1.0, 0.0))
	_save_strip(dir.path_join("walk.png"), fw, fh, 4, func(img: Image, fx: int, phase: float) -> void:
		_draw_enemy(img, fx, fw, fh, base, trim, sin(phase * TAU) * 1.5, sin(phase * TAU) * 3.0))
	_write_meta(dir, {
		"id": id, "kind": "enemy", "frame_w": fw, "frame_h": fh,
		"anims": {
			"idle": {"sheet": "idle.png", "frames": 2, "fps": 3, "dirs": ["se"], "loop": true},
			"walk": {"sheet": "walk.png", "frames": 4, "fps": 7, "dirs": ["se"], "loop": true},
		},
	})


## Static tall figure for the login class-select screen.
func _class_bundle(id: String, pal: Array, name: String) -> void:
	var dir := ROOT.path_join(id)
	DirAccess.make_dir_recursive_absolute(dir)
	var img := Image.create(64, 96, false, Image.FORMAT_RGBA8)
	_draw_humanoid(img, 0, 64, 96, pal[0], pal[1], _accent_for(name), 0.0, 0.0)
	img.save_png(dir.path_join("fig.png"))
	_write_meta(dir, {"id": id, "kind": "hero", "sprites": {"fig": "fig.png"}})


## Static dungeon props in one bundle, keyed by prop kind.
func _props_bundle() -> void:
	var dir := ROOT.path_join("props.dungeon")
	DirAccess.make_dir_recursive_absolute(dir)
	_save_one(dir.path_join("tree.png"), 58, 92, func(img: Image) -> void:
		_rect(img, 25, 50, 8, 42, Color("3a2a1a"))  # trunk
		_disc(img, 29, 34, 22, Color("2a4a2a"))     # canopy
		_disc(img, 18, 42, 14, Color("335a33")))
	_save_one(dir.path_join("rock.png"), 44, 30, func(img: Image) -> void:
		_disc(img, 22, 20, 18, Color("4a4640"))
		_disc(img, 14, 22, 10, Color("565049")))
	_save_one(dir.path_join("pillar.png"), 48, 96, func(img: Image) -> void:
		_rect(img, 14, 6, 20, 86, Color("575144"))
		_rect(img, 10, 2, 28, 8, Color("6a6356"))
		_rect(img, 10, 86, 28, 8, Color("6a6356")))
	_save_one(dir.path_join("brazier.png"), 40, 56, func(img: Image) -> void:
		_rect(img, 14, 30, 12, 24, Color("44403a"))
		_disc(img, 20, 22, 12, Color("e8843a"))
		_disc(img, 20, 18, 7, Color("ffd28a")))
	_save_one(dir.path_join("tomb.png"), 56, 48, func(img: Image) -> void:
		_rect(img, 8, 16, 40, 30, Color("4a4640"))
		_rect(img, 22, 6, 12, 16, Color("565049")))
	_write_meta(dir, {"id": "props.dungeon", "kind": "prop", "sprites": {
		"tree": "tree.png", "rock": "rock.png", "pillar": "pillar.png",
		"brazier": "brazier.png", "tomb": "tomb.png"}})


func _chest_bundle() -> void:
	var dir := ROOT.path_join("chest")
	DirAccess.make_dir_recursive_absolute(dir)
	_save_one(dir.path_join("chest.png"), 48, 40, func(img: Image) -> void:
		_rect(img, 6, 14, 36, 24, Color("5a3a1f"))    # body
		_rect(img, 6, 12, 36, 8, Color("6e4a28"))     # lid
		_rect(img, 6, 19, 36, 2, Color("c8a24a"))     # gold band
		_rect(img, 21, 18, 6, 6, Color("f0cf86")))    # lock
	_write_meta(dir, {"id": "chest", "kind": "item", "sprites": {"chest": "chest.png"}})


func _campfire_bundle() -> void:
	var dir := ROOT.path_join("campfire")
	DirAccess.make_dir_recursive_absolute(dir)
	_save_one(dir.path_join("fire.png"), 60, 46, func(img: Image) -> void:
		_rect(img, 10, 36, 40, 6, Color("3a2a1a"))    # logs
		_disc(img, 30, 26, 16, Color("e0843a"))
		_disc(img, 30, 22, 9, Color("ffd28a")))
	_write_meta(dir, {"id": "campfire", "kind": "prop", "sprites": {"campfire": "fire.png"}})


func _buildings_bundle() -> void:
	var dir := ROOT.path_join("buildings.camp")
	DirAccess.make_dir_recursive_absolute(dir)
	_save_one(dir.path_join("altar.png"), 80, 72, func(img: Image) -> void:
		_rect(img, 16, 30, 48, 38, Color("46413a"))
		_disc(img, 40, 24, 16, Color("7a5ad0")))
	_save_one(dir.path_join("board.png"), 80, 64, func(img: Image) -> void:
		_rect(img, 14, 16, 52, 40, Color("5a3a1f"))
		_rect(img, 18, 20, 44, 32, Color("c8b88a")))
	_save_one(dir.path_join("forge.png"), 80, 64, func(img: Image) -> void:
		_rect(img, 12, 28, 56, 32, Color("3a3630"))
		_disc(img, 40, 34, 12, Color("e0843a")))
	_save_one(dir.path_join("kitchen.png"), 80, 60, func(img: Image) -> void:
		_rect(img, 14, 24, 52, 32, Color("4a4036"))
		_disc(img, 40, 22, 10, Color("ffd28a")))
	_write_meta(dir, {"id": "buildings.camp", "kind": "building", "sprites": {
		"altar": "altar.png", "board": "board.png", "forge": "forge.png", "kitchen": "kitchen.png"}})


# =========================================================================
# Drawing
# =========================================================================

## A chunky standing figure (head/torso/legs/arms + a weapon nub), filling the
## frame box at fx. `bob` shifts the body vertically, `swing` alternates legs.
func _draw_humanoid(img: Image, fx: int, fw: int, fh: int, base: Color, trim: Color, accent: Color, bob: float, swing: float) -> void:
	var cx := fx + fw / 2
	var by := int(bob)
	var sw := int(swing)
	# legs
	_rect(img, cx - 6, fh - 16 + by, 5, 14 - sw, base.darkened(0.3))
	_rect(img, cx + 1, fh - 16 + by, 5, 14 + sw, base.darkened(0.3))
	# torso (trapezoid via stacked rects)
	_rect(img, cx - 8, fh - 30 + by, 16, 16, base)
	_rect(img, cx - 6, fh - 34 + by, 12, 6, base.lightened(0.1))
	# arms
	_rect(img, cx - 11, fh - 30 + by, 4, 13, base.darkened(0.15))
	_rect(img, cx + 7, fh - 30 + by, 4, 13, base.darkened(0.15))
	# head
	_disc(img, cx, fh - 38 + by, 6, trim)
	# weapon (accent) on the right
	_rect(img, cx + 11, fh - 44 + by, 3, 26, accent)
	# trim belt
	_rect(img, cx - 8, fh - 18 + by, 16, 3, trim.darkened(0.1))


## A hunched, narrower figure for enemies (reads as "not the heroes").
func _draw_enemy(img: Image, fx: int, fw: int, fh: int, base: Color, trim: Color, bob: float, swing: float) -> void:
	var cx := fx + fw / 2
	var by := int(bob)
	var sw := int(swing)
	_rect(img, cx - 5, fh - 14 + by, 4, 12 - sw, base.darkened(0.3))
	_rect(img, cx + 1, fh - 14 + by, 4, 12 + sw, base.darkened(0.3))
	# hunched torso (offset forward)
	_rect(img, cx - 7, fh - 26 + by, 14, 14, base)
	_rect(img, cx - 9, fh - 24 + by, 4, 11, base.darkened(0.2))  # long arm
	_rect(img, cx + 6, fh - 24 + by, 4, 11, base.darkened(0.2))
	# low head
	_disc(img, cx + 2, fh - 30 + by, 5, trim)
	# glowing eye
	_rect(img, cx + 3, fh - 31 + by, 2, 2, Color("ff5a3a"))


func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	var sz := img.get_size()
	for yy in range(maxi(0, y), mini(sz.y, y + h)):
		for xx in range(maxi(0, x), mini(sz.x, x + w)):
			img.set_pixel(xx, yy, c)


func _disc(img: Image, cx: int, cy: int, r: int, c: Color) -> void:
	var sz := img.get_size()
	for yy in range(maxi(0, cy - r), mini(sz.y, cy + r + 1)):
		for xx in range(maxi(0, cx - r), mini(sz.x, cx + r + 1)):
			if (xx - cx) * (xx - cx) + (yy - cy) * (yy - cy) <= r * r:
				img.set_pixel(xx, yy, c)


# =========================================================================
# IO
# =========================================================================

## A horizontal strip of [frames] cells, each drawn by `draw_cell(img, fx, phase)`.
func _save_strip(path: String, fw: int, fh: int, frames: int, draw_cell: Callable) -> void:
	var img := Image.create(fw * frames, fh, false, Image.FORMAT_RGBA8)
	for col in frames:
		draw_cell.call(img, col * fw, float(col) / float(frames))
	img.save_png(path)


func _save_one(path: String, w: int, h: int, draw: Callable) -> void:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	draw.call(img)
	img.save_png(path)


func _write_meta(dir: String, meta: Dictionary) -> void:
	var f := FileAccess.open(dir.path_join("meta.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "\t"))
	f.close()


func _accent_for(name: String) -> Color:
	return Color.from_hsv(fmod(float(hash(name) % 360) / 360.0, 1.0), 0.55, 0.95)
