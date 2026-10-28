extends SceneTree

## Shelter readability (#235): the 727 street front from 20-30 m at eye height, daylight and
## dusk, so a player can tell the shelter from the shells beside it without the interface.
## Run: xvfb-run godot --path . --rendering-driver vulkan --fixed-fps 30 --script res://tools/runtime/capture_shelter_read.gd -- <out dir>

const SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"
const EYE_HEIGHT: float = 1.6
## [name, metres out from the 727 door, metres along the street (+ = door's right), hour]
const SHOTS: Array = [
	["25m_noon", 25.0, 0.0, 13.0],
	["25m_left_noon", 22.0, -12.0, 13.0],
	["25m_right_noon", 22.0, 12.0, 13.0],
	["25m_dusk", 25.0, 0.0, 18.5],
]

var _out: String = "user://shots/shelter_read"
var _world: Node3D
var _player: Node3D


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_run()


func _run() -> void:
	_world = (load(SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(_world)
	var ctx: Variant = null
	for _i: int in range(600):
		await process_frame
		ctx = _world.call(&"get_context")
		if ctx != null:
			break
	_player = ctx.player as Node3D
	## The frame is the street alone: Henry stands at the camera, dev labels and the HUD are hidden.
	for node: Node in [_player] + _world.find_children("*", "Label3D", true, false):
		(node as Node3D).visible = false
	for layer: Node in root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	var door := _world.find_children("HouseDoor", "", true, false)[0] as Node3D
	var out: Vector3 = door.global_basis.z
	out.y = 0.0
	out = out.normalized()
	var along: Vector3 = Vector3.UP.cross(out).normalized()
	var aim: Vector3 = door.global_position + Vector3.UP * 1.2
	print("[read] door ", door.global_position, " out ", out)
	for shot: Array in SHOTS:
		_set_hour(float(shot[3]))
		var from: Vector3 = door.global_position + out * float(shot[1]) + along * float(shot[2])
		from.y = _ground_y(from) + EYE_HEIGHT
		## Henry stands at the camera so streaming and the world around him load as in play.
		_player.global_position = Vector3(from.x, from.y - EYE_HEIGHT + 0.1, from.z)
		await _shot(String(shot[0]), from, aim)
	print("[read] done")
	quit(0)


func _set_hour(hour: float) -> void:
	for node: Node in _world.find_children("*", "DayNightManager", true, false):
		node.set(&"total_game_time_hours", floorf(float(node.get(&"total_game_time_hours")) / 24.0) * 24.0 + hour)
		node.call(&"force_update_lighting")


## Ground height under `at` from a ray down through the streamed world.
func _ground_y(at: Vector3) -> float:
	var space := _player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 60.0, at + Vector3.DOWN * 60.0)
	query.exclude = [(_player as CollisionObject3D).get_rid()] if _player is CollisionObject3D else []
	var hit: Dictionary = space.intersect_ray(query)
	return float(hit.position.y) if hit else at.y


func _shot(shot_name: String, from: Vector3, at: Vector3) -> void:
	var previous := root.get_camera_3d()
	var camera := Camera3D.new()
	camera.fov = 60.0
	camera.far = 600.0
	root.add_child(camera)
	camera.look_at_from_position(from, at)
	camera.make_current()
	for _i: int in range(150):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out).path_join(shot_name + ".png"))
	print("[read] ", shot_name, " from ", from)
	camera.queue_free()
	if previous != null:
		previous.make_current()
