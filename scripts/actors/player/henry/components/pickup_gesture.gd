class_name PickupGesture
extends RefCounted

## F on an ordinary pickup: a quick tap stores it, holding past tap_max enters hand
## mode, and reaching hold_seconds takes it into the hands. Pure timing, no effects.

enum Phase { TAP_PENDING, HOLD, DONE }
enum Outcome { NONE, ENTERED_HOLD, TAP, CANCEL, HANDS }

## The pickup F went down on; attention moving away never changes it.
var target: InteractiveArea
var phase: Phase = Phase.TAP_PENDING
var elapsed: float = 0.0

var _tap_max: float
var _hold_seconds: float


func _init(gesture_target: InteractiveArea, tap_max: float, hold_seconds: float) -> void:
	target = gesture_target
	_tap_max = tap_max
	_hold_seconds = maxf(hold_seconds, tap_max + 0.01)


## Hand-mode progress, 0 on entering hold mode to 1 at hold_seconds.
func get_progress() -> float:
	if phase == Phase.TAP_PENDING:
		return 0.0
	return clampf((elapsed - _tap_max) / (_hold_seconds - _tap_max), 0.0, 1.0)


## The key is still down after this many seconds.
func update(duration: float) -> Outcome:
	elapsed = duration
	if phase == Phase.TAP_PENDING and elapsed > _tap_max:
		phase = Phase.HOLD
		return Outcome.ENTERED_HOLD
	if phase == Phase.HOLD and elapsed >= _hold_seconds:
		phase = Phase.DONE
		return Outcome.HANDS
	return Outcome.NONE


## The key came up after this many seconds. Once hold mode began it never becomes a tap.
func release(duration: float) -> Outcome:
	elapsed = duration
	match phase:
		Phase.TAP_PENDING:
			phase = Phase.DONE
			if duration <= _tap_max:
				return Outcome.TAP
			return Outcome.HANDS if duration >= _hold_seconds else Outcome.CANCEL
		Phase.HOLD:
			phase = Phase.DONE
			return Outcome.HANDS if duration >= _hold_seconds else Outcome.CANCEL
	return Outcome.NONE
