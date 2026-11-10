extends SceneTree

## The container search on every kind of furniture in the test row (ContainerRow): a floor cabinet, a kitchen
## cupboard with two doors high on the wall, a dresser's three drawers, a floor chest with a lid. For each:
## - shut, no search is offered;
## - opened (F on its door, drawer or lid), the search is offered only if something is inside, and the open face
##   is frosted over; an empty one offers nothing;
## - F on the search works where Henry stands (he does not walk): he faces it, crouches at a low one, not at the
##   high cupboard, the pack comes off and the view cuts to the working frame, the ring hovering an item there;
## - in that frame no mesh of the pack (its body, open panel, what hangs off it) passes into any part of the
##   furniture (doors and drawers as they stand), every item inside shows to the view with nothing in between,
##   and the pack is on screen;
## - closing the pack stands him up and leaves the furniture searchable again.
## Run: godot --headless --path . --fixed-fps 30 --script res://tests/systems/test_container_kinds.gd

const PLAYER: String = "res://scenes/actors/player/player.tscn"
const ROW: String = "res://tests/scenes/container_row.tscn"
## [container, its ways in (all opened), holds something, low (Henry crouches)].
const CASES: Array = [
	["floor_cabinet", ["floor_cabinet"], true, true],
	["cupboard", ["cupboard_left", "cupboard_right"], true, false],
	["drawer_top", ["drawer_top"], true, true],
	["drawer_middle", ["drawer_middle"], true, true],
	["drawer_bottom", ["drawer_bottom"], false, true],
	["chest", ["chest"], true, true],
]
const CHECKS: GDScript = preload("res://tests/systems/container_search_checks.gd")
## Henry stands this far out from a container's front to search it, metres.
const STAND_M: float = 0.9

var _failures: int = 0
var _player: Player
var _hub: PlayerHubComponent
var _row: ContainerRow


func _initialize() -> void:
	_run()


func _run() -> void:
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	floor.add_child(shape)
	root.add_child(floor)
	_row = (load(ROW) as PackedScene).instantiate() as ContainerRow
	root.add_child(_row)
	_player = (load(PLAYER) as PackedScene).instantiate() as Player
	root.add_child(_player)
	_player.position = Vector3(0.0, 1.0, 3.0)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.make_current()
	await _frames(30)
	_hub = _player.get_node(^"PlayerHubComponent") as PlayerHubComponent
	for case: Array in CASES:
		await _try(case[0], case[1], case[2], case[3])
	await _new_kind_plugs_in()
	_finish()


func _try(id: String, ways_in: Array, full: bool, low: bool) -> void:
	var shelves: ItemContainer = _row.containers[id]
	var search := shelves.get_node(^"Search") as ContainerSearch
	## Henry walks up himself: he stands out from its front, facing it.
	var face: Array = shelves.front()
	var stand: Vector3 = (face[0] as Vector3) + (face[1] as Vector3) * STAND_M
	stand.y = 1.0
	_player.global_position = stand
	_player.velocity = Vector3.ZERO
	_player.face_work_target(face[0])
	await _frames(5)
	_check(not search.can_interact(), "%s: shut, it still offers a search" % id)
	await _toggle(ways_in)
	_check(shelves.is_reachable(), "%s: F on its way in did not open it" % id)
	var veil := shelves.get_node_or_null(^"FrostedVeil") as MeshInstance3D
	if not full:
		_check(not search.can_interact(), "%s: empty, it still offers a search" % id)
		_check(veil == null or not veil.visible, "%s: empty, its face is still frosted" % id)
		print("container kinds: %s empty, nothing offered" % id)
		await _toggle(ways_in)
		return
	_check(search.can_interact(), "%s: open with something inside, it offers no search" % id)
	_check(veil != null and veil.visible, "%s: open, its face is not frosted" % id)
	var before: Vector3 = _player.global_position
	search.interact()
	var hands: PackHandling = null
	for _i: int in 120:
		hands = _hub.get_pack_hands()
		if hands != null and hands.enabled:
			break
		await _frames(1)
	_check(hands != null and hands.enabled, "%s: the view never cut to the working frame" % id)
	_check(_hub.container == shelves, "%s: the Hub did not take its shelves" % id)
	var moved: float = Vector2(_player.global_position.x - before.x, _player.global_position.z - before.z).length()
	_check(moved < 0.05, "%s: Henry walked %.2f m to search (he searches where he stands)" % [id, moved])
	_check(_player.is_crouching() == low, "%s: Henry %s at it" % [id, "did not crouch" if low else "crouched"])
	_check(veil == null or not veil.visible, "%s: the frost stayed during Henry's own search" % id)
	if hands != null and hands.enabled:
		await _frames(45)
		_check_clear(id, shelves, hands.camera)
		var pickup: Node3D = shelves.items[0]["pickup"]
		var outline: PackedVector2Array = PackHandling.screen_outline(pickup, hands.camera)
		var middle := Vector2.ZERO
		for point: Vector2 in outline:
			middle += point
		hands.set_cursor(middle / maxf(outline.size(), 1.0))
		await _frames(3)
		_check(hands.hovered_shelf == 0, "%s: in the working frame the ring does not hover its first item" % id)
	print("container kinds: %s searched in place (moved %.2f m, crouched %s)" % [id, moved, _player.is_crouching()])
	_hub.close()
	await _frames(40)
	_check(not _hub.is_open() and not _player.is_work_crouching(), "%s: closing the pack did not stand Henry up" % id)
	_check(search.can_interact(), "%s: after the search it is not searchable again" % id)
	await _toggle(ways_in)


## A way in of a kind ItemContainer has never seen (a sliding door) plugs in through Opener with no change there:
## shut, nothing is reachable or offered; slid open, the shelves are reachable and the search is offered.
func _new_kind_plugs_in() -> void:
	var piece := Node3D.new()
	piece.name = "SlidingCupboard"
	root.add_child(piece)
	piece.global_position = Vector3(-3.0, 0.0, 0.0)
	var door := SlidingDoor.new()
	piece.add_child(door)
	var shelves := ItemContainer.new()
	shelves.container_id = &"test_sliding"
	shelves.shelves = [AABB(Vector3(-0.4, 0.8, -0.2), Vector3(0.8, 0.3, 0.4))] as Array[AABB]
	shelves.openers.append(door)
	piece.add_child(shelves)
	shelves.put(&"spov_can")
	var search := shelves.get_node(^"Search") as ContainerSearch
	var face: Array = shelves.front()
	var stand: Vector3 = (face[0] as Vector3) + (face[1] as Vector3) * STAND_M
	stand.y = 1.0
	_player.global_position = stand
	_player.velocity = Vector3.ZERO
	await _frames(5)
	_check(not shelves.is_reachable() and not search.can_interact(), "a shut sliding door left its shelves reachable")
	door.slid_open = true
	await _frames(2)
	_check(shelves.is_reachable(), "an open sliding door did not make its shelves reachable")
	_check(search.can_interact(), "an open sliding door with something inside offers no search")
	print("container kinds: a new kind of way in (sliding door) plugs in through Opener")
	piece.queue_free()
	await _frames(2)


## A sliding door: a kind of way in the container code does not know.
class SlidingDoor:
	extends Opener

	var slid_open: bool = false

	func is_open() -> bool:
		return slid_open


## F on each of `ways` (opens what is shut, shuts what is open), then lets them swing.
func _toggle(ways: Array) -> void:
	for way: String in ways:
		(_row.openers[way] as InteractiveArea).interact()
	await _frames(40)


## The working frame (container_search_checks.gd): no pack mesh in the furniture, everything in sight.
func _check_clear(id: String, shelves: ItemContainer, camera: Camera3D) -> void:
	var failures: Array[String] = CHECKS.frame_failures(id, shelves, camera, root)
	for failure: String in failures:
		_check(false, failure)
	var pack: PackRig = CHECKS.pack_in(root)
	if pack == null:
		return
	var face: AABB = shelves.global_transform * shelves.shelves_box()
	var apart: float = pack.global_position.clamp(face.position, face.end).distance_to(pack.global_position)
	var to_eye: Vector3 = (camera.global_position - pack.global_position).normalized()
	var facing: float = rad_to_deg(acos(clampf((-pack.global_basis.z.normalized()).dot(to_eye), -1.0, 1.0)))
	print("container kinds: %s pack opening %.0f degrees off the view, %.2f m off the shelves" % [id, facing, apart])
	## The owner's framing (container_framing.tres) stands at the 727-like floor cabinet: the view as authored,
	## the pack within 3 cm of its authored place (only lifted so what hangs clears the floor).
	var framing: ContainerFraming = ContainerFraming.load_saved()
	if id == "floor_cabinet" and framing != null:
		var front: Transform3D = ContainerFraming.front_of(shelves)
		var holds: Array[Node] = root.find_children("*", "PackFrontHold", true, false)
		var side: float = (holds[0] as PackFrontHold).container_side if not holds.is_empty() else 1.0
		var view: Vector3 = (front * ContainerFraming.on_side(framing.camera, side)).origin
		var placed: Vector3 = (front * ContainerFraming.on_side(framing.pack, side)).origin
		_check(camera.global_position.distance_to(view) < 0.01, "%s: the view left the owner's framing by %.2f m" % [id, camera.global_position.distance_to(view)])
		_check(pack.global_position.distance_to(placed) < 0.03, "%s: the pack left the owner's framing by %.2f m" % [id, pack.global_position.distance_to(placed)])
	## A side door on the pack's side stands all the way open, and the pack stands before it, nearer the view.
	for way: Opener in shelves.all_openers():
		var door := way as Cabinet
		if door == null or not door.is_open() or not door.swing_axis.is_equal_approx(Vector3.UP):
			continue
		var angle: float = absf(rad_to_deg(door.door_hinge.rotation.y))
		var leaf: Vector3 = door.get_focus_point(camera.global_position)
		var on_pack_side: bool = (leaf - shelves.front()[0]).dot(shelves.front()[2]) * (pack.global_position - shelves.front()[0]).dot(shelves.front()[2]) > 0.0
		if on_pack_side:
			_check(angle > door.hold_max_deg - 1.0, "%s: door %s on the pack's side only opened %.0f degrees" % [id, door.name, angle])
			_check(camera.global_position.distance_to(pack.global_position) < camera.global_position.distance_to(leaf),
				"%s: the pack stands behind door %s, not before it" % [id, door.name])
		print("container kinds: %s door %s at %.0f degrees%s" % [id, door.name, angle, " (pack's side)" if on_pack_side else ""])
	print("container kinds: %s clear (%d frame failures)" % [id, failures.size()])


func _frames(count: int) -> void:
	for _i: int in count:
		await process_frame


func _finish() -> void:
	print("container kinds: %s" % ("all checks passed" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("container kinds: %s" % message)
