extends "res://scripts/actors/player/henry/embodied/embodied_interaction_lab.gd"

## Player-facing policy for the embodied interaction lab.
##
## Production InteractComponent owns F acceptance. The lab owns only the
## presentation: authored standing pickup, crouch-preserving low reach,
## persistent held state, hand transfer and return.
##
## The lab adds a hard body-clearance plane on top of production targeting.
## Hands may reach into the rack; Henry's core may not pass through it.

const CONTACT_TO_HELD_SECONDS: float = 0.22
const LOW_CROUCH_REACH_SECONDS: float = 0.34
const DEFAULT_FOCUS_RADIUS_M: float = 0.18
const FLOOR_FOCUS_RADIUS_M: float = 0.22
const RACK_FRONT_LOCAL_Z: float = RACK_Z_M - 0.20
const BODY_CLEARANCE_M: float = 0.08
const BODY_GUARD_BONES: Array[StringName] = [&"pelvis", &"spine_01", &"spine_03", &"Head"]

var _handoff_requested: bool = false
var _low_reach_start: Vector3 = Vector3.ZERO
var _clearance_push_total_m: float = 0.0


func _ready() -> void:
	super._ready()
	_configure_target_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not _item_attached or _stage != Stage.MANUAL or event.is_echo():
		return
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_RIGHT:
		_handoff_requested = true
		_begin_handoff()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"drop_carried"):
		_start_return_from_held()
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _stage == Stage.PICKUP:
		## Animation may lean after its first frame. Enforce the rack plane every
		## physics tick, after the skeleton has evaluated the current action pose.
		if not _enforce_rack_body_clearance():
			_abort_for_rack_clearance()
			_update_labels()
			return
	if _item_attached and _stage == Stage.MANUAL:
		## Persistent held state must not keep TwoBoneIK alive. The prop is already
		## on hand_l/hand_r, so the normal idle/crouch animation owns wrist rotation.
		_disable_all_ik()
		if _pickup_phase == &"HELD":
			_manual_prompt = _held_prompt()
			_update_labels()
		return
	if _stage == Stage.MANUAL and not _item_attached:
		_refresh_manual_diagnostics()
		_update_labels()


func _begin_pickup_case(index: int) -> void:
	_disable_all_ik()
	visual.abort_action()
	_pickup_case_index = index
	_pickup_phase = &"MANUAL"
	_phase_time = 0.0
	_action_time = 0.0
	_action_started = false
	_item_attached = false
	_return_released = false
	_clearance_push_total_m = 0.0
	_active_item = _items[index]
	var case_data: Dictionary = PICKUP_CASES[index]
	var contact := _contact_for(index)
	_active_hand = _select_hand(contact)
	_active_action = case_data["action_left"] if _active_hand == &"LEFT" else case_data["action_right"]
	_body_error_m = global_position.distance_to(_active_item.global_position)
	var facing := _body_faces(contact)
	var clear_path := _rack_reach_is_clear(_active_hand, contact)
	var chosen := _candidate_report.get(String(_active_hand), {}) as Dictionary
	_body_aligned = bool(chosen.get("feasible", false)) and clear_path and facing

	_stage = Stage.PICKUP
	_targets[index].available = false
	_manual_prompt = ""
	_cycle_results[String(case_data["name"])] = {
		"grasped": false,
		"stood_to_idle": false,
		"idle_presented": false,
		"returned": false,
		"released": false,
		"pre_facing": facing,
		"pre_wrist_path_clear": clear_path,
		"pre_measured_reach": bool(chosen.get("feasible", false)),
		"crouch_preserved": is_crouching() and _is_low_case(index),
	}
	print("[EmbodiedReadyPath] case=%s hand=%s action=%s facing=%s wrist_path=%s crouch=%s candidates=%s" % [
		case_data["name"], String(_active_hand), String(_active_action), facing, clear_path,
		is_crouching(), JSON.stringify(_candidate_report)])

	## Neutral pose must already respect the rack plane. If there is free space
	## behind Henry the guard makes the tiny corrective step before the action.
	if not _enforce_rack_body_clearance():
		_abort_for_rack_clearance()
		return
	if is_crouching() and _is_low_case(index):
		_low_reach_start = _bone_world(&"hand_l" if _active_hand == &"LEFT" else &"hand_r")
		_pickup_phase = &"CROUCH_PICK"
		_phase_time = 0.0
		velocity = Vector3.ZERO
		return
	_start_action(&"PICK_ACTION")


func _update_pickup(delta: float) -> void:
	match _pickup_phase:
		&"CROUCH_PICK":
			_update_crouch_pick(delta)
		&"CROUCH_RETURN":
			_update_crouch_return(delta)
		_:
			super._update_pickup(delta)


func _update_crouch_pick(delta: float) -> void:
	_phase_time += delta
	var t := smoothstep(0.0, LOW_CROUCH_REACH_SECONDS, _phase_time)
	_set_hand_ik(_active_hand, _low_reach_start.lerp(_active_contact_position(), t), t * 0.92)
	if t < 1.0:
		return
	_attach_item(_active_hand)
	_item_attached = true
	_record_pickup_result()
	_pickup_phase = &"IDLE_PRESENT"
	_phase_time = 0.0


## Standing authored actions are cut at physical contact. Their recovery tails
## are wrong once the prop has already moved onto the hand socket.
func _update_pick_action(delta: float) -> void:
	_action_time += delta
	var case_data: Dictionary = PICKUP_CASES[_pickup_case_index]
	var contact_time := float(case_data["contact"]) / float(case_data["speed"])
	var contact_weight := smoothstep(contact_time - 0.28, contact_time, _action_time)
	_set_hand_ik(_active_hand, _active_contact_position(), contact_weight)
	if _item_attached or _action_time < contact_time:
		return
	_attach_item(_active_hand)
	_item_attached = true
	_record_pickup_result()
	visual.abort_action()
	_pickup_phase = &"IDLE_PRESENT"
	_phase_time = 0.0


func _update_idle_present() -> void:
	var blend := smoothstep(0.0, CONTACT_TO_HELD_SECONDS, _phase_time)
	var target := _active_contact_position().lerp(_held_target(_active_hand), blend)
	_set_hand_ik(_active_hand, target, lerpf(0.92, 0.68, blend))
	if _phase_time < CONTACT_TO_HELD_SECONDS:
		return
	var case_data: Dictionary = PICKUP_CASES[_pickup_case_index]
	var cycle: Dictionary = _cycle_results[String(case_data["name"])]
	cycle["stood_to_idle"] = true
	cycle["idle_presented"] = true
	cycle["rack_clearance_push_m"] = _clearance_push_total_m
	_disable_all_ik()
	_stage = Stage.MANUAL
	_pickup_phase = &"HELD"
	_phase_time = 0.0
	_manual_prompt = _held_prompt()


func _begin_handoff() -> void:
	if not _handoff_requested or not _item_attached or _stage != Stage.MANUAL:
		return
	_handoff_requested = false
	_handoff_result = {}
	super._begin_handoff()


func _update_handoff(delta: float) -> void:
	_phase_time += delta
	var left_shoulder := _bone_world(&"upperarm_l")
	var right_shoulder := _bone_world(&"upperarm_r")
	var transfer := (left_shoulder + right_shoulder) * 0.5 \
		+ Vector3.DOWN * 0.24 - global_transform.basis.z * 0.25
	_set_hand_ik(_handoff_source_hand, transfer, minf(1.0, _phase_time / 0.45) * 0.82)
	if _phase_time >= 0.48 and _handoff_result.is_empty():
		_handoff_phase = &"RECEIVER_REACH"
		_set_hand_ik(_handoff_receiver_hand, _active_item.global_position, smoothstep(0.48, 0.98, _phase_time) * 0.90)
	if _phase_time >= HANDOFF_CONTACT_SECONDS and _handoff_result.is_empty():
		_attach_item(_handoff_receiver_hand)
		_active_hand = _handoff_receiver_hand
		_handoff_phase = &"CONTACT"
		var receiver_arm := _arm_candidate(_handoff_receiver_hand, transfer)
		var case_data: Dictionary = PICKUP_CASES[_pickup_case_index]
		var cycle: Dictionary = _cycle_results.get(String(case_data["name"]), {}) as Dictionary
		_handoff_result = {
			"contact": true,
			"case": String(case_data["name"]),
			"source_hand": String(_handoff_source_hand),
			"receiver_hand": String(_handoff_receiver_hand),
			"receiver_arm": receiver_arm,
			"transfer_height_m": transfer.y,
			"stood_before_transfer": bool(cycle.get("stood_to_idle", false)),
		}
	if not _handoff_result.is_empty():
		_set_hand_ik(_handoff_source_hand, transfer + global_transform.basis * Vector3(0.0, 0.0, -0.08), maxf(0.0, 0.82 - (_phase_time - HANDOFF_CONTACT_SECONDS) * 1.8))
		_set_hand_ik(_handoff_receiver_hand, transfer, 0.78)
	if _phase_time >= HANDOFF_DONE_SECONDS:
		_stage = Stage.MANUAL
		_pickup_phase = &"HELD"
		_handoff_phase = &"COMPLETE"
		_phase_time = 0.0
		_disable_all_ik()
		_manual_prompt = _held_prompt()


func _attach_item(hand: StringName) -> void:
	if visual.get_held_prop() == _active_item:
		visual.release_hand()
	if visual.get_offhand_prop() == _active_item:
		visual.release_offhand()
	if hand == &"LEFT":
		visual.hold_in_hand(_active_item)
	else:
		visual.hold_in_offhand(_active_item)


func _start_return_from_held() -> void:
	if not _item_attached or _pickup_case_index < 0 or _pickup_case_index >= PICKUP_CASES.size():
		return
	var case_data: Dictionary = PICKUP_CASES[_pickup_case_index]
	_active_action = case_data["action_left"] if _active_hand == &"LEFT" else case_data["action_right"]
	_return_released = false
	_clearance_push_total_m = 0.0
	_disable_all_ik()
	_stage = Stage.PICKUP
	_manual_prompt = ""
	if not _enforce_rack_body_clearance():
		_abort_for_rack_clearance()
		return
	if is_crouching() and _is_low_case(_pickup_case_index):
		_low_reach_start = _bone_world(&"hand_l" if _active_hand == &"LEFT" else &"hand_r")
		_pickup_phase = &"CROUCH_RETURN"
		_phase_time = 0.0
		return
	_start_action(&"RETURN_ACTION")


func _update_crouch_return(delta: float) -> void:
	_phase_time += delta
	var t := smoothstep(0.0, LOW_CROUCH_REACH_SECONDS, _phase_time)
	_set_hand_ik(_active_hand, _low_reach_start.lerp(_active_contact_position(), t), t * 0.92)
	if t < 1.0:
		return
	_restore_active_item()
	_return_released = true
	var case_data: Dictionary = PICKUP_CASES[_pickup_case_index]
	var cycle: Dictionary = _cycle_results[String(case_data["name"])]
	cycle["returned"] = true
	cycle["released"] = true
	cycle["rack_clearance_push_m"] = _clearance_push_total_m
	_disable_all_ik()
	_pickup_phase = &"SETTLE"
	_phase_time = 0.0


func _update_return_action(delta: float) -> void:
	_action_time += delta
	var case_data: Dictionary = PICKUP_CASES[_pickup_case_index]
	var contact_time := float(case_data["contact"]) / float(case_data["speed"])
	var contact_weight := smoothstep(contact_time - 0.28, contact_time, _action_time)
	_set_hand_ik(_active_hand, _active_contact_position(), contact_weight)
	if _return_released or _action_time < contact_time:
		return
	_restore_active_item()
	_return_released = true
	var cycle: Dictionary = _cycle_results[String(case_data["name"])]
	cycle["returned"] = true
	cycle["released"] = true
	cycle["rack_clearance_push_m"] = _clearance_push_total_m
	visual.abort_action()
	_disable_all_ik()
	_pickup_phase = &"SETTLE"
	_phase_time = 0.0


func _held_prompt() -> String:
	var case_name := "CAN"
	if _pickup_case_index >= 0 and _pickup_case_index < PICKUP_CASES.size():
		case_name = String((PICKUP_CASES[_pickup_case_index] as Dictionary)["name"])
	return "%s HELD IN %s | RMB transfer hand <-> hand | G return to rack | F cannot take another can" % [
		case_name, String(_active_hand)]


func _rack_reach_is_clear(hand: StringName, target: Vector3) -> bool:
	var wrist := _bone_world(&"hand_l" if hand == &"LEFT" else &"hand_r")
	return _rack_safe_endpoint(wrist, target).distance_to(target) < 0.005


func _set_hand_ik(hand: StringName, target_position: Vector3, weight: float) -> void:
	var ik := _left_ik if hand == &"LEFT" else _right_ik
	var target := _left_target if hand == &"LEFT" else _right_target
	var pole := _left_pole if hand == &"LEFT" else _right_pole
	var shoulder := _bone_world(&"upperarm_l" if hand == &"LEFT" else &"upperarm_r")
	var elbow := _bone_world(&"lowerarm_l" if hand == &"LEFT" else &"lowerarm_r")
	var wrist := _bone_world(&"hand_l" if hand == &"LEFT" else &"hand_r")
	if weight > 0.001:
		target_position = _rack_safe_endpoint(wrist, target_position)
	target.global_position = target_position
	var reach := (target_position - shoulder).normalized()
	var bend := elbow - shoulder
	bend -= reach * bend.dot(reach)
	if bend.length_squared() < 0.0001:
		bend = global_transform.basis.x * signf(to_local(shoulder).x) + Vector3.DOWN * 0.4
		bend -= reach * bend.dot(reach)
	if bend.length_squared() < 0.0001:
		bend = reach.cross(Vector3.UP)
	if bend.length_squared() < 0.0001:
		bend = reach.cross(Vector3.RIGHT)
	pole.global_position = shoulder + bend.normalized() * 0.5
	ik.influence = clampf(weight, 0.0, 1.0)
	ik.active = ik.influence > 0.001


## Keep the core silhouette out of the shelf volume while still allowing hands
## and forearms to reach in. This is evaluated in rack-local space, so it does
## not depend on the world orientation of the test scene.
func _enforce_rack_body_clearance() -> bool:
	if visual == null or visual.skeleton == null:
		return true
	var limit_z := RACK_FRONT_LOCAL_Z - BODY_CLEARANCE_M
	var max_core_z := -INF
	for bone_name: StringName in BODY_GUARD_BONES:
		max_core_z = maxf(max_core_z, interaction_rig.to_local(_bone_world(bone_name)).z)
	if max_core_z <= limit_z + 0.002:
		return true
	var correction := max_core_z - limit_z
	var local_position := interaction_rig.to_local(global_position)
	var desired_local := local_position
	desired_local.z -= correction
	var motion := interaction_rig.to_global(desired_local) - global_position
	motion.y = 0.0
	if motion.length_squared() > 0.000001:
		var before := global_position
		move_and_collide(motion)
		_clearance_push_total_m += before.distance_to(global_position)
	max_core_z = -INF
	for bone_name: StringName in BODY_GUARD_BONES:
		max_core_z = maxf(max_core_z, interaction_rig.to_local(_bone_world(bone_name)).z)
	return max_core_z <= limit_z + 0.01


func _abort_for_rack_clearance() -> void:
	visual.abort_action()
	_disable_all_ik()
	velocity = Vector3.ZERO
	if _item_attached:
		_stage = Stage.MANUAL
		_pickup_phase = &"HELD"
		_manual_prompt = "RACK BLOCKED: no safe body clearance behind Henry | item stays held | step back, then G to return"
		return
	if _pickup_case_index >= 0 and _pickup_case_index < _targets.size():
		_targets[_pickup_case_index].available = true
	_stage = Stage.MANUAL
	_pickup_phase = &"RACK_BLOCKED"
	_manual_prompt = "RACK BLOCKED: Henry cannot keep torso outside the shelf | step back slightly and press F again"


func _refresh_manual_diagnostics() -> void:
	var interact := get_node_or_null(^"InteractComponent") as InteractComponent
	if interact == null or not (interact.get_active_target() is EmbodiedLabTarget):
		_manual_prompt = "SOFT TARGET: aim near a can, not pixel-perfect centre | highlighted can = active | F pick up | WASD move"
		return
	var lab_target := interact.get_active_target() as EmbodiedLabTarget
	var index := lab_target.case_index
	if index < 0 or index >= _items.size() or not lab_target.available:
		_manual_prompt = "crosshair target: unavailable"
		return
	var case_data: Dictionary = PICKUP_CASES[index]
	var contact := _contact_for(index)
	var hand := _select_hand(contact)
	var left := _candidate_report.get("LEFT", {}) as Dictionary
	var right := _candidate_report.get("RIGHT", {}) as Dictionary
	var facing := _body_faces(contact)
	var path_clear := _rack_reach_is_clear(hand, contact)
	var action := "F PICK UP" if interact.is_active_target_in_reach() else "F APPROACH + PICK UP"
	_manual_prompt = "LOCKED %s | chosen=%s | L reach=%.2fx %s | R reach=%.2fx %s | facing=%s | wrist path=%s | %s" % [
		String(case_data["name"]),
		String(hand),
		float(left.get("reach_ratio", INF)), "OK" if bool(left.get("feasible", false)) else "LIMIT",
		float(right.get("reach_ratio", INF)), "OK" if bool(right.get("feasible", false)) else "LIMIT",
		"OK" if facing else "TURN",
		"OK" if path_clear else "BLOCKED",
		action,
	]


func _contact_for(index: int) -> Vector3:
	var case_data: Dictionary = PICKUP_CASES[index]
	return interaction_rig.to_global(_item_home[index].origin + Vector3.UP * float(case_data.get("grip_y", 0.0)))


func _is_low_case(index: int) -> bool:
	return index >= 3


## Give every can a front-biased focus point and a small trigger volume.
## InteractComponent's score and line of sight decide which can wins.
func _configure_target_focus() -> void:
	for index: int in range(_targets.size()):
		var target := _targets[index]
		var case_data: Dictionary = PICKUP_CASES[index]
		var marker := Marker3D.new()
		marker.name = "SoftFocus_%s" % String(case_data["name"])
		var lift := 0.04
		if index == 3:
			lift = 0.07
		elif index == 4:
			lift = 0.14
		marker.position = _item_home[index].origin + Vector3(0.0, lift, -0.07)
		interaction_rig.add_child(marker)
		target.focus_anchor = marker
		for child: Node in target.get_children():
			var collision := child as CollisionShape3D
			if collision == null:
				continue
			var sphere := SphereShape3D.new()
			sphere.radius = FLOOR_FOCUS_RADIUS_M if index == 4 else DEFAULT_FOCUS_RADIUS_M
			collision.shape = sphere
			break
