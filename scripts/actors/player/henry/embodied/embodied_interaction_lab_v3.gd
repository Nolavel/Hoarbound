class_name EmbodiedInteractionLabV3
extends EmbodiedInteractionLabActor

## Issue #198 tactile grasp lab, third pass.
##
## Rejected V1/V2 lessons are explicit here:
## - no full-body pickup/fixing action playback;
## - gaze identifies the object, then the nearer/side-appropriate hand is chosen;
## - body approach is collision-authoritative CharacterBody motion;
## - a short authored UAL upper-body window is only a pose prior;
## - arm IK is bounded and cannot stretch/cross the torso;
## - each can cycle is grasp -> chest -> shelf return;
## - the final low pickup becomes a true two-hand ownership transfer.

const V3_CASES := [
	{"duration": 4.7, "align_end": 1.25, "reach_end": 1.85, "grasp_end": 2.55, "chest_end": 3.20, "return_end": 4.05, "release_end": 4.45},
	{"duration": 4.3, "align_end": 0.75, "reach_end": 1.35, "grasp_end": 2.05, "chest_end": 2.70, "return_end": 3.55, "release_end": 4.10},
	{"duration": 4.3, "align_end": 0.75, "reach_end": 1.35, "grasp_end": 2.05, "chest_end": 2.70, "return_end": 3.55, "release_end": 4.10},
	{"duration": 4.5, "align_end": 0.85, "reach_end": 1.55, "grasp_end": 2.30, "chest_end": 3.00, "return_end": 3.75, "release_end": 4.30},
	{"duration": 4.8, "align_end": 0.95, "reach_end": 1.75, "grasp_end": 2.55, "chest_end": 3.55, "return_end": 4.80, "release_end": 4.80},
]
const V3_HANDOFF_SECONDS: float = 5.0
const V3_HANDOFF_RECEIVER_BEGIN: float = 1.15
const V3_HANDOFF_GRASP_END: float = 2.75
const V3_HANDOFF_HOLD_END: float = 4.55
const CHEST_HEIGHT_STAND_M: float = 1.28
const CHEST_HEIGHT_CROUCH_M: float = 0.94
const CHEST_FORWARD_M: float = 0.28
const CHEST_SIDE_M: float = 0.11
const TRANSFER_FORWARD_M: float = 0.30
const TRANSFER_HEIGHT_M: float = 1.22
const TRANSFER_SOURCE_SIDE_M: float = 0.055
const TRANSFER_RADIUS_M: float = 0.12

var _reach_pose: TactileReachPose
var _rack_item_world := Transform3D.IDENTITY
var _returned_to_shelf: bool = false
var _cycle_phase: StringName = &""


func _ready() -> void:
	super()
	_reach_pose = TactileReachPose.new()
	_reach_pose.name = "TactileReachPose"
	visual.skeleton.add_child(_reach_pose)
	## Authored pose prior must run before arm reach and fingertip settlement.
	if _left_reach != null:
		visual.skeleton.move_child(_reach_pose, _left_reach.get_index())
	print("[EmbodiedLabV3] partial_animation=true cycle=grasp->chest->return final=handoff")


func _physics_process(delta: float) -> void:
	_elapsed += delta
	var pickup_total: float = _pickup_total_duration_v3()
	if _elapsed < pickup_total:
		_set_stage(Stage.PICKUP)
		var info: Dictionary = _case_at_time_v3(_elapsed)
		var index: int = int(info["index"])
		if index != _pickup_case_index:
			_begin_pickup_case(index)
		_update_pickup_case_v3(float(info["local_time"]), delta)
	elif _elapsed < pickup_total + V3_HANDOFF_SECONDS:
		_set_stage(Stage.HANDOFF)
		_update_handoff_v3(_elapsed - pickup_total)
	else:
		_set_stage(Stage.DONE)
		_finish_sequence_v3()
		velocity = Vector3.ZERO

	if visual != null:
		visual.update_animation_blend(delta)
		visual.update_head_look(delta)
	_update_labels()


func _stage_name() -> String:
	match _stage:
		Stage.PICKUP:
			return "1 / GRASP CYCLE — reach → grip → chest → shelf"
		Stage.HANDOFF:
			return "2 / HANDOFF — donor holds, receiver grips, ownership transfers"
		_:
			return "3 / DONE — lab-only stack"


func _pickup_total_duration_v3() -> float:
	var total: float = 0.0
	for data: Dictionary in V3_CASES:
		total += float(data["duration"])
	return total


func _case_at_time_v3(local_time: float) -> Dictionary:
	var cursor: float = 0.0
	for i: int in range(V3_CASES.size()):
		var duration: float = float(V3_CASES[i]["duration"])
		if local_time < cursor + duration or i == V3_CASES.size() - 1:
			return {"index": i, "local_time": local_time - cursor}
		cursor += duration
	return {"index": V3_CASES.size() - 1, "local_time": 0.0}


func _begin_pickup_case(index: int) -> void:
	super(index)
	_rack_item_world = _pickup_item.global_transform
	_returned_to_shelf = false
	_cycle_phase = &"BODY_ALIGN"
	if _reach_pose != null:
		_reach_pose.release()
	print("[EmbodiedLabV3] case=%s authored_profile=%s" % [
		String(PICKUP_CASES[index]["name"]), "LOW" if index >= 3 else "PICKUP"])


func _set_stance(stance: StringName) -> void:
	## No full Fixing_Kneeling action. Low cases keep the production crouch base;
	## TactileReachPose samples only upper-body bones from Fixing_Kneeling.
	_stance = stance
	_set_capsule_height(CROUCH_CAPSULE_HEIGHT if stance != &"STAND" else STAND_CAPSULE_HEIGHT)
	if _base_playback != null:
		_base_playback.travel(&"Crouch" if stance != &"STAND" else &"Grounded")
	_work_pose_requested = false


func _select_hand_from_context() -> void:
	var item_pos: Vector3 = _pickup_item.global_position
	var lateral: float = global_transform.basis.x.normalized().dot(item_pos - global_position)
	var candidates: Dictionary = {}
	var best_hand: StringName = &""
	var best_score: float = INF
	for hand: StringName in [&"LEFT", &"RIGHT"]:
		var sign: float = -1.0 if hand == &"LEFT" else 1.0
		var distance: float = _hand_world(hand).distance_to(item_pos)
		var side_penalty: float = 0.0
		if absf(lateral) > 0.055 and lateral * sign < 0.0:
			side_penalty = 0.18
		var score: float = distance + side_penalty
		candidates[String(hand)] = {
			"hand_distance_m": distance,
			"target_lateral_m": lateral,
			"side_penalty_m": side_penalty,
			"score": score,
			"pre_reach_rejection": false,
		}
		if score < best_score:
			best_score = score
			best_hand = hand
	_candidate_report = candidates
	_active_hand = best_hand


func _update_pickup_case_v3(case_time: float, delta: float) -> void:
	var timing: Dictionary = V3_CASES[_pickup_case_index]
	_aim_camera_at(_pickup_item.global_position)
	_update_focus_gate()

	if not _hand_locked:
		_select_hand_from_context()
		if case_time >= 0.20:
			_hand_locked = _active_hand != &""
	if _active_hand == &"":
		_pickup_phase = &"NO_HAND"
		return

	_body_goal = _body_goal_for_hand(_active_hand)
	_body_goal_yaw = 0.0
	var align_end: float = float(timing["align_end"])
	if case_time < align_end or not _body_aligned:
		_cycle_phase = &"BODY_ALIGN"
		_pickup_phase = &"BODY_ALIGN"
		_move_body_toward_goal(delta)
		if case_time > align_end + 0.55 and not _body_aligned:
			_record_pickup_result(false, "body_alignment_failed")
		return

	velocity = Vector3.ZERO
	_body_error_m = Vector2(global_position.x - _body_goal.x, global_position.z - _body_goal.z).length()
	_body_aligned = _body_error_m <= BODY_ALIGN_TOLERANCE_M
	if not _focus_valid:
		_pickup_phase = &"GAZE_LOST"
		if case_time >= float(timing["grasp_end"]):
			_record_pickup_result(false, "gaze_gate_failed")
		return

	var reach: TactileArmReach = _reach_for_hand(_active_hand)
	var grip: TactileHandGrip = _grip_for_hand(_active_hand)
	var profile: StringName = &"LOW" if _pickup_case_index >= 3 else &"PICKUP"
	var reach_end: float = float(timing["reach_end"])
	var grasp_end: float = float(timing["grasp_end"])
	var chest_end: float = float(timing["chest_end"])
	var return_end: float = float(timing["return_end"])
	var release_end: float = float(timing["release_end"])

	if not _pickup_attached:
		_cycle_phase = &"REACH"
		var pose_phase: float = clampf(inverse_lerp(align_end, grasp_end, case_time), 0.0, 1.0)
		_reach_pose.set_pose(_active_hand, profile, pose_phase, 0.62 if profile == &"PICKUP" else 0.52)
		reach.set_goal(_palm_target_for_hand(_active_hand, _rack_item_world), 1.0)
		if case_time < reach_end:
			_pickup_phase = &"ARM_REACH"
			grip.release()
			return
		var arm_debug: Dictionary = reach.get_debug()
		if not bool(arm_debug.get("feasible", false)):
			_pickup_phase = &"ARM_REJECT"
			grip.release()
			if case_time >= grasp_end:
				_record_pickup_result(false, "arm_%s" % String(arm_debug.get("reason", "unknown")))
			return
		var close_t: float = clampf(inverse_lerp(reach_end, grasp_end, case_time), 0.0, 1.0)
		close_t = close_t * close_t * (3.0 - 2.0 * close_t)
		grip.set_goal(_active_hand, _pickup_item.global_transform, ITEM_RADIUS_M, ITEM_HALF_HEIGHT_M, close_t)
		_update_tactile_metrics(grip)
		if close_t >= 0.72 and _pickup_thumb_contact and _pickup_finger_contacts >= 2:
			_attach_item_to_hand(_active_hand)
			_record_pickup_result(true, "ok")
			_cycle_phase = &"GRASP"
			_pickup_phase = &"CONTACT"
			print("[EmbodiedCycleV3] %s hand=%s GRASP" % [String(PICKUP_CASES[_pickup_case_index]["name"]), String(_active_hand)])
			return
		_pickup_phase = &"GRASP"
		if case_time >= grasp_end:
			_record_pickup_result(false, "tactile_contact_failed")
		return

	## Once grasped, the cylinder stays rigidly owned by the active hand. The arm
	## moves the owned prop to chest and, except for the final case, back to shelf.
	grip.set_goal(_active_hand, _pickup_item.global_transform, ITEM_RADIUS_M, ITEM_HALF_HEIGHT_M, 1.0)
	if case_time < chest_end:
		_cycle_phase = &"BRING_TO_CHEST"
		_pickup_phase = &"BRING_TO_CHEST"
		_reach_pose.set_pose(_active_hand, profile, 0.72, 0.42)
		_move_owned_item_with_hand(reach, _chest_item_center(_active_hand))
		return

	if _pickup_case_index == PICKUP_CASES.size() - 1:
		_cycle_phase = &"CHEST_HOLD"
		_pickup_phase = &"CHEST_HOLD"
		_reach_pose.set_pose(_active_hand, profile, 0.68, 0.34)
		_move_owned_item_with_hand(reach, _chest_item_center(_active_hand))
		return

	if case_time < return_end:
		_cycle_phase = &"RETURN_TO_SHELF"
		_pickup_phase = &"RETURN_TO_SHELF"
		_reach_pose.set_pose(_active_hand, profile, clampf(inverse_lerp(return_end, chest_end, case_time), 0.0, 1.0), 0.34)
		_move_owned_item_with_hand(reach, _rack_item_world.origin)
		return

	if not _returned_to_shelf:
		var return_error: float = _pickup_item.global_position.distance_to(_rack_item_world.origin)
		_place_item_back_on_shelf()
		_returned_to_shelf = true
		print("[EmbodiedCycleV3] %s hand=%s RETURN error=%.3f" % [
			String(PICKUP_CASES[_pickup_case_index]["name"]), String(_active_hand), return_error])
	if case_time < release_end:
		_cycle_phase = &"RELEASE"
		_pickup_phase = &"RELEASE"
		reach.release()
		grip.release()
		_reach_pose.release()
	else:
		_pickup_phase = &"RESET"


func _chest_item_center(hand: StringName) -> Vector3:
	var sign: float = -1.0 if hand == &"LEFT" else 1.0
	var height: float = CHEST_HEIGHT_STAND_M if _stance == &"STAND" else CHEST_HEIGHT_CROUCH_M
	return global_position + Vector3.UP * height \
		+ global_transform.basis.z.normalized() * CHEST_FORWARD_M \
		+ global_transform.basis.x.normalized() * CHEST_SIDE_M * sign


func _move_owned_item_with_hand(reach: TactileArmReach, desired_item_center: Vector3) -> void:
	var hand_now: Vector3 = _hand_world(_active_hand)
	var delta: Vector3 = desired_item_center - _pickup_item.global_position
	reach.set_goal(hand_now + delta, 1.0)


func _place_item_back_on_shelf() -> void:
	if _pickup_item.get_parent() != _pickup_root:
		_pickup_item.reparent(_pickup_root, true)
	_pickup_item.global_transform = _rack_item_world
	_pickup_attached = false


func _update_handoff_v3(local_time: float) -> void:
	if not _handoff_started:
		_handoff_started = true
		_handoff_source_hand = _active_hand
		_handoff_receiver_hand = &"LEFT" if _handoff_source_hand == &"RIGHT" else &"RIGHT"
		_set_stance(&"STAND")
		print("[EmbodiedHandoffV3] begin %s -> %s" % [String(_handoff_source_hand), String(_handoff_receiver_hand)])
	if not _pickup_attached or _handoff_source_hand == &"":
		_handoff_phase = &"SKIPPED_NO_SOURCE_GRIP"
		if _handoff_result.is_empty():
			_handoff_result = {"contact": false, "reason": "no_source_grip"}
		return

	var source_sign: float = -1.0 if _handoff_source_hand == &"LEFT" else 1.0
	var transfer_center: Vector3 = global_position + Vector3.UP * TRANSFER_HEIGHT_M
	transfer_center += global_transform.basis.z.normalized() * TRANSFER_FORWARD_M
	transfer_center += global_transform.basis.x.normalized() * TRANSFER_SOURCE_SIDE_M * source_sign
	_aim_camera_at(transfer_center)

	var source_reach: TactileArmReach = _reach_for_hand(_handoff_source_hand)
	var source_grip: TactileHandGrip = _grip_for_hand(_handoff_source_hand)
	_active_hand = _handoff_source_hand
	_move_owned_item_with_hand(source_reach, transfer_center)
	source_grip.set_goal(_handoff_source_hand, _pickup_item.global_transform, ITEM_RADIUS_M, ITEM_HALF_HEIGHT_M, 1.0)
	if local_time < V3_HANDOFF_RECEIVER_BEGIN:
		_handoff_phase = &"SOURCE_PRESENT"
		_reach_pose.set_pose(_handoff_source_hand, &"PICKUP", 0.68, 0.28)
		return

	var receiver_reach: TactileArmReach = _reach_for_hand(_handoff_receiver_hand)
	var receiver_grip: TactileHandGrip = _grip_for_hand(_handoff_receiver_hand)
	_reach_pose.set_pose(_handoff_receiver_hand, &"PICKUP", 0.62, 0.52)
	receiver_reach.set_goal(_palm_target_for_hand(_handoff_receiver_hand, _pickup_item.global_transform), 1.0)
	var close_t: float = clampf(inverse_lerp(V3_HANDOFF_RECEIVER_BEGIN, V3_HANDOFF_GRASP_END, local_time), 0.0, 1.0)
	close_t = close_t * close_t * (3.0 - 2.0 * close_t)
	receiver_grip.set_goal(_handoff_receiver_hand, _pickup_item.global_transform, ITEM_RADIUS_M, ITEM_HALF_HEIGHT_M, close_t)
	_update_tactile_metrics(receiver_grip)

	var source_ok: bool = bool(source_reach.get_debug().get("feasible", false))
	var receiver_ok: bool = bool(receiver_reach.get_debug().get("feasible", false))
	var volume_error: float = _pickup_item.global_position.distance_to(transfer_center)
	if not _handoff_transferred and close_t >= 0.72 and source_ok and receiver_ok \
			and volume_error <= TRANSFER_RADIUS_M and _pickup_thumb_contact and _pickup_finger_contacts >= 2:
		_attach_item_to_hand(_handoff_receiver_hand)
		_handoff_transferred = true
		source_reach.release()
		source_grip.release()
		_handoff_phase = &"CONTACT"
		_handoff_result = {
			"contact": true,
			"reason": "ok",
			"source_hand": String(_handoff_source_hand),
			"receiver_hand": String(_handoff_receiver_hand),
			"transfer_volume_error_m": volume_error,
			"contacts": _pickup_contact_count,
			"finger_contacts": _pickup_finger_contacts,
			"thumb_contact": _pickup_thumb_contact,
		}
		print("[EmbodiedHandoffV3] TRANSFER %s -> %s volume=%.3f contacts=%d" % [
			String(_handoff_source_hand), String(_handoff_receiver_hand), volume_error, _pickup_contact_count])

	if _handoff_transferred:
		_handoff_phase = &"RECEIVER_HOLD"
		_active_hand = _handoff_receiver_hand
		receiver_grip.set_goal(_handoff_receiver_hand, _pickup_item.global_transform, ITEM_RADIUS_M, ITEM_HALF_HEIGHT_M, 1.0)
		_move_owned_item_with_hand(receiver_reach, _chest_item_center(_handoff_receiver_hand))
	elif local_time < V3_HANDOFF_GRASP_END:
		_handoff_phase = &"RECEIVER_GRASP"
	else:
		_handoff_phase = &"MISS"
		if _handoff_result.is_empty():
			_handoff_result = {
				"contact": false,
				"reason": "handoff_gate_failed",
				"source_hand": String(_handoff_source_hand),
				"receiver_hand": String(_handoff_receiver_hand),
				"transfer_volume_error_m": volume_error,
				"source_arm": _arm_summary(source_reach.get_debug()),
				"receiver_arm": _arm_summary(receiver_reach.get_debug()),
				"contacts": _pickup_contact_count,
				"finger_contacts": _pickup_finger_contacts,
				"thumb_contact": _pickup_thumb_contact,
			}
	if local_time >= V3_HANDOFF_HOLD_END and _handoff_transferred:
		_reach_pose.release()


func _release_all_hands() -> void:
	super()
	if _reach_pose != null:
		_reach_pose.release()


func _finish_sequence_v3() -> void:
	_release_all_hands()
	velocity = Vector3.ZERO


func get_capture_report() -> Dictionary:
	var report: Dictionary = super()
	report["lab_revision"] = "V3 rejected-proof replacement"
	report["animation_policy"] = "Grounded/Crouch base + partial UAL upper-body sample window only; no full PickUp_Table/Fixing_Kneeling playback"
	report["cycle_policy"] = "each non-final case: grasp -> bring to chest -> return to same shelf; final floor case -> chest -> opposite-hand transfer"
	report["hand_selection_policy"] = "gaze target first; nearest actual hand with target-side bias; no pre-approach reach rejection"
	report["handoff_volume_radius_m"] = TRANSFER_RADIUS_M
	return report
