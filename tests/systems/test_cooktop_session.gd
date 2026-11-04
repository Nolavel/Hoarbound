extends SceneTree

## F on either top plate owns the cooktop mode; F again restores on-foot and camera.
var failed: int = 0

func _initialize() -> void:
	call_deferred(&"_run")

func _run() -> void:
	var world := (load("res://scenes/world/first_exit/first_exit_blockout.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	var house := world.get_node(^"ShelterHouse/House") as Node3D
	var stove := house.get_node(^"ShelterZone/Stove") as HeatSource
	var mode := stove.get_node(^"CooktopInteraction") as CooktopInteractionController
	var a := stove.get_node(^"Warmer") as StoveWarmer
	var b := stove.get_node(^"Warmer2") as StoveWarmer
	var player := (load("res://scenes/actors/player/player.tscn") as PackedScene).instantiate() as Player
	root.add_child(player)
	var camera := (load("res://scenes/game/systems/camera/tps_camera.tscn") as PackedScene).instantiate() as TpsCamera
	camera.player = player
	root.add_child(camera)
	camera.set_process(false)
	camera.set_physics_process(false)
	camera.current = true
	await _frames(5)
	var pos := stove.to_global(CooktopInteractionController.STAND_OFFSET)
	pos.y = house.to_global(Vector3(0.0, 1.91, 0.0)).y
	player.global_position = pos
	player.velocity = Vector3.ZERO
	await _frames(3)
	_check(mode != null and a != null and b != null, "727 has no cooktop mode / two plates")
	if mode == null or a == null or b == null:
		quit(1)
		return
	mode.request_enter(a)
	_check(mode.get_phase() == CooktopInteractionController.Phase.WORKING, "F on first plate did not enter standing work mode")
	_check(not player.is_crouching(), "standing cooktop forced Henry to crouch")
	_check(root.get_node(^"InputSystems").call(&"is_interact_claimed"), "cooktop mode did not claim F")
	_check(camera._rig_work.lock_look, "cooktop camera is not fixed")
	_check(mode.get_ring() != null and mode.get_ring().is_shown(), "stove context ring was not shown")
	mode.select_plate(1)
	_check(mode.get_selected_warmer() == b, "RMB did not choose the other plate")
	mode.on_interact_claimed()
	_check(mode.get_phase() == CooktopInteractionController.Phase.OUTSIDE, "second F did not exit the cooktop")
	_check(not camera._rig_work.lock_look and not root.get_node(^"InputSystems").call(&"is_interact_claimed"), "cooktop did not restore camera/F")
	_check(root.get_node(^"PlayerState").call(&"is_on_foot"), "cooktop did not restore on-foot state")
	if failed == 0:
		print("COOKTOP_SESSION_PASS")
	else:
		print("COOKTOP_SESSION_FAILED %d" % failed)
	quit(1 if failed > 0 else 0)

func _frames(count: int) -> void:
	for i: int in range(count):
		await physics_frame

func _check(condition: bool, problem: String) -> void:
	if not condition:
		failed += 1
		push_error(problem)
