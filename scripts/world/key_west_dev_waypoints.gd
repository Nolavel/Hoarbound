class_name KeyWestDevWaypoints
extends Node3D
## Debug-build navigation: F5 cycles route goals and addresses (beacon, distance/bearing line); F6 holds Henry at the
## target until its ground is live, then stands him on a free spot outside buildings. Freed in release builds.

const ROUTE_PATH: String = "res://data/world/key_west/reality/routes/first_exit_gate.json"
const BEACON_HEIGHT_M: float = 150.0
const BEACON_COLOUR: Color = Color(1.0, 0.35, 0.05, 0.55)
## Gap between the ground and Henry's shape when he is set down.
const TELEPORT_CLEARANCE_M: float = 0.05
## Free-spot search around the wanted spot: ring spacing, ring count, points per ring.
const SPOT_STEP_M: float = 1.5
const SPOT_RINGS: int = 12
const SPOT_DIRECTIONS: int = 12
## How far out from a facade an address spot stands, and how far its open side is probed.
const FACADE_OFFSET_M: float = 2.0
const OPEN_PROBE_M: float = 30.0
## A held teleport warns once after this long without live ground.
const WAIT_WARN_MS: int = 15000
const COMPASS: Array[String] = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

## Addresses resolved through the Reality editor index, after the route goals.
@export var addresses: PackedStringArray = PackedStringArray(["727 fort st", "907 whitehead st"])

var _player: Node3D
var _camera: Camera3D
var _ground: KeyWestRealityGround
var _index: RealityIndex
var _targets: Array[Dictionary] = []  # {"name", "at": Vector3 (xz), "spots": PackedVector2Array, preferred first}
var _pending: PackedVector2Array = PackedVector2Array()
var _pending_since_ms: int = 0
var _warned: bool = false
var _current: int = -1
var _beacon: MeshInstance3D
var _label: Label3D
var _hud: Label


func on_world_ready(context: WorldContext) -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	_player = context.player
	_camera = context.camera
	_ground = get_parent().find_child("RealityGround", false, false) as KeyWestRealityGround
	var input_systems: Node = get_node_or_null(^"/root/InputSystems")
	if input_systems == null or not input_systems.has_signal(&"dev_waypoint_next_pressed"):
		return
	input_systems.connect(&"dev_waypoint_next_pressed", next_target)
	input_systems.connect(&"dev_waypoint_teleport_pressed", teleport)
	set_process(false)
	set_physics_process(false)


## Next target, or off after the last; the list is read on first use.
func next_target() -> void:
	if _targets.is_empty():
		_load_targets()
	_current = _current + 1 if _current + 1 < _targets.size() else -1
	_show()


## Moves Henry to the current target and holds him there until its ground is live, then sets him down on a free spot.
func teleport() -> void:
	if _current < 0 or _player == null or is_teleporting():
		return
	_pending = _targets[_current]["spots"]
	_pending_since_ms = Time.get_ticks_msec()
	_warned = false
	## The streamer loads around Henry, so he waits at the target with his own physics off and cannot fall.
	_player.set_physics_process(false)
	_player.global_position = Vector3(_pending[0].x, _player.global_position.y, _pending[0].y)
	if _player is CharacterBody3D:
		(_player as CharacterBody3D).velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	set_physics_process(true)


## True while a teleport waits for its ground.
func is_teleporting() -> bool:
	return not _pending.is_empty()


func current_target() -> Dictionary:
	return _targets[_current] if _current >= 0 else {}


func target_names() -> PackedStringArray:
	if _targets.is_empty():
		_load_targets()
	var out: PackedStringArray = PackedStringArray()
	for t: Dictionary in _targets:
		out.append(t["name"])
	return out


func _physics_process(_delta: float) -> void:
	if _pending.is_empty():
		set_physics_process(false)
		return
	if _ground == null or not _ground.has_ground_at(_pending[0].x, _pending[0].y):
		if not _warned and Time.get_ticks_msec() - _pending_since_ms > WAIT_WARN_MS:
			_warned = true
			push_warning("KeyWestDevWaypoints: still waiting for the ground at %s" % _pending[0])
		return
	_land(_free_spot(_pending))
	_pending = PackedVector2Array()
	set_physics_process(false)


func _process(_delta: float) -> void:
	if _current < 0 or _player == null:
		return
	var at: Vector3 = _targets[_current]["at"]
	var d: Vector2 = Vector2(at.x - _player.global_position.x, at.z - _player.global_position.z)
	## Local frame: x east, z south; compass 0 is north (-z).
	var sector: int = posmod(roundi(rad_to_deg(atan2(d.x, -d.y)) / 45.0), 8)
	_hud.text = "Dev target %d/%d: %s, %d m %s   [F5 next, F6 teleport]" % [_current + 1, _targets.size(), _targets[_current]["name"],
		roundi(d.length()), COMPASS[sector]]


func _load_targets() -> void:
	var seen: Dictionary = {}
	var route: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROUTE_PATH))
	if route is Dictionary:
		for goal: Dictionary in (route as Dictionary).get("goals", []):
			var xz: Array = goal["xz"]
			var key: String = "%.1f_%.1f" % [float(xz[0]), float(xz[1])]
			if seen.has(key):
				continue
			seen[key] = true
			var at: Vector2 = Vector2(float(xz[0]), float(xz[1]))
			_targets.append({"name": String(goal["name"]), "at": Vector3(at.x, 0.0, at.y), "spots": PackedVector2Array([at])})
	_index = RealityIndex.new()
	if not addresses.is_empty() and _index.load_index():
		for query: String in addresses:
			var hits: Array = _index.search(query, 1)
			if hits.is_empty():
				push_warning("KeyWestDevWaypoints: no building for '%s'" % query)
				continue
			var b: Dictionary = hits[0]
			_targets.append({"name": RealityIndex.label_of(b), "at": Vector3(float(b["c"][0]), 0.0, float(b["c"][1])),
				"spots": _facade_spots(b)})


## Points FACADE_OFFSET_M out from each wall's midpoint, the wall facing the most open ground (the street) first.
func _facade_spots(b: Dictionary) -> PackedVector2Array:
	var ring: Array = b["ring"]
	var poly: PackedVector2Array = PackedVector2Array()
	for k: int in range(0, ring.size(), 2):
		poly.append(Vector2(float(ring[k]), float(ring[k + 1])))
	var centre: Vector2 = Vector2(float(b["c"][0]), float(b["c"][1]))
	var scored: Array = []
	for i: int in range(poly.size()):
		var a: Vector2 = poly[i]
		var e: Vector2 = poly[(i + 1) % poly.size()] - a
		if e.length() < 1.0:
			continue
		var mid: Vector2 = a + e * 0.5
		var out: Vector2 = Vector2(e.y, -e.x).normalized()
		if out.dot(mid - centre) < 0.0:
			out = -out
		var open: float = 0.0
		while open < OPEN_PROBE_M and _index.pick(mid.x + out.x * (open + 1.0), mid.y + out.y * (open + 1.0)).is_empty():
			open += 1.0
		scored.append([open, e.length(), mid + out * FACADE_OFFSET_M])
	scored.sort_custom(func(p: Array, q: Array) -> bool: return p[0] > q[0] or (p[0] == q[0] and p[1] > q[1]))
	var spots: PackedVector2Array = PackedVector2Array()
	for s: Array in scored:
		spots.append(s[2])
	if spots.is_empty():
		spots.append(centre)
	return spots


## First spot, in preference order then in rings around the first, where Henry's own shape overlaps nothing.
func _free_spot(spots: PackedVector2Array) -> Vector3:
	var candidates: PackedVector2Array = spots.duplicate()
	for r: int in range(1, SPOT_RINGS + 1):
		for d: int in range(SPOT_DIRECTIONS):
			candidates.append(spots[0] + Vector2.from_angle(TAU * d / SPOT_DIRECTIONS) * SPOT_STEP_M * r)
	var shape: CollisionShape3D = _body_shape()
	var space: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
	for c: Vector2 in candidates:
		if not _ground.has_ground_at(c.x, c.y):
			continue
		var at: Vector3 = _stand_at(c, shape)
		if shape == null or not (_player is CollisionObject3D):
			return at
		var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
		query.shape = shape.shape
		query.transform = Transform3D(shape.basis, at + shape.position)
		query.collision_mask = (_player as CollisionObject3D).collision_mask
		query.exclude = [(_player as CollisionObject3D).get_rid()]
		if space.intersect_shape(query, 1).is_empty():
			return at
	push_warning("KeyWestDevWaypoints: no free spot near %s, standing on the first" % spots[0])
	return _stand_at(spots[0], shape)


## Henry's origin with the bottom of his shape TELEPORT_CLEARANCE_M over the ground at xz.
func _stand_at(xz: Vector2, shape: CollisionShape3D) -> Vector3:
	var bottom: float = 0.0
	if shape != null and shape.shape is CapsuleShape3D:
		bottom = shape.position.y - (shape.shape as CapsuleShape3D).height * 0.5
	return Vector3(xz.x, _ground.get_height(xz.x, xz.y) - bottom + TELEPORT_CLEARANCE_M, xz.y)


func _body_shape() -> CollisionShape3D:
	for child: Node in _player.get_children():
		if child is CollisionShape3D and not (child as CollisionShape3D).disabled:
			return child
	return null


func _land(at: Vector3) -> void:
	_player.global_position = at
	if _player is CharacterBody3D:
		(_player as CharacterBody3D).velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	_player.set_physics_process(true)
	if _camera is TpsCamera:
		(_camera as TpsCamera).snap_to_target()
	print("Dev waypoint: teleported to %s at %s" % [_targets[_current]["name"] if _current >= 0 else "?", at])


func _show() -> void:
	if _beacon == null:
		_build_markers()
	var on: bool = _current >= 0
	_beacon.visible = on
	_label.visible = on
	_hud.visible = on
	set_process(on)
	if not on:
		return
	var at: Vector3 = _targets[_current]["at"]
	var y: float = _ground.get_height(at.x, at.z) if _ground != null else 0.0
	_beacon.global_position = Vector3(at.x, y + BEACON_HEIGHT_M * 0.5, at.z)
	_label.global_position = Vector3(at.x, y + BEACON_HEIGHT_M + 4.0, at.z)
	_label.text = _targets[_current]["name"]
	_process(0.0)


func _build_markers() -> void:
	_beacon = MeshInstance3D.new()
	_beacon.name = "Beacon"
	var column: CylinderMesh = CylinderMesh.new()
	column.top_radius = 0.8
	column.bottom_radius = 0.8
	column.height = BEACON_HEIGHT_M
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = BEACON_COLOUR
	mat.no_depth_test = true  # seen through buildings
	column.material = mat
	_beacon.mesh = column
	_beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beacon)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0015
	_label.font_size = 28
	_label.outline_size = 8
	add_child(_label)
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 41
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(24.0, 24.0)
	_hud.add_theme_font_size_override(&"font_size", 20)
	_hud.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override(&"outline_size", 6)
	layer.add_child(_hud)
