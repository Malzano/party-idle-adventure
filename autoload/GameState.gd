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
## player_class is EMPTY until the first-login class selection (Login scene);
## an empty class is what routes a fresh profile through character creation.
var player_name: String = ""
var player_title: String = ""
var player_class: String = ""
## One of GameContent.CLASSES ids ("warrior"/"mage"/"hunter"/"rogue"; "" for
## legacy profiles created before classes existed).
var class_id: String = ""
var prestige: String = "III"
var global_rank: int = 11


## True once a profile exists (class chosen, or a legacy pre-class save).
func has_profile() -> bool:
	return player_class != ""


## First-login character creation (Login scene): locks in the chosen class.
func choose_class(id: String, chosen_name: String) -> void:
	var cls := GameContent.class_by_id(id)
	if cls.is_empty():
		return
	class_id = id
	player_class = String(cls["name"])
	player_title = String(cls["title"])
	player_name = chosen_name.strip_edges() if not chosen_name.strip_edges().is_empty() else "Delver"
	EventBus.loadout_changed.emit()  # class bonuses reprice the party
	EventBus.currencies_changed.emit()

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

# --- Equipment (canonical items: {n, r, slot, ilvl, s}) ---------------------------
## Paperdoll, index-aligned with GameContent.EQUIP_SLOTS (null = empty slot).
var equipped: Array = []
## Equipment bag (drag source/target; cap 30). Non-equipment bag tabs
## (consumables/materials/quest) remain static design content.
var bag_equipment: Array = []
const BAG_CAP := 30


## Seed the paperdoll + bag from the design's static content (first run or
## pre-equipment saves).
func seed_default_equipment() -> void:
	equipped = []
	for g in GameContent.GEAR_L + GameContent.GEAR_R:
		equipped.append(GameContent.gear_to_item(g))
	bag_equipment = []
	for b in GameContent.BAG["equipment"]:
		var item := GameContent.bag_to_item(b)
		bag_equipment.append(item if not item.is_empty() else {
			"n": String(b["n"]), "r": String(b["r"]), "slot": "", "ilvl": 1,
			"s": (b.get("s", []) as Array).duplicate(true)})


## Equip bag[bag_idx] into paperdoll slot_idx (swapping any occupant back to
## the same bag position). Returns false when the slot doesn't accept it.
func equip_from_bag(bag_idx: int, slot_idx: int) -> bool:
	if bag_idx < 0 or bag_idx >= bag_equipment.size():
		return false
	var item: Dictionary = bag_equipment[bag_idx]
	if not GameContent.slot_accepts(slot_idx, String(item.get("slot", ""))):
		return false
	var old: Variant = equipped[slot_idx]
	equipped[slot_idx] = item
	if old != null:
		bag_equipment[bag_idx] = old
	else:
		bag_equipment.remove_at(bag_idx)
	EventBus.equipment_changed.emit()
	EventBus.loadout_changed.emit()
	return true


## Unequip paperdoll slot_idx into the bag. Fails when the bag is full.
func unequip_to_bag(slot_idx: int) -> bool:
	if slot_idx < 0 or slot_idx >= equipped.size() or equipped[slot_idx] == null:
		return false
	if bag_equipment.size() >= BAG_CAP:
		return false
	bag_equipment.append(equipped[slot_idx])
	equipped[slot_idx] = null
	EventBus.equipment_changed.emit()
	EventBus.loadout_changed.emit()
	return true


## Add a looted item to the bag (chest rewards). False when full.
func add_bag_item(item: Dictionary) -> bool:
	if bag_equipment.size() >= BAG_CAP:
		return false
	bag_equipment.append(item)
	EventBus.equipment_changed.emit()
	return true

# --- Chests -----------------------------------------------------------------------
var daily_chests: int = 0

# --- Hero lineup (the fighting four; design v2 roster) -----------------------------
## Hero ids from GameContent.HEROES, one per battlefield slot. Saved as
## "party_lineup". Edited in the Hero window's ROSTER tab.
var party_ids: Array[String] = ["brand", "ash", "hex", "wren"]

## hero_id -> equipped skin bundle id (AssetManager). Empty = base art.
## Saved as "hero_skins"; cosmetic only (no stat effect).
var hero_skins: Dictionary = {}


## Equip/clear a hero's cosmetic skin. Triggers the lazy bundle download and
## rebuilds the lineup-bound surfaces (battlefield renders the new art).
func set_hero_skin(hero_id: String, skin_id: String) -> void:
	if skin_id == "":
		hero_skins.erase(hero_id)
	else:
		hero_skins[hero_id] = skin_id
		AssetManager.request(skin_id)  # ensure the lazy skin bundle is present
	EventBus.lineup_changed.emit()


## Put [param hero_id] into [param slot] (design PartyStore.assign): if the
## hero already holds another slot the two swap, so the lineup never dupes.
func set_party_slot(slot: int, hero_id: String) -> bool:
	if slot < 0 or slot >= party_ids.size():
		return false
	if not GameContent.hero_recruited(hero_id):
		return false
	var cur := party_ids.find(hero_id)
	if cur == slot:
		return false
	if cur >= 0:
		party_ids[cur] = party_ids[slot]
	party_ids[slot] = hero_id
	EventBus.lineup_changed.emit()
	EventBus.loadout_changed.emit()  # aura/base DPS reprice
	return true


# --- Party (server-authoritative; this is only the client mirror) -------------------
## PartyView from GET /v1/party/mine ({} = solo). NOT part of to_dict — the
## server owns party membership; BackendClient refreshes the mirror (and
## persists the mock world in user://netstate.json, not the save blob).
var party: Dictionary = {}


func in_party() -> bool:
	return not party.is_empty()


func set_party(p: Dictionary) -> void:
	party = p
	EventBus.party_changed.emit()

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
	@warning_ignore("integer_division")
	var today := now_utc() / 86400
	if daily_day == today:
		return
	daily_day = today
	daily_stages = 0
	daily_damage = 0.0
	daily_meals = 0
	daily_summons = 0
	daily_forges = 0
	daily_chests = 0
	quests_claimed.clear()
	dungeon_attempts = Balance.inum("energy.dungeon_attempts_per_day", 3)
	EventBus.quests_changed.emit()


func now_utc() -> int:
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


## Restore a brand-new profile (first launch or corrupted save). The class
## is left EMPTY so the Login scene runs character creation.
func reset_to_defaults() -> void:
	player_name = ""
	player_title = ""
	player_class = ""
	class_id = ""
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
	seed_default_equipment()
	daily_chests = 0
	party = {}
	party_ids = GameContent.DEFAULT_PARTY_IDS.duplicate()
	hero_skins = {}
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
		"class_id": class_id,
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
		"equipped": equipped,
		"bag_equipment": bag_equipment,
		"daily_chests": daily_chests,
		"party_lineup": party_ids,
		"hero_skins": hero_skins,
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
	class_id = str(data.get("class_id", class_id))
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
	# Equipment arrays: saves from before the equip system seed the defaults.
	if data.has("equipped") and (data["equipped"] as Array).size() == GameContent.EQUIP_SLOTS.size():
		equipped = data["equipped"]
		bag_equipment = data.get("bag_equipment", [])
	else:
		seed_default_equipment()
	daily_chests = int(data.get("daily_chests", 0))
	# Lineup: only valid, RECRUITED, non-duplicated 4-hero sets are adopted
	# (same gate as set_party_slot); anything else keeps the current four.
	# roster_extra was adopted above, so hero_recruited sees the loaded state.
	var old_lineup := party_ids.duplicate()
	var lineup_v: Variant = data.get("party_lineup", [])
	if typeof(lineup_v) == TYPE_ARRAY and (lineup_v as Array).size() == party_ids.size():
		var seen := {}
		var valid := true
		for id_v in lineup_v:
			var id := String(id_v)
			if not GameContent.hero_recruited(id) or seen.has(id):
				valid = false
				break
			seen[id] = true
		if valid:
			for i in party_ids.size():
				party_ids[i] = String((lineup_v as Array)[i])
	var skins_v: Variant = data.get("hero_skins", {})
	hero_skins = (skins_v as Dictionary).duplicate() if typeof(skins_v) == TYPE_DICTIONARY else {}
	# Runtime loads (e.g. adopting the server save on a 409) must refresh the
	# lineup-bound surfaces; at boot nothing listens yet, so this is free.
	if party_ids != old_lineup or not hero_skins.is_empty():
		EventBus.lineup_changed.emit.call_deferred()
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
