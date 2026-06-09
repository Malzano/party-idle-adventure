extends ScreenBase
## FIGHT idle auto-combat screen (CLAUDE.md §5, §6). Placeholder until the
## CombatSim and roaming battlefield land.

func _ready() -> void:
	build_placeholder(
		"Fight",
		"Wide isometric battlefield — party roams bottom-left to top-right.",
		PackedStringArray([
			"Stage / wave bar",
			"4 hero frames — HP / mana + role tags",
			"Team Aura indicator",
			"Floating damage numbers + auto-loot ticker",
			"Controls — Speed 1x/2x/4x, Auto-Skill, Auto-Advance, Retreat",
			"Party Finder panel (docked)",
		]),
		"2"
	)
