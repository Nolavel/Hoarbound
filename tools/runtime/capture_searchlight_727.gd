extends SceneTree

## Uses the real 727 world, pickup, held prop and Forward+/Vulkan renderer.
const WORLD := preload("res://scenes/world/key_west/key_west_reality.tscn")
var output: String
var world: Node3D
var player: Player
var held: HeldItemComponent
var prop: HeldSearchlight
var camera: Camera3D
var capture_viewport: SubViewport
var render_camera: Camera3D
var report: Dictionary = {"frames": []}
var review_mode: bool = false

func _initialize() -> void:
	output = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://searchlight_727"
	review_mode = OS.get_cmdline_user_args().size() > 1 and OS.get_cmdline_user_args()[1] in ["review", "indicator", "grip_orbit"]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(640, 360)
	root.content_scale_size = Vector2i(640, 360)
	call_deferred("_run")

func _run() -> void:
	world = WORLD.instantiate()
	root.add_child(world)
	var ctx: Variant
	for i in range(600):
		await process_frame
		ctx = world.call(&"get_context")
		if ctx != null: break
	if ctx == null:
		push_error("searchlight: no world context");quit(1);return
	player = ctx.player as Player
	for weather: Node in world.find_children("*", "WeatherController", true, false):
		weather.call(&"set_weather", &"calm", true)
	for day: Node in world.find_children("*", "DayNightManager", true, false):
		day.set(&"total_game_time_hours", 12.0 if review_mode else 22.5)
		day.call(&"force_update_lighting")
		day.set_process(false)
	for layer: Node in root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	var stove := world.find_children("*", "HeatSource", true, false)[0] as Node3D
	var pickup := world.find_children("SearchlightShelter", "ItemPickup", true, false)[0] as ItemPickup
	var counter := pickup.get_parent().get_node(^"ReceptionCounter") as StaticBody3D
	var entrance := pickup.get_parent().get_node(^"HouseDoor") as Node3D
	assert(pickup.global_position.distance_to(counter.global_position + Vector3.UP * 0.525) < 0.6)
	assert(pickup.global_position.distance_to(entrance.global_position) < 3.0)
	assert(pickup.world_id == &"searchlight_727_reception")
	player.global_position = stove.to_global(Vector3(1.4, 1.0, 0.6))
	await _frames(5)
	report["renderer"] = RenderingServer.get_current_rendering_method()
	report["driver"] = RenderingServer.get_current_rendering_driver_name()
	report["adapter"] = RenderingServer.get_video_adapter_name()
	report["pickup_world_id"] = String(pickup.world_id)
	assert(pickup.pick_up(true))
	held = player.get_node(^"HeldItemComponent") as HeldItemComponent
	assert(held.present_owned(&"searchlight"))
	prop = held.get(&"_prop") as HeldSearchlight
	assert(prop != null and prop.lamp.shadow_enabled)
	if OS.get_cmdline_user_args().size() > 1 and OS.get_cmdline_user_args()[1] == "clock_check":
		var clock := world.find_children("*", "SimulationClock", true, false)[0] as SimulationClock
		var stored := player.get_node(^"InventoryComponent") as InventoryComponent
		prop.toggle()
		clock.advance_hours(0.25, &"searchlight_validation")
		assert(is_equal_approx(float(stored.get_first_instance_state(&"searchlight").get("searchlight_runtime_hours", -1.0)), 0.25))
		assert(held.put_away())
		clock.advance_hours(0.25, &"searchlight_validation")
		assert(is_equal_approx(float(stored.get_first_instance_state(&"searchlight").get("searchlight_runtime_hours", -1.0)), 0.25))
		print("SEARCHLIGHT_CLOCK_CHECK_OK")
		quit()
		return
	camera = Camera3D.new()
	camera.fov = 55.0
	camera.cull_mask &= ~(RenderLayers.RESERVED | RenderLayers.SCREEN_PASS)
	root.add_child(camera)
	camera.look_at_from_position(stove.to_global(Vector3(3.2, 1.7, 2.6)),stove.to_global(Vector3(1.3, 0.8, 0.5)))
	camera.make_current()
	capture_viewport = SubViewport.new()
	capture_viewport.name = "SearchlightCaptureViewport"
	capture_viewport.size = Vector2i(640, 360)
	capture_viewport.world_3d = root.world_3d
	capture_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(capture_viewport)
	render_camera = Camera3D.new()
	render_camera.fov = camera.fov
	render_camera.cull_mask = camera.cull_mask
	capture_viewport.add_child(render_camera)
	render_camera.make_current()
	var exposure := CameraAttributesPractical.new()
	exposure.exposure_multiplier = 2.0
	camera.attributes = exposure
	render_camera.attributes = exposure
	_hide_ui()
	await _frames(3 if OS.get_cmdline_user_args().size() > 1 and OS.get_cmdline_user_args()[1] == "grip_orbit" else 20)
	await _shot("off")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	held._unhandled_input(click)
	await _frames(3 if OS.get_cmdline_user_args().size() > 1 and OS.get_cmdline_user_args()[1] == "grip_orbit" else 20)
	await _shot("on")
	if OS.get_cmdline_user_args().size() > 1 and OS.get_cmdline_user_args()[1] == "grip_orbit":
		render_camera.fov = 36.0
		render_camera.look_at_from_position(prop.global_position + prop.global_basis.z * 0.85 + prop.global_basis.x * 0.55 + Vector3.UP * 0.25, prop.global_position)
		var fixed_view: Transform3D = render_camera.global_transform
		var body_forward: Vector3 = (player.get_node(^"HenryUALVisual") as HenryUALAnimation).global_basis.z.normalized()
		var body_right: Vector3 = (player.get_node(^"HenryUALVisual") as HenryUALAnimation).global_basis.x.normalized()
		for degrees: int in [0, 45, 90, 135, 180, 225, 270, 315]:
			var radians: float = deg_to_rad(float(degrees))
			var target_direction: Vector3 = body_forward * cos(radians) + body_right * sin(radians)
			camera.look_at_from_position(camera.global_position, camera.global_position + target_direction)
			await _frames(3)
			var beam_yaw: float = rad_to_deg(atan2(prop.direction.dot(body_right), prop.direction.dot(body_forward)))
			assert(absf(beam_yaw) <= 71.0)
			var grip_reach: StoveHandReach = (player.get_node(^"HenryUALVisual") as HenryUALAnimation).get_present_reach()
			assert(absf(grip_reach.fingers_world.dot(prop.direction)) < 0.02)
			render_camera.global_transform = fixed_view
			await RenderingServer.frame_post_draw
			capture_viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(output).path_join("grip_%03d.png" % degrees))
			print("SEARCHLIGHT_GRIP_ANGLE camera=", degrees, " beam=", beam_yaw)
		print("SEARCHLIGHT_GRIP_ORBIT_OK")
		quit()
		return
	if OS.get_cmdline_user_args().size() > 1 and OS.get_cmdline_user_args()[1] == "indicator":
		held.set_process(false)
		var reach: StoveHandReach = (player.get_node(^"HenryUALVisual") as HenryUALAnimation).get_present_reach()
		if reach.hand_solved.is_connected(held._on_searchlight_hand_solved):
			reach.hand_solved.disconnect(held._on_searchlight_hand_solved)
		prop.reparent(root, true)
		prop.top_level = true
		prop.global_position = stove.to_global(Vector3(3.2, 1.7, 2.6))
		prop.global_basis = Basis.IDENTITY
		var body_center: Vector3 = prop.global_position + Vector3(0.0, -0.13, 0.03)
		var side_view: Vector3 = body_center + Vector3(-0.72, 0.16, 0.0)
		camera.fov = 40.0
		render_camera.fov = camera.fov
		await _frames(18)
		camera.look_at_from_position(side_view, body_center)
		await _shot("indicator_full")
		prop.set_runtime_hours(24.0)
		await _frames(3)
		camera.look_at_from_position(side_view, body_center)
		await _shot("indicator_half")
		prop.set_runtime_hours(47.6)
		await _frames(3)
		camera.look_at_from_position(side_view, body_center)
		await _shot("indicator_low")
		prop.set_runtime_hours(48.0)
		await _frames(3)
		camera.look_at_from_position(side_view, body_center)
		await _shot("indicator_empty")
		print("SEARCHLIGHT_INDICATOR_OK renderer=", RenderingServer.get_current_rendering_method())
		quit()
		return
	if review_mode:
		await _shot("727_lit")
		var lamp_pos: Vector3 = prop.lamp.global_position
		camera.fov = 48.0
		render_camera.fov = camera.fov
		camera.look_at_from_position(lamp_pos + prop.global_basis.z * 0.85 + prop.global_basis.x * 0.45 + Vector3.UP * 0.28, lamp_pos + Vector3.UP * 0.08)
		await _frames(3)
		await _shot("henry_grip")
		print("SEARCHLIGHT_REVIEW_OK renderer=", RenderingServer.get_current_rendering_method(), " adapter=", RenderingServer.get_video_adapter_name())
		quit()
		return
	if OS.get_cmdline_user_args().size() > 1 and OS.get_cmdline_user_args()[1] in ["outdoor", "stow"]:
		var door := world.find_children("HouseDoor", "", true, false)[0] as Node3D
		var out: Vector3 = door.global_basis.z
		out.y = 0.0
		out = out.normalized()
		var side: Vector3 = Vector3.UP.cross(out).normalized()
		player.global_position = door.global_position + out * 7.0 + Vector3.UP
		player.look_at(player.global_position + side, Vector3.UP)
		camera.look_at_from_position(player.global_position + out * 3.0 + side * 1.4 + Vector3.UP * 1.2, player.global_position + Vector3.UP * 0.65)
		await _frames(20)
		await _shot("outside_on")
		if OS.get_cmdline_user_args()[1] == "stow":
			held._unhandled_input(click)
			await _frames(3)
			assert(not prop.lamp.visible)
			await _shot("outside_off")
			assert(held.put_away())
			await _frames(3)
			for frame: int in range(12):
				await process_frame
				render_camera.global_transform = camera.global_transform
				await RenderingServer.frame_post_draw
				capture_viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(output).path_join("stow_%03d.png" % frame))
			print("SEARCHLIGHT_STOW_OK")
			quit()
			return
		Input.action_press("move_forward")
		for frame: int in range(36):
			camera.look_at_from_position(player.global_position + out * 3.0 + side * 1.4 + Vector3.UP * 1.2, player.global_position + Vector3.UP * 0.65)
			await process_frame
			render_camera.global_transform = camera.global_transform
			await RenderingServer.frame_post_draw
			capture_viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(output).path_join("walk_%03d.png" % frame))
		Input.action_release("move_forward")
		await _shot("outside_walk")
		print("SEARCHLIGHT_OUTDOOR_OK")
		quit()
		return
	if OS.get_cmdline_user_args().size() > 1 and OS.get_cmdline_user_args()[1] == "probe":
		held.set_process(false)
		var lamp_pos: Vector3 = prop.lamp.global_position
		camera.look_at_from_position(lamp_pos + prop.global_basis.x * 0.7 + prop.global_basis.z * 0.6 + Vector3.UP * 0.35, lamp_pos)
		await _frames(3)
		await _shot("hero_close")
		camera.look_at_from_position(lamp_pos - prop.lamp.global_basis.z * 0.65 + prop.lamp.global_basis.x * 0.16 + Vector3.UP * 0.13, lamp_pos)
		await _frames(3)
		await _shot("hero_front")
		print("SEARCHLIGHT_PROBE_OK lamp=", lamp_pos, " player=", player.global_position)
		quit()
		return
	var start_ms := Time.get_ticks_msec()
	for i in range(144):
		var t: float = float(i) / 12.0
		camera.look_at_from_position(stove.to_global(Vector3(3.2 + sin(t * 0.8) * 0.25, 1.7, 2.6)),stove.to_global(Vector3(1.3 + sin(t * 0.8) * 0.35, 0.8, 0.5)))
		await process_frame
		render_camera.global_transform = camera.global_transform
		await RenderingServer.frame_post_draw
		capture_viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(output).path_join("frame_%03d.png" % i))
	report["capture_ms"] = Time.get_ticks_msec() - start_ms
	report["frames_count"] = 144
	report["spot_energy"] = prop.lamp.light_energy
	report["spot_range"] = prop.lamp.spot_range
	report["shadow_enabled"] = prop.lamp.shadow_enabled
	report["held"] = held.get_item_id() == &"searchlight"
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("SEARCHLIGHT_CAPTURE_OK ",JSON.stringify(report))
	quit()

func _frames(count: int) -> void:
	for i in range(count): await process_frame

func _shot(name: String) -> void:
	render_camera.global_transform = camera.global_transform
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	capture_viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(output).path_join(name + ".png"))

func _hide_ui() -> void:
	for layer: Node in root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	for control: Node in root.find_children("*", "Control", true, false):
		(control as Control).hide()
