class_name PanCookingModel
extends RefCounted

## Contents of ONE stove plate, independent of screen time and scene visuals.
## Fractions are hours of effective heat emitted by HeatSource; each egg has its own history.
const MAX_EGGS: int = 3
const READY_HOURS: float = 0.08
const WELL_HOURS: float = 0.115
const BURNT_HOURS: float = 0.16
const POSITIONS: Array[Vector2] = [
	Vector2(-0.048, -0.037), Vector2(0.049, -0.033), Vector2(0.001, 0.051)
]

var eggs: Array[Dictionary] = []
var oil: bool = false
var salt: bool = false
var pepper: bool = false

func add_egg() -> bool:
	if eggs.size() >= MAX_EGGS:
		return false
	var spot: Vector2 = POSITIONS[eggs.size()]
	eggs.append({"heat_h": 0.0, "intro": 0.0, "x": spot.x, "z": spot.y})
	return true

func advance_heat(hours: float) -> void:
	for i: int in range(eggs.size()):
		var entry: Dictionary = eggs[i]
		entry["heat_h"] = minf(BURNT_HOURS + 0.08, float(entry.get("heat_h", 0.0)) + maxf(0.0, hours))
		eggs[i] = entry

func advance_intro(delta: float) -> bool:
	var changed: bool = false
	for i: int in range(eggs.size()):
		var entry: Dictionary = eggs[i]
		if float(entry.get("intro", 0.0)) < 3.3:
			entry["intro"] = minf(3.3, float(entry.get("intro", 0.0)) + maxf(delta, 0.0))
			eggs[i] = entry
			changed = true
	return changed

func get_quality(index: int) -> StringName:
	if index < 0 or index >= eggs.size():
		return &"none"
	var heat: float = float(eggs[index].get("heat_h", 0.0))
	if heat >= BURNT_HOURS + (0.025 if oil else 0.0):
		return &"burnt"
	if heat >= WELL_HOURS:
		return &"well"
	if heat >= READY_HOURS:
		return &"ready"
	return &"cooking"

func first_ready_index() -> int:
	for i: int in range(eggs.size()):
		if get_quality(i) != &"cooking":
			return i
	return -1

func clear() -> void:
	eggs.clear()
	oil = false
	salt = false
	pepper = false

func to_save() -> Dictionary:
	return {"eggs": eggs.duplicate(true), "oil": oil, "salt": salt, "pepper": pepper}

func from_save(data: Dictionary) -> void:
	clear()
	oil = bool(data.get("oil", false))
	salt = bool(data.get("salt", false))
	pepper = bool(data.get("pepper", false))
	var raw: Array = data.get("eggs", [])
	for item: Variant in raw:
		if eggs.size() >= MAX_EGGS or not item is Dictionary:
			break
		var spot: Vector2 = POSITIONS[eggs.size()]
		eggs.append({
			"heat_h": clampf(float(item.get("heat_h", 0.0)), 0.0, BURNT_HOURS + 0.08),
			"intro": clampf(float(item.get("intro", 3.3)), 0.0, 3.3),
			"x": clampf(float(item.get("x", spot.x)), -0.065, 0.065),
			"z": clampf(float(item.get("z", spot.y)), -0.065, 0.065)
		})
