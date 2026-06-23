extends GutTest
## Tutorial overlay: compile/build integrity of the wired screens (with autoloads
## present), the placement math, and the anchor registry.

const _LayerScript := preload("res://scenes/ui/TutorialLayer.gd")

# Every script that gained tutorial wiring must still compile (load() returns
# null on a compile error, with autoloads available here unlike `-s` mode).
const _WIRED := [
	"res://autoload/TutorialOverlay.gd",
	"res://scenes/ui/TutorialLayer.gd",
	"res://scenes/fight/Fight.gd",
	"res://scenes/hero/Hero.gd",
	"res://scenes/hero/EquipmentTab.gd",
	"res://scenes/hero/BagTab.gd",
	"res://systems/survival/SurvivalSim.gd",
	"res://scenes/survival/Survival.gd",
	"res://scenes/survival/SurvivalDraft.gd",
	"res://scenes/survival/SurvivalGameOver.gd",
	"res://scenes/camp/Camp.gd",
	"res://scenes/ui/NavRail.gd",
	"res://scenes/ui/ResourceStrip.gd",
	"res://scenes/settings/Settings.gd",
]


func test_wired_scripts_compile() -> void:
	for path in _WIRED:
		assert_not_null(load(path), "%s must compile" % path)


func test_overlay_has_public_api() -> void:
	assert_true(TutorialOverlay.has_method("start"), "Settings replay calls start()")
	assert_true(TutorialOverlay.has_method("register_anchor"))
	assert_true(TutorialOverlay.has_method("is_done"))
	assert_true(TutorialOverlay.has_method("maybe_autostart"))
	assert_eq(TutorialOverlay.STEPS.size(), 14, "14-step tour")


func test_anchor_registry_validates_liveness() -> void:
	var c := Control.new()
	add_child_autofree(c)
	TutorialOverlay.register_anchor("test.alive", c)
	assert_eq(TutorialOverlay._anchor("test.alive"), c, "live, in-tree control resolves")
	assert_null(TutorialOverlay._anchor("test.missing"), "unknown key resolves null")
	var gone := Control.new()
	TutorialOverlay.register_anchor("test.gone", gone)
	gone.free()
	assert_null(TutorialOverlay._anchor("test.gone"), "freed control resolves null, not a crash")


func test_layer_renders_without_error() -> void:
	var layer := _LayerScript.new()
	add_child_autofree(layer)
	layer.size = Vector2(1920, 1080)
	# A typical "below" info step.
	layer.render({
		"alpha": 0.78, "hole": Rect2(800, 300, 240, 60), "sec": null, "arrow": false,
		"prefer": "below", "headline": "Five waves to glory", "body": "Fill this bar.",
		"mode": "next", "cta": "Next ›", "hint": "", "skip_label": "Skip tour",
		"big": false, "step_idx": 2, "total": 14,
	})
	await get_tree().process_frame
	assert_gt(layer.get_child_count(), 5, "bands + ring + box built")
	# Regression: the box must stay a card, not balloon to full-screen height when
	# the autowrap body computes its min size (the width-pin keeps it sane).
	assert_lt(layer._box.get_combined_minimum_size().y, 400.0, "wording box is a card, not a full-height strip")
	# Intro centered step (no hole).
	layer.render({
		"alpha": 0.66, "hole": null, "sec": null, "arrow": false, "prefer": "center",
		"headline": "The delve never stops", "body": "Your party fights without you.",
		"mode": "intro", "cta": "Begin ›", "hint": "", "skip_label": "Skip tour",
		"big": true, "step_idx": 0, "total": 14,
	})
	await get_tree().process_frame
	pass_test("layer rendered both an anchored and a centered step")


func test_resolve_rect_maps_through_scaled_host() -> void:
	# The multi-window spotlight hinges on this: a target rect resolved through a
	# scaled/offset host (a popup stage) must come back in the host's 1920×1080
	# design space. Mirror a popup: host scaled 0.5 + offset, child at a known spot.
	var host := Control.new()
	add_child_autofree(host)
	host.position = Vector2(200, 100)
	host.scale = Vector2(0.5, 0.5)
	var child := Control.new()
	host.add_child(child)
	child.position = Vector2(300, 400)
	child.size = Vector2(120, 60)
	await get_tree().process_frame
	TutorialOverlay.register_anchor("test.xform", child)
	var r: Variant = TutorialOverlay._resolve_rect({"targets": ["test.xform"]}, 0, host)
	assert_true(r is Rect2, "resolves to a Rect2")
	var rect: Rect2 = r
	assert_almost_eq(rect.position.x, 300.0, 1.0, "x back in design space")
	assert_almost_eq(rect.position.y, 400.0, 1.0, "y back in design space")
	assert_almost_eq(rect.size.x, 120.0, 1.0, "width un-scaled")
	assert_almost_eq(rect.size.y, 60.0, 1.0, "height un-scaled")
	# The "frac" sub-rect (step 2 clash zone) shrinks the resolved rect.
	var sub: Variant = TutorialOverlay._resolve_rect({"targets": ["test.xform"], "frac": [0.25, 0.0, 0.5, 1.0]}, 0, host)
	assert_almost_eq((sub as Rect2).size.x, 60.0, 1.0, "frac halves the width")


func test_placement_autoflips_and_clamps() -> void:
	var layer := _LayerScript.new()
	add_child_autofree(layer)
	# A hole hugging the BOTTOM with prefer "below" must flip above (it won't fit).
	var low := layer._place(Rect2(900, 1000, 120, 50), "below", 376, 180)
	assert_lt(float(low["y"]), 1000.0, "box flips above a bottom-edge target")
	# A centered hole with prefer "below" keeps below and points its tail up.
	var mid := layer._place(Rect2(900, 200, 120, 50), "below", 376, 180)
	assert_gt(float(mid["y"]), 200.0, "box sits below a high target")
	assert_eq(String((mid["tail"] as Dictionary)["side"]), "top", "tail points up at the target")
	# No hole → centered, no tail.
	var c := layer._place(null, "center", 432, 200)
	assert_almost_eq(float(c["x"]), (1920.0 - 432.0) / 2.0, 0.5)
	assert_null(c["tail"])
