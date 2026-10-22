extends SceneTree

## The stove ritual in the 727 Fort St shelter (Key West Reality), driven by real input through the
## production TPS camera: named stages and a continuous frame run for a video.
## Run: xvfb-run godot --path . --rendering-driver vulkan --disable-render-loop --fixed-fps 30 --script res://tools/runtime/capture_stove.gd -- <out dir>
## Frames: 1 before F, 2 crouched with the empty ring, 3 one log, 4 three logs, 5 tinder laid,
## 6 holding the lighter, 7 the fire growing, 8 the door closed and Henry up. video/ holds every
## third frame of the whole run. Additional named frames cover refuel, embers and cooling.

const SCENE: String = "res://scenes/world/key_west/key_west_reality.tscn"
## Early afternoon: daylight through the windows shows the firebox and Henry before the fire.
const HOUR: float = 13.0
const VIDEO_EVERY: int = 3

var _out: String = "user://shots/stove"
var _world: Node3D
var _player: Player
var _feed: HeatSourceFeed
var _source: HeatSource
var _control: StoveInteractionController
var _frame: int = 0
var _video: int = 0
var _recording: bool = false


func _initialize() -> void:
	root.content_scale_size = Vector2i(960,540)
	root.size = Vector2i(960,540)
	print("[stove] automatic_render_loop=",RenderingServer.is_render_loop_enabled())
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out).path_join("video"))
	_run()


func _run() -> void:
	_world = (load(SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(_world)
	var ctx: Variant = null
	for _i: int in range(600):
		await process_frame
		ctx = _world.call(&"get_context")
		if _i % 30 == 0:
			print("[stove] bootstrap frame=",_i," context=",ctx != null)
		if ctx != null:
			break
	_player = ctx.player as Player
	for node: Node in _world.find_children("*", "CanvasLayer", true, false):
		node.set(&"visible", false)
	var weather: Node = ctx.get_system(preload("res://scripts/systems/world/WeatherController.gd"))
	weather.call(&"set_weather", &"calm", true, 9999.0)
	for node: Node in _world.find_children("*", "DayNightManager", true, false):
		node.set(&"total_game_time_hours", floorf(float(node.get(&"total_game_time_hours")) / 24.0) * 24.0 + HOUR)
		node.call(&"force_update_lighting")
		node.set_process(false)
	for _i: int in range(90):
		await process_frame
		if HeatSource.get_all().any(func(s: HeatSource) -> bool: return s.find_child("Feed",true,false) != null):
			break
	var shelter: Node = _world.find_children("*", "", true, false).filter(func(n: Node) -> bool: return n is KeyWest727Shelter)[0]
	_feed = shelter.find_child("Feed", true, false) as HeatSourceFeed
	_source = _feed.heat_source
	_control = _feed.controller
	_source.restore_fuel(0.0, false)
	_source.set_tinder_prepared(false)
	var inventory: InventoryComponent = InventoryComponent.find_in(_player)
	var equipment := _player.get_node(^"EquipmentComponent") as EquipmentComponent
	var held := _player.get_node(^"HeldItemComponent") as HeldItemComponent
	if held.get_item_id() == &"tinder":
		held.put_away()
	for pocket: Dictionary in equipment.get_available_pockets():
		if pocket["item_id"] == &"tinder":
			var removed: StringName = equipment.take_from_pocket(pocket["body_slot"],pocket["pocket"])
			_require(inventory.try_add(ItemCatalog.get_item(removed)),"Could not move starter tinder to backpack")
	for _i: int in range(3):
		inventory.try_add(ItemCatalog.get_item(&"firewood"))
	inventory.try_add(ItemCatalog.get_item(&"tinder"))
	inventory.try_add(ItemCatalog.get_item(&"lighter"))
	## Henry two metres before the door, inside the heated room, looking at the stove.
	## Off the door's axis, so the camera over his shoulder sees the stove beside him.
	var stand: Vector3 = _floor_point(_source.to_global(Vector3(1.9, 0.0, 0.95)))
	_player.global_position = stand + Vector3.UP * 1.0
	_player.velocity = Vector3.ZERO
	_player.look_at(Vector3(_source.global_position.x, _player.global_position.y, _source.global_position.z), Vector3.UP)
	## The player's mouse: the TPS aim on the firebox, so F names the stove.
	for _i: int in range(3):
		_aim_camera(_feed.focus_anchor.global_position)
		for _f: int in range(15):
			await process_frame
	_recording = not OS.get_cmdline_user_args().has("review")
	await _shot("1_before_f")
	_press_interact()
	await _until(func() -> bool: return _control.is_working(), 12.0)
	await _hold(0.6)
	await _shot("2_crouched_empty_ring")
	_mouse(MOUSE_BUTTON_RIGHT, true)
	_mouse(MOUSE_BUTTON_RIGHT, false)
	await _hold(0.65)
	await _shot("03a_log_in_hand")
	await _hold(0.55)
	await _shot("03b_log_reach")
	await _until(func() -> bool: return _source.get_loaded_log_count() == 1,5.0)
	await _shot("03c_log_release")
	await _until(func() -> bool: return not _feed.is_acting(), 5.0)
	await _hold(0.3)
	await _shot("3_one_log")
	for _log: int in range(2):
		_mouse(MOUSE_BUTTON_RIGHT, true)
		_mouse(MOUSE_BUTTON_RIGHT, false)
		await _until(func() -> bool: return not _feed.is_acting(), 5.0)
	await _hold(0.3)
	_validate_log_bounds()
	await _shot("4_three_logs")
	_dump_bones("idle")
	_require(_source.get_loaded_log_count() == 3,"Contact did not place all three logs")
	_mouse(MOUSE_BUTTON_LEFT,true)
	_mouse(MOUSE_BUTTON_LEFT,false)
	await _hold(0.3)
	_require(not _feed.is_acting() and not _source.is_tinder_prepared(),"Backpack tinder was incorrectly usable")
	await _shot("04a_backpack_tinder_inactive")
	var pocketed: bool = false
	for pocket: Dictionary in equipment.get_available_pockets():
		if equipment.can_stow(pocket["body_slot"],pocket["pocket"],&"tinder") == EquipmentComponent.Refusal.NONE:
			_require(inventory.try_remove(&"tinder"))
			_require(equipment.stow(pocket["body_slot"],pocket["pocket"],&"tinder") == EquipmentComponent.Refusal.NONE)
			pocketed = true
			break
	_require(pocketed,"No worn Quick Access pocket accepts tinder")
	await _hold(0.3)
	await _shot("04b_pocket_tinder_available")
	# A closer composition through the same TPS work rig; no camera replacement/cut.
	(root.get_camera_3d() as TpsCamera).set_work_framing(_source.to_global(Vector3(0.24,0.4,0.02)),_source.to_global(Vector3(0.86,0.96,-0.30)))
	await _hold(0.6)

	_mouse(MOUSE_BUTTON_LEFT, true)
	await _hold(0.9)
	await _shot("05a_tinder_reach")
	_dump_bones("act")
	await _until(func() -> bool: return _source.is_tinder_prepared(), 5.0)
	if OS.get_cmdline_user_args().has("probe"):
		await _probe_views()
	await _hold(0.4)
	_mouse(MOUSE_BUTTON_LEFT, false)
	await _hold(0.2)
	await _shot("5_tinder_laid")
	var state: ShelterState = ctx.get_system(preload("res://scripts/systems/survival/shelter_state.gd")) as ShelterState
	_require(state != null,"No production ShelterState")
	var visual_before := _source.find_child("StoveVisual",true,false) as StoveVisual
	var placed_before: Dictionary = visual_before.get_presentation_save_data()
	var saved: Dictionary = state.get_save_data()
	state.load_save_data(saved)
	await _until(func() -> bool: return not _control.is_active(),5.0)
	_control.request_enter()
	await _until(func() -> bool: return _control.is_working(),12.0)
	(root.get_camera_3d() as TpsCamera).set_work_framing(_source.to_global(Vector3(0.24,0.4,0.02)),_source.to_global(Vector3(0.86,0.96,-0.30)))
	await _hold(0.6)
	var placed_after: Dictionary = visual_before.get_presentation_save_data()
	print("[stove-save] before=",placed_before," after=",placed_after)
	_require(_same_placement(placed_before,placed_after),"Save/load rearranged the cold firebox")
	await _shot("05b_save_reload_tinder")
	await _until(func() -> bool: return _feed.get_stage() == HeatSourceFeed.Stage.READY, 8.0)
	_mouse(MOUSE_BUTTON_LEFT,true)
	await _hold(1.1)
	await _shot("06a_lighter_contact_early")
	_mouse(MOUSE_BUTTON_LEFT,false)
	await _hold(0.6)
	_require(not _source.is_burning() and _source.is_tinder_prepared(),"Early release lost tinder or lit the stove")
	await _shot("06b_early_release_unlit")
	_mouse(MOUSE_BUTTON_LEFT, true)
	await _hold(HeatSourceFeed.LIGHT_SECONDS * 0.55)
	await _shot("6_lighter_hold")
	await _until(func() -> bool: return _source.is_burning(), 5.0)
	_mouse(MOUSE_BUTTON_LEFT, false)
	await _shot("06c_tinder_catches_first")
	await _hold(0.4)
	for slot: int in visual_before._active_slots:
		_require(float(visual_before._logs[slot].burn_progress) <= 0.001,"A log lit before the tinder-only stage")
	await _shot("06d_tinder_alone")
	await _hold(4.6)
	await _shot("7_fire_growing")
	await _advance_fire(0.20,17.0)
	await _shot("9_steady_open")
	if OS.get_cmdline_user_args().has("review"):
		_control.request_exit()
		await _until(func() -> bool: return not _control.is_active(),5.0)
		quit(0)
		return
	# Input mouse capture is unavailable in the unattended window. Drive the public
	# look API; the production workspace rig still owns orbit and collision.
	var camera := root.get_camera_3d() as TpsCamera
	var yaw: float = camera.get_yaw()
	var pitch: float = camera.get_view_pitch_deg()
	camera.set_look(yaw - deg_to_rad(12.0),pitch)
	await _hold(0.5)
	await _shot("16_open_orbit_left")
	camera.set_look(yaw + deg_to_rad(12.0),pitch)
	await _hold(0.5)
	await _shot("17_open_orbit_right")
	camera.set_look(yaw,pitch)
	await _hold(0.5)
	# Exercise real fuel authority, accelerated only for the render proof.
	await _advance_fire(2.1,2.0)
	await _hold(0.4)
	await _shot("10_two_burning_logs")
	var visual: StoveVisual = _source.find_child("StoveVisual",true,false) as StoveVisual
	var old_progress: Dictionary = {}
	var old_poses: Dictionary = {}
	for slot: int in visual._active_slots:
		old_progress[slot] = float(visual._logs[slot].burn_progress)
		old_poses[slot] = visual._logs[slot].transform
	inventory.try_add(ItemCatalog.get_item(&"firewood"))
	_mouse(MOUSE_BUTTON_RIGHT,true)
	_mouse(MOUSE_BUTTON_RIGHT,false)
	await _until(func() -> bool: return not _feed.is_acting(),5.0)
	await _hold(0.4)
	_require(_source.get_loaded_log_count() == 3,"Refuel did not restore three real fuel units")
	for slot: int in old_progress:
		_require(float(visual._logs[slot].burn_progress) >= float(old_progress[slot]),"Refuel reset an older log")
		_require(visual._logs[slot].transform.is_equal_approx(old_poses[slot]),"Refuel moved an older log")
	await _shot("11_refuel_preserves_old_logs")
	_press_interact()
	await _until(func() -> bool: return not _control.is_active(), 5.0)
	await _hold(1.2)
	await _shot("8_door_closed_up")
	# TPS orbit under the same production follow rig, closed-door depth/occlusion proof.
	_aim_camera(_feed.focus_anchor.global_position)
	await _hold(0.5)
	await _shot("12_closed_door_fire")
	# The follow-camera centre now targets the pot on top (Warm up), not Feed.
	# Reenter the actual stove controller explicitly; keep its full door/crouch flow.
	_control.request_enter()
	await _until(func() -> bool: return _control.is_working(),12.0)
	await _hold(0.6)
	await _advance_fire(maxf(0.0,_source.get_remaining_hours()-0.12),4.0)
	await _hold(0.8)
	await _shot("13_embers_open")
	_source.advance_fuel(_source.get_remaining_hours())
	await _hold(0.4)
	await _shot("14_residual_coals_no_fuel")
	await _hold(6.5)
	await _shot("15_cold_empty")
	_recording = false
	print("[stove] logs=%d tinder=%s burning=%s intensity=%.2f video_frames=%d" % [_source.get_loaded_log_count(),
		_source.is_tinder_prepared(), _source.is_burning(), _source.get_intensity(), _video])
	_control.request_exit()
	await _until(func() -> bool: return not _control.is_active(),5.0)
	quit(0)


func _process(_delta: float) -> bool:
	## Debug HUD layers come and go; only the stove ring stays on the frames.
	if Engine.get_process_frames() % 15 == 0 and _world != null:
		for node: Node in _world.find_children("*", "CanvasLayer", true, false):
			if node.name != &"StoveRingLayer" and not _is_prompt(node):
				node.set(&"visible", false)
		for node: Node in root.get_children():
			if node is Control:
				node.set(&"visible", false)
		for node: Node in _world.find_children("*", "Label", true, false):
			if node.get_viewport() == root and not _is_prompt(node) and not _under_ring(node):
				node.set(&"visible", false)
	if _recording:
		_frame += 1
		if _frame % VIDEO_EVERY == 0:
			_video += 1
			_save(ProjectSettings.globalize_path(_out).path_join("video/%05d.png" % _video))
	return false


func _shot(name: String) -> void:
	_save(ProjectSettings.globalize_path(_out).path_join(name + ".png"))
	print("[stove] shot ", name, " phase=", _control.get_phase(), " logs=", _source.get_loaded_log_count(),
		" visual_logs=", (_source.find_child("StoveVisual",true,false) as StoveVisual).get_visible_log_count(), " tinder=", _source.is_tinder_prepared(), " stage=", _feed.get_stage(), " burning=", _source.is_burning())
	if _feed.get_act() != HeatSourceFeed.Act.NONE:
		if _feed._lighter != null:
			print("[stove] nozzle-to-visible-tinder=",_feed._lighter.get_flame_tip().distance_to((_source.find_child("StoveVisual",true,false) as StoveVisual).to_global((_source.find_child("StoveVisual",true,false) as StoveVisual).get_tinder_contact())))
		print("[stove] hand-target error=",_feed._actual_palm.distance_to(_feed._contact_palm)," target=",_source.to_local(_feed._contact_palm)," hand=",_source.to_local(_feed._actual_palm))
	var camera := root.get_camera_3d() as TpsCamera
	if camera != null:
		print("[stove] camera in stove space ", _source.to_local(camera.global_position), " henry ",
			_source.to_local(_player.global_position), " framing ", camera.get_work_framing_blend())


## Probe: Henry's bones and the door in stove space, for composing the work framing.
func _dump_bones(tag: String) -> void:
	var skeleton: Skeleton3D = (_player.animation_component as HenryUALAnimation).skeleton
	for i: int in range(skeleton.get_bone_count()):
		var bone: String = skeleton.get_bone_name(i)
		if bone.to_lower().contains("head") or bone.to_lower().contains("hand") or bone.to_lower().contains("upperarm") \
				or bone.to_lower().contains("clavicle") or bone.to_lower().contains("shoulder") or bone.to_lower().contains("neck"):
			print("[bone] %s %s %s" % [tag, bone, _source.to_local(skeleton.to_global(skeleton.get_bone_global_pose(i).origin))])
	var hinge: Node3D = _source.find_child("DoorHinge", true, false) as Node3D
	if hinge != null:
		print("[bone] %s door_hinge %s door_tip %s" % [tag, _source.to_local(hinge.global_position),
			_source.to_local(hinge.to_global(Vector3(0.0, 0.17, 0.44)))])


func _probe_views() -> void:
	var camera := root.get_camera_3d() as TpsCamera
	var views: Array = OS.get_cmdline_user_args().slice(2)
	for i: int in range(0, views.size() - 5, 6):
		var eye := Vector3(float(views[i]), float(views[i + 1]), float(views[i + 2]))
		var focus := Vector3(float(views[i + 3]), float(views[i + 4]), float(views[i + 5]))
		camera.set_work_framing(_source.to_global(focus), _source.to_global(eye))
		await _hold(0.2)
		await _shot("probe_%d" % (i / 6))


func _save(path: String) -> void:
	RenderingServer.force_draw(false, 1.0/30.0)
	root.get_texture().get_image().save_png(path)


func _until(done: Callable, seconds: float) -> void:
	var frames: int = int(seconds * 30.0)
	for _i: int in range(frames):
		if done.call():
			return
		await process_frame
	push_error("capture_stove: timed out waiting for real ritual state")
	quit(1)


## Render-only time compression through the existing fuel owner, never a second simulation.
func _advance_fire(hours: float, seconds: float) -> void:
	var steps: int = maxi(1,int(seconds*30.0))
	for _i: int in range(steps):
		_source.advance_fuel(hours/float(steps))
		await process_frame


func _hold(seconds: float) -> void:
	for _i: int in range(int(seconds * 30.0)):
		await process_frame


func _press_interact() -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = &"interact"
		event.pressed = pressed
		root.push_input(event)


func _mouse(button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	root.push_input(event)


func _is_prompt(node: Node) -> bool:
	while node != null:
		if node.is_in_group(&"interaction_cursor_prompt") or node.is_in_group(&"action_prompt_3d"):
			return true
		node = node.get_parent()
	return false


func _under_ring(node: Node) -> bool:
	while node != null:
		if node.name == &"StoveRingLayer":
			return true
		node = node.get_parent()
	return false


## The production TPS camera turned so its aim passes through the point.
func _aim_camera(point: Vector3) -> void:
	var camera := root.get_camera_3d()
	if camera == null or not camera.has_method(&"set_look"):
		return
	var dir: Vector3 = (point - camera.global_position).normalized()
	camera.call(&"set_look", atan2(-dir.x, -dir.z), rad_to_deg(asin(clampf(dir.y, -1.0, 1.0))))


func _floor_point(at: Vector3) -> Vector3:
	var space: PhysicsDirectSpaceState3D = _world.get_world_3d().direct_space_state
	var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.6, at + Vector3.DOWN * 2.0))
	return hit["position"] if not hit.is_empty() else at


func _require(ok: bool, message: String = "capture invariant failed") -> void:
	if not ok:
		push_error(message)
		quit(1)


func _same_placement(a: Dictionary, b: Dictionary) -> bool:
	if a["logs"].size() != b["logs"].size() or a["has_tinder"] != b["has_tinder"]:
		return false
	if not (str_to_var(a["tinder_position"]) as Vector3).is_equal_approx(str_to_var(b["tinder_position"])):
		return false
	for i: int in range(a["logs"].size()):
		var p: Vector3 = str_to_var(a["logs"][i]["position"])
		var q: Vector3 = str_to_var(b["logs"][i]["position"])
		var r: Vector3 = str_to_var(a["logs"][i]["rotation"])
		var s: Vector3 = str_to_var(b["logs"][i]["rotation"])
		if not p.is_equal_approx(q) or not Basis.from_euler(r).is_equal_approx(Basis.from_euler(s)):
			return false
	return true


func _validate_log_bounds() -> void:
	var visual := _source.find_child("StoveVisual",true,false) as StoveVisual
	for slot: int in visual._active_slots:
		var body: Node3D = visual._logs[slot].get_child(0)
		var mesh_node := body.get_child(0) as MeshInstance3D
		var vertices: PackedVector3Array = mesh_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var bottom: float = INF
		for vertex: Vector3 in vertices:
			var p: Vector3 = visual.to_local(mesh_node.to_global(vertex))
			_require(absf(p.x) <= StoveVisual.SIZE.x*0.5-StoveVisual.WALL+0.002,"A log penetrates the back/closed door plane")
			_require(absf(p.z) <= StoveVisual.SIZE.z*0.5-StoveVisual.WALL+0.002,"A log penetrates a firebox side")
			bottom = minf(bottom,p.y)
		_require(absf(bottom-(StoveVisual.LEG_H+StoveVisual.ASH_H+StoveVisual.WALL)) < 0.002,"A resting log floats or penetrates the floor")
	print("[stove] wood mesh bounds/floor contacts verified")
