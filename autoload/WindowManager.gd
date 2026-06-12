extends Node
## Multi-window manager. The MAIN window permanently hosts the Fight scene
## (it cannot be closed in-app; closing it quits the game with an autosave —
## Main.gd handles that). Camp, Hero, and Leaderboard each open in their own
## OS window, all of which can be open simultaneously and closed freely.
##
## Windows are created once and hidden on close so per-window UI state
## (selected tabs, talent pan/zoom) survives reopening.

const WIN_CAMP := "camp"
const WIN_HERO := "hero"
const WIN_LEADERBOARD := "leaderboard"
const WIN_PARTY := "party"

# Titlebars compose as "<title> — GameContent.GAME_TITLE" in _create().
const _DEFS := {
	WIN_CAMP: {
		"title": "Hollowreach Camp",
		"scene": "res://scenes/camp/Camp.tscn",
		"size": Vector2i(1600, 900),
		"strip": true,
	},
	WIN_HERO: {
		"title": "Hero",
		"scene": "res://scenes/hero/Hero.tscn",
		"size": Vector2i(1600, 900),
		"strip": true,
	},
	WIN_LEADERBOARD: {
		"title": "Global Rankings",
		"scene": "res://scenes/leaderboard/Leaderboard.tscn",
		"size": Vector2i(1480, 900),
		"strip": false,
	},
	WIN_PARTY: {
		"title": "Party Finder",
		"scene": "res://scenes/party/PartyFinder.tscn",
		"size": Vector2i(1480, 900),
		"strip": false,
	},
}

const _ResourceStripScene := preload("res://scenes/ui/ResourceStrip.tscn")

var _windows: Dictionary = {}  # id -> Window


## Open the window (creating it on first use) or focus it if already open.
func open(id: String) -> void:
	if not _DEFS.has(id):
		push_warning("WindowManager: unknown window id '%s'" % id)
		return
	var w: Window = _windows.get(id)
	if w == null:
		w = _create(id)
		_windows[id] = w
	if w.visible:
		w.grab_focus()
		return
	w.show()
	w.grab_focus()
	EventBus.window_state_changed.emit(id, true)


## Toggle semantics for the nav rail: open if closed, focus if open.
func toggle(id: String) -> void:
	open(id)


func close(id: String) -> void:
	var w: Window = _windows.get(id)
	if w != null and w.visible:
		w.hide()
		EventBus.window_state_changed.emit(id, false)


func is_open(id: String) -> bool:
	var w: Window = _windows.get(id)
	return w != null and w.visible


## Focus the main (Fight) window.
func focus_main() -> void:
	get_tree().root.grab_focus()


func _create(id: String) -> Window:
	var def: Dictionary = _DEFS[id]
	var w := Window.new()
	w.title = "%s — %s" % [def["title"], GameContent.GAME_TITLE]
	w.size = def["size"]
	w.min_size = Vector2i(960, 540)
	w.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	w.transient = false
	w.exclusive = false
	w.visible = false
	w.close_requested.connect(func() -> void: close(id))
	get_tree().root.add_child(w)

	# Backdrop covering the whole window (including letterbox bars).
	var bg := ColorRect.new()
	bg.color = Palette.BG_0
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	w.add_child(bg)

	# Fixed 1920×1080 design-space stage, manually scale-to-fit (the same
	# approach as the design prototype's useScale). Window.content_scale_* is
	# bypassed entirely — the stage gives every screen a stable layout space.
	var stage := Control.new()
	stage.mouse_filter = Control.MOUSE_FILTER_PASS
	w.add_child(stage)
	stage.size = Vector2(1920, 1080)

	# Screen content.
	var scene := load(def["scene"]) as PackedScene
	if scene != null:
		var content := scene.instantiate() as Control
		stage.add_child(content)
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Floating resource strip, top-right (camp + hero), inset 16/14.
	if def["strip"]:
		var strip := _ResourceStripScene.instantiate() as Control
		stage.add_child(strip)
		strip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		strip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		strip.offset_top = 14
		strip.offset_right = -16
		strip.offset_left = -16

	var fit := func() -> void:
		var ws := Vector2(w.size)
		var s := minf(ws.x / 1920.0, ws.y / 1080.0)
		stage.scale = Vector2(s, s)
		stage.position = (ws - Vector2(1920, 1080) * s) * 0.5
	w.size_changed.connect(fit)
	fit.call()

	# Per-window hotkeys (1/2/3/L + Esc-to-close fallback).
	var keys := _PopupKeys.new()
	keys.window_id = id
	w.add_child(keys)
	return w


## Per-popup unhandled-key handler. Screens inside the window get first chance
## (children handle unhandled input before parents/siblings added earlier);
## anything they consume never reaches this node.
class _PopupKeys:
	extends Node

	var window_id: String = ""

	func _unhandled_key_input(event: InputEvent) -> void:
		var k := event as InputEventKey
		if k == null or not k.pressed or k.echo:
			return
		match k.keycode:
			KEY_1:
				WindowManager.open(WindowManager.WIN_CAMP)
			KEY_2:
				WindowManager.focus_main()
			KEY_3:
				WindowManager.open(WindowManager.WIN_HERO)
			KEY_L:
				WindowManager.open(WindowManager.WIN_LEADERBOARD)
			KEY_P:
				WindowManager.open(WindowManager.WIN_PARTY)
			KEY_ESCAPE:
				WindowManager.close(window_id)
