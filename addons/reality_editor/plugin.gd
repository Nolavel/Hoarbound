@tool
extends EditorPlugin
## Key West Reality editor: search dock, and detail chunks that follow the 3D editor camera.

## Seconds between editor camera reads; one chunk assembles per read at most.
const FOLLOW_INTERVAL_S: float = 0.5
## Farthest ground point the camera's look ray may pick as the detail focus.
const FOLLOW_MAX_M: float = 600.0

var _dock: RealityEditorDock
var _since: float = 0.0


func _enter_tree() -> void:
	_dock = RealityEditorDock.new()
	_dock.undo_redo = get_undo_redo()
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, _dock)


func _exit_tree() -> void:
	if _dock == null:
		return
	remove_control_from_docks(_dock)
	_dock.queue_free()
	_dock = null


func _process(delta: float) -> void:
	_since += delta
	if _since < FOLLOW_INTERVAL_S or _dock == null:
		return
	_since = 0.0
	var view: KeyWestRealityEditorView = _dock.find_view()
	var camera: Camera3D = EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	if view == null or camera == null:
		return
	view.set_focus(_ground_focus(camera))
	view.step()


## Where the camera looks on the ground, clamped to FOLLOW_MAX_M; the camera itself when level.
func _ground_focus(camera: Camera3D) -> Vector3:
	var ray: Vector3 = -camera.global_basis.z
	var origin: Vector3 = camera.global_position
	if ray.y > -0.05:
		return origin
	return origin + ray * minf(-origin.y / ray.y, FOLLOW_MAX_M)
