extends Control
## Dev utility (not part of the game): run windowed with
##   godot --path . res://test/CaptureShots.tscn
## Boots the real scenes, drives a fresh-profile Login → class pick →
## battlefield with chests and the mythic ribbon, saving PNGs to
## res://_shots/ (gitignored). Never calls save_game, so the on-disk
## profile is untouched.

const _LoginScene := preload("res://scenes/login/Login.tscn")
const _MainScene := preload("res://scenes/main/Main.tscn")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	DirAccess.make_dir_recursive_absolute("res://_shots")
	call_deferred("_run")


func _run() -> void:
	# --- 1) Fresh profile → Login class picker ---
	GameState.reset_to_defaults()
	var login := _LoginScene.instantiate() as Control
	add_child(login)
	await get_tree().create_timer(1.2).timeout
	await _snap("01_login_fresh")

	login.call("_select", "warrior")
	await get_tree().create_timer(0.8).timeout
	await _snap("02_login_warrior_selected")
	login.call("_select", "rogue")
	await get_tree().create_timer(0.8).timeout
	await _snap("03_login_rogue_selected")
	login.queue_free()
	await get_tree().process_frame

	# --- 2) Profile chosen → Fight with props/chests/ribbon ---
	GameState.choose_class("warrior", "Shotbot")
	var main := _MainScene.instantiate() as Control
	add_child(main)
	await get_tree().create_timer(3.0).timeout
	await _snap("04_battlefield_early")

	# Collect the welcome-back popup the way a player would (Enter hotkey).
	var ev := InputEventKey.new()
	ev.keycode = KEY_ENTER
	ev.pressed = true
	Input.parse_input_event(ev)

	# Chests spawn from t≈8s; give the field time, then announce a mythic.
	await get_tree().create_timer(9.5).timeout
	EventBus.mythic_announced.emit("Vael", "Crown of the Last Ember")
	await get_tree().create_timer(1.0).timeout
	await _snap("05_battlefield_chest_ribbon")

	# --- 3) Party Finder, joined state (mock world) ---
	var listing: Dictionary = await BackendClient.party_list()
	var open: Array = listing["data"]["parties"]
	if not open.is_empty():
		await BackendClient.party_join(String((open[0] as Dictionary)["id"]))
	var cover := ColorRect.new()
	cover.color = Palette.BG_0
	add_child(cover)
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var finder := preload("res://scenes/party/PartyFinder.tscn").instantiate() as Control
	add_child(finder)
	finder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await get_tree().create_timer(1.2).timeout
	await _snap("06_party_finder_joined")
	await BackendClient.party_leave()  # clears the mock party from netstate

	print("CAPTURE_DONE")
	get_tree().quit()


func _snap(shot: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://_shots/%s.png" % shot)
	print("SHOT %s %dx%d" % [shot, img.get_width(), img.get_height()])
