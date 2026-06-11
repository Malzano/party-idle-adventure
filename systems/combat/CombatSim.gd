extends Node
## Deterministic tick-based combat simulation (CLAUDE.md §3).
##
## Runs at TICK_RATE logical ticks per second; the speed toggle (1×/2×/4×)
## only changes how many ticks are processed per real second. All combat
## outcomes are decided here and all the math is REAL: party DPS comes from
## PlayerStats (gear + talents + pets + relics + food + aura + roster), each
## wave is an enemy HP pool that grows per stage (Balance), and gold/XP apply
## the player's gold_find / xp_gain bonuses. The same per-wave math powers
## offline progress, so away-gains match what the live sim would have done.

const TICK_RATE := 10.0  # logical ticks per second

const FLOATER_CHANCE_PER_TICK := 0.22
const ENERGY_REGEN_SECONDS := 300.0  # fallback; Balance overrides

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
var wave: int = 1
var wave_pool: float = 1.0     # total HP of the current wave
var wave_damage: float = 0.0   # damage dealt into the current wave
var stage_name: String = "The Sunken Reliquary"
var party_dps: float = 0.0
var party_dps_label: String = "0"

## Party vitals as percentages (index-aligned with GameContent.PARTY).
var party_hp: Array[float] = []
var party_mana: Array[float] = []

## Pending offline rewards computed at startup ({} when none).
var offline_rewards: Dictionary = {}

var _accum: float = 0.0
var _loot_cooldown: float = 21.0
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
	GameState.check_daily_reset()
	_recompute_stats()
	_reset_wave()
	_loot_cooldown = Balance.num("rewards.loot_interval_ticks", 21.0)
	# Any loadout/talent/roster change re-prices the party.
	EventBus.talents_changed.connect(_recompute_stats)
	EventBus.loadout_changed.connect(_recompute_stats)
	EventBus.game_loaded.connect(_recompute_stats)
	_compute_offline()


func _recompute_stats() -> void:
	PlayerStats.invalidate()
	var profile := PlayerStats.compute()
	party_dps = float(profile["party_dps"])
	party_dps_label = String(profile["dps_label"])
	EventBus.sim_stats_changed.emit()


func _reset_wave() -> void:
	wave_pool = Balance.wave_pool(Balance.stage_index(act, stage))
	wave_damage = 0.0


func wave_fill() -> float:
	return clampf(wave_damage / wave_pool * 100.0, 0.0, 100.0)


func _process(delta: float) -> void:
	_accum += delta * TICK_RATE * float(speed)
	while _accum >= 1.0:
		_accum -= 1.0
		_tick()
	# Energy regen runs on real time, independent of combat speed.
	_energy_accum += delta
	var regen := Balance.num("energy.regen_seconds", ENERGY_REGEN_SECONDS)
	if _energy_accum >= regen:
		_energy_accum -= regen
		if GameState.energy < GameState.energy_max:
			GameState.energy += 1
			EventBus.currencies_changed.emit()


## One logical tick: deal damage into the wave pool, roll floaters, drip loot.
func _tick() -> void:
	GameState.check_daily_reset()

	var dmg := party_dps / TICK_RATE
	wave_damage += dmg
	GameState.daily_damage += dmg
	if wave_damage >= wave_pool:
		_on_wave_cleared()
	EventBus.sim_wave_progress.emit(wave_fill())

	# Floating combat numbers, scaled to real DPS so they read believably.
	if _rng.randf() < FLOATER_CHANCE_PER_TICK:
		var heal := _rng.randf() < 0.22
		if heal:
			var idx := _rng.randi_range(0, party_hp.size() - 1)
			var amount := 200 + _rng.randi_range(0, 599)
			party_hp[idx] = minf(100.0, party_hp[idx] + 2.0)
			EventBus.sim_floater.emit("heal", amount, idx)
		else:
			var crit := _rng.randf() < 0.28
			var hit := party_dps * _rng.randf_range(0.10, 0.45)
			if crit:
				hit *= 3.0
			EventBus.sim_floater.emit("crit" if crit else "dmg", int(hit), -1)

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
		_loot_cooldown = Balance.num("rewards.loot_interval_ticks", 21.0)
		var entry: Array = GameContent.LOOT_FEED[_rng.randi_range(0, GameContent.LOOT_FEED.size() - 1)]
		EventBus.sim_loot.emit(entry)


func _on_wave_cleared() -> void:
	wave_damage -= wave_pool
	var s_index := Balance.stage_index(act, stage)
	GameState.add_gold(wave_gold_reward(s_index))
	GameState.add_xp(wave_xp_reward(s_index))
	var waves_per_stage := Balance.inum("enemy.waves_per_stage", 5)
	if wave >= waves_per_stage:
		wave = 1
		GameState.daily_stages += 1
		EventBus.quests_changed.emit()
		if auto_advance:
			_advance_stage()
		else:
			_reset_wave()
	else:
		wave += 1
		_reset_wave()
	EventBus.sim_wave_changed.emit(wave)


## Gold for one wave clear, including gold_find and the dungeon gold rush.
func wave_gold_reward(s_index: int) -> int:
	var profile := PlayerStats.compute()
	var gold := Balance.wave_gold(s_index) * (1.0 + float(profile["derived"]["gold_find"]))
	if GameState.dungeon_buff_active():
		gold *= Balance.num("energy.dungeon_gold_mult", 3.0)
	return int(gold)


## XP for one wave clear, including xp_gain.
func wave_xp_reward(s_index: int) -> int:
	var profile := PlayerStats.compute()
	return int(Balance.wave_xp(s_index) * (1.0 + float(profile["derived"]["xp_gain"])))


func _advance_stage() -> void:
	var per_act := Balance.inum("enemy.stages_per_act", 50)
	stage += 1
	if stage > per_act:
		stage = 1
		act += 1
	GameState.act = act
	GameState.stage = stage
	GameState.max_stage = maxi(GameState.max_stage, act * 100 + stage)
	stage_name = GameContent.STAGE_NAMES[(stage - 1) % GameContent.STAGE_NAMES.size()]
	_reset_wave()
	EventBus.sim_stage_changed.emit(stage_label(), stage_name)


## "4-7"-style stage label.
func stage_label() -> String:
	return "%d-%d" % [act, stage]


## Retreat: fall back one stage and restart the wave cycle.
func retreat() -> void:
	stage = maxi(1, stage - 1)
	GameState.stage = stage
	wave = 1
	stage_name = GameContent.STAGE_NAMES[(stage - 1) % GameContent.STAGE_NAMES.size()]
	_reset_wave()
	EventBus.sim_stage_changed.emit(stage_label(), stage_name)
	EventBus.sim_wave_changed.emit(wave)


## Team Aura passthrough (the real check lives with the stats).
func team_aura_optimal() -> bool:
	return PlayerStats.team_aura_optimal()

# ---------------------------------------------------------------------------
# Offline progress (CLAUDE.md §3): elapsed time → the same per-wave math.
# ---------------------------------------------------------------------------

func _compute_offline() -> void:
	var seconds := GameState.pending_offline_seconds
	GameState.pending_offline_seconds = 0
	if seconds < 60:
		return
	offline_rewards = simulate_offline(seconds)


## Headless fast-forward: clears waves one by one with the live party DPS and
## growing per-stage pools (no auto-advance assumption changes — it advances
## exactly like the live sim with auto_advance on). Returns the reward summary.
func simulate_offline(seconds: int) -> Dictionary:
	var cap := Balance.inum("rewards.offline_cap_hours", 12) * 3600
	var sim_seconds := mini(seconds, cap)
	var time_left := float(sim_seconds)
	var dps := maxf(1.0, party_dps)

	var sim_act := act
	var sim_stage := stage
	var sim_wave := wave
	var waves_per_stage := Balance.inum("enemy.waves_per_stage", 5)
	var per_act := Balance.inum("enemy.stages_per_act", 50)

	var gold := 0.0
	var xp_total := 0.0
	var waves_cleared := 0
	var profile := PlayerStats.compute()
	var gold_mult := 1.0 + float(profile["derived"]["gold_find"])
	var xp_mult := 1.0 + float(profile["derived"]["xp_gain"])

	while time_left > 0.0 and waves_cleared < 200000:
		var s_index := Balance.stage_index(sim_act, sim_stage)
		var wave_time := Balance.wave_pool(s_index) / dps
		if wave_time > time_left:
			break
		time_left -= wave_time
		waves_cleared += 1
		gold += Balance.wave_gold(s_index) * gold_mult
		xp_total += Balance.wave_xp(s_index) * xp_mult
		if sim_wave >= waves_per_stage:
			sim_wave = 1
			sim_stage += 1
			if sim_stage > per_act:
				sim_stage = 1
				sim_act += 1
		else:
			sim_wave += 1

	# Convert XP to levels against the real curve (without mutating state).
	var levels := 0
	var xp_probe := GameState.xp
	var need := GameState.xp_to_next
	var growth := Balance.num("rewards.xp_to_next_growth", 1.15)
	var xp_pool := int(xp_total)
	while xp_pool > 0 and levels < 999:
		var room := need - xp_probe
		if xp_pool >= room:
			xp_pool -= room
			xp_probe = 0
			need = int(float(need) * growth)
			levels += 1
		else:
			xp_probe += xp_pool
			xp_pool = 0

	var items := waves_cleared / Balance.inum("rewards.offline_item_waves_per_item", 15)
	return {
		"seconds": seconds,
		"gold": int(gold),
		"levels": levels,
		"items": items,
		"waves": waves_cleared,
		"end_act": sim_act,
		"end_stage": sim_stage,
		"end_wave": sim_wave,
	}


## Apply pending offline rewards to the profile (Collect button) — including
## the stage progress the party made while away.
func collect_offline() -> void:
	if offline_rewards.is_empty():
		return
	GameState.add_gold(int(offline_rewards["gold"]))
	for i in int(offline_rewards["levels"]):
		GameState.level_up()
	act = int(offline_rewards.get("end_act", act))
	stage = int(offline_rewards.get("end_stage", stage))
	wave = int(offline_rewards.get("end_wave", wave))
	GameState.act = act
	GameState.stage = stage
	GameState.max_stage = maxi(GameState.max_stage, act * 100 + stage)
	stage_name = GameContent.STAGE_NAMES[(stage - 1) % GameContent.STAGE_NAMES.size()]
	_reset_wave()
	EventBus.sim_stage_changed.emit(stage_label(), stage_name)
	EventBus.sim_wave_changed.emit(wave)
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
