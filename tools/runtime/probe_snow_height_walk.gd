extends "res://tools/runtime/capture_snow_walk.gd"
## Fixed top-down camera, snow drawn as height colour (debug_height); Henry walks straight. Any change in the
## height colour away from his trail is snow moving under a still camera. Args: <out_dir> 1.0 <quality>.


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
	var mats: Array[ShaderMaterial] = []
	for mi: Node in _world.find_children("*", "GeometryInstance3D", true, false):
		var cands: Array = [(mi as GeometryInstance3D).material_override]
		var mesh_inst := mi as MeshInstance3D
		if mesh_inst != null and mesh_inst.mesh != null:
			for k: int in range(mesh_inst.mesh.get_surface_count()):
				cands.append(mesh_inst.get_active_material(k))
		for c: Variant in cands:
			var m := c as ShaderMaterial
			if m != null and m.shader != null and m.shader.code.contains("debug_height") and not mats.has(m):
				mats.append(m)
	if shell._surface != null and not mats.has(shell._surface):
		mats.append(shell._surface)
	for m: ShaderMaterial in mats:
		m.set_shader_parameter(&"debug_height", true)
	var start: Vector3 = _player.global_position
	var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 24.0
	root.add_child(cam)
	cam.global_transform = Transform3D(Basis.looking_at(Vector3.DOWN, fwd), start + fwd * 6.0 + Vector3.UP * 30.0)
	cam.make_current()
	if _camera.has_method(&"set_look"):
		_camera.call(&"set_look", _yaw, -16.0)
	Input.action_press(&"move_forward", 1.0)
	for i: int in range(240):
		await process_frame
		if i % 8 == 0:
			await RenderingServer.frame_post_draw
			_save(root.get_texture().get_image(), "h_%03d.png" % (i / 8))
	_release()
	print("SNOW_HEIGHT_WALK materials=%d walked=%.1f" % [mats.size(), start.distance_to(_player.global_position)])
	quit(0)
