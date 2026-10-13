extends SceneTree

## Captures a spot of the real Key West Reality scene: Henry is moved there, chunks stream in,
## then a free camera shoots the spot from eye height and from above.
## Run: xvfb-run godot --path . --rendering-driver vulkan --script res://tools/runtime/capture_key_west_reality_spot.gd -- <out_dir> <name> <x> <z> <look_x> <look_z> [noshell]
## noshell hides the deep-snow shell, to tell what the shell covers.

const SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"
const WARMUP_FRAMES: int = 180
const SETTLE_FRAMES: int = 40
const EYE_M: float = 1.7

var _out: String = ""
var _name: String = "spot"
var _at: Vector2
var _look: Vector2
var _world: Node3D
var _camera: Camera3D
var _frame: int = 0
var _stage: int = 0
var _hide_shell: bool = false


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_out = args[0]
	_name = args[1]
	_at = Vector2(float(args[2]), float(args[3]))
	_look = Vector2(float(args[4]), float(args[5]))
	_hide_shell = args.size() > 6 and args[6] == "noshell"
	DirAccess.make_dir_recursive_absolute(_out)
	_world = (load(SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(_world)


func _process(_delta: float) -> bool:
	_frame += 1
	var player: Node3D = _world.get(&"player") as Node3D
	if _frame == 30 and player != null:
		player.global_position = Vector3(_at.x, _ground(_at) + 0.3, _at.y)
	if _frame < WARMUP_FRAMES:
		return false
	if _camera == null:
		if _hide_shell:
			for shell: Node in root.find_children("*", "SnowShell", true, false):
				for geo: Node in shell.find_children("*", "GeometryInstance3D", true, false):
					(geo as GeometryInstance3D).visible = false
		_camera = Camera3D.new()
		_camera.fov = 65.0
		_camera.far = 1500.0
		root.add_child(_camera)
		_camera.make_current()
	if (_frame - WARMUP_FRAMES) % SETTLE_FRAMES != 0:
		return false
	match _stage:
		0:
			_camera.look_at_from_position(Vector3(_at.x, _ground(_at) + EYE_M, _at.y), Vector3(_look.x, _ground(_look) + 0.5, _look.y))
		1:
			_save("%s_eye" % _name)
			var mid: Vector2 = (_at + _look) * 0.5
			_camera.look_at_from_position(Vector3(mid.x - 6.0, _ground(mid) + 22.0, mid.y + 18.0), Vector3(mid.x, _ground(mid), mid.y))
		2:
			_save("%s_above" % _name)
			quit(0)
			return true
	_stage += 1
	return false


## Ground under a point from the streamed Reality heights (sea level when not loaded yet).
func _ground(p: Vector2) -> float:
	var ground: Node = _world.find_child("RealityGround", true, false)
	return float(ground.get_height(p.x, p.y)) if ground is KeyWestRealityGround else 0.0


func _save(shot: String) -> void:
	var path: String = _out.path_join(shot + ".png")
	root.get_viewport().get_texture().get_image().save_png(path)
	print("spot capture: ", path)
