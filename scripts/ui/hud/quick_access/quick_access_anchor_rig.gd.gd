class_name QuickAccessAnchorRig
extends Node3D

## Camera-facing orbit rig for the physical Quick Access anchors.
## Small camera motion is ignored so the HUD does not swim around Henry.
## Runtime visual proof is exercised by tools/runtime/capture_quick_access.gd.

@export_range(1.0, 30.0, 0.5) var orbit_follow_speed: float = 12.0
@export_range(0.0, 20.0, 0.5) var dead_zone_degrees: float = 6.0
@export var enabled: bool = true

var _hold_left: float = 0.0


func hold_for(seconds: float) -> void:
	_hold_left = maxf(_hold_left, seconds)


func snap_to_camera() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var target := _target_yaw(camera)
	if is_nan(target):
		return
	var rotation_now := global_rotation
	rotation_now.y = target
	global_rotation = rotation_now


func _process(delta: float) -> void:
	if not enabled:
		return
	if _hold_left > 0.0:
		_hold_left = maxf(0.0, _hold_left - delta)
		return

	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	var target_yaw := _target_yaw(camera)
	if is_nan(target_yaw):
		return

	var current_yaw := global_rotation.y
	var difference := absf(rad_to_deg(wrapf(target_yaw - current_yaw, -PI, PI)))
	if difference <= dead_zone_degrees:
		return

	var blend := 1.0 - exp(-orbit_follow_speed * delta)
	var rotation_now := global_rotation
	rotation_now.y = lerp_angle(current_yaw, target_yaw, blend)
	global_rotation = rotation_now


func _target_yaw(camera: Camera3D) -> float:
	var direction := camera.global_position - global_position
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return NAN
	direction = direction.normalized()
	return atan2(direction.x, direction.z)
