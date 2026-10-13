extends SceneTree
## 727 loop in the real Reality World via the F/LMB handlers: enter, kit, board, stove, warm, eat, sleep,
## then reload from the save and compare. godot --headless --script <this> -- [--out=DIR]

const SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"
const THERMAL: GDScript = preload("res://scripts/systems/survival/thermal_manager.gd")
const CLOCK: GDScript = preload("res://scripts/systems/time/simulation_clock.gd")
const ACTIONS: GDScript = preload("res://scripts/systems/actions/time_costed_action_system.gd")
const SAVE: GDScript = preload("res://scripts/systems/save/save_manager.gd")
const SLEEP: GDScript = preload("res://scripts/systems/save/sleep_controller.gd")
const HEATED_WINDOWS: Array[String] = ["FrontWindow1", "FrontWindow2", "SideWindowWest", "SideWindowEast"]
const BOARD_STACKS: Array[String] = ["BoardsShelterInside", "BoardsShelterTest1", "BoardsShelterTest2",
	"BoardsShelterTest3", "BoardsShelterTest4", "BoardsShelterTest5", "BoardsShelterTest6"]
const KIT: Array[String] = ["HammerShelter", "NailsShelter", "LighterShelterTest", "StewShelterTest"]
const ARRIVAL_WETNESS: float = 0.4
const WAIT_HOURS: float = 3.0
const HENRY_HALF_HEIGHT: float = 1.0

var _out: String = "user://loop_key_west_727"
var _world: Node3D
var _ctx: WorldContext
var _player: Player
var _inventory: InventoryComponent
var _camera: Camera3D
var _house: Node3D
var _steps: Array[Dictionary] = []
var _verdict: Dictionary = {}
var _expected: Dictionary = {}


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_run.call_deferred()


func _run() -> void:
	SaveManager.pending_load_slot = -1
	var probe: SaveManager = SAVE.new()
	probe.delete_slot(SaveManager.SLEEP_SLOT)
	probe.free()
	await _boot()
	await _enter()
	await _take_kit()
	await _board_windows()
	await _light_stove()
	await _warm_and_dry()
	await _eat()
	await _sleep()
	await _reload()
	_finish()


func _boot() -> void:
	_world = (load(SCENE) as PackedScene).instantiate() as Node3D
	_world.set(&"spawn_at_shelter", true)
	root.add_child(_world)
	while _ctx == null:
		await process_frame
		_ctx = _world.call(&"get_context") if _world.has_method(&"get_context") else null
	_player = _ctx.player as Player
	_camera = _ctx.camera
	## As in test_shelter_workflow: the script owns the view, the orbit camera must not pull it back.
	_camera.set_process(false)
	_camera.set_physics_process(false)
	_inventory = _player.get_node(^"InventoryComponent") as InventoryComponent
	_house = _world.find_child("Shelter727", true, false).get_node(^"House") as Node3D
	await _await_floor()


## The 727 chunk is streamed when the lobby floor collides.
func _await_floor() -> void:
	var lobby: Vector3 = _plan(6.2, 1.6, 1.5)
	for _i: int in range(3000):
		await physics_frame
		var hit: Dictionary = _ray(lobby, lobby + Vector3.DOWN * 3.0)
		if not hit.is_empty():
			return
	_fail("727 chunk never streamed in")


func _enter() -> void:
	var thermal: ThermalManager = _thermal()
	_step("arrive", {"outside_sheltered": thermal.is_sheltered()})
	_put_player(_plan(6.2, 1.4, 0.0))
	for _i: int in range(30):
		await physics_frame
	thermal.add_wetness(ARRIVAL_WETNESS)
	_step("enter", {"sheltered": thermal.is_sheltered(), "wetness": thermal.get_wetness()})
	_verdict["entered_and_sheltered"] = thermal.is_sheltered()


func _take_kit() -> void:
	var ok: bool = true
	for node_name: String in KIT:
		ok = await _pick(node_name) and ok
	_step("take_kit", {"hammer": _inventory.get_count(&"hammer"), "nails": _inventory.get_count(&"nails"),
		"lighter": _inventory.get_count(&"lighter"), "stew": _inventory.get_count(&"tinned_stew")})
	_verdict["kit_taken"] = ok


## Each window takes five boards (2 nails each); an armful of three is staged by F, then each
## board is nailed by LMB with the camera on the opening.
func _board_windows() -> void:
	var zone: ThermalZone = _house.get_node(^"ShelterZone") as ThermalZone
	var stacks: Array[String] = BOARD_STACKS.duplicate()
	var sealed: int = 0
	var nails_before: int = _inventory.get_count(&"nails")
	for window: String in HEATED_WINDOWS:
		var breach: ShelterBreach = zone.get_node(NodePath(window)) as ShelterBreach
		var area: BreachBoardUp = breach.get_node(^"BoardUp") as BreachBoardUp
		while not breach.is_boarded():
			if breach.get_staged_boards() == 0:
				if _inventory.get_count(&"boards") == 0:
					if stacks.is_empty():
						break
					await _pick(stacks.pop_front())
				_stand_before(breach)
				await _settle()
				area._on_interaction_performed()
				await _settle()
			_stand_before(breach)
			await _settle()
			area._on_interaction_performed()
			if not area.is_placing_board():
				_fail("%s: could not take a staged board (staged %d, nails %d)" % [window, breach.get_staged_boards(), _inventory.get_count(&"nails")])
				break
			var y: float = _next_board_y(breach)
			_point_camera(breach.to_global(Vector3(0.0, y, 0.0)))
			area._commit_board()
			await _settle()
		if breach.is_boarded() and breach.get_staged_boards() > 0:
			## F on a sealed window takes the spare boards back, as a player carries them on.
			(_player.get_node(^"HammerComponent") as HammerComponent).put_away()
			await _settle()
			area._on_interaction_performed()
			await _settle()
		sealed += 1 if breach.is_boarded() else 0
	var hammer: HammerComponent = _player.get_node(^"HammerComponent") as HammerComponent
	if hammer.is_holding():
		hammer.put_away()
	var spare: int = _inventory.get_count(&"boards")
	if spare > 0:
		## Hands must be free for the firewood: the spare goes by the storage window for later.
		var clinic: ThermalZone = _house.get_node(^"ClinicZone") as ThermalZone
		var storage: ShelterBreach = clinic.get_node(^"StorageWindow") as ShelterBreach
		_stand_before(storage)
		await _settle()
		(storage.get_node(^"BoardUp") as BreachBoardUp)._on_interaction_performed()
		await _settle()
	_step("repair", {"windows_sealed": sealed, "of": HEATED_WINDOWS.size(), "nails_used": nails_before - _inventory.get_count(&"nails"),
		"spare_boards_staged_in_storage": spare,
		"zone_exposure": zone.get_breaches().map(func(b: ShelterBreach) -> float: return snappedf(b.get_open_fraction(), 0.01))})
	_verdict["heated_room_sealed"] = sealed == HEATED_WINDOWS.size()


## Tinder is not in the 727 kit; the First Exit route carries it (here: the house next door).
func _light_stove() -> void:
	var tinder: bool = await _pick("TinderCollapsedN3")
	await _pick("FirewoodShelter")
	var feed: HeatSourceFeed = _house.get_node(^"ShelterZone/Stove/Feed") as HeatSourceFeed
	var source: HeatSource = feed.heat_source
	var anchor: Vector3 = feed.focus_anchor.global_position
	## The hut workflow approaches the stove along its local +X (the firebox side).
	var side: Vector3 = source.global_basis.x
	var out: Vector3 = Vector3(side.x, 0.0, side.z).normalized()
	var stand: Vector3 = source.global_position + out * 1.2
	stand = _floor_at(stand)
	await _aim(stand, anchor)
	if not feed.is_door_open():
		feed.toggle_door()
	await create_timer(0.4).timeout
	await _aim(stand, anchor)
	var ic: InteractComponent = _player.get_node(^"InteractComponent") as InteractComponent
	var aimed: Dictionary = {"target": str(ic.get_world_target()), "in_reach": ic.is_world_target_in_reach(),
		"henry_to_door_m": snappedf(_player.global_position.distance_to(feed.focus_anchor.global_position), 0.01)}
	var load_refusal: int = feed.begin_act()
	await _while_acting(feed, 20.0)
	var loaded: int = source.get_recoverable_log_count()
	## Loading cold logs moves straight on to lighting; F again would cancel it.
	var light_refusal: int = HeatSourceFeed.Refusal.NONE if feed.is_acting() else feed.begin_act()
	var strike: int = HeatSourceFeed.StrikeResult.IGNORED
	## Wall clock, not frames: the work pose that readies the lighter animates in real time.
	var deadline: int = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		strike = feed.attempt_lighter_strike()
		if strike == HeatSourceFeed.StrikeResult.FLAME:
			break
	await _while_acting(feed, 20.0)
	await _settle()
	_step("fire", {"aim": aimed, "tinder_carried": tinder, "load_refusal": load_refusal, "logs_loaded": loaded, "light_refusal": light_refusal,
		"strike": strike, "burning": source.is_burning(), "fuel_h": snappedf(source.get_remaining_hours(), 0.01),
		"firewood_left": _inventory.get_count(&"firewood"), "door_open": feed.is_door_open()})
	_verdict["stove_lit"] = source.is_burning()


## Henry waits by the stove (the game's wait action) until warm and dry or the fire fails him.
func _warm_and_dry() -> void:
	var thermal: ThermalManager = _thermal()
	var sleep: SleepController = _ctx.get_system(SLEEP) as SleepController
	_put_player(_floor_at(_plan(-1.2, 4.9, 0.0)))
	await _settle()
	var before: Dictionary = _thermal_state(thermal)
	var waited: float = sleep.try_wait(WAIT_HOURS)
	await _settle()
	var after: Dictionary = _thermal_state(thermal)
	_put_player(_floor_at(_plan(-4.4, 7.6, 0.0)))
	await _settle()
	var mattress: Dictionary = _thermal_state(thermal)
	_step("warm_dry", {"by_stove_before": before, "by_stove_after": after, "waited_h": snappedf(waited, 0.01),
		"on_mattress": mattress, "outdoor_c": thermal.get_outdoor_air_c()})
	_verdict["warmed_and_dried"] = after["wetness"] < before["wetness"] and after["felt_c"] > before["felt_c"]


func _thermal_state(thermal: ThermalManager) -> Dictionary:
	return {"body_c": snappedf(thermal.get_body_temperature_c(), 0.01), "felt_c": snappedf(thermal.get_felt_temperature_c(), 0.1),
		"room_c": snappedf(thermal.get_room_temperature_c(), 0.1), "wetness": snappedf(thermal.get_wetness(), 0.01)}


func _eat() -> void:
	var controller: ConsumptionController = _player.get_node(^"ConsumptionController") as ConsumptionController
	var before: int = _inventory.get_count(&"tinned_stew")
	var result: int = controller.consume(&"tinned_stew")
	await _settle()
	_step("eat", {"refusal": result, "stew_before": before, "stew_after": _inventory.get_count(&"tinned_stew")})
	_verdict["ate"] = result == ConsumptionController.Refusal.NONE


func _sleep() -> void:
	var sleep: SleepController = _ctx.get_system(SLEEP) as SleepController
	_put_player(_floor_at(_plan(-4.4, 7.6, 0.0)))
	await _settle()
	var refusal: int = sleep.can_sleep()
	var slept: bool = sleep.try_sleep(8.0) if refusal == SleepController.Refusal.NONE else false
	await _settle()
	var saver: SaveManager = _ctx.get_system(SAVE) as SaveManager
	_expected = _snapshot()
	_step("sleep_save", {"refusal": refusal, "slept": slept, "slot_written": saver.has_slot(SaveManager.SLEEP_SLOT)})
	_verdict["slept_and_saved"] = slept and saver.has_slot(SaveManager.SLEEP_SLOT)


func _reload() -> void:
	_world.queue_free()
	await process_frame
	await process_frame
	_ctx = null
	SaveManager.pending_load_slot = SaveManager.SLEEP_SLOT
	await _boot()
	for _i: int in range(20):
		await physics_frame
	var got: Dictionary = _snapshot()
	var diffs: Array[String] = []
	for key: String in _expected:
		if str(_expected[key]) != str(got[key]):
			diffs.append("%s: saved %s, reloaded %s" % [key, _expected[key], got[key]])
	_step("reload", {"saved": _expected, "reloaded": got, "diffs": diffs})
	_verdict["reload_matches"] = diffs.is_empty()


## Persistent state the reload must reproduce.
func _snapshot() -> Dictionary:
	var zone: ThermalZone = _house.get_node(^"ShelterZone") as ThermalZone
	var boards: Dictionary = {}
	for breach: ShelterBreach in zone.get_breaches():
		boards[String(breach.name)] = snappedf(breach.get_coverage_fraction(), 0.01)
	var source: HeatSource = (_house.get_node(^"ShelterZone/Stove/Feed") as HeatSourceFeed).heat_source
	var taken: Array[String] = []
	for name: String in KIT + BOARD_STACKS + ["FirewoodShelter"]:
		if _world.find_child(name, true, false) == null:
			taken.append(name)
	var p: Vector3 = _house.to_local(_player.global_position)
	return {"boards": boards, "fire_burning": source.is_burning(), "fire_hours": snappedf(source.get_remaining_hours(), 0.1),
		"taken": taken, "hammer": _inventory.get_count(&"hammer"), "nails": _inventory.get_count(&"nails"),
		"stew": _inventory.get_count(&"tinned_stew"), "player_in_727": absf(p.x) < 14.0 and absf(p.z) < 11.0}


func _pick(node_name: String) -> bool:
	var pickup: ItemPickup = _world.find_child(node_name, true, false) as ItemPickup
	if pickup == null:
		_fail("pickup %s missing" % node_name)
		return false
	var away: Vector3 = _player.global_position - pickup.global_position
	away.y = 0.0
	_put_player(_floor_at(pickup.global_position + away.normalized() * 0.8))
	await _settle()
	var id: StringName = pickup.item_id
	var before: int = _inventory.get_count(id)
	var ok: bool = pickup.pick_up()
	await _settle()
	if not ok or _inventory.get_count(id) <= before:
		_fail("pickup %s refused" % node_name)
		return false
	return true


## Stands Henry 1.2 m inside the opening, facing it.
func _stand_before(breach: ShelterBreach) -> void:
	var inward: Vector3 = -breach.get_facing()
	var at: Vector3 = breach.global_position + inward * 1.2
	_put_player(_floor_at(at))
	_point_camera(breach.global_position)


func _next_board_y(breach: ShelterBreach) -> float:
	var limit: float = breach.opening_height_m * 0.5 - breach.board_height_m * 0.5
	var placed: Array[float] = breach.get_placed_board_positions()
	var y: float = -limit
	while y <= limit + 0.001:
		var free: bool = true
		for other: float in placed:
			free = free and absf(other - y) >= breach.board_height_m * 0.9
		if free:
			return y
		y += breach.board_height_m
	return limit


## Henry stands at `from`, faces `point` and looks at it, so the interaction target is what he sees.
func _aim(from: Vector3, point: Vector3) -> void:
	_put_player(from)
	var flat: Vector3 = Vector3(point.x, _player.global_position.y, point.z)
	if _player.global_position.distance_to(flat) > 0.01:
		_player.look_at(flat, Vector3.UP)
	_point_camera(point)
	await physics_frame
	await physics_frame
	(_player.get_node(^"InteractComponent") as InteractComponent).detect_target()


## `feet` is where Henry stands; his origin is the capsule centre, HENRY_HALF_HEIGHT above.
func _put_player(feet: Vector3) -> void:
	_player.global_position = feet + Vector3.UP * HENRY_HALF_HEIGHT
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()


## Lens shift moves the ray origin, so the basis is iterated until the centre ray hits the point.
func _point_camera(point: Vector3) -> void:
	_camera.global_position = _player.global_position + Vector3.UP * 0.65  # eye height, as test_shelter_workflow
	_camera.look_at(point)
	var centre: Vector2 = root.get_visible_rect().size * 0.5
	for _i: int in range(12):
		var from: Vector3 = _camera.project_ray_origin(centre)
		var actual: Vector3 = _camera.project_ray_normal(centre).normalized()
		var desired: Vector3 = (point - from).normalized()
		_camera.global_basis = Basis(Quaternion(actual, desired)) * _camera.global_basis


## Finishes the running action clip so the next interaction is not locked out.
func _settle() -> void:
	var actions: TimeCostedActionSystem = _ctx.get_system(ACTIONS) as TimeCostedActionSystem
	if actions != null and actions.is_active():
		var presentation: float = actions.get_effective_presentation_seconds()
		if presentation > 0.0:
			actions.advance_presentation(presentation + 0.05)
	_player._hold_until_ms = 0
	var visual: HenryUALAnimation = _player.animation_component
	if is_instance_valid(visual):
		visual.end_work_pose()
		visual.abort_action()
	await process_frame
	await physics_frame
	await physics_frame


## Waits out a stove act (loading runs on its own presentation clock, lighting on the held flame).
## The limit is wall clock: the flame must be held LIGHT_SECONDS of real frame time at any frame rate.
func _while_acting(feed: HeatSourceFeed, max_seconds: float) -> void:
	var actions: TimeCostedActionSystem = _ctx.get_system(ACTIONS) as TimeCostedActionSystem
	var deadline: int = Time.get_ticks_msec() + int(max_seconds * 1000.0)
	while feed.is_acting() and Time.get_ticks_msec() < deadline:
		if actions.is_active() and not feed._is_lighting():
			actions.advance_presentation(0.1)
		await process_frame


func _thermal() -> ThermalManager:
	return _ctx.get_system(THERMAL) as ThermalManager


## Plan point (u, v) of 727 at y metres above its floor, in world space.
func _plan(u: float, v: float, y: float) -> Vector3:
	var floor_y: float = float(_world.find_child("Shelter727", true, false).get(&"interior")["floor_y"])
	return _house.to_global(Vector3(u, floor_y + y, v))


## Floor or ground under a point: the 727 floor inside its walls, else the first surface below.
func _floor_at(p: Vector3) -> Vector3:
	var local: Vector3 = _house.to_local(p)
	if absf(local.x) < 13.5 and local.z > -6.5 and local.z < 10.0:
		return Vector3(p.x, _plan(0.0, 0.0, 0.02).y, p.z)
	var hit: Dictionary = _ray(p + Vector3.UP * 1.5, p + Vector3.DOWN * 3.0)
	return (hit["position"] as Vector3) + Vector3.UP * 0.02 if not hit.is_empty() else p


func _ray(a: Vector3, b: Vector3) -> Dictionary:
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(a, b)
	q.collide_with_areas = false
	return _world.get_world_3d().direct_space_state.intersect_ray(q)


func _step(name: String, data: Dictionary) -> void:
	data["step"] = name
	_steps.append(data)
	print("loop: %s %s" % [name, JSON.stringify(data)])


func _fail(message: String) -> void:
	_steps.append({"step": "failure", "message": message})
	push_error("loop: " + message)


func _finish() -> void:
	var report: Dictionary = {"scene": SCENE, "steps": _steps, "verdict": _verdict}
	var path: String = ProjectSettings.globalize_path(_out.path_join("loop_report.json"))
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("loop: verdict %s" % JSON.stringify(_verdict))
	print("loop: report -> %s" % path)
	var ok: bool = not _verdict.is_empty() and _verdict.values().all(func(v: Variant) -> bool: return bool(v))
	quit(0 if ok else 1)
