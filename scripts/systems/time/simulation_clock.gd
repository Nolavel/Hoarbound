class_name SimulationClock
extends Node

## Canonical world-scoped game clock. Presentation observes absolute time;
## survival systems advance only through deterministic fixed-order slices.

signal clock_changed(total_hours: float, reason: StringName)
signal simulation_step_completed(context: SimulationStepContext)
signal advance_completed(total_hours: float, advanced_hours: float, reason: StringName)

const HOURS_PER_DAY: float = 24.0
const REALTIME_REASON: StringName = &"realtime"

@export_range(0.01, 1.0, 0.01) var max_step_hours: float = 0.25

var _total_hours: float = 0.0
var _simulated_total_hours: float = 0.0
var _initialized: bool = false
var _participants: Array[Dictionary] = []
var _next_order: int = 0
var _world_context: WorldContext
var _realtime_blockers: int = 0
var _realtime_step_requests: Dictionary = {}


func _ready() -> void:
	add_to_group(&"simulation_clock")


func on_world_ready(context: WorldContext) -> void:
	_world_context = context
	for system: Node in context.systems:
		register_participant(system)
	_register_subtree(context.player)


func is_initialized() -> bool:
	return _initialized


func get_total_hours() -> float:
	return _total_hours


func get_hour_of_day() -> float:
	return fmod(_total_hours, HOURS_PER_DAY)


func get_day_number() -> int:
	return floori(_total_hours / HOURS_PER_DAY) + 1


## Sets absolute time without billing simulation. Save loading uses this path.
func set_total_hours(hours: float, reason: StringName = &"load") -> bool:
	if hours < 0.0:
		return false
	_total_hours = hours
	_simulated_total_hours = hours
	_initialized = true
	clock_changed.emit(_total_hours, reason)
	return true


## Advances canonical time. Realtime keeps a partial slice buffered; explicit
## actions flush the prior realtime remainder first and end exactly on target.
func advance_hours(hours: float, reason: StringName) -> bool:
	if hours <= 0.0:
		return false
	if reason == REALTIME_REASON and _realtime_blockers > 0:
		return false
	if not _initialized:
		set_total_hours(0.0, &"implicit_start")

	if reason != REALTIME_REASON:
		_flush_partial(REALTIME_REASON)

	var before: float = _total_hours
	_total_hours += hours
	clock_changed.emit(_total_hours, reason)

	var quantum: float = _realtime_quantum() if reason == REALTIME_REASON else maxf(max_step_hours, 0.001)
	while _total_hours - _simulated_total_hours >= quantum - 0.000001:
		_dispatch_step(quantum, reason)

	if reason != REALTIME_REASON:
		_flush_partial(reason)

	advance_completed.emit(_total_hours, _total_hours - before, reason)
	return true


## Explicitly settles a buffered realtime fraction, useful before state capture.
func flush_realtime() -> void:
	_flush_partial(REALTIME_REASON)


## Controlled actions own game-time advancement while active. A counter rather
## than a bool makes nested presentation layers safe without a second clock.
func push_realtime_block() -> void:
	_flush_partial(REALTIME_REASON)
	_realtime_blockers += 1


func pop_realtime_block() -> void:
	_realtime_blockers = maxi(0, _realtime_blockers - 1)


func is_realtime_blocked() -> bool:
	return _realtime_blockers > 0


func register_participant(node: Node) -> void:
	if node == null or node == self or not SimulationParticipantCapability.ensure(node):
		return
	for entry: Dictionary in _participants:
		if entry["node"] == node:
			return
	var priority: int = SimulationParticipantCapability.priority(node)
	_participants.append({"node": node, "priority": priority, "order": _next_order})
	_next_order += 1
	_participants.sort_custom(_participant_before)


func unregister_participant(node: Node) -> void:
	for i: int in range(_participants.size() - 1, -1, -1):
		if _participants[i]["node"] == node:
			_participants.remove_at(i)


func get_participant_count() -> int:
	_prune_dead_participants()
	return _participants.size()


func _register_subtree(node: Node) -> void:
	if node == null:
		return
	register_participant(node)
	for child: Node in node.get_children():
		_register_subtree(child)


func _dispatch_step(hours: float, reason: StringName) -> void:
	if hours <= 0.0:
		return
	var start_h: float = _simulated_total_hours
	var end_h: float = start_h + hours
	var context := SimulationStepContext.new(start_h, end_h, reason)
	_simulated_total_hours = end_h

	_prune_dead_participants()
	for entry: Dictionary in _participants:
		var participant := entry["node"] as Node
		if participant != null:
			SimulationParticipantCapability.advance(participant, hours, context)
	simulation_step_completed.emit(context)


func _flush_partial(reason: StringName) -> void:
	var remainder: float = _total_hours - _simulated_total_hours
	if remainder > 0.000001:
		_dispatch_step(remainder, reason)


func _prune_dead_participants() -> void:
	for i: int in range(_participants.size() - 1, -1, -1):
		if not is_instance_valid(_participants[i]["node"]):
			_participants.remove_at(i)


func _participant_before(a: Dictionary, b: Dictionary) -> bool:
	var ap: int = int(a["priority"])
	var bp: int = int(b["priority"])
	if ap != bp:
		return ap < bp
	return int(a["order"]) < int(b["order"])


## Short visible stages can refine realtime slices without multiplying sleep/action steps.
func request_realtime_step(owner_node: Node, hours: float) -> void:
	_realtime_step_requests[owner_node.get_instance_id()] = {"owner": weakref(owner_node), "hours": maxf(hours, 0.000001)}


func release_realtime_step(owner_node: Node) -> void:
	_realtime_step_requests.erase(owner_node.get_instance_id())


func _realtime_quantum() -> float:
	var quantum: float = maxf(max_step_hours, 0.001)
	for key: int in _realtime_step_requests.keys():
		var request: Dictionary = _realtime_step_requests[key]
		if (request["owner"] as WeakRef).get_ref() == null:
			_realtime_step_requests.erase(key)
		else:
			quantum = minf(quantum, float(request["hours"]))
	return quantum
