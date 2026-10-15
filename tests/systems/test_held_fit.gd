extends SceneTree

## Item Fitter contract: transforms live on ItemResource and specialized props
## are created by the same factory used by the editor.
var _failures: int = 0


func _initialize() -> void:
	var prop := Node3D.new()
	var fit := HeldFit.new()
	fit.offset = Vector3(0.11, -0.22, 0.33)
	fit.rotation_deg = Vector3(12.0, 34.0, -56.0)
	fit.scale = Vector3(1.1, 0.9, 1.2)
	fit.apply_to(prop)
	_check(prop.position.is_equal_approx(fit.offset), "offset was not applied")
	_check(prop.rotation_degrees.is_equal_approx(fit.rotation_deg), "rotation was not applied")
	_check(prop.scale.is_equal_approx(fit.scale), "scale was not applied")

	var hammer: ItemResource = load("res://data/items/hammer.tres") as ItemResource
	var road_flare: ItemResource = load("res://data/items/road_flare.tres") as ItemResource
	_check(hammer != null and hammer.held_fit != null, "hammer has no authored HeldFit")
	_check(road_flare != null and road_flare.held_fit != null, "road flare has no authored HeldFit")
	if hammer != null and hammer.held_fit != null:
		_check(hammer.held_fit.hand == HeldFit.Hand.LEFT, "hammer moved off the primary hand")
		_check(hammer.held_fit.offset.is_equal_approx(Vector3(0, 0.12, 0.06)), "hammer fit lost the production socket offset")
		_check(hammer.held_fit.rotation_deg.is_equal_approx(Vector3(-55, 0, 0)), "hammer fit lost the production rotation")
	if road_flare != null and road_flare.held_fit != null:
		_check(road_flare.held_fit.hand == HeldFit.Hand.LEFT, "flare moved off the torch hand")
		_check(road_flare.held_fit.offset.is_equal_approx(Vector3(0.055, 0.1, 0.05)), "flare fit lost the production socket offset")
		_check(road_flare.held_fit.rotation_deg.is_equal_approx(Vector3(86, 0, 0)), "flare fit lost the upright torch pose")

	var hammer_prop: Node3D = HeldPropFactory.make(&"hammer", hammer)
	var flare_prop: Node3D = HeldPropFactory.make(&"road_flare", road_flare)
	_check(hammer_prop != null and hammer_prop.name == "HeldHammer" and hammer_prop.get_child_count() == 2,
		"factory did not build the runtime hammer")
	_check(flare_prop is HeldFlare, "factory did not instantiate the runtime HeldFlare")
	if hammer_prop != null:
		hammer_prop.free()
	if flare_prop != null:
		flare_prop.free()

	var legacy := Node3D.new()
	legacy.transform = Transform3D(Basis.from_euler(Vector3(-55.0, 0.0, 0.0) * (PI / 180.0)), Vector3(0.0, 0.12, 0.06))
	var before: Transform3D = legacy.transform
	HeldFit.apply_legacy_adjustment(legacy, &"knife")
	_check(not legacy.transform.is_equal_approx(before), "legacy generic-item adjustment became a no-op")
	legacy.free()
	prop.free()

	if _failures == 0:
		print("held_fit: all checks passed")
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("held_fit: " + message)
