class_name Window727FrostProbe
extends Node3D

## Issue #281, new art iteration: an isolated REAL pane extracted from
## kw_727_fort_st.glb, lit by neutral light only.
##
## The pane extraction follows the Codex probe for issue #281 (the real
## FrontWindow1 triangles with their authored UV and COLOR); everything else
## here is new: no game world, no interior, no stove, no weather, no LUT, no
## streaming. A flat neutral backdrop and two neutral lights only, so the frost
## reads as white ice instead of taking the colour of the scene.

const SPEC_PATH: String = "res://data/world/key_west/reality/landmarks/kw_727_fort_st.json"
const GLB_PATH: String = "res://assets/world/key_west/landmarks/kw_727_fort_st.glb"
const ART_SHADER: Shader = preload("res://tests/demos/window_727_frost/frosted_glass_727_art_thaw.gdshader")

var _window: MeshInstance3D
var _material: ShaderMaterial
var _verified_triangles: int = 0
var _coverage_min: float = 1.0
var _coverage_max: float = 0.0


func _ready() -> void:
	if not _load_real_pane():
		return
	_make_lights()
	_make_camera()
	set_capture_time(0.0)


func is_valid() -> bool:
	return _window != null


func verified_triangles() -> int:
	return _verified_triangles


## The deterministic 6 second timeline of the brief:
## 0-1 s fully frosted, 1-3 s the thaw starts, 3-5 s the areas merge,
## 5-6 s most of the glass is clear but the cold corners keep white frost.
func warmth_at(seconds: float) -> float:
	if seconds <= 1.0:
		return 0.0
	if seconds <= 3.0:
		return 0.24 * smoothstep(1.0, 3.0, seconds)
	if seconds <= 5.0:
		return 0.24 + 0.38 * smoothstep(3.0, 5.0, seconds)
	return 0.62 + 0.38 * smoothstep(5.0, 6.0, seconds)


func set_capture_time(seconds: float) -> void:
	set_warmth(warmth_at(seconds))


## Direct warmth value, used by the pre-flight probe frame.
func set_warmth(value: float) -> void:
	if _material == null:
		return
	_material.set_shader_parameter(&"heated_warmth", clampf(value, 0.0, 1.0))


func _load_real_pane() -> bool:
	var info: Variant = JSON.parse_string(FileAccess.get_file_as_string(SPEC_PATH))
	if not (info is Dictionary):
		push_error("WINDOW_727_FROST_FAIL: missing 727 landmark spec")
		return false
	var plan: Dictionary = info["interior"]
	var source_opening: Dictionary = {}
	for opening: Dictionary in plan["openings"]:
		if String(opening["name"]) == "FrontWindow1":
			source_opening = opening
			break
	if source_opening.is_empty() or source_opening["room"] != "waiting":
		push_error("WINDOW_727_FROST_FAIL: FrontWindow1 is not in waiting room")
		return false
	var width: float = float(source_opening["width_m"])
	var y0: float = float(source_opening["y0"])
	var y1: float = float(source_opening["y1"])
	var height: float = y1 - y0
	var uv_center: Array = source_opening["centre_uv"]
	var centre: Vector3 = Vector3(float(uv_center[0]), (y0 + y1) * 0.5, float(uv_center[1]))
	var yaw: float = float(plan["plan_yaw_rad"])
	var plan_basis: Basis = Basis(Vector3.UP, yaw)
	var imported: PackedScene = load(GLB_PATH) as PackedScene
	if imported == null:
		push_error("WINDOW_727_FROST_FAIL: actual 727 GLB missing")
		return false
	var instance: Node3D = imported.instantiate() as Node3D
	if instance == null:
		push_error("WINDOW_727_FROST_FAIL: GLB did not instantiate")
		return false
	add_child(instance)
	var glass: MeshInstance3D = instance.find_child("Glass", true, false) as MeshInstance3D
	if glass == null or glass.mesh == null:
		push_error("WINDOW_727_FROST_FAIL: actual GLB Glass mesh missing")
		instance.queue_free()
		return false

	# Keep the authored UV and COLOR of the real glass triangles.
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var texcoords: PackedVector2Array = PackedVector2Array()
	var colours: PackedColorArray = PackedColorArray()
	for si: int in range(glass.mesh.get_surface_count()):
		var arrays: Array = glass.mesh.surface_get_arrays(si)
		var source_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var source_uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var source_color: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		if source_uv.size() != source_vertices.size() or source_color.size() != source_vertices.size():
			push_error("WINDOW_727_FROST_FAIL: missing source UV/COLOR")
			instance.queue_free()
			return false
		var source_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if source_indices.is_empty():
			for iv: int in range(source_vertices.size()):
				source_indices.append(iv)
		for k: int in range(0, source_indices.size() - 2, 3):
			var tri: Array[Vector3] = []
			var planar: Array[Vector3] = []
			for corner: int in range(3):
				var source_point: Vector3 = source_vertices[source_indices[k + corner]]
				var p: Vector3 = glass.global_transform * source_point
				tri.append(p)
				planar.append(plan_basis.inverse() * p)
			var mid: Vector3 = (planar[0] + planar[1] + planar[2]) / 3.0
			if absf(mid.x - centre.x) > width * 0.5 + 0.12:
				continue
			if absf(mid.z - centre.z) > 0.33:
				continue
			if mid.y < y0 - 0.07 or mid.y > y1 + 0.07:
				continue
			var all_inside: bool = true
			for q: Vector3 in planar:
				if absf(q.x - centre.x) > width * 0.5 + 0.12 or absf(q.z - centre.z) > 0.33 or q.y < y0 - 0.07 or q.y > y1 + 0.07:
					all_inside = false
			if not all_inside:
				continue
			var n: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
			for corner: int in range(3):
				vertices.append(tri[corner])
				normals.append(n)
				texcoords.append(source_uv[source_indices[k + corner]])
				var c: Color = source_color[source_indices[k + corner]]
				colours.append(c)
				_coverage_min = minf(_coverage_min, c.r)
				_coverage_max = maxf(_coverage_max, c.r)
			_verified_triangles += 1
	instance.queue_free()
	if _verified_triangles != 12:
		push_error("WINDOW_727_FROST_FAIL: only %d source glass triangles for FrontWindow1" % _verified_triangles)
		return false
	var mesh_arrays: Array = []
	mesh_arrays.resize(Mesh.ARRAY_MAX)
	mesh_arrays[Mesh.ARRAY_VERTEX] = vertices
	mesh_arrays[Mesh.ARRAY_NORMAL] = normals
	mesh_arrays[Mesh.ARRAY_TEX_UV] = texcoords
	mesh_arrays[Mesh.ARRAY_COLOR] = colours
	var copied_mesh: ArrayMesh = ArrayMesh.new()
	copied_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_arrays)
	_window = MeshInstance3D.new()
	_window.name = "FrontWindow1_RealGlassOnly"
	_window.mesh = copied_mesh
	_window.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_window)
	_material = ShaderMaterial.new()
	_material.shader = ART_SHADER
	_material.set_shader_parameter(&"growth_seed", 0.28)
	_material.set_shader_parameter(&"melt_seed", 0.73)
	_material.set_shader_parameter(&"pane_aspect", width / height)
	_window.material_override = _material
	print("WINDOW_727_FROST_PANE_OK source=%s window=FrontWindow1 room=waiting width=%.2f height=%.2f triangles=%d coverage=%.3f..%.3f" % [
		GLB_PATH, width, height, _verified_triangles, _coverage_min, _coverage_max
	])
	set_meta(&"plan_basis", plan_basis)
	set_meta(&"window_centre", centre)
	return true


func _make_lights() -> void:
	# Neutral light only. No sun colour, no stove, no world Environment tint.
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.name = "NeutralKey"
	key.light_color = Color(1.0, 1.0, 1.0)
	key.light_energy = 1.05
	key.shadow_enabled = false
	key.rotation_degrees = Vector3(-38.0, 28.0, 0.0)
	add_child(key)
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.name = "NeutralFill"
	fill.light_color = Color(1.0, 1.0, 1.0)
	fill.light_energy = 0.32
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-18.0, -132.0, 0.0)
	add_child(fill)
	var world: WorldEnvironment = WorldEnvironment.new()
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.40, 0.40, 0.40)
	# Godot 4.3+ defaults to AgX, which cools and desaturates the white frost.
	# This test wants a neutral white ice, so the tonemap is set explicitly.
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.70, 0.70, 0.70)
	env.ambient_light_energy = 0.55
	world.environment = env
	add_child(world)


func _make_camera() -> void:
	var basis: Basis = get_meta(&"plan_basis") as Basis
	var centre: Vector3 = get_meta(&"window_centre") as Vector3
	# The pane is 2.00 x 1.10 m. At 1.95 m with a 36 degree vertical field it
	# fills about 87 percent of the frame height.
	var eye: Vector3 = basis * Vector3(centre.x, centre.y, centre.z - 1.95)
	var target: Vector3 = basis * centre
	var camera: Camera3D = Camera3D.new()
	camera.name = "FrostCamera"
	camera.fov = 36.0
	camera.near = 0.05
	camera.far = 50.0
	add_child(camera)
	camera.look_at_from_position(eye, target, Vector3.UP)
	camera.make_current()
