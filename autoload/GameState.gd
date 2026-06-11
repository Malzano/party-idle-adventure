extends Node
## Singleton holding the live player profile.
##
## In-memory source of truth for identity, currencies, progression, gacha
## pity, talent allocation, and loadout. Mutations that screens care about
## emit EventBus signals so every open window stays in sync. Starting values
## mirror the design mockup (Vael, LV 47, 248,910 gold, …).

## Screen identifiers used by the nav rail / WindowManager.
const SCREEN_CAMP := "camp"
const SCREEN_FIGHT := "fight"
const SCREEN_HERO := "hero"

# --- Identity ----------------------------------------------------------------
var player_name: String = "Vael"
var player_title: String = "the Forsaken"
var player_class: String = "Pyromancer"
var prestige: String = "III"
var global_rank: int = 11

# --- Resources ----------------------------------------------------------------
var player_level: int = 47
var xp: int = 12480
var xp_to_next: int = 14000
var gold: int = 248910
var premium_currency: int = 1204   # soulstones
var ember_dust: int = 38
var energy: int = 86
var energy_max: int = 120

# --- Progression ---------------------------------------------------------------
var act: int = 4
var stage: int = 7
var max_stage: int = 407

# --- Gacha ----------------------------------------------------------------------
var pity: int = 47

# --- Loadout / collections -------------------------------------------------------
## Talent node ids currently allocated (empty until first load seeds defaults).
var talents_allocated: Array[int] = []
## Index into GameContent.PETS of the active companion.
var active_pet: int = 0
## Extra heroes pulled from the gacha this profile: Array of {n, r, role}.
var roster_extra: Array = []
## Daily quest indices already claimed (resets daily).
var quests_claimed: Array[int] = []

# --- Materials & forge ----------------------------------------------------------
var iron_ingots: int = 46
## Upgrade level of the main-hand weapon (design base is +7).
var forge_level: int = 7

# --- Timed buffs -------------------------------------------------------------------
## Active food buff: recipe name, parsed effect string, and expiry (unix UTC).
var food_buff: String = ""
var food_buff_effect: String = ""
var food_buff_until: int = 0
## Daily-dungeon gold rush: expiry (unix UTC) + attempts left today.
var dungeon_buff_until: int = 0
var dungeon_attempts: int = 3

# --- Daily quest counters (reset when the UTC day changes) ------------------------
var daily_day: int = 0  # unix day stamp (now_utc / 86400)
var daily_stages: int = 0
var daily_damage: float = 0.0
var daily_meals: int = 0
var daily_summons: int = 0
var daily_forges: int = 0

# --- Idle bookkeeping --------------------------------------------------------
## Unix UTC seconds the game was last saved/closed (CLAUDE.md §3).
var last_played_utc: int = 0
## Seconds elapsed while closed, computed once at load; CombatSim consumes it.
var pending_offline_seconds: int = 0


# --- Mutation helpers (emit signals so all windows refresh) -------------------

func add_gold(amount: int) -> void:
	gold = maxi(0, gold + amount)
	EventBus.currencies_changed.emit()


func add_xp(amount: int) -> void:
	xp += amount
	while xp >= xp_to_next:
		xp -= xp_to_next
		level_up()
	EventBus.currencies_changed.emit()


func level_up() -> void:
	player_level += 1
	xp_to_next = int(float(xp_to_next) * 1.15)


## Spend soulstones; returns false (and changes nothing) if unaffordable.
func spend_soulstones(amount: int) -> bool:
	if premium_currency < amount:
		return false
	premium_currency -= amount
	EventBus.currencies_changed.emit()
	return true


func set_pity(value: int) -> void:
	pity = clampi(value, 0, GameContent.PITY_HARD)
	EventBus.pity_changed.emit(pity)


func add_roster_hero(hero: Dictionary) -> void:
	roster_extra.append(hero)
	daily_summons += 1
	EventBus.quests_changed.emit()
	EventBus.hero_summoned.emit(String(hero.get("n", "")))
	EventBus.loadout_changed.emit()  # roster support DPS changed


func claim_quest(index: int) -> void:
	if not quests_claimed.has(index):
		quests_claimed.append(index)
		EventBus.quests_changed.emit()


func set_active_pet(index: int) -> void:
	active_pet = index
	EventBus.loadout_changed.emit()


## Apply a timed party food buff (Hearthfire Kitchen).
func set_food_buff(recipe_name: String, effect: String, duration_seconds: int) -> void:
	food_buff = recipe_name
	food_buff_effect = effect
	food_buff_until = now_utc() + duration_seconds
	daily_meals += 1
	EventBus.quests_changed.emit()
	EventBus.loadout_changed.emit()


func food_buff_active() -> bool:
	return food_buff != "" and now_utc() < food_buff_until


func dungeon_buff_active() -> bool:
	return now_utc() < dungeon_buff_until


## Spend energy; returns false (and changes nothing) if unaffordable.
func spend_energy(amount: int) -> bool:
	if energy < amount:
		return false
	energy -= amount
	EventBus.currencies_changed.emit()
	return true


## Attempt the forge upgrade: spends gold + materials, rolls success.
## Returns {"ok": bool, "success": bool, "reason": String}.
func try_forge_upgrade(rng: RandomNumberGenerator) -> Dictionary:
	var gold_cost := Balance.forge_gold_cost(forge_level)
	var iron_cost := Balance.inum("forge.iron_cost", 12)
	var dust_cost := Balance.inum("forge.dust_cost", 3)
	if gold < gold_cost:
		return {"ok": false, "success": false, "reason": "Not enough gold"}
	if iron_ingots < iron_cost:
		return {"ok": false, "success": false, "reason": "Not enough Iron Ingots"}
	if ember_dust < dust_cost:
		return {"ok": false, "success": false, "reason": "Not enough Ember Dust"}
	gold -= gold_cost
	iron_ingots -= iron_cost
	ember_dust -= dust_cost
	daily_forges += 1
	var success := rng.randf() < Balance.num("forge.success_rate", 0.82)
	if success:
		forge_level += 1
		EventBus.loadout_changed.emit()  # weapon stats changed
	EventBus.quests_changed.emit()
	EventBus.currencies_changed.emit()
	return {"ok": true, "success": success, "reason": ""}


## Enter the daily dungeon: spends energy + an attempt, starts the gold rush.
## Returns false when out of attempts/energy.
func enter_daily_dungeon() -> bool:
	if dungeon_attempts <= 0:
		return false
	if not spend_energy(Balance.inum("energy.dungeon_cost", 20)):
		return false
	dungeon_attempts -= 1
	dungeon_buff_until = now_utc() + Balance.inum("energy.dungeon_buff_seconds", 60)
	EventBus.quests_changed.emit()
	return true


## Live progress (0..goal) for daily quest [param index] (GameContent.QUESTS order).
func quest_progress(index: int) -> float:
	match index:
		0:
			return float(daily_stages)
		1:
			return float(daily_summons)
		2:
			return float(daily_meals)
		3:
			return daily_damage / 1_000_000.0  # goal is in millions
		_:
			return float(daily_forges)


## Roll the daily counters when the UTC day changes.
func check_daily_reset() -> void:
	var today := now_utc() / 86400
	if daily_day == today:
		return
	daily_day = today
	daily_stages = 0
	daily_damage = 0.0
	daily_meals = 0
	daily_summons = 0
	daily_forges = 0
	quests_claimed.clear()
	dungeon_attempts = Balance.inum("energy.dungeon_attempts_per_day", 3)
	EventBus.quests_changed.emit()


static func now_utc() -> int:
	return int(Time.get_unix_time_from_system())


## Talent allocation following the design's rules: a node can be allocated when
## adjacent to an allocated node; refunded only at the edge of the path.
func talent_toggle(id: int, adjacency: Dictionary) -> void:
	if talents_allocated.has(id):
		if id == 0:
			return
		var allocated_neighbors := 0
		for n in adjacency.get(id, []):
			if talents_allocated.has(int(n)):
				allocated_neighbors += 1
		if allocated_neighbors <= 1:
			talents_allocated.erase(id)
			EventBus.talents_changed.emit()
	else:
		for n in adjacency.get(id, []):
			if talents_allocated.has(int(n)):
				talents_allocated.append(id)
				EventBus.talents_changed.emit()
				return


## Restore a brand-new profile (first launch or corrupted save).
func reset_to_defaults() -> void:
	player_name = "Vael"
	player_title = "the Forsaken"
	player_class = "Pyromancer"
	prestige = "III"
	global_rank = 11
	player_level = 47
	xp = 12480
	xp_to_next = 14000
	gold = 248910
	premium_currency = 1204
	ember_dust = 38
	energy = 86
	energy_max = 120
	act = 4
	stage = 7
	max_stage = 407
	pity = 47
	talents_allocated = []
	active_pet = 0
	roster_extra = []
	quests_claimed = []
	iron_ingots = 46
	forge_level = 7
	food_buff = ""
	food_buff_effect = ""
	food_buff_until = 0
	dungeon_buff_until = 0
	dungeon_attempts = 3
	daily_day = 0
	daily_stages = 0
	daily_damage = 0.0
	daily_meals = 0
	daily_summons = 0
	daily_forges = 0
	last_played_utc = 0
	pending_offline_seconds = 0


## Serialize the profile for persistence (plain Dictionary → JSON).
func to_dict() -> Dictionary:
	return {
		"player_name": player_name,
		"player_title": player_title,
		"player_class": player_class,
		"prestige": prestige,
		"global_rank": global_rank,
		"player_level": player_level,
		"xp": xp,
		"xp_to_next": xp_to_next,
		"gold": gold,
		"premium_currency": premium_currency,
		"ember_dust": ember_dust,
		"energy": energy,
		"energy_max": energy_max,
		"act": act,
		"stage": stage,
		"max_stage": max_stage,
		"pity": pity,
		"talents_allocated": talents_allocated,
		"active_pet": active_pet,
		"roster_extra": roster_extra,
		"quests_claimed": quests_claimed,
		"iron_ingots": iron_ingots,
		"forge_level": forge_level,
		"food_buff": food_buff,
		"food_buff_effect": food_buff_effect,
		"food_buff_until": food_buff_until,
		"dungeon_buff_until": dungeon_buff_until,
		"dungeon_attempts": dungeon_attempts,
		"daily_day": daily_day,
		"daily_stages": daily_stages,
		"daily_damage": daily_damage,
		"daily_meals": daily_meals,
		"daily_summons": daily_summons,
		"daily_forges": daily_forges,
		"last_played_utc": last_played_utc,
	}


## Load the profile from a serialized Dictionary. Missing keys keep current
## (default) values so old saves stay forward-compatible.
func from_dict(data: Dictionary) -> void:
	player_name = str(data.get("player_name", player_name))
	player_title = str(data.get("player_title", player_title))
	player_class = str(data.get("player_class", player_class))
	prestige = str(data.get("prestige", prestige))
	global_rank = int(data.get("global_rank", global_rank))
	player_level = int(data.get("player_level", player_level))
	xp = int(data.get("xp", xp))
	xp_to_next = int(data.get("xp_to_next", xp_to_next))
	gold = int(data.get("gold", gold))
	premium_currency = int(data.get("premium_currency", premium_currency))
	ember_dust = int(data.get("ember_dust", ember_dust))
	energy = int(data.get("energy", energy))
	energy_max = int(data.get("energy_max", energy_max))
	act = int(data.get("act", act))
	stage = int(data.get("stage", stage))
	max_stage = int(data.get("max_stage", max_stage))
	pity = int(data.get("pity", pity))
	talents_allocated.clear()
	for v in data.get("talents_allocated", []):
		talents_allocated.append(int(v))
	active_pet = int(data.get("active_pet", active_pet))
	roster_extra = data.get("roster_extra", roster_extra)
	quests_claimed.clear()
	for v in data.get("quests_claimed", []):
		quests_claimed.append(int(v))
	iron_ingots = int(data.get("iron_ingots", iron_ingots))
	forge_level = int(data.get("forge_level", forge_level))
	food_buff = str(data.get("food_buff", food_buff))
	food_buff_effect = str(data.get("food_buff_effect", food_buff_effect))
	food_buff_until = int(data.get("food_buff_until", food_buff_until))
	dungeon_buff_until = int(data.get("dungeon_buff_until", dungeon_buff_until))
	dungeon_attempts = int(data.get("dungeon_attempts", dungeon_attempts))
	daily_day = int(data.get("daily_day", daily_day))
	daily_stages = int(data.get("daily_stages", daily_stages))
	daily_damage = float(data.get("daily_damage", daily_damage))
	daily_meals = int(data.get("daily_meals", daily_meals))
	daily_summons = int(data.get("daily_summons", daily_summons))
	daily_forges = int(data.get("daily_forges", daily_forges))
	last_played_utc = int(data.get("last_played_utc", last_played_utc))
