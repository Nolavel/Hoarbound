extends SceneTree

const QUEUE_SCRIPT: GDScript = preload("res://scripts/systems/world/snow/snow_interaction_queue.gd")
const HEIGHT_SCRIPT: GDScript = preload("res://scripts/systems/world/snow/snow_height_contract.gd")
const FIELD_SCRIPT: GDScript = preload("res://scripts/systems/world/snow/snow_field.gd")
const SHELL_SCRIPT: GDScript = preload("res://scripts/systems/world/snow/deterministic_snow_shell.gd")

var _failures: int = 0


func _process(_delta: float) -> bool:
	_run()
	return true


func _run() -> void:
	_test_queue_keeps_order_across_bounded_passes()
	_test_queue_canonicalizes_foot_basis()
	_test_height_contract_round_trips_world_mapping()
	_test_height_contract_preserves_old_compression_result()
	_test_deformation_channels_are_separate()
	_test_snow_field_matches_base_height_contract()
	_test_shell_uses_render_independent_queue()
	if _failures > 0:
		push_error("snow architecture: %d check(s) failed" % _failures)
		quit(1)
		return
	print("snow architecture: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("snow architecture: %s" % message)


func _flat_ground(_at: Vector2) -> Vector2:
	return Vector2(5.0, 0.0)


func _test_queue_keeps_order_across_bounded_passes() -> void:
	var queue: RefCounted = QUEUE_SCRIPT.new()
	for i: int in range(20):
		queue.call(&"push_foot_plant", i % 2, Vector3(float(i), 0.0, 0.0), Vector3.UP, Vector3.FORWARD, 1.5)
	_check(queue.call(&"size") == 20, "queue dropped accepted plants before a simulation pass")
	var first: Array = queue.call(&"peek_batch", 16)
	_check(first.size() == 16, "16-stamp pass did not expose exactly 16 events")
	for i: int in range(first.size()):
		_check(int((first[i] as Dictionary)["sequence"]) == i, "queue changed FIFO order in first batch")
	_check(queue.call(&"size") == 20, "peek consumed events before the deformation pass committed")
	queue.call(&"consume", 16)
	_check(queue.call(&"size") == 4, "bounded pass did not leave the overflow events queued")
	var second: Array = queue.call(&"peek_batch", 16)
	_check(second.size() == 4, "remaining batch size is not four")
	_check(int((second[0] as Dictionary)["sequence"]) == 16, "second pass did not resume at sequence 16")
	queue.call(&"consume", 999)
	_check(queue.call(&"is_empty"), "consume did not clamp safely at queue size")


func _test_queue_canonicalizes_foot_basis() -> void:
	var queue: RefCounted = QUEUE_SCRIPT.new()
	var n := Vector3(0.24, 0.95, 0.18).normalized()
	var event: Dictionary = queue.call(
		&"push_foot_plant", 0, Vector3(2.0, 4.0, -3.0), n, Vector3(0.1, 0.3, -1.0), 2.4
	)
	_check(not event.is_empty(), "valid foot plant was rejected")
	var up := event["normal"] as Vector3
	var forward := event["forward"] as Vector3
	_check(absf(up.length() - 1.0) < 0.0001, "queued normal is not normalized")
	_check(absf(forward.length() - 1.0) < 0.0001, "queued forward is not normalized")
	_check(absf(up.dot(forward)) < 0.0001, "queued forward is not tangent to the contact plane")
	var before: int = queue.call(&"size")
	var invalid: Dictionary = queue.call(&"push_foot_plant", 3, Vector3.ZERO, Vector3.UP, Vector3.FORWARD, 0.0)
	_check(invalid.is_empty(), "invalid foot side produced an interaction")
	_check(queue.call(&"size") == before, "invalid foot side changed queue size")


func _test_height_contract_round_trips_world_mapping() -> void:
	var origin := Vector2(-12.8, 7.25)
	var window_m: float = 25.6
	for at: Vector2 in [origin + Vector2(0.1, 0.1), origin + Vector2(12.3, 19.7), origin + Vector2(25.5, 25.5)]:
		var uv: Vector2 = HEIGHT_SCRIPT.world_to_uv(at, origin, window_m)
		var restored: Vector2 = HEIGHT_SCRIPT.uv_to_world(uv, origin, window_m)
		_check(restored.distance_to(at) < 0.00001, "world -> UV -> world mapping drifted")
		_check(HEIGHT_SCRIPT.contains_world(at, origin, window_m), "point inside field was rejected")
	_check(not HEIGHT_SCRIPT.contains_world(origin + Vector2(window_m, 1.0), origin, window_m), "exclusive outer edge leaked into field")
	var texel_m: float = 6.4 / 256.0
	var snapped: Vector2 = HEIGHT_SCRIPT.snapped_window_origin(Vector2(1.337, -2.711), 6.4, texel_m)
	_check(absf(snapped.x / texel_m - roundf(snapped.x / texel_m)) < 0.0001, "snapped contact origin is off the texel lattice on X")
	_check(absf(snapped.y / texel_m - roundf(snapped.y / texel_m)) < 0.0001, "snapped contact origin is off the texel lattice on Y")


func _test_height_contract_preserves_old_compression_result() -> void:
	var ground: float = 3.5
	var depth: float = 0.42
	var compression: float = 0.17
	var old_bottom: float = ground + depth - compression
	var contracted: float = HEIGHT_SCRIPT.visible_top(ground, depth, compression, 0.0)
	_check(is_equal_approx(contracted, old_bottom), "height contract changed existing top - sink behaviour")
	_check(is_equal_approx(HEIGHT_SCRIPT.deformation_delta(0.17, 0.05), -0.12), "compression/displaced delta has the wrong sign")
	_check(is_equal_approx(HEIGHT_SCRIPT.visible_top(ground, depth, 0.17, 0.05), ground + depth - 0.12), "combined compression + displaced height is wrong")
	_check(is_equal_approx(HEIGHT_SCRIPT.visible_top(ground, depth, 0.0, 0.08), ground + depth + 0.08), "displaced mass was not added to visible height")
	_check(is_equal_approx(HEIGHT_SCRIPT.visible_top(ground, depth, 2.0, 0.0), ground), "over-compression pushed snow below hard ground")
	_check(is_equal_approx(HEIGHT_SCRIPT.depth_from_top(ground, ground - 1.0), 0.0), "depth_from_top returned negative snow")


func _test_deformation_channels_are_separate() -> void:
	var accum: String = FileAccess.get_file_as_string("res://shaders/environment/snow/snow_accumulate.gdshader")
	var shape: String = FileAccess.get_file_as_string("res://shaders/environment/snow/snow_shape.gdshader")
	var ground: String = FileAccess.get_file_as_string("res://shaders/environment/snow/snow_ground.gdshader")
	_check(accum.contains("COLOR = vec4(compression, displaced, disturbance, density);"), "accumulator no longer writes RGBA deformation-state v2")
	_check(accum.contains("float disturbance = 0.0;"), "broken-crust disturbance channel is missing")
	_check(accum.contains("float density = 0.0;"), "density/freshness reserve channel is missing")
	_check(accum.contains("displaced += deposited;"), "boot displacement is not accumulated into the displaced channel")
	_check(accum.contains("vec4 restored = texture(restore, uv);"), "accumulator does not read multi-channel persistence restore")
	_check(not accum.contains("packed -= deposit"), "legacy signed packed/deposit representation returned")
	_check(shape.contains("vec4 state = texture(source, UV);"), "shape pass does not carry deformation-state v2")
	_check(shape.contains("float flatten = mix(0.05, 0.52"), "compacted-floor flattening is missing")
	_check(shape.contains("flatten *= 1.0 - clamp(state.b"), "broken crust no longer protects sharp edges from flattening")
	_check(not shape.contains("5x5 Gaussian"), "legacy common Gaussian blur returned")
	_check(ground.contains("varying float v_disturbance;"), "surface shader does not expose broken-crust state")
	_check(ground.contains("varying float v_density;"), "surface shader does not expose compacted density")
	_check(ground.contains("float local_delta = -v_packed + v_displaced + v_rim;"), "surface shader does not apply the shared compression/displacement sign convention")
	_check(ground.contains("float fracture = clamp(max(v_disturbance"), "surface fractures are not driven by persistent disturbance")


func _test_snow_field_matches_base_height_contract() -> void:
	var field: RefCounted = FIELD_SCRIPT.new()
	field.set("window_m", 6.4)
	field.set("res", 32)
	field.set("cover_depth_m", Vector2(0.25, 0.25))
	field.set("drift_m", 0.0)
	field.set("lee_m", 0.0)
	field.set("use_baked_baseline", true)
	field.set("ground_sampler", Callable(self, "_flat_ground"))
	field.call(&"rebuild", Vector2.ZERO, 1.0, Vector2(0.0, -1.0))
	var at := Vector2(3.2, 3.2)
	var top: float = field.call(&"get_snow_top", at.x, at.y)
	var depth: float = field.call(&"get_depth", at.x, at.y)
	_check(is_equal_approx(top, HEIGHT_SCRIPT.base_top(5.0, depth)), "SnowField top disagrees with ground + settled-depth contract")
	_check(depth > 0.2 and depth < 0.3, "test field did not build the expected settled pack")


func _test_shell_uses_render_independent_queue() -> void:
	var shell: Node = SHELL_SCRIPT.new()
	for i: int in range(33):
		shell.call(&"_on_foot_planted", i % 2, Vector3(float(i) * 0.2, 0.0, 0.0), Vector3.UP, Vector3.FORWARD, 1.0)
	_check(shell.call(&"get_pending_foot_stamp_count") == 33, "DeterministicSnowShell lost queued plants without a render pass")
	var source: String = FileAccess.get_file_as_string("res://scripts/systems/world/snow/deterministic_snow_shell.gd")
	_check(source.contains("snow_interaction_queue.gd"), "shell does not depend on SnowInteractionQueue")
	_check(source.contains("snow_height_contract.gd"), "shell does not depend on SnowHeightContract")
	_check(not source.contains("var _foot_stamps"), "legacy foot-stamp array still owns interactions")
	shell.free()
