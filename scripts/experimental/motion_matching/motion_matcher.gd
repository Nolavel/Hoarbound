class_name MotionMatcher
extends RefCounted

## Brute-force frame matcher for issue #202.
## Search is linear by design. Semantic domains are inferred from the query so
## clean start/stop/pivot samples cannot steal a steady locomotion request.

@export var velocity_weight: float = 0.75
@export var pose_weight: float = 0.75
@export var trajectory_weight: float = 3.0
@export var facing_weight: float = 1.25

const WALK_ROLES := ["walk_f", "walk_fr", "walk_r", "walk_br", "walk_b", "walk_bl", "walk_l", "walk_fl"]


func find_best(database: MotionDatabase, query: PackedFloat32Array, allowed_roles: PackedStringArray = PackedStringArray()) -> Dictionary:
	if not _validate(database, query):
		return {}
	var roles := allowed_roles
	if roles.is_empty():
		roles = _infer_roles(database, query)

	var best_sample := -1
	var best_total := INF
	var best_costs: Dictionary = {}
	for sample_index in range(database.get_sample_count()):
		if not roles.is_empty() and not roles.has(database.get_sample_role(sample_index)):
			continue
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
		"velocity_cost": best_costs["velocity"], "pose_cost": best_costs["pose"],
		"trajectory_cost": best_costs["trajectory"], "facing_cost": best_costs["facing"],
		"total_cost": best_total, "allowed_roles": Array(roles),
	}


func score_sample(database: MotionDatabase, sample_index: int, query: PackedFloat32Array) -> Dictionary:
	if not _validate(database, query) or sample_index < 0 or sample_index >= database.get_sample_count():
		return {}
	return _sample_cost(database, sample_index, query)


func _infer_roles(database: MotionDatabase, query: PackedFloat32Array) -> PackedStringArray:
	if query.size() < 29:
		return PackedStringArray()
	var current_velocity := Vector2(query[0], query[1])
	var desired_velocity := Vector2(query[21], query[22]) / 0.2
	var desired_facing := Vector2(query[27], query[28])
	var roles := PackedStringArray()
	if desired_velocity.length() < 0.12:
		var turn := Vector2(0.0, 1.0).angle_to(desired_facing.normalized() if desired_facing.length_squared() > 0.0001 else Vector2(0.0, 1.0))
		if absf(turn) > deg_to_rad(50.0):
			var side := "r" if turn > 0.0 else "l"
			var pivot := ("pivot_180_" if absf(turn) > deg_to_rad(135.0) else "pivot_90_") + side
			if _has_role(database, pivot):
				roles.append(pivot)
				return roles
		if current_velocity.length() > 0.28:
			var stop_role := _action_role("stop_", current_velocity)
			if _has_role(database, stop_role):
				roles.append(stop_role)
		if _has_role(database, "idle_neutral"):
			roles.append("idle_neutral")
		return roles

	var walk_role := _walk_role(desired_velocity)
	if current_velocity.length() < 0.24:
		var start_role := _action_role("start_", desired_velocity)
		if _has_role(database, start_role):
			roles.append(start_role)
	if _has_role(database, walk_role):
		roles.append(walk_role)
		return roles
	# Missing authored direction: degrade only within locomotion, never into a
	# stop/pivot/start clip just because its pose cost is attractive.
	for fallback in WALK_ROLES:
		if _has_role(database, fallback):
			roles.append(fallback)
	return roles


func _walk_role(local_velocity: Vector2) -> String:
	var angle := atan2(local_velocity.x, local_velocity.y)
	var sector := posmod(int(round(angle / (PI * 0.25))), 8)
	match sector:
		0: return "walk_f"
		1: return "walk_fr"
		2: return "walk_r"
		3: return "walk_br"
		4: return "walk_b"
		5: return "walk_bl"
		6: return "walk_l"
		7: return "walk_fl"
	return "walk_f"


func _action_role(prefix: String, velocity: Vector2) -> String:
	var walk := _walk_role(velocity)
	match walk:
		"walk_f": return prefix + "f"
		"walk_b": return prefix + "b"
		"walk_l": return prefix + "l"
		"walk_r": return prefix + "r"
	return ""


func _has_role(database: MotionDatabase, role: String) -> bool:
	return not role.is_empty() and database.clip_roles.has(role)


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
		if feature_index < 3: velocity_cost += squared
		elif feature_index < 21: pose_cost += squared
		elif feature_index < 27: trajectory_cost += squared
		else: facing_cost += squared
	velocity_cost /= 3.0
	pose_cost /= 18.0
	trajectory_cost /= 6.0
	facing_cost /= 6.0
	return {
		"velocity": velocity_cost, "pose": pose_cost, "trajectory": trajectory_cost, "facing": facing_cost,
		"total": velocity_cost * velocity_weight + pose_cost * pose_weight + trajectory_cost * trajectory_weight + facing_cost * facing_weight,
	}
