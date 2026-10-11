extends SceneTree

## 727 Fort St shelter: the hut's gameplay nodes land on the landmark plan, inside the measured
## shell, and the shell's door opening really lets a body through.
## Run: godot --headless --script tests/systems/test_key_west_727_shelter.gd

const SHELL: String = "res://assets/world/key_west/landmarks/kw_727_fort_st.glb"

var _failures: int = 0
var _physics_start: int = 0
var _shelter: KeyWest727Shelter
var _shell: Node3D


func _initialize() -> void:
	_shelter = KeyWest727Shelter.new()
	_shelter.build()
	root.add_child(_shelter)
	_shell = (load(SHELL) as PackedScene).instantiate() as Node3D
	_shell.position = _shelter.position
	root.add_child(_shell)
	_physics_start = Engine.get_physics_frames()


func _process(_delta: float) -> bool:
	if Engine.get_physics_frames() - _physics_start < 3:
		return false  # let the physics server register the shell's collision
	_check_nodes()
	_check_openings()
	if _failures > 0:
		push_error("727 shelter: %d check(s) failed" % _failures)
		quit(1)
	else:
		print("727 shelter: all checks passed")
		quit(0)
	return true


func _check_nodes() -> void:
	var house: Node3D = _shelter.get_node_or_null(^"House") as Node3D
	_check(house != null, "House was not built")
	if house == null:
		return
	var door: HingedDoor = house.get_node_or_null(^"HouseDoor") as HingedDoor
	var zone: ThermalZone = house.get_node_or_null(^"ShelterZone") as ThermalZone
	var clinic: ThermalZone = house.get_node_or_null(^"ClinicZone") as ThermalZone
	_check(door != null and zone != null and clinic != null, "door or zones missing")
	if door == null or zone == null or clinic == null:
		return
	_check(door.opening_size.is_equal_approx(Vector2(1.5, 2.25)), "door is not the hut standard: %s" % door.opening_size)
	_check(door.breach == zone.get_node_or_null(^"Door"), "door is not wired to the shelter breach")
	_check(zone.get_node_or_null(^"Stove") is HeatSource, "stove missing from the heated zone")
	_check(zone.is_interior and clinic.is_interior, "zones must count as indoors")
	_check(clinic.zone_priority < zone.zone_priority, "the heated zone must win where boxes touch")
	var windows: int = 0
	for o: Dictionary in _shelter.interior["openings"]:
		windows += 1 if o["kind"] == "window" else 0
	var breaches: int = zone.get_breaches().size() + clinic.get_breaches().size()
	_check(breaches == windows + 1, "expected %d breaches (windows + door), got %d" % [windows + 1, breaches])
	for breach: ShelterBreach in clinic.get_breaches():
		_check(breach.boarded_visual != null and breach.is_ancestor_of(breach.boarded_visual),
			"%s boards point outside the copy" % breach.name)
	var outline: PackedVector2Array = PackedVector2Array()
	for p: Array in _shelter.interior["outline_uv"]:
		outline.append(Vector2(float(p[0]), float(p[1])))
	for item: Dictionary in _shelter.interior["furniture"]:
		var node: Node3D = house.find_child(String(item["node"]), true, false) as Node3D
		_check(node != null, "furniture %s missing" % item["node"])
		if node != null:
			var at: Vector3 = house.global_transform.affine_inverse() * node.global_position
			_check(Geometry2D.is_point_in_polygon(Vector2(at.x, at.z), outline), "%s stands outside the walls" % item["node"])
	var zone_centre: Vector3 = _room_centre("waiting")
	_check(_inside_zone(zone, zone_centre), "waiting room centre is outside the heated zone")
	_check(_inside_zone(clinic, _room_centre("exam_1")), "exam room centre is outside the clinic zone")
	_check(_shelter.get_node_or_null(^"ShelterSpawnPoint") is Marker3D, "ShelterSpawnPoint missing")


## A ray through the main door's centre crosses the wall line; one beside it hits the wall.
func _check_openings() -> void:
	var space: PhysicsDirectSpaceState3D = _shell.get_world_3d().direct_space_state
	var house: Node3D = _shelter.get_node(^"House") as Node3D
	for o: Dictionary in _shelter.interior["openings"]:
		if o["kind"] != "door" and o["kind"] != "window":
			continue
		var c: Vector3 = Vector3(float(o["centre_uv"][0]), (float(o["y0"]) + float(o["y1"])) * 0.5, float(o["centre_uv"][1]))
		var out: Vector3 = Vector3(float(o["outward_uv"][0]), 0.0, float(o["outward_uv"][1]))
		var side: Vector3 = Vector3(-out.z, 0.0, out.x) * (float(o["width_m"]) * 0.5 + 0.3)
		var hit_open: Dictionary = _ray(space, house, c + out * 1.0, c - out * 1.0)
		_check(hit_open.is_empty(), "%s opening is blocked at %s" % [o["name"], c])
		if o["kind"] == "door":
			_check(not _ray(space, house, c + side + out, c + side - out).is_empty(), "%s has no wall beside it" % o["name"])


func _ray(space: PhysicsDirectSpaceState3D, house: Node3D, a: Vector3, b: Vector3) -> Dictionary:
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(house.global_transform * a, house.global_transform * b)
	q.collide_with_areas = false
	var exclude: Array[RID] = []
	for body: Node in _shelter.find_children("*", "CollisionObject3D", true, false):
		exclude.append((body as CollisionObject3D).get_rid())
	q.exclude = exclude
	return space.intersect_ray(q)


func _room_centre(room_id: String) -> Vector3:
	for room: Dictionary in _shelter.interior["rooms"]:
		if room["id"] == room_id:
			var r: Array = room["rect_uv"]
			return Vector3((float(r[0]) + float(r[2])) * 0.5, float(_shelter.interior["floor_y"]) + 1.0, (float(r[1]) + float(r[3])) * 0.5)
	return Vector3.ZERO


func _inside_zone(zone: ThermalZone, house_point: Vector3) -> bool:
	var house: Node3D = _shelter.get_node(^"House") as Node3D
	var world_point: Vector3 = house.global_transform * house_point
	for child: Node in zone.get_children():
		var shape: CollisionShape3D = child as CollisionShape3D
		if shape != null and shape.shape is BoxShape3D:
			var local: Vector3 = shape.global_transform.affine_inverse() * world_point
			if AABB(-(shape.shape as BoxShape3D).size * 0.5, (shape.shape as BoxShape3D).size).has_point(local):
				return true
	return false


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("727 shelter: %s" % message)
