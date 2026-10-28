extends SceneTree
## Held lighter RMB check: Henry holds the lighter, the present hold raises it before the chest and
## lights it; at 10 s the flame goes out with RMB still held. Front and left frames per stage.
## godot --path . --fixed-fps 30 --resolution 960x540 --script tools/runtime/capture_held_lighter.gd -- <out_dir>

const VISUAL: String = "res://scenes/actors/player/HenryUALVisual.tscn"
## The minimal body test_held_light uses: the animation reads speed and view from its parent.
const BODY_SOURCE: String = """extends CharacterBody3D
var animation_component: HenryUALAnimation
func get_locomotion_speed_ratio() -> float:
	return 0.0
func get_crouch_speed_ratio() -> float:
	return 0.0
func is_crouching() -> bool:
	return false
func get_view_direction() -> Vector3:
	return Vector3.FORWARD
"""
const VIEWS: Dictionary = {"front": Vector3(0.0, 1.45, -1.6), "left": Vector3(-1.6, 1.45, -0.3)}
## Stage name -> seconds since the press.
const STAGES: Dictionary = {"0_idle": -1.0, "1_lit": 1.2, "2_out": 10.6}

var _out: String = ""
var _visual: HenryUALAnimation
var _held: HeldItemComponent
var _camera: Camera3D
var _seconds: float = -0.5
var _done: Array = []
var _view: int = 2
var _shot_frames: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "user://shots/held_lighter"
	DirAccess.make_dir_recursive_absolute(_out)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.12, 0.13, 0.15)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.45, 0.45, 0.5)
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	sun.light_energy = 0.4
	root.add_child(sun)
	var script := GDScript.new()
	script.source_code = BODY_SOURCE
	script.reload()
	var body := CharacterBody3D.new()
	body.set_script(script)
	_visual = (load(VISUAL) as PackedScene).instantiate() as HenryUALAnimation
	_visual.name = "HenryUALVisual"
	_visual.rotation.y = PI  # the real player's model orientation
	body.add_child(_visual)
	body.set(&"animation_component", _visual)
	_held = HeldItemComponent.new()
	body.add_child(_held)
	root.add_child(body)
	_camera = Camera3D.new()
	_camera.fov = 40.0
	root.add_child(_camera)
	_camera.make_current()


func _process(delta: float) -> bool:
	_visual.update_animation_blend(delta)
	if _held._prop == null:
		_held._item_id = &"lighter"
		_held._draw()
		return false
	var before: float = _seconds
	_seconds += delta
	if before < 0.0 and _seconds >= 0.0:
		_held._presenting = true
	if _shot_frames > 0:
		_shot_frames -= 1
		if _shot_frames == 0:
			var key: String = VIEWS.keys()[_view]
			root.get_viewport().get_texture().get_image().save_png(_out.path_join("%s_%s.png" % [_done[-1], key]))
			_view += 1
			if _view < VIEWS.size():
				_aim_camera()
		return false
	for stage: String in STAGES:
		if stage in _done or _seconds < float(STAGES[stage]):
			continue
		_done.append(stage)
		print("[held_lighter] ", stage, " lit=", _held.is_flame_lit(), " t=", snappedf(_seconds, 0.01))
		_view = 0
		_aim_camera()
		return false
	if _view < VIEWS.size():
		return false
	if _done.size() == STAGES.size():
		quit(0)
		return true
	return false


func _aim_camera() -> void:
	_camera.look_at_from_position(VIEWS[VIEWS.keys()[_view]], Vector3(0.0, 1.3, 0.0))
	_shot_frames = 3
