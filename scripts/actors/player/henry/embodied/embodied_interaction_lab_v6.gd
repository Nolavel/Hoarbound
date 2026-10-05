class_name EmbodiedInteractionLabV6
extends EmbodiedInteractionLabV5

## Issue #198 pose-to-pose lab pass.
##
## V6 deliberately stops treating pickup as a robotics/contact-solver problem.
## The readable authored pose owns the action; runtime IK only corrects the wrist.
## Finger CCD and gaze remain diagnostics, never semantic success gates.
##
## Per height:
## target -> stance -> hand -> body align -> partial authored pose -> wrist IK ->
## authored cylindrical grip -> stand to Grounded idle -> present -> return.
## FLOOR ends as: pickup -> stand -> present -> receiver reaches -> ownership transfer.
## No full-body action clip is played and no root motion owns CharacterBody3D.

const V6_GRASP_COMMIT: float = 0.76
const V6_HANDOFF_COMMIT: float = 0.78
const V6_HAND_SIDE_PENALTY: float = 0.22
const V6_NEUTRAL_SIDE_M: float = 0.055
const V6_TRANSFER_RADIUS_M: float = 0.14


func _ready() -> void:
	super()
	## The grip modifier is used as an authored fist/cylindrical pose only. The old
	## per-finger CCD remains available for diagnostics, but does not touch V6 pose.
	for grip: TactileHandGrip in [_left_grip, _right_grip]:
		if grip == null:
			continue
		grip.hand_orient_weight = 0.0
		grip.contact_settle_weight = 0.0
	## Near-straight arms are valid; >100% extension is still impossible.
	for reach: TactileArmReach in [_left_reach, _right_reach]:
		if reach == null:
			continue
		reach.max_extension_ratio = 0.98
		reach.min_reach_ratio = 0.20
		reach.max_midline_cross_m = 0.055
	if _stance_pose != null:
		_stance_pose.pelvis_vertical_weight = 1.0
	print("[EmbodiedLabV6] pose_to_pose=true finger_ccd_gate=false gaze_gate=false full_action_playback=false")


func _stage_name() -> String:
	match _stage:
		Stage.PICKUP:
			return "1 / POSE-TO-POSE PICKUP — stance → reach → grip → idle present → return"
		Stage.HANDOFF:
			return "2 / HANDOFF — donor presents → receiver grip pose → ownership transfer"
		_:
			return "3 / DONE — authored pose + selective IK only"


func _select_hand_from_context() -> void:
	## Hand choice happens only after the requested stance is actually visible.
	## We use the loaded skeleton to infer which anatomical shoulder owns the side
	## of the target. Current fingertip position is only a small tie breaker.
	if not _stance_is_ready():
		_active_hand = &""
		_candidate_report = {}
		return

	var item_pos: Vector3 = _pickup_item.global_position
	var left_shoulder: Vector3 = _shoulder_world(&"LEFT")
	var right_shoulder: Vector3 = _shoulder_world(&"RIGHT")
	var shoulder_mid: Vector3 = (left_shoulder + right_shoulder) * 0.5
	var left_axis: Vector3 = left_shoulder - right_shoulder
	left_axis.y = 0.0
	if left_axis.length_squared() > 0.0001:
		left_axis = left_axis.normalized()
	else:
		left_axis = global_transform.basis.x.normalized()
	var target_side: float = (item_pos - shoulder_mid).dot(left_axis)
	var neutral_side: bool = absf(target_side) <= V6_NEUTRAL_SIDE_M

	var candidates: Dictionary = {}
	var best_hand: StringName = &""
	var best_score: float = INF
	for hand: StringName in [&"LEFT", &"RIGHT"]:
		var same_side: bool = neutral_side \
			or (target_side > 0.0 and hand == &"LEFT") \
			or (target_side < 0.0 and hand == &"RIGHT")
		var shoulder: Vector3 = left_shoulder if hand == &"LEFT" else right_shoulder
		var lateral_error: float = absf((item_pos - shoulder).dot(left_axis))
		var hand_distance: float = _hand_world(hand).distance_to(item_pos)
		var score: float = lateral_error + hand_distance * 0.08
		if not same_side:
			score += V6_HAND_SIDE_PENALTY
		var body_goal: Vector3 = _body_goal_for_hand(hand)
		candidates[String(hand)] = {
			"feasible": true,
			"reason": "stance_and_side",
			"same_side": same_side,
			"target_side_m": target_side,
			"lateral_error_m": lateral_error,
			"hand_distance_m": hand_distance,
			"body_goal": _vec3_array(body_goal),
			"body_yaw_deg": 0.0,
			"score": score,
		}
		if score < best_score:
			best_score = score
			best_hand = hand

	_candidate_report = candidates
	_active_hand = best_hand
	_chosen_body_yaw = 0.0
	print("[EmbodiedHandV6] case=%s stance=%s gaze=%.2f side=%.3f chosen=%s L=%s R=%s" % [
		String(PICKUP_CASES[_pickup_case_index]["name"]), String(_case_pickup_stance), _gaze_angle_deg,
		target_side, String(best_hand), str(candidates.get("LEFT", {})), str(candidates.get("RIGHT", {}))])


func _update_pickup_case_v3(case_time: float, delta: float) -> void:
	var timing: Dictionary = V5_CASES[_pickup_case_index]
	_aim_camera_at(_pickup_item.global_position)
	_update_focus_gate() # diagnostic only in V6

	if not _hand_locked:
		_select_hand_from_context()
		if _active_hand != &"":
			_hand_locked = true
	if _active_hand == &"":
		_cycle_phase = &"STANCE_SETTLE"
		_pickup_phase = &"STANCE_SETTLE"
		velocity = Vector3.ZERO
		if case_time >= float(timing["grasp_end"]):
			_record_pickup_result(false, "stance_or_hand_selection_failed")
		return

	_body_goal = _body_goal_for_hand(_active_hand)
	_body_goal_yaw = 0.0
	var align_end: float = float(timing["align_end"])
	if case_time < align_end or not _body_aligned:
		_cycle_phase = &"BODY_ALIGN"
		_pickup_phase = &"BODY_ALIGN"
		_move_body_toward_goal(delta)
		if case_time > align_end + 0.85 and not _body_aligned:
			_record_pickup_result(false, "body_alignment_failed")
		return

	velocity = Vector3.ZERO
	_body_error_m = Vector2(global_position.x - _body_goal.x, global_position.z - _body_goal.z).length()
	_body_aligned = _body_error_m <= BODY_ALIGN_TOLERANCE_M

	var reach: TactileArmReach = _reach_for_hand(_active_hand)
	var grip: TactileHandGrip = _grip_for_hand(_active_hand)
	var profile: StringName = &"LOW" if _case_pickup_stance != &"STAND" else &"PICKUP"
	var reach_end: float = float(timing["reach_end"])
	var grasp_end: float = float(timing["grasp_end"])
	var rise_end: float = float(timing["rise_end"])
	var present_end: float = float(timing["present_end"])
	var return_stance_end: float = float(timing["return_stance_end"])
	var return_end: float = float(timing["return_end"])
	var release_end: float = float(timing["release_end"])

	if not _pickup_attached:
		_cycle_phase = &"AUTHORED_REACH"
		var pose_phase: float = clampf(inverse_lerp(align_end, grasp_end, case_time), 0.0, 1.0)
		var pose_weight: float = 0.70 if profile == &"PICKUP" else 0.66
		_reach_pose.set_pose(_active_hand, profile, pose_phase, pose_weight)
		reach.set_goal(_palm_target_for_hand(_active_hand, _rack_item_world), 1.0)
		if case_time < reach_end:
			_pickup_phase = &"POSE_REACH"
			grip.release()
			return

		var arm_debug: Dictionary = reach.get_debug()
		var arm_ok: bool = bool(arm_debug.get("feasible", false))
		var close_t: float = clampf(inverse_lerp(reach_end, grasp_end, case_time), 0.0, 1.0)
		close_t = close_t * close_t * (3.0 - 2.0 * close_t)
		grip.set_goal(_active_hand, _pickup_item.global_transform, ITEM_RADIUS_M, ITEM_HALF_HEIGHT_M, close_t)
		_pickup_phase = &"GRIP_POSE" if arm_ok else &"WRIST_SETTLE"

		if arm_ok and close_t >= V6_GRASP_COMMIT:
			_attach_item_to_hand(_active_hand)
			_record_pickup_result(true, "authored_grip_pose")
			_mark_cycle("grasped", true)
			_cycle_phase = &"GRASP"
			_pickup_phase = &"CONTACT"
			print("[EmbodiedCycleV6] %s hand=%s GRASP arm_ratio=%.3f gaze_diag=%.2f" % [
				String(PICKUP_CASES[_pickup_case_index]["name"]), String(_active_hand),
				float(arm_debug.get("reach_ratio", 0.0)), _gaze_angle_deg])
			return
		if case_time >= grasp_end:
			_record_pickup_result(false, "wrist_%s" % String(arm_debug.get("reason", "not_settled")))
		return

	## Ownership is deterministic once the authored grip commits. From here the
	## object follows the hand socket; IK only poses the arm for presentation.
	grip.set_goal(_active_hand, _pickup_item.global_transform, ITEM_RADIUS_M, ITEM_HALF_HEIGHT_M, 1.0)
	_reach_pose.release()
	if _stance != &"STAND":
		_set_stance(&"STAND")
	if case_time < rise_end:
		_cycle_phase = &"RISE_TO_IDLE"
		_pickup_phase = &"RISE_TO_IDLE"
		_move_owned_item_with_hand(reach, _present_item_center(_active_hand))
		return

	_mark_cycle("stood_to_idle", true)
	if case_time < present_end:
		_cycle_phase = &"IDLE_PRESENT"
		_pickup_phase = &"IDLE_PRESENT"
		_move_owned_item_with_hand(reach, _present_item_center(_active_hand))
		_mark_cycle("idle_presented", true)
		return

	if _pickup_case_index == PICKUP_CASES.size() - 1:
		_cycle_phase = &"FINAL_IDLE_HOLD"
		_pickup_phase = &"FINAL_IDLE_HOLD"
		_move_owned_item_with_hand(reach, _present_item_center(_active_hand))
		_mark_cycle("idle_presented", true)
		return

	if _stance != _case_pickup_stance:
		_set_stance(_case_pickup_stance)
	if case_time < return_stance_end or not _stance_is_ready():
		_cycle_phase = &"RETURN_STANCE"
		_pickup_phase = &"RETURN_STANCE"
		_move_owned_item_with_hand(reach, _present_item_center(_active_hand))
		return

	if case_time < return_end:
		_cycle_phase = &"RETURN_TO_OBJECT_POSE"
		_pickup_phase = &"RETURN_TO_SHELF"
		_reach_pose.set_pose(_active_hand, profile, 0.72, 0.42)
		_move_owned_item_with_hand(reach, _rack_item_world.origin)
		return

	if not _returned_to_shelf:
		_place_item_back_on_shelf()
		_returned_to_shelf = true
		_mark_cycle("returned", true)
		print("[EmbodiedCycleV6] %s hand=%s RETURN" % [
			String(PICKUP_CASES[_pickup_case_index]["name"]), String(_active_hand)])
	if case_time < release_end:
		_cycle_phase = &"RELEASE"
		_pickup_phase = &"RELEASE"
		reach.release()
		grip.release()
		_reach_pose.release()
		_mark_cycle("released", true)
	else:
		if _stance != &"STAND":
			_set_stance(&"STAND")
		_pickup_phase = &"RESET"


func _update_handoff_v3(local_time: float) -> void:
	if not _handoff_started:
		_handoff_started = true
		_handoff_source_hand = _active_hand
		_handoff_receiver_hand = &"LEFT" if _handoff_source_hand == &"RIGHT" else &"RIGHT"
		_set_stance(&"STAND")
		_reach_pose.release()
		print("[EmbodiedHandoffV6] begin %s -> %s" % [String(_handoff_source_hand), String(_handoff_receiver_hand)])
	if not _pickup_attached or _handoff_source_hand == &"":
		_handoff_phase = &"SKIPPED_NO_SOURCE_GRIP"
		if _handoff_result.is_empty():
			_handoff_result = {"contact": false, "reason": "no_source_grip"}
		return

	var transfer_center: Vector3 = global_position + Vector3.UP * V5_TRANSFER_HEIGHT_M
	transfer_center += global_transform.basis.z.normalized() * V5_TRANSFER_FORWARD_M
	_aim_camera_at(transfer_center)

	var source_reach: TactileArmReach = _reach_for_hand(_handoff_source_hand)
	var source_grip: TactileHandGrip = _grip_for_hand(_handoff_source_hand)
	_active_hand = _handoff_source_hand
	_move_owned_item_with_hand(source_reach, transfer_center)
	source_grip.set_goal(_handoff_source_hand, _pickup_item.global_transform, ITEM_RADIUS_M, ITEM_HALF_HEIGHT_M, 1.0)
	if local_time < V5_HANDOFF_RECEIVER_BEGIN:
		_handoff_phase = &"SOURCE_PRESENT"
		return

	var receiver_reach: TactileArmReach = _reach_for_hand(_handoff_receiver_hand)
	var receiver_grip: TactileHandGrip = _grip_for_hand(_handoff_receiver_hand)
	receiver_reach.set_goal(_palm_target_for_hand(_handoff_receiver_hand, _pickup_item.global_transform), 1.0)
	var close_t: float = clampf(inverse_lerp(V5_HANDOFF_RECEIVER_BEGIN, V5_HANDOFF_GRASP_END, local_time), 0.0, 1.0)
	close_t = close_t * close_t * (3.0 - 2.0 * close_t)
	receiver_grip.set_goal(_handoff_receiver_hand, _pickup_item.global_transform, ITEM_RADIUS_M, ITEM_HALF_HEIGHT_M, close_t)

	var source_debug: Dictionary = source_reach.get_debug()
	var receiver_debug: Dictionary = receiver_reach.get_debug()
	var receiver_ok: bool = bool(receiver_debug.get("feasible", false))
	var volume_error: float = _pickup_item.global_position.distance_to(transfer_center)
	if not _handoff_transferred and close_t >= V6_HANDOFF_COMMIT and receiver_ok \
			and volume_error <= V6_TRANSFER_RADIUS_M:
		_attach_item_to_hand(_handoff_receiver_hand)
		_handoff_transferred = true
		_handoff_transfer_time = local_time
		source_reach.release()
		source_grip.release()
		_handoff_result = {
			"contact": true,
			"reason": "authored_receiver_grip_pose",
			"source_hand": String(_handoff_source_hand),
			"receiver_hand": String(_handoff_receiver_hand),
			"transfer_volume_error_m": volume_error,
			"source_arm": _arm_summary(source_debug),
			"receiver_arm": _arm_summary(receiver_debug),
			"finger_ccd_required": false,
		}
		print("[EmbodiedHandoffV6] TRANSFER %s -> %s volume=%.3f receiver_ratio=%.3f" % [
			String(_handoff_source_hand), String(_handoff_receiver_hand), volume_error,
			float(receiver_debug.get("reach_ratio", 0.0))])

	if _handoff_transferred:
		_handoff_phase = &"CONTACT"
		_active_hand = _handoff_receiver_hand
		receiver_grip.set_goal(_handoff_receiver_hand, _pickup_item.global_transform, ITEM_RADIUS_M, ITEM_HALF_HEIGHT_M, 1.0)
		_move_owned_item_with_hand(receiver_reach, _present_item_center(_handoff_receiver_hand))
	elif local_time < V5_HANDOFF_GRASP_END:
		_handoff_phase = &"RECEIVER_GRIP_POSE"
	else:
		_handoff_phase = &"MISS"
		if _handoff_result.is_empty():
			_handoff_result = {
				"contact": false,
				"reason": "receiver_wrist_or_transfer_volume_failed",
				"source_hand": String(_handoff_source_hand),
				"receiver_hand": String(_handoff_receiver_hand),
				"transfer_volume_error_m": volume_error,
				"source_arm": _arm_summary(source_debug),
				"receiver_arm": _arm_summary(receiver_debug),
			}


func get_capture_report() -> Dictionary:
	var report: Dictionary = super()
	report["lab_revision"] = "V6 pose-to-pose authored interaction; wrist IK correction; authored grip pose; no fingertip/gaze semantic gates"
	report["motion_policy"] = "base locomotion remains authoritative; static/partial UAL samples only; no full action playback and no root-motion ownership"
	report["hand_selection_policy"] = "after stance settles, infer target side from measured shoulders; ipsilateral preference; current hand distance only tie-breaker"
	report["grip_policy"] = "Idle_Torch authored fist/cylindrical prior; finger CCD and fingertip contact are diagnostic only"
	report["success_gate"] = "stance + collision-safe body alignment + bounded wrist reach + authored grip commit + deterministic ownership"
	report["gaze_policy"] = "production TPS aims for readable staging; gaze angle is recorded but does not veto an otherwise valid authored interaction"
	report["finger_ccd_required"] = false
	return report
