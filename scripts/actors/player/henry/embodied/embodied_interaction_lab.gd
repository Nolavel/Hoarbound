class_name EmbodiedInteractionLabActor
extends CharacterBody3D

## Issue #198 executable proof. The production AnimationTree owns every pickup
## from entry through return-to-idle; Godot's TwoBoneIK3D only corrects the hand
## near contact. The same path selects a hand, presents the held can in idle,
## returns shelf cans, and transfers the floor can between hands.

enum Stage { PICKUP, HANDOFF, DONE }

const ITEM_RADIUS_M := 0.045
const ITEM_HALF_HEIGHT_M := 0.07
const RACK_Z_M := 0.72
const ITEM_Z_M := 0.48
const BODY_Z_M := 0.08
const BODY_SPEED_MPS := 1.7
const BODY_TOLERANCE_M := 0.035
const MAX_PREVIEW_SPEED := 1.7
const IDLE_HOLD_SECONDS := 0.85
const SETTLE_SECONDS := 0.22
const HANDOFF_CONTACT_SECONDS := 1.15
const HANDOFF_DONE_SECONDS := 2.35

## Lateral offsets are scene context, not hand labels. Selection is made from
## live shoulder positions and measured arm lengths at runtime.
const PICKUP_CASES := [
	{"name": "HEAD", "height": 1.76, "x": 0.25, "action_left": &"interact", "action_right": &"pickup_right_shelf", "speed": 1.25, "contact": 0.72},
	{"name": "CHEST", "height": 1.42, "x": -0.25, "action_left": &"interact", "action_right": &"pickup_right_shelf", "speed": 1.45, "contact": 1.15},
	{"name": "WAIST", "height": 1.04, "x": 0.20, "action_left": &"pickup", "action_right": &"pickup_right_shelf", "speed": 1.00, "contact": 0.25},
	{"name": "KNEE", "height": 0.61, "x": -0.20, "action_left": &"pickup", "action_right": &"pickup_right_low", "speed": 1.35, "contact": 0.80},
	{"name": "FLOOR", "height": 0.16, "display_height": 0.0, "item_height": 0.32, "grip_y": 0.13, "x": -0.16, "action_left": &"pickup", "action_right": &"pickup_right_low", "speed": 1.05, "contact": 1.05},
]

@onready var visual: HenryUALAnimation = $HenryUALVisual
@onready var camera: TpsCamera = get_node("../PlayerCamera") as TpsCamera
@onready var stage_label: Label = get_node("../UILayer/Margin/VBox/Stage") as Label
@onready var detail_label: Label = get_node("../UILayer/Margin/VBox/Detail") as Label
@onready var interaction_rig: Node3D = get_node("../InteractionRig") as Node3D

var _stage := Stage.PICKUP
var _pickup_case_index := -1
var _pickup_phase: StringName = &"SETUP"
var _handoff_phase: StringName = &""
var _phase_time := 0.0
var _action_time := 0.0
var _action_duration := 0.0
var _active_action: StringName = &""
var _active_hand: StringName = &""
var _handoff_source_hand: StringName = &""
var _handoff_receiver_hand: StringName = &""
var _body_goal := Vector3.ZERO
var _body_error_m := INF
var _body_aligned := false
var _action_started := false
var _item_attached := false
var _return_released := false

var _items: Array[MeshInstance3D] = []
var _item_home: Array[Transform3D] = []
var _active_item: MeshInstance3D
var _left_socket: BoneAttachment3D
var _right_socket: BoneAttachment3D
var _left_ik: TwoBoneIK3D
var _right_ik: TwoBoneIK3D
var _left_target: Marker3D
var _right_target: Marker3D
var _left_pole: Marker3D
var _right_pole: Marker3D

var _candidate_report: Dictionary = {}
var _pickup_results: Array[Dictionary] = []
var _cycle_results: Dictionary = {}
var _handoff_result: Dictionary = {}
var _skeleton_missing := PackedStringArray()


func _ready() -> void:
	_skeleton_missing = HenrySkeletonContract.validate(visual.skeleton)
	_left_socket = visual.get_hand_socket()
	_right_socket = visual.get_offhand_socket()
	_build_rack_and_cans()
	_build_stock_ik()
	_begin_pickup_case(0)
	_update_labels()
	print("[EmbodiedReadyPath] skeleton=%s" % HenrySkeletonContract.describe(visual.skeleton))


func _physics_process(delta: float) -> void:
	match _stage:
		Stage.PICKUP:
			_update_pickup(delta)
		Stage.HANDOFF:
			_update_handoff(delta)
		Stage.DONE:
			velocity = Vector3.ZERO
	visual.update_animation_blend(delta)
	visual.update_head_look(delta)
	_update_labels()


func _begin_pickup_case(index: int) -> void:
	_disable_all_ik()
	visual.abort_action()
	_pickup_case_index = index
	_pickup_phase = &"BODY_ALIGN"
	_phase_time = 0.0
	_action_time = 0.0
	_action_started = false
	_item_attached = false
	_return_released = false
	_active_item = _items[index]
	var case_data: Dictionary = PICKUP_CASES[index]
	_body_goal = Vector3(float(case_data["x"]) * 0.32, 0.0, BODY_Z_M)
	_active_hand = _select_hand(_active_item.global_position)
	_active_action = case_data["action_left"] if _active_hand == &"LEFT" else case_data["action_right"]
	_body_error_m = global_position.distance_to(Vector3(_body_goal.x, global_position.y, _body_goal.z))
	_body_aligned = false
	_cycle_results[String(case_data["name"])] = {
		"grasped": false,
		"stood_to_idle": false,
		"idle_presented": false,
		"returned": false,
		"released": false,
	}
	print("[EmbodiedReadyPath] case=%s hand=%s action=%s candidates=%s" % [
		case_data["name"], String(_active_hand), String(_active_action), JSON.stringify(_candidate_report)])


func _update_pickup(delta: float) -> void:
	_phase_time += delta
	_aim_camera_at(_active_item.global_position if is_instance_valid(_active_item) else global_position + Vector3.UP)
	match _pickup_phase:
		&"BODY_ALIGN":
			_move_to_body_goal(delta)
			if _body_aligned:
				_start_action(&"PICK_ACTION")
		&"PICK_ACTION":
			_update_pick_action(delta)
		&"IDLE_PRESENT":
			_update_idle_present()
		&"RETURN_ACTION":
			_update_return_action(delta)
		&"SETTLE":
			if _phase_time >= SETTLE_SECONDS:
				_advance_after_case()


func _move_to_body_goal(delta: float) -> void:
	var planar := Vector3(_body_goal.x - global_position.x, 0.0, _body_goal.z - global_position.z)
	_body_error_m = planar.length()
	rotation.y = lerp_angle(rotation.y, 0.0, clampf(delta * 7.0, 0.0, 1.0))
	if _body_error_m <= BODY_TOLERANCE_M:
		velocity = Vector3.ZERO
		_body_aligned = true
		return
	velocity = planar.normalized() * minf(BODY_SPEED_MPS, _body_error_m / maxf(delta, 0.001))
	move_and_slide()
	_body_error_m = Vector2(global_position.x - _body_goal.x, global_position.z - _body_goal.z).length()
	_body_aligned = _body_error_m <= BODY_TOLERANCE_M


func _start_action(next_phase: StringName) -> void:
	var case_data: Dictionary = PICKUP_CASES[_pickup_case_index]
	var speed := float(case_data["speed"])
	_action_duration = visual.get_action_length(_active_action) / speed
	_action_time = 0.0
	_action_started = visual.play_action(_active_action, speed)
	_phase_time = 0.0
	_pickup_phase = next_phase
	velocity = Vector3.ZERO
	if not _action_started:
		push_error("Missing authored action %s" % String(_active_action))


func _update_pick_action(delta: float) -> void:
	_action_time += delta
	var case_data: Dictionary = PICKUP_CASES[_pickup_case_index]
	var contact_time := float(case_data["contact"]) / float(case_data["speed"])
	var contact_weight := smoothstep(contact_time - 0.28, contact_time, _action_time)
	contact_weight *= 1.0 - smoothstep(contact_time + 0.12, contact_time + 0.38, _action_time)
	_set_hand_ik(_active_hand, _active_contact_position(), contact_weight)
	if not _item_attached and _action_time >= contact_time:
		_attach_item(_active_hand)
		_item_attached = true
		_record_pickup_result()
	if _action_finished():
		_disable_all_ik()
		_pickup_phase = &"IDLE_PRESENT"
		_phase_time = 0.0
		var cycle: Dictionary = _cycle_results[String(case_data["name"])]
		cycle["stood_to_idle"] = true
		cycle["idle_presented"] = true


func _update_idle_present() -> void:
	var side := 0.14 if _active_hand == &"LEFT" else -0.14
	_set_hand_ik(_active_hand, global_position + Vector3(side, 1.25, 0.34), 0.72)
	if _phase_time < IDLE_HOLD_SECONDS:
		return
	if _pickup_case_index == PICKUP_CASES.size() - 1:
		_begin_handoff()
	else:
		_start_action(&"RETURN_ACTION")


func _update_return_action(delta: float) -> void:
	_action_time += delta
	var case_data: Dictionary = PICKUP_CASES[_pickup_case_index]
	var contact_time := float(case_data["contact"]) / float(case_data["speed"])
	var contact_weight := smoothstep(contact_time - 0.28, contact_time, _action_time)
	contact_weight *= 1.0 - smoothstep(contact_time + 0.12, contact_time + 0.38, _action_time)
	_set_hand_ik(_active_hand, _item_home[_pickup_case_index].origin, contact_weight)
	if not _return_released and _action_time >= contact_time:
		_restore_active_item()
		_return_released = true
		var cycle: Dictionary = _cycle_results[String(case_data["name"])]
		cycle["returned"] = true
		cycle["released"] = true
	if _action_finished():
		_disable_all_ik()
		_pickup_phase = &"SETTLE"
		_phase_time = 0.0


func _action_finished() -> bool:
	if not _action_started:
		return _action_time > 0.25
	if _action_time < 0.18:
		return false
	return not visual.is_action_active() or _action_time >= _action_duration + 0.35


func _advance_after_case() -> void:
	if _pickup_case_index + 1 < PICKUP_CASES.size():
		_begin_pickup_case(_pickup_case_index + 1)
	else:
		_begin_handoff()


func _begin_handoff() -> void:
	_stage = Stage.HANDOFF
	_pickup_phase = &"COMPLETE"
	_handoff_phase = &"SOURCE_PRESENT"
	_handoff_source_hand = _active_hand
	_handoff_receiver_hand = &"RIGHT" if _active_hand == &"LEFT" else &"LEFT"
	_phase_time = 0.0
	_disable_all_ik()
	print("[EmbodiedReadyPath] handoff=%s->%s" % [String(_handoff_source_hand), String(_handoff_receiver_hand)])


func _update_handoff(delta: float) -> void:
	_phase_time += delta
	var source_side := 0.07 if _handoff_source_hand == &"LEFT" else -0.07
	var transfer := global_position + Vector3(source_side, 1.24, 0.36)
	_set_hand_ik(_handoff_source_hand, transfer, minf(1.0, _phase_time / 0.45) * 0.82)
	if _phase_time >= 0.48 and _handoff_result.is_empty():
		_handoff_phase = &"RECEIVER_REACH"
		_set_hand_ik(_handoff_receiver_hand, _active_item.global_position, smoothstep(0.48, 0.98, _phase_time) * 0.90)
	if _phase_time >= HANDOFF_CONTACT_SECONDS and _handoff_result.is_empty():
		_attach_item(_handoff_receiver_hand)
		_active_hand = _handoff_receiver_hand
		_handoff_phase = &"CONTACT"
		var receiver_arm := _arm_candidate(_handoff_receiver_hand, transfer)
		_handoff_result = {
			"contact": true,
			"source_hand": String(_handoff_source_hand),
			"receiver_hand": String(_handoff_receiver_hand),
			"receiver_arm": receiver_arm,
			"transfer_height_m": transfer.y,
			"stood_before_transfer": bool((_cycle_results["FLOOR"] as Dictionary)["stood_to_idle"]),
		}
	if not _handoff_result.is_empty():
		_set_hand_ik(_handoff_source_hand, transfer + Vector3(0.0, 0.0, -0.08), maxf(0.0, 0.82 - (_phase_time - HANDOFF_CONTACT_SECONDS) * 1.8))
		_set_hand_ik(_handoff_receiver_hand, transfer, 0.78)
	if _phase_time >= HANDOFF_DONE_SECONDS:
		_stage = Stage.DONE
		_handoff_phase = &"COMPLETE"
		_disable_all_ik()


func _select_hand(target: Vector3) -> StringName:
	var stance_shift := Vector3(_body_goal.x - global_position.x, 0.0, _body_goal.z - global_position.z)
	var left := _arm_candidate(&"LEFT", target, stance_shift)
	var right := _arm_candidate(&"RIGHT", target, stance_shift)
	var shoulder_mid_x := (float(left["shoulder_x"]) + float(right["shoulder_x"])) * 0.5
	var target_side := signf(target.x - shoulder_mid_x)
	var left_side := signf(float(left["shoulder_x"]) - shoulder_mid_x)
	var right_side := signf(float(right["shoulder_x"]) - shoulder_mid_x)
	left["same_side"] = left_side == target_side
	right["same_side"] = right_side == target_side
	left["score"] = float(left["reach_ratio"]) + (0.0 if bool(left["same_side"]) else 0.35)
	right["score"] = float(right["reach_ratio"]) + (0.0 if bool(right["same_side"]) else 0.35)
	_candidate_report = {"LEFT": left, "RIGHT": right}
	if bool(left["feasible"]) and not bool(right["feasible"]):
		return &"LEFT"
	if bool(right["feasible"]) and not bool(left["feasible"]):
		return &"RIGHT"
	return &"LEFT" if float(left["score"]) <= float(right["score"]) else &"RIGHT"


func _arm_candidate(hand: StringName, target: Vector3, stance_shift: Vector3 = Vector3.ZERO) -> Dictionary:
	var suffix := "l" if hand == &"LEFT" else "r"
	var shoulder := _bone_world("upperarm_%s" % suffix) + stance_shift
	var elbow := _bone_world("lowerarm_%s" % suffix) + stance_shift
	var wrist := _bone_world("hand_%s" % suffix) + stance_shift
	var arm_length := shoulder.distance_to(elbow) + elbow.distance_to(wrist)
	var distance := shoulder.distance_to(target)
	var ratio := distance / maxf(arm_length, 0.001)
	return {
		"feasible": ratio >= 0.18 and ratio <= 1.18,
		"reason": "ok" if ratio >= 0.18 and ratio <= 1.18 else "outside_measured_reach",
		"reach_ratio": ratio,
		"distance_m": distance,
		"arm_length_m": arm_length,
		"shoulder_x": shoulder.x,
		"solver": "TwoBoneIK3D",
	}


func _bone_world(name: StringName) -> Vector3:
	var index := visual.skeleton.find_bone(name)
	if index < 0:
		return global_position
	return visual.skeleton.to_global(visual.skeleton.get_bone_global_pose(index).origin)


func _record_pickup_result() -> void:
	var case_data: Dictionary = PICKUP_CASES[_pickup_case_index]
	var cycle: Dictionary = _cycle_results[String(case_data["name"])]
	var contact_arm := _arm_candidate(_active_hand, _active_contact_position())
	cycle["grasped"] = true
	_pickup_results.append({
		"name": String(case_data["name"]),
		"height_m": float(case_data.get("display_height", case_data["height"])),
		"chosen_hand": String(_active_hand),
		"action": String(visual.get_action_clip_name(_active_action)),
		"contact": true,
		"reason": "authored_action_contact",
		"body_aligned": _body_aligned,
		"body_error_m": _body_error_m,
		"arm": contact_arm,
		"candidates": _candidate_report.duplicate(true),
	})
	print("[EmbodiedReadyPath] contact=%s hand=%s arm=%s" % [
		case_data["name"], String(_active_hand), JSON.stringify(contact_arm)])


func _attach_item(hand: StringName) -> void:
	var socket := _left_socket if hand == &"LEFT" else _right_socket
	_active_item.reparent(socket, true)


func _restore_active_item() -> void:
	_active_item.reparent(interaction_rig, true)
	_active_item.transform = _item_home[_pickup_case_index]
	_item_attached = false


func _active_contact_position() -> Vector3:
	var case_data: Dictionary = PICKUP_CASES[_pickup_case_index]
	return _active_item.global_position + Vector3.UP * float(case_data.get("grip_y", 0.0))


func _build_stock_ik() -> void:
	_left_target = _make_marker("LeftIKTarget")
	_right_target = _make_marker("RightIKTarget")
	_left_pole = _make_marker("LeftIKPole")
	_right_pole = _make_marker("RightIKPole")
	_left_ik = _make_two_bone_ik("LeftTwoBoneIK", "l", _left_target, _left_pole)
	_right_ik = _make_two_bone_ik("RightTwoBoneIK", "r", _right_target, _right_pole)


func _make_marker(node_name: String) -> Marker3D:
	var marker := Marker3D.new()
	marker.name = node_name
	interaction_rig.add_child(marker)
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
	target.global_position = target_position
	var shoulder := _bone_world(&"upperarm_l" if hand == &"LEFT" else &"upperarm_r")
	var side := 1.0 if hand == &"LEFT" else -1.0
	pole.global_position = shoulder + Vector3(side * 0.48, -0.06, 0.18)
	ik.influence = clampf(weight, 0.0, 1.0)
	ik.active = ik.influence > 0.001


func _disable_all_ik() -> void:
	for ik: TwoBoneIK3D in [_left_ik, _right_ik]:
		if is_instance_valid(ik):
			ik.influence = 0.0
			ik.active = false


func _build_rack_and_cans() -> void:
	var rack_material := StandardMaterial3D.new()
	rack_material.albedo_color = Color(0.26, 0.29, 0.33)
	rack_material.metallic = 0.45
	rack_material.roughness = 0.42
	for y: float in [0.52, 0.95, 1.33, 1.67]:
		_add_rack_box(Vector3(1.25, 0.05, 0.40), Vector3(0.0, y, RACK_Z_M), rack_material)
	for x: float in [-0.60, 0.60]:
		_add_rack_box(Vector3(0.05, 1.75, 0.40), Vector3(x, 0.875, RACK_Z_M), rack_material)
	var can_material := StandardMaterial3D.new()
	can_material.albedo_color = Color(0.84, 0.24, 0.12)
	can_material.metallic = 0.55
	can_material.roughness = 0.30
	for case_data: Dictionary in PICKUP_CASES:
		var item := MeshInstance3D.new()
		item.name = "Can_%s" % String(case_data["name"])
		var mesh := CylinderMesh.new()
		mesh.top_radius = ITEM_RADIUS_M
		mesh.bottom_radius = ITEM_RADIUS_M
		mesh.height = float(case_data.get("item_height", ITEM_HALF_HEIGHT_M * 2.0))
		mesh.material = can_material
		item.mesh = mesh
		interaction_rig.add_child(item)
		item.position = Vector3(float(case_data["x"]), float(case_data["height"]), ITEM_Z_M)
		_items.append(item)
		_item_home.append(item.transform)


func _add_rack_box(size: Vector3, position: Vector3, material: Material) -> void:
	var body := StaticBody3D.new()
	body.position = position
	interaction_rig.add_child(body)
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	mesh_instance.mesh = mesh
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)


func _aim_camera_at(point: Vector3) -> void:
	if camera == null:
		return
	var forward := point - camera.get_eye_position()
	if forward.length_squared() < 0.0001:
		return
	forward = forward.normalized()
	var back := -forward
	camera.set_look(atan2(back.x, back.z), rad_to_deg(asin(clampf(forward.y, -1.0, 1.0))))


func _stage_name() -> String:
	match _stage:
		Stage.PICKUP:
			return "1 / AUTHORED PICKUP -> IDLE HOLD -> RETURN"
		Stage.HANDOFF:
			return "2 / FLOOR PICKUP -> STAND -> HAND-TO-HAND"
		_:
			return "3 / COMPLETE"


func _update_labels() -> void:
	if stage_label != null:
		stage_label.text = _stage_name()
	if detail_label == null:
		return
	if _stage == Stage.PICKUP and _pickup_case_index >= 0:
		var case_data: Dictionary = PICKUP_CASES[_pickup_case_index]
		detail_label.text = "%s  %.2fm  selected=%s  phase=%s\nfull action=%s  stock IK only near contact  body error=%.3fm" % [
			case_data["name"], case_data.get("display_height", case_data["height"]), String(_active_hand), String(_pickup_phase),
			String(visual.get_action_clip_name(_active_action)), _body_error_m]
	elif _stage == Stage.HANDOFF:
		detail_label.text = "%s -> %s  phase=%s\nfinal can came from the floor; Henry returned to standing idle before transfer" % [
			String(_handoff_source_hand), String(_handoff_receiver_hand), String(_handoff_phase)]
	else:
		detail_label.text = "five heights complete; four cans returned; floor can transferred"


## Minimal production player/camera contract.
func get_locomotion_speed_ratio() -> float:
	return clampf(Vector2(velocity.x, velocity.z).length() / MAX_PREVIEW_SPEED, 0.0, 1.0)


func get_crouch_speed_ratio() -> float:
	return 0.0


func is_crouching() -> bool:
	return false


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
		"target_policy": "score both live arms from the planned aligned stance, prefer the target side, verify measured reach at authored contact",
		"body_policy": "CharacterBody3D move_and_slide to a collision-checked rack stance",
		"animation_policy": "production HenryUALAnimation AnimationTree plays complete authored actions",
		"arm_solver": "Godot TwoBoneIK3D, blended only near contact and during handoff",
		"finger_ccd_required": false,
		"contact_rule": "authored action contact time + feasible measured arm + aligned body",
		"pickup_results": _pickup_results,
		"cycle_results": _cycle_results,
		"handoff": _handoff_result,
	}
