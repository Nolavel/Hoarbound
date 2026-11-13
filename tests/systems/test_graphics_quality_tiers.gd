extends SceneTree

## LOW drops vegetation shadows and draws the sun's shadow in one split; MEDIUM/HIGH restore the
## authored state, also on vegetation streamed in later. Run: godot --headless --script <this>

const GRAPHICS: GDScript = preload("res://scripts/settings/graphics_quality.gd")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var sun := DirectionalLight3D.new()
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	root.add_child(sun)
	var policy := ShadowCasterPolicy.new()
	root.add_child(policy)
	var veg := Node3D.new()
	veg.name = "Vegetation"
	root.add_child(veg)
	var palms := MultiMeshInstance3D.new()
	veg.add_child(palms)
	var wall := MeshInstance3D.new()
	root.add_child(wall)
	await process_frame

	GRAPHICS.apply(self, &"low")
	await process_frame
	_check(palms.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "LOW kept the vegetation's shadow")
	_check(wall.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "LOW took a building's shadow")
	_check(sun.directional_shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL, "LOW kept more than one shadow split")
	var later := MultiMeshInstance3D.new()
	veg.add_child(later)
	await process_frame
	_check(later.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "vegetation streamed in on LOW casts a shadow")

	GRAPHICS.apply(self, &"high")
	await process_frame
	_check(palms.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "HIGH did not restore the vegetation's shadow")
	_check(sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, "HIGH did not restore the authored splits")
	GRAPHICS.apply(self, &"medium")
	await process_frame
	_check(later.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "MEDIUM dropped vegetation shadows")

	print("test_graphics_quality_tiers: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error("graphics quality tiers: FAIL: %s" % message)
