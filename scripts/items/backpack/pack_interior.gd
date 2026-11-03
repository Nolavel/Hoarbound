class_name PackInterior
extends Node3D

## The main compartment without slots (3D inventory, stage 0): what Henry carries lies in it as rigid bodies on
## simple shapes (a Cairn-style physics container). The bodies live in a physics space of their own, in pack
## space: the walls never move, gravity is turned into the pack's frame each step, carrying the pack cannot
## fling anything, and nothing inside touches the world. Closed, the space stops and every pose stays as it was.

signal refused(item_id: StringName, reason: StringName)

## How far each side wall and the front give under what presses on them, metres (canvas stretch).
const STRETCH_M: float = 0.03
## The opening's hem rises this far above the mouth (it stretches up round a heap), metres.
const HEM_M: float = 0.12
## Wall thickness of the collision slabs, metres (thick enough that nothing tunnels through).
const WALL_M: float = 0.05
## Share of the compartment's volume items can fill: loose shapes never pack solid.
const FILL_SHARE: float = 0.7
## Below this speed (m/s, rad/s) for SETTLE_S an item counts as settled.
const SETTLE_SPEED: float = 0.03
const SETTLE_S: float = 0.4
## The interior's own solver: more iterations and a tighter penetration allowance than the world, so a heap
## of small tins stacks without sinking; it is cheap with at most a few dozen bodies.
const SOLVER_ITERATIONS: int = 32
const ALLOWED_PENETRATION_M: float = 0.002
## Item bodies: damping so a heap settles instead of jittering, friction of canvas and tins.
const LINEAR_DAMP: float = 0.6
const ANGULAR_DAMP: float = 1.2
const FRICTION: float = 0.8
## In-pack masses are kept within this range: a 20 g lighter under a 400 g tin makes the solver chatter.
const MASS_MIN: float = 0.25
const MASS_MAX: float = 1.2
## Since its last disturbance an item's damping climbs by this per second (to CALM_MAX_DAMP): a heap settles
## within a second or two instead of rattling on.
const CALM_RAMP: float = 4.0
const CALM_MAX_DAMP: float = 10.0
## Thinnest collision shape, metres: thinner boxes (a lighter, a glove) chatter.
const MIN_SHAPE_M: float = 0.022
## Refusal reasons (localised by the caller).
const TOO_BIG: StringName = &"INVENTORY_TOO_BIG"
const NO_ROOM: StringName = &"INVENTORY_NO_ROOM"

var model: BackpackModel
## Per item: {"id", "rid": body RID, "shape": shape RID, "visual": Node3D, "box": AABB (its shape in its own
## space), "still_s": float, "calm_s": float, "state": Dictionary}. Poses are read from the body (pack space).
var items: Array[Dictionary] = []
var _space: RID
var _walls: RID
var _wall_shapes: Array[RID] = []
var _open: bool = false


## Builds the compartment inside `pack` (pack space: x across, y up, z from the back face to the front).
func setup(pack: BackpackModel) -> void:
	model = pack
	_space = PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_param(_space, PhysicsServer3D.SPACE_PARAM_SOLVER_ITERATIONS, SOLVER_ITERATIONS)
	PhysicsServer3D.space_set_param(_space, PhysicsServer3D.SPACE_PARAM_CONTACT_MAX_ALLOWED_PENETRATION, ALLOWED_PENETRATION_M)
	PhysicsServer3D.area_set_param(_space, PhysicsServer3D.AREA_PARAM_GRAVITY, _gravity_strength())
	_walls = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(_walls, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(_walls, _space)
	var size: Vector3 = BackpackModel.BODY
	var sink: float = ALLOWED_PENETRATION_M
	var half_x: float = size.x * 0.5 + STRETCH_M - sink
	var deep: float = size.z + STRETCH_M + HEM_M
	## Back (the floor when the pack lies face up), the two sides, top and bottom; the front is the mouth.
	_slab(Vector3(0.0, size.y * 0.5, sink - WALL_M * 0.5), Vector3(half_x * 2.0 + WALL_M * 2.0, size.y + WALL_M * 2.0, WALL_M))
	for side: float in [-1.0, 1.0]:
		_slab(Vector3(side * (half_x + WALL_M * 0.5), size.y * 0.5, deep * 0.5), Vector3(WALL_M, size.y + WALL_M * 2.0, deep))
	_slab(Vector3(0.0, sink - WALL_M * 0.5, deep * 0.5), Vector3(half_x * 2.0, WALL_M, deep))
	_slab(Vector3(0.0, size.y - sink + WALL_M * 0.5, deep * 0.5), Vector3(half_x * 2.0, WALL_M, deep))
	_apply_gravity()


func _slab(centre: Vector3, extents: Vector3) -> void:
	var shape: RID = PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(shape, extents * 0.5)
	PhysicsServer3D.body_add_shape(_walls, shape, Transform3D(Basis.IDENTITY, centre))
	_wall_shapes.append(shape)


## The compartment's inside, pack space: what a stored item's shape must lie within.
static func inside() -> AABB:
	var size: Vector3 = BackpackModel.BODY
	return AABB(Vector3(-size.x * 0.5 - STRETCH_M, 0.0, 0.0), Vector3(size.x + STRETCH_M * 2.0, size.y, size.z + STRETCH_M))


## Why item_id cannot go in now (TOO_BIG: bulky, or its smallest outline does not pass the mouth; NO_ROOM:
## the room left is too small), or &"" when it can.
func refusal(item_id: StringName) -> StringName:
	var visual: Node3D = SurvivalItemVisual.make(item_id)
	var box: AABB = BackpackModel._local_bounds(visual)
	visual.free()
	return refusal_for(box, item_id)


func refusal_for(box: AABB, item_id: StringName = &"") -> StringName:
	var kind: ItemResource = ItemCatalog.get_item(item_id) if item_id != &"" else null
	## Bulky things (boards, a log, a person) never go in, whatever their placeholder shape measures.
	if kind != null and kind.size_class == ItemTraits.SizeClass.BULKY:
		return TOO_BIG
	var dims: Array = [box.size.x, box.size.y, box.size.z]
	dims.sort()
	var mouth := Vector2(BackpackModel.BODY.x + STRETCH_M * 2.0, BackpackModel.BODY.y)
	## Through the front opening on its two smallest sides; it must also fit the depth on its smallest one.
	if dims[0] > BackpackModel.BODY.z + STRETCH_M or dims[1] > mouth.x or dims[2] > mouth.y * 1.15:
		return TOO_BIG
	if box.get_volume() > room_left():
		return NO_ROOM
	return &""


## Volume still free for loose items, cubic metres (FILL_SHARE of the compartment less what is in).
func room_left() -> float:
	var used: float = 0.0
	for item: Dictionary in items:
		used += (item["box"] as AABB).get_volume()
	return inside().get_volume() * FILL_SHARE - used


## Puts item_id in through the mouth at `drop_at` (pack space, defaults above the middle of the opening); it
## falls in while open. False with refused(...) when it cannot go in.
func add(item_id: StringName, drop_at: Vector3 = Vector3.INF, state: Dictionary = {}) -> bool:
	var visual: Node3D = SurvivalItemVisual.make(item_id)
	var box: AABB = BackpackModel._local_bounds(visual)
	var why: StringName = refusal_for(box, item_id)
	if why != &"":
		visual.free()
		refused.emit(item_id, why)
		return false
	var kind: ItemResource = ItemCatalog.get_item(item_id)
	var body: RID = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
	PhysicsServer3D.body_set_space(body, _space)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_MASS, clampf(kind.weight if kind != null else 0.3, MASS_MIN, MASS_MAX))
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_FRICTION, FRICTION)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP, LINEAR_DAMP)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP, ANGULAR_DAMP)
	PhysicsServer3D.body_set_enable_continuous_collision_detection(body, true)
	var shape: RID
	var round: float = float(visual.get_meta(&"round_radius", 0.0))
	if round > 0.0:
		shape = PhysicsServer3D.cylinder_shape_create()
		PhysicsServer3D.shape_set_data(shape, {"radius": maxf(round, MIN_SHAPE_M * 0.5), "height": maxf(box.size.y, MIN_SHAPE_M)})
	else:
		shape = PhysicsServer3D.box_shape_create()
		PhysicsServer3D.shape_set_data(shape, box.size.max(Vector3.ONE * MIN_SHAPE_M) * 0.5)
	PhysicsServer3D.body_add_shape(body, shape, Transform3D(Basis.IDENTITY, box.get_center()))
	if drop_at == Vector3.INF:
		drop_at = Vector3(0.0, BackpackModel.BODY.y * 0.5, BackpackModel.BODY.z + 0.12)
	var start := Transform3D(Basis.IDENTITY, drop_at - box.get_center())
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, start)
	add_child(visual)
	visual.transform = start
	items.append({"id": item_id, "rid": body, "shape": shape, "visual": visual, "box": box, "still_s": 0.0, "calm_s": 0.0,
		"round": round, "state": state})
	return true


## Opens the compartment (its physics runs) or closes it (stopped, every pose kept as it is).
func set_open(open: bool) -> void:
	if open == _open:
		return
	_open = open
	PhysicsServer3D.space_set_active(_space, open)
	if open:
		_apply_gravity()
		disturb()


## Wakes every item and restarts its calm-down (a grab, a shake, something dropped on the heap).
func disturb() -> void:
	for item: Dictionary in items:
		item["calm_s"] = 0.0
		PhysicsServer3D.body_set_state(item["rid"], PhysicsServer3D.BODY_STATE_SLEEPING, false)


func is_open() -> bool:
	return _open


## True when every item has been still for SETTLE_S.
func is_settled() -> bool:
	for item: Dictionary in items:
		if float(item["still_s"]) < SETTLE_S:
			return false
	return true


## Item i's pose in pack space.
func pose(i: int) -> Transform3D:
	return PhysicsServer3D.body_get_state(items[i]["rid"], PhysicsServer3D.BODY_STATE_TRANSFORM)


## Item i's speed now, m/s.
func speed(i: int) -> float:
	return (PhysicsServer3D.body_get_state(items[i]["rid"], PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY) as Vector3).length()


## Each item's exact outline now, pack space (for the canvas bulge and for measuring).
func boxes() -> Array[AABB]:
	var out: Array[AABB] = []
	for i: int in items.size():
		out.append(extent(i))
	return out


## Item i's exact axis-aligned outline in pack space (a turned cylinder is not its box's corners).
func extent(i: int) -> AABB:
	var at: Transform3D = pose(i)
	var box: AABB = items[i]["box"]
	var reach: Vector3 = _reach(at.basis, box.size * 0.5, float(items[i]["round"]))
	return AABB(at * box.get_center() - reach, reach * 2.0)


func _physics_process(delta: float) -> void:
	if model == null or not _open:
		return
	_apply_gravity()
	for i: int in items.size():
		var item: Dictionary = items[i]
		var body: RID = item["rid"]
		var calm: float = float(item["calm_s"]) + delta
		item["calm_s"] = calm
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP, minf(LINEAR_DAMP + CALM_RAMP * calm, CALM_MAX_DAMP))
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP, minf(ANGULAR_DAMP + CALM_RAMP * calm, CALM_MAX_DAMP))
		_keep_inside(i)
		var spin: float = (PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY) as Vector3).length()
		var still: bool = speed(i) < SETTLE_SPEED and spin < SETTLE_SPEED * 3.0
		item["still_s"] = float(item["still_s"]) + delta if still else 0.0
		(item["visual"] as Node3D).transform = pose(i)
	model.set_interior_boxes(boxes())


## Projects item i back inside the walls (Jakobsen-style constraint projection): a heap pressed by a new drop
## can push a shape into a wall faster than the solver pushes it out; data stays inside whatever the solver did.
func _keep_inside(i: int) -> void:
	var item: Dictionary = items[i]
	var body: RID = item["rid"]
	var outline: AABB = extent(i)
	var room: AABB = inside()
	var high: Vector3 = room.end
	high.z = INF
	var push: Vector3 = (room.position - outline.position).max(Vector3.ZERO) + (high - outline.end).min(Vector3.ZERO)
	## Under half a millimetre is left to the solver: setting the pose wakes the body, and a heap must sleep.
	if push.length() < 0.0005:
		return
	var at: Transform3D = pose(i)
	at.origin += push
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, at)
	var velocity: Vector3 = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	for axis: int in 3:
		if push[axis] != 0.0 and signf(velocity[axis]) != signf(push[axis]):
			velocity[axis] = 0.0
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, velocity)


## Half extent along each pack axis of a box (or a cylinder of radius `round` round its local y) turned by basis.
static func _reach(basis: Basis, half: Vector3, round: float) -> Vector3:
	var out := Vector3.ZERO
	for axis: int in 3:
		var a := Vector3.ZERO
		a[axis] = 1.0
		var local: Vector3 = basis.transposed() * a
		if round > 0.0:
			var along: float = absf(local.y)
			out[axis] = along * half.y + round * sqrt(maxf(1.0 - along * along, 0.0))
		else:
			out[axis] = absf(local.x) * half.x + absf(local.y) * half.y + absf(local.z) * half.z
	return out


## World gravity turned into the pack's frame: tilt the pack and the heap slides.
func _apply_gravity() -> void:
	if model == null or not model.is_inside_tree():
		return
	var down: Vector3 = model.global_basis.orthonormalized().inverse() * Vector3.DOWN
	PhysicsServer3D.area_set_param(_space, PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR, down)


static func _gravity_strength() -> float:
	return float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))


func _exit_tree() -> void:
	for item: Dictionary in items:
		PhysicsServer3D.free_rid(item["rid"])
		PhysicsServer3D.free_rid(item["shape"])
	items.clear()
	if _walls.is_valid():
		PhysicsServer3D.free_rid(_walls)
		for shape: RID in _wall_shapes:
			PhysicsServer3D.free_rid(shape)
		PhysicsServer3D.free_rid(_space)
		_walls = RID()
