class_name MotionMatcher
extends RefCounted

## Brute-force real-frame matcher; skips only range tails and the playing pose's
## neighbourhood. Normalization per quantity, after orangeduck/Motion-Matching.

const GROUPS := [
	{"name": "root_velocity", "first": 0, "count": 2, "weight": 1.0, "category": "velocity", "quantity": "root_velocity"},
	{"name": "root_angular_velocity", "first": 2, "count": 1, "weight": 0.5, "category": "velocity", "quantity": "angular_velocity"},
	{"name": "pelvis_position", "first": 3, "count": 3, "weight": 0.5, "category": "pose", "quantity": "pose_position"},
	{"name": "pelvis_velocity", "first": 6, "count": 3, "weight": 1.0, "category": "pose", "quantity": "pose_velocity"},
	{"name": "left_foot_position", "first": 9, "count": 3, "weight": 0.75, "category": "pose", "quantity": "pose_position"},
	{"name": "left_foot_velocity", "first": 12, "count": 3, "weight": 1.0, "category": "pose", "quantity": "pose_velocity"},
	{"name": "right_foot_position", "first": 15, "count": 3, "weight": 0.75, "category": "pose", "quantity": "pose_position"},
	{"name": "right_foot_velocity", "first": 18, "count": 3, "weight": 1.0, "category": "pose", "quantity": "pose_velocity"},
	{"name": "trajectory_position", "first": 21, "count": 6, "weight": 1.0, "category": "trajectory", "quantity": "trajectory_position"},
	{"name": "trajectory_facing", "first": 27, "count": 6, "weight": 1.5, "category": "facing", "quantity": "trajectory_facing"},
]
const CATEGORIES := ["velocity", "pose", "trajectory", "facing"]
## Frames that cannot finish a crossfade before their range ends.
const DEFAULT_END_MARGIN_SAMPLES := 10

var end_margin_samples: int = DEFAULT_END_MARGIN_SAMPLES

var _database_id := 0
var _scales := PackedFloat32Array()
var _means := PackedFloat32Array()
var _normalized := PackedFloat32Array()
var _category_of_feature := PackedInt32Array()


## exclude_first..exclude_last: sample interval skipped (the playing neighbourhood).
func find_best(database: MotionDatabase, query: PackedFloat32Array, exclude_first: int = -1, exclude_last: int = -1) -> Dictionary:
	if not _prepare(database, query):
		return {}
	var feature_count := database.feature_count
	var normalized_query := _normalize(query)
	var best_sample := -1
	var best_total := INF
	var candidate_count := 0
	for sample_index in range(database.get_sample_count()):
		if database.samples_to_range_end[sample_index] < end_margin_samples:
			continue
		if sample_index >= exclude_first and sample_index <= exclude_last:
			continue
		candidate_count += 1
		var start := sample_index * feature_count
		var total := 0.0
		for feature_index in range(feature_count):
			var delta := normalized_query[feature_index] - _normalized[start + feature_index]
			total += delta * delta
			if total >= best_total:
				break
		if total < best_total:
			best_total = total
			best_sample = sample_index
	if best_sample < 0:
		return {}
	var result := score_sample(database, best_sample, query)
	result["candidate_count"] = candidate_count
	result["search_scope"] = "all_samples_except_range_tails"
	return result


func score_sample(database: MotionDatabase, sample_index: int, query: PackedFloat32Array) -> Dictionary:
	if not _prepare(database, query) or sample_index < 0 or sample_index >= database.get_sample_count():
		return {}
	var normalized_query := _normalize(query)
	var start := sample_index * database.feature_count
	var costs := PackedFloat32Array()
	costs.resize(CATEGORIES.size())
	for feature_index in range(database.feature_count):
		var delta := normalized_query[feature_index] - _normalized[start + feature_index]
		costs[_category_of_feature[feature_index]] += delta * delta
	var total := 0.0
	for cost in costs:
		total += cost
	return {
		"sample_index": sample_index,
		"clip": database.get_sample_clip_name(sample_index),
		"role": database.get_sample_role(sample_index),
		"time": database.get_sample_time(sample_index),
		"velocity_cost": costs[0],
		"pose_cost": costs[1],
		"trajectory_cost": costs[2],
		"facing_cost": costs[3],
		"total_cost": total,
	}


func get_group_report() -> Array:
	var result: Array = []
	for group in GROUPS:
		result.append({"name": group["name"], "weight": group["weight"], "scale": _scales[int(group["first"])] if not _scales.is_empty() else 0.0})
	return result


func _prepare(database: MotionDatabase, query: PackedFloat32Array) -> bool:
	if database == null or not database.is_consistent() or query.size() != database.feature_count:
		push_error("MotionMatcher: invalid database or query size.")
		return false
	if _database_id == database.get_instance_id() and _normalized.size() == database.features.size():
		return true
	_database_id = database.get_instance_id()
	_means = database.feature_means.duplicate()
	_scales.resize(database.feature_count)
	_category_of_feature.resize(database.feature_count)
	var quantity_std: Dictionary = {}
	var quantity_count: Dictionary = {}
	for group in GROUPS:
		for feature_index in range(int(group["first"]), int(group["first"]) + int(group["count"])):
			quantity_std[group["quantity"]] = float(quantity_std.get(group["quantity"], 0.0)) + database.feature_stddevs[feature_index]
			quantity_count[group["quantity"]] = int(quantity_count.get(group["quantity"], 0)) + 1
	for group in GROUPS:
		var mean_std := maxf(float(quantity_std[group["quantity"]]) / float(quantity_count[group["quantity"]]), 0.0001)
		for feature_index in range(int(group["first"]), int(group["first"]) + int(group["count"])):
			_scales[feature_index] = sqrt(float(group["weight"])) / mean_std
			_category_of_feature[feature_index] = CATEGORIES.find(group["category"])
	_normalized.resize(database.features.size())
	for sample_index in range(database.get_sample_count()):
		var start := sample_index * database.feature_count
		for feature_index in range(database.feature_count):
			_normalized[start + feature_index] = (database.features[start + feature_index] - database.feature_means[feature_index]) * _scales[feature_index]
	return true


func _normalize(query: PackedFloat32Array) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(query.size())
	for feature_index in range(query.size()):
		result[feature_index] = (query[feature_index] - _means[feature_index]) * _scales[feature_index]
	return result
