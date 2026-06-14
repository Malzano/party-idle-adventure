extends Node
## Persists GameState to user:// as JSON.
##
## Stores a last-played UTC timestamp on every save (CLAUDE.md §1, §3). On load
## it computes how long the game was closed and stashes that on GameState as
## pending_offline_seconds for the offline-progress system to consume later.

const SAVE_PATH := "user://savegame.json"
## v3: single-character profile (roster dropped, total_summons added). v2→v3 is
## backward-compatible — from_dict tolerates missing keys and migrates the
## legacy roster — so both load via from_dict (see the gate in load_game).
const SAVE_VERSION := 3

## Hours of offline time beyond which no further progress accrues. Open
## question in CLAUDE.md §10.5 — placeholder until confirmed.
const OFFLINE_CAP_SECONDS := 12 * 60 * 60

## DEV: wipe ALL local cached state on every editor run so the game boots fresh
## at the Login screen (no save, party, auth, settings, or asset cache). Editor
## ONLY — exported builds keep normal persistence. Flip to false to keep state
## between runs in the editor.
const DEV_FRESH_START := true


func _ready() -> void:
	# Runs before BackendClient (auth/netstate) and AssetManager (cache) read
	# their files — autoload order: …, SaveManager(3), …, BackendClient(6),
	# AssetManager(8) — so clearing here gives a truly clean boot.
	if DEV_FRESH_START and OS.has_feature("editor"):
		_dev_clear_local_state()
	load_game()


## Delete the cached profile / party / auth / settings / downloaded assets so an
## editor run starts from scratch. Targets specific paths only (never the engine
## caches). No-op in exported builds.
func _dev_clear_local_state() -> void:
	for f: String in ["user://savegame.json", "user://netstate.json",
			"user://auth.json", "user://settings.cfg"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	_dev_rm_rf("user://assets")  # AssetManager's hash-keyed download cache
	print("[SaveManager] DEV_FRESH_START: cleared local state → fresh boot.")


func _dev_rm_rf(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var entry := d.get_next()
	while entry != "":
		var full := path.path_join(entry)
		if d.current_is_dir():
			_dev_rm_rf(full)
		else:
			DirAccess.remove_absolute(full)
		entry = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(path)


## Write the current GameState to disk. Returns true on success.
func save_game() -> bool:
	GameState.last_played_utc = _now_utc()

	var payload := {
		"version": SAVE_VERSION,
		"state": GameState.to_dict(),
	}

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: could not open save for writing (error %d)" % FileAccess.get_open_error())
		return false

	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	EventBus.game_saved.emit()
	return true


## Read the save from disk into GameState. Returns true if an existing save was
## loaded, false if none existed or it was unreadable (defaults applied).
func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		GameState.reset_to_defaults()
		GameState.last_played_utc = _now_utc()
		EventBus.game_loaded.emit()
		return false

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("SaveManager: could not open save for reading (error %d)" % FileAccess.get_open_error())
		_recover_to_defaults()
		return false

	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SaveManager: save file is malformed; resetting to defaults.")
		_recover_to_defaults()
		return false

	var data: Dictionary = parsed
	var state: Dictionary = data.get("state", {})
	GameState.reset_to_defaults()
	if int(data.get("version", 0)) < 2:
		# Truly ancient (pre-Grimhollow v2) save: the schema changed wholesale,
		# so start from new defaults but keep the timestamp for offline gains.
		# NOTE: this gate is `< 2`, NOT `< SAVE_VERSION` — v2 and v3 are
		# compatible and MUST go through from_dict (bumping the version with a
		# `< SAVE_VERSION` gate would silently wipe every existing profile).
		GameState.last_played_utc = int(state.get("last_played_utc", _now_utc()))
	else:
		GameState.from_dict(state)

	_compute_offline_progress()
	EventBus.game_loaded.emit()
	return true


## Elapsed time since last save, clamped to the offline cap, recorded for the
## offline-progress milestone. Does not yet grant rewards.
func _compute_offline_progress() -> void:
	var now := _now_utc()
	var elapsed := now - GameState.last_played_utc
	if elapsed < 0:
		elapsed = 0  # Clock moved backwards; ignore.
	GameState.pending_offline_seconds = mini(elapsed, OFFLINE_CAP_SECONDS)


func _recover_to_defaults() -> void:
	GameState.reset_to_defaults()
	GameState.last_played_utc = _now_utc()
	EventBus.game_loaded.emit()


func _now_utc() -> int:
	return int(Time.get_unix_time_from_system())
