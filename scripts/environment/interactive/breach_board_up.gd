class_name BreachBoardUp
extends InteractiveArea

## F lays carried boards beside the opening. With the hammer equipped, F takes
## one staged board; camera aim moves its ghost and LMB nails it in place.

signal breach_boarded(breach: ShelterBreach)
signal board_placed(breach: ShelterBreach, coverage: float)
signal repair_refused(missing_item_id: StringName)

const BOARD_ID: StringName = &"boards"
const NAIL_ID: StringName = &"nails"
const NAILS_PER_BOARD: int = 2
const PLACE_ACTION: StringName = &"fire"
const CANCEL_ACTION: StringName = &"pause"
const MAX_BOARDING_DISTANCE: float = 2.2
const RAY_LENGTH: float = 8.0

const NO_BOARDS_KEY: String = "BREACH_REFUSED_NO_BOARDS"
const NEED_HAMMER_KEY: String = "BREACH_REFUSED_NO_HAMMER"
const NEED_NAILS_KEY: String = "BREACH_REFUSED_NO_NAILS"
const STAGED_KEY: String = "BREACH_BOARDS_STAGED"
const PLACE_HINT_KEY: String = "BREACH_BOARD_PLACE_HINT"
const SEALED_KEY: String = "BREACH_SEALED"
const GAP_KEY: String = "BREACH_GAP_REMAINS"

@export_group("Breach")
@export var breach: ShelterBreach

@export_group("Work time")
## One board placement pays game time even though the current LMB presentation is immediate.
@export_range(0.1, 30.0, 0.1) var board_time_cost_minutes: float = 1.0

var _inventory: InventoryComponent
var _placing: bool = false
var _preview: MeshInstance3D
var _preview_material: StandardMaterial3D
var _preview_y: float = 0.0
var _preview_valid: bool = false
var _offhand_board: Node3D


func _ready() -> void:
	if breach == null:
		breach = _find_breach()
	if interactive_mesh == null and breach != null:
		interactive_mesh = breach.boarded_visual as MeshInstance3D
	super()
	if breach != null:
		set_item_name(tr(breach.name_key))
	set_description("")


func _process(_delta: float) -> void:
	if _placing:
		if _hammer() == null or not _hammer().is_holding():
			_cancel_placement()
			return
		_update_preview()


func _input(event: InputEvent) -> void:
	if not _placing:
		return
	if event.is_action_pressed(CANCEL_ACTION):
		_cancel_placement()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(PLACE_ACTION) and not event.is_echo():
		_commit_board()
		get_viewport().set_input_as_handled()


func can_interact() -> bool:
	return super() and breach != null and breach.boardable and (not breach.is_boarded() or breach.get_staged_boards() > 0)


func is_placing_board() -> bool:
	return _placing


## The entire visible aperture stays selectable as the player aims above/below its centre.
func is_aim_on_opening(from: Vector3, direction: Vector3) -> bool:
	if breach == null:
		return false
	var normal: Vector3 = breach.get_facing()
	var denominator: float = normal.dot(direction)
	if absf(denominator) < 0.001:
		return false
	var distance_on_ray: float = normal.dot(breach.global_position - from) / denominator
	if distance_on_ray <= 0 or distance_on_ray > RAY_LENGTH:
		return false
	var point: Vector3 = breach.to_local(from + direction * distance_on_ray)
	return absf(point.x) <= breach.opening_width_m * 0.5 and absf(point.y) <= breach.opening_height_m * 0.5


func accepts_focus(from: Vector3, direction: Vector3) -> bool:
	return is_aim_on_opening(from, direction)


func _on_interaction_performed() -> void:
	if breach == null or not breach.boardable or _placing:
		return
	var inventory: InventoryComponent = _get_inventory()
	if inventory == null:
		return
	var carried_boards: int = inventory.get_count(BOARD_ID)
	if carried_boards > 0:
		for _i: int in range(carried_boards):
			inventory.try_remove(BOARD_ID)
		breach.stage_boards(carried_boards)
		show_message(tr(STAGED_KEY) % breach.get_staged_boards())
		return
	if breach.is_boarded():
		_recover_staged_boards()
		return
	if breach.get_staged_boards() <= 0:
		repair_refused.emit(BOARD_ID)
		show_message(tr(NO_BOARDS_KEY))
		return
	var hammer: HammerComponent = _hammer()
	if hammer != null and not hammer.is_holding():
		_equip_hammer(hammer)
	if hammer == null or not hammer.is_holding():
		repair_refused.emit(&"hammer")
		show_message(tr(NEED_HAMMER_KEY))
		return
	if inventory.get_count(NAIL_ID) < NAILS_PER_BOARD:
		repair_refused.emit(NAIL_ID)
		show_message(tr(NEED_NAILS_KEY))
		return
	_begin_placement()


func _equip_hammer(hammer: HammerComponent) -> void:
	if hammer.can_use(&"hammer"):
		hammer.use(&"hammer")
		return
	var player: Node = get_tree().get_first_node_in_group(&"player")
	var equipment: EquipmentComponent = player.get_node_or_null(^"EquipmentComponent") as EquipmentComponent if player != null else null
	if equipment != null:
		for pocket: Dictionary in equipment.get_available_pockets():
			if pocket["item_id"] == &"hammer":
				hammer.equip_from_zone(&"hammer", equipment.pocket_path(pocket["body_slot"], pocket["pocket"]))
				return


func _get_interaction_text() -> String:
	var key: String = "BREACH_STAGE_ACTION"
	var inventory: InventoryComponent = _get_inventory()
	var detail: String = tr(NO_BOARDS_KEY)
	if _placing:
		return "[LMB] %s\n%s" % [tr("BREACH_NAIL_ACTION"), tr(PLACE_HINT_KEY)]
	if inventory != null and inventory.get_count(BOARD_ID) > 0:
		detail = tr("BREACH_CARRIED_DETAIL") % inventory.get_count(BOARD_ID)
	elif breach != null and breach.get_staged_boards() > 0:
		key = "BREACH_TAKE_ACTION"
		detail = tr(STAGED_KEY) % breach.get_staged_boards()
		if inventory == null or inventory.get_count(NAIL_ID) < NAILS_PER_BOARD:
			detail = tr(NEED_NAILS_KEY)
		if breach.is_boarded():
			key = "BREACH_RECOVER_ACTION"
	set_item_name(tr(key))
	set_description(detail)
	return "[%s] %s" % [_interact_key_label(), tr(key)]


func _begin_placement() -> void:
	if _placing or breach == null:
		return
	var animation: HenryUALAnimation = _animation()
	if animation == null or animation.get_offhand_socket() == null:
		return
	_placing = true
	add_to_group(&"active_board_placement")
	_preview = MeshInstance3D.new()
	_preview.name = "BoardPreview"
	var mesh := BoxMesh.new()
	mesh.size = breach.get_board_size()
	_preview_material = StandardMaterial3D.new()
	_preview_material.albedo_color = Color(0.55, 0.86, 0.55, 0.38)
	_preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = _preview_material
	_preview.mesh = mesh
	breach.add_child(_preview)
	_offhand_board = _make_hand_board()
	animation.hold_in_offhand(_offhand_board)
	show_message(tr(PLACE_HINT_KEY))
	_update_preview()


func _update_preview() -> void:
	if not _placing or breach == null or not is_instance_valid(_preview):
		return
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	var viewport := get_viewport()
	var camera: Camera3D = viewport.get_camera_3d() if viewport != null else null
	_preview_valid = false
	_preview.visible = false
	if player == null or camera == null:
		_preview_y = 0.0
		_preview.position = Vector3(0.0, _preview_y, 0.12)
		return
	var from: Vector3 = TpsCamera.aim_origin(camera)
	var direction: Vector3 = TpsCamera.aim_direction(camera)
	var normal: Vector3 = breach.get_facing()
	var denom: float = normal.dot(direction)
	if absf(denom) < 0.001:
		return
	var distance_on_ray: float = normal.dot(breach.global_position - from) / denom
	if distance_on_ray <= 0.0 or distance_on_ray > RAY_LENGTH:
		return
	var hit: Vector3 = from + direction * distance_on_ray
	var local: Vector3 = breach.to_local(hit)
	var limit: float = maxf(0.0, breach.opening_height_m * 0.5 - breach.board_height_m * 0.5)
	_preview_y = clampf(local.y, -limit, limit)
	_preview.position = Vector3(0.0, _preview_y, 0.12)
	_preview.visible = true
	var close_enough: bool = player.global_position.distance_to(breach.global_position) <= MAX_BOARDING_DISTANCE
	var within_width: bool = absf(local.x) <= breach.opening_width_m * 0.5 + 0.15
	var within_height: bool = absf(local.y) <= breach.opening_height_m * 0.5 + 0.15
	var query := PhysicsRayQueryParameters3D.create(from, hit - direction * 0.04)
	query.exclude = [(player as CollisionObject3D).get_rid()]
	query.collide_with_areas = false
	var unobstructed: bool = get_world_3d().direct_space_state.intersect_ray(query).is_empty()
	_preview_valid = close_enough and within_width and within_height and unobstructed
	if _preview_material != null:
		_preview_material.albedo_color = Color(0.55, 0.86, 0.55, 0.38) if _preview_valid else Color(0.95, 0.28, 0.22, 0.38)


func _commit_board() -> void:
	if not _placing or breach == null:
		return
	_update_preview()
	if not _preview_valid:
		return
	var inventory: InventoryComponent = _get_inventory()
	var hammer: HammerComponent = _hammer()
	if inventory == null or hammer == null or not hammer.is_holding():
		_cancel_placement()
		return
	if breach.get_staged_boards() <= 0 or inventory.get_count(NAIL_ID) < NAILS_PER_BOARD:
		_cancel_placement()
		return
	var actions: TimeCostedActionSystem = _actions()
	if actions != null and actions.is_active():
		return
	if not inventory.try_remove(NAIL_ID) or not inventory.try_remove(NAIL_ID):
		_cancel_placement()
		return
	if not breach.take_staged_board():
		inventory.try_add(ItemCatalog.get_item(NAIL_ID))
		inventory.try_add(ItemCatalog.get_item(NAIL_ID))
		_cancel_placement()
		return

	var paid: bool = true
	if actions != null:
		var request := TimeActionRequest.new()
		request.action_id = StringName("board_window:%d" % get_instance_id())
		request.duration_hours = board_time_cost_minutes / 60.0
		request.reason = &"board_window"
		request.actor = get_tree().get_first_node_in_group(&"player")
		request.target = breach
		request.player_mode = _resolve_player_mode(&"WORKING")
		request.interruptible = false
		var result: Dictionary = actions.run_to_completion(request)
		paid = bool(result.get("completed", false))
	if not paid:
		inventory.try_add(ItemCatalog.get_item(NAIL_ID))
		inventory.try_add(ItemCatalog.get_item(NAIL_ID))
		breach.return_staged_board()
		return

	breach.place_board(_preview_y)
	hammer.swing()
	board_placed.emit(breach, breach.get_coverage_fraction())
	var sealed: bool = breach.is_boarded()
	_clear_placement_visuals()
	if sealed:
		show_message(tr(SEALED_KEY))
		breach_boarded.emit(breach)
	else:
		show_message(tr(GAP_KEY) % int(round(breach.get_gap_fraction() * 100.0)))


func _cancel_placement() -> void:
	_clear_placement_visuals()


func _clear_placement_visuals() -> void:
	_placing = false
	if is_in_group(&"active_board_placement"):
		remove_from_group(&"active_board_placement")
	if is_instance_valid(_preview):
		_preview.queue_free()
	_preview = null
	_preview_material = null
	_preview_valid = false
	var animation: HenryUALAnimation = _animation()
	if animation != null:
		animation.release_offhand()
	if is_instance_valid(_offhand_board):
		_offhand_board.queue_free()
	_offhand_board = null


func _exit_tree() -> void:
	_clear_placement_visuals()


func get_interaction_prompt_data() -> Dictionary:
	var data: Dictionary = super()
	if _placing:
		data["key"] = "LMB"
		data["action"] = tr("BREACH_NAIL_ACTION")
		data["detail"] = tr(PLACE_HINT_KEY)
	return data


func _recover_staged_boards() -> void:
	var inventory: InventoryComponent = _get_inventory()
	if inventory == null or breach == null:
		return
	var hammer: HammerComponent = _hammer()
	if hammer != null and hammer.is_holding():
		hammer.put_away()
	var item: ItemResource = ItemCatalog.get_item(BOARD_ID)
	while breach.get_staged_boards() > 0 and inventory.get_add_refusal(item) == &"":
		if not inventory.try_add(item):
			break
		breach.take_staged_board()


func _make_hand_board() -> Node3D:
	var root := Node3D.new()
	root.name = "SelectedBoard"
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.85, 0.055, 0.16)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.42, 0.30, 0.19)
	material.roughness = 0.95
	mesh.material = material
	mesh_instance.mesh = mesh
	root.add_child(mesh_instance)
	return root


func _resolve_player_mode(mode_name: StringName) -> int:
	var state: Node = get_node_or_null(^"/root/PlayerState")
	if state == null:
		return -1
	var script: Script = state.get_script() as Script
	if script == null:
		return -1
	var constants: Dictionary = script.get_script_constant_map()
	var modes: Dictionary = constants.get("Mode", {})
	return int(modes.get(String(mode_name), -1))


func _actions() -> TimeCostedActionSystem:
	return TimeCostedActionSystem.find(get_tree()) if is_inside_tree() else null


func _get_inventory() -> InventoryComponent:
	if is_instance_valid(_inventory):
		return _inventory
	var player: Node = get_tree().get_first_node_in_group("player")
	_inventory = InventoryComponent.find_in(player)
	return _inventory


func _hammer() -> HammerComponent:
	var player: Node = get_tree().get_first_node_in_group(&"player")
	return player.get_node_or_null(^"HammerComponent") as HammerComponent if player != null else null


func _animation() -> HenryUALAnimation:
	var player: Node = get_tree().get_first_node_in_group(&"player")
	return player.get(&"animation_component") as HenryUALAnimation if player != null else null


func _find_breach() -> ShelterBreach:
	var parent_breach := get_parent() as ShelterBreach
	if parent_breach != null:
		return parent_breach
	if get_parent() == null:
		return null
	for sibling: Node in get_parent().get_children():
		var candidate := sibling as ShelterBreach
		if candidate != null:
			return candidate
	return null
