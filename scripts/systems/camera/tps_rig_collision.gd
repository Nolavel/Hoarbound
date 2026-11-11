class_name TpsRigCollision
extends TpsRigBehaviour

## Walls on the boom, Lyra's way: the shoulder leg and the centre sweep snap in, feelers
## ease in, any release eases back out, and a camera left inside a body is pulled out.

## Lyra's soft feelers around the boom: yaw and pitch offsets (degrees), weight.
const FEELERS: Array = [[16.0, 0.0, 0.75], [-16.0, 0.0, 0.75], [32.0, 0.0, 0.5], [-32.0, 0.0, 0.5],
	[0.0, 20.0, 1.0], [0.0, -20.0, 0.5]]

## The direct rig's feelers: sphere sweeps like the boom's own, so they meet a jamb edge before it does.
const DIRECT_FEELERS: Array = [[7.0, 0.0, 1.0], [-7.0, 0.0, 1.0], [16.0, 0.0, 0.8], [-16.0, 0.0, 0.8],
	[32.0, 0.0, 0.5], [-32.0, 0.0, 0.5], [0.0, 10.0, 1.0], [0.0, -10.0, 1.0], [0.0, 22.0, 0.6], [0.0, -22.0, 0.6]]

## Seconds ahead along the shoulder's own travel the direct rig sweeps the boom from, and their weights:
## angle feelers warn of a turn, these warn of a lintel or jamb Henry is walking the boom into.
const DIRECT_LEADS: Array = [[0.3, 1.0], [0.5, 0.7]]

## Share of the shoulder leg and of the boom the walls leave, eased.
var _shoulder_pct: float = 1.0
var _dist_pct: float = 1.0
## Free length of the centre sweep last frame.
var _boom_room: float = INF
var _last_shoulder: Vector3 = Vector3.INF
var _shoulder_velocity: Vector3 = Vector3.ZERO


func reset() -> void:
	_shoulder_pct = 1.0
	_dist_pct = 1.0
	_last_shoulder = Vector3.INF
	_shoulder_velocity = Vector3.ZERO


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
	var soft_pct: float = minf(shares.y, _lead_share(delta, shoulder, back, want)) if rig.direct_rig else shares.y
	var this_frame: float = minf(hard_pct, soft_pct)
	if not rig.is_placed():
		_dist_pct = this_frame
	elif _dist_pct < this_frame:
		_dist_pct = lerpf(_dist_pct, this_frame, TpsCamera.damp(1.0 / rig.blend_out_time, delta))
	else:
		## The clamp and the ease are not exclusive: a boom resting on the centre sweep still heeds feelers.
		_dist_pct = minf(_dist_pct, hard_pct)
		if _dist_pct > soft_pct:
			_dist_pct = lerpf(_dist_pct, soft_pct, TpsCamera.damp(1.0 / rig.blend_in_time, delta))
	return _dist_pct


## Share of `want` left to a boom swept from where the shoulder will be in a moment, weighted like a feeler.
func _lead_share(delta: float, shoulder: Vector3, back: Vector3, want: float) -> float:
	var placed: bool = rig.is_placed() and _last_shoulder != Vector3.INF and delta > 0.0
	var velocity: Vector3 = (shoulder - _last_shoulder) / delta if placed else Vector3.ZERO
	_last_shoulder = shoulder
	## A teleport is not travel.
	if velocity.length() > 12.0:
		velocity = Vector3.ZERO
	_shoulder_velocity = _shoulder_velocity.lerp(velocity, TpsCamera.damp(12.0, delta)) if placed else Vector3.ZERO
	if _shoulder_velocity.length() < 0.2:
		return 1.0
	var probe: TpsBoomProbe = rig.get_probe()
	var share: float = 1.0
	for lead: Array in DIRECT_LEADS:
		var step: Vector3 = _shoulder_velocity * float(lead[0])
		## Never start a sweep past a wall Henry is walking at.
		var from: Vector3 = shoulder + step.normalized() * maxf(probe.sweep(shoulder, step) - 0.02, 0.0)
		var hit: float = clampf((probe.sweep(from, back * want) - rig.collision_surface_margin) / want, 0.0, 1.0)
		share = minf(share, hit + (1.0 - hit) * (1.0 - float(lead[1])))
	return maxf(share, clampf(rig.collision_min_distance / maxf(want, 0.001), 0.0, 1.0))


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
		_shoulder_pct = lerpf(_shoulder_pct, pct, TpsCamera.damp(1.0 / rig.blend_out_time, delta))
	return safe + leg * _shoulder_pct
