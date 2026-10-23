class_name ExtremityCold
extends RefCounted

## Cold load 0..1 on the head, hands and feet: what the HUD silhouette frosts over.
## A warning layer, not injuries; it follows felt cold, cover and wetness of that region.

const REGIONS: Array[StringName] = [&"head", &"hands", &"feet"]

## Effective region temperature at which load starts, and where it is full, °C.
var safe_c: float = -5.0
var severe_c: float = -35.0
## Extra chill a soaked garment adds to its region, °C.
var wet_chill_c: float = 8.0
## Approach rates per game hour while load builds and while it eases.
var build_rate: float = 1.5
var ease_rate: float = 2.5

var _load: Dictionary = {&"head": 0.0, &"hands": 0.0, &"feet": 0.0}


## Moves each region toward the load its effective temperature calls for.
## `protection` maps region -> {insulation_c, windproof, wetness}; a missing region is bare.
func advance(hours: float, felt_c: float, protection: Dictionary) -> void:
	if hours <= 0.0:
		return
	for region: StringName in REGIONS:
		var cover: Dictionary = protection.get(region, {})
		var effective: float = felt_c + float(cover.get("insulation_c", 0.0)) - float(cover.get("wetness", 0.0)) * wet_chill_c
		var target: float = clampf(inverse_lerp(safe_c, severe_c, effective), 0.0, 1.0)
		var current: float = _load[region]
		var rate: float = build_rate if target > current else ease_rate
		_load[region] = lerpf(current, target, 1.0 - exp(-rate * hours))


## Warm sleep or a full recovery clears every region.
func reset() -> void:
	for region: StringName in REGIONS:
		_load[region] = 0.0


func get_load(region: StringName) -> float:
	return float(_load.get(region, 0.0))


func get_save_data() -> Dictionary:
	var out: Dictionary = {}
	for region: StringName in REGIONS:
		out[String(region)] = _load[region]
	return out


func load_save_data(data: Dictionary) -> void:
	for region: StringName in REGIONS:
		_load[region] = clampf(float(data.get(String(region), 0.0)), 0.0, 1.0)
