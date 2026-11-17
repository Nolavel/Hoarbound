extends "res://tools/runtime/capture_snow_walk.gd"
## Reads the GPU packed-snow field at fixed world points beside Henry's walk line. Snow away from his prints
## must not change while he walks. Args: <out_dir> 1.0 <quality>; Vulkan.


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
	_place()
	await _wait_streamed()
	shell.recentre_to(Vector2(_player.global_position.x, _player.global_position.z))
	await _wait_frames(60)
	if _camera.has_method(&"set_look"):
		_camera.call(&"set_look", _yaw, -16.0)
	var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var side := Vector3(fwd.z, 0.0, -fwd.x)
	var probes: Array[Vector2] = []
	for a: float in [0.0, 2.0, 4.0, 6.0, 8.0]:
		for b: float in [-4.0, -2.5, -1.5, 1.5, 2.5, 4.0]:
			var w: Vector3 = _player.global_position + fwd * a + side * b
			probes.append(Vector2(w.x, w.z))
	var first: Array[float] = []
	var worst: Array[float] = []
	var moves: int = 0
	var origin: Vector2 = shell.field.origin
	Input.action_press(&"move_forward", 1.0)
	for f: int in range(300):
		await process_frame
		if f % 6 != 0:
			continue
		await RenderingServer.frame_post_draw
		if shell.field.origin != origin:
			origin = shell.field.origin
			moves += 1
		var img: Image = shell._accum[shell._parity].get_texture().get_image()
		var n: int = img.get_width()
		for k: int in range(probes.size()):
			var uv: Vector2 = (probes[k] - shell.field.origin) / shell.window_m
			var v: float = img.get_pixelv(Vector2i((uv * n).floor()).clamp(Vector2i.ZERO, Vector2i(n - 1, n - 1))).r
			if first.size() < probes.size():
				first.append(v)
				worst.append(0.0)
			else:
				worst[k] = maxf(worst[k], absf(v - first[k]))
	_release()
	var order: Array = range(worst.size())
	order.sort_custom(func(a: int, b: int) -> bool: return worst[a] > worst[b])
	var top: Array[String] = []
	for k: int in order.slice(0, 6):
		top.append("%.3f@%s" % [worst[k], str(probes[k] - Vector2(_player.global_position.x, _player.global_position.z))])
	print("SNOW_PACKED moves=%d first_range=[%.3f, %.3f] worst=%s" % [moves, first.min(), first.max(), ", ".join(top)])
	quit(0)
