class_name Window727SDFProbe
extends Node3D

## Issue #281: an isolated REAL pane extracted from kw_727_fort_st.glb.
## No invented room, window mesh, game item or substitute glass geometry.

const SPEC_PATH: String = "res://data/world/key_west/reality/landmarks/kw_727_fort_st.json"
const GLB_PATH: String = "res://assets/world/key_west/landmarks/kw_727_fort_st.glb"
const SDF_SHADER: Shader = preload("res://tests/demos/window_727_sdf/sdf_frosted_glass_727.gdshader")
const NATURAL_SHADER: Shader = preload("res://tests/demos/window_727_sdf/natural_thaw_glass_727.gdshader")
const BACKDROP_SHADER: Shader = preload("res://tests/demos/window_727_sdf/diagnostic_backdrop.gdshader")
const WHEEL_STEP: float = 0.02

var _window: MeshInstance3D
var _sdf: ShaderMaterial
var _label: Label
var _slider: HSlider
var _valid: bool = false
var _verified_triangles: int = 0
var _leaving: bool = false
var _esc_was_down: bool = false
var _variant: StringName = &"natural"

func _ready() -> void:
	set_process_input(true)
	set_process_unhandled_input(true)
	# Ignore a key that is already held when the window appears.
	_esc_was_down = Input.is_physical_key_pressed(KEY_ESCAPE) or Input.is_key_pressed(KEY_ESCAPE)
	_valid = _load_real_pane()
	if _valid:
		_make_diagnostic_background()
		_make_camera()
	_make_overlay()
	var window := get_window()
	if window != null and not window.window_input.is_connected(_on_window_input):
		window.window_input.connect(_on_window_input)
		window.grab_focus()
	if _valid:
		set_thaw(0.0)
		print("WINDOW_727_SCRUB_READY thaw=0 esc=keycode+physical")
	else:
		_label.text = "WINDOW FAILED TO LOAD.  Esc leaves."

func _process(_delta: float) -> void:
	# Embedded editor play often delivers Escape as key state and never as
	# ui_cancel, and the focused slider then swallows the action.
	var down := Input.is_physical_key_pressed(KEY_ESCAPE) or Input.is_key_pressed(KEY_ESCAPE)
	if down and not _esc_was_down:
		_leave()
	_esc_was_down = down

func is_valid() -> bool:
	return _valid

func verified_triangles() -> int:
	return _verified_triangles


## One vertex per corner, so a cleared pane does not draw each shared edge twice.
func _weld_pane(vertices: PackedVector3Array, normals: PackedVector3Array, texcoords: PackedVector2Array, colours: PackedColorArray) -> Array:
	var out_vertices := PackedVector3Array()
	var out_normals := PackedVector3Array()
	var out_uv := PackedVector2Array()
	var out_colours := PackedColorArray()
	var indices := PackedInt32Array()
	for i: int in vertices.size():
		var found := -1
		for j: int in out_vertices.size():
			if out_vertices[j].distance_squared_to(vertices[i]) > 1e-8:
				continue
			if out_uv[j].distance_squared_to(texcoords[i]) > 1e-8:
				continue
			found = j
			break
		if found < 0:
			found = out_vertices.size()
			out_vertices.append(vertices[i])
			out_normals.append(normals[i])
			out_uv.append(texcoords[i])
			out_colours.append(colours[i])
		indices.append(found)
	return [out_vertices, out_normals, out_uv, out_colours, indices]

## 0 is the whole pane frosted. 1 is the open thaw.
func set_thaw(progress: float) -> void:
	if not _valid:
		return
	progress = clampf(progress, 0.0, 1.0)
	if _slider != null:
		_slider.set_value_no_signal(progress)
	_apply_thaw(progress)

## &"natural" is the natural thaw; &"v3" is the imported SDF sheet, for comparison (V toggles).
func set_variant(variant: StringName) -> void:
	if not _valid:
		return
	_variant = &"v3" if variant == &"v3" else &"natural"
	_sdf.shader = SDF_SHADER if _variant == &"v3" else NATURAL_SHADER
	_apply_thaw(_slider.value if _slider != null else 0.0)

func set_test_time(seconds: float) -> void:
	set_thaw(clampf(seconds / 6.0, 0.0, 1.0))

func _apply_thaw(progress: float) -> void:
	_window.material_override = _sdf
	progress = clampf(progress, 0.0, 1.0)
	_sdf.set_shader_parameter(&"heated_warmth", progress)
	var radius: float = lerpf(0.001, 0.46, pow(progress, 0.85))
	var blobs: Array[Vector4] = []
	for point: Vector2 in [Vector2(0.35, 0.54), Vector2(0.62, 0.46), Vector2(0.49, 0.60)]:
		blobs.append(Vector4(point.x, point.y, radius, 0.0))
	while blobs.size() < 16:
		blobs.append(Vector4.ZERO)
	_sdf.set_shader_parameter(&"blob_data", blobs)
	_sdf.set_shader_parameter(&"blob_count", 3 if progress > 0.0 else 0)
	_label.text = "727 FRONTWINDOW1   %s   THAW %02d%%" % ["NATURAL THAW" if _variant == &"natural" else "V3 SDF SHEET", int(progress * 100.0)]

func _is_escape(event: InputEvent) -> bool:
	if event.is_action_pressed(&"ui_cancel"):
		return true
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			return key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE
	return false

func _on_window_input(event: InputEvent) -> void:
	if _is_escape(event):
		_leave()

func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	print("WINDOW_727_LEAVE")
	call_deferred("_quit_now")

func _quit_now() -> void:
	var tree := get_tree()
	if tree == null:
		return
	# quit() alone does not dismiss an embedded editor game on this build.
	tree.root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
	tree.quit()

func _input(event: InputEvent) -> void:
	if _is_escape(event):
		get_viewport().set_input_as_handled()
		_leave()
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo \
			and (event as InputEventKey).physical_keycode == KEY_V:
		set_variant(&"v3" if _variant == &"natural" else &"natural")

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var button := event as InputEventMouseButton
	if not button.pressed:
		return
	if button.button_index == MOUSE_BUTTON_WHEEL_UP:
		_nudge_thaw(-WHEEL_STEP)
	elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_nudge_thaw(WHEEL_STEP)
	else:
		return
	get_viewport().set_input_as_handled()

func _nudge_thaw(delta: float) -> void:
	if _slider == null:
		return
	set_thaw(_slider.value + delta)

func _on_slider_changed(value: float) -> void:
	_apply_thaw(value)

func _on_slider_gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var button := event as InputEventMouseButton
	if not button.pressed:
		return
	if button.button_index == MOUSE_BUTTON_WHEEL_UP:
		_nudge_thaw(-WHEEL_STEP)
	elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_nudge_thaw(WHEEL_STEP)
	else:
		return
	_slider.accept_event()

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

	# Preserve UV/COLOR already authored in the current main GLB.
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
			push_error("WINDOW_727_TEST_FAIL: missing source UV/COLOR")
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
			_verified_triangles += 1
			# The solid is a 2 cm box: pane, back face, and four edge lips.
			# The lips are the horizontal and vertical lines once the sheet clears.
			var e1 := Vector2(planar[1].x - planar[0].x, planar[1].y - planar[0].y)
			var e2 := Vector2(planar[2].x - planar[0].x, planar[2].y - planar[0].y)
			var pane_area := absf(e1.x * e2.y - e1.y * e2.x) * 0.5
			var face_z := (planar[0].z + planar[1].z + planar[2].z) / 3.0
			if pane_area < 0.2 or face_z > centre.z:
				continue
			var n: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
			for corner: int in range(3):
				vertices.append(tri[corner])
				normals.append(n)
				texcoords.append(source_uv[source_indices[k + corner]])
				colours.append(source_color[source_indices[k + corner]])
	instance.queue_free()
	if _verified_triangles != 12:
		push_error("WINDOW_727_TEST_FAIL: only %d source glass triangles for FrontWindow1" % _verified_triangles)
		return false
	if vertices.size() != 6:
		push_error("WINDOW_727_TEST_FAIL: pane face is %d vertices" % vertices.size())
		return false
	var mesh_arrays: Array = []
	mesh_arrays.resize(Mesh.ARRAY_MAX)
	var welded: Array = _weld_pane(vertices, normals, texcoords, colours)
	mesh_arrays[Mesh.ARRAY_VERTEX] = welded[0]
	mesh_arrays[Mesh.ARRAY_NORMAL] = welded[1]
	mesh_arrays[Mesh.ARRAY_TEX_UV] = welded[2]
	mesh_arrays[Mesh.ARRAY_COLOR] = welded[3]
	mesh_arrays[Mesh.ARRAY_INDEX] = welded[4]
	var copied_mesh: ArrayMesh = ArrayMesh.new()
	copied_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_arrays)
	_window = MeshInstance3D.new()
	_window.name = "FrontWindow1_RealGlassOnly"
	_window.mesh = copied_mesh
	_window.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_window)
	_sdf = ShaderMaterial.new()
	_sdf.shader = NATURAL_SHADER
	_sdf.set_shader_parameter(&"growth_seed", 0.28)
	_sdf.set_shader_parameter(&"melt_seed", 0.73)
	_sdf.set_shader_parameter(&"pane_aspect", width / height)
	_window.material_override = _sdf
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

func _make_overlay() -> void:
	var overlay := CanvasLayer.new()
	overlay.name = "FrostScrub"
	add_child(overlay)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(root)
	_label = Label.new()
	_label.position = Vector2(20.0, 16.0)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_color_override("font_color", Color(0.95, 0.97, 0.97))
	_label.add_theme_font_size_override("font_size", 19)
	root.add_child(_label)
	var hint := Label.new()
	hint.position = Vector2(20.0, 46.0)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.text = "Left is the whole pane frosted. Right opens the thaw. V compares with the V3 sheet. Esc leaves."
	hint.add_theme_color_override("font_color", Color(0.93, 0.95, 0.96))
	hint.add_theme_font_size_override("font_size", 20)
	root.add_child(hint)
	var bar := ColorRect.new()
	bar.color = Color(0.04, 0.05, 0.06, 0.88)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -78.0
	bar.offset_bottom = 0.0
	var frost_end := Label.new()
	frost_end.text = "FROST"
	frost_end.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frost_end.add_theme_color_override("font_color", Color(0.86, 0.91, 0.94))
	frost_end.add_theme_font_size_override("font_size", 18)
	root.add_child(frost_end)
	frost_end.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	frost_end.offset_left = 18.0
	frost_end.offset_top = -64.0
	frost_end.offset_right = 110.0
	frost_end.offset_bottom = -36.0
	var thaw_end := Label.new()
	thaw_end.text = "THAW"
	thaw_end.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	thaw_end.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thaw_end.add_theme_color_override("font_color", Color(0.86, 0.91, 0.94))
	thaw_end.add_theme_font_size_override("font_size", 18)
	root.add_child(thaw_end)
	thaw_end.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	thaw_end.offset_left = -110.0
	thaw_end.offset_top = -64.0
	thaw_end.offset_right = -18.0
	thaw_end.offset_bottom = -36.0
	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = 1.0
	_slider.step = 0.001
	_slider.value = 0.0
	# Clicks still drag. Keyboard focus would eat Escape as "release focus".
	_slider.focus_mode = Control.FOCUS_NONE
	_slider.mouse_filter = Control.MOUSE_FILTER_STOP
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.22, 0.26, 0.29)
	track.set_corner_radius_all(4)
	track.content_margin_top = 8.0
	track.content_margin_bottom = 8.0
	var filled := StyleBoxFlat.new()
	filled.bg_color = Color(0.78, 0.88, 0.92)
	filled.set_corner_radius_all(4)
	var handle := Image.create(16, 34, false, Image.FORMAT_RGBA8)
	handle.fill(Color(0.96, 0.98, 0.99))
	var handle_tex := ImageTexture.create_from_image(handle)
	_slider.add_theme_stylebox_override("slider", track)
	_slider.add_theme_stylebox_override("grabber_area", filled)
	_slider.add_theme_stylebox_override("grabber_area_highlight", filled)
	_slider.add_theme_icon_override("grabber", handle_tex)
	_slider.add_theme_icon_override("grabber_highlight", handle_tex)
	root.add_child(_slider)
	_slider.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_slider.offset_left = 118.0
	_slider.offset_right = -118.0
	_slider.offset_top = -58.0
	_slider.offset_bottom = -18.0
	_slider.value_changed.connect(_on_slider_changed)
	_slider.gui_input.connect(_on_slider_gui_input)
