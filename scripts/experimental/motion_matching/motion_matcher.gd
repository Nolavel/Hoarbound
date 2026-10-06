class_name MotionMatcher
extends RefCounted

## Brute-force real-frame matcher for issue #202.
## By default every sample in the database competes on numeric feature cost.
## Roles remain metadata only; callers may explicitly provide a coarse domain
## (for example locomotion vs jump) but directions/start/stop/pivot are never
## inferred from the query here.

@export var velocity_weight: float = 0.75
@export var pose_weight: float = 0.75
@export var trajectory_weight: float = 3.0
@export var facing_weight: float = 1.25


func find_best(database: MotionDatabase, query: PackedFloat32Array, allowed_roles: PackedStringArray = PackedStringArray()) -> Dictionary:
	if not _validate(database, query):
		return {}

	var best_sample := -1
	var best_total := INF
	var best_costs: Dictionary = {}
	var candidate_count := 0
	for sample_index in range(database.get_sample_count()):
		if not allowed_roles.is_empty() and not allowed_roles.has(database.get_sample_role(sample_index)):
			continue
		candidate_count += 1
		var costs := _sample_cost(database, sample_index, query)
		var total := float(costs["total"])
		if total < best_total:
			best_total = total
			best_sample = sample_index
			best_costs = costs
	if best_sample < 0:
		return {}
	return {
		"sample_index": best_sample,
		"clip": database.get_sample_clip_name(best_sample),
		"role": database.get_sample_role(best_sample),
		"time": database.get_sample_time(best_sample),
		"velocity_cost": best_costs["velocity"],
		"pose_cost": best_costs["pose"],
		"trajectory_cost": best_costs["trajectory"],
		"facing_cost": best_costs["facing"],
		"total_cost": best_total,
		"candidate_count": candidate_count,
		"search_scope": "explicit_domain" if not allowed_roles.is_empty() else "all_samples",
	}


func score_sample(database: MotionDatabase, sample_index: int, query: PackedFloat32Array) -> Dictionary:
	if not _validate(database, query) or sample_index < 0 or sample_index >= database.get_sample_count():
		return {}
	return _sample_cost(database, sample_index, query)


func _validate(database: MotionDatabase, query: PackedFloat32Array) -> bool:
	if database == null or not database.is_consistent():
		push_error("MotionMatcher: database is invalid.")
		return false
	if query.size() != database.feature_count:
		push_error("MotionMatcher: query has %d features, expected %d." % [query.size(), database.feature_count])
		return false
	if database.feature_stddevs.size() != database.feature_count:
		push_error("MotionMatcher: database statistics are missing.")
		return false
	return true


func _sample_cost(database: MotionDatabase, sample_index: int, query: PackedFloat32Array) -> Dictionary:
	var velocity_cost := 0.0
	var pose_cost := 0.0
	var trajectory_cost := 0.0
	var facing_cost := 0.0
	var start := sample_index * database.feature_count
	for feature_index in range(database.feature_count):
		var sigma := maxf(absf(database.feature_stddevs[feature_index]), 0.001)
		var delta := (query[feature_index] - database.features[start + feature_index]) / sigma
		var squared := delta * delta
		if feature_index < 3:
			velocity_cost += squared
		elif feature_index < 21:
			pose_cost += squared
		elif feature_index < 27:
			trajectory_cost += squared
		else:
			facing_cost += squared
	velocity_cost /= 3.0
	pose_cost /= 18.0
	trajectory_cost /= 6.0
	facing_cost /= 6.0
	return {
		"velocity": velocity_cost,
		"pose": pose_cost,
		"trajectory": trajectory_cost,
		"facing": facing_cost,
		"total": velocity_cost * velocity_weight + pose_cost * pose_weight + trajectory_cost * trajectory_weight + facing_cost * facing_weight,
	}
