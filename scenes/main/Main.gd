extends Control
## Root of the app (CLAUDE.md §4). Holds the persistent Grimhollow shell — the
## left icon rail and the floating top-right resource strip — over a screen host
## that swaps between Camp / Fight / Hero. Owns autosave-on-exit so the
## last-played timestamp stays fresh.

const _ResourceStripScene := preload("res://scenes/ui/ResourceStrip.tscn")
const _NavRailScene := preload("res://scenes/ui/NavRail.tscn")

# Keys mirror the GameState.SCREEN_* constants (literals here because autoload
# constants aren't available in a compile-time const initializer).
const _SCREEN_SCENES := {
	"camp": "res://scenes/camp/Camp.tscn",
	"fight": "res://scenes/fight/Fight.tscn",
	"hero": "res://scenes/hero/Hero.tscn",
}

var _nav_rail: Control
var _screen_host: Control
var _screens: Dictionary = {}  # screen id (String) -> Control instance
var _active_screen: Control = null


func _ready() -> void:
	# Save when the window's close button is pressed (CLAUDE.md §3 timestamp).
	get_tree().auto_accept_quit = false
	_build_shell()
	_instance_screens()
	_nav_rail.select(GameState.SCREEN_CAMP)


func _build_shell() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# Deepest stage background (.stage bg-0).
	var bg := ColorRect.new()
	bg.color = Palette.BG_0
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Screen host fills the area to the right of the rail.
	_screen_host = Control.new()
	_screen_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen_host.offset_left = Palette.RAIL_W
	_screen_host.clip_contents = true
	add_child(_screen_host)

	# Vignette overlay above the screens, below the chrome (.vignette).
	add_child(_make_vignette())

	# Left rail, full height.
	_nav_rail = _NavRailScene.instantiate() as Control
	_nav_rail.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_nav_rail.offset_right = Palette.RAIL_W
	add_child(_nav_rail)

	# Floating resource strip, pinned top-right via a transparent top row.
	var strip_row := HBoxContainer.new()
	strip_row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	strip_row.offset_left = Palette.RAIL_W
	strip_row.offset_right = -16
	strip_row.offset_top = 14
	strip_row.offset_bottom = 14 + Palette.STRIP_H
	strip_row.alignment = BoxContainer.ALIGNMENT_END
	strip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(strip_row)

	var strip := _ResourceStripScene.instantiate() as Control
	strip_row.add_child(strip)

	EventBus.screen_changed.connect(_on_screen_changed)


## Soft radial darkening at the edges (.vignette). Built procedurally so there's
## no texture asset to manage.
func _make_vignette() -> Control:
	var tex := GradientTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.42)
	tex.fill_to = Vector2(1.05, 1.0)
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0))
	grad.set_color(1, Color(0, 0, 0, 0.55))
	grad.set_offset(0, 0.52)
	grad.set_offset(1, 1.0)
	tex.gradient = grad

	var rect := TextureRect.new()
	rect.texture = tex
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## Instance all three screens up front and keep them resident; switching just
## toggles visibility. Cheap for three screens and preserves per-screen state.
func _instance_screens() -> void:
	for id in _SCREEN_SCENES:
		var scene := load(_SCREEN_SCENES[id]) as PackedScene
		var screen := scene.instantiate() as Control
		screen.set_anchors_preset(Control.PRESET_FULL_RECT)
		screen.visible = false
		_screen_host.add_child(screen)
		_screens[id] = screen


func _on_screen_changed(screen: String) -> void:
	var next := _screens.get(screen) as Control
	if next == null or next == _active_screen:
		return
	if _active_screen != null:
		_active_screen.visible = false
	next.visible = true
	_active_screen = next


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		SaveManager.save_game()
		get_tree().quit()
