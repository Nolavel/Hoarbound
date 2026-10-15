extends SceneTree
## Held flare pose check: Henry standing with the drawn flare in the hand socket, seen from the front and the left,
## once with the authored HeldFit and once with a fit given on the command line. Reports the nozzle in body space.
## xvfb-run godot --path . --rendering-driver vulkan --script tools/runtime/capture_held_flare_pose.gd -- <out_dir> [ox oy oz rx ry rz]

const VISUAL: String = "res://scenes/actors/player/HenryUALVisual.tscn"
const FLARE: String = "res://data/items/road_flare.tres"
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
const VIEWS: Dictionary = {"front": Vector3(0.0, 1.4, -2.2), "left": Vector3(-2.2, 1.4, 0.0), "top": Vector3(-0.4, 3.0, -0.6)}

var _out: String = ""
var _alt: Array = []
var _frame: int = 0
var _visual: HenryUALAnimation
var _camera: Camera3D
var _fit: HeldFit
var _pass: int = 0
var _authored: Array = []
var _report: Array = []


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_out = args[0]
	for i: int in range(1, args.size()):
		_alt.append(float(args[i]))
	DirAccess.make_dir_recursive_absolute(_out)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.6, 0.65)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.8)
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	root.add_child(sun)
	var script := GDScript.new()
	script.source_code = BODY_SOURCE
	script.reload()
	var body := CharacterBody3D.new()
	body.set_script(script)
	_visual = (load(VISUAL) as PackedScene).instantiate() as HenryUALAnimation
	_visual.rotation.y = PI  # the real player's model orientation
	body.add_child(_visual)
	body.set(&"animation_component", _visual)
	root.add_child(body)
	_fit = (load(FLARE) as ItemResource).held_fit
	_authored = [_fit.offset, _fit.rotation_deg]
	_camera = Camera3D.new()
	_camera.fov = 40.0
	root.add_child(_camera)
	_camera.make_current()


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		_draw()
	if _frame < 12:
		_visual.update_animation_blend(0.5)
		_visual.animation_tree.advance(0.1)
		return false
	if _frame == 12:
		var flare: Node3D = _visual.get_held_prop()
		var nozzle: Vector3 = (_visual.global_basis.rotated(Vector3.UP, PI).inverse() * flare.global_basis.y).normalized()
		_report.append({"fit": "authored" if _pass == 0 else "alt", "offset": _fit.offset, "rotation_deg": _fit.rotation_deg,
			"nozzle_body": nozzle, "tip": flare.global_position + flare.global_basis.y * 0.15})
	var view: int = _frame - 12
	if view >= 0 and view < VIEWS.size() * 4:
		var key: String = VIEWS.keys()[view / 4]
		_camera.look_at_from_position(VIEWS[key], Vector3(0.0, 1.15, 0.0))
		if view % 4 == 3:
			root.get_viewport().get_texture().get_image().save_png(_out.path_join("flare_%s_%s.png" % ["authored" if _pass == 0 else "alt", key]))
		return false
	if _pass == 0 and _alt.size() == 6:
		_pass = 1
		_fit.offset = Vector3(_alt[0], _alt[1], _alt[2])
		_fit.rotation_deg = Vector3(_alt[3], _alt[4], _alt[5])
		var old: Node3D = _visual.release_hand()
		if old != null:
			old.queue_free()
		_frame = 1
		return false
	print("flare pose: ", JSON.stringify(_report))
	quit(0)
	return true


func _draw() -> void:
	var item: ItemResource = load(FLARE) as ItemResource
	var flare: Node3D = HeldPropFactory.make(&"road_flare", item)
	_visual.hold_in_hand(flare)
	_fit.apply_to(flare)
