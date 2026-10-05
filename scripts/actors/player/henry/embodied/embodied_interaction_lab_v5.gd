class_name EmbodiedInteractionLabV5
extends EmbodiedInteractionLabV4

## Issue #198 lab pass after owner rejection of the earlier proofs.
##
## V5 treats pickup as a whole-body decision, not a fingertip trick:
## camera target -> stance -> evaluate both hands at collision-safe body goals ->
## bounded arm reach -> cylindrical grasp -> stand into idle presentation -> return.
## The floor case ends with a shared-volume handoff. Full action clips are never
## played: locomotion owns the base, static/partial authored samples are pose priors.

const V5_CASES := [
	{"duration": 5.6, "align_end": 1.45, "reach_end": 2.15, "grasp_end": 3.00, "rise_end": 3.30, "present_end": 3.85, "return_stance_end": 4.05, "return_end": 4.85, "release_end": 5.25},
	{"duration": 5.0, "align_end": 0.70, "reach_end": 1.35, "grasp_end": 2.20, "rise_end": 2.50, "present_end": 3.05, "return_stance_end": 3.25, "return_end": 4.10, "release_end": 4.55},
	{"duration": 5.0, "align_end": 0.70, "reach_end": 1.35, "grasp_end": 2.20, "rise_end": 2.50, "present_end": 3.05, "return_stance_end": 3.25, "return_end": 4.10, "release_end": 4.55},
	{"duration": 5.8, "align_end": 0.85, "reach_end": 1.55, "grasp_end": 2.45, "rise_end": 3.05, "present_end": 3.65, "return_stance_end": 4.15, "return_end": 4.95, "release_end": 5.40},
	{"duration": 6.2, "align_end": 1.10, "reach_end": 1.95, "grasp_end": 2.95, "rise_end": 3.80, "present_end": 4.55, "return_stance_end": 4.55, "return_end": 5.80, "release_end": 5.95},
]

const V5_BODY_CLEARANCE_M: float = 0.018
const V5_ITEM_FRONT_Z_M: float = SHELF_FRONT_Z_M + 0.035
const V5_COMFORT_REACH_RATIO: float = 0.74
const V5_MIN_REACH_RATIO: float = 0.28
const V5_MAX_REACH_RATIO: float = 0.95
const V5_CONTRALATERAL_PENALTY: float = 0.28
const V5_BODY_YAW_DEG: float = 22.0
const V5_PRESENT_HEIGHT_M: float = 1.24
const V5_PRESENT_FORWARD_M: float = 0.30
const V5_PRESENT_SIDE_M: float = 0.055
const V5_TRANSFER_HEIGHT_M: float = 1.25
const V5_TRANSFER_FORWARD_M: float = 0.31
const V5_TRANSFER_RADIUS_M: float = 0.11
const V5_HANDOFF_RECEIVER_BEGIN: float = 1.00
const V5_HANDOFF_GRASP_END: float = 2.65

var _stance_pose: TactileStancePose
var _standing_foot_y: float = 0.0
var _standing_pelvis_y: float = 0.95
var _standing_shoulder_y: float = 1.45
var _case_pickup_stance: StringName = &"STAND"
var _chosen_body_yaw: float = 0.0
var _cycle_results: Dictionary = {}
var _handoff_transfer_time: float = -1.0


func _ready() -> void:
	super()
	_stance_pose = TactileStancePose.new()
	_stance_pose.name = "TactileStancePose"
	visual.skeleton.add_child(_stance_pose)
	if _reach_pose != null:
		visual.skeleton.move_child(_stance_pose, _reach_pose.get_index())
	_measure_standing_landmarks()
	print("[EmbodiedLabV5] stance-before-reach=true hand=biomechanical cycle=pickup->stand-idle->return final=handoff")


func _pickup_total_duration_v3() -> float:
	var total: float = 0.0
	for data: Dictionary in V5_CASES:
		total += float(data["duration"])
	return total


func _case_at_time_v3(local_time: float) -> Dictionary:
	var cursor: float = 0.0
	for i: int in range(V5_CASES.size()):
		var duration: float = float(V5_CASES[i]["duration"])
		if local_time < cursor + duration or i == V5_CASES.size() - 1:
			return {"index": i, "local_time": local_time - cursor}
		cursor += duration
	return {"index": V5_CASES.size() - 1, "local_time": 0.0}


func _begin_pickup_case(index: int) -> void:
	super(index)
	## Keep the cylinder near the front lip. Previous passes put it deep enough on
	## the shelf that Henry's capsule correctly stopped, then the arm was asked to
	## exceed its measured length. That was a bad test arrangement, not a reason to
	## stretch the arm.
	var item_xf: Transform3D = _pickup_item.global_transform
	item_xf.origin.z = V5_ITEM_FRONT_Z_M
	_pickup_item.global_transform = item_xf
	_rack_item_world = item_xf

	_case_pickup_stance = _choose_stance_for_height(float(PICKUP_CASES[index]["height"]))
	_set_stance(_case_pickup_stance)
	_chosen_body_yaw = 0.0
	var key: String = String(PICKUP_CASES[index]["name"])
	_cycle_results[key] = {
		"pickup_stance": String(_case_pickup_stance),
		"grasped": false,
		"stood_to_idle": false,
		"idle_presented": false,
		"returned": false,
		"released": false,
	}
	print("[EmbodiedCaseV5] %s h=%.2f stance=%s" % [
		key, float(PICKUP_CASES[index]["height"]), String(_case_pickup_stance)])


func _set_stance(stance: StringName) -> void:
	## Grounded/Crouch are normal locomotion states. KNEEL is Crouch plus a static
	## lower-body sample; no full Fixing_Kneeling action and no root motion.
	_stance = stance
	_set_capsule_height(CROUCH_CAPSULE_HEIGHT if stance != &"STAND" else STAND_CAPSULE_HEIGHT)
	if _base_playback != null:
		_base_playback.travel(&"Crouch" if stance != &"STAND" else &"Grounded")
	if _stance_pose != null:
		_stance_pose.set_stance(stance)
	_work_pose_requested = false


func _choose_stance_for_height(target_y: float) -> StringName:
	var leg_span: float = maxf(0.45, _standing_pelvis_y - _standing_foot_y)
	var kneel_limit: float = _standing_foot_y + leg_span * 0.46
	var crouch_limit: float = _standing_foot_y + leg_span * 0.86
	if target_y <= kneel_limit:
		return &"KNEEL"
	if target_y <= crouch_limit:
		return &"CROUCH"
	return &"STAND"


func _stance_is_ready() -> bool:
	if _stance != &"KNEEL" or _stance_pose == null:
		return true
	return _stance_pose.get_weight() >= 0.72


func _aim_camera_at(point: Vector3) -> void:
	if camera == null:
		return
	## Set the absolute control look from the currently rendered ray origin. Do not
	## integrate an error from a stale 10-fps render transform on every 60-Hz physics
	## tick: V4.1 did that and repeatedly overshot the target between render frames.
	var origin: Vector3 = TpsCamera.aim_origin(camera)
	var wanted: Vector3 = point - origin
	if wanted.length_squared() < 0.0001:
		return
	wanted = wanted.normalized()
	camera.set_look(
		atan2(-wanted.x, -wanted.z),
		rad_to_deg(asin(clampf(wanted.y, -1.0, 1.0)))
	)


func _select_hand_from_context() -> void:
	if not _focus_valid or not _stance_is_ready():
		_active_hand = &""
		_candidate_report = {}
		return

	var item_pos: Vector3 = _pickup_item.global_position
	var left_shoulder: Vector3 = _shoulder_world(&"LEFT")
	var right_shoulder: Vector3 = _shoulder_world(&"RIGHT")
	var shoulder_mid: Vector3 = (left_shoulder + right_shoulder) * 0.5
	var left_axis: Vector3 = left_shoulder - shoulder_mid
	left_axis.y = 0.0
	if left_axis.length_squared() > 0.0001:
		left_axis = left_axis.normalized()
	var target_side: float = (item_pos - shoulder_mid).dot(left_axis) if left_axis.length_squared() > 0.0001 else 0.0
	var neutral_side: bool = absf(target_side) <= 0.07

	var candidates: Dictionary = {}
	var best_hand: StringName = &""
	var best_score: float = INF
	var best_yaw: float = 0.0
	for hand: StringName in [&"LEFT", &"RIGHT"]:
		var same_side: bool = neutral_side or (target_side > 0.0 and hand == &"LEFT") or (target_side < 0.0 and hand == &"RIGHT")
		var body_goal: Vector3 = _body_goal_for_hand(hand)
		var body_yaw: float = _candidate_body_yaw(hand, body_goal)
		var shoulder_est: Vector3 = _predict_shoulder_at(hand, body_goal, body_yaw)
		var palm_target: Vector3 = _palm_target_from_shoulder(_pickup_item.global_transform, shoulder_est)
		var lengths: Vector2 = _arm_lengths(hand)
		var full_length: float = lengths.x + lengths.y
		var reach_ratio: float = shoulder_est.distance_to(palm_target) / maxf(full_length, 0.001)
		var reach_ok: bool = full_length > 0.1 and reach_ratio >= V5_MIN_REACH_RATIO and reach_ratio <= V5_MAX_REACH_RATIO
		var score: float = absf(reach_ratio - V5_COMFORT_REACH_RATIO)
		if not same_side:
			score += V5_CONTRALATERAL_PENALTY
		score += _hand_world(hand).distance_to(item_pos) * 0.035
		var reason: String = "ok"
		if not reach_ok:
			reason = "overreach" if reach_ratio > V5_MAX_REACH_RATIO else "overcompressed"
		candidates[String(hand)] = {
			"feasible": reach_ok,
			"reason": reason,
			"same_side": same_side,
			"target_side_m": target_side,
			"predicted_reach_ratio": reach_ratio,
			"hand_distance_m": _hand_world(hand).distance_to(item_pos),
			"body_goal": _vec3_array(body_goal),
			"body_yaw_deg": rad_to_deg(body_yaw),
			"score": score,
		}
		if reach_ok and score < best_score:
			best_score = score
			best_hand = hand
			best_yaw = body_yaw

	_candidate_report = candidates
	_active_hand = best_hand
	_chosen_body_yaw = best_yaw
	print("[EmbodiedHandV5] case=%s gaze=%.2f side=%.3f chosen=%s L=%s R=%s" % [
		String(PICKUP_CASES[_pickup_case_index]["name"]), _gaze_angle_deg, target_side, String(best_hand),
		str(candidates.get("LEFT", {})), str(candidates.get("RIGHT", {}))])


func _body_goal_for_hand(hand: StringName) -> Vector3:
	var shoulder: Vector3 = _shoulder_world(hand)
	var shoulder_offset_x: float = clampf(shoulder.x - global_position.x, -0.32, 0.32)
	var z: float = SHELF_FRONT_Z_M - BODY_RADIUS_M - V5_BODY_CLEARANCE_M
	return Vector3(_pickup_item.global_position.x - shoulder_offset_x * 0.94, 0.0, z)


func _candidate_body_yaw(hand: StringName, body_goal: Vector3) -> float:
	var signed: float = deg_to_rad(V5_BODY_YAW_DEG)
	var yaws: Array[float] = [0.0, signed, -signed]
	var best_yaw: float = 0.0
	var best_distance: float = INF
	for yaw: float in yaws:
		var shoulder: Vector3 = _predict_shoulder_at(hand, body_goal, yaw)
		var palm_target: Vector3 = _palm_target_from_shoulder(_pickup_item.global_transform, shoulder)
		var distance: float = shoulder.distance_to(palm_target)
		if distance < best_distance:
			best_distance = distance
			best_yaw = yaw
	return best_yaw


func _predict_shoulder_at(hand: StringName, body_goal: Vector3, body_yaw: float) -> Vector3:
	var suffix: String = "l" if hand == &"LEFT" else "r"
	var idx: int = visual.skeleton.find_bone(StringName("upperarm_" + suffix))
	if idx < 0:
		return body_goal + Vector3(-0.22 if hand == &"LEFT" else 0.22, 1.40, 0.0)
	var world: Vector3 = visual.skeleton.global_transform * visual.skeleton.get_bone_global_pose(idx).origin
	var local: Vector3 = global_transform.affine_inverse() * world
	return Transform3D(Basis(Vector3.UP, body_yaw), body_goal) * local


func _present_item_center(hand: StringName) -> Vector3:
	var side: Vector3 = _anatomical_side_axis(hand)
	return global_position + Vector3.UP * V5_PRESENT_HEIGHT_M \
		+ global_transform.basis.z.normalized() * V5_PRESENT_FORWARD_M \
		+ side * V5_PRESENT_SIDE_M


func _update_pickup_case_v3(case_time: float, delta: float) -> void:
	var timing: Dictionary = V5_CASES[_pickup_case_index]
	_aim_camera_at(_pickup_item.global_position)
	_update_focus_gate()

	if not _hand_locked:
		_select_hand_from_context()
		if _active_hand != &"":
			_hand_locked = true
	if _active_hand == &"":
		_cycle_phase = &"TARGET_ACQUIRE"
		_pickup_phase = &"TARGET_ACQUIRE"
		velocity = Vector3.ZERO
		if case_time >= float(timing["grasp_end"]):
			_record_pickup_result(false, "no_feasible_hand_or_gaze")
		return

	_body_goal = _body_goal_for_hand(_active_hand)
	_body_goal_yaw = _chosen_body_yaw
	var align_end: float = float(timing["align_end"])
	if case_time < align_end or not _body_aligned:
		_cycle_phase = &"BODY_ALIGN"
		_pickup_phase = &"BODY_ALIGN"
		_move_body_toward_goal(delta)
		if case_time > align_end + 0.75 and not _body_aligned:
			_record_pickup_result(false, "body_alignment_failed")
		return

	velocity = Vector3.ZERO
	_body_error_m = Vector2(global_position.x - _body_goal.x, global_position.z - _body_goal.z).length()
	_body_aligned = _body_error_m <= BODY_ALIGN_TOLERANCE_M
	if not _focus_valid:
		_pickup_phase = &"GAZE_SETTLE"
		if case_time >= float(timing["grasp_end"]):
			_record_pickup_result(false, "gaze_gate_failed")
		return

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
		_cycle_phase = &"REACH"
		var pose_phase: float = clampf(inverse_lerp(align_end, grasp_end, case_time), 0.0, 1.0)
		_reach_pose.set_pose(_active_hand, profile, pose_phase, 0.68 if profile == &"PICKUP" else 0.56)
		reach.set_goal(_palm_target_for_hand(_active_hand, _rack_item_world), 1.0)
		if case_time < reach_end:
			_pickup_phase = &"ARM_REACH"
			grip.release()
			return
		var arm_debug: Dictionary = reach.get_debug()
		if not bool(arm_debug.get("feasible", false)):
			_pickup_phase = &"ARM_SETTLE" if String(arm_debug.get("reason", "")) == "released" else &"ARM_REJECT"
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
			_mark_cycle("grasped", true)
			_cycle_phase = &"GRASP"
			_pickup_phase = &"CONTACT"
			return
		_pickup_phase = &"GRASP"
		if case_time >= grasp_end:
			_record_pickup_result(false, "tactile_contact_failed")
		return

	## Once the cylinder is owned, stop sampling pickup action poses. Henry returns
	## to normal Grounded idle while bounded arm IK holds the object in front of him.
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
		_cycle_phase = &"RETURN_TO_SHELF"
		_pickup_phase = &"RETURN_TO_SHELF"
		_reach_pose.set_pose(_active_hand, profile, 0.52, 0.34)
		_move_owned_item_with_hand(reach, _rack_item_world.origin)
		return

	if not _returned_to_shelf:
		_place_item_back_on_shelf()
		_returned_to_shelf = true
		_mark_cycle("returned", true)
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
		print("[EmbodiedHandoffV5] begin %s -> %s" % [String(_handoff_source_hand), String(_handoff_receiver_hand)])
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
	_update_tactile_metrics(receiver_grip)

	var source_debug: Dictionary = source_reach.get_debug()
	var receiver_debug: Dictionary = receiver_reach.get_debug()
	var source_ok: bool = bool(source_debug.get("feasible", false))
	var receiver_ok: bool = bool(receiver_debug.get("feasible", false))
	var volume_error: float = _pickup_item.global_position.distance_to(transfer_center)
	if not _handoff_transferred and close_t >= 0.72 and source_ok and receiver_ok \
			and volume_error <= V5_TRANSFER_RADIUS_M and _pickup_thumb_contact and _pickup_finger_contacts >= 2:
		_attach_item_to_hand(_handoff_receiver_hand)
		_handoff_transferred = true
		_handoff_transfer_time = local_time
		source_reach.release()
		source_grip.release()
		_handoff_result = {
			"contact": true,
			"reason": "ok",
			"source_hand": String(_handoff_source_hand),
			"receiver_hand": String(_handoff_receiver_hand),
			"transfer_volume_error_m": volume_error,
			"source_arm": _arm_summary(source_debug),
			"receiver_arm": _arm_summary(receiver_debug),
			"contacts": _pickup_contact_count,
			"finger_contacts": _pickup_finger_contacts,
			"thumb_contact": _pickup_thumb_contact,
		}
		print("[EmbodiedHandoffV5] TRANSFER %s -> %s volume=%.3f" % [
			String(_handoff_source_hand), String(_handoff_receiver_hand), volume_error])

	if _handoff_transferred:
		_handoff_phase = &"CONTACT"
		_active_hand = _handoff_receiver_hand
		receiver_grip.set_goal(_handoff_receiver_hand, _pickup_item.global_transform, ITEM_RADIUS_M, ITEM_HALF_HEIGHT_M, 1.0)
		_move_owned_item_with_hand(receiver_reach, _present_item_center(_handoff_receiver_hand))
	elif local_time < V5_HANDOFF_GRASP_END:
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
				"source_arm": _arm_summary(source_debug),
				"receiver_arm": _arm_summary(receiver_debug),
				"contacts": _pickup_contact_count,
				"finger_contacts": _pickup_finger_contacts,
				"thumb_contact": _pickup_thumb_contact,
			}


func _measure_standing_landmarks() -> void:
	var pelvis_idx: int = HenrySkeletonContract.resolve_bone(visual.skeleton, &"pelvis")
	var left_foot_idx: int = HenrySkeletonContract.resolve_bone(visual.skeleton, &"left_foot")
	var right_foot_idx: int = HenrySkeletonContract.resolve_bone(visual.skeleton, &"right_foot")
	if pelvis_idx >= 0:
		_standing_pelvis_y = (visual.skeleton.global_transform * visual.skeleton.get_bone_global_pose(pelvis_idx).origin).y
	var foot_sum: float = 0.0
	var foot_count: int = 0
	for idx: int in [left_foot_idx, right_foot_idx]:
		if idx >= 0:
			foot_sum += (visual.skeleton.global_transform * visual.skeleton.get_bone_global_pose(idx).origin).y
			foot_count += 1
	if foot_count > 0:
		_standing_foot_y = foot_sum / float(foot_count)
	_standing_shoulder_y = (_shoulder_world(&"LEFT").y + _shoulder_world(&"RIGHT").y) * 0.5
	print("[EmbodiedMetricsV5] foot=%.3f pelvis=%.3f shoulder=%.3f" % [
		_standing_foot_y, _standing_pelvis_y, _standing_shoulder_y])


func _mark_cycle(field: String, value: Variant) -> void:
	if _pickup_case_index < 0:
		return
	var key: String = String(PICKUP_CASES[_pickup_case_index]["name"])
	if not _cycle_results.has(key):
		_cycle_results[key] = {}
	var data: Dictionary = _cycle_results[key]
	data[field] = value
	_cycle_results[key] = data


func get_capture_report() -> Dictionary:
	var report: Dictionary = super()
	report["lab_revision"] = "V5 whole-body stance + biomechanical hand choice + idle presentation + semantic proof gate"
	report["camera_target_policy"] = "production TPS centre ray; absolute target solve from current ray origin, no stale-frame feedback integration"
	report["hand_selection_policy"] = "evaluate LEFT and RIGHT at collision-safe candidate body transforms; measured arm ratio + ipsilateral ergonomic preference; nearest-hand only tie-break weight"
	report["stance_policy"] = {
		"order": "target height -> stance -> hand candidates -> body alignment -> arm -> fingers",
		"standing_foot_y": _standing_foot_y,
		"standing_pelvis_y": _standing_pelvis_y,
		"standing_shoulder_y": _standing_shoulder_y,
		"kneel": "static Fixing_Kneeling lower-body sample at 2.6 s; no full action/root motion",
	}
	report["cycle_policy"] = "each height: contextual grasp -> stand -> Grounded idle presentation in front -> return/release; FLOOR -> stand -> opposite-hand shared-volume transfer"
	report["cycle_results"] = _cycle_results.duplicate(true)
	report["stance_debug"] = _stance_pose.get_debug() if _stance_pose != null else {}
	report["handoff_transfer_time"] = _handoff_transfer_time
	return report
