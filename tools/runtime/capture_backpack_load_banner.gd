extends SceneTree

## Isolated renderer fixture on the real Henry + BackpackModel; no snow/world streaming.
## Saves three 1280x720 reference angles of the load gauge (not a mockup).
## Run under xvfb-run with --rendering-driver opengl3 --rendering-method gl_compatibility.
const PLAYER: PackedScene = preload("res://scenes/actors/player/player.tscn")
const BANNER: PackedScene = preload("res://scenes/ui/hud/backpack_load_banner.tscn")
var _out: String = "user://shots/backpack_load"
var _camera: Camera3D
var _player: Player
var _banner: BackpackLoadBanner


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_run.call_deferred()


func _run() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.10, 0.13, 0.16)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.72, 0.78, 0.83)
	env.environment.ambient_light_energy = 0.8
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, -30.0, 0.0)
	sun.light_energy = 1.4
	root.add_child(sun)
	var floor := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = WorldBoundaryShape3D.new()
	floor.add_child(collision)
	root.add_child(floor)
	_player = PLAYER.instantiate() as Player
	root.add_child(_player)
	_player.global_position = Vector3(0.0, 1.0, 0.0)
	await _frames(45)
	_banner = BANNER.instantiate() as BackpackLoadBanner
	root.add_child(_banner)
	_banner.bind_player(_player, null)
	_camera = Camera3D.new()
	_camera.fov = 40.0
	root.add_child(_camera)
	_camera.make_current()
	var rig: PackRig = _player.animation_component.get_pack_rig()
	var canvas: BackpackModel = rig.get_canvas()
	var centre: Vector3 = BackpackLoadBanner.panel_transform(canvas).origin
	var outward: Vector3 = canvas.global_basis.z.normalized()
	var right: Vector3 = canvas.global_basis.x.normalized()
	if not rig.is_visible_in_tree():
		push_error("BACKPACK_LOAD_CAPTURE: worn pack is not visible")
		quit(1)
		return
	await _shot("01_rear", centre + outward * 1.25 + Vector3.UP * 0.04, centre)
	await _shot("02_three_quarter", centre + outward * 1.30 + right * 0.35 + Vector3.UP * 0.12, centre)
	await _shot("03_far", centre + outward * 1.8 + Vector3.UP * 0.15, centre)
	print("BACKPACK_LOAD_CAPTURE: PASS")
	quit(0)


func _shot(filename: String, eye: Vector3, focus: Vector3) -> void:
	_camera.look_at_from_position(eye, focus)
	_banner.set("_visible_left", 4.2)
	await _frames(12)
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(_out).path_join(filename + ".png"))


func _frames(count: int) -> void:
	for _i in range(count):
		await process_frame
