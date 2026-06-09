extends ScreenBase
## HERO profile screen (CLAUDE.md §5). Placeholder until the tabbed paperdoll,
## stats, pets, relics, and talent web land.

func _ready() -> void:
	build_placeholder(
		"Hero",
		"Tabbed profile — Equipment / Stats / Pets / Relics / Talents.",
		PackedStringArray([
			"Equipment — PoE-style paperdoll with rarity-colored slots",
			"Stats — 5 mains + expandable derived stats",
			"Pets — active slot + collection grid",
			"Relics — equipped relics & bonuses",
			"Talents — pan/zoom node web",
		]),
		"3"
	)
