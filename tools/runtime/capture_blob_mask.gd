extends SceneTree

## Real Godot canvas capture. PNGs are taken after RenderingServer.frame_post_draw.

const SCENE: PackedScene = preload("res://tests/scenes/blob_mask_demo.tscn")
const FPS: int = 30
const FRAME_COUNT: int = 180
const OUTPUT_ROOT: String = "res://docs/runtime_previews/blob_mask"

var _demo: BlobMaskDemo


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var frame_directory: String = ProjectSettings.globalize_path(OUTPUT_ROOT.path_join("frames"))
	var result: Error = DirAccess.make_dir_recursive_absolute(frame_directory)
	if result != OK:
		push_error("blob mask: cannot create capture directory (%d)" % result)
		quit(2)
		return

	_demo = SCENE.instantiate() as BlobMaskDemo
	if _demo == null:
		push_error("blob mask: demo scene could not instantiate")
		quit(2)
		return
	root.add_child(_demo)
	for frame: int in range(FRAME_COUNT):
		_demo.set_demo_time(float(frame) / float(FPS))
		await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		if image == null or image.is_empty():
			push_error("blob mask: empty rendered image at frame %d" % frame)
			quit(3)
			return
		var png: String = frame_directory.path_join("frame_%04d.png" % frame)
		if image.save_png(png) != OK:
			push_error("blob mask: failed to save frame %d" % frame)
			quit(3)
			return

	print("BLOB_MASK_CAPTURE_OK frames=%d fps=%d seconds=6" % [FRAME_COUNT, FPS])
	quit(0)
