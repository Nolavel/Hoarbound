extends SceneTree

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for path: String in [
		"res://shaders/environment/terrain/island_terrain.gdshader",
		"res://shaders/environment/snow/snow_chunk_cover.gdshader",
		"res://shaders/environment/snow/snow_ground.gdshader",
		"res://shaders/environment/materials/stylized_environment.gdshader",
		"res://shaders/environment/materials/stylized_environment_double_sided.gdshader",
		"res://shaders/environment/ice/frozen_sea.gdshader",
		"res://shaders/environment/stylized_shadows.gdshader",
	]:
		_check(load(path) is Shader, "shader failed to load: %s" % path)

	var material := StylizedEnvironmentMaterial.make(Color.WHITE, 0.8)
	_check(material is ShaderMaterial, "opaque environment factory did not return ShaderMaterial")
	_check(material.shader != null, "environment ShaderMaterial has no shader")

	var double_sided := StylizedEnvironmentMaterial.make(Color.WHITE, 0.8, false, true)
	_check(double_sided is ShaderMaterial, "double-sided environment factory failed")
	_check(double_sided.shader != material.shader, "double-sided material did not select its cull-disabled shader")

	var source := StandardMaterial3D.new()
	source.albedo_color = Color(0.3, 0.4, 0.5)
	source.roughness = 0.77
	source.metallic = 0.2
	_check(
		StylizedEnvironmentMaterial.from_standard(source) is ShaderMaterial,
		"opaque StandardMaterial3D was not adapted"
	)

	var transparent := StandardMaterial3D.new()
	transparent.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_check(
		StylizedEnvironmentMaterial.from_standard(transparent) == transparent,
		"transparent material should stay on its original path"
	)

	## Reality chunk buildings and the shared winter trees take stylized lighting.
	_check(StylizedEnvironmentMaterial.make_static(Color(0.6, 0.6, 0.6), 0.9) is ShaderMaterial, "Reality building material bypasses stylized lighting")
	for key: String in WinterTreeMeshes.materials():
		_check(WinterTreeMeshes.materials()[key] is ShaderMaterial, "tree material %s bypasses stylized lighting" % key)

	## Stock Godot only: the contract reads its globals and no engine sampler.
	var contract_source := FileAccess.get_file_as_string(
		"res://shaders/environment/stylized_shadow.gdshaderinc"
	)
	_check(not contract_source.contains("sample_directional_shadow"), "shared contract calls an engine-patched sampler")
	for global_name: String in ["stylized_shadow_strength", "stylized_shadow_brush_mask", "stylized_shadow_brush_mix"]:
		_check(
			ProjectSettings.has_setting("shader_globals/%s" % global_name),
			"missing global shader parameter: %s" % global_name
		)
	var brush_mask: Dictionary = ProjectSettings.get_setting("shader_globals/stylized_shadow_brush_mask", {})
	_check(load(String(brush_mask.get("value", ""))) is Texture2D, "brush mask global does not point at a texture")

	if _failures > 0:
		push_error("stylized shadows: %d check(s) failed" % _failures)
		quit(1)
		return
	print("stylized shadows: shared production contract passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("stylized shadows: %s" % message)
