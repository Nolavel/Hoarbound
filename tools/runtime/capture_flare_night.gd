extends SceneTree

## Matched shadow/scattering views in the real 727 at night; no unshadowed PNG.
## Modes: scattering (default), shadows, benchmark (timing only), legacy, smoke.
## Run with Forward+/Vulkan and --fixed-fps 30; user args: <output dir> [mode].

const SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"
const NIGHT_HOUR: float = 22.5
## [id, fog_energy, light_attenuation, range_breath]
const VARIANTS: Array = [
	["A_now", 1.0, 1.0, 1.0],
	["B_fog03", 0.3, 1.0, 1.0],
	["C_fog03_att2_steady", 0.3, 2.0, 0.0],
]

var _out: String = "user://shots/flare_night"
## Second arg "smoke": one wider close-up of the burning flare with its plume, nothing else.
var _smoke_only: bool = false
var _review: bool = false
var _compare_scattering: bool = false
var _benchmark_only: bool = false
var _report: Dictionary = {}
var _world: Node3D
var _player: Player


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	_smoke_only = args.size() > 1 and args[1] == "smoke"
	_review = args.size() < 2 or args[1] in ["shadows", "scattering", "benchmark"]
	_benchmark_only = args.size() > 1 and args[1] == "benchmark"
	_compare_scattering = args.size() < 2 or args[1] == "scattering"
	if _review:
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(960, 540)
		root.content_scale_size = Vector2i(960, 540)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_run()


func _run() -> void:
	_world = (load(SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(_world)
	var ctx: Variant = null
	for _i: int in range(600):
		await process_frame
		ctx = _world.call(&"get_context")
		if ctx != null:
			break
	if ctx == null:
		push_error("Flare capture: world context unavailable")
		quit(1)
		return
	_player = ctx.player as Player
	for weather: Node in _world.find_children("*", "WeatherController", true, false):
		weather.call(&"set_weather", &"calm", true)
	for node: Node in _world.find_children("*", "DayNightManager", true, false):
		node.set(&"total_game_time_hours", floorf(float(node.get(&"total_game_time_hours")) / 24.0) * 24.0 + NIGHT_HOUR)
		node.call(&"force_update_lighting")
		node.set_process(false)
	for layer: Node in root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	for label: Node in _world.find_children("*", "Label3D", true, false):
		(label as Node3D).visible = false
	var door := _world.find_children("HouseDoor", "", true, false)[0] as Node3D
	var out: Vector3 = door.global_basis.z
	out.y = 0.0
	out = out.normalized()
	var side: Vector3 = Vector3.UP.cross(out).normalized()

	var inventory := _player.get_node(^"InventoryComponent") as InventoryComponent
	inventory.try_add(load("res://data/items/road_flare.tres") as ItemResource)
	var held := _player.get_node(^"HeldLightComponent") as HeldLightComponent
	if _review:
		await _capture_shadow_review(held)
		return
	## Outside: Henry on open snow 7 m from the door, side-on to the camera.
	_player.global_position = door.global_position + out * 7.0 + Vector3.UP
	_player.look_at(_player.global_position + side, Vector3.UP)
	await _frames(60)
	print("[flare] lit=", held.light())
	await _frames(90)
	var henry: Vector3 = _player.global_position
	var flare: HeldFlare = held.get(&"_flare") as HeldFlare
	if _smoke_only:
		var top: Vector3 = (flare.get(&"_tip") as Node3D).global_position
		await _shot("smoke_close", top + out * 1.9 + side * 0.5 + Vector3.UP * 0.25, top + Vector3.UP * 0.45, flare)
		quit(0)
		return
	for v: Array in VARIANTS:
		_apply(flare, v)
		await _shot("out_" + String(v[0]), henry + out * 4.5 + side * 1.5 + Vector3.UP * 2.0, henry + Vector3.UP * 0.6, flare)
	## Close on the flare in Henry's hand, six frames apart, to see the jet and the spurts.
	_apply(flare, VARIANTS[2])
	var tip: Vector3 = (flare.get(&"_tip") as Node3D).global_position
	for i: int in range(6):
		await _shot("close_%d" % i, tip + out * 1.3 + side * 0.4 + Vector3.UP * 0.35, tip + Vector3.UP * 0.12, flare)
	## Inside 727, stove cold: the flare is the only light; framed across the room as the shadow capture.
	var stove := _world.find_children("*", "HeatSource", true, false)[0] as Node3D
	_player.global_position = stove.to_global(Vector3(1.4, 1.0, 0.6))
	await _frames(120)
	for v: Array in [VARIANTS[0], VARIANTS[2]]:
		_apply(flare, v)
		await _shot("in_" + String(v[0]), stove.to_global(Vector3(3.2, 1.7, 2.6)), stove.to_global(Vector3(1.3, 0.4, 0.5)), flare)
	print("[flare] done")
	quit(0)


func _apply(flare: HeldFlare, v: Array) -> void:
	flare.fog_energy = float(v[1])
	flare.light_attenuation = float(v[2])
	flare.range_breath = float(v[3])
	var light := flare.get(&"_light") as OmniLight3D
	light.light_volumetric_fog_energy = flare.fog_energy
	light.omni_attenuation = flare.light_attenuation


func _frames(count: int) -> void:
	for _i: int in range(count):
		await process_frame


func _shot(shot_name: String, from: Vector3, at: Vector3, flare: HeldFlare) -> void:
	var previous := root.get_camera_3d()
	var camera := Camera3D.new()
	camera.fov = 55.0
	camera.cull_mask &= ~(RenderLayers.RESERVED | RenderLayers.SCREEN_PASS)
	for control: Node in root.find_children("*", "Control", true, false):
		(control as Control).hide()
	root.add_child(camera)
	camera.look_at_from_position(from, at)
	camera.make_current()
	await _frames(24 if _review else (12 if shot_name.begins_with("close") else 40))
	await RenderingServer.frame_post_draw
	var error: Error = root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out).path_join(shot_name + ".png"))
	if error != OK:
		push_error("Flare capture: PNG save failed: " + error_string(error))
		quit(1)
		return
	var light := flare.get(&"_light") as OmniLight3D
	if _review:
		_report["captures"].append({"file": shot_name + ".png", "camera_from": _vector(from), "camera_at": _vector(at), "player_position": _vector(_player.global_position), "energy": light.light_energy, "tip_position": _vector(light.global_position), "scattering": flare.get_node(^"Tip/LocalScattering").visible})
	print("[flare] %s energy %.2f range %.2f fog %.2f att %.2f" % [shot_name, light.light_energy, light.omni_range, light.light_volumetric_fog_energy, light.omni_attenuation])
	camera.queue_free()
	if previous != null:
		previous.make_current()


## Paused pairs keep Henry, the burn energy and the particle state identical.
func _capture_shadow_review(held: HeldLightComponent) -> void:
	var stove := _world.find_children("*", "HeatSource", true, false)[0] as Node3D
	_player.global_position = stove.to_global(Vector3(1.4, 1.0, 0.6))
	await _frames(30)
	if not held.light():
		push_error("Flare capture: ignition failed")
		quit(1)
		return
	await _frames(30)
	var flare: HeldFlare = held.get(&"_flare") as HeldFlare
	flare.burn_duration_s = 300.0
	var light: OmniLight3D = flare.get(&"_light") as OmniLight3D
	var casters: Array[Dictionary] = []
	for mesh: Node in _player.find_children("*", "MeshInstance3D", true, false):
		casters.append({"path": String(mesh.get_path()), "visible": mesh.is_visible_in_tree(), "shadow_mode": mesh.cast_shadow})
	_report = {
		"renderer": RenderingServer.get_current_rendering_method(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"engine": Engine.get_version_info().string,
		"resolution": [root.size.x, root.size.y], "night_hour": NIGHT_HOUR,
		"shadow_bias": light.shadow_bias, "shadow_normal_bias": light.shadow_normal_bias,
		"shadow_mode": light.omni_shadow_mode, "casters": casters, "captures": [],
	}
	print("[review] player=", _player.global_position, " tip=", light.global_position)
	paused = true
	var room_from: Vector3 = stove.to_global(Vector3(3.2, 1.7, 2.6))
	var room_at: Vector3 = stove.to_global(Vector3(1.3, 0.8, 0.5))
	if not _benchmark_only:
		await _capture_pair("room", room_from, room_at, flare)
	var tip: Vector3 = light.global_position
	if not _benchmark_only:
		await _capture_pair("close", tip + Vector3(1.0, 0.35, 0.8), tip + Vector3.UP * 0.08, flare)
	var toward_light: Vector3 = light.global_position - _player.global_position
	toward_light.y = 0.0
	toward_light = toward_light.normalized()
	if not _benchmark_only:
		await _capture_pair("wall", _player.global_position + toward_light * 2.1 + Vector3.UP * 1.0, _player.global_position + Vector3.UP * 0.2, flare)
	paused = false
	held.drop()
	await _frames(90)
	var scattering: FogVolume = flare.get_node(^"Tip/LocalScattering") as FogVolume
	var dropped: RigidBody3D = flare.get_parent() as RigidBody3D
	_report["drop"] = {
		"same_flare": dropped != null and flare.is_burning(), "shadows": light.shadow_enabled,
		"tip_position": _vector(light.global_position), "scattering_at_tip": scattering.get_parent() == light.get_parent(),
	}
	print("[drop] ", JSON.stringify(_report["drop"]))
	paused = true
	if not _benchmark_only:
		await _capture_pair("drop", room_from, room_at, flare)
	await _benchmark(flare, room_from, room_at)
	flare.extinguish()
	_report["extinguished"] = not light.visible and not scattering.visible
	var file := FileAccess.open(ProjectSettings.globalize_path(_out).path_join("report.json"), FileAccess.WRITE)
	if file == null:
		push_error("Flare capture: cannot write report")
		quit(1)
		return
	file.store_string(JSON.stringify(_report, "\t"))
	quit(0 if _report["drop"]["same_flare"] and light.shadow_enabled and _report["extinguished"] and _report.has("performance") else 1)


func _capture_pair(view: String, from: Vector3, at: Vector3, flare: HeldFlare) -> void:
	var scattering := flare.get_node(^"Tip/LocalScattering") as FogVolume
	scattering.visible = false
	await _shot("stage1_" + view, from, at, flare)
	if _compare_scattering:
		scattering.visible = flare.scattering_density > 0.0
		await _shot("stage2_" + view, from, at, flare)


## The reference without shadows is timed only; no PNG of it is saved.
func _benchmark(flare: HeldFlare, from: Vector3, at: Vector3) -> void:
	var camera := Camera3D.new()
	camera.fov = 55.0
	camera.cull_mask &= ~(RenderLayers.RESERVED | RenderLayers.SCREEN_PASS)
	root.add_child(camera)
	camera.look_at_from_position(from, at)
	camera.make_current()
	var light := flare.get_node(^"Tip/FlareLight") as OmniLight3D
	var scattering := flare.get_node(^"Tip/LocalScattering") as FogVolume
	root.size = Vector2i(960, 540)
	root.content_scale_size = Vector2i(960, 540)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var results: Array[Dictionary] = []
	for round_index: int in range(2):
		var order: Array[int] = [0, 1, 2]
		if round_index == 1:
			order.reverse()
		for state: int in order:
			light.shadow_enabled = state > 0
			scattering.visible = state == 2
			await _frames(8)
			var samples: Array[float] = []
			var gpu_samples: Array[float] = []
			var origin: Vector3 = light.position
			for i: int in range(12):
				light.position = origin + Vector3(sin(float(i) * 0.2) * 0.003, 0.0, 0.0)
				var start: int = Time.get_ticks_usec()
				await process_frame
				await RenderingServer.frame_post_draw
				samples.append(float(Time.get_ticks_usec() - start) / 1000.0)
				gpu_samples.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
			light.position = origin
			samples.sort()
			gpu_samples.sort()
			var result: Dictionary = {"state": state, "round": round_index, "median_wall_ms": samples[6], "p95_wall_ms": samples[11], "median_render_ms": gpu_samples[6], "wall_ms": samples}
			results.append(result)
			print("[performance] ", JSON.stringify(result))
	light.shadow_enabled = flare.enable_shadows
	scattering.visible = flare.scattering_density > 0.0
	_report["benchmark_resolution"] = [root.get_texture().get_width(), root.get_texture().get_height()]
	_report["performance"] = results
	_report["performance_scope"] = "Paused 727 scene; moving light forces shadow updates. Software Vulkan, not target GPU. State 0: shadows off; 1: shadows; 2: shadows + local scattering."
	camera.queue_free()


func _vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]
