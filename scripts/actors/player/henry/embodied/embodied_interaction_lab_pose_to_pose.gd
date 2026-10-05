class_name EmbodiedInteractionLabPoseToPose
extends EmbodiedInteractionLabV6

## Concrete pose-to-pose lab driver for issue #198.
##
## Body alignment is allowed before hand commitment; target height selects an
## authored contact-pose profile before wrist IK. The final FLOOR case is staged
## on the actual floor in front of Henry, not on the rack's lowest shelf.
## Production movement / pickup are untouched.

const FLOOR_SURFACE_Y_M: float = 0.04
const FLOOR_FORWARD_FROM_BODY_M: float = 0.13


func _begin_pickup_case(index: int) -> void:
	super(index)
	if index != PICKUP_CASES.size() - 1:
		return
	## Previous lab revisions called this FLOOR while still placing the can on a
	## dynamically lowered rack shelf at y=0.18 and behind the shelf lip. That made
	## the arm solve a different problem. Put the cylinder on the actual floor,
	## slightly ahead of Henry between his reachable kneeling workspace.
	var floor_xf: Transform3D = _pickup_item.global_transform
	floor_xf.origin.x = float(PICKUP_CASES[index]["x"])
	floor_xf.origin.y = FLOOR_SURFACE_Y_M + ITEM_HALF_HEIGHT_M
	floor_xf.origin.z = global_position.z + FLOOR_FORWARD_FROM_BODY_M
	_pickup_item.global_transform = floor_xf
	_rack_item_world = floor_xf
	print("[EmbodiedFloorV6] actual_floor=true pos=%s body_z=%.3f" % [str(floor_xf.origin), global_position.z])


func _move_body_toward_goal(delta: float) -> void:
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


func _pose_profile_for_case() -> StringName:
	match _pickup_case_index:
		2:
			return &"TABLE"
		3, 4:
			return &"LOW"
		_:
			return &"PICKUP"


func _pose_weight(profile: StringName) -> float:
	match profile:
		&"TABLE":
			return 0.88
		&"LOW":
			return 0.90
		_:
			return 0.70


func _update_pickup_case_v3(case_time: float, delta: float) -> void:
	var timing: Dictionary = V5_CASES[_pickup_case_index]
	_aim_camera_at(_pickup_item.global_position)
	_update_focus_gate() # staging/diagnostic only

	var align_end: float = float(timing["align_end"])
	var reach_end: float = float(timing["reach_end"])
	var grasp_end: float = float(timing["grasp_end"])
	var rise_end: float = float(timing["rise_end"])
	var present_end: float = float(timing["present_end"])
	var return_stance_end: float = float(timing["return_stance_end"])
	var return_end: float = float(timing["return_end"])
	var release_end: float = float(timing["release_end"])

	if _returned_to_shelf:
		var returned_reach: TactileArmReach = _reach_for_hand(_active_hand) if _active_hand != &"" else null
		var returned_grip: TactileHandGrip = _grip_for_hand(_active_hand) if _active_hand != &"" else null
		if returned_reach != null:
			returned_reach.release()
		if returned_grip != null:
			returned_grip.release()
		_reach_pose.release()
		_mark_cycle("released", true)
		_cycle_phase = &"RELEASE"
		_pickup_phase = &"RELEASE" if case_time < release_end else &"RESET"
		if case_time >= release_end and _stance != &"STAND":
			_set_stance(&"STAND")
		velocity = Vector3.ZERO
		return

	_body_goal = _neutral_body_goal()
	_body_goal_yaw = 0.0
	if not _body_aligned:
		_cycle_phase = &"BODY_ALIGN"
		_pickup_phase = &"BODY_ALIGN"
		_move_body_toward_goal(delta)
		return
	velocity = Vector3.ZERO
	_body_error_m = Vector2(global_position.x - _body_goal.x, global_position.z - _body_goal.z).length()
	_body_aligned = _body_error_m <= BODY_ALIGN_TOLERANCE_M

	if not _hand_locked:
		_select_hand_from_context()
		if _active_hand != &"":
			_hand_locked = true
	if _active_hand == &"":
		_cycle_phase = &"HAND_SELECT"
		_pickup_phase = &"HAND_SELECT"
		if case_time >= grasp_end:
			_record_pickup_result(false, "hand_selection_failed")
		return

	var reach: TactileArmReach = _reach_for_hand(_active_hand)
	var grip: TactileHandGrip = _grip_for_hand(_active_hand)
	var profile: StringName = _pose_profile_for_case()

	if not _pickup_attached:
		_cycle_phase = &"AUTHORED_REACH"
		var pose_phase: float = clampf(inverse_lerp(align_end, grasp_end, case_time), 0.0, 1.0)
		_reach_pose.set_pose(_active_hand, profile, pose_phase, _pose_weight(profile))
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
			_record_pickup_result(true, "authored_%s_grip_pose" % String(profile).to_lower())
			_mark_cycle("grasped", true)
			_cycle_phase = &"GRASP"
			_pickup_phase = &"CONTACT"
			print("[EmbodiedCycleV6] %s profile=%s hand=%s GRASP arm_ratio=%.3f gaze_diag=%.2f" % [
				String(PICKUP_CASES[_pickup_case_index]["name"]), String(profile), String(_active_hand),
				float(arm_debug.get("reach_ratio", 0.0)), _gaze_angle_deg])
			return
		if case_time >= grasp_end:
			if not _pickup_result_recorded:
				print("[EmbodiedReachFailV6] %s profile=%s hand=%s reason=%s ratio=%.3f pose_weight=%.2f" % [
					String(PICKUP_CASES[_pickup_case_index]["name"]), String(profile), String(_active_hand),
					String(arm_debug.get("reason", "not_settled")), float(arm_debug.get("reach_ratio", 0.0)),
					_reach_pose.get_weight()])
				_record_pickup_result(false, "wrist_%s" % String(arm_debug.get("reason", "not_settled")))
			return

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
		_reach_pose.set_pose(_active_hand, profile, 0.72, _pose_weight(profile) * 0.62)
		_move_owned_item_with_hand(reach, _rack_item_world.origin)
		return

	_place_item_back_on_shelf()
	_returned_to_shelf = true
	_mark_cycle("returned", true)
	print("[EmbodiedCycleV6] %s profile=%s hand=%s RETURN" % [
		String(PICKUP_CASES[_pickup_case_index]["name"]), String(profile), String(_active_hand)])
