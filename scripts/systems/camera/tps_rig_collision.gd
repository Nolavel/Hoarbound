class_name TpsRigCollision
extends TpsRigBehaviour

## Walls on the boom, Lyra's way: the shoulder leg and the centre sweep snap in, feelers
## ease in, any release eases back out, and a camera left inside a body is pulled out.

## Lyra's soft feelers around the boom: yaw and pitch offsets (degrees), weight.
const FEELERS: Array = [[16.0, 0.0, 0.75], [-16.0, 0.0, 0.75], [32.0, 0.0, 0.5], [-32.0, 0.0, 0.5],
	[0.0, 20.0, 1.0], [0.0, -20.0, 0.5]]

## The direct rig's feelers: sphere sweeps like the boom's own, so they meet a jamb edge before it does.
const DIRECT_FEELERS: Array = [[7.0, 0.0, 1.0], [-7.0, 0.0, 1.0], [16.0, 0.0, 0.6], [-16.0, 0.0, 0.6],
	[32.0, 0.0, 0.25], [-32.0, 0.0, 0.25], [0.0, 10.0, 1.0], [0.0, -10.0, 1.0], [0.0, 22.0, 0.6], [0.0, -22.0, 0.6]]

## Seconds ahead, by the shoulder's travel and the view's turn rate, the direct rig sweeps the boom at, and
## their weights: fixed feelers warn of what is near the boom, these of what he walks or turns it into.
const DIRECT_LEADS: Array = [[0.15, 1.0], [0.3, 1.0], [0.5, 0.7]]
## Seconds ahead the shoulder's sideways room is read at.
const SIDE_LEADS: Array = [0.0, 0.2, 0.4]
## Most a lead sweep is turned ahead of the view, radians: a flick must not sweep the room behind it.
const MAX_LEAD_TURN: float = 0.8

## Share of the shoulder leg and of the boom the walls leave, eased.
var _shoulder_pct: float = 1.0
var _dist_pct: float = 1.0
## Free length of the centre sweep last frame.
var _boom_room: float = INF
## Seconds left before a shortened direct boom may lengthen again.
var _out_hold: float = 0.0
var _last_shoulder: Vector3 = Vector3.INF
var _shoulder_velocity: Vector3 = Vector3.ZERO
## The boom's yaw and pitch last frame, and their eased rates, radians and radians per second.
var _last_aim: Vector2 = Vector2.ZERO
var _aim_rate: Vector2 = Vector2.ZERO


func reset() -> void:
	_shoulder_pct = 1.0
	_dist_pct = 1.0
	_last_shoulder = Vector3.INF
	_shoulder_velocity = Vector3.ZERO
	_aim_rate = Vector2.ZERO


func get_shoulder_share() -> float:
	return _shoulder_pct


func get_boom_share() -> float:
	return _dist_pct


func get_boom_room() -> float:
	return _boom_room


## Places frame.shoulder and frame.camera with walls applied.
func apply(frame: TpsRigFrame) -> void:
	frame.shoulder = _sweep_shoulder(frame.delta, frame.safe, frame.pivot + frame.right * frame.side)
	frame.camera = frame.shoulder + frame.back * frame.want * _blend_boom(frame.delta, frame.shoulder, frame.back, frame.want)
	## Safety net for a camera left inside a blocking body; thin ones still pass.
	var probe: TpsBoomProbe = rig.get_probe()
	if probe.overlaps(frame.camera):
		var hard: float = probe.sweep(frame.shoulder, frame.back * frame.want) - rig.collision_surface_margin
		frame.camera = frame.shoulder + frame.back * clampf(hard, rig.collision_min_distance, frame.want)


## Lyra's penetration blend: the centre sweep snaps the boom in, the feelers ease
## it in, and any release eases it back out. Returns the share of `want` kept.
func _blend_boom(delta: float, shoulder: Vector3, back: Vector3, want: float) -> float:
	var shares: Vector3 = target_shares(shoulder, back, want)
	_boom_room = shares.z
	var hard_pct: float = shares.x
	var soft_pct: float = minf(shares.y, _foresee(delta, shoulder, back, want)) if rig.direct_rig else shares.y
	var this_frame: float = minf(hard_pct, soft_pct)
	if not rig.is_placed():
		_dist_pct = this_frame
	elif _dist_pct < this_frame:
		## The direct rig waits before it lets the boom back out, and lets it out slowly: a camera that
		## springs out the moment a wall clears pumps in and out all the way round a room.
		_out_hold = maxf(_out_hold - delta, 0.0)
		if not rig.direct_rig:
			_dist_pct = lerpf(_dist_pct, this_frame, TpsCamera.damp(1.0 / rig.blend_out_time, delta))
		elif _out_hold <= 0.0:
			_dist_pct = lerpf(_dist_pct, this_frame, TpsCamera.damp(1.0 / rig.direct_out_time, delta))
	else:
		_out_hold = rig.direct_out_hold
		## The clamp and the ease are not exclusive: a boom resting on the centre sweep still heeds feelers.
		_dist_pct = minf(_dist_pct, hard_pct)
		if _dist_pct > soft_pct:
			_dist_pct = lerpf(_dist_pct, soft_pct, TpsCamera.damp(1.0 / rig.blend_in_time, delta))
	return _dist_pct


## Share of `want` left to the boom a moment ahead, weighted like a feeler: swept from where the shoulder
## will be and along where the view will point, by their own measured rates.
func _foresee(delta: float, shoulder: Vector3, back: Vector3, want: float) -> float:
	var placed: bool = rig.is_placed() and _last_shoulder != Vector3.INF and delta > 0.0
	var velocity: Vector3 = (shoulder - _last_shoulder) / delta if placed else Vector3.ZERO
	var yaw: float = atan2(back.x, back.z)
	var pitch: float = asin(clampf(back.y, -1.0, 1.0))
	var turn := Vector2(angle_difference(_last_aim.x, yaw), pitch - _last_aim.y) / delta if placed else Vector2.ZERO
	_last_shoulder = shoulder
	_last_aim = Vector2(yaw, pitch)
	## A teleport is not travel.
	if velocity.length() > 12.0:
		velocity = Vector3.ZERO
	var ease: float = TpsCamera.damp(12.0, delta)
	_shoulder_velocity = _shoulder_velocity.lerp(velocity, ease) if placed else Vector3.ZERO
	_aim_rate = _aim_rate.lerp(turn, ease) if placed else Vector2.ZERO
	if _shoulder_velocity.length() < 0.2 and _aim_rate.length() < deg_to_rad(5.0):
		return 1.0
	var probe: TpsBoomProbe = rig.get_probe()
	var right: Vector3 = back.cross(Vector3.UP).normalized()
	var share: float = 1.0
	for lead: Array in DIRECT_LEADS:
		var ahead: float = lead[0]
		var step: Vector3 = _shoulder_velocity * ahead
		## Never start a sweep past a wall Henry is walking at.
		var from: Vector3 = shoulder
		if step.length() > 0.001:
			from += step.normalized() * maxf(probe.sweep(shoulder, step) - 0.1, 0.0)
		var swing: Vector2 = (_aim_rate * ahead).limit_length(MAX_LEAD_TURN)
		var dir: Vector3 = back.rotated(Vector3.UP, swing.x)
		if right.length_squared() > 0.0:
			dir = dir.rotated(right, swing.y)
		var hit: float = clampf((probe.sweep(from, dir * want) - rig.collision_surface_margin) / want, 0.0, 1.0)
		share = minf(share, hit + (1.0 - hit) * (1.0 - float(lead[1])))
	return maxf(share, clampf(rig.collision_min_distance / maxf(want, 0.001), 0.0, 1.0))


## Free sideways room for a shoulder `side` metres out, now and where travel and turn will have it in a
## moment: the direct rig keeps its shoulder inside this, so a jamb closes it in before it cuts it.
func lateral_room(safe: Vector3, pivot: Vector3, right: Vector3, side: float) -> float:
	var probe: TpsBoomProbe = rig.get_probe()
	var reach: float = absf(side)
	var room: float = reach
	if reach < 0.001:
		return 0.0
	for ahead: float in SIDE_LEADS:
		var shift: Vector3 = _shoulder_velocity * ahead
		if shift.length() > 0.001:
			shift = shift.normalized() * maxf(probe.sweep(safe, shift, false) - 0.1, 0.0)
		var turn: float = clampf(_aim_rate.x * ahead, -MAX_LEAD_TURN, MAX_LEAD_TURN)
		var leg: Vector3 = (pivot - safe) + right.rotated(Vector3.UP, turn) * side
		if leg.length() < 0.001:
			continue
		room = minf(room, probe.sweep(safe + shift, leg, false) / leg.length() * reach)
	return room


## Stateless: shares of `want` the centre sweep (x) and the feelers (y) leave, and the
## centre sweep's free length (z).
func target_shares(shoulder: Vector3, back: Vector3, want: float) -> Vector3:
	var probe: TpsBoomProbe = rig.get_probe()
	var min_pct: float = clampf(rig.collision_min_distance / maxf(want, 0.001), 0.0, 1.0)
	var room: float = probe.sweep(shoulder, back * want)
	var hard_pct: float = clampf((room - rig.collision_surface_margin) / want, min_pct, 1.0)
	var soft_pct: float = 1.0
	var right: Vector3 = back.cross(Vector3.UP).normalized()
	var direct: bool = rig.direct_rig
	for feeler: Array in (DIRECT_FEELERS if direct else FEELERS):
		var dir: Vector3 = back.rotated(Vector3.UP, deg_to_rad(feeler[0]))
		if right.length_squared() > 0.0:
			dir = dir.rotated(right, deg_to_rad(feeler[1]))
		var hit: float = 0.0
		if direct:
			hit = clampf((probe.sweep(shoulder, dir * want) - rig.collision_surface_margin) / want, 0.0, 1.0)
		else:
			hit = probe.ray(shoulder, dir * want) / want
		soft_pct = minf(soft_pct, hit + (1.0 - hit) * (1.0 - float(feeler[2])))
	return Vector3(hard_pct, maxf(soft_pct, min_pct), room)


## First leg of the rig: from inside Henry to the shoulder point. Thin props do
## not pass here; the shoulder snaps in and eases back out.
func _sweep_shoulder(delta: float, safe: Vector3, goal: Vector3) -> Vector3:
	var leg: Vector3 = goal - safe
	var length: float = leg.length()
	if length < 0.001:
		return goal
	var free: float = rig.get_probe().sweep(safe, leg, false)
	var pct: float = clampf((free - 0.05) / length, 0.0, 1.0)
	if not rig.is_placed() or pct < _shoulder_pct:
		_shoulder_pct = pct
	else:
		_shoulder_pct = lerpf(_shoulder_pct, pct, TpsCamera.damp(1.0 / (rig.direct_out_time if rig.direct_rig else rig.blend_out_time), delta))
	return safe + leg * _shoulder_pct
