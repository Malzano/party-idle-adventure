class_name Palette
extends RefCounted
## BinkBonk Idle design tokens — cozy, cute party idle crawler.
##
## Ported 1:1 from the design handoff (Claude Design project "party idle game",
## styles.css :root). Pure constants + tiny lookup helpers; single source of truth
## for color. Constant NAMES are kept from the old Grimhollow palette so every
## consumer keeps working — only the values change (dark gothic → candy/honey).

# --- Surfaces: cozy night navy stage → warm cream panels ---
const BG_0 := Color("232849")        # stage / deepest background (night navy)
const BG_1 := Color("2a3057")        # rail base
const BG_2 := Color("fff3da")        # panel base (cream)
const BG_3 := Color("fffaec")        # raised panel
const BG_4 := Color("ffe8c2")        # inset / hover
const STONE := Color("ffe3a8")       # button base
const STONE_LIGHT := Color("fff4d4")
const GROOVE := Color(0.627, 0.416, 0.173, 0.25)

# --- Frame edges: honey wood ---
const IRON_HI := Color("ffe9bc")
const IRON_LO := Color("c98d4b")
const IRON_EDGE := Color("c08040")

# --- Warm accents: peach + honey gold ---
const EMBER := Color("ff9052")
const EMBER_BRIGHT := Color("ffb36e")
const EMBER_DEEP := Color("ec6f33")
const EMBER_HOT := Color("ff7a4d")   # danger label / hot spawn markers
const GOLD := Color("f0a32b")
const GOLD_BRIGHT := Color("ffc84a")
const GOLD_DIM := Color("d18a2a")

# --- Cool accents: sky (mana / interactive) + mint ---
const CYAN := Color("4db5ff")
const CYAN_BRIGHT := Color("82d2ff")
const CYAN_DEEP := Color("2a8fd6")
const MINT := Color("3dc98a")

# --- Status bars ---
const HP := Color("ff6b5e")
const HP_D := Color("e04a44")
const MANA := Color("4db5ff")
const MANA_D := Color("2a8fd6")
const XP := Color("ffc44d")

# --- Floaters ---
const DMG_CREAM := Color("fff6e0")
const HEAL_GREEN := Color("5fdd9c")

# --- Text: cocoa on cream ---
const TX := Color("4a3826")
const TX_DIM := Color("7a6248")
const TX_MUTE := Color("a2895f")
const TX_FAINT := Color("c6ae87")

# --- Rarity ladder: candy-bright (common → uncommon → rare → epic → legendary → mythic) ---
const R_COMMON := Color("a89a84")
const R_UNCOMMON := Color("3dc98a")
const R_RARE := Color("4da3ff")
const R_EPIC := Color("b46ef5")
const R_LEGENDARY := Color("ffab2e")
const R_MYTHIC := Color("e0455e")  # SSR — broadcast-worthy (kept vivid for the mythic pop)

# --- Podium metals ---
const SILVER := Color("aeb4ba")
const SILVER_TEXT := Color("cdd2d6")
const BRONZE := Color("c8884a")

# --- Role colors (Tank / Healer / DPS / Mage) ---
const ROLE_TANK := Color("d98d16")
const ROLE_HEALER := Color("2bab74")
const ROLE_DPS := Color("f25c4c")
const ROLE_MAGE := Color("3d95e8")

# --- Layout metrics (styles.css :root) ---
const RAIL_W := 110.0
const STRIP_H := 64.0

## Sparkle-glow intensity multiplier (the design's --glow tweak, default 1.0).
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
