extends SceneTree

## Stills of the thin-ice lab: Henry stands still on the thinnest ice until it creaks,
## cracks and gives way, then climbs out. Two angles per beat, plus a stage trace.
## Run: xvfb-run godot --path . --rendering-driver vulkan --fixed-fps 30 --resolution 1600x900 --script res://tools/runtime/capture_ice_lab.gd -- <out dir>

const LAB: String = "res://tests/scenes/ice_lab.tscn"
const STAND: Vector3 = Vector3(30.6, 0.1, 29.4)

var _out: String = "user://shots/ice_lab"
var _lab: IceLabDirector
var _camera: Camera3D


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_run()


func _run() -> void:
	TranslationServer.set_locale("ru")
	_lab = (load(LAB) as PackedScene).instantiate() as IceLabDirector
	root.add_child(_lab)
	_camera = Camera3D.new()
	_camera.fov = 55.0
	root.add_child(_camera)
	await _frames(20)
	_lab.henry.global_position = STAND
	_lab.henry.rotation.y = deg_to_rad(-35.0)
	_camera.make_current()
	var field: IceField = _lab.ice_field
	var tile: Vector2i = field.world_to_tile(STAND)
	await _frames(30)
	await _shoot("01_solid")
	await _wait_stage(field, tile, IceField.Stage.CREAKING)
	print("ICE_LAB creaking at integrity %.3f growth %.2f" % [field.get_integrity(tile), _lab.presenter.get_growth(tile)])
	await _wait_stage(field, tile, IceField.Stage.CRACKING)
	await _frames(15)
	await _shoot("02_first_cracks")
	await _frames(22)
	print("ICE_LAB late cracks growth %.2f" % _lab.presenter.get_growth(tile))
	await _shoot("03_spreading")
	await _wait_stage(field, tile, IceField.Stage.BROKEN)
	await _frames(40)
	print("ICE_LAB broken: in_water=%s henry_y=%.2f" % [_lab.is_in_water(), _lab.henry.global_position.y])
	await _shoot("04_through")
	await _frames(30)
	var climbed: bool = _lab.climb_out()
	await _frames(30)
	print("ICE_LAB climbed=%s in_water=%s henry=%s" % [climbed, _lab.is_in_water(), str(_lab.henry.global_position)])
	await _shoot("05_climbed_out")
	_lab.henry.global_position = Vector3(-4.0, 0.1, 29.0)
	await _frames(10)
	await _shoot_top("06_hole_top", tile)
	print("ICE_LAB_CAPTURE: done")
	quit(0)


func _wait_stage(field: IceField, tile: Vector2i, stage: IceField.Stage) -> void:
	for i: int in range(900):
		if field.get_stage(tile) == stage:
			return
		await process_frame
	push_error("ICE_LAB stage %d never reached" % stage)


## A 3/4 view on Henry and a near top-down view on the ice beside him.
func _shoot(label: String) -> void:
	var at: Vector3 = _lab.henry.global_position
	at.y = 0.0
	_camera.look_at_from_position(at + Vector3(-3.4, 2.6, 3.2), at + Vector3(0.4, 0.4, -0.3))
	await _frames(3)
	_save(label + "_a")
	_camera.look_at_from_position(at + Vector3(0.2, 4.2, 2.4), at + Vector3(0.2, 0.0, -0.2))
	await _frames(3)
	_save(label + "_b")


func _shoot_top(label: String, tile: Vector2i) -> void:
	var centre: Vector3 = _lab.presenter.get_hole_centre(tile)
	_camera.look_at_from_position(centre + Vector3(0.01, 7.5, 0.6), centre)
	await _frames(3)
	_save(label)


func _save(label: String) -> void:
	var image: Image = root.get_viewport().get_texture().get_image()
	var path: String = ProjectSettings.globalize_path(_out.path_join(label + ".png"))
	image.save_png(path)
	print("ICE_LAB shot ", path)


func _frames(count: int) -> void:
	for i: int in range(count):
		await process_frame
