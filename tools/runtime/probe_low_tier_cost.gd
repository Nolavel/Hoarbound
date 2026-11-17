extends "res://tools/runtime/capture_snow_walk.gd"
## LOW tier frame cost on Duval Street with one feature off at a time: as is, no volumetric fog, no sun shadows.
## Relative only (lavapipe is a CPU rasteriser). Args: <out_dir> 1.0 low; Vulkan, uncapped frames.

const SAMPLE_FRAMES: int = 90


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
	_place()
	await _wait_streamed()
	if _camera.has_method(&"set_look"):
		_camera.call(&"set_look", _yaw, -10.0)
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await _wait_frames(120)
	var env: Environment = (_world.find_child("WorldEnvironment", true, false) as WorldEnvironment).environment
	var sun := _world.find_child("SunLight", true, false) as DirectionalLight3D
	var rows: Array[String] = []
	rows.append(await _measure("low_as_is"))
	env.volumetric_fog_enabled = false
	rows.append(await _measure("no_volumetric_fog"))
	env.volumetric_fog_enabled = true
	sun.shadow_enabled = false
	rows.append(await _measure("no_sun_shadows"))
	sun.shadow_enabled = true
	rows.append(await _primitives_by_group())
	print("LOW_TIER_COST scale=%.2f %s" % [root.scaling_3d_scale, " | ".join(rows)])
	quit(0)


func _measure(label: String) -> String:
	await _wait_frames(30)
	var t0: int = Time.get_ticks_usec()
	await _wait_frames(SAMPLE_FRAMES)
	var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0 / SAMPLE_FRAMES
	return "%s=%.1fms" % [label, ms]


## Triangles drawn per frame, and how many each top-level group of the world takes when hidden.
func _primitives_by_group() -> String:
	await _wait_frames(5)
	var total: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var calls: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var parts: Array[String] = ["primitives=%d draw_calls=%d" % [total, calls]]
	var groups: Array[Node3D] = []
	for top: Node in _world.get_children():
		if top is Node3D:
			groups.append(top as Node3D)
	var stream := _world.find_child("StreamContainer", true, false)
	if stream != null:
		for chunk: Node in stream.get_children():
			for part: Node in chunk.get_children():
				if part is Node3D:
					groups.append(part as Node3D)
	var by_name: Dictionary = {}
	for g: Node3D in groups:
		if not g.visible:
			continue
		g.visible = false
		await _wait_frames(3)
		var without: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		g.visible = true
		var key: String = String(g.name) if g.get_parent() != stream and (g.get_parent() == null or g.get_parent().get_parent() != stream) else "chunk/" + String(g.name)
		by_name[key] = int(by_name.get(key, 0)) + (total - without)
	var keys: Array = by_name.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return by_name[a] > by_name[b])
	for k: String in keys.slice(0, 10):
		parts.append("%s=%d" % [k, by_name[k]])
	return " ".join(parts)
