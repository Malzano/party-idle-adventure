extends "res://scenes/camp/ModalShell.gd"
## Run-over summary ("All Tuckered Out!"): final score/bonks/stage/time, then
## finalize with the backend (records the score + collects the Goodie Bag into
## the bag) and shows the Stampede Rankings. TRY AGAIN restarts the run;
## BACK TO LOADOUT returns to the backpack screen.

signal retry_requested
signal loadout_requested

var run_score: int = 0
var run_kills: int = 0
var run_stage: int = 1
var run_time: float = 0.0

var _status_lbl: Label
var _drops_box: VBoxContainer
var _board_box: VBoxContainer


func _build_body(body: VBoxContainer) -> void:
	var sub := Style.body_label("You fought bravely — time for a nap and a snack.", 13, Palette.TX_MUTE)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(sub)

	# Headline stats.
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 2)
	body.add_child(grid)
	_stat(grid, "SCORE", Style.group_int(run_score), Palette.EMBER_DEEP)
	_stat(grid, "BONKS", str(run_kills), Palette.GOLD_DIM)
	_stat(grid, "STAGE", str(run_stage), Palette.CYAN_DEEP)
	_stat(grid, "TIME", "%d:%02d" % [int(run_time) / 60, int(run_time) % 60], Palette.TX)

	body.add_child(_hr())

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	body.add_child(cols)

	# Drops collected.
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.custom_minimum_size = Vector2(320, 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	left.add_child(Style.display_label("GOODIE BAG", 14, Palette.GOLD_DIM))
	_status_lbl = Style.body_label("Collecting rewards…", 13, Palette.TX_MUTE)
	left.add_child(_status_lbl)
	_drops_box = VBoxContainer.new()
	_drops_box.add_theme_constant_override("separation", 4)
	left.add_child(_drops_box)

	# Leaderboard.
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.custom_minimum_size = Vector2(320, 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	right.add_child(Style.display_label("STAMPEDE RANKINGS", 14, Palette.GOLD_DIM))
	_board_box = VBoxContainer.new()
	_board_box.add_theme_constant_override("separation", 3)
	right.add_child(_board_box)

	body.add_child(_hr())

	# Actions.
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(actions)
	var retry := Style.make_button("TRY AGAIN", "ember", 13)
	retry.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	retry.pressed.connect(func() -> void:
		retry_requested.emit()
		closed.emit()
		queue_free())
	actions.add_child(retry)
	var ret := Style.make_button("BACK TO LOADOUT", "ghost", 13)
	ret.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	ret.pressed.connect(func() -> void:
		loadout_requested.emit()
		closed.emit()
		queue_free())
	actions.add_child(ret)

	call_deferred("_finalize")


func _finalize() -> void:
	var res: Dictionary = await BackendClient.survival_complete(run_score, run_kills, run_stage, run_time)
	var d: Dictionary = res.get("data", {})
	var drops: Array = d.get("drops", [])
	var gold := int(d.get("gold", 0))
	_status_lbl.text = "Banked %d drop%s · +%s coins" % [drops.size(), ("" if drops.size() == 1 else "s"), Style.group_int(gold)]
	for it in drops:
		var item: Dictionary = it
		var rar := String(item.get("r", "common"))
		var line := Style.body_label("◆ %s  (%s)" % [String(item.get("n", "?")), String(item.get("slot", ""))], 12, Palette.rarity_color(rar))
		_drops_box.add_child(line)
	if drops.is_empty():
		_drops_box.add_child(Style.body_label("(bag full — no room for spoils)", 12, Palette.TX_DIM))

	var lb: Dictionary = await BackendClient.survival_leaderboard("global")
	var entries: Array = lb.get("data", {}).get("entries", [])
	var your_rank := int(lb.get("data", {}).get("your_rank", 0))
	for i in mini(6, entries.size()):
		var e: Dictionary = entries[i]
		var mine := bool(e.get("you", false))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var rank := Style.pixel_label("#%d" % (i + 1), 11, Palette.GOLD_DIM if not mine else Palette.EMBER_BRIGHT)
		rank.custom_minimum_size = Vector2(40, 0)
		row.add_child(rank)
		var nm := Style.body_label(String(e.get("name", "?")), 12, Palette.EMBER_BRIGHT if mine else Palette.TX)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nm)
		var sc := int(e.get("score", e.get("survival", 0)))  # mock uses "score", server board "survival"
		row.add_child(Style.pixel_label(Style.group_int(sc), 11, Palette.CYAN_DEEP))
		_board_box.add_child(row)
	if your_rank > 0:
		_board_box.add_child(Style.body_label("You: rank #%d" % your_rank, 12, Palette.EMBER_BRIGHT))


func _stat(grid: GridContainer, label: String, value: String, color: Color) -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	var v := Style.pixel_label(value, 26, color)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(v)
	var l := Style.body_label(label, 10, Palette.TX_MUTE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(l)
	grid.add_child(col)


func _hr() -> ColorRect:
	var h := ColorRect.new()
	h.color = Color(0, 0, 0, 0.4)
	h.custom_minimum_size = Vector2(0, 1)
	return h
