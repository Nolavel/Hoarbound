class_name MotionRuntimeQueryBuilder
extends RefCounted

## Builds the same 33-feature schema used by MotionDatabaseBaker, but from the
## live canonical Henry/UAL skeleton plus current motion and desired trajectory.
## Desired trajectory and desired facing are intentionally independent: a
## sideways/backward locomotion request must not implicitly rotate the body.
## CMU dataset facing is normalized upstream before it is compared in this local basis.

const FUTURE_HORIZONS := [0.2, 0.5, 0.8]


func capture_pose(skeleton: Skeleton3D) -> Dictionary:
	if skeleton == null:
		return {}
	var pelvis_index := skeleton.find_bone("pelvis")
	var left_foot_index := skeleton.find_bone("foot_l")
	var right_foot_index := skeleton.find_bone("foot_r")
	if pelvis_index < 0 or left_foot_index < 0 or right_foot_index < 0:
		return {}
	return {
		"pelvis": skeleton.get_bone_global_pose(pelvis_index).origin,
		"left_foot": skeleton.get_bone_global_pose(left_foot_index).origin,
		"right_foot": skeleton.get_bone_global_pose(right_foot_index).origin,
	}


func build_query(
		previous_pose: Dictionary,
		current_pose: Dictionary,
		delta: float,
		root_velocity_world: Vector3,
		root_angular_velocity: float,
		current_facing_world: Vector2,
		desired_local_velocity: Vector2,
		desired_local_facing: Vector2 = Vector2(0.0, 1.0)
	) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	if previous_pose.is_empty() or current_pose.is_empty() or delta <= 0.000001:
		return values

	var facing := _safe_facing(current_facing_world)
	var previous_pelvis: Vector3 = previous_pose["pelvis"]
	var current_pelvis: Vector3 = current_pose["pelvis"]
	var previous_left: Vector3 = previous_pose["left_foot"] - previous_pelvis
	var current_left: Vector3 = current_pose["left_foot"] - current_pelvis
	var previous_right: Vector3 = previous_pose["right_foot"] - previous_pelvis
	var current_right: Vector3 = current_pose["right_foot"] - current_pelvis

	var root_velocity_local := _to_facing_space(root_velocity_world, facing)
	values.append(root_velocity_local.x)
	values.append(root_velocity_local.z)
	values.append(root_angular_velocity)

	_append_vec3(values, _to_facing_space(current_pelvis, facing))
	_append_vec3(values, _to_facing_space((current_pelvis - previous_pelvis) / delta, facing))
	_append_vec3(values, _to_facing_space(current_left, facing))
	_append_vec3(values, _to_facing_space((current_left - previous_left) / delta, facing))
	_append_vec3(values, _to_facing_space(current_right, facing))
	_append_vec3(values, _to_facing_space((current_right - previous_right) / delta, facing))

	for horizon in FUTURE_HORIZONS:
		values.append(desired_local_velocity.x * float(horizon))
		values.append(desired_local_velocity.y * float(horizon))

	var desired_facing := _safe_local_facing(desired_local_facing)
	for _horizon in FUTURE_HORIZONS:
		values.append(desired_facing.x)
		values.append(desired_facing.y)

	return values


func _safe_facing(facing: Vector2) -> Vector2:
	if facing.length_squared() <= 0.000001:
		return Vector2(0.0, -1.0)
	return facing.normalized()


func _safe_local_facing(facing: Vector2) -> Vector2:
	# MotionDatabaseBaker stores facing relative to the current heading, where
	# unchanged body heading is local +Z = (0, +1).
	if facing.length_squared() <= 0.000001:
		return Vector2(0.0, 1.0)
	return facing.normalized()


func _to_facing_xz(value: Vector3, facing: Vector2) -> Vector2:
	var forward := _safe_facing(facing)
	var right := Vector2(-forward.y, forward.x)
	var xz := Vector2(value.x, value.z)
	return Vector2(xz.dot(right), xz.dot(forward))


func _to_facing_space(value: Vector3, facing: Vector2) -> Vector3:
	var xz := _to_facing_xz(value, facing)
	return Vector3(xz.x, value.y, xz.y)


func _append_vec3(values: PackedFloat32Array, value: Vector3) -> void:
	values.append(value.x)
	values.append(value.y)
	values.append(value.z)
