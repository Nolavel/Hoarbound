class_name StoveHandReach
extends DoorHandIK

## Addressed right-arm action over the existing crouch. The same analytic two-bone
## solve as door contact; the spine lean and palm goal follow the action trajectory.
signal hand_solved(palm_world: Vector3)
var grip_weight: float = 0.0
var lean_weight: float = 0.0
var fingers_world: Vector3 = Vector3.LEFT
## Palm frame `into` for _flatten_palm: down onto the stove load, the arm's outward side when presenting.
var palm_into_world: Vector3 = Vector3.DOWN
## Weight per second while the arm eases back to the animation.
var ease_out_rate: float = 6.0
var palm_world: Vector3 = Vector3.ZERO

func _init() -> void:
	use_left_hand(false)
	elbow_drop = 0.3
	palm_flatten = 1.0

func use_left_hand(left: bool) -> void:
	if left_hand != left:
		_weight = 0.0
	left_hand = left
	var suffix: String = "l" if left else "r"
	upper_bone = StringName("upperarm_"+suffix)
	lower_bone = StringName("lowerarm_"+suffix)
	hand_bone = StringName("hand_"+suffix)
	middle_bone = StringName("middle_01_"+suffix)
	index_bone = StringName("index_01_"+suffix)
	pinky_bone = StringName("pinky_01_"+suffix)
	_index.clear()

func aim(point: Vector3, fingers: Vector3, weight: float) -> void:
	_goal_point = point
	fingers_world = fingers.normalized()
	_goal_weight = clampf(weight,0.0,1.0)

## Eases the arm back to the animation from where it is; the last goal stays put.
func release() -> void:
	_goal_weight = 0.0

## 0..1: how far the arm currently follows the reach rather than the animation.
func get_weight() -> float:
	return _weight

func _process_modification() -> void:
	var rig := get_skeleton()
	if rig == null:
		return
	_weight = move_toward(_weight,_goal_weight,(6.0 if _goal_weight > _weight else ease_out_rate)*clampf(get_process_delta_time(),0.001,0.05))
	if _weight <= 0.001:
		return
	var u: int = _bone(rig,upper_bone)
	var l: int = _bone(rig,lower_bone)
	var h: int = _bone(rig,hand_bone)
	if mini(u,mini(l,h)) < 0:
		return
	var inverse: Transform3D = rig.global_transform.affine_inverse()
	var spine: int = rig.find_bone(&"spine_01")
	if spine >= 0:
		var pose: Transform3D = rig.get_bone_global_pose(spine)
		var forward: Vector3 = _goal_point-rig.to_global(pose.origin)
		forward.y = 0.0
		if forward.length_squared() > 0.001:
			var axis: Vector3 = inverse.basis * Vector3.UP.cross(forward.normalized())
			pose.basis = Basis(axis.normalized(),lean_weight*_weight)*pose.basis
			rig.set_bone_global_pose(spine,pose)
	var wrist: Vector3 = rig.get_bone_global_pose(h).origin.lerp(inverse*(_goal_point-fingers_world*0.08),smoothstep(0,1,_weight))
	_solve(rig,u,l,h,wrist,_weight)
	_flatten_palm(rig,h,inverse.basis*fingers_world,inverse.basis*palm_into_world,_weight)
	_curl_fingers(rig,inverse.basis)
	palm_world = rig.to_global(rig.get_bone_global_pose(h).origin)+fingers_world*0.08
	hand_solved.emit(palm_world)


func _curl_fingers(rig: Skeleton3D, inverse: Basis) -> void:
	var axis: Vector3 = inverse*fingers_world.cross(palm_into_world).normalized()
	if axis.length_squared() < 0.1:
		return
	for finger: String in ["index","middle","ring","pinky"]:
		for joint: int in range(1,4):
			var index: int = rig.find_bone(StringName("%s_0%d_%s" % [finger,joint,"l" if left_hand else "r"]))
			if index < 0:
				continue
			var pose: Transform3D = rig.get_bone_global_pose(index)
			pose.basis = Basis(axis.normalized(),(0.85 if joint == 2 else 0.45)*grip_weight*_weight)*pose.basis
			rig.set_bone_global_pose(index,pose)
