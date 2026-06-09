extends ScreenBase
## CAMP hub (CLAUDE.md §5). Placeholder until the building modals land.

func _ready() -> void:
	build_placeholder(
		"Camp",
		"Torchlit hub — clickable buildings open centered modals.",
		PackedStringArray([
			"Notice Board — Leaderboard / Daily Quests / Daily Dungeon",
			"Crafting House — forge & upgrade items",
			"Restaurant — consumable party buffs (food)",
			"Skill Learning House — gacha summoning altar (x1 / x10, pity)",
		]),
		"1"
	)
