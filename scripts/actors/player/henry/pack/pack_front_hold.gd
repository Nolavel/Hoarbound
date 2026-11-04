class_name PackFrontHold
extends Node

## The pack held open before Henry (3D inventory, stage 3): it swings off the back to a spot ahead of his
## chest, upright with its opening turned out toward the camera that faces him (front_view()), tipped back so he
## sees in from above too; the front panel opens down and away from him. Both hands take it by the sides
## (HandGrip). Ended, it swings back on and the hands let go.

signal settled
signal finished

## Where the pack's middle is held: ahead of the chest, below it, metres.
const AHEAD_M: float = 0.46
const BELOW_M: float = 0.18
## How far the opening tips up from facing straight out, so Henry sees in from above, degrees.
const TIP_DEG: float = 45.0
## The camera: the share of the frame height the pack fills, how much it rises above the opening's line, and
## how far above the pack's middle it aims (so Henry's face shows over the pack), metres.
const FRAME_SHARE: float = 0.47
const VIEW_RISE: float = 0.35
const VIEW_LIFT_M: float = -0.07
## The strap that stays over a shoulder while the pack is held (0 left, 1 right).
const STRAP_KEPT_SIDE: int = 0
## Swinging off the back and on again takes this long, seconds.
const SWING_S: float = 0.7
## How high the swing arcs above the straight path, metres.
const ARC_M: float = 0.18
## The hands take the sides this far below the pack's middle, this far out from its walls and this far back
## toward its back face (outside the opening), metres.
const GRIP_DROP_M: float = 0.08
const GRIP_OUT_M: float = 0.1
const GRIP_BACK_M: float = 0.05

var visual: HenryUALAnimation
var pack: PackRig
var _home_parent: Node
var _home_transform: Transform3D
var _from: Transform3D
var _t: float = 0.0
var _ending: bool = false


## Takes `rig` off the back of `henry` and starts the swing to the front.
func start(henry: HenryUALAnimation, rig: PackRig) -> void:
	visual = henry
	pack = rig
	_home_parent = rig.get_parent()
	_home_transform = rig.transform
	_from = rig.global_transform
	var world: Node = henry.get_tree().current_scene if henry.get_tree().current_scene != null else henry.get_tree().root
	rig.reparent(world, true)
	rig.set_openness(PackRig.Openness.FULL)
	## He slips one arm out only: the left strap stays over his shoulder (PackShoulderStraps).
	rig.set_meta(&"strap_on_shoulder", STRAP_KEPT_SIDE)


## Swings the pack back on; `finished` fires when it is home and the hands are free.
func finish() -> void:
	if _ending:
		return
	_ending = true
	_from = held_transform()
	pack.set_openness(PackRig.Openness.CLOSED)


func is_settled() -> bool:
	return not _ending and _t >= 1.0


## Where the pack is held now (world): ahead of and below the chest, the opening tipped up toward Henry.
func held_transform() -> Transform3D:
	var body := visual.get_parent() as Node3D
	var rig: Skeleton3D = visual.skeleton
	var chest_bone: int = rig.find_bone(&"spine_03")
	var chest: Vector3 = rig.to_global(rig.get_bone_global_pose(chest_bone).origin) if chest_bone >= 0 else body.global_position + Vector3.UP * 1.3
	## Ahead is square to the line between his shoulders, whatever the nodes above the skeleton are turned to.
	var left_bone: int = rig.find_bone(&"upperarm_l")
	var right_bone: int = rig.find_bone(&"upperarm_r")
	var shoulders: Vector3 = rig.to_global(rig.get_bone_global_pose(right_bone).origin) - rig.to_global(rig.get_bone_global_pose(left_bone).origin)
	var forward: Vector3 = Vector3.UP.cross(shoulders) if left_bone >= 0 and right_bone >= 0 else visual.global_basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 1e-6 else Vector3.FORWARD
	var tip: float = deg_to_rad(TIP_DEG)
	## The rig's -Z is its opening (outward on the back): it faces out ahead of Henry, tipped up; its top leans
	## back toward him and its bottom (the panel's hinge) is below, so the panel drops open away from him.
	var opening: Vector3 = (forward * cos(tip) + Vector3.UP * sin(tip)).normalized()
	var top: Vector3 = (Vector3.UP - opening * Vector3.UP.dot(opening)).normalized()
	var across: Vector3 = top.cross(-opening).normalized()
	return Transform3D(Basis(across, top, -opening), chest + forward * AHEAD_M - Vector3.UP * BELOW_M)


## The inventory camera: facing Henry, square to the pack's opening and a little above it, at the distance where
## the pack fills FRAME_SHARE of the height at `fov` degrees.
func front_view(fov: float) -> Transform3D:
	var held: Transform3D = held_transform()
	var opening: Vector3 = -held.basis.z.normalized()
	var distance: float = view_distance(fov)
	var eye: Vector3 = held.origin + (opening + Vector3.UP * VIEW_RISE).normalized() * distance
	return Transform3D(Basis.IDENTITY, eye).looking_at(held.origin + Vector3.UP * VIEW_LIFT_M, Vector3.UP)


## How far the front view stands from the pack's middle at `fov` degrees (the camera focuses there), metres.
func view_distance(fov: float) -> float:
	return (pack.size.y * 0.5 / FRAME_SHARE) / tan(deg_to_rad(fov) * 0.5)


func _process(delta: float) -> void:
	if visual == null or pack == null:
		return
	if _ending:
		_t = maxf(_t - delta / SWING_S, 0.0)
	elif _t < 1.0:
		_t = minf(_t + delta / SWING_S, 1.0)
		if _t >= 1.0:
			settled.emit()
	var eased: float = smoothstep(0.0, 1.0, _t)
	var home: Transform3D = _home_parent.global_transform * _home_transform if is_instance_valid(_home_parent) else _from
	var start: Transform3D = home if not _ending else home
	var held: Transform3D = held_transform() if not _ending else _from
	var at: Transform3D = start.interpolate_with(held, eased)
	at.origin += Vector3.UP * ARC_M * sin(PI * eased) * (1.0 - eased)
	pack.global_transform = at
	_grip_sides(eased)
	if _ending and _t <= 0.0:
		_put_back()


## Both hands on the pack's side walls, palms in, fingers down its sides; weight follows the swing.
func _grip_sides(weight: float) -> void:
	var at: Transform3D = pack.global_transform
	var half: Vector3 = pack.size * 0.5
	for left: bool in [true, false]:
		var grip: HandGrip = visual.get_hand_grip(left)
		if grip == null:
			continue
		var side: float = -1.0 if left else 1.0
		var outward: Vector3 = at.basis.x.normalized() * side
		var wrist: Vector3 = at.origin + outward * (half.x + GRIP_OUT_M) - at.basis.y.normalized() * GRIP_DROP_M + at.basis.z.normalized() * GRIP_BACK_M
		## Fingers down the side and slightly in, palm on the wall from outside; elbows wide so no sleeve enters.
		var along: Vector3 = (-at.basis.y.normalized() + outward * 0.15).normalized()
		var across: Vector3 = at.basis.z.normalized()
		var pole: Vector3 = wrist + outward * 0.6 + Vector3.DOWN * 0.15 + at.basis.z.normalized() * 0.2
		grip.hold(wrist, along, across, pole, weight)


func _put_back() -> void:
	for left: bool in [true, false]:
		var grip: HandGrip = visual.get_hand_grip(left)
		if grip != null:
			grip.release()
	pack.remove_meta(&"strap_on_shoulder")
	if is_instance_valid(_home_parent):
		pack.reparent(_home_parent, false)
		pack.transform = _home_transform
	visual = null
	finished.emit()
	queue_free()
