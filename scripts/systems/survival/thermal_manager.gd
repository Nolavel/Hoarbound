class_name ThermalManager
extends Node3D

## Scripts looked up through the world context, never by node path.
const WEATHER_CONTROLLER_SCRIPT: GDScript = preload("res://scripts/systems/world/WeatherController.gd")
const DAY_NIGHT_SCRIPT: GDScript = preload("res://scripts/systems/world/DayNightManager.gd")
const EQUIPMENT_SCRIPT: GDScript = preload("res://scripts/actors/player/henry/components/equipment_component.gd")
## Diurnal air curve used when none is assigned: coldest before dawn (05:30), warmest at 14:30.
const DEFAULT_AMBIENT_CURVE: Curve = preload("res://data/climate/air_temperature_day.tres")
## Radius of the probe built when the scene supplies none.
const PROBE_RADIUS: float = 0.4

## Simulates Henry's body temperature against the felt temperature of his
## surroundings. This is the survival pillar every other cold system feeds.

## Emitted whenever body temperature changes, for HUD and audio.
signal body_temperature_changed(celsius: float, normalised: float)
## Emitted when the felt temperature changes, for the thermometer readout.
signal felt_temperature_changed(celsius: float)
## Emitted when the player crosses into a new hypothermia stage.
signal stage_changed(stage: Stage)
## Emitted once when body temperature reaches the lethal floor.
signal freezing_death_reached
## Emitted when clothing wetness changes, 0.0 dry to 1.0 soaked.
signal wetness_changed(wetness: float)
## Emitted on the edge of entering or leaving an interior zone; the colour grade
## and other presentation switch on it rather than guessing from position.
signal sheltered_changed(is_sheltered: bool)

## Hypothermia stages, ordered from safe to lethal.
enum Stage { NORMAL, CHILLED, COLD, HYPOTHERMIC, CRITICAL }
enum WetnessStage { DRY, DAMP, WET, SOAKED }

const HOURS_PER_DAY: float = 24.0

@export_group("Body")
## Core temperature the body holds when the environment is comfortable.
@export var normal_body_temp_c: float = 36.6
## Body temperature at or below which the player dies.
@export var lethal_body_temp_c: float = 28.0
## Felt temperature at which bare skin would neither gain nor lose heat.
@export var comfort_temp_c: float = 20.0
## Degrees of self-generated warmth from basal metabolism. Without this the
## body can never rewarm, because no reachable shelter beats bare-skin comfort.
@export var basal_heat_c: float = 12.0
## Degrees the body moves per in-game hour per degree of comfort deficit.
@export var cooling_coefficient: float = 0.075
## Degrees the body recovers per in-game hour when the surroundings are warm.
@export var rewarm_coefficient: float = 0.55

@export_group("Stage thresholds")
## Body temperature below which each stage begins, warmest first.
@export var chilled_below_c: float = 36.0
@export var cold_below_c: float = 35.0
@export var hypothermic_below_c: float = 33.0
@export var critical_below_c: float = 31.0

@export_group("Insulation")
## Fallback protection used only when no EquipmentComponent is wired. Once one
## is, what Henry is actually wearing decides this instead.
@export var clothing_insulation_c: float = 6.0
## What Henry is wearing. When present its summed garment insulation replaces
## the fallback above, so a coat is a survival decision rather than a costume.
@export var equipment: EquipmentComponent
## Fraction of insulation lost when clothing is fully soaked.
@export_range(0.0, 1.0) var wetness_insulation_penalty: float = 0.8
## Wetness units lost per in-game hour at full warmth, beside a real fire.
@export var drying_rate_per_hour: float = 0.35
## Felt temperature below which nothing dries at all.
@export var drying_starts_c: float = 0.0
## Felt temperature at which clothes dry at the full rate.
@export var drying_full_c: float = 25.0

@export_group("Wind chill")
## Degrees lost per metre per second of wind at full exposure.
@export var wind_chill_per_mps: float = 0.55
## Wind speed beyond which extra wind stops mattering, in metres per second.
@export var wind_chill_cap_mps: float = 22.0

@export_group("Exertion")
## Degrees of self-generated warmth at full sprint.
@export var exertion_bonus_c: float = 3.5

@export_group("Wiring")
## Global weather state; without it the model runs on ambient alone.
@export var weather_controller: WeatherController
## Supplies the in-game clock that drives every hourly rate.
@export var day_night_manager: DayNightManager
## Probe area that reports which ThermalZones contain the player.
@export var zone_probe: Area3D
## Ambient air temperature by hour of day, sampled 0.0 to 1.0 across the curve.
@export var ambient_curve: Curve
## Coldest ambient air temperature, at the curve's minimum.
@export var ambient_min_c: float = -28.0
## Warmest ambient air temperature, at the curve's maximum.
@export var ambient_max_c: float = -8.0

var _body_temp_c: float = 36.6
var _felt_temp_c: float = 0.0
var _wetness: float = 0.0
var _stage: Stage = Stage.NORMAL
var _exertion: float = 0.0
var _is_dead: bool = false
var _hours: GameHourTracker = GameHourTracker.new()
var _zones: Array[ThermalZone] = []
var _was_sheltered: bool = false
var _initialized: bool = false
var _follow_target: Node3D
var _outdoor_air_c: float = 0.0
var _extremities: ExtremityCold = ExtremityCold.new()


## Lifecycle hook world.gd calls once the player and camera exist. Everything
## this system needs is found here, so no scene has to wire it by hand.
func on_world_ready(context: WorldContext) -> void:
	_follow_target = context.player
	if weather_controller == null:
		weather_controller = context.get_system(WEATHER_CONTROLLER_SCRIPT) as WeatherController
	if day_night_manager == null:
		day_night_manager = context.find_in_scene(DAY_NIGHT_SCRIPT) as DayNightManager
	if equipment == null:
		equipment = context.find_in_scene(EQUIPMENT_SCRIPT) as EquipmentComponent
	if zone_probe == null:
		zone_probe = _build_probe()
	_follow()
	initialize()
	refresh_felt_temperature()


## Recomputes the felt temperature now instead of at the next clock step (a quarter hour
## away), so a fresh start or load never shows 0 °C.
func refresh_felt_temperature() -> void:
	var hour: float = day_night_manager.get_current_hour_float() if day_night_manager != null else 12.0
	_felt_temp_c = _compute_felt_temperature(hour)
	felt_temperature_changed.emit(_felt_temp_c)


## The thermal model reads the world at Henry's feet, so it rides with him.
func _process(_delta: float) -> void:
	_follow()


func _follow() -> void:
	if _follow_target != null and _follow_target.is_inside_tree():
		global_position = _follow_target.global_position


## An Area3D that notices ThermalZones, built when the scene supplies none.
## Masks every layer: a zone authored on any layer must still be felt.
func _build_probe() -> Area3D:
	var probe := Area3D.new()
	probe.name = "ZoneProbe"
	probe.monitorable = false
	probe.collision_layer = 0
	probe.collision_mask = 0xFFFFF
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = PROBE_RADIUS
	shape.shape = sphere
	probe.add_child(shape)
	add_child(probe)
	return probe


func _ready() -> void:
	initialize()


## Seeds body temperature and connects the clock and the zone probe.
## Public so headless tests can drive it without waiting for a frame.
func initialize() -> void:
	if ambient_curve == null:
		ambient_curve = DEFAULT_AMBIENT_CURVE
	if not _initialized:
		_initialized = true
		_body_temp_c = normal_body_temp_c
	_connect_probe()


## Subscribes to the zone probe, at most once.
func _connect_probe() -> void:
	if zone_probe == null:
		return
	if not zone_probe.area_entered.is_connected(_on_zone_entered):
		zone_probe.area_entered.connect(_on_zone_entered)
		zone_probe.area_exited.connect(_on_zone_exited)


## Dry insulation in degrees: what Henry is wearing when equipment is wired,
## the exported fallback otherwise.
func get_insulation_c() -> float:
	if equipment != null:
		return equipment.get_effective_insulation_c()
	return clothing_insulation_c


## Current core temperature in degrees Celsius.
func get_body_temperature_c() -> float:
	return _body_temp_c


## Core temperature as 0.0 at the lethal floor and 1.0 at normal.
func get_body_temperature_normalised() -> float:
	var span: float = maxf(0.001, normal_body_temp_c - lethal_body_temp_c)
	return clampf((_body_temp_c - lethal_body_temp_c) / span, 0.0, 1.0)


## Outdoor air: time of day plus weather, before wind, shelter or fires.
## What frost on the world responds to, as opposed to what Henry feels.
func get_outdoor_air_c() -> float:
	return _outdoor_air_c


## Temperature the player feels right now, after wind, shelter and fires.
func get_felt_temperature_c() -> float:
	return _felt_temp_c


## Room air excludes the stove's local radiant heat and Henry's body temperature.
func get_room_temperature_c() -> float:
	var zone: ThermalZone = _get_dominant_zone()
	return _outdoor_air_c + (zone.get_total_offset_c() if zone != null else 0.0)


func get_stage() -> Stage:
	return _stage


## Body temperature of a stage boundary as 0..1 on the HUD scale (lethal 0, normal 1).
func get_stage_threshold_normalised(stage: Stage) -> float:
	var celsius: float = normal_body_temp_c
	match stage:
		Stage.CHILLED:
			celsius = chilled_below_c
		Stage.COLD:
			celsius = cold_below_c
		Stage.HYPOTHERMIC:
			celsius = hypothermic_below_c
		Stage.CRITICAL:
			celsius = critical_below_c
	return clampf((celsius - lethal_body_temp_c) / maxf(0.001, normal_body_temp_c - lethal_body_temp_c), 0.0, 1.0)


## Cold load 0..1 on one extremity (&"head", &"hands", &"feet"), for the HUD silhouette.
func get_extremity_cold(region: StringName) -> float:
	return _extremities.get_load(region)


func get_wetness() -> float:
	if equipment != null:
		return equipment.get_average_wetness()
	return _wetness


func get_wetness_stage() -> WetnessStage:
	var wetness: float = get_wetness()
	if wetness < 0.05:
		return WetnessStage.DRY
	if wetness < 0.35:
		return WetnessStage.DAMP
	if wetness < 0.75:
		return WetnessStage.WET
	return WetnessStage.SOAKED


## Fraction of dry insulation still working at the current global clothing wetness.
func get_wetness_insulation_multiplier() -> float:
	if equipment != null:
		var dry: float = equipment.get_total_insulation_c()
		return clampf(equipment.get_effective_insulation_c() / dry, 0.0, 1.0) if dry > 0.001 else 1.0
	return clampf(1.0 - _wetness * wetness_insulation_penalty, 0.0, 1.0)


## True only when the next wetness step would actually dry clothing.
func is_clothing_drying() -> bool:
	var wet: bool = equipment.has_wet_garments() if equipment != null else _wetness > 0.01
	if not wet or _drying_warmth() <= 0.001:
		return false
	if not is_sheltered() and weather_controller != null and weather_controller.get_wetness_rate_per_hour() > 0.0:
		return false
	return true


## True while the player is inside any zone flagged as an interior.
func is_sheltered() -> bool:
	for zone: ThermalZone in _zones:
		if zone.is_interior:
			return true
	return false


## Feeds movement effort in, 0.0 standing still to 1.0 sprinting.
func set_exertion(value: float) -> void:
	_exertion = clampf(value, 0.0, 1.0)


## Soaks clothing, for falling through ice or standing in heavy snowfall.
func add_wetness(amount: float) -> void:
	if equipment != null:
		equipment.add_wetness_all(amount)
		_set_wetness(equipment.get_average_wetness())
		return
	_set_wetness(_wetness + amount)


## Drops the clock baseline so the next tick does not bill skipped hours.
## Call this after any deliberate time skip, such as sleeping.
func reset_clock() -> void:
	_hours.reset()


## Applies a direct change to core temperature, for events the ambient model
## does not cover, such as falling into freezing water.
func apply_body_temperature_delta(degrees: float) -> void:
	if _is_dead:
		return
	_body_temp_c = clampf(_body_temp_c + degrees, lethal_body_temp_c, normal_body_temp_c)
	_emit_body_temperature()
	_update_stage()
	if _body_temp_c <= lethal_body_temp_c:
		_is_dead = true
		freezing_death_reached.emit()


## Instantly restores core temperature, for sleeping in a warm shelter.
func restore_body_temperature() -> void:
	_is_dead = false
	_body_temp_c = normal_body_temp_c
	_extremities.reset()
	_emit_body_temperature()
	_update_stage()


## Key this system owns in a save file, stated explicitly so renaming the
## script never orphans an existing save.
func get_save_key() -> StringName:
	return &"thermal"


## State the save system persists for this system.
func get_save_data() -> Dictionary:
	return {
		"body_temp_c": _body_temp_c,
		"wetness": _wetness,
		"is_dead": _is_dead,
		"extremities": _extremities.get_save_data(),
	}


## Restores persisted state and re-derives everything downstream of it.
func load_save_data(data: Dictionary) -> void:
	_body_temp_c = clampf(
		float(data.get("body_temp_c", normal_body_temp_c)), lethal_body_temp_c, normal_body_temp_c
	)
	_is_dead = bool(data.get("is_dead", false))
	_set_wetness(float(data.get("wetness", 0.0)))
	_extremities.load_save_data(data.get("extremities", {}))
	_hours.reset()
	if is_inside_tree():
		refresh_felt_temperature()
	_emit_body_temperature()
	_update_stage()


func get_simulation_priority() -> int:
	return 300


func advance_simulation(hours: float, context: SimulationStepContext) -> void:
	_advance_hours(hours, context.hour_of_day)


## Compatibility seam for isolated thermal tests/tools; production uses SimulationClock.
func _on_time_update(current_hour: float) -> void:
	_advance_hours(_hours.consume(current_hour), current_hour)


func _advance_hours(hours: float, current_hour: float) -> void:
	if hours <= 0.0 or _is_dead:
		return
	HeatSource.advance_all_fuel(hours)
	for zone: ThermalZone in _zones:
		zone.advance_heating(hours)
	_update_wetness(hours, current_hour)
	_felt_temp_c = _compute_felt_temperature(current_hour)
	felt_temperature_changed.emit(_felt_temp_c)
	_integrate_body_temperature(hours)
	_extremities.advance(hours, _felt_temp_c, _region_protection())


## Sums ambient air, weather, wind chill, zones and nearby fires.
func _compute_felt_temperature(current_hour: float) -> float:
	var felt: float = _sample_ambient_c(current_hour)
	var wind: float = 0.0
	var wind_direction: Vector3 = Vector3.ZERO
	if weather_controller != null:
		felt += weather_controller.get_ambient_offset_c()
	_outdoor_air_c = felt
	if weather_controller != null:
		wind = weather_controller.get_wind_speed_mps()
		wind_direction = weather_controller.get_wind_direction()

	var zone_offset: float = 0.0
	var exposure: float = 1.0
	var best: ThermalZone = _get_dominant_zone()
	if best != null:
		zone_offset = best.get_total_offset_c()
		exposure = best.get_wind_exposure(wind_direction)
	felt += zone_offset

	var capped_wind: float = minf(wind, wind_chill_cap_mps)
	var clothing_wind_factor: float = 1.0 - (equipment.get_wind_protection() if equipment != null else 0.0)
	felt -= capped_wind * wind_chill_per_mps * exposure * clothing_wind_factor

	for source: HeatSource in HeatSource.get_all():
		felt += source.get_offset_at(global_position)

	felt += exertion_bonus_c * _exertion
	return felt


## Cover of each extremity; without equipment every region counts as bare.
func _region_protection() -> Dictionary:
	var out: Dictionary = {}
	if equipment == null:
		return out
	for region: StringName in ExtremityCold.REGIONS:
		out[region] = equipment.get_region_protection(region)
	return out


## Moves body temperature toward the felt temperature through insulation.
func _integrate_body_temperature(hours: float) -> void:
	var insulation: float = get_insulation_c()
	if equipment == null:
		insulation *= 1.0 - _wetness * wetness_insulation_penalty
	var effective: float = _felt_temp_c + insulation + basal_heat_c
	var deficit: float = comfort_temp_c - effective
	var previous: float = _body_temp_c

	if deficit > 0.0:
		_body_temp_c -= deficit * cooling_coefficient * hours
	else:
		var headroom: float = normal_body_temp_c - _body_temp_c
		_body_temp_c += minf(headroom, -deficit * rewarm_coefficient * hours)

	_body_temp_c = clampf(_body_temp_c, lethal_body_temp_c, normal_body_temp_c)
	if not is_equal_approx(previous, _body_temp_c):
		_emit_body_temperature()
	_update_stage()

	if _body_temp_c <= lethal_body_temp_c and not _is_dead:
		_is_dead = true
		freezing_death_reached.emit()


## Soaks clothing in exposed snowfall, dries it in warm shelter.
func _update_wetness(hours: float, _current_hour: float) -> void:
	var sheltered: bool = is_sheltered()
	var exposure_rate: float = 0.0
	if not sheltered and weather_controller != null:
		exposure_rate = maxf(weather_controller.get_wetness_rate_per_hour(), 0.0)

	if equipment != null:
		equipment.advance_garment_moisture(hours, exposure_rate, _drying_warmth())
		_set_wetness(equipment.get_average_wetness())
		return

	if exposure_rate > 0.0:
		_set_wetness(_wetness + exposure_rate * hours)
		return
	_set_wetness(_wetness - get_drying_rate_per_hour() * hours)


## Wetness shed per game hour at the current felt temperature.
func get_drying_rate_per_hour() -> float:
	return drying_rate_per_hour * _drying_warmth()


func _drying_warmth() -> float:
	return clampf(inverse_lerp(drying_starts_c, drying_full_c, _felt_temp_c), 0.0, 1.0)


## Reads the ambient air temperature curve for the given hour of day.
func _sample_ambient_c(current_hour: float) -> float:
	var t: float = clampf(current_hour / HOURS_PER_DAY, 0.0, 1.0)
	var shaped: float = ambient_curve.sample(t) if ambient_curve != null else 0.5
	return lerpf(ambient_min_c, ambient_max_c, clampf(shaped, 0.0, 1.0))


## Highest-priority zone the player is standing in, or null when outdoors.
func _get_dominant_zone() -> ThermalZone:
	var best: ThermalZone = null
	for zone: ThermalZone in _zones:
		if best == null or zone.zone_priority > best.zone_priority:
			best = zone
	return best


func _set_wetness(value: float) -> void:
	var clamped: float = clampf(value, 0.0, 1.0)
	if is_equal_approx(clamped, _wetness):
		return
	_wetness = clamped
	wetness_changed.emit(_wetness)


func _emit_body_temperature() -> void:
	body_temperature_changed.emit(_body_temp_c, get_body_temperature_normalised())


## Recomputes the hypothermia stage and reports only real transitions.
func _update_stage() -> void:
	var next: Stage = Stage.NORMAL
	if _body_temp_c < critical_below_c:
		next = Stage.CRITICAL
	elif _body_temp_c < hypothermic_below_c:
		next = Stage.HYPOTHERMIC
	elif _body_temp_c < cold_below_c:
		next = Stage.COLD
	elif _body_temp_c < chilled_below_c:
		next = Stage.CHILLED
	if next == _stage:
		return
	_stage = next
	stage_changed.emit(_stage)


func _on_zone_entered(area: Area3D) -> void:
	var zone := area as ThermalZone
	if zone != null and not _zones.has(zone):
		_zones.append(zone)
		_emit_sheltered_edge()


func _on_zone_exited(area: Area3D) -> void:
	var zone := area as ThermalZone
	if zone != null:
		_zones.erase(zone)
		_emit_sheltered_edge()


func _emit_sheltered_edge() -> void:
	var sheltered: bool = is_sheltered()
	if sheltered == _was_sheltered:
		return
	_was_sheltered = sheltered
	sheltered_changed.emit(sheltered)
