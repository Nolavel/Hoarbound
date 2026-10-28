class_name TpsRigCollision
extends TpsRigBehaviour

## Walls on the boom, Lyra's way: the shoulder leg and the centre sweep snap in, feelers
## ease in, any release eases back out, and a camera left inside a body is pulled out.

## Lyra's soft feelers around the boom: yaw and pitch offsets (degrees), weight.
const FEELERS: Array = [[16.0, 0.0, 0.75], [-16.0, 0.0, 0.75], [32.0, 0.0, 0.5], [-32.0, 0.0, 0.5],
	[0.0, 20.0, 1.0], [0.0, -20.0, 0.5]]

## Share of the shoulder leg and of the boom the walls leave, eased.
var _shoulder_pct: float = 1.0
var _dist_pct: float = 1.0
## Free length of the centre sweep last frame.
var _boom_room: float = INF


func reset() -> void:
	_shoulder_pct = 1.0
	_dist_pct = 1.0


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
	var soft_pct: float = shares.y
	var this_frame: float = minf(hard_pct, soft_pct)
	if not rig.is_placed():
		_dist_pct = this_frame
	elif _dist_pct < this_frame:
		_dist_pct = lerpf(_dist_pct, this_frame, TpsCamera.damp(1.0 / rig.blend_out_time, delta))
	elif _dist_pct > hard_pct:
		_dist_pct = hard_pct
	elif _dist_pct > soft_pct:
		_dist_pct = lerpf(_dist_pct, soft_pct, TpsCamera.damp(1.0 / rig.blend_in_time, delta))
	return _dist_pct


## Stateless: shares of `want` the centre sweep (x) and the feelers (y) leave, and the
## centre sweep's free length (z).
func target_shares(shoulder: Vector3, back: Vector3, want: float) -> Vector3:
	var probe: TpsBoomProbe = rig.get_probe()
	var min_pct: float = clampf(rig.collision_min_distance / maxf(want, 0.001), 0.0, 1.0)
	var room: float = probe.sweep(shoulder, back * want)
	var hard_pct: float = clampf((room - rig.collision_surface_margin) / want, min_pct, 1.0)
	var soft_pct: float = 1.0
	var right: Vector3 = back.cross(Vector3.UP).normalized()
	for feeler: Array in FEELERS:
		var dir: Vector3 = back.rotated(Vector3.UP, deg_to_rad(feeler[0]))
		if right.length_squared() > 0.0:
			dir = dir.rotated(right, deg_to_rad(feeler[1]))
		var hit: float = probe.ray(shoulder, dir * want) / want
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
