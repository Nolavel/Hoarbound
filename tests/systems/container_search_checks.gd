extends RefCounted

## Shared checks of the container search's working frame (test_container_kinds, test_727_furniture): no mesh of
## the pack in the furniture or in the room's own walls and floor, every item and the pack in sight, the pack's
## opening to the view, the pack by the furniture. Each returns the failures as messages (empty: all good).


## The pack in the scene under `root`, or null.
static func pack_in(root: Node) -> PackRig:
	var pack: PackRig = null
	for node: Node in root.find_children("*", "PackRig", true, false):
		pack = node as PackRig
	return pack


## Every visible mesh of `pack` as [Transform3D, AABB, label, MeshInstance3D or null], world (the open panel as it
## lies now, bent in the shader, as its sweep box with no mesh).
static func pack_boxes(pack: PackRig) -> Array:
	var mine: Array = []
	for node: Node in pack.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		if mesh.name == &"FrontPanel":
			var canvas: BackpackModel = pack.get_canvas()
			mine.append([canvas.global_transform, canvas.open_panel_box(canvas.get_fold_degrees()), "FrontPanel", null])
			continue
		mine.append([mesh.global_transform, mesh.mesh.get_aabb(), String(pack.get_path_to(mesh)), mesh])
	return mine


## Whether `piece` (pack_boxes) really passes into the box `part_xf` * `part_box`: its oriented box overlaps it and,
## for a real mesh, a triangle edge crosses the box or a box edge crosses a triangle (shrunk 1 mm: resting is touching).
static func passes_into(piece: Array, part_xf: Transform3D, part_box: AABB) -> bool:
	if not ContainerClearance.boxes_overlap(piece[0], piece[1], part_xf, part_box, 0.0):
		return false
	var mesh: MeshInstance3D = piece[3]
	if mesh == null:
		return true
	var inner: AABB = part_box.grow(-0.001)
	var corners: Array[Vector3] = []
	for k: int in 8:
		corners.append(part_xf * inner.get_endpoint(k))
	var edges: Array[Vector2i] = [Vector2i(0, 1), Vector2i(2, 3), Vector2i(4, 5), Vector2i(6, 7), Vector2i(0, 2),
		Vector2i(1, 3), Vector2i(4, 6), Vector2i(5, 7), Vector2i(0, 4), Vector2i(1, 5), Vector2i(2, 6), Vector2i(3, 7)]
	var faces: PackedVector3Array = mesh.mesh.get_faces()
	var xf: Transform3D = mesh.global_transform
	for i: int in range(0, faces.size(), 3):
		var a: Vector3 = xf * faces[i]
		var b: Vector3 = xf * faces[i + 1]
		var c: Vector3 = xf * faces[i + 2]
		if ContainerClearance.segment_hits(a, b, part_xf, inner) or ContainerClearance.segment_hits(b, c, part_xf, inner) \
				or ContainerClearance.segment_hits(c, a, part_xf, inner):
			return true
		for edge: Vector2i in edges:
			if Geometry3D.segment_intersects_triangle(corners[edge.x], corners[edge.y], a, b, c) != null:
				return true
	return false


static func frame_failures(id: String, shelves: ItemContainer, camera: Camera3D, root: Node) -> Array[String]:
	var out: Array[String] = []
	var pack: PackRig = pack_in(root)
	if pack == null:
		out.append("%s: no pack in the frame" % id)
		return out
	var parts: Array = ContainerClearance.furniture_parts(shelves)
	var mine: Array = pack_boxes(pack)
	for piece: Array in mine:
		for part: Array in parts:
			if passes_into(piece, part[0], part[1]):
				out.append("%s: pack mesh %s at %s passes into the furniture part %s at %s" % [id, piece[2],
					(piece[0] as Transform3D) * (piece[1] as AABB).get_center(), part[1], (part[0] as Transform3D).origin])
	var blockers: Array = parts.duplicate()
	blockers.append_array(mine)
	var size: Vector2 = camera.get_viewport().get_visible_rect().size
	var hidden: int = 0
	for item: Dictionary in shelves.items:
		var middle: Vector3 = ContainerClearance.middle_of(item["pickup"])
		var shown: bool = not camera.is_position_behind(middle) and Rect2(Vector2.ZERO, size).has_point(camera.unproject_position(middle))
		if not shown or not ContainerClearance.sees(camera.global_position, middle, blockers):
			hidden += 1
	if hidden > 0:
		out.append("%s: %d of %d items inside do not show to the view" % [id, hidden, shelves.items.size()])
	if camera.is_position_behind(pack.global_position) or not Rect2(Vector2.ZERO, size).has_point(camera.unproject_position(pack.global_position)):
		out.append("%s: the pack is off screen" % id)
	var to_eye: Vector3 = (camera.global_position - pack.global_position).normalized()
	var facing: float = rad_to_deg(acos(clampf((-pack.global_basis.z.normalized()).dot(to_eye), -1.0, 1.0)))
	var steep: float = maxf(rad_to_deg(asin(clampf(to_eye.y, -1.0, 1.0))) - 50.0, 0.0)
	if facing >= 15.0 + steep:
		out.append("%s: the pack's opening is %.0f degrees off the view" % [id, facing])
	var face: AABB = shelves.global_transform * shelves.shelves_box()
	var apart: float = pack.global_position.clamp(face.position, face.end).distance_to(pack.global_position)
	if apart >= 0.75:
		out.append("%s: the pack stands %.2f m off the furniture" % [id, apart])
	var half: Vector3 = pack.size * 0.45
	for corner: Vector3 in [Vector3.ZERO, Vector3(-half.x, -half.y, -half.z), Vector3(half.x, -half.y, -half.z),
			Vector3(-half.x, half.y, -half.z), Vector3(half.x, half.y, -half.z)]:
		if not ContainerClearance.sees(camera.global_position, pack.global_transform * corner, parts):
			out.append("%s: the pack's face at %s is hidden behind the furniture" % [id, corner])
	return out


## Pack meshes inside any physics body of the world other than Henry and the furniture piece: walls, floor, other
## furniture (the room's own geometry, which the furniture parts do not cover).
static func world_failures(id: String, shelves: ItemContainer, root: Node) -> Array[String]:
	var out: Array[String] = []
	var pack: PackRig = pack_in(root)
	if pack == null:
		return out
	var space: PhysicsDirectSpaceState3D = (root as Node).get_viewport().world_3d.direct_space_state
	var skip: Array[RID] = []
	for node: Node in root.find_children("*", "CollisionObject3D", true, false):
		var body := node as CollisionObject3D
		if body is CharacterBody3D or shelves.furniture_root().is_ancestor_of(body) or pack.is_ancestor_of(body):
			skip.append(body.get_rid())
	for piece: Array in pack_boxes(pack):
		var box := BoxShape3D.new()
		var aabb: AABB = piece[1]
		box.size = aabb.size.max(Vector3.ONE * 0.001)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = box
		query.transform = (piece[0] as Transform3D) * Transform3D(Basis.IDENTITY, aabb.get_center())
		query.exclude = skip
		query.collide_with_areas = false
		for hit: Dictionary in space.intersect_shape(query, 4):
			var collider: Object = hit.get("collider")
			out.append("%s: pack mesh %s passes into %s" % [id, piece[2], collider.get(&"name") if collider != null else "?"])
	return out
