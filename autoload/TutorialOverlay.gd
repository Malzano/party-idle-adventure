extends Node
## First-session spotlight tutorial controller (autoload). Drives a 14-step
## coachmark tour: dim the active window, spotlight one real control, show a
## wording box, and advance by Next or by the player DOING the thing (changing
## speed, toggling auto-skill, opening HERO/CAMP, equipping gear).
##
## Ported from the Claude Design handoff (tutorial.jsx / tutorial.css), adapted
## to the multi-OS-window shell: the visual TutorialLayer is mounted into the
## design-space host of whichever window owns the current step's target — Main
## for the Fight HUD / nav rail / resource strip; the popup `stage` for Hero and
## Camp — and target rects are converted through that host's transform so the
## spotlight tracks at any resolution / window size.
##
## Persistence: a tiny user://tutorial.json {"done": bool}. SaveManager's
## DEV_FRESH_START wipes it (alongside the save/netstate), so the tour replays on
## a clean editor boot; in shipped builds it persists, so the tour auto-runs only
## once. Settings → "Replay Tutorial" calls start() any time.

const FLAG_PATH := "user://tutorial.json"
const _Layer := preload("res://scenes/ui/TutorialLayer.gd")
const _POLL := 0.1  # re-measure cadence (tracks moving targets + layout settle)

# Anchor registry: string key -> Control (validated on use).
var _anchors: Dictionary = {}
var _main_host: Control = null

var _active := false
var _step := 0
var _done := false
# A TutorialLayer instance. Left untyped (Variant) so this autoload doesn't pull
# the new global-class into its compile graph, and so its layer-specific methods
# (render / hide_all / signals) dispatch dynamically.
var _layer = null
var _init_skill: bool = false       # captured auto-skill state for step 7
var _eff_mode := "next"             # effective mode (may downgrade do→next)
var _eff_advance := ""              # effective advance-by-doing trigger
var _accum := 0.0

# The 14 beats — verbatim copy from the design handoff. target keys resolve via
# the anchor registry; advance_on maps to an EventBus signal handled below.
const STEPS: Array = [
	{"screen": "fight", "mode": "intro", "prefer": "center", "targets": [], "big": true,
		"headline": "The delve never stops", "cta": "Begin ›",
		"body": "Delver, your party fights without you — day and night, even when the game is shut. Watch them carve forward."},
	{"screen": "fight", "mode": "next", "prefer": "below", "targets": ["fight.battlefield"], "frac": [0.28, 0.34, 0.36, 0.30],
		"headline": "Blood and mercy",
		"body": "Cream numbers are damage, ember crits bite deepest, green is healing. Every strike is real math, not theatre."},
	{"screen": "fight", "mode": "next", "prefer": "below", "targets": ["fight.wavebar"],
		"headline": "Five waves to glory",
		"body": "Each stage is five waves. Fill this bar to push the boss and break into the next stage."},
	{"screen": "fight", "mode": "next", "prefer": "below", "targets": ["fight.dps"],
		"headline": "Your killing speed",
		"body": "This is how fast your party deals death. Raise it with gear and talents — higher means deeper, faster."},
	{"screen": "fight", "mode": "next", "prefer": "above", "targets": ["fight.heroframe"],
		"headline": "Watch their vitals",
		"body": "Your delver's life and mana ride these bars. If the red runs dry, the advance stalls."},
	{"screen": "fight", "mode": "do", "prefer": "above", "targets": ["fight.speed"], "advance_on": "speed4",
		"headline": "Bend the clock", "hint": "▸ Tap 4× to continue",
		"body": "Click to fast-forward the carnage — 1×, 2×, 4×. Try 4× now and watch the bodies fall faster."},
	{"screen": "fight", "mode": "do", "prefer": "above", "targets": ["fight.autoskill"], "advance_on": "autoskill",
		"headline": "Hands off the reins", "hint": "▸ Toggle Auto-Skill to continue",
		"body": "With Auto-Skill lit, your abilities fire themselves. This is an idle crawl — let it run."},
	{"screen": "fight", "mode": "next", "prefer": "below", "targets": ["strip.level"],
		"headline": "Your mark on the world",
		"body": "Your name, level, and renown sit here. Slain foes feed this bar — and your rank."},
	{"screen": "fight", "mode": "next", "prefer": "below", "targets": ["strip.gold"],
		"headline": "The coin of the dead",
		"body": "Gold pours in from every kill. You'll spend it at the forge and on the road to power."},
	{"screen": "fight", "mode": "do", "prefer": "right", "targets": ["nav.hero"], "advance_on": "hero_open",
		"headline": "Tend your delver", "hint": "▸ Open HERO to continue",
		"body": "Press 3 or click HERO. Loot means nothing until it's worn — let's arm you."},
	{"screen": "profile", "hero_tab": 0, "mode": "do", "prefer": "left", "arrow": true,
		"targets": ["hero.inventory", "hero.gearslot"], "advance_on": "equip",
		"headline": "Drag it onto your bones", "hint": "▸ Equip a bag item to continue",
		"body": "Drag a piece of gear from the bag onto its slot. Feel your power climb."},
	{"screen": "profile", "mode": "next", "prefer": "below", "targets": ["hero.talents"],
		"headline": "Carve your path",
		"body": "The talent web waits here — spend points to twist your build toward ruin or resilience. Explore it later."},
	{"screen": "fight", "mode": "do", "prefer": "right", "targets": ["nav.camp"], "advance_on": "camp_open",
		"headline": "Return to the fire", "hint": "▸ Open CAMP to continue",
		"body": "Press 1 or click CAMP. Between delves, the camp is where you grow stronger."},
	{"screen": "camp", "mode": "finish", "prefer": "below", "targets": ["camp.altar"], "cta": "Finish ✦", "skip_label": "Skip",
		"headline": "Summon greater arms",
		"body": "The altar trades soulstones for gear from beyond. Save your pulls, then push deeper, delver. The dark won't wait."},
]


func _ready() -> void:
	set_process(false)
	_done = _load_done()
	EventBus.sim_speed_changed.connect(_on_speed)
	EventBus.sim_toggles_changed.connect(_on_toggles)
	EventBus.equipment_changed.connect(_on_equip)
	EventBus.window_state_changed.connect(_on_window_state)


# --- public API -------------------------------------------------------------

## A screen registers a spotlightable control under a stable key. Idempotent;
## last registration wins (re-run safely after a rebuild).
func register_anchor(key: String, control: Control) -> void:
	_anchors[key] = control


## Main registers its root as the design-space host for the Fight HUD / nav /
## strip (the main window uses project canvas_items stretch, not a manual stage).
func set_main_host(host: Control) -> void:
	_main_host = host


func is_done() -> bool:
	return _done


## Auto-run once for a brand-new delver (after class select → Main).
func maybe_autostart() -> void:
	if _done or _active or not GameState.has_profile():
		return
	get_tree().create_timer(0.9).timeout.connect(func() -> void:
		if not _done and not _active:
			start())


## Begin (or replay) the tour from step 1.
func start() -> void:
	_step = 0
	_active = true
	_ensure_layer()
	set_process(true)
	_show_step()


# --- step flow --------------------------------------------------------------

func _show_step() -> void:
	var s: Dictionary = STEPS[_step]
	# Effective mode: a "do" step with no possible action (empty bag on the equip
	# step) downgrades to a plain Next so the player can never get stuck.
	_eff_mode = String(s.get("mode", "next"))
	_eff_advance = String(s.get("advance_on", ""))
	if _eff_advance == "equip" and _bag_empty():
		_eff_mode = "next"
		_eff_advance = ""

	if _eff_advance == "autoskill":
		_init_skill = CombatSim.auto_skill

	_navigate(s)
	_accum = _POLL  # force an immediate render next tick
	_render_current()


## Bring the target's window forward / open it (and the right Hero tab).
func _navigate(s: Dictionary) -> void:
	match String(s.get("screen", "fight")):
		"profile":
			if s.has("hero_tab"):
				WindowManager.open_hero_tab(int(s["hero_tab"]))
			else:
				WindowManager.open(WindowManager.WIN_HERO)
		"camp":
			WindowManager.open(WindowManager.WIN_CAMP)
		_:
			WindowManager.focus_main()


func _render_current() -> void:
	if not _active or _layer == null:
		return
	var s: Dictionary = STEPS[_step]
	var screen := String(s.get("screen", "fight"))
	var host := _host_for(screen)
	# Re-open a popup the player closed mid-step (cheap; no-op if already open).
	if host == null:
		if screen == "profile" and not WindowManager.is_open(WindowManager.WIN_HERO):
			WindowManager.open(WindowManager.WIN_HERO)
		elif screen == "camp" and not WindowManager.is_open(WindowManager.WIN_CAMP):
			WindowManager.open(WindowManager.WIN_CAMP)
		host = _host_for(screen)
	if host == null:
		return
	if _layer.get_parent() != host:
		_mount_into(host)

	var hole: Variant = _resolve_rect(s, 0, host)
	var sec: Variant = _resolve_rect(s, 1, host)
	var intro := _eff_mode == "intro"
	_layer.render({
		"alpha": 0.66 if intro else 0.78,
		"hole": hole,
		"sec": sec,
		"arrow": bool(s.get("arrow", false)),
		"prefer": String(s.get("prefer", "below")),
		"headline": String(s.get("headline", "")),
		"body": String(s.get("body", "")),
		"mode": _eff_mode,
		"cta": String(s.get("cta", "Next ›")),
		"hint": String(s.get("hint", "▸ Do it to continue")),
		"skip_label": String(s.get("skip_label", "Skip tour")),
		"big": bool(s.get("big", false)),
		"step_idx": _step,
		"total": STEPS.size(),
	})


func _process(delta: float) -> void:
	if not _active:
		return
	_accum += delta
	if _accum >= _POLL:
		_accum = 0.0
		_render_current()


func _advance() -> void:
	if not _active:
		return
	var n := _step + 1
	if n >= STEPS.size():
		_complete()
	else:
		_step = n
		_show_step()


func _on_next() -> void:
	if _active and _eff_mode != "do":
		_advance()


func _on_skip() -> void:
	_complete()


func _complete() -> void:
	_active = false
	set_process(false)
	if _layer != null:
		_layer.hide_all()
		if _layer.get_parent() != null:
			_layer.get_parent().remove_child(_layer)
	_done = true
	_save_done()


# --- advance-by-doing -------------------------------------------------------

func _on_speed(speed: int) -> void:
	if _active and _eff_advance == "speed4" and speed >= 4:
		_advance()


func _on_toggles(auto_skill: bool, _auto_advance: bool) -> void:
	if _active and _eff_advance == "autoskill" and auto_skill != _init_skill:
		_advance()


func _on_equip() -> void:
	if _active and _eff_advance == "equip":
		_advance()


func _on_window_state(id: String, open: bool) -> void:
	if not _active or not open:
		return
	if _eff_advance == "hero_open" and id == WindowManager.WIN_HERO:
		_advance()
	elif _eff_advance == "camp_open" and id == WindowManager.WIN_CAMP:
		_advance()


# --- geometry helpers -------------------------------------------------------

func _host_for(screen: String) -> Control:
	match screen:
		"profile":
			return WindowManager.get_stage(WindowManager.WIN_HERO)
		"camp":
			return WindowManager.get_stage(WindowManager.WIN_CAMP)
		_:
			return _main_host


func _ensure_layer() -> void:
	if _layer == null or not is_instance_valid(_layer):
		_layer = _Layer.new()
		_layer.next_pressed.connect(_on_next)
		_layer.skip_pressed.connect(_on_skip)


func _mount_into(host: Control) -> void:
	if _layer.get_parent() == host:
		return
	if _layer.get_parent() != null:
		_layer.get_parent().remove_child(_layer)
	host.add_child(_layer)
	_layer.position = Vector2.ZERO
	_layer.size = Vector2(1920, 1080)
	_layer.move_to_front()


## Resolve target #idx for step `s` into host (design) space. Returns Rect2|null.
func _resolve_rect(s: Dictionary, idx: int, host: Control) -> Variant:
	var targets: Array = s.get("targets", [])
	if idx >= targets.size():
		return null
	var c := _anchor(String(targets[idx]))
	if c == null:
		return null
	var inv := host.get_global_transform().affine_inverse()
	var gr := c.get_global_rect()
	var p: Vector2 = inv * gr.position
	var e: Vector2 = inv * gr.end
	var r := Rect2(p, e - p).abs()
	if idx == 0 and s.has("frac"):
		var f: Array = s["frac"]
		r = Rect2(
			r.position.x + r.size.x * float(f[0]),
			r.position.y + r.size.y * float(f[1]),
			r.size.x * float(f[2]),
			r.size.y * float(f[3]))
	return r


func _anchor(key: String) -> Control:
	var c: Variant = _anchors.get(key)
	# is_instance_valid FIRST — `is Control` on a freed instance throws.
	if is_instance_valid(c) and c is Control and c.is_inside_tree() and c.is_visible_in_tree():
		return c
	return null


func _bag_empty() -> bool:
	var bag: Variant = GameState.get("bag_equipment")
	return not (bag is Array) or (bag as Array).is_empty()


# --- persistence ------------------------------------------------------------

func _load_done() -> bool:
	if not FileAccess.file_exists(FLAG_PATH):
		return false
	var f := FileAccess.open(FLAG_PATH, FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed is Dictionary and bool((parsed as Dictionary).get("done", false))


func _save_done() -> void:
	var f := FileAccess.open(FLAG_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"done": _done}))
	f.close()
