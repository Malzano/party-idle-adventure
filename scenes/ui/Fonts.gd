class_name Fonts
extends RefCounted
## Font access for the Grimhollow UI.
##
## The design uses Spectral (serif display, weights 500–800 incl. italic) and
## Silkscreen (pixel face for hotkey chips / tickers / numerics). Drop the TTFs
## into res://assets/fonts/ and they're picked up automatically; until then the
## helpers return null and callers fall back to Godot's default font.

# First existing path wins, so heavier weights are preferred for the display face.
const _DISPLAY_CANDIDATES := [
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
	"res://assets/fonts/Silkscreen-Regular.ttf",
	"res://assets/fonts/Silkscreen-Bold.ttf",
]

static var _display: Font = null
static var _display_italic: Font = null
static var _pixel: Font = null
static var _loaded := false


## Serif display face (titles, headings, buttons). May be null → default font.
static func display() -> Font:
	_ensure()
	return _display


## Italic display face (item names, hero name). Falls back to display() then null.
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
	_display = _first_existing(_DISPLAY_CANDIDATES)
	_display_italic = _first_existing(_DISPLAY_ITALIC_CANDIDATES)
	_pixel = _first_existing(_PIXEL_CANDIDATES)


static func _first_existing(paths: Array) -> Font:
	for path in paths:
		if ResourceLoader.exists(path):
			return load(path) as Font
	return null
