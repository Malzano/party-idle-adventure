class_name Palette
extends RefCounted
## Grimhollow design tokens — dark gothic ARPG idle crawler.
##
## Ported 1:1 from the design handoff (.design_ref/project/styles.css :root).
## Pure constants + tiny lookup helpers; single source of truth for color.

# --- Surfaces: near-black charcoal → cold stone grey ---
const BG_0 := Color("0a0908")        # stage / deepest background
const BG_1 := Color("110f0d")        # rail base
const BG_2 := Color("18150f")        # panel base
const BG_3 := Color("211d16")        # raised panel
const BG_4 := Color("2a251c")        # inset / hover
const STONE := Color("322c22")
const STONE_LIGHT := Color("463e30")
const GROOVE := Color(0, 0, 0, 0.55)

# --- Metal frame edges (beveled iron) ---
const IRON_HI := Color("5a5142")
const IRON_LO := Color("14110c")
const IRON_EDGE := Color("0c0a07")

# --- Warm accents: ember + dull gold ---
const EMBER := Color("e8843a")
const EMBER_BRIGHT := Color("ffac5c")
const EMBER_DEEP := Color("b85a1f")
const EMBER_HOT := Color("ff7a4d")   # danger label / hot spawn markers
const GOLD := Color("d3ad62")
const GOLD_BRIGHT := Color("f0cf86")
const GOLD_DIM := Color("8a6e36")

# --- Cold highlight: mana / interactive teal ---
const CYAN := Color("46c2d4")
const CYAN_BRIGHT := Color("7fe3f0")
const CYAN_DEEP := Color("1d6f7d")

# --- Status bars ---
const HP := Color("c0433a")
const HP_D := Color("6e211c")
const MANA := Color("3f9fd0")
const MANA_D := Color("1d4f70")
const XP := Color("c9a24a")

# --- Floaters ---
const DMG_CREAM := Color("fff2dd")
const HEAL_GREEN := Color("8ef08a")

# --- Text: warm parchment on charcoal ---
const TX := Color("ece0c8")
const TX_DIM := Color("b3a489")
const TX_MUTE := Color("7d7058")
const TX_FAINT := Color("564c3b")

# --- Rarity ladder: common → uncommon → rare → epic → legendary → mythic ---
const R_COMMON := Color("8c8579")
const R_UNCOMMON := Color("5fa64e")
const R_RARE := Color("4a8fd6")
const R_EPIC := Color("a661d6")
const R_LEGENDARY := Color("e6a93a")
const R_MYTHIC := Color("e0455e")  # SSR crimson — broadcast-worthy

# --- Podium metals ---
const SILVER := Color("aeb4ba")
const SILVER_TEXT := Color("cdd2d6")
const BRONZE := Color("c8884a")

# --- Role colors (Tank / Healer / DPS / Mage) ---
const ROLE_TANK := Color("d6a24a")
const ROLE_HEALER := Color("6fcf6a")
const ROLE_DPS := Color("e0584a")
const ROLE_MAGE := Color("46c2d4")

# --- Layout metrics (styles.css :root) ---
const RAIL_W := 110.0
const STRIP_H := 64.0

## Ember-glow intensity multiplier (the design's --glow tweak, default 1.0).
const GLOW := 1.0


## Rarity name → color ("" or unknown → common grey).
static func rarity_color(rarity: String) -> Color:
	match rarity:
		"uncommon":
			return R_UNCOMMON
		"rare":
			return R_RARE
		"epic":
			return R_EPIC
		"legendary":
			return R_LEGENDARY
		"mythic":
			return R_MYTHIC
		_:
			return R_COMMON


## Role name → color.
static func role_color(role: String) -> Color:
	match role:
		"tank":
			return ROLE_TANK
		"healer":
			return ROLE_HEALER
		"mage":
			return ROLE_MAGE
		_:
			return ROLE_DPS


## c with alpha a (convenience for glow shadows).
static func with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)
