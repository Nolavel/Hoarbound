class_name EmbodiedInteractionLabActor
extends CharacterBody3D

## Issue #198 replacement laboratory after the previous proof was rejected.
## Production pickup/inventory remain untouched.
##
## This lab deliberately separates five decisions that the rejected proof mixed:
## gaze target -> hand candidate -> collision-safe body placement -> bounded arm
## reach -> tactile finger contact. A grasp is accepted only if every gate passes.

enum Stage { PICKUP, HANDOFF, DONE }

const ITEM_RADIUS_M: float = 0.045
const ITEM_HALF_HEIGHT_M: float = 0.07
const SHELF_DEPTH_M: float = 0.38
const SHELF_Z_M: float = 0.28
const SHELF_FRONT_Z_M: float = SHELF_Z_M - SHELF_DEPTH_M * 0.5
const SHELF_HALF_THICKNESS_M: float = 0.025
const BODY_RADIUS_M: float = 0.35
const BODY_CLEARANCE_M: float = 0.12
const BODY_HAND_LATERAL_M: float = 0.18
const BODY_SPEED_MPS: float = 1.5
const BODY_ALIGN_TOLERANCE_M: float = 0.045
const BODY_TURN_RATE: float = 6.0
const FINGER_SURFACE_TOLERANCE_M: float = 0.018
const STAND_CAPSULE_HEIGHT: float = 2.0
const CROUCH_CAPSULE_HEIGHT: float = 1.30
const MAX_PREVIEW_SPEED: float = 1.5
const GAZE_ACCEPT_DEG: float = 7.0
const HANDOFF_SECONDS: float = 7.0
const HANDOFF_RECEIVER_BEGIN: float = 2.4
const HANDOFF_GRASP_END: float = 4.2
const HANDOFF_HOLD_END: float = 6.1
const HANDOFF_HEIGHT_M: float = 1.24
const HANDOFF_FORWARD_M: float = 0.34
const HANDOFF_SOURCE_SIDE_M: float = 0.10
const HANDOFF_VOLUME_RADIUS_M: float = 0.10

## Same physical can, five heights. Lateral placement alternates so the lab must
## actually choose a hand instead of succeeding with one hardcoded arm.
const PICKUP_CASES := [
	{"name": "HEAD", "height": 1.76, "x": 0.16, "stance": &"STAND", "duration": 4.2, "align_end": 0.9, "reach_end": 1.65, "grasp_end": 2.85, "hold_end": 3.7},
	{"name": "CHEST", "height": 1.42, "x": -0.16, "stance": &"STAND", "duration": 4.2, "align_end": 0.9, "reach_end": 1.65, "grasp_end": 2.85, "hold_end": 3.7},
	{"name": "WAIST", "height": 1.04, "x": 0.12, "stance": &"STAND", "duration": 4.2, "align_end": 0.9, "reach_end": 1.65, "grasp_end": 2.85, "hold_end": 3.7},
	{"name": "KNEE", "height": 0.66, "x": -0.15, "stance": &"CROUCH", "duration": 4.8, "align_end": 1.2, "reach_end": 2.0, "grasp_end": 3.25, "hold_end": 4.2},
	{"name": "FLOOR", "height": 0.18, "x": 0.16, "stance": &"KNEEL", "duration": 6.4, "align_end": 2.8, "reach_end": 3.55, "grasp_end": 4.85, "hold_end": 5.8},
]

@onready var visual: HenryUALAnimation = $HenryUALVisual
@onready var camera: TpsCamera = get_node("../PlayerCamera") as TpsCamera
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var stage_label: Label = get_node("../UILayer/Margin/VBox/Stage") as Label
@onready var detail_label: Label = get_node("../UILayer/Margin/VBox/Detail") as Label

var _elapsed: float = 0.0
var _stage: Stage = Stage.PICKUP
var _base_playback: AnimationNodeStateMachinePlayback
var _skeleton_missing := PackedStringArray()

var _pickup_root: Node3D
var _shelf_body: AnimatableBody3D
var _pickup_item: MeshInstance3D
var _left_reach: TactileArmReach
var _right_reach: TactileArmReach
var _left_grip: TactileHandGrip
var _right_grip: TactileHandGrip
var _left_socket: BoneAttachment3D
var _right_socket: BoneAttachment3D

var _pickup_case_index: int = -1
var _pickup_phase: StringName = &""
var _handoff_phase: StringName = &""
var _stance: StringName = &"STAND"
var _active_hand: StringName = &""
var _handoff_source_hand: StringName = &""
var _handoff_receiver_hand: StringName = &""
var _hand_locked: bool = false
var _body_goal: Vector3 = Vector3.ZERO
var _body_goal_yaw: float = 0.0
var _body_aligned: bool = false
var _body_error_m: float = INF
var _body_collision_seen: bool = false
var _focus_valid: bool = false
var _gaze_angle_deg: float = INF
var _candidate_report: Dictionary = {}
var _pickup_attached: bool = false
var _pickup_result_recorded: bool = false
var _pickup_results: Array[Dictionary] = []
var _pickup_contact_count: int = 0
var _pickup_finger_contacts: int = 0
var _pickup_thumb_contact: bool = false
var _pickup_surface_error: float = INF
var _pickup_per_finger: Dictionary = {}
var _work_pose_requested: bool = false
var _handoff_started: bool = false
var _handoff_transferred: bool = false
var _handoff_result: Dictionary = {}


func _ready() -> void:
	_skeleton_missing = HenrySkeletonContract.validate(visual.skeleton)
	if visual.animation_tree != null:
		_base_playback = visual.animation_tree.get("parameters/base/playback") as AnimationNodeStateMachinePlayback
	_build_rack()
	_build_hand_stack()
	_update_labels()
	print("[EmbodiedLabV2] skeleton=%s" % HenrySkeletonContract.describe(visual.skeleton))


func _physics_process(delta: float) -> void:
	_elapsed += delta
	var pickup_total: float = _pickup_total_duration()
	if _elapsed < pickup_total:
		_set_stage(Stage.PICKUP)
		var case_info: Dictionary = _case_at_time(_elapsed)
		var index: int = int(case_info["index"])
		if index != _pickup_case_index:
			_begin_pickup_case(index)
		_update_pickup_case(float(case_info["local_time"]), delta)
	elif _elapsed < pickup_total + HANDOFF_SECONDS:
		_set_stage(Stage.HANDOFF)
		_update_handoff(_elapsed - pickup_total, delta)
	else:
		_set_stage(Stage.DONE)
		_finish_sequence()
		velocity = Vector3.ZERO

	if visual != null:
		visual.update_animation_blend(delta)
		visual.update_head_look(delta)
	_update_labels()


func _set_stage(stage: Stage) -> void:
	if _stage == stage:
		return
	_stage = stage
	print("[EmbodiedLabV2] stage=%s" % _stage_name())


func _stage_name() -> String:
	match _stage:
		Stage.PICKUP:
			return "1 / CONTEXT GRASP — gaze → hand → body → arm → fingers"
		Stage.HANDOFF:
			return "2 / HANDOFF — shared transfer volume"
		_:
			return "3 / DONE — production pickup untouched"


func _pickup_total_duration() -> float:
	var total: float = 0.0
	for case_data: Dictionary in PICKUP_CASES:
		total += float(case_data["duration"])
	return total


func _case_at_time(local_time: float) -> Dictionary:
	var cursor: float = 0.0
	for i: int in range(PICKUP_CASES.size()):
		var duration: float = float(PICKUP_CASES[i]["duration"])
		if local_time < cursor + duration or i == PICKUP_CASES.size() - 1:
			return {"index": i, "local_time": local_time - cursor}
		cursor += duration
	return {"index": PICKUP_CASES.size() - 1, "local_time": 0.0}


func _begin_pickup_case(index: int) -> void:
	_restore_item_to_rack()
	_release_all_hands()
	if _work_pose_requested:
		visual.end_work_pose()
		_work_pose_requested = false
	visual.abort_action()

	_pickup_case_index = index
	_pickup_phase = &"SETUP"
	_active_hand = &""
	_hand_locked = false
	_body_aligned = false
	_body_error_m = INF
	_body_collision_seen = false
	_focus_valid = false
	_gaze_angle_deg = INF
	_candidate_report = {}
	_pickup_attached = false
	_pickup_result_recorded = false
	_reset_contact_metrics()

	var case_data: Dictionary = PICKUP_CASES[index]
	var height: float = float(case_data["height"])
	var x: float = float(case_data["x"])
	var shelf_y: float = maxf(SHELF_HALF_THICKNESS_M, height - ITEM_HALF_HEIGHT_M - SHELF_HALF_THICKNESS_M)
	_shelf_body.position = Vector3(0.0, shelf_y, SHELF_Z_M)
	_pickup_item.transform = Transform3D(Basis.IDENTITY, Vector3(x, height, SHELF_Z_M - 0.10))
	_set_stance(StringName(case_data["stance"]))
	print("[EmbodiedLabV2] case=%s h=%.2f x=%.2f stance=%s" % [case_data["name"], height, x, _stance])


func _update_pickup_case(case_time: float, delta: float) -> void:
	var case_data: Dictionary = PICKUP_CASES[_pickup_case_index]
	_aim_camera_at(_pickup_item.global_position)
	_update_focus_gate()

	if not _hand_locked:
		_select_hand_from_context()
		if case_time >= minf(0.35, float(case_data["align_end"]) * 0.45):
			_hand_locked = _active_hand != &""

	if _active_hand != &"":
		_body_goal = _body_goal_for_hand(_active_hand)
		_body_goal_yaw = 0.0

	if case_time < float(case_data["align_end"]):
		_pickup_phase = &"BODY_ALIGN"
		_move_body_toward_goal(delta)
		return

	velocity = Vector3.ZERO
	_body_error_m = Vector2(global_position.x - _body_goal.x, global_position.z - _body_goal.z).length()
	_body_aligned = _body_error_m <= BODY_ALIGN_TOLERANCE_M
	if not _body_aligned:
		_pickup_phase = &"BODY_BLOCKED"
		if case_time >= float(case_data["grasp_end"]):
			_record_pickup_result(false, "body_alignment_failed")
		return
	if not _focus_valid:
		_pickup_phase = &"GAZE_LOST"
		if case_time >= float(case_data["grasp_end"]):
			_record_pickup_result(false, "gaze_gate_failed")
		return

	var reach: TactileArmReach = _reach_for_hand(_active_hand)
	var grip: TactileHandGrip = _grip_for_hand(_active_hand)
	var palm_target: Vector3 = _palm_target_for_hand(_active_hand, _pickup_item.global_transform)
	reach.set_goal(palm_target, 1.0)
	if case_time < float(case_data["reach_end"]):
		_pickup_phase = &"ARM_REACH"
		grip.release()
		return

	var arm_debug: Dictionary = reach.get_debug()
	var arm_feasible: bool = bool(arm_debug.get("feasible", false))
	if not arm_feasible:
		_pickup_phase = &"ARM_REJECT"
		grip.release()
		if case_time >= float(case_data["grasp_end"]):
			_record_pickup_result(false, "arm_%s" % String(arm_debug.get("reason", "unknown")))
		return

	var close_t: float = clampf((case_time - float(case_data["reach_end"])) / maxf(0.01, float(case_data["grasp_end"]) - float(case_data["reach_end"])), 0.0, 1.0)
	close_t = close_t * close_t * (3.0 - 2.0 * close_t)
	grip.set_goal(_active_hand, _pickup_item.global_transform, ITEM_RADIUS_M, ITEM_HALF_HEIGHT_M, close_t)
	_update_tactile_metrics(grip)

	if not _pickup_attached and close_t >= 0.72 and _pickup_thumb_contact and _pickup_finger_contacts >= 2:
		_attach_item_to_hand(_active_hand)
		_record_pickup_result(true, "ok")

	if _pickup_attached:
		_pickup_phase = &"CONTACT"
		grip.set_goal(_active_hand, _pickup_item.global_transform, ITEM_RADIUS_M, ITEM_HALF_HEIGHT_M, 1.0)
	elif case_time < float(case_data["grasp_end"]):
		_pickup_phase = &"GRASP"
	else:
		_pickup_phase = &"MISS"
		_record_pickup_result(false, "tactile_contact_failed")

	if case_time >= float(case_data["hold_end"]) and _pickup_case_index < PICKUP_CASES.size() - 1:
		reach.release()
		grip.release()


func _select_hand_from_context() -> void:
	var candidates: Dictionary = {}
	var best_hand: StringName = &""
	var best_score: float = INF
	var item_pos: Vector3 = _pickup_item.global_position
	var lateral: float = global_transform.basis.x.normalized().dot(item_pos - global_position)
	for hand: StringName in [&"LEFT", &"RIGHT"]:
		var sign: float = -1.0 if hand == &"LEFT" else 1.0
		var side_ok: bool = true
		if absf(lateral) > 0.06:
			side_ok = lateral * sign > 0.0
		var hand_pos: Vector3 = _hand_world(hand)
		var hand_distance: float = hand_pos.distance_to(item_pos)
		var goal: Vector3 = _body_goal_for_hand(hand)
		var shoulder_est: Vector3 = _predicted_bone_world(hand, true, goal)
		var palm_target: Vector3 = _palm_target_from_shoulder(_pickup_item.global_transform, shoulder_est)
		var lengths: Vector2 = _arm_lengths(hand)
		var full_length: float = lengths.x + lengths.y
		var reach_ratio: float = shoulder_est.distance_to(palm_target) / maxf(full_length, 0.001)
		var reach_ok: bool = full_length > 0.1 and reach_ratio >= 0.28 and reach_ratio <= 0.95
		var score: float = hand_distance + absf(reach_ratio - 0.72) * 0.35
		if not side_ok:
			score += 10.0
		if not reach_ok:
			score += 10.0
		var reason: String = "ok"
		if not side_ok:
			reason = "cross_body"
		elif not reach_ok:
			reason = "reach_ratio"
		candidates[String(hand)] = {
			"feasible": side_ok and reach_ok,
			"reason": reason,
			"hand_distance_m": hand_distance,
			"predicted_reach_ratio": reach_ratio,
			"score": score,
			"body_goal": _vec3_array(goal),
		}
		if side_ok and reach_ok and score < best_score:
			best_score = score
			best_hand = hand
	_candidate_report = candidates
	_active_hand = best_hand


func _body_goal_for_hand(hand: StringName) -> Vector3:
	var sign: float = -1.0 if hand == &"LEFT" else 1.0
	var item_x: float = _pickup_item.global_position.x
	var z: float = SHELF_FRONT_Z_M - BODY_RADIUS_M - BODY_CLEARANCE_M
	return Vector3(item_x - sign * BODY_HAND_LATERAL_M, 0.0, z)


func _move_body_toward_goal(delta: float) -> void:
	if _active_hand == &"":
		velocity = Vector3.ZERO
		return
	var planar := Vector3(_body_goal.x - global_position.x, 0.0, _body_goal.z - global_position.z)
	var distance: float = planar.length()
	rotation.y = lerp_angle(rotation.y, _body_goal_yaw, clampf(delta * BODY_TURN_RATE, 0.0, 1.0))
	if distance <= BODY_ALIGN_TOLERANCE_M:
		velocity = Vector3.ZERO
		_body_aligned = true
		_body_error_m = distance
		return
	var speed: float = minf(BODY_SPEED_MPS, distance / maxf(delta, 0.001))
	velocity = planar.normalized() * speed
	move_and_slide()
	if get_slide_collision_count() > 0:
		_body_collision_seen = true
	_body_error_m = Vector2(global_position.x - _body_goal.x, global_position.z - _body_goal.z).length()
	_body_aligned = _body_error_m <= BODY_ALIGN_TOLERANCE_M


func _aim_camera_at(point: Vector3) -> void:
	if camera == null:
		return
	var eye: Vector3 = camera.get_eye_position()
	var forward: Vector3 = point - eye
	if forward.length_squared() < 0.0001:
		return
	forward = forward.normalized()
	var back: Vector3 = -forward
	var yaw: float = atan2(back.x, back.z)
	var pitch_deg: float = rad_to_deg(asin(clampf(forward.y, -1.0, 1.0)))
	camera.set_look(yaw, pitch_deg)


func _update_focus_gate() -> void:
	if camera == null:
		_focus_valid = false
		_gaze_angle_deg = INF
		return
	var from: Vector3 = TpsCamera.aim_origin(camera)
	var aim: Vector3 = TpsCamera.aim_direction(camera)
	var toward: Vector3 = _pickup_item.global_position - from
	if toward.length_squared() < 0.0001:
		_focus_valid = false
		_gaze_angle_deg = INF
		return
	_gaze_angle_deg = rad_to_deg(aim.angle_to(toward.normalized()))
	_focus_valid = toward.dot(aim) > 0.0 and _gaze_angle_deg <= GAZE_ACCEPT_DEG


func _palm_target_for_hand(hand: StringName, item_xf: Transform3D) -> Vector3:
	return _palm_target_from_shoulder(item_xf, _shoulder_world(hand))


func _palm_target_from_shoulder(item_xf: Transform3D, shoulder_world: Vector3) -> Vector3:
	var axis: Vector3 = item_xf.basis.y.normalized()
	var radial: Vector3 = shoulder_world - item_xf.origin
	radial -= axis * radial.dot(axis)
	if radial.length_squared() < 0.0001:
		radial = -global_transform.basis.z
	return item_xf.origin + radial.normalized() * (ITEM_RADIUS_M - 0.004)


func _predicted_bone_world(hand: StringName, shoulder: bool, body_goal: Vector3) -> Vector3:
	var suffix: String = "l" if hand == &"LEFT" else "r"
	var bone_name := StringName(("upperarm_" if shoulder else "hand_") + suffix)
	var idx: int = visual.skeleton.find_bone(bone_name)
	if idx < 0:
		return body_goal + Vector3((-0.22 if hand == &"LEFT" else 0.22), 1.40, 0.0)
	var world: Vector3 = visual.skeleton.global_transform * visual.skeleton.get_bone_global_pose(idx).origin
	var local: Vector3 = global_transform.affine_inverse() * world
	var candidate_xf := Transform3D(Basis(Vector3.UP, _body_goal_yaw), body_goal)
	return candidate_xf * local


func _arm_lengths(hand: StringName) -> Vector2:
	var suffix: String = "l" if hand == &"LEFT" else "r"
	var u: int = visual.skeleton.find_bone(StringName("upperarm_" + suffix))
	var l: int = visual.skeleton.find_bone(StringName("lowerarm_" + suffix))
	var h: int = visual.skeleton.find_bone(StringName("hand_" + suffix))
	if u < 0 or l < 0 or h < 0:
		return Vector2.ZERO
	var pu: Vector3 = visual.skeleton.get_bone_global_pose(u).origin
	var pl: Vector3 = visual.skeleton.get_bone_global_pose(l).origin
	var ph: Vector3 = visual.skeleton.get_bone_global_pose(h).origin
	return Vector2(pu.distance_to(pl), pl.distance_to(ph))


func _shoulder_world(hand: StringName) -> Vector3:
	var suffix: String = "l" if hand == &"LEFT" else "r"
	var idx: int = visual.skeleton.find_bone(StringName("upperarm_" + suffix))
	return global_position + Vector3.UP * 1.4 if idx < 0 else visual.skeleton.global_transform * visual.skeleton.get_bone_global_pose(idx).origin


func _hand_world(hand: StringName) -> Vector3:
	var suffix: String = "l" if hand == &"LEFT" else "r"
	var idx: int = visual.skeleton.find_bone(StringName("hand_" + suffix))
	return global_position if idx < 0 else visual.skeleton.global_transform * visual.skeleton.get_bone_global_pose(idx).origin


func _update_handoff(local_time: float, _delta: float) -> void:
	if not _handoff_started:
		_handoff_started = true
		_handoff_source_hand = _active_hand
		_handoff_receiver_hand = &"LEFT" if _handoff_source_hand == &"RIGHT" else &"RIGHT"
		if _work_pose_requested:
			visual.end_work_pose()
			_work_pose_requested = false
		_set_stance(&"STAND")
		print("[EmbodiedLabV2] handoff %s -> %s" % [String(_handoff_source_hand), String(_handoff_receiver_hand)])

	if not _pickup_attached or _handoff_source_hand == &"":
		_handoff_phase = &"SKIPPED_NO_SOURCE_GRIP"
		if _handoff_result.is_empty():
			_handoff_result = {"contact": false, "reason": "no_source_grip"}
		return

	var side_sign: float = -1.0 if _handoff_source_hand == &"LEFT" else 1.0
	var transfer_center: Vector3 = global_position + Vector3.UP * HANDOFF_HEIGHT_M
	transfer_center += global_transform.basis.z.normalized() * HANDOFF_FORWARD_M
	transfer_center += global_transform.basis.x.normalized() * HANDOFF_SOURCE_SIDE_M * side_sign
	_aim_camera_at(transfer_center)

	var source_reach: TactileArmReach = _reach_for_hand(_handoff_source_hand)
	var source_grip: TactileHandGrip = _grip_for_hand(_handoff_source_hand)
	var source_hand_pos: Vector3 = _hand_world(_handoff_source_hand)
	var source_target: Vector3 = source_hand_pos + (transfer_center - _pickup_item.global_position)
	source_reach.set_goal(source_target, 1.0)
	source_grip.set_goal(_handoff_source_hand, _pickup_item.global_transform, ITEM_RADIUS_M, ITEM_HALF_HEIGHT_M, 1.0)

	var transfer_error: float = _pickup_item.global_position.distance_to(transfer_center)
	if local_time < HANDOFF_RECEIVER_BEGIN:
		_handoff_phase = &"SOURCE_PRESENT"
		return

	var receiver_reach: TactileArmReach = _reach_for_hand(_handoff_receiver_hand)
	var receiver_grip: TactileHandGrip = _grip_for_hand(_handoff_receiver_hand)
	var receiver_target: Vector3 = _palm_target_for_hand(_handoff_receiver_hand, _pickup_item.global_transform)
	receiver_reach.set_goal(receiver_target, 1.0)
	var close_t: float = clampf((local_time - HANDOFF_RECEIVER_BEGIN) / maxf(0.01, HANDOFF_GRASP_END - HANDOFF_RECEIVER_BEGIN), 0.0, 1.0)
	close_t = close_t * close_t * (3.0 - 2.0 * close_t)
	receiver_grip.set_goal(_handoff_receiver_hand, _pickup_item.global_transform, ITEM_RADIUS_M, ITEM_HALF_HEIGHT_M, close_t)
	_update_tactile_metrics(receiver_grip)

	var source_ok: bool = bool(source_reach.get_debug().get("feasible", false))
	var receiver_ok: bool = bool(receiver_reach.get_debug().get("feasible", false))
	var volume_ok: bool = transfer_error <= HANDOFF_VOLUME_RADIUS_M
	if not _handoff_transferred and close_t >= 0.72 and source_ok and receiver_ok and volume_ok and _pickup_thumb_contact and _pickup_finger_contacts >= 2:
		_attach_item_to_hand(_handoff_receiver_hand)
		_handoff_transferred = true
		source_grip.release()
		source_reach.release()
		_handoff_phase = &"CONTACT"
		_handoff_result = {
			"contact": true,
			"reason": "ok",
			"source_hand": String(_handoff_source_hand),
			"receiver_hand": String(_handoff_receiver_hand),
			"transfer_volume_error_m": transfer_error,
			"source_arm": _arm_summary(source_reach.get_debug()),
			"receiver_arm": _arm_summary(receiver_reach.get_debug()),
			"contacts": _pickup_contact_count,
			"finger_contacts": _pickup_finger_contacts,
			"thumb_contact": _pickup_thumb_contact,
		}
		print("[EmbodiedHandoffV2] transferred %s->%s volume=%.3f contacts=%d" % [
			String(_handoff_source_hand), String(_handoff_receiver_hand), transfer_error, _pickup_contact_count])

	if _handoff_transferred:
		_handoff_phase = &"CONTACT"
		receiver_grip.set_goal(_handoff_receiver_hand, _pickup_item.global_transform, ITEM_RADIUS_M, ITEM_HALF_HEIGHT_M, 1.0)
	elif local_time < HANDOFF_GRASP_END:
		_handoff_phase = &"RECEIVER_REACH"
	else:
		_handoff_phase = &"MISS"
		if _handoff_result.is_empty():
			_handoff_result = {
				"contact": false,
				"reason": "handoff_gate_failed",
				"source_hand": String(_handoff_source_hand),
				"receiver_hand": String(_handoff_receiver_hand),
				"transfer_volume_error_m": transfer_error,
				"source_arm": _arm_summary(source_reach.get_debug()),
				"receiver_arm": _arm_summary(receiver_reach.get_debug()),
				"contacts": _pickup_contact_count,
				"finger_contacts": _pickup_finger_contacts,
				"thumb_contact": _pickup_thumb_contact,
			}

	if local_time >= HANDOFF_HOLD_END:
		receiver_reach.release()


func _build_rack() -> void:
	_pickup_root = Node3D.new()
	_pickup_root.name = "PickupContextRig"
	get_parent().add_child.call_deferred(_pickup_root)

	var rack_material := StandardMaterial3D.new()
	rack_material.albedo_color = Color(0.20, 0.23, 0.25)
	rack_material.roughness = 0.88

	_shelf_body = AnimatableBody3D.new()
	_shelf_body.name = "CollisionShelf"
	_pickup_root.add_child(_shelf_body)
	var shelf_mesh := BoxMesh.new()
	shelf_mesh.size = Vector3(1.35, SHELF_HALF_THICKNESS_M * 2.0, SHELF_DEPTH_M)
	shelf_mesh.material = rack_material
	var shelf_visual := MeshInstance3D.new()
	shelf_visual.mesh = shelf_mesh
	_shelf_body.add_child(shelf_visual)
	var shelf_shape := BoxShape3D.new()
	shelf_shape.size = shelf_mesh.size
	var shelf_collision := CollisionShape3D.new()
	shelf_collision.shape = shelf_shape
	_shelf_body.add_child(shelf_collision)

	for x: float in [-0.66, 0.66]:
		var post := StaticBody3D.new()
		post.position = Vector3(x, 1.05, 0.40)
		_pickup_root.add_child(post)
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.05, 2.10, 0.05)
		post_mesh.material = rack_material
		var post_visual := MeshInstance3D.new()
		post_visual.mesh = post_mesh
		post.add_child(post_visual)
		var post_shape := BoxShape3D.new()
		post_shape.size = post_mesh.size
		var post_collision := CollisionShape3D.new()
		post_collision.shape = post_shape
		post.add_child(post_collision)

	var can_mesh := CylinderMesh.new()
	can_mesh.top_radius = ITEM_RADIUS_M
	can_mesh.bottom_radius = ITEM_RADIUS_M
	can_mesh.height = ITEM_HALF_HEIGHT_M * 2.0
	can_mesh.radial_segments = 32
	var can_material := StandardMaterial3D.new()
	can_material.albedo_color = Color(0.88, 0.58, 0.14)
	can_material.metallic = 0.35
	can_material.roughness = 0.42
	can_mesh.material = can_material
	_pickup_item = MeshInstance3D.new()
	_pickup_item.name = "ContextTestTin"
	_pickup_item.mesh = can_mesh
	_pickup_root.add_child(_pickup_item)


func _build_hand_stack() -> void:
	_left_socket = visual.get_hand_socket()
	_right_socket = visual.get_offhand_socket()
	_left_reach = TactileArmReach.new()
	_left_reach.name = "TactileReachLeft"
	_left_reach.configure_hand(&"LEFT")
	visual.skeleton.add_child(_left_reach)
	_right_reach = TactileArmReach.new()
	_right_reach.name = "TactileReachRight"
	_right_reach.configure_hand(&"RIGHT")
	visual.skeleton.add_child(_right_reach)
	_left_grip = TactileHandGrip.new()
	_left_grip.name = "TactileGripLeft"
	visual.skeleton.add_child(_left_grip)
	_right_grip = TactileHandGrip.new()
	_right_grip.name = "TactileGripRight"
	visual.skeleton.add_child(_right_grip)


func _set_stance(stance: StringName) -> void:
	_stance = stance
	_set_capsule_height(CROUCH_CAPSULE_HEIGHT if stance != &"STAND" else STAND_CAPSULE_HEIGHT)
	if _base_playback != null:
		_base_playback.travel(&"Crouch" if stance == &"CROUCH" else &"Grounded")
	if stance == &"KNEEL":
		_work_pose_requested = visual.begin_work_pose()


func _set_capsule_height(height: float) -> void:
	var capsule := collision_shape.shape as CapsuleShape3D
	if capsule == null:
		return
	capsule.height = height
	collision_shape.position.y = height * 0.5


func _reach_for_hand(hand: StringName) -> TactileArmReach:
	return _left_reach if hand == &"LEFT" else _right_reach


func _grip_for_hand(hand: StringName) -> TactileHandGrip:
	return _left_grip if hand == &"LEFT" else _right_grip


func _socket_for_hand(hand: StringName) -> BoneAttachment3D:
	return _left_socket if hand == &"LEFT" else _right_socket


func _release_all_hands() -> void:
	if _left_reach != null:
		_left_reach.release()
	if _right_reach != null:
		_right_reach.release()
	if _left_grip != null:
		_left_grip.release()
	if _right_grip != null:
		_right_grip.release()


func _attach_item_to_hand(hand: StringName) -> void:
	var socket: BoneAttachment3D = _socket_for_hand(hand)
	if socket == null:
		return
	var world_xf: Transform3D = _pickup_item.global_transform
	_pickup_item.reparent(socket, true)
	_pickup_item.global_transform = world_xf
	_pickup_attached = true


func _restore_item_to_rack() -> void:
	if _pickup_item == null or _pickup_root == null:
		return
	if _pickup_item.get_parent() != _pickup_root:
		_pickup_item.reparent(_pickup_root, true)


func _update_tactile_metrics(grip: TactileHandGrip) -> void:
	_reset_contact_metrics()
	var errors := grip.get_contact_debug().get("errors_m", {}) as Dictionary
	for finger: String in ["index", "middle", "ring", "pinky", "thumb"]:
		if not errors.has(finger):
			continue
		var error: float = float(errors[finger])
		_pickup_per_finger[finger] = error
		_pickup_surface_error = minf(_pickup_surface_error, error)
		if error <= FINGER_SURFACE_TOLERANCE_M:
			_pickup_contact_count += 1
			if finger == "thumb":
				_pickup_thumb_contact = true
			else:
				_pickup_finger_contacts += 1


func _reset_contact_metrics() -> void:
	_pickup_contact_count = 0
	_pickup_finger_contacts = 0
	_pickup_thumb_contact = false
	_pickup_surface_error = INF
	_pickup_per_finger = {}


func _record_pickup_result(contact: bool, reason: String) -> void:
	if _pickup_result_recorded:
		return
	_pickup_result_recorded = true
	var case_data: Dictionary = PICKUP_CASES[_pickup_case_index]
	var reach: TactileArmReach = _reach_for_hand(_active_hand) if _active_hand != &"" else null
	var result := {
		"name": String(case_data["name"]),
		"height_m": float(case_data["height"]),
		"stance": String(case_data["stance"]),
		"chosen_hand": String(_active_hand),
		"hand_candidates": _candidate_report.duplicate(true),
		"contact": contact,
		"reason": reason,
		"gaze_focus": _focus_valid,
		"gaze_angle_deg": _gaze_angle_deg,
		"body_aligned": _body_aligned,
		"body_error_m": _body_error_m,
		"body_collision_seen": _body_collision_seen,
		"arm": _arm_summary(reach.get_debug()) if reach != null else {},
		"contacts": _pickup_contact_count,
		"finger_contacts": _pickup_finger_contacts,
		"thumb_contact": _pickup_thumb_contact,
		"best_tip_surface_error_m": _pickup_surface_error,
		"per_finger_error_m": _pickup_per_finger.duplicate(true),
	}
	_pickup_results.append(result)
	print("[EmbodiedContext] %s hand=%s contact=%s reason=%s body=%.3f gaze=%.2f arm=%s" % [
		case_data["name"], String(_active_hand), contact, reason, _body_error_m, _gaze_angle_deg,
		String(result["arm"].get("reason", "none"))])


func _arm_summary(debug: Dictionary) -> Dictionary:
	return {
		"feasible": bool(debug.get("feasible", false)),
		"reason": String(debug.get("reason", "none")),
		"reach_ratio": float(debug.get("reach_ratio", 0.0)),
		"weight": float(debug.get("weight", 0.0)),
	}


func _finish_sequence() -> void:
	_release_all_hands()
	if _work_pose_requested:
		visual.end_work_pose()
		_work_pose_requested = false


func _update_labels() -> void:
	if stage_label != null:
		stage_label.text = _stage_name()
	if detail_label == null:
		return
	if _stage == Stage.PICKUP:
		var case_name: String = "—"
		if _pickup_case_index >= 0:
			case_name = String(PICKUP_CASES[_pickup_case_index]["name"])
		detail_label.text = "%s  hand=%s  stance=%s  phase=%s\ngaze=%.1f° body_error=%.3fm collision=%s  contacts=%d (fingers=%d thumb=%s)" % [
			case_name, String(_active_hand), String(_stance), String(_pickup_phase), _gaze_angle_deg,
			_body_error_m, _body_collision_seen, _pickup_contact_count, _pickup_finger_contacts, _pickup_thumb_contact]
	elif _stage == Stage.HANDOFF:
		detail_label.text = "%s → %s  phase=%s  contacts=%d (fingers=%d thumb=%s)" % [
			String(_handoff_source_hand), String(_handoff_receiver_hand), String(_handoff_phase),
			_pickup_contact_count, _pickup_finger_contacts, _pickup_thumb_contact]
	else:
		detail_label.text = "lab complete"


func _vec3_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


## Minimal methods used by HenryUALAnimation / production TpsCamera.
func get_locomotion_speed_ratio() -> float:
	return clampf(Vector2(velocity.x, velocity.z).length() / MAX_PREVIEW_SPEED, 0.0, 1.0)


func get_crouch_speed_ratio() -> float:
	return 0.0


func is_crouching() -> bool:
	return _stance != &"STAND"


func get_view_direction() -> Vector3:
	return TpsCamera.aim_direction(camera) if camera != null else global_transform.basis.z.normalized()


func get_pickup_case_index() -> int:
	return _pickup_case_index


func get_pickup_phase() -> String:
	return String(_pickup_phase)


func get_handoff_phase() -> String:
	return String(_handoff_phase)


func get_capture_report() -> Dictionary:
	return {
		"stage": _stage_name(),
		"skeleton_missing": Array(_skeleton_missing),
		"skeleton_roles": HenrySkeletonContract.describe(visual.skeleton),
		"camera": "production TpsCamera; set_look only aims the gameplay view at each can target",
		"target_policy": "gaze target -> nearest feasible hand; alternating lateral can placements prove selection",
		"body_policy": "CharacterBody move_and_slide into stance/hand-specific body goal; shelf/posts are colliders",
		"arm_solver": "lab-only TactileArmReach; bounded two-bone reach, extension/compression gate, elbow midline gate",
		"finger_solver": "TactileHandGrip authored UAL prior + bounded cylinder settle",
		"contact_rule": "gaze + body aligned + arm feasible + thumb + >=2 non-thumb contacts",
		"pickup_results": _pickup_results,
		"handoff": _handoff_result,
		"production_movement_replaced": false,
		"production_item_pickup_replaced": false,
		"production_held_fit_changed": false,
	}
