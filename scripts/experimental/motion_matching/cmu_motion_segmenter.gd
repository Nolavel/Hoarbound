class_name CMUMotionSegmenter
extends RefCounted

## Kinematic curation pass for issue #202.
## Reads only raw BVH root motion, so noisy/mixed parts of long captures never
## enter the expensive UAL retarget bake or runtime search database.

const ANALYSIS_RATE_HZ := 30.0
const KINEMATIC_HALF_WINDOW_SECONDS := 0.10
const IDLE_SPEED_MAX := 0.18
const MOVE_SPEED_MIN := 0.36
const MOVE_YAW_MAX := 1.15
const PIVOT_SPEED_MAX := 0.34
const PIVOT_YAW_MIN := 0.45
const MIN_IDLE_SECONDS := 0.65
const MIN_WALK_SECONDS := 0.45
const MIN_SIDE_DIAGONAL_SECONDS := 0.50
const MIN_PIVOT_SECONDS := 0.28
const WALK_MAX_SECONDS := 1.65
const IDLE_MAX_SECONDS := 1.35
const EVENT_MAX_SECONDS := 0.95
const PIVOT_MAX_SECONDS := 1.75
const START_IDLE_SECONDS := 0.20
const START_MOVE_SECONDS := 0.34
const STOP_MOVE_SECONDS := 0.34
const STOP_IDLE_SECONDS := 0.20

const ROLE_ORDER := [
	"idle_neutral",
	"walk_f", "walk_fr", "walk_r", "walk_br", "walk_b", "walk_bl", "walk_l", "walk_fl",
	"start_f", "start_b", "start_l", "start_r",
	"stop_f", "stop_b", "stop_l", "stop_r",
	"pivot_90_l", "pivot_90_r", "pivot_180_l", "pivot_180_r",
]


func analyze_file(
		source_path: String,
		source_id: String,
		trial: String,
		description: String,
		import_options: Dictionary = {}
	) -> Dictionary:
	var source := CMUBVHSource.new()
	if not source.configure_import(
		float(import_options.get("position_scale", CMUBVHSource.DEFAULT_POSITION_SCALE)),
		bool(import_options.get("detect_rest_frame", false)),
		bool(import_options.get("include_first_frame", false)),
		bool(import_options.get("zero_rotation_rest", false))
	):
		source.free()
		return {"ok": false, "error": "failed to configure BVH source", "source": source_id}
	if not source.load_bvh(source_path):
		var error := source.error_message
		source.free()
		return {"ok": false, "error": error, "source": source_id}
	var metrics := _sample_metrics(source)
	var candidates: Array[Dictionary] = []
	candidates.append_array(_stable_candidates(metrics, source, source_path, source_id, trial, description))
	candidates.append_array(_transition_candidates(metrics, source, source_path, source_id, trial, description))
	for candidate in candidates:
		candidate["import_options"] = import_options.duplicate(true)
	var report := {
		"source": source_id,
		"source_path": source_path,
		"dataset": String(import_options.get("dataset", "CMU")),
		"duration": source.clip_length,
		"analysis_samples": metrics.size(),
		"candidate_count": candidates.size(),
		"source_import": source.get_report(),
	}
	source.free()
	return {"ok": true, "candidates": candidates, "report": report}


func select_canonical(candidates: Array[Dictionary]) -> Dictionary:
	var selected: Array[Dictionary] = []
	var missing: Array[String] = []
	for role in ROLE_ORDER:
		var role_candidates: Array[Dictionary] = []
		for candidate in candidates:
			if String(candidate.get("role", "")) == role:
				role_candidates.append(candidate)
		role_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("score", 0.0)) > float(b.get("score", 0.0))
		)
		if role_candidates.is_empty():
			missing.append(role)
			continue
		var chosen := role_candidates[0].duplicate(true)
		chosen["clip"] = "%s_%s" % [String(chosen["source"]), role]
		selected.append(chosen)
	return {"segments": selected, "missing_roles": missing, "requested_roles": ROLE_ORDER.duplicate()}


func _sample_metrics(source: CMUBVHSource) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var dt := 1.0 / ANALYSIS_RATE_HZ
	var count := maxi(2, int(floor(source.clip_length * ANALYSIS_RATE_HZ)) + 1)
	for index in range(count):
		var time := minf(source.clip_length, float(index) * dt)
		# Root channels contain capture jitter at one-frame derivatives. A 200 ms
		# centered window preserves authored direction changes while preventing a
		# real diagonal gait from flickering between adjacent 45-degree sectors.
		var previous_time := maxf(0.0, time - KINEMATIC_HALF_WINDOW_SECONDS)
		var next_time := minf(source.clip_length, time + KINEMATIC_HALF_WINDOW_SECONDS)
		var duration := maxf(next_time - previous_time, dt)
		var previous_position := source.get_raw_root_position(previous_time)
		var next_position := source.get_raw_root_position(next_time)
		var velocity_world_3d := (next_position - previous_position) / duration
		# CMU's BVH character forward is opposite Godot's -Z basis used by the
		# original parser. Flip only the semantic root-facing channel; bone pose
		# rotations/retarget are untouched.
		var facing_3d := -source.get_raw_root_facing(time)
		var facing := _safe_facing(Vector2(facing_3d.x, facing_3d.z))
		var previous_facing_3d := -source.get_raw_root_facing(previous_time)
		var next_facing_3d := -source.get_raw_root_facing(next_time)
		var previous_facing := _safe_facing(Vector2(previous_facing_3d.x, previous_facing_3d.z))
		var next_facing := _safe_facing(Vector2(next_facing_3d.x, next_facing_3d.z))
		var yaw_rate := previous_facing.angle_to(next_facing) / duration
		var world_velocity := Vector2(velocity_world_3d.x, velocity_world_3d.z)
		var right := Vector2(-facing.y, facing.x)
		var local_velocity := Vector2(world_velocity.dot(right), world_velocity.dot(facing))
		var speed := local_velocity.length()
		result.append({
			"time": time,
			"speed": speed,
			"local_velocity": local_velocity,
			"facing": facing,
			"yaw_rate": yaw_rate,
			"label": _classify_frame(local_velocity, speed, yaw_rate),
		})
	return result


func _classify_frame(local_velocity: Vector2, speed: float, yaw_rate: float) -> String:
	if speed <= IDLE_SPEED_MAX and absf(yaw_rate) < PIVOT_YAW_MIN:
		return "idle_neutral"
	if speed <= PIVOT_SPEED_MAX and absf(yaw_rate) >= PIVOT_YAW_MIN:
		return "pivot_raw"
	if speed >= MOVE_SPEED_MIN and absf(yaw_rate) <= MOVE_YAW_MAX:
		return _walk_role(local_velocity)
	return "transition"


func _stable_candidates(
		metrics: Array[Dictionary],
		source: CMUBVHSource,
		source_path: String,
		source_id: String,
		trial: String,
		description: String
	) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if metrics.is_empty():
		return result
	var run_start := 0
	while run_start < metrics.size():
		var label := String(metrics[run_start]["label"])
		var run_end := run_start
		while run_end + 1 < metrics.size() and String(metrics[run_end + 1]["label"]) == label:
			run_end += 1
		var start_time := float(metrics[run_start]["time"])
		var end_time := float(metrics[run_end]["time"])
		var duration := end_time - start_time
		if label == "idle_neutral" and duration >= MIN_IDLE_SECONDS:
			var window := _trim_window(start_time, end_time, IDLE_MAX_SECONDS)
			result.append(_candidate(label, window.x, window.y, duration, source_path, source_id, trial, description, duration))
		elif label.begins_with("walk_"):
			var minimum := MIN_WALK_SECONDS if label == "walk_f" or label == "walk_b" else MIN_SIDE_DIAGONAL_SECONDS
			if duration >= minimum:
				var window := _trim_window(start_time, end_time, WALK_MAX_SECONDS)
				var stability := _run_stability(metrics, run_start, run_end)
				result.append(_candidate(label, window.x, window.y, duration, source_path, source_id, trial, description, duration + stability))
		elif label == "pivot_raw" and duration >= MIN_PIVOT_SECONDS:
			result.append_array(_pivot_candidates(metrics, run_start, run_end, source, source_path, source_id, trial, description))
		run_start = run_end + 1
	return result


func _transition_candidates(
		metrics: Array[Dictionary],
		source: CMUBVHSource,
		source_path: String,
		source_id: String,
		trial: String,
		description: String
	) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var pre_idle := maxi(2, int(round(START_IDLE_SECONDS * ANALYSIS_RATE_HZ)))
	var post_move := maxi(3, int(round(START_MOVE_SECONDS * ANALYSIS_RATE_HZ)))
	var pre_move := maxi(3, int(round(STOP_MOVE_SECONDS * ANALYSIS_RATE_HZ)))
	var post_idle := maxi(2, int(round(STOP_IDLE_SECONDS * ANALYSIS_RATE_HZ)))
	var last_event_time: Dictionary = {}
	for index in range(maxi(pre_idle, pre_move), metrics.size() - maxi(post_move, post_idle)):
		var time := float(metrics[index]["time"])
		var before_idle := _average_speed(metrics, index - pre_idle, index - 1) <= IDLE_SPEED_MAX
		var after_move := _average_speed(metrics, index + 1, index + post_move) >= MOVE_SPEED_MIN
		if before_idle and after_move:
			var local := _average_local_velocity(metrics, index + 1, index + post_move)
			var cardinal := _cardinal_suffix(_walk_role(local))
			if not cardinal.is_empty():
				var role := "start_" + cardinal
				if time - float(last_event_time.get(role, -10.0)) > 1.0:
					var start := maxf(0.0, time - 0.20)
					var end := minf(source.clip_length, start + EVENT_MAX_SECONDS)
					result.append(_candidate(role, start, end, end - start, source_path, source_id, trial, description, 3.0 + local.length()))
					last_event_time[role] = time
		var before_move := _average_speed(metrics, index - pre_move, index - 1) >= MOVE_SPEED_MIN
		var after_idle := _average_speed(metrics, index + 1, index + post_idle) <= IDLE_SPEED_MAX
		if before_move and after_idle:
			var local_before := _average_local_velocity(metrics, index - pre_move, index - 1)
			var cardinal_before := _cardinal_suffix(_walk_role(local_before))
			if not cardinal_before.is_empty():
				var stop_role := "stop_" + cardinal_before
				if time - float(last_event_time.get(stop_role, -10.0)) > 1.0:
					var stop_start := maxf(0.0, time - 0.55)
					var stop_end := minf(source.clip_length, stop_start + EVENT_MAX_SECONDS)
					result.append(_candidate(stop_role, stop_start, stop_end, stop_end - stop_start, source_path, source_id, trial, description, 3.0 + local_before.length()))
					last_event_time[stop_role] = time
	return result


func _pivot_candidates(
		metrics: Array[Dictionary], start_index: int, end_index: int,
		source: CMUBVHSource, source_path: String, source_id: String,
		trial: String, description: String
	) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var dt := 1.0 / ANALYSIS_RATE_HZ
	var accumulated := 0.0
	var emitted_90 := false
	var emitted_180 := false
	for index in range(start_index, end_index + 1):
		accumulated += float(metrics[index]["yaw_rate"]) * dt
		var absolute_turn := absf(accumulated)
		var side := "r" if accumulated > 0.0 else "l"
		if not emitted_90 and absolute_turn >= deg_to_rad(78.0):
			var start_time := float(metrics[start_index]["time"])
			var end_time := minf(source.clip_length, float(metrics[index]["time"]))
			if end_time - start_time <= PIVOT_MAX_SECONDS:
				result.append(_candidate("pivot_90_" + side, start_time, end_time, end_time - start_time, source_path, source_id, trial, description, 4.0 - absf(absolute_turn - PI * 0.5)))
			emitted_90 = true
		if not emitted_180 and absolute_turn >= deg_to_rad(158.0):
			var start_180 := float(metrics[start_index]["time"])
			var end_180 := minf(source.clip_length, float(metrics[index]["time"]))
			if end_180 - start_180 <= PIVOT_MAX_SECONDS:
				result.append(_candidate("pivot_180_" + side, start_180, end_180, end_180 - start_180, source_path, source_id, trial, description, 4.0 - absf(absolute_turn - PI)))
			emitted_180 = true
		if emitted_90 and emitted_180:
			break
	return result


func _candidate(role: String, start_time: float, end_time: float, duration: float, source_path: String, source_id: String, trial: String, description: String, score: float) -> Dictionary:
	return {
		"role": role, "start": start_time, "end": end_time, "duration": duration,
		"source_path": source_path, "source": source_id, "trial": trial,
		"description": description, "score": score,
	}


func _trim_window(start_time: float, end_time: float, max_duration: float) -> Vector2:
	var duration := end_time - start_time
	if duration <= max_duration:
		return Vector2(start_time, end_time)
	var center := (start_time + end_time) * 0.5
	return Vector2(center - max_duration * 0.5, center + max_duration * 0.5)


func _run_stability(metrics: Array[Dictionary], start_index: int, end_index: int) -> float:
	var yaw_sum := 0.0
	var speed_sum := 0.0
	var count := maxi(1, end_index - start_index + 1)
	for index in range(start_index, end_index + 1):
		yaw_sum += absf(float(metrics[index]["yaw_rate"]))
		speed_sum += float(metrics[index]["speed"])
	return speed_sum / float(count) - yaw_sum / float(count) * 0.25


func _average_speed(metrics: Array[Dictionary], start_index: int, end_index: int) -> float:
	var total := 0.0
	var count := 0
	for index in range(maxi(0, start_index), mini(metrics.size() - 1, end_index) + 1):
		total += float(metrics[index]["speed"])
		count += 1
	return total / float(maxi(1, count))


func _average_local_velocity(metrics: Array[Dictionary], start_index: int, end_index: int) -> Vector2:
	var total := Vector2.ZERO
	var count := 0
	for index in range(maxi(0, start_index), mini(metrics.size() - 1, end_index) + 1):
		total += metrics[index]["local_velocity"] as Vector2
		count += 1
	return total / float(maxi(1, count))


func _walk_role(local_velocity: Vector2) -> String:
	if local_velocity.length_squared() <= 0.000001:
		return "transition"
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
	return "transition"


func _cardinal_suffix(walk_role: String) -> String:
	match walk_role:
		"walk_f": return "f"
		"walk_b": return "b"
		"walk_l": return "l"
		"walk_r": return "r"
	return ""


func _safe_facing(facing: Vector2) -> Vector2:
	return facing.normalized() if facing.length_squared() > 0.000001 else Vector2(0.0, -1.0)
