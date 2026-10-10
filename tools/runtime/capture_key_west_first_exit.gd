extends SceneTree

const MAIN_SCENE: String = "res://scenes/world/key_west/key_west.tscn"
const OUT_DIR: String = "res://docs/runtime_previews/key_west_first_exit"

## Public-reference anchors projected into the existing NOAA local frame.
## Battery Osceola: historic concrete fortification at Fort Zachary Taylor.
## 727 Fort Street: CHI Key West Health Center / historic 1948 one-story masonry building.
const BATTERY_OSCEOLA := Vector2(-4052.73, 1924.69)
const FORT_727 := Vector2(-3531.78, 1590.28)
const OLD_CUSTOM_SHELTER := Vector2(-3579.85, 1574.51)
const FORT_727_YAW_DEG: float = 126.76

## Both landmarks sit inside the initial Key West detail radius, so the capture
## never re-scans streaming between shots. Each teleport gets rendered settle
## frames before the PNG is read back; otherwise screenshots contain the prior pose.
const FIRST_CAPTURE_FRAME: int = 60
const SETTLE_FRAMES: int = 3

var _scene: Node3D
var _player: Player
var _camera: TpsCamera
var _terrain: IslandTerrain
var _weather: WeatherController
var _landmarks: Node3D
var _frame: int = 0
var _shot: int = 0
var _next: int = FIRST_CAPTURE_FRAME
var _waiting_for_capture: bool = false


func _initialize() -> void:
	OS.set_environment("HFN_WORLD", "key_west_test")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_scene = (load(MAIN_SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 20:
		_bind()
	if _frame < _next or _player == null or _landmarks == null:
		return false

	if not _waiting_for_capture:
		if _shot == 0 and not _validate_start():
			quit(1)
			return true
		_place_shot(_shot)
		_waiting_for_capture = true
		_next = _frame + SETTLE_FRAMES
		return false

	_capture(_shot_name(_shot))
	_waiting_for_capture = false
	_shot += 1
	if _shot >= 7:
		_write_report()
		print("key west landmark capture: complete")
		quit()
		return true
	_next = _frame + 1
	return false


func _bind() -> void:
	_player = get_first_node_in_group(&"player") as Player
	_camera = _scene.get_node_or_null(^"PlayerCamera") as TpsCamera
	_terrain = _scene.get_node_or_null(^"IslandTerrain") as IslandTerrain
	for node: Node in _scene.get_children():
		if node is WeatherController:
			_weather = node as WeatherController
			break
	var splash := _scene.get_node_or_null(^"StartupTitleCard")
	if splash != null:
		splash.queue_free()
	if _player != null:
		_player.set_physics_process(false)
	if _terrain != null:
		_build_landmark_previews()


func _validate_start() -> bool:
	if _terrain == null:
		push_error("key west landmark capture: terrain did not initialize")
		return false
	if _weather == null or _weather.get_current_profile() == null:
		push_error("key west landmark capture: weather did not initialize")
		return false
	if _weather.get_current_profile().id != &"blizzard":
		push_error("key west landmark capture: first visible weather is not blizzard")
		return false
	return true


func _place_shot(index: int) -> void:
	var front := Vector2(sin(deg_to_rad(FORT_727_YAW_DEG)), cos(deg_to_rad(FORT_727_YAW_DEG)))
	var side := Vector2(cos(deg_to_rad(FORT_727_YAW_DEG)), -sin(deg_to_rad(FORT_727_YAW_DEG)))
	var route_dir := (FORT_727 - BATTERY_OSCEOLA).normalized()
	match index:
		0:
			_place_player(BATTERY_OSCEOLA + Vector2(65.0, 55.0), BATTERY_OSCEOLA)
		1:
			_place_player(BATTERY_OSCEOLA + Vector2(-70.0, 25.0), BATTERY_OSCEOLA)
		2:
			_place_player(BATTERY_OSCEOLA + route_dir * 62.0, BATTERY_OSCEOLA)
		3:
			_place_player(FORT_727 + front * 38.0, FORT_727)
		4:
			_place_player(FORT_727 + side * 36.0, FORT_727)
		5:
			_place_player(FORT_727 + (front + side).normalized() * 44.0, FORT_727)
		_:
			_place_player(BATTERY_OSCEOLA.lerp(FORT_727, 0.82), FORT_727)


func _shot_name(index: int) -> String:
	var names: Array[String] = [
		"01_battery_osceola_route_approach",
		"02_battery_osceola_west_flank",
		"03_battery_osceola_exit_relation",
		"04_727_fort_street_front",
		"05_727_petronia_side",
		"06_727_fort_petronia_corner",
		"07_route_context_to_727",
	]
	return names[index]


func _build_landmark_previews() -> void:
	_landmarks = Node3D.new()
	_landmarks.name = "FirstExitLandmarkPreview"
	_scene.add_child(_landmarks)
	_build_battery_osceola()
	_build_727_fort_street()


func _build_battery_osceola() -> void:
	var landmark := Node3D.new()
	landmark.name = "BatteryOsceolaPreview"
	landmark.position = Vector3(BATTERY_OSCEOLA.x, _ground_under(BATTERY_OSCEOLA, 30.0), BATTERY_OSCEOLA.y)
	landmark.rotation.y = deg_to_rad(7.0)
	_landmarks.add_child(landmark)

	var concrete := _material(Color(0.34, 0.36, 0.35), 0.96)
	var aged := _material(Color(0.25, 0.27, 0.26), 0.98)
	var earth := _material(Color(0.25, 0.29, 0.25), 1.0)
	var dark := _material(Color(0.045, 0.05, 0.05), 0.95)

	## Restrained exterior-only study: low stepped earthwork around a concrete core.
	## No armament is represented; the goal is the surviving architectural massing.
	_box(landmark, Vector3(0.0, 0.55, 0.0), Vector3(50.0, 1.1, 34.0), earth)
	_box(landmark, Vector3(0.0, 1.35, -1.0), Vector3(45.0, 1.0, 29.0), earth)
	_box(landmark, Vector3(0.0, 3.05, 0.0), Vector3(40.0, 4.3, 22.0), concrete)
	_box(landmark, Vector3(0.0, 4.95, -1.0), Vector3(34.0, 0.65, 18.0), aged)
	_box(landmark, Vector3(-10.0, 5.45, -1.0), Vector3(12.5, 0.55, 10.0), concrete)
	_box(landmark, Vector3(10.0, 5.45, -1.0), Vector3(12.5, 0.55, 10.0), concrete)
	_box(landmark, Vector3(0.0, 2.55, 11.25), Vector3(34.0, 3.2, 1.2), aged)
	_box(landmark, Vector3(0.0, 2.15, 11.92), Vector3(4.1, 2.45, 0.18), dark)
	_box(landmark, Vector3(-10.2, 3.0, 11.9), Vector3(5.5, 1.5, 0.16), concrete)
	_box(landmark, Vector3(10.2, 3.0, 11.9), Vector3(5.5, 1.5, 0.16), concrete)


func _build_727_fort_street() -> void:
	var landmark := Node3D.new()
	landmark.name = "Fort727Preview"
	landmark.position = Vector3(FORT_727.x, _ground_under(FORT_727, 18.0), FORT_727.y)
	landmark.rotation.y = deg_to_rad(FORT_727_YAW_DEG)
	_landmarks.add_child(landmark)

	var stucco := _material(Color(0.72, 0.66, 0.52), 0.91)
	var parapet := _material(Color(0.63, 0.58, 0.47), 0.94)
	var canopy := _material(Color(0.12, 0.14, 0.15), 0.9)
	var glass := _material(Color(0.10, 0.19, 0.23), 0.65)
	var door := _material(Color(0.16, 0.23, 0.25), 0.72)
	var concrete := _material(Color(0.44, 0.45, 0.43), 0.97)

	## 3,693 sq ft ~= 343 m2. 24 x 14.3 m keeps that documented footprint area
	## while the exact final footprint remains owned by the city/OSM landmark pass.
	_box(landmark, Vector3(0.0, 2.10, 0.0), Vector3(24.0, 4.2, 14.3), stucco)
	_box(landmark, Vector3(0.0, 4.42, 0.0), Vector3(24.5, 0.55, 14.8), parapet)
	_box(landmark, Vector3(0.0, 4.12, 0.0), Vector3(23.4, 0.22, 13.7), concrete)
	_box(landmark, Vector3(0.0, 3.45, 8.05), Vector3(20.0, 0.20, 2.15), canopy)
	for x: float in [-8.6, -2.9, 2.9, 8.6]:
		_box(landmark, Vector3(x, 1.65, 9.0), Vector3(0.16, 3.3, 0.16), canopy)
	for x: float in [-7.7, -4.0, 4.0, 7.7]:
		_box(landmark, Vector3(x, 2.05, 7.19), Vector3(2.7, 1.7, 0.12), glass)
	_box(landmark, Vector3(0.0, 1.75, 7.22), Vector3(2.1, 3.5, 0.14), door)
	for z: float in [-4.5, -1.3, 1.9, 5.1]:
		_box(landmark, Vector3(12.06, 2.05, z), Vector3(0.12, 1.65, 2.35), glass)
	_box(landmark, Vector3(0.0, 0.08, 9.2), Vector3(20.5, 0.16, 2.0), concrete)
	_box(landmark, Vector3(13.1, 0.08, 0.5), Vector3(2.0, 0.16, 11.0), concrete)


func _ground_under(center: Vector2, radius: float) -> float:
	var ground: float = INF
	for offset: Vector2 in [Vector2.ZERO, Vector2(radius, radius), Vector2(-radius, radius), Vector2(radius, -radius), Vector2(-radius, -radius)]:
		ground = minf(ground, maxf(_terrain.get_height(center.x + offset.x, center.y + offset.y), 0.0))
	return ground if ground != INF else 0.0


func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = 0.0
	return material


func _box(parent: Node3D, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.position = at
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(visual)
	return visual


func _place_player(p: Vector2, look: Vector2) -> void:
	var y: float = maxf(_terrain.get_height(p.x, p.y), 0.0) + 1.0
	_player.global_position = Vector3(p.x, y, p.y)
	var direction := (look - p).normalized()
	var yaw: float = atan2(direction.x, direction.y) + PI
	_player.global_rotation.y = yaw
	if _camera != null:
		_camera.set_look(yaw, -8.0)


func _find_streaming() -> StreamingSystem:
	for node: Node in _scene.get_children():
		if node is StreamingSystem:
			return node as StreamingSystem
	return null


func _capture(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT_DIR, name])
	print("[key-west-landmarks] ", name, " player=", _player.global_position)


func _write_report() -> void:
	var streaming := _find_streaming()
	var report := {
		"profile": "key_west_test",
		"battery_osceola": [BATTERY_OSCEOLA.x, BATTERY_OSCEOLA.y],
		"fort_727": [FORT_727.x, FORT_727.y],
		"old_custom_shelter_retained": [OLD_CUSTOM_SHELTER.x, OLD_CUSTOM_SHELTER.y],
		"route_distance_m": BATTERY_OSCEOLA.distance_to(FORT_727),
		"weather": String(_weather.get_current_profile().id),
		"snowfall_density": _weather.get_snowfall_density(),
		"wind_speed_mps": _weather.get_wind_speed_mps(),
		"stream_chunks": streaming.get_chunk_count() if streaming != null else 0,
		"captures": [
			"01_battery_osceola_route_approach.png",
			"02_battery_osceola_west_flank.png",
			"03_battery_osceola_exit_relation.png",
			"04_727_fort_street_front.png",
			"05_727_petronia_side.png",
			"06_727_fort_petronia_corner.png",
			"07_route_context_to_727.png",
		],
		"note": "Architectural review preview for #211. Battery and 727 are restrained authored capture geometry over the real NOAA/OSM world; final generator overrides remain separate acceptance work.",
	}
	var file := FileAccess.open("%s/report.json" % OUT_DIR, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
