extends Node
## Deterministic tick-based combat simulation (CLAUDE.md §3).
##
## Runs at TICK_RATE logical ticks per second; the speed toggle (1×/2×/4×)
## only changes how many ticks are processed per real second. All combat
## outcomes (wave/stage progress, gold, XP, levels, loot, party vitals) are
## decided here; the Fight screen is a pure presentation layer reading the
## signals on EventBus. The same step logic powers offline progress, so
## "away gains" are literally the sim advanced N ticks.

const TICK_RATE := 10.0  # logical ticks per second
const WAVES_PER_STAGE := 5

## Per-tick tuning (at 10 ticks/sec these reproduce the design's pacing:
## wave fill ~1.4%/220ms at 2× in the mockup → ~0.32%/tick at 1×).
const WAVE_FILL_PER_TICK := 0.318
const GOLD_PER_WAVE := 460
const XP_PER_WAVE := 140
const FLOATER_CHANCE_PER_TICK := 0.22
const LOOT_INTERVAL_TICKS := 21.0  # ≈2.1 s at 1×
const ENERGY_REGEN_SECONDS := 300.0  # +1 energy / 5 min

var speed: int = 2:
	set(v):
		speed = clampi(v, 1, 4)
		EventBus.sim_speed_changed.emit(speed)
var auto_skill: bool = true:
	set(v):
		auto_skill = v
		EventBus.sim_toggles_changed.emit(auto_skill, auto_advance)
var auto_advance: bool = true:
	set(v):
		auto_advance = v
		EventBus.sim_toggles_changed.emit(auto_skill, auto_advance)

## Live battle state (presentation reads these freely).
var act: int = 4
var stage: int = 7
var wave: int = 3
var wave_fill: float = 38.0
var stage_name: String = "The Sunken Reliquary"
var party_dps_label: String = "4.82M"

## Party vitals as percentages (index-aligned with GameContent.PARTY).
var party_hp: Array[float] = []
var party_mana: Array[float] = []

## Pending offline rewards computed at startup ({} when none).
var offline_rewards: Dictionary = {}

var _accum: float = 0.0
var _loot_cooldown: float = LOOT_INTERVAL_TICKS
var _energy_accum: float = 0.0
var _vitals_dirty_ticks: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 0x6D2B79F5  # fixed seed: deterministic flavor rolls
	for h in GameContent.PARTY:
		party_hp.append(float(h["hp"]))
		party_mana.append(float(h["mana"]))
	# SaveManager (earlier in autoload order) has loaded the profile by now.
	act = GameState.act
	stage = GameState.stage
	stage_name = GameContent.STAGE_NAMES[(stage - 1) % GameContent.STAGE_NAMES.size()]
	_compute_offline()


func _process(delta: float) -> void:
	_accum += delta * TICK_RATE * float(speed)
	while _accum >= 1.0:
		_accum -= 1.0
		_tick()
	# Energy regen runs on real time, independent of combat speed.
	_energy_accum += delta
	if _energy_accum >= ENERGY_REGEN_SECONDS:
		_energy_accum -= ENERGY_REGEN_SECONDS
		if GameState.energy < GameState.energy_max:
			GameState.energy += 1
			EventBus.currencies_changed.emit()


## One logical tick: advance the wave, roll floaters/heals, drip loot.
func _tick() -> void:
	# Wave progress.
	wave_fill += WAVE_FILL_PER_TICK
	if wave_fill >= 100.0:
		wave_fill = 0.0
		_on_wave_cleared()
	EventBus.sim_wave_progress.emit(wave_fill)

	# Floating combat numbers (damage erupts at the clash zone; heals on party).
	if _rng.randf() < FLOATER_CHANCE_PER_TICK:
		var heal := _rng.randf() < 0.22
		if heal:
			var idx := _rng.randi_range(0, party_hp.size() - 1)
			var amount := 200 + _rng.randi_range(0, 599)
			party_hp[idx] = minf(100.0, party_hp[idx] + 2.0)
			EventBus.sim_floater.emit("heal", amount, idx)
		else:
			var crit := _rng.randf() < 0.28
			var amount := (4000 + _rng.randi_range(0, 8999)) if crit else (600 + _rng.randi_range(0, 2399))
			EventBus.sim_floater.emit("crit" if crit else "dmg", amount, -1)

	# Party vitals drift: chip damage + mana churn, healer keeps up.
	for i in party_hp.size():
		party_hp[i] = clampf(party_hp[i] + _rng.randf_range(-0.8, 0.72), 34.0, 100.0)
		party_mana[i] = clampf(party_mana[i] + _rng.randf_range(-1.1, 1.06), 18.0, 100.0)
	_vitals_dirty_ticks += 1
	if _vitals_dirty_ticks >= 3:
		_vitals_dirty_ticks = 0
		EventBus.sim_party_vitals.emit(party_hp, party_mana)

	# Auto-loot drip.
	_loot_cooldown -= 1.0
	if _loot_cooldown <= 0.0:
		_loot_cooldown = LOOT_INTERVAL_TICKS
		var entry: Array = GameContent.LOOT_FEED[_rng.randi_range(0, GameContent.LOOT_FEED.size() - 1)]
		EventBus.sim_loot.emit(entry)


func _on_wave_cleared() -> void:
	GameState.add_gold(GOLD_PER_WAVE)
	GameState.add_xp(XP_PER_WAVE)
	if wave >= WAVES_PER_STAGE:
		wave = 1
		if auto_advance:
			_advance_stage()
	else:
		wave += 1
	EventBus.sim_wave_changed.emit(wave)


func _advance_stage() -> void:
	stage += 1
	if stage > 50:
		stage = 1
		act += 1
	GameState.act = act
	GameState.stage = stage
	GameState.max_stage = maxi(GameState.max_stage, act * 100 + stage)
	stage_name = GameContent.STAGE_NAMES[(stage - 1) % GameContent.STAGE_NAMES.size()]
	EventBus.sim_stage_changed.emit(stage_label(), stage_name)


## "4-7"-style stage label.
func stage_label() -> String:
	return "%d-%d" % [act, stage]


## Retreat: fall back one stage and restart the wave cycle.
func retreat() -> void:
	stage = maxi(1, stage - 1)
	GameState.stage = stage
	wave = 1
	wave_fill = 0.0
	stage_name = GameContent.STAGE_NAMES[(stage - 1) % GameContent.STAGE_NAMES.size()]
	EventBus.sim_stage_changed.emit(stage_label(), stage_name)
	EventBus.sim_wave_changed.emit(wave)


## Team Aura: optimal = exactly 1 tank + 1 healer + 2 DPS of different classes.
func team_aura_optimal() -> bool:
	var tanks := 0
	var healers := 0
	var dps_classes := {}
	for h in GameContent.PARTY:
		match String(h["role"]):
			"tank":
				tanks += 1
			"healer":
				healers += 1
			_:
				dps_classes[h["cls"]] = true
	return tanks == 1 and healers == 1 and dps_classes.size() == 2

# ---------------------------------------------------------------------------
# Offline progress (CLAUDE.md §3): elapsed → ticks → same per-tick rewards.
# ---------------------------------------------------------------------------

func _compute_offline() -> void:
	var seconds := GameState.pending_offline_seconds
	GameState.pending_offline_seconds = 0
	if seconds < 60:
		return
	offline_rewards = simulate_offline(seconds)


## Headless fast-forward of [param seconds] of combat at 1× speed. Pure math
## over the same per-tick constants, so it matches what the live sim would do.
func simulate_offline(seconds: int) -> Dictionary:
	var ticks := float(seconds) * TICK_RATE
	var waves := int(ticks * WAVE_FILL_PER_TICK / 100.0)
	var gold := waves * GOLD_PER_WAVE
	var xp_total := waves * XP_PER_WAVE
	var levels := 0
	# Apply XP curve without mutating state (collect does that).
	var xp_probe := GameState.xp
	var need := GameState.xp_to_next
	while xp_total > 0 and levels < 999:
		var room := need - xp_probe
		if xp_total >= room:
			xp_total -= room
			xp_probe = 0
			need = int(float(need) * 1.15)
			levels += 1
		else:
			xp_probe += xp_total
			xp_total = 0
	var items := int(ticks / LOOT_INTERVAL_TICKS / 14.0)  # rare-ish keepers only
	return {
		"seconds": seconds,
		"gold": gold,
		"levels": levels,
		"items": items,
		"waves": waves,
	}


## Apply pending offline rewards to the profile (Collect button).
func collect_offline() -> void:
	if offline_rewards.is_empty():
		return
	GameState.add_gold(int(offline_rewards["gold"]))
	for i in int(offline_rewards["levels"]):
		GameState.level_up()
	offline_rewards = {}
	EventBus.rewards_collected.emit({})
	EventBus.currencies_changed.emit()


## Human-readable "2h 14m" for the welcome-back popup.
static func format_away(seconds: int) -> String:
	var h := seconds / 3600
	var m := (seconds % 3600) / 60
	if h > 0:
		return "%dh %02dm" % [h, m]
	return "%dm" % m
