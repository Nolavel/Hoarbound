extends SceneTree

## Road flare at night in Key West Reality (#57 follow-up): the same frames with light
## variants, to judge the red pool against the cold dark. A = as shipped; B = fog tint 0.3;
## C = B + inverse-square falloff + steady radius. Outside on the snow by 727 and inside it.
## Run: xvfb-run godot --path . --rendering-driver vulkan --fixed-fps 30 --script res://tools/runtime/capture_flare_night.gd -- <out dir>

const SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"
const NIGHT_HOUR: float = 22.5
## [id, fog_energy, light_attenuation, range_breath]
const VARIANTS: Array = [
	["A_now", 1.0, 1.0, 1.0],
	["B_fog03", 0.3, 1.0, 1.0],
	["C_fog03_att2_steady", 0.3, 2.0, 0.0],
]

var _out: String = "user://shots/flare_night"
var _world: Node3D
var _player: Player


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
	_player = ctx.player as Player
	for weather: Node in _world.find_children("*", "WeatherController", true, false):
		weather.call(&"set_weather", &"calm", true)
	for node: Node in _world.find_children("*", "DayNightManager", true, false):
		node.set(&"total_game_time_hours", floorf(float(node.get(&"total_game_time_hours")) / 24.0) * 24.0 + NIGHT_HOUR)
		node.call(&"force_update_lighting")
		node.set_process(false)
	for layer: Node in root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	for label: Node in _world.find_children("*", "Label3D", true, false):
		(label as Node3D).visible = false
	var door := _world.find_children("HouseDoor", "", true, false)[0] as Node3D
	var out: Vector3 = door.global_basis.z
	out.y = 0.0
	out = out.normalized()
	var side: Vector3 = Vector3.UP.cross(out).normalized()

	var inventory := _player.get_node(^"InventoryComponent") as InventoryComponent
	inventory.try_add(load("res://data/items/road_flare.tres") as ItemResource)
	var held := _player.get_node(^"HeldLightComponent") as HeldLightComponent
	## Outside: Henry on open snow 7 m from the door, side-on to the camera.
	_player.global_position = door.global_position + out * 7.0 + Vector3.UP
	_player.look_at(_player.global_position + side, Vector3.UP)
	await _frames(60)
	print("[flare] lit=", held.light())
	await _frames(90)
	var henry: Vector3 = _player.global_position
	var flare: HeldFlare = held.get(&"_flare") as HeldFlare
	for v: Array in VARIANTS:
		_apply(flare, v)
		await _shot("out_" + String(v[0]), henry + out * 4.5 + side * 1.5 + Vector3.UP * 2.0, henry + Vector3.UP * 0.6, flare)
	## Close on the flare in Henry's hand, six frames apart, to see the jet and the spurts.
	_apply(flare, VARIANTS[2])
	var tip: Vector3 = (flare.get(&"_tip") as Node3D).global_position
	for i: int in range(6):
		await _shot("close_%d" % i, tip + out * 1.3 + side * 0.4 + Vector3.UP * 0.35, tip + Vector3.UP * 0.12, flare)
	## Inside 727, stove cold: the flare is the only light; framed across the room as the shadow capture.
	var stove := _world.find_children("*", "HeatSource", true, false)[0] as Node3D
	_player.global_position = stove.to_global(Vector3(1.4, 1.0, 0.6))
	await _frames(120)
	for v: Array in [VARIANTS[0], VARIANTS[2]]:
		_apply(flare, v)
		await _shot("in_" + String(v[0]), stove.to_global(Vector3(3.2, 1.7, 2.6)), stove.to_global(Vector3(1.3, 0.4, 0.5)), flare)
	print("[flare] done")
	quit(0)


func _apply(flare: HeldFlare, v: Array) -> void:
	flare.fog_energy = float(v[1])
	flare.light_attenuation = float(v[2])
	flare.range_breath = float(v[3])
	var light := flare.get(&"_light") as OmniLight3D
	light.light_volumetric_fog_energy = flare.fog_energy
	light.omni_attenuation = flare.light_attenuation


func _frames(count: int) -> void:
	for _i: int in range(count):
		await process_frame


func _shot(shot_name: String, from: Vector3, at: Vector3, flare: HeldFlare) -> void:
	var previous := root.get_camera_3d()
	var camera := Camera3D.new()
	camera.fov = 55.0
	root.add_child(camera)
	camera.look_at_from_position(from, at)
	camera.make_current()
	await _frames(12 if shot_name.begins_with("close") else 40)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out).path_join(shot_name + ".png"))
	var light := flare.get(&"_light") as OmniLight3D
	print("[flare] %s energy %.2f range %.2f fog %.2f att %.2f" % [shot_name, light.light_energy, light.omni_range, light.light_volumetric_fog_energy, light.omni_attenuation])
	camera.queue_free()
	if previous != null:
		previous.make_current()
