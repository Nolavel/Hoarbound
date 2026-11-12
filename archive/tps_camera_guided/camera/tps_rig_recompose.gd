class_name TpsRigRecompose
extends TpsRigBehaviour

## Cramped closer than recompose_distance to the eyes, the shoulder gives way to the centre
## line if that gives the boom more room.

## Share of the shoulder given up for the centre line while the boom is cramped.
var _recompose: float = 0.0
## Recompose goal the shoulder is easing to; replaced only past recompose_hysteresis.
var _recompose_goal: float = 0.0


func reset() -> void:
	_recompose = 0.0


func get_recompose() -> float:
	return _recompose


## Scales frame.side by the share of the shoulder kept. Same-frame casts, one damp.
func apply(frame: TpsRigFrame) -> void:
	frame.side *= 1.0 - _update(frame.delta, frame.safe, frame.pivot, frame.right * frame.side, frame.back, frame.want)


func _update(delta: float, safe: Vector3, pivot: Vector3, offset: Vector3, back: Vector3, want: float) -> float:
	var goal: float = 0.0
	var centre_worse: bool = false
	if rig.get_last_eye_distance() < rig.recompose_distance + 0.3 and offset.length() > 0.05:
		var eye: Vector3 = rig.get_eye_position()
		var near: float = rig.free_eye_distance(safe, pivot + offset, back, want, eye)
		var centre: float = rig.free_eye_distance(safe, pivot, back, want, eye)
		if near < rig.recompose_distance and centre > near + 0.05:
			goal = clampf(inverse_lerp(rig.recompose_distance, rig.recompose_full_distance, near), 0.0, 1.0)
		centre_worse = centre < near - 0.02  # back to a wall: the centre line would bring the camera closer
	if not rig.is_placed() or absf(goal - _recompose_goal) >= rig.recompose_hysteresis or goal == 0.0 or goal == 1.0:
		_recompose_goal = goal
	var rate: float = rig.recompose_in_rate if _recompose_goal > _recompose or centre_worse else rig.recompose_out_rate
	_recompose = _recompose_goal if not rig.is_placed() else lerpf(_recompose, _recompose_goal, TpsCamera.damp(rate, delta))
	return _recompose
