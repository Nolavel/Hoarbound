class_name DevDioramaMap
extends Control

## Debug-only oblique world map rendered from the live World3D.
## Follow-only by design: the production scene has no free mouse cursor.

const GROUP: StringName = &"dev_diorama_map"
const PANEL_SIZE: Vector2 = Vector2(500.0, 320.0)
const PANEL_OFFSET: Vector2 = Vector2(20.0, 20.0)
const RENDER_SIZE: Vector2i = Vector2i(640, 360)
const CAMERA_HEIGHT_M: float = 90.0
const CAMERA_FOV_DEG: float = 50.0
const CAMERA_YAW_DEG: float = 12.0
const CAMERA_PITCH_DEG: float = 64.0
const FOLLOW_RESPONSE: float = 9.0
const MAP_LABEL_MASK: int = RenderLayers.DEV_MAP_LABEL
const LABEL_RADIUS_M: float = 95.0
const LABEL_REFRESH_DISTANCE_M: float = 7.0
const LABEL_REFRESH_SECONDS: float = 0.75

var _context: WorldContext
var _player: Node3D
var _terrain: IslandTerrain
var _city: ChunkedCityMassing
var _reality_index: RealityIndex
var _label_signature: String = ""
var _focus: Vector3 = Vector3.ZERO
var _label_focus := Vector2(INF, INF)
var _label_elapsed: float = LABEL_REFRESH_SECONDS
var _disabled_for_release: bool = false
var _runtime_toggle_enabled: bool = false
var _map_open: bool = false

var _panel: PanelContainer
var _map_area: Control
var _map_container: SubViewportContainer
var _viewport: SubViewport
var _camera: Camera3D
var _labels_root: Node3D
var _marker: Label
var _status_label: Label


func _ready() -> void:
	if not OS.is_debug_build():
		_disabled_for_release = true
		visible = false
		queue_free()
		return
	add_to_group(GROUP)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	get_viewport().size_changed.connect(_resize_to_viewport)
	_resize_to_viewport()
	set_process(false)
	visible = false
	var input_systems := get_node_or_null(^"/root/InputSystems")
	if input_systems != null and input_systems.has_signal(&"dev_map_toggle_pressed"):
		input_systems.connect(&"dev_map_toggle_pressed", _on_toggle_requested)


func on_world_ready(context: WorldContext) -> void:
	if _disabled_for_release or context == null:
		return
	_context = context
	_player = context.player
	_runtime_toggle_enabled = bool(context.world.get("enable_runtime_dev_map")) if context.world != null else false
	_map_open = false
	visible = false
	set_process(false)
	if context.world != null:
		_terrain = context.world.find_child("IslandTerrain", true, false) as IslandTerrain
		_city = _find_city(context.world)
	if context.camera != null:
		context.camera.cull_mask &= ~MAP_LABEL_MASK
	if _player == null:
		return
	_focus = _player.global_position
	_update_camera()
	_refresh_labels()
	_update_marker()


func is_runtime_toggle_enabled() -> bool:
	return _runtime_toggle_enabled


func is_map_open() -> bool:
	return _map_open


func _on_toggle_requested() -> void:
	if not _runtime_toggle_enabled or _disabled_for_release:
		return
	_map_open = not _map_open
	visible = _map_open
	set_process(_map_open)
	if _map_open:
		_focus = _player.global_position if _player != null else _focus
		_update_camera()
		_refresh_labels()
		_update_marker()


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player) or _camera == null:
		return
	var weight: float = 1.0 - exp(-FOLLOW_RESPONSE * maxf(delta, 0.0))
	_focus = _focus.lerp(_player.global_position, weight)
	_update_camera()
	_update_marker()
	_label_elapsed += maxf(delta, 0.0)
	var current_xz := Vector2(_focus.x, _focus.z)
	if _label_elapsed >= LABEL_REFRESH_SECONDS or current_xz.distance_to(_label_focus) >= LABEL_REFRESH_DISTANCE_M:
		_refresh_labels()


func get_height_m() -> float:
	return CAMERA_HEIGHT_M


func get_focus_world() -> Vector3:
	return _focus


func get_map_cull_mask() -> int:
	return _camera.cull_mask if _camera != null else 0


func get_map_image() -> Image:
	if _viewport == null or _viewport.get_texture() == null:
		return null
	return _viewport.get_texture().get_image()


func get_visible_label_count() -> int:
	return _labels_root.get_child_count() if _labels_root != null else 0


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "DioramaPanel"
	_panel.position = PANEL_OFFSET
	_panel.custom_minimum_size = PANEL_SIZE
	_panel.size = PANEL_SIZE
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_bottom", 8)
	_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(header)

	var title := Label.new()
	title.text = "DEV DIORAMA"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.95, 0.92, 0.84))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	_status_label = Label.new()
	_status_label.text = "FOLLOW  ·  %dm" % int(CAMERA_HEIGHT_M)
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_label.add_theme_font_size_override("font_size", 11)
	_status_label.add_theme_color_override("font_color", Color(0.68, 0.73, 0.77))
	header.add_child(_status_label)

	_map_area = Control.new()
	_map_area.name = "MapArea"
	_map_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_area.custom_minimum_size = Vector2(0.0, 272.0)
	_map_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_map_area)

	_map_container = SubViewportContainer.new()
	_map_container.name = "ViewportContainer"
	_map_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_container.stretch = true
	_map_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_container.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_map_area.add_child(_map_container)

	_viewport = SubViewport.new()
	_viewport.name = "MapViewport"
	_viewport.size = RENDER_SIZE
	_viewport.own_world_3d = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_map_container.add_child(_viewport)

	_camera = Camera3D.new()
	_camera.name = "DioramaCamera"
	## Moved in _process, so physics interpolation would draw (and project) it a tick behind.
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.fov = CAMERA_FOV_DEG
	_camera.near = 0.15
	_camera.far = 1200.0
	_camera.cull_mask = ((1 << 20) - 1) & ~(RenderLayers.SNOW_CONTACT | RenderLayers.SCREEN_PASS)
	_camera.environment = _map_environment()
	_viewport.add_child(_camera)
	_camera.make_current()

	_labels_root = Node3D.new()
	_labels_root.name = "MapOnlyLabels"
	_viewport.add_child(_labels_root)

	_marker = Label.new()
	_marker.name = "HenryMarker"
	_marker.text = "●"
	_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## Henry stands out on snow from 90 m: a large saturated red dot with a white rim.
	_marker.custom_minimum_size = Vector2(30.0, 30.0)
	_marker.add_theme_font_size_override("font_size", 30)
	_marker.add_theme_color_override("font_color", Color(1.0, 0.16, 0.1))
	_marker.add_theme_color_override("font_outline_color", Color(1.0, 1.0, 1.0, 0.95))
	_marker.add_theme_constant_override("outline_size", 7)
	_map_area.add_child(_marker)
	_marker.reset_size()


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.03, 0.035, 0.90)
	style.border_color = Color(0.52, 0.57, 0.61, 0.48)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	return style


## The world's depth fog is opaque by 100 m, about the map camera's distance to Henry; the map draws without it.
func _map_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.18, 0.2)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.65, 0.7)
	env.ambient_light_energy = 0.7
	return env


func _update_camera() -> void:
	if _camera == null:
		return
	var target: Vector3 = _focus
	var horizontal: float = CAMERA_HEIGHT_M / tan(deg_to_rad(CAMERA_PITCH_DEG))
	var offset := Vector3(0.0, CAMERA_HEIGHT_M, horizontal)
	offset = Basis(Vector3.UP, deg_to_rad(CAMERA_YAW_DEG)) * offset
	_camera.global_position = target + offset
	_camera.look_at(target, Vector3.UP)


func _update_marker() -> void:
	if _marker == null or _camera == null or _player == null or _map_area == null:
		return
	var world_point: Vector3 = _marker_world_point()
	if _camera.is_position_behind(world_point):
		_marker.visible = false
		return
	var marker_center: Vector2 = _project_world_to_map(world_point)
	if not is_finite(marker_center.x) or not is_finite(marker_center.y):
		_marker.visible = false
		return
	_marker.position = marker_center - _marker.size * 0.5
	_marker.visible = (
		marker_center.x >= 0.0
		and marker_center.y >= 0.0
		and marker_center.x <= _map_area.size.x
		and marker_center.y <= _map_area.size.y
	)


## Camera3D returns coordinates in its live SubViewport. SubViewportContainer
## with stretch enabled may resize that viewport, so RENDER_SIZE is only an
## initial allocation and must never be used as the runtime conversion scale.
func _project_world_to_map(world_point: Vector3) -> Vector2:
	if _camera == null or _viewport == null or _map_container == null:
		return Vector2(INF, INF)
	var viewport_size := Vector2(_viewport.size)
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		return Vector2(INF, INF)
	if _map_container.size.x <= 1.0 or _map_container.size.y <= 1.0:
		return Vector2(INF, INF)
	var viewport_point: Vector2 = _camera.unproject_position(world_point)
	var scale_to_display := Vector2(
		_map_container.size.x / viewport_size.x,
		_map_container.size.y / viewport_size.y
	)
	return _map_container.position + viewport_point * scale_to_display


## Geographic marker position: Henry's X/Z projected onto the world surface.
## Never use body/chest height here — this is an oblique perspective map, so a
## vertical offset becomes a false horizontal offset on screen.
func _marker_world_point() -> Vector3:
	var point: Vector3 = _player.global_position if _player != null else Vector3.ZERO
	if _terrain != null and is_instance_valid(_terrain) and _terrain.heightmap != null:
		point.y = _terrain.get_height(point.x, point.z)
		return point

	## Fallback for fixtures/worlds without IslandTerrain: use the bottom of
	## Henry's collision capsule rather than the CharacterBody origin.
	if _player != null:
		var collision := _player.find_child("Main_Collision", true, false) as CollisionShape3D
		if collision != null:
			var capsule := collision.shape as CapsuleShape3D
			if capsule != null:
				point.y = collision.global_position.y - capsule.height * 0.5 * collision.global_basis.y.length()
	return point


func _refresh_labels() -> void:
	if _labels_root == null:
		return
	_label_elapsed = 0.0
	_label_focus = Vector2(_focus.x, _focus.z)
	if _city == null:
		_city = _find_city(_context.world) if _context != null and _context.world != null else null
	var entries: Array[Dictionary] = []
	if _city != null:
		entries = _city.get_map_label_entries(_label_focus, LABEL_RADIUS_M)
	else:
		## Key West Reality has no ChunkedCityMassing: addresses come from the Reality building index.
		if _reality_index == null:
			_reality_index = RealityIndex.new()
			if not _reality_index.load_index():
				return
		entries = _reality_index.map_label_entries(_label_focus, LABEL_RADIUS_M)
	## The same labels as last time stay as they are: rebuilding them each refresh made them flicker.
	var signature: String = str(entries.map(func(e: Dictionary) -> Array: return [e.get("text", ""), e.get("position", Vector3.ZERO)]))
	if signature == _label_signature:
		return
	_label_signature = signature
	for child: Node in _labels_root.get_children():
		child.queue_free()
	for entry: Dictionary in entries:
		_add_world_label(entry)


func _add_world_label(entry: Dictionary) -> void:
	var label := Label3D.new()
	var kind := StringName(entry.get("kind", &"house"))
	var world_position: Vector3 = entry.get("position", Vector3.ZERO)
	label.text = String(entry.get("text", ""))
	label.position = world_position
	label.layers = MAP_LABEL_MASK
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	## Same size on screen at any camera height.
	label.fixed_size = true
	label.outline_size = 7
	if kind == &"street":
		label.font_size = 30
		label.pixel_size = 0.0017
		label.modulate = Color(0.90, 0.94, 0.98)
		label.outline_modulate = Color(0.025, 0.035, 0.045, 0.94)
	else:
		label.font_size = 24
		label.pixel_size = 0.0016
		label.modulate = Color(1.0, 0.82, 0.44)
		label.outline_modulate = Color(0.04, 0.03, 0.015, 0.94)
	_labels_root.add_child(label)


func _find_city(node: Node) -> ChunkedCityMassing:
	if node == null:
		return null
	if node is ChunkedCityMassing:
		return node as ChunkedCityMassing
	for child: Node in node.get_children():
		var found := _find_city(child)
		if found != null:
			return found
	return null


func _resize_to_viewport() -> void:
	size = get_viewport_rect().size
