extends SceneTree

## Camera stability against interaction targets, on the real shelter with the
## production TPS camera running. Pickup attention must cause zero framing motion;
## a slow sweep across the stove must not oscillate between targets or shoulders.
## Run: godot --headless --script tests/systems/test_interaction_framing.gd

const SWEEP_FRAMES: int = 150
const TOOL_NAMES: Array[String] = ["HammerShelter", "NailsShelter", "LighterShelterTest", "KnifeShelterTest", "AxeShelterTest"]

var _failures: int = 0
var _scene: Node3D
var _house: Node3D
var _player: Player
var _camera: TpsCamera
var _interact: InteractComponent


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_scene = (load("res://scenes/world/first_exit/first_exit_blockout.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	_house = _scene.get_node(^"ShelterHouse/House") as Node3D
	_player = (load("res://scenes/actors/player/player.tscn") as PackedScene).instantiate() as Player
	root.add_child(_player)
	_interact = _player.get_node(^"InteractComponent") as InteractComponent
	_camera = (load("res://scenes/game/systems/camera/tps_camera.tscn") as PackedScene).instantiate() as TpsCamera
	_camera.player = _player
	root.add_child(_camera)
	_camera.current = true
	await _frames(4)
	await _check_pickup_sweep_moves_no_camera()
	await _check_stove_sweep_is_stable()
	print("test_interaction_framing: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)


## Henry before the tool bench; the view sweeps A -> E -> B over five close tools.
func _check_pickup_sweep_moves_no_camera() -> void:
	var tools: Array[Node3D] = []
	var centre := Vector3.ZERO
	for tool_name: String in TOOL_NAMES:
		var tool := _scene.get_node(NodePath(tool_name)) as Node3D
		tools.append(tool)
		centre += tool.global_position
	centre /= float(tools.size())
	var stand: Vector3 = centre - _house.global_basis.z * 0.0 + (Vector3(1133.2, 0.0, -655.6) - Vector3(centre.x, 0.0, centre.z))
	await _place(Vector3(stand.x, centre.y + 0.25, stand.z), centre)
	var base_yaw: float = _camera.get_yaw()
	var visited: Dictionary = {}
	var max_weight: float = 0.0
	var max_goal: float = 0.0
	var world_seen: int = 0
	var switches: int = 0
	var last: InteractiveArea = null
	for leg: Vector2 in [Vector2(35.0, -35.0), Vector2(-35.0, 15.0)]:
		for i: int in range(SWEEP_FRAMES):
			var t: float = float(i) / float(SWEEP_FRAMES - 1)
			_camera.set_look(base_yaw + deg_to_rad(lerpf(leg.x, leg.y, t)), -32.0)
			await physics_frame
			var pickup: InteractiveArea = _interact.get_pickup_target()
			if pickup != null:
				visited[pickup] = true
			if pickup != last:
				switches += 1
				last = pickup
			if _interact.get_world_target() != null:
				world_seen += 1
			max_weight = maxf(max_weight, _camera._shoulder.get_interaction_weight())
			max_goal = maxf(max_goal, _camera._shoulder._interaction_weight_goal)
	print("framing trace: pickup sweep visited %d tools, %d switches, world frames %d, max weight %.4f" % [visited.size(), switches, world_seen, max_weight])
	_check(visited.size() >= 3, "the sweep did not move the dominant pickup across the bench (%d)" % visited.size())
	_check(max_weight == 0.0 and max_goal == 0.0, "pickup attention moved the camera shoulder (weight %.4f)" % max_weight)
	_check(switches <= visited.size() * 2 + 2, "the dominant pickup flickered: %d switches over %d tools" % [switches, visited.size()])


## A slow one-way sweep across the stove: the world target enters and leaves once,
## and the framing shoulder side never flips back and forth.
func _check_stove_sweep_is_stable() -> void:
	var feed: HeatSourceFeed = _house.get_node(^"ShelterZone/Stove/Feed") as HeatSourceFeed
	var source: Node3D = feed.heat_source
	var focus: Vector3 = feed.focus_anchor.global_position
	await _place(source.to_global(Vector3(1.2, 0.9, 0.0)), focus)
	## Centre the sweep on the stove's focus as seen from the real aim origin.
	var to_focus: Vector3 = (focus - TpsCamera.aim_origin(_camera)).normalized()
	var base_yaw: float = atan2(-to_focus.x, -to_focus.z)
	var pitch: float = rad_to_deg(asin(to_focus.y))
	for leg: Vector2 in [Vector2(60.0, -60.0), Vector2(-60.0, 60.0)]:
		var sequence: Array[InteractiveArea] = []
		var sides: Array[float] = []
		var aba: int = 0
		var aim_min: float = INF
		var aim_max: float = 0.0
		for i: int in range(SWEEP_FRAMES):
			var t: float = float(i) / float(SWEEP_FRAMES - 1)
			_camera.set_look(base_yaw + deg_to_rad(lerpf(leg.x, leg.y, t)), pitch)
			await physics_frame
			var world: InteractiveArea = _interact.get_world_target()
			var off: float = rad_to_deg(TpsCamera.aim_direction(_camera).angle_to(focus - TpsCamera.aim_origin(_camera)))
			aim_min = minf(aim_min, off)
			aim_max = maxf(aim_max, off)
			if sequence.is_empty() or sequence[-1] != world:
				## Entering and leaving once is fine; meeting a target again is oscillation.
				if world != null and sequence.has(world):
					aba += 1
				sequence.append(world)
			var goal: float = _camera._shoulder._interaction_goal if _camera._shoulder._interaction_weight_goal > 0.0 else 0.0
			if not is_zero_approx(goal) and (sides.is_empty() or signf(sides[-1]) != signf(goal)):
				sides.append(goal)
		print("framing trace: stove sweep %s -> %s: aim off the stove %.1f..%.1f deg, targets %s, shoulder sides %s, ABA %d"
			% [leg.x, leg.y, aim_min, aim_max, sequence.map(func(a: Variant) -> String: return "-" if a == null else str((a as Node).name)), sides, aba])
		var exit_cone: float = _interact.world_aim_cone_deg * _interact.world_exit_scale
		_check(aim_max > exit_cone, "the sweep never left the stove's exit cone (max %.1f deg)" % aim_max)
		_check(aba == 0, "the world target oscillated during a one-way sweep (%d re-entries)" % aba)
		_check(sides.size() <= 2, "the framing shoulder flipped %d times in one sweep" % sides.size())
		_check(sequence.has(feed) or sequence.any(func(a: Variant) -> bool: return a is StoveDoorControl),
			"the sweep never selected the stove")


func _place(at: Vector3, look_point: Vector3) -> void:
	_player.global_position = at
	_player.velocity = Vector3.ZERO
	var flat := Vector3(look_point.x, at.y, look_point.z)
	if at.distance_to(flat) > 0.01:
		_player.look_at(flat, Vector3.UP)
	_player.reset_physics_interpolation()
	_camera.set_look(_player.global_rotation.y, -25.0)
	await _frames(30)


func _frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("interaction framing: " + message)
