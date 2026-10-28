class_name FatigueComponent
extends Node

signal level_changed(progress: float)
signal critical_reached
signal recovered

var max_energy: float = 100.0
var base_rate_per_hour: float = 7.0
var critical_threshold_percent: float = 10.0
var energy_restored_per_hour: float = 12.5
var carry_fatigue_factor: float = 0.6
var carry_inventory: InventoryComponent

var current_energy: float = 100.0
var previous_energy: float = 100.0
var is_critical: bool = false
var recently_replenished: bool = false


func configure(
	maximum: float,
	initial_percent: float,
	hourly_rate: float,
	critical_percent: float,
	restore_per_hour: float,
	carry_factor: float,
	inventory: InventoryComponent
) -> void:
	max_energy = maxf(maximum, 0.001)
	base_rate_per_hour = maxf(hourly_rate, 0.0)
	critical_threshold_percent = clampf(critical_percent, 0.0, 100.0)
	energy_restored_per_hour = maxf(restore_per_hour, 0.0)
	carry_fatigue_factor = maxf(carry_factor, 0.0)
	carry_inventory = inventory
	current_energy = clampf(initial_percent / 100.0 * max_energy, 0.0, max_energy)
	previous_energy = current_energy
	is_critical = _critical_now()
	recently_replenished = false


func progress() -> float:
	return clampf(current_energy / max_energy, 0.0, 1.0)


func consume(hours: float) -> void:
	if hours <= 0.0:
		return
	previous_energy = current_energy
	current_energy = maxf(0.0, current_energy - base_rate_per_hour * get_drain_multiplier() * hours)


func restore_sleep(hours: float, rest_quality: float) -> void:
	if hours <= 0.0:
		return
	var was_critical: bool = is_critical
	previous_energy = current_energy
	current_energy = clampf(
		current_energy + hours * energy_restored_per_hour * clampf(rest_quality, 0.0, 1.0)
			* _status_multiplier(&"recovery_rate_multiplier"),
		0.0,
		max_energy
	)
	recently_replenished = true
	_refresh_critical(was_critical)


func add(amount: float) -> void:
	var was_critical: bool = is_critical
	previous_energy = current_energy
	current_energy = clampf(current_energy + amount, 0.0, max_energy)
	recently_replenished = true
	level_changed.emit(progress())
	_refresh_critical(was_critical)


func set_current(value: float) -> void:
	current_energy = clampf(value, 0.0, max_energy)


func emit_level() -> void:
	level_changed.emit(progress())


func refresh_critical() -> void:
	_refresh_critical(is_critical)


func reset_recent() -> void:
	recently_replenished = false


func get_drain_multiplier() -> float:
	var load: float = get_load_fraction()
	var over_half: float = clampf((load - 0.5) * 2.0, 0.0, 1.0)
	var carry_multiplier: float = 1.0 + over_half * carry_fatigue_factor
	return carry_multiplier * _status_multiplier(&"fatigue_rate_multiplier")


func _status_multiplier(stat_id: StringName) -> float:
	var root: Node = get_parent()
	if root is BioMonitorManager:
		root = root.get_parent()
	return StatusModifierCapability.multiplier(root, stat_id)


func get_drain_reason() -> StringName:
	return &"load" if get_load_fraction() > 0.5 else &"normal"


func get_load_fraction() -> float:
	if carry_inventory == null:
		var root: Node = get_parent()
		if root is BioMonitorManager:
			root = root.get_parent()
		if root != null and root.is_in_group(&"player"):
			carry_inventory = InventoryComponent.find_in(root)
	return carry_inventory.get_load_fraction() if carry_inventory != null else 0.0


func _critical_now() -> bool:
	return current_energy <= max_energy * (critical_threshold_percent / 100.0)


func _refresh_critical(old_state: bool) -> void:
	var next: bool = _critical_now()
	is_critical = next
	if next and not old_state:
		critical_reached.emit()
	elif old_state and not next:
		recovered.emit()
