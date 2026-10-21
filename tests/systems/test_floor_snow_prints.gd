extends SceneTree

## Boots fill with snow outside and print white tread on floors indoors, the inverse of the snow
## print, fainter each step, then melt away. Run: godot --headless --script tests/systems/test_floor_snow_prints.gd

var _failures: int = 0
var _started: bool = false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	var half_m := Vector2(BootSole.LENGTH_M * 0.5, 0.055)
	var image: Image = BootSole.floor_print_image(0.11, 800.0, 0)
	var lug_px: Vector2i = Vector2i(-1, -1)
	var groove_px: Vector2i = Vector2i(-1, -1)
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var uv := Vector2((float(y) + 0.5) / image.get_height() * 2.0 - 1.0, (float(x) + 0.5) / image.get_width() * 2.0 - 1.0)
			if BootSole.edge_m(uv, half_m) > -0.012 or uv.x < 0.2:
				continue
			var lug: float = BootSole.lug(uv, half_m)
			if lug > 0.99 and lug_px.x < 0:
				lug_px = Vector2i(x, y)
			elif lug < 0.01 and groove_px.x < 0:
				groove_px = Vector2i(x, y)
	_check(lug_px.x >= 0 and groove_px.x >= 0, "no lug or groove found on the forefoot")
	_check(image.get_pixelv(lug_px).a < 0.01, "a lug left snow on the floor")
	_check(image.get_pixelv(groove_px).a > 0.3, "a groove left no snow on the floor")
	_check(image.get_pixel(0, 0).a < 0.01, "snow outside the outsole")

	var prints := FloorSnowPrints.new()
	root.add_child(prints)
	prints.build()
	var at := Vector3.ZERO
	_check(prints.place_step(0, at, Vector3.UP, Vector3.FORWARD, true, 1.0) == null, "a dry boot printed indoors")
	_check(prints.place_step(0, at, Vector3.UP, Vector3.FORWARD, false, 1.0) == null, "a print outdoors")
	_check(is_equal_approx(prints.get_load(0), 1.0), "snow outside did not fill the tread")
	var alphas: Array[float] = []
	var first: Decal = null
	for step: int in range(30):
		var decal: Decal = prints.place_step(0, at + Vector3.FORWARD * 0.6 * step, Vector3.UP, Vector3.FORWARD, true, 0.0)
		if decal == null:
			break
		first = decal if first == null else first
		alphas.append(decal.modulate.a)
	_check(alphas.size() >= 6 and alphas.size() <= 14, "prints indoors: %d" % alphas.size())
	_check(alphas.size() > 1 and alphas[-1] < alphas[0], "prints did not fade step by step")
	_check(first != null and first.global_basis.z.is_equal_approx(Vector3.FORWARD), "the print does not point the way Henry walked")
	prints.melt(100.0, 20.0, true)
	_check(first.visible, "a print melted within 100 s in a warm room")
	prints.melt(400.0, 20.0, true)
	_check(not first.visible, "a print outlived its melt time")
	print("floor snow prints: all checks passed" if _failures == 0 else "floor snow prints: %d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error(message)
