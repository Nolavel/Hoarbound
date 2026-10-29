extends SceneTree

## Backpack inspector (#260): loads the pack with Henry's starting contents and checks it in numbers
## and in pictures. Report: each item's box, how far a pocket item reaches into the main cavity,
## main items poking out past the canvas give, items overlapping, the handle off the top. Pictures:
## front, side, top (orthographic) and a three-quarter view, each with the canvas see-through and
## the cavity (green), pockets (cyan) and item boxes (yellow, red when wrong) drawn as wire boxes;
## and the same four with the real canvas. Run:
## xvfb-run godot --path . --rendering-driver vulkan --script res://tools/runtime/inspect_backpack.gd -- <out dir>

## Canvas wall and lining between the cavity and the outside, and how far the canvas may give.
const WALL_M: float = 0.012
const GIVE_M: float = 0.02

var _out: String = "user://shots/backpack_inspect"
var _pack: BackpackModel
var _lines: MeshInstance3D
var _report: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_run()


func _run() -> void:
	await process_frame
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.14, 0.14, 0.15)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.62, 0.66)
	env.environment.ambient_light_energy = 0.6
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	sun.light_energy = 1.3
	root.add_child(sun)
	_pack = BackpackModel.new()
	root.add_child(_pack)
	_pack.add_loose(&"spov_can")
	_pack.add_loose(&"tinned_stew")
	_pack.add_item(&"water_flask", &"side_left")
	_pack.hang_item(&"mug", 1)
	for _i: int in range(90):
		await process_frame
	_check()
	_lines = MeshInstance3D.new()
	_lines.mesh = _wire_boxes()
	var line_material := StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.vertex_color_use_as_albedo = true
	line_material.no_depth_test = true
	_lines.material_override = line_material
	root.add_child(_lines)
	var file := FileAccess.open(ProjectSettings.globalize_path(_out).path_join("report.txt"), FileAccess.WRITE)
	file.store_string("\n".join(_report))
	file.close()
	for line: String in _report:
		print("[inspect] ", line)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.make_current()
	var centre := Vector3(0.0, BackpackModel.BODY.y * 0.45, BackpackModel.BODY.z * 0.5)
	var views: Array = [
		["front", centre + Vector3(0.0, 0.0, 1.5), true],
		["side", centre + Vector3(-1.5, 0.0, 0.0), true],
		["top", centre + Vector3(0.0, 1.5, 0.001), true],
		["three_quarter", centre + Vector3(0.75, 0.55, 0.9), false],
	]
	var shot: int = 0
	for see_through: bool in [true, false]:
		_set_see_through(see_through)
		_lines.visible = see_through
		for view: Array in views:
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL if view[2] else Camera3D.PROJECTION_PERSPECTIVE
			camera.size = 0.75
			camera.fov = 40.0
			camera.look_at_from_position(view[1], centre, Vector3.UP if view[0] != "top" else Vector3.BACK)
			for _i: int in range(4):
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out).path_join("%02d_%s_%s.png" % [shot, view[0], "xray" if see_through else "canvas"]))
			shot += 1
	quit(0)


## Numbers: item boxes, pocket items in the cavity, main items poking out, overlaps, handle gap.
func _check() -> void:
	var cavity: AABB = _cavity()
	var items: Array = _pack.get(&"_items")
	_report.append("cavity %s" % _cm(cavity))
	var faults: int = 0
	for i: int in range(items.size()):
		var item: Dictionary = items[i]
		var box: AABB = item["box"]
		var slot := String(item["slot"])
		_report.append("%s in %s: %s" % [item["id"], slot if slot != "" else "main (loose)", _cm(box)])
		if slot.begins_with("side_"):
			var inside: AABB = box.intersection(cavity)
			if inside.has_volume():
				faults += 1
				_report.append("  FAULT reaches %.1f cm into the main cavity" % (inside.size.x * 100.0))
		else:
			var out: Vector3 = (box.end - cavity.end).max(cavity.position - box.position)
			var worst: float = maxf(out.x, maxf(out.y, out.z))
			if worst > GIVE_M:
				faults += 1
				_report.append("  FAULT pokes %.1f cm past the canvas (gives %.1f cm)" % [worst * 100.0, GIVE_M * 100.0])
		for j: int in range(i + 1, items.size()):
			var other: AABB = items[j]["box"]
			if box.intersects(other) and box.intersection(other).get_volume() > 0.000001:
				faults += 1
				_report.append("  FAULT overlaps %s by %s" % [items[j]["id"], _cm(box.intersection(other))])
	var handle: Node3D = _pack.get(&"_handle")
	var top: Vector3 = _pack.canvas_point(BackpackModel.HANDLE_AT, Vector3.UP)
	var gap: float = handle.position.distance_to(top)
	_report.append("handle foot %.1f cm off the canvas top" % (gap * 100.0))
	if gap > 0.005:
		faults += 1
	_report.append("fill %.2f  faults %d" % [_pack.get_fill_target(), faults])


func _cavity() -> AABB:
	var body: Vector3 = BackpackModel.BODY
	return AABB(Vector3(-body.x * 0.5 + WALL_M, WALL_M, WALL_M), Vector3(body.x - WALL_M * 2.0, body.y - WALL_M * 2.0, body.z - WALL_M * 2.0))


func _wire_boxes() -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_box_lines(mesh, _cavity(), Color(0.3, 1.0, 0.4))
	for side: float in [-1.0, 1.0]:
		var half: Vector3 = BackpackModel.POCKET_HALF
		var at := Vector3(side * BackpackModel.POCKET_X, half.y + 0.03, BackpackModel.BODY.z * 0.5)
		_box_lines(mesh, AABB(at - half, half * 2.0), Color(0.3, 0.9, 1.0))
	var cavity: AABB = _cavity()
	for item: Dictionary in _pack.get(&"_items"):
		var box: AABB = item["box"]
		var wrong: bool = String(item["slot"]).begins_with("side_") and box.intersection(cavity).has_volume()
		_box_lines(mesh, box, Color(1.0, 0.2, 0.2) if wrong else Color(1.0, 0.9, 0.2))
	mesh.surface_end()
	return mesh


func _box_lines(mesh: ImmediateMesh, box: AABB, colour: Color) -> void:
	for e: int in range(12):
		var edge: Array = _edge(e)
		mesh.surface_set_color(colour)
		mesh.surface_add_vertex(box.position + box.size * (edge[0] as Vector3))
		mesh.surface_set_color(colour)
		mesh.surface_add_vertex(box.position + box.size * (edge[1] as Vector3))


static func _edge(e: int) -> Array:
	var corners: Array[Vector3] = [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0),
		Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1)]
	var pairs: Array = [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4], [0, 4], [1, 5], [2, 6], [3, 7]]
	return [corners[pairs[e][0]], corners[pairs[e][1]]]


## See-through: the canvas parts draw as a faint transparent shell so the boxes inside show.
func _set_see_through(on: bool) -> void:
	for mesh: Node in _pack.find_children("*", "MeshInstance3D", true, false):
		var part := mesh as MeshInstance3D
		if not part.has_meta(&"inspect_material"):
			part.set_meta(&"inspect_material", part.material_override)
		if on and part.material_override is ShaderMaterial:
			var ghost := StandardMaterial3D.new()
			ghost.albedo_color = Color(0.5, 0.55, 0.6, 0.18)
			ghost.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			ghost.cull_mode = BaseMaterial3D.CULL_DISABLED
			part.material_override = ghost
		else:
			part.material_override = part.get_meta(&"inspect_material")


func _cm(box: AABB) -> String:
	return "x %.1f..%.1f  y %.1f..%.1f  z %.1f..%.1f cm" % [box.position.x * 100.0, box.end.x * 100.0,
		box.position.y * 100.0, box.end.y * 100.0, box.position.z * 100.0, box.end.z * 100.0]
