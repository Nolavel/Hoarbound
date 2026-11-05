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
## What it takes up beyond its body (rig space, metres): the bedroll above, the loops, the panel on the floor.
const CONTAINER_PACK_EXTRA_TOP_M: float = 0.16
const CONTAINER_PACK_EXTRA_SIDE_M: float = 0.08
const CONTAINER_PACK_PANEL_M: float = 0.46
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


## At `shelves` (an open container): the pack floats on `side` of it (ItemContainer.visit_spot), the two framed
## side by side at `fov` degrees; Henry is hidden until the pack goes back.
func begin_container(shelves: ItemContainer, side: float, fov: float) -> void:
	container = shelves
	container_side = side
	_frame_container(fov)
	pack.get_canvas().set_opening(BackpackModel.ZIP_FULL_M, CONTAINER_PANEL_DEG)
	visual.visible = false


## Swings the pack back on; `finished` fires when it is home and the hands are free.
func finish() -> void:
	if _ending:
		return
	_ending = true
	_from = held_transform()
	visual.visible = true
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
	if container != null:
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


## Works out the container view and the pack's place: the view looks in at an angle and stands where the
## furniture fills its half (CONTAINER_SHARE of the width); the pack stands on the floor where it fills the other.
func _frame_container(fov: float) -> void:
	var face: Array = container.front()
	var turn: float = deg_to_rad(CONTAINER_VIEW_TURN_DEG)
	var flat: Vector3 = (face[1] as Vector3) * cos(turn) - (face[2] as Vector3) * container_side * sin(turn)
	var from: Vector3 = (flat + Vector3.UP * CONTAINER_VIEW_UP).normalized()
	var basis := Basis.looking_at(-from, Vector3.UP)
	var size: Vector2 = container.get_viewport().get_visible_rect().size
	var tans := Vector2(tan(deg_to_rad(fov) * 0.5) * size.x / maxf(size.y, 1.0), tan(deg_to_rad(fov) * 0.5))
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
	## The pack floats in the other half, as near as fills it across (or the band's height), its foot on the
	## furniture's foot line on screen so the two read as standing side by side.
	var depth: float = (container.global_transform * body.get_center() - eye).dot(-basis.z) * 0.6
	var aim := Vector2(container_side * 0.5, mid_y)
	for _step: int in 60:
		var at: Vector3 = eye + (-basis.z + basis.x * aim.x * tans.x + basis.y * aim.y * tans.y) * depth
		_container_pack = _pack_facing(at, eye)
		var corners: Array[Vector3] = []
		for corner: Vector3 in _container_pack_corners():
			corners.append(_container_pack * corner)
		var pack_box: Rect2 = _ndc_box(corners, _container_view, tans)
		var room_y: float = CONTAINER_TOP - furniture_box.position.y
		depth *= maxf(pack_box.size.x / (half.x * 2.0), pack_box.size.y / room_y)
		aim.x -= (pack_box.get_center().x - container_side * 0.5) * 0.5
		aim.y -= (pack_box.position.y - furniture_box.position.y) * 0.5


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


## The pack standing upright at `at`, its opening turned to `eye` (flat).
func _pack_facing(at: Vector3, eye: Vector3) -> Transform3D:
	var toward: Vector3 = (eye - at).slide(Vector3.UP).normalized()
	return Transform3D(Basis(Vector3.UP.cross(toward).normalized() * -1.0, Vector3.UP, -toward), at)


## The corners of what the open pack takes up, rig space: its body, the bedroll, the panel open on the floor.
func _container_pack_corners() -> Array[Vector3]:
	var half: Vector3 = pack.size * 0.5
	var low := Vector3(-half.x - CONTAINER_PACK_EXTRA_SIDE_M, -half.y, -half.z - CONTAINER_PACK_PANEL_M)
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
			settled.emit()
	elif _still_s < HANG_SETTLE_S:
		_still_s += delta
		if _still_s >= HANG_SETTLE_S:
			## Held still in his hands, nothing on it swings: the mug and the pan keep the pose they settled in.
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
	if container == null:
		_grip_sides(eased)
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
