class_name HeatSource
extends Node3D

## Point source of warmth: a fire, a barrel, a working heater. Sampled by
## distance rather than by Area3D, so falloff stays smooth and cheap.

## Emitted when the source ignites or dies, for VFX, audio and zone heating.
signal burning_changed(is_burning: bool)
## Emitted as fuel burns down, 1.0 full to 0.0 spent, for the HUD.
signal fuel_changed(fraction: float)
## Emitted for every stretch of game time the source burns through, for things
## warming on it; also for sources that never run out.
signal heat_elapsed(hours: float)
signal intensity_changed(intensity: float)
## Tinder laid under the logs of a cold stove, kept until a fire catches it.
signal tinder_changed(prepared: bool)

static var _registry: Array[HeatSource] = []

@export_group("Heat")
## Degrees added at the very centre of the source.
@export var peak_offset_c: float = 18.0
## Distance in metres at which the contribution reaches zero.
@export var radius_m: float = 6.0
## Shapes the falloff: 1.0 linear, 2.0 concentrated near the flame.
@export var falloff_exponent: float = 2.0

@export_group("Zone")
## Zone this source warms while it burns. Registering is automatic, so a fire
## going out stops heating the room without any scene wiring.
@export var heats_zone: ThermalZone

@export_group("Visual")
## Light shown while the source burns, so a lit stove reads at a glance.
@export var flame_light: Light3D

@export_group("Fuel")
## Starts lit when the scene loads.
@export var starts_burning: bool = true
## In-game hours the source burns on a full load of fuel; 0.0 means forever.
@export var burn_duration_h: float = 6.0
## Hours a single unit of fuel adds when the player feeds the fire.
@export var hours_per_fuel_unit: float = 2.0

## Opt-in startup ramp; other heat sources keep instant full output.
@export_range(0.0, 120.0, 0.5) var warmup_seconds: float = 0.0

var _simulation_clock: SimulationClock
var _recoverable_logs: int = 0
var _warmup_duration_h: float = 0.0
var _warmup_remaining_h: float = 0.0
var _step_intensity: float = 1.0
var _is_burning: bool = false
var _remaining_h: float = 0.0
var _tinder_prepared: bool = false


func _ready() -> void:
	initialize()


## Registers the source and lights it if configured to start burning.
## Public so headless tests can drive it without waiting for a frame.
func initialize() -> void:
	if _registry.has(self):
		return
	_registry.append(self)
	burning_changed.connect(_on_burning_changed)
	if flame_light != null:
		flame_light.visible = false
	if starts_burning:
		ignite()
	else:
		_step_intensity = 0.0


func _exit_tree() -> void:
	_registry.erase(self)
	if is_instance_valid(_simulation_clock):
		_simulation_clock.release_realtime_step(self)
	if _is_burning and heats_zone != null:
		heats_zone.remove_heat_source(self)


## Frees can bypass _exit_tree, so drop out of the registry here as well.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_registry.erase(self)


## Keeps the zone's heating count in step with this source's flame.
func _on_burning_changed(burning: bool) -> void:
	if flame_light != null:
		flame_light.visible = burning
	if heats_zone == null:
		return
	if burning:
		heats_zone.add_heat_source(self)
	else:
		heats_zone.remove_heat_source(self)


## All live heat sources. Freed entries are dropped rather than returned,
## so one stale source cannot break every temperature calculation.
static func get_all() -> Array[HeatSource]:
	var live: Array[HeatSource] = []
	var stale: bool = false
	for source: HeatSource in _registry:
		if is_instance_valid(source):
			live.append(source)
		else:
			stale = true
	if stale:
		_registry = live
	return live


func is_burning() -> bool:
	return _is_burning


## Hours of fuel left; infinite sources report their nominal duration.
func get_remaining_hours() -> float:
	return _remaining_h


## Fuel left as 0.0 to 1.0, for a HUD gauge. Infinite sources report 1.0.
func get_fuel_fraction() -> float:
	if burn_duration_h <= 0.0:
		return 1.0
	return clampf(_remaining_h / burn_duration_h, 0.0, 1.0)


## Adds fuel, capped at the full load. Relights a fire that had gone out.
func refuel(units: float = 1.0) -> void:
	if burn_duration_h <= 0.0:
		return
	_remaining_h = minf(burn_duration_h, _remaining_h + units * hours_per_fuel_unit)
	if _remaining_h > 0.0 and not _is_burning:
		_is_burning = true
		_recoverable_logs = 0
		_warmup_remaining_h = 0.0
		_step_intensity = 1.0
		set_tinder_prepared(false)
		burning_changed.emit(true)
	_sync_warmup_step()
	fuel_changed.emit(get_fuel_fraction())


## Whether another unit of fuel would do anything. A full fire refuses, so a
## caller does not burn an item for nothing.
func can_refuel() -> bool:
	if burn_duration_h <= 0.0:
		return false
	return _remaining_h < burn_duration_h


## Restores exact fuel state, for a save rather than for gameplay. Gameplay
## goes through refuel(), which is capped and relights.
func restore_fuel(hours: float, burning: bool) -> void:
	_warmup_duration_h = 0.0
	_warmup_remaining_h = 0.0
	_recoverable_logs = 0
	_remaining_h = clampf(hours, 0.0, maxf(burn_duration_h, hours))
	var should_burn: bool = burning and (_remaining_h > 0.0 or burn_duration_h <= 0.0)
	if should_burn != _is_burning:
		_is_burning = should_burn
		burning_changed.emit(_is_burning)
	_step_intensity = get_intensity()
	_sync_warmup_step()
	fuel_changed.emit(get_fuel_fraction())


## Lights the source and refills it to its full burn duration.
func ignite() -> void:
	_recoverable_logs = 0
	_warmup_remaining_h = 0.0
	_warmup_duration_h = 0.0
	_step_intensity = 1.0
	_remaining_h = burn_duration_h
	_sync_warmup_step()
	if not _is_burning:
		_is_burning = true
		set_tinder_prepared(false)
		burning_changed.emit(true)
	fuel_changed.emit(get_fuel_fraction())


## Puts the source out immediately.
func extinguish() -> void:
	if not _is_burning:
		return
	_is_burning = false
	_sync_warmup_step()
	_step_intensity = 0.0
	burning_changed.emit(false)
	fuel_changed.emit(get_fuel_fraction())


## Burns fuel for the given number of in-game hours.
func advance_fuel(delta_hours: float) -> void:
	_step_intensity = 0.0
	if not _is_burning or delta_hours <= 0.0:
		return
	var burned_hours: float = delta_hours if burn_duration_h <= 0.0 else minf(delta_hours, _remaining_h)
	var heat_hours: float = _advance_warmup(burned_hours)
	var average_intensity: float = heat_hours / delta_hours
	if heat_hours > 0.0:
		heat_elapsed.emit(heat_hours)
	if burn_duration_h > 0.0:
		_remaining_h = maxf(0.0, _remaining_h - burned_hours)
		if _remaining_h <= 0.0:
			extinguish()
	_step_intensity = average_intensity
	fuel_changed.emit(get_fuel_fraction())


func _advance_warmup(hours: float) -> float:
	var ramp_hours: float = minf(hours, _warmup_remaining_h)
	var before: float = get_intensity()
	_warmup_remaining_h = maxf(0.0, _warmup_remaining_h - ramp_hours)
	if _warmup_remaining_h < 0.000000001:
		_warmup_remaining_h = 0.0
	var after: float = get_intensity()
	_sync_warmup_step()
	if not is_equal_approx(before, after):
		intensity_changed.emit(after)
	return ramp_hours * (before + after) * 0.5 + hours - ramp_hours


func get_intensity() -> float:
	if not _is_burning:
		return 0.0
	if _warmup_duration_h <= 0.0:
		return 1.0
	return lerpf(0.08, 1.0, 1.0 - _warmup_remaining_h / _warmup_duration_h)


func get_step_intensity() -> float:
	return _step_intensity


func get_recoverable_log_count() -> int:
	return _recoverable_logs if not _is_burning else 0


func get_log_room() -> int:
	if burn_duration_h <= 0.0 or hours_per_fuel_unit <= 0.0:
		return 0
	return maxi(0, floori((burn_duration_h - _remaining_h + 0.0001) / hours_per_fuel_unit))


## Whole logs a full firebox holds: burn_duration_h / hours_per_fuel_unit.
func get_log_capacity() -> int:
	if burn_duration_h <= 0.0 or hours_per_fuel_unit <= 0.0:
		return 0
	return floori(burn_duration_h / hours_per_fuel_unit + 0.0001)


## Logs in the firebox now, a partly burned one counted whole (as the stove shows it).
func get_loaded_log_count() -> int:
	if hours_per_fuel_unit <= 0.0:
		return 0
	return clampi(ceili(_remaining_h / hours_per_fuel_unit - 0.001), 0, get_log_capacity())


func is_tinder_prepared() -> bool:
	return _tinder_prepared


## Lays or clears tinder in a cold firebox; a burning stove needs none.
func set_tinder_prepared(prepared: bool) -> bool:
	if prepared and _is_burning:
		return false
	if prepared == _tinder_prepared:
		return true
	_tinder_prepared = prepared
	tinder_changed.emit(prepared)
	return true


## Whole-log transfers never ignite a cold load or manufacture a partly burned log.
func add_logs(count: int) -> bool:
	if count <= 0 or count > get_log_room():
		return false
	_remaining_h += float(count) * hours_per_fuel_unit
	if not _is_burning:
		_recoverable_logs += count
	fuel_changed.emit(get_fuel_fraction())
	return true


func remove_cold_logs(count: int) -> bool:
	if count <= 0 or count > get_recoverable_log_count():
		return false
	_recoverable_logs -= count
	_remaining_h = maxf(0.0, _remaining_h - float(count) * hours_per_fuel_unit)
	fuel_changed.emit(get_fuel_fraction())
	return true


## Starts the loaded fuel without filling the firebox. Hours come from the normal world rate.
func start_loaded_fire(game_hours_per_second: float = 1.0 / 3600.0) -> bool:
	if _is_burning or _remaining_h <= 0.0:
		return false
	_sync_warmup_step()
	if is_instance_valid(_simulation_clock):
		_simulation_clock.flush_realtime()
	_warmup_duration_h = warmup_seconds * game_hours_per_second
	_warmup_remaining_h = _warmup_duration_h
	_recoverable_logs = 0
	_is_burning = true
	## The tinder is what caught: it is spent.
	set_tinder_prepared(false)
	_step_intensity = get_intensity()
	_sync_warmup_step()
	burning_changed.emit(true)
	intensity_changed.emit(get_intensity())
	fuel_changed.emit(get_fuel_fraction())
	return true


func get_fire_save_data() -> Dictionary:
	return {"remaining_h": _remaining_h, "burning": _is_burning,
		"recoverable_logs": _recoverable_logs, "warmup_duration_h": _warmup_duration_h,
		"warmup_remaining_h": _warmup_remaining_h, "tinder_prepared": _tinder_prepared}


func restore_fire_save_data(data: Dictionary) -> void:
	restore_fuel(float(data.get("remaining_h", 0.0)), bool(data.get("burning", false)))
	var legacy_logs: int = floori(_remaining_h / hours_per_fuel_unit + 0.0001) if hours_per_fuel_unit > 0.0 else 0
	_recoverable_logs = 0 if _is_burning else clampi(int(data.get("recoverable_logs", 0)), 0, legacy_logs)
	_warmup_duration_h = maxf(0.0, float(data.get("warmup_duration_h", 0.0)))
	_warmup_remaining_h = clampf(float(data.get("warmup_remaining_h", 0.0)), 0.0, _warmup_duration_h)
	set_tinder_prepared(bool(data.get("tinder_prepared", false)) and not _is_burning)
	_step_intensity = get_intensity()
	_sync_warmup_step()
	intensity_changed.emit(get_intensity())
	fuel_changed.emit(get_fuel_fraction())


## Advances every live source. Called once per tick by ThermalManager so fuel
## burns on the game clock rather than per frame.
static func advance_all_fuel(delta_hours: float) -> void:
	for source: HeatSource in get_all():
		source.advance_fuel(delta_hours)


## Degrees this source contributes at a world position, zero beyond its radius.
func get_offset_at(world_position: Vector3) -> float:
	if not _is_burning or radius_m <= 0.0 or not is_inside_tree():
		return 0.0
	var distance: float = global_position.distance_to(world_position)
	if distance >= radius_m:
		return 0.0
	var normalised: float = 1.0 - (distance / radius_m)
	return peak_offset_c * pow(normalised, falloff_exponent) * get_intensity()


func _sync_warmup_step() -> void:
	if not is_instance_valid(_simulation_clock) and is_inside_tree():
		_simulation_clock = get_tree().get_first_node_in_group(&"simulation_clock") as SimulationClock
	if not is_instance_valid(_simulation_clock):
		return
	if _is_burning and _warmup_remaining_h > 0.0 and warmup_seconds > 0.0:
		_simulation_clock.request_realtime_step(self, _warmup_duration_h / warmup_seconds * 0.1)
	else:
		_simulation_clock.release_realtime_step(self)
