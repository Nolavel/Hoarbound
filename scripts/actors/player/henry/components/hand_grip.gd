class_name HandGrip
extends SkeletonModifier3D

signal gripped

## One hand holding an item by its handle, for any item: the item says where its handle is (anchor, axis,
## radius); the arm reaches with Godot's TwoBoneIK3D, the hand turns within the wrist's range, BoneTwistDisperser3D
## spreads the forearm roll over the arm's bones, and the fingers close until they meet the handle.

## Wrist range off the forearm's line (flexion/extension and deviation together), degrees.
const WRIST_CONE_DEG: float = 60.0
## Finger closing: step per pass, passes, and the gap a finger tip stops at above the handle, metres.
const CURL_STEP: float = 0.08
const CURL_PASSES: int = 24
const FINGER_SKIN_M: float = 0.009
const FINGERS: Array[String] = ["index", "middle", "ring", "pinky"]

## The held item's handle radius, metres.
var handle_radius: float = 0.012
## Hand goal (world): wrist position and the hand's frame as along (wrist to knuckles) and across (index to pinky).
var goal_wrist: Vector3 = Vector3.ZERO
var goal_along: Vector3 = Vector3.DOWN
var goal_across: Vector3 = Vector3.FORWARD
## The handle in world space this frame (after the solve), for placing the item.
var handle_centre: Vector3 = Vector3.ZERO
var handle_axis: Vector3 = Vector3.FORWARD
var palm_out: Vector3 = Vector3.ZERO
var hand_along: Vector3 = Vector3.DOWN
var left_hand: bool = false
var _weight: float = 0.0
var _goal_weight: float = 0.0
var _ik: TwoBoneIK3D
var _twist: BoneTwistDisperser3D
var _target: Node3D
var _pole: Node3D


## Builds the arm's modifiers after this one's place in the stack: IK first, then this (hand and fingers), then the twist spread.
func setup(left: bool) -> void:
	left_hand = left
	var rig: Skeleton3D = get_skeleton()
	var s: String = "l" if left else "r"
	_target = Node3D.new()
	_target.name = "GripTarget_" + s
	rig.add_child(_target)
	_pole = Node3D.new()
	_pole.name = "GripPole_" + s
	rig.add_child(_pole)
	_ik = TwoBoneIK3D.new()
	_ik.name = "GripIK_" + s
	_ik.setting_count = 1
	_ik.set_root_bone_name(0, "upperarm_" + s)
	_ik.set_middle_bone_name(0, "lowerarm_" + s)
	_ik.set_end_bone_name(0, "hand_" + s)
	rig.add_child(_ik)
	rig.move_child(_ik, get_index())
	_ik.set_target_node(0, _ik.get_path_to(_target))
	_ik.set_pole_node(0, _ik.get_path_to(_pole))
	_ik.influence = 0.0
	_twist = BoneTwistDisperser3D.new()
	_twist.name = "GripTwist_" + s
	_twist.setting_count = 1
	_twist.set_root_bone_name(0, "upperarm_" + s)
	_twist.set_end_bone_name(0, "hand_" + s)
	_twist.set_twist_from_rest(0, true)
	rig.add_child(_twist)
	rig.move_child(_twist, get_index() + 1)
	_twist.influence = 0.0


## Holds the goal this frame; weight eases in (1) or out (0).
func hold(wrist: Vector3, along: Vector3, across: Vector3, pole: Vector3, weight: float) -> void:
	goal_wrist = wrist
	goal_along = along.normalized()
	goal_across = (across - goal_along * across.dot(goal_along)).normalized()
	_goal_weight = clampf(weight, 0.0, 1.0)
	if _target != null:
		_target.global_position = wrist
		_pole.global_position = pole


func release() -> void:
	_goal_weight = 0.0


func get_weight() -> float:
	return _weight


func _process_modification() -> void:
	var rig: Skeleton3D = get_skeleton()
	if rig == null or _ik == null:
		return
	_weight = move_toward(_weight, _goal_weight, 5.0 * clampf(get_process_delta_time(), 0.001, 0.05))
	var w: float = smoothstep(0.0, 1.0, _weight)
	_ik.influence = w
	_twist.influence = w
	if w <= 0.001:
		return
	var s: String = "l" if left_hand else "r"
	var h: int = rig.find_bone("hand_" + s)
	var l: int = rig.find_bone("lowerarm_" + s)
	var to_rig: Basis = rig.global_basis.inverse()
	var hand: Transform3D = rig.get_bone_global_pose(h)
	var frame: Array = _palm_frame(rig, s)
	var have := Basis(frame[1], frame[0], (frame[1] as Vector3).cross(frame[0]))
	var along: Vector3 = (to_rig * goal_along).normalized()
	var across: Vector3 = (to_rig * goal_across).normalized()
	## The wrist only bends so far off the forearm: the goal's along is held inside the cone.
	var fore: Vector3 = (hand.origin - rig.get_bone_global_pose(l).origin).normalized()
	var cone: float = deg_to_rad(WRIST_CONE_DEG)
	if fore.angle_to(along) > cone:
		var turn := Quaternion(fore, along)
		along = (Basis(Quaternion.IDENTITY.slerp(turn, cone / fore.angle_to(along))) * fore).normalized()
		across = (across - along * across.dot(along)).normalized()
	var want := Basis(across, along, across.cross(along))
	var turn_hand: Quaternion = (want * have.inverse()).get_rotation_quaternion()
	hand.basis = Basis(Quaternion.IDENTITY.slerp(turn_hand, w)) * hand.basis
	rig.set_bone_global_pose(h, hand)
	_close_fingers(rig, s, w)


## Wrist to knuckles, index to pinky, and out of the palm (the side the fingers close to), rig space.
func _palm_frame(rig: Skeleton3D, s: String) -> Array:
	var wrist: Vector3 = rig.get_bone_global_pose(rig.find_bone("hand_" + s)).origin
	var along: Vector3 = (rig.get_bone_global_pose(rig.find_bone("middle_01_" + s)).origin - wrist).normalized()
	var across: Vector3 = rig.get_bone_global_pose(rig.find_bone("pinky_01_" + s)).origin - rig.get_bone_global_pose(rig.find_bone("index_01_" + s)).origin
	across = (across - along * across.dot(along)).normalized()
	## along x (index - pinky) is the back of a right hand on Henry's rig (measured), mirrored on the left.
	var back: Vector3 = along.cross(-across) * (-1.0 if left_hand else 1.0)
	return [along, across, -back]


## Places the handle in the palm's hollow, then closes each finger's three joints together in small steps until
## its tip meets the handle (as Auto Hand closes VR fingers on a collider).
func _close_fingers(rig: Skeleton3D, s: String, w: float) -> void:
	var frame: Array = _palm_frame(rig, s)
	var along: Vector3 = frame[0]
	var across: Vector3 = frame[1]
	var palm: Vector3 = frame[2]
	var knuckles: Vector3 = rig.get_bone_global_pose(rig.find_bone("middle_01_" + s)).origin
	var centre: Vector3 = knuckles - along * 0.012 + palm * (handle_radius + FINGER_SKIN_M)
	var axis: Vector3 = along.cross(palm).normalized()
	for finger: String in FINGERS:
		var bones: Array[int] = []
		for joint: int in range(1, 4):
			bones.append(rig.find_bone("%s_0%d_%s" % [finger, joint, s]))
		if bones.has(-1):
			continue
		for _pass: int in CURL_PASSES:
			var off: Vector3 = _tip(rig, bones[2]) - centre
			off -= across * off.dot(across)
			if off.length() <= handle_radius + FINGER_SKIN_M:
				break
			for k: int in 3:
				var pose: Transform3D = rig.get_bone_global_pose(bones[k])
				pose.basis = Basis(axis, CURL_STEP * [1.0, 1.2, 0.8][k] * w) * pose.basis
				rig.set_bone_global_pose(bones[k], pose)
	_close_thumb(rig, s, w, centre, along, across, palm)
	var rig_to_world: Transform3D = rig.global_transform
	handle_centre = rig_to_world * centre
	handle_axis = (rig_to_world.basis * across).normalized()
	palm_out = (rig_to_world.basis * palm).normalized()
	hand_along = (rig_to_world.basis * along).normalized()
	gripped.emit()


## The thumb wraps the handle from the other side: it turns across the palm (about the wrist-to-knuckles line),
## then bends at its joints, until its tip meets the handle.
func _close_thumb(rig: Skeleton3D, s: String, w: float, centre: Vector3, along: Vector3, across: Vector3, palm: Vector3) -> void:
	var bones: Array[int] = []
	for joint: int in range(1, 4):
		bones.append(rig.find_bone("thumb_0%d_%s" % [joint, s]))
	if bones.has(-1):
		return
	var turn: Vector3 = along * (1.0 if left_hand else -1.0)
	var bend: Vector3 = across.cross(palm).normalized() * (1.0 if left_hand else -1.0)
	for _pass: int in CURL_PASSES:
		var off: Vector3 = _tip(rig, bones[2]) - centre
		off -= across * off.dot(across)
		if off.length() <= handle_radius + FINGER_SKIN_M:
			break
		var root: Transform3D = rig.get_bone_global_pose(bones[0])
		root.basis = Basis(turn, CURL_STEP * 0.6 * w) * root.basis
		rig.set_bone_global_pose(bones[0], root)
		for k: int in range(1, 3):
			var pose: Transform3D = rig.get_bone_global_pose(bones[k])
			pose.basis = Basis(bend, CURL_STEP * 0.5 * w) * pose.basis
			rig.set_bone_global_pose(bones[k], pose)


## A finger's tip: its last bone's origin pushed on by that bone's length.
func _tip(rig: Skeleton3D, bone: int) -> Vector3:
	var pose: Transform3D = rig.get_bone_global_pose(bone)
	var parent: int = rig.get_bone_parent(bone)
	var length: float = rig.get_bone_rest(bone).origin.length() if parent >= 0 else 0.02
	return pose.origin + (pose.basis * Vector3.UP).normalized() * length
