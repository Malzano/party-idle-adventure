extends Node
## Device/user settings (design v2 settings.jsx) — NOT part of the save blob:
## these are per-machine preferences, persisted in user://settings.cfg.
## apply() pushes them into the engine (V-Sync, fullscreen, master volume);
## gameplay readers (e.g. Battlefield damage numbers) query get_value/get_bool
## and listen to EventBus.settings_changed.

const PATH := "user://settings.cfg"
const SECTION := "settings"

const DEFAULTS := {
	"master": 80,
	"music": 60,
	"sfx": 90,
	"quality": "High",
	"vsync": true,
	"fullscreen": false,
	"dmg_numbers": true,
	"screen_shake": true,
	"boss_pause": false,
}

var _values: Dictionary = {}


func _ready() -> void:
	load_settings()
	apply()


func load_settings() -> void:
	_values = DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for key in DEFAULTS:
		_values[key] = cfg.get_value(SECTION, key, DEFAULTS[key])


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in _values:
		cfg.set_value(SECTION, key, _values[key])
	cfg.save(PATH)


func get_value(key: String) -> Variant:
	return _values.get(key, DEFAULTS.get(key))


func get_bool(key: String) -> bool:
	return bool(_values.get(key, DEFAULTS.get(key, false)))


func set_value(key: String, value: Variant) -> void:
	_values[key] = value
	save_settings()
	apply()
	EventBus.settings_changed.emit()


func restore_defaults() -> void:
	_values = DEFAULTS.duplicate()
	save_settings()
	apply()
	EventBus.settings_changed.emit()


## Push the engine-level preferences into the runtime.
func apply() -> void:
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if get_bool("vsync") else DisplayServer.VSYNC_DISABLED)
	var win := get_window()
	if win != null:
		var fullscreen := get_bool("fullscreen")
		var is_fs := win.mode == Window.MODE_FULLSCREEN or win.mode == Window.MODE_EXCLUSIVE_FULLSCREEN
		if fullscreen and not is_fs:
			win.mode = Window.MODE_FULLSCREEN
		elif not fullscreen and is_fs:
			win.mode = Window.MODE_WINDOWED
	# Master volume: 0–100 slider → dB on the Master bus (0 = silence).
	var master := float(get_value("master")) / 100.0
	AudioServer.set_bus_mute(0, master <= 0.001)
	if master > 0.001:
		AudioServer.set_bus_volume_db(0, linear_to_db(master))
