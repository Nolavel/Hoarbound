extends SceneTree

## Two stills of the shelter stove for before/after checks of its scene: cold with three logs
## and tinder laid, then burning with the door open. No Henry, no world: just the shelter.
## Run: xvfb-run godot --path . --rendering-driver vulkan --fixed-fps 30 --resolution 1280x720 --script res://tools/runtime/capture_stove_still.gd -- <out dir>

const BLOCKOUT: String = "res://scenes/world/first_exit/first_exit_blockout.tscn"
const STOVE: String = "ShelterHouse/House/ShelterZone/Stove"

var _out: String = "user://shots/stove_still"


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_run()


func _run() -> void:
	var shelter := (load(BLOCKOUT) as PackedScene).instantiate() as Node3D
	root.add_child(shelter)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.2, 0.22, 0.25)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.45, 0.47, 0.5)
	root.add_child(env)
	var stove := shelter.get_node(STOVE) as HeatSource
	var visual := stove.get_node(^"StoveVisual") as StoveVisual
	var camera := Camera3D.new()
	camera.fov = 50.0
	root.add_child(camera)
	var front: Vector3 = visual.to_global(Vector3(1.3, 0.75, 0.5))
	camera.look_at_from_position(front, visual.to_global(Vector3(0.0, 0.4, 0.0)))
	camera.make_current()
	stove.add_logs(3)
	stove.set_tinder_prepared(true)
	visual.set_door_open(true)
	await _frames(20)
	_save("1_cold_laid")
	stove.start_loaded_fire()
	for _i: int in range(240):
		await process_frame
	_save("2_burning_open")
	print("STOVE_STILL: done logs=%d glowing=%s" % [visual.get_visible_log_count(), visual.is_glowing()])
	quit(0)


func _save(label: String) -> void:
	var path: String = ProjectSettings.globalize_path(_out.path_join(label + ".png"))
	root.get_viewport().get_texture().get_image().save_png(path)


func _frames(count: int) -> void:
	for _i: int in range(count):
		await process_frame
