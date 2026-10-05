extends SceneTree

const SENSOR_SCRIPT: GDScript = preload("res://scripts/actors/player/henry/components/foot_contact_sensor.gd")
const SHELL_SCRIPT: GDScript = preload("res://scripts/systems/world/snow/deterministic_snow_shell.gd")
const GRAPHICS: GDScript = preload("res://scripts/settings/graphics_quality.gd")

var _failures: int = 0


func _process(_delta: float) -> bool:
	_run()
	return true


func _run() -> void:
	_test_three_probe_contact_follows_camber()
	_test_stamp_basis_is_tangent_plane()
	_test_twenty_plants_are_retained_without_rendering()
	_test_local_contact_target_keeps_packed_field_large()
	_test_sensor_uses_pre_modifier_probe()
	_test_quality_profiles_keep_contact_precision()
	if _failures > 0:
		push_error("snow contact pipeline: %d check(s) failed" % _failures)
		quit(1)
		return
	print("snow contact pipeline: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("snow contact pipeline: %s" % message)


func _test_three_probe_contact_follows_camber() -> void:
	var n := Vector3(0.18, 0.97, 0.12).normalized()
	var feet := {
		"heel": Vector3(-0.03, 0.12, 0.14),
		"ball": Vector3(0.01, 0.10, 0.0),
		"toe": Vector3(0.04, 0.11, -0.15),
	}
	var hits := {
		"heel": {"position": Vector3(-0.03, 0.02, 0.14), "normal": n},
		"ball": {"position": Vector3(0.01, 0.0, 0.0), "normal": n},
		"toe": {"position": Vector3(0.04, -0.02, -0.15), "normal": n},
	}
	var contact: Dictionary = SENSOR_SCRIPT.resolve_contact_from_hits(feet, hits)
	_check(not contact.is_empty(), "three valid probes produced no contact")
	_check((contact["normal"] as Vector3).dot(n) > 0.999, "contact normal ignored road camber")
	var forward := (feet["toe"] as Vector3) - (feet["heel"] as Vector3)
	var tangent := forward - n * forward.dot(n)
	_check(tangent.length() > 0.1, "test tangent collapsed")


func _test_stamp_basis_is_tangent_plane() -> void:
	var n := Vector3(0.2, 0.96, 0.15).normalized()
	var f := Vector3(0.1, 0.2, -1.0).normalized()
	var encoded: Array[Vector4] = SHELL_SCRIPT.stamp_uniforms(
		Vector3(4.0, 2.0, -3.0), n, f, 0.15, 0.055,
		Vector2(-12.8, -12.8), 25.6, 0.08
	)
	_check(encoded.size() == 2, "stamp basis did not encode two rows")
	_check(is_equal_approx(encoded[1].z, 0.08), "stamp depth was not preserved")
	var centre_uv := (Vector2(4.0, -3.0) - Vector2(-12.8, -12.8)) / 25.6
	var d := centre_uv - Vector2(encoded[0].x, encoded[0].y)
	var local := Vector2(d.dot(Vector2(encoded[0].z, encoded[0].w)), d.dot(Vector2(encoded[1].x, encoded[1].y)))
	_check(local.length() < 1e-6, "stamp centre does not map to its own tangent basis")


func _test_twenty_plants_are_retained_without_rendering() -> void:
	var shell: Node = SHELL_SCRIPT.new()
	for i: int in range(20):
		var side: int = i % 2
		shell.call(&"_on_foot_planted", side, Vector3(float(i) * 0.3, 0.0, 0.0), Vector3.UP, Vector3.FORWARD, 1.5)
	_check(shell.call(&"get_pending_foot_stamp_count") == 20, "physics plants were dropped before any render pass")
	shell.free()


func _test_local_contact_target_keeps_packed_field_large() -> void:
	var before_graphics: Variant = ProjectSettings.get_setting("hfn/graphics/quality", "low")
	var before_snow: Variant = ProjectSettings.get_setting("hfn/snow/quality", "high")
	ProjectSettings.set_setting("hfn/graphics/quality", "high")
	ProjectSettings.set_setting("hfn/snow/quality", "high")
	var shell: Node3D = SHELL_SCRIPT.new()
	root.add_child(shell)
	var contact := shell.get_node("SnowContact") as SubViewport
	var packed := shell.get_node("SnowPacked0") as SubViewport
	var camera := contact.get_node("Camera3D") as Camera3D
	_check(contact.size == Vector2i(256, 256), "contact target is not 256²")
	_check(is_equal_approx(camera.size, 6.4), "contact camera does not cover 6.4 m")
	_check(packed.size == Vector2i(896, 896), "HIGH packed field is not 896²")
	shell.free()
	ProjectSettings.set_setting("hfn/graphics/quality", before_graphics)
	ProjectSettings.set_setting("hfn/snow/quality", before_snow)


func _test_sensor_uses_pre_modifier_probe() -> void:
	var source: String = FileAccess.get_file_as_string("res://scripts/actors/player/henry/components/foot_contact_sensor.gd")
	_check(source.contains("FootPoseProbe"), "sensor has no pre-modifier pose probe")
	_check(not source.contains("get_lift(side)"), "sensor still subtracts SnowFootModifier output")
	var probe: String = FileAccess.get_file_as_string("res://scripts/actors/player/henry/components/foot_pose_probe.gd")
	_check(probe.contains("extends SkeletonModifier3D"), "pre-modifier probe is not in the modifier chain")


func _test_quality_profiles_keep_contact_precision() -> void:
	var low: Dictionary = GRAPHICS.profile_for(&"low")
	var medium: Dictionary = GRAPHICS.profile_for(&"medium")
	var high: Dictionary = GRAPHICS.profile_for(&"high")
	_check(int(low["snow_packed_res"]) == 640, "LOW packed target changed")
	_check(int(medium["snow_packed_res"]) == 768, "MEDIUM packed target changed")
	_check(int(high["snow_packed_res"]) == 896, "HIGH packed target changed")
	_check(float(low["render_scale"]) < float(medium["render_scale"]), "render tiers are not ordered")
	_check(float(medium["render_scale"]) < float(high["render_scale"]), "render tiers are not ordered")
	_check(SHELL_SCRIPT.CONTACT_RES == 256, "quality tier changed contact precision")
	_check(is_equal_approx(SHELL_SCRIPT.CONTACT_WINDOW_M, 6.4), "quality tier changed contact window")
