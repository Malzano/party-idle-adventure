class_name UnitSprite
extends Control
## A unit's on-screen art (hero/enemy/anything animated). Renders real frames
## from an AssetManager bundle when its art is present, and falls back to the
## labeled PixelSlot placeholder when it isn't — so the battlefield works at
## every stage of art production. The battlefield keeps driving position /
## scroll / depth / stride-bob in CODE; this only animates the sprite IN PLACE.
##
## Usage:
##   var u := UnitSprite.new("hero.warrior", "64×96\nBrand", true)
##   u.play("walk", "ne")     # action + optional facing; degrades gracefully

var bundle_id: String
var _fallback_label: String
var _lit: bool
var _anim: AnimatedSprite2D
var _placeholder: PixelSlot
var _action := "idle"
var _dir := ""


func _init(p_bundle: String = "", p_label: String = "", p_lit: bool = false) -> void:
	bundle_id = p_bundle
	_fallback_label = p_label
	_lit = p_lit
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_rebuild()
	# A bundle can arrive later (lazy download / equipped skin) → upgrade then.
	if not AssetManager.asset_ready.is_connected(_on_asset_ready):
		AssetManager.asset_ready.connect(_on_asset_ready)
	resized.connect(_fit)


## Swap to a different bundle (e.g. an equipped skin). No-op if unchanged.
func set_bundle(id: String) -> void:
	if id == bundle_id:
		return
	bundle_id = id
	_rebuild()


## Drive the animation. Unknown actions/dirs degrade: <action>_<dir> →
## <action> → idle → walk → first available. Pure no-op while on placeholder.
func play(action: String, dir: String = "") -> void:
	_action = action
	_dir = dir
	_apply_anim()


func is_animated() -> bool:
	return _anim != null


func _on_asset_ready(id: String) -> void:
	if id == bundle_id and _anim == null:
		_rebuild()


func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_anim = null
	_placeholder = null
	var sf: SpriteFrames = AssetManager.get_sprite_frames(bundle_id) if bundle_id != "" else null
	if sf != null and sf.get_animation_names().size() > 0:
		_anim = AnimatedSprite2D.new()
		_anim.sprite_frames = sf
		_anim.centered = true
		add_child(_anim)
		_apply_anim()
		_fit()
	else:
		_placeholder = PixelSlot.new(_fallback_label, _lit)
		add_child(_placeholder)
		_placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _apply_anim() -> void:
	if _anim == null:
		return
	var sf := _anim.sprite_frames
	var want := _action
	if _dir != "" and sf.has_animation("%s_%s" % [_action, _dir]):
		want = "%s_%s" % [_action, _dir]
	elif not sf.has_animation(want):
		for fb in ["idle", "walk"]:
			if sf.has_animation(fb):
				want = fb
				break
		if not sf.has_animation(want):
			var names := sf.get_animation_names()
			if names.size() > 0:
				want = names[0]
	if sf.has_animation(want):
		_anim.play(want)


## Scale the (centered) frame to fill the Control rect.
func _fit() -> void:
	if _anim == null or _anim.sprite_frames == null:
		return
	var names := _anim.sprite_frames.get_animation_names()
	if names.is_empty():
		return
	var tex := _anim.sprite_frames.get_frame_texture(names[0], 0)
	if tex == null:
		return
	var fs := tex.get_size()
	if fs.x <= 0.0 or fs.y <= 0.0 or size.x <= 0.0:
		return
	_anim.scale = Vector2.ONE * minf(size.x / fs.x, size.y / fs.y)
	_anim.position = size * 0.5
