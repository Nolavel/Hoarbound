extends Node

## Lab-only extreme-reach tuning for issue #198.
##
## The production DoorHandIK is intentionally a flat-surface solver. At the
## head/floor limits it fights the cylindrical grip by forcing its door-palm
## frame. The head case can be solved by reducing that ownership. The floor case
## additionally proves a body-alignment requirement: the authored kneeling clip
## lands the hand several centimetres lateral to a standing affordance target,
## so the body target must shift with stance instead of twisting fingers harder.

const FLOOR_BODY_SHIFT_M: float = 0.105

var _last_mode: StringName = &""


func _ready() -> void:
	## Henry's lab driver writes the canonical body target at priority 0. Apply the
	## stance-specific alignment afterwards, before the skeleton modifiers evaluate.
	process_priority = 100


func _process(_delta: float) -> void:
	var actor := get_node_or_null(^"../Henry") as EmbodiedInteractionLabActor
	if actor == null:
		return
	var visual := actor.get_node_or_null(^"HenryUALVisual") as HenryUALAnimation
	if visual == null or visual.skeleton == null:
		return
	var source_ik := visual.skeleton.get_node_or_null(^"DoorHand") as DoorHandIK
	var source_grip := visual.skeleton.get_node_or_null(^"TactileGripRight") as TactileHandGrip
	var receiver_ik := visual.skeleton.get_node_or_null(^"TactileHandoffIK") as DoorHandIK
	var receiver_grip := visual.skeleton.get_node_or_null(^"TactileGripLeft") as TactileHandGrip
	if source_ik == null or source_grip == null:
		return

	var handoff: String = actor.get_handoff_phase()
	if not handoff.is_empty():
		_apply_floor_body_alignment(actor)
		_apply_source(source_ik, source_grip, &"HANDOFF_SOURCE")
		if receiver_ik != null and receiver_grip != null:
			_apply_receiver(receiver_ik, receiver_grip)
		_report_mode(&"HANDOFF")
		return

	match actor.get_pickup_case_index():
		0:
			_apply_source(source_ik, source_grip, &"HEAD")
			_report_mode(&"HEAD")
		4:
			_apply_floor_body_alignment(actor)
			_apply_source(source_ik, source_grip, &"FLOOR")
			_report_mode(&"FLOOR")
		_:
			_apply_source(source_ik, source_grip, &"BASELINE")
			_report_mode(&"BASELINE")


func _apply_floor_body_alignment(actor: EmbodiedInteractionLabActor) -> void:
	## The can is authored to Henry's +X side. Moving the whole stance preserves
	## natural shoulder/elbow geometry and keeps the same shelf/item placement.
	actor.global_position += actor.global_transform.basis.x.normalized() * FLOOR_BODY_SHIFT_M


func _apply_source(ik: DoorHandIK, grip: TactileHandGrip, mode: StringName) -> void:
	if mode == &"HEAD":
		ik.elbow_drop = 0.08
		ik.palm_flatten = 0.03
		ik.wrist_back_m = 0.0
		grip.hand_orient_weight = 0.78
		grip.contact_settle_weight = 1.0
		grip.contact_iterations = 10
		grip.max_joint_step_deg = 18.0
	elif mode == &"FLOOR":
		## Once the body is actually aligned, the wrist only needs a moderate
		## cylinder correction. Stronger rotation was measurably worse for fingers.
		ik.elbow_drop = 0.08
		ik.palm_flatten = 0.04
		ik.wrist_back_m = 0.0
		grip.hand_orient_weight = 0.52
		grip.contact_settle_weight = 1.0
		grip.contact_iterations = 9
		grip.max_joint_step_deg = 16.0
	elif mode == &"HANDOFF_SOURCE":
		grip.hand_orient_weight = 0.55
		grip.contact_settle_weight = 0.95
		grip.contact_iterations = 8
		grip.max_joint_step_deg = 16.0
	else:
		ik.elbow_drop = 0.12
		ik.palm_flatten = 0.18
		ik.wrist_back_m = 0.040
		grip.hand_orient_weight = 0.35
		grip.contact_settle_weight = 0.95
		grip.contact_iterations = 7
		grip.max_joint_step_deg = 14.0


func _apply_receiver(ik: DoorHandIK, grip: TactileHandGrip) -> void:
	## Hand-off is object-to-hand, not hand-to-wall. Let the arm solve position and
	## the tactile modifier solve the opposing cylindrical grip.
	ik.elbow_drop = 0.08
	ik.palm_flatten = 0.0
	ik.wrist_back_m = 0.0
	grip.hand_orient_weight = 0.82
	grip.contact_settle_weight = 1.0
	grip.contact_iterations = 10
	grip.max_joint_step_deg = 18.0


func _report_mode(mode: StringName) -> void:
	if mode == _last_mode:
		return
	_last_mode = mode
	print("[EmbodiedLabTune] mode=%s" % String(mode))
