extends SceneTree

## The stove ritual on the real shelter, real player (physics on) and real input: F walks Henry to
## the stove, opens it and crouches him; RMB loads one log, LMB lays tinder, a new LMB press works
## the lighter; F closes it. Run: godot --headless --script tests/systems/test_stove_ritual.gd

var _failures: int = 0
var _scene: Node3D
var _house: Node3D
var _player: Player
var _camera: TpsCamera
var _interact: InteractComponent
var _inventory: InventoryComponent
var _clock: SimulationClock
var _actions: TimeCostedActionSystem
var _feed: HeatSourceFeed
var _source: HeatSource
var _control: StoveInteractionController
var _state: Node


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_clock = SimulationClock.new()
	root.add_child(_clock)
	_clock.set_total_hours(12.0, &"test_seed")
	_actions = TimeCostedActionSystem.new()
	_actions.simulation_clock = _clock
	root.add_child(_actions)
	_scene = (load("res://scenes/world/first_exit/first_exit_blockout.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	_house = _scene.get_node(^"ShelterHouse/House") as Node3D
	_player = (load("res://scenes/actors/player/player.tscn") as PackedScene).instantiate() as Player
	root.add_child(_player)
	_interact = _player.get_node(^"InteractComponent") as InteractComponent
	_inventory = _player.get_node(^"InventoryComponent") as InventoryComponent
	_camera = (load("res://scenes/game/systems/camera/tps_camera.tscn") as PackedScene).instantiate() as TpsCamera
	_camera.player = _player
	root.add_child(_camera)
	_camera.set_process(false)
	_camera.set_physics_process(false)
	_camera.current = true
	_state = root.get_node(^"PlayerState")
	_feed = _house.get_node(^"ShelterZone/Stove/Feed") as HeatSourceFeed
	_source = _feed.heat_source
	_control = _feed.controller
	await _frames(3)
	_check(_control != null and _control.get_interaction_point() != null, "the stove has no interaction controller or point")
	_check(_control.get_interaction_point().get_parent() == _source, "the work spot is not in stove space")
	await _test_unreachable()
	await _test_entry_without_autoload()
	await _test_tinder_needs_fuel()
	await _test_one_log_per_press()
	await _test_tinder_and_long_press()
	await _test_fuel_after_tinder()
	await _test_held_tinder_cancel()
	await _test_conflicts_while_working()
	await _test_exit_and_return()
	await _test_save_round_trip()
	await _test_lighter()
	await _test_burning_refuel()
	await _test_quick_f_and_target_loss()
	print("test_stove_ritual: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)


## A crate on the work spot: F refuses and Henry does not enter the mode.
func _test_unreachable() -> void:
	_place_henry_before_stove(2.2)
	var blocker := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 1.2, 0.5)
	shape.shape = box
	blocker.add_child(shape)
	root.add_child(blocker)
	blocker.global_position = _control.get_interaction_point().global_position + Vector3.UP * 0.4
	await _frames(2)
	_control.request_enter()
	_check(_control.get_phase() == StoveInteractionController.Phase.OUTSIDE, "a blocked spot still started the ritual")
	_check(_state.call(&"is_on_foot"), "a refused ritual left Henry rooted")
	blocker.queue_free()
	await _frames(2)


## Test 1 and 2: F from the room walks over (no teleport), opens, crouches; carried logs survive.
func _test_entry_without_autoload() -> void:
	_add(&"firewood", 3)
	_inventory.try_add(ItemCatalog.get_item(&"lighter"))
	_check(_inventory.get_count(&"firewood") == 3, "fixture: three logs did not enter the hands")
	await _place_and_aim(2.2)
	var start: Vector3 = _player.global_position
	_press(&"interact")
	await _frames(2)
	_check(_control.get_phase() != StoveInteractionController.Phase.OUTSIDE or _interact._pending != null,
		"F on the stove did not start the ritual")
	_check(_player.global_position.distance_to(start) < 0.3, "Henry jumped to the stove instead of walking")
	var travelled: float = 0.0
	var last: Vector3 = _player.global_position
	for _i: int in range(600):
		await physics_frame
		travelled += _player.global_position.distance_to(last)
		last = _player.global_position
		if _control.is_working():
			break
	_check(_control.is_working(), "Henry never reached the working pose (phase %d)" % _control.get_phase())
	_check(travelled > 0.8, "Henry reached the stove without walking: %.2f m" % travelled)
	var spot: Vector3 = _control.get_interaction_point().global_position
	_check(Vector2(spot.x - _player.global_position.x, spot.z - _player.global_position.z).length() < 0.25,
		"Henry stopped off the work spot")
	_check(_control.is_facing_door(), "Henry does not face the stove door")
	_check(_feed.is_door_open(), "the door did not open")
	_check(_player.is_crouching(), "Henry did not crouch at the stove")
	_check(_control.get_ring() != null and _control.get_ring().is_shown(), "the three-arc ring did not appear")
	_check(_source.get_loaded_log_count() == 0 and _inventory.get_count(&"firewood") == 3, "entering loaded fuel by itself")
	_check(not _source.is_burning(), "entering lit the stove")
	_check(_state.call(&"is_movement_blocked"), "WASD still moves Henry at the stove")
	var visual: HenryUALAnimation = _player.animation_component
	await _frames(30)
	_check(visual.is_carrying(), "crouching dropped the carried logs")
	var playback := visual.animation_tree.get("parameters/base/playback") as AnimationNodeStateMachinePlayback
	_check(playback.get_current_node() == &"CrouchCarry", "crouched with logs is not the carry crouch: %s" % playback.get_current_node())
	await _check_work_framing()


## Test 4: an empty firebox takes no tinder; the fuel arc says why.
func _test_tinder_needs_fuel() -> void:
	var equipment := _player.get_node(^"EquipmentComponent") as EquipmentComponent
	for pocket: Dictionary in equipment.get_available_pockets():
		if pocket["item_id"] == &"tinder":
			var item: StringName = equipment.take_from_pocket(pocket["body_slot"],pocket["pocket"])
			_add(item,1)
	_add(&"tinder", 2)
	var tinder: int = _tinder_count()
	_mouse(MOUSE_BUTTON_LEFT, true)
	_mouse(MOUSE_BUTTON_LEFT, false)
	await _frames(2)
	_check(_tinder_count() == tinder and not _source.is_tinder_prepared(), "tinder went into an empty firebox")
	_check(_control.get_ring().get_refusal_left(StoveInteractionRing.Arc.FUEL) > 0.0, "the fuel arc gave no feedback for an empty firebox")


## Test 3: one RMB press, one log; a held RMB loads no more; presses during the act are ignored.
func _test_one_log_per_press() -> void:
	_mouse(MOUSE_BUTTON_RIGHT,true)
	_mouse(MOUSE_BUTTON_RIGHT,false)
	await _frames(10)
	_feed.set_door_open(false)
	await _frames(20)
	_check(_inventory.get_count(&"firewood") == 3 and _source.get_loaded_log_count() == 0,"closing before contact lost/duplicated a log")
	_feed.set_door_open(true)
	await _frames(25)
	var saved_fire: Dictionary = _source.get_fire_save_data()
	var saved_inventory: Dictionary = _inventory.get_save_data()
	_check(_feed.insert_fuel() == HeatSourceFeed.Refusal.NONE,"load test could not start transfer")
	await _frames(10)
	_source.restore_fire_save_data(saved_fire)
	_inventory.load_save_data(saved_inventory)
	await _frames(80)
	_check(not _control.is_active() and _feed.get_act() == HeatSourceFeed.Act.NONE,"load left a pending stove action")
	_check(_inventory.get_count(&"firewood") == 3 and _source.get_loaded_log_count() == 0,"load consumed or duplicated a pending log")
	_control.request_enter()
	for _i: int in range(240):
		await physics_frame
		if _control.is_working():
			break
	_check(_control.is_working(),"cannot reenter after loading")
	_mouse(MOUSE_BUTTON_RIGHT, true)
	await _frames(2)
	_check(_feed.get_act() == HeatSourceFeed.Act.FUEL, "RMB did not start laying a log")
	_mouse(MOUSE_BUTTON_RIGHT, true)
	_check(_inventory.get_count(&"firewood") == 3, "a log left the hands before it was laid")
	for _i: int in range(220):
		await physics_frame
		if _feed.did_commit_transfer():
			break
	_check(_feed.did_commit_transfer(),"the contact transaction never happened")
	_feed.cancel_act(&"test_after_contact")
	_check(_inventory.get_count(&"firewood") == 2 and _source.get_loaded_log_count() == 1,
		"one press moved %d logs" % (3 - _inventory.get_count(&"firewood")))
	_check(not _source.is_burning(), "a cold log lit the stove")
	var fuel: Dictionary = _control.get_ring().describe(StoveInteractionRing.Arc.FUEL)
	_check(int(fuel["loaded"]) == 1 and int(fuel["ticks"]) == _source.get_log_capacity(), "the fuel arc does not show 1/%d" % _source.get_log_capacity())
	await _frames(int(HeatSourceFeed.FUEL_SECONDS * 60.0) + 20)
	_check(_source.get_loaded_log_count() == 1, "holding RMB kept loading logs")
	_mouse(MOUSE_BUTTON_RIGHT, false)


## Test 5 and 6: LMB lays tinder, lights nothing, and a held LMB never reaches the lighter.
func _test_tinder_and_long_press() -> void:
	_check(_feed.get_tinder_refusal() == HeatSourceFeed.Refusal.NO_TINDER,"backpack tinder enables the act")
	_check(_control.get_ring().describe(StoveInteractionRing.Arc.TINDER)["state"] == StoveInteractionRing.ArcState.INACTIVE,"backpack tinder lights its arc")
	_mouse(MOUSE_BUTTON_LEFT,true)
	_mouse(MOUSE_BUTTON_LEFT,false)
	await _frames(3)
	_check(not _feed.is_acting(),"backpack tinder started an action")
	var equipment := _player.get_node(^"EquipmentComponent") as EquipmentComponent
	for pocket: Dictionary in equipment.get_available_pockets():
		if equipment.can_stow(pocket["body_slot"],pocket["pocket"],&"tinder") == EquipmentComponent.Refusal.NONE:
			_check(_inventory.try_remove(&"tinder"),"no tinder to move to pocket")
			_check(equipment.stow(pocket["body_slot"],pocket["pocket"],&"tinder") == EquipmentComponent.Refusal.NONE,"pocket refused tinder")
			break
	_check(_feed.get_tinder_refusal() == HeatSourceFeed.Refusal.NONE,"pocket tinder is unavailable")
	var tinder: int = _tinder_count()
	_mouse(MOUSE_BUTTON_LEFT, true)
	await _wait_act()
	_check(_source.is_tinder_prepared() and _tinder_count() == tinder - 1, "LMB did not lay exactly one tinder")
	_check(not _source.is_burning(), "laying tinder lit the stove")
	_check(_control.get_ring().describe(StoveInteractionRing.Arc.TINDER)["state"] == StoveInteractionRing.ArcState.DONE, "the tinder arc did not fill")
	await _frames(int(HeatSourceFeed.LIGHT_SECONDS * 60.0) + 30)
	_check(not _source.is_burning() and _feed.get_stage() == HeatSourceFeed.Stage.IDLE,
		"one long LMB press went on to the lighter")
	_mouse(MOUSE_BUTTON_LEFT, false)
	await _frames(3)
	_check(_feed.get_act() == HeatSourceFeed.Act.LIGHT, "the lighter was not readied after the release")


## Test 8: a log after the tinder keeps the tinder.
func _test_fuel_after_tinder() -> void:
	_mouse(MOUSE_BUTTON_RIGHT, true)
	_mouse(MOUSE_BUTTON_RIGHT, false)
	await _wait_act()
	_check(_source.get_loaded_log_count() == 2 and _source.is_tinder_prepared(), "a log after the tinder lost it")
	_mouse(MOUSE_BUTTON_RIGHT, true)
	_mouse(MOUSE_BUTTON_RIGHT, false)
	await _wait_act()
	_check(_source.get_loaded_log_count() == 3, "the third log did not go in")


## Test 12 (working): a full firebox, pause, a missing lighter, a log lost mid-act.
func _test_conflicts_while_working() -> void:
	_add(&"firewood", 1)
	var held: int = _inventory.get_count(&"firewood")
	_mouse(MOUSE_BUTTON_RIGHT, true)
	_mouse(MOUSE_BUTTON_RIGHT, false)
	await _frames(2)
	_check(_inventory.get_count(&"firewood") == held and _control.get_ring().get_refusal_left(StoveInteractionRing.Arc.FUEL) > 0.0,
		"a full firebox spent a log or gave no feedback")
	_state.call(&"open_menu")
	_mouse(MOUSE_BUTTON_LEFT, true)
	_mouse(MOUSE_BUTTON_LEFT, false)
	_check(_feed.get_stage() != HeatSourceFeed.Stage.HOLDING, "a paused game struck the lighter")
	_state.call(&"close_menu")
	await _frames(2)
	_check(_control.is_working(), "closing the menu dropped the ritual")
	var lighters: int = _take_owned(&"lighter")
	await _frames(3)
	_check(_feed.get_lighter_refusal() == HeatSourceFeed.Refusal.NO_LIGHTER, "the lighter is still offered without one")
	_mouse(MOUSE_BUTTON_LEFT, true)
	_mouse(MOUSE_BUTTON_LEFT, false)
	await _frames(2)
	_check(not _source.is_burning() and _control.get_ring().get_refusal_left(StoveInteractionRing.Arc.FIRE) > 0.0,
		"no lighter: no fire-arc feedback")
	_add(&"lighter", maxi(lighters, 1))
	_source.remove_cold_logs(1)
	_mouse(MOUSE_BUTTON_RIGHT, true)
	_mouse(MOUSE_BUTTON_RIGHT, false)
	await _frames(3)
	while _inventory.try_remove(&"firewood"):
		pass
	await _frames(int(HeatSourceFeed.FUEL_SECONDS * 60.0) + 20)
	_check(_source.get_loaded_log_count() == 2, "a log lost mid-act still went in")
	_add(&"firewood", 2)
	_mouse(MOUSE_BUTTON_RIGHT, true)
	_mouse(MOUSE_BUTTON_RIGHT, false)
	await _wait_act()
	_check(_source.get_loaded_log_count() == 3, "the refill log did not go in")


## Test 9: F closes the door and stands Henry; a return finds the logs and the tinder.
func _test_exit_and_return() -> void:
	_press(&"interact")
	await _frames(3)
	_check(_control.get_phase() == StoveInteractionController.Phase.EXITING, "F did not start the exit")
	_check(not _feed.is_door_open(), "F did not close the door")
	await _frames(60)
	_check(_control.get_phase() == StoveInteractionController.Phase.OUTSIDE, "the exit did not finish")
	_check(not _player.is_crouching() and _state.call(&"is_on_foot"), "Henry did not stand up and get his legs back")
	_check(not _control.get_ring().is_shown(), "the ring stayed up")
	_check(_source.get_loaded_log_count() == 3 and _source.is_tinder_prepared(), "leaving lost the logs or the tinder")
	_camera.set_process(true)
	for _i: int in range(60):
		if _camera.get_work_framing_blend() <= 0.0:
			break
		await create_timer(0.05).timeout
	_camera.set_process(false)
	_check(_camera.get_work_framing_blend() <= 0.0, "the camera did not hand the view back after F")
	_control.request_enter()
	for _i: int in range(240):
		await physics_frame
		if _control.is_working():
			break
	_check(_control.is_working(), "a second F did not return to the stove")
	_check(_source.get_loaded_log_count() == 3 and _source.is_tinder_prepared(), "returning reset the firebox")


## Test 10: a save keeps the logs and the tinder; nothing of the ritual mode is saved.
func _test_save_round_trip() -> void:
	var data: Dictionary = _source.get_fire_save_data()
	_check(bool(data.get("tinder_prepared", false)), "the save has no prepared tinder")
	var copy := HeatSource.new()
	copy.starts_burning = false
	root.add_child(copy)
	copy.restore_fire_save_data(data)
	_check(copy.get_loaded_log_count() == 3 and copy.is_tinder_prepared() and not copy.is_burning(),
		"loading lost the cold load or the tinder")
	copy.queue_free()
	var shelter := ShelterState.new()
	root.add_child(shelter)
	var zone: ThermalZone = _house.get_node(^"ShelterZone") as ThermalZone
	shelter.adopt_fire(zone, _source)
	_source.set_tinder_prepared(false)
	_source.set_tinder_prepared(true)
	shelter._world = _house
	var saved_shelter: Dictionary = shelter.get_save_data()
	var stored: Dictionary = (saved_shelter["fires"] as Dictionary).values()[0]
	var visual := _source.find_child("StoveVisual",true,false) as StoveVisual
	var placements: Dictionary = visual.get_presentation_save_data()
	_source.restore_fuel(0.0,false)
	shelter.load_save_data(saved_shelter)
	_check(_source.get_loaded_log_count() == 3 and _source.is_tinder_prepared(),"ShelterState failed to restore real fuel/tinder")
	var restored: Dictionary = visual.get_presentation_save_data()
	for i: int in range(placements["logs"].size()):
		var a: Vector3 = str_to_var(placements["logs"][i]["position"])
		var b: Vector3 = str_to_var(restored["logs"][i]["position"])
		_check(a.is_equal_approx(b),"ShelterState moved a placed log")
	_check(placements["tinder_position"] == restored["tinder_position"],"ShelterState moved tinder contact")
	await _frames(80)
	_check(not _control.is_active(),"loading kept the ritual mode")
	_control.request_enter()
	for _i: int in range(240):
		await physics_frame
		if _control.is_working():
			break
	_check(bool(stored.get("tinder_prepared", false)), "ShelterState does not record the tinder")
	shelter.queue_free()


## Test 7: a new LMB press strikes; releasing early resets the hold; a full hold lights the stove.
func _test_lighter() -> void:
	for _i: int in range(240):
		await physics_frame
		if _feed.get_stage() == HeatSourceFeed.Stage.READY:
			break
	_check(_feed.get_stage() == HeatSourceFeed.Stage.READY, "the lighter never became ready (%d)" % _feed.get_stage())
	_mouse(MOUSE_BUTTON_LEFT, true)
	await _frames(2)
	_check(_feed.get_stage() == HeatSourceFeed.Stage.HOLDING and _feed._lighter != null and _feed._lighter.is_flame_visible(),
		"the strike gave no flame")
	await _frames(40)
	_check(_control.get_ring().describe(StoveInteractionRing.Arc.FIRE)["state"] == StoveInteractionRing.ArcState.ACTIVE, "the fire arc does not show the hold")
	_mouse(MOUSE_BUTTON_LEFT, false)
	await _frames(2)
	_check(_feed.get_stage() == HeatSourceFeed.Stage.READY and not _source.is_burning(), "an early release lit the stove")
	_check(_source.get_loaded_log_count() == 3 and _source.is_tinder_prepared(), "a failed hold lost fuel or tinder")
	await _frames(20)
	_mouse(MOUSE_BUTTON_LEFT, true)
	await _frames(int((HeatSourceFeed.LIGHT_SECONDS+0.9) * 60.0) + 20)
	_mouse(MOUSE_BUTTON_LEFT, false)
	_check(_source.is_burning(), "a full hold did not light the stove")
	_check(not _source.is_tinder_prepared(), "the tinder survived its own fire")
	_check(_source.get_intensity() < 1.0, "the fire skipped its warm-up")
	var ring: StoveInteractionRing = _control.get_ring()
	_check(ring.describe(StoveInteractionRing.Arc.FIRE)["state"] == StoveInteractionRing.ArcState.DONE and ring.describe(StoveInteractionRing.Arc.TINDER)["state"] == StoveInteractionRing.ArcState.SPENT,
		"the arcs do not show the fire and the spent tinder")


## Test 11: a burning stove takes a log (no relight, the warm-up keeps going).
func _test_burning_refuel() -> void:
	_source.advance_fuel(2.5)
	var intensity: float = _source.get_intensity()
	_add(&"firewood", 1)
	_mouse(MOUSE_BUTTON_RIGHT, true)
	_mouse(MOUSE_BUTTON_RIGHT, false)
	await _wait_act()
	_check(_source.is_burning() and _source.get_intensity() >= intensity - 0.0001, "refuelling restarted the fire")
	_check(_source.get_loaded_log_count() == _source.get_log_capacity(), "the burning stove did not take the log")
	_press(&"interact")
	await _frames(60)
	_check(_control.get_phase() == StoveInteractionController.Phase.OUTSIDE, "leaving a burning stove hung")


## Test 12 (entry): F twice quickly aborts the walk cleanly; a freed stove frees Henry.
func _test_quick_f_and_target_loss() -> void:
	await _place_and_aim(2.2)
	_control.request_enter()
	await _frames(2)
	_press(&"interact")
	await _frames(3)
	_check(_control.get_phase() == StoveInteractionController.Phase.OUTSIDE and _state.call(&"is_on_foot"),
		"a second F mid-walk left a mode behind")
	_control.request_enter()
	for _i: int in range(600):
		await physics_frame
		if _control.is_working():
			break
	_check(_control.is_working(), "fixture: could not re-enter (phase %d, at %.2f m)" % [_control.get_phase(), _control._flat_distance()])
	_feed.get_parent().remove_child(_feed)
	await _frames(2)
	_check(_state.call(&"is_on_foot") and not _player.is_work_crouching(), "a vanished stove kept Henry rooted")
	var input_systems: Node = root.get_node(^"InputSystems")
	_check(not input_systems.call(&"is_interact_claimed"), "a vanished stove kept the F key")
	_feed.free()


func _place_henry_before_stove(distance: float) -> void:
	var at: Vector3 = _source.to_global(Vector3(distance, 0.0, 0.15))
	at.y = _house.to_global(Vector3(0, 1.91, 0)).y
	_player.global_position = at
	_player.velocity = Vector3.ZERO
	_player.look_at(Vector3(_source.global_position.x, at.y, _source.global_position.z), Vector3.UP)


func _place_and_aim(distance: float) -> void:
	_place_henry_before_stove(distance)
	_camera.global_position = _player.global_position + Vector3.UP * 0.65
	_camera.look_at(_feed.focus_anchor.global_position)
	await _frames(3)
	_interact.detect_target()


func _wait_act() -> void:
	for _i: int in range(400):
		await physics_frame
		if not _feed.is_acting() or _feed.get_act() == HeatSourceFeed.Act.LIGHT:
			return


func _add(id: StringName, count: int) -> void:
	for _i: int in range(count):
		_inventory.try_add(ItemCatalog.get_item(id))


## Takes every one Henry owns, pack and Quick Access pockets alike; returns how many.
func _take_owned(id: StringName) -> int:
	var taken: int = 0
	while _inventory.try_remove(id):
		taken += 1
	var equipment := _player.get_node_or_null(^"EquipmentComponent") as EquipmentComponent
	for pocket: Dictionary in equipment.get_available_pockets():
		if pocket["item_id"] == id and equipment.take_from_pocket(pocket["body_slot"], pocket["pocket"]) == id:
			taken += 1
	return taken


func _tinder_count() -> int:
	var count: int = _inventory.get_count(&"tinder")
	var equipment := _player.get_node_or_null(^"EquipmentComponent") as EquipmentComponent
	if equipment != null:
		for pocket: Dictionary in equipment.get_available_pockets():
			if pocket["item_id"] == &"tinder":
				count += 1
	return count


## The TPS camera frames the open firebox: the fire's spot sits mid-screen and no part of
## Henry stands between the lens and it (owner: the ritual must be seen).
func _check_work_framing() -> void:
	var camera := root.get_camera_3d() as TpsCamera
	_check(camera != null, "the ritual runs without the TPS camera")
	if camera == null:
		return
	## The fixture holds the camera still for aiming; the framing check lets it run.
	camera.set_process(true)
	## The blend runs on real time; headless frames are short, so wait on the clock.
	for _i: int in range(60):
		if camera.get_work_framing_blend() >= 1.0:
			break
		await create_timer(0.05).timeout
	await process_frame
	_check(camera.get_work_framing_blend() >= 1.0, "the camera never settled on the stove framing (blend %.2f)" % camera.get_work_framing_blend())
	var focus: Vector3 = _source.to_global(StoveInteractionController.VIEW_FOCUS)
	var size: Vector2 = camera.get_viewport().get_visible_rect().size
	var on_screen: Vector2 = camera.unproject_position(focus) / size
	_check(not camera.is_position_behind(focus) and absf(on_screen.x - 0.5) < 0.25 and absf(on_screen.y - 0.5) < 0.3,
		"the firebox is off the frame: %s" % on_screen)
	## Henry's collision capsule (0.5 m) is far wider than his body; his bones say what hides.
	var skeleton: Skeleton3D = (_player.animation_component as HenryUALAnimation).skeleton
	var nearest: float = INF
	for bone: String in ["Head", "neck_01", "clavicle_r", "upperarm_r", "clavicle_l", "upperarm_l"]:
		var index: int = skeleton.find_bone(bone)
		if index < 0:
			continue
		var at: Vector3 = skeleton.to_global(skeleton.get_bone_global_pose(index).origin)
		nearest = minf(nearest, at.distance_to(Geometry3D.get_closest_point_to_segment(at, camera.global_position, focus)))
	_check(nearest > 0.15, "Henry's head or shoulders hide the firebox from the camera (%.2f m off the sight line)" % nearest)
	var to_eye: float = camera.global_position.distance_to(_player.global_position)
	_check(to_eye > 0.4 and to_eye < 2.6, "the stove framing is not a close work view: %.2f m from Henry" % to_eye)
	camera.set_process(false)


func _frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame


func _press(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		root.push_input(event)


func _mouse(button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	root.push_input(event)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("stove ritual: " + message)


func _test_held_tinder_cancel() -> void:
	_feed.cancel_act(&"test_put_lighter_away")
	_source.set_tinder_prepared(false)
	var hand := _player.get_node(^"HeldItemComponent") as HeldItemComponent
	var before_hand: int = _tinder_count()
	_check(hand.present_owned(&"tinder"),"owned tinder cannot be held")
	_check(_feed.get_tinder_refusal() == HeatSourceFeed.Refusal.NONE,"actual held tinder is refused")
	_check(_feed.insert_tinder() == HeatSourceFeed.Refusal.NONE,"held tinder act did not start")
	await _frames(10)
	_feed.cancel_act(&"test_before_contact")
	_check(_tinder_count() == before_hand and not _source.is_tinder_prepared(),"pre-contact cancel consumed tinder")
	_check(hand.get_item_id() == &"tinder","pre-contact cancel did not restore the held tinder")
	_check(_feed.insert_tinder() == HeatSourceFeed.Refusal.NONE,"held-source placement cannot restart after cancellation")
	await _wait_act()
	_check(_source.is_tinder_prepared() and _tinder_count() == before_hand-1,"held-source contact did not commit exactly one tinder")
	hand.put_away()
	_source.set_tinder_prepared(true)
