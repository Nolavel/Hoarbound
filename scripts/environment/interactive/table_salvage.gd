class_name TableSalvage
extends InteractiveArea

## An explicit hammer-in-hand choice converts a wooden table into one saved log pile.
const WORK_SECONDS: float = 4.0

@export var table_owner: Node3D
@export var world_id: StringName = &""
@export var yield_count: int = 3
@export var floor_y: float = 0.0
## Game-time price is tuning, separate from the four-second presentation.
@export_range(0.1, 60.0, 0.1) var time_cost_minutes: float = 2.0

var _destroyed: bool = false
var _work_left: float = 0.0
var _logs: ItemPickup
var _solid_layers: Dictionary = {}
var _action_managed: bool = false
var _action_id: StringName = &""


func _ready() -> void:
	object_on_ground = false
	auto_detect_ground = false
	player_animation_action = &"none"
	if table_owner == null:
		table_owner = get_parent() as Node3D
	if world_id == &"":
		world_id = StringName(table_owner.get_path())
	for body: Node in table_owner.find_children("*", "StaticBody3D", true, false):
		focus_bodies.append(body as CollisionObject3D)
		_solid_layers[body] = (body as StaticBody3D).collision_layer
	super()
	add_to_group(&"saveable")
	set_item_name(tr("TABLE_BREAK_ACTION"))


func wants_break() -> bool:
	var hammer: HammerComponent = _hammer()
	return not table_owner is MealTable and not _destroyed and hammer != null and hammer.is_holding()


func can_interact() -> bool:
	return super() and wants_break() and _work_left <= 0.0 and not _is_seated()


func _get_interaction_text() -> String:
	set_description(tr("TABLE_CLEAR_FIRST") if _has_supplies() else tr("TABLE_BREAK_WARNING") % yield_count)
	return "[%s] %s" % [_interact_key_label(), tr("TABLE_BREAK_ACTION")]


func _on_interaction_performed() -> void:
	if _has_supplies():
		show_message(tr("TABLE_CLEAR_FIRST"))
		return
	if not wants_break() or _work_left > 0.0 or _is_seated():
		return
	_work_left = WORK_SECONDS
	var player: Node = _player()
	if player != null:
		InteractHostCapability.run(player, &"hold", [WORK_SECONDS])
		InteractHostCapability.run(player, &"animate", [&"fix"])
	_hammer().swing()

	var actions: TimeCostedActionSystem = _actions()
	if actions != null:
		var request := TimeActionRequest.new()
		_action_id = StringName("dismantle:%d" % get_instance_id())
		request.action_id = _action_id
		request.duration_hours = time_cost_minutes / 60.0
		request.presentation_seconds = WORK_SECONDS
		request.reason = &"dismantle"
		request.actor = player
		request.target = self
		request.player_mode = _resolve_player_mode(&"WORKING")
		request.stop_check = _work_stop_reason
		request.on_complete = _work_action_completed
		request.on_cancel = _work_action_cancelled
		_action_managed = actions.start_action(request)
		if not _action_managed:
			_work_left = 0.0


func _process(delta: float) -> void:
	if _work_left <= 0.0:
		return
	if _action_managed:
		var actions: TimeCostedActionSystem = _actions()
		if actions != null and actions.get_active_action_id() == _action_id:
			_work_left = WORK_SECONDS * (1.0 - actions.get_progress())
		return
	_action_managed = false
	_work_left -= delta
	if _work_left <= 0.0:
		_destroy()


func _work_stop_reason() -> StringName:
	if not wants_break():
		return &"tool_lost"
	if _is_seated():
		return &"seated"
	return &""


func _work_action_completed(_elapsed_h: float) -> void:
	_action_managed = false
	_work_left = 0.0
	_destroy()


func _work_action_cancelled(_elapsed_h: float, _reason: StringName) -> void:
	_action_managed = false
	_work_left = 0.0


func _resolve_player_mode(mode_name: StringName) -> int:
	var state: Node = get_node_or_null(^"/root/PlayerState")
	if state == null:
		return -1
	var script: Script = state.get_script() as Script
	if script == null:
		return -1
	var constants: Dictionary = script.get_script_constant_map()
	var modes: Dictionary = constants.get("Mode", {})
	return int(modes.get(String(mode_name), -1))


func _actions() -> TimeCostedActionSystem:
	return TimeCostedActionSystem.find(get_tree()) if is_inside_tree() else null


func _destroy() -> void:
	_destroyed = true
	table_owner.visible = false
	for body: Node in table_owner.find_children("*", "StaticBody3D", true, false):
		(body as StaticBody3D).collision_layer = 0
	var pile_id := StringName("%s:logs" % world_id)
	var ledger: PickupLedger = PickupLedger.find(get_tree())
	if ledger != null and ledger.is_taken(pile_id):
		if is_instance_valid(_logs) and not _logs.is_queued_for_deletion():
			_logs.queue_free()
		_logs = null
		return
	if is_instance_valid(_logs) and not _logs.is_queued_for_deletion():
		return
	var pile := ItemPickup.new()
	_logs = pile
	pile.name = "SalvagedLogs"
	pile.item_id = &"firewood"
	pile.world_id = pile_id
	pile.count = yield_count
	var shape := SphereShape3D.new()
	shape.radius = 0.5
	var collision := CollisionShape3D.new()
	collision.shape = shape
	pile.add_child(collision)
	table_owner.get_parent().add_child(pile)
	pile.global_position = table_owner.to_global(Vector3(0, floor_y + 0.025, 0.55))


func get_save_key() -> StringName:
	return StringName("furniture:%s" % world_id)


func get_save_data() -> Dictionary:
	return {"destroyed": _destroyed}


func load_save_data(data: Dictionary) -> void:
	_work_left = 0.0
	if bool(data.get("destroyed", false)):
		_destroy()
		call_deferred(&"_finish_restore")
	elif _destroyed:
		_destroyed = false
		table_owner.visible = true
		for body: StaticBody3D in _solid_layers:
			body.collision_layer = int(_solid_layers[body])
		if is_instance_valid(_logs):
			_logs.queue_free()
		_logs = null


## The pickup ledger may be restored after furniture in the same save pass.
func _finish_restore() -> void:
	if _destroyed:
		_destroy()


func _has_supplies() -> bool:
	for node: Node in get_tree().get_nodes_in_group(ItemPickup.WORLD_GROUP):
		var pickup := node as ItemPickup
		if pickup == null or pickup.is_queued_for_deletion():
			continue
		var local: Vector3 = table_owner.to_local(pickup.global_position)
		if absf(local.x) < 1.0 and absf(local.z) < 0.4 and local.y > 0.4 and local.y < 1.2:
			return true
	return false


func _player() -> Node:
	return get_tree().get_first_node_in_group(&"player")


func _hammer() -> HammerComponent:
	var player: Node = _player()
	return player.get_node_or_null(^"HammerComponent") as HammerComponent if player != null else null


func _is_seated() -> bool:
	var player: Node = _player()
	var rest: RestComponent = player.get_node_or_null(^"RestComponent") as RestComponent if player != null else null
	return rest != null and rest.is_sitting()
