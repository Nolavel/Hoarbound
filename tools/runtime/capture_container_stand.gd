extends SceneTree

## The held pack at an open cabinet on a bare stand (fast to frame, unlike Key West): a cabinet built like the
## 727 one ahead of Henry with tins and a stew; Tab, then a still of the view. For tuning the container view.
## Run: xvfb-run godot --path . --rendering-driver vulkan --resolution 1920x1080 --script res://tools/runtime/capture_container_stand.gd -- <out png> [plain|left|right]

const PLAYER: String = "res://scenes/actors/player/player.tscn"
const PANELS: Array = [
	[Vector3(0.8, 0.9, 0.03), Vector3(0.0, 0.45, -0.21)],
	[Vector3(0.03, 0.9, 0.45), Vector3(-0.385, 0.45, 0.0)],
	[Vector3(0.03, 0.9, 0.45), Vector3(0.385, 0.45, 0.0)],
	[Vector3(0.8, 0.03, 0.45), Vector3(0.0, 0.885, 0.0)],
	[Vector3(0.8, 0.06, 0.45), Vector3(0.0, 0.03, 0.0)],
	[Vector3(0.74, 0.02, 0.4), Vector3(0.0, 0.45, 0.0)],
]

var _out: String = "user://container_stand.png"
## "plain" as the second argument: no cabinet (the ordinary Tab view); "left" / "right": Henry starts off to
## that side of the cabinet's front (as one looks in), so he visits that side.
var _plain: bool = false
var _start_side: float = 0.0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	_plain = args.size() > 1 and args[1] == "plain"
	if args.size() > 1 and args[1] in ["left", "right"]:
		_start_side = -1.0 if args[1] == "left" else 1.0
	_run()


func _run() -> void:
	TranslationServer.set_locale("ru")
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	floor.add_child(shape)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20.0, 20.0)
	ground.mesh = plane
	floor.add_child(ground)
	root.add_child(floor)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	root.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.72, 0.75, 0.8)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.72, 0.78)
	root.add_child(env)
	var player := (load(PLAYER) as PackedScene).instantiate() as Player
	root.add_child(player)
	player.global_position = Vector3(0.0, 1.0, 0.0)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.make_current()
	for _i: int in 40:
		await process_frame
	var forward: Vector3 = -player.global_basis.z.slide(Vector3.UP).normalized()
	if _plain:
		forward = Vector3.DOWN * 100.0  # the cabinet goes far below, out of reach and sight
	var cabinet := Node3D.new()
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.36, 0.38, 0.42)
	for panel: Array in PANELS:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = panel[0]
		mesh.mesh = box
		mesh.position = panel[1]
		mesh.material_override = paint
		cabinet.add_child(mesh)
	root.add_child(cabinet)
	cabinet.global_position = player.global_position * Vector3(1, 0, 1) + forward * 0.75
	cabinet.look_at(cabinet.global_position - forward, Vector3.UP, true)
	var box_node := ItemContainer.new()
	box_node.container_id = &"stand_cabinet"
	box_node.shelves = ItemContainer.shelves_from_furniture(cabinet, null)
	cabinet.add_child(box_node)
	for id: StringName in [&"tinned_stew", &"tinned_pineapple", &"spov_can", &"spov_can", &"work_gloves"]:
		box_node.put(id)
	if _start_side != 0.0:
		## Seen from the cabinet's front looking in, its right is the player's left.
		player.global_position += player.global_basis.x * -_start_side * 0.7
	for _i: int in 5:
		await physics_frame
	var hub := player.get_node(^"PlayerHubComponent") as PlayerHubComponent
	hub.open()
	for _i: int in 240:
		await process_frame
		if hub.is_open():
			break
	for _i: int in 60:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out))
	print("[container stand] saved ", _out, " container ", hub.container != null)
	if hub.container != null:
		var view_camera: Camera3D = root.get_viewport().get_camera_3d()
		var hold: PackFrontHold = hub.get("_front_hold")
		var pack_points: Array[Vector3] = []
		for corner: Vector3 in hold.call(&"_container_pack_corners"):
			pack_points.append(hold.held_transform() * corner)
		var body_points: Array[Vector3] = []
		for i: int in 8:
			body_points.append(hub.container.global_transform * hub.container.body_box().get_endpoint(i))
		print("[container stand] screen share: pack ", _share(view_camera, pack_points), " furniture ", _share(view_camera, body_points))
		var face: Array = hub.container.front()
		var to_front: Transform3D = Transform3D(Basis(face[2], Vector3.UP, face[1]), face[0]).affine_inverse()
		print("[container stand] side ", hold.container_side, " camera ", var_to_str(to_front * view_camera.global_transform), " pack ", var_to_str(to_front * hold.held_transform()), " henry ", var_to_str(to_front * player.global_transform))
	quit()


## The share of the frame's width and height that `points` cover on screen, and their x span in pixels.
func _share(camera: Camera3D, points: Array[Vector3]) -> String:
	var box := Rect2(camera.unproject_position(points[0]), Vector2.ZERO)
	for point: Vector3 in points:
		box = box.expand(camera.unproject_position(point))
	var size: Vector2 = root.get_viewport().get_visible_rect().size
	return "%.0f%% wide, %.0f%% high (x %.0f..%.0f)" % [box.size.x / size.x * 100.0, box.size.y / size.y * 100.0, box.position.x, box.end.x]
