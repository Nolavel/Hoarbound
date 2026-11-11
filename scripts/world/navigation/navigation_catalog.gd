class_name NavigationCatalog
extends RefCounted

## Small, explicit gameplay catalog, backed by the canonical two real-world
## landmark roles. It does not load the 13k-building editor Reality index.
## Add authored resources here when a location is approved for navigation.
const LANDMARKS_PATH: String = "res://data/world/key_west/reality/overrides/first_exit_landmarks.geojson"
const TARGET_FILES: PackedStringArray = [
	"res://data/world/key_west/navigation/fort_st_shelter.tres",
	"res://data/world/key_west/navigation/battery_osceola.tres",
]

var _by_id: Dictionary = {}
var _id_by_role: Dictionary = {}
var _ready: bool = false


func ensure_loaded() -> bool:
	if _ready:
		return true
	if not FileAccess.file_exists(LANDMARKS_PATH):
		push_error("NavigationCatalog: missing canonical landmark overrides")
		return false
	var payload: Variant = JSON.parse_string(FileAccess.get_file_as_string(LANDMARKS_PATH))
	if not payload is Dictionary:
		push_error("NavigationCatalog: invalid landmark FeatureCollection")
		return false

	var roles: Dictionary = {}
	for item: Variant in (payload as Dictionary).get("features", []):
		if not item is Dictionary:
			continue
		var props: Dictionary = (item as Dictionary).get("properties", {})
		var params: Dictionary = props.get("params", {})
		var role: String = String(params.get("role", ""))
		if role.is_empty():
			continue
		if roles.has(role):
			push_error("NavigationCatalog: duplicate reality role " + role)
			return false
		roles[role] = props

	var targets: Dictionary = {}
	var role_ids: Dictionary = {}
	for path: String in TARGET_FILES:
		var original: NavigationTarget = load(path) as NavigationTarget
		if original == null or original.id.is_empty() or original.world_role.is_empty():
			push_error("NavigationCatalog: missing or invalid resource: " + path)
			return false
		if targets.has(original.id) or role_ids.has(original.world_role):
			push_error("NavigationCatalog: duplicate ID/role in " + path)
			return false
		if not roles.has(original.world_role) or not original.has_valid_thresholds():
			push_error("NavigationCatalog: unbound role or invalid proximity tuning: " + path)
			return false
		var feature: Dictionary = roles[original.world_role]
		if String(feature.get("target_feature_id", "")) != original.feature_id:
			push_error("NavigationCatalog: reality feature mismatch: " + path)
			return false
		var params: Dictionary = feature.get("params", {})
		var xz: Array = params.get("bearing_local_xz", params.get("anchor_local_xz", []))
		if xz.size() < 2:
			push_error("NavigationCatalog: missing authored navigation anchor: " + path)
			return false
		var x: float = float(xz[0])
		var z: float = float(xz[1])
		if not is_finite(x) or not is_finite(z):
			push_error("NavigationCatalog: invalid anchor: " + path)
			return false
		var entry: NavigationTarget = original.duplicate(true) as NavigationTarget
		entry.bearing_xz = Vector2(x, z)
		targets[entry.id] = entry
		role_ids[entry.world_role] = entry.id
	_by_id = targets
	_id_by_role = role_ids
	_ready = true
	return true


func get_target(id: String) -> NavigationTarget:
	return _by_id.get(id) as NavigationTarget


func id_for_role(role: String) -> String:
	return String(_id_by_role.get(role, ""))


func target_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for id: Variant in _by_id.keys():
		ids.append(String(id))
	ids.sort()
	return ids
