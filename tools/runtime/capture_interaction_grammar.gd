extends SceneTree

## One consolidated proof of the interaction grammar in the real First Exit shelter:
## head attention moves [F] across the tool bench with the camera shoulder still,
## the stove's central prompt wins F over a tin beside it, a deep bench tin is
## approached and taken, a fenced tin is noticed but never promised, and a rare
## flare carries the check mark. Run under Movie Maker for frames:
##   godot --path . --write-movie <dir>/f.png --fixed-fps 10 --resolution 960x540 \
##     --script res://tools/runtime/capture_interaction_grammar.gd

const BLOCKOUT: String = "res://scenes/world/first_exit/first_exit_blockout.tscn"
const PLAYER: String = "res://scenes/actors/player/player.tscn"
const CAMERA: String = "res://scenes/game/systems/camera/tps_camera.tscn"
const AREA_SCENE: String = "res://scenes/environment/interactive/InteractiveArea.tscn"
const PICKUP_SCRIPT: String = "res://scripts/environment/interactive/item_pickup.gd"
const FPS: int = 10

var _scene: Node3D
var _house: Node3D
var _player: Player
var _camera: TpsCamera
var _interact: InteractComponent
var _caption: Label
var _status: Label
var _report: Array[String] = []
var _max_pickup_weight: float = 0.0
var _segment: String = ""


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_build_world()
	await _seconds(1.0)
	await _dense_tools()
	await _stove_wins_f()
	await _deep_bench_tin()
	await _fenced_tin()
	for line: String in _report:
		print("[InteractionGrammarCapture] " + line)
	print("[InteractionGrammarCapture] max shoulder override weight in pickup-only segments 1, 3, 4: %.4f" % _max_pickup_weight)
	quit(0)


func _build_world() -> void:
	_scene = (load(BLOCKOUT) as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	_house = _scene.get_node(^"ShelterHouse/House") as Node3D
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, -40.0, 0.0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var lamp := OmniLight3D.new()
	lamp.omni_range = 9.0
	lamp.light_energy = 1.6
	root.add_child(lamp)
	lamp.global_position = _local(Vector3(0.5, 2.6, 0.5))
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.66, 0.7)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.57, 0.6)
	env.ambient_light_energy = 0.9
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)
	_player = (load(PLAYER) as PackedScene).instantiate() as Player
	root.add_child(_player)
	_interact = _player.get_node(^"InteractComponent") as InteractComponent
	_camera = (load(CAMERA) as PackedScene).instantiate() as TpsCamera
	_camera.player = _player
	root.add_child(_camera)
	_camera.current = true
	var rare: ItemPickup = _spawn(&"road_flare", _local(Vector3(-1.4, 0.93, 3.6)))
	rare.special_awareness = true
	rare.add_to_group(InteractiveArea.AWARENESS_GROUP)
	var layer := CanvasLayer.new()
	layer.layer = 50
	root.add_child(layer)
	_caption = _label(layer, Vector2(16.0, 12.0), 22)
	_status = _label(layer, Vector2(16.0, 44.0), 15)


## Five close tools; the view sweeps A -> B -> C -> D -> C -> B and Henry's head follows.
func _dense_tools() -> void:
	_segment = "1  Dense tools: Henry's head picks, [F] follows, camera shoulder stays still"
	await _place(_local(Vector3(2.0, 0.91, 0.32)), _local(Vector3(2.0, 1.71, 1.2)))
	var order: Array[String] = ["HammerShelter", "KnifeShelterTest", "NailsShelter", "AxeShelterTest", "NailsShelter", "KnifeShelterTest"]
	var points: Array[Vector3] = []
	for tool_name: String in order:
		points.append((_scene.get_node(NodePath(tool_name)) as InteractiveArea).get_focus_point(_player.global_position))
	var seen: Array[String] = []
	for i: int in range(points.size() - 1):
		for step: int in range(FPS * 2):
			_aim_at(points[i].lerp(points[i + 1], float(step) / float(FPS * 2)))
			await _frame(true)
			var pickup: InteractiveArea = _interact.get_pickup_target()
			if pickup != null and (seen.is_empty() or seen[-1] != String(pickup.name)):
				seen.append(String(pickup.name))
	_report.append("dense tools dominant sequence: %s" % " -> ".join(seen))


## The view on the stove gives the central prompt and F; on the tin beside it, [F] returns.
func _stove_wins_f() -> void:
	_segment = "2  World wins F: stove under the view -> central prompt; pickup [F] hidden"
	var feed: HeatSourceFeed = _house.get_node(^"ShelterZone/Stove/Feed") as HeatSourceFeed
	var source: Node3D = feed.heat_source
	var stand: Vector3 = source.to_global(Vector3(1.2, 0.9, 0.0))
	var tin: ItemPickup = _spawn(&"tinned_stew", source.to_global(Vector3(1.3, 0.03, -0.75)))
	await _place(stand, feed.focus_anchor.global_position)
	for _i: int in range(FPS * 3):
		_aim_at(feed.focus_anchor.global_position)
		await _frame(false)
	_report.append("stove under view: world=%s pickup=%s pickup_actionable=%s" % [
		_name(_interact.get_world_target()), _name(_interact.get_pickup_target()), _interact.is_pickup_actionable()])
	_segment = "2  View leaves the stove: prompt closes, [F] returns on the tin"
	## The stove's own framing fades out here; that is world framing, so it is not counted.
	var fade_start: float = _camera._shoulder.get_interaction_weight()
	for step: int in range(FPS * 3):
		_aim_at(feed.focus_anchor.global_position.lerp(tin.get_focus_point(_player.global_position), minf(1.0, float(step) / float(FPS))))
		await _frame(false)
	_report.append("stove framing weight %.3f faded to %.3f after the view left it" % [fade_start, _camera._shoulder.get_interaction_weight()])
	_report.append("tin under view: world=%s pickup=%s pickup_actionable=%s" % [
		_name(_interact.get_world_target()), _name(_interact.get_pickup_target()), _interact.is_pickup_actionable()])
	tin.queue_free()


## A tin 0.28 m behind the supply bench edge: F walks Henry to the edge, then takes it.
func _deep_bench_tin() -> void:
	_segment = "3  Deep bench tin: [F] only with a valid spot; F -> straight walk -> take"
	var tin: ItemPickup = _spawn(&"tinned_stew", _local(Vector3(1.55, 1.71, -0.76)))
	await _place(_local(Vector3(0.1, 0.91, 0.55)), tin.global_position)
	for _i: int in range(FPS * 2):
		_aim_at(tin.get_focus_point(_player.global_position))
		await _frame(true)
	var affordance: PickupAffordance = _interact.get_pickup_affordance()
	_report.append("deep tin: actionable=%s valid=%s in_place=%s spot=%s" % [_interact.is_pickup_actionable(),
		affordance != null and affordance.valid, affordance != null and affordance.in_place,
		_house.to_local(affordance.body_position) if affordance != null and affordance.valid else Vector3.ZERO])
	_press(&"interact")
	var taken: bool = false
	for _i: int in range(FPS * 6):
		if is_instance_valid(tin) and not tin.is_queued_for_deletion():
			_aim_at(tin.get_focus_point(_player.global_position))
		else:
			taken = true
		await _frame(true)
	_report.append("deep tin taken: %s, Henry ended at %s" % [taken, _house.to_local(_player.global_position)])


## A tin fenced in by crates: Henry notices it, the game never promises [F].
func _fenced_tin() -> void:
	_segment = "4  Fenced tin: noticed (dot), no valid spot, no [F].  Far flare: special awareness check mark"
	var centre: Vector3 = _local(Vector3(0.6, 0.91, 3.1))
	for offset: Vector3 in [Vector3(0.55, 0.0, 0.0), Vector3(-0.55, 0.0, 0.0), Vector3(0.0, 0.0, 0.55), Vector3(0.0, 0.0, -0.55)]:
		var crate := CSGBox3D.new()
		crate.use_collision = true
		## Low enough for Henry to see over, too tight for his capsule to step into.
		crate.size = Vector3(0.2, 0.5, 1.3) if offset.x != 0.0 else Vector3(1.3, 0.5, 0.2)
		root.add_child(crate)
		crate.global_position = centre + _house.global_basis * offset + Vector3.UP * 0.25
	var tin: ItemPickup = _spawn(&"tinned_stew", centre + Vector3.UP * 0.02)
	await _place(_local(Vector3(0.6, 0.91, 1.75)), tin.global_position)
	for _i: int in range(FPS * 4):
		_aim_at(tin.get_focus_point(_player.global_position))
		await _frame(true)
	var affordance: PickupAffordance = _interact.get_pickup_affordance()
	_report.append("fenced tin: pickup=%s actionable=%s reason=%s" % [_name(_interact.get_pickup_target()),
		_interact.is_pickup_actionable(), affordance.reason if affordance != null else &"none"])
	var flare := _scene.get_tree().get_first_node_in_group(InteractiveArea.AWARENESS_GROUP) as InteractiveArea
	_report.append("special flare marker: %s" % InteractiveArea.MarkerState.keys()[flare.get_marker_state()] if flare != null else "special flare missing")


func _place(at: Vector3, look_point: Vector3) -> void:
	_player.global_position = at + Vector3.UP * 1.0
	_player.velocity = Vector3.ZERO
	var flat := Vector3(look_point.x, _player.global_position.y, look_point.z)
	_player.look_at(flat, Vector3.UP)
	_player.reset_physics_interpolation()
	_aim_at(look_point)
	for _i: int in range(FPS):
		_aim_at(look_point)
		await _frame(false)


## Turns the production camera so its gameplay aim ray passes through a point.
func _aim_at(point: Vector3) -> void:
	var to_point: Vector3 = (point - TpsCamera.aim_origin(_camera)).normalized()
	_camera.set_look(atan2(-to_point.x, -to_point.z), rad_to_deg(asin(clampf(to_point.y, -1.0, 1.0))))


func _frame(pickup_segment: bool) -> void:
	await process_frame
	if pickup_segment and _interact.get_world_target() == null:
		_max_pickup_weight = maxf(_max_pickup_weight, _camera._shoulder.get_interaction_weight())
	_caption.text = _segment
	_status.text = "pickup: %s   [F] shown: %s   committed: %s\nworld: %s   central prompt: %s\nshoulder override weight: %.3f" % [
		_name(_interact.get_pickup_target()), _interact.is_pickup_actionable() or _interact.get_committed_target() != null,
		_name(_interact.get_committed_target()), _name(_interact.get_world_target()),
		_interact.get_world_target() != null and _interact.get_world_target().prompt_shown,
		_camera._shoulder.get_interaction_weight()]


func _seconds(seconds: float) -> void:
	for _i: int in range(int(seconds * FPS)):
		await _frame(false)


func _press(action: StringName) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)


func _spawn(item_id: StringName, at: Vector3) -> ItemPickup:
	var area: Node = (load(AREA_SCENE) as PackedScene).instantiate()
	area.set_script(load(PICKUP_SCRIPT))
	var pickup := area as ItemPickup
	pickup.item_id = item_id
	pickup.position = at
	root.add_child(pickup)
	return pickup


func _local(point: Vector3) -> Vector3:
	return _house.to_global(point)


func _name(area: InteractiveArea) -> String:
	return "-" if area == null else String(area.name)


func _label(layer: CanvasLayer, at: Vector2, size: int) -> Label:
	var label := Label.new()
	label.position = at
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", Color(1.0, 0.97, 0.9))
	label.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0))
	label.add_theme_constant_override(&"outline_size", 6)
	layer.add_child(label)
	return label
