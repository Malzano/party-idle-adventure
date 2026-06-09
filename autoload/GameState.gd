extends Node
## Singleton holding the live player profile.
##
## This is the in-memory source of truth for currencies and progression. The
## party, roster, gear, talents, etc. will hang off here as those systems land
## (see CLAUDE.md §7). For the skeleton it carries just enough to drive the top
## bar and exercise the save/load round-trip — including the last-played UTC
## timestamp the offline-progress system will read on the next launch.

## Screen identifiers used by the nav rail and EventBus.screen_changed.
const SCREEN_CAMP := "camp"
const SCREEN_FIGHT := "fight"
const SCREEN_HERO := "hero"

# --- Identity ----------------------------------------------------------------
var player_name: String = "Delver"

# --- Top-bar resources -------------------------------------------------------
var player_level: int = 1
## Progress toward the next level, for the resource-strip XP bar.
var xp: int = 0
var xp_to_next: int = 100
var gold: int = 0
var premium_currency: int = 0
var energy: int = 100
var energy_max: int = 100

# --- Progression -------------------------------------------------------------
var max_stage: int = 1

# --- Idle bookkeeping --------------------------------------------------------
## Unix UTC seconds the game was last saved/closed. The offline-progress system
## (CLAUDE.md §3) computes elapsed = now_utc - last_played_utc on load.
var last_played_utc: int = 0

## Seconds elapsed while the game was closed, computed once at load. Not yet
## consumed — the CombatSim milestone will turn this into rewards.
var pending_offline_seconds: int = 0


## Restore a brand-new profile (first launch or corrupted save).
func reset_to_defaults() -> void:
	player_name = "Delver"
	player_level = 1
	xp = 0
	xp_to_next = 100
	gold = 0
	premium_currency = 0
	energy = 100
	energy_max = 100
	max_stage = 1
	last_played_utc = 0
	pending_offline_seconds = 0


## Serialize the profile for persistence. Plain Dictionary so SaveManager can
## hand it straight to JSON.stringify.
func to_dict() -> Dictionary:
	return {
		"player_name": player_name,
		"player_level": player_level,
		"xp": xp,
		"xp_to_next": xp_to_next,
		"gold": gold,
		"premium_currency": premium_currency,
		"energy": energy,
		"energy_max": energy_max,
		"max_stage": max_stage,
		"last_played_utc": last_played_utc,
	}


## Load the profile from a previously serialized Dictionary. Missing keys fall
## back to current defaults so old saves stay forward-compatible.
func from_dict(data: Dictionary) -> void:
	player_name = str(data.get("player_name", player_name))
	player_level = int(data.get("player_level", player_level))
	xp = int(data.get("xp", xp))
	xp_to_next = int(data.get("xp_to_next", xp_to_next))
	gold = int(data.get("gold", gold))
	premium_currency = int(data.get("premium_currency", premium_currency))
	energy = int(data.get("energy", energy))
	energy_max = int(data.get("energy_max", energy_max))
	max_stage = int(data.get("max_stage", max_stage))
	last_played_utc = int(data.get("last_played_utc", last_played_utc))
