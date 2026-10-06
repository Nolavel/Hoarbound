class_name MotionDatabaseBaker
extends RefCounted

## Bakes features in Henry model space: root at origin, +Z forward, +X left.
## Velocities are world velocities seen from the root, at Henry scale.

const DEFAULT_SAMPLE_RATE_HZ := 30.0
const FUTURE_HORIZONS := [0.2, 0.5, 0.8]
## Shared with the live query so baked and runtime contacts mean the same.
const CONTACT_SPEED := 0.30
## Henry's ankle joint rests 0.104 m above the floor; 7 cm of lift still counts.
const CONTACT_ANKLE_HEIGHT := 0.17

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
	"left_foot_contact", "right_foot_contact",
]

var last_quality: Dictionary = {}
## Source times of the last bake's samples that failed the structural audit.
var last_failed_times := PackedFloat32Array()


func bake_range(
		retargeter: MotionRetargeter,
		clip_name: StringName,
		start_time: float,
		end_time: float,
		role: String = "",
		source_id: String = "",
		sample_rate_hz: float = DEFAULT_SAMPLE_RATE_HZ
	) -> MotionDatabase:
	var target := retargeter.target
	var duration := retargeter.get_duration()
	var segment_start := clampf(start_time, 0.0, duration)
	var segment_end := clampf(end_time, segment_start, duration)
	var count := int(floor((segment_end - segment_start) * sample_rate_hz)) + 1
	if count < 2:
		push_error("MotionDatabaseBaker: empty segment for %s." % String(clip_name))
		return null
	var dt := 1.0 / sample_rate_hz
	var pelvis := target.find_bone("pelvis")
	var foot_l := target.find_bone("foot_l")
	var foot_r := target.find_bone("foot_r")

	# One extra sample on each side (inside the clip) feeds central differences.
	var poses: Array[Dictionary] = []
	var model_positions: Array[Dictionary] = []
	var world_positions: Array[Dictionary] = []
	var times := PackedFloat32Array()
	for index in range(-1, count + 1):
		var time := clampf(segment_start + float(index) * dt, 0.0, duration)
		var pose := retargeter.retarget_at(time)
		var globals := target.forward_kinematics(pose["rotations"], pose["pelvis_position"])
		var track := retargeter.track_index(time)
		var yaw := Basis(Vector3.UP, atan2(retargeter.root_forwards[track].x, retargeter.root_forwards[track].z))
		var root := retargeter.root_positions[track]
		var model := {
			"pelvis": globals[pelvis].origin,
			"foot_l": globals[foot_l].origin,
			"foot_r": globals[foot_r].origin,
		}
		var world := {}
		for key in model.keys():
			world[key] = root + yaw * (model[key] as Vector3)
		times.append(time)
		poses.append({"pose": pose, "globals": globals})
		model_positions.append(model)
		world_positions.append(world)

	var database := MotionDatabase.new()
	database.configure_schema(PackedStringArray(FEATURE_NAMES), sample_rate_hz)
	database.configure_pose_schema(target.bone_names)
	database.set_clip_metadata(clip_name, role, source_id)
	var audit := MotionRetargetAudit.new(target)

	for index in range(1, count + 1):
		var time := times[index]
		var track := retargeter.track_index(time)
		var forward := retargeter.root_forwards[track]
		var yaw_inverse := Basis(Vector3.UP, atan2(forward.x, forward.z)).inverse()
		var values := PackedFloat32Array()

		var previous_track := retargeter.track_index(times[index - 1])
		var next_track := retargeter.track_index(times[index + 1])
		var span := maxf(float(next_track - previous_track) / retargeter.track_rate_hz, dt)
		var root_velocity := yaw_inverse * (retargeter.root_positions[next_track] - retargeter.root_positions[previous_track]) / span
		values.append(root_velocity.x)
		values.append(root_velocity.z)
		values.append(_yaw_delta(retargeter.root_forwards[previous_track], retargeter.root_forwards[next_track]) / span)

		var contacts := 0
		for key in ["pelvis", "foot_l", "foot_r"]:
			var position: Vector3 = model_positions[index][key]
			var velocity := yaw_inverse * ((world_positions[index + 1][key] as Vector3) - (world_positions[index - 1][key] as Vector3)) / (2.0 * dt)
			_append_vec3(values, position)
			_append_vec3(values, velocity)
			if key != "pelvis" and position.y < CONTACT_ANKLE_HEIGHT and Vector2(velocity.x, velocity.z).length() < CONTACT_SPEED:
				contacts |= 1 if key == "foot_l" else 2

		for horizon in FUTURE_HORIZONS:
			var future := retargeter.track_index(time + float(horizon))
			var delta := yaw_inverse * (retargeter.root_positions[future] - retargeter.root_positions[track])
			values.append(delta.x)
			values.append(delta.z)
		for horizon in FUTURE_HORIZONS:
			var future := retargeter.track_index(time + float(horizon))
			var local_facing := yaw_inverse * retargeter.root_forwards[future]
			values.append(local_facing.x)
			values.append(local_facing.z)
		values.append(1.0 if contacts & 1 else 0.0)
		values.append(1.0 if contacts & 2 else 0.0)

		var pose: Dictionary = poses[index]["pose"]
		audit.add_sample(poses[index]["globals"], pose["rotations"], poses[index - 1]["pose"]["rotations"], dt)
		if not database.append_sample(
			clip_name,
			time,
			values,
			_pack_rotations(pose["rotations"]),
			Vector2(forward.x, forward.z),
			pose["pelvis_position"],
			contacts
		):
			return null

	database.rebuild_statistics()
	last_quality = audit.get_report()
	last_failed_times.clear()
	for failed in audit.get_failed_samples():
		last_failed_times.append(times[failed + 1])
	return database


func _pack_rotations(rotations: Array[Quaternion]) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	values.resize(rotations.size() * 4)
	for bone_index in range(rotations.size()):
		var rotation := rotations[bone_index]
		values[bone_index * 4] = rotation.x
		values[bone_index * 4 + 1] = rotation.y
		values[bone_index * 4 + 2] = rotation.z
		values[bone_index * 4 + 3] = rotation.w
	return values


func _yaw_delta(from_forward: Vector3, to_forward: Vector3) -> float:
	return wrapf(atan2(to_forward.x, to_forward.z) - atan2(from_forward.x, from_forward.z), -PI, PI)


func _append_vec3(values: PackedFloat32Array, value: Vector3) -> void:
	values.append(value.x)
	values.append(value.y)
	values.append(value.z)
