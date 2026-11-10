extends SceneTree

## The isolated 727 FrontWindow1 thaw probe (issue #281) still loads the real pane and scrubs:
## - the pane is the 12 source glass triangles of the landmark GLB, not a stand-in quad;
## - it opens on the natural thaw shader with its baked frost sheet; V3 stays one switch away for comparison;
## - thaw is clamped to 0..1 and reaches the material under both variants.
## Run: godot --headless --path . --script res://tests/systems/test_window_727_thaw_probe.gd

const PROBE: String = "res://tests/scenes/window_727_sdf_probe.tscn"
const NATURAL: String = "res://tests/demos/window_727_sdf/natural_thaw_glass_727.gdshader"
const V3: String = "res://tests/demos/window_727_sdf/sdf_frosted_glass_727.gdshader"

var _failures: int = 0


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var probe := (load(PROBE) as PackedScene).instantiate() as Window727SDFProbe
	root.add_child(probe)
	await process_frame
	_check(probe.is_valid(), "the probe did not load the real pane")
	_check(probe.verified_triangles() == 12, "the pane is %d source triangles, not 12" % probe.verified_triangles())
	var pane := probe.get_node_or_null(^"FrontWindow1_RealGlassOnly") as MeshInstance3D
	_check(pane != null, "the extracted pane is missing")
	if pane != null:
		var glass := pane.material_override as ShaderMaterial
		_check(glass != null and glass.shader.resource_path == NATURAL, "the probe does not open on the natural thaw")
		_check(glass.get_shader_parameter(&"frost_sheet") is Texture2D, "the natural thaw has no baked frost sheet")
		probe.set_thaw(1.7)
		_check(is_equal_approx(float(glass.get_shader_parameter(&"heated_warmth")), 1.0), "thaw above 1 was not clamped")
		probe.set_variant(&"v3")
		_check(glass.shader.resource_path == V3, "the V3 sheet is not one switch away")
		probe.set_thaw(0.4)
		_check(is_equal_approx(float(glass.get_shader_parameter(&"heated_warmth")), 0.4), "thaw did not reach the V3 material")
		probe.set_variant(&"natural")
		_check(glass.shader.resource_path == NATURAL and is_equal_approx(float(glass.get_shader_parameter(&"heated_warmth")), 0.4),
			"switching back lost the natural thaw or its progress")
	if _failures > 0:
		push_error("window thaw probe: %d check(s) failed" % _failures)
		quit(1)
		return
	print("window thaw probe: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("window thaw probe: %s" % message)
