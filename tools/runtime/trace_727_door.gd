extends SceneTree
## Spawns at the 727 shelter with the player camera and traces the front door: leaf visibility, cell changes near
## 727, and every visible geometry crossing the camera-to-door segment; frames at fixed times and on each change.
## godot --path . --script <this> -- <out_dir> [scene]

const SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"
const STREAMING: GDScript = preload("res://core/world/streaming_system.gd")
const NEAR_M: float = 700.0
const FRAMES: int = 900
const SHOT_FRAMES: Array[int] = [3, 30, 90, 180, 300, 600, 899]

var _out: String = ""
var _world: Node3D
var _ctx: WorldContext
var _door: Node3D
var _leaf: GeometryInstance3D
var _frame: int = 0
var _changes: Array = []
var _rows: Array = []
var _leaf_was: int = -1
var _shoot_next: bool = false


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	_world = (load(args[1] if args.size() > 1 else SCENE) as PackedScene).instantiate() as Node3D
	_world.set(&"spawn_at_shelter", true)
	root.add_child(_world)


func _process(_delta: float) -> bool:
	if _ctx == null:
		_ctx = _world.call(&"get_context") if _world.has_method(&"get_context") else null
		if _ctx == null:
			return false
		var shelter: Node = _world.find_child("Shelter727", true, false)
		_door = shelter.find_child("HouseDoor", true, false) as Node3D
		_leaf = _door.find_child("DoorLeaf", true, false) as GeometryInstance3D
		(_ctx.get_system(STREAMING) as StreamingSystem).cell_state_changed.connect(_on_cell)
	_frame += 1
	var visible_now: int = 1 if _leaf.is_visible_in_tree() else 0
	if visible_now != _leaf_was:
		_changes.append({"frame": _frame, "event": "leaf visible_in_tree=%d" % visible_now})
		_leaf_was = visible_now
		_shoot_next = true
	if _shoot_next or SHOT_FRAMES.has(_frame):
		_shoot_next = false
		_record()
	if _frame >= FRAMES:
		var f: FileAccess = FileAccess.open(_out.path_join("door_trace.json"), FileAccess.WRITE)
		f.store_string(JSON.stringify({"changes": _changes, "frames": _rows}, " ", false))
		f.close()
		print("door trace: wrote ", _out.path_join("door_trace.json"))
		quit(0)
	return false


func _on_cell(id: StringName, state: StreamingSystem.CellState) -> void:
	if _door == null:
		return
	var s: String = String(id)
	if not (s.begins_with("kw_gen_") or s.begins_with("kw_far_") or s.begins_with("kw_bld_")):
		return
	var parts: PackedStringArray = s.split("_")
	var centre: Vector3 = Vector3((int(parts[-2]) + 0.5) * 512.0, 0.0, (int(parts[-1]) + 0.5) * 512.0) if not s.begins_with("kw_bld_") else _door.global_position
	if Vector2(centre.x, centre.z).distance_to(Vector2(_door.global_position.x, _door.global_position.z)) > NEAR_M:
		return
	_changes.append({"frame": _frame, "event": "%s -> %s" % [s, StreamingSystem.CellState.keys()[state]]})
	_shoot_next = true


## One traced frame: camera, leaf state, and visible geometry whose bounds cross the camera-to-leaf segment.
func _record() -> void:
	var cam: Camera3D = root.get_camera_3d()
	var from: Vector3 = cam.global_position
	var to: Vector3 = (_leaf.global_transform * _leaf.get_aabb()).get_center()
	var blockers: Array = []
	for n: Node in _world.find_children("*", "GeometryInstance3D", true, false):
		var g: GeometryInstance3D = n as GeometryInstance3D
		if g == _leaf or not g.is_visible_in_tree() or _door.is_ancestor_of(g):
			continue
		var box: AABB = g.global_transform * g.get_aabb()
		if box.size == Vector3.ZERO or box.grow(0.05).intersects_segment(from, to) == null:
			continue
		var d: float = g.get_visibility_range_end()
		blockers.append({"path": str(_world.get_path_to(g)), "class": g.get_class(), "visibility_range_end": d,
			"camera_distance": snappedf(from.distance_to(box.get_center()), 0.1), "transparency": g.transparency})
	var hit: Dictionary = cam.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	var name: String = "frame_%04d" % _frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	_rows.append({"frame": _frame, "shot": name + ".png", "camera": [snappedf(from.x, 0.01), snappedf(from.y, 0.01), snappedf(from.z, 0.01)],
		"door": [snappedf(to.x, 0.01), snappedf(to.y, 0.01), snappedf(to.z, 0.01)], "camera_to_door_m": snappedf(from.distance_to(to), 0.01),
		"leaf_visible": _leaf.is_visible_in_tree(), "leaf_range_end": _leaf.get_visibility_range_end(), "leaf_transparency": _leaf.transparency,
		"in_frustum": cam.is_position_in_frustum(to), "ray_hit": str(hit.get("collider").get_path()) if not hit.is_empty() and hit.get("collider") is Node else "",
		"blockers": blockers})
	print("door trace: frame %d leaf %s, %d blockers, ray %s" % [_frame, _leaf.is_visible_in_tree(), blockers.size(), _rows[-1]["ray_hit"]])
