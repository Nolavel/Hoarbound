extends "res://tools/runtime/capture_snow_walk.gd"
## Looks down on Henry from above and from a high oblique after a walk, to find a square snow boundary.
## Args: <out_dir> 1.0 <quality>; Vulkan.


func _run() -> void:
	_world = (load(SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(_world)
	for i: int in range(600):
		await process_frame
		_ctx = _world.call(&"get_context")
		if _ctx != null:
			break
	_player = _ctx.player as CharacterBody3D
	_camera = _ctx.camera as Camera3D
	_streaming = _ctx.get_system(preload("res://core/world/streaming_system.gd")) as StreamingSystem
	_ground = _world.find_child("RealityGround", true, false)
	var shell := SnowShell.active as DeterministicSnowShell
	for node: Node in _world.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false
	_place()
	await _wait_streamed()
	shell.recentre_to(Vector2(_player.global_position.x, _player.global_position.z))
	await _wait_frames(30)
	if _camera.has_method(&"set_look"):
		_camera.call(&"set_look", _yaw, -16.0)
	Input.action_press(&"move_forward", 1.0)
	await _wait_frames(150)
	_release()
	await _wait_frames(20)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.far = 400.0
	var p: Vector3 = _player.global_position
	var shots: Array = [["top", p + Vector3(0.0, 40.0, 0.01)], ["oblique", p + Vector3(-18.0, 14.0, -18.0)],
		["tps_far", p + Vector3(-4.0, 3.0, -4.0)]]
	cam.make_current()
	for s: Array in shots:
		cam.global_position = s[1]
		cam.look_at(p, Vector3.FORWARD if s[0] == "top" else Vector3.UP)
		await _wait_frames(3)
		await RenderingServer.frame_post_draw
		_save(root.get_texture().get_image(), "%s.png" % s[0])
	for env_node: Node in _world.find_children("*", "WorldEnvironment", true, false):
		var env: Environment = (env_node as WorldEnvironment).environment
		if env != null:
			env.fog_enabled = false
			env.volumetric_fog_enabled = false
	cam.global_position = p + Vector3(0.0, 30.0, 0.01)
	cam.look_at(p, Vector3.FORWARD)
	await _wait_frames(3)
	await RenderingServer.frame_post_draw
	_save(root.get_texture().get_image(), "top_nofog.png")
	shell._mesh.visible = false
	shell.set_process(false)
	await _wait_frames(3)
	await RenderingServer.frame_post_draw
	_save(root.get_texture().get_image(), "top_nofog_nolocal.png")
	var vp: Vector2 = Vector2(root.get_visible_rect().size)
	var corners: Array = []
	for c: Vector2 in [shell.field.origin, shell.field.origin + Vector2(shell.window_m, shell.window_m)]:
		corners.append(cam.unproject_position(Vector3(c.x, p.y, c.y)))
	print("SNOW_SQUARE_CORNERS %s" % [corners])
	print("SNOW_SQUARE origin=%s window=%.1f henry=%s near_half=%.2f" % [shell.field.origin, shell.window_m, p, shell.near_half_m])
	quit(0)
