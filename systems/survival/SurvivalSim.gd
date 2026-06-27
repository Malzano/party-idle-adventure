class_name SurvivalSim
extends RefCounted
## Headless, deterministic bullet-hell simulation for the SURVIVAL side mode
## (vampire-survivors-like). Decoupled from rendering (CLAUDE.md §3 philosophy):
## Survival.gd owns one of these, feeds it a move-input each frame via tick(),
## and draws from its state. Runs fully headless for unit tests.
##
## Combat is gear-driven: base numbers are self-contained (so balance is tunable)
## and the hero's idle loadout applies MULTIPLIERS — the equipped/bagged items'
## Survival-only "bh" affixes (GameContent.item_bullet_hell) map straight onto
## sim params (Surge Damage→dmg, Fire Rate→cadence, Blast Area→radius, …), plus
## class/level scaling. Class archetype decides the weapon: hunter/mage fire
## PROJECTILES, warrior/rogue swing a BLADE AURA. Each STAGE cleared offers a
## 3-card enhancement draft (diagonal / double / backside / +dmg / +atk speed …).

const ARENA := Vector2(1920.0, 1080.0)
const PLAYER_R := 24.0
const MARGIN := 46.0
## Half-extent the delver may roam past the arena edges (the camera follows, so
## the world is effectively large; bounded only to avoid float drift).
const ROAM := 2200.0
const STAGE_SECONDS := 22.0
const MAX_ENEMIES := 130
## Seconds before the first world boss, and between bosses after each kill.
## Crownfall-style: a marked mini-boss roams the map and rewards an upgrade.
const BOSS_DELAY := 45.0

## Enemy archetypes. Stat multipliers over the stage-scaled base; the spawn
## director (below) weights them by elapsed stage so the swarm gains variety and
## threat. Adapted from the MIT references — DarkRewar/SurvivorsStarterKit's
## EnemyManager difficulty progression + rcanpahali/pathfinder's timed spawn
## waves (both MIT). `tint` is a hex colour the renderer reads.
const ENEMY_KINDS := {
	"swarmer": {"hp": 0.5, "spd": 1.55, "r": 15.0, "dmg": 0.7, "tint": "c75c4e"},
	"grunt": {"hp": 1.0, "spd": 1.0, "r": 22.0, "dmg": 1.0, "tint": "a83a33"},
	"brute": {"hp": 2.7, "spd": 0.58, "r": 31.0, "dmg": 1.9, "tint": "7e2a66"},
}

# --- run config (derived from the hero's gear in _init) ---------------------
var rng := RandomNumberGenerator.new()
var class_id := "warrior"
var is_ranged := false

# Base combat numbers (gear/upgrades multiply these).
var max_hp := 100.0
var hp := 100.0
var move_speed := 360.0
var base_hit := 12.0
var fire_interval := 0.85
var aura_radius := 165.0
var shot_radius := 16.0
var proj_speed := 760.0
var pickup_radius := 135.0
var crit_chance := 0.10
var crit_mult := 2.0

# Upgrade-driven attack shape.
var proj_extra := 0      # extra forward projectiles / fan width
var diagonal := false
var backside := false
var pierce := 1

# Secondary weapons (drafted; 0 = not owned). Adapted from the MIT references'
# powerups: orbiting orbs (DarkRewar's FloatingSphere) + a periodic AoE nova
# (SpiritWater). Class-agnostic passives that stack via the draft.
var orbs := 0
var orb_radius := 116.0
var orb_angle := 0.0
var nova_level := 0
var nova_radius := 230.0
var nova_flash := 0.0

# --- run state --------------------------------------------------------------
var player := ARENA * 0.5
var enemies: Array = []   # {pos:Vector2, hp:float, max:float, spd:float, r:float, dmg:float}
var shots: Array = []     # {pos:Vector2, vel:Vector2, dmg:float, pierce:int, r:float, hit:Dictionary}
var gems: Array = []      # {pos:Vector2, xp:int}
var floaters: Array = []  # {pos:Vector2, amount:int, crit:bool, t:float} — render consumes
var time := 0.0
var stage := 1
var stage_time := 0.0
var score := 0
var kills := 0
var level := 1
var alive := true
var awaiting_upgrade := false
var aim := 0.0          # current aim angle (render draws the aura toward it)
var aura_flash := 0.0   # >0 briefly after a melee swing (render hint)
var upgrades_taken: Array[String] = []

# World boss (Crownfall-style): one roams the map at a time, marked on the
# minimap. Killing it opens a bonus upgrade draft. The boss lives in `enemies`
# (kind "boss") so the normal attack pipeline damages it.
var boss_alive := false
var boss_spawns := 0       # how many have appeared (render rising-edge banner)
var bosses_slain := 0
var _draft_reason := "stage"  # "stage" (timed clear) or "boss" (boss kill)

var _fire_acc := 0.0
var _spawn_acc := 0.0
var _iframe := 0.0
var _burst_acc := 0.0
var _orb_tick := 0.0
var _nova_acc := 0.0
var _boss_acc := 0.0


## Build a run from the live player profile (PlayerStats.compute()) + the bag's
## Survival affixes. [param seed] makes a run reproducible for tests.
func _init(profile: Dictionary = {}, p_class := "", seed_val: int = 0) -> void:
	if seed_val != 0:
		rng.seed = seed_val
	else:
		rng.randomize()
	class_id = p_class if p_class != "" else String(GameState.class_id if GameState.class_id != "" else "warrior")
	is_ranged = class_id == "mage" or class_id == "hunter"

	var derived: Dictionary = profile.get("derived", {})
	var lvl := int(GameState.player_level)
	var mods := _gear_survival_mods()

	# Level + gear give moderate multipliers over a self-contained base so the
	# bullet-hell stays tunable/fun rather than inheriting the huge idle numbers.
	var dmg_mult := 1.0 + 0.05 * float(lvl - 1) + _pct(mods, "Surge Damage")
	base_hit = 12.0 * dmg_mult
	max_hp = 100.0 + 12.0 * float(lvl - 1)
	hp = max_hp
	move_speed = 340.0 * (1.0 + float(derived.get("movement_speed", 0.0)) + _pct(mods, "Dash Charge") * 0.5)
	fire_interval = 0.85 / (1.0 + float(derived.get("attack_speed", 0.0)) + _pct(mods, "Fire Rate"))
	aura_radius = 165.0 * (1.0 + _pct(mods, "Blast Area"))
	proj_speed = 760.0 * (1.0 + _pct(mods, "Projectile Speed"))
	pickup_radius = 135.0 * (1.0 + _pct(mods, "Pickup Radius"))
	crit_chance = 0.12
	crit_mult = maxf(1.8, float(derived.get("crit_multiplier", 2.0)))

	# Archetype balance: the melee blade aura is strong AoE (it sweeps every foe
	# in its arc each swing), so ranged classes fire faster and pierce by default
	# to keep the swarm clear too; melee trades a little raw damage for the reach.
	if is_ranged:
		fire_interval *= 0.6
		pierce = 2
	else:
		base_hit *= 0.9
	fire_interval = clampf(fire_interval, 0.12, 1.2)


## Sum the Survival-only "bh" affixes across the bag + equipped loadout into a
## {affix_name: total_percent_as_fraction} dict (e.g. {"Surge Damage": 0.42}).
func _gear_survival_mods() -> Dictionary:
	var out: Dictionary = {}
	var sources: Array = GameState.bag_equipment.duplicate()
	for it in GameState.equipped:
		if it != null:
			sources.append(it)
	for it_v in sources:
		if it_v == null:
			continue
		for pair in GameContent.item_bullet_hell(it_v):
			var nm := String(pair[0])
			var num := float(String(pair[1]).replace("+", "").replace("%", ""))
			out[nm] = float(out.get(nm, 0.0)) + num / 100.0
	return out


func _pct(mods: Dictionary, key: String) -> float:
	return float(mods.get(key, 0.0))


# ===========================================================================
# Tick
# ===========================================================================

## Advance the sim by [param delta] with a normalized move [param input]
## (Vector2, zero = stand still). No-op while dead or waiting on an upgrade pick.
func tick(delta: float, input: Vector2) -> void:
	if not alive or awaiting_upgrade:
		return
	time += delta
	stage_time += delta
	_iframe = maxf(0.0, _iframe - delta)
	aura_flash = maxf(0.0, aura_flash - delta)

	if input.length() > 0.01:
		# Vampire-survivors movement: the delver roams freely and the camera
		# follows (Survival.gd keeps the delver screen-centered). Clamp only to a
		# generous world bound so a very long run can't drift floats out of range.
		player += input.normalized() * move_speed * delta
		player.x = clampf(player.x, -ROAM, ARENA.x + ROAM)
		player.y = clampf(player.y, -ROAM, ARENA.y + ROAM)

	var tgt: Variant = _nearest_enemy()
	if tgt != null:
		aim = ((tgt["pos"] as Vector2) - player).angle()

	_spawn(delta)
	_advance_enemies(delta)
	if not alive:
		return
	_attack(delta)
	_update_orbs(delta)
	_update_nova(delta)
	_advance_shots(delta)
	_advance_gems(delta)

	if stage_time >= STAGE_SECONDS:
		awaiting_upgrade = true  # render shows the 3-card draft; resumes on pick
		_draft_reason = "stage"


## The full roamable map the camera follows the delver across.
func world_rect() -> Rect2:
	return Rect2(-ROAM, -ROAM, ARENA.x + 2.0 * ROAM, ARENA.y + 2.0 * ROAM)


## Spawn director: a steady stream whose rate ramps with stage/time, plus a
## periodic swarm BURST (pathfinder's batched enemy_count) — keeps the screen
## alive and rewards crowd-clear builds.
func _spawn(delta: float) -> void:
	_spawn_acc += delta
	var interval := maxf(0.16, 0.95 * pow(0.93, float(stage - 1)) - time * 0.004)
	while _spawn_acc >= interval and enemies.size() < MAX_ENEMIES:
		_spawn_acc -= interval
		_spawn_enemy(_pick_kind())
	_burst_acc += delta
	if _burst_acc >= 13.0 and enemies.size() < MAX_ENEMIES - 12:
		_burst_acc = 0.0
		var n := 6 + stage
		for i in n:
			_spawn_enemy("swarmer", float(i) / float(n) * TAU)
	# World boss: one at a time — first at BOSS_DELAY, then BOSS_DELAY after each
	# kill (the timer only runs while none is alive). Marked on the minimap.
	if not boss_alive:
		_boss_acc += delta
		if _boss_acc >= BOSS_DELAY:
			_boss_acc = 0.0
			_spawn_boss()


## A roaming map boss at a random spot well away from the delver (Crownfall-style).
func _spawn_boss() -> void:
	var wr := world_rect()
	var pos := player
	for _i in 8:
		pos = wr.position + Vector2(rng.randf() * wr.size.x, rng.randf() * wr.size.y)
		if (pos - player).length() > 760.0:
			break
	var bhp := 16.0 * pow(1.17, float(stage - 1)) * 70.0 + 1200.0
	enemies.append({
		"pos": pos, "hp": bhp, "max": bhp,
		"spd": 52.0 + float(stage) * 2.0,
		"r": 54.0, "dmg": 22.0 + float(stage) * 2.0,
		"kind": "boss", "tint": "e0455e",
	})
	boss_alive = true
	boss_spawns += 1


## Weighted archetype pick: early stages are grunts + swarmers; brutes ramp in
## with the stage (the difficulty curve adapted from EnemyManager).
func _pick_kind() -> String:
	var brute_w := clampf(0.04 * float(stage - 1), 0.0, 0.4)
	var r := rng.randf()
	if r < brute_w:
		return "brute"
	if r < brute_w + 0.35:
		return "swarmer"
	return "grunt"


## Spawn one foe of [param kind] just offscreen around the player (every angle).
## [param ang] < 0 picks a random angle; >= 0 places it precisely (burst rings).
func _spawn_enemy(kind := "grunt", ang := -1.0) -> void:
	var k: Dictionary = ENEMY_KINDS.get(kind, ENEMY_KINDS["grunt"])
	var a := ang if ang >= 0.0 else rng.randf() * TAU
	# The screen half-extent is ~960×540, so 1040+ guarantees they enter from the
	# edges, never pop in on top of the player.
	var dist := 1040.0 + rng.randf() * 320.0
	var pos := player + Vector2.RIGHT.rotated(a) * dist
	var ehp := 16.0 * pow(1.17, float(stage - 1)) * float(k["hp"]) * (0.85 + rng.randf() * 0.4)
	enemies.append({
		"pos": pos, "hp": ehp, "max": ehp,
		"spd": (66.0 + float(stage) * 4.0 + rng.randf() * 18.0) * float(k["spd"]),
		"r": float(k["r"]), "dmg": (7.0 + float(stage) * 1.2) * float(k["dmg"]),
		"kind": kind, "tint": String(k["tint"]),
	})


func _advance_enemies(delta: float) -> void:
	for e in enemies:
		var to := player - (e["pos"] as Vector2)
		var d := to.length()
		if d > 0.5:
			e["pos"] = (e["pos"] as Vector2) + to / d * float(e["spd"]) * delta
		if d <= PLAYER_R + float(e["r"]) and _iframe <= 0.0:
			hp -= float(e["dmg"])
			_iframe = 0.55
			if hp <= 0.0:
				hp = 0.0
				alive = false
				return


func _attack(delta: float) -> void:
	_fire_acc += delta
	if _fire_acc < fire_interval:
		return
	_fire_acc = 0.0
	if enemies.is_empty():
		return
	if is_ranged:
		_fire_projectiles()
	else:
		_swing_aura()


## Hunter/Mage: emit projectiles along the upgrade-shaped angle set.
func _fire_projectiles() -> void:
	for off in _attack_offsets():
		var a := aim + float(off)
		shots.append({
			"pos": player, "vel": Vector2.RIGHT.rotated(a) * proj_speed,
			"dmg": _roll_dmg(), "pierce": pierce, "r": shot_radius, "hit": {},
		})


## Warrior/Rogue: a blade aura damages every enemy inside the radius that also
## falls within an active arc (forward; backside → omni; diagonal widens).
func _swing_aura() -> void:
	aura_flash = 0.22
	var arcs := _aura_arcs()
	for e in enemies.duplicate():  # snapshot: _damage_enemy may erase on a kill
		var off := (e["pos"] as Vector2) - player
		if off.length() > aura_radius + float(e["r"]):
			continue
		var ea := off.angle()
		for arc in arcs:
			if absf(wrapf(ea - float(arc[0]), -PI, PI)) <= float(arc[1]):
				_damage_enemy(e, _roll_dmg())
				break


## Orbiting orbs (FloatingSphere): N orbs circle the delver and damage enemies
## they overlap on a fixed tick — a passive crowd weapon, class-agnostic.
func _update_orbs(delta: float) -> void:
	if orbs <= 0:
		return
	orb_angle = wrapf(orb_angle + delta * 2.6, 0.0, TAU)
	_orb_tick -= delta
	if _orb_tick > 0.0:
		return
	_orb_tick = 0.22
	for i in orbs:
		var op := player + Vector2.RIGHT.rotated(orb_angle + TAU * float(i) / float(orbs)) * orb_radius
		for e in enemies.duplicate():
			if ((e["pos"] as Vector2) - op).length() <= 26.0 + float(e["r"]):
				_damage_enemy(e, base_hit * 0.6)


## Periodic AoE nova (SpiritWater): every few seconds, blast every nearby foe.
func _update_nova(delta: float) -> void:
	nova_flash = maxf(0.0, nova_flash - delta)
	if nova_level <= 0:
		return
	_nova_acc += delta
	if _nova_acc < 2.4:
		return
	_nova_acc = 0.0
	nova_flash = 0.3
	for e in enemies.duplicate():
		if ((e["pos"] as Vector2) - player).length() <= nova_radius:
			_damage_enemy(e, base_hit * (0.8 + 0.4 * float(nova_level)))


## Angle offsets (from aim) for ranged shots: a forward fan (widened by extra
## projectiles), optional diagonal pair, optional rear shot.
func _attack_offsets() -> Array:
	var arr: Array = []
	var n := 1 + proj_extra
	if n == 1:
		arr.append(0.0)
	else:
		var span := 0.18 * float(n - 1)
		for i in n:
			arr.append(-span + 2.0 * span * float(i) / float(n - 1))
	if diagonal:
		arr.append(-0.5)
		arr.append(0.5)
	if backside:
		arr.append(PI)
	return arr


## Arc set (center_angle, half_width) for the melee aura.
func _aura_arcs() -> Array:
	if backside:
		return [[aim, PI]]  # full circle
	var hw := 0.95 + (0.55 if diagonal else 0.0)
	var arcs: Array = [[aim, hw]]
	if proj_extra > 0:
		arcs[0][1] = hw + 0.3 * float(proj_extra)  # "double" widens the swing
	return arcs


func _roll_dmg() -> float:
	var d := base_hit * (0.9 + rng.randf() * 0.2)
	if rng.randf() < crit_chance:
		d *= crit_mult
	return d


func _damage_enemy(e: Dictionary, dmg: float) -> void:
	e["hp"] = float(e["hp"]) - dmg
	floaters.append({"pos": (e["pos"] as Vector2) + Vector2(0, -18), "amount": int(dmg), "crit": dmg > base_hit * 1.5, "t": 0.0})
	if float(e["hp"]) <= 0.0:
		_kill_enemy(e)


func _kill_enemy(e: Dictionary) -> void:
	kills += 1
	if String(e.get("kind", "")) == "boss":
		boss_alive = false
		bosses_slain += 1
		score += 1500
		hp = minf(max_hp, hp + max_hp * 0.4)
		_boss_acc = 0.0
		for i in 6:  # a gem burst + a bonus upgrade draft — the boss reward
			gems.append({"pos": (e["pos"] as Vector2) + Vector2.RIGHT.rotated(TAU * float(i) / 6.0) * 42.0, "xp": 3})
		awaiting_upgrade = true
		_draft_reason = "boss"
	else:
		gems.append({"pos": (e["pos"] as Vector2), "xp": 1})
	enemies.erase(e)


func _advance_shots(delta: float) -> void:
	var live: Array = []
	for s in shots:
		s["pos"] = (s["pos"] as Vector2) + (s["vel"] as Vector2) * delta
		var p := s["pos"] as Vector2
		if p.x < -80.0 or p.x > ARENA.x + 80.0 or p.y < -80.0 or p.y > ARENA.y + 80.0:
			continue
		var hits: Dictionary = s["hit"]
		var dead := false
		for e in enemies.duplicate():  # snapshot: _damage_enemy may erase on a kill
			if hits.has(e):
				continue
			if ((e["pos"] as Vector2) - p).length() <= float(s["r"]) + float(e["r"]):
				hits[e] = true
				_damage_enemy(e, float(s["dmg"]))
				s["pierce"] = int(s["pierce"]) - 1
				if int(s["pierce"]) <= 0:
					dead = true
					break
		if not dead:
			live.append(s)
	shots = live


func _advance_gems(delta: float) -> void:
	var live: Array = []
	for g in gems:
		var to := player - (g["pos"] as Vector2)
		var d := to.length()
		if d <= pickup_radius:
			g["pos"] = (g["pos"] as Vector2) + to.normalized() * 520.0 * delta  # magnet pull
		if d <= PLAYER_R + 8.0:
			score += 10
			level = 1 + kills / 12
			hp = minf(max_hp, hp + 0.6)
			continue
		live.append(g)
	gems = live


func _nearest_enemy() -> Variant:
	var best: Variant = null
	var best_d := INF
	for e in enemies:
		var d := ((e["pos"] as Vector2) - player).length_squared()
		if d < best_d:
			best_d = d
			best = e
	return best


# ===========================================================================
# Stage / upgrade draft
# ===========================================================================

## The full enhancement pool. `once` upgrades leave the pool after being taken;
## the rest stack. `kind` lets render tint the cards.
const UPGRADES: Array[Dictionary] = [
	{"id": "double", "name": "Double Strike", "desc": "+1 projectile / wider swing", "kind": "shape"},
	{"id": "diagonal", "name": "Diagonal Volley", "desc": "Adds diagonal attacks", "kind": "shape", "once": true},
	{"id": "backside", "name": "Rearguard", "desc": "Also attacks behind you", "kind": "shape", "once": true},
	{"id": "pierce", "name": "Piercing", "desc": "Attacks pass through +1 foe", "kind": "shape"},
	{"id": "dmg", "name": "Honed Edge", "desc": "+25% damage", "kind": "power"},
	{"id": "atk_speed", "name": "Frenzy", "desc": "+18% attack speed", "kind": "power"},
	{"id": "area", "name": "Wide Arc", "desc": "+25% area / projectile size", "kind": "power"},
	{"id": "proj_speed", "name": "Velocity", "desc": "+25% projectile speed", "kind": "power"},
	{"id": "crit", "name": "Deadeye", "desc": "+8% crit chance", "kind": "power"},
	{"id": "move", "name": "Fleetfoot", "desc": "+15% move speed", "kind": "util"},
	{"id": "max_hp", "name": "Vitality", "desc": "+20% max HP & heal", "kind": "util"},
	{"id": "pickup", "name": "Lodestone", "desc": "+40% pickup radius", "kind": "util"},
	{"id": "orbs", "name": "Warding Orbs", "desc": "Orbiting orbs strike nearby foes", "kind": "weapon"},
	{"id": "nova", "name": "Pyre Nova", "desc": "A blast erupts around you periodically", "kind": "weapon"},
]


## Three distinct enhancement choices for the just-cleared stage (drops `once`
## upgrades already taken). Deterministic under the seeded rng.
func offer_upgrades() -> Array:
	var pool: Array = []
	for u in UPGRADES:
		if bool(u.get("once", false)) and upgrades_taken.has(String(u["id"])):
			continue
		pool.append(u)
	# Fisher-Yates pick 3 (or fewer if the pool is small).
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	return pool.slice(0, mini(3, pool.size()))


## Apply a chosen enhancement. A timed stage-clear advances the stage; a boss
## reward is a bonus pick that just resumes (no stage-timer reset).
func choose_upgrade(id: String) -> void:
	apply_upgrade(id)
	upgrades_taken.append(id)
	if _draft_reason == "boss":
		awaiting_upgrade = false
		_draft_reason = "stage"
		hp = minf(max_hp, hp + max_hp * 0.1)
	else:
		next_stage()


func apply_upgrade(id: String) -> void:
	match id:
		"double": proj_extra += 1
		"diagonal": diagonal = true
		"backside": backside = true
		"pierce": pierce += 1
		"dmg": base_hit *= 1.25
		"atk_speed": fire_interval = maxf(0.12, fire_interval * 0.82)
		"area":
			aura_radius *= 1.25
			shot_radius *= 1.22
		"proj_speed": proj_speed *= 1.25
		"crit": crit_chance = minf(0.85, crit_chance + 0.08)
		"move": move_speed *= 1.15
		"max_hp":
			max_hp *= 1.2
			hp = minf(max_hp, hp + max_hp * 0.2)
		"pickup": pickup_radius *= 1.4
		"orbs": orbs = maxi(2, orbs + 1)  # first pick = 2 orbs, then +1 each
		"nova": nova_level += 1


func next_stage() -> void:
	stage += 1
	stage_time = 0.0
	score += stage * 200  # stage-clear bonus
	awaiting_upgrade = false
	hp = minf(max_hp, hp + max_hp * 0.15)  # small clear heal


## Final run score for the leaderboard / drops (kills + score + stage + time).
func final_score() -> int:
	return score + kills * 25 + (stage - 1) * 400 + int(time) * 2
