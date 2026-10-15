extends SceneTree

## Captures the follow-only developer diorama map with OSM address/street labels.

const MAIN_SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"
const OUT_DIR: String = "res://docs/runtime_previews/dev_diorama_map"
const BIND_FRAME: int = 35
const FIRST_CAPTURE_FRAME: int = 60
## Densest Duval St block (capture_stylized_shadows uses the same spot), local x/z.
const DUVAL := Vector2(-3072.7, 1374.3)

var _scene: Node3D
var _player: Player
var _map: DevDioramaMap
var _frame: int = 0
var _phase: int = 0
var _next_capture: int = FIRST_CAPTURE_FRAME
## Reality starts Henry at the fort, with no addresses in view: he is moved to Duval St first.
var _placed: bool = false
var _placing: bool = false


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_scene = (load(MAIN_SCENE) as PackedScene).instantiate() as Node3D
	if _scene is World:
		(_scene as World).enable_runtime_dev_map = true
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame >= BIND_FRAME and (_map == null or _player == null):
		_bind()
	if _frame < _next_capture or _map == null or _player == null:
		return false
	if not _placed:
		if not _placing:
			_placing = true
			_place_on_duval()
		return false

	if _phase == 0:
		_capture_full("01_follow_with_labels")
		_capture_map("02_map_labels_close")
		_player.global_position += Vector3(24.0, 0.0, -18.0)
		_next_capture = _frame + 20
		_phase = 1
		return false

	## Full frame is required here: HenryMarker is 2D UI over the SubViewport texture.
	_capture_full("03_follow_after_move")
	_capture_map("04_map_labels_followed")
	print("dev diorama map capture: complete; labels=", _map.get_visible_label_count())
	quit()
	return true


func _bind() -> void:
	_player = get_first_node_in_group(&"player") as Player
	_map = get_first_node_in_group(DevDioramaMap.GROUP) as DevDioramaMap
	var splash := _scene.get_node_or_null(^"StartupTitleCard")
	if splash != null:
		splash.queue_free()
	if _player != null:
		_player.set_physics_process(false)
	if _map == null:
		push_error("dev diorama map capture: map UI did not initialize")
		quit(1)
		return
	if _player != null and _map != null and not _map.is_map_open():
		_map._on_toggle_requested()


## Henry on Duval St, the densest addressed block, once that chunk is live; the map re-centres and relabels.
func _place_on_duval() -> void:
	await CaptureWorldSupport.wait_streamed(self, _scene, _player, DUVAL)
	_player.global_position = Vector3(DUVAL.x, CaptureWorldSupport.height(_scene, DUVAL.x, DUVAL.y) + 1.0, DUVAL.y)
	if _map.is_map_open():
		_map._on_toggle_requested()
	_map._on_toggle_requested()
	_placed = true
	_next_capture = _frame + 20


func _capture_full(name: String) -> void:
	var path: String = "%s/%s.png" % [OUT_DIR, name]
	var error: Error = root.get_texture().get_image().save_png(path)
	if error != OK:
		push_error("dev diorama map capture: cannot save %s (%d)" % [path, error])
	else:
		print("[dev-diorama] ", path)


func _capture_map(name: String) -> void:
	var image: Image = _map.get_map_image()
	var path: String = "%s/%s.png" % [OUT_DIR, name]
	if image == null or image.is_empty():
		push_error("dev diorama map capture: viewport returned no image")
		return
	var error: Error = image.save_png(path)
	if error != OK:
		push_error("dev diorama map capture: cannot save %s (%d)" % [path, error])
	else:
		print("[dev-diorama] ", path)
