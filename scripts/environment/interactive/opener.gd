class_name Opener
extends InteractiveArea

## A way into a container (a door, a lid, a drawer): what the container asks, whatever kind it is. A new kind
## extends this and plugs into ItemContainer.openers with no change there (ARCHITECTURE §16).

## It starts to open (true) or to shut.
signal toggled(open: bool)

## The aim counts as on the leaf this close to its mesh bounds, metres.
const LEAF_AIM_MARGIN_M: float = 0.03
## A leaf given as a bare point (a drawer's handle) is aimed at within this of it, about its front's half height, metres.
const LEAF_POINT_RADIUS_M: float = 0.12

## The search of the container it opens (set by ItemContainer): open, the view on the shelves goes to it.
var search: InteractiveArea


## Whether it stands open now (a kind overrides it).
func is_open() -> bool:
	return false


## Whether it is still moving between open and shut.
func is_swinging() -> bool:
	return false


## F goes to what the aim meets first: this leaf, or other open shelves offering a search (#42 record 03).
func accepts_focus(from: Vector3, direction: Vector3) -> bool:
	var leaf: Node3D = get_leaf()
	var on_leaf: float = _aim_distance(leaf, from, direction) if leaf != null else INF
	if search != null and is_open() and search.can_interact() and on_leaf == INF:
		return leaf == null
	for node: Node in get_tree().get_nodes_in_group(ItemContainer.GROUP):
		var other := node as ItemContainer
		if other != null and other.get_search() != search and other.offers_search() \
				and other.aim_distance_to_shelves(from, direction) < on_leaf:
			return false
	return true


## The part that moves aside to open it, aimed at to shut it (a kind overrides it); null: no such part.
func get_leaf() -> Node3D:
	return null


## How far along the aim it meets `leaf` (its meshes' bounds, or near its point when it has none); INF: it misses.
static func _aim_distance(leaf: Node3D, from: Vector3, direction: Vector3) -> float:
	var along: Vector3 = direction.normalized()
	var meshes: Array[Node] = leaf.find_children("*", "MeshInstance3D", true, false)
	if leaf is MeshInstance3D:
		meshes.append(leaf)
	if meshes.is_empty():
		var to: Vector3 = leaf.global_position - from
		var ahead: float = along.dot(to)
		return ahead if ahead > 0.0 and to.distance_to(along * ahead) <= LEAF_POINT_RADIUS_M else INF
	var nearest: float = INF
	for node: Node in meshes:
		var mesh := node as MeshInstance3D
		var inverse: Transform3D = mesh.global_transform.affine_inverse()
		var hit: Variant = mesh.get_aabb().grow(LEAF_AIM_MARGIN_M).intersects_ray(inverse * from, inverse.basis * along)
		if hit != null:
			nearest = minf(nearest, from.distance_to(mesh.global_transform * (hit as Vector3)))
	return nearest
