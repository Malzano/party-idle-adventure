class_name Combat3DView
extends SubViewportContainer
## A reusable 2.5D world: a 3D SubViewport (tilted Crownfall/Diablo camera, a
## grid ground, a sun) that both combat scenes (Survival, Fight) render into,
## while their HUD/minimap/modals stay 2D Control on top. The headless sims feed
## abstract Vector2 positions; this maps them onto the ground plane and drives a
## pooled 3D node per entity — a placeholder primitive until a real model is
## registered via set_model(kind, scene). Nothing in the sim/balance/HUD changes.
##
## Usage each frame:
##   view.focus(sim.player)                          # camera + follow
##   var n := view.node("enemy", i, "enemy_grunt")   # pooled anchor (on the ground)
##   n.position = view.to3(e.pos); n.rotation.y = ...
##   view.trim("enemy", sim.enemies.size())          # hide the unused tail

## Sim pixels → 3D metres (≈1000 px → 20 m).
const MSCALE := 0.02
## Tilted-perspective camera offset from the focus point (Crownfall/Diablo look).
const CAM_HEIGHT := 15.0
const CAM_BACK := 11.0

var _sv: SubViewport
var _world: Node3D
var _cam: Camera3D
var _pools: Dictionary = {}    # group -> { index:int -> Node3D anchor }
var _models: Dictionary = {}   # kind -> PackedScene (drop real .glb here)


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_sv = SubViewport.new()
	_sv.own_world_3d = true
	_sv.transparent_bg = false
	_sv.msaa_3d = Viewport.MSAA_2X
	_sv.positional_shadow_atlas_size = 1024
	add_child(_sv)

	_world = Node3D.new()
	_sv.add_child(_world)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("0a0807")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.48, 0.42)
	env.ambient_light_energy = 0.65
	env.fog_enabled = true
	env.fog_light_color = Color("0a0807")
	env.fog_density = 0.012
	we.environment = env
	_world.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58.0, -42.0, 0.0)
	sun.light_energy = 1.15
	sun.light_color = Color("ffe6c4")
	sun.shadow_enabled = true
	_world.add_child(sun)

	# Grid ground — a placeholder "map" so movement reads (swap for real terrain).
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1400.0, 1400.0)
	ground.mesh = pm
	ground.material_override = _grid_material()
	_world.add_child(ground)

	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.current = true
	_world.add_child(_cam)


## Register a real model (PackedScene from a .glb) for an entity kind. Its forward
## should be -Z and its origin at the feet; then it just works with the pooling.
func set_model(kind: String, scene: PackedScene) -> void:
	_models[kind] = scene


## Map a sim 2D position onto the ground plane (y = 0).
func to3(p: Vector2) -> Vector3:
	return Vector3(p.x * MSCALE, 0.0, p.y * MSCALE)


## Aim the tilted camera at a sim position (follows the delver).
func focus(world2d: Vector2) -> void:
	var t := to3(world2d)
	_cam.position = t + Vector3(0.0, CAM_HEIGHT, CAM_BACK)
	_cam.look_at(t, Vector3.UP)


## A pooled ground-anchor Node3D for entity [param index] of [param group],
## carrying the visual for [param kind] (a registered model, else a placeholder).
func node(group: String, index: int, kind: String) -> Node3D:
	if not _pools.has(group):
		_pools[group] = {}
	var pool: Dictionary = _pools[group]
	var anchor: Node3D = pool.get(index)
	if anchor == null or not is_instance_valid(anchor):
		anchor = Node3D.new()
		_world.add_child(anchor)
		pool[index] = anchor
	anchor.visible = true
	if String(anchor.get_meta("kind", "")) != kind:
		for c in anchor.get_children():
			c.queue_free()
		var vis: Node3D
		if _models.has(kind):
			vis = (_models[kind] as PackedScene).instantiate()
		else:
			vis = _placeholder(kind)
		anchor.add_child(vis)
		anchor.set_meta("kind", kind)
	return anchor


## Hide pooled anchors of [param group] beyond [param count] (the unused tail).
func trim(group: String, count: int) -> void:
	var pool: Dictionary = _pools.get(group, {})
	for idx in pool:
		if int(idx) >= count:
			var a: Node3D = pool[idx]
			if is_instance_valid(a):
				a.visible = false


# --- placeholders (used until a real model is registered for the kind) -------

func _placeholder(kind: String) -> Node3D:
	var mi := MeshInstance3D.new()
	var col := Color("b9b1a0")
	var yoff := 0.7
	var emit := false
	if kind.begins_with("class_"):
		mi.mesh = _capsule(0.42, 1.5); col = Color("d3ad62"); yoff = 0.75
	elif kind == "boss":
		mi.mesh = _capsule(1.0, 2.8); col = Color("e0455e"); yoff = 1.4; emit = true
	elif kind.begins_with("enemy_") or kind == "enemy":
		var k := kind.replace("enemy_", "")
		if k == "swarmer":
			mi.mesh = _capsule(0.26, 0.82); col = Color("c75c4e"); yoff = 0.41
		elif k == "brute":
			mi.mesh = _capsule(0.5, 1.5); col = Color("7e2a66"); yoff = 0.75
		else:
			mi.mesh = _capsule(0.34, 1.05); col = Color("a83a33"); yoff = 0.52
	elif kind == "shot":
		mi.mesh = _sphere(0.2); col = Color("7fe3f0"); yoff = 0.8; emit = true
	elif kind == "gem":
		mi.mesh = _sphere(0.16); col = Color("8fffb0"); yoff = 0.3; emit = true
	elif kind == "chest":
		var bm := BoxMesh.new(); bm.size = Vector3(0.9, 0.7, 0.7); mi.mesh = bm; col = Color("d3ad62"); yoff = 0.35
	else:
		var bx := BoxMesh.new(); bx.size = Vector3(0.6, 0.6, 0.6); mi.mesh = bx; yoff = 0.3
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.85
	if emit:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 0.55
	mi.material_override = m
	mi.position.y = yoff
	return mi


func _capsule(radius: float, height: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = height
	return c


func _sphere(radius: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	return s


func _grid_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_back, diffuse_lambert;
uniform vec3 base_color : source_color = vec3(0.075, 0.058, 0.042);
uniform vec3 line_color : source_color = vec3(0.20, 0.13, 0.07);
uniform float cell = 4.0;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 c = wpos.xz / cell;
	vec2 g = abs(fract(c - 0.5) - 0.5) / fwidth(c);
	float line = 1.0 - min(min(g.x, g.y), 1.0);
	ALBEDO = mix(base_color, line_color, line);
	ROUGHNESS = 1.0;
}
"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	return sm
