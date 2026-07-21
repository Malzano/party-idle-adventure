class_name Fonts
extends RefCounted
## Font access for the BinkBonk UI.
##
## Display face = Baloo 2 (rounded + chunky, rendered at weight 800 for the
## MapleStory heading/button feel). Pixel face = Pixelify Sans (hotkey chips,
## numeric readouts, tickers). Both are variable TTFs in res://assets/fonts/.
## The old Spectral / Silkscreen faces stay as automatic fallbacks if the new
## files are ever missing, so the UI never loses its font.

# First existing path wins; Baloo 2 is preferred, Spectral is the fallback.
const _DISPLAY_CANDIDATES := [
	"res://assets/fonts/Baloo2-VariableFont.ttf",
	"res://assets/fonts/Spectral-SemiBold.ttf",
	"res://assets/fonts/Spectral-Bold.ttf",
	"res://assets/fonts/Spectral-Medium.ttf",
	"res://assets/fonts/Spectral-Regular.ttf",
]
const _DISPLAY_ITALIC_CANDIDATES := [
	"res://assets/fonts/Spectral-SemiBoldItalic.ttf",
	"res://assets/fonts/Spectral-BoldItalic.ttf",
	"res://assets/fonts/Spectral-Italic.ttf",
]
const _PIXEL_CANDIDATES := [
	"res://assets/fonts/PixelifySans-VariableFont.ttf",
	"res://assets/fonts/Silkscreen-Regular.ttf",
	"res://assets/fonts/Silkscreen-Bold.ttf",
]
const _DISPLAY_WEIGHT := 800  # Baloo 2 rendered chunky for the cute, bold headings

static var _display: Font = null
static var _display_italic: Font = null
static var _pixel: Font = null
static var _loaded := false


## Display face (titles, headings, buttons). May be null → default font.
static func display() -> Font:
	_ensure()
	return _display


## Italic display face (item names, hero name). Baloo has no italic cut, so it
## reuses the upright display; a real italic is used only on the Spectral fallback.
static func display_italic() -> Font:
	_ensure()
	if _display_italic != null:
		return _display_italic
	return _display


## Pixel face (hotkey chips, numeric readouts, tickers). May be null.
static func pixel() -> Font:
	_ensure()
	return _pixel


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var disp := _first_existing(_DISPLAY_CANDIDATES)
	_display = _weighted(disp, _DISPLAY_WEIGHT)
	# When Baloo is the display face there is no italic cut → reuse it upright;
	# only the Spectral fallback supplies a real italic.
	if disp != null and String(disp.resource_path).contains("Baloo"):
		_display_italic = null
	else:
		_display_italic = _first_existing(_DISPLAY_ITALIC_CANDIDATES)
	_pixel = _first_existing(_PIXEL_CANDIDATES)


## Render a variable font at a target weight (no-op if null / not weight-varying).
static func _weighted(f: Font, weight: int) -> Font:
	if f == null:
		return f
	var fv := FontVariation.new()
	fv.base_font = f
	fv.variation_opentype = {"wght": weight}
	return fv


static func _first_existing(paths: Array) -> Font:
	for path in paths:
		if ResourceLoader.exists(path):
			return load(path) as Font
	return null
