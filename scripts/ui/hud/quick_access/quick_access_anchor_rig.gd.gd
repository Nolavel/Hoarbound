class_name QuickAccessAnchorRig
extends Node3D

## Camera-facing orbit rig for the physical Quick Access anchors.
## Screen-space card following owns the visible smoothing, so this rig stays in sync.
## Runtime visual proof is exercised by tools/runtime/capture_quick_access.gd.

@export var enabled: bool = true

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


func _process(_delta: float) -> void:
	if not enabled:
		return
	snap_to_camera()


func _target_yaw(camera: Camera3D) -> float:
	var direction := camera.global_position - global_position
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return NAN
	direction = direction.normalized()
	return atan2(direction.x, direction.z)
