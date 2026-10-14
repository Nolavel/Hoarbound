@tool
extends Node
## Screenshots of the Reality dock at work, for docs: per address, Go to, then F, with how well F framed the building.
## Runs only when HOARBOUND_REALITY_EDITOR_CAPTURE names an output folder; quits the editor after.

const ENV: String = "HOARBOUND_REALITY_EDITOR_CAPTURE"
const QUERIES: Array[String] = ["907 whitehead", "1009 windsor"]
## Frames to wait for editor start-up; then until the detail chunk count holds for STREAM_QUIET_MS.
const SETTLE_FRAMES: int = 240
const STREAM_QUIET_MS: int = 20000

var dock: RealityEditorDock
var _out: String = ""
var _frame: int = 0
var _step: int = 0
var _next: int = SETTLE_FRAMES
var _query: int = 0
var _camera_before: Vector3 = Vector3.ZERO
var _stream_since: int = 0
var _stream_count: int = -1
var _report: Array = []


func _ready() -> void:
	_out = OS.get_environment(ENV)
	DirAccess.make_dir_recursive_absolute(_out)


func _process(_delta: float) -> void:
	_frame += 1
	if _frame < _next:
		return
	match _step:
		0:
			## The first open scans hundreds of chunk scenes; wait for it, then open the Reality editor scene.
			if EditorInterface.get_resource_filesystem().is_scanning():
				_next = _frame + 30
				return
			if dock.find_view() == null:
				EditorInterface.open_scene_from_path(RealityEditorDock.EDITOR_SCENE)
				_next = _frame + 120
				return
			EditorInterface.set_main_screen_editor("3D")
			_reveal_dock()
			print("capture demo: found %d for '%s'" % [dock.search_for(QUERIES[_query]), QUERIES[_query]])
			dock.go_to_selected()
			_next = _frame + 5
		1:
			## The plugin assembles one detail chunk per half second; cells at sea have no chunk.
			var count: int = dock.find_view().loaded_cells().size()
			if count != _stream_count:
				_stream_count = count
				_stream_since = Time.get_ticks_msec()
			if count == 0 or Time.get_ticks_msec() - _stream_since < STREAM_QUIET_MS:
				return
			_reveal_dock()
			_next = _frame + 5
		2:
			_shot("%d_go_to" % _query)
			_camera_before = _camera().global_position
			_press_focus()
			_next = _frame + 30
		3:
			_report_focus()
			_shot("%d_after_F" % _query)
			_query += 1
			if _query < QUERIES.size():
				print("capture demo: found %d for '%s'" % [dock.search_for(QUERIES[_query]), QUERIES[_query]])
				dock.go_to_selected()
				_stream_count = -1
				_step = 1
				_next = _frame + 5
				return
			var f: FileAccess = FileAccess.open(_out.path_join("focus_report.json"), FileAccess.WRITE)
			f.store_string(JSON.stringify(_report, " ", false))
			f.close()
			dock.identify_at_camera()
			_reveal_dock()
			_next = _frame + 20
		4:
			_shot("identified_at_camera")
			get_tree().quit()
	_step += 1


## Brings the Reality tab to the front; selecting a node switches the dock column to the Inspector.
func _reveal_dock() -> void:
	var child: Node = dock
	while child.get_parent() != null:
		var tabs: TabContainer = child.get_parent() as TabContainer
		if tabs != null:
			tabs.current_tab = child.get_index()
			return
		child = child.get_parent()


func _camera() -> Camera3D:
	return EditorInterface.get_editor_viewport_3d(0).get_camera_3d()


## The 3D view's input surface: the focusable control beside its SubViewportContainer.
func _surface() -> Control:
	var view: Node = EditorInterface.get_editor_viewport_3d(0).get_parent().get_parent()
	for child: Node in view.get_children(true):
		if child is Control and not child is SubViewportContainer and (child as Control).focus_mode != Control.FOCUS_NONE:
			return child as Control
	return null


## F in the 3D view: "Focus Selection" on the selected FocusMarker.
func _press_focus() -> void:
	var surface: Control = _surface()
	if surface != null:
		surface.grab_focus()
	for pressed: bool in [true, false]:
		var key: InputEventKey = InputEventKey.new()
		key.keycode = KEY_F
		key.physical_keycode = KEY_F
		key.pressed = pressed
		Input.parse_input_event(key)


## Camera distance after F against the distance at which the building's bounding sphere fills the view.
func _report_focus() -> void:
	var marker: Node3D = EditorInterface.get_edited_scene_root().find_child("FocusMarker") as Node3D
	var bounds: AABB = _bounds(dock.get(&"_current"))
	var radius: float = bounds.size.length() * 0.5
	var camera: Camera3D = _camera()
	var distance: float = camera.global_position.distance_to(bounds.get_center())
	var fits_at: float = radius / sin(deg_to_rad(camera.fov) * 0.5)
	var row: Dictionary = {"query": QUERIES[_query], "moved_m": snappedf(camera.global_position.distance_to(_camera_before), 0.1),
		"distance_m": snappedf(distance, 0.1), "bounds_radius_m": snappedf(radius, 0.1), "fits_at_m": snappedf(fits_at, 0.1),
		"marker_at_centre": marker.global_position.distance_to(bounds.get_center()) < 0.5,
		"in_view": camera.is_position_in_frustum(bounds.get_center()), "framed": distance >= fits_at * 0.9}
	_report.append(row)
	print("capture demo: focus ", row)


## Building record bounds, footprint extent from ground to roof (same rule as the dock's Go to).
func _bounds(b: Dictionary) -> AABB:
	var ring: Array = b.get("ring", [])
	var lo: Vector2 = Vector2(float(b["c"][0]), float(b["c"][1]))
	var hi: Vector2 = lo
	for i: int in range(0, ring.size() - 1, 2):
		lo = lo.min(Vector2(float(ring[i]), float(ring[i + 1])))
		hi = hi.max(Vector2(float(ring[i]), float(ring[i + 1])))
	return AABB(Vector3(lo.x, float(b["y"]), lo.y), Vector3(hi.x - lo.x, maxf(float(b["h"]), 1.0), hi.y - lo.y))


func _shot(name: String) -> void:
	get_tree().root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("capture demo: ", name)
