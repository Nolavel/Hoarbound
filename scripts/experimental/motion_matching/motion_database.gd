class_name MotionDatabase
extends Resource

## Dense frame database for the motion-matching lab.
## One Resource owns the whole matrix; samples are rows, never per-frame
## Resources. Metadata keeps exact clip + animation time for playback.

@export var sample_rate_hz: float = 30.0
@export var feature_count: int = 0
@export var feature_names: PackedStringArray = PackedStringArray()
@export var features: PackedFloat32Array = PackedFloat32Array()
@export var clip_names: PackedStringArray = PackedStringArray()
@export var sample_clip_indices: PackedInt32Array = PackedInt32Array()
@export var sample_times: PackedFloat32Array = PackedFloat32Array()
@export var feature_means: PackedFloat32Array = PackedFloat32Array()
@export var feature_stddevs: PackedFloat32Array = PackedFloat32Array()


func configure_schema(names: PackedStringArray, rate_hz: float) -> void:
	feature_names = names
	feature_count = feature_names.size()
	sample_rate_hz = rate_hz
	features.clear()
	clip_names.clear()
	sample_clip_indices.clear()
	sample_times.clear()
	feature_means.clear()
	feature_stddevs.clear()


func append_sample(clip_name: StringName, exact_time: float, values: PackedFloat32Array) -> bool:
	if feature_count <= 0 or values.size() != feature_count:
		push_error("MotionDatabase: feature row has %d values, expected %d." % [values.size(), feature_count])
		return false
	var clip_index := clip_names.find(String(clip_name))
	if clip_index < 0:
		clip_index = clip_names.size()
		clip_names.append(String(clip_name))
	features.append_array(values)
	sample_clip_indices.append(clip_index)
	sample_times.append(exact_time)
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


func get_sample_clip_name(sample_index: int) -> String:
	if sample_index < 0 or sample_index >= sample_clip_indices.size():
		return ""
	var clip_index := sample_clip_indices[sample_index]
	if clip_index < 0 or clip_index >= clip_names.size():
		return ""
	return clip_names[clip_index]


func get_sample_time(sample_index: int) -> float:
	if sample_index < 0 or sample_index >= sample_times.size():
		return 0.0
	return sample_times[sample_index]


func rebuild_statistics() -> void:
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
		"sample_rate_hz": sample_rate_hz,
		"matrix_float_count": features.size(),
		"matrix_bytes": features.size() * 4,
		"statistics_ready": feature_means.size() == feature_count and feature_stddevs.size() == feature_count,
		"first_sample_time": 0.0 if sample_count == 0 else sample_times[0],
		"last_sample_time": 0.0 if sample_count == 0 else sample_times[sample_count - 1],
		"consistent": is_consistent(),
	}
