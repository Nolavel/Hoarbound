class_name PackQuickShelf
extends Node3D

## Quick Access while the pack is open (3D inventory, stage 2): each quick pocket is a card beside the pack on
## the same gradient as the Quick Access cards (BG_frame.gdshader), with its item standing on it in 3D. Body
## pockets (coat, thigh, lid) stand in a column left of the pack, the pack's outside pockets (side pocket,
## sleeves, carabiners) right of it. A pocket takes an item by the inventory's own rule (size against max_size).

signal changed(slot: int)

const BG_FRAME: Shader = preload("res://assets/materials/Shaders/BG_frame.gdshader")
## Card side and the gap between cards, metres; how big an item stands on its card.
const CARD_M: float = 0.12
const GAP_M: float = 0.03
const ITEM_FIT_M: float = 0.095
## Column offset from the pack's side wall, metres; how far the card stands in front of the pack's back.
const COLUMN_OUT_M: float = 0.13
## An item on its card turns slowly so its shape reads, rad/s.
const SPIN: float = 0.6
## Card tints: hovered (warm yellow, as the active Quick Access card), filled, empty, refusing.
const ACTIVE: Color = Color(1.0, 0.82, 0.0, 0.9)
const FILLED: Color = Color(0.42, 0.42, 0.42, 0.82)
const EMPTY: Color = Color(0.3, 0.3, 0.3, 0.38)
const REFUSE: Color = Color(1.0, 0.25, 0.2, 0.9)
## Live cards: depth ahead of the camera (metres), card height as a share of the frame height, column x as a
## share of the half width, and the top row's y as a share of the half height.
const LIVE_DEPTH_M: float = 0.5
const LIVE_CARD_SHARE: float = 0.115
const LIVE_COLUMN_SHARE: float = 0.8
const LIVE_TOP_SHARE: float = 0.78
const FULL: StringName = &"INVENTORY_POCKET_FULL"
const TOO_SMALL: StringName = &"INVENTORY_POCKET_TOO_SMALL"

## Per slot: {"definition": EquipmentSlotDefinition, "item_id", "state", "card": MeshInstance3D, "label": Label3D,
## "visual": Node3D or null, "tint": Color}.
var slots: Array[Dictionary] = []
var camera: Camera3D
## Live mode (setup_live): the cards are Henry's real quick pockets (through the Hub), standing in two columns
## at the screen's sides, children of the camera; slots carry "path" and moves go through the Hub.
var hub: PlayerHubComponent
var _live: bool = false
var _pack: BackpackModel
## The gradient for the left column (fading toward the pack, rightward) and the right one (leftward).
var _frames: Array[SubViewport] = []


## Cards beside `pack` facing `view`, one per [garment item id, pocket id] in `body` (left) and `outside` (right).
func setup(pack: BackpackModel, view: Camera3D, body: Array, outside: Array) -> void:
	_pack = pack
	camera = view
	_frames = [_gradient_viewport(0), _gradient_viewport(1)]
	var columns: Array = [[body, -1.0], [outside, 1.0]]
	for column: Array in columns:
		var sources: Array = column[0]
		for row: int in sources.size():
			var definition: EquipmentSlotDefinition = _pocket(sources[row][0], sources[row][1])
			if definition == null:
				continue
			var at := Vector3(float(column[1]) * (BackpackModel.BODY.x * 0.5 + COLUMN_OUT_M),
				BackpackModel.BODY.y - CARD_M * 0.5 - float(row) * (CARD_M + GAP_M), BackpackModel.BODY.z * 0.6)
			slots.append(_card(definition, at, _frames[0 if float(column[1]) < 0.0 else 1]))
	_refresh_all()


## Live cards for `quick_hub`'s quick pockets, at the sides of `view`'s frame (body pockets left, the pack's
## outside pockets right), each the gradient card with the pocket's 3D item on it, no text.
func setup_live(quick_hub: PlayerHubComponent, view: Camera3D) -> void:
	hub = quick_hub
	camera = view
	_live = true
	_frames = [_gradient_viewport(0), _gradient_viewport(1)]
	var rows: Array[int] = [0, 0]
	for zone: Dictionary in hub.get_quick_access_zones():
		var path: StringName = zone["path"]
		var column: int = 1 if String(path).begins_with("pack" + EquipmentComponent.POCKET_SEPARATOR) else 0
		var slot: Dictionary = _card(null, Vector3.ZERO, _frames[1 - column])
		slot["path"] = path
		slot["column"] = column
		slot["row"] = rows[column]
		slot["item_id"] = zone["item_id"]
		rows[column] += 1
		slots.append(slot)
	if hub.equipment != null:
		hub.equipment.slot_changed.connect(func(_path: StringName, _id: StringName) -> void: refresh_live())
	_refresh_all()


## Re-reads every live pocket's item.
func refresh_live() -> void:
	if not _live or hub == null:
		return
	var by_path: Dictionary = {}
	for zone: Dictionary in hub.get_quick_access_zones():
		by_path[zone["path"]] = zone["item_id"]
	for k: int in slots.size():
		var now: StringName = by_path.get(slots[k]["path"], &"")
		if now != StringName(slots[k]["item_id"]):
			slots[k]["item_id"] = now
			_refresh(k)


## Live: moves slot k's item into the pack: it flies from its card into the opening, then the Hub moves it
## (the pack's straps take it in). False when the pocket is empty or the Hub refuses.
func send_to_pack(k: int, into: Vector3, seconds: float = 0.4) -> bool:
	var visual: Node3D = slots[k]["visual"]
	if not _live or visual == null:
		return false
	var flying: Node3D = visual.duplicate()
	var world: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	world.add_child(flying)
	flying.global_transform = visual.global_transform
	visual.visible = false
	var tween: Tween = flying.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(flying, ^"global_position", into, seconds)
	tween.parallel().tween_property(flying, ^"scale", flying.scale * 1.6, seconds)
	await tween.finished
	flying.queue_free()
	var path: StringName = slots[k]["path"]
	var refused: StringName = hub.move_to_pack(path)
	refresh_live()
	if refused != &"":
		if is_instance_valid(visual):
			visual.visible = true
		return false
	return true


## The slot whose card a world-space ray meets, or -1.
func pick(origin: Vector3, direction: Vector3) -> int:
	var best: float = INF
	var found: int = -1
	for k: int in slots.size():
		var card: MeshInstance3D = slots[k]["card"]
		var plane := Plane(card.global_basis.z, card.global_position)
		var hit: Variant = plane.intersects_ray(origin, direction)
		if hit == null:
			continue
		var local: Vector3 = card.global_transform.affine_inverse() * (hit as Vector3)
		if absf(local.x) <= CARD_M * 0.5 and absf(local.y) <= CARD_M * 0.5:
			var distance: float = origin.distance_to(hit)
			if distance < best:
				best = distance
				found = k
	return found


## Why slot k cannot take `item_id` now (FULL, TOO_SMALL), or &"" when it can.
func refusal(k: int, item_id: StringName) -> StringName:
	if StringName(slots[k]["item_id"]) != &"":
		return FULL
	var item: ItemResource = ItemCatalog.get_item(item_id)
	var definition: EquipmentSlotDefinition = slots[k]["definition"]
	if item == null or item.size_class > definition.max_size:
		return TOO_SMALL
	return &""


func put(k: int, item_id: StringName, state: Dictionary = {}) -> void:
	slots[k]["item_id"] = item_id
	slots[k]["state"] = state
	_refresh(k)
	changed.emit(k)


## Empties slot k: {"id", "state"}, or {} if it held nothing.
func take(k: int) -> Dictionary:
	var id: StringName = slots[k]["item_id"]
	if id == &"":
		return {}
	var out: Dictionary = {"id": id, "state": slots[k]["state"]}
	slots[k]["item_id"] = &""
	slots[k]["state"] = {}
	_refresh(k)
	changed.emit(k)
	return out


## Tints slot k's card: ACTIVE, REFUSE, or back to its filled/empty look with Color.TRANSPARENT.
func set_tint(k: int, colour: Color) -> void:
	for i: int in slots.size():
		var want: Color = colour if i == k and colour.a > 0.0 else (FILLED if StringName(slots[i]["item_id"]) != &"" else EMPTY)
		if slots[i]["tint"] != want:
			slots[i]["tint"] = want
			((slots[i]["card"] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = want


func visual_of(k: int) -> Node3D:
	return slots[k]["visual"]


func _process(delta: float) -> void:
	if camera == null:
		return
	if _live:
		_place_live()
	for slot: Dictionary in slots:
		var card: MeshInstance3D = slot["card"]
		if _live:
			var spinning: Node3D = slot["visual"]
			if spinning != null:
				spinning.rotate_y(SPIN * delta)
			continue
		## Cards lie flat on the screen, as the Quick Access cards do.
		card.global_basis = camera.global_basis.orthonormalized()
		var visual: Node3D = slot["visual"]
		if visual != null:
			visual.rotate_y(SPIN * delta)


## Live cards stand in camera space LIVE_DEPTH_M ahead, in a column at each side of the frame.
func _place_live() -> void:
	var view: Vector2 = camera.get_viewport().get_visible_rect().size
	var half_h: float = LIVE_DEPTH_M * tan(deg_to_rad(camera.fov) * 0.5)
	var half_w: float = half_h * view.x / maxf(view.y, 1.0)
	var size: float = half_h * 2.0 * LIVE_CARD_SHARE
	for slot: Dictionary in slots:
		var card: MeshInstance3D = slot["card"]
		var side: float = -1.0 if int(slot["column"]) == 0 else 1.0
		var at := Vector3(side * half_w * LIVE_COLUMN_SHARE, half_h * LIVE_TOP_SHARE - float(slot["row"]) * size * 1.18, -LIVE_DEPTH_M)
		card.global_transform = camera.global_transform * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size / CARD_M), at)


func _card(definition: EquipmentSlotDefinition, at: Vector3, frame: SubViewport) -> Dictionary:
	var card := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(CARD_M, CARD_M)
	card.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = frame.get_texture()
	material.albedo_color = EMPTY
	material.no_depth_test = false
	card.material_override = material
	card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(card)
	card.position = at
	if definition == null:
		return {"definition": null, "item_id": &"", "state": {}, "card": card, "label": null, "visual": null, "tint": EMPTY}
	var label := Label3D.new()
	var key: String = "POCKET_" + String(definition.id).to_upper()
	label.text = tr(key) if tr(key) != key else definition.display_name
	label.font_size = 32
	label.pixel_size = 0.00045
	label.modulate = Color(0.92, 0.92, 0.9, 0.85)
	label.outline_size = 8
	label.position = Vector3(0.0, -CARD_M * 0.5 - 0.008, 0.002)
	card.add_child(label)
	return {"definition": definition, "item_id": &"", "state": {}, "card": card, "label": label, "visual": null, "tint": EMPTY}


func _refresh_all() -> void:
	for k: int in slots.size():
		_refresh(k)


## Slot k's item stands on its card, scaled to fit it, turning slowly.
func _refresh(k: int) -> void:
	var slot: Dictionary = slots[k]
	var old: Node3D = slot["visual"]
	if old != null:
		old.queue_free()
		slot["visual"] = null
	var id: StringName = slot["item_id"]
	if id != &"":
		var holder := Node3D.new()
		var visual: Node3D = SurvivalItemVisual.make(id)
		var box: AABB = BackpackModel._local_bounds(visual)
		holder.add_child(visual)
		visual.position = -box.get_center()
		holder.scale = Vector3.ONE * (ITEM_FIT_M / maxf(box.size[box.size.max_axis_index()], 0.001))
		(slot["card"] as MeshInstance3D).add_child(holder)
		holder.position = Vector3(0.0, 0.0, CARD_M * 0.35)
		slot["visual"] = holder
	slot["tint"] = Color.TRANSPARENT
	set_tint(-1, Color.TRANSPARENT)


## The Quick Access gradient (BG_frame.gdshader) fading in `direction` (0 right, 1 left), drawn once in white;
## each card tints it.
func _gradient_viewport(direction: int) -> SubViewport:
	var view := SubViewport.new()
	view.size = Vector2i(128, 128)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = Vector2(128, 128)
	var material := ShaderMaterial.new()
	material.shader = BG_FRAME
	material.set_shader_parameter(&"base_color", Color.WHITE)
	material.set_shader_parameter(&"fade_direction", direction)
	material.set_shader_parameter(&"reveal", 1.0)
	rect.material = material
	view.add_child(rect)
	add_child(view)
	return view


static func _pocket(garment_id: StringName, pocket_id: StringName) -> EquipmentSlotDefinition:
	var item: ItemResource = ItemCatalog.get_item(garment_id)
	if item == null or item.garment == null:
		return null
	for pocket: EquipmentSlotDefinition in item.garment.pockets:
		if pocket.id == pocket_id:
			return pocket
	return null
