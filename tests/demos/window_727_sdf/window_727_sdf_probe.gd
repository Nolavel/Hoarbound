class_name Window727SDFProbe
extends Node3D

## Issue #281: an isolated REAL pane extracted from kw_727_fort_st.glb.
## No invented room, window mesh, game item or substitute glass geometry.

const SPEC_PATH: String = "res://data/world/key_west/reality/landmarks/kw_727_fort_st.json"
const GLB_PATH: String = "res://assets/world/key_west/landmarks/kw_727_fort_st.glb"
const BASELINE: ShaderMaterial = preload("res://assets/world/key_west/landmarks/frosted_glass_727.tres")
const SDF_SHADER: Shader = preload("res://tests/demos/window_727_sdf/sdf_frosted_glass_727.gdshader")
const BACKDROP_SHADER: Shader = preload("res://tests/demos/window_727_sdf/diagnostic_backdrop.gdshader")

var _window: MeshInstance3D
var _plain: ShaderMaterial
var _sdf: ShaderMaterial
var _label: Label
var _valid: bool = false
var _verified_triangles: int = 0

func _ready() -> void:
	_valid = _load_real_pane()
	if not _valid:
		return
	_make_diagnostic_background()
	_make_camera()
	_make_label()
	set_test_time(0.0)

func is_valid() -> bool:
	return _valid

func verified_triangles() -> int:
	return _verified_triangles

func set_test_time(seconds: float) -> void:
	if not _valid:
		return
	# Exactly one six-second video: baseline 0..3 s, SDF 3..6 s.
	var second: bool = seconds >= 3.0
	var progress: float = clampf(fmod(seconds, 3.0) / 3.0, 0.0, 1.0)
	_window.material_override = _sdf if second else _plain
	_plain.set_shader_parameter(&"heated_warmth", progress)
	_sdf.set_shader_parameter(&"heated_warmth", progress)
	var radius: float = mix(0.001, 0.46, pow(progress, 0.85))
	var blobs: Array[Vector4] = []
	for point: Vector2 in [Vector2(0.35, 0.54), Vector2(0.62, 0.46), Vector2(0.49, 0.60)]:
		blobs.append(Vector4(point.x, point.y, radius, 0.0))
	while blobs.size() < 16:
		blobs.append(Vector4.ZERO)
	_sdf.set_shader_parameter(&"blob_data", blobs)
	_sdf.set_shader_parameter(&"blob_count", 3 if progress > 0.0 else 0)
	_label.text = "727 FORT ST  /  FRONTWINDOW1     %s     THAW: %02d%%" % [
		"BASELINE" if not second else "SDF MASK",
		int(progress * 100.0)
	]

func _load_real_pane() -> bool:
	var info: Variant = JSON.parse_string(FileAccess.get_file_as_string(SPEC_PATH))
	if not (info is Dictionary):
		push_error("WINDOW_727_TEST_FAIL: missing 727 landmark spec")
		return false
	var plan: Dictionary = info["interior"]
	var source_opening: Dictionary = {}
	for opening: Dictionary in plan["openings"]:
		if String(opening["name"]) == "FrontWindow1":
			source_opening = opening
			break
	if source_opening.is_empty() or source_opening["room"] != "waiting":
		push_error("WINDOW_727_TEST_FAIL: FrontWindow1 is not in waiting room")
		return false
	var measured_width: float = float(source_opening["width_m"])
	var y0: float = float(source_opening["y0"])
	var y1: float = float(source_opening["y1"])
	var width: float = measured_width
	var height: float = y1 - y0
	if absf(width - 2.0) > 0.001 or absf(height - 1.1) > 0.001:
		push_error("WINDOW_727_TEST_FAIL: unexpected spec window size")
		return false
	var uv_center: Array = source_opening["centre_uv"]
	var centre: Vector3 = Vector3(float(uv_center[0]), (y0 + y1) * 0.5, float(uv_center[1]))
	var yaw: float = float(plan["plan_yaw_rad"])
	var plan_basis: Basis = Basis(Vector3.UP, yaw)
	var imported: PackedScene = load(GLB_PATH) as PackedScene
	if imported == null:
		push_error("WINDOW_727_TEST_FAIL: actual 727 GLB missing")
		return false
	var instance: Node3D = imported.instantiate() as Node3D
	if instance == null:
		push_error("WINDOW_727_TEST_FAIL: GLB did not instantiate")
		return false
	add_child(instance)
	var glass: MeshInstance3D = instance.find_child("Glass", true, false) as MeshInstance3D
	if glass == null or glass.mesh == null:
		push_error("WINDOW_727_TEST_FAIL: actual GLB Glass mesh missing")
		instance.queue_free()
		return false

	# The existing GLB exporter includes POSITION + NORMAL, but no TEXCOORD_0
	# or COLOR_0. Extract ONLY the real triangle vertices for this opening.
	# Test-only UVs are derived by projecting each original vertex to the
	# existing plan frame. No QuadMesh replacement and no GLB rewrite.
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var texcoords: PackedVector2Array = PackedVector2Array()
	var colours: PackedColorArray = PackedColorArray()
	for si: int in range(glass.mesh.get_surface_count()):
		var arrays: Array = glass.mesh.surface_get_arrays(si)
		var source_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
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
			var n: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
			for corner: int in range(3):
				vertices.append(tri[corner])
				normals.append(n)
				var p: Vector3 = planar[corner]
				texcoords.append(Vector2(
					0.5 + (p.x - centre.x) / width,
					0.5 - (p.y - centre.y) / height))
				colours.append(Color(0.96, 1.0, 0.16, 1.0))
			_verified_triangles += 1
	instance.queue_free()
	if _verified_triangles < 4:
		push_error("WINDOW_727_TEST_FAIL: only %d source glass triangles for FrontWindow1" % _verified_triangles)
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
	_plain = BASELINE.duplicate(true) as ShaderMaterial
	_sdf = ShaderMaterial.new()
	_sdf.shader = SDF_SHADER
	for variant: ShaderMaterial in [_plain, _sdf]:
		variant.set_shader_parameter(&"growth_seed", 0.28)
		variant.set_shader_parameter(&"melt_seed", 0.73)
	_sdf.set_shader_parameter(&"pane_aspect", width / height)
	print("WINDOW_727_REAL_GLASS_OK source=%s window=FrontWindow1 room=waiting width=%.2f height=%.2f centre_uv=(%.3f,%.3f) selected_triangles=%d" % [
		GLB_PATH, width, height, centre.x, centre.z, _verified_triangles
	])
	set_meta(&"plan_basis", plan_basis)
	set_meta(&"window_centre", centre)
	return true

func _make_camera() -> void:
	var basis: Basis = get_meta(&"plan_basis") as Basis
	var centre: Vector3 = get_meta(&"window_centre") as Vector3
	var eye: Vector3 = basis * Vector3(centre.x, centre.y, centre.z - 2.45)
	var target: Vector3 = basis * centre
	var camera: Camera3D = Camera3D.new()
	camera.name = "WindowTestCamera"
	camera.fov = 36.0
	camera.near = 0.05
	camera.far = 50.0
	add_child(camera)
	camera.look_at_from_position(eye, target, Vector3.UP)
	camera.make_current()

func _make_diagnostic_background() -> void:
	# A flat CHECKERED TRANSPARENCY TARGET only, not any invented game world.
	var basis: Basis = get_meta(&"plan_basis") as Basis
	var centre: Vector3 = get_meta(&"window_centre") as Vector3
	var background: MeshInstance3D = MeshInstance3D.new()
	background.name = "TransparencyTarget_TestFixture"
	var board: QuadMesh = QuadMesh.new()
	board.size = Vector2(5.5, 3.5)
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = BACKDROP_SHADER
	board.material = mat
	background.mesh = board
	background.transform = Transform3D(basis, basis * Vector3(centre.x, centre.y, centre.z + 2.1))
	add_child(background)

func _make_label() -> void:
	var overlay: CanvasLayer = CanvasLayer.new()
	add_child(overlay)
	_label = Label.new()
	_label.position = Vector2(20.0, 14.0)
	_label.add_theme_color_override("font_color", Color(0.95, 0.97, 0.97))
	_label.add_theme_font_size_override("font_size", 19)
	overlay.add_child(_label)
