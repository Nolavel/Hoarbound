class_name PackQuickShelf
extends Node3D

## Quick Access while Henry holds the pack open (3D inventory). A pocket whose item shows on the pack itself
## (side pockets, carabiners) gets its Quick Access gradient card (BG_frame.gdshader) behind that real item,
## nothing duplicated. Only pockets that cannot be seen (coat, thigh, the lid) stand as cards with their 3D item
## in a column at the frame's sides, no text: body pockets left, the pack's right. Moves go through the Hub, so
## the cards always show the equipment's own state.

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
## A card behind an item on the pack: its margin around the item's screen outline, and how far behind the
## item's far side it stands, metres.
const BACKDROP_PAD_M: float = 0.015
const BACKDROP_BEHIND_M: float = 0.01
## The card of an empty pocket on the pack is this big around its spot, metres.
const EMPTY_SPOT_M: float = 0.07
## The stencil value an item on the pack writes so its card, drawn over everything, stays behind it.
const STENCIL_REF: int = 7
## A card behind an item on the pack lies over the pack and the coat, so it shows this much of its tint's alpha.
const BACKDROP_ALPHA: float = 0.55
## Card tints: hovered (warm yellow, as the active Quick Access card), filled, empty, refusing.
const ACTIVE: Color = Color(1.0, 0.82, 0.0, 0.9)
const FILLED: Color = Color(0.42, 0.42, 0.42, 0.82)
const EMPTY: Color = Color(0.3, 0.3, 0.3, 0.38)
const REFUSE: Color = Color(1.0, 0.25, 0.2, 0.9)
const FULL: StringName = &"INVENTORY_POCKET_FULL"
const TOO_SMALL: StringName = &"INVENTORY_POCKET_TOO_SMALL"

## Per slot: {"path", "on_pack" (its item shows on the pack), "column" (0 left, 1 right), "row", "item_id",
## "card": MeshInstance3D, "visual": the card's own item (Node3D or null; none on the pack), "tint": Color}.
var slots: Array[Dictionary] = []
var camera: Camera3D
var hub: PlayerHubComponent
var pack: PackRig
## The gradient for the left column (fading toward the pack, rightward) and the right one (leftward).
var _frames: Array[SubViewport] = []


## Cards for `quick_hub`'s quick pockets at the sides of `view`'s frame.
func setup(quick_hub: PlayerHubComponent, view: Camera3D) -> void:
	hub = quick_hub
	camera = view
	pack = hub.pack
	_frames = [_gradient_viewport(0), _gradient_viewport(1)]
	var rows: Array[int] = [0, 0]
	for zone: Dictionary in hub.get_quick_access_zones():
		var path: StringName = zone["path"]
		var parts: PackedStringArray = String(path).split(EquipmentComponent.POCKET_SEPARATOR)
		var on_pack: bool = pack != null and parts.size() == 2 and parts[0] == "pack" and PackRig.shows_pocket(StringName(parts[1]))
		var column: int = 1 if parts[0] == "pack" else 0
		slots.append({"path": path, "on_pack": on_pack, "column": column, "row": -1 if on_pack else rows[column],
			"item_id": zone["item_id"], "card": _card(_frames[1 - column], on_pack), "visual": null, "tint": EMPTY})
		if not on_pack:
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
			var shown: Color = want
			if slots[i]["on_pack"]:
				shown.a *= BACKDROP_ALPHA
			((slots[i]["card"] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = shown


## What shows slot k's item: the real one on the pack, or the one standing on its card.
func visual_of(k: int) -> Node3D:
	if slots[k]["on_pack"]:
		return pack.get_pocket_visual(_pocket(k)) if is_instance_valid(pack) else null
	return slots[k]["visual"]


func _process(delta: float) -> void:
	if camera == null:
		return
	var view: Vector2 = camera.get_viewport().get_visible_rect().size
	var half_h: float = DEPTH_M * tan(deg_to_rad(camera.fov) * 0.5)
	var half_w: float = half_h * view.x / maxf(view.y, 1.0)
	var size: float = half_h * 2.0 * CARD_SHARE
	for k: int in slots.size():
		var slot: Dictionary = slots[k]
		if slot["on_pack"]:
			_place_backdrop(k)
			continue
		var side: float = -1.0 if int(slot["column"]) == 0 else 1.0
		var at := Vector3(side * half_w * COLUMN_SHARE, half_h * TOP_SHARE - float(slot["row"]) * size * ROW_PITCH, -DEPTH_M)
		(slot["card"] as Node3D).global_transform = camera.global_transform * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size / CARD_M), at)
		var visual: Node3D = slot["visual"]
		if visual != null:
			visual.rotate_y(SPIN * delta)


## Slot k's card stands square to the camera just behind its item on the pack (or its empty spot), covering it.
func _place_backdrop(k: int) -> void:
	var to_view: Transform3D = camera.global_transform.affine_inverse()
	var visual: Node3D = visual_of(k)
	var corners: Array[Vector3] = []
	if visual != null and visual.is_visible_in_tree():
		_mask(visual)
		var box: AABB = BackpackModel._local_bounds(visual)
		for i: int in 8:
			corners.append(to_view * (visual.global_transform * box.get_endpoint(i)))
	else:
		var box := AABB(pack.get_pocket_spot(_pocket(k)) - Vector3.ONE * EMPTY_SPOT_M * 0.5, Vector3.ONE * EMPTY_SPOT_M)
		for i: int in 8:
			corners.append(to_view * box.get_endpoint(i))
	## Every corner scaled onto the plane behind the far side; the card spans their outline.
	var depth: float = 0.0
	for corner: Vector3 in corners:
		depth = maxf(depth, -corner.z)
	depth += BACKDROP_BEHIND_M
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for corner: Vector3 in corners:
		var on_plane: Vector2 = Vector2(corner.x, corner.y) * depth / maxf(-corner.z, 0.01)
		low = low.min(on_plane)
		high = high.max(on_plane)
	low -= Vector2.ONE * BACKDROP_PAD_M
	high += Vector2.ONE * BACKDROP_PAD_M
	## It stops at the edge of the pack's opening on screen, so it never covers what the straps hold.
	var opening: Vector2 = _opening_span(to_view, depth)
	if (low.x + high.x) * 0.5 < (opening.x + opening.y) * 0.5:
		high.x = maxf(minf(high.x, opening.x), low.x + BACKDROP_PAD_M)
	else:
		low.x = minf(maxf(low.x, opening.y), high.x - BACKDROP_PAD_M)
	var middle: Vector2 = (low + high) * 0.5
	var span: Vector2 = high - low
	var card: MeshInstance3D = slots[k]["card"]
	card.global_transform = camera.global_transform * Transform3D(Basis.IDENTITY.scaled(Vector3(span.x, span.y, 1.0) / CARD_M), Vector3(middle.x, middle.y, -depth))
	## It fades toward the frame's middle, as the side columns do.
	var frame: Texture2D = _frames[0 if middle.x > 0.0 else 1].get_texture()
	var material := card.material_override as StandardMaterial3D
	if material.albedo_texture != frame:
		material.albedo_texture = frame


## The pack opening's left and right x on the view plane at `depth` (camera space).
func _opening_span(to_view: Transform3D, depth: float) -> Vector2:
	var straps: PackStraps = pack.get_straps()
	var room: AABB = PackStraps.room()
	var span := Vector2(INF, -INF)
	for i: int in 8:
		var corner: Vector3 = to_view * (straps.model.global_transform * room.get_endpoint(i))
		var x: float = corner.x * depth / maxf(-corner.z, 0.01)
		span = Vector2(minf(span.x, x), maxf(span.y, x))
	return span


func _pocket(k: int) -> StringName:
	return StringName(String(slots[k]["path"]).get_slice(EquipmentComponent.POCKET_SEPARATOR, 1))


## The item on the pack writes STENCIL_REF where it is seen, so its card never covers it.
func _mask(visual: Node3D) -> void:
	if visual.has_meta(&"backdrop_mask"):
		return
	var mask := StandardMaterial3D.new()
	mask.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mask.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mask.albedo_color = Color(0.0, 0.0, 0.0, 0.0)
	mask.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mask.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
	mask.stencil_flags = BaseMaterial3D.STENCIL_FLAG_WRITE
	mask.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_ALWAYS
	mask.stencil_reference = STENCIL_REF
	mask.render_priority = -1
	mask.set_meta(&"backdrop_mask", true)
	visual.set_meta(&"backdrop_mask", mask)
	for mesh: Node in [visual] + visual.find_children("*", "MeshInstance3D", true, false):
		if mesh is MeshInstance3D:
			(mesh as MeshInstance3D).material_overlay = mask


## Takes the masks off the pack's items when the cards go.
func _exit_tree() -> void:
	for k: int in slots.size():
		var visual: Node3D = visual_of(k) if slots[k]["on_pack"] else null
		if visual == null or not visual.has_meta(&"backdrop_mask"):
			continue
		visual.remove_meta(&"backdrop_mask")
		for mesh: Node in [visual] + visual.find_children("*", "MeshInstance3D", true, false):
			if mesh is MeshInstance3D:
				(mesh as MeshInstance3D).material_overlay = null


## A card on the gradient; one behind an item on the pack draws over everything but that item (stencil).
func _card(frame: SubViewport, on_pack: bool = false) -> MeshInstance3D:
	var card := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(CARD_M, CARD_M)
	card.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = frame.get_texture()
	material.albedo_color = EMPTY
	if on_pack:
		material.no_depth_test = true
		material.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
		material.stencil_flags = BaseMaterial3D.STENCIL_FLAG_READ
		material.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_NOT_EQUAL
		material.stencil_reference = STENCIL_REF
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
	if id != &"" and not slot["on_pack"]:
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
