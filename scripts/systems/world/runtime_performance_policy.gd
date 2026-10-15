class_name RuntimePerformancePolicy
extends Node

## Small production performance policy for work that is safe to schedule at runtime.
## It deliberately keeps gameplay systems enabled: the Freeman/parallax sky still
## animates and camera collision still runs. The policy only reduces redundant work.

const CAMERA_OPENNESS_PROBE_COUNT: int = 5

var _day_night: DayNightManager
var _camera: TpsCamera


func _ready() -> void:
	set_process(true)
	call_deferred(&"_refresh_bindings")


func _process(_delta: float) -> void:
	_refresh_bindings()
	_apply_sky_policy()
	_apply_camera_policy()


func _refresh_bindings() -> void:
	if not is_instance_valid(_day_night):
		_day_night = get_parent().get_node_or_null(^"DayNightManager") as DayNightManager
	if not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_3d() as TpsCamera


func _apply_sky_policy() -> void:
	if _day_night == null or _day_night.sky_resource == null:
		return
	## Freeman/parallax changes cloud_time every rendered frame. Godot's automatic
	## mode already chooses incremental for custom uniforms, so explicitly choosing
	## incremental would be a no-op. For a genuinely dynamic sky the documented
	## fast path is realtime filtering at a 256 px radiance cubemap. This changes
	## only IBL/reflection filtering; the visible Freeman/parallax shader is intact.
	if _day_night.sky_resource.process_mode != Sky.PROCESS_MODE_REALTIME:
		_day_night.sky_resource.process_mode = Sky.PROCESS_MODE_REALTIME
	if _day_night.sky_resource.radiance_size != Sky.RADIANCE_SIZE_256:
		_day_night.sky_resource.radiance_size = Sky.RADIANCE_SIZE_256


func _apply_camera_policy() -> void:
	if _camera == null:
		return
	## Preserve the centre sweep, feelers, overlaps, doorway framing and thin-prop
	## fade logic. Only the adaptive room fan is reduced: five rays still sample
	## left / centre / right with intermediate coverage, down from seven.
	if _camera.probe_count > CAMERA_OPENNESS_PROBE_COUNT:
		_camera.probe_count = CAMERA_OPENNESS_PROBE_COUNT
