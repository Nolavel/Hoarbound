class_name TpsRigFollow
extends TpsRigBehaviour

## Follow and prediction: the orbit centre trails Henry's feet plus a lead along his motion,
## and the boom pulls back while he sprints.

var _pivot_smooth: Vector3 = Vector3.ZERO
var _lead: Vector3 = Vector3.ZERO
var _pullback: float = 0.0


func reset() -> void:
	_lead = Vector3.ZERO
	_pullback = 0.0


## Extra boom while sprinting, metres.
func get_pullback() -> float:
	return _pullback


## Sets frame.pivot to the followed feet plus the lead; heights are added by the camera.
func apply(frame: TpsRigFrame, speed_ratio: float) -> void:
	_pullback = lerpf(_pullback, speed_ratio * rig.sprint_pullback, TpsCamera.damp(rig.pullback_smoothing, frame.delta))
	var planar := Vector3(rig.player.velocity.x, 0.0, rig.player.velocity.z)
	var move_dir: Vector3 = planar.normalized() if planar.length() > 0.05 else Vector3.ZERO
	_lead = _lead.lerp(move_dir * speed_ratio * rig.lead_distance, TpsCamera.damp(rig.lead_smoothing, frame.delta))
	## Framing heights ride on the followed feet, so each is smoothed once.
	frame.pivot = _follow_pivot(frame.delta, rig.get_feet_position() + _lead)


## The orbit centre trails Henry: lag across the ground, softer lag in height.
func _follow_pivot(delta: float, pivot: Vector3) -> Vector3:
	if not rig.is_placed():
		_pivot_smooth = pivot
		return pivot
	var flat: Vector2 = Vector2(_pivot_smooth.x, _pivot_smooth.z).lerp(Vector2(pivot.x, pivot.z), TpsCamera.damp(rig.follow_speed, delta))
	var height: float = lerpf(_pivot_smooth.y, pivot.y, TpsCamera.damp(rig.follow_speed_vertical, delta))
	_pivot_smooth = Vector3(flat.x, height, flat.y)
	return _pivot_smooth
