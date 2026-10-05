class_name EmbodiedInteractionLabActor
extends CharacterBody3D

## Isolated proof for issue #198. It deliberately bypasses production input and
## demonstrates two seams only:
## 1) target -> body alignment -> existing action -> release;
## 2) one real Henry skeleton + current pickup clip + current two-bone arm solver
##    against the same small item at several authored heights.
##
## This remains diagnostic code. It does not replace production locomotion,
## ItemPickup, inventory ownership, or the eventual authored low/high reach set.

enum Stage { IDLE, ALIGN, ACTION, RELEASE, PICKUP_REACH, DONE }

const IDLE_END: float = 1.2
const ALIGN_END: float = 3.2
const ACTION_END: float = 5.5
const RELEASE_END: float = 7.2
const PICKUP_BEGIN: float = 7.6
const PICKUP_CASE_SECONDS: float = 1.8
const PICKUP_SETUP_END: float = 0.38
const PICKUP_REACH_END: float = 1.28
const PICKUP_CONTACT_END: float = 1.55
const PICKUP_CONTACT_TOLERANCE_M: float = 0.13
const MAX_PREVIEW_SPEED: float = 1.5

## The centre cases keep lateral position constant so height is the main variable.
## The mirrored waist case exists only to prove that hand choice is not hard-wired
## to the right arm. The last case deliberately exceeds a plausible standing reach.
const PICKUP_CASES := [
	{"name": "FLOOR", "position": Vector3(0.22, 0.10, 0.10)},
	{"name": "KNEE", "position": Vector3(0.22, 0.58, 0.10)},
	{"name": "WAIST", "position": Vector3(0.22, 1.00, 0.10)},
	{"name": "HIGH SHELF", "position": Vector3(0.22, 1.55, 0.10)},
	{"name": "ABOVE HEAD", "position": Vector3(0.16, 2.00, 0.10)},
	{"name": "WAIST LEFT", "position": Vector3(-0.28, 1.00, 0.10)},
	{"name": "TOO HIGH", "position": Vector3(0.16, 2.34, 0.10)},
]

@onready var visual: HenryUALAnimation = $HenryUALVisual
@onready var body_target: EmbodiedTarget3D = get_node("../Targets/BodyTarget") as EmbodiedTarget3D
@onready var hand_target: EmbodiedTarget3D = get_node("../Targets/RightHandTarget") as EmbodiedTarget3D
@onready var stage_label: Label = get_node("../UILayer/Margin/VBox/Stage") as Label
@onready var detail_label: Label = get_node("../UILayer/Margin/VBox/Detail") as Label
@onready var camera: Camera3D = get_node("../Camera3D") as Camera3D
@onready var pedestal: MeshInstance3D = get_node("../InteractionPedestal") as MeshInstance3D

var _elapsed: float = 0.0
var _stage: Stage = Stage.IDLE
var _alignment_start_position: Vector3
var _alignment_start_yaw: float
var _release_start_position: Vector3
var _action_started: bool = false
var _skeleton_missing := PackedStringArray()

var _pickup_root: Node3D
var _pickup_item: MeshInstance3D
var _pickup_ik: DoorHandIK
var _pickup_case_index: int = -1
var _pickup_phase: StringName = &""
var _pickup_hand: StringName = &"RIGHT"
var _pickup_action_class: StringName = &""
var _pickup_reach_started: bool = false
var _pickup_contact_recorded: bool = false
var _pickup_attached: bool = false
var _pickup_attachment: BoneAttachment3D
var _pickup_hand_error: float = -1.0
var _pickup_results: Array[Dictionary] = []


func _ready() -> void:
	_alignment_start_position = global_position
	_alignment_start_yaw = rotation.y
	camera.fov = 47.0
	camera.look_at(Vector3(0.0, 1.15, 0.12), Vector3.UP)
	_skeleton_missing = HenrySkeletonContract.validate(visual.skeleton)
	if _skeleton_missing.is_empty():
		print("[EmbodiedLab] Henry skeleton contract OK: %s" % [HenrySkeletonContract.describe(visual.skeleton)])
	else:
		push_warning("[EmbodiedLab] Missing skeleton roles: %s" % [_skeleton_missing])
	_build_pickup_rack()
	_update_labels()


func _process(delta: float) -> void:
	_elapsed += delta
	var previous_position: Vector3 = global_position

	if _elapsed < IDLE_END:
		_set_stage(Stage.IDLE)
	elif _elapsed < ALIGN_END:
		_set_stage(Stage.ALIGN)
		var t: float = clampf((_elapsed - IDLE_END) / (ALIGN_END - IDLE_END), 0.0, 1.0)
		var eased: float = t * t * (3.0 - 2.0 * t)
		global_position = _alignment_start_position.lerp(body_target.global_position, eased)
		var target_yaw: float = body_target.global_rotation.y
		rotation.y = lerp_angle(_alignment_start_yaw, target_yaw, eased)
	elif _elapsed < ACTION_END:
		_set_stage(Stage.ACTION)
		global_position = body_target.global_position
		rotation.y = body_target.global_rotation.y
		if not _action_started:
			_action_started = true
			var played: bool = visual.play_action(&"interact")
			print("[EmbodiedLab] action interact started=%s body_error=%.4f" % [played, global_position.distance_to(body_target.global_position)])
	elif _elapsed < RELEASE_END:
		if _stage != Stage.RELEASE:
			_release_start_position = global_position
		_set_stage(Stage.RELEASE)
		var t: float = clampf((_elapsed - ACTION_END) / (RELEASE_END - ACTION_END), 0.0, 1.0)
		var released_position: Vector3 = body_target.global_position - body_target.global_transform.basis.z.normalized() * 0.38
		global_position = _release_start_position.lerp(released_position, t)
	elif _elapsed < PICKUP_BEGIN:
		_set_stage(Stage.RELEASE)
	elif _elapsed < PICKUP_BEGIN + PICKUP_CASES.size() * PICKUP_CASE_SECONDS:
		_set_stage(Stage.PICKUP_REACH)
		_update_pickup_reach(_elapsed - PICKUP_BEGIN)
	else:
		_finish_pickup_sequence()
		_set_stage(Stage.DONE)

	velocity = (global_position - previous_position) / maxf(delta, 0.0001)
	if visual != null:
		visual.update_animation_blend(delta)
	if _stage == Stage.PICKUP_REACH:
		_pickup_hand_error = _measure_pickup_hand_error()
	_update_labels()


func _set_stage(next_stage: Stage) -> void:
	if _stage == next_stage:
		return
	_stage = next_stage
	if next_stage == Stage.PICKUP_REACH:
		pedestal.visible = false
		_set_target_debug_visible(false)
		_pickup_root.visible = true
		visual.abort_action()
	print("[EmbodiedLab] stage=%s" % [_stage_name()])


func _stage_name() -> String:
	match _stage:
		Stage.IDLE:
			return "1 / IDLE — locomotion owns Henry"
		Stage.ALIGN:
			return "2 / ALIGN — BODY TARGET acquired"
		Stage.ACTION:
			return "3 / ACTION — authored interact at target"
		Stage.RELEASE:
			return "4 / RELEASE — ownership returns"
		Stage.PICKUP_REACH:
			return "5 / PICKUP REACH — current clip + arm IK measured"
		_:
			return "6 / DONE — production systems still untouched"


func _update_labels() -> void:
	if stage_label != null:
		stage_label.text = _stage_name()
	if detail_label == null:
		return
	if _stage != Stage.PICKUP_REACH:
		var body_error: float = global_position.distance_to(body_target.global_position)
		detail_label.text = "green ring = BODY TARGET   amber sphere = RIGHT HAND TARGET\nbody error: %.3f m   target contract is independent from animation" % body_error
		return
	var case_name: String = "—"
	var item_height: float = 0.0
	if _pickup_case_index >= 0 and _pickup_case_index < PICKUP_CASES.size():
		case_name = String(PICKUP_CASES[_pickup_case_index]["name"])
		item_height = float((PICKUP_CASES[_pickup_case_index]["position"] as Vector3).y)
	var error_text: String = "settling" if _pickup_hand_error < 0.0 else "%.3f m" % _pickup_hand_error
	var verdict: String = "CONTACT" if _pickup_attached else ("MISS / body action needed" if _pickup_phase == &"CONTACT" else "measuring")
	detail_label.text = "test %d/%d: %s   item height %.2f m   class=%s\nhand=%s   phase=%s   hand error=%s   %s" % [
		_pickup_case_index + 1, PICKUP_CASES.size(), case_name, item_height,
		String(_pickup_action_class), String(_pickup_hand), String(_pickup_phase), error_text, verdict]


func _build_pickup_rack() -> void:
	_pickup_root = Node3D.new()
	_pickup_root.name = "PickupReachRig"
	_pickup_root.visible = false
	get_parent().add_child.call_deferred(_pickup_root)

	var rack_material := StandardMaterial3D.new()
	rack_material.albedo_color = Color(0.20, 0.23, 0.25)
	rack_material.roughness = 0.88
	for y: float in [0.52, 0.94, 1.49, 1.94, 2.28]:
		var shelf_mesh := BoxMesh.new()
		shelf_mesh.size = Vector3(1.25, 0.045, 0.34)
		shelf_mesh.material = rack_material
		var shelf := MeshInstance3D.new()
		shelf.mesh = shelf_mesh
		shelf.position = Vector3(0.0, y, 0.25)
		_pickup_root.add_child(shelf)
	for x: float in [-0.61, 0.61]:
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.05, 2.35, 0.05)
		post_mesh.material = rack_material
		var post := MeshInstance3D.new()
		post.mesh = post_mesh
		post.position = Vector3(x, 1.175, 0.37)
		_pickup_root.add_child(post)

	var can_mesh := CylinderMesh.new()
	can_mesh.top_radius = 0.045
	can_mesh.bottom_radius = 0.045
	can_mesh.height = 0.14
	can_mesh.radial_segments = 18
	var can_material := StandardMaterial3D.new()
	can_material.albedo_color = Color(0.82, 0.55, 0.16)
	can_material.metallic = 0.35
	can_material.roughness = 0.5
	can_mesh.material = can_material
	_pickup_item = MeshInstance3D.new()
	_pickup_item.name = "TestTin"
	_pickup_item.mesh = can_mesh
	_pickup_root.add_child(_pickup_item)

	if visual != null and visual.skeleton != null:
		_pickup_ik = visual.skeleton.get_node_or_null(^"DoorHand") as DoorHandIK
		if _pickup_ik != null:
			## DoorHandIK is reused only as a two-bone diagnostic solver here.
			_pickup_ik.elbow_drop = 0.18
			_pickup_ik.palm_flatten = 0.20
			_pickup_ik.wrist_back_m = 0.035


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
		_configure_pickup_hand(_pickup_hand)
		visual.play_action(&"pickup")
		if _pickup_ik != null:
			_pickup_ik.set_goal(_pickup_item.global_position, Vector3(0.0, 0.0, -1.0), 1.0)

	if case_time < PICKUP_REACH_END:
		_pickup_phase = &"REACH"
		return

	_pickup_phase = &"CONTACT"
	if not _pickup_contact_recorded:
		_pickup_contact_recorded = true
		_pickup_hand_error = _measure_pickup_hand_error()
		if _pickup_hand_error >= 0.0 and _pickup_hand_error <= PICKUP_CONTACT_TOLERANCE_M and _pickup_action_class != &"OUT_OF_REACH":
			_attach_pickup_to_hand()
		_pickup_results.append({
			"name": String(PICKUP_CASES[_pickup_case_index]["name"]),
			"height_m": (_pickup_item.global_position.y if not _pickup_attached else float((PICKUP_CASES[_pickup_case_index]["position"] as Vector3).y)),
			"action_class": String(_pickup_action_class),
			"hand": String(_pickup_hand),
			"hand_error_m": _pickup_hand_error,
			"contact": _pickup_attached,
		})
		print("[EmbodiedPickup] %s class=%s hand=%s error=%.3f contact=%s" % [
			PICKUP_CASES[_pickup_case_index]["name"], _pickup_action_class, _pickup_hand,
			_pickup_hand_error, _pickup_attached])
	if case_time >= PICKUP_CONTACT_END and _pickup_ik != null:
		_pickup_ik.release()


func _begin_pickup_case(index: int) -> void:
	_restore_pickup_item_to_rack()
	if _pickup_ik != null:
		_pickup_ik.release()
	visual.abort_action()
	_pickup_case_index = index
	_pickup_phase = &"SETUP"
	_pickup_reach_started = false
	_pickup_contact_recorded = false
	_pickup_attached = false
	_pickup_hand_error = -1.0
	var target_position := PICKUP_CASES[index]["position"] as Vector3
	_pickup_item.position = target_position
	_pickup_hand = _choose_pickup_hand(target_position)
	_pickup_action_class = _classify_pickup_height(target_position.y)


func _choose_pickup_hand(target_local: Vector3) -> StringName:
	## Generic pickup is right-dominant in the proof. A clear target on Henry's
	## left side selects the left arm. Production can later add occupied-hand rules.
	return &"LEFT" if target_local.x < -0.12 else &"RIGHT"


func _classify_pickup_height(height_m: float) -> StringName:
	if height_m < 0.25:
		return &"FLOOR_PICKUP"
	if height_m < 0.72:
		return &"LOW_PICKUP"
	if height_m < 1.28:
		return &"MID_REACH"
	if height_m < 1.78:
		return &"HIGH_REACH"
	if height_m < 2.15:
		return &"OVERHEAD_REACH"
	return &"OUT_OF_REACH"


func _configure_pickup_hand(hand: StringName) -> void:
	if _pickup_ik == null:
		return
	var suffix: String = "l" if hand == &"LEFT" else "r"
	_pickup_ik.upper_bone = StringName("upperarm_" + suffix)
	_pickup_ik.lower_bone = StringName("lowerarm_" + suffix)
	_pickup_ik.hand_bone = StringName("hand_" + suffix)
	_pickup_ik.middle_bone = StringName("middle_01_" + suffix)
	_pickup_ik.index_bone = StringName("index_01_" + suffix)
	_pickup_ik.pinky_bone = StringName("pinky_01_" + suffix)
	_pickup_ik.left_hand = hand == &"LEFT"


func _measure_pickup_hand_error() -> float:
	if visual == null or visual.skeleton == null or _pickup_item == null or _pickup_case_index < 0:
		return -1.0
	var bone_name: StringName = &"hand_l" if _pickup_hand == &"LEFT" else &"hand_r"
	var bone: int = visual.skeleton.find_bone(bone_name)
	if bone < 0:
		return -1.0
	var wrist_world: Vector3 = visual.skeleton.global_transform * visual.skeleton.get_bone_global_pose(bone).origin
	return wrist_world.distance_to(_pickup_item.global_position)


func _attach_pickup_to_hand() -> void:
	if _pickup_item == null or visual == null or visual.skeleton == null:
		return
	var bone_name: StringName = &"hand_l" if _pickup_hand == &"LEFT" else &"hand_r"
	_pickup_attachment = BoneAttachment3D.new()
	_pickup_attachment.name = "PickupProofAttachment"
	_pickup_attachment.bone_name = bone_name
	visual.skeleton.add_child(_pickup_attachment)
	_pickup_item.reparent(_pickup_attachment, true)
	_pickup_attached = true


func _restore_pickup_item_to_rack() -> void:
	if _pickup_item == null or _pickup_root == null:
		return
	if _pickup_item.get_parent() != _pickup_root:
		_pickup_item.reparent(_pickup_root, true)
	if is_instance_valid(_pickup_attachment):
		_pickup_attachment.queue_free()
	_pickup_attachment = null


func _finish_pickup_sequence() -> void:
	if _pickup_ik != null:
		_pickup_ik.release()
	visual.abort_action()
	_restore_pickup_item_to_rack()


func _set_target_debug_visible(visible: bool) -> void:
	var body_disc := body_target.get_node_or_null(^"Disc") as VisualInstance3D
	var hand_sphere := hand_target.get_node_or_null(^"Sphere") as VisualInstance3D
	if body_disc != null:
		body_disc.visible = visible
	if hand_sphere != null:
		hand_sphere.visible = visible


## Minimal methods read by the existing HenryUALAnimation component.
func get_locomotion_speed_ratio() -> float:
	return clampf(Vector2(velocity.x, velocity.z).length() / MAX_PREVIEW_SPEED, 0.0, 1.0)


func get_crouch_speed_ratio() -> float:
	return 0.0


func is_crouching() -> bool:
	return false


func get_view_direction() -> Vector3:
	return global_transform.basis.z.normalized()


func get_pickup_case_index() -> int:
	return _pickup_case_index


func get_pickup_phase() -> String:
	return String(_pickup_phase)


func get_capture_report() -> Dictionary:
	return {
		"stage": _stage_name(),
		"body_target": [body_target.global_position.x, body_target.global_position.y, body_target.global_position.z],
		"right_hand_target": [hand_target.global_position.x, hand_target.global_position.y, hand_target.global_position.z],
		"skeleton_missing": Array(_skeleton_missing),
		"skeleton_roles": HenrySkeletonContract.describe(visual.skeleton),
		"uses_existing_interact_action": true,
		"uses_existing_pickup_action": true,
		"pickup_solver_reused": "DoorHandIK (lab-only reconfiguration)",
		"pickup_contact_tolerance_m": PICKUP_CONTACT_TOLERANCE_M,
		"pickup_results": _pickup_results,
		"production_movement_replaced": false,
		"production_item_pickup_replaced": false,
	}
