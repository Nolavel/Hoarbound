class_name PackFrontHold
extends Node

## The pack held open before Henry (3D inventory, stage 3): it swings off the back to a spot ahead of his
## chest, upright with its opening turned out toward the camera that faces him (front_view()), tipped back so he
## sees in from above too; the front panel opens down and away from him. Both hands take it by the sides
## (HandGrip). Ended, it swings back on and the hands let go.

signal settled
signal finished

## Where the pack's middle is held: ahead of the chest, below it, metres.
const AHEAD_M: float = 0.46
const BELOW_M: float = 0.18
## How far the opening tips up from facing straight out, so Henry sees in from above, degrees.
const TIP_DEG: float = 45.0
## The camera: the share of the frame height the pack fills, how much it rises above the opening's line, and
## how far above the pack's middle it aims (so Henry's face shows over the pack), metres.
const FRAME_SHARE: float = 0.47
const VIEW_RISE: float = 0.35
const VIEW_LIFT_M: float = -0.07
## At a container only the pack and the furniture are framed, side by side, each across CONTAINER_SHARE of the
## frame width (owner's call: 48%), Henry hidden. The view looks in at an angle from the side away from the pack
## (degrees off the front, owner's sketch: the front turned to the pack, the far side showing), and this much up
## as a weight; the band both fit in (NDC y: nearly the whole height, the load bar and cards drawn over it).
const CONTAINER_SHARE: float = 0.48
const CONTAINER_VIEW_TURN_DEG: float = 30.0
const CONTAINER_VIEW_UP: float = 0.15
const CONTAINER_TOP: float = 0.98
const CONTAINER_BOTTOM: float = -1.0
## The pack stands on the floor beside it, opening turned to the view, the front panel lying open before it.
## What it takes up beyond its body (rig space, metres): the bedroll above, the loops.
const CONTAINER_PACK_EXTRA_TOP_M: float = 0.16
const CONTAINER_PACK_EXTRA_SIDE_M: float = 0.0
## What hangs off its loops (the pan, the mug) reaches this far below its foot; the pack is lifted until that
## clears the floor by CONTAINER_FLOOR_CLEAR_M, metres.
const CONTAINER_PACK_HANG_M: float = 0.26
const CONTAINER_FLOOR_CLEAR_M: float = 0.03
## The pack's half sits this much (NDC) in toward the furniture; the frame is worked out this much wider than the
## view, so both show this much larger (owner: closer, tighter), their outer edges past the frame.
const CONTAINER_PACK_IN: float = 0.22
const CONTAINER_TIGHTEN: float = 1.15
## The pack, nearer the view than its half alone asks, spans this share of the frame width (its body, loops
## left out); its foot sits this much (NDC) above the furniture's, lower when its top (the bedroll) would leave
## the frame; its front turns this share of the way from the view to the furniture's front.
const CONTAINER_PACK_SHARE: float = 0.3
const CONTAINER_PACK_LIFT: float = 0.3
const CONTAINER_PACK_PLANE: float = 0.75
## A container opening upward (a drawer, a chest) is looked down into at this angle, degrees.
const CONTAINER_OPENS_UP_DEG: float = 55.0
## The shelves the framing was authored on (the 727 cabinet's, width and height), metres.
const CONTAINER_REF_SHELVES: Vector2 = Vector2(0.74, 0.81)
## Looked down into, the pack's opening faces the view, tipped back at most this far (owner: its contents read).
const CONTAINER_FACE_TIP_DEG: float = 50.0
## The front panel opens this far there, so it lies on the floor (fully open it would dip under), degrees.
const CONTAINER_PANEL_DEG: float = 88.0
## The strap that stays over a shoulder while the pack is held (0 left, 1 right).
const STRAP_KEPT_SIDE: int = 0
## Swinging off the back and on again takes this long, seconds.
const SWING_S: float = 0.7
## How high the swing arcs above the straight path, metres.
const ARC_M: float = 0.18
## Something put in jolts the pack in his hands: the hand's push dips it JOLT_BASE_M, the item's weight more
## per kg (capped); it tips with it and springs back as a damped bounce at JOLT_HZ fading at JOLT_DECAY (1/s).
const JOLT_BASE_M: float = 0.012
const JOLT_M_PER_KG: float = 0.02
const JOLT_MAX_M: float = 0.035
const JOLT_TIP_DEG_PER_CM: float = 1.2
const JOLT_HZ: float = 3.2
const JOLT_DECAY: float = 7.0
## What hangs off the pack settles this long after the swing, then freezes until the pack goes back, seconds.
const HANG_SETTLE_S: float = 0.8
## The hands take the sides this far below the pack's middle, this far out from its walls and this far back
## toward its back face (outside the opening), metres.
const GRIP_DROP_M: float = 0.08
const GRIP_OUT_M: float = 0.1
const GRIP_BACK_M: float = 0.05

var visual: HenryUALAnimation
var pack: PackRig
## The open container being framed (its own pose and view), or null for the front view; the side of it the pack
## floats on (-1 left, 1 right, as one looks in).
var container: ItemContainer
var container_side: float = 1.0
## The container framing, worked out once: the view and the pack's place (world).
var _container_view := Transform3D()
var _container_pack := Transform3D()
var _framing: ContainerFraming
## Once the pack is off his back at a container, it is in its framed place by the furniture (the view cuts).
var _container_cut: bool = false
var _container_fov: float = 50.0
## Doors held out of the pack's way (swung back on finish).
var _held_doors: Array[Cabinet] = []
## Each pinned hanger's own hinge_out while it turns out by a container (put back after).
var _hanger_lean: Dictionary = {}
var _home_parent: Node
var _home_transform: Transform3D
var _from: Transform3D
var _t: float = 0.0
var _ending: bool = false
var _still_s: float = 0.0
var _jolt_m: float = 0.0
var _jolt_t: float = 0.0


## Takes `rig` off the back of `henry` and starts the swing to the front.
func start(henry: HenryUALAnimation, rig: PackRig) -> void:
	visual = henry
	pack = rig
	_home_parent = rig.get_parent()
	_home_transform = rig.transform
	_from = rig.global_transform
	var world: Node = henry.get_tree().current_scene if henry.get_tree().current_scene != null else henry.get_tree().root
	rig.reparent(world, true)
	rig.set_openness(PackRig.Openness.FULL)
	## He slips one arm out only: the left strap stays over his shoulder (PackShoulderStraps).
	rig.set_meta(&"strap_on_shoulder", STRAP_KEPT_SIDE)


## At `shelves` (an open container): the pack on `side` of it (ItemContainer.visit_spot), framed by the owner's
## ContainerFraming, else worked out at `fov` degrees; Henry is hidden unless the framing shows him.
func begin_container(shelves: ItemContainer, side: float, fov: float) -> void:
	container = shelves
	container_side = side
	_container_fov = fov
	_framing = ContainerFraming.load_saved()
	if _framing != null:
		## The owner's framing (tests/scenes/container_framing_stage.tscn), mirrored for the pack on the left.
		var front: Transform3D = ContainerFraming.front_of(container)
		## Authored on the 727 cabinet: a wider or taller one pushes the view and the pack out in proportion.
		var box: AABB = container.shelves_box()
		var grow: float = maxf(1.0, maxf(box.size.x / CONTAINER_REF_SHELVES.x, box.size.y / CONTAINER_REF_SHELVES.y))
		var camera: Transform3D = ContainerFraming.on_side(_framing.camera, side)
		var placed: Transform3D = ContainerFraming.on_side(_framing.pack, side)
		camera.origin *= grow
		placed.origin.x *= grow
		_container_view = front * camera
		_container_pack = front * placed
		if container.opens_up:
			## A drawer or a chest opens upward: the view looks down into it at CONTAINER_OPENS_UP_DEG from the same
			## distance (from the framing's level view its front wall hides what lies on its floor).
			var inside: Vector3 = container.global_transform * Vector3(box.get_center().x, box.position.y, box.get_center().z)
			var aim: Vector3 = inside.lerp(_container_pack.origin, 0.5)
			var away: Vector3 = _container_view.origin - aim
			var flat: Vector3 = away.slide(Vector3.UP).normalized()
			var drop: float = deg_to_rad(CONTAINER_OPENS_UP_DEG)
			var eye: Vector3 = aim + (flat * cos(drop) + Vector3.UP * sin(drop)) * away.length()
			_container_view = Transform3D(Basis.IDENTITY, eye).looking_at(aim, Vector3.UP)
	else:
		_frame_container(fov)
	pack.get_canvas().set_opening(BackpackModel.ZIP_FULL_M, CONTAINER_PANEL_DEG)
	## What hangs off it rests on the floor there instead of passing through: the floor under Henry (a kitchen
	## cupboard hangs high on the wall, so the furniture's foot is not the floor).
	pack.get_canvas().hang_floor_y = visual.global_position.y
	pack.get_canvas().hang_obstacles = ContainerClearance.furniture_parts(container)
	_lean_hangers_out()


## Whether the pack is in its framed place by a container (after the cut).
func is_container_cut() -> bool:
	return _container_cut


## Swings the pack back on; `finished` fires when it is home and the hands are free.
func finish() -> void:
	if _ending:
		return
	_ending = true
	## Back from the furniture's frame, it goes on again from his hands as by Tab (the view has left already).
	_container_cut = false
	_from = held_transform()
	visual.visible = true
	pack.get_canvas().hang_floor_y = -INF
	pack.get_canvas().hang_obstacles = []
	for door: Cabinet in _held_doors:
		if is_instance_valid(door):
			door.release_hold()
	_held_doors.clear()
	for hang: PendulumHang in _hanger_lean:
		if is_instance_valid(hang):
			hang.hinge_out = _hanger_lean[hang]
	_hanger_lean.clear()
	pack.set_hangers_frozen(false)
	pack.set_openness(PackRig.Openness.CLOSED)


## The pack dips under `kg` put into it and bounces back (a short hitch in his hands).
func jolt(kg: float) -> void:
	_jolt_m = minf(JOLT_BASE_M + maxf(kg, 0.0) * JOLT_M_PER_KG, JOLT_MAX_M)
	_jolt_t = 0.0


func is_settled() -> bool:
	return not _ending and _t >= 1.0


## Where the pack is held now (world): ahead of and below the chest, the opening tipped up toward Henry.
func held_transform() -> Transform3D:
	var frame: Array = _body_frame()
	var chest: Vector3 = frame[0]
	var forward: Vector3 = frame[1]
	if container != null and _container_cut:
		return _container_pack
	var tip: float = deg_to_rad(TIP_DEG)
	## The rig's -Z is its opening (outward on the back): it faces out ahead of Henry, tipped up; its top leans
	## back toward him and its bottom (the panel's hinge) is below, so the panel drops open away from him.
	var opening: Vector3 = (forward * cos(tip) + Vector3.UP * sin(tip)).normalized()
	var top: Vector3 = (Vector3.UP - opening * Vector3.UP.dot(opening)).normalized()
	var across: Vector3 = top.cross(-opening).normalized()
	return Transform3D(Basis(across, top, -opening), chest + forward * AHEAD_M - Vector3.UP * BELOW_M)


## The inventory camera: facing Henry, square to the pack's opening and a little above it, at the distance where
## the pack fills FRAME_SHARE of the height at `fov` degrees.
func front_view(fov: float) -> Transform3D:
	var held: Transform3D = held_transform()
	var opening: Vector3 = -held.basis.z.normalized()
	var distance: float = view_distance(fov)
	var eye: Vector3 = held.origin + (opening + Vector3.UP * VIEW_RISE).normalized() * distance
	return Transform3D(Basis.IDENTITY, eye).looking_at(held.origin + Vector3.UP * VIEW_LIFT_M, Vector3.UP)


## The view at an open container: the furniture across one half of the frame, the pack across the other.
func container_view(_fov: float) -> Transform3D:
	return _container_view


## Just before the cut, the working frame is fitted to this piece of furniture (owner: one system for every kind).
## The owner's framing stands as authored unless something passes into something or hides: side doors on the
## pack's side open all the way, the pack moves the least way clear of every part, the view turns until it sees
## every item and the pack. Looked down into (a drawer, a chest), the pack's opening turns to the view.
func _clear_container() -> void:
	var size: Vector2 = container.get_viewport().get_visible_rect().size
	var aspect: float = size.x / maxf(size.y, 1.0)
	var floor_y: float = visual.global_position.y
	var down: bool = container.opens_up
	if down:
		_face_view()
	_open_doors_wide()
	var parts: Array = ContainerClearance.furniture_parts(container)
	var shape: Array = ContainerClearance.pack_shape(pack, CONTAINER_PANEL_DEG, _container_pack.basis)
	_container_pack.origin = ContainerClearance.place_pack(_container_pack.origin, shape, parts, _ways_out(), floor_y)[0]
	var targets: Array[Vector3] = []
	for item: Dictionary in container.items:
		var pickup: Node3D = item["pickup"]
		if is_instance_valid(pickup):
			targets.append(ContainerClearance.middle_of(pickup))
	## Looking down, the whole open box is framed too; the owner's side framing crops the furniture on purpose.
	var scenery: Array[Vector3] = []
	var box: AABB = container.shelves_box()
	for i: int in (8 if down else 0):
		scenery.append(container.global_transform * box.get_endpoint(i))
	## Twice when looking down: the view moves, the pack turns to it again and is placed clear again.
	for _pass: int in (2 if down else 1):
		var half: Vector3 = pack.size * 0.5
		var framed: Array[Vector3] = [_container_pack.origin]
		for corner: Vector3 in [Vector3(-half.x, -half.y, -half.z), Vector3(half.x, -half.y, -half.z),
				Vector3(-half.x, half.y, -half.z), Vector3(half.x, half.y, -half.z)]:
			framed.append(_container_pack * (corner * 0.9))
		_container_view = ContainerClearance.aim_view(_container_view, targets, framed, scenery, parts,
			ContainerClearance.placed(_container_pack.origin, shape), _container_fov, aspect, down)
		if down:
			_face_view()
			shape = ContainerClearance.pack_shape(pack, CONTAINER_PANEL_DEG, _container_pack.basis)
			_container_pack.origin = ContainerClearance.place_pack(_container_pack.origin, shape, parts, _ways_out(), floor_y)[0]
	pack.get_canvas().hang_obstacles = parts


## The pack turned so its opening (-Z) looks straight at the view, tipped back at most CONTAINER_FACE_TIP_DEG.
func _face_view() -> void:
	var to_eye: Vector3 = _container_view.origin - _container_pack.origin
	var flat: Vector3 = to_eye.slide(Vector3.UP)
	if flat.length() < 0.01:
		return
	var tip: float = minf(atan2(to_eye.y, flat.length()), deg_to_rad(CONTAINER_FACE_TIP_DEG))
	var look: Vector3 = flat.normalized() * cos(tip) + Vector3.UP * sin(tip)
	_container_pack.basis = Basis.looking_at(look, Vector3.UP)


## Each open side door on the pack's side opens all the way (Cabinet.hold_max_deg, owner: doors open wider out of
## our way, the pack stands before them); unseen at the hard cut, swung back when the pack goes on.
func _open_doors_wide() -> void:
	var middle: float = container.shelves_box().get_center().x
	for opener: InteractiveArea in container.all_openers():
		var door := opener as Cabinet
		if door == null or not door.is_open() or door.door_hinge == null or not door.swing_axis.is_equal_approx(Vector3.UP):
			continue
		var hinge: Vector3 = container.global_transform.affine_inverse() * door.door_hinge.global_position
		if signf(hinge.x - middle) != container_side:
			continue
		door.hold_at(signf(door.open_angle_deg) * door.hold_max_deg)
		_held_doors.append(door)


## The ways the pack may move off the furniture: toward the view first (before an open door), out in front, out to
## its side, up, and between them (world).
func _ways_out() -> Array[Vector3]:
	var face: Array = container.front()
	var side: Vector3 = (face[2] as Vector3) * container_side
	var out: Vector3 = face[1]
	var toward: Vector3 = (_container_view.origin - _container_pack.origin).normalized()
	return [toward, out, side, Vector3.UP, (side + out).normalized(), (out + Vector3.UP).normalized()]


## By a container what hangs on a pin (the pan, the mug) turns toward the view if it meets the floor
## (PendulumHang.hinge_out): never under the open panel, never sideways onto the furniture.
func _lean_hangers_out() -> void:
	var placed: Transform3D = _container_pack
	var toward_view: Vector3 = -placed.basis.z.slide(Vector3.UP).normalized()
	for node: Node in pack.find_children("*", "PendulumHang", true, false):
		var hang := node as PendulumHang
		if hang.hinge_axis == Vector3.ZERO:
			continue
		_hanger_lean[hang] = hang.hinge_out
		hang.hinge_out = toward_view


## Works out the container view and the pack's place: the view looks in at an angle and stands where the
## furniture fills its half (CONTAINER_SHARE of the width); the pack stands on the floor where it fills the other.
func _frame_container(fov: float) -> void:
	var face: Array = container.front()
	var turn: float = deg_to_rad(CONTAINER_VIEW_TURN_DEG)
	var flat: Vector3 = (face[1] as Vector3) * cos(turn) - (face[2] as Vector3) * container_side * sin(turn)
	var from: Vector3 = (flat + Vector3.UP * CONTAINER_VIEW_UP).normalized()
	var basis := Basis.looking_at(-from, Vector3.UP)
	var size: Vector2 = container.get_viewport().get_visible_rect().size
	var tans := Vector2(tan(deg_to_rad(fov) * 0.5) * size.x / maxf(size.y, 1.0), tan(deg_to_rad(fov) * 0.5)) * CONTAINER_TIGHTEN
	var mid_y: float = (CONTAINER_TOP + CONTAINER_BOTTOM) * 0.5
	var half := Vector2(CONTAINER_SHARE, (CONTAINER_TOP - CONTAINER_BOTTOM) * 0.5)
	var body: AABB = container.body_box()
	var furniture: Array[Vector3] = []
	for i: int in 8:
		furniture.append(container.global_transform * body.get_endpoint(i))
	## The furniture fills its half (CONTAINER_SHARE across, within the band's height).
	var eye: Vector3 = container.global_transform * body.get_center() + from * 3.0
	for _step: int in 40:
		eye = _fit(furniture, Transform3D(basis, eye), tans, Vector2(-container_side * 0.5, mid_y), half)[0]
	_container_view = Transform3D(basis, eye)
	var furniture_box: Rect2 = _ndc_box(furniture, _container_view, tans)
	## The pack floats in the other half, as near as fills CONTAINER_PACK_SHARE across, its foot
	## CONTAINER_PACK_LIFT above the furniture's on screen (owner: higher), turned a little toward the furniture.
	var depth: float = (container.global_transform * body.get_center() - eye).dot(-basis.z) * 0.6
	var pack_x: float = container_side * (0.5 - CONTAINER_PACK_IN)
	var aim := Vector2(pack_x, mid_y)
	for _step: int in 60:
		var at: Vector3 = eye + (-basis.z + basis.x * aim.x * tans.x + basis.y * aim.y * tans.y) * depth
		_container_pack = _pack_facing(at, eye)
		var corners: Array[Vector3] = []
		for corner: Vector3 in _container_pack_corners():
			corners.append(_container_pack * corner)
		var pack_box: Rect2 = _ndc_box(corners, _container_view, tans)
		depth *= pack_box.size.x / (CONTAINER_PACK_SHARE * 2.0)
		aim.x -= (pack_box.get_center().x - pack_x) * 0.5
		var foot: float = minf(furniture_box.position.y + CONTAINER_PACK_LIFT, CONTAINER_TOP - pack_box.size.y)
		aim.y -= (pack_box.position.y - foot) * 0.5
	## Nearer than the furniture, its foot on the same screen line stands above the floor; lifted further if
	## what hangs off it would still reach the floor.
	var floor_y: float = (container.global_transform * body.position).y
	var hang_y: float = _container_pack.origin.y - pack.size.y * 0.5 - CONTAINER_PACK_HANG_M
	_container_pack.origin.y += maxf(floor_y + CONTAINER_FLOOR_CLEAR_M - hang_y, 0.0)


## One step of fitting `corners` into the NDC box at `centre` ± `half` from `view` (by width only when
## `across`): [the moved eye].
static func _fit(corners: Array[Vector3], view: Transform3D, tans: Vector2, centre: Vector2, half: Vector2, across: bool = false) -> Array:
	var ndc: Rect2 = _ndc_box(corners, view, tans)
	var depth: float = 0.0
	for corner: Vector3 in corners:
		depth += -(view.affine_inverse() * corner).z / corners.size()
	var scale: float = ndc.size.x / (half.x * 2.0) if across else maxf(ndc.size.x / (half.x * 2.0), ndc.size.y / (half.y * 2.0))
	var shift: Vector2 = ndc.get_center() - centre
	var eye: Vector3 = view.origin + view.basis.x * shift.x * tans.x * depth + view.basis.y * shift.y * tans.y * depth
	eye += view.basis.z * depth * (scale - 1.0)
	return [eye]


## The NDC box (x right, y up, -1..1) that `corners` cover as seen from `view` with half-angle tangents `tans`.
static func _ndc_box(corners: Array[Vector3], view: Transform3D, tans: Vector2) -> Rect2:
	var to_view: Transform3D = view.affine_inverse()
	var box := Rect2()
	for i: int in corners.size():
		var local: Vector3 = to_view * corners[i]
		var point := Vector2(local.x / (-local.z * tans.x), local.y / (-local.z * tans.y))
		box = Rect2(point, Vector2.ZERO) if i == 0 else box.expand(point)
	return box


## The pack standing upright at `at`, its opening turned from `eye` (flat) CONTAINER_PACK_PLANE of the way to the
## furniture's own front, so the two fronts nearly share a plane (owner).
func _pack_facing(at: Vector3, eye: Vector3) -> Transform3D:
	var toward: Vector3 = (eye - at).slide(Vector3.UP).normalized()
	toward = toward.slerp(container.front()[1] as Vector3, CONTAINER_PACK_PLANE).normalized()
	return Transform3D(Basis(Vector3.UP.cross(toward).normalized() * -1.0, Vector3.UP, -toward), at)


## The corners of what the pack is placed by, rig space: its body and the bedroll (the open panel left out, so
## turning it does not shift the pack).
func _container_pack_corners() -> Array[Vector3]:
	var half: Vector3 = pack.size * 0.5
	var low := Vector3(-half.x - CONTAINER_PACK_EXTRA_SIDE_M, -half.y, -half.z)
	var high := Vector3(half.x + CONTAINER_PACK_EXTRA_SIDE_M, half.y + CONTAINER_PACK_EXTRA_TOP_M, half.z)
	var box := AABB(low, high - low)
	var out: Array[Vector3] = []
	for i: int in 8:
		out.append(box.get_endpoint(i))
	return out


## Henry's chest (spine_03), his flat forward (square to the line between his shoulders, whatever the nodes
## above the skeleton are turned to) and his right: [Vector3, Vector3, Vector3], world.
func _body_frame() -> Array:
	var body := visual.get_parent() as Node3D
	var rig: Skeleton3D = visual.skeleton
	var chest_bone: int = rig.find_bone(&"spine_03")
	var chest: Vector3 = rig.to_global(rig.get_bone_global_pose(chest_bone).origin) if chest_bone >= 0 else body.global_position + Vector3.UP * 1.3
	var left_bone: int = rig.find_bone(&"upperarm_l")
	var right_bone: int = rig.find_bone(&"upperarm_r")
	var shoulders: Vector3 = rig.to_global(rig.get_bone_global_pose(right_bone).origin) - rig.to_global(rig.get_bone_global_pose(left_bone).origin)
	var forward: Vector3 = Vector3.UP.cross(shoulders) if left_bone >= 0 and right_bone >= 0 else visual.global_basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 1e-6 else Vector3.FORWARD
	return [chest, forward, Vector3.UP.cross(forward).normalized() * -1.0]


## How far the front view stands from the pack's middle at `fov` degrees (the camera focuses there), metres.
func view_distance(fov: float) -> float:
	return (pack.size.y * 0.5 / FRAME_SHARE) / tan(deg_to_rad(fov) * 0.5)


func _process(delta: float) -> void:
	if visual == null or pack == null:
		return
	if _ending:
		_t = maxf(_t - delta / SWING_S, 0.0)
	elif _t < 1.0:
		_t = minf(_t + delta / SWING_S, 1.0)
		if _t >= 1.0:
			if container != null:
				## Off his back in his hands: now the pack is in its place by the furniture and Henry leaves the frame.
				_clear_container()
				_container_cut = true
				if _framing == null or not _framing.show_henry:
					visual.visible = false
			settled.emit()
	elif _still_s < HANG_SETTLE_S:
		_still_s += delta
		if _still_s >= HANG_SETTLE_S and container == null:
			## Held still in his hands, nothing on it swings: the mug and the pan keep the pose they settled in.
			## By a container they stay free, so they can lie on the floor (BackpackModel.hang_floor_y).
			pack.set_hangers_frozen(true)
	var eased: float = smoothstep(0.0, 1.0, _t)
	var home: Transform3D = _home_parent.global_transform * _home_transform if is_instance_valid(_home_parent) else _from
	var start: Transform3D = home if not _ending else home
	var held: Transform3D = held_transform() if not _ending else _from
	var at: Transform3D = start.interpolate_with(held, eased)
	at.origin += Vector3.UP * ARC_M * sin(PI * eased) * (1.0 - eased)
	if _jolt_m > 0.0 and not _ending:
		_jolt_t += delta
		var dip: float = _jolt_m * exp(-JOLT_DECAY * _jolt_t) * sin(TAU * JOLT_HZ * _jolt_t)
		at.basis = Basis(at.basis.x.normalized(), deg_to_rad(JOLT_TIP_DEG_PER_CM * dip * 100.0)) * at.basis
		at.origin -= Vector3.UP * dip
		if exp(-JOLT_DECAY * _jolt_t) < 0.01:
			_jolt_m = 0.0
	pack.global_transform = at
	if container == null or not _container_cut:
		_grip_sides(eased)  # his hands hold it as it comes off, until the cut to the furniture's frame
	if _ending and _t <= 0.0:
		_put_back()


## Both hands on the pack's side walls, palms in, fingers down its sides; weight follows the swing.
func _grip_sides(weight: float) -> void:
	var at: Transform3D = pack.global_transform
	var half: Vector3 = pack.size * 0.5
	for left: bool in [true, false]:
		var grip: HandGrip = visual.get_hand_grip(left)
		if grip == null:
			continue
		var side: float = -1.0 if left else 1.0
		var outward: Vector3 = at.basis.x.normalized() * side
		var wrist: Vector3 = at.origin + outward * (half.x + GRIP_OUT_M) - at.basis.y.normalized() * GRIP_DROP_M + at.basis.z.normalized() * GRIP_BACK_M
		## Fingers down the side and slightly in, palm on the wall from outside; elbows wide so no sleeve enters.
		var along: Vector3 = (-at.basis.y.normalized() + outward * 0.15).normalized()
		var across: Vector3 = at.basis.z.normalized()
		var pole: Vector3 = wrist + outward * 0.6 + Vector3.DOWN * 0.15 + at.basis.z.normalized() * 0.2
		grip.hold(wrist, along, across, pole, weight)


func _put_back() -> void:
	for left: bool in [true, false]:
		var grip: HandGrip = visual.get_hand_grip(left)
		if grip != null:
			grip.release()
	pack.remove_meta(&"strap_on_shoulder")
	if is_instance_valid(_home_parent):
		pack.reparent(_home_parent, false)
		pack.transform = _home_transform
	visual = null
	finished.emit()
	queue_free()
