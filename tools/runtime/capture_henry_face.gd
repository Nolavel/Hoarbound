extends SceneTree

## Henry's face, three-quarter front (FACE_YAW env turns the camera; 303 default), warm (no cold), at rime 0.4 and at 0.85: the cold flush on the cheeks and nose
## and the breath rime on the brows.
## Run: xvfb-run godot --path . --rendering-driver vulkan --resolution 960x540 --script res://tools/runtime/capture_henry_face.gd -- <out dir>

const PLAYER: String = "res://scenes/actors/player/player.tscn"
const LEVELS: Array[float] = [0.0, 0.4, 0.85]

var _out: String = "user://shots/henry_face"


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_run.call_deferred()


func _run() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	root.add_child(floor_body)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.5, 0.55, 0.62)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.63, 0.7)
	root.add_child(env)
	var player := (load(PLAYER) as PackedScene).instantiate() as Player
	root.add_child(player)
	player.global_position = Vector3(0.0, 1.0, 0.0)
	var frost := player.get_node(^"ClothingFrostComponent") as ClothingFrostComponent
	frost.set_process(false)
	var camera := Camera3D.new()
	camera.fov = 30.0
	root.add_child(camera)
	camera.make_current()
	for _i: int in range(60):
		await process_frame
	var visual: HenryUALAnimation = player.animation_component
	## The head look turns Henry toward where the camera looks, away from a camera set in front of him: off.
	visual._head_lookat.active = false
	visual._head_lookat.influence = 0.0
	for _i: int in range(10):
		await process_frame
	var bone: int = visual.skeleton.find_bone(visual.head_bone)
	await visual.skeleton.skeleton_updated
	var head: Transform3D = visual.skeleton.global_transform * visual.skeleton.get_bone_global_pose(bone)
	var face: Vector3 = head * Vector3(0.0, 0.12, 0.05)
	var forward: Vector3 = visual.get_head_facing()
	forward = Vector3(forward.x, 0.0, forward.z).normalized().rotated(Vector3.UP, deg_to_rad(float(OS.get_environment("FACE_YAW")) if OS.has_environment("FACE_YAW") else 303.0))
	var sun := DirectionalLight3D.new()
	root.add_child(sun)
	sun.look_at_from_position(face + forward * 2.0 + Vector3(0.8, 1.4, 0.0), face, Vector3.UP)
	sun.light_energy = 0.9
	camera.look_at_from_position(face + forward * 0.95 + Vector3.UP * 0.02, face, Vector3.UP)
	for level: float in LEVELS:
		frost.set_frost(level)
		for _i: int in range(4):
			await process_frame
		await RenderingServer.frame_post_draw
		var label: String = "face_%02d" % int(level * 100.0)
		root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(_out.path_join(label + ".png")))
		print("HENRY_FACE ", label)
	quit(0)
