extends "res://scripts/actors/player/henry/embodied/embodied_interaction_lab.gd"

const CONTACT_TO_HELD_SECONDS: float = 0.22
const LOW_TARGET_FOCUS_CONE_DEG: float = 28.0
const KNEE_FOCUS_RADIUS_M: float = 0.15
const FLOOR_FOCUS_RADIUS_M: float = 0.18
var _handoff_requested: bool = false

func _ready() -> void:
	super._ready()
	var interact := get_node_or_null(^"InteractComponent") as InteractComponent
	if interact != null: interact.focus_angle_deg = maxf(interact.focus_angle_deg, LOW_TARGET_FOCUS_CONE_DEG)
	_configure_low_target_focus()

func _unhandled_input(event: InputEvent) -> void:
	if not _item_attached or _stage != Stage.MANUAL or event.is_echo(): return
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_RIGHT:
		_handoff_requested = true; _begin_handoff(); get_viewport().set_input_as_handled(); return
	if event.is_action_pressed(&"drop_carried"): _start_return_from_held(); get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _item_attached and _stage == Stage.MANUAL:
		_set_hand_ik(_active_hand, _held_target(_active_hand), 0.68)
		if _pickup_phase == &"HELD": _manual_prompt = _held_prompt(); _update_labels()
		return
	if _stage == Stage.MANUAL and not _item_attached: _refresh_manual_diagnostics(); _update_labels()

func _begin_pickup_case(index: int) -> void:
	_disable_all_ik(); visual.abort_action(); _pickup_case_index = index; _pickup_phase = &"MANUAL"; _phase_time = 0.0; _action_time = 0.0; _action_started = false; _item_attached = false; _return_released = false; _active_item = _items[index]
	var case_data: Dictionary = PICKUP_CASES[index]; var contact := _contact_for(index)
	_active_hand = _select_hand(contact); _active_action = case_data["action_left"] if _active_hand == &"LEFT" else case_data["action_right"]; _body_error_m = global_position.distance_to(_active_item.global_position)
	var facing := _body_faces(contact); var clear_path := _rack_reach_is_clear(_active_hand, contact); var chosen := _candidate_report.get(String(_active_hand), {}) as Dictionary
	_body_aligned = bool(chosen.get("feasible", false)) and clear_path and facing; _stage = Stage.PICKUP; _targets[index].available = false; _manual_prompt = ""
	_cycle_results[String(case_data["name"])] = {"grasped": false, "stood_to_idle": false, "idle_presented": false, "returned": false, "released": false, "pre_facing": facing, "pre_wrist_path_clear": clear_path, "pre_measured_reach": bool(chosen.get("feasible", false))}
	print("[EmbodiedReadyPath] case=%s hand=%s action=%s facing=%s wrist_path=%s candidates=%s" % [case_data["name"], String(_active_hand), String(_active_action), facing, clear_path, JSON.stringify(_candidate_report)]); _start_action(&"PICK_ACTION")

func _update_pick_action(delta: float) -> void:
	_action_time += delta; var case_data: Dictionary = PICKUP_CASES[_pickup_case_index]; var contact_time := float(case_data["contact"]) / float(case_data["speed"]); _set_hand_ik(_active_hand, _active_contact_position(), smoothstep(contact_time - 0.28, contact_time, _action_time))
	if _item_attached or _action_time < contact_time: return
	_attach_item(_active_hand); _item_attached = true; _record_pickup_result(); visual.abort_action(); _pickup_phase = &"IDLE_PRESENT"; _phase_time = 0.0

func _update_idle_present() -> void:
	var blend := smoothstep(0.0, CONTACT_TO_HELD_SECONDS, _phase_time); _set_hand_ik(_active_hand, _active_contact_position().lerp(_held_target(_active_hand), blend), lerpf(0.92, 0.68, blend))
	if _phase_time < CONTACT_TO_HELD_SECONDS: return
	var case_data: Dictionary = PICKUP_CASES[_pickup_case_index]; var cycle: Dictionary = _cycle_results[String(case_data["name"])]; cycle["stood_to_idle"] = true; cycle["idle_presented"] = true; _stage = Stage.MANUAL; _pickup_phase = &"HELD"; _phase_time = 0.0; _manual_prompt = _held_prompt()

func _begin_handoff() -> void:
	if not _handoff_requested or not _item_attached or _stage != Stage.MANUAL: return
	_handoff_requested = false; _handoff_result = {}; super._begin_handoff()

func _update_handoff(delta: float) -> void:
	_phase_time += delta; var transfer := (_bone_world(&"upperarm_l") + _bone_world(&"upperarm_r")) * 0.5 + Vector3.DOWN * 0.24 - global_transform.basis.z * 0.25; _set_hand_ik(_handoff_source_hand, transfer, minf(1.0, _phase_time / 0.45) * 0.82)
	if _phase_time >= 0.48 and _handoff_result.is_empty(): _handoff_phase = &"RECEIVER_REACH"; _set_hand_ik(_handoff_receiver_hand, _active_item.global_position, smoothstep(0.48, 0.98, _phase_time) * 0.90)
	if _phase_time >= HANDOFF_CONTACT_SECONDS and _handoff_result.is_empty():
		_attach_item(_handoff_receiver_hand); _active_hand = _handoff_receiver_hand; _handoff_phase = &"CONTACT"; var case_data: Dictionary = PICKUP_CASES[_pickup_case_index]; var cycle: Dictionary = _cycle_results.get(String(case_data["name"]), {}) as Dictionary; _handoff_result = {"contact": true, "case": String(case_data["name"]), "source_hand": String(_handoff_source_hand), "receiver_hand": String(_handoff_receiver_hand), "receiver_arm": _arm_candidate(_handoff_receiver_hand, transfer), "transfer_height_m": transfer.y, "stood_before_transfer": bool(cycle.get("stood_to_idle", false))}
	if not _handoff_result.is_empty(): _set_hand_ik(_handoff_source_hand, transfer + global_transform.basis * Vector3(0.0, 0.0, -0.08), maxf(0.0, 0.82 - (_phase_time - HANDOFF_CONTACT_SECONDS) * 1.8)); _set_hand_ik(_handoff_receiver_hand, transfer, 0.78)
	if _phase_time >= HANDOFF_DONE_SECONDS: _stage = Stage.MANUAL; _pickup_phase = &"HELD"; _handoff_phase = &"COMPLETE"; _phase_time = 0.0; _disable_all_ik(); _manual_prompt = _held_prompt()

func _attach_item(hand: StringName) -> void:
	if visual.get_held_prop() == _active_item: visual.release_hand()
	if visual.get_offhand_prop() == _active_item: visual.release_offhand()
	if hand == &"LEFT": visual.hold_in_hand(_active_item)
	else: visual.hold_in_offhand(_active_item)

func _start_return_from_held() -> void:
	if not _item_attached or _pickup_case_index < 0 or _pickup_case_index >= PICKUP_CASES.size(): return
	var case_data: Dictionary = PICKUP_CASES[_pickup_case_index]; _active_action = case_data["action_left"] if _active_hand == &"LEFT" else case_data["action_right"]; _return_released = false; _disable_all_ik(); _stage = Stage.PICKUP; _manual_prompt = ""; _start_action(&"RETURN_ACTION")

func _update_return_action(delta: float) -> void:
	_action_time += delta; var case_data: Dictionary = PICKUP_CASES[_pickup_case_index]; var contact_time := float(case_data["contact"]) / float(case_data["speed"]); _set_hand_ik(_active_hand, _active_contact_position(), smoothstep(contact_time - 0.28, contact_time, _action_time))
	if _return_released or _action_time < contact_time: return
	_restore_active_item(); _return_released = true; var cycle: Dictionary = _cycle_results[String(case_data["name"])]; cycle["returned"] = true; cycle["released"] = true; visual.abort_action(); _disable_all_ik(); _pickup_phase = &"SETTLE"; _phase_time = 0.0

func _held_prompt() -> String:
	var case_name := "CAN"
	if _pickup_case_index >= 0 and _pickup_case_index < PICKUP_CASES.size(): case_name = String((PICKUP_CASES[_pickup_case_index] as Dictionary)["name"])
	return "%s HELD IN %s | RMB transfer hand <-> hand | G return to rack | F cannot take another can" % [case_name, String(_active_hand)]

func _rack_reach_is_clear(hand: StringName, target: Vector3) -> bool:
	return _rack_safe_endpoint(_bone_world(&"hand_l" if hand == &"LEFT" else &"hand_r"), target).distance_to(target) < 0.005

func _set_hand_ik(hand: StringName, target_position: Vector3, weight: float) -> void:
	var ik := _left_ik if hand == &"LEFT" else _right_ik; var target := _left_target if hand == &"LEFT" else _right_target; var pole := _left_pole if hand == &"LEFT" else _right_pole; var shoulder := _bone_world(&"upperarm_l" if hand == &"LEFT" else &"upperarm_r"); var elbow := _bone_world(&"lowerarm_l" if hand == &"LEFT" else &"lowerarm_r"); var wrist := _bone_world(&"hand_l" if hand == &"LEFT" else &"hand_r")
	if weight > 0.001: target_position = _rack_safe_endpoint(wrist, target_position)
	target.global_position = target_position; var reach := (target_position - shoulder).normalized(); var bend := elbow - shoulder; bend -= reach * bend.dot(reach)
	if bend.length_squared() < 0.0001: bend = global_transform.basis.x * signf(to_local(shoulder).x) + Vector3.DOWN * 0.4; bend -= reach * bend.dot(reach)
	if bend.length_squared() < 0.0001: bend = reach.cross(Vector3.UP)
	if bend.length_squared() < 0.0001: bend = reach.cross(Vector3.RIGHT)
	pole.global_position = shoulder + bend.normalized() * 0.5; ik.influence = clampf(weight, 0.0, 1.0); ik.active = ik.influence > 0.001

func _refresh_manual_diagnostics() -> void:
	var interact := get_node_or_null(^"InteractComponent") as InteractComponent
	if interact == null or not is_instance_valid(interact.current_target) or not (interact.current_target is EmbodiedLabTarget): _manual_prompt = "crosshair target: NONE | aim at a can | WASD move | F pick up | Esc pause"; return
	var lab_target := interact.current_target as EmbodiedLabTarget; var index := lab_target.case_index
	if index < 0 or index >= _items.size() or not lab_target.available: _manual_prompt = "crosshair target: unavailable"; return
	var case_data: Dictionary = PICKUP_CASES[index]; var contact := _contact_for(index); var hand := _select_hand(contact); var left := _candidate_report.get("LEFT", {}) as Dictionary; var right := _candidate_report.get("RIGHT", {}) as Dictionary; var facing := _body_faces(contact); var path_clear := _rack_reach_is_clear(hand, contact); var action := "F PICK UP" if interact.is_target_in_reach() else "F APPROACH + PICK UP"
	_manual_prompt = "%s | chosen=%s | L reach=%.2fx %s | R reach=%.2fx %s | facing=%s | wrist path=%s | %s" % [String(case_data["name"]), String(hand), float(left.get("reach_ratio", INF)), "OK" if bool(left.get("feasible", false)) else "LIMIT", float(right.get("reach_ratio", INF)), "OK" if bool(right.get("feasible", false)) else "LIMIT", "OK" if facing else "TURN", "OK" if path_clear else "BLOCKED", action]

func _contact_for(index: int) -> Vector3:
	var case_data: Dictionary = PICKUP_CASES[index]; return interaction_rig.to_global(_item_home[index].origin + Vector3.UP * float(case_data.get("grip_y", 0.0)))

func _configure_low_target_focus() -> void:
	for index: int in [3, 4]:
		if index < 0 or index >= _targets.size(): continue
		var target := _targets[index]; var case_data: Dictionary = PICKUP_CASES[index]; var marker := Marker3D.new(); marker.name = "StandingFocus_%s" % String(case_data["name"]); var lift := 0.07 if index == 3 else 0.14; marker.position = _item_home[index].origin + Vector3(0.0, lift, -0.08); interaction_rig.add_child(marker); target.focus_anchor = marker
		for child: Node in target.get_children():
			var collision := child as CollisionShape3D
			if collision == null: continue
			var sphere := SphereShape3D.new(); sphere.radius = KNEE_FOCUS_RADIUS_M if index == 3 else FLOOR_FOCUS_RADIUS_M; collision.shape = sphere; break
