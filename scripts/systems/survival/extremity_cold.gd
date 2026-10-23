class_name ExtremityCold
extends RefCounted

## Cold load 0..1 and frost stage per BodyPartLibrary part: the HUD silhouette and frostbite.
## Load follows still air, the part's wind, cover and wetness; stages follow how long it lasts.

enum FrostStage { NONE, FROSTNIP, FROSTBITE }

## Extra chill a soaked garment adds to its part, °C.
var wet_chill_c: float = 8.0
## Approach rates per game hour while load builds and while it eases.
var build_rate: float = 1.5
var ease_rate: float = 2.5

var _library: BodyPartLibrary
## Per part id: {load, nip_hours, bite_hours, warm_hours, stage}.
var _parts: Dictionary = {}


func _init(library: BodyPartLibrary = null) -> void:
	_library = library if library != null else BodyPartLibrary.shared()
	for id: StringName in _library.get_ids():
		_parts[id] = _fresh()


## Moves each part toward its load, then its frost stage; returns the ids whose stage changed.
## `protection` maps garment region -> {insulation_c, windproof, wetness}; a missing one is bare.
func advance(hours: float, still_air_c: float, wind_chill_c: float, protection: Dictionary) -> Array[StringName]:
	var changed: Array[StringName] = []
	if hours <= 0.0:
		return changed
	for part: BodyPartDefinition in _library.parts:
		var state: Dictionary = _parts.get(part.id, _fresh())
		var cover: Dictionary = protection.get(part.garment_region, {})
		var wind: float = wind_chill_c * part.wind_exposure * (1.0 - float(cover.get("windproof", 0.0)))
		var effective: float = still_air_c - wind + float(cover.get("insulation_c", 0.0)) \
				- float(cover.get("wetness", 0.0)) * wet_chill_c
		var target: float = clampf(inverse_lerp(part.safe_c, part.severe_c, effective) * part.cold_sensitivity, 0.0, 1.0)
		var current: float = state["load"]
		var rate: float = build_rate if target > current else ease_rate
		state["load"] = lerpf(current, target, 1.0 - exp(-rate * hours))
		var before: int = state["stage"]
		_advance_stage(part, state, hours)
		_parts[part.id] = state
		if state["stage"] != before:
			changed.append(part.id)
	return changed


## Warm sleep or a full recovery clears every part, frostbite included.
func reset() -> Array[StringName]:
	var changed: Array[StringName] = []
	for id: StringName in _parts:
		if int(_parts[id]["stage"]) != FrostStage.NONE:
			changed.append(id)
		_parts[id] = _fresh()
	return changed


func get_load(id: StringName) -> float:
	return float(_parts.get(id, {}).get("load", 0.0))


func get_stage(id: StringName) -> FrostStage:
	return int(_parts.get(id, {}).get("stage", FrostStage.NONE)) as FrostStage


func get_library() -> BodyPartLibrary:
	return _library


func get_save_data() -> Dictionary:
	var out: Dictionary = {}
	for id: StringName in _parts:
		out[String(id)] = (_parts[id] as Dictionary).duplicate()
	return out


## Reads both this layout and the first one, which stored a bare load per part.
func load_save_data(data: Dictionary) -> void:
	for id: StringName in _parts:
		var saved: Variant = data.get(String(id), 0.0)
		var state: Dictionary = _fresh()
		if saved is Dictionary:
			for key: String in state:
				state[key] = (saved as Dictionary).get(key, state[key])
			state["stage"] = clampi(int(state["stage"]), FrostStage.NONE, FrostStage.FROSTBITE)
		else:
			state["load"] = float(saved)
		state["load"] = clampf(float(state["load"]), 0.0, 1.0)
		_parts[id] = state


## Time above the thresholds raises the stage; time warm lowers it, frostbite slowly.
func _advance_stage(part: BodyPartDefinition, state: Dictionary, hours: float) -> void:
	var cold: float = state["load"]
	state["nip_hours"] = float(state["nip_hours"]) + hours if cold >= part.frostnip_load else maxf(0.0, float(state["nip_hours"]) - hours)
	state["bite_hours"] = float(state["bite_hours"]) + hours if cold >= part.frostbite_load else maxf(0.0, float(state["bite_hours"]) - hours)
	state["warm_hours"] = float(state["warm_hours"]) + hours if cold <= part.thaw_load else 0.0
	match int(state["stage"]):
		FrostStage.NONE:
			if float(state["nip_hours"]) >= part.frostnip_hours:
				state["stage"] = FrostStage.FROSTNIP
				state["warm_hours"] = 0.0
		FrostStage.FROSTNIP:
			if float(state["bite_hours"]) >= part.frostbite_hours:
				state["stage"] = FrostStage.FROSTBITE
				state["warm_hours"] = 0.0
			elif float(state["warm_hours"]) >= part.frostnip_heal_hours:
				state["stage"] = FrostStage.NONE
				state["nip_hours"] = 0.0
		FrostStage.FROSTBITE:
			if float(state["warm_hours"]) >= part.frostbite_heal_hours:
				state["stage"] = FrostStage.FROSTNIP
				state["warm_hours"] = 0.0
				state["bite_hours"] = 0.0


static func _fresh() -> Dictionary:
	return {"load": 0.0, "nip_hours": 0.0, "bite_hours": 0.0, "warm_hours": 0.0, "stage": FrostStage.NONE}
