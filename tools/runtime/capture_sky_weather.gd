extends SceneTree

const MAIN_SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"
const OUT_DIR: String = "res://docs/runtime_previews/sky_weather"
const PROFILE_IDS: Array[StringName] = [&"calm", &"snowfall", &"blizzard"]
const SHOT_NAMES: Array[String] = [
	"01_clear",
	"02_moderate_snow",
	"03_heavy_snow",
]
const FIRST_CAPTURE_FRAME: int = 180
const BETWEEN_SHOTS: int = 90

var _scene: Node3D
var _player: Player
var _weather: WeatherController
var _day_night: DayNightManager
var _camera: TpsCamera
var _frame: int = 0
var _shot: int = 0
var _next_capture: int = FIRST_CAPTURE_FRAME
var _bound: bool = false
var _thresholds: Array[float] = []
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
			_apply_profile(PROFILE_IDS[0])

	if not _bound or _frame < _next_capture:
		return false

	_capture_current()
	_shot += 1
	if _shot >= PROFILE_IDS.size():
		if not _validate_threshold_order():
			quit(1)
			return true
		_write_report()
		print("sky weather capture: complete thresholds=", _thresholds)
		quit()
		return true

	_apply_profile(PROFILE_IDS[_shot])
	_next_capture = _frame + BETWEEN_SHOTS
	return false


func _bind() -> bool:
	_player = get_first_node_in_group(&"player") as Player
	_weather = get_first_node_in_group(&"weather_controller") as WeatherController
	_day_night = _scene.get_node_or_null(^"WorldEnvironmentSystem/DayNightManager") as DayNightManager
	_camera = _scene.get_node_or_null(^"PlayerCamera") as TpsCamera
	if _player == null or _weather == null or _day_night == null or _camera == null:
		return false
	if _weather.profiles.is_empty() or _day_night.sky_material == null:
		return false

	var splash := _scene.get_node_or_null(^"StartupTitleCard")
	if splash != null:
		splash.queue_free()
	_player.set_physics_process(false)
	## Freeze the runtime TPS transform and tilt it upward so this acceptance
	## capture judges the cloud deck itself instead of mostly ground/fog.
	_camera.set_physics_process(false)
	var sky_rotation := _camera.global_rotation
	sky_rotation.x = deg_to_rad(24.0)
	_camera.global_rotation = sky_rotation
	_camera.make_current()

	## Lock all three frames to the same noon lighting and the same TPS camera.
	_day_night.total_game_time_hours = 12.0
	_day_night.force_update_lighting()
	return true


func _apply_profile(id: StringName) -> void:
	_weather.set_weather(id, true)
	_day_night.total_game_time_hours = 12.0
	_day_night.force_update_lighting()
	## Freeze cloud drift only for this A/B/C capture so all three images sample
	## the same authored noise phase. Snow particles and the weather profile stay live.
	_day_night.sky_material.set_shader_parameter("cloud_wind_speed", Vector2.ZERO)


func _capture_current() -> void:
	var profile: WeatherProfile = _weather.get_current_profile()
	if profile == null or profile.id != PROFILE_IDS[_shot]:
		push_error("sky weather capture: profile did not switch to %s" % PROFILE_IDS[_shot])
		return

	var threshold := float(_day_night.sky_material.get_shader_parameter("cloud_coverage"))
	var density := float(_day_night.sky_material.get_shader_parameter("cloud_density"))
	var opacity := float(_day_night.sky_material.get_shader_parameter("cloud_opacity"))
	var mask_top := float(_day_night.sky_material.get_shader_parameter("cloud_mask_top"))
	var shape_contrast := float(_day_night.sky_material.get_shader_parameter("cloud_shape_contrast"))
	var shadow_strength := float(_day_night.sky_material.get_shader_parameter("cloud_shadow_strength"))
	_thresholds.append(threshold)
	_report_rows.append({
		"profile": String(profile.id),
		"snowfall_density": profile.snowfall_density,
		"cloud_mask_threshold": threshold,
		"cloud_density": density,
		"cloud_opacity": opacity,
		"cloud_mask_top": mask_top,
		"cloud_shape_contrast": shape_contrast,
		"cloud_shadow_strength": shadow_strength,
	})
	var path := "%s/%s.png" % [OUT_DIR, SHOT_NAMES[_shot]]
	root.get_texture().get_image().save_png(path)
	print(
		"[sky-weather] ", SHOT_NAMES[_shot],
		" snow=", profile.snowfall_density,
		" threshold=", threshold,
		" density=", density,
		" opacity=", opacity,
		" mask_top=", mask_top,
		" shape=", shape_contrast,
		" shadow=", shadow_strength
	)


func _validate_threshold_order() -> bool:
	if _thresholds.size() != 3:
		push_error("sky weather capture: expected three threshold samples")
		return false
	var clear_threshold: float = _thresholds[0]
	var moderate_threshold: float = _thresholds[1]
	var heavy_threshold: float = _thresholds[2]
	if not is_equal_approx(clear_threshold, _day_night.settings.cloud_coverage):
		push_error("sky weather capture: calm weather no longer preserves authored baseline")
		return false
	if not (clear_threshold > moderate_threshold and moderate_threshold > heavy_threshold):
		push_error("sky weather capture: snowfall does not monotonically reveal more cloud")
		return false
	if heavy_threshold < 0.20 - 0.0001:
		push_error("sky weather capture: heavy snow exceeded the conservative threshold floor")
		return false
	return true


func _write_report() -> void:
	var report := {
		"camera_contract": "same runtime TPS camera position and noon lighting; camera tilted upward 24 deg for cloud readability",
		"threshold_semantics": "lower cloud_coverage uniform = more visible cloud",
		"samples": _report_rows,
	}
	var file := FileAccess.open("%s/report.json" % OUT_DIR, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
