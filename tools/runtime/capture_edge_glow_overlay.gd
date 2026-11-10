extends SceneTree

## Live 727 + actual Tab-Hub and cabinet, from capture_container_view.gd.
## Scripted overlay colors only: not a gameplay result integration.
const SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"
const FPS: int = 30

var _out: String = "user://shots/container_view"
var _overlay: EdgeGlowOverlay
var _frames_saved: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_run()


func _run() -> void:
	TranslationServer.set_locale("ru")
	var world := (load(SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(world)
	root.size = Vector2i(960, 540)
	root.content_scale_size = Vector2i(960, 540)
	var ctx: Variant = null
	for _i: int in range(600):
		await process_frame
		ctx = world.call(&"get_context")
		if ctx != null:
			break
	if ctx == null:
		_fail("world context missing")
		return
	var player := ctx.player as Player
	for node: Node in world.find_children("*", "DayNightManager", true, false):
		node.set(&"total_game_time_hours", floorf(float(node.get(&"total_game_time_hours")) / 24.0) * 24.0 + 13.0)
		node.call(&"force_update_lighting")
	for _i: int in range(120):
		await process_frame
	var found := world.find_children("Shelves", "ItemContainer", true, false)
	if found.is_empty():
		_fail("727 cabinet missing")
		return
	var shelves := found[0] as ItemContainer
	if shelves.door != null and shelves.door.is_open():
		shelves.door.interact()
	## Henry stands out before the cabinet, a little off to its left (as one looks in), facing it.
	var face: Array = shelves.front()
	var stand: Vector3 = (face[0] as Vector3) + (face[1] as Vector3) * 1.3 - (face[2] as Vector3) * 0.35
	stand.y = player.global_position.y
	player.global_position = stand
	player.velocity = Vector3.ZERO
	player.look_at(face[0] as Vector3 * Vector3(1, 0, 1) + Vector3.UP * stand.y, Vector3.UP)
	var inventory := player.get_node(^"InventoryComponent") as InventoryComponent
	for _n: int in 3:
		inventory.try_add(ItemCatalog.get_item(&"spov_can"))
	for _i: int in range(60):
		await physics_frame
	var hub := player.get_node(^"PlayerHubComponent") as PlayerHubComponent

	# Both shots are live 3D gameplay, using the real Hub camera and held pack.
	var layer := CanvasLayer.new()
	layer.layer = 30
	root.add_child(layer)
	var screen := Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(screen)
	_overlay = EdgeGlowOverlay.new()
	screen.add_child(_overlay)
	_overlay.set_process(false)
	if not hub.open():
		_fail("Tab-Hub refused to open")
		return
	await _settle(70)
	if hub.get_pack_hands() == null:
		_fail("Tab-Hub did not produce actual 3D pack handling")
		return
	print("EDGE_GLOW_HUB: actual 3D pack")
	await _capture_states("tab")
	hub.close()
	_overlay.set_hub_active(false)
	await _settle(70)
	# Visit the same real 727 cabinet through the existing Hub entry point.
	if not shelves.door.is_open():
		shelves.door.interact()
	await _settle(70)
	if not hub.visit_container(shelves):
		_fail("cabinet Hub refused to open")
		return
	await _settle(100)
	var hands: PackHandling = hub.get_pack_hands()
	if hands == null or hands.container != shelves:
		_fail("cabinet did not produce 3D pack and shelves")
		return
	print("EDGE_GLOW_HUB: real 727 cabinet paired with pack")
	await _capture_states("cabinet")
	hub.close()
	_overlay.set_hub_active(false)
	if _frames_saved != 10:
		_fail("incomplete captures")
		return
	print("EDGE_GLOW_CAPTURE: PASS")
	quit(0)


func _settle(frames: int) -> void:
	for _i: int in frames:
		await process_frame


func _advance(seconds: float) -> void:
	var frames: int = maxi(1, int(ceil(seconds * 60.0)))
	for _i: int in frames:
		_overlay._process(seconds / float(frames))


func _capture_states(prefix: String) -> void:
	_overlay.set_hub_active(false)
	await _snap(prefix + "_01_off")
	_overlay.set_hub_active(true)
	_advance(0.45)
	await _snap(prefix + "_02_idle")
	_overlay.set_action_active(true)
	_advance(0.45)
	await _snap(prefix + "_03_amber")
	_overlay.show_result(true)
	_advance(0.15)
	await _snap(prefix + "_04_green")
	_overlay.show_result(false)
	_advance(0.15)
	await _snap(prefix + "_05_red")
	_overlay.set_hub_active(false)


func _snap(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img == null or img.is_empty():
		_fail("empty image " + name)
		return
	if img.save_png(ProjectSettings.globalize_path(_out).path_join(name + ".png")) != OK:
		_fail("cannot save " + name)
		return
	_frames_saved += 1
	print("EDGE_GLOW_CAPTURE: " + name)


func _fail(message: String) -> void:
	push_error("EDGE_GLOW_CAPTURE: " + message)
	quit(1)
