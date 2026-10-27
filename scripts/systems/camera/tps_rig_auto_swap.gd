class_name TpsRigAutoSwap
extends TpsRigBehaviour

## Automatic shoulder: crosses to the other side when the player's side stays walled off and
## the other is free, and comes back once it has been clear a while.

## 0 on the player's shoulder, 1 crossed to the other one; the timer counts the condition.
var _swap: float = 0.0
var _swap_goal: float = 0.0
var _swap_timer: float = 0.0
var _swap_rooms: Vector2 = Vector2.ONE


func get_swap() -> float:
	return _swap


## Free share of a shoulder reach on the player's side (x) and the other (y), last frame.
func get_rooms() -> Vector2:
	return _swap_rooms


## Multiplier for the player's shoulder: 1 on it, -1 crossed, eased between.
func update(frame: TpsRigFrame, shoulder: float) -> float:
	var delta: float = frame.delta
	if not rig.auto_shoulder_swap or rig.get_passage_blend() > 0.05 or absf(shoulder) < 0.05:
		_swap_goal = 0.0
		_swap_timer = 0.0
	else:
		var right := Vector3(cos(frame.view_yaw), 0.0, -sin(frame.view_yaw))
		var reach: float = maxf(absf(shoulder) * lerpf(rig.tight_shoulder_fraction, 1.0, 0.5), 0.4)
		var own: float = rig.get_probe().sweep(frame.safe, right * signf(shoulder) * reach) / reach
		var other: float = rig.get_probe().sweep(frame.safe, -right * signf(shoulder) * reach) / reach
		_swap_rooms = Vector2(own, other)
		## Never while the mouse turns: the player owns the view then and the body guard holds walls.
		var settled: bool = rig.get_look_idle_time() > 0.3 or Vector2(rig.player.velocity.x, rig.player.velocity.z).length() > 0.5
		var wants_cross: bool = settled and own < rig.swap_blocked_share and other - own >= rig.swap_margin
		var wants_home: bool = own > rig.swap_free_share
		var leaving: bool = wants_cross if _swap_goal == 0.0 else wants_home
		_swap_timer = _swap_timer + delta if leaving else 0.0
		if leaving and _swap_timer >= (rig.swap_after_s if _swap_goal == 0.0 else rig.swap_back_after_s):
			_swap_goal = 1.0 - _swap_goal
			_swap_timer = 0.0
	_swap = move_toward(_swap, _swap_goal, delta / maxf(rig.swap_duration_s, 0.01)) if rig.is_placed() else _swap_goal
	return 1.0 - 2.0 * smoothstep(0.0, 1.0, _swap)
