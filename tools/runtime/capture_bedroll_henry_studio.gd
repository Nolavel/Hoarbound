extends SceneTree

## Bounded Forward+/Vulkan visual QA of the real Henry, pack, and bedroll flow.
## Uses a simple floor so the view isolates the asset; not a 727 scene capture.
## Run with Xvfb and --rendering-driver vulkan --rendering-method forward_plus.

const PLAYER: PackedScene = preload("res://scenes/actors/player/player.tscn")
const ITEM: ItemResource = preload("res://data/items/bedroll.tres")
var _out := "user://shots/bedroll_henry"
var _camera: Camera3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_run()


func _run() -> void:
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.20, 0.24, 0.30)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color(0.58, 0.65, 0.75)
	world.environment.ambient_light_energy = 1.0
	root.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-48, -35, 0)
	root.add_child(sun)
	var floor := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(12, .3, 12)
	collider.shape = shape
	collider.position.y = -.15
	floor.add_child(collider)
	var ground := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = shape.size
	ground.mesh = box
	ground.position.y = -.15
	ground.material_override = StylizedEnvironmentMaterial.make_static(Color(.37,.40,.44), .96)
	floor.add_child(ground)
	root.add_child(floor)
	var player := PLAYER.instantiate() as Player
	root.add_child(player)
	player.position = Vector3(0,1,0)
	for _i: int in range(50):
		await process_frame
	var cursor := player.get_node_or_null(^"MouseCursorUI") as MouseCursorUI
	if cursor != null:
		cursor.set_process(false)
		cursor.visible = false
	for layer: Node in root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	_camera = Camera3D.new()
	_camera.fov = 42
	root.add_child(_camera)
	_camera.make_current()
	var inventory := InventoryComponent.find_in(player)
	var component := player.get_node(^"BedrollComponent") as BedrollComponent
	if not inventory.has_item(&"bedroll"):
		inventory.try_add(ITEM)
	if not component.lay_down():
		push_error("Bedroll could not be laid")
		quit(1)
		return
	for _i: int in range(12):
		await process_frame
	var laid := component.get_laid_bedroll()
	_camera.look_at_from_position(laid.global_position + Vector3(1.5,2.0,1.7), laid.global_position + Vector3.UP*.03)
	await _save("01_open_on_ground.png")
	var pickup := laid.get_node(^"Pack") as ItemPickup
	if not pickup.pick_up():
		push_error("Bedroll pickup failed")
		quit(1)
		return
	## Laying triggers the 5.17 s "fix" clip. Wait for the actual end so the
	## backpack is reviewed on an upright Henry, never mid-kneel.
	for _i: int in range(300):
		if not player.animation_component.is_action_active():
			break
		await process_frame
	if player.animation_component.is_action_active():
		push_error("Henry did not return from the bedroll placement action")
		quit(1)
		return
	for _i: int in range(45):
		await process_frame
	var pack: PackRig = player.animation_component.get_pack_rig()
	var mounted := pack.get_canvas().get_node(^"Bedroll") as Node3D
	if not mounted.visible:
		push_error("Bedroll not visible on Henry")
		quit(1)
		return
	for overlay: Node in root.find_children("*", "Control", true, false):
		(overlay as Control).visible = false
	var focus := player.global_position + Vector3.UP * 0.45
	var back_direction := player.global_basis.z.normalized()
	var side_direction := player.global_basis.x.normalized()
	print("BEDROLL_FOCUS player=", player.global_position, " mounted=", mounted.global_position,
		" player_yaw=", player.rotation_degrees.y)
	_camera.look_at_from_position(focus + back_direction * 2.35 + Vector3.UP * 0.45, focus)
	await _save("02_on_henry_back.png")
	_camera.look_at_from_position(focus + side_direction * 2.35 + Vector3.UP * 0.4, focus)
	await _save("03_on_henry_side.png")
	print("BEDROLL_STUDIO_CAPTURE Forward+ frames=3")
	quit()


func _save(filename: String) -> void:
	await process_frame
	for layer: Node in root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	for overlay: Node in root.find_children("*", "Control", true, false):
		(overlay as Control).visible = false
	for label: Node in root.find_children("*", "Label3D", true, false):
		(label as Label3D).visible = false
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out).path_join(filename))
