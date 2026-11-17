class_name TpsRigShotChoice
extends TpsRigBehaviour

## Shot candidates in tight space (#240 stage 4, ClearShot-like, position only): how far the
## shoulder lift may go and how far the camera body may swing round Henry off the view. Each
## pair is scored on a stateless prediction of the frame it gives; the best is eased to, with
## hysteresis. The view stays the player's: a swing only moves where the camera stands.

const CAPS: Array[float] = [0.0, 0.35, 0.7, 1.0]
const SWINGS_DEG: Array[float] = [0.0, -20.0, 20.0, -40.0, 40.0]
## A new shot must score this much better than the held one to take over.
const HYSTERESIS: float = 0.25
## Eyes kept this far inside the left and right edges, share of the screen width.
const SIDE_MARGIN: float = 0.1

var _choice: Vector2i = Vector2i(CAPS.size() - 1, 0)
var _cap: float = 1.0
var _yaw_offset: float = 0.0
var _best_cost: float = 0.0
var _predicted_eye: Vector2 = Vector2.ZERO


func reset() -> void:
	_choice = Vector2i(CAPS.size() - 1, 0)
	_cap = 1.0
	_yaw_offset = 0.0


## Eased lift cap, 0..1.
func get_cap() -> float:
	return _cap


## Eased swing of the camera body off the orbit, radians.
func get_yaw_offset() -> float:
	return _yaw_offset


func get_best_cost() -> float:
	return _best_cost


## Where the held shot predicts Henry's eyes on screen, for the traces.
func get_predicted_eye() -> Vector2:
	return _predicted_eye


## Picks and eases the shot for this frame; `room_lift` is the lift the room alone asks for.
## Returns the lift cap; the swing is read with get_yaw_offset().
func update(frame: TpsRigFrame, room_lift: float) -> float:
	var out_rate: float = TpsCamera.damp(rig.shoulder_lift_out_rate, frame.delta)
	if room_lift <= 0.001 or rig.get_passage_blend() > 0.5:
		_choice = Vector2i(CAPS.size() - 1, 0)
		_cap = lerpf(_cap, 1.0, out_rate) if rig.is_placed() else 1.0
		_yaw_offset = lerpf(_yaw_offset, 0.0, out_rate) if rig.is_placed() else 0.0
		return _cap
	var held: float = _cost(frame, room_lift, _choice)
	var best: Vector2i = _choice
	var best_cost: float = held
	for c: int in range(CAPS.size()):
		for w: int in range(SWINGS_DEG.size()):
			var candidate := Vector2i(c, w)
			if candidate == _choice:
				continue
			var cost: float = _cost(frame, room_lift, candidate)
			if cost < best_cost:
				best_cost = cost
				best = candidate
	if not rig.is_placed() or best_cost < held - HYSTERESIS:
		_choice = best
		held = best_cost
	_predicted_eye = rig.predict_shot(frame, minf(room_lift, CAPS[_choice.x]), deg_to_rad(SWINGS_DEG[_choice.y]))["eye_screen"]
	_best_cost = held
	var cap: float = CAPS[_choice.x]
	var swing: float = deg_to_rad(SWINGS_DEG[_choice.y])
	var in_rate: float = TpsCamera.damp(rig.shoulder_lift_in_rate, frame.delta)
	_cap = cap if not rig.is_placed() else lerpf(_cap, cap, in_rate if cap > _cap else out_rate)
	_yaw_offset = swing if not rig.is_placed() else lerpf(_yaw_offset, swing, in_rate)
	return _cap


## Cost of a shot: pressing into Henry's eyes (the fade's ground) weighs most, then his eyes
## off the sides or low in the frame, then the lift and the swing themselves, so the plain
## shoulder wins whenever it frames as well.
func _cost(frame: TpsRigFrame, room_lift: float, choice: Vector2i) -> float:
	var lift: float = minf(room_lift, CAPS[choice.x])
	var swing: float = SWINGS_DEG[choice.y]
	var predicted: Dictionary = rig.predict_shot(frame, lift, deg_to_rad(swing))
	var distance: float = predicted["eye_distance"]
	var eye: Vector2 = predicted["eye_screen"]
	var close: float = maxf(0.0, rig.guard_soft_distance - distance) / maxf(rig.guard_soft_distance - rig.guard_eye_distance, 0.01)
	var low: float = maxf(0.0, eye.y - 0.75) / 0.25
	var sides: float = maxf(0.0, maxf(SIDE_MARGIN - eye.x, eye.x - (1.0 - SIDE_MARGIN))) / SIDE_MARGIN
	return 4.0 * close + 2.0 * low + 2.0 * sides + 0.5 * lift + 0.25 * absf(swing) / 20.0
