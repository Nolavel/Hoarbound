class_name TimeCostedActionSystem
extends Node

## One lifecycle for long survival actions. It owns elapsed game time, progress
## and cancellation; inventory/recipes/world mutations stay with gameplay owners.

signal action_started(action_id: StringName, duration_h: float)
signal action_progress(action_id: StringName, progress: float)
signal action_completed(action_id: StringName, elapsed_h: float)
signal action_cancelled(action_id: StringName, elapsed_h: float, reason: StringName)

const CLOCK_SCRIPT: GDScript = preload("res://scripts/systems/time/simulation_clock.gd")
const GROUP: StringName = &"time_costed_actions"

var simulation_clock: SimulationClock
var _active: TimeActionRequest
var _elapsed_hours: float = 0.0
var _elapsed_seconds: float = 0.0
var _effective_duration_hours: float = 0.0
var _effective_presentation_seconds: float = 0.0
var _previous_player_mode: int = -1
var _owns_realtime_block: bool = false


func _ready() -> void:
	add_to_group(GROUP)


func on_world_ready(context: WorldContext) -> void:
	simulation_clock = context.get_system(CLOCK_SCRIPT) as SimulationClock


static func find(tree: SceneTree) -> TimeCostedActionSystem:
	return tree.get_first_node_in_group(GROUP) as TimeCostedActionSystem if tree != null else null


func is_active() -> bool:
	return _active != null


func get_active_action_id() -> StringName:
	return _active.action_id if _active != null else &""


func get_progress() -> float:
	if _active == null:
		return 0.0
	if _effective_presentation_seconds > 0.0:
		return clampf(_elapsed_seconds / _effective_presentation_seconds, 0.0, 1.0)
	return clampf(_elapsed_hours / maxf(_effective_duration_hours, 0.000001), 0.0, 1.0)


## Starts a staged action whose presentation consumes real seconds.
func start_action(request: TimeActionRequest) -> bool:
	if not _can_start(request) or request.presentation_seconds <= 0.0:
		return false
	_begin(request)
	return true


## Starts an event-driven action. It owns PlayerState/realtime blocking like any
## other action, but gameplay decides when the action succeeds.
func start_manual_action(request: TimeActionRequest) -> bool:
	if not _can_start(request) or request.presentation_seconds > 0.0:
		return false
	_begin(request)
	return true


## Runs an action entirely in simulation time. Sleep/wait use this so eight
## hours never require eight hours of real-time presentation.
func run_to_completion(request: TimeActionRequest) -> Dictionary:
	if not _can_start(request):
		return {"started": false, "completed": false, "elapsed_hours": 0.0, "reason": &"busy"}
	_begin(request)
	while _active != null and _elapsed_hours < _effective_duration_hours - 0.000001:
		var slice: float = minf(request.simulation_step_hours, _effective_duration_hours - _elapsed_hours)
		if not _bill(slice):
			_cancel_internal(&"clock_refused")
			break
		var stop_reason: StringName = _stop_reason()
		if stop_reason != &"":
			_cancel_internal(stop_reason)
			break
	if _active != null:
		_complete_internal()
	return {
		"started": true,
		"completed": _active == null and _last_end_reason == &"",
		"elapsed_hours": _last_elapsed_hours,
		"reason": _last_end_reason,
	}


func cancel(reason: StringName = &"cancelled") -> bool:
	if _active == null or not _active.interruptible:
		return false
	_cancel_internal(reason)
	return true


## Completes the current event-driven action and bills its remaining declared
## game-time cost through the same deterministic clock path.
func complete_active() -> bool:
	if _active == null:
		return false
	var stop_reason: StringName = _stop_reason()
	if stop_reason != &"":
		_cancel_internal(stop_reason)
		return false
	while _active != null and _elapsed_hours < _effective_duration_hours - 0.000001:
		var slice: float = minf(_active.simulation_step_hours, _effective_duration_hours - _elapsed_hours)
		if not _bill(slice):
			_cancel_internal(&"clock_refused")
			return false
		stop_reason = _stop_reason()
		if stop_reason != &"":
			_cancel_internal(stop_reason)
			return false
	if _active != null:
		_complete_internal()
	return _last_end_reason == &""


func _process(delta: float) -> void:
	if _active != null and _active.external_presentation:
		return
	advance_presentation(delta)


## Advances a staged presentation through the same clock, stop checks and completion callback.
func advance_presentation(delta: float) -> void:
	if _active == null:
		return
	var stop_reason: StringName = _stop_reason()
	if stop_reason != &"":
		_cancel_internal(stop_reason)
		return
	if _active.presentation_seconds <= 0.0:
		return
	if _effective_presentation_seconds <= 0.0:
		complete_active()
		return

	_elapsed_seconds = minf(_effective_presentation_seconds, _elapsed_seconds + maxf(delta, 0.0))
	var target_hours: float = _effective_duration_hours * get_progress()
	var owed: float = target_hours - _elapsed_hours
	while owed >= _active.simulation_step_hours - 0.000001:
		if not _bill(_active.simulation_step_hours):
			_cancel_internal(&"clock_refused")
			return
		owed = target_hours - _elapsed_hours
		stop_reason = _stop_reason()
		if stop_reason != &"":
			_cancel_internal(stop_reason)
			return

	action_progress.emit(_active.action_id, get_progress())
	if _elapsed_seconds >= _effective_presentation_seconds - 0.000001:
		var remainder: float = _effective_duration_hours - _elapsed_hours
		if remainder > 0.000001 and not _bill(remainder):
			_cancel_internal(&"clock_refused")
			return
		stop_reason = _stop_reason()
		if stop_reason != &"":
			_cancel_internal(stop_reason)
			return
		_complete_internal()


var _last_elapsed_hours: float = 0.0
var _last_end_reason: StringName = &""


func _can_start(request: TimeActionRequest) -> bool:
	return request != null and request.is_valid() and simulation_clock != null and _active == null


func _begin(request: TimeActionRequest) -> void:
	_active = request
	_elapsed_hours = 0.0
	_elapsed_seconds = 0.0
	var duration_multiplier: float = _work_duration_multiplier(request)
	_effective_duration_hours = request.duration_hours * duration_multiplier
	_effective_presentation_seconds = request.presentation_seconds * duration_multiplier
	_last_elapsed_hours = 0.0
	_last_end_reason = &""
	simulation_clock.push_realtime_block()
	_owns_realtime_block = true
	_enter_player_mode(request.player_mode)
	action_started.emit(request.action_id, _effective_duration_hours)
	action_progress.emit(request.action_id, 0.0)


func _bill(hours: float) -> bool:
	if _active == null or hours <= 0.0:
		return false
	if not simulation_clock.advance_hours(hours, _active.reason):
		return false
	_elapsed_hours += hours
	action_progress.emit(_active.action_id, clampf(_elapsed_hours / maxf(_effective_duration_hours, 0.000001), 0.0, 1.0))
	return true


func get_effective_duration_hours() -> float:
	return _effective_duration_hours if _active != null else 0.0


func get_effective_presentation_seconds() -> float:
	return _effective_presentation_seconds if _active != null else 0.0


func _work_duration_multiplier(request: TimeActionRequest) -> float:
	if request == null or request.actor == null:
		return 1.0
	## The action layer depends only on the status modifier contract, not on afflictions.
	return StatusModifierCapability.multiplier(request.actor, &"work_duration_multiplier")


func _stop_reason() -> StringName:
	if _active == null or not _active.stop_check.is_valid():
		return &""
	var value: Variant = _active.stop_check.call()
	if value == null:
		return &""
	return StringName(String(value))


func _complete_internal() -> void:
	if _active == null:
		return
	var request: TimeActionRequest = _active
	_last_elapsed_hours = _elapsed_hours
	_last_end_reason = &""
	_active = null
	_release_control()
	if request.on_complete.is_valid():
		request.on_complete.call(_last_elapsed_hours)
	action_progress.emit(request.action_id, 1.0)
	action_completed.emit(request.action_id, _last_elapsed_hours)


func _cancel_internal(reason: StringName) -> void:
	if _active == null:
		return
	var request: TimeActionRequest = _active
	_last_elapsed_hours = _elapsed_hours
	_last_end_reason = reason
	_active = null
	_release_control()
	if request.on_cancel.is_valid():
		request.on_cancel.call(_last_elapsed_hours, reason)
	action_cancelled.emit(request.action_id, _last_elapsed_hours, reason)


func _enter_player_mode(mode: int) -> void:
	_previous_player_mode = -1
	if mode < 0:
		return
	var state := get_node_or_null(^"/root/PlayerState") as PlayerStateService
	if state == null or state.is_paused():
		return
	_previous_player_mode = int(state.mode)
	state.set_mode(mode as PlayerStateService.Mode)


func _release_control() -> void:
	if _owns_realtime_block and simulation_clock != null:
		simulation_clock.pop_realtime_block()
	_owns_realtime_block = false
	if _previous_player_mode >= 0 and is_inside_tree():
		var state := get_node_or_null(^"/root/PlayerState") as PlayerStateService
		if state != null and not state.is_paused():
			state.set_mode(_previous_player_mode as PlayerStateService.Mode)
	_previous_player_mode = -1
