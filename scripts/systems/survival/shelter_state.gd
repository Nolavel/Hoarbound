class_name ShelterState
extends Node

## Remembers physical board placement, fuel and room warmth across streaming and sleep saves.

signal shelter_changed(zone_path: String, sealed_fraction: float)

const SEPARATOR: String = "/"

var _world: Node
## Values are breach save dictionaries. Legacy saves may still contain bools.
var _boarded: Dictionary = {}
var _fires: Dictionary = {}
## Accumulated fire warmth per zone name, °C over the zone's base offset.
var _heat: Dictionary = {}


func on_world_ready(context: WorldContext) -> void:
	_world = context.world
	for zone: ThermalZone in find_zones():
		adopt_zone(zone)


func find_zones() -> Array[ThermalZone]:
	var zones: Array[ThermalZone] = []
	_collect(_world, zones)
	return zones


func adopt_zone(zone: ThermalZone) -> void:
	if zone == null:
		return
	for breach: ShelterBreach in zone.get_breaches():
		var key: String = _key(zone, breach)
		if _boarded.has(key):
			_apply_saved_breach(breach, _boarded[key])
		else:
			_boarded[key] = breach.get_save_data()
		if not breach.coverage_changed.is_connected(_on_breach_coverage_changed):
			breach.coverage_changed.connect(_on_breach_coverage_changed.bind(zone, breach))
		if not breach.staged_boards_changed.is_connected(_on_staged_changed):
			breach.staged_boards_changed.connect(_on_staged_changed.bind(zone, breach))
	for fire: HeatSource in find_fires_in(zone):
		adopt_fire(zone, fire)
	if _heat.has(String(zone.name)):
		zone.restore_heated_offset(float(_heat[String(zone.name)]))
	if not zone.warmth_changed.is_connected(_on_warmth_changed):
		zone.warmth_changed.connect(_on_warmth_changed.bind(zone))


static func find_fires_in(zone: ThermalZone) -> Array[HeatSource]:
	var fires: Array[HeatSource] = []
	_collect_fires(zone, fires)
	return fires


func adopt_fire(zone: ThermalZone, fire: HeatSource) -> void:
	if fire == null:
		return
	var key: String = _fire_key(zone, fire)
	if _fires.has(key):
		var stored: Dictionary = _fires[key]
		_restore_fire(fire, stored)
	else:
		_remember_fire(key, fire)
	var visual := fire.find_child("StoveVisual", true, false) as StoveVisual
	if visual != null and not visual.presentation_changed.is_connected(_on_visual_changed):
		visual.presentation_changed.connect(_on_visual_changed.bind(key,fire))
	if not fire.fuel_changed.is_connected(_on_fuel_changed):
		fire.fuel_changed.connect(_on_fuel_changed.bind(key, fire))
	if not fire.tinder_changed.is_connected(_on_tinder_changed):
		fire.tinder_changed.connect(_on_tinder_changed.bind(key, fire))


func get_save_key() -> StringName:
	return &"shelter"


func get_save_data() -> Dictionary:
	for zone: ThermalZone in find_zones():
		for fire: HeatSource in find_fires_in(zone):
			_remember_fire(_fire_key(zone, fire), fire)
	return {"boarded": _boarded.duplicate(true), "fires": _fires.duplicate(true), "heat": _heat.duplicate(true)}


func load_save_data(data: Dictionary) -> void:
	_boarded = Dictionary(data.get("boarded", {})).duplicate(true)
	_fires = Dictionary(data.get("fires", {})).duplicate(true)
	_heat = Dictionary(data.get("heat", {})).duplicate(true)
	for zone: ThermalZone in find_zones():
		for breach: ShelterBreach in zone.get_breaches():
			var key: String = _key(zone, breach)
			if _boarded.has(key):
				_apply_saved_breach(breach, _boarded[key])
		for fire: HeatSource in find_fires_in(zone):
			var fire_key: String = _fire_key(zone, fire)
			if not _fires.has(fire_key):
				continue
			var stored: Dictionary = _fires[fire_key]
			_restore_fire(fire, stored)
		zone.restore_heated_offset(float(_heat.get(String(zone.name), 0.0)))


func _apply_saved_breach(breach: ShelterBreach, saved: Variant) -> void:
	if typeof(saved) == TYPE_DICTIONARY:
		breach.load_save_data(saved as Dictionary)
	elif bool(saved):
		breach.board_up()
	else:
		breach.tear_open()


func _on_breach_coverage_changed(_coverage: float, zone: ThermalZone, breach: ShelterBreach) -> void:
	_remember_breach(zone, breach)


func _on_staged_changed(_count: int, zone: ThermalZone, breach: ShelterBreach) -> void:
	_remember_breach(zone, breach)


func _remember_breach(zone: ThermalZone, breach: ShelterBreach) -> void:
	_boarded[_key(zone, breach)] = breach.get_save_data()
	shelter_changed.emit(String(zone.get_path()), zone.get_sealed_fraction())


func _on_warmth_changed(_total_c: float, zone: ThermalZone) -> void:
	_heat[String(zone.name)] = zone.get_heated_offset_c()


func _on_fuel_changed(_fraction: float, key: String, fire: HeatSource) -> void:
	_remember_fire(key, fire)


func _on_tinder_changed(_prepared: bool, key: String, fire: HeatSource) -> void:
	_remember_fire(key, fire)


func _remember_fire(key: String, fire: HeatSource) -> void:
	_fires[key] = fire.get_fire_save_data()
	var visual := fire.find_child("StoveVisual", true, false) as StoveVisual
	if visual != null:
		_fires[key]["presentation"] = visual.get_presentation_save_data()


func _fire_key(zone: ThermalZone, fire: HeatSource) -> String:
	return "%s%s%s" % [zone.name, SEPARATOR, fire.name]


static func _collect_fires(node: Node, out: Array[HeatSource]) -> void:
	if node == null:
		return
	var fire := node as HeatSource
	if fire != null:
		out.append(fire)
	for child: Node in node.get_children():
		_collect_fires(child, out)


func _key(zone: ThermalZone, breach: ShelterBreach) -> String:
	return "%s%s%s" % [zone.name, SEPARATOR, breach.name]


static func _collect(node: Node, out: Array[ThermalZone]) -> void:
	if node == null:
		return
	var zone := node as ThermalZone
	if zone != null:
		out.append(zone)
	for child: Node in node.get_children():
		_collect(child, out)


func _on_visual_changed(key: String, fire: HeatSource) -> void:
	_remember_fire(key,fire)

func _restore_fire(fire: HeatSource, data: Dictionary) -> void:
	fire.restore_fire_save_data(data)
	var visual := fire.find_child("StoveVisual", true, false) as StoveVisual
	if visual != null:
		visual.restore_presentation(data.get("presentation", {}))
