class_name AfflictionComponent
extends Node

## Persistent player-owned status layer. Threshold truth stays in the source
## systems; this component stores durable state and aggregates named modifiers.

signal affliction_activated(id: StringName, severity: float, source: StringName)
signal affliction_changed(id: StringName, severity: float)
signal affliction_recovered(id: StringName)

const HYPOTHERMIA: AfflictionDefinition = preload("res://resources/status/hypothermia.tres")
const DEHYDRATION: AfflictionDefinition = preload("res://resources/status/dehydration.tres")
const EXHAUSTION: AfflictionDefinition = preload("res://resources/status/exhaustion.tres")
const THERMAL_SCRIPT: GDScript = preload("res://scripts/systems/survival/thermal_manager.gd")

var _definitions: Dictionary = {}
var _states: Dictionary = {}
var _thermal: ThermalManager
var _hydration: HydrationComponent
var _fatigue: FatigueComponent


func _ready() -> void:
	for definition: AfflictionDefinition in [HYPOTHERMIA, DEHYDRATION, EXHAUSTION]:
		_definitions[definition.id] = definition
	## Frostnip and frostbite come from the body part library, one pair per part.
	for part: BodyPartDefinition in BodyPartLibrary.shared().parts:
		for definition: AfflictionDefinition in [part.frostnip_affliction, part.frostbite_affliction]:
			if definition != null:
				_definitions[definition.id] = definition
	if get_parent() != null:
		StatusModifierCapability.publish(get_parent(), self, &"get_multiplier")
	_bind_metabolic_sources()


func on_world_ready(context: WorldContext) -> void:
	bind_thermal(context.get_system(THERMAL_SCRIPT) as ThermalManager)


func _bind_metabolic_sources() -> void:
	var player: Node = get_parent()
	if player == null:
		return
	_hydration = player.get_node_or_null(^"HydrationComponent") as HydrationComponent
	_fatigue = player.get_node_or_null(^"FatigueComponent") as FatigueComponent
	if _hydration != null:
		if not _hydration.critical_reached.is_connected(_on_dehydration_reached):
			_hydration.critical_reached.connect(_on_dehydration_reached)
			_hydration.recovered.connect(_on_dehydration_recovered)
		set_condition(&"dehydration", _hydration.is_critical, 1.0, &"hydration")
	if _fatigue != null:
		if not _fatigue.critical_reached.is_connected(_on_exhaustion_reached):
			_fatigue.critical_reached.connect(_on_exhaustion_reached)
			_fatigue.recovered.connect(_on_exhaustion_recovered)
		set_condition(&"exhaustion", _fatigue.is_critical, 1.0, &"fatigue")


func bind_thermal(thermal: ThermalManager) -> void:
	if _thermal == thermal:
		if _thermal != null:
			_sync_thermal_stage(_thermal.get_stage())
		return
	if _thermal != null and _thermal.stage_changed.is_connected(_on_thermal_stage_changed):
		_thermal.stage_changed.disconnect(_on_thermal_stage_changed)
		_thermal.frost_stage_changed.disconnect(_on_frost_stage_changed)
	_thermal = thermal
	if _thermal != null:
		_thermal.stage_changed.connect(_on_thermal_stage_changed)
		_thermal.frost_stage_changed.connect(_on_frost_stage_changed)
		_sync_thermal_stage(_thermal.get_stage())
		for part_id: StringName in BodyPartLibrary.shared().get_ids():
			_on_frost_stage_changed(part_id, _thermal.get_frost_stage(part_id))
	else:
		set_condition(&"hypothermia", false)


func set_condition(
	id: StringName,
	active: bool,
	severity: float = 1.0,
	source: StringName = &""
) -> bool:
	var definition := _definitions.get(id) as AfflictionDefinition
	if definition == null:
		return false
	var state := _states.get(id) as AfflictionState
	if active:
		var next_severity: float = clampf(severity, 0.0, definition.max_severity)
		if state == null:
			state = AfflictionState.new()
			state.id = id
			_states[id] = state
		var was_active: bool = state.active
		var changed: bool = not is_equal_approx(state.severity, next_severity)
		state.active = true
		state.severity = next_severity
		state.source = source
		if not was_active:
			state.elapsed_hours = 0.0
			state.recovery_progress = 0.0
			affliction_activated.emit(id, state.severity, state.source)
		elif changed:
			affliction_changed.emit(id, state.severity)
		return true

	if state == null or not state.active:
		return false
	state.active = false
	state.severity = 0.0
	state.recovery_progress = 1.0
	affliction_recovered.emit(id)
	return true


func has_affliction(id: StringName) -> bool:
	var state := _states.get(id) as AfflictionState
	return state != null and state.active


func get_severity(id: StringName) -> float:
	var state := _states.get(id) as AfflictionState
	return state.severity if state != null and state.active else 0.0


func get_elapsed_hours(id: StringName) -> float:
	var state := _states.get(id) as AfflictionState
	return state.elapsed_hours if state != null and state.active else 0.0


func get_multiplier(stat_id: StringName) -> float:
	var result: float = 1.0
	for id: StringName in get_active_ids():
		var state := _states[id] as AfflictionState
		var definition := _definitions.get(id) as AfflictionDefinition
		if definition == null:
			continue
		var raw: Variant = definition.modifiers.get(
			String(stat_id),
			definition.modifiers.get(stat_id, 1.0)
		)
		var at_max: float = maxf(float(raw), 0.0)
		var severity_ratio: float = clampf(state.severity / maxf(definition.max_severity, 0.001), 0.0, 1.0)
		result *= lerpf(1.0, at_max, severity_ratio)
	return result


func get_active_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for raw_id: Variant in _states.keys():
		var id := StringName(raw_id)
		var state := _states[id] as AfflictionState
		if state != null and state.active:
			ids.append(id)
	ids.sort()
	return ids


func get_definition(id: StringName) -> AfflictionDefinition:
	return _definitions.get(id) as AfflictionDefinition


func get_simulation_priority() -> int:
	return 450


func advance_simulation(hours: float, _context: SimulationStepContext) -> void:
	if hours <= 0.0:
		return
	var health_loss: float = 0.0
	for id: StringName in get_active_ids():
		var state := _states[id] as AfflictionState
		state.elapsed_hours += hours
		var definition := _definitions.get(id) as AfflictionDefinition
		if definition != null and definition.health_loss_per_hour > 0.0:
			health_loss += definition.health_loss_per_hour * hours * clampf(state.severity / maxf(definition.max_severity, 0.001), 0.0, 1.0)
	if health_loss > 0.0:
		var health := get_parent().get_node_or_null(^"PlayerHealthSystem") as PlayerHealthSystem if get_parent() != null else null
		if health != null:
			health.drain(health_loss, "frostbite")


func get_save_key() -> StringName:
	return &"afflictions"


func get_save_data() -> Dictionary:
	var saved: Array = []
	for id: StringName in get_active_ids():
		saved.append((_states[id] as AfflictionState).to_dict())
	return {"states": saved}


func load_save_data(data: Dictionary) -> void:
	_states.clear()
	for raw: Variant in data.get("states", []):
		if not raw is Dictionary:
			continue
		var state := AfflictionState.from_dict(raw)
		var definition := _definitions.get(state.id) as AfflictionDefinition
		if definition == null or not state.active:
			continue
		state.severity = clampf(state.severity, 0.0, definition.max_severity)
		_states[state.id] = state


func _on_thermal_stage_changed(stage: ThermalManager.Stage) -> void:
	_sync_thermal_stage(stage)


func _sync_thermal_stage(stage: ThermalManager.Stage) -> void:
	match stage:
		ThermalManager.Stage.HYPOTHERMIC:
			set_condition(&"hypothermia", true, 1.0, &"thermal")
		ThermalManager.Stage.CRITICAL:
			set_condition(&"hypothermia", true, 2.0, &"thermal")
		_:
			set_condition(&"hypothermia", false)


## Mirrors one part's frost stage onto its frostnip and frostbite afflictions.
func _on_frost_stage_changed(part_id: StringName, stage: int) -> void:
	var part: BodyPartDefinition = BodyPartLibrary.shared().find(part_id)
	if part == null:
		return
	if part.frostnip_affliction != null:
		set_condition(part.frostnip_affliction.id, stage == ExtremityCold.FrostStage.FROSTNIP, 1.0, &"frost")
	if part.frostbite_affliction != null:
		set_condition(part.frostbite_affliction.id, stage == ExtremityCold.FrostStage.FROSTBITE, 1.0, &"frost")


func _on_dehydration_reached() -> void:
	set_condition(&"dehydration", true, 1.0, &"hydration")


func _on_dehydration_recovered() -> void:
	set_condition(&"dehydration", false)


func _on_exhaustion_reached() -> void:
	set_condition(&"exhaustion", true, 1.0, &"fatigue")


func _on_exhaustion_recovered() -> void:
	set_condition(&"exhaustion", false)
