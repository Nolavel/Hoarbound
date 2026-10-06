class_name TableInteractionSolverLab
extends Node

## Issue #203 tabletop interaction-commit experiment.
##
## Focus never moves Henry. Once F is committed, this lab solves a small authored
## interaction stance from the live Henry pose + item position, then plays a real
## UAL action and uses stock TwoBoneIK3D only as contact correction.
##
## This is intentionally LAB-ONLY. It does not own InventoryComponent and never
## changes production InteractComponent, Player or camera defaults.

enum State { IDLE, SETTLE, ACTION, HOLD, COMPLETE }

const ITEM_ID: StringName = &"tinned_stew"
const TABLE_HALF_DEPTH_M: float = 0.20
const TABLE_FRONT_Z_M: float = TABLE_HALF_DEPTH_M
const NEAR_ITEM_Z_M: float = 0.13
const FAR_ITEM_Z_M: float = -0.14
const ITEM_X_M: float = 0.10
const ITEM_Y_M: float = MealTable.TOP_Y + 0.02

## The body may make one small preparation adjustment after F, never a hidden
## metre-long auto-walk. Larger corrections mean the interaction is unavailable.
const MAX_SETTLE_M: float = 0.35
const MAX_SETTLE_YAW_DEG: float = 25.0
const SETTLE_SECONDS: float = 0.34
const MIN_FRONT_CLEARANCE_M: float = 0.44
const NEAR_FRONT_CLEARANCE_M: float = 0.62
const FAR_FRONT_CLEARANCE_M: float = 0.46
const MAX_LATERAL_STANCE_M: float = 0.16

## Authored pickup motion may bring the shoulder forward. IK is not allowed to
## invent infinite reach; this small allowance represents torso/shoulder motion
## that the full-body clip owns before contact.
const AUTHORED_TORSO_REACH_M: float = 0.18
const COMFORT_ARM_FRACTION: float = 0.92
const HARD_ARM_FRACTION: float = 1.03

const ACTION_SPEED: float = 1.35
const CONTACT_SECONDS_SOURCE: float = 0.80
const IK_BLEND_IN_SECONDS: float = 0.24
const IK_BLEND_OUT_SECONDS: float = 0.26
const HOLD_SECONDS: float = 0.80

var stage: DiegeticInventoryStage
var player: Player
var camera: TpsCamera
var visual: HenryUALAnimation
var item: ItemPickup

var state: State = State.IDLE
var current_case: StringName = &""
var prompt_visible: bool = false
var solution: Dictionary = {}
var case_results: Dictionary = {}

var _state_time: float = 0.0
var _settle_from: Vector3 = Vector3.ZERO
var _settle_to: Vector3 = Vector3.ZERO
var _settle_from_yaw: float = 0.0
var _settle_to_yaw: float = 0.0
var _action_time: float = 0.0
var _action_length: float = 0.0
var _contact_time: float = CONTACT_SECONDS_SOURCE / ACTION_SPEED
var _contact_done: bool = false
var _active_hand: StringName = &""
var _active_action: StringName = &""
var _left_ik: TwoBoneIK3D
var _right_ik: TwoBoneIK3D
var _left_target: Marker3D
var _right_target: Marker3D
var _left_pole: Marker3D
var _right_pole: Marker3D
var _held_attachment: BoneAttachment3D
var _held_prop: Node3D
var _world_mesh_was_visible: bool = true
var _prompt_label: Label
var _case_label: Label


func setup(stage_node: DiegeticInventoryStage) -> void:
	stage = stage_node
	player = stage.player
	camera = stage.camera
	visual = player.get_node_or_null(^"HenryUALVisual") as HenryUALAnimation
	item = stage.get_item_by_id(ITEM_ID)
	_build_stock_ik()
	_build_overlay()
	process_priority = 20
	set_process(true)


func prepare_case(case_name: StringName) -> void:
	_restore_world_item()
	_disable_all_ik()
	if is_instance_valid(visual):
		visual.abort_action()
	state = State.IDLE
	current_case = case_name
	_state_time = 0.0
	_action_time = 0.0
	_contact_done = false
	_active_hand = &""
	_active_action = &""
	solution.clear()
	case_results.erase(String(case_name))
	stage.call(&"_reset_focus")

	match case_name:
		&"NEAR_TOO_CLOSE":
			item.position = Vector3(ITEM_X_M, ITEM_Y_M, NEAR_ITEM_Z_M)
			player.global_position = Vector3(0.02, 1.0, 0.56)
		&"FAR_EDGE":
			item.position = Vector3(-ITEM_X_M, ITEM_Y_M, FAR_ITEM_Z_M)
			player.global_position = Vector3(0.0, 1.0, 0.86)
		&"OUT_OF_REACH":
			item.position = Vector3(-ITEM_X_M, ITEM_Y_M, FAR_ITEM_Z_M)
			player.global_position = Vector3(0.0, 1.0, 1.42)
		_:
			push_error("Unknown interaction settle lab case: %s" % String(case_name))
			return

	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	var face_yaw := _yaw_to(stage.table.global_position)
	player.global_rotation.y = face_yaw
	camera.set_look(face_yaw, -22.0)
	if camera.has_method(&"snap_to_target"):
		camera.call(&"snap_to_target")
	stage.lock_demo_body_to_table()
	_update_solution()
	_update_overlay()


func aim_at_item() -> void:
	if not is_instance_valid(stage) or not is_instance_valid(item):
		return
	var look: Vector2 = stage.get_demo_look_for_item(ITEM_ID)
	stage.set_demo_look(look.x, look.y)


func press_interact() -> bool:
	_update_solution()
	if not prompt_visible or solution.is_empty() or state != State.IDLE:
		return false
	state = State.SETTLE
	_state_time = 0.0
	_settle_from = player.global_position
	_settle_to = solution["stance_position"] as Vector3
	_settle_from_yaw = player.global_rotation.y
	_settle_to_yaw = float(solution["stance_yaw"])
	_active_hand = StringName(solution["hand"])
	_active_action = StringName(solution["action"])
	case_results[String(current_case)] = {
		"prompt_before_f": true,
		"pressed_f": true,
		"reachable": true,
		"hand": String(_active_hand),
		"action": String(_active_action),
		"item_depth_m": float(solution["item_depth_m"]),
		"settle_distance_m": float(solution["settle_distance_m"]),
		"settle_yaw_deg": float(solution["settle_yaw_deg"]),
		"predicted_reach_ratio": float(solution["predicted_reach_ratio"]),
		"contact": false,
		"contact_error_m": INF,
		"actual_reach_ratio": INF,
	}
	return true


func get_report() -> Dictionary:
	return {
		"state": State.keys()[state],
		"current_case": String(current_case),
		"prompt_visible": prompt_visible,
		"solution": solution.duplicate(true),
		"case_results": case_results.duplicate(true),
		"principle": "focus_does_not_move_body; F commits stance settle + authored action + IK contact correction",
		"max_settle_m": MAX_SETTLE_M,
		"authored_torso_reach_m": AUTHORED_TORSO_REACH_M,
	}


func is_case_complete() -> bool:
	return state == State.COMPLETE


func get_item_depth_m() -> float:
	return float(solution.get("item_depth_m", 0.0))


func _process(delta: float) -> void:
	if not is_instance_valid(stage) or not is_instance_valid(item):
		return
	_state_time += maxf(delta, 0.0)
	match state:
		State.IDLE:
			_update_solution()
		State.SETTLE:
			_update_settle()
		State.ACTION:
			_update_action(delta)
		State.HOLD:
			if _state_time >= HOLD_SECONDS:
				state = State.COMPLETE
				_state_time = 0.0
		State.COMPLETE:
			pass
	_update_overlay()


func _update_solution() -> void:
	prompt_visible = false
	solution.clear()
	if current_case == &"" or not is_instance_valid(item) or not is_instance_valid(visual):
		return
	if current_case == &"OUT_OF_REACH":
		## Still solve honestly; the distance budget below must reject it.
		pass
	if stage.get_stable_interact_target_id() != ITEM_ID:
		return

	var contact := stage.get_item_focus_point(item)
	var item_local := stage.table.to_local(contact)
	var depth := clampf(TABLE_FRONT_Z_M - item_local.z, 0.0, TABLE_HALF_DEPTH_M * 2.0)
	var depth_t := clampf(depth / (TABLE_HALF_DEPTH_M * 2.0), 0.0, 1.0)
	var desired_clearance := lerpf(NEAR_FRONT_CLEARANCE_M, FAR_FRONT_CLEARANCE_M, depth_t)
	desired_clearance = maxf(desired_clearance, MIN_FRONT_CLEARANCE_M)
	var desired_local_x := clampf(item_local.x * 0.45, -MAX_LATERAL_STANCE_M, MAX_LATERAL_STANCE_M)
	var desired_local := Vector3(desired_local_x, player.global_position.y - stage.table.global_position.y, TABLE_FRONT_Z_M + desired_clearance)
	var stance := stage.table.to_global(desired_local)
	stance.y = player.global_position.y
	var stance_yaw := _yaw_from(stance, contact)
	var settle_distance := Vector2(player.global_position.x - stance.x, player.global_position.z - stance.z).length()
	var settle_yaw_deg := absf(rad_to_deg(wrapf(stance_yaw - player.global_rotation.y, -PI, PI)))

	var left := _arm_candidate(&"LEFT", contact, stance, stance_yaw)
	var right := _arm_candidate(&"RIGHT", contact, stance, stance_yaw)
	var chosen: Dictionary = left if float(left["score"]) <= float(right["score"]) else right
	if not bool(chosen["feasible"]) and bool((right if chosen == left else left)["feasible"]):
		chosen = right if chosen == left else left
	var reachable := (
		settle_distance <= MAX_SETTLE_M
		and settle_yaw_deg <= MAX_SETTLE_YAW_DEG
		and bool(chosen["feasible"])
	)
	if not reachable:
		return

	var hand := StringName(chosen["hand"])
	var action: StringName = &"pickup" if hand == &"LEFT" else &"pickup_right_low"
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
		"torso_allowance_m": AUTHORED_TORSO_REACH_M,
		"left": left,
		"right": right,
	}
	prompt_visible = true


func _arm_candidate(hand: StringName, target: Vector3, stance: Vector3, stance_yaw: float) -> Dictionary:
	var suffix := "l" if hand == &"LEFT" else "r"
	var shoulder := _bone_world(StringName("upperarm_%s" % suffix))
	var elbow := _bone_world(StringName("lowerarm_%s" % suffix))
	var wrist := _bone_world(StringName("hand_%s" % suffix))
	var arm_length := shoulder.distance_to(elbow) + elbow.distance_to(wrist)
	var shoulder_local := player.global_transform.affine_inverse() * shoulder
	var predicted_basis := Basis(Vector3.UP, stance_yaw)
	var predicted_shoulder := stance + predicted_basis * shoulder_local
	var distance := predicted_shoulder.distance_to(target)
	var effective_reach := arm_length * COMFORT_ARM_FRACTION + AUTHORED_TORSO_REACH_M
	var ratio := distance / maxf(arm_length, 0.001)
	var target_local_x := _point_local_to_pose(target, stance, stance_yaw).x
	var shoulder_side := signf(shoulder_local.x)
	var target_side := signf(target_local_x)
	var cross_body_penalty := 0.16 if target_side != 0.0 and shoulder_side != target_side else 0.0
	return {
		"hand": String(hand),
		"feasible": distance <= effective_reach and ratio >= 0.25,
		"distance_m": distance,
		"arm_length_m": arm_length,
		"effective_reach_m": effective_reach,
		"reach_ratio": ratio,
		"score": ratio + cross_body_penalty,
		"cross_body_penalty": cross_body_penalty,
	}


func _update_settle() -> void:
	var t := clampf(_state_time / SETTLE_SECONDS, 0.0, 1.0)
	var eased := smoothstep(0.0, 1.0, t)
	player.velocity = Vector3.ZERO
	player.global_position = _settle_from.lerp(_settle_to, eased)
	player.global_rotation.y = lerp_angle(_settle_from_yaw, _settle_to_yaw, eased)
	player.reset_physics_interpolation()
	if t >= 1.0:
		_start_action()


func _start_action() -> void:
	state = State.ACTION
	_state_time = 0.0
	_action_time = 0.0
	_contact_done = false
	player.velocity = Vector3.ZERO
	_action_length = visual.get_action_length(_active_action) / ACTION_SPEED
	var started := visual.play_action(_active_action, ACTION_SPEED)
	if not started:
		push_error("Table interaction lab could not play action %s" % String(_active_action))
	_contact_time = CONTACT_SECONDS_SOURCE / ACTION_SPEED


func _update_action(delta: float) -> void:
	_action_time += maxf(delta, 0.0)
	var target := stage.get_item_focus_point(item)
	var weight := smoothstep(_contact_time - IK_BLEND_IN_SECONDS, _contact_time, _action_time)
	weight *= 1.0 - smoothstep(_contact_time + 0.08, _contact_time + IK_BLEND_OUT_SECONDS, _action_time)
	_set_hand_ik(_active_hand, target, weight)
	if not _contact_done and _action_time >= _contact_time:
		_contact_done = true
		_record_contact(target)
		_show_held_prop(_active_hand)
	if _action_time >= maxf(_action_length + 0.20, _contact_time + 0.45) or not visual.is_action_active() and _action_time > 0.25:
		_disable_all_ik()
		state = State.HOLD
		_state_time = 0.0


func _record_contact(target: Vector3) -> void:
	var hand_bone := &"hand_l" if _active_hand == &"LEFT" else &"hand_r"
	var shoulder_bone := &"upperarm_l" if _active_hand == &"LEFT" else &"upperarm_r"
	var elbow_bone := &"lowerarm_l" if _active_hand == &"LEFT" else &"lowerarm_r"
	var hand_pos := _bone_world(hand_bone)
	var shoulder := _bone_world(shoulder_bone)
	var elbow := _bone_world(elbow_bone)
	var arm_length := shoulder.distance_to(elbow) + elbow.distance_to(hand_pos)
	var ratio := shoulder.distance_to(target) / maxf(arm_length, 0.001)
	var result: Dictionary = case_results.get(String(current_case), {}) as Dictionary
	result["contact"] = true
	result["contact_error_m"] = hand_pos.distance_to(target)
	result["actual_reach_ratio"] = ratio
	result["hard_arm_fraction"] = HARD_ARM_FRACTION
	case_results[String(current_case)] = result


func _build_stock_ik() -> void:
	if not is_instance_valid(visual) or not is_instance_valid(visual.skeleton):
		return
	_left_target = _make_marker("TableLeftIKTarget")
	_right_target = _make_marker("TableRightIKTarget")
	_left_pole = _make_marker("TableLeftIKPole")
	_right_pole = _make_marker("TableRightIKPole")
	_left_ik = _make_two_bone_ik("TableLeftTwoBoneIK", "l", _left_target, _left_pole)
	_right_ik = _make_two_bone_ik("TableRightTwoBoneIK", "r", _right_target, _right_pole)


func _make_marker(node_name: String) -> Marker3D:
	var marker := Marker3D.new()
	marker.name = node_name
	stage.add_child(marker)
	return marker


func _make_two_bone_ik(node_name: String, suffix: String, target: Marker3D, pole: Marker3D) -> TwoBoneIK3D:
	var ik := TwoBoneIK3D.new()
	ik.name = node_name
	visual.skeleton.add_child(ik)
	ik.setting_count = 1
	ik.set_root_bone_name(0, "upperarm_%s" % suffix)
	ik.set_middle_bone_name(0, "lowerarm_%s" % suffix)
	ik.set_end_bone_name(0, "hand_%s" % suffix)
	ik.set_target_node(0, ik.get_path_to(target))
	ik.set_pole_node(0, ik.get_path_to(pole))
	ik.influence = 0.0
	ik.active = false
	return ik


func _set_hand_ik(hand: StringName, target_position: Vector3, weight: float) -> void:
	var ik := _left_ik if hand == &"LEFT" else _right_ik
	var target := _left_target if hand == &"LEFT" else _right_target
	var pole := _left_pole if hand == &"LEFT" else _right_pole
	if not is_instance_valid(ik) or not is_instance_valid(target) or not is_instance_valid(pole):
		return
	var shoulder := _bone_world(&"upperarm_l" if hand == &"LEFT" else &"upperarm_r")
	var elbow := _bone_world(&"lowerarm_l" if hand == &"LEFT" else &"lowerarm_r")
	target.global_position = target_position
	var reach := (target_position - shoulder).normalized()
	var bend := elbow - shoulder
	bend -= reach * bend.dot(reach)
	if bend.length_squared() < 0.0001:
		bend = player.global_transform.basis.x * (1.0 if hand == &"RIGHT" else -1.0) + Vector3.DOWN * 0.35
		bend -= reach * bend.dot(reach)
	if bend.length_squared() < 0.0001:
		bend = reach.cross(Vector3.UP)
	pole.global_position = shoulder + bend.normalized() * 0.48
	ik.influence = clampf(weight, 0.0, 1.0)
	ik.active = ik.influence > 0.001


func _disable_all_ik() -> void:
	for ik: TwoBoneIK3D in [_left_ik, _right_ik]:
		if is_instance_valid(ik):
			ik.influence = 0.0
			ik.active = false


func _show_held_prop(hand: StringName) -> void:
	if is_instance_valid(item.interactive_mesh):
		_world_mesh_was_visible = item.interactive_mesh.visible
		item.interactive_mesh.visible = false
	if is_instance_valid(_held_prop):
		_held_prop.queue_free()
	if is_instance_valid(_held_attachment):
		_held_attachment.queue_free()
	_held_attachment = BoneAttachment3D.new()
	_held_attachment.name = "TablePickupHeldAttachment"
	_held_attachment.bone_name = &"hand_l" if hand == &"LEFT" else &"hand_r"
	visual.skeleton.add_child(_held_attachment)
	_held_prop = SurvivalItemVisual.make(ITEM_ID)
	_held_prop.name = "HeldTableTin"
	_held_attachment.add_child(_held_prop)
	var item_resource := ItemCatalog.get_item(ITEM_ID)
	if item_resource != null and item_resource.held_fit != null:
		item_resource.held_fit.apply_to(_held_prop)
	else:
		_held_prop.position = Vector3(0.0, 0.08, 0.025)
		_held_prop.rotation = Vector3(0.0, 0.0, PI * 0.5)


func _restore_world_item() -> void:
	if is_instance_valid(item) and is_instance_valid(item.interactive_mesh):
		item.interactive_mesh.visible = _world_mesh_was_visible
	if is_instance_valid(_held_prop):
		_held_prop.queue_free()
	_held_prop = null
	if is_instance_valid(_held_attachment):
		_held_attachment.queue_free()
	_held_attachment = null


func _bone_world(name: StringName) -> Vector3:
	if not is_instance_valid(visual) or not is_instance_valid(visual.skeleton):
		return player.global_position
	var index := visual.skeleton.find_bone(name)
	if index < 0:
		return player.global_position
	return visual.skeleton.to_global(visual.skeleton.get_bone_global_pose(index).origin)


func _point_local_to_pose(point: Vector3, origin: Vector3, yaw: float) -> Vector3:
	var basis := Basis(Vector3.UP, yaw)
	return basis.inverse() * (point - origin)


func _yaw_to(target: Vector3) -> float:
	return _yaw_from(player.global_position, target)


func _yaw_from(origin: Vector3, target: Vector3) -> float:
	var heading := target - origin
	heading.y = 0.0
	if heading.length_squared() < 0.0001:
		return player.global_rotation.y
	heading = heading.normalized()
	return atan2(-heading.x, -heading.z)


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "InteractionSettleLabUI"
	layer.layer = 110
	stage.add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	_case_label = Label.new()
	_case_label.position = Vector2(32.0, 30.0)
	_case_label.add_theme_font_size_override("font_size", 18)
	root.add_child(_case_label)

	_prompt_label = Label.new()
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.set_anchors_preset(Control.PRESET_CENTER)
	_prompt_label.position = Vector2(-110.0, 34.0)
	_prompt_label.size = Vector2(220.0, 36.0)
	_prompt_label.add_theme_font_size_override("font_size", 17)
	root.add_child(_prompt_label)


func _update_overlay() -> void:
	if not is_instance_valid(_case_label) or not is_instance_valid(_prompt_label):
		return
	var case_text := ""
	match current_case:
		&"NEAR_TOO_CLOSE": case_text = "NEAR EDGE / BODY TOO CLOSE"
		&"FAR_EDGE": case_text = "FAR EDGE / REACH SOLVE"
		&"OUT_OF_REACH": case_text = "OUT OF REACH / NO AUTO-WALK"
	_case_label.text = case_text
	if state == State.IDLE:
		_prompt_label.text = "F  PICK UP" if prompt_visible else ""
	elif state == State.SETTLE:
		_prompt_label.text = "SETTLE"
	elif state == State.ACTION:
		_prompt_label.text = "REACH"
	else:
		_prompt_label.text = ""
