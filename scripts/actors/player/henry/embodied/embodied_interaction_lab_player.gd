extends "res://scripts/actors/player/henry/embodied/embodied_interaction_lab.gd"

## Player-facing policy for the embodied interaction lab.
##
## The production InteractComponent is the authority for whether F accepted a
## focused can. Reach/facing/path measurements remain visible diagnostics and
## capture metadata; they must not become a second hidden veto after F.


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _stage == Stage.MANUAL and not _item_attached:
		_refresh_manual_diagnostics()
		_update_labels()


## F has already been accepted by InteractComponent when this is called. Measure
## the stance for the report, but never silently cancel the authored action here.
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
	}
	print("[EmbodiedReadyPath] case=%s hand=%s action=%s facing=%s wrist_path=%s candidates=%s" % [
		case_data["name"], String(_active_hand), String(_active_action), facing, clear_path,
		JSON.stringify(_candidate_report)])
	_start_action(&"PICK_ACTION")


## The hand does not travel shoulder -> object. The actionable clearance segment
## is wrist -> contact; the elbow and shoulder are already represented by the
## measured two-bone chain and the authored animation.
func _rack_reach_is_clear(hand: StringName, target: Vector3) -> bool:
	var wrist := _bone_world(&"hand_l" if hand == &"LEFT" else &"hand_r")
	return _rack_safe_endpoint(wrist, target).distance_to(target) < 0.005


## Same stock TwoBoneIK3D correction as the base proof, but rack collision clamps
## the actual wrist path instead of an artificial shoulder-to-can chord.
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


func _refresh_manual_diagnostics() -> void:
	var interact := get_node_or_null(^"InteractComponent") as InteractComponent
	if interact == null or not is_instance_valid(interact.current_target) or not (interact.current_target is EmbodiedLabTarget):
		_manual_prompt = "crosshair target: NONE | aim at a can | WASD move | F pick up | Esc pause"
		return
	var lab_target := interact.current_target as EmbodiedLabTarget
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
	var action := "F PICK UP" if interact.is_target_in_reach() else "F APPROACH + PICK UP"
	_manual_prompt = "%s | chosen=%s | L reach=%.2fx %s | R reach=%.2fx %s | facing=%s | wrist path=%s | %s" % [
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
