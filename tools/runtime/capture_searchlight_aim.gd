extends SceneTree

## A few seconds of aiming the searchlight at night outside 727 Fort St: the camera looks left, right, up and down
## (Henry's head and the light follow), then held LMB raises the light forward and sweeps again. PNG frames at 30 fps.
## Run: xvfb-run godot --path . --rendering-driver vulkan --fixed-fps 30 --resolution 960x540 --script res://tools/runtime/capture_searchlight_aim.gd -- <out dir>

const WORLD: PackedScene = preload("res://scenes/world/key_west/key_west_reality.tscn")
const NIGHT_HOUR: float = 22.5

var _out: String = "user://shots/searchlight_aim"
var _camera: Camera3D
var _player: Player
var _frame: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_run()


func _run() -> void:
	var world: Node = WORLD.instantiate()
	root.add_child(world)
	var ctx: Variant = null
	for _i: int in range(600):
		await process_frame
		ctx = world.call(&"get_context")
		if ctx != null:
			break
	_player = ctx.player as Player
	for weather: Node in world.find_children("*", "WeatherController", true, false):
		weather.call(&"set_weather", &"calm", true)
	for day: Node in world.find_children("*", "DayNightManager", true, false):
		day.set(&"total_game_time_hours", NIGHT_HOUR)
		day.call(&"force_update_lighting")
		day.set_process(false)
	var pickup := world.find_children("SearchlightShelter", "ItemPickup", true, false)[0] as ItemPickup
	var door := world.find_children("HouseDoor", "", true, false)[0] as Node3D
	pickup.pick_up(true)
	var held := _player.get_node(^"HeldItemComponent") as HeldItemComponent
	held.present_owned(&"searchlight")
	(held.get_held_prop() as HeldSearchlight).toggle()
	var out: Vector3 = door.global_basis.z
	out.y = 0.0
	out = out.normalized()
	_player.global_position = door.global_position + out * 6.0 + Vector3.UP
	_player.look_at(_player.global_position + out, Vector3.UP)
	for layer: Node in root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	_camera = Camera3D.new()
	_camera.fov = 60.0
	root.add_child(_camera)
	_camera.make_current()
	await _frames(40)
	## Yaw then pitch of where the camera looks, degrees, keyed over the run.
	var keys: Array = [[0, 0.0, 0.0], [20, -40.0, 0.0], [45, 40.0, 0.0], [60, 0.0, 0.0], [72, 0.0, 22.0], [86, 0.0, -20.0], [96, 0.0, 0.0]]
	await _sweep(keys, false)
	Input.action_press(&"fire")
	await _sweep(keys, true)
	Input.action_release(&"fire")
	await _sweep([[0, 0.0, 0.0], [20, 0.0, 0.0]], false)
	print("SEARCHLIGHT_AIM frames=", _frame)
	quit()


## Steps the camera over shoulder along the keyed yaw/pitch, saving every frame.
func _sweep(keys: Array, aiming: bool) -> void:
	var last: int = int(keys[keys.size() - 1][0])
	for f: int in range(last + 1):
		var yaw: float = 0.0
		var pitch: float = 0.0
		for k: int in range(keys.size() - 1):
			var a: Array = keys[k]
			var b: Array = keys[k + 1]
			if f >= int(a[0]) and f <= int(b[0]):
				var t: float = smoothstep(0.0, 1.0, float(f - int(a[0])) / maxf(float(int(b[0]) - int(a[0])), 1.0))
				yaw = lerpf(float(a[1]), float(b[1]), t)
				pitch = lerpf(float(a[2]), float(b[2]), t)
		var forward: Vector3 = (-_player.global_basis.z).rotated(Vector3.UP, deg_to_rad(-yaw))
		var right: Vector3 = forward.cross(Vector3.UP).normalized()
		var look: Vector3 = (forward * cos(deg_to_rad(pitch)) + Vector3.UP * sin(deg_to_rad(pitch))).normalized()
		var eye: Vector3 = _player.global_position + Vector3.UP * 0.75 - forward * 2.6 + right * 0.55
		_camera.global_position = eye
		_camera.look_at(eye + look * 10.0, Vector3.UP)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png("%s/f_%04d.png" % [_out, _frame])
		_frame += 1


func _frames(count: int) -> void:
	for _i: int in range(count):
		await process_frame
