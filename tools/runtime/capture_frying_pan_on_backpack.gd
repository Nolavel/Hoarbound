extends SceneTree

## Forward+/Vulkan review of the frying-pan GLB on Henry's actual backpack carabiner.
## The pan is staged for visual review; this does not add a gameplay item.

const PLAYER: PackedScene = preload("res://scenes/actors/player/player.tscn")
const PAN_PATH := "res://assets/items/frying_pan/frying_pan.glb"
const EYE_LOCAL := Vector3(0.250, 0.045, 0.0)
var _out := "user://shots/frying_pan"
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
	world.environment.background_color = Color(.16, .20, .26)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color(.55, .64, .75)
	world.environment.ambient_light_energy = 1.1
	root.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.65
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-48, -35, 0)
	root.add_child(sun)
	var floor := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var ground_shape := BoxShape3D.new()
	ground_shape.size = Vector3(8, .3, 8)
	collider.shape = ground_shape
	collider.position.y = -.15
	floor.add_child(collider)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 8)
	ground.mesh = plane
	ground.material_override = StylizedEnvironmentMaterial.make_static(Color(.36, .39, .44), .96)
	floor.add_child(ground)
	root.add_child(floor)
	var player := PLAYER.instantiate() as Player
	root.add_child(player)
	player.position = Vector3(0, 1, 0)
	for _i: int in range(55):
		await process_frame
	var pack := player.animation_component.get_pack_rig() as PackRig
	var clip := pack.get_canvas().get_carabiner(0) as Carabiner
	var hang := clip.get_hang_point()
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	var err := gltf.append_from_file(PAN_PATH, state)
	if err != OK:
		push_error("Pan GLB import failed: %s" % err)
		quit(1)
		return
	var pan := gltf.generate_scene(state) as Node3D
	if pan == null:
		push_error("Pan GLB scene could not be generated")
		quit(1)
		return
	pan.name = "FryingPan_Preview"
	var turn := Basis(Vector3.BACK, PI * .5)
	## The pan hangs by its 24 x 17 mm eye; the 9 mm carabiner rod lies inside it.
	## Lower the eye slightly so its upper edge rests near the bottom of the rod.
	pan.transform = Transform3D(turn, -(turn * EYE_LOCAL) + Vector3.DOWN * .005)
	hang.add_child(pan)
	var adapted := StylizedEnvironmentMaterial.apply_to_tree(pan)
	if adapted == 0:
		push_error("Pan materials did not enter the Hoarbound NPR adapter")
		quit(1)
		return
	print("PAN_PREVIEW NPR materials=", adapted)
	for layer: Node in root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	for overlay: Node in root.find_children("*", "Control", true, false):
		(overlay as Control).visible = false
	for label: Node in root.find_children("*", "Label3D", true, false):
		(label as Label3D).visible = false
	_camera = Camera3D.new()
	_camera.fov = 38
	root.add_child(_camera)
	_camera.make_current()
	for _i: int in range(10):
		await process_frame
	var back := player.global_basis.z.normalized()
	var side := -player.global_basis.x.normalized()
	var eye := hang.to_global(Vector3.ZERO)
	var focus := eye + Vector3.DOWN * .11
	var fill := OmniLight3D.new()
	fill.light_color = Color(.78, .82, .91)
	fill.light_energy = 1.15
	fill.omni_range = 1.25
	fill.position = focus + back * .48 + side * .22 + Vector3.DOWN * .15
	root.add_child(fill)
	print("PAN_PREVIEW clip=", clip.global_position, " eye=", eye, " pan=", pan.global_position)
	_camera.look_at_from_position(focus + back * 1.65 + side * .48 + Vector3.UP * .32, focus)
	await _save("01_henry_back.png")
	_camera.look_at_from_position(focus + back * .76 + side * 1.20 + Vector3.UP * .20, focus)
	await _save("02_henry_side.png")
	var close_focus := eye + Vector3.DOWN * .17
	_camera.look_at_from_position(close_focus + back * .75 + side * .18 + Vector3.UP * .11, close_focus)
	await _save("03_carabiner_close.png")
	print("PAN_PREVIEW Forward+ frames=3")
	quit()


func _save(filename: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out).path_join(filename))
