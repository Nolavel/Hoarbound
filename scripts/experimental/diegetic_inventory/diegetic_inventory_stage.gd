class_name DiegeticInventoryStage
extends Node3D

## Issue #203 preparation stage. This intentionally implements no backpack packing.
## It isolates production Henry, the production TPS camera, the real shelter meal
## table and real production pickup visuals so item handling can be judged before
## the actual diegetic-inventory interaction is written.
##
## Focus framing below is LAB-ONLY. It changes only this scene instance's camera
## parameters; production TpsCamera/TpsInteractionFraming defaults are untouched.

const FIRST_EXIT_SOURCE: PackedScene = preload("res://scenes/world/first_exit/first_exit_blockout.tscn")
const ITEM_NAMES: Array[StringName] = [
	&"FlaskShelterTest",
	&"PineappleShelterTest",
	&"StewShelterTest",
	&"HammerShelter",
]
const ITEM_POSITIONS: Array[Vector3] = [
	Vector3(-0.17, MealTable.TOP_Y + 0.02, -0.08),
	Vector3(0.00, MealTable.TOP_Y + 0.02, -0.08),
	Vector3(0.16, MealTable.TOP_Y + 0.02, -0.07),
	Vector3(0.00, MealTable.TOP_Y + 0.035, 0.11),
]

## Camera experiment: focus only after the centre-ray has held a nearby item.
const FOCUS_DISTANCE_M: float = 1.95
const FOCUS_DWELL_S: float = 0.16
const FOCUS_RELEASE_HOLD_S: float = 0.28
const FOCUS_IN_RATE: float = 3.8
const FOCUS_OUT_RATE: float = 2.4
const FOCUS_NEAR_DISTANCE: float = 0.88
const FOCUS_FAR_DISTANCE: float = 2.15

@onready var player: Player = $Player
@onready var camera: TpsCamera = $PlayerCamera
@onready var stage_items: Node3D = $StageItems

var table: MealTable
var items: Array[ItemPickup] = []
var focus_weight: float = 0.0

var _base_near_distance: float = 0.95
var _base_far_distance: float = 3.0
var _focus_candidate: ItemPickup
var _focus_target: ItemPickup
var _candidate_time: float = 0.0
var _release_hold: float = 0.0
var _interaction_framing: TpsInteractionFraming


func _ready() -> void:
	## Apply the lab overlay before the production camera computes its rig.
	process_priority = -20
	camera.player = player
	_base_near_distance = camera.near_distance
	_base_far_distance = camera.far_distance
	_disable_player_ui(player)
	_extract_production_props()
	_configure_stage_only_camera()
	prepare_capture_pose(0)


func _process(delta: float) -> void:
	_update_item_focus(delta)
	var wanted: float = 1.0 if is_instance_valid(_focus_target) else 0.0
	var rate: float = FOCUS_IN_RATE if wanted > focus_weight else FOCUS_OUT_RATE
	focus_weight = move_toward(focus_weight, wanted, maxf(delta, 0.0) * rate)

	## Only the scene instance is changed. TpsCamera still owns smoothing, collision,
	## passage handling and the final physical rig.
	camera.near_distance = lerpf(_base_near_distance, FOCUS_NEAR_DISTANCE, focus_weight)
	camera.far_distance = lerpf(_base_far_distance, FOCUS_FAR_DISTANCE, focus_weight)


## Three viewpoints, all produced by the shipping TPS camera rather than a free
## capture camera. The player stays a normal production Player when this scene is
## opened interactively in Godot.
func prepare_capture_pose(index: int) -> void:
	var positions: Array[Vector3] = [
		Vector3(0.0, 1.0, 2.45),
		Vector3(0.72, 1.0, 1.62),
		Vector3(-0.90, 1.0, 1.85),
	]
	var pitches: Array[float] = [-12.0, -21.0, -18.0]
	index = clampi(index, 0, positions.size() - 1)
	player.global_position = positions[index]
	player.velocity = Vector3.ZERO
	var yaw: float = _table_yaw()
	player.global_rotation.y = yaw
	player.reset_physics_interpolation()
	camera.set_look(yaw, pitches[index])
	if camera.has_method(&"snap_to_target"):
		camera.call(&"snap_to_target")


## Starting pose for the 6-second camera experiment. Henry approaches under the
## normal production controller; no teleport is used once capture begins.
func prepare_focus_demo() -> void:
	_reset_focus()
	player.global_position = Vector3(0.72, 1.0, 3.05)
	player.velocity = Vector3.ZERO
	var yaw: float = _table_yaw()
	player.global_rotation.y = yaw
	player.reset_physics_interpolation()
	camera.set_look(yaw, -10.0)
	if camera.has_method(&"snap_to_target"):
		camera.call(&"snap_to_target")


## The capture driver changes only the player's control look. The camera is never
## orbited around Henry by the experiment itself.
func set_demo_look(yaw_offset_deg: float, pitch_deg: float) -> void:
	camera.set_look(_table_yaw() + deg_to_rad(yaw_offset_deg), pitch_deg)


func get_focus_target_id() -> StringName:
	return _focus_target.item_id if is_instance_valid(_focus_target) else &""


func _configure_stage_only_camera() -> void:
	camera.auto_recenter = false
	camera.whisker_max_deg = 0.0
	camera.assist_max_yaw_deg = 0.0
	camera.close_in_rate = 4.5
	camera.open_out_rate = 2.2
	_interaction_framing = camera.get_node_or_null(^"InteractionFraming") as TpsInteractionFraming
	if _interaction_framing != null:
		## More legible than production defaults so the experiment clearly shows
		## whether physical shoulder clearing helps without any automatic orbit.
		_interaction_framing.max_shoulder_offset = 1.22
		_interaction_framing.screen_clearance_fraction = 0.16
		_interaction_framing.vertical_window_fraction = 0.34
		_interaction_framing.swap_threshold = 0.90
		_interaction_framing.target_hold_seconds = 0.30


func _update_item_focus(delta: float) -> void:
	var interact := player.get_node_or_null(^"InteractComponent") as InteractComponent
	var live := interact.current_target as ItemPickup if interact != null else null
	if live != null and (not items.has(live) or _flat_distance_to(live) > FOCUS_DISTANCE_M):
		live = null

	if live != _focus_candidate:
		_focus_candidate = live
		_candidate_time = 0.0
	elif is_instance_valid(live):
		_candidate_time += maxf(delta, 0.0)

	if is_instance_valid(live) and _candidate_time >= FOCUS_DWELL_S:
		_focus_target = live
		_release_hold = FOCUS_RELEASE_HOLD_S
		return

	if is_instance_valid(_focus_target) and _release_hold > 0.0:
		_release_hold = maxf(0.0, _release_hold - maxf(delta, 0.0))
		return

	_focus_target = null


func _flat_distance_to(node: Node3D) -> float:
	return Vector2(player.global_position.x, player.global_position.z).distance_to(
		Vector2(node.global_position.x, node.global_position.z)
	)


func _table_yaw() -> float:
	var target: Vector3 = table.global_position if table != null else Vector3.ZERO
	var heading: Vector3 = target - player.global_position
	heading.y = 0.0
	if heading.length_squared() < 0.001:
		heading = Vector3.FORWARD * -1.0
	heading = heading.normalized()
	return atan2(-heading.x, -heading.z)


func _reset_focus() -> void:
	_focus_candidate = null
	_focus_target = null
	_candidate_time = 0.0
	_release_hold = 0.0
	focus_weight = 0.0
	camera.near_distance = _base_near_distance
	camera.far_distance = _base_far_distance


func _extract_production_props() -> void:
	var source := FIRST_EXIT_SOURCE.instantiate() as Node3D
	add_child(source)
	var source_table := source.find_child("MealTable", true, false) as MealTable
	if source_table == null:
		push_error("diegetic inventory stage: production MealTable not found")
		return
	source_table.reparent(stage_items, false)
	source_table.transform = Transform3D.IDENTITY
	table = source_table

	for i: int in range(ITEM_NAMES.size()):
		var pickup := source.find_child(String(ITEM_NAMES[i]), true, false) as ItemPickup
		if pickup == null:
			push_error("diegetic inventory stage: production pickup missing: %s" % ITEM_NAMES[i])
			continue
		pickup.reparent(stage_items, false)
		pickup.position = ITEM_POSITIONS[i]
		pickup.rotation = Vector3.ZERO
		items.append(pickup)

	## Everything else in the generated First Exit blockout is deliberately left
	## out. The table and pickups above are the exact production nodes/scripts.
	source.queue_free()


func _disable_player_ui(node: Node) -> void:
	for child: Node in node.get_children():
		if child is CanvasItem:
			(child as CanvasItem).visible = false
			## Production HUD scripts (notably MouseCursorUI) may set visible=true
			## every frame. Stop only UI processing in this clean staging scene;
			## Henry movement, camera and interaction components remain untouched.
			child.process_mode = Node.PROCESS_MODE_DISABLED
		elif child is CanvasLayer:
			(child as CanvasLayer).visible = false
			child.process_mode = Node.PROCESS_MODE_DISABLED
		_disable_player_ui(child)
