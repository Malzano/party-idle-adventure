extends Node
## Remote sprite/skin/item delivery (client side). The server serves a thin
## MANIFEST (BackendClient.assets_manifest); the bytes live on a CDN. This
## autoload reconciles the manifest against a local cache and exposes loaded
## bundles to the renderer.
##
## Priority model (design decision: tiny core in build + rest remote):
##   core     — baked into the game at res://assets/core/<id>/ (opens instantly,
##              offline); listed in the manifest only so versions can be checked.
##   standard — downloaded on first launch, in the background after core.
##   lazy     — downloaded on demand (a skin only when equipped).
##
## A bundle folder holds meta.json + atlas PNG(s). Animated kinds (hero/enemy)
## get a SpriteFrames built on request; static kinds expose textures by key.
## Missing art is never fatal: has()==false → callers fall back to the labeled
## PixelSlot placeholder, so the game runs at every stage of art production.

const CORE_DIR := "res://assets/core"
const CACHE_DIR := "user://assets"
const INDEX_PATH := "user://assets/index.json"

signal asset_ready(bundle_id: String)
signal catalog_synced(downloaded: int, total: int)

## id -> {meta: Dictionary, dir: String, textures: {file->Texture2D}, frames: SpriteFrames|null}
var _bundles: Dictionary = {}
## id -> hash currently on disk (mirrors user://assets/index.json).
var _index: Dictionary = {}
## The whole last-seen catalog (bundle defs by id), for lazy on-demand fetches.
var _catalog: Dictionary = {}
var _catalog_version: int = 0
var _cdn_base: String = ""


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	_load_index()
	_register_core()
	_register_cached()
	# Manifest reconcile needs BackendClient ready (later in autoload order).
	sync_catalog.call_deferred()


# =========================================================================
# Public API
# =========================================================================

func has(bundle_id: String) -> bool:
	return _bundles.has(bundle_id)


func bundle_meta(bundle_id: String) -> Dictionary:
	var b: Dictionary = _bundles.get(bundle_id, {})
	return b.get("meta", {})


## Animated bundles → a built (cached) SpriteFrames, or null if the bundle has
## no art yet (caller falls back to a placeholder).
func get_sprite_frames(bundle_id: String) -> SpriteFrames:
	var b: Dictionary = _bundles.get(bundle_id, {})
	if b.is_empty():
		return null
	if b.get("frames") != null:
		return b["frames"]
	var sf := _build_sprite_frames(bundle_id, b)
	b["frames"] = sf
	return sf


## Static bundles → a texture by key (or the lone sprite when key is omitted).
func get_texture(bundle_id: String, key: String = "") -> Texture2D:
	var b: Dictionary = _bundles.get(bundle_id, {})
	if b.is_empty():
		return null
	var meta: Dictionary = b["meta"]
	var sprites: Dictionary = meta.get("sprites", {})
	var file := ""
	if key != "" and sprites.has(key):
		file = String(sprites[key])
	elif not sprites.is_empty():
		file = String(sprites.values()[0])
	if file == "":
		return null
	return _texture(bundle_id, file)


## Ensure a lazy bundle (e.g. a skin) is present at the CURRENT catalog hash;
## emits asset_ready when usable. Re-acquires when the cached copy is stale
## (a hot-updated skin), not just when it's missing.
func request(bundle_id: String) -> void:
	var def: Dictionary = _catalog.get(bundle_id, {})
	var fresh := has(bundle_id) and (def.is_empty() or String(_index.get(bundle_id, "")) == String(def.get("hash", "")))
	if fresh:
		asset_ready.emit(bundle_id)
		return
	if def.is_empty():
		return
	if await _acquire(def):
		asset_ready.emit(bundle_id)


# =========================================================================
# Catalog sync
# =========================================================================

## Fetch the manifest and reconcile standard bundles. Core is already in the
## build; lazy waits for request(). Re-runnable (the combat heartbeat can call
## it so hot content — new skins/items — appears without a restart).
func sync_catalog() -> void:
	var res: Dictionary = await BackendClient.assets_manifest(_catalog_version)
	if not bool(res.get("ok", false)):
		return
	var data: Dictionary = res["data"]
	if bool(data.get("unchanged", false)):
		return
	_catalog_version = int(data.get("catalog_version", _catalog_version))
	_cdn_base = String(data.get("cdn_base", _cdn_base))
	var bundles: Array = data.get("bundles", [])
	var downloaded := 0
	var standard := 0
	for b_v in bundles:
		var def: Dictionary = b_v
		_catalog[String(def["id"])] = def
		if String(def.get("priority", "")) != "standard":
			continue
		standard += 1
		if String(_index.get(def["id"], "")) == String(def["hash"]) and has(String(def["id"])):
			continue
		if await _acquire(def):
			downloaded += 1
			# A bundle that finished downloading mid-session must refresh the
			# units already drawn as placeholders (hot content w/o restart).
			asset_ready.emit(String(def["id"]))
	catalog_synced.emit(downloaded, standard)


# =========================================================================
# Acquisition (mock = load from res://; live = download from the CDN)
# =========================================================================

## Make a bundle available: in mock, its bytes ship locally (res://assets/core
## already, or treat the folder as present); in live, download + unpack from
## the CDN. Returns true if the bundle is now registered.
func _acquire(def: Dictionary) -> bool:
	var id := String(def["id"])
	# Already cached at the right hash.
	if has(id) and String(_index.get(id, "")) == String(def["hash"]):
		return true
	# A res:// folder is AUTHORITATIVE only for core (baked baseline) and, in
	# mock mode, for any bundle (the dev art is the only source). In LIVE mode a
	# standard/lazy hash bump means the CDN has newer art → it must download,
	# never silently re-register stale baked art under the new hash.
	var core := String(def.get("priority", "")) == "core"
	if (core or BackendClient.mock) and DirAccess.dir_exists_absolute(CORE_DIR.path_join(id)) \
			and _register_dir(id, CORE_DIR.path_join(id)):
		_index[id] = String(def["hash"])
		_save_index()
		return true
	if BackendClient.mock:
		return false  # mock has no network; missing art → placeholder fallback
	return await _download(def)


## Live download: GET the .pkg from cdn_base+url, hash-verify, unzip to the
## cache, register. Inert in mock mode. A PER-CALL HTTPRequest (not a shared
## member) so concurrent downloads — background sync + an equipped skin — never
## clobber each other's download_file / completion signal.
func _download(def: Dictionary) -> bool:
	var url := _cdn_base + String(def["url"])
	if url == "" or not url.begins_with("http"):
		return false
	var http := HTTPRequest.new()
	add_child(http)
	var dest := CACHE_DIR.path_join(String(def["id"]) + ".pkg")
	http.download_file = dest
	if http.request(url) != OK:
		http.queue_free()
		return false
	var result: Array = await http.request_completed
	http.queue_free()
	if int(result[1]) != 200:
		return false
	# Integrity: short sha256 of the package vs the manifest hash. Verified
	# whenever the catalog carries a REAL content hash (16 hex chars, no '-');
	# dev/seed placeholder hashes (e.g. "s-elite-1") are skipped, real uploads
	# MUST set a real hash so swapped/corrupt bytes are caught.
	var want := String(def["hash"])
	if _is_content_hash(want):
		var got := _short_sha(FileAccess.get_file_as_bytes(dest))
		if got != want:
			push_warning("AssetManager: hash mismatch for %s (got %s)" % [def["id"], got])
			DirAccess.remove_absolute(dest)
			return false
	var out_dir := CACHE_DIR.path_join(String(def["id"]))
	if not _unzip(dest, out_dir):
		return false
	DirAccess.remove_absolute(dest)
	if _register_dir(String(def["id"]), out_dir):
		_index[String(def["id"])] = want
		_save_index()
		return true
	return false


## A real content hash = 16 lowercase hex chars (what _short_sha emits).
func _is_content_hash(h: String) -> bool:
	if h.length() != 16:
		return false
	for c in h:
		if not ((c >= "0" and c <= "9") or (c >= "a" and c <= "f")):
			return false
	return true


func _unzip(pkg: String, out_dir: String) -> bool:
	var zip := ZIPReader.new()
	if zip.open(pkg) != OK:
		return false
	DirAccess.make_dir_recursive_absolute(out_dir)
	for entry in zip.get_files():
		var dest_path := out_dir.path_join(entry)
		# Entries can be nested (e.g. "se/walk.png"); make the parent first or
		# the write silently drops the file.
		DirAccess.make_dir_recursive_absolute(dest_path.get_base_dir())
		var data := zip.read_file(entry)
		var f := FileAccess.open(dest_path, FileAccess.WRITE)
		if f != null:
			f.store_buffer(data)
			f.close()
	zip.close()
	return true


# =========================================================================
# Bundle registration + loading
# =========================================================================

func _register_core() -> void:
	if not DirAccess.dir_exists_absolute(CORE_DIR):
		return
	for sub in DirAccess.get_directories_at(CORE_DIR):
		_register_dir(sub, CORE_DIR.path_join(sub))


func _register_cached() -> void:
	for sub in DirAccess.get_directories_at(CACHE_DIR):
		_register_dir(sub, CACHE_DIR.path_join(sub))


## Read <dir>/meta.json and register the bundle. Returns false when there's no
## meta (the bundle is "known but artless" → placeholder fallback).
func _register_dir(bundle_id: String, dir: String) -> bool:
	var meta_path := dir.path_join("meta.json")
	if not FileAccess.file_exists(meta_path):
		return false
	var text := FileAccess.get_file_as_string(meta_path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	_bundles[bundle_id] = {"meta": parsed, "dir": dir, "textures": {}, "frames": null}
	return true


func _texture(bundle_id: String, file: String) -> Texture2D:
	var b: Dictionary = _bundles[bundle_id]
	var cache: Dictionary = b["textures"]
	if cache.has(file):
		return cache[file]
	var path := String(b["dir"]).path_join(file)
	var tex: Texture2D = null
	if path.begins_with("res://"):
		tex = load(path) as Texture2D
	else:
		var img := Image.new()
		if img.load(path) == OK:
			tex = ImageTexture.create_from_image(img)
	cache[file] = tex
	return tex


## Build SpriteFrames from a bundle's anims. Each action's sheet is a grid:
## columns = frames, rows = directions (in `dirs` order). Single-direction
## actions register as "<action>"; multi-dir as "<action>_<dir>".
func _build_sprite_frames(bundle_id: String, b: Dictionary) -> SpriteFrames:
	var meta: Dictionary = b["meta"]
	var anims: Dictionary = meta.get("anims", {})
	if anims.is_empty():
		return null
	var fw := int(meta.get("frame_w", 64))
	var fh := int(meta.get("frame_h", 64))
	var sf := SpriteFrames.new()
	if sf.has_animation("default"):
		sf.remove_animation("default")
	for action in anims:
		var a: Dictionary = anims[action]
		var tex := _texture(bundle_id, String(a.get("sheet", "")))
		if tex == null:
			continue
		var dirs: Array = a.get("dirs", ["se"])
		var frames := int(a.get("frames", 1))
		for row in dirs.size():
			var anim_name := String(action) if dirs.size() == 1 else "%s_%s" % [action, dirs[row]]
			sf.add_animation(anim_name)
			sf.set_animation_speed(anim_name, float(a.get("fps", 8)))
			sf.set_animation_loop(anim_name, bool(a.get("loop", true)))
			for col in frames:
				var at := AtlasTexture.new()
				at.atlas = tex
				at.region = Rect2(col * fw, row * fh, fw, fh)
				sf.add_frame(anim_name, at)
	return sf


# =========================================================================
# Cache index
# =========================================================================

func _load_index() -> void:
	if not FileAccess.file_exists(INDEX_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(INDEX_PATH))
	if typeof(parsed) == TYPE_DICTIONARY:
		_index = parsed


func _save_index() -> void:
	var f := FileAccess.open(INDEX_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_index))
		f.close()


func _short_sha(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode().substr(0, 16)
