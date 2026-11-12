extends SceneTree

## Compares TpsCamera framing presets in the real 727 shelter: at each spot Henry walks forward and one frame
## is saved per preset, with shot-quality numbers judged at 16:9 (where he stands in the frame, whether his
## head is in it, how much of the frame is a surface nearer than a metre, how far the centre sees).
## Run (windowed for the frames): godot --path . --resolution 1280x720 --fixed-fps 30 --script res://tools/runtime/compare_camera_framing.gd -- [out_dir]

const SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"
const WARMUP_FRAMES: int = 300
const SETTLE_FRAMES: int = 40
const WALK_FRAMES: int = 45
## [name, Henry (u, v), facing point (u, v)] in the shelter plan frame.
const SPOTS: Array = [
	["corridor", Vector2(-6.0, -0.7), Vector2(6.0, -0.7)],
	["along_wall", Vector2(-8.0, -1.3), Vector2(8.0, -1.3)],
	["restroom", Vector2(-11.1, 2.4), Vector2(-11.1, 0.4)],
	["exam_room", Vector2(-7.4, -5.0), Vector2(-4.5, -4.0)],
	["stove_room", Vector2(2.6, 9.4), Vector2(-1.2, 6.4)],
]
## Preset name -> TpsCamera properties. Each preset sets every knob, so a run never inherits the last one.
const PRESETS: Dictionary = {
	"far_3.0": {"far_distance": 3.0, "direct_wall_clearance": 0.28, "direct_side_min": 0.34,
		"direct_side_per_metre": 0.4, "direct_tight_fov_deg": 0.0, "gear_hide_distance": 0.0},
	"far_2.2": {"far_distance": 2.2, "direct_wall_clearance": 0.28, "direct_side_min": 0.34,
		"direct_side_per_metre": 0.4, "direct_tight_fov_deg": 0.0, "gear_hide_distance": 0.0},
}

var _out: String = "user://shots/camera_framing_compare"
var _world: Node3D
var _house: Node3D
var _floor_y: float = 0.15
var _player: CharacterBody3D
var _camera: TpsCamera
var _rows: Array[Dictionary] = []


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_world = (load(SCENE) as PackedScene).instantiate() as Node3D
	_world.set(&"spawn_at_shelter", true)
	root.add_child(_world)
	## The numbers need physics and the camera, not pixels: 3D draws only for the saved frames.
	root.disable_3d = true
	_run.call_deferred()


func _run() -> void:
	for i: int in range(WARMUP_FRAMES):
		await process_frame
	var shelter: KeyWest727Shelter = _world.find_child("Shelter727", true, false) as KeyWest727Shelter
	_player = _world.get(&"player") as CharacterBody3D
	_camera = _world.get(&"camera") as TpsCamera
	if shelter == null or _player == null or _camera == null:
		push_error("camera compare: shelter, player or TpsCamera missing")
		quit(1)
		return
	_house = shelter.get_node(^"House") as Node3D
	_floor_y = float(shelter.interior["floor_y"])
	for spot: Array in SPOTS:
		for preset: String in PRESETS:
			for key: String in PRESETS[preset]:
				_camera.set(key, PRESETS[preset][key])
			await _place(spot)
			Input.action_press(&"move_forward")
			for i: int in range(WALK_FRAMES):
				await process_frame
			root.disable_3d = false
			await process_frame
			await process_frame
			var row: Dictionary = _measure()
			row["spot"] = spot[0]
			row["preset"] = preset
			_rows.append(row)
			if DisplayServer.get_name() != "headless":
				root.get_viewport().get_texture().get_image().save_png(
					ProjectSettings.globalize_path(_out).path_join("%s__%s.png" % [spot[0], preset]))
			root.disable_3d = true
			Input.action_release(&"move_forward")
			print("camera compare: %-11s %-15s %s" % [spot[0], preset, row])
	var file: FileAccess = FileAccess.open(ProjectSettings.globalize_path(_out).path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(_rows, "\t"))
	file.close()
	quit(0)


func _place(spot: Array) -> void:
	var at: Vector3 = _plan(spot[1])
	var face: Vector3 = _plan(spot[2])
	_player.global_position = at
	_player.velocity = Vector3.ZERO
	_player.look_at(Vector3(face.x, at.y, face.z), Vector3.UP)
	var to: Vector3 = face - at
	_camera.set_look(atan2(-to.x, -to.z), -10.0)
	_camera.snap_to_target()
	for i: int in range(SETTLE_FRAMES):
		await process_frame


## Plan point (u, v) in world space, at the height Henry's origin stands at.
func _plan(uv: Vector2) -> Vector3:
	return _house.global_transform * Vector3(uv.x, _floor_y + _camera.origin_above_feet + 0.05, uv.y)


## Shot quality of the frame the camera holds now, at 16:9.
func _measure() -> Dictionary:
	var eye: Vector3 = _camera.get_eye_position()
	var half_y: float = tan(deg_to_rad(_camera.fov * 0.5))
	var half_x: float = half_y * 16.0 / 9.0
	var head: Vector3 = _camera.global_transform.affine_inverse() * (eye + Vector3.UP * 0.05)
	var shoulder: Vector3 = _camera.global_transform.affine_inverse() * (eye - Vector3.UP * 0.25)
	var space: PhysicsDirectSpaceState3D = root.get_world_3d().direct_space_state
	var near: int = 0
	var total: int = 0
	var centre_free: float = 0.0
	var centre_rays: int = 0
	for iy: int in range(7):
		for ix: int in range(13):
			var sx: float = lerpf(-0.92, 0.92, float(ix) / 12.0)
			var sy: float = lerpf(-0.9, 0.9, float(iy) / 6.0)
			var dir: Vector3 = (_camera.global_basis * Vector3(sx * half_x, sy * half_y, -1.0)).normalized()
			var query := PhysicsRayQueryParameters3D.create(_camera.global_position, _camera.global_position + dir * 12.0)
			query.exclude = [_player.get_rid()]
			var hit: Dictionary = space.intersect_ray(query)
			var free: float = _camera.global_position.distance_to(hit["position"]) if not hit.is_empty() else 12.0
			total += 1
			near += int(free < 1.0)
			if absf(sx) < 0.25 and absf(sy) < 0.35:
				centre_free += free
				centre_rays += 1
	return {
		"head_x": snappedf(_frame_x(head, half_x), 0.01),
		"head_in_frame": _in_frame(head, half_x, half_y),
		"shoulder_in_frame": _in_frame(shoulder, half_x, half_y),
		"eye_m": snappedf(_camera.global_position.distance_to(eye), 0.01),
		"side_m": snappedf(absf(shoulder.x), 0.01),
		"body_fade": snappedf(_camera.get_body_fade(), 0.01),
		"near_wall_share": snappedf(float(near) / float(total), 0.01),
		"centre_free_m": snappedf(centre_free / float(maxi(centre_rays, 1)), 0.1),
		"fov": snappedf(_camera.fov, 0.1),
	}


static func _frame_x(local: Vector3, half_x: float) -> float:
	if local.z >= -0.01:
		return -1.0
	return 0.5 + 0.5 * (local.x / -local.z) / half_x


static func _in_frame(local: Vector3, half_x: float, half_y: float) -> bool:
	return local.z < -0.01 and absf(local.x) <= -local.z * half_x and absf(local.y) <= -local.z * half_y
