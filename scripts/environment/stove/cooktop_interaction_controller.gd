class_name CooktopInteractionController
extends Node

## F over either plate -> walk to the stove -> stand at a fixed TPS work camera.
## F exits; RMB changes active plate; LMB performs exactly one contextual food action.
## No separate camera, food ownership or timer; firebox ritual retains its own F mode.
signal phase_changed(phase: Phase)
enum Phase { OUTSIDE, APPROACHING, WORKING }
const COOK_FOCUS: Vector3 = Vector3(0.09, 0.76, 0.0)
const COOK_EYE: Vector3 = Vector3(1.04, 1.62, 0.22)
const STAND_OFFSET: Vector3 = Vector3(0.94, 0.0, 0.0)
const ARRIVAL_DISTANCE: float = 0.15
const APPROACH_TIMEOUT: float = 6.0
const STALL_TIMEOUT: float = 1.2

var source: HeatSource
var _player: Player
var _phase: Phase = Phase.OUTSIDE
var _selected: int = 0
var _action_id: StringName = &""
var _ring: StoveInteractionRing
var _claim: bool = false
var _working_mode: bool = false
var _elapsed: float = 0.0
var _stall: float = 0.0
var _closest: float = INF
## Dedicated for capture script; actual sessions always read the player's inventory.
var _preview_inventory: InventoryComponent

func _ready() -> void:
	source = get_parent() as HeatSource
	set_physics_process(false)

func is_active() -> bool:
	return _phase != Phase.OUTSIDE

func get_phase() -> Phase:
	return _phase

func get_selected_index() -> int:
	return _selected

func get_selected_warmer() -> StoveWarmer:
	if source == null:
		return null
	return source.get_node_or_null(^"Warmer" if _selected == 0 else ^"Warmer2") as StoveWarmer

func select_plate(index: int) -> void:
	_selected = clampi(index, 0, 1)
	_action_id = &""
	if is_instance_valid(_ring):
		_ring.queue_redraw()


func get_actions() -> Array[Dictionary]:
	var warmer: StoveWarmer = get_selected_warmer()
	return warmer.get_cooking_actions(get_inventory()) if warmer != null else []


func get_selected_action() -> StringName:
	var options: Array[Dictionary] = get_actions()
	for a: Dictionary in options:
		if a.get("id", &"") == _action_id:
			return _action_id
	for a: Dictionary in options:
		if bool(a.get("enabled", false)):
			return StringName(a.get("id", &""))
	return &""


func cycle_action(step: int) -> void:
	var options: Array[Dictionary] = get_actions()
	var enabled: Array[StringName] = []
	for a: Dictionary in options:
		if bool(a.get("enabled", false)):
			enabled.append(StringName(a.get("id", &"")))
	if enabled.is_empty():
		_action_id = &""
		return
	var selected: int = enabled.find(get_selected_action())
	_action_id = enabled[posmod(selected + step, enabled.size())]
	if is_instance_valid(_ring):
		_ring.queue_redraw()

func get_inventory() -> InventoryComponent:
	if _preview_inventory != null:
		return _preview_inventory
	return InventoryComponent.find_in(_player) if is_instance_valid(_player) else null

func get_ring() -> StoveInteractionRing:
	return _ring

func can_enter() -> bool:
	if is_active() or source == null or _paused():
		return false
	var feed: HeatSourceFeed = source.get_node_or_null(^"Feed") as HeatSourceFeed
	if feed != null and feed.controller != null and feed.controller.is_active():
		return false
	var inputs: Node = get_node_or_null(^"/root/InputSystems")
	return inputs == null or not bool(inputs.call(&"is_interact_claimed"))

func request_enter(plate: StoveWarmer) -> void:
	if not can_enter() or plate == null or plate.get_parent() != source:
		return
	_player = get_tree().get_first_node_in_group(&"player") as Player
	if _player == null:
		return
	select_plate(0 if plate.name == "Warmer" else 1)
	var stand: Vector3 = source.to_global(STAND_OFFSET)
	if not _spot_is_free(stand):
		return
	_claim_interact(true)
	_elapsed = 0.0
	_stall = 0.0
	_closest = INF
	if _flat_distance(stand) <= ARRIVAL_DISTANCE:
		_begin_work()
	else:
		_set_phase(Phase.APPROACHING)
		_player.move_to_position(_walk_target())
		set_physics_process(true)

func request_exit() -> void:
	if _phase == Phase.OUTSIDE:
		return
	if _phase == Phase.APPROACHING and is_instance_valid(_player):
		_player.stop_moving()
	_finish_exit()

func on_interact_claimed() -> void:
	request_exit()

func on_interact_held(_duration: float) -> void:
	pass

func on_interact_released(_duration: float) -> void:
	pass

func _physics_process(delta: float) -> void:
	if _paused():
		return
	if not is_instance_valid(_player) or not is_instance_valid(source):
		_finish_exit()
		return
	if _phase != Phase.APPROACHING:
		return
	var stand: Vector3 = source.to_global(STAND_OFFSET)
	var dist: float = _flat_distance(stand)
	if dist <= ARRIVAL_DISTANCE:
		_player.stop_moving()
		_begin_work()
		return
	if not _player.is_walking_to_target():
		if dist <= ARRIVAL_DISTANCE * 2.0:
			_begin_work()
		else:
			_finish_exit()
		return
	if _player.is_action_locking():
		return
	_elapsed += delta
	if dist < _closest - 0.04:
		_closest = dist
		_stall = 0.0
	else:
		_stall += delta
	if _elapsed > APPROACH_TIMEOUT or _stall > STALL_TIMEOUT:
		_finish_exit()

func _input(event: InputEvent) -> void:
	if _phase != Phase.WORKING or _paused():
		return
	var button := event as InputEventMouseButton
	if button == null or button.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		return
	get_viewport().set_input_as_handled()
	if not button.pressed or button.is_echo():
		return
	match button.button_index:
		MOUSE_BUTTON_RIGHT: select_plate(1 - _selected)
		MOUSE_BUTTON_WHEEL_UP: cycle_action(-1)
		MOUSE_BUTTON_WHEEL_DOWN: cycle_action(1)
		MOUSE_BUTTON_LEFT: perform_selected_action()

func perform_selected_action() -> void:
	if _phase != Phase.WORKING:
		return
	perform_action(get_selected_action())


## Also called by the scriptable capture; inventory is never modified by the UI itself.
func perform_action(action_id: StringName) -> bool:
	var warmer: StoveWarmer = get_selected_warmer()
	var inventory: InventoryComponent = get_inventory()
	if warmer == null or inventory == null or action_id == &"":
		return false
	var actions: Array[Dictionary] = warmer.get_cooking_actions(inventory)
	for a: Dictionary in actions:
		if a.get("id", &"") == action_id and bool(a.get("enabled", false)):
			var ok: bool = warmer.perform_cooking_action(inventory, action_id)
			_action_id = &""
			if is_instance_valid(_ring):
				_ring.queue_redraw()
			return ok
	return false

func _begin_work() -> void:
	var state: Node = get_node_or_null(^"/root/PlayerState")
	if state != null and int(state.get("mode")) == _mode(&"ON_FOOT"):
		state.call(&"set_mode", _mode(&"WORKING"))
		_working_mode = true
	_player.call(&"face_work_target", source.to_global(COOK_FOCUS))
	_frame_camera(true)
	_show_ring(true)
	_set_phase(Phase.WORKING)
	set_physics_process(true)

func _finish_exit() -> void:
	_show_ring(false)
	_frame_camera(false)
	if _working_mode:
		_working_mode = false
		var state: Node = get_node_or_null(^"/root/PlayerState")
		if state != null and int(state.get("mode")) == _mode(&"WORKING"):
			state.call(&"set_mode", _mode(&"ON_FOOT"))
	_claim_interact(false)
	set_physics_process(false)
	_set_phase(Phase.OUTSIDE)
	_player = null

func _walk_target() -> Vector3:
	var v: Vector3 = source.to_global(STAND_OFFSET)
	v.y = _player.global_position.y
	return v

func _flat_distance(target: Vector3) -> float:
	var v: Vector3 = target - _player.global_position
	v.y = 0.0
	return v.length()

func _spot_is_free(at: Vector3) -> bool:
	var body := _player.get_node_or_null(^"Main_Collision") as CollisionShape3D
	var capsule := body.shape as CapsuleShape3D if body != null else null
	if capsule == null:
		return true
	var shape := CylinderShape3D.new()
	shape.radius = capsule.radius * 0.9
	shape.height = 0.6
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	var floor_y: float = _player.global_position.y - capsule.height * 0.5
	query.transform = Transform3D(Basis.IDENTITY, Vector3(at.x, floor_y + 0.7, at.z))
	query.exclude = [_player.get_rid()]
	query.collision_mask = _player.collision_mask
	return _player.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _frame_camera(framed: bool) -> void:
	var camera := get_viewport().get_camera_3d() as TpsCamera
	if camera == null:
		return
	if framed:
		camera.set_fixed_work_framing(source.to_global(COOK_FOCUS), source.to_global(COOK_EYE))
	else:
		camera.clear_work_framing()

func _show_ring(shown: bool) -> void:
	if shown and not is_instance_valid(_ring):
		var layer := CanvasLayer.new()
		layer.name = "CooktopRingLayer"
		layer.layer = 5
		add_child(layer)
		_ring = StoveInteractionRing.new()
		_ring.bind_cooktop(self)
		layer.add_child(_ring)
	if is_instance_valid(_ring):
		_ring.set_shown(shown)

func _claim_interact(claim: bool) -> void:
	var systems: Node = get_node_or_null(^"/root/InputSystems")
	if systems == null or claim == _claim:
		return
	_claim = claim
	systems.call(&"claim_interact" if claim else &"release_interact", self)

func _mode(name: StringName) -> int:
	var state: Node = get_node_or_null(^"/root/PlayerState")
	return int(state.get_script().get_script_constant_map().get("Mode", {}).get(String(name), -1)) if state != null else -1

func _set_phase(phase: Phase) -> void:
	if _phase != phase:
		_phase = phase
		phase_changed.emit(phase)

func _paused() -> bool:
	var state: Node = get_node_or_null(^"/root/PlayerState")
	return state != null and bool(state.call(&"is_paused"))

func _exit_tree() -> void:
	if is_active():
		_finish_exit()
