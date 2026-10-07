class_name MotionDatasetCurator
extends RefCounted

## Picks real ranges from the normalized root track; labels are provenance and
## debug only, never matcher input. Source capture glitches are excluded.

const SPEED_IDLE := 0.15
const SPEED_TURN := 0.35
const SPEED_WALK := 0.45
## Henry's game walk is 1.5 m/s; forward walking from here up is its own tier.
const SPEED_BRISK := 1.2
const SPEED_TOO_FAST := 2.2
const YAW_TURN := 0.4
const YAW_WALK_MAX := 1.2
const TRANSITION_SECONDS := 0.6
const GLITCH_RAD_PER_S := 20.0
const GLITCH_MARGIN_SECONDS := 0.25
## Long windows keep the real transitions between gaits and directions.
const WINDOW_SECONDS := 8.0
const WINDOW_HOP_SECONDS := 2.0
const MIN_WINDOW_SECONDS := 2.0
const TOTAL_BUDGET_SECONDS := 460.0
const MIN_USEFUL_SECONDS := 0.5
const SECTORS := ["walk_f", "walk_fl", "walk_l", "walk_bl", "walk_b", "walk_br", "walk_r", "walk_fr"]
const BUDGET_SECONDS := {
	"idle": 25.0, "turn": 25.0, "start": 15.0, "stop": 15.0, "transition": 40.0,
	"walk_f": 20.0, "walk_b": 20.0, "walk_l": 15.0, "walk_r": 15.0,
	"walk_fl": 12.0, "walk_fr": 12.0, "walk_bl": 12.0, "walk_br": 12.0,
	"walk_f_brisk": 50.0, "turn_brisk": 20.0,
}


func analyze(retargeter: MotionRetargeter, source_id: String) -> Dictionary:
	var rate := retargeter.track_rate_hz
	var count := retargeter.root_positions.size()
	var labels := PackedStringArray()
	labels.resize(count)
	var speeds := PackedFloat32Array()
	speeds.resize(count)
	for index in range(count):
		var previous := maxi(0, index - 1)
		var following := mini(count - 1, index + 1)
		var span := maxf(float(following - previous) / rate, 0.0001)
		var forward := retargeter.root_forwards[index]
		var yaw_inverse := Basis(Vector3.UP, atan2(forward.x, forward.z)).inverse()
		var velocity := yaw_inverse * (retargeter.root_positions[following] - retargeter.root_positions[previous]) / span
		var yaw_rate := wrapf(atan2(retargeter.root_forwards[following].x, retargeter.root_forwards[following].z) - atan2(retargeter.root_forwards[previous].x, retargeter.root_forwards[previous].z), -PI, PI) / span
		var speed := Vector2(velocity.x, velocity.z).length()
		speeds[index] = speed
		labels[index] = _classify(velocity, speed, yaw_rate)
	_mark_transitions(labels, rate)
	var glitches := _glitch_mask(retargeter)
	var windows := _windows(labels, glitches, rate, retargeter.get_duration(), source_id)
	var histogram := _histogram(labels, 0, count - 1, rate)
	var glitch_count := 0
	for flag in glitches:
		glitch_count += flag
	return {
		"windows": windows,
		"report": {
			"source": source_id,
			"duration": retargeter.get_duration(),
			"label_seconds": histogram,
			"glitch_samples": glitch_count,
			"window_count": windows.size(),
		},
	}


func select(windows: Array[Dictionary]) -> Dictionary:
	var available: Dictionary = {}
	for window in windows:
		for label in (window["label_seconds"] as Dictionary).keys():
			available[label] = float(available.get(label, 0.0)) + float(window["label_seconds"][label])
	var remaining := BUDGET_SECONDS.duplicate()
	var selected: Array[Dictionary] = []
	var total := 0.0
	while total < TOTAL_BUDGET_SECONDS:
		var best_index := -1
		var best_score := MIN_USEFUL_SECONDS
		for index in range(windows.size()):
			var window := windows[index]
			if bool(window.get("taken", false)) or _overlaps(window, selected):
				continue
			var score := 0.0
			for label in (window["label_seconds"] as Dictionary).keys():
				if not remaining.has(label):
					continue
				var useful := minf(float(remaining[label]), float(window["label_seconds"][label]))
				score += useful * clampf(20.0 / maxf(float(available.get(label, 1.0)), 1.0), 1.0, 5.0)
			if score > best_score:
				best_score = score
				best_index = index
		if best_index < 0:
			break
		var chosen := windows[best_index]
		chosen["taken"] = true
		for label in (chosen["label_seconds"] as Dictionary).keys():
			if remaining.has(label):
				remaining[label] = maxf(0.0, float(remaining[label]) - float(chosen["label_seconds"][label]))
		total += float(chosen["end"]) - float(chosen["start"])
		selected.append(chosen)
	var covered: Dictionary = {}
	for window in selected:
		for label in (window["label_seconds"] as Dictionary).keys():
			covered[label] = float(covered.get(label, 0.0)) + float(window["label_seconds"][label])
	var missing: Array[String] = []
	for label in BUDGET_SECONDS.keys():
		if float(covered.get(label, 0.0)) < MIN_USEFUL_SECONDS:
			missing.append(label)
	return {
		"ranges": _merge(selected),
		"covered_seconds": covered,
		"available_seconds": available,
		"missing_labels": missing,
		"total_seconds": total,
	}


func _classify(velocity: Vector3, speed: float, yaw_rate: float) -> String:
	if speed > SPEED_TOO_FAST:
		return "too_fast"
	if speed < SPEED_IDLE and absf(yaw_rate) < YAW_TURN:
		return "idle"
	if speed < SPEED_TURN and absf(yaw_rate) >= YAW_TURN:
		return "turn"
	if speed >= SPEED_WALK and absf(yaw_rate) < YAW_WALK_MAX:
		# Model space: +Z forward, +X left; sectors run counter-clockwise.
		var sector := posmod(int(round(atan2(velocity.x, velocity.z) / (PI * 0.25))), 8)
		return SECTORS[sector] + ("_brisk" if sector == 0 and speed >= SPEED_BRISK else "")
	if speed >= SPEED_BRISK:
		return "turn_brisk"
	return "transition"


func _mark_transitions(labels: PackedStringArray, rate: float) -> void:
	var span := int(round(TRANSITION_SECONDS * rate))
	var original := labels.duplicate()
	for index in range(1, original.size()):
		var was_idle := original[index - 1] == "idle"
		var is_idle := original[index] == "idle"
		if was_idle == is_idle:
			continue
		var event := "start" if was_idle else "stop"
		var first := index if was_idle else maxi(0, index - span)
		var last := mini(original.size() - 1, index + span) if was_idle else index - 1
		for marked in range(first, last + 1):
			if original[marked] != "idle":
				labels[marked] = event


func _glitch_mask(retargeter: MotionRetargeter) -> PackedByteArray:
	var clip := retargeter.clip
	var count := retargeter.root_positions.size()
	var mask := PackedByteArray()
	mask.resize(count)
	var margin := int(ceil(GLITCH_MARGIN_SECONDS * retargeter.track_rate_hz))
	var previous: Array[Quaternion] = []
	for index in range(count):
		var frame := clip.frame_at_time(float(index) / retargeter.track_rate_hz, retargeter.profile.first_motion_frame)
		var current: Array[Quaternion] = []
		for joint in range(clip.get_bone_count()):
			current.append(clip.local_transform(frame, joint).basis.get_rotation_quaternion())
		if not previous.is_empty():
			for joint in range(current.size()):
				if previous[joint].angle_to(current[joint]) * retargeter.track_rate_hz > GLITCH_RAD_PER_S:
					for flagged in range(maxi(0, index - margin), mini(count, index + margin + 1)):
						mask[flagged] = 1
					break
		previous = current
	return mask


func _windows(labels: PackedStringArray, glitches: PackedByteArray, rate: float, duration: float, source_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var count := labels.size()
	var window := int(round(WINDOW_SECONDS * rate))
	var hop := int(round(WINDOW_HOP_SECONDS * rate))
	var minimum := int(round(MIN_WINDOW_SECONDS * rate))
	var start := 0
	while start < count:
		while start < count and (glitches[start] == 1 or labels[start] == "too_fast"):
			start += 1
		var end := start
		while end < count and end - start < window and glitches[end] == 0 and labels[end] != "too_fast":
			end += 1
		if end - start >= minimum:
			result.append({
				"source": source_id,
				"start": float(start) / rate,
				"end": minf(duration, float(end - 1) / rate),
				"label_seconds": _histogram(labels, start, end - 1, rate),
			})
		start = start + hop if end - start >= window else end + 1
	return result


func _histogram(labels: PackedStringArray, first: int, last: int, rate: float) -> Dictionary:
	var result: Dictionary = {}
	for index in range(first, last + 1):
		result[labels[index]] = float(result.get(labels[index], 0.0)) + 1.0 / rate
	return result


func _overlaps(window: Dictionary, selected: Array[Dictionary]) -> bool:
	for other in selected:
		if other["source"] == window["source"] and float(window["start"]) < float(other["end"]) and float(other["start"]) < float(window["end"]):
			return true
	return false


func _merge(selected: Array[Dictionary]) -> Array[Dictionary]:
	var sorted := selected.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["source"] < b["source"] or (a["source"] == b["source"] and float(a["start"]) < float(b["start"]))
	)
	var merged: Array[Dictionary] = []
	for window in sorted:
		if not merged.is_empty():
			var last: Dictionary = merged.back()
			if last["source"] == window["source"] and float(window["start"]) <= float(last["end"]) + 0.05:
				last["end"] = maxf(float(last["end"]), float(window["end"]))
				for label in (window["label_seconds"] as Dictionary).keys():
					last["label_seconds"][label] = float(last["label_seconds"].get(label, 0.0)) + float(window["label_seconds"][label])
				continue
		merged.append({
			"source": window["source"], "start": window["start"], "end": window["end"],
			"label_seconds": (window["label_seconds"] as Dictionary).duplicate(),
		})
	for range_entry in merged:
		var dominant := ""
		var best := -1.0
		for label in (range_entry["label_seconds"] as Dictionary).keys():
			if label != "transition" and float(range_entry["label_seconds"][label]) > best:
				best = float(range_entry["label_seconds"][label])
				dominant = label
		range_entry["role"] = dominant
	return merged
