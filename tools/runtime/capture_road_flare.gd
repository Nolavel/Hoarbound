extends SceneTree

## The Emberline flare in the game renderer, framed like its reference sheet: a lit product view
## of both labels, the flare lying in snow, and a lit flare at night with its flame and smoke.
## Run: xvfb-run godot --path . --rendering-driver vulkan --fixed-fps 30 --resolution 1600x900 --script res://tools/runtime/capture_road_flare.gd -- <out dir>

const MODEL: String = "res://assets/items/road_flare/RoadFlare.glb"
const HELD: String = "res://scenes/actors/player/held/HeldFlare.tscn"

var _out: String = "user://shots/road_flare"
var _env: Environment
var _sun: DirectionalLight3D
var _camera: Camera3D


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_run()


func _run() -> void:
	var world_env := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.09, 0.09, 0.1)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.55, 0.57, 0.62)
	_env.ambient_light_energy = 0.5
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_env.environment = _env
	root.add_child(world_env)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-40.0, 30.0, 0.0)
	_sun.light_energy = 1.3
	_sun.shadow_enabled = true
	root.add_child(_sun)
	_camera = Camera3D.new()
	_camera.fov = 30.0
	root.add_child(_camera)
	_camera.make_current()
	## Product view: front label above, warning label below, lying like the reference's side view.
	var front: Node3D = (load(MODEL) as PackedScene).instantiate()
	front.rotation = Vector3(0.0, 0.0, PI * 0.5)
	front.position = Vector3(0.0, 0.035, 0.0)
	root.add_child(front)
	var back: Node3D = (load(MODEL) as PackedScene).instantiate()
	back.rotation = Vector3(PI, 0.0, -PI * 0.5)
	back.position = Vector3(0.0, -0.035, 0.0)
	root.add_child(back)
	_camera.look_at_from_position(Vector3(0.0, 0.0, 0.62), Vector3.ZERO)
	await _frames(10)
	_save("1_product")
	_camera.look_at_from_position(Vector3(0.24, 0.12, 0.22), Vector3(0.02, 0.0, 0.0))
	await _frames(4)
	_save("2_three_quarter")
	front.queue_free()
	back.queue_free()
	## In snow, as a pickup lies.
	var snow := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(4.0, 4.0)
	snow.mesh = plane
	var snow_look := StandardMaterial3D.new()
	snow_look.albedo_color = Color(0.86, 0.88, 0.93)
	snow_look.roughness = 0.9
	snow.material_override = snow_look
	root.add_child(snow)
	var lying: Node3D = (load(MODEL) as PackedScene).instantiate()
	lying.rotation = Vector3(0.0, 0.5, PI * 0.5)
	lying.position = Vector3(0.0, 0.0196, 0.0)
	root.add_child(lying)
	_env.background_color = Color(0.32, 0.36, 0.48)
	_camera.fov = 40.0
	_camera.look_at_from_position(Vector3(0.18, 0.26, 0.42), Vector3(0.0, 0.02, 0.0))
	await _frames(6)
	_save("3_in_snow")
	lying.queue_free()
	## Night: the held flare burning upright, planted in the snow.
	_sun.light_energy = 0.05
	_env.ambient_light_energy = 0.08
	_env.background_color = Color(0.04, 0.05, 0.09)
	var flare: Node3D = (load(HELD) as PackedScene).instantiate()
	flare.position = Vector3(0.0, 0.1, 0.0)
	root.add_child(flare)
	_camera.fov = 45.0
	_camera.look_at_from_position(Vector3(0.55, 0.45, 0.85), Vector3(0.0, 0.25, 0.0))
	await _frames(90)
	_save("4_burning_night")
	print("ROAD_FLARE_CAPTURE: done")
	quit(0)


func _save(label: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(_out.path_join(label + ".png")))


func _frames(count: int) -> void:
	for _i: int in range(count):
		await process_frame
