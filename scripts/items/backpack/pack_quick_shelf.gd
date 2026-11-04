class_name PackQuickShelf
extends Node3D

## Quick Access while Henry holds the pack open (3D inventory): each of his real quick pockets is a card on the
## Quick Access gradient (BG_frame.gdshader) with its 3D item standing on it, no text. The cards stand in camera
## space in a column at each side of the frame, clear of the pack: body pockets left, the pack's outside
## pockets right. Moves go through the Hub, so what the cards show is always the equipment's own state.

const BG_FRAME: Shader = preload("res://assets/materials/Shaders/BG_frame.gdshader")
## A card's side in its own space, and how big its item stands on it (shares of that side).
const CARD_M: float = 0.1
const ITEM_FIT: float = 0.8
## An item on its card turns slowly so its shape reads, rad/s.
const SPIN: float = 0.6
## Cards: depth ahead of the camera (metres), card height as a share of the frame height, column x as a share
## of the half width, the top row's y as a share of the half height, and the row pitch in card heights.
const DEPTH_M: float = 0.5
const CARD_SHARE: float = 0.115
const COLUMN_SHARE: float = 0.8
const TOP_SHARE: float = 0.78
const ROW_PITCH: float = 1.18
## Card tints: hovered (warm yellow, as the active Quick Access card), filled, empty, refusing.
const ACTIVE: Color = Color(1.0, 0.82, 0.0, 0.9)
const FILLED: Color = Color(0.42, 0.42, 0.42, 0.82)
const EMPTY: Color = Color(0.3, 0.3, 0.3, 0.38)
const REFUSE: Color = Color(1.0, 0.25, 0.2, 0.9)
const FULL: StringName = &"INVENTORY_POCKET_FULL"
const TOO_SMALL: StringName = &"INVENTORY_POCKET_TOO_SMALL"

## Per slot: {"path", "column" (0 left, 1 right), "row", "item_id", "card": MeshInstance3D, "visual": Node3D or
## null, "tint": Color}.
var slots: Array[Dictionary] = []
var camera: Camera3D
var hub: PlayerHubComponent
## The gradient for the left column (fading toward the pack, rightward) and the right one (leftward).
var _frames: Array[SubViewport] = []


## Cards for `quick_hub`'s quick pockets at the sides of `view`'s frame.
func setup(quick_hub: PlayerHubComponent, view: Camera3D) -> void:
	hub = quick_hub
	camera = view
	_frames = [_gradient_viewport(0), _gradient_viewport(1)]
	var rows: Array[int] = [0, 0]
	for zone: Dictionary in hub.get_quick_access_zones():
		var path: StringName = zone["path"]
		var column: int = 1 if String(path).begins_with("pack" + EquipmentComponent.POCKET_SEPARATOR) else 0
		slots.append({"path": path, "column": column, "row": rows[column], "item_id": zone["item_id"],
			"card": _card(_frames[1 - column]), "visual": null, "tint": EMPTY})
		rows[column] += 1
	if hub.equipment != null:
		hub.equipment.slot_changed.connect(func(_path: StringName, _id: StringName) -> void: refresh())
	for k: int in slots.size():
		_refresh(k)


## Re-reads every pocket's item from the equipment.
func refresh() -> void:
	if hub == null:
		return
	var by_path: Dictionary = {}
	for zone: Dictionary in hub.get_quick_access_zones():
		by_path[zone["path"]] = zone["item_id"]
	for k: int in slots.size():
		var now: StringName = by_path.get(slots[k]["path"], &"")
		if now != StringName(slots[k]["item_id"]):
			slots[k]["item_id"] = now
			_refresh(k)


## Why slot k would not take `item_id` now (FULL, TOO_SMALL), or &"" when it would.
func refusal(k: int, item_id: StringName) -> StringName:
	if StringName(slots[k]["item_id"]) != &"":
		return FULL
	var parts: PackedStringArray = String(slots[k]["path"]).split(EquipmentComponent.POCKET_SEPARATOR)
	if hub.equipment == null or parts.size() != 2:
		return TOO_SMALL
	var why: EquipmentComponent.Refusal = hub.equipment.can_stow(StringName(parts[0]), StringName(parts[1]), item_id)
	if why == EquipmentComponent.Refusal.NONE:
		return &""
	return FULL if why == EquipmentComponent.Refusal.SLOT_OCCUPIED else TOO_SMALL


## Flies slot k's item from its card to `into` (world), then moves it into the pack through the Hub.
## False when the pocket is empty or the Hub refuses (the item stays on its card).
func send_to_pack(k: int, into: Vector3, seconds: float = 0.4) -> bool:
	var visual: Node3D = slots[k]["visual"]
	if visual == null:
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
	var refused: StringName = hub.move_to_pack(slots[k]["path"])
	refresh()
	if refused != &"" and is_instance_valid(visual):
		visual.visible = true
	return refused == &""


## The slot whose card a world-space ray meets, or -1.
func pick(origin: Vector3, direction: Vector3) -> int:
	for k: int in slots.size():
		var card: MeshInstance3D = slots[k]["card"]
		var plane := Plane(card.global_basis.z.normalized(), card.global_position)
		var hit: Variant = plane.intersects_ray(origin, direction)
		if hit == null:
			continue
		var local: Vector3 = card.global_transform.affine_inverse() * (hit as Vector3)
		if absf(local.x) <= CARD_M * 0.5 and absf(local.y) <= CARD_M * 0.5:
			return k
	return -1


## Tints slot k's card ACTIVE or REFUSE; every other card (or all, with Color.TRANSPARENT) shows filled or empty.
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
	var view: Vector2 = camera.get_viewport().get_visible_rect().size
	var half_h: float = DEPTH_M * tan(deg_to_rad(camera.fov) * 0.5)
	var half_w: float = half_h * view.x / maxf(view.y, 1.0)
	var size: float = half_h * 2.0 * CARD_SHARE
	for slot: Dictionary in slots:
		var side: float = -1.0 if int(slot["column"]) == 0 else 1.0
		var at := Vector3(side * half_w * COLUMN_SHARE, half_h * TOP_SHARE - float(slot["row"]) * size * ROW_PITCH, -DEPTH_M)
		(slot["card"] as Node3D).global_transform = camera.global_transform * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size / CARD_M), at)
		var visual: Node3D = slot["visual"]
		if visual != null:
			visual.rotate_y(SPIN * delta)


func _card(frame: SubViewport) -> MeshInstance3D:
	var card := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(CARD_M, CARD_M)
	card.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = frame.get_texture()
	material.albedo_color = EMPTY
	card.material_override = material
	card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(card)
	return card


## Slot k's item stands on its card, scaled to fit it.
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
		holder.scale = Vector3.ONE * (CARD_M * ITEM_FIT / maxf(box.size[box.size.max_axis_index()], 0.001))
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
