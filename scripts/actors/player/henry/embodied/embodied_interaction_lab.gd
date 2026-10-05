class_name EmbodiedInteractionLabActor
extends CharacterBody3D

## Isolated issue #198 laboratory. Production pickup/inventory remain untouched.
##
## Acceptance for this pass:
## - production TpsCamera frames the whole proof;
## - one physical can is presented on one shelf at five authored heights;
## - Henry uses standing / crouch / kneeling body poses instead of stretching a
##   detached arm through the entire vertical reach envelope;
## - ownership transfers only after measured thumb + finger surface contact;
## - the final floor pickup is followed by a right-to-left handoff.

enum Stage { BODY_ALIGN, PICKUP_REACH, HANDOFF, DONE }

const BODY_ALIGN_SECONDS: float = 1.0
const PICKUP_CASE_SECONDS: float = 4.0
const PICKUP_SETUP_END: float = 0.55
const PICKUP_REACH_END: float = 1.35
const PICKUP_GRASP_END: float = 2.35
const PICKUP_HOLD_END: float = 3.35
const HANDOFF_SECONDS: float = 5.2
const HANDOFF_RECEIVER_BEGIN: float = 1.15
const HANDOFF_GRASP_END: float = 2.65
const HANDOFF_HOLD_END: float = 4.55

const ITEM_RADIUS_M: float = 0.045
const ITEM_HALF_HEIGHT_M: float = 0.07
const SHELF_HALF_THICKNESS_M: float = 0.025
const FINGER_SURFACE_TOLERANCE_M: float = 0.018
const MAX_PREVIEW_SPEED: float = 1.5
const STAND_CAPSULE_HEIGHT: float = 2.0
const CROUCH_CAPSULE_HEIGHT: float = 1.30

## The same shelf and the same can move vertically between cases. The order is
## chosen so the final floor pickup can flow directly into stand-up + handoff.
const PICKUP_CASES := [
	{"name": "HEAD SHELF", "height": 1.76, "stance": &"STAND"},
	{"name": "CHEST SHELF", "height": 1.42, "stance": &"STAND"},
	{"name": "WAIST SHELF", "height": 1.04, "stance": &"STAND"},
	{"name": "KNEE SHELF", "height": 0.66, "stance": &"CROUCH"},
	{"name": "FLOOR SHELF", "height": 0.18, "stance": &"KNEEL"},
]

@onready var visual: HenryUALAnimation = $HenryUALVisual
@onready var body_target: EmbodiedTarget3D = get_node("../Targets/BodyTarget") as EmbodiedTarget3D
@onready var hand_target: EmbodiedTarget3D = get_node("../Targets/RightHandTarget") as EmbodiedTarget3D
@onready var stage_label: Label = get_node("../UILayer/Margin/VBox/Stage") as Label
@onready var detail_label: Label = get_node("../UILayer/Margin/VBox/Detail") as Label
@onready var camera: TpsCamera = get_node("../PlayerCamera") as TpsCamera
@onready var pedestal: MeshInstance3D = get_node("../InteractionPedestal") as MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var _elapsed: float = 0.0
var _stage: Stage = Stage.BODY_ALIGN
var _alignment_start_position: Vector3
var _alignment_start_yaw: float
var _skeleton_missing := PackedStringArray()
var _base_playback: AnimationNodeStateMachinePlayback

var _pickup_root: Node3D
var _pickup_shelf: MeshInstance3D
var _pickup_item: MeshInstance3D
var _source_ik: DoorHandIK
var _receiver_ik: DoorHandIK
var _source_grip: TactileHandGrip
var _receiver_grip: TactileHandGrip
var _left_socket: BoneAttachment3D
var _right_socket: BoneAttachment3D

var _pickup_case_index: int = -1
var _pickup_phase: StringName = &""
var _handoff_phase: StringName = &""
var _pickup_reach_started: bool = false
var _pickup_result_recorded: bool = false
var _pickup_attached: bool = false
var _pickup_contact_count: int = 0
var _pickup_finger_contacts: int = 0
var _pickup_thumb_contact: bool = false
var _pickup_surface_error: float = INF
var _pickup_per_finger: Dictionary = {}
var _pickup_results: Array[Dictionary] = []
var _handoff_result: Dictionary = {}
var _handoff_started: bool = false
var _handoff_transferred: bool = false
var _work_pose_requested: bool = false
var _stance: StringName = &"STAND"


func _ready() -> void:
	_alignment_start_position = global_position
	_alignment_start_yaw = rotation.y
	_skeleton_missing = HenrySkeletonContract.validate(visual.skeleton)
	if _skeleton_missing.is_empty():
		print("[EmbodiedLab] Henry skeleton contract OK: %s" % [HenrySkeletonContract.describe(visual.skeleton)])
	else:
		push_warning("[EmbodiedLab] Missing skeleton roles: %s" % [_skeleton_missing])
	if visual.animation_tree != null:
		_base_playback = visual.animation_tree.get("parameters/base/playback") as AnimationNodeStateMachinePlayback
	_build_pickup_rack()
	_set_target_debug_visible(false)
	pedestal.visible = false
	_pickup_root.visible = true
	_update_labels()


func _process(delta: float) -> void:
	_elapsed += delta
	var previous_position: Vector3 = global_position
	var pickup_duration: float = PICKUP_CASES.size() * PICKUP_CASE_SECONDS
	var pickup_end: float = BODY_ALIGN_SECONDS + pickup_duration
	var handoff_end: float = pickup_end + HANDOFF_SECONDS

	if _elapsed < BODY_ALIGN_SECONDS:
		_set_stage(Stage.BODY_ALIGN)
		var t: float = clampf(_elapsed / BODY_ALIGN_SECONDS, 0.0, 1.0)
		var eased: float = t * t * (3.0 - 2.0 * t)
		global_position = _alignment_start_position.lerp(body_target.global_position, eased)
		rotation.y = lerp_angle(_alignment_start_yaw, body_target.global_rotation.y, eased)
		if _pickup_case_index < 0:
			_begin_pickup_case(0)
	elif _elapsed < pickup_end:
		_set_stage(Stage.PICKUP_REACH)
		global_position = body_target.global_position
		rotation.y = body_target.global_rotation.y
		_update_pickup_reach(_elapsed - BODY_ALIGN_SECONDS)
	elif _elapsed < handoff_end:
		_set_stage(Stage.HANDOFF)
		global_position = body_target.global_position
		rotation.y = body_target.global_rotation.y
		_update_handoff(_elapsed - pickup_end)
	else:
		_finish_sequence()
		_set_stage(Stage.DONE)

	velocity = (global_position - previous_position) / maxf(delta, 0.0001)
	if visual != null:
		visual.update_animation_blend(delta)
	_update_labels()


func _set_stage(next_stage: Stage) -> void:
	if _stage == next_stage:
		return
	_stage = next_stage
	print("[EmbodiedLab] stage=%s" % [_stage_name()])


func _stage_name() -> String:
	match _stage:
		Stage.BODY_ALIGN:
			return "1 / ALIGN — gameplay body + production TPS camera"
		Stage.PICKUP_REACH:
			return "2 / SHELF GRASP — five heights / one can"
		Stage.HANDOFF:
			return "3 / HANDOFF — right hand to left hand"
		_:
			return "4 / DONE — production pickup remains untouched"


func _update_labels() -> void:
	if stage_label != null:
		stage_label.text = _stage_name()
	if detail_label == null:
		return
	if _stage == Stage.BODY_ALIGN:
		detail_label.text = "production TpsCamera / body alignment"
		return
	if _stage == Stage.HANDOFF:
		var verdict: String = "TRANSFERRED" if _handoff_transferred else "receiver closing"
		detail_label.text = "right → left   phase=%s   %s\nreceiver contacts=%d (fingers=%d thumb=%s)   best surface error=%s" % [
			String(_handoff_phase), verdict, _pickup_contact_count, _pickup_finger_contacts,
			_pickup_thumb_contact, _error_text(_pickup_surface_error)]
		return
	if _stage == Stage.PICKUP_REACH:
		var case_name: String = "—"
		if _pickup_case_index >= 0 and _pickup_case_index < PICKUP_CASES.size():
			case_name = String(PICKUP_CASES[_pickup_case_index]["name"])
		var verdict: String = "TACTILE HOLD" if _pickup_attached else ("NO CONTACT" if _pickup_phase == &"MISS" else "closing fingers")
		detail_label.text = "test %d/%d: %s   stance=%s   phase=%s\ncontacts=%d (fingers=%d thumb=%s)   best surface error=%s   %s" % [
			_pickup_case_index + 1, PICKUP_CASES.size(), case_name, String(_stance), String(_pickup_phase),
			_pickup_contact_count, _pickup_finger_contacts, _pickup_thumb_contact,
			_error_text(_pickup_surface_error), verdict]
		return
	detail_label.text = "lab complete"


func _error_text(value: float) -> String:
	return "—" if is_inf(value) else "%.3f m" % value


func _build_pickup_rack() -> void:
	_pickup_root = Node3D.new()
	_pickup_root.name = "PickupTactileRig"
	get_parent().add_child.call_deferred(_pickup_root)

	var rack_material := StandardMaterial3D.new()
	rack_material.albedo_color = Color(0.20, 0.23, 0.25)
	rack_material.roughness = 0.88

	var shelf_mesh := BoxMesh.new()
	shelf_mesh.size = Vector3(1.35, SHELF_HALF_THICKNESS_M * 2.0, 0.38)
	shelf_mesh.material = rack_material
	_pickup_shelf = MeshInstance3D.new()
	_pickup_shelf.name = "MovingShelf"
	_pickup_shelf.mesh = shelf_mesh
	_pickup_root.add_child(_pickup_shelf)

	for x: float in [-0.66, 0.66]:
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.05, 2.10, 0.05)
		post_mesh.material = rack_material
		var post := MeshInstance3D.new()
		post.mesh = post_mesh
		post.position = Vector3(x, 1.05, 0.40)
		_pickup_root.add_child(post)

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
	_pickup_item.name = "TactileTestTin"
	_pickup_item.mesh = can_mesh
	_pickup_root.add_child(_pickup_item)

	if visual == null or visual.skeleton == null:
		return
	_source_ik = visual.skeleton.get_node_or_null(^"DoorHand") as DoorHandIK
	if _source_ik != null:
		_tune_arm_solver(_source_ik)

	_receiver_ik = DoorHandIK.new()
	_receiver_ik.name = "TactileHandoffIK"
	_tune_arm_solver(_receiver_ik)
	visual.skeleton.add_child(_receiver_ik)

	_left_socket = visual.get_hand_socket()
	_right_socket = visual.get_offhand_socket()

	_source_grip = TactileHandGrip.new()
	_source_grip.name = "TactileGripRight"
	visual.skeleton.add_child(_source_grip)
	_receiver_grip = TactileHandGrip.new()
	_receiver_grip.name = "TactileGripLeft"
	visual.skeleton.add_child(_receiver_grip)


func _tune_arm_solver(ik: DoorHandIK) -> void:
	ik.elbow_drop = 0.12
	ik.palm_flatten = 0.18
	ik.palm_offset_m = 0.0
	ik.wrist_back_m = 0.040
	ik.blend_in_rate = 8.0
	ik.blend_out_rate = 6.0
	ik.follow_rate = 22.0


func _update_pickup_reach(local_time: float) -> void:
	var case_index: int = mini(int(floor(local_time / PICKUP_CASE_SECONDS)), PICKUP_CASES.size() - 1)
	var case_time: float = fmod(local_time, PICKUP_CASE_SECONDS)
	if case_index != _pickup_case_index:
		_begin_pickup_case(case_index)

	if case_time < PICKUP_SETUP_END:
		_pickup_phase = &"SETUP"
		return

	if not _pickup_reach_started:
		_pickup_reach_started = true
		_configure_arm_for_hand(_source_ik, &"RIGHT")

	_update_arm_goal(_source_ik, &"RIGHT", _pickup_item.global_transform)
	if case_time < PICKUP_REACH_END:
		_pickup_phase = &"REACH"
		_source_grip.release()
		return

	var close_t: float = clampf((case_time - PICKUP_REACH_END) / (PICKUP_GRASP_END - PICKUP_REACH_END), 0.0, 1.0)
	close_t = close_t * close_t * (3.0 - 2.0 * close_t)
	_source_grip.set_goal(&"RIGHT", _pickup_item.global_transform, ITEM_RADIUS_M, ITEM_HALF_HEIGHT_M, close_t)
	_update_tactile_metrics(_source_grip)

	if not _pickup_attached and close_t >= 0.72 and _pickup_thumb_contact and _pickup_finger_contacts >= 2:
		_attach_pickup_to_socket(_right_socket)
		_record_pickup_result(true)

	if _pickup_attached:
		_pickup_phase = &"CONTACT"
		_source_grip.set_goal(&"RIGHT", _pickup_item.global_transform, ITEM_RADIUS_M, ITEM_HALF_HEIGHT_M, 1.0)
	elif case_time < PICKUP_GRASP_END:
		_pickup_phase = &"GRASP"
	else:
		_pickup_phase = &"MISS"
		if not _pickup_result_recorded:
			_record_pickup_result(false)

	if case_time >= PICKUP_HOLD_END and case_index < PICKUP_CASES.size() - 1:
		_source_ik.release()
		_source_grip.release()


func _begin_pickup_case(index: int) -> void:
	if _pickup_case_index >= 0 and _pickup_case_index < PICKUP_CASES.size() - 1:
		_restore_pickup_item_to_rack()
	if _source_ik != null:
		_source_ik.release()
	if _receiver_ik != null:
		_receiver_ik.release()
	if _source_grip != null:
		_source_grip.release()
	if _receiver_grip != null:
		_receiver_grip.release()
	if _work_pose_requested:
		visual.end_work_pose()
		_work_pose_requested = false
	visual.abort_action()

	_pickup_case_index = index
	_pickup_phase = &"SETUP"
	_pickup_reach_started = false
	_pickup_result_recorded = false
	_pickup_attached = false
	_reset_contact_metrics()

	var case_data: Dictionary = PICKUP_CASES[index]
	var height: float = float(case_data["height"])
	_pickup_shelf.position = Vector3(0.0, maxf(SHELF_HALF_THICKNESS_M, height - ITEM_HALF_HEIGHT_M - SHELF_HALF_THICKNESS_M), 0.28)
	_pickup_item.transform = Transform3D(Basis.IDENTITY, Vector3(0.25, height, 0.18))
	_set_stance(StringName(case_data["stance"]))
	print("[EmbodiedLab] case=%s height=%.2f stance=%s" % [case_data["name"], height, _stance])


func _set_stance(stance: StringName) -> void:
	_stance = stance
	var crouched: bool = stance != &"STAND"
	_set_capsule_height(CROUCH_CAPSULE_HEIGHT if crouched else STAND_CAPSULE_HEIGHT)
	if _base_playback != null:
		_base_playback.travel(&"Crouch" if stance == &"CROUCH" else &"Grounded")
	if stance == &"KNEEL":
		_work_pose_requested = visual.begin_work_pose()


func _set_capsule_height(height: float) -> void:
	if collision_shape == null:
		return
	var capsule := collision_shape.shape as CapsuleShape3D
	if capsule == null:
		return
	capsule.height = height
	collision_shape.position.y = height * 0.5


func _configure_arm_for_hand(ik: DoorHandIK, hand: StringName) -> void:
	if ik == null:
		return
	var suffix: String = "l" if hand == &"LEFT" else "r"
	ik.upper_bone = StringName("upperarm_" + suffix)
	ik.lower_bone = StringName("lowerarm_" + suffix)
	ik.hand_bone = StringName("hand_" + suffix)
	ik.middle_bone = StringName("middle_01_" + suffix)
	ik.index_bone = StringName("index_01_" + suffix)
	ik.pinky_bone = StringName("pinky_01_" + suffix)
	ik.left_hand = hand == &"LEFT"


func _update_arm_goal(ik: DoorHandIK, hand: StringName, item_xf: Transform3D) -> void:
	if ik == null:
		return
	var axis: Vector3 = item_xf.basis.y.normalized()
	var shoulder_height: float = 1.30 if _stance == &"STAND" else (0.92 if _stance == &"CROUCH" else 0.72)
	var outward: Vector3 = global_position + Vector3.UP * shoulder_height - item_xf.origin
	outward -= axis * outward.dot(axis)
	if outward.length_squared() < 0.0001:
		outward = -global_transform.basis.z
	outward = outward.normalized()
	if hand == &"LEFT":
		outward = (outward + global_transform.basis.x * -0.12).normalized()
	else:
		outward = (outward + global_transform.basis.x * 0.12).normalized()
	var palm_surface: Vector3 = item_xf.origin + outward * (ITEM_RADIUS_M - 0.006)
	ik.set_goal(palm_surface, outward, 1.0)


func _update_tactile_metrics(grip: TactileHandGrip) -> void:
	_reset_contact_metrics()
	if grip == null:
		return
	var debug: Dictionary = grip.get_contact_debug()
	var errors := debug.get("errors_m", {}) as Dictionary
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


func _attach_pickup_to_socket(socket: BoneAttachment3D) -> void:
	if _pickup_item == null or socket == null:
		return
	var contact_xf: Transform3D = _pickup_item.global_transform
	_pickup_item.reparent(socket, true)
	_pickup_item.global_transform = contact_xf
	_pickup_attached = true


func _record_pickup_result(contact: bool) -> void:
	if _pickup_result_recorded:
		return
	_pickup_result_recorded = true
	var case_data: Dictionary = PICKUP_CASES[_pickup_case_index]
	var result := {
		"name": String(case_data["name"]),
		"height_m": float(case_data["height"]),
		"stance": String(case_data["stance"]),
		"contact": contact,
		"contacts": _pickup_contact_count,
		"finger_contacts": _pickup_finger_contacts,
		"thumb_contact": _pickup_thumb_contact,
		"best_tip_surface_error_m": _pickup_surface_error,
		"per_finger_error_m": _pickup_per_finger.duplicate(true),
		"tactile_weight": _source_grip.get_weight() if _source_grip != null else 0.0,
	}
	_pickup_results.append(result)
	print("[EmbodiedTactile] %s h=%.2f contact=%s contacts=%d fingers=%d thumb=%s best=%.3f" % [
		case_data["name"], float(case_data["height"]), contact, _pickup_contact_count,
		_pickup_finger_contacts, _pickup_thumb_contact, _pickup_surface_error])


func _restore_pickup_item_to_rack() -> void:
	if _pickup_item == null or _pickup_root == null:
		return
	if _pickup_item.get_parent() != _pickup_root:
		_pickup_item.reparent(_pickup_root, true)


func _update_handoff(local_time: float) -> void:
	if not _handoff_started:
		_handoff_started = true
		_handoff_phase = &"RISE"
		if _work_pose_requested:
			visual.end_work_pose()
			_work_pose_requested = false
		_set_capsule_height(STAND_CAPSULE_HEIGHT)
		_stance = &"STAND"
		if _base_playback != null:
			_base_playback.travel(&"Grounded")
		if _source_ik != null:
			_source_ik.release()
		_configure_arm_for_hand(_receiver_ik, &"LEFT")

	if not _pickup_attached:
		_handoff_phase = &"SKIPPED_NO_SOURCE_GRIP"
		return

	_source_grip.set_goal(&"RIGHT", _pickup_item.global_transform, ITEM_RADIUS_M, ITEM_HALF_HEIGHT_M, 1.0)
	if local_time < HANDOFF_RECEIVER_BEGIN:
		_handoff_phase = &"RISE"
		return

	_update_arm_goal(_receiver_ik, &"LEFT", _pickup_item.global_transform)
	var close_t: float = clampf((local_time - HANDOFF_RECEIVER_BEGIN) / (HANDOFF_GRASP_END - HANDOFF_RECEIVER_BEGIN), 0.0, 1.0)
	close_t = close_t * close_t * (3.0 - 2.0 * close_t)
	_receiver_grip.set_goal(&"LEFT", _pickup_item.global_transform, ITEM_RADIUS_M, ITEM_HALF_HEIGHT_M, close_t)
	_update_tactile_metrics(_receiver_grip)

	if not _handoff_transferred and close_t >= 0.72 and _pickup_thumb_contact and _pickup_finger_contacts >= 2:
		_attach_pickup_to_socket(_left_socket)
		_handoff_transferred = true
		_source_grip.release()
		_handoff_phase = &"CONTACT"
		_handoff_result = {
			"contact": true,
			"contacts": _pickup_contact_count,
			"finger_contacts": _pickup_finger_contacts,
			"thumb_contact": _pickup_thumb_contact,
			"best_tip_surface_error_m": _pickup_surface_error,
			"per_finger_error_m": _pickup_per_finger.duplicate(true),
		}
		print("[EmbodiedHandoff] transferred right_to_left contacts=%d fingers=%d thumb=%s best=%.3f" % [
			_pickup_contact_count, _pickup_finger_contacts, _pickup_thumb_contact, _pickup_surface_error])

	if _handoff_transferred:
		_handoff_phase = &"CONTACT"
		_receiver_grip.set_goal(&"LEFT", _pickup_item.global_transform, ITEM_RADIUS_M, ITEM_HALF_HEIGHT_M, 1.0)
	elif local_time < HANDOFF_GRASP_END:
		_handoff_phase = &"RECEIVER_GRASP"
	else:
		_handoff_phase = &"MISS"
		if _handoff_result.is_empty():
			_handoff_result = {
				"contact": false,
				"contacts": _pickup_contact_count,
				"finger_contacts": _pickup_finger_contacts,
				"thumb_contact": _pickup_thumb_contact,
				"best_tip_surface_error_m": _pickup_surface_error,
				"per_finger_error_m": _pickup_per_finger.duplicate(true),
			}

	if local_time >= HANDOFF_HOLD_END:
		_receiver_ik.release()


func _finish_sequence() -> void:
	if _source_ik != null:
		_source_ik.release()
	if _receiver_ik != null:
		_receiver_ik.release()
	if _work_pose_requested:
		visual.end_work_pose()
		_work_pose_requested = false


func _set_target_debug_visible(visible: bool) -> void:
	var body_disc := body_target.get_node_or_null(^"Disc") as VisualInstance3D
	var hand_sphere := hand_target.get_node_or_null(^"Sphere") as VisualInstance3D
	if body_disc != null:
		body_disc.visible = visible
	if hand_sphere != null:
		hand_sphere.visible = visible


## Minimal methods read by HenryUALAnimation / production TpsCamera.
func get_locomotion_speed_ratio() -> float:
	return clampf(Vector2(velocity.x, velocity.z).length() / MAX_PREVIEW_SPEED, 0.0, 1.0)


func get_crouch_speed_ratio() -> float:
	return 0.0


func is_crouching() -> bool:
	return _stance != &"STAND"


func get_view_direction() -> Vector3:
	if camera != null:
		return -camera.global_transform.basis.z.normalized()
	return -global_transform.basis.z.normalized()


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
		"camera": "production TpsCamera scene",
		"test_geometry": "one shelf + one cylindrical can, shelf moved through five heights",
		"body_pose_policy": "Grounded idle / Crouch idle / Fixing_Kneeling work pose",
		"arm_solver": "DoorHandIK as lab wrist reach only",
		"finger_solver": "TactileHandGrip authored Idle_Torch prior + bounded CCD surface settle",
		"contact_rule": "thumb + >=2 non-thumb anatomical tip proxies at cylinder surface",
		"finger_surface_tolerance_m": FINGER_SURFACE_TOLERANCE_M,
		"pickup_results": _pickup_results,
		"handoff": _handoff_result,
		"production_movement_replaced": false,
		"production_item_pickup_replaced": false,
		"production_held_fit_changed": false,
	}
