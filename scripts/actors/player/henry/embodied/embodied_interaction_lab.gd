class_name EmbodiedInteractionLabActor
extends CharacterBody3D

## Isolated proof for issue #198. Production pickup/inventory remain untouched.
## The pickup pass now has a strict acceptance rule: the arm reaches the prop,
## the fingers close around its actual cylinder volume, thumb opposes the fingers,
## and only measured fingertip contact transfers the prop to Henry's hand socket.

enum Stage { IDLE, ALIGN, ACTION, RELEASE, PICKUP_REACH, DONE }

const IDLE_END: float = 1.2
const ALIGN_END: float = 3.2
const ACTION_END: float = 5.5
const RELEASE_END: float = 7.2
const PICKUP_BEGIN: float = 7.6
const PICKUP_CASE_SECONDS: float = 3.2
const PICKUP_SETUP_END: float = 0.42
const PICKUP_REACH_END: float = 1.20
const PICKUP_GRASP_END: float = 2.05
const PICKUP_HOLD_END: float = 2.90
const ITEM_RADIUS_M: float = 0.045
const ITEM_HALF_HEIGHT_M: float = 0.07
const FINGER_SURFACE_TOLERANCE_M: float = 0.040
const MAX_PREVIEW_SPEED: float = 1.5

## Same prop and height, mirrored side/hand. This pass tests tactile ownership,
## not the vertical reach envelope from the previous rejected preview.
const PICKUP_CASES := [
	{"name": "RIGHT TACTILE GRAB", "position": Vector3(0.25, 1.42, 0.18), "hand": &"RIGHT"},
	{"name": "LEFT TACTILE GRAB", "position": Vector3(-0.25, 1.42, 0.18), "hand": &"LEFT"},
]

@onready var visual: HenryUALAnimation = $HenryUALVisual
@onready var body_target: EmbodiedTarget3D = get_node("../Targets/BodyTarget") as EmbodiedTarget3D
@onready var hand_target: EmbodiedTarget3D = get_node("../Targets/RightHandTarget") as EmbodiedTarget3D
@onready var stage_label: Label = get_node("../UILayer/Margin/VBox/Stage") as Label
@onready var detail_label: Label = get_node("../UILayer/Margin/VBox/Detail") as Label
@onready var camera: TpsCamera = get_node("../PlayerCamera") as TpsCamera
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
var _tactile_grip: TactileHandGrip
var _left_socket: BoneAttachment3D
var _right_socket: BoneAttachment3D
var _contact_markers: Dictionary = {}
var _pickup_case_index: int = -1
var _pickup_phase: StringName = &""
var _pickup_hand: StringName = &"RIGHT"
var _pickup_reach_started: bool = false
var _pickup_result_recorded: bool = false
var _pickup_attached: bool = false
var _pickup_contact_count: int = 0
var _pickup_finger_contacts: int = 0
var _pickup_thumb_contact: bool = false
var _pickup_surface_error: float = INF
var _pickup_results: Array[Dictionary] = []


func _ready() -> void:
	_alignment_start_position = global_position
	_alignment_start_yaw = rotation.y
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
		rotation.y = lerp_angle(_alignment_start_yaw, body_target.global_rotation.y, eased)
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
			return "1 / IDLE — gameplay camera owns framing"
		Stage.ALIGN:
			return "2 / ALIGN — BODY TARGET acquired"
		Stage.ACTION:
			return "3 / ACTION — authored interact at target"
		Stage.RELEASE:
			return "4 / RELEASE — ownership returns"
		Stage.PICKUP_REACH:
			return "5 / TACTILE PICKUP — object-aware fingers"
		_:
			return "6 / DONE — production pickup still untouched"


func _update_labels() -> void:
	if stage_label != null:
		stage_label.text = _stage_name()
	if detail_label == null:
		return
	if _stage != Stage.PICKUP_REACH:
		var body_error: float = global_position.distance_to(body_target.global_position)
		detail_label.text = "production TpsCamera / over-shoulder\nbody error: %.3f m" % body_error
		return
	var case_name: String = "—"
	if _pickup_case_index >= 0 and _pickup_case_index < PICKUP_CASES.size():
		case_name = String(PICKUP_CASES[_pickup_case_index]["name"])
	var error_text: String = "—" if is_inf(_pickup_surface_error) else "%.3f m" % _pickup_surface_error
	var verdict: String = "TACTILE HOLD" if _pickup_attached else ("NO CONTACT" if _pickup_phase == &"MISS" else "closing fingers")
	detail_label.text = "test %d/%d: %s   hand=%s   phase=%s\ncontacts=%d (fingers=%d thumb=%s)   best surface error=%s   %s" % [
		_pickup_case_index + 1, PICKUP_CASES.size(), case_name, String(_pickup_hand), String(_pickup_phase),
		_pickup_contact_count, _pickup_finger_contacts, _pickup_thumb_contact, error_text, verdict]


func _build_pickup_rack() -> void:
	_pickup_root = Node3D.new()
	_pickup_root.name = "PickupTactileRig"
	_pickup_root.visible = false
	get_parent().add_child.call_deferred(_pickup_root)

	var rack_material := StandardMaterial3D.new()
	rack_material.albedo_color = Color(0.20, 0.23, 0.25)
	rack_material.roughness = 0.88
	var shelf_mesh := BoxMesh.new()
	shelf_mesh.size = Vector3(1.35, 0.05, 0.38)
	shelf_mesh.material = rack_material
	var shelf := MeshInstance3D.new()
	shelf.mesh = shelf_mesh
	shelf.position = Vector3(0.0, 1.34, 0.28)
	_pickup_root.add_child(shelf)
	for x: float in [-0.66, 0.66]:
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.05, 1.75, 0.05)
		post_mesh.material = rack_material
		var post := MeshInstance3D.new()
		post.mesh = post_mesh
		post.position = Vector3(x, 0.875, 0.40)
		_pickup_root.add_child(post)

	var can_mesh := CylinderMesh.new()
	can_mesh.top_radius = ITEM_RADIUS_M
	can_mesh.bottom_radius = ITEM_RADIUS_M
	can_mesh.height = ITEM_HALF_HEIGHT_M * 2.0
	can_mesh.radial_segments = 24
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
	_pickup_ik = visual.skeleton.get_node_or_null(^"DoorHand") as DoorHandIK
	if _pickup_ik != null:
		## Reuse only the proven arm-to-wrist reach. Finger ownership is below.
		_pickup_ik.elbow_drop = 0.14
		_pickup_ik.palm_flatten = 0.35
		_pickup_ik.palm_offset_m = 0.012
		_pickup_ik.wrist_back_m = 0.035
		_pickup_ik.blend_in_rate = 8.0

	## Production sockets are deliberately created before contact, so ownership
	## transfer cannot sample a just-created/stale BoneAttachment transform.
	_left_socket = visual.get_hand_socket()
	_right_socket = visual.get_offhand_socket()

	_tactile_grip = TactileHandGrip.new()
	_tactile_grip.name = "TactileGripProof"
	visual.skeleton.add_child(_tactile_grip)
	_build_contact_markers()


func _build_contact_markers() -> void:
	for finger: String in ["index", "middle", "ring", "thumb"]:
		var marker := BoneAttachment3D.new()
		marker.name = "TactileContact_%s" % finger
		marker.bone_name = StringName("%s_03_r" % finger)
		visual.skeleton.add_child(marker)
		_contact_markers[finger] = marker


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

	_update_arm_goal()
	if case_time < PICKUP_REACH_END:
		_pickup_phase = &"REACH"
		if _tactile_grip != null:
			_tactile_grip.release()
		return

	var close_t: float = clampf((case_time - PICKUP_REACH_END) / (PICKUP_GRASP_END - PICKUP_REACH_END), 0.0, 1.0)
	close_t = close_t * close_t * (3.0 - 2.0 * close_t)
	if _tactile_grip != null:
		_tactile_grip.set_goal(_pickup_hand, _pickup_item.global_transform, ITEM_RADIUS_M, ITEM_HALF_HEIGHT_M, close_t)
	_update_tactile_metrics()

	if not _pickup_attached and close_t >= 0.72 and _pickup_thumb_contact and _pickup_finger_contacts >= 1:
		_attach_pickup_to_hand()
		_record_pickup_result(true)

	if _pickup_attached:
		_pickup_phase = &"CONTACT"
	elif case_time < PICKUP_GRASP_END:
		_pickup_phase = &"GRASP"
	else:
		_pickup_phase = &"MISS"
		if not _pickup_result_recorded:
			_record_pickup_result(false)

	## Hold the successful tactile pose long enough for the gameplay camera proof.
	if case_time >= PICKUP_HOLD_END and not _pickup_attached and _pickup_ik != null:
		_pickup_ik.release()


func _begin_pickup_case(index: int) -> void:
	_restore_pickup_item_to_rack()
	if _pickup_ik != null:
		_pickup_ik.release()
	if _tactile_grip != null:
		_tactile_grip.release()
	visual.abort_action()
	_pickup_case_index = index
	_pickup_phase = &"SETUP"
	_pickup_reach_started = false
	_pickup_result_recorded = false
	_pickup_attached = false
	_pickup_contact_count = 0
	_pickup_finger_contacts = 0
	_pickup_thumb_contact = false
	_pickup_surface_error = INF
	var case_data: Dictionary = PICKUP_CASES[index]
	_pickup_item.transform = Transform3D(Basis.IDENTITY, case_data["position"] as Vector3)
	_pickup_hand = case_data["hand"] as StringName


func _configure_pickup_hand(hand: StringName) -> void:
	var suffix: String = "l" if hand == &"LEFT" else "r"
	if _pickup_ik != null:
		_pickup_ik.upper_bone = StringName("upperarm_" + suffix)
		_pickup_ik.lower_bone = StringName("lowerarm_" + suffix)
		_pickup_ik.hand_bone = StringName("hand_" + suffix)
		_pickup_ik.middle_bone = StringName("middle_01_" + suffix)
		_pickup_ik.index_bone = StringName("index_01_" + suffix)
		_pickup_ik.pinky_bone = StringName("pinky_01_" + suffix)
		_pickup_ik.left_hand = hand == &"LEFT"
	for finger: String in _contact_markers:
		var marker := _contact_markers[finger] as BoneAttachment3D
		if marker != null:
			marker.bone_name = StringName("%s_03_%s" % [finger, suffix])


func _update_arm_goal() -> void:
	if _pickup_ik == null or _pickup_item == null:
		return
	var axis: Vector3 = _pickup_item.global_transform.basis.y.normalized()
	var outward: Vector3 = global_position + Vector3.UP * 1.25 - _pickup_item.global_position
	outward -= axis * outward.dot(axis)
	if outward.length_squared() < 0.0001:
		outward = -global_transform.basis.z
	outward = outward.normalized()
	var palm_surface: Vector3 = _pickup_item.global_position + outward * (ITEM_RADIUS_M + 0.004)
	_pickup_ik.set_goal(palm_surface, outward, 1.0)


func _update_tactile_metrics() -> void:
	_pickup_contact_count = 0
	_pickup_finger_contacts = 0
	_pickup_thumb_contact = false
	_pickup_surface_error = INF
	for finger: String in _contact_markers:
		var marker := _contact_markers[finger] as BoneAttachment3D
		if marker == null:
			continue
		var error: float = _cylinder_surface_error(marker.global_position)
		_pickup_surface_error = minf(_pickup_surface_error, error)
		var contacting: bool = error <= FINGER_SURFACE_TOLERANCE_M
		if contacting:
			_pickup_contact_count += 1
			if finger == "thumb":
				_pickup_thumb_contact = true
			else:
				_pickup_finger_contacts += 1


func _cylinder_surface_error(world_point: Vector3) -> float:
	if _pickup_item == null:
		return INF
	var p: Vector3 = _pickup_item.global_transform.affine_inverse() * world_point
	var radial: float = Vector2(p.x, p.z).length()
	var q := Vector2(radial - ITEM_RADIUS_M, absf(p.y) - ITEM_HALF_HEIGHT_M)
	var outside := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length()
	var inside: float = minf(maxf(q.x, q.y), 0.0)
	return absf(outside + inside)


func _attach_pickup_to_hand() -> void:
	if _pickup_item == null:
		return
	var socket: BoneAttachment3D = _left_socket if _pickup_hand == &"LEFT" else _right_socket
	if socket == null:
		return
	## Both sockets have existed since setup. Preserve the exact world contact pose;
	## no authored offset is allowed to teleport the proof item into the fist.
	var contact_xf: Transform3D = _pickup_item.global_transform
	_pickup_item.reparent(socket, true)
	_pickup_item.global_transform = contact_xf
	_pickup_attached = true


func _record_pickup_result(contact: bool) -> void:
	if _pickup_result_recorded:
		return
	_pickup_result_recorded = true
	var result := {
		"name": String(PICKUP_CASES[_pickup_case_index]["name"]),
		"hand": String(_pickup_hand),
		"contact": contact,
		"contacts": _pickup_contact_count,
		"finger_contacts": _pickup_finger_contacts,
		"thumb_contact": _pickup_thumb_contact,
		"best_surface_error_m": _pickup_surface_error,
		"tactile_weight": _tactile_grip.get_weight() if _tactile_grip != null else 0.0,
	}
	_pickup_results.append(result)
	print("[EmbodiedTactile] %s hand=%s contact=%s contacts=%d fingers=%d thumb=%s surface_error=%.3f" % [
		PICKUP_CASES[_pickup_case_index]["name"], _pickup_hand, contact, _pickup_contact_count,
		_pickup_finger_contacts, _pickup_thumb_contact, _pickup_surface_error])


func _restore_pickup_item_to_rack() -> void:
	if _pickup_item == null or _pickup_root == null:
		return
	if _pickup_item.get_parent() != _pickup_root:
		_pickup_item.reparent(_pickup_root, true)


func _finish_pickup_sequence() -> void:
	if _pickup_ik != null:
		_pickup_ik.release()
	if _tactile_grip != null:
		_tactile_grip.release()
	visual.abort_action()


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
	return false


func get_view_direction() -> Vector3:
	if camera != null:
		return -camera.global_transform.basis.z.normalized()
	return -global_transform.basis.z.normalized()


func get_pickup_case_index() -> int:
	return _pickup_case_index


func get_pickup_phase() -> String:
	return String(_pickup_phase)


func get_capture_report() -> Dictionary:
	return {
		"stage": _stage_name(),
		"skeleton_missing": Array(_skeleton_missing),
		"skeleton_roles": HenrySkeletonContract.describe(visual.skeleton),
		"camera": "production TpsCamera scene",
		"uses_existing_interact_action": true,
		"uses_existing_pickup_action": true,
		"arm_solver": "DoorHandIK wrist reach",
		"finger_solver": "TactileHandGrip cylinder-volume modifier",
		"contact_rule": "thumb + >=1 non-thumb fingertip within cylinder surface tolerance",
		"finger_surface_tolerance_m": FINGER_SURFACE_TOLERANCE_M,
		"pickup_results": _pickup_results,
		"production_movement_replaced": false,
		"production_item_pickup_replaced": false,
		"production_held_fit_changed": false,
	}
