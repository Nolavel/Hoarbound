extends SceneTree

## Stills of the isolated 727 FrontWindow1 thaw probe at fixed thaw steps, one PNG each.
## Run: xvfb-run godot --path . --rendering-driver vulkan --resolution 1600x900 --script res://tools/runtime/capture_window_727_thaw.gd -- <out dir> [variant]

const PROBE: String = "res://tests/scenes/window_727_sdf_probe.tscn"
const STEPS: Array[float] = [0.0, 0.12, 0.25, 0.4, 0.55, 0.7, 0.85, 1.0]

var _out: String = "user://shots/window_727_thaw"
var _variant: String = ""


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	if args.size() > 1:
		_variant = args[1]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	call_deferred(&"_run")


func _run() -> void:
	var probe := (load(PROBE) as PackedScene).instantiate() as Window727SDFProbe
	root.add_child(probe)
	for _i: int in 6:
		await process_frame
	if not probe.is_valid():
		push_error("capture window thaw: the probe did not load the pane")
		quit(1)
		return
	if _variant != "":
		probe.set_variant(StringName(_variant))
	for step: float in STEPS:
		probe.set_thaw(step)
		for _i: int in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		var path: String = "%s/thaw_%03d.png" % [_out, int(round(step * 100.0))]
		image.save_png(ProjectSettings.globalize_path(path) if path.begins_with("user://") else path)
		print("capture window thaw: %s" % path)
	quit(0)
