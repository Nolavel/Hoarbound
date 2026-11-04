class_name PackInterior
extends Node3D

## The main compartment without slots (3D inventory, stage 0): what Henry carries lies in it as rigid bodies on
## simple shapes (a Cairn-style physics container). The bodies live in a physics space of their own, in pack
## space: the walls never move, gravity is turned into the pack's frame each step, carrying the pack cannot
## fling anything, and nothing inside touches the world. Closed, the space stops and every pose stays as it was.
## The walls are the canvas itself: its rounded inside, giving only as far as the canvas bulges over an item
## (BackpackModel.CANVAS_STRETCH_M); slack cloth sags only onto what is in.

signal refused(item_id: StringName, reason: StringName)
## Item i left the pack (thrown out with G); the caller puts it in the world.
signal removed(item_id: StringName, state: Dictionary)

## How far past the canvas's resting inside an item may press, metres: the canvas bulges this much and more
## (CANVAS_STRETCH_M), so the cloth always stays over what pushes it.
const STRETCH_M: float = BackpackModel.CANVAS_STRETCH_M - 0.004
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
## No item in the pack moves faster than this (m/s, rad/s): a solver pushing two shapes apart can fling them,
## as PhysX's max depenetration velocity guards against.
const MAX_SPEED: float = 2.0
const MAX_SPIN: float = 12.0
## A held item is pulled toward the cursor's point like a stiff spring: its grab point closes this share of the
## gap each second, never faster than HOLD_MAX_SPEED (velocity drive, as Penumbra and Amnesia carry props).
const HOLD_GAIN: float = 14.0
## A held item's mass is MASS_MAX times this while held.
const HELD_MASS_SCALE: float = 4.0
const HOLD_MAX_SPEED: float = 2.5
## A held item turns by this many radians per wheel notch, about the camera's line of sight.
const TURN_STEP: float = deg_to_rad(15.0)
## The shove (RMB) moves what lies this close to the cursor's point, never faster than SHOVE_MAX_SPEED, m, m/s.
const SHOVE_RADIUS_M: float = 0.04
const SHOVE_MAX_SPEED: float = 0.6
## A part much longer than wide is cut into this many boxes along its length (a tool's head and handle).
const SLICES: int = 6
static var _part_cache: Dictionary = {}
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
var _drawn_boxes: Array[AABB] = []
## The held item: index (-1 none), its grab point in its own space, where the cursor wants that point (pack
## space), and the turn the wheel asks of it (pack space).
var _held: int = -1
var _held_local: Vector3 = Vector3.ZERO
var _held_target: Vector3 = Vector3.ZERO
var _held_basis: Basis = Basis.IDENTITY


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
	## The walls are the canvas's inner rounded box at full stretch, as a closed mesh hit from inside.
	var room: AABB = inside()
	var mesh: ArrayMesh = BackpackModel._rounded_box(room.size * 0.5, room.get_center(), _inner_round() + STRETCH_M,
		BackpackModel.STEPS, BackpackModel.FACES_ALL)
	var shape: RID = PhysicsServer3D.concave_polygon_shape_create()
	PhysicsServer3D.shape_set_data(shape, {"faces": mesh.get_faces(), "backface_collision": true})
	PhysicsServer3D.body_add_shape(_walls, shape)
	_wall_shapes.append(shape)
	_apply_gravity()


## The compartment's inside at full stretch, pack space: the canvas's inner box grown by STRETCH_M (its edges
## are rounded; see overshoot()).
static func inside() -> AABB:
	var half: Vector3 = BackpackModel.BODY * 0.5 - Vector3.ONE * (BackpackModel.CANVAS_LINING_M - STRETCH_M)
	return AABB(_centre() - half, half * 2.0)


## The canvas's inner surface: a rounded box (centre, half size, edge radius) in pack space.
static func _centre() -> Vector3:
	return Vector3(0.0, BackpackModel.BODY.y * 0.5, BackpackModel.BODY.z * 0.5)


static func _inner_half() -> Vector3:
	return BackpackModel.BODY * 0.5 - Vector3.ONE * BackpackModel.CANVAS_LINING_M


static func _inner_round() -> float:
	return BackpackModel.ROUND_M - BackpackModel.CANVAS_LINING_M


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
	var room: Vector3 = inside().size
	## Through the front opening on its two smallest sides, and lying in the depth on its smallest one.
	if dims[0] > room.z or dims[1] > room.x or dims[2] > room.y:
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


## Puts item_id in at `drop_at` (pack space, its centre; defaults high in the middle); it falls while open. False with refused(...) when it cannot go in.
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
	var mass: float = clampf(kind.weight if kind != null else 0.3, MASS_MIN, MASS_MAX)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_MASS, mass)
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
		drop_at = Vector3(0.0, BackpackModel.BODY.y * 0.75, BackpackModel.BODY.z * 0.5)
	var turn: Basis = fit_basis(box.size)
	var start := Transform3D(turn, drop_at - turn * box.get_center())
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, start)
	add_child(visual)
	## Picked by its own outline (part boxes), not its collision box: a hammer's box is mostly air.
	var parts: Array[AABB] = []
	if round <= 0.0:
		parts = _parts_for(item_id, visual)
	if parts.is_empty():
		parts.append(box)
	items.append({"id": item_id, "rid": body, "shape": shape, "visual": visual, "box": box, "still_s": 0.0, "calm_s": 0.0,
		"round": round, "parts": parts, "mass": mass, "state": state})
	## Started inside the canvas, wherever it was asked to go.
	_keep_inside(items.size() - 1)
	visual.transform = pose(items.size() - 1)
	return true


## Each item kind's drawn outline for picking (visual root space), cached: a tight box per mesh part, or SLICES
## boxes across a part much longer than wide (a tool's head and its handle).
static func _parts_for(item_id: StringName, visual: Node3D) -> Array[AABB]:
	if _part_cache.has(item_id):
		return _part_cache[item_id]
	var out: Array[AABB] = []
	for node: Node in visual.find_children("*", "MeshInstance3D", true, false) + ([visual] if visual is MeshInstance3D else []):
		var part := node as MeshInstance3D
		if part.mesh == null:
			continue
		var to_root: Transform3D = _path_transform(visual, part)
		var verts := PackedVector3Array()
		for surface: int in part.mesh.get_surface_count():
			for v: Vector3 in part.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				verts.append(to_root * v)
		if verts.is_empty():
			continue
		var bounds := AABB(verts[0], Vector3.ZERO)
		for v: Vector3 in verts:
			bounds = bounds.expand(v)
		## Tiny parts (rivets) live inside their neighbours' boxes.
		if bounds.size.length() < MIN_SHAPE_M:
			continue
		var axis: int = bounds.size.max_axis_index()
		var long_side: float = bounds.size[axis]
		var others: float = maxf(bounds.size[(axis + 1) % 3], bounds.size[(axis + 2) % 3])
		var slices: int = SLICES if long_side > others * 2.0 else 1
		var boxes: Array = []
		boxes.resize(slices)
		for v: Vector3 in verts:
			var k: int = mini(int((v[axis] - bounds.position[axis]) / maxf(long_side, 0.0001) * slices), slices - 1)
			boxes[k] = AABB(v, Vector3.ZERO) if boxes[k] == null else (boxes[k] as AABB).expand(v)
		for k: int in slices:
			if boxes[k] == null:
				continue
			## Each slice spans its whole band along the part, so neighbours meet with no gap.
			var box: AABB = boxes[k]
			var from: float = bounds.position[axis] + long_side * float(k) / float(slices)
			box = box.expand(_on_axis(box.get_center(), axis, from)).expand(_on_axis(box.get_center(), axis, from + long_side / float(slices)))
			out.append(box)
	_part_cache[item_id] = out
	return out


static func _on_axis(at: Vector3, axis: int, value: float) -> Vector3:
	at[axis] = value
	return at


static func _path_transform(root: Node3D, node: Node3D) -> Transform3D:
	var at := Transform3D.IDENTITY
	var walk: Node = node
	while walk != null and walk != root:
		if walk is Node3D:
			at = (walk as Node3D).transform * at
		walk = walk.get_parent()
	return at


## The turn that puts an item in the way it passes the mouth: its longest side up, its middle one across, its
## thinnest front to back.
static func fit_basis(size: Vector3) -> Basis:
	var order: Array = [0, 1, 2]
	order.sort_custom(func(a: int, b: int) -> bool: return size[a] < size[b])
	var columns: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	columns[order[0]] = Vector3.BACK
	columns[order[1]] = Vector3.RIGHT
	columns[order[2]] = Vector3.UP
	var turn := Basis(columns[0], columns[1], columns[2])
	if turn.determinant() < 0.0:
		columns[order[0]] = Vector3.FORWARD
		turn = Basis(columns[0], columns[1], columns[2])
	return turn


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


## The outlines last handed to the canvas (what it bulges over), pack space.
func drawn_boxes() -> Array[AABB]:
	return _drawn_boxes


## Item i's exact axis-aligned outline in pack space (a turned cylinder is not its box's corners).
func extent(i: int) -> AABB:
	var points: PackedVector3Array = support_points(i)
	var out := AABB(points[0], Vector3.ZERO)
	for point: Vector3 in points:
		out = out.expand(point)
	return out


## The item and point a pack-space ray from `from` to `to` meets first, on the items' drawn outlines (part
## boxes): {"index", "point"}, or {} for none.
func pick(from: Vector3, to: Vector3) -> Dictionary:
	if not _open:
		return {}
	var best: float = INF
	var found: Dictionary = {}
	for i: int in items.size():
		var to_item: Transform3D = (items[i]["visual"] as Node3D).transform.affine_inverse()
		var a: Vector3 = to_item * from
		var b: Vector3 = to_item * to
		for part: AABB in items[i]["parts"]:
			var hit: Variant = part.intersects_segment(a, b)
			if hit == null:
				continue
			var at: Vector3 = (items[i]["visual"] as Node3D).transform * (hit as Vector3)
			var distance: float = from.distance_to(at)
			if distance < best:
				best = distance
				found = {"index": i, "point": at}
	return found


## Takes item i by `point` (pack space, on it): from now it follows move_held() until let_go().
func hold(i: int, point: Vector3) -> void:
	if i < 0 or i >= items.size():
		return
	let_go()
	_held = i
	## A hand pulls harder than the heap leans on it: heavy while held, it shoves what lies on it aside.
	PhysicsServer3D.body_set_param(items[i]["rid"], PhysicsServer3D.BODY_PARAM_MASS, MASS_MAX * HELD_MASS_SCALE)
	_held_local = pose(i).affine_inverse() * point
	_held_target = point
	_held_basis = pose(i).basis.orthonormalized()
	disturb()


## Where the held item's grab point should go (pack space; kept inside the canvas).
func move_held(target: Vector3) -> void:
	_held_target = target


## Turns the held item by `notches` wheel steps about `axis` (pack space).
func turn_held(notches: float, axis: Vector3) -> void:
	if _held >= 0:
		_held_basis = Basis(axis.normalized(), notches * TURN_STEP) * _held_basis


func let_go() -> void:
	if _held >= 0:
		PhysicsServer3D.body_set_param(items[_held]["rid"], PhysicsServer3D.BODY_PARAM_MASS, float(items[_held]["mass"]))
		disturb()
	_held = -1


func held() -> int:
	return _held


## Where the held item's grab point is now (pack space).
func held_point() -> Vector3:
	return pose(_held) * _held_local if _held >= 0 else Vector3.INF


## Takes item i out of the pack: {"id", "state"} and removed(...), or {} for a wrong index.
func remove(i: int) -> Dictionary:
	if i < 0 or i >= items.size():
		return {}
	var item: Dictionary = items[i]
	if _held == i:
		_held = -1
	elif _held > i:
		_held -= 1
	PhysicsServer3D.free_rid(item["rid"])
	PhysicsServer3D.free_rid(item["shape"])
	(item["visual"] as Node3D).queue_free()
	items.remove_at(i)
	disturb()
	removed.emit(item["id"], item["state"])
	return {"id": item["id"], "state": item["state"]}


## The shove (RMB): what lies within SHOVE_RADIUS_M of `point` (pack space) is swept along `motion` (m/s,
## pack space, capped at SHOVE_MAX_SPEED) like a hand pushing through the heap; no body of infinite mass.
func shove(point: Vector3, motion: Vector3) -> void:
	if motion.length() > SHOVE_MAX_SPEED:
		motion = motion.normalized() * SHOVE_MAX_SPEED
	for i: int in items.size():
		if i == _held:
			continue
		var outline: AABB = extent(i)
		if _box_distance(point, outline) > SHOVE_RADIUS_M:
			continue
		var body: RID = items[i]["rid"]
		var velocity: Vector3 = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
		velocity += (motion - velocity).project(motion.normalized()) if motion.length() > 0.001 else Vector3.ZERO
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, velocity)
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_SLEEPING, false)
		items[i]["calm_s"] = 0.0


static func _box_distance(p: Vector3, box: AABB) -> float:
	var q: Vector3 = (p - box.get_center()).abs() - box.size * 0.5
	return q.max(Vector3.ZERO).length() + minf(maxf(q.x, maxf(q.y, q.z)), 0.0)


func _physics_process(delta: float) -> void:
	if model == null or not _open:
		return
	_apply_gravity()
	_drive_held(delta)
	for i: int in items.size():
		var item: Dictionary = items[i]
		var body: RID = item["rid"]
		var calm: float = float(item["calm_s"]) + delta if i != _held else 0.0
		item["calm_s"] = calm
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP, minf(LINEAR_DAMP + CALM_RAMP * calm, CALM_MAX_DAMP))
		PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP, minf(ANGULAR_DAMP + CALM_RAMP * calm, CALM_MAX_DAMP))
		_cap_speed(body)
		_keep_inside(i)
		var spin: float = (PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY) as Vector3).length()
		var still: bool = speed(i) < SETTLE_SPEED and spin < SETTLE_SPEED * 3.0
		item["still_s"] = float(item["still_s"]) + delta if still else 0.0
		(item["visual"] as Node3D).transform = pose(i)
	_drawn_boxes = boxes()
	model.set_interior_boxes(_drawn_boxes)


func _cap_speed(body: RID) -> void:
	var velocity: Vector3 = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	if velocity.length() > MAX_SPEED:
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, velocity.normalized() * MAX_SPEED)
	var spin: Vector3 = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
	if spin.length() > MAX_SPIN:
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, spin.normalized() * MAX_SPIN)


## Velocity drive of the held item toward the cursor's point, and its wheel turns.
func _drive_held(delta: float) -> void:
	if _held < 0:
		return
	var body: RID = items[_held]["rid"]
	var gap: Vector3 = _held_target - held_point()
	var velocity: Vector3 = gap * HOLD_GAIN
	if velocity.length() > HOLD_MAX_SPEED:
		velocity = velocity.normalized() * HOLD_MAX_SPEED
	## Gravity is cancelled for the step: a held item hangs where the hand is.
	velocity -= _gravity_vector() * delta
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, velocity)
	## The wheel sets a target turn; the item spins toward it and the heap can stop it (no turning through a pan).
	var error: Quaternion = _held_basis.get_rotation_quaternion() * pose(_held).basis.get_rotation_quaternion().inverse()
	if error.w < 0.0:
		error = -error
	var angle: float = error.get_angle()
	var spin := Vector3.ZERO
	if angle > 0.001:
		spin = error.get_axis().normalized() * minf(angle * HOLD_GAIN, MAX_SPIN)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, spin)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_SLEEPING, false)


func _gravity_vector() -> Vector3:
	return model.global_basis.orthonormalized().inverse() * Vector3.DOWN * _gravity_strength()


## Projects item i back inside the canvas (Jakobsen-style constraint projection): a heap pressed by a new drop
## can push a shape into a wall faster than the solver pushes it out; the data stays inside whatever it did.
func _keep_inside(i: int) -> void:
	var body: RID = items[i]["rid"]
	var at: Transform3D = pose(i)
	var moved := Vector3.ZERO
	for _pass: int in 6:
		var worst: float = 0.0
		var normal := Vector3.ZERO
		for point: Vector3 in support_points(i):
			var gap: Array = _past_canvas(point + moved)
			if float(gap[0]) > worst:
				worst = gap[0]
				normal = gap[1]
		## Under half a millimetre is left to the solver: setting the pose wakes the body, and a heap must sleep.
		if worst < 0.0005:
			break
		moved -= normal * worst
	if moved.is_zero_approx():
		return
	at.origin += moved
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, at)
	var velocity: Vector3 = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var into: Vector3 = -moved.normalized()
	velocity -= into * maxf(velocity.dot(into), 0.0)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, velocity)


## How far item i reaches past what the canvas allows at its worst point, metres (0 or less: inside).
func overshoot(i: int) -> float:
	var worst: float = -INF
	for point: Vector3 in support_points(i):
		worst = maxf(worst, float(_past_canvas(point)[0]))
	return worst


## The points that bound item i's shape now, pack space: a box's corners, or two rims of a cylinder. `drawn`
## reads the pose last drawn (after the projection) instead of the body's.
func support_points(i: int, drawn: bool = false) -> PackedVector3Array:
	var at: Transform3D = (items[i]["visual"] as Node3D).transform if drawn else pose(i)
	var box: AABB = items[i]["box"]
	var round: float = float(items[i]["round"])
	var out := PackedVector3Array()
	var c: Vector3 = box.get_center()
	var half: Vector3 = box.size * 0.5
	if round > 0.0:
		for k: int in 16:
			var a: float = TAU * float(k) / 16.0
			for y: float in [-half.y, half.y]:
				out.append(at * (c + Vector3(cos(a) * round, y, sin(a) * round)))
	else:
		for k: int in 8:
			out.append(at * (c + Vector3(half.x * (1 - 2 * (k & 1)), half.y * (1 - 2 * ((k >> 1) & 1)), half.z * (1 - 2 * ((k >> 2) & 1)))))
	return out


## [distance a pack-space point lies past the allowed inside, outward normal there]: the canvas's inner rounded
## box grown by STRETCH_M (slack cloth only sags onto the contents, never into them).
func _past_canvas(q: Vector3) -> Array:
	var c: Vector3 = _centre()
	var r: float = _inner_round()
	var core: Vector3 = _inner_half() - Vector3.ONE * r
	var d: Vector3 = q - c
	var excess: Vector3 = d.abs() - core
	var outside: Vector3 = excess.max(Vector3.ZERO)
	var normal: Vector3
	var distance: float
	if outside.length() > 0.00001:
		normal = (outside * d.sign()).normalized()
		distance = outside.length() - r
	else:
		## Deep in the core: the nearest face.
		var axis: int = excess.max_axis_index()
		normal = Vector3.ZERO
		normal[axis] = signf(d[axis]) if d[axis] != 0.0 else 1.0
		distance = excess[axis] - r
	return [distance - STRETCH_M, normal]


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
