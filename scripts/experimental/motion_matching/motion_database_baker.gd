class_name MotionDatabaseBaker
extends RefCounted

## Offline dense feature baker for the motion-matching lab.
## The source only needs to expose exact-time seek plus root trajectory/facing;
## pose features are always sampled from the canonical target Skeleton3D after
## retargeting. This keeps database rows independent of source rig naming.

const DEFAULT_SAMPLE_RATE_HZ := 30.0
const FUTURE_HORIZONS := [0.2, 0.5, 0.8]

const FEATURE_NAMES := [
	"root_velocity_x", "root_velocity_z", "root_angular_velocity",
	"pelvis_position_x", "pelvis_position_y", "pelvis_position_z",
	"pelvis_velocity_x", "pelvis_velocity_y", "pelvis_velocity_z",
	"left_foot_position_x", "left_foot_position_y", "left_foot_position_z",
	"left_foot_velocity_x", "left_foot_velocity_y", "left_foot_velocity_z",
	"right_foot_position_x", "right_foot_position_y", "right_foot_position_z",
	"right_foot_velocity_x", "right_foot_velocity_y", "right_foot_velocity_z",
	"trajectory_0_2_x", "trajectory_0_2_z",
	"trajectory_0_5_x", "trajectory_0_5_z",
	"trajectory_0_8_x", "trajectory_0_8_z",
	"facing_0_2_x", "facing_0_2_z",
	"facing_0_5_x", "facing_0_5_z",
	"facing_0_8_x", "facing_0_8_z",
]


func bake_seekable_skeleton(
		skeleton: Skeleton3D,
		clip_name: StringName,
		clip_length: float,
		seek_pose: Callable,
		root_position_at_time: Callable,
		root_facing_at_time: Callable,
		sample_rate_hz: float = DEFAULT_SAMPLE_RATE_HZ
	) -> MotionDatabase:
	if skeleton == null:
		push_error("MotionDatabaseBaker: target skeleton is null.")
		return null
	if not seek_pose.is_valid() or not root_position_at_time.is_valid() or not root_facing_at_time.is_valid():
		push_error("MotionDatabaseBaker: source callbacks are invalid.")
		return null
	if clip_length <= 0.0 or sample_rate_hz <= 0.0:
		push_error("MotionDatabaseBaker: invalid clip length/rate.")
		return null

	var pelvis_index := skeleton.find_bone("pelvis")
	var left_foot_index := skeleton.find_bone("foot_l")
	var right_foot_index := skeleton.find_bone("foot_r")
	if pelvis_index < 0 or left_foot_index < 0 or right_foot_index < 0:
		push_error("MotionDatabaseBaker: target skeleton needs pelvis/foot_l/foot_r.")
		return null

	var database := MotionDatabase.new()
	database.configure_schema(PackedStringArray(FEATURE_NAMES), sample_rate_hz)

	var sample_count := maxi(2, int(floor(clip_length * sample_rate_hz)))
	var sample_dt := 1.0 / sample_rate_hz
	var times := PackedFloat32Array()
	var pelvis_positions: Array[Vector3] = []
	var left_foot_positions: Array[Vector3] = []
	var right_foot_positions: Array[Vector3] = []
	var root_positions: Array[Vector3] = []
	var root_facings: Array[Vector2] = []
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		push_error("MotionDatabaseBaker: SceneTree is unavailable.")
		return null

	for sample_index in range(sample_count):
		var sample_time := float(sample_index) * sample_dt
		seek_pose.call(sample_time)
		# RetargetModifier3D applies after source pose changes; one process frame
		# matches the same path used by the visual capture harness.
		await tree.process_frame

		times.append(sample_time)
		pelvis_positions.append(skeleton.get_bone_global_pose(pelvis_index).origin)
		left_foot_positions.append(skeleton.get_bone_global_pose(left_foot_index).origin)
		right_foot_positions.append(skeleton.get_bone_global_pose(right_foot_index).origin)
		var root_position: Vector3 = root_position_at_time.call(sample_time)
		var root_facing_3d: Vector3 = root_facing_at_time.call(sample_time)
		root_positions.append(root_position)
		root_facings.append(_safe_facing(Vector2(root_facing_3d.x, root_facing_3d.z)))

	var left_relative: Array[Vector3] = []
	var right_relative: Array[Vector3] = []
	for sample_index in range(sample_count):
		left_relative.append(left_foot_positions[sample_index] - pelvis_positions[sample_index])
		right_relative.append(right_foot_positions[sample_index] - pelvis_positions[sample_index])

	for sample_index in range(sample_count):
		var facing := root_facings[sample_index]
		var values := PackedFloat32Array()

		var root_velocity := _derivative_vec3(root_positions, sample_index, sample_dt)
		var root_velocity_local := _to_facing_space(root_velocity, facing)
		values.append(root_velocity_local.x)
		values.append(root_velocity_local.z)
		values.append(_angular_velocity(root_facings, sample_index, sample_dt))

		_append_vec3(values, _to_facing_space(pelvis_positions[sample_index], facing))
		_append_vec3(values, _to_facing_space(_derivative_vec3(pelvis_positions, sample_index, sample_dt), facing))
		_append_vec3(values, _to_facing_space(left_relative[sample_index], facing))
		_append_vec3(values, _to_facing_space(_derivative_vec3(left_relative, sample_index, sample_dt), facing))
		_append_vec3(values, _to_facing_space(right_relative[sample_index], facing))
		_append_vec3(values, _to_facing_space(_derivative_vec3(right_relative, sample_index, sample_dt), facing))

		for horizon in FUTURE_HORIZONS:
			var future_index := mini(sample_count - 1, sample_index + int(round(float(horizon) * sample_rate_hz)))
			var future_delta := root_positions[future_index] - root_positions[sample_index]
			var local_delta := _to_facing_xz(future_delta, facing)
			values.append(local_delta.x)
			values.append(local_delta.y)

		for horizon in FUTURE_HORIZONS:
			var future_index := mini(sample_count - 1, sample_index + int(round(float(horizon) * sample_rate_hz)))
			var local_facing := _relative_facing(root_facings[future_index], facing)
			values.append(local_facing.x)
			values.append(local_facing.y)

		if not database.append_sample(clip_name, times[sample_index], values):
			return null

	database.rebuild_statistics()
	return database


func _derivative_vec3(values: Array[Vector3], index: int, sample_dt: float) -> Vector3:
	var previous := maxi(0, index - 1)
	var following := mini(values.size() - 1, index + 1)
	var duration := float(following - previous) * sample_dt
	if duration <= 0.000001:
		return Vector3.ZERO
	return (values[following] - values[previous]) / duration


func _angular_velocity(facings: Array[Vector2], index: int, sample_dt: float) -> float:
	var previous := maxi(0, index - 1)
	var following := mini(facings.size() - 1, index + 1)
	var duration := float(following - previous) * sample_dt
	if duration <= 0.000001:
		return 0.0
	return facings[previous].angle_to(facings[following]) / duration


func _safe_facing(facing: Vector2) -> Vector2:
	if facing.length_squared() <= 0.000001:
		return Vector2(0.0, -1.0)
	return facing.normalized()


func _to_facing_xz(value: Vector3, facing: Vector2) -> Vector2:
	var forward := _safe_facing(facing)
	var right := Vector2(-forward.y, forward.x)
	var xz := Vector2(value.x, value.z)
	return Vector2(xz.dot(right), xz.dot(forward))


func _to_facing_space(value: Vector3, facing: Vector2) -> Vector3:
	var xz := _to_facing_xz(value, facing)
	return Vector3(xz.x, value.y, xz.y)


func _relative_facing(future: Vector2, current: Vector2) -> Vector2:
	var forward := _safe_facing(current)
	var right := Vector2(-forward.y, forward.x)
	var future_safe := _safe_facing(future)
	return Vector2(future_safe.dot(right), future_safe.dot(forward))


func _append_vec3(values: PackedFloat32Array, value: Vector3) -> void:
	values.append(value.x)
	values.append(value.y)
	values.append(value.z)
