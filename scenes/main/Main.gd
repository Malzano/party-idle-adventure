extends Control
## Root of the app (main window). Permanently hosts the FIGHT scene — the one
## screen that can never be closed — plus the persistent nav rail and the
## top-right resource strip. Camp / Hero / Leaderboard open as separate OS
## windows via WindowManager (all can be open at once). Closing the main
## window autosaves and quits.

const _NavRailScene := preload("res://scenes/ui/NavRail.tscn")
const _ResourceStripScene := preload("res://scenes/ui/ResourceStrip.tscn")
const _FightScene := preload("res://scenes/fight/Fight.tscn")

var _nav_rail: Control


func _ready() -> void:
	get_tree().auto_accept_quit = false  # save on close (CLAUDE.md §3)
	_build()
	# The main window hosts the Fight HUD / nav rail / strip in project design
	# space — register it so the tutorial overlay can spotlight those controls,
	# then auto-run the first-session tour for a brand-new delver.
	TutorialOverlay.set_main_host(self)
	TutorialOverlay.maybe_autostart()


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Palette.BG_0
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Fight battlefield fills everything right of the rail.
	var fight := _FightScene.instantiate() as Control
	fight.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fight.offset_left = Palette.RAIL_W
	add_child(fight)

	# Persistent rail (left, full height) above the battlefield.
	_nav_rail = _NavRailScene.instantiate() as Control
	_nav_rail.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_nav_rail.offset_right = Palette.RAIL_W
	add_child(_nav_rail)

	# Floating resource strip, top-right (above the fight HUD).
	var strip := _ResourceStripScene.instantiate() as Control
	add_child(strip)
	strip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	strip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	strip.offset_top = 14
	strip.offset_right = -16
	strip.offset_left = -16


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		SaveManager.save_game()
		get_tree().quit()
