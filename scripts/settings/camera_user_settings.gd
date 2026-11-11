class_name CameraUserSettings
extends RefCounted

## Persistent player-owned TPS camera preferences.
## The Settings UI stages edits; only Accept writes this file.
const CONFIG_PATH: String = "user://settings.cfg"
const SECTION: String = "camera"

const DEFAULT_MOUSE_SENSITIVITY: float = 1.0
const MIN_MOUSE_SENSITIVITY: float = 0.25
const MAX_MOUSE_SENSITIVITY: float = 2.0
const DEFAULT_INVERT_Y: bool = false
## Number keys: default, least, most. Field of view is degrees added to the authored lens.
const RANGES: Dictionary = {
	"mouse_sensitivity_multiplier": [DEFAULT_MOUSE_SENSITIVITY, MIN_MOUSE_SENSITIVITY, MAX_MOUSE_SENSITIVITY],
	"stick_sensitivity_multiplier": [1.0, 0.25, 2.0],
	"fov_offset_deg": [0.0, -10.0, 15.0],
	"distance_scale": [1.0, 0.75, 1.3],
}
const FLAGS: Dictionary = {
	"invert_y": DEFAULT_INVERT_Y,
	"left_shoulder": false,
}

## The file read and written; a test points it away from the player's own.
static var config_path: String = CONFIG_PATH


static func defaults() -> Dictionary:
	var result: Dictionary = {}
	for key: String in RANGES:
		result[key] = float(RANGES[key][0])
	for key: String in FLAGS:
		result[key] = bool(FLAGS[key])
	return result


static func load_camera() -> Dictionary:
	var result: Dictionary = defaults()
	var config := ConfigFile.new()
	var error: Error = config.load(config_path)
	if error == ERR_FILE_NOT_FOUND:
		return result
	if error != OK:
		push_warning("CameraUserSettings: cannot read %s (error %d); using defaults" % [config_path, error])
		return result
	for key: String in RANGES:
		var raw: Variant = config.get_value(SECTION, key, RANGES[key][0])
		if typeof(raw) == TYPE_FLOAT or typeof(raw) == TYPE_INT:
			result[key] = clampf(float(raw), float(RANGES[key][1]), float(RANGES[key][2]))
	for key: String in FLAGS:
		var raw: Variant = config.get_value(SECTION, key, FLAGS[key])
		if typeof(raw) == TYPE_BOOL:
			result[key] = bool(raw)
	return result


## Writes the keys of `values` this store knows, clamped; other keys and sections of the file are kept.
static func save_values(values: Dictionary) -> Error:
	var config := ConfigFile.new()
	var load_error: Error = config.load(config_path)
	if load_error != OK and load_error != ERR_FILE_NOT_FOUND:
		config = ConfigFile.new()
	for key: String in RANGES:
		if values.has(key):
			config.set_value(SECTION, key, clampf(float(values[key]), float(RANGES[key][1]), float(RANGES[key][2])))
	for key: String in FLAGS:
		if values.has(key):
			config.set_value(SECTION, key, bool(values[key]))
	return config.save(config_path)


static func save_camera(mouse_sensitivity_multiplier: float, invert_y: bool) -> Error:
	return save_values({"mouse_sensitivity_multiplier": mouse_sensitivity_multiplier, "invert_y": invert_y})
