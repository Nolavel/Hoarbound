class_name RestComponent
extends Node

## Henry sitting on a RestSpot. Sitting gives no bonus: the stove warms and dries.
## Seated, F uses what is at arm's length (food on the table), else waits; Esc or
## any move stands him up. Pack left, Kenny right.

signal sat_down(spot: Node3D)
signal stood_up

## Seconds the reason a wait ended early stays up.
const RESULT_SECONDS: float = 3.0
const WAIT_ACTION: StringName = &"interact"
const STAND_ACTIONS: Array[StringName] = [&"pause", &"move_forward", &"move_backward",
	&"move_left", &"move_right", &"jump"]
## Where the pack and Kenny are set down, in the seat's space (-Z faces the stove).
const PACK_SPOT: Vector3 = Vector3(-0.62, 0.0, 0.05)
const KENNY_SPOT: Vector3 = Vector3(0.62, 0.0, 0.05)

var _spot: Node3D
var _status_label: Label
var _table: MealTable


func is_sitting() -> bool:
	return is_instance_valid(_spot)


## Sits on a spot: Henry moves onto its seat and faces its forward (-Z).
func sit(spot: Node3D) -> bool:
	var body := get_parent() as CharacterBody3D
	var visual: HenryUALAnimation = _visual()
	if is_sitting() or body == null or spot == null or body.velocity.y < -0.5:
		return false
	if visual != null and visual.is_carrying():
		return false
	for child: Node in body.get_children():
		if child.has_method(&"is_holding") and bool(child.call(&"is_holding")):
			if not child.has_method(&"put_away_unlit") or not bool(child.call(&"put_away_unlit")):
				return false
	_spot = spot
	body.velocity = Vector3.ZERO
	var facing: Vector3 = -spot.global_transform.basis.z
	facing.y = 0.0
	body.global_position = Vector3(spot.global_position.x, body.global_position.y, spot.global_position.z)
	if facing.length() > 0.01:
		body.rotation.y = atan2(-facing.x, -facing.z)
	body.reset_physics_interpolation()
	if visual != null:
		visual.set_sitting(true)
		visual.set_pack_down(spot.global_transform * Transform3D(Basis(Vector3.UP, 0.4), PACK_SPOT),
			spot.global_transform * Transform3D(Basis(Vector3.UP, PI * 0.5), KENNY_SPOT))  # faces the pack
	_table = MealTable.near(get_tree(), spot.global_position) if is_inside_tree() else null
	if _table != null:
		_table.lay_out(InventoryComponent.find_in(body), body.get_node_or_null(^"EquipmentComponent") as EquipmentComponent)
	sat_down.emit(spot)
	return true


func stand() -> bool:
	if not is_sitting():
		return false
	_spot = null
	var visual: HenryUALAnimation = _visual()
	if visual != null:
		visual.set_sitting(false)
		visual.pick_pack_up()
	if is_instance_valid(_table):
		_table.clear()
	_table = null
	stood_up.emit()
	return true


## Before InteractComponent hears F, so F waits instead of re-triggering the spot.
## While the hours prompt is open it owns the keys.
func _input(event: InputEvent) -> void:
	if not is_sitting() or event.is_echo() or _prompt_open():
		return
	if InputMap.has_action(WAIT_ACTION) and event.is_action_pressed(WAIT_ACTION):
		if _reachable_target() != null:
			return  # F belongs to the thing in front of Henry (food on the table)
		open_wait()
		get_viewport().set_input_as_handled()
		return
	for action: StringName in STAND_ACTIONS:
		if InputMap.has_action(action) and event.is_action_pressed(action):
			stand()
			if action == &"pause":
				get_viewport().set_input_as_handled()
			return


## What F would act on at arm's length, other than the seat itself.
func _reachable_target() -> InteractiveArea:
	var body: Node = get_parent()
	var interact := body.get_node_or_null(^"InteractComponent") as InteractComponent if body != null else null
	if interact == null:
		return null
	var target: InteractiveArea = interact.get_active_target()
	if target == null or target is RestSpot or not interact.is_active_target_in_reach():
		return null
	return target


## Opens the hours prompt in wait mode; false when there is none (headless).
func open_wait() -> bool:
	var prompt := _prompt()
	if prompt == null or not prompt.request_wait():
		return false
	var sleep: SleepController = prompt.sleep_controller
	if sleep != null and not sleep.wait_completed.is_connected(_on_wait_completed):
		sleep.wait_completed.connect(_on_wait_completed)
	return true


## Says why a wait ended before the chosen hours, then returns to the seated hint.
func _on_wait_completed(_hours: float, ended_early_key: String) -> void:
	if ended_early_key == "":
		return
	_show_status(ended_early_key)


func _prompt() -> SleepPrompt:
	return get_tree().get_first_node_in_group(SleepPrompt.GROUP) as SleepPrompt if is_inside_tree() else null


func _prompt_open() -> bool:
	var prompt := _prompt()
	return prompt != null and prompt.is_open()


func _visual() -> HenryUALAnimation:
	var body: Node = get_parent()
	return body.get_node_or_null(^"HenryUALVisual") as HenryUALAnimation if body != null else null


## A short result message is still allowed here; the persistent control grammar
## is owned by KeyHintsPanel so seated controls are not duplicated.
func _show_status(key: String) -> void:
	if not is_inside_tree():
		return
	if _status_label == null:
		var layer := CanvasLayer.new()
		layer.layer = 15
		add_child(layer)
		_status_label = Label.new()
		_status_label.anchor_left = 0.5
		_status_label.anchor_right = 0.5
		_status_label.anchor_top = 0.88
		_status_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		layer.add_child(_status_label)
	_status_label.text = tr(key)
	_status_label.visible = true
	get_tree().create_timer(RESULT_SECONDS).timeout.connect(func() -> void:
		if is_instance_valid(_status_label):
			_status_label.visible = false)
