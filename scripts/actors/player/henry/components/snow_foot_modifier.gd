class_name SnowFootModifier
extends SkeletonModifier3D

## Snow has weight: a planted boot lands on the snow top and sinks as it packs,
## stays pinned where it landed, and the hips give a little on each heavy step.

## Bones on the UAL rig.
const THIGHS: Array[StringName] = [&"thigh_l", &"thigh_r"]
const CALVES: Array[StringName] = [&"calf_l", &"calf_r"]
const FEET: Array[StringName] = [&"foot_l", &"foot_r"]
const PELVIS: StringName = &"pelvis"

## Share of the lower boot's lift the hips follow. Below 1 the legs are shortened
## by the rest and the knees fold (Henry stood crouched on snow at spawn).
@export_range(0.0, 1.0) var hip_follow: float = 1.0
## Stiffness of a boot rising to clear snow and settling onto a print, rad/s.
@export var rise_omega: float = 28.0
@export var settle_omega: float = 16.0
## Damping ratio of the boot and hip springs; under 1 lets weight overshoot a touch.
@export_range(0.3, 1.5) var damping: float = 0.8
## Stiffness of the hips following the boots, rad/s.
@export var hip_omega: float = 10.0
## Downward hip speed a plant into the deepest snow gives, m/s.
@export var plant_dip_mps: float = 0.35
## Snow depth under a plant that gives the full hip dip, metres.
@export var plant_dip_depth_m: float = 0.35
## Gap kept between a swinging boot's sole and the snow top, metres.
@export var clearance_m: float = 0.03
## In snow deeper than the shell's wade depth the swing does not clear it all:
## this share of the depth past that is ploughed by the shin, not stepped over.
@export_range(0.0, 1.0) var plough_share: float = 0.5
## Ankle bone height above the sole, metres.
@export var ankle_m: float = 0.08
## Farthest a planted boot is held against the clip's glide, metres; past it the
## boot lets go and slides rather than stretching the leg.
@export var lock_reach_m: float = 0.1
## How fast the pin fades in on a plant and out on a lift, per second.
@export var lock_blend_rate: float = 10.0

var _lift: Array[float] = [0.0, 0.0]
var _lift_v: Array[float] = [0.0, 0.0]
var _applied: Array[float] = [0.0, 0.0]
var _hip: float = 0.0
var _hip_v: float = 0.0
var _planted: Array[bool] = [false, false]
var _lock_at: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _lock_weight: Array[float] = [0.0, 0.0]
## Last horizontal pin offset in world metres, kept to fade it out after a lift.
var _lock_offset: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _index: Dictionary = {}


func _process_modification() -> void:
	var skeleton: Skeleton3D = get_skeleton()
	var shell: SnowShell = SnowShell.active
	if skeleton == null or not is_instance_valid(shell):
		return
	## Capped so the stiffest spring stays stable through a hitch.
	var delta: float = clampf(get_process_delta_time(), 0.001, 0.033)
	for side: int in range(2):
		var planted: bool = shell.get_foot_snow_top(side) != -INF
		var want: float = shell.get_foot_raise(side)
		## A swinging boot clears the snow ahead of it by a hand's width, no more.
		if not planted:
			want = _swing_clearance(skeleton, shell, side)
		if planted and not _planted[side]:
			_on_plant(skeleton, side, want)
		_planted[side] = planted
		var omega: float = rise_omega if want > _lift[side] else settle_omega
		var spring: Vector2 = spring_step(_lift[side], _lift_v[side], want, omega, damping, delta)
		_lift[side] = maxf(spring.x, -0.01)
		_lift_v[side] = spring.y
		_lock_weight[side] = move_toward(_lock_weight[side], 1.0 if planted else 0.0, lock_blend_rate * delta)
	var hip_goal: float = minf(_lift[0], _lift[1]) * hip_follow
	var hip: Vector2 = spring_step(_hip, _hip_v, hip_goal, hip_omega, damping, delta)
	_hip = hip.x
	_hip_v = hip.y
	var idle: bool = absf(_hip) <= 0.001 and _lock_weight[0] <= 0.001 and _lock_weight[1] <= 0.001
	if idle and absf(_lift[0]) <= 0.001 and absf(_lift[1]) <= 0.001:
		_applied = [0.0, 0.0]
		return
	## World metres, in skeleton space (the rig may be scaled).
	var to_rig: Basis = skeleton.global_transform.basis.inverse()
	var up: Vector3 = to_rig * Vector3.UP
	var pelvis: int = _bone(skeleton, PELVIS)
	if pelvis >= 0 and absf(_hip) > 0.001:
		var pose: Transform3D = skeleton.get_bone_global_pose(pelvis)
		pose.origin += up * _hip
		skeleton.set_bone_global_pose(pelvis, pose)
	for side: int in range(2):
		var offset: Vector3 = up * (_lift[side] - _hip) + to_rig * _pin(skeleton, side)
		_applied[side] = _hip
		if offset.length() > 0.001:
			var moved: Vector3 = _reach(skeleton, side, offset)
			_applied[side] += moved.dot(up) / up.length_squared()


## One semi-implicit step of a damped spring from `x` with speed `v` towards
## `goal`; returns the new (x, v). Weight settles instead of snapping.
static func spring_step(x: float, v: float, goal: float, omega: float, zeta: float, dt: float) -> Vector2:
	var accel: float = -2.0 * zeta * omega * v - omega * omega * (x - goal)
	v += accel * dt
	return Vector2(x + v * dt, v)


## A boot landing: pin it where it lands, and let the hips give with the snow.
func _on_plant(skeleton: Skeleton3D, side: int, depth: float) -> void:
	var f: int = _bone(skeleton, FEET[side])
	if f >= 0:
		_lock_at[side] = skeleton.global_transform * skeleton.get_bone_global_pose(f).origin
	_hip_v -= plant_dip_mps * clampf(depth / maxf(plant_dip_depth_m, 0.01), 0.0, 1.0)


## World offset that holds a planted boot on its print against the clip's glide,
## faded by the lock weight; after a lift the last offset eases out.
func _pin(skeleton: Skeleton3D, side: int) -> Vector3:
	var weight: float = _lock_weight[side]
	if weight <= 0.001:
		_lock_offset[side] = Vector3.ZERO
		return Vector3.ZERO
	if _planted[side]:
		var f: int = _bone(skeleton, FEET[side])
		if f < 0:
			return Vector3.ZERO
		var ankle: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(f).origin
		var gap := Vector3(_lock_at[side].x - ankle.x, 0.0, _lock_at[side].z - ankle.z)
		if gap.length() > lock_reach_m:
			## Let go: re-pin at the reach limit so the boot slides, never snaps.
			var over: Vector3 = gap.normalized() * (gap.length() - lock_reach_m)
			_lock_at[side] -= over
			gap -= over
		_lock_offset[side] = gap
	return _lock_offset[side] * smoothstep(0.0, 1.0, weight)


## Two-bone solve (`LegTwoBoneIK`): moves the ankle by `offset`, keeping the
## boot's orientation. Returns how far the ankle really moved.
func _reach(skeleton: Skeleton3D, side: int, offset: Vector3) -> Vector3:
	return LegTwoBoneIK.reach(skeleton, _bone(skeleton, THIGHS[side]), _bone(skeleton, CALVES[side]), _bone(skeleton, FEET[side]), offset)


## Lift that lets the clip's swinging boot pass over the snow under it.
func _swing_clearance(skeleton: Skeleton3D, shell: SnowShell, side: int) -> float:
	var f: int = _bone(skeleton, FEET[side])
	if f < 0:
		return 0.0
	var ankle: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(f).origin
	var top: float = shell.field.get_snow_top(ankle.x, ankle.z)
	if top == -INF:
		return 0.0
	var depth: float = shell.field.get_depth(ankle.x, ankle.z)
	var ploughed: float = maxf(depth - shell.wade_depth_m, 0.0) * plough_share
	return maxf(top + clearance_m - ploughed - (ankle.y - ankle_m), 0.0)


## World metres the `side` boot was really lifted above the walk clip last frame.
func get_lift(side: int) -> float:
	return _applied[side]


func _bone(skeleton: Skeleton3D, bone: StringName) -> int:
	if not _index.has(bone):
		_index[bone] = skeleton.find_bone(bone)
	return _index[bone]
