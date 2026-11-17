extends SceneTree
## Run against an exported pack from an empty directory: godot --headless --main-pack <pck> --script <this>.
## The baked wind field must load there, or the snow falls back to the moving window (0.312b square).

const PROFILE: String = "res://data/world_profiles/key_west_reality.tres"


func _initialize() -> void:
	var profile: Resource = load(PROFILE)
	var path: String = String(profile.get(&"snow_wind_field_path")) if profile != null else ""
	var field := SnowField.new()
	var ok: bool = path != "" and field.load_wind_field(path)
	print("EXPORT_SNOW wind_field=%s loaded=%s" % [path, ok])
	quit(0 if ok else 1)
