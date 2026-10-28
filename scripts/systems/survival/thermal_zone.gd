@tool
class_name ThermalZone
extends Area3D

## Static volume that modifies the felt temperature inside it: shelter interiors,
## wind shadows, caves. Placed in the level, never moved with the player.

## Emitted when the zone's own warmth changes, so interiors can be heated.
signal warmth_changed(current_offset_c: float)
## Emitted when a breach is boarded or torn open, for the HUD and audio.
signal protection_changed(sealed_fraction: float)

@export_group("Thermal")
## Degrees added to the felt temperature while inside. Interiors are positive.
@export var temperature_offset_c: float = 0.0
## Wind that reaches the player through a fully boarded shelter: 0 sealed,
## 1 exposed. Breaches are added on top of this, never subtracted from it.
@export_range(0.0, 1.0) var wind_exposure: float = 1.0
## Marks a fully enclosed space; blocks snowfall wetness and muffles wind audio.
@export var is_interior: bool = false

@export_group("Heating")
## Extra degrees this zone can gain from heat sources burning inside it.
@export var max_heated_offset_c: float = 0.0
## Optional small heat retention even with every opening exposed.
@export var minimum_heated_offset_c: float = 0.0
## Degrees per in-game hour the zone gains while a heat source burns inside.
@export var heating_rate_c_per_hour: float = 6.0
## Degrees per in-game hour the zone loses once nothing is burning.
@export var cooling_rate_c_per_hour: float = 3.0

@export_group("Priority")
## Higher value wins when zones overlap. Named to avoid Area3D.priority.
@export var zone_priority: int = 0

static var _registry: Array[ThermalZone] = []

var _heated_offset_c: float = 0.0
var _active_heat_sources: int = 0
var _breaches: Array[ShelterBreach] = []
var _heat_sources: Array[HeatSource] = []


func _ready() -> void:
	if not _registry.has(self):
		_registry.append(self)
	refresh_breaches()


func _exit_tree() -> void:
	_registry.erase(self)


## Frees can bypass _exit_tree, so drop out of the registry here as well.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_registry.erase(self)


## Every live zone in the tree: rooms warm and cool whether Henry is in them or not.
static func get_all() -> Array[ThermalZone]:
	var live: Array[ThermalZone] = []
	for zone: ThermalZone in _registry:
		if is_instance_valid(zone) and zone.is_inside_tree():
			live.append(zone)
	_registry = live
	return live


## Rebuilds the list of holes in this shelter. Called by a breach whenever it
## is boarded, torn open or retuned, so nothing polls.
func refresh_breaches() -> void:
	_breaches.clear()
	for child: Node in get_children():
		var breach := child as ShelterBreach
		if breach != null:
			_breaches.append(breach)
	protection_changed.emit(get_sealed_fraction())


## Every hole in this shelter, boarded or not.
func get_breaches() -> Array[ShelterBreach]:
	return _breaches


## How much of this shelter is closed off, 1.0 fully boarded (or breachless)
## down to 0.0. Scales how warm a fire can make the room.
func get_sealed_fraction() -> float:
	var open: float = 0.0
	for breach: ShelterBreach in _breaches:
		open += breach.severity * breach.get_open_fraction() * breach.get_exposure_multiplier()
	return clampf(1.0 - open, 0.0, 1.0)


## Wind that reaches the player, given which way it blows. The base leak plus
## every unboarded hole facing into it; a hole in the lee costs almost nothing.
func get_wind_exposure(wind_direction: Vector3 = Vector3.ZERO) -> float:
	var exposure: float = wind_exposure
	for breach: ShelterBreach in _breaches:
		exposure += breach.get_exposure_against(wind_direction)
	return clampf(exposure, 0.0, 1.0)


## The warmth a fire can build here. A holed shelter cannot hold heat however
## long it burns, which is what makes boarding up worth the trouble.
func get_heat_ceiling_c() -> float:
	return lerpf(minimum_heated_offset_c, max_heated_offset_c, get_sealed_fraction())


## The warmth accumulated from fires alone, without the zone's base offset.
func get_heated_offset_c() -> float:
	return _heated_offset_c


## Puts back warmth a save or a streamed-out chunk remembered; the ceiling still caps it.
func restore_heated_offset(offset_c: float) -> void:
	var previous: float = _heated_offset_c
	_heated_offset_c = clampf(offset_c, 0.0, maxf(max_heated_offset_c, 0.0))
	if not is_equal_approx(previous, _heated_offset_c):
		warmth_changed.emit(get_total_offset_c())


## Total offset this zone contributes right now, base plus accumulated heating.
func get_total_offset_c() -> float:
	return temperature_offset_c + _heated_offset_c


## Registers a burning heat source so the zone starts accumulating warmth.
func add_heat_source(source: HeatSource = null) -> void:
	_active_heat_sources += 1
	if source != null and not _heat_sources.has(source):
		_heat_sources.append(source)


## Unregisters a heat source; the zone cools once the count reaches zero.
func remove_heat_source(source: HeatSource = null) -> void:
	_active_heat_sources = maxi(0, _active_heat_sources - 1)
	_heat_sources.erase(source)


## Advances the zone's stored warmth. Called by ThermalManager with game hours.
func advance_heating(delta_hours: float) -> void:
	if max_heated_offset_c <= 0.0:
		return
	var previous: float = _heated_offset_c
	var ceiling: float = get_heat_ceiling_c()
	var intensity: float = 1.0 if _active_heat_sources > _heat_sources.size() else 0.0
	for source: HeatSource in HeatSource.get_all():
		if source.heats_zone == self:
			intensity = minf(1.0, intensity + source.get_step_intensity())
	if intensity > 0.0:
		_heated_offset_c = minf(
			ceiling, _heated_offset_c + heating_rate_c_per_hour * delta_hours * intensity
		)
	else:
		_heated_offset_c = maxf(0.0, _heated_offset_c - cooling_rate_c_per_hour * delta_hours)
	## Boards torn off mid-night drop the ceiling under the stored warmth.
	_heated_offset_c = minf(_heated_offset_c, ceiling)
	if not is_equal_approx(previous, _heated_offset_c):
		warmth_changed.emit(get_total_offset_c())
