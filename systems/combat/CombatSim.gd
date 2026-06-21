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

var speed: int = 1:
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
var _kills_emitted: int = 0
var _wave_count: int = 8       # individual monsters in the current normal wave
var _rng := RandomNumberGenerator.new()

## Boss-wave state (set by _reset_wave; "normal" the rest of the time). The
## skill modulations live in Balance and are applied identically here (live)
## and in simulate_offline so away-gains never diverge.
var _wave_kind: String = "normal"
var _wave_ticks: int = 0           # boss-wave tick count (integer → no float drift)
var _wave_elapsed: float = 0.0     # = _wave_ticks / TICK_RATE; drives skill timing
var _boss_kit: Dictionary = {}
var _boss_regen: float = 0.0       # absolute boss HP recovered per second
var _boss_adds_done: bool = false
var _boss_add_hp: float = 0.0      # one-time threshold bump from an adds wave
var _boss_shield_on: bool = false  # tracks the shield window for telegraphs

## Shared-delve FOLLOWER mode (Stage 5): the party leader drives the fight; this
## client renders the session position (apply_session) and does NOT self-advance
## or persist. The leader + solo players keep follow_mode = false.
var follow_mode: bool = false

## Follower reward cursor (Stage 5.3): the global wave index this client has
## already credited while following. -1 means "needs a baseline" — set on the
## first apply_session of a follow so joining a deep delve doesn't back-pay the
## whole floor; reset whenever follow mode ends.
var _delve_credited_index: int = -1


func _ready() -> void:
	_rng.seed = 0x6D2B79F5  # fixed seed: deterministic flavor rolls
	for h in GameContent.active_party():
		party_hp.append(float(h["hp"]))
		party_mana.append(float(h["mana"]))
	# Swapping the fighting four re-seeds vitals and reprices the party.
	EventBus.lineup_changed.connect(_on_lineup_changed)
	# SaveManager (earlier in autoload order) has loaded the profile by now.
	act = GameState.act
	stage = GameState.stage
	stage_name = _stage_theme()
	GameState.check_daily_reset()
	_recompute_stats()
	_maybe_relic_unlock()  # baseline the milestone count (no reprice on first)
	_reset_wave()
	_loot_cooldown = Balance.num("rewards.loot_interval_ticks", 21.0)
	# Any loadout/talent/roster change re-prices the party.
	EventBus.talents_changed.connect(_recompute_stats)
	EventBus.loadout_changed.connect(_recompute_stats)
	EventBus.game_loaded.connect(_recompute_stats)
	# Joining/leaving a party changes the composition aura → reprice party_dps.
	EventBus.party_changed.connect(_recompute_stats)
	_compute_offline()


func _recompute_stats() -> void:
	PlayerStats.invalidate()
	var profile := PlayerStats.compute()
	party_dps = float(profile["party_dps"])
	party_dps_label = String(profile["dps_label"])
	EventBus.sim_stats_changed.emit()


func _on_lineup_changed() -> void:
	var lineup := GameContent.active_party()
	for i in mini(lineup.size(), party_hp.size()):
		party_hp[i] = float((lineup[i] as Dictionary)["hp"])
		party_mana[i] = float((lineup[i] as Dictionary)["mana"])
	EventBus.sim_party_vitals.emit(party_hp, party_mana)


## Stage-milestone relics (GameContent.RELIC_STAGE_UNLOCKS): when max_stage
## crosses a threshold the relic set changes, so the party gets repriced.
var _relic_filled := -1

func _maybe_relic_unlock() -> void:
	var n := 0
	for rl in GameContent.live_relics():
		if not bool(rl["empty"]):
			n += 1
	if n == _relic_filled:
		return
	var first := _relic_filled < 0
	_relic_filled = n
	if not first:
		_recompute_stats()
		EventBus.loadout_changed.emit()  # relic tabs/windows rebuild


func _reset_wave() -> void:
	wave_pool = Balance.wave_pool(Balance.stage_index(act, stage))
	_wave_kind = Balance.wave_kind(act, stage, wave)
	wave_damage = 0.0
	_wave_ticks = 0
	_wave_elapsed = 0.0
	_boss_adds_done = false
	_boss_add_hp = 0.0
	_boss_shield_on = false
	_kills_emitted = 0
	# How many individual monsters this wave fields (data-driven per stage; boss
	# waves return 1). The wave HP pool is split evenly across them and the
	# progress bar tracks monsters killed / this count.
	_wave_count = Balance.wave_monster_count(act, stage, wave)
	if _wave_kind != "normal":
		wave_pool *= Balance.boss_hp_mult(_wave_kind)
		_boss_kit = Balance.boss_kit(_wave_kind)
		_boss_regen = Balance.boss_regen_per_sec(_boss_kit, wave_pool)
		var fl := Balance.floor_index(act, stage)
		EventBus.sim_boss_started.emit(_wave_kind, Balance.boss_name(_wave_kind, fl), _wave_kind, wave_pool)
		EventBus.sim_boss_hp.emit(1.0)
	else:
		_boss_kit = {}
		_boss_regen = 0.0


## Damage needed to clear the current wave NOW. For boss waves this grows with
## the enrage ramp and any adds bump; for normal waves it is just wave_pool.
func _boss_threshold() -> float:
	if _wave_kind == "normal":
		return wave_pool
	return wave_pool * (1.0 + Balance.boss_enrage_factor(_boss_kit, _wave_elapsed)) + _boss_add_hp


## The current stage's display name: the authored theme from stages.json if any,
## else the rotating default from GameContent.
func _stage_theme() -> String:
	var authored := Balance.stage_theme(act, stage)
	if authored != "":
		return authored
	return GameContent.STAGE_NAMES[(stage - 1) % GameContent.STAGE_NAMES.size()]


func wave_fill() -> float:
	# Solo / party-leader normal waves: the bar tracks MONSTERS KILLED / total, so
	# it steps up each time a monster dies (not a smooth time-based crawl).
	# Followers don't track kills locally — their fill is the leader's broadcast
	# value reconstructed in apply_session, so they keep the damage-based read.
	if _wave_kind == "normal" and not follow_mode:
		return clampf(float(_kills_emitted) / float(maxi(1, _wave_count)) * 100.0, 0.0, 100.0)
	return clampf(wave_damage / _boss_threshold() * 100.0, 0.0, 100.0)


## Un-multiplied wave pool for the current stage. Presentation layers (the
## battlefield's cosmetic enemy HP / time-to-kill) must read THIS, not wave_pool,
## which is boss-HP-multiplied (×9 / ×4) during boss waves.
func base_wave_pool() -> float:
	return Balance.wave_pool(Balance.stage_index(act, stage))


func _process(delta: float) -> void:
	# No profile yet (Login scene) — the delve hasn't started, nothing accrues.
	if not GameState.has_profile():
		return
	# As a shared-delve FOLLOWER the leader drives the fight; we only render the
	# session (apply_session) and skip our own advancement. Energy still regens.
	if not follow_mode:
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

	# Wave clock (INTEGER tick count so elapsed is exactly float(n)/TICK_RATE —
	# byte-for-byte equal to the offline projection; accumulating += 0.1 drifts
	# and flips integer-second boundaries). Drives boss skill windows AND the
	# normal-wave minimum duration, so live and offline clear in the same tick.
	_wave_ticks += 1
	_wave_elapsed = float(_wave_ticks) / TICK_RATE

	var dmg: float
	var cleared := false
	if _wave_kind == "normal":
		dmg = party_dps / TICK_RATE
		wave_damage += dmg
		# The wave is _wave_count individual monsters sharing the HP pool evenly;
		# a monster dies each time cumulative damage crosses its 1/count share, so
		# kills (and the progress bar) are driven purely by damage dealt — the wave
		# length is therefore monster-count x time-to-kill, with NO fixed minimum.
		var dmg_frac := (wave_damage / wave_pool) if wave_pool > 0.0 else 1.0
		var kills_due := mini(_wave_count, int(dmg_frac * float(_wave_count)))
		while _kills_emitted < kills_due:
			_kills_emitted += 1
			EventBus.sim_enemy_killed.emit()
		cleared = wave_damage >= wave_pool
	else:
		# Boss wave: party DPS is modulated by the kit's skills (shield/debuff
		# windows), the boss may regen, and an adds wave can bump the threshold.
		var mult := Balance.boss_dps_mult(_boss_kit, _wave_elapsed)
		dmg = party_dps * mult / TICK_RATE
		wave_damage = maxf(0.0, wave_damage + dmg - _boss_regen / TICK_RATE)
		if not _boss_adds_done and _boss_kit.has("adds"):
			var adds: Dictionary = _boss_kit["adds"]
			if wave_damage >= float(adds.get("at_frac", 2.0)) * wave_pool:
				_boss_adds_done = true
				_boss_add_hp = float(adds.get("hp_frac", 0.0)) * wave_pool
		var shielded := mult < 1.0
		if shielded != _boss_shield_on:
			_boss_shield_on = shielded
			EventBus.sim_boss_skill.emit("shield", shielded, 0.0)
		EventBus.sim_boss_hp.emit(clampf(1.0 - wave_damage / _boss_threshold(), 0.0, 1.0))
		# Threshold force-clear keeps offline/idle a speed-bump, never a wall.
		cleared = wave_damage >= _boss_threshold() or _wave_elapsed >= Balance.boss_time_cap()
	GameState.daily_damage += dmg
	if cleared:
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

## The activity log shows REAL events (stage clears, level-ups, bosses, special
## finds) — emitted via _log from _on_wave_cleared. No more random flavor drip.
func _log(verb: String, subject: String, rarity: String) -> void:
	var who := GameState.player_name if GameState.player_name != "" else "You"
	EventBus.sim_loot.emit([who, verb, subject, rarity])


## A special item is a GUARANTEED, cap-safe gold cache flavored by the item name
## (a real equippable special would need a server-issued grant — future work).
func _grant_special(s_index: int, name: String) -> void:
	GameState.add_gold(int(Balance.wave_gold(s_index) * Balance.num("rewards.special_item_gold_mult", 40.0)))
	_log("found", name, "epic")


func _on_wave_cleared() -> void:
	var cleared_kind := _wave_kind
	if cleared_kind != "normal":
		EventBus.sim_boss_defeated.emit(cleared_kind)
		_log("vanquished", Balance.boss_name(cleared_kind, Balance.floor_index(act, stage)),
			"mythic" if cleared_kind == "boss" else "epic")
	# No carryover: every wave (the _reset_wave calls below zero wave_damage)
	# clears in a whole number of ticks, so the live sim and simulate_offline
	# stay identical. Boss waves pay a reward multiplier for the longer fight.
	var s_index := Balance.stage_index(act, stage)
	var rmult := Balance.boss_reward_mult(cleared_kind)
	GameState.add_gold(int(wave_gold_reward(s_index) * rmult))
	var lvl_before := GameState.player_level
	GameState.add_xp(int(wave_xp_reward(s_index) * rmult))
	# DPS scales with level, so a level-up here must reprice party_dps for the
	# very next wave (otherwise the party would feel its new level only after a
	# loadout change). Fires at most once per wave.
	if GameState.player_level != lvl_before:
		_recompute_stats()
		_log("reached", "Level %d" % GameState.player_level, "rare")
	# Wave-level special grants on THIS wave; the stage-level special grants once
	# on the stage clear (below) so it isn't paid out every wave.
	var wsp := String(Balance.wave_def(act, stage, wave).get("special_item", ""))
	if wsp != "":
		_grant_special(s_index, wsp)
	var waves_per_stage := Balance.inum("enemy.waves_per_stage", 5)
	if wave >= waves_per_stage:
		var ssp := String(Balance.stage_def(act, stage).get("special_item", ""))
		if ssp != "":
			_grant_special(s_index, ssp)
		_log("cleared", "%s  (%s)" % [stage_name, stage_label()], "uncommon")
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
	stage_name = _stage_theme()
	_reset_wave()
	EventBus.sim_stage_changed.emit(stage_label(), stage_name)
	_maybe_relic_unlock()


## "4-7"-style stage label.
func stage_label() -> String:
	return "%d-%d" % [act, stage]


## Retreat: fall back one stage and restart the wave cycle.
func retreat() -> void:
	stage = maxi(1, stage - 1)
	GameState.stage = stage
	wave = 1
	stage_name = _stage_theme()
	_reset_wave()
	EventBus.sim_stage_changed.emit(stage_label(), stage_name)
	EventBus.sim_wave_changed.emit(wave)


## Team Aura passthrough (the real check lives with the stats).
func team_aura_optimal() -> bool:
	return PlayerStats.team_aura_optimal()


# ---------------------------------------------------------------------------
# Shared delve (Stage 5): followers mirror the leader's session.
# ---------------------------------------------------------------------------

## Render the leader's shared position WITHOUT advancing or persisting (the
## player's own GameState.act/stage stay put so solo resumes cleanly on leave).
## Called by BackendClient on each delve heartbeat while following.
func apply_session(sess: Dictionary) -> void:
	var a := int(sess.get("act", act))
	var st := int(sess.get("stage", stage))
	var wv := int(sess.get("wave", wave))
	var fill := clampf(float(sess.get("wave_fill", 0.0)), 0.0, 100.0)
	if a != act or st != stage or wv != wave:
		act = a
		stage = st
		wave = wv
		stage_name = _stage_theme()
		_reset_wave()  # sets _wave_kind / wave_pool, emits the boss banner if boss
		EventBus.sim_stage_changed.emit(stage_label(), stage_name)
		EventBus.sim_wave_changed.emit(wave)
	wave_damage = fill / 100.0 * _boss_threshold()
	if _wave_kind != "normal":
		EventBus.sim_boss_hp.emit(clampf(1.0 - wave_damage / _boss_threshold(), 0.0, 1.0))
	EventBus.sim_wave_progress.emit(wave_fill())
	_credit_followed_progress()


## Stage 5.3 — credit a follower for the shared waves cleared since the last poll
## (at the PARTY floor, with this player's own gold_find/xp_gain), and advance
## "deepest reached". Baselines on the first apply of a follow so joining a deep
## delve doesn't back-pay the whole floor; the burst clamp guards a stale cursor.
## The follower's own grind position (GameState.act/stage) is untouched — only
## gold/xp/max_stage move, and /v1/sync's party-floor grace lets these land.
func _credit_followed_progress() -> void:
	if not follow_mode:
		return
	var wps := Balance.inum("enemy.waves_per_stage", 5)
	var s_index := Balance.stage_index(act, stage)
	var cursor := s_index * wps + (wave - 1)
	if _delve_credited_index < 0:
		_delve_credited_index = cursor  # baseline; no back-pay on join
		return
	if cursor <= _delve_credited_index:
		return  # no forward progress this beat (or leader reset)
	var cleared := mini(cursor - _delve_credited_index, wps * 6)  # bound a burst
	_delve_credited_index = cursor
	GameState.add_gold(wave_gold_reward(s_index) * cleared)
	GameState.add_xp(wave_xp_reward(s_index) * cleared)
	GameState.max_stage = maxi(GameState.max_stage, act * 100 + stage)


## Become the delve LEADER continuing from the shared session position (host
## migration). Without this, a just-promoted follower would set_follow_mode(false)
## back to its own (behind) solo floor and its first checkpoint would be rejected
## as "backward", stalling the whole delve.
func adopt_as_leader(sess: Dictionary) -> void:
	follow_mode = false
	_delve_credited_index = -1  # leaving follow mode; re-baseline if I follow again
	act = int(sess.get("act", act))
	stage = int(sess.get("stage", stage))
	wave = int(sess.get("wave", wave))
	stage_name = _stage_theme()
	_reset_wave()
	wave_damage = clampf(float(sess.get("wave_fill", 0.0)), 0.0, 100.0) / 100.0 * _boss_threshold()
	EventBus.sim_stage_changed.emit(stage_label(), stage_name)
	EventBus.sim_wave_changed.emit(wave)


## Enter/leave follower mode. Leaving restores the player's OWN solo position so
## offline/solo progress continues from where it actually is.
func set_follow_mode(on: bool) -> void:
	if on == follow_mode:
		return
	follow_mode = on
	_delve_credited_index = -1  # entering or leaving follow → re-baseline the cursor
	if not on:
		act = GameState.act
		stage = GameState.stage
		wave = 1
		stage_name = _stage_theme()
		_reset_wave()
		EventBus.sim_stage_changed.emit(stage_label(), stage_name)
		EventBus.sim_wave_changed.emit(wave)

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

	# Backstop only (never the reward limiter): 12h at 1 tick/wave = 432000
	# waves, so this must sit above that or strong parties lose late offline time.
	while time_left > 0.0 and waves_cleared < 500000:
		var s_index := Balance.stage_index(sim_act, sim_stage)
		var kind := Balance.wave_kind(sim_act, sim_stage, sim_wave)
		var pool := Balance.wave_pool(s_index)
		var wave_time: float
		if kind == "normal":
			# Tick-quantize so offline matches the live sim's whole-tick clears.
			# Wave length is now purely DPS-driven (monster count x time-to-kill),
			# no fixed minimum — the live tick clears the same way (damage >= pool).
			wave_time = ceilf(pool / dps * TICK_RATE) / TICK_RATE
		else:
			pool *= Balance.boss_hp_mult(kind)
			wave_time = _boss_clear_secs(pool, Balance.boss_kit(kind), dps)
		if wave_time > time_left:
			break
		time_left -= wave_time
		waves_cleared += 1
		var rmult := Balance.boss_reward_mult(kind)
		gold += Balance.wave_gold(s_index) * gold_mult * rmult
		xp_total += Balance.wave_xp(s_index) * xp_mult * rmult
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

	@warning_ignore("integer_division")
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


## Seconds to clear one boss wave, stepped at TICK_RATE with the exact same
## per-tick math as the live boss branch in _tick — so offline gains match the
## live sim. Force-clears at the time cap so a weak party is slowed, not walled.
func _boss_clear_secs(pool: float, kit: Dictionary, dps: float) -> float:
	var cap := Balance.boss_time_cap()
	var max_ticks := int(cap * TICK_RATE)
	var regen := Balance.boss_regen_per_sec(kit, pool)
	var has_adds: bool = kit.has("adds")
	var adds_at := INF
	var adds_hp := 0.0
	if has_adds:
		var adds: Dictionary = kit["adds"]
		adds_at = float(adds.get("at_frac", 2.0)) * pool
		adds_hp = float(adds.get("hp_frac", 0.0)) * pool
	var dmg := 0.0
	var add_hp := 0.0
	var adds_done := false
	for n in range(1, max_ticks + 1):
		var t := float(n) / TICK_RATE
		var mult := Balance.boss_dps_mult(kit, t)
		dmg = maxf(0.0, dmg + dps * mult / TICK_RATE - regen / TICK_RATE)
		if not adds_done and has_adds and dmg >= adds_at:
			adds_done = true
			add_hp = adds_hp
		var threshold := pool * (1.0 + Balance.boss_enrage_factor(kit, t)) + add_hp
		if dmg >= threshold:
			return float(n) / TICK_RATE
	return cap


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
	stage_name = _stage_theme()
	_reset_wave()
	EventBus.sim_stage_changed.emit(stage_label(), stage_name)
	EventBus.sim_wave_changed.emit(wave)
	_maybe_relic_unlock()
	offline_rewards = {}
	EventBus.rewards_collected.emit({})
	EventBus.currencies_changed.emit()


## Human-readable "2h 14m" for the welcome-back popup.
func format_away(seconds: int) -> String:
	@warning_ignore("integer_division")
	var h := seconds / 3600
	@warning_ignore("integer_division")
	var m := (seconds % 3600) / 60
	if h > 0:
		return "%dh %02dm" % [h, m]
	return "%dm" % m
