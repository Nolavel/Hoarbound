class_name SnowHeightFieldService
extends GPUParticlesCollisionHeightField3D

## Local GPU height-field collider for snowfall around Henry.
## It never follows the TPS camera. The expensive height map is refreshed only
## when Henry enters another coarse world-space cell while snow is active.

const HORIZONTAL_CELL_M: float = 8.0
const VERTICAL_CELL_M: float = 4.0
const HEIGHT_OFFSET_M: float = 2.0
const FIELD_SIZE: Vector3 = Vector3(48.0, 24.0, 48.0)

var _target: Node3D
var _active: bool = false
var _last_cell_position: Vector3 = Vector3(INF, INF, INF)
var _refresh_frames: int = 0


func _ready() -> void:
	size = FIELD_SIZE
	resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_256
	update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	follow_camera_enabled = false
	set_process(false)


func configure(target: Node3D) -> void:
	_target = target
	_last_cell_position = Vector3(INF, INF, INF)
	if _active:
		_update_cell(true)


func set_active(active: bool) -> void:
	if _active == active:
		return
	_active = active
	set_process(active)
	if active:
		_update_cell(true)


## Re-renders the field: geometry under it changed without Henry changing cell (a chunk streamed in).
func refresh() -> void:
	if not _active:
		return
	update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_ALWAYS
	_refresh_frames = 2


func _process(_delta: float) -> void:
	_update_cell(false)
	if _refresh_frames > 0:
		_refresh_frames -= 1
		if _refresh_frames == 0:
			update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED


func _update_cell(force: bool) -> void:
	if not _active or not is_instance_valid(_target):
		return

	var p: Vector3 = _target.global_position
	var cell_position := Vector3(
		snappedf(p.x, HORIZONTAL_CELL_M),
		snappedf(p.y + HEIGHT_OFFSET_M, VERTICAL_CELL_M),
		snappedf(p.z, HORIZONTAL_CELL_M)
	)
	if force or not cell_position.is_equal_approx(_last_cell_position):
		_last_cell_position = cell_position
		global_position = cell_position
