extends SceneTree

## Grade crossfade: baked in-between LUTs are exact lerps, symmetric per pair, and the controller
## keeps the blend on the Environment LUT (no screen pass), falling back to a source LUT until baked.
## Run: godot --headless --script tests/systems/test_lut_blend_cache.gd

const STEPS: int = LutBlendCache.STEPS

var _failures: int = 0


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_check_lerp()
	_check_cache()
	await _check_controller()
	_finish()


func _check_lerp() -> void:
	var a := PackedByteArray([0, 255, 100])
	var b := PackedByteArray([255, 0, 200])
	_check(LutBlendCache.lerp_bytes(a, b, 0.0) == a and LutBlendCache.lerp_bytes(a, b, 1.0) == b, "lerp ends are not the source bytes")
	_check(LutBlendCache.lerp_bytes(a, b, 0.5) == PackedByteArray([128, 128, 150]), "lerp midpoint is wrong")


func _check_cache() -> void:
	var cache := LutBlendCache.new()
	_check(cache.add_slices(&"a", _volume(0)) and cache.add_slices(&"b", _volume(160)), "cache rejected matching volumes")
	_check(not cache.add_slices(&"c", _volume(10, 3)), "cache accepted a volume of another size")
	_check(cache.get_slices(&"a", &"b", STEPS / 2).is_empty(), "cache served a step before the bake")
	cache.start_bake()
	cache.wait()
	_check(cache.is_baked(), "cache does not report the finished bake")
	var mid: Array[Image] = cache.get_slices(&"a", &"b", STEPS / 2)
	_check(mid.size() == 2 and mid[1].get_pixel(1, 1).r8 == 80, "midpoint step is not halfway")
	var forward: Array[Image] = cache.get_slices(&"a", &"b", 4)
	var back: Array[Image] = cache.get_slices(&"b", &"a", STEPS - 4)
	_check(not forward.is_empty() and forward[0].get_data() == back[0].get_data(), "pair order changes the baked step")
	_check(cache.get_slices(&"a", &"b", 0).is_empty() and cache.get_slices(&"a", &"b", STEPS).is_empty(), "source steps should come from the source LUTs")


func _check_controller() -> void:
	var holder := WorldEnvironment.new()
	holder.environment = Environment.new()
	root.add_child(holder)
	var grade := ColorGradeController.new()
	grade.world_environment = holder
	grade.day_profile = load("res://resources/environment/color_grading/HFN_ColdAsh_Day.tres") as ColorGradeProfile
	grade.dusk_profile = load("res://resources/environment/color_grading/HFN_ColdAsh_Dusk.tres") as ColorGradeProfile
	grade.night_profile = load("res://resources/environment/color_grading/HFN_ColdAsh_Night.tres") as ColorGradeProfile
	grade.shelter_profile = load("res://resources/environment/color_grading/HFN_ColdAsh_Shelter.tres") as ColorGradeProfile
	root.add_child(grade)
	await process_frame
	var env: Environment = holder.environment
	grade.update_for_time(16.9)
	_check(env.adjustment_color_correction == grade.day_profile.lut, "unbaked blend below halfway is not the Day LUT")
	_check(env.adjustment_enabled, "grade adjustment switched off during a blend")
	var day_b: float = grade.day_profile.brightness
	var dusk_b: float = grade.dusk_profile.brightness
	var w: float = grade.get_blend_weight()
	_check(w > 0.0 and w < 0.5 and absf(env.adjustment_brightness - lerpf(day_b, dusk_b, w)) < 0.001, "brightness is not lerped with the blend")
	var cache := LutBlendCache.new()
	cache.add_slices(ColorGradeController.DAY_PROFILE_ID, _volume(0))
	cache.add_slices(ColorGradeController.DUSK_PROFILE_ID, _volume(160))
	cache.start_bake()
	cache.wait()
	grade.set(&"_lut_cache", cache)
	grade.update_for_time(17.0)
	var blended := env.adjustment_color_correction as ImageTexture3D
	_check(blended != null and blended.get_depth() == 2, "mid-corridor Environment LUT is not the baked in-between")
	grade.update_for_time(12.0)
	_check(env.adjustment_color_correction == grade.day_profile.lut, "outside the corridor the Day LUT is not restored")
	grade.queue_free()
	holder.queue_free()


func _volume(value: int, size: int = 2) -> Array[Image]:
	var out: Array[Image] = []
	for z: int in size:
		var image := Image.create_empty(size, size, false, Image.FORMAT_RGB8)
		image.fill(Color8(value, value, value))
		out.append(image)
	return out


func _finish() -> void:
	if _failures > 0:
		push_error("lut blend cache: %d check(s) failed" % _failures)
		quit(1)
		return
	print("lut blend cache: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("lut blend cache: " + message)
