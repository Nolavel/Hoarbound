class_name QuickAccessAnchorRig
extends Node3D


@export_range(1.0, 30.0, 0.5)
var orbit_follow_speed: float = 12.0

@export var enabled: bool = true


func _process(delta: float) -> void:
	if not enabled:
		return

	var camera := get_viewport().get_camera_3d()

	if camera == null:
		return

	_face_camera_yaw(camera, delta)


func _face_camera_yaw(
	camera: Camera3D,
	delta: float
) -> void:

	var direction := (
		camera.global_position
		- global_position
	)

	# Нам нужен только поворот вокруг вертикальной оси.
	direction.y = 0.0

	if direction.length_squared() < 0.0001:
		return

	direction = direction.normalized()

	# Поворот root так, чтобы локальная плоскость anchors
	# всё время была ориентирована относительно камеры.
	var target_yaw := atan2(
		direction.x,
		direction.z
	)

	var current_yaw := global_rotation.y

	var blend := 1.0 - exp(
		-orbit_follow_speed * delta
	)

	var new_yaw := lerp_angle(
		current_yaw,
		target_yaw,
		blend
	)

	var rotation_now := global_rotation
	rotation_now.y = new_yaw

	global_rotation = rotation_now
