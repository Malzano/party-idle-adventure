extends Node
## Central signal hub for cross-screen communication.
##
## Decouples senders from receivers: any system can emit here and any screen
## can subscribe without holding a direct reference to the source. Keep these
## signals coarse-grained and game-level (not per-widget).

## Emitted when the active screen changes. [param screen] is one of the
## GameState.SCREEN_* constants.
signal screen_changed(screen: String)

## Emitted after offline/active progress hands the player loot to collect.
signal rewards_collected(rewards: Dictionary)

## Emitted when a new hero is added to the roster (gacha or unlock).
signal hero_summoned(hero_id: String)

## Emitted whenever a top-bar resource (gold, level, premium, energy) changes,
## so the resource strip can refresh without polling every frame.
signal currencies_changed

## Save lifecycle signals.
signal game_saved
signal game_loaded
