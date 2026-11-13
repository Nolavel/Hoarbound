extends SceneTree

## Covers IceCrackPresenter: creak stays invisible, cracks grow from the load point and
## never heal, a break opens one hole under Henry, a loaded save restores holes silently.
## Run: godot --headless --script tests/systems/test_ice_crack_presenter.gd

const STEP_S: float = 0.05
const PRESENTER: GDScript = preload("res://scripts/systems/ice/ice_crack_presenter.gd")

var _failures: int = 0
var _frame: int = 0
var _restored: Dictionary = {}


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_test_creaking_draws_no_cracks()
		_test_cracks_grow_from_the_load_point_and_never_heal()
		_test_a_break_opens_one_hole_under_henry()
		_test_hole_outline_is_shared_and_fits_henry()
		_test_tiles_outside_the_window_are_skipped()
		_restored = _start_save_restore()
		return false
	_finish_save_restore(_restored)
	if _failures > 0:
		push_error("ice_crack_presenter: %d check(s) failed" % _failures)
		quit(1)
		return true
	print("ice_crack_presenter: all checks passed")
	quit(0)
	return true


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("ice_crack_presenter: %s" % message)


## Shore is everything west of x = 0, as in tests/scenes/ice_lab.tscn.
func _make_rig() -> Dictionary:
	var body := Node3D.new()
	root.add_child(body)
	var field := IceField.new()
	field.profile = load("res://resources/ice/bay_ice.tres") as IceProfile
	field.shore_polygon = PackedVector2Array([Vector2(-20, 0), Vector2(0, 0), Vector2(0, 64), Vector2(-20, 64)])
	field.tracked_body = body
	field.set_physics_process(false)
	root.add_child(field)
	var presenter: IceCrackPresenter = PRESENTER.new()
	presenter.ice_field = field
	presenter.hole_fx_scene = load("res://scenes/environment/ice/ice_hole_fx.tscn") as PackedScene
	root.add_child(presenter)
	return {"body": body, "field": field, "presenter": presenter}


func _dispose(rig: Dictionary) -> void:
	for key: String in ["presenter", "field", "body"]:
		var node: Node = rig[key]
		root.remove_child(node)
		node.free()


## Stands on a point until the tile reaches a stage; returns false if it never does.
func _load_until(rig: Dictionary, point: Vector3, gait: IceField.Gait, stage: IceField.Stage) -> bool:
	var field: IceField = rig["field"]
	var body: Node3D = rig["body"]
	body.global_position = point
	field.set_gait(gait)
	var tile: Vector2i = field.world_to_tile(point)
	for i: int in range(4000):
		if field.get_stage(tile) == stage:
			return true
		field.step(point, STEP_S)
	return false


func _test_creaking_draws_no_cracks() -> void:
	var rig := _make_rig()
	var point := Vector3(30.0, 0.0, 30.0)
	var tile: Vector2i = (rig["field"] as IceField).world_to_tile(point)
	var presenter: IceCrackPresenter = rig["presenter"]
	_check(_load_until(rig, point, IceField.Gait.STILL, IceField.Stage.CREAKING), "thin ice never creaked")
	_check(presenter.get_growth(tile) == 0.0, "creaking already drew cracks: the audio-first warning is lost")
	_check(_load_until(rig, point, IceField.Gait.STILL, IceField.Stage.CRACKING), "thin ice never cracked")
	_check(
		presenter.get_growth(tile) >= IceCrackPresenter.FIRST_CRACK_GROWTH,
		"the first crack was invisible: growth %.3f" % presenter.get_growth(tile)
	)
	_dispose(rig)


func _test_cracks_grow_from_the_load_point_and_never_heal() -> void:
	var rig := _make_rig()
	var field: IceField = rig["field"]
	var presenter: IceCrackPresenter = rig["presenter"]
	var shakes: Array = []
	presenter.shake_requested.connect(func(strength: float, _s: float) -> void: shakes.append(strength))
	var point := Vector3(29.1, 0.0, 30.7)
	var tile: Vector2i = field.world_to_tile(point)
	_load_until(rig, point, IceField.Gait.STILL, IceField.Stage.CRACKING)
	var first: float = presenter.get_growth(tile)
	for i: int in range(6):
		field.step(point, STEP_S)
	var later: float = presenter.get_growth(tile)
	_check(later > first, "cracks did not grow under load: %.3f then %.3f" % [first, later])
	var origin: Vector3 = presenter.get_crack_origin(tile)
	_check(Vector2(origin.x, origin.z).distance_to(Vector2(point.x, point.z)) < 0.001, "cracks did not start under the load")
	var texel: Color = presenter.get_crack_image().get_pixel(tile.x, tile.y)
	var size: float = field.profile.tile_size_m
	_check(
		absf(texel.b - (point.x / size - float(tile.x))) < 0.001 and absf(texel.a - (point.z / size - float(tile.y))) < 0.001,
		"crack map origin %s does not match the load point" % str(texel)
	)
	_check(not shakes.is_empty(), "a crack step requested no camera shake")
	var away := Vector3(10.0, 0.0, 10.0)
	for i: int in range(400):
		field.step(away, STEP_S)
	_check(field.get_integrity(tile) > 0.0, "setup: the tile broke instead of recovering")
	_check(is_equal_approx(presenter.get_growth(tile), later), "cracks healed when the ice recovered")
	_dispose(rig)


func _test_a_break_opens_one_hole_under_henry() -> void:
	var rig := _make_rig()
	var field: IceField = rig["field"]
	var presenter: IceCrackPresenter = rig["presenter"]
	var opened: Array = []
	presenter.hole_opened.connect(func(tile: Vector2i, centre: Vector3) -> void: opened.append([tile, centre]))
	var point := Vector3(33.4, 0.0, 30.6)
	var tile: Vector2i = field.world_to_tile(point)
	_check(_load_until(rig, point, IceField.Gait.SPRINT, IceField.Stage.BROKEN), "sprinting the thinnest ice never broke it")
	_check(opened.size() == 1, "expected one hole, got %d" % opened.size())
	_check(presenter.has_hole(tile), "the broken tile has no hole")
	var centre: Vector3 = presenter.get_hole_centre(tile)
	_check(Vector2(centre.x, centre.z).distance_to(Vector2(point.x, point.z)) < 0.001, "the hole did not open under Henry")
	_check(presenter.is_in_hole(point), "Henry's own position is not inside the hole")
	_check(not presenter.is_in_hole(point + Vector3(2.0, 0.0, 0.0)), "ice 2 m from the hole counted as hole")
	_check(is_equal_approx(presenter.get_growth(tile), 1.0), "a hole without full cracks around it")
	var fx_count: int = presenter.get_child_count()
	_check(fx_count == 1, "expected one hole dressing, found %d" % fx_count)
	for i: int in range(20):
		field.step(point, STEP_S)
	_check(opened.size() == 1, "standing in the hole opened it again")
	_dispose(rig)


func _test_hole_outline_is_shared_and_fits_henry() -> void:
	for tile: Vector2i in [Vector2i(0, 0), Vector2i(-3, 5), Vector2i(7, -11)]:
		var phases: Vector2 = IceHoleShape.phases_for(tile)
		_check(phases.x >= 0.0 and phases.y >= 0.0, "negative phase for tile %s: the shader's mod() would differ" % str(tile))
		for step: int in range(16):
			var r: float = IceHoleShape.radius_at(tile, float(step) / 16.0 * TAU)
			_check(r > IceLabDirector.HOLE_CLEARANCE_M + 0.3, "hole too tight for Henry at tile %s: %.2f m" % [str(tile), r])
			_check(r < IceHoleShape.BASE_RADIUS_M * 1.32, "hole outline overshoots at tile %s: %.2f m" % [str(tile), r])


func _test_tiles_outside_the_window_are_skipped() -> void:
	var rig := _make_rig()
	var presenter: IceCrackPresenter = rig["presenter"]
	var far := Vector3(200.0, 0.0, 30.0)
	_load_until(rig, far, IceField.Gait.SPRINT, IceField.Stage.BROKEN)
	var tile: Vector2i = (rig["field"] as IceField).world_to_tile(far)
	_check(presenter.has_hole(tile), "a hole outside the window was not tracked")
	var image: Image = presenter.get_crack_image()
	_check(image.get_width() == presenter.window_tiles, "the crack map changed size")
	_dispose(rig)


func _start_save_restore() -> Dictionary:
	var source := _make_rig()
	var point := Vector3(31.0, 0.0, 34.0)
	_load_until(source, point, IceField.Gait.SPRINT, IceField.Stage.BROKEN)
	var data: Dictionary = (source["field"] as IceField).get_save_data()
	var tile: Vector2i = (source["field"] as IceField).world_to_tile(point)
	_dispose(source)
	var rig := _make_rig()
	var opened: Array = []
	(rig["presenter"] as IceCrackPresenter).hole_opened.connect(func(t: Vector2i, _c: Vector3) -> void: opened.append(t))
	(rig["field"] as IceField).load_save_data(data)
	rig["tile"] = tile
	rig["opened"] = opened
	return rig


func _finish_save_restore(rig: Dictionary) -> void:
	var presenter: IceCrackPresenter = rig["presenter"]
	var tile: Vector2i = rig["tile"]
	_check(presenter.has_hole(tile), "a hole from the save was not shown")
	_check((rig["opened"] as Array).is_empty(), "loading a save replayed the break")
	_check(presenter.get_child_count() == 0, "loading a save spawned a splash")
	_dispose(rig)
