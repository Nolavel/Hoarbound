@tool
extends Node
## Screenshots of the Reality dock at work, for docs: search, Go to + F, identify at camera.
## Runs only when HOARBOUND_REALITY_EDITOR_CAPTURE names an output folder; quits the editor after.

const ENV: String = "HOARBOUND_REALITY_EDITOR_CAPTURE"
const QUERY: String = "907 whitehead"
## Frames to wait for editor start-up; then until the detail chunk count holds for STREAM_QUIET_MS.
const SETTLE_FRAMES: int = 240
const STREAM_QUIET_MS: int = 150000
## Mouse wheel notches after F, as a user zooms out to see the whole house.
const ZOOM_OUT_NOTCHES: int = 12

var dock: RealityEditorDock
var _out: String = ""
var _frame: int = 0
var _step: int = 0
var _next: int = SETTLE_FRAMES
var _camera_before: Vector3 = Vector3.ZERO
var _notches: int = 0
var _stream_since: int = 0
var _stream_count: int = -1


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
			print("capture demo: found %d for '%s'" % [dock.search_for(QUERY), QUERY])
			_next = _frame + 60
		1:
			_shot("1_search")
			dock.go_to_selected()
			_next = _frame + 20
		2:
			_camera_before = _camera().global_position
			_press_focus()
			_next = _frame + 10
		3:
			if _notches == 0:
				_report_focus()
			_zoom_out()
			_notches += 1
			if _notches < ZOOM_OUT_NOTCHES:
				return
		4:
			## The plugin assembles one detail chunk per half second; cells at sea have no chunk.
			var count: int = dock.find_view().loaded_cells().size()
			if count != _stream_count:
				_stream_count = count
				_stream_since = Time.get_ticks_msec()
			if count == 0 or Time.get_ticks_msec() - _stream_since < STREAM_QUIET_MS:
				return
			print("capture demo: %d detail chunks" % count)
			_reveal_dock()
			_next = _frame + 5
		5:
			_shot("2_framed_after_F")
			dock.identify_at_camera()
			_reveal_dock()
			_next = _frame + 20
		6:
			_shot("3_identified_at_camera")
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


## F in the 3D view: "Focus Selection" centres the view on the selected FocusMarker.
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


func _report_focus() -> void:
	var marker: Vector3 = (EditorInterface.get_edited_scene_root().find_child("FocusMarker") as Node3D).global_position
	var at: Vector3 = _camera().global_position
	print("capture demo: F moved the camera %.1f m; now %.1f m from the marker" % [at.distance_to(_camera_before), at.distance_to(marker)])


func _zoom_out() -> void:
	var surface: Control = _surface()
	if surface == null:
		return
	for pressed: bool in [true, false]:
		var wheel: InputEventMouseButton = InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wheel.factor = 1.0
		wheel.pressed = pressed
		wheel.position = surface.get_global_rect().get_center()
		wheel.global_position = wheel.position
		Input.parse_input_event(wheel)


func _shot(name: String) -> void:
	var path: String = _out.path_join(name + ".png")
	get_tree().root.get_texture().get_image().save_png(path)
	print("capture demo: ", path)
