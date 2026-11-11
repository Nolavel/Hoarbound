class_name TpsShoulderState
extends RefCounted

## Which shoulder the camera sits over, with a smoothstep manual swap between them.
## Interaction framing may temporarily override that physical shoulder offset; the
## base/manual side remains untouched and resumes when the target is gone.

enum Side { LEFT, RIGHT, TRANSITION }

var right_offset: float = 0.85
var left_offset: float = -0.85
var transition_duration: float = 0.18
var state: int = Side.RIGHT

## Interaction framing is deliberately slower than mouse look but quicker than
## ordinary follow lag. It changes the real shoulder point, so TpsCamera's sweeps
## still own walls, doorways and final collision.
var interaction_blend_rate: float = 8.0
var interaction_offset_rate: float = 10.0

var _pending: int = Side.RIGHT
var _from: int = Side.RIGHT
var _time: float = 0.0
var _interaction_goal: float = 0.0
var _interaction_offset: float = 0.0
var _interaction_weight_goal: float = 0.0
var _interaction_weight: float = 0.0


func toggle() -> void:
	if state == Side.TRANSITION:
		return
	_start(Side.LEFT if state == Side.RIGHT else Side.RIGHT)


func is_right() -> bool:
	if state == Side.TRANSITION:
		return _pending == Side.RIGHT
	return state == Side.RIGHT


## Requests a temporary physical shoulder position. Strength is 0..1 and may
## cross the centre line only when the interaction-composition owner asks for it.
func set_interaction_override(goal_offset: float, strength: float) -> void:
	_interaction_goal = goal_offset
	_interaction_weight_goal = clampf(strength, 0.0, 1.0)


func clear_interaction_override() -> void:
	_interaction_weight_goal = 0.0


func get_interaction_weight() -> float:
	return _interaction_weight


## Advances manual swap and interaction composition, then returns the physical
## shoulder offset consumed by TpsCamera before passage/collision clamping.
func update(delta: float) -> float:
	var base: float = _manual_offset(delta)
	var offset_alpha := 1.0 - exp(-interaction_offset_rate * delta)
	var weight_alpha := 1.0 - exp(-interaction_blend_rate * delta)
	_interaction_offset = lerpf(_interaction_offset, _interaction_goal, offset_alpha)
	_interaction_weight = lerpf(_interaction_weight, _interaction_weight_goal, weight_alpha)
	if _interaction_weight < 0.001 and _interaction_weight_goal <= 0.0:
		_interaction_weight = 0.0
		return base
	return lerpf(base, _interaction_offset, _interaction_weight)


func _manual_offset(delta: float) -> float:
	if state != Side.TRANSITION:
		return _offset_for(state)
	_time += delta
	var t: float = clampf(_time / transition_duration, 0.0, 1.0)
	var eased: float = t * t * (3.0 - 2.0 * t)
	var result: float = lerpf(_offset_for(_from), _offset_for(_pending), eased)
	if _time >= transition_duration:
		state = _pending
	return result


func _start(to: int) -> void:
	_from = state
	_pending = to
	_time = 0.0
	state = Side.TRANSITION


func _offset_for(side: int) -> float:
	return left_offset if side == Side.LEFT else right_offset
