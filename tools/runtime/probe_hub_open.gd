extends SceneTree

## Hub (TAB) open cost in the 727 yard on a real GPU: per open, pipeline compiles by kind and the worst frame.
## Run: godot --path . --resolution 1280x720 --script res://tools/runtime/probe_hub_open.gd -- [opens] [nofrost|nolight]
## nofrost: Henry's rime at 0 (no overlays); nolight: the Hub key light off. One factor per run.

const SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"
const MONITORS: Dictionary = {
	"surface": Performance.PIPELINE_COMPILATIONS_SURFACE,
	"draw": Performance.PIPELINE_COMPILATIONS_DRAW,
	"spec": Performance.PIPELINE_COMPILATIONS_SPECIALIZATION,
	"mesh": Performance.PIPELINE_COMPILATIONS_MESH,
	"canvas": Performance.PIPELINE_COMPILATIONS_CANVAS,
}
const OPEN_FRAMES: int = 30
const CLOSED_FRAMES: int = 20

var _opens: int = 6
var _mode: String = ""


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for arg: String in args:
		if arg.is_valid_int():
			_opens = arg.to_int()
		else:
			_mode = arg
	_run()


func _run() -> void:
	var world := (load(SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(world)
	var ctx: Variant = null
	for _i: int in range(900):
		await process_frame
		ctx = world.call(&"get_context")
		if ctx != null:
			break
	if ctx == null:
		push_error("[hubprobe] the world never gave its context")
		quit(1)
		return
	print("[hubprobe] world ready")
	var player := ctx.player as Player
	var hub := player.get_node(^"PlayerHubComponent") as PlayerHubComponent
	if _mode == "nofrost":
		(player.get_node(^"ClothingFrostComponent") as ClothingFrostComponent).initial_frost = 0.0
		(player.get_node(^"ClothingFrostComponent") as ClothingFrostComponent).set_frost(0.0)
	## Held by the probe for the whole run, so they outlive each Hub visit.
	var kept: Array[Resource] = []
	if _mode == "keepblur":
		kept.append(load("res://shaders/items/pack_focus_blur.gdshader"))
	if _mode == "keepmask":
		kept.append(PackFocusBlur._mask(null))
	if _mode == "noblur":
		hub.hub_opened.connect(func() -> void:
			for blur: Node in player.find_children("PackFocusBlur", "", true, false):
				blur.free())
	if _mode == "maskonly":
		hub.hub_opened.connect(func() -> void:
			for blur: Node in player.find_children("PackFocusBlur", "", true, false):
				(blur as Node3D).visible = false)
	if _mode == "quadonly":
		hub.hub_opened.connect(func() -> void:
			for blur: Node in player.find_children("PackFocusBlur", "", true, false):
				blur.set_process(false)
				if blur.get_tree().node_added.is_connected(Callable(blur, &"_on_node_added")):
					blur.get_tree().node_added.disconnect(Callable(blur, &"_on_node_added"))
			for node: Node in root.find_children("*", "GeometryInstance3D", true, false):
				var geo := node as GeometryInstance3D
				if geo.material_overlay != null and geo.material_overlay.has_meta(&"focus_mask"):
					geo.material_overlay = geo.material_overlay.next_pass)
	if _mode == "nolight":
		hub.character_light = null
		for light: Node in player.find_children("HubCharacterLight", "", true, false):
			(light as Node3D).visible = false
			light.set_process(false)
	await create_timer(15.0).timeout
	print("[hubprobe] mode=%s renderer=%s gpu=%s" % [_mode if _mode != "" else "baseline",
		RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_video_adapter_name()])
	var settle: Dictionary = await _measure(CLOSED_FRAMES)
	print("[hubprobe] closed settle  ", _row(settle))
	var seen: Dictionary = _shaders_in_tree()
	for i: int in range(_opens):
		var shaders_before: Dictionary = seen
		var opened: bool = hub.open()
		var open_cost: Dictionary = await _measure(OPEN_FRAMES)
		print("[hubprobe] open %d (%s) %s" % [i + 1, "ok" if opened else "REFUSED", _row(open_cost)])
		var shaders_now: Dictionary = _shaders_in_tree()
		for id: int in shaders_now:
			if not shaders_before.has(id):
				print("[hubprobe]   shader never drawn before: ", shaders_now[id])
				seen[id] = shaders_now[id]
		var standard: Dictionary = {}
		for node: Node in root.find_children("*", "GeometryInstance3D", true, false):
			var geo := node as GeometryInstance3D
			var material: Material = geo.material_overlay
			while material != null:
				if material is BaseMaterial3D:
					standard[material.get_instance_id()] = true
				material = material.next_pass
		print("[hubprobe]   BaseMaterial3D overlays live: ", standard.size())
		hub.close()
		var close_cost: Dictionary = await _measure(CLOSED_FRAMES)
		print("[hubprobe] close %d      %s" % [i + 1, _row(close_cost)])
	quit(0)


func _frames(count: int) -> void:
	for _i: int in range(count):
		await process_frame


## Compiles by kind over `count` frames, the worst and median frame, and the frame index of the worst.
func _measure(count: int) -> Dictionary:
	var before: Dictionary = _compiles()
	var times: Array[float] = []
	var last: int = Time.get_ticks_usec()
	for _i: int in range(count):
		await process_frame
		var now: int = Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
	var after: Dictionary = _compiles()
	var result: Dictionary = {}
	for key: String in MONITORS:
		result[key] = int(after[key] - before[key])
	var worst: float = times.max()
	result["worst_ms"] = worst
	result["worst_at"] = times.find(worst)
	var sorted: Array[float] = times.duplicate()
	sorted.sort()
	result["median_ms"] = sorted[sorted.size() / 2]
	result["draw_calls"] = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	return result


## Every Shader drawn in the tree now, by instance id: its path (or "built" plus its owner node).
func _shaders_in_tree() -> Dictionary:
	var out: Dictionary = {}
	for node: Node in root.find_children("*", "", true, false):
		var materials: Array[Material] = []
		var geo := node as GeometryInstance3D
		if geo != null:
			materials.append_array([geo.material_override, geo.material_overlay])
			var mesh_inst := geo as MeshInstance3D
			if mesh_inst != null and mesh_inst.mesh != null:
				for surface: int in mesh_inst.mesh.get_surface_count():
					materials.append(mesh_inst.get_active_material(surface))
		var item := node as CanvasItem
		if item != null:
			materials.append(item.material)
		for material: Material in materials:
			while material != null:
				var shader: Shader = (material as ShaderMaterial).shader if material is ShaderMaterial else null
				if shader != null and not out.has(shader.get_rid().get_id()):
					out[shader.get_rid().get_id()] = "rid %d %s  (on %s)" % [shader.get_rid().get_id(), shader.resource_path, node.get_path()]
				material = material.next_pass
	return out


func _compiles() -> Dictionary:
	var out: Dictionary = {}
	for key: String in MONITORS:
		out[key] = Performance.get_monitor(MONITORS[key])
	return out


func _row(r: Dictionary) -> String:
	return "compiles surface=%d draw=%d spec=%d mesh=%d canvas=%d | worst %.1f ms @%d | median %.1f ms | draws %d" % [
		r["surface"], r["draw"], r["spec"], r["mesh"], r["canvas"], r["worst_ms"], r["worst_at"], r["median_ms"], r["draw_calls"]]
