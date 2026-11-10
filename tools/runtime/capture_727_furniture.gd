extends SceneTree

## Stills of the searchable furniture in the 727 shelter (FurnitureKit kinds in the real shell): two views of the
## waiting room with every way in open (full ones frosted), then the working frame of each one holding something.
## Run: xvfb-run godot --path . --rendering-driver vulkan --fixed-fps 30 --resolution 1920x1080 --script res://tools/runtime/capture_727_furniture.gd -- <out dir>

const SHELL: String = "res://assets/world/key_west/landmarks/kw_727_fort_st.glb"
const PLAYER: String = "res://scenes/actors/player/player.tscn"
## [container key, file name, ways in].
const SEARCHED: Array = [
	["KitchenCupboard", "cupboard", ["KitchenCupboard/left", "KitchenCupboard/right"]],
	["Dresser/top", "dresser_top", ["Dresser/top"]],
	["Dresser/middle", "dresser_middle", ["Dresser/middle"]],
	["Chest", "chest", ["Chest/lid"]],
]

var _out: String = "user://shots/727_furniture"


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	call_deferred(&"_run")


func _run() -> void:
	TranslationServer.set_locale("ru")
	var shelter := KeyWest727Shelter.new()
	shelter.build()
	root.add_child(shelter)
	var shell := (load(SHELL) as PackedScene).instantiate() as Node3D
	shell.position = shelter.position
	root.add_child(shell)
	var house := shelter.get_node(^"House") as Node3D
	var floor_y: float = float(shelter.interior["floor_y"])
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.7, 0.74, 0.8)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.56, 0.6)
	root.add_child(env)
	for at: Vector2 in [Vector2(-2.5, 2.5), Vector2(1.5, 5.0)]:
		var lamp := OmniLight3D.new()
		lamp.omni_range = 8.0
		lamp.light_energy = 1.6
		house.add_child(lamp)
		lamp.position = Vector3(at.x, floor_y + 2.6, at.y)
	var player := (load(PLAYER) as PackedScene).instantiate() as Player
	root.add_child(player)
	player.global_position = house.global_transform * Vector3(-0.5, floor_y + 0.05, 6.0)
	var camera := Camera3D.new()
	camera.fov = 60.0
	root.add_child(camera)
	camera.make_current()
	await _frames(30)
	for way: InteractiveArea in shelter.furniture_openers.values():
		way.interact()
	await _frames(45)
	## The waiting room's south-west corner (cupboard, dresser), then its east side (chest).
	camera.global_transform = house.global_transform * Transform3D(Basis.IDENTITY, Vector3(-1.2, floor_y + 1.9, 4.6)).looking_at(Vector3(-4.6, floor_y + 0.9, 0.9), Vector3.UP)
	await _frames(8)
	await _save("room_corner.png")
	camera.global_transform = house.global_transform * Transform3D(Basis.IDENTITY, Vector3(-0.6, floor_y + 1.8, 3.0)).looking_at(Vector3(3.1, floor_y + 0.4, 4.4), Vector3.UP)
	await _frames(8)
	await _save("room_chest.png")
	for way: InteractiveArea in shelter.furniture_openers.values():
		way.interact()
	await _frames(45)
	var hub := player.get_node(^"PlayerHubComponent") as PlayerHubComponent
	for entry: Array in SEARCHED:
		var shelves: ItemContainer = shelter.furniture_containers[entry[0]]
		var face: Array = shelves.front()
		var stand: Vector3 = (face[0] as Vector3) + (face[1] as Vector3) * 0.9
		stand.y = shelter.global_position.y + floor_y + 0.05
		player.global_position = stand
		player.velocity = Vector3.ZERO
		player.face_work_target(face[0])
		for way: String in entry[2]:
			(shelter.furniture_openers[way] as InteractiveArea).interact()
		await _frames(45)
		(shelves.get_node(^"Search") as ContainerSearch).interact()
		for _i: int in 150:
			var hands: PackHandling = hub.get_pack_hands()
			if hands != null and hands.enabled:
				break
			await _frames(1)
		await _frames(45)
		await _save("framed_%s.png" % entry[1])
		print("[727] framed ", entry[0])
		hub.close()
		await _frames(45)
		for way: String in entry[2]:
			(shelter.furniture_openers[way] as InteractiveArea).interact()
		await _frames(45)
		camera.make_current()
	quit()


func _save(file: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out).path_join(file))


func _frames(count: int) -> void:
	for _i: int in count:
		await process_frame
