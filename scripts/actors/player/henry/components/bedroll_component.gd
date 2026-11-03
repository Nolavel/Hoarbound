class_name BedrollComponent
extends Node

## Use in the Hub starts a world-space placement preview. The camera-centre ray
## chooses the ground; green means the whole bedroll fits in a warm room, red means it does not.
## Laid, it unrolls from its head to its foot.

signal bedroll_laid(bedroll: Node3D)
signal bedroll_packed

const CONFIRM_ACTION: StringName = &"interact"
const CANCEL_ACTION: StringName = &"pause"
const PLACE_HINT_KEY: String = "BEDROLL_PLACE_HINT"
const BLOCKED_HINT_KEY: String = "BEDROLL_PLACE_BLOCKED"
const COLD_HINT_KEY: String = "BEDROLL_TOO_COLD"
## Seconds the roll takes to unroll, and the rolled bundle's radius at the start.
const UNROLL_S: float = 1.2
const ROLL_RADIUS: float = 0.17
const PLACE_DISTANCE: float = 1.3
const MAX_PLACE_DISTANCE: float = 3.0
const RAY_LENGTH: float = 6.0
const MAX_SLOPE_DEG: float = 14.0
const BEDROLL_SIZE: Vector3 = Vector3(0.75, 0.005, 1.9)
const VALID_COLOR: Color = Color(0.45, 0.9, 0.55, 0.35)
const INVALID_COLOR: Color = Color(0.95, 0.28, 0.22, 0.35)
const ITEM_ID: StringName = &"bedroll"
const INTERACTIVE_SCENE: String = "res://scenes/environment/interactive/InteractiveArea.tscn"
const SLEEP_SPOT_SCRIPT: String = "res://scripts/environment/interactive/sleep_spot.gd"
const PICKUP_SCRIPT: String = "res://scripts/environment/interactive/item_pickup.gd"
const PACK_KEY: String = "BEDROLL_PACK"
const BEDROLL_OPEN: PackedScene = preload("res://assets/items/bedroll/bedroll_open.scn")

@export var inventory: InventoryComponent

var _laid: Node3D
var _preview: Node3D
var _preview_material: StandardMaterial3D
var _preview_hint: Label3D
var _preview_valid: bool = false
var _preview_cold: bool = false


func _ready() -> void:
	add_to_group(&"saveable")
	if inventory == null:
		inventory = InventoryComponent.find_in(get_parent())


func _input(event: InputEvent) -> void:
	if not is_placing():
		return
	if event.is_action_pressed(CONFIRM_ACTION) and not event.is_echo():
		confirm_placement()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(CANCEL_ACTION):
		cancel_placement()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if is_placing():
		_update_preview()


func can_use(item_id: StringName) -> bool:
	return (
		item_id == ITEM_ID
		and not is_laid()
		and not is_placing()
		and inventory != null
		and inventory.has_item(item_id)
		and _can_free_hands()
	)


func use(item_id: StringName) -> bool:
	return can_use(item_id) and begin_placement()


func is_placing() -> bool:
	return is_instance_valid(_preview)


func is_preview_valid() -> bool:
	return is_placing() and _preview_valid


func begin_placement() -> bool:
	if is_placing() or is_laid() or inventory == null or not inventory.has_item(ITEM_ID):
		return false
	if not _prepare_hands():
		return false
	var world: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	_preview = Node3D.new()
	_preview.name = "BedrollPreview"
	world.add_child(_preview)
	_preview_material = StandardMaterial3D.new()
	_preview_material.albedo_color = VALID_COLOR
	_preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var pad := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = BEDROLL_SIZE
	box.material = _preview_material
	pad.mesh = box
	pad.position = Vector3(0.0, BEDROLL_SIZE.y * 0.5, 0.0)
	_preview.add_child(pad)
	_preview_hint = Label3D.new()
	_preview_hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_preview_hint.font_size = 28
	_preview_hint.position = Vector3(0.0, 0.5, 0.0)
	_preview.add_child(_preview_hint)
	_update_preview()
	return true


func confirm_placement() -> bool:
	if not is_placing() or not _preview_valid:
		return false
	var xf: Transform3D = _preview.global_transform
	_clear_preview()
	return _lay_at(xf)


func cancel_placement() -> void:
	_clear_preview()


func _clear_preview() -> void:
	if is_instance_valid(_preview):
		_preview.queue_free()
	_preview = null
	_preview_material = null
	_preview_hint = null
	_preview_valid = false


func _update_preview() -> void:
	var candidate: Dictionary = _raycast_placement()
	_preview.global_transform = candidate["transform"]
	_preview_valid = bool(candidate["valid"])
	_preview_cold = bool(candidate.get("cold", false))
	if _preview_material != null:
		_preview_material.albedo_color = VALID_COLOR if _preview_valid else INVALID_COLOR
	if is_instance_valid(_preview_hint):
		_preview_hint.text = tr(PLACE_HINT_KEY if _preview_valid else (COLD_HINT_KEY if _preview_cold else BLOCKED_HINT_KEY))


## Camera-centre ray to the floor. In headless tests with no camera, the old
## straight-ahead transform remains a deterministic fallback.
func _raycast_placement() -> Dictionary:
	var body := get_parent() as CharacterBody3D
	var viewport := get_viewport()
	var camera: Camera3D = viewport.get_camera_3d() if viewport != null else null
	if body == null or not body.is_inside_tree() or camera == null:
		return {"transform": _front_transform(), "valid": true}
	var from: Vector3 = TpsCamera.aim_origin(camera)
	var to: Vector3 = from + TpsCamera.aim_direction(camera) * RAY_LENGTH
	var ray := PhysicsRayQueryParameters3D.create(from, to)
	ray.collide_with_areas = false
	ray.collide_with_bodies = true
	ray.exclude = [body.get_rid()]
	var space := body.get_world_3d().direct_space_state
	var hit: Dictionary = space.intersect_ray(ray)
	if hit.is_empty():
		return {"transform": _front_transform(), "valid": false}
	var point: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"].normalized()
	var facing: Vector3 = -body.global_transform.basis.z
	facing.y = 0.0
	facing = facing.normalized() if facing.length() > 0.01 else Vector3.FORWARD
	var xf := Transform3D(Basis(Vector3.UP, atan2(facing.x, facing.z)), point + normal * 0.025)
	var slope_ok: bool = normal.dot(Vector3.UP) >= cos(deg_to_rad(MAX_SLOPE_DEG))
	var distance_ok: bool = body.global_position.distance_to(point) <= MAX_PLACE_DISTANCE
	var height_ok: bool = absf(point.y - body.global_position.y) <= 0.65
	var clearance := BoxShape3D.new()
	clearance.size = Vector3(BEDROLL_SIZE.x * 0.94, 0.14, BEDROLL_SIZE.z * 0.94)
	var shape_query := PhysicsShapeQueryParameters3D.new()
	shape_query.shape = clearance
	shape_query.transform = Transform3D(xf.basis, xf.origin + Vector3.UP * 0.09)
	shape_query.collide_with_areas = false
	shape_query.collide_with_bodies = true
	var excluded: Array[RID] = [body.get_rid()]
	var collider := hit.get("collider") as CollisionObject3D
	if collider != null:
		excluded.append(collider.get_rid())
	shape_query.exclude = excluded
	var clear: bool = space.intersect_shape(shape_query, 8).is_empty()
	## A bedroll is for sleeping where it is warm: indoors, in a heated room.
	var warm: bool = ThermalZone.is_warm_at(body.get_world_3d(), point + Vector3.UP * 0.3)
	return {"transform": xf, "valid": slope_ok and distance_ok and height_ok and clear and warm, "cold": not warm}


func _front_transform() -> Transform3D:
	var body := get_parent() as Node3D
	if body == null:
		return Transform3D.IDENTITY
	var facing: Vector3 = -body.global_transform.basis.z
	facing.y = 0.0
	facing = facing.normalized() if facing.length() > 0.01 else Vector3.FORWARD
	return Transform3D(Basis(Vector3.UP, atan2(facing.x, facing.z)), body.global_position + facing * PLACE_DISTANCE)


func _can_free_hands() -> bool:
	var body: Node = get_parent()
	if body == null:
		return false
	var carry := body.get_node_or_null(^"CarryComponent") as CarryComponent
	if carry != null and carry.is_carrying():
		return false
	var light := body.get_node_or_null(^"HeldLightComponent") as HeldLightComponent
	return light == null or not light.is_burning()


func _prepare_hands() -> bool:
	if not _can_free_hands():
		return false
	var body: Node = get_parent()
	for child: Node in body.get_children():
		if not child.has_method(&"is_holding") or not bool(child.call(&"is_holding")):
			continue
		if child.has_method(&"put_away_unlit") and bool(child.call(&"put_away_unlit")):
			continue
		if child.has_method(&"put_away") and bool(child.call(&"put_away")):
			continue
		return false
	return true


func is_laid() -> bool:
	return is_instance_valid(_laid)


func get_laid_bedroll() -> Node3D:
	return _laid if is_laid() else null


## Compatibility seam for tests/tools; real play enters through the raycast preview.
func lay_down() -> bool:
	return _lay_at(_front_transform())


func _lay_at(xf: Transform3D) -> bool:
	var body := get_parent() as CharacterBody3D
	if is_laid() or body == null or inventory == null or body.velocity.y < -0.5:
		return false
	if not inventory.try_remove(ITEM_ID):
		return false
	_spawn(xf)
	if body.has_method(&"play_action_animation"):
		body.call(&"play_action_animation", &"fix")
	return true


func _spawn(xf: Transform3D, unroll: bool = true) -> void:
	var roll := Node3D.new()
	roll.name = "LaidBedroll"
	var world: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	world.add_child(roll)
	roll.global_transform = xf
	var visual := BEDROLL_OPEN.instantiate() as Node3D
	visual.name = "OpenMat"
	roll.add_child(visual)
	StylizedEnvironmentMaterial.apply_to_tree(visual)
	var pad := visual.find_child("Bedroll_Continuous_Sheet_Static", true, false) as MeshInstance3D
	if pad == null:
		push_error("Bedroll open scene has no continuous sheet mesh")
		roll.queue_free()
		return
	if unroll:
		_unroll(roll, visual, pad)
	_prompt(roll, "Sleep", SLEEP_SPOT_SCRIPT, Vector3(0.6, 0.0, 0.2), Vector3(1.0, 1.4, 1.4), pad, {})
	var pack: Node3D = _prompt(roll, "Pack", PICKUP_SCRIPT, Vector3(0.0, 0.0, -1.2), Vector3(0.9, 1.2, 0.7), pad,
		{&"item_id": ITEM_ID})
	pack.connect(&"picked_up", _on_packed)
	_laid = roll
	(pack as InteractiveArea).set_item_name(tr(PACK_KEY))
	bedroll_laid.emit(roll)


## The bedroll unrolls: the mat spreads from its head end to its foot while a roll of the same cloth,
## thinning as it goes, travels ahead of it; at the end only the open mat is left.
func _unroll(roll: Node3D, visual: Node3D, pad: MeshInstance3D) -> void:
	var box: AABB = pad.get_aabb()
	var to_roll: Transform3D = roll.global_transform.affine_inverse() * pad.global_transform
	var head_z: float = (to_roll * box.position).z
	var foot_z: float = (to_roll * (box.position + box.size)).z
	## The mat grows from its head end: a pivot there scales it along its length.
	var pivot := Node3D.new()
	pivot.name = "Unroll"
	roll.add_child(pivot)
	pivot.position = Vector3(0.0, 0.0, head_z)
	visual.reparent(pivot, false)
	visual.position.z -= head_z
	var bundle := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = ROLL_RADIUS
	cylinder.bottom_radius = ROLL_RADIUS
	cylinder.height = BEDROLL_SIZE.x
	cylinder.material = pad.get_active_material(0)
	bundle.mesh = cylinder
	roll.add_child(bundle)
	var spread := func(t: float) -> void:
		pivot.scale = Vector3(1.0, 1.0, maxf(t, 0.001))
		var r: float = lerpf(ROLL_RADIUS, 0.02, t)
		bundle.transform = Transform3D(Basis(Vector3.BACK, PI * 0.5).scaled(Vector3(r / ROLL_RADIUS, 1.0, r / ROLL_RADIUS)),
			Vector3(0.0, r, lerpf(head_z, foot_z, t)))
	spread.call(0.0)
	var tween := roll.create_tween()
	tween.tween_method(spread, 0.0, 1.0, UNROLL_S).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(bundle.queue_free)


func _prompt(parent: Node3D, node_name: String, script_path: String, pos: Vector3, size: Vector3,
		mesh: MeshInstance3D, props: Dictionary) -> Node3D:
	var prompt: Node3D = (load(INTERACTIVE_SCENE) as PackedScene).instantiate()
	prompt.name = node_name
	prompt.set_script(load(script_path))
	for key: StringName in props:
		prompt.set(key, props[key])
	prompt.set(&"interactable_scene", null)
	prompt.set(&"interactive_mesh", mesh)
	prompt.position = pos
	var col := prompt.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	if col != null:
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
	parent.add_child(prompt)
	return prompt


func _on_packed(_item_id: StringName, _count: int) -> void:
	if is_laid():
		_laid.queue_free()
	_laid = null
	bedroll_packed.emit()


func get_save_key() -> StringName:
	return &"bedroll"


func get_save_data() -> Dictionary:
	if not is_laid():
		return {}
	var xf: Transform3D = _laid.global_transform
	return {"x": xf.origin.x, "y": xf.origin.y, "z": xf.origin.z,
		"yaw": xf.basis.get_euler().y}


func load_save_data(data: Dictionary) -> void:
	if is_laid():
		_laid.queue_free()
		_laid = null
	if data.has("x"):
		var origin := Vector3(float(data["x"]), float(data["y"]), float(data["z"]))
		_spawn(Transform3D(Basis(Vector3.UP, float(data.get("yaw", 0.0))), origin), false)
