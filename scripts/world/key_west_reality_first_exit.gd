class_name KeyWestRealityFirstExit
extends Node3D
## First Exit gameplay on the Reality world: the template bunker set into the fort's courtyard
## face, and every template pickup at a site from first_exit_gameplay.json (game-authored).

const TEMPLATE: PackedScene = preload("res://scenes/world/first_exit/first_exit_blockout.tscn")
const SITES_PATH: String = "res://data/world/key_west/reality/overrides/first_exit_gameplay.json"
const BUNKER_NODES: Array[StringName] = [&"BunkerPortal", &"BunkerVent", &"BedrollBunker", &"RoadFlareBunker"]
## The template's earth cover behind the door; the measured fort mass stands in for it.
const BUNKER_COVER: NodePath = ^"MeshInstance3D5"
## Bunker-side items keep their template offset along the face but lie this far in front of it.
const BUNKER_ITEM_FRONT_M: float = 1.0
const RECON_META: String = "game_authored_override"

## The 727 shelter that takes the interior supplies.
@export var shelter: KeyWest727Shelter
## Spawn marker the World reads after content _ready.
@export var spawn_point: Marker3D

var sites: Dictionary = {}
var pickups: Array[ItemPickup] = []


func _ready() -> void:
	build()


## Reads the sites and moves the template's bunker and pickups. Safe to call once.
func build() -> void:
	if not sites.is_empty():
		return
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(SITES_PATH))
	if not doc is Dictionary:
		push_error("KeyWestRealityFirstExit: cannot read %s" % SITES_PATH)
		return
	sites = doc
	var template: Node = TEMPLATE.instantiate()
	var bunker: Dictionary = sites["bunker"]
	var yaw: float = float(bunker["yaw_rad"])
	var portal_xz: Vector2 = _xz(bunker["portal_xz"])
	var door_xz: Vector2 = _xz(bunker["door_xz"])
	var ground_y: float = float(bunker["ground_y"])
	var target: Vector3 = Vector3(portal_xz.x, ground_y, portal_xz.y)
	var source: Node3D = template.get_node(^"BunkerPortal") as Node3D
	var source_origin: Vector3 = source.position
	var source_yaw: float = source.rotation.y
	var door_local_z: float = portal_xz.distance_to(door_xz)
	for node_name: StringName in BUNKER_NODES:
		var node: Node3D = template.get_node(NodePath(node_name)) as Node3D
		var local: Vector3 = (node.position - source_origin).rotated(Vector3.UP, -source_yaw)
		_adopt(node, template)
		node.rotation.y += yaw - source_yaw
		if node_name == &"BunkerVent":
			var vent: Dictionary = sites["vent"]
			node.position = Vector3(_xz(vent["xz"]).x, float(vent["base_y"]), _xz(vent["xz"]).y)
		elif node is ItemPickup:
			local.z = maxf(local.z, door_local_z + BUNKER_ITEM_FRONT_M)
			node.position = target + local.rotated(Vector3.UP, yaw)
			pickups.append(node as ItemPickup)
		else:
			node.position = target
		node.set_meta("reconstruction_class", RECON_META)
	var cover: Node = get_node(^"BunkerPortal").get_node_or_null(BUNKER_COVER)
	if cover != null:
		cover.get_parent().remove_child(cover)
		cover.free()
	_place_pickups(template)
	template.free()
	_place_spawn(yaw)


func _place_pickups(template: Node) -> void:
	var route: Dictionary = sites["pickups"]
	var sockets: Dictionary = sites["shelter_sockets"]
	var interior: Array[ItemPickup] = []
	for child: Node in template.get_children():
		var pickup: ItemPickup = child as ItemPickup
		if pickup == null:
			continue
		var key: String = String(pickup.name)
		if route.has(key):
			var site: Dictionary = route[key]
			_adopt(pickup, template)
			pickup.position = Vector3(_xz(site["xz"]).x, float(site["y"]), _xz(site["xz"]).y)
			pickup.set_meta("reconstruction_class", RECON_META)
			pickup.set_meta("site", site["site"])
			pickups.append(pickup)
		elif sockets.has(key):
			_clear_owner(pickup, template)
			template.remove_child(pickup)
			interior.append(pickup)
		else:
			push_error("KeyWestRealityFirstExit: template pickup %s has no Reality site" % key)
	if shelter == null:
		push_error("KeyWestRealityFirstExit: no 727 shelter for %d interior supplies" % interior.size())
		for pickup: ItemPickup in interior:
			pickup.free()
		return
	shelter.build()
	shelter.place_supplies(interior, sockets)
	pickups.append_array(interior)


## Henry wakes past the wing walls, facing out of the door (player forward is -Z).
func _place_spawn(yaw: float) -> void:
	if spawn_point == null:
		push_error("KeyWestRealityFirstExit: spawn point is not set")
		return
	var spawn: Dictionary = sites["spawn"]
	spawn_point.position = Vector3(_xz(spawn["xz"]).x, float(spawn["y"]), _xz(spawn["xz"]).y)
	spawn_point.rotation = Vector3(0.0, yaw + PI, 0.0)


func _adopt(node: Node, template: Node) -> void:
	_clear_owner(node, template)
	template.remove_child(node)
	add_child(node)


func _clear_owner(node: Node, template: Node) -> void:
	if node.owner == template:
		node.owner = null
	for child: Node in node.get_children():
		_clear_owner(child, template)


static func _xz(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))
