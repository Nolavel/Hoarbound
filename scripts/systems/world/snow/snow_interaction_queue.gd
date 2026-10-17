class_name SnowInteractionQueue
extends RefCounted
## Ordered, render-independent snow interactions waiting for a simulation pass.
## The queue owns accepted events; consumers may peek a bounded batch and only
## consume it after the deformation pass has actually run.

var _events: Array[Dictionary] = []
var _next_sequence: int = 0


func push_foot_plant(
	side: int, position: Vector3, normal: Vector3, forward: Vector3, speed_mps: float
) -> Dictionary:
	if side < 0 or side >= 2:
		return {}
	var up: Vector3 = normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
	var toe: Vector3 = forward - up * forward.dot(up)
	if toe.length_squared() < 0.0001:
		toe = Vector3.FORWARD - up * Vector3.FORWARD.dot(up)
	toe = toe.normalized()
	var event := {
		"kind": &"foot_plant",
		"sequence": _next_sequence,
		"side": side,
		"position": position,
		"normal": up,
		"forward": toe,
		"speed": speed_mps,
	}
	_next_sequence += 1
	_events.append(event)
	return event.duplicate(true)


func is_empty() -> bool:
	return _events.is_empty()


func size() -> int:
	return _events.size()


func peek_batch(limit: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var count: int = mini(maxi(limit, 0), _events.size())
	for i: int in range(count):
		out.append(_events[i])
	return out


func consume(count: int) -> void:
	var consumed: int = mini(maxi(count, 0), _events.size())
	for _i: int in range(consumed):
		_events.pop_front()


func clear() -> void:
	_events.clear()
