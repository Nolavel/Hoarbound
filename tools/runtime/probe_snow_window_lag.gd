extends "res://tools/runtime/capture_snow_walk.gd"
## Henry walks straight down Duval Street; logs how close he gets to the local snow window's rim.
## Run at the owner's frame rate: godot --headless --fixed-fps 9 --script <this> -- <out_dir> 1.0 low [seconds]


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
	await _wait_frames(30)
	if _camera.has_method(&"set_look"):
		_camera.call(&"set_look", _yaw, -16.0)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var seconds: float = float(args[3]) if args.size() > 3 else 30.0
	var plants: Array[int] = [0]
	shell._sensor.foot_planted.connect(func(_s: int, _p: Vector3, _n: Vector3, _f: Vector3, _v: float) -> void: plants[0] += 1)
	## Fixed world points off the walk line: the snow top there must not move while Henry walks.
	var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var side := Vector3(fwd.z, 0.0, -fwd.x)
	var probes: Array[Vector2] = []
	for a: float in [-2.0, 0.0, 3.0, 6.0, 9.0]:
		for b: float in [-5.0, -3.0, -1.8, 1.8, 3.0, 5.0]:
			var w: Vector3 = _player.global_position + fwd * a + side * b
			probes.append(Vector2(w.x, w.z))
	var first: Array[float] = []
	var worst: Array[float] = []
	for q: Vector2 in probes:
		first.append(shell.field._sample(q.x, q.y).x)
		worst.append(0.0)
	var rebuilds: int = 0
	var was_origin: Vector2 = shell.field.origin
	Input.action_press(&"move_forward", 1.0)
	var min_rim: float = INF
	var outside_frames: int = 0
	var frames: int = 0
	var start: Vector3 = _player.global_position
	var elapsed: float = 0.0
	var worst_rebuild_frames: int = 0
	var rebuild_run: int = 0
	while elapsed < seconds:
		await process_frame
		elapsed += _player.get_process_delta_time()
		frames += 1
		var p: Vector3 = _player.global_position
		var local: Vector2 = Vector2(p.x, p.z) - shell.field.origin
		var w: float = shell.window_m
		var rim: float = minf(minf(local.x, local.y), minf(w - local.x, w - local.y))
		min_rim = minf(min_rim, rim)
		outside_frames += 1 if rim < 0.0 else 0
		rebuild_run = rebuild_run + 1 if shell.field.is_rebuilding() else 0
		if shell.field.origin != was_origin:
			was_origin = shell.field.origin
			rebuilds += 1
		for k: int in range(probes.size()):
			var top: float = shell.field._sample(probes[k].x, probes[k].y).x
			if top > -1.0e9 and first[k] > -1.0e9:
				worst[k] = maxf(worst[k], absf(top - first[k]))
		worst_rebuild_frames = maxi(worst_rebuild_frames, rebuild_run)
	_release()
	var walked: float = Vector2(_player.global_position.x - start.x, _player.global_position.z - start.z).length()
	worst.sort()
	print("SNOW_FIXED_POINTS window_moves=%d max_top_change_cm=%.2f median_cm=%.2f" % [rebuilds, worst[-1] * 100.0, worst[worst.size() / 2] * 100.0])
	print("SNOW_LAG frames=%d walked_m=%.1f min_rim_m=%.2f outside_frames=%d longest_rebuild_frames=%d plants=%d plants_per_m=%.2f" % [
		frames, walked, min_rim, outside_frames, worst_rebuild_frames, plants[0], plants[0] / maxf(walked, 0.1)])
	quit(0)
