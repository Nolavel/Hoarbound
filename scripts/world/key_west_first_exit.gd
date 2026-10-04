class_name KeyWestFirstExit
extends Node3D

const FIRST_EXIT_TEMPLATE: PackedScene = preload("res://scenes/world/first_exit/first_exit_blockout.tscn")
const STREAMING_SCRIPT: GDScript = preload("res://core/world/streaming_system.gd")
const CITY_SCRIPT: GDScript = preload("res://scripts/systems/world/city/chunked_city_massing.gd")
const FROZEN_SEA_SHADER: Shader = preload("res://shaders/environment/ice/frozen_sea.gdshader")
const FADE_VOLUME_SCENE: PackedScene = preload("res://scenes/environment/visual_fx/FadeVolume.tscn")

const CITY_JSON: String = "res://data/world/key_west/city_preview.json"
const ENRICHMENT_JSON: String = "res://data/world/key_west/visual_enrichment.json"
const OCEAN_MASK: String = "res://data/world/key_west/ocean_connected_mask.png"
const HEIGHT_META: String = "res://world/terrain/key_west_preview_2m_la8.json"

const BUNKER_XZ := Vector2(-3452.88, 2273.84)
## A vacant Fort Street lot: no OSM building or road inside the fenced yard,
## chosen from the city data; the porch faces the street.
const SHELTER_XZ := Vector2(-3579.85, 1574.51)
const SHELTER_YAW_DEG: float = 126.76
## Henry starts this far in front of the bottom stair, facing the door.
const SPAWN_BEFORE_STAIRS_M: float = 2.5
const ROUTE_PICKUP_SCALE: float = 0.35
const SHELTER_EXACT_RADIUS_M: float = 38.0

var _world: Node3D
var _terrain: IslandTerrain
var _city: ChunkedCityMassing
var _prepared: bool = false
var _source_shelter: Vector3 = Vector3.ZERO
var _target_shelter: Vector3 = Vector3.ZERO
var _target_bunker: Vector3 = Vector3.ZERO
var _porch_spawn: Vector3 = Vector3.ZERO


func prepare_world_content(world: Node3D) -> void:
	if _prepared:
		return
	_prepared = true
	_world = world
	_terrain = world.get_node_or_null("IslandTerrain") as IslandTerrain
	if _terrain == null or _terrain.heightmap == null:
		push_error("KeyWestFirstExit: Key West terrain is not loaded")
		return
	_hide_graciosa_sea()
	_build_masked_ice()
	_transplant_first_exit()


func on_world_ready(context: WorldContext) -> void:
	if _terrain == null:
		_terrain = context.world.get_node_or_null("IslandTerrain") as IslandTerrain
	if _terrain == null or not FileAccess.file_exists(CITY_JSON):
		push_warning("KeyWestFirstExit: city preview is not built; terrain/First Exit still run")
		return
	if not FileAccess.file_exists(ENRICHMENT_JSON):
		push_warning("KeyWestFirstExit: visual enrichment is not built; city streaming is skipped")
		return
	_city = CITY_SCRIPT.new() as ChunkedCityMassing
	_city.name = "KeyWestCity"
	context.stream_container.add_child(_city)
	if not _city.configure(_terrain, CITY_JSON, ENRICHMENT_JSON):
		push_error("KeyWestFirstExit: failed to configure chunked city")
		_city.queue_free()
		_city = null
		return
	## Only buildings the house itself stands on give way; the lot is chosen empty.
	var house_outline: PackedVector2Array = shelter_snow_outline()
	_city.exclude_buildings_overlapping(house_outline)
	_city.register_snow_obstacle(&"first_exit_shelter", house_outline)
	var streaming := context.get_system(STREAMING_SCRIPT) as StreamingSystem
	if streaming == null:
		push_error("KeyWestFirstExit: shared StreamingSystem is missing")
		return
	var registered: int = streaming.register_runtime_source(_city)
	if registered != 148:
		push_warning("KeyWestFirstExit: expected 148 city chunks, registered %d" % registered)


func get_bunker_xz() -> Vector2:
	return BUNKER_XZ


static func shelter_snow_outline() -> PackedVector2Array:
	var outline := PackedVector2Array()
	for corner: Vector2 in [Vector2(-4.5, -5.5), Vector2(4.5, -5.5), Vector2(4.5, 10.5), Vector2(-4.5, 10.5)]:
		outline.append(SHELTER_XZ + corner.rotated(-deg_to_rad(SHELTER_YAW_DEG)))
	return outline


func get_shelter_xz() -> Vector2:
	return SHELTER_XZ


func get_route_distance_m() -> float:
	return BUNKER_XZ.distance_to(SHELTER_XZ)


func _transplant_first_exit() -> void:
	var template := FIRST_EXIT_TEMPLATE.instantiate() as Node3D
	if template == null:
		push_error("KeyWestFirstExit: First Exit template failed to instantiate")
		return
	var shelter := template.get_node_or_null(^"ShelterHouse") as Node3D
	var house := template.get_node_or_null(^"ShelterHouse/House") as Node3D
	var bunker := template.get_node_or_null(^"BunkerPortal") as Node3D
	if shelter == null or house == null or bunker == null:
		push_error("KeyWestFirstExit: reusable shelter/bunker anchors are missing")
		template.free()
		return
	_source_shelter = shelter.transform * house.position
	var shelter_target_yaw: float = deg_to_rad(SHELTER_YAW_DEG)
	## Seat the house so the ground at the stair foot meets the bottom stair:
	## one normal riser up onto the porch, never a jump.
	var stairs: AABB = _local_aabb(house.get_node_or_null(^"EntrySteps"), house)
	var foot_local := Vector3(stairs.get_center().x, 0.0, stairs.end.z + 0.4)
	var foot: Vector3 = Vector3(SHELTER_XZ.x, 0.0, SHELTER_XZ.y) + foot_local.rotated(Vector3.UP, shelter_target_yaw)
	var foot_ground: float = maxf(_terrain.get_height(foot.x, foot.z), 0.0)
	_target_shelter = Vector3(SHELTER_XZ.x, foot_ground - stairs.position.y, SHELTER_XZ.y)
	var shelter_delta_yaw: float = shelter_target_yaw - shelter.rotation.y
	var house_offset: Vector3 = _source_shelter - shelter.position
	house_offset = house_offset.rotated(Vector3.UP, shelter_delta_yaw)
	_clear_template_owner(shelter, template)
	template.remove_child(shelter)
	add_child(shelter)
	shelter.rotation.y = shelter_target_yaw
	shelter.position = _target_shelter - house_offset
	_add_plinth(house)
	_add_stair_ramp(house, stairs)
	## Convert opaque shelter materials; transparent/unshaded specials and the
	## player/VFX hierarchy keep their own paths.
	StylizedEnvironmentMaterial.apply_to_tree(house)
	_add_cabinet_fade_volume(house)
	_porch_spawn = foot + (foot - Vector3(SHELTER_XZ.x, 0.0, SHELTER_XZ.y)).normalized() * SPAWN_BEFORE_STAIRS_M
	_porch_spawn.y = maxf(_terrain.get_height(_porch_spawn.x, _porch_spawn.z), 0.0) + 0.15
	var bunker_ground: float = maxf(_terrain.get_height(BUNKER_XZ.x, BUNKER_XZ.y), 0.0)
	_target_bunker = Vector3(BUNKER_XZ.x, bunker_ground, BUNKER_XZ.y)
	var route_dir: Vector2 = (SHELTER_XZ - BUNKER_XZ).normalized()
	var bunker_target_yaw: float = atan2(route_dir.x, route_dir.y)
	var bunker_source_anchor: Vector3 = bunker.position
	var bunker_delta_yaw: float = bunker_target_yaw - bunker.rotation.y
	var bunker_names: Array[StringName] = [&"BunkerPortal", &"BunkerVent", &"BedrollBunker", &"RoadFlareBunker"]
	var direct_children: Array[Node] = template.get_children()
	for child: Node in direct_children:
		if not child is Node3D:
			continue
		var node := child as Node3D
		if bunker_names.has(StringName(node.name)):
			_move_from_anchor(node, bunker_source_anchor, _target_bunker, bunker_delta_yaw, 1.0)
			_clear_template_owner(node, template)
			template.remove_child(node)
			add_child(node)
			continue
		if child is ItemPickup:
			var flat_distance: float = Vector2(node.position.x - _source_shelter.x, node.position.z - _source_shelter.z).length()
			var scale: float = 1.0 if flat_distance <= SHELTER_EXACT_RADIUS_M else ROUTE_PICKUP_SCALE
			_move_from_anchor(node, _source_shelter, _target_shelter, shelter_delta_yaw, scale)
			_snap_pickup_to_ground(node)
			_clear_template_owner(node, template)
			template.remove_child(node)
			add_child(node)
	var shelter_spawn := template.get_node_or_null(^"SpawnPoint") as Marker3D
	if shelter_spawn != null:
		## Shelter starts also begin in front of the porch, facing the door.
		shelter_spawn.position = _porch_spawn
		shelter_spawn.rotation = Vector3(0.0, shelter_target_yaw, 0.0)
		shelter_spawn.name = "ShelterSpawnPoint"
		_clear_template_owner(shelter_spawn, template)
		template.remove_child(shelter_spawn)
		add_child(shelter_spawn)
	_build_bunker_vestibule(bunker_target_yaw)
	_build_spawn_marker(route_dir)
	template.free()


## Adds the reusable Fade Volume to the hollow shelter cabinet. The shader's
## signed local-X contract is intentional: -X stays transparent at the opening,
## +X darkens toward the back wall. The same setup is suitable for cabinets,
## drawers/crates and other hollow props when their carrier box matches the cavity.
func _add_cabinet_fade_volume(house: Node3D) -> void:
	var cabinet := house.find_child("Cabinet", true, false) as Node3D
	if cabinet == null:
		push_warning("KeyWestFirstExit: shelter Cabinet not found for FadeVolume")
		return
	var volume := FADE_VOLUME_SCENE.instantiate() as MeshInstance3D
	if volume == null:
		push_warning("KeyWestFirstExit: FadeVolume failed to instantiate")
		return
	volume.name = "CabinetFadeVolume"
	## Cabinet local +Z is its opening. +90° maps volume -X to the opening and
	## +X to the back wall, matching the original Fade Volume reference.
	volume.position = Vector3(0.0, 0.45, -0.111)
	volume.rotation.y = PI * 0.5
	var source_box := volume.mesh as BoxMesh
	if source_box != null and source_box.material is ShaderMaterial:
		var material := (source_box.material as ShaderMaterial).duplicate() as ShaderMaterial
		var physical_box := BoxMesh.new()
		physical_box.size = Vector3(0.60, 0.78, 0.72)
		physical_box.material = material
		volume.mesh = physical_box
		volume.scale = Vector3.ONE
		material.set_shader_parameter(&"x_len", 0.60)
		material.set_shader_parameter(&"y_len", 0.78)
		material.set_shader_parameter(&"z_len", 0.72)
		material.set_shader_parameter(&"exponent", 1.0)
		material.set_shader_parameter(&"axis_sign", 1.0)
		material.set_shader_parameter(&"fade_color", Color(0.025, 0.035, 0.055, 0.58))
		material.set_shader_parameter(&"corner_radius", 0.07)
		material.set_shader_parameter(&"edge_softness", 0.025)
		volume.material_override = material
	cabinet.add_child(volume)
	_add_cabinet_set_dressing(cabinet)


## Static level-art silhouettes only: no focus prompt, pickup area or inventory
## state. They make the cabinet read as a used hollow object rather than a black box.
func _add_cabinet_set_dressing(cabinet: Node3D) -> void:
	var stew := SurvivalItemVisual.make(&"tinned_stew")
	stew.name = "CabinetProp_StewTin"
	stew.position = Vector3(-0.20, 0.075, -0.02)
	stew.rotation.y = deg_to_rad(-12.0)
	cabinet.add_child(stew)

	var pineapple := SurvivalItemVisual.make(&"tinned_pineapple")
	pineapple.name = "CabinetProp_PineappleTin"
	pineapple.position = Vector3(0.16, 0.075, -0.04)
	pineapple.rotation.y = deg_to_rad(16.0)
	cabinet.add_child(pineapple)

	var mug := SurvivalItemVisual.make(&"mug")
	mug.name = "CabinetProp_Mug"
	mug.position = Vector3(0.10, 0.475, -0.02)
	mug.rotation.y = deg_to_rad(24.0)
	cabinet.add_child(mug)


func _clear_template_owner(node: Node, template: Node) -> void:
	if node.owner == template:
		node.owner = null
	for child: Node in node.get_children():
		_clear_template_owner(child, template)


func _move_from_anchor(node: Node3D, source_anchor: Vector3, target_anchor: Vector3, yaw_delta: float, horizontal_scale: float) -> void:
	var rel: Vector3 = node.position - source_anchor
	rel.x *= horizontal_scale
	rel.z *= horizontal_scale
	rel = rel.rotated(Vector3.UP, yaw_delta)
	node.position = target_anchor + rel
	node.rotation.y += yaw_delta


func _snap_pickup_to_ground(node: Node3D) -> void:
	var relative_height: float = node.position.y - _target_shelter.y
	if absf(relative_height) < 1.6:
		var ground: float = maxf(_terrain.get_height(node.position.x, node.position.z), 0.0)
		node.position.y = ground + maxf(relative_height, 0.35)


func _build_spawn_marker(route_dir: Vector2) -> void:
	var route_yaw: float = atan2(route_dir.x, route_dir.y)
	var front := Vector3(route_dir.x, 0.0, route_dir.y)
	var marker := Marker3D.new()
	marker.name = "SpawnPoint"
	marker.position = _target_bunker + front * 5.6 + Vector3.UP * 0.15
	marker.rotation.y = route_yaw + PI
	add_child(marker)


func get_porch_spawn() -> Vector3:
	return _porch_spawn


## Bounds of a node's meshes in `frame`'s space, walking local transforms, so it
## works on a template that is not in the tree yet.
func _local_aabb(node: Node, frame: Node3D) -> AABB:
	var result := AABB()
	var first: bool = true
	if node == null:
		return result
	var stack: Array = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		stack.append_array(current.get_children())
		if not current is VisualInstance3D:
			continue
		var to_frame := Transform3D.IDENTITY
		var walker: Node = current
		while walker != null and walker != frame:
			if walker is Node3D:
				to_frame = (walker as Node3D).transform * to_frame
			walker = walker.get_parent()
		var box: AABB = to_frame * (current as VisualInstance3D).get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


## A dark foundation under the floor down to the lowest ground beneath it, so the
## house never floats where the lot falls away.
func _add_plinth(house: Node3D) -> void:
	var floor_box: AABB = AABB(Vector3(-4.0, 0.7, -5.0), Vector3(8.0, 0.2, 13.0))
	var lowest: float = INF
	for corner: Vector2 in [Vector2(-4, -5), Vector2(4, -5), Vector2(4, 8), Vector2(-4, 8), Vector2(0, 1.5)]:
		var world_xz: Vector3 = Vector3(SHELTER_XZ.x, 0.0, SHELTER_XZ.y) + Vector3(corner.x, 0.0, corner.y).rotated(Vector3.UP, deg_to_rad(SHELTER_YAW_DEG))
		lowest = minf(lowest, maxf(_terrain.get_height(world_xz.x, world_xz.z), 0.0))
	var top: float = floor_box.position.y
	var bottom: float = lowest - _target_shelter.y - 0.3
	if bottom >= top:
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3(floor_box.size.x - 0.2, top - bottom, floor_box.size.z - 0.2)
	var material := StylizedEnvironmentMaterial.make(Color(0.16, 0.15, 0.14), 0.95)
	mesh.material = material
	var plinth := MeshInstance3D.new()
	plinth.name = "Plinth"
	plinth.mesh = mesh
	plinth.position = Vector3(floor_box.get_center().x, (top + bottom) * 0.5, floor_box.get_center().z)
	house.add_child(plinth)


func _build_bunker_vestibule(yaw: float) -> void:
	var chamber := Node3D.new()
	chamber.name = "WhiteheadBunkerVestibule"
	chamber.position = _target_bunker
	chamber.rotation.y = yaw
	add_child(chamber)
	var concrete := StylizedEnvironmentMaterial.make(Color(0.19, 0.21, 0.22), 0.92)
	var dark := StylizedEnvironmentMaterial.make(Color(0.055, 0.06, 0.065), 0.58, false, false, 0.55)
	_box(chamber, Vector3(-3.05, 1.35, 6.6), Vector3(0.28, 2.7, 6.2), concrete)
	_box(chamber, Vector3(3.05, 1.35, 6.6), Vector3(0.28, 2.7, 6.2), concrete)
	_box(chamber, Vector3(0.0, 2.72, 6.6), Vector3(6.35, 0.28, 6.2), concrete)
	var leaf := _box(chamber, Vector3(2.78, 1.35, 9.55), Vector3(0.18, 2.55, 2.5), dark)
	leaf.rotation.y = deg_to_rad(82.0)


func _box(parent: Node3D, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.position = at
	parent.add_child(visual)
	var body := StaticBody3D.new()
	body.position = at
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	return visual


func _hide_graciosa_sea() -> void:
	var legacy_sea := _world.get_node_or_null(^"MeshInstance3D") as MeshInstance3D
	if legacy_sea != null:
		legacy_sea.visible = false


func _build_masked_ice() -> void:
	if not FileAccess.file_exists(OCEAN_MASK) or not FileAccess.file_exists(HEIGHT_META):
		push_warning("KeyWestFirstExit: ocean mask is not built")
		return
	var mask_image: Image = Image.load_from_file(OCEAN_MASK)
	if mask_image == null or mask_image.is_empty():
		return
	var meta_variant: Variant = JSON.parse_string(FileAccess.get_file_as_string(HEIGHT_META))
	if not meta_variant is Dictionary:
		return
	var meta := meta_variant as Dictionary
	var mask_texture := ImageTexture.create_from_image(mask_image)
	var width_m: float = float(int(meta["width"]) - 1) * float(meta["m_per_px"])
	var depth_m: float = float(int(meta["height"]) - 1) * float(meta["m_per_px"])
	var origin := Vector2(float(meta["origin_x"]), float(meta["origin_z"]))
	var material := ShaderMaterial.new()
	material.shader = FROZEN_SEA_SHADER
	material.set_shader_parameter("ocean_mask", mask_texture)
	material.set_shader_parameter("world_origin", origin)
	material.set_shader_parameter("world_size", Vector2(width_m, depth_m))
	var plane := PlaneMesh.new()
	plane.size = Vector2(width_m, depth_m)
	plane.material = material
	var ice := MeshInstance3D.new()
	ice.name = "FrozenSea"
	ice.mesh = plane
	ice.position = Vector3(origin.x + width_m * 0.5, -0.04, origin.y + depth_m * 0.5)
	add_child(ice)


## An invisible slope over the entry steps: Henry walks up them like stairs,
## since his body has no step-up of its own.
func _add_stair_ramp(house: Node3D, stairs: AABB) -> void:
	if stairs.size == Vector3.ZERO:
		return
	## Starting 1.2 m out keeps every stair nosing under the slope (~10°).
	var low := Vector3(stairs.get_center().x, stairs.position.y, stairs.end.z + 1.2)
	var high := Vector3(stairs.get_center().x, stairs.end.y, stairs.position.z)
	var run: Vector3 = high - low
	var shape := BoxShape3D.new()
	shape.size = Vector3(stairs.size.x, 0.06, run.length())
	var collision := CollisionShape3D.new()
	collision.shape = shape
	var body := StaticBody3D.new()
	body.name = "StairRamp"
	## Steps are swept: no snow lies on them to bury the climb.
	body.add_to_group(SnowShell.SWEPT_GROUP)
	body.add_child(collision)
	## The box's -Z runs from the stair foot up to the veranda.
	var forward: Vector3 = -run.normalized()
	body.transform = Transform3D(Basis.looking_at(-forward, Vector3.UP), (low + high) * 0.5 - Vector3.UP * 0.03)
	house.add_child(body)
