class_name NavigationTarget
extends Resource

## Author-owned metadata for one *selectable* navigation destination.
## No global POI/quest map. XZ is bound at runtime to a canonical Reality
## landmark override, not copied from an editor-generated footprint.
enum Kind { SHELTER, LANDMARK }
enum ArrivalPolicy { EXPLICIT, SHELTER_ZONE }

@export var id: String = ""
@export var feature_id: String = ""
@export var world_role: String = ""
@export var internal_label: String = ""
@export var compass_title: String = ""
@export var kind: Kind = Kind.SHELTER
@export var arrival_policy: ArrivalPolicy = ArrivalPolicy.EXPLICIT

## Different destinations can tune the same five-word feedback independently.
@export var warm_enter_m: float = 280.0
@export var warm_exit_m: float = 295.0
@export var hot_enter_m: float = 65.0
@export var hot_exit_m: float = 75.0

## Runtime binding from first_exit_landmarks.geojson; never serialized twice.
var bearing_xz: Vector2 = Vector2.ZERO


func has_valid_thresholds() -> bool:
	return hot_enter_m > 0.0 and hot_enter_m < hot_exit_m \
		and hot_exit_m < warm_enter_m and warm_enter_m < warm_exit_m
