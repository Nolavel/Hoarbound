extends SceneTree

## Aiming a throw keeps Henry still (owner's play test: with a snowball in hand, RMB turned him round and round).
## He stood side-on to the hand's own throw line, which moves as he turns: with the aim near his feet it fed back
## and spun him. He now stands side-on to the camera's heading. Also no look_at() error from a near face target
## at Key West's large coordinates.
## Run: godot --headless --script tests/systems/test_throw_aim_facing.gd

const PLAYER: String = "res://scenes/actors/player/player.tscn"
const CAMERA: String = "res://scenes/game/systems/camera/tps_camera.tscn"
## Key West's coordinates, where look_at's tolerance is some 3 cm.
const AT: Vector3 = Vector3(-3533.0, 1.0, 1592.0)
## After the first second of aim, the facing may wander this much at most, degrees.
const STEADY_DEG: float = 2.0

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = AT - Vector3(0.0, 1.5, 0.0)
	root.add_child(floor_body)
	var player := (load(PLAYER) as PackedScene).instantiate() as Player
	root.add_child(player)
	player.global_position = AT
	var camera := (load(CAMERA) as PackedScene).instantiate() as TpsCamera
	camera.player = player
	root.add_child(camera)
	camera.make_current()
	for _i: int in 60:
		await physics_frame
	var equipment := player.get_node(^"EquipmentComponent") as EquipmentComponent
	var held := player.find_children("*", "HeldItemComponent", true, false)[0] as HeldItemComponent
	var throw := player.find_children("*", "ThrowComponent", true, false)[0] as ThrowComponent
	equipment.stow(&"legs_outer", &"thigh_right", &"snow_handful")
	_check(held.equip_from_zone(&"snow_handful", &"legs_outer/thigh_right"), "the snowball did not come to hand")
	for _i: int in 60:
		await process_frame
	for pitch: float in [-10.0, -45.0, -70.0]:
		var forward: Vector3 = -player.global_basis.z
		camera.set_look(atan2(-forward.x, -forward.z), pitch)
		camera.snap_to_target()
		throw._set_aiming(true)
		var yaws: Array[float] = []
		for k: int in 90:
			await process_frame
			if k >= 30:
				yaws.append(rad_to_deg(player.global_rotation.y))
		var wander: float = 0.0
		for yaw: float in yaws:
			wander = maxf(wander, absf(angle_difference(deg_to_rad(yaw), deg_to_rad(yaws[0]))))
		_check(rad_to_deg(wander) <= STEADY_DEG, "aiming %.0f degrees down, Henry turned %.0f degrees after the first second"
			% [-pitch, rad_to_deg(wander)])
		print("throw aim facing: %.0f degrees down, %.1f degrees of turn after the first second" % [-pitch, rad_to_deg(wander)])
		throw._set_aiming(false)
		for _i: int in 30:
			await process_frame
	var before: Basis = player.global_basis
	player.face_work_target(player.global_position + Vector3(0.02, 0.0, 0.0))
	_check(player.global_basis.is_equal_approx(before), "a face target 2 cm away still turned him")
	if _failures > 0:
		push_error("throw aim facing: %d check(s) failed" % _failures)
		quit(1)
		return
	print("throw aim facing: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("throw aim facing: " + message)
