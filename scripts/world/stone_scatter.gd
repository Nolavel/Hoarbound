class_name StoneScatter
extends Node3D

## Loose stones along house walls near Henry (#257): now and then one lies at a wall's foot.
## Spots come from the building outlines and a hash of their position, so the same wall always
## has the same stones, and a taken one stays taken through the PickupLedger.

const ITEM_ID: StringName = &"stone"
## Henry's surroundings that get stones, and the range past which they are dropped again, metres.
const REACH_M: float = 45.0
const FORGET_M: float = 70.0
## One candidate spot per this much wall, of which this share holds a stone.
const SPOT_SPACING_M: float = 4.0
const CHANCE: float = 0.07
## A stone lies this far out from the wall face.
const WALL_GAP_M: float = 0.3
const REFRESH_S: float = 2.0
const SEED: int = 0x5701E

var _ground: KeyWestRealityGround
var _player: Node3D
var _spots: Dictionary = {}
var _refresh_left: float = 0.0


func on_world_ready(context: WorldContext) -> void:
	_ground = get_parent().find_child("RealityGround", false, false) as KeyWestRealityGround
	_player = context.player


func _process(delta: float) -> void:
	if _ground == null or not is_instance_valid(_player):
		return
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = REFRESH_S
	refresh(Vector2(_player.global_position.x, _player.global_position.z))


## Places the stones of the walls within REACH_M of centre and drops those past FORGET_M.
func refresh(centre: Vector2) -> void:
	var ledger: PickupLedger = PickupLedger.find(get_tree())
	var area := Rect2(centre - Vector2.ONE * REACH_M, Vector2.ONE * REACH_M * 2.0)
	for ring: PackedVector2Array in _ground.get_snow_obstacles_in_rect(area):
		for spot: Vector2 in wall_spots(ring):
			var id: StringName = StringName("stone:%d:%d" % [roundi(spot.x * 10.0), roundi(spot.y * 10.0)])
			if _spots.has(id) or spot.distance_to(centre) > REACH_M or (ledger != null and ledger.is_taken(id)):
				continue
			_spots[id] = _place(id, spot)
	for id: StringName in _spots.keys():
		var pickup: ItemPickup = _spots[id]
		if not is_instance_valid(pickup):
			_spots.erase(id)
		elif Vector2(pickup.global_position.x, pickup.global_position.z).distance_to(centre) > FORGET_M:
			pickup.queue_free()
			_spots.erase(id)


## Wall-foot points of one building outline that hold a stone, just outside the wall.
static func wall_spots(ring: PackedVector2Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var count: int = ring.size()
	for i: int in range(count):
		var a: Vector2 = ring[i]
		var b: Vector2 = ring[(i + 1) % count]
		var length: float = a.distance_to(b)
		if length < SPOT_SPACING_M * 0.5:
			continue
		var along: Vector2 = (b - a) / length
		var outward := Vector2(along.y, -along.x)
		var steps: int = maxi(1, floori(length / SPOT_SPACING_M))
		for s: int in range(steps):
			var foot: Vector2 = a + along * (float(s) + 0.5) * (length / float(steps))
			if _hash01(foot) >= CHANCE:
				continue
			var spot: Vector2 = foot + outward * WALL_GAP_M
			if Geometry2D.is_point_in_polygon(spot, ring):
				spot = foot - outward * WALL_GAP_M
			out.append(spot)
	return out


## A stable 0..1 value for a point, so a wall's stones never move between visits.
static func _hash01(point: Vector2) -> float:
	var h: int = hash(Vector3i(roundi(point.x * 10.0), roundi(point.y * 10.0), SEED))
	return float(h & 0xFFFF) / 65535.0


func _place(id: StringName, spot: Vector2) -> ItemPickup:
	var pickup := ItemPickup.new()
	pickup.item_id = ITEM_ID
	pickup.world_id = id
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.3
	collision.shape = shape
	pickup.add_child(collision)
	add_child(pickup)
	var y: float = _ground.get_surface_height(spot.x, spot.y)
	var shell: SnowShell = SnowShell.active
	if is_instance_valid(shell):
		## It lies on the snow, sunk a little into it, not buried under it.
		y += maxf(shell.field.get_depth(spot.x, spot.y) - 0.02, 0.0)
	pickup.global_transform = Transform3D(Basis(Vector3.UP, _hash01(spot * 3.7) * TAU), Vector3(spot.x, y, spot.y))
	return pickup
