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
var prestige: String = "I"
var global_rank: int = 0


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
	# MOCK: stock the bag with the full item set so a new delver has gear to arrange
	# and equip. The paperdoll still starts empty — the player drags pieces on.
	if bag_equipment.is_empty():
		for g in GameContent.GEAR_L + GameContent.GEAR_R:
			bag_equipment.append(GameContent.gear_to_item(g))
	# MOCK: starting gold + forge materials so crafting is testable from the start.
	gold = maxi(gold, 100000)
	iron_ingots = maxi(iron_ingots, 200)
	ember_dust = maxi(ember_dust, 200)
	premium_currency = maxi(premium_currency, 24000)  # ~15 ×10 summons, so the altar is testable
	# MOCK: complete today's dailies so the Notice Board's Claim flow is testable
	# from the start. Stamp the day too, or the first combat tick's
	# check_daily_reset() sees daily_day == 0 and wipes these back to zero.
	@warning_ignore("integer_division")
	daily_day = now_utc() / 86400
	daily_stages = maxi(daily_stages, 3)      # quest 0: clear 3 stages
	daily_summons = maxi(daily_summons, 1)    # quest 1: summon
	daily_meals = maxi(daily_meals, 1)        # quest 2: cook a meal
	daily_damage = maxf(daily_damage, 5_000_000.0)  # quest 3: deal 5M damage
	daily_forges = maxi(daily_forges, 5)      # quest 4: salvage 5 items
	EventBus.loadout_changed.emit()  # class bonuses reprice the party
	EventBus.currencies_changed.emit()

# --- Resources ----------------------------------------------------------------
# Fresh-start seeds — a new delver begins clean at the level-1 dungeon. xp_to_next
# at level 1 ≈ 14000 / 1.15^46, so the client's ×1.15-per-level curve lands back on
# the server's expected 14000 by level 47 (validation.ts plausibility check).
var player_level: int = 1
var xp: int = 0
var xp_to_next: int = 23
var gold: int = 0
var premium_currency: int = 480    # soulstones — small welcome grant (≤ bootstrap cap)
var ember_dust: int = 0
var energy: int = 120
var energy_max: int = 120

# --- Progression ---------------------------------------------------------------
# A fresh delver begins at the level-1 dungeon: floor 1, sub-stage 1
# (max_stage = act*100 + stage = 101). Existing saves keep their stored position.
var act: int = 1
var stage: int = 1
var max_stage: int = 101

# --- Gacha ----------------------------------------------------------------------
var pity: int = 0

# --- Loadout / collections -------------------------------------------------------
## Talent node ids currently allocated (empty until first load seeds defaults).
var talents_allocated: Array[int] = []
## Index into GameContent.PETS of the active companion.
var active_pet: int = 0
## LEGACY: heroes a v2 profile pulled from the gacha. No longer serialized or
## used for DPS (gacha rolls gear now); kept only so dormant readers don't crash.
var roster_extra: Array = []
## Lifetime gacha summons. Replaces roster_extra.size() as the pet-unlock gate
## (save key "total_summons"; migrated from a legacy roster's length on load).
var total_summons: int = 0
## Daily quest indices already claimed (resets daily).
var quests_claimed: Array[int] = []

# --- Materials & forge ----------------------------------------------------------
var iron_ingots: int = 0
## Upgrade level of the main-hand weapon (design base is +7; the server save
## schema floors this at 7, so a fresh delver starts here — not at 0).
var forge_level: int = 7

# --- Equipment (canonical items: {n, r, slot, ilvl, s}) ---------------------------
## Paperdoll, index-aligned with GameContent.EQUIP_SLOTS (null = empty slot).
var equipped: Array = []
## Equipment bag (drag source/target; cap 30). Non-equipment bag tabs
## (consumables/materials/quest) remain static design content.
var bag_equipment: Array = []
const BAG_CAP := 30


## Seed an EMPTY paperdoll + bag (first run or pre-equipment saves). A fresh
## level-1 delver starts with nothing equipped and earns all gear through play;
## the paperdoll keeps one (null) cell per EQUIP_SLOTS so slot indexing is valid.
func seed_default_equipment() -> void:
	equipped = []
	for _i in GameContent.EQUIP_SLOTS.size():
		equipped.append(null)
	bag_equipment = []


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

# --- Hero lineup (VESTIGIAL) --------------------------------------------------
## LEGACY: the old 4-hero lineup. No longer serialized, edited, or read by the
## sim (1 account = 1 character — active_party() returns your single delver).
## Kept as a harmless default so dormant references don't crash; removed in a
## later cleanup with the HEROES pool.
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


# --- Party (server-authoritative; this is only the client mirror) -------------------
## PartyView from GET /v1/party/mine ({} = solo). NOT part of to_dict — the
## server owns party membership; BackendClient refreshes the mirror (and
## persists the mock world in user://netstate.json, not the save blob).
var party: Dictionary = {}

## Real-party composition aura multiplier from the server (1.0 = solo / no
## bonus). Set by BackendClient on the /party/mine heartbeat; multiplies
## party_dps in PlayerStats. Runtime only — never serialized.
var party_aura_mult: float = 1.0


func in_party() -> bool:
	return not party.is_empty()


## The shared-delve session (Stage 5) the player is in ({} = not delving). A
## read-only mirror of the server combat_sessions doc; BackendClient refreshes
## it on the ~4s delve heartbeat. Runtime only — never serialized.
var delve: Dictionary = {}


func in_delve() -> bool:
	return not delve.is_empty()


func set_delve(d: Dictionary) -> void:
	var was := not delve.is_empty()
	delve = d
	var now_in := not d.is_empty()
	if now_in != was:
		EventBus.delve_changed.emit(now_in)


## The uid of the party leader (from the PartyView), "" when solo / no leader.
func party_leader_uid() -> String:
	for m in party.get("members", []):
		if bool((m as Dictionary).get("leader", false)):
			return String((m as Dictionary).get("uid", ""))
	return ""


## Count of online party members (PartyView presence).
func party_online_count() -> int:
	var n := 0
	for m in party.get("members", []):
		if bool((m as Dictionary).get("online", false)):
			n += 1
	return n


func set_party(p: Dictionary) -> void:
	party = p
	# Adopt the real-party composition aura (server-authoritative; 1.0 solo).
	# CombatSim reprices party_dps and the Fight badge rebuilds on party_changed.
	party_aura_mult = float(p.get("party_aura_mult", 1.0)) if not p.is_empty() else 1.0
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
	# DPS scales with level (Balance.level_dps_mult), so a new level must reprice
	# the cached stat profile. CombatSim re-reads party_dps after the level-up.
	PlayerStats.invalidate()


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
	prestige = "I"
	global_rank = 0
	player_level = 1
	xp = 0
	xp_to_next = 23
	gold = 0
	premium_currency = 480
	ember_dust = 0
	energy = 120
	energy_max = 120
	act = 1
	stage = 1
	max_stage = 101
	pity = 0
	talents_allocated = []
	active_pet = 0
	roster_extra = []
	total_summons = 0
	quests_claimed = []
	iron_ingots = 0
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
		"total_summons": total_summons,
		"quests_claimed": quests_claimed,
		"iron_ingots": iron_ingots,
		"forge_level": forge_level,
		"equipped": equipped,
		"bag_equipment": bag_equipment,
		"daily_chests": daily_chests,
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
	# Migration: the roster is gone. Seed lifetime summons from total_summons
	# (new saves) OR a legacy roster's length (v2 saves), whichever is larger,
	# so pet unlocks survive. roster_extra itself is dropped.
	var legacy_roster: Array = data.get("roster_extra", [])
	total_summons = maxi(int(data.get("total_summons", 0)), legacy_roster.size())
	roster_extra = []
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
	var skins_v: Variant = data.get("hero_skins", {})
	hero_skins = (skins_v as Dictionary).duplicate() if typeof(skins_v) == TYPE_DICTIONARY else {}
	# Adopting a server save (409) can change the character's name/class/level,
	# so refresh every lineup-bound surface (HUD frame, battlefield sprite, sim
	# vitals). At boot nothing listens yet, so the deferred emit is free.
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
