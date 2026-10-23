class_name ExtremityCold
extends RefCounted

## Cold load 0..1 on each BodyPartLibrary part: what the HUD silhouette frosts over.
## A warning layer, not injuries; it follows still air, the part's wind, cover and wetness.

## Extra chill a soaked garment adds to its part, °C.
var wet_chill_c: float = 8.0
## Approach rates per game hour while load builds and while it eases.
var build_rate: float = 1.5
var ease_rate: float = 2.5

var _library: BodyPartLibrary
var _load: Dictionary = {}


func _init(library: BodyPartLibrary = null) -> void:
	_library = library if library != null else BodyPartLibrary.shared()
	for id: StringName in _library.get_ids():
		_load[id] = 0.0


## Moves each part toward its load: still air minus the wind its exposure lets through, plus cover.
## `protection` maps garment region -> {insulation_c, windproof, wetness}; a missing one is bare.
func advance(hours: float, still_air_c: float, wind_chill_c: float, protection: Dictionary) -> void:
	if hours <= 0.0:
		return
	for part: BodyPartDefinition in _library.parts:
		var cover: Dictionary = protection.get(part.garment_region, {})
		var wind: float = wind_chill_c * part.wind_exposure * (1.0 - float(cover.get("windproof", 0.0)))
		var effective: float = still_air_c - wind + float(cover.get("insulation_c", 0.0)) \
				- float(cover.get("wetness", 0.0)) * wet_chill_c
		var target: float = clampf(inverse_lerp(part.safe_c, part.severe_c, effective) * part.cold_sensitivity, 0.0, 1.0)
		var current: float = _load.get(part.id, 0.0)
		var rate: float = build_rate if target > current else ease_rate
		_load[part.id] = lerpf(current, target, 1.0 - exp(-rate * hours))


## Warm sleep or a full recovery clears every part.
func reset() -> void:
	for id: StringName in _load:
		_load[id] = 0.0


func get_load(id: StringName) -> float:
	return float(_load.get(id, 0.0))


func get_library() -> BodyPartLibrary:
	return _library


func get_save_data() -> Dictionary:
	var out: Dictionary = {}
	for id: StringName in _load:
		out[String(id)] = _load[id]
	return out


func load_save_data(data: Dictionary) -> void:
	for id: StringName in _load:
		_load[id] = clampf(float(data.get(String(id), 0.0)), 0.0, 1.0)
