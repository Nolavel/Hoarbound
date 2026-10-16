extends SceneTree

const MAIN_SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"
const OUT_DIR: String = "res://docs/runtime_previews/sky_weather"

## Reuse the production painterly street shot instead of the runtime spawn.
## This is an open Petronia Street view with enough sky and street silhouettes
## to judge cloud volume without moving the camera between weather/time states.
const STREET_AT := Vector2(-3163.0, 1363.0)
const STREET_LOOK := Vector2(-3115.0, 1331.0)
const STREET_PITCH_DEG: float = 10.0

const SHOTS: Array[Dictionary] = [
	{"name": "01_day_calm", "profile": &"calm", "hour": 12.0, "period": "day"},
	{"name": "02_day_windy", "profile": &"windy", "hour": 12.0, "period": "day"},
	{"name": "03_day_blizzard", "profile": &"blizzard", "hour": 12.0, "period": "day"},
	{"name": "04_night_calm", "profile": &"calm", "hour": 23.0, "period": "night"},
	{"name": "05_night_windy", "profile": &"windy", "hour": 23.0, "period": "night"},
	{"name": "06_night_blizzard", "profile": &"blizzard", "hour": 23.0, "period": "night"},
]

const FIRST_CAPTURE_FRAME: int = 240
const BETWEEN_SHOTS: int = 90

var _scene: Node3D
var _player: Player
var _weather: WeatherController
var _day_night: DayNightManager
var _camera: TpsCamera
var _ground: Node
var _frame: int = 0
var _shot: int = 0
var _next_capture: int = FIRST_CAPTURE_FRAME
var _bound: bool = false
var _report_rows: Array[Dictionary] = []


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_scene = (load(MAIN_SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frame += 1
	if not _bound and _frame >= 30:
		_bound = _bind()
		if _bound:
			_apply_shot(SHOTS[0])

	if not _bound or _frame < _next_capture:
		return false

	_capture_current(SHOTS[_shot])
	_shot += 1
	if _shot >= SHOTS.size():
		if not _validate_capture_contract():
			quit(1)
			return true
		_write_report()
		print("sky weather capture: complete six-frame day/night street matrix")
		quit()
		return true

	_apply_shot(SHOTS[_shot])
	_next_capture = _frame + BETWEEN_SHOTS
	return false


func _bind() -> bool:
	_player = get_first_node_in_group(&"player") as Player
	_weather = get_first_node_in_group(&"weather_controller") as WeatherController
	_day_night = _scene.get_node_or_null(^"WorldEnvironmentSystem/DayNightManager") as DayNightManager
	_camera = _scene.get_node_or_null(^"PlayerCamera") as TpsCamera
	_ground = _scene.find_child("RealityGround", true, false)
	if _player == null or _weather == null or _day_night == null or _camera == null or _ground == null:
		return false
	if _weather.profiles.is_empty() or _day_night.sky_material == null:
		return false

	var splash := _scene.get_node_or_null(^"StartupTitleCard")
	if splash != null:
		splash.queue_free()

	_player.set_physics_process(false)
	_camera.set_physics_process(false)
	_place_open_street_camera()
	_camera.make_current()
	return true


func _place_open_street_camera() -> void:
	var ground_y := _ground_height(STREET_AT.x, STREET_AT.y)
	_player.global_position = Vector3(STREET_AT.x, ground_y + 1.0, STREET_AT.y)
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()

	var direction := Vector3(
		STREET_LOOK.x - STREET_AT.x,
		0.0,
		STREET_LOOK.y - STREET_AT.y
	).normalized()
	var yaw := atan2(-direction.x, -direction.z)
	_player.rotation.y = yaw
	_camera.call(&"set_look", yaw, STREET_PITCH_DEG)
	_camera.make_current()


func _ground_height(x: float, z: float) -> float:
	if _ground != null and _ground.has_method(&"get_height"):
		return float(_ground.call(&"get_height", x, z))
	return 0.0


func _apply_shot(shot: Dictionary) -> void:
	var profile_id: StringName = shot["profile"]
	var hour: float = shot["hour"]
	_weather.set_weather(profile_id, true)
	_day_night.total_game_time_hours = hour
	_day_night.force_update_lighting()
	## Every frame samples the same authored cloud phase. Weather still changes
	## density/mask/contrast/opacity, but drift cannot move the composition.
	_day_night.sky_material.set_shader_parameter("cloud_wind_speed", Vector2.ZERO)
	## Weather/time changes must never move the acceptance camera.
	_place_open_street_camera()


func _capture_current(shot: Dictionary) -> void:
	var expected_profile: StringName = shot["profile"]
	var profile: WeatherProfile = _weather.get_current_profile()
	if profile == null or profile.id != expected_profile:
		push_error("sky weather capture: profile did not switch to %s" % expected_profile)
		return

	var threshold := float(_day_night.sky_material.get_shader_parameter("cloud_coverage"))
	var density := float(_day_night.sky_material.get_shader_parameter("cloud_density"))
	var opacity := float(_day_night.sky_material.get_shader_parameter("cloud_opacity"))
	var mask_top := float(_day_night.sky_material.get_shader_parameter("cloud_mask_top"))
	var shape_contrast := float(_day_night.sky_material.get_shader_parameter("cloud_shape_contrast"))
	var shadow_strength := float(_day_night.sky_material.get_shader_parameter("cloud_shadow_strength"))
	var path := "%s/%s.png" % [OUT_DIR, String(shot["name"])]
	root.get_texture().get_image().save_png(path)

	_report_rows.append({
		"shot": String(shot["name"]),
		"period": String(shot["period"]),
		"hour": float(shot["hour"]),
		"profile": String(profile.id),
		"snowfall_density": profile.snowfall_density,
		"cloud_mask_threshold": threshold,
		"cloud_density": density,
		"cloud_opacity": opacity,
		"cloud_mask_top": mask_top,
		"cloud_shape_contrast": shape_contrast,
		"cloud_shadow_strength": shadow_strength,
		"png": path,
	})

	print(
		"[sky-weather] ", String(shot["name"]),
		" hour=", shot["hour"],
		" profile=", profile.id,
		" snow=", profile.snowfall_density,
		" threshold=", threshold,
		" density=", density,
		" opacity=", opacity,
		" mask_top=", mask_top,
		" shape=", shape_contrast,
		" shadow=", shadow_strength
	)


func _validate_capture_contract() -> bool:
	if _report_rows.size() != 6:
		push_error("sky weather capture: expected six day/night samples")
		return false

	for offset in [0, 3]:
		var calm: Dictionary = _report_rows[offset]
		var windy: Dictionary = _report_rows[offset + 1]
		var blizzard: Dictionary = _report_rows[offset + 2]
		var calm_threshold := float(calm["cloud_mask_threshold"])
		var windy_threshold := float(windy["cloud_mask_threshold"])
		var blizzard_threshold := float(blizzard["cloud_mask_threshold"])
		if not is_equal_approx(calm_threshold, _day_night.settings.cloud_coverage):
			push_error("sky weather capture: calm no longer preserves authored cloud baseline")
			return false
		if not (calm_threshold > windy_threshold and windy_threshold > blizzard_threshold):
			push_error("sky weather capture: calm/windy/blizzard cloud thresholds are not ordered")
			return false
		if blizzard_threshold < 0.20 - 0.0001:
			push_error("sky weather capture: blizzard exceeded the conservative threshold floor")
			return false

	return true


func _write_report() -> void:
	var report := {
		"camera_contract": "one fixed open Petronia Street TPS camera for all six frames",
		"street_at_xz": [STREET_AT.x, STREET_AT.y],
		"street_look_xz": [STREET_LOOK.x, STREET_LOOK.y],
		"camera_pitch_deg": STREET_PITCH_DEG,
		"time_matrix": "day=12:00, night=23:00",
		"weather_matrix": ["calm", "windy", "blizzard"],
		"threshold_semantics": "lower cloud_coverage uniform = more visible cloud",
		"samples": _report_rows,
	}
	var file := FileAccess.open("%s/report.json" % OUT_DIR, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
