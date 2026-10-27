class_name TpsRigShotChoice
extends TpsRigBehaviour

## Shot candidates in tight space (#240 stage 4, ClearShot-like, position only): how far the
## shoulder lift may go. Each cap is scored on a stateless prediction of the camera it gives;
## the best one is eased to, with hysteresis. Over-the-shoulder where there is room ahead,
## the lift only where the camera would otherwise press into Henry. The view stays the player's.

const CAPS: Array[float] = [0.0, 0.35, 0.7, 1.0]
## A new cap must score this much better than the held one to take over.
const HYSTERESIS: float = 0.25

var _choice: int = CAPS.size() - 1
var _cap: float = 1.0
var _costs: PackedFloat32Array = PackedFloat32Array()


func reset() -> void:
	_choice = CAPS.size() - 1
	_cap = 1.0


## Eased lift cap, 0..1.
func get_cap() -> float:
	return _cap


## Last scores per cap, for traces.
func get_costs() -> PackedFloat32Array:
	return _costs


## Picks and eases the cap for this frame; `room_lift` is the lift the room alone asks for.
func update(frame: TpsRigFrame, room_lift: float) -> float:
	if room_lift <= 0.001:
		_costs = PackedFloat32Array()
		_cap = lerpf(_cap, 1.0, TpsCamera.damp(rig.shoulder_lift_out_rate, frame.delta)) if rig.is_placed() else 1.0
		return _cap
	_costs.resize(CAPS.size())
	var best: int = _choice
	for i: int in range(CAPS.size()):
		_costs[i] = _cost(frame, minf(room_lift, CAPS[i]))
		if _costs[i] < _costs[best]:
			best = i
	if not rig.is_placed() or _costs[best] < _costs[_choice] - HYSTERESIS:
		_choice = best
	var goal: float = CAPS[_choice]
	var rate: float = rig.shoulder_lift_in_rate if goal > _cap else rig.shoulder_lift_out_rate
	_cap = goal if not rig.is_placed() else lerpf(_cap, goal, TpsCamera.damp(rate, frame.delta))
	return _cap


## Cost of a lift share: pressing into Henry's eyes (the fade's ground) weighs most, then his
## eyes low in the frame, then the lift itself, so a level shoulder wins when it frames as well.
func _cost(frame: TpsRigFrame, lift: float) -> float:
	var predicted: Dictionary = rig.predict_lift(frame, lift)
	var distance: float = predicted["eye_distance"]
	var eye_y: float = predicted["eye_screen_y"]
	var close: float = maxf(0.0, rig.guard_soft_distance - distance) / maxf(rig.guard_soft_distance - rig.guard_eye_distance, 0.01)
	var low: float = maxf(0.0, eye_y - 0.75) / 0.25
	return 4.0 * close + 2.0 * low + 0.5 * lift
