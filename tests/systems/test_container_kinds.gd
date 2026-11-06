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


## F on each of `ways` (opens what is shut, shuts what is open), then lets them swing.
func _toggle(ways: Array) -> void:
	for way: String in ways:
		(_row.openers[way] as InteractiveArea).interact()
	await _frames(40)


## No mesh of the pack inside any furniture part; every item and the pack seen past everything, on screen.
func _check_clear(id: String, shelves: ItemContainer, camera: Camera3D) -> void:
	var parts: Array = ContainerClearance.furniture_parts(shelves)
	var pack: PackRig = null
	for node: Node in root.find_children("*", "PackRig", true, false):
		pack = node as PackRig
	if pack == null:
		_check(false, "%s: no pack in the frame" % id)
		return
	var mine: Array = []
	for node: Node in pack.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		if mesh.name == &"FrontPanel":
			## It bends in the shader: its sweep as it lies open now.
			var canvas: BackpackModel = pack.get_canvas()
			mine.append([canvas.global_transform, canvas.open_panel_box(canvas.get_fold_degrees()), "FrontPanel"])
			continue
		mine.append([mesh.global_transform, mesh.mesh.get_aabb(), String(pack.get_path_to(mesh))])
	var hits: int = 0
	for piece: Array in mine:
		for part: Array in parts:
			if ContainerClearance.boxes_overlap(piece[0], piece[1], part[0], part[1], 0.0):
				hits += 1
				if hits <= 3:
					push_error("container kinds: %s: pack mesh %s passes into the furniture part %s at %s" % [id, piece[2], part[1], (part[0] as Transform3D).origin])
	_check(hits == 0, "%s: %d pack meshes pass into the furniture" % [id, hits])
	var blockers: Array = parts.duplicate()
	blockers.append_array(mine)
	var size: Vector2 = camera.get_viewport().get_visible_rect().size
	var hidden: int = 0
	for item: Dictionary in shelves.items:
		var middle: Vector3 = ContainerClearance.middle_of(item["pickup"])
		var screen: Vector2 = camera.unproject_position(middle)
		var shown: bool = not camera.is_position_behind(middle) and Rect2(Vector2.ZERO, size).has_point(screen)
		if not shown or not ContainerClearance.sees(camera.global_position, middle, blockers):
			hidden += 1
	_check(hidden == 0, "%s: %d of %d items inside do not show to the view" % [id, hidden, shelves.items.size()])
	var pack_middle: Vector3 = pack.global_position
	_check(Rect2(Vector2.ZERO, size).has_point(camera.unproject_position(pack_middle)) and not camera.is_position_behind(pack_middle),
		"%s: the pack is off screen" % id)
	## The pack's opening faces the view (within 15 degrees; a view from far above is met up to 50 degrees back).
	var to_eye: Vector3 = (camera.global_position - pack.global_position).normalized()
	var facing: float = rad_to_deg(acos(clampf((-pack.global_basis.z.normalized()).dot(to_eye), -1.0, 1.0)))
	var steep: float = maxf(rad_to_deg(asin(clampf(to_eye.y, -1.0, 1.0))) - 50.0, 0.0)
	_check(facing < 15.0 + steep, "%s: the pack's opening is %.0f degrees off the view" % [id, facing])
	## It stays by the furniture: its middle within 0.75 m of the open face's nearest edge.
	var face: AABB = shelves.global_transform * shelves.shelves_box()
	var nearest: Vector3 = pack.global_position.clamp(face.position, face.end)
	var apart: float = nearest.distance_to(pack.global_position)
	_check(apart < 0.75, "%s: the pack stands %.2f m off the furniture" % [id, apart])
	print("container kinds: %s pack opening %.0f degrees off the view, %.2f m off the shelves" % [id, facing, apart])
	## Side doors as they were held out of the pack's way.
	for way: InteractiveArea in shelves.all_openers():
		var door := way as Cabinet
		if door != null and door.is_open() and door.swing_axis.is_equal_approx(Vector3.UP):
			print("container kinds: %s door %s at %.0f degrees" % [id, door.name, rad_to_deg(door.door_hinge.rotation.y)])
	## Its open face, corner to corner, shows past every part of the furniture (an open door in front hides it).
	var half: Vector3 = pack.size * 0.45
	for corner: Vector3 in [Vector3.ZERO, Vector3(-half.x, -half.y, -half.z), Vector3(half.x, -half.y, -half.z),
			Vector3(-half.x, half.y, -half.z), Vector3(half.x, half.y, -half.z)]:
		_check(ContainerClearance.sees(camera.global_position, pack.global_transform * corner, parts),
			"%s: the pack's face at %s is hidden behind the furniture" % [id, corner])
	print("container kinds: %s clear (pack meshes in furniture %d, items hidden %d)" % [id, hits, hidden])


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
