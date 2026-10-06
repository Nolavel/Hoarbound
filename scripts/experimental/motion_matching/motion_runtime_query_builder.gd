class_name MotionRuntimeQueryBuilder
extends RefCounted

## Builds the same 33-feature schema used by MotionDatabaseBaker from the live
## Henry pose, measured root motion and a controller-predicted future path.
## No animation role/label participates in query construction.

const FUTURE_HORIZONS := [0.2, 0.5, 0.8]


func capture_pose(skeleton: Skeleton3D) -> Dictionary:
	if skeleton == null:
		return {}
	var pelvis_index := skeleton.find_bone("pelvis")
	var left_foot_index := skeleton.find_bone("foot_l")
	var right_foot_index := skeleton.find_bone("foot_r")
	if pelvis_index < 0 or left_foot_index < 0 or right_foot_index < 0:
		return {}

	# Store world positions plus the live skeleton root. build_query_trajectory()
	# removes root translation again before converting to facing space. This lets
	# the query observe a moving/rotating CharacterBody3D without polluting pose
	# features with absolute world coordinates.
	var world := skeleton.global_transform
	return {
		"root_origin": world.origin,
		"pelvis": world * skeleton.get_bone_global_pose(pelvis_index).origin,
		"left_foot": world * skeleton.get_bone_global_pose(left_foot_index).origin,
		"right_foot": world * skeleton.get_bone_global_pose(right_foot_index).origin,
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
	var trajectory := PackedVector2Array()
	var facings := PackedVector2Array()
	var desired_facing := _safe_local_facing(desired_local_facing)
	for horizon in FUTURE_HORIZONS:
		trajectory.append(desired_local_velocity * float(horizon))
		facings.append(desired_facing)
	return build_query_trajectory(
		previous_pose,
		current_pose,
		delta,
		root_velocity_world,
		root_angular_velocity,
		current_facing_world,
		trajectory,
		facings
	)


func build_query_trajectory(
		previous_pose: Dictionary,
		current_pose: Dictionary,
		delta: float,
		root_velocity_world: Vector3,
		root_angular_velocity: float,
		current_facing_world: Vector2,
		desired_trajectory_local: PackedVector2Array,
		desired_facings_local: PackedVector2Array
	) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	if previous_pose.is_empty() or current_pose.is_empty() or delta <= 0.000001:
		return values
	if desired_trajectory_local.size() != FUTURE_HORIZONS.size() or desired_facings_local.size() != FUTURE_HORIZONS.size():
		push_error("MotionRuntimeQueryBuilder: trajectory prediction must contain 0.2/0.5/0.8 s samples.")
		return values

	var facing := _safe_facing(current_facing_world)
	var previous_root: Vector3 = previous_pose.get("root_origin", Vector3.ZERO)
	var current_root: Vector3 = current_pose.get("root_origin", Vector3.ZERO)
	var previous_pelvis: Vector3 = previous_pose["pelvis"] - previous_root
	var current_pelvis: Vector3 = current_pose["pelvis"] - current_root
	var previous_left: Vector3 = previous_pose["left_foot"] - previous_pose["pelvis"]
	var current_left: Vector3 = current_pose["left_foot"] - current_pose["pelvis"]
	var previous_right: Vector3 = previous_pose["right_foot"] - previous_pose["pelvis"]
	var current_right: Vector3 = current_pose["right_foot"] - current_pose["pelvis"]

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

	for point in desired_trajectory_local:
		values.append(point.x)
		values.append(point.y)
	for desired_facing in desired_facings_local:
		var safe_facing := _safe_local_facing(desired_facing)
		values.append(safe_facing.x)
		values.append(safe_facing.y)

	return values


func _safe_facing(facing: Vector2) -> Vector2:
	if facing.length_squared() <= 0.000001:
		return Vector2(0.0, 1.0)
	return facing.normalized()


func _safe_local_facing(facing: Vector2) -> Vector2:
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
