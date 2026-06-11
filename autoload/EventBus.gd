extends Node
## Central signal hub for cross-screen / cross-window communication.
##
## Decouples senders from receivers: any system can emit here and any screen
## can subscribe without holding a direct reference to the source. All popup
## windows share this bus (same SceneTree), so currency changes etc. update
## every open window at once.

## Emitted when the active screen changes (legacy single-window nav).
signal screen_changed(screen: String)

## Emitted when a popup window opens or closes. [param id] is one of the
## WindowManager.WIN_* ids; the nav rail uses this to light its buttons.
signal window_state_changed(id: String, open: bool)

## Emitted after offline/active progress hands the player loot to collect.
signal rewards_collected(rewards: Dictionary)

## Emitted when a new hero is added to the roster (gacha or unlock).
signal hero_summoned(hero_id: String)

## Emitted whenever a resource (gold, soulstone, ember dust, energy, xp, level)
## changes, so every resource strip / inventory footer refreshes without polling.
signal currencies_changed

## Save lifecycle signals.
signal game_saved
signal game_loaded

# --- CombatSim → presentation (Fight screen) --------------------------------

## A damage/heal number to float. kind: "dmg" | "crit" | "heal".
## [param hero_idx] is the party index for heals (-1 for damage).
signal sim_floater(kind: String, amount: int, hero_idx: int)

## Wave progress 0..100 for the top wave bar.
signal sim_wave_progress(fill: float)

## Wave index changed (1..5).
signal sim_wave_changed(wave: int)

## Stage advanced; label like "4-7", name like "The Sunken Reliquary".
signal sim_stage_changed(label: String, stage_name: String)

## Auto-loot ticker entry: [who, verb, item, rarity].
signal sim_loot(entry: Array)

## One enemy of the current wave died (wave damage crossed its HP share).
## The battlefield kills a token and respawns a fresh one from an edge.
signal sim_enemy_killed

## Party HP/mana percentages changed (arrays of 4 floats, 0..100).
signal sim_party_vitals(hp: Array, mana: Array)

## Sim speed multiplier changed (1 / 2 / 4).
signal sim_speed_changed(speed: int)

## Auto-skill / auto-advance toggles changed.
signal sim_toggles_changed(auto_skill: bool, auto_advance: bool)

## Pity counter changed (gacha).
signal pity_changed(pity: int)

## Recomputed player stats (party DPS / powers) after a loadout change.
signal sim_stats_changed

## A daily quest's progress/claim state changed.
signal quests_changed

## Talent allocation changed.
signal talents_changed

## Pet / relic loadout changed.
signal loadout_changed
