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
## Daily quest indices already claimed.
var quests_claimed: Array[int] = []
## Active food buff ("" when none) + its description.
var food_buff: String = ""

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
	EventBus.hero_summoned.emit(String(hero.get("n", "")))


func claim_quest(index: int) -> void:
	if not quests_claimed.has(index):
		quests_claimed.append(index)
		EventBus.quests_changed.emit()


func set_active_pet(index: int) -> void:
	active_pet = index
	EventBus.loadout_changed.emit()


func set_food_buff(buff: String) -> void:
	food_buff = buff
	EventBus.loadout_changed.emit()


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
	food_buff = ""
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
		"food_buff": food_buff,
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
	food_buff = str(data.get("food_buff", food_buff))
	last_played_utc = int(data.get("last_played_utc", last_played_utc))
