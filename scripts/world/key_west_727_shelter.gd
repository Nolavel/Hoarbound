class_name KeyWest727Shelter
extends Node3D
## The First Exit hut's door, thermal zone, stove, breaches and furniture inside the measured
## 727 Fort St shell, placed on the landmark spec's game-invented clinic plan.

const TEMPLATE: PackedScene = preload("res://scenes/world/first_exit/first_exit_blockout.tscn")
const SPEC_PATH: String = "res://data/world/key_west/reality/landmarks/kw_727_fort_st.json"
## Hut ShelterZone space: the zone origin sits this far above the finished floor.
const ZONE_ABOVE_FLOOR: float = 1.175
const ZONE_BOX_HEIGHT: float = 2.55
## Hut window breaches, in the order the spec's heated-room windows take them.
const HUT_WINDOWS: Array[String] = ["FrontWindow1", "FrontWindow2", "BackWindow1", "BackWindow2"]
const HUT_KINDS: Dictionary = {"hut_stove": "ShelterZone/Stove", "hut_mattress": "ShelterZone/Mattress",
	"hut_rest_crate": "ShelterZone/RestCrate", "hut_cabinet": "ShelterZone/Cabinet",
	"hut_tool_bench": "ToolBench", "hut_supply_bench": "SupplyBench"}
const CLINIC_OFFSET_C: float = 4.0
const CLINIC_WIND_EXPOSURE: float = 0.15
const CLINIC_WINDOW_SEVERITY: float = 0.2
const SPAWN_BEFORE_RAMP_M: float = 2.0
const PIPE_ABOVE_ROOF_M: float = 0.8
const BOX_COLOURS: Dictionary = {"counter": Color(0.62, 0.56, 0.48), "bench": Color(0.36, 0.40, 0.46),
	"exam_table": Color(0.70, 0.74, 0.72), "desk": Color(0.55, 0.47, 0.38), "dental_chair": Color(0.42, 0.56, 0.60),
	"cart": Color(0.66, 0.66, 0.68), "shelf": Color(0.50, 0.46, 0.40), "toilet": Color(0.90, 0.90, 0.88),
	"sink": Color(0.86, 0.87, 0.88)}

var interior: Dictionary = {}
var _house: Node3D
var _floor_y: float = 0.0


func _ready() -> void:
	build()


## Reads the landmark spec and assembles the shelter. Safe to call once; the house is built off-tree.
func build() -> void:
	if _house != null:
		return
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(SPEC_PATH))
	if not (doc is Dictionary) or not (doc as Dictionary).has("interior"):
		push_error("KeyWest727Shelter: %s has no interior plan" % SPEC_PATH)
		return
	interior = doc["interior"]
	var origin: Array = doc["origin_local"]
	position = Vector3(float(origin[0]), float(origin[1]), float(origin[2]))
	_floor_y = float(interior["floor_y"])
	_house = Node3D.new()
	_house.name = "House"
	_house.basis = Basis(Vector3.UP, float(interior["plan_yaw_rad"]))
	var template: Node = TEMPLATE.instantiate()
	var hut: Node3D = template.get_node(^"ShelterHouse/House")
	for node_name: String in ["HouseDoor", "ShelterZone", "ToolBench", "SupplyBench"]:
		var node: Node = hut.get_node(NodePath(node_name))
		_clear_owner(node, template)
		hut.remove_child(node)
		_house.add_child(node)
	template.free()
	var zone: ThermalZone = _house.get_node(^"ShelterZone") as ThermalZone
	var window_proto: Node3D = zone.get_node(^"FrontWindow1").duplicate() as Node3D
	_remap_node_refs(zone.get_node(^"FrontWindow1"), window_proto)
	_place_door(zone)
	_place_zone(zone, true)
	var clinic: ThermalZone = _clinic_zone(zone)
	_place_windows(zone, clinic, window_proto)
	window_proto.free()
	_place_furniture()
	_add_stove_pipe(float(doc["elements"]["roof_top_navd88_m"]["above_ground_m"]))
	StylizedEnvironmentMaterial.apply_to_tree(_house)
	ShelterCabinet.add_cabinet_fade_volume(_house)
	add_child(_house)
	_add_spawn()


## Lays the First Exit supplies on their interior sockets ({name: {uv, h, yaw_deg}}, h above the floor).
## Pickup ids, counts and world_ids are the template's; only the place changes.
func place_supplies(supplies: Array[ItemPickup], sockets: Dictionary) -> void:
	for pickup: ItemPickup in supplies:
		var socket: Dictionary = sockets[String(pickup.name)]
		var yaw: Basis = Basis(Vector3.UP, deg_to_rad(float(socket.get("yaw_deg", 0.0))))
		pickup.transform = Transform3D(yaw, plan_point(socket["uv"], _floor_y + float(socket["h"])))
		pickup.set_meta("reconstruction_class", "game_authored_override")
		pickup.set_meta("site", "727_%s" % socket["room"])
		_house.add_child(pickup)


## Plan point (u, v) at height y, in House space.
func plan_point(uv: Array, y: float) -> Vector3:
	return Vector3(float(uv[0]), y, float(uv[1]))


## Basis turning local +Z towards the plan direction out.
func _facing(out: Array) -> Basis:
	return Basis(Vector3.UP, atan2(float(out[0]), float(out[1])))


func _opening(opening_name: String) -> Dictionary:
	for o: Dictionary in interior["openings"]:
		if o["name"] == opening_name:
			return o
	return {}


func _place_door(zone: ThermalZone) -> void:
	var o: Dictionary = _opening("MainDoor")
	var door: HingedDoor = _house.get_node(^"HouseDoor") as HingedDoor
	door.transform = Transform3D(_facing(o["outward_uv"]), plan_point(o["centre_uv"], _floor_y + float(o["y1"] - o["y0"]) * 0.5))
	door.opening_size = Vector2(float(o["width_m"]), float(o["y1"]) - float(o["y0"]))
	door.wall_thickness_m = float(interior["wall_thickness_m"])
	var breach: Node3D = zone.get_node(^"Door") as Node3D
	breach.transform = (Transform3D(Basis(), Vector3(0.0, _zone_y(), 0.0)).affine_inverse()
		* door.transform * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO))


func _zone_y() -> float:
	return _floor_y + ZONE_ABOVE_FLOOR


## Replaces the hut's single box with one box per room of the zone (heated or not).
func _place_zone(zone: ThermalZone, heated: bool) -> void:
	zone.transform = Transform3D(Basis(), Vector3(0.0, _zone_y(), 0.0))
	for child: Node in zone.get_children():
		if child is CollisionShape3D:
			zone.remove_child(child)
			child.free()
	for room: Dictionary in interior["rooms"]:
		if bool(room["heated"]) != heated:
			continue
		var r: Array = room["rect_uv"]
		var box: BoxShape3D = BoxShape3D.new()
		box.size = Vector3(absf(float(r[2]) - float(r[0])), ZONE_BOX_HEIGHT, absf(float(r[3]) - float(r[1])))
		var shape: CollisionShape3D = CollisionShape3D.new()
		shape.name = "Room_" + String(room["id"])
		shape.shape = box
		shape.position = Vector3((float(r[0]) + float(r[2])) * 0.5, ZONE_BOX_HEIGHT * 0.5 - ZONE_ABOVE_FLOOR - 0.1, (float(r[1]) + float(r[3])) * 0.5)
		zone.add_child(shape)


## Unheated clinic rooms: still indoors (sheltered from wind), no stove, lower priority.
func _clinic_zone(shelter: ThermalZone) -> ThermalZone:
	var clinic: ThermalZone = ThermalZone.new()
	clinic.name = "ClinicZone"
	clinic.is_interior = true
	clinic.temperature_offset_c = CLINIC_OFFSET_C
	clinic.wind_exposure = CLINIC_WIND_EXPOSURE
	clinic.zone_priority = shelter.zone_priority - 1
	clinic.collision_layer = shelter.collision_layer
	clinic.collision_mask = shelter.collision_mask
	_house.add_child(clinic)
	_place_zone(clinic, false)
	return clinic


## Heated-room windows reuse the hut's four breaches; every other window gets a copy.
func _place_windows(zone: ThermalZone, clinic: ThermalZone, proto: Node3D) -> void:
	var heated: Dictionary = {}
	for room: Dictionary in interior["rooms"]:
		heated[room["id"]] = bool(room["heated"])
	var hut_index: int = 0
	for o: Dictionary in interior["openings"]:
		if o["kind"] != "window":
			continue
		var window: Node3D
		if heated.get(o["room"], false) and hut_index < HUT_WINDOWS.size():
			window = zone.get_node(NodePath(HUT_WINDOWS[hut_index])) as Node3D
			hut_index += 1
		else:
			window = proto.duplicate() as Node3D
			_remap_node_refs(proto, window)
			(window as ShelterBreach).severity = CLINIC_WINDOW_SEVERITY
			clinic.add_child(window)
		window.name = String(o["name"])
		window.transform = Transform3D(_facing(o["outward_uv"]) * Basis(Vector3.UP, PI),
			plan_point(o["centre_uv"], (float(o["y0"]) + float(o["y1"])) * 0.5 - _zone_y()))
	for i: int in range(hut_index, HUT_WINDOWS.size()):
		var spare: Node = zone.get_node_or_null(NodePath(HUT_WINDOWS[i]))
		if spare != null:
			zone.remove_child(spare)
			spare.free()


func _place_furniture() -> void:
	for item: Dictionary in interior["furniture"]:
		var yaw: Basis = Basis(Vector3.UP, deg_to_rad(float(item["yaw_deg"])))
		var kind: String = item["kind"]
		if HUT_KINDS.has(kind):
			var node: Node3D = _house.get_node(NodePath(HUT_KINDS[kind])) as Node3D
			var in_zone: bool = String(HUT_KINDS[kind]).begins_with("ShelterZone/")
			## Hut furniture keeps its height above the hut floor; only plan position and yaw move.
			var y: float = node.position.y if in_zone else _floor_y
			node.transform = Transform3D(yaw * node.basis, plan_point(item["uv"], y))
			continue
		var size: Array = item["size"]
		var extents: Vector3 = Vector3(float(size[0]), float(size[1]), float(size[2]))
		var body: StaticBody3D = StaticBody3D.new()
		body.name = String(item["node"])
		body.transform = Transform3D(yaw, plan_point(item["uv"], _floor_y + extents.y * 0.5))
		body.set_meta("reconstruction_class", "game_invented")
		var mesh: MeshInstance3D = MeshInstance3D.new()
		var box_mesh: BoxMesh = BoxMesh.new()
		box_mesh.size = extents
		box_mesh.material = StylizedEnvironmentMaterial.make_static(BOX_COLOURS.get(kind, Color(0.6, 0.6, 0.6)), 0.85)
		mesh.mesh = box_mesh
		body.add_child(mesh)
		var shape: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = extents
		shape.shape = box
		body.add_child(shape)
		_house.add_child(body)


func _add_stove_pipe(roof_top: float) -> void:
	var stove: Node3D = _house.get_node(^"ShelterZone/Stove") as Node3D
	## The hut stove brings its own flue up to the ceiling; this one carries on through the roof.
	var base: float = float(interior["ceiling_y"])
	var top: float = roof_top + PIPE_ABOVE_ROOF_M
	var pipe: MeshInstance3D = MeshInstance3D.new()
	pipe.name = "StovePipe"
	var cylinder: CylinderMesh = CylinderMesh.new()
	cylinder.top_radius = 0.12
	cylinder.bottom_radius = 0.12
	cylinder.height = top - base
	cylinder.material = StylizedEnvironmentMaterial.make_static(Color(0.18, 0.17, 0.16), 0.6)
	pipe.mesh = cylinder
	var at: Vector3 = (_house.get_node(^"ShelterZone") as Node3D).transform * stove.position
	pipe.position = Vector3(at.x, (base + top) * 0.5, at.z)
	_house.add_child(pipe)


## ShelterSpawnPoint: in front of the entry ramp, facing the door (World.spawn_at_shelter).
func _add_spawn() -> void:
	var ramp: Dictionary = interior["entry_ramp"]
	var o: Dictionary = _opening("MainDoor")
	var out: Vector2 = Vector2(float(o["outward_uv"][0]), float(o["outward_uv"][1]))
	var foot: Vector2 = Vector2(float(ramp["from_uv"][0]), float(ramp["from_uv"][1])) + out * SPAWN_BEFORE_RAMP_M
	var marker: Marker3D = Marker3D.new()
	marker.name = "ShelterSpawnPoint"
	marker.transform = _house.transform * Transform3D(_facing(o["outward_uv"]),
		Vector3(foot.x, float(ramp["foot_y_navd88"]) - position.y + 0.15, foot.y))
	add_child(marker)


func _clear_owner(node: Node, template: Node) -> void:
	if node.owner == template:
		node.owner = null
	for child: Node in node.get_children():
		_clear_owner(child, template)


## Points exported Node references of copy at its own nodes where the source pointed inside source.
func _remap_node_refs(source: Node, copy: Node) -> void:
	for node: Node in [copy] + copy.find_children("*", "", true, false):
		var original: Node = source.get_node_or_null(copy.get_path_to(node)) if node != copy else source
		if original == null:
			continue
		for prop: Dictionary in original.get_property_list():
			var value: Variant = original.get(prop["name"]) if prop["type"] == TYPE_OBJECT else null
			if value is Node and (value == source or source.is_ancestor_of(value)):
				node.set(prop["name"], copy.get_node_or_null(source.get_path_to(value)))
