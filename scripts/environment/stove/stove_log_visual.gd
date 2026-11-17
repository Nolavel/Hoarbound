extends Node3D

## Presentation only: normalized study geometry fitted to the real 0.54 m stove log.
## It never owns fuel, temperature, capacity, ignition permission or inventory.
## The authored log: Body (wood, three flames, smoke) lives in stove_log.tscn.
const SCENE_PATH: String = "res://scenes/environment/stove/stove_log.tscn"
const WOOD := preload("res://shaders/environment/stove/log_wood.gdshader")

var burn_progress: float = 0.0
var _materials: Array[ShaderMaterial] = []
var _animation_seconds: float = 0.0
var _flame_nodes: Array[MeshInstance3D] = []

@onready var _body: Node3D = $Body


## A log built from the authored scene.
static func instantiate() -> Node3D:
	return (load(SCENE_PATH) as PackedScene).instantiate() as Node3D


func _ready() -> void:
	for child: Node in _body.get_children():
		var material := (child as GeometryInstance3D).material_override as ShaderMaterial
		if material != null:
			_materials.append(material)
		if child.name.begins_with("Flame"):
			_flame_nodes.append(child as MeshInstance3D)
	set_stage(0.0)

func set_stage(progress: float) -> void:
	burn_progress=clampf(progress,0.0,1.0)
	for m: ShaderMaterial in _materials:
		m.set_shader_parameter("burn_progress",burn_progress)

func _process(delta: float) -> void:
	_animation_seconds+=delta
	for m: ShaderMaterial in _materials:
		if m.shader != WOOD:
			m.set_shader_parameter("animation_seconds",_animation_seconds)

func set_ignition_source(world_point: Vector3) -> void:
	if _body == null:
		return
	var local: Vector3 = _body.to_local(world_point)+Vector3(0,0.48,0)
	local.x = clampf(local.x,-1.45,1.45)
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter("ignition_source",local)
	for i: int in range(_flame_nodes.size()):
		var root_x: float = lerpf(local.x,-signf(local.x)*1.3,float(i)*0.4)
		_flame_nodes[i].position.x = root_x
		_flame_nodes[i].position.z = 0.35*signf(local.z)
		(_flame_nodes[i].material_override as ShaderMaterial).set_shader_parameter("root_z",_flame_nodes[i].position.z)
		(_flame_nodes[i].material_override as ShaderMaterial).set_shader_parameter("root_x",root_x)


func resting_height(rotation_value: Vector3, floor_y: float) -> float:
	var mesh_node := _body.get_node(^"Wood") as MeshInstance3D
	var vertices: PackedVector3Array = mesh_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var basis: Basis = Basis.from_euler(rotation_value)*_body.basis
	var bottom: float = INF
	for vertex: Vector3 in vertices:
		bottom = minf(bottom,(basis*vertex).y)
	return floor_y-bottom
