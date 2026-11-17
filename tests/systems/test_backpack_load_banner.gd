extends SceneTree

## Small spatial/cost contract for the diegetic badge, not a renderer screenshot test.
const BANNER: PackedScene = preload("res://scenes/ui/hud/backpack_load_banner.tscn")
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var banner := BANNER.instantiate() as BackpackLoadBanner
	root.add_child(banner)
	await process_frame
	var badge := banner.get_node(^"Billboard") as Sprite3D
	var viewport := banner.get_node(^"BannerViewport") as SubViewport
	_check("not camera-facing", badge.billboard == 0)
	_check("one-sided", not badge.double_sided)
	_check("depth test enabled", not badge.no_depth_test)
	var physical_width: float = badge.pixel_size * float(viewport.size.x)
	_check("inside flat cloth width", physical_width <= BackpackModel.BODY.x - BackpackModel.ROUND_M * 2.0 + 0.001)
	_check("panel centred on pack and below top", absf(BackpackLoadBanner.PANEL_POSITION.x) < 0.001
		and BackpackLoadBanner.PANEL_POSITION.y > 0.1
		and BackpackLoadBanner.PANEL_POSITION.y < BackpackModel.BODY.y - 0.1)
	_check("not a perpetual redraw", viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS)
	var pack := BackpackModel.new()
	root.add_child(pack)
	await process_frame
	var transform := BackpackLoadBanner.panel_transform(pack)
	var expected := pack.to_global(pack.canvas_point(BackpackLoadBanner.PANEL_POSITION, Vector3.BACK)
		+ Vector3.BACK * BackpackLoadBanner.PANEL_DEPTH)
	_check("canvas follows real model", transform.origin.distance_to(expected) < 0.0001)
	_check("front normal follows pack", transform.basis.z.normalized().dot(pack.global_basis.z.normalized()) > 0.99)
	banner.set("_shown_kg", 10.0)
	banner.set("_maximum_kg", 30.0)
	banner.call("_update_text_and_fill")
	_check("weight requests a single redraw", viewport.render_target_update_mode == SubViewport.UPDATE_ONCE)
	print("test_backpack_load_banner: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(label: String, good: bool) -> void:
	if not good:
		_failures += 1
		push_error("Backpack load banner: %s" % label)
