class_name TableInteractionContactTruthLab
extends TableInteractionSolverLab

## Issue #203 hardening layer for the table interaction proof.
##
## The previous lab could report contact at a timer even when the hand had not
## reached the can, then spawned a second held can while the original visual was
## still partly visible on the table. This subclass keeps the same interaction
## contract but makes the proof physically falsifiable:
## - contact is sampled from the post-modifier hand pose for several frames;
## - contact only passes inside the measured arm + hand-error limits;
## - the actual world visual is transferred to the hand socket (no duplicate);
## - far-edge alignment uses the same bounded post-F settle budget, but places
##   Henry close enough for the authored low-pickup action to have a real chance.
##
## LAB ONLY. Production Player, camera, InteractComponent and inventory ownership
## are untouched.

const CONTACT_ERROR_MAX_M: float = 0.10
const CONTACT_SAMPLE_FRAMES: int = 5
const FAR_FRONT_CLEARANCE_TRUTH_M: float = 0.38
const FAR_TARGET_LOCAL_X_M: float = 0.05

var _verify_serial: int = 0
var _world_visual_parent: Node
var _world_visual_home: Transform3D = Transform3D.IDENTITY
var _world_visual_transferred: bool = false


func prepare_case(case_name: StringName) -> void:
	_verify_serial += 1
	super.prepare_case(case_name)


func _update_solution() -> void:
	if current_case != &"FAR_EDGE" and current_case != &"OUT_OF_REACH":
		super._update_solution()
		return

	prompt_visible = false
	solution.clear()
	rejection.clear()
	if current_case == &"" or not is_instance_valid(item) or not is_instance_valid(visual):
		return
	if stage.get_stable_interact_target_id() != ITEM_ID:
		rejection = {"reason": "no_stable_item_focus"}
		return

	var contact := stage.get_item_focus_point(item)
	var item_local := stage.table.to_local(contact)
	var depth := clampf(TABLE_FRONT_Z_M - item_local.z, 0.0, TABLE_HALF_DEPTH_M * 2.0)

	## The far can is deliberately aligned slightly to Henry's right after the
	## settle. That lets the runtime hand chooser prefer the right low-pickup clip
	## instead of asking the left table clip to bridge an impossible reach.
	var desired_local_x := clampf(
		item_local.x - FAR_TARGET_LOCAL_X_M,
		-MAX_LATERAL_STANCE_M,
		MAX_LATERAL_STANCE_M
	)
	var desired_local := Vector3(
		desired_local_x,
		player.global_position.y - stage.table.global_position.y,
		TABLE_FRONT_Z_M + FAR_FRONT_CLEARANCE_TRUTH_M
	)
	var stance := stage.table.to_global(desired_local)
	stance.y = player.global_position.y
	var stance_yaw := _yaw_from(stance, contact)
	var settle_distance := Vector2(
		player.global_position.x - stance.x,
		player.global_position.z - stance.z
	).length()
	var settle_yaw_deg := absf(rad_to_deg(wrapf(
		stance_yaw - player.global_rotation.y,
		-PI,
		PI
	)))

	var left := _arm_candidate(&"LEFT", contact, stance, stance_yaw)
	var right := _arm_candidate(&"RIGHT", contact, stance, stance_yaw)
	var chosen: Dictionary = left if float(left["score"]) <= float(right["score"]) else right
	var hand := StringName(chosen["hand"])
	var action: StringName = &"pickup" if hand == &"LEFT" else &"pickup_right_low"

	var action_local := _point_local_to_pose(contact, stance, stance_yaw)
	var action_forward := -action_local.z
	var action_lateral := absf(action_local.x)
	var action_height := contact.y - stance.y
	var action_envelope_ok := (
		action_forward >= ACTION_MIN_FORWARD_M
		and action_forward <= ACTION_MAX_FORWARD_M
		and action_lateral <= ACTION_MAX_LATERAL_M
		and action_height >= ACTION_MIN_HEIGHT_FROM_ROOT_M
		and action_height <= ACTION_MAX_HEIGHT_FROM_ROOT_M
	)
	var stance_ok := settle_distance <= MAX_SETTLE_M and settle_yaw_deg <= MAX_SETTLE_YAW_DEG

	rejection = {
		"reason": "" if stance_ok and action_envelope_ok else ("stance_budget" if not stance_ok else "action_envelope"),
		"item_depth_m": depth,
		"stance_position": stance,
		"settle_distance_m": settle_distance,
		"settle_yaw_deg": settle_yaw_deg,
		"action_forward_m": action_forward,
		"action_lateral_m": action_lateral,
		"action_height_m": action_height,
		"target_local_x_after_settle_m": _point_local_to_pose(contact, stance, stance_yaw).x,
		"neutral_left": left,
		"neutral_right": right,
		"contact_truth_profile": "far_edge_bounded_settle",
	}
	if not stance_ok or not action_envelope_ok:
		return

	solution = {
		"stance_position": stance,
		"stance_yaw": stance_yaw,
		"settle_distance_m": settle_distance,
		"settle_yaw_deg": settle_yaw_deg,
		"item_depth_m": depth,
		"hand": String(hand),
		"action": String(action),
		"predicted_reach_ratio": float(chosen["reach_ratio"]),
		"predicted_distance_m": float(chosen["distance_m"]),
		"arm_length_m": float(chosen["arm_length_m"]),
		"action_forward_m": action_forward,
		"action_lateral_m": action_lateral,
		"action_height_m": action_height,
		"target_local_x_after_settle_m": _point_local_to_pose(contact, stance, stance_yaw).x,
		"neutral_left": left,
		"neutral_right": right,
		"contact_truth_profile": "far_edge_bounded_settle",
	}
	prompt_visible = true


func _record_contact(target: Vector3) -> void:
	_verify_serial += 1
	var ticket := _verify_serial
	var case_key := String(current_case)
	var hand := _active_hand
	_verify_contact_window(target, hand, case_key, ticket)


func _verify_contact_window(target: Vector3, hand: StringName, case_key: String, ticket: int) -> void:
	var best_error := INF
	var best_ratio := INF
	var best_frame := -1

	## TwoBoneIK3D is a SkeletonModifier3D. The modifier is applied after the lab's
	## process callback, so measuring in the same callback reads the old wrist pose.
	## Sample subsequent rendered poses instead of declaring contact at the timer.
	for frame: int in range(CONTACT_SAMPLE_FRAMES):
		await get_tree().process_frame
		if ticket != _verify_serial or String(current_case) != case_key:
			return
		var hand_bone := &"hand_l" if hand == &"LEFT" else &"hand_r"
		var shoulder_bone := &"upperarm_l" if hand == &"LEFT" else &"upperarm_r"
		var elbow_bone := &"lowerarm_l" if hand == &"LEFT" else &"lowerarm_r"
		var hand_pos := _bone_world(hand_bone)
		var shoulder := _bone_world(shoulder_bone)
		var elbow := _bone_world(elbow_bone)
		var arm_length := shoulder.distance_to(elbow) + elbow.distance_to(hand_pos)
		var error := hand_pos.distance_to(target)
		var ratio := shoulder.distance_to(target) / maxf(arm_length, 0.001)
		if error < best_error:
			best_error = error
			best_ratio = ratio
			best_frame = frame + 1
		if error <= CONTACT_ERROR_MAX_M and ratio <= HARD_ARM_FRACTION:
			var passed: Dictionary = case_results.get(case_key, {}) as Dictionary
			passed["contact"] = true
			passed["contact_error_m"] = error
			passed["actual_reach_ratio"] = ratio
			passed["hard_arm_fraction"] = HARD_ARM_FRACTION
			passed["contact_verified_after_frames"] = frame + 1
			passed["world_visual_transferred"] = false
			case_results[case_key] = passed
			_transfer_world_visual(hand, case_key)
			print("[interaction-contact-truth] PASS case=%s hand=%s error=%.3f ratio=%.3f frame=%d" % [
				case_key, String(hand), error, ratio, frame + 1
			])
			return

	var failed: Dictionary = case_results.get(case_key, {}) as Dictionary
	failed["contact"] = false
	failed["contact_error_m"] = best_error
	failed["actual_reach_ratio"] = best_ratio
	failed["hard_arm_fraction"] = HARD_ARM_FRACTION
	failed["contact_verified_after_frames"] = best_frame
	failed["world_visual_transferred"] = false
	failed["contact_failure"] = "hand_never_entered_verified_contact_window"
	case_results[case_key] = failed
	print("[interaction-contact-truth] FAIL case=%s hand=%s best_error=%.3f ratio=%.3f" % [
		case_key, String(hand), best_error, best_ratio
	])


func _show_held_prop(_hand: StringName) -> void:
	## Deliberately empty. The base lab used to fabricate a second tin here.
	## The real world visual is moved only after verified hand contact.
	pass


func _transfer_world_visual(hand: StringName, case_key: String) -> void:
	if _world_visual_transferred or not is_instance_valid(item) or not is_instance_valid(item.interactive_mesh):
		return
	var world_root := item.interactive_mesh as Node3D
	var candidate_parent := world_root.get_parent()
	## SurvivalItemVisual.make() creates a holder with multiple mesh children.
	## ItemPickup.interactive_mesh points only at child 0, so move the holder when
	## present or the label cylinder would remain behind as a fake second can.
	if candidate_parent is Node3D and candidate_parent != item:
		world_root = candidate_parent as Node3D

	_world_visual_parent = world_root.get_parent()
	_world_visual_home = world_root.transform
	_held_attachment = BoneAttachment3D.new()
	_held_attachment.name = "TablePickupVerifiedAttachment"
	_held_attachment.bone_name = &"hand_l" if hand == &"LEFT" else &"hand_r"
	visual.skeleton.add_child(_held_attachment)
	world_root.reparent(_held_attachment, false)
	world_root.transform = Transform3D.IDENTITY
	_held_prop = world_root

	var item_resource := ItemCatalog.get_item(ITEM_ID)
	if item_resource != null and item_resource.held_fit != null:
		item_resource.held_fit.apply_to(world_root)
	else:
		world_root.position = Vector3(0.0, 0.08, 0.025)
		world_root.rotation = Vector3(0.0, 0.0, PI * 0.5)

	_world_visual_transferred = true
	var result: Dictionary = case_results.get(case_key, {}) as Dictionary
	result["world_visual_transferred"] = true
	case_results[case_key] = result


func _restore_world_item() -> void:
	_verify_serial += 1
	if _world_visual_transferred and is_instance_valid(_held_prop) and is_instance_valid(_world_visual_parent):
		_held_prop.reparent(_world_visual_parent, false)
		_held_prop.transform = _world_visual_home
	_held_prop = null
	_world_visual_parent = null
	_world_visual_transferred = false
	if is_instance_valid(_held_attachment):
		_held_attachment.queue_free()
	_held_attachment = null


func _update_overlay() -> void:
	super._update_overlay()
	if not is_instance_valid(_case_label):
		return
	match current_case:
		&"NEAR_TOO_CLOSE":
			_case_label.text = "NEAR EDGE / FOCUS + BOUNDED SETTLE"
		&"FAR_EDGE":
			_case_label.text = "FAR EDGE / VERIFIED HAND CONTACT"
		&"OUT_OF_REACH":
			_case_label.text = "OUT OF REACH / NO AUTO-WALK"


func get_report() -> Dictionary:
	var report := super.get_report()
	report["contact_truth"] = {
		"max_hand_error_m": CONTACT_ERROR_MAX_M,
		"max_reach_ratio": HARD_ARM_FRACTION,
		"sample_frames": CONTACT_SAMPLE_FRAMES,
		"world_handoff": "actual world SurvivalItemVisual holder -> verified hand socket",
		"duplicate_held_prop_spawn": false,
	}
	return report
