class_name EmbodiedInteractionLabV4
extends EmbodiedInteractionLabV3

## Camera/hand-context correction after #436.
##
## The gameplay gaze ray owns target choice. Hand choice then uses measured hand
## distance only; anatomical shoulder position is used for body alignment, never
## as a penalty that can override the nearer hand.

const TPS_AIM_CORRECTION_SHARE: float = 0.72
const V4_BODY_CLEARANCE_M: float = 0.04


func _aim_camera_at(point: Vector3) -> void:
	if camera == null:
		return
	## Closed-loop correction around the ACTUAL gameplay centre ray. Setting an
	## absolute yaw from the previous frame's shoulder-camera origin caused #437's
	## feedback drift as the production TPS boom moved during body approach.
	var origin: Vector3 = TpsCamera.aim_origin(camera)
	var current: Vector3 = TpsCamera.aim_direction(camera)
	var wanted: Vector3 = point - origin
	if wanted.length_squared() < 0.0001 or current.length_squared() < 0.0001:
		return
	current = current.normalized()
	wanted = wanted.normalized()
	var current_yaw: float = atan2(-current.x, -current.z)
	var wanted_yaw: float = atan2(-wanted.x, -wanted.z)
	var yaw_error: float = wrapf(wanted_yaw - current_yaw, -PI, PI)
	var current_pitch: float = asin(clampf(current.y, -1.0, 1.0))
	var wanted_pitch: float = asin(clampf(wanted.y, -1.0, 1.0))
	var pitch_error_deg: float = rad_to_deg(wanted_pitch - current_pitch)
	camera.set_look(
		camera.get_yaw() + yaw_error * TPS_AIM_CORRECTION_SHARE,
		camera.get_view_pitch_deg() + pitch_error_deg * TPS_AIM_CORRECTION_SHARE
	)


func _select_hand_from_context() -> void:
	## Context order matters: no valid centre-ray target -> no committed hand.
	if not _focus_valid:
		_active_hand = &""
		_candidate_report = {}
		return
	var item_pos: Vector3 = _pickup_item.global_position
	var left_distance: float = _hand_world(&"LEFT").distance_to(item_pos)
	var right_distance: float = _hand_world(&"RIGHT").distance_to(item_pos)
	_active_hand = &"LEFT" if left_distance <= right_distance else &"RIGHT"
	var shoulder_left: Vector3 = _shoulder_world(&"LEFT")
	var shoulder_right: Vector3 = _shoulder_world(&"RIGHT")
	var shoulder_mid: Vector3 = (shoulder_left + shoulder_right) * 0.5
	var left_axis: Vector3 = shoulder_left - shoulder_mid
	left_axis.y = 0.0
	if left_axis.length_squared() > 0.0001:
		left_axis = left_axis.normalized()
	var anatomical_side: float = (item_pos - shoulder_mid).dot(left_axis) if left_axis.length_squared() > 0.0001 else 0.0
	_candidate_report = {
		"LEFT": {
			"hand_distance_m": left_distance,
			"score": left_distance,
			"pre_reach_rejection": false,
			"anatomical_target_side": anatomical_side,
		},
		"RIGHT": {
			"hand_distance_m": right_distance,
			"score": right_distance,
			"pre_reach_rejection": false,
			"anatomical_target_side": anatomical_side,
		},
	}
	print("[EmbodiedHandV4] case=%s gaze=%.2f LEFT=%.3f RIGHT=%.3f chosen=%s" % [
		String(PICKUP_CASES[_pickup_case_index]["name"]), _gaze_angle_deg,
		left_distance, right_distance, String(_active_hand)])


func _body_goal_for_hand(hand: StringName) -> Vector3:
	## Put the chosen shoulder under the item using the measured skeleton, not a
	## hardcoded LEFT=-X / RIGHT=+X convention. The requested depth is intentionally
	## close to the shelf; move_and_slide() remains authoritative and will stop the
	## capsule before geometry. This gives the arm its natural reach instead of
	## compensating with stretch while still preserving body collision.
	var shoulder: Vector3 = _shoulder_world(hand)
	var shoulder_offset_x: float = clampf(shoulder.x - global_position.x, -0.30, 0.30)
	var z: float = SHELF_FRONT_Z_M - BODY_RADIUS_M - V4_BODY_CLEARANCE_M
	return Vector3(_pickup_item.global_position.x - shoulder_offset_x * 0.82, 0.0, z)


func _chest_item_center(hand: StringName) -> Vector3:
	var height: float = CHEST_HEIGHT_STAND_M if _stance == &"STAND" else CHEST_HEIGHT_CROUCH_M
	var side: Vector3 = _anatomical_side_axis(hand)
	return global_position + Vector3.UP * height \
		+ global_transform.basis.z.normalized() * CHEST_FORWARD_M \
		+ side * CHEST_SIDE_M


func _anatomical_side_axis(hand: StringName) -> Vector3:
	var left: Vector3 = _shoulder_world(&"LEFT")
	var right: Vector3 = _shoulder_world(&"RIGHT")
	var mid: Vector3 = (left + right) * 0.5
	var side: Vector3 = (_shoulder_world(hand) - mid)
	side.y = 0.0
	if side.length_squared() < 0.0001:
		return global_transform.basis.x.normalized() * (-1.0 if hand == &"LEFT" else 1.0)
	return side.normalized()


func get_capture_report() -> Dictionary:
	var report: Dictionary = super()
	report["lab_revision"] = "V4.1 closed-loop TPS aim + nearest-hand + partial-pose runtime fix"
	report["camera_target_policy"] = "production TpsCamera centre ray; damped closed-loop yaw/pitch correction; 7 degree gate unchanged"
	report["hand_selection_policy"] = "gaze must be valid first; choose minimum measured hand-to-can distance; no side penalty"
	report["body_alignment_policy"] = "chosen shoulder lateral offset measured from loaded UAL skeleton; close target remains collision-authoritative through move_and_slide"
	return report
