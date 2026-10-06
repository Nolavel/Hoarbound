class_name MotionDatabase
extends Resource

## Dense frame database: one feature matrix, exact clip + time per row, plus the
## root-space UAL pose and foot contacts, so playback never needs the source.

@export var sample_rate_hz: float = 30.0
@export var feature_count: int = 0
@export var feature_names: PackedStringArray = PackedStringArray()
@export var features: PackedFloat32Array = PackedFloat32Array()
@export var clip_names: PackedStringArray = PackedStringArray()
@export var clip_roles: PackedStringArray = PackedStringArray()
@export var clip_sources: PackedStringArray = PackedStringArray()
@export var sample_clip_indices: PackedInt32Array = PackedInt32Array()
@export var sample_times: PackedFloat32Array = PackedFloat32Array()
@export var sample_root_facings: PackedFloat32Array = PackedFloat32Array()
@export var pose_bone_names: PackedStringArray = PackedStringArray()
@export var pose_rotations: PackedFloat32Array = PackedFloat32Array()
@export var pose_pelvis_positions: PackedFloat32Array = PackedFloat32Array()
## Bit 0 = left foot contact, bit 1 = right foot contact.
@export var sample_contacts: PackedByteArray = PackedByteArray()
@export var samples_to_range_end: PackedInt32Array = PackedInt32Array()
@export var feature_means: PackedFloat32Array = PackedFloat32Array()
@export var feature_stddevs: PackedFloat32Array = PackedFloat32Array()


func configure_schema(names: PackedStringArray, rate_hz: float) -> void:
	feature_names = names
	feature_count = feature_names.size()
	sample_rate_hz = rate_hz
	features.clear()
	clip_names.clear()
	clip_roles.clear()
	clip_sources.clear()
	sample_clip_indices.clear()
	sample_times.clear()
	sample_root_facings.clear()
	pose_bone_names.clear()
	pose_rotations.clear()
	pose_pelvis_positions.clear()
	sample_contacts.clear()
	feature_means.clear()
	feature_stddevs.clear()


func configure_pose_schema(bone_names: PackedStringArray) -> bool:
	if get_sample_count() > 0:
		push_error("MotionDatabase: pose schema must be configured before samples are appended.")
		return false
	pose_bone_names = bone_names
	pose_rotations.clear()
	pose_pelvis_positions.clear()
	return not pose_bone_names.is_empty()


func set_clip_metadata(clip_name: StringName, role: String = "", source: String = "") -> int:
	var clip_index := _ensure_clip(clip_name)
	if clip_index < 0:
		return -1
	if not role.is_empty():
		clip_roles[clip_index] = role
	if not source.is_empty():
		clip_sources[clip_index] = source
	return clip_index


func append_sample(
		clip_name: StringName,
		exact_time: float,
		values: PackedFloat32Array,
		pose_values: PackedFloat32Array = PackedFloat32Array(),
		root_facing: Vector2 = Vector2(0.0, 1.0),
		pelvis_position: Vector3 = Vector3.ZERO,
		contacts: int = 0
	) -> bool:
	if feature_count <= 0 or values.size() != feature_count:
		push_error("MotionDatabase: feature row has %d values, expected %d." % [values.size(), feature_count])
		return false
	var expected_pose_values := pose_bone_names.size() * 4
	if expected_pose_values > 0 and pose_values.size() != expected_pose_values:
		push_error("MotionDatabase: pose row has %d values, expected %d." % [pose_values.size(), expected_pose_values])
		return false
	if expected_pose_values == 0 and not pose_values.is_empty():
		push_error("MotionDatabase: pose values supplied without a pose schema.")
		return false

	var clip_index := _ensure_clip(clip_name)
	features.append_array(values)
	if expected_pose_values > 0:
		pose_rotations.append_array(pose_values)
	pose_pelvis_positions.append(pelvis_position.x)
	pose_pelvis_positions.append(pelvis_position.y)
	pose_pelvis_positions.append(pelvis_position.z)
	sample_contacts.append(contacts)
	sample_clip_indices.append(clip_index)
	sample_times.append(exact_time)
	var facing := root_facing.normalized() if root_facing.length_squared() > 0.000001 else Vector2(0.0, 1.0)
	sample_root_facings.append(facing.x)
	sample_root_facings.append(facing.y)
	return true


func append_database(other: MotionDatabase) -> bool:
	if other == null or not other.is_consistent():
		push_error("MotionDatabase: cannot append an invalid database.")
		return false
	if get_sample_count() == 0 and feature_count == 0:
		configure_schema(other.feature_names, other.sample_rate_hz)
		if not other.pose_bone_names.is_empty():
			configure_pose_schema(other.pose_bone_names)
	else:
		if feature_count != other.feature_count or Array(feature_names) != Array(other.feature_names):
			push_error("MotionDatabase: feature schemas do not match.")
			return false
		if not is_equal_approx(sample_rate_hz, other.sample_rate_hz):
			push_error("MotionDatabase: sample rates do not match.")
			return false
		if Array(pose_bone_names) != Array(other.pose_bone_names):
			push_error("MotionDatabase: canonical pose schemas do not match.")
			return false

	for clip_index in range(other.clip_names.size()):
		set_clip_metadata(
			StringName(other.clip_names[clip_index]),
			other.clip_roles[clip_index],
			other.clip_sources[clip_index]
		)

	for sample_index in range(other.get_sample_count()):
		if not append_sample(
			StringName(other.get_sample_clip_name(sample_index)),
			other.get_sample_time(sample_index),
			other.get_feature_row(sample_index),
			other.get_pose_row(sample_index),
			other.get_sample_root_facing(sample_index),
			other.get_pelvis_position(sample_index),
			other.get_sample_contacts(sample_index)
		):
			return false
	return true


func get_sample_count() -> int:
	return sample_times.size()


func get_feature_row(sample_index: int) -> PackedFloat32Array:
	var row := PackedFloat32Array()
	if sample_index < 0 or sample_index >= get_sample_count() or feature_count <= 0:
		return row
	row.resize(feature_count)
	var start := sample_index * feature_count
	for feature_index in range(feature_count):
		row[feature_index] = features[start + feature_index]
	return row


func get_pose_row(sample_index: int) -> PackedFloat32Array:
	var row := PackedFloat32Array()
	var pose_width := pose_bone_names.size() * 4
	if pose_width <= 0 or sample_index < 0 or sample_index >= get_sample_count():
		return row
	row.resize(pose_width)
	var start := sample_index * pose_width
	for value_index in range(pose_width):
		row[value_index] = pose_rotations[start + value_index]
	return row


func get_pose_rotation(sample_index: int, pose_bone_index: int) -> Quaternion:
	if sample_index < 0 or sample_index >= get_sample_count():
		return Quaternion.IDENTITY
	if pose_bone_index < 0 or pose_bone_index >= pose_bone_names.size():
		return Quaternion.IDENTITY
	var pose_width := pose_bone_names.size() * 4
	var start := sample_index * pose_width + pose_bone_index * 4
	if start + 3 >= pose_rotations.size():
		return Quaternion.IDENTITY
	return Quaternion(
		pose_rotations[start],
		pose_rotations[start + 1],
		pose_rotations[start + 2],
		pose_rotations[start + 3]
	).normalized()


func get_sample_root_facing(sample_index: int) -> Vector2:
	var start := sample_index * 2
	if sample_index < 0 or sample_index >= get_sample_count() or start + 1 >= sample_root_facings.size():
		return Vector2(0.0, 1.0)
	var facing := Vector2(sample_root_facings[start], sample_root_facings[start + 1])
	return facing.normalized() if facing.length_squared() > 0.000001 else Vector2(0.0, 1.0)


func get_pelvis_position(sample_index: int) -> Vector3:
	var start := sample_index * 3
	if sample_index < 0 or start + 2 >= pose_pelvis_positions.size():
		return Vector3.ZERO
	return Vector3(pose_pelvis_positions[start], pose_pelvis_positions[start + 1], pose_pelvis_positions[start + 2])


func get_sample_contacts(sample_index: int) -> int:
	if sample_index < 0 or sample_index >= sample_contacts.size():
		return 0
	return sample_contacts[sample_index]


## Samples left in the same contiguous clip range after this one.
func get_samples_to_range_end(sample_index: int) -> int:
	if sample_index < 0 or sample_index >= samples_to_range_end.size():
		return 0
	return samples_to_range_end[sample_index]


func get_sample_clip_index(sample_index: int) -> int:
	if sample_index < 0 or sample_index >= sample_clip_indices.size():
		return -1
	return sample_clip_indices[sample_index]


func get_sample_clip_name(sample_index: int) -> String:
	var clip_index := get_sample_clip_index(sample_index)
	if clip_index < 0 or clip_index >= clip_names.size():
		return ""
	return clip_names[clip_index]


func get_sample_role(sample_index: int) -> String:
	var clip_index := get_sample_clip_index(sample_index)
	if clip_index < 0 or clip_index >= clip_roles.size():
		return ""
	return clip_roles[clip_index]


func get_sample_source(sample_index: int) -> String:
	var clip_index := get_sample_clip_index(sample_index)
	if clip_index < 0 or clip_index >= clip_sources.size():
		return ""
	return clip_sources[clip_index]


func get_sample_time(sample_index: int) -> float:
	if sample_index < 0 or sample_index >= sample_times.size():
		return 0.0
	return sample_times[sample_index]


func find_nearest_sample(clip_name: String, exact_time: float) -> int:
	var best_index := -1
	var best_distance := INF
	for sample_index in range(get_sample_count()):
		if get_sample_clip_name(sample_index) != clip_name:
			continue
		var distance := absf(get_sample_time(sample_index) - exact_time)
		if distance < best_distance:
			best_distance = distance
			best_index = sample_index
	return best_index


func get_next_sample_in_clip(sample_index: int) -> int:
	if sample_index < 0 or sample_index >= get_sample_count():
		return -1
	var next_index := sample_index + 1
	if next_index >= get_sample_count():
		return sample_index
	if sample_clip_indices[next_index] != sample_clip_indices[sample_index]:
		return sample_index
	return next_index


func rebuild_statistics() -> void:
	samples_to_range_end.resize(get_sample_count())
	var remaining := 0
	for sample_index in range(get_sample_count() - 1, -1, -1):
		var continues := sample_index + 1 < get_sample_count() and sample_clip_indices[sample_index + 1] == sample_clip_indices[sample_index]
		remaining = remaining + 1 if continues else 0
		samples_to_range_end[sample_index] = remaining
	feature_means.clear()
	feature_stddevs.clear()
	if feature_count <= 0 or get_sample_count() <= 0:
		return
	feature_means.resize(feature_count)
	feature_stddevs.resize(feature_count)
	var sums := PackedFloat64Array()
	var sums_sq := PackedFloat64Array()
	sums.resize(feature_count)
	sums_sq.resize(feature_count)
	for sample_index in range(get_sample_count()):
		var start := sample_index * feature_count
		for feature_index in range(feature_count):
			var value := float(features[start + feature_index])
			sums[feature_index] += value
			sums_sq[feature_index] += value * value
	var count := float(get_sample_count())
	for feature_index in range(feature_count):
		var mean := sums[feature_index] / count
		var variance := maxf(0.0, sums_sq[feature_index] / count - mean * mean)
		feature_means[feature_index] = mean
		feature_stddevs[feature_index] = maxf(sqrt(variance), 0.00001)


func is_consistent() -> bool:
	if feature_count <= 0:
		return false
	if features.size() != get_sample_count() * feature_count:
		return false
	if sample_clip_indices.size() != get_sample_count():
		return false
	if sample_root_facings.size() != get_sample_count() * 2:
		return false
	if pose_pelvis_positions.size() != get_sample_count() * 3 or sample_contacts.size() != get_sample_count():
		return false
	if clip_roles.size() != clip_names.size() or clip_sources.size() != clip_names.size():
		return false
	if not pose_bone_names.is_empty():
		if pose_rotations.size() != get_sample_count() * pose_bone_names.size() * 4:
			return false
	for clip_index in sample_clip_indices:
		if clip_index < 0 or clip_index >= clip_names.size():
			return false
	return true


func get_report() -> Dictionary:
	var sample_count := get_sample_count()
	return {
		"sample_count": sample_count,
		"feature_count": feature_count,
		"feature_names": Array(feature_names),
		"clip_count": clip_names.size(),
		"clip_names": Array(clip_names),
		"clip_roles": Array(clip_roles),
		"clip_sources": Array(clip_sources),
		"sample_rate_hz": sample_rate_hz,
		"matrix_float_count": features.size(),
		"matrix_bytes": features.size() * 4,
		"pose_bone_count": pose_bone_names.size(),
		"pose_float_count": pose_rotations.size(),
		"pose_bytes": pose_rotations.size() * 4,
		"root_facing_float_count": sample_root_facings.size(),
		"pose_space": "character_root_local_ual",
		"statistics_ready": feature_means.size() == feature_count and feature_stddevs.size() == feature_count,
		"first_sample_time": 0.0 if sample_count == 0 else sample_times[0],
		"last_sample_time": 0.0 if sample_count == 0 else sample_times[sample_count - 1],
		"consistent": is_consistent(),
	}


func _ensure_clip(clip_name: StringName) -> int:
	var clip_string := String(clip_name)
	var clip_index := clip_names.find(clip_string)
	if clip_index >= 0:
		return clip_index
	clip_index = clip_names.size()
	clip_names.append(clip_string)
	clip_roles.append("")
	clip_sources.append("")
	return clip_index
