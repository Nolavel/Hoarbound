class_name WorldProfile
extends Resource

## One terrain/content dataset that HFN can select.
## This resource stores paths and provenance only; it owns no runtime state.

@export var id: StringName = &""
@export var display_name: String = ""

@export_group("Terrain")
@export_file("*.png") var terrain_image_path: String = ""
@export_file("*.json") var terrain_meta_path: String = ""

@export_group("Streaming")
@export_file("*.tres") var world_data_path: String = ""

@export_group("Runtime content")
@export_file("*.tscn") var content_scene_path: String = ""
@export var spawn_marker_name: StringName = &"SpawnPoint"

@export_group("Initial weather")
@export var initial_weather_profile_id: StringName = &""
@export_range(-1.0, 360.0, 0.1) var wind_direction_override_deg: float = -1.0
@export var prewarm_before_first_frame: bool = false

@export_group("Snow")
## Baked city wind field (tools/world/bake_key_west_snow_wind.py); empty keeps the legacy bake.
@export_file("*.png") var snow_wind_field_path: String = ""

@export_group("Provenance")
@export var experimental: bool = false
@export var source_note: String = ""
@export var source_manifest_path: String = ""


func terrain_is_configured() -> bool:
	return terrain_image_path != "" and terrain_meta_path != ""


func terrain_files_exist() -> bool:
	return (
		terrain_is_configured()
		and FileAccess.file_exists(terrain_image_path)
		and FileAccess.file_exists(terrain_meta_path)
	)


func world_data_exists() -> bool:
	return world_data_path != "" and ResourceLoader.exists(world_data_path)


func content_scene_exists() -> bool:
	return content_scene_path == "" or ResourceLoader.exists(content_scene_path)


func is_runtime_ready() -> bool:
	var streaming_ready: bool = world_data_path == "" or world_data_exists()
	return id != &"" and terrain_files_exist() and streaming_ready and content_scene_exists()
